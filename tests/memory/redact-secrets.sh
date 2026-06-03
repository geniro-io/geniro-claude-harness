#!/usr/bin/env bash
# Smoke test for lib/redact-secrets.sh
#
# Run: bash tests/memory/redact-secrets.sh
# Exits non-zero on any failure.
#
# Plugin-developer tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Run all tests inside an isolated temp git repo so that `git rev-parse` resolves
# to a known root for audit-log placement, and .geniro/safety.json doesn't leak
# from neighbouring tests.
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# Per-test sandbox. Sets the global $SANDBOX_DIR (NOT echoed) so callers can
# use both the path AND the side-effects (cwd, sourced helper) — `$(new_sandbox)`
# would force a subshell and lose both.
SANDBOX_DIR=""
new_sandbox() {
  SANDBOX_DIR="$(mktemp -d "$TMPDIR_BASE/sandbox.XXXXXXXXXX")"
  mkdir -p "$SANDBOX_DIR/.geniro"
  cd "$SANDBOX_DIR" || return 1
  git init -q
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/redact-secrets.sh"
}

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

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [ "$got" = "$want" ]; then
    pass "$label"
  else
    fail "$label — got: '$got' | want: '$want'"
  fi
}

# Helper: redact + return stdout
redact() {
  printf '%s' "$1" | redact_secrets test-producer test-field test-key
}

# ---------------------------------------------------------------------------
# Per-pattern sanity
# ---------------------------------------------------------------------------

new_sandbox
assert_eq "$(redact 'Header: eyJhbGc.eyJzdWI.signature_part trailing')" \
          'Header: [REDACTED:jwt] trailing' \
          'jwt — single match in middle of string'

new_sandbox
assert_eq "$(redact 'AKIAIOSFODNN7EXAMPLE')" \
          '[REDACTED:aws-key]' \
          'aws-key — bare 20-char key'

new_sandbox
assert_eq "$(redact 'aws_secret_access_key = AbCdEfGhIjKlMnOpQrStUvWxYz0123456789ABCD')" \
          'aws_secret_access_key=[REDACTED:aws-secret]' \
          'aws-secret — with whitespace around ='

new_sandbox
assert_eq "$(redact 'sk-ant-api03-abc123')" \
          '[REDACTED:api-key:anthropic]' \
          'api-key:sk-ant — provider-name label (not nested)'

new_sandbox
assert_eq "$(redact 'sk-proj-9C0fAbCdEfGhIjKlMnOp')" \
          '[REDACTED:api-key:openai-or-similar]' \
          'api-key:sk — bare OpenAI-style key'

new_sandbox
assert_eq "$(redact 'pk_live_51AbCdEfGhIjKlMnOpQrStUv')" \
          '[REDACTED:api-key:stripe-live]' \
          'api-key:pk_live'

new_sandbox
assert_eq "$(redact 'pk_test_51XyZAbCdEfGhIjKlMnOp')" \
          '[REDACTED:api-key:stripe-test]' \
          'api-key:pk_test'

new_sandbox
assert_eq "$(redact 'ghp_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AB')" \
          '[REDACTED:api-key:github]' \
          'api-key:ghp'

new_sandbox
assert_eq "$(redact 'xoxb-12345-67890-ABCDEFGHIJKLMNOPQRSTUVWX')" \
          '[REDACTED:api-key:slack-bot]' \
          'api-key:xoxb'

new_sandbox
assert_eq "$(redact 'Authorization: Bearer abc.def_123-xyz')" \
          'Authorization: Bearer [REDACTED:bearer]' \
          'bearer — Authorization header'

new_sandbox
assert_eq "$(redact 'connect to https://user:pass@host.example.com/path')" \
          'connect to https://[REDACTED:url-cred]@host.example.com/path' \
          'url-cred — preserves scheme and host'

new_sandbox
assert_eq "$(redact 'connect to http://u:p@h/')" \
          'connect to http://[REDACTED:url-cred]@h/' \
          'url-cred — http scheme preserved via backref'

new_sandbox
pem=$'-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA...\n-----END RSA PRIVATE KEY-----'
assert_eq "$(redact "$pem")" \
          '[REDACTED:private-key]' \
          'private-key — multi-line PEM block'

new_sandbox
assert_eq "$(redact '')" \
          '' \
          'empty input → empty output (no error)'

new_sandbox
assert_eq "$(redact 'no secrets here just plain text')" \
          'no secrets here just plain text' \
          'no-match input passes through unchanged'

# ---------------------------------------------------------------------------
# Order dependency: sk-ant- must beat sk-
# ---------------------------------------------------------------------------

# Verify the sk-ant- key isn't re-redacted as if it were a generic sk- key.
# Old greedy-strip labels would produce nested gibberish; provider-name labels
# avoid this.
new_sandbox
out="$(redact 'sk-ant-api03-AbCd-EfGh')"
case "$out" in
  *anthropic*) pass "sk-ant precedence — label contains 'anthropic'" ;;
  *) fail "sk-ant precedence — got '$out'" ;;
esac

# No nested REDACTED label.
case "$out" in
  *'[REDACTED:'*'[REDACTED'*) fail "sk-ant nested label (got '$out')" ;;
  *) pass "sk-ant precedence — no nested REDACTED label" ;;
esac

# ---------------------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------------------

new_sandbox
sandbox="$SANDBOX_DIR"
redact 'Header: eyJhbGc.eyJzdWI.signature_part' >/dev/null
log="$sandbox/.geniro/knowledge/.redaction-log.jsonl"
if [ ! -f "$log" ]; then
  fail "audit log file should exist after a redaction"
else
  pass "audit log file created"
  # Exactly one line for one fired pattern (jwt)
  lines=$(wc -l < "$log")
  if [ "$lines" -eq 1 ]; then
    pass "audit log has exactly 1 line for 1 fired pattern"
  else
    fail "audit log line count: got $lines, want 1"
  fi
  # Validate JSONL shape
  if jq -e '.pattern == "jwt" and .producer == "test-producer" and .field == "test-field" and .entry_dedup_key == "test-key" and (.redacted_chars | type == "number")' "$log" >/dev/null 2>&1; then
    pass "audit log JSONL has correct shape"
  else
    fail "audit log JSONL shape mismatch — content: $(cat "$log")"
  fi
fi

# Multiple patterns → multiple audit lines
new_sandbox
sandbox="$SANDBOX_DIR"
redact 'Auth: Bearer abc.def & token AKIAIOSFODNN7EXAMPLE' >/dev/null
log="$sandbox/.geniro/knowledge/.redaction-log.jsonl"
lines=$(wc -l < "$log" 2>/dev/null || echo 0)
if [ "$lines" -eq 2 ]; then
  pass "audit log has 2 lines for 2 fired patterns (bearer + aws-key)"
else
  fail "audit log line count: got $lines, want 2"
fi

# audit_log_enabled: false → no log file
new_sandbox
sandbox="$SANDBOX_DIR"
cat > .geniro/safety.json <<EOF
{ "redaction": { "audit_log_enabled": false } }
EOF
redact 'Header: eyJhbGc.eyJzdWI.signature_part' >/dev/null
log="$sandbox/.geniro/knowledge/.redaction-log.jsonl"
if [ ! -f "$log" ]; then
  pass "audit_log_enabled=false suppresses log file creation"
else
  fail "audit_log_enabled=false should have suppressed log; found: $(cat "$log")"
fi

# ---------------------------------------------------------------------------
# safety.json knobs
# ---------------------------------------------------------------------------

new_sandbox
sandbox="$SANDBOX_DIR"
cat > .geniro/safety.json <<EOF
{ "redaction": { "ignore_patterns": ["jwt"] } }
EOF
out="$(redact 'Header: eyJhbGc.eyJzdWI.signature_part trailing')"
if [ "$out" = 'Header: eyJhbGc.eyJzdWI.signature_part trailing' ]; then
  pass "ignore_patterns=['jwt'] skips the jwt pattern"
else
  fail "ignore_patterns ignored — got '$out'"
fi

new_sandbox
sandbox="$SANDBOX_DIR"
cat > .geniro/safety.json <<EOF
{ "redaction": { "additional_patterns": [
  { "name": "internal-token", "regex": "INT-[A-Z0-9]{8}", "replacement": "[REDACTED:internal]" }
] } }
EOF
assert_eq "$(redact 'token: INT-ABCD1234 end')" \
          'token: [REDACTED:internal] end' \
          'additional_patterns — custom INT- pattern fires'

new_sandbox
sandbox="$SANDBOX_DIR"
cat > .geniro/safety.json <<EOF
{ "redaction": { "additional_patterns": [
  { "name": "custom-pat", "regex": "ZZ-[A-Z]+", "replacement": "[REDACTED:custom]" }
] } }
EOF
redact 'prefix ZZ-ABC suffix' >/dev/null
log="$sandbox/.geniro/knowledge/.redaction-log.jsonl"
if jq -e 'select(.pattern == "custom-pat")' "$log" >/dev/null 2>&1; then
  pass "additional_patterns — audit log records custom pattern name"
else
  fail "additional_patterns — audit log missing 'custom-pat' entry"
fi

# ---------------------------------------------------------------------------
# Composition: multiple patterns in one input
# ---------------------------------------------------------------------------

new_sandbox
mixed='url=https://user:pass@h/, key=AKIAIOSFODNN7EXAMPLE, jwt=eyJa.bcD.eFg'
out="$(redact "$mixed")"
case "$out" in
  *'[REDACTED:url-cred]'*'[REDACTED:aws-key]'*'[REDACTED:jwt]'*)
    pass "mixed input — all three patterns redacted in order"
    ;;
  *) fail "mixed input — got '$out'" ;;
esac

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
