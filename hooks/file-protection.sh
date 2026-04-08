#!/bin/bash
# file-protection.sh
# PreToolUse hook for Write and Edit - blocks writes to sensitive files
# Prevents accidental exposure of credentials and protected configurations

set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Extract file path from tool input JSON
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // "" | ascii_downcase' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
  # No file path found, allow execution
  exit 0
fi

# Array of protected file patterns (case-insensitive)
PROTECTED_PATTERNS=(
  "\.env$"                    # .env files
  "\.env\."                   # .env.* files (e.g., .env.local, .env.production)
  "\.git/"                    # Git internal files
  "pnpm-lock\.yaml$"          # pnpm lock file
  "package-lock\.json$"       # npm lock file
  "yarn\.lock$"               # yarn lock file
  "\.pem$"                    # PEM certificates and private keys
  "\.key$"                    # Private key files
  "credentials\."             # credentials.* files
  "secrets\."                 # secrets.* files
  "private-key"               # Files with private-key in name
  "\.tfstate"                 # Terraform state files
  "\.vault"                   # Vault files
)

# Convert file path to lowercase for case-insensitive matching
FILE_PATH_LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

# Check if file matches any protected pattern
for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if echo "$FILE_PATH_LOWER" | grep -qE "$pattern"; then
    # Block the write with exit code 2
    echo "File protection: Cannot write to protected file: $FILE_PATH" >&2
    exit 2
  fi
done

# File is safe to write, allow execution
exit 0
