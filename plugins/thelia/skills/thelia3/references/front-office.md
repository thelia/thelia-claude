# Front-office Flexy and Symfony UX - Thelia 3

> Front 100% Twig (Flexy bundle). Stack: Webpack Encore 4 + Tailwind 3.4 + Stimulus 3.2 + LiveComponent 2.31 + TwigComponent. Turbo and Mercure are ABSENT.

## 1. FlexyBundle and template overrides

`FlexyBundle extends AbstractBundle` (`vendor/thelia/flexy/src/FlexyBundle.php:23`). Loads `FlexyBundle\` from `THELIA_TEMPLATE_DIR/frontOffice/{theme}/src/` and `FlexyBundle\UiComponents\` from `src/UiComponents/`. Active theme read via `ConfigQuery::read('active-front-template', 'default')` (default `flexy`), exposed as Symfony parameter `%thelia_front_template%` (`TheliaKernel.php:175-179`).

Flexy Twig namespaces (`vendor/thelia/flexy/config/packages/twig.yaml`):

| Namespace | Target | Content |
|---|---|---|
| `@components` | `templates/frontOffice/{theme}/components/` | Atoms / Molecules / Organisms / Layout / Page |
| `@UiComponents` | `templates/frontOffice/{theme}/src/UiComponents/` | PHP-backed components (LiveComponent / TwigComponent) |
| `@assets` | `templates/frontOffice/{theme}/assets/` | Images / icons / vendors |
| `@formTwig` | `templates/frontOffice/{theme}/form/` | Form theme |
| `@{ModuleCode}Module` | `{module}/Template/` or `{module}/templates/` | Module-specific Twig templates |

Module override: place `{module}/templates/frontOffice/flexy/mytemplate.html.twig`. The kernel scans `{module}/templates/{templateSubdir}/` at boot (`TheliaKernel.php:835-900`) and adds via `addPath()` to the TwigParser `FilesystemLoader` **after** the active theme (`TwigParser.php:146-149`).

Priority: active theme -> parents -> modules (activation order) -> `default`.

To force priority: `addTemplateDirectory(..., $unshift = true)` (`ParserTemplateTrait.php:78-85`) - not natively exposed, requires event listener.

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

## 4. LiveComponents

`symfony/ux-live-component` 2.31. Attribute `#[AsLiveComponent]` + PHP class.

```php
use Symfony\UX\LiveComponent\Attribute\{AsLiveComponent, LiveAction, LiveArg, LiveListener, LiveProp};
use Symfony\UX\LiveComponent\{ComponentToolsTrait, ComponentWithFormTrait, DefaultActionTrait};
use Thelia\Domain\Cart\CartFacade;

#[AsLiveComponent(name: 'Flexy:Checkout:Cart', template: '@UiComponents/Checkout/Cart/Cart.html.twig')]
class Cart
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

## 5. TwigComponents

`symfony/ux-twig-component`. Stateless, no Ajax.

```php
use Symfony\UX\TwigComponent\Attribute\{AsTwigComponent, ExposeInTemplate, PostMount, PreMount};

#[AsTwigComponent(name: 'Flexy:ProductCard', template: '@UiComponents/ProductCard/ProductCard.html.twig')]
class ProductCard
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
{{ component('Flexy:ProductCard', {productId: 42}) }}
{# Or direct include for static @components templates #}
{{ include('@components/Organisms/CategoryCard/CategoryCard.html.twig', category) }}
```

`twig_component.yaml`: `FlexyBundle\Twig\:` with `name_prefix: Flexy`.

**Trap**: calling `DataAccessService` in `mount()` = synchronous internal AP call on every inclusion. No native cache. For lists, pass data from the parent.

## 6. Stimulus

`@symfony/stimulus-bridge` 3.2 + `@hotwired/stimulus` 3.2. Convention: `{name}_controller.{js|ts}` -> identifier `{name}`.

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

**Turbo and Mercure: ABSENT** from Flexy. Architectural choice - interactivity = LiveComponents only.

### Stimulus / front JS traps

- **`Intl` locale**: Thelia exposes locale as `fr_FR` (underscore) but `Intl.NumberFormat`/`Intl.DateTimeFormat` require `fr-FR` (`RangeError: Invalid language tag` otherwise). Always `(document.documentElement.lang || 'fr-FR').replace('_', '-')` before instantiating.
- **`data-*-value` JSON**: for a Stimulus `Object`/`Array` value, always `{{ data|json_encode|e('html_attr') }}`. Without `e('html_attr')`, a quote in the JSON (e.g. a product title) silently breaks the HTML attribute (Stimulus parses a partial/empty value).
- **URL template + route with regex constraint**: `path('route', {x: 'PLACEHOLDER'})` throws `InvalidParameterException` at **Twig render time** if the route declares a `requirement` on `x`. Pass a **valid** value as anchor (e.g. `'image'` for `image|document|virtual`) then substitute on the JS side on a slash-delimited segment (`url.replace('/image/', '/'+value+'/')`).
- **Module front + Stimulus**: the theme loads its own `Application` via `@symfony/stimulus-bridge`. A module that starts a second `Application.start()` (`@hotwired/stimulus`) conflicts (double-loading of the same controller). Prefer vanilla JS, or register the controller in the theme's existing app.

## 7. Domain facades

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

## 8. Mailing and PDF

Emails: Twig templates in `templates/email/default/` (`.html.twig` + `.txt.twig`), resolved by `TwigParser`. Module override: `{module}/templates/email/default/`. The `message` table row points at the files through `html_template_file_name` / `text_template_file_name`.

PDF: Twig templates in `templates/pdf/default/` (admin invoices and delivery slips), rendered with dompdf. Generation is event-driven: dispatch `TheliaEvents::GENERATE_PDF` with a `PdfEvent($html)` and `Action\Pdf` produces the document. A module can listen to that event at a higher priority to swap the renderer.

Both template sets are Twig in Thelia 3. A `.html` (non-Twig) email or PDF template is a Thelia 2 leftover.

## 9. Assets - Webpack Encore + Tailwind

Stack:
- Bundler: Webpack Encore 4.0 (NOT Vite)
- CSS: PostCSS + Tailwind CSS 3.4 + `postcss-nested` + `postcss-rem`
- TS: `ts-loader` 9.5
- React: Babel preset-react + `@symfony/ux-react` 2.31
- Stimulus: `@symfony/stimulus-bridge` 3.2 + `lazy-controller-loader`

Commands:
```bash
ddev exec bash -c "cd templates/frontOffice/flexy && npm install && npm run build"
# Variants: npm run watch (encore dev --watch), npm run dev (encore dev)
```

Public path: `/templates-assets/frontOffice/{theme}/dist`, symlinked by `EncoreExtension` at kernel boot (guard `!is_dir($dest)`). In production, `THELIA_WEB_DIR/templates-assets/` must be writable.

Tailwind `tailwind.config.js`: custom CSS tokens (`var(--theme)`, `var(--theme-dark)`) -> theming without rebuild. Content scanned: `components/**/*.twig`, `src/UiComponents/**/*.twig`, `form/**/*.twig`, `*.twig`.

## 10. Custom module components

Registering components directly under `FlexyBundle\UiComponents\` (which points to `{theme}/src/UiComponents/`) is not possible for a third-party module.

Canonical option: create a Symfony Bundle for the module with `loadExtension()` that loads a separate namespace + a `config/packages/twig.yaml` in the bundle declaring a dedicated Twig namespace.

```yaml
# {module}/config/packages/twig.yaml
twig:
  paths:
    "%kernel.project_dir%/local/modules/MyModule/templates/UiComponents": MyModuleComponents
```

```php
#[AsTwigComponent(name: 'MyModule:MyCard', template: '@MyModuleComponents/MyCard.html.twig')]
class MyCard { /* ... */ }
```

Simple option (theme coupling): place in `templates/frontOffice/flexy/src/UiComponents/`.

## 11. Sitemap

Flexy exposes `GET /sitemap` and `GET /sitemap.xml` (alias) via `FlexyBundle\Controller\SitemapController`. Rendering goes through `FlexyBundle\Service\SitemapGenerator`, cache-backed on `thelia.cache` (TTL configurable via `ConfigQuery::read('sitemap_ttl', '7200')`). The `sitemap.html.twig` template lives at the root of the active theme and consumes `resources('/api/front/{categories,products,folders,contents}', {'visible': 1})`. Accepted parameters: `?lang=<code>` (404 if unknown lang), `?context=catalog|content` (404 if other value), `?flush=1` to force cache regeneration.

To customize: override `sitemap.html.twig` in the child template, or inject `SitemapGenerator` in a module controller to wrap the render (custom URL addition, multi-file sitemap).

## 12. Traps

| Trap | Fix |
|---|---|
| `resources()` / `attr()` in CLI | guard / fallback / avoid in CLI |
| LiveProp with Propel objects | not serializable - use simple DTOs or arrays |
| `getCartFromSession()` can be null | `getOrCreateFromSession()` for writes |
| `getComponent()` Stimulus without `await` | always `await getComponent(this.element)` |
| Stale `module_template_dirs.php` cache | `cache:clear` after activation |
| Missing `templates-assets/{theme}/dist` symlink | first boot, guard `!is_dir($dest)` |
| `extends BaseFrontController` in LiveComponent | inject `requestStack` directly |
| `resources()` call in Twig `mount()` without cache | pass data from parent or cache |
| `active-front-template` = non-existent directory | always a valid `flexy` value in DB |
