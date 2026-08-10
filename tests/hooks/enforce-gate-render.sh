#!/usr/bin/env bash
# Smoke test for hooks/enforce-gate-render.sh (PreToolUse AskUserQuestion, hard-block).
#
# Run: bash tests/hooks/enforce-gate-render.sh
#
# Coverage:
#   - Question without "above" → allow (no transcript needed).
#   - "abovementioned" does not match the word-bounded regex → allow.
#   - "ABOVE" uppercase still gates (case-insensitive) → block.
#   - "above" only in the second question of a two-question call → block.
#   - "above" question + assistant text render in the turn → allow.
#   - Finding-ID + finding co-text (no "above") on a render-less turn → block.
#   - Benign F5/M2 tokens with no co-text on a render-less turn → allow unscanned.
#   - Finding-ID + parenthesized-severity co-text (only trigger) → block.
#   - Finding-ID + a lowercase word merely starting with a severity token in
#     parens ("(lower bound)", "(low priority)") is NOT co-text → allow
#     unscanned; a real uppercase parenthesized severity (D1 (LOW), F3 (HIGH))
#     still blocks, and a bare finding-ID with no co-text still does not.
#   - PRODUCT-DECISION shorthand (no "above") on a render-less turn → block.
#   - Same finding-bearing question WITH an assistant render → allow.
#   - D-id (deferred-entry schema) + parenthesized severity, render-less → block;
#     same question WITH a render → allow.
#   - Include-deferred/minor-findings gate template wording ("below the fix
#     threshold"), render-less → block; same question WITH a render → allow.
#   - Non-English question carrying severity shorthand + a digit count (the
#     scrub-leak shape), render-less → block; same question WITH a render →
#     allow.
#   - review-handoff-post.md §7.2 granularity-gate wording ("including LOW /
#     deferred awareness items") stays unscanned on a render-less turn — the
#     bare-severity-word false-positive branch (d) is guarded against.
#   - Branch (d) is word-bounded and case-sensitive: a digit near an ordinary
#     word that merely CONTAINS a severity substring ("follow", "Allow",
#     "below", "highlight"/"slowest") does not trigger it → allow unscanned.
#   - Lean workspace/depth question (no shorthand, no "above") → allow unscanned.
#   - Assistant string-shaped content with text counts as a render → allow.
#   - "above" question + tool_use-only assistant record → block.
#   - Render earlier in the turn with tool traffic after it → allow.
#   - Whitespace-only assistant text block is not a render → block.
#   - Whitespace-only array-shaped user text is not a turn boundary → allow.
#   - <task-notification> (background agent at rest) skipped, earlier render found → allow.
#   - <task-notification> present but no render in the turn → still block (no blanket-allow).
#   - "above" in an option description (not the question text) still gates.
#   - Array-shaped user text (content blocks) counts as start of turn.
#   - Fail-open: missing transcript_path / nonexistent file / garbage-only JSONL.
#   - Fail-open: >2000 records with no decisive one (scan cap) → allow.
#   - Garbage lines interleaved do not break a legit block decision.
#   - Block stderr is byte-exact against the recovery directive.
#   - Non-AskUserQuestion input (defensive) → allow.
#   - safety.json gate-render bypass.
#   - Batched ≥2 product-decision findings in one call → block regardless of render.
#   - One product-decision + one benign question (render present) → allow (not a batch).
#   - /plan-style clarifying batch (≥2 questions, no finding shorthand) → allow unscanned.
#
# Each block case costs ~0.4s (the hook's lazy-flush retry sleep) — expected.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/enforce-gate-render.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }
expect_block() { if [ "$2" = "2" ]; then pass "$1"; else fail "$1 (expected exit=2, got exit=$2)"; fi; }
expect_allow() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1 (expected exit=0, got exit=$2)"; fi; }

cd "$TMPDIR_BASE" || exit 1

# run_q <question-text> [transcript-path]
run_q() {
  if [ -n "${2:-}" ]; then
    jq -nc --arg q "$1" --arg t "$2" \
      '{tool_name:"AskUserQuestion", transcript_path:$t,
        tool_input:{questions:[{question:$q, options:[{label:"Approve"},{label:"Cancel"}]}]}}' \
      | bash "$HOOK" >/dev/null 2>&1
  else
    jq -nc --arg q "$1" \
      '{tool_name:"AskUserQuestion",
        tool_input:{questions:[{question:$q, options:[{label:"Approve"},{label:"Cancel"}]}]}}' \
      | bash "$HOOK" >/dev/null 2>&1
  fi
  echo $?
}

TR="$TMPDIR_BASE/transcript.jsonl"

user_text()       { jq -nc '{type:"user", message:{content:"please run the review"}}'; }
user_text_arr()   { jq -nc '{type:"user", message:{content:[{type:"text", text:"please review the finding"}]}}'; }
user_ws_arr()     { jq -nc '{type:"user", message:{content:[{type:"text", text:"   \n\t  "}]}}'; }
user_toolresult() { jq -nc '{type:"user", message:{content:[{type:"tool_result", tool_use_id:"t1", content:"ok"}]}}'; }
# Harness-injected background-agent/workflow completion notice — string and
# array-text shapes both seen in real transcripts. Mid-turn feedback, not a
# turn boundary: the scan must skip it like a tool_result.
user_tasknotif()     { jq -nc '{type:"user", message:{role:"user", content:"<task-notification>\n<task-id>wkx5n4j0d</task-id>\n<status>completed</status>\n<summary>Reflection pass on PR #3119 findings completed</summary>"}}'; }
user_tasknotif_arr() { jq -nc '{type:"user", message:{role:"user", content:[{type:"text", text:"<task-notification>\n<status>completed</status>"}]}}'; }
asst_text()       { jq -nc --arg t "$1" '{type:"assistant", message:{content:[{type:"text", text:$t}]}}'; }
asst_string()     { jq -nc --arg t "$1" '{type:"assistant", message:{content:$t}}'; }
asst_tooluse()    { jq -nc '{type:"assistant", message:{content:[{type:"tool_use", name:"Bash", input:{}}]}}'; }

# ===== No "above" token → allow without any transcript =====
expect_allow "question without 'above' → allow" "$(run_q 'Approve the spec?')"

# ===== Word boundary: "abovementioned" must not match even on a render-less turn =====
{ user_text; asst_tooluse; } > "$TR"
expect_allow "'abovementioned' does not match word-bounded regex → allow" "$(run_q 'Apply the abovementioned plan?' "$TR")"

# ===== Case-insensitivity: "ABOVE" gates on a render-less turn =====
{ user_text; asst_tooluse; } > "$TR"
expect_block "'ABOVE' uppercase on a render-less turn → block" "$(run_q 'Full explanation ABOVE. Approve?' "$TR")"

# ===== Render present: [user text] → [assistant text] =====
{ user_text; asst_text 'Here is the finding digest with evidence and visuals.'; } > "$TR"
expect_allow "'above' question with render in turn → allow" "$(run_q 'Full explanation above. Approve?' "$TR")"

# ===== Finding-gate shorthand (no "above"): the PR-2091 blind-gate pattern =====
# A real /review open-decision gate carried finding IDs + convergence wording but
# never said "above". The (a)-only guard let it slip; branch (b) now catches it.

# Finding-ID + finding-gate co-text on a render-less turn → block.
# This question carries the finding-ID tokens (F5/F6) AND the co-text words
# "Findings" + "converged", so it satisfies the compound finding-ID branch (and
# the convergence shorthand branch independently).
{ user_text; asst_tooluse; } > "$TR"
expect_block "finding-ID + co-text (F5, 'Findings', converged) on a render-less turn → block" \
  "$(run_q 'Findings F5 and F6 (converged x3): how should I handle them?' "$TR")"

# Benign F/M tokens with NO finding-gate co-text → allow unscanned (the W1 fix).
# A bare F5/M2 token collides with load-balancer models, version tags, etc. The
# finding-ID branch now requires co-text, so these no longer block. They would
# have blocked before the fix (render-less transcript, finding-ID token present).
{ user_text; asst_tooluse; } > "$TR"
expect_allow "benign 'F5 load balancer' token, no co-text → allow unscanned" \
  "$(run_q 'Deploy to: F5 load balancer or direct?' "$TR")"
{ user_text; asst_tooluse; } > "$TR"
expect_allow "benign 'version M2' token, no co-text → allow unscanned" \
  "$(run_q 'Bump to version M2 of the schema?' "$TR")"

# Finding-ID + parenthesized-severity co-text, with NO "above"/PRODUCT-DECISION/
# converge → block. Proves the new co-text branch still catches a real
# open-decision gate that can ONLY be matched by finding-ID + co-text.
{ user_text; asst_tooluse; } > "$TR"
expect_block "finding-ID + parenthesized severity '(MEDIUM, ...)' (only trigger) → block" \
  "$(run_q 'F5 (MEDIUM, security): create/update accept any file UUID — fix now or defer?' "$TR")"

# PRODUCT-DECISION shorthand on a render-less turn → block.
{ user_text; asst_tooluse; } > "$TR"
expect_block "PRODUCT-DECISION shorthand on a render-less turn → block" \
  "$(run_q 'This is a PRODUCT-DECISION: pick a resolution.' "$TR")"

# Same finding-bearing question WITH a render → allow (properly-rendered gate).
{ user_text; asst_text 'Finding digest: F5 is X because Y; F6 converged across 3 reviewers.'; } > "$TR"
expect_allow "finding-ID shorthand (F5) with render in turn → allow" \
  "$(run_q 'Findings F5 and F6 (converged x3): how should I handle them?' "$TR")"

# ===== Lean workspace/depth question (zero-false-positive guard) =====
# No "above", no finding-ID, no PRODUCT-DECISION, no convergence wording, and the
# severity word "Deep"/options carry no trigger token → must exit 0 unscanned,
# regardless of transcript state (here: render-less, which would block if scanned).
run_lean() {
  jq -nc --arg t "$1" \
    '{tool_name:"AskUserQuestion", transcript_path:$t,
      tool_input:{questions:[{question:"Where should the review run?",
        options:[{label:"Create review worktree"},{label:"Review in current location"}]}]}}' \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
run_depth() {
  jq -nc --arg t "$1" \
    '{tool_name:"AskUserQuestion", transcript_path:$t,
      tool_input:{questions:[{question:"How deep should the review go?",
        options:[{label:"Standard"},{label:"Deep - 3x passes + 3-vote verify"}]}]}}' \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
{ user_text; asst_tooluse; } > "$TR"
expect_allow "lean workspace question (no shorthand, no 'above') → allow unscanned" "$(run_lean "$TR")"
expect_allow "lean review-depth question (severity word 'Deep' not a trigger) → allow unscanned" "$(run_depth "$TR")"

# ===== Assistant string-shaped content with text is a render =====
{ user_text; asst_string 'Here is the digest rendered as plain string content.'; } > "$TR"
expect_allow "assistant string-shaped content with text → allow" "$(run_q 'Full explanation above. Approve?' "$TR")"

# ===== No render: [user text] → [assistant tool_use-only] =====
{ user_text; asst_tooluse; } > "$TR"
expect_block "'above' question with tool_use-only turn → block" "$(run_q 'Full explanation above. Approve?' "$TR")"

# ===== Render earlier in turn, tool traffic after it =====
{ user_text; asst_text 'Digest: the finding is X because Y.'; asst_tooluse; user_toolresult; } > "$TR"
expect_allow "render earlier in turn, tool calls after → allow" "$(run_q 'Details in the message above.' "$TR")"

# ===== Whitespace-only assistant text block is not a render =====
{ user_text; asst_text $'   \n\t  '; } > "$TR"
expect_block "whitespace-only assistant text is not a render → block" "$(run_q 'Approve the plan above?' "$TR")"

# ===== Whitespace-only array-shaped user text is not a turn boundary =====
# Reverse scan must skip past it and reach the earlier render.
{ user_text; asst_text 'Digest: finding X, evidence Y.'; user_ws_arr; asst_tooluse; } > "$TR"
expect_allow "whitespace-only array user text skipped, render found → allow" "$(run_q 'Approve the plan above?' "$TR")"

# ===== Background-agent completion notification is NOT a turn boundary =====
# A <task-notification> (a backgrounded agent/workflow coming to rest) is
# harness-injected mid-flow feedback; the assistant resumes the SAME logical
# turn after it. The reverse scan must skip it like a tool_result and keep
# looking for the render — so a gate fired right after a background agent is not
# falsely blocked when the render exists. This is the PR #3119 race.
{ user_text; asst_text 'Review complete: F1 is X; F6 converged across reviewers — full table here.'; user_tasknotif; asst_tooluse; } > "$TR"
expect_allow "task-notification (string) skipped, earlier render found → allow" \
  "$(run_q 'Findings F1 and F6 (converged x3): how should I proceed?' "$TR")"
{ user_text; asst_text 'Review complete: F1 is X; F6 converged across reviewers — full table here.'; user_tasknotif_arr; asst_tooluse; } > "$TR"
expect_allow "task-notification (array text) skipped, earlier render found → allow" \
  "$(run_q 'Findings F1 and F6 (converged x3): how should I proceed?' "$TR")"
# But the skip does NOT blanket-allow: with no render anywhere in the turn the
# scan reaches the real user-text start and still blocks.
{ user_text; asst_tooluse; user_tasknotif; asst_tooluse; } > "$TR"
expect_block "task-notification present but no render in turn → still blocks" \
  "$(run_q 'Findings F1 and F6 (converged x3): how should I proceed?' "$TR")"

# ===== "above" only in an option description still gates; array-shaped user text =====
run_desc() {
  jq -nc --arg t "$1" \
    '{tool_name:"AskUserQuestion", transcript_path:$t,
      tool_input:{questions:[{question:"Proceed?", options:[{label:"Yes", description:"Details in the message above."},{label:"No"}]}]}}' \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
{ user_text_arr; asst_tooluse; } > "$TR"
expect_block "'above' in option description + array user text → block" "$(run_desc "$TR")"

# ===== "above" only in the SECOND question of a two-question call still gates =====
run_q2() {
  jq -nc --arg t "$1" \
    '{tool_name:"AskUserQuestion", transcript_path:$t,
      tool_input:{questions:[
        {question:"Pick a branch name?", options:[{label:"A"},{label:"B"}]},
        {question:"Approve the plan above?", options:[{label:"Approve"},{label:"Cancel"}]}]}}' \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
{ user_text; asst_tooluse; } > "$TR"
expect_block "'above' only in the second question → block" "$(run_q2 "$TR")"

# ===== Fail-open cases =====
expect_allow "transcript_path missing from stdin → allow" "$(run_q 'Full explanation above. Approve?')"
expect_allow "transcript file nonexistent → allow" "$(run_q 'Full explanation above. Approve?' "$TMPDIR_BASE/no-such.jsonl")"

# >2000 records, none decisive within the cap: the only decisive record (user
# text) sits beyond 2100 skippable tool_result records in reverse order → the
# scan hits the cap with no decision → fail open.
BIG="$TMPDIR_BASE/big.jsonl"
user_text > "$BIG"
SKIP_REC=$(user_toolresult)
for _ in $(seq 1 2100); do printf '%s\n' "$SKIP_REC"; done >> "$BIG"
expect_allow ">2000-record transcript with no decisive record in cap → fail-open allow" "$(run_q 'Full explanation above. Approve?' "$BIG")"

# GENIRO_GATE_RENDER_SCAN_LIMIT raises the cap so the SAME fixture's decisive
# record (now within reach) is actually found → the gate blocks instead of
# failing open. Proves the override reaches the jq scan, not just the shell var.
run_q_limit() {  # <question> <transcript> <limit>
  jq -nc --arg q "$1" --arg t "$2" \
    '{tool_name:"AskUserQuestion", transcript_path:$t,
      tool_input:{questions:[{question:$q, options:[{label:"Approve"},{label:"Cancel"}]}]}}' \
    | GENIRO_GATE_RENDER_SCAN_LIMIT="$3" bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "GENIRO_GATE_RENDER_SCAN_LIMIT=3000 reaches the same fixture's decisive record → block" \
  "$(run_q_limit 'Full explanation above. Approve?' "$BIG" 3000)"
# A non-numeric override must fall back to the 2000 default (sanitized), not
# error out of the jq call or disable the cap outright.
expect_allow "GENIRO_GATE_RENDER_SCAN_LIMIT=notanumber sanitizes to the 2000 default" \
  "$(run_q_limit 'Full explanation above. Approve?' "$BIG" notanumber)"

# Garbage lines interleaved must not break the stream (fromjson? resilience):
# this fixture still has a real user-text start-of-turn and no render → block.
{ user_text; echo 'not json {{{'; asst_tooluse; } > "$TR"
expect_block "garbage line interleaved in a blocking fixture → still blocks" "$(run_q 'Approve the spec summarized above?' "$TR")"

# Only-garbage transcript → no decision → fail open.
{ echo 'garbage1'; echo '%%%'; } > "$TR"
expect_allow "garbage-only transcript → fail-open allow" "$(run_q 'Full explanation above. Approve?' "$TR")"

# ===== Block stderr is byte-exact against the recovery directive =====
{ user_text; asst_tooluse; } > "$TR"
ERR_ACTUAL="$TMPDIR_BASE/stderr-actual.txt"
ERR_EXPECTED="$TMPDIR_BASE/stderr-expected.txt"
jq -nc --arg t "$TR" \
  '{tool_name:"AskUserQuestion", transcript_path:$t,
    tool_input:{questions:[{question:"Full explanation above. Approve?", options:[{label:"Approve"}]}]}}' \
  | bash "$HOOK" 2>"$ERR_ACTUAL" >/dev/null || true
cat > "$ERR_EXPECTED" <<'EOF'
Gate render missing: this gate question needs a rendered chat block the user can see, but no visible assistant message exists in the current turn — the user would be answering blind.
This is an automated plugin guard (gate-render), NOT a user denial. Do not stop, and do not treat the question as answered.
Recovery: (1) write the full gate render as an ordinary chat message — the digest, evidence, and visuals the question refers to; (2) then call AskUserQuestion again with the same options.
Project bypass: add "gate-render" to allow_patterns in .geniro/safety.json.
EOF
if cmp -s "$ERR_EXPECTED" "$ERR_ACTUAL"; then
  pass "block stderr is byte-exact against the recovery directive"
else
  fail "block stderr is byte-exact against the recovery directive (diff: $(diff "$ERR_EXPECTED" "$ERR_ACTUAL" 2>&1 | head -8))"
fi

# ===== Non-AskUserQuestion input (defensive) → allow =====
expect_allow "non-AskUserQuestion tool input → allow" \
  "$(jq -nc '{tool_name:"Edit", tool_input:{file_path:"x", new_string:"above"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"

# ===== safety.json gate-render bypass =====
mkdir -p "$TMPDIR_BASE/byp/.geniro"
echo '{"allow_patterns":["gate-render"]}' > "$TMPDIR_BASE/byp/.geniro/safety.json"
cd "$TMPDIR_BASE/byp" || exit 1
{ user_text; asst_tooluse; } > "$TR"
expect_allow "gate-render bypass on a blocking fixture → allow" "$(run_q 'Full explanation above. Approve?' "$TR")"
cd "$TMPDIR_BASE" || exit 1

# ===== Finding-batching guard: ≥2 product-decision questions in one call → block =====
# Two PRODUCT-DECISION questions batched into one call is the tabbed F3/F4/F5
# prompt — blocked regardless of render state (shape violation, not render).
run_batch_pd() {
  jq -nc '{tool_name:"AskUserQuestion",
    tool_input:{questions:[
      {question:"F3 is a PRODUCT-DECISION: docstring over-promise — how to resolve?", options:[{label:"Reword"},{label:"Leave as-is"}]},
      {question:"F4 is a PRODUCT-DECISION: config split — how to resolve?", options:[{label:"Inline"},{label:"Keep split"}]}]}}' \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "two PRODUCT-DECISION questions batched in one call → block" "$(run_batch_pd)"

# Three finding-ID + co-text questions batched (the screenshot's exact shape) → block.
run_batch_fid() {
  jq -nc '{tool_name:"AskUserQuestion",
    tool_input:{questions:[
      {question:"F3 (LOW, architecture): over-promise in the docstring — your call?", options:[{label:"Reword"},{label:"Refactor"}]},
      {question:"F4 (LOW, architecture): provider mcpUrl split across two files — your call?", options:[{label:"Inline"},{label:"Keep"}]},
      {question:"F5 (LOW, architecture): PR thread still open — confirm intent?", options:[{label:"Confirm"},{label:"Reopen"}]}]}}' \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "three finding-ID+co-text questions batched (F3/F4/F5) → block" "$(run_batch_fid)"

# A render present does NOT rescue a batched product-decision call — shape wins.
{ user_text; asst_text 'Digest: F3 over-promise; F4 config split — full evidence here.'; } > "$TR"
run_batch_pd_tr() {
  jq -nc --arg t "$1" '{tool_name:"AskUserQuestion", transcript_path:$t,
    tool_input:{questions:[
      {question:"F3 is a PRODUCT-DECISION: docstring over-promise — how to resolve?", options:[{label:"Reword"},{label:"Leave as-is"}]},
      {question:"F4 is a PRODUCT-DECISION: config split — how to resolve?", options:[{label:"Inline"},{label:"Keep split"}]}]}}' \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "batched product-decisions block even WITH a render present → block" "$(run_batch_pd_tr "$TR")"

# Two-question call where only ONE carries product-decision shorthand → batching
# guard does not fire; with a render present the existing logic allows.
{ user_text; asst_text 'Digest: F3 over-promise — evidence and visual here.'; } > "$TR"
run_one_pd_one_benign() {
  jq -nc --arg t "$1" '{tool_name:"AskUserQuestion", transcript_path:$t,
    tool_input:{questions:[
      {question:"F3 is a PRODUCT-DECISION: docstring over-promise — how to resolve?", options:[{label:"Reword"},{label:"Leave as-is"}]},
      {question:"Pick a branch name for the follow-up?", options:[{label:"A"},{label:"B"}]}]}}' \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_allow "one product-decision + one benign question, render present → allow (not a batch)" "$(run_one_pd_one_benign "$TR")"

# /plan-style clarifying batch: ≥2 questions, NO product-decision shorthand →
# allow unscanned even on a render-less turn (the false-positive guard).
{ user_text; asst_tooluse; } > "$TR"
run_plan_clarify() {
  jq -nc --arg t "$1" '{tool_name:"AskUserQuestion", transcript_path:$t,
    tool_input:{questions:[
      {question:"Which database should the feature use?", options:[{label:"Postgres"},{label:"SQLite"}]},
      {question:"Should the endpoint be paginated?", options:[{label:"Yes"},{label:"No"}]}]}}' \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_allow "plan-style clarifying batch (no finding shorthand) → allow unscanned" "$(run_plan_clarify "$TR")"

# ===== Include-deferred / minor-findings gate template wording (branch c) =====
# review-handoff.md §4.6 and implement-reference.md's Phase 3 minor-findings
# gate both emit "below the fix threshold" in their question. Neither "above"
# nor PRODUCT-DECISION/convergence nor a finding-ID appears, so pre-fix this
# question matched no branch and exited 0 unscanned regardless of render state.
{ user_text; asst_tooluse; } > "$TR"
expect_block "include-deferred gate template wording, render-less → block" \
  "$(run_q 'The review also set aside 10 minor findings below the fix threshold. Include them in the fix list for /geniro:implement?' "$TR")"

{ user_text; asst_text 'Minor findings set aside: short titles, file:lines, and why each was left out.'; } > "$TR"
expect_allow "include-deferred gate template wording WITH render → allow" \
  "$(run_q 'The review also set aside 10 minor findings below the fix threshold. Include them in the fix list for /geniro:implement?' "$TR")"

# ===== D-id (deferred-entry schema) + parenthesized severity (branch b, extended) =====
# FINDING_ID_RE now accepts D alongside F/M — the deferred-entry schema's D1/D2
# ids. Paired with the existing parenthesized-severity co-text, this is the
# scrub's own named-forbidden example ("D1 (LOW)") and is language-invariant:
# neither the id nor the parenthesized severity requires an English word.
{ user_text; asst_tooluse; } > "$TR"
expect_block "D-id + parenthesized severity (scrub's 'D1 (LOW)' shape), render-less → block" \
  "$(run_q 'D1 (LOW): a minor improvement below the fix bar — include it?' "$TR")"

{ user_text; asst_text 'Deferred entry: D1 is a minor improvement, left out because it is below the fix bar.'; } > "$TR"
expect_allow "D-id + parenthesized severity WITH render → allow" \
  "$(run_q 'D1 (LOW): a minor improvement below the fix bar — include it?' "$TR")"

# ===== Non-English question carrying severity shorthand + digit count (branch d) =====
# The observed real failure: the whole gate ran in Russian, so every English
# trigger (above / PRODUCT-DECISION / converg / finding / reviewer / severit)
# is absent, and the question paraphrased the template rather than using its
# literal wording, so branch (c) does not match either. Only the severity
# shorthand ("LOW") paired with the deferred-count digit is language-invariant.
{ user_text; asst_tooluse; } > "$TR"
expect_block "non-English question with severity shorthand + digit count, render-less → block" \
  "$(run_q 'Включить в список фиксов 10 отложенных LOW-находок?' "$TR")"

{ user_text; asst_text 'Findings set aside: 10 entries below the fix threshold, with short titles and locations.'; } > "$TR"
expect_allow "non-English question with severity shorthand + digit count WITH render → allow" \
  "$(run_q 'Включить в список фиксов 10 отложенных LOW-находок?' "$TR")"

# ===== False-positive guard: the §7.2 post-granularity gate must stay unscanned =====
# review-handoff-post.md §7.2's actual question carries a bare "LOW" with no
# digit nearby and no finding-ID — branch (d)'s digit-count pairing is what
# keeps this legitimate, render-independent lean question from being scanned
# (and thus falsely blocked) on a render-less turn.
{ user_text; asst_tooluse; } > "$TR"
expect_allow "§7.2 granularity-gate wording ('including LOW / deferred awareness items') → allow unscanned" \
  "$(run_q 'Send all unposted findings (including LOW / deferred awareness items) in a single batched review, or pick which ones to post?' "$TR")"

# ===== False-positive guard: branch (d) must not fire on a severity SUBSTRING
# inside an ordinary word. Regression for the unbounded/case-insensitive
# SEVERITY_COUNT_RE that matched "LOW" inside "follow"/"below"/"slowest" and
# "HIGH" inside "highlight" whenever any digit appeared nearby — which blocked
# ordinary AskUserQuestion calls carrying no severity content at all. All
# render-less (would block if branch (d) mis-fired). =====
{ user_text; asst_tooluse; } > "$TR"
expect_allow "digit + 'follow' (LOW substring, not a word) → allow" \
  "$(run_q 'I found 3 candidate configs. Should I follow the existing pattern?' "$TR")"
{ user_text; asst_tooluse; } > "$TR"
expect_allow "digit + 'Allow' (LOW substring, mixed case) → allow" \
  "$(run_q 'There are 2 migrations pending. Allow me to run them?' "$TR")"
{ user_text; asst_tooluse; } > "$TR"
expect_allow "digit + 'below' (LOW substring, lowercase) → allow" \
  "$(run_q 'Which of the 4 options below do you prefer?' "$TR")"
{ user_text; asst_tooluse; } > "$TR"
expect_allow "digit + 'highlight'/'slowest' (HIGH/LOW substrings) → allow" \
  "$(run_q 'Should I highlight the 5 slowest queries?' "$TR")"
{ user_text; asst_tooluse; } > "$TR"
expect_allow "digit with no severity word anywhere → allow" \
  "$(run_q 'Ready to commit 7 files. Proceed?' "$TR")"

# ===== False-positive guard: branch (d) must not fire on an ALL-CAPS identifier
# that merely BEGINS with a severity token. Case-sensitivity alone does not
# reject these — SCREAMING_SNAKE_CASE constants are the realistic blast radius,
# and the earlier lowercase-only cases above passed while these still blocked.
# Regression for the alternative that carried a leading word boundary but no
# trailing one. All render-less (would block if branch (d) mis-fired). =====
{ user_text; asst_tooluse; } > "$TR"
expect_allow "digit + 'LOW_WATERMARK' (severity-prefixed constant) → allow" \
  "$(run_q 'Set LOW_WATERMARK to 5 or keep the current value?' "$TR")"
{ user_text; asst_tooluse; } > "$TR"
expect_allow "digit + 'HIGH_PRIORITY_QUEUE' (severity-prefixed constant) → allow" \
  "$(run_q 'Should I bump HIGH_PRIORITY_QUEUE workers from 2 to 8?' "$TR")"
{ user_text; asst_tooluse; } > "$TR"
expect_allow "digit + 'CRITICAL_PATH' (severity-prefixed constant) → allow" \
  "$(run_q 'The CRITICAL_PATH constant is used in 4 modules — inline it?' "$TR")"
{ user_text; asst_tooluse; } > "$TR"
expect_allow "digit + 'CRITICALLY'/'HIGHLIGHT' (all-caps, severity-prefixed word) → allow" \
  "$(run_q 'CRITICALLY, 3 tests are skipped. Unskip them?' "$TR")"

# ===== False-positive guard: branch (b)'s parenthesized-severity co-text must
# not fire on an ordinary lowercase word that merely STARTS with a severity
# token in parens ("(lower bound)", "(low priority)") — even alongside a
# finding-ID-shaped token elsewhere in the text. Case-sensitivity + a trailing
# boundary (mirroring branch (d)'s SEVERITY_COUNT_RE) is what keeps this from
# being finding-gate co-text. Render-less (would block if branch (b) mis-fired). =====
{ user_text; asst_tooluse; } > "$TR"
expect_allow "F5 token + '(lower bound)' (LOW-prefixed word, not co-text) → allow unscanned" \
  "$(run_q 'The F5 config caps requests at a (lower bound) of 10 per second — increase it?' "$TR")"
{ user_text; asst_tooluse; } > "$TR"
expect_allow "F5 token + '(low priority)' (lowercase severity word, not co-text) → allow unscanned" \
  "$(run_q 'F5 queue jobs are (low priority) by default — change to high?' "$TR")"

# Same finding-ID + a REAL parenthesized severity still blocks (regression
# guard: the boundary/case fix must not regress genuine co-text).
{ user_text; asst_tooluse; } > "$TR"
expect_block "D1 (LOW) real finding co-text still blocks render-less" \
  "$(run_q 'D1 (LOW): a minor improvement — include it?' "$TR")"
{ user_text; asst_tooluse; } > "$TR"
expect_block "F3 (HIGH) real finding co-text still blocks render-less" \
  "$(run_q 'F3 (HIGH): the accept-any-UUID check — fix now or defer?' "$TR")"

# A bare finding-ID with no co-text at all still does not block (unchanged
# baseline — re-asserted here alongside the new lower/low-word cases above).
{ user_text; asst_tooluse; } > "$TR"
expect_allow "bare F7 token, no co-text at all → allow unscanned" \
  "$(run_q 'Ship to F7 or hold?' "$TR")"

# ===== Portable `sleep`: a fractional-second rejection must not fail the gate open =====
# `sleep 0.4` is a GNU/BSD extension, not POSIX. Under `set -e`, a `sleep` that
# rejects "0.4" (busybox / minimal coreutils) would abort the hook itself before
# it ever reaches the block — the exact gate this re-scan protects fails open.
# Simulate that host with a stub `sleep` ahead of PATH that errors on any
# argument containing a '.'.
FAKESLEEP_BIN="$TMPDIR_BASE/fakesleep-bin"
mkdir -p "$FAKESLEEP_BIN"
cat > "$FAKESLEEP_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *.*) echo "sleep: invalid time interval '$1'" >&2; exit 1 ;;
  *) exec /bin/sleep "$@" ;;
esac
EOF
chmod +x "$FAKESLEEP_BIN/sleep"
{ user_text; } > "$TR"
rc=$(jq -nc --arg t "$TR" \
  '{tool_name:"AskUserQuestion", transcript_path:$t,
    tool_input:{questions:[{question:"Full explanation above. Approve?", options:[{label:"Approve"},{label:"Cancel"}]}]}}' \
  | PATH="$FAKESLEEP_BIN:$PATH" bash "$HOOK" >/dev/null 2>&1; echo $?)
expect_block "fractional-sleep-rejecting host still blocks (does not fail open)" "$rc"

# ===== T4-5: jq-less fail-open — the guard cannot parse tool input or scan the
# transcript without jq, and carries no coarse fallback, so it fails open
# UNCONDITIONALLY, even on a fixture that would otherwise block. FAKEBIN holds
# symlinks to every tool the guard needs except jq (mirrors
# block-dangerous-git.sh's shape). The payload is built with printf, not jq,
# so the test harness itself does not depend on jq being on PATH for this case. =====
FAKEBIN="$TMPDIR_BASE/nojq-bin"
mkdir -p "$FAKEBIN"
for _t in cat grep sed awk tr head printf env bash sh; do
  _s="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_s" "$FAKEBIN/$_t"
done
{ user_text; asst_tooluse; } > "$TR"
run_q_nojq() {  # <transcript-path>
  printf '{"tool_name":"AskUserQuestion","transcript_path":"%s","tool_input":{"questions":[{"question":"Full explanation above. Approve?","options":[{"label":"Approve"},{"label":"Cancel"}]}]}}' "$1" \
    | PATH="$FAKEBIN" bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_allow "jqless: render-less 'above' gate fails open (no coarse fallback in this guard)" \
  "$(run_q_nojq "$TR")"

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
