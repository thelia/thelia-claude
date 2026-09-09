# Testing Thelia 3 - Strategy and FixtureFactory

> Infrastructure: 4 base classes + `FixtureFactory`. Isolated test DB (`.env.test` `DATABASE_NAME=test`). Propel transaction rollback per test.

## 1. Base classes

| Class | Inherits | Use |
|---|---|---|
| `IntegrationTestCase` | `KernelTestCase` | Service tests - kernel boot + Propel rollback + fixtures |
| `WebIntegrationTestCase` | `WebTestCase` | HTTP tests with `KernelBrowser` (shared transaction test <-> handlers) |
| `ApiTestCase` | `WebIntegrationTestCase` | API Platform tests (JWT login + `jsonRequest()` + JSON-LD assertions) |
| `ActionIntegrationTestCase` | `IntegrationTestCase` | Action listener tests (`dispatch()` shortcut) |

### `IntegrationTestCase`

- Boots kernel
- Initializes `Translator::$instance` and `URL::$instance` singletons
- Pushes a Request with Session onto `RequestStack`
- Propel transaction rollback wrapping (`$useTransaction = true`)
- Disables Propel instance pooling
- Helpers: `createFixtureFactory()`, `getService(class)`

```php
final class MyServiceIntegrationTest extends IntegrationTestCase
{
    public function testDoSomething(): void
    {
        $factory = $this->createFixtureFactory();
        $product = $factory->product(
            $factory->category(),
            $factory->taxRule(),
            $factory->currency(),
        );

        $service = $this->getService(MyService::class);
        $result = $service->doSomething($product);

        self::assertSame('expected', $result);
        // Auto rollback in tearDown
    }
}
```

### `WebIntegrationTestCase`

- `KernelBrowser` + `disableReboot()`
- Shared transaction test <-> HTTP handlers
- No manual Request (the browser handles it)

```php
final class CustomerHttpTest extends WebIntegrationTestCase
{
    public function testProfileIsRendered(): void
    {
        $this->client->request('GET', '/account/profile');
        self::assertResponseIsSuccessful();
    }
}
```

### `ApiTestCase`

- `extends WebIntegrationTestCase`
- Composes `AssertsJsonApi`, `LogsInAsAdmin`, `LogsInAsCustomer`
- `jsonRequest(method, uri, payload, token, format)` - `format`: `'jsonld'` (default), `'json'`, `'merge-patch+json'`

**Authentication helpers** (EXACT signatures):

| Method | Trait | Signature | Return | Use |
|---|---|---|---|---|
| `authenticateAsAdmin` | `LogsInAsAdmin` | `(?Admin $admin = null, string $password = 'password'): string` | JWT | API tests (pass token to `jsonRequest`) |
| `authenticateAsCustomer` | `LogsInAsCustomer` | `(?Customer $customer = null, string $password = 'password'): string` | JWT | API tests |
| `loginAsCustomerInSession` | `LogsInAsCustomer` | `(?Customer $customer = null): Customer` | Customer | HTTP web tests (pushes into session) |

The names `logInAsAdmin()` / `logInAsCustomer()` do NOT exist - do not invent them. `CustomerFacade::login()` takes a `CustomerLogin` DTO and is not suitable for tests.

```php
final class CategoryApiTest extends ApiTestCase
{
    public function testListAsAdmin(): void
    {
        $token = $this->authenticateAsAdmin();
        $this->jsonRequest('GET', '/api/admin/categories', null, $token);
        self::assertResponseStatusCodeSame(200);
        self::assertJsonContains(['@context' => '/api/contexts/Category']);
    }

    public function testCreateCategory(): void
    {
        $token = $this->authenticateAsAdmin();
        $this->jsonRequest('POST', '/api/admin/categories', [
            'visible' => true,
            'i18ns' => ['fr_FR' => ['title' => 'My category']],
        ], $token);
        self::assertResponseStatusCodeSame(201);
    }
}
```

### `ActionIntegrationTestCase`

- `extends IntegrationTestCase`
- `$this->dispatcher` (real) + `$this->factory` (FixtureFactory)
- `dispatch(Event, eventName)` - shortcut

```php
final class CustomerActionTest extends ActionIntegrationTestCase
{
    public function testAccountCreatedDispatch(): void
    {
        $event = new CustomerCreateOrUpdateEvent(/* ... */);
        $this->dispatch($event, TheliaEvents::CUSTOMER_CREATEACCOUNT);
        self::assertNotNull($event->getCustomer()->getId());
    }
}
```

## 2. FixtureFactory

`Tests\FixtureFactory` - entities + orders + carts. Methods:

| Category | Methods |
|---|---|
| Locale / currency | `lang()`, `currency()` |
| Customer | `customerTitle()`, `customer()`, `address()` |
| Catalog | `category()`, `product()`, `productSaleElement()`, `brand()`, `attribute()`, `attributeAv()`, `feature()`, `featureAv()` |
| Tax | `taxRule()`, `tax()` |
| Geo | `country()` |
| Admin | `admin()`, `profile()` |
| Folder / content | `folder()`, `content()` |
| Order | `orderStatus()`, `orderAddress()`, `order()` |
| Cart | `cart()` |
| Marketing | `coupon()` |

Each method persists via Propel `->save()` (rolled back at end of test).

```php
$factory = $this->createFixtureFactory();

$lang = $factory->lang();              // fr_FR by default
$customer = $factory->customer();
$category = $factory->category();
$taxRule = $factory->taxRule();
$currency = $factory->currency();

$product = $factory->product($category, $taxRule, $currency);
$pse = $factory->productSaleElement($product);

$order = $factory->order($customer);
```

## 3. Isolated test DB

`.env.test` override:
```
DATABASE_NAME=test
```

`bin/test-prepare`:
1. Creates the test DB (`db_create` standalone)
2. Applies the schema (core + modules)
3. Runs `module:post-activate-all`
4. Generates JWT keys
5. **Clears `var/propel/test/`** to force the correct DSN

If tests hit the wrong DB: delete `var/propel/test/` and re-run `bin/test-prepare`.

**DDEV danger - shell env overrides `.env.test`**: DDEV (`web_environment`) injects `DATABASE_*` at the **shell** level. `ddev exec php ...` sees them in `$_SERVER` before `Dotenv::bootEnv()` (which uses `overrideExistingVars=false`) runs -> **no `.env.test` can override an already-present variable**. A script or test targeting the `test` DB silently operates on the **dev** DB (`db`) and may wipe it. Symptom: "Creating database db" when `test` was expected, Propel DSN with `dbname=db`. Workarounds:
- Composer scripts chaining `--env=test`: prefix with `env -u DATABASE_HOST -u DATABASE_PORT -u DATABASE_NAME -u DATABASE_USER -u DATABASE_PASSWORD APP_ENV=test ...`
- Standalone script: `unset($_SERVER[$k], $_ENV[$k]); putenv($k);` for each `DATABASE_*` **before** `bootEnv()`.

## 4. Running tests

```bash
# All suites
ddev exec composer test

# Single suite
ddev exec ./vendor/bin/phpunit --testsuite=integration
ddev exec ./vendor/bin/phpunit --testsuite=api
ddev exec ./vendor/bin/phpunit --testsuite=flexy
ddev exec ./vendor/bin/phpunit --testsuite=backoffice
ddev exec ./vendor/bin/phpunit --testsuite=unit

# Single test
ddev exec ./vendor/bin/phpunit tests/Integration/MyModule/MyServiceTest.php
```

## 5. Typical API test pattern

```php
final class MyResourceApiTest extends ApiTestCase
{
    public function testCreateAndFetch(): void
    {
        $factory = $this->createFixtureFactory();
        $factory->customerTitle();

        $token = $this->authenticateAsAdmin();

        $this->jsonRequest('POST', '/api/admin/my-resources', [
            'code' => 'foo',
            'visible' => true,
        ], $token);
        self::assertResponseStatusCodeSame(201);

        $response = $this->jsonRequest('GET', '/api/admin/my-resources?code=foo', null, $token);
        $payload = json_decode($response->getContent(), true);
        self::assertSame(1, $payload['hydra:totalItems']);
    }
}
```

### Testing an admin controller with `BaseForm` (CSRF + form-urlencoded)

`ApiTestCase::jsonRequest()` is **EXCLUSIVELY** for API Platform endpoints (JSON-LD). For an HTTP controller using `BaseAdminController::validateForm()` with Thelia `BaseForm`, the test must:

- Use `WebIntegrationTestCase` (not `ApiTestCase`)
- Send `application/x-www-form-urlencoded` (not JSON)
- Include the CSRF token (`_token` field in the form payload)
- Push an admin in **session**, not via JWT

```php
final class AdminConfigTest extends WebIntegrationTestCase
{
    public function testAdminCanSaveConfig(): void
    {
        $factory = $this->createFixtureFactory();
        $admin = $factory->admin();

        // Push admin into session (not JWT)
        $this->getService(SecurityContext::class)->setAdminUser($admin);

        $this->client->request('POST', '/admin/module/mymodule', [
            'mymodule_config' => [
                '_token' => $this->getCsrfToken('mymodule.config'),  // name = form getName()
                'iban' => 'FR7630006000011234567890189',
                'bic' => 'BNPAFRPP',
            ],
        ]);

        self::assertResponseRedirects();   // 302 success
        self::assertSame('FR7630006000011234567890189', MyModule::getConfigValue('iban', ''));
    }
}
```

If `getCsrfToken()` does not exist in the project's base class, alternative: override `BaseForm::buildForm` with `csrf_protection => false` ONLY in `test` env (Symfony parameter). NEVER disable CSRF in production.

`WebIntegrationTestCase::client` is a `KernelBrowser` - all Symfony test client methods (request, followRedirect, getResponse, getCrawler) are available.

### Integration test for a listener that needs a logged-in customer

`ActionIntegrationTestCase` does NOT have the `LogsInAsCustomer` trait. For a listener that reads the current customer, two approaches:

```php
// Approach 1: extends ApiTestCase to use loginAsCustomerInSession
final class CartAddListenerTest extends ApiTestCase
{
    public function testRemovesFromWishlist(): void
    {
        $factory = $this->createFixtureFactory();
        $customer = $factory->customer();
        $product = $factory->product($factory->category(), $factory->taxRule(), $factory->currency());

        $this->loginAsCustomerInSession($customer);

        $event = new CartEvent($factory->cart($customer));
        $event->setProductId($product->getId());      // setProductId - not setProduct()
        $event->setProductSaleElementsId($pse->getId());
        $event->setQuantity(1);

        $this->getService(EventDispatcherInterface::class)
            ->dispatch($event, TheliaEvents::CART_ADDITEM);

        // assertions...
    }
}

// Approach 2: push customer into SecurityContext manually
$this->getService(SecurityContext::class)->setCustomerUser($customer);
```

## 6. Propel data seeding (outside FixtureFactory)

Traps that apply to any seed, import, manual fixture, or populate command:

- **Blocking `preDelete()`**: some models cancel their deletion via `preDelete()` returning `false`. Example: `Address::preDelete()` does `return !$this->getIsDefault();` -> `->delete()` is silently ignored on a default address, which accumulates between runs. Use `deleteAll()` (direct SQL DELETE, without hooks) for a clean reset.
- **Internal transaction**: `Customer::createOrUpdate()` opens its own `beginTransaction()/commit()` -> it escapes an enclosing transaction and breaks the idempotence of a `--reset`. For a seed, instantiate models directly (`new Customer()`, `setPassword()` hashes) as `FixtureFactory` does.
- **Backdating `created_at`**: `setCreatedAt($pastDate)` BEFORE `save()` is respected by the `timestampable` behavior (it only sets `now` `if (!isColumnModified(CREATED_AT))`). Useful for demo data spread over time.
- **`Order` requires NOT NULL FKs**: `payment_module_id` + `delivery_module_id`. Resolve them defensively (`ModuleQuery::filterByActivate(1)->filterByType(...)->findOne()` + fallback) rather than throwing (which rolls back everything). `Order::ref` is auto-generated in `postInsert` - do not set it.
- **`new URL($router)`**: `new URL()` without a router leaves the request context uninitialized -> crash on the first URL generation in a booted kernel.

## 7. Quality tooling - known false signals

- **PHPStan result cache stale**: `class.notFound` errors on `Base\*` Propel classes (or methods derived from i18n/timestampable traits) are often a **stale result cache** (the Base classes were regenerated, the cache points to the old state). Reflex BEFORE investigating: `phpstan clear-result-cache` + purge the analysis cache, then re-run. Hint: the "missing" class does in fact exist (`class_exists()` true).
- **PHPUnit 11 - silent XML warning**: a validation warning in `phpunit.xml` (`cacheResultFile` legacy, `<listeners>` deprecated) causes **exit 1** even when the suite shows "Tests: X, OK". This non-zero **stops the `composer test` chain** and hides the following suites (undetected latent regressions). If exit 1 + "OK": read the warning block above the stats, migrate to `cacheDirectory` + `<extensions><bootstrap>`.

## 8. Test traps

| Trap | Fix |
|---|---|
| `Translator::$instance` / `URL::$instance` non-null in test | must stay `?self = null` (fatal otherwise) |
| `final readonly class` not mockable (PHP 8.3 / PHPUnit 11) | a service intended to be mocked in unit tests = `readonly` without `final` (assumed exception; `final readonly` remains the default for DTOs and non-mocked services). Prefer integration tests without mocks. |
| Propel test cache pointing to wrong DB | `bin/test-prepare` clears `var/propel/test/` |
| Test does not rollback | protect `$useTransaction = true` (default) - do not override. One documented exception: a test that searches a MySQL/MariaDB `FULLTEXT` index over rows it just inserted must commit them (InnoDB merges FULLTEXT writes only at commit), so it runs without the wrapper and cleans up explicitly in `tearDown()` |
| `IntegrationTestCase::createFixtureFactory()` not used | always use factory for stable fixtures |
| Container singleton state leak | `IntegrationTestCase` reboots per test if necessary |
| `LogsInAsAdmin` without admin in DB | `$this->factory->admin()` before login |
| `getMainRequest()` null in `IntegrationTestCase` | base class pushes a Request with Session - do not reset |
| PHP deprecation in test | no warnings tolerated |
| `.env.test` not loaded | check `DATABASE_NAME=test` |
| `logInAsAdmin()` / `logInAsCustomer()` not found | use `authenticateAsAdmin()` / `authenticateAsCustomer()` (returns JWT string) |
| `CartEvent::setProduct()` not found | `setProductId(int\|string)` + `setProductSaleElementsId(int\|string)` |
| `CustomerFacade::login($customer)` TypeError | takes a `CustomerLogin` DTO - do not use in tests, prefer `loginAsCustomerInSession()` |
| `ActionIntegrationTestCase` without `LogsInAsCustomer` | extend `ApiTestCase` or push via `SecurityContext::setCustomerUser()` |
| FK `customer` crash on `factory->customer()` | call `factory->lang()`, `factory->currency()`, `factory->customerTitle()` in setup |

## Test infrastructure pitfalls

- Modules present in `local/modules/` are activated by `bin/test-prepare` and their listeners run during the core suites. A red core test can come from a local module, not from the core.
- PHPUnit runs with `APP_DEBUG=0`, so the compiled test container is never invalidated on a constructor signature change, an API group change or a template change. `cache:warmup --env=test` does not help either: it keeps stale serializer and validator metadata. Remove `var/cache/test` (and `var/propel/test/` after a vendor resync) before debugging.
- `phpunit.xml.dist` sets neither `failOnWarning` nor `failOnNotice`: a PHP warning is printed but the suite exits `0`. Read the output, not only the exit code. When piping `composer test`, add `set -o pipefail` or the exit code is the pipe's.
- `WebIntegrationTestCase::createFixtureFactory()` pushes a synthetic `GET /` request onto the `RequestStack` when none exists and never pops it. In an HTTP test that calls it, `getMainRequest()` returns that synthetic request, not the one the client sent.
- A test that fails while a Propel transaction is open leaks the nested-transaction counter; a single `rollBack()` in `tearDown()` only decrements it, and the next tests hang or see foreign data. Force the rollback down to depth zero.
- The currency-update test fetches the real ECB feed. A failure on an XML parse error is a network flake; rerun it alone before treating it as a regression.
- The core disables MySQL's strict transaction mode at boot. A test that expects strict-mode rejection passes silently; prove such a test can fail by sabotaging the code it covers.
