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
#   1b. Reject obvious instruction-injection payloads in summary/body/ext
#       (defense-in-depth — these get replayed into context by query_learnings).
#   2. Compute dedup_key if absent: sha256(producer|scope|normalize(summary))[:12]
#   3. Auto-inject ts (UTC ISO-8601) if absent.
#   4. Sanitize summary and body directly, then sweep every remaining string
#      value anywhere else in the entry (ext, links, tags, any caller-added
#      key) via redact_secrets — one walk, not a loop per field.
#   5. Default recurrence_count to 1 if absent.
#   6. Scan the last 200 entries for matching dedup_key:
#        - identical content (excluding ts) → no-op return 0
#        - different content → inject supersedes=<old_key>, carry forward
#          prior recurrence_count + 1, append
#        - no match → append fresh (recurrence_count = 1)

# Helper sourcing — idempotent.
if [ -z "${_EL_DEPS_LOADED:-}" ]; then
  # Cross-shell self-location: BASH_SOURCE is bash-only — sourced under zsh it
  # is empty and the sibling `source` calls below would silently load nothing.
  # zsh names the sourced file via the %x prompt escape; eval keeps the
  # zsh-only syntax out of bash's (and ShellCheck's) parser.
  if [ -n "${BASH_SOURCE:-}" ]; then
    _el_self="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval '_el_self="${(%):-%x}"'
  else
    _el_self="$0"
  fi
  _el_script_dir="$(cd "$(dirname "$_el_self")" && pwd)"
  # shellcheck disable=SC1091
  source "$_el_script_dir/repo-root.sh"
  # shellcheck disable=SC1091
  source "$_el_script_dir/redact-secrets.sh"
  # shellcheck disable=SC1091
  source "$_el_script_dir/atomic-state-write.sh"
  # shellcheck disable=SC1091
  source "$_el_script_dir/hash.sh"
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

  # Reject instruction-injection payloads at write time. L2 learnings are
  # re-loaded into orchestrator/subagent context by query_learnings, so a
  # poisoned free-text field (e.g. one auto-emitted from a fetched page or a PR
  # body) would be replayed verbatim. The read side is defended by
  # skills/_shared/untrusted-content-defense.md; this closes the write side.
  # The scan covers EVERY string value in the entry (`.. | strings`) so a payload
  # cannot ride in via a non-canonical key (e.g. `entry`/`note`); the structured
  # injection shapes never match control-plane tokens like producer/scope/tags,
  # so scanning them is harmless. High-signal patterns only — the
  # "<verb> <prev-reference> <instruction-noun>" shape and chat-template control
  # tokens virtually never appear in genuine technical learnings, so false-reject
  # risk is low, and a false reject drops just one best-effort learning — the
  # caller surfaces the non-zero return (emit-learning.md §Caller contract rule 3)
  # but does not block the workflow on it. Shares the rc=64 "input rejected" family.
  local scan_text
  scan_text=$(printf '%s' "$input" | jq -r '[.. | strings] | join("\n")' 2>/dev/null || printf '%s' "$summary")
  if printf '%s' "$scan_text" | grep -qiE \
'(ignore|disregard|forget|override)[[:space:]]+([a-z]+[[:space:]]+)?(previous|prior|earlier|preceding|above)[[:space:]]+([a-z]+[[:space:]]+)?(instruction|prompt|context|directive|rule|message)s?|(new|updated)[[:space:]]+(instruction|directive|rule)s?[[:space:]]*:|new[[:space:]]+system[[:space:]]+prompt|<\|(im_start|im_end|system|user|assistant)\|>|</?(system|assistant)[[:space:]]*>'; then
    echo "emit_learning: refusing entry — contains instruction-injection patterns (defense-in-depth; see skills/_shared/untrusted-content-defense.md)" >&2
    return 64
  fi

  # Compute dedup_key if absent.
  local dedup_key
  dedup_key=$(printf '%s' "$input" | jq -r '.dedup_key // empty')
  if [ -z "$dedup_key" ]; then
    local norm
    norm=$(_el_normalize "$summary")
    dedup_key=$(printf '%s|%s|%s' "$producer" "$scope" "$norm" | _geniro_sha256 | cut -c1-12)
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

  # Sanitize every remaining string, at ANY depth, anywhere except the
  # control-plane identifiers (ts / dedup_key / supersedes / producer / scope /
  # type / trust) and summary / body, already sanitized above. This ONE walk
  # is deliberately the only path into ext, links, AND tags — no per-field
  # loop for any of them, because a per-field loop only catches the shape it
  # was written for: a dedicated `.ext | paths(strings)` call finds nothing
  # when `ext` itself is a scalar string (paths(strings) enumerates paths to
  # DESCENDANTS, and a scalar has none), and a loop keyed on `.tags[$i]`'s own
  # type skips a non-string element (e.g. an object) even though a secret can
  # be nested inside it. Walking `paths(strings)` over the WHOLE entry finds
  # every string leaf regardless of which key or container holds it — a
  # scalar `ext`/`links` value is itself a leaf at path `["ext"]`/`["links"]`,
  # and a string nested inside a non-string `tags[]` element is a leaf same as
  # any other. `paths(strings)` rather than a top-level `type == "string"`
  # selection for the same reason: the old top-level form matched only scalar
  # top-level fields, so a caller stashing a secret one level down (`meta:
  # {tok: "..."}`) persisted it verbatim into learnings.jsonl, which
  # query_learnings then replays into context. Path labels use dotted
  # notation throughout (`ext.options.0`, `links.refs.1`, `tags.0`, or
  # `tags.0.k` for a string nested inside a non-string tag).
  local dpaths_json dpath_count di
  dpaths_json=$(printf '%s' "$rebuilt" | jq -c \
    '[paths(strings)
      | select(.[0] as $k
               | ["ts","dedup_key","summary","body","supersedes","producer",
                  "scope","type","trust"]
               | index($k) == null)]')
  dpath_count=$(printf '%s' "$dpaths_json" | jq 'length')
  for ((di = 0; di < dpath_count; di++)); do
    local dpath_arr dval dlabel dsan
    dpath_arr=$(printf '%s' "$dpaths_json" | jq -c ".[$di]")
    dval=$(printf '%s' "$rebuilt" | jq -r --argjson p "$dpath_arr" 'getpath($p)')
    dlabel=$(printf '%s' "$dpath_arr" | jq -r 'map(tostring) | join(".")')
    dsan=$(printf '%s' "$dval" | redact_secrets "$producer" "$dlabel" "$dedup_key")
    rebuilt=$(printf '%s' "$rebuilt" | jq -c --argjson p "$dpath_arr" --arg v "$dsan" 'setpath($p; $v)')
  done

  # Dedup scan — last N entries (window overridable; see skills/_shared/emit-learning.md).
  local log root dedup_window
  root=$(_geniro_repo_root)
  log="$root/.geniro/knowledge/learnings.jsonl"
  dedup_window="${GENIRO_DEDUP_WINDOW:-200}"
  case "$dedup_window" in ''|*[!0-9]*) dedup_window=200 ;; esac

  if [ -f "$log" ]; then
    local last_match
    last_match=$(tail -n "$dedup_window" "$log" 2>/dev/null \
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

  # Byte count, not character count — ${#line} counts characters, but the append
  # cap is a byte limit; multibyte content just under GENIRO_APPEND_MAX_BYTES
  # chars can exceed it in bytes and silently skip the guard. The ceiling here
  # is GENIRO_APPEND_MAX_BYTES itself (content bytes only, not the PIPE_BUF byte
  # count) — atomic_state_append reserves the remaining bytes for its own
  # newline framing, so total bytes written stay within PIPE_BUF (4096 on
  # Linux, only 512 on macOS — see atomic-state-write.md §Constraints).
  local line_bytes
  line_bytes=$(printf '%s' "$line" | wc -c | tr -d ' ')
  if [ "$line_bytes" -gt "$GENIRO_APPEND_MAX_BYTES" ]; then
    echo "emit_learning: serialized entry + framing exceeds the ${GENIRO_APPEND_MAX_BYTES}-byte ceiling (${line_bytes}); atomicity not guaranteed — consider shrinking body" >&2
    return 68
  fi

  printf '%s' "$line" | atomic_state_append "$log"
}
