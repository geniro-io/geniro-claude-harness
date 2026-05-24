#!/usr/bin/env bash
# Smoke test for lib/atomic-state-write.sh
#
# Run: bash tests/state/atomic-write.sh
# Exits non-zero on any failure.
#
# Plugin-developer tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/atomic-state-write.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "PASS: $1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "FAIL: $1" >&2
}

# ---------------------------------------------------------------------------
# atomic_state_write
# ---------------------------------------------------------------------------

# Test 1: basic write
target="$TMPDIR/t1.md"
atomic_state_write "$target" <<'EOF'
hello world
EOF
if [ -f "$target" ] && [ "$(cat "$target")" = "hello world" ]; then
  pass "atomic_state_write — basic write"
else
  fail "atomic_state_write — basic write (got: '$(cat "$target" 2>/dev/null)')"
fi

# Test 2: overwrite existing file
atomic_state_write "$target" <<'EOF'
second write
EOF
if [ "$(cat "$target")" = "second write" ]; then
  pass "atomic_state_write — overwrites existing"
else
  fail "atomic_state_write — overwrites existing (got: '$(cat "$target" 2>/dev/null)')"
fi

# Test 3: parent dir auto-created
target="$TMPDIR/nested/dir/t3.md"
atomic_state_write "$target" <<'EOF'
nested
EOF
if [ -f "$target" ] && [ "$(cat "$target")" = "nested" ]; then
  pass "atomic_state_write — creates parent directory"
else
  fail "atomic_state_write — creates parent directory"
fi

# Test 4: no target path → exit 64
set +e
echo "x" | atomic_state_write "" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "atomic_state_write — missing target returns 64"
else
  fail "atomic_state_write — missing target (rc=$rc, expected 64)"
fi

# Test 5: no tmp file remains after successful write
target="$TMPDIR/t5.md"
atomic_state_write "$target" <<'EOF'
content
EOF
remnant=$(find "$TMPDIR" -maxdepth 1 -name 't5.md.tmp.*' 2>/dev/null | head -1)
if [ -z "$remnant" ]; then
  pass "atomic_state_write — leaves no tmp file after success"
else
  fail "atomic_state_write — tmp file remains: $remnant"
fi

# Test 6: multi-line content preserved verbatim
target="$TMPDIR/t6.md"
atomic_state_write "$target" <<'EOF'
---
tier: T1
producer: test
---

## Body
line 1
line 2
EOF
expected="---
tier: T1
producer: test
---

## Body
line 1
line 2"
if [ "$(cat "$target")" = "$expected" ]; then
  pass "atomic_state_write — multi-line content preserved"
else
  fail "atomic_state_write — multi-line content mangled"
fi

# Test 6b: empty stdin must not nuke existing target.
# Regression test for a bug where `failing_gen | atomic_state_write target`
# silently truncated target to zero bytes.
target="$TMPDIR/t6b.md"
printf 'precious state\n' > "$target"
true | atomic_state_write "$target"
if [ -f "$target" ] && [ "$(cat "$target")" = "precious state" ]; then
  pass "atomic_state_write — empty stdin preserves existing target"
else
  fail "atomic_state_write — empty stdin clobbered target (got: '$(cat "$target" 2>/dev/null)')"
fi

# ---------------------------------------------------------------------------
# atomic_state_append
# ---------------------------------------------------------------------------

# Test 7: single line append
target="$TMPDIR/log.jsonl"
printf '%s' '{"line":1}' | atomic_state_append "$target"
if [ -f "$target" ] && [ "$(cat "$target")" = '{"line":1}' ]; then
  pass "atomic_state_append — single line"
else
  fail "atomic_state_append — single line (got: '$(cat "$target" 2>/dev/null)')"
fi

# Test 8: second append doesn't replace first
printf '%s' '{"line":2}' | atomic_state_append "$target"
expected='{"line":1}
{"line":2}'
if [ "$(cat "$target")" = "$expected" ]; then
  pass "atomic_state_append — appends without replacing"
else
  fail "atomic_state_append — appended content wrong (got: '$(cat "$target")')"
fi

# Test 9: missing target → exit 64
set +e
echo "x" | atomic_state_append "" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "atomic_state_append — missing target returns 64"
else
  fail "atomic_state_append — missing target (rc=$rc, expected 64)"
fi

# Test 10: line >4096 bytes → exit 68 (atomicity not guaranteed)
target="$TMPDIR/big.jsonl"
big_line="$(printf 'x%.0s' $(seq 1 5000))"
set +e
printf '%s' "$big_line" | atomic_state_append "$target" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 68 ]; then
  pass "atomic_state_append — oversized line returns 68"
else
  fail "atomic_state_append — oversized line (rc=$rc, expected 68)"
fi

# Test 11: parent dir auto-created for append
target="$TMPDIR/append-nested/log.jsonl"
printf '%s' '{"first":true}' | atomic_state_append "$target"
if [ -f "$target" ] && [ "$(cat "$target")" = '{"first":true}' ]; then
  pass "atomic_state_append — creates parent directory"
else
  fail "atomic_state_append — creates parent directory"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

# Test 12: append to file without trailing newline must NOT concatenate.
# Regression for the bug where a hand-edited learnings.jsonl ending without
# `\n` caused emit-learning to merge two JSONL objects onto one physical line.
target="$TMPDIR/t12.jsonl"
printf '{"first":"line"}' > "$target"   # No trailing newline.
printf '{"second":"line"}' | atomic_state_append "$target"
n=$(wc -l < "$target")
if [ "$n" = "2" ]; then
  pass "atomic_state_append — appends to no-trailing-newline file with leading-\\n guard"
else
  fail "no-trailing-newline append produced $n lines (want 2). File: $(cat "$target")"
fi

# Test 13: append to file WITH trailing newline must NOT add an extra blank line.
target="$TMPDIR/t13.jsonl"
printf '{"first":"line"}\n' > "$target"  # WITH trailing newline.
printf '{"second":"line"}' | atomic_state_append "$target"
n=$(wc -l < "$target")
if [ "$n" = "2" ]; then
  pass "atomic_state_append — newline-terminated file gets exactly one more line"
else
  fail "newline-terminated append produced $n lines (want 2)"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
