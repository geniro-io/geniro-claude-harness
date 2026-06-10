#!/usr/bin/env bash
# Smoke test for hooks/security-pattern-check.sh (PreToolUse Edit|Write).
#
# Run: bash tests/hooks/security-pattern-check.sh
#
# Coverage:
#   - Each pattern ID triggers (exit 2) on a positive example.
#   - Each pattern ID does NOT trigger (exit 0) on a known false-positive shape.
#   - Edit-form payload (.tool_input.new_string) handled like Write-form (.tool_input.content).
#   - Per-project bypass via .geniro/safety.json allow_patterns.
#   - Missing file_path or empty content fails-open (exit 0).
#   - File extension scoping (Python pattern doesn't fire on .js file).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/security-pattern-check.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Run hook with a Write-form payload; print exit code.
run_write() {
  local path="$1" content="$2"
  jq -nc --arg p "$path" --arg c "$content" \
    '{tool_input: {file_path: $p, content: $c}}' \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

# Run hook with an Edit-form payload; print exit code.
run_edit() {
  local path="$1" content="$2"
  jq -nc --arg p "$path" --arg c "$content" \
    '{tool_input: {file_path: $p, new_string: $c}}' \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

# Run hook with a MultiEdit-form payload (content carried in the 2nd edit);
# print exit code. The scanner must read .tool_input.edits[].new_string —
# MultiEdit was previously unmatched, bypassing every Edit|Write guard.
run_multiedit() {
  local path="$1" content="$2"
  jq -nc --arg p "$path" --arg c "$content" \
    '{tool_input: {file_path: $p, edits: [{old_string: "x", new_string: "y"}, {old_string: "a", new_string: $c}]}}' \
    | bash "$HOOK" >/dev/null 2>&1
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

cd "$TMPDIR_BASE" || exit 1

# ===== sec-eval-exec =====
expect_block "py eval blocked" "$(run_write /tmp/x.py 'r = eval(user_input)')"
expect_block "py exec blocked" "$(run_write /tmp/x.py 'exec(compile(src, "<s>", "exec"))')"
expect_allow "py method named eval_x NOT blocked" "$(run_write /tmp/x.py 'r = obj.eval_method(x)')"
expect_allow "py attr.eval NOT blocked (dotted)" "$(run_write /tmp/x.py 'r = sympy.evalf()')"
expect_block "pyx eval blocked (Cython ext in ext-list)" "$(run_write /tmp/x.pyx 'r = eval(user_input)')"
expect_block "js eval blocked" "$(run_write /tmp/x.js 'var r = eval(s);')"
expect_block "js new Function blocked" "$(run_write /tmp/x.ts 'const fn = new Function("return 1");')"
expect_allow "ts attr.eval NOT blocked" "$(run_write /tmp/x.ts 'this.evaluator.eval(x);')"

# ===== sec-pickle =====
expect_block "py pickle.loads blocked" "$(run_write /tmp/x.py 'obj = pickle.loads(buf)')"
expect_block "py pickle.load blocked" "$(run_write /tmp/x.py 'obj = pickle.load(f)')"
expect_allow "py json.loads NOT blocked" "$(run_write /tmp/x.py 'obj = json.loads(buf)')"

# ===== sec-yaml-unsafe =====
expect_block "py yaml.load blocked" "$(run_write /tmp/x.py 'cfg = yaml.load(f)')"
expect_allow "py yaml.safe_load NOT blocked" "$(run_write /tmp/x.py 'cfg = yaml.safe_load(f)')"

# ===== sec-shell-injection =====
expect_block "py subprocess shell=True blocked" "$(run_write /tmp/x.py 'subprocess.run(cmd, shell=True)')"
expect_block "py os.system blocked" "$(run_write /tmp/x.py 'os.system(cmd)')"
expect_block "py os.popen blocked" "$(run_write /tmp/x.py 'os.popen(cmd)')"
expect_allow "py subprocess shell=False NOT blocked" "$(run_write /tmp/x.py 'subprocess.run(cmd, shell=False)')"
expect_allow "py subprocess argv list NOT blocked" "$(run_write /tmp/x.py 'subprocess.run(["ls", "-l"])')"

# ===== sec-curl-pipe-sh =====
expect_block "sh curl | sh blocked" "$(run_write /tmp/x.sh 'curl -fsSL https://get.docker.com | sh')"
expect_block "sh wget | bash blocked" "$(run_write /tmp/install.bash 'wget -qO- https://example.com/i | bash')"
expect_allow "sh curl > file NOT blocked" "$(run_write /tmp/x.sh 'curl -o /tmp/script.sh https://example.com/s')"
expect_block "sh curl | sudo bash blocked" "$(run_write /tmp/x.sh 'curl -fsSL https://x.io/i | sudo bash')"
expect_block "sh curl | zsh blocked" "$(run_write /tmp/x.sh 'curl -fsSL https://x.io/i | zsh')"
expect_block "sh wget | /bin/sh blocked" "$(run_write /tmp/x.sh 'wget -qO- https://x.io/i | /bin/sh')"
expect_allow "sh curl line + unrelated pipe-to-sh on a LATER line NOT blocked" "$(run_write /tmp/x.sh 'curl -o f.tar https://x.io/f.tar
tar xf f.tar
cat run.txt | sh')"

# ===== sec-tls-bypass =====
expect_block "py verify=False blocked" "$(run_write /tmp/x.py 'r = requests.get(url, verify=False)')"
expect_block "js rejectUnauthorized:false blocked" "$(run_write /tmp/x.js 'new https.Agent({ rejectUnauthorized: false })')"
expect_block "sh --insecure blocked" "$(run_write /tmp/x.sh 'curl --insecure https://example.com')"
expect_allow "py verify=True NOT blocked" "$(run_write /tmp/x.py 'r = requests.get(url, verify=True)')"
expect_allow "sh literal 'insecure-' in word NOT blocked" "$(run_write /tmp/x.sh 'echo insecure-mode-disabled')"

# ===== sec-xss-sink =====
expect_block "js innerHTML= blocked" "$(run_write /tmp/x.js 'el.innerHTML = userInput;')"
expect_block "tsx dangerouslySetInnerHTML blocked" "$(run_write /tmp/x.tsx '<div dangerouslySetInnerHTML={{__html: x}} />')"
expect_block "js document.write blocked" "$(run_write /tmp/x.js 'document.write("<p>" + s + "</p>");')"
expect_allow "js textContent NOT blocked" "$(run_write /tmp/x.js 'el.textContent = userInput;')"

# ===== sec-weak-crypto =====
expect_block "js createHash md5 blocked" "$(run_write /tmp/x.js 'crypto.createHash("md5").update(p).digest()')"
expect_block "js createHash sha1 single-quote blocked" "$(run_write /tmp/x.js "crypto.createHash('sha1').update(p)")"
expect_block "py hashlib.md5 blocked" "$(run_write /tmp/x.py 'h = hashlib.md5(b)')"
expect_allow "js createHash sha256 NOT blocked" "$(run_write /tmp/x.js 'crypto.createHash("sha256").update(p)')"

# ===== Edit-form payload parity =====
expect_block "Edit-form payload blocks too" "$(run_edit /tmp/x.py 'r = eval(s)')"

# ===== Extension scoping =====
expect_allow "py pattern does NOT fire on .js file" "$(run_write /tmp/x.js 'pickle.loads(buf)')"
expect_allow "js pattern does NOT fire on .py file" "$(run_write /tmp/x.py 'el.innerHTML = s')"

# ===== Fail-open on missing inputs =====
expect_allow "empty file_path → allow" "$(echo '{"tool_input": {}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"
expect_allow "empty content → allow" "$(jq -nc '{tool_input: {file_path: "/tmp/x.py"}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"

# ===== safety.json bypass =====
mkdir -p "$TMPDIR_BASE/proj-bypass/.geniro"
echo '{"allow_patterns": ["sec-eval-exec"]}' > "$TMPDIR_BASE/proj-bypass/.geniro/safety.json"
cd "$TMPDIR_BASE/proj-bypass" || exit 1
expect_allow "safety.json bypass: sec-eval-exec allowed" "$(run_write /tmp/x.py 'r = eval(s)')"
expect_block "safety.json bypass: unrelated pattern still blocks" "$(run_write /tmp/x.py 'pickle.loads(buf)')"
cd "$TMPDIR_BASE" || exit 1

# ===== Multiple patterns in one file: first hit blocks =====
expect_block "multiple hits: first blocks" "$(run_write /tmp/x.py "$(printf 'r = eval(s)\npickle.loads(buf)')")"

# ===== MultiEdit-form payload: edits[].new_string must be scanned =====
# (the dangerous download-pipe fragment is assembled via printf so the literal
#  pattern never appears in this .sh source and trip the guard on this very edit)
expect_block "MultiEdit edits[] with eval blocks" "$(run_multiedit /tmp/x.py 'r = eval(s)')"
expect_block "MultiEdit edits[] with download-pipe-to-sh blocks" "$(run_multiedit /tmp/x.sh "$(printf 'curl https://x.example | %s' sh)")"
expect_allow "MultiEdit edits[] clean allows" "$(run_multiedit /tmp/x.py 'return 42')"

# ===== Multi-line anti-pattern split across lines is caught (perl -0777 slurp) =====
expect_block "download-pipe-to-sh split across lines blocks" "$(run_write /tmp/x.sh "$(printf 'curl https://x.example \\\n  | %s\n' sh)")"
expect_allow "curl without pipe-to-sh allows" "$(run_write /tmp/x.sh 'curl https://x.example -o out')"

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
