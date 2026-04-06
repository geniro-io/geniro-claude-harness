#!/bin/bash
# secret-protection-output.sh
# PostToolUse hook for all tools - scans tool output for leaked secrets
# Detects and warns about API keys, tokens, passwords, and other sensitive data in output
# Does NOT block (PostToolUse always exits 0) but injects warning via additionalContext

set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Check if jq is available (required for output parsing and JSON construction)
if ! command -v jq &>/dev/null; then
  # jq not available, exit gracefully (non-critical post-hook)
  exit 0
fi

# Extract tool output from input JSON
TOOL_OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // ""' 2>/dev/null || echo "")

if [ -z "$TOOL_OUTPUT" ]; then
  # No output to scan, allow completion
  exit 0
fi

# Patterns indicating leaked secrets/sensitive data
# These patterns catch common API key formats, tokens, passwords, etc.
SECRET_PATTERNS=(
  "api[_-]?key\s*[:=]\s*['\"]?[a-zA-Z0-9]+"        # API_KEY = or api-key:
  "bearer\s+[a-zA-Z0-9._-]{20,}"                    # Bearer token
  "authorization:\s*bearer\s+"                      # Authorization: Bearer
  "token\s*[:=]\s*['\"]?[a-zA-Z0-9_-]{20,}"         # token = (long string)
  "password\s*[:=]\s*['\"]?[^'\"\s]+"               # password =
  "aws_secret_access_key\s*[:=]"                    # AWS secret
  "aws_access_key_id\s*[:=]"                        # AWS access key
  "private\s+key[:\-]"                              # PRIVATE KEY
  "-----begin\s+(rsa\s+|ec\s+)?private"             # BEGIN PRIVATE KEY
  "secret\s*[:=]\s*['\"]?[^'\"\s]{10,}"             # secret = (any value)
  "github_token\s*[:=]"                             # GitHub token
  "gitlab_token\s*[:=]"                             # GitLab token
  "slack[_-]?webhook\s*[:=]"                        # Slack webhook
  "stripe[_-]?(secret[_-])?key\s*[:=]"              # Stripe key
  "oauth[_-]?token\s*[:=]"                          # OAuth token
  "refresh[_-]?token\s*[:=]"                        # Refresh token
  "-----begin\s+pgp\s+private"                      # PGP private key
  "ssh[_-]?private[_-]?key\s*[:=]"                  # SSH private key
)

# Flag to track if any secrets were detected
SECRETS_FOUND=0
DETECTED_PATTERNS=""

# Check if output matches any secret patterns
for pattern in "${SECRET_PATTERNS[@]}"; do
  if echo "$TOOL_OUTPUT" | grep -qi "$pattern"; then
    SECRETS_FOUND=1
    DETECTED_PATTERNS="$DETECTED_PATTERNS\n  - $pattern"
  fi
done

# If secrets detected, inject warning via additionalContext
if [ $SECRETS_FOUND -eq 1 ]; then
  # Build JSON warning output (use --arg for safe string handling)
  jq -n -c \
    --arg warning "SECURITY WARNING: Tool output may contain sensitive data (API keys, tokens, passwords, private keys, etc.)" \
    --arg patterns "$DETECTED_PATTERNS" \
    --arg recommendation "Review output carefully before sharing. Do not commit secrets to version control or send in messages." \
    '{
      type: "security_warning",
      severity: "high",
      message: $warning,
      matched_patterns: ($patterns | split("\n") | map(select(length > 0))),
      recommendation: $recommendation
    }' 2>/dev/null || true
fi

# PostToolUse always exits 0 (never blocks output, only warns)
exit 0
