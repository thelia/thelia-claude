# API Platform Filters: Detailed Reference

## Contents

- QueryParameter (AP 4.2, recommended for new Doctrine projects)
- `#[ApiFilter]` Declaration (legacy, AP 3.x / 4.x, deprecated in 5.0)
  - Propel/Thelia (stays on AP 3.x bridge)
  - Doctrine
- SearchFilter Strategies
- HTTP Query Examples
- Custom Filters (Doctrine)
  - AP 4.2+: new `FilterInterface` (no constructor dependencies)
  - Legacy: `AbstractFilter`
- Performance Notes

## QueryParameter (AP 4.2, recommended for new Doctrine projects)

AP 4.2 introduces a new filter system based on `QueryParameter`, declared per operation. It gradually replaces `#[ApiFilter]` (deprecated in AP 5.0).

### Declaration

```php
use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\GetCollection;
use ApiPlatform\Metadata\QueryParameter;
use ApiPlatform\Doctrine\Orm\Filter\SearchFilter;
use ApiPlatform\Doctrine\Orm\Filter\OrderFilter;
use ApiPlatform\Doctrine\Orm\Filter\BooleanFilter;
use ApiPlatform\Doctrine\Orm\Filter\RangeFilter;

#[ApiResource(
    operations: [
        new GetCollection(
            parameters: [
                // Partial search on name
                'q' => new QueryParameter(
                    filter: SearchFilter::class,
                    property: 'name',
                    filterContext: ['strategy' => 'partial'],
                ),
                // Boolean filter on active
                'active' => new QueryParameter(filter: BooleanFilter::class),
                // Range filter on price
                'price' => new QueryParameter(filter: RangeFilter::class),
                // Order on createdAt and name
                'order' => new QueryParameter(
                    filter: OrderFilter::class,
                    property: ['createdAt', 'name'],
                ),
                // Custom filter with validation and docs
                'category' => new QueryParameter(
                    filter: SearchFilter::class,
                    property: 'category.id',
                    filterContext: ['strategy' => 'exact'],
                    schema: ['type' => 'integer'],
                    openApi: new Parameter(
                        name: 'category',
                        description: 'Filter by category ID',
                    ),
                ),
            ],
        ),
    ],
)]
final class Product { }
```

### Benefits vs legacy `#[ApiFilter]`

| Aspect | `QueryParameter` (4.2+) | `#[ApiFilter]` legacy |
|---|---|---|
| OpenAPI documentation | Auto-generated per parameter, customizable | Global, less control |
| Validation | JSON Schema per parameter | Indirect via filter |
| Responsibility | Separated (filter / docs / validation) | Mixed in one annotation |
| Filter constructor | New `FilterInterface` without dependencies | Old filters with dependencies |
| Reusability across operations | Per-operation declaration (explicit) | Global on the resource |
| Deprecation path | Stable API 4.2+ | Deprecated in AP 5.0 |

### Simplified `FilterInterface` (AP 4.2)

The new `FilterInterface` is minimal: one `apply()` method, no constructor dependencies, no `DocumentationInterface` to implement (documentation lives in the `QueryParameter`).

```php
use ApiPlatform\Metadata\FilterInterface;
use Doctrine\ORM\QueryBuilder;

final readonly class ActiveInLastDaysFilter implements FilterInterface
{
    public function apply(
        QueryBuilder $queryBuilder,
        mixed $value,
        array $context = [],
    ): void {
        if (!is_numeric($value)) {
            return;
        }
        $threshold = new \DateTimeImmutable(sprintf('-%d days', (int) $value));
        $queryBuilder
            ->andWhere('o.lastActivityAt >= :threshold')
            ->setParameter('threshold', $threshold);
    }
}
```

Usage:

```php
new GetCollection(parameters: [
    'active_days' => new QueryParameter(filter: ActiveInLastDaysFilter::class),
])
```

## `#[ApiFilter]` Declaration (legacy, AP 3.x / 4.x, deprecated in 5.0)

### Propel/Thelia

The Propel bridge (Thelia 3) remains on AP 3.x compatibility mode. The AP 4.2 features (`QueryParameter`, ObjectMapper) do not apply to the Propel bridge. Continue using `#[ApiFilter]` below on Thelia 3.

```php
use ApiPlatform\Metadata\ApiFilter;
use Thelia\Api\Bridge\Propel\Filter\BooleanFilter;
use Thelia\Api\Bridge\Propel\Filter\OrderFilter;
use Thelia\Api\Bridge\Propel\Filter\RangeFilter;
use Thelia\Api\Bridge\Propel\Filter\SearchFilter;

#[ApiFilter(
    filterClass: SearchFilter::class,
    properties: [
        'ref',                                    // exact
        'title' => 'word_start',                  // word starts with
        'productCategories.category.id',          // relation
    ],
)]
#[ApiFilter(
    filterClass: BooleanFilter::class,
    properties: ['visible', 'virtual'],
)]
#[ApiFilter(
    filterClass: OrderFilter::class,
    properties: ['position', 'createdAt', 'ref'],
)]
#[ApiFilter(
    filterClass: RangeFilter::class,
    properties: ['productSaleElements.productPrices.price'],
)]
class Product extends AbstractTranslatableResource
```

### Doctrine (legacy)

See SKILL.md for the short version. New Doctrine development should use `QueryParameter` above.

## Filter Declaration (Doctrine)

```php
use ApiPlatform\Doctrine\Orm\Filter\SearchFilter;
use ApiPlatform\Doctrine\Orm\Filter\BooleanFilter;
use ApiPlatform\Doctrine\Orm\Filter\OrderFilter;
use ApiPlatform\Doctrine\Orm\Filter\RangeFilter;
use ApiPlatform\Doctrine\Orm\Filter\DateFilter;
use ApiPlatform\Doctrine\Orm\Filter\ExistsFilter;
use ApiPlatform\Metadata\ApiFilter;

#[ApiFilter(SearchFilter::class, properties: ['name' => 'partial', 'status' => 'exact'])]
#[ApiFilter(BooleanFilter::class, properties: ['active'])]
#[ApiFilter(OrderFilter::class, properties: ['createdAt', 'name', 'price'])]
#[ApiFilter(RangeFilter::class, properties: ['price', 'stock'])]
#[ApiFilter(DateFilter::class, properties: ['createdAt', 'updatedAt'])]
#[ApiFilter(ExistsFilter::class, properties: ['deletedAt'])]
```

## SearchFilter Strategies

| Strategy | Description | SQL | Example |
|----------|-------------|-----|---------|
| `exact` | Equality (default) | `= value` | `?ref=PRD-001` |
| `partial` | Contains | `LIKE %value%` | `?name=widget` |
| `start` | Starts with | `LIKE value%` | `?name=Wid` |
| `end` | Ends with | `LIKE %value` | `?name=Pro` |
| `word_start` | Word starts with | `LIKE value% OR LIKE % value%` | `?title=new` |

## HTTP Query Examples

### Simple Filters

```http
# Exact match
GET /api/front/products?ref=PRD-001

# Boolean
GET /api/front/products?visible=true

# Relation filter
GET /api/front/products?brand.id=5
GET /api/front/products?productCategories.category.id=3

# Multiple values (OR)
GET /api/front/products?id[]=1&id[]=2&id[]=5
```

### Ordering

```http
# Single field
GET /api/front/products?order[position]=asc

# Multiple fields
GET /api/front/products?order[position]=asc&order[createdAt]=desc
```

### Pagination

```http
# Page 2 with 20 items per page
GET /api/front/products?page=2&itemsPerPage=20
```

### Range Filters

```http
# Greater than or equal
GET /api/front/products?price[gte]=10

# Less than or equal
GET /api/front/products?price[lte]=100

# Between
GET /api/front/products?price[gte]=10&price[lte]=100

# Greater than (strict)
GET /api/front/products?price[gt]=0

# Less than (strict)
GET /api/front/products?price[lt]=1000
```

### Date Filters (Doctrine)

```http
# After date
GET /api/products?createdAt[after]=2024-01-01

# Before date
GET /api/products?createdAt[before]=2024-12-31

# Between dates
GET /api/products?createdAt[after]=2024-01-01&createdAt[before]=2024-12-31
```

### Exists Filter (Doctrine)

```http
# Only non-deleted items
GET /api/products?exists[deletedAt]=false

# Only items with a category
GET /api/products?exists[category]=true
```

### Combined Filters

```http
GET /api/front/products?visible=true&productCategories.category.id=5&order[position]=asc&itemsPerPage=20&page=1
```

## Custom Filters

### Doctrine Custom Filter

```php
declare(strict_types=1);

namespace App\Filter;

use ApiPlatform\Doctrine\Orm\Filter\AbstractFilter;
use ApiPlatform\Doctrine\Orm\Util\QueryNameGeneratorInterface;
use ApiPlatform\Metadata\Operation;
use Doctrine\ORM\QueryBuilder;

final class ActiveProductFilter extends AbstractFilter
{
    protected function filterProperty(
        string $property,
        mixed $value,
        QueryBuilder $queryBuilder,
        QueryNameGeneratorInterface $queryNameGenerator,
        string $resourceClass,
        ?Operation $operation = null,
        array $context = [],
    ): void {
        if ($property !== 'active') {
            return;
        }

        $alias = $queryBuilder->getRootAliases()[0];
        $parameterName = $queryNameGenerator->generateParameterName($property);

        $queryBuilder
            ->andWhere(sprintf('%s.active = :%s', $alias, $parameterName))
            ->setParameter($parameterName, filter_var($value, FILTER_VALIDATE_BOOLEAN));
    }

    public function getDescription(string $resourceClass): array
    {
        return [
            'active' => [
                'property' => 'active',
                'type' => 'bool',
                'required' => false,
                'description' => 'Filter by active status',
            ],
        ];
    }
}
```

## Performance Notes

- Add database indexes on columns used in filters.
- The `partial` and `word_start` strategies use `LIKE` with wildcards and are slower on large datasets.
- `exact` is the most performant strategy.
- For relation filters, ensure foreign key columns are indexed.
- Pagination limits the result set. Always configure `paginationItemsPerPage`.
