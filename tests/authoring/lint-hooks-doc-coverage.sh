#!/usr/bin/env bash
# C13 (plugin-audit 2026-09-23, fix-plan §O / T3-2) — HOOKS.md documents every
# literal `is_allowed "<id>"` bypass ID a hooks/*.sh guard checks.
#
# Run: bash tests/authoring/lint-hooks-doc-coverage.sh
#
# Why this exists: D2 §"Bypass-list integrity" — every hook bypass branch
# needs a documented ID, or a user hitting a block has no way to know what
# `allow_patterns[]` entry opts out of it. T3-2: `worktree-remove-force` is
# implemented and bypassable in `block-dangerous-git.sh` but was undocumented
# in HOOKS.md and README.md.
#
# Detection: extract every literal (double-quoted) `is_allowed "<id>"` call
# site across hooks/*.sh, and confirm the ID appears backtick-quoted
# somewhere in HOOKS.md. Scope note: `security-pattern-check.sh` calls
# `is_allowed "$id"` with a VARIABLE, not a literal — its pattern IDs
# (`sec-eval-exec`, etc.) are documented in HOOKS.md by a different, already-
# audited mechanism (its own pattern-ID table) and are out of scope for this
# literal-call-site check by construction (the pattern below requires a
# double-quoted, non-`$`-prefixed argument).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# <dir> -> file:line:id for every literal is_allowed "<id>" call.
_is_allowed_literals() {
  grep -rnoE 'is_allowed[[:space:]]+"[A-Za-z0-9_-]+"' "$@" 2>/dev/null \
    | sed -E 's/is_allowed[[:space:]]+"([^"]+)"/\1/'
}

checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  checked=$((checked + 1))
  f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"; id="${rest#*:}"
  if ! grep -qF "\`$id\`" HOOKS.md 2>/dev/null; then
    report_fail "$f:$l — bypass ID \`$id\` is not documented anywhere in HOOKS.md (\`$id\` never appears backtick-quoted there)"
  fi
done < <(_is_allowed_literals hooks)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: every literal is_allowed \"<id>\" bypass in hooks/*.sh is documented in HOOKS.md ($checked distinct ID(s) checked)"
fi

# --- self-test: red on a seeded undocumented ID, green on a documented one ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/hooks"

cat > "$SELFTEST_DIR/hooks/probe-guard.sh" <<'EOF'
if ! is_allowed "probe-undocumented-id"; then
  echo "blocked" >&2
  exit 2
fi
if ! is_allowed "probe-documented-id"; then
  echo "blocked" >&2
  exit 2
fi
if ! is_allowed "$id"; then
  return 0
fi
EOF

run_check() {
  local hooks_md="$1"
  local f l id
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"; id="${rest#*:}"
    grep -qF "\`$id\`" "$hooks_md" 2>/dev/null || echo "UNDOCUMENTED:$id"
  done < <(grep -rnoE 'is_allowed[[:space:]]+"[A-Za-z0-9_-]+"' "$SELFTEST_DIR/hooks" 2>/dev/null \
    | sed -E 's/is_allowed[[:space:]]+"([^"]+)"/\1/')
}

printf 'Bypass: `probe-documented-id`\n' > "$SELFTEST_DIR/HOOKS-partial.md"
out=$(run_check "$SELFTEST_DIR/HOOKS-partial.md")
if printf '%s\n' "$out" | grep -q 'UNDOCUMENTED:probe-undocumented-id'; then
  echo "OK: self-test — a bypass ID absent from HOOKS.md is detected"
else
  report_fail "self-test — the seeded undocumented ID was NOT detected. Output: $out"
fi
if ! printf '%s\n' "$out" | grep -q 'UNDOCUMENTED:probe-documented-id'; then
  echo "OK: self-test — a bypass ID that IS backtick-quoted in HOOKS.md is not flagged"
else
  report_fail "self-test — a documented ID was wrongly flagged"
fi
if ! printf '%s\n' "$out" | grep -q 'UNDOCUMENTED:\$id'; then
  echo "OK: self-test — a variable is_allowed \"\$id\" call (security-pattern-check.sh's shape) is not extracted at all"
else
  report_fail "self-test — a variable-argument is_allowed call was wrongly treated as a literal ID"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS undocumented hook bypass ID problem(s)." >&2
  exit 1
fi
echo "OK: HOOKS.md documents every literal is_allowed bypass ID in hooks/*.sh."
