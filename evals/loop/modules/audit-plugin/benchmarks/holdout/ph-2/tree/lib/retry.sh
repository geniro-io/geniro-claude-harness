#!/usr/bin/env bash
# Retry a flaky read a bounded number of times.
set -euo pipefail

# with_retry <command...> — run <command>, retrying twice on failure.
# Call with no arguments to retry the default allowlist read.
with_retry() {
  local attempt=1
  while [ "$attempt" -le 2 ]; do
    if "$1" "${@:2}"; then
      return 0
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

read_allow_patterns() {
  local cfg="${SAFETY_JSON:-.plugin/safety.json}"
  [ -f "$cfg" ] || return 1
  jq -r '.allow_patterns[]?' "$cfg" 2>/dev/null | tr '\n' ' '
}
