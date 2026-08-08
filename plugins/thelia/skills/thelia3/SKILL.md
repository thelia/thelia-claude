---
name: thelia3
description: "Thelia 3 e-commerce framework (Symfony 7.4 LTS, API Platform 4.3, PHP 8.3 or later, Propel ORM, Flexy/Twig front, Twig back-office via the default-twig theme). Covers modern module development: configureServices() autoconfigure, API resources (PropelResourceInterface, ResourceAddonInterface), Flexy front (LiveComponents, TwigComponents, resources() / attr() Twig, facades CartFacade/CustomerFacade/OrderFacade/CheckoutFacade), auto-discovered hooks and loops (NO config.xml required for these declarations), front theme hooks (theme_hook() Twig function + ThemeHookInterface), Thelia events, typed modules (AbstractPaymentModule/AbstractDeliveryModule), tests (IntegrationTestCase, ApiTestCase, FixtureFactory). Use when working on Thelia 3 projects, creating modules in local/modules or vendor, building front-office Twig/Flexy with LiveComponents, exposing API resources, extending native resources, migrating from Thelia 2. Triggers on: thelia 3, TheliaKernel, BaseModule, configureServices, BaseHook, theme_hook, ThemeHookInterface, theme hooks, BaseLoop, BaseForm, PropelResourceInterface, ResourceAddonInterface, AbstractTranslatableResource, DataAccessService, resources(), attr(), AsLiveComponent, AsTwigComponent, CartFacade, CustomerFacade, OrderFacade, CheckoutFacade, Flexy, FlexyBundle, AbstractPaymentModule, AbstractDeliveryModule, FixtureFactory, IntegrationTestCase, ApiTestCase, local/modules, vendor/thelia/modules, ApiFilter SearchFilter OrderFilter BooleanFilter RangeFilter NotInFilter DateFilter. Do NOT trigger for Thelia 2 projects (Smarty .html front templates, {loop}, {hook} Smarty syntax)."
---

# Thelia 3 - Module Development Guide

> Stack: Symfony 7.4 LTS, API Platform 4.3, PHP 8.3 or later, Propel ORM. Front in Twig (Flexy, Webpack Encore, Tailwind), back-office in Twig via the default-twig theme. Email and PDF templates are Twig too. No Doctrine, no Messenger, no Turbo/Mercure.

## 0. Install and version constraints

Thelia 3 is installed from tagged releases, not from a development branch:

```bash
composer create-project thelia/thelia-project my-shop
```

While `3.0.0-beta1` is the only tag, add `--stability=beta`, or target the version explicitly:

```bash
composer create-project thelia/thelia-project:^3.0.0-beta1 my-shop
```

Constraints for an existing project:

| Package | Constraint |
|---|---|
| `thelia/core`, `thelia/thelia-project` | `^3.0.0-beta1` |
| Templates (`thelia/flexy`, back-office, email, PDF) | `^1.0.0-beta1` |
| `thelia/*-module` | the module's current major |

The project `composer.json` also needs `"minimum-stability": "beta"` and `"prefer-stable": true` until a stable release is tagged.

`THELIA_VERSION` is `3.0.0-beta1`. The announced PHP matrix is 8.3; 8.4 support is being validated in CI.

## 1. Decision router - "I want to..."

| Goal | Canonical approach | Reference |
|---|---|---|
| Create a module | `local/modules/MyModule/` (takes priority over `vendor/thelia/modules/`) | modules.md |
| Initialize module DI | `MyModule::configureServices()` static + `load()->autowire()->autoconfigure()` | modules.md |
| Declare metadata | `Config/module.xml` (XSD `module-2_2.xsd`) | modules.md |
| Persist a DB schema | `Config/schema.xml` Propel + `Config/TheliaMain.sql` | modules.md |
| Migrate a version | `Config/update/{version}.sql` + override `update()` | modules.md |
| Initialize after activation | `postActivation()` with `is_initialized` guard | modules.md |
| Prefix all module routes | `BaseModule::getRoutePrefix()` (NOT the deprecated `getAnnotationRoutePrefix()`) | modules.md |
| Define a route | PHP 8 `#[Route]` on Controller (auto-scanned by `ModuleAttributeLoader`) | modules.md |
| Expose an API resource | `PropelResourceInterface` + `PropelResourceTrait` | api-integration.md |
| Add i18n to a resource | `extends AbstractTranslatableResource` + `getI18nResourceClass()` | api-integration.md |
| Extend a native resource | `ResourceAddonInterface` + `ResourceAddonTrait` (auto-tagged) | api-integration.md |
| Filter an API collection | `#[ApiFilter]` with Thelia filter classes (`SearchFilter`, `OrderFilter`...) | api-integration.md |
| Secure an admin operation | path `/api/admin/*` (auto `ROLE_ADMIN`) + `security:` expression | api-integration.md |
| Secure a front authenticated operation | path `/api/front/account/*` (auto `ROLE_CUSTOMER`) | api-integration.md |
| Customize a query | `QueryCollectionExtensionInterface` (auto-tagged) | api-integration.md |
| Fetch data in Twig | `resources('/api/front/...')` | front-office.md |
| Read a contextual attribute | `attr('cart', '...')`, `attr('customer', '...')` | front-office.md |
| Interactive component (Ajax) | `#[AsLiveComponent]` + `LiveProp` + `LiveAction` | front-office.md |
| Static component | `#[AsTwigComponent]` (pure render) | front-office.md |
| Slider / modal / map JS | Stimulus controller in `assets/controllers/` | front-office.md |
| HTML web form | Thelia `BaseForm` + `validateForm()` + auto CSRF | code-patterns.md |
| Extend an existing form | listen to `TheliaEvents::FORM_AFTER_BUILD.{name}` | code-patterns.md |
| REST API form (modern) | DTO + `#[MapRequestPayload]` + Validator (to adopt) | code-patterns.md |
| Listen to a Thelia event | class + static `EventSubscriberInterface` | hooks.md |
| Back-office hook | `extends BaseHook` + `getSubscribedHooks()` (AUTO-tagged, NO XML) | hooks.md |
| Inject HTML in the front theme | implement `ThemeHookInterface` (AUTO-tagged `thelia.theme_hook`), theme declares points via `theme_hook()` | hooks.md |
| Legacy loop | `extends BaseLoop` (AUTO-tagged, snake_case auto, `@deprecated`) | hooks.md |
| Propel query or third-party API call in a controller/listener/component | NEVER inline - always via Repository / ApiClient with business-named methods | code-patterns.md §9 |
| Manipulate the cart | inject `CartFacade` (NOT `CartItemService`) | front-office.md |
| Handle checkout/payment | `CheckoutFacade::pay()`, `validateForOrder()` | front-office.md |
| Customer login/logout | `CustomerFacade::login()` / `logout()` | front-office.md |
| CLI command | `#[AsCommand]` + `extends ContainerAwareCommand` | code-patterns.md |
| Payment module | `extends AbstractPaymentModule` + `pay(Order)` + `isValidPayment()` | payment-delivery.md |
| Delivery module | `extends AbstractDeliveryModule` + `getPostage(Country)` | payment-delivery.md |
| Test a service | `extends IntegrationTestCase` + `createFixtureFactory()` | testing.md |
| Test an Action listener | `extends ActionIntegrationTestCase` + `dispatch()` | testing.md |
| Test an API endpoint | `extends ApiTestCase` + JWT login + `jsonRequest()` | testing.md |
| i18n DB data | Propel `i18n` behavior + `setLocale()->getTitle()` | modules.md |
| i18n UI strings | `MyModule/I18n/{locale}.php` + `Translator::trans('msg', [], 'mymodule')` | modules.md |
| Override a theme template | place in `{module}/templates/frontOffice/flexy/` | front-office.md |
| Compile assets | Webpack Encore (`npm run build`) - NOT Vite | front-office.md |
| Distribute via Composer | `"type": "thelia-module"` + `thelia/installer` + `extra.installer-name` | modules.md |
| Migrate a T2 module | see the dedicated guide | See thelia3-module-migration skill |

## 2. Modern Thelia 3 module skeleton

```
local/modules/MyModule/
+- Config/
|  +- module.xml             # REQUIRED - XSD module-2_2.xsd
|  +- schema.xml             # REQUIRED if DB tables
|  +- TheliaMain.sql         # Initial SQL (postActivation)
|  +- update/                # Versioned *.sql files (1.0.1.sql, 1.1.0.sql...)
|  +- config.xml             # OPTIONAL - exports/imports/parameters/loop aliases only
+- Controller/               # PHP 8 #[Route] - auto-scanned by ModuleAttributeLoader
+- Api/Resource/             # Auto-discovered via configureServices() + uriTemplate
+- Form/                     # extends BaseForm -> auto-tag thelia.form
+- EventListener/            # EventSubscriberInterface - auto-tagged by SF
+- Hook/                     # extends BaseHook -> auto-tag hook.event_listener
+- Loop/                     # extends BaseLoop -> auto-tag thelia.loop (deprecated)
+- I18n/                     # fr_FR.php, en_US.php
+- templates/
|  +- backOffice/default-twig/ # Twig (.html.twig) - back-office hooks
|  +- frontOffice/flexy/     # Twig overrides (.html.twig)
+- MyModule.php              # extends BaseModule + configureServices()
```

```php
<?php
declare(strict_types=1);

namespace MyModule;

use Propel\Runtime\Connection\ConnectionInterface;
use Symfony\Component\DependencyInjection\Loader\Configurator\ServicesConfigurator;
use Symfony\Component\Finder\Finder;
use Thelia\Core\Install\Database;
use Thelia\Module\BaseModule;

final class MyModule extends BaseModule
{
    public const DOMAIN_NAME = 'mymodule';

    public static function configureServices(ServicesConfigurator $services): void
    {
        $services->load(self::getModuleCode().'\\', __DIR__)
            ->exclude([__DIR__.'/I18n/*', __DIR__.'/Config/**/*.php', __DIR__.'/Tests/*', __DIR__.'/MyModule.php'])
            ->autowire()
            ->autoconfigure();
    }

    public function postActivation(?ConnectionInterface $con = null): void
    {
        if (!self::getConfigValue('is_initialized', false)) {
            (new Database($con))->insertSql(null, [__DIR__.'/Config/TheliaMain.sql']);
            self::setConfigValue('is_initialized', true);
        }
    }

    public function update($currentVersion, $newVersion, ?ConnectionInterface $con = null): void
    {
        $finder = Finder::create()->name('*.sql')->depth(0)->sortByName()->in(__DIR__.'/Config/update');
        $database = new Database($con);
        foreach ($finder as $file) {
            if (version_compare($currentVersion, $file->getBasename('.sql'), '<')) {
                $database->insertSql(null, [$file->getPathname()]);
            }
        }
    }
}
```

## 3. Core capabilities (summary)

### 3.1 Lifecycle and DI
- `configureServices()` static is **REQUIRED** in the Module class: without it, zero classes are scanned (auto-registration was reverted).
- `module.xml` minimal (metadata + `<fullnamespace>`).
- `config.xml`: OPTIONAL - only if `<exports>`, `<imports>`, `<parameters>`, or a `<loop name="alias">` that differs from the auto snake_case name.
- `local/modules/` takes PRIORITY over `vendor/thelia/modules/`.
- Single source of truth at boot: `ModuleQuery::getActivated()`. A module present on the filesystem but absent from the DB is invisible.
- Details: [references/modules.md](references/modules.md)

### 3.2 API Platform 4.3 and DataAccessService
- Resource = implements `PropelResourceInterface` + use `PropelResourceTrait` (or `extends AbstractTranslatableResource` for i18n).
- Extend a native resource without forking = `ResourceAddonInterface` + `ResourceAddonTrait`.
- Filters = `#[ApiFilter]` with Thelia classes (NOT native AP `QueryParameter`, which couples to Doctrine).
- DAS `resources()`: bypasses AP internally (but requires an active HTTP Request, NOT usable in CLI).
- Admin/front operations separated via `uriTemplate: '/admin/...'` or `/front/...` + groups.
- Details: [references/api-integration.md](references/api-integration.md)

### 3.3 Flexy front and Symfony UX
- `#[AsLiveComponent]` (interactive Ajax) or `#[AsTwigComponent]` (static).
- Twig: `resources('/api/front/...')`, `attr('product', 'id')`, `getForm(name)`, `hook(name)`, `theme_hook(name, params)`, `path(routeId)`.
- Facades in LiveComponents: `CartFacade`, `CustomerFacade`, `OrderFacade`, `CheckoutFacade`.
- Template overrides: place in `{module}/templates/frontOffice/flexy/`.
- Assets: Webpack Encore + Tailwind. Turbo/Mercure are ABSENT.
- Details: [references/front-office.md](references/front-office.md)

### 3.4 Events and back-office extensions
- Listeners: `EventSubscriberInterface` (dominant in core) or `#[AsEventListener]` (to adopt when appropriate).
- Back-office hooks: `extends BaseHook` + `getSubscribedHooks()` -> **AUTO-tagged, NO `<hooks>` declaration required**.
- Front theme hooks: implement `ThemeHookInterface` -> AUTO-tagged `thelia.theme_hook`; the theme declares its points with `theme_hook('page.zone.position')` (Flexy: 20 points, primary use SEO/analytics). Pure code, no DB, no admin.
- Legacy loops: `extends BaseLoop` -> AUTO-tagged, snake_case auto. `BaseLoop` is `@deprecated` - prefer API Resources.
- Back-office hook templates are Twig in the default-twig theme. See the `thelia3-backoffice-twig` skill for back-office theming, hooks, i18n, and forms.
- Details: [references/hooks.md](references/hooks.md)

### 3.5 Forms
- Web HTML: Thelia `BaseForm` (CSRF + Twig error ParserContext built in).
- REST API: DTO + `#[MapRequestPayload]` + Validator (to push as the modern approach, not yet adopted in core).
- Extending an existing form: listen to `TheliaEvents::FORM_AFTER_BUILD.{name}`.
- Details: [references/code-patterns.md](references/code-patterns.md)

### 3.6 Tests
- `IntegrationTestCase` (kernel + Propel rollback), `WebIntegrationTestCase` (KernelBrowser), `ApiTestCase` (JWT + JSON-LD), `ActionIntegrationTestCase` (Action listeners). The `FixtureFactory` provides fixture methods covering entities, orders, and carts.
- Isolated test DB via `.env.test` `DATABASE_NAME=test`. `bin/test-prepare` clears `var/propel/test/`.
- Details: [references/testing.md](references/testing.md)

### 3.7 Typed modules
- Payment: `extends AbstractPaymentModule` -> `pay(Order)`, `isValidPayment()`.
- Delivery: `extends AbstractDeliveryModule` (or `WithState`) -> `getPostage(Country)`, `isValidDelivery(Country)`.
- Details: [references/payment-delivery.md](references/payment-delivery.md)

## 4. Deprecated patterns - BLOCK THESE

| Pattern | Why | Replacement |
|---|---|---|
| `<hooks>` in `config.xml` | autoconfigure from `BaseHookInterface` | `extends BaseHook` + `getSubscribedHooks()` |
| `<loops>` in `config.xml` (except aliases) | autoconfigure from `LoopInterface` (auto snake_case) | `extends BaseLoop` (alias only in XML) |
| `<forms>` in `config.xml` | autoconfigure from `FormInterface` (`getName()`) | `extends BaseForm` + `static getName()` |
| `<services>` business services in `config.xml` | duplicates `configureServices()` | `configureServices()` `load()->autowire()->autoconfigure()` |
| Module `routing.xml` | `ModuleAttributeLoader` scans `Controller/` | PHP 8 `#[Route]` on controllers |
| `@Route` Doctrine annotations | removed in Symfony 7 | `#[Route]` |
| `getAnnotationRoutePrefix()` | `@deprecated BaseModule` | `getRoutePrefix()` |
| `#[TaggedIterator]` / `#[TaggedLocator]` | deprecated SF 7.1 | `#[AutowireIterator]` / `#[AutowireLocator]` |
| `DataAccessService::loop()` / `loopCount()` | `@deprecated` | `resources('/api/front/...')` |
| Twig `loop()` / `loopCount()` | same | `resources()` |
| `BaseLoop` extends | `@deprecated` | API Resources (`PropelResourceInterface`) |
| `extends BaseFrontController` in LiveComponent | service locator anti-pattern | explicit constructor injection |
| `final readonly` on Thelia controllers | incompatible with `#[Required]` setters in `BaseController` | follow hierarchy without `readonly` (ok for services and DTOs) |
| `OpenApi @OA\Schema` annotations | T2 residual | API Platform 4.3 attributes (`#[ApiResource]`) |
| `BaseApiModel` | T2 residual | `PropelResourceInterface` + `PropelResourceTrait` |
| `setRequest()` setter in services | service locator | constructor injection |
| `Thelia\Install\Database` (without `\Core`) | legacy namespace | `Thelia\Core\Install\Database` |
| `new Database($con->getWrappedConnection())` | constructor accepts `ConnectionInterface` | `new Database($con)` |
| `ContainerAwareInterface` (services, outside commands) | deprecated | explicit injection |
| `ORDER_SET_POSTAGE` event | deprecated | `CART_SET_POSTAGE` |
| `#[Ignore]` on a `static` method | crashes Serializer | never on static |
| `<commands>` in `config.xml` | autoconfigure `console.command` / `thelia.command` | autoconfigure |
| `ApiPlatform\Api\*` (`IriConverterInterface`, `UrlGeneratorInterface`...) | namespace removed in AP 4 (no alias - fatal at boot) | `ApiPlatform\Metadata\*` |
| `ApiPlatform\Exception\*` | namespace removed in AP 4 | `ApiPlatform\Metadata\Exception\*` |
| `openapiContext:` on an **operation** (`Get`, `Post`...) | removed in AP 4 | `openapi: new Operation(...)` (still supported on `#[ApiProperty]`) |

## 5. Critical traps (security / reliability)

| Trap | Cause | Fix |
|---|---|---|
| `Translator::$instance` non-null in test | singleton state leak | `?self = null` |
| `URL::$instance` non-null in test | same | same |
| `#[Ignore]` on a `static` method | crashes Serializer | never on static |
| `resources()` in CLI | `RequestBuilderService` `RuntimeException` if `getMainRequest()` is null | guard / fallback / avoid in CLI |
| `attr()` in CLI | `AttributeAccessService::getRequest()` `RuntimeException` | same |
| `PropelPersistProcessor` write in CLI | `requestStack->getMainRequest()->getContent()` null | do not write API in CLI |
| Propel test cache pointing to wrong DB | stale DSN cache | `bin/test-prepare` clears `var/propel/test/` |
| `/api/front/**` routes public by default | `access_control` covers only `/account/` | explicit `security:` on operation |
| `local/modules` silently overrides `vendor/thelia/modules` | `getModuleDir()` priority | use distinct names |
| LiveProp with Propel objects | not serializable | use simple DTOs or arrays |
| `getRequest()` from `BaseModule` in CLI | `RuntimeException` | guard `$container->has('request_stack')` |
| `active-front-template` = non-existent directory | FlexyBundle crashes at boot | always a valid `flexy` value |
| `postActivation()` throws exception | transaction rollback + module re-deactivated | idempotent `is_initialized` guard |
| `getModuleCode()` != first FQCN segment | `RegisterHookListenersPass` `explode('\\')[0]` does not match DB | folder = class = FQCN root |
| `getPropelRelatedTableMap()` returns null | `PropelCollectionProvider` NPE | always `new XxxTableMap()` on concrete resource |
| `getCartFromSession()` can be null | no session cart | `getOrCreateFromSession()` for writes |
| `Translator::getInstance()` not initialized in tests/CLI | `RuntimeException` singleton | inject `TranslatorInterface` |
| `SecurityContext::getSession()` in CLI | `requestStack->getMainRequest()->getSession()` null | push Request manually or use `IntegrationTestCase` |
| `getComponent()` Stimulus without `await` | async hydration | always `await getComponent(this.element)` |
| Stale `module_template_dirs.php` cache | not invalidated outside `module:post-activate-all` | `cache:clear` after activation |
| Missing `templates-assets/{theme}/dist` symlink | first boot | ensure `THELIA_WEB_DIR/templates-assets/` is writable |
| Propel `TINYINT` setter (`setVisible(true)`...) | column typed `?int`, `strict_types` rejects `bool` | pass `0`/`1` (DECIMAL = `?string`, never `float`) |
| `trans('X')` PHP without domain gives unexpected French text | injected `TranslatorInterface` = **`core`** domain (Twig `\|trans` = `messages` domain); missing key returns raw string | specify module domain (`trans('X', [], 'mymodule')`) |
| `Lang::getDefaultLanguage()` mistaken for current locale | = store default language (often `en_US`) | `$request->getLocale()` for the UI locale |
| `$request->getSession()` without a session | `SessionNotFoundException` (error page, CLI, test) | guard `$request?->hasSession()` |
| `.env.test` ignored in DDEV, wiping dev DB | `web_environment` injects `DATABASE_*` into shell, `Dotenv` does not override (`override=false`) | `env -u DATABASE_*` / `unset()` before `bootEnv` |
| `ConfigQuery::read()` returns stale value | PSR `thelia_config` cache not invalidated by direct SQL UPDATE | `ConfigQuery::write()` or `initCacheConfigs(true)`; `php Thelia cache:clear` |
| `SecurityContext::isGranted([A, B], ...)` | combines resources in **AND** | for OR, iterate resource by resource |
| `_or()` Propel | switches **the entire WHERE** to OR | `condition()` + `combine([...], 'OR')` |

## 6. Symfony-native evolution candidates

When working on a module, these patterns are more modern but not yet standard Thelia. Use them when the context allows:

- Listeners: `EventSubscriberInterface` -> `#[AsEventListener]` SF 7.4
- Console: `ContainerAwareCommand::execute()` -> invokable command SF 7.4 + `#[Argument]`/`#[Option]`
- API forms: DTO + `#[MapRequestPayload]` + Validator (zero core usage)
- Async: Messenger ABSENT - strong candidate for native async (email, stock recalculation, PDF)
- DTO mapping: manual transformations -> `ObjectMapper` SF 7.3
- Web security: Thelia `SecurityContext` + `checkAuth()` -> Symfony Voters + `#[IsGranted]` (Propel profile integration to design)
- AP serialization perf: `JsonStreamer` SF 7.3 on large collections
- Bundler: Webpack Encore -> Vite (current ecosystem)
- Front interactivity: LiveComponents only -> Turbo Drive + Streams + Mercure (real-time)

## 7. Essential vocabulary

- `BaseModule` - parent module class; `BaseModuleInterface` install/update/destroy/activate/deactivate/getHooks contract
- `configureServices(ServicesConfigurator)` - module DI entry point (REQUIRED)
- `ModuleQuery::getActivated()` - single source of active modules at boot
- `Database` - `Thelia\Core\Install\Database` PDO wrapper (`insertSql()`)
- `module.xml` - XSD `module-2_2.xsd`; `config.xml` - optional legacy
- `PropelResourceInterface` / `PropelResourceTrait` - base API resource
- `AbstractTranslatableResource` / `TranslatableResourceInterface` / `I18nCollection` - i18n API
- `ResourceAddonInterface` / `ResourceAddonTrait` - native resource extension (auto-tagged)
- `PropelCollectionProvider` / `PropelItemProvider` / `PropelPersistProcessor` / `PropelRemoveProcessor` - built-in providers/processors
- `EagerLoadingExtension` / `FilterExtension` / `ResourceAddonExtension` / `PaginationExtension` - Propel bridge extensions
- `QueryCollectionExtensionInterface` / `QueryItemExtensionInterface` - custom query extensions
- `SearchFilter` / `OrderFilter` / `BooleanFilter` / `RangeFilter` / `NotInFilter` / `DateFilter` - Thelia filters (`#[ApiFilter]`)
- `#[Relation]` / `#[Column]` / `#[CompositeIdentifiers]` - Propel bridge attributes
- `DataAccessService::resources()` / `AttributeAccessService::attribute*()` - internal AP bypass + contextual attributes
- `FlexyBundle`; Twig namespaces `@components`, `@UiComponents`, `@assets`, `@formTwig`, `@{Module}Module`
- `AsLiveComponent` / `AsTwigComponent`; `LiveProp` / `LiveAction` / `LiveListener` / `LiveArg` / `PreMount` / `PostMount` / `ExposeInTemplate`
- `ComponentToolsTrait` (`emit`, `dispatchBrowserEvent`); `ComponentWithFormTrait` (`instantiateForm`, `submitForm`); `DefaultActionTrait`
- `CartFacade`, `CustomerFacade`, `CheckoutFacade`, `OrderFacade` - domain facades
- `BaseController`, `BaseAdminController`, `BaseFrontController` - controllers (NOT `final readonly`)
- `BaseAction`, `TheliaEvents` - listeners and event constants
- `BaseForm`, `FirewallForm`, `BruteforceForm`, `TheliaFormFactory`, `TheliaFormValidator`
- `SecurityContext`, `AccessManager`, `AdminResources` - Thelia security (NOT SF Security); `isGranted` combines resources in AND
- `Tools\TokenProvider` - CSRF for GET links/actions (`assignToken()` stable per session, `checkToken()`, `refreshToken()`)
- `Thelia\Core\Translation\Translator` - alias of `TranslatorInterface`, default domain `core`, fallback = raw key; distinct from Symfony `translator` (Twig `|trans`, domain `messages`)
- `Lang::getDefaultLanguage()` - store default language (not equal to `$request->getLocale()`)
- `BaseHook` / `BaseHookInterface` / `getSubscribedHooks()` - back-office hooks auto-tagged
- `ThemeHookInterface` / tag `thelia.theme_hook` / Twig `theme_hook()` - front theme hooks auto-tagged (renderer in TwigEngine)
- `RegisterHookListenersPass` / `LoopCompilerPass` / `RegisterFormPass` - auto-discovery passes
- `router.admin` / `router.front` / `ModuleAttributeLoader` / `RewritingRouter` - chain routers
- `IntegrationTestCase` / `WebIntegrationTestCase` / `ApiTestCase` / `ActionIntegrationTestCase` / `FixtureFactory`
- `AbstractPaymentModule` / `PaymentModuleInterface`; `AbstractDeliveryModule` / `AbstractDeliveryModuleWithState` / `DeliveryModuleInterface`

## Deep-dive references

- [references/modules.md](references/modules.md) - Skeleton, configureServices, lifecycle, Propel persistence, i18n, Composer distribution
- [references/api-integration.md](references/api-integration.md) - AP 4.3, resources, addons, filters, security, DAS, providers/processors
- [references/front-office.md](references/front-office.md) - Flexy, LiveComponents, TwigComponents, Stimulus, facades, assets, template overrides
- [references/hooks.md](references/hooks.md) - Thelia events, listeners, back-office hooks auto-tagged, front theme hooks (`theme_hook()`), loops auto-tagged
- [references/code-patterns.md](references/code-patterns.md) - Forms (BaseForm + API DTO), `#[AsCommand]` commands, services
- [references/testing.md](references/testing.md) - Test strategy + FixtureFactory + ApiTestCase
- [references/payment-delivery.md](references/payment-delivery.md) - Typed payment / delivery modules
- [references/glossary.md](references/glossary.md) - Complete vocabulary by cluster

For migrating a Thelia 2 module to Thelia 3, see the thelia3-module-migration skill.
