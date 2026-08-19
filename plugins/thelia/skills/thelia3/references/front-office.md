# Front-office Flexy and Symfony UX - Thelia 3

> Front 100% Twig (Flexy bundle). Stack: AssetMapper + Tailwind CLI v4 + Stimulus + LiveComponent + TwigComponent. Mercure is ABSENT; Turbo ships but Drive is off by default (`Turbo.session.drive = false`), opted into per link with `data-turbo="true"`.

## 1. FlexyBundle and template overrides

`FlexyBundle extends AbstractBundle` (`src/FlexyBundle.php`). It registers two PSR-4 roots: `FlexyBundle\` on the theme's `src/` and `FlexyBundle\Components\` on the theme's `components/`. Active theme read via `ConfigQuery::read('active-front-template', 'default')` (default `flexy`), exposed as Symfony parameter `%thelia_front_template%`.

Almost all of the theme's Symfony configuration is done in `FlexyBundle::prependExtension()` rather than in `config/packages/*.yaml`: Twig paths and globals, TwigComponent defaults, AssetMapper paths, UX Icons, Tailwind, Stimulus controller paths.

Flexy Twig namespaces - there are only two:

| Namespace | Target | Content |
|---|---|---|
| `@Flexy` | `templates/frontOffice/{theme}/components/` | All components (PHP-backed and anonymous) |
| `@FlexyForm` | `templates/frontOffice/{theme}/form/` | Form theme |
| `@{ModuleCode}Module` | `{module}/Template/` or `{module}/templates/` | Module-specific Twig templates (registered by the kernel, not by Flexy) |

The old `@components`, `@UiComponents`, `@assets` and `@formTwig` namespaces are gone, along with the `src/UiComponents/` directory they pointed at.

### The theme owns the front catch-all route

Flexy no longer depends on `thelia/front-module` (a Thelia 2 package with no 3.x release). The theme itself declares the catch-all in `FlexyBundle\Controller\ViewController`, which extends the core `Thelia\Controller\Front\DefaultController`:

```php
#[Route(
    '/{_view}',
    name: 'flexy_view',
    requirements: ['_view' => '^(?!admin|api)[^/]+'],
    defaults: ['_view' => 'index'],
    priority: -1000,
)]
public function view(Request $request): void
{
    $this->noAction($request);
}
```

This one route serves categories, products, contents and folders. `priority: -1000` makes it match last, and the requirement keeps `/admin` and `/api` out.

### `config/views.yaml`: root templates that are not pages

A theme's `config/views.yaml` declares its *internal* views - root templates that exist only to be extended, or that render only with the context a controller prepares. Read by `Thelia\Core\Template\InternalViewsDeclaration` and enforced in `ViewRenderer`.

```yaml
internal:
    - base            # layouts, only ever extended
    - checkout-base
    - '404'           # quote it: unquoted, YAML reads an integer and the core rejects it
    - account         # controller checks auth and resolves the entity
    - checkout-cart   # each step guarded by the cart state its controller checks
```

Asking for one of these by name through the catch-all returns 404 instead of a half-rendered page. A controller rendering the same template is unaffected - only requests that *name* a view are filtered. The file is optional: absent, nothing is filtered. A malformed `internal:` key throws a `TemplateException` at boot rather than failing silently.

### Routes that are not views: `ignore_thelia_view`

`Thelia\Core\EventListener\ViewListener` subscribes to `kernel.view`, so it runs only when a controller returns something that is not a `Response`, and only on the main request. Unless the request carries the `ignore_thelia_view` attribute it hands over to `Thelia\Core\View\ViewRenderer`, which reads the `_view` request attribute and renders that template from the active theme.

A module route that declares no `_view` reaches the renderer with an empty view name: it logs `No view found` through `Tlog` and throws a `NotFoundHttpException`. `Thelia\Core\EventListener\ErrorListener` then catches that exception and, in production with the shop set to show its error page, replaces it with the theme's error template. So the endpoint answers a themed 404 page, and the only trace is one line in the Thelia log. A caller expecting JSON gets a shop page and no explanation.

Declare the flag in the route defaults for anything that is not a themed page: JSON and AJAX endpoints, webhooks, callbacks, file downloads.

```php
#[Route(
    '/mymodule/webhook',
    name: 'mymodule_webhook',
    defaults: ['ignore_thelia_view' => true],
)]
```

One flag, three listeners, all keyed on the same request attribute:

| Listener | Without the flag | With it |
|---|---|---|
| `ViewListener` | renders the themed view | stands down |
| `ControllerListener::adminFirewall` | refuses a `BaseAdminController` action to a visitor who is not logged into the admin | stands down, so the route has to guard itself |
| `ErrorListener` | logs the exception and, in production, swaps it for the theme's error page | stands down, so the exception surfaces as Symfony handles it |

The counterpart is that opting out obliges you to return a `Response`: nothing renders a view for you any more, and `HttpKernel` throws `ControllerDoesNotReturnResponseException` on a controller that returns nothing. Nothing in the core ever sets the flag - it comes from route configuration only.

### Module template overrides

Place `{module}/templates/frontOffice/flexy/mytemplate.html.twig`. The kernel scans `{module}/templates/{templateSubdir}/` at boot and adds it via `addPath()` to the TwigParser `FilesystemLoader` **after** the active theme.

Priority: active theme -> parents -> modules (activation order) -> `default`.

To force priority: `addTemplateDirectory(..., $unshift = true)` - not natively exposed, requires an event listener.

Cache: `var/cache/{env}/module_template_dirs.php` - not auto-invalidated on activation/deactivation outside `module:post-activate-all`. Clear as needed.

## 2. Available Twig functions

`DataAccessExtension` (FlexyBundle):

| Function | Signature | Use |
|---|---|---|
| `resources(path, params, format?)` | `string, array=[], ?string='jsonld'` | Internal API Platform call |
| `attr(type, name)` | `string, string` | Contextual attributes (`cart`, `customer`, `product`...) |
| `loop(name, type, params)` | - | **@deprecated** |
| `loopCount(type, params)` | - | **@deprecated** |

`FlexyBundleExtension`: `attributeAv(?ProductSaleElements)`, `getCurrentCustomer()`.

Extensions from TwigEngine (`vendor/thelia/modules/TwigEngine/Extension/`):

| Function | Extension | Use |
|---|---|---|
| `getForm(name, data)` | `FormExtension` | `FormView` of a Thelia form |
| `hook(name, params)` | `HookExtension` | Execute a legacy hook (BO/email/PDF bridge) |
| `theme_hook(name, params)` | `ThemeHookExtension` | Render a theme extension point (modules answer via `ThemeHookInterface`, see hooks.md) |
| `path(routeId, params)` | `URLExtension` | URL (Thelia + SF routes) |
| `isAuthenticated()`, `isAuthenticatedFront()`, `isAuthenticatedAdmin()` | `SecurityExtension` | Auth guards |
| `assertAuth(...)`, `assertCartNotEmpty()`, `assertValidDelivery()` | `SecurityExtension` | Guards (throw if KO) |
| `svg(filename)` | `SvgExtension` | Inline SVG from `assets/icons/` |
| `getAttributesAndValues(...)` | `AttributeExtension` | Product attributes |
| `psesByProduct(productId)` | `PSEExtension` | JSON PSE data |
| `filters_count(filters)` | `FilterExtension` | Active filter count |

### The `app` variable is not Symfony's `AppVariable`

`TwigParser::render()` (in the TwigEngine module, `Template/TwigParser.php`) injects its own `app` into the render context, alongside `locale`, `lang_code`, `lang_id` and `current_url`:

```php
'app' => (object) [
    'environment' => ...,
    'request' => ...,
    'session' => ...,   // null when the request carries none
    'debug' => ...,
],
```

A context variable shadows a Twig global, so every template the parser renders - the page, whatever it extends, whatever it includes - sees that stub instead of `Symfony\Bridge\Twig\AppVariable`. The stub is a plain object with four properties and no methods, and `strict_variables` is off outside the test environment, so `app.flashes(...)`, `app.user`, `app.token` and `app.locale` all resolve to null without a word. A flash block written the Symfony way renders empty and nothing says why.

Read flashes through the session instead, which is what the theme does:

```twig
{% for message in app.session ? app.session.flashBag.get('error') : [] %}
```

The back-office is not in the same position: its controllers render through the injected Twig `Environment` rather than through the parser, so their templates do get the real `AppVariable` and `app.flashes` works there. Which `app` you get depends on who renders the template.

## 3. `resources()` in Twig

```twig
{% set product = resources('/api/front/products/' ~ productId) %}

{% set categories = resources('/api/front/categories', {
    'parent': categoryId,
    'order[position]': 'asc',
    'visible': true
}) %}

{# JSON-LD format for pagination #}
{% set page = resources('/api/front/products', {
    'productCategories.category.id': id,
    'itemsPerPage': 12,
    'page': 1,
}, 'jsonld') %}
{# page['hydra:totalItems'], page['hydra:member'] #}
```

Synchronous, internal AP call. Do NOT call inside a Twig loop without caching.

## 4. Component naming and layout

Components live in the theme's `components/` directory under `FlexyBundle\Components\`, grouped as `Atoms`, `Fields`, `Forms`, `Layouts`, `Molecules`, `Organisms`, `Toolkit`. Each component is a directory holding its PHP class, its Twig template, its CSS and, when it needs one, its Stimulus controller.

TwigComponent is configured with `name_prefix: ''` (empty) and `template_directory: '@Flexy'`, so **the attributes are written bare** and the name and template are both derived from the class path:

```php
namespace FlexyBundle\Components\Molecules\Button;

#[AsTwigComponent]
class Base { /* ... */ }
```

`FlexyBundle\Components\Molecules\Button\Base` is then used as `<twig:Molecules:Button:Base>`. Never pass `name:` or `template:` explicitly in this theme - no component in Flexy does.

```twig
<twig:Layouts:Header:Base />
<twig:Molecules:Breadcrumb:Base :items="breadcrumb" />
```

## 5. LiveComponents

Attribute `#[AsLiveComponent]` + PHP class, same bare-attribute convention.

```php
namespace FlexyBundle\Components\Organisms\Cart;

use Symfony\UX\LiveComponent\Attribute\{AsLiveComponent, LiveAction, LiveArg, LiveListener, LiveProp};
use Symfony\UX\LiveComponent\{ComponentToolsTrait, ComponentWithFormTrait, DefaultActionTrait};
use Thelia\Domain\Cart\CartFacade;

#[AsLiveComponent]
class Base
{
    use DefaultActionTrait;
    use ComponentToolsTrait;       // emit() + dispatchBrowserEvent()
    use ComponentWithFormTrait;    // instantiateForm() + submitForm()

    #[LiveProp(writable: true)]
    public array $items = [];

    public function __construct(private CartFacade $cartFacade) {}

    public function mount(): void { $this->fetchCart(); }

    #[LiveAction]
    public function updateQuantity(#[LiveArg] int $itemId, #[LiveArg] int $quantity): void
    {
        $this->cartFacade->updateItemQuantity(new CartItemUpdateQuantityDTO(/* ... */));
        $this->emit(CheckoutEvents::UPDATE_ITEM_QUANTITY_EVENT);
    }

    #[LiveListener('syncCart')]
    public function onSyncCart(): void { $this->fetchCart(); }
}
```

Patterns:
- `mount()`: one-time init, Propel dependencies resolved.
- Writable `LiveProp`: modified from JS. `url: true`: sync URL (persistent filters).
- `array` LiveProp must contain scalars/simple DTOs - **Propel objects are not serializable**.
- Inter-component events: `$this->emit('eventName')` + `#[LiveListener('eventName')]`.
- Forms: `ComponentWithFormTrait::instantiateForm()` returns the Thelia BaseForm obtained via `formService->getFormByName()`.
- Validation: `$this->submitForm()` runs standard Symfony validation.
- Auto CSRF on `#[LiveAction]` - do not disable.
- XSS: LiveProps serialized as JSON in `data-live-props` - NEVER put secrets there.

**Anti-pattern**: `extends BaseFrontController` to access `requestStack` - inject the service directly in the constructor instead.

## 6. TwigComponents

`symfony/ux-twig-component` (`^2.36 || ^3.1`). Stateless, no Ajax.

```php
namespace FlexyBundle\Components\Molecules\ProductCard;

use Symfony\UX\TwigComponent\Attribute\{AsTwigComponent, ExposeInTemplate, PostMount, PreMount};

#[AsTwigComponent]
class Base
{
    public ?int $productId = null;
    public ?array $product = null;

    public function __construct(private DataAccessService $das) {}

    #[PreMount]
    public function preMount(array $data): array
    {
        if (isset($data['productId'])) {
            return $data;
        }
        return $data;
    }

    public function mount(): void
    {
        $this->product = $this->das->resources('/api/front/products/'.$this->productId);
    }
}
```

`#[PostMount]`: modifies the object after prop injection. `#[ExposeInTemplate]`: exposes a private property to the template.

Twig invocation:
```twig
<twig:Molecules:ProductCard:Base :productId="42" />
{# Anonymous components resolve against @Flexy too #}
{{ include('@Flexy/Organisms/CategoryCard/Base.html.twig', category) }}
```

**Trap**: calling `DataAccessService` in `mount()` = synchronous internal AP call on every inclusion. No native cache. For lists, pass data from the parent.

### `provide()` / `inject()` on PHP 8.3

`symfony/ux-twig-component` ships `provide()` and `inject()` from 3.0 on, but 3.0 requires PHP 8.4. On PHP 8.3 Composer resolves the 2.x line, where those functions do not exist, and every compound component fails to render. The theme fills the gap itself with `FlexyBundle\Twig\ComponentContextExtension`, which registers the two functions and then returns nothing when `symfony/ux-twig-component >= 3.0` is installed, so the package's own implementation always wins on 8.4. Backing store `FlexyBundle\Twig\ComponentContext` keeps a stack of frames pushed on `PreRenderEvent` and popped on `PostRenderEvent`; `inject()` walks it innermost-first, so a provided value is scoped to the providing component and its subtree.

Do not add your own `provide`/`inject` Twig functions in a module: you would collide with one of the two implementations depending on the PHP version in use.

## 7. Stimulus

Convention: `{name}_controller.js` -> identifier `{name}`. Controllers live in two places: shared ones in `assets/controllers/`, component-specific ones next to their component in `components/`. Both directories are registered as `stimulus.controller_paths`.

Twig activation: `stimulus_controller('product')` (SF UX helper).

Stimulus bridge to LiveComponent: `getComponent(this.element)` from `@symfony/ux-live-component` (always `await`!).

`data-action: 'live#action'` or `live#emit` activate LiveActions without custom Stimulus.

```twig
<div {{ attributes.defaults(stimulus_controller('product')) }}
     data-product-current-pse-id-value="{{ currentPse.id }}">
```

```js
// assets/controllers/product_controller.js
import { Controller } from '@hotwired/stimulus';
import { getComponent } from '@symfony/ux-live-component';

export default class extends Controller {
    async connect() {
        this.component = await getComponent(this.element);
    }
}
```

**Mercure: ABSENT** from Flexy. Turbo ships - `@hotwired/turbo` sits in the theme's `importmap.php` and `assets/app.js` imports it - but the same file sets `Turbo.session.drive = false`, so Drive is off globally and only a zone marked `data-turbo="true"` (the checkout tunnel) navigates client-side. Everywhere else, interactivity = LiveComponents.

### Stimulus / front JS traps

- **`Intl` locale**: Thelia exposes locale as `fr_FR` (underscore) but `Intl.NumberFormat`/`Intl.DateTimeFormat` require `fr-FR` (`RangeError: Invalid language tag` otherwise). Always `(document.documentElement.lang || 'fr-FR').replace('_', '-')` before instantiating.
- **`data-*-value` JSON**: for a Stimulus `Object`/`Array` value, always `{{ data|json_encode|e('html_attr') }}`. Without `e('html_attr')`, a quote in the JSON (e.g. a product title) silently breaks the HTML attribute (Stimulus parses a partial/empty value).
- **URL template + route with regex constraint**: `path('route', {x: 'PLACEHOLDER'})` throws `InvalidParameterException` at **Twig render time** if the route declares a `requirement` on `x`. Pass a **valid** value as anchor (e.g. `'image'` for `image|document|virtual`) then substitute on the JS side on a slash-delimited segment (`url.replace('/image/', '/'+value+'/')`).
- **Module front + Stimulus**: the theme starts its own `Application` in `assets/stimulus_bootstrap.js` via `startStimulusApp()` from `@symfony/stimulus-bundle`. A module that starts a second `Application.start()` (`@hotwired/stimulus`) conflicts (double-loading of the same controller). Prefer vanilla JS, or register the controller in the theme's existing app.

## 8. Domain facades

`core/lib/Thelia/Domain/{Cart,Customer,Checkout,Order}/`. Single entry point for cart/checkout/auth mutations.

| Facade | Key methods | Use |
|---|---|---|
| `CartFacade` | `addItem(CartItemAddDTO)`, `removeItem(CartItemDeleteDTO)`, `updateItemQuantity(CartItemUpdateQuantityDTO)` (throws `NotEnoughStockException`), `setDeliveryAddress/InvoiceAddress/DeliveryModule/PaymentModule(CheckoutDTO)`, `getCartFromSession(): ?Cart`, `getOrCreateFromSession(): Cart` | Cart mutations, preliminary checkout selections |
| `CustomerFacade` | `login(CustomerLogin)`, `logout()`, `getCurrentCustomer(): ?Customer`, `isLoggedIn(): bool`, `register(CustomerRegisterDTO): Customer`, `update(...)`, `sendCode(Customer)` | Auth + front customer CRUD |
| `CheckoutFacade` | `selectDeliveryAddress/InvoiceAddress/DeliveryModule/PaymentModule(CheckoutDTO)`, `validateForOrder(Cart)`, `pay(CheckoutDTO): ?Response`, `cancelOrder(int): Order`, `resetCheckout()` | Final checkout + payment |
| `OrderFacade` | low-level, internal to `CheckoutFacade` | Do NOT inject in front modules (use `CheckoutFacade::pay()`) |

**Trap**: `CartFacade::getCartFromSession()` can return `null`. For write actions: use `getOrCreateFromSession()`.

When to use a Facade vs direct Propel:

| Situation | Approach |
|---|---|
| Business operations (cart, checkout, customer) | Facade |
| Simple read queries | `resources()` Twig or `DataAccessService::resources()` PHP |
| Import/export scripts, CLI | Direct Propel (`XxxQuery::create()`) |
| LiveComponents | Facade |

## 9. Mailing and PDF

Emails: Twig templates in `templates/email/default/` (`.html.twig` + `.txt.twig`), resolved by `TwigParser`. Module override: `{module}/templates/email/default/`. The `message` table row points at the files through `html_template_file_name` / `text_template_file_name`.

PDF: Twig templates in `templates/pdf/default/` (admin invoices and delivery slips), rendered with dompdf. Generation is event-driven: dispatch `TheliaEvents::GENERATE_PDF` with a `PdfEvent($html)` and `Action\Pdf` produces the document. A module can listen to that event at a higher priority to swap the renderer.

Both template sets are Twig in Thelia 3. A `.html` (non-Twig) email or PDF template is a Thelia 2 leftover.

## 10. Forms and the form theme

Flexy's form theme is `@FlexyForm/flexy_form_theme.html.twig`. It is **not** registered as a global `twig.form_themes` entry, on purpose: a global theme would also restyle the back-office forms. Instead the bundle exposes a Twig global, `flexy_form_themes`, and every template opts in explicitly:

```twig
{% form_theme form with flexy_form_themes only %}
```

The `only` keyword keeps anything else out. The back-office does the same with its own `bo_form_themes` global. Consequence: a front-office form rendered without that tag gets Symfony's bare default markup, not Flexy widgets. Put the tag inside the rendered block, before `form_start`.

## 11. Assets - AssetMapper + Tailwind CLI

There is **no bundler, no `package.json`, no `webpack.config.js` and no `node_modules`** in the theme. Webpack Encore is gone, and so is `@symfony/ux-react`.

- JavaScript: AssetMapper. The theme's `importmap.php` declares the `app` entrypoint (`assets/app.js`) and its vendor packages (Stimulus, `@symfony/ux-live-component`, `@symfony/ux-translator`, Turbo, Leaflet, Splide). `importmap:install` downloads them into `assets/vendor/` (git-ignored).
- CSS: `symfonycasts/tailwind-bundle` drives a standalone Tailwind v4 binary. `tailwind:build` compiles `assets/styles/app.css`, which is the config: Tailwind v4 is CSS-first, so there is no `tailwind.config.js`. Because the theme directory is git-ignored from the project root, the scanned paths are declared explicitly with `@source` (`components`, `partials`, `form`, `blocks`, root `*.html.twig`).
- Icons: `symfony/ux-icons`, reading `assets/icons/`.
- Class merging: `tales-from-a-dev/twig-tailwind-extra`, with custom class groups configured in the theme.

`bin/install` runs `importmap:install`, `tailwind:build` and `sass:build` itself when those commands exist, so a fresh install needs no manual asset step at all — the `default-twig` back office builds with sass-bundle since 1.0.0-beta9, npm is gone everywhere.

Public output is AssetMapper's, under `/assets/frontOffice/{theme}/`. The old `templates-assets/{theme}/dist` symlink and the `<assets>dist</assets>` entry in `template.xml` no longer apply to Flexy.

### Building for production

What `bin/install` runs is a development build. A production deployment needs two more steps:

```bash
php bin/console tailwind:build --minify
php bin/console asset-map:compile
```

`tailwind:build` on its own writes unminified CSS. `asset-map:compile` writes the mapped assets and their manifest into the public directory; AssetMapper's dev server, which serves them on the fly otherwise, defaults to the debug flag and is therefore off in production. Skip the compile and the front office loads with no CSS and no JavaScript, on a page that is otherwise fine.

Run both again after any deployment that touches templates. Tailwind v4 scans the Twig sources, so a utility class used for the first time in a template only reaches the stylesheet once a build has seen it.

## 12. Virtual product download

Flexy serves virtual product files from the customer account:

```
GET /account/order/download/{orderProductId}     route: account_order_download
```

`FlexyBundle\Controller\AccountOrderController::downloadVirtualProduct` checks authentication, verifies the order product belongs to the current customer and that the order is paid, then dispatches `TheliaEvents::VIRTUAL_PRODUCT_ORDER_DOWNLOAD_RESPONSE` with a `VirtualProductOrderDownloadResponseEvent`. The response comes from whichever module answers (VirtualProductDelivery in a standard install); if none does, the route 404s. A module implementing its own virtual delivery listens to that event and calls `setResponse()`.

## 13. Custom module components

A third-party module cannot register components under `FlexyBundle\Components\`, which is bound to the active theme's `components/` directory.

Canonical option: create a Symfony Bundle for the module with `loadExtension()` that loads a separate namespace + a `config/packages/twig.yaml` in the bundle declaring a dedicated Twig namespace.

```yaml
# {module}/config/packages/twig.yaml
twig:
  paths:
    "%kernel.project_dir%/local/modules/MyModule/templates/components": MyModuleComponents
```

```php
#[AsTwigComponent(name: 'MyModule:MyCard', template: '@MyModuleComponents/MyCard.html.twig')]
class MyCard { /* ... */ }
```

Simple option (theme coupling): place the component in the active theme's `components/` directory.

## 14. Sitemap

Flexy exposes `GET /sitemap` and `GET /sitemap.xml` (alias) via `FlexyBundle\Controller\SitemapController`. Rendering goes through `FlexyBundle\Service\SitemapGenerator`, cache-backed on `thelia.cache` (TTL configurable via `ConfigQuery::read('sitemap_ttl', '7200')`). The `sitemap.html.twig` template lives at the root of the active theme and consumes `resources('/api/front/{categories,products,folders,contents}', {'visible': 1})`. Accepted parameters: `?lang=<code>` (404 if unknown lang), `?context=catalog|content` (404 if other value), `?flush=1` to force cache regeneration.

To customize: override `sitemap.html.twig` in the child template, or inject `SitemapGenerator` in a module controller to wrap the render (custom URL addition, multi-file sitemap).

## 15. Traps

| Trap | Fix |
|---|---|
| `resources()` / `attr()` in CLI | guard / fallback / avoid in CLI |
| LiveProp with Propel objects | not serializable - use simple DTOs or arrays |
| `getCartFromSession()` can be null | `getOrCreateFromSession()` for writes |
| `getComponent()` Stimulus without `await` | always `await getComponent(this.element)` |
| Stale `module_template_dirs.php` cache | `cache:clear` after activation |
| `extends BaseFrontController` in LiveComponent | inject `requestStack` directly |
| `resources()` call in Twig `mount()` without cache | pass data from parent or cache |
| `active-front-template` = non-existent directory | always a valid `flexy` value in DB |
| LiveComponents answer 404 | `/_components` route needs `defaults: ignore_thelia_view: true` |
| Front page 500 right after install | `importmap:install` / `tailwind:build` did not run - assets missing |
| `provide()` / `inject()` undefined on PHP 8.3 | ux-twig-component resolves to 2.x; the theme's `ComponentContextExtension` supplies them - do not add your own |
| Component named with `name:` or `template:` | prefix is empty and the template is derived from the class path - write the attribute bare |
| A form rendering as bare Symfony markup | no theme is global any more; add `{% form_theme form with flexy_form_themes only %}` |
| A module JSON or webhook route answers a themed 404 page | it is still going through `ViewListener`; add `defaults: ['ignore_thelia_view' => true]` |
| `app.flashes()` or `app.user` renders nothing | the parser's `app` is a four-property stub, not `AppVariable` - read flashes from `app.session.flashBag` |
| A label translated in PHP shows its raw key | plain `TranslatorInterface` autowires to Thelia's `Translator`, which has no `messages` catalog - inject `#[Autowire(service: 'translator')]` |
| Front office deployed with no CSS or JavaScript | `asset-map:compile` was not run; AssetMapper's dev server is off outside debug |
