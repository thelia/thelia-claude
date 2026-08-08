# Thelia 3 Modules - Skeleton, lifecycle, persistence

> Stack: SF 7.4 LTS, AP 4.3, PHP 8.3 or later, Propel ORM. Modules are loaded from the DB (`ModuleQuery::getActivated()`).

## 1. Module discovery

`local/modules/` takes PRIORITY over `vendor/thelia/modules/` (`Module::getModuleDir()`, `Model/Module.php:350-355`).

Composer autoload: both directories are declared as PSR-4 with no namespace prefix (`composer.json`). `MyModule\MyModule` resolves normally through Composer.

`module:refresh` scans `THELIA_MODULE_DIR` and `THELIA_LOCAL_MODULE_DIR` for `module.xml` files (`ModuleManagement.php:56,69`) and inserts them into the DB (table `module`).

Single source of truth at boot: `ModuleQuery::getActivated()` (`TheliaKernel.php:372`). A module present on the filesystem but absent from the DB is invisible.

## 2. `configureServices()` - DI entry point

REQUIRED since the "auto-register module classes" revert. Without an override, ZERO module services are in the container (`BaseModule.php:474-477` returns a no-op).

Called in `core/lib/Thelia/Config/Resources/services.php:121` during the PHP-DSL container boot, BEFORE `loadModulesConfiguration()` (which loads `config.xml`) at `TheliaKernel.php:374`.

```php
public static function configureServices(ServicesConfigurator $services): void
{
    $services->load(self::getModuleCode().'\\', __DIR__)
        ->exclude([__DIR__.'/I18n/*', __DIR__.'/Config/**/*.php', __DIR__.'/Tests/*', __DIR__.'/MyModule.php'])
        ->autowire()
        ->autoconfigure();
}
```

`autoconfigure()` activates ALL relevant tags:
- `BaseHookInterface` -> `hook.event_listener` (`TheliaKernel.php:503-505`)
- `LoopInterface` -> `thelia.loop` (`TheliaKernel.php:492-495`)
- `FormInterface` (Thelia) -> `thelia.form` (`TheliaKernel.php:497-500`)
- `ResourceAddonInterface` -> `thelia.api.resource.addon` (`TheliaKernel.php:476`)
- `EventSubscriberInterface` -> `kernel.event_subscriber` (native Symfony)
- `ContainerAwareInterface` (commands) -> `console.command` / `thelia.command`
- API filters (`FilterInterface`) -> `thelia.api.propel.filter`
- Query extensions -> `thelia.api.propel.query_extension.collection|item`

## 3. `module.xml` - metadata

Target XSD: `module-2_2.xsd`, namespace `http://thelia.net/schema/dic/module`. The old v1 XSD without namespace is legacy.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<module xmlns="http://thelia.net/schema/dic/module"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://thelia.net/schema/dic/module http://thelia.net/schema/dic/module/module-2_2.xsd">
    <fullnamespace>MyModule\MyModule</fullnamespace>
    <descriptive locale="fr_FR"><title>Mon module</title></descriptive>
    <descriptive locale="en_US"><title>My module</title></descriptive>
    <languages><language>fr_FR</language><language>en_US</language></languages>
    <version>1.0.0</version>
    <authors><author><name>Your Name</name><email>you@example.com</email></author></authors>
    <type>classic</type>
    <thelia>3.0.0</thelia>
    <stability>alpha</stability>
    <mandatory>0</mandatory>
    <hidden>0</hidden>
</module>
```

Required fields: `<fullnamespace>`, `<descriptive locale><title>`, `<version>`, `<type>` (`classic|delivery|payment|marketplace|price|accounting|seo|administration|statistic`), `<stability>` (`alpha|beta|rc|prod|other`).

Optional: `<required><module version="x.y">Code</module>` (dependencies), `<thelia>` (min version), `<mandatory>` (1 = cannot be uninstalled), `<hidden>`.

## 4. `config.xml` - OPTIONAL

`config.xml` is no longer required for the majority of cases. Keep it ONLY for:

- `<exports>` / `<imports>` (Thelia import/export channels)
- `<parameters>` (Symfony parameters specific to the module)
- `<loop name="alias" class="...">` when a short alias differs from the auto snake_case name

DO NOT add these any more:

| Element | Why obsolete |
|---|---|
| `<services>` (business services) | Covered by `configureServices()` |
| `<hooks>` | Auto-tagged from `BaseHookInterface` |
| `<loops>` (except aliases) | Auto-tagged + auto snake_case name |
| `<forms>` | Auto-tagged from `FormInterface` + `getName()` |
| `<commands>` | Auto-tagged `console.command` / `thelia.command` |
| Module `routing.xml` | `ModuleAttributeLoader` scans `Controller/` |

## 5. Lifecycle methods (`BaseModuleInterface`)

| Method | When | Use |
|---|---|---|
| `install(?ConnectionInterface)` | First install (rare) | Initial setup before activation |
| `preActivation(?ConnectionInterface): bool` | Before activate save | Guard. `false` blocks activation + exception (`BaseModule.php:92-94`) |
| `postActivation(?ConnectionInterface)` | After save activate=1, SAME TRANSACTION | Seed + insertSql. **Exception = rollback AND `setActivate(0)`** |
| `update($from, $to, ?ConnectionInterface)` | When DB version != module version | SQL migrations via `Config/update/*.sql` |
| `preDeactivation(?ConnectionInterface): bool` | Before deactivate save | `false` blocks deactivation |
| `postDeactivation(?ConnectionInterface)` | After save activate=0 | Cleanup cache, optional data |
| `destroy(?ConnectionInterface, bool $deleteData)` | Physical removal | DROP tables if `$deleteData` |
| `getHooks(): array` | Activation + `module:refresh` | Declares hook positions DEFINED by the module (extension points for other modules) |

Canonical `postActivation` pattern:
```php
public function postActivation(?ConnectionInterface $con = null): void
{
    if (!self::getConfigValue('is_initialized', false)) {
        (new Database($con))->insertSql(null, [__DIR__.'/Config/TheliaMain.sql']);
        $this->seedDefaultData($con);              // SEED INSIDE THE GUARD
        self::setConfigValue('is_initialized', true);
    }
}
```

**Strict rule**: ALL code in `postActivation()` (insertSql, Propel seed, default hook creation, fixtures) MUST be inside the `if (!is_initialized)` block. Outside the guard = re-executes on every reactivation, causing N+1 on all customers/products, timeout risk in production, duplicate data, and unexpected side effects.

**Propel seed on first activation**: `MyModule\Model\*` Propel classes are only generated after `module:post-activate-all` (`bin/install`). If the seed instantiates `MyModuleQuery::create()` directly in `postActivation()`, the first pass results in `Class not found`. Three solutions:
1. Seed via raw SQL in `Config/TheliaMain.sql` (simplest, guaranteed idempotent via `INSERT ... ON DUPLICATE KEY UPDATE`)
2. Seed in a dedicated command `app:my-module:seed` launched after `module:post-activate-all`
3. Lazy pattern: detect `class_exists(MyModuleQuery::class)` before seeding, otherwise defer

Solution 1 is recommended for simple seeds; solution 2 for complex seeds (loop over existing entities).

Activation flow via BO: dispatch `TheliaEvents::MODULE_TOGGLE_ACTIVATION` -> `checkToggleActivation` (prio 255) -> `toggleActivation` (prio 128) -> `activate()` or `deActivate()` -> cache clear.

CLI: `ModuleManagement::installModule()` validates, inserts into DB, dispatches `MODULE_TOGGLE_ACTIVATION`. `module:post-activate-all` is run by `bin/install`.

## 6. Routes

Canonical convention: PHP 8 `#[Route]` on controllers. `ModuleAttributeLoader` (`ModuleAttributeLoader.php:35`) scans `Controller/` of each active module with `AttributeDirectoryLoader` + `AttributeRouteControllerLoader`.

`routing.xml`: EMPTY/absent in all modern modules.

Module prefix: override `static getRoutePrefix(): string` (NOT the deprecated `getAnnotationRoutePrefix()`).

```php
#[Route('/admin/mymodule', name: 'mymodule_')]
final class FooController extends BaseAdminController
{
    #[Route('', name: 'list', methods: ['GET'])]
    public function list(): Response
    {
        if ($response = $this->checkAuth(AdminResources::MODULE, ['MyModule'], AccessManager::VIEW)) {
            return $response;
        }
        return $this->render('mymodule.list');
    }
}
```

Three cumulative routers (`core/lib/Thelia/Config/Resources/services/core/routing.php`):
- `router.admin` (`admin.xml`, prio 0)
- `router.front` (`front.xml` from Front module, prio 128)
- `ModuleAttributeLoader` (`#[Route]`, prio 254)
- `RewritingRouter` (SEO URLs)

Note: `BaseController` has `#[Required]` setters -> NEVER use `final readonly` on a Thelia controller. `final readonly` remains required for services and DTOs.

## 7. Propel persistence

### 7.1 `schema.xml`

`SchemaLocator::findForAllModules()` (`SchemaLocator.php:29,46`) scans `*/Config/*schema.xml` in both module directories and merges with the core schema.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<database defaultIdMethod="native" name="TheliaMain"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:noNamespaceSchemaLocation="../../../../core/vendor/propel/propel/resources/xsd/database.xsd">
    <table name="my_module_entity" namespace="MyModule\Model">
        <column autoIncrement="true" name="id" primaryKey="true" required="true" type="INTEGER" />
        <column name="visible" type="TINYINT" />
        <behavior name="timestampable" />
        <behavior name="i18n">
            <parameter name="i18n_columns" value="title, description" />
        </behavior>
    </table>
    <external-schema filename="local/config/schema.xml" referenceOnly="true" />
</database>
```

Required: `name="TheliaMain"` on `<database>`, `namespace="MyModule\Model"` on each `<table>`. `external-schema` is required whenever you have a `<foreign-key>` pointing to core tables (customer, order, product...).

Common behaviors: `timestampable` (created_at/updated_at), `i18n` (generates `*_i18n` + `setLocale()/getTitle()`).

### 7.2 SQL migrations

Convention: `Config/update/{version}.sql`, merged by `version_compare`.

```php
public function update($currentVersion, $newVersion, ?ConnectionInterface $con = null): void
{
    $finder = Finder::create()->name('*.sql')->depth(0)->sortByName()->in(__DIR__.'/Config/update');
    $database = new Database($con);
    foreach ($finder as $file) {
        if (version_compare($currentVersion, $file->getBasename('.sql'), '<')) {
            $database->insertSql(null, [$file->getPathname()]);
        }
    }
}
```

No auto-generated Doctrine/Propel migrations - only raw SQL via `Thelia\Core\Install\Database::insertSql()`.

### 7.3 Propel ORM - basic rules

```php
// CRUD
$product = ProductQuery::create()->findPk($id);
$products = ProductQuery::create()->filterByVisible(true)->orderByPosition()->find();

// Joins via useQuery/endUse
$products = ProductQuery::create()
    ->useProductCategoryQuery()
        ->filterByCategoryId($categoryId)
    ->endUse()
    ->find();

// i18n
$category->setLocale('fr_FR')->getTitle();

// Connection
$con = Propel::getConnection('TheliaMain');
```

Rules:
- Each `->save()` persists IMMEDIATELY (no Doctrine `flush()`, no `EntityManager`).
- No Doctrine, ever.

### 7.4 Strict Propel setter types

Generated setters are natively typed and, under `declare(strict_types=1)` (the norm throughout T3), reject any coercion:

- **`TINYINT` columns** (`visible`, `activate`, `active`, `native`, `is_default`, `is_free_text`, `default_folder`, `default_category`, `unsubscribed`...) -> setter `?int`. Pass `0`/`1`, **never** `true`/`false`: `setVisible(false)` raises `TypeError: Argument #1 ($v) must be of type ?int, bool given`. Toggle: `setVisible($obj->getVisible() ? 0 : 1)`. Mass update: `update(['Visible' => 0])`.
- **`DECIMAL` columns** (`price`, `weight`, `amount`...) -> setter `?string`. Pass a string (`'12.5'`), **never** a `float`.
- **`INTEGER` columns** -> setter `?int`.

Note: these constraints apply to **Propel models**. Native PHP Event classes (`$event->setActive(true)`) keep their own types (often `bool`) - do not confuse the two.

### 7.5 Propel query traps

- **`_or()` rewrites the ENTIRE WHERE**: `$query->filterByStatus($s)->_or()->filterByRef($r)` does not produce `status AND (... OR ...)` but switches the entire WHERE to OR (including previous filters). To group an OR without breaking other filters, use `condition()` + `combine()`:
  ```php
  $query
      ->condition('c1', OrderTableMap::COL_REF.' LIKE ?', $needle)
      ->condition('c2', OrderTableMap::COL_INVOICE_REF.' LIKE ?', $needle)
      ->combine(['c1', 'c2'], 'OR');   // WHERE (existing filters) AND (c1 OR c2)
  ```
- **`Criteria::NOT_IN` / `IN` on an empty array**: `filterById([], Criteria::NOT_IN)` does not generate a valid clause and **returns all rows**. Always guard with `if ($ids !== []) { ... }` before applying the filter.
- **`Model::TABLE_MAP`** returns the **PHP FQCN** (`\Thelia\Model\Map\OrderTableMap`), not the SQL table name. For a column name in raw SQL, use the `XxxTableMap::COL_*` constants (e.g. `OrderTableMap::COL_REF` = `'order.ref'`).

## 8. i18n

### Propel i18n (business DB data)
Behavior in `schema.xml`:
```xml
<behavior name="i18n">
    <parameter name="i18n_columns" value="title, description" />
</behavior>
```
Generates a `*_i18n` table + `setLocale('fr_FR')->getTitle()` methods.

### Symfony Translation (UI strings)
`MyModule/I18n/{locale}.php` (Thelia format: array<string,string>) or `translations/`. Domain = module code in lowercase.

```php
// MyModule/I18n/fr_FR.php
return [
    'My message' => 'Mon message',
];
```

```php
// Preferred usage: injection
public function __construct(private TranslatorInterface $translator) {}
$this->translator->trans('My message', [], 'mymodule');
```

#### The TWO translators (central trap)

T3 runs two translation systems with different default domains:

| Call | Actual service | Default domain | Loaded from |
|---|---|---|---|
| **PHP** `$this->translator->trans('X')` (injected `TranslatorInterface`) | `Thelia\Core\Translation\Translator` (alias of `TranslatorInterface`) | **`core`** (`$domain ??= 'core'`) | Thelia catalogs (`I18n/*.php` from modules, core) |
| **Twig** `{{ 'X'\|trans }}` | Symfony FrameworkBundle `translator` (not overridden by Thelia) | **`messages`** | `translations/` + `framework.translator.paths` |

Consequences:
- **In PHP, always specify the module domain** (`trans('X', [], 'mymodule')`): without it, the `core` catalog is queried, not the module's.
- **Fallback = raw key**: if the key is missing from the catalog, `Translator::trans()` returns `strtr($id, $parameters)` - the source string as-is (gettext model: the string IS the key). An untranslated string displays in plain text (often the English source), with no error - a silent trap if you assume the translation is loaded.

#### `Lang::getDefaultLanguage()` is not the request locale

`Lang::getDefaultLanguage()` returns the language marked as default **in the store** (often `en_US` on a fresh install), independent of the current user. To create/display i18n content in the active interface language, use `$request->getLocale()` - never the default language. A common mistake: content created from a `fr_FR` UI gets persisted in `en_US` because the controller passed the store default language as the locale.

**Trap**: `Translator::getInstance()` can throw `RuntimeException` if the singleton is not initialized (tests, CLI). Prefer injected service.

## 9. Composer distribution

```json
{
  "name": "vendor/my-module",
  "type": "thelia-module",
  "license": "LGPL-3.0-or-later",
  "require": {"thelia/installer": "~1.1"},
  "extra": {"installer-name": "MyModule"}
}
```

`thelia/installer` copies to `vendor/thelia/modules/{installer-name}/`. Modules in `local/modules/` do NOT need a `composer.json`.

## 10. Traps

| Trap | Fix |
|---|---|
| `getModuleCode()` != first FQCN segment | folder = class = FQCN root (`RegisterHookListenersPass:81` `explode('\\')[0]`) |
| `local/modules` silently overrides `vendor/thelia/modules` | use distinct names |
| `postActivation()` not idempotent | `is_initialized` guard + `setConfigValue` |
| `Thelia\Install\Database` (without `\Core`) | use `Thelia\Core\Install\Database` |
| `new Database($con->getWrappedConnection())` | `new Database($con)` - accepts `ConnectionInterface` |
| `getRequest()` from BaseModule in CLI | guard `$container->has('request_stack')` |
| `RegisterHookListenersPass` DB query at compile time | DB must be available at cache warmup |
| `ConfigQuery::read()` returns a stale value | PSR `thelia_config` cache (see §11) - force via `ConfigQuery::write()` or purge |

### Configuration cache `thelia_config`

`ConfigQuery::read()` does NOT read the `config` table on every call: `ConfigCacheService` caches a snapshot of all configs in the PSR `thelia.cache` pool (key `thelia_config`). Consequences:
- A direct SQL `UPDATE` on the `config` table **does not invalidate** this cache -> `read()` may return the old value. Use `ConfigQuery::write()` (updates DB + cache) or force `ConfigCacheService::initCacheConfigs(true)`.
- `bin/console cache:clear` may not purge this pool depending on its config. `php Thelia cache:clear` purges more completely (see below).

## 11. Useful CLI commands

Two CLI entrypoints coexist:
- **`php Thelia X`** - Thelia-aware bootstrap. **Required** for Thelia commands: `template:set`, `*:demo:import`, `admin:create`, `admin:updatePassword`, `module:*`, and **`cache:clear`** (more complete purge, including Thelia PSR pools like `thelia_config`). `bin/console template:set` crashes.
- **`bin/console X`** - pure Symfony console. OK for `lint:twig`, `debug:router`, `debug:container`, `debug:event-dispatcher`.

```bash
ddev exec php Thelia cache:clear
ddev exec php Thelia module:activate MyModule
ddev exec php Thelia module:refresh
ddev exec php Thelia module:post-activate-all
ddev exec php Thelia module:generate MyModule
ddev exec php Thelia module:generate:model MyModule --generate-sql
ddev exec php Thelia admin:create
```
