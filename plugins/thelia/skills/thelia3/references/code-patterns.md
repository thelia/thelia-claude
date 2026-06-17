# Forms, services and commands - Thelia 3

> Code patterns for forms (`BaseForm` + API DTO), services (`final readonly` + DI), and commands (`#[AsCommand]` + `ContainerAwareCommand`).

## 1. Forms - decision matrix

| Use case | Recommended approach | Why |
|---|---|---|
| HTML web form (cart, address, profile, admin) | `BaseForm` + `validateForm()` in controller | CSRF + success_url/error_url + Twig error ParserContext |
| Extend an existing form | listen to `TheliaEvents::FORM_AFTER_BUILD.{name}` | Add fields without subclassing |
| API endpoint (AP) | `#[ApiResource]` + DTO + `#[Assert\...]` | Auto validation, JSON-LD, no HTML form |
| Simple API action without AP | `#[MapRequestPayload]` + DTO + Validator | SF 6.3+, zero boilerplate - to adopt |
| CLI command | No form - `InputInterface::getArgument()` | Console has no CSRF/HTML |

## 2. `BaseForm` Thelia

- Does NOT inherit `AbstractType` Symfony - `implements FormInterface` Thelia.
- `buildForm()` abstract, `$this->formBuilder->add(...)`.
- Constraints via `'constraints' => [new NotBlank(), ...]` in field options (NOT `#[Assert\...]` attributes on the form - those are reserved for DTOs).
- CSRF enabled by default via `CsrfExtension` (override with `'csrf_protection' => false`).
- Hidden fields auto-added: `success_url`, `error_url`, `error_message`.
- Dispatches `FORM_BEFORE_BUILD.{name}` and `FORM_AFTER_BUILD.{name}`.
- `static getName()`: canonical name for `getForm('name')` Twig + `formService->getFormByName()`.
- `FirewallForm extends BaseForm`: adds rate-limit / brute-force protection.
- `BruteforceForm extends FirewallForm`.

```php
namespace MyModule\Form;

use Symfony\Component\Form\Extension\Core\Type\EmailType;
use Symfony\Component\Form\Extension\Core\Type\TextType;
use Symfony\Component\Validator\Constraints\{Email, NotBlank};
use Thelia\Core\Translation\Translator;
use Thelia\Form\BaseForm;

class ContactForm extends BaseForm
{
    public static function getName(): string
    {
        return 'mymodule.contact';
    }

    protected function buildForm(): void
    {
        $this->formBuilder
            ->add('email', EmailType::class, [
                'constraints' => [new NotBlank(), new Email()],
                'label' => Translator::getInstance()->trans('Email', [], 'mymodule'),
            ])
            ->add('message', TextType::class, [
                'constraints' => [new NotBlank()],
                'label' => Translator::getInstance()->trans('Message', [], 'mymodule'),
            ]);
    }
}
```

Auto-tagged `thelia.form` via `FormInterface` autoconfigure. `<forms>` in `config.xml` is NEVER required.

### Controller usage

```php
#[Route('/contact', name: 'mymodule_contact', methods: ['POST'])]
public function submit(Request $request): Response
{
    $form = $this->createForm(ContactForm::getName());
    try {
        $vform = $this->validateForm($form);
        $data = $vform->getData();
        // ... processing
        return $this->generateSuccessRedirect($form);
    } catch (FormValidationException $e) {
        $this->setupFormErrorContext('contact', $e->getMessage(), $form);
        return $this->generateErrorRedirect($form);
    }
}
```

### Extending a form without subclassing

```php
class CustomerFamilyFormListener implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [
            TheliaEvents::FORM_AFTER_BUILD.'.thelia.customer.create' => ['extend', 100],
        ];
    }

    public function extend(TheliaFormEvent $event): void
    {
        $event->getForm()->getFormBuilder()->add('family_code', ChoiceType::class, [
            'choices' => [...],
        ]);
    }
}
```

## 3. Form rendering in Flexy (Twig)

```twig
{% set form = getForm('thelia.customer.login') %}
{{ form_start(form) }}
{{ form_row(form.email) }}
{{ form_row(form.password) }}
{{ form_end(form) }}
```

LiveComponent with form:
```php
use Symfony\UX\LiveComponent\ComponentWithFormTrait;

#[AsLiveComponent(name: 'Flexy:Customer:Login')]
class Login
{
    use ComponentWithFormTrait;

    public function __construct(private FormService $formService) {}

    protected function instantiateForm(): FormInterface
    {
        return $this->formService->getFormByName(FrontForm::CUSTOMER_LOGIN)->getForm();
    }

    #[LiveAction]
    public function submit(): void
    {
        $this->submitForm();
        $data = $this->getForm()->getData();
        // ...
    }
}
```

`TwigEngine\Service\FormService::getFormByName(name)` reads `Thelia.parser.forms`, looks in `ParserContext` (error case), otherwise creates via `TheliaFormFactory`. Throws `ElementNotFoundException` if form not registered.

Flexy form theme: `templates/frontOffice/flexy/form/flexy_form_theme.html.twig` overrides `form_label`, `form_widget_simple`, `password_widget`.

### `form_end()` renders un-rendered fields

Whenever a field is rendered as raw HTML (`<select name="{{ form.X.vars.full_name }}">`, `<input ...>`) instead of `form_widget`/`form_row`, Symfony does not know it was rendered: `form_end(form)` outputs it again at the end of the form (via `form_rest`), duplicated and outside the layout (sometimes outside a modal). Two fixes:

```twig
{# 1. mark each manually-rendered widget #}
<select name="{{ form.default_category.vars.full_name }}">...</select>
{% do form.default_category.setRendered %}

{# 2. disable automatic rendering of the rest #}
{{ form_end(form, { render_rest: false }) }}
```

## 4. REST API DTO with `MapRequestPayload`

Symfony 6.3+ evolution candidate, **not yet adopted** in Thelia 3 core. Enables validation + auto-deserialization without an HTML form for simple REST endpoints.

```php
final readonly class CreateAddressDTO
{
    public function __construct(
        #[Assert\NotBlank, Assert\Length(max: 100)]
        public string $title,

        #[Assert\NotBlank]
        public string $firstname,

        #[Assert\NotBlank]
        public string $lastname,

        #[Assert\NotBlank, Assert\Length(min: 5, max: 10)]
        public string $zipcode,
    ) {}
}
```

```php
#[Route('/api/custom/address', methods: ['POST'])]
public function create(#[MapRequestPayload] CreateAddressDTO $dto): JsonResponse
{
    // $dto already validated, ready to use
    return new JsonResponse(['ok' => true]);
}
```

## 5. Services - required pattern

```php
declare(strict_types=1);

namespace MyModule\Service;

use Psr\Log\LoggerInterface;
use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Contracts\EventDispatcher\EventDispatcherInterface;

final readonly class OrderProcessor
{
    public function __construct(
        private EventDispatcherInterface $dispatcher,
        private LoggerInterface $logger,
        #[Autowire(env: 'PAYMENT_API_KEY')]
        private string $apiKey,
    ) {
    }

    public function process(Order $order): void
    {
        if (!$order->isPaid()) {
            return;
        }
        if ($order->isCancelled()) {
            return;
        }

        $this->logger->info('Order processing', ['id' => $order->getId()]);
        // ...
    }
}
```

Rules:
- `final readonly class` for services and DTOs.
- Constructor injection only - no `#[Required]` setters outside Thelia hierarchy.
- `declare(strict_types=1)` everywhere.
- Guard clauses + early return - no nested conditions.
- No abbreviations in naming.
- No redundant PHPDoc - code is doc.

### Null Object for optional extension points

When a core service depends on behavior that a module may not want to override, expose an interface + a `NullXxxService` default. The module that customizes it aliases the interface to its implementation; otherwise the core works without conditions. Avoids `if ($service !== null)` scattered throughout consumers.

```php
interface FormServiceInterface
{
    public function buildLoginForm(): FormInterface;
}

final class NullFormService implements FormServiceInterface
{
    public function buildLoginForm(): FormInterface
    {
        return /* empty / default form */;
    }
}

// core services.php
$services->alias(FormServiceInterface::class, NullFormService::class);

// module services.php that overrides
$services->set(FormServiceInterface::class, MyFormService::class);
```

The core uses this pattern for `FormServiceInterface` (Flexy customizes login/checkout forms). Other legitimate extension points: renderers, validators, accessors - any non-listener dependency that a module may not need to customize.

## 6. Controllers

Minimal, delegate to services. **NOT** `final readonly` (incompatible with `#[Required]` setters in `BaseController`).

```php
namespace MyModule\Controller\Front;

use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;
use Thelia\Controller\Front\BaseFrontController;
use Thelia\Domain\Customer\CustomerFacade;

#[Route('/account', name: 'mymodule_account_')]
final class AccountController extends BaseFrontController
{
    #[Route('/profile', name: 'profile', methods: ['GET'])]
    public function profile(CustomerFacade $customerFacade): Response
    {
        $customer = $customerFacade->getCurrentCustomer();
        if ($customer === null) {
            return $this->redirectToRoute('customer.login');
        }
        return $this->render('account/profile', ['customer' => $customer]);
    }
}
```

Admin: `extends BaseAdminController`, uses `checkAuth([], [], AccessManager::VIEW)`.

```php
final class CategoryController extends BaseAdminController
{
    #[Route('/admin/categories', name: 'admin_categories_list')]
    public function list(): Response
    {
        if ($response = $this->checkAuth(AdminResources::CATEGORY, [], AccessManager::VIEW)) {
            return $response;
        }
        return $this->render('categories');
    }
}
```

`SecurityContext::isGranted([roles], [resources], [modules], [accesses])` (underlying `checkAuth`) combines resources and accesses in **AND**: all resources AND all accesses are required (`isUserGranted` returns `false` at the first missing one). To authorize on resource A **OR** B, do not pass `[A, B]` (that means A AND B) - iterate manually and accept at the first true `isGranted`.

## 7. Commands - `#[AsCommand]`

Dominant pattern in Thelia 3:

```php
namespace MyModule\Command;

use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\{InputArgument, InputInterface};
use Symfony\Component\Console\Output\OutputInterface;
use Thelia\Command\ContainerAwareCommand;

#[AsCommand(name: 'mymodule:do-something', description: 'Short description')]
class DoSomethingCommand extends ContainerAwareCommand
{
    protected function configure(): void
    {
        $this->addArgument('id', InputArgument::REQUIRED);
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $service = $this->getContainer()->get(MyService::class);
        $service->doSomething((int) $input->getArgument('id'));

        $output->writeln('<info>Done.</info>');
        return Command::SUCCESS;
    }
}
```

`ContainerAwareCommand` (`core/lib/Thelia/Command/ContainerAwareCommand.php:38`) provides:
- `getContainer()` - full SF container
- `getDispatcher()` - event_dispatcher
- `initRequest()` - pushes a Request with Session when needed (for `resources()` / `attr()`)

`extends Command` pure (without ContainerAware): for install/DB commands that do not need the full container (`DatabaseCreateCommand`, `ModuleSchemaApplyCommand`).

Auto-tagged `thelia.command` via `TheliaKernel.php:469`. `RegisterCommandPass` makes it public + populates `command.definition`.

**SF 7.4 evolution candidate** (not adopted in Thelia):
```php
#[AsCommand('module:do-something')]
final class DoSomethingCommand
{
    public function __invoke(
        #[Argument] string $moduleCode,
        #[Option] bool $force = false,
        SymfonyStyle $io,
    ): int {
        // ...
        return Command::SUCCESS;
    }
}
```

## 8. Async (Messenger) - ABSENT

`symfony/messenger` is not present in Thelia 3. Zero `MessageBus`, zero `MessageInterface` in core. Everything is synchronous via `EventDispatcher`.

For async (email sending, stock recalculation, PDF generation):
- Either synchronous via event listener
- Or external DB/Redis queue or job scheduler

**Strong evolution candidate**: integrate `symfony/messenger` for native Symfony async.

## 9. Repository pattern - Propel queries and third-party APIs

**Mandatory project rule**: no Propel query or third-party API call should live directly in a controller, listener, command, hook, LiveComponent, or template. All interaction with a data source goes through a dedicated **Repository** class with **business-vocabulary** methods (not SQL/ORM).

### Why

- Readability: `$customerRepository->findActivePremiumCustomersFor($company)` reads clearly; `CustomerQuery::create()->filterByActive(1)->filterByTier('premium')->joinCompany()->where(...)->find()` is a technical pattern that pollutes business logic.
- Reuse: the same query often appears in 3-5 places (controller + command + listener + LiveComponent). Centralizing means one place to evolve.
- Tests: a Repository is trivially mockable/stubbable. An inline `Query::create()` is not.
- Propel / external data source coupling: if a module later switches to a third-party REST API (or cache / search index), only the Repository class changes.
- Audit / cache / monitoring: a single place to add logs, cache, retry, circuit breaker.

### Structure

One Repository per business aggregate: `CustomerRepository`, `OrderRepository`, `WishlistRepository`, `LoyaltyRepository`, `StripeApiClient` (for third-party API). Place under `MyModule\Repository\` or `MyModule\Service\Api\` (for external API clients).

```php
namespace MyModule\Repository;

use MyModule\Model\WishlistQuery;
use MyModule\Model\Wishlist;
use Thelia\Model\Customer;

final readonly class WishlistRepository
{
    public function findDefaultFor(Customer $customer): ?Wishlist
    {
        return WishlistQuery::create()
            ->filterByCustomer($customer)
            ->filterByIsDefault(true)
            ->findOne();
    }

    public function findOrCreateDefaultFor(Customer $customer): Wishlist
    {
        return $this->findDefaultFor($customer) ?? $this->createDefaultFor($customer);
    }

    public function listForCustomerOrderedByCreatedAt(Customer $customer): array
    {
        return WishlistQuery::create()
            ->filterByCustomer($customer)
            ->orderByCreatedAt()
            ->find()
            ->getData();
    }

    private function createDefaultFor(Customer $customer): Wishlist
    {
        $wishlist = (new Wishlist())
            ->setCustomer($customer)
            ->setIsDefault(true);
        $wishlist->save();
        return $wishlist;
    }
}
```

### Third-party API - same rule

For an external REST client (PSP, ESP, search engine, CRM...): create a class with business methods that ENCAPSULATE the HTTP client.

```php
namespace MyModule\Service\Api;

use Symfony\Contracts\HttpClient\HttpClientInterface;

final readonly class StripeApiClient
{
    public function __construct(
        private HttpClientInterface $stripeClient,  // SF scoped client
    ) {}

    public function chargeOrder(int $orderId, int $amountCents, string $currency, string $idempotencyKey): string
    {
        $response = $this->stripeClient->request('POST', '/v1/charges', [
            'headers' => ['Idempotency-Key' => $idempotencyKey],
            'body' => [
                'amount' => $amountCents,
                'currency' => $currency,
                'metadata[order_id]' => $orderId,
            ],
        ]);
        return $response->toArray()['id'];
    }

    public function refundCharge(string $chargeId, ?int $amountCents = null): bool
    {
        $payload = ['charge' => $chargeId];
        if ($amountCents !== null) {
            $payload['amount'] = $amountCents;
        }
        $response = $this->stripeClient->request('POST', '/v1/refunds', ['body' => $payload]);
        return $response->getStatusCode() === 200;
    }
}
```

Method naming = **business action**, not HTTP verb: `chargeOrder()` not `postCharge()`, `findOrCreateDefaultFor()` not `selectByCustomerOrInsert()`.

### Anti-patterns to avoid

| Pattern | Why it is bad |
|---|---|
| `CustomerQuery::create()` directly in controller / listener / command / template | mixes query + business logic, untestable, duplicated |
| `WishlistQuery::create()` in a business service (`WishlistManager`) | OK for a `final readonly` Manager if only one class uses the query, but delegate to a Repository once a second class uses it |
| HttpClient injected directly in listener | wrap in `XxxApiClient` with named methods |
| `$repository->find()`, `findAll()`, `findBy(...)` as public API | return by business name (`findActiveFor()`, `findOverdueAt()`) |
| Repository with >15 methods | split into multiple Repositories or a `XxxQueryService` |
| Repository that mutates via setters and `save()` more complex than CRUD | extract mutation logic into a `XxxManager` - Repository = read/simple CRUD, Manager = orchestration |

### Core Thelia models - same rule, no exception

The Repository rule applies to ALL Propel queries, including those on core models (`Customer`, `Country`, `TaxRule`, `Order`, `Product`...). Common argument: "it's just a simple lookup on a core model, it doesn't deserve a Repository". Bad argument - readability and testability always matter, and a Repository on a core model has the same benefits.

Pattern: create an `XxxCoreRepository` (or simply `XxxRepository`) in the module that encapsulates useful core reads:

```php
namespace MyModule\Repository;

use Thelia\Model\TaxRule;
use Thelia\Model\TaxRuleQuery;

final readonly class TaxRuleRepository
{
    public function findById(int $id): ?TaxRule
    {
        return TaxRuleQuery::create()->findPk($id);
    }

    public function findByCode(string $code): ?TaxRule
    {
        return TaxRuleQuery::create()->filterByCode($code)->findOne();
    }
}
```

```php
// In the consuming service
public function __construct(
    private TaxRuleRepository $taxRuleRepository,
) {}

public function buildPostage(): OrderPostage
{
    $taxRule = $this->taxRuleRepository->findById(self::getConfigValue('tax_rule_id'));
    // ...
}
```

**Hard line**: as soon as a Propel query appears outside a Repository - module or core - it is a violation.

### Repository vs Manager vs Query Service

- **Repository**: read + simple CRUD on 1 aggregate. Methods `findX()`, `addX()`, `removeX()`. No business logic.
- **Manager** (`XxxManager`): multi-aggregate orchestration, business calculations, event dispatch. Injects Repositories.
- **Query Service** (`XxxQueryService`): for complex reads/aggregates without a clear root aggregate (reports, dashboards). Returns DTOs, not entities.

Example for Wishlist:
- `WishlistRepository`: `findDefaultFor`, `listForCustomerOrderedByCreatedAt`, `addItem`, `removeItem`
- `WishlistManager`: `mergeWishlists()`, `convertToCart()`, `cleanupExpired()` - orchestrates Repository + dispatches events
- `WishlistStatsQueryService`: `getMostWishlistedProducts(int $limit, int $days)` for BO

### Testing a Repository

No internal mocks. Integration test (`IntegrationTestCase`) with Propel rollback. Covers real queries.

```php
final class WishlistRepositoryTest extends IntegrationTestCase
{
    public function testFindDefaultForReturnsExistingDefault(): void
    {
        $factory = $this->createFixtureFactory();
        $customer = $factory->customer();
        $repo = $this->getService(WishlistRepository::class);

        $wishlist = $repo->findOrCreateDefaultFor($customer);
        self::assertTrue($wishlist->getIsDefault());
        self::assertSame($wishlist->getId(), $repo->findDefaultFor($customer)?->getId());
    }
}
```

## 10. CSRF tokens (`TokenProvider`) and SSR fragments

### CSRF tokens for GET links/actions

Beyond the auto CSRF from `BaseForm` and `#[LiveAction]`, GET tokenized links/actions go through `Thelia\Tools\TokenProvider`:

- `assignToken()` returns a token **stable per session**: it reads the existing token from session in the service constructor (`assignTokenFromSession()`) and only generates a new one (stored in session) **if absent**. All links and forms on the same page share the same token - no need to generate one per link.
- `checkToken($value)` re-reads the session and compares; throws `TokenAuthenticationException('Tried to validate an invalid token')` on mismatch.
- `refreshToken()` forces regeneration (resets to `null` then `assignToken()`). **Avoid** while a page has already rendered tokenized links: their token would become invalid.

Diagnosing "Tried to validate an invalid token": if `_token` values in the DOM are consistent but the click fails, the session changed between render and click - look for a request (often AJAX) that regenerated the token.

### SSR fragments via `render(controller(...))`

When a template embeds a sub-controller (`render(controller('App\\Controller\\X::method', {param: value}))`), parameters arrive in `$request->attributes`, **not** in the query string. The controller must read via `$request->get('param')` (which looks in attributes + query + request), never `$request->query->get('param')` (query string only). The same endpoint exposed as a GET AJAX call receives its params in query -> `$request->get()` covers both cases.

## 11. Code traps

| Trap | Fix |
|---|---|
| `final readonly` on Thelia controller | remove `readonly` (`#[Required]` setters) |
| `$request->getSession()` without attached session | `SessionNotFoundException` (SF7) on HTTP error page / CLI / test without session - guard `$request?->hasSession()` and return a neutral value before `getSession()` |
| Thelia `Request` injected directly in listener/hook/service constructor | use `RequestStack` - the `expr('service("request_stack").getMainRequest()')` binding (`services.php:53`) returns `null` in CLI/warmup, injection fails. Use `$this->requestStack->getMainRequest()` at usage time. |
| `setRequest()` setter in services | constructor injection |
| `ContainerAwareInterface` outside commands | explicit injection |
| Form without `static getName()` | without `getName()`, not registered in `Thelia.parser.forms` |
| `#[Assert\...]` on `BaseForm` | use `'constraints' => [...]` in field options |
| Translation domain != lowercase module code | always lowercase (`'mymodule'`) |
| Translator singleton not initialized in CLI | inject `TranslatorInterface` |
| Untyped exception (`\Exception`) | specific exceptions |
| Redundant PHPDoc | remove - code is doc |
| Mutable services | always `final readonly class` |
