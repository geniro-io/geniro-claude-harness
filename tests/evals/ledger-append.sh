#!/usr/bin/env bash
# Smoke test for evals/lib/ledger-append.sh — the cross-run eval ledger writer.
#
# Run: bash tests/evals/ledger-append.sh   (auto-discovered by tests/run-all.sh)
# Exits non-zero on any failure.
#
# Plugin-developer / eval tooling only — not shipped to user projects.
#
# Contract under test (evals pipeline plan §8, "model the record on emit-learning's
# producer contract"): ledger_append reads one JSON object on stdin and
#   1. appends one normalised record to   <repo-root>/evals/history.jsonl  (via atomic_state_append)
#   2. appends one human row to           <repo-root>/evals/HISTORY.md
# auto-injecting run_id when absent, redacting the free-text `notes`, deduping on
# run_id (a run is immutable — re-ingest is a no-op), and enforcing the 4094-byte
# atomic-append ceiling. Required fields: skill, baseline_ref, candidate_ref.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/evals/lib/ledger-append.sh"

TMPDIR_BASE="$(cd "$(mktemp -d)" && pwd -P)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Fresh sandbox repo whose root the lib resolves to (mirrors tests/memory/emit-rejection.sh).
new_sandbox() {
  local d
  d="$(mktemp -d "$TMPDIR_BASE/sandbox.XXXXXXXXXX")"
  mkdir -p "$d/.geniro"
  cd "$d" || return 1
  git init -q
  JSONL="$d/evals/history.jsonl"
  HISTMD="$d/evals/HISTORY.md"
}

jsonl_lines() { [ -f "$JSONL" ] && grep -c . "$JSONL" || echo 0; }

# A minimal but valid record builder (jq-built so quoting is safe).
record() {
  jq -nc \
    --arg skill "${1:-plan}" \
    --arg base "${2:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}" \
    --arg cand "${3:-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}" \
    '{skill:$skill, baseline_ref:$base, candidate_ref:$cand}'
}

# ===== 1. Appends a valid record as one JSONL line =====
new_sandbox
record | ledger_append
rc=$?
if [ "$rc" -eq 0 ] && [ "$(jsonl_lines)" -eq 1 ] && jq -e . "$JSONL" >/dev/null 2>&1; then
  pass "valid record → 1 well-formed JSONL line (rc=$rc)"
else
  fail "valid record append — rc=$rc lines=$(jsonl_lines)"
fi

# ===== 2. Auto-injects run_id when absent (ISO-8601 UTC + collision-resistant suffix) =====
new_sandbox
record | ledger_append >/dev/null
run_id=$(jq -r '.run_id // empty' "$JSONL")
if printf '%s' "$run_id" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z-[0-9]+$'; then
  pass "run_id auto-injected as ISO-8601 UTC + entropy suffix ($run_id)"
else
  fail "run_id not auto-injected with entropy (got: '$run_id')"
fi

# ===== 3. Preserves a caller-supplied run_id =====
new_sandbox
record | jq -c '. + {run_id:"2026-01-02T03:04:05Z"}' | ledger_append >/dev/null
if [ "$(jq -r '.run_id' "$JSONL")" = "2026-01-02T03:04:05Z" ]; then
  pass "caller-supplied run_id preserved"
else
  fail "caller run_id clobbered (got: $(jq -r '.run_id' "$JSONL"))"
fi

# ===== 4. Redacts a secret in notes AND preserves the surrounding non-secret text =====
new_sandbox
secret="sk-ant-api03-AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKKKLLLL1234"
record | jq -c --arg s "leaked $secret here" '. + {notes:$s}' | ledger_append >/dev/null
stored=$(jq -r '.notes // empty' "$JSONL" 2>/dev/null)
if [ -f "$JSONL" ] && ! grep -qF "$secret" "$JSONL" \
   && printf '%s' "$stored" | grep -q 'REDACTED' \
   && printf '%s' "$stored" | grep -q 'leaked' \
   && printf '%s' "$stored" | grep -q 'here'; then
  pass "secret redacted (REDACTED marker), surrounding notes text preserved"
else
  fail "redaction wrong — stored notes: '$stored'"
fi

# ===== 5. Dedup on run_id — re-appending the same run is a no-op =====
new_sandbox
rec=$(record | jq -c '. + {run_id:"2026-02-02T02:02:02Z"}')
printf '%s' "$rec" | ledger_append >/dev/null
printf '%s' "$rec" | ledger_append >/dev/null
if [ "$(jsonl_lines)" -eq 1 ]; then
  pass "same run_id appended twice → 1 line (idempotent)"
else
  fail "dedup failed — $(jsonl_lines) lines for one run_id"
fi

# ===== 6. Two distinct runs → two lines =====
new_sandbox
record plan | jq -c '. + {run_id:"2026-03-01T00:00:00Z"}' | ledger_append >/dev/null
record review | jq -c '. + {run_id:"2026-03-02T00:00:00Z"}' | ledger_append >/dev/null
if [ "$(jsonl_lines)" -eq 2 ]; then
  pass "two distinct runs → 2 lines"
else
  fail "expected 2 lines, got $(jsonl_lines)"
fi

# ===== 7. Appends a human row to HISTORY.md carrying skill + candidate ref =====
new_sandbox
record review aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa e4f5e4f5e4f5e4f5e4f5e4f5e4f5e4f5e4f5e4f5 \
  | ledger_append >/dev/null
if [ -f "$HISTMD" ] && grep -q '| review |' "$HISTMD" && grep -q 'e4f5e4f' "$HISTMD"; then
  pass "HISTORY.md row appended with skill + short candidate ref"
else
  fail "HISTORY.md row missing or malformed"
fi

# ===== 8. HISTORY.md header is single-sourced & created when absent =====
new_sandbox
record | ledger_append >/dev/null
if grep -q '^| Date | Skill |' "$HISTMD" && grep -q '^|---' "$HISTMD"; then
  pass "HISTORY.md table header auto-created when file absent"
else
  fail "HISTORY.md header not created"
fi

# ===== 9. Missing required field rejected (no skill) =====
new_sandbox
echo '{"baseline_ref":"a","candidate_ref":"b"}' | ledger_append >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ "$(jsonl_lines)" -eq 0 ]; then
  pass "missing required field 'skill' rejected (rc=$rc), nothing written"
else
  fail "missing-skill not rejected — rc=$rc lines=$(jsonl_lines)"
fi

# ===== 10. Oversized record rejected (atomic-append byte ceiling) =====
new_sandbox
big=$(head -c 5000 < /dev/zero | tr '\0' 'x')
record | jq -c --arg n "$big" '. + {notes:$n}' | ledger_append >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ "$(jsonl_lines)" -eq 0 ]; then
  pass "oversized record rejected (rc=$rc), nothing written"
else
  fail "oversized record not rejected — rc=$rc lines=$(jsonl_lines)"
fi

# ===== 12. A full §8-style record renders a complete HISTORY.md row =====
# Exercises the _la_history_row jq paths: primary-metric lookup, CI, tasks×trials, sig, verdict.
new_sandbox
jq -nc '{
  skill:"review",
  baseline_ref:"a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4",
  candidate_ref:"e4f5e4f5e4f5e4f5e4f5e4f5e4f5e4f5e4f5e4f5",
  run_id:"2026-06-06T10:30:00Z",
  tasks:24, trials_per_task:5,
  primary_metric:"quality_winrate_vs_baseline",
  quality_winrate_vs_baseline:0.78,
  quality_ci:[0.69,0.86],
  recall_passk:0.80,
  judge_human_kappa:0.71,
  cost_delta:-0.05, time_delta:1.4,
  significant_on_primary:true,
  comparator_verdict:"candidate better"
}' | ledger_append >/dev/null
row=$(tail -n1 "$HISTMD")
ok=1
for token in '| review |' '0.78' '[0.69,0.86]' '0.71' '24×5' '| yes |' 'candidate better'; do
  printf '%s' "$row" | grep -qF "$token" || { ok=0; echo "  missing token: $token" >&2; }
done
if [ "$ok" -eq 1 ]; then
  pass "full record → complete HISTORY.md row (winrate, CI, κ, tasks×trials, sig, verdict)"
else
  fail "full-record HISTORY.md row incomplete — row: $row"
fi

# ===== 11. Empty stdin is a no-op, not a crash =====
new_sandbox
printf '' | ledger_append >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] || [ "$(jsonl_lines)" -eq 0 ]; then
  pass "empty stdin → no record written (rc=$rc)"
else
  fail "empty stdin wrote a record"
fi

# ===== 13. A durable-append failure is propagated, not swallowed (regression: rc capture) =====
new_sandbox
rc=$(
  atomic_state_append() { return 69; }   # stub the durable write to fail (disk-full / EACCES)
  record | ledger_append >/dev/null 2>&1
  echo $?
)
if [ "$rc" -ne 0 ] && [ "$(jsonl_lines)" -eq 0 ]; then
  pass "durable append failure → ledger_append returns non-zero (rc=$rc), nothing written"
else
  fail "durable write failure swallowed — rc=$rc lines=$(jsonl_lines)"
fi

# ===== 14. Two distinct auto-run_id records (no caller run_id, same second) → 2 lines =====
# Regression for the 1-second-resolution run_id collision: back-to-back calls land in the same
# second, so without entropy the second would dedup-drop. Both omit run_id; candidates differ.
new_sandbox
record plan | ledger_append >/dev/null
record plan aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa cccccccccccccccccccccccccccccccccccccccc | ledger_append >/dev/null
if [ "$(jsonl_lines)" -eq 2 ]; then
  pass "two distinct auto-run_id records in the same second → 2 lines (no false dedup)"
else
  fail "auto-run_id collision dropped a distinct run — $(jsonl_lines) lines"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
