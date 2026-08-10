#!/usr/bin/env bash
# Read the project's guard allowlist from .plugin/safety.json.

# read_allow_patterns — the allow_patterns array as a space-separated string.
# Returns non-zero when the file is missing or unparseable, so callers can fail
# closed rather than treating an unreadable allowlist as an empty one.
read_allow_patterns() {
  local cfg="${SAFETY_JSON:-.plugin/safety.json}"
  [ -f "$cfg" ] || return 1
  jq -r '.allow_patterns[]?' "$cfg" 2>/dev/null | tr '\n' ' ' || return 1
}
