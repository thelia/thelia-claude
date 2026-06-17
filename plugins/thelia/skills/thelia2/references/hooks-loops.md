# Thelia 2.6: Hooks & Loops

> Source: `core/lib/Thelia/Core/Hook/BaseHook.php:44`, `core/lib/Thelia/Core/Template/Element/BaseLoop.php:55`, `core/lib/Thelia/Core/Event/TheliaEvents.php` (175 events).

## 1. Hooks: BaseHook

```php
abstract class BaseHook implements BaseHookInterface  // BaseHook.php:44
{
    public function __construct(
        SmartyParser $parser = null,
        AssetResolverInterface $resolver = null,
        EventDispatcherInterface $eventDispatcher = null
    ) { /* ... ModuleQuery::create()->findOneByCode($moduleCode) ... */ }

    public static function getSubscribedHooks(): array  // BaseHook.php:485, default []
    {
        return [
            'hook.event.name' => [
                ['type' => 'front', 'method' => 'onSomething'],
                ['type' => 'back',  'template' => 'render:module_configuration.html'],
            ],
        ];
    }
}
```

### Useful methods

- `$this->add(string $content)`: from handler method (alias `$event->add()`)
- `$this->render(string $template, array $vars = []): string`: Smarty render
- `$this->addCSS(string $url)` / `$this->addJS(string $url)`

## 2. Double mode XML + getSubscribedHooks (BLOCKER)

`RegisterHookListenersPass.php:71-118` **merges** both sources without dedup. If the same `(event, type)` is declared in both places, `registerHook()` is called twice -> double entry in the `module_hook` table with duplicate `class_name`. **No error displayed** (SIGNAL-02).

**Recommendation**: choose ONE mode per module.

| Mode | Pros | Cons |
|---|---|---|
| `<hook>` XML in config.xml | Admin visibility, traceability, works without pitfalls | XML verbosity |
| `getSubscribedHooks()` static | Co-located, testable, self-documenting | `autoconfigure` alone on `BaseHookInterface` is not enough (SIGNAL-06): tag placed without `event/type/method` causes `RegisterHookListenersPass:120` to iterate on empty events silently |

**Default recommendation: XML** because the autoconfigure pitfall makes `getSubscribedHooks()` fragile when declarations are forgotten.

## 3. XML config.xml pattern

```xml
<hooks>
    <hook id="mymodule.front" class="MyModule\Hook\FrontHook">
        <tag name="hook.event_listener" event="main.body-bottom" type="front" method="onMainBodyBottom"/>
        <tag name="hook.event_listener" event="account.bottom" type="front" method="onAccountBottom"/>
    </hook>
    <hook id="mymodule.back" class="MyModule\Hook\BackHook">
        <tag name="hook.event_listener" event="module.configuration" type="back" method="onModuleConfiguration"/>
    </hook>
</hooks>
```

```php
<?php
declare(strict_types=1);

namespace MyModule\Hook;

use Thelia\Core\Event\Hook\HookRenderEvent;
use Thelia\Core\Hook\BaseHook;

final class FrontHook extends BaseHook
{
    public function onMainBodyBottom(HookRenderEvent $event): void
    {
        $event->add($this->render('my-module-include.html'));
    }
}
```

## 4. HookRenderEvent vs HookRenderBlockEvent

- `HookRenderEvent` (`Core/Event/Hook/HookRenderEvent.php:22`): `add(string $content)` -> `{hook name="x"}` (function).
- `HookRenderBlockEvent` (`Core/Event/Hook/HookRenderBlockEvent.php:23`): `add(array $data)` -> Fragment (`id`/`class`/`title`/`content`...) -> `{hookblock name="x" fields="..."}` (block).

Real event name: `hook.{type}.{code}` (e.g., `hook.front.main.head-top`). Module-specific hooks: `hook.{type}.{code}.{moduleId}`.

```php
public function onAccountBottomBlock(HookRenderBlockEvent $event): void
{
    $event->add(['title' => 'My section', 'content' => $this->render('my-account-section.html')]);
    $event->add(['title' => 'Other',      'content' => $this->render('my-account-other.html')]);
}
```

```smarty
{hookblock name="account.bottom" fields="title,content"}
    <h2>{$title}</h2>{$content}
{/hookblock}
```

## 5. Native front hooks (excerpts)

| Hook | Template | Args |
|---|---|---|
| `main.head-top`, `main.head-bottom` | `layout.tpl:42, 124` | (none) |
| `main.stylesheet` | `layout.tpl:90` | (none) |
| `main.body-top`, `main.body-bottom` | `layout.tpl:127` | (none) |
| `main.header-top`, `main.header-bottom` | layout.tpl | (none) |
| `main.footer-top`, `main.footer-bottom` | layout.tpl | (none) |
| `main.content-top`, `main.content-bottom` | layout.tpl | (none) |
| `main.navbar-primary` | `layout.tpl:168` | (none) |
| `home.body`, `home.stylesheet` | `index.html` | (none) |
| `category.top/bottom/content-top/content-bottom/main-top/main-bottom` | `category.html` | `category` |
| `cart.top/bottom`, `cart.stylesheet` | `cart.html` | (none) |
| `account.bottom`, `account.javascript-initialization` | `account.html` | (none) |
| `account-order.after-information/after-products/delivery-address/invoice-address/product-extra` | `account-order.html` | `order`, `module` |

### 5b. Native back-office hooks: admin lists (extensible without patching)

All BO lists (`/admin/orders`, `/admin/products`, `/admin/categories`, `/admin/customers`...) expose the same 5 hook patterns:

| Pattern | Position | Args | Usage |
|---|---|---|---|
| `<entity>.top` | Above the table | (none) | Custom filters, alerts |
| `<entity>.table-header` | Last `<th>` before Actions | (none) | `add('<th>My column</th>')` |
| `<entity>.table-row` | Last `<td>` of each row | `<entity>_id` (e.g., `order_id`, `product_id`) | `add('<td>...</td>')` |
| `<entity>.bottom` | Below the table | (none) | Stats, exports |
| `<entity>.js` | `javascript-last-call` block | (none) | List-specific JS |

Retrieving an argument on the PHP side:
```php
public function onOrdersTableRow(HookRenderEvent $event): void
{
    $orderId = (int) $event->getArgument('order_id');  // null if absent
    $event->add('<td class="text-center">'.$this->renderer->renderForOrderId($orderId).'</td>');
}
```

On the native Smarty side (`templates/backOffice/default/orders.html`):
```smarty
{hook name="orders.table-row" location="orders_table_row" order_id={$ID} }
```

Verify DB registration:
```bash
ddev mysql db -e "SELECT mh.classname, mh.method, h.code FROM module_hook mh JOIN hook h ON h.id=mh.hook_id JOIN module m ON m.id=mh.module_id WHERE m.code='MyModule';"
```

The hook itself must exist in the DB (`hook` table) with `native=1, type=2` for BO. All native `<entity>.table-row` hooks are there (Thelia core seeds them at install).

## 6. Hook pitfalls

1. **Double mode** (XML + `getSubscribedHooks()`) -> silent double DB entry (`RegisterHookListenersPass.php:71`, SIGNAL-02)
2. **Silent auto-tag** without `event/type/method` (`Thelia.php:480` + SIGNAL-06)
3. **`{hook}` Smarty silent** if no listener; a mistyped name is invisible
4. **Pre-install instantiation crashes**: `BaseHook::__construct()` calls `ModuleQuery::create()->findOneByCode($moduleCode)` (`BaseHook.php:87-103`). Hook instantiated BEFORE the module is in the database (e.g., during `install`) crashes. **Hooks cannot be registered in preActivation.**
5. **`addTemplate()` magic**: `BaseHook::__construct()` allows `addTemplate('hook.code', 'render:tpl.html;css:assets/x.css')` without a handler method. Convenient but opaque; prefer `onMyHook(HookRenderEvent $event)` methods for maintainability.

### Verify that a listener / hook is registered

```bash
# Symfony EventDispatcher listeners (#[AsEventListener])
ddev exec "php Thelia debug:event-dispatcher 'order.manager.template.column.definition'"

# Thelia Smarty hooks (BaseHook::getSubscribedHooks), internal name prefixed by hook.<type>.
ddev exec "php Thelia debug:event-dispatcher 'hook.2.orders.table-row'"   # type 2 = backOffice

# DB side: authoritative trace of registered Smarty hooks
ddev mysql db -e "SELECT mh.classname, mh.method, h.code, h.type FROM module_hook mh JOIN hook h ON h.id=mh.hook_id JOIN module m ON m.id=mh.module_id WHERE m.code='MyModule';"
```

If a hook does not appear in `module_hook` after modifying `getSubscribedHooks()`: `php Thelia module:refresh` (re-seeds hooks).

> **Note on `native=1` hooks**: seeded by Thelia core at install (`orders.table-row`, `category.top`, etc.), not by `module:refresh`. If a native hook is missing from the DB, it is an install bug, not a bug in the consuming module. Look in `core/lib/Thelia/Install/Database/insert.sql` or re-seed via the wizard.

---

## 7. Loops: BaseLoop cycle

```
init() -> initializeArgs() -> exec() -> {
    PropelSearchLoopInterface  -> buildModelCriteria() -> searchPropel()
    OR
    ArraySearchLoopInterface   -> buildArray()         -> searchArray()
} -> parseResults(LoopResult) -> finalizeRows() (event loop.extends.parse_results.{name})
```

## 8. Interfaces (mutex)

| Interface | Method | Compatibility |
|---|---|---|
| `PropelSearchLoopInterface` (`Element/PropelSearchLoopInterface.php:18`) | `buildModelCriteria(): ModelCriteria` | Compatible with `timestampable`, `versionable` |
| `ArraySearchLoopInterface` (`Element/ArraySearchLoopInterface.php:18`) | `buildArray(): array` | Incompatible with `versionable` |
| `SearchLoopInterface` | activates `search_term` + `search_in` + `search_mode` | Combinable with one of the two above |
| `BaseI18nLoop` | parent class that auto-joins i18n tables | For i18n resources |

`checkInterface()` (`BaseLoop.php:560-617`) raises `LoopException` if the loop does not implement exactly one of the two main interfaces (Propel or Array, not both).

## 9. Auto-tag

`registerForAutoconfiguration(LoopInterface::class)` -> tag `thelia.loop` + `public=true` + `shared=false` (`Thelia.php:497-500`). `RegisterLoopPass` (`Compiler/RegisterLoopPass.php:34`) collects -> param `Thelia.parser.loops`.

**Auto name**: snake_case of the simple class name, e.g., `BetterSeoLoop` -> `better_seo_loop`. If the Smarty template uses `name="better-seo"`, declare in `config.xml` (SIGNAL-17):

```xml
<loops>
    <loop name="better-seo" class="MyModule\Loop\BetterSeoLoop"/>
</loops>
```

## 10. ArgumentCollection: 10 factories

`Argument.php`:

```php
Argument::createAnyTypeArgument($name, $default = null, $mandatory = false, $empty = true, $value = null);
Argument::createIntTypeArgument($name, $default = null, $mandatory = false, $empty = true);
Argument::createFloatTypeArgument(...);
Argument::createBooleanTypeArgument(...);
Argument::createBooleanOrBothTypeArgument(...);
Argument::createIntListTypeArgument(...);
Argument::createAnyListTypeArgument(...);
Argument::createEnumListTypeArgument($name, array $values, ...);
Argument::createAlphaNumStringTypeArgument(...);
Argument::createAlphaNumStringListTypeArgument(...);
```

## 11. Auto-pagination

If `protected $countable = true` (default), args `page`, `limit`, `offset` are auto-added (`BaseLoop.php:187-191`). When `page` is set, `searchPropel()` calls `$query->paginate($page, $limit)`. `{pageloop}` exposes the `PropelPagination` collection held in `TheliaLoop::$pagination[name]`.

## 12. Real examples

### Simple Propel loop

```php
<?php
declare(strict_types=1);

namespace MyModule\Loop;

use Propel\Runtime\ActiveQuery\Criteria;
use Thelia\Core\Template\Element\BaseLoop;
use Thelia\Core\Template\Element\LoopResult;
use Thelia\Core\Template\Element\LoopResultRow;
use Thelia\Core\Template\Element\PropelSearchLoopInterface;
use Thelia\Core\Template\Loop\Argument\Argument;
use Thelia\Core\Template\Loop\Argument\ArgumentCollection;

final class ItemLoop extends BaseLoop implements PropelSearchLoopInterface
{
    public function __construct(
        private readonly ItemRepository $repository,
    ) {}
    // No parent::__construct(). BaseLoop has no constructor; init() is enough

    protected function getArgDefinitions(): ArgumentCollection
    {
        return new ArgumentCollection(
            Argument::createIntListTypeArgument('id'),
            Argument::createBooleanTypeArgument('visible', true),
        );
    }

    public function buildModelCriteria()
    {
        $query = \MyModule\Model\ItemQuery::create();
        if (null !== $id = $this->getId())      { $query->filterById($id, Criteria::IN); }
        if (null !== $v  = $this->getVisible()) { $query->filterByVisible($v); }
        return $query;
    }

    public function parseResults(LoopResult $loopResult): LoopResult
    {
        foreach ($loopResult->getResultDataCollection() as $item) {
            $row = new LoopResultRow($item);
            $row->set('ID', $item->getId())->set('TITLE', $item->getTitle());
            $loopResult->addRow($row);
        }
        return $loopResult;
    }
}
```

Smarty: `{loop name="x" type="item" visible="1"}{$ID} {$TITLE}{/loop}`. The `type` derives to snake_case (`ItemLoop` -> `item_loop`, the `Loop` suffix stays). To use `type="item"`, declare in `config.xml`: `<loop name="item" class="MyModule\Loop\ItemLoop"/>`.

### Injecting a Repository into a Loop

`BaseLoop` has **no constructor** (`__construct` absent in `BaseLoop.php`). Initialization is done via `init()`. The subclass can therefore declare its own constructor without `parent::__construct()`:

```php
final class ItemLoop extends BaseLoop implements PropelSearchLoopInterface
{
    public function __construct(
        private readonly ItemRepository $repository,
    ) {}
}
```

A `#[Required]` setter also works (the container applies setters even in `shared=false`), but the constructor is preferable for readability and testability. **Do not confuse with `BaseHook`** which has a constructor with optional parameters.

### Array loop

```php
final class CartItemLoop extends BaseLoop implements ArraySearchLoopInterface
{
    protected function getArgDefinitions(): ArgumentCollection
    {
        return new ArgumentCollection();
    }

    public function buildArray(): array
    {
        return $this->getCurrentRequest()->getSession()->getSessionCart()->getCartItems()->getData();
    }

    public function parseResults(LoopResult $loopResult): LoopResult
    {
        foreach ($loopResult->getResultDataCollection() as $cartItem) {
            $row = new LoopResultRow($cartItem);
            $row->set('PRODUCT_ID', $cartItem->getProductId())->set('QTY', $cartItem->getQuantity());
            $loopResult->addRow($row);
        }
        return $loopResult;
    }
}
```

## 13. Native loops (excerpts, 70 total)

| Loop | Interface(s) | Main args |
|---|---|---|
| `Product` (`Loop/Product.php:45`) | `BaseI18nLoop, PropelSearchLoopInterface, SearchLoopInterface` | `id, ref, category, brand, sale, new, promo, min_price, max_price, visible, currency, order, complex` |
| `Category` | PropelSearch | `id, parent, current, not_empty, visible, with_prev_next_info, order` |
| `Cart` | ArraySearch | `order` (normal/reverse) |
| `Order` | PropelSearch | `id, ref, customer, status, exclude_status, order` |
| `Customer` | PropelSearch + Search | `id, ref, email, current, order` |
| `Image` / `Document` | PropelSearch | `id, source, source_id, width, height, resize_mode, effects` |
| `Address` | PropelSearch | `id, customer, default, order` |
| `Currency` | PropelSearch | `id, default_only, visible, exclude, order` |
| `Hook` | PropelSearch | `id, code, type, active, order` |

## 14. Loop pitfalls

1. `BaseLoop::$cacheLoopResult` and `$cacheCount` are **static globals** (`BaseLoop.php:92-94`) that survive across requests within an FPM worker. Clear on each init.
2. `versionable=true` -> requires `PropelSearchLoopInterface`
3. Argument `force_return=true` disables some visibility checks, with risk of exposing hidden data
4. Argument `no-cache` disables loop cache; necessary for session-dependent data (cart)
5. Auto snake_case name inconsistent with template (SIGNAL-17)
6. **N+1 in `parseResults`**: `XxxQuery::create()->findPk(...)` per item is forbidden. Join relations in `buildModelCriteria()`:

```php
public function buildModelCriteria()
{
    return WishlistItemQuery::create()
        ->filterByCustomerId($this->getCustomer())
        ->joinWithProduct()  // JOIN, hydrates Product in one query
        ->orderByCreatedAt(Criteria::DESC);
}

public function parseResults(LoopResult $loopResult): LoopResult
{
    foreach ($loopResult->getResultDataCollection() as $item) {
        $row = new LoopResultRow($item);
        // No additional query, already hydrated by the JOIN
        $row->set('PRODUCT_REF', $item->getProduct()->getRef());
        $loopResult->addRow($row);
    }
    return $loopResult;
}
```

---

## 15. Thelia events: 175 constants (`TheliaEvents.php`)

`core/lib/Thelia/Core/Event/TheliaEvents.php`, `final` class. Critical selection:

### Order

| Constant | Value | Event class |
|---|---|---|
| `ORDER_BEFORE_PAYMENT` | `action.order.beforePayment` | `OrderEvent` |
| `ORDER_PAY` | `action.order.pay` | `OrderEvent` |
| `ORDER_PAY_GET_TOTAL` | `action.order.pay.getTotal` | `OrderPayTotalEvent` |
| `ORDER_UPDATE_STATUS` | `action.order.updateStatus` | `OrderEvent` |
| `ORDER_SET_DELIVERY_ADDRESS/MODULE` | `action.order.setDeliveryAddress` / `action.order.setDeliveryModule` | `OrderEvent` |
| `ORDER_SET_INVOICE_ADDRESS` | `action.order.setInvoiceAddress` | `OrderEvent` |
| `ORDER_SET_PAYMENT_MODULE` | `action.order.setPaymentModule` | `OrderEvent` |
| `ORDER_SEND_CONFIRMATION_EMAIL` | `action.order.sendOrderConfirmationEmail` | `OrderEvent` |
| `ORDER_PRODUCT_BEFORE_CREATE` / `_AFTER_CREATE` | `action.orderProduct.{before/after}Create` | `OrderProductEvent` |
| `ORDER_STATUS_CREATE/UPDATE/DELETE/UPDATE_POSITION` | various | `OrderStatusEvent`, `UpdatePositionEvent` |

### Cart

| Constant | Value | Event class |
|---|---|---|
| `CART_ADDITEM` | `action.addArticle` | `CartEvent` (HTTP action) |
| `AFTER_CARTADDITEM` | `cart.after.addItem` | `CartEvent` (post-save) |
| `CART_UPDATEITEM` / `AFTER_CARTUPDATEITEM` | `action.updateArticle` / `cart.updateItem` | `CartEvent` |
| `CART_DELETEITEM` | `action.deleteArticle` | `CartEvent` |
| `CART_PERSIST` | `cart.persist` | `CartPersistEvent` |
| `CART_RESTORE_CURRENT` | `cart.restore.current` | `CartRestoreEvent` |
| `CART_DUPLICATE` / `CART_DUPLICATED` | `cart.duplicate` / `cart.duplicated` | `CartDuplicationEvent`/`CartEvent` |

#### Differential payload `CART_ADDITEM` vs `AFTER_CARTADDITEM`

The choice is asymmetric depending on the payload needed:

| Event | Event data | CartItem persistence |
|---|---|---|
| `CART_ADDITEM` | `product` (productId), `productSaleElementsId`, `quantity` set by the controller | CartItem persisted at priority 128 (core `Cart::addItem` action). Listener at priority < 128 sees the item already in DB |
| `AFTER_CARTADDITEM` | `cart` only: `getProduct()` returns `null`, `getProductSaleElementsId()` also | CartItem already persisted, but identified via `$event->getCart()->getCartItems()` (last added) |

**Recommendation**:
- To access the `productId` just added: **`CART_ADDITEM`** (priority 0 or negative to run after `Cart::addItem`).
- To react to a modified cart without needing the precise productId: `AFTER_CARTADDITEM`.

### Customer

| Constant | Value | Event class |
|---|---|---|
| `CUSTOMER_LOGIN/LOGOUT` | `action.customer_{login/logout}` | `Event` |
| `CUSTOMER_CREATEACCOUNT` | `action.createCustomer` | `CustomerCreateOrUpdateEvent` |
| `CUSTOMER_UPDATEACCOUNT` | `action.updateCustomer` | `CustomerCreateOrUpdateEvent` |
| `CUSTOMER_DELETEACCOUNT` | `action.deleteCustomer` | `CustomerEvent` |
| `LOST_PASSWORD` | `action.lostPassword` | `LostPasswordEvent` |

### Module / Hook

| Constant | Value | Event class |
|---|---|---|
| `MODULE_PAY` | `thelia.module.pay` | `OrderPaymentEvent` |
| `MODULE_PAYMENT_IS_VALID` | `thelia.module.payment.is_valid` | `IsValidPaymentEvent` |
| `MODULE_DELIVERY_GET_POSTAGE` | `thelia.module.delivery.postage` | `DeliveryPostageEvent` |
| `MODULE_DELIVERY_GET_PICKUP_LOCATIONS` | `thelia.module.delivery.pickupLocations` | `PickupLocationEvent` |
| `MODULE_INSTALL` / `MODULE_TOGGLE_ACTIVATION` | various | `Module*Event` |

### Form / Loop / Generic

| Constant | Value |
|---|---|
| `FORM_BEFORE_BUILD` | `thelia.form.before_build` |
| `FORM_AFTER_BUILD` | `thelia.form.after_build` |
| `LOOP_EXTENDS_BUILD_MODEL_CRITERIA` | `loop.extends.build_model_criteria` |
| `LOOP_EXTENDS_PARSE_RESULTS` | `loop.extends.parse_results` |
| `BOOT` | `thelia.boot` |
| `CACHE_CLEAR` | `thelia.cache.clear` |

Helpers:
- `TheliaEvents::getLoopExtendsEvent($eventName, $loopName)` -> `loop.extends.build_model_criteria.product`
- `TheliaEvents::getModuleEvent($eventName, $moduleCode)` -> `thelia.module.create.cheque`

## 16. Invented vs real constants (PITFALLS)

| Assumed constant | Exists? | Real one |
|---|---|---|
| `ORDER_BEFORE_CREATE` | **NO** | `ORDER_BEFORE_PAYMENT` |
| `ORDER_AFTER_CREATE` / `ORDER_CREATED` | **NO** | goes through `ORDER_PAY` |
| `CART_ITEM_ADD` | **NO** | `CART_ADDITEM` (HTTP action) + `AFTER_CARTADDITEM` (post-save) |
| `CART_ITEM_CREATE` | **NO** | `CART_ITEM_CREATE_BEFORE` + `CART_ADDITEM` |

Inconsistent convention (SIGNAL-22): `CART_ADDITEM` (no underscore) vs `AFTER_CARTADDITEM` (no separator) vs `CART_ITEM_CREATE_BEFORE` (with underscore).

## 17. Listeners: patterns

### XML config.xml

```xml
<services>
    <service id="mymodule.listener.order" class="MyModule\EventListener\OrderListener">
        <tag name="kernel.event_listener" event="action.order.beforePayment" method="onBeforePayment"/>
    </service>
</services>
```

### `#[AsEventListener]` SF 6.x (recommended)

```php
<?php
declare(strict_types=1);

namespace MyModule\EventListener;

use Symfony\Component\EventDispatcher\Attribute\AsEventListener;
use Thelia\Core\Event\Order\OrderEvent;
use Thelia\Core\Event\TheliaEvents;

#[AsEventListener(event: TheliaEvents::ORDER_BEFORE_PAYMENT)]
final class OrderListener
{
    public function __invoke(OrderEvent $event): void
    {
        // ...
    }
}
```

Both work in T2.6. Prefer `#[AsEventListener]` for new modules (testable, auto-discovered via autoconfigure, readable).
