#!/usr/bin/env bash
# Smoke test for lib/update-semantic.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

SANDBOX_DIR=""
new_sandbox() {
  SANDBOX_DIR="$(mktemp -d "$TMPDIR_BASE/sandbox.XXXXXXXXXX")"
  mkdir -p "$SANDBOX_DIR/.geniro/planning"
  cd "$SANDBOX_DIR" || return 1
  git init -q
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/update-semantic.sh"
}

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# ---------------------------------------------------------------------------
# Append
# ---------------------------------------------------------------------------

# Append to non-existent file → creates file with one line
new_sandbox
update_semantic --file codebase-map --append "- src/foo.ts — root, used by App.tsx"
if [ -f .geniro/planning/_CODEBASE_MAP.md ] \
   && [ "$(wc -l < .geniro/planning/_CODEBASE_MAP.md)" -eq 1 ]; then
  pass "append to missing file creates it with one line"
else
  fail "append to missing file"
fi

# Append to a file WITHOUT trailing newline must NOT concatenate onto the
# prior final line. Regression for the P0 found in round-3 review where
# `printf '%s\n' >> file` produced "old line- new line\n" on no-nl files.
new_sandbox
printf 'pre-existing line without newline' > .geniro/planning/_CODEBASE_MAP.md
update_semantic --file codebase-map --append "- new line"
n=$(wc -l < .geniro/planning/_CODEBASE_MAP.md)
if [ "$n" -eq 2 ]; then
  pass "append to no-trailing-newline file produces 2 lines (P0 regression)"
else
  fail "no-trailing-newline append: got $n lines (want 2). content: $(cat .geniro/planning/_CODEBASE_MAP.md)"
fi

# Append second line preserves first
new_sandbox
update_semantic --file codebase-map --append "- a"
update_semantic --file codebase-map --append "- b"
if [ "$(wc -l < .geniro/planning/_CODEBASE_MAP.md)" -eq 2 ]; then
  pass "append preserves prior content (2 lines)"
else
  fail "append-then-append: lines=$(wc -l < .geniro/planning/_CODEBASE_MAP.md)"
fi

# Append to features file uses different target
new_sandbox
update_semantic --file features --append "- [feat-1] foo, scope: ui, status: pending"
if [ -f .geniro/planning/_FEATURES.md ] && [ ! -f .geniro/planning/_CODEBASE_MAP.md ]; then
  pass "--file features writes to _FEATURES.md (not _CODEBASE_MAP.md)"
else
  fail "--file features routing"
fi

# ---------------------------------------------------------------------------
# Replace
# ---------------------------------------------------------------------------

# Replace by prefix on existing file with matching line
new_sandbox
printf '%s\n' \
  "- src/foo.ts — old description, used by App.tsx" \
  "- src/bar.ts — utility, used by foo.ts" \
  > .geniro/planning/_CODEBASE_MAP.md
update_semantic --file codebase-map \
  --replace "- src/foo.ts" "- src/foo.ts — NEW description, used by App.tsx"
got=$(grep -c 'NEW description' .geniro/planning/_CODEBASE_MAP.md)
preserved=$(grep -c 'utility, used by foo.ts' .geniro/planning/_CODEBASE_MAP.md)
if [ "$got" = "1" ] && [ "$preserved" = "1" ]; then
  pass "replace updates matching line + preserves non-matching"
else
  fail "replace: got=$got preserved=$preserved"
fi

# Replace with no match → no-op, stderr notice
new_sandbox
echo "- src/foo.ts — original" > .geniro/planning/_CODEBASE_MAP.md
err=$(update_semantic --file codebase-map --replace "- not-here" "irrelevant" 2>&1)
if echo "$err" | grep -q 'did not match'; then
  pass "replace with no match emits stderr notice"
else
  fail "replace-no-match stderr: '$err'"
fi
if [ "$(cat .geniro/planning/_CODEBASE_MAP.md)" = "- src/foo.ts — original" ]; then
  pass "replace with no match preserves file"
else
  fail "replace-no-match clobbered file: $(cat .geniro/planning/_CODEBASE_MAP.md)"
fi

# Replace on missing file → no-op, no error
new_sandbox
set +e
update_semantic --file codebase-map --replace "x" "y" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ ! -f .geniro/planning/_CODEBASE_MAP.md ]; then
  pass "replace on missing file is a no-op (rc=0, file not created)"
else
  fail "replace-missing-file: rc=$rc, file-exists=$([ -f .geniro/planning/_CODEBASE_MAP.md ] && echo yes || echo no)"
fi

# Replace only touches FIRST matching line
new_sandbox
printf '%s\n' \
  "- src/foo.ts — A" \
  "- src/foo.ts — B" \
  > .geniro/planning/_CODEBASE_MAP.md
update_semantic --file codebase-map --replace "- src/foo.ts" "- src/foo.ts — REPLACED"
content=$(cat .geniro/planning/_CODEBASE_MAP.md)
expected=$(printf '%s\n%s\n' "- src/foo.ts — REPLACED" "- src/foo.ts — B")
if [ "$content" = "$expected" ]; then
  pass "replace touches only the first matching line"
else
  fail "first-match-only: content='$content'"
fi

# ---------------------------------------------------------------------------
# Flag validation
# ---------------------------------------------------------------------------

new_sandbox
set +e
update_semantic --file bogus --append "x" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "bad --file → rc=64"
else
  fail "bad --file should rc=64; got $rc"
fi

new_sandbox
set +e
update_semantic --append "x" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "missing --file → rc=64"
else
  fail "missing --file should rc=64; got $rc"
fi

new_sandbox
set +e
update_semantic --file codebase-map 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "missing op → rc=64"
else
  fail "missing op should rc=64; got $rc"
fi

new_sandbox
set +e
update_semantic --file codebase-map --append "a" --replace "b" "c" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "--append + --replace combined → rc=64"
else
  fail "combined ops should rc=64; got $rc"
fi

new_sandbox
set +e
update_semantic --foo 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "unknown flag → rc=64"
else
  fail "unknown flag should rc=64; got $rc"
fi

# Trailing --file (missing operand) → rc=64 PROMPTLY. Regression guard against
# the parse-loop spin: `shift 2` with $#=1 no-ops, so an unguarded arm loops on
# --file forever. Run in a background subshell and poll, so a regression fails
# the test instead of hanging the whole suite.
new_sandbox
set +e
( update_semantic --file 2>/dev/null ) &
guard_pid=$!
rc=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! kill -0 "$guard_pid" 2>/dev/null; then
    wait "$guard_pid"
    rc=$?
    break
  fi
  sleep 0.5
done
if [ -z "$rc" ]; then
  kill "$guard_pid" 2>/dev/null
  wait "$guard_pid" 2>/dev/null
  fail "trailing --file hung (parse-loop spin regression)"
elif [ "$rc" -eq 64 ]; then
  pass "trailing --file (missing operand) → rc=64 promptly (no spin)"
else
  fail "trailing --file should rc=64; got $rc"
fi
set -e

# ---------------------------------------------------------------------------
# Secret redaction
# ---------------------------------------------------------------------------

# Appended content routes through redact_secrets before commit — a line
# carrying a secret must land redacted, never verbatim.
new_sandbox
update_semantic --file codebase-map --append "- api key sk-ant-abc123XYZ used in src/client.ts"
if grep -q 'REDACTED:api-key:anthropic' .geniro/planning/_CODEBASE_MAP.md \
   && ! grep -q 'sk-ant-abc123XYZ' .geniro/planning/_CODEBASE_MAP.md; then
  pass "append redacts secrets before commit"
else
  fail "append redaction — stored: $(cat .geniro/planning/_CODEBASE_MAP.md)"
fi

# ---------------------------------------------------------------------------
# Lock contention
# ---------------------------------------------------------------------------

# Manually acquire the lock, helper should return 11
new_sandbox
: > .geniro/planning/.codebase-map.lock
set +e
update_semantic --file codebase-map --append "x" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 11 ]; then
  pass "held lock → rc=11"
else
  fail "held lock should rc=11; got $rc"
fi
# Cleanup
rm -f .geniro/planning/.codebase-map.lock

# Lock is released after success
new_sandbox
update_semantic --file codebase-map --append "x"
if [ ! -f .geniro/planning/.codebase-map.lock ]; then
  pass "lock released after successful append"
else
  fail "lock leaked after success"
fi

# Different files have independent locks
new_sandbox
: > .geniro/planning/.codebase-map.lock
set +e
update_semantic --file features --append "- [feat-1] x" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -f .geniro/planning/_FEATURES.md ]; then
  pass "different files have independent locks (features unblocked while codebase-map locked)"
else
  fail "feature write blocked by codebase-map lock — rc=$rc"
fi
rm -f .geniro/planning/.codebase-map.lock

# A FRESH held lock still blocks (rc=11) — the reclaim must not steal a live lock.
new_sandbox
: > .geniro/planning/.codebase-map.lock   # mtime = now, well within the stale window
set +e
update_semantic --file codebase-map --append "x" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 11 ]; then
  pass "fresh held lock still blocks (rc=11) — reclaim does not steal a live lock"
else
  fail "fresh lock should rc=11; got $rc"
fi
rm -f .geniro/planning/.codebase-map.lock

# A STALE held lock (mtime older than the 600s window) is reclaimed, the write
# succeeds, and the lock is released. Guards the SIGKILL/crash wedge: without
# reclaim the lock would pin every future L3 write at rc=11 forever.
new_sandbox
: > .geniro/planning/.codebase-map.lock
touch -t 202001010000 .geniro/planning/.codebase-map.lock   # backdate to 2020 → stale
set +e
update_semantic --file codebase-map --append "- reclaimed after stale lock" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 0 ] \
   && grep -q 'reclaimed after stale lock' .geniro/planning/_CODEBASE_MAP.md \
   && [ ! -f .geniro/planning/.codebase-map.lock ]; then
  pass "stale lock (>600s) is reclaimed, write succeeds, lock released"
else
  fail "stale-lock reclaim: rc=$rc, lock-exists=$([ -f .geniro/planning/.codebase-map.lock ] && echo yes || echo no)"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
