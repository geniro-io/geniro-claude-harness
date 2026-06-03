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
  _us_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "$_us_script_dir/repo-root.sh"
  # shellcheck disable=SC1091
  source "$_us_script_dir/atomic-state-write.sh"
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

# O_EXCL-style lock acquisition. Returns 0 on acquire, non-zero if held.
_us_acquire_lock() {
  local path="$1"
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

  local rc=0
  case "$op" in
    append)
      # Route through atomic_state_append so we inherit (a) the
      # last-byte-is-newline guard against no-trailing-newline corruption,
      # (b) the POSIX-atomic append for writes ≤ PIPE_BUF, and (c) fsync.
      # atomic_state_append's own rc semantics propagate verbatim:
      # rc=68 oversized, rc=69 append IO failure.
      local ap_rc
      printf '%s' "$arg1" | atomic_state_append "$target_path"
      ap_rc=$?
      if [ "$ap_rc" -ne 0 ]; then
        rc=$ap_rc
      fi
      ;;
    replace)
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
          # Wrote rewritten content; commit atomically.
          if ! atomic_state_write "$target_path" < "$tmp"; then
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
