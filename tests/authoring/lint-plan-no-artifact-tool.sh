#!/usr/bin/env bash
# C17 (plugin-audit 2026-09-23, fix-plan §O / T4-49) — skills/plan/SKILL.md's
# `allowed-tools:` frontmatter excludes `Artifact`.
#
# Run: bash tests/authoring/lint-plan-no-artifact-tool.sh
#
# Why this exists: skills/_shared/plan-artifact.md documents that `Artifact`
# is "deliberately absent from allowed-tools so the first publish raises the
# one-time claude.ai consent prompt" — an intentional invariant, not an
# oversight. A future edit that adds `Artifact` to plan's allowlist (e.g. a
# well-meaning "let's pre-approve every tool this skill uses" pass) would
# silently skip that one-time consent gate. This check holds the invariant
# plan-artifact.md's prose depends on, mechanically.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

PLAN_SKILL="skills/plan/SKILL.md"

_allowed_tools_line() {
  grep -m1 '^allowed-tools:' "$1" 2>/dev/null
}

check_no_artifact() {  # <skill-md> -> 0 if clean, 1 if Artifact is present
  local f="$1" line
  line="$(_allowed_tools_line "$f")"
  [ -n "$line" ] || return 0
  printf '%s\n' "$line" | grep -qE '(^|[^A-Za-z0-9_])Artifact([^A-Za-z0-9_]|$)'
}

if [ -f "$PLAN_SKILL" ]; then
  if check_no_artifact "$PLAN_SKILL"; then
    report_fail "$PLAN_SKILL allowed-tools includes Artifact — this skips the one-time claude.ai consent prompt plan-artifact.md's design depends on: $(_allowed_tools_line "$PLAN_SKILL")"
  else
    echo "OK: $PLAN_SKILL allowed-tools excludes Artifact"
  fi
else
  report_fail "$PLAN_SKILL not found — cannot verify its allowed-tools"
fi

# --- self-test: red on a seeded Artifact grant, green on the real absence ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/probe"

cat > "$SELFTEST_DIR/skills/probe/violation.md" <<'EOF'
---
name: probe
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, Artifact]
---
EOF

cat > "$SELFTEST_DIR/skills/probe/clean.md" <<'EOF'
---
name: probe
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, ArtifactComments]
---
EOF

if check_no_artifact "$SELFTEST_DIR/skills/probe/violation.md"; then
  echo "OK: self-test — a seeded 'Artifact' entry in allowed-tools is detected"
else
  report_fail "self-test — seeded Artifact grant was NOT detected"
fi

if ! check_no_artifact "$SELFTEST_DIR/skills/probe/clean.md"; then
  echo "OK: self-test — 'ArtifactComments' (a DIFFERENT tool name) does not false-positive as 'Artifact'"
else
  report_fail "self-test — the ArtifactComments fixture false-positived as a bare Artifact grant"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS plan allowed-tools / Artifact problem(s)." >&2
  exit 1
fi
echo "OK: skills/plan/SKILL.md's allowed-tools excludes Artifact."
