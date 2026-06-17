# Performance Review Checklist

## Contents

- JsonStreamer on large collections (Important)
- N+1 Queries (Important)
- `flush()` inside a loop (Important)
- Inverse OneToOne (Important)
- `find()` to set a FK (Suggestion)
- Missing indexes (Important)
- `count($collection)` vs `isEmpty()` (Suggestion)
- Full hydration for read-only lists (Suggestion)
- Chained `array_map` + `array_filter` (Suggestion)
- Missing Lazy Services (Suggestion)
- Doctrine Query Cache in production (Important)
- `clear()` without re-fetching references (Important)

## JsonStreamer on Large Collections (Important)

An API Platform collection serialized through the standard Serializer loads all items into memory before writing the response. With over 1000 items, this causes RAM spikes and high first-byte latency.

Require JsonStreamer on affected operations:

```php
// BAD: standard Serializer, O(n) RAM
new GetCollection()

// GOOD: streaming, O(1) RAM
new GetCollection(extraProperties: ['json_streamer' => true])
```

Measured gains on Sylius: **+32% RPS**, RAM divided by 10.

Cases where activation is not recommended:
- Deep embedded relations that cannot be serialized in streaming mode (check case by case)
- Collections under 100 items (overhead is neutral)

## N+1 Queries (Important)

The most common performance bug. Occurs when a collection is loaded and then each item accesses a lazy-loaded relation.

```php
// BAD: 1 + N queries (N = number of employees)
$employees = $this->employeeRepository->findAll();
// In Twig: {{ employee.company.name }} triggers 1 SELECT per employee

// GOOD: fetch join
public function findAllWithCompany(): array
{
    return $this->createQueryBuilder('e')
        ->leftJoin('e.company', 'c')
        ->addSelect('c')
        ->getQuery()
        ->getResult();
}

// GOOD: DTO projection (better for read-only lists)
$dql = 'SELECT NEW App\Dto\EmployeeRow(e.name, c.name)
        FROM App\Entity\Employee e JOIN e.company c';
```

Flag: any `findAll()` or `findBy()` whose result is iterated in Twig/PHP with relation access.

## `flush()` Inside a Loop (Important)

See `symfony-review-rules.md`. Each `flush()` opens a SQL transaction.

## Inverse OneToOne (Important)

Doctrine cannot lazy-load the inverse side of a OneToOne. Each hydration of the parent triggers an immediate SELECT.

```php
// BAD: SELECT triggered even when $profile is never accessed
#[ORM\OneToOne(mappedBy: 'user')]
private ?UserProfile $profile;
```

Solutions: remove the inverse side, or use explicit `fetch: 'EAGER'`.

## `find()` to Set a FK (Suggestion)

```php
// BAD: full SELECT just to set a FK
$category = $this->categoryRepository->find($categoryId);
$product->setCategory($category);

// GOOD: proxy with no query
$category = $this->em->getReference(Category::class, $categoryId);
$product->setCategory($category);
```

## Missing Indexes (Important)

### On JoinColumn

Doctrine does **not** automatically create indexes on FK columns. Verify that `#[ORM\Index]` is present on frequently-used join columns.

### On Filtered/Sorted Columns

Any column used in `WHERE`, `ORDER BY`, or as an API Platform filter must have an index.

## `count($collection)` vs `isEmpty()` (Suggestion)

```php
// BAD: loads the entire collection or fires a COUNT(*) on each call
if (count($entity->getOrders()) > 0) { ... }

// GOOD: optimized query
if (!$entity->getOrders()->isEmpty()) { ... }
```

## Full Hydration for Read-Only Lists (Suggestion)

```php
// BAD: loads all properties and fills the identity map
$users = $this->userRepository->findAll();
// Template only uses getId() and getEmail()

// GOOD: DTO projection
$dql = 'SELECT NEW App\Dto\UserOption(u.id, u.email) FROM App\Entity\User u';
```

## Chained `array_map` + `array_filter` on Large Collections (Suggestion)

```php
// BAD: 2 full passes, intermediate array
$result = array_values(array_map(
    fn($item) => $item->getName(),
    array_filter($items, fn($item) => $item->isActive())
));

// GOOD: single pass
$result = [];
foreach ($items as $item) {
    if ($item->isActive()) {
        $result[] = $item->getName();
    }
}
```

Flag only on critical paths (batch processing, imports, over 1000 items).

## Missing Lazy Services (Suggestion)

A service that injects a heavy dependency (PdfGenerator, external HTTP client) used conditionally instantiates that dependency on every request.

```php
// GOOD
#[Lazy] private PdfGeneratorInterface $pdfGenerator,
```

## Doctrine Query Cache Not Configured in Production (Important)

Check in `doctrine.yaml`:
- `auto_generate_proxy_classes: false`
- `metadata_cache_driver` configured with a cache pool
- `query_cache_driver` configured with a cache pool

Without a cache, every `createQuery()` re-parses the DQL.

## `clear()` Without Re-Fetching References (Important)

`$em->clear()` detaches **all** entities. Any reference obtained before `clear()` is stale. Re-fetch with `getReference()` after each `clear()` in batch loops.
