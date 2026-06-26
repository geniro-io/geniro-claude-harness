#!/usr/bin/env bash
# Smoke test for hooks/enforce-state-helper.sh (PreToolUse Edit|Write|MultiEdit AND Bash, block-mode).
#
# Run: bash tests/hooks/enforce-state-helper.sh
#
# Coverage:
#   - State-path write blocks (exit 2) with the atomic-helper guidance.
#   - JSONL knowledge path suggests atomic_state_append; others atomic_state_write.
#   - Non-canonical .geniro/state/ path gets the canonical-layout hint.
#   - Excluded transient files (locks, notes.md, .tmp) stay silent (exit 0).
#   - Non-state paths stay silent.
#   - .geniro/state/tdd/ paths are exempt (own mktemp + mv procedure).
#   - Bash branch: redirection / tee / sed -i / cp / mv / dd into state paths block.
#   - Bash branch: atomic_state_write/append invocation, reads, non-state writes allow.
#   - enforce-state-helper bypass via safety.json (both branches).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/enforce-state-helper.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Edit/Write-form payload (content arbitrary; the guard is file_path-based).
run_path() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, content: "x"}}' | bash "$HOOK" 2>&1
}
rc_path() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, content: "x"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
# Bash-form payload -> exit code.
rc_bash() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
run_bash() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOOK" 2>&1
}
expect_block() { if [ "$2" = "2" ]; then pass "$1"; else fail "$1 (expected exit=2, got exit=$2)"; fi; }
expect_allow() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1 (expected exit=0, got exit=$2)"; fi; }

cd "$TMPDIR_BASE" || exit 1

# ===== Edit/Write branch: state path now hard-blocks =====
out=$(run_path '/proj/.geniro/state/handoff/from-review-main.md')
expect_block "block mode blocks the state write (exit 2)" "$(rc_path '/proj/.geniro/state/handoff/from-review-main.md')"
if printf '%s' "$out" | grep -q 'atomic_state_write'; then
  pass "state path suggests atomic_state_write"
else
  fail "state path suggests atomic_state_write"
fi

out=$(run_path '/proj/.geniro/knowledge/learnings.jsonl')
if printf '%s' "$out" | grep -q 'atomic_state_append'; then
  pass "jsonl knowledge path suggests atomic_state_append"
else
  fail "jsonl knowledge path suggests atomic_state_append"
fi

# Canonical state/<skill>/<slug>/state.md must NOT carry the layout hint.
out=$(run_path '/proj/.geniro/state/review/slug/state.md')
expect_block "canonical state/<skill>/<slug>/state.md blocks" "$(rc_path '/proj/.geniro/state/review/slug/state.md')"
if printf '%s' "$out" | grep -q 'matches no canonical layout'; then
  fail "canonical layout does NOT emit the layout hint"
else
  pass "canonical layout does NOT emit the layout hint"
fi
# Ad-hoc file directly under .geniro/state/ gets the canonical-layout hint.
out=$(run_path '/proj/.geniro/state/integration-flakes.md')
if printf '%s' "$out" | grep -q 'matches no canonical layout'; then
  pass "non-canonical state/ path gets the layout hint"
else
  fail "non-canonical state/ path gets the layout hint"
fi

# ===== Edit/Write branch: exclusions and exemptions stay silent =====
expect_allow "non-state path stays silent"          "$(rc_path '/proj/src/app.js')"
expect_allow "lock file is excluded"                "$(rc_path '/proj/.geniro/planning/.codebase-map.lock')"
expect_allow "scratch notes.md is excluded"         "$(rc_path '/proj/.geniro/planning/task-dir/notes.md')"
expect_allow "atomic-write temp file is excluded"   "$(rc_path '/proj/.geniro/state/x/state.md.tmp.123.host')"
expect_allow ".geniro/state/tdd/ path is exempt"    "$(rc_path '/proj/.geniro/state/tdd/state-myslug.md')"

# ===== Bash branch: shell-side writes into state paths block =====
expect_block "bash: redirect into state path blocks"   "$(rc_bash 'echo x > .geniro/state/review/s/state.md')"
# Regression: the sanctioned-helper allow-check runs AFTER the quote+comment
# scrub, so the helper name appearing only in a string or comment can no longer
# disable the guard while a real invocation still passes.
expect_block "bash: helper name in echo string still blocks"   "$(rc_bash 'echo "atomic_state_write" > .geniro/state/review/s/state.md')"
expect_block "bash: helper name in trailing comment still blocks" "$(rc_bash 'echo x > .geniro/state/review/s/state.md  # atomic_state_write')"
expect_block "bash: append into state path blocks"     "$(rc_bash 'printf y >> ./.geniro/planning/td/state.md')"
expect_block "bash: tee into state path blocks"        "$(rc_bash 'echo x | tee .geniro/state/debug/s/state.md')"
expect_block "bash: sed -i on state file blocks"       "$(rc_bash "sed -i.bak 's/a/b/' .geniro/instructions/global.md")"
expect_block "bash: mv onto state path blocks"         "$(rc_bash 'mv new.md .geniro/state/onboard/s/state.md')"
expect_block "bash: cp onto state path blocks"         "$(rc_bash 'cp tmp.md .geniro/workflow/linear.md')"
expect_block "bash: dd of= into state path blocks"     "$(rc_bash 'dd if=/dev/stdin of=.geniro/knowledge/learnings.jsonl')"

# ===== Bash branch: sanctioned helpers, reads, exemptions, non-state writes allow =====
expect_allow "bash: atomic_state_write invocation allowed" "$(rc_bash 'atomic_state_write .geniro/state/review/s/state.md < body.txt')"
expect_allow "bash: atomic_state_append invocation allowed" "$(rc_bash 'atomic_state_append .geniro/knowledge/learnings.jsonl < line.json')"
expect_allow "bash: redirect into .geniro/state/tdd/ allowed" "$(rc_bash 'echo RED > .geniro/state/tdd/state-myslug.md')"
expect_allow "bash: reading a state file allowed"      "$(rc_bash 'cat .geniro/state/review/s/state.md')"
expect_allow "bash: grep in a state file allowed"      "$(rc_bash 'grep phase .geniro/planning/td/state.md')"
expect_allow "bash: cp FROM a state file allowed"      "$(rc_bash 'cp .geniro/state/review/s/state.md /tmp/inspect.md')"
expect_allow "bash: redirect to non-state file allowed" "$(rc_bash 'echo x > /tmp/out.txt')"
expect_allow "bash: stderr to /dev/null allowed"       "$(rc_bash 'npm test 2>/dev/null')"
expect_allow "bash: plain git command allowed"         "$(rc_bash 'git status')"
expect_allow "bash: rm of a state file is not a write candidate" "$(rc_bash 'rm -f .geniro/state/review/s/state.md')"

# ===== Bash branch: same-tier cp/mv housekeeping (source under .geniro/) allowed =====
# /geniro:actions version-it: rename existing action to <name>-v1.md.
expect_allow "bash: mv rename within .geniro/actions/ allowed" "$(rc_bash 'mv .geniro/actions/foo.md .geniro/actions/foo-v1.md')"
# /geniro:actions pre-edit snapshot: cp to a sibling .pre-edit.bak.
expect_allow "bash: cp to pre-edit snapshot within .geniro/ allowed" "$(rc_bash 'cp .geniro/actions/foo.md .geniro/actions/foo.md.pre-edit.bak')"
# /geniro:actions revert: mv the backup back over the original.
expect_allow "bash: mv backup back within .geniro/ allowed" "$(rc_bash 'mv .geniro/actions/foo.md.pre-edit.bak .geniro/actions/foo.md')"

# A cp/mv whose SOURCE is OUTSIDE .geniro/ is a content write around the helper — still blocks.
expect_block "bash: mv from outside .geniro/ into state path blocks" "$(rc_bash 'mv /tmp/staged.md .geniro/state/review/s/state.md')"
expect_block "bash: cp from outside .geniro/ into actions blocks"    "$(rc_bash 'cp /tmp/x .geniro/actions/foo.md')"

# Bash branch canonical-layout hint on non-canonical state/ redirect.
out=$(run_bash 'echo x > .geniro/state/integration-flakes.md')
if printf '%s' "$out" | grep -q 'matches no canonical layout'; then
  pass "bash: non-canonical state/ redirect gets the layout hint"
else
  fail "bash: non-canonical state/ redirect gets the layout hint"
fi

# ===== safety.json bypass — both branches =====
mkdir -p "$TMPDIR_BASE/byp/.geniro"
echo '{"allow_patterns":["enforce-state-helper"]}' > "$TMPDIR_BASE/byp/.geniro/safety.json"
cd "$TMPDIR_BASE/byp" || exit 1
expect_allow "bypass: Edit/Write to state path allowed" "$(rc_path '/proj/.geniro/state/review/slug/state.md')"
expect_allow "bypass: Bash redirect into state path allowed" "$(rc_bash 'echo x > .geniro/state/review/s/state.md')"
cd "$TMPDIR_BASE" || exit 1

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
