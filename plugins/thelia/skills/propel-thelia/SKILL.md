---
name: propel-thelia
description: "Deep Propel ORM reference for Thelia 3. Covers the Thelia fork internals (4 waves of patches), bootstrap sequence (TheliaKernel, PropelInitService, SchemaLocator), model file layout (stubs vs generated Base/), query patterns (CRUD, relations, pagination, i18n, transactions), lifecycle events (Propel low-level and Thelia business events), API Platform bridge (PropelResourceInterface, AbstractTranslatableResource, ResourceAddonInterface, filters, providers, processors), loops (BaseLoop, PropelSearchLoopInterface), native PHP typing rules for generated models (nullable types, TINYINT/DECIMAL/BOOLEAN rules, method renames), and all common pitfalls. Triggers on: Propel, schema.xml, PropelQuery, PropelInitService, TheliaKernel, PropelResourceInterface, AbstractTranslatableResource, ResourceAddonInterface, BaseLoop, PropelSearchLoopInterface, ModelCriteria, TheliaEvents, BaseAction, EventSubscriberInterface (Thelia context), native typed setters, TINYINT bool coercion, DECIMAL string coercion."
---

# Propel ORM in Thelia 3: Complete Reference

This document gives an agent without prior context everything needed to understand Propel's architecture, patterns, key files, and pitfalls in a Thelia 3 codebase.

## When to use

- Adding or modifying a Propel model (`schema.xml`, `Model/`, `Query/`)
- Working on Action listeners (event-driven persistence)
- Creating or modifying an API resource (Propel / API Platform bridge)
- Debugging a query, i18n, or model-generation issue
- Creating a module with its own tables
- Understanding the application bootstrap

## Overview

Thelia 3 uses **Propel 2** (ActiveRecord ORM, not Doctrine). It is a maintained fork: `thelia/propel` (branch `thelia3.0`), based on the upstream tip of `propelorm/Propel2`.

**Propel is not Doctrine:**
- No `EntityManager`, no `flush()`, no Unit of Work.
- Every `->save()` persists immediately to the database.
- Models are ActiveRecord: `$product->setTitle('X')->save()`
- Queries are fluent builders: `ProductQuery::create()->filterByVisible(1)->find()`

## The Thelia Fork

Repo: `https://github.com/thelia/Propel2.git`, branch `thelia3.0`
Composer package: `thelia/propel` (`dev-thelia3.0`)
0 commits behind upstream.

### The 4 waves of changes

**Wave 1 — Backward compatibility (2016, 8 commits)**
- Reintroduced constants: `TYPE_STUDLYPHPNAME`, `TYPE_RAW_COLNAME`
- Iterator methods on `Collection` (225 lines, all `@deprecated`)
- Auto-conversion from `Join` to `ModelJoin`

**Wave 2 — Propel event system (2018-2019, 7 commits)**
Upstream Propel has no events. The fork adds:
- `EventBuilder`: generates one Event class per table (`ProductEvent`, `CategoryEvent`, etc.) with 8 lifecycle constants (`PRE_SAVE`, `POST_SAVE`, `PRE_INSERT`, `POST_INSERT`, `PRE_UPDATE`, `POST_UPDATE`, `PRE_DELETE`, `POST_DELETE`)
- `ResolverBuilder`: maps table name to TableMap namespace
- Injection of `EventDispatcherInterface` into `ConnectionInterface`, `ConnectionWrapper`, `PdoConnection` (marked `@specificity thelia`)
- Lifecycle hooks in generation templates: each `preSave()`, `postSave()`, etc. dispatches a Symfony event when the connection has an EventDispatcher

**Wave 3 — PHP 8.x / Symfony 6 compatibility (2020-2025, 7 commits)**
- Fix for dynamic properties (PHP 8.2)
- Return types, missing namespaces, bug fixes

**Wave 4 — Native PHP typing**
Generated models now have native PHP types on properties, getters, and setters. Files changed in the fork: `PropelTypes.php`, `Column.php`, `ObjectBuilder.php`. See [Native typing of generated models](#native-typing-of-generated-models) below.

## Fork architecture

```
vendor/thelia/propel/src/Propel/
├── Common/          # Config, pluralization, utilities
├── Generator/       # Code generation (build-time, ~35,000 LOC)
│   ├── Behavior/    # 14 behaviors: i18n, timestampable, sortable, versionable,
│   │                #   archivable, sluggable, nested_set, aggregate_column...
│   ├── Builder/Om/  # Generates Model, Query, TableMap, Event
│   ├── Platform/    # SQL per DB: MySQL, PostgreSQL, SQLite, MSSQL, Oracle
│   └── Reverse/     # Reverse-engineering from an existing DB
├── Runtime/         # ORM runtime (~25,000 LOC)
│   ├── ActiveQuery/ # Criteria, ModelCriteria, QueryExecutors (Select/Insert/Update/Delete/Count)
│   ├── Connection/  # ConnectionWrapper + EventDispatcher (custom Thelia)
│   ├── Collection/  # ObjectCollection, ArrayCollection, OnDemandCollection
│   ├── Formatter/   # ObjectFormatter, ArrayFormatter, OnDemandFormatter
│   ├── Event/       # ActiveRecordEvent (custom Thelia)
│   ├── Map/         # TableMap, ColumnMap, RelationMap (metadata)
│   └── Adapter/     # PDO adapters per DB
└── templates/       # PHP templates for code generation
```

## Propel bootstrap in Thelia

### Initialization sequence

```
TheliaKernel.__construct()
  └→ Registers PSR-4 autoloaders: var/propel/{env}/model/ and var/propel/{env}/database/TheliaMain/

TheliaKernel.initializeContainer()
  ├→ Creates SchemaLocator(theliaConfDir, theliaModuleDir, theliaLocalModuleDir)
  ├→ Creates PropelInitService(environment, debug, envParameters, schemaLocator)
  ├→ Calls PropelInitService.init()
  │     ├→ isCacheComplete() ? fast path: loadPropelRuntime()
  │     └→ slow path (with FlockStore lock):
  │           ├→ buildPropelConfig()       → var/propel/{env}/config/propel.yml
  │           ├→ buildPropelInitFile()     → var/propel/{env}/config/propel.init.php
  │           ├→ buildPropelGlobalSchema() → merges all schema.xml files
  │           ├→ buildPropelModels()       → generates Base/, Map/, Event/ under var/propel/{env}/model/
  │           └→ loadPropelRuntime()       → requires init file + configures connection
  └→ Validates MySQL configuration (sql_mode)
```

### Key bootstrap files

| File | Role |
|------|------|
| `core/lib/Thelia/Core/TheliaKernel.php` | Boots Propel before the Symfony container |
| `core/lib/Thelia/Core/Propel/PropelInitService.php` | Init orchestrator (cache, lock, generation) |
| `core/lib/Thelia/Config/DatabaseConfigurationSource.php` | DB config from env vars or YAML |
| `core/lib/Thelia/Core/Propel/Schema/SchemaLocator.php` | Discovers schema.xml files (core + modules) |
| `core/lib/Thelia/Core/Propel/Schema/SchemaCombiner.php` | Merges schemas into a single XML per DB |

### Custom Thelia builders

All located in `core/lib/Thelia/Core/Propel/Generator/Builder/Om/`:

| Builder | Propel base | Trait | Role |
|---------|-------------|-------|------|
| `ObjectBuilder` | `PropelObjectBuilder` | `ImplementationClassTrait` | Base Model classes (into `var/propel/`) |
| `ExtensionObjectBuilder` | `PropelExtensionObjectBuilder` | `StubClassTrait` | Model stubs (into `core/lib/` or module) |
| `QueryBuilder` | `PropelQueryBuilder` | `ImplementationClassTrait` | Base Query classes |
| `ExtensionQueryBuilder` | `PropelExtensionQueryBuilder` | `StubClassTrait` | Query stubs |
| `TableMapBuilder` | `PropelTableMapBuilder` | `ImplementationClassTrait` | TableMap metadata |
| `EventBuilder` | `PropelEventBuilder` | `ImplementationClassTrait` | Lifecycle Event classes |
| `ResolverBuilder` | (none) | (none) | Table-to-TableMap resolver (into `var/propel/{env}/database/`) |

`ImplementationClassTrait`: routes generated classes to `var/propel/{APP_ENV}/model/`
`StubClassTrait`: routes stubs to `core/lib/Thelia/Model/` or the module directory

## Schema and models

### Main schema

**File:** `local/config/schema.xml` (2030 lines, **75 tables**)

Main tables: `category`, `product`, `country`, `tax`, `tax_rule`, `feature`, `feature_av`, `attribute`, `attribute_av`, `product_sale_elements`, `config`, `customer`, `address`, `customer_title`, `lang`, `folder`, `content`, `order`, `currency`, `order_product`, `order_status`, `module`, `brand`, `sale`, `coupon`, `hook`, `rewriting_url`, `cart`, `cart_item`, `admin`...

**Behaviors used in the schema:**
- `timestampable` — on almost every table (created_at/updated_at)
- `i18n` — on ~41 tables (title, description, chapo, postscriptum, meta_*)
- `versionable` — on category, product, order, coupon, admin_log

### Module schemas

Active modules add their own tables via `{module}/Config/schema.xml`. `SchemaCombiner` merges them at build time. Examples: CustomerFamily (6 tables), TheliaBlocks, TheliaLibrary, OpenApi...

### Model file layout

```
core/lib/Thelia/Model/          # Hand-written stubs (~283 files)
├── Product.php                 # Extends Base\Product, adds business logic
├── ProductQuery.php            # Extends Base\ProductQuery, can add methods
├── ProductI18n.php             # i18n stub
├── Category.php
├── CategoryQuery.php
├── Tools/                      # Model utilities
│   ├── ModelCriteriaTools.php  # i18n helper (dual-locale JOIN)
│   ├── PositionManagementTrait.php  # Position-based sorting
│   ├── UrlRewritingTrait.php   # URL rewriting
│   └── ProductPriceTools.php   # Price calculation
├── Breadcrumb/                 # Breadcrumb traits
└── Exception/                  # Model exceptions

var/propel/{env}/model/Thelia/Model/   # Auto-generated
├── Base/                       # ~280 files (Product.php, ProductQuery.php...)
├── Map/                        # TableMap (column/relation metadata)
└── Event/                      # Lifecycle events (ProductEvent.php...)
```

### Anatomy of a model stub

```php
// core/lib/Thelia/Model/Product.php
class Product extends BaseProduct implements FileModelParentInterface
{
    use PositionManagementTrait;
    use UrlRewritingTrait;

    public function getRewrittenUrlViewName(): string { return 'product'; }
    public function getRealLowestPrice(): ?float { /* virtual column */ }
    // Domain-specific logic...
}
```

Stubs are edited by hand. `Base/` classes are regenerated on every `buildPropelModels()` call. Never edit `Base/`.

## Propel query patterns

### Basic CRUD

```php
// Create
$product = new Product();
$product->setRef('PRD-001')->setLocale('fr_FR')->setTitle('My product')->save();

// Read by PK
$product = ProductQuery::create()->findPk($id);

// Read with filters
$products = ProductQuery::create()
    ->filterByVisible(1)
    ->filterByRef('PRD-%', Criteria::LIKE)
    ->orderByCreatedAt(Criteria::DESC)
    ->find();  // returns ObjectCollection

// Update
$product->setTitle('New title')->save();

// Delete
$product->delete();
```

### Queries with relations (useXxxQuery)

```php
$products = ProductQuery::create()
    ->useProductCategoryQuery()         // JOIN to product_category
        ->filterByCategoryId($catId)
    ->endUse()
    ->useProductI18nQuery()             // JOIN to product_i18n
        ->filterByLocale('fr_FR')
    ->endUse()
    ->find();
```

### Advanced queries

```php
// Pagination
$pager = ProductQuery::create()
    ->filterByVisible(1)
    ->paginate($page, $perPage);  // returns PropelModelPager

// Count
$count = ProductQuery::create()->filterByVisible(1)->count();

// Virtual columns
$query = ProductQuery::create()
    ->withColumn('COUNT(product_sale_elements.id)', 'pse_count')
    ->addSelectQuery($subQuery, 'lowest_price');

// On-demand formatter (memory-efficient iteration)
$products = ProductQuery::create()
    ->setFormatter(ModelCriteria::FORMAT_ON_DEMAND)
    ->find();
```

### i18n

```php
// Reading i18n
$product->setLocale('fr_FR')->getTitle();

// i18n in loops (dual-locale fallback)
ModelCriteriaTools::getFrontEndI18n($search, 'PRODUCT', 'product_i18n', 'fr_FR');
// Adds a JOIN for the requested locale with a fallback to the default locale
```

### Connections and transactions

```php
// Named connection
$con = Propel::getConnection('TheliaMain');

// Explicit write connection
$con = Propel::getWriteConnection(ProductTableMap::DATABASE_NAME);

// Transaction
$con->beginTransaction();
try {
    $product->save($con);
    $pse->save($con);
    $con->commit();
} catch (\Exception $e) {
    $con->rollBack();
    throw $e;
}
```

## Event system (two levels)

### Level 1: Propel lifecycle events (low-level)

Generated by the fork. Every `->save()` automatically dispatches events when the connection has an EventDispatcher.

```php
// Generated in var/propel/{env}/model/Thelia/Model/Base/Product.php
public function preSave(?ConnectionInterface $con = null): bool {
    if (null !== $con
        && method_exists($con, 'getEventDispatcher')
        && null !== $con->getEventDispatcher()
    ) {
        $event = new ProductEvent($this);
        $con->getEventDispatcher()->dispatch($event, ProductEvent::PRE_SAVE);
        return !$event->isPropagationStopped();
    }
    return true;
}
```

Constants: `PRE_SAVE`, `POST_SAVE`, `PRE_INSERT`, `POST_INSERT`, `PRE_UPDATE`, `POST_UPDATE`, `PRE_DELETE`, `POST_DELETE`
Format: `'propel.pre.save.product'`

### Level 2: Thelia business events (high-level)

Event-driven architecture. A controller never persists directly:

```
Controller → dispatch(TheliaEvents::PRODUCT_CREATE, $event)
  → Action\Product::create($event) → new Product() + ->save()
```

**Central file:** `core/lib/Thelia/Core/Event/TheliaEvents.php`
Categories: ADDRESS, CATEGORY, PRODUCT, CART, ORDER, COUPON, IMAGE, DOCUMENT, CONFIG, TAX, PROFILE, CUSTOMER, etc.

**Action listener pattern:**

```php
// core/lib/Thelia/Action/Category.php
class Category extends BaseAction implements EventSubscriberInterface
{
    public function create(CategoryCreateEvent $event, $eventName, EventDispatcherInterface $dispatcher): void
    {
        $category = new CategoryModel();
        $category
            ->setLocale($event->getLocale())
            ->setParent($event->getParent())
            ->setVisible($event->getVisible())
            ->setTitle($event->getTitle())
            ->save();
        $event->setCategory($category);
    }

    public function delete(CategoryDeleteEvent $event, $eventName, EventDispatcherInterface $dispatcher): void
    {
        $category = CategoryQuery::create()->findPk($event->getCategoryId());
        if (null === $category) { return; }

        $con = Propel::getWriteConnection(CategoryTableMap::DATABASE_NAME);
        $con->beginTransaction();
        try {
            $category->delete($con);
            $con->commit();
        } catch (\Exception $e) {
            $con->rollback();
            throw $e;
        }
    }

    public static function getSubscribedEvents(): array
    {
        return [
            TheliaEvents::CATEGORY_CREATE            => ['create', 128],
            TheliaEvents::CATEGORY_UPDATE            => ['update', 128],
            TheliaEvents::CATEGORY_DELETE            => ['delete', 128],
            TheliaEvents::CATEGORY_TOGGLE_VISIBILITY => ['toggleVisibility', 128],
            TheliaEvents::CATEGORY_UPDATE_POSITION   => ['updatePosition', 128],
        ];
    }
}
```

**Priority:** 128 is the default. Higher runs first. Example: `IMAGE_DELETE => ['handler', 192]`

## API Platform / Propel bridge

### Architecture

```
core/lib/Thelia/Api/
├── Resource/                              # API resources (DTO-like)
│   ├── PropelResourceInterface.php        # Central interface
│   ├── PropelResourceTrait.php            # Implementation (magic __get, __set)
│   ├── TranslatableResourceInterface.php  # For i18n resources
│   ├── AbstractTranslatableResource.php   # i18n base class
│   ├── ResourceAddonInterface.php         # Resource extension
│   ├── Product.php, Category.php...       # 50+ concrete resources
│
├── Bridge/Propel/
│   ├── State/
│   │   ├── PropelItemProvider.php         # GET /resource/{id}
│   │   ├── PropelCollectionProvider.php   # GET /resources
│   │   ├── PropelPersistProcessor.php     # POST/PUT/PATCH
│   │   └── PropelRemoveProcessor.php      # DELETE
│   │
│   ├── Service/
│   │   └── ApiResourcePropelTransformerService.php  # Model <-> Resource (823 lines)
│   │
│   ├── Extension/
│   │   ├── QueryItemExtensionInterface.php
│   │   ├── QueryCollectionExtensionInterface.php
│   │   ├── QueryResultCollectionExtensionInterface.php
│   │   ├── FilterExtension.php
│   │   └── PaginationExtension.php
│   │
│   ├── Filter/
│   │   ├── SearchFilter.php   # exact, partial, start, end, word_start
│   │   ├── BooleanFilter.php
│   │   ├── OrderFilter.php
│   │   ├── DateFilter.php
│   │   ├── RangeFilter.php
│   │   └── NotInFilter.php
│   │
│   └── Attribute/
│       ├── Column.php                # #[Column(propelFieldName: '...')]
│       ├── Relation.php              # #[Relation(targetResource: X::class)]
│       └── CompositeIdentifiers.php  # #[CompositeIdentifiers(keys: [...])]
```

### API resource pattern

```php
#[ApiResource(
    operations: [
        new Get(uriTemplate: '/admin/products/{id}'),
        new Put(uriTemplate: '/admin/products/{id}'),
        new GetCollection(uriTemplate: '/admin/products'),
    ],
)]
#[ApiFilter(filterClass: SearchFilter::class, properties: ['ref', 'title' => 'word_start'])]
#[ApiFilter(filterClass: BooleanFilter::class, properties: ['visible'])]
class Product extends AbstractTranslatableResource
{
    #[Groups([self::GROUP_ADMIN_READ])]
    public ?int $id = null;

    #[Relation(targetResource: TaxRule::class)]
    public TaxRule $taxRule;

    #[Column(propelFieldName: 'visibility')]
    public bool $visible;
}
```

### Data flow

```
GET /admin/products/{id}
  → PropelItemProvider
    → Builds ProductQuery::create() from TableMap
    → Dispatches ItemProviderQueryEvent (extensible)
    → Applies QueryItemExtensions
    → $query->findOne()
    → ApiResourcePropelTransformerService::modelToResource()
    → Returns Product resource

POST /admin/products
  → PropelPersistProcessor
    → ApiResourcePropelTransformerService::resourceToModel()
    → Symfony validation
    → $model->save() in a transaction
    → Handles relations (#[Relation]) and i18n
    → Returns transformed resource
```

### LiveComponent

`PropelModelHydrationExtension` (in `Core/LiveComponent/Hydration/`) serializes and deserializes Propel models in Symfony UX LiveComponents:
- Dehydrate: `['__propel_class' => Product::class, '__id' => 42]`
- Hydrate: `ProductQuery::create()->findPk(42)`

## Loops (Smarty/Twig legacy)

Loops are the front-office query system inherited from Thelia 2.

### Base classes

- `BaseLoop` (`Core/Template/Element/BaseLoop.php`): pagination, cache, arguments
- `BaseI18nLoop`: extends BaseLoop with i18n handling
- `PropelSearchLoopInterface`: requires `buildModelCriteria(): ModelCriteria`

### Execution flow

```
BaseLoop.exec()
  → buildModelCriteria()     # Builds the Propel query
  → search($criteria)        # Executes: paginate() or find()
  → parseResults($results)   # Transforms into LoopResult
```

### Example: Product Loop

```php
// core/lib/Thelia/Core/Template/Loop/Product.php
public function buildModelCriteria(): ModelCriteria
{
    $search = ProductQuery::create();

    // Filters
    if ($id = $this->getId()) {
        $search->filterById($id, Criteria::IN);
    }
    if ($visible !== BooleanOrBothType::ANY) {
        $search->filterByVisible($visible);
    }

    // i18n
    $this->configureI18nProcessing($search, ['TITLE', 'CHAPO', 'DESCRIPTION', ...]);

    // Price JOIN with PSE
    $currencyJoin = new Join();
    $currencyJoin->addExplicitCondition(/*...*/);
    $search->addJoinObject($currencyJoin);

    // Sort
    $search->orderByCreatedAt(Criteria::DESC);

    return $search;
}
```

## Native typing of generated models

Since the Thelia 3 Propel fork, models generated in `var/propel/` carry native PHP 8.2+ types. This typing is implemented in the fork's `ObjectBuilder.php` and affects all `Base/` classes.

### What is generated

```php
// BEFORE (no types)
protected $id;
public function getId() { ... }
public function setId($v) { ... }

// AFTER (native types)
protected ?int $id = null;
public function getId(): ?int { ... }
public function setId(?int $v = null): static { ... }
```

### Typing rules by column type

| Schema type | Property | Getter return | Setter param |
|-------------|----------|---------------|--------------|
| INTEGER, TINYINT, SMALLINT | `?int` | `?int` | `?int` |
| VARCHAR, CHAR, LONGVARCHAR | `?string` | `?string` | `?string` |
| DECIMAL, NUMERIC | `?string` | `?string` | `?string` |
| BIGINT | `?string` | `?string` | `?string` |
| FLOAT, DOUBLE, REAL | `?float` | `?float` | `?float` |
| DATE, DATETIME, TIMESTAMP, TIME | `?\DateTimeInterface` | `string\|\DateTimeInterface\|null` | `string\|int\|\DateTimeInterface\|null` |
| BOOLEAN, BOOLEAN_EMU | `?bool` (property/getter) | `?bool` | **untyped** (accepts bool/int/string) |
| ENUM, SET | **untyped** | **untyped** | **untyped** |
| OBJECT, BLOB | **untyped** | **untyped** | **untyped** |
| JSON | `?string` | `?string` | `?string` |

**All setters return `: static`** (fluent interface).

### Why everything is nullable (`?type`)

Propel initializes all properties to `null` before hydration. An unpersisted object (`new Product()`) has all fields as `null`, including `required=true` columns like `id` (auto-increment). The clone pattern (`$order->setId(null)->setNew(true)`) also depends on nullability.

### Types excluded from typing

**ENUM/SET:** Propel stores an `int` index internally but the getter returns the `string` value via a lookup table. A `?int` type on the getter would cause a TypeError.

**BOOLEAN setters:** The Boolean setter does permissive conversion (`is_string($v)`, `(boolean) $v`). Typing the param as `?bool` would break callers that pass `0`/`1` or `'true'`/`'false'`. The property and getter are typed `?bool`, but the setter param remains untyped.

### Impact on model stubs

When a stub overrides a getter or setter from the Base class, it **must** match the typed signature.

```php
// WRONG — "must be compatible" fatal error
public function setPassword($password) { ... }

// CORRECT — aligned signature
public function setPassword(?string $password = null): static { ... }
```

Common cases to align:
- `getValue(): ?string` on Config, MetaData
- `setPosition(?int $v = null): static` on Product, Content
- `setPassword(?string $v = null): static` on Admin, Customer
- Any getter/setter override in stubs under `core/lib/Thelia/Model/`

### Impact on interfaces

Interfaces that declare Propel setter signatures must match the actual column type.

```php
// FileModelInterface — visible is TINYINT, not BOOLEAN
public function setVisible(?int $visible = null): static;  // correct
public function setVisible(bool $visible);                  // WRONG
```

### Type coercion in calling code

Strict typing surfaces historical implicit coercions. Common patterns to fix:

```php
// bool to int (TINYINT columns: visible, position, reseller...)
$product->setVisible(true);     // TypeError if TINYINT
$product->setVisible(1);        // correct

// float to string (DECIMAL columns: price, discount, postage...)
$price->setPrice(29.99);        // TypeError
$price->setPrice('29.99');      // correct

// int to string (VARCHAR columns: view_id...)
$url->setViewId($product->getId());          // TypeError
$url->setViewId((string) $product->getId()); // correct

// SimpleXMLElement to string
$module->setTitle($xml->title);           // TypeError
$module->setTitle((string) $xml->title);  // correct

// Mixed to string (ConfigQuery::write, ModuleConfigQuery)
ConfigQuery::write('key', 42);    // internal TypeError
ConfigQuery::write('key', '42');  // correct
// (fixed in core — the cast is done internally)
```

### Renames caused by typing

Some methods that overrode Propel getters/setters with incompatible signatures were renamed:

| Old name | New name | Reason |
|----------|----------|--------|
| `Customer::setEmail($email, $force)` | `Customer::updateEmail($email, $force)` | Extra `$force` param incompatible with the Propel setter |
| `Cart::getDiscount($withTaxes, $country, $state)` | `Cart::getCalculatedDiscount(...)` | Extra params + return type `float` vs `?string` (DECIMAL) |
| `MetaData::getValue()` | `MetaData::getDeserializedValue()` | Return type `mixed` (post-unserialize) vs `?string` |
| `MetaData::setValue($v)` | `MetaData::setSerializableValue($v)` | Accepts `mixed` (serialized array/object) |

### Fork files changed for native typing

| File | Role |
|------|------|
| `src/Propel/Generator/Model/PropelTypes.php` | Maps `boolean→bool`, `double→float` via `getNativeTypeDeclaration()` |
| `src/Propel/Generator/Model/Column.php` | Helper `getNativeTypeDeclaration()` (routes to PropelTypes or typeHint) |
| `src/Propel/Generator/Builder/Om/ObjectBuilder.php` | Generates types on properties, getters, setters |

## Pitfalls

### Propel

- **`->save()` = immediate persist.** No `flush()`. Each save is an INSERT or UPDATE.
- **Singletons** `Translator::$instance` and `URL::$instance` must stay `?self = null` (fatal error in tests otherwise).
- **`#[Ignore]` on `static` methods** crashes the Symfony Serializer. Never do this.
- **Propel subprocess:** `PropelInitService` crashes when Propel is launched in a cold subprocess. Always boot `App\Kernel` in-process.
- **`Base/` classes are regenerated.** Never edit them manually.
- **`Collection` is no longer an iterator:** use `getIterator()`; the `current()`/`next()` methods are `@deprecated`.
- **Strict setter typing:** setters now have native PHP types. Passing a `bool` to a `?int` setter (TINYINT) or a `float` to a `?string` setter (DECIMAL) raises a `TypeError`. Always cast explicitly.
- **ENUM/SET are untyped:** ENUM/SET getters and properties have no native type (the getter returns a string, but Propel maps ENUM to int internally). Do not attempt to type them.
- **Stub overrides:** any stub that overrides a getter or setter from Base must match the exact signature (param type + return type `: static`). Otherwise a fatal "must be compatible" error occurs.
- **Property redeclaration:** a stub must never redeclare a property already defined in Base with a different type (for example, `protected $postage_tax = '0.00'` in `Order.php` crashed because Base declares `protected ?string $postage_tax = null`).
- **SimpleXMLElement:** XML properties must be cast to `(string)` before being passed to typed setters.

### Schema

- **`insert.sql`:** `active-front-template` must be `flexy` (FlexyBundle crashes on a missing directory otherwise).
- **Namespace in schema.xml** must match the module's Composer package.
- **Multiple FKs to the same table:** the `aggregate_column` behavior has a documented bug in this case.

### Database

- **DDEV:** the `db` user cannot CREATE arbitrary databases; use `db` as the database name.
- **Transaction nesting:** `ConnectionWrapper` supports nested transactions (depth counter).
- **Prepared statements:** cache is enabled by default (`PROPEL_ATTR_CACHE_PREPARES = true`).

### API Platform

- **Circular references:** use `excludedGroups` on `#[Relation]` to break loops.
- **`ApiResourcePropelTransformerService`** (823 lines) is the bridge core; it tracks depth/visited to avoid infinite recursion.
- **`OrderFilter`** is always applied last by `FilterExtension` to preserve JOIN types.

## Quick reference

### Commands

```bash
# Regenerate Propel models (after modifying schema.xml)

# On thelia/thelia (dev repo with bin/console):
ddev exec rm -rf var/propel/ var/cache/
ddev exec APP_ENV=dev php bin/console cache:clear

# On thelia-project (skeleton with Thelia):
ddev exec rm -rf var/propel/ var/cache/
ddev exec APP_ENV=dev php Thelia cache:clear

# PropelInitService regenerates automatically when the cache is stale.

# For tests: also generate the test env
ddev exec APP_ENV=test php Thelia cache:clear --no-warmup
```

### Tests in a thelia-project

Integration tests must register the Propel autoloader in `tests/bootstrap.php`:

```php
$loader = require dirname(__DIR__).'/vendor/autoload.php';
$environment = $_SERVER['APP_ENV'] ?? 'test';
$propelModelDir = dirname(__DIR__).'/var/propel/'.$environment.'/model';
if (is_dir($propelModelDir)) {
    $loader->addPsr4('', $propelModelDir);
}
```

Models live in `var/propel/{env}/model/` (not `var/cache/`). PHPStan `scanDirectories` and Psalm `extraFiles` in CI must point to `var/propel/dev/model`. Use a symlink `ln -sfn test var/propel/dev` when only the test env is available (CI).

### Key files at a glance

| Need | File |
|------|------|
| Add a table | `local/config/schema.xml` (core) or `Module/Config/schema.xml` |
| Add model logic | `core/lib/Thelia/Model/{Model}.php` (stub) |
| Add query methods | `core/lib/Thelia/Model/{Model}Query.php` (stub) |
| Create a persistence listener | `core/lib/Thelia/Action/{Entity}.php` |
| Available events | `core/lib/Thelia/Core/Event/TheliaEvents.php` |
| Create an API resource | `core/lib/Thelia/Api/Resource/{Entity}.php` |
| i18n query helpers | `core/lib/Thelia/Model/Tools/ModelCriteriaTools.php` |
| DB config | `core/lib/Thelia/Config/DatabaseConfigurationSource.php` |
| Propel init | `core/lib/Thelia/Core/Propel/PropelInitService.php` |
| Kernel (boots Propel) | `core/lib/Thelia/Core/TheliaKernel.php` |
| API Platform bridge | `core/lib/Thelia/Api/Bridge/Propel/Service/ApiResourcePropelTransformerService.php` |
| Loop base classes | `core/lib/Thelia/Core/Template/Element/BaseLoop.php` |
