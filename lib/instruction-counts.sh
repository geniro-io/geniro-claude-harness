#!/usr/bin/env bash
# Counts top-level ## Rules / ## Constraints / ## Data Sources bullets in a
# custom-instruction file.
#
# Spec: skills/_shared/load-custom-instructions.md §Echo contract — the load
# echo quotes this helper's output instead of a model-counted tally, so a
# miscounted echo now traces to one script instead of a per-invocation guess.
# Producer schema: skills/instructions/instructions-authoring-reference.md §1.
#
# API: count_instruction_sections <path>
#   Prints "<rules> <constraints> <data-sources>" to stdout, rc 0, when the
#   path resolves to a readable file — including a file with none of the
#   three headings (not every instruction file declares Data Sources, and a
#   fresh project may have no instructions at all: a real, present-but-empty
#   result, reported as 0 rather than an error).
#   No path at all is the same "nothing to load" case, also "0 0 0" rc 0 — a
#   caller with no override configured passes no argument by design.
#   A non-empty path that is missing, unreadable, or not a regular file
#   prints nothing and returns $_GIC_UNREADABLE: that caller has a real path
#   it could not open, which the echo consuming this output must not report
#   as a legitimate zero count (skills/_shared/load-custom-instructions.md
#   §Procedure step 2).
# Or run it directly (same output, same exit code):
#   bash "${CLAUDE_PLUGIN_ROOT}/lib/instruction-counts.sh" <path>
#
# Counts only bullets (`- ` / `* `) at column 0 directly under a top-level
# (`## `) Rules / Constraints / Data Sources heading. An indented sub-bullet
# and anything inside a fenced ``` code block are excluded — both are common
# in a hand-edited instructions file (an explanatory sub-point, a pasted
# example) and neither is a rule/constraint/source entry itself.

# Guarded so a second `source` in the same shell doesn't trip `readonly
# variable` — every peer helper in lib/ carries this guard.
if [ -z "${_GIC_DEPS_LOADED:-}" ]; then
  # Matches lib/validate-action-file.sh / lib/validate-plan-spec.sh, which use
  # the same code for the same condition (a given target that isn't a
  # readable file) — one convention for "could not open this path" across
  # lib/, not a code invented for this helper alone.
  readonly _GIC_UNREADABLE=65
  _GIC_DEPS_LOADED=1
fi

count_instruction_sections() {
  local file="${1:-}"

  if [ -z "$file" ]; then
    echo "0 0 0"
    return 0
  fi

  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    echo "count_instruction_sections: $file — not a readable file" >&2
    return "$_GIC_UNREADABLE"
  fi

  awk '
    BEGIN { section = ""; fence = 0; rules = 0; constraints = 0; sources = 0 }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^```/) { fence = !fence; next }
      if (fence) { next }
      if (line ~ /^## /) {
        heading = line
        sub(/^## /, "", heading)
        gsub(/[ \t]+$/, "", heading)
        low = tolower(heading)
        if (low == "rules") { section = "rules" }
        else if (low == "constraints") { section = "constraints" }
        else if (low == "data sources") { section = "sources" }
        else { section = "" }
        next
      }
      if (line ~ /^[-*] /) {
        if (section == "rules") { rules++ }
        else if (section == "constraints") { constraints++ }
        else if (section == "sources") { sources++ }
      }
    }
    END { printf "%d %d %d\n", rules, constraints, sources }
  ' "$file"
}

# Direct execution: `bash lib/instruction-counts.sh <path>`. Sourcing this
# file defines the function and runs nothing, so the two entry points share
# one implementation — the BASH_SOURCE-vs-$0 test, not a basename match,
# matching lib/validate-action-file.sh.
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
  count_instruction_sections "${1:-}"
  exit $?
fi
