#!/usr/bin/env bash
# Atomic state-file write helpers.
#
# Spec: skills/_shared/atomic-state-write.md
# Tier model: skills/_shared/state-tier-spec.md
# Design rationale: ARCHITECTURE.md §State Files
#
# Source this file from a skill's Bash invocation:
#   source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
#   atomic_state_write <target-path> <<'CONTENT'
#   ...
#   CONTENT
#
# Functions exported:
#   atomic_state_write <target>   — tmp + fsync + rename + fsync-dir (T1 / T2 / T3 CRUD)
#   atomic_state_append <target>  — POSIX O_APPEND for ≤4KB lines (T3 append-only / JSONL)

# Single source for the append/JSONL byte ceiling: PIPE_BUF (4096 on Linux, 512 on
# macOS) minus 2 bytes for the newline framing the append adds. emit-learning.sh sources
# this file and reuses GENIRO_APPEND_MAX_BYTES, so the two enforcers never drift.
: "${GENIRO_APPEND_MAX_BYTES:=4094}"

# Per-file sync fallback: GNU `sync -d <path>` works on Linux; macOS lacks -d.
# Probe once; reuse decision via a function.
_atomic_state_sync_file() {
  if sync -d "$1" 2>/dev/null; then
    return 0
  fi
  # Fallback: whole-disk sync. Slower but portable.
  sync
}

atomic_state_write() {
  local target="${1:-}"   # default so a zero-arg call under `set -u` reaches the guard
  if [ -z "$target" ]; then
    echo "atomic_state_write: target path required" >&2
    return 64
  fi

  # PID + hostname suffix prevents collision on NFS-shared .geniro/.
  # Sanitize: hostnames with `/`, spaces, or other path-breaking chars
  # (legal per POSIX, observed in some k8s/container envs) would create a
  # tmp path that `cat > "$tmp"` can't write to. Replace anything outside
  # [A-Za-z0-9.-] with `_`.
  local host="${HOSTNAME:-localhost}"
  host="${host//[^A-Za-z0-9.-]/_}"
  local tmp="${target}.tmp.$$.${host}"

  # Ensure parent directory exists. Creating it now keeps the helper
  # idempotent — skills don't need a pre-mkdir step.
  local dir
  dir="$(dirname "$target")"
  mkdir -p "$dir" || {
    echo "atomic_state_write: failed to mkdir $dir" >&2
    return 65
  }

  # 1. Write content from stdin to tmp.
  if ! cat > "$tmp"; then
    rm -f "$tmp"
    echo "atomic_state_write: failed to write tmp $tmp" >&2
    return 66
  fi

  # 1.5. Empty-stdin guard. Without this, a pipe that errors before producing
  # output (e.g., `failing_generator | atomic_state_write target`) would
  # silently truncate target to zero bytes — a data-loss footgun.
  # Callers that intentionally want to write an empty file must `echo ""`
  # or use `truncate -s 0` directly.
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    return 0
  fi

  # 2. fsync tmp file (best effort).
  _atomic_state_sync_file "$tmp"

  # 3. Atomic rename (POSIX guarantees rename-within-same-fs is atomic). -f so
  #    an unwritable existing target cannot prompt and hang a tty session.
  if ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    echo "atomic_state_write: rename to $target failed" >&2
    return 67
  fi

  # 4. fsync the directory so the rename is durable across power loss.
  _atomic_state_sync_file "$dir"

  return 0
}

atomic_state_append() {
  local target="${1:-}"   # default so a zero-arg call under `set -u` reaches the guard
  if [ -z "$target" ]; then
    echo "atomic_state_append: target path required" >&2
    return 64
  fi

  # Ensure parent directory exists.
  local dir
  dir="$(dirname "$target")"
  mkdir -p "$dir" || {
    echo "atomic_state_append: failed to mkdir $dir" >&2
    return 65
  }

  # Capture stdin (handles content without trailing newline; `read -r` would
  # return non-zero on EOF and lose the partial line).
  local content
  content="$(cat)"
  if [ -z "$content" ]; then
    # Empty stdin — nothing to append, treat as success.
    return 0
  fi

  # 4096-byte sanity ceiling for the append. Shell `>>` opens O_APPEND, so the
  # kernel serializes concurrent writes up to PIPE_BUF — but PIPE_BUF is
  # platform-dependent (4096 on Linux, only 512 on macOS), so this cap bounds
  # line length and is NOT a hard macOS atomicity guarantee (see
  # atomic-state-write.md §Constraints). Reserve 2 bytes for the framing the
  # append adds below (an optional leading `\n` + the trailing `\n`) so the
  # bytes actually written stay within the ceiling. Count BYTES not characters
  # — ${#content} counts characters, and multibyte content can exceed 4096
  # bytes while under 4096 chars, silently skipping the guard.
  local content_bytes
  content_bytes=$(printf '%s' "$content" | wc -c | tr -d ' ')
  if [ "$content_bytes" -gt "$GENIRO_APPEND_MAX_BYTES" ]; then
    echo "atomic_state_append: content + framing exceeds the ${GENIRO_APPEND_MAX_BYTES}-byte ceiling (content ${content_bytes}); atomicity not guaranteed" >&2
    return 68
  fi

  # Newline-terminator guard. If the target exists and its last byte is not
  # `\n` (typical of hand-edited files or partial migrations), a bare append
  # would concatenate onto the previous final line, corrupting JSONL — a
  # single line containing two adjacent objects. Prepend a `\n` in that case.
  # `[ -n "$(tail -c 1 "$target")" ]` is the portable last-byte-is-not-newline
  # check: command substitution strips trailing newlines, so when the last
  # byte IS `\n`, `$(tail -c 1)` becomes empty, and `-n` returns false.
  local prefix=""
  if [ -s "$target" ] && [ -n "$(tail -c 1 "$target" 2>/dev/null)" ]; then
    prefix=$'\n'
  fi

  printf '%s%s\n' "$prefix" "$content" >> "$target" || {
    echo "atomic_state_append: append to $target failed" >&2
    return 69
  }

  _atomic_state_sync_file "$target"
  return 0
}
