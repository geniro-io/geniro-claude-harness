<!-- Generated from skills/update/phase-2-update.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Update Phase 2 — Update

Phase file for `/geniro:update`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/update/SKILL.md`.

### Step 1 — Marketplace refresh + plugin update (exponential backoff)

Run the marketplace update, then the plugin update, each retried up to 4× on network error with 2s / 4s / 8s / 16s backoff between attempts; abort with a non-zero exit if either still fails after the 4th attempt (Termination case: network error after 4 retries):

1. `claude plugin marketplace update geniro-claude-harness`
2. `claude plugin update geniro@geniro-claude-harness --scope user`

Pass `--scope user` explicitly. The plugin is meant to be available in every directory, which is the user (global) scope — the install record that the global `enabledPlugins` entry in `settings.json` resolves against. Updating without the flag lets the CLI target whichever scope matches the current working directory; when a project-scoped install record exists for the cwd, the user-scope record gets dropped and the plugin then loads only in that one project (it disappears everywhere else). Pinning the scope keeps the global install authoritative.

### Step 1.5 — Restore the global install if it went missing

After the update, confirm a `user`-scope install record still exists. A prior update run (before the `--scope user` pin) may have left the plugin project-scoped only — in which case it loads nowhere except that one project. Re-install at user scope to repair it:

```bash
REGISTRY="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"

HAS_USER_SCOPE=$(python3 -c "
import json
try:
    d = json.load(open('$REGISTRY'))
    entry = d['plugins'].get('geniro@geniro-claude-harness', [])
    print('yes' if any(e.get('scope') == 'user' for e in entry) else 'no')
except Exception:
    print('unknown')
")

if [ "$HAS_USER_SCOPE" = "no" ]; then
  echo "[repair] no global install record found — restoring user-scope install so the plugin loads in every directory." >&2
  claude plugin install geniro@geniro-claude-harness --scope user 2>&1 | tee /tmp/geniro-plugin-repair.log || true
fi
```

When the repair runs, tell the user in plain English that the plugin's global install was restored — it had been left available in only one project, and is now back in every directory.

### Step 2 — Discover new plugin path

```bash
# CURRENT_VERSION cannot be re-read: plugin.json now holds the NEW version, so
# substitute the literal value phase-1-precheck.md §Read current version read.
REGISTRY="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
CURRENT_VERSION="<the version read by phase-1-precheck.md §Read current version>"

if [ ! -f "$REGISTRY" ]; then
echo "ERROR: registry not found at $REGISTRY — abort." >&2
echo "Hint: if you use a custom config dir, ensure CLAUDE_CONFIG_DIR is exported." >&2
exit 1
fi

PLUGIN_PATH=$(python3 -c "
import json, sys
try:
    d = json.load(open('$REGISTRY'))
    entry = d['plugins'].get('geniro@geniro-claude-harness', [])
    # Prefer the user-scope (global) install — the one this skill keeps authoritative.
    # Fall back to the first record only if no user-scope entry exists.
    chosen = next((e for e in entry if e.get('scope') == 'user'), entry[0] if entry else None)
    print(chosen['installPath'] if chosen else '')
except Exception as e:
    print(f'PARSE_ERROR: {e}', file=sys.stderr)
    sys.exit(1)
")

if [ -z "$PLUGIN_PATH" ]; then
echo "ERROR: registry parsed but no entry for the geniro plugin — abort." >&2
exit 1
fi

NEW_VERSION=$(cat "$PLUGIN_PATH/.claude-plugin/plugin.json" \
| python3 -c "import json,sys; print(json.load(sys.stdin).get('version','unknown'))")

if [ "$NEW_VERSION" = "$CURRENT_VERSION" ]; then
echo "[info] already on latest version (v$NEW_VERSION) — nothing to do."
# Same refresh as phase-3-postcheck.md §Refresh update cache. The status line renders straight from this cache and
# nothing else rewrites it before the next session start — exiting without it leaves the
# "update available" arrow lit for the rest of the session, in the run meant to clear it.
GENIRO_UPDATE_BG=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_PATH" \
node "$PLUGIN_PATH/hooks/geniro-check-update.js"
exit 0
fi

echo "PLUGIN_PATH=$PLUGIN_PATH"
echo "NEW_VERSION=$NEW_VERSION"
```

Carry both echoed values forward by literal substitution: every later fenced block re-assigns them at its top, because each Bash call runs in a fresh shell and nothing else recomputes them.

Transition to Phase 3.

