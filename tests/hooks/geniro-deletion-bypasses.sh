#!/usr/bin/env bash
# Regression suite for the 2026-09-23 plugin-audit bypasses in
# hooks/block-geniro-deletion.sh (T0-4, T0-5, T0-6, T0-7, T0-8, T0-9,
# T0-10). Each probe below reproduces the exact repro command from
# design/scratch/plugin-audit-2026-09-23.md / .geniro/state/audit-plugin/main/
# findings-D5b.md and findings-D8.md, run in a fresh mktemp -d sandbox — never
# against the real repo.
#
# Run: bash tests/hooks/geniro-deletion-bypasses.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-geniro-deletion.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

run_cmd() {
  jq -nc --arg c "$1" '{tool_input: {command: $c}}' | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK" >/dev/null 2>&1
  echo $?
}

# Cursor's file-tool `Delete` shape (T0-15): no `command` field at all, a
# `tool_input.file_path` instead, per the shim contract in the fix plan.
run_delete() {
  jq -nc --arg p "$1" --arg cwd "$PWD" '{tool_name:"Delete", tool_input:{file_path:$p}, cwd:$cwd}' | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK" >/dev/null 2>&1
  echo $?
}

expect_block() {
  local label="$1" actual="$2"
  if [ "$actual" = "2" ]; then pass "$label"; else fail "$label (expected exit=2, got exit=$actual)"; fi
}
expect_allow() {
  local label="$1" actual="$2"
  if [ "$actual" = "0" ]; then pass "$label"; else fail "$label (expected exit=0, got exit=$actual)"; fi
}

mkdir -p "$TMPDIR_BASE/sandbox"
cd "$TMPDIR_BASE/sandbox" || exit 1

# ===== T0-4: case-fold gaps — global-option strip =====
expect_block "GIT -C . add -f .geniro/x blocked (uppercase git + global opt)" \
  "$(run_cmd 'GIT -C . add -f .geniro/x')"
expect_block "Git -C . add -f .geniro/x blocked (mixed-case git + global opt)" \
  "$(run_cmd 'Git -C . add -f .geniro/x')"

# ===== T0-5: abbreviated long options =====
expect_block "git add --forc .geniro/x blocked (abbreviated --force)" \
  "$(run_cmd 'git add --forc .geniro/x')"
expect_block "git add --for .geniro/x blocked (abbreviated --force)" \
  "$(run_cmd 'git add --for .geniro/x')"
expect_allow "git add --force-with-lease-ish typo not misread as force" \
  "$(run_cmd 'git add --update foo.txt')"
expect_block "rm --rec -f .geniro blocked (abbreviated --recursive)" \
  "$(run_cmd 'rm --rec -f .geniro')"
expect_block "rm --recursive -f .geniro blocked (full spelling still works)" \
  "$(run_cmd 'rm --recursive -f .geniro')"
expect_allow "rm --recursive -f node_modules allowed (non-.geniro path)" \
  "$(run_cmd 'rm --recursive -f node_modules')"

# ===== T0-6: heredoc scrub false-positives on arithmetic and comments =====
expect_block "arithmetic shift heredoc false-positive no longer hides rm -rf .geniro" \
  "$(run_cmd $'echo $((1<<X))\nrm -rf .geniro\nX')"
expect_block "comment-line phantom heredoc no longer hides rm -rf .geniro" \
  "$(run_cmd $'# just a note <<EOF\nrm -rf .geniro\nEOF')"
expect_allow "plain arithmetic in an ordinary script stays allowed" \
  "$(run_cmd 'echo $((1<<3))')"
expect_allow "a genuine heredoc body mentioning rm -rf .geniro stays data" \
  "$(run_cmd $'cat <<EOF\nrm -rf .geniro/\nEOF')"

# ===== T0-7: glob / brace spellings of .geniro =====
expect_block "rm -rf .genir? blocked (single-char glob)" \
  "$(run_cmd 'rm -rf .genir?')"
expect_block "rm -rf .g*o blocked (mid-word glob)" \
  "$(run_cmd 'rm -rf .g*o')"
expect_block "rm -rf .geni[r]o blocked (bracket glob)" \
  "$(run_cmd 'rm -rf .geni[r]o')"
expect_block "rm -rf .?eniro blocked (leading glob)" \
  "$(run_cmd 'rm -rf .?eniro')"
expect_block "rm -rf .geniro{,} blocked (brace, empty alternatives)" \
  "$(run_cmd 'rm -rf .geniro{,}')"
expect_block "rm -rf {.geniro,x} blocked (brace, leading alternative)" \
  "$(run_cmd 'rm -rf {.geniro,x}')"
expect_allow "rm -rf .cache? allowed (glob not covering .geniro)" \
  "$(run_cmd 'rm -rf .cache?')"
expect_allow "rm -rf {build,dist} allowed (brace not covering .geniro)" \
  "$(run_cmd 'rm -rf {build,dist}')"

# ===== T0-8: cd-then-find / cd-then-xargs =====
expect_block "cd .geniro && find . -delete blocked" \
  "$(run_cmd 'cd .geniro && find . -delete')"
expect_block "cd .geniro && find . -type f -exec rm {} + blocked" \
  "$(run_cmd 'cd .geniro && find . -type f -exec rm {} +')"
expect_block "cd .geniro && ls | xargs rm -rf blocked" \
  "$(run_cmd 'cd .geniro && ls | xargs rm -rf')"
expect_block "cd .geniro/instructions && find . -delete blocked (subdir cd)" \
  "$(run_cmd 'cd .geniro/instructions && find . -delete')"
expect_allow "cd src && find . -name x -delete allowed (non-.geniro cd)" \
  "$(run_cmd 'cd src && find . -name x -delete')"
expect_allow "cd .geniro/planning/task-1 && find . -delete allowed (3+ seg)" \
  "$(run_cmd 'cd .geniro/planning/task-1 && find . -delete')"
expect_allow "cd .geniro && find . -name foo allowed (non-destructive)" \
  "$(run_cmd 'cd .geniro && find . -name foo')"
expect_allow "cd .geniro && ls allowed (no xargs)" \
  "$(run_cmd 'cd .geniro && ls')"

# ===== T0-9: the GENIRO_WV_AMBIGUOUS_VAR sentinel is never checked =====
expect_block "D=\$(pwd)/.geniro; rm -rf \$D blocked (non-literal assignment)" \
  "$(run_cmd 'D=$(pwd)/.geniro; rm -rf $D')"
expect_block "P=/tmp/x; P=.geniro; rm -rf \$P blocked (two distinct bindings)" \
  "$(run_cmd 'P=/tmp/x; P=.geniro; rm -rf $P')"
expect_allow "assignment-resolved operand over a non-.geniro word stays allowed" \
  "$(run_cmd 'Q=/tmp/scratch; rm -rf $Q')"

# ===== T0-10: mv -t DIR .geniro (GNU target-directory form) =====
expect_block "mv -t /tmp/trash .geniro blocked" \
  "$(run_cmd 'mv -t /tmp/trash .geniro')"
expect_block "mv --target-directory=/tmp/trash .geniro blocked" \
  "$(run_cmd 'mv --target-directory=/tmp/trash .geniro')"
expect_block "mv -t /tmp/trash .geniro/instructions blocked (subdir source)" \
  "$(run_cmd 'mv -t /tmp/trash .geniro/instructions')"
expect_allow "mv -t /tmp/trash notes.txt allowed (non-.geniro source)" \
  "$(run_cmd 'mv -t /tmp/trash notes.txt')"
expect_block "mv .geniro /tmp/trash still blocked (plain form, no regression)" \
  "$(run_cmd 'mv .geniro /tmp/trash')"

# ===== T0-15: Cursor file-tool Delete payload (no `command` field) =====
mkdir -p "$TMPDIR_BASE/delete-sandbox/.geniro/instructions"
mkdir -p "$TMPDIR_BASE/delete-sandbox/.geniro/planning/task-1"
mkdir -p "$TMPDIR_BASE/delete-sandbox/.geniro/state"
printf 'x\n' > "$TMPDIR_BASE/delete-sandbox/.geniro/instructions/global.md"
printf 'x\n' > "$TMPDIR_BASE/delete-sandbox/.geniro/planning/task-1/notes.md"
printf 'x\n' > "$TMPDIR_BASE/delete-sandbox/.geniro/state/review-findings-state.md"
cd "$TMPDIR_BASE/delete-sandbox" || exit 1

expect_block "Delete file-tool on .geniro (bare) blocked" \
  "$(run_delete "$TMPDIR_BASE/delete-sandbox/.geniro")"
expect_block "Delete file-tool on a top-level subdir blocked" \
  "$(run_delete "$TMPDIR_BASE/delete-sandbox/.geniro/instructions")"
expect_allow "Delete file-tool on a deep task-dir file allowed" \
  "$(run_delete "$TMPDIR_BASE/delete-sandbox/.geniro/planning/task-1/notes.md")"
expect_allow "Delete file-tool on a single state file allowed" \
  "$(run_delete "$TMPDIR_BASE/delete-sandbox/.geniro/state/review-findings-state.md")"
expect_allow "Delete file-tool on a non-.geniro path allowed" \
  "$(run_delete "$TMPDIR_BASE/delete-sandbox/README.md")"
expect_allow "Delete file-tool with no file_path fails open (nothing to check)" \
  "$(jq -nc '{tool_name:"Delete", tool_input:{}}' | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$HOOK" >/dev/null 2>&1; echo $?)"
cd "$TMPDIR_BASE/sandbox" || exit 1

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
