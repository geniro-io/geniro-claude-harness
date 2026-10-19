#!/usr/bin/env bash
# C9 (plugin-audit 2026-09-23, fix-plan §O / T1-14; widened 2026-10-19, T3-6) —
# no skills/, agents/, or .claude/skills/ file passes `disallowedTools` as a
# spawn argument: neither the call-syntax `disallowedTools=[...]` nor the
# declaration form `disallowedTools: [...]`.
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
# shape. T3-6: the call-syntax token was the only shape matched, so a spawn
# instruction written as "`disallowedTools: [Edit, Write, NotebookEdit]`
# declared and restated in the prompt body" (debug's verifier spawn) told the
# run to declare an argument the tool rejects, and the spawn failed into
# `Validation: unverified`.
#
# Detection: the word `disallowedTools` immediately followed by `=` or `:`
# and then a VALUE (an opening bracket, a quote, or a tool name). A NEGATION —
# "the Agent tool has no `disallowedTools` parameter", "takes no `tools=` or
# `disallowedTools=` argument", "has no `tools` / `disallowedTools` field" —
# never has a value after the symbol (the closing backtick, a slash or a
# space-then-word follows instead), so it stays silent. That distinction is
# what keeps this hard.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# `disallowedTools`, optional spaces, `=` or `:`, optional spaces, then `[`, a
# quote, or a letter: a value. A backtick, `/`, `,`, `)` or end of line after
# the symbol is a mention of the name, not a use.
_hits() {
  grep -rnoE "disallowedTools[[:space:]]*[:=][[:space:]]*(\\[|[\"'A-Za-z])" "$@" 2>/dev/null
}

checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  checked=$((checked + 1))
  f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"
  report_fail "$f:$l — disallowedTools passed as a spawn argument — the Agent tool schema has no such parameter; drop it and restate READ-ONLY in the prompt body (context-isolation-checklist.md §Prohibited tools list)"
done < <(_hits skills agents .claude/skills)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no skills/, agents/ or .claude/skills/ file passes disallowedTools as a spawn argument ($checked hit(s) found)"
fi

# --- self-test: red on each seeded use, green on the negation mentions ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/probe"

cat > "$SELFTEST_DIR/skills/probe/violation.md" <<'EOF'
Agent(description="Investigate: git history", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""
Satisfy context-isolation-checklist.md: `disallowedTools: [Edit, Write, NotebookEdit]` declared and restated in the prompt body.
Pass disallowedTools: Edit, Write on the spawn.
EOF

cat > "$SELFTEST_DIR/skills/probe/clean.md" <<'EOF'
The Agent tool has no `disallowedTools` parameter — nothing at the spawn call withholds a tool.
The Agent tool itself takes no `tools=` or `disallowedTools=` argument, so a spawn cannot restrict a generic subagent.
Cursor's subagent frontmatter has no `tools` / `disallowedTools` / `allowed-tools` field.
The agent's good judgment is unaudited, and the Agent tool has no `disallowedTools` argument.
EOF

v=$(_hits "$SELFTEST_DIR/skills/probe/violation.md" | grep -c . || true)
if [ "$v" -eq 3 ]; then
  echo "OK: self-test — the call-syntax '=[', the declaration ': [' and the bare ': Edit' spawn-argument forms are all detected"
else
  report_fail "self-test — expected 3 seeded spawn-argument hits, got $v"
fi

c=$(_hits "$SELFTEST_DIR/skills/probe/clean.md" | grep -c . || true)
if [ "$c" -eq 0 ]; then
  echo "OK: self-test — four negation mentions ('has no disallowedTools parameter', 'takes no disallowedTools= argument', ...) do not false-positive"
else
  report_fail "self-test — the negation fixture false-positived ($c hit(s))"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS disallowedTools spawn-argument problem(s)." >&2
  exit 1
fi
echo "OK: no skills/, agents/ or .claude/skills/ file passes the non-existent disallowedTools Agent() argument."
