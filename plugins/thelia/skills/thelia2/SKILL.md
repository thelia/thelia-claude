---
name: thelia2
description: "Thelia 2.6 e-commerce framework (branch main, Symfony 6.4, API Platform 3.4, PHP 8.2+, Propel ORM, Smarty front + back + email + pdf). Covers module creation: BaseModule lifecycle 8 methods (install/update/preActivation/postActivation/registerHooks/preDeactivation/postDeactivation/destroy), config.xml/module.xml/schema.xml (XSD module-2_2.xsd, thelia-1.0.xsd), Propel-AP Bridge (PropelResourceInterface, PropelResourceTrait, ResourceAddonInterface, ResourceAddonTrait, AbstractTranslatableResource, I18nCollection, Relation/Column/CompositeIdentifiers attributes), 7 custom Propel filters (SearchFilter/OrderFilter/BooleanFilter/RangeFilter/DateFilter/NotInFilter/AbstractFilter), JWT Lexik 2.x without refresh, Smarty back+front hooks (BaseHook + getSubscribedHooks(), HookRenderEvent .add() vs HookRenderBlockEvent fragments), loops (BaseLoop + PropelSearchLoopInterface vs ArraySearchLoopInterface mutex, BaseI18nLoop, SearchLoopInterface, ArgumentCollection 10 factories), forms (BaseForm + init() non-constructor + getName() auto-FQCN snake_case + ParserContext, success_url/error_url hidden fields), 175 events TheliaEvents (ORDER_BEFORE_PAYMENT, AFTER_CARTADDITEM, FORM_BEFORE_BUILD/AFTER_BUILD, MODULE_PAY, MODULE_DELIVERY_GET_POSTAGE), 20 Smarty plugins / ~85 tags ({loop}, {ifloop}, {elseloop}, {pageloop}, {hook}, {hookblock}, {form}, {form_field}, {form_hidden_fields}, {intl}, {url}, {token_url}, {theme}, {theme_url}, {flash}, {check_auth}, {format_money}, {format_date}, {encore_entry_script_tags}), payment/delivery modules (AbstractPaymentModule pay()/isValidPayment(), AbstractDeliveryModule getPostage()), TheliaSmarty local module + SmartyParser, RegisterHookListenersPass, RegisterLoopPass. Use when working on Thelia 2.6 projects, branch main repo thelia/thelia, creating modules in local/modules, building Smarty front+back+email+pdf templates, exposing API resources, writing hooks/loops/forms, integrating payment/delivery modules. Triggers on: thelia 2, thelia 2.6, branch main, BaseModule, config.xml, module.xml, schema.xml, postActivation, registerHooks, TheliaEvents, BaseHook, getSubscribedHooks, HookRenderEvent, HookRenderBlockEvent, BaseLoop, PropelSearchLoopInterface, ArraySearchLoopInterface, BaseI18nLoop, BaseForm, ParserContext, SmartyParser, TheliaSmarty, Smarty, {loop}, {hook}, {hookblock}, {form}, {intl}, {url}, {pageloop}, {ifloop}, {elseloop}, {form_field}, {form_hidden_fields}, {check_auth}, {format_money}, PropelResourceInterface, PropelResourceTrait, ResourceAddonInterface, ResourceAddonTrait, AbstractTranslatableResource, I18nCollection, ApiFilter SearchFilter OrderFilter BooleanFilter RangeFilter DateFilter NotInFilter, Relation Column CompositeIdentifiers, local/modules, AbstractPaymentModule, AbstractDeliveryModule, ORDER_BEFORE_PAYMENT, AFTER_CARTADDITEM, CART_ADDITEM, Api/Resource/, normalizationContext per operation, GROUP_ADMIN_READ_SINGLE, BankCoordinatesForm, IBAN normalization, setPostage save, module.configuration save Controller, routing.xml admin module, token_url CSRF, final readonly tests Reflection, BaseAdminController checkAuth, validateForm, generateSuccessRedirect, generateErrorRedirect. Do NOT trigger for Thelia 3 projects (look for Twig .html.twig templates, FlexyBundle, LiveComponent, TwigComponent, AP 4.3 standalone, branch twig, IntegrationTestCase, FixtureFactory, resources(), attr(), CartFacade)."
---

# Thelia 2.6 -- Module Development Guide

> Stack: Symfony 6.4, API Platform 3.4 (bundle), PHP 8.2+, Propel ORM, branch `main`. Front + back + email + pdf in Smarty exclusively (no Twig). API JSON-LD only. JWT Lexik 2.x without refresh. No Doctrine, no Messenger, no Turbo/Mercure, no LiveComponent.

## 1. Decision router "I want X"

| I want X | Canonical T2.6 approach | Reference |
|---|---|---|
| Create a module | `local/modules/MyModule/` (PSR-4 declared globally by Thelia) | modules.md |
| Initialize module DI | `MyModule::configureServices()` + `load()->autowire()->autoconfigure()` (`BaseModule.php:487`) | modules.md |
| Declare metadata | `Config/module.xml` -- XSD `module-2_2.xsd` -- required | modules.md |
| Declare legacy DI | `Config/config.xml` -- XSD `thelia-1.0.xsd` -- **required EVEN IF EMPTY** (`Thelia.php:555`) | modules.md |
| Define a Propel schema | `Config/schema.xml` `<database name="TheliaMain">` + `<external-schema referenceOnly="true">` (`SchemaLocator.php:173`) | modules.md |
| Migrate a version | `Config/update/{version}.sql` + override `update()` (do NOT confuse with `Config/Update/`) | modules.md |
| Initialize after activation | `postActivation()` with guard `getConfigValue('is_initialized')` | modules.md |
| Persist an entity | `$model->save()` Propel -- each save persists, **no flush** | modules.md |
| Read/write module config | `BaseModule::getConfigValue($name, $default)` / `setConfigValue($name, $value)` (`BaseModule.php:234/240`) | modules.md |
| DB connection | `Propel::getConnection('TheliaMain')` (= `Thelia\Config\DatabaseConfiguration::THELIA_CONNECTION_NAME` -- NOT `Thelia\Core\Propel\...`) | modules.md |
| Execute a .sql file | `(new Thelia\Install\Database($con))->insertSql(null, [$path])` | modules.md |
| Expose an API resource | `implements PropelResourceInterface` + `use PropelResourceTrait` (`Api/Resource/PropelResourceInterface.php:19`) | api-platform.md |
| i18n resource | `extends AbstractTranslatableResource` + concrete I18n class `extends I18n` | api-platform.md |
| Extend a native resource | `implements ResourceAddonInterface` + `use ResourceAddonTrait` -- auto-tagged | api-platform.md |
| Filter a Propel API endpoint | `#[ApiFilter]` with **Thelia custom Propel filters** (never Doctrine) | api-platform.md |
| Secure an admin operation | path `/admin/{resource}` + `access_control ^/api/admin` -> `ROLE_ADMIN` | api-platform.md |
| Secure an authenticated front operation | path `/front/account/{resource}` + `access_control ^/api/front/account` -> `ROLE_CUSTOMER` | api-platform.md |
| JWT API login | `POST /api/{front\|admin}/login` body `{username, password}` -- no refresh | api-platform.md |
| React to an event | `#[AsEventListener]` SF 6.x or `<tag name="kernel.event_listener">` XML | hooks-loops.md |
| Before order payment | Listener on `TheliaEvents::ORDER_BEFORE_PAYMENT` -- `ORDER_BEFORE_CREATE` does not exist | hooks-loops.md |
| After product added to cart | Listener on `AFTER_CARTADDITEM` (not `CART_ADDITEM` which is the HTTP action) | hooks-loops.md |
| Discover events | `core/lib/Thelia/Core/Event/TheliaEvents.php` -- 175 constants | hooks-loops.md |
| Smarty front/back hook | `extends BaseHook` + **`<hook>` XML** in config.xml (autoconfigure alone is not enough) | hooks-loops.md |
| Render hook function | `HookRenderEvent::add(string $content)` -> `{hook name="..."}` | hooks-loops.md |
| Render hook block | `HookRenderBlockEvent::add(array $data)` -> `{hookblock name="..." fields="..."}` | hooks-loops.md |
| Declare a loop | `extends BaseLoop` + `implements PropelSearchLoopInterface` (mutex with `ArraySearchLoopInterface`) | hooks-loops.md |
| Rename a Smarty loop | snake_case auto (`BetterSeoLoop` -> `better_seo_loop`); alias = `<loop name="alias">` | hooks-loops.md |
| Declare a form | `extends BaseForm` -- auto-tagged, `getName()` auto FQCN snake_case (`BaseForm.php:394`) | forms.md |
| Form errors in template | `ParserContext::addForm($form)` -> `{form name="..."}` Smarty | forms.md |
| Generate Smarty URL | `{url path="/x"}` (no token) or `{token_url path="/x"}` (with CSRF) | smarty-front.md |
| Translate string in Smarty | `{intl l="..."}` or `{intl l="..." d="modulecode"}` for module domain | smarty-front.md |
| Read cart in template | `{loop type="cart"}` or data accessor `{cart}` | smarty-front.md |
| Read customer in template | `{loop type="customer"}` or `{customer attr="email"}` | smarty-front.md |
| Override theme template | `{module}/templates/{frontOffice\|backOffice}/{theme}/<relative path>` (`Thelia.php:377-404`) | smarty-front.md |
| Check customer auth | `{check_auth role="CUSTOMER"}...{/check_auth}` (block) | smarty-front.md |
| Module Encore asset | `{encore_entry_script_tags name="..."}` | smarty-front.md |
| Custom BO hook | `templates/backOffice/default/...` + `{hook name="..."}` (8-10 native hooks) | smarty-back.md |
| Payment module | `extends AbstractPaymentModule` + `pay(Order)` + `isValidPayment()` | payment-delivery.md |
| Delivery module | `extends AbstractDeliveryModule` + `getPostage(Country)` + zones/rates | payment-delivery.md |
| Test an HTTP endpoint | `WebTestCase::createClient()` + `loginAdmin()` -- **pollutes dev DB** (no rollback) | testing.md |
| Test a Propel Action | Build your own harness (`tests/Legacy/` not executed by phpunit) | testing.md |
| Propel Repository | `final readonly class XxxRepository` -- project convention, no inline query | code-patterns.md |
| Migrate module T2.5 -> T2.6 | Audit AP 3.4 + Doctrine filters -> custom Propel | migration.md |
| Migrate T2 -> T3 | Out of scope -- see skill `thelia3` | migration.md |
| Vocabulary | Framework terms | glossary.md |

## 2. Minimal Thelia 2.6 module skeleton

```
local/modules/MyModule/
+- MyModule.php                       # extends BaseModule
+- composer.json                      # OPTIONAL if distributed via Composer
+- Config/
|  +- module.xml                      # REQUIRED -- XSD module-2_2.xsd
|  +- config.xml                      # REQUIRED EVEN IF EMPTY -- XSD thelia-1.0.xsd
|  +- schema.xml                      # OPTIONAL -- Propel schema
|  +- thelia.sql                      # Initial SQL (postActivation)
|  +- routing.xml                     # OPTIONAL (prefer #[Route] PHP 8)
|  +- update/                         # Versioned *.sql files (1.1.0.sql, 1.2.0.sql)
+- Command/                           # #[AsCommand] SF 6.4
+- Hook/                              # extends BaseHook
+- Loop/                              # extends BaseLoop + PropelSearchLoopInterface
+- Form/                              # extends BaseForm (auto-tagged thelia.form)
+- Controller/Front, Controller/Admin # extends BaseFront/AdminController
+- EventListener/                     # #[AsEventListener] SF 6.x
+- Api/Resource/                      # PropelResourceInterface (scanned dynamically)
+- I18n/                              # en_US.php, fr_FR.php
+- templates/
   +- frontOffice/default/...html
   +- backOffice/default/...html
```

### `Config/module.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<module xmlns="http://thelia.net/schema/dic/module"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://thelia.net/schema/dic/module http://thelia.net/schema/dic/module/module-2_2.xsd">
    <fullnamespace>MyModule\MyModule</fullnamespace>
    <descriptive locale="en_US"><title>My Module</title></descriptive>
    <languages><language>en_US</language></languages>
    <version>1.0.0</version>
    <authors><author><name>Dev</name><email>dev@example.com</email></author></authors>
    <type>classic</type>
    <thelia>2.6.0</thelia>
    <stability>prod</stability>
</module>
```

### `Config/config.xml` (autoconfigure + required hook XML)

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<config xmlns="http://thelia.net/schema/dic/config"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://thelia.net/schema/dic/config http://thelia.net/schema/dic/config/thelia-1.0.xsd">
    <hooks>
        <hook id="mymodule.front" class="MyModule\Hook\FrontHook">
            <tag name="hook.event_listener" event="main.body-bottom" type="front" method="onMainBodyBottom"/>
        </hook>
    </hooks>
</config>
```

### `MyModule.php`

```php
<?php
declare(strict_types=1);

namespace MyModule;

use Propel\Runtime\Connection\ConnectionInterface;
use Symfony\Component\DependencyInjection\Loader\Configurator\ServicesConfigurator;
use Thelia\Install\Database;
use Thelia\Module\BaseModule;

final class MyModule extends BaseModule
{
    public function postActivation(ConnectionInterface $con = null): void
    {
        if (!self::getConfigValue('is_initialized')) {
            (new Database($con))->insertSql(null, [__DIR__.'/Config/thelia.sql']);
            self::setConfigValue('is_initialized', '1');
        }
    }

    public static function configureServices(ServicesConfigurator $services): void
    {
        $services->load(__NAMESPACE__.'\\', __DIR__)
            ->exclude([__DIR__.'/I18n/*', __DIR__.'/Config/*', __DIR__.'/templates/*'])
            ->autowire(true)
            ->autoconfigure(true);
    }
}
```

### `Config/schema.xml` minimal

```xml
<?xml version="1.0" encoding="UTF-8"?>
<database xmlns="http://xsd.propelorm.org/1.6/database.xsd"
          name="TheliaMain" defaultIdMethod="native">
    <external-schema filename="local/config/schema.xml" referenceOnly="true"/>
    <table name="my_module_item" namespace="MyModule\Model">
        <column name="id" type="INTEGER" primaryKey="true" autoIncrement="true" required="true"/>
        <column name="visible" type="TINYINT" required="true" defaultValue="0"/>
        <column name="product_id" type="INTEGER"/>
        <foreign-key foreignTable="product" onDelete="CASCADE" onUpdate="RESTRICT">
            <reference local="product_id" foreign="id"/>
        </foreign-key>
        <behavior name="timestampable"/>
        <behavior name="i18n">
            <parameter name="i18n_columns" value="title, description"/>
        </behavior>
    </table>
</database>
```

### `composer.json` (if distributing via Composer)

```json
{
    "name": "vendor/mymodule",
    "type": "thelia-module",
    "require": {"thelia/installer": "~1.1"},
    "extra": {"installer-name": "MyModule"}
}
```

## 3. Lifecycle -- 8 methods (`BaseModule.php:502-534`)

| # | Method | Contract | Pitfall |
|---|---|---|---|
| 1 | `install` | First discovery. Wrapped by `ModuleManagement::updateModule()` | No second transaction |
| 2 | `update($currentVersion, $newVersion, $con)` | If `module.xml.version > DB version` | No-op by default, the module MUST load its .sql files |
| 3 | `preActivation` | Return `bool` required. `false` silently rolls back | Exception also rolls back |
| 4 | `postActivation` | Inside the activation transaction | Idempotency is essential (`is_initialized`) |
| 5 | `registerHooks` | **OUTSIDE transaction** -- after `$con->commit()` | **MAJOR PITFALL**: exception here = module active with no hooks |
| 6 | `preDeactivation` | Return `bool` | Same as preActivation |
| 7 | `postDeactivation` | Inside the transaction | -- |
| 8 | `destroy` | Manual removal (`$deleteModuleData=true` purges tables) | -- |

Access from `BaseModule`: `$this->getContainer()` (`L143`), `$this->getRequest()` (`L167`, priority `request_stack`), `$this->getDispatcher()` (`L196`).

## 4. Capability summary

### 4.1 Modules & DI
- `configureServices()` static with `autowire()->autoconfigure()` (`Thelia.php:470-509`).
- Auto-tags via `registerForAutoconfiguration`: `LoopInterface` -> `thelia.loop`, `FormInterface` -> `thelia.form`, `FilterInterface` -> `thelia.api.propel.filter`, `ResourceAddonInterface` -> `thelia.api.resource.addon`, `BaseHookInterface` -> `hook.event_listener` (incomplete, see hooks).
- SQL migration convention: `Config/update/{version}.sql` (semver, `version_compare()`).
- Details: [references/modules.md](references/modules.md)

### 4.2 API Platform 3.4 & Propel Bridge
- 5 Propel Bridge decorators (collection metadata factory, IRI converter, class metadata factory, property metadata factory, OpenAPI factory).
- Resources: `PropelResourceInterface` + `PropelResourceTrait`; i18n: `AbstractTranslatableResource` + `I18nCollection`.
- 7 custom Propel filters (SearchFilter, OrderFilter, BooleanFilter, DateFilter, RangeFilter, NotInFilter, AbstractFilter). **Native AP Doctrine filters are INCOMPATIBLE on Propel resources.**
- JWT Lexik 2.x without refresh; URL conventions `/admin/{resource}` (ROLE_ADMIN), `/front/{resource}` (public), `/front/account/{resource}` (ROLE_CUSTOMER).
- **NO QueryParameter, NO Metadata Mutators, NO JsonStreamer, NO ObjectMapper** (AP 4.1+ only).
- Details: [references/api-platform.md](references/api-platform.md)

### 4.3 Smarty front-office
- `SmartyParser` is a local module `local/modules/TheliaSmarty/`, not a Symfony bundle.
- 4 contexts: `FRONT_OFFICE = 1`, `BACK_OFFICE = 2`, `PDF = 3`, `EMAIL = 4` (`TemplateDefinition.php:21-29`).
- 20 plugins / ~85 tags: `{loop}`, `{ifloop}`, `{elseloop}`, `{pageloop}`, `{hook}`, `{hookblock}`, `{form}`, `{form_field}`, `{form_hidden_fields}`, `{intl}`, `{url}`, `{token_url}`, `{theme}`, `{theme_url}`, `{flash}`, `{check_auth}`, `{format_money}`, `{format_date}`, `{encore_entry_script_tags}`, etc.
- **No Smarty sandbox**: `{php}` is allowed -- NEVER render Smarty from user input.
- Details: [references/smarty-front.md](references/smarty-front.md)

### 4.4 Smarty back-office
- Theme `default`; module override in `{module}/templates/backOffice/default/...`.
- 8-10 native BO hooks (`main.head-css`, `main.before-topbar`, `categories.row`, `order-edit.bill-top`, `customer-edit.top`, `modules.config-js`...).
- `BaseAdminController` helpers: `validateForm()`, `generateRedirectFromRoute()`, `generateErrorRedirect()`, `generateSuccessRedirect()`, `getParserContext()`.
- Details: [references/smarty-back.md](references/smarty-back.md)

### 4.5 Hooks
- `BaseHook` + `getSubscribedHooks()` static OR `<hook>` XML in config.xml. **Choose ONE mode only** (`RegisterHookListenersPass.php:71` merges without dedup -> SIGNAL-02).
- Recommendation: XML because `autoconfigure` alone on `BaseHookInterface` is not enough (tag placed without `event/type/method` -> SIGNAL-06).
- `HookRenderEvent` (.add string) vs `HookRenderBlockEvent` (.add fragments).
- Silent hook if no listener -- no error, no log.
- Details: [references/hooks-loops.md](references/hooks-loops.md)

### 4.6 Loops
- Cycle: `init() -> initializeArgs() -> exec() -> buildModelCriteria()|buildArray() -> parseResults(LoopResult)`.
- `PropelSearchLoopInterface` (Propel) **mutex** with `ArraySearchLoopInterface` (`BaseLoop.php:560-617`).
- Auto-pagination if `protected $countable = true`.
- 70 native loops (`Product`, `Category`, `Cart`, `Order`, `Customer`, `Image`, `Document`, `Address`, `Currency`, `Hook`...).
- Details: [references/hooks-loops.md](references/hooks-loops.md)

### 4.7 Forms
- `BaseForm::init()` non-constructor (7 dependencies). `getName()` static auto FQCN snake_case (`BaseForm.php:394-406`).
- CSRF auto, hidden fields `success_url`/`error_url`/`error_message` -> **potential OPEN-REDIRECT** (SIGNAL-16).
- Events `FORM_BEFORE_BUILD.{name}` / `FORM_AFTER_BUILD.{name}` for external extension.
- `ParserContext::addForm()` to pass errors back to Smarty template.
- Details: [references/forms.md](references/forms.md)

### 4.8 Tests
- phpunit.xml.dist covers `unit` (empty) + `functional` (`WebTestCase` HTTP smoke).
- **NO `IntegrationTestCase`, NO `ApiTestCase`, NO `FixtureFactory`, NO isolated test DB** (vs T3).
- `WebTestCase::tearDown()` has NO rollback (commented lines) -> **DEV DB POLLUTION** (SIGNAL-15).
- `tests/Legacy/` is not referenced in phpunit.xml.dist -> silently ignored tests (SIGNAL-14).
- Recommended pattern: custom harness that boots `(new Thelia('test', true))->boot()` + manual Propel transaction begin/rollback.
- Details: [references/testing.md](references/testing.md)

### 4.9 Payment / delivery modules
- Payment: `extends AbstractPaymentModule` -> `pay(Order)`, `isValidPayment()`. Smarty BO hook `module.configuration`.
- Delivery: `extends AbstractDeliveryModule` -> `getPostage(Country)`, zones/rates config, listener `ORDER_UPDATE_STATUS`.
- `Message` seed required for notification emails (otherwise silently lost).
- Details: [references/payment-delivery.md](references/payment-delivery.md)

## 5. Deprecated patterns -- BLOCK THESE

| Pattern | Reason | T2.6 alternative |
|---|---|---|
| `Doctrine\ORM\EntityManager`, `persist()`, `flush()` | Thelia uses **Propel**, not Doctrine | `$model->save()` Propel |
| Native Doctrine AP filters on Propel resource | Runtime crash (QueryBuilder != ModelCriteria) | 7 Thelia custom Propel filters |
| Twig on front | Does not exist in T2 (Smarty exclusively) | Smarty |
| LiveComponent / TwigComponent / FlexyBundle | Do not exist in T2 | Standalone Stimulus for interactivity |
| `@Route` annotations | Deprecated SF 6.4, removed SF 7 | `#[Route]` PHP 8 |
| `#[TaggedIterator]` / `#[TaggedLocator]` | Deprecated SF 7.1+ | `#[AutowireIterator]` / `#[AutowireLocator]` |
| `scope="request"` config.xml | Deprecated SF 2.8 | `RequestStack` injection |
| `ContainerAwareTrait` in services | Deprecated SF 6.4 | Constructor injection |
| `csrf_protection => false` BaseForm | Security flaw | Always keep CSRF active |
| `force_return=true` without business args | Exposes non-visible content | Justify in review |
| `{$VAR\|escape:'html'}` Smarty | Double escape (native theliaEscape) | Leave auto-filter active |
| `tests/Legacy/` | Not executed by phpunit.xml.dist | Custom harness or `tests/Functional/` |
| Hooks XML + `getSubscribedHooks()` simultaneously | Silent double DB entry (SIGNAL-02) | Choose ONE mode per module |
| `QueryParameter` AP 4.1+, `JsonStreamer`, `ObjectMapper`, `Metadata Mutators` | Do not exist in AP 3.4 | `#[ApiFilter]` + custom processors |
| `IntegrationTestCase` / `FixtureFactory` / `ApiTestCase` | Do not exist in T2.6 | Custom harness |

## 6. Top 10 critical pitfalls

| # | Pitfall | Source | Solution |
|---|---|---|---|
| 1 | **Folder `Resource/` instead of `Api/Resource/`** -- AP resource silently absent | `services.php:88` | `{Module}\Api\Resource` namespace + folder; exclude `__DIR__.'/Api/Resource/*'` from DI |
| 2 | **`new XxxRepository()` inline** bypasses DI -- crash if repository acquires a dependency | review acceptance | `$this->getContainer()->get(MyRepository::class)` in inherited methods without injection (`pay`, `getPostage`...) |
| 3 | **BO configuration without dedicated Controller** -- save 404 or overwrites core config | `ModuleController::processUpdateAction` core CRUD | `routing.xml` + `Controller/Admin/` + `{token_url}` in template (see CustomDelivery) |
| 4 | **`$order->setPostage()` without `$order->save()`** -- recalculation lost (event after core save) | `Order.php:241/410` | Always `$order->save()` in `ORDER_BEFORE_PAYMENT` listener |
| 5 | **Test extending `final readonly`** -- fatal PHP 8.3, suite non-executable | PHP 8.3 | Interface + mock OR Reflection, never `extends FinalRepository` |
| 6 | **Global `normalizationContext`** ignores `GROUP_*_READ_SINGLE` on `Get` single | AP pattern | Override `normalizationContext` at the `Get` operation level |
| 7 | **`XxxQuery::create()` inline in loop/listener/hook/controller** | project rule | Always via Repository; exception **only** for native core loops |
| 8 | Hooks double mode (XML + `getSubscribedHooks()`) -> double DB entry | `RegisterHookListenersPass.php:71-118` | Choose ONE mode (XML recommended) |
| 9 | `config.xml` required EVEN IF EMPTY -- silent crash in production without it | `Thelia.php:555 + 572-577` | Always create the file, even empty |
| 10 | Native Doctrine AP filters incompatible with Propel resource | runtime crash | 7 Thelia custom Propel filters only |

Bonus criticals:
- `registerHooks()` outside transaction -> module active without hooks if exception (`BaseModule.php:111`)
- `ORDER_BEFORE_CREATE` does not exist -- use `ORDER_BEFORE_PAYMENT` (`TheliaEvents.php:296`)
- `CART_ADDITEM` (productId payload) vs `AFTER_CARTADDITEM` (cart only, productId absent) -- choose based on the payload you need
- IBAN validation rejecting spaces -> all users who copy-paste formatted IBANs get rejected; normalize PRE_SUBMIT
- `getTotalAmount(&$tax = 0, ...)`: the `$tax = 0` argument form is misleading, use a named variable
- No `IntegrationTestCase` -> tests pollute dev DB (`WebTestCase.php:50/55`)
- BOLA POST front addresses (no `securityPostDenormalize`, `Address.php:62`)
- Open-redirect `success_url` BaseForm without whitelist (`BaseForm.php:296-308`)
- Case sensitivity `Config/update/` vs `Config/Update/` on Linux (SIGNAL-04)
- Auto snake_case loop name inconsistent with templates (`RegisterLoopPass.php:34`)
- N+1 in `parseResults` via `findPk()` -- join in `buildModelCriteria()` via `useXxxQuery()`
- `{hook}` Smarty silent if no listener (mistyped name = invisible)
- `IriConverter` returns `'undefined_iri'` instead of exception on badly mapped composite (SIGNAL-11)
- Empty `security.yaml` project -- config injected by Reflection (`Thelia.php:647`, SIGNAL-12)
- `BaseHook::__construct()` calls `ModuleQuery` -> hook instantiated pre-install crashes (`BaseHook.php:87-103`)
- `BaseModule::getModuleCode()` collides on last FQCN segment (`BaseModule.php:364`, SIGNAL-07)

## 7. Deep-dive references

- [references/modules.md](references/modules.md) -- BaseModule, 8-method lifecycle, module.xml/config.xml/schema.xml, autoconfigure, SQL migrations, Composer distribution
- [references/api-platform.md](references/api-platform.md) -- AP 3.4 + Propel Bridge, 5 decorators, PropelResourceInterface, ResourceAddonInterface, AbstractTranslatableResource, Relation/Column/CompositeIdentifiers attributes, 7 Propel filters, JWT Lexik 2.x, security
- [references/smarty-front.md](references/smarty-front.md) -- SmartyParser, TemplateDefinition, 20 plugins / ~85 tags, theme override, compile cache
- [references/smarty-back.md](references/smarty-back.md) -- backOffice/default, 10 native BO hooks, BaseAdminController helpers
- [references/hooks-loops.md](references/hooks-loops.md) -- BaseHook + getSubscribedHooks vs XML, HookRenderEvent vs Block, BaseLoop cycle, PropelSearchLoopInterface vs ArraySearchLoopInterface, ArgumentCollection
- [references/forms.md](references/forms.md) -- BaseForm.init(), getName() auto FQCN, auto CSRF, success_url/error_url, ParserContext, FORM_BEFORE_BUILD/AFTER_BUILD
- [references/testing.md](references/testing.md) -- WebTestCase, custom harness, DB pollution, patterns by layer
- [references/payment-delivery.md](references/payment-delivery.md) -- AbstractPaymentModule, AbstractDeliveryModule, ORDER_UPDATE_STATUS listener, Message seed
- [references/code-patterns.md](references/code-patterns.md) -- declare(strict_types), final readonly, Repository pattern, #[AsEventListener], #[AsCommand], #[Route], enum, no redundant PHPDoc
- [references/migration.md](references/migration.md) -- T2.5 -> T2.6 (AP 3.4, SF 6.4, Propel filters); note T2 -> T3 out of scope
- [references/glossary.md](references/glossary.md) -- ~80 framework terms
