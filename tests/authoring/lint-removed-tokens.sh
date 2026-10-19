#!/usr/bin/env bash
# C11 (plugin-audit 2026-09-23, fix-plan §O / T3-18, T3-19, T3-29; widened
# 2026-10-19, T3-1 / T3-2) — no shipped skills/, agents/, or cursor/README.md
# file carries a leftover reference to a removed mechanism: deep mode, debug
# depth, a depth pick/gate/question, a "skeptic" agent, or a write-env flag.
# A second token class covers the deleted guard hooks (below).
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
#
# Deleted guard hooks (T3-1 / T3-2). HOOKS.md §Removed guards records the six
# scripts deleted on 2026-09-29. Prose that still says a hook blocks a direct
# state write ("A hook blocks a direct Edit or Write", "trips the state-helper
# hook", "hook-protected") tells a run about a guard that no longer exists, so
# it plans around a protection that is not there — and the same stale claim
# was found in four files in one audit. The class is scanned in skills/,
# agents/, hooks/ and .claude/skills/. MIGRATION.md and HOOKS.md are out of
# scope on purpose: they carry the removal history, and lint-migration-
# superseded.sh owns the MIGRATION side. The same removal-notice carve-out
# applies ("deleted" / "removed" / "dropped" on the line), so a code comment
# that says what a guard "was deleted" for stays legal.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

TOKENS='deep mode|debug depth|depth (pick|gate|question)|\bskeptic\b|write-env'

# The six scripts HOOKS.md §Removed guards lists, plus the four phrases that
# describe a hook-enforced state write. `.` in a script name is escaped so
# `file-protection.sh` does not match `file-protection-sh`.
GUARD_TOKENS='file-protection\.sh|security-pattern-check\.sh|block-dangerous-git\.sh|block-geniro-deletion\.sh|enforce-state-helper\.sh|write-vectors\.sh|state-helper hook|A hook blocks a direct (Edit|Write)|hook-protected|guarded persistent path'

# README.md's "## Skills deleted" section's line range (start, and the next
# H2 after it) — excluded from the scan. Empty when the section is absent.
_readme_exempt_range() {
  awk '
    /^## Skills deleted/ { start = NR; next }
    start && /^## / && NR > start { print start "," (NR - 1); exit }
    END { if (start) print start ",$" }
  ' README.md 2>/dev/null
}

# <tokens-regex> <dirs/files...> -> file:line:match, skipping a line that
# documents its own removal ("removed"/"deleted"/"dropped" on the same line).
_removed_token_hits() {
  local tokens="$1" exempt_range
  shift
  exempt_range="$(_readme_exempt_range)"
  grep -rnoiE "$tokens" "$@" 2>/dev/null | while IFS=: read -r f l m; do
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
done < <(_removed_token_hits "$TOKENS" skills agents cursor/README.md README.md)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no leftover 'deep mode' / 'debug depth' / depth-gate / skeptic / write-env reference found ($checked hit(s))"
fi

guard_checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  guard_checked=$((guard_checked + 1))
  f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"; m="${rest#*:}"
  report_fail "$f:$l — names a deleted guard hook or describes hook-enforced state writes: \"$m\" — no hook checks state writes any more (HOOKS.md §Removed guards); state the real reason (torn-write atomicity) or drop the sentence"
done < <(_removed_token_hits "$GUARD_TOKENS" skills agents hooks .claude/skills)

if [ "$guard_checked" -eq 0 ]; then
  echo "OK: no skills/, agents/, hooks/ or .claude/skills/ file names a deleted guard hook or a hook-enforced state write"
fi

# --- self-test: red on a seeded live leftover, green on a removal notice + "skeptical" ----
# Each scenario runs the real _removed_token_hits inside a scratch tree, so the
# self-test exercises the same matcher, carve-out and README handling as the scan.
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/probe" "$SELFTEST_DIR/agents" "$SELFTEST_DIR/hooks" "$SELFTEST_DIR/.claude/skills/probe"

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

# Real shapes from the audit: the stale claims that tell a run a hook guards state writes.
cat > "$SELFTEST_DIR/skills/probe/guard-violation.md" <<'EOF'
Write the state file via the helper (a direct Write to a state path trips the state-helper hook).
A hook blocks a direct Edit or Write on these paths, so route every change through the helper.
The `_*.md` snapshots are a hook-protected persistent path.
A direct edit is refused because `.geniro/planning/_*.md` is a guarded persistent path.
See file-protection.sh for the list of guarded paths.
EOF
cat > "$SELFTEST_DIR/.claude/skills/probe/guard-violation.md" <<'EOF'
Source `lib/atomic-state-write.sh` — a direct `Write` trips the State-Helper Hook.
EOF
cat > "$SELFTEST_DIR/hooks/guard-violation.sh" <<'EOF'
# Mirrors enforce-state-helper.sh: block a direct Write to a state path.
EOF

# Clean: removal notices for the same scripts, and the live force-add guard's own name.
cat > "$SELFTEST_DIR/hooks/guard-clean.sh" <<'EOF'
# The one check kept from block-geniro-deletion.sh, which was deleted on 2026-09-29.
# block-geniro-force-add.sh blocks only a force-add of an ignored .geniro/ path.
EOF
cat > "$SELFTEST_DIR/skills/probe/guard-clean.md" <<'EOF'
The state-helper guard was removed; writes go through the helpers and no hook checks them.
The file protection helper and the geniro-deletion check are unrelated live names here.
EOF

( cd "$SELFTEST_DIR" || exit 1
  v=$(_removed_token_hits "$TOKENS" skills/probe/violation.md | grep -c . || true)
  if [ "$v" -eq 2 ]; then
    echo "OK: self-test — a seeded 'debug depth question' and 'skeptic agent' leftover are both detected ($v hit(s))"
  else
    echo "FAIL: self-test — expected 2 seeded leftover hits, got $v" >&2
    exit 1
  fi
) || report_fail "self-test — the seeded-violation scenario did not detect as expected"

( cd "$SELFTEST_DIR" || exit 1
  c=$(_removed_token_hits "$TOKENS" skills/probe/clean.md agents/clean.md | grep -c . || true)
  if [ "$c" -eq 0 ]; then
    echo "OK: self-test — a removal-documentation line ('...is removed') and 'skeptical, fresh eyes' do not false-positive"
  else
    echo "FAIL: self-test — the removal-notice / 'skeptical' fixture false-positived ($c hit(s))" >&2
    exit 1
  fi
) || report_fail "self-test — the clean (removal-notice + skeptical) scenario false-positived"

( cd "$SELFTEST_DIR" || exit 1
  g=$(_removed_token_hits "$GUARD_TOKENS" skills/probe/guard-violation.md .claude/skills/probe/guard-violation.md hooks/guard-violation.sh | grep -c . || true)
  if [ "$g" -eq 7 ]; then
    echo "OK: self-test — all 7 seeded deleted-guard claims (4 phrases, a script name, a mixed-case phrase, a hook comment) are detected"
  else
    echo "FAIL: self-test — expected 7 seeded deleted-guard hits, got $g" >&2
    exit 1
  fi
) || report_fail "self-test — the seeded deleted-guard scenario did not detect as expected"

( cd "$SELFTEST_DIR" || exit 1
  gc=$(_removed_token_hits "$GUARD_TOKENS" skills/probe/guard-clean.md hooks/guard-clean.sh | grep -c . || true)
  if [ "$gc" -eq 0 ]; then
    echo "OK: self-test — removal notices and the live block-geniro-force-add.sh name do not false-positive"
  else
    echo "FAIL: self-test — the deleted-guard clean fixture false-positived ($gc hit(s))" >&2
    exit 1
  fi
) || report_fail "self-test — the clean deleted-guard scenario false-positived"

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS removed-mechanism leftover reference problem(s)." >&2
  exit 1
fi
echo "OK: skills/, agents/, hooks/, .claude/skills/, cursor/README.md, and README.md carry no leftover removed-mechanism reference."
