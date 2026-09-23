#!/usr/bin/env bash
# Custom-instructions file validator — the decidable rows of the /geniro:instructions
# `validate` lint, mechanized.
#
# Spec: skills/instructions/mode-validate.md §Step 2 — this script covers the
# structural checks a command can decide (heading present, length threshold,
# dropped-skill slug references, Additional-Steps anchor legality). The
# description-quality rows (skills/_shared/description-quality.md) and every
# other judgment-shaped row in §Step 2 (Data Sources / Verification Surface /
# Memory Backend content, per-scope frontmatter field checks, `requires-context`
# detection) stay hand-run prose there — this script does not decide those.
#
# Every row this script DOES cover is a condition a command can decide, so it
# is decided here rather than hand-run by the orchestrator: a hand-run table is
# re-read and re-interpreted on every create and every validate, and the
# interpretation is what drifts (the same reasoning lib/validate-action-file.sh
# documents for the actions equivalent). mode-validate.md calls this and
# renders the rows.
#
# API — source it, then call:
#   source "${CLAUDE_PLUGIN_ROOT}/lib/validate-instructions-file.sh"
#   validate_instructions_file <path> [scope] [max_lines]
# Or run it directly (same output, same exit codes):
#   bash "${CLAUDE_PLUGIN_ROOT}/lib/validate-instructions-file.sh" <path> [scope] [max_lines]
#
# <scope> — one of global | code-style | memory | review-extra | implement |
#   plan | review | resolve | debug | refactor | onboard | investigate |
#   reflect. Omit (or pass "") to auto-detect from the path: the parent
#   directory basename "review-extra" wins, else the filename minus ".md".
#
# <max_lines> — overrides the length threshold. Omit (or pass "") to fall back
# to $GENIRO_INSTRUCTIONS_MAX_LINES, then the default below. 0 disables the
# length check entirely (mirrors mode-validate.md §Step 1 `--max-lines 0`).
#
# Output: one TAB-separated row per FAILED check, on stdout:
#   <SEVERITY><TAB><check-id><TAB><line-or-dash><TAB><message>
# A clean file prints nothing. The rows are the report and the exit code is the
# verdict, so a caller gates on the code without parsing the rows.
#
# Exit codes:
#   0  — no failed checks
#   1  — failed checks, none of them CRITICAL or HIGH (MEDIUM/LOW only: warn)
#   2  — at least one CRITICAL or HIGH failed check (blocking)
#   64 — usage error: no target path passed (EX_USAGE)
#   65 — target path is not a readable file
# 64/65 are distinct from 2 on purpose: "the validator could not run" must not
# read as "the file is bad", and neither may read as "the file is fine".

# Guarded so a second `source` in the same shell doesn't trip `readonly
# variable` errors — under a caller's `set -e` an unguarded re-source aborts the
# whole Bash block before validation runs. Every peer helper carries this guard.
if [ -z "${_VIF_DEPS_LOADED:-}" ]; then
  readonly _VIF_OK=0
  readonly _VIF_WARN=1
  readonly _VIF_BLOCKING=2
  readonly _VIF_NO_TARGET=64
  readonly _VIF_UNREADABLE=65

  # Default length threshold. Single home for the number is the `--max-lines`
  # flag line in skills/instructions/mode-validate.md §Step 1 — this constant
  # is the enforcement copy, kept in lockstep by hand (same pattern
  # lib/validate-action-file.sh uses for its own constants).
  readonly _VIF_DEFAULT_MAX_LINES=300

  # Scopes whose file shape carries no `## Rules` / `## Constraints` — memory.md
  # is the Memory Backend block only, review-extra/<slug>.md uses `# Criteria`.
  readonly _VIF_NO_RULES_CONSTRAINTS_SCOPES="memory review-extra"

  # The legal (scope, phase) anchor pairs an `### After <phase>` subsection may
  # name. Single home for the table is
  # skills/instructions/instructions-authoring-reference.md §5 — this is the
  # enforcement copy; a change there needs the matching change here (a
  # `tests/instructions/validate-instructions-file.sh` case pins the pairing).
  readonly _VIF_LEGAL_ANCHORS="implement:analyze implement:ship plan:explore plan:user-approve refactor:verify global:worktree-setup"

  # Dropped-skill slugs an instruction body must not still reference — single
  # home skills/_shared/dropped-skills.md §The list.
  readonly _VIF_DROPPED_SKILLS_RE='(^|[^/A-Za-z0-9_.-])/(brainstorm|decompose|follow-up|deep-simplify|features|learnings|cleanup|vendor)([^/A-Za-z0-9_.-]|$)'

  _VIF_DEPS_LOADED=1
fi

# Emit one finding row. Callers pass severity, check id, line (or `-`), message.
_vif_row() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
}

# Scope auto-detect: the parent directory basename "review-extra" wins over the
# filename, else the filename minus ".md", lowercased.
_vif_detect_scope() {
  local path="$1" base parent
  base="$(basename "$path")"
  base="${base%.md}"
  parent="$(basename "$(dirname "$path")")"
  if [ "$parent" = "review-extra" ]; then
    printf '%s\n' "review-extra"
  else
    printf '%s\n' "$base" | tr '[:upper:]' '[:lower:]'
  fi
}

validate_instructions_file() {
  local target="${1:-}"   # default so a zero-arg call under `set -u` reaches the guard
  local scope="${2:-}"
  local max_lines="${3:-}"
  if [ -z "$target" ]; then
    echo "validate_instructions_file: target path required" >&2
    return "$_VIF_NO_TARGET"
  fi
  if [ ! -f "$target" ] || [ ! -r "$target" ]; then
    echo "validate_instructions_file: $target — not a readable file" >&2
    return "$_VIF_UNREADABLE"
  fi

  if [ -z "$scope" ]; then
    scope="$(_vif_detect_scope "$target")"
  fi
  if [ -z "$max_lines" ]; then
    max_lines="${GENIRO_INSTRUCTIONS_MAX_LINES:-$_VIF_DEFAULT_MAX_LINES}"
  fi

  # Verdict accumulators: every emitted row raises exactly one of these, so the
  # exit code stays derivable without re-reading the rows.
  local blocking=0 warning=0

  local skip_rc=1
  case " $_VIF_NO_RULES_CONSTRAINTS_SCOPES " in
    *" $scope "*) skip_rc=0 ;;
  esac

  # --- Check: `## Rules` heading present -------------------------------------
  if [ "$skip_rc" -ne 0 ]; then
    if ! grep -qE '^##[[:space:]]+Rules[[:space:]]*$' "$target"; then
      _vif_row HIGH rules-heading-present - "no '## Rules' heading — the scope requires one (skip only for memory.md / review-extra/<slug>.md)"
      blocking=1
    fi

    # --- Check: `## Constraints` heading present -----------------------------
    if ! grep -qE '^##[[:space:]]+Constraints[[:space:]]*$' "$target"; then
      _vif_row HIGH constraints-heading-present - "no '## Constraints' heading — the scope requires one (skip only for memory.md / review-extra/<slug>.md)"
      blocking=1
    fi
  fi

  # --- Check: file length -----------------------------------------------------
  if [ "$max_lines" -gt 0 ] 2>/dev/null; then
    local lines
    lines="$(awk 'END { print NR }' "$target")"
    if [ "$lines" -gt "$max_lines" ]; then
      _vif_row LOW file-length - "file is $lines lines, over the $max_lines threshold — longer instruction files consume more context and reduce rule adherence; consider splitting into topic-specific files or trimming redundant rules"
      warning=1
    fi
  fi

  # --- Check: dropped-skill slug references -----------------------------------
  local dropped_hit
  dropped_hit="$(grep -nE "$_VIF_DROPPED_SKILLS_RE" "$target" | head -n 1 || true)"
  if [ -n "$dropped_hit" ]; then
    _vif_row HIGH dropped-skill-reference "${dropped_hit%%:*}" "references a dropped skill — see \${CLAUDE_PLUGIN_ROOT}/skills/_shared/dropped-skills.md §The list"
    blocking=1
  fi

  # --- Check: Additional-Steps anchor legality --------------------------------
  # Scan for every `###` subsection nested under `## Additional Steps`, and
  # classify each: free-form (not an After/Before heading at all — LOW), a
  # `### Before <phase>` form (no skill reads that prefix — always MEDIUM), or
  # `### After <phase>` naming a (scope, phase) pair outside the legal set
  # (real-phase-no-read-site or dropped — MEDIUM). Report the first hit of
  # each category, matching the first-occurrence convention every other
  # multi-match check here uses.
  local freeform_line="" illegal_line="" illegal_msg=""
  while IFS=$'\t' read -r lineno heading; do
    [ -n "$lineno" ] || continue
    local lower
    lower="$(printf '%s' "$heading" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
      before\ *)
        if [ -z "$illegal_line" ]; then
          illegal_line="$lineno"
          illegal_msg="'### Before ${heading#* }' — no skill reads the Before form; use the scope's legal After anchor instead"
        fi
        ;;
      after\ *)
        local phase
        phase="${lower#after }"
        phase="${phase%%\(*}"                    # drop a trailing parenthetical
        phase="$(printf '%s' "$phase" | sed -E 's/[[:space:]]+$//; s/^[[:space:]]+//')"
        case " $_VIF_LEGAL_ANCHORS " in
          *" $scope:$phase "*) ;;
          *)
            if [ -z "$illegal_line" ]; then
              illegal_line="$lineno"
              illegal_msg="'### After $phase' is not a legal anchor for scope '$scope' — see \${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md §5 for the per-skill anchor table"
            fi
            ;;
        esac
        ;;
      *)
        if [ -z "$freeform_line" ]; then
          freeform_line="$lineno"
        fi
        ;;
    esac
  done < <(awk '
    /^##[[:space:]]+Additional Steps[[:space:]]*$/ { in_as = 1; next }
    in_as && /^##[[:space:]]/ { in_as = 0 }
    in_as && /^###[[:space:]]+/ {
      line = $0
      sub(/^###[[:space:]]+/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      print NR "\t" line
    }
  ' "$target")

  if [ -n "$freeform_line" ]; then
    _vif_row LOW anchor-freeform "$freeform_line" "'## Additional Steps' subsection heading is not an '### After <phase>' / '### Before <phase>' form — free-form subsections never fire"
    warning=1
  fi
  if [ -n "$illegal_line" ]; then
    _vif_row MEDIUM anchor-illegal "$illegal_line" "$illegal_msg"
    warning=1
  fi

  if [ "$blocking" -eq 1 ]; then
    return "$_VIF_BLOCKING"
  fi
  if [ "$warning" -eq 1 ]; then
    return "$_VIF_WARN"
  fi
  return "$_VIF_OK"
}

# Direct execution: `bash lib/validate-instructions-file.sh <path> [scope] [max_lines]`.
# Sourcing this file defines the function and runs nothing, so the two entry
# points share one implementation. The test is BASH_SOURCE-vs-$0, not a
# basename match: a same-named caller (the suite for this helper is
# `tests/instructions/<same name>.sh`) would otherwise trip a basename check on
# every source.
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
  validate_instructions_file "$@"
  exit $?
fi
