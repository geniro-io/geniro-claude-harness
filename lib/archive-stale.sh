#!/usr/bin/env bash
# L2 stale-entry archival helper.
#
# Spec: skills/_shared/archive-stale.md
#
# Walks .geniro/knowledge/learnings.jsonl and flips `deprecated: true`
# on entries matching all four criteria simultaneously:
#   - score < 0.1 (recency_decay × trust_weight × access_weight ×
#       recurrence_weight — same scoring formula as query-learnings --score-min)
#   - age > 180 days
#   - access_count == 0 (never queried)
#   - not already deprecated ((.deprecated // false) == false)
#
# NEVER deletes — flips deprecated:true only, audit trail preserved.
# Auto-runs on SessionStart (default ON, hash-gated, opt-out via
# safety.json memory.auto_archive_stale: false). Locking: the SessionStart
# hook acquires the mkdir-lock around its invocation, so the FUNCTION never
# auto-locks; the direct-invocation branch at the bottom of this file takes
# the same lock itself (rc=3 when held), so manual runs cannot interleave
# with the hook or with record_access counter rewrites of the same log.
# Idempotent: already-deprecated entries skipped.
#
# API:
#   archive_stale_learnings [--dry-run]
#   → flips deprecated:true on stale entries (or reports without writing).
#
# Exit codes:
#   0 — success (flipped or no-op)
#   1 — no entries match criteria (informational)
#   2 — IO error
#   3 — direct invocation only: rewrite lock held by another process; skipped

if [ -z "${_AS_DEPS_LOADED:-}" ]; then
  # Cross-shell self-location: BASH_SOURCE is bash-only — sourced under zsh it
  # is empty and the sibling `source` calls below would silently load nothing.
  # zsh names the sourced file via the %x prompt escape; eval keeps the
  # zsh-only syntax out of bash's (and ShellCheck's) parser.
  if [ -n "${BASH_SOURCE:-}" ]; then
    _as_self="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval '_as_self="${(%):-%x}"'
  else
    _as_self="$0"
  fi
  _as_script_dir="$(cd "$(dirname "$_as_self")" && pwd)"
  # shellcheck disable=SC1091
  source "$_as_script_dir/repo-root.sh"
  # shellcheck disable=SC1091
  source "$_as_script_dir/score-formula.sh"
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
  tau="${GENIRO_DECAY_TAU_DAYS:-$GENIRO_DECAY_TAU_DAYS_DEFAULT}"
  # Validate tau up front — a non-numeric value otherwise reaches `--argjson`
  # below and surfaces only as an opaque "jq failed" error.
  if ! printf '%s' "$tau" | grep -Eq '^([0-9]+(\.[0-9]+)?|\.[0-9]+)$'; then
    echo "archive-stale: GENIRO_DECAY_TAU_DAYS must be a non-negative number (got '$tau')" >&2
    return 2
  fi

  # Compute score per entry, identify stale candidates, optionally write.
  # Stale criterion AND-ed: score < 0.1 AND age > 180d AND access_count == 0
  # AND not-already-deprecated. Reports per-type breakdown to stderr.
  # Score-formula weight functions are single-sourced in lib/score-formula.sh so
  # the archiver and the ranker (query-learnings --score-min) never drift — a
  # divergence would make archival reap entries the ranker would still surface.
  local stale_filter="$GENIRO_SCORE_JQ_DEFS"'
    fromjson?
    | . as $entry
    | (try (.ts // "" | fromdateiso8601) catch null) as $epoch
    | (if $epoch == null then null else ($now - $epoch) / 86400 end) as $age_days
    | (recency_decay($age_days; $tau_days)) as $rd
    | ((.trust // "inferred") | trust_weight) as $tw
    | (access_weight(.access_count // 0)) as $aw
    | (recurrence_weight(.recurrence_count // 1)) as $rw
    | ($rd * $tw * $aw * $rw) as $score
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
  processed=$(jq -Rc \
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
  # Guard the count before the arithmetic test — an empty/non-numeric value (jq
  # absent or erroring) otherwise crashes `[ -eq ]` with an opaque "integer
  # expected" instead of a clean failure (mirrors the tau validation above).
  if ! printf '%s' "$stale_count" | grep -Eq '^[0-9]+$'; then
    echo "archive-stale: jq failed counting stale entries in $log" >&2
    return 2
  fi

  # Verification-coverage line: the fraction of the live (non-deprecated) L2
  # corpus whose trust is `verified`, surfaced read-only for the human. Computed
  # over the PRE-FLIP on-disk $log — NOT the post-flip $processed stream — so the
  # number is identical dry-run vs real-run on the same corpus and represents
  # "current live coverage before this run's archiving". (A real run merges
  # {deprecated: true} onto the just-flipped stale entries in $processed, which
  # would otherwise shrink the live denominator vs the dry-run report.) So this
  # line is the pre-archive live-set coverage, identical dry-run vs real-run for
  # THIS helper. hooks/session-start-restore.sh computes its own coverage
  # independently off the on-disk file at hook time (which, after a real
  # archiving session, is the post-flip set), so the two are not guaranteed to
  # report the identical number. Prints before the stale_count==0 early-return, so the number surfaces
  # whether or not anything was archived. Absent trust folds into `inferred`
  # ((.trust // "inferred")) to match the score-formula and query-learnings
  # normalization — there is no phantom "absent" bucket. n/a guards the
  # zero-live divide-by-zero.
  local coverage_line
  coverage_line=$(jq -Rsr '
        [splits("\n") | select(length > 0) | fromjson?
         | select((.deprecated // false) == false)] as $live
        | ($live | length) as $total
        | ([$live[] | select((.trust // "inferred") == "verified")] | length) as $verified
        | if $total == 0 then "coverage: n/a"
          else "coverage: verified \($verified)/\($total) (\(($verified * 100 / $total) | round)%)"
          end' "$log" 2>/dev/null)
  [ -z "$coverage_line" ] && coverage_line="coverage: n/a"

  if [ "$stale_count" -eq 0 ]; then
    echo "archive-stale: 0 stale candidates (no entries match score<0.1 + age>180d + access_count==0)" >&2
    echo "archive-stale: $coverage_line" >&2
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
    echo "archive-stale: $coverage_line" >&2
    echo "" >&2
    echo "Run without --dry-run to flip deprecated:true on these entries." >&2
    return 0
  fi

  # Guard the destructive rewrite: jq's `fromjson?` silently DROPS any line it
  # cannot parse, so a malformed line would vanish from the rewritten log —
  # violating the never-deletes / audit-trail-preserved invariant. Refuse the
  # rewrite when the parsed-object count differs from the non-blank input lines.
  local raw_lines parsed_lines
  # Count non-blank records the way jq -Rc reads them: awk processes a final line
  # even without a trailing newline (grep -c does not), so a valid log that simply
  # lacks a trailing \n is not mistaken for a corrupt one.
  raw_lines=$(awk 'NF{c++} END{print c+0}' "$log" 2>/dev/null || echo 0)
  if [ -z "$processed" ]; then
    parsed_lines=0
  else
    parsed_lines=$(printf '%s\n' "$processed" | jq -s 'length' 2>/dev/null || echo 0)
  fi
  if [ "$raw_lines" -ne "$parsed_lines" ]; then
    echo "archive-stale: $((raw_lines - parsed_lines)) malformed line(s) in $log — refusing to rewrite (would lose the audit trail). Fix or remove the malformed entries, then re-run." >&2
    return 2
  fi

  # Real run: write processed content back (with _is_stale stripped).
  local tmp="${log}.tmp.$$"
  printf '%s\n' "$processed" | jq -c 'del(._is_stale)' > "$tmp" 2>/dev/null || {
    rm -f "$tmp"
    echo "archive-stale: failed to prepare new log content" >&2
    return 2
  }

  # POSIX rename(2) — atomic on same filesystem. -f so an unwritable target
  # cannot prompt and hang a tty session.
  mv -f "$tmp" "$log" || {
    rm -f "$tmp"
    echo "archive-stale: failed to rename tmp to $log" >&2
    return 2
  }

  echo "archive-stale: flipped deprecated:true on $stale_count entries:" >&2
  printf '%s\n' "$by_type" >&2
  echo "archive-stale: $coverage_line" >&2
  echo "" >&2
  echo "All entries preserved on-disk (audit trail). Re-run safe (idempotent — already-deprecated entries skipped)." >&2
  return 0
}

# Allow direct invocation: archive-stale.sh [--dry-run]
# bash: executed ⇔ BASH_SOURCE[0] == $0. zsh: sourcing appends ":file" to
# ZSH_EVAL_CONTEXT; direct execution leaves it "toplevel" (the bash test
# would mis-read both zsh cases as sourced, since BASH_SOURCE is empty there).
_as_direct=0
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-toplevel}" in *:file*) ;; *) _as_direct=1 ;; esac
elif [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  _as_direct=1
fi
if [ "$_as_direct" = "1" ]; then
  # Direct runs take the same mkdir lock the SessionStart hook holds around its
  # invocation (and that record_access takes for its counter rewrite), so a
  # manual run cannot interleave with another rewrite of the same log. Held
  # lock → another writer is active; skip with rc=3 rather than queue. Stale
  # locks (>10 min, crashed process) are reclaimed, mirroring the hook.
  # The hook itself invokes this file as a script while ALREADY holding the
  # lock — it sets GENIRO_ARCHIVE_LOCK_HELD=1 to say "caller owns the lock",
  # which skips acquisition here.
  _as_lock_root="$(_geniro_repo_root)"
  _as_lock="$_as_lock_root/.geniro/knowledge/.archive-stale.lock"
  if [ -d "$_as_lock_root/.geniro/knowledge" ] && [ -z "${GENIRO_ARCHIVE_LOCK_HELD:-}" ]; then
    if [ -d "$_as_lock" ]; then
      _as_lock_mtime=$(stat -c %Y "$_as_lock" 2>/dev/null || stat -f %m "$_as_lock" 2>/dev/null || echo 0)
      # Shared reclaim window — override via GENIRO_LOCK_RECLAIM_SECS (default 600s);
      # archive-stale.sh + query-learnings.sh reclaim the SAME lock and must agree.
      # Sanitized before the integer test: a non-numeric override makes `[ -gt ]`
      # error and evaluate false, so an abandoned lock is never reclaimed and every
      # subsequent write wedges. Same guard the numeric knobs elsewhere carry.
      _as_reclaim_secs="${GENIRO_LOCK_RECLAIM_SECS:-600}"
      case "$_as_reclaim_secs" in ''|*[!0-9]*) _as_reclaim_secs=600 ;; esac
      if [ $(( $(date +%s) - _as_lock_mtime )) -gt "$_as_reclaim_secs" ]; then
        rmdir "$_as_lock" 2>/dev/null
      fi
    fi
    if ! mkdir "$_as_lock" 2>/dev/null; then
      echo "archive-stale: another rewrite of learnings.jsonl is in progress (lock held: $_as_lock) — skipped. Re-run in a moment." >&2
      exit 3
    fi
    trap 'rmdir "$_as_lock" 2>/dev/null' EXIT
  fi
  archive_stale_learnings "$@"
  exit $?
fi
