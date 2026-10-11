#!/usr/bin/env bash
# Description length gate for the Thelia Claude plugin.
#
# Claude Code lists every installed skill with its description in each session,
# under a budget shared by all plugins. Past that budget it drops descriptions,
# and a skill listed by name only no longer triggers on its own. Long keyword
# lists cost more than they help, so every description stays under the limit.
#
# Run locally before opening a pull request:  bash scripts/check-skill-descriptions.sh

set -uo pipefail

MAX_CHARS=350
status=0

for file in plugins/*/skills/*/SKILL.md; do
  [ -f "$file" ] || continue
  # Frontmatter only: a single-line description, or a folded/literal block (> or |)
  # whose indented lines are joined with a space.
  description=$(awk '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    !inside { exit }
    block && /^[ \t]/ { sub(/^[ \t]+/, ""); text = text (text == "" ? "" : " ") $0; next }
    block { block = 0 }
    /^description:/ {
      value = $0
      sub(/^description:[ \t]*/, "", value)
      if (value ~ /^[>|][-+]?$/) { block = 1; next }
      text = value
    }
    END { print text }
  ' "$file")
  description="${description#\"}"; description="${description%\"}"
  description="${description#\'}"; description="${description%\'}"

  if [ -z "$description" ]; then
    echo "FAIL $file: no description in the frontmatter"
    status=1
    continue
  fi
  # UTF-8 characters, independent of the locale: bytes minus continuation bytes.
  chars=$(printf '%s' "$description" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' ')
  if [ "$chars" -gt "$MAX_CHARS" ]; then
    echo "FAIL $file: description is $chars characters (at most $MAX_CHARS)"
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "All skill descriptions are at most $MAX_CHARS characters."
fi
exit "$status"
