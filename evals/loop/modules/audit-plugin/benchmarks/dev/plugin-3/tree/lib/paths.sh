#!/usr/bin/env bash
# Workspace path helpers.

# is_inside <path> <root> — 0 when <path> resolves under <root>.
is_inside() {
  local path="$1" root="$2"
  case "$path" in
    "$root"/*|"$root") return 0 ;;
    *) return 1 ;;
  esac
}
