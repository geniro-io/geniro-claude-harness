#!/usr/bin/env bash
# L2 legacy-entry schema-migration helper.
#
# Spec: skills/_shared/migrate-learnings.md
# Design rationale: architecture/M2-memory-layers.md §5.1 (canonical schema).
#
# Walks .geniro/knowledge/learnings.jsonl and rewrites pre-M2 / non-canonical
# entries to the canonical M2 §5.1 schema. Legacy fields are PRESERVED
# on-disk (schema is open) — only missing required fields are synthesized.
#
# Cheap idempotency gate: if all entries already have the 4 required fields
# (producer, scope, summary, tags-array), returns rc=1 fast.
#
# Invoked by /geniro:setup Phase 1 §1.2a. One-shot migration; safe to re-run.
#
# API:
#   migrate_legacy_learnings [--dry-run]
#   → rewrites legacy entries к canonical schema (or reports without writing).
#
# Exit codes:
#   0 — success (rewrote N entries, or dry-run completed)
#   1 — no learnings.jsonl present OR all entries already canonical (informational)
#   2 — IO error (jq failed, tmp-write failed, rename failed, bad flag)

if [ -z "${_ML_DEPS_LOADED:-}" ]; then
  _ml_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "$_ml_script_dir/repo-root.sh"
  # shellcheck disable=SC1091
  source "$_ml_script_dir/redact-secrets.sh"
  _ML_DEPS_LOADED=1
fi

migrate_legacy_learnings() {
  local dry_run=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      *)
        echo "migrate_legacy_learnings: unknown flag '$1'" >&2
        return 2
        ;;
    esac
  done

  local root log
  root=$(_geniro_repo_root)
  log="$root/.geniro/knowledge/learnings.jsonl"

  if [ ! -f "$log" ] || [ ! -s "$log" ]; then
    echo "migrate-learnings: no learnings.jsonl found (nothing к migrate)" >&2
    return 1
  fi

  # Cheap idempotency gate: count lines missing any of the 4 required fields.
  local legacy_count
  legacy_count=$(jq -Rc 'fromjson? | select(.producer == null or .scope == null or .summary == null or (.tags | type) != "array")' "$log" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$legacy_count" = "0" ]; then
    echo "migrate-learnings: all entries already canonical (no-op)" >&2
    return 1
  fi

  local now_iso
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local tmp="${log}.tmp.$$"
  : > "$tmp" || {
    echo "migrate-learnings: failed к open tmp file $tmp" >&2
    return 2
  }

  local truncated_skipped=0
  local migrated_count=0
  local line needs_migrate synthesized new_line key_source dedup_key final_line

  # jq filter to synthesize required fields. Uses --arg now_iso for ts default;
  # category-to-type mapping table inline.
  local synth_filter='
    . as $orig
    | (if (.summary // null) != null then .summary
       elif (.title // null) != null then (.title | tostring | .[0:240])
       else "<legacy entry without summary>"
       end) as $summary
    | (if (.tags // null) != null and (.tags | type) == "array" then .tags
       else ((["legacy-migrated"]
              + (if (.category // null) != null and (.category | tostring | length) > 0 then [.category | tostring] else [] end)
              + (if (.type // null) != null and (.type | tostring | length) > 0 then [.type | tostring] else [] end)
             ) | unique)
       end) as $tags
    | (if (.ts // null) != null then .ts else $now_iso end) as $ts
    | (if (.type // null) != null then .type
       else
         (if (.category // null) == "pattern" then "discovery"
          elif (.category // null) == "gotcha" then "diagnosis"
          elif (.category // null) == "anti-pattern" then "pitfall"
          elif (.category // null) == "investigation-methodology" then "discovery"
          else "discovery"
          end)
       end) as $type
    | (if (.trust // null) != null then .trust else "inferred" end) as $trust
    | $orig
      + {producer: (.producer // "/geniro:setup"),
         scope: (.scope // "global"),
         summary: $summary,
         tags: $tags,
         ts: $ts,
         type: $type,
         trust: $trust,
         migrated_from_legacy: true}
  '

  # Per-type breakdown counters (used by both dry-run and real-run summary).
  local count_pattern=0 count_gotcha=0 count_antipattern=0 count_other=0

  while IFS= read -r line || [ -n "$line" ]; do
    # Skip blank lines (preserve as-is).
    if [ -z "$line" ]; then
      printf '%s\n' "$line" >> "$tmp"
      continue
    fi

    # Detect: does this line need migration?
    needs_migrate=$(printf '%s\n' "$line" | jq -r 'if (.producer == null or .scope == null or .summary == null or (.tags | type) != "array") then "yes" else "no" end' 2>/dev/null || echo "skip")

    if [ "$needs_migrate" = "skip" ]; then
      # JSON-syntax-error line: preserve verbatim, no counter bump.
      printf '%s\n' "$line" >> "$tmp"
      continue
    fi

    if [ "$needs_migrate" = "no" ]; then
      printf '%s\n' "$line" >> "$tmp"
      continue
    fi

    # Synthesize required fields.
    synthesized=$(printf '%s\n' "$line" | jq -c --arg now_iso "$now_iso" "$synth_filter" 2>/dev/null) || {
      # jq failure on this line — preserve verbatim, no counter bump.
      printf '%s\n' "$line" >> "$tmp"
      continue
    }

    # Sanitize the synthesized summary field (legacy .title may contain secrets).
    local raw_summary sanitized_summary
    raw_summary=$(printf '%s\n' "$synthesized" | jq -r '.summary // ""' 2>/dev/null)
    if [ -n "$raw_summary" ]; then
      sanitized_summary=$(printf '%s' "$raw_summary" | redact_secrets "/geniro:setup" "migrate.summary" "pending-$$" 2>/dev/null)
      if [ -n "$sanitized_summary" ] && [ "$sanitized_summary" != "$raw_summary" ]; then
        synthesized=$(printf '%s\n' "$synthesized" | jq -c --arg s "$sanitized_summary" '.summary = $s' 2>/dev/null) || true
      fi
    fi

    # Compute dedup_key from synthesized producer|scope|summary.
    key_source=$(printf '%s\n' "$synthesized" | jq -r '"\(.producer)|\(.scope)|\(.summary | ascii_downcase | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; ""))"' 2>/dev/null)
    if [ -n "$key_source" ]; then
      dedup_key=$(printf '%s' "$key_source" | shasum -a 256 | cut -c1-12)
      new_line=$(printf '%s\n' "$synthesized" | jq -c --arg k "$dedup_key" 'if (.dedup_key // null) == null then . + {dedup_key: $k} else . end' 2>/dev/null)
    else
      new_line="$synthesized"
    fi

    if [ -z "$new_line" ]; then
      # Last-resort fallback: keep original.
      printf '%s\n' "$line" >> "$tmp"
      continue
    fi

    # 4096-byte guardrail: if migrated line is too large, preserve original.
    if [ "${#new_line}" -gt 4096 ]; then
      truncated_skipped=$((truncated_skipped + 1))
      printf '%s\n' "$line" >> "$tmp"
      continue
    fi

    printf '%s\n' "$new_line" >> "$tmp"
    # Bump per-category counter only after successful write.
    local orig_category
    orig_category=$(printf '%s\n' "$line" | jq -r '.category // "other"' 2>/dev/null || echo "other")
    case "$orig_category" in
      pattern) count_pattern=$((count_pattern + 1)) ;;
      gotcha) count_gotcha=$((count_gotcha + 1)) ;;
      anti-pattern) count_antipattern=$((count_antipattern + 1)) ;;
      *) count_other=$((count_other + 1)) ;;
    esac
    migrated_count=$((migrated_count + 1))
  done < "$log"

  # Build per-category breakdown string for stderr summary.
  local by_category=""
  [ "$count_pattern" -gt 0 ] && by_category="${by_category}  pattern → discovery: ${count_pattern}\n"
  [ "$count_gotcha" -gt 0 ] && by_category="${by_category}  gotcha → diagnosis: ${count_gotcha}\n"
  [ "$count_antipattern" -gt 0 ] && by_category="${by_category}  anti-pattern → pitfall: ${count_antipattern}\n"
  [ "$count_other" -gt 0 ] && by_category="${by_category}  (untyped): ${count_other}\n"

  if [ "$dry_run" = "true" ]; then
    echo "migrate-learnings: ${migrated_count} legacy entries would be migrated (dry-run — no changes written):" >&2
    printf '%b' "$by_category" >&2
    if [ "$truncated_skipped" -gt 0 ]; then
      echo "Skipped ${truncated_skipped} entries (>4096 bytes after migration; legacy unchanged)." >&2
    fi
    echo "" >&2
    echo "Run without --dry-run к rewrite legacy entries к canonical schema." >&2
    rm -f "$tmp"
    return 0
  fi

  # Real run: atomic rename.
  mv "$tmp" "$log" || {
    rm -f "$tmp"
    echo "migrate-learnings: failed к rename tmp к $log" >&2
    return 2
  }

  echo "migrate-learnings: rewrote ${migrated_count} legacy entries to canonical schema:" >&2
  printf '%b' "$by_category" >&2
  echo "All synthesized via /geniro:setup; legacy fields preserved on-disk." >&2
  if [ "$truncated_skipped" -gt 0 ]; then
    echo "Skipped ${truncated_skipped} entries (>4096 bytes after migration; legacy unchanged)." >&2
  fi
  return 0
}

# Allow direct invocation: migrate-learnings.sh [--dry-run]
if [ "${BASH_SOURCE[0]}" = "${0:-}" ]; then
  migrate_legacy_learnings "$@"
  exit $?
fi
