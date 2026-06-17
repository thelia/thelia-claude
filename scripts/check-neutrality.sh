#!/usr/bin/env bash
# Neutrality gate for the Thelia Claude plugin.
#
# Shared content must be useful to any Thelia developer in any future session,
# and free of session-specific or personal detail. This script fails (exit 1)
# if it finds contamination in the content that ships in the plugin (the
# `plugins/` and `.claude-plugin/` trees).
#
# It checks two layers, so this script itself stays neutral and publishable:
#   1. Generic patterns below. They name no person, company, or private setup.
#   2. Optional project denylist patterns supplied from outside this file:
#        - the NEUTRALITY_EXTRA_PATTERNS environment variable (one regex per line)
#        - a local, git-ignored file: .neutrality-denylist.local (one regex per line)
#      Maintainers keep their own name, organization, private commands, and
#      ticket prefixes there. None of that belongs in this committed script.
#
# Run locally before opening a pull request:  bash scripts/check-neutrality.sh

set -uo pipefail

ROOTS=("plugins" ".claude-plugin")

# Generic, identity-free contamination patterns (extended regex).
GENERIC_PATTERNS=(
  '/home/|/Users/'
  '~/\.claude|\.claude/projects/'
  '\[\[[A-Za-z0-9_-]+\]\]'
)
GENERIC_DESCRIPTIONS=(
  "absolute or personal home paths"
  "personal Claude config or memory paths"
  "private memory cross-links"
)

# Optional project-specific denylist, loaded from outside this script.
EXTRA_PATTERNS=()
add_extra() { [ -n "$1" ] && [[ "$1" != \#* ]] && EXTRA_PATTERNS+=("$1"); }
if [ -n "${NEUTRALITY_EXTRA_PATTERNS:-}" ]; then
  while IFS= read -r line || [ -n "$line" ]; do add_extra "$line"; done <<< "${NEUTRALITY_EXTRA_PATTERNS}"
fi
if [ -f ".neutrality-denylist.local" ]; then
  while IFS= read -r line || [ -n "$line" ]; do add_extra "$line"; done < ".neutrality-denylist.local"
fi

fail=0
scan() { # $1 pattern, $2 description
  local hits
  for root in "${ROOTS[@]}"; do
    [ -e "$root" ] || continue
    hits=$(grep -rnIE "$1" "$root" 2>/dev/null) || true
    if [ -n "$hits" ]; then
      echo "FAIL — $2:"
      echo "$hits"
      echo
      fail=1
    fi
  done
}

for i in "${!GENERIC_PATTERNS[@]}"; do
  scan "${GENERIC_PATTERNS[$i]}" "${GENERIC_DESCRIPTIONS[$i]}"
done
for pat in "${EXTRA_PATTERNS[@]}"; do
  scan "$pat" "project-specific denylist match"
done

if [ "$fail" -ne 0 ]; then
  echo "Neutrality check FAILED. See CONTRIBUTING.md for the rule."
  exit 1
fi

echo "Neutrality check passed."
