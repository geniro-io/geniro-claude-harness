---
name: geniro:update
description: "Update the geniro-claude-plugin to the latest version and re-run setup to sync project-specific files. Run when the status line shows an update is available."
context: main
model: inherit
allowed-tools: [Bash, AskUserQuestion, Read, Write, Edit, Glob, Grep, Agent]
---

# /geniro:update — Update Plugin

Update the plugin and sync project-specific configuration.

## Path Constraints

**NEVER use `~` in file paths passed to Read, Write, Edit, or Glob tools.** The `~` character is NOT expanded by these tools — it creates a literal `~` directory in the working directory. Always use `${CLAUDE_PLUGIN_ROOT}` for plugin files or absolute paths (e.g., `/Users/...`) for project files.

If a step fails, do NOT improvise by constructing paths manually. Report the error and stop.

## Steps

### 1. Check current version

```bash
cat "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" | grep version
```

### 2. Refresh marketplace and update plugin

Run both commands — the marketplace refresh fetches latest commit info from GitHub,
then the plugin update pulls the new files:

```bash
claude plugin marketplace update geniro-claude-harness
claude plugin update geniro-claude-plugin@geniro-claude-harness
```

If the update fails or no update is available, report the result and stop.

### 3. Refresh update cache

Re-run the update check so the statusline reflects the new version:

```bash
GENIRO_UPDATE_BG=1 GENIRO_FORCE_CHECK=1 node "${CLAUDE_PLUGIN_ROOT}/hooks/geniro-check-update.js"
```

This writes `update_available: false` to the cache with the correct installed version.

### 4. Re-run setup

After a successful update, invoke `/geniro:setup` using the Skill tool to sync project-specific files
(tailored agents, rules, review criteria) with any changes in the updated plugin templates.

```
Skill(skill="geniro:setup")
```

The setup skill detects existing files and shows a per-file diff — the user decides what to accept.
