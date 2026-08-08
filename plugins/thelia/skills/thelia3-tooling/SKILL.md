---
name: thelia3-tooling
description: "Operational gotchas when developing and testing Thelia 3: the Thelia console versus bin/console, a stale PHPStan result cache on Propel classes, PHPUnit 11 failing on deprecated XML, JWT keys for the API test suite, and rebuilding a theme's compiled assets after composer update. Use when a Thelia command, the test suite, PHPStan, JWT auth, or a theme's assets behave in a way the code does not explain."
---

# Thelia 3 tooling

Operational traps that cost time when you do not know them. None of these is a code bug.

## Thelia console vs bin/console

Thelia's own commands run through the Thelia console, not the Symfony one.

- `php Thelia <command>` for Thelia commands: `cache:clear`, `module:install`, `module:activate`, `admin:create`, `template:set`, demo import.
- `bin/console <command>` only for Symfony-native commands: `lint:twig`, `debug:router`, `debug:container`.

`php Thelia cache:clear` clears more than the Symfony cache (it also handles the Propel and template caches), so prefer it when a stale cache is suspected.

## A stale PHPStan result cache on Propel classes

PHPStan caches results, and the cache can go stale on generated Propel `Base` classes, producing phantom errors on classes that are actually fine. Before treating such an error as real, clear the cache:

```bash
vendor/bin/phpstan clear-result-cache
```

## PHPUnit 11 fails on deprecated XML

A deprecated attribute in `phpunit.xml` (for example `cacheResultFile`, or the old `listeners` element) makes PHPUnit 11 exit with code 1 even when every test passes. Inside a `composer test` chain this looks like a test failure but is a configuration warning. Migrate the config: use `cacheDirectory`, and move listeners to `extensions` and bootstrap entries.

## JWT keys and the API test suite

If the dev and test environments share the same `config/jwt/` keypair but use different passphrases, the API test suite cannot decrypt the key and reports `bad decrypt`. The fix is to regenerate the keypair without a passphrase, so the unencrypted key loads in both environments. Suspect this before any application bug when the API suite turns red right after a restart or a test database rebuild.

## composer update deletes a theme's compiled assets

Running `composer update` on a Thelia theme removes its compiled `dist/` directory. The next page render then throws a Twig error such as "Could not find the entrypoints file from Webpack". Rebuild the assets locally after an update:

```bash
cd templates/frontOffice/<theme> && npm install && npm run build
```

CI usually recreates `dist/` at deploy time, so the committed change is the lockfile, not the build output.
