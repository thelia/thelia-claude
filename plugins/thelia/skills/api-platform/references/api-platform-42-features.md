# API Platform 4.2: Key Features

Detailed reference for the major features introduced in AP 4.2 for Symfony/Doctrine projects. The Propel bridge (Thelia 3) remains on AP 3.x compatibility mode. These features do not apply to Thelia 3.

## Contents

- ObjectMapper Integration
- JSON Streamer
- Metadata Mutators
- Query Parameter (replaces ApiFilter)
- Link Provider

## ObjectMapper Integration

AP 4.2 integrates the Symfony ObjectMapper component natively via two decorators that operate automatically upstream of the Provider/Processor chain:

- `ApiPlatform\State\Provider\ObjectMapperProvider`
- `ApiPlatform\State\Processor\ObjectMapperProcessor`

### When to use

| Case | Approach |
|---|---|
| Public DTO + internal Entity, direct mapping | **ObjectMapper**: no custom Provider/Processor needed |
| Business logic (recalculation, side effects, multi-entity orchestration) | **Custom Processor**: keep full control |
| Transformation + simple validation | **ObjectMapper + Symfony Validator** |

### Minimal example

```php
use Symfony\Component\ObjectMapper\Attribute\Map;
use ApiPlatform\Doctrine\Orm\State\Options;
use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\Post;

#[Map(target: UserEntity::class)]
#[ApiResource(
    operations: [
        new Post(), // ObjectMapperProcessor applied automatically
        new Get(),  // ObjectMapperProvider applied automatically
    ],
    stateOptions: new Options(entityClass: UserEntity::class),
)]
final class User
{
    public ?int $id = null;
    #[Map(transform: 'strtolower')]
    public string $email;
    public string $firstName;
}
```

No `ProductProvider` or `ProductProcessor` needed for a direct 1-to-1 mapping. Net gain: less code, fewer tests, no duplication.

### Advanced `#[Map]` attributes

```php
final class BookInput
{
    public function __construct(
        #[Map(target: 'title')]
        public string $name,
        #[Map(if: 'hasDiscount')]
        public ?int $discountPercent = null,
        #[Map(target: 'author', transform: [AuthorFactory::class, 'fromName'])]
        public string $authorName,
    ) {}

    public function hasDiscount(): bool
    {
        return $this->discountPercent !== null && $this->discountPercent > 0;
    }
}
```

## JSON Streamer

Serialization via the Symfony 7.3 `JsonStreamer` component. Opt-in per resource:

```php
#[ApiResource(
    operations: [
        new GetCollection(
            extraProperties: ['json_streamer' => true],
        ),
    ],
)]
final class Product { }
```

### Measured gains

| Metric | Standard Serializer | JsonStreamer |
|---|---|---|
| RPS (Sylius benchmark) | 100% | **+32%** |
| RAM / 10,000 objects | 100% | ~10% |
| Latency first byte | standard | **immediate** (streaming) |

### Compatibility

- JSON: yes
- JSON-LD: yes
- Hydra: yes
- Deep embedded relations: verify case by case

### When to enable

Collections exceeding 1,000 items, exports, feeds (full catalog, history, data pipelines). Not needed for standard CRUD endpoints (fewer than 100 items).

## Metadata Mutators

Dynamically modify metadata (security, groups, pagination) without editing attributes on the class. Useful for cross-cutting conventions.

### Resource Mutator

```php
use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\ResourceMutatorInterface;

final readonly class AddAuditGroupsMutator implements ResourceMutatorInterface
{
    public function __invoke(ApiResource $resource): ApiResource
    {
        if (!str_starts_with($resource->getClass(), 'App\\Entity\\Audit\\')) {
            return $resource;
        }

        return $resource->withNormalizationContext(
            array_merge(
                $resource->getNormalizationContext() ?? [],
                ['groups' => ['audit:read']],
            ),
        );
    }
}
```

### Operation Mutator

```php
use ApiPlatform\Metadata\HttpOperation;
use ApiPlatform\Metadata\OperationMutatorInterface;

final readonly class EnforceAdminSecurityMutator implements OperationMutatorInterface
{
    public function __invoke(HttpOperation $operation): HttpOperation
    {
        if (str_starts_with($operation->getUriTemplate() ?? '', '/api/admin/')) {
            return $operation->withSecurity("is_granted('ROLE_ADMIN')");
        }
        return $operation;
    }
}
```

### Use cases

- Multi-tenant (inject a tenant filter on all resources)
- Audit trails (inject normalization groups)
- Feature flags (enable/disable operations per environment)
- Uniform security (enforce ROLE on `/admin/*` URIs)

## Query Parameter (replaces ApiFilter)

AP 4.2 introduces a new filter system based on `QueryParameter`, declared per operation. It gradually replaces `#[ApiFilter]` (deprecated in AP 5.0).

See `references/filters.md` (QueryParameter section) for complete examples and a comparison with the legacy system.

### Benefits summary

- OpenAPI documentation auto-generated **per parameter**
- Validation via JSON Schema per parameter
- New minimal `FilterInterface` (no constructor dependencies)
- Separated responsibilities (filtering / documentation / validation)
- Declaration per operation (more flexible than a global annotation)

### Progressive migration

Both systems coexist in 4.2:

- **Existing code**: `#[ApiFilter]` works, no forced migration.
- **New code**: use `QueryParameter`.
- **AP 5.0**: `#[ApiFilter]` will be deprecated.

## Link Provider (URI variables for subresources)

From 4.2 onward, a provider can be attached directly to a `Link` to resolve a URI variable without searching the entire resource:

```php
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\Link;

new Get(
    uriTemplate: '/companies/{companyId}/users/{id}',
    uriVariables: [
        'companyId' => new Link(
            fromClass: Company::class,
            provider: CompanyProvider::class,
            identifiers: ['id'],
        ),
        'id' => new Link(fromClass: User::class),
    ],
),
```

Advantages over monolithic providers:
- Each URI variable is resolved independently.
- Smaller, more testable providers.
- No full URL re-parsing.
- Access control per segment if needed.

### Typical pattern: scoped subresource

```php
#[ApiResource(
    operations: [
        new GetCollection(
            uriTemplate: '/companies/{companyId}/users',
            uriVariables: [
                'companyId' => new Link(
                    fromClass: Company::class,
                    provider: ScopedCompanyProvider::class, // verifies access
                ),
            ],
            security: "is_granted('COMPANY_ACCESS', companyId)",
        ),
    ],
)]
final class User { }
```
