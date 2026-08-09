#!/usr/bin/env bash
# Smoke test for hooks/enforce-tdd-order.sh (PreToolUse Edit|Write|MultiEdit, hard-block in RED).
#
# Run: bash tests/hooks/enforce-tdd-order.sh
#
# Coverage:
#   - No TDD state file → not opted in → allow.
#   - RED phase blocks production-code edits (Edit AND MultiEdit), allows test files.
#   - Test-substring-but-not-a-test (contestant.ts) is treated as production → blocked.
#   - GREEN / IDLE phase → allow production.
#   - safety.json tdd-order bypass.
#   - Missing file_path fails-open.
#
# Uses an isolated git repo so the branch slug (and thus the state-file path) is deterministic.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/enforce-tdd-order.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }
expect_block() { if [ "$2" = "2" ]; then pass "$1"; else fail "$1 (expected exit=2, got exit=$2)"; fi; }
expect_allow() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1 (expected exit=0, got exit=$2)"; fi; }

run_edit() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, new_string: "x"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
run_multiedit() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, edits: [{old_string: "a", new_string: "b"}]}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
# Bash-form payload: the command writes a file via heredoc / redirect / tee. The
# Bash branch extracts the write target and applies the same test-vs-production
# classification as the Edit path.
run_bash() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

# Isolated git repo so `git branch --show-current` (the slug source) is deterministic.
GITREPO="$TMPDIR_BASE/repo"
mkdir -p "$GITREPO"
cd "$GITREPO" || exit 1
git init -q
git checkout -q -b tddbranch
SLUG="tddbranch"
STATE_FILE=".geniro/state/tdd/state-${SLUG}.md"
mkdir -p "$(dirname "$STATE_FILE")"
write_phase() { printf '## phase\n%s\n' "$1" > "$STATE_FILE"; }

# ===== No state file → not opted in → allow =====
rm -f "$STATE_FILE"
expect_allow "no TDD state file → production edit allowed" "$(run_edit "$GITREPO/src/app.js")"

# ===== RED phase =====
write_phase RED
expect_block "RED: production file blocked"            "$(run_edit "$GITREPO/src/app.js")"
expect_block "RED: production file blocked (MultiEdit)" "$(run_multiedit "$GITREPO/src/app.js")"
expect_allow "RED: *.test.js allowed"                  "$(run_edit "$GITREPO/src/app.test.js")"
expect_allow "RED: tests/ dir allowed"                 "$(run_edit "$GITREPO/tests/app.js")"
expect_block "RED: 'contestant.ts' (test-substring, not a test) blocked" "$(run_edit "$GITREPO/src/contestant.ts")"

# ===== RED: Edit/Write branch honors the same non-production exemption as Bash =====
# The Bash branch calls is_non_production_target before is_test_file; the
# Edit/Write/MultiEdit/NotebookEdit branch must too, or the TDD orchestrator's own
# .geniro/state/tdd/ write (via Edit/Write, not just Bash mktemp+mv) hard-blocks.
expect_allow "RED: Edit under .geniro/state/tdd/ allowed (orchestrator state)" \
  "$(run_edit "$GITREPO/.geniro/state/tdd/state-${SLUG}.md")"
expect_allow "RED: Edit under dist/ (build output) allowed" \
  "$(run_edit "$GITREPO/dist/app.js")"
expect_allow "RED: Edit under node_modules/ allowed" \
  "$(run_edit "$GITREPO/node_modules/pkg/index.js")"

# ===== GREEN / IDLE → allow production =====
write_phase GREEN
expect_allow "GREEN: production file allowed"          "$(run_edit "$GITREPO/src/app.js")"
write_phase IDLE
expect_allow "IDLE: production file allowed"           "$(run_edit "$GITREPO/src/app.js")"

# ===== RED enforced from a subdirectory cwd (state path is root-resolved) =====
write_phase RED
mkdir -p "$GITREPO/src/deep"
cd "$GITREPO/src/deep" || exit 1
expect_block "RED from subdir cwd: production file blocked" "$(run_edit "$GITREPO/src/app.js")"
cd "$GITREPO" || exit 1

# ===== safety.json tdd-order bypass =====
write_phase RED
mkdir -p "$GITREPO/.geniro"
echo '{"allow_patterns": ["tdd-order"]}' > "$GITREPO/.geniro/safety.json"
expect_allow "RED + tdd-order bypass: production allowed" "$(run_edit "$GITREPO/src/app.js")"
rm -f "$GITREPO/.geniro/safety.json"

# ===== Missing file_path → allow =====
expect_allow "missing file_path → allow" "$(echo '{"tool_input": {}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"

# ===== Bash branch: shell-side writes are gated like Edits during RED =====
write_phase RED
expect_block "RED: Bash heredoc into production src/app.js blocked" \
  "$(run_bash "$(printf 'cat > %s/src/app.js <<EOF\nconst x = 1;\nEOF\n' "$GITREPO")")"
expect_allow "RED: Bash heredoc into test file src/app.test.js allowed" \
  "$(run_bash "$(printf 'cat > %s/src/app.test.js <<EOF\ntest()\nEOF\n' "$GITREPO")")"
expect_block "RED: Bash redirect into production app.py blocked" \
  "$(run_bash "printf abc > $GITREPO/app.py")"
expect_allow "RED: Bash redirect into tests/ dir allowed" \
  "$(run_bash "printf abc > $GITREPO/tests/helper.js")"
# A bash command whose only write target is a pseudo-device (2>/dev/null) is not
# production source — allowed, so ordinary RED-phase commands aren't surprised.
expect_allow "RED: Bash 2>/dev/null only (no production write) allowed" \
  "$(run_bash 'pytest 2>/dev/null')"
# The TDD orchestrator's own RED-phase state write lands under .geniro/ — skipped,
# else the mktemp+mv that advances the cycle would deadlock.
expect_allow "RED: Bash write under .geniro/ allowed (orchestrator state)" \
  "$(run_bash "mv /tmp/x $GITREPO/.geniro/state/tdd/state-${SLUG}.md")"
# The exemption must anchor on `.geniro` as a whole path SEGMENT, not merely as
# a substring suffix — a production directory that happens to END in "geniro"
# (my.geniro/) is not the state tree and must still be gated during RED.
expect_block "RED: Bash write to a dir merely ending in 'geniro' (not a segment) blocked" \
  "$(run_bash "printf x > $GITREPO/my.geniro/app.js")"
expect_allow "RED: Bash read-only command (no write target) allowed" \
  "$(run_bash "cat $GITREPO/src/app.js | grep foo")"
# Outside RED, Bash writes to production are allowed.
write_phase GREEN
expect_allow "GREEN: Bash heredoc into production allowed" \
  "$(run_bash "$(printf 'cat > %s/src/app.js <<EOF\nx\nEOF\n' "$GITREPO")")"
# ===== RED: additional Bash write vectors are gated like Edits =====
write_phase RED
expect_block "RED: truncate on production src blocked" \
  "$(run_bash "truncate -s 0 $GITREPO/src/app.js")"
expect_block "RED: shred on production src blocked" \
  "$(run_bash "shred -u $GITREPO/src/app.py")"
expect_block "RED: install into production src blocked" \
  "$(run_bash "install -m 644 /tmp/x $GITREPO/src/app.ts")"
expect_block "RED: ln -sf over production src blocked" \
  "$(run_bash "ln -sf /tmp/x $GITREPO/src/app.rb")"
expect_allow "RED: truncate on a test file allowed" \
  "$(run_bash "truncate -s 0 $GITREPO/src/app.test.js")"
expect_allow "RED: shred on a scratch (non-production, /dev) allowed" \
  "$(run_bash 'dd if=/dev/zero of=/dev/null')"
# T4-8: this guard carries the same sed -i / cp / rsync / dd-of= write vectors
# as file-protection.sh but had no BLOCK assertion for any of them — only a
# /dev/null ALLOW control for dd exercised that vector at all.
expect_block "RED: sed -i on production src blocked" \
  "$(run_bash "sed -i.bak 's/a/b/' $GITREPO/src/app.js")"
expect_allow "RED: sed -i on a test file allowed" \
  "$(run_bash "sed -i.bak 's/a/b/' $GITREPO/src/app.test.js")"
expect_block "RED: cp onto production src blocked" \
  "$(run_bash "cp /tmp/x $GITREPO/src/app.js")"
expect_allow "RED: cp FROM production src (read) allowed" \
  "$(run_bash "cp $GITREPO/src/app.js /tmp/inspect.js")"
expect_block "RED: rsync destination onto production src blocked" \
  "$(run_bash "rsync -a /tmp/src/ $GITREPO/src/app.js")"
expect_allow "RED: rsync destination onto a test file allowed" \
  "$(run_bash "rsync -a /tmp/src/ $GITREPO/src/app.test.js")"
expect_block "RED: dd of= onto production src blocked" \
  "$(run_bash "dd if=/dev/zero of=$GITREPO/src/app.js")"

# ===== T0 #3/#4 (2026-08-07 audit): a trailing token after the real
# destination must not displace it in the cp/mv/install/rsync/ln/ed/sponge
# "last non-flag token" scan — 2>/dev/null is the single most common shell
# idiom, so this is reachable by accident, not only adversarially. =====
expect_block "RED: cp onto production src with trailing 2>/dev/null blocked" \
  "$(run_bash "cp /tmp/x $GITREPO/src/app.js 2>/dev/null")"
expect_block "RED: install into production src with trailing 2>/dev/null blocked" \
  "$(run_bash "install -m 644 /tmp/x $GITREPO/src/app.ts 2>/dev/null")"
expect_block "RED: ln -sf over production src with trailing 2>/dev/null blocked" \
  "$(run_bash "ln -sf /tmp/x $GITREPO/src/app.rb 2>/dev/null")"
expect_block "RED: rsync destination onto production src with trailing 2>/dev/null blocked" \
  "$(run_bash "rsync -a /tmp/src/ $GITREPO/src/app.js 2>/dev/null")"
expect_block "RED: ed onto production src with trailing stdin redirect blocked" \
  "$(run_bash "ed $GITREPO/src/app.js < /tmp/patch.txt")"
expect_block "RED: sponge onto production src with trailing stdin redirect blocked" \
  "$(run_bash "sponge $GITREPO/src/app.js < /tmp/in")"
# Controls: same trailing-token shapes onto a test file allow.
expect_allow "RED: cp onto a test file with trailing 2>/dev/null allowed" \
  "$(run_bash "cp /tmp/x $GITREPO/src/app.test.js 2>/dev/null")"
expect_allow "RED: ed onto a test file with trailing stdin redirect allowed" \
  "$(run_bash "ed $GITREPO/src/app.test.js < /tmp/patch.txt")"

# Spaced-tag heredoc must be recognized so its target is classified — a spaced
# `<< EOF` into production blocks; into a test file allows.
expect_block "RED: spaced-tag heredoc into production blocked" \
  "$(run_bash "$(printf 'cat > %s/src/app.js << EOF\nconst x = 1;\nEOF\n' "$GITREPO")")"
expect_allow "RED: spaced-tag heredoc into a test file allowed" \
  "$(run_bash "$(printf 'cat > %s/src/app.test.js << EOF\ntest()\nEOF\n' "$GITREPO")")"

# ===== Interpreter indirection must be inspected =====
# `sh -c "<payload>"` and `eval "<payload>"` hand <payload> to a shell as a
# COMMAND, so the gate extracts it before the quote scrub and re-runs on it.
expect_block "RED: sh -c write into production blocked" \
  "$(run_bash "sh -c \"echo x > $GITREPO/src/app.js\"")"
expect_block "RED: bash -lc tee into production blocked" \
  "$(run_bash "bash -lc 'echo x | tee $GITREPO/src/app.js'")"
expect_block "RED: eval write into production blocked" \
  "$(run_bash "eval \"echo x > $GITREPO/src/app.js\"")"
expect_block "RED: eval nested in sh -c blocked" \
  "$(run_bash "sh -c \"eval 'echo x > $GITREPO/src/app.js'\"")"
# No false positives: benign payloads, a test-file target, and the dangerous
# form MENTIONED as data.
expect_allow "RED: sh -c benign command allowed" \
  "$(run_bash 'sh -c "echo hello"')"
expect_allow "RED: eval benign command allowed" \
  "$(run_bash 'eval "echo hello"')"
expect_allow "RED: eval ssh-agent idiom allowed" \
  "$(run_bash 'eval "$(ssh-agent -s)"')"
expect_allow "RED: eval write into a test file allowed" \
  "$(run_bash "eval \"echo x > $GITREPO/src/app.test.js\"")"
expect_allow "RED: prose mentioning eval write to production allowed" \
  "$(run_bash "echo \"never run eval echo x > $GITREPO/src/app.js here\"")"

# ===== Bash branch: interpreter-mediated writes during RED =====
# An interpreter's file write is never shell syntax, so the redirect/tee/sed
# vectors never see it. The same test-vs-production classification applies to
# the target the script names.
expect_block "RED: python3 open(app.js,'w') blocked" \
  "$(run_bash "python3 -c \"open('src/app.js','w').write('x')\"")"
expect_block "RED: node writeFileSync(app.ts) blocked" \
  "$(run_bash "node -e \"require('fs').writeFileSync('src/app.ts','x')\"")"
expect_block "RED: ruby File.write(app.rb) blocked" \
  "$(run_bash "ruby -e \"File.write('src/app.rb','x')\"")"
expect_block "RED: awk print redirected into app.js blocked" \
  "$(run_bash "awk 'BEGIN{print \"x\" > \"src/app.js\"}'")"
# Test files stay writable during RED — that is the phase's whole point.
expect_allow "RED: python3 writing a test file allowed" \
  "$(run_bash "python3 -c \"open('src/app.test.js','w').write('x')\"")"
expect_allow "RED: awk print redirected into a test file allowed" \
  "$(run_bash "awk 'BEGIN{print \"x\" > \"tests/app_spec.py\"}'")"
# Read-only interpreter calls are untouched.
expect_allow "RED: python3 reading production source allowed" \
  "$(run_bash "python3 -c \"print(open('src/app.js').read())\"")"
expect_allow "RED: node console.log allowed" \
  "$(run_bash "node -e \"console.log(1+1)\"")"
expect_allow "RED: awk printing a field allowed" \
  "$(run_bash "awk '{print \$1}' src/app.js")"
expect_allow "RED: awk numeric compare allowed" \
  "$(run_bash "awk '{print (a > b) ? 1 : 2}' src/app.js")"
expect_allow "RED: running a python script allowed" \
  "$(run_bash 'python3 manage.py migrate')"
# Regression from the #6 fix: unquoting a whitespace-free token before the
# blank pass (needed so a quoted write TARGET survives) also un-hides a
# whitespace-free awk PROGRAM that used to be blanked as quoted data — the
# in-place-awk vector had no name-based skip for that shape the way sed's
# script-token skip already does, so `{print}` itself became a bogus second
# candidate and hard-blocked the write to the REAL (test-file) target.
expect_allow "RED: gawk -i inplace with an unquoted brace program on a test file allowed" \
  "$(run_bash 'gawk -i inplace "{print}" src/app.test.js')"
expect_block "RED: gawk -i inplace with an unquoted brace program on production blocks" \
  "$(run_bash 'gawk -i inplace "{print}" src/app.js')"

# ===== NotebookEdit branch: notebook_path is classified like file_path =====
run_notebookedit() {
  jq -nc --arg p "$1" '{tool_name: "NotebookEdit", tool_input: {notebook_path: $p, new_source: "x = 1"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
write_phase RED
expect_block "RED: NotebookEdit on a production notebook blocked" \
  "$(run_notebookedit "$GITREPO/src/pipeline.ipynb")"
expect_allow "RED: NotebookEdit on a test notebook allowed" \
  "$(run_notebookedit "$GITREPO/tests/pipeline.ipynb")"

# No TDD state file → not opted in → Bash production write allowed.
write_phase RED
rm -f "$STATE_FILE"
expect_allow "no state file: Bash production write allowed" \
  "$(run_bash "$(printf 'cat > %s/src/app.js <<EOF\nx\nEOF\n' "$GITREPO")")"

# ===== T1 #6 (2026-08-09 audit): quoting the write target must not bypass
# the RED gate — the quote-blank ran with no preceding unquote pass, so the
# whole shell word (including a quoted `src/app.js`) was erased as data. =====
write_phase RED
expect_block "RED: bash unquoted redirect into production blocks (control)" \
  "$(run_bash "echo x > $GITREPO/src/app.js")"
expect_block "RED: bash double-quoted redirect target blocks" \
  "$(run_bash "echo x > \"$GITREPO/src/app.js\"")"
expect_block "RED: bash single-quoted redirect target blocks" \
  "$(run_bash "echo x > '$GITREPO/src/app.js'")"
expect_allow "RED: bash quoted redirect into a test file allowed" \
  "$(run_bash "echo x > \"$GITREPO/tests/app.test.js\"")"

# ===== T1 #10 (2026-08-09 audit): collapsing newlines to spaces merged two
# separate simple commands, so an unrelated flag on line 2 (`grep -i`) was
# misread as line 1's `sed -i` in-place flag and hard-blocked a read-only
# span. The `&&`-joined equivalent (already one line, never collapsed) must
# decide the SAME way. =====
write_phase RED
expect_allow "RED: sed(no -i)+grep -i on separate lines stays allowed" \
  "$(run_bash "$(printf "sed 's/a/b/' %s/src/app.js > /tmp/o\ngrep -i foo %s/notes.txt\n" "$GITREPO" "$GITREPO")")"
expect_allow "RED: sed(no -i)+grep -i joined with && stays allowed (control)" \
  "$(run_bash "sed 's/a/b/' $GITREPO/src/app.js > /tmp/o && grep -i foo $GITREPO/notes.txt")"

# ===== T4-5: jq-less fail-open — the guard cannot inspect tool input without
# jq and, unlike the data-loss guards, carries no coarse raw-text fallback, so
# it fails open UNCONDITIONALLY. FAKEBIN holds symlinks to every tool the
# guard needs except jq (mirrors block-dangerous-git.sh's shape). =====
write_phase RED
FAKEBIN="$TMPDIR_BASE/nojq-bin"
mkdir -p "$FAKEBIN"
for _t in cat grep sed awk tr head printf env bash sh git; do
  _s="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_s" "$FAKEBIN/$_t"
done
run_edit_nojq() {
  printf '{"tool_input":{"file_path":"%s","new_string":"x"}}' "$1" \
    | PATH="$FAKEBIN" bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_allow "jqless: RED production edit fails open (no coarse fallback in this guard)" \
  "$(run_edit_nojq "$GITREPO/src/app.js")"

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
