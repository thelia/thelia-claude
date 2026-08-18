---
name: thelia3-tooling
description: "Operational gotchas when developing and testing Thelia 3: the Thelia console versus bin/console, a stale PHPStan result cache on Propel classes, a PHPStan config whose includes merge paths instead of replacing them, PHPUnit 11 failing on deprecated XML, JWT keys for the API test suite, front-office assets built by bin/install versus the back-office theme built by hand and the extra steps a production deployment needs, a missing GitHub token that fails an install with an unrelated error, and LiveComponents answering 404. Use when a Thelia command, an install, a deployment, the test suite, PHPStan, JWT auth, or a theme's assets behave in a way the code does not explain."
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

## A PHPStan `includes:` merges `paths`, it does not replace them

A second PHPStan config that includes the main one inherits every parameter, and array parameters are merged rather than overwritten. Include a root config that analyses `core`, add your own `paths`, and the run analyses both: the extra config is a superset of the first, not a narrower scope.

```neon
includes:
    - phpstan.neon      # already declares paths and a level
parameters:
    paths:
        - templates/backOffice/default-twig/src
```

Scalars behave the other way round and simply override, so a config that does not restate `level` silently runs at the included one. The two combine into a gate you believe is scoped to one directory at one level while it re-analyses everything at a level someone else chose.

Mark the key with `!` to replace instead of append:

```neon
parameters:
    level: 5
    paths!:
        - templates/backOffice/default-twig/src
```

`vendor/bin/phpstan dump-parameters -c <config>` prints the merged result and settles the question without running an analysis. Relative paths in it resolve against the directory of the config file that declares them, not the working directory.

## PHPUnit 11 fails on deprecated XML

A deprecated attribute in `phpunit.xml` (for example `cacheResultFile`, or the old `listeners` element) makes PHPUnit 11 exit with code 1 even when every test passes. Inside a `composer test` chain this looks like a test failure but is a configuration warning. Migrate the config: use `cacheDirectory`, and move listeners to `extensions` and bootstrap entries.

## JWT keys and the API test suite

If the dev and test environments share the same `config/jwt/` keypair but use different passphrases, the API test suite cannot decrypt the key and reports `bad decrypt`. The fix is to regenerate the keypair without a passphrase, so the unencrypted key loads in both environments. Suspect this before any application bug when the API suite turns red right after a restart or a test database rebuild.

## Which theme assets are built for you, and which are not

`bin/install` builds the front-office assets itself: it runs `importmap:install` then `tailwind:build` when those commands exist. Flexy is an AssetMapper plus Tailwind CLI theme, so there is no `npm install` and no bundler step to run by hand.

The back-office theme is the exception. Its compiled `dist/` is gitignored and therefore absent from the published package, so it has to be built once:

```bash
cd templates/backOffice/default-twig && npm install && npm run build
```

An admin that renders with no styling is this missing build, not a broken configuration. Rebuild it after a `composer update` on the theme too, since the update replaces the package directory and takes `dist/` with it.

Deploying to production adds two steps that no install script runs for you: `tailwind:build --minify` for the stylesheet, and `asset-map:compile` to write the mapped assets into the public directory. AssetMapper's dev server, which serves them on the fly during development, follows the debug flag and is off in production, so a front office deployed without the compile loads with no CSS and no JavaScript.

## A missing GitHub token fails an install on an unrelated message

Composer needs a GitHub token to fetch `thelia/thelia-recipes`. Without one, Symfony Flex does not stop: it falls back to auto-generated recipes, so Thelia's `config/packages/*.yaml` files are never written. The install proceeds and dies much later on a message that names none of this:

```
You must either configure a "public_key" or a "secret_key"
```

Check Composer's authentication and the contents of `config/packages/` before reading that message literally.

## LiveComponents return 404

The `/_components` route must carry `ignore_thelia_view: true` in its defaults. Without it, `Thelia\Core\EventListener\ViewListener` answers `kernel.view` with a themed view, `/_components/...` matches no front-office view, and every LiveComponent round-trip answers 404. The current `thelia/thelia-recipes` recipe sets it, but Flex never rewrites a routing file that already exists, so a project created before it keeps the old one:

```yaml
# config/routes/ux_live_component.yaml
live_component:
    resource: '@LiveComponentBundle/config/routes.php'
    prefix: '/_components'
    defaults:
        ignore_thelia_view: true
```

The same flag is the general opt-out from Thelia's view rendering: any route whose controller returns something the theme should not wrap needs it in its defaults. Nothing in the core ever sets it; it comes from route configuration only.
