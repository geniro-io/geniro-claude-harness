#!/bin/bash
# dangerous-command-blocker.sh
# PreToolUse hook for Bash - blocks destructive and dangerous commands
# Prevents accidental data loss and security issues

set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Extract command from tool input JSON
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  # No command found, allow execution
  exit 0
fi

# Array of dangerous patterns to block
# Use word boundaries to avoid false positives in comments/strings
DANGEROUS_PATTERNS=(
  "docker volume rm"              # Docker volume destruction
  "\bDROP\s+TABLE\b"              # SQL table destruction (word boundaries)
  "git push --force"              # Force push (rewrites history)
  "git push -f"                   # Force push alias
  "rm -rf /"                      # Root directory deletion
  "git reset --hard"              # Discard all changes
  "git checkout \."               # Discard staged changes
  "\bTRUNCATE\b"                  # SQL table truncation (word boundaries)
  "\bDELETE\s+FROM\s+\w+\s*$"     # SQL DELETE FROM without WHERE clause
  "git clean -f"                  # Force clean working directory
  "git branch -D main"            # Delete main branch
  "git branch -D master"          # Delete master branch
)

# Extract the base command (before any pipe) for SQL/destructive checks.
# Grep patterns inside pipes (e.g., `| grep "drop table"`) are search patterns,
# not actual destructive commands — don't match against them.
BASE_COMMAND=$(echo "$COMMAND" | sed 's/|.*//')

# Check if command matches any dangerous pattern
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  # SQL patterns (DROP, TRUNCATE, DELETE) only check the base command (before pipes)
  # to avoid false positives on grep/search patterns in piped output.
  # All other patterns check the full command.
  case "$pattern" in
    *DROP*|*TRUNCATE*|*DELETE*)
      CHECK_AGAINST="$BASE_COMMAND"
      ;;
    *)
      CHECK_AGAINST="$COMMAND"
      ;;
  esac

  if echo "$CHECK_AGAINST" | grep -qiE "$pattern"; then
    # Block the command with exit code 2
    echo "Security blocked: Command matches dangerous pattern: $pattern" >&2
    exit 2
  fi
done

# Command is safe, allow execution
exit 0
