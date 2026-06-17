# Thelia 2: Smarty templates quick reference

## Quick reference

| Task | Approach |
|------|----------|
| Generate URL | `{url path="/route"}` |
| Translate | `{intl l="Text" d="domain"}` |
| Format price | `{format_money number=$PRICE}` |
| Access cart | `{cart attr="total_taxed_price"}` |
| Loop over data | `{loop type="product" name="x"}...{/loop}` |
| Form | `{form name="x"}{form_field field="y"}...{/form_field}{/form}` |
| Hook | `{hook name="product.top"}` |

## Theme structure

```
templates/
+-- frontOffice/
|   +-- default/
|       +-- layout.tpl           # Main layout
|       +-- index.html           # Home page
|       +-- product.html         # Product page
|       +-- category.html        # Category page
|       +-- cart.html            # Cart
|       +-- order-*.html         # Checkout tunnel
|       +-- includes/            # Reusable fragments
|       +-- assets/              # CSS, JS, images
+-- backOffice/
    +-- default/
```

## URLs

```smarty
{url path="/cart"}                           {* Simple URL *}
{url path="/product" product_id=$ID}         {* With parameters *}
{url path="/product/%id" id=$PRODUCT_ID}     {* With placeholder *}
{url file="assets/img/logo.png"}             {* Static file *}
{url route_id="product.view" product_id=$ID} {* Named route *}

{navigate to="current"}     {* Current URL *}
{navigate to="previous"}    {* Previous page *}
{navigate to="index"}       {* Home *}
```

## Translations ({intl})

```smarty
{intl l="Add to cart"}                     {* Simple *}
{intl l="Welcome" d="fo.default"}          {* With domain *}
{intl l="Hello %name" name=$FIRSTNAME}     {* With variables *}
{intl l="Are you sure?" js=1}              {* JS escaping *}
{default_translation_domain domain='fo.default'} {* Default domain *}
```

## Formatting

```smarty
{* Prices *}
{format_money number=$TAXED_PRICE}
{format_money number=$PRICE currency_id=$CURRENCY_ID}
{format_money number="10.00" remove_zero_decimal=true}
{format_money number=$PRICE decimals="2" dec_point="," thousands_sep=" " symbol="EUR"}

{* Dates *}
{format_date date=$CREATE_DATE format="d/m/Y H:i"}
{format_date date=$CREATE_DATE output="date"}
{format_date date=$CREATE_DATE output="datetime"}

{* Numbers *}
{format_number number="1234.56" decimals="2" dec_point="," thousands_sep=" "}

{* Addresses *}
{format_address address=$ADDRESS_ID}
{format_address order_address=$ORDER_ADDRESS_ID html=true}
```

## Data accessors (substitutions)

```smarty
{cart attr="total_taxed_price"}    {* Cart: count_product, count_item, total_price, weight... *}
{customer attr="firstname"}        {* Customer: id, lastname, email, discount *}
{product attr="title"}             {* Product (in product context): id, ref, description *}
{category attr="title"}            {* Category (in category context): id, description *}
{config key="store_name"}          {* Config: store_email, etc. *}
{module_config module="Mod" key="k"} {* Module config *}
{lang attr="code"}                 {* Language: locale *}
{currency attr="symbol"}           {* Currency: code *}
{order attr="postage"}             {* Order: discount, delivery_address *}
{coupon attr="has_coupons"}        {* Coupons: coupon_count, is_delivery_free *}
```

## Loops ({loop})

### Basic syntax

```smarty
{loop type="product" name="products" category=$CATEGORY_ID visible="yes" limit="12"}
    <div class="product">
        <h3>{$TITLE}</h3>
        <p>{$CHAPO}</p>
        <span>{format_money number=$TAXED_PRICE}</span>
        <span>#{$LOOP_COUNT} of {$LOOP_TOTAL}</span>
    </div>
{/loop}
```

### Conditional loop

```smarty
{ifloop rel="products"}
    <h2>Our products</h2>
    {loop type="product" name="products" category=$ID}
        <div>{$TITLE}</div>
    {/loop}
{/ifloop}
{elseloop rel="products"}
    <p>No products available</p>
{/elseloop}
```

### Pagination

```smarty
{loop type="product" name="paginated" limit="10" page=$smarty.get.page|default:1}
    {* Content *}
{/loop}
{pageloop rel="paginated"}
    <a href="?page={$PAGE}" {if $PAGE == $CURRENT}class="active"{/if}>{$PAGE}</a>
{/pageloop}
```

## Forms

### Essential structure

```smarty
{form name="thelia.front.customer.login"}
<form action="{url path="/login"}" method="post">
    {form_hidden_fields}
    {if $form_error}<div class="alert alert-danger">{$form_error_message}</div>{/if}

    {form_field field="email"}
    <div class="form-group {if $error}has-error{/if}">
        <label for="{$name}">{$label} {if $required}*{/if}</label>
        <input type="email" name="{$name}" id="{$name}" value="{$value}" {if $required}required{/if}>
        {if $error}<span class="help-block">{$message}</span>{/if}
    </div>
    {/form_field}

    <button type="submit">{intl l="Login"}</button>
</form>
{/form}
```

`{form_field}` variables: `$name`, `$value`, `$label`, `$type`, `$required`, `$error`, `$message`, `$attr`, `$choices`, `$checked`.

## Hooks

```smarty
{* Simple hook *}
{hook name="product.top" product=$ID}
{hook name="main.head-bottom"}

{* Block hook *}
{hookblock name="product.additional" fields="id,class,title,content"}
    {forhook rel="product.additional"}
        <div id="{$id}"><h3>{$title}</h3><div>{$content nofilter}</div></div>
    {/forhook}
{/hookblock}

{* Conditional hook *}
{ifhook rel="product.gallery"}
    {hook name="product.gallery" product=$ID}
{/ifhook}
{elsehook rel="product.gallery"}
    <p>No gallery</p>
{/elsehook}
```

## Assets

```smarty
{stylesheets file='assets/css/style.css'}
    <link rel="stylesheet" href="{$asset_url}">
{/stylesheets}

{javascripts file='assets/js/script.js'}
    <script src="{$asset_url}"></script>
{/javascripts}

{images file='assets/img/logo.png'}
    <img src="{$asset_url}" alt="Logo">
{/images}
```

## Security

```smarty
{check_auth role="CUSTOMER" login_tpl="login.html"}
{check_auth role="ADMIN" resource="admin.customers" access="VIEW"}
{check_cart_not_empty}
{check_valid_delivery}
{token_url path="/cart/delete" item_id=$ITEM_ID}
```

## Smarty variables

```smarty
{$myVar = "value"}
{$smarty.get.page|default:1}
{$smarty.post.email}
{$smarty.session.customer_id}
{$variable|default:"default"}
{$html_content nofilter}

{if $condition}...{elseif $other}...{else}...{/if}
{foreach $items as $key => $item}{$key}: {$item}{foreachelse}None{/foreach}
```

## Anti-patterns

| Anti-pattern | Problem | Solution |
|---|---|---|
| Re-creating an existing template | Native template already available | Override in `templates/.../modules/MyModule/` |
| Forgetting nofilter | URLs and HTML escaped as `&amp;` | `{$URL nofilter}`, `{$DESCRIPTION nofilter}` |
| Forgetting form_hidden_fields | No CSRF protection | Always include `{form_hidden_fields}` in forms |
| Wrong name in ifloop | `rel="products"` vs `name="my_products"` | Use the same name in `rel` as in `name` |
| Business logic in template | Calculations, SQL queries in Smarty | Use loops or pass data from controller |
| Accessing $ID outside loop | Loop variable outside context | Loop variables are only available inside `{loop}...{/loop}` |
| Missing translation domain | Translations not found | `{intl l="..." d="mymodule"}` or `{default_translation_domain}` |

## Before writing a template

Check before creating any template:

1. Existing templates: is there a similar one? A native override? Reusable partials?
2. Available data: loops, substitutions (`{product}`, `{cart}`, ...), available hooks?
3. Project patterns: existing template structure, layout used, CSS/JS conventions?

## New template checklist

- [ ] Extend `layout.tpl` with `{extends}`
- [ ] Define the `{block name="main-content"}`
- [ ] Use `{intl}` for all text
- [ ] `{form_hidden_fields}` in forms
- [ ] `nofilter` on URLs and HTML
- [ ] `{ifloop}/{elseloop}` to handle empty lists
- [ ] Hooks at the right locations
- [ ] Assets via `{stylesheets}` / `{javascripts}`

---

## Complete substitution reference

### Cart

```smarty
{cart attr="count_product"}              {* Number of distinct products *}
{cart attr="count_item"}                 {* Total number of items *}
{cart attr="total_price"}                {* Total ex-tax *}
{cart attr="total_taxed_price"}          {* Total inc-tax *}
{cart attr="total_price_without_discount"} {* Before discount *}
{cart attr="total_tax_amount"}           {* Tax amount *}
{cart attr="weight"}                     {* Total weight *}
{cart attr="is_virtual"}                 {* Virtual cart *}
```

### Customer

```smarty
{customer attr="id"}
{customer attr="firstname"}
{customer attr="lastname"}
{customer attr="email"}
{customer attr="discount"}
```

### Product (in product context)

```smarty
{product attr="id"}
{product attr="ref"}
{product attr="title"}
{product attr="description"}
```

### Category (in category context)

```smarty
{category attr="id"}
{category attr="title"}
{category attr="description"}
```

### Configuration

```smarty
{config key="store_name"}
{config key="store_email" default="contact@example.com"}

{module_config module="MyModule" key="my_key" default=""}
```

### Language and currency

```smarty
{lang attr="code"}      {* fr, en... *}
{lang attr="locale"}    {* fr_FR, en_US... *}

{currency attr="code"}   {* EUR, USD... *}
{currency attr="symbol"} {* EUR, $... *}
```

### Order (checkout tunnel)

```smarty
{order attr="postage"}
{order attr="discount"}
{order attr="delivery_address"}
{order attr="delivery_module"}
```

### Coupons

```smarty
{coupon attr="has_coupons"}
{coupon attr="coupon_count"}
{coupon attr="is_delivery_free"}
```

---

## Common pitfalls: detailed examples

### Forgetting nofilter for HTML/URLs

```smarty
{* WRONG: escaped URL *}
<a href="{$URL}">

{* WRONG: escaped HTML *}
<div>{$DESCRIPTION}</div>
```

```smarty
{* CORRECT *}
<a href="{$URL nofilter}">
<div>{$DESCRIPTION nofilter}</div>
```

### Wrong loop name in ifloop

```smarty
{* WRONG *}
{loop type="product" name="my_products"}...{/loop}
{ifloop rel="products"}  {* wrong name *}

{* CORRECT *}
{loop type="product" name="my_products"}...{/loop}
{ifloop rel="my_products"}
```

### Forgetting form_hidden_fields

```smarty
{* WRONG: no CSRF token *}
{form name="thelia.front.contact"}
<form method="post">
    {* content *}
</form>
{/form}

{* CORRECT *}
{form name="thelia.front.contact"}
<form method="post">
    {form_hidden_fields}
    {* content *}
</form>
{/form}
```

### Accessing a variable outside context

```smarty
{* WRONG: $ID only exists inside a loop *}
{product attr="title"}  {* OK *}
{$ID}                   {* ERROR outside loop *}
```

### Missing translation domain

```smarty
{* WRONG: translation not found *}
{intl l="My text"}

{* CORRECT *}
{intl l="My text" d="mymodule"}

{* Or set the default domain at the top of the template *}
{default_translation_domain domain='fo.default'}
```

---

## Complete template examples

### Full form (login)

```smarty
{form name="thelia.front.customer.login"}
<form action="{url path="/login"}" method="post">
    {form_hidden_fields}

    {if $form_error}
        <div class="alert alert-danger">{$form_error_message}</div>
    {/if}

    {form_field field="email"}
    <div class="form-group {if $error}has-error{/if}">
        <label for="{$name}">{$label} {if $required}*{/if}</label>
        <input type="email" name="{$name}" id="{$name}"
               value="{$value}" class="form-control" {if $required}required{/if}>
        {if $error}
            <span class="help-block">{$message}</span>
        {/if}
    </div>
    {/form_field}

    {form_field field="password"}
    <div class="form-group">
        <label for="{$name}">{$label}</label>
        <input type="password" name="{$name}" id="{$name}" class="form-control">
    </div>
    {/form_field}

    <button type="submit" class="btn btn-primary">{intl l="Login"}</button>
</form>
{/form}
```

### {form_field} variables

| Variable | Description |
|---|---|
| `$name` | Field name |
| `$value` | Current value |
| `$label` | Label |
| `$type` | HTML type |
| `$required` | Required flag |
| `$error` | Error boolean |
| `$message` | Error message |
| `$attr` | HTML attributes |
| `$choices` | Select/radio options |
| `$checked` | Checkbox/radio state |

### Select with loop

```smarty
{form_field field="country_id"}
<select name="{$name}" class="form-control">
    <option value="">{intl l="Select..."}</option>
    {loop type="country" name="countries" visible="yes"}
        <option value="{$ID}" {if $ID == $value}selected{/if}>{$TITLE}</option>
    {/loop}
</select>
{/form_field}
```

### Field errors

```smarty
{form_error form=$form.email}
    <div class="error">{$message}</div>
{/form_error}
```

### Common loops

#### Categories

```smarty
{loop type="category" name="cats" parent="0" visible="yes"}
    <a href="{$URL nofilter}">{$TITLE}</a>
{/loop}
```

#### Product images

```smarty
{loop type="image" name="imgs" product=$ID width="300" height="300" resize_mode="crop"}
    <img src="{$IMAGE_URL nofilter}" alt="{$TITLE}">
{/loop}
```

#### Cart

```smarty
{loop type="cart" name="cart_items"}
    <tr>
        <td>{$TITLE}</td>
        <td>{$QUANTITY}</td>
        <td>{format_money number=$REAL_TOTAL_TAXED_PRICE}</td>
    </tr>
{/loop}
```

#### Product attributes

```smarty
{loop type="attribute_combination" name="attrs" product_sale_elements=$PSE_ID}
    {$ATTRIBUTE_TITLE}: {$ATTRIBUTE_AVAILABILITY_TITLE}
{/loop}
```

#### Features

```smarty
{loop type="feature_value" name="features" product=$ID}
    {$FEATURE_TITLE}: {$TITLE}
{/loop}
```

### Block hook

```smarty
{hookblock name="product.additional" fields="id,class,title,content"}
    {forhook rel="product.additional"}
        <div id="{$id}" class="{$class}">
            <h3>{$title}</h3>
            <div>{$content nofilter}</div>
        </div>
    {/forhook}
{/hookblock}
```

### Conditional hook

```smarty
{ifhook rel="product.gallery"}
    <div class="gallery">
        {hook name="product.gallery" product=$ID}
    </div>
{/ifhook}
{elsehook rel="product.gallery"}
    <p>No gallery</p>
{/elsehook}
```

### Pagination

```smarty
{loop type="product" name="paginated" limit="10" page=$smarty.get.page|default:1}
    {* Content *}
{/loop}

{pageloop rel="paginated"}
    {if $PAGE == $CURRENT}
        <span class="active">{$PAGE}</span>
    {else}
        <a href="?page={$PAGE}">{$PAGE}</a>
    {/if}
{/pageloop}
```

### Full template with loops, hooks, and formatting

```smarty
{default_translation_domain domain='mymodule.fo.default'}

{block name="main"}
    <h1>{intl l="Our products"}</h1>

    {loop type="category" name="categories" parent="0" visible="1"}
        <section class="category">
            <h2>{$TITLE}</h2>

            {loop type="product" name="products_{$ID}" category=$ID limit="4"}
                <article class="product">
                    <h3><a href="{$URL}">{$TITLE}</a></h3>

                    {loop type="image" name="product_img" product=$ID limit="1"}
                        <img src="{$IMAGE_URL}" alt="{$TITLE}" />
                    {/loop}

                    <p class="price">
                        {if $IS_PROMO}
                            <span class="old">{format_money number=$PRICE}</span>
                            <span class="promo">{format_money number=$PROMO_PRICE}</span>
                        {else}
                            {format_money number=$PRICE}
                        {/if}
                    </p>

                    {hook name="product.list.item" product=$ID}
                </article>
            {/loop}

            {ifloop rel="products_{$ID}"}
                <a href="{url path='/category' category_id=$ID}">{intl l="View all"}</a>
            {/ifloop}
            {elseloop rel="products_{$ID}"}
                <p>{intl l="No products"}</p>
            {/elseloop}
        </section>
    {/loop}
{/block}
```

### Essential Smarty helpers

```smarty
{intl l="Text to translate" d="mymodule.fo.default"}
{intl l="Hello %name!" name=$username}
{format_date date=$dateObject output="date"}
{format_number number="1246.12"}
{format_money number="1246.12"}
{url path="/product/{$ID}"}
{navigate to="product" product=$ID}
```
