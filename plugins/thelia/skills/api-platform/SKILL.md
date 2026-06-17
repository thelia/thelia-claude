---
name: api-platform
description: "Enforces API Platform 4.2+ standards for Symfony (Doctrine ORM) and Thelia 3 (Propel, AP 3.x bridge) projects. Covers resource definition with explicit operations, state providers and processors, ObjectMapper integration (4.2), JsonStreamer for high-performance serialization (4.2), Metadata Mutators (4.2), QueryParameter filter system (4.2, replacing legacy ApiFilter), Link Provider for subresources, serialization groups, SearchFilter/BooleanFilter/OrderFilter/RangeFilter, input/output DTOs, validation with groups, JWT authentication flow, error handling with exception-to-status mapping. For Thelia/Propel: PropelResourceInterface, PropelResourceTrait, AbstractTranslatableResource, ResourceAddonInterface for extending native resources, admin/front endpoint separation, IRI relations. Triggers on ApiResource, operations, filters, serialization groups, JWT, state provider, state processor, ObjectMapper, JsonStreamer, QueryParameter, Metadata Mutator, PropelResourceInterface, ResourceAddonInterface."
---

# API Platform 4.2+: Development Standards

These standards apply to API Platform 4.2+ projects on Doctrine ORM (standard Symfony). The Propel bridge (Thelia 3) remains on AP 3.x compatibility mode. See the dedicated section and `references/propel-resources.md` for Propel-specific patterns.

## Quick Reference

| Task | Doctrine (Symfony) | Propel (Thelia 3) |
|------|-------------------|-------------------|
| Resource class | DTO or Entity + `#[ApiResource]` | `PropelResourceInterface` + `PropelResourceTrait` |
| i18n resource | N/A (use translations) | `AbstractTranslatableResource` + `I18nCollection` |
| State provider | Custom `ProviderInterface` | Built-in (Propel bridge) |
| State processor | Custom `ProcessorInterface` | Built-in (Propel bridge) |
| Extend existing | Decorate provider/processor | `ResourceAddonInterface` + `buildFromModel()` |
| Filters | `ApiPlatform\Doctrine\Orm\Filter\*` | `Thelia\Api\Bridge\Propel\Filter\*` |
| Auth | JWT / custom | JWT via `/api/admin/login`, `/api/front/login` |

## API Platform 4.2: Key Features (Summary)

AP 4.2 introduces five major features that change development patterns on Doctrine projects. See `references/api-platform-42-features.md` for complete examples.

| Feature | Usage | Replaces |
|---|---|---|
| **ObjectMapper Integration** | `#[Map(target: Entity::class)]` on the DTO resource. Auto-decorator Provider/Processor applied upstream | Custom Provider/Processor for 1-to-1 mapping |
| **JsonStreamer** | `extraProperties: ['json_streamer' => true]` on the operation | Standard Serializer on large collections (+32% RPS) |
| **Metadata Mutators** | `ResourceMutatorInterface` / `OperationMutatorInterface` services | Scattered attribute edits on each resource |
| **QueryParameter** | `parameters:` on each operation, new minimal `FilterInterface` | `#[ApiFilter]` (deprecated in AP 5.0) |
| **Link Provider** | `new Link(provider: ..., identifiers: ...)` | Monolithic providers that re-parse the URL |

**Propel bridge (Thelia 3)**: these features do not apply. The Propel bridge remains on AP 3.x compatibility mode. Continue using `PropelResourceInterface`, `#[ApiFilter]`, and `ResourceAddonInterface`.

## Doctrine Resources (Standard Symfony)

### Architecture Decision

Two approaches, choose based on project complexity:

- **Entity as Resource (rapid prototyping / simple CRUD):** Mark the Doctrine entity directly with `#[ApiResource]`. Convenient and fast, but couples the API to the internal model.
- **DTO as Resource (recommended for production):** The class marked `#[ApiResource]` is a dedicated DTO. Entities remain internal. Decouples the API contract from persistence.

For non-trivial projects, use the DTO approach. The Entity-as-Resource shortcut is reserved for internal admin CRUD or prototypes.

### Resource Definition (DTO approach)

```php
declare(strict_types=1);

namespace App\ApiResource;

use ApiPlatform\Doctrine\Orm\State\Options;
use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\Patch;
use ApiPlatform\Metadata\Post;

#[ApiResource(
    shortName: 'Product',
    operations: [
        new GetCollection(),
        new Get(),
        new Post(
            processor: ProductProcessor::class,
            validationContext: ['groups' => ['create']],
        ),
        new Patch(
            processor: ProductProcessor::class,
            validationContext: ['groups' => ['update']],
        ),
    ],
    stateOptions: new Options(entityClass: ProductEntity::class),
    provider: ProductProvider::class,
    paginationItemsPerPage: 30,
    normalizationContext: ['groups' => ['product:read']],
    denormalizationContext: ['groups' => ['product:write']],
)]
final class Product
{
    public ?int $id = null;
    public string $name;
    public string $description;
    public int $priceInCents;
}
```

### State Providers

Providers fetch data for GET operations.

```php
declare(strict_types=1);

final readonly class ProductProvider implements ProviderInterface
{
    public function __construct(
        private ProductRepository $productRepository,
    ) {
    }

    public function provide(
        Operation $operation,
        array $uriVariables = [],
        array $context = [],
    ): Product|array|null {
        if ($operation instanceof CollectionOperationInterface) {
            return array_map(
                $this->toResource(...),
                $this->productRepository->findAllPublished(),
            );
        }

        $entity = $this->productRepository->find($uriVariables['id']);

        if (!$entity) {
            return null; // API Platform returns 404 automatically
        }

        return $this->toResource($entity);
    }
}
```

### State Processors

Processors handle write operations (POST, PUT, PATCH, DELETE).

```php
declare(strict_types=1);

final readonly class ProductProcessor implements ProcessorInterface
{
    public function __construct(
        private EntityManagerInterface $entityManager,
        private ProductProvider $productProvider,
    ) {
    }

    public function process(
        mixed $data,
        Operation $operation,
        array $uriVariables = [],
        array $context = [],
    ): ?Product {
        if ($operation instanceof DeleteOperationInterface) {
            $entity = $this->entityManager->find(ProductEntity::class, $uriVariables['id']);
            if ($entity) {
                $this->entityManager->remove($entity);
                $this->entityManager->flush();
            }
            return null;
        }

        // Create or update
        $entity = isset($uriVariables['id'])
            ? $this->entityManager->find(ProductEntity::class, $uriVariables['id'])
            : new ProductEntity();

        $entity->setName($data->name);
        $this->entityManager->persist($entity);
        $this->entityManager->flush();

        return $this->productProvider->provide($operation, ['id' => $entity->getId()], $context);
    }
}
```

### Processor Patterns

- **Per-resource processor**: Set `processor:` on individual operations. Clear and explicit.
- **Decorator pattern**: Use `#[AsDecorator('api_platform.doctrine.orm.state.persist_processor')]` to wrap the core processor for cross-cutting concerns.
- Always return the resource DTO from write processors so the response is properly serialized.
- Use `#[Autowire(service: 'api_platform.doctrine.orm.state.persist_processor')]` when you need to inject the core Doctrine processor.

### Input / Output DTOs

For operations that need a different shape than the resource:

```php
#[ApiResource(
    operations: [
        new Post(
            uriTemplate: '/products/{id}/publish',
            input: PublishProductInput::class,
            output: Product::class,
            processor: PublishProductProcessor::class,
        ),
    ],
)]
```

See `references/doctrine-resources.md` for complete Doctrine examples.

## Propel Resources (Thelia 3)

### Resource Structure

```php
#[ApiResource(
    operations: [
        new Post(uriTemplate: '/admin/product_reviews'),
        new GetCollection(uriTemplate: '/admin/product_reviews'),
        new Get(uriTemplate: '/admin/product_reviews/{id}'),
        new Put(uriTemplate: '/admin/product_reviews/{id}'),
        new Delete(uriTemplate: '/admin/product_reviews/{id}'),
    ],
    normalizationContext: ['groups' => [self::GROUP_ADMIN_READ]],
    denormalizationContext: ['groups' => [self::GROUP_ADMIN_WRITE]],
)]
#[ApiResource(
    operations: [
        new GetCollection(uriTemplate: '/front/product_reviews'),
        new Get(uriTemplate: '/front/product_reviews/{id}'),
    ],
    normalizationContext: ['groups' => [self::GROUP_FRONT_READ]],
)]
class ProductReview implements PropelResourceInterface
{
    use PropelResourceTrait;

    public const GROUP_ADMIN_READ = 'admin:product_review:read';
    public const GROUP_ADMIN_READ_SINGLE = 'admin:product_review:read:single';
    public const GROUP_ADMIN_WRITE = 'admin:product_review:write';
    public const GROUP_FRONT_READ = 'front:product_review:read';

    public static function getPropelRelatedTableMap(): ?TableMap
    {
        return new ProductReviewTableMap();
    }
}
```

Key differences from Doctrine:
- `implements PropelResourceInterface` + `use PropelResourceTrait`
- `getPropelRelatedTableMap()` maps to the Propel model
- Double `#[ApiResource]` for admin AND front endpoints
- i18n: extend `AbstractTranslatableResource` + `I18nCollection`
- Relations: `#[Relation(targetResource: X::class)]`

### Addon (extending existing resources)

File in `MyModule/Api/Addon/`. Static `buildFromModel()` method with `#[Ignore]`. Use the target resource's groups.

```php
class ProductMyAddon
{
    #[Groups([Product::GROUP_ADMIN_READ, Product::GROUP_FRONT_READ])]
    public ?string $customField = null;

    #[Ignore]
    public static function buildFromModel(
        PropelProduct $propelModel,
        Product $resource,
    ): self {
        $addon = new self();
        $addon->customField = $propelModel->getVirtualColumn('custom_field');
        return $addon;
    }
}
```

### Thelia Endpoints

| Context | URL | Access | Operations |
|---------|-----|--------|------------|
| Admin | `/api/admin/*` | JWT required | Full CRUD |
| Front | `/api/front/*` | Public | Read only |
| Login admin | `/api/admin/login` | POST | JWT token |
| Login customer | `/api/front/login` | POST | JWT token |

See `references/propel-resources.md` for complete Propel/Thelia examples.

## Filters

### AP 4.2+: `QueryParameter` (recommended for new Doctrine projects)

See the "API Platform 4.2: Key Features" section above and `references/filters.md` (QueryParameter section). New Doctrine development declares filters via `parameters:` on each operation. `#[ApiFilter]` remains supported but is deprecated in AP 5.0.

### `#[ApiFilter]` (legacy, AP 3.x / 4.x)

```php
use ApiPlatform\Doctrine\Orm\Filter\SearchFilter;
use ApiPlatform\Doctrine\Orm\Filter\OrderFilter;
use ApiPlatform\Doctrine\Orm\Filter\BooleanFilter;
use ApiPlatform\Doctrine\Orm\Filter\RangeFilter;
use ApiPlatform\Metadata\ApiFilter;

#[ApiFilter(SearchFilter::class, properties: ['name' => 'partial', 'status' => 'exact'])]
#[ApiFilter(OrderFilter::class, properties: ['createdAt', 'name'])]
#[ApiFilter(BooleanFilter::class, properties: ['active'])]
#[ApiFilter(RangeFilter::class, properties: ['price'])]
```

### Propel/Thelia Filters

```php
use Thelia\Api\Bridge\Propel\Filter\SearchFilter;
use Thelia\Api\Bridge\Propel\Filter\BooleanFilter;
use Thelia\Api\Bridge\Propel\Filter\OrderFilter;
use Thelia\Api\Bridge\Propel\Filter\RangeFilter;

#[ApiFilter(SearchFilter::class, properties: ['ref', 'title' => 'word_start'])]
#[ApiFilter(BooleanFilter::class, properties: ['visible'])]
#[ApiFilter(OrderFilter::class, properties: ['position', 'createdAt'])]
#[ApiFilter(RangeFilter::class, properties: ['price'])]
```

### SearchFilter Strategies

| Strategy | Description | SQL |
|----------|-------------|-----|
| `exact` | Equality (default) | `= value` |
| `partial` | Contains | `LIKE %value%` |
| `start` | Starts with | `LIKE value%` |
| `end` | Ends with | `LIKE %value` |
| `word_start` | Word starts with | `LIKE value% OR LIKE % value%` |

### HTTP Query Examples

```http
# Simple filters
GET /api/products?active=true&brand.id=5

# Ordering
GET /api/products?order[position]=asc&order[createdAt]=desc

# Pagination
GET /api/products?page=2&itemsPerPage=20

# Range
GET /api/products?price[gte]=10&price[lte]=100

# Combined
GET /api/products?active=true&category.id=5&order[position]=asc&itemsPerPage=20
```

See `references/filters.md` for detailed filter documentation.

## Serialization Groups

### Doctrine Convention

```php
#[ApiResource(
    normalizationContext: ['groups' => ['product:read']],
    denormalizationContext: ['groups' => ['product:write']],
)]
```

Convention: `{resource}:read`, `{resource}:write`, `{resource}:admin` for admin-only fields.

### Propel/Thelia Convention

Convention: `{context}:{resource}:{operation}`

```php
public const GROUP_ADMIN_READ = 'admin:product:read';
public const GROUP_ADMIN_READ_SINGLE = 'admin:product:read:single';
public const GROUP_ADMIN_WRITE = 'admin:product:write';
public const GROUP_FRONT_READ = 'front:product:read';
```

### Rules

- Every exposed property MUST have `#[Groups([...])]`.
- Use validation groups matching serialization groups: `groups: [self::GROUP_ADMIN_WRITE]`.
- Use `READ_SINGLE` groups for data only needed on detail views (heavy relations, images).
- Admin groups must never be exposed on front endpoints.

## JWT Authentication (Quick Overview)

### Login Flow

```http
POST /api/admin/login
Content-Type: application/json

{"username": "admin@example.com", "password": "password"}
```

Response: `{"token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9..."}`

### Authenticated Request

```http
GET /api/admin/products
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9...
```

### Security on Operations

```php
new Get(
    uriTemplate: '/front/account/orders/{id}',
    security: 'object.customer.getId() == user.getId()'
),
```

See `references/security-jwt.md` for the complete JWT flow.

## Validation

Validation is applied automatically before the processor runs. Use Symfony validation constraints.

```php
#[Assert\NotBlank(groups: ['create'])]
#[Assert\Length(min: 3, max: 255, groups: ['create', 'update'])]
public string $name;
```

Use validation groups to differentiate create vs update constraints.

## Error Handling

API Platform converts exceptions to proper HTTP responses:

```yaml
api_platform:
    exception_to_status:
        App\Exception\ProductNotFoundException: 404
        App\Exception\InsufficientStockException: 409
```

Throw specific domain exceptions from processors. API Platform handles the rest.

## Anti-Patterns

| Anti-pattern | Problem | Solution |
|--------------|---------|----------|
| Recreating a native resource | Product, Category already exist in Thelia | `ResourceAddonInterface` to extend |
| Missing PropelResourceInterface | Resource non-functional in Thelia | `implements PropelResourceInterface` + trait |
| Missing Groups on properties | Properties not serialized | `#[Groups]` on every exposed property |
| Exposing admin data on front | Sensitive data public | Separate `GROUP_ADMIN_*` and `GROUP_FRONT_*` |
| Validation without groups | Validates everywhere | `groups: [self::GROUP_ADMIN_WRITE]` |
| N+1 in Twig resources() | Loop with unit requests | Filtered collection with `id[]` |
| Non-indexed filter columns | Slow queries | Database index on filtered columns |
| Relying on default operations | Unexpected endpoints in production | Always explicit `operations` array |
| No pagination config | Unbounded queries | Set `paginationItemsPerPage` per resource |
| API coupled to entity | Breaking changes on model refactor | DTO as Resource (Doctrine) |
| Custom Provider/Processor for direct mapping (AP 4.2) | Unnecessary boilerplate | ObjectMapper + `#[Map]` |
| Large collection serialization without streaming | Timeout / memory exhaustion | `json_streamer: true` on the operation |
| `#[ApiFilter]` on new AP 4.2+ code | Deprecated in AP 5.0 | Use `QueryParameter` per operation |
| Scattered metadata edits (security/groups) | Hard to maintain | Metadata Mutator |

## Checklist

### Doctrine Resource

- [ ] Explicit `operations` array (no defaults)
- [ ] `shortName` set for clean URIs
- [ ] `normalizationContext` / `denormalizationContext` with groups
- [ ] `#[Groups]` on every exposed property
- [ ] Validation constraints with groups
- [ ] `paginationItemsPerPage` configured
- [ ] State provider and/or processor defined
- [ ] Filters declared if needed
- [ ] Exception-to-status mapping for domain exceptions

### Propel/Thelia Resource

- [ ] `implements PropelResourceInterface` + `use PropelResourceTrait`
- [ ] `getPropelRelatedTableMap()` returns the correct TableMap
- [ ] Group constants defined (admin/front, read/write)
- [ ] `#[Groups]` on every exposed property
- [ ] Validation with groups (`groups: [self::GROUP_ADMIN_WRITE]`)
- [ ] Double `#[ApiResource]` if admin AND front
- [ ] `#[Relation]` on related properties
- [ ] Filters declared if needed
- [ ] File in `Api/Resource/` of the module

## Deep-Dive References

- AP 4.2 features in detail (ObjectMapper, JsonStreamer, Metadata Mutators, QueryParameter, Link Provider): [references/api-platform-42-features.md](references/api-platform-42-features.md)
- Complete Doctrine examples with AP 4.2 (ObjectMapper, streaming, providers, processors, input/output DTOs): [references/doctrine-resources.md](references/doctrine-resources.md)
- Complete Propel/Thelia examples (simple, i18n, relations, addon, AP 3.x compatibility mode): [references/propel-resources.md](references/propel-resources.md)
- Filter details (QueryParameter 4.2, legacy strategies, HTTP queries, simplified FilterInterface): [references/filters.md](references/filters.md)
- Complete JWT flow (login, authenticated requests, security): [references/security-jwt.md](references/security-jwt.md)
