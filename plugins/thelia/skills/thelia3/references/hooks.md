# Events and back-office extensions - Thelia 3

> Symfony listeners + back-office hooks (Smarty) + legacy loops. Everything is auto-tagged from `BaseHookInterface` / `LoopInterface` / `EventSubscriberInterface` - NO XML declaration required.

## 1. `TheliaEvents`

`final class TheliaEvents` with `string` constants (NOT an enum). Readable events: `'action.addArticle'`, `'cart.persist'`, etc.

Top module events:

| Constant | Value | Use |
|---|---|---|
| `CART_ADDITEM` / `AFTER_CARTADDITEM` | `'action.addArticle'` / `'cart.after.addItem'` | Cart add |
| `CART_UPDATEITEM` / `CART_DELETEITEM` | - | Update / delete cart item |
| `CART_SET_DELIVERY_MODULE` / `CART_SET_PAYMENT_MODULE` | - | Carrier / payment selection |
| `ORDER_PAY` / `ORDER_BEFORE_PAYMENT` | - | Payment |
| `ORDER_UPDATE_STATUS` / `ORDER_SEND_CONFIRMATION_EMAIL` | - | Order cycle |
| `ORDER_BEFORE_CREATE` / `ORDER_AFTER_CREATE` | - | Order creation |
| `CUSTOMER_CREATEACCOUNT` / `CUSTOMER_LOGIN` / `CUSTOMER_LOGOUT` / `CUSTOMER_UPDATEACCOUNT` | - | Customer lifecycle |
| `PRODUCT_CREATE` / `PRODUCT_UPDATE` / `CATEGORY_CREATE` | - | Catalog CRUD |
| `COUPON_CONSUME` / `NEWSLETTER_SUBSCRIBE` | - | Marketing |
| `FORM_AFTER_BUILD` / `FORM_BEFORE_BUILD` | - | Form extension |
| `MODULE_TOGGLE_ACTIVATION` | - | Module activation |
| `LOOP_EXTENDS_*` | - | Legacy loop extension |

Module events: `TheliaEvents::getModuleEvent(MODULE_PAY, 'MyPayment')` -> `'thelia.module.pay.mypayment'`.

Priority conventions:
- `192+` = pre-processing / guard
- `128` = core / business handler
- `100` = transversal / log
- `64` = post-processing

Higher = earlier.

## 2. Symfony listeners (`EventSubscriberInterface`)

Dominant pattern in core and modules: static `EventSubscriberInterface::getSubscribedEvents()`. **Not** `#[AsEventListener]` (zero usage in core/modules).

Auto-tagged via native Symfony autoconfigure. No XML declaration required.

```php
namespace MyModule\EventListener;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Thelia\Core\Event\TheliaEvents;
use Thelia\Core\Event\Customer\CustomerEvent;

class CustomerListener implements EventSubscriberInterface
{
    public function __construct(private LoggerInterface $logger) {}

    public static function getSubscribedEvents(): array
    {
        return [
            TheliaEvents::CUSTOMER_CREATEACCOUNT => ['onCustomerCreate', 128],
            TheliaEvents::FORM_AFTER_BUILD.'.thelia.customer.create' => ['extendForm', 100],
        ];
    }

    public function onCustomerCreate(CustomerEvent $event): void
    {
        $this->logger->info('Customer created', ['id' => $event->getCustomer()->getId()]);
    }

    public function extendForm($event): void { /* ... */ }
}
```

**Evolution candidate**: `#[AsEventListener]` SF 7.4 - viable but not adopted in Thelia.

```php
// Modern pattern (to adopt when context allows):
use Symfony\Component\EventDispatcher\Attribute\AsEventListener;

#[AsEventListener(event: TheliaEvents::CUSTOMER_CREATEACCOUNT, priority: 128)]
class CustomerCreatedListener
{
    public function __invoke(CustomerEvent $event): void { /* ... */ }
}
```

## 3. Back-office hooks - AUTO-DISCOVERY

`BaseHookInterface` (`Hook/BaseHookInterface.php:17`) auto-configured in `TheliaKernel::loadAutoConfigureInterfaces()` (`TheliaKernel.php:503-505`):

```php
$container->registerForAutoconfiguration(BaseHookInterface::class)
    ->addTag('hook.event_listener')
    ->setPublic(true);
```

`RegisterHookListenersPass::processHook()` (`RegisterHookListenersPass.php:71`):
1. Scans all services tagged `hook.event_listener`.
2. Extracts the module via `explode('\\', $class)[0]`.
3. Calls `getSubscribedHooks()` static on the class.
4. Inserts `ModuleHook` into the DB if absent.
5. Registers active listeners on the event_dispatcher.

**Canonical approach - NO XML config**:

```php
namespace MyModule\Hook;

use Thelia\Core\Event\Hook\HookRenderEvent;
use Thelia\Core\Hook\BaseHook;

class ProductHook extends BaseHook
{
    public static function getSubscribedHooks(): array
    {
        return [
            'product.top' => [
                'type'   => 'front',
                'method' => 'onProductTop',
            ],
            'main.navbar-secondary' => [
                ['type' => 'front', 'method' => 'onNavbar'],
            ],
        ];
    }

    public function onProductTop(HookRenderEvent $event): void
    {
        $event->add($this->render('product-top.html')); // Smarty
    }

    public function onNavbar(HookRenderEvent $event): void
    {
        $event->add($this->render('navbar-link.html', [
            'link' => $this->getRoute('mymodule.front.list'),
        ]));
    }
}
```

### Dependency injection in `BaseHook`

`BaseHook` has a constructor signature `(?EventDispatcherInterface $dispatcher = null, ?ParserResolver $parserResolver = null)` + `#[Required]` setter for `container`. To inject your own deps, **two options**:

```php
// Option 1: #[Required] setters (compatible with parent init)
final class CustomerEditHook extends BaseHook
{
    private CustomerLoyaltyRepository $loyaltyRepo;

    #[Required]
    public function setLoyaltyRepository(CustomerLoyaltyRepository $repo): void
    {
        $this->loyaltyRepo = $repo;
    }

    public static function getSubscribedHooks(): array { /* ... */ }

    public function onCustomerEdit(HookRenderEvent $event): void
    {
        $loyalty = $this->loyaltyRepo->findByCustomerId($event->getArgument('id'));
        $event->add($this->render('customer-edit-loyalty.html', ['loyalty' => $loyalty]));
    }
}

// Option 2: child constructor calling parent
final class CustomerEditHook extends BaseHook
{
    public function __construct(
        private readonly CustomerLoyaltyRepository $loyaltyRepo,
        ?EventDispatcherInterface $dispatcher = null,
        ?ParserResolver $parserResolver = null,
    ) {
        parent::__construct($dispatcher, $parserResolver);
    }
    // ...
}
```

Option 1 is safer - no risk of breaking the parent init chain. Note: `final readonly class` is not possible on a Hook (same `#[Required]` setter constraint as controllers).

Back-office hook templates = **Smarty only**:
- `render:template.html` -> Smarty render
- `js:assets/js/script.js` -> inject JS
- `css:assets/css/style.css` -> inject CSS

**`<hooks>` in `config.xml` is no longer required.** It accumulates as a duplicate alongside `getSubscribedHooks()` (both sources are merged in `processHook()` `:113-128`). Remaining edge case: hooks with purely static template and no PHP logic (still supported in XML but can be replaced by `getSubscribedHooks()` + `addTemplate()`).

`getHooks()` (a `BaseModule` method, distinct from `getSubscribedHooks()`): declares **hook positions DEFINED by the module** (extension points for other modules), inserted into DB on activation.

```php
// MyModule.php
public function getHooks(): array
{
    return [
        ['type' => 'front', 'code' => 'mymodule.special-block', 'title' => 'My Module Special Block'],
    ];
}
```

### Hook type - valid values

`getSubscribedHooks()` returns for each event an array `['type' => '...', 'method' => '...']`. Valid `type` values recognized by `RegisterHookListenersPass:293`:

| Value | Context | Equivalent |
|---|---|---|
| `'front'` | Front-office (Twig/Smarty front) | - |
| `'back'` / `'bo'` / `'backoffice'` | Back-office (Smarty BO) | **all three are equivalent** |
| `'email'` | Email templates | rare |
| `'pdf'` | PDF generation (invoices, slips) | rare |

For a BO hook, prefer `'back'` (most used in core). `'admin'` is **NOT** recognized - do not invent it.

```php
public static function getSubscribedHooks(): array
{
    return [
        'customer.edit' => ['type' => 'back', 'method' => 'onCustomerEdit'],
        'product.top'   => ['type' => 'front', 'method' => 'onProductTop'],
    ];
}
```

### Common native hooks

| Hook | Position | Use |
|---|---|---|
| `product.top` / `product.bottom` | front - product page | Before / after product info |
| `category.top` / `category.bottom` | front - category | Banner / bottom of category |
| `main.navbar-secondary` | front - navbar | Link in the navbar |
| `main.body-top` / `main.body-bottom` | front - all pages | Global banners |
| `module.configuration` | back-office | Module config page in BO |
| `main.top-menu-tools` | back-office | Link in admin tools menu |
| `customer.edit` | back-office - admin customer page | Block in customer edit page (no `customer.tab-content`) |
| `customer-edit.top` / `customer-edit.bottom` | back-office - customer page | Above / below the customer sheet |
| `order-edit.top` / `order-edit.bottom` | back-office - order page | Block in order sheet |
| `cart.top` / `cart.bottom` | front - cart page | Banners on cart page |

### How to list AVAILABLE hooks in a project

BO hooks are strings registered dynamically in the DB via `getHooks()` from modules + those placed in templates. To enumerate the extension points actually available in a given project:

```bash
# Hooks placed in BO templates (Smarty)
grep -rn '{hook name="' templates/backOffice/default/ | sed -E 's/.*hook name="([^"]+)".*/\1/' | sort -u

# Hooks placed in front templates (Twig)
grep -rn 'hook(' templates/frontOffice/flexy/ | grep -E "hook\('([^']+)'" | sed -E "s/.*hook\('([^']+)'.*/\1/" | sort -u

# Active hooks in DB
ddev exec mysql -udb -pdb thelia -e "SELECT code, type FROM hook WHERE activate=1 ORDER BY type, code;"
```

Inventing a hook code (e.g. `customer.tab-content`) that does not exist = listener silently inactive. Always verify a hook exists before attaching code to it.

## 4. Loops - AUTO-DISCOVERY (DEPRECATED)

`LoopInterface` auto-configured (`TheliaKernel.php:492-495`):
```php
$container->registerForAutoconfiguration(LoopInterface::class)
    ->setPublic(true)
    ->setShared(false)
    ->addTag('thelia.loop');
```

`LoopCompilerPass::process()` (`LoopCompilerPass.php:23-53`) derives the auto name via snake_case of the class name (`CategoryPath` -> `category_path`).

```php
namespace MyModule\Loop;

use Thelia\Core\Template\Element\BaseLoop;
use Thelia\Core\Template\Element\PropelSearchLoopInterface;
use Thelia\Core\Template\Loop\Argument\ArgumentCollection;

class ProductLoop extends BaseLoop implements PropelSearchLoopInterface
{
    protected function getArgDefinitions(): ArgumentCollection { /* ... */ }
    public function buildModelCriteria() { /* ... */ }
    public function parseResults(LoopResult $loopResult): LoopResult { /* ... */ }
}
// Accessible: {loop type="product_loop" ...}
```

`<loops>` in `config.xml` required **only if the alias differs from the auto snake_case name**:
```xml
<loop name="product" class="MyModule\Loop\ProductLoop" />  <!-- short alias -->
```

**NOTE**: `BaseLoop` is `@deprecated` in Thelia 3, the future path is API Resources (`PropelResourceInterface`). Create a new loop only if:
- Back-office compatibility (Smarty `{loop}`) is required
- No equivalent API Resource can be exposed

For all new front development: **API Resources + `resources()`** or **LiveComponent + `DataAccessService`**.

## 5. Back-office forms - AUTO-DISCOVERY

`FormInterface` (Thelia, distinct from SF) auto-configured (`TheliaKernel.php:497-500`) tag `thelia.form`. `RegisterFormPass` reads `getName()` static and populates `Thelia.parser.forms`.

`<forms>` in `config.xml` is **NEVER required** if the form extends `BaseForm` and is in an autoconfigured namespace. See `code-patterns.md`.

## 6. Traps

| Trap | Fix |
|---|---|
| `getModuleCode()` != first FQCN segment | folder = class = FQCN root |
| `RegisterHookListenersPass` DB query at compile time | DB must be available at cache warmup |
| `getSubscribedHooks()` not static | must be static (`RegisterHookListenersPass:71`) |
| Front hook in Twig (T2 reflex) | not possible - BO hooks Smarty only, front = LiveComponents |
| `EventSubscriberInterface` but service not public | autoconfigure makes it public automatically, or `setPublic(true)` |
| `BaseLoop` for new development | prefer API Resources + `resources()` |
| Duplicate `<hooks>` in config.xml + `getSubscribedHooks()` | remove `<hooks>` from XML |
| Wrong event priority | 128 = core handler, 192+ = guard, 64 = post-processing |
| `ORDER_SET_POSTAGE` deprecated | use `CART_SET_POSTAGE` |
