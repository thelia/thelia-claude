---
name: symfony-ux
description: "Symfony UX frontend stack combining Stimulus, Turbo, TwigComponent and LiveComponent. Builds reactive server-rendered UIs with minimal JavaScript. Use when choosing between UX tools, creating interactive components, handling partial page updates, real-time updates, or combining multiple UX packages. Relevant to Thelia 3's Flexy front-office (AsLiveComponent, AsTwigComponent, LiveProp, LiveAction, resources(), attr() Twig helpers). Triggers on: symfony ux, stimulus, turbo, live component, twig component, data-controller, data-action, data-model, turbo-frame, turbo-stream, AsLiveComponent, AsTwigComponent, LiveProp, LiveAction, frontend symfony, interactive ui, SPA feel, reactive component, server-rendered component, Mercure, real-time update, which ux package, how to make this interactive. Do NOT trigger for pure backend PHP/Symfony questions without frontend context."
---

# Symfony UX

Modern frontend stack for Symfony. Build reactive UIs with minimal JavaScript using server-rendered HTML.

Philosophy: start with plain HTML, add interactivity only where needed, prefer server-side rendering over client-side JavaScript. Each tool solves a specific problem, so pick the simplest one that fits.

## Decision Tree: Which Tool?

```
Need frontend interactivity?
|
+-- Pure JavaScript behavior (no server)?
|   -> Stimulus
|      (DOM manipulation, event handling, third-party libs)
|
+-- Navigation / partial page updates?
|   -> Turbo
|      +-- Full page AJAX        -> Turbo Drive (automatic, zero config)
|      +-- Single section update  -> Turbo Frame
|      +-- Multiple sections      -> Turbo Stream (HTTP response)
|      +-- Real-time from server  -> Turbo Stream + Mercure (SSE)
|
+-- Reusable UI component?
|   |
|   +-- Static (no live updates)?
|   |   -> TwigComponent
|   |      (props, blocks, computed properties, anonymous components)
|   |
|   +-- Dynamic (re-renders on interaction)?
|       -> LiveComponent
|          (data binding, actions, forms, real-time validation)
|
+-- Combination needed?
    -> They compose naturally (see Combining Tools below)
```

## Quick Comparison

| Feature | Stimulus | Turbo | TwigComponent | LiveComponent |
|---------|----------|-------|---------------|---------------|
| JavaScript required | Yes (minimal) | No | No | No |
| Server re-render | No | Yes (page/frame) | No | Yes (AJAX) |
| State management | JS only | URL/Server | Props (immutable) | LiveProp (mutable) |
| Two-way binding | Manual | No | No | data-model |
| Input validation modifiers (2.28+) | n/a | n/a | n/a | `min_length(3)`, `max_value(999)` |
| Route param binding (2.25+) | n/a | n/a | n/a | `#[LiveProp(fromUrl: true)]` |
| Multi-step form (Sf 7.4 form flows) | n/a | n/a | n/a | Native via `ComponentWithFormTrait` |
| Real-time capable | Manual | Yes (Streams+Mercure) | No | Yes (polling/emit) |
| Lazy loading | Yes (stimulusFetch) | Yes (lazy frames) | No | Yes (defer/lazy) |

## Installation

```bash
# All core packages
composer require symfony/ux-turbo symfony/stimulus-bundle \
    symfony/ux-twig-component symfony/ux-live-component

# Individual
composer require symfony/stimulus-bundle      # Stimulus
composer require symfony/ux-turbo             # Turbo
composer require symfony/ux-twig-component    # TwigComponent
composer require symfony/ux-live-component    # LiveComponent (includes TwigComponent)
```

## Common Patterns

### Pattern 1: Static Component (TwigComponent)

Reusable UI with no interactivity. Use for buttons, cards, alerts, badges.

```php
#[AsTwigComponent]
final class Alert
{
    public string $type = 'info';
    public string $message;
}
```

```twig
{# templates/components/Alert.html.twig #}
<div class="alert alert-{{ type }}" {{ attributes }}>{{ message }}</div>
```

```twig
<twig:Alert type="success" message="Saved!" />
```

### Pattern 2: Component with JS Behavior (TwigComponent + Stimulus)

Server-rendered component with client-side interactivity (toggling, animations, third-party libs).

```twig
{# templates/components/Dropdown.html.twig #}
<div data-controller="dropdown" {{ attributes }}>
    <button data-action="click->dropdown#toggle">{{ label }}</button>
    <div data-dropdown-target="menu" hidden>
        {% block content %}{% endblock %}
    </div>
</div>
```

### Pattern 3: Server-Reactive Component (LiveComponent)

Re-renders via AJAX on user input. Use for search, filters, forms with real-time validation.

```php
#[AsLiveComponent]
final class SearchBox
{
    use DefaultActionTrait;

    #[LiveProp(writable: true, url: true)]
    public string $query = '';

    public function __construct(
        private readonly ProductRepository $products,
    ) {}

    public function getResults(): array
    {
        return $this->products->search($this->query);
    }
}
```

```twig
<div {{ attributes }}>
    <input data-model="debounce(300)|query" placeholder="Search...">
    <div data-loading="addClass(opacity-50)">
        {% for item in this.results %}
            <div>{{ item.name }}</div>
        {% endfor %}
    </div>
</div>
```

### Pattern 4: Frame-Based Navigation (Turbo Frame)

Partial page updates without full reload. Use for pagination, inline editing, tabbed content.

```twig
<turbo-frame id="product-list">
    {% for product in products %}
        <a href="{{ path('product_show', {id: product.id}) }}">{{ product.name }}</a>
    {% endfor %}
</turbo-frame>
```

### Pattern 5: Multi-Section Update (Turbo Stream)

Update multiple page areas from a single server response.

```twig
{# create.stream.html.twig #}
<turbo-stream action="append" target="comments">
    <template>{{ include('comment/_comment.html.twig') }}</template>
</turbo-stream>
<turbo-stream action="update" target="comment-count">
    <template>{{ count }}</template>
</turbo-stream>
```

### Pattern 6: LiveComponent Inside Turbo Frame

Combine for complex UIs: the frame scopes navigation, and LiveComponent handles reactivity.

```twig
<turbo-frame id="search-section">
    <twig:ProductSearch />
</turbo-frame>
```

### Pattern 7: Real-Time Updates (Mercure + Turbo Stream)

Broadcast server-side events to all connected browsers via SSE.

```twig
<turbo-stream-source src="{{ mercure('chat')|escape('html_attr') }}"></turbo-stream-source>
<div id="messages">...</div>
```

## When to Use What (Summary)

- **Stimulus**: JS behavior on existing HTML, third-party libs, client-only interactions
- **Turbo Drive**: SPA-like navigation (automatic, zero config)
- **Turbo Frames**: Loading/updating a single page section
- **Turbo Streams**: Updating multiple sections, real-time broadcasts (with Mercure)
- **TwigComponent**: Reusable UI elements (buttons, cards, alerts), no server interaction after render
- **LiveComponent**: Forms with validation, search with live results, data binding, any reactive UI

## Combining Tools

```
Page
  Turbo Drive (automatic full-page AJAX)
    Turbo Frame (partial section)
      LiveComponent (reactive)
        TwigComponent (static)
          + Stimulus (JS behavior)
```

## File Structure

```
src/Twig/Components/
    Alert.php              # TwigComponent
    SearchBox.php          # LiveComponent

templates/components/
    Alert.html.twig
    SearchBox.html.twig

assets/controllers/
    dropdown_controller.js # Stimulus
    modal_controller.js    # Stimulus
```

## Anti-Patterns

| Anti-pattern | Solution |
|--------------|----------|
| LiveComponent for static content | Use TwigComponent (no AJAX overhead) |
| Turbo Streams when Frame is enough | Use Turbo Frame (simpler, one section) |
| Stimulus for link/form AJAX | Turbo Drive handles it automatically |
| Fighting Turbo Drive | Ensure server returns full HTML page |
| Mega LiveComponent with many props | Split into smaller components, use emit/listen |
| Missing `{{ attributes }}` on root | Required for LiveComponent and TwigComponent |
| Every keystroke triggers re-render | Use `debounce(300)` or `on(blur)` on data-model |

## References

For detailed documentation on each tool, read the relevant reference:

- `references/stimulus.md`: Controllers, targets, values, actions, outlets, lazy loading, Twig integration
- `references/turbo.md`: Drive, Frames, Streams, Mercure integration, Symfony controller patterns
- `references/twig-component.md`: Props, blocks/slots, computed properties, anonymous components, attributes, lifecycle hooks
- `references/live-component.md`: LiveProp, LiveAction, data-model, forms, emit/listen, polling, defer/lazy, loading states
