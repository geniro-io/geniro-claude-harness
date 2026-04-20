---
name: geniro:update
description: "Update the geniro-claude-plugin to the latest version. Run when the status line shows an update is available."
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

### 3. Discover new plugin path

After a successful update, the plugin install path changes (new version directory). Discover the new path first — subsequent steps need it:

```bash
PLUGIN_PATH=$(python3 -c "import json; d=json.load(open('$HOME/.claude/plugins/installed_plugins.json')); p=d['plugins'].get('geniro-claude-plugin@geniro-claude-harness',[]); print(p[0]['installPath'] if p else '')" 2>/dev/null)
```

### 4. Refresh update cache

Re-run the update check using the **new** plugin path (NOT `${CLAUDE_PLUGIN_ROOT}` — it still points to the old version in this session):

```bash
GENIRO_UPDATE_BG=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_PATH" node "$PLUGIN_PATH/hooks/geniro-check-update.js"
```

This writes `update_available: false` to the cache with the correct installed version. Using `${CLAUDE_PLUGIN_ROOT}` here would read the old `plugin.json` and leave the cache stale.

### 4.1 Refresh statusLine script

Refresh the stable user-level copy of the statusline script only if it already exists — its presence indicates the user ran `/geniro:setup` and has a `statusLine` entry in `~/.claude/settings.json` pointing at `~/.claude/hooks/geniro-statusline.js`. If the stable copy is absent, skip this step: the plugin's bundled `settings.json` already exposes the statusline via `${CLAUDE_PLUGIN_ROOT}` (which now points at the new version), so no refresh is needed. Creating `~/.claude/hooks/geniro-statusline.js` here without a corresponding settings entry would be a stray file the user never asked for — `/geniro:setup` is the single source of truth for installing that entry.

```bash
if [ -f "$HOME/.claude/hooks/geniro-statusline.js" ]; then
  mkdir -p "$HOME/.claude/hooks"
  cp "$PLUGIN_PATH/hooks/geniro-statusline.js" "$HOME/.claude/hooks/geniro-statusline.js"
fi
```

This overwrites the previous stable copy in place; the path in `~/.claude/settings.json` continues to resolve correctly, so no settings edit is needed.

### 5. Confirm update

Report the new version and confirm the update was successful. No need to re-run `/geniro:setup` — the plugin provides agents, skills, and hooks globally, and your project's CLAUDE.md is project-specific content that doesn't change with plugin updates.
