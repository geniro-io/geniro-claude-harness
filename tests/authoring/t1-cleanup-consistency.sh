#!/usr/bin/env bash
# T1 cleanup-consistency lint — asserts the Ship-cleanup rm list covers every
# T1 transient file the canonical tier spec declares.
#
# Run: bash tests/authoring/t1-cleanup-consistency.sh
#
# Contract under test (two files edited independently, drifted in the past —
# the rm list silently omitted .research-out.md / .research-<facet>.md):
#   SOURCE   skills/_shared/state-tier-spec.md
#            §"T1 — ephemeral transient outputs" table — the canonical list of
#            `.geniro/planning/<task-dir>/<name>` transient files.
#   COVERAGE skills/implement/implement-reference.md
#            §Cleanup `rm -f` fenced block — the executor's delete list of
#            `"<task-dir>"/<entry>` tokens.
# Every T1 basename in the spec table must match at least one rm entry, either
# literally or via shell glob (e.g. `.research-*.md` covers `.research-out.md`
# and the per-facet `.research-<facet>.md`). Placeholder forms like `<facet>`
# are normalized to a representative concrete sample before matching.
#
# Contract-driven: both lists are parsed from the live files (no hardcoded
# basenames), so the test guards future drift in either direction. Empty parse
# results hard-fail — a moved heading or reworded anchor must surface as a
# failure, never as a silent pass.
#
# Portability: bash 3.2 (no associative arrays / mapfile), BSD/GNU-neutral
# grep/sed/awk (no -P), read-only (no writes anywhere).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

SPEC_FILE="skills/_shared/state-tier-spec.md"
RM_FILE="skills/implement/implement-reference.md"

HARD_FAILS=0
report_fail() { HARD_FAILS=$((HARD_FAILS + 1)); echo "FAIL: $1" >&2; }

for f in "$SPEC_FILE" "$RM_FILE"; do
  if [ ! -f "$f" ]; then
    report_fail "missing contract file: $f"
  fi
done
if [ "$HARD_FAILS" -gt 0 ]; then
  echo "Hard failures: $HARD_FAILS"
  exit 1
fi

# --- 1. Canonical T1 basenames from the tier spec -------------------------
# Scope to the §"T1 — ephemeral transient outputs" section only (from its
# heading to the next ###/## heading), then pull the
# `.geniro/planning/<task-dir>/<basename>` path cells out of the table rows.
# Anchoring on the path prefix keeps the parser tolerant of pipes, backticks,
# and cell spacing.
t1_section=$(awk '
  /^### T1 .*ephemeral transient outputs/ { in_t1 = 1; next }
  in_t1 && (/^### / || /^## /) { exit }
  in_t1 { print }
' "$SPEC_FILE")

spec_basenames=$(printf '%s\n' "$t1_section" \
  | grep -oE '\.geniro/planning/<task-dir>/[A-Za-z0-9._<>-]+' \
  | sed -E 's#^\.geniro/planning/<task-dir>/##' \
  | sort -u)

if [ -z "$spec_basenames" ]; then
  report_fail "parsed zero T1 paths from $SPEC_FILE §\"T1 — ephemeral transient outputs\" — section heading or path prefix drifted; fix this parser's anchors"
fi

# --- 2. rm entries from the implement-reference Cleanup block --------------
# First fenced bash block after the ### Cleanup heading is the Ship rm list.
rm_block=$(awk '
  /^### Cleanup/ { in_sec = 1; next }
  in_sec && !in_block && (/^### / || /^## /) { exit }
  in_sec && /^```bash/ { in_block = 1; next }
  in_block && /^```/ { exit }
  in_block { print }
' "$RM_FILE")

rm_entries=$(printf '%s\n' "$rm_block" \
  | grep -oE '"<task-dir>"/[A-Za-z0-9._*?-]+' \
  | sed -E 's#^"<task-dir>"/##' \
  | sort -u)

if [ -z "$rm_entries" ]; then
  report_fail "parsed zero rm entries from $RM_FILE §Cleanup rm-f block — heading, fence tag, or \"<task-dir>\"/ token shape drifted; fix this parser's anchors"
fi

if [ "$HARD_FAILS" -gt 0 ]; then
  echo "Hard failures: $HARD_FAILS"
  exit 1
fi

# --- 3. Coverage check: every spec basename matches some rm entry ----------
# Placeholder forms (`.research-<facet>.md`) normalize to a concrete sample
# (`.research-codebase.md`) so glob matching is meaningful; the rm entry is
# applied unquoted in `case` so its globs (`.research-*.md`) match.
total=0
covered=0
while IFS= read -r raw; do
  [ -z "$raw" ] && continue
  total=$((total + 1))
  case "$raw" in
    *'<'*'>'*)
      concrete=$(printf '%s' "$raw" | sed -E 's/<[A-Za-z0-9_-]+>/codebase/g')
      display="$raw (matched as sample: $concrete)"
      ;;
    *)
      concrete="$raw"
      display="$raw"
      ;;
  esac
  matched=0
  matched_by=""
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    # shellcheck disable=SC2254  # unquoted on purpose: rm entry is a glob pattern
    case "$concrete" in
      $entry) matched=1; matched_by="$entry" ;;
    esac
  done <<< "$rm_entries"
  if [ "$matched" -eq 1 ]; then
    covered=$((covered + 1))
    echo "OK: $display — covered by rm entry '$matched_by'"
  else
    report_fail "T1 transient file not covered by the Ship rm block: $display — add it (or a covering glob) to $RM_FILE §Cleanup"
  fi
done <<< "$spec_basenames"

echo
echo "==================================================="
echo "T1 basenames in spec: $total"
echo "Covered by rm block:  $covered"
echo "Hard failures:        $HARD_FAILS"
[ "$HARD_FAILS" -eq 0 ]
