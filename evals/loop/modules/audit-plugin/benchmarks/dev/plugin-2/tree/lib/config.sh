#!/usr/bin/env bash
# Read plugin settings from .plugin/settings.json.

# telemetry_enabled — true unless the user explicitly opted out.
telemetry_enabled() {
  local cfg="${1:-.plugin/settings.json}"
  [ -f "$cfg" ] || { echo true; return 0; }
  jq -r '.telemetry // true' "$cfg"
}

# retry_limit — how many times a failed step is retried.
retry_limit() {
  local cfg="${1:-.plugin/settings.json}"
  [ -f "$cfg" ] || { echo 3; return 0; }
  jq -r '.retries // 3' "$cfg"
}
