#!/usr/bin/env bash
# Smoke test for lib/emit-rejection.sh (emit_rejection_if_signal)
#
# Run: bash tests/memory/emit-rejection.sh
#
# Coverage:
#   - Each explicit signal (cancel / abort / reject / exact-no / skip) emits an
#     L2 entry with the right rejection_signal.
#   - picked != recommended (no explicit keyword) -> picked_non_recommended.
#   - picked == recommended -> no-op (no entry).
#   - Substring false-positive guard: 'now' is NOT treated as 'no'.
#   - Missing required arg -> rc=64.
#   - Emitted entry shape: type / trust / ext.* / tags.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

LOG=""
new_sandbox() {
  local d; d="$(mktemp -d "$TMPDIR_BASE/sandbox.XXXXXXXXXX")"
  mkdir -p "$d/.geniro"
  cd "$d" || return 1
  git init -q
  LOG="$d/.geniro/knowledge/learnings.jsonl"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/emit-rejection.sh"
}
last_entry() { tail -n 1 "$LOG" 2>/dev/null; }
line_count() { if [ -f "$LOG" ]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }

# Assert an emitted entry carries the expected rejection_signal + canonical shape.
assert_signal() {
  local label="$1" expect="$2"
  local e; e="$(last_entry)"
  local sig type trust cat
  sig=$(printf '%s' "$e" | jq -r '.ext.rejection_signal')
  type=$(printf '%s' "$e" | jq -r '.type')
  trust=$(printf '%s' "$e" | jq -r '.trust')
  cat=$(printf '%s' "$e" | jq -r '.ext.auq_category')
  if [ "$sig" = "$expect" ] && [ "$type" = "user_rejected_suggestion" ] \
     && [ "$trust" = "verified" ] && [ "$cat" = "ship_mode" ]; then
    pass "$label -> signal=$expect, canonical entry shape"
  else
    fail "$label: signal='$sig' type='$type' trust='$trust' cat='$cat'"
  fi
}

# ===== Explicit signals =====
new_sandbox
emit_rejection_if_signal "/plan" "global" "ship_mode" "open PR" "Cancel" >/dev/null 2>&1
assert_signal "explicit Cancel" "explicit_cancel"

new_sandbox
emit_rejection_if_signal "/plan" "global" "ship_mode" "open PR" "Abort run" >/dev/null 2>&1
assert_signal "explicit Abort" "explicit_cancel"

new_sandbox
emit_rejection_if_signal "/plan" "global" "ship_mode" "open PR" "Reject finding" >/dev/null 2>&1
assert_signal "explicit Reject" "explicit_no"

new_sandbox
emit_rejection_if_signal "/plan" "global" "ship_mode" "open PR" "no" >/dev/null 2>&1
assert_signal "exact 'no'" "explicit_no"

new_sandbox
emit_rejection_if_signal "/plan" "global" "ship_mode" "open PR" "Skip this" >/dev/null 2>&1
assert_signal "explicit Skip" "explicit_skip"

# ===== Tags carry the generic + per-category labels =====
new_sandbox
emit_rejection_if_signal "/plan" "global" "ship_mode" "open PR" "Cancel" >/dev/null 2>&1
tags=$(last_entry | jq -c '.tags')
if echo "$tags" | grep -q 'auq-rejection' && echo "$tags" | grep -q 'ship_mode'; then
  pass "tags include auq-rejection + category"
else
  fail "tags wrong: $tags"
fi

# ===== picked != recommended (no explicit keyword) -> picked_non_recommended =====
new_sandbox
emit_rejection_if_signal "/plan" "global" "ship_mode" "open PR" "Option B" "Option A" >/dev/null 2>&1
sig=$(last_entry | jq -r '.ext.rejection_signal')
[ "$sig" = "picked_non_recommended" ] \
  && pass "picked != recommended -> picked_non_recommended" \
  || fail "expected picked_non_recommended; got '$sig'"

# ===== picked == recommended -> no-op (no entry) =====
new_sandbox
set +e
emit_rejection_if_signal "/plan" "global" "ship_mode" "open PR" "Option A" "Option A" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ "$(line_count)" -eq 0 ]; then
  pass "picked == recommended -> no-op (rc=0, no entry)"
else
  fail "picked==recommended should be silent no-op; rc=$rc lines=$(line_count)"
fi

# ===== Substring false-positive guard: 'now' is NOT 'no' =====
new_sandbox
set +e
emit_rejection_if_signal "/plan" "global" "ship_mode" "open PR" "now" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ "$(line_count)" -eq 0 ]; then
  pass "'now' (no recommendation) is NOT a rejection signal (no false 'no' match)"
else
  fail "'now' wrongly emitted; rc=$rc lines=$(line_count)"
fi

# ===== Missing required arg -> rc=64 =====
new_sandbox
set +e
emit_rejection_if_signal "/plan" "global" "ship_mode" "open PR" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 64 ] \
  && pass "missing 'picked' arg -> rc=64" \
  || fail "missing arg should rc=64; got $rc"

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
