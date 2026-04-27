---
name: geniro:cleanup
description: "Use when uninstalling the plugin from this project. Removes all geniro-claude-plugin files; preserves user-created files via plugin state; confirms before any deletion."
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

**If found:** parse the `files.generated` and `files.user_created` arrays — these tell you which files the plugin generated versus which the user created. Also check the top-level `mode` field: if `mode == "vendored"`, parse the `vendor.file_manifest` array (vendored files that must be removed) and `vendor.settings_backup` (path to the pre-vendor `.claude/settings.json` backup to restore).

**If not found:** fall back to heuristic detection — the plugin generates files in `.geniro/` and optionally `CLAUDE.md` at root:

```bash
# List all files inside .geniro/
find .geniro/ -type f 2>/dev/null
```

A file is **plugin-owned** if it lives in `.geniro/` or is listed in 1.2.
A file is **user-created** if it exists in `.geniro/` but is not a known plugin file.

### 1.2 Build deletion manifest

The plugin generates these files in the project:

1. **Plugin runtime** (will be removed entirely): `.geniro/` directory
2. **Vendored overlay** (only if `mode == "vendored"` in state file): every `dst` path listed in `vendor.file_manifest` — these are the files `/geniro:vendor` copied into `.claude/skills/geniro-*`, `.claude/agents/geniro-*`, and `.claude/hooks/geniro-*`. Remove each by its `dst` path.
3. **Settings restore** (only if `mode == "vendored"` and `vendor.settings_backup` exists): restore `.claude/settings.json` from the backup path stored in `vendor.settings_backup`, then delete the backup. If the backup does not exist, delete any `.claude/settings.json` that contains only vendored hooks (sha-match against the vendored hooks block); otherwise leave it alone and warn the user.
4. **User-created files** (will be preserved): any non-plugin files in `.geniro/` (e.g., user-added workflow files)

Also check for plugin-generated entries in other files:
- `CLAUDE.md` at project root — check geniro-state `files.generated` for `CLAUDE.md`. If listed, it was plugin-generated. If no geniro-state, check if the first line contains `# Geniro Plugin` or `# Geniro Harness Plugin` (legacy header).
- `.gitignore` — check for `.geniro/` entry added by setup

## Phase 2: Confirm with User

Present the deletion manifest clearly:

```
## Files to remove

### Plugin runtime
- .geniro/ (entire directory)

### Vendored overlay (only if mode == "vendored")
- N files under .claude/skills/geniro-*
- M files under .claude/agents/geniro-*
- K files under .claude/hooks/geniro-*
- .claude/settings.json restored from .claude/settings.json.pre-vendor-backup

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

Execute deletion in order. Prefer `rm -f` for individual files and `rmdir` for empty directories for precise, auditable removal.

### 3.1 Remove plugin runtime directory

Remove `.geniro/` contents file-by-file, then remove empty directories:

```bash
# Remove all files inside .geniro/ recursively, then empty dirs
find .geniro/ -type f -delete 2>/dev/null
find .geniro/ -type d -empty -delete 2>/dev/null
```

### 3.1.5 Remove vendored overlay (only if `mode == "vendored"`)

If the state file had `mode: "vendored"`, remove every file listed in `vendor.file_manifest` by its `dst` path. Use per-file `rm -f` (never `rm -rf`) and trust the manifest — do NOT bolt on `find -delete` safety nets. A `find ... -name 'geniro-*' -delete` would happily delete user-authored files that happen to match the pattern, or files from a different vendored copy than the one tracked in the manifest, defeating the whole point of keeping a manifest. If the manifest is incomplete, that is a bug in `/geniro:vendor` and belongs there, not here.

```bash
# Remove every file listed in the vendor file_manifest
# (each manifest entry has a dst path; use per-file rm -f, never rm -rf)
python3 <<'PY'
import json, pathlib
state = json.loads(pathlib.Path(".geniro/.geniro-state.json").read_text())
for entry in state.get("vendor", {}).get("file_manifest", []):
    p = pathlib.Path(entry["dst"])
    if p.exists() and p.is_file():
        p.unlink()
PY

# Collapse empty directories left behind (safe: only removes empty dirs, never files)
find .claude/skills -type d -name 'geniro-*' -empty -delete 2>/dev/null
```

Restore `.claude/settings.json` from `vendor.settings_backup` if the backup exists:

```bash
if [ -f "$VENDOR_SETTINGS_BACKUP" ]; then
  mv "$VENDOR_SETTINGS_BACKUP" .claude/settings.json
fi
```

If the backup does not exist and `.claude/settings.json` contains ONLY the vendored hooks (no user hooks), remove the file. Otherwise, warn the user that manual cleanup of `.claude/settings.json` hook entries may be needed.

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

If the state file had `mode == "vendored"`, the marketplace plugin may already have been uninstalled by the user after vendoring (per the `/geniro:vendor` Phase 7 instructions). Running `claude plugin uninstall` in that case is a no-op — still run the command, still tolerate failure.

```bash
claude plugin uninstall geniro-claude-plugin@geniro-claude-harness
```

If the uninstall command fails (e.g., plugin already removed, not installed, or the project was vendored and the marketplace plugin was uninstalled earlier), report the error but do not treat it as a cleanup failure — the project files have already been removed successfully.

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
