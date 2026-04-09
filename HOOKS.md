# Geniro Plugin - Hooks Documentation

This directory contains production-grade hooks for the geniro plugin. All hooks follow best practices from the official Claude Code documentation and proven implementations from Citadel, Claude Forge, and claude-pipeline.

## Files Created

### 1. dangerous-command-blocker.sh
**Type:** PreToolUse hook for Bash  
**Purpose:** Blocks destructive and dangerous commands before execution

**Blocks:**
- `docker volume rm` - Container volume destruction
- `DROP TABLE` - SQL table deletion
- `git push --force` / `git push -f` - Forced push (rewrites history)
- `rm -rf /` - Root directory deletion
- `git reset --hard` - Discard all changes
- `git checkout .` - Discard staged changes
- `TRUNCATE` - SQL truncation
- `DELETE FROM` without WHERE clause
- `git clean -f` - Force clean working directory
- `git branch -D main/master` - Delete main/master branch

**Implementation Details:**
- Consumes stdin as first action
- Parses JSON input with jq
- Uses regex matching for flexibility
- Exit code 2 to block (FAIL-SAFE)
- Provides clear error message

---

### 2. file-protection.sh
**Type:** PreToolUse hook for Write and Edit  
**Purpose:** Prevents writes to sensitive files containing credentials and configurations

**Protects:**
- `.env` files - Environment configuration
- `.env.*` files - Environment variants (.env.local, .env.production, etc.)
- `.git/*` - Git internal files
- `pnpm-lock.yaml` - PNPM lock files
- `package-lock.json` - NPM lock files
- `yarn.lock` - Yarn lock files
- `*.pem` - PEM certificates/keys
- `*.key` - Private key files
- `credentials.*` - Credential files
- `secrets.*` - Secret files
- `*.tfstate` - Terraform state files
- `.vault` - Vault files

**Implementation Details:**
- Case-insensitive pattern matching
- Lowercase conversion for consistency
- Exit code 2 to block (FAIL-SAFE)
- Protects against accidental credential exposure

---

### 4. settings.json
**Purpose:** Centralized configuration for all hooks

**Structure:**
- `hooks.PreToolUse` - Dangerous command, interactive command, and file protection
- `hooks.PostToolUse` - Auto-format after edits
- `permissions` - Global permission model (Bash, Write, Edit allowed)

**Matchers Used:**
- `"Bash"` - All bash commands
- `"Edit|Write"` - File operations
- `"Edit|Write"` - Format post-operation

**Status Messages:** User-friendly spinner messages during hook execution

---

## Testing

All hooks have been tested with sample inputs:

```bash
# Test dangerous command blocker
echo '{"tool_input":{"command":"rm -rf /"}}' | ./hooks/dangerous-command-blocker.sh
# Exit code 2 - BLOCKED

# Test file protection
echo '{"tool_input":{"file_path":"/config/.env"}}' | ./hooks/file-protection.sh
# Exit code 2 - BLOCKED
```

---

## Key Safety Principles

1. **Exit Code 2 for Blocking** - Never use exit 1 (which is FAIL-OPEN)
2. **Stdin Consumption** - All hooks consume stdin as first action
3. **JSON Parsing** - Use jq for safe input extraction
4. **Error Messages to Stderr** - Clear feedback redirected to user
5. **Graceful Degradation** - Auto-format fails safely if no formatter found
6. **Case Insensitivity** - File patterns are case-insensitive

---

## Installation

Place `.claude/` directory at project root:

```
project/
├── .claude/
│   ├── settings.json (from this template)
│   └── hooks/
│       ├── dangerous-command-blocker.sh
│       ├── file-protection.sh
│       ├── secret-protection-input.sh
│       └── secret-protection-output.sh
├── src/
└── ...
```

The hooks will automatically trigger on matching tool uses.

---

## Sources & References

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- Exit code behavior: Exit 0 = allow, Exit 2 = block
