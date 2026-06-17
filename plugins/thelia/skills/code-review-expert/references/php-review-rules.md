# PHP 8.3+ Review Rules

Severity-focused review table. Canonical code standards are defined in the `php` skill (`/skills/php/SKILL.md` and `references/`). This file references those standards and adds review severity.

## Contents

- Blocking (6 rules): strict_types, final readonly, guard clauses, catch-all, JSON_THROW, business in controller/command, I/O in constructor
- Important (5 rules): mixed without narrowing, generic @return array, missing never, #[\Override], typed constants
- Suggestion / nit (4 rules): switch to match, strpos to str_contains, string callables, nullsafe

## Rules by Severity

| # | Rule | Severity | Canonical Standard |
|---|---|---|---|
| 1 | Missing `declare(strict_types=1)` in file | **Blocking** | `php/SKILL.md` § Strict Typing |
| 2 | Service or DTO without `final readonly class` (excluding Doctrine entities) | **Blocking** | `php/SKILL.md` § Classes |
| 3 | Nesting over 2 levels without guard clauses | **Blocking** | `php/SKILL.md` § Fail-First |
| 4 | Catch-all `catch (\Exception)` or `catch (\Throwable)` | **Blocking** | `php/SKILL.md` § Fail-First |
| 5 | `json_decode()` / `json_encode()` without `JSON_THROW_ON_ERROR` | **Blocking** | `php/SKILL.md` § Fail-First |
| 6 | Business logic in controller or command | **Blocking** | `symfony/SKILL.md` § Controllers |
| 7 | Constructor that executes I/O (DB query, HTTP call, file read) | **Blocking** | Review-only (see below) |
| 8 | `mixed` without immediate narrowing | **Important** | `php/SKILL.md` § Type System |
| 9 | `@return array` without a generic PHPDoc type | **Important** | Review-only (see below) |
| 10 | Missing `never` on a method that always throws | **Important** | `php/SKILL.md` § Modern Features |
| 11 | Missing `#[\Override]` on an override (PHP 8.3+) | **Important** | `php/SKILL.md` § Modern Features |
| 12 | Missing typed class constant (`const string X` vs `const X`, PHP 8.3+) | **Important** | `php/SKILL.md` § Modern Features |
| 13 | `switch` that assigns a variable | Suggestion | `php/SKILL.md` § Modern Features |
| 14 | `strpos() !== false` instead of `str_contains()` | Suggestion | `php/SKILL.md` § Anti-Patterns |
| 15 | String callable (`'strtolower'`) instead of first-class (`strtolower(...)`) | Suggestion | `php/SKILL.md` § Modern Features |
| 16 | Chain of null checks instead of nullsafe `?->` | Suggestion | Review-only (see below) |

## Review-Only Rules (details)

### 7. Constructor Executing I/O (Blocking)

Services that run DB queries, HTTP calls, file reads, or expensive instantiation inside `__construct()`. The constructor must only assign injected dependencies.

```php
// BAD: DB query on every instantiation
public function __construct(private readonly EntityManagerInterface $em) {
    $this->config = $em->find(Config::class, 1); // I/O!
}

// GOOD: lazy load on first use
public function getConfig(): Config {
    return $this->config ??= $this->em->find(Config::class, 1);
}
```

### 9. `@return array` Without Generic Type (Important)

```php
// BAD: implicitly array<mixed, mixed>, PHPStan 10 flags this
/** @return array */
public function getItems(): array { }

// GOOD
/** @return array<int, Product> */
public function getItems(): array { }

// BETTER: list when 0-indexed contiguous
/** @return list<Product> */
public function getItems(): array { }
```

### 16. Nullsafe Operator (Suggestion)

```php
// BAD
if ($order !== null && $order->getCustomer() !== null) {
    $city = $order->getCustomer()->getAddress()->getCity();
}

// GOOD
$city = $order?->getCustomer()?->getAddress()?->getCity();
```
