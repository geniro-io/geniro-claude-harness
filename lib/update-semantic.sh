#!/usr/bin/env bash
# L3 semantic-memory write helper.
#
# Spec: skills/_shared/update-semantic.md
# Bounded auto-incremental writes: ARCHITECTURE.md §Memory Layers
#
# API:
#   update_semantic --file <codebase-map|features> --append "<line>"
#   update_semantic --file <codebase-map|features> --replace "<prefix>" "<new-line>"
#
# Behavior:
#   - Lock-guarded via O_EXCL create of a per-file lock file under
#     .geniro/planning/. Caller gets rc=11 (EAGAIN-shaped) if lock is held
#     and must decide to retry / defer.
#   - Append: appends the line as-is to the target .md file (creates the
#     file if missing).
#   - Replace: finds the first line whose CONTENT starts with the given
#     prefix; replaces that whole line. No-op on non-existent files; no-op
#     on no-match (signaled via stderr, not error).

if [ -z "${_US_DEPS_LOADED:-}" ]; then
  # Cross-shell self-location: BASH_SOURCE is bash-only — sourced under zsh it
  # is empty and the sibling `source` calls below would silently load nothing.
  # zsh names the sourced file via the %x prompt escape; eval keeps the
  # zsh-only syntax out of bash's (and ShellCheck's) parser.
  if [ -n "${BASH_SOURCE:-}" ]; then
    _us_self="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval '_us_self="${(%):-%x}"'
  else
    _us_self="$0"
  fi
  _us_script_dir="$(cd "$(dirname "$_us_self")" && pwd)"
  # shellcheck disable=SC1091
  source "$_us_script_dir/repo-root.sh"
  # shellcheck disable=SC1091
  source "$_us_script_dir/atomic-state-write.sh"
  # shellcheck disable=SC1091
  source "$_us_script_dir/redact-secrets.sh"
  # shellcheck disable=SC1091
  source "$_us_script_dir/lock-reclaim.sh"
  _US_DEPS_LOADED=1
fi

_US_LOCK_HELD=11

# Map --file flag to (basename, lock-name).
_us_resolve_target() {
  case "$1" in
    codebase-map) printf '_CODEBASE_MAP.md\t.codebase-map.lock' ;;
    features)     printf '_FEATURES.md\t.features.lock' ;;
    *) return 1 ;;
  esac
}

# Stale-lock window: a lock older than this (seconds) is presumed abandoned by a
# crashed/killed holder and reclaimed. Value, rationale and sanitation live in
# lib/lock-reclaim.sh, which every lock site in the plugin reads.
_US_STALE_LOCK_SECS="$(_geniro_lock_reclaim_secs)"

# O_EXCL-style lock acquisition. Returns 0 on acquire, non-zero if held.
# Before acquiring, reclaim a stale lock whose mtime is older than the stale
# window — a SIGKILL/crash while holding the lock leaves the file behind with no
# RETURN trap to clear it, which would wedge every future L3 write at rc=11
# forever. The reclaim removes the abandoned lock, then the O_EXCL create retries.
_us_acquire_lock() {
  local path="$1"
  if [ -f "$path" ]; then
    local lock_mtime now
    lock_mtime=$(stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ $(( now - lock_mtime )) -gt "$_US_STALE_LOCK_SECS" ]; then
      rm -f "$path" 2>/dev/null
    fi
  fi
  # `set -C` (noclobber) makes `:>` fail if the file exists.
  (set -C; : > "$path") 2>/dev/null
}

update_semantic() {
  local target_file=""
  local op=""
  local arg1=""
  local arg2=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --file)
        # Require the operand (same trailing-flag spin guard as --append below).
        if [ "$#" -lt 2 ]; then
          echo "update_semantic: --file requires <codebase-map|features>" >&2
          return 64
        fi
        target_file="$2"
        shift 2
        ;;
      --append)
        if [ -n "$op" ]; then
          echo "update_semantic: --append and --replace are mutually exclusive" >&2
          return 64
        fi
        # Require the operand; a bare trailing `--append` makes `shift 2` fail to
        # consume $1, so the while-loop spins on --append forever.
        if [ "$#" -lt 2 ]; then
          echo "update_semantic: --append requires <line>" >&2
          return 64
        fi
        op="append"
        arg1="$2"
        shift 2
        ;;
      --replace)
        if [ -n "$op" ]; then
          echo "update_semantic: --append and --replace are mutually exclusive" >&2
          return 64
        fi
        # Require both operands; without this guard a `--replace` missing an
        # operand makes `shift 3` fail to consume $1, and the while-loop spins on
        # --replace forever.
        if [ "$#" -lt 3 ]; then
          echo "update_semantic: --replace requires <old> <new>" >&2
          return 64
        fi
        op="replace"
        arg1="$2"
        arg2="$3"
        shift 3
        ;;
      *)
        echo "update_semantic: unknown flag '$1'" >&2
        return 64
        ;;
    esac
  done

  if [ -z "$target_file" ]; then
    echo "update_semantic: --file <codebase-map|features> required" >&2
    return 64
  fi
  if [ -z "$op" ]; then
    echo "update_semantic: --append or --replace required" >&2
    return 64
  fi

  local resolved
  if ! resolved=$(_us_resolve_target "$target_file"); then
    echo "update_semantic: --file must be 'codebase-map' or 'features' (got '$target_file')" >&2
    return 64
  fi
  local target_md lock_name
  target_md="${resolved%%$'\t'*}"
  lock_name="${resolved##*$'\t'}"

  local root planning target_path lock_path
  root=$(_geniro_repo_root)
  planning="$root/.geniro/planning"
  target_path="$planning/$target_md"
  lock_path="$planning/$lock_name"

  mkdir -p "$planning"

  if ! _us_acquire_lock "$lock_path"; then
    echo "update_semantic: lock $lock_name held by another process; defer this write to skill completion or retry" >&2
    return "$_US_LOCK_HELD"
  fi

  # Release the lock on every function-return path (normal or early-error return)
  # so a stale O_EXCL lock can't wedge all future L3 writes. Bash RETURN traps
  # are NOT function-scoped by default — the trap self-clears (`trap - RETURN`)
  # on first fire so it cannot linger in the caller's shell and clobber a
  # caller's own RETURN trap.
  trap 'rm -f "$lock_path"; trap - RETURN' RETURN

  # A SIGINT/SIGTERM mid-write would skip the RETURN trap and leave the lock (and
  # any in-flight mktemp) behind. Clean both on interrupt so the next write isn't
  # wedged at rc=11. _us_inflight_tmp is set when the replace branch creates its
  # temp file; empty otherwise. Split by signal and exit explicitly — cleanup
  # alone does not terminate the process, so without the exit bash would resume
  # mid-write with the lock already released for a concurrent writer.
  local _us_inflight_tmp=""
  trap 'rm -f "$lock_path" ${_us_inflight_tmp:+"$_us_inflight_tmp"}; trap - INT TERM RETURN; exit 130' INT
  trap 'rm -f "$lock_path" ${_us_inflight_tmp:+"$_us_inflight_tmp"}; trap - INT TERM RETURN; exit 143' TERM

  local rc=0
  case "$op" in
    append)
      # Redact-before-store: the line persists in the L3 snapshot, so pass it
      # through the shared secret redaction first — the same pipeline
      # emit-learning applies to every L2 field before it reaches disk.
      arg1=$(printf '%s' "$arg1" | redact_secrets "update_semantic" "append:$target_md" "")
      # Route through atomic_state_append so we inherit (a) the
      # last-byte-is-newline guard against no-trailing-newline corruption,
      # (b) the POSIX-atomic append for writes ≤ PIPE_BUF, and (c) fsync.
      # atomic_state_append's own rc semantics propagate verbatim:
      # rc=68 oversized, rc=69 append IO failure, rc=70 nothing to append
      # (redact_secrets returned empty — a silent 0 there would report a
      # snapshot update that never reached disk).
      local ap_rc
      printf '%s' "$arg1" | atomic_state_append "$target_path"
      ap_rc=$?
      if [ "$ap_rc" -ne 0 ]; then
        rc=$ap_rc
      fi
      ;;
    replace)
      # Redact the replacement value before it reaches disk (the match prefix
      # stays verbatim — redacting it would change what it matches).
      arg2=$(printf '%s' "$arg2" | redact_secrets "update_semantic" "replace:$target_md" "")
      if [ ! -f "$target_path" ]; then
        # No file → no-op (replace can't match anything).
        rc=0
      else
        local tmp rewritten
        tmp=$(mktemp) || {
          rm -f "$lock_path"
          echo "update_semantic: mktemp failed" >&2
          return 71
        }
        _us_inflight_tmp="$tmp"
        # END exits 3 (not awk's own fatal-error code 2) for a clean no-match,
        # so a genuine awk runtime failure is not mistaken for "nothing matched".
        rewritten=$(awk -v p="$arg1" -v r="$arg2" '
          BEGIN { replaced = 0 }
          {
            if (!replaced && index($0, p) == 1) {
              print r
              replaced = 1
            } else {
              print
            }
          }
          END { exit (replaced ? 0 : 3) }
        ' "$target_path" > "$tmp"; echo $?)
        local awk_rc="$rewritten"
        if [ "$awk_rc" -eq 0 ]; then
          # Commit the rewrite.
          #
          # Deliberate carve-out from atomic_state_write (CLAUDE.md §State
          # Files): the INT/TERM traps set above (:181-182) are keyed to
          # THIS function's $lock_path and $_us_inflight_tmp and exit
          # directly. atomic_state_write installs its own INT/TERM trap on
          # entry — traps are process-global, not function-scoped — and its
          # handler also exits directly, which would override ours mid-write
          # and then clear back to default disposition on return
          # (the `trap - INT TERM` on each of atomic_state_write's return paths), leaving
          # $lock_path signal-unprotected for the remainder of this
          # function. A signal landing in that window orphans the lock for
          # the reclaim TTL. archive-stale.sh:220-232 and
          # query-learnings.sh:330-340 carve out of the helper for this
          # exact collision; this mirrors their shape. $tmp already holds
          # the finished content (the awk write above), so the commit is a
          # plain atomic rename — no second tmp file is needed. Only
          # power-loss durability in the narrow post-rename window is
          # traded away, same as the two sibling carve-outs.
          if ! mv -f "$tmp" "$target_path"; then
            rc=71
            echo "update_semantic: atomic write of replacement failed" >&2
          fi
        elif [ "$awk_rc" -eq 3 ]; then
          # No match — content unchanged. Surface a notice but don't error.
          echo "update_semantic: --replace prefix '$arg1' did not match any line in $target_md (no-op)" >&2
        else
          # awk itself failed — do NOT commit the (possibly partial) tmp and do
          # NOT mistake the failure for a clean no-match.
          rc=70
          echo "update_semantic: awk failed during replace (rc=$awk_rc)" >&2
        fi
        rm -f "$tmp"
      fi
      ;;
  esac

  rm -f "$lock_path"
  return "$rc"
}
