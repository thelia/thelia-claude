# Thelia 2.6: Tests: reality and patterns

> Source: `tests/`, `phpunit.xml.dist`, `tests/Functional/WebTestCase.php:25`. **WARNING**: T2.6 has NO `IntegrationTestCase`, NO `ApiTestCase`, NO `FixtureFactory`, NO isolated test DB. Testing a module means building your own harness.

## 1. Reality of the test framework

`phpunit.xml.dist` covers **2 test suites only**:

- `unit` -> `tests/Unit/` (in practice empty; only `tests/Unit/TestCase.php extends PHPUnit\Framework\TestCase`)
- `functional` -> `tests/Functional/` (HTTP smoke via Symfony `WebTestCase`)

`tests/Legacy/` is **not referenced** in phpunit.xml.dist: `phpunit --testsuite unit|functional` never runs it. It IS executed by the `test-legacy` Composer script, which `composer test` (and therefore `composer ci`, run by the GitHub workflow on `2.6`) chains after the unit and functional suites, after activating the modules the legacy tests need (CustomDelivery, Cheque, HookTest...). A green CI proves what these scripts execute, nothing more: check `composer.json` scripts and `.github/workflows/test.yml` on the target branch before citing CI as proof. Bootstrap: `tests/bootstrap.php` (autoload + `Dotenv::bootEnv('.env')`).

`KERNEL_CLASS = App\Kernel`, `APP_ENV = test`, **no specific `.env.test`**, **no isolated test DB** (shares the dev DB).

## 2. What is MISSING (vs T3)

- No `IntegrationTestCase` (boot kernel + push Request + transaction rollback per test)
- No `ApiTestCase` (JWT login + JSON-LD assertions)
- No `FixtureFactory` (entities + orders + carts factory methods)
- No isolated test DB
- `WebTestCase::tearDown()` has no rollback (commented lines `// self::$connection->beginTransaction()` / `// self::$connection->rollBack()` in `WebTestCase.php:50/55`) -> **DEV DB POLLUTION** (SIGNAL-15)

## 3. Symfony WebTestCase (HTTP smoke)

Basic functional pattern:

```php
<?php
declare(strict_types=1);

namespace MyModule\Tests\Functional;

use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;

final class HomePageTest extends WebTestCase
{
    public function testHomePageRespondsOk(): void
    {
        $client = static::createClient();
        $client->request('GET', '/');
        self::assertResponseIsSuccessful();
    }
}
```

The Thelia `WebTestCase` adds a `loginAdmin()` helper (see `tests/Functional/WebTestCase.php`).

## 4. Recommended pattern for testing a T2.6 module

Build a custom harness.

### Parent TestCase harness

```php
<?php
declare(strict_types=1);

namespace MyModule\Tests;

use PHPUnit\Framework\TestCase;
use Propel\Runtime\Propel;
use Thelia\Core\Thelia;

abstract class TheliaIntegrationTestCase extends TestCase
{
    private static ?Thelia $kernel = null;
    protected \Propel\Runtime\Connection\ConnectionInterface $con;

    protected function setUp(): void
    {
        if (self::$kernel === null) {
            self::$kernel = new Thelia('test', true);
            self::$kernel->boot();
        }

        $this->con = Propel::getConnection('TheliaMain');
        $this->con->beginTransaction();
    }

    protected function tearDown(): void
    {
        if ($this->con->isInTransaction()) {
            $this->con->rollBack();
        }
    }
}
```

Reference: `tests/Legacy/TestCaseWithURLToolSetup.php:23` shows the `URL::$instance` singleton initialization, a key point for avoiding NPE in tests.

## 5. Patterns by layer

| Case | Pattern |
|---|---|
| Propel query | `extends TheliaIntegrationTestCase`. Boot kernel + `$con->beginTransaction()` setUp / `$con->rollBack()` tearDown. Manipulate Propel models directly. |
| Loop | Functional test: Smarty page with `{loop type="myloop"}`, GET via `WebTestCase`, assertion on `$crawler->filter()`. |
| Form | Functional test: POST via `WebTestCase` to handler route, assert redirect (success) or crawl errored form (failure). Form rarely instantiated in isolation due to heavy `init()`. |
| API endpoint | `WebTestCase` + manual JWT login: `POST /api/admin/login` get token, then `client->request('GET', '/api/admin/products', [], [], ['HTTP_AUTHORIZATION' => 'Bearer ...'])`. Assert JSON-LD. |
| Action / event listener | Pattern from `tests/Legacy/` (run only through the `test-legacy` Composer script, not by `phpunit --testsuite`): copy the bootstrap that boots Thelia + mock dispatcher. |

### JWT API endpoint test (real pattern)

```php
public function testGetProducts(): void
{
    $client = static::createClient();

    // Login
    $client->request('POST', '/api/admin/login', server: ['CONTENT_TYPE' => 'application/json'],
        content: json_encode(['username' => 'admin', 'password' => 'password'], JSON_THROW_ON_ERROR));
    $token = json_decode($client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR)['token'];

    // Authenticated request
    $client->request('GET', '/api/admin/products', server: [
        'HTTP_AUTHORIZATION' => 'Bearer '.$token,
        'HTTP_ACCEPT' => 'application/ld+json',
    ]);

    self::assertResponseIsSuccessful();
    $data = json_decode($client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);
    self::assertArrayHasKey('hydra:member', $data);
}
```

## 6. Custom fixture methods

Build them in the harness. The core provides no `FixtureFactory`.

```php
abstract class TheliaIntegrationTestCase extends TestCase
{
    // ...

    protected function createCustomer(string $email = 'test@example.com'): \Thelia\Model\Customer
    {
        $customer = new \Thelia\Model\Customer();
        $customer
            ->setEmail($email)
            ->setFirstname('Test')
            ->setLastname('User')
            ->setTitleId(1)
            ->setRef(uniqid('cust_', true))
            ->save();
        return $customer;
    }

    protected function createProduct(int $categoryId, int $taxRuleId): \Thelia\Model\Product
    {
        $product = new \Thelia\Model\Product();
        $product
            ->setRef(uniqid('prod_', true))
            ->setVisible(1)
            ->setTaxRuleId($taxRuleId)
            ->setLocale('en_US')
            ->setTitle('Test product')
            ->save();
        $product->addCategory(\Thelia\Model\CategoryQuery::create()->findPk($categoryId));
        return $product;
    }
}
```

## 6bis. Testing a `final readonly`: NEVER extend

A `final readonly` class (typical of well-structured repositories) cannot be extended. PHP 8.3 raises `Fatal error: Class Foo cannot extend final class Bar`. Anonymous stub `new class extends FinalRepository {}` = test dead on load.

**To avoid**:
```php
// FATAL PHP 8.3
$stub = new class extends ZoneRepository {
    public function findOneByCode(string $code): ?Zone { return $this->fakeZone; }
};
```

**Valid patterns**:

### Option 1: Extract an interface (recommended)

```php
interface ZoneRepositoryInterface {
    public function findOneByCode(string $code): ?Zone;
}

final readonly class ZoneRepository implements ZoneRepositoryInterface { /* ... */ }

// Test: mock the interface
$mock = $this->createMock(ZoneRepositoryInterface::class);
$mock->method('findOneByCode')->willReturn($fakeZone);
```

### Option 2: Reflection to test a contract

When you want to test without booting the kernel:

```php
public function testRepositoryIsFinalReadonly(): void
{
    $reflection = new \ReflectionClass(ZoneRepository::class);
    self::assertTrue($reflection->isFinal());
    self::assertTrue($reflection->isReadOnly());  // PHP 8.2+
}

public function testListenerIsWiredToCorrectEvent(): void
{
    $reflection = new \ReflectionClass(OrderListener::class);
    $attributes = $reflection->getAttributes(\Symfony\Component\EventDispatcher\Attribute\AsEventListener::class);
    self::assertCount(1, $attributes);
    self::assertSame(TheliaEvents::ORDER_UPDATE_STATUS, $attributes[0]->newInstance()->event);
}
```

### Option 3: Integration test with real kernel + transaction rollback

For tests that need the concrete repository, boot the kernel and use the real service (see section 4). The Propel transaction rollback in tearDown guarantees isolation.

### Anti-pattern: remove `final` or `readonly`

Defensible but **not recommended**: you lose immutability and non-inheritance guarantees. Prefer options 1-3.

## 7. Test pitfalls

1. No DB isolation -> tests permanently pollute dev DB (SIGNAL-15)
2. `tests/Legacy/` is outside phpunit.xml.dist's suites and only runs through the `test-legacy` script; add new tests to `tests/Unit` or `tests/Functional`
3. `URL::$instance` singleton not initialized -> NPE; always set up in bootstrap
4. `Translator::$instance` singleton not initialized -> RuntimeException; same rule applies
5. `WebTestCase::createClient()` does not reset the Kernel between tests; env mocks potentially contaminated
6. No `KERNEL_BROWSER` cleanup between tests; each test needs a new client
7. **Anonymous stub `extends FinalReadonlyRepository`** = fatal PHP 8.3, entire test suite non-executable. Use interface + mock OR Reflection (see section 6bis).
8. `ReflectionClass::isReadOnly()` requires PHP 8.2+, absent in 8.1. For multi-version CI: `@requires PHP 8.2` or `method_exists($reflection, 'isReadOnly')`.

## 8. Against `tests/Legacy/`

`tests/Legacy/` contains substantial tests (Propel Actions). On the 2.6 branch they run through the `test-legacy` Composer script, chained by `composer test` and by the CI workflow (`composer ci`), on a freshly reloaded demo database. They still are not part of phpunit.xml.dist, so a plain `vendor/bin/phpunit` or `--testsuite` run skips them.

If you want to reuse the Legacy bootstrap (`tests/Legacy/bootstrap.php`) to test your module, copy it to `tests/{YourModule}/bootstrap.php` and configure a dedicated phpunit suite in the project (or module) `phpunit.xml.dist`.

## 9. Ambitious module -> robust harness

For a module with serious test coverage:
1. Boot `(new Thelia('test', true))->boot()` once (singleton in parent TestCase).
2. Retrieve `$con = Propel::getConnection('TheliaMain')`, `$con->beginTransaction()` in setUp.
3. `$con->rollBack()` in tearDown.
4. Provide custom fixture methods (`createCustomer()`, `createProduct()`, etc.).
5. Configure module phpunit.xml.dist so the suite is executable via the module's `composer test`.
