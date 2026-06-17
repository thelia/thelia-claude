# Thelia Module README Template

```markdown
# {ModuleName}

{Description}

## Compatibility

- Thelia {2.x | 3.x}
- PHP {version}+

## Installation

```bash
php Thelia module:activate {ModuleName}
php Thelia cache:clear
```

## Configuration

Go to **Configuration > Modules > {ModuleName}**

| Parameter | Description |
|-----------|-------------|
| {param} | {description} |

## Loops

### `{loop_name}`

| Argument | Type | Description |
|----------|------|-------------|
| `id` | int | Filter by ID |
| `visible` | bool | Filter by visibility |

| Variable | Description |
|----------|-------------|
| `$ID` | Identifier |
| `$TITLE` | Title |

**Example:**

```smarty
{loop type="{loop_name}" name="my_loop" visible="1"}
    {$TITLE}
{/loop}
```

## Hooks

| Hook | Type | Description |
|------|------|-------------|
| `{hook.name}` | front/back | {description} |

## Changelog

### 1.0.0
- Initial release
```
