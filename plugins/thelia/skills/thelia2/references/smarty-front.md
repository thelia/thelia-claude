# Thelia 2.6: Smarty front-office

> Source: `local/modules/TheliaSmarty/Template/SmartyParser.php:35`, `core/lib/Thelia/Core/Template/TemplateDefinition.php:21`. **Key point**: T2 uses Smarty exclusively for front + back + email + pdf. No Twig anywhere.

## 1. Architecture

`SmartyParser extends \Smarty implements ParserInterface` (`local/modules/TheliaSmarty/Template/SmartyParser.php:35`). Smarty is a **local module**, not a Symfony bundle. Migration to Twig (T3) breaks this integration in chain (SIGNAL-21).

`ParserInterface` (`core/lib/Thelia/Core/Template/ParserInterface.php`) is the unique parser interface for all 4 contexts.

## 2. 4 contexts: TemplateDefinition

`core/lib/Thelia/Core/Template/TemplateDefinition.php:21-29`:

| Type | Constant | Subdirectory | DB config var |
|---|---|---|---|
| Front office | `FRONT_OFFICE = 1` | `frontOffice` | `active-front-template` |
| Back office | `BACK_OFFICE = 2` | `backOffice` | `active-admin-template` |
| PDF | `PDF = 3` | `pdf` | `active-pdf-template` |
| Email | `EMAIL = 4` | `email` | `active-email-template` |

Compile dir: `var/cache/{env}/smarty/compile`. Cache dir: `var/cache/{env}/smarty/cache`.
Path conventions: `templates/{frontOffice|backOffice|email|pdf}/{theme}/...`.

## 3. 20 plugins / ~85 Smarty tags

| Category | Plugin | Tags |
|---|---|---|
| Loops | `TheliaLoop.php` | `{loop}` `{elseloop}` `{ifloop}` `{pageloop}` `{count}` |
| Hooks | `Hook.php` | `{hook}` `{hookblock}` `{forhook}` `{elsehook}` `{ifhook}` |
| Forms | `Form.php` | `{form}` `{form_field}` `{form_tagged_fields}` `{form_error}` `{custom_render_form_field}` `{form_collection}` `{form_collection_field}` `{form_hidden_fields}` `{form_enctype}` `{form_field_attributes}` `{render_form_field}` `{form_collection_count}` |
| Intl | `Translation.php` | `{intl}` `{default_translation_domain}` `{default_locale}` |
| URL | `UrlGenerator.php` | `{url}` `{token_url}` `{viewurl}` `{admin_viewurl}` `{navigate}` `{set_previous_url}` |
| Format | `Format.php` | `{format_date}` `{format_number}` `{format_money}` `{format_array_2d}` `{format_address}` `\|implode` |
| Assets | `Assets.php` | `{stylesheets}` `{javascripts}` `{images}` `{asset}` `{image}` `{javascript}` `{stylesheet}` `{renderSvgImage}` `{declare_assets}` |
| Security | `Security.php` | `{check_auth}` `{check_cart_not_empty}` `{check_valid_delivery}` |
| Encore | `Encore.php` | `{encore_module_asset}` `{encore_manifest_file}` `{encore_entry_js_files}` `{encore_entry_css_files}` `{encore_entry_script_tags}` `{encore_entry_prefetch_script_tags}` `{encore_entry_preload_script_tags}` `{encore_entry_link_tags}` `{encore_entry_exists}` |
| Data Access | `DataAccessFunctions.php` | `{admin}` `{customer}` `{product}` `{category}` `{content}` `{folder}` `{brand}` `{currency}` `{country}` `{lang}` `{cart}` `{order}` `{config}` `{stats}` `{meta}` `{module_config}` `{coupon}` `{local_media}` |
| Front utils | `FrontUtils.php` | `{domain}` `{currentView}` `{renderIconSvg}` `{renderSvg}` `{psesByProduct}` `{extractOptions}` `{isInCategory}` `{isInFolder}` `{rewritingUrl}` |
| Render | `Render.php` | `{render}` |
| Module include | `Module.php` | `{module_include}` |
| Component | `Component.php` | `{component}` `{include_component}` |
| Cache | `Cache.php` | `{cache}` |
| Flash | `FlashMessage.php` | `{hasflash}` `{flash}` |
| Postage | `CartPostage.php` | `{postage}` |
| Type | `Type.php` | `\|assertType` |
| Var dumper | `VarDumper.php` | `{dump}` |

## 4. Main tags: syntax

### Loops

```smarty
{loop name="prods" type="product" category="3" limit="10"}
    <a href="{url path="/product/{$URL}"}">{$TITLE}</a>
{/loop}

{ifloop rel="prods"}<ul>...</ul>{/ifloop}
{elseloop rel="prods"}<p>no products</p>{/elseloop}
{pageloop rel="prods"}<a href="?page={$PAGE}">{$PAGE}</a>{/pageloop}
{count name="prods" type="product" category="3"}
```

Auto variables inside `{loop}`: `$LOOP_COUNT`, `$LOOP_TOTAL`.

### Hooks

```smarty
{hook name="main.head-bottom"}
{hook name="account-order.after-information" order=$ORDER}
{hookblock name="account.bottom" fields="title,content"}
    <h2>{$title}</h2>{$content}
{/hookblock}
```

`{hook}` is SILENT if no listener (no error, no log). Mistyped hook name = invisible.

### Forms

```smarty
{form name="thelia.front.contact"}
    {render_form_field field="email"}
    {render_form_field field="message"}
    {form_hidden_fields form=$form}
    <input type="hidden" name="success_url" value="{url path='/contact-thanks'}">
    <button type="submit">Send</button>
{/form}
```

`{form_hidden_fields}` renders the CSRF token. `success_url` / `error_url` are automatic hidden fields of `BaseForm`. See [forms.md](forms.md).

### Intl

```smarty
{intl l="Hello"}
{intl l="Welcome %name" name=$customer->getFirstname()}
{intl l="Module text" d="mymodule"}        {* module domain *}
```

### URL

```smarty
{url path="/account"}                       {* without token *}
{token_url path="/account/delete"}          {* with CSRF *}
{viewurl view="product" id=$ID}             {* rewrite-aware link *}
{admin_viewurl view="categories"}           {* admin *}
```

### Format

```smarty
{$price|format_money:1:2}                   {* active currency, 2 decimals *}
{$date|format_date}
{$amount|format_number:2}
```

### Security

```smarty
{check_auth role="CUSTOMER"}
    Welcome {$customer->getFirstname()}
{/check_auth}

{check_cart_not_empty}
    Proceed to checkout
{/check_cart_not_empty}
```

### Encore (module assets)

```smarty
{encore_entry_script_tags name="mymodule" template="frontOffice"}
{encore_entry_link_tags name="mymodule" template="frontOffice"}
```

### Data accessors

```smarty
{customer attr="email"}
{product attr="title" id=42}
{cart attr="total"}
{order attr="ref" id=$ORDER_ID}
{module_config var="my_setting" module_code="MyModule"}
```

## 5. Module override -> active theme

Place in `{module}/templates/frontOffice/{themeName}/<sub-path>/file.html`.

The scanner `Thelia::addModuleTemplateToParserEnvironment()` (`Thelia.php:377-404`) adds this directory to the Smarty search path with the module key. `addTemplateDirectory(..., $unshift=true)` can prioritize the module over the theme, depending on the loading mode.

Example: to override `templates/frontOffice/default/layout.tpl` from MyModule:
```
local/modules/MyModule/templates/frontOffice/default/layout.tpl
```

## 6. Compile cache per env

- Compile dir: `var/cache/{env}/smarty/compile`.
- Modifying a module template -> clear cache (`bin/console cache:clear` or manual deletion).
- HTTP `{cache}` block bypassable for debugging.

## 7. Smarty security

### No sandbox

`{php}` is allowed by default. **NEVER render Smarty containing user input.** Module threat model: a compromised third-party theme exfiltrates data.

### Auto-escape `theliaEscape`

`SmartyParser.php:121` configures the auto-filter `theliaEscape` (htmlspecialchars on scalars).

**Anti-pattern**: `{$VAR|escape:'html'}` -> double escape. Let the auto-filter act.

### Auto CSRF via `{form_hidden_fields}`

Always render in every public form. Token generated by `CsrfTokenManager` at form boot.

## 8. Smarty pitfalls

1. Silent hook if no listener (mistyped name = invisible)
2. Auto snake_case loop name (`BetterSeoLoop` -> `better_seo_loop`). Declare alias `<loop name="...">` in config.xml if template expects another name (SIGNAL-17).
3. `{php}` is allowed. Never render Smarty containing user input.
4. Double escape from `{$x|escape:'html'}`. Leave the auto-filter alone.
5. `success_url` / `error_url` are BaseForm hidden fields. Host whitelist required (SIGNAL-16).
