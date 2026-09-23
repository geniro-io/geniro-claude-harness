#!/usr/bin/env bash
# C14 (plugin-audit 2026-09-23, fix-plan §O / T4-58) — every SKILL.md whose
# compaction re-attach boundary drops >=1 section carries a compaction
# re-read paragraph somewhere ABOVE that boundary (in the surviving prefix).
#
# Run: bash tests/authoring/lint-compaction-reread.sh
#
# Why this exists: skill-prose.md §Rule placement / §Token budget awareness —
# a paragraph telling the model to re-read the running phase after a
# compaction is itself LOAD-BEARING instruction, so it has to sit where
# compaction cannot drop it. A copy placed past the boundary is exactly the
# failure it exists to prevent: it describes the recovery procedure for
# content that has already, by the time anyone would need it, been dropped
# ALONGSIDE it. T4-58: onboard/SKILL.md's whole Phase 2 sat past the boundary
# with no such paragraph above it (every other long spine already had one).
#
# Detection reuses tests/authoring/lint-skills.sh's own REATTACH_CHARS
# (20,000, the measured host re-attach cutoff) and its `frontload_cut`
# accumulation logic, so "boundary" means the same thing in both checks — this
# does not invent a second definition of where the cut falls. A file under the
# cutoff (nothing lost) is out of scope by construction: check 6's own
# advisory warning is silent for it too, so there is no boundary for a
# paragraph to sit above.
#
# The canonical paragraph shape, observed across every currently-compliant
# long spine (debug, implement, investigate, plan, refactor, review, resolve,
# onboard, actions, audit-instructions — each authored independently, not
# copy-pasted, so the wording varies): a single line mentioning BOTH
# "compaction" and a re-read instruction ("re-read" / "re-Read"). This corpus
# authors each such paragraph as one long unwrapped line, so a same-line
# co-occurrence check is precise without needing a multi-line paragraph
# parser.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

REATTACH_CHARS=20000

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# <file> -> the file's surviving prefix (lines whose cumulative offset is
# still under REATTACH_CHARS), one per line — mirrors lint-skills.sh's own
# frontload_cut() accumulation (length($0)+1 per line) so "above the
# boundary" means the same byte-offset cut in both checks.
_surviving_prefix() {
  awk -v lim="$REATTACH_CHARS" '{ if (c < lim) print; c += length($0) + 1 }' "$1" 2>/dev/null
}

_total_chars() {
  wc -c < "$1" 2>/dev/null | tr -d ' '
}

_has_reread_paragraph() {
  grep -qiE 'compaction.*re-?read|re-?read.*compaction' <<<"$1"
}

checked=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  chars="$(_total_chars "$f")"
  [ -n "$chars" ] || continue
  [ "$chars" -gt "$REATTACH_CHARS" ] || continue   # nothing lost — out of scope
  checked=$((checked + 1))
  prefix="$(_surviving_prefix "$f")"
  if ! _has_reread_paragraph "$prefix"; then
    report_fail "$f — compaction re-attaches only the first $REATTACH_CHARS chars of this $chars-char file (>=1 section is lost past it), and no compaction re-read paragraph appears above that boundary — add one (skill-prose.md §Rule placement)"
  fi
done < <(find skills .claude/skills -type f -name 'SKILL.md' 2>/dev/null | LC_ALL=C sort)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: every SKILL.md whose re-attach boundary drops a section carries a compaction re-read paragraph above it ($checked file(s) over the boundary checked)"
fi

# --- self-test: red on a seeded over-boundary file with no paragraph above it ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/violation" "$SELFTEST_DIR/skills/clean" "$SELFTEST_DIR/skills/short"

FILLER=$(printf 'x%.0s' $(seq 1 500))

{
  echo "# Probe"
  echo "No compaction paragraph here at all."
  for i in $(seq 1 45); do echo "Filler line $i: $FILLER"; done
  echo "## Phase 2"
  echo "Steps that will be dropped past the boundary."
} > "$SELFTEST_DIR/skills/violation/SKILL.md"

{
  echo "# Probe"
  echo "**Compaction.** The host re-attaches only an initial slice of this file; re-read this file and the running phase's body before relying on anything past the truncation marker."
  for i in $(seq 1 45); do echo "Filler line $i: $FILLER"; done
  echo "## Phase 2"
  echo "Steps that will be dropped past the boundary, but the paragraph above already covers it."
} > "$SELFTEST_DIR/skills/clean/SKILL.md"

{
  echo "# Probe"
  echo "Short file, well under the boundary, no compaction paragraph needed."
} > "$SELFTEST_DIR/skills/short/SKILL.md"

check_one() {
  local f chars prefix
  f="$1"
  chars="$(wc -c < "$f" | tr -d ' ')"
  [ "$chars" -gt "$REATTACH_CHARS" ] || { echo "under-boundary"; return; }
  prefix="$(awk -v lim="$REATTACH_CHARS" '{ if (c < lim) print; c += length($0) + 1 }' "$f")"
  if grep -qiE 'compaction.*re-?read|re-?read.*compaction' <<<"$prefix"; then
    echo "has-paragraph"
  else
    echo "missing-paragraph"
  fi
}

v="$(check_one "$SELFTEST_DIR/skills/violation/SKILL.md")"
c="$(check_one "$SELFTEST_DIR/skills/clean/SKILL.md")"
s="$(check_one "$SELFTEST_DIR/skills/short/SKILL.md")"

if [ "$v" = "missing-paragraph" ]; then
  echo "OK: self-test — an over-boundary file with no compaction re-read paragraph above the cut is detected"
else
  report_fail "self-test — the seeded over-boundary/no-paragraph fixture was measured '$v', expected 'missing-paragraph'"
fi

if [ "$c" = "has-paragraph" ]; then
  echo "OK: self-test — an over-boundary file WITH a compaction re-read paragraph above the cut does not false-positive"
else
  report_fail "self-test — the seeded over-boundary/with-paragraph fixture was measured '$c', expected 'has-paragraph'"
fi

if [ "$s" = "under-boundary" ]; then
  echo "OK: self-test — a short file under the boundary is out of scope (no paragraph required)"
else
  report_fail "self-test — the short fixture was measured '$s', expected 'under-boundary'"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS missing compaction re-read paragraph problem(s)." >&2
  exit 1
fi
echo "OK: every over-boundary SKILL.md carries a compaction re-read paragraph above its re-attach cut."
