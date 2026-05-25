#!/usr/bin/env bash
# L2 stale-entry archival helper.
#
# Spec: skills/_shared/archive-stale.md
#
# Walks .geniro/knowledge/learnings.jsonl and flips `deprecated: true`
# on entries matching all three criteria simultaneously:
#   - score < 0.1 (same scoring formula as query-learnings --score-min)
#   - age > 180 days
#   - access_count == 0 (never queried)
#
# NEVER deletes — flips deprecated:true only, audit trail preserved.
# NEVER auto-runs — invoked explicitly by user OR surfaced as notice
# in SessionStart Block 5e. Idempotent: already-deprecated entries
# skipped.
#
# API:
#   archive_stale_learnings [--dry-run]
#   → flips deprecated:true on stale entries (or reports without writing).
#
# Exit codes:
#   0 — success (flipped or no-op)
#   1 — no entries match criteria (informational)
#   2 — IO error

if [ -z "${_AS_DEPS_LOADED:-}" ]; then
  _as_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "$_as_script_dir/repo-root.sh"
  _AS_DEPS_LOADED=1
fi

archive_stale_learnings() {
  local dry_run=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      *)
        echo "archive_stale_learnings: unknown flag '$1'" >&2
        return 2
        ;;
    esac
  done

  local root log
  root=$(_geniro_repo_root)
  log="$root/.geniro/knowledge/learnings.jsonl"

  if [ ! -f "$log" ] || [ ! -s "$log" ]; then
    echo "archive-stale: no learnings.jsonl found (nothing to archive)" >&2
    return 1
  fi

  local now tau
  now=$(date -u +%s)
  tau="${GENIRO_DECAY_TAU_DAYS:-90}"

  # Compute score per entry, identify stale candidates, optionally write.
  # Stale criterion AND-ed: score < 0.1 AND age > 180d AND access_count == 0
  # AND not-already-deprecated. Reports per-type breakdown to stderr.
  local stale_filter='
    def recency_decay($age_days; $tau):
      if $age_days == null then 0.5
      else (- ($age_days / $tau)) | exp end;
    def trust_weight:
      if . == "verified" then 1.0
      elif . == "retrieved" then 0.66
      else 0.33
      end;
    def access_weight($n):
      1.0 + (($n + 1) | log10);

    . as $entry
    | (try (.ts // "" | fromdateiso8601) catch null) as $epoch
    | (if $epoch == null then null else ($now - $epoch) / 86400 end) as $age_days
    | (recency_decay($age_days; $tau_days)) as $rd
    | ((.trust // "inferred") | trust_weight) as $tw
    | (access_weight(.access_count // 0)) as $aw
    | ($rd * $tw * $aw) as $score
    | ((.deprecated // false) == false
       and $score < 0.1
       and ($age_days != null and $age_days > 180)
       and ((.access_count // 0) == 0)) as $is_stale
    | if $is_stale then
        if $dry then $entry else $entry + {deprecated: true} end
      else
        $entry
      end
    | . + {_is_stale: $is_stale}
  '

  local processed
  processed=$(jq -c \
      --argjson now "$now" \
      --argjson tau_days "$tau" \
      --argjson dry "$dry_run" \
      "$stale_filter" "$log" 2>/dev/null) || {
    echo "archive-stale: jq failed processing $log" >&2
    return 2
  }

  # Count stale entries (and per-type breakdown for the report).
  local stale_count
  stale_count=$(printf '%s\n' "$processed" | jq -s '[.[] | select(._is_stale)] | length')
  if [ "$stale_count" -eq 0 ]; then
    echo "archive-stale: 0 stale candidates (no entries match score<0.1 + age>180d + access_count==0)" >&2
    return 1
  fi

  local by_type
  by_type=$(printf '%s\n' "$processed" \
    | jq -sr '[.[] | select(._is_stale) | (.type // "untyped")]
              | group_by(.) | map({type: .[0], count: length})
              | .[] | "  \(.type): \(.count)"')

  if [ "$dry_run" = "true" ]; then
    echo "archive-stale: $stale_count stale candidate(s) (dry-run — no changes written):" >&2
    printf '%s\n' "$by_type" >&2
    echo "" >&2
    echo "Run without --dry-run to flip deprecated:true on these entries." >&2
    return 0
  fi

  # Real run: write processed content back (with _is_stale stripped).
  local tmp="${log}.tmp.$$"
  printf '%s\n' "$processed" | jq -c 'del(._is_stale)' > "$tmp" 2>/dev/null || {
    rm -f "$tmp"
    echo "archive-stale: failed to prepare new log content" >&2
    return 2
  }

  # POSIX rename(2) — atomic on same filesystem.
  mv "$tmp" "$log" || {
    rm -f "$tmp"
    echo "archive-stale: failed to rename tmp to $log" >&2
    return 2
  }

  echo "archive-stale: flipped deprecated:true on $stale_count entries:" >&2
  printf '%s\n' "$by_type" >&2
  echo "" >&2
  echo "All entries preserved on-disk (audit trail). Re-run safe (idempotent — already-deprecated entries skipped)." >&2
  return 0
}

# Allow direct invocation: archive-stale.sh [--dry-run]
if [ "${BASH_SOURCE[0]}" = "${0:-}" ]; then
  archive_stale_learnings "$@"
  exit $?
fi
