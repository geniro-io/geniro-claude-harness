#!/usr/bin/env bash
# Covers scripts/install-cursor.sh when the checkout path contains a single
# quote (T4-54, plugin-audit 2026-10-19).
#
# Run: bash tests/scripts/install-cursor.sh
#
# hooks_ours() rewrites "./cursor/hooks/..." to an absolute path wrapped in
# single quotes. A quote INSIDE the root (`~/O'Brien/checkout`, or a hostile
# directory name) used to end that quoted string early: the rest of the path
# became bare shell words, so the hook either failed to start or ran whatever
# the directory name spelled. tests/cursor/install-cursor.sh covers the space
# case; this suite covers the quote and the injection that rides on it.
#
# HOME is redirected to a temp dir for the whole run; the real profile is never
# touched, and the repo's cursor/ tree is read-only input.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
    pass=$((pass + 1))
  else
    echo "FAIL: $1 (expected '$3', got '$2')" >&2
    fail=$((fail + 1))
  fi
}

# A minimal checkout: the hooks the installer rewrites, the script itself, and
# empty skills/agents trees (the installer links whatever it finds there).
make_root() {  # <root>
  mkdir -p "$1/cursor/skills" "$1/cursor/agents" "$1/scripts"
  cp -R "$REPO_ROOT/cursor/hooks" "$1/cursor/hooks"
  cp "$REPO_ROOT/cursor/hooks.json" "$1/cursor/hooks.json"
  cp "$REPO_ROOT/scripts/install-cursor.sh" "$1/scripts/install-cursor.sh"
}

# --- a root with a single quote ----------------------------------------------
HOME_A="$WORK/home-a"; mkdir -p "$HOME_A"
QUOTE_ROOT="$WORK/O'Brien/checkout"
make_root "$QUOTE_ROOT"

HOME="$HOME_A" bash "$QUOTE_ROOT/scripts/install-cursor.sh" >/dev/null 2>&1; rc=$?
check "install from a quote-containing root exits 0" "$rc" "0"

QUOTE_CMD="$(jq -r '.hooks.beforeShellExecution[0].command' "$HOME_A/.cursor/hooks.json")"
check "the stored command is single-quoted" "$(printf '%s' "$QUOTE_CMD" | cut -c1)" "'"

# Run the stored command the way a shell-based hook runner would. Fed empty
# stdin the shim's no-op path exits 0 with no output; a broken quote shows up as
# "unterminated quoted string" / "not found" and a non-zero rc.
OUT="$(cd "$WORK" && sh -c "$QUOTE_CMD" </dev/null 2>&1)"; RUN_RC=$?
check "the stored command resolves the quote-containing shim path (rc 0, no output)" "$RUN_RC:$OUT" "0:"

# Re-running must not duplicate entries: the escaped path still carries the
# marker the merge keys on.
before="$(jq '[.hooks[][]] | length' "$HOME_A/.cursor/hooks.json")"
HOME="$HOME_A" bash "$QUOTE_ROOT/scripts/install-cursor.sh" >/dev/null 2>&1
check "re-install from the quote-containing root does not duplicate hook entries" \
  "$(jq '[.hooks[][]] | length' "$HOME_A/.cursor/hooks.json")" "$before"

HOME="$HOME_A" bash "$QUOTE_ROOT/scripts/install-cursor.sh" --uninstall >/dev/null 2>&1
check "uninstall removes the quote-root entries" \
  "$(jq '[.hooks[][] | select(.command | test("claude-hook-shim"))] | length' "$HOME_A/.cursor/hooks.json")" "0"

# --- a root whose name is a command injection ----------------------------------
# The directory name closes the quote, runs `touch PWNED`, and reopens one, so
# the unescaped command stays quote-balanced and the injected word really runs.
HOME_B="$WORK/home-b"; mkdir -p "$HOME_B"
INJECT_ROOT="$WORK/it's; touch PWNED; echo 'x/checkout"
make_root "$INJECT_ROOT"

HOME="$HOME_B" bash "$INJECT_ROOT/scripts/install-cursor.sh" >/dev/null 2>&1; rc=$?
check "install from an injection-named root exits 0" "$rc" "0"

INJECT_CMD="$(jq -r '.hooks.beforeShellExecution[0].command' "$HOME_B/.cursor/hooks.json")"
RUN_DIR="$WORK/run-dir"; mkdir -p "$RUN_DIR"
OUT="$(cd "$RUN_DIR" && sh -c "$INJECT_CMD" </dev/null 2>&1)"; RUN_RC=$?
check "the stored command runs the shim, not the directory name (rc 0, no output)" "$RUN_RC:$OUT" "0:"
check "no command smuggled in through the directory name ran" \
  "$([ -e "$RUN_DIR/PWNED" ] && echo created || echo absent)" "absent"

echo "--------------------------------------------------------"
echo "install-cursor (quote root): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
