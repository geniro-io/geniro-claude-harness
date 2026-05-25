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
      --subject)          _RC_SUBJECT="$2"; shift 2 ;;
      --l4)               _RC_L4="$2"; shift 2 ;;
      --l4-source)        _RC_L4_SRC="$2"; shift 2 ;;
      --l3)               _RC_L3="$2"; shift 2 ;;
      --l3-source)        _RC_L3_SRC="$2"; shift 2 ;;
      --l2)               _RC_L2="$2"; shift 2 ;;
      --l2-source)        _RC_L2_SRC="$2"; shift 2 ;;
      --following)        _RC_FOLLOWING="$2"; shift 2 ;;
      --suggested-action) _RC_SUGGESTED="$2"; shift 2 ;;
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

  printf '[layer-conflict] subject: %s\n' "$_RC_SUBJECT"

  if [ -n "$_RC_L4" ]; then
    if [ -n "$_RC_L4_SRC" ]; then
      printf '  L4 %s: %s\n' "$_RC_L4_SRC" "$_RC_L4"
    else
      printf '  L4: %s\n' "$_RC_L4"
    fi
  fi
  if [ -n "$_RC_L3" ]; then
    if [ -n "$_RC_L3_SRC" ]; then
      printf '  L3 %s: %s\n' "$_RC_L3_SRC" "$_RC_L3"
    else
      printf '  L3: %s\n' "$_RC_L3"
    fi
  fi
  if [ -n "$_RC_L2" ]; then
    if [ -n "$_RC_L2_SRC" ]; then
      printf '  L2 %s: %s\n' "$_RC_L2_SRC" "$_RC_L2"
    else
      printf '  L2: %s\n' "$_RC_L2"
    fi
  fi

  if [ -n "$_RC_FOLLOWING" ]; then
    printf '  → Skill is following %s (precedence).' "$_RC_FOLLOWING"
    if [ -n "$_RC_SUGGESTED" ]; then
      printf ' %s' "$_RC_SUGGESTED"
    fi
    printf '\n'
  fi
}

hard_conflict_block() {
  _rc_parse_args "$@" || return $?

  printf 'Hard cross-layer conflict on: %s\n\n' "$_RC_SUBJECT"
  printf 'The layers disagree and precedence (L4 > L3 > L2) alone cannot resolve this — your L4 rule contradicts current L3 reality. Which is intent?\n\n'

  if [ -n "$_RC_L4" ]; then
    printf '  - L4 rule'
    [ -n "$_RC_L4_SRC" ] && printf ' (%s)' "$_RC_L4_SRC"
    printf ': %s\n' "$_RC_L4"
  fi
  if [ -n "$_RC_L3" ]; then
    printf '  - L3 fact'
    [ -n "$_RC_L3_SRC" ] && printf ' (%s)' "$_RC_L3_SRC"
    printf ': %s\n' "$_RC_L3"
  fi
  if [ -n "$_RC_L2" ]; then
    printf '  - L2 history'
    [ -n "$_RC_L2_SRC" ] && printf ' (%s)' "$_RC_L2_SRC"
    printf ': %s\n' "$_RC_L2"
  fi

  if [ -n "$_RC_SUGGESTED" ]; then
    printf '\n%s\n' "$_RC_SUGGESTED"
  fi
}
