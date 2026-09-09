---
name: thelia3-backoffice-twig
description: Build and theme the Thelia 3 default-twig back-office. Use when adding or changing admin pages, controllers, hooks, forms, i18n, CSRF, or Stimulus behavior in the Twig back-office, or when a module needs to render correctly in the Twig admin. Covers thin-controller architecture, the Repository plus Service/Presenter pattern, the two-translator i18n mechanism, hook registration and rendering, form theming scoped to /admin, CSRF tokens, and the pitfalls specific to the Twig admin.
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

## Tests against the Twig back office

- The core CI never compiles the back-office theme's assets. An HTTP test on an admin page must guard on asset presence (`assertPageRenders()` or the equivalent helper) before asserting content; a raw `200` assertion breaks on the first theme release that changes an asset name.
- The `test` environment can default the admin template to the legacy Smarty theme; the Twig routes then never register and a test hitting one gets `404` instead of `403` or `302`. Assert on the exact expected status, and check which template the test kernel activates before reading a `404` as a routing bug.
- Open every creation modal full-page as well as inline, then diff submitted versus stored values. A modal can leave a field orphaned or overwrite a default with no visible symptom in the list view.
- The admin login is scriptable end to end with curl (form login, then the session cookie); the JSON admin API login is a separate endpoint. Negative tests on a restricted admin need a profile row with a reduced permission bitmask.
