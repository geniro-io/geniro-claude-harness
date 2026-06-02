#!/usr/bin/env bash
# L2 episodic-memory write helper.
#
# Spec: skills/_shared/emit-learning.md
# Schema: ARCHITECTURE.md §Memory Layers
# Lifecycle: ARCHITECTURE.md §Memory Layers
#
# API:
#   echo '<json-object>' | emit_learning
#   → writes one JSONL line to .geniro/knowledge/learnings.jsonl
#
# Required JSON fields: producer, scope, summary, tags
# Optional fields:      ts, body, dedup_key, supersedes, deprecated, type, ext, trust, links, recurrence_count
#
# Pipeline:
#   1. Validate required fields.
#   2. Compute dedup_key if absent: sha256(producer|scope|normalize(summary))[:12]
#   3. Auto-inject ts (UTC ISO-8601) if absent.
#   4. Sanitize summary, body, and every string-valued path inside ext via
#      redact_secrets.
#   5. Default recurrence_count to 1 if absent.
#   6. Scan the last 200 entries for matching dedup_key:
#        - identical content (excluding ts) → no-op return 0
#        - different content → inject supersedes=<old_key>, carry forward
#          prior recurrence_count + 1, append
#        - no match → append fresh (recurrence_count = 1)

# Helper sourcing — idempotent.
if [ -z "${_EL_DEPS_LOADED:-}" ]; then
  _el_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "$_el_script_dir/repo-root.sh"
  # shellcheck disable=SC1091
  source "$_el_script_dir/redact-secrets.sh"
  # shellcheck disable=SC1091
  source "$_el_script_dir/atomic-state-write.sh"
  _EL_DEPS_LOADED=1
fi

# Normalize a summary string for dedup-key computation. The dedup-key spec
# just says `normalize(summary)`; standardize on lowercase + whitespace
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
  local producer scope summary tags_present tags_type
  producer=$(printf '%s' "$input" | jq -r '.producer // empty')
  scope=$(printf '%s' "$input" | jq -r '.scope // empty')
  summary=$(printf '%s' "$input" | jq -r '.summary // empty')
  tags_present=$(printf '%s' "$input" | jq -r 'has("tags")')

  if [ -z "$producer" ] || [ -z "$scope" ] || [ -z "$summary" ] || [ "$tags_present" != "true" ]; then
    echo "emit_learning: required fields missing (producer, scope, summary, tags)" >&2
    return 64
  fi

  # Type-check `tags` (must be an array). A bare string like `"tags":"bug"`
  # would otherwise round-trip through write+read but break query-side
  # filtering: `((.tags // []) | index($tag_filter))` on a string does
  # SUBSTRING match (jq's index() semantics) — so `--tag b` would match a
  # tags field of just `"bug"`. Fail fast at the writer.
  tags_type=$(printf '%s' "$input" | jq -r '.tags | type')
  if [ "$tags_type" != "array" ]; then
    echo "emit_learning: 'tags' must be an array (got '$tags_type')" >&2
    return 64
  fi

  # Type-check `trust` if present. The schema defines a closed enum
  # {verified, retrieved, inferred}; an invalid value would silently filter
  # under --min-trust queries and confuse readers. Absent trust is allowed
  # (query-side treats it as `inferred`).
  local trust
  trust=$(printf '%s' "$input" | jq -r '.trust // empty')
  case "$trust" in
    ""|verified|retrieved|inferred) ;;
    *)
      echo "emit_learning: 'trust' must be verified|retrieved|inferred (got '$trust')" >&2
      return 64
      ;;
  esac

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
  # caller pre-populated them. `recurrence_count` defaults to 1 on a fresh
  # emit; the dedup branch below carries forward + increments the prior
  # entry's value when a re-emit matches an existing dedup_key. Entries
  # written before this field existed have it absent — readers treat
  # absent as 1, so the default preserves backward-compatible scoring.
  local rebuilt
  rebuilt=$(printf '%s' "$input" | jq -c \
    --arg ts "$ts" \
    --arg dk "$dedup_key" \
    --arg sum "$summary_sanitized" \
    '. + {ts:$ts, dedup_key:$dk, summary:$sum, recurrence_count:(.recurrence_count // 1)}')

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
  root=$(_geniro_repo_root)
  log="$root/.geniro/knowledge/learnings.jsonl"

  if [ -f "$log" ]; then
    local last_match
    last_match=$(tail -n 200 "$log" 2>/dev/null \
      | jq -Rc --arg k "$dedup_key" 'fromjson? | select(.dedup_key == $k)' 2>/dev/null \
      | tail -n 1)

    if [ -n "$last_match" ]; then
      # Compare excluding ts, recurrence_count, and supersedes. All three are
      # derived: ts is auto-injected per write, recurrence_count is a re-emit
      # counter that always differs between a prior entry (carried-forward
      # value) and a fresh-default new entry, and supersedes is auto-injected
      # only on the prior superseding entry — a fresh re-emit of that same
      # content has no supersedes at compare time. Excluding all three makes an
      # identical re-emit of a superseding entry compare equal (correct no-op:
      # no duplicate line, no false recurrence_count increment), while
      # genuinely different content still differs.
      local prior_norm new_norm
      prior_norm=$(printf '%s' "$last_match" | jq -cS 'del(.ts, .recurrence_count, .supersedes)')
      new_norm=$(printf '%s' "$rebuilt" | jq -cS 'del(.ts, .recurrence_count, .supersedes)')
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
      # Carry forward the prior entry's recurrence_count and increment by 1
      # on this superseding entry. Absent on the prior entry (pre-field
      # writes) counts as 1, so a first re-emit lands at 2.
      local prior_rc
      prior_rc=$(printf '%s' "$last_match" | jq -r '.recurrence_count // 1')
      rebuilt=$(printf '%s' "$rebuilt" | jq -c --argjson prc "$prior_rc" '.recurrence_count = ($prc + 1)')
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
