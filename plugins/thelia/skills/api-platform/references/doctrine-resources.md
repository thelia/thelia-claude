# API Platform: Doctrine Resources (Complete Examples)

## Contents

- AP 4.2+: ObjectMapper (native, replaces simple Provider/Processor)
- AP 4.2+: JsonStreamer (opt-in per resource)
- Resource Definition (DTO approach)
- State Provider (when still needed)
- State Processor (when still needed)
- Input / Output DTOs
- Serialization Groups
- Filters (Doctrine)
- Validation
- Error Handling
- Testing
- Messenger Integration

## AP 4.2+: ObjectMapper (native, replaces simple Provider/Processor)

From AP 4.2, the Symfony `ObjectMapper` component is integrated natively via two decorators that apply automatically:

- `ApiPlatform\State\Provider\ObjectMapperProvider`: maps Entity to DTO on reads
- `ApiPlatform\State\Processor\ObjectMapperProcessor`: maps DTO to Entity on writes

### Mapped resource, zero custom Provider/Processor

```php
declare(strict_types=1);

namespace App\ApiResource;

use ApiPlatform\Doctrine\Orm\State\Options;
use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\Patch;
use ApiPlatform\Metadata\Post;
use App\Entity\Product as ProductEntity;
use Symfony\Component\ObjectMapper\Attribute\Map;
use Symfony\Component\Validator\Constraints as Assert;

#[Map(target: ProductEntity::class)]
#[ApiResource(
    shortName: 'Product',
    operations: [
        new GetCollection(),
        new Get(),
        new Post(),
        new Patch(),
    ],
    stateOptions: new Options(entityClass: ProductEntity::class),
    paginationItemsPerPage: 30,
    normalizationContext: ['groups' => ['product:read']],
    denormalizationContext: ['groups' => ['product:write']],
)]
final class Product
{
    public ?int $id = null;

    #[Assert\NotBlank(groups: ['create', 'update'])]
    #[Assert\Length(min: 3, max: 255, groups: ['create', 'update'])]
    public string $name;

    public string $description;

    #[Map(transform: 'intval')]
    public int $priceInCents;
}
```

AP detects `#[Map(target: ProductEntity::class)]` and automatically applies ObjectMapperProvider on reads (entity to DTO) and ObjectMapperProcessor on writes (DTO to entity to persist). No `ProductProvider` or `ProductProcessor` needed for a direct mapping.

### Advanced `#[Map]` attributes

```php
final class UserResource
{
    #[Map(target: 'emailAddress', transform: 'strtolower')]
    public string $email;

    #[Map(if: 'isAdult', target: 'adultVerified')]
    public bool $isAdult;

    #[Map(target: 'fullName', transform: [NameFormatter::class, 'combine'])]
    public string $firstName;
    public string $lastName;
}
```

### When to keep a custom Provider/Processor

ObjectMapper does not replace a Provider/Processor when:

- Non-trivial business logic (total recalculation, business side effects)
- Aggregating multiple entities into a single DTO
- Conditional persistence (dispatching a message instead of persisting)
- Async Messenger integration
- Complex access control requiring a runtime object

See the "State Provider" and "State Processor" sections below for these cases.

## AP 4.2+: JsonStreamer (opt-in per resource)

For endpoints that serialize large collections (exports, full catalog, history), enable JsonStreamer opt-in per operation:

```php
#[ApiResource(
    operations: [
        new GetCollection(
            extraProperties: [
                'json_streamer' => true,
            ],
        ),
        new Get(), // no streaming on individual items
    ],
)]
final class Product { }
```

**Measured gains**: +32% RPS (Sylius benchmarks), roughly 10x less RAM on large volumes.

Compatible with JSON, JSON-LD, Hydra formats. Incompatible with some patterns (deep embedded relations; verify case by case).

Activate as soon as a collection exceeds ~1,000 items or is streamed toward a client (CDN, data pipeline).

## Resource Definition (DTO approach)

```php
declare(strict_types=1);

namespace App\ApiResource;

use ApiPlatform\Doctrine\Orm\State\Options;
use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\Patch;
use ApiPlatform\Metadata\Post;
use App\Entity\Product as ProductEntity;
use App\State\ProductProcessor;
use App\State\ProductProvider;

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
    public ProductStatus $status;
    public \DateTimeImmutable $createdAt;
}
```

### Resource Rules

- One API resource class per endpoint group.
- Use an explicit `operations` array. Never rely on defaults in production.
- Always specify methods implicitly through operation classes (`Get`, `Post`, etc.).
- Set `shortName` to control the URI segment and documentation label.
- Use `normalizationContext` / `denormalizationContext` with serialization groups for fine control.
- Set `paginationItemsPerPage` explicitly per resource.

## State Provider (Complete)

```php
declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\CollectionOperationInterface;
use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\ApiResource\Product;
use App\Repository\ProductRepository;

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

    private function toResource(\App\Entity\Product $entity): Product
    {
        $resource = new Product();
        $resource->id = $entity->getId();
        $resource->name = $entity->getName();
        $resource->description = $entity->getDescription();
        $resource->priceInCents = $entity->getPriceInCents();
        $resource->status = $entity->getStatus();
        $resource->createdAt = $entity->getCreatedAt();

        return $resource;
    }
}
```

When using `stateOptions` with `entityClass`, you can also leverage the built-in Doctrine providers and decorate them to add transformation logic.

## State Processor (Complete)

```php
declare(strict_types=1);

namespace App\State;

use ApiPlatform\Metadata\DeleteOperationInterface;
use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\ApiResource\Product;
use Doctrine\ORM\EntityManagerInterface;

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
        if (!$data instanceof Product) {
            return $data;
        }

        if ($operation instanceof DeleteOperationInterface) {
            $entity = $this->entityManager->find(\App\Entity\Product::class, $uriVariables['id']);
            if ($entity) {
                $this->entityManager->remove($entity);
                $this->entityManager->flush();
            }
            return null;
        }

        // Create or update
        $entity = isset($uriVariables['id'])
            ? $this->entityManager->find(\App\Entity\Product::class, $uriVariables['id'])
            : new \App\Entity\Product();

        $entity->setName($data->name);
        $entity->setDescription($data->description);
        $entity->setPriceInCents($data->priceInCents);

        $this->entityManager->persist($entity);
        $this->entityManager->flush();

        return $this->productProvider->provide($operation, ['id' => $entity->getId()], $context);
    }
}
```

## Input / Output DTOs

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

```php
declare(strict_types=1);

namespace App\ApiResource\Input;

use Symfony\Component\Validator\Constraints as Assert;

final class PublishProductInput
{
    #[Assert\NotBlank]
    public \DateTimeImmutable $publishDate;

    #[Assert\Range(min: 0, max: 100)]
    public int $discountPercentage = 0;
}
```

## Serialization Groups

```php
use Symfony\Component\Serializer\Attribute\Groups;

#[Groups(['product:read'])]
public ?int $id = null;

#[Groups(['product:read', 'product:write'])]
public string $name;

#[Groups(['product:admin'])]
public string $internalNotes;
```

Convention: `{resource}:read`, `{resource}:write`, `{resource}:admin` for admin-only fields.

## Filters (Doctrine)

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

For custom filtering logic, implement a custom Doctrine ORM extension or a custom filter.

## Validation

Validation is applied automatically before the processor runs:

```php
#[Assert\NotBlank(groups: ['create'])]
#[Assert\Length(min: 3, max: 255, groups: ['create', 'update'])]
public string $name;
```

Use validation groups to differentiate create vs update constraints.

## Error Handling

```yaml
api_platform:
    exception_to_status:
        App\Exception\ProductNotFoundException: 404
        App\Exception\InsufficientStockException: 409
```

Throw specific domain exceptions from processors. API Platform handles the rest.

## Testing API Endpoints

```php
use ApiPlatform\Symfony\Bundle\Test\ApiTestCase;

class ProductApiTest extends ApiTestCase
{
    public function testCreateProduct(): void
    {
        static::createClient()->request('POST', '/api/products', [
            'json' => [
                'name' => 'Widget Pro',
                'description' => 'A professional widget',
                'priceInCents' => 2999,
            ],
        ]);

        $this->assertResponseStatusCodeSame(201);
        $this->assertJsonContains(['name' => 'Widget Pro']);
    }
}
```

## Messenger Integration

API Platform can dispatch messages directly:

```php
#[ApiResource(
    operations: [
        new Post(
            messenger: true,
            output: false,
            status: 202,
        ),
    ],
)]
```

Setting `messenger: true` dispatches the resource object as a message. Use `output: false` with status `202` to indicate async processing.

For input DTOs, `messenger: 'input'` dispatches the input DTO instead of the resource.
