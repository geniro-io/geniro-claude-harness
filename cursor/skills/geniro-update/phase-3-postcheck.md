<!-- Generated from skills/update/phase-3-postcheck.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Update Phase 3 — Post-check

Phase file for `/geniro:update`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/update/SKILL.md`.

### Step 1 — Plugin file hash-check (sanity mode)

If the new plugin publishes `$PLUGIN_PATH/.claude-plugin/manifest.sha256`, verify each file via `sha256sum -c` (or `shasum -a 256 -c` on macOS, which ships no `sha256sum`). Otherwise (no manifest published), sanity-check that key files exist:

```bash
PLUGIN_PATH="<the path echoed by phase-2-update.md §Discover new plugin path>"

HASH_FAIL=0
MISSING=()
for f in \
"$PLUGIN_PATH/skills/_shared/load-custom-instructions.md" \
"$PLUGIN_PATH/skills/_shared/spawn-agent.md" \
"$PLUGIN_PATH/skills/implement/SKILL.md" \
"$PLUGIN_PATH/skills/setup/SKILL.md" \
"$PLUGIN_PATH/hooks/geniro-check-update.js"; do
[ -f "$f" ] || { MISSING+=("$f"); HASH_FAIL=1; }
done
[ -d "$PLUGIN_PATH/agents" ] && [ "$(ls -A "$PLUGIN_PATH/agents" | wc -l)" -gt 0 ] \
|| { MISSING+=("$PLUGIN_PATH/agents/ (empty or missing)"); HASH_FAIL=1; }
```

If `HASH_FAIL=1`, fire AUQ (Cancel-as-recommended — a hash-check failure means the download may be corrupted or tampered, so default the user to Cancel):

- **Question:** `Integrity check failed — ${MISSING[*]}. Continue anyway?`
- **Options:**
- `Abort` — Exit without continuing; investigate (Recommended)
- `Continue anyway (not recommended)` — Proceed with possibly broken install

### Step 2 — User-content survival check

Re-resolve `PRIMARY_ROOT` by running the same Mode A resolver in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` used in `phase-1-precheck.md` §Resolve `$PRIMARY_ROOT` and snapshot user content — Bash environments don't persist across phases (the AUQ + plugin-update step runs in separate shell invocations). The post-update snapshot must scan the same tree as the pre-update one, and must be computed by the same code, or the diff is meaningless. Paste the §User-content snapshot definitions into this call and pass the re-resolved `PRIMARY_ROOT` — that recomputes the baseline's filename and reads it back.

```bash
# PRIMARY_ROOT is set by the Mode A resolver, which runs inside THIS Bash call.
# --- paste the definitions from ${CLAUDE_PLUGIN_ROOT}/skills/update/user-content-snapshot.md here ---

USER_SNAPSHOT=$(cat "$(_gu_snapshot_file "$PRIMARY_ROOT")" 2>/dev/null)
CURRENT_SNAPSHOT=$(_gu_snapshot "$PRIMARY_ROOT")

if [ -z "$USER_SNAPSHOT" ]; then
echo "[info] pre-update snapshot missing or empty — skipping tamper diff (cannot compare against a baseline that was never recorded)."
elif [ "$USER_SNAPSHOT" != "$CURRENT_SNAPSHOT" ]; then
diff <(printf '%s\n' "$USER_SNAPSHOT") <(printf '%s\n' "$CURRENT_SNAPSHOT") > /tmp/geniro-content-diff.log
# Fire AUQ below.
fi
```

If diff non-empty, render it to chat first — the affected-files list and the diff itself (full diff at `/tmp/geniro-content-diff.log` if too long to inline) — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, in the visual language of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md`. Then fire a lean AUQ:

- **Question:** `User content under .geniro/instructions/ or .geniro/actions/ changed during the update — review the diff above before continuing.`
- **Options:**
- `Continue to migration walk` — Proceed; the change stays as shown
- `Abort — preserve current state` — Exit; investigate manually (Recommended)

### Step 3 — Refresh update cache

```bash
PLUGIN_PATH="<the path echoed by phase-2-update.md §Discover new plugin path>"

GENIRO_UPDATE_BG=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_PATH" \
node "$PLUGIN_PATH/hooks/geniro-check-update.js"
```

This writes `update_available: false` to the cache with the new installed version — the source that clears the "update available" indicator. Record the outcome for the final report's `Update cache` line.

### Step 4 — Refresh statusline stable copy (conditional)

Only when `$CLAUDE_USER_DIR/hooks/geniro-statusline.js` already exists, overwrite it from `$PLUGIN_PATH/hooks/geniro-statusline.js`. Its absence means the user never ran `/geniro:setup` or has no `statusLine` settings entry — creating the file there would install a statusline they never asked for. Claude Code accepts a `statusLine` command only from user or project settings, so the plugin's own bundled `settings.json` cannot activate the statusline directly — the user-config copy this step refreshes is what makes it live. Record the outcome for the final report's `Statusline` line.

### Step 5 — Re-point the Cursor CLI skill links (conditional)

Only when `$HOME/.cursor/skills/` already holds `geniro-*` symlinks, re-run `bash "$PLUGIN_PATH/scripts/install-cursor-skills.sh"`. Their absence means the user never opted into that workaround, and creating them here would install skills into a Cursor profile they never asked to touch.

The script normally links to a path with no version in it — a checkout, or the marketplace checkout — and those links need nothing after an update, so this step is usually a no-op. It earns its place in the case that is left: links that do carry a version (no marketplace checkout was available when they were made) resolve to the old plugin after an update, or to nothing once that version is cleaned up. Re-running re-points them. Record the outcome for the final report's `Cursor CLI skills` line.

Transition to Phase 4.

