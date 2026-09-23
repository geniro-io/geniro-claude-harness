#!/usr/bin/env bash
# C11 (plugin-audit 2026-09-23, fix-plan §O / T3-18, T3-19, T3-29) — no shipped
# skills/, agents/, or cursor/README.md file carries a leftover reference to a
# removed mechanism: deep mode, debug depth, a depth pick/gate/question,
# a "skeptic" agent, or a write-env flag.
#
# Run: bash tests/authoring/lint-removed-tokens.sh
#
# Why this exists: D3 "dropped phase/step names" — grep alone over-counts,
# because a hit that merely *documents the removal* is not evidence the name
# is still live (D6 §6 states the same principle for anti-rationalization
# rows: "a hit that only documents the removal is not evidence"). This check
# mechanizes the decidable half — a token match that is NOT paired with its
# own documentation-of-removal — and defers genuinely ambiguous prose to the
# D3 reviewer, same division of labor lint-skills.sh already uses for
# deleted-skill references (D1 battery finds candidates; D3 adjudicates).
#
# Scope decisions (stated per the task's instruction to decide and say so):
#
# - MIGRATION.md is skipped ENTIRELY, not scanned with a section carve-out —
#   it is this plugin's own changelog and legitimately restates every one of
#   these tokens dozens of times ("Deep mode" x2, "write-env" x7, "skeptic"
#   x4 measured) as the historical record of their removal. A section-level
#   exemption (mirroring README's "Skills deleted" TABLE) does not fit this
#   file's shape — the mentions are scattered across dozens of dated entries,
#   not confined to one table — so the whole file is out of scope, matching
#   the fix-plan's own "(exempt ... MIGRATION.md)" instruction read as a
#   whole-file exemption.
# - README.md's "## Skills deleted" section is excluded by line range, per
#   the fix-plan's literal instruction; the rest of README.md IS scanned.
# - `test-gate` / `test gate` is DROPPED from the token list. It collides
#   with live, unrelated terminology: `skills/implement/implement-reference.md`
#   uses "Phase 2 test-gate escalation" for implement's OWN still-live
#   self-review gate, and `skills/refactor/SKILL.md` uses "regression test
#   gate" for refactor's OWN still-live verification step — neither is
#   /review's removed Phase 4.3 test gate (T3-19's actual referent), and
#   nothing in the corpus's remaining "test-gate"/"test gate" hits IS that
#   referent. Keeping the token produces two confirmed false positives and
#   zero confirmed true positives on this tree, so it fails this check's own
#   zero-false-positive bar.
# - `skeptic` is word-boundaried (`\bskeptic\b`) to admit the (deleted)
#   "skeptic" agent/pick without also matching "skeptical" — `agents/
#   reviewer-agent.md` legitimately instructs "skeptical, fresh eyes" as
#   ordinary English, unrelated to the removed agent.
# - A line ALSO containing "removed" / "deleted" / "dropped" is a removal
#   NOTICE, not a leftover reference (the same shape the README "Skills
#   deleted" table and MIGRATION.md carve-outs already establish as
#   legitimate) — generalized here per-line rather than per-file, since a
#   skill body can carry the identical correct "§11 reserved — the
#   review-depth question is removed" shape MIGRATION.md and README use.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

TOKENS='deep mode|debug depth|depth (pick|gate|question)|\bskeptic\b|write-env'

# README.md's "## Skills deleted" section's line range (start, and the next
# H2 after it) — excluded from the scan. Empty when the section is absent.
_readme_exempt_range() {
  awk '
    /^## Skills deleted/ { start = NR; next }
    start && /^## / && NR > start { print start "," (NR - 1); exit }
    END { if (start) print start ",$" }
  ' README.md 2>/dev/null
}

# <dirs/files...> -> file:line:match, skipping a line that documents its own
# removal ("removed"/"deleted"/"dropped" on the same line).
_removed_token_hits() {
  local exempt_range
  exempt_range="$(_readme_exempt_range)"
  grep -rnoiE "$TOKENS" "$@" 2>/dev/null | while IFS=: read -r f l m; do
    if [ "$f" = "README.md" ] && [ -n "$exempt_range" ]; then
      case "$exempt_range" in
        *,'$')
          start="${exempt_range%,\$}"
          [ "$l" -ge "$start" ] && continue
          ;;
        *)
          start="${exempt_range%,*}"; end="${exempt_range#*,}"
          [ "$l" -ge "$start" ] && [ "$l" -le "$end" ] && continue
          ;;
      esac
    fi
    sed -n "${l}p" "$f" 2>/dev/null | grep -qiE '\b(removed|deleted|dropped)\b' && continue
    printf '%s:%s:%s\n' "$f" "$l" "$m"
  done
}

checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  checked=$((checked + 1))
  f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"; m="${rest#*:}"
  report_fail "$f:$l — leftover reference to a removed mechanism: \"$m\" — remove it, or if the token is another mechanism's coincidental name, drop it from this check's list with evidence"
done < <(_removed_token_hits skills agents cursor/README.md README.md)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no leftover 'deep mode' / 'debug depth' / depth-gate / skeptic / write-env reference found ($checked hit(s))"
fi

# --- self-test: red on a seeded live leftover, green on a removal notice + "skeptical" ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/probe" "$SELFTEST_DIR/agents"

cat > "$SELFTEST_DIR/skills/probe/violation.md" <<'EOF'
Ask the debug depth question before Phase 1: how deep should this investigation go?
Spawn a skeptic agent to challenge the finding.
EOF

cat > "$SELFTEST_DIR/skills/probe/clean.md" <<'EOF'
§11 reserved — the review-depth question is removed; the re-review gate asks scope + steering under §7.
EOF

cat > "$SELFTEST_DIR/agents/clean.md" <<'EOF'
Review with skeptical, fresh eyes. Do not rubber-stamp.
EOF

( cd "$SELFTEST_DIR" || exit 1
  v=$(grep -rnoiE 'deep mode|debug depth|depth (pick|gate|question)|\bskeptic\b|write-env' skills 2>/dev/null | while IFS=: read -r f l m; do
    sed -n "${l}p" "$f" | grep -qiE '\b(removed|deleted|dropped)\b' && continue
    echo hit
  done | grep -c . || true)
  if [ "$v" -ge 2 ]; then
    echo "OK: self-test — a seeded 'debug depth question' and 'skeptic agent' leftover are both detected ($v hit(s))"
  else
    echo "FAIL: self-test — expected >=2 seeded leftover hits, got $v" >&2
    exit 1
  fi
) || report_fail "self-test — the seeded-violation scenario did not detect as expected"

( cd "$SELFTEST_DIR" || exit 1
  c=$(grep -rnoiE 'deep mode|debug depth|depth (pick|gate|question)|\bskeptic\b|write-env' skills/probe/clean.md agents/clean.md 2>/dev/null | while IFS=: read -r f l m; do
    sed -n "${l}p" "$f" | grep -qiE '\b(removed|deleted|dropped)\b' && continue
    echo hit
  done | grep -c . || true)
  if [ "$c" -eq 0 ]; then
    echo "OK: self-test — a removal-documentation line ('...is removed') and 'skeptical, fresh eyes' do not false-positive"
  else
    echo "FAIL: self-test — the removal-notice / 'skeptical' fixture false-positived ($c hit(s))" >&2
    exit 1
  fi
) || report_fail "self-test — the clean (removal-notice + skeptical) scenario false-positived"

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS removed-mechanism leftover reference problem(s)." >&2
  exit 1
fi
echo "OK: skills/, agents/, cursor/README.md, and README.md carry no leftover removed-mechanism reference."
