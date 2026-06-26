#!/usr/bin/env bash
# Smoke test for _geniro_instructions_dir() in lib/repo-root.sh.
#
# Run: bash tests/memory/instructions-dir.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(cd "$(mktemp -d)" && pwd -P)"
ORIGINAL_PWD="$PWD"
ORIGINAL_HOME="$HOME"
trap 'cd "$ORIGINAL_PWD"; HOME="$ORIGINAL_HOME"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/repo-root.sh"

# Clear BOTH override env vars so no case bleeds into the next. unset of an
# already-unset var is a no-op under `set -u`, so this is safe every call.
clear_env() { unset GENIRO_INSTRUCTIONS_DIR CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR; }

# cd into a sandbox project, resolve the instructions dir, assert. cd happens
# in the CURRENT shell so the counters update (subshells would lose them).
# Always cd back to TMPDIR_BASE at end to avoid bleed-over.
expect_instructions() {
  local from_dir="$1" expected="$2" label="$3"
  cd "$from_dir" || { fail "cd $from_dir failed"; return; }
  local got
  got=$(_geniro_instructions_dir)
  if [ "$got" = "$expected" ]; then
    pass "$label"
  else
    fail "$label — expected '$expected', got '$got'"
  fi
  # shellcheck disable=SC2164
  cd "$TMPDIR_BASE"
}

# Sandbox project with a .geniro/ marker so the in-repo default resolves
# deterministically via the _geniro_repo_root walk-up. git init establishes
# a clean repo boundary, matching the repo-root.sh test.
PROJ="$TMPDIR_BASE/proj"
DEFAULT_INSTR="$PROJ/.geniro/instructions"
mkdir -p "$PROJ/.geniro"
( cd "$PROJ" && git init -q )

# Pre-create the override target dirs used across cases.
EXT_GLOBAL="$TMPDIR_BASE/ext-global"
PLUGIN_OPT="$TMPDIR_BASE/plugin-opt"
mkdir -p "$EXT_GLOBAL" "$PLUGIN_OPT"

# 1. Neither override set → in-repo default under the project's .geniro/.
clear_env
expect_instructions "$PROJ" "$DEFAULT_INSTR" \
  "no override env → in-repo .geniro/instructions default"

# 2. GENIRO_INSTRUCTIONS_DIR set to an existing dir → that dir verbatim.
clear_env
export GENIRO_INSTRUCTIONS_DIR="$EXT_GLOBAL"
expect_instructions "$PROJ" "$EXT_GLOBAL" \
  "GENIRO_INSTRUCTIONS_DIR (existing) → that dir"

# 3. GENIRO_INSTRUCTIONS_DIR set to a non-existent path → fail-open to default.
clear_env
export GENIRO_INSTRUCTIONS_DIR="$TMPDIR_BASE/does-not-exist"
expect_instructions "$PROJ" "$DEFAULT_INSTR" \
  "GENIRO_INSTRUCTIONS_DIR (missing) → fail-open to in-repo default"

# 4. Plugin-option dir set, GENIRO unset → plugin-option dir used.
clear_env
export CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR="$PLUGIN_OPT"
expect_instructions "$PROJ" "$PLUGIN_OPT" \
  "CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR (existing), GENIRO unset → plugin-option dir"

# 5. Both set to different existing dirs → GENIRO_INSTRUCTIONS_DIR wins.
clear_env
export GENIRO_INSTRUCTIONS_DIR="$EXT_GLOBAL"
export CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR="$PLUGIN_OPT"
expect_instructions "$PROJ" "$EXT_GLOBAL" \
  "both set → GENIRO_INSTRUCTIONS_DIR wins (precedence)"

# 6. Tilde expansion: GENIRO_INSTRUCTIONS_DIR="~/<subdir>" → $HOME/<subdir>.
# Point HOME at a tmp fake home so the real home is never touched, create the
# subdir there, assert the expansion, then restore HOME for the remaining run.
clear_env
FAKE_HOME="$TMPDIR_BASE/fakehome"
mkdir -p "$FAKE_HOME/myinstr"
HOME="$FAKE_HOME"
# shellcheck disable=SC2088
export GENIRO_INSTRUCTIONS_DIR="~/myinstr"
expect_instructions "$PROJ" "$FAKE_HOME/myinstr" \
  "tilde ~/subdir expands to \$HOME/subdir (existing)"
HOME="$ORIGINAL_HOME"

# 7. Bare tilde: GENIRO_INSTRUCTIONS_DIR="~" → $HOME. Point HOME at the existing
# tmp fake home, assert the bare-~ arm returns $HOME verbatim, then restore HOME.
clear_env
HOME="$FAKE_HOME"
# shellcheck disable=SC2088
export GENIRO_INSTRUCTIONS_DIR="~"
expect_instructions "$PROJ" "$FAKE_HOME" \
  "bare tilde ~ expands to \$HOME"
HOME="$ORIGINAL_HOME"

# 8. Plugin-option dir set to a non-existent path, GENIRO unset → fail-open to the
# in-repo default (NOT the bad path), mirroring case 3 for the plugin-option channel.
clear_env
export CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR="$TMPDIR_BASE/plugin-opt-missing"
expect_instructions "$PROJ" "$DEFAULT_INSTR" \
  "CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR (missing), GENIRO unset → fail-open to in-repo default"

clear_env
echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
