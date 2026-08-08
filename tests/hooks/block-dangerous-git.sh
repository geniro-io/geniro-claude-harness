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

# Feed a raw JSON payload to the hook with jq REMOVED from PATH, to exercise the
# jq-less data-loss fallback. FAKEBIN holds symlinks to every tool the fallback
# needs except jq.
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
# T0-5: the pathspec matcher above only caught a bare `.`/`*` pathspec — the
# no-pathspec force forms discarded the entire working tree unblocked.
expect_block "checkout -f blocked"              "$(run_cmd 'git checkout -f main')"
expect_block "checkout --force blocked"         "$(run_cmd 'git checkout --force main')"
expect_block "switch --discard-changes blocked" "$(run_cmd 'git switch --discard-changes main')"
expect_block "switch -f blocked"                "$(run_cmd 'git switch -f main')"
expect_block "switch --force blocked"           "$(run_cmd 'git switch --force main')"
expect_allow "checkout -b feature/x allowed"    "$(run_cmd 'git checkout -b feature/x')"
expect_allow "switch main allowed"              "$(run_cmd 'git switch main')"
expect_allow "switch -c feature/x allowed"      "$(run_cmd 'git switch -c feature/x')"

# ===== restore mass-discard =====
expect_block "restore . blocked"                "$(run_cmd 'git restore .')"
expect_block "restore --staged . blocked"       "$(run_cmd 'git restore --staged .')"

# ===== reset --hard plumbing equivalent =====
# T0-5: `git read-tree --reset -u HEAD` resets the index and working tree
# exactly like `reset --hard`, but carried no matcher of its own.
expect_block "read-tree --reset -u HEAD blocked" "$(run_cmd 'git read-tree --reset -u HEAD')"

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
# Regression: a QUOTED -C operand (incl. one with a space) must be consumed by the
# global-options strip, not leak the subcommand past it (audit D5b-1 — a quoted
# path defeated every destructive-git guard).
expect_block "git -C \"<path>\" push --force blocked"    "$(run_cmd 'git -C "/tmp/r" push --force')"
expect_block "git -C \"<spaced>\" reset --hard blocked"  "$(run_cmd 'git -C "/tmp/my repo" reset --hard')"
expect_block "git -C '<spaced>' clean -fd blocked"      "$(run_cmd "git -C '/tmp/my repo' clean -fd")"
expect_allow "git -C \"<path>\" status allowed"          "$(run_cmd 'git -C "/tmp/r" status')"

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

# ===== quote / heredoc scrub: destructive pattern as DATA does not block =====
expect_allow "echo mentioning force-push allowed"     "$(run_cmd 'echo "remember to git push --force later"')"
expect_allow "commit -m mentioning checkout allowed"  "$(run_cmd 'git commit -m "git checkout . is dangerous"')"
expect_allow "commit -m mentioning reset --hard allowed" "$(run_cmd "git commit -m 'do not run git reset --hard here'")"
expect_allow "heredoc body mentioning force-push allowed" "$(run_cmd 'cat <<EOF
git push --force origin main
EOF')"
# A real destructive command (unquoted) still blocks after the scrub.
expect_block "real force-push still blocks after scrub" "$(run_cmd 'git push --force origin main')"
expect_block "real bare-dot checkout still blocks after scrub" "$(run_cmd 'git checkout .')"

# ===== push-delete (remote-branch deletion) =====
expect_block "push --delete blocked"            "$(run_cmd 'git push origin --delete feature-x')"
expect_block "push -d blocked"                  "$(run_cmd 'git push origin -d feature-x')"
expect_block "push colon-refspec blocked"       "$(run_cmd 'git push origin :feature-x')"
expect_allow "plain push (no delete) allowed"   "$(run_cmd 'git push origin main')"
expect_allow "push -u origin main allowed"      "$(run_cmd 'git push -u origin main')"
# A src:dst refspec push (not a delete — source side is non-empty) must not block.
expect_allow "push src:dst refspec allowed"     "$(run_cmd 'git push origin main:main')"

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
# push-delete honors its own bypass key.
mkdir -p "$TMPDIR_BASE/bypass-pd/.geniro"
printf '%s\n' '{"allow_patterns":["push-delete"]}' > "$TMPDIR_BASE/bypass-pd/.geniro/safety.json"
cd "$TMPDIR_BASE/bypass-pd" || exit 1
expect_allow "push --delete allowed via push-delete bypass" "$(run_cmd 'git push origin --delete feature-x')"
expect_allow "push :refspec allowed via push-delete bypass" "$(run_cmd 'git push origin :feature-x')"
cd "$TMPDIR_BASE" || exit 1
# Malformed safety.json must fail safe — the guard still blocks.
mkdir -p "$TMPDIR_BASE/badjson/.geniro"
printf '%s\n' '{ this is not valid json' > "$TMPDIR_BASE/badjson/.geniro/safety.json"
cd "$TMPDIR_BASE/badjson" || exit 1
expect_block "malformed safety.json fails safe (force-push still blocked)" "$(run_cmd 'git push --force origin main')"
cd "$TMPDIR_BASE" || exit 1

# ===== quoted destructive flag must not slip the guard =====
# A quoted flag/subcommand token (no internal whitespace) is unquoted before
# matching, so smuggling --force past the guard by quoting it still blocks; a
# quoted PROSE string with whitespace stays data.
expect_block "quoted --force flag blocked"            "$(run_cmd 'git push origin main "--force"')"
expect_block "quoted -f flag blocked"                 "$(run_cmd "git push origin main '-f'")"
expect_allow "prose with quoted whitespace allowed"   "$(run_cmd 'echo "please do not git push --force"')"

# ===== unbalanced apostrophes across a separator must not swallow a real op =====
# A benign apostrophe in prose (can't / don't) must not pair across && and blank
# the force-push sitting between the two quotes.
expect_block "apostrophe-prose around real force-push blocked" \
  "$(run_cmd "echo can't wait && git push --force origin main && echo don't stop")"
expect_allow "apostrophe-prose with no destructive op allowed" \
  "$(run_cmd "echo can't && echo won't && echo shan't")"

# ===== interpreter indirection (sh -c "<payload>") must be inspected =====
# The payload is a command to the inner shell; the guard re-runs on it.
expect_block "sh -c force-push blocked"               "$(run_cmd 'sh -c "git push --force origin main"')"
expect_block "bash -lc reset --hard blocked"          "$(run_cmd 'bash -lc "git reset --hard HEAD~1"')"
expect_block "nested sh -c force-push blocked"         "$(run_cmd $'sh -c "sh -c \'git push --force\'"')"
expect_allow "sh -c benign command allowed"           "$(run_cmd 'sh -c "echo hello world"')"

# ===== eval indirection (eval "<payload>") must be inspected =====
# eval hands its argument to the shell as a command, so the guard re-runs on it.
expect_block "eval force-push blocked"                "$(run_cmd 'eval "git push --force origin main"')"
expect_block "eval single-quoted reset --hard blocked" "$(run_cmd "eval 'git reset --hard HEAD~1'")"
expect_block "eval inside sh -c blocked"              "$(run_cmd $'sh -c "eval \'git push --force\'"')"
expect_allow "eval benign command allowed"            "$(run_cmd 'eval "echo hello world"')"
expect_allow "eval ssh-agent idiom allowed"           "$(run_cmd 'eval "$(ssh-agent -s)"')"
# A dangerous form MENTIONED as data (not handed to eval) must stay allowed.
expect_allow "prose mentioning eval force-push allowed" \
  "$(run_cmd 'echo "never run eval git push --force here"')"

# ===== jq-less data-loss fallback: coarse raw scan still blocks the worst =====
expect_block "jqless: force-push still blocked"       "$(run_cmd_nojq '{"tool_input":{"command":"git push --force"}}')"
expect_block "jqless: reset --hard still blocked"      "$(run_cmd_nojq '{"tool_input":{"command":"git reset --hard"}}')"
expect_allow "jqless: benign command fails open"      "$(run_cmd_nojq '{"tool_input":{"command":"git status"}}')"

# ===== jq PRESENT but payload MALFORMED: must still fail-closed on a raw scan =====
# Distinct from the jqless block above (jq absent, well-formed JSON). Here jq is on
# PATH but the JSON is truncated, so tool_input.command parses empty and the
# top-level `[ -z "$COMMAND" ]` branch's own raw-text scan is what has to catch it.
run_raw() {  # <raw-payload-text>
  printf '%s' "$1" | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "malformed payload with destructive token still blocked" \
  "$(run_raw '{"tool_input":{"command":"git push --force origin main"')"
expect_allow "malformed payload with no destructive token allows" \
  "$(run_raw '{"tool_input":{"command":"git status"')"

# ===== T0-2: ANSI-C quoting ($'...') must not evade the guard =====
# The unquote pass strips a token's outer quote marks but used to leave the `$`
# sigil glued onto the result ($'--force' -> $--force), so the whitespace-
# anchored matchers never anchored. One case per affected pattern ID.
expect_block "push \$'--force' (ANSI-C quote) blocked"  "$(run_cmd "git push \$'--force' origin main")"
expect_block "reset \$'--hard' (ANSI-C quote) blocked"  "$(run_cmd "git reset \$'--hard'")"
expect_block "clean \$'-fd' (ANSI-C quote) blocked"     "$(run_cmd "git clean \$'-fd'")"
expect_block "\$'filter-branch' (ANSI-C quote) blocked" "$(run_cmd "git \$'filter-branch' --tree-filter true HEAD")"

# ===== T0-3 / T4-6: newline must not mask a destructive sibling =====
# Newlines used to be collapsed to spaces before span extraction, so a whole
# multi-line script became ONE span and a leading dry-run flag masked the
# destructive command sitting right after it. Order-independent.
expect_block "clean -n then clean -fd (newline) still blocked" \
  "$(run_cmd $'git clean -n\ngit clean -fd')"
expect_block "clean -fd then clean -n (newline, order flipped) still blocked" \
  "$(run_cmd $'git clean -fd\ngit clean -n')"

# ===== T1-1 / T4-6: newline-separated benign commands must not false-positive =====
# The same newline collapse let a benign SECOND line's content leak into the
# first line's span, so an unrelated flag/token on a following line blocked a
# harmless first command. Newline-separated siblings of the existing span-
# bounding cases above (git reset + chained --hardened flag, chained rm -f).
expect_allow "push then chained tar -f (newline) allowed" \
  "$(run_cmd $'git push origin main\ntar -f a.tar d')"
expect_allow "branch --list then chained gcc -DFOO (newline) allowed" \
  "$(run_cmd $'git branch --list\ngcc -DFOO x.c')"
expect_allow "reset + chained --hardened flag (newline) allowed" \
  "$(run_cmd $'git reset HEAD~1\nnpm run build -- --hardened')"
expect_allow "chained rm -f after push (newline) allowed" \
  "$(run_cmd $'git push origin main\nrm -f stale.txt')"

# ===== T0-4: git push --mirror / --prune are unmatched force/delete spellings =====
# --mirror force-updates and deletes remote refs to match the local repo
# exactly; --prune deletes every remote ref absent locally. Both cause the
# same remote-history loss --force/--delete exist to block.
expect_block "push --mirror blocked" "$(run_cmd 'git push --mirror origin')"
expect_block "push --prune blocked"  "$(run_cmd 'git push --prune origin')"

# ===== T1-3: a `#` comment must not be scanned as a live command =====
# The sibling data-loss guards strip trailing comments before matching; this
# guard had no such pass, so text that never executes still blocked.
expect_allow "commented-out force-push (own line) allowed" \
  "$(run_cmd $'# git push --force\necho hi')"
expect_allow "trailing-comment force-push allowed" \
  "$(run_cmd 'echo hi # git push --force')"
# A real, unquoted, uncommented destructive command still blocks.
expect_block "real force-push still blocks after comment-strip" \
  "$(run_cmd 'git push --force')"

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
