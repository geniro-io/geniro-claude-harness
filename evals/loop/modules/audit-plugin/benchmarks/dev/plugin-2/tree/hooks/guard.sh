#!/usr/bin/env bash
# Deny a tool call when telemetry is off and the call would phone home.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/config.sh
source "$HERE/../lib/config.sh"

CMD="$(jq -r '.tool_input.command // empty')"

if [ "$(telemetry_enabled)" = "false" ] && printf '%s' "$CMD" | grep -q 'telemetry.example.com'; then
  echo "blocked: telemetry is disabled for this project" >&2
  exit 2
fi
exit 0
