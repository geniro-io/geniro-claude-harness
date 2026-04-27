---
name: geniro:update
description: "Use when the status line shows a plugin update is available, or to manually pull the latest geniro-claude-plugin version."
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

After a successful update, the plugin install path changes (new version directory). Discover the new path first — subsequent steps need it. Honor `CLAUDE_CONFIG_DIR` so users with a relocated config dir resolve to the right `installed_plugins.json`:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REGISTRY="$CLAUDE_USER_DIR/plugins/installed_plugins.json"
if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: plugin registry not found at $REGISTRY" >&2
  echo "Hint: if you use a custom config dir, ensure CLAUDE_CONFIG_DIR is exported before running Claude Code." >&2
  exit 1
fi
# Bash expands $REGISTRY before python parses the script — do not refactor to read it from python's env.
PLUGIN_PATH=$(python3 -c "import json,sys; d=json.load(open('$REGISTRY')); p=d['plugins'].get('geniro-claude-plugin@geniro-claude-harness',[]); print(p[0]['installPath'] if p else '')")
```

If `$PLUGIN_PATH` is empty, the registry parsed but contained no entry for this plugin — stop and report the registry path. Do NOT fall back to `${CLAUDE_PLUGIN_ROOT}` (it points at the old version in this session). If python prints a stack trace (malformed JSON, schema change), surface it to the user — that's the diagnostic.

### 4. Refresh update cache

Re-run the update check using the **new** plugin path (NOT `${CLAUDE_PLUGIN_ROOT}` — it still points to the old version in this session). Guard against an empty `$PLUGIN_PATH` so a registry-discovery miss in Step 3 doesn't silently cascade into running `node "/hooks/..."`:

```bash
if [ -z "$PLUGIN_PATH" ]; then
  echo "ERROR: PLUGIN_PATH is empty — Step 3 did not resolve a new plugin install. Stop here." >&2
  exit 1
fi
GENIRO_UPDATE_BG=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_PATH" node "$PLUGIN_PATH/hooks/geniro-check-update.js"
```

This writes `update_available: false` to the cache with the correct installed version. Using `${CLAUDE_PLUGIN_ROOT}` here would read the old `plugin.json` and leave the cache stale.

### 4.1 Refresh statusLine script

Refresh the stable user-level copy of the statusline script only if it already exists — its presence indicates the user ran `/geniro:setup` and has a `statusLine` entry in their settings file pointing at `<config-dir>/hooks/geniro-statusline.js`. If the stable copy is absent, skip this step: the plugin's bundled `settings.json` already exposes the statusline via `${CLAUDE_PLUGIN_ROOT}` (which now points at the new version), so no refresh is needed. Creating `<config-dir>/hooks/geniro-statusline.js` here without a corresponding settings entry would be a stray file the user never asked for — `/geniro:setup` is the single source of truth for installing that entry.

`$CLAUDE_USER_DIR` was resolved in Step 3 (`${CLAUDE_CONFIG_DIR:-$HOME/.claude}`); reuse it so users with a relocated config dir hit the right path:

```bash
if [ -f "$CLAUDE_USER_DIR/hooks/geniro-statusline.js" ]; then
  mkdir -p "$CLAUDE_USER_DIR/hooks"
  cp "$PLUGIN_PATH/hooks/geniro-statusline.js" "$CLAUDE_USER_DIR/hooks/geniro-statusline.js"
fi
```

This overwrites the previous stable copy in place; the path in the user's `settings.json` continues to resolve correctly, so no settings edit is needed.

### 5. Confirm update — and tell the user to restart their session

Report the new version. Then explicitly tell the user:

> **Restart your Claude Code session before using any other geniro skill.** Claude Code resolves `${CLAUDE_PLUGIN_ROOT}` once at session start and never refreshes it mid-session. Until you restart, every skill (including `/geniro:setup`, `/geniro:implement`, `/geniro:review`, etc.) keeps reading files from the old plugin install path — even though the new version is on disk. The cache and statusline copy were refreshed above, but in-memory skill bodies cannot be refreshed without a session restart.

No need to re-run `/geniro:setup` after restart — the plugin provides agents, skills, and hooks globally, and your project's CLAUDE.md is project-specific content that doesn't change with plugin updates.
