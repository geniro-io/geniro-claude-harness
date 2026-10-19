#!/usr/bin/env bash
# Guards markdown link targets.
#
# Run: bash tests/authoring/lint-prose-and-links.sh
#
# Why this exists: link rot has an objective answer and was being found by
# reading instead of by CI, so every audit round rediscovered it, and the
# round's own fixes seeded the next round's dangling references.
#
# Coverage: every markdown link to a local path resolves (HARD).
#
# What this deliberately does NOT check: terminology or heading case. Both were
# built and measured; a terminology table on a corpus whose vocabulary is already
# consistent cannot find drift, it can only manufacture it, and half this corpus's
# Title-Case headings are literal contract tokens a spec is parsed for.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# --- 1. Local link targets resolve -------------------------------------------
#
# Path-shaped targets only. This corpus embeds regular expressions inside
# bracket-paren pairs (`(recharts|chart\.js|monaco)` in a review criterion), and
# those parse as links to anything that scans for `](...)`. A target carrying an
# alternation, a backslash escape, or a space is not a path and is not this
# check's business.
_is_pathish() {
  case "$1" in
    *'|'*|*'\'*|*' '*|*'*'*|*'$'*) return 1 ;;
    */*) return 0 ;;
    *.md|*.sh|*.js|*.json|*.txt|*.yml|*.yaml) return 0 ;;
    *) return 1 ;;
  esac
}

links_checked=0
while IFS= read -r file; do
  [ -f "$file" ] || continue
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    target="${raw%%#*}"          # drop the anchor; the file is what must exist
    [ -n "$target" ] || continue
    case "$target" in
      http://*|https://*|mailto:*|'<'*) continue ;;
    esac
    _is_pathish "$target" || continue
    links_checked=$((links_checked + 1))
    [ -e "$(dirname "$file")/$target" ] && continue
    [ -e "$target" ] && continue
    report_fail "$file links to $target — no such file"
  done < <(grep -oE '\]\([^)]+\)' "$file" 2>/dev/null | sed 's/^](//; s/)$//' || true)
done < <(git ls-files '*.md' 2>/dev/null)
[ "$FAILS" -eq 0 ] && echo "OK: all $links_checked local markdown links resolve"

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS broken local link(s)." >&2
  exit 1
fi
echo "OK: local links resolve."
