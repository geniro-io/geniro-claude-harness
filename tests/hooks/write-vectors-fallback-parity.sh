#!/usr/bin/env bash
# Vendored-fallback drift guard for lib/write-vectors.sh.
#
# Run: bash tests/hooks/write-vectors-fallback-parity.sh
#
# Every Bash guard sources lib/write-vectors.sh and carries an INLINE FALLBACK
# copy of the functions it uses, so a vendored install shipping hooks/ without
# lib/ still recurses into shell indirection and interpreter writes — "a missing
# helper must never make a guard fail open" (the helper's own header).
#
# That fallback is a second copy of a security-critical scanner, and a second
# copy drifts. It already had: with CLAUDE_PLUGIN_ROOT unset, file-protection.sh
# allowed `Path('.env').open('w')` that it blocks with lib/ present. A one-sided
# fix to the canonical helper silently leaves the vendored path open, so this
# suite fails CI on exactly that.
#
# Two independent assertions per guard:
#   1. TEXT   — each inline fallback, normalized (comments dropped, whitespace
#               and `;` flattened), is identical to the canonical function of the
#               same name. Precise enough to catch a single missing regex arm.
#               Also: a canonical function the guard CALLS must have a fallback,
#               or the vendored install hits a command-not-found instead.
#   2. EFFECT — the guard's exit code on a channel matrix is identical with lib/
#               present and with lib/ absent. This is the property the drift was
#               measured as, and it holds no matter how the fallback is spelled.
#
# Portability: bash 3.2 / BSD, no writes outside a mktemp sandbox, no network.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CANON="$REPO_ROOT/lib/write-vectors.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

if [ ! -f "$CANON" ]; then
  echo "FAIL: canonical helper missing: $CANON" >&2
  exit 1
fi

# --- extraction --------------------------------------------------------------
# A shell function's source, signature line through the closing brace that sits
# at the SAME indentation. Brace COUNTING would be wrong here: these bodies carry
# `${…}` expansions and `{1,2}` regex intervals inside strings.
extract_fn() {  # <file> <fn-name>
  awk -v fn="$2" '
    !inb {
      i = index($0, fn "() {")
      if (i > 0) {
        pre = substr($0, 1, i - 1)
        if (pre ~ /^[ \t]*$/) { indent = length(pre); inb = 1; print; next }
      }
      next
    }
    {
      print
      line = $0
      sub(/[ \t]+$/, "", line)
      n = match(line, /[^ \t]/)
      if (n > 0 && substr(line, n) == "}" && n - 1 == indent) exit
    }
  ' "$1"
}

# Canonical form for comparison: drop whole-line comments (the fallback carries
# its own preamble and drops the arm headings), then flatten every whitespace run
# and statement separator, so `if X; then Y; fi` on one line equals the same
# three lines. What survives is the executable text — a dropped regex arm, a
# changed character class or a missing branch all still differ.
normalize_fn() {
  sed -e 's/^[ \t]*//' -e 's/[ \t]*$//' \
    | { grep -v '^#' || true; } \
    | { grep -v '^$' || true; } \
    | tr '\n;' '  ' \
    | tr -s ' ' ' ' \
    | sed -e 's/^ *//' -e 's/ *$//'
}

# Where two normalized strings first diverge, with a little context each side —
# a bare "not identical" on a 1,500-character regex body is unusable.
first_divergence() {  # <want> <got>
  awk -v a="$1" -v b="$2" '
    BEGIN {
      n = (length(a) < length(b)) ? length(a) : length(b)
      for (i = 1; i <= n; i++) if (substr(a, i, 1) != substr(b, i, 1)) break
      s = (i > 40) ? i - 40 : 1
      printf "at char %d\n      canonical: …%s…\n      fallback:  …%s…",
             i, substr(a, s, 90), substr(b, s, 90)
    }'
}

# --- 1. TEXT: every inline fallback matches the canonical function ------------
canon_fns=$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\) \{' "$CANON" | sed 's/() {$//' | LC_ALL=C sort -u)
if [ -z "$canon_fns" ]; then
  fail "parsed zero functions from $CANON — the definition-line shape drifted; fix this parser's anchor"
fi

guards=$(grep -lE 'lib/write-vectors\.sh' "$REPO_ROOT"/hooks/*.sh 2>/dev/null | LC_ALL=C sort)
if [ -z "$guards" ]; then
  fail "no hook sources lib/write-vectors.sh — the helper has no consumers, or the sourcing path changed"
fi

while IFS= read -r hook; do
  [ -z "$hook" ] && continue
  hname="$(basename "$hook")"
  while IFS= read -r fn; do
    [ -z "$fn" ] && continue
    # "Uses" = the name appears in the guard at all. A guard that never mentions a
    # canonical function needs no fallback for it.
    grep -q "$fn" "$hook" || continue
    fb=$(extract_fn "$hook" "$fn")
    if [ -z "$fb" ]; then
      fail "$hname: calls $fn but carries no inline fallback — a vendored install (no lib/) hits command-not-found and the guard fails open"
      continue
    fi
    want=$(extract_fn "$CANON" "$fn" | normalize_fn)
    got=$(printf '%s\n' "$fb" | normalize_fn)
    if [ "$want" = "$got" ]; then
      pass "$hname: inline fallback for $fn matches lib/write-vectors.sh"
    else
      fail "$hname: inline fallback for $fn has DRIFTED from lib/write-vectors.sh — $(first_divergence "$want" "$got")"
    fi
  done <<< "$canon_fns"
done <<< "$guards"

# --- 2. EFFECT: the guard decides identically with and without lib/ -----------
# The vendored install is simulated by unsetting CLAUDE_PLUGIN_ROOT and running
# from a directory that has no lib/ — exactly what `${CLAUDE_PLUGIN_ROOT:-.}`
# resolves against there.
SANDBOX="$TMPDIR_BASE/vendored"
mkdir -p "$SANDBOX"
cd "$SANDBOX" || exit 1
git init -q 2>/dev/null || true

hook_rc() {  # <hook-path> <with|without> <command>
  local hook="$1" mode="$2" cmd="$3" rc
  if [ "$mode" = "with" ]; then
    printf '%s' "$cmd" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' \
      | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$hook" >/dev/null 2>&1
    rc=$?
  else
    printf '%s' "$cmd" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' \
      | env -u CLAUDE_PLUGIN_ROOT bash "$hook" >/dev/null 2>&1
    rc=$?
  fi
  echo "$rc"
}

# Each probe asserts BOTH halves: the two modes agree, AND they agree on the
# RIGHT verdict. Parity alone is satisfiable by a guard that is broken in both
# modes (a syntax error exits 2 on every input), which would make the whole
# matrix vacuous — the benign controls are what keep it honest.
expect_parity() {  # <hook-basename> <expected-rc> <label> <command>
  local hook="$REPO_ROOT/hooks/$1" want="$2" label="$3" cmd="$4" a b
  a=$(hook_rc "$hook" with "$cmd")
  b=$(hook_rc "$hook" without "$cmd")
  if [ "$a" != "$b" ]; then
    if [ "$a" = "2" ]; then
      fail "$1 [$label]: FAILS OPEN on a vendored install — exit=$a with lib/, exit=$b without"
    else
      fail "$1 [$label]: over-blocks on a vendored install — exit=$a with lib/, exit=$b without"
    fi
  elif [ "$a" != "$want" ]; then
    fail "$1 [$label]: both modes agree on the WRONG verdict — exit=$a (expected $want)"
  else
    pass "$1 [$label]: same correct verdict with and without lib/ (exit=$a)"
  fi
}

# Channel matrix — one probe per indirection shape the helper models, against the
# guard whose protected paths make the shape observable. 2 = blocked, 0 = allowed.
PROT=".env"
STATE=".geniro/planning/task/state.md"
GTREE=".geniro/instructions"

expect_parity file-protection.sh 2 "plain redirect"     "echo x > $PROT"
expect_parity file-protection.sh 2 "sh -c"              "sh -c 'echo x > $PROT'"
expect_parity file-protection.sh 2 "eval"               "eval \"echo x > $PROT\""
expect_parity file-protection.sh 2 "pipe-to-shell"      "echo \"echo x > $PROT\" | bash"
expect_parity file-protection.sh 2 "heredoc-to-shell"   "$(printf 'bash <<EOF\necho x > %s\nEOF\n' "$PROT")"
expect_parity file-protection.sh 2 "python open(w)"     "python3 -c \"open('$PROT','w').write('k')\""
expect_parity file-protection.sh 2 "pathlib open(w)"    "python3 -c \"from pathlib import Path; Path('$PROT').open('w')\""
expect_parity file-protection.sh 2 "pathlib touch"      "python3 -c \"from pathlib import Path; Path('$PROT').touch()\""
expect_parity file-protection.sh 2 "node writeFileSync" "node -e \"require('fs').writeFileSync('$PROT','k')\""
expect_parity file-protection.sh 2 "shutil.copy"        "python3 -c \"import shutil; shutil.copy('t','$PROT')\""
expect_parity file-protection.sh 2 "os.rename"          "python3 -c \"import os; os.rename('t','$PROT')\""
expect_parity file-protection.sh 0 "benign write"       "echo x > src/app.js"
expect_parity file-protection.sh 0 "benign interp read" "python3 -c \"print(open('src/app.js').read())\""

expect_parity block-geniro-deletion.sh 2 "sh -c delete"    "sh -c 'rm -rf $GTREE'"
expect_parity block-geniro-deletion.sh 2 "pipe-to-shell"   "echo \"rm -rf $GTREE\" | bash"
expect_parity block-geniro-deletion.sh 2 "interp delete"   "python3 -c \"import shutil; shutil.rmtree('$GTREE')\""
expect_parity block-geniro-deletion.sh 2 "interp move"     "python3 -c \"import shutil; shutil.move('$GTREE','/tmp/gone')\""
expect_parity block-geniro-deletion.sh 0 "benign delete"   "rm -f build/out.o"

expect_parity enforce-state-helper.sh 2 "sh -c state write"  "sh -c 'echo x > $STATE'"
expect_parity enforce-state-helper.sh 2 "pipe-to-shell"      "echo \"echo x > $STATE\" | bash"
expect_parity enforce-state-helper.sh 2 "interp state write" "python3 -c \"open('$STATE','w').write('k')\""
expect_parity enforce-state-helper.sh 2 "pathlib state open" "python3 -c \"from pathlib import Path; Path('$STATE').open('w')\""
expect_parity enforce-state-helper.sh 0 "benign write"       "echo x > notes.txt"

expect_parity block-dangerous-git.sh 2 "sh -c force push" "sh -c 'git push --force origin main'"
expect_parity block-dangerous-git.sh 2 "pipe-to-shell"    "echo \"git push --force origin main\" | bash"
expect_parity block-dangerous-git.sh 0 "benign push"      "git push origin feature/x"

cd "$ORIGINAL_PWD" || exit 1

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
