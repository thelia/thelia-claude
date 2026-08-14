---
name: fresh-install-test
description: >
  Validates a fresh Thelia 3 install from an empty directory and empty database.
  Use after a version bump, a merge, or any change to bin/install, bin/test-prepare,
  bootstrap.php, or DatabaseSetup. Covers two scenarios: the thelia/thelia dev repo
  (with core/ as a path repository) and the thelia-project skeleton installed the way
  a new developer installs it, with composer create-project from the tagged releases.
---

# Skill: Fresh Install Test

Reusable validation protocol for a clean Thelia 3 installation. Run it after any upgrade, merge, or infrastructure change before tagging a release.

## When to use

- Before merging an upgrade branch (Symfony, API Platform, dependency bumps)
- After modifying `bin/install`, `bin/test-prepare`, `bootstrap.php`, or `DatabaseSetup`
- After extracting changes to `thelia-project`
- Before cutting an alpha, beta, or stable release

## Prerequisites

- DDEV installed and running
- SSH access to the GitHub repos under `thelia/*` for the dev-repo scenario
- **A GitHub token available to Composer** (see the trap below). Without it the install fails, and the error message points nowhere near the cause.
- The target workspace directory must be empty (the protocol deletes and recreates it)

Thelia 3 ships as tagged releases; there is no development branch to install from. Test 1 clones the development repository, whose live branch is `main`. Test 2 installs the published packages. The skeleton needs `--stability=beta` (or an explicit version), and a project's own `composer.json` needs `"minimum-stability": "beta"` with `"prefer-stable": true`.

Current tags: `3.0.0-beta3` for `thelia/thelia`, `thelia/core` and `thelia/setup`; `3.0.0-beta5` for `thelia/thelia-project`. Each template moves on its own track: Flexy `1.0.0-beta7`, default-twig back-office `1.0.0-beta7`, PDF `1.0.0-beta6`, legacy back and email `1.0.0-beta4`. The skeleton and the templates are versioned independently of the core, so do not expect the numbers to line up.

### Trap: a missing GitHub token fails the install far from its cause

Composer needs a GitHub token to reach `thelia/thelia-recipes`. Without one, Symfony Flex does not fail loudly: it falls back to auto-generated recipes, so none of Thelia's `config/packages/*.yaml` files are ever written. The install then dies much later on an unrelated-looking message:

```
You must either configure a "public_key" or a "secret_key"
```

Symptom and cause have nothing in common. Before debugging that message, check that `config/packages/` holds Thelia's own configuration files and that Composer is authenticated:

```bash
composer config --global --list | grep github-oauth   # or check auth.json / COMPOSER_AUTH
```

---

## Test 1: thelia/thelia (dev repo with core/ as a path repository)

```bash
# Set WORKSPACE to the directory that will contain the cloned project.
# Example: WORKSPACE="$(pwd)"  or  WORKSPACE=/path/to/your/workspace
WORKSPACE=<path-to-your-workspace>

PROJECT=thelia-3
BRANCH=main  # the live branch; replace with a tag to test a release
             # `twig` is a frozen legacy branch, do not test against it

# 1. Full cleanup
ddev stop --unlist $PROJECT 2>/dev/null
ddev delete -Oy $PROJECT 2>/dev/null
rm -rf "$WORKSPACE/$PROJECT"

# 2. Fresh clone
cd "$WORKSPACE"
git clone -b $BRANCH git@github.com:thelia/thelia.git $PROJECT
cd $PROJECT

# 3. Configure DDEV
ddev config --project-name=$PROJECT --project-type=symfony --docroot=public \
  --php-version=8.3 --webserver-type=nginx-fpm --database=mariadb:10.11
ddev start

# 4. Install PHP dependencies
ddev exec composer install

# 5. Install Thelia with demo data and admin account
ddev exec php bin/install \
  --frontoffice_theme=flexy --backoffice_theme=default \
  --pdf_theme=default --email_theme=default \
  --with-demo --with-admin \
  --admin_login=thelia --admin_password=thelia \
  --admin_first_name=thelia --admin_last_name=thelia \
  --admin_email=thelia@example.com

# Expected output:
#   "Thelia installed successfully." on the last line
#   4x "Theme ready !"
#   "N module(s) post-activated." (count varies with installed modules)
#   "User thelia successfully created."
#   No "ERROR:" lines anywhere
#   The front-office assets built by bin/install itself (importmap:install, then tailwind:build)

# 6. Build the back-office theme (bin/install does NOT do this one)
ddev exec bash -c "cd templates/backOffice/default-twig && npm install && npm run build"

# 7. Verify the home page
curl -sk https://$PROJECT.ddev.site/ | wc -c
# Expected: more than 50000 bytes (full HTML page with demo products)

# 8. Verify the admin login page
curl -sk https://$PROJECT.ddev.site/admin/login | wc -c
# Expected: more than 1000 bytes

# 9. Verify the Symfony version
ddev exec php bin/console about | grep Version
# Expected: 7.4.x

# 10. Run the full test suite (uses a separate test DB, does not touch demo data)
ddev exec composer test
# Expected: all suites pass with no failures

# 11. Confirm the dev DB is untouched after tests
ddev exec bash -c "mysql -h db -u db -pdb db -e 'SELECT COUNT(*) FROM product'"
# Expected: the demo product count (verify against your demo dataset)

# 12. Check for new deprecations
ddev exec php bin/console debug:container --deprecations | head -3
# Expected: no new deprecations introduced by your change
```

**Success criteria:**

- [ ] Install completes with zero errors
- [ ] 4x "Theme ready !" in install output
- [ ] Front-office assets built by `bin/install`; back-office assets built manually
- [ ] Home page returns more than 50 KB with demo products and images
- [ ] Admin login page is accessible
- [ ] Symfony 7.4.x reported
- [ ] The full test suite passes
- [ ] Dev DB product count is unchanged after running tests
- [ ] No new deprecations compared to baseline

---

## Test 2: thelia/thelia-project (simulates a new developer install)

```bash
# Set WORKSPACE to the directory that will contain the project.
WORKSPACE=<path-to-your-workspace>

PROJECT=thelia-project-test

# 1. Full cleanup
ddev stop --unlist $PROJECT 2>/dev/null
ddev delete -Oy $PROJECT 2>/dev/null
rm -rf "$WORKSPACE/$PROJECT"

# 2. Create the project from the tagged release
cd "$WORKSPACE"
composer create-project --stability=beta thelia/thelia-project $PROJECT
# Equivalent, pinned: composer create-project thelia/thelia-project:3.0.0-beta5 $PROJECT
cd $PROJECT

# 3. Configure DDEV (MariaDB version can vary by host)
ddev config --project-name=$PROJECT --project-type=symfony --docroot=public \
  --php-version=8.3 --webserver-type=nginx-fpm --database=mariadb:11.8
ddev start

# 4. Install PHP dependencies inside the container
ddev exec composer install

# 5. Install Thelia with demo data and admin account
ddev exec php bin/install \
  --frontoffice_theme=flexy --backoffice_theme=default \
  --pdf_theme=default --email_theme=default \
  --with-demo --with-admin \
  --admin_login=thelia --admin_password=thelia \
  --admin_first_name=thelia --admin_last_name=thelia \
  --admin_email=thelia@example.com

# 6. Build the back-office theme (the front-office assets are already built by bin/install)
ddev exec bash -c "cd templates/backOffice/default-twig && npm install && npm run build"

# 7. Verify the home page
curl -sk https://$PROJECT.ddev.site/ | wc -c
# Expected: more than 50000 bytes

# 8. Verify the Symfony version
# bin/console on thelia-project routes through the Thelia wrapper and may silence stdout.
# Use this instead for a quick check:
ddev exec php -r 'require "vendor/autoload.php"; echo Symfony\Component\HttpKernel\Kernel::VERSION."\n";'
# Expected: 7.4.x
```

**Key points for thelia-project:**

- `bootstrap.php` must NOT load `vendor/autoload.php` (doing so disables the Symfony Runtime via its `require_once` guard).
- `public/index.php` must load `bootstrap.php` first, then `vendor/autoload_runtime.php`.
- `bin/console` passes through `vendor/thelia/core/Thelia`, not the standard Symfony pattern.
- Constraints in the generated `composer.json`: `^3.0.0-beta` for `thelia/core`, `^1.0.0-beta` for the templates, the module's current major for `thelia/*-module`, plus `"minimum-stability": "beta"` and `"prefer-stable": true`.

---

## Breaking changes to watch during upgrades

The most common problems encountered in modules:

1. `@Route` annotation must become `#[Route]` attribute (fatal in Symfony 7)
2. `ObjectNormalizer` is now `final` (fatal in Symfony 7)
3. `getSubscribedEvents()` missing `: array` return type (deprecation that becomes fatal in Symfony 8)
4. `execute()` on commands missing `: int` return type (fatal in Symfony 7)
5. `openapiContext` on operations must become `openapi: new Operation(...)` (fatal in API Platform 4)
6. `TaggedIterator` / `TaggedLocator` must become `AutowireIterator` / `AutowireLocator` (deprecated in Symfony 7.1, fatal in 8)
7. `keep_legacy_inflector` in `api_platform.yaml` must be removed (fatal in API Platform 4)
8. `ApiPlatformBundle` must be declared in `bundles.php` (removed by the Flex recipe swap)

---

## Front-office assets: automatic; back-office assets: manual

`bin/install` builds the front-office assets itself, running `importmap:install` then `tailwind:build` when those commands are available. There is nothing to run by hand for Flexy, and no `npm install` either: the theme uses AssetMapper and a Tailwind CLI binary, not Node.

The back-office theme is the exception. Its compiled `dist/` is gitignored, so it ships absent from the package and has to be built once after install:

```bash
ddev exec bash -c "cd templates/backOffice/default-twig && npm install && npm run build"
```

An admin that renders unstyled is this build missing, not a configuration problem.

## Known issues

**LiveComponents return 404:** a project whose `config/routes/ux_live_component.yaml` predates the current recipe is missing `ignore_thelia_view: true` on the `/_components` route. Without it, `Thelia\Core\EventListener\ViewListener` answers `kernel.view` with a themed view, which matches no front-office view, so every LiveComponent round-trip 404s. Flex never rewrites a file that already exists, so an upgraded project keeps the old one. Add the default by hand:

```yaml
live_component:
    resource: '@LiveComponentBundle/config/routes.php'
    prefix: '/_components'
    defaults:
        ignore_thelia_view: true
```

**Blank page on thelia-project:** if `bootstrap.php` loads `vendor/autoload.php`, the Symfony Runtime silently deactivates itself because of the `require_once` guard returning `true`. Fix: load only constants in `bootstrap.php`.

**Test suite targeting the wrong database:** `.env.test` must set `DATABASE_NAME=test`, not `db`. If tests are still hitting the dev database, delete `var/propel/test/` to flush the Propel DSN cache.

**`bin/console` produces no output on thelia-project:** the `Thelia` wrapper swallows stdout. Use `php -r 'require "vendor/autoload.php"; ...'` for one-off version checks.
