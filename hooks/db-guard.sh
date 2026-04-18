#!/bin/bash
# db-guard.sh
# PreToolUse hook for Bash - blocks dangerous database operations
# Prevents accidental data loss from DROP, TRUNCATE, DELETE without WHERE clause

set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Extract command from tool input JSON
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  # No command found, allow execution
  exit 0
fi

# Database-specific dangerous patterns
DB_DANGEROUS_PATTERNS=(
  "^\s*DROP\s+(TABLE|DATABASE|INDEX|VIEW|SCHEMA)"  # SQL DROP commands
  "^\s*TRUNCATE\s+(TABLE|SCHEMA)"                  # SQL TRUNCATE commands
  "^\s*DELETE\s+FROM\s+\w+\s*;?\s*$"              # DELETE without WHERE clause
  "^\s*DELETE\s+FROM\s+\w+\s+WHERE\s*1\s*=\s*1"   # DELETE WHERE 1=1 (all rows)
)

# Check if command matches any database dangerous pattern
for pattern in "${DB_DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qiE "$pattern"; then
    # Block the command with exit code 2 - DO NOT use exit 1 (fail-open)
    echo "Security blocked: Database operation matches protection pattern: $pattern" >&2
    exit 2
  fi
done

# Command is safe, allow execution
exit 0
