#!/usr/bin/env bash
# `/geniro:setup` scaffolds `.geniro/instructions/*.md` files carrying
# `## Additional Steps` subsections anchored to a phase boundary. The loader
# only runs a subsection whose anchor some skill actually reads; an anchor with
# no read site is parsed, looks legal, and never fires — and the user cannot
# discover that, because every visible step still succeeds.
#
# A scaffold is the worst place for such an anchor: it is pre-written into the
# user's tree, so the step they add under it is dead on arrival. This check
# asserts every `### After <anchor>` shipped in a scaffold appears in the
# legal-anchor table that `/geniro:instructions validate` adjudicates against.
#
# The table is the single source; this check reads it rather than restating the
# anchor list, so adding a read site to a skill updates both at once.

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

SCAFFOLD_DIR="skills/setup/instruction-templates"
ANCHOR_TABLE="skills/instructions/instructions-authoring-reference.md"

fails=0
report_fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

[ -d "$SCAFFOLD_DIR" ] || { echo "FAIL: $SCAFFOLD_DIR missing — wrong working directory?" >&2; exit 1; }
[ -f "$ANCHOR_TABLE" ] || { echo "FAIL: $ANCHOR_TABLE missing" >&2; exit 1; }

# Legal anchors: every `After <phase>` appearing in a backtick span inside the
# §5 table. Read from the doc so the two cannot drift.
legal=$(
  awk '
    /^## 5\./            { in_sec = 1; next }
    in_sec && /^## /     { exit }
    in_sec               { print }
  ' "$ANCHOR_TABLE" \
  | grep -oE '`After [a-z-]+`' \
  | tr -d '`' \
  | sort -u
)

if [ -z "$legal" ]; then
  echo "FAIL: parsed zero legal anchors from $ANCHOR_TABLE §5 — the table's shape changed and this check went blind" >&2
  exit 1
fi

echo "Legal anchors (from $ANCHOR_TABLE §5):"
printf '%s\n' "$legal" | sed 's/^/  /'
echo

checked=0
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  file="${hit%%:*}"
  rest="${hit#*:}"
  lineno="${rest%%:*}"
  heading="${rest#*:}"
  # `### After ship` -> `After ship`; normalize case as the loader does.
  anchor=$(printf '%s' "$heading" | sed -E 's/^###[[:space:]]+//' | tr '[:upper:]' '[:lower:]')
  anchor="After ${anchor#after }"
  checked=$((checked + 1))
  if printf '%s\n' "$legal" | grep -qxF "$anchor"; then
    echo "PASS: ${file}:${lineno} — \`$anchor\` has a read site"
  else
    report_fail "${file}:${lineno} scaffolds \`$anchor\`, which no skill reads — a step written there never runs. Legal anchors are listed in $ANCHOR_TABLE §5"
  fi
done < <(grep -rn '^### After ' "$SCAFFOLD_DIR" 2>/dev/null || true)

# Self-test: a fixture scaffold carrying a dropped anchor must be rejected.
# `After implement` is the exact anchor this check was built after — it shipped
# in a scaffold with no read site until the audit found it.
if printf '%s\n' "$legal" | grep -qxF "After implement"; then
  report_fail "self-test: 'After implement' parsed as LEGAL — it has no read site, so the table parse is wrong"
else
  echo "PASS: self-test — a dropped anchor ('After implement') is not accepted as legal"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "OK: all $checked scaffolded Additional-Steps anchor(s) resolve to a real read site."
  exit 0
fi
echo "Failures: $fails" >&2
exit 1
