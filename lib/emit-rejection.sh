#!/usr/bin/env bash
# AUQ-rejection L2 emit helper.
#
# Spec: skills/_shared/emit-rejection.md
#
# Called at AUQ-resolution sites to convert rejection-signal picks into a
# cross-session L2 entry. Skills already persist the pick into T1
# frontmatter `approvals[]` (task-scoped); this helper additionally emits
# a `user_rejected_suggestion` entry to learnings.jsonl (cross-session).
#
# API:
#   emit_rejection_if_signal \
#       <producer> <scope> <auq_category> <suggestion> <picked> [recommended]
#
# Behavior:
#   - Detects rejection signal:
#     * 'cancel' / 'abort' / 'reject' / 'skip' anywhere in $picked (substring,
#       case-insensitive) → explicit_*. 'no' is matched EXACTLY (no/no./no,/no!)
#       or as a don't / do-not prefix — NOT any substring containing "no" (so
#       "now", "notes", "anonymous" do not false-trigger).
#     * Else if $recommended supplied AND $picked != $recommended →
#       picked_non_recommended
#     * Else → no signal, no-op (rc=0)
#   - On signal: emit L2 entry with type=user_rejected_suggestion,
#     trust=verified, required ext.{suggestion, auq_category, rejection_signal}
#
# Exit codes:
#   0 — emitted, or no-op (no signal detected)
#  64 — missing required arg
#   1 — emit-learning helper error

if [ -z "${_ER_DEPS_LOADED:-}" ]; then
  # Cross-shell self-location: BASH_SOURCE is bash-only — sourced under zsh it
  # is empty and the sibling `source` calls below would silently load nothing.
  # zsh names the sourced file via the %x prompt escape; eval keeps the
  # zsh-only syntax out of bash's (and ShellCheck's) parser.
  if [ -n "${BASH_SOURCE:-}" ]; then
    _er_self="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval '_er_self="${(%):-%x}"'
  else
    _er_self="$0"
  fi
  _er_script_dir="$(cd "$(dirname "$_er_self")" && pwd)"
  # shellcheck disable=SC1091
  source "$_er_script_dir/emit-learning.sh"
  _ER_DEPS_LOADED=1
fi

emit_rejection_if_signal() {
  # Read every positional with a default so a caller running under `set -u`
  # (most skill Bash blocks do) reaches the validation below and gets a clean
  # rc=64 instead of an "unbound variable" abort on a short arg list.
  local producer="${1:-}"
  local scope="${2:-}"
  local auq_category="${3:-}"
  local suggestion="${4:-}"
  local picked="${5:-}"
  local recommended="${6:-}"

  if [ -z "$producer" ] || [ -z "$scope" ] || [ -z "$auq_category" ] \
     || [ -z "$suggestion" ] || [ -z "$picked" ]; then
    echo "emit_rejection_if_signal: required args: <producer> <scope> <auq_category> <suggestion> <picked> [recommended]" >&2
    return 64
  fi

  # Detect rejection signal.
  local signal=""
  local lower_picked
  lower_picked=$(printf '%s' "$picked" | tr '[:upper:]' '[:lower:]')

  case "$lower_picked" in
    *cancel*)   signal="explicit_cancel" ;;
    *abort*)    signal="explicit_cancel" ;;
    *reject*)   signal="explicit_no" ;;
    'no'|'no.'|'no,'|'no!'|"don't"*|"do not"*) signal="explicit_no" ;;
    *skip*)     signal="explicit_skip" ;;
    *)
      if [ -n "$recommended" ] && [ "$picked" != "$recommended" ]; then
        signal="picked_non_recommended"
      fi
      ;;
  esac

  # No signal → no-op.
  if [ -z "$signal" ]; then
    return 0
  fi

  # Compose tags. Generic auq-rejection + per-category.
  local tags_json
  tags_json=$(jq -nc --arg cat "$auq_category" \
    '["auq-rejection", $cat]') || return 1

  # Compose summary with picked option.
  local summary="user picked '${picked}' over '${recommended:-<no recommendation>}' for '${suggestion}'"

  # Compose payload.
  local payload
  payload=$(jq -nc \
    --arg producer "$producer" \
    --arg scope "$scope" \
    --arg summary "$summary" \
    --argjson tags "$tags_json" \
    --arg suggestion "$suggestion" \
    --arg category "$auq_category" \
    --arg signal "$signal" \
    '{
      producer: $producer, scope: $scope, summary: $summary, tags: $tags,
      type: "user_rejected_suggestion", trust: "verified",
      ext: {suggestion: $suggestion, auq_category: $category, rejection_signal: $signal}
    }') || return 1

  printf '%s' "$payload" | emit_learning || return 1
  # Echo the outcome rather than splitting the return code. A caller cannot tell
  # "emitted" from "no signal" on its own — that is the whole point of this
  # helper — and rc is the wrong channel to tell it: the no-op path is the
  # common one (every accepted suggestion), so returning non-zero there would
  # abort any caller running under `set -e` on its normal path. Silence on
  # no-op, one line on emit, rc=0 for both.
  printf 'Recorded a rejection pattern: %s\n' "$suggestion"
  return 0
}
