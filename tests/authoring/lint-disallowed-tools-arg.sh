#!/usr/bin/env bash
# C9 (plugin-audit 2026-09-23, fix-plan §O / T1-14) — no skills/ or agents/
# file passes `disallowedTools=[...]` to `Agent(...)`.
#
# Run: bash tests/authoring/lint-disallowed-tools-arg.sh
#
# Why this exists: the Agent tool schema has no `disallowedTools` parameter —
# skill-structure.md §"Let the tool surface state the boundary" and
# context-isolation-checklist.md §"Prohibited tools list" both say so
# explicitly ("the Agent tool has no disallowedTools parameter"). A spawn
# template that still writes `Agent(..., disallowedTools=["Edit", "Write"],
# ...)` fails input validation the moment a run copies it verbatim. T1-14: a
# T0-8 sweep already removed this argument from most spawn templates but
# missed five sites in investigate/investigate-taxonomy-reference.md and
# investigate/phase-2-investigate.md, all describing the SAME broken call
# shape.
#
# Detection: the exact call-syntax token `disallowedTools=[` — the fix-plan's
# own literal check text. This is unambiguous: nothing else in the corpus
# writes this token, and the corpus's correct usage always states the
# constraint as PROSE ("disallowedTools=[Edit, Write, NotebookEdit] declared
# and restated in the prompt body") without the `=[` call-syntax shape
# immediately following the word.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

_hits() {
  grep -rnoF 'disallowedTools=[' "$@" 2>/dev/null
}

checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  checked=$((checked + 1))
  f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"
  report_fail "$f:$l — Agent(disallowedTools=[...]) — the Agent tool schema has no such parameter; drop the argument (the prompt already restates READ-ONLY)"
done < <(_hits skills agents)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no skills/ or agents/ file passes disallowedTools=[ to Agent() ($checked hit(s) found)"
fi

# --- self-test: red on a seeded call-syntax use, green on the prose-only mention ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/probe"

cat > "$SELFTEST_DIR/skills/probe/violation.md" <<'EOF'
Agent(description="Investigate: git history", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""
EOF

cat > "$SELFTEST_DIR/skills/probe/clean.md" <<'EOF'
Satisfy context-isolation-checklist.md: `disallowedTools: [Edit, Write, NotebookEdit]` declared and restated in the prompt body; the Agent tool itself takes no such argument.
EOF

v=$(_hits "$SELFTEST_DIR/skills/probe/violation.md" | grep -c .)
if [ "$v" -ge 1 ]; then
  echo "OK: self-test — a seeded 'disallowedTools=[' call-syntax use is detected"
else
  report_fail "self-test — seeded violation was NOT detected"
fi

c=$(_hits "$SELFTEST_DIR/skills/probe/clean.md" | grep -c .)
if [ "$c" -eq 0 ]; then
  echo "OK: self-test — a prose mention ('disallowedTools: [...] declared') without the '=[' call-syntax shape does not false-positive"
else
  report_fail "self-test — the prose-only fixture false-positived ($c hit(s))"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS disallowedTools=[ call-syntax problem(s)." >&2
  exit 1
fi
echo "OK: no skills/ or agents/ file writes the non-existent disallowedTools=[ Agent() argument."
