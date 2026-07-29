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
expect_block "bash: sed --in-place (GNU long form) on .env blocked" "$(run_bash "sed --in-place 's/a/b/' .env")"
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

# ===== Bash branch: additional write vectors (truncate/shred/install/rsync/ln -f) =====
expect_block "bash: truncate -s 0 .env blocked"          "$(run_bash 'truncate -s 0 .env')"
expect_block "bash: shred server.pem blocked"            "$(run_bash 'shred -u server.pem')"
expect_block "bash: install into credentials.json blocked" "$(run_bash 'install -m 600 src config/credentials.json')"
expect_block "bash: rsync onto secrets.yaml blocked"     "$(run_bash 'rsync -a a.txt secrets.yaml')"
expect_block "bash: ln -sf over .env blocked"            "$(run_bash 'ln -sf real .env')"
# Allowed: same tools targeting non-protected paths, and ln WITHOUT -f (won't clobber).
expect_allow "bash: truncate on a log file allowed"      "$(run_bash 'truncate -s 0 out.log')"
expect_allow "bash: shred a scratch tmp allowed"         "$(run_bash 'shred -u scratch.tmp')"
expect_allow "bash: rsync into a normal dir allowed"     "$(run_bash 'rsync -a src/ dest/')"
expect_allow "bash: ln -s (no -f) allowed"               "$(run_bash 'ln -s real link')"
# install -t DIR: the trailing token is a SOURCE (read), not the destination.
expect_allow "bash: install -t DIR (source not flagged) allowed" "$(run_bash 'install -t config src.pem')"

# ===== Bash branch: spaced-tag heredoc body is DATA (no false block) =====
# `<< EOF` (space before the tag) must be recognized so its body is dropped —
# else a doc heredoc mentioning `cmd > .env` would hard-block.
expect_allow "bash: spaced-tag heredoc body mentioning > .env allowed" "$(run_bash 'cat << DOC > out.txt
PORT=3000 > .env is just text
DOC')"
expect_block "bash: spaced-tag heredoc INTO .env still blocked"        "$(run_bash 'cat << DOC > .env
K=v
DOC')"

# ===== Bash branch: interpreter indirection must be inspected =====
# `sh -c "<payload>"` and `eval "<payload>"` hand <payload> to a shell as a
# COMMAND, so the guard extracts it before the quote scrub and re-runs on it.
expect_block "bash: sh -c redirect into .env blocked"    "$(run_bash 'sh -c "echo K=v > .env"')"
expect_block "bash: bash -lc tee into .env blocked"      "$(run_bash "bash -lc 'echo K=v | tee .env'")"
expect_block "bash: eval redirect into .env blocked"     "$(run_bash 'eval "echo K=v > .env"')"
expect_block "bash: eval cp onto a lockfile blocked"     "$(run_bash "eval 'cp new.json package-lock.json'")"
expect_block "bash: eval nested in sh -c blocked"        "$(run_bash $'sh -c "eval \'echo K=v > .env\'"')"
# No false positives: benign payloads, and the dangerous form MENTIONED as data.
expect_allow "bash: sh -c benign command allowed"        "$(run_bash 'sh -c "echo hello"')"
expect_allow "bash: eval benign command allowed"         "$(run_bash 'eval "echo hello"')"
expect_allow "bash: eval ssh-agent idiom allowed"        "$(run_bash 'eval "$(ssh-agent -s)"')"
expect_allow "bash: prose mentioning eval write to .env allowed" \
  "$(run_bash 'echo "never run eval echo K=v > .env here"')"

# ===== Bash branch: interpreter-mediated writes =====
# An interpreter's file write is never shell syntax, so the redirection/tee/sed
# vectors above never see it. The guard scans the raw command for the
# conjunction interpreter + write op + protected target.
expect_block "bash: python3 -c open(.env,'w') blocked"   "$(run_bash "python3 -c \"open('.env','w').write('K=v')\"")"
expect_block "bash: python3 pathlib write_text blocked"  "$(run_bash "python3 -c \"from pathlib import Path; Path('.env').write_text('K=v')\"")"
expect_block "bash: node writeFileSync(.env) blocked"    "$(run_bash "node -e \"require('fs').writeFileSync('.env','K=v')\"")"
expect_block "bash: node appendFileSync onto a key blocked" "$(run_bash "node -e \"require('fs').appendFileSync('server.key','x')\"")"
expect_block "bash: perl 3-arg open onto .env blocked"   "$(run_bash "perl -e 'open(F, \">\", \".env\"); print F \"K=v\";'")"
expect_block "bash: ruby File.write onto a lockfile blocked" "$(run_bash "ruby -e \"File.write('package-lock.json','{}')\"")"
expect_block "bash: php file_put_contents onto .env blocked" "$(run_bash "php -r \"file_put_contents('.env','K=v');\"")"
expect_block "bash: awk print redirected into .env blocked"  "$(run_bash "awk 'BEGIN{print \"K=v\" > \".env\"}'")"
expect_block "bash: awk printf appended to a .pem blocked"   "$(run_bash "awk 'BEGIN{printf \"x\" >> \"cert.pem\"}'")"
expect_block "bash: python var target resolved to .env blocked" "$(run_bash "F=.env; python3 -c \"open('\$F','w').write('K=v')\"")"
expect_block "bash: python unresolvable target near .env blocked" "$(run_bash "python3 -c \"p='.env'; open(p,'w').write('K=v')\"")"
# No false positives: read-only interpreter calls, and writes elsewhere.
expect_allow "bash: python3 reading .env allowed"        "$(run_bash "python3 -c \"print(open('.env').read())\"")"
expect_allow "bash: node console.log allowed"           "$(run_bash "node -e \"console.log(1+1)\"")"
expect_allow "bash: awk printing a field allowed"       "$(run_bash "awk '{print \$1}' .env")"
expect_allow "bash: awk numeric compare allowed"        "$(run_bash "awk '{print (a > b) ? 1 : 2}' .env")"
expect_allow "bash: python writing a normal file allowed" "$(run_bash "python3 -c \"open('out.txt','w').write('x')\"")"
expect_allow "bash: running a python script allowed"    "$(run_bash 'python3 manage.py migrate')"
expect_allow "bash: node reading .env allowed"          "$(run_bash "node -e \"console.log(require('fs').readFileSync('.env','utf8'))\"")"

# ===== NotebookEdit form is guarded (notebook_path, not file_path) =====
run_notebookedit() {
  jq -nc --arg p "$1" '{tool_name: "NotebookEdit", tool_input: {notebook_path: $p, new_source: "x = 1"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "NotebookEdit to .env blocked"          "$(run_notebookedit /proj/.env)"
expect_block "NotebookEdit to a .pem blocked"        "$(run_notebookedit /proj/server.pem)"
expect_allow "NotebookEdit to a normal notebook allows" "$(run_notebookedit /proj/analysis.ipynb)"

# ===== jq-less fail-closed scan: the coarse raw name check still blocks =====
# The guard's whole role is preventing credential clobber, so it does NOT fail
# fully open when jq is missing — it scans the path/command FIELDS textually and
# blocks the highest-signal protected names. Everything else fails open. FAKEBIN
# holds symlinks to every tool the fallback needs except jq.
FAKEBIN="$TMPDIR_BASE/nojq-bin"
mkdir -p "$FAKEBIN"
for _t in cat grep sed awk tr head printf env bash sh; do
  _s="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_s" "$FAKEBIN/$_t"
done
run_write_nojq() {  # <path>
  printf '{"tool_input":{"file_path":"%s","content":"x"}}' "$1" | PATH="$FAKEBIN" bash "$HOOK" >/dev/null 2>&1
  echo $?
}
run_bash_nojq() {  # <command>
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | PATH="$FAKEBIN" bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "jqless: write to .env still blocked"        "$(run_write_nojq /proj/.env)"
expect_block "jqless: write to a .pem still blocked"      "$(run_write_nojq /proj/server.pem)"
expect_block "jqless: write to credentials.json blocked"  "$(run_write_nojq /proj/credentials.json)"
expect_block "jqless: bash redirect to .env blocked"      "$(run_bash_nojq 'echo x > .env')"
expect_block "jqless: notebook_path .env blocked"         "$(printf '{"tool_input":{"notebook_path":"/proj/.env"}}' | PATH="$FAKEBIN" bash "$HOOK" >/dev/null 2>&1; echo $?)"
# Outside the coarse name set the guard fails OPEN — a lockfile is protected only
# on the full jq path, and the allowlist itself needs jq to read.
expect_allow "jqless: lockfile fails open"                "$(run_write_nojq /proj/package-lock.json)"
expect_allow "jqless: normal source fails open"           "$(run_bash_nojq 'echo x > src/app.js')"

# ===== Fail-open on missing file_path =====
expect_allow "missing file_path → allow" "$(echo '{"tool_input": {}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
