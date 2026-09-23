#!/usr/bin/env bash
# C6 (plugin-audit 2026-09-23, fix-plan §O / T2-6) — two decidable slices of
# "system-tool names used as instructions" (skill-authoring.md §6):
#   1. A capitalized system-tool name immediately followed by the literal
#      word "tool" ("using Edit tool", "the Write tool") — skills/, agents/,
#      AND .claude/skills/ (the plan's "for the first" scope note).
#   2. A hardcoded tracker MCP tool name (`mcp__linear__...`, `mcp__jira__...`)
#      — skills/ and agents/ only.
#
# Run: bash tests/authoring/lint-tool-name-instruction.sh
#
# Why this exists: skill-authoring.md §6 says instruct by capability, not by
# tool name — a host that registers the capability under another name (or
# never named it Grep/Glob/Edit/Write/Read at all) still follows "read the
# file", where "use the Read tool" reads as a missing step. T2-6 also flags
# the plan skill hardcoding one tracker's MCP tool name (`mcp__linear__
# get_issue`) instead of reading the tracker `kind` generically from
# `.geniro/workflow/<kind>.md`, per task-chain-context.md §3.
#
# Scope decisions (stated per the task's instruction to decide and say so):
#
# - Slice 1 is narrowed from the fix-plan's literal `(Use|using) the (Glob|
#   Grep|Read|Edit|Write) tool` to the bare bigram `(Glob|Grep|Read|Edit|
#   Write) tool` (verb optional, "the" optional). The corpus's live
#   violations at the time this check was written read "using Edit tool" (no
#   "the") and "Glob the directory" / "Grep for ..." (no "tool" at all,
#   tool-name-as-verb) — none of which the plan's literal verb-list regex
#   matches. The "X tool" bigram is the maximal SAFE generalization: Read /
#   Write / Edit are common English verbs, so nothing shorter than "<name>
#   tool" stays zero-false-positive (a bare "Grep the directory" cannot be
#   told apart from ordinary capitalized prose without semantic judgment —
#   that residue is a D4 prose-reviewer call, not a mechanizable one).
#
# - Slice 2 is narrowed from `mcp__(linear|github|jira)__` to `mcp__(linear|
#   jira)__`. Every `mcp__github__*` hit in this corpus (setup/SKILL.md,
#   instructions/SKILL.md, actions/SKILL.md, update/SKILL.md's ACI tables;
#   review's phase-1-pr-reference.md, phase-5-6-emit-handoff.md,
#   pr-threads.md; debug/adversarial-mode.md) is a legitimate hardcode of
#   GitHub's own PR/review API, which — unlike a tracker — /geniro:review
#   operates on directly with no vendor-swap abstraction offered anywhere in
#   the design. Including `github` would hard-fail every one of those
#   correct, load-bearing sites.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

_tool_bigram_hits() {
  grep -rnoE '(Glob|Grep|Read|Edit|Write) tool' "$@" 2>/dev/null
}
_tracker_mcp_hits() {
  grep -rnoE 'mcp__(linear|jira)__[A-Za-z_]+' "$@" 2>/dev/null
}

checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  checked=$((checked + 1))
  f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"; m="${rest#*:}"
  report_fail "$f:$l — tool name used as an instruction: \"$m\" — instruct by capability instead (skill-authoring.md §6)"
done < <(_tool_bigram_hits skills agents .claude/skills)

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  checked=$((checked + 1))
  f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"; m="${rest#*:}"
  report_fail "$f:$l — hardcoded tracker MCP tool: \"$m\" — read the tracker kind from .geniro/workflow/<kind>.md instead (task-chain-context.md §3)"
done < <(_tracker_mcp_hits skills agents)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no tool-name-as-instruction bigram or hardcoded tracker MCP tool found ($checked hit(s))"
fi

# --- self-test: red on each seeded shape, green on legitimate mcp__github__ use ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/probe" "$SELFTEST_DIR/.claude/skills/probe"

cat > "$SELFTEST_DIR/skills/probe/violation.md" <<'EOF'
Apply directly using Edit tool. No subagent needed.
Fetch via the matching MCP (`mcp__linear__get_issue` for Linear, etc.).
EOF

cat > "$SELFTEST_DIR/.claude/skills/probe/phase.md" <<'EOF'
- **Trivial** (1-2 lines, obvious target): Apply directly using Edit tool.
EOF

cat > "$SELFTEST_DIR/skills/probe/clean.md" <<'EOF'
Read-only `mcp__github__pull_request_read` with the resolved owner/repo/number.
Write the report to state.md. Read the spec before editing.
EOF

v1=$(_tool_bigram_hits "$SELFTEST_DIR/skills" "$SELFTEST_DIR/.claude/skills" | grep -c .)
v2=$(_tracker_mcp_hits "$SELFTEST_DIR/skills" | grep -c .)
if [ "$v1" -ge 2 ] && [ "$v2" -ge 1 ]; then
  echo "OK: self-test — the seeded 'Edit tool' bigrams (skills/ + .claude/skills/) and the seeded mcp__linear__ hardcode are all detected"
else
  report_fail "self-test — expected >=2 tool-bigram hits and >=1 tracker-mcp hit, got $v1 / $v2"
fi

c1=$(_tool_bigram_hits "$SELFTEST_DIR/skills/probe/clean.md" | grep -c .)
c2=$(_tracker_mcp_hits "$SELFTEST_DIR/skills/probe/clean.md" | grep -c .)
if [ "$c1" -eq 0 ] && [ "$c2" -eq 0 ]; then
  echo "OK: self-test — plain 'Write the report' / 'Read the spec' prose and the legitimate mcp__github__ PR-review call do not false-positive"
else
  report_fail "self-test — the clean fixture false-positived (bigram=$c1, tracker=$c2)"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS tool-name-as-instruction / hardcoded-tracker problem(s)." >&2
  exit 1
fi
echo "OK: no tool-name-as-instruction bigram or hardcoded non-GitHub tracker MCP tool in skills/ or agents/."
