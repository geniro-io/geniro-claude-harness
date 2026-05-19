#!/usr/bin/env bash
# L2 episodic-memory write helper.
#
# Spec: skills/_shared/emit-learning.md
# Schema: architecture/M2-memory-layers.md §5.1
# Lifecycle: architecture/M2-memory-layers.md §5.2
#
# API:
#   echo '<json-object>' | emit_learning
#   → writes one JSONL line to .geniro/knowledge/learnings.jsonl
#
# Required JSON fields: producer, scope, summary, tags
# Optional fields:      ts, body, dedup_key, supersedes, deprecated, type, ext, trust, links
#
# Pipeline (matches M2 §5.2):
#   1. Validate required fields.
#   2. Compute dedup_key if absent: sha256(producer|scope|normalize(summary))[:12]
#   3. Auto-inject ts (UTC ISO-8601) if absent.
#   4. Sanitize summary, body, and every string-valued path inside ext via
#      redact_secrets.
#   5. Scan the last 200 entries for matching dedup_key:
#        - identical content (excluding ts) → no-op return 0
#        - different content → inject supersedes=<old_key>, append
#        - no match → append fresh

# Helper sourcing — idempotent.
if [ -z "${_EL_DEPS_LOADED:-}" ]; then
  _el_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "$_el_script_dir/redact-secrets.sh"
  # shellcheck disable=SC1091
  source "$_el_script_dir/atomic-state-write.sh"
  _EL_DEPS_LOADED=1
fi

# Repo root — re-uses redact-secrets' helper if loaded, else falls back.
_el_repo_root() {
  if declare -F _red_repo_root >/dev/null; then
    _red_repo_root
  elif git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    echo "$PWD"
  fi
}

# Normalize a summary string for dedup-key computation. Per M2 §5.1 the spec
# just says `normalize(summary)`; we standardize on lowercase + whitespace
# collapse + trim. Documented in the helper spec.
_el_normalize() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -s '[:space:]' ' ' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

emit_learning() {
  local input
  input="$(cat)"

  if [ -z "$input" ]; then
    return 0
  fi

  if ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
    echo "emit_learning: invalid JSON on stdin" >&2
    return 64
  fi

  # Extract required fields up front.
  local producer scope summary tags_present
  producer=$(printf '%s' "$input" | jq -r '.producer // empty')
  scope=$(printf '%s' "$input" | jq -r '.scope // empty')
  summary=$(printf '%s' "$input" | jq -r '.summary // empty')
  tags_present=$(printf '%s' "$input" | jq -r 'has("tags")')

  if [ -z "$producer" ] || [ -z "$scope" ] || [ -z "$summary" ] || [ "$tags_present" != "true" ]; then
    echo "emit_learning: required fields missing (producer, scope, summary, tags)" >&2
    return 64
  fi

  # Compute dedup_key if absent.
  local dedup_key
  dedup_key=$(printf '%s' "$input" | jq -r '.dedup_key // empty')
  if [ -z "$dedup_key" ]; then
    local norm
    norm=$(_el_normalize "$summary")
    dedup_key=$(printf '%s|%s|%s' "$producer" "$scope" "$norm" | sha256sum | cut -c1-12)
  fi

  # Auto-inject ts if absent.
  local ts
  ts=$(printf '%s' "$input" | jq -r '.ts // empty')
  if [ -z "$ts" ]; then
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  fi

  # Sanitize summary and body.
  local summary_sanitized body body_sanitized
  summary_sanitized=$(printf '%s' "$summary" | redact_secrets "$producer" "summary" "$dedup_key")
  body=$(printf '%s' "$input" | jq -r '.body // empty')
  if [ -n "$body" ]; then
    body_sanitized=$(printf '%s' "$body" | redact_secrets "$producer" "body" "$dedup_key")
  fi

  # Rebuild the entry with normalized fields. We use jq to apply the
  # changes atomically; this also drops the auto-computed fields if the
  # caller pre-populated them.
  local rebuilt
  rebuilt=$(printf '%s' "$input" | jq -c \
    --arg ts "$ts" \
    --arg dk "$dedup_key" \
    --arg sum "$summary_sanitized" \
    '. + {ts:$ts, dedup_key:$dk, summary:$sum}')

  if [ -n "$body" ]; then
    rebuilt=$(printf '%s' "$rebuilt" | jq -c --arg b "$body_sanitized" '.body = $b')
  fi

  # Sanitize every string-valued path inside ext (one redact_secrets call per
  # path; preserves array shape via setpath).
  if printf '%s' "$rebuilt" | jq -e 'has("ext") and (.ext != null)' >/dev/null 2>&1; then
    local paths_json
    paths_json=$(printf '%s' "$rebuilt" | jq -c '[.ext | paths(strings)]')
    local path_count
    path_count=$(printf '%s' "$paths_json" | jq 'length')
    local i
    for ((i = 0; i < path_count; i++)); do
      local path_arr val field_label sanitized
      path_arr=$(printf '%s' "$paths_json" | jq -c ".[$i]")
      val=$(printf '%s' "$rebuilt" | jq -r --argjson p "$path_arr" '.ext | getpath($p)')
      field_label=$(printf '%s' "$path_arr" | jq -r '"ext." + (map(tostring) | join("."))')
      sanitized=$(printf '%s' "$val" | redact_secrets "$producer" "$field_label" "$dedup_key")
      rebuilt=$(printf '%s' "$rebuilt" | jq -c --argjson p "$path_arr" --arg v "$sanitized" \
        '.ext = (.ext | setpath($p; $v))')
    done
  fi

  # Dedup scan — last 200 entries.
  local log root
  root=$(_el_repo_root)
  log="$root/.geniro/knowledge/learnings.jsonl"

  if [ -f "$log" ]; then
    local last_match
    last_match=$(tail -n 200 "$log" 2>/dev/null \
      | jq -c --arg k "$dedup_key" 'select(.dedup_key == $k)' 2>/dev/null \
      | tail -n 1)

    if [ -n "$last_match" ]; then
      # Compare excluding ts. If equal, this is a no-op write.
      local prior_norm new_norm
      prior_norm=$(printf '%s' "$last_match" | jq -cS 'del(.ts)')
      new_norm=$(printf '%s' "$rebuilt" | jq -cS 'del(.ts)')
      if [ "$prior_norm" = "$new_norm" ]; then
        return 0
      fi
      # Different content under same dedup_key → auto-inject supersedes
      # UNLESS the caller already set supersedes explicitly.
      local existing_super
      existing_super=$(printf '%s' "$rebuilt" | jq -r '.supersedes // empty')
      if [ -z "$existing_super" ]; then
        rebuilt=$(printf '%s' "$rebuilt" | jq -c --arg k "$dedup_key" '.supersedes = $k')
      fi
    fi
  fi

  # Compactify to one line (single-line JSONL).
  local line
  line=$(printf '%s' "$rebuilt" | jq -c .)

  if [ "${#line}" -gt 4096 ]; then
    echo "emit_learning: serialized entry exceeds 4096 bytes (${#line}); atomicity not guaranteed — consider shrinking body" >&2
    return 68
  fi

  printf '%s' "$line" | atomic_state_append "$log"
}
