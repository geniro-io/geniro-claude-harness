#!/usr/bin/env bash
# Smoke test for hooks/file-protection.sh (PreToolUse Edit|Write|MultiEdit).
#
# Run: bash tests/hooks/file-protection.sh
#
# Coverage:
#   - Each protected pattern blocks (exit 2).
#   - Normal files + the substring-not-path-segment false-positive shape allow.
#   - safety.json allow_patterns bypass.
#   - MultiEdit form is guarded (file_path-based; fires once the matcher includes MultiEdit).
#   - Missing file_path fails-open (exit 0).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/file-protection.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Write-form payload (content arbitrary; the guard is file_path-based) -> exit code.
run_write() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, content: "x"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
# MultiEdit-form payload -> exit code (same single file_path; edits content irrelevant here).
run_multiedit() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, edits: [{old_string: "a", new_string: "b"}]}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block() { if [ "$2" = "2" ]; then pass "$1"; else fail "$1 (expected exit=2, got exit=$2)"; fi; }
expect_allow() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1 (expected exit=0, got exit=$2)"; fi; }

cd "$TMPDIR_BASE" || exit 1

# ===== Protected patterns block =====
expect_block "write-env .env blocked"               "$(run_write /proj/.env)"
expect_block "write-env .env.local blocked"         "$(run_write /proj/.env.local)"
expect_block "write-git-internal .git/ blocked"     "$(run_write /proj/.git/config)"
expect_block "write-lockfile package-lock blocked"  "$(run_write /proj/package-lock.json)"
expect_block "write-lockfile go.sum blocked"        "$(run_write /proj/go.sum)"
expect_block "write-cert-key .pem blocked"          "$(run_write /proj/server.pem)"
expect_block "write-cert-key .key blocked"          "$(run_write /proj/tls.key)"
expect_block "write-credentials credentials.* blocked" "$(run_write /proj/credentials.json)"
expect_block "write-credentials secrets.* blocked"  "$(run_write /proj/config/secrets.yaml)"
expect_block "write-tfstate blocked"                "$(run_write /proj/terraform.tfstate)"
expect_block "write-vault blocked"                  "$(run_write /proj/prod.vault)"

# ===== Normal files allow =====
expect_allow "normal source file allows"            "$(run_write /proj/src/app.js)"
expect_allow "secrets as substring (not segment) allows" "$(run_write /proj/lib/redact-secrets.sh)"
expect_allow "env inside a longer name allows"      "$(run_write /proj/environment.ts)"

# ===== MultiEdit form is now guarded (file_path-based) =====
expect_block "MultiEdit to .env blocked"            "$(run_multiedit /proj/.env)"
expect_allow "MultiEdit to normal file allows"      "$(run_multiedit /proj/src/app.js)"

# ===== safety.json bypass =====
mkdir -p "$TMPDIR_BASE/proj-bypass/.geniro"
echo '{"allow_patterns": ["write-env"]}' > "$TMPDIR_BASE/proj-bypass/.geniro/safety.json"
cd "$TMPDIR_BASE/proj-bypass" || exit 1
expect_allow "safety.json bypass: write-env allowed"        "$(run_write /proj/.env)"
expect_block "safety.json bypass: unrelated pattern still blocks" "$(run_write /proj/server.pem)"
cd "$TMPDIR_BASE" || exit 1

# ===== Bash branch: shell-side writes into protected paths =====
run_bash() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "bash: echo redirect to .env blocked"        "$(run_bash 'echo "API_KEY=x" > .env')"
expect_block "bash: append to .env blocked"               "$(run_bash 'printf "K=v\n" >> ./.env')"
expect_block "bash: tee to .env blocked"                  "$(run_bash 'echo x | tee .env')"
expect_block "bash: tee -a to credentials.json blocked"   "$(run_bash 'cat tmp.txt | tee -a config/credentials.json')"
expect_block "bash: sed -i on go.sum blocked"             "$(run_bash "sed -i.bak 's/a/b/' go.sum")"
expect_block "bash: cp onto .env blocked"                 "$(run_bash 'cp .env.example .env')"
expect_block "bash: mv onto server.pem blocked"           "$(run_bash 'mv new.pem server.pem')"
expect_block "bash: dd of=secrets.yaml blocked"           "$(run_bash 'dd if=/dev/stdin of=secrets.yaml')"
expect_allow "bash: reading .env allowed"                 "$(run_bash 'cat .env')"
expect_allow "bash: grep in .env allowed"                 "$(run_bash 'grep KEY .env')"
expect_allow "bash: cp FROM protected source allowed"     "$(run_bash 'cp .env /tmp/inspect.txt')"
expect_allow "bash: redirect to normal file allowed"      "$(run_bash 'echo x > out.txt')"
expect_allow "bash: stderr to /dev/null allowed"          "$(run_bash 'npm test 2>/dev/null')"
expect_allow "bash: fd dup >&2 allowed"                   "$(run_bash 'echo err >&2')"
expect_allow "bash: plain git command allowed"            "$(run_bash 'git status')"
expect_allow "bash: sed without -i on go.sum allowed"     "$(run_bash "sed 's/a/b/' go.sum")"

# Data contexts (quoted strings, heredoc bodies, sed scripts) must not block —
# and the quoted-target miss is the documented trade-off of that scrub.
expect_allow "bash: quoted-string mention of > .env allowed"  "$(run_bash 'echo "set x > .env to configure"')"
expect_allow "bash: quoted sed script naming .env allowed"    "$(run_bash "sed -i 's/.env.example/.env.sample/' README.md")"
expect_allow "bash: unquoted sed script naming .env allowed"  "$(run_bash 'sed -i s/.env.example/.env.sample/ README.md')"
expect_allow "bash: heredoc body mentioning > .env allowed"   "$(run_bash 'cat <<DOC > out.txt
PORT=3000 > .env is just text
DOC')"
expect_block "bash: heredoc INTO .env still blocked"          "$(run_bash 'cat <<DOC > .env
K=v
DOC')"
expect_allow "bash: QUOTED redirect target is a documented miss" "$(run_bash 'echo k > ".env"')"

# safety.json bypass applies to the Bash branch too
cd "$TMPDIR_BASE/proj-bypass" || exit 1
expect_allow "bash: bypass write-env honored"             "$(run_bash 'echo K=v > .env')"
expect_block "bash: bypass unrelated pattern still blocks" "$(run_bash 'cp x.pem server.pem')"
cd "$TMPDIR_BASE" || exit 1

# ===== Fail-open on missing file_path =====
expect_allow "missing file_path → allow" "$(echo '{"tool_input": {}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
