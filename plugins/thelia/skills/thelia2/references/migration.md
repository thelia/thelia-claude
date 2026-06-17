# Thelia 2.6: Migration

> Migration guide for T2.5 -> T2.6 modules. For T2 -> T3 migration, see the `thelia3` skill (out of scope here).

## 1. T2.5 -> T2.6: major version jumps

| Subject | T2.5 | T2.6 |
|---|---|---|
| Symfony | 5.4 | **6.4** |
| PHP | 7.4 / 8.0 | **8.2+** |
| API Platform | absent / partial | **3.4** integrated (bundle) |
| Propel | 2.x | 2.x (stable) |
| Smarty | kept | kept |
| JWT | absent / Lexik 1.x | **Lexik 2.x** without refresh |

## 2. Structural breaking changes

### 2.1 PHP 8.2+: strict types required

- `declare(strict_types=1)` recommended systematically
- Silent `string -> int` coercion no longer forgives; audit entry points (Request, Form, Propel query)
- `#[ReturnTypeWillChange]` may appear on some overrides; align signatures with core

### 2.2 Symfony 6.4: deprecations

| Old | New |
|---|---|
| `@Route` annotations | `#[Route]` PHP 8 attribute |
| `ContainerAwareTrait` in services | constructor injection |
| `scope="request"` config.xml | `RequestStack` injection |
| `$container->get('id')` in services | constructor injection |
| `KernelEvents::*` strings | typed constants |
| `EventDispatcher::dispatch($eventName, $event)` | `dispatch($event, $eventName)` (reversed order) |

### 2.3 API Platform 3.4 (new)

If the module exposed a custom API (manual controllers + serializer) in T2.5, T2.6 allows migration to AP 3.4:

- Define a resource: `implements PropelResourceInterface` + `use PropelResourceTrait`
- Operations: `#[ApiResource(operations: [new GetCollection(...), new Get(...), ...])]`
- Filters: `#[ApiFilter]` with **Thelia custom Propel filters only** (no Doctrine, which causes a runtime crash)
- Format: JSON-LD only (`application/ld+json`)
- JWT: `POST /api/{front|admin}/login` Lexik 2.x

See [api-platform.md](api-platform.md) for the complete pattern.

### 2.4 Doctrine AP filters -> custom Propel filters

If an early module already attempted AP, it likely used Doctrine AP filters:

```php
// BEFORE: INCOMPATIBLE WITH PROPEL, crash
use ApiPlatform\Doctrine\Orm\Filter\SearchFilter;

#[ApiFilter(SearchFilter::class, properties: ['ref' => 'partial'])]
class Item implements PropelResourceInterface { /* ... */ }
```

```php
// AFTER T2.6: Thelia custom Propel filters
use Thelia\Api\Bridge\Propel\Filter\SearchFilter;

#[ApiFilter(SearchFilter::class, properties: ['ref' => 'partial'])]
class Item implements PropelResourceInterface { /* ... */ }
```

Available Thelia Propel filters: `SearchFilter`, `OrderFilter`, `BooleanFilter`, `RangeFilter`, `DateFilter`, `NotInFilter`, `AbstractFilter`. See [api-platform.md §8](api-platform.md).

### 2.5 i18n: `AbstractTranslatableResource` + `I18nCollection`

If the module has an i18n resource, T2.6 provides a dedicated pattern:

```php
final class Item extends AbstractTranslatableResource implements PropelResourceInterface
{
    use PropelResourceTrait;

    public I18nCollection $i18ns;

    // ...
}

final class ItemI18n extends I18n
{
    public ?string $title = null;
    public ?string $description = null;
}
```

## 3. module.xml: alignment

| Field | T2.6 note |
|---|---|
| `<thelia>2.6.0</thelia>` | minimum required to function |
| `<stability>` | `prod` recommended for distribution |
| `<type>` | `classic` / `delivery` / `payment` / `marketplace` / `price` / `accounting` / `seo` / `administration` / `statistic` |
| `<fullnamespace>` | must point to the Module class FQCN |

## 4. config.xml: alignment

- `config.xml` remains **required EVEN IF EMPTY** in T2.6 (`Thelia.php:555`, SIGNAL-03)
- `<services>` can be replaced by static `configureServices()` with `autowire()->autoconfigure()` but XML remains valid
- Hooks: prefer `<hook>` XML because `autoconfigure` alone on `BaseHookInterface` is not enough (SIGNAL-06)

## 5. Code patterns to modernize

| Modernization | Recommended adoption |
|---|---|
| `MapRequestPayload` SF 6.3+ for REST form-driven controllers | Yes for non-Smarty API endpoints |
| `#[AsEventListener]` SF 6.x | Yes, replaces XML |
| `#[AsCommand]` SF 6.4 | Yes, already standard |
| `#[AutowireIterator]` / `#[AutowireLocator]` | Yes, prepares for SF 7.1+ |
| `final readonly class` PHP 8.2 | Yes, required for stateless services and DTOs |
| `enum` PHP 8.1 | Yes, replaces string constants |
| `match` expressions | Yes, replaces `switch` |
| `RequestStack` injection (vs `BaseModule::getRequest()`) | Yes in services |
| Repository pattern (extracted Propel queries) | Yes |
| `#[Assert]` Symfony Validator on DTOs | Yes |

## 6. Code patterns NOT to adopt (T2.6)

| Pattern | Reason |
|---|---|
| Twig | Does not exist in T2.6 front; keep Smarty |
| LiveComponent / TwigComponent | Do not exist in T2 |
| `QueryParameter` AP 4.1+ | Does not exist in AP 3.4 |
| `Metadata Mutators` AP 4.2+ | Does not exist in AP 3.4 |
| `JsonStreamer` SF 7.3 | Does not exist in SF 6.4 |
| `ObjectMapper` SF 7.3 | Does not exist in SF 6.4 |
| `IntegrationTestCase` / `FixtureFactory` / `ApiTestCase` | Do not exist in T2 (vs T3); use a custom harness |

## 7. Tests: no regression possible

T2.6 still has no `IntegrationTestCase` or `FixtureFactory`. If the migration adds tests:
- Build a custom harness (`tests/{Module}/AbstractTestCase.php`) that boots `(new Thelia('test', true))->boot()` + manual Propel transaction
- DO NOT use `tests/Legacy/` (silently ignored, SIGNAL-14)
- `WebTestCase::tearDown()` core does not rollback -> dev DB pollution (SIGNAL-15)

See [testing.md](testing.md) for the pattern.

## 8. Security: audit during migration

| Point | What to check |
|---|---|
| BOLA POST front | every `POST /api/front/account/*` endpoint that writes with a `customerId` field must add `securityPostDenormalize: 'object.customerId == user.getId()'` (SIGNAL-08) |
| GetCollection front | add `security: 'is_granted("ROLE_CUSTOMER")'` minimum on front Operations (SIGNAL-09) |
| Open-redirect `success_url` | if the module renders a public form, whitelist host for `success_url` (SIGNAL-16) |
| CSRF | always active on `BaseForm`; NEVER `csrf_protection => false` |
| `{php}` Smarty | no user string should ever be rendered in a Smarty template (no sandbox) |

## 9. Migration T2 -> T3: out of scope

To migrate a T2.6 module to T3 (Symfony 7.4 LTS, AP 4.3 standalone, front Twig/Flexy, tests `IntegrationTestCase`/`FixtureFactory`), see the **skill `thelia3`**.

Summary of major T2.6 -> T3 changes:
- XML hooks removed in favor of PHP `#[Hook(...)]` attributes auto-discovered (in T3, `BaseHook` + `getSubscribedHooks()` AUTO-tags WITHOUT XML)
- Loops auto-discovered (same)
- API Platform 4.3 standalone (`api-platform/symfony`), no more bundle
- Front Twig + FlexyBundle + LiveComponent + TwigComponent: rewrite front Smarty `.html` files to `.html.twig`
- `IntegrationTestCase` + `ApiTestCase` + `FixtureFactory` + isolated test DB
- Back-office remains Smarty (continuity)

For a multi-version T2/T3 module: abstract the layers (queries via Repository, services, events) through common interfaces, duplicate hooks/forms/loops/templates per version.
