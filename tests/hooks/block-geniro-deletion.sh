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

# Feed a raw JSON payload with jq REMOVED from PATH, exercising the jq-less
# data-loss fallback. FAKEBIN holds symlinks to every tool the fallback needs
# except jq.
FAKEBIN="$TMPDIR_BASE/nojq-bin"
mkdir -p "$FAKEBIN"
for _t in cat grep sed awk tr head printf env bash sh; do
  _s="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_s" "$FAKEBIN/$_t"
done
run_cmd_nojq() {
  printf '%s' "$1" | PATH="$FAKEBIN" bash "$HOOK" >/dev/null 2>&1
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
# Regression: a globbed-filename trailing segment (*.md) wipes the same files as
# the bare-* form and must block too (audit D5b-3 — only bare * was normalized).
expect_block "trailing glob subdir/*.md blocked" "$(run_cmd 'rm -rf .geniro/instructions/*.md')"
expect_allow "deep task-dir/*.md allowed"        "$(run_cmd 'rm -rf .geniro/planning/task-1/*.md')"
# Regression: a NON-recursive glob bulk-delete (rm -f .geniro/<dir>/*) expands to
# every file in the dir — the real Cursor-SCM .geniro/actions/*.md incident form —
# and must block even without -r, which the recursive-only gate previously skipped.
expect_block "rm -f subdir/* (no -r) blocked"    "$(run_cmd 'rm -f .geniro/instructions/*')"
expect_block "rm -f subdir/*.md (no -r) blocked" "$(run_cmd 'rm -f .geniro/actions/*.md')"
expect_block "rm -f .geniro/* (no -r) blocked"   "$(run_cmd 'rm -f .geniro/*')"
# A NON-glob single-file rm -f at any depth stays allowed (the design-allowed
# individual delete); a deep task-dir glob is skill cleanup and stays allowed.
expect_allow "rm -f single file (no -r) allowed" "$(run_cmd 'rm -f .geniro/instructions/global.md')"
expect_allow "rm -f deep task-dir glob allowed"  "$(run_cmd 'rm -f .geniro/planning/task-1/*.tmp')"
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
# xargs rm loses the same content whatever produced the list — find is not required.
expect_block "echo .geniro | xargs rm -rf blocked" "$(run_cmd 'echo .geniro | xargs rm -rf')"
expect_block "ls .geniro/actions | xargs rm blocked" "$(run_cmd 'ls .geniro/actions | xargs rm -f')"
expect_allow "echo .geniro | xargs wc allowed"   "$(run_cmd 'echo .geniro | xargs wc -l')"

# ===== rmdir (T4-11) =====
# rmdir removes only an EMPTY directory, but that is the same NODE-loss shape
# rm -r produces at that segment depth, and it carried no matcher at all.
expect_block "rmdir .geniro (bare) blocked"      "$(run_cmd 'rmdir .geniro')"
expect_block "rmdir .geniro/instructions blocked" "$(run_cmd 'rmdir .geniro/instructions')"
expect_block "find .geniro -exec rmdir blocked"  "$(run_cmd 'find .geniro -type d -exec rmdir {} \;')"
expect_allow "rmdir a deep task-dir subpath allowed" "$(run_cmd 'rmdir .geniro/planning/task-1/sub')"
expect_allow "rmdir an unrelated directory allowed"  "$(run_cmd 'rmdir build/tmp')"

# ===== rsync --delete INTO a .geniro/ path =====
# An empty/partial source mirrored with --delete removes everything the source
# lacks — the same loss as deleting the directory. Same depth rules as rm.
expect_block "rsync --delete into .geniro/ blocked"      "$(run_cmd 'rsync -a --delete /tmp/empty/ .geniro/')"
expect_block "rsync --delete into a top-level subdir blocked" "$(run_cmd 'rsync -a --delete /tmp/empty/ .geniro/instructions/')"
expect_block "rsync --delete-after into a subdir blocked" "$(run_cmd 'rsync -a --delete-after /tmp/empty/ .geniro/actions/')"
expect_allow "rsync --delete into a deep task dir allowed" "$(run_cmd 'rsync -a --delete /tmp/src/ .geniro/planning/task-1/')"
expect_allow "rsync WITHOUT --delete into a subdir allowed" "$(run_cmd 'rsync -a /tmp/src/ .geniro/instructions/')"
expect_allow "rsync --delete FROM .geniro/ allowed"      "$(run_cmd 'rsync -a --delete .geniro/instructions/ /tmp/backup/')"

# ===== interpreter-mediated deletes =====
# A script's delete is not shell syntax, so the rm spans never see it. Same
# depth rules: whole tree and top-level subdirs block, deep paths and per-file
# deletes stay allowed, and a read-only script is untouched.
expect_block "python shutil.rmtree(.geniro) blocked"     "$(run_cmd "python3 -c \"import shutil; shutil.rmtree('.geniro')\"")"
expect_block "python rmtree of a top-level subdir blocked" "$(run_cmd "python3 -c \"import shutil; shutil.rmtree('.geniro/instructions')\"")"
expect_block "python os.rmdir of a state subdir blocked"  "$(run_cmd "python3 -c \"import os; os.rmdir('.geniro/state/review')\"")"
expect_block "node fs.rmSync(.geniro) blocked"           "$(run_cmd "node -e \"require('fs').rmSync('.geniro',{recursive:true})\"")"
expect_block "ruby FileUtils.rm_rf of a subdir blocked"  "$(run_cmd "ruby -e \"FileUtils.rm_rf('.geniro/actions')\"")"
expect_block "python rmtree with an unresolvable target blocked" "$(run_cmd "python3 -c \"import shutil; shutil.rmtree(d)\"; ls .geniro/instructions")"
expect_allow "python rmtree of a deep task dir allowed"  "$(run_cmd "python3 -c \"import shutil; shutil.rmtree('.geniro/planning/task-1')\"")"
expect_allow "python os.remove of a single file allowed" "$(run_cmd "python3 -c \"import os; os.remove('.geniro/planning/task/notes.md')\"")"
expect_allow "python Path.unlink of a single file allowed" "$(run_cmd "python3 -c \"from pathlib import Path; Path('.geniro/state/x.md').unlink()\"")"
expect_allow "python listing .geniro allowed"            "$(run_cmd "python3 -c \"import os; print(os.listdir('.geniro'))\"")"
expect_allow "node reading a .geniro file allowed"       "$(run_cmd "node -e \"console.log(require('fs').readFileSync('.geniro/x.md','utf8'))\"")"
expect_allow "python deleting outside .geniro allowed"   "$(run_cmd "python3 -c \"import shutil; shutil.rmtree('build')\"")"

# ===== git worktree remove =====
expect_block "git worktree remove blocked"      "$(run_cmd 'git worktree remove ../wt')"
# Regression: a quoted -C operand with a space must not leak the subcommand past
# the global-options strip (audit D5b-2).
expect_block "git -C \"<spaced>\" worktree remove blk" "$(run_cmd 'git -C "/my repo" worktree remove ../wt')"

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
# A quoted literal carrying a BACKSLASH-ESCAPED separator is still data. The
# escape spells a BRE alternation, not a command chain, so the whole literal has
# to be blanked — else the tokenizer reads the search pattern as an rm operand.
expect_allow "grep with escaped-alternation naming rm -rf allowed" \
  "$(run_cmd 'grep -c "foo\|rm -rf .geniro/state" file.md')"
expect_allow "single-quoted escaped-alternation naming rm -rf allowed" \
  "$(run_cmd "grep -c 'foo\\|rm -rf .geniro/instructions' file.md")"
expect_allow "sed with escaped-semicolon naming rm -rf allowed" \
  "$(run_cmd 'sed -n "/rm -rf .geniro\;/p" notes.md')"
# The escape neutralization must not hide a REAL destructive command.
expect_block "real rm after an escaped alternation still blocks" \
  "$(run_cmd 'grep -c "a\|b" file.md && rm -rf .geniro/instructions')"
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

# ===== interpreter indirection (sh -c "<payload>") must be inspected =====
expect_block "sh -c rm -rf .geniro blocked"        "$(run_cmd 'sh -c "rm -rf .geniro"')"
expect_block "sh -c subdir rm blocked"             "$(run_cmd 'sh -c "rm -rf .geniro/instructions"')"
expect_allow "sh -c benign command allowed"        "$(run_cmd 'sh -c "echo hello"')"

# ===== eval indirection (eval "<payload>") must be inspected =====
# eval hands its argument to the shell as a command, so the guard re-runs on it.
expect_block "eval rm -rf .geniro blocked"         "$(run_cmd 'eval "rm -rf .geniro"')"
expect_block "eval single-quoted subdir rm blocked" "$(run_cmd "eval 'rm -rf .geniro/instructions/'")"
expect_block "eval inside sh -c blocked"           "$(run_cmd $'sh -c "eval \'rm -rf .geniro\'"')"
expect_allow "eval benign command allowed"         "$(run_cmd 'eval "echo hello"')"
expect_allow "eval ssh-agent idiom allowed"        "$(run_cmd 'eval "$(ssh-agent -s)"')"
# A bulk delete MENTIONED as data (not handed to eval) must stay allowed.
expect_allow "prose mentioning eval rm -rf .geniro/ allowed" \
  "$(run_cmd 'echo "never run eval rm -rf .geniro/ here"')"

# ===== quoted subcommand token must not slip the worktree matcher =====
# A quoted whitespace-free subcommand ("remove") is unquoted before matching, so
# a real quoted worktree removal still blocks; a quoted PROSE mention stays data.
expect_block "git worktree \"remove\" (quoted subcommand) blocked" "$(run_cmd 'git worktree "remove" ../wt')"
expect_allow "prose mentioning git worktree remove allowed"        "$(run_cmd 'echo "to clean up later: git worktree remove ../wt"')"
expect_allow "prose mentioning git add -f .geniro/ allowed"        "$(run_cmd 'git commit -m "docs: explain why git add -f .geniro/ is banned"')"

# ===== heredoc body mentioning a bulk delete is DATA, not a command =====
expect_allow "heredoc body mentioning rm -rf .geniro/ allowed" "$(run_cmd 'cat <<'"'"'EOF'"'"'
rm -rf .geniro/
EOF')"
expect_allow "spaced-tag heredoc body mentioning rm -rf .geniro/ allowed" "$(run_cmd 'cat << EOF
rm -rf .geniro/
EOF')"
# A real bulk delete (unquoted, not in a heredoc body) still blocks after the scrub.
expect_block "real rm -rf .geniro/ still blocks after heredoc scrub" "$(run_cmd 'rm -rf .geniro/')"

# ===== jq-less data-loss fallback: coarse raw scan still blocks the worst =====
expect_block "jqless: rm -rf .geniro still blocked"  "$(run_cmd_nojq '{"tool_input":{"command":"rm -rf .geniro/"}}')"
expect_allow "jqless: benign command fails open"     "$(run_cmd_nojq '{"tool_input":{"command":"ls .geniro/"}}')"

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
