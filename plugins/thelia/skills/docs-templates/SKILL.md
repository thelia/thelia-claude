---
name: docs-templates
description: "Generate and structure technical documentation for PHP/Symfony/Thelia projects: project README, module README, CHANGELOG, REST API documentation, ADR (Architecture Decision Record). Use this skill when asked to: create a README, generate a CHANGELOG, document an API, write an ADR, structure documentation, use a documentation template, write markdown for a project, document a Thelia module, initialize README.md, apply Keep a Changelog format, document REST endpoints, record an architecture decision."
---

# Documentation Templates

## When to use this skill

Use this skill in any of these situations:
- Creating or updating a README (project or module)
- Generating a CHANGELOG in Keep a Changelog format
- Documenting REST API endpoints
- Writing an ADR (Architecture Decision Record)
- Structuring technical markdown documentation

## Quick Reference

| Type | Template | Reference file |
|------|----------|----------------|
| Project README | Standard structure with installation, usage, contribution | `references/template-readme-projet.md` |
| Thelia module README | Structure for modules with loops and hooks | `references/template-readme-module-thelia.md` |
| CHANGELOG | Keep a Changelog format + SemVer | `references/template-changelog.md` |
| API docs | REST endpoint documentation (Hydra/JSON-LD) | `references/template-api-docs.md` |
| ADR | Architecture Decision Record | `references/template-adr.md` |

## Required checks before writing documentation

Before creating any documentation, run these checks:

1. **Look for existing documentation** in the project: README, CHANGELOG, `docs/` folder.
2. **Identify conventions already in use**: format, language, existing templates.
3. **Inventory what needs documenting**: key features, API endpoints, CLI commands.
4. **Never rewrite existing documentation**: update it in place.

## Instructions by template type

### Project README
1. Read `references/template-readme-projet.md` for the full skeleton.
2. Fill every `{...}` placeholder with real project information.
3. Always include: prerequisites, installation, configuration, usage, tests.
4. Add a Contribution section if the project is open-source or collaborative.

### Thelia module README
1. Read `references/template-readme-module-thelia.md` for the full skeleton.
2. Document each loop with its arguments and output variables.
3. Document each hook with its type (front/back) and description.
4. Include a working Smarty example for each loop.

### CHANGELOG
1. Read `references/template-changelog.md` for the exact format.
2. Use only these categories: Added, Changed, Deprecated, Removed, Fixed, Security.
3. Link each version to a GitHub diff at the bottom of the file.
4. Keep the `[Unreleased]` section current with every change.

### API documentation
1. Read `references/template-api-docs.md` for the full structure.
2. Document authentication first (method, headers, token format).
3. For each endpoint: HTTP method, URL, query params, body, responses, errors.
4. Include working curl examples.

### ADR (Architecture Decision Record)
1. Read `references/template-adr.md` for the structure.
2. Number ADRs sequentially (ADR-001, ADR-002, ...).
3. Always fill in: Status, Context, Decision, Consequences.
4. Document at least two considered alternatives with reasons for rejection.

## Anti-patterns

| Anti-pattern | Fix |
|---|---|
| Rewriting existing documentation | Update in place, do not duplicate |
| Documentation without code examples | Always include concrete, working examples |
| CHANGELOG not kept up to date | Update with every release or notable change |
| Stale documentation left as-is | Revise with every major change |
| Too much detail in the README | Stay concise, link to detailed docs |
| Missing prerequisites | Always list PHP version, dependencies, tooling |

## Markdown best practices

- Use heading hierarchy `#`, `##`, `###` without skipping levels.
- Prefer `-` for unordered lists.
- Always specify the language in code blocks (` ```bash `, ` ```php `, ` ```json `).
- Align table columns for readability in source.
- Use `[text](url)` instead of bare URLs.
- Lead with the essentials: installation, then usage, then details.
- Prefer concrete examples over abstract explanations.

## References

- `references/template-readme-projet.md`: full project README template
- `references/template-readme-module-thelia.md`: Thelia module README template with loops and hooks
- `references/template-changelog.md`: CHANGELOG template in Keep a Changelog format
- `references/template-api-docs.md`: REST API documentation template
- `references/template-adr.md`: Architecture Decision Record template
