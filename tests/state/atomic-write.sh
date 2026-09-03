#!/usr/bin/env bash
# Smoke test for lib/atomic-state-write.sh
#
# Run: bash tests/state/atomic-write.sh
# Exits non-zero on any failure.
#
# Plugin-developer tooling only — not shipped to user projects.

# No `set -e`: every case below captures the helper's rc explicitly and asserts
# on it, so an expected non-zero return must not abort the suite.
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
echo "x" | atomic_state_write "" 2>/dev/null
rc=$?
if [ "$rc" -eq 64 ]; then
  pass "atomic_state_write — missing target returns 64"
else
  fail "atomic_state_write — missing target (rc=$rc, expected 64)"
fi

# Test 4b: ZERO-arg call under `set -u` must still reach the guard (rc=64), not
# abort on an "unbound variable" $1. Run in a subshell so an unfixed helper
# fails this one assertion instead of crashing the whole suite.
rc=$(set -u; echo "x" | atomic_state_write >/dev/null 2>&1; echo $?)
if [ "$rc" -eq 64 ]; then
  pass "atomic_state_write — zero-arg under set -u returns 64 (not an unbound crash)"
else
  fail "atomic_state_write — zero-arg under set -u (rc=$rc, expected 64)"
fi

# Test 5: no tmp file remains after successful write
target="$TMPDIR/t5.md"
atomic_state_write "$target" <<'EOF'
content
EOF
rc=$?
remnant=$(find "$TMPDIR" -maxdepth 1 -name 't5.md.tmp.*' 2>/dev/null | head -1)
if [ -z "$remnant" ] && [ "$rc" -eq 0 ] && [ "$(cat "$target")" = "content" ]; then
  pass "atomic_state_write — leaves no tmp file after success"
else
  fail "atomic_state_write — rc=$rc content='$(cat "$target" 2>/dev/null)' tmp remains: $remnant"
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

# Test 6c: empty stdin must REPORT (rc 70), not return 0.
# A pipeline puts the helper last, so the pipeline's rc is the helper's — an
# rc 0 here told the caller "state written" for a producer that crashed before
# emitting a byte. Same class as emit_learning returning 0 with nothing on disk.
target="$TMPDIR/t6c.md"
printf 'precious state\n' > "$target"
bash -c 'exit 1' 2>/dev/null | atomic_state_write "$target" 2>/dev/null
rc=$?
if [ "$rc" -eq 70 ] && [ "$(cat "$target")" = "precious state" ]; then
  pass "atomic_state_write — crashed producer reports rc 70, target untouched"
else
  fail "atomic_state_write — empty stdin rc=$rc (want 70), content: '$(cat "$target" 2>/dev/null)'"
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
echo "x" | atomic_state_append "" 2>/dev/null
rc=$?
if [ "$rc" -eq 64 ]; then
  pass "atomic_state_append — missing target returns 64"
else
  fail "atomic_state_append — missing target (rc=$rc, expected 64)"
fi

# Test 10: line >4096 bytes → exit 68 (atomicity not guaranteed)
target="$TMPDIR/big.jsonl"
big_line="$(printf 'x%.0s' $(seq 1 5000))"
printf '%s' "$big_line" | atomic_state_append "$target" 2>/dev/null
rc=$?
if [ "$rc" -eq 68 ] && [ ! -s "$target" ]; then
  pass "atomic_state_append — oversized line returns 68 and appends nothing"
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
want='{"first":"line"}
{"second":"line"}'
if [ "$n" -eq 2 ] && [ "$(cat "$target")" = "$want" ]; then
  pass "atomic_state_append — appends to no-trailing-newline file with leading-\\n guard"
else
  fail "no-trailing-newline append produced $n lines (want 2). File: $(cat "$target")"
fi

# Test 13: append to file WITH trailing newline must NOT add an extra blank line.
target="$TMPDIR/t13.jsonl"
printf '{"first":"line"}\n' > "$target"  # WITH trailing newline.
printf '{"second":"line"}' | atomic_state_append "$target"
n=$(wc -l < "$target")
want='{"first":"line"}
{"second":"line"}'
if [ "$n" -eq 2 ] && [ "$(cat "$target")" = "$want" ]; then
  pass "atomic_state_append — newline-terminated file gets exactly one more line"
else
  fail "newline-terminated append produced $n lines (want 2)"
fi

# Test 13b: append with empty stdin must report rc 70, not silently succeed.
target="$TMPDIR/t13b.jsonl"
printf '{"first":"line"}\n' > "$target"
true | atomic_state_append "$target" 2>/dev/null
rc=$?
n=$(wc -l < "$target")
if [ "$rc" -eq 70 ] && [ "$n" -eq 1 ]; then
  pass "atomic_state_append — empty stdin reports rc 70, appends nothing"
else
  fail "atomic_state_append — empty stdin rc=$rc (want 70), lines=$n (want 1)"
fi

# ---------------------------------------------------------------------------
# atomic_state_write_cmd — producer exit status is visible
# ---------------------------------------------------------------------------

# Test 14: a producer that dies MID-STREAM must not commit its partial output.
# This is the defect the pipeline form cannot catch: `cat` sees a short but
# valid payload, so the helper renamed a truncated file over good state at rc 0.
target="$TMPDIR/t14.md"
printf 'ORIGINAL\n' > "$target"
atomic_state_write_cmd "$target" bash -c 'printf HALF; exit 1' 2>/dev/null
rc=$?
if [ "$rc" -eq 75 ] && [ "$(cat "$target")" = "ORIGINAL" ]; then
  pass "atomic_state_write_cmd — mid-stream producer failure does not commit partial output"
else
  fail "atomic_state_write_cmd — partial commit: rc=$rc (want 75), content: '$(cat "$target")' (want ORIGINAL)"
fi

# Test 15: a producer that fails with no output → rc 75, target untouched.
target="$TMPDIR/t15.md"
printf 'ORIGINAL\n' > "$target"
atomic_state_write_cmd "$target" bash -c 'exit 3' 2>/dev/null
rc=$?
if [ "$rc" -eq 75 ] && [ "$(cat "$target")" = "ORIGINAL" ]; then
  pass "atomic_state_write_cmd — silent producer failure reports rc 75"
else
  fail "atomic_state_write_cmd — silent failure rc=$rc (want 75), content: '$(cat "$target")'"
fi

# Test 16: a producer that succeeds commits normally, leaving no tmp behind.
target="$TMPDIR/t16.md"
printf 'ORIGINAL\n' > "$target"
atomic_state_write_cmd "$target" printf 'REGENERATED\n'
rc=$?
leftover=$(find "$TMPDIR" -name 't16.md.tmp.*' | wc -l | tr -d ' ')
if [ "$rc" -eq 0 ] && [ "$(cat "$target")" = "REGENERATED" ] && [ "$leftover" -eq 0 ]; then
  pass "atomic_state_write_cmd — successful producer commits, no tmp left"
else
  fail "atomic_state_write_cmd — rc=$rc, content: '$(cat "$target")', tmp leftovers=$leftover"
fi

# Test 17: no producer command → caller error rc 64.
atomic_state_write_cmd "$TMPDIR/t17.md" 2>/dev/null
rc=$?
if [ "$rc" -eq 64 ]; then
  pass "atomic_state_write_cmd — missing producer command → rc 64"
else
  fail "atomic_state_write_cmd — missing producer rc=$rc (want 64)"
fi

# ---------------------------------------------------------------------------
# atomic_state_edit — literal, exactly-once replacement
# ---------------------------------------------------------------------------

FIXTURE='---
tier: T1.5
phase: validate
status: in-progress
---

## Phase log
- analyze done
'

# Test 18: single unambiguous match is replaced; everything else byte-identical.
target="$TMPDIR/t18.md"
printf '%s' "$FIXTURE" > "$target"
atomic_state_edit "$target" "- analyze done" "- analyze done
- implement done"
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -q '^- implement done$' "$target" \
  && grep -q '^phase: validate$' "$target" \
  && [ "$(head -1 "$target")" = "---" ]; then
  pass "atomic_state_edit — replaces the one match, leaves the rest intact"
else
  fail "atomic_state_edit — rc=$rc; file:
$(cat "$target")"
fi

# Test 19: zero matches must be an error, never a no-op reported as success.
target="$TMPDIR/t19.md"
printf '%s' "$FIXTURE" > "$target"
before="$(cat "$target")"
atomic_state_edit "$target" "phase: nonexistent" "phase: ship" 2>/dev/null
rc=$?
if [ "$rc" -eq 71 ] && [ "$(cat "$target")" = "$before" ]; then
  pass "atomic_state_edit — no match → rc 71, file unchanged"
else
  fail "atomic_state_edit — no-match rc=$rc (want 71)"
fi

# Test 20: an ambiguous anchor must refuse rather than guess which one to edit.
target="$TMPDIR/t20.md"
printf 'status: open\nstatus: open\n' > "$target"
before="$(cat "$target")"
atomic_state_edit "$target" "status: open" "status: closed" 2>/dev/null
rc=$?
if [ "$rc" -eq 72 ] && [ "$(cat "$target")" = "$before" ]; then
  pass "atomic_state_edit — ambiguous anchor → rc 72, file unchanged"
else
  fail "atomic_state_edit — ambiguous rc=$rc (want 72), file: '$(cat "$target")'"
fi

# Test 21: matching is LITERAL — glob metacharacters in the anchor are bytes,
# not patterns. A glob-interpreting implementation would match `axb` here.
target="$TMPDIR/t21.md"
printf 'left a*b right\nnoise axb noise\n' > "$target"
atomic_state_edit "$target" 'a*b' 'REPLACED'
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -q '^left REPLACED right$' "$target" \
  && grep -q '^noise axb noise$' "$target"; then
  pass "atomic_state_edit — glob metacharacters matched literally"
else
  fail "atomic_state_edit — literal match failed: rc=$rc, file:
$(cat "$target")"
fi

# Test 22: missing target → rc 73 (not a silent create).
atomic_state_edit "$TMPDIR/does-not-exist.md" "a" "b" 2>/dev/null
rc=$?
if [ "$rc" -eq 73 ] && [ ! -e "$TMPDIR/does-not-exist.md" ]; then
  pass "atomic_state_edit — missing target → rc 73, no file created"
else
  fail "atomic_state_edit — missing target rc=$rc (want 73)"
fi

# Test 23: empty old text is a caller error, not a match-everywhere edit.
target="$TMPDIR/t23.md"
printf '%s' "$FIXTURE" > "$target"
atomic_state_edit "$target" "" "x" 2>/dev/null
rc=$?
if [ "$rc" -eq 64 ]; then
  pass "atomic_state_edit — empty old text → rc 64"
else
  fail "atomic_state_edit — empty old text rc=$rc (want 64)"
fi

# Test 24: trailing newline is preserved byte-for-byte.
target="$TMPDIR/t24.md"
printf 'alpha\nbeta\n' > "$target"
atomic_state_edit "$target" "beta" "gamma"
if [ -z "$(tail -c 1 "$target")" ] && [ "$(cat "$target")" = "alpha
gamma" ]; then
  pass "atomic_state_edit — trailing newline preserved"
else
  fail "atomic_state_edit — trailing newline lost or content wrong"
fi

# ---------------------------------------------------------------------------
# atomic_state_set_field — frontmatter-scoped field advance
# ---------------------------------------------------------------------------

# Test 25: advancing a field leaves every other field and the body untouched.
# This is the silent-carry-forward class: a whole-file regeneration re-writes
# untouched fields at their old values; a scoped set cannot.
target="$TMPDIR/t25.md"
printf '%s' "$FIXTURE" > "$target"
atomic_state_set_field "$target" "phase" "user-approve"
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -q '^phase: user-approve$' "$target" \
  && grep -q '^tier: T1.5$' "$target" \
  && grep -q '^status: in-progress$' "$target" \
  && grep -q '^- analyze done$' "$target"; then
  pass "atomic_state_set_field — sets the field, preserves siblings and body"
else
  fail "atomic_state_set_field — rc=$rc; file:
$(cat "$target")"
fi

# Test 26: a same-named line in the BODY must not be touched.
target="$TMPDIR/t26.md"
printf -- '---\nphase: validate\n---\n\nprose about phase: validate here\n' > "$target"
atomic_state_set_field "$target" "phase" "ship"
rc=$?
body_hits=$(grep -c 'prose about phase: validate here' "$target")
if [ "$rc" -eq 0 ] && grep -q '^phase: ship$' "$target" && [ "$body_hits" -eq 1 ]; then
  pass "atomic_state_set_field — body line with the same key is left alone"
else
  fail "atomic_state_set_field — body leaked: rc=$rc, file:
$(cat "$target")"
fi

# Test 27: setting a field the schema does not have must fail, not invent a key.
target="$TMPDIR/t27.md"
printf '%s' "$FIXTURE" > "$target"
before="$(cat "$target")"
atomic_state_set_field "$target" "made-up-key" "x" 2>/dev/null
rc=$?
if [ "$rc" -eq 74 ] && [ "$(cat "$target")" = "$before" ]; then
  pass "atomic_state_set_field — absent field → rc 74, file unchanged"
else
  fail "atomic_state_set_field — absent field rc=$rc (want 74)"
fi

# Test 28: a file with no frontmatter at all → rc 74, nothing written.
target="$TMPDIR/t28.md"
printf 'no frontmatter here\nphase: validate\n' > "$target"
before="$(cat "$target")"
atomic_state_set_field "$target" "phase" "ship" 2>/dev/null
rc=$?
if [ "$rc" -eq 74 ] && [ "$(cat "$target")" = "$before" ]; then
  pass "atomic_state_set_field — no frontmatter block → rc 74"
else
  fail "atomic_state_set_field — no-frontmatter rc=$rc (want 74), file: '$(cat "$target")'"
fi

# Test 29: missing target → rc 73.
atomic_state_set_field "$TMPDIR/absent.md" "phase" "ship" 2>/dev/null
rc=$?
if [ "$rc" -eq 73 ]; then
  pass "atomic_state_set_field — missing target → rc 73"
else
  fail "atomic_state_set_field — missing target rc=$rc (want 73)"
fi

# Test 30: a value containing frontmatter-ish punctuation survives verbatim.
target="$TMPDIR/t30.md"
printf '%s' "$FIXTURE" > "$target"
atomic_state_set_field "$target" "status" "blocked: waiting on #42 (50% done)"
rc=$?
if [ "$rc" -eq 0 ] && grep -qxF 'status: blocked: waiting on #42 (50% done)' "$target"; then
  pass "atomic_state_set_field — punctuation-bearing value written verbatim"
else
  fail "atomic_state_set_field — value mangled: rc=$rc, line: '$(grep '^status:' "$target")'"
fi

# Test 30b: a multi-line value would put a bare continuation line inside the
# `---` block — frontmatter the validator rejects, written at rc 0.
target="$TMPDIR/t30b.md"
printf '%s' "$FIXTURE" > "$target"
before="$(cat "$target")"
atomic_state_set_field "$target" "status" "line one
line two" 2>/dev/null
rc=$?
if [ "$rc" -eq 64 ] && [ "$(cat "$target")" = "$before" ]; then
  pass "atomic_state_set_field — multi-line value → rc 64, file unchanged"
else
  fail "atomic_state_set_field — multi-line value rc=$rc (want 64), file:
$(cat "$target")"
fi

# Test 30c: with no CLOSING `---`, every body line counts as frontmatter, so the
# "leading block only" contract would hold only by first-match luck. Require the
# block to be closed before accepting any set.
target="$TMPDIR/t30c.md"
printf -- '---\nphase: a\n\nbody mentioning phase: b here\n' > "$target"
before="$(cat "$target")"
atomic_state_set_field "$target" "phase" "Z" 2>/dev/null
rc=$?
if [ "$rc" -eq 74 ] && [ "$(cat "$target")" = "$before" ]; then
  pass "atomic_state_set_field — unclosed frontmatter → rc 74, file unchanged"
else
  fail "atomic_state_set_field — unclosed frontmatter rc=$rc (want 74), file:
$(cat "$target")"
fi

# Test 30d: CRLF frontmatter must fail closed, never half-edit.
target="$TMPDIR/t30d.md"
printf -- '---\r\nphase: a\r\n---\r\n' > "$target"
before="$(cat "$target")"
atomic_state_set_field "$target" "phase" "Z" 2>/dev/null
rc=$?
if [ "$rc" -eq 74 ] && [ "$(cat "$target")" = "$before" ]; then
  pass "atomic_state_set_field — CRLF frontmatter fails closed (rc 74)"
else
  fail "atomic_state_set_field — CRLF rc=$rc (want 74)"
fi

# Test 30e: deleting a whole line via an empty replacement must not glue the
# surrounding lines together or eat a boundary newline.
target="$TMPDIR/t30e.md"
printf 'alpha\nDELETEME\nbeta\n' > "$target"
atomic_state_edit "$target" "DELETEME
" ""
rc=$?
if [ "$rc" -eq 0 ] && [ "$(od -An -c "$target" | tr -s ' ')" = "$(printf 'alpha\nbeta\n' | od -An -c | tr -s ' ')" ]; then
  pass "atomic_state_edit — line deletion keeps byte-exact newline boundaries"
else
  fail "atomic_state_edit — deletion mangled boundaries: rc=$rc, bytes: $(od -An -c "$target")"
fi

# Test 31: no tmp file survives any of the editor paths above.
leftover=$(find "$TMPDIR" -name '*.tmp.*' | wc -l | tr -d ' ')
if [ "$leftover" -eq 0 ]; then
  pass "editors — no tmp files left in the state tree"
else
  fail "editors — $leftover tmp file(s) left behind: $(find "$TMPDIR" -name '*.tmp.*')"
fi


# ---------------------------------------------------------------------------
# Regressions for defects found by adversarial review + mutation testing
# ---------------------------------------------------------------------------

# --- atomic_state_set_field: frontmatter scoping ---------------------------

# A field present ONLY in the body must not be set. Without this, removing the
# fence scope entirely leaves every other assertion green — the function's whole
# reason for existing was untested.
target="$TMPDIR/r1.md"
printf -- '---\ntier: T1\n---\n\nphase: validate\n' > "$target"
before="$(cat "$target")"
atomic_state_set_field "$target" "phase" "ship" 2>/dev/null
rc=$?
if [ "$rc" -eq 74 ] && [ "$(cat "$target")" = "$before" ]; then
  pass "set_field — a field only in the body is not set (rc 74, file unchanged)"
else
  fail "set_field — body-only field: rc=$rc (want 74), file:
$(cat "$target")"
fi

# Key matching is exact, not a prefix: `phase` must not claim `phases:`.
target="$TMPDIR/r2.md"
printf -- '---\nphases: 3\nphase: a\n---\n' > "$target"
atomic_state_set_field "$target" "phase" "Z"
rc=$?
if [ "$rc" -eq 0 ] && grep -qx 'phases: 3' "$target" && grep -qx 'phase: Z' "$target"; then
  pass "set_field — exact key match, a longer sibling key is untouched"
else
  fail "set_field — prefix key collision: rc=$rc, file:
$(cat "$target")"
fi

# Duplicate keys: only the first is rewritten.
target="$TMPDIR/r3.md"
printf -- '---\nphase: a\nphase: b\n---\n' > "$target"
atomic_state_set_field "$target" "phase" "Z"
if [ "$(sed -n 2p "$target")" = "phase: Z" ] && [ "$(sed -n 3p "$target")" = "phase: b" ]; then
  pass "set_field — only the first of duplicate keys is rewritten"
else
  fail "set_field — duplicate keys: $(sed -n '2,3p' "$target" | tr '\n' '|')"
fi

# The opening fence must be line 1; a title above it is not frontmatter.
target="$TMPDIR/r4.md"
printf -- '# Title\n---\nphase: a\n---\n' > "$target"
before="$(cat "$target")"
atomic_state_set_field "$target" "phase" "Z" 2>/dev/null
rc=$?
if [ "$rc" -eq 74 ] && [ "$(cat "$target")" = "$before" ]; then
  pass "set_field — opening fence must be line 1 (rc 74)"
else
  fail "set_field — non-line-1 fence: rc=$rc"
fi

# --- atomic_state_set_field: byte fidelity ---------------------------------

# A newline-terminated file keeps exactly one trailing newline.
target="$TMPDIR/r5.md"
printf -- '---\nphase: a\n---\nbody\n' > "$target"
atomic_state_set_field "$target" "phase" "Z"
if [ "$(od -An -c "$target" | tr -s ' ')" = "$(printf -- '---\nphase: Z\n---\nbody\n' | od -An -c | tr -s ' ')" ]; then
  pass "set_field — trailing newline preserved exactly"
else
  fail "set_field — trailing newline changed: $(od -An -c "$target")"
fi

# A file with NO trailing newline still has none, and its last line survives.
target="$TMPDIR/r6.md"
printf -- '---\nphase: a\n---\nlast line no newline' > "$target"
atomic_state_set_field "$target" "phase" "Z"
if [ "$(od -An -c "$target" | tr -s ' ')" = "$(printf -- '---\nphase: Z\n---\nlast line no newline' | od -An -c | tr -s ' ')" ]; then
  pass "set_field — missing trailing newline preserved, last line not dropped"
else
  fail "set_field — no-trailing-newline mangled: $(od -An -c "$target")"
fi

# --- atomic_state_set_field: caller errors ---------------------------------

# A forgotten value blanked the field at rc 0 — a typo destroying live state.
target="$TMPDIR/r7.md"
printf -- '---\nphase: implement\n---\n' > "$target"
before="$(cat "$target")"
atomic_state_set_field "$target" "phase" 2>/dev/null
rc=$?
if [ "$rc" -eq 64 ] && [ "$(cat "$target")" = "$before" ]; then
  pass "set_field — omitted value is an error (rc 64), not a blanked field"
else
  fail "set_field — omitted value: rc=$rc, line: '$(sed -n 2p "$target")'"
fi

# An explicit empty string is still a legal set.
target="$TMPDIR/r8.md"
printf -- '---\nphase: implement\n---\n' > "$target"
atomic_state_set_field "$target" "phase" ""
rc=$?
if [ "$rc" -eq 0 ] && [ "$(sed -n 2p "$target")" = "phase: " ]; then
  pass "set_field — an explicit empty value is accepted"
else
  fail "set_field — explicit empty value: rc=$rc, line: '$(sed -n 2p "$target")'"
fi

# Empty field name is a caller error.
target="$TMPDIR/r9.md"
printf -- '---\nphase: a\n---\n' > "$target"
atomic_state_set_field "$target" "" "Z" 2>/dev/null
rc=$?
if [ "$rc" -eq 64 ]; then
  pass "set_field — empty field name → rc 64"
else
  fail "set_field — empty field name: rc=$rc (want 64)"
fi

# --- atomic_state_write_cmd ------------------------------------------------

# A producer that succeeds but emits nothing must not commit an empty file.
target="$TMPDIR/r10.md"
printf 'ORIGINAL\n' > "$target"
atomic_state_write_cmd "$target" true 2>/dev/null
rc=$?
if [ "$rc" -eq 70 ] && [ "$(cat "$target")" = "ORIGINAL" ]; then
  pass "write_cmd — silent-but-successful producer → rc 70, target untouched"
else
  fail "write_cmd — empty output: rc=$rc (want 70), content '$(cat "$target")'"
fi

# Missing target is a caller error, like every sibling function.
atomic_state_write_cmd "" printf x 2>/dev/null
rc=$?
if [ "$rc" -eq 64 ]; then
  pass "write_cmd — missing target → rc 64"
else
  fail "write_cmd — missing target: rc=$rc (want 64)"
fi

# --- Error paths that had no coverage at all -------------------------------

# An unwritable parent directory is a tmp-write failure (66), and write_cmd must
# report it as such rather than blaming the producer (75).
rodir="$TMPDIR/ro"
mkdir -p "$rodir"
printf 'KEEP\n' > "$rodir/x.md"
chmod 500 "$rodir"
printf 'NEW\n' | atomic_state_write "$rodir/x.md" 2>/dev/null
rc_w=$?
atomic_state_write_cmd "$rodir/x.md" printf 'NEW\n' 2>/dev/null
rc_c=$?
chmod 700 "$rodir"
if [ "$rc_w" -eq 66 ] && [ "$rc_c" -eq 66 ] && [ "$(cat "$rodir/x.md")" = "KEEP" ]; then
  pass "write / write_cmd — unwritable directory reports rc 66, not a producer error"
else
  fail "unwritable dir: write rc=$rc_w write_cmd rc=$rc_c (both want 66)"
fi

# A parent path that cannot be created is rc 65.
printf 'x\n' > "$TMPDIR/afile"
printf 'y\n' | atomic_state_write "$TMPDIR/afile/nested/state.md" 2>/dev/null
rc=$?
if [ "$rc" -eq 65 ]; then
  pass "atomic_state_write — unmakeable parent directory → rc 65"
else
  fail "unmakeable parent: rc=$rc (want 65)"
fi

# A target shadowed by a DIRECTORY used to return 0, write nothing, and strand
# the tmp file inside it.
mkdir -p "$TMPDIR/dirtarget.md"
printf 'content\n' | atomic_state_write "$TMPDIR/dirtarget.md" 2>/dev/null
rc=$?
strays=$(find "$TMPDIR/dirtarget.md" -type f | wc -l | tr -d ' ')
if [ "$rc" -eq 67 ] && [ "$strays" -eq 0 ]; then
  pass "atomic_state_write — directory target → rc 67, nothing left behind"
else
  fail "directory target: rc=$rc (want 67), stray files=$strays"
fi

# An unwritable append target is rc 69.
touch "$TMPDIR/ro.jsonl"
chmod 400 "$TMPDIR/ro.jsonl"
printf '%s' '{"a":1}' | atomic_state_append "$TMPDIR/ro.jsonl" 2>/dev/null
rc=$?
chmod 600 "$TMPDIR/ro.jsonl"
if [ "$rc" -eq 69 ]; then
  pass "atomic_state_append — unwritable target → rc 69"
else
  fail "unwritable append target: rc=$rc (want 69)"
fi

# --- atomic_state_append: the ceiling -------------------------------------

# The ceiling counts BYTES. 3000 two-byte characters are under the 4094-character
# mark but over the byte ceiling, which is the whole reason the code uses wc -c.
target="$TMPDIR/mb.jsonl"
mb_line="$(awk 'BEGIN{for(i=0;i<3000;i++) printf "\303\251"}')"
printf '%s' "$mb_line" | atomic_state_append "$target" 2>/dev/null
rc=$?
if [ "$rc" -eq 68 ] && [ ! -s "$target" ]; then
  pass "atomic_state_append — multibyte line over the BYTE ceiling → rc 68"
else
  fail "multibyte ceiling: rc=$rc (want 68), bytes=$(wc -c < "$target" 2>/dev/null)"
fi

# A hostile GENIRO_APPEND_MAX_BYTES must fall back to the default, including an
# all-digit value too large for shell arithmetic — that one silently disabled the
# ceiling entirely, appending 50 KB.
ceiling_ok=1
for bad in "abc" "-5" "0" "" "999999999999999999999999" "4094abc"; do
  out=$(GENIRO_APPEND_MAX_BYTES="$bad" bash -c '
    source "'"$REPO_ROOT"'/lib/atomic-state-write.sh" 2>/dev/null
    head -c 50000 /dev/zero | tr "\0" a | atomic_state_append "'"$TMPDIR"'/ceil.jsonl" 2>/dev/null
    echo $?' 2>/dev/null | tail -1)
  if [ "$out" != "68" ]; then
    ceiling_ok=0
    echo "  (GENIRO_APPEND_MAX_BYTES='$bad' gave rc=$out, want 68)" >&2
  fi
  rm -f "$TMPDIR/ceil.jsonl"
done
if [ "$ceiling_ok" -eq 1 ]; then
  pass "atomic_state_append — every hostile byte-ceiling override falls back to the default"
else
  fail "atomic_state_append — a hostile GENIRO_APPEND_MAX_BYTES disabled the ceiling"
fi

# --- Signals, traps, and tmp naming ---------------------------------------

# The helpers must not remove a trap the caller installed. They used to clear
# INT/TERM unconditionally, so a caller's own cleanup silently disappeared.
# Assert the dispositions are UNCHANGED rather than equal to a literal: a suite
# run as a background job inherits SIGINT as SIG_IGN, and POSIX forbids trapping
# a signal ignored on entry, so requiring a specific handler is environment-
# dependent. "Same before and after" is the actual property.
trap_diff=$(bash -c '
  source "'"$REPO_ROOT"'/lib/atomic-state-write.sh"
  trap "echo CALLER" INT 2>/dev/null
  trap "echo CALLER" TERM 2>/dev/null
  before="$(trap -p INT; trap -p TERM)"
  atomic_state_write "'"$TMPDIR"'/trap.md" <<EOF
hello
EOF
  printf -- "---\nphase: a\n---\n" > "'"$TMPDIR"'/trap2.md"
  atomic_state_set_field "'"$TMPDIR"'/trap2.md" phase Z
  atomic_state_edit "'"$TMPDIR"'/trap2.md" "phase: Z" "phase: Y"
  atomic_state_write_cmd "'"$TMPDIR"'/trap3.md" printf "x\n"
  after="$(trap -p INT; trap -p TERM)"
  [ "$before" = "$after" ] && echo SAME || { echo "BEFORE[$before] AFTER[$after]"; }')
if [ "$trap_diff" = "SAME" ]; then
  pass "helpers — the caller's INT/TERM trap dispositions are unchanged by every helper"
else
  fail "helpers — caller traps altered: $trap_diff"
fi

# Two calls must never compute the same tmp path. `$$` is the PARENT pid inside a
# subshell, so backgrounded writers to one target shared a tmp and could splice
# their payloads into the committed file.
n1=$(_atomic_state_mktemp "$TMPDIR/uniq.md")
n2=$(_atomic_state_mktemp "$TMPDIR/uniq.md")
rm -f "$n1" "$n2"
if [ -n "$n1" ] && [ -n "$n2" ] && [ "$n1" != "$n2" ]; then
  pass "tmp naming — two calls for one target get distinct paths"
else
  fail "tmp naming — collision: '$n1' vs '$n2'"
fi

# A hostname carrying path characters must not break the write.
out=$(HOSTNAME='bad/host name' bash -c '
  source "'"$REPO_ROOT"'/lib/atomic-state-write.sh"
  printf "ok\n" | atomic_state_write "'"$TMPDIR"'/host.md"; echo $?' | tail -1)
if [ "$out" = "0" ] && [ "$(cat "$TMPDIR/host.md" 2>/dev/null)" = "ok" ]; then
  pass "tmp naming — a hostname with path characters is sanitized"
else
  fail "tmp naming — hostile HOSTNAME: rc=$out"
fi

# --- Permissions and identity ---------------------------------------------

# A deliberately restricted state file must not be widened by an edit.
target="$TMPDIR/perm.md"
printf -- '---\nphase: a\n---\n' > "$target"
chmod 600 "$target"
atomic_state_set_field "$target" "phase" "Z"
mode=$(stat -f '%Lp' "$target" 2>/dev/null || stat -c '%a' "$target" 2>/dev/null)
if [ "$mode" = "600" ]; then
  pass "editors — the target's permissions are carried across the rewrite"
else
  fail "editors — mode changed to $mode (want 600)"
fi

# A rename failure must name the function the caller actually called.
target="$TMPDIR/msg.md"
printf -- '---\nphase: a\n---\n' > "$target"
mkdir -p "$TMPDIR/msgdir.md"
msg=$(printf 'x\n' | atomic_state_write_cmd "$TMPDIR/msgdir.md" printf 'x\n' 2>&1 >/dev/null | head -1)
case "$msg" in
  atomic_state_write_cmd:*) pass "errors — a failure names the function that was called" ;;
  *) fail "errors — message misattributed: [$msg]" ;;
esac

# --- checksum interaction --------------------------------------------------

# A file sealing its body with checksum: must not have that body edited silently —
# validate_state_file would then reject the file the helper reported writing.
target="$TMPDIR/sum.md"
printf -- '---\ntier: T1.5\nchecksum: deadbeef\n---\n\n## Log\n- one\n' > "$target"
before="$(cat "$target")"
atomic_state_edit "$target" "- one" "- two" 2>/dev/null
rc=$?
if [ "$rc" -eq 76 ] && [ "$(cat "$target")" = "$before" ]; then
  pass "atomic_state_edit — refuses a body edit that would stale a checksum (rc 76)"
else
  fail "checksum body edit: rc=$rc (want 76), file:
$(cat "$target")"
fi

# The same file's FRONTMATTER is still editable — the seal covers the body only.
atomic_state_edit "$target" "tier: T1.5" "tier: T2"
rc=$?
if [ "$rc" -eq 0 ] && grep -qx 'tier: T2' "$target"; then
  pass "atomic_state_edit — a frontmatter edit on a checksummed file is allowed"
else
  fail "checksum frontmatter edit: rc=$rc"
fi

# --- Bytes the editors cannot round-trip ------------------------------------

# NUL and 0x04 cannot survive command substitution / the awk record separator.
# Both used to shorten the file silently at rc 0.
target="$TMPDIR/nul.md"
printf -- '---\nphase: a\n---\nbo\000dy\n' > "$target"
before_bytes=$(wc -c < "$target" | tr -d ' ')
atomic_state_set_field "$target" "phase" "Z" 2>/dev/null
rc_s=$?
atomic_state_edit "$target" "bo" "BO" 2>/dev/null
rc_e=$?
after_bytes=$(wc -c < "$target" | tr -d ' ')
if [ "$rc_s" -eq 73 ] && [ "$rc_e" -eq 73 ] && [ "$before_bytes" = "$after_bytes" ]; then
  pass "editors — a NUL-bearing file is refused (rc 73), not silently shortened"
else
  fail "NUL file: set_field rc=$rc_s edit rc=$rc_e, bytes $before_bytes -> $after_bytes"
fi

# --- Scale -----------------------------------------------------------------

# The editors were quadratic: 21 s for one 200 KB replacement, past the default
# tool timeout, whose SIGTERM then landed mid-write. Assert a real bound.
target="$TMPDIR/big.md"
head -c 204800 /dev/zero | tr '\0' a > "$target"
printf '\nUNIQUE_ANCHOR\n' >> "$target"
start=$(date +%s)
atomic_state_edit "$target" "UNIQUE_ANCHOR" "REPLACED"
rc=$?
elapsed=$(( $(date +%s) - start ))
if [ "$rc" -eq 0 ] && [ "$elapsed" -le 5 ] && grep -q REPLACED "$target"; then
  pass "atomic_state_edit — a 200 KB file edits in ${elapsed}s (bound: 5s)"
else
  fail "atomic_state_edit — 200 KB took ${elapsed}s, rc=$rc"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"

# An expected total: deleting a case would otherwise report a smaller green run.
# Update this number in the same commit that adds or removes a case.
EXPECTED_TESTS=65
if [ "$TESTS_RUN" -ne "$EXPECTED_TESTS" ]; then
  echo "FAIL: expected $EXPECTED_TESTS assertions, ran $TESTS_RUN — a case was added or dropped without updating EXPECTED_TESTS" >&2
  exit 1
fi
[ "$TESTS_FAILED" -eq 0 ]
