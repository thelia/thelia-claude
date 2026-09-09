---
name: thelia3-tooling
description: "Operational gotchas when developing and testing Thelia 3: the Thelia console versus bin/console, a stale PHPStan result cache on Propel classes, a PHPStan config whose includes merge paths instead of replacing them, PHPUnit 11 failing on deprecated XML, JWT keys for the API test suite, front-office assets built by bin/install versus the back-office theme built by hand and the extra steps a production deployment needs, a missing GitHub token that fails an install with an unrelated error, LiveComponents answering 404, a stale test container that cache:clear cannot fix, PHPStan failing on ungenerated Propel models, PHPUnit warnings exiting 0, ddev composer hiding output, thelia/config overwriting the local schema, Composer advisories, installer-paths clobbering a clone, production cache warmup, and the update loop replaying every script. Use when a Thelia command, an install, a deployment, the test suite, PHPStan, JWT auth, or a theme's assets behave in a way the code does not explain."
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

## Every theme's assets are built for you

`bin/install` builds all the theme assets itself: it runs `importmap:install`, `tailwind:build` and `sass:build` when those commands exist. Flexy is an AssetMapper plus Tailwind CLI theme; the `default-twig` back office (since 1.0.0-beta9) is an AssetMapper plus sass-bundle theme. No `npm install`, no bundler step, no Node anywhere.

An admin that renders with no styling means `sass:build` has not run: the core predates 3.0.0-beta4 (its installer does not know the command), or the stylesheet needs a rebuild after a `composer update` on the theme:

```bash
php bin/console sass:build
```

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

## A stale test container that `cache:clear` cannot fix

PHPUnit runs with `APP_DEBUG=0`, so Symfony never invalidates the compiled test container when a constructor signature, an API serialization group or a template changes. `cache:clear --env=test` boots into a different container hash and fixes nothing; `cache:warmup` keeps the stale metadata. Remove the directory:

```bash
rm -rf var/cache/test
```

Add `var/propel/test/` to the removal after a vendor or bundle resync. Symptoms: `ArgumentCountError`, `ServiceNotFoundException` on a service that exists, or hundreds of failures right after a rebase.

## PHPStan reports a hundred missing classes after clearing `var/propel`

The generated Propel models live under `var/propel/<env>/model/`. Removing that directory (or running on a fresh clone) makes PHPStan and `lint:twig`/`lint:yaml` fail on classes that are not missing but not generated yet. Run `bin/test-prepare` (or the model generation) first, and run the linters with `--env=test` after it.

## PHPUnit warnings exit 0

`phpunit.xml.dist` sets neither `failOnWarning` nor `failOnNotice`. A PHP warning is printed and the run still counts green. Read the summary line, and use `set -o pipefail` when piping the output.

## `ddev composer` hides the failing output

On a non-zero exit, `ddev composer <cmd>` shows only stderr, which hides PHPUnit's report. Run `ddev exec composer <cmd>` to see the whole output. Also, `composer` inside the container resolves to the project's vendored proxy, whose autoloader shadows a Composer plugin class present in the project's vendor tree; a plugin-related crash inside DDEV is not reproducible on the host for that reason.

## `thelia/config` overwrites the local schema

`composer install` extracts the published `thelia/config` package over `local/config/schema.xml`. On a project carrying a schema change that is not released yet, the install silently reverts the schema before Propel generation, and every model built from it lacks the new columns. Restore the file after `composer install` and before `bin/install`, and remember that a schema-only pull request stays red until the package is released.

## Composer refuses an advisory-only version

Composer 2.10 and later refuse by default to install a version covered by a registered security advisory. An exact pin on a series whose every release carries an advisory becomes unsolvable, with a message that names none of this ("could not be found in any version"). Widen the constraint or opt out explicitly.

## `installer-paths` reinstalls over a local clone

A package installed through `installer-paths` (modules, themes) is reinstalled from the registry by any `composer update` or `composer require`, over the directory it targets. A local development clone placed there is clobbered. Use a path repository with `symlink: true` for local work.

## Production cache: purge, then warm up

Purging `var/cache/prod` must always be followed by an explicit `cache:warmup`. The LiveComponents template map is produced by a cache warmer that nothing rebuilds lazily, so a purged-but-not-warmed production answers `500` on the first component render. `cache:clear` in production is the wrong tool for the same reason (see the Thelia console section).

## The update loop replays everything

The updater matches the version marker stored in the database against the update script filenames with a strict lookup. A marker that matches no filename (a pre-release suffix, a renamed script) makes it replay every script from the first one instead of resuming. Check the marker before running an update on a real database.

## Waiting for a long command

Chaining `sleep N && <command>` to wait for a build or a CI run is refused by the coding agent's safety layer. Poll with the harness's monitoring tool (a bounded `until` loop with a timeout) or run the command in the background and let its completion notify you.
