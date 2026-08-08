#!/usr/bin/env bash
# Regression: lib helpers must work when SOURCED UNDER ZSH, not just bash.
#
# The Bash tool in some Claude Code environments executes commands under zsh.
# BASH_SOURCE is bash-only — before the cross-shell self-location fix, every
# helper that located siblings via dirname "${BASH_SOURCE[0]}" silently loaded
# nothing under zsh (functions undefined), and _geniro_repo_root resolved to
# the empty string so writes targeted /.geniro (filesystem root). Separately,
# `${!arr[@]}` in redact_secrets expanded to VALUES under zsh, mis-iterating
# the pattern loop and blanking every sanitized field.
#
# This suite sources EVERY lib/ helper under BOTH shells — plainly, and again
# under `set -u`, which is where an unguarded ${BASH_SOURCE[0]} stops expanding
# to "" and starts aborting the whole file — and exercises the end-to-end emit +
# redact + query path under zsh.
#
# Run: bash tests/memory/zsh-source-compat.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if ! command -v zsh >/dev/null 2>&1; then
  echo "SKIP: zsh not available on this machine — nothing to verify."
  exit 0
fi

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

SANDBOX_DIR=""
new_sandbox() {
  SANDBOX_DIR="$(mktemp -d "$TMPDIR_BASE/sandbox.XXXXXXXXXX")"
  mkdir -p "$SANDBOX_DIR/.geniro"
  (cd "$SANDBOX_DIR" && git init -q)
}

# --- 1. Each sibling-sourcing helper defines its public function when
#        sourced under zsh AND under bash (the fix must not regress bash).
check_source() {
  local shell="$1" helper="$2" fn="$3"
  new_sandbox
  if (cd "$SANDBOX_DIR" && "$shell" -c "source '$REPO_ROOT/lib/$helper' && command -v $fn" >/dev/null 2>&1); then
    pass "$shell: source lib/$helper defines $fn"
  else
    fail "$shell: source lib/$helper did not define $fn"
  fi
}

for shell in zsh bash; do
  check_source "$shell" emit-learning.sh      emit_learning
  check_source "$shell" redact-secrets.sh     redact_secrets
  check_source "$shell" query-learnings.sh    query_learnings
  check_source "$shell" load-semantic.sh      load_semantic
  check_source "$shell" update-semantic.sh    update_semantic
  check_source "$shell" emit-rejection.sh     emit_rejection_if_signal
  check_source "$shell" archive-stale.sh      archive_stale_learnings
  check_source "$shell" validate-state-file.sh validate_state_file
  check_source "$shell" atomic-state-write.sh atomic_state_write
  check_source "$shell" repo-root.sh          _geniro_repo_root
  check_source "$shell" hash.sh               _geniro_sha256
  check_source "$shell" branch-slug.sh        _geniro_branch_slug
  check_source "$shell" resolve-conflicts.sh  emit_conflict_notice
  check_source "$shell" write-vectors.sh      _geniro_extract_inner_payloads
  check_source "$shell" clean-task-transients.sh clean_task_transients
done

# score-formula.sh exports a jq definition block rather than a function, so it is
# checked on the variable it publishes.
for shell in zsh bash; do
  new_sandbox
  if (cd "$SANDBOX_DIR" && "$shell" -c "source '$REPO_ROOT/lib/score-formula.sh' && [ -n \"\$GENIRO_SCORE_JQ_DEFS\" ]" >/dev/null 2>&1); then
    pass "$shell: source lib/score-formula.sh defines GENIRO_SCORE_JQ_DEFS"
  else
    fail "$shell: source lib/score-formula.sh did not define GENIRO_SCORE_JQ_DEFS"
  fi
done

# --- 1b. EVERY lib helper must survive `set -u`, under both shells.
#        The failure this catches is silent in the check above: an unguarded
#        ${BASH_SOURCE[0]} expands to the empty string under a permissive zsh and
#        only aborts (rc=126, whole block dead) once the caller runs with `set -u`
#        — which the Bash tool does. Enumerated by glob, not by hand, so a newly
#        added lib/ helper is covered the moment it lands.
#
#        rc==0 alone is not enough: a helper can print a
#        `BASH_SOURCE[0]: parameter not set` error to stderr under zsh and
#        still return 0 (bash's `set -u` aborts the file; zsh's warns and
#        continues) — the exact shape that lets a mis-resolved repo root ship
#        with this suite green. Assert the captured output is empty too.
for helper in "$REPO_ROOT"/lib/*.sh; do
  [ -f "$helper" ] || continue
  hname="$(basename "$helper")"
  for shell in zsh bash; do
    new_sandbox
    out=$( (cd "$SANDBOX_DIR" && "$shell" -c "set -u; source '$helper'") 2>&1 )
    rc=$?
    if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
      pass "$shell: source lib/$hname under 'set -u' succeeds silently"
    else
      fail "$shell: source lib/$hname under 'set -u' failed or printed (rc=$rc): $out"
    fi
  done
done

# --- 1c. Positive resolution probe: sourcing "successfully" is not the same
#        as resolving to the RIGHT path — a helper can silently mis-resolve
#        (e.g. ${BASH_SOURCE:-} empty → dirname "" → ".") without printing
#        anything or returning non-zero. For every helper that exposes its
#        derived script-dir as an
#        accessible variable/function after sourcing, assert it equals the
#        REAL path — under both shells. Helpers with no such accessor are
#        skipped rather than given one invented for the test.
_SCRIPT_DIR_PROBES="archive-stale.sh:_as_script_dir emit-learning.sh:_el_script_dir emit-rejection.sh:_er_script_dir load-semantic.sh:_ls_script_dir query-learnings.sh:_ql_script_dir redact-secrets.sh:_red_script_dir update-semantic.sh:_us_script_dir validate-state-file.sh:_vsf_script_dir"
for probe in $_SCRIPT_DIR_PROBES; do
  hname="${probe%%:*}"
  var="${probe##*:}"
  for shell in zsh bash; do
    new_sandbox
    got=$(cd "$SANDBOX_DIR" && "$shell" -c "source '$REPO_ROOT/lib/$hname' && printf '%s' \"\$$var\"" 2>/dev/null)
    if [ "$got" = "$REPO_ROOT/lib" ]; then
      pass "$shell: lib/$hname resolves $var to the real lib/ directory"
    else
      fail "$shell: lib/$hname resolved $var to '$got', want '$REPO_ROOT/lib'"
    fi
  done
done

# --- 2. End-to-end emit under zsh: entry lands in the SANDBOX log (repo root
#        resolved correctly, not "" → /.geniro) with the secret redacted
#        (pattern loop iterated, sanitized text not blanked).
new_sandbox
json=$(jq -nc '{producer:"/debug",scope:"zsh-e2e",summary:"key sk-ant-test12345 leaked",tags:["zsh-compat"]}')
rc=0
(cd "$SANDBOX_DIR" && printf '%s' "$json" \
  | zsh -c "source '$REPO_ROOT/lib/emit-learning.sh' && emit_learning") || rc=$?
log="$SANDBOX_DIR/.geniro/knowledge/learnings.jsonl"
summary=$(jq -r '.summary' "$log" 2>/dev/null || echo "MISSING")
if [ "$rc" -eq 0 ] && [ "$summary" = "key [REDACTED:api-key:anthropic] leaked" ]; then
  pass "zsh e2e: emit_learning writes to sandbox log with redacted summary"
else
  fail "zsh e2e: rc=$rc summary='$summary' (expected redacted, in sandbox log)"
fi

# --- 3. redact_secrets under zsh walks the WHOLE pattern list: secrets from
#        two different patterns (anthropic + AWS) both redacted in one pass.
new_sandbox
out=$(cd "$SANDBOX_DIR" && printf '%s' 'a sk-ant-abc123 b AKIAAAAABBBBCCCCDDDD c' \
  | zsh -c "source '$REPO_ROOT/lib/redact-secrets.sh' && redact_secrets test summary k1" 2>/dev/null)
case "$out" in
  *'sk-ant'*|*'AKIA'*)
    fail "zsh redact: secret survived sanitization: '$out'" ;;
  *'[REDACTED:api-key:anthropic]'*'[REDACTED:aws-key]'*)
    pass "zsh redact: both patterns redacted in one pass" ;;
  *)
    fail "zsh redact: unexpected output: '$out'" ;;
esac

# --- 4. Seed under zsh, then query under zsh (exercises repo-root +
#        score-formula chain in the read path).
new_sandbox
json=$(jq -nc '{producer:"/debug",scope:"zsh-q",summary:"query roundtrip probe",tags:["zsh-roundtrip"]}')
out=$(cd "$SANDBOX_DIR" && printf '%s' "$json" \
  | zsh -c "source '$REPO_ROOT/lib/emit-learning.sh' && emit_learning \
            && source '$REPO_ROOT/lib/query-learnings.sh' && query_learnings --tag zsh-roundtrip" 2>/dev/null)
case "$out" in
  *'query roundtrip probe'*) pass "zsh roundtrip: emit then query finds the entry" ;;
  *) fail "zsh roundtrip: query output missing entry: '$out'" ;;
esac

# --- 5. archive-stale direct-invocation guard under zsh: sourcing must NOT
#        run main; direct execution MUST (empty log → its rc=1 notice).
new_sandbox
out=$(cd "$SANDBOX_DIR" && zsh -c "source '$REPO_ROOT/lib/archive-stale.sh'" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "zsh: sourcing archive-stale.sh does not trigger the direct-run main"
else
  fail "zsh: sourcing archive-stale.sh ran main (rc=$rc out='$out')"
fi

new_sandbox
out=$(cd "$SANDBOX_DIR" && zsh "$REPO_ROOT/lib/archive-stale.sh" --dry-run 2>&1)
rc=$?
case "$out" in
  *'no learnings.jsonl found'*)
    if [ "$rc" -eq 1 ]; then
      pass "zsh: direct execution of archive-stale.sh runs main"
    else
      fail "zsh: direct execution ran main but rc=$rc (expected 1)"
    fi ;;
  *)
    fail "zsh: direct execution did not reach main (rc=$rc out='$out')" ;;
esac

# --- 6. clean-task-transients direct-invocation guard under zsh: the same
#        sourced-vs-executed split as archive-stale.sh, verified by effect —
#        sourcing must leave the scratch alone, direct execution must remove the
#        T1 transients while preserving the T1.5 durables.
new_sandbox
mkdir -p "$SANDBOX_DIR/task"
: > "$SANDBOX_DIR/task/.kr-out.md"
: > "$SANDBOX_DIR/task/spec.md"
(cd "$SANDBOX_DIR" && zsh -c "source '$REPO_ROOT/lib/clean-task-transients.sh'" >/dev/null 2>&1)
if [ -f "$SANDBOX_DIR/task/.kr-out.md" ]; then
  pass "zsh: sourcing clean-task-transients.sh does not trigger the direct-run cleanup"
else
  fail "zsh: sourcing clean-task-transients.sh ran the cleanup"
fi

(cd "$SANDBOX_DIR" && zsh "$REPO_ROOT/lib/clean-task-transients.sh" task >/dev/null 2>&1)
if [ ! -f "$SANDBOX_DIR/task/.kr-out.md" ] && [ -f "$SANDBOX_DIR/task/spec.md" ]; then
  pass "zsh: direct execution of clean-task-transients.sh removes T1 scratch, keeps T1.5 durables"
else
  fail "zsh: direct execution of clean-task-transients.sh did not clean as expected"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
