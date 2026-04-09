---
name: geniro:cleanup
description: "Remove all geniro-claude-plugin files from the project. Uses plugin state to preserve user-created files. Includes confirmation before any deletion."
context: main
model: inherit
allowed-tools: [Bash, AskUserQuestion, Read, Glob, Grep]
---

# /geniro:cleanup — Remove Plugin Files

Remove all geniro-claude-plugin files from the current project. In the global-only model,
the plugin provides agents, skills, and hooks globally — setup only generates CLAUDE.md and `.geniro/` runtime dirs into the project. Cleanup removes only what setup generated.

## Phase 0: Quick Check

If `.claude/` does not exist and `.geniro/` does not exist, report
"No plugin files found. Nothing to clean up." and stop.

## Phase 1: Inventory

### 1.1 Detect plugin state

Check for `.geniro/.geniro-state.json`:

```bash
cat .geniro/.geniro-state.json 2>/dev/null
```

**If found:** parse the `files.tailored` and `files.user_created` arrays.
These tell you exactly which files in `.claude/` belong to the plugin and which the user created.

**If not found:** fall back to heuristic detection — compare files in `.claude/` against
the known plugin-generated files:

```bash
# List all files in .claude/ (excluding .artifacts/)
find .claude/ -type f ! -path '.claude/.artifacts/*' 2>/dev/null
```

A file is **plugin-owned** if it matches one of the known generated files listed in 1.2.
A file is **user-created** if it exists in `.claude/` but is not a known plugin file.

### 1.2 Build deletion manifest

The plugin generates these files in the project:

1. **Plugin runtime** (will be removed entirely): `.geniro/` directory
2. **User-created files** (will be preserved): any files in `.claude/` not created by plugin

Also check for plugin-generated entries in other files:
- `CLAUDE.md` at project root — check geniro-state `files.tailored` for `CLAUDE.md`. If listed, it was plugin-generated. If no geniro-state, check if the first line contains `# Geniro Plugin` or `# Geniro Harness Plugin` (legacy header).
- `.gitignore` — check for `.geniro/` entry added by setup

## Phase 2: Confirm with User

Present the deletion manifest clearly:

```
## Files to remove

### Plugin runtime
- .geniro/ (entire directory)

### Plugin-generated config
- CLAUDE.md (if plugin-generated)
- .gitignore entry: .geniro/

### Files that will be PRESERVED (user-created)
- ... (list all, or "none")
```

Use the `AskUserQuestion` tool:
- **Question:** "Confirm removal of all listed plugin files?"
- **Options:**
  - "Remove all plugin files (Recommended)" — delete everything listed above
  - "Remove plugin files but keep CLAUDE.md" — preserve the generated CLAUDE.md
  - "Cancel — don't remove anything" — abort cleanup

**If user cancels:** stop immediately, report "Cleanup cancelled. No files were modified."

## Phase 3: Remove Files

Execute deletion in order. **NEVER use `rm -rf`** — it triggers the dangerous-command-blocker
hook. Use `rm -f` for individual files and `rmdir` for empty directories only.

### 3.1 Remove plugin runtime directory

Remove `.geniro/` contents file-by-file, then remove empty directories:

```bash
# Remove all files inside .geniro/ recursively, then empty dirs
find .geniro/ -type f -delete 2>/dev/null
find .geniro/ -type d -empty -delete 2>/dev/null
```

### 3.2 Clean up generated config

If user approved CLAUDE.md removal and it was plugin-generated:
```bash
rm -f CLAUDE.md
```

Remove `.geniro/` entry from `.gitignore` (if present):
```bash
# Remove the .geniro/ ignore from .gitignore
grep -v '^\\.geniro/$' .gitignore > .gitignore.tmp && mv .gitignore.tmp .gitignore
```

If `.gitignore` is now empty, remove it:
```bash
[ ! -s .gitignore ] && rm -f .gitignore
```

### 3.3 Uninstall the plugin

Attempt to uninstall the plugin from Claude Code:

```bash
claude plugin uninstall geniro-claude-plugin@geniro-claude-harness
```

If the uninstall command fails (e.g., plugin already removed or not installed), report the
error but do not treat it as a cleanup failure — the project files have already been removed
successfully.

## Phase 4: Report

Present a summary:

```
## Cleanup Complete

### Removed
- Plugin runtime: .geniro/
- Plugin uninstalled from Claude Code

### Preserved
- Y user-created files (list them, or "none")

The geniro-claude-plugin has been fully removed from this project.
To reinstall: claude plugin install geniro-claude-plugin@geniro-claude-harness
```
