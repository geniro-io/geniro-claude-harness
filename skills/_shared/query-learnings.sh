#!/usr/bin/env bash
# L2 episodic-memory read helper.
#
# Spec: skills/_shared/query-learnings.md
# Read pipeline: architecture/M2-memory-layers.md §5.2 (read side)
# Trust filter: architecture/M2-memory-layers.md §5.1 + §5.3
#
# API:
#   query_learnings [--type T] [--tag T] [--scope S] [--min-trust LEVEL]
#                   [--include-superseded] [--include-deprecated]
#                   [--include-archive] [--limit N]
#   → emits matching JSONL entries to stdout, one per line.
#
# Exit codes:
#   0 — query ran (may have zero matches)
#  64 — unknown flag / bad argument

_ql_repo_root() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    echo "$PWD"
  fi
}

query_learnings() {
  local type_filter=""
  local tag_filter=""
  local scope_filter=""
  local min_trust=""
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

  local root log
  root=$(_ql_repo_root)
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
    | ($all | map(.supersedes? // empty) | map(select(. != "")) | unique) as $superseded
    | $all
    | map(select(matches_filters))
    | (if $include_superseded then .
       else map(select((.dedup_key as $k | $superseded | index($k)) == null))
       end)
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

  if [ -n "$limit" ]; then
    printf '%s\n' "$result" | tail -n "$limit"
  else
    printf '%s\n' "$result"
  fi
}
