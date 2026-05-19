#!/usr/bin/env bash
# Smoke test for skills/_shared/query-learnings.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

SANDBOX_DIR=""
new_sandbox() {
  SANDBOX_DIR="$TMPDIR_BASE/$(date +%s%N)-$RANDOM"
  mkdir -p "$SANDBOX_DIR/.geniro/knowledge"
  cd "$SANDBOX_DIR" || return 1
  git init -q
  # shellcheck disable=SC1091
  source "$REPO_ROOT/skills/_shared/query-learnings.sh"
}

# Seed log with the canonical fixture.
seed_log() {
  cat > "$SANDBOX_DIR/.geniro/knowledge/learnings.jsonl" <<'EOF'
{"ts":"2026-05-01T10:00:00Z","producer":"/debug","scope":"src/foo","summary":"bug A","tags":["bug","react"],"dedup_key":"k1","type":"diagnosis","trust":"verified"}
{"ts":"2026-05-02T10:00:00Z","producer":"/debug","scope":"src/bar","summary":"bug B","tags":["bug","node"],"dedup_key":"k2","type":"diagnosis","trust":"verified"}
{"ts":"2026-05-03T10:00:00Z","producer":"/plan","scope":"global","summary":"decision X","tags":["arch"],"dedup_key":"k3","type":"decision","trust":"verified"}
{"ts":"2026-05-04T10:00:00Z","producer":"/debug","scope":"src/foo","summary":"bug A revised","tags":["bug","react"],"dedup_key":"k4","supersedes":"k1","type":"diagnosis","trust":"verified"}
{"ts":"2026-05-05T10:00:00Z","producer":"/investigate","scope":"global","summary":"web finding","tags":["info"],"dedup_key":"k5","trust":"retrieved"}
{"ts":"2026-05-06T10:00:00Z","producer":"/debug","scope":"src/old","summary":"deprecated entry","tags":["bug"],"dedup_key":"k6","deprecated":true}
{"ts":"2026-05-07T10:00:00Z","producer":"/debug","scope":"src/baz","summary":"low trust guess","tags":["bug"],"dedup_key":"k7","trust":"inferred"}
EOF
}

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Collect dedup_keys from query output, sorted for stable comparison.
keys() {
  jq -r .dedup_key | LC_ALL=C sort | tr '\n' ',' | sed 's/,$//'
}

# Missing log → empty
new_sandbox
out=$(query_learnings)
if [ -z "$out" ]; then
  pass "no log file → empty output, rc=0"
else
  fail "expected empty output for missing log; got '$out'"
fi

# Empty log → empty
new_sandbox
: > .geniro/knowledge/learnings.jsonl
out=$(query_learnings)
if [ -z "$out" ]; then
  pass "empty log → empty output"
else
  fail "expected empty for empty log; got '$out'"
fi

# Default: supersede + deprecated excluded.
new_sandbox; seed_log
got=$(query_learnings | keys)
want="k2,k3,k4,k5,k7"
if [ "$got" = "$want" ]; then
  pass "default filters exclude superseded (k1) AND deprecated (k6)"
else
  fail "default — got '$got' want '$want'"
fi

# --type diagnosis (k1 superseded, k2 + k4)
new_sandbox; seed_log
got=$(query_learnings --type diagnosis | keys)
want="k2,k4"
if [ "$got" = "$want" ]; then
  pass "--type diagnosis filters correctly"
else
  fail "--type — got '$got' want '$want'"
fi

# --tag react (k1 superseded, k4 remains)
new_sandbox; seed_log
got=$(query_learnings --tag react | keys)
want="k4"
if [ "$got" = "$want" ]; then
  pass "--tag matches array membership"
else
  fail "--tag — got '$got' want '$want'"
fi

# --scope global (k3 + k5)
new_sandbox; seed_log
got=$(query_learnings --scope global | keys)
want="k3,k5"
if [ "$got" = "$want" ]; then
  pass "--scope exact match"
else
  fail "--scope — got '$got' want '$want'"
fi

# Combined --type + --tag
new_sandbox; seed_log
got=$(query_learnings --type diagnosis --tag node | keys)
want="k2"
if [ "$got" = "$want" ]; then
  pass "--type AND --tag combine correctly"
else
  fail "combo — got '$got' want '$want'"
fi

# --min-trust verified
new_sandbox; seed_log
got=$(query_learnings --min-trust verified | keys)
want="k2,k3,k4"
if [ "$got" = "$want" ]; then
  pass "--min-trust verified — excludes retrieved + inferred"
else
  fail "min-trust verified — got '$got' want '$want'"
fi

# --min-trust retrieved
new_sandbox; seed_log
got=$(query_learnings --min-trust retrieved | keys)
want="k2,k3,k4,k5"
if [ "$got" = "$want" ]; then
  pass "--min-trust retrieved — verified + retrieved"
else
  fail "min-trust retrieved — got '$got' want '$want'"
fi

# --min-trust inferred
new_sandbox; seed_log
got=$(query_learnings --min-trust inferred | keys)
want="k2,k3,k4,k5,k7"
if [ "$got" = "$want" ]; then
  pass "--min-trust inferred — all (matches default)"
else
  fail "min-trust inferred — got '$got' want '$want'"
fi

# --include-superseded (adds k1 back)
new_sandbox; seed_log
got=$(query_learnings --include-superseded | keys)
want="k1,k2,k3,k4,k5,k7"
if [ "$got" = "$want" ]; then
  pass "--include-superseded restores k1"
else
  fail "--include-superseded — got '$got' want '$want'"
fi

# --include-deprecated (adds k6)
new_sandbox; seed_log
got=$(query_learnings --include-deprecated | keys)
want="k2,k3,k4,k5,k6,k7"
if [ "$got" = "$want" ]; then
  pass "--include-deprecated restores k6"
else
  fail "--include-deprecated — got '$got' want '$want'"
fi

# --include-archive merges archive files
new_sandbox; seed_log
mkdir -p .geniro/knowledge/archive
cat > .geniro/knowledge/archive/learnings-2025-Q4.jsonl <<'EOF'
{"ts":"2025-12-01T00:00:00Z","producer":"/debug","scope":"src/old/x","summary":"cold","tags":["bug"],"dedup_key":"a1","type":"diagnosis","trust":"verified"}
EOF
got=$(query_learnings --include-archive | keys)
want="a1,k2,k3,k4,k5,k7"
if [ "$got" = "$want" ]; then
  pass "--include-archive merges archive entries"
else
  fail "--include-archive — got '$got' want '$want'"
fi

# Without --include-archive: archive entries NOT visible.
new_sandbox; seed_log
mkdir -p .geniro/knowledge/archive
cat > .geniro/knowledge/archive/learnings-2025-Q4.jsonl <<'EOF'
{"ts":"2025-12-01T00:00:00Z","producer":"/debug","scope":"src/old/x","summary":"cold","tags":["bug"],"dedup_key":"a1","type":"diagnosis","trust":"verified"}
EOF
got=$(query_learnings | keys)
if echo "$got" | grep -qv 'a1'; then
  pass "default (no --include-archive) skips archive entries"
else
  fail "archive leaked into default query: $got"
fi

# --limit
new_sandbox; seed_log
n=$(query_learnings --limit 2 | wc -l)
if [ "$n" -eq 2 ]; then
  pass "--limit 2 caps output"
else
  fail "--limit 2 should yield 2 lines; got $n"
fi

# Unknown flag
new_sandbox; seed_log
set +e
query_learnings --bogus x >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "unknown flag → rc=64"
else
  fail "unknown flag should rc=64; got $rc"
fi

# Invalid --min-trust value
new_sandbox; seed_log
set +e
query_learnings --min-trust foo >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "invalid --min-trust value → rc=64"
else
  fail "bad --min-trust should rc=64; got $rc"
fi

# Trust handling: missing trust field treated as inferred.
new_sandbox
cat > .geniro/knowledge/learnings.jsonl <<'EOF'
{"ts":"2026-05-01T10:00:00Z","producer":"/debug","scope":"x","summary":"y","tags":["bug"],"dedup_key":"q1"}
EOF
got=$(query_learnings --min-trust verified | wc -l)
if [ "$got" -eq 0 ]; then
  pass "missing trust field excluded under --min-trust verified"
else
  fail "expected 0 results with missing-trust under verified; got $got"
fi
got=$(query_learnings --min-trust inferred | wc -l)
if [ "$got" -eq 1 ]; then
  pass "missing trust field counts as inferred under --min-trust inferred"
else
  fail "expected 1 result; got $got"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
