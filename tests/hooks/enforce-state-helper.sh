#!/usr/bin/env bash
# Smoke test for hooks/enforce-state-helper.sh (PreToolUse Edit|Write|MultiEdit|NotebookEdit, block-mode).
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
#   - enforce-state-helper bypass via safety.json.

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

# ===== Block-message reframing pins (2026-08-11 incident): a real run treated
# this hook's block as a hard denial of the FILE, reported it as such to the
# user three times, and shipped a PR calling the gap unfixable by an agent —
# even though .geniro/actions/ was writable the whole time via
# atomic_state_write, which that same run had already used nine times that
# session. The message was reworded to prevent that misreading. These pin the
# load-bearing PROPERTIES of the wording, not its exact prose — a future
# reword should still satisfy every anchor below, and an editor who can't
# should stop and reconsider before deleting the assertion.
# .geniro/actions/ is used deliberately: it's the path from the incident and a
# non-obvious member of the protected-prefix list (easy to forget alongside
# state/planning/knowledge).
out=$(run_path '/proj/.geniro/actions/check-crawler-errors.md')

# Pin 1: the required route is NAMED and the invocation is SHOWN, not just
# implied. Losing this reintroduces the "blocked with no way forward" reading
# that made the run treat the file as unwritable.
if printf '%s' "$out" | grep -q 'atomic_state_write'; then
  pass "actions/ block names the required helper (atomic_state_write)"
else
  fail "actions/ block names the required helper (atomic_state_write)"
fi
if printf '%s' "$out" | grep -qF "atomic_state_write \"/proj/.geniro/actions/check-crawler-errors.md\" <<'EOF'"; then
  pass "actions/ block shows the concrete invocation pattern"
else
  fail "actions/ block shows the concrete invocation pattern"
fi

# Pin 2: the path is explicitly stated to be WRITABLE. This is the exact claim
# missing from the old wording ("Direct write to canonical state path") that
# let a run read the block as "this file can't be written" instead of "this
# ROUTE can't be used". Losing the word is losing the fix.
if printf '%s' "$out" | grep -q 'writable'; then
  pass "actions/ block states the path is writable"
else
  fail "actions/ block states the path is writable"
fi

# Pin 3: the run is told this is routing guidance, not a denial — anchored on
# "not a denial" rather than the full sentence, so a reword of the surrounding
# prose doesn't false-fail this. This is the line that should have stopped the
# incident run from reporting the file as blocked and offering a manual patch.
if printf '%s' "$out" | grep -q 'not a denial'; then
  pass "actions/ block frames itself as routing guidance, not a denial"
else
  fail "actions/ block frames itself as routing guidance, not a denial"
fi

# Pin 4: the safety.json bypass is still present (it's a legitimate, if rare,
# escape hatch) but demoted — labeled "rare" rather than offered as the
# obvious next step. Losing "rare" here is how the bypass drifts back into
# looking like the sanctioned way out instead of the routing helper.
if printf '%s' "$out" | grep -q 'Project bypass (rare'; then
  pass "actions/ block marks the safety.json bypass as a rare escape hatch"
else
  fail "actions/ block marks the safety.json bypass as a rare escape hatch"
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

# T1 scratch is recognised by SHAPE (dot-prefixed basename), not by a roster of
# known filenames. The roster version blocked `.review-round1.md` six times in
# one run — a name no list anticipated, with nothing in the deny text to reveal
# what the list contained.
expect_allow "named T1 output is excluded"          "$(rc_path '/proj/.geniro/planning/task/.kr-out.md')"
expect_allow "unlisted dot-prefixed scratch is excluded" "$(rc_path '/proj/.geniro/planning/task/.review-round1.md')"
expect_allow "dot-prefixed scratch under state/ is excluded" "$(rc_path '/proj/.geniro/state/review/slug/.round2-notes.md')"
# ...and the shape must not swallow a durable file. Every canonical state file
# is undotted, so the two rules cannot collide — except .geniro-state.json,
# which is both dot-prefixed and guarded, and is therefore decided first.
expect_block "durable state.md still blocks"        "$(rc_path '/proj/.geniro/planning/task/state.md')"
expect_block ".geniro-state.json is guarded despite its leading dot" \
  "$(rc_path '/proj/.geniro/.geniro-state.json')"

# ===== safety.json bypass =====
mkdir -p "$TMPDIR_BASE/byp/.geniro"
echo '{"allow_patterns":["enforce-state-helper"]}' > "$TMPDIR_BASE/byp/.geniro/safety.json"
cd "$TMPDIR_BASE/byp" || exit 1
expect_allow "bypass: Edit/Write to state path allowed" "$(rc_path '/proj/.geniro/state/review/slug/state.md')"
cd "$TMPDIR_BASE" || exit 1

# ===== T1 #8 (2026-08-07 audit): .geniro/safety.json itself — the file that
# disables every guard by pattern ID — is outside every guarded prefix in
# matches_state_path, so an agent could self-grant any bypass in one Write. =====
expect_block "Edit/Write to .geniro/safety.json blocks" "$(rc_path '/proj/.geniro/safety.json')"
# The DEDICATED "safety-json-edit" ID unlocks it WITHOUT
# needing the broad "enforce-state-helper" grant — a narrower, independently
# documented route rather than riding on the all-guards bypass.
mkdir -p "$TMPDIR_BASE/byp-sj/.geniro"
echo '{"allow_patterns":["safety-json-edit"]}' > "$TMPDIR_BASE/byp-sj/.geniro/safety.json"
cd "$TMPDIR_BASE/byp-sj" || exit 1
expect_allow "safety.json: safety-json-edit bypass allows Edit/Write to safety.json" \
  "$(rc_path '/proj/.geniro/safety.json')"
# The dedicated bypass is scoped to safety.json only — an ordinary state path
# still blocks under it.
expect_block "safety.json: safety-json-edit bypass does NOT also unlock ordinary state paths" \
  "$(rc_path '/proj/.geniro/state/review/slug/state.md')"
cd "$TMPDIR_BASE" || exit 1

# ===== NotebookEdit branch: notebook_path is read like file_path =====
rc_notebook() {
  jq -nc --arg p "$1" '{tool_name: "NotebookEdit", tool_input: {notebook_path: $p, new_source: "x = 1"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "NotebookEdit into a state path blocks" \
  "$(rc_notebook '/proj/.geniro/planning/task/state.md')"
expect_allow "NotebookEdit into a normal notebook allowed" \
  "$(rc_notebook '/proj/notebooks/analysis.ipynb')"

# ===== jq PRESENT but payload MALFORMED: must still fail-closed on a raw scan =====
# A truncated payload makes tool_name AND file_path parse empty, so the
# Edit/Write branch never fires — this is the input class
# the coarse raw-text fallback exists for (mirrors file-protection.sh,
# block-dangerous-git.sh, block-geniro-deletion.sh's identical fallback).
run_raw() {  # <raw-payload-text>
  printf '%s' "$1" | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "malformed payload naming a canonical state path still blocked" \
  "$(run_raw '{"tool_name":"Write","tool_input":{"file_path":".geniro/state/foo/state.md"')"
expect_allow "malformed payload with no canonical state path allows" \
  "$(run_raw '{"tool_name":"Write","tool_input":{"file_path":"/tmp/out.txt"')"
# `command` is deliberately NOT among the fields the raw scan reads: this guard
# no longer matches Bash, and a state path inside a shell string is as often
# prose as it is a write target.
expect_allow "malformed Bash payload naming a state path is not this guard's business" \
  "$(run_raw '{"tool_name":"Bash","tool_input":{"command":"mv /tmp/x .geniro/state/foo/state.md"')"

# ===== T1 #9 (2026-08-07 audit): jq ABSENT — the coarse raw-text fallback
# scan is pure grep+sed and needs no jq, but it used to sit BELOW the
# jq-missing fail-open branch, so it never ran when jq was absent at all
# (only when jq was present but the payload was malformed, tested above).
# FAKEBIN holds symlinks to every tool the fallback needs except jq. =====
FAKEBIN="$TMPDIR_BASE/nojq-bin"
mkdir -p "$FAKEBIN"
for _t in cat grep sed awk tr head printf env bash sh; do
  _s="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_s" "$FAKEBIN/$_t"
done
run_path_nojq() {  # <path>
  printf '{"tool_input":{"file_path":"%s","content":"x"}}' "$1" | PATH="$FAKEBIN" bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "jqless: write to a canonical state path still blocked" \
  "$(run_path_nojq '.geniro/planning/task/state.md')"
# Outside the coarse text scan the guard fails OPEN — jq is what the full
# candidate-extraction pipeline needs, and the allowlist itself needs jq too.
expect_allow "jqless: non-state write fails open" \
  "$(run_path_nojq '/tmp/out.txt')"

# ===== T0 #1/#2 (2026-08-09 audit): a `/./` segment defeats BOTH the
# safety-json-edit gate and the general state-path gate — nothing in the
# guard collapsed a `.` path segment before matching. A single-tool `Write`
# to `.geniro/./safety.json` was a self-grant of every bypass pattern ID in
# one call. =====
expect_block "safety.json: /./ segment still blocks (Write)" \
  "$(rc_path '/proj/.geniro/./safety.json')"
expect_block "state path: /./ segment still blocks (Write)" \
  "$(rc_path '/proj/.geniro/./planning/t/state.md')"
expect_block "state path: repeated-slash + /./ comb still blocks" \
  "$(rc_path '/proj/.geniro//./planning/t//state.md')"

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
