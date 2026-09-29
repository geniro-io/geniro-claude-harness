#!/usr/bin/env bash
# Smoke test for hooks/block-geniro-force-add.sh (PreToolUse Bash).
#
# Run: bash tests/hooks/block-geniro-force-add.sh
#
# Coverage:
#   - `git add -f` / `--force` / a `--forc` prefix / `git update-index --force`
#     on a .geniro/ path blocks (exit 2), including git global options and
#     mixed-case spellings.
#   - Everything else passes (exit 0): plain `git add`, force-adding a non-.geniro
#     path, prose that mentions the rule (commit message, heredoc body), and the
#     read-only commands the deleted block-geniro-deletion.sh blocked in real
#     transcripts.
#   - Per-project bypass via .geniro/safety.json allow_patterns; a malformed
#     safety.json fails safe.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-geniro-force-add.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

run_cmd() {
  jq -nc --arg c "$1" '{tool_input: {command: $c}}' | bash "$HOOK" >/dev/null 2>&1
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

# Run from a clean tmp dir so no ambient .geniro/safety.json is on the walk-up path.
cd "$TMPDIR_BASE" || exit 1

# ===== force-add on .geniro/ blocks =====
expect_block "git add -f .geniro/ blocked"             "$(run_cmd 'git add -f .geniro/actions/foo.md')"
expect_block "git add --force .geniro/ blocked"        "$(run_cmd 'git add --force .geniro/actions/foo.md')"
expect_block "git add --forc prefix blocked"           "$(run_cmd 'git add --forc .geniro/actions/foo.md')"
expect_block "git add -Af cluster blocked"             "$(run_cmd 'git add -Af .geniro')"
expect_block "quoted .geniro path blocked"             "$(run_cmd 'git add -f ".geniro/actions/foo.md"')"
expect_block "absolute .geniro path blocked"           "$(run_cmd 'git add -f /repo/.geniro/actions/foo.md')"
expect_block "git -C <spaced> add -f blocked"          "$(run_cmd 'git -C "/my repo" add -f .geniro/actions/foo.md')"
expect_block "GIT -C . add -f blocked (uppercase)"     "$(run_cmd 'GIT -C . add -f .geniro/x')"
expect_block "git -c k=v add -f blocked"               "$(run_cmd 'git -c core.x=1 add -f .geniro/x')"
expect_block "second command in a chain blocked"       "$(run_cmd 'git status && git add -f .geniro/x')"
expect_block "update-index --force plumbing blocked"   "$(run_cmd 'git update-index --add --force .geniro/x')"
expect_block "backslash continuation blocked"          "$(run_cmd "$(printf 'git add -f \\\n  .geniro/x')")"

# ===== everything else passes =====
expect_allow "git add without -f allowed"              "$(run_cmd 'git add .geniro/actions/foo.md')"
expect_allow "git add -f on a non-.geniro path allowed" "$(run_cmd 'git add -f build/out.js')"
expect_allow "force-with-lease-ish typo not read as force" "$(run_cmd 'git add --force-with-lease-ish .geniro/x')"
expect_allow "-f after -- is a path, not a flag"       "$(run_cmd 'git add -- -f .geniro-notes.md')"
expect_allow "commit message mentioning the rule allowed" \
  "$(run_cmd 'git commit -m "docs: explain why git add -f .geniro/ is banned"')"
expect_allow ".geniro mention in another command allowed" \
  "$(run_cmd 'echo .geniro/notes.md && git add -f README.md')"
expect_allow "heredoc body mentioning the rule allowed" \
  "$(run_cmd "$(printf 'cat > notes.md <<EOF\nnever git add -f .geniro/x\nEOF')")"
expect_allow "empty command allowed"                   "$(run_cmd '')"

# ===== read-only commands the deleted deletion guard blocked in real transcripts =====
expect_allow "ls under a variable root allowed" \
  "$(run_cmd 'MAIN=/repo; ls $MAIN/.geniro/knowledge/ 2>/dev/null | head')"
expect_allow "du on .geniro dirs allowed" \
  "$(run_cmd 'du -sh .geniro/state .geniro/planning 2>/dev/null')"
expect_allow "state-helper write allowed" \
  "$(run_cmd "$(printf 'source "$CLAUDE_PLUGIN_ROOT/lib/atomic-state-write.sh"; atomic_state_write .geniro/state/review/x/state.md <<EOF\nphase: spawn\nEOF')")"

# ===== per-project bypass =====
mkdir -p "$TMPDIR_BASE/bypass/sub/.git" "$TMPDIR_BASE/bypass/.geniro"
printf '%s\n' '{"allow_patterns":["git-add-force-geniro"]}' > "$TMPDIR_BASE/bypass/.geniro/safety.json"
cd "$TMPDIR_BASE/bypass/sub" || exit 1
expect_allow "bypass honored from a nested subdir (walk-up)" "$(run_cmd 'git add -f .geniro/actions/foo.md')"

mkdir -p "$TMPDIR_BASE/badjson/.geniro"
printf '%s\n' '{ this is not valid json' > "$TMPDIR_BASE/badjson/.geniro/safety.json"
cd "$TMPDIR_BASE/badjson" || exit 1
expect_block "malformed safety.json fails safe" "$(run_cmd 'git add -f .geniro/actions/foo.md')"
cd "$TMPDIR_BASE" || exit 1

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
