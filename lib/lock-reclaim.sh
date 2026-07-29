#!/usr/bin/env bash
# Stale-lock reclaim window — the single home of the seconds value every lock
# site in the plugin reclaims by.
#
# A lock is a mkdir/O_EXCL marker with no owner liveness check, so a SIGKILL or a
# crashed process leaves it behind forever. Each acquisition site reclaims a lock
# whose mtime is older than this window, then retries. archive-stale.sh,
# query-learnings.sh and hooks/session-start-restore.sh reclaim the SAME
# .archive-stale.lock, so the value cannot differ between them: a shorter window
# on one side reclaims a lock the other side still believes it holds.
#
# 600s (10 min) is long enough that no legitimate holder is ever reclaimed — the
# longest holder is a full learnings.jsonl rewrite, seconds of work — and short
# enough that an abandoned lock does not wedge writes for a whole session.
# GENIRO_LOCK_RECLAIM_SECS retunes every site at once.
#
# The value is SANITIZED here rather than at each call site: a non-numeric
# override makes `[ -gt ]` error and evaluate false, so an abandoned lock would
# never be reclaimed and every subsequent write would wedge behind it.
#
# Usage:
#   source "$_script_dir/lock-reclaim.sh"
#   secs="$(_geniro_lock_reclaim_secs)"
#
# hooks/ source this with an inline fallback: a vendored install ships hooks/
# without lib/, and a hook that cannot read the window must still reclaim.

_geniro_lock_reclaim_secs() {
  local secs="${GENIRO_LOCK_RECLAIM_SECS:-600}"
  case "$secs" in ''|*[!0-9]*) secs=600 ;; esac
  printf '%s' "$secs"
}
