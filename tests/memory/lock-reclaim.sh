#!/usr/bin/env bash
# Smoke test for lib/lock-reclaim.sh — the single home of the stale-lock reclaim
# window every lock site in the plugin reads.
#
# Run: bash tests/memory/lock-reclaim.sh
#
# Three properties matter, and all three are safety-relevant:
#   1. The default is the documented 600s, and every consumer resolves the SAME
#      value — archive-stale.sh, query-learnings.sh and the session-start hook
#      reclaim the same .archive-stale.lock, so a divergence lets one side
#      reclaim a lock another still believes it holds.
#   2. A non-numeric override falls back to the default rather than reaching a
#      `[ -gt ]` test, which would error, evaluate false, and leave an abandoned
#      lock wedging every subsequent write.
#   3. The hook's inline fallback (a vendored install ships hooks/ without lib/)
#      resolves identically to the canonical helper.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

check() {  # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/lock-reclaim.sh"

# --- 1. Documented default.
check "default reclaim window is 600s" "600" "$(_geniro_lock_reclaim_secs)"

# --- 2. A numeric override is honoured.
check "numeric override is honoured" "45" "$(GENIRO_LOCK_RECLAIM_SECS=45 _geniro_lock_reclaim_secs)"

# --- 3. Malformed overrides fall back to the default instead of reaching `[ -gt ]`.
check "non-numeric override falls back"  "600" "$(GENIRO_LOCK_RECLAIM_SECS=abc _geniro_lock_reclaim_secs)"
check "empty override falls back"        "600" "$(GENIRO_LOCK_RECLAIM_SECS='' _geniro_lock_reclaim_secs)"
check "negative override falls back"     "600" "$(GENIRO_LOCK_RECLAIM_SECS=-30 _geniro_lock_reclaim_secs)"
check "float override falls back"        "600" "$(GENIRO_LOCK_RECLAIM_SECS=1.5 _geniro_lock_reclaim_secs)"
check "whitespace override falls back"   "600" "$(GENIRO_LOCK_RECLAIM_SECS='6 00' _geniro_lock_reclaim_secs)"
# Zero would make every lock older than a second "stale" (a live writer's lock
# stolen); an overlong digit string overflows the shell's arithmetic and wraps
# negative (reclaim never fires). Both fall back; the longest accepted value is 9 digits.
check "zero override falls back"         "600" "$(GENIRO_LOCK_RECLAIM_SECS=0 _geniro_lock_reclaim_secs)"
check "all-zero override falls back"     "600" "$(GENIRO_LOCK_RECLAIM_SECS=000 _geniro_lock_reclaim_secs)"
check "10-digit override falls back"     "600" "$(GENIRO_LOCK_RECLAIM_SECS=1234567890 _geniro_lock_reclaim_secs)"
check "overflowing override falls back"  "600" "$(GENIRO_LOCK_RECLAIM_SECS=99999999999999999999 _geniro_lock_reclaim_secs)"
check "1 is the smallest honoured value" "1"   "$(GENIRO_LOCK_RECLAIM_SECS=1 _geniro_lock_reclaim_secs)"
check "9-digit override is honoured"     "123456789" "$(GENIRO_LOCK_RECLAIM_SECS=123456789 _geniro_lock_reclaim_secs)"

# The sanitized value must survive as an integer test operand — the failure mode
# the sanitation exists to prevent is `[ -gt ]` erroring on a junk value.
if [ "$(GENIRO_LOCK_RECLAIM_SECS=abc _geniro_lock_reclaim_secs)" -gt 0 ] 2>/dev/null; then
  pass "sanitized value is a valid integer-test operand"
else
  fail "sanitized value is a valid integer-test operand"
fi

# --- 4. Every consumer resolves the same number.
#        query-learnings.sh and archive-stale.sh source the helper; the
#        session-start hook carries an inline fallback for vendored installs.
for lib in query-learnings archive-stale update-semantic; do
  got=$(bash -c "source '$REPO_ROOT/lib/$lib.sh' >/dev/null 2>&1; _geniro_lock_reclaim_secs" 2>/dev/null)
  check "lib/$lib.sh resolves the shared window" "600" "$got"
done

# --- 5. The hook's inline fallback matches the canonical helper. Extract it from
#        the hook and run it with lib/ unreachable, which is the vendored install.
FALLBACK=$(awk '
  /^if ! command -v _geniro_lock_reclaim_secs /{inb=1; next}
  inb && /^fi$/{exit}
  inb{print}
' "$REPO_ROOT/hooks/session-start-restore.sh")
if [ -z "$FALLBACK" ]; then
  fail "session-start-restore.sh carries an inline _geniro_lock_reclaim_secs fallback"
else
  pass "session-start-restore.sh carries an inline _geniro_lock_reclaim_secs fallback"
  check "inline fallback default matches the helper" "600" \
    "$(bash -c "$FALLBACK
_geniro_lock_reclaim_secs")"
  check "inline fallback sanitizes like the helper" "600" \
    "$(GENIRO_LOCK_RECLAIM_SECS=abc bash -c "$FALLBACK
_geniro_lock_reclaim_secs")"
  check "inline fallback honours a numeric override" "45" \
    "$(GENIRO_LOCK_RECLAIM_SECS=45 bash -c "$FALLBACK
_geniro_lock_reclaim_secs")"
  check "inline fallback rejects zero like the helper" "600" \
    "$(GENIRO_LOCK_RECLAIM_SECS=0 bash -c "$FALLBACK
_geniro_lock_reclaim_secs")"
  check "inline fallback rejects an overlong digit string like the helper" "600" \
    "$(GENIRO_LOCK_RECLAIM_SECS=99999999999999999999 bash -c "$FALLBACK
_geniro_lock_reclaim_secs")"
fi

# --- 6. Double-sourcing under `set -e` does not crash the caller.
if bash -c "set -e; source '$REPO_ROOT/lib/lock-reclaim.sh'; source '$REPO_ROOT/lib/lock-reclaim.sh'; _geniro_lock_reclaim_secs >/dev/null"; then
  pass "double-sourcing lib/lock-reclaim.sh under set -e does not crash"
else
  fail "double-sourcing lib/lock-reclaim.sh under set -e crashed"
fi

# --- 7. Sourcing under zsh defines the function (helpers are sourced into skill
#        Bash blocks, which run under zsh on some hosts).
if command -v zsh >/dev/null 2>&1; then
  if zsh -c "source '$REPO_ROOT/lib/lock-reclaim.sh' && command -v _geniro_lock_reclaim_secs" >/dev/null 2>&1; then
    pass "zsh: source lib/lock-reclaim.sh defines _geniro_lock_reclaim_secs"
  else
    fail "zsh: source lib/lock-reclaim.sh did not define _geniro_lock_reclaim_secs"
  fi
else
  echo "SKIP: zsh not available — zsh-source check skipped."
fi

# --- 8. _geniro_reclaim_stale_lock <path> <secs>: atomic rename-then-remove.
RL_DIR="$(mktemp -d)"
trap 'rm -rf "$RL_DIR"' EXIT
mkdir "$RL_DIR/stale.lock"; touch -t 202001010000 "$RL_DIR/stale.lock"
_geniro_reclaim_stale_lock "$RL_DIR/stale.lock" 600; rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$RL_DIR/stale.lock" ] && [ -z "$(find "$RL_DIR" -name '*.stale.*')" ]; then
  pass "reclaim: stale lock dir removed (rc 0), no moved copy left behind"
else fail "reclaim: stale dir rc=$rc left=$(ls "$RL_DIR" | tr '\n' ' ')"; fi
# A second reclaimer arriving after a rival re-acquired must not remove the fresh lock.
mkdir "$RL_DIR/stale.lock"
_geniro_reclaim_stale_lock "$RL_DIR/stale.lock" 600; rc=$?
if [ "$rc" -eq 1 ] && [ -d "$RL_DIR/stale.lock" ]; then
  pass "reclaim: a freshly re-acquired lock is untouched (rc 1)"
else fail "reclaim: fresh lock rc=$rc present=$([ -d "$RL_DIR/stale.lock" ] && echo y || echo n)"; fi
_geniro_reclaim_stale_lock "$RL_DIR/absent.lock" 600; rc=$?
[ "$rc" -eq 0 ] && pass "reclaim: absent lock returns 0" || fail "reclaim: absent rc=$rc"
: > "$RL_DIR/stale.file"; touch -t 202001010000 "$RL_DIR/stale.file"
_geniro_reclaim_stale_lock "$RL_DIR/stale.file" 600; rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$RL_DIR/stale.file" ]; then pass "reclaim: stale lock FILE reclaimed"; else fail "reclaim: stale file rc=$rc"; fi
# Racing reclaimers over one stale lock, each followed by acquire: exactly one
# mkdir winner may hold the lock at the end, and nobody may delete the winner's.
mkdir "$RL_DIR/race.lock"; touch -t 202001010000 "$RL_DIR/race.lock"
for _i in 1 2 3 4 5 6; do
  ( _geniro_reclaim_stale_lock "$RL_DIR/race.lock" 600 || true
    mkdir "$RL_DIR/race.lock" 2>/dev/null && echo won >> "$RL_DIR/race.wins" ) &
done
wait
wins=$(wc -l < "$RL_DIR/race.wins" 2>/dev/null | tr -d ' ')
if [ "${wins:-0}" -ge 1 ] && [ -d "$RL_DIR/race.lock" ] && [ -z "$(find "$RL_DIR" -name '*.stale.*')" ]; then
  pass "reclaim: concurrent reclaimers leave a held lock and no moved copies (wins=$wins)"
else fail "reclaim: race wins=$wins left=$(ls "$RL_DIR" | tr '\n' ' ')"; fi
# Inline fallback in the hook matches the canonical behavior.
RFB=$(awk '/^if ! command -v _geniro_reclaim_stale_lock /{inb=1; next} inb && /^fi$/{exit} inb{print}' "$REPO_ROOT/hooks/session-start-restore.sh")
mkdir "$RL_DIR/fb.lock"; touch -t 202001010000 "$RL_DIR/fb.lock"
if [ -n "$RFB" ] && bash -c "$RFB
_geniro_reclaim_stale_lock '$RL_DIR/fb.lock' 600" && [ ! -e "$RL_DIR/fb.lock" ]; then
  pass "hook inline _geniro_reclaim_stale_lock fallback reclaims a stale lock"
else fail "hook inline reclaim fallback missing or broken"; fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
