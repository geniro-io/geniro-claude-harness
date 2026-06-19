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
#     When --score-min N is set: filters by recency × trust × access ×
#     recurrence score >= N, AND sorts result DESC by score (most relevant
#     first).
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
#  64 — query_learnings unknown flag / bad argument, OR record_access missing dedup_key
#   1 — record_access IO error

if [ -z "${_QL_DEPS_LOADED:-}" ]; then
  # Cross-shell self-location: BASH_SOURCE is bash-only — sourced under zsh it
  # is empty and the sibling `source` calls below would silently load nothing.
  # zsh names the sourced file via the %x prompt escape; eval keeps the
  # zsh-only syntax out of bash's (and ShellCheck's) parser.
  if [ -n "${BASH_SOURCE:-}" ]; then
    _ql_self="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval '_ql_self="${(%):-%x}"'
  else
    _ql_self="$0"
  fi
  _ql_script_dir="$(cd "$(dirname "$_ql_self")" && pwd)"
  # shellcheck disable=SC1091
  source "$_ql_script_dir/repo-root.sh"
  # shellcheck disable=SC1091
  source "$_ql_script_dir/score-formula.sh"
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
    # Require a single optional-dot non-negative number (e.g. 0, .5, 1.25).
    # The regex rejects the multi-dot / trailing-dot malformed forms ("0.0.1",
    # "1.") that would later make jq error out.
    if ! printf '%s' "$score_min" | grep -Eq '^[0-9]+(\.[0-9]+)?$|^\.[0-9]+$'; then
      echo "query_learnings: --score-min must be a non-negative number (got '$score_min')" >&2
      return 64
    fi
    # Normalize a leading-dot value (.5 -> 0.5): jq --argjson rejects leading-dot
    # JSON on strict builds, which the masked jq failure below would otherwise
    # surface as a silent empty result instead of correct filtering.
    case "$score_min" in
      .*) score_min="0$score_min" ;;
    esac
  fi

  if [ -n "$limit" ]; then
    # Guard before the value reaches head/tail -n; BSD and GNU reject a
    # non-integer differently, so validate here for a single clear message.
    if ! printf '%s' "$limit" | grep -Eq '^[0-9]+$'; then
      echo "query_learnings: --limit must be a non-negative integer (got '$limit')" >&2
      return 64
    fi
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

  # Pre-parse each line with `jq -Rc 'fromjson?'` so a single malformed line
  # drops instead of aborting the slurp and zeroing the whole result set.
  local result
  result=$(cat "${files[@]}" 2>/dev/null \
    | jq -Rc 'fromjson?' \
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
  # = recency_decay × trust_weight × access_weight × recurrence_weight,
  # filter by threshold, AND sort DESC by score (most relevant first). When
  # unset, behavior is unchanged — append-order with --limit applied via
  # tail (recent N).
  if [ -n "$score_min" ]; then
    local now tau
    now=$(date -u +%s)
    tau="${GENIRO_DECAY_TAU_DAYS:-$GENIRO_DECAY_TAU_DAYS_DEFAULT}"

    # Score-formula weight functions are single-sourced in lib/score-formula.sh
    # so the ranker and the archiver (archive-stale) never drift.
    local score_filter="$GENIRO_SCORE_JQ_DEFS"'
      map(
        . as $entry
        | (try (.ts // "" | fromdateiso8601) catch null) as $epoch
        | (if $epoch == null then null else ($now - $epoch) / 86400 end) as $age_days
        | (recency_decay($age_days; $tau_days)) as $rd
        | ((.trust // "inferred") | trust_weight) as $tw
        | (access_weight(.access_count // 0)) as $aw
        | (recurrence_weight(.recurrence_count // 1)) as $rw
        | $entry + {_score: ($rd * $tw * $aw * $rw)}
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
    # --limit 0 means "no results". head -n 0 / tail -n 0 differ across platforms
    # (GNU prints nothing, BSD errors), so handle 0 explicitly for portability.
    if [ "$limit" -eq 0 ]; then
      return 0
    fi
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
  # Read with default-expansion so a zero-arg call under a caller's `set -u`
  # reaches the guard below and returns rc=64 instead of crashing on an unbound $1.
  local key="${1:-}"
  if [ -z "$key" ]; then
    echo "record_access: dedup_key required" >&2
    return 64
  fi

  local root log
  root=$(_geniro_repo_root)
  log="$root/.geniro/knowledge/learnings.jsonl"

  [ -f "$log" ] || return 0

  # Take the shared knowledge-rewrite lock (the same mkdir lock the
  # auto-archive path uses) so two whole-file rewriters cannot overwrite each
  # other's changes (e.g. erase freshly-flipped deprecated flags — both
  # rewrites preserve the line count, so the count guard below cannot catch
  # rewriter-vs-rewriter races). Held lock → another rewrite is in flight; skip
  # the bump (best-effort counter). The RETURN trap releases the lock on every
  # exit path and self-clears (bash RETURN traps are not function-scoped by
  # default — without `trap - RETURN` it would linger in the caller's shell),
  # mirroring update-semantic.sh.
  local lock="$root/.geniro/knowledge/.archive-stale.lock"
  # Pre-acquire stale-lock reclaim: a SIGKILL/crash while another rewriter held
  # the lock leaves the dir behind with no trap to clear it, which would wedge
  # this counter bump for up to the TTL. Reclaim an abandoned lock whose mtime
  # age exceeds the TTL, then the mkdir below retries. The 600s TTL mirrors the
  # reclaim window in update-semantic.sh / archive-stale.sh.
  if [ -d "$lock" ]; then
    local lock_mtime
    lock_mtime=$(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock" 2>/dev/null || echo 0)
    if [ $(( $(date +%s) - lock_mtime )) -gt 600 ]; then
      rmdir "$lock" 2>/dev/null
    fi
  fi
  if ! mkdir "$lock" 2>/dev/null; then
    return 0
  fi
  trap 'rmdir "$lock" 2>/dev/null; trap - RETURN' RETURN
  # A SIGINT/SIGTERM mid-rewrite would skip the RETURN trap and orphan the lock
  # for up to the TTL. Release it on interrupt too, mirroring update-semantic.sh.
  trap 'rmdir "$lock" 2>/dev/null; rm -f "${tmp:-}" 2>/dev/null; trap - INT TERM RETURN' INT TERM

  local tmp="${log}.tmp.$$"
  # Read raw and `fromjson?` per line: a malformed line yields no output for that
  # line rather than aborting jq. The post-jq count guard below then refuses the
  # rewrite so the unparseable line is preserved (never-deletes invariant — the
  # same guarantee archive-stale.sh enforces on this same file).
  jq -Rc --arg k "$key" '
    fromjson?
    | if (.dedup_key // "") == $k then
        . + {access_count: ((.access_count // 0) + 1)}
      else
        .
      end
  ' "$log" > "$tmp" 2>/dev/null || {
    rm -f "$tmp"
    return 1
  }

  # Refuse the rewrite if `fromjson?` dropped any line (parsed count < input
  # count) — losing an audit-trail entry to bump a best-effort counter is the
  # wrong trade. awk (not grep -c) counts a final line lacking a trailing
  # newline, matching how jq -Rc reads the log.
  local raw_n parsed_n
  raw_n=$(awk 'NF{c++} END{print c+0}' "$log" 2>/dev/null || echo 0)
  parsed_n=$(awk 'NF{c++} END{print c+0}' "$tmp" 2>/dev/null || echo 0)
  if [ "$raw_n" -ne "$parsed_n" ]; then
    rm -f "$tmp"
    return 1
  fi

  # POSIX rename(2) — atomic on same filesystem. -f so an unwritable target
  # cannot prompt and hang a tty session.
  mv -f "$tmp" "$log" || {
    rm -f "$tmp"
    return 1
  }
}
