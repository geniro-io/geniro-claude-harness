#!/usr/bin/env bash
# Smoke test for lib/load-semantic.sh

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
  source "$REPO_ROOT/lib/load-semantic.sh"
}

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# ---------------------------------------------------------------------------
# load_semantic
# ---------------------------------------------------------------------------

# Missing L3 files → empty output, no error.
new_sandbox
out=$(load_semantic --quiet)
if [ -z "$out" ]; then
  pass "missing L3 files → empty stdout"
else
  fail "expected empty stdout; got '$out'"
fi

# Default load: _project + _CODEBASE_MAP
new_sandbox
echo '# Project' > .geniro/planning/_project.md
echo '# Map' > .geniro/planning/_CODEBASE_MAP.md
out=$(load_semantic --quiet)
proj_count=$(echo "$out" | grep -c '=== file: .geniro/planning/_project.md ===' || true)
map_count=$(echo "$out" | grep -c '=== file: .geniro/planning/_CODEBASE_MAP.md ===' || true)
if [ "$proj_count" = "1" ] && [ "$map_count" = "1" ]; then
  pass "default load includes _project.md AND _CODEBASE_MAP.md with file headers"
else
  fail "default load missing files (proj=$proj_count map=$map_count)"
fi

# --extras with bare name (no leading underscore)
new_sandbox
echo 'arch' > .geniro/planning/_architecture.md
out=$(load_semantic --quiet --extras "architecture")
if echo "$out" | grep -q '=== file: .geniro/planning/_architecture.md ==='; then
  pass "--extras 'architecture' resolves to _architecture.md"
else
  fail "--extras bare name didn't resolve; got: $out"
fi

# --extras with leading underscore
new_sandbox
echo 'feat' > .geniro/planning/_FEATURES.md
out=$(load_semantic --quiet --extras "_FEATURES")
if echo "$out" | grep -q '=== file: .geniro/planning/_FEATURES.md ==='; then
  pass "--extras '_FEATURES' resolves to _FEATURES.md"
else
  fail "--extras with leading _ didn't resolve"
fi

# --extras multiple
new_sandbox
echo 'a' > .geniro/planning/_architecture.md
echo 'f' > .geniro/planning/_FEATURES.md
out=$(load_semantic --quiet --extras "_architecture _FEATURES")
if echo "$out" | grep -q '=== file: .geniro/planning/_architecture.md ===' \
   && echo "$out" | grep -q '=== file: .geniro/planning/_FEATURES.md ==='; then
  pass "--extras multiple files loaded"
else
  fail "--extras multiple failed; got: $out"
fi

# Missing extras file is silently skipped (no error)
new_sandbox
set +e
out=$(load_semantic --quiet --extras "_DOES_NOT_EXIST" 2>/dev/null)
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "missing --extras file is silently skipped (rc=0, empty)"
else
  fail "missing extras file: rc=$rc out='$out'"
fi

# --extras must not glob-expand against cwd. Regression: previous code used
# `for e in $extras` which word-splits AND glob-expands. A literal token
# like `_focus-*` would match files in PWD and silently load wrong ones.
new_sandbox
# Plant files in cwd that would match a glob expansion of `_focus-*`
touch _focus-OOPS.md _focus-WRONG.md
# Plant the actual L3 file we want loaded
echo 'real focus content' > .geniro/planning/_focus-auth.md
out=$(load_semantic --quiet --extras "_focus-*" 2>/dev/null)
if echo "$out" | grep -q 'OOPS\|WRONG'; then
  fail "--extras glob-expanded against cwd (loaded $(echo "$out" | grep -oE 'OOPS|WRONG'))"
else
  pass "--extras does not glob-expand against cwd"
fi

# Unknown flag → rc=64
new_sandbox
set +e
load_semantic --bogus x >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "load_semantic unknown flag → rc=64"
else
  fail "load_semantic unknown flag should rc=64; got $rc"
fi

# Trailing --extras (missing operand) → rc=64, not a parse-loop spin
# (`shift 2` with $#=1 no-ops, so an unguarded arm loops on the flag forever).
new_sandbox
set +e
load_semantic --extras >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "trailing --extras (missing operand) → rc=64"
else
  fail "trailing --extras should rc=64; got $rc"
fi

# ---------------------------------------------------------------------------
# update_fingerprint
# ---------------------------------------------------------------------------

# No tracked files exist → stub fingerprint
new_sandbox
update_fingerprint
fp=".geniro/planning/.fingerprint.json"
if [ -f "$fp" ] && [ "$(jq -r '.files | length' "$fp")" = "0" ]; then
  pass "update_fingerprint with zero tracked files writes stub (files: {})"
else
  fail "stub fingerprint missing; content: $(cat "$fp" 2>/dev/null)"
fi

# With explicit paths
new_sandbox
echo '{"name":"foo"}' > package.json
echo '{"target":"es2022"}' > tsconfig.json
update_fingerprint package.json tsconfig.json
pkg_hash=$(jq -r '.files["package.json"]' "$fp")
ts_hash=$(jq -r '.files["tsconfig.json"]' "$fp")
if [[ "$pkg_hash" =~ ^sha256: ]] && [[ "$ts_hash" =~ ^sha256: ]]; then
  pass "update_fingerprint with explicit paths hashes both files"
else
  fail "explicit-path hashes missing: pkg='$pkg_hash' ts='$ts_hash'"
fi

# With no args, picks up default candidates
new_sandbox
echo '{"name":"foo"}' > package.json
echo 'pnpm-lock' > pnpm-lock.yaml
update_fingerprint
if [ -n "$(jq -r '.files["package.json"]' "$fp")" ] \
   && [ -n "$(jq -r '.files["pnpm-lock.yaml"]' "$fp")" ]; then
  pass "update_fingerprint no-args picks up default candidates that exist"
else
  fail "no-args fingerprint missing defaults: $(cat "$fp")"
fi

# Missing file in explicit list is skipped (not an error)
new_sandbox
echo '{"name":"foo"}' > package.json
set +e
update_fingerprint package.json does-not-exist.toml
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -z "$(jq -r '.files["does-not-exist.toml"] // ""' "$fp")" ]; then
  pass "missing path in explicit list is silently skipped"
else
  fail "missing-path handling: rc=$rc fingerprint=$(cat "$fp")"
fi

# ---------------------------------------------------------------------------
# Drift detection
# ---------------------------------------------------------------------------

# No fingerprint → no warning
new_sandbox
err=$(load_semantic 2>&1 >/dev/null)
if [ -z "$err" ]; then
  pass "no .fingerprint.json → no drift warning"
else
  fail "unexpected stderr: $err"
fi

# Fingerprint matches → no warning
new_sandbox
echo '{"name":"foo"}' > package.json
update_fingerprint
err=$(load_semantic 2>&1 >/dev/null)
if [ -z "$err" ]; then
  pass "matching fingerprint → no drift warning"
else
  fail "false-positive drift: $err"
fi

# Fingerprint diverges → warning to stderr
new_sandbox
echo '{"name":"foo"}' > package.json
update_fingerprint
echo '{"name":"changed"}' > package.json
err=$(load_semantic 2>&1 >/dev/null)
if echo "$err" | grep -q 'Project snapshot may be out of date.*package.json'; then
  pass "diverged file → drift warning on stderr"
else
  fail "drift warning missing or wrong; got: '$err'"
fi

# --quiet suppresses drift warning
new_sandbox
echo '{"name":"foo"}' > package.json
update_fingerprint
echo '{"name":"changed"}' > package.json
err=$(load_semantic --quiet 2>&1 >/dev/null)
if [ -z "$err" ]; then
  pass "--quiet suppresses drift warning"
else
  fail "--quiet still warned: '$err'"
fi

# Multiple diverged files are listed together
new_sandbox
echo '{"name":"foo"}' > package.json
echo '{"target":"es2022"}' > tsconfig.json
update_fingerprint package.json tsconfig.json
echo '{"name":"changed"}' > package.json
echo '{"target":"es2024"}' > tsconfig.json
err=$(load_semantic 2>&1 >/dev/null)
if echo "$err" | grep -q 'package.json' && echo "$err" | grep -q 'tsconfig.json'; then
  pass "drift warning lists both diverged files"
else
  fail "diverged list incomplete: '$err'"
fi

# A file referenced in fingerprint but DELETED from disk does NOT warn
# (per spec: missing files are not divergent, just skipped).
new_sandbox
echo '{"name":"foo"}' > package.json
update_fingerprint package.json
rm package.json
err=$(load_semantic 2>&1 >/dev/null)
if [ -z "$err" ]; then
  pass "deleted file (gone from disk) does not warn drift"
else
  fail "deleted-file false positive: '$err'"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
