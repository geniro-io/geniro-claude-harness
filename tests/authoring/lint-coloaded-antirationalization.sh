#!/usr/bin/env bash
# A skill declaring its Anti-rationalization table CO-LOADED with a sibling
# file's table must keep their COMBINED row count <=15.
#
# Run: bash tests/authoring/lint-coloaded-antirationalization.sh
#
# Why this exists: `lint-skills.sh` check 7 already warns per-file when an
# `## Anti-rationalization` table exceeds the 15-row guideline — but it reads
# one file at a time, so it cannot see a table that was deliberately SPLIT
# across two files that always load together. `skills/plan/SKILL.md` states
# exactly that split: "Loop-level rows ... live in
# `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §Anti-rationalization —
# co-loaded with this file, and counted against the same <=15-row cap as one
# table." Both files individually sit under 15 rows, so the per-file check
# stays silent while the union — what a session actually holds in context at
# once — sits well over it. Nothing re-derives the sum, so "auditing row #16"
# never fires.
#
# Scope: any `skills/*/SKILL.md` that declares a co-loaded sibling. The
# declaration is detected by the phrase "co-loaded with this file" (or "co-
# loaded with the skill") on a line that also names another `.md` file via
# `${CLAUDE_PLUGIN_ROOT}/...` or a bare basename in backticks — the shape this
# corpus's one instance uses today, kept general so a second skill that adopts
# the same split is caught the same way rather than requiring a second,
# hand-written check.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

CAP=15
FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }
# WARNS never gate the exit code — the cap is a guideline (see the call site).
# report_fail stays for the self-tests: a checker that silently stops checking
# is worse than the drift it watches for, so those DO hard-fail.
WARNS=0
report_warn() { WARNS=$((WARNS + 1)); echo "WARN: $1"; }

# Row count of the (first) "## Anti-rationalization" table in a file, header +
# separator rows subtracted — identical rule to lint-skills.sh check 7, so a
# file's count never disagrees between the two checks.
_antirat_rows() {
  local f="$1" rows
  rows=$(sed -n '/^## [Aa]nti-[Rr]ationalization/,/^## /p' "$f" 2>/dev/null | grep -cE '^\|' || true)
  [ "$rows" -gt 2 ] && rows=$((rows - 2)) || rows=0
  printf '%s' "$rows"
}

# `<declaring-file>\t<co-loaded-file>` for every co-load declaration found.
_coload_pairs() {
  local f rel_root
  for f in "$@"; do
    [ -f "$f" ] || continue
    grep -niE 'co-loaded with (this file|the skill)' "$f" 2>/dev/null | while IFS=: read -r _l rest; do
      tok=$(printf '%s\n' "$rest" \
        | grep -oE '(\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]+\.md|`[A-Za-z0-9._-]+\.md`)' | head -1)
      [ -n "$tok" ] || continue
      tok="${tok#\$\{CLAUDE_PLUGIN_ROOT\}/}"
      tok="${tok#\`}"; tok="${tok%\`}"
      if [ -f "$tok" ]; then
        printf '%s\t%s\n' "$f" "$tok"
      elif [ -f "$(dirname "$f")/$tok" ]; then
        printf '%s\t%s\n' "$f" "$(dirname "$f")/$tok"
      fi
    done
  done
}

checked=0
while IFS=$'\t' read -r declaring coloaded; do
  [ -n "$declaring" ] || continue
  checked=$((checked + 1))
  a=$(_antirat_rows "$declaring")
  b=$(_antirat_rows "$coloaded")
  total=$((a + b))
  if [ "$total" -gt "$CAP" ]; then
    # ADVISORY, matching lint-skills.sh's per-file treatment of the same rule
    # (`report_warn` at its anti-rationalization check). skill-structure.md states
    # the cap as "adding row #16 means auditing the existing rows" — an instruction
    # to audit, not a prohibition, and an author who audits and concludes all 15 are
    # still live must not be blocked from committing a justified 16th. Hard-failing
    # here would also make the co-loaded case stricter than the per-file case for
    # one identical rule, which is the drift this whole check exists to prevent.
    report_warn "$declaring + $coloaded: co-loaded Anti-rationalization tables total $total rows ($a + $b) against the <=$CAP guideline declared at $declaring — audit the union; at least one row is likely defending a failure mode that is no longer live"
  fi
done < <(_coload_pairs skills/*/SKILL.md)

if [ "$FAILS" -eq 0 ]; then
  if [ "$checked" -eq 0 ]; then
    echo "OK: no skill declares a co-loaded Anti-rationalization table (nothing to sum)"
  else
    echo "OK: every declared co-loaded Anti-rationalization pair stays within the <=$CAP cap ($checked pair(s) checked)"
  fi
fi

# --- self-test: red on a seeded pair totalling 16, green at 15 --------------
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT

_gen_rows() {  # <n> -> n table data rows (plus header+separator)
  local n="$1" i
  printf '| Your reasoning | Why it is wrong |\n|---|---|\n'
  for i in $(seq 1 "$n"); do printf '| reasoning %d | wrong %d |\n' "$i" "$i"; done
}

gen_case() {  # <dir> <a_rows> <b_rows>
  local dir="$1" a="$2" b="$3"
  mkdir -p "$dir"
  {
    printf '# Probe skill\n\n## Anti-rationalization\n\n'
    printf 'Loop-level rows live in `sibling.md` §Anti-rationalization — co-loaded with this file, counted against the same cap as one table.\n\n'
    _gen_rows "$a"
  } > "$dir/SKILL.md"
  {
    printf '# Sibling\n\n## Anti-rationalization\n\n'
    _gen_rows "$b"
  } > "$dir/sibling.md"
}

gen_case "$SELFTEST_DIR/violation" 8 8    # 16 total, over the cap
gen_case "$SELFTEST_DIR/clean" 7 8        # 15 total, at the cap

v_pairs="$(_coload_pairs "$SELFTEST_DIR/violation/SKILL.md")"
v_total=0
if [ -n "$v_pairs" ]; then
  while IFS=$'\t' read -r d c; do
    [ -n "$d" ] || continue
    v_total=$(( $(_antirat_rows "$d") + $(_antirat_rows "$c") ))
  done <<< "$v_pairs"
fi
if [ "$v_total" -gt "$CAP" ]; then
  echo "OK: self-test — a seeded 16-row co-loaded union (8+8) is detected as over the $CAP cap"
else
  report_fail "self-test — seeded 16-row violation NOT detected (measured total: $v_total)"
fi

c_pairs="$(_coload_pairs "$SELFTEST_DIR/clean/SKILL.md")"
c_total=0
if [ -n "$c_pairs" ]; then
  while IFS=$'\t' read -r d c; do
    [ -n "$d" ] || continue
    c_total=$(( $(_antirat_rows "$d") + $(_antirat_rows "$c") ))
  done <<< "$c_pairs"
fi
if [ "$c_total" -le "$CAP" ] && [ "$c_total" -gt 0 ]; then
  echo "OK: self-test — a seeded 15-row co-loaded union (7+8) stays at the cap (no false positive)"
else
  report_fail "self-test — the clean fixture measured $c_total rows, expected exactly $CAP"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS co-loaded Anti-rationalization problem(s)." >&2
  exit 1
fi
echo "OK: every declared co-loaded Anti-rationalization union stays within the cap."
