# Contributing to the Thelia 3 core

What a pull request on `thelia/thelia` is held to, and what its CI says. Module repositories have their own CI: see `modules.md` §12.

## 1. The 3.x compatibility promise

`BC-PROMISE.md` at the root of `thelia/thelia` is the reference. A 3.x.y release breaks nothing written against an earlier 3.x; a break needs a major release and a deprecation period before it.

Covered (public): PHP classes of `core/lib/Thelia` not marked `@internal`, events and their payload getters, hooks, Twig functions/filters/tests/globals registered by the core and the official themes, API resources (operations, fields), route names and parameters, configuration variables, the tables and columns of `local/config/schema.xml`.

Not covered: `@internal`, `Test` namespaces, generated `Model\Base` / `Model\Map` classes, theme markup and CSS class names, messages, listener order at equal priority.

**Removing a Twig function or filter from a theme breaks every published module that calls it.** Deprecate first, in a minor release, with the replacement available in the same release:

| Surface | How to deprecate |
|---|---|
| PHP | keep the old path, call `trigger_deprecation('thelia/core', '3.x', 'Use %s instead.', ...)`, add `@deprecated since 3.x, use ... instead` |
| Twig function, filter, test | pass the `deprecation_info` option (`Twig\DeprecatedCallableInfo`) to `TwigFunction` / `TwigFilter` / `TwigTest`, naming the replacement |
| API field or operation | keep it, set `deprecationReason` in the resource metadata |
| Event, hook, route, config | keep the old name as an alias of the new one for the whole period |

Where to write it: a line in `CHANGELOG.md` for every deprecation and behaviour change; an entry in the `UPGRADE-3.x.md` of the minor release for every deprecation (what to replace, with what). The test suite runs without deprecations: a deprecated path the core itself still uses is a bug.

## 2. What the CI of a core PR reports

Required checks: the `CI ...` jobs per PHP version and the BO Twig PHPStan job. The rest below are signals: they annotate and summarize, they do not block, and a reviewer decides.

- **Evidence report** (`pr-evidence.yml`, one comment updated per push on same-repo branches, otherwise the job summary): each new or changed test file is run against the base code and must be seen red there (`green` means it would not catch a regression); what the change alters in the public surface (Twig callables, routes, event listeners, API operations and fields, PHP API through Roave BackwardCompatibilityCheck); new duplicated code; a `schema.xml` change without its migration.
- **Skipped tests** (`test.yml`): the skipped tests of the PR are compared with the last green run of `main`. A suite that skips itself stays green while proving nothing: compare the skips, not only the totals.
- **PHPStan level 5 on added lines** (`phpstan-diff.yml`): the project gate runs at a low level against a baseline; new code is held to level 5 through annotations on the lines it adds.
- **Upgrade check** (`upgrade.yml`, runs when schema, `setup/` or the installer change, and nightly): a shop of the latest release is moved to the branch code the way a merchant does, and its schema is compared with a fresh install of the same code (see the schema diff trap in the `thelia3-tooling` skill).

PR template: backward compatibility, schema change with `setup/thelia.sql` plus `setup/update/sql/<version>.sql`, changelog line, each new test seen failing without the change.

## 3. Merging

`main` is protected and merged through a merge queue (rebase method). Once the checks are green, `gh pr merge <n>` without a method flag enqueues the PR; the queue re-runs the checks on the queued commit (`merge_group` event in `test.yml`) and rebases it onto `main`.
