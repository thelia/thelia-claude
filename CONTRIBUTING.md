# Contributing

`thelia-claude` turns lessons from real Thelia work into knowledge that anyone's Claude Code can reuse. That only holds up if what we add stays reusable.

## The one rule

**Everything shared must help any Thelia developer in any future session, with nothing in it tied to a specific person, machine, task, or conversation.**

The test for a sentence you want to add:

> Is this true for the next developer on a fresh clone, no matter what happened in my own sessions?

If yes, it belongs. If it only makes sense with the context you happened to have, it does not.

## What never goes in

A CI check (`scripts/check-neutrality.sh`) fails the build on these. It scans `plugins/` and `.claude-plugin/`.

- Absolute or personal filesystem paths (home directories, user-config locations, temporary working files)
- Personal names, company names, or client names
- Dates and session markers (a skill is a fact, not a journal)
- Internal backlog or ticket references
- Links to a private memory store
- Coupling to private slash commands or a personal model-routing strategy

Two more the check cannot catch, so watch for them yourself:

- Volatile specifics that rot: exact dependency versions, test counts, "new in version X" framing. Describe the behavior and anchor on stable concepts. Name a version only when the version is the actual point.
- Implementation trivia that only mattered for one screen. Pull out the pattern that travels and drop the rest.

## How it's organized

- `plugins/thelia/skills/<name>/SKILL.md`: knowledge Claude loads on demand. The `description` in the frontmatter is the trigger, so write it to match the situations where the knowledge helps.
- `plugins/thelia/agents/<name>.md`: subagents.
- `plugins/thelia/commands/<name>.md`: slash commands.

Skills and agents are discovered automatically, so there is no index to keep in sync.

## Adding a lesson

1. Decide where it belongs. A Propel gotcha goes in the Propel skill, a back-office pattern in the back-office skill. Fold it into an existing file rather than starting a new one when you can.
2. Write the durable fact in neutral form. Keep the principle, drop the story.
3. Run the check locally: `bash scripts/check-neutrality.sh`.
4. Open a pull request. CI runs the neutrality and manifest checks, then a maintainer reads it for accuracy and reuse.

## Quality bar

Keep it short. The code is the documentation, and a skill only adds what the code cannot say for itself. Make sure it is accurate against the current Thelia branch, and if you are not sure a claim still holds, check before you add it. Write plainly, so the prose reads like a person wrote it and not a template.
