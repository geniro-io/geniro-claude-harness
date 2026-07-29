#!/usr/bin/env bash
# Smoke test for lib/query-learnings.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

SANDBOX_DIR=""
new_sandbox() {
  SANDBOX_DIR="$(mktemp -d "$TMPDIR_BASE/sandbox.XXXXXXXXXX")"
  mkdir -p "$SANDBOX_DIR/.geniro/knowledge"
  cd "$SANDBOX_DIR" || return 1
  git init -q
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/query-learnings.sh"
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

# Trailing value-taking flag (missing operand) → rc=64, not a parse-loop spin
# (`shift 2` with $#=1 no-ops, so an unguarded arm loops on the flag forever).
new_sandbox; seed_log
set +e
query_learnings --type >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "trailing --type (missing operand) → rc=64"
else
  fail "trailing --type should rc=64; got $rc"
fi

# Bad GENIRO_DECAY_TAU_DAYS must fail LOUD (rc=64 + stderr), not silently
# return an empty result set via the 2>/dev/null-masked jq failure.
new_sandbox; seed_log
set +e
err=$(GENIRO_DECAY_TAU_DAYS="bogus" query_learnings --score-min 0.1 2>&1 >/dev/null)
rc=$?
set -e
if [ "$rc" -eq 64 ] && echo "$err" | grep -q 'GENIRO_DECAY_TAU_DAYS'; then
  pass "non-numeric GENIRO_DECAY_TAU_DAYS fails loud (rc=64 + stderr notice)"
else
  fail "bad tau should rc=64 with stderr notice; rc=$rc err='$err'"
fi

# Zero tau rejected too — recency_decay divides by tau.
new_sandbox; seed_log
set +e
GENIRO_DECAY_TAU_DAYS=0 query_learnings --score-min 0.1 >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "zero GENIRO_DECAY_TAU_DAYS → rc=64 (division-by-zero guard)"
else
  fail "tau=0 should rc=64; got $rc"
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

# Position-aware supersede filter — regression for P0 bug where
# emit_learning auto-injects supersedes=<own_dedup_key> on self-collision,
# and a naive set-membership filter then hides BOTH the new AND old entry.
new_sandbox
cat > .geniro/knowledge/learnings.jsonl <<'EOF'
{"ts":"2026-05-01T10:00:00Z","producer":"/d","scope":"s","summary":"same","tags":["x"],"dedup_key":"selfk","body":"v1"}
{"ts":"2026-05-02T10:00:00Z","producer":"/d","scope":"s","summary":"same","tags":["x"],"dedup_key":"selfk","body":"v2","supersedes":"selfk"}
EOF
out=$(query_learnings | jq -r .body | tr '\n' ',' | sed 's/,$//')
if [ "$out" = "v2" ]; then
  pass "self-supersede chain keeps only the LATEST entry (position-aware)"
else
  fail "self-supersede should keep v2 only; got '$out'"
fi

# Position-aware: a supersede points BACKWARD only. The earlier entry must
# be hidden, the later kept.
new_sandbox
cat > .geniro/knowledge/learnings.jsonl <<'EOF'
{"ts":"2026-05-01T10:00:00Z","producer":"/d","scope":"s","summary":"a","tags":["x"],"dedup_key":"ka"}
{"ts":"2026-05-02T10:00:00Z","producer":"/d","scope":"s","summary":"b","tags":["x"],"dedup_key":"kb","supersedes":"ka"}
EOF
out=$(query_learnings | jq -r .dedup_key | tr '\n' ',' | sed 's/,$//')
if [ "$out" = "kb" ]; then
  pass "supersede with distinct dedup_keys hides predecessor only"
else
  fail "distinct-key supersede should keep kb only; got '$out'"
fi

# Edge case: a supersede appearing BEFORE its target (out-of-order file).
# Position-aware filter should NOT treat the target as superseded.
new_sandbox
cat > .geniro/knowledge/learnings.jsonl <<'EOF'
{"ts":"2026-05-02T10:00:00Z","producer":"/d","scope":"s","summary":"b","tags":["x"],"dedup_key":"kb","supersedes":"ka"}
{"ts":"2026-05-03T10:00:00Z","producer":"/d","scope":"s","summary":"a","tags":["x"],"dedup_key":"ka"}
EOF
out=$(query_learnings | jq -r .dedup_key | LC_ALL=C sort | tr '\n' ',' | sed 's/,$//')
if [ "$out" = "ka,kb" ]; then
  pass "supersede pointing forward (target appears AFTER) does not retroactively hide"
else
  fail "forward-pointing supersede semantics; got '$out'"
fi

# ---- record_access: counter bump + never-deletes guard ----

# Bumps access_count on a matching entry; tolerates a log lacking a trailing newline
# (awk counts the final unterminated record the same way jq -Rc reads it).
new_sandbox
printf '%s\n%s' \
  '{"ts":"2026-05-01T10:00:00Z","producer":"/d","scope":"s","summary":"a","tags":["x"],"dedup_key":"ra1","access_count":0}' \
  '{"ts":"2026-05-02T10:00:00Z","producer":"/d","scope":"s","summary":"b","tags":["x"],"dedup_key":"ra2","access_count":0}' \
  > .geniro/knowledge/learnings.jsonl
set +e; record_access ra1; rc=$?; set -e
cnt=$(jq -Rc 'fromjson? | select(.dedup_key=="ra1") | .access_count' .geniro/knowledge/learnings.jsonl)
lines=$(awk 'NF{c++} END{print c+0}' .geniro/knowledge/learnings.jsonl)
if [ "$rc" -eq 0 ] && [ "$cnt" = "1" ] && [ "$lines" -eq 2 ]; then
  pass "record_access bumps access_count and keeps both lines on a no-trailing-newline log"
else
  fail "record_access valid-log bump; rc=$rc cnt=$cnt lines=$lines (expect 0/1/2)"
fi

# A malformed line must NOT be silently dropped: jq fromjson? would skip it, so the
# guard refuses the rewrite (rc 1) and leaves the log byte-for-byte — the same
# never-deletes invariant archive-stale.sh enforces on this file.
new_sandbox
printf '%s\n%s\n%s\n' \
  '{"ts":"2026-05-01T10:00:00Z","producer":"/d","scope":"s","summary":"a","tags":["x"],"dedup_key":"rb1","access_count":0}' \
  'THIS LINE IS NOT JSON' \
  '{"ts":"2026-05-03T10:00:00Z","producer":"/d","scope":"s","summary":"c","tags":["x"],"dedup_key":"rb3","access_count":0}' \
  > .geniro/knowledge/learnings.jsonl
before=$(cksum < .geniro/knowledge/learnings.jsonl)
set +e; record_access rb1; rc=$?; set -e
after=$(cksum < .geniro/knowledge/learnings.jsonl)
lines=$(awk 'NF{c++} END{print c+0}' .geniro/knowledge/learnings.jsonl)
if [ "$rc" -eq 1 ] && [ "$lines" -eq 3 ] && [ "$before" = "$after" ]; then
  pass "record_access refuses to rewrite a log with a malformed line (never-deletes guard)"
else
  fail "record_access never-deletes guard; rc=$rc lines=$lines unchanged=$([ "$before" = "$after" ] && echo y || echo n) (expect 1/3/y)"
fi

# Held rewrite lock → skip the bump (best-effort), leave the log untouched,
# and do NOT steal or release the foreign lock.
new_sandbox
printf '%s\n' '{"ts":"2026-05-01T10:00:00Z","producer":"/d","scope":"s","summary":"a","tags":["x"],"dedup_key":"rl1","access_count":0}' \
  > .geniro/knowledge/learnings.jsonl
mkdir .geniro/knowledge/.archive-stale.lock
set +e; record_access rl1; rc=$?; set -e
cnt=$(jq -Rc 'fromjson? | select(.dedup_key=="rl1") | .access_count' .geniro/knowledge/learnings.jsonl)
if [ "$rc" -eq 0 ] && [ "$cnt" = "0" ] && [ -d .geniro/knowledge/.archive-stale.lock ]; then
  pass "record_access skips the bump while the rewrite lock is held (lock preserved)"
else
  fail "record_access lock-skip; rc=$rc cnt=$cnt lockdir=$([ -d .geniro/knowledge/.archive-stale.lock ] && echo y || echo n) (expect 0/0/y)"
fi
rmdir .geniro/knowledge/.archive-stale.lock

# Lock is acquired for the bump and released afterwards (RETURN trap).
set +e; record_access rl1; rc=$?; set -e
cnt=$(jq -Rc 'fromjson? | select(.dedup_key=="rl1") | .access_count' .geniro/knowledge/learnings.jsonl)
if [ "$rc" -eq 0 ] && [ "$cnt" = "1" ] && [ ! -d .geniro/knowledge/.archive-stale.lock ]; then
  pass "record_access releases the rewrite lock after the bump"
else
  fail "record_access lock-release; rc=$rc cnt=$cnt lock-left=$([ -d .geniro/knowledge/.archive-stale.lock ] && echo y || echo n) (expect 0/1/n)"
fi

# ===== Pre-acquire stale-lock reclaim (the crash-wedge branch) =====
# A crash while another rewriter held the mkdir DIRECTORY lock leaves it behind
# with no trap to clear it; without reclaim every later bump skips silently. The
# reclaim window is shared with archive-stale.sh via GENIRO_LOCK_RECLAIM_SECS.
seed_rl() {   # plant one bumpable entry; $1 = touch -t stamp for the lock, or ""
  new_sandbox
  printf '%s\n' '{"ts":"2026-05-01T10:00:00Z","producer":"/d","scope":"s","summary":"a","tags":["x"],"dedup_key":"rl1","access_count":0}' \
    > .geniro/knowledge/learnings.jsonl
  mkdir .geniro/knowledge/.archive-stale.lock
  # Explicit `if`, not `[ … ] && …`: the guard is the function's last command, so
  # an empty stamp would return 1 and abort the caller under `set -e`.
  if [ -n "$1" ]; then touch -t "$1" .geniro/knowledge/.archive-stale.lock; fi
  return 0
}
count_rl() { jq -Rc 'fromjson? | select(.dedup_key=="rl1") | .access_count' .geniro/knowledge/learnings.jsonl; }

seed_rl 202001010000   # 2020 → far past any sane reclaim window
set +e; record_access rl1; rc=$?; set -e
cnt=$(count_rl)
if [ "$rc" -eq 0 ] && [ "$cnt" = "1" ] && [ ! -d .geniro/knowledge/.archive-stale.lock ]; then
  pass "record_access reclaims a stale lock, bumps, and releases"
else
  fail "record_access stale-lock reclaim; rc=$rc cnt=$cnt lock-left=$([ -d .geniro/knowledge/.archive-stale.lock ] && echo y || echo n) (expect 0/1/n)"
fi

# A non-numeric override must not disable reclaim: unsanitized it would reach
# `[ -gt ]`, error, evaluate false, and wedge the counter bump permanently.
seed_rl 202001010000
set +e; err=$(GENIRO_LOCK_RECLAIM_SECS=abc record_access rl1 2>&1 >/dev/null); rc=$?; set -e
cnt=$(count_rl)
if [ "$rc" -eq 0 ] && [ "$cnt" = "1" ] && [ ! -d .geniro/knowledge/.archive-stale.lock ] \
   && ! printf '%s' "$err" | grep -qi 'integer expression'; then
  pass "non-numeric GENIRO_LOCK_RECLAIM_SECS falls back to the default — stale lock still reclaimed"
else
  fail "record_access bad-override sanitization; rc=$rc cnt=$cnt lock-left=$([ -d .geniro/knowledge/.archive-stale.lock ] && echo y || echo n) err='$err' (expect 0/1/n)"
fi

# The same override must not make reclaim indiscriminate: a FRESH lock is a live
# writer, so the bump skips and the foreign lock survives untouched.
seed_rl ""             # mtime = now
set +e; GENIRO_LOCK_RECLAIM_SECS=abc record_access rl1; rc=$?; set -e
cnt=$(count_rl)
if [ "$rc" -eq 0 ] && [ "$cnt" = "0" ] && [ -d .geniro/knowledge/.archive-stale.lock ]; then
  pass "non-numeric override does not steal a fresh lock (bump skipped, lock preserved)"
else
  fail "record_access fresh-lock preservation; rc=$rc cnt=$cnt lockdir=$([ -d .geniro/knowledge/.archive-stale.lock ] && echo y || echo n) (expect 0/0/y)"
fi
rmdir .geniro/knowledge/.archive-stale.lock 2>/dev/null || true
# bash keeps a `VAR=v func` assignment set after the function returns — clear it
# so it cannot leak into anything appended below.
unset GENIRO_LOCK_RECLAIM_SECS

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
