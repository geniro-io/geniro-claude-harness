#!/usr/bin/env bash
# Atomic state-file write helpers.
#
# Spec: skills/_shared/atomic-state-write.md
# Tier model: skills/_shared/state-tier-spec.md
# Design rationale: architecture/M1-state-files.md §Atomic write helper
#
# Source this file from a skill's Bash invocation:
#   source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.sh"
#   atomic_state_write <target-path> <<'CONTENT'
#   ...
#   CONTENT
#
# Functions exported:
#   atomic_state_write <target>   — tmp + fsync + rename + fsync-dir (T1 / T2 / T3 CRUD)
#   atomic_state_append <target>  — POSIX O_APPEND for ≤4KB lines (T3 append-only / JSONL)

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
  local target="$1"
  if [ -z "$target" ]; then
    echo "atomic_state_write: target path required" >&2
    return 64
  fi

  # PID + hostname suffix prevents collision on NFS-shared .geniro/.
  local host="${HOSTNAME:-localhost}"
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

  # 2. fsync tmp file (best effort).
  _atomic_state_sync_file "$tmp"

  # 3. Atomic rename (POSIX guarantees rename-within-same-fs is atomic).
  if ! mv "$tmp" "$target"; then
    rm -f "$tmp"
    echo "atomic_state_write: rename to $target failed" >&2
    return 67
  fi

  # 4. fsync the directory so the rename is durable across power loss.
  _atomic_state_sync_file "$dir"

  return 0
}

atomic_state_append() {
  local target="$1"
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

  # Read one line from stdin.
  local line
  IFS= read -r line || {
    # EOF on empty stdin — nothing to append, treat as success.
    return 0
  }

  # POSIX-atomic append for writes ≤ PIPE_BUF (4096 on Linux).
  # Shell `>>` opens with O_APPEND, so the kernel serializes concurrent writes.
  if [ "${#line}" -gt 4096 ]; then
    echo "atomic_state_append: line exceeds 4096 bytes (got ${#line}); atomicity not guaranteed" >&2
    return 68
  fi

  printf '%s\n' "$line" >> "$target" || {
    echo "atomic_state_append: append to $target failed" >&2
    return 69
  }

  _atomic_state_sync_file "$target"
  return 0
}
