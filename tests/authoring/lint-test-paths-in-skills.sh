#!/usr/bin/env bash
# T2-3 (plugin-audit 2026-10-19) — no skills/ or agents/ file cites one of this
# repo's own test scripts (`tests/<dir>/<file>.sh`).
#
# Run: bash tests/authoring/lint-test-paths-in-skills.sh
#
# Why this exists: skills/ and agents/ ship to every repo that installs the
# plugin, and a downstream repo has no `tests/memory/query-learnings.sh`.
# A helper that says "only tests/memory/query-learnings.sh exercises it" or
# cites a suite as a call site hands its reader a path that resolves nowhere,
# and the sentence only makes sense to a contributor — skill-authoring.md §2
# (plugin-author-internal references) and §5 (out-of-scope content). The audit
# found three such citations; each carried a runtime fact ("no shipped caller
# invokes record_access") that stands without the path.
#
# Detection: `tests/` followed by at least one directory and a `.sh` file. A
# test script path always has that shape; the corpus's other uses of `tests/`
# — a user project's `tests/api/handler.test.ts` example, "the tests/ folder" —
# are directories or non-shell files and do not match.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

TEST_PATH_PATTERN='tests/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*/[A-Za-z0-9_.-]+\.sh'

_hits() {
  grep -rnoE "$TEST_PATH_PATTERN" "$@" 2>/dev/null
}

checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  checked=$((checked + 1))
  f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"; m="${rest#*:}"
  report_fail "$f:$l — cites this repo's test script \"$m\", which does not exist in a consumer repo — drop the path and keep the runtime fact (skill-authoring.md §2)"
done < <(_hits skills agents)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no skills/ or agents/ file cites a tests/<dir>/<file>.sh path ($checked hit(s) found)"
fi

# --- self-test: red on each seeded citation, green on user-project test paths ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/probe" "$SELFTEST_DIR/agents"

cat > "$SELFTEST_DIR/skills/probe/violation.md" <<'EOF'
No shipped caller invokes `record_access` today — only `tests/memory/query-learnings.sh` exercises it directly.
Pinned by `tests/hooks/session-start-restore.sh` (the restore suite).
The call site is tests/state/validate-frontmatter.sh.
EOF
cat > "$SELFTEST_DIR/agents/violation.md" <<'EOF'
Run tests/authoring/deep/nested/lint-skills.sh before committing.
EOF

cat > "$SELFTEST_DIR/skills/probe/clean.md" <<'EOF'
    path: tests/api/handler.test.ts   # relative to git rev-parse --show-toplevel
Run the project's own suite from its tests/ folder; do not add files under tests/ without asking.
A user project might keep tests/e2e/ and a helper named tests-runner.sh at the root.
EOF

v=$(_hits "$SELFTEST_DIR/skills/probe/violation.md" "$SELFTEST_DIR/agents/violation.md" | grep -c . || true)
if [ "$v" -eq 4 ]; then
  echo "OK: self-test — all 4 seeded test-script citations (backticked, bare, nested) are detected"
else
  report_fail "self-test — expected 4 seeded test-path hits, got $v"
fi

c=$(_hits "$SELFTEST_DIR/skills/probe/clean.md" | grep -c . || true)
if [ "$c" -eq 0 ]; then
  echo "OK: self-test — a user-project test path, the 'tests/' folder and 'tests-runner.sh' do not false-positive"
else
  report_fail "self-test — the clean fixture false-positived ($c hit(s))"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS test-script citation problem(s)." >&2
  exit 1
fi
echo "OK: no skills/ or agents/ file cites this repo's test scripts."
