---
name: geniro:cleanup
description: "Remove all geniro-claude-plugin files from the project. Uses harness state to preserve user-created files. Includes confirmation before any deletion."
context: main
model: inherit
allowed-tools: [Bash, AskUserQuestion, Read, Glob, Grep]
---

# /geniro:cleanup — Remove Plugin Files

Remove all geniro-claude-plugin files from the current project. Preserves any user-created
files that are not part of the plugin template.

## Phase 0: Quick Check

If `.claude/` does not exist and `.geniro/` does not exist, report
"No plugin files found. Nothing to clean up." and stop.

## Phase 1: Inventory

### 1.1 Detect harness state

Check for `.geniro/.harness-state.json`:

```bash
cat .geniro/.harness-state.json 2>/dev/null
```

**If found:** parse the `files.verbatim`, `files.tailored`, and `files.user_created` arrays.
These tell you exactly which files in `.claude/` belong to the plugin and which the user created.

**If not found:** fall back to heuristic detection — compare files in `.claude/` against
the plugin template to classify them:

```bash
# List all files in .claude/ (excluding .artifacts/)
find .claude/ -type f ! -path '.claude/.artifacts/*' 2>/dev/null

# List template files for comparison
ls "${CLAUDE_PLUGIN_ROOT}/agents/" "${CLAUDE_PLUGIN_ROOT}/hooks/" 2>/dev/null
ls "${CLAUDE_PLUGIN_ROOT}/skills/" 2>/dev/null
```

A file is **plugin-owned** if its filename matches a template file (agents, hooks, skills, settings.json).
A file is **user-created** if it exists in `.claude/` but has no corresponding template file.

### 1.2 Build deletion manifest

Build three lists:

1. **Plugin files** (will be deleted): all verbatim + tailored files from `.claude/`, including:
   - Agent files (`.claude/agents/*.md`) — both `.sh` and `.md` files
   - Hook files (`.claude/hooks/*.sh`, `.claude/hooks/*.js`, `.claude/hooks/hooks.json`)
   - Skill directories (`.claude/skills/*/`)
   - Rules files (`.claude/rules/*.md`)
   - `settings.json` — see Step 1.3 for merge handling
2. **Plugin directories** (will be removed if empty after file deletion):
   - `.claude/agents/`
   - `.claude/hooks/`
   - `.claude/skills/` (each skill subdirectory)
   - `.claude/rules/`
3. **Plugin runtime** (will be removed entirely): `.geniro/` directory
4. **User-created files** (will be preserved): files not matching any template file

Also check for plugin-generated entries in other files:
- `CLAUDE.md` at project root — check harness-state `files.tailored` for `CLAUDE.md`. If listed, it was plugin-generated. If no harness-state, check if the first line contains `# Geniro Harness Plugin`.
- `.gitignore` — check for `.geniro/` entry added by setup

### 1.3 Handle settings.json

`settings.json` requires special handling because setup may have merged plugin entries into
a pre-existing user file:

- If `settings.json` is listed in `files.verbatim` in harness-state → it was a fresh copy from
  the template. Safe to delete entirely.
- If `settings.json` is listed in `files.tailored` or harness-state is absent → it may contain
  merged user settings. Read the file and remove only plugin-specific entries (hook command paths
  containing `CLAUDE_PLUGIN_ROOT` or `geniro`, plugin-specific permission entries). Preserve any
  remaining user settings. If the file would be empty after removal, delete it.
- If `settings.json` is not listed in harness-state at all → it's user-created. Do not touch it.

## Phase 2: Confirm with User

Present the deletion manifest clearly:

```
## Files to remove

### Plugin files (.claude/)
- .claude/agents/architect-agent.md
- .claude/agents/backend-agent.md
- ... (list all)

### Plugin runtime
- .geniro/ (entire directory)

### Plugin-generated config
- CLAUDE.md (if plugin-generated)
- .gitignore entry: .geniro/

### Files that will be PRESERVED (user-created)
- .claude/agents/my-custom-agent.md
- ... (list all, or "none" if empty)
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

### 3.1 Remove plugin files from .claude/

Remove each file individually with `rm -f`. Do NOT use `rm -rf` on directories.

```bash
# Remove each plugin file one by one — NEVER rm -rf on directories
rm -f .claude/agents/architect-agent.md
rm -f .claude/agents/backend-agent.md
rm -f .claude/hooks/dangerous-command-blocker.sh
rm -f .claude/hooks/geniro-check-update.js
rm -f .claude/skills/plan/SKILL.md
# ... repeat for EVERY file individually
```

### 3.2 Remove empty directories

After all files are removed, clean up directories that are now empty using `rmdir` (NOT `rm -rf`):

```bash
# Remove empty skill subdirectories
for dir in .claude/skills/*/; do
  [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ] && rmdir "$dir"
done

# Remove empty top-level directories
for dir in .claude/agents .claude/hooks .claude/skills .claude/rules; do
  [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ] && rmdir "$dir"
done

# Remove .claude/ itself only if completely empty
[ -d ".claude/" ] && [ -z "$(ls -A .claude/)" ] && rmdir .claude/
```

### 3.3 Remove plugin runtime directory

Remove `.geniro/` contents file-by-file, then remove empty directories:

```bash
# Remove all files inside .geniro/ recursively, then empty dirs
find .geniro/ -type f -delete 2>/dev/null
find .geniro/ -type d -empty -delete 2>/dev/null
```

### 3.4 Clean up generated config

If user approved CLAUDE.md removal and it was plugin-generated:
```bash
rm -f CLAUDE.md
```

Remove `.geniro/` entry from `.gitignore` (if present):
```bash
# Remove the .geniro/ line from .gitignore
grep -v '^\\.geniro/$' .gitignore > .gitignore.tmp && mv .gitignore.tmp .gitignore
```

If `.gitignore` is now empty, remove it:
```bash
[ ! -s .gitignore ] && rm -f .gitignore
```

### 3.5 Uninstall the plugin

After removing project files, uninstall the plugin from Claude Code:

```bash
claude plugin uninstall geniro-claude-plugin@geniro-claude-harness
```

If the uninstall command fails (e.g., plugin already removed), report the error but do not
treat it as a cleanup failure — the project files have already been removed successfully.

## Phase 4: Report

Present a summary:

```
## Cleanup Complete

### Removed
- X plugin files from .claude/
- .geniro/ runtime directory
- Plugin uninstalled from Claude Code

### Preserved
- Y user-created files (list them, or "none")

The geniro-claude-plugin has been fully removed from this project.
To reinstall: claude plugin install geniro-claude-plugin@geniro-claude-harness
```
