# Thelia 2.6: Smarty back-office

> Source: `templates/backOffice/default/`. Official theme `default`. Module override: `{module}/templates/backOffice/default/...`.

## 1. Structure

The back-office uses **Smarty exclusively** (no Twig). Templates live in `templates/backOffice/default/` of the core. To override from a module: copy the relative path into `local/modules/{Name}/templates/backOffice/default/`.

Note: T3 keeps Smarty for the back-office only (the front switches to Twig). This distinction does not affect T2.

## 2. Native BO hooks

Excerpts from `templates/backOffice/default/admin-layout.tpl` and pages:

| Hook | Location | Context / args |
|---|---|---|
| `main.head-css` | `admin-layout.tpl:49` | CSS inclusion |
| `main.before-topbar` | `admin-layout.tpl:68` | Before topbar |
| `main.topbar-top` | `admin-layout.tpl:96` | Topbar top |
| `main.inside-topbar` | `admin-layout.tpl:138` | Inside topbar |
| `main.before-content` | `admin-layout.tpl:158` | Before content |
| `main.after-content` | admin-layout | After content |
| `main.footer-js` | admin-layout | Footer JS |
| `main.before-footer`, `main.after-footer`, `main.in-footer` | admin-layout | Admin footer |
| `categories.row` / `categories.header` / `categories.top` / `categories.bottom` | `categories.html` | category listing, args: `category_id` |
| `category.create-form` / `category.delete-form` | `categories.html` | modal sub-forms |
| `customer-edit.top/bottom` / `customer.edit-js` / `customer.edit` | `customer-edit.html` | customer record, arg: `customer_id` |
| `customer.address-{create,update,delete}-form` | `customer-edit.html` | address sub-form |
| `order-edit.bill-top` / `order-edit.bill-bottom` / `order-edit.cart-top` / `order-edit.cart-bottom` | `order-edit.html` | order record, args: `order_id` |
| `order-edit.before-order-product-list` / `order-edit.after-order-product-list` / `order-edit.before-order-product-row` / `order-edit.after-order-product-row` | `order-edit.html` | product table |
| `administrators.row` / `.header` / `.top` / `.bottom` | `administrators.html` | admin listing |
| `administrator.{create,update,delete}-form` | `administrators.html` | admin forms |
| `attribute-edit.top/bottom` / `attribute.edit-js` | `attribute-edit.html` | attribute record |
| `module.configuration` | `module-configure.html` | module configuration page |

## 3. BaseAdminController helpers

`core/lib/Thelia/Controller/Admin/BaseAdminController.php` (and parent `BaseController.php`):

| Helper | Signature | Role |
|---|---|---|
| `validateForm` | `validateForm(BaseForm $form, $expectedMethod = null): \Symfony\Component\Form\Form` | CSRF + method + Symfony validators; throws `FormValidationException` otherwise. Exceptions caught in `ParserContext` (`BaseController.php:263-271`) |
| `generateRedirectFromRoute` | `generateRedirectFromRoute(string $route, array $params = [])` | Redirect to admin URL — **core `router.admin` routes only**: module `#[Route]` names raise `RouteNotFoundException`, use `generateRedirect(URL::getInstance()->absoluteUrl('/admin/...'))` in module controllers |
| `generateErrorRedirect` | `generateErrorRedirect(BaseForm $form)` | Redirect to form `error_url` with errors persisted in `ParserContext` |
| `generateSuccessRedirect` | `generateSuccessRedirect(BaseForm $form)` | Redirect to `success_url` |
| `getParserContext` | `getParserContext(): ParserContext` | Push errors / variables for Smarty |

### Admin controller pattern

```php
<?php
declare(strict_types=1);

namespace MyModule\Controller\Admin;

use Symfony\Component\Routing\Attribute\Route;
use Thelia\Controller\Admin\BaseAdminController;
use Thelia\Form\Exception\FormValidationException;
use MyModule\Form\ItemForm;

#[Route('/admin/mymodule/items')]
final class ItemController extends BaseAdminController
{
    #[Route('/save', name: 'mymodule.admin.item.save', methods: ['POST'])]
    public function save(): \Symfony\Component\HttpFoundation\Response
    {
        $form = $this->createForm(ItemForm::class);
        try {
            $validated = $this->validateForm($form);
            // do action via Repository / dispatch event
            return $this->generateSuccessRedirect($form);
        } catch (FormValidationException $e) {
            return $this->generateErrorRedirect($form);
        }
    }
}
```

## 4. BO hook pattern

Render via method:

```php
<?php
declare(strict_types=1);

namespace MyModule\Hook;

use Thelia\Core\Event\Hook\HookRenderEvent;
use Thelia\Core\Hook\BaseHook;

final class BackHook extends BaseHook
{
    public function onCategoriesRow(HookRenderEvent $event): void
    {
        $event->add($this->render('mymodule-categories-row.html', [
            'category_id' => $event->getArgument('category_id'),
        ]));
    }
}
```

Declaration in `config.xml`:

```xml
<hooks>
    <hook id="mymodule.back" class="MyModule\Hook\BackHook">
        <tag name="hook.event_listener" event="categories.row" type="back" method="onCategoriesRow"/>
    </hook>
</hooks>
```

Template `local/modules/MyModule/templates/backOffice/default/mymodule-categories-row.html`:

```smarty
<td>{intl l="My data" d="mymodule"} {$category_id}</td>
```

## 5. Module configuration page

Convention: admin route `/admin/module/{ModuleCode}` (rendered by the core `ModuleController`), with hook `module.configuration` providing the module-specific content.

Typical template: `templates/backOffice/default/module-configure.html` triggers `{hook name="module.configuration" module_code="MyModule"}`. The module renders its configuration form via this hook.

```php
public function onModuleConfiguration(HookRenderEvent $event): void
{
    if ($event->getArgument('module_code') !== 'MyModule') {
        return;
    }
    $form = $this->createForm(\MyModule\Form\ConfigForm::class);
    $event->add($this->render('mymodule-config.html', ['form' => $form->createView()]));
}
```

### The hook does NOT process submission

The hook **displays** the form. **Saving requires a dedicated route + Controller in the module.** Without them, the Save button results in a 404 or overwrites core config.

Complete pattern:

1. `Config/routing.xml`: declare `mymodule.admin.save` -> POST `/admin/module/MyModule/save` -> `MyModule\Controller\Admin\ConfigController::saveAction`
2. `Controller/Admin/ConfigController.php`: `extends BaseAdminController`, `checkAuth(MODULE, 'MyModule', UPDATE)`, `validateForm()`, injected repository
3. Template: `<form action="{token_url path='/admin/module/MyModule/save'}" method="post">` (`{token_url}` injects the CSRF token that `validateForm()` validates)

Full detail in `payment-delivery.md §3bis`. Reference: `local/modules/CustomDelivery/`.

**To avoid**:
- `<form action="{url path='/admin/module/save'}">` (generic core CRUD route, incompatible with custom form)
- `<form action="{url path='...'}">` without `{token_url}` -> CSRF not valid -> 400 rejection

## 6. BO pitfalls

1. BO templates in Smarty exclusively; no progressive migration to Twig is possible
2. Silent BO hooks if no listener; check hook name on target pages
3. `module.configuration` must guard on `module_code` because it is called for ALL modules
4. `BaseAdminController::validateForm()` throws `FormValidationException`; always catch and call `generateErrorRedirect()`
5. **BO configuration without dedicated Controller = save 404**. The `module.configuration` hook renders the form but does not process it. Always `routing.xml` + `Controller/Admin/`.
6. **`{url}` instead of `{token_url}` on POST action** = CSRF not valid -> 400 rejection. Always `{token_url}` for BO forms.
7. **Stray Smarty in templates**: `{$smarty.foreach.X.value}` outside a `{foreach}` block has no meaning. This is typical corrupted copy-paste. Use simple `{$value|escape:'html'}`.
