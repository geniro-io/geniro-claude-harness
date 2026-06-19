#!/usr/bin/env bash
# Smoke test for lib/hash.sh — the portable SHA-256 helper used by
# emit-learning dedup-key derivation, load-semantic fingerprinting, and the
# session-start auto-archive hash marker.
#
# Stock macOS ships `shasum` but NOT `sha256sum`; Linux ships `sha256sum`.
# The helper routes to whichever is present so a bare `sha256sum` does not
# fail silently (empty digest mistaken for a real hash). This suite pins the
# digest of a known input, idempotency, and double-source safety so a
# regression in the fallback fails the suite instead of silently corrupting
# every downstream hash.
#
# Run: bash tests/memory/hash.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/hash.sh"

# SHA-256 of zero bytes — the universally-published constant. Both `sha256sum`
# and `shasum -a 256` must agree on it, so it is the tightest cross-tool pin.
EMPTY_SHA256="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# --- 1. Known-input digest: empty file hashes to the published constant.
empty_file="$TMPDIR_BASE/empty"
: > "$empty_file"
got_file=$(_geniro_sha256 "$empty_file" | awk '{print $1}')
if [ "$got_file" = "$EMPTY_SHA256" ]; then
  pass "_geniro_sha256 on an empty file matches the known SHA-256 constant"
else
  fail "_geniro_sha256 empty file — expected '$EMPTY_SHA256', got '$got_file'"
fi

# --- 2. Digest is a 64-hex-character string (shape, not just value).
case "$got_file" in
  [0-9a-f]*) :;;
  *) got_file="";;
esac
if [ "${#got_file}" -eq 64 ]; then
  pass "_geniro_sha256 emits a 64-char lowercase-hex digest"
else
  fail "_geniro_sha256 digest is not 64 hex chars (len=${#got_file})"
fi

# --- 3. Stdin form agrees with the file form on the same (empty) input.
got_stdin=$(printf '' | _geniro_sha256 | awk '{print $1}')
if [ "$got_stdin" = "$EMPTY_SHA256" ]; then
  pass "_geniro_sha256 stdin form matches the file form (empty input)"
else
  fail "_geniro_sha256 stdin form — expected '$EMPTY_SHA256', got '$got_stdin'"
fi

# --- 4. Fixed non-empty string hashes to its known constant.
# sha256("abc") is a standard test vector.
ABC_SHA256="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
got_abc=$(printf 'abc' | _geniro_sha256 | awk '{print $1}')
if [ "$got_abc" = "$ABC_SHA256" ]; then
  pass "_geniro_sha256 of the string 'abc' matches the known SHA-256 vector"
else
  fail "_geniro_sha256 'abc' — expected '$ABC_SHA256', got '$got_abc'"
fi

# --- 5. Idempotent: the same input always yields the same digest.
again=$(printf 'abc' | _geniro_sha256 | awk '{print $1}')
if [ "$got_abc" = "$again" ]; then
  pass "_geniro_sha256 is idempotent (same input → same digest)"
else
  fail "_geniro_sha256 not idempotent: '$got_abc' vs '$again'"
fi

# --- 6. Double-sourcing under `set -e` does not crash (helpers get re-sourced
#        across the codebase — a redefinition or a stray top-level command
#        would abort the caller).
if bash -c "set -e; source '$REPO_ROOT/lib/hash.sh'; source '$REPO_ROOT/lib/hash.sh'; _geniro_sha256 /dev/null >/dev/null"; then
  pass "double-sourcing lib/hash.sh under set -e does not crash"
else
  fail "double-sourcing lib/hash.sh under set -e crashed"
fi

# --- 7. Sourcing under zsh defines the function (the Bash tool runs under zsh
#        in some environments; skip cleanly when zsh is absent).
if command -v zsh >/dev/null 2>&1; then
  if zsh -c "source '$REPO_ROOT/lib/hash.sh' && command -v _geniro_sha256" >/dev/null 2>&1; then
    pass "zsh: source lib/hash.sh defines _geniro_sha256"
  else
    fail "zsh: source lib/hash.sh did not define _geniro_sha256"
  fi
else
  echo "SKIP: zsh not available — zsh-source check skipped."
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
