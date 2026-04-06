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

# SQL patterns should only be checked when the command is actually executing SQL,
# not when reading/searching files that happen to mention SQL keywords.
SQL_EXECUTORS="psql|mysql|sqlite3|mongosh|mongo|sqlcmd|bq|clickhouse-client"
IS_SQL_CONTEXT=false
if echo "$BASE_COMMAND" | grep -qiE "^\s*($SQL_EXECUTORS)\b"; then
  IS_SQL_CONTEXT=true
fi

# Check if command matches any dangerous pattern
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  # SQL patterns (DROP, TRUNCATE, DELETE) only apply in SQL execution contexts
  # to avoid false positives on cat/grep/echo commands that mention SQL keywords.
  case "$pattern" in
    *DROP*|*TRUNCATE*|*DELETE*)
      if [ "$IS_SQL_CONTEXT" = false ]; then
        continue
      fi
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
