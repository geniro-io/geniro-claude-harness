---
name: geniro:cleanup
description: "Remove all geniro-claude-plugin files from the project. Uses plugin state to preserve user-created files. Includes confirmation before any deletion."
context: main
model: inherit
allowed-tools: [Bash, AskUserQuestion, Read, Glob, Grep]
---

# /geniro:cleanup — Remove Plugin Files

Remove all geniro-claude-plugin files from the current project. Preserves any user-created
files that are not part of the plugin.

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
Also extract `deploy_mode` from the state file. Store as `$DEPLOY_MODE` (`"global"` or `"standalone"`). If the field is absent (legacy state), default to `"global"`.

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

1. **Tailored agents** (will be deleted):
   - `.claude/agents/backend-agent.md`
   - `.claude/agents/frontend-agent.md`
2. **Tailored rules** (will be deleted):
   - `.claude/rules/backend-conventions.md`
   - `.claude/rules/security-patterns.md`
3. **Generated review criteria** (will be deleted):
   - `.geniro/project/review/*-criteria.md` (5 files, current location)
   - `.claude/skills/review/*-criteria.md` (5 files, legacy location — clean up if present)
4. **Settings files** (will be deleted — see 1.3 for merge handling):
   - `.claude/settings.json`
   - `.claude/settings.local.json`
5. **Plugin runtime** (will be removed entirely): `.geniro/` directory
6. **User-created files** (will be preserved): any other files in `.claude/` not listed above

**Additional files in standalone mode ($DEPLOY_MODE = standalone):**
7. **All universal agents** (will be deleted):
   - `.claude/agents/architect-agent.md`, `skeptic-agent.md`, `reviewer-agent.md`,
     `refactor-agent.md`, `debugger-agent.md`, `security-agent.md`, `doc-agent.md`,
     `devops-agent.md`, `knowledge-agent.md`, `knowledge-retrieval-agent.md`, `meta-agent.md`
8. **All skills** (will be deleted): `.claude/skills/*/` (all skill directories)
9. **All hooks** (will be deleted): `.claude/hooks/` directory
10. **Hook entries in settings.json** (will be removed from `.claude/settings.json`)
11. **Review criteria** at `.claude/skills/review/` (standalone location, instead of `.geniro/project/review/`)

Also check for plugin-generated entries in other files:
- `CLAUDE.md` at project root — check geniro-state `files.tailored` for `CLAUDE.md`. If listed, it was plugin-generated. If no geniro-state, check if the first line contains `# Geniro Plugin` or `# Geniro Harness Plugin` (legacy header).
- `.gitignore` — check for `.geniro/` entry added by setup

### 1.3 Handle settings.json

`settings.json` requires special handling because setup may have merged plugin entries into
a pre-existing user file:

- If `settings.json` is listed in `files.verbatim` in geniro-state → it was a fresh copy from
  the template. Safe to delete entirely.
- If `settings.json` is listed in `files.tailored` or geniro-state is absent → it may contain
  merged user settings. Read the file and remove only plugin-specific entries (hook command paths
  containing `CLAUDE_PLUGIN_ROOT` or `geniro`, plugin-specific permission entries). Preserve any
  remaining user settings. If the file would be empty after removal, delete it.
- If `settings.json` is not listed in geniro-state at all → it's user-created. Do not touch it.

## Phase 2: Confirm with User

Present the deletion manifest clearly:

```
## Files to remove

### Tailored agents
- .claude/agents/backend-agent.md
- .claude/agents/frontend-agent.md

### Tailored rules
- .claude/rules/backend-conventions.md
- .claude/rules/security-patterns.md

### Generated review criteria
- .geniro/project/review/*-criteria.md (list each file)
- .claude/skills/review/*-criteria.md (legacy, list if present)

### Settings
- .claude/settings.json
- .claude/settings.local.json

### Plugin runtime
- .geniro/ (entire directory)

### Plugin-generated config
- CLAUDE.md (if plugin-generated)
- .gitignore entry: .geniro/

### Standalone-mode files (only if $DEPLOY_MODE = standalone)
- .claude/agents/ (11 universal agent files)
- .claude/skills/*/ (all skill directories)
- .claude/hooks/ (hook scripts)
- .claude/settings.json hook entries

### Files that will be PRESERVED (user-created)
- .claude/some-custom-file.md
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
# Remove tailored agents
rm -f .claude/agents/backend-agent.md
rm -f .claude/agents/frontend-agent.md

# Remove tailored rules
rm -f .claude/rules/backend-conventions.md
rm -f .claude/rules/security-patterns.md

# Remove generated review criteria (current location)
rm -f .geniro/project/review/*-criteria.md
[ -d ".geniro/project/review/" ] && [ -z "$(ls -A .geniro/project/review/)" ] && rmdir .geniro/project/review/

# Remove generated review criteria (legacy location)
rm -f .claude/skills/review/*-criteria.md

# Remove settings
rm -f .claude/settings.json
rm -f .claude/settings.local.json
```

### 3.1b Remove standalone-mode files (only if $DEPLOY_MODE = standalone)

```bash
# Remove all universal agents
for agent in architect-agent skeptic-agent reviewer-agent refactor-agent debugger-agent security-agent doc-agent devops-agent knowledge-agent knowledge-retrieval-agent meta-agent; do
  rm -f ".claude/agents/${agent}.md"
done

# Remove all skill directories
for skill_dir in .claude/skills/*/; do
  [ -d "$skill_dir" ] && find "$skill_dir" -type f -delete && find "$skill_dir" -type d -empty -delete
done

# Remove hook scripts
find .claude/hooks/ -type f -delete 2>/dev/null
[ -d ".claude/hooks/" ] && rmdir .claude/hooks/ 2>/dev/null

# Remove review criteria from standalone location
rm -f .claude/skills/review/*-criteria.md
```

Also remove hook entries from `.claude/settings.json` if present. Read the file, remove any
entries in the `hooks` object that reference `.claude/hooks/`, and write it back. If the file
would be empty or only contain `{}` after removal, delete it.

### 3.2 Remove empty directories

After all files are removed, clean up directories that are now empty using `rmdir` (NOT `rm -rf`):

```bash
# Remove empty skill subdirectories
for dir in .claude/skills/*/; do
  [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ] && rmdir "$dir"
done

# Remove empty top-level directories
for dir in .claude/agents .claude/skills .claude/rules; do
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

Remove `.geniro/` and `!.geniro/project/` entries from `.gitignore` (if present):
```bash
# Remove the .geniro/ ignore and !.geniro/project/ exception from .gitignore
grep -v '^\\.geniro/$' .gitignore | grep -v '^!\.geniro/project/$' > .gitignore.tmp && mv .gitignore.tmp .gitignore
```

If `.gitignore` is now empty, remove it:
```bash
[ ! -s .gitignore ] && rm -f .gitignore
```

### 3.5 Uninstall the plugin

If `$DEPLOY_MODE` is `global` or if the plugin is still installed, uninstall from Claude Code.
If `$DEPLOY_MODE` is `standalone` and the plugin is not installed, skip this step.

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
- X plugin files from .claude/
- .geniro/ runtime directory
- Plugin uninstalled from Claude Code

### Preserved
- Y user-created files (list them, or "none")

The geniro-claude-plugin has been fully removed from this project.
To reinstall: claude plugin install geniro-claude-plugin@geniro-claude-harness
```
