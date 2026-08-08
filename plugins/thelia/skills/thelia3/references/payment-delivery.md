# Typed modules - Payment and Delivery

> Specialized modules with dedicated interfaces. They inherit `BaseModule` but add a specific business contract.

## 1. AbstractPaymentModule (payment)

(`core/lib/Thelia/Module/AbstractPaymentModule.php` implements `PaymentModuleInterface`)

```php
interface PaymentModuleInterface extends BaseModuleInterface
{
    public function pay(Order $order): ?Response;          // REQUIRED
    public function isValidPayment(): bool;                // REQUIRED
    public function manageStockOnCreation(): bool;         // true by default
}
```

Methods provided by `AbstractPaymentModule` (override only if needed):

| Method | Role |
|---|---|
| `generateGatewayFormResponse(Order, gateway_url, form_data)` | PSP redirect page (auto-POST HTML form) |
| `getPaymentSuccessPageUrl(int $order_id)` | Success URL |
| `getPaymentFailurePageUrl(int $order_id, ?string $message)` | Failure URL |
| `getMinimumAmount()` | 0 by default |
| `getMaximumAmount()` | 10000000 by default |

Constant: `PAYMENT_MODULE_TYPE = 3`. The `<type>` in `module.xml` must be `payment`.

### Full example

```php
namespace MyPayment;

use Thelia\Module\AbstractPaymentModule;
use Thelia\Model\Order;
use Symfony\Component\HttpFoundation\Response;

final class MyPayment extends AbstractPaymentModule
{
    public const DOMAIN_NAME = 'mypayment';

    public function pay(Order $order): ?Response
    {
        $gatewayUrl = 'https://psp.example.com/pay';
        $formData = [
            'order_id'  => $order->getId(),
            'amount'    => (string) $order->getTotalAmount(),
            'currency'  => $order->getCurrency()->getCode(),
            'return_url' => $this->getPaymentSuccessPageUrl($order->getId()),
            'cancel_url' => $this->getPaymentFailurePageUrl($order->getId(), 'Cancelled'),
            'signature' => $this->signPayload($order),
        ];

        return $this->generateGatewayFormResponse($order, $gatewayUrl, $formData);
    }

    public function isValidPayment(): bool
    {
        $cart = $this->getRequest()->getSession()->getSessionCart();
        if ($cart === null) {
            return false;
        }
        return $cart->getTotalAmount() >= $this->getMinimumAmount()
            && $cart->getTotalAmount() <= $this->getMaximumAmount();
    }

    public static function configureServices(ServicesConfigurator $services): void
    {
        $services->load(self::getModuleCode().'\\', __DIR__)
            ->exclude([__DIR__.'/I18n/*', __DIR__.'/Config/**/*.php', __DIR__.'/MyPayment.php'])
            ->autowire()
            ->autoconfigure();
    }

    private function signPayload(Order $order): string
    {
        return hash_hmac('sha256', (string) $order->getId(), $this->getApiKey());
    }

    private function getApiKey(): string
    {
        return self::getConfigValue('api_key', '');
    }
}
```

### Alternative `pay()` pattern - internal redirect (no external PSP)

For a module without an external gateway (bank transfer, purchase order, admin payment), `pay()` redirects to a module page that presents instructions:

```php
public function pay(Order $order): ?Response
{
    /** @var \Symfony\Component\Routing\Router $router */
    $router = $this->getContainer()->get('router');
    $url = URL::getInstance()->absoluteUrl(
        $router->generate('mymodule_instructions', ['id' => $order->getId()]),
    );
    return new Response('', Response::HTTP_FOUND, ['Location' => $url]);
}
```

**Never combine** `UrlGeneratorInterface::ABSOLUTE_URL` (parameter for `Router::generate`) AND `URL::absoluteUrl()` - use one or the other. Double absolutization duplicates scheme/host depending on the implementation.

The target route must check ownership:

```php
#[Route('/order/{id}/instructions', name: 'mymodule_instructions')]
public function show(int $id, CustomerFacade $customerFacade): Response
{
    $order = OrderQuery::create()->findPk($id) ?? throw new NotFoundHttpException();
    $customer = $customerFacade->getCurrentCustomer() ?? throw new AccessDeniedHttpException();
    if ($order->getCustomerId() !== $customer->getId()) {
        throw new AccessDeniedHttpException();
    }
    return $this->render('mymodule.instructions', ['order' => $order]);
}
```

### Custom email - mandatory `Message` seed (otherwise email silently lost)

`MailerFactory::sendEmailToCustomer($code, ...)` requires a row in the `message` table with that `$code`. Without it, `MessageQuery::getFromName()` throws an exception **silently absorbed** by `MailerFactory` (logged via `Tlog`, not visible to admin). Email lost, no feedback.

**Canonical pattern** (inspired by `vendor/thelia/modules/Cheque/`):

1. `Config/setup.sql` - idempotent INSERT of the message + i18n:

```sql
SET @var := 0;
SELECT @var := `id` FROM `message` WHERE name='mymodule_payment_confirmation';
DELETE FROM `message` WHERE `id`=@var;
SELECT @max := COALESCE(MAX(`id`), 0) FROM `message`;
SET @max := @max + 1;
INSERT INTO `message` (`id`, `name`, `secured`, `text_template_file_name`,
                      `html_template_file_name`, `created_at`, `updated_at`)
VALUES (@max, 'mymodule_payment_confirmation', 0,
        'mymodule_payment_confirmation.txt.twig',
        'mymodule_payment_confirmation.html.twig',
        NOW(), NOW());
INSERT INTO `message_i18n` (`id`, `locale`, `title`, `subject`, `text_message`, `html_message`)
VALUES (@max, 'fr_FR', 'Confirmation paiement', 'Paiement recu commande {$order_ref}', '', ''),
       (@max, 'en_US', 'Payment confirmation', 'Payment received for order {$order_ref}', '', '');
```

2. `postActivation()` - MUST insert the SQL even after the first pass (the message seed is independent of the `is_initialized` flag since it may change between versions):

```php
public function postActivation(?ConnectionInterface $con = null): void
{
    (new \Thelia\Core\Install\Database($con))->insertSql(null, [__DIR__.'/Config/setup.sql']);

    if (!self::getConfigValue('is_initialized', false)) {
        // setConfigValue defaults...
        self::setConfigValue('is_initialized', true);
    }
}
```

3. `destroy()` - clean up:

```php
public function destroy(?ConnectionInterface $con = null, $deleteModuleData = false): void
{
    if (null !== $msg = MessageQuery::create()->findOneByName('mymodule_payment_confirmation')) {
        $msg->delete($con);
    }
    parent::destroy($con, $deleteModuleData);
}
```

The `.html.twig` / `.txt.twig` templates placed in `{module}/templates/email/default/` are automatically resolved by `TwigParser` (the kernel scans `TemplateDefinition::EMAIL` in `getStandardTemplatesSubdirsIterator()`). The `message` table row must point to them via `html_template_file_name` / `text_template_file_name`.

### Callback / IPN

Webhook from PSP received on a module `#[Route('/payment/callback')]`. Pattern:

1. Verify HMAC signature.
2. Load `Order::findPk($id)`.
3. Dispatch `TheliaEvents::ORDER_UPDATE_STATUS` with `OrderEvent` + status `paid` / `cancelled` / `refunded`.
4. Respond `200 OK` to the PSP.

```php
#[Route('/payment/mypayment/callback', methods: ['POST'])]
public function callback(Request $request, EventDispatcherInterface $dispatcher): Response
{
    if (!$this->verifySignature($request)) {
        return new Response('', 403);
    }
    $order = OrderQuery::create()->findPk($request->request->getInt('order_id'));
    if ($order === null) {
        return new Response('', 404);
    }

    $event = new OrderEvent($order);
    $event->setStatus(OrderStatusQuery::getPaidStatus()->getId());
    $dispatcher->dispatch($event, TheliaEvents::ORDER_UPDATE_STATUS);

    return new Response('OK', 200);
}
```

## 2. AbstractDeliveryModule (delivery)

(`core/lib/Thelia/Module/AbstractDeliveryModule.php` implements `DeliveryModuleInterface`)

```php
interface DeliveryModuleInterface extends BaseModuleInterface
{
    public function isValidDelivery(Country $country): bool;          // REQUIRED
    public function getPostage(Country $country): OrderPostage|float; // REQUIRED
    public function handleVirtualProductDelivery(): bool;             // false by default
}
```

Methods provided:

| Method | Role |
|---|---|
| `getAreaForCountry(Country)` | Returns the `Area` configured for this country + module |
| `getDeliveryMode()` | `'delivery'` (override possible: `'pickup'`, etc.) |

Constant: `DELIVERY_MODULE_TYPE = 2`. The `<type>` in `module.xml` must be `delivery`.

### Example

```php
namespace MyDelivery;

use Thelia\Model\Country;
use Thelia\Model\OrderPostage;
use Thelia\Module\AbstractDeliveryModule;

final class MyDelivery extends AbstractDeliveryModule
{
    public const DOMAIN_NAME = 'mydelivery';

    public function isValidDelivery(Country $country): bool
    {
        return $this->getAreaForCountry($country) !== null;
    }

    public function getPostage(Country $country): OrderPostage|float
    {
        $area = $this->getAreaForCountry($country);
        if ($area === null) {
            return 0.0;
        }
        $postage = new OrderPostage();
        $postage->setAmount($this->computeAmount($country))
                ->setAmountTax(0.0)
                ->setTaxRuleTitle('-');
        return $postage;
    }

    private function computeAmount(Country $country): float
    {
        // Pricing logic: weight/zones/flat rate...
        return 6.99;
    }
}
```

### Variant with state - `AbstractDeliveryModuleWithState`

(`core/lib/Thelia/Module/AbstractDeliveryModuleWithState.php`)

Adds state/region management for the US. Override `isValidDelivery(Country $country, ?State $state = null)` and `getPostage(Country $country, ?State $state = null)`.

**TaxEngine helper ONLY in `WithState`**: the `buildOrderPostage(float $price, Country, ?State, int $taxRuleId): OrderPostage` method that calculates VAT via `Calculator::loadTaxRuleWithoutProduct() + getTaxedPrice() + getTaxAmountFromUntaxedPrice()` exists ONLY in `AbstractDeliveryModuleWithState` (`:60-83`). **Not in plain `AbstractDeliveryModule`.**

Three options if you need the TaxEngine helper:
1. Extend `AbstractDeliveryModuleWithState` even without state logic (`?State` is nullable)
2. Re-implement the `Calculator::loadTaxRuleWithoutProduct()` -> `getTaxedPrice()` -> `getTaxAmountFromUntaxedPrice()` pattern inline (~10 lines, see `AbstractDeliveryModuleWithState.php:60-83`)
3. If no differential VAT (zero cart VAT, or module VAT = 0): simple `OrderPostage` with `setAmount($x)->setAmountTax(0.0)->setTaxRuleTitle('-')`

Use `WithState` if pricing varies at the state level (e.g. US, CA, AU) OR if you want the VAT helper.

### `Country::getAreaId()` deprecated

`core/lib/Thelia/Model/Country.php:64-66` - "a country may belong to several Areas". To map a country to a module pricing zone, **do not reuse `Country::getAreaId()`** or the Thelia `Area` (coupled to global merchant config). Create a custom mapping table in the module (`mymodule_zone_country` with FK `country_id` + `zone_id`).

`getAreaForCountry(Country)` (inherited from `AbstractDeliveryModule`) remains usable but traverses `Area` - same limitation. Reserve it for modules that trust core Areas.

## 3. Admin configuration page (back-office)

Common pattern for both types: configuration page accessible from BO via the `module.configuration` hook or a dedicated admin route.

```php
#[Route('/admin/module/mypayment', name: 'mypayment_admin_')]
final class ConfigController extends BaseAdminController
{
    #[Route('', name: 'config', methods: ['GET', 'POST'])]
    public function config(Request $request): Response
    {
        if ($response = $this->checkAuth(AdminResources::MODULE, ['MyPayment'], AccessManager::UPDATE)) {
            return $response;
        }

        if ($request->isMethod('POST')) {
            MyPayment::setConfigValue('api_key', $request->request->get('api_key', ''));
            MyPayment::setConfigValue('mode', $request->request->get('mode', 'sandbox'));
            $this->addFlashMessage('success', 'Configuration saved');
            return $this->redirectToRoute('mypayment_admin_config');
        }

        return $this->render('mypayment/config', [
            'api_key' => MyPayment::getConfigValue('api_key', ''),
            'mode'    => MyPayment::getConfigValue('mode', 'sandbox'),
        ]);
    }
}
```

Back-office template (Twig): `templates/backOffice/default-twig/mypayment/config.html.twig`.

## 4. Typed module traps

| Trap | Fix |
|---|---|
| `<type>` in `module.xml` != abstract type | align `payment` / `delivery` |
| `pay()` returns `null` without Response | must return an HTTP `Response` (redirect, HTML form...) |
| `pay()` URL doubly absolutized | ONE absolutization only: `URL::absoluteUrl()` OR `UrlGeneratorInterface::ABSOLUTE_URL`, not both |
| `isValidPayment()` reads Cart from Request in CLI | guard `$this->getRequest()` + try/catch + fallback `false` |
| Webhook callback not signed | always sign + verify (HMAC) |
| Custom email sent but no mail received | seed the `message` row via `Config/setup.sql` + `postActivation()` (see above). MailerFactory silently absorbs the error. |
| `MessageQuery::getFromName()` throws exception | message not seeded -> seed required in `postActivation()` |
| `destroy()` does not clean up the message | always implement `destroy()` with `MessageQuery::findOneByName()->delete()` |
| `getPostage()` returns `0.0` instead of error | prefer `false` via `isValidDelivery()` - do not expose the module if invalid |
| `OrderPostage::setAmountTax(0.0)` but real VAT | calculate VAT via `TaxEngine` |
| `manageStockOnCreation()` confused with status | `manageStockOnCreation()` = decrements stock on order creation, distinct from paid status |
| Modules ordered arbitrarily | `Module::getPosition()` configured in BO |
| `TheliaEvents::ORDER_BEFORE_CREATE` not found | **does NOT exist** - use `ORDER_BEFORE_PAYMENT` (line 265 of TheliaEvents) to intercept the order cycle, OR `ORDER_PRODUCT_BEFORE_CREATE` (line 275) for OrderProduct |
| `buildOrderPostage()` not found in `AbstractDeliveryModule` | helper ONLY in `AbstractDeliveryModuleWithState` (see WithState variant section) |
| `Country::getAreaId()` used in a delivery module | deprecated - prefer custom mapping table |
| `Request` injected in listener/hook constructor | `getMainRequest()` binding = `null` in CLI/warmup - inject `RequestStack` and call `getMainRequest()` at usage time |
| `Tests/` not excluded in `configureServices()` | autoloader scans everything - `->exclude([__DIR__.'/Tests/*', __DIR__.'/I18n/*', __DIR__.'/Config/**/*.php', __DIR__.'/MyModule.php'])` |

### Order cycle events - real names (`core/lib/Thelia/Core/Event/TheliaEvents.php:256-276`)

| Constant | Value | When triggered |
|---|---|---|
| `ORDER_BEFORE_PAYMENT` | `'action.order.beforePayment'` | Before `pay()` of the payment module (interception possible - exception blocks) |
| `ORDER_PAY` | `'action.order.pay'` | Call to `pay()` of the payment module |
| `ORDER_AFTER_PAYMENT` | `'action.order.afterPayment'` | After `pay()` returns |
| `ORDER_UPDATE_STATUS` | `'action.order.update_status'` | Status change (paid, processing, sent, cancel) |
| `ORDER_PRODUCT_BEFORE_CREATE` | `'action.order_product.beforeCreate'` | Before OrderProduct insert |
| `ORDER_PRODUCT_AFTER_CREATE` | `'action.order_product.afterCreate'` | After OrderProduct insert |
| `ORDER_AFTER_CREATE` | `'action.order.afterCreate'` | After `Order::save()` |
| `ORDER_SET_DELIVERY_MODULE` | - | Carrier selection in cart |
| `ORDER_SET_PAYMENT_MODULE` | - | Payment selection in cart |

**ORDER_BEFORE_CREATE does NOT exist**. To intercept before creation: use `ORDER_BEFORE_PAYMENT` (the last point BEFORE persistence).
