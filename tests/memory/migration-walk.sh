#!/usr/bin/env bash
# Behavior test for lib/migration-walk.sh — runs the walk on a fixture
# MIGRATION.md carrying every class, then on the real MIGRATION.md.
#
# Run: bash tests/memory/migration-walk.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi; }

# shellcheck source=../../lib/migration-walk.sh
source "$REPO_ROOT/lib/migration-walk.sh"

PROJ="$TMP/proj"
mkdir -p "$PROJ"
printf 'stale\n' > "$PROJ/marker.txt"
SENTINEL="$TMP/sentinel"

cat > "$TMP/M.md" <<FIX
# Migration Notes

## v9.0.0

### inline hit

**Auto-detect:** \`grep -Hn stale marker.txt\`

### fenced hit

**Auto-detect:**

\`\`\`bash
x=1
grep -l stale marker.txt
\`\`\`

**Auto-fix:**

\`\`\`bash
rm -rf /never-run
\`\`\`

### clean

**Auto-detect:** \`grep -l absent marker.txt\`

### informational

**Auto-detect:** n/a — touch $SENTINEL; echo ran

### no detector

**Action required:** nothing.

### broken syntax

**Auto-detect:** \`if then fi (\`

### command missing

**Auto-detect:** \`geniro-no-such-command-xyz\`

### hostile

**Auto-detect:** \`cd /; set -e; exit 9\`
FIX

out="$(migration_walk "$TMP/M.md" "$PROJ")"; rc=$?
check "rc 0 on a parseable file" 0 "$rc"
cls() { printf '%s\n' "$out" | awk -F'\t' -v t="$1" '$1 == t { print $2 }'; }
check "inline backtick detector with output -> applies" applies "$(cls 'inline hit')"
check "fenced multi-line detector with output -> applies" applies "$(cls 'fenced hit')"
check "first output line carried as detail" "marker.txt:1:stale" \
  "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "inline hit" { print $3 }')"
check "empty output -> not-applicable" not-applicable "$(cls clean)"
check "N/A value -> informational" informational "$(cls informational)"
[ ! -e "$SENTINEL" ] && pass "N/A prose never reached a shell" || fail "N/A prose was executed"
check "entry without detector -> not-applicable" not-applicable "$(cls 'no detector')"
check "invalid bash -> detector-error" detector-error "$(cls 'broken syntax')"
check "missing command (rc 127) -> detector-error" detector-error "$(cls 'command missing')"
check "detector that cd/exit/set -e does not stop the walk" not-applicable "$(cls hostile)"
check "one row per entry, in file order" 8 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
check "caller cwd untouched" "$PWD" "$(pwd)"

migration_walk "$TMP/nope.md" >/dev/null 2>&1; check "absent file -> rc 65" 65 "$?"
migration_walk >/dev/null 2>&1; check "no args -> rc 64" 64 "$?"
printf '# no entries\n' > "$TMP/empty.md"
migration_walk "$TMP/empty.md" "$PROJ" >/dev/null 2>&1; check "no entries -> rc 66" 66 "$?"
printf '### x\n\n**Auto-detect:**\n\n```bash\nls\n' > "$TMP/open.md"
migration_walk "$TMP/open.md" "$PROJ" >/dev/null 2>&1; check "unterminated fence -> rc 66" 66 "$?"

# Real file: one row per `### ` entry, only known classes.
real="$(migration_walk "$REPO_ROOT/MIGRATION.md" "$PROJ")"; rc=$?
check "real MIGRATION.md walks, rc 0" 0 "$rc"
check "real MIGRATION.md: one row per entry" "$(grep -c '^### ' "$REPO_ROOT/MIGRATION.md")" \
  "$(printf '%s\n' "$real" | wc -l | tr -d ' ')"
bad="$(printf '%s\n' "$real" | awk -F'\t' '$2 !~ /^(applies|not-applicable|informational|detector-error)$/' | wc -l | tr -d ' ')"
check "real MIGRATION.md: every class known" 0 "$bad"
check "real MIGRATION.md: no detector-error in a scratch project" 0 \
  "$(printf '%s\n' "$real" | awk -F'\t' '$2 == "detector-error"' | wc -l | tr -d ' ')"

if command -v zsh >/dev/null 2>&1; then
  z="$(zsh -c "source '$REPO_ROOT/lib/migration-walk.sh' && migration_walk '$TMP/M.md' '$PROJ'" | wc -l | tr -d ' ')"
  check "sourceable and runnable under zsh" 8 "$z"
fi

echo; echo "Tests run:    $TESTS_RUN"; echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
