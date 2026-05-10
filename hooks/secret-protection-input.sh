#!/bin/bash
# secret-protection-input.sh
# PreToolUse hook for Bash - blocks commands that read sensitive files.
#
# Simplified 2026-05-10 — dropped broad keyword patterns (cat *secret*, *token*,
# *password*, *key*) which fired on routine source files and docs
# (src/auth/token.ts, docs/secret-handling.md, src/components/PasswordReset.tsx).
# New patterns target unambiguous secret-file paths only (.env, ~/.aws/credentials,
# ~/.ssh/id_*, *.pem/*.p12/*.pfx/keystore, .npmrc, .pypirc, .netrc) and cover
# additional reader commands beyond `cat` (less, tail, head, xxd, awk, < redirection).

set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Extract command from tool input JSON
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  # No command found, allow execution
  exit 0
fi

# Patterns for commands that read sensitive files.
# Two flavors: (a) unambiguous secret-file paths anywhere in the command,
# (b) reader commands explicitly aimed at .env / ssh / aws files.
SENSITIVE_FILE_PATTERNS=(
  # --- (a) Unambiguous secret-file paths (target the file, not the keyword) ---
  "\.env(\.|$|\s)"                           # .env / .env.local / .env.prod / etc.
  "~?/\.aws/credentials"                     # AWS credentials file
  "~?/\.ssh/id_(rsa|ed25519|dsa|ecdsa)"      # SSH private keys
  "~?/\.kube/config"                         # Kubernetes config
  "\.pem(\s|$)"                              # PEM certs/keys
  "\.p12(\s|$)"                              # PKCS#12 bundles
  "\.pfx(\s|$)"                              # PFX bundles
  "\.keystore(\s|$)"                         # Java keystores
  "~?/\.npmrc"                               # npm auth tokens
  "~?/\.pypirc"                              # PyPI auth
  "\.netrc"                                  # netrc credentials

  # --- (b) Reader commands (cover < redirection + alternates beyond cat) ---
  "(^|\s)cat\s+[^|]*\.env"
  "(^|\s)less\s+[^|]*\.env"
  "(^|\s)tail\s+[^|]*\.env"
  "(^|\s)head\s+[^|]*\.env"
  "(^|\s)xxd\s+[^|]*\.env"
  "(^|\s)awk\s+.*\.env"
  "(^|\s)<\s*.*\.env"
  "(^|\s)cat\s+[^|]*~?/\.aws/credentials"
  "(^|\s)cat\s+[^|]*~?/\.ssh/id_"

  # --- Long-standing patterns retained ---
  "source\s+\.env([^a-zA-Z0-9_]|$)"          # source .env (exports secrets)
  "source\s+\.env\.\w+"                      # source .env.local, .env.dev
  "openssl\s+rsa\s+-in"                      # openssl rsa -in (key inspection)
  "openssl\s+ec\s+-in"                       # openssl ec -in (EC key inspection)
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
