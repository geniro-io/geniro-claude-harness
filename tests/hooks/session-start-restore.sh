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

grep -q "Context was compressed by compaction" <<<"$ac" \
  && pass "compact: Block 1 prefix" \
  || fail "compact: Block 1 prefix missing"

grep -q "instructions/implement.md" <<<"$ac" \
  && pass "compact: Block 2 active-skill instructions pointer" \
  || fail "compact: active-skill pointer missing"

grep -q "state.md" <<<"$ac" \
  && pass "compact: Block 2 state.md pointer (validation passed)" \
  || fail "compact: state.md pointer missing"

grep -q "Resume steps:" <<<"$ac" \
  && pass "compact: Block 6 resume protocol header" \
  || fail "compact: Block 6 missing"

grep -q "active task: feature-x · skill: /implement · branch: feature/x · phase: implement · non-resumable: 0" <<<"$sm" \
  && pass "compact: systemMessage shape (task/skill/branch/phase/non-resumable)" \
  || fail "compact: systemMessage shape wrong — '$sm'"

# ---------------------------------------------------------------------------
# 3. resume source → "Restoring from prior session" prefix
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(run_hook resume "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
grep -q "Restoring from prior session" <<<"$ac" \
  && pass "resume: Block 1 phrasing" \
  || fail "resume: Block 1 phrasing missing"

# ---------------------------------------------------------------------------
# 4. startup source with active task → "Active task detected"
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(run_hook startup "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
sm=$(echo "$out" | jq -r '.systemMessage // ""')

grep -q "Active task detected at startup" <<<"$ac" \
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
if grep -q "Active task detected" <<<"$ac"; then
  fail "cold startup: Block 1 says 'Active task detected' (must omit)"
else
  pass "cold startup: Block 1 omits 'Active task detected'"
fi

grep -q "no in-flight task" <<<"$ac" \
  && pass "cold startup: Block 1 cold-startup phrasing fires" \
  || fail "cold startup: Block 1 cold-startup phrasing missing"

# Block 6 — entire resume protocol must be suppressed (no active task,
# so no "active task" block). State.md / spec.md / plan.md references would
# be meaningless.
if grep -q "Resume steps:" <<<"$ac"; then
  fail "cold startup: Block 6 should be suppressed (no active task)"
else
  pass "cold startup: Block 6 suppressed"
fi
if grep -q "Read state.md" <<<"$ac"; then
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

grep -q "STATE FILE FAILED VALIDATION" <<<"$ac" \
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

grep -q "Helpers not installed" <<<"$ac" \
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
grep -q "active task: different-name · skill: /refactor · branch: feature/y · phase: rewrite" <<<"$sm" \
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

grep -q "git-push (target: origin/feature/x, ref: a3f9e2" <<<"$ac" \
  && pass "Block 5: git-push structured rendering" \
  || fail "Block 5: git-push not rendered correctly"

grep -q "pr-comment-posted (pr: 142, comment-id: 1834720" <<<"$ac" \
  && pass "Block 5: pr-comment-posted rendering" \
  || fail "Block 5: pr-comment-posted not rendered correctly"

grep -q "custom-unknown (completed:" <<<"$ac" \
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

grep -q "slack-notify-sent (channel: #deploys, ts: 1747393200.123456" <<<"$ac" \
  && pass "Block 5: slack-notify-sent structured rendering" \
  || fail "Block 5: slack-notify-sent not rendered correctly"

grep -q "release-tagged (tag: v1.85.0, completed:" <<<"$ac" \
  && pass "Block 5: release-tagged structured rendering" \
  || fail "Block 5: release-tagged not rendered correctly"

# pr-comment-amended rendering (review post-posting overturn reconciliation).
sandbox=$(new_sandbox)
cat > "$sandbox/.geniro/planning/feature-x/state.md" <<'EOF'
---
tier: T1
producer: review
schema-version: 1
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: action-gate
status: in-progress
non-resumable-actions:
  - action: pr-comment-amended
    pr-ref: owner/repo#2811
    comment-id: 123456789
    kind: delete
    completed-at: 2026-05-19T14:50:00Z
---

body
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

grep -q "pr-comment-amended (pr: owner/repo#2811, comment-id: 123456789, kind: delete, completed:" <<<"$ac" \
  && pass "Block 5: pr-comment-amended structured rendering" \
  || fail "Block 5: pr-comment-amended not rendered correctly"

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

grep -q "ERRORS ENCOUNTERED IN PRIOR TURNS" <<<"$ac" \
  && pass "Block 5b: header fires" \
  || fail "Block 5b: header missing"

grep -q "npm test" <<<"$ac" \
  && pass "Block 5b: unresolved error renders" \
  || fail "Block 5b: unresolved error missing"

if grep -q "missing semi" <<<"$ac"; then
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

grep -q "PENDING QUESTIONS FROM PRIOR TURN" <<<"$ac" \
  && pass "Block 5c: header fires" \
  || fail "Block 5c: header missing"

grep -q "What OAuth provider" <<<"$ac" \
  && pass "Block 5c: unresolved question renders" \
  || fail "Block 5c: unresolved question missing"

if grep -q "Old question" <<<"$ac"; then
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

grep -q "DECISIONS ALREADY MADE" <<<"$ac" \
  && pass "Block 5d: header fires" \
  || fail "Block 5d: header missing"

grep -q '\[ship_mode\] User picked: "open PR"' <<<"$ac" \
  && pass "Block 5d: approval rendering" \
  || fail "Block 5d: approval rendering wrong"

# An entry carrying none of the three optional fields must render exactly the two
# lines it always did — no stray "why:" label, no empty-value noise.
grep -q 'why:' <<<"$ac" \
  && fail "Block 5d: rendered a why: label for an entry that carries no why" \
  || pass "Block 5d: optional fields absent render nothing"

# ---------------------------------------------------------------------------
# 12b. Block 5d renders the optional why / result, and omits evidence
# ---------------------------------------------------------------------------
# `why` and `result` are what let a resumed session judge whether a recorded
# decision still holds, so they have to reach the block or the fields are dead
# weight. `evidence` deliberately does not: it stays in the file for a reader
# re-checking the premise, and this block fires on every compaction and resume.
# An empty string is truthy in jq, so the empty `why` below is the real trap —
# a presence test would print a bare label for it.

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
    why: "the branch already had an open PR reviewers were watching"
    evidence: "gh pr view reported state OPEN"
    result: "PR 412 updated, no new PR created"
  - category: rereview_scope_choice
    picked: "Re-review the whole PR"
    at: 2026-05-19T14:05:00Z
    asked_in_phase: triage
    why: ""
---

body
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

grep -q 'why: the branch already had an open PR' <<<"$ac" \
  && pass "Block 5d: renders why when recorded" \
  || fail "Block 5d: why not rendered"

grep -q 'result: PR 412 updated' <<<"$ac" \
  && pass "Block 5d: renders result when recorded" \
  || fail "Block 5d: result not rendered"

grep -q 'gh pr view reported state OPEN' <<<"$ac" \
  && fail "Block 5d: evidence leaked into the block — it belongs in the file only" \
  || pass "Block 5d: evidence stays out of the block"

# The second entry carries `why: ""`. jq treats "" as truthy, so a presence test
# would emit `why: ` with nothing after it.
grep -qE 'why:[[:space:]]*$' <<<"$ac" \
  && fail "Block 5d: an empty why rendered a bare label" \
  || pass "Block 5d: an empty-string why renders nothing"

grep -q '\[rereview_scope_choice\] User picked: "Re-review the whole PR"' <<<"$ac" \
  && pass "Block 5d: an entry with only the required fields still renders" \
  || fail "Block 5d: entry with empty optional field stopped rendering"

# ---------------------------------------------------------------------------
# 12c. Block 5d — every spelling of "no reason recorded", not just `""`
# ---------------------------------------------------------------------------
# The guard is `(.why // "") != ""`, and it recognizes exactly one contentless
# value: the empty string. The frontmatter parser hands jq the raw scalar it read,
# so every other way of writing "nothing here" arrives as a non-empty string and
# prints. `why: "  "` makes the same claim as the `why: ""` case above and gets the
# bare label that case rules out; `null` and `~` are YAML's own words for an absent
# value, and rendering one puts a reason in front of a resumed session that no
# producer ever wrote.

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
    why: "  "
  - category: rereview_scope_choice
    picked: "Re-review the whole PR"
    at: 2026-05-19T14:05:00Z
    asked_in_phase: triage
    why: null
  - category: minor_findings
    picked: "fix now"
    at: 2026-05-19T14:07:00Z
    asked_in_phase: review
    result: ~
---

body
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

grep -q '\[minor_findings\] User picked: "fix now"' <<<"$ac" \
  && pass "Block 5d: all three entries render" \
  || fail "Block 5d: the third entry did not render — the fixture, not the guard, is being measured"

grep -qE 'why:[[:space:]]*$' <<<"$ac" \
  && fail "Block 5d: a whitespace-only why rendered a bare 'why:' label — the same empty claim as why: \"\", which the case above already requires to render nothing" \
  || pass "Block 5d: a whitespace-only why renders nothing"

grep -qE 'why:[[:space:]]*(null|~)[[:space:]]*$' <<<"$ac" \
  && fail "Block 5d: 'why: null' rendered the literal word null as the reason a decision was made — YAML null is an absent value, and the block presents it to the resumed session as recorded rationale" \
  || pass "Block 5d: a null why renders nothing"

grep -qE 'result:[[:space:]]*(null|~)[[:space:]]*$' <<<"$ac" \
  && fail "Block 5d: 'result: ~' rendered '~' as what acting on the pick produced — an absent result is the signal that the decision was recorded but never acted on, and this spelling of absent reads as a recorded outcome instead" \
  || pass "Block 5d: a tilde result renders nothing"

# A reason too long for one line is written as a block scalar, and the frontmatter
# parser reads only the marker: the continuation lines match no rule and fall
# through. What reaches the block is `why: |` — a label whose content was dropped.
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
    why: |
      the branch already had an open PR reviewers were watching,
      so a second one would have split the review in half
---

body
EOF

out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

grep -qE 'why:[[:space:]]*[|>][[:space:]]*$' <<<"$ac" \
  && fail "Block 5d: a block-scalar why rendered the YAML marker as the reason ('why: |') and dropped the two lines under it — the block must carry the reason or say nothing, never a marker standing in for one" \
  || pass "Block 5d: a block-scalar why does not render its YAML marker as the reason"

# ---------------------------------------------------------------------------
# 13. No false positives — empty state.md body produces no 5b/5c/5d blocks
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

if grep -qE "ERRORS ENCOUNTERED|PENDING QUESTIONS|DECISIONS ALREADY MADE" <<<"$ac"; then
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
grep -q "STATE FILE FAILED VALIDATION" <<<"$ac" \
  && pass "validation fail (schema-version): Block 3 fires" \
  || fail "validation fail (schema-version): Block 3 missing"

# Blocks 5/5b/5c/5d must all be suppressed.
if grep -qE "ALREADY COMPLETED|ERRORS ENCOUNTERED|PENDING QUESTIONS|DECISIONS ALREADY MADE" <<<"$ac"; then
  fail "validation fail: Blocks 5/5b/5c/5d leaked content from invalid state.md"
else
  pass "validation fail: Blocks 5/5b/5c/5d all suppressed"
fi

# Direct grep — make sure no leaked value made it through.
if grep -qE "leaked-error|leaked-question|leaked-pick|leaked-fix|ref: leaked" <<<"$ac"; then
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

if grep -q "Active task detected" <<<"$ac"; then
  fail "terminal phase=done: Block 1 should NOT say 'Active task detected'"
else
  pass "terminal phase=done: Block 1 omits 'Active task detected'"
fi

if grep -q "Resume steps:" <<<"$ac"; then
  fail "terminal phase=done: Block 6 resume protocol should be suppressed"
else
  pass "terminal phase=done: Block 6 suppressed"
fi

[ -z "$sm" ] \
  && pass "terminal phase=done: systemMessage suppressed (startup)" \
  || fail "terminal phase=done: systemMessage should be suppressed — '$sm'"

grep -q "no in-flight task" <<<"$ac" \
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

if grep -q "Active task detected" <<<"$ac"; then
  fail "terminal status=completed: Block 1 should NOT say 'Active task detected'"
else
  pass "terminal status=completed: Block 1 omits 'Active task detected'"
fi

if grep -q "Resume steps:" <<<"$ac"; then
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

grep -q "Active task detected" <<<"$ac" \
  && pass "escalated phase: still surfaced as active (terminal gate did not over-match)" \
  || fail "escalated phase: should still resume — 'Active task detected' missing"

# 15d. Terminal via bare `phase: escalated` (review's terminal phase, written
#      without a guaranteed terminal `status:`). Must NOT surface as resumable.
#      Pairs with 15c: the whole-word terminal gate catches `escalated` but
#      leaves the hyphenated `*-escalated` paused phases resumable.
sandbox=$(new_sandbox)
cat > "$sandbox/.geniro/planning/feature-x/state.md" <<'EOF'
---
tier: T1
producer: review
schema-version: 1
branch: feature/x
timestamp: 2026-05-19T15:00:00Z
phase: escalated
status: in-progress
non-resumable-actions: []
---

## Phase log
- escalated after max rounds
EOF

out=$(run_hook startup "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

if grep -q "Active task detected" <<<"$ac"; then
  fail "terminal phase=escalated: Block 1 should NOT say 'Active task detected'"
else
  pass "terminal phase=escalated: Block 1 omits 'Active task detected'"
fi

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

grep -q "state/debug/feature-x/state.md" <<<"$ac" \
  && pass "terminal planning state does not shadow the live debug task" \
  || fail "terminal planning state shadows the live debug task"

if grep -q "planning/feature-x/state.md" <<<"$ac"; then
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
# 19. Block 1b — standing behavioral contracts re-asserted only with an active
#     task. Compaction keeps file pointers but drops the behavioral rules, so the
#     block must fire when a resolvable in-flight state.md exists and stay absent
#     on cold startup.
# ---------------------------------------------------------------------------

sandbox=$(new_sandbox)
out=$(run_hook compact "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

grep -q "work, not authority" <<<"$ac" \
  && pass "Block 1b: contract block fires with an active task" \
  || fail "Block 1b: contract block missing with an active task"

# Cold startup (no active task) → block must be absent.
sandbox="$TMPDIR_BASE/cold1b-$$"
mkdir -p "$sandbox" && cd "$sandbox" && git init -q && git checkout -q -b "fresh" 2>/dev/null || exit 1
out=$(run_hook startup "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')

if grep -q "work, not authority" <<<"$ac"; then
  fail "Block 1b: contract block should be absent on cold startup"
else
  pass "Block 1b: contract block absent on cold startup"
fi

# ---------------------------------------------------------------------------
# 20. Verification-coverage suffix on systemMessage — present when learnings.jsonl
#     has live entries; absent when safety.json sets memory.show_coverage: false.
# ---------------------------------------------------------------------------

# 20a. Coverage suffix appears (default ON). Live set: 2 entries, 1 verified -> 50%.
sandbox=$(new_sandbox)
mkdir -p "$sandbox/.geniro/knowledge"
{
  printf '%s\n' '{"type":"discovery","trust":"verified","dedup_key":"v1"}'
  printf '%s\n' '{"type":"discovery","trust":"inferred","dedup_key":"i1"}'
} > "$sandbox/.geniro/knowledge/learnings.jsonl"

out=$(run_hook compact "$sandbox")
sm=$(echo "$out" | jq -r '.systemMessage // ""')
grep -q "memory verified: 1/2 (50%)" <<<"$sm" \
  && pass "coverage suffix present on systemMessage (default ON)" \
  || fail "coverage suffix missing/wrong — '$sm'"

# 20b. Opt-out via memory.show_coverage:false suppresses the suffix.
mkdir -p "$sandbox/.geniro"
cat > "$sandbox/.geniro/safety.json" <<'EOF'
{ "memory": { "show_coverage": false } }
EOF
out=$(run_hook compact "$sandbox")
sm=$(echo "$out" | jq -r '.systemMessage // ""')
if grep -q "verified:" <<<"$sm"; then
  fail "coverage suffix should be suppressed when show_coverage:false — '$sm'"
else
  pass "coverage suffix suppressed when memory.show_coverage:false"
fi

# 20c. Coverage overrides cold-startup systemMessage suppression — a fresh repo
#      with no active task but a learnings.jsonl still emits the memory-health line.
sandbox="$TMPDIR_BASE/cov-cold-$$"
mkdir -p "$sandbox/.geniro/knowledge" && cd "$sandbox" && git init -q && git checkout -q -b "fresh" 2>/dev/null || exit 1
{
  printf '%s\n' '{"type":"discovery","trust":"verified","dedup_key":"v1"}'
  printf '%s\n' '{"type":"discovery","trust":"verified","dedup_key":"v2"}'
} > "$sandbox/.geniro/knowledge/learnings.jsonl"

out=$(run_hook startup "$sandbox")
sm=$(echo "$out" | jq -r '.systemMessage // ""')
grep -q "memory verified: 2/2 (100%)" <<<"$sm" \
  && pass "coverage overrides cold-startup suppression (systemMessage emitted)" \
  || fail "coverage should emit systemMessage on cold startup — '$sm'"

# 20d. Empty (0-byte) learnings.jsonl on cold startup → NO coverage suffix and
#      no systemMessage. The coverage block guards on `[ -s ]` (non-empty), so an
#      empty file folds to "no coverage" instead of computing "n/a" — a non-empty
#      string that would otherwise defeat cold-startup suppression and fire a
#      bogus `verified: n/a` line with zero learnings.
sandbox="$TMPDIR_BASE/cov-empty-$$"
mkdir -p "$sandbox/.geniro/knowledge" && cd "$sandbox" && git init -q && git checkout -q -b "fresh" 2>/dev/null || exit 1
: > "$sandbox/.geniro/knowledge/learnings.jsonl"   # 0-byte file

out=$(run_hook startup "$sandbox")
sm=$(echo "$out" | jq -r '.systemMessage // ""')
if grep -q "verified:" <<<"$sm"; then
  fail "empty learnings.jsonl emitted a coverage suffix — '$sm'"
else
  pass "empty learnings.jsonl: no coverage suffix (no verified: n/a spam)"
fi
[ -z "$sm" ] \
  && pass "empty learnings.jsonl on cold startup: systemMessage suppressed" \
  || fail "empty learnings.jsonl on cold startup: systemMessage should be suppressed — '$sm'"

# 20e. Non-empty ALL-DEPRECATED learnings.jsonl on cold startup → NO coverage
#      suffix and no systemMessage. The file is non-empty (passes `[ -s ]`), but
#      every entry is deprecated, so the live set is empty and coverage computes
#      the "n/a" sentinel. The assignment filters "n/a" out, so COVERAGE_SUFFIX
#      stays empty and cold-startup suppression holds — no bogus `verified: n/a`.
sandbox="$TMPDIR_BASE/cov-alldep-$$"
mkdir -p "$sandbox/.geniro/knowledge" && cd "$sandbox" && git init -q && git checkout -q -b "fresh" 2>/dev/null || exit 1
{
  printf '%s\n' '{"type":"discovery","trust":"verified","dedup_key":"d1","deprecated":true}'
  printf '%s\n' '{"type":"discovery","trust":"inferred","dedup_key":"d2","deprecated":true}'
} > "$sandbox/.geniro/knowledge/learnings.jsonl"

out=$(run_hook startup "$sandbox")
sm=$(echo "$out" | jq -r '.systemMessage // ""')
if grep -q "verified:" <<<"$sm"; then
  fail "all-deprecated learnings.jsonl emitted a coverage suffix — '$sm'"
else
  pass "all-deprecated learnings.jsonl: no coverage suffix (no verified: n/a spam)"
fi
[ -z "$sm" ] \
  && pass "all-deprecated learnings.jsonl on cold startup: systemMessage suppressed" \
  || fail "all-deprecated learnings.jsonl on cold startup: systemMessage should be suppressed — '$sm'"

# ---------------------------------------------------------------------------
# 21. memory.auto_archive_stale opt-out must actually disable. jq's `//` treats
#     a boolean `false` as empty and falls through to the default, so a
#     `.memory.auto_archive_stale // true` resolver would never disable the
#     feature. Guard the explicit `== false` resolver against regressing.
# ---------------------------------------------------------------------------
if grep -q 'auto_archive_stale // true' "$HOOK"; then
  fail "hook reintroduced the broken 'auto_archive_stale // true' opt-out (jq // eats boolean false)"
else
  pass "hook uses the explicit == false opt-out resolver (no // true)"
fi

# Behavioral half — drive the ACTUAL hook resolver, not a local copy. Build a
# corpus that exceeds the auto-archive line threshold (lowered via the env knob,
# the same pattern test 18 uses) and contains an archivable stale entry, so
# auto-archive WOULD fire. The opt-out is the only thing that should suppress it,
# so a regression of the hook's real `== false` resolver flips these assertions.
#
# Stale entry: ts in 2020 (age » 180d), trust inferred, access_count 0,
# recurrence_count 1 → score « 0.1 (matches lib/archive-stale.sh criteria, same
# corpus shape as tests/memory/archive-stale.sh). A fresh control keeps the
# total over the threshold without itself being archivable.
write_archivable_corpus() {
  {
    printf '%s\n' '{"producer":"/debug","scope":"x","summary":"stale one","tags":["bug"],"type":"diagnosis","ts":"2020-01-01T00:00:00Z","trust":"inferred","access_count":0,"recurrence_count":1,"dedup_key":"opt-stale1"}'
    printf '{"producer":"/debug","scope":"x","summary":"fresh one","tags":["bug"],"type":"diagnosis","ts":"%s","trust":"verified","access_count":0,"recurrence_count":1,"dedup_key":"opt-fresh1"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$1"
}

# 21a. Default ON (no safety.json) → real hook archives the stale entry and the
#      systemMessage carries the `auto-archived: N` suffix. The on-disk flip is
#      the deterministic signal; the suffix is the user-visible observable.
sandbox=$(new_sandbox)
mkdir -p "$sandbox/.geniro/knowledge"
write_archivable_corpus "$sandbox/.geniro/knowledge/learnings.jsonl"
# cd into the sandbox: the hook's safety.json resolver walks up from $PWD, so the
# opt-out check in 21b must see this sandbox's tree, not a sibling's.
cd "$sandbox" || exit 1
out=$(printf '{"source":"compact","cwd":"%s"}' "$sandbox" \
  | GENIRO_AUTO_ARCHIVE_THRESHOLD=1 CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK")
sm=$(echo "$out" | jq -r '.systemMessage // ""')
dep=$(jq -r 'select(.dedup_key=="opt-stale1") | (.deprecated // false)' "$sandbox/.geniro/knowledge/learnings.jsonl")
[ "$dep" = "true" ] \
  && pass "default-ON: real hook flips the stale entry to deprecated on disk" \
  || fail "default-ON: real hook should archive the stale entry (deprecated=true); got deprecated=$dep"
grep -Eq 'auto-archived: [1-9][0-9]*' <<<"$sm" \
  && pass "default-ON: systemMessage carries the auto-archived: N suffix" \
  || fail "default-ON: real hook should show auto-archived: N — '$sm'"
# The hash marker is written via stage-and-rename (mv), not a bare truncating
# redirect — a completed run must leave a non-empty marker and no stray .tmp
# leftovers in .geniro/knowledge/ (a leftover would mean the rename never ran,
# e.g. a failure mid-write left the tmp file orphaned).
hm="$sandbox/.geniro/knowledge/.archive-stale.hash"
[ -s "$hm" ] \
  && pass "hash marker written (non-empty) after a successful archive run" \
  || fail "hash marker should be non-empty after a successful run — got: $(cat "$hm" 2>/dev/null || echo '<missing>')"
if find "$sandbox/.geniro/knowledge" -maxdepth 1 -name '*.tmp.*' | grep -q .; then
  fail "stray .archive-stale.hash.tmp.* file left behind (stage-and-rename did not complete)"
else
  pass "no stray .archive-stale.hash.tmp.* file left behind after the run"
fi

# 21b. Opt-out ON via safety.json → real hook's `== false` resolver disables
#      auto-archive, so NO `auto-archived:` suffix appears. Fresh sandbox so the
#      opt-out (not run 21a's already-flipped entry or the hash gate) is the only
#      thing that can suppress archival.
sandbox=$(new_sandbox)
mkdir -p "$sandbox/.geniro/knowledge" "$sandbox/.geniro"
write_archivable_corpus "$sandbox/.geniro/knowledge/learnings.jsonl"
cat > "$sandbox/.geniro/safety.json" <<'EOF'
{ "memory": { "auto_archive_stale": false } }
EOF
# cd in so the hook's $PWD-anchored safety.json walk-up finds THIS opt-out file.
cd "$sandbox" || exit 1
out=$(printf '{"source":"compact","cwd":"%s"}' "$sandbox" \
  | GENIRO_AUTO_ARCHIVE_THRESHOLD=1 CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK")
sm=$(echo "$out" | jq -r '.systemMessage // ""')
if grep -q "auto-archived:" <<<"$sm"; then
  fail "opt-out: auto_archive_stale:false must suppress archival via the real hook resolver — '$sm'"
else
  pass "opt-out genuinely disables auto-archive via the real hook (no auto-archived suffix)"
fi
# Confirm the stale entry was left untouched on disk (opt-out skipped the run,
# not merely the suffix) — the entry must NOT be flipped to deprecated:true.
dep=$(jq -r 'select(.dedup_key=="opt-stale1") | (.deprecated // false)' "$sandbox/.geniro/knowledge/learnings.jsonl")
[ "$dep" = "false" ] \
  && pass "opt-out leaves the stale entry un-archived on disk (deprecated still false)" \
  || fail "opt-out should leave the entry un-archived; deprecated=$dep"

# 21c. Malformed safety.json (jq cannot parse it) must fail CLOSED on the
#      opt-out check — treated as opt-out, not as default-on. Before the fix,
#      jq's exit status went uncaptured: a parse failure left `_opt` empty,
#      `[ "$_opt" = "false" ]` was false, and auto-archive ran anyway despite
#      the file being unreadable — the opposite of every OTHER safety.json
#      reader's fail-closed posture (file-protection.sh, block-dangerous-git.sh,
#      block-geniro-deletion.sh all block on a coarse scan when jq can't read
#      their allowlist). Same corpus/threshold shape as 21a/21b.
sandbox=$(new_sandbox)
mkdir -p "$sandbox/.geniro/knowledge" "$sandbox/.geniro"
write_archivable_corpus "$sandbox/.geniro/knowledge/learnings.jsonl"
printf '%s\n' '{ this is not valid json' > "$sandbox/.geniro/safety.json"
cd "$sandbox" || exit 1
out=$(printf '{"source":"compact","cwd":"%s"}' "$sandbox" \
  | GENIRO_AUTO_ARCHIVE_THRESHOLD=1 CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK")
sm=$(echo "$out" | jq -r '.systemMessage // ""')
if grep -q "auto-archived:" <<<"$sm"; then
  fail "malformed safety.json: unparseable file must fail-closed (suppress), not fail-open — '$sm'"
else
  pass "malformed safety.json: unparseable file fails closed (auto-archive suppressed)"
fi
dep=$(jq -r 'select(.dedup_key=="opt-stale1") | (.deprecated // false)' "$sandbox/.geniro/knowledge/learnings.jsonl")
[ "$dep" = "false" ] \
  && pass "malformed safety.json leaves the stale entry un-archived on disk" \
  || fail "malformed safety.json should leave the entry un-archived; deprecated=$dep"

# ---------------------------------------------------------------------------
# 22. Tier-2 staleness gate — a branch-matched candidate untouched past
#     GENIRO_RESUME_STALE_DAYS is NOT surfaced (an abandoned /plan on a
#     long-lived branch like `main` stops resurfacing on every session); a fresh
#     one still is; the env knob set to 0 disables the gate. Tier-2 only (an exact
#     slug match is never gated). Uses file mtime, so a freshly-written fixture is
#     "fresh" regardless of its frontmatter timestamp.
# ---------------------------------------------------------------------------

# 22a. Stale Tier-2 candidate (mtime backdated well past the cutoff) → suppressed.
sandbox="$TMPDIR_BASE/stale-$$"
mkdir -p "$sandbox" && cd "$sandbox" && git init -q && git checkout -q -b "main" 2>/dev/null || exit 1
mkdir -p .geniro/planning/ghost-plan
cat > .geniro/planning/ghost-plan/state.md <<'EOF'
---
tier: T1
producer: plan
schema-version: 1
branch: main
timestamp: 2026-05-19T15:00:00Z
phase: clarify
status: in-progress
non-resumable-actions: []
---

body
EOF
touch -t 202501010000 .geniro/planning/ghost-plan/state.md

out=$(run_hook startup "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
if grep -q "Active task detected" <<<"$ac"; then
  fail "stale Tier-2 candidate should NOT be surfaced (mtime past cutoff)"
else
  pass "stale Tier-2 candidate suppressed (past GENIRO_RESUME_STALE_DAYS)"
fi

# 22b. Same candidate, fresh mtime → surfaced (gate only skips stale ones).
touch .geniro/planning/ghost-plan/state.md
out=$(run_hook startup "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
grep -q "Active task detected" <<<"$ac" \
  && pass "fresh Tier-2 candidate still surfaced (gate only skips stale)" \
  || fail "fresh Tier-2 candidate should be surfaced"

# 22c. GENIRO_RESUME_STALE_DAYS=0 disables the gate → stale candidate surfaces.
touch -t 202501010000 .geniro/planning/ghost-plan/state.md
out=$(printf '{"source":"startup","cwd":"%s"}' "$sandbox" \
  | GENIRO_RESUME_STALE_DAYS=0 CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
grep -q "Active task detected" <<<"$ac" \
  && pass "GENIRO_RESUME_STALE_DAYS=0 disables the staleness gate (stale candidate surfaces)" \
  || fail "GENIRO_RESUME_STALE_DAYS=0 should disable the staleness gate"

# 22d. Tier-1 (exact slug match) is NEVER staleness-gated — a stale task-dir whose
#      name equals the branch slug must still resume.
sandbox="$TMPDIR_BASE/tier1-stale-$$"
mkdir -p "$sandbox" && cd "$sandbox" && git init -q && git checkout -q -b "feature/z" 2>/dev/null || exit 1
mkdir -p .geniro/planning/feature-z
cat > .geniro/planning/feature-z/state.md <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: feature/z
timestamp: 2026-05-19T15:00:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---

body
EOF
touch -t 202501010000 .geniro/planning/feature-z/state.md

out=$(run_hook startup "$sandbox")
ac=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
grep -q "Active task detected" <<<"$ac" \
  && pass "Tier-1 exact slug match resumes even when stale (never gated)" \
  || fail "Tier-1 exact slug match should not be staleness-gated"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
