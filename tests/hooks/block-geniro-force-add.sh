#!/usr/bin/env bash
# Smoke test for hooks/block-geniro-force-add.sh (PreToolUse Bash|Monitor).
#
# Run: bash tests/hooks/block-geniro-force-add.sh
#
# Coverage:
#   - GIT-PARITY MATRIX: every command spelling is run through real git in a
#     scratch repo whose .gitignore ignores `.geniro/`, and the guard must block
#     (exit 2) exactly when that command leaves an ignored `.geniro/` file in the
#     index. A new bypass spelling is one new matrix row. The matrix also pins the
#     premise of each row (`stage` / `nostage`), so a fixture that stops matching
#     git's real behavior fails loudly instead of passing vacuously.
#   - Literal spellings the matrix cannot run through git (a path that does not
#     exist, an uppercase `GIT`, a `sudo`/`xargs` wrapper): blocked on the words as
#     written, by design.
#   - Everything else passes (exit 0): plain `git add`, force-adding a non-.geniro
#     path, prose that mentions the rule (commit message, heredoc body, an `echo`
#     argument), and the read-only commands the deleted block-geniro-deletion.sh
#     blocked in real transcripts.
#   - Per-project bypass via .geniro/safety.json allow_patterns (walk-up and the
#     linked-worktree fallback to the main checkout); a malformed safety.json fails
#     safe; a missing jq fails open with a loud notice.
#   - The guard keys on tool_input.command, not tool_name, so the Monitor tool
#     (wired in hooks/hooks.json) is checked the same as Bash.

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

# ===== git-parity matrix =====
# The scratch repo ignores .geniro/ the way a real project does. Each row names
# the premise (`stage`: git leaves an ignored .geniro/ file in the index;
# `nostage`: it does not) and the command; the harness checks the premise against
# real git first, then requires the guard to agree with git.
if command -v git >/dev/null 2>&1; then
  PARITY="$TMPDIR_BASE/parity"
  mkdir -p "$TMPDIR_BASE/home"
  git_env() {  # hermetic git: no user config, no global excludes, fixed identity
    env -i HOME="$TMPDIR_BASE/home" XDG_CONFIG_HOME="$TMPDIR_BASE/home" PATH="$PATH" \
      GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
      GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t "$@"
  }
  git_env git init -q "$PARITY" >/dev/null 2>&1
  printf '.geniro/\n' > "$PARITY/.gitignore"
  mkdir -p "$PARITY/.geniro/actions"
  printf 'x\n' > "$PARITY/.geniro/actions/x.md"
  printf 'x\n' > "$PARITY/.geniro/x"
  printf 'x\n' > "$PARITY/README.md"
  BLOB="$(git_env git -C "$PARITY" hash-object -w "$PARITY/README.md")"

  parity() {  # <label> <stage|nostage> <command>
    local label="$1" premise="$2" cmd="$3" staged guard
    git_env git -C "$PARITY" read-tree --empty >/dev/null 2>&1
    ( cd "$PARITY" && git_env bash -c "$cmd" ) >/dev/null 2>&1 </dev/null
    staged="$(git_env git -C "$PARITY" ls-files --cached 2>/dev/null | grep -c '^\.geniro/')"
    git_env git -C "$PARITY" read-tree --empty >/dev/null 2>&1
    if { [ "$premise" = stage ] && [ "$staged" -gt 0 ]; } || { [ "$premise" = nostage ] && [ "$staged" -eq 0 ]; }; then
      guard="$(cd "$PARITY" && run_cmd "$cmd")"
      if [ "$premise" = stage ]; then
        expect_block "parity: $label (git stages an ignored .geniro/ file)" "$guard"
      else
        expect_allow "parity: $label (git stages nothing under .geniro/)" "$guard"
      fi
    else
      fail "parity fixture: $label — expected git to $premise, but $staged .geniro/ file(s) were staged"
    fi
  }

  P="$PARITY"
  # -- the force flag, every spelling
  parity "git add -f"                       stage   'git add -f .geniro/actions/x.md'
  parity "git add --force"                  stage   'git add --force .geniro/actions/x.md'
  parity "git add --forc prefix"            stage   'git add --forc .geniro/actions/x.md'
  parity "git add --f prefix"               stage   'git add --f .geniro/actions/x.md'
  parity "git add -Af short-flag cluster"   stage   'git add -Af .geniro'
  parity "git add -f after another flag"    stage   'git add -v -f .geniro/actions/x.md'
  parity "git add -f -- <path>"             stage   'git add -f -- .geniro/actions/x.md'
  parity "quoted path"                      stage   'git add -f ".geniro/actions/x.md"'
  parity "single-quoted path"               stage   "git add -f '.geniro/actions/x.md'"
  parity "absolute path"                    stage   "git add -f $P/.geniro/actions/x.md"
  parity "directory path"                   stage   'git add -f .geniro/'
  parity "git -c k=v add -f"                stage   'git -c core.x=1 add -f .geniro/x'
  parity "git -C . add -f"                  stage   'git -C . add -f .geniro/x'
  parity "backslash continuation"           stage   "$(printf 'git add -f \\\n  .geniro/x')"
  # -- T0-2: stage is git's built-in synonym for add
  parity "git stage -f"                     stage   'git stage -f .geniro/actions/x.md'
  parity "git stage --force"                stage   'git stage --force .geniro/actions/x.md'
  parity "git stage without -f"             nostage 'git stage .geniro/actions/x.md'
  # -- T0-1: update-index stages with --add, not --force (git rejects that flag)
  parity "update-index --add"               stage   'git update-index --add .geniro/actions/x.md'
  parity "update-index --ad prefix"         stage   'git update-index --ad .geniro/actions/x.md'
  parity "update-index --add --cacheinfo (comma form)"  stage "git update-index --add --cacheinfo 100644,$BLOB,.geniro/actions/y.md"
  parity "update-index --add --cacheinfo (three words)" stage "git update-index --add --cacheinfo 100644 $BLOB .geniro/actions/y.md"
  parity "update-index --add on a non-.geniro path"     nostage 'git update-index --add README.md'
  parity "update-index --force is a git usage error"    nostage 'git update-index --force .geniro/actions/x.md'
  # -- T0-3: the -C value names the .geniro directory
  parity "git -C .geniro add -f <relative>" stage   'git -C .geniro add -f actions/x.md'
  parity "git -C .geniro/ add -f"           stage   'git -C .geniro/ add -f actions/x.md'
  parity "git -C .geniro/actions add -f"    stage   'git -C .geniro/actions add -f x.md'
  parity "git -C \"<abs>/.geniro\" add -f"  stage   "git -C \"$P/.geniro\" add -f actions/x.md"
  parity "git -C .geniro add (no -f)"       nostage 'git -C .geniro add actions/x.md'
  parity "git -C . add -f on a non-.geniro path" nostage 'git -C . add -f README.md'
  # -- T0-4: pathspec magic hides the leading `.geniro` behind `:(…)`
  parity "pathspec :(top)"                  stage   "git add -f ':(top).geniro/actions/x.md'"
  parity "pathspec :(top,glob)"             stage   "git add -f ':(top,glob).geniro/**'"
  parity "pathspec :(top) double-quoted"    stage   'git add -f ":(top).geniro/actions/x.md"'
  parity "pathspec :/ top shorthand"        stage   "git add -f ':/.geniro/actions/x.md'"
  parity "pathspec :(exclude) of .geniro"   nostage "git add -f ':(exclude).geniro' README.md"
  parity "pathspec :! exclude of .geniro"   nostage "git add -f ':!.geniro' README.md"
  parity "pathspec :^ exclude of .geniro"   nostage "git add -f ':^.geniro' README.md"
  # -- T0-5: heredoc detection must not swallow the lines after it
  parity "hyphenated heredoc tag, force-add after it" stage \
    "$(printf 'cat >/dev/null <<END-NOTE\nbody\nEND-NOTE\ngit add -f .geniro/actions/x.md')"
  parity "arithmetic shift is not a heredoc" stage \
    "$(printf 'echo $((1<<n))\ngit add -f .geniro/actions/x.md')"
  parity "quoted <<EOF in an argument is not a heredoc" stage \
    "$(printf 'echo "<<EOF"\ngit add -f .geniro/actions/x.md')"
  parity "here-string is not a heredoc" stage \
    "$(printf 'cat <<<word >/dev/null\ngit add -f .geniro/actions/x.md')"
  parity "quoted heredoc tag, force-add after it" stage \
    "$(printf 'cat >/dev/null <<"STOP"\nbody\nSTOP\ngit add -f .geniro/actions/x.md')"
  parity "backslash heredoc tag, force-add after it" stage \
    "$(printf 'cat >/dev/null <<\\STOP\nbody\nSTOP\ngit add -f .geniro/actions/x.md')"
  parity "two heredocs on one line, force-add after both" stage \
    "$(printf 'cat <<A >/dev/null; cat <<B >/dev/null\nbody a\nA\nbody b\nB\ngit add -f .geniro/actions/x.md')"
  parity "force-add on the heredoc command line itself" stage \
    "$(printf 'cat <<EOF >/dev/null && git add -f .geniro/actions/x.md\nbody\nEOF')"
  parity "force-add inside a hyphenated heredoc body" nostage \
    "$(printf 'cat >/dev/null <<END-NOTE\nnever git add -f .geniro/actions/x.md\nEND-NOTE')"
  parity "force-add inside a heredoc body" nostage \
    "$(printf 'cat >/dev/null <<EOF\nnever git add -f .geniro/actions/x.md\nEOF')"
  parity "force-add inside a <<- heredoc body, tab-indented tag" nostage \
    "$(printf 'cat >/dev/null <<-EOF\n\tnever git add -f .geniro/actions/x.md\n\tEOF')"
  parity "force-add inside a quoted-tag heredoc body" nostage \
    "$(printf "cat >/dev/null <<'EOF'\nnever git add -f .geniro/actions/x.md\nEOF")"
  # -- T4-59: `git` counts only where a command word can stand
  parity "echo of the words is not an invocation"   nostage 'echo git add -f .geniro/x'
  parity "printf of the words is not an invocation" nostage "printf '%s\n' git add -f .geniro/x"
  parity "comment after a command"                  nostage 'git status # git add -f .geniro/x'
  parity "grep for the words"                       nostage 'grep -rn git .geniro 2>/dev/null; true'
  parity "env assignment before git"                stage   'GIT_X=1 git add -f .geniro/actions/x.md'
  parity "path-qualified git"                       stage   "$(command -v git) add -f .geniro/actions/x.md"
  parity "backslash-escaped git"                    stage   '\git add -f .geniro/actions/x.md'
  parity "quoted git word"                          stage   '"git" add -f .geniro/actions/x.md'
  parity "command git"                              stage   'command git add -f .geniro/actions/x.md'
  parity "env git"                                  stage   'env GIT_X=1 git add -f .geniro/actions/x.md'
  parity "time git"                                 stage   'time git add -f .geniro/actions/x.md'
  parity "git after &&"                             stage   'git status && git add -f .geniro/actions/x.md'
  parity "git after ;"                              stage   'git status; git add -f .geniro/actions/x.md'
  parity "git after ||"                             stage   'false || git add -f .geniro/actions/x.md'
  parity "git after a pipe"                         stage   'true | git add -f .geniro/actions/x.md'
  parity "git in a subshell"                        stage   '(git add -f .geniro/actions/x.md)'
  parity "git in command substitution"              stage   'x=$(git add -f .geniro/actions/x.md)'
  parity "git in backticks"                         stage   'x=`git add -f .geniro/actions/x.md`'
  parity "git in a brace group"                     stage   '{ git add -f .geniro/actions/x.md; }'
  parity "git after then"                           stage   'if true; then git add -f .geniro/actions/x.md; fi'
  parity "git after do"                             stage   'for i in 1; do git add -f .geniro/actions/x.md; done'
  parity "git after a negation"                     stage   '! git add -f .geniro/actions/x.md'
  parity "git after a leading redirection"          stage   '2>/dev/null git add -f .geniro/actions/x.md'
  # -- the allowed controls
  parity "git add without -f"                       nostage 'git add .geniro/actions/x.md'
  parity "git add -f on a non-.geniro path"         nostage 'git add -f README.md'
  parity "commit message mentioning the rule"       nostage 'git commit -m "docs: never git add -f .geniro/x"'
  parity "single-quoted message mentioning the rule" nostage "git commit -m 'docs: never git add -f .geniro/x'"
  parity "ls under .geniro"                         nostage 'ls .geniro/actions'
  parity "git status mentioning .geniro"            nostage 'git status --short .geniro'
else
  echo "SKIP: git-parity matrix — git unavailable"
fi

# ===== literal spellings the matrix cannot run through git =====
# The guard reads the words as written; these are blocked on the words alone.
expect_block "git -C <spaced> add -f blocked"          "$(run_cmd 'git -C "/my repo" add -f .geniro/actions/foo.md')"
expect_block "GIT -C . add -f blocked (uppercase)"     "$(run_cmd 'GIT -C . add -f .geniro/x')"
expect_block "absolute .geniro path blocked"           "$(run_cmd 'git add -f /repo/.geniro/actions/foo.md')"
expect_block "second command in a chain blocked"       "$(run_cmd 'git status && git add -f .geniro/x')"
expect_block "-C value: separate word, quoted"         "$(run_cmd 'git -C ".geniro" add -f actions/x.md')"
expect_block "-C value: uppercase .GENIRO"             "$(run_cmd 'git -C .GENIRO add -f actions/x.md')"
expect_block "--work-tree=<.geniro> value blocked"     "$(run_cmd 'git --work-tree=.geniro add -f actions/x.md')"
expect_block "--work-tree <.geniro> value blocked"     "$(run_cmd 'git --work-tree .geniro add -f actions/x.md')"
expect_block "--git-dir=<.geniro> value blocked"       "$(run_cmd 'git --git-dir=.geniro/x.git add -f x')"
expect_block "--git-dir <.geniro> value blocked"       "$(run_cmd 'git --git-dir .geniro/x.git add -f x')"
expect_block "update-index --add --force blocked (git rejects --force; --add alone stages)" "$(run_cmd 'git update-index --add --force .geniro/x')"
expect_block "update-index --cacheinfo blocked"        "$(run_cmd 'git update-index --cacheinfo 100644,abc123,.geniro/x')"
expect_block "update-index --index-info from .geniro"  "$(run_cmd 'git update-index --index-info < .geniro/idx.txt')"
expect_block "pathspec magic inside a longer chain"    "$(run_cmd "git add README.md && git add -f ':(top).geniro/x' && git status")"
expect_block "pathspec magic with a closing paren in the chain" "$(run_cmd "(git add -f ':(top).geniro/x')")"
expect_block "pathspec magic holding a space, inside quotes" "$(run_cmd "git add -f ':(top, glob).geniro/**'")"
expect_block "sudo git add -f"                         "$(run_cmd 'sudo git add -f .geniro/x')"
expect_block "sudo -u <user> git add -f"               "$(run_cmd 'sudo -u root git add -f .geniro/x')"
expect_block "timeout <n> git add -f"                  "$(run_cmd 'timeout 5 git add -f .geniro/x')"
expect_block "xargs git add -f"                        "$(run_cmd 'xargs git add -f .geniro/x')"
expect_block "xargs -n1 git add -f"                    "$(run_cmd 'xargs -n1 git add -f .geniro/x')"
expect_block "eval git add -f (unquoted)"              "$(run_cmd 'eval git add -f .geniro/x')"
expect_block "nohup git add -f"                        "$(run_cmd 'nohup git add -f .geniro/x')"
expect_block "redirect word before git"                "$(run_cmd '> /dev/null git add -f .geniro/x')"
expect_block "an unclosed heredoc is scanned, not dropped" \
  "$(run_cmd "$(printf 'cat <<EOF >/dev/null\ngit add -f .geniro/actions/x.md')")"
expect_block "an unclosed arithmetic << is scanned, not dropped" \
  "$(run_cmd "$(printf 'echo $((1<<n))\nnotes\ngit add -f .geniro/x')")"
expect_block "a heredoc closed by the wrong tag is scanned" \
  "$(run_cmd "$(printf 'cat <<END-NOTE >/dev/null\nbody\nEND\ngit add -f .geniro/x')")"

# ===== everything else passes =====
expect_allow "force-with-lease-ish typo not read as force" "$(run_cmd 'git add --force-with-lease-ish .geniro/x')"
expect_allow "-f after -- is a path, not a flag"       "$(run_cmd 'git add -- -f .geniro-notes.md')"
expect_allow "update-index --force alone is no staging form" "$(run_cmd 'git update-index --force .geniro/x')"
expect_allow "update-index without --add allowed"      "$(run_cmd 'git update-index --refresh .geniro/x')"
expect_allow "git -c k=.geniro value is not a path"    "$(run_cmd 'git -c core.hooksPath=.geniro add -f README.md')"
expect_allow "a subcommand other than add is not a force-add" "$(run_cmd 'git commit -f .geniro/x')"
expect_allow ".geniro mention in another command allowed" \
  "$(run_cmd 'echo .geniro/notes.md && git add -f README.md')"
expect_allow "echo of a force-add allowed"             "$(run_cmd 'echo git add -f .geniro/x')"
expect_allow "echo with git after a pipe-free redirect allowed" "$(run_cmd 'echo git add -f .geniro/x > notes.txt')"
expect_allow "cat of a file named git allowed"         "$(run_cmd 'cat git add -f .geniro/x')"
expect_allow "man page lookup allowed"                 "$(run_cmd 'man git-add .geniro')"
expect_allow "empty command allowed"                   "$(run_cmd '')"
expect_allow "heredoc body mentioning the rule allowed" \
  "$(run_cmd "$(printf 'cat > notes.md <<EOF\nnever git add -f .geniro/x\nEOF')")"
expect_allow "hyphenated-tag heredoc body allowed" \
  "$(run_cmd "$(printf 'cat > notes.md <<END-NOTE\nnever git add -f .geniro/x\nEND-NOTE')")"
expect_allow "two heredoc bodies allowed" \
  "$(run_cmd "$(printf 'cat <<A >a.md; cat <<B >b.md\ngit add -f .geniro/x\nA\ngit add -f .geniro/y\nB')")"
expect_allow "commit message mentioning the rule allowed" \
  "$(run_cmd 'git commit -m "docs: explain why git add -f .geniro/ is banned"')"

# ===== read-only commands the deleted deletion guard blocked in real transcripts =====
expect_allow "ls under a variable root allowed" \
  "$(run_cmd 'MAIN=/repo; ls $MAIN/.geniro/knowledge/ 2>/dev/null | head')"
expect_allow "du on .geniro dirs allowed" \
  "$(run_cmd 'du -sh .geniro/state .geniro/planning 2>/dev/null')"
expect_allow "state-helper write allowed" \
  "$(run_cmd "$(printf 'source "$CLAUDE_PLUGIN_ROOT/lib/atomic-state-write.sh"; atomic_state_write .geniro/state/review/x/state.md <<EOF\nphase: spawn\nEOF')")"

# ===== the guard keys on tool_input.command, so every shell-executing tool is checked =====
for TOOL in Bash Monitor; do
  rc=$(jq -nc --arg t "$TOOL" --arg c 'git add -f .geniro/actions/x.md' '{tool_name: $t, tool_input: {command: $c}}' \
         | bash "$HOOK" >/dev/null 2>&1; echo $?)
  expect_block "tool_name $TOOL: force-add blocked" "$rc"
done

# ===== block message names the bypass =====
MSG="$(printf '%s' '{"tool_input":{"command":"git add -f .geniro/x"}}' | bash "$HOOK" 2>&1 >/dev/null)"
if printf '%s' "$MSG" | grep -q 'git-add-force-geniro' && printf '%s' "$MSG" | grep -q 'gitignore'; then
  pass "block message names the .gitignore negation and the bypass token"
else
  fail "block message missing the .gitignore hint or the bypass token: $MSG"
fi

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

# ===== bypass from a linked worktree =====
# A linked worktree never carries the gitignored .geniro/, so the allowlist lives
# in the main checkout and the guard finds it through the git common dir.
if command -v git >/dev/null 2>&1; then
  WT_MAIN="$TMPDIR_BASE/wt-main"
  WT_LINKED="$TMPDIR_BASE/wt-linked"
  WT_PLAIN_MAIN="$TMPDIR_BASE/wt-plain-main"
  WT_PLAIN_LINKED="$TMPDIR_BASE/wt-plain-linked"
  wt_setup() {  # <main> <linked>
    git_env git init -q "$1" >/dev/null 2>&1
    git_env git -C "$1" commit -q --allow-empty -m init >/dev/null 2>&1
    git_env git -C "$1" worktree add -q "$2" >/dev/null 2>&1
  }
  wt_setup "$WT_MAIN" "$WT_LINKED"
  mkdir -p "$WT_MAIN/.geniro"
  printf '%s\n' '{"allow_patterns":["git-add-force-geniro"]}' > "$WT_MAIN/.geniro/safety.json"
  wt_setup "$WT_PLAIN_MAIN" "$WT_PLAIN_LINKED"
  if [ -f "$WT_LINKED/.git" ] && [ ! -e "$WT_LINKED/.geniro" ]; then
    cd "$WT_LINKED" || exit 1
    expect_allow "bypass in the main checkout honored from a linked worktree" "$(run_cmd 'git add -f .geniro/actions/foo.md')"
    cd "$WT_PLAIN_LINKED" || exit 1
    expect_block "a linked worktree with no safety.json anywhere still blocks" "$(run_cmd 'git add -f .geniro/actions/foo.md')"
    cd "$TMPDIR_BASE" || exit 1
  else
    fail "linked-worktree fixture: git worktree add did not produce a linked checkout without .geniro/"
  fi
else
  echo "SKIP: linked-worktree bypass — git unavailable"
fi

# ===== jq missing: fail open, loudly =====
# A guard that is not running must say so; a silent exit 0 would leave the user
# believing git add -f on .geniro/ is still being checked.
NOJQ_BIN="$TMPDIR_BASE/nojq-bin"
mkdir -p "$NOJQ_BIN"
CAT_PATH="$(command -v cat 2>/dev/null || echo "")"
if [ -n "$CAT_PATH" ]; then
  ln -sf "$CAT_PATH" "$NOJQ_BIN/cat"
  NOJQ_OUT="$(printf '%s' '{"tool_input":{"command":"git add -f .geniro/x"}}' | PATH="$NOJQ_BIN" "$BASH" "$HOOK" 2>/dev/null)"
  NOJQ_RC=$?
  if [ "$NOJQ_RC" -eq 0 ] && printf '%s' "$NOJQ_OUT" | grep -q 'force-add guard inactive: jq not found' \
     && printf '%s' "$NOJQ_OUT" | grep -q '"systemMessage"'; then
    pass "jq missing: exit 0 with a systemMessage saying the guard is inactive"
  else
    fail "jq missing: expected exit 0 and an inactivity systemMessage, got rc=$NOJQ_RC out=$NOJQ_OUT"
  fi
else
  echo "SKIP: jq-missing notice — cat not found to stub PATH"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
