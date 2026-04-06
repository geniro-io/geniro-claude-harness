#!/bin/bash
# secret-protection-input.sh
# PreToolUse hook for Bash - blocks commands that read sensitive files
# Prevents accidental exposure of credentials, API keys, private keys, and secrets

set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Extract command from tool input JSON
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  # No command found, allow execution
  exit 0
fi

# Patterns for commands that read sensitive files
# Covers: .env files, credentials, private keys, secrets, tokens, passwords
SENSITIVE_FILE_PATTERNS=(
  "cat\s+\.env([^a-zA-Z0-9_]|$)"        # cat .env (but NOT .envrc — direnv config is safe)
  "source\s+\.env([^a-zA-Z0-9_]|$)"     # source .env (but NOT .envrc)
  "cat\s+credentials\."                  # cat credentials.json, credentials.ini, etc.
  "cat\s+.*\.pem"                        # cat *.pem (private keys)
  "cat\s+.*private.*\.key"               # cat *private*.key
  "cat\s+.*secret"                       # cat *secret* files
  "cat\s+~/.ssh/id_"                     # cat ~/.ssh/id_rsa, id_ed25519, etc.
  "cat\s+~/.aws/credentials"             # cat AWS credentials
  "cat\s+~/.kube/config"                 # cat kubernetes config
  "cat\s+\.git/config"                   # cat .git/config (may contain credentials)
  "cat\s+.*token"                        # cat *token* files
  "cat\s+.*api_?key"                     # cat *api_key* or *apikey* files
  "cat\s+.*password"                     # cat *password* files
  "cat\s+\.env\.\w+"                     # cat .env.local, .env.prod, etc.
  "source\s+~/.bashrc"                   # source ~/.bashrc (may export secrets)
  "source\s+~/.bash_profile"             # source ~/.bash_profile
  "source\s+\.env\.\w+"                  # source .env.local, .env.dev, etc.
  "grep\s+-r\s+API"                      # Recursive grep for API patterns
  "grep\s+-r\s+SECRET"                   # Recursive grep for SECRET
  "openssl\s+rsa\s+-in"                  # openssl rsa -in (key inspection)
  "openssl\s+ec\s+-in"                   # openssl ec -in (EC key inspection)
)

# Check if command matches any sensitive file pattern
for pattern in "${SENSITIVE_FILE_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qiE "$pattern"; then
    # Block the command with exit code 2 - DO NOT use exit 1 (fail-open)
    echo "Security blocked: Command attempts to read sensitive file: $pattern" >&2
    exit 2
  fi
done

# Command is safe, allow execution
exit 0
