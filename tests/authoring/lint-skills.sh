#!/usr/bin/env bash
# Authoring lint — mechanizes the manual greps in .claude/rules/skill-structure.md
# §Pre-commit verification and .claude/rules/skill-authoring.md §Hard exclusions.
#
# Run: bash tests/authoring/lint-skills.sh
#
# Two severities:
#   HARD (exit non-zero) — zero-false-positive correctness checks:
#     1. Non-Latin (Cyrillic) letters in skills/ or agents/ bodies.
#     2. Dangling ${CLAUDE_PLUGIN_ROOT}/<path> file references (target must exist).
#     3. Unknown subagent_type spawn names (must resolve to a real agent/builtin).
#   ADVISORY (warn only, exit 0 contribution) — guideline checks the maintainer
#   reads but never auto-trims to satisfy (size targets are guidelines, not limits):
#     4. SKILL.md word count vs the front-load budget and whole-file guideline.
#     5. Anti-rationalization tables over the 15-row guideline.
#     6. Decaying line-number cross-references (file.md:NNN).
#
# Portability: pure POSIX-ish bash + BSD/GNU-portable grep (no -P / PCRE).
# Cyrillic detection uses a byte-class match (UTF-8 lead bytes 0xD0/0xD1) so it
# is precise (does not flag the allowed em-dash / arrows / § / ≥ / curly quotes,
# whose lead bytes are 0xC2/0xC3/0xE2) and runs identically on macOS and Linux.
# Scope note: only Cyrillic (the documented real contamination risk for this
# repo) is hard-gated. Greek/Han/Hiragana are intentionally NOT gated — a broad
# non-ASCII check would false-positive on the very glyphs the repo allows, which
# is exactly why the precise byte-class is used over rule §1's broader net.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

HARD_FAILS=0
WARNS=0
report_fail() { HARD_FAILS=$((HARD_FAILS + 1)); echo "FAIL: $1" >&2; }
report_warn() { WARNS=$((WARNS + 1)); echo "WARN: $1"; }
rel() { printf '%s' "${1#"$REPO_ROOT"/}"; }

echo "=== HARD checks ==="

# 1. Non-Latin (Cyrillic) letters — the documented real contamination risk.
cyr_files=$(LC_ALL=C grep -ralE $'[\xd0\xd1]' skills agents 2>/dev/null || true)
if [ -n "$cyr_files" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    report_fail "non-Latin (Cyrillic) bytes in $(rel "$f") — skill/agent bodies must be English-only"
  done <<< "$cyr_files"
else
  echo "OK: no Cyrillic in skills/ or agents/"
fi

# 2. Dangling ${CLAUDE_PLUGIN_ROOT}/<path> file references.
dangling=0
refs=$(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]+\.(md|sh|js|json)(\.example)?' skills agents 2>/dev/null \
  | sed -E 's#\$\{CLAUDE_PLUGIN_ROOT\}/##' | sort -u)
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if [ ! -f "$p" ]; then report_fail "dangling reference: \${CLAUDE_PLUGIN_ROOT}/$p (target file does not exist)"; dangling=$((dangling + 1)); fi
done <<< "$refs"
[ "$dangling" -eq 0 ] && echo "OK: all \${CLAUDE_PLUGIN_ROOT}/ file references resolve"

# 3. Unknown subagent_type spawn names.
valid_agents="$(mktemp)"
trap 'rm -f "$valid_agents"' EXIT
{ for f in agents/*.md; do basename "$f" .md; done; printf '%s\n' general-purpose Explore Plan statusline-setup; } \
  | sort -u > "$valid_agents"
unknown=0
spawns=$(grep -rhoE 'subagent_type[=:][[:space:]]*"?(geniro:)?[A-Za-z0-9_:-]+' skills agents 2>/dev/null \
  | sed -E 's/.*subagent_type[=:][[:space:]]*"?//; s/^geniro://' | grep -v '^$' | sort -u)
while IFS= read -r s; do
  [ -z "$s" ] && continue
  if ! grep -qxF "$s" "$valid_agents"; then report_fail "unknown subagent_type spawn: '$s' (no agents/$s.md and not a known builtin)"; unknown=$((unknown + 1)); fi
done <<< "$spawns"
rm -f "$valid_agents"
[ "$unknown" -eq 0 ] && echo "OK: all subagent_type spawns resolve to a real agent or builtin"

echo
echo "=== ADVISORY checks (warn only) ==="

# 4. SKILL.md size, measured in WORDS per skill-structure.md §File-size limits.
#    Not lines: a skill body here runs 9-21 words/line depending on table density,
#    so a line count ranks files backwards (setup 571L/5267W vs resolve 142L/3044W).
#    The front-load budget is the load-bearing figure — Claude Code re-attaches only
#    the first 5,000 tokens of a skill after compaction (~3,000 words of table-dense
#    markdown), so anything past it is absent for the rest of a compacted session.
FRONTLOAD_WORDS=3000
WHOLEFILE_WORDS=5000
for f in skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  n=$(wc -w < "$f" | tr -d ' ')
  if [ "$n" -gt "$WHOLEFILE_WORDS" ]; then
    report_warn "$(rel "$f"): $n words (whole-file guideline <=$WHOLEFILE_WORDS)"
  fi
  if [ "$n" -gt "$FRONTLOAD_WORDS" ]; then
    # Name the last H2 that still fits inside the front-load budget, so the warning
    # says WHICH sections stop being re-attached rather than just that the file is big.
    cut=$(awk -v lim="$FRONTLOAD_WORDS" '
      /^## / { last = $0 }
      { w += NF; if (w > lim && !done) { print last; done = 1 } }
    ' "$f")
    [ -n "$cut" ] && report_warn "$(rel "$f"): compaction boundary (~$FRONTLOAD_WORDS words) falls at \"$cut\" — sections after it are dropped once the session compacts"
  fi
done

# Corpus shape, not per-file compliance: a median that creeps up is the signal to
# act on, and one oversize skill among lean ones is a different problem from all of
# them drifting together. INFO, not a warning — it never needs "fixing" on its own.
skill_words=$(for f in skills/*/SKILL.md; do [ -f "$f" ] && wc -w < "$f"; done | tr -d ' ')
if [ -n "$skill_words" ]; then
  echo "INFO: SKILL.md word counts — $(printf '%s\n' "$skill_words" | sort -n | awk -v lim="$FRONTLOAD_WORDS" '
    {a[NR]=$1; if ($1 > lim) over++}
    END {printf "median %d, range %d-%d, %d of %d over the ~%d-word front-load budget",
         (NR%2 ? a[(NR+1)/2] : int((a[NR/2]+a[NR/2+1])/2)), a[1], a[NR], over+0, NR, lim}')"
fi

# 5. Anti-rationalization tables over the 15-row guideline.
for f in skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  rows=$(sed -n '/^## [Aa]nti-[Rr]ationalization/,/^## /p' "$f" | grep -cE '^\|' || true)
  if [ "$rows" -gt 2 ]; then
    rows=$((rows - 2))  # subtract header + separator rows
    if [ "$rows" -gt 15 ]; then report_warn "$(rel "$f"): anti-rationalization table has $rows rows (guideline ≤15)"; fi
  fi
done

# 6. Decaying line-number cross-references (file.md:NNN) — section/content anchors survive edits; line numbers do not.
# -o extracts just the `file.md:NNN` match (with a grep file:line locator prefix);
# advisory only, so a rare URL-with-port (foo.md:8080) miscount is acceptable.
linerefs=$(grep -rnoE '[A-Za-z0-9_-]+\.md:[0-9]+' skills 2>/dev/null || true)
if [ -n "$linerefs" ]; then
  count=$(printf '%s\n' "$linerefs" | grep -c . || true)
  report_warn "found $count line-number cross-reference(s) (file.md:NNN) in skills/ — prefer content anchors"
fi

echo
echo "==================================================="
echo "Hard failures: $HARD_FAILS"
echo "Warnings:      $WARNS"
[ "$HARD_FAILS" -eq 0 ]
