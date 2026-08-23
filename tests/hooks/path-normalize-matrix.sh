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
# 2026-08-23 audit T0-1/T0-2: the same slash/dot-segment matrix was silent on
# a whole SECOND axis — case. `.GENIRO` and `.geniro` are the same inode on a
# case-insensitive filesystem, so a case-sensitive matcher is exactly as open
# as one that forgets to collapse `.`/`//`. {XU}/{GU} below are that axis, and
# a trailing block of command-word case variants (rm/RM, git/Git/GIT) closes
# T0-3/T0-4 the same way.
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
upper-geniro|.GENIRO/{X}
mixed-case-geniro|.GeNiRo/{X}
upper-segment|.geniro/{XU}
upper-both|.GENIRO/{XU}
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
  local seg_upper
  # tr, not bash 4's ${seg^^}: this suite runs on bash 3.2 (macOS /bin/bash).
  seg_upper="$(printf '%s' "$seg" | tr '[:lower:]' '[:upper:]')"
  local id path_tmpl path payload rc first_rc="" all_agree=1
  while IFS='|' read -r id path_tmpl; do
    [ -z "$id" ] && continue
    path="${path_tmpl//\{X\}/$seg}"
    path="${path//\{XU\}/$seg_upper}"
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
# general state-path gate, file-tool side (#2). Was a Bash redirect until the
# shell-side branch was retired; the path-spelling matrix is what matters here
# and it runs identically through file_path.
matrix_for_guard "enforce-state-helper.sh [state path write]" \
  "$REPO_ROOT/hooks/enforce-state-helper.sh" "planning/task/state.md" \
  '{"tool_name":"Write","tool_input":{"file_path":"{P}","content":"x"}}'

# ===== hooks/block-geniro-deletion.sh (findings #3, #4) =====
matrix_for_guard "block-geniro-deletion.sh [rm -rf]" \
  "$REPO_ROOT/hooks/block-geniro-deletion.sh" "instructions" \
  '{"tool_input":{"command":"rm -rf {P}"}}'

# ===== Command-word case axis (2026-08-23 audit T0-3/T0-4) =====
# Same "every spelling must agree with the plain form" property, applied to
# the COMMAND WORD (rm/RM, git/GIT) rather than the .geniro path — macOS PATH
# lookup resolves `RM`/`Git`/`GIT` to the same binary as the lowercase
# spelling, so a matcher keyed to one case is exactly as open as one that
# forgets a path spelling.
# cmdword_matrix <label> <hook-path> <cmd-template-with-{C}>
# {C} is substituted with each command-word spelling in turn; all must agree.
cmdword_matrix() {  # <label> <hook-path> <cmd-tmpl-with-{C}-and-rest> <words...>
  local label="$1" hook="$2" cmd_tmpl="$3"
  shift 3
  local word cmd payload rc first_rc="" all_agree=1
  for word in "$@"; do
    cmd="${cmd_tmpl//\{C\}/$word}"
    payload="{\"tool_input\":{\"command\":\"${cmd}\"}}"
    rc=$(run_guard "$hook" "$payload")
    if [ -z "$first_rc" ]; then first_rc="$rc"; fi
    if [ "$rc" = "$first_rc" ]; then
      pass "$label [$word]: agrees with the plain spelling (rc=$rc)"
    else
      all_agree=0
      fail "$label [$word]: DISAGREES with the plain spelling (plain=$first_rc, this=$rc), cmd=$cmd"
    fi
  done
  if [ "$first_rc" != "2" ]; then
    all_agree=0
    fail "$label: the plain spelling itself did not block (rc=$first_rc) — the matrix is vacuous without a real gate to close"
  fi
  [ "$all_agree" = "1" ] && pass "$label: every command-word spelling decided identically (rc=2)"
}

cmdword_matrix "block-geniro-deletion.sh [rm -rf .geniro command-word case]" \
  "$REPO_ROOT/hooks/block-geniro-deletion.sh" \
  '{C} -rf .geniro' \
  rm RM Rm rM

cmdword_matrix "block-dangerous-git.sh [push --force command-word case]" \
  "$REPO_ROOT/hooks/block-dangerous-git.sh" \
  '{C} push --force' \
  git Git GIT gIt

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
