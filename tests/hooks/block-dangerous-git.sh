#!/usr/bin/env bash
# Smoke test for hooks/block-dangerous-git.sh (PreToolUse Bash).
#
# Run: bash tests/hooks/block-dangerous-git.sh
#
# Coverage:
#   - Each pattern ID blocks (exit 2) on a positive example.
#   - Normal git workflow (push / soft reset / safe branch delete / single-file
#     checkout-restore / dry-run clean / branch create) is allowed (exit 0).
#   - A -f/--force from a command CHAINED after `git push` (e.g. `&& rm -f`)
#     does not false-positive the force-push matcher.
#   - Empty command fails-open (exit 0).
#   - Per-project bypass via .geniro/safety.json allow_patterns.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-dangerous-git.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Feed a Bash-tool payload to the hook; print its exit code.
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

# ===== force-push-with-lease =====
expect_block "force-with-lease blocked"        "$(run_cmd 'git push --force-with-lease')"
expect_block "force-with-lease w/ remote"       "$(run_cmd 'git push --force-with-lease origin main')"

# ===== force-push =====
expect_block "push --force blocked"             "$(run_cmd 'git push --force')"
expect_block "push -f blocked"                  "$(run_cmd 'git push -f origin main')"
expect_block "push -fu (combined) blocked"      "$(run_cmd 'git push -fu origin main')"

# ===== reset --hard =====
expect_block "reset --hard blocked"             "$(run_cmd 'git reset --hard')"
expect_block "reset --hard HEAD~1 blocked"      "$(run_cmd 'git reset --hard HEAD~1')"

# ===== branch -D / --delete --force (incl. combined short flags) =====
expect_block "branch -D blocked"                "$(run_cmd 'git branch -D feature')"
expect_block "branch -Df (combined) blocked"    "$(run_cmd 'git branch -Df feature')"
expect_block "branch -fD (combined) blocked"    "$(run_cmd 'git branch -fD feature')"
expect_block "branch --delete --force blocked"  "$(run_cmd 'git branch --delete --force feature')"
expect_allow "branch -m (rename, no D) allowed" "$(run_cmd 'git branch -m old new')"

# ===== clean -fd =====
expect_block "clean -fd blocked"                "$(run_cmd 'git clean -fd')"
expect_block "clean -df blocked"                "$(run_cmd 'git clean -df')"
expect_block "clean -f -d blocked"              "$(run_cmd 'git clean -f -d')"
expect_block "clean -fdx (force+ignored) blocked" "$(run_cmd 'git clean -fdx')"

# ===== checkout mass-discard =====
expect_block "checkout -- . blocked"            "$(run_cmd 'git checkout -- .')"
expect_block "checkout -- * blocked"            "$(run_cmd 'git checkout -- *')"

# ===== restore mass-discard =====
expect_block "restore . blocked"                "$(run_cmd 'git restore .')"
expect_block "restore --staged . blocked"       "$(run_cmd 'git restore --staged .')"

# ===== update-ref -d =====
expect_block "update-ref -d blocked"            "$(run_cmd 'git update-ref -d refs/heads/x')"

# ===== filter-branch =====
expect_block "filter-branch blocked"            "$(run_cmd 'git filter-branch --tree-filter true HEAD')"

# ===== allowed (normal workflow) =====
expect_allow "plain push allowed"               "$(run_cmd 'git push origin main')"
expect_allow "push -u (set-upstream) allowed"   "$(run_cmd 'git push -u origin feature')"
expect_allow "reset --soft allowed"             "$(run_cmd 'git reset --soft HEAD~1')"
expect_allow "mixed reset (no --hard) allowed"  "$(run_cmd 'git reset HEAD~1')"
expect_allow "branch -d (safe delete) allowed"  "$(run_cmd 'git branch -d merged-feature')"
expect_allow "clean -n (dry run) allowed"       "$(run_cmd 'git clean -n')"
expect_allow "checkout -b allowed"              "$(run_cmd 'git checkout -b new-feature')"
expect_allow "checkout single file allowed"     "$(run_cmd 'git checkout -- src/file.js')"
expect_allow "restore single file allowed"      "$(run_cmd 'git restore src/file.js')"
expect_allow "chained rm -f after push allowed" "$(run_cmd 'git push origin main && rm -f stale.txt')"
expect_allow "empty command fails open"         "$(run_cmd '')"

# ===== git global options must not evade the guards =====
expect_block "git -C <path> push --force blocked"      "$(run_cmd 'git -C /tmp/r push --force')"
expect_block "git -C <path> reset --hard blocked"      "$(run_cmd 'git -C /tmp/r reset --hard')"
expect_block "git -c k=v push -f blocked"              "$(run_cmd 'git -c user.email=x@y push -f origin main')"
expect_block "git --git-dir=... clean -fd blocked"     "$(run_cmd 'git --git-dir=/srv/repo/.git clean -fd')"
expect_block "git -C <path> branch -D blocked"         "$(run_cmd 'git -C ../other branch -D feature')"
expect_allow "git -C <path> plain push allowed"        "$(run_cmd 'git -C /tmp/r push origin main')"
expect_allow "git -C <path> status allowed"            "$(run_cmd 'git -C /tmp/r status')"

# ===== backslash line-continuation must not evade =====
expect_block "backslash-continued force-push blocked"  "$(run_cmd 'git \
push --force')"

# ===== reset --hard is span-bounded (no cross-command false positive) =====
expect_allow "reset + chained --hardened flag allowed" "$(run_cmd 'git reset HEAD~1 && npm run build -- --hardened')"

# ===== checkout/restore mass-discard without -- =====
expect_block "checkout . (no --) blocked"              "$(run_cmd 'git checkout .')"
expect_block "checkout ./ blocked"                     "$(run_cmd 'git checkout ./')"
expect_block "checkout HEAD -- . blocked"              "$(run_cmd 'git checkout HEAD -- .')"
expect_allow "checkout dotfile allowed"                "$(run_cmd 'git checkout -- .gitignore')"
expect_block "restore ./ blocked"                      "$(run_cmd 'git restore ./')"

# ===== separator abutting the flag (no space) must still block =====
expect_block "reset --hard;chained blocked"            "$(run_cmd 'git reset --hard;git status')"
expect_block "push --force;chained blocked"            "$(run_cmd 'git push --force;echo done')"
expect_block "push -f|piped blocked"                   "$(run_cmd 'git push -f|cat')"
expect_block "checkout .;chained blocked"              "$(run_cmd 'git checkout .;npm start')"
expect_block "restore .&&chained blocked"              "$(run_cmd 'git restore .&&true')"

# ===== update-ref --delete long form =====
expect_block "update-ref --delete blocked"             "$(run_cmd 'git update-ref --delete refs/heads/x')"

# ===== clean dry-run is a preview, not a deletion =====
expect_allow "clean -nfd (dry-run) allowed"            "$(run_cmd 'git clean -nfd')"
expect_allow "clean --dry-run -fd allowed"             "$(run_cmd 'git clean --dry-run -fd')"
expect_block "clean -n && clean -fd still blocked"     "$(run_cmd 'git clean -n && git clean -fd')"

# ===== per-project bypass =====
mkdir -p "$TMPDIR_BASE/bypass/.geniro"
printf '%s\n' '{"allow_patterns":["force-push"]}' > "$TMPDIR_BASE/bypass/.geniro/safety.json"
cd "$TMPDIR_BASE/bypass" || exit 1
expect_allow "force-push allowed via safety.json bypass" "$(run_cmd 'git push --force origin main')"
# A non-bypassed pattern still blocks even with the bypass file present.
expect_block "reset --hard still blocked (not in allowlist)" "$(run_cmd 'git reset --hard')"
# Allowlist in an ANCESTOR .geniro/safety.json is honored (walk-up from a subdir).
mkdir -p "$TMPDIR_BASE/bypass/sub/deeper"
cd "$TMPDIR_BASE/bypass/sub/deeper" || exit 1
expect_allow "bypass honored from a nested subdir (walk-up)" "$(run_cmd 'git push --force origin main')"
cd "$TMPDIR_BASE" || exit 1
# Malformed safety.json must fail safe — the guard still blocks.
mkdir -p "$TMPDIR_BASE/badjson/.geniro"
printf '%s\n' '{ this is not valid json' > "$TMPDIR_BASE/badjson/.geniro/safety.json"
cd "$TMPDIR_BASE/badjson" || exit 1
expect_block "malformed safety.json fails safe (force-push still blocked)" "$(run_cmd 'git push --force origin main')"
cd "$TMPDIR_BASE" || exit 1

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
