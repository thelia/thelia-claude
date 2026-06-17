# Thelia 2 - Hook system

## Quick Reference

| Task | Approach |
|-------|----------|
| Inject simple HTML | Hook function + `HookRenderEvent` |
| Inject structured block | Hook block + `HookRenderBlockEvent` |
| Declare a hook | `config.xml` with `<hooks>` |
| Inject CSS/JS without PHP | `templates="css:..."` or `templates="js:..."` |
| Create a custom hook | `getHooks()` in the main module class |
| Debug hooks | `?SHOW_HOOK=1` in URL (debug mode) |
| Clean module hooks | `php Thelia hook:clean MyModule` |

## Hook types

### Hook Function (simple)

Use a hook function to concatenate content from all listeners. Used to inject HTML/CSS/JS.

```smarty
{* In the Smarty template *}
{hook name="main.head-bottom"}
```

### Hook Block (structured)

Use a hook block to iterate over fragments with structured data. Used for lists, menus, footer blocks.

```smarty
{* In the Smarty template *}
{hookblock name="main.footer-body" fields="id,class,title,content"}
    {forhook rel="main.footer-body"}
        <div id="{$id}" class="{$class}">
            <h3>{$title}</h3>
            <div>{$content}</div>
        </div>
    {/forhook}
{/hookblock}
```

## Declaration in config.xml

### Hook with PHP class

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<config xmlns="http://thelia.net/schema/dic/config"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://thelia.net/schema/dic/config http://thelia.net/schema/dic/config/thelia-1.0.xsd">

    <hooks>
        <hook id="mymodule.hook.front" class="MyModule\Hook\FrontHook">
            <tag name="hook.event_listener" event="main.head-bottom" type="front" method="onMainHeadBottom" />
            <tag name="hook.event_listener" event="main.footer-body" type="front" method="onMainFooterBody" />
        </hook>
    </hooks>
</config>
```

### Hook without class (direct injection)

```xml
<hooks>
    <!-- CSS -->
    <hook id="mymodule.hook.css">
        <tag name="hook.event_listener" event="main.stylesheet" type="front" templates="css:assets/css/style.css" />
    </hook>

    <!-- JS -->
    <hook id="mymodule.hook.js">
        <tag name="hook.event_listener" event="main.after-javascript-include" type="front" templates="js:assets/js/script.js" />
    </hook>

    <!-- Template -->
    <hook id="mymodule.hook.template">
        <tag name="hook.event_listener" event="product.bottom" type="front" templates="render:product-extra.html" />
    </hook>
</hooks>
```

### Tag attributes

| Attribute | Description | Values |
|----------|-------------|---------|
| `event` | Hook name | `main.head-bottom`, `product.top`, etc. |
| `type` | Context | `front`, `back`, `email`, `pdf` |
| `method` | PHP method | `onMainHeadBottom` (if class) |
| `templates` | Direct injection | `render:`, `css:`, `js:`, `dump:` |
| `active` | Initial state | `1` (default) or `0` |

## Hook Listener implementation

### File structure

```
MyModule/
├── Config/
│   └── config.xml
├── Hook/
│   ├── FrontHook.php
│   └── BackHook.php
└── templates/
    └── frontOffice/
        └── default/
            └── my-template.html
```

### Hook Function (HookRenderEvent)

```php
<?php

namespace MyModule\Hook;

use Thelia\Core\Event\Hook\HookRenderEvent;
use Thelia\Core\Hook\BaseHook;
use MyModule\MyModule;

class FrontHook extends BaseHook
{
    public function onMainHeadBottom(HookRenderEvent $event): void
    {
        // Direct injection
        $trackingCode = MyModule::getConfigValue('tracking_code', '');
        if ('' !== $trackingCode) {
            $event->add($trackingCode);
        }
    }

    public function onProductBottom(HookRenderEvent $event): void
    {
        // With template
        $productId = $event->getArgument('product');

        $content = $this->render('product-reviews.html', [
            'product_id' => $productId,
        ]);

        $event->add($content);
    }
}
```

### Hook Block (HookRenderBlockEvent)

```php
<?php

namespace MyModule\Hook;

use Thelia\Core\Event\Hook\HookRenderBlockEvent;
use Thelia\Core\Hook\BaseHook;
use MyModule\MyModule;

class FrontHook extends BaseHook
{
    public function onMainFooterBody(HookRenderBlockEvent $event): void
    {
        $content = trim($this->render('footer-block.html'));

        if ('' === $content) {
            return;
        }

        $event->add([
            'id' => 'mymodule-footer',
            'class' => 'mymodule-block',
            'title' => $this->trans('My Title', [], MyModule::DOMAIN_NAME),
            'content' => $content,
        ]);
    }
}
```

### Available methods in BaseHook

```php
// Template render
$this->render('template.html', ['var' => $value]);

// Raw file
$this->dump('file.txt');

// CSS/JS
$this->addCSS('assets/css/style.css');
$this->addJS('assets/js/script.js');

// Translation
$this->trans('key', ['%param%' => $value], 'mymodule.domain');

// Context
$this->getRequest();
$this->getSession();
$this->getCustomer();
$this->getCart();
$this->getOrder();
$this->getLang();
$this->getCurrency();
```

## Method naming convention

Convert the hook name to PascalCase and add the `on` prefix:

| Hook | Method |
|------|---------|
| `main.head-bottom` | `onMainHeadBottom()` |
| `product.details-top` | `onProductDetailsTop()` |
| `order-delivery.form-bottom` | `onOrderDeliveryFormBottom()` |

## Calling from Smarty

### Basic hook function

```smarty
{hook name="main.head-bottom"}
```

### With parameters

```smarty
{hook name="product.bottom" product=$ID}
{hook name="order-delivery.extra" order=$order_id module=$delivery_module_id}
```

### With HTML wrapper

```smarty
{hook name="main.footer-bottom" before="<div class='custom'>" after="</div>"}
```

### Hook block with iteration

```smarty
{hookblock name="product.additional" product=$product_id fields="id,class,title,content"}
    {forhook rel="product.additional"}
        <section id="{$id}" class="panel {$class}">
            <h3 class="panel-title">{$title}</h3>
            <div class="panel-body">{$content}</div>
        </section>
    {/forhook}
{/hookblock}
```

### Conditional

```smarty
{ifhook rel="account.additional"}
    <div class="additional-content">
        {hook name="account.additional"}
    </div>
{/ifhook}

{elsehook rel="account.additional"}
    {* Default display if no module *}
{/elsehook}
```

### Hook specific to a module

```smarty
{hook name="order-delivery.extra" module=$delivery_module_id}
```

## Create a custom hook

Implement `getHooks()` in the main module class:

```php
<?php

namespace MyModule;

use Thelia\Module\BaseModule;
use Thelia\Core\Template\TemplateDefinition;

class MyModule extends BaseModule
{
    public function getHooks(): array
    {
        return [
            [
                'type' => TemplateDefinition::FRONT_OFFICE,
                'code' => 'mymodule.custom-area',
                'title' => [
                    'en_US' => 'Custom area',
                    'fr_FR' => 'Zone personnalisee',
                ],
                'description' => [
                    'en_US' => 'Injection area for third-party modules',
                    'fr_FR' => 'Zone d\'injection pour les modules tiers',
                ],
                'active' => true,
                'block' => false,  // true for hook block
            ],
        ];
    }
}
```

Call the custom hook in the Smarty template:

```smarty
{hook name="mymodule.custom-area"}
```

## Common native hooks

### Frontend

| Hook | Usage |
|------|-------|
| `main.head-top` | Start of `<head>` |
| `main.head-bottom` | End of `<head>` (tracking, meta) |
| `main.stylesheet` | CSS injection |
| `main.body-top` | Start of `<body>` |
| `main.header-top/bottom` | Page header |
| `main.navbar-primary/secondary` | Navigation |
| `main.content-top/bottom` | Main content |
| `main.footer-top/body/bottom` | Footer |
| `main.after-javascript-include` | After JS |
| `main.javascript-initialization` | JS init |
| `product.top/bottom` | Product page |
| `product.gallery` | Product gallery |
| `product.details-top/bottom` | Product details |
| `product.additional` | Additional tabs (block) |
| `category.top/bottom` | Category page |
| `cart.top/bottom` | Cart |
| `order-delivery.top/bottom` | Delivery |
| `order-invoice.top/bottom` | Payment |
| `account.top/bottom/additional` | Customer account |

### Backend

| Hook | Usage |
|------|-------|
| `module.configuration` | Module config |
| `module.config-js` | Module config JS |
| `home.top/block/bottom` | Dashboard |
| `product.tab-content` | Product tabs |
| `product.edit-js` | Product edit JS |
| `orders.table-header/row` | Orders list |
| `main.top-menu-tools` | Tools menu |

## CLI commands

```bash
# Clean and recreate hooks for a module
php Thelia hook:clean MyModule

# Without confirmation
php Thelia hook:clean MyModule -y

# All modules
php Thelia hook:clean
```

## Common pitfalls

### Missing type in config.xml

```xml
<!-- WRONG: no type -->
<tag name="hook.event_listener" event="main.head-bottom" method="onMainHeadBottom" />
```

```xml
<!-- CORRECT: always specify type -->
<tag name="hook.event_listener" event="main.head-bottom" type="front" method="onMainHeadBottom" />
```

### Wrong event type for HookRenderBlockEvent

```php
// WRONG: uses HookRenderEvent for a block hook
public function onMainFooterBody(HookRenderEvent $event): void
```

```php
// CORRECT: HookRenderBlockEvent for block hooks
public function onMainFooterBody(HookRenderBlockEvent $event): void
```

### Returning instead of adding

```php
// WRONG
public function onMainHeadBottom(HookRenderEvent $event): string
{
    return '<script>...</script>';
}
```

```php
// CORRECT
public function onMainHeadBottom(HookRenderEvent $event): void
{
    $event->add('<script>...</script>');
}
```

### Template without content check

```php
// WRONG
public function onMainFooterBody(HookRenderBlockEvent $event): void
{
    $event->add([
        'content' => $this->render('footer.html'),  // May be empty
    ]);
}
```

```php
// CORRECT: check before adding
public function onMainFooterBody(HookRenderBlockEvent $event): void
{
    $content = trim($this->render('footer.html'));
    if ('' === $content) {
        return;
    }
    $event->add(['content' => $content]);
}
```

## Add admin menu entry

```php
<?php
namespace MyModule\Hook;

use Thelia\Core\Event\Hook\HookRenderBlockEvent;
use Thelia\Core\Hook\BaseHook;
use Thelia\Tools\URL;

class BackHook extends BaseHook
{
    public function onToolsMenu(HookRenderBlockEvent $event): void
    {
        $event->add([
            'id' => 'tools_menu_mymodule',
            'class' => '',
            'url' => URL::getInstance()->absoluteUrl('/admin/module/MyModule'),
            'title' => $this->trans('My Module Settings', [], MyModule::DOMAIN_NAME),
        ]);
    }
}
```

## Anti-patterns

| Anti-pattern | Problem | Fix |
|--------------|----------|------------|
| **Recoding existing behavior** | Hook for an existing feature | Run an Explore agent before coding |
| **Modifying the core** | Editing native Thelia templates | Use injection hooks |
| **Heavy hook** | DB queries on every page | Cache, use lazy loading |
| **Wrong event type** | `HookRenderEvent` for hook block | Use `HookRenderBlockEvent` |
| **Missing type** | No `type="front"` in config | Always specify `type="front"` or `type="back"` |
| **Return instead of add** | `return $content;` | Use `$event->add($content)` with return type `void` |
| **Empty content** | Adding an empty block to hook | Check `trim()` before `add()` |
| **Ignoring cache** | Hook with dynamic non-cached data | Use Thelia cache |

## New hook listener checklist

Apply each point in order:

1. Declare the hook in `config.xml` with `id`, `class`, `event`, `type`, `method`.
2. Create the PHP class extending `BaseHook`.
3. Name the method `onPascalCaseHookName()` (e.g., `main.head-bottom` -> `onMainHeadBottom()`).
4. Type-hint the parameter: `HookRenderEvent` (function) or `HookRenderBlockEvent` (block).
5. Declare return type `void`.
6. Use `$event->add()` to inject content (never `return`).
7. Place templates in `templates/{frontOffice|backOffice}/default/`.
8. Use `$this->trans()` for all displayed strings.
9. Test with `?SHOW_HOOK=1` in debug mode to verify injection.
10. Run `php Thelia hook:clean MyModule` after any config modification.
