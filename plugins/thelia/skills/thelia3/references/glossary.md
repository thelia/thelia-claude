# Thelia 3 Vocabulary - Complete Glossary

> Exhaustive reference of classes, interfaces, services, attributes, Twig functions, and constants used in Thelia 3 module development (SF 7.4 LTS, AP 4.3, PHP 8.3 or later).

## Module lifecycle

| Symbol | Description |
|---|---|
| `BaseModule` | Module parent class (`extends BaseModule`) |
| `BaseModuleInterface` | install/update/destroy/activate/deactivate/getHooks contract |
| `configureServices(ServicesConfigurator)` | Module DI entry point (REQUIRED) |
| `loadConfiguration(ContainerBuilder)` | Low-level hook before `config.xml` |
| `getCompilers(): array` | Additional compiler passes |
| `ModuleManagement` | Orchestrates install/update/activate |
| `ModuleQuery::getActivated()` | Single source of active modules at boot |
| `ModuleAttributeLoader` | Scans `Controller/` for `#[Route]` |
| `THELIA_MODULE_DIR` | Constant = `vendor/thelia/modules/` |
| `THELIA_LOCAL_MODULE_DIR` | Constant = `local/modules/` (takes priority) |
| `Database` | `Thelia\Core\Install\Database` - PDO wrapper (`insertSql()`) |
| `module.xml` | Metadata, XSD `module-2_2.xsd` |
| `config.xml` | Optional legacy (exports/imports/parameters/loop aliases) |
| `schema.xml` | Propel schema merged by `SchemaLocator` |
| `TheliaEvents::MODULE_TOGGLE_ACTIVATION` | Module activation event |
| `module:refresh` / `module:activate` / `module:post-activate-all` | Lifecycle CLI commands |

## API Platform and Propel bridge

| Symbol | Description |
|---|---|
| `PropelResourceInterface` | API resource interface (7 methods) |
| `PropelResourceTrait` | Default implementation except `getPropelRelatedTableMap()` |
| `AbstractTranslatableResource` | i18n base (`I18nCollection $i18ns`) |
| `TranslatableResourceInterface` | i18n contract (`getI18ns/setI18ns/addI18n/getI18nResourceClass`) |
| `I18nCollection` | Container indexed by locale (`'fr_FR' => I18n`) |
| `ResourceAddonInterface` | Extends a native resource (auto-tagged `thelia.api.resource.addon`) |
| `ResourceAddonTrait` | Default addon implementation |
| `PropelCollectionProvider` | Built-in provider for `GetCollection` |
| `PropelItemProvider` | Built-in provider for `Get/Put/Patch` |
| `PropelPersistProcessor` | Built-in processor for `Post/Put/Patch` |
| `PropelRemoveProcessor` | Built-in processor for `Delete` |
| `EagerLoadingExtension` | Auto JOIN for `#[Relation]` |
| `FilterExtension` | Applies Thelia `#[ApiFilter]` |
| `ResourceAddonExtension` | JOINs addon tables |
| `PaginationExtension` | AP pagination |
| `QueryCollectionExtensionInterface` / `QueryItemExtensionInterface` | Custom auto-tagged query extensions |
| `FilterInterface` | Thelia filter interface (extends AP `BaseFilterInterface`) |
| `SearchFilter` | `?prop=val` with strategies `exact/partial/start/end/word_start` |
| `OrderFilter` | `?order[prop]=asc\|desc` |
| `BooleanFilter` | `?prop=true\|false` |
| `RangeFilter` | `?prop[gt\|gte\|lt\|lte]=v` |
| `NotInFilter` | `?not_in[prop]=["v1","v2"]` |
| `DateFilter` | `?prop[before\|after\|strictly_before\|strictly_after]=date` |
| `#[Relation]` | Propel bridge attribute (relation -> auto JOIN) |
| `#[Column]` | Override Propel column mapping |
| `#[CompositeIdentifiers]` | Composite primary keys |
| `#[ApiResource]` | API Platform (uriTemplate, operations, groups) |
| `#[ApiFilter]` | Declares a Thelia filter |
| `ApiResourcePropelTransformerService` | Propel <-> Resource mapping |
| `MetadataService::canUserAccessResource()` | Operation security check |
| `JwtDecorator` | OpenAPI JWT login decorator |

## Data Access

| Symbol | Description |
|---|---|
| `DataAccessService::resources(path, params, format)` | Internal AP bypass |
| `AttributeAccessService::attribute*()` | Contextual attributes (`Cart`, `Customer`, `Product`...) |
| `ResourceService` | Internal `resources()` orchestrator |
| `RequestBuilderService` | Builds synthetic Request |
| `RouteMatcherService` | Matches AP route |
| `OperationProviderService` | Retrieves `Operation` |
| `ContextBuilderService` | Builds context (filters, groups) |
| `DataProviderService::fetchData()` | Runs provider |
| `AccessCheckerService::checkUserAccess()` | Checks `security:` ExpressionLanguage |
| `NormalizerService::normalizeData()` | Serializes according to groups |

## Flexy front

| Symbol | Description |
|---|---|
| `FlexyBundle` | SF bundle for the active theme |
| `active-front-template` | DB key for the current theme |
| `%thelia_front_template%` | SF parameter for the active theme |
| `@Flexy` | Twig namespace - `templates/frontOffice/{theme}/components/` |
| `@FlexyForm` | Twig namespace - `templates/frontOffice/{theme}/form/` |
| `@{Module}Module` | Twig namespace for module templates |
| `FlexyBundle\Components\` | PSR-4 root on the theme's `components/`; TwigComponent `name_prefix` is empty |
| `flexy_form_themes` | Twig global listing the Flexy form theme; opt in with `{% form_theme form with flexy_form_themes only %}` |
| `ViewController` | Theme-owned front catch-all `/{_view}`, route `flexy_view`, delegates to `DefaultController::noAction()` |
| `ComponentContextExtension` | Supplies `provide()` / `inject()` on PHP 8.3, where ux-twig-component resolves to 2.x |
| `config/views.yaml` | Theme file declaring internal views (root templates that are not pages) |
| `InternalViewsDeclaration` | Reads `config/views.yaml`; `ViewRenderer` 404s a request naming an internal view |
| `importmap.php` | AssetMapper entrypoints and vendor packages (replaces Webpack Encore) |
| `ignore_thelia_view` | Route default opting a route out of themed view rendering, the admin firewall check and the themed error page (`/_components` needs it) |
| `#[AsLiveComponent]` | Interactive Ajax component |
| `#[AsTwigComponent]` | Static component |
| `#[LiveProp]` | LiveComponent property (writable, url, etc.) |
| `#[LiveAction]` | Action invokable from the client side |
| `#[LiveListener]` | Listens to a LiveComponent event |
| `#[LiveArg]` | LiveComponent action argument |
| `#[ExposeInTemplate]` | Exposes a private property to the template |
| `#[PreMount]` / `#[PostMount]` | TwigComponent lifecycle hooks |
| `ComponentToolsTrait` | `emit()` / `dispatchBrowserEvent()` |
| `ComponentWithFormTrait` | `instantiateForm()` / `submitForm()` / `getForm()` |
| `DefaultActionTrait` | Default LiveComponent handler |
| `TwigParser` | Twig `ParserInterface` (tag `thelia.parser.template`) |
| `DataAccessExtension` | Twig functions `resources()`, `attr()`, `loop()` (deprecated) |
| `FlexyBundleExtension` | Twig functions `attributeAv()`, `getCurrentCustomer()` |
| `FormExtension` | Twig `getForm(name, data)` |
| `HookExtension` | Twig `hook(name, params)` |
| `URLExtension` | Twig `path(routeId, params)` |
| `SecurityExtension` | Twig `isAuthenticated*()`, `assertAuth*()` |
| `SvgExtension` | Twig `svg(filename)` |

## Domain (Facades)

| Symbol | Description |
|---|---|
| `CartFacade` | Cart mutations (`addItem`, `removeItem`, `updateItemQuantity`, `getOrCreateFromSession`) |
| `CustomerFacade` | Auth + customer CRUD (`login`, `logout`, `register`, `getCurrentCustomer`) |
| `CheckoutFacade` | Checkout selections + payment (`pay`, `validateForOrder`, `selectDeliveryAddress`) |
| `OrderFacade` | Low-level, internal - do not inject in modules |
| `CartItemAddDTO` / `CartItemDeleteDTO` / `CartItemUpdateQuantityDTO` | Cart DTOs |
| `CheckoutDTO` | Checkout selection DTO |
| `CustomerLogin` / `CustomerRegisterDTO` | Auth DTOs |

## Symfony / Thelia backbone

| Symbol | Description |
|---|---|
| `BaseController` | Abstract, `#[Required]` setters - do NOT `final readonly` |
| `BaseAdminController` | Admin controller (`checkAuth()`, `render()`) |
| `BaseFrontController` | Front controller |
| `BaseAction` | Action listener base |
| `TheliaEvents` | `final class` event constants (NOT an enum) |
| `TheliaEvents::getModuleEvent(name, code)` | Builds `'thelia.module.xxx.code'` |
| `BaseForm` | Thelia form (CSRF + ParserContext + static `getName()`) |
| `FirewallForm` | `BaseForm` + rate-limit |
| `BruteforceForm` | `FirewallForm` + brute-force protection |
| `TheliaFormFactory` | Form creation service |
| `TheliaFormValidator` | Form validation service |
| `FormService` (TwigEngine) | `getFormByName(name)` |
| `SecurityContext` | Thelia security (NOT SF Security) - admin/customer in Propel session |
| `AccessManager` | Constants `VIEW`, `CREATE`, `UPDATE`, `DELETE` |
| `AdminResources` | Admin resource constants (`CATEGORY`, `PRODUCT`, `MODULE`...) |
| `ContainerAwareCommand` | Thelia command base (`getContainer()`, `getDispatcher()`, `initRequest()`) |

## Hooks / Loops back-office

| Symbol | Description |
|---|---|
| `BaseHook` | Back-office hook base (Twig templates) |
| `BaseHookInterface` | Auto-tagged `hook.event_listener` |
| `getSubscribedHooks(): array` | Auto hook declaration (static) |
| `HookRenderEvent` | Hook event - `add(html)`, `addTemplate()`, `addJS()`, `addCSS()` |
| `BaseLoop` | Legacy `{loop type=...}` data source. Prefer `resources()`. |
| `LoopInterface` | Auto-tagged `thelia.loop` |
| `PropelSearchLoopInterface` | Loop with Propel query |
| `LoopResult` / `LoopResultRow` | Loop results |
| `RegisterHookListenersPass` | Hook auto-discovery compiler pass |
| `LoopCompilerPass` | Loop auto-discovery compiler pass (snake_case) |
| `RegisterFormPass` | Form auto-discovery compiler pass |
| `RegisterApiResourceAddonPass` | Addon collection by parent compiler pass |
| `RegisterCommandPass` | Command compiler pass |

## Routing

| Symbol | Description |
|---|---|
| `router.admin` | Admin router (`admin.xml`, prio 0) |
| `router.front` | Front router (`front.xml` from Front module, prio 128) |
| `ModuleAttributeLoader` | Scans `Controller/` for `#[Route]` (prio 254) |
| `RewritingRouter` | SEO URLs + locale resolution |
| `getRoutePrefix(): string` | Override module route prefix |
| `getAnnotationRoutePrefix()` | `@deprecated` |

## Tests

| Symbol | Description |
|---|---|
| `IntegrationTestCase` | Kernel + Propel rollback + fixtures |
| `WebIntegrationTestCase` | KernelBrowser + shared transaction |
| `ApiTestCase` | JWT login + `jsonRequest()` + JSON-LD assertions |
| `ActionIntegrationTestCase` | Action listener tests (`dispatch()`) |
| `FixtureFactory` | Fixture methods for entities, orders, carts, and more |
| `AssertsJsonApi` | JSON-LD API assertions |
| `LogsInAsAdmin` / `LogsInAsCustomer` | JWT login helpers |
| `bin/test-prepare` | Creates test DB + applies schema + JWT keys |
| `var/propel/test/` | Propel test cache (clear if DSN changes) |

## Typed modules

| Symbol | Description |
|---|---|
| `AbstractPaymentModule` | Payment base |
| `PaymentModuleInterface` | Contract (`pay`, `isValidPayment`, `manageStockOnCreation`) |
| `PAYMENT_MODULE_TYPE = 3` | Module type constant |
| `AbstractDeliveryModule` | Delivery base |
| `AbstractDeliveryModuleWithState` | Variant with states/regions |
| `DeliveryModuleInterface` | Contract (`getPostage`, `isValidDelivery`, `handleVirtualProductDelivery`) |
| `DELIVERY_MODULE_TYPE = 2` | Module type constant |
| `OrderPostage` | `getPostage()` result object |
| `Area` | Delivery geo zone |

## Security

| Symbol | Description |
|---|---|
| `SecurityContext::isGranted(roles, resources, modules, accesses)` | Checks admin DB profiles - resources/accesses combined in **AND** (for OR: iterate) |
| `Tools\TokenProvider` | CSRF for GET links/actions: `assignToken()` (stable per session), `checkToken()`, `refreshToken()` |
| `BaseAdminController::checkAuth()` | Admin guard pattern |
| `Lexik JWT 3.2` | Token-based API auth - `JWT_TOKEN_TTL` (default 3600s) + refresh flow `/api/{front,admin}/token/refresh` (`JWT_REFRESH_TOKEN_TTL` default 30 days) |
| `RefreshTokenService` | Cache-backed single-use refresh token storage (admin/customer scoped) |
| `access_control` | Injected by Reflection on `extensionConfigs` (`TheliaKernel:107-115`) |
| `security:` ExpressionLanguage | On `#[ApiResource]` operation |

## Constants and context

| Symbol | Description |
|---|---|
| `THELIA_ROOT` | Thelia root |
| `THELIA_LIB` | `core/lib/` |
| `THELIA_WEB_DIR` | Public directory (`web/` or `public/`) |
| `THELIA_TEMPLATE_DIR` | `templates/` |
| `THELIA_VERSION` | `'3.0.0'` (`TheliaKernel::THELIA_VERSION`) |
| `Translator::getInstance()` | Singleton - prefer injected `TranslatorInterface` |
| `Thelia\Core\Translation\Translator` | Alias of injected `TranslatorInterface`; default domain **`core`**; missing key -> raw string (`strtr`). Distinct from Symfony `translator` service (Twig `\|trans`, domain `messages`) |
| `URL::getInstance()` | Singleton - same |
| `Lang::getDefaultLanguage()` | Store default language (not equal to `$request->getLocale()`) |
| `LangService::getLocale()` | Current locale |
| `Propel::getConnection('TheliaMain')` | DB connection |

## Thelia events (top constants)

| Constant | Use |
|---|---|
| `TheliaEvents::CART_ADDITEM` / `AFTER_CARTADDITEM` | Cart add |
| `TheliaEvents::CART_UPDATEITEM` / `CART_DELETEITEM` | Cart update / delete |
| `TheliaEvents::CART_SET_DELIVERY_MODULE` / `CART_SET_PAYMENT_MODULE` | Carrier / payment selection |
| `TheliaEvents::ORDER_PAY` / `ORDER_BEFORE_PAYMENT` | Payment |
| `TheliaEvents::ORDER_UPDATE_STATUS` / `ORDER_SEND_CONFIRMATION_EMAIL` | Order cycle |
| `TheliaEvents::ORDER_BEFORE_CREATE` / `ORDER_AFTER_CREATE` | Order creation |
| `TheliaEvents::CUSTOMER_CREATEACCOUNT` / `CUSTOMER_LOGIN` / `CUSTOMER_LOGOUT` | Customer lifecycle |
| `TheliaEvents::PRODUCT_CREATE` / `PRODUCT_UPDATE` | Catalog CRUD |
| `TheliaEvents::FORM_AFTER_BUILD` / `FORM_BEFORE_BUILD` | Form extension |
| `TheliaEvents::MODULE_TOGGLE_ACTIVATION` | Module activation |
| `TheliaEvents::CART_SET_POSTAGE` | Postage (replaces deprecated `ORDER_SET_POSTAGE`) |
| `TheliaEvents::CUSTOMER_PERSONAL_DATA_EXPORT` / `CUSTOMER_ANONYMIZE` | Customer data export / anonymization; modules answer via `CustomerPersonalDataProviderInterface` |
| `TheliaEvents::VIRTUAL_PRODUCT_ORDER_DOWNLOAD_RESPONSE` | Virtual product file download; the delivery module supplies the response |
