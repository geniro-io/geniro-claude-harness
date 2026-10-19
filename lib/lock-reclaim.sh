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
# never be reclaimed and every subsequent write would wedge behind it. Two more
# shapes fall back to the default: an overlong digit string (10+ digits overflows
# the shell's arithmetic and wraps negative, so reclaim never fires), and zero
# (every lock older than a second would be "stale", stealing a live writer's).
#
# The same lock guards whole-file REWRITES of learnings.jsonl (archive-stale.sh,
# query-learnings.sh record_access). It excludes other rewriters only:
# emit_learning APPENDS without taking it, so a rewriter that reads, builds a temp
# file and renames over the log would drop an entry appended in between. Each
# rewriter therefore reads only the first N bytes it measured up front
# (_geniro_log_size), and carries any bytes the log gained past N into its temp
# file just before the rename (_geniro_log_carry_appends).
#
# Usage:
#   source "$_script_dir/lock-reclaim.sh"
#   secs="$(_geniro_lock_reclaim_secs)"
#   n="$(_geniro_log_size "$log")"        # before reading the log
#   head -c "$n" "$log" | …build "$tmp"…  # read exactly those N bytes
#   _geniro_log_carry_appends "$log" "$tmp" "$n"   # just before: mv -f "$tmp" "$log"
#
# hooks/ source this with an inline fallback: a vendored install ships hooks/
# without lib/, and a hook that cannot read the window must still reclaim.

_geniro_lock_reclaim_secs() {
  local secs="${GENIRO_LOCK_RECLAIM_SECS:-600}"
  case "$secs" in ''|*[!0-9]*|??????????*) secs=600 ;; esac
  [ "$secs" -lt 1 ] && secs=600
  printf '%s' "$secs"
}

# Byte size of <log> (digits only; empty on failure). Measured BEFORE the rewrite
# reads the log, and the read is then bounded to exactly this many bytes.
_geniro_log_size() {
  local f="${1:-}" n
  n=$(wc -c < "$f" 2>/dev/null) || return 1
  n="${n//[!0-9]/}"
  [ -n "$n" ] || return 1
  printf '%s' "$n"
}

# Append to <tmp> whatever <log> gained past its first <size> bytes — lines
# emit_learning appended while the rewrite was in flight. rc 0 on success or when
# nothing was appended; non-zero when the size is not a number or the copy fails
# (the caller then abandons the rewrite instead of renaming over the log).
_geniro_log_carry_appends() {
  local log="${1:-}" tmp="${2:-}" size="${3:-}" cur
  case "$size" in ''|*[!0-9]*) return 1 ;; esac
  cur=$(_geniro_log_size "$log") || return 1
  [ "$cur" -gt "$size" ] || return 0
  tail -c +$((size + 1)) "$log" >> "$tmp"
}
