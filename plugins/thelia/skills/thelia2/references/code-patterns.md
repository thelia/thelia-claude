# Thelia 2.6 -- Code patterns

> Stack T2.6: PHP 8.2+, Symfony 6.4. Several modern patterns can be applied to new modules without modifying the core. This guide consolidates the recommended conventions.

## 1. `declare(strict_types=1)` -- required

Every PHP file in the module starts with:

```php
<?php
declare(strict_types=1);
```

No exceptions. This aligns the module with the PHP 8.2+ standard and prevents silent coercions that hide bugs (e.g., `string -> int` on a lost `customer_id`).

## 2. `final readonly class` for services and DTOs (PHP 8.2+)

```php
final readonly class ItemRepository
{
    public function __construct(
        private LoggerInterface $logger,
    ) {}
}

final readonly class CreateItemDto
{
    public function __construct(
        public string $title,
        public int $customerId,
    ) {}
}
```

**Exception**: Thelia controllers (`BaseFrontController`, `BaseAdminController`) cannot be `final readonly` because the hierarchy uses `#[Required]` setters. Keep the hierarchy without `readonly` for controllers (fine for services and pure DTOs).

`BaseForm` is not `readonly` either because of the `init()` non-constructor (SIGNAL-13).

## 3. Repository pattern (STRICT PROJECT RULE)

**Every Propel query or third-party API call MUST go through an injectable Repository class.** Never inline in:
- Controllers (`BaseFrontController`, `BaseAdminController`)
- Loops (`buildModelCriteria` can delegate to a repo)
- Application services
- Listeners
- Hooks

Rationale: testability, isolation, mocking, reusability. The T2.6 core often mixes Propel queries everywhere -- the project convention imposes the separation.

### Tolerated exception -- clarification

One case only: direct queries on core models (`CategoryQuery::create()`, `CountryQuery::create()`) **inside a native core loop** (`Loop/Product.php`, `Loop/Category.php`) or a very tightly-scoped framework fork.

**Does NOT apply to custom modules**, even if the query targets a core model. Example: a `WishlistItemLoop` (custom module) executing `ProductQuery::create()->filterByVisible(1)->find()` in `buildModelCriteria()` violates the rule, even though `Product` is a core model. The query must go through the module's repository (join `useProductQuery()->endUse()` in the repo's `buildBaseQuery()`) or through an injected core repository.

**Summary**: in a custom module, **no** `XxxQuery::create()` inline in:
- `buildModelCriteria()` of a loop
- `__invoke()` of a listener
- hook handler method
- controller action
- service business method

### Bulk Propel operations

Prefer `deleteAll()` / `updateAll()` over `foreach $items as $item -> $item->delete()` loops:

```php
// 1 SQL query instead of SELECT + N DELETE
WishlistItemQuery::create()
    ->filterByCustomerId($customerId)
    ->filterByProductId($productId)
    ->deleteAll();
```

### Race condition `findOne + new + save`

The `findOne() -> if null -> new + save()` pattern is prone to a race condition if two concurrent requests arrive for the same unique key. Prefer Propel `findOneOrCreate()` (atomic SELECT + INSERT) or catch `ConstraintViolationException` and retry with `findOne()`.

### Repository pattern

```php
<?php
declare(strict_types=1);

namespace MyModule\Repository;

use Propel\Runtime\ActiveQuery\Criteria;
use MyModule\Model\Item;
use MyModule\Model\ItemQuery;

final readonly class ItemRepository
{
    public function findByPk(int $id): ?Item
    {
        return ItemQuery::create()->findPk($id);
    }

    public function findVisibleByCategory(int $categoryId, int $limit = 50): array
    {
        return ItemQuery::create()
            ->filterByVisible(1)
            ->filterByCategoryId($categoryId)
            ->orderByPosition()
            ->limit($limit)
            ->find()
            ->getData();
    }

    public function save(Item $item): void
    {
        $item->save();
    }

    public function delete(Item $item): void
    {
        $item->delete();
    }
}
```

### Third-party API repository

```php
final readonly class StripePaymentRepository
{
    public function __construct(
        private \Stripe\StripeClient $client,
    ) {}

    public function createPaymentIntent(int $amountCents, string $currency): \Stripe\PaymentIntent
    {
        return $this->client->paymentIntents->create([
            'amount' => $amountCents,
            'currency' => $currency,
        ]);
    }
}
```

### Loop with Repository

```php
final class ItemLoop extends BaseLoop implements PropelSearchLoopInterface
{
    public function __construct(
        private readonly ItemRepository $repository,
    ) {
        parent::__construct(/* inject via container -- see autoconfigure docs */);
    }

    public function buildModelCriteria()
    {
        // Better: call $this->repository->buildVisibleQuery() which returns the ModelCriteria
        // If the loop genuinely needs the builder, the query exposes it via a dedicated method
        return $this->repository->buildBaseQuery()
            ->filterByVisible($this->getVisible());
    }
}
```

## 4. `enum` PHP 8.1 for fixed values

Replace string constants with backed enums:

```php
enum ItemStatus: string
{
    case Draft     = 'draft';
    case Published = 'published';
    case Archived  = 'archived';
}

final readonly class Item { public ItemStatus $status; }
```

## 5. `#[AsEventListener]` SF 6.x instead of XML

```php
use Symfony\Component\EventDispatcher\Attribute\AsEventListener;
use Thelia\Core\Event\TheliaEvents;

#[AsEventListener(event: TheliaEvents::ORDER_BEFORE_PAYMENT)]
final class OrderListener
{
    public function __invoke(OrderEvent $event): void { /* ... */ }
}
```

Auto-discovered via `autoconfigure(true)` in `configureServices()`. More testable than `<service><tag name="kernel.event_listener">` XML.

## 6. `#[AsCommand]` invokable SF 6.4

```php
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;

#[AsCommand(name: 'mymodule:hello')]
final class HelloCommand extends Command
{
    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $output->writeln('hello');
        return Command::SUCCESS;
    }
}
```

Auto-tagged via `autoconfigure(true)`. No need to declare `<command>` in config.xml.

## 7. `#[Route]` PHP 8 (never `@Route`)

```php
use Symfony\Component\Routing\Attribute\Route;

#[Route('/admin/mymodule')]
final class ItemController extends BaseAdminController
{
    #[Route('/items', name: 'mymodule.admin.items.list', methods: ['GET'])]
    public function list(): Response { /* ... */ }
}
```

`@Route` Doctrine annotations are deprecated in SF 6.4 and removed in SF 7. T2.6 is SF 6.4, so migrate now.

### Loading mechanism (Thelia 2 specific)

`Thelia\Core\Routing\AnnotationRouter` (tag `router.register`, priority 255) automatically scans `<module>/Controller/` at boot via `AnnotationDirectoryLoader`. No declaration in `routing.xml` needed. Source: `core/lib/Thelia/Core/Routing/AnnotationRouter.php`.

**Major pitfall**: these routes are **invisible** in `php Thelia debug:router` and `router:match` returns "None of the routes match" -- those commands only list `router.default` (Symfony FrameworkBundle), not the full `chainRouter`.

To verify a module route is loaded:
- Direct hit via curl + admin cookie (200 or auth required = route found, true 404 = absent)
- Inspect cache: `var/cache/{env}/routing/router.{Module}/url_matching_routes.php` contains **only** `routing.xml` routes. `#[Route]` attribute routes live elsewhere in cache.

Optional prefix per module: override `BaseModule::getAnnotationRoutePrefix(): string` (empty by default). Applied to all annotated routes in the module via `AnnotationRouter::getRouteCollection()`.

### Propel cache pitfall after schema.xml modification

After bumping `module.xml::version` + adding a column in `schema.xml` + creating `Config/update/X.X.X.sql`:
1. `php Thelia module:refresh` applies the SQL via `BaseModule::update()`
2. But the TableMap in `var/cache/{env}/propel/model/{Module}/Model/Map/{Table}TableMap.php` **remains stale** -- new `COL_*` constants and Propel getters/setters do not appear
3. **Required**: `rm -rf var/cache/dev/* var/cache/prod/* && php Thelia cache:clear`
4. Verify: `grep COL_NEW_COLUMN var/cache/dev/propel/model/.../TableMap.php`

### Idempotent SQL migration (MariaDB 10.11+)

Pattern for `Config/update/X.X.X.sql` that can re-run without breaking:

```sql
SET FOREIGN_KEY_CHECKS = 0;

ALTER TABLE my_table
    ADD COLUMN IF NOT EXISTS my_status VARCHAR(20) DEFAULT 'pending' AFTER existing_col,
    ADD COLUMN IF NOT EXISTS my_message LONGTEXT NULL AFTER my_status;

CREATE INDEX IF NOT EXISTS my_table_status_idx ON my_table (my_status);

-- Retroactive init on existing rows
UPDATE my_table SET my_status = 'synced' WHERE existing_col IS NOT NULL;

SET FOREIGN_KEY_CHECKS = 1;
```

`IF NOT EXISTS` on `ADD COLUMN` and `CREATE INDEX` is native MariaDB 10.6+ (non-standard SQL, but Thelia 2 targets MariaDB exclusively).

## 8. `#[AutowireIterator]` / `#[AutowireLocator]`

```php
use Symfony\Component\DependencyInjection\Attribute\AutowireIterator;

final readonly class FilterRunner
{
    public function __construct(
        #[AutowireIterator('mymodule.filter')] private iterable $filters,
    ) {}
}
```

`#[TaggedIterator]` / `#[TaggedLocator]` are deprecated in SF 7.1+. T2.6 stays on SF 6.4 but already uses the new attributes to prepare for the transition.

## 9. No abbreviations

`CustomerService`, not `CustSvc`. `OrderRepository`, not `OrderRepo`. The code should be readable to developers who are new to the module.

Name methods with business verbs (`findVisibleByCategory()`) rather than technical ones (`getQueryByX()`).

## 10. No redundant PHPDoc

Code is documentation -- no PHPDoc that paraphrases the signature:

```php
// BAD
/**
 * Get the customer
 * @return Customer
 */
public function getCustomer(): Customer

// GOOD -- the signature is sufficient
public function getCustomer(): Customer
```

PHPDoc is allowed for:
- Non-obvious `@throws` (specific exception)
- Complex types PHP cannot express (e.g., `array<string, list<Foo>>`)
- Documenting a non-trivial business rule or pitfall

## 11. Autowired vs config.xml listeners

| Case | Choice |
|---|---|
| New T2.6 module | `#[AsEventListener]` + `autoconfigure(true)` |
| Listener needing explicit priority | `<tag name="kernel.event_listener" priority="...">` XML |
| Listener that must be disableable via DB config | `<service>` + factory or conditional injection |

## 12. `MapRequestPayload` for modern REST controllers

Available if the module (SF 6.3+) wants to modernize its form-driven controllers:

```php
#[Route('/api/mymodule/items', methods: ['POST'])]
public function create(
    #[MapRequestPayload] CreateItemDto $dto,
): JsonResponse {
    $item = $this->repository->createFromDto($dto);
    return new JsonResponse($item, Response::HTTP_CREATED);
}
```

Reserve for non-Smarty endpoints (API, AJAX). For classic HTML web forms, keep `BaseForm` + `validateForm()`.

## 12bis. Strict DI -- `new XxxRepository()` FORBIDDEN

`final readonly class XxxRepository` classes must be **injected**, never instantiated via `new`. Even a repository with no external dependency today may acquire one later (logger, cache) -- manual instantiation then silently bypasses the Symfony container.

### Specific pitfalls

In certain inherited methods from the core (`AbstractPaymentModule::pay()`, `AbstractDeliveryModule::getPostage()`, `BaseHook::onXxx()`), constructor injection is not possible. Solutions in order of preference:

1. **Use the container**: `$this->getContainer()->get(MyRepository::class)`
2. **Module static method**: `BaseModule::getConfigValue()` / `setConfigValue()` directly, without a repository
3. **For a BaseHook**: declare the repository as a property via `__construct` (the container injects it) then use `$this->repository`

### TO BLOCK IN REVIEW

```php
// BAD -- bypasses DI
public function pay(Order $order): Response
{
    $repository = new BankTransferConfigRepository();
    // ...
}

// GOOD -- via container
public function pay(Order $order): Response
{
    $repository = $this->getContainer()->get(BankTransferConfigRepository::class);
    // ...
}
```

## 13. Summary

1. `declare(strict_types=1)` systematically
2. `final readonly` for services and DTOs (except Thelia controllers + BaseForm)
3. **Strict Repository pattern** -- no inline Propel query in controller/loop/listener/hook (except tightly-scoped native core model)
4. `enum` instead of string constants
5. `#[AsEventListener]`, `#[AsCommand]`, `#[Route]`, `#[AutowireIterator]` PHP 8
6. No abbreviations in naming
7. No redundant PHPDoc -- strict types in signature
8. English for technical identifiers
9. No `ContainerAwareTrait` or `$container->get()` in services
10. CSRF never disabled on `BaseForm`
11. **Never `new XxxRepository()` inline** -- always via DI or `$this->getContainer()->get()` in inherited methods without injection
12. `XxxQuery::create()` inline forbidden in all custom module code (loop, listener, hook, controller, service) -- exception **only** for native core loops
