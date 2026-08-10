#!/usr/bin/env bash
# atomic_state_write <path> — write stdin to <path> via tmp + fsync + rename.

atomic_state_write() {
  local dest="$1" tmp
  [ -n "$dest" ] || return 10
  tmp="$(mktemp "${dest}.XXXXXX")" || return 10
  cat > "$tmp"
  sync
  mv -f "$tmp" "$dest" || { rm -f "$tmp"; return 11; }
  return 0
}
