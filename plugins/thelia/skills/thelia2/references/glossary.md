# Thelia 2.6: Glossary

> ~80 entries: term, short definition, code ref.

## Modules

| Term | Definition | Ref |
|---|---|---|
| `BaseModule` | Root abstract module class, implements `BaseModuleInterface`, `ContainerAwareTrait` | `BaseModule.php:50` |
| `BaseModuleInterface` | Full lifecycle contract | `BaseModuleInterface.php` |
| `THELIA_MODULE_DIR` | `local/modules/`, the only scanned directory | const |
| `module.xml` | Module XML descriptor (XSD `module-2_2.xsd`) | `Module/schema/module/` |
| `config.xml` | Module DI (XSD `thelia-1.0.xsd`), required even if empty | `DependencyInjection/Loader/schema/dic/config/` |
| `schema.xml` | Propel schema (`<database name="TheliaMain">`) | `SchemaLocator.php:173` |
| `install/update/preActivation/postActivation/registerHooks/preDeactivation/postDeactivation/destroy` | 8 lifecycle methods | `BaseModule.php:502-534` |
| `getConfigValue/setConfigValue` | Read/write `module_config` table | `BaseModule.php:234/240` |
| `Database` | `Thelia\Install\Database`, SQL helper `insertSql()` | `core/lib/Thelia/Install/Database.php` |
| `SchemaLocator` | Collects `*schema.xml` | `Core/Propel/Schema/SchemaLocator.php` |
| `PropelInitService` | Builds global schema + models | `Core/PropelInitService.php` |
| `ModuleManagement` | Scans `local/modules/*/Config/module.xml` | `Module/ModuleManagement.php` |
| `registerForAutoconfiguration` | Auto-tags interfaces (loops, forms, hooks, filters, addons, etc.) | `Thelia.php:470-509` |
| `configureServices` | Static method for PSR-4 load + autowire/autoconfigure | `BaseModule.php:487` |

## Hooks

| Term | Definition | Ref |
|---|---|---|
| `BaseHook` | Abstract class with `add()`, `addCSS()`, `addJS()`, `render()` | `Core/Hook/BaseHook.php:44` |
| `BaseHookInterface` | Hook contract | `Core/Hook/BaseHookInterface.php` |
| `getSubscribedHooks` | Static method alternative to `<tag>` XML | `BaseHook.php:485` |
| `HookRenderEvent` | `add(string $content)`, used by `{hook}` function | `Core/Event/Hook/HookRenderEvent.php` |
| `HookRenderBlockEvent` | `add(array $data)` Fragment, used by `{hookblock}` | `Core/Event/Hook/HookRenderBlockEvent.php` |
| `Fragment` / `FragmentBag` | Hook block fragment collection | `Core/Hook/Fragment.php` |
| `RegisterHookListenersPass` | Merges XML + getSubscribedHooks (WITHOUT DEDUP) | `Compiler/RegisterHookListenersPass.php:71` |

## Loops

| Term | Definition | Ref |
|---|---|---|
| `BaseLoop` | Abstract class with init/exec/parseResults | `Core/Template/Element/BaseLoop.php:55` |
| `PropelSearchLoopInterface` | `buildModelCriteria(): ModelCriteria` | `Element/PropelSearchLoopInterface.php` |
| `ArraySearchLoopInterface` | `buildArray(): array` (mutex with Propel) | `Element/ArraySearchLoopInterface.php` |
| `SearchLoopInterface` | search_term + search_in + search_mode | `Element/SearchLoopInterface.php` |
| `BaseI18nLoop` | Auto-joins i18n tables | `Element/BaseI18nLoop.php` |
| `LoopResult` / `LoopResultRow` | Loop result exposed to Smarty | `Element/LoopResult.php` |
| `ArgumentCollection` / `Argument` | Loop arg definitions, 10 factories | `Loop/Argument/Argument.php` |
| `RegisterLoopPass` | Collects tag `thelia.loop` -> param `Thelia.parser.loops` | `Compiler/RegisterLoopPass.php:34` |

## Forms

| Term | Definition | Ref |
|---|---|---|
| `BaseForm` | Abstract class with `init()` (not constructor) and `buildForm()` | `Form/BaseForm.php:44` |
| `ParserContext` | Request-scoped store (errored forms, vars), persists in session | `Core/Template/ParserContext.php:31` |
| `TheliaFormFactory` | Service `thelia.form_factory` | core |
| `TheliaFormValidator` | Service `thelia.form_validator` | core |
| `validateForm` | Controller helper: CSRF + method + validators | `BaseController.php:263` |
| `success_url` / `error_url` / `error_message` | Auto hidden fields BaseForm | `BaseForm.php:161-178` |
| `FORM_BEFORE_BUILD` / `FORM_AFTER_BUILD` | External form extension events | `TheliaEvents.php:607-608` |

## Events

| Term | Definition | Ref |
|---|---|---|
| `TheliaEvents` | 175 event constants (final class) | `Core/Event/TheliaEvents.php` |
| `loop.extends.*` | Loop extension events, suffixed by name | `TheliaEvents.php:426` |
| `ORDER_BEFORE_PAYMENT` | `action.order.beforePayment` (not `ORDER_BEFORE_CREATE`) | `TheliaEvents.php:296` |
| `AFTER_CARTADDITEM` | `cart.after.addItem`, post-save | `TheliaEvents.php:271` |
| `CART_ADDITEM` | `action.addArticle`, HTTP action | `TheliaEvents.php:256` |
| `MODULE_PAY` | `thelia.module.pay` | `TheliaEvents.php` |
| `MODULE_DELIVERY_GET_POSTAGE` | `thelia.module.delivery.postage` | `TheliaEvents.php` |
| `ORDER_UPDATE_STATUS` | `action.order.updateStatus` | `TheliaEvents.php` |

## Smarty / Templates

| Term | Definition | Ref |
|---|---|---|
| `ParserInterface` | Unique parser interface (front, back, pdf, email) | `Core/Template/ParserInterface.php` |
| `SmartyParser` | Unique implementation, local module | `local/modules/TheliaSmarty/Template/SmartyParser.php:35` |
| `TemplateDefinition` | 4 types: FRONT_OFFICE=1, BACK_OFFICE=2, PDF=3, EMAIL=4 | `Core/Template/TemplateDefinition.php:21` |
| `theliaEscape` | Variable filter htmlspecialchars (scalars) | `SmartyParser.php:121` |
| `theme` | Directory in `templates/{type}/`, active via DB config | const |
| `compile dir` | `var/cache/{env}/smarty/compile` | core |
| `addTemplateDirectory` | Registers module template path in Smarty | `SmartyParser.php` |
| `TheliaSmarty` | Local module implementing Smarty parser | `local/modules/TheliaSmarty/` |

## API Platform & Propel Bridge

| Term | Definition | Ref |
|---|---|---|
| `ApiPlatformBundle` | AP 3.4 Symfony bundle | `config/bundles.php:5` |
| `PropelResourceInterface` | Contract for AP resource tied to Propel model | `Api/Resource/PropelResourceInterface.php:19` |
| `PropelResourceTrait` | Default implementation (propelModel, addons, __get) | `Api/Resource/PropelResourceTrait.php` |
| `AbstractTranslatableResource` | Base for i18n resources + `I18nCollection` | `Api/Resource/AbstractTranslatableResource.php:15` |
| `I18nCollection` | Collection of I18n objects indexed by locale | `Api/Resource/I18nCollection.php` |
| `ResourceAddonInterface` | Extends a native resource from a module | `Api/Resource/ResourceAddonInterface.php` |
| `ResourceAddonTrait` | Virtual columns implementation | `Api/Resource/ResourceAddonTrait.php` |
| `RegisterApiResourceAddonPass` | Collects tag `thelia.api.resource.addon` | `Compiler/RegisterApiResourceAddonPass.php:35` |
| `#[Relation]` | Propel FK <-> Resource attribute | `Bridge/Propel/Attribute/Relation.php` |
| `#[Column]` | Propel field alias attribute | `Bridge/Propel/Attribute/Column.php` |
| `#[CompositeIdentifiers]` | Composite key attribute | `Bridge/Propel/Attribute/CompositeIdentifiers.php` |
| `PropelCollectionProvider` | AP `GetCollection` provider | `Bridge/Propel/State/PropelCollectionProvider.php:24` |
| `PropelItemProvider` | AP `Get` item provider, dispatches `ItemProviderQueryEvent` | `State/PropelItemProvider.php:29` |
| `PropelPersistProcessor` | AP POST/PUT/PATCH transaction processor | `State/PropelPersistProcessor.php:33` |
| `PropelRemoveProcessor` | AP DELETE processor | `State/PropelRemoveProcessor.php:23` |
| `ItemProviderQueryEvent` | Item query hook event | `Bridge/Propel/Event/ItemProviderQueryEvent.php` |
| `QueryCollectionExtensionInterface` | Collection hook (filter/pagination/security) | `Bridge/Propel/Extension/` |
| `QueryItemExtensionInterface` | Item hook | `Bridge/Propel/Extension/` |
| `IriConverter` (Thelia) | Decorator `api_platform.symfony.iri_converter` for composites | `Bridge/Propel/Routing/IriConverter.php:26` |
| `FilterInterface` (Thelia) | Propel filters, distinct from `ApiPlatform\Api\FilterInterface` | `Bridge/Propel/Filter/FilterInterface.php` |
| `SearchFilter / OrderFilter / BooleanFilter / DateFilter / RangeFilter / NotInFilter` | 7 custom Propel filters | `Bridge/Propel/Filter/` |
| `JwtListener` | Adds `type` claim to JWT | `Core/EventListener/JwtListener.php:22` |
| `CustomerGetCollectionExtension` | Auto Propel filter on front GetCollection | `Bridge/Propel/Extension/CustomerGetCollectionExtension.php` |

## Security

| Term | Definition | Ref |
|---|---|---|
| `AdminUserProvider` / `CustomerUserProvider` | Symfony providers | `core` |
| `URL::$instance` | URL helper singleton | `core` |
| `Translator::$instance` | Translator singleton | `core` |
| `Tlog::getInstance()` | Logger singleton | `core` |
| `BaseFrontController` / `BaseAdminController` | Thelia parent controllers with helpers | `core/lib/Thelia/Controller/` |
| `SecurityContext` | Thelia auth service (NOT SF Security) | core |

## Module types

| Term | Definition | Ref |
|---|---|---|
| `AbstractPaymentModule` | Payment module type with `pay()`, `isValidPayment()` | `Module/AbstractPaymentModule.php` |
| `AbstractDeliveryModule` | Delivery module type with `getPostage()`, `isValidDelivery()` | `Module/AbstractDeliveryModule.php` |

## Tests

| Term | Definition | Ref |
|---|---|---|
| `WebTestCase` | HTTP smoke test, loginAdmin helpers | `tests/Functional/WebTestCase.php:25` |
| `tests/Legacy` | Historical tests **NOT executed** by phpunit.xml.dist | `tests/Legacy/` |
| `TestCaseWithURLToolSetup` | Initializes URL singleton | `tests/Legacy/TestCaseWithURLToolSetup.php:23` |

## Persistence

| Term | Definition | Ref |
|---|---|---|
| `Propel::getConnection('TheliaMain')` | Main connection | `core` |
| `DatabaseConfiguration::THELIA_CONNECTION_NAME` | const = `'TheliaMain'` | `core` |
| `timestampable` / `i18n` / `versionable` | Propel behaviors in core | `local/config/schema.xml` |

## Autoconfigure / DI

| Auto tag | Interface |
|---|---|
| `thelia.loop` | `LoopInterface` |
| `thelia.form` | `FormInterface` (Thelia) |
| `hook.event_listener` | `BaseHookInterface` (incomplete; see hooks-loops.md) |
| `thelia.api.propel.filter` | `FilterInterface` (Propel) |
| `thelia.api.resource.addon` | `ResourceAddonInterface` |
| `thelia.api.propel.query_extension.collection` | `QueryCollectionExtensionInterface` |
| `thelia.api.propel.query_extension.item` | `QueryItemExtensionInterface` |
| `thelia.serializer` | `SerializerInterface` |
| `thelia.archiver` | `ArchiverInterface` |
| `controller.service_arguments` | `ControllerInterface` |
| `thelia.command` | `ContainerAwareInterface` (commands) |
