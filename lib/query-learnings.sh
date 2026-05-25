#!/usr/bin/env bash
# L2 episodic-memory read helper.
#
# Spec: skills/_shared/query-learnings.md
#
# API:
#   query_learnings [--type T] [--tag T] [--scope S] [--min-trust LEVEL]
#                   [--score-min N] [--include-superseded]
#                   [--include-deprecated] [--include-archive] [--limit N]
#   → emits matching JSONL entries to stdout, one per line.
#     When --score-min N is set: filters by recency × trust × access score
#     >= N, AND sorts result DESC by score (most relevant first).
#
#   record_access <dedup_key>
#   → in-place increment access_count of entry matching dedup_key. Used
#     by callers that want to feed access_weight signal into future
#     --score-min queries. Best-effort, no lock — concurrent misses are
#     acceptable (counter, not ledger).
#
# Exit codes:
#   0 — query ran (may have zero matches), or record_access succeeded /
#       no-op (no log file, no matching entry)
#  64 — unknown flag / bad argument
#   1 — record_access IO error

if [ -z "${_QL_DEPS_LOADED:-}" ]; then
  _ql_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "$_ql_script_dir/repo-root.sh"
  _QL_DEPS_LOADED=1
fi

query_learnings() {
  local type_filter=""
  local tag_filter=""
  local scope_filter=""
  local min_trust=""
  local score_min=""
  local include_superseded=false
  local include_deprecated=false
  local include_archive=false
  local limit=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --type)               type_filter="$2"; shift 2 ;;
      --tag)                tag_filter="$2"; shift 2 ;;
      --scope)              scope_filter="$2"; shift 2 ;;
      --min-trust)          min_trust="$2"; shift 2 ;;
      --score-min)          score_min="$2"; shift 2 ;;
      --include-superseded) include_superseded=true; shift ;;
      --include-deprecated) include_deprecated=true; shift ;;
      --include-archive)    include_archive=true; shift ;;
      --limit)              limit="$2"; shift 2 ;;
      *)
        echo "query_learnings: unknown flag '$1'" >&2
        return 64
        ;;
    esac
  done

  case "$min_trust" in
    ""|verified|retrieved|inferred) ;;
    *)
      echo "query_learnings: --min-trust must be verified|retrieved|inferred (got '$min_trust')" >&2
      return 64
      ;;
  esac

  if [ -n "$score_min" ]; then
    case "$score_min" in
      ''|*[!0-9.]*)
        echo "query_learnings: --score-min must be a non-negative number (got '$score_min')" >&2
        return 64
        ;;
    esac
  fi

  local root log
  root=$(_geniro_repo_root)
  log="$root/.geniro/knowledge/learnings.jsonl"

  # Build the source stream: main log + optionally archive files.
  # We slurp everything via cat → jq -s so the supersede filter sees the
  # whole set at once (it needs to know which dedup_keys are superseded
  # by SOMEONE in the input).
  local files=()
  if [ -f "$log" ] && [ -s "$log" ]; then
    files+=("$log")
  fi
  if [ "$include_archive" = "true" ]; then
    local archive_dir="$root/.geniro/knowledge/archive"
    if [ -d "$archive_dir" ]; then
      while IFS= read -r -d '' f; do
        files+=("$f")
      done < <(find "$archive_dir" -type f -name 'learnings-*.jsonl' -print0 2>/dev/null)
    fi
  fi

  if [ "${#files[@]}" -eq 0 ]; then
    return 0
  fi

  # Build the jq predicate.
  # Supersede filter is POSITION-AWARE: entry X is superseded iff some LATER
  # entry Y (higher file-position) has Y.supersedes == X.dedup_key. A naive
  # set-membership filter would exclude the NEWEST entry too whenever
  # emit_learning auto-injects supersedes=<dedup_key> on a self-collision
  # (auto-computed dedup_key is content-insensitive, so two entries with the
  # same producer/scope/normalized-summary collide).
  local jq_filter='
    def trust_allowed($min):
      if $min == "verified" then ["verified"]
      elif $min == "retrieved" then ["verified", "retrieved"]
      elif $min == "inferred" then ["verified", "retrieved", "inferred"]
      else null
      end;

    def matches_filters:
      (if $type_filter == "" then true else (.type // "") == $type_filter end) and
      (if $tag_filter == "" then true else ((.tags // []) | index($tag_filter)) != null end) and
      (if $scope_filter == "" then true else (.scope // "") == $scope_filter end) and
      (if $deprecated_ok then true else (.deprecated // false) == false end) and
      (if $min_trust == "" then true
       else (trust_allowed($min_trust) // []) as $allowed |
            ((.trust // "inferred") | IN($allowed[]))
       end);

    . as $all
    | [range(0; length) as $i
       | $all[$i] as $cur
       | $cur + {
           _superseded: (
             [$all[($i + 1):][] | .supersedes? // empty]
             | index($cur.dedup_key // null) != null
           )
         }]
    | map(select(matches_filters))
    | (if $include_superseded then .
       else map(select(._superseded | not))
       end)
    | map(del(._superseded))
    | .[]
  '

  local result
  result=$(cat "${files[@]}" 2>/dev/null \
    | jq -cs \
        --arg type_filter "$type_filter" \
        --arg tag_filter "$tag_filter" \
        --arg scope_filter "$scope_filter" \
        --arg min_trust "$min_trust" \
        --argjson include_superseded "$include_superseded" \
        --argjson deprecated_ok "$include_deprecated" \
        "$jq_filter" 2>/dev/null) || return 0

  if [ -z "$result" ]; then
    return 0
  fi

  # Scoring pass: when --score-min is set, compute per-entry score
  # = recency_decay × trust_weight × access_weight, filter by threshold,
  # AND sort DESC by score (most relevant first). When unset, behavior is
  # unchanged — append-order with --limit applied via tail (recent N).
  if [ -n "$score_min" ]; then
    local now tau
    now=$(date -u +%s)
    tau="${GENIRO_DECAY_TAU_DAYS:-90}"

    local score_filter='
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

      map(
        . as $entry
        | (try (.ts // "" | fromdateiso8601) catch null) as $epoch
        | (if $epoch == null then null else ($now - $epoch) / 86400 end) as $age_days
        | (recency_decay($age_days; $tau_days)) as $rd
        | ((.trust // "inferred") | trust_weight) as $tw
        | (access_weight(.access_count // 0)) as $aw
        | $entry + {_score: ($rd * $tw * $aw)}
      )
      | map(select(._score >= $smin))
      | sort_by(._score) | reverse
      | map(del(._score))
      | .[]
    '

    result=$(printf '%s\n' "$result" \
      | jq -cs \
          --argjson now "$now" \
          --argjson tau_days "$tau" \
          --argjson smin "$score_min" \
          "$score_filter" 2>/dev/null) || return 0

    if [ -z "$result" ]; then
      return 0
    fi
  fi

  if [ -n "$limit" ]; then
    if [ -n "$score_min" ]; then
      # Score-sorted result: top N (head), since order is DESC by score.
      printf '%s\n' "$result" | head -n "$limit"
    else
      # Append-order result: most-recent N (tail), original behavior.
      printf '%s\n' "$result" | tail -n "$limit"
    fi
  else
    printf '%s\n' "$result"
  fi
}

# Increment access_count of entry matching dedup_key. Best-effort,
# no lock. Concurrent misses acceptable — access_count is a ranking signal,
# not a ledger. Returns 0 on success or no-op (no log, no match), 1 on
# write error.
record_access() {
  local key="$1"
  if [ -z "$key" ]; then
    echo "record_access: dedup_key required" >&2
    return 64
  fi

  local root log
  root=$(_geniro_repo_root)
  log="$root/.geniro/knowledge/learnings.jsonl"

  [ -f "$log" ] || return 0

  local tmp="${log}.tmp.$$"
  jq -c --arg k "$key" '
    if (.dedup_key // "") == $k then
      . + {access_count: ((.access_count // 0) + 1)}
    else
      .
    end
  ' "$log" > "$tmp" 2>/dev/null || {
    rm -f "$tmp"
    return 1
  }

  # POSIX rename(2) — atomic on same filesystem.
  mv "$tmp" "$log" || {
    rm -f "$tmp"
    return 1
  }
}
