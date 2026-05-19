#!/usr/bin/env bash
# Smoke test for skills/_shared/emit-learning.sh
#
# Run: bash tests/memory/emit-learning.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

SANDBOX_DIR=""
new_sandbox() {
  SANDBOX_DIR="$TMPDIR_BASE/$(date +%s%N)-$RANDOM"
  mkdir -p "$SANDBOX_DIR/.geniro"
  cd "$SANDBOX_DIR" || return 1
  git init -q
  # shellcheck disable=SC1091
  source "$REPO_ROOT/skills/_shared/emit-learning.sh"
}

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Read the (single) JSONL line from the log.
read_log() {
  cat "$SANDBOX_DIR/.geniro/knowledge/learnings.jsonl"
}
log_line_count() {
  if [ -f "$SANDBOX_DIR/.geniro/knowledge/learnings.jsonl" ]; then
    wc -l < "$SANDBOX_DIR/.geniro/knowledge/learnings.jsonl"
  else
    echo 0
  fi
}

# Basic minimal entry.
new_sandbox
set +e
echo '{"producer":"/debug","scope":"src/foo","summary":"baseline test","tags":["bug"]}' | emit_learning
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ "$(log_line_count)" -eq 1 ]; then
  pass "minimal entry appends one line"
else
  fail "minimal entry — rc=$rc lines=$(log_line_count)"
fi

# Auto-injected ts is ISO-8601 UTC.
new_sandbox
echo '{"producer":"/debug","scope":"src/foo","summary":"ts test","tags":["bug"]}' | emit_learning
ts=$(read_log | jq -r .ts)
if echo "$ts" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  pass "auto-injected ts in ISO-8601 UTC format"
else
  fail "ts not ISO-8601 UTC: '$ts'"
fi

# Auto-computed dedup_key.
new_sandbox
echo '{"producer":"/debug","scope":"src/foo","summary":"  Stale CLOSURE  ","tags":["bug"]}' | emit_learning
dk=$(read_log | jq -r .dedup_key)
expected=$(printf '/debug|src/foo|stale closure' | sha256sum | cut -c1-12)
if [ "$dk" = "$expected" ]; then
  pass "auto-computed dedup_key normalizes summary (lowercase+trim+collapse)"
else
  fail "dedup_key mismatch — got '$dk' want '$expected'"
fi

# Caller-supplied dedup_key respected.
new_sandbox
echo '{"producer":"/debug","scope":"src/foo","summary":"x","tags":["bug"],"dedup_key":"deadbeef0000"}' | emit_learning
dk=$(read_log | jq -r .dedup_key)
if [ "$dk" = "deadbeef0000" ]; then
  pass "caller-supplied dedup_key preserved"
else
  fail "dedup_key overwritten — got '$dk'"
fi

# Required-field violations.
new_sandbox
set +e
echo '{"scope":"x","summary":"y","tags":[]}' | emit_learning 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "missing producer → rc=64"
else
  fail "missing producer should rc=64; got $rc"
fi

new_sandbox
set +e
echo '{"producer":"/debug","scope":"x","summary":"y"}' | emit_learning 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "missing tags → rc=64"
else
  fail "missing tags should rc=64; got $rc"
fi

new_sandbox
set +e
echo 'not-valid-json{' | emit_learning 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "invalid JSON → rc=64"
else
  fail "invalid JSON should rc=64; got $rc"
fi

# Sanitization: summary
new_sandbox
echo '{"producer":"/debug","scope":"x","summary":"key=AKIAIOSFODNN7EXAMPLE leaked","tags":["bug"]}' | emit_learning
sum=$(read_log | jq -r .summary)
if echo "$sum" | grep -q '\[REDACTED:aws-key\]'; then
  pass "summary sanitization fires"
else
  fail "summary not sanitized: '$sum'"
fi

# Sanitization: body
new_sandbox
echo '{"producer":"/debug","scope":"x","summary":"y","tags":["bug"],"body":"Authorization: Bearer abc.def_123"}' | emit_learning
body=$(read_log | jq -r .body)
if echo "$body" | grep -q '\[REDACTED:bearer\]'; then
  pass "body sanitization fires"
else
  fail "body not sanitized: '$body'"
fi

# Sanitization: ext.* strings
new_sandbox
jq -nc '{
  producer:"/debug", scope:"x", summary:"y", tags:["bug"],
  type:"diagnosis",
  ext:{
    symptom:"saw eyJaaaa.eyJbbbb.signature_part",
    root_cause:"missing dep",
    fix:"add it"
  }
}' | emit_learning
sym=$(read_log | jq -r .ext.symptom)
if echo "$sym" | grep -q '\[REDACTED:jwt\]'; then
  pass "ext.symptom sanitization fires"
else
  fail "ext.symptom not sanitized: '$sym'"
fi

# Sanitization: nested ext (array)
new_sandbox
jq -nc '{
  producer:"/plan", scope:"global", summary:"y", tags:["arch"],
  type:"decision",
  ext:{
    options:["sk-ant-api03-leaked","fetch"],
    chosen:"fetch",
    reasoning:"safer"
  }
}' | emit_learning
opt0=$(read_log | jq -r '.ext.options[0]')
if echo "$opt0" | grep -q '\[REDACTED:api-key:anthropic\]'; then
  pass "ext.options[0] (array element) sanitization fires"
else
  fail "ext.options[0] not sanitized: '$opt0'"
fi

# Dedup: identical entries → second is no-op.
new_sandbox
echo '{"producer":"/debug","scope":"src/foo","summary":"same","tags":["bug"]}' | emit_learning
echo '{"producer":"/debug","scope":"src/foo","summary":"same","tags":["bug"]}' | emit_learning
n=$(log_line_count)
if [ "$n" -eq 1 ]; then
  pass "identical entry (matching dedup_key + content) is no-op"
else
  fail "identical entry produced $n lines, want 1"
fi

# Dedup: different content same dedup_key → supersedes auto-injected.
new_sandbox
echo '{"producer":"/debug","scope":"src/foo","summary":"v1","tags":["bug"],"dedup_key":"k1"}' | emit_learning
echo '{"producer":"/debug","scope":"src/foo","summary":"v2","tags":["bug"],"dedup_key":"k1"}' | emit_learning
n=$(log_line_count)
if [ "$n" -eq 2 ]; then
  pass "different content under same dedup_key appends second entry"
else
  fail "expected 2 lines after different-content append; got $n"
fi
last_super=$(tail -n 1 "$SANDBOX_DIR/.geniro/knowledge/learnings.jsonl" | jq -r .supersedes)
if [ "$last_super" = "k1" ]; then
  pass "supersedes auto-injected for changed content"
else
  fail "supersedes missing or wrong: '$last_super'"
fi

# Dedup: caller-set supersedes is preserved verbatim.
new_sandbox
echo '{"producer":"/debug","scope":"src/foo","summary":"v1","tags":["bug"],"dedup_key":"k2"}' | emit_learning
echo '{"producer":"/debug","scope":"src/foo","summary":"v2","tags":["bug"],"dedup_key":"k2","supersedes":"explicit-old-key"}' | emit_learning
last_super=$(tail -n 1 "$SANDBOX_DIR/.geniro/knowledge/learnings.jsonl" | jq -r .supersedes)
if [ "$last_super" = "explicit-old-key" ]; then
  pass "caller-set supersedes is preserved (not overwritten)"
else
  fail "caller supersedes overwritten — got '$last_super'"
fi

# Oversize: serialized entry > 4096 → rc=68.
new_sandbox
big=$(printf 'x%.0s' {1..5000})
set +e
jq -nc --arg b "$big" '{producer:"/debug",scope:"x",summary:"y",tags:["bug"],body:$b}' | emit_learning 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 68 ]; then
  pass "oversized entry (>4096 B) → rc=68"
else
  fail "oversized entry should rc=68; got $rc"
fi

# Empty stdin → no-op return 0.
new_sandbox
set +e
printf '' | emit_learning
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ "$(log_line_count)" -eq 0 ]; then
  pass "empty stdin is no-op (rc=0, no log file change)"
else
  fail "empty stdin should be no-op; rc=$rc lines=$(log_line_count)"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
