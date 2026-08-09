#!/usr/bin/env bash
# Custom-action file validator — the 13 create/validate gate checks, mechanized.
#
# Spec + escalation semantics: skills/actions/actions-reference.md §Validation gate
# File shape being validated: skills/actions/skill-template.md
#
# Every row of that gate is a condition a command can decide, so it is decided
# here rather than hand-run by the orchestrator: a hand-run table is re-read and
# re-interpreted on every create and every validate, and the interpretation is
# what drifts. The skill calls this and renders the rows.
#
# API — source it, then call:
#   source "${CLAUDE_PLUGIN_ROOT}/lib/validate-action-file.sh"
#   validate_action_file .geniro/actions/<slug>.md
# Or run it directly (same output, same exit codes):
#   bash "${CLAUDE_PLUGIN_ROOT}/lib/validate-action-file.sh" .geniro/actions/<slug>.md
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
#
# YAML parsing strategy: shell-line only, matching lib/validate-state-file.sh.
# An action file's frontmatter is flat scalars plus one inline list, so a
# key-shape scan decides every check here; nested-structure parsing is never
# needed and would add a dependency the hooks' vendored installs may not have.

# Guarded so a second `source` in the same shell doesn't trip `readonly
# variable` errors — under a caller's `set -e` an unguarded re-source aborts the
# whole Bash block before validation runs. Every peer helper carries this guard.
if [ -z "${_VAF_DEPS_LOADED:-}" ]; then
  readonly _VAF_OK=0
  readonly _VAF_WARN=1
  readonly _VAF_BLOCKING=2
  readonly _VAF_NO_TARGET=64
  readonly _VAF_UNREADABLE=65

  # Description length cap. The description is also the free-text match
  # target for Target resolution (actions-reference.md §Target resolution) —
  # past this length it reads as a paragraph rather than a routing summary,
  # which dilutes match precision more than a longer description improves it.
  # This constant is the single home — see skills/actions/skill-template.md
  # §Authoring rules, which cites it by name rather than restating the number.
  readonly _VAF_DESC_MAX_CHARS=250

  # File-length guideline. An action body is followed step-by-step inline by the
  # orchestrator, so a long one competes with the task's own context; past this
  # the action is doing more than one job and wants splitting. MEDIUM, not
  # blocking — length alone never makes an action wrong.
  readonly _VAF_MAX_LINES=500

  # Slug length cap. The slug is the filename (`.geniro/actions/<slug>.md`)
  # and the token typed at `/geniro:actions run <slug>` — long past this and
  # it stops being something a user types or scans in a list. This constant,
  # and the reserved-word list below, are the single home for the slug-shape
  # rule — skills/actions/SKILL.md §Name validation cites this check by name
  # rather than restating either.
  readonly _VAF_SLUG_MAX_CHARS=64

  # Reserved words a slug may not equal: the three vendor names plus every
  # verb the Phase 1 alias table dispatches on (skills/actions/SKILL.md
  # §Sub-commands) — a slug equal to one of these collides with verb
  # detection in `$ARGUMENTS`.
  readonly _VAF_RESERVED_SLUGS="anthropic claude geniro list create edit run delete validate"

  _VAF_DEPS_LOADED=1
fi

# Emit one finding row. Callers pass severity, check id, line (or `-`), message.
_vaf_row() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
}

# Print the frontmatter body (everything between the line-1 `---` and the next
# `---`). Exit 2 when line 1 is not `---`, 3 when no closing fence exists.
_vaf_extract_frontmatter() {
  awk '
    NR == 1 && $0 != "---" { exit 2 }
    NR == 1 { in_fm = 1; next }
    in_fm && $0 == "---" { found_close = 1; exit 0 }
    in_fm { print }
    END { if (in_fm && !found_close) exit 3 }
  ' "$1"
}

# First frontmatter line number (1-based, relative to the frontmatter block)
# that is neither blank, a comment, a list item, an indented continuation, nor
# `key:`-shaped. Prints nothing when every line is well-formed.
_vaf_first_bad_key_line() {
  printf '%s\n' "$1" | awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*-[[:space:]]/ { next }
    /^[[:space:]]/ { next }
    /^[A-Za-z_][A-Za-z0-9_.-]*:/ { next }
    { print NR; exit }
  '
}

# Scalar value for a frontmatter key: strips `key:` plus surrounding whitespace,
# then at most one balanced outer pair of quotes. An unbalanced or mixed quote
# run is left intact so the caller sees what the YAML actually held.
_vaf_fm_value() {
  printf '%s\n' "$1" | awk -v k="$2" '
    $0 ~ "^" k ":" {
      sub("^" k ":[[:space:]]*", "")
      gsub(/[[:space:]]+$/, "")
      if ($0 ~ /^"[^"]*"$/ || $0 ~ /^\047[^\047]*\047$/) {
        $0 = substr($0, 2, length($0) - 2)
      }
      print
      exit
    }
  '
}

# Whether a frontmatter key is present at all (value may be empty).
_vaf_fm_has_key() {
  printf '%s\n' "$1" | grep -qE "^$2:"
}

validate_action_file() {
  local target="${1:-}"   # default so a zero-arg call under `set -u` reaches the guard
  if [ -z "$target" ]; then
    echo "validate_action_file: target path required" >&2
    return "$_VAF_NO_TARGET"
  fi
  if [ ! -f "$target" ] || [ ! -r "$target" ]; then
    echo "validate_action_file: $target — not a readable file" >&2
    return "$_VAF_UNREADABLE"
  fi

  # Verdict accumulators: every emitted row raises exactly one of these, so the
  # exit code stays derivable without re-reading the rows.
  local blocking=0 warning=0

  # --- Check 1: YAML frontmatter parses -------------------------------------
  local fm fm_rc
  fm="$(_vaf_extract_frontmatter "$target")"
  fm_rc=$?
  if [ "$fm_rc" -eq 2 ]; then
    _vaf_row CRITICAL frontmatter-parse 1 "line 1 is not '---' — no frontmatter block, so the frontmatter checks (name / description / risk_class / external-send) did not run"
    return "$_VAF_BLOCKING"
  fi
  if [ "$fm_rc" -eq 3 ]; then
    _vaf_row CRITICAL frontmatter-parse 1 "frontmatter opened at line 1 but never closed with '---' — the frontmatter checks (name / description / risk_class / external-send) did not run"
    return "$_VAF_BLOCKING"
  fi
  local bad_line
  bad_line="$(_vaf_first_bad_key_line "$fm")"
  if [ -n "$bad_line" ]; then
    _vaf_row CRITICAL frontmatter-parse "$((bad_line + 1))" "frontmatter line is not 'key: value', a list item, or an indented continuation"
    blocking=1
  fi

  # --- Check 2: name matches the filename slug ------------------------------
  local base slug name_val
  base="$(basename "$target")"
  slug="${base%.md}"
  name_val="$(_vaf_fm_value "$fm" name)"
  if [ "$name_val" != "$slug" ]; then
    _vaf_row CRITICAL name-matches-filename - "name: '$name_val' does not match the filename slug '$slug' — /geniro:actions run resolves by filename, so a mismatched name never runs"
    blocking=1
  fi

  # --- Checks 3-4: description shape and length -----------------------------
  local desc
  desc="$(_vaf_fm_value "$fm" description)"
  case "$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')" in
    "use when"*) ;;
    *)
      _vaf_row HIGH description-use-when - "description: does not start with 'Use when' — that opener is what makes the action's trigger legible in the listing"
      blocking=1
      ;;
  esac
  if [ "${#desc}" -gt "$_VAF_DESC_MAX_CHARS" ]; then
    _vaf_row HIGH description-length - "description: is ${#desc} characters, over the $_VAF_DESC_MAX_CHARS cap"
    blocking=1
  fi

  # --- Check 5: no unsubstituted template placeholders ----------------------
  # Whole file, not only the body: a `{{risk_class}}` left in frontmatter is the
  # same unfinished-scaffold defect and breaks the checks below on top of it.
  local ph
  ph="$(grep -nE '\{\{[A-Za-z_][A-Za-z0-9_]*\}\}' "$target" | head -n 1 || true)"
  if [ -n "$ph" ]; then
    _vaf_row HIGH no-placeholders "${ph%%:*}" "unsubstituted template placeholder still present — the scaffold was written without filling it in"
    blocking=1
  fi

  # --- Check 6: file length -------------------------------------------------
  local lines
  lines="$(awk 'END { print NR }' "$target")"
  if [ "$lines" -ge "$_VAF_MAX_LINES" ]; then
    _vaf_row MEDIUM file-length - "file is $lines lines (guideline under $_VAF_MAX_LINES) — consider splitting it into two actions"
    warning=1
  fi

  # --- Check 7: `## Steps` present with at least one numbered item ----------
  local steps_state
  steps_state="$(awk '
    /^##[[:space:]]+Steps[[:space:]]*$/ { seen = 1; in_steps = 1; next }
    in_steps && /^##[[:space:]]/ { in_steps = 0 }
    in_steps && /^[[:space:]]*[0-9]+[.)][[:space:]]/ { numbered = 1 }
    END {
      if (!seen) { print "missing" }
      else if (!numbered) { print "empty" }
      else { print "ok" }
    }
  ' "$target")"
  case "$steps_state" in
    missing)
      _vaf_row HIGH steps-section - "no '## Steps' section — run mode follows that section, so the action has nothing to execute"
      blocking=1
      ;;
    empty)
      _vaf_row HIGH steps-section - "'## Steps' carries no numbered item — run mode follows numbered steps, so the action has nothing to execute"
      blocking=1
      ;;
  esac

  # --- Checks 8-9: risk_class present and in range --------------------------
  local risk
  risk="$(_vaf_fm_value "$fm" risk_class)"
  if ! _vaf_fm_has_key "$fm" risk_class; then
    _vaf_row CRITICAL risk-class-present - "risk_class: is missing — it is required, and it drives the listing, the delete warning, and the lint"
    blocking=1
  else
    case "$risk" in
      low|medium|high) ;;
      *)
        _vaf_row CRITICAL risk-class-value - "risk_class: '$risk' is not one of low / medium / high"
        blocking=1
        ;;
    esac
  fi

  # --- Check 10: external-send implies medium-or-high risk ------------------
  local ext
  ext="$(_vaf_fm_value "$fm" external-send)"
  if [ "$ext" = "true" ]; then
    case "$risk" in
      medium|high) ;;
      *)
        _vaf_row HIGH external-send-risk - "external-send: true with risk_class: '$risk' — an action that reaches an external system is at least medium risk"
        blocking=1
        ;;
    esac
  fi

  # --- Checks 11-13: slug shape (kebab-case, length cap, reserved word) -----
  # `$slug` (basename minus .md) was computed at Check 2. A shape violation
  # here isn't a parse failure like Check 2 — the file still resolves by
  # filename — but it breaks the bare-slug fast path's kebab-normalization
  # (actions-reference.md §Target resolution Step 2) or, for a reserved word,
  # collides with Phase 1's verb-alias dispatch (SKILL.md §Sub-commands).
  case "$slug" in
    *[!a-z0-9-]*|-*|*-|"")
      _vaf_row HIGH slug-shape - "filename slug '$slug' is not kebab-case (lowercase letters, digits, hyphens only; no leading/trailing hyphen)"
      blocking=1
      ;;
  esac
  if [ "${#slug}" -gt "$_VAF_SLUG_MAX_CHARS" ]; then
    _vaf_row HIGH slug-length - "filename slug '$slug' is ${#slug} characters, over the $_VAF_SLUG_MAX_CHARS cap"
    blocking=1
  fi
  case " $_VAF_RESERVED_SLUGS " in
    *" $slug "*)
      _vaf_row HIGH slug-reserved-word - "filename slug '$slug' is a reserved word (one of: $_VAF_RESERVED_SLUGS) — it collides with Phase 1 verb detection"
      blocking=1
      ;;
  esac

  if [ "$blocking" -eq 1 ]; then
    return "$_VAF_BLOCKING"
  fi
  if [ "$warning" -eq 1 ]; then
    return "$_VAF_WARN"
  fi
  return "$_VAF_OK"
}

# Direct execution: `bash lib/validate-action-file.sh <path>`. Sourcing this
# file defines the function and runs nothing, so the two entry points share one
# implementation. The test is BASH_SOURCE-vs-$0, not a basename match: a
# same-named caller (the suite for this helper is `tests/actions/<same
# name>.sh`) would otherwise trip a basename check on every source.
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
  validate_action_file "$@"
  exit $?
fi
