#!/usr/bin/env bash
# Cross-guard write-vector matrix (T4-5).
#
# Run: bash tests/hooks/write-vectors-matrix.sh
#
# The structural cause behind several of the 2026-08-07 audit's T0 findings:
# file-protection.sh carries an INLINE, hand-duplicated copy of the same
# nine-plus syntax vectors (redirect, tee, sed -i, cp/mv, dd of=, truncate,
# shred, install/rsync, ln -f, sponge/ed/ex/patch, curl -o/wget -O) — they are
# NOT functions in lib/write-vectors.sh, so
# tests/hooks/write-vectors-fallback-parity.sh (which enumerates only the
# canonical file's FUNCTION DEFINITIONS) cannot see them drift.
#
# This suite is the structural fix: ONE vector list, driven against the
# guard's own protected-target fixture and a benign control. A vector added to
# (or fixed on) the guard without a matching case here now fails CI
# immediately, instead of silently sitting open until the next audit
# re-discovers it by hand.
#
# Portability: bash 3.2 / BSD, no writes outside a mktemp sandbox, no network.
# Payloads are inert text — the guards parse the command out of stdin JSON and
# never execute it, so none of `gawk`/`sponge`/`wget`/`ed`/`ex` need to be
# installed for this suite to run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# The single vector list. {T} is substituted with the guard's protected/benign
# target. Each id names the HOOKS.md vector item it exercises.
VECTORS='
redirect|echo x > {T}
tee|echo x | tee {T}
sed-i|sed -i.bak "s/a/b/" {T}
awk-i-inplace|gawk -i inplace "{print}" {T}
cp-dest|cp /tmp/src {T}
mv-dest|mv /tmp/src {T}
dd-of|dd if=/dev/zero of={T}
truncate|truncate -s 0 {T}
shred|shred {T}
rsync-dest|rsync -a /tmp/src/ {T}
ln-f|ln -f /tmp/src {T}
sponge|cat /tmp/src | sponge {T}
ed|printf "w\nq\n" | ed {T}
ex|ex -sc "wq" {T}
patch|patch {T} < /tmp/a.diff
curl-o|curl -o {T} https://x.example
wget-O|wget -O {T} https://x.example
cp-dest-trailing-redir|cp /tmp/src {T} 2>/dev/null
mv-dest-trailing-redir|mv /tmp/src {T} 2>&1
rsync-dest-trailing-redir|rsync -a /tmp/src/ {T} 2>/dev/null
ln-f-trailing-redir|ln -f /tmp/src {T} 2>/dev/null
sponge-trailing-stdin|sponge {T} < /tmp/in
ed-trailing-stdin|ed {T} < /tmp/patch.txt
ex-trailing-stdin|ex -sc "wq" {T} < /tmp/in
'

run_guard() {  # <hook-path> <command>
  local hook="$1" cmd="$2"
  printf '%s' "$cmd" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' \
    | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$hook" >/dev/null 2>&1
  echo $?
}

matrix_for_guard() {  # <label> <hook-path> <protected-target> <benign-target>
  local label="$1" hook="$2" target="$3" benign="$4" id tmpl cmd rc
  while IFS='|' read -r id tmpl; do
    [ -z "$id" ] && continue
    cmd="${tmpl//\{T\}/$target}"
    rc=$(run_guard "$hook" "$cmd")
    if [ "$rc" = "2" ]; then
      pass "$label [$id]: protected target blocks (rc=2)"
    else
      fail "$label [$id]: protected target did NOT block — rc=$rc, cmd=$cmd"
    fi
    cmd="${tmpl//\{T\}/$benign}"
    rc=$(run_guard "$hook" "$cmd")
    if [ "$rc" = "0" ]; then
      pass "$label [$id]: benign target allows (rc=0)"
    else
      fail "$label [$id]: benign target was BLOCKED (over-block) — rc=$rc, cmd=$cmd"
    fi
  done <<< "$VECTORS"
}

# ===== file-protection.sh =====
matrix_for_guard "file-protection.sh" "$REPO_ROOT/hooks/file-protection.sh" "tls.key" "notes.txt"

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
