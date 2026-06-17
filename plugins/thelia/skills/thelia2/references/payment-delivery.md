# Thelia 2.6: Payment and delivery modules

> Source: `core/lib/Thelia/Module/AbstractPaymentModule.php`, `core/lib/Thelia/Module/AbstractDeliveryModule.php`, events `MODULE_PAY`, `MODULE_PAYMENT_IS_VALID`, `MODULE_DELIVERY_GET_POSTAGE`, `ORDER_UPDATE_STATUS`.

## 1. Payment module: AbstractPaymentModule

```php
<?php
declare(strict_types=1);

namespace MyPayment;

use Symfony\Component\HttpFoundation\Response;
use Thelia\Model\Order;
use Thelia\Module\AbstractPaymentModule;

final class MyPayment extends AbstractPaymentModule
{
    public function pay(Order $order): Response
    {
        // Redirect to PSP / generate token / call payment gateway API
        return $this->redirectToProvider($order);
    }

    public function isValidPayment(): bool
    {
        // Check conditions: config present, minimum amount, supported currency, etc.
        $minAmount = (float) self::getConfigValue('min_amount', 0);
        $cart = $this->getRequest()->getSession()->getSessionCart($this->getDispatcher());
        return $cart->getTotalAmount() >= $minAmount;
    }

    public function manageStockOnCreation(): bool
    {
        // false = stock decremented only when payment is confirmed
        return false;
    }

    private function redirectToProvider(Order $order): Response
    {
        // provider logic (Stripe, PayPal, Cheque, etc.)
        return new \Symfony\Component\HttpFoundation\RedirectResponse(/* ... */);
    }
}
```

### `module.xml` (type)

```xml
<type>payment</type>
```

### BO hook `module.configuration`

```xml
<hooks>
    <hook id="mypayment.configuration" class="MyPayment\Hook\ConfigurationHook">
        <tag name="hook.event_listener" event="module.configuration" type="back" method="onConfiguration"/>
    </hook>
</hooks>
```

```php
public function onConfiguration(HookRenderEvent $event): void
{
    if ($event->getArgument('module_code') !== 'MyPayment') {
        return;
    }
    $event->add($this->render('mypayment-config.html', ['form' => /* ... */]));
}
```

### Payment confirmation listener

When the PSP responds (callback / webhook), a module controller must dispatch `ORDER_UPDATE_STATUS` with the `paid` status. Simplified pattern:

```php
public function onPaymentSuccess(string $transactionRef): void
{
    $order = OrderQuery::create()->findOneByTransactionRef($transactionRef);
    $order->setTransactionRef($transactionRef);
    $event = new \Thelia\Core\Event\Order\OrderEvent($order);
    $event->setStatus(OrderStatusQuery::create()->findOneByCode('paid')->getId());
    $this->getDispatcher()->dispatch($event, \Thelia\Core\Event\TheliaEvents::ORDER_UPDATE_STATUS);
}
```

## 2. Delivery module: AbstractDeliveryModule

```php
<?php
declare(strict_types=1);

namespace MyDelivery;

use Thelia\Model\Country;
use Thelia\Model\State;
use Thelia\Module\AbstractDeliveryModule;
use Thelia\Module\Exception\DeliveryException;

final class MyDelivery extends AbstractDeliveryModule
{
    public function isValidDelivery(Country $country): bool
    {
        // True if delivery is available in this country
        return in_array($country->getIsoalpha2(), ['FR', 'BE', 'CH'], true);
    }

    public function getPostage(Country $country): float
    {
        $cart = $this->getRequest()->getSession()->getSessionCart($this->getDispatcher());
        $weight = (float) $cart->getWeight();

        return match (true) {
            $weight <= 1.0  => 5.90,
            $weight <= 5.0  => 9.90,
            default         => 14.90,
        };
    }
}
```

### `module.xml` (type)

```xml
<type>delivery</type>
```

### Variant: AbstractDeliveryModuleWithState

For modules depending on province/state (US, CA, AU): override a signature that takes `Country` + `State`. T2.6 standard stays on `Country` alone; check the exact signature in the core for the adopted module type.

### Zones / rates configuration

Typical convention: `mydelivery_slice` table (weight -> price), seeded in `postActivation()` via SQL. Admin page = `module.configuration` hook rendering a CRUD form over the slices.

### `ORDER_UPDATE_STATUS` listener

To trigger label/waybill generation when status moves to `processing`:

```php
#[AsEventListener(event: TheliaEvents::ORDER_UPDATE_STATUS)]
final class OrderStatusListener
{
    public function __invoke(OrderEvent $event): void
    {
        $order = $event->getOrder();
        if ($order->getDeliveryModuleId() !== \MyDelivery\MyDelivery::getModuleId()) {
            return;
        }
        if ($order->getStatusCode() === 'processing') {
            // generate waybill, call carrier API, etc.
        }
    }
}
```

## 3. Required Message seed for notification emails

If the module sends a notification email (payment confirmed, shipping, etc.), it must seed a `Thelia\Model\Message` row in `postActivation()` with a unique `name`. Otherwise `MailerFactory::sendEmailMessage()` returns silently without sending.

```php
public function postActivation(ConnectionInterface $con = null): void
{
    if (!self::getConfigValue('is_initialized')) {
        $message = (new \Thelia\Model\Message())
            ->setName('mypayment_confirmation')
            ->setHtmlLayoutFileName('')
            ->setHtmlTemplateFileName('mypayment_confirmation.html')
            ->setTextLayoutFileName('')
            ->setTextTemplateFileName('mypayment_confirmation.txt')
            ->setLocale('en_US')
            ->setTitle('Payment confirmation')
            ->setSubject('Payment confirmation: order #ORDER_REF')
            ->setLocale('fr_FR')
            ->setTitle('Confirmation de paiement')
            ->setSubject('Confirmation de paiement: commande #ORDER_REF')
            ->save();
        self::setConfigValue('is_initialized', '1');
    }
}
```

Templates: `local/modules/MyPayment/templates/email/default/mypayment_confirmation.html` (Smarty).

## 3bis. BO module configuration: required pattern

The `module.configuration` hook renders the BO form **but does not process submission**. The core route `/admin/module/save` is a generic CRUD (`ModuleController::processUpdateAction`) **incompatible** with a custom `BaseForm`.

**Without dedicated route + Controller, the Save button results in a 404 or overwrites core config without validating the form.** This is a frequent blocker.

### 1. Declare the route: `Config/routing.xml`

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<routes xmlns="http://symfony.com/schema/routing"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://symfony.com/schema/routing http://symfony.com/schema/routing/routing-1.0.xsd">
    <route id="mymodule.admin.save" path="/admin/module/MyModule/save" methods="POST">
        <default key="_controller">MyModule\Controller\Admin\ConfigController::saveAction</default>
    </route>
</routes>
```

### 2. Dedicated controller: `Controller/Admin/ConfigController.php`

```php
<?php
declare(strict_types=1);

namespace MyModule\Controller\Admin;

use MyModule\Form\ConfigForm;
use MyModule\Repository\ConfigRepository;
use Symfony\Component\HttpFoundation\RedirectResponse;
use Thelia\Controller\Admin\BaseAdminController;
use Thelia\Core\Security\AccessManager;
use Thelia\Core\Security\Resource\AdminResources;

final class ConfigController extends BaseAdminController
{
    public function saveAction(ConfigRepository $repository): RedirectResponse
    {
        if (null !== $response = $this->checkAuth(AdminResources::MODULE, 'MyModule', AccessManager::UPDATE)) {
            return $response;
        }

        $form = $this->createForm(ConfigForm::class);
        try {
            $data = $this->validateForm($form)->getData();
            $repository->save($data);
            return $this->generateSuccessRedirect($form);
        } catch (\Exception $e) {
            $this->setupFormErrorContext('MyModule configuration', $e->getMessage(), $form);
            return $this->generateErrorRedirect($form);
        }
    }
}
```

### 3. BO template: CSRF via `{token_url}`

```smarty
<form action="{token_url path='/admin/module/MyModule/save'}" method="post">
    {form_hidden_fields form=$form}
    {* fields *}
    <button type="submit">{intl l="Save"}</button>
</form>
```

**`{token_url}` (not `{url}`)**: adds the CSRF token to the URL. `BaseAdminController::validateForm()` automatically validates this token. Without `{token_url}`, the submission is rejected with a CSRF error.

Reference: `local/modules/CustomDelivery/` is the canonical example (routing.xml + BackController + module-configure.html).

## 4. Payment / delivery pitfalls

1. `isValidPayment()` must be fast, with no heavy network calls
2. `pay()` returns a `Response` (Redirect or HTML content), not JSON
3. `manageStockOnCreation()` default depends on the parent class; override for asynchronous payment (card, bank transfer)
4. PSP webhooks (Stripe, PayPal) must be protected by signature/secret; never trust the body alone
5. `ORDER_UPDATE_STATUS` listener fires for ALL modules; always guard on `getDeliveryModuleId()` or `getPaymentModuleId()`
6. Forgotten `Message` seed -> emails silently lost
7. `getPostage()` must return a `float`, not a `Money`/`Decimal` (Propel expects a simple numeric)
8. BO hook `module.configuration` is called for ALL modules; always guard on `module_code`
9. **`$order->setPostage()` without `$order->save()` = lost modification**. When `ORDER_BEFORE_PAYMENT` is dispatched (`Order.php:410`), the order has already been saved (`Order.php:241`). The core does not re-save. A listener that recalculates postage MUST call `$order->save()` explicitly, otherwise the value stays as the session value. **If the listener updates `postage_tax` / `postage_tax_rule_title`, reset them to 0 / null to avoid accounting discrepancies.**
10. **BO configuration without dedicated Controller** = save 404 (see section 3bis). Always `routing.xml` + `Controller/Admin/`.
11. **`$tax = 0` as argument in `getTotalAmount(&$tax = 0, ...)`**: misleading form (assignment in argument, by-ref param). Use a named variable:
```php
$taxAmount = 0;
$totalEur = (float) $order->getTotalAmount($taxAmount, true, true);
```
12. **`addPoints()` / `decrementBalance()` without guard**: a negative delta can bring a balance below zero with no application constraint. Always `if ($newBalance < 0) throw new \DomainException(...)`.

## 5. Structure recap

### Payment module structure

```
local/modules/MyPayment/
+- MyPayment.php                       # extends AbstractPaymentModule
+- Config/module.xml                   # <type>payment</type>
+- Config/config.xml                   # <hook> module.configuration
+- Config/thelia.sql                   # CREATE TABLE mypayment_*, INSERT message
+- Form/ConfigurationForm.php
+- Hook/ConfigurationHook.php
+- Controller/Front/CallbackController.php
+- EventListener/PaymentSuccessListener.php
+- templates/email/default/mypayment_confirmation.html
+- templates/backOffice/default/mypayment-config.html
```

### Delivery module structure

```
local/modules/MyDelivery/
+- MyDelivery.php                      # extends AbstractDeliveryModule
+- Config/module.xml                   # <type>delivery</type>
+- Config/config.xml
+- Config/schema.xml                   # mydelivery_slice
+- Config/thelia.sql                   # initial slice seeds
+- Form/SliceForm.php
+- Hook/ConfigurationHook.php
+- Controller/Admin/SliceController.php
+- EventListener/OrderStatusListener.php
+- templates/backOffice/default/mydelivery-slices.html
```
