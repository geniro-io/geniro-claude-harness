#!/usr/bin/env bash
# Smoke test for hooks/session-start-restore.sh (SessionStart hook).
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

# Build a sandbox with a valid state.md under branch `feature/x`.
new_sandbox() {
  local d; d="$(mktemp -d "$TMPDIR_BASE/sandbox.XXXXXXXXXX")"
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
# 5. startup source with NO active task → cold-startup phrasing,
#    Block 6 suppressed, systemMessage suppressed.
# ---------------------------------------------------------------------------

sandbox="$TMPDIR_BASE/cold-$$"
mkdir -p "$sandbox" && cd "$sandbox" && git init -q && git checkout -q -b "fresh" 2>/dev/null || exit 1
out=$(run_hook startup "$sandbox")
sm=$(echo "$out" | jq -r '.systemMessage // ""')
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

[ -z "$sm" ] \
  && pass "cold startup: systemMessage suppressed" \
  || fail "cold startup: systemMessage should be suppressed — '$sm'"

# Block 1 phrasing — must NOT claim a task was detected.
if echo "$ac" | grep -q "Active task detected"; then
  fail "cold startup: Block 1 says 'Active task detected' (must omit)"
else
  pass "cold startup: Block 1 omits 'Active task detected'"
fi

echo "$ac" | grep -q "no in-flight task" \
  && pass "cold startup: Block 1 cold-startup phrasing fires" \
  || fail "cold startup: Block 1 cold-startup phrasing missing"

# Block 6 — entire resume protocol must be suppressed (no active task,
# so no "active task" block). State.md / spec.md / plan.md references would
# be meaningless.
if echo "$ac" | grep -q "Resume steps:"; then
  fail "cold startup: Block 6 should be suppressed (no active task)"
else
  pass "cold startup: Block 6 suppressed"
fi
if echo "$ac" | grep -q "Read state.md"; then
  fail "cold startup: should not reference state.md (no active task)"
else
  pass "cold startup: no state.md reference"
fi

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
# 7. Helper missing → Block 4 fires (validation skipped)
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(printf '{"source":"compact","cwd":"%s"}' "$sandbox" \
  | CLAUDE_PLUGIN_ROOT=/tmp/no-such-dir-$$ bash "$HOOK")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

echo "$ac" | grep -q "Helpers not installed" \
  && pass "helper missing: Block 4 fires" \
  || fail "helper missing: Block 4 missing"

# ---------------------------------------------------------------------------
# 8. Tier-2 fallback — task-dir name differs from slug
# ---------------------------------------------------------------------------

sandbox="$TMPDIR_BASE/tier2-$$"
mkdir -p "$sandbox" && cd "$sandbox" && git init -q && git checkout -q -b "feature/y" 2>/dev/null || exit 1
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

# slack-notify-sent + release-tagged rendering.
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
  - action: slack-notify-sent
    channel: "#deploys"
    ts: 1747393200.123456
    completed-at: 2026-05-19T14:40:00Z
  - action: release-tagged
    tag: v1.85.0
    completed-at: 2026-05-19T14:45:00Z
---

body
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

echo "$ac" | grep -q "slack-notify-sent (channel: #deploys, ts: 1747393200.123456" \
  && pass "Block 5: slack-notify-sent structured rendering" \
  || fail "Block 5: slack-notify-sent not rendered correctly"

echo "$ac" | grep -q "release-tagged (tag: v1.85.0, completed:" \
  && pass "Block 5: release-tagged structured rendering" \
  || fail "Block 5: release-tagged not rendered correctly"

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
# 13b. Validation-fail suppresses Blocks 5/5b/5c/5d (Block 3 "below")
# ---------------------------------------------------------------------------
# Frontmatter is partially valid (non-resumable + approvals + body have
# content), but schema-version is bumped to force validation failure.
sandbox=$(new_sandbox)
cat > "$sandbox/.geniro/planning/feature-x/state.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 99
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: ship
status: in-progress
non-resumable-actions:
  - action: git-push
    target: origin/feature/x
    ref: leaked
    completed-at: 2026-05-19T14:32:00Z
approvals:
  - category: ship_mode
    picked: "leaked-pick"
    at: 2026-05-19T14:00:00Z
    asked_in_phase: ship
---

## Errors
- ts: 2026-05-19T10:42:00Z
  tool: Bash
  detail: "leaked-error-detail"
  error: "leaked-error"
  attempted_fix: "leaked-fix"
  resolved: false

## Open Questions
- ts: 2026-05-19T10:30:00Z
  asked_in_phase: analyze
  question: "leaked-question"
  resolved: false
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

# Block 3 must fire.
echo "$ac" | grep -q "STATE FILE FAILED VALIDATION" \
  && pass "validation fail (schema-version): Block 3 fires" \
  || fail "validation fail (schema-version): Block 3 missing"

# Blocks 5/5b/5c/5d must all be suppressed.
if echo "$ac" | grep -qE "ALREADY COMPLETED|ERRORS ENCOUNTERED|PENDING QUESTIONS|DECISIONS ALREADY MADE"; then
  fail "validation fail: Blocks 5/5b/5c/5d leaked content from invalid state.md"
else
  pass "validation fail: Blocks 5/5b/5c/5d all suppressed"
fi

# Direct grep — make sure no leaked value made it through.
if echo "$ac" | grep -qE "leaked-error|leaked-question|leaked-pick|leaked-fix|ref: leaked"; then
  fail "validation fail: state.md content leaked into additionalContext"
else
  pass "validation fail: no leaked content from suspect state.md"
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
# 15. Terminal-state task → treated as no-active-task (mirrors Case 5).
#     A finished state.md (terminal `phase:` OR terminal `status:`) must NOT be
#     surfaced as resumable: no "Active task detected", no "Resume steps:",
#     systemMessage suppressed. Guards the /update-resumes-completed-/implement
#     regression. The `*-escalated` paused phases are the negative control —
#     they are in-flight and must still resume.
# ---------------------------------------------------------------------------

# 15a. Terminal via `phase: done` (status stays in-progress — the implement /
#      plan / refactor / onboard / investigate completion pattern).
sandbox=$(new_sandbox)
cat > "$sandbox/.geniro/planning/feature-x/state.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: done
status: in-progress
non-resumable-actions: []
---

## Phase log
- shipped
EOF

out=$(run_hook startup "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
sm=$(echo "$out" | jq -r '.systemMessage // ""')

if echo "$ac" | grep -q "Active task detected"; then
  fail "terminal phase=done: Block 1 should NOT say 'Active task detected'"
else
  pass "terminal phase=done: Block 1 omits 'Active task detected'"
fi

if echo "$ac" | grep -q "Resume steps:"; then
  fail "terminal phase=done: Block 6 resume protocol should be suppressed"
else
  pass "terminal phase=done: Block 6 suppressed"
fi

[ -z "$sm" ] \
  && pass "terminal phase=done: systemMessage suppressed (startup)" \
  || fail "terminal phase=done: systemMessage should be suppressed — '$sm'"

echo "$ac" | grep -q "no in-flight task" \
  && pass "terminal phase=done: cold-startup phrasing fires" \
  || fail "terminal phase=done: cold-startup phrasing missing"

# 15b. Terminal via `status: completed` drift (phase left at a working value).
#      The real /implement state.md that triggered the bug carried
#      `status: completed` — outside the documented in-progress|done|failed enum
#      — so the `status:` fallback must catch it independently of `phase:`.
sandbox=$(new_sandbox)
cat > "$sandbox/.geniro/planning/feature-x/state.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: implement
status: completed
non-resumable-actions: []
---

## Phase log
- shipped
EOF

out=$(run_hook startup "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
sm=$(echo "$out" | jq -r '.systemMessage // ""')

if echo "$ac" | grep -q "Active task detected"; then
  fail "terminal status=completed: Block 1 should NOT say 'Active task detected'"
else
  pass "terminal status=completed: Block 1 omits 'Active task detected'"
fi

if echo "$ac" | grep -q "Resume steps:"; then
  fail "terminal status=completed: Block 6 resume protocol should be suppressed"
else
  pass "terminal status=completed: Block 6 suppressed"
fi

[ -z "$sm" ] \
  && pass "terminal status=completed: systemMessage suppressed (startup)" \
  || fail "terminal status=completed: systemMessage should be suppressed — '$sm'"

# 15c. Negative control — a non-terminal `*-escalated` paused phase must STILL
#      resume (the terminal gate must not over-match).
sandbox=$(new_sandbox)
cat > "$sandbox/.geniro/planning/feature-x/state.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: phase-2-escalated
status: in-progress
non-resumable-actions: []
---

## Phase log
- paused at escalation
EOF

out=$(run_hook startup "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

echo "$ac" | grep -q "Active task detected" \
  && pass "escalated phase: still surfaced as active (terminal gate did not over-match)" \
  || fail "escalated phase: should still resume — 'Active task detected' missing"

# ---------------------------------------------------------------------------
# 16. Malformed / empty stdin → graceful default (no crash, valid JSON, exit 0).
#     jq parse failures fall back to source=compact with cwd unchanged; under
#     `set -uo pipefail` the hook must never abort on garbage input.
# ---------------------------------------------------------------------------

sandbox="$TMPDIR_BASE/malformed-$$"
mkdir -p "$sandbox" && cd "$sandbox" && git init -q && git checkout -q -b "fresh" 2>/dev/null || exit 1

set +e
out=$(printf 'not-json{{{' | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK"); rc=$?
set -e
[ "$rc" -eq 0 ] \
  && pass "malformed stdin: hook exits 0 (no crash)" \
  || fail "malformed stdin: expected exit 0, got $rc"
if [ -z "$out" ] || echo "$out" | jq . >/dev/null 2>&1; then
  pass "malformed stdin: output is empty or valid JSON"
else
  fail "malformed stdin: output neither empty nor valid JSON — '$out'"
fi

set +e
out=$(printf '' | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK"); rc=$?
set -e
[ "$rc" -eq 0 ] \
  && pass "empty stdin: hook exits 0 (no crash)" \
  || fail "empty stdin: expected exit 0, got $rc"
if [ -z "$out" ] || echo "$out" | jq . >/dev/null 2>&1; then
  pass "empty stdin: output is empty or valid JSON"
else
  fail "empty stdin: output neither empty nor valid JSON — '$out'"
fi

# ---------------------------------------------------------------------------
# 17. Terminal Tier-1a candidate must not shadow an in-flight Tier-1b task —
#     resolution skips finished candidates instead of discarding the final pick.
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
# Finish the planning task (terminal phase) and add a live debug slug dir on
# the same branch.
sed -i.bak 's/^phase: implement$/phase: done/' "$sandbox/.geniro/planning/feature-x/state.md"
rm -f "$sandbox/.geniro/planning/feature-x/state.md.bak"
mkdir -p "$sandbox/.geniro/state/debug/feature-x"
cat > "$sandbox/.geniro/state/debug/feature-x/state.md" <<'EOF'
---
tier: T1
producer: debug
schema-version: 1
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: investigate
status: in-progress
non-resumable-actions: []
---

## Phase log
- observing
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

echo "$ac" | grep -q "state/debug/feature-x/state.md" \
  && pass "terminal planning state does not shadow the live debug task" \
  || fail "terminal planning state shadows the live debug task"

if echo "$ac" | grep -q "planning/feature-x/state.md"; then
  fail "finished planning state.md should not be surfaced"
else
  pass "finished planning state.md is not surfaced"
fi

# ---------------------------------------------------------------------------
# 18. Auto-archive hash marker is written only after a SUCCESSFUL helper run —
#     a failed run must stay retry-eligible on the next session start.
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
mkdir -p "$sandbox/.geniro/knowledge"
printf '%s\n%s\n' '{"type":"discovery","dedup_key":"a"}' '{"type":"discovery","dedup_key":"b"}' \
  > "$sandbox/.geniro/knowledge/learnings.jsonl"

# Helper unreachable (bogus plugin root) → run fails → marker must NOT appear.
printf '{"source":"startup","cwd":"%s"}' "$sandbox" \
  | GENIRO_AUTO_ARCHIVE_THRESHOLD=1 CLAUDE_PLUGIN_ROOT="/tmp/no-such-dir-$$" bash "$HOOK" >/dev/null 2>&1
if [ ! -f "$sandbox/.geniro/knowledge/.archive-stale.hash" ]; then
  pass "archive hash marker NOT written when the helper run fails"
else
  fail "archive hash marker written despite a failed helper run"
fi

# Real plugin root → helper succeeds → marker appears.
printf '{"source":"startup","cwd":"%s"}' "$sandbox" \
  | GENIRO_AUTO_ARCHIVE_THRESHOLD=1 CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK" >/dev/null 2>&1
if [ -f "$sandbox/.geniro/knowledge/.archive-stale.hash" ]; then
  pass "archive hash marker written after a successful helper run"
else
  fail "archive hash marker missing after a successful helper run"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
