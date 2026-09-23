#!/usr/bin/env bash
# C1 (plugin-audit 2026-09-23, fix-plan §O / T2-1) — no `skills/*/SKILL.md`
# frontmatter `description:` carries an angle-bracket placeholder.
#
# Run: bash tests/authoring/lint-description-xml.sh
#
# Why this exists: skill-structure.md §Frontmatter hygiene rule 5 is "No XML
# tags anywhere in the description" — but the description is also the ONE
# field Claude Code parses to decide whether to trigger a skill, so a stray
# `<branch>` placeholder (copied from a file-path example elsewhere in the
# body, e.g. `.geniro/state/handoff/from-debug-<branch>.md`) reads as an
# opening tag to anything that treats the field as markup, not as the
# angle-bracket placeholder a body sentence can use safely. T2-1: `skills/
# debug/SKILL.md` and `skills/plan/SKILL.md` both carry one.
#
# Detection: `<` immediately followed by a Latin letter, anywhere inside the
# quoted description string. This is the same shape XML/HTML opening tags
# take and the same shape a `<placeholder>` takes — the rule bans both
# identically, so there is no separate "legitimate placeholder" carve-out to
# construct. `<` before a non-letter (a stray `<` used as a comparison, e.g.
# "latency < 200ms") does NOT match and stays silent.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# <dir-glob> -> file:line:offending-snippet for every description: line whose
# quoted value contains `<` immediately followed by a Latin letter.
_check_descriptions() {
  local f line
  for f in "$@"; do
    [ -f "$f" ] || continue
    line=$(grep -n '^description:' "$f" | head -1)
    [ -n "$line" ] || continue
    if printf '%s\n' "$line" | grep -qE '<[A-Za-z]'; then
      printf '%s\n' "$line" | sed "s#^#$f:#"
    fi
  done
}

checked=0
while IFS= read -r f; do [ -n "$f" ] && checked=$((checked + 1)); done < <(printf '%s\n' skills/*/SKILL.md)

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  fl="${hit%%:*}:$(printf '%s' "${hit#*:}" | cut -d: -f1)"
  snippet=$(printf '%s' "${hit#*:}" | cut -d: -f2- | sed 's/^[[:space:]]*//')
  report_fail "$fl — description: contains an angle-bracket placeholder (reads as an XML/HTML tag): $snippet"
done < <(_check_descriptions skills/*/SKILL.md)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no skills/*/SKILL.md description: contains a '<letter' angle-bracket placeholder ($checked file(s) checked)"
fi

# --- self-test: red on a seeded '<branch>'-style description, green on a clean one ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/violation" "$SELFTEST_DIR/clean"

cat > "$SELFTEST_DIR/violation/SKILL.md" <<'EOF'
---
name: probe
description: "Use when probing. Writes a handoff to .geniro/state/handoff/from-debug-<branch>.md."
context: main
---

# Probe
EOF

cat > "$SELFTEST_DIR/clean/SKILL.md" <<'EOF'
---
name: probe
description: "Use when probing. Writes a handoff to .geniro/state/handoff/from-debug-{branch}.md. Latency < 200ms."
context: main
---

# Probe
EOF

v=$(_check_descriptions "$SELFTEST_DIR/violation/SKILL.md" | grep -c .)
if [ "$v" -ge 1 ]; then
  echo "OK: self-test — a seeded '<branch>' placeholder in description: is detected"
else
  report_fail "self-test — seeded '<branch>' violation was NOT detected"
fi

c=$(_check_descriptions "$SELFTEST_DIR/clean/SKILL.md" | grep -c .)
if [ "$c" -eq 0 ]; then
  echo "OK: self-test — a '{branch}' placeholder and a '< 200ms' comparison do not false-positive"
else
  report_fail "self-test — the clean fixture ('{branch}' + '< 200ms') false-positived"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS description: angle-bracket problem(s)." >&2
  exit 1
fi
echo "OK: every SKILL.md description: is free of angle-bracket placeholders."
