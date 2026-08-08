#!/usr/bin/env bash
# Cross-guard OBFUSCATION matrix — the spelling axis.
#
# Run: bash tests/hooks/obfuscation-matrix.sh
#
# tests/hooks/write-vectors-matrix.sh drives one axis: which OPERATION reaches a
# protected target (redirect, tee, sed -i, dd, ...). This suite drives the other:
# for one operation a guard already blocks, which SPELLINGS of the same command
# still reach it. Every 2026-08-07 T0 finding lived on this axis — the guard
# caught the plain form and missed a re-spelling that runs the identical program
# (`git push $'--force'`, a newline instead of `&&`, `--mirror`, a `pushd`
# prefix). Each had a regression test for the spelling that had been fixed and
# none for its siblings, which is why the next audit re-found the class by hand.
#
# The rule this encodes: a guard matches PROGRAMS, and the shell offers many
# spellings per program. A spelling the shell resolves to a blocked command must
# block; a benign command wearing the same spelling must not. The second half is
# the one that keeps a fix honest — unquoting operands to catch `> '.env'` is
# only correct while `echo "set x > .env to configure"` still passes.
#
# Adding a guard here costs one BASES row. Adding a spelling costs one TRANSFORMS
# row and is immediately driven against every guard, which is the property the
# hand-written per-guard suites did not have.
#
# Portability: bash 3.2 / BSD, no writes outside a mktemp sandbox, no network.
# Payloads are inert text — guards parse the command out of stdin JSON and never
# execute it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# ---------------------------------------------------------------------------
# The spelling list. {C} is the command under test. `\n` is expanded to a real
# newline by printf %b, so a multi-line spelling stays one table row.
#
# Each entry is a way the shell reaches the SAME program: quoting that a word
# splitter removes, a separator other than &&, a wrapper that changes only the
# process environment, an indirection that hands the text to a shell, or a
# grouping construct. None changes what runs.
# ---------------------------------------------------------------------------
TRANSFORMS='
plain|{C}
newline-sep|echo hi\n{C}
semicolon-sep|echo hi; {C}
and-sep|echo hi && {C}
or-chain|false || {C}
env-wrapper|env FOO=bar {C}
timeout-wrapper|timeout 5 {C}
nohup-wrapper|nohup {C}
subshell|({C})
brace-group|{ {C}; }
background|{C} &
trailing-comment|{C}  # routine cleanup
leading-space|   {C}
sh-c|sh -c "{C}"
eval|eval "{C}"
pipe-to-bash|echo "{C}" | bash
heredoc-to-bash|bash <<XEOF\n{C}\nXEOF
command-builtin|command {C}
'

# ---------------------------------------------------------------------------
# Per-guard: a command that MUST block, and one that MUST NOT. Both are driven
# through every spelling above. The benign command is chosen to be structurally
# similar to the dangerous one, so a matcher that over-generalizes fails here
# rather than in production.
# ---------------------------------------------------------------------------
BASES='
block-dangerous-git.sh|push-force|git push --force origin main|git push origin main
block-dangerous-git.sh|clean-fd|git clean -fd|git clean -n
block-dangerous-git.sh|reset-hard|git reset --hard HEAD~1|git reset HEAD~1
block-dangerous-git.sh|push-mirror|git push --mirror origin|git push --tags origin
block-geniro-deletion.sh|rm-geniro|rm -rf .geniro|rm -rf build
file-protection.sh|write-env|echo k > .env|echo k > notes.txt
enforce-state-helper.sh|write-state|echo k > .geniro/planning/t/state.md|echo k > notes.txt
'

# ---------------------------------------------------------------------------
# Word-level re-spellings of the FLAG, applied only to bases that carry one.
# These are the shapes lib/write-vectors.sh §E canonicalizes; a guard matching
# the literal flag text misses every one of them.
# ---------------------------------------------------------------------------
FLAG_SPELLINGS='
ansi-c-quote|$FLAG
single-quote|FLAG
double-quote|FLAG
intraword-dq|FLAG
intraword-sq|FLAG
backslash-dash|FLAG
backslash-midword|FLAG
'

run_guard() {  # <hook> <command>
  printf '%s' "$2" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' \
    | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/$1" >/dev/null 2>&1
  echo $?
}

check() {  # <label> <hook> <command> <want-rc>
  local rc
  rc=$(run_guard "$2" "$3")
  if [ "$rc" = "$4" ]; then
    pass "$1"
  else
    fail "$1 — rc=$rc want=$4, cmd=$(printf '%s' "$3" | tr '\n' '~')"
  fi
}

# --- axis 1: every spelling, every guard, block-and-allow ------------------
while IFS='|' read -r hook id danger benign; do
  [ -z "$hook" ] && continue
  while IFS='|' read -r tid tmpl; do
    [ -z "$tid" ] && continue
    check "$hook [$id/$tid] dangerous blocks" "$hook" \
      "$(printf '%b' "${tmpl//\{C\}/$danger}")" 2
    check "$hook [$id/$tid] benign allows" "$hook" \
      "$(printf '%b' "${tmpl//\{C\}/$benign}")" 0
  done <<< "$TRANSFORMS"
done <<< "$BASES"

# --- axis 2: flag re-spellings ---------------------------------------------
# Built by substitution rather than by table text, so the quoting survives this
# file's own parsing exactly as the shell would see it.
flag_variants() {  # <flag> -> "id|spelling" lines
  local f="$1" body="${1#--}"
  printf '%s\n' \
    "ansi-c-quote|\$'$f'" \
    "single-quote|'$f'" \
    "double-quote|\"$f\"" \
    "intraword-dq|--${body:0:2}\"\"${body:2}" \
    "intraword-sq|--${body:0:2}''${body:2}" \
    "backslash-dash|\\-\\-$body" \
    "backslash-midword|--${body:0:2}\\${body:2}"
}

while IFS='|' read -r hook id danger _benign; do
  [ -z "$hook" ] && continue
  case "$danger" in *' --'*) ;; *) continue ;; esac
  flag="${danger#* --}"; flag="--${flag%% *}"
  while IFS='|' read -r sid spelling; do
    [ -z "$sid" ] && continue
    check "$hook [$id/flag:$sid] blocks" "$hook" \
      "${danger/$flag/$spelling}" 2
  done <<< "$(flag_variants "$flag")"
done <<< "$BASES"

# --- axis 3: a directory change hides every later relative operand ----------
# `cd`/`pushd` into a guarded tree is not a spelling of the command; it is a
# spelling of the TARGET, and it applies to every guard that matches paths.
for pre in "cd .geniro &&" "pushd .geniro &&"; do
  check "file-protection.sh [cd-prefix: ${pre%% *}] blocks" "file-protection.sh" \
    "$pre echo k > .env" 2
  check "enforce-state-helper.sh [cd-prefix: ${pre%% *}] blocks" "enforce-state-helper.sh" \
    "$pre echo k > planning/t/state.md" 2
  check "block-geniro-deletion.sh [cd-prefix: ${pre%% *}] blocks" "block-geniro-deletion.sh" \
    "$pre rm -rf planning" 2
done

# --- axis 4: a value carried in through a variable --------------------------
# A variable can hold the subcommand, the flag, the whole command, or the path
# an otherwise-plain command acts on. All four reach the shell as their value,
# so all four must match; a variable holding something benign must not.
check "block-dangerous-git.sh [var: subcommand] blocks" "block-dangerous-git.sh" \
  'SUB=push; git $SUB --force origin main' 2
check "block-dangerous-git.sh [var: braced subcommand] blocks" "block-dangerous-git.sh" \
  'SUB=push; git ${SUB} --force origin main' 2
check "block-dangerous-git.sh [var: whole command] blocks" "block-dangerous-git.sh" \
  'C="git push --force origin main"; $C' 2
check "block-dangerous-git.sh [var: benign subcommand] allows" "block-dangerous-git.sh" \
  'B=status; git $B' 0
check "block-geniro-deletion.sh [var: path] blocks" "block-geniro-deletion.sh" \
  'P=.geniro; rm -rf $P' 2
check "block-geniro-deletion.sh [var: benign path] allows" "block-geniro-deletion.sh" \
  'P=build; rm -rf $P' 0
check "file-protection.sh [var: target] blocks" "file-protection.sh" \
  'T=.env; echo k > $T' 2
check "file-protection.sh [var: benign target] allows" "file-protection.sh" \
  'T=notes.txt; echo k > $T' 0
# A value that is itself a substitution is NOT chased — nothing here evaluates
# anything, so an unresolvable value must leave the text alone rather than
# blank it and hide what follows.
check "block-dangerous-git.sh [var: unresolvable value] allows" "block-dangerous-git.sh" \
  'V=$(date); echo $V' 0

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
