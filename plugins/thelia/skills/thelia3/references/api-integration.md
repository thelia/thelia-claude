# API Platform 4.3 and DataAccessService - Thelia 3

> AP 4.3 standalone (`api-platform/symfony`), custom Propel bridge. All routes prefixed `/api` via `config/routes.yaml:12`. Lexik JWT 3.2.

## 1. `PropelResourceInterface` + `PropelResourceTrait`

(`core/lib/Thelia/Api/Resource/PropelResourceInterface.php:20`)

```php
interface PropelResourceInterface
{
    public function __get(string $property);
    public function setPropelModel(ActiveRecordInterface $propelModel): self;
    public function getPropelModel(): ?ActiveRecordInterface;
    public function getResourceAddons(): array;
    public function getResourceAddon(string $addonName): ?ResourceAddonInterface;
    public function setResourceAddon(string $addonName, ?ResourceAddonInterface $addon): self;
    public static function getPropelRelatedTableMap(): ?TableMap;
}
```

`PropelResourceTrait` (`PropelResourceTrait.php:22`) implements everything except `getPropelRelatedTableMap()` (abstract). Stores `$propelModel` and `$resourceAddons` marked `#[Ignore]`. Provides magic `__get/__isset/__set` for addons via their shortname.

Propel <-> Resource mapping handled by `ApiResourcePropelTransformerService::modelToResource()` (`Api/Bridge/Propel/Service/ApiResourcePropelTransformerService.php:56`) - reflection + `#[Relation]` + `#[Column]`.

```php
#[ApiResource(
    uriTemplate: '/admin/my-resources',
    operations: [new Get(), new GetCollection(), new Post(), new Put(), new Delete()],
    normalizationContext: ['groups' => ['admin:my:read']],
    denormalizationContext: ['groups' => ['admin:my:write']],
)]
#[ApiResource(
    uriTemplate: '/front/my-resources',
    operations: [new GetCollection(), new Get()],
    normalizationContext: ['groups' => ['front:my:read']],
)]
class MyResource implements PropelResourceInterface
{
    use PropelResourceTrait;

    #[Groups(['admin:my:read', 'front:my:read'])]
    public ?int $id = null;

    #[Groups(['admin:my:read', 'admin:my:write', 'front:my:read'])]
    public ?string $code = null;

    public static function getPropelRelatedTableMap(): ?TableMap
    {
        return new \MyModule\Model\Map\MyTableMap();
    }
}
```

**Trap**: `getPropelRelatedTableMap()` must NEVER return `null` on a concrete resource - `PropelCollectionProvider:45` NPE.

## 2. `AbstractTranslatableResource` (i18n)

(`AbstractTranslatableResource.php:17`)

```php
abstract class AbstractTranslatableResource implements PropelResourceInterface, TranslatableResourceInterface
{
    use PropelResourceTrait;
    public I18nCollection $i18ns; // keyed by locale ('fr_FR')
}
```

`TranslatableResourceInterface` requires: `setI18ns()`, `addI18n()`, `getI18ns()`, `static getI18nResourceClass(): string`.

```php
class Category extends AbstractTranslatableResource
{
    #[Groups([...])]
    public ?int $id = null;

    public static function getPropelRelatedTableMap(): ?TableMap { return new CategoryTableMap(); }
    public static function getI18nResourceClass(): string { return CategoryI18n::class; }
}

// MANDATORY: the i18n class MUST extend Thelia\Api\Resource\I18n
class CategoryI18n extends \Thelia\Api\Resource\I18n
{
    #[Groups([...])]
    public ?string $title = null;
    #[Groups([...])]
    public ?string $description = null;
}
```

**Mandatory rule**: a module's i18n class MUST `extends \Thelia\Api\Resource\I18n`. `AbstractTranslatableResource::addI18n()` declares `I18n $i18n` as a type hint - a `TypeError` is thrown at runtime on any i18n operation if the class does not inherit. Pattern: `class MyResourceI18n extends \Thelia\Api\Resource\I18n`.

Locale resolution:
- `EagerLoadingExtension` joins the i18n table for ALL active languages.
- `ResourceService::formatI18ns()` (`ResourceService.php:96`) reduces to the current locale (`LangService::getLocale()`).
- In Twig output, `i18ns` is flattened: `{{ category.title }}` (current locale).

## 3. Admin/front operations and groups

Two `#[ApiResource]` declarations on the same class (admin + front). Group convention: `{scope}:{resource}:{read|write}[:single]`. A `Get` single can have an additional `:read:single` group.

```php
#[ApiResource(
    uriTemplate: '/admin/categories',
    operations: [new Post(), new GetCollection()],
    normalizationContext: ['groups' => ['admin:category:read']],
    denormalizationContext: ['groups' => ['admin:category:write']],
)]
```

Built-in providers/processors (auto-assigned by `PropelResourceCollectionMetadataFactory::addDefaults()`, `:69`):
- `PropelCollectionProvider` - `GetCollection`
- `PropelItemProvider` - `Get/Put/Patch`
- `PropelPersistProcessor` - `Post/Put/Patch`
- `PropelRemoveProcessor` - `Delete`

## 4. `ResourceAddonInterface` - extend a native resource

(`ResourceAddonInterface.php:23`, `ResourceAddonTrait.php:23`)

Auto-tagged `thelia.api.resource.addon` (`TheliaKernel.php:476`). `RegisterApiResourceAddonPass` (`TheliaBundle.php:72`) collects by parent class in `Thelia.api.resource.addons[$parent][$shortName]`.

```php
interface ResourceAddonInterface
{
    public static function getResourceParent(): string;          // FQCN of host
    public static function getPropelRelatedTableMap(): ?TableMap;
    public static function extendQuery(ModelCriteria $query, ?Operation $operation, array $context): void;
    public function setContext(array $context): self;
    public function getContext(): array;
    public function buildFromModel(ActiveRecordInterface $ar, PropelResourceInterface $host): self;
    public function buildFromArray(array $data, PropelResourceInterface $host): self;
    public function doSave(ActiveRecordInterface $ar, PropelResourceInterface $host): void;
    public function doDelete(ActiveRecordInterface $ar, PropelResourceInterface $host): void;
}
```

```php
class CustomerCustomerFamily implements ResourceAddonInterface
{
    use ResourceAddonTrait;

    #[Groups(['admin:customer:read', 'admin:customer:write'])]
    public ?string $code = null;

    public static function getResourceParent(): string { return Customer::class; }
    public static function getPropelRelatedTableMap(): ?TableMap { return new CustomerCustomerFamilyTableMap(); }
}
```

Available automatically in JSON-LD under the shortname **raw PascalCase** (`ReflectionClass::getShortName()` cf `RegisterApiResourceAddonPass.php:37`): `{"CustomerCustomerFamily": {"code": "pro"}}`. Not camelCase. The JSON key = class short name as-is. `ResourceAddonTrait::extendQuery()` performs an auto LEFT JOIN via TableMap with columns prefixed `{AddonName}_`.

`ResourceAddonExtension` implements **both** interfaces (`QueryItemExtensionInterface` + `QueryCollectionExtensionInterface`) - the addon is joined and exposed **on both `Get` single and `GetCollection`**. The `#[Groups]` on addon properties control visibility per operation.

### Virtual column trap - camelCase / snake_case mismatch

The default `extendQuery()` from the trait generates SQL aliases `{AddonShortName}_{property_name}`. If a PHP property name contains an implicit underscore (e.g. `joinedAt` -> Propel stores it as `joined_at` in SQL), `buildFromModel()` reads the virtual column by the **PHP name**: it looks for `CustomerLoyaltyAddon_joinedAt`, but the query generated `CustomerLoyaltyAddon_joined_at`. **Silent mismatch**: the property stays `null` after hydration, with no error.

Symptoms: all fields with SQL underscore and PHP camelCase are empty in API output. Simple fields without transformation (`points`, `tier`, `code`) work.

**Fix**: override `extendQuery()` with explicit aliases aligned to PHP names:

```php
public static function extendQuery(ModelCriteria $query, ?Operation $operation, array $context): void
{
    $alias = (new \ReflectionClass(static::class))->getShortName();
    $query->useCustomerLoyaltyQuery(null, \Criteria::LEFT_JOIN)
        ->withColumn("{$alias}.points", "{$alias}_points")
        ->withColumn("{$alias}.tier", "{$alias}_tier")
        ->withColumn("{$alias}.joined_at", "{$alias}_joinedAt")  // explicit camelCase alias
        ->endUse();
}
```

**Traps**:
- JSON-LD shortname = raw `getShortName()` (PascalCase). Choose the class name carefully (it becomes the public key).
- `findOrCreateModel` filters by parent `id` - override `doSave()` if the FK differs.
- `#[Groups]` on addon must reference the parent's groups.
- **Virtual column mismatch** - override `extendQuery()` if a PHP camelCase property maps to an SQL snake_case column (see above).

## 5. Custom Thelia filters

All in `core/lib/Thelia/Api/Bridge/Propel/Filter/`, inherit `AbstractFilter`. **Not** the AP 4.1+ `QueryParameter` (coupled to Doctrine).

| Class | URL param | Options |
|---|---|---|
| `SearchFilter` | `?prop=val` or `?prop[]=v` | `strategy`: `exact`(default), `partial`, `start`, `end`, `word_start` |
| `OrderFilter` | `?order[prop]=asc\|desc` | `default_direction` per property |
| `BooleanFilter` | `?prop=true\|false\|1\|0` | - |
| `RangeFilter` | `?prop[gt\|gte\|lt\|lte]=v` | - |
| `NotInFilter` | `?not_in[prop]=["v1","v2"]` | - |
| `DateFilter` | `?prop[before\|after\|strictly_before\|strictly_after]=date` | `exclude_null` (default) / `include_null_*` |

```php
use ApiPlatform\Metadata\ApiFilter;
use Thelia\Api\Bridge\Propel\Filter\{SearchFilter, OrderFilter, BooleanFilter};

#[ApiFilter(filterClass: SearchFilter::class, properties: ['title' => SearchFilter::STRATEGY_PARTIAL])]
#[ApiFilter(filterClass: OrderFilter::class, properties: ['position' => ['default_direction' => 'ASC']])]
#[ApiFilter(filterClass: BooleanFilter::class, properties: ['visible'])]
class Category extends AbstractTranslatableResource { /* ... */ }
```

i18n property: `SearchFilter` detects it automatically via `TranslatableResourceInterface` (`AbstractFilter.php:139`), alias `{table}_lang_{locale}.{property}`.

`FilterExtension` (`Api/Bridge/Propel/Extension/FilterExtension.php:24`) applies filters via `ServiceLocator` tag `thelia.api.propel.filter`. `OrderFilter` is deferred after others (JOIN conflicts, `:49`).

## 6. Operation security

Two levels:

**1. Symfony `access_control`** (`TheliaKernel.php`, injected by Reflection on `extensionConfigs`):
- `/api/front/login`, `/api/admin/login`, `/api/docs`, `/api/{front,admin}/token/refresh` -> PUBLIC_ACCESS
- `/api/admin/**` -> `ROLE_ADMIN`
- `/api/front/account/**` -> `ROLE_CUSTOMER`
- Remaining `/api/front/**` -> **NOT PROTECTED BY DEFAULT**

**2. `security:` ExpressionLanguage on the operation**:
- Evaluated AFTER `fetchData`, on the loaded `object`.
- `user` variable = admin or customer depending on `isAdminRoute()` (`MetadataService.php:104`).
- Examples: `Order` `security: 'object.customer.getId() == user.getId()'`, `Cart` `security: 'is_granted("ROLE_CUSTOMER") and object.customer.getId() == user.getId()'`.

`MetadataService::canUserAccessResource()` (`MetadataService.php:64`) delegates. On failure: log + `return null` (no exception in prod).

JWT Lexik 3.2: firewalls injected dynamically by the kernel. Login routes `POST /api/{front,admin}/login` return `{"token": "...", "refresh_token": "...", "refresh_token_ttl": 2592000}`. Access token TTL configurable via `JWT_TOKEN_TTL` (default 3600s), refresh token via `JWT_REFRESH_TOKEN_TTL` (default 30 days).

**Refresh flow**: `POST /api/{front,admin}/token/refresh` with `{"refresh_token": "..."}` returns a new access + refresh pair. Single-use on the `RefreshTokenService` side (cache-backed via `thelia.cache`), so replay -> 401. Token scope (admin vs customer) is checked on the endpoint, so a customer refresh token sent to `/api/admin/token/refresh` -> 401.

```php
#[ApiResource(
    uriTemplate: '/front/orders/{id}',
    operations: [
        new Get(security: 'object.customer.getId() == user.getId()'),
    ],
)]
```

### 6.0 Front `Customer` - mandatory ownership

`core/lib/Thelia/Api/Resource/Customer.php` declares `security: 'is_granted("ROLE_CUSTOMER") and object.getId() == user.getId()'` on the `Get` and `Put` `/front/account/customers/{id}` operations. The `access_control` `/api/front/account/**` -> `ROLE_CUSTOMER` is not enough to prevent a customer from reading or modifying another customer's data via an arbitrary id: the ownership expression closes the IDOR.

Implications for a module that extends Customer via `ResourceAddon`:
- Data tagged `front:customer:read:single` (or `front:customer:read`) remains exposed only to the owner customer, thanks to the expression already in place on `Get`.
- For any new sensitive endpoint, **always** add a `security:` ownership expression on the operation, without relying solely on path-based `access_control`.

Reference pattern:
```php
new Get(
    uriTemplate: '/front/account/customers/{id}',
    security: 'is_granted("ROLE_CUSTOMER") and object.getId() == user.getId()',
),
```

### 6.1 IDOR `GetCollection` front - resource linked to customer via join table

`CustomerGetCollectionExtension` (`core/lib/Thelia/Api/Bridge/Propel/Extension/CustomerGetCollectionExtension.php`) applies `filterByCustomer($user)` on front resources that have a **direct FK** to customer. For resources linked indirectly (e.g. `WishlistItem` -> `Wishlist` -> `Customer`, `OrderProduct` -> `Order` -> `Customer`), you must declare `extraProperties: ['usesForCustomer' => ['joinTableProperty']]` on the front `GetCollection`, otherwise **IDOR**: any authenticated customer can see all customers' data.

```php
// WishlistItem - linked to customer via Wishlist (indirect FK)
#[ApiResource(
    uriTemplate: '/front/account/wishlist_items',
    operations: [
        new GetCollection(
            security: 'is_granted("ROLE_CUSTOMER")',
            extraProperties: ['usesForCustomer' => ['wishlist']], // join via wishlist.customer_id
        ),
        new Get(security: 'is_granted("ROLE_CUSTOMER") and object.wishlist.customer.getId() == user.getId()'),
    ],
)]
```

Real core pattern: `OrderProduct` (`core/lib/Thelia/Api/Resource/OrderProduct.php:67`) `extraProperties: ['usesForCustomer' => ['order']]`.

**Recognized `extraProperties` keys in core**: `usesForCustomer` (CustomerGetCollectionExtension). **Any other key is silently ignored**. To scope a collection by a URI variable NOT related to the customer (e.g. `productId` in `/front/products/{productId}/reviews`), use a dedicated `QueryCollectionExtensionInterface` that reads `$context['uri_variables'][$varName]`. See section 7.3.

### 6.2 Front `Post` - verifying parent resource ownership

A front relational resource (`WishlistItem`, `Address`, `OrderComment`...) created via `Post` accepts a parent IRI in the payload. `is_granted("ROLE_CUSTOMER")` alone is insufficient - a customer can create an item attached to another customer's parent resource by passing their IRI.

Three solutions:

1. **Simple validation via `security:` expression** on the request value (limited: no access to the loaded parent object in DB):
   ```php
   new Post(security: 'is_granted("ROLE_CUSTOMER") and request.get("wishlist") starts with "/api/front/account/wishlists/"')
   ```
2. **Custom `PropelPersistProcessor`** that loads the parent resource before `save()` and checks its ownership.
3. **`QueryCollectionExtensionInterface`** applied to the parent resource (to constrain acceptable parent IRIs).

Solution 2 is recommended when the logic is non-trivial: single authority, testable.

## 7. Customization - providers / processors / extensions

Preferred customization: `QueryCollectionExtensionInterface` / `QueryItemExtensionInterface` (auto-tagged `thelia.api.propel.query_extension.collection|item`). Lighter than a full custom provider.

```php
class FilterByVisibilityExtension implements QueryCollectionExtensionInterface
{
    public function applyToCollection(ModelCriteria $query, string $resourceClass, ?Operation $operation = null, array $context = []): void
    {
        if ($resourceClass !== Product::class) return;
        $query->filterByVisible(true);
    }
}
```

Custom provider: declare `provider: MyProvider::class` on the operation + implement `ProviderInterface`.

### 7.1 Propel bridge attributes (`Thelia\Api\Bridge\Propel\Attribute\*`)

Three PHP 8 attributes specific to the Propel <-> API Platform bridge. **Use systematically** on resources that have relations or FKs with differing names.

#### `#[Relation]` - a property pointing to another Resource

(`Thelia\Api\Bridge\Propel\Attribute\Relation`, target = TARGET_PROPERTY)

Full signature:

```php
#[Relation(
    string $targetResource,           // FQCN of target Resource (REQUIRED)
    ?string $relationAlias = null,    // Propel alias if different from class name (rare)
    ?array $propertyGroups = [],      // groups applied to sub-properties of the relation
    ?bool $forceJoin = null,          // force JOIN even if no group match
    ?array $excludedGroups = [],      // groups for which the relation is NOT loaded
)]
```

Real core examples:

```php
// Simple ManyToOne relation (CartItem -> Product, Cart, PSE)
// core/lib/Thelia/Api/Resource/CartItem.php:95-103
#[Relation(targetResource: Product::class)]
public ?Product $product = null;

#[Relation(targetResource: Cart::class)]
public ?Cart $cart = null;

#[Relation(targetResource: ProductSaleElements::class)]
public ?ProductSaleElements $productSaleElements = null;
```

```php
// OneToMany relation (collection)
// core/lib/Thelia/Api/Resource/Customer.php:207
#[Relation(targetResource: Address::class)]
#[Groups([self::GROUP_ADMIN_READ_SINGLE, self::GROUP_ADMIN_WRITE])]
public array $addresses = [];
```

```php
// Relation with relationAlias (Propel getter has a different name)
// core/lib/Thelia/Api/Resource/Customer.php:137
#[Relation(targetResource: Lang::class, relationAlias: 'LangModel')]
public ?Lang $lang = null;
// Why: on the Propel Customer model, getLang() already exists for something else
// so Thelia uses getLangModel(); relationAlias tells it which getter to call.
```

```php
// Relation with excludedGroups (avoid infinite cycles or unnecessary loads)
// core/lib/Thelia/Api/Resource/ContentFolder.php:53
#[Relation(targetResource: Content::class, excludedGroups: [
    Product::GROUP_ADMIN_READ,
    Product::GROUP_FRONT_READ,
])]
public ?Content $content = null;
// The relation will NOT be loaded when serializing with a Product group.
```

#### `#[Column]` - override Propel mapping for a property

(`Thelia\Api\Bridge\Propel\Attribute\Column`, target = TARGET_PROPERTY)

```php
#[Column(
    ?string $propelFieldName = null,   // Propel field name if different from PHP property
    ?string $propelSetter = null,      // Propel setter to call (override auto)
    ?string $propelGetter = null,      // Propel getter to call (override auto)
    ?string $propelQueryFilter = null, // filterByXxx method for queries
)]
```

Use case: 99% of the time, a **FK pointing to an object** but whose Propel setter expects an ID, not an object.

```php
// core/lib/Thelia/Api/Resource/Customer.php:127-135
// Customer.title_id (INT FK in DB) <-> Customer Propel: setTitleId(int) / getCustomerTitle(): CustomerTitle
// The API exposes a CustomerTitle-typed property (object) - but persistence needs to call setTitleId
#[Relation(targetResource: CustomerTitle::class)]
#[Column(propelSetter: 'setTitleId')]
public CustomerTitle $customerTitle;
```

```php
// Property name != Propel field (rarer case)
// core/lib/Thelia/Api/Resource/Product.php:225
#[Column(propelFieldName: 'productSaleElementss')]  // double 's' in Propel
public array $productSaleElementss = [];
```

```php
// Order: 5 FKs to Module/Address/Status declared this way
// core/lib/Thelia/Api/Resource/Order.php:205-231
#[Column(propelSetter: 'setInvoiceOrderAddressId')] public OrderAddress $invoiceOrderAddress;
#[Column(propelSetter: 'setDeliveryOrderAddressId')] public OrderAddress $deliveryOrderAddress;
#[Column(propelSetter: 'setPaymentModuleId')] public Module $paymentModule;
#[Column(propelSetter: 'setDeliveryModuleId')] public Module $deliveryModule;
#[Column(propelSetter: 'setStatusId')] public OrderStatus $orderStatus;
```

**Practical rule**: whenever a property is typed as an object (`Customer $customer`, `Country $country`, `Lang $lang`...) and the underlying table has a FK `xxx_id`, add `#[Column(propelSetter: 'setXxxId')]`. Without it, `PropelPersistProcessor` will try `$model->setCustomer($obj)` which may not exist.

#### `#[CompositeIdentifiers]` - composite primary keys

(`Thelia\Api\Bridge\Propel\Attribute\CompositeIdentifiers`, target = TARGET_CLASS)

For join tables (ProductCategory, ContentFolder, AttributeCombination, ProductPrice...) that have no auto-increment ID but a composite PK.

```php
// core/lib/Thelia/Api/Resource/ProductCategory.php:44
#[CompositeIdentifiers(['category', 'product'])]
class ProductCategory implements PropelResourceInterface { /* ... */ }

// core/lib/Thelia/Api/Resource/ContentFolder.php:42
#[CompositeIdentifiers(['content', 'folder'])]
class ContentFolder implements PropelResourceInterface { /* ... */ }

// core/lib/Thelia/Api/Resource/AttributeCombination.php:44
#[CompositeIdentifiers(['productSaleElements', 'attributeAv', 'attribute'])]
class AttributeCombination implements PropelResourceInterface { /* ... */ }

// core/lib/Thelia/Api/Resource/ProductPrice.php:45
#[CompositeIdentifiers(['productSaleElements', 'currency'])]
class ProductPrice implements PropelResourceInterface { /* ... */ }
```

The keys passed are **resource property names** (not SQL columns). Each must be a `#[Relation]` declared in the class. The resource IRI will be `/admin/product_categories/{categoryId}-{productId}`.

### 7.2 Native Resources list (FQCNs reusable in `targetResource:`)

Core resources in `Thelia\Api\Resource\*` usable from a module via `#[Relation(targetResource: ...)]`:

| FQCN | Resource | Typical use |
|---|---|---|
| `Thelia\Api\Resource\Customer` | customer | extension via ResourceAddon |
| `Thelia\Api\Resource\Address` | customer address | - |
| `Thelia\Api\Resource\CustomerTitle` | title (Mr/Ms) | customer FK |
| `Thelia\Api\Resource\Lang` | language | customer/order FK |
| `Thelia\Api\Resource\Country` | country | shipping/billing |
| `Thelia\Api\Resource\State` | state/region | US/CA/AU shipping |
| `Thelia\Api\Resource\Currency` | currency | pricing |
| `Thelia\Api\Resource\Product` | product | catalog |
| `Thelia\Api\Resource\ProductSaleElements` (PSE) | product variant | pricing/stock |
| `Thelia\Api\Resource\ProductImage` / `ProductDocument` | product media | - |
| `Thelia\Api\Resource\Category` | category | catalog |
| `Thelia\Api\Resource\Brand` | brand | - |
| `Thelia\Api\Resource\Attribute` / `AttributeAv` | PSE attributes | combinations |
| `Thelia\Api\Resource\Feature` / `FeatureAv` | product features | - |
| `Thelia\Api\Resource\Order` | order | - |
| `Thelia\Api\Resource\OrderProduct` | order line | - |
| `Thelia\Api\Resource\OrderStatus` | order status | - |
| `Thelia\Api\Resource\OrderAddress` | order address snapshot | - |
| `Thelia\Api\Resource\Cart` / `CartItem` | cart | - |
| `Thelia\Api\Resource\Content` / `Folder` | CMS pages | - |
| `Thelia\Api\Resource\Coupon` | promotion | - |
| `Thelia\Api\Resource\TaxRule` | tax rule | shipping/product |
| `Thelia\Api\Resource\Module` / `ModuleConfig` | thelia modules | - |
| `Thelia\Api\Resource\Admin` | back-office admin | - |
| `Thelia\Api\Resource\Config` | store parameter | - |

Always verify a FQCN exists in `core/lib/Thelia/Api/Resource/` before using it.

**Trap**: `PropelPersistProcessor` reads `requestStack->getMainRequest()->getContent()` for addons (`:177`) -> **exception in CLI**.

### 7.3 `uriVariables` with a non-identifying path variable (scoped collection)

For a `GetCollection` whose URI template contains a variable that **is NOT the resource identifier** (e.g. `/front/products/{productId}/reviews` where `productId` is a scope parameter, not the id of a `ProductReview`), declare `uriVariables` with an explicit `Link`. Without it, AP4's `UriVariablesResolverTrait` may throw `InvalidIdentifierException` depending on the version, and scoping remains fragile.

```php
use ApiPlatform\Metadata\Link;

#[ApiResource(
    operations: [
        new GetCollection(
            uriTemplate: '/front/products/{productId}/reviews',
            uriVariables: [
                'productId' => new Link(fromClass: Product::class, identifiers: ['id']),
            ],
        ),
    ],
)]
```

`$context['uri_variables']['productId']` is then resolved and available in `QueryCollectionExtensionInterface::applyToCollection()`:

```php
public function applyToCollection(ModelCriteria $query, ...): void
{
    if (Review::class !== $resourceClass) { return; }
    $productId = $context['uri_variables']['productId'] ?? null;
    if (null !== $productId) {
        $query->filterByProductId((int) $productId);
    }
}
```

**Without `new Link(...)`** -> behavior not guaranteed, scoping potentially absent, IDOR possible if the extension is not wired up.

### 7.4 Custom `Post` operation on a Propel resource - PlaceholderAction and `write: false` traps

A `Post` operation triggers the full AP4 pipeline by default: deserialize -> validate -> read -> write (= `PropelPersistProcessor`). For a **functional operation** (duplicate, replace, regenerate...), these steps must be neutralized to avoid side effects.

**Case 1 - business operation that does NOT consume a payload (e.g. `/admin/block_groups/{id}/duplicate`)**:

```php
new Post(
    uriTemplate: '/admin/block_groups/{id}/duplicate',
    processor: BlockGroupDuplicateProcessor::class,
    read: false,
    validate: false,
),
```

`read: false` prevents AP from loading the object via the Provider (the source id comes from the URI, the processor loads it itself). `validate: false` skips the Validator (the source resource is not populated).

**Do not set `deserialize: false` or `input: false`**: AP4 continues using `PlaceholderAction` which calls `$this->resourceClass()`. If deserialization is cut, the processor receives `mixed $data` untyped and the URI key is consumed but the object is never hydrated. With `read: false, validate: false` only, the pipeline remains consistent and the Processor receives a minimal `BlockGroup` object (default constructor).

**Test trap**: an empty JSON body raises `Syntax error` (400). Send a non-empty payload even if ignored by the Processor:
```php
$response = $this->jsonRequest('POST', '/api/admin/block_groups/'.$id.'/duplicate', ['source' => $id], $token);
```

**Case 2 - operation consuming a multipart file (e.g. `/admin/library_images/{id}/replace`)**:

```php
new Post(
    uriTemplate: '/admin/library_images/{id}/replace',
    inputFormats: ['multipart' => ['multipart/form-data']],
    controller: LibraryImageReplaceController::class,
    deserialize: false,
    validate: false,
    read: false,
    write: false,
),
```

`controller: ...` bypasses the AP chain with a Symfony controller. `deserialize: false` prevents AP from attempting the multipart-denormalizer (which cannot hydrate an `AbstractTranslatableResource`). `write: false` is **CRITICAL**: without it, `PropelPersistProcessor` re-tries to insert the object returned by the controller -> `PropelException("Cannot insert a value for auto-increment primary key (...)")`. Keep `read: false` when `{id}` is present (the controller uses it) to avoid a useless round-trip via PropelItemProvider.

The invokable controller returns the AP resource directly:
```php
return $this->apiResourceService->modelToResource(
    resourceClass: LibraryImage::class,
    propelModel: $newPropelModel,
    context: $request->attributes->get('_api_operation')->getNormalizationContext() ?? [],
    withAddon: false,
);
```

AP4 then serializes the returned value according to `normalizationContext` (admin/front groups).

## 8. DataAccessService - internal AP bypass

`Thelia\Api\Service\DataAccess\DataAccessService` (`DataAccessService.php:22`):

```php
public function resources(string $path, array $parameters = [], ?string $format = null): object|array|null;
public function loop(string $loopName, string $loopType, array $params = []): array;     // @deprecated
public function loopCount(string $loopType, array $params = []): int;                    // @deprecated
```

`resources()` trace (NO HTTP socket):
```
ResourceService::resources()
  -> RequestBuilderService::createApiRequest()    # synthetic Request
  -> RouteMatcherService::matchRoute()
  -> OperationProviderService::getOperation()
  -> ContextBuilderService::buildContext()        # filters, groups
  -> DataProviderService::fetchData()             # PropelCollectionProvider/PropelItemProvider
    -> extensions (FilterExtension, EagerLoadingExtension, PaginationExtension, ResourceAddonExtension)
    -> ApiResourcePropelTransformerService::modelToResource()
  -> AccessCheckerService::checkUserAccess()      # security: expression
  -> NormalizerService::normalizeData()
  -> formatI18ns()                                # flattened locale
```

Format: `null` (default) = normalized PHP array. `'jsonld'` = Hydra (`@context`, `hydra:totalItems`, `hydra:member`). Pagination: `itemsPerPage` + `page` in `$parameters`.

`AttributeAccessService` - `attribute{Type}($name)` methods: `Admin`, `Customer`, `Product`, `Category`, `Content`, `Folder`, `Brand`, `Currency`, `Country`, `Cart`, `Coupon`, `Lang`, `Config`.

**Critical CLI trap**: `RequestBuilderService` throws `RuntimeException` if `getMainRequest()` is null (`AttributeAccessService.php:441-445`). `resources()` AND `attr()` are **unusable in CLI**.

**Critical mutation trap**: `DataAccessService::resources()` is ONLY a READ layer (`Get` / `GetCollection`). `RequestBuilderService::createApiRequest()` (`RequestBuilderService.php:31`) always sets the HTTP method to `GET`. To trigger a `Post` / `Patch` / `Delete` from a LiveComponent or service:

1. **Recommended in LiveComponent**: inject and call the Processor directly (`PropelPersistProcessor` or your decorator Processor) with the AP object built manually. Faster, explicit IDOR validation.
2. **E2E tests only**: send a real request via `KernelBrowser`.

**NEVER use `resources()` for mutations** - silent, persistence not executed, misleading success flash.

PHP pattern in LiveComponent:
```php
public function __construct(private DataAccessService $das) {}

public function getProducts(): array
{
    return $this->das->resources('/api/front/products', [
        'productCategories.category.id' => $this->categoryId,
        'itemsPerPage' => 3,
        'not_in[id]' => $this->productIdsToIgnore,
    ]);
}
```

## 9. Thelia endpoints (summary)

| Endpoint | Default access | Operations |
|---|---|---|
| `POST /api/admin/login` | Public | Returns `{"token": "..."}` |
| `POST /api/front/login` | Public | Returns `{"token": "..."}` |
| `/api/admin/**` | `ROLE_ADMIN` | Full CRUD |
| `/api/front/account/**` | `ROLE_CUSTOMER` | Private customer endpoints |
| `/api/front/**` (other) | **Public** | Read only (by default) |
| `/api/docs` | Public | OpenAPI / Swagger UI |

Any module exposing private data on `/front/xxx` (outside `/account/`) MUST add explicit `security:` on its operations.

## 10. Traps

| Trap | Fix |
|---|---|
| `resources()` / `attr()` in CLI | guard / fallback / avoid in CLI |
| `/api/front/**` routes public by default | explicit `security:` on operation |
| `PropelPersistProcessor` reads body in CLI | do not write API in CLI |
| `getPropelRelatedTableMap()` returns null | always `new XxxTableMap()` |
| `#[Groups]` on addon does not match parent | parent groups required on addon properties |
| i18n filter without alias | `SearchFilter` handles automatically via `TranslatableResourceInterface` |
| JOIN conflict with `OrderFilter` | applied after other filters - order matters |
| `JwtDecorator` - OpenAPI login doc | decorator to extend for custom endpoints |
| i18n class without `extends I18n` | TypeError at runtime -> always `extends \Thelia\Api\Resource\I18n` |
| IDOR front collection via indirect FK | `extraProperties: ['usesForCustomer' => ['joinTable']]` |
| Front `Post` without parent ownership check | `security:` expression OR custom PersistProcessor |
