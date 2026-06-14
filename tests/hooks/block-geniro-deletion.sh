#!/usr/bin/env bash
# Smoke test for hooks/block-geniro-deletion.sh (PreToolUse Bash).
#
# Run: bash tests/hooks/block-geniro-deletion.sh
#
# Coverage:
#   - Bulk-deletion patterns block (exit 2): whole-tree rm, top-level subdir rm,
#     per-skill state-subdir rm, find -delete, worktree remove, git add -f.
#   - The multi-arg masking case (a shallow first arg next to a deep second arg)
#     still blocks — the regression that the per-arg evaluation fixed.
#   - Allowed-by-design deletes pass (exit 0): single-file rm -f at any depth,
#     deep 3+ segment trees, single-file state deletes (incl. -rf on a file),
#     non-.geniro paths, `git add` without -f, `git worktree list`.
#   - Empty command fails-open (exit 0).
#   - Per-project bypass via .geniro/safety.json allow_patterns.

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

# ===== rm-geniro-tree (whole tree) =====
expect_block "rm -rf .geniro/ blocked"          "$(run_cmd 'rm -rf .geniro/')"
expect_block "rm -rf .geniro (bare) blocked"    "$(run_cmd 'rm -rf .geniro')"

# ===== rm-geniro-subdir (2-segment top-level category) =====
expect_block "rm -rf .geniro/instructions/ blocked" "$(run_cmd 'rm -rf .geniro/instructions/')"
expect_block "rm -rf .geniro/actions blocked"   "$(run_cmd 'rm -rf .geniro/actions')"

# ===== rm-geniro-state-subdir (3-segment per-skill state dir) =====
expect_block "rm -rf .geniro/state/review/ blocked" "$(run_cmd 'rm -rf .geniro/state/review/')"

# ===== multi-arg masking — either ordering must still block =====
expect_block "multi-arg shallow+deep still blocks" \
  "$(run_cmd 'rm -rf .geniro/instructions/ .geniro/planning/foo/bar')"
expect_block "multi-arg deep+shallow still blocks" \
  "$(run_cmd 'rm -rf .geniro/planning/foo/bar .geniro/instructions/')"

# ===== path-normalization bypass forms (glob / double-slash / .. / dotted-dir) =====
expect_block "trailing glob subdir/* blocked"   "$(run_cmd 'rm -rf .geniro/instructions/*')"
expect_block "trailing glob .geniro/* blocked"  "$(run_cmd 'rm -rf .geniro/*')"
expect_block "double-slash subdir blocked"      "$(run_cmd 'rm -rf .geniro//instructions/')"
expect_block "parent-escape .. blocked"         "$(run_cmd 'rm -rf .geniro/instructions/..')"
expect_block "dotted-DIR state subdir blocked"  "$(run_cmd 'rm -rf .geniro/state/review.bak/')"

# ===== prefixed-path forms (absolute / $PWD / ~ / ..) must not evade =====
expect_block "absolute-path subdir blocked"      "$(run_cmd "rm -rf $TMPDIR_BASE/.geniro/instructions")"
expect_block "PWD-var-prefixed subdir blocked"   "$(run_cmd 'rm -rf "$PWD/.geniro/instructions"')"
expect_block "parent-relative subdir blocked"    "$(run_cmd 'rm -rf ../proj/.geniro/instructions')"
expect_block "tilde-prefixed subdir blocked"     "$(run_cmd 'rm -rf ~/proj/.geniro/actions')"
expect_block "absolute whole tree blocked"       "$(run_cmd "rm -rf $TMPDIR_BASE/.geniro")"
expect_allow "absolute deep 3-seg tree allowed"  "$(run_cmd "rm -rf $TMPDIR_BASE/.geniro/planning/task-dir/")"

# ===== compound commands: only rm's OWN args are segment-gated =====
expect_allow "mkdir .geniro path + unrelated rm -rf allowed" "$(run_cmd 'mkdir -p .geniro/knowledge && rm -rf /tmp/scratch')"
expect_block "command-substitution rm -rf .geniro blocked"   "$(run_cmd 'echo $(rm -rf .geniro)')"
expect_block "command-substitution subdir rm blocked"        "$(run_cmd 'echo $(rm -rf .geniro/instructions)')"
expect_block "/bin/rm -rf .geniro blocked"                   "$(run_cmd '/bin/rm -rf .geniro/')"
expect_block "plain rm span does not mask destructive span"  "$(run_cmd 'rm -f notes.txt; rm -rf .geniro/instructions/')"

# ===== prefix-glob tokens must not evade =====
expect_block "rm -rf .geniro* blocked"           "$(run_cmd 'rm -rf .geniro*')"
expect_block "rm -rf .gen* blocked"              "$(run_cmd 'rm -rf .gen*')"
expect_block "rm -rf .* blocked"                 "$(run_cmd 'rm -rf .*')"
expect_allow "rm -rf .cache* allowed"            "$(run_cmd 'rm -rf .cache*')"

# ===== find ... .geniro ... -delete / -exec rm / xargs rm =====
expect_block "find .geniro -delete blocked"     "$(run_cmd "find .geniro -name '*.md' -delete")"
expect_block "find .geniro -exec rm blocked"    "$(run_cmd 'find .geniro -type f -exec rm {} +')"
expect_block "find .geniro -execdir rm blocked" "$(run_cmd 'find .geniro -name "*.md" -execdir rm {} \;')"
expect_block "find .geniro | xargs rm blocked"  "$(run_cmd 'find .geniro -type f | xargs rm -f')"
expect_block "find .geniro | xargs -0 rm blocked" "$(run_cmd 'find .geniro -type f -print0 | xargs -0 rm')"
expect_allow "find .geniro -print allowed"      "$(run_cmd 'find .geniro -name "*.md" -print')"
expect_allow "find .geniro | xargs grep allowed" "$(run_cmd 'find .geniro -type f | xargs grep -l TODO')"

# ===== git worktree remove =====
expect_block "git worktree remove blocked"      "$(run_cmd 'git worktree remove ../wt')"

# ===== git add -f on .geniro/ =====
expect_block "git add -f .geniro/ blocked"      "$(run_cmd 'git add -f .geniro/actions/foo.md')"
expect_block "git add --force .geniro/ blocked" "$(run_cmd 'git add --force .geniro/actions/foo.md')"

# ===== allowed by design =====
expect_allow "rm -f single file allowed"        "$(run_cmd 'rm -f .geniro/planning/task/notes.md')"
expect_allow "rm -rf deep 3-seg tree allowed"   "$(run_cmd 'rm -rf .geniro/planning/task-dir/')"
expect_allow "rm -rf 4-seg slug tree allowed"   "$(run_cmd 'rm -rf .geniro/state/review/slug-foo/')"
expect_allow "rm -f state file allowed"         "$(run_cmd 'rm -f .geniro/state/review-findings-state.md')"
expect_allow "rm -rf on a state FILE allowed"   "$(run_cmd 'rm -rf .geniro/state/findings.md')"
expect_allow "rm -rf non-.geniro path allowed"  "$(run_cmd 'rm -rf node_modules/')"
expect_allow "git add (no -f) .geniro/ allowed" "$(run_cmd 'git add .geniro/actions/foo.md')"
expect_allow "git worktree list allowed"        "$(run_cmd 'git worktree list')"
expect_allow "empty command fails open"         "$(run_cmd '')"

# ===== quote scrub: rm-as-DATA in another command's string does NOT block, =====
# ===== but a REAL quoted rm operand still blocks. =====
expect_allow "echo mentioning rm -rf .geniro/ allowed"      "$(run_cmd 'echo "do not rm -rf .geniro/"')"
expect_allow "commit -m mentioning rm -rf .geniro allowed"  "$(run_cmd 'git commit -m "remove the rm -rf .geniro stuff"')"
expect_allow "single-quoted echo of rm -rf .geniro allowed" "$(run_cmd "echo 'rm -rf .geniro'")"
# A REAL rm with a quoted operand still blocks — the rm token is outside the quote.
expect_block "real rm -rf .geniro/ (unquoted) still blocks"  "$(run_cmd 'rm -rf .geniro/')"
expect_block "real rm -rf \".geniro/\" (quoted operand) still blocks" "$(run_cmd 'rm -rf ".geniro/"')"
expect_block "real rm -rf '\''.geniro/'\'' (quoted operand) still blocks" "$(run_cmd "rm -rf '.geniro/'")"
expect_block "real rm -rf \".geniro/instructions/\" still blocks" "$(run_cmd 'rm -rf ".geniro/instructions/"')"

# ===== per-project bypass =====
mkdir -p "$TMPDIR_BASE/bypass/.geniro"
printf '%s\n' '{"allow_patterns":["rm-geniro-tree"]}' > "$TMPDIR_BASE/bypass/.geniro/safety.json"
cd "$TMPDIR_BASE/bypass" || exit 1
expect_allow "rm -rf .geniro/ allowed via bypass" "$(run_cmd 'rm -rf .geniro/')"
# A non-bypassed pattern still blocks even with the bypass file present.
expect_block "subdir rm still blocked (not in allowlist)" "$(run_cmd 'rm -rf .geniro/instructions/')"
# Allowlist in an ANCESTOR .geniro/safety.json is honored (walk-up from a subdir).
mkdir -p "$TMPDIR_BASE/bypass/sub/deeper"
cd "$TMPDIR_BASE/bypass/sub/deeper" || exit 1
expect_allow "bypass honored from a nested subdir (walk-up)" "$(run_cmd 'rm -rf .geniro/')"

# Each distinct guard honors its OWN bypass key (not just rm-geniro-tree).
mkdir -p "$TMPDIR_BASE/bypass-find/.geniro"
printf '%s\n' '{"allow_patterns":["find-geniro-delete"]}' > "$TMPDIR_BASE/bypass-find/.geniro/safety.json"
cd "$TMPDIR_BASE/bypass-find" || exit 1
expect_allow "find -delete allowed via find-geniro-delete bypass" "$(run_cmd "find .geniro -name '*.md' -delete")"

mkdir -p "$TMPDIR_BASE/bypass-wt/.geniro"
printf '%s\n' '{"allow_patterns":["worktree-remove-with-state"]}' > "$TMPDIR_BASE/bypass-wt/.geniro/safety.json"
cd "$TMPDIR_BASE/bypass-wt" || exit 1
expect_allow "git worktree remove allowed via worktree bypass" "$(run_cmd 'git worktree remove ../wt')"

mkdir -p "$TMPDIR_BASE/bypass-add/.geniro"
printf '%s\n' '{"allow_patterns":["git-add-force-geniro"]}' > "$TMPDIR_BASE/bypass-add/.geniro/safety.json"
cd "$TMPDIR_BASE/bypass-add" || exit 1
expect_allow "git add -f .geniro/ allowed via git-add-force bypass" "$(run_cmd 'git add -f .geniro/actions/foo.md')"

cd "$TMPDIR_BASE" || exit 1
# Malformed safety.json must fail safe — the guard still blocks.
mkdir -p "$TMPDIR_BASE/badjson/.geniro"
printf '%s\n' '{ this is not valid json' > "$TMPDIR_BASE/badjson/.geniro/safety.json"
cd "$TMPDIR_BASE/badjson" || exit 1
expect_block "malformed safety.json fails safe (tree rm still blocked)" "$(run_cmd 'rm -rf .geniro/')"
cd "$TMPDIR_BASE" || exit 1

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
