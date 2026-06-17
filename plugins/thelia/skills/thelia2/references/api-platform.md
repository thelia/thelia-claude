# Thelia 2.6 -- API Platform 3.4 + Propel Bridge

> Source: `core/lib/Thelia/Api/`, `core/lib/Thelia/Api/Bridge/Propel/`. AP version 3.4 (bundle `ApiPlatform\Symfony\Bundle\ApiPlatformBundle`). Single format JSON-LD.

## 1. Bootstrap

- Bundle: `ApiPlatform\Symfony\Bundle\ApiPlatformBundle` (`config/bundles.php:5`).
- Config: `config/packages/api_platform.yaml` -- `formats: jsonld`, `stateless: true`, `use_symfony_listeners: true`, `rfc_7807_compliant_errors: true`, `keep_legacy_inflector: false`.
- Routes: `config/routes/api_platform.yaml` -- prefix `/api`.
- Resource mapping: INJECTED IN PHP, not YAML (`core/lib/Thelia/Config/Resources/services.php:79-103`) -- scans `THELIA_LIB/Api/Resource` + `{module}/Api/Resource/` of active modules.
- Single format: **JSON-LD** (`application/ld+json`). No pure JSON, no HAL, no JSON:API.

## 2. AP 3.4 -- important limits

**What does NOT exist in AP 3.4 (and therefore not in T2.6):**

- `QueryParameter` system (AP 4.1+) -- continue using `#[ApiFilter]`.
- `Metadata Mutators` (AP 4.2+) -- no API for modifying resource metadata.
- `JsonStreamer` (AP 4.2 / SF 7.3) -- no serialization streaming.
- `ObjectMapper` (SF 7.3) -- no native DTO <-> entity mapping.
- `ExistsFilter` native AP -- no Propel equivalent (partially addressable with `BooleanFilter`).
- `NumericFilter` native AP -- not ported (partially covered by `RangeFilter`).
- **Native Doctrine AP filters** (`ApiPlatform\Doctrine\*Filter`): INCOMPATIBLE on Propel resources (Doctrine QueryBuilder != Propel ModelCriteria) -> runtime crash. **Block in review.**

## 3. 5 Propel Bridge decorators

| AP target | Mechanism | File |
|---|---|---|
| `api_platform.metadata.resource.metadata_collection_factory` | XML `decorates=` priority 40 | `Config/Resources/config.xml:273-278` + `Bridge/Propel/MetaData/PropelResourceCollectionMetadataFactory.php` |
| `api_platform.symfony.iri_converter` | `#[AsDecorator]` | `Bridge/Propel/Routing/IriConverter.php:26` |
| `api_platform.serializer.mapping.class_metadata_factory` | `#[AsDecorator]` | `Bridge/Propel/Loader/ClassMetaDataFactory.php:23` |
| `api_platform.metadata.property.metadata_factory.serializer` | `#[AsDecorator]` | `Bridge/Propel/MetaData/Property/PropelPropertyMetadataFactory.php:23` |
| `api_platform.openapi.factory` | `#[AsDecorator]` | `Bridge/Propel/OpenApiDecorator/JwtDecorator.php:23` |

## 4. Pivot interfaces / classes

- **`PropelResourceInterface`** (`Api/Resource/PropelResourceInterface.php:19`): contract `setPropelModel/getPropelModel/getResourceAddons/getPropelRelatedTableMap` static. **No `getId()` in the interface** -- convention per resource.
- **`PropelResourceTrait`** (`Api/Resource/PropelResourceTrait.php`): default implementation. **Always `use PropelResourceTrait`** otherwise `__get()` is missing -> `NoSuchPropertyException` on addons.
- **`AbstractTranslatableResource`** (`Api/Resource/AbstractTranslatableResource.php:15`): extends `PropelResourceInterface, TranslatableResourceInterface`, embeds `I18nCollection $i18ns`. Concrete I18n classes (`CategoryI18n`, `BrandI18n`, `ProductI18n`, `FolderI18n`, `ContentI18n`, `ModuleConfigI18n`) `extends I18n`.
- **`ResourceAddonInterface`** (`Api/Resource/ResourceAddonInterface.php`): pattern for extending a native resource from a module.

## 4bis. CRITICAL PITFALL -- Folder `Api/Resource/` (not `Resource/`)

The AP bridge scans **only** `{module}/Api/Resource/` (exact case, `services.php:88` -> `$module->getAbsoluteBaseDir().'/Api/Resource'`). A class placed in `{module}/Resource/` (without `Api/` prefix):

- is **invisible** to the AP bridge
- generates **no endpoint**
- raises **no error**, writes **no log**
- functional tests get a silent 404

**Always**:
- Folder: `{module}/Api/Resource/`
- Namespace: `{Module}\Api\Resource`
- Exclude from DI scan: `__DIR__.'/Api/Resource/*'` (not `__DIR__.'/Resource/*'`) in `configureServices()`

## 5. Complete `PropelResourceInterface` pattern

```php
<?php
declare(strict_types=1);

namespace MyModule\Api\Resource;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\Post;
use ApiPlatform\Metadata\Put;
use ApiPlatform\Metadata\Delete;
use Propel\Runtime\Map\TableMap;
use Symfony\Component\Serializer\Attribute\Groups;
use Thelia\Api\Resource\PropelResourceInterface;
use Thelia\Api\Resource\PropelResourceTrait;

#[ApiResource(
    operations: [
        new GetCollection(uriTemplate: '/admin/items'),
        // Override REQUIRED to activate GROUP_ADMIN_READ_SINGLE on Get single
        new Get(
            uriTemplate: '/admin/items/{id}',
            normalizationContext: ['groups' => [self::GROUP_ADMIN_READ, self::GROUP_ADMIN_READ_SINGLE]],
        ),
        new Post(uriTemplate: '/admin/items'),
        new Put(uriTemplate: '/admin/items/{id}'),
        new Delete(uriTemplate: '/admin/items/{id}'),
    ],
    normalizationContext: ['groups' => [self::GROUP_ADMIN_READ]],
    denormalizationContext: ['groups' => [self::GROUP_ADMIN_WRITE]],
)]
final class Item implements PropelResourceInterface
{
    use PropelResourceTrait;

    public const GROUP_ADMIN_READ        = 'admin:item:read';
    public const GROUP_ADMIN_READ_SINGLE = 'admin:item:read:single';
    public const GROUP_ADMIN_WRITE       = 'admin:item:write';

    #[Groups([self::GROUP_ADMIN_READ])]
    public ?int $id = null;

    #[Groups([self::GROUP_ADMIN_READ, self::GROUP_ADMIN_WRITE])]
    public ?string $title = null;

    public static function getPropelRelatedTableMap(): ?TableMap
    {
        return \MyModule\Model\Map\ItemTableMap::getTableMap();
    }
}
```

## 6. `ResourceAddonInterface` pattern

```php
namespace MyModule\Api\Resource;

use Propel\Runtime\Map\TableMap;
use Thelia\Api\Resource\ResourceAddonInterface;
use Thelia\Api\Resource\ResourceAddonTrait;
use Thelia\Api\Resource\Product;

final class CustomProductData implements ResourceAddonInterface
{
    use ResourceAddonTrait;

    public ?string $customField = null;

    public static function getResourceParent(): string { return Product::class; }

    public static function getPropelRelatedTableMap(): ?TableMap
    {
        return \MyModule\Model\Map\CustomProductDataTableMap::getTableMap();
    }
}
```

Auto-tagged via `registerForAutoconfiguration(ResourceAddonInterface::class)` -> tag `thelia.api.resource.addon` -> `RegisterApiResourceAddonPass` (`Compiler/RegisterApiResourceAddonPass.php:35`) collects into param `Thelia.api.resource.addons[Product::class]['CustomProductData'] = CustomProductData::class`.

## 7. Propel Bridge attributes -- signatures + 5 real examples

```php
#[\Attribute(\Attribute::TARGET_PROPERTY)]
class Relation { __construct(string $targetResource, ?string $relationAlias = null, ?array $propertyGroups = []) }

#[\Attribute(\Attribute::TARGET_PROPERTY)]
class Column   { __construct(?string $propelFieldName = null, ?string $propelSetter = null, ?string $propelGetter = null, ?string $propelQueryFilter = null) }

#[\Attribute(\Attribute::TARGET_CLASS)]
class CompositeIdentifiers { __construct(array $keys) }
```

**Note**: all properties of the 3 attributes are `private`. Read via Reflection (`$attribute->newInstance()`).

### Example 1 -- simple `#[Relation]` (`AttributeAv.php:91`)

```php
#[Relation(targetResource: Attribute::class)]
public Attribute $attribute;
```

### Example 2 -- `#[Relation]` with `relationAlias` for ambiguous FK (`Order.php:190`)

```php
#[Relation(targetResource: OrderAddress::class, relationAlias: 'OrderAddressRelatedByInvoiceOrderAddressId')]
#[Column(propelSetter: 'setInvoiceOrderAddressId')]
public OrderAddress $invoiceOrderAddress;
```

### Example 3 -- `#[Column(propelFieldName:)]` for collection (`Product.php:181`)

```php
#[Column(propelFieldName: 'productSaleElementss')]
#[Relation(targetResource: ProductSaleElements::class)]
public array $productSaleElements;
```

### Example 4 -- `#[CompositeIdentifiers]` junction table (`AttributeCombination.php:42`)

```php
#[CompositeIdentifiers(['productSaleElements', 'attributeAv', 'attribute'])]
class AttributeCombination implements PropelResourceInterface
```

URI: `/admin/attribute_combinations/{productSaleElements}/attribute_av/{attributeAv}`. All identifiers must have `getId()`, otherwise IRI is silently `'undefined_iri'` (SIGNAL-11).

### Example 5 -- `#[Column(propelSetter)]` for writing FK directly (`Customer.php:118-126`)

```php
#[Relation(targetResource: CustomerTitle::class)]
#[Column(propelSetter: 'setTitleId')]
public CustomerTitle $customerTitle;
```

## 8. 7 custom Propel filters

Auto-tagged: `FilterInterface` (Thelia, `Bridge/Propel/Filter/FilterInterface.php`) -> `thelia.api.propel.filter` (`Thelia.php:480`).

| Class | Strategy / usage | Example ApiFilter |
|---|---|---|
| `AbstractFilter` | abstract base | n/a |
| `SearchFilter` | strategies `exact`, `partial`, `start`, `end`, `word_start`; nested relations via `.` | `#[ApiFilter(SearchFilter::class, properties: ['ref', 'title' => 'word_start', 'customer.id' => 'exact'])]` |
| `OrderFilter` | `?order[prop]=ASC\|DESC`; option `default_direction` | `#[ApiFilter(OrderFilter::class, properties: ['createdAt', 'ref'])]` |
| `BooleanFilter` | `filter_var FILTER_VALIDATE_BOOLEAN` | `#[ApiFilter(BooleanFilter::class, properties: ['visible'])]` |
| `DateFilter` | `before/strictly_before/after/strictly_after` + null strategies (EXCLUDE_NULL, INCLUDE_NULL_BEFORE, etc.) | `#[ApiFilter(DateFilter::class, properties: ['createdAt' => DateFilter::INCLUDE_NULL_BEFORE_AND_AFTER])]` |
| `RangeFilter` | `gt/gte/lt/lte` | `#[ApiFilter(RangeFilter::class, properties: ['discount'])]` |
| `NotInFilter` | `?not_in[prop][]=v1&not_in[prop][]=v2` | `#[ApiFilter(NotInFilter::class, properties: ['id', 'ref'])]` -- **does not support nested relations** |

**BLOCK IN REVIEW**: `ApiPlatform\Doctrine\*Filter` on Propel resource -> runtime crash.

### PITFALL: `#[ApiFilter]` scope at class vs operation level

An `#[ApiFilter]` declared at the **class** level applies to **all operations of all stacks** (admin AND front) without distinction. On a resource exposed to both stacks, declaring `#[ApiFilter(SearchFilter::class, properties: ['status'])]` at class level exposes the filter to `/api/front/...?status=rejected` -- an anonymous visitor can then read records with `rejected` or `pending` status that the front collection intended to hide.

**Always scope sensitive filters**:

```php
// INSTEAD OF:
#[ApiFilter(SearchFilter::class, properties: ['status' => 'exact'])]
class ProductReview { ... }

// PUT THE FILTER ON THE ADMIN OPERATION ONLY:
new GetCollection(
    uriTemplate: '/admin/product-reviews',
    filters: ['my_module.search_filter.product_review.status'],
    // or
    extraProperties: ['filters' => [...]]
)
```

**Or** add a `QueryCollectionExtensionInterface` that forces the filter on the front side:

```php
final readonly class ApprovedReviewCollectionExtension implements QueryCollectionExtensionInterface
{
    public function applyToCollection(ModelCriteria $query, string $resourceClass, ?Operation $operation = null, array $context = []): void
    {
        if (ProductReview::class !== $resourceClass) { return; }
        if (null === $operation || !str_starts_with($operation->getUriTemplate() ?? '', '/front/')) { return; }
        $query->filterByStatus(ReviewStatus::Approved->value);
    }
}
```

This pattern is identical in T3 -- the class-vs-operation scope is an AP feature, not Thelia-specific.

## 9. Security

### Firewalls (`Thelia.php:647-712`)

Firewalls are declared **programmatically by Reflection** on `ContainerBuilder.extensionConfigs` -- the project's security.yaml is empty / supplementary (SIGNAL-12).

4 firewalls:
- `frontLogin` (`^/api/front/login`)
- `adminLogin` (`^/api/admin/login`)
- `api` (`^/api` JWT)
- traditional front/admin web login

Providers:
- `admin_provider` (`AdminUserProvider`)
- `customer_provider` (`CustomerUserProvider`)
- `all_users` (chain)

### JWT Lexik 2.x

- RSA keys via `JWT_SECRET_KEY` / `JWT_PUBLIC_KEY` / `JWT_PASSPHRASE`
- `JwtListener` adds claim `type` = model FQCN (`Thelia\Model\Customer` or `Thelia\Model\Admin`)
- **No refresh token** -- `gesdinet/jwt-refresh-token-bundle` absent from composer.json (SIGNAL-10)
- Endpoints: `POST /api/front/login`, `POST /api/admin/login` JSON body `{username, password}`

### URL conventions

- Admin: `/admin/{resource}` -- `ROLE_ADMIN`
- Public front: `/front/{resource}` -- no auth
- Customer account front: `/front/account/{resource}` -- `ROLE_CUSTOMER`

### `security:` expressions per resource (excerpts)

| Resource | Operation | Expression | Source |
|---|---|---|---|
| Customer | front Get | `object.getId() == user.getId()` | `Customer.php:72` |
| Customer | front Put | `object.getId() == user.getId()` | `Customer.php:76` |
| Order | front Get | `object.customer.getId() == user.getId()` | `Order.php:69` |
| Address | front Get/Put/Delete | `object.customer.getId() == user.getId()` | `Address.php:72/76/80` |
| Cart | front Get/Put/Delete | `is_granted("ROLE_CUSTOMER") and object.customer.getId() == user.getId()` | `Cart.php:61/70/74` |

## 10. Serialization group conventions

```php
public const GROUP_ADMIN_READ          = 'admin:{resource}:read';
public const GROUP_ADMIN_READ_SINGLE   = 'admin:{resource}:read:single';
public const GROUP_ADMIN_WRITE         = 'admin:{resource}:write';
public const GROUP_ADMIN_WRITE_UPDATE  = 'admin:{resource}:write:update';
public const GROUP_FRONT_READ          = 'front:{resource}:read';
public const GROUP_FRONT_READ_SINGLE   = 'front:{resource}:read:single';
public const GROUP_FRONT_WRITE         = 'front:{resource}:write';
```

Cross-resource: to expose Category in a Product single, add `Product::GROUP_ADMIN_READ_SINGLE` to the `#[Groups]` of the Category field.

### PITFALL: global `normalizationContext` ignores `_SINGLE`

The `normalizationContext` declared at the `#[ApiResource]` level applies to ALL operations. To expose additional fields only on `Get` single (`GROUP_*_READ_SINGLE`), explicitly override the context of the `Get` operation:

```php
new Get(
    uriTemplate: '/admin/items/{id}',
    normalizationContext: ['groups' => [self::GROUP_ADMIN_READ, self::GROUP_ADMIN_READ_SINGLE]],
),
```

Without this override, fields annotated only with `GROUP_*_READ_SINGLE` never appear -- silent behavior. Native core pattern: see `Product.php:50`.

Symmetrically: do not declare a group (`GROUP_ADMIN_WRITE`, `GROUP_*_READ_SINGLE`) if no operation activates it -- dead code that misleads about the API surface.

### Post-denormalize FK validation

For FKs exposed in `write` (e.g., `loyaltyAccountId`), the DB constraint exists but a Propel violation surfaces as an uncontrolled `500`. Add:
- `#[Assert\Positive]` or `#[Assert\GreaterThan(0)]` on the id in input
- Ideal: a decorated `StateProcessor` that validates existence before `save()` and returns a `422`

### PITFALL: `Length(min: N)` does not catch `null`

`Symfony\Component\Validator\Constraints\LengthValidator::validate()` returns without violation if `$value === null` (`LengthValidator.php:33`: `if (null === $value) { return; }`). On an i18n resource `?string $title = null` carrying only `#[Assert\Length(min: 5)]`, a payload `title: null` or absent field passes validation.

**Always combine `NotBlank` + `Length` on required i18n fields in write:**

```php
#[Assert\NotBlank(groups: [ProductReview::GROUP_FRONT_WRITE, ProductReview::GROUP_ADMIN_WRITE])]
#[Assert\Length(min: 5, max: 200, groups: [ProductReview::GROUP_FRONT_WRITE])]
protected ?string $title = null;
```

Otherwise the protection only exists in the Processor (procedural, not testable, bypassable on the next refactor).

## 11. Built-in State Providers / Processors

| Service | Role | File |
|---|---|---|
| `PropelCollectionProvider` | `find()` + `QueryCollectionExtensionInterface` extensions (FilterExtension, PaginationExtension, ResourceAddonExtension, CustomerGetCollectionExtension) | `State/PropelCollectionProvider.php:24` |
| `PropelItemProvider` | dispatch `ItemProviderQueryEvent` -> `QueryItemExtensionInterface` extensions -> `findOne()` | `State/PropelItemProvider.php:29` |
| `PropelPersistProcessor` | Propel transaction: `beforeSave()` (handles PUT i18n + composite) -> `save()` -> `manageResourceAddons()` -> reload + `modelToResource()` | `State/PropelPersistProcessor.php:33` |
| `PropelRemoveProcessor` | `doDelete()` addons + `delete()`. Throws if `isDeleted()` false | `State/PropelRemoveProcessor.php:23` |

Injection: `PropelResourceCollectionMetadataFactory` automatically injects the correct provider/processor for any resource implementing `PropelResourceInterface`. **No manual declaration needed.**

## 12. IDOR / BOLA -- security rules (SIGNAL-08, SIGNAL-09)

### Front POST with owner field

**Every front creation operation that contains a `customerId` (or owner field) must verify ownership manually.** The T2.6 core has this hole on `POST /api/front/account/addresses` (`Address.php:62`) -- an authenticated customer can create an address with another customer's `customerId`.

Recommendation for any module adding a front POST:

```php
new Post(
    uriTemplate: '/front/account/items',
    securityPostDenormalize: 'object.customerId == user.getId()',
)
```

Or via decorated processor:

```php
if ($data->customerId !== $user->getId()) {
    throw new \Symfony\Component\Security\Core\Exception\AccessDeniedException();
}
```

### Front GetCollection

Front GetCollection for Order/Address carries **no** `security:` expression -- protection relies entirely on `CustomerGetCollectionExtension` (`Bridge/Propel/Extension/CustomerGetCollectionExtension.php`) which adds a `filterByCustomer($user)` if the query exposes that filter. If the extension is disabled or bypassed by a module, the full collection becomes accessible. Recommendation: add a minimal `security: 'is_granted("ROLE_CUSTOMER")'` expression on front operations.

## 13. Native resource inventory (~96)

| Domain | Resources |
|---|---|
| Catalog (15) | Product, ProductSaleElements, ProductPrice, ProductCategory, Brand, Accessory, Template, Feature, FeatureAv, FeatureProduct, FeatureTemplate, Attribute, AttributeAv, AttributeCombination, AttributeTemplate |
| Images/Docs (12) | Product/Category/Brand/Folder/Content/Module Image+Document, ProductSaleElementsProductImage |
| CMS (4) | Content, Folder, ContentFolder, ProductAssociatedContent |
| Customer (5) | Customer, Address, CustomerTitle, Cart, CartItem |
| Order (6) | Order, OrderProduct, OrderProductTax, OrderCoupon, OrderStatus, OrderAddress |
| Geo/Tax (7) | Country, State, Currency, Lang, Tax, TaxRule, TaxRuleCountry |
| Config/Admin (5) | Config, Module, ModuleConfig, RewritingUrl, NewsLetter |
| I18n entities (~30) | suffixed `I18n` for each translatable entity |

## 14. API pitfalls

1. **Folder `Resource/` instead of `Api/Resource/`** -- resource silently absent from AP bridge, no endpoint, no error (`services.php:88`). Always `{Module}\Api\Resource` with matching namespace.
2. **Global `normalizationContext`** -- `_READ_SINGLE` groups never appear on `Get` single without operation override (see section 10).
3. Native Doctrine AP filters on Propel resource -> crash (always)
4. `IriConverter` returns `'undefined_iri'` instead of exception on badly mapped composite (SIGNAL-11)
5. `getPropelRelatedTableMap()` returns null -> `PropelCollectionProvider` NPE -- always return `XxxTableMap::getTableMap()`
6. `PropelResourceTrait` not `use`d -> `NoSuchPropertyException` on addons
7. No JWT refresh -- expired token = forced re-login (SIGNAL-10)
8. Single format JSON-LD -- any extension requesting `application/json` returns 406
9. Group declared without associated operation = dead code (`GROUP_ADMIN_WRITE` without `Post`/`Put`)
10. FK in write without post-denormalize validation -> Propel `500` instead of a clean `422`
