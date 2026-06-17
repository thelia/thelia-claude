# Thelia Claude

Claude Code plugins for working on [Thelia](https://thelia.net), the open-source PHP e-commerce framework.

This repository is a Claude Code marketplace. It ships one plugin, `thelia`, which teaches Claude Code how Thelia 3 works: building modules, Propel ORM, the API Platform bridge, the Flexy front-office, the default-twig back-office, and porting modules from Thelia 2.

## Install

```
/plugin marketplace add thelia/thelia-claude
/plugin install thelia
```

Then work in a Thelia project as usual. Skills load on their own when they fit what you ask, and the agents are available to Claude's `Agent` tool.

## What's inside

Two kinds of thing. Skills are reference knowledge Claude pulls in when it fits the task: Propel patterns, module structure, the API Platform bridge, back-office theming, migration playbooks, project tooling. Agents are subagents that explore a Thelia codebase or review changes.

Both are discovered automatically from the plugin directory, so the catalogue can grow without touching any config.

## Contributing

The plugin is only worth installing if what it holds stays reusable. One rule decides what goes in: it has to help any Thelia developer in any future session, with nothing tied to a specific machine, task, or conversation. A CI check enforces it.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[GPL-3.0](LICENSE), same as Thelia.
