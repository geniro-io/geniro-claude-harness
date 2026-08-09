#!/usr/bin/env bash
# Path-spelling matrix — closes the T0 defect class behind the 2026-08-09
# audit's findings #1-#4, not just the four reported instances.
#
# Run: bash tests/hooks/path-normalize-matrix.sh
#
# Findings #1 (hooks/enforce-state-helper.sh's safety-json-edit gate), #2 (the
# same file's general state-path gate) and #3/#4 (hooks/block-geniro-deletion.sh's
# check_delete_arg) were four surfacings of ONE missing step: nothing in the
# plugin collapsed a `.` path segment, and the deletion guard stripped only one
# trailing slash. Each was fixed by adding `_geniro_normalize_path` (duplicated
# verbatim in both files — lib/write-vectors.sh is out of scope for this fix)
# and calling it before the path match runs.
#
# A fix keyed to the four REPORTED spellings re-opens on the fifth spelling
# nobody has thought of yet. This suite instead feeds every guard a MATRIX of
# spellings that all resolve to the identical filesystem path, and asserts
# every one of them decides the SAME way as the plain, unadorned spelling —
# the property that stays true no matter which spelling a future caller (or
# adversary) picks, and that goes red immediately if `_geniro_normalize_path`
# is ever reverted or edited out of only one of the two files.
#
# Portability: bash 3.2 / BSD, no writes outside a mktemp sandbox, no network.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# The spelling list itself — every entry resolves to the SAME path as the
# plain "x" entry once `.` segments, repeated slashes and trailing slashes are
# collapsed. {X} is substituted with the guard-specific protected segment
# (e.g. "instructions", or "planning/task/state.md"). The last entry is the
# "..-free mixed case" the task calls for: leading "./", an internal "/./",
# and a doubled slash, all in one spelling, with no ".." anywhere.
SPELLINGS='
plain|.geniro/{X}
dot-segment|.geniro/./{X}
double-slash|.geniro//{X}
trailing-slash|.geniro/{X}/
trailing-double-slash|.geniro/{X}//
dot-segment-trailing-slash|.geniro/./{X}/
mixed-no-dotdot|./.geniro/./{X}//
'

run_guard() {  # <hook-path> <payload-json>
  local hook="$1" payload="$2"
  printf '%s' "$payload" | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$hook" >/dev/null 2>&1
  echo $?
}

# matrix_for_guard <label> <hook-path> <segment> <cmd-template>
#
# <cmd-template> uses {P} for the fully-substituted path and is turned into
# the tool_input JSON payload the guard expects. All seven spellings must
# yield the IDENTICAL exit code — this is the class-closing assertion, not
# just "each spelling blocks": if a future spelling nobody tested slips
# through, it disagrees with its siblings and this loop catches it without
# needing to have been told the new spelling in advance.
matrix_for_guard() {  # <label> <hook-path> <segment> <payload-tmpl-with-{P}>
  local label="$1" hook="$2" seg="$3" payload_tmpl="$4"
  local id path_tmpl path payload rc first_rc="" all_agree=1
  while IFS='|' read -r id path_tmpl; do
    [ -z "$id" ] && continue
    path="${path_tmpl//\{X\}/$seg}"
    payload="${payload_tmpl//\{P\}/$path}"
    rc=$(run_guard "$hook" "$payload")
    if [ -z "$first_rc" ]; then first_rc="$rc"; fi
    if [ "$rc" = "$first_rc" ]; then
      pass "$label [$id]: agrees with the plain spelling (rc=$rc), path=$path"
    else
      all_agree=0
      fail "$label [$id]: DISAGREES with the plain spelling (plain=$first_rc, this=$rc), path=$path"
    fi
  done <<< "$SPELLINGS"
  if [ "$first_rc" != "2" ]; then
    all_agree=0
    fail "$label: the plain spelling itself did not block (rc=$first_rc) — the matrix is vacuous without a real gate to close"
  fi
  [ "$all_agree" = "1" ] && pass "$label: every spelling in the matrix decided identically (rc=2)"
}

# ===== hooks/enforce-state-helper.sh (findings #1, #2) =====
# safety-json-edit gate: the exact single-tool self-grant reproduction (#1).
matrix_for_guard "enforce-state-helper.sh [safety.json write]" \
  "$REPO_ROOT/hooks/enforce-state-helper.sh" "safety.json" \
  '{"tool_name":"Write","tool_input":{"file_path":"{P}","content":"x"}}'
# general state-path gate, Bash-side redirect (#2).
matrix_for_guard "enforce-state-helper.sh [bash redirect]" \
  "$REPO_ROOT/hooks/enforce-state-helper.sh" "planning/task/state.md" \
  '{"tool_name":"Bash","tool_input":{"command":"echo x > {P}"}}'

# ===== hooks/block-geniro-deletion.sh (findings #3, #4) =====
matrix_for_guard "block-geniro-deletion.sh [rm -rf]" \
  "$REPO_ROOT/hooks/block-geniro-deletion.sh" "instructions" \
  '{"tool_input":{"command":"rm -rf {P}"}}'

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
