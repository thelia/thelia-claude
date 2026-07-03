---
name: thelia3-module-migration
description: "Migrating a Thelia 2 module to Thelia 3 (twig branch, Symfony 7.4 LTS, API Platform 4.3, PHP 8.3): namespace and directory structure changes, config.xml cleanup, auto-discovery of hooks/loops/forms (no config.xml declarations needed in T3), #[Route] replacing @Route and routing.xml, #[AutowireIterator]/#[AutowireLocator] replacing deprecated #[TaggedIterator]/#[TaggedLocator], native return types on Symfony interface overrides, Symfony 6.4-to-7.4 breaking changes, API Platform 3.x-to-4.3 breaking changes (namespace removals, openapiContext removal, standalone setup), Propel native typing strictness (tinyint as int not bool, decimal as string not float), migrating from thelia/open-api-module to native API Platform resources, back-office Smarty hook templates, front-office Smarty .tpl to Twig .html.twig with resources() replacing {loop}, LiveComponents replacing manual JS. Triggers on: migrate module, port module T2 T3, config.xml to configureServices, routing.xml to Route attribute, TaggedIterator AutowireIterator, open-api-module drop, BaseApiModel PropelResourceInterface, ApiPlatform\\Api removed, openapiContext deprecated, Thelia\\Install\\Database legacy namespace, getAnnotationRoutePrefix deprecated, BaseLoop deprecated."
---

# Thelia 2 to Thelia 3: Module Migration Guide

> Covers porting a T2 module to T3 (twig branch, Symfony 7.4 LTS, API Platform 4.3, PHP 8.3) and modernizing an older T3 module that predates auto-registration.

## 1. Breaking changes at a glance

| Aspect | Thelia 2 | Thelia 3 (twig) | Impact |
|---|---|---|---|
| PHP | 8.0 - 8.2 | **8.3+** | strict_types, modern types |
| Symfony | 6.0 - 6.3 | **7.4 LTS** | PHP 8 attributes, MapRequestPayload, Voters |
| API | API Platform 3.x | **4.3 standalone** | Propel-based resources, addons |
| Front templates | Smarty `.html` | **Twig `.html.twig`** (Flexy) | Full template rewrite |
| Front data | `{loop}` Smarty | `resources('/api/front/...')` | Internal API Platform call |
| Front interactivity | Hooks + manual JS | **LiveComponents + Stimulus** | Reactive components |
| Front HTML injection | `{hook}` Smarty | **Theme hooks** (`ThemeHookInterface` + `theme_hook()`) | Pure code, the theme declares the points |
| Back-office | Smarty + XML hooks | **Smarty + auto-tag hooks** | XML hook declarations become optional |
| DI | `<services>` in config.xml | `configureServices()` PHP | Modern, autoconfigure |
| Routes | routing.xml | `#[Route]` PHP 8 | Auto-scanned from `Controller/` |
| Business logic | Event Actions | **Facades** + Services | `CartFacade`, `CustomerFacade`, etc. |
| Database namespace | `Thelia\Install\Database` | `Thelia\Core\Install\Database` | Update use statement |
| `configureServices` exclude | `THELIA_MODULE_DIR` constant | Relative path (`__DIR__.'/I18n/*'`) | Simpler |
| API auth | None native | **JWT Lexik 3.2** + `/api/{front\|admin}/login` | Token-based |

---

## 2. Migration workflow

1. **Audit deps.** Review composer.json, PHP version, and any T2-only external deps.
2. **`module.xml`**: update to XSD `module-2_2.xsd`, namespace `http://thelia.net/schema/dic/module`.
3. **`MyModule.php`**: add `configureServices()` static method. Without it, zero classes are scanned.
4. **`config.xml`**: strip `<services>`, `<hooks>`, `<loops>`, `<forms>`, `<commands>` (see section 3). They are now auto-discovered.
5. **`routing.xml`**: delete, replace with `#[Route]` PHP 8 attributes on controllers.
6. **`schema.xml`**: adapt table namespaces and `external-schema` declarations for core FKs.
7. **Hooks**: convert `<hooks>` XML to `extends BaseHook` + `static getSubscribedHooks()`. Back-office templates stay Smarty.
8. **Loops**: `BaseLoop` is `@deprecated`. Keep as-is for back-office Smarty. For front-office, migrate to API Resources.
9. **Front templates**: rewrite `.tpl` Smarty to `.html.twig` Flexy. `{loop}` becomes `resources()`. Manual JS becomes LiveComponents + Stimulus.
10. **API**: expose models via `PropelResourceInterface` (see section 5). To extend a native resource, use `ResourceAddonInterface`.
11. **Forms**: keep `BaseForm` for HTML web forms. For simple REST APIs, use DTO + `#[MapRequestPayload]`.
12. **Tests**: port to `IntegrationTestCase` / `ApiTestCase` + `FixtureFactory`.
13. **Code style**: `final readonly class` on services and DTOs (not Thelia controllers), `declare(strict_types=1)`, guard clauses, no abbreviations.

---

## 3. What to remove from config.xml

| XML element | T3 replacement |
|---|---|
| `<services>` (business services) | `configureServices()` with `load()->autowire()->autoconfigure()` |
| `<hooks>` | `extends BaseHook` + `static getSubscribedHooks()` |
| `<loops>` (except aliases) | `extends BaseLoop` (auto snake_case) or migrate to API Resource |
| `<forms>` | `extends BaseForm` + `static getName()` |
| `<commands>` | `#[AsCommand]` + autoconfigure `console.command` / `thelia.command` |

Keep in config.xml if still needed:
- `<exports>` / `<imports>` (channels)
- `<parameters>`
- `<loop name="alias">` when alias differs from auto snake_case

---

## 4. Front templates: Smarty to Twig

| Smarty T2 | Twig T3 |
|---|---|
| `{loop type="product" id="42"}{$TITLE}{/loop}` | `{% set product = resources('/api/front/products/42') %}{{ product.title }}` |
| `{$smarty.const.URL}` / `{path()}` | `{{ path('route_id') }}` |
| `{intl l='Hello'}` | `{{ 'Hello'\|trans({}, 'mymodule') }}` |
| `{form name="thelia.customer.login"}` | `{% set form = getForm('thelia.customer.login') %}{{ form_start(form) }}` |
| `{hook name="product.top" product=$product}` | Front: implement `Thelia\Core\Hook\Theme\ThemeHookInterface` answering a point the theme declares (Flexy: `theme_hook('product.top', {product: product})`). BO: `BaseHook` unchanged. |
| `{include file="..."}` | `{% include '@components/...' %}` |
| `{assign var=...}` | `{% set ... %}` |
| Complex conditional loop | `{% if %}{% else %}{% endif %}`, Twig filters |

Front interactivity: move manual JS to LiveComponent or Stimulus controllers.

### Back-office forms

For a module's back-office (default-twig) screens, render forms with the standard Symfony helpers (`form_row`, `form_widget`, `form_label`) rather than hand-built `<input name="{{ form.vars.full_name }}[field]">` with a manual `{{ form._token.vars.value }}`. Theme each form root explicitly:

```twig
{% form_theme form with bo_form_themes only %}
{{ form_start(form) }}
```

`bo_form_themes` is a Twig global provided by the default-twig back-office (`['bootstrap_5_layout.html.twig', '@BackOfficeDefaultTwigForm/bo_form_theme.html.twig']`). The `only` keyword keeps the global front-office Flexy theme out, so the form renders as Bootstrap and never picks up a Flexy `FieldInput` widget. Put the tag inside the rendered block, before `form_start`. Do not pass a single theme with `only` (it 500s on `form_start`); always go through `bo_form_themes`. See the `thelia3-backoffice-twig` skill for the full rationale.

---

## 5. Loop to API Resource

Loop T2:
```php
class Brand extends BaseLoop implements PropelSearchLoopInterface
{
    public function buildModelCriteria()
    {
        return BrandQuery::create()->filterByVisible(true);
    }
}
// {loop type="brand"}...{/loop}
```

Resource T3:
```php
#[ApiResource(
    uriTemplate: '/front/brands',
    operations: [new GetCollection(), new Get()],
    normalizationContext: ['groups' => ['front:brand:read']],
)]
#[ApiFilter(filterClass: BooleanFilter::class, properties: ['visible'])]
class Brand extends AbstractTranslatableResource
{
    #[Groups(['front:brand:read'])]
    public ?int $id = null;

    public static function getPropelRelatedTableMap(): ?TableMap { return new BrandTableMap(); }
    public static function getI18nResourceClass(): string { return BrandI18n::class; }
}
```

Twig usage:
```twig
{% set brands = resources('/api/front/brands', {visible: true}) %}
{% for brand in brands %}
    <a href="{{ path('brand_show', {slug: brand.slug}) }}">{{ brand.title }}</a>
{% endfor %}
```

---

## 6. Extending a native resource

T2 pattern: custom table + listener on Customer events.

T3 pattern: `ResourceAddonInterface` for automatic JOIN and JSON exposure under the addon's short name.

```php
class CustomerCustomerFamily implements ResourceAddonInterface
{
    use ResourceAddonTrait;

    #[Groups(['admin:customer:read', 'admin:customer:write', 'front:customer:read'])]
    public ?string $code = null;

    public static function getResourceParent(): string { return Customer::class; }
    public static function getPropelRelatedTableMap(): ?TableMap { return new CustomerCustomerFamilyTableMap(); }
}
```

Result in JSON:
```json
{
  "id": 12,
  "email": "...",
  "customerCustomerFamily": {"code": "pro"}
}
```

For polymorphic relations (no declared FK), override `extendQuery()` to a no-op and load data in `buildFromModel()`. `getPropelRelatedTableMap()` may return `null` on addons (the trait only throws on concrete resources).

---

## 7. Front interactivity: manual JS to LiveComponent

T2:
```html
<div class="cart-item" data-id="{$id}">
  <button onclick="updateQty(this, {$id})">+</button>
</div>
<script>function updateQty(btn, id) { /* manual AJAX */ }</script>
```

T3:
```php
#[AsLiveComponent(name: 'Flexy:CartItem')]
class CartItem
{
    use DefaultActionTrait, ComponentToolsTrait;

    #[LiveProp]
    public int $itemId;

    public function __construct(private CartFacade $cart) {}

    #[LiveAction]
    public function increment(): void
    {
        $this->cart->updateItemQuantity(new CartItemUpdateQuantityDTO(/* ... */));
    }
}
```

```twig
{# CartItem.html.twig #}
<div {{ attributes }}>
    <button data-action="live#action" data-live-action-param="increment">+</button>
</div>
```

---

## 8. Code standards

```php
declare(strict_types=1);

final readonly class MyService
{
    public function __construct(
        private LoggerInterface $logger,
        private DataAccessService $das,
    ) {
    }

    public function process(?Order $order): void
    {
        if ($order === null) {
            return;                // guard clause
        }
        if (!$order->isPaid()) {
            return;
        }
        // business logic
    }
}
```

Rules:
- `final readonly class` on services, DTOs, listeners, processors. Not on Thelia controllers.
- `declare(strict_types=1)` everywhere.
- Constructor injection (promoted properties).
- Guard clauses and early return, no deep nesting.
- `#[Autowire]` for env/parameter injection, `#[Route]` for routes, `#[AsCommand]` for commands.
- No abbreviations in naming.
- No redundant PHPDoc. Keep only non-obvious `@throws` and complex types.
- PSR-12.

---

## 9. Deprecated patterns to block

| Anti-pattern | Replacement |
|---|---|
| `<services>` `<hooks>` `<loops>` `<forms>` `<commands>` in config.xml | autoconfigure |
| `routing.xml` | `#[Route]` PHP 8 |
| `@Route` Doctrine annotations | `#[Route]` |
| `getAnnotationRoutePrefix()` | `getRoutePrefix()` |
| `#[TaggedIterator]` / `#[TaggedLocator]` | `#[AutowireIterator]` / `#[AutowireLocator]` |
| `loop()` / `loopCount()` Twig + DAS | `resources('/api/front/...')` |
| `BaseLoop` for new front-office dev | API Resources |
| `Thelia\Install\Database` | `Thelia\Core\Install\Database` |
| `final readonly` on Thelia controllers | remove `readonly` |
| `extends BaseFrontController` in LiveComponent | direct constructor injection |
| `OpenApi @OA\Schema` annotations | `#[ApiResource]` |
| `BaseApiModel` | `PropelResourceInterface` + `PropelResourceTrait` |
| `ApiPlatform\Api\*` (removed in AP 4, no alias, fatal at boot) | `ApiPlatform\Metadata\*` |
| `ApiPlatform\Exception\*` (removed in AP 4) | `ApiPlatform\Metadata\Exception\*` |
| `openapiContext:` on an operation (`Get`, `Post`, ...) | `openapi: new Operation(...)` (still supported on `#[ApiProperty]`) |
| Doctrine `EntityManager` | Propel `XxxQuery::create()` |

---

## 10. Dropping thelia/open-api-module

Modules that relied on `thelia/open-api-module` (controllers extending `BaseAdminOpenApiController`, models extending `BaseApiModel`, endpoints under `/open_api/*`) need a full replacement. The module was a pre-bridge shim before native API Platform support landed.

### 10.1 Target: native AP 4.3 resources

After migration:
- One or more `Api/Resource/*` classes with `/api/admin/*` and `/api/front/*` operations.
- Remove `Model/Api/*BaseApiModel` classes.
- Remove `ApiExtend/*ApiListener` classes, replace with `ResourceAddonInterface` or `QueryCollectionExtensionInterface`.
- For legacy routes (`/open_api/*`) still called by an external consumer (npm bundle, mobile app), keep the route but rewrite the controller as plain Symfony + Propel, dropping all `OpenApi\` imports.
- `composer.json`: drop `thelia/open-api-module` from `require`.
- `module.xml`: drop `<module>OpenApi</module>` from `<required>`. Leaving it causes `SchemaLocator::addModulesDependencies()` to crash at boot with "Module OpenApi directory doesn't exists".

### 10.2 Multipart upload

`PropelPersistProcessor` does not handle binary files. Use an invokable controller:

```php
new Post(
    uriTemplate: '/admin/library_xxx',
    inputFormats: ['multipart' => ['multipart/form-data']],
    controller: LibraryXxxUploadController::class,
    deserialize: false,
    validate: false,
    write: false, // without this, PropelPersistProcessor re-inserts and throws "Cannot insert auto-increment id"
),
```

```php
#[AsController]
final readonly class LibraryXxxUploadController
{
    public function __construct(
        private LibraryXxxService $service,
        private ApiResourcePropelTransformerService $transformer,
    ) {}

    public function __invoke(Request $request): PropelResourceInterface
    {
        $file = $request->files->get('image');
        if (!$file instanceof UploadedFile) {
            throw new BadRequestHttpException('Missing required "image" file part.');
        }

        $propelModel = $this->service->createImage(
            file: $file,
            title: $request->request->get('title'),
            locale: $request->request->get('locale') ?? Lang::getDefaultLanguage()->getLocale(),
        );

        $operation = $request->attributes->get('_api_operation');

        return $this->transformer->modelToResource(
            resourceClass: LibraryXxx::class,
            propelModel: $propelModel,
            context: $operation->getNormalizationContext() ?? [],
            withAddon: false,
        );
    }
}
```

In tests using `KernelBrowser`: the service calls `move()` on the fixture file, so copy it to a temp path before each upload assertion, otherwise the second upload fails with `FileNotFoundException`.

```php
$file = new UploadedFile($fixturePath, 'sample.png', 'image/png', null, true);

$this->client->request(
    'POST',
    '/api/admin/library_xxx',
    parameters: ['title' => 'Hero', 'locale' => 'en_US'],
    files: ['image' => $file],
    server: [
        'CONTENT_TYPE' => 'multipart/form-data',
        'HTTP_AUTHORIZATION' => 'Bearer '.$token,
        'HTTP_ACCEPT' => 'application/ld+json',
    ],
);
```

### 10.3 Custom delete with filesystem side effects

`PropelRemoveProcessor` only calls `$model->delete()`. If the model owns a physical file, override the processor:

```php
new Delete(
    uriTemplate: '/admin/library_xxx/{id}',
    processor: LibraryXxxDeleteProcessor::class,
),
```

```php
final readonly class LibraryXxxDeleteProcessor implements ProcessorInterface
{
    public function __construct(private LibraryXxxService $service) {}

    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): void
    {
        $id = $uriVariables['id'] ?? null;
        if (null === $id) {
            throw new NotFoundHttpException('Missing id.');
        }
        if (false === $this->service->deleteImage((int) $id)) {
            throw new NotFoundHttpException();
        }
    }
}
```

### 10.4 Polymorphic ResourceAddon (no declared FK)

`ResourceAddonTrait::extendQuery()` assumes a JOIN on a table with a declared FK. For polymorphic relations (`item_type` + `item_id`), override it:

```php
class ProductLibraryImagesAddon implements ResourceAddonInterface
{
    use ResourceAddonTrait;

    /** @var array<int, LibraryItemImage> */
    #[Groups([Product::GROUP_ADMIN_READ_SINGLE, Product::GROUP_FRONT_READ_SINGLE])]
    public array $libraryImages = [];

    public static function getResourceParent(): string { return Product::class; }
    public static function getPropelRelatedTableMap(): ?TableMap { return null; }

    public static function extendQuery(ModelCriteria $query, ?Operation $operation = null, array $context = []): void
    {
        // No-op: no FK, load on demand in buildFromModel().
    }

    public function buildFromModel(ActiveRecordInterface $product, PropelResourceInterface $host): ResourceAddonInterface
    {
        $rows = LibraryItemImageQuery::create()
            ->filterByItemType('product')
            ->filterByItemId($product->getId())
            ->orderByPosition()
            ->find();

        $this->libraryImages = array_map(
            static fn (LibraryItemImageModel $row): LibraryItemImage => self::mapRow($row),
            iterator_to_array($rows),
        );

        return $this;
    }

    public function buildFromArray(array $data, PropelResourceInterface $host): ResourceAddonInterface { return $this; }
    public function doSave(ActiveRecordInterface $ar, PropelResourceInterface $host): void {}
    public function doDelete(ActiveRecordInterface $ar, PropelResourceInterface $host): void {}
}
```

### 10.5 Legacy shim for /open_api/* routes

When an external consumer still calls `/open_api/library/image`, keep the route but remove the OpenApi dependency:

```php
#[Route('/open_api/library/image', name: 'thelialibrary_legacy_image_admin')]
final class ImageController extends BaseAdminController
{
    #[Route('', name: '_create', methods: ['POST'])]
    public function createImage(Request $request, LibraryImageService $service): JsonResponse
    {
        $file = $request->files->get('image');
        if (null === $file) {
            return $this->legacyJson(['error' => 'Missing required image file'], 400);
        }
        $locale = $this->resolveLocale($request);
        $image = $service->createImage($file, $request->request->get('title'), $locale);

        return $this->legacyJson(LegacyLibraryImageSerializer::imageToArray($image, $locale));
    }

    private function legacyJson(mixed $data, int $status = 200): JsonResponse
    {
        $response = (new JsonResponse())->setContent(json_encode($data));
        $response->headers->set('Access-Control-Allow-Origin', '*');

        return $response->setStatusCode($status);
    }
}
```

The legacy serializer must reproduce the exact JSON shape of the old `OpenApi\Model\Api\*` classes (keys, types, null vs absent values). Any drift breaks the client. Verify with a curl diff against the baseline before changing anything.

### 10.6 Removing the open-api-module dependency

Once all modules have been cleaned (controllers, models, listeners, module.xml requirements):

```bash
composer update thelia/flexy thelia/thelia-blocks-module thelia/thelia-library-module --no-interaction
composer why thelia/open-api-module
```

If `composer why` still lists consuming modules, migrate those first.

**Payment event migration.** Before Thelia 3 twig commit `2e0e5da9d`, `PaymentModuleService` dispatched two events that lived inside the OpenApi module. Those events were replaced with native Thelia equivalents:
- `Thelia\Api\Resource\PaymentModuleOption{,Group,Choice}` (mirroring `DeliveryModuleOption`).
- `Thelia\Api\Bridge\Propel\Event\PaymentModuleOptionEvent` with the same constructor contract.
- `PaymentModuleService` now uses `TheliaEvents::MODULE_PAYMENT_GET_OPTIONS` (same string `thelia.module.payment.options`, so no BC on the event name contract).

Payment modules that type-hint the old OpenApi event class (PayPal, Payzen, CawlPayment, etc.) need two changes: retype the listener to `Thelia\Api\Bridge\Propel\Event\PaymentModuleOptionEvent`, and replace `$modelFactory->buildModel('PaymentModuleOption{,Group}')` with `new \Thelia\Api\Resource\PaymentModuleOption{,Group}()`.

**Known ecosystem issue.** `ChoiceFilter` declares a `choice_filter_other` table that is already present in the core `schema.xml`, causing "Table declared twice" at boot. The fix is tracked on the core side; do not work around it in your module.

---

## 11. Migration pitfalls

| Pitfall | Solution |
|---|---|
| Module on filesystem but absent from database | `module:refresh` then `module:activate` |
| Stale Twig cache after template override | `cache:clear` |
| `module_template_dirs.php` stale | `cache:clear` after activation |
| `var/propel/test/` cache pointing at wrong database | `bin/test-prepare` auto-purges it |
| `THELIA_VERSION = '2.6.0'` | Constant not bumped for T3, do not rely on it |
| `getPropelRelatedTableMap()` returns null on concrete resource | Always return `new XxxTableMap()` |
| LiveProp with Propel object | Use DTOs or scalar values only |
| `resources()` called from CLI | Unusable, throws `RuntimeException` (no main request). Add a guard or avoid. |
| FlexyBundle crashes at boot | `active-front-template` must be a valid directory name (`flexy`) |
| Propel tinyint setter called with `true`/`false` | Columns are typed `?int` under strict types. Pass `0` or `1`. |
| Propel decimal setter called with `float` | Columns are typed `?string`. Pass a string. |
| `#[Ignore]` on a `static` method | Crashes the Serializer. Never use it on static. |
| `ApiPlatform\Api\*` import left in place | Fatal at boot in AP 4 (no alias). Replace with `ApiPlatform\Metadata\*`. |
| `openapiContext:` left on an operation | Silently ignored or fatal in AP 4. Replace with `openapi: new Operation(...)`. |

---

## 12. Final migration checklist

- [ ] `module.xml` uses XSD `module-2_2.xsd`
- [ ] `MyModule.php` has `configureServices()` with `load()->autowire()->autoconfigure()`
- [ ] `configureServices()` exclude list uses relative paths (`__DIR__.'/I18n/*'`), not `THELIA_MODULE_DIR`
- [ ] `config.xml` keeps only `<exports>`, `<imports>`, `<parameters>`, and loop aliases
- [ ] `routing.xml` deleted, all routes use `#[Route]` PHP 8 attributes
- [ ] No `@Route` Doctrine annotation
- [ ] `getRoutePrefix()` instead of `getAnnotationRoutePrefix()`
- [ ] `#[AutowireIterator]` / `#[AutowireLocator]` instead of `#[TaggedIterator]` / `#[TaggedLocator]`
- [ ] `Thelia\Core\Install\Database` instead of `Thelia\Install\Database`
- [ ] `BaseHook` + `getSubscribedHooks()` for back-office hooks (no XML declaration)
- [ ] Back-office hook templates are Smarty (`.html` in `templates/backOffice/default/`)
- [ ] Front-office templates are Twig (`.html.twig` in `templates/frontOffice/flexy/`)
- [ ] `{loop}` replaced by `resources('/api/front/...')` in Twig templates
- [ ] No `BaseApiModel`, no `extends BaseAdminOpenApiController`
- [ ] No `ApiPlatform\Api\*` or `ApiPlatform\Exception\*` imports
- [ ] No `openapiContext:` on operations (use `openapi: new Operation(...)`)
- [ ] `module.xml` has no `<module>OpenApi</module>` requirement
- [ ] Propel tinyint setters receive `int` (0/1), not `bool`
- [ ] Propel decimal setters receive `string`, not `float`
- [ ] `declare(strict_types=1)` in every PHP file
- [ ] `final readonly class` on services and DTOs (not controllers)
- [ ] All Symfony interface override methods have native return types
- [ ] Tests use `IntegrationTestCase` / `ApiTestCase` + `FixtureFactory`
- [ ] Fresh install produces zero PHP warnings and zero deprecations
