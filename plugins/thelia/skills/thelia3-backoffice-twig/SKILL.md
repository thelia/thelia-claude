---
name: thelia3-backoffice-twig
description: "Thelia 3 default-twig back-office: admin pages, thin controllers, the Repository plus Presenter pattern, hooks, forms scoped to /admin, the two-translator i18n, CSRF, Stimulus. Use when adding or changing an admin screen, or when a module must render in the Twig admin."
---

# Thelia 3 back-office (default-twig)

The default-twig theme is the Thelia 3 back-office, built on Symfony, Twig, and Bootstrap 5. Admin pages follow a thin-controller pattern and render through Twig templates and hooks. This skill covers how to add or change admin screens, render module hooks in the admin, handle i18n and CSRF, and the traps specific to the Twig back-office.

## Architecture

Controllers stay thin. They read input, call a service, and render a template. Queries and persistence live elsewhere.

- Propel queries go in `src/Repository/` classes, never in a controller or a template.
- Presentation logic (shaping data for Twig) goes in `src/Service/<Domain>/` presenters.
- Services and DTOs are `final readonly`.
- Prefer value objects and backed enums over primitives and string constants. Validate at the boundary (FormType, EventSubscriber) and fail fast in the domain.

For a filterable list page, a repeatable five-layer shape keeps it clean:

1. A `final readonly` Filters value object with `fromRequest()`, `applyTo($query)`, `toQueryParams()`, and `withoutFilter($key)`.
2. A Catalog service that loads the filter options, memoized per locale.
3. A Presenter that composes the value object and the Catalog into Twig-friendly arrays.
4. A Row presenter for each table row.
5. A thin controller that wires them together.

## Lists and tables

Every admin list, core or module, renders through the theme's `BoDataTable` component and, when it pages, `BoPagination`. The orders list (`order/list.html.twig`) is the reference: page header, GET search form, filter chips, table, pagination. A list built any other way (jQuery DataTables, a hand-written `<table>`, a CDN script) looks and behaves differently from the rest of the admin, and it is the first thing a reviewer will ask to redo.

Server side, not AJAX. The controller (or the hook, for a module configuration page) reads the filters, the sort and the page from the query string, runs one bounded query in a repository, and passes finished rows to the template. Search, filter, sort and page are links and GET forms, so every state of the list has a URL, survives a reload and works without JavaScript.

```twig
{{ component('BoDataTable', {
    id: 'gift-cards',
    columns: [
        column_html('code_html', 'Code / order'|trans, 'start', 'code'),
        column_html('customer_html', 'Customer'|trans, visibleFrom: 'lg'),
        column_html('amount_html', 'Amount'|trans, 'end', 'amount'),
        column_badge('status_code', 'Status'|trans, {active: 'success', inactive: 'secondary'}, labelKey: 'status_label'),
        column_actions('_actions', 'Actions'|trans),
    ],
    rows: rows,
    emptyMessage: 'No gift card matches the current filters.'|trans,
    sortField: sort.field,
    sortDirection: sort.direction,
    sortKeepParams: query_params,
}) }}
{{ component('BoPagination', {
    route: 'admin.module.configure',
    currentPage: page,
    lastPage: last_page,
    routeParams: { module_code: 'GiftCard' }|merge(query_params),
}) }}
```

- Columns come from the Twig helpers `column_text`, `column_html`, `column_badge`, `column_toggle`, `column_select`, `column_radio`, `column_position` and `column_actions`. Each takes a row key and a label. `sortKey` makes the header a sort link. `visibleFrom` hides a secondary column below a breakpoint, and its value moves into the row's expandable detail. Give the reference, the status and the actions no `visibleFrom`, so they stay visible on a phone.
- A row is a flat array keyed by column key, plus `id`. Build it in a row presenter, never in the template: dates and amounts are formatted there, in the interface locale.
- `column_text` escapes its value. `column_html` prints it raw, so every value inside it that comes from a customer or an admin goes through `htmlspecialchars()` in the presenter. Reach for `column_html` only for a link or an icon, and never put a name or a free text in it unescaped.
- A person (customer, buyer, recipient) is shown the way the orders list shows its customer, in every list: the flag of their country before the name in bold, the name linked to their account (route `admin.customer.update.view`, `customer_id` in the query string), and the email under it, small, muted and truncated (`<div class="fw-semibold">…</div><div class="text-muted small text-truncate">…</div>`, inside a `bo-order-customer` wrapper with a bounded `max-width`). The flag is `CountryFlag::prefix($isoAlpha2)` (`BackOfficeDefaultTwigBundle\Service\I18n`); a module calls it behind `class_exists()`, since the class belongs to the theme. Load the names, emails and countries of a page in one query per table, never one per row.
- Make the table fit a 1440 px screen, sidebar included: compare `scrollWidth` and `clientWidth` of the table wrapper in the browser. When it overflows, put a secondary value under the main one in the same cell (email under the name, amount spent under the amount, order under the code) instead of giving it a column. Keep the actions used on every visit inline (edit, send, the switch that activates or deactivates) and give the row no menu when they all fit; a menu holds only the rare actions. `visibleFrom: 'xxl'` does not help at that width.
- A choice of language in a row (a document per language, a preview) is a small button group, one button per active language, marked by the flag of the country of its locale (`fr_FR` gives FR) with the language name in its `title`; fall back to the language code when the locale has no country.
- An amount or a quantity with its unit takes `leftToRight: true`, or a right-to-left page splits it at its spaces; inside a `column_html` cell, wrap it in `<span dir="ltr">`. A free text written by a person takes `wrap: true`.
- A status is a `column_badge`: a variant per code, or a `colorKey` pointing to the stored color (order statuses). It is not a sentence in a text column.
- Row actions are a list of `RowAction` under the actions key, built in the presenter: `kind` picks the icon and the button style (`edit`, `delete`, `view`, `cancel`, `download`, `send` for an email, `activate` and `deactivate` for the switch of a row that is off or on, `custom`…; the list is `iconByKind` in `components/DataTable/cells/actions.html.twig`). An action whose kind is missing shows the three dots of `custom`: add the kind to the theme rather than living with a glyph that says nothing, `grantedAttribute` with `grantedSubject` hides an action the admin may not use, `disabledReason` shows it inert with the reason (better than hiding it), and `inMenu` or `inlineFrom` moves it into the row's menu.
- A `RowAction` is a link (`href`) or a modal opener (`modalTarget` plus `dataAttributes`). An action that changes state (activate, cancel, delete) is never a GET link: give it a modal whose form posts with the `_token`, and pass the target URL and the row label through `dataAttributes`, as the order cancel action does. The controller answers the form with a redirect to the list, keeping its query string.
- Sorting maps each allowed `sortKey` to a column in the repository. `ListSort::fromRequest($request, $allowedFields, $default)` rejects anything else, so a crafted `?order=` never reaches `orderBy()`. Pass the current filters as `sortKeepParams` and `routeParams`, or a sort click or a page link drops them.
- Bound the query: page size and offset always apply, the first page included. A missing limit loads the whole table on the first visit.
- The search form and the filter chips follow the orders list: one search field with Apply and Reset, chips for a few values (`btn-primary` when active, `btn-outline-secondary` otherwise), a collapsed advanced panel when there are more, and active filters shown as removable chips.
- In a module configuration page (the `module.configuration` hook), the same component works: the hook reads the request, calls the module's list service and renders the fragment with `rows`. Pagination and sort links point at the module configuration route, so the filters live in that page's query string.
- No jQuery, DataTables, select2 or flatpickr from a CDN: the theme ships none of them, and a CDN script breaks under a strict content security policy. A modal that must be filled from the server uses a small native script (`fetch`, `show.bs.modal` through `addEventListener`) and ignores a late answer for a row opened before. Use `type="date"` instead of a date picker.

## i18n: two translators

The back-office uses two translation systems at once, and you need to know which one applies to a given string.

- Twig `{{ '...'|trans }}` uses the Symfony translator, domain `messages`, loaded from `translations/messages.<locale>.php` (wired through `framework.translator.paths`).
- PHP `$this->translator->trans('...')` in presenters and forms uses the Thelia `Translator`, domain `core`, loaded by a `kernel.request` listener.

Both have to be populated to cover every string on a screen.

You get the second one by default, and not by choice: the core aliases `Symfony\Contracts\Translation\TranslatorInterface` to `Thelia\Core\Translation\Translator`, so a constructor that type-hints the interface is wired to Thelia's translator whatever the surrounding code looks like. That translator never loaded `translations/messages.<locale>.php`, so a key defined for the templates comes back unchanged from PHP. When a service needs the same catalog the templates use, ask for the Symfony translator explicitly:

```php
public function __construct(
    #[Autowire(service: 'translator')]
    private readonly TranslatorInterface $translator,
) {
}
```

Pitfalls:

- `|trans` resolves against the request locale, not the session or `default_locale`. A listener sets the request locale on `/admin` routes so the admin renders in the chosen language.
- `$this->defaultLocale()` returns the site default language, not the active UI locale. Use `$request->getLocale()` for anything that should follow the interface language.
- Naming a translation domain that is never loaded falls back silently to the key, which shows as English. Reusing a short key already defined higher in a catalog silently overrides it. Use specific keys.

### Module hooks in the back-office

A module hook template rendered in the admin has its `|trans` resolved by the Symfony translator, which has no module domains, so module labels show in English. Two ways to fix it:

- In the module, translate in PHP with the Thelia `Translator` and pass finished strings to the template.
- Project-wide, a `#[AsDecorator('translator')]` decorator (a module-aware translator) delegates non-standard domains to the Thelia `Translator` on `/admin`. That fixes every module hook's `|trans` without touching each module.

## Hooks

Register hooks with `getSubscribedHooks()`. Inject extra dependencies through the constructor, forwarding the parent arguments. Do not use `#[Required]` setters or properties: with autowiring they are silently left unwired, the dependency is null, `render()` throws, hook isolation swallows the exception, and you get a blank response.

Hook dispatch isolates each listener, so one listener that throws does not take down the others rendered at the same hook point.

## Forms

- When building a creation form, pass `'locale' => $request->getLocale()` (not the site default) and set `'visible' => true` explicitly. Otherwise new entities save with the default locale and `visible = 0` regardless of what the UI showed.
- When you render a field manually as raw HTML, Symfony does not know it was rendered, so `form_end()` outputs it a second time. Call `{% do form.X.setRendered %}` after the manual render.
- Theme each form explicitly; do not rely on a global theme. Neither theme registers itself globally any more: Flexy scopes its own widgets with `{% form_theme form with flexy_form_themes only %}` and the back-office does the same with its own list. A back-office form with no `form_theme` tag therefore falls back to Symfony's bare default, not to Bootstrap. Opt in per form root with `{% form_theme form with bo_form_themes only %}`, where `bo_form_themes` is a Twig global listing `bootstrap_5_layout.html.twig` (the Bootstrap base) then `@BackOfficeDefaultTwigForm/bo_form_theme.html.twig` (the back-office overrides). The back-office theme file holds only the back-office refinements (label, row spacing, checkbox); everything else comes from `bootstrap_5_layout`.
- Place the `{% form_theme %}` tag inside the rendered block (typically `{% block content %}`), right before `form_start`. A `{% form_theme %}` outside any block in a template that uses `{% extends %}` is silently ignored by Twig. One tag per form view; it propagates to the field partials you include with `{% include ... with {form: form} %}`.
- Do not write `{% form_theme form '@BackOfficeDefaultTwigForm/bo_form_theme.html.twig' only %}` (a single theme): it throws a 500 (`getTemplateClass(): ... null given`) on `form_start`, because `{% use %}` is not transitive enough under `only` and there is no global fallback. Always list `bootstrap_5_layout.html.twig` first, which is exactly what the `bo_form_themes` global does.
- Module form extensions that add fields through `FORM_BEFORE_BUILD` and `FORM_AFTER_BUILD` events are dead in a Symfony-native form unless a bridge dispatches those legacy events after `createNamed()`. Module-added fields are then rendered by the module's own hook, not by `form_rest`, and `form_end` uses `{render_rest: false}`.

## CSRF

`Thelia\Tools\TokenProvider` produces a stable token per session: it reads the token from the session in its constructor and generates one only if it is absent. Do not refresh the token after a page has rendered tokenized links, or those links stop matching. The action that validates a token reads `_token` from the query string, so a form that posts `_token` in the body must be read body-first, then query.

Diagnosis: if every `_token` in the DOM is consistent but a click still fails, the session changed between render and click.

## Templates

- A controller that renders a template from inside the bundle must use the full namespaced path, for example `@BackOfficeDefaultTwig/base.html.twig`. The bundle prefix is not implied, and an unqualified `extends` throws a loader error.
- `render(controller('Ctrl::action', {x: v}))` passes `x` as a request attribute, not a query parameter. Read it through a typed method argument, not `$request->query->get('x')`.
- A default-twig template cannot be replaced by a child back-office theme or by `templates/bundles/`. The bundle and its compiler pass switch on only when `active-admin-template` is exactly `default-twig` (`BackOfficeDefaultTwigBundle::isActive()`), so a child theme turns the whole back office off; `templates/bundles/BackOfficeDefaultTwigBundle/` is read after the theme directory (`debug:twig @BackOfficeDefaultTwig/<template>` lists it under "Overridden Files"). The working route is a compiler pass in a project module that calls `prependPath()` on `twig.loader.native_filesystem` for the `BackOfficeDefaultTwig` namespace. Keep it for screens that must differ from the theme; prefer a hook or an upstream change.
- `{% embed ... only %}` drops the parent context inside the embedded blocks. If a variable is missing in a header partial, check the `with {}` of the embed before suspecting config or the database.

## Edit screens

- Selection dropdowns (category, brand, parent) use the UI interface locale, `$request->getLocale()`. Only the content being edited (title, description) follows the edit locale. A front-office preview link uses the edit locale.
- Twig removed the `{% for x in y if cond %}` form. Use `y|filter(x => cond)`.

## JavaScript

- Thelia exposes locale codes with an underscore (`fr_FR`), but the browser `Intl` API expects a dash (`fr-FR`). Call `.replace('_', '-')` before constructing an `Intl` object.
- If the admin path is obfuscated, JavaScript that builds the admin URL from the literal string `/admin` breaks. Build the path at runtime or read a server-injected value.
- Do not pass a human-readable type string as a route parameter when the route has a regex constraint. Use a valid real value, then do a JavaScript string replacement bounded by slashes.

## Security

The login page returns a generic "Invalid credentials" message. Never distinguish an unknown username from a wrong password: that enables user enumeration.

## CSS and Stimulus pitfalls

- Bootstrap's `offcanvas-md` / `-lg` / `-sm` utility forces a transparent background at and above its breakpoint; an element that needs its own background must redeclare `--bs-offcanvas-bg` there.
- A Bootstrap reboot rule can beat a `.btn` variant at equal specificity by source order and render a solid button transparent. Raise the selector (`button.btn-primary`) instead of reordering imports.
- A modal placed outside the element carrying `data-controller` has no working `data-action` or `data-target`: Stimulus wires descendants only. Move the modal inside the controller's element or give it its own controller.
- Information that must be readable from every admin screen belongs in the top bar. Nothing in the layout is `position: sticky`, so a footer scrolls out of view.

## Routing between two back-office bundles

When the legacy Smarty bundle and the Twig bundle both register a route under the same name, matching favors the Twig router but `path()` generation favors the legacy definition. Reuse the legacy path verbatim when porting a route, or generated links point at the old controller.

## Hooks: more rules

- `hook_cards(name|[names], params)` wraps each module's contribution to a hook point in its own titled card. Use it where several modules stack on one point; never on JavaScript, menu or tab-content hooks.
- A module configuration page registers through the module-configuration hook point and is gated by a capability check; the module must be reactivated after the hook class is added, or it never registers.
- With both admin bundles active, a mutable "current parser" static can be overwritten by whichever bundle renders first; a later Twig hook fragment then resolves through the Smarty parser and renders empty. Prefer a Twig-only admin for any rendering diagnosis.
- A new `|trans` key needs its translation in the same commit. A missing key falls back to the raw key with no error.
- `safe_hook()` swallows the errors of its listeners (it isolates each listener, so one faulty module, for instance one whose Propel models were never generated, only loses its own fragment). An empty zone with no error on screen means a listener failed: read `var/log`, then switch the call to `hook()` once the module is ported.

## Tests against the Twig back office

- The core CI never compiles the back-office theme's assets. An HTTP test on an admin page must guard on asset presence (`assertPageRenders()` or the equivalent helper) before asserting content; a raw `200` assertion breaks on the first theme release that changes an asset name.
- The `test` environment can default the admin template to the legacy Smarty theme; the Twig routes then never register and a test hitting one gets `404` instead of `403` or `302`. Assert on the exact expected status, and check which template the test kernel activates before reading a `404` as a routing bug.
- Open every creation modal full-page as well as inline, then diff submitted versus stored values. A modal can leave a field orphaned or overwrite a default with no visible symptom in the list view.
- The admin login is scriptable end to end with curl (form login, then the session cookie); the JSON admin API login is a separate endpoint. Negative tests on a restricted admin need a profile row with a reduced permission bitmask.
