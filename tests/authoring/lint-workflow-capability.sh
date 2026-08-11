#!/usr/bin/env bash
# Authoring lint — a skill that reads a capability out of a project's workflow file
# (.geniro/workflow/<kind>.md) must cite a section the shipped template actually declares.
#
# Run: bash tests/authoring/lint-workflow-capability.sh
#
# The failure this catches: a consumer citing `## Searching for issues` while no
# workflow template declares it. The probe then cannot fire in ANY project, and
# because an unreachable source is reported rather than silently dropped
# (skills/_shared/data-sources.md §5/§6), it reports a permanent false "couldn't
# reach the tracker" instead of the true "no such capability is configured".
# A documented slot with no producer is the class of defect this file exists for.
#
# Two hard checks per cited section:
#   1. The shipped template declares it, so the capability exists for that tracker.
#   2. skills/setup/phase-3-generate.md names it, so a non-Linear project's stub
#      carries the heading as an explicit blank. That blank is what lets a consumer
#      distinguish "no capability declared" (normal absence) from "source unreachable".
#
# Portability: bash 3.2 / BSD grep — no -P, no GNU-only flags.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATE_DIR="skills/setup/workflow-templates"
STUB_DECL="skills/setup/phase-3-generate.md"
FAILS=0

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "FAIL: $TEMPLATE_DIR is missing — workflow templates are the producer half of this contract" >&2
  exit 1
fi

# Consumers: any skills/ file that names a workflow-file path AND, on the same line,
# cites a heading in the `## Heading` section form — the phrasing that claims the
# workflow file declares that section. The trailing "section" keyword is what keeps a
# report heading mentioned nearby (a `## Caveats` one-liner, say) out of the result;
# a loose match there would fail on prose that never claimed a workflow capability at
# all, and a lint that cries wolf gets switched off. Templates and the stub declaration
# are the producer half, so they are excluded from the consumer scan.
CITED="$(
  grep -rn '\.geniro/workflow/' --include='*.md' skills/ 2>/dev/null \
    | grep -v "^$TEMPLATE_DIR/" \
    | grep -v "^$STUB_DECL:" \
    | grep -oE '`## [^`]+` section' \
    | sed -e 's/^`//' -e 's/` section$//' \
    | sort -u
)"

if [ -z "$CITED" ]; then
  echo "OK: no workflow-file capability sections are cited by any skill"
  exit 0
fi

while IFS= read -r heading; do
  [ -n "$heading" ] || continue

  # 1. At least one shipped template declares the section as a real heading.
  if grep -rqF "$heading" "$TEMPLATE_DIR" 2>/dev/null; then
    :
  else
    echo "FAIL: a skill cites '$heading' in a workflow file, but no template under $TEMPLATE_DIR declares it — the capability has no producer" >&2
    FAILS=$((FAILS + 1))
  fi

  # 2. The stub declaration names it, so non-Linear projects get the heading as a blank.
  if grep -qF "$heading" "$STUB_DECL" 2>/dev/null; then
    :
  else
    echo "FAIL: '$heading' is cited by a skill and declared by a template, but $STUB_DECL does not require it in the non-Linear stub — a non-Linear project would read the missing section as an unreachable source instead of an undeclared capability" >&2
    FAILS=$((FAILS + 1))
  fi
done <<EOF
$CITED
EOF

if [ "$FAILS" -gt 0 ]; then
  echo "" >&2
  echo "Workflow-capability checks failed: $FAILS" >&2
  exit 1
fi

echo "OK: every workflow-file capability a skill cites is declared by a template and required in the stub"
exit 0
