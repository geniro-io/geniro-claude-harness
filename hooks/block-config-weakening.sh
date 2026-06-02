#!/bin/bash
# block-config-weakening.sh
# PreToolUse hook for Edit|Write — blocks edits to an EXISTING lint / formatter /
# type-checker config file.
#
# Rationale: editing an established linter/formatter/type-checker config to silence
# a check (disable a rule, loosen tsconfig strictness, add an ignore entry) hides
# the underlying issue instead of fixing the source. First-time creation of such a
# config is allowed — only edits to a file that already exists on disk are blocked.
#
# Per-project bypass: add "config-weakening" to allow_patterns in .geniro/safety.json
# (in cwd or any ancestor).
#
# Schema:
#   {
#     "allow_patterns": ["config-weakening"]
#   }

set -euo pipefail

# Consume stdin — REQUIRED first step.
INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Find the nearest .geniro/safety.json walking up from cwd.
find_safety_json() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.geniro/safety.json" ]; then
      echo "$dir/.geniro/safety.json"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

ALLOWED=""
SAFETY_FILE=$(find_safety_json 2>/dev/null || true)
if [ -n "$SAFETY_FILE" ] && [ -f "$SAFETY_FILE" ]; then
  ALLOWED=$(jq -r '.allow_patterns[]? // empty' "$SAFETY_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
fi

is_allowed() {
  local pattern_id="$1"
  case " $ALLOWED " in
    *" $pattern_id "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Bypassed for this project — allow.
if is_allowed "config-weakening"; then
  exit 0
fi

# Match the basename against known lint / formatter / type-checker config names.
filename="${FILE_PATH##*/}"

is_config_file() {
  local name="$1"
  case "$name" in
    # ESLint
    .eslintrc|.eslintrc.*|eslint.config.*) return 0 ;;
    # Prettier
    .prettierrc|.prettierrc.*|prettier.config.*) return 0 ;;
    # Biome
    biome.json|biome.jsonc) return 0 ;;
    # Ruff
    ruff.toml|.ruff.toml) return 0 ;;
    # TypeScript compiler config (tsconfig.json, tsconfig.base.json, tsconfig.build.json, ...)
    tsconfig.json|tsconfig.*.json) return 0 ;;
    # golangci-lint
    .golangci.yml|.golangci.yaml|.golangci.toml) return 0 ;;
    *) return 1 ;;
  esac
}

if ! is_config_file "$filename"; then
  exit 0
fi

# First-time creation is fine — only block edits to a config that already exists.
if [ ! -e "$FILE_PATH" ]; then
  exit 0
fi

cat >&2 <<EOF
Security blocked [config-weakening]: editing an existing linter/formatter/type config to silence checks is blocked.
  File: $FILE_PATH

Fix the source the check is flagging instead of loosening the config.
EOF
if [ -n "$SAFETY_FILE" ]; then
  echo "To allow this, add \"config-weakening\" to allow_patterns in $SAFETY_FILE" >&2
else
  echo "To allow this in this project, create .geniro/safety.json with: {\"allow_patterns\": [\"config-weakening\"]}" >&2
fi
exit 2
