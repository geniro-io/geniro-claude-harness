#!/usr/bin/env bash
# HOOKS.md documents every script in hooks/, no deleted one, and every bypass ID
# a hook checks.
#
# Run: bash tests/authoring/lint-hooks-doc-coverage.sh
#
# Why this exists: a user hitting a block needs the `allow_patterns[]` entry
# that opts out of it, and a reader needs each shipped hook — and no deleted
# one — to have its own section. Both drift silently: plugin-audit 2026-09-23
# T3-2 found a bypassable guard whose ID HOOKS.md never named.
#
# Checks:
#   1. Every hooks/*.sh and hooks/*.js has a `### <basename>` heading in
#      HOOKS.md (backticks around the name and trailing text are allowed).
#   2. Every `### <name>.sh|.js` heading names a script still in hooks/. A
#      deleted hook keeps no section; naming it in prose or a table is fine.
#   3. Every bypass ID a hook looks up — the literal `index("<id>")` on a
#      non-comment line reading `.allow_patterns` — appears backtick-quoted
#      somewhere in HOOKS.md.
#   4. A hook that reads `.allow_patterns` yields at least one such ID, so a
#      lookup rewritten into another shape fails here instead of leaving
#      check 3 with nothing to check.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# check_tree <hooks-dir> <hooks-md> -> one line per problem, nothing when clean.
check_tree() {
  local dir="$1" md="$2" headings f name code ids id
  headings="$(sed -nE 's/^###[[:space:]]+`?([A-Za-z0-9._-]+\.(sh|js))`?([[:space:]].*)?$/\1/p' "$md")"
  for f in "$dir"/*.sh "$dir"/*.js; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    grep -qxF "$name" <<< "$headings" || echo "hooks/$name has no \`### $name\` section in HOOKS.md"
    case "$name" in *.sh) ;; *) continue ;; esac
    code="$(grep -v '^[[:space:]]*#' "$f")"
    grep -qF '.allow_patterns' <<< "$code" || continue
    ids="$(grep -F '.allow_patterns' <<< "$code" | grep -oE 'index\("[A-Za-z0-9_-]+"\)' \
      | sed -E 's/index\("([^"]+)"\)/\1/' | sort -u)"
    if [ -z "$ids" ]; then
      echo "hooks/$name reads .allow_patterns but has no literal index(\"<id>\") lookup — teach this lint the new shape"
      continue
    fi
    while IFS= read -r id; do
      grep -qF "\`$id\`" "$md" || echo "hooks/$name bypass ID \`$id\` is not backtick-quoted anywhere in HOOKS.md"
    done <<< "$ids"
  done
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ -f "$dir/$name" ] || echo "HOOKS.md has a \`### $name\` section but hooks/$name does not exist"
  done <<< "$headings"
}

problems="$(check_tree hooks HOOKS.md)"
if [ -n "$problems" ]; then
  while IFS= read -r p; do report_fail "$p"; done <<< "$problems"
else
  echo "OK: HOOKS.md has a section for every hooks/ script, none for a deleted one, and names every bypass ID"
fi

# --- self-test: each check goes red on a seeded problem and stays quiet otherwise ---
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/hooks"
cat > "$SELFTEST_DIR/hooks/probe-guard.sh" <<'EOF'
# A comment naming .allow_patterns | index("probe-comment-id") is not a lookup.
jq -e '(.allow_patterns // []) | index("probe-documented-id")' "$f"
jq -e '(.allow_patterns // []) | index("probe-undocumented-id")' "$f"
EOF
cat > "$SELFTEST_DIR/hooks/probe-reshaped.sh" <<'EOF'
jq -e --arg id "$ID" '(.allow_patterns // []) | index($id)' "$f"
EOF
cat > "$SELFTEST_DIR/HOOKS.md" <<'EOF'
### probe-guard.sh
Bypass: `probe-documented-id`
### `probe-deleted.sh` (removed)
EOF
out="$(check_tree "$SELFTEST_DIR/hooks" "$SELFTEST_DIR/HOOKS.md")"

expect() { # <label> <needle> <present|absent>
  local found=absent
  grep -qF "$2" <<< "$out" && found=present
  if [ "$found" = "$3" ]; then
    echo "OK: self-test — $1"
  else
    report_fail "self-test — $1 (expected '$2' $3). Output: $out"
  fi
}
expect "an undocumented bypass ID is detected"          '`probe-undocumented-id`'                     present
expect "a documented bypass ID is not flagged"          '`probe-documented-id`'                       absent
expect "a comment line is not read as a lookup"         'probe-comment-id'                            absent
expect "a hook with no section is detected"             'hooks/probe-reshaped.sh has no'              present
expect "a hook with its section is not flagged"         'hooks/probe-guard.sh has no'                 absent
expect "a lookup in an unknown shape is detected"       'probe-reshaped.sh reads .allow_patterns'     present
expect "a section for a deleted hook is detected"       'hooks/probe-deleted.sh does not exist'       present

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS HOOKS.md coverage problem(s)." >&2
  exit 1
fi
echo "OK: HOOKS.md covers every hook script and bypass ID in hooks/."
