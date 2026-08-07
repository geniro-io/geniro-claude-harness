#!/usr/bin/env bash
# Smoke test for hooks/enforce-state-helper.sh (PreToolUse Edit|Write|MultiEdit AND Bash, block-mode).
#
# Run: bash tests/hooks/enforce-state-helper.sh
#
# Coverage:
#   - State-path write blocks (exit 2) with the atomic-helper guidance.
#   - JSONL knowledge path suggests atomic_state_append; others atomic_state_write.
#   - Non-canonical .geniro/state/ path gets the canonical-layout hint.
#   - Excluded transient files (locks, notes.md, .tmp) stay silent (exit 0).
#   - Non-state paths stay silent.
#   - .geniro/state/tdd/ paths are exempt (own mktemp + mv procedure).
#   - Bash branch: redirection / tee / sed -i / cp / mv / dd into state paths block.
#   - Bash branch: atomic_state_write/append invocation, reads, non-state writes allow.
#   - enforce-state-helper bypass via safety.json (both branches).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/enforce-state-helper.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Edit/Write-form payload (content arbitrary; the guard is file_path-based).
run_path() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, content: "x"}}' | bash "$HOOK" 2>&1
}
rc_path() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, content: "x"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
# Bash-form payload -> exit code.
rc_bash() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
run_bash() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOOK" 2>&1
}
expect_block() { if [ "$2" = "2" ]; then pass "$1"; else fail "$1 (expected exit=2, got exit=$2)"; fi; }
expect_allow() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1 (expected exit=0, got exit=$2)"; fi; }

cd "$TMPDIR_BASE" || exit 1

# ===== Edit/Write branch: state path now hard-blocks =====
out=$(run_path '/proj/.geniro/state/handoff/from-review-main.md')
expect_block "block mode blocks the state write (exit 2)" "$(rc_path '/proj/.geniro/state/handoff/from-review-main.md')"
if printf '%s' "$out" | grep -q 'atomic_state_write'; then
  pass "state path suggests atomic_state_write"
else
  fail "state path suggests atomic_state_write"
fi

out=$(run_path '/proj/.geniro/knowledge/learnings.jsonl')
if printf '%s' "$out" | grep -q 'atomic_state_append'; then
  pass "jsonl knowledge path suggests atomic_state_append"
else
  fail "jsonl knowledge path suggests atomic_state_append"
fi

# Canonical state/<skill>/<slug>/state.md must NOT carry the layout hint.
out=$(run_path '/proj/.geniro/state/review/slug/state.md')
expect_block "canonical state/<skill>/<slug>/state.md blocks" "$(rc_path '/proj/.geniro/state/review/slug/state.md')"
if printf '%s' "$out" | grep -q 'matches no canonical layout'; then
  fail "canonical layout does NOT emit the layout hint"
else
  pass "canonical layout does NOT emit the layout hint"
fi
# Ad-hoc file directly under .geniro/state/ gets the canonical-layout hint.
out=$(run_path '/proj/.geniro/state/integration-flakes.md')
if printf '%s' "$out" | grep -q 'matches no canonical layout'; then
  pass "non-canonical state/ path gets the layout hint"
else
  fail "non-canonical state/ path gets the layout hint"
fi

# ===== Edit/Write branch: exclusions and exemptions stay silent =====
expect_allow "non-state path stays silent"          "$(rc_path '/proj/src/app.js')"
expect_allow "lock file is excluded"                "$(rc_path '/proj/.geniro/planning/.codebase-map.lock')"
expect_allow "scratch notes.md is excluded"         "$(rc_path '/proj/.geniro/planning/task-dir/notes.md')"
expect_allow "atomic-write temp file is excluded"   "$(rc_path '/proj/.geniro/state/x/state.md.tmp.123.host')"
expect_allow ".geniro/state/tdd/ path is exempt"    "$(rc_path '/proj/.geniro/state/tdd/state-myslug.md')"

# ===== Bash branch: shell-side writes into state paths block =====
expect_block "bash: redirect into state path blocks"   "$(rc_bash 'echo x > .geniro/state/review/s/state.md')"
# Regression: the sanctioned-helper allow-check runs AFTER the quote+comment
# scrub, so the helper name appearing only in a string or comment can no longer
# disable the guard while a real invocation still passes.
expect_block "bash: helper name in echo string still blocks"   "$(rc_bash 'echo "atomic_state_write" > .geniro/state/review/s/state.md')"
expect_block "bash: helper name in trailing comment still blocks" "$(rc_bash 'echo x > .geniro/state/review/s/state.md  # atomic_state_write')"
expect_block "bash: append into state path blocks"     "$(rc_bash 'printf y >> ./.geniro/planning/td/state.md')"
expect_block "bash: tee into state path blocks"        "$(rc_bash 'echo x | tee .geniro/state/debug/s/state.md')"
expect_block "bash: sed -i on state file blocks"       "$(rc_bash "sed -i.bak 's/a/b/' .geniro/instructions/global.md")"
expect_block "bash: mv onto state path blocks"         "$(rc_bash 'mv new.md .geniro/state/onboard/s/state.md')"
expect_block "bash: cp onto state path blocks"         "$(rc_bash 'cp tmp.md .geniro/workflow/linear.md')"
expect_block "bash: dd of= into state path blocks"     "$(rc_bash 'dd if=/dev/stdin of=.geniro/knowledge/learnings.jsonl')"
# T4-8: this guard carries the same rsync-destination vector as file-protection.sh
# (vector 8) but had no assertion of its own for it.
expect_block "bash: rsync destination onto state path blocks" "$(rc_bash 'rsync -a /tmp/src/ .geniro/planning/td/state.md')"
expect_allow "bash: rsync FROM a state file allowed"    "$(rc_bash 'rsync -a .geniro/state/review/s/state.md /tmp/backup/')"

# ===== Bash branch: sanctioned helpers, reads, exemptions, non-state writes allow =====
expect_allow "bash: atomic_state_write invocation allowed" "$(rc_bash 'atomic_state_write .geniro/state/review/s/state.md < body.txt')"
expect_allow "bash: atomic_state_append invocation allowed" "$(rc_bash 'atomic_state_append .geniro/knowledge/learnings.jsonl < line.json')"
expect_allow "bash: redirect into .geniro/state/tdd/ allowed" "$(rc_bash 'echo RED > .geniro/state/tdd/state-myslug.md')"
expect_allow "bash: reading a state file allowed"      "$(rc_bash 'cat .geniro/state/review/s/state.md')"
expect_allow "bash: grep in a state file allowed"      "$(rc_bash 'grep phase .geniro/planning/td/state.md')"
expect_allow "bash: cp FROM a state file allowed"      "$(rc_bash 'cp .geniro/state/review/s/state.md /tmp/inspect.md')"
expect_allow "bash: redirect to non-state file allowed" "$(rc_bash 'echo x > /tmp/out.txt')"
expect_allow "bash: stderr to /dev/null allowed"       "$(rc_bash 'npm test 2>/dev/null')"
expect_allow "bash: plain git command allowed"         "$(rc_bash 'git status')"
expect_allow "bash: rm of a state file is not a write candidate" "$(rc_bash 'rm -f .geniro/state/review/s/state.md')"

# ===== Bash branch: same-tier cp/mv housekeeping (source under .geniro/) allowed =====
# /geniro:actions version-it: rename existing action to <name>-v1.md.
expect_allow "bash: mv rename within .geniro/actions/ allowed" "$(rc_bash 'mv .geniro/actions/foo.md .geniro/actions/foo-v1.md')"
# /geniro:actions pre-edit snapshot: cp to a sibling .pre-edit.bak.
expect_allow "bash: cp to pre-edit snapshot within .geniro/ allowed" "$(rc_bash 'cp .geniro/actions/foo.md .geniro/actions/foo.md.pre-edit.bak')"
# /geniro:actions revert: mv the backup back over the original.
expect_allow "bash: mv backup back within .geniro/ allowed" "$(rc_bash 'mv .geniro/actions/foo.md.pre-edit.bak .geniro/actions/foo.md')"

# A cp/mv whose SOURCE is OUTSIDE .geniro/ is a content write around the helper — still blocks.
expect_block "bash: mv from outside .geniro/ into state path blocks" "$(rc_bash 'mv /tmp/staged.md .geniro/state/review/s/state.md')"
expect_block "bash: cp from outside .geniro/ into actions blocks"    "$(rc_bash 'cp /tmp/x .geniro/actions/foo.md')"

# Bash branch canonical-layout hint on non-canonical state/ redirect.
out=$(run_bash 'echo x > .geniro/state/integration-flakes.md')
if printf '%s' "$out" | grep -q 'matches no canonical layout'; then
  pass "bash: non-canonical state/ redirect gets the layout hint"
else
  fail "bash: non-canonical state/ redirect gets the layout hint"
fi

# ===== safety.json bypass — both branches =====
mkdir -p "$TMPDIR_BASE/byp/.geniro"
echo '{"allow_patterns":["enforce-state-helper"]}' > "$TMPDIR_BASE/byp/.geniro/safety.json"
cd "$TMPDIR_BASE/byp" || exit 1
expect_allow "bypass: Edit/Write to state path allowed" "$(rc_path '/proj/.geniro/state/review/slug/state.md')"
expect_allow "bypass: Bash redirect into state path allowed" "$(rc_bash 'echo x > .geniro/state/review/s/state.md')"
cd "$TMPDIR_BASE" || exit 1

# ===== Bash branch: additional write vectors into state paths block =====
expect_block "bash: truncate on a state file blocks"   "$(rc_bash 'truncate -s 0 .geniro/state/review/s/state.md')"
expect_block "bash: shred on learnings.jsonl blocks"   "$(rc_bash 'shred .geniro/knowledge/learnings.jsonl')"
expect_block "bash: install into a state path blocks"  "$(rc_bash 'install -m 644 /tmp/x .geniro/instructions/global.md')"
expect_block "bash: ln -sf over a state file blocks"   "$(rc_bash 'ln -sf /tmp/x .geniro/state/review/s/state.md')"
expect_allow "bash: truncate on a non-state file allowed" "$(rc_bash 'truncate -s 0 /tmp/out.log')"

# ===== Bash branch: per-segment helper allow (T1-1) =====
# A sanctioned helper call in one segment must NOT whitelist a raw redirect in
# another segment of the same compound command.
expect_block "bash: helper in seg 1 does not whitelist redirect in seg 2 (;)" \
  "$(rc_bash 'true atomic_state_write; echo x > .geniro/planning/t/state.md')"
expect_block "bash: helper in seg 1 does not whitelist redirect in seg 2 (&&)" \
  "$(rc_bash 'atomic_state_write foo && echo y > .geniro/planning/t/state.md')"
# A genuine single-segment helper invocation still passes.
expect_allow "bash: lone atomic_state_write invocation still allowed" \
  "$(rc_bash 'atomic_state_write .geniro/state/review/s/state.md < body.txt')"

# ===== Bash branch: interpreter-mediated writes (vector 10) =====
# A script writing the file is not shell syntax, and a heredoc body is scrubbed
# as data before vectors 1-9 run — so `python3 - "$S" <<'PY' … open(p,'w') … PY`
# reached the filesystem unchecked. Observed in the wild across 15 state writes
# whose trailing atomic_state_write call re-wrote already-mutated content.
expect_block "bash: python heredoc in-place write to spec.md blocks" \
  "$(rc_bash 'S=.geniro/planning/cls/spec.md; python3 - "$S" <<'"'"'PY'"'"'
p=sys.argv[1]; b=open(p).read()
open(p,"w").write(b)
PY
cp "$S" /tmp/x && atomic_state_write "$S" < /tmp/x')"
expect_block "bash: python -c in-place write via \$S blocks" \
  "$(rc_bash 'S=.geniro/planning/x/state.md; python3 -c "b=open('"'"'$S'"'"').read();open('"'"'$S'"'"','"'"'w'"'"').write(b)"')"
expect_block "bash: python write to a literal state path blocks" \
  "$(rc_bash 'python3 -c "open(\".geniro/planning/x/state.md\", \"w\").write(s)"')"
expect_block "bash: node writeFileSync with variable target blocks" \
  "$(rc_bash 'P=.geniro/planning/x/state.md; node -e "fs.writeFileSync(p, out)"')"
expect_block "bash: perl -pi in-place edit of a state file blocks" \
  "$(rc_bash 'perl -pi -e "s/a/b/" .geniro/planning/x/spec.md')"
expect_block "bash: python append to learnings.jsonl blocks" \
  "$(rc_bash 'S=.geniro/knowledge/learnings.jsonl; python3 -c "open('"'"'$S'"'"','"'"'a'"'"').write(l)"')"
expect_block "bash: write target variable with no visible assignment blocks" \
  "$(rc_bash 'python3 -c "open('"'"'$OUT'"'"','"'"'w'"'"').write(b)"; cat .geniro/planning/x/spec.md')"
# Reads and provable non-state writes stay allowed — the vector fires only on
# interpreter + write-mode op + state path together.
expect_allow "bash: read-only python over a state file allowed" \
  "$(rc_bash 'S=.geniro/planning/x/spec.md; python3 -c "print(open('"'"'$S'"'"').read())"')"
expect_allow "bash: read-only python over a literal state path allowed" \
  "$(rc_bash 'python3 -c "print(open(\".geniro/planning/x/spec.md\").read())"')"
expect_allow "bash: python writing an assigned non-state path allowed" \
  "$(rc_bash 'T=/tmp/out.md; python3 -c "open('"'"'$T'"'"','"'"'w'"'"').write(x)"; cat .geniro/planning/x/spec.md')"
expect_allow "bash: python rendering to stdout piped into the helper allowed" \
  "$(rc_bash 'S=.geniro/planning/x/state.md; python3 render.py | atomic_state_write "$S"')"
expect_allow "bash: interpreter write to a transient .research file allowed" \
  "$(rc_bash 'python3 -c "open(\".geniro/planning/x/.research-api.md\",\"w\").write(b)"')"
expect_allow "bash: interpreter write under state/tdd/ allowed" \
  "$(rc_bash 'python3 -c "open(\".geniro/state/tdd/state-x.md\",\"w\").write(b)"')"
expect_allow "bash: grep whose pattern names an interpreter allowed" \
  "$(rc_bash 'grep -rn "python" .geniro/planning/x/spec.md')"
# A variable escaped to survive a double-quoted -c/-r script is still a variable.
expect_block "bash: escaped-dollar write target blocks" \
  "$(rc_bash 'S=.geniro/planning/x/state.md; python3 -c "open(\$p,\"w\").write(b)"')"
# awk redirects `print` from inside its program string, which vector 1 blanks as
# data — so the same conjunction has to be checked on the raw command.
expect_block "bash: awk print redirected into a state file blocks" \
  "$(rc_bash 'awk '"'"'BEGIN{print "x" > ".geniro/planning/x/state.md"}'"'"'')"
expect_block "bash: awk printf appended to learnings.jsonl blocks" \
  "$(rc_bash 'awk '"'"'BEGIN{printf "x" >> ".geniro/knowledge/learnings.jsonl"}'"'"' in.txt')"
expect_allow "bash: awk reading a state file allowed" \
  "$(rc_bash 'awk '"'"'/phase/{print}'"'"' .geniro/planning/x/state.md')"
expect_allow "bash: awk numeric comparison over a state file allowed" \
  "$(rc_bash 'awk '"'"'{print (a > b) ? 1 : 2}'"'"' .geniro/planning/x/state.md')"
expect_allow "bash: awk writing outside .geniro allowed" \
  "$(rc_bash 'awk '"'"'BEGIN{print "x" > "/tmp/out.md"}'"'"' && cat .geniro/planning/x/spec.md')"
expect_block "bash: php file_put_contents to a state path blocks" \
  "$(rc_bash 'php -r "file_put_contents(\".geniro/planning/x/state.md\", \$b);"')"
expect_block "bash: perl -i.bak in-place on a state file blocks" \
  "$(rc_bash 'perl -i.bak -pe "s/a/b/" .geniro/planning/x/spec.md')"
# `-version` ends in no in-place flag — a long option must not read as `-i`.
expect_allow "bash: ruby -version beside a state path allowed" \
  "$(rc_bash 'ruby -version; cat .geniro/planning/x/spec.md')"

# ===== Bash branch: interpreter indirection must be inspected =====
# `sh -c "<payload>"` and `eval "<payload>"` hand <payload> to a shell as a
# COMMAND, so the guard extracts it before the quote scrub and re-runs on it.
expect_block "bash: sh -c redirect into a state path blocks" \
  "$(rc_bash 'sh -c "echo x > .geniro/planning/task/state.md"')"
expect_block "bash: bash -lc tee into a state path blocks" \
  "$(rc_bash "bash -lc 'echo x | tee .geniro/planning/task/state.md'")"
expect_block "bash: eval redirect into a state path blocks" \
  "$(rc_bash 'eval "echo x > .geniro/planning/task/state.md"')"
expect_block "bash: eval nested in sh -c blocks" \
  "$(rc_bash $'sh -c "eval \'echo x > .geniro/planning/task/state.md\'"')"
# No false positives: benign payloads, a helper call inside the payload, and the
# dangerous form MENTIONED as data.
expect_allow "bash: sh -c benign command allowed" \
  "$(rc_bash 'sh -c "echo hello"')"
expect_allow "bash: eval benign command allowed" \
  "$(rc_bash 'eval "echo hello"')"
expect_allow "bash: eval ssh-agent idiom allowed" \
  "$(rc_bash 'eval "$(ssh-agent -s)"')"
expect_allow "bash: sh -c invoking the sanctioned helper allowed" \
  "$(rc_bash 'sh -c "atomic_state_write .geniro/planning/task/state.md"')"
expect_allow "bash: prose mentioning eval write to a state path allowed" \
  "$(rc_bash 'echo "never run eval echo x > .geniro/planning/task/state.md here"')"
# A quoted literal spanning a NEWLINE: the per-line quote-blanking pass used to
# see an unbalanced quote on each half and read the second half as syntax, so a
# redirect written INSIDE the string blocked while its single-line twin allowed.
expect_allow "bash: multi-line quoted string containing a redirect allowed" \
  "$(rc_bash "$(printf 'echo "first line\nsee > .geniro/planning/task/state.md"\n')")"
expect_allow "bash: single-line equivalent allowed (control)" \
  "$(rc_bash 'echo "see > .geniro/planning/task/state.md"')"
expect_block "bash: real redirect after a multi-line quoted string still blocks" \
  "$(rc_bash "$(printf 'echo "first line\nsecond line"\necho x > .geniro/planning/task/state.md\n')")"

# ===== NotebookEdit branch: notebook_path is read like file_path =====
rc_notebook() {
  jq -nc --arg p "$1" '{tool_name: "NotebookEdit", tool_input: {notebook_path: $p, new_source: "x = 1"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "NotebookEdit into a state path blocks" \
  "$(rc_notebook '/proj/.geniro/planning/task/state.md')"
expect_allow "NotebookEdit into a normal notebook allowed" \
  "$(rc_notebook '/proj/notebooks/analysis.ipynb')"

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
