---
name: thelia3-project-migration
description: "Migrating a whole Thelia 2 shop to Thelia 3: moving a production database up (refused in-place update, 2.6 config keys, columns and NULLs that differ from a fresh install), modules on a migrated database, mail and PDF themes, settings an update leaves empty, cutover checks. Use with thelia3-module-migration when a live shop moves, not one module."
---

# Migrating a Thelia 2 shop to Thelia 3

A shop migration is a database migration plus a code migration. Port each module with `thelia3-module-migration`; this skill covers what only shows up on a real production database and on the day the shop moves. Tooling gotchas are in `thelia3-tooling`, Propel typing in `propel-thelia`.

## 1. The database cannot be updated in place

`Update::process()` refuses any database below `Update::MIN_UPDATABLE_VERSION` (`3.0.0-alpha1`): the update scripts jump from 2.5.5 to 3.0.0-alpha1, so a 2.6 database would be read as a 2.5.5 one. Moving from Thelia 2 is a guided migration that you write, and it always starts from a fresh import of the production dump, never from a database a previous attempt left half-way.

Path from a 2.6.x database:

1. Undo what 2.6.1 changed that the 3.x scripts do not expect: the `store_*` config keys suffixed by locale (`store_email_fr_FR`...). Save every original value in a table of your own, give the bare key the value of the default language, then remove the suffixed keys. Keep a suffixed value that differs from the bare key: a second storefront in another language reads it.
2. Leave image files per language alone: the core's 3.2 script reads the schema and handles both a 2.6 base (files already in the translations) and an older one.
3. Set `config.thelia_version` to `2.5.5`. It is the only legitimate manual write of that key: it declares the schema you just restored.
4. Replay the core's SQL and PHP update scripts in `version_compare()` order (`sort -V` puts `3.0.0.sql` before `3.0.0-alpha1.sql`). Read each script's exit code: the `SELECT @var := ...` lines go to stdout, errors only to stderr.

Read the scripts of the core version you install before writing a workaround: a defect already fixed in `setup/update/sql/` must not be fixed twice.

## 2. A migrated schema is not a fresh-install schema

The same code behaves differently on the two. Compare `information_schema.COLUMNS` (type, nullability, default) of the migrated database with a fresh install of the same core, table by table, and decide each difference:

- **Text where a fresh install has a decimal.** `order_product.promo_price` stays `VARCHAR` on a Thelia 2 database; `ROUND()` over a text value rounds as a float, one cent off between cart, order and invoice. The 3.3 update converts it and writes `last_text_promo_price_order_id`: orders up to that id keep the old computation so invoiced totals do not change. Never edit or drop that key, and count the orders below it before and after.
- **`NOT NULL` without a default where a fresh install is nullable** (or the reverse): an API `POST` that works on a demo shop fails on the migrated one (`cannot be null`, SQL error 1364). Test creation endpoints with an empty body on the migrated database.
- **A shop table with the same name as a table the core adds.** The core's update scripts create their tables with `CREATE TABLE IF NOT EXISTS`: on a name clash nothing happens, and the core model then reads columns that do not exist. After each core upgrade, grep the new scripts for `CREATE TABLE IF NOT EXISTS` and check every name against the shop's own tables.
- **Collations.** A migrated base keeps `utf8mb3`/`*_general_ci` tables while the connection speaks `utf8mb4_unicode_ci`: a join on `CAST(id AS CHAR)` fails with `Illegal mix of collations` or loses its index. Compare homogeneous types instead (`CAST(x AS UNSIGNED)`, or `CONCAT('', id)` against a text column). `thelia:database:convert-utf8mb4` converts the tables but reports the ones it leaves untouched.
- **Columns whose type surprises a query.** `rewriting_url.view_id` is a `VARCHAR`: `view_id = p.id` ignores the index and scans the table for each row, so compare strings. `product_sale_elements.quantity` is a `FLOAT` (displayed rounded to six digits): compare through `CAST(... AS DECIMAL)`. `ean_code` and `order_product.product_ref` have no index.

## 3. Modules on a migrated database

- Before `module:refresh`, set every `module` row that comes from Thelia 2 to `<Thelia 3 major>.0.0`. Otherwise the update replays the module's Thelia 2 scripts, some of which start with `DROP TABLE`. Side effect: Thelia 3 scripts numbered at or below that major are skipped too; play them explicitly when the module has one.
- Disable in SQL, before the first `bin/console`, every active module that has no Thelia 3 code on disk: the kernel loads every module active in the database and stops at the first missing class. The same happens when an upgrade makes Composer remove a package (a theme no longer requires a module): read `git diff composer.lock` for removals and deactivate before `composer install`. Once it is broken, `module:deactivate` cannot run; `UPDATE module SET activate = 0 WHERE code IN (...)` can.
- A module marked active by SQL never ran `preActivation()` / `postActivation()`: its tables, its `message` rows and the assets it copies under `public/` do not exist. Play its SQL as a migration step, publish its assets at every deployment rather than at activation, and expect the same on a test shop.
- Activate modules one at a time, counting every table before and after. Many Thelia 2 `postActivation()` start with `DROP TABLE IF EXISTS` behind an `is_initialized` flag that production never wrote. Never `module:schema:apply --all` or `module:post-activate-all` on a populated database.
- `template:set` activates the modules a theme requires and carries on when one of them fails to activate. Compare the modules required by each theme's `composer.json` with the active ones afterwards: Flexy without its SEO module answers 500 everywhere.
- Modules shipped with `<enabled-by-default>0</enabled-by-default>` register inactive: activate them in a migration step, not by hand.

## 4. Settings an update leaves empty, or switches on

- `image_formats`: a fresh install writes `webp`, the update script inserts it empty, so no `<source>` is rendered. Set it in the migration.
- The 3.3 update adds the `order_shipped` message and `order_shipped_email_enabled = 1`: customers start receiving a shipping e-mail the old shop never sent. Turn it off in the migration if the shop did not send one.
- `order_status_transition` (3.1): a status with no row is free, which keeps the old behavior. Once a status has rows, an order can only move to the listed targets (`OrderStatusTransitionGuard`), and a custom status nobody can reach is dead. When you seed the graph, seed it for every status, custom ones included.
- `active-mail-template` and `active-pdf-template` must name Twig themes. A Thelia 2 shop has Smarty ones, and the core has no Smarty: no order, account or password e-mail leaves and no invoice renders, with the error only in the logs.
- Message bodies and subjects stored in the database (`message_i18n`) are often Smarty (`{$order_ref}`, `{assign}`): rewrite them in Twig. A subject goes through `renderString()` with auto-escaping, so `l'article` becomes `l&#039;article` unless the template marks it safe. The subject sent is the stored one: `Message::buildMessage()` does not read the template's `<title>`.

## 5. Front, SEO and server

- The document root is `public/`. A server still on `web/` returns every page with status 200 and the right HTML but no stylesheet: check in a browser, not with `curl`.
- `thelia-project` ships a static `public/robots.txt`. The web server serves it before Thelia, so a module that answers `/robots.txt` per domain from the database is never reached. Delete the file when a module owns robots.
- Thelia 2 redirections (https, `www`, `index.php`) belong in one 301 to the canonical address. Behind a TLS proxy, Apache builds absolute redirects in http: read `X-Forwarded-Proto`, and declare the proxy in `TRUSTED_PROXIES` or Symfony treats every request as http.
- Compare the old and new sites URL by URL (status, redirect target, canonical, hreflang, robots meta, sitemap entries), per language and per domain. SEO regressions do not show in user journeys.

## 6. Before the cutover

- Production runs on tagged releases only. A project developed on `dev-main` keeps the list of tags it waits for and checks it before the cutover.
- Payment providers call back fixed paths: keep the same return paths in the new shop, or update them at the provider. Close the old shop's return paths before the final dump; replay from the provider's console the callbacks received during the window.
- Take an order fingerprint before and after the final import: `COUNT(*)`, `MAX(id)`, `MAX(updated_at)`, count per status.
- A rollback after opening must put the old shop's `order` `AUTO_INCREMENT` and the order and invoice counters (`order_sequence`, `invoice_ref`) above what the new shop reached.
- Copy the media folders (`local/media`, module folders under `public/`) before importing images; the SQL dump does not hold them.
- Stop the old shop's scheduled tasks before the final import and copy their definitions first: they are not in the repository, and running both sets sends every notification twice.

## Related skills

- `thelia3-module-migration`: porting each module.
- `thelia3-tooling`: caches, Propel models.
- `thelia3` § 0: update scripts on a dev branch.
- `propel-thelia`: native typing of the generated models.
- `fresh-install-test`: the fresh install to compare the migrated schema with.
