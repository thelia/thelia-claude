# Symfony 7 Review Rules

Severity-focused review table. Canonical code standards are defined in the `symfony` and `api-platform` skills. This file references those standards and adds review severity.

## Contents

- Rules by severity (table)
- Review-only rules (details)
  - Doctrine migrations (destructive, NOT NULL without DEFAULT, rename, missing FK index, editing post-deploy)
  - `ContainerInterface` service locator
  - Events inside nested transactions
  - `paginationEnabled: false` without a maximum
  - Twig `createTemplate($variable)`

## Rules by Severity

### Doctrine ORM 3

| Rule | Severity | Canonical Standard |
|---|---|---|
| `EntityManager::flush($entity)` used (ORM 3+) | **Blocking** | `symfony/references/doctrine.md` § ORM 3 Migration |
| `GeneratedValue` without `strategy: 'CUSTOM'` for UUID v7 | **Blocking** | `symfony/references/doctrine.md` § UUID v7 |
| UUID PK as `CHAR(36)` instead of `BINARY(16)` | **Important** | `symfony/references/doctrine.md` § UUID v7 |
| `flush()` inside a loop | **Blocking** | `symfony/references/doctrine.md` § Performance |
| Missing `onDelete` on `JoinColumn` | **Blocking** | `symfony/references/doctrine.md` § Cascade |
| Incomplete multi-level cascade | **Blocking** | `symfony/references/doctrine.md` § Cascade |
| `cascade: ['remove']` on the ManyToOne (child) side | **Blocking** | `symfony/references/doctrine.md` § Cascade |
| `orphanRemoval: true` on a shared entity | **Blocking** | `symfony/references/doctrine.md` § Cascade |
| `find()` to set a FK (instead of `getReference()`) | Suggestion | `symfony/references/doctrine.md` § getReference |
| Missing index on JoinColumn | **Important** | `symfony/references/doctrine.md` § Index |

### API Platform 4.2

| Rule | Severity | Canonical Standard |
|---|---|---|
| Custom Provider/Processor for direct DTO-to-Entity mapping | **Important** | `api-platform/references/api-platform-42-features.md` § ObjectMapper |
| `ObjectMapper` without validation | **Important** | Review-only (see below) |
| Large collection without `json_streamer: true` (over 1000 items) | **Important** | `code-review-expert/references/performance-checklist.md` § JsonStreamer |
| `#[ApiFilter]` on new AP 4.2+ code | Suggestion | `api-platform/references/filters.md` § QueryParameter |
| Operation without `security` | **Blocking** | `api-platform/SKILL.md` § JWT Authentication |
| `paginationEnabled: false` without `paginationMaximumItemsPerPage` | **Important** | Review-only (see below) |
| Entity used directly as API Resource (non-trivial) | **Important** | `api-platform/SKILL.md` § Architecture Decision |

### Services / DI

| Rule | Severity | Canonical Standard |
|---|---|---|
| `ContainerInterface` injected into a service | **Blocking** | Review-only (see below) |
| `#[Required]` setter injection | **Important** | `symfony/SKILL.md` § Anti-Patterns |
| Non-`final` service | **Important** | `symfony/SKILL.md` § Services |

### Messenger

| Rule | Severity | Canonical Standard |
|---|---|---|
| Entity as message parameter | **Blocking** | `symfony/references/messenger.md` § Message Rules |
| Non-idempotent handler | **Blocking** | `symfony/references/messenger.md` § Idempotence |
| `RecoverableMessageHandlingException` on a permanent error | **Blocking** | `symfony/references/messenger.md` § Recoverable |
| Wildcard routing `'*': async` | **Important** | `symfony/references/messenger.md` § Transport |

### Events

| Rule | Severity | Canonical Standard |
|---|---|---|
| Business logic in `kernel.request`/`response` without `isMainRequest()` guard | **Important** | Review-only |
| Events dispatched inside a transaction | **Important** | Review-only (see below) |

### Forms / Twig

| Rule | Severity | Canonical Standard |
|---|---|---|
| Validation on the entity instead of the input DTO | **Important** | `symfony/SKILL.md` § Forms |
| Form Type without `data_class` | Suggestion | `symfony/SKILL.md` § Forms |
| `twig->createTemplate($variable)` with user input | **Blocking** | Review-only (see below) |
| Manual HTML form without CSRF | **Important** | `symfony/references/security.md` § CSRF |

### Migrations

All rules are review-only; see the detailed section below. Blocking: destructive without a plan, `NOT NULL` without `DEFAULT`, migration edited post-deploy. Important: direct rename, missing FK index, `kernel.request` events without guard.

## Review-Only Rules (details)

### `ContainerInterface` in a Service (Blocking)

Service locator anti-pattern. It hides dependencies, breaks typing, and breaks `final readonly`.

```php
// BAD: service locator
final class InvoiceService
{
    public function __construct(private readonly ContainerInterface $container) {}
    public function process(): void {
        $mailer = $this->container->get('mailer');
    }
}

// GOOD: explicit injection
final readonly class InvoiceService
{
    public function __construct(private MailerInterface $mailer) {}
}
```

Exceptions: `CompilerPass`, explicit factories.

### Events Dispatched Inside a Transaction (Important)

A listener that calls `flush()` during a `postFlush` causes nested transactions and deadlocks. Correct pattern:

```php
// BAD: nested flush
#[AsEventListener]
final readonly class SyncExternalService
{
    public function __invoke(OrderCreatedEvent $event): void
    {
        $this->externalClient->send($event->order);
        $this->em->flush(); // nested transaction if caller has not committed yet
    }
}

// GOOD: dispatch async, process outside the transaction
public function __invoke(OrderCreatedEvent $event): void
{
    $this->messageBus->dispatch(new SyncOrderToExternalService($event->order->getId()));
}
```

### `paginationEnabled: false` Without `paginationMaximumItemsPerPage` (Important)

Dumping the entire table is a DoS risk. When pagination is intentionally disabled (internal export), require a strict maximum:

```php
new GetCollection(
    paginationEnabled: false,
    paginationMaximumItemsPerPage: 500, // limit even without pagination
)
```

### Twig `createTemplate($variable)` With User Input (Blocking)

SSTI (Server-Side Template Injection) with possible RCE. Using `createTemplate()` or directly rendering a string that contains user data allows injection of Twig filters and functions.

```php
// BAD: SSTI
$rendered = $twig->createTemplate($userInput)->render();

// GOOD: file template with context
$rendered = $twig->render('emails/welcome.html.twig', ['user' => $user]);
```

### `ObjectMapper` Without Validation (Important)

AP 4.2 `ObjectMapper` transforms without validating. If the resource has no `validationContext` and the validator is not called manually, `#[Assert]` constraints are silently ignored.

Verify at least one of:
- `validationContext: ['groups' => [...]]` on the operation (AP applies it automatically)
- An explicit call to `$this->validator->validate(...)` in a custom processor

### Doctrine Migrations

#### Destructive Migration Without a Rollback Plan (Blocking)

```php
// BLOCKING without justification and a plan:
$this->addSql('DROP TABLE old_table');
$this->addSql('ALTER TABLE users DROP COLUMN legacy_field');
$this->addSql('ALTER TABLE orders MODIFY status VARCHAR(20) NOT NULL'); // reduces size
```

Require either a business justification with a rollback plan, or an add-copy-drop strategy spread across multiple deploys.

#### `NOT NULL` Without `DEFAULT` on an Existing Column (Blocking)

```php
// BAD: fails if the table already contains data
$this->addSql('ALTER TABLE users ADD phone VARCHAR(20) NOT NULL');

// GOOD: two migrations
// Migration 1: add nullable
$this->addSql('ALTER TABLE users ADD phone VARCHAR(20) DEFAULT NULL');
// Migration 2 (after data backfill): switch to NOT NULL
$this->addSql('ALTER TABLE users MODIFY phone VARCHAR(20) NOT NULL');
```

#### Column Rename (Important)

A `RENAME COLUMN` breaks code referencing the old name until the deploy finishes. Use the add-copy-drop strategy across 3 migrations:

1. Add the new column
2. Copy the data and update the code to read/write the new column
3. Drop the old column (next migration, after deploy)

#### Missing Index on New FK (Important)

Any migration that adds an FK column (`ADD COLUMN xxx_id INT`) must include a corresponding `CREATE INDEX`. Doctrine `make:migration` does not always generate indexes.

#### Migration Edited After Deploy (Blocking)

Never modify a migration that has already been executed on another environment (staging, preprod, production). Create a new corrective migration instead.
