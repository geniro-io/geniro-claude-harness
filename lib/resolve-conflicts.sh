#!/usr/bin/env bash
# Cross-layer conflict formatting helper.
#
# Spec: skills/_shared/resolve-conflicts.md
# Protocol: ARCHITECTURE.md §Memory Layers
#
# This helper does NOT detect conflicts — detection is semantic and lives in
# the consuming skill (which can use LLM judgment over the loaded L4/L3/L2
# content). What it does provide is canonical FORMATTING for the notice that
# every skill emits when it has decided a conflict exists, so the user-facing
# UX is identical across skills.
#
# Two output modes:
#
#   emit_conflict_notice <args...>
#     Soft conflict — skill continues using precedence-winning value.
#     Prints a [layer-conflict] block to stdout (one line per layer plus
#     a "Skill is following <Layer>" footer).
#
#   hard_conflict_block <args...>
#     Hard conflict — L4 rule directly contradicts L3 reality. Returns a
#     block intended to be embedded in AskUserQuestion text. Caller is
#     responsible for invoking AUQ; this helper only formats.
#
# Args (both modes) — flags, all optional except --subject:
#   --subject <text>       required; short label like "http library"
#   --l4 <text>            L4 rule (e.g. "use axios")
#   --l4-source <path>     where the L4 rule lives
#   --l3 <text>            L3 fact (e.g. "vite.config.ts present")
#   --l3-source <path>     where the L3 fact came from
#   --l2 <text>            L2 historical event
#   --l2-source <ref>      typically dedup_key or ts
#   --following <L2|L3|L4> for soft mode: which layer the skill is using
#   --suggested-action     optional remediation prompt

_rc_parse_args() {
  _RC_SUBJECT=""
  _RC_L4=""
  _RC_L4_SRC=""
  _RC_L3=""
  _RC_L3_SRC=""
  _RC_L2=""
  _RC_L2_SRC=""
  _RC_FOLLOWING=""
  _RC_SUGGESTED=""

  while [ $# -gt 0 ]; do
    case "$1" in
      # Each value-taking flag requires its operand: a bare trailing flag makes
      # `shift 2` fail to consume $1, so the while-loop spins on it forever.
      --subject)          [ "$#" -ge 2 ] || { echo "resolve-conflicts: --subject requires a value" >&2; return 64; }
                          _RC_SUBJECT="$2"; shift 2 ;;
      --l4)               [ "$#" -ge 2 ] || { echo "resolve-conflicts: --l4 requires a value" >&2; return 64; }
                          _RC_L4="$2"; shift 2 ;;
      --l4-source)        [ "$#" -ge 2 ] || { echo "resolve-conflicts: --l4-source requires a value" >&2; return 64; }
                          _RC_L4_SRC="$2"; shift 2 ;;
      --l3)               [ "$#" -ge 2 ] || { echo "resolve-conflicts: --l3 requires a value" >&2; return 64; }
                          _RC_L3="$2"; shift 2 ;;
      --l3-source)        [ "$#" -ge 2 ] || { echo "resolve-conflicts: --l3-source requires a value" >&2; return 64; }
                          _RC_L3_SRC="$2"; shift 2 ;;
      --l2)               [ "$#" -ge 2 ] || { echo "resolve-conflicts: --l2 requires a value" >&2; return 64; }
                          _RC_L2="$2"; shift 2 ;;
      --l2-source)        [ "$#" -ge 2 ] || { echo "resolve-conflicts: --l2-source requires a value" >&2; return 64; }
                          _RC_L2_SRC="$2"; shift 2 ;;
      --following)        [ "$#" -ge 2 ] || { echo "resolve-conflicts: --following requires a value" >&2; return 64; }
                          _RC_FOLLOWING="$2"; shift 2 ;;
      --suggested-action) [ "$#" -ge 2 ] || { echo "resolve-conflicts: --suggested-action requires a value" >&2; return 64; }
                          _RC_SUGGESTED="$2"; shift 2 ;;
      *)
        echo "resolve-conflicts: unknown flag '$1'" >&2
        return 64
        ;;
    esac
  done

  if [ -z "$_RC_SUBJECT" ]; then
    echo "resolve-conflicts: --subject required" >&2
    return 64
  fi
}

emit_conflict_notice() {
  _rc_parse_args "$@" || return $?

  case "$_RC_FOLLOWING" in
    L4|L3|L2|"") ;;
    *)
      echo "resolve-conflicts: --following must be L2, L3, or L4 (got '$_RC_FOLLOWING')" >&2
      return 64
      ;;
  esac

  printf 'Conflict on: %s\n' "$_RC_SUBJECT"

  if [ -n "$_RC_L4" ]; then
    if [ -n "$_RC_L4_SRC" ]; then
      printf '  Your project rules %s: %s\n' "$_RC_L4_SRC" "$_RC_L4"
    else
      printf '  Your project rules: %s\n' "$_RC_L4"
    fi
  fi
  if [ -n "$_RC_L3" ]; then
    if [ -n "$_RC_L3_SRC" ]; then
      printf '  Your project snapshot %s: %s\n' "$_RC_L3_SRC" "$_RC_L3"
    else
      printf '  Your project snapshot: %s\n' "$_RC_L3"
    fi
  fi
  if [ -n "$_RC_L2" ]; then
    if [ -n "$_RC_L2_SRC" ]; then
      printf '  Past learnings %s: %s\n' "$_RC_L2_SRC" "$_RC_L2"
    else
      printf '  Past learnings: %s\n' "$_RC_L2"
    fi
  fi

  if [ -n "$_RC_FOLLOWING" ]; then
    # The flag carries a layer code; the rendered line must not (fresh-user test).
    # `local`: this file is sourced into a skill's Bash block, so an unscoped
    # assignment would leak the name into the caller's shell.
    local _rc_following_name
    case "$_RC_FOLLOWING" in
      L4) _rc_following_name="your project rules" ;;
      L3) _rc_following_name="your project snapshot" ;;
      L2) _rc_following_name="past learnings" ;;
      *)  _rc_following_name="$_RC_FOLLOWING" ;;
    esac
    printf '  \342\206\222 Following %s.' "$_rc_following_name"
    if [ -n "$_RC_SUGGESTED" ]; then
      printf ' %s' "$_RC_SUGGESTED"
    fi
    printf '\n'
  fi
}

hard_conflict_block() {
  _rc_parse_args "$@" || return $?

  printf 'Conflict that needs your decision: %s\n\n' "$_RC_SUBJECT"
  printf 'The layers disagree and precedence (project rules > project snapshot > past learnings) alone cannot resolve this — your project rule contradicts current project-snapshot reality. Which is intent?\n\n'

  if [ -n "$_RC_L4" ]; then
    printf '  - Your project rules'
    [ -n "$_RC_L4_SRC" ] && printf ' (%s)' "$_RC_L4_SRC"
    printf ': %s\n' "$_RC_L4"
  fi
  if [ -n "$_RC_L3" ]; then
    printf '  - Your project snapshot'
    [ -n "$_RC_L3_SRC" ] && printf ' (%s)' "$_RC_L3_SRC"
    printf ': %s\n' "$_RC_L3"
  fi
  if [ -n "$_RC_L2" ]; then
    printf '  - Past learnings'
    [ -n "$_RC_L2_SRC" ] && printf ' (%s)' "$_RC_L2_SRC"
    printf ': %s\n' "$_RC_L2"
  fi

  if [ -n "$_RC_SUGGESTED" ]; then
    printf '\n%s\n' "$_RC_SUGGESTED"
  fi
}
