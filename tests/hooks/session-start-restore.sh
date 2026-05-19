#!/usr/bin/env bash
# Smoke test for hooks/session-start-restore.sh (M3 SessionStart hook).
#
# Run: bash tests/hooks/session-start-restore.sh
#
# Coverage:
#   - All 4 source paths (compact / resume / startup / clear).
#   - Tier-1 slug match + Tier-2 frontmatter `branch:` fallback.
#   - Cold startup (no active task) — systemMessage suppression.
#   - Validation pass / fail / skipped (CLAUDE_PLUGIN_ROOT misset).
#   - Block 5 non-resumable rendering (per-action-type + fallback).
#   - Block 5b errors (resolved-filter).
#   - Block 5c open questions (resolved-filter).
#   - Block 5d approvals (no filter).
#   - Empty-list cases (no false Block emissions).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/session-start-restore.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Run hook with given source + cwd; emit raw stdout (caller pipes to jq).
run_hook() {
  local source="$1" sandbox="$2"
  printf '{"source":"%s","cwd":"%s"}' "$source" "$sandbox" \
    | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK"
}

# Build a sandbox with а valid state.md под branch `feature/x`.
new_sandbox() {
  local d="$TMPDIR_BASE/$(date +%s%N)-$RANDOM"
  mkdir -p "$d"
  cd "$d" || return 1
  git init -q
  git checkout -q -b "feature/x" 2>/dev/null
  mkdir -p .geniro/planning/feature-x
  cat > .geniro/planning/feature-x/state.md <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---

## Phase log
- analyze done
EOF
  echo "$d"
}

# ---------------------------------------------------------------------------
# 1. clear source → silent (exit 0, no output)
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(run_hook clear "$sandbox")
if [ -z "$out" ]; then
  pass "clear source produces no output"
else
  fail "clear source should be silent — got: $out"
fi

# ---------------------------------------------------------------------------
# 2. compact source → all blocks fire when state.md is valid
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
sm=$(echo "$out" | jq -r '.systemMessage // ""')

echo "$ac" | grep -q "Context was compressed by compaction" \
  && pass "compact: Block 1 prefix" \
  || fail "compact: Block 1 prefix missing"

echo "$ac" | grep -q "instructions/implement.md" \
  && pass "compact: Block 2 active-skill instructions pointer" \
  || fail "compact: active-skill pointer missing"

echo "$ac" | grep -q "state.md" \
  && pass "compact: Block 2 state.md pointer (validation passed)" \
  || fail "compact: state.md pointer missing"

echo "$ac" | grep -q "Resume steps:" \
  && pass "compact: Block 6 resume protocol header" \
  || fail "compact: Block 6 missing"

echo "$sm" | grep -q "active: feature-x · phase: implement · non-resumable: 0" \
  && pass "compact: systemMessage shape (active/phase/non-resumable)" \
  || fail "compact: systemMessage shape wrong — '$sm'"

# ---------------------------------------------------------------------------
# 3. resume source → "Restoring from prior session" prefix
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(run_hook resume "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
echo "$ac" | grep -q "Restoring from prior session" \
  && pass "resume: Block 1 phrasing" \
  || fail "resume: Block 1 phrasing missing"

# ---------------------------------------------------------------------------
# 4. startup source with active task → "Active task detected"
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(run_hook startup "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
sm=$(echo "$out" | jq -r '.systemMessage // ""')

echo "$ac" | grep -q "Active task detected at startup" \
  && pass "startup with task: Block 1 phrasing" \
  || fail "startup with task: Block 1 missing"

[ -n "$sm" ] \
  && pass "startup with task: systemMessage emitted" \
  || fail "startup with task: systemMessage suppressed (should be emitted)"

# ---------------------------------------------------------------------------
# 5. startup source with NO active task → systemMessage suppressed
# ---------------------------------------------------------------------------

sandbox="$TMPDIR_BASE/cold-$$"
mkdir -p "$sandbox" && cd "$sandbox" && git init -q && git checkout -q -b "fresh" 2>/dev/null
out=$(run_hook startup "$sandbox")
sm=$(echo "$out" | jq -r '.systemMessage // ""')

[ -z "$sm" ] \
  && pass "cold startup: systemMessage suppressed" \
  || fail "cold startup: systemMessage should be suppressed — '$sm'"

# ---------------------------------------------------------------------------
# 6. Validation FAIL → Block 3, state.md pointer suppressed
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
# Corrupt the state.md by removing the frontmatter opener.
cat > "$sandbox/.geniro/planning/feature-x/state.md" <<'EOF'
not-a-frontmatter
foo: bar
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

echo "$ac" | grep -q "STATE FILE FAILED VALIDATION" \
  && pass "validation fail: Block 3 fires" \
  || fail "validation fail: Block 3 missing"

# State.md pointer should NOT appear under "- " bullets (only instructions trio).
if echo "$ac" | grep -E "^- .*state\.md$" >/dev/null; then
  fail "validation fail: state.md pointer should be suppressed"
else
  pass "validation fail: state.md pointer suppressed"
fi

# ---------------------------------------------------------------------------
# 7. M1 helper missing → Block 4 fires (validation skipped)
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(printf '{"source":"compact","cwd":"%s"}' "$sandbox" \
  | CLAUDE_PLUGIN_ROOT=/tmp/no-such-dir-$$ bash "$HOOK")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

echo "$ac" | grep -q "M1 helpers not installed" \
  && pass "helper missing: Block 4 fires" \
  || fail "helper missing: Block 4 missing"

# ---------------------------------------------------------------------------
# 8. Tier-2 fallback — task-dir name differs from slug
# ---------------------------------------------------------------------------

sandbox="$TMPDIR_BASE/tier2-$$"
mkdir -p "$sandbox" && cd "$sandbox" && git init -q && git checkout -q -b "feature/y" 2>/dev/null
# Put state.md in a task-dir that does NOT match slug "feature-y" — Tier-1 must miss,
# Tier-2 frontmatter `branch:` grep must find it.
mkdir -p .geniro/planning/different-name
cat > .geniro/planning/different-name/state.md <<'EOF'
---
tier: T1
producer: refactor
schema-version: 1
branch: feature/y
timestamp: 2026-05-19T15:00:00Z
phase: rewrite
status: in-progress
non-resumable-actions: []
---

body
EOF

out=$(run_hook compact "$sandbox")
sm=$(echo "$out" | jq -r '.systemMessage // ""')
echo "$sm" | grep -q "active: different-name · phase: rewrite" \
  && pass "tier-2 fallback: branch grep finds non-slug task-dir" \
  || fail "tier-2 fallback failed — sm='$sm'"

# ---------------------------------------------------------------------------
# 9. Block 5 — structured non-resumable rendering
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
cat > "$sandbox/.geniro/planning/feature-x/state.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: ship
status: in-progress
non-resumable-actions:
  - action: git-push
    target: origin/feature/x
    ref: a3f9e2
    completed-at: 2026-05-19T14:32:00Z
  - action: pr-comment-posted
    pr: 142
    comment-id: 1834720
    completed-at: 2026-05-19T14:35:00Z
  - action: custom-unknown
    completed-at: 2026-05-19T14:40:00Z
---

body
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

echo "$ac" | grep -q "git-push (target: origin/feature/x, ref: a3f9e2" \
  && pass "Block 5: git-push structured rendering" \
  || fail "Block 5: git-push not rendered correctly"

echo "$ac" | grep -q "pr-comment-posted (pr: 142, comment-id: 1834720" \
  && pass "Block 5: pr-comment-posted rendering" \
  || fail "Block 5: pr-comment-posted not rendered correctly"

echo "$ac" | grep -q "custom-unknown (completed:" \
  && pass "Block 5: unknown-action fallback" \
  || fail "Block 5: unknown-action fallback missing"

# ---------------------------------------------------------------------------
# 10. Block 5b — Errors (resolved filter)
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
cat > "$sandbox/.geniro/planning/feature-x/state.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---

## Errors
- ts: 2026-05-19T10:42:00Z
  tool: Bash
  detail: "npm test"
  error: "TypeError"
  attempted_fix: "added dep"
  resolved: false
- ts: 2026-05-19T11:00:00Z
  tool: Bash
  detail: "npm lint"
  error: "missing semi"
  attempted_fix: "added semi"
  resolved: true
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

echo "$ac" | grep -q "ERRORS ENCOUNTERED IN PRIOR TURNS" \
  && pass "Block 5b: header fires" \
  || fail "Block 5b: header missing"

echo "$ac" | grep -q "npm test" \
  && pass "Block 5b: unresolved error renders" \
  || fail "Block 5b: unresolved error missing"

if echo "$ac" | grep -q "missing semi"; then
  fail "Block 5b: resolved entry leaked (should be filtered)"
else
  pass "Block 5b: resolved entry filtered out"
fi

# ---------------------------------------------------------------------------
# 11. Block 5c — Open Questions (resolved filter)
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
cat > "$sandbox/.geniro/planning/feature-x/state.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---

## Open Questions
- ts: 2026-05-19T10:30:00Z
  asked_in_phase: analyze
  question: "What OAuth provider?"
  resolved: false
- ts: 2026-05-19T10:31:00Z
  asked_in_phase: analyze
  question: "Old question"
  resolved: true
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

echo "$ac" | grep -q "PENDING QUESTIONS FROM PRIOR TURN" \
  && pass "Block 5c: header fires" \
  || fail "Block 5c: header missing"

echo "$ac" | grep -q "What OAuth provider" \
  && pass "Block 5c: unresolved question renders" \
  || fail "Block 5c: unresolved question missing"

if echo "$ac" | grep -q "Old question"; then
  fail "Block 5c: resolved entry leaked"
else
  pass "Block 5c: resolved entry filtered"
fi

# ---------------------------------------------------------------------------
# 12. Block 5d — Approvals (no filter)
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
cat > "$sandbox/.geniro/planning/feature-x/state.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: ship
status: in-progress
non-resumable-actions: []
approvals:
  - category: ship_mode
    picked: "open PR"
    at: 2026-05-19T14:00:00Z
    asked_in_phase: ship
---

body
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

echo "$ac" | grep -q "DECISIONS ALREADY MADE" \
  && pass "Block 5d: header fires" \
  || fail "Block 5d: header missing"

echo "$ac" | grep -q '\[ship_mode\] User picked: "open PR"' \
  && pass "Block 5d: approval rendering" \
  || fail "Block 5d: approval rendering wrong"

# ---------------------------------------------------------------------------
# 13. No false positives — empty state.md body produces no 5b/5c/5d blocks
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

if echo "$ac" | grep -qE "ERRORS ENCOUNTERED|PENDING QUESTIONS|DECISIONS ALREADY MADE"; then
  fail "empty state.md should produce no 5b/5c/5d blocks"
else
  pass "empty state.md: no false-positive 5b/5c/5d emission"
fi

# ---------------------------------------------------------------------------
# 14. JSON output shape — valid JSON in all cases (regression guard)
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(run_hook compact "$sandbox")
if echo "$out" | jq . >/dev/null 2>&1; then
  pass "JSON output is valid (compact)"
else
  fail "JSON output invalid: $out"
fi

out=$(run_hook resume "$sandbox")
if echo "$out" | jq . >/dev/null 2>&1; then
  pass "JSON output is valid (resume)"
else
  fail "JSON output invalid (resume): $out"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
