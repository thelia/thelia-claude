#!/usr/bin/env bash
# Neutrality gate for the Thelia Claude plugin.
#
# Shared content must be useful to any Thelia developer in any future session,
# and free of session-specific or personal detail. This script fails (exit 1)
# if it finds contamination in the content that actually ships in the plugin.
#
# Run locally before opening a pull request:  bash scripts/check-neutrality.sh

set -uo pipefail

# Only the installable artifacts are scanned. Repo meta (README, CONTRIBUTING,
# this script) may legitimately describe the patterns below.
ROOTS=("plugins" ".claude-plugin")

PATTERNS=(
  '/home/|/Users/|~/\.claude'
  'Alexandre|anoziere|[Oo]pen[Ss]tudio'
  '\bESN\b'
  '/os-(feature|init|review|setup-project)\b'
  '\[\[[A-Za-z0-9_-]+\]\]'
  '\b(PAR|B)-[0-9]{2,}\b'
)

DESCRIPTIONS=(
  "absolute or personal filesystem paths"
  "personal or organization names"
  "internal ESN references"
  "coupling to private /os-* commands"
  "private memory cross-links"
  "internal backlog references (PAR-/B-)"
)

fail=0
for root in "${ROOTS[@]}"; do
  [ -e "$root" ] || continue
  for i in "${!PATTERNS[@]}"; do
    hits=$(grep -rnIE "${PATTERNS[$i]}" "$root" 2>/dev/null) || true
    if [ -n "$hits" ]; then
      echo "FAIL — ${DESCRIPTIONS[$i]}:"
      echo "$hits"
      echo
      fail=1
    fi
  done
done

if [ "$fail" -ne 0 ]; then
  echo "Neutrality check FAILED. See CONTRIBUTING.md for the rule."
  exit 1
fi

echo "Neutrality check passed."
