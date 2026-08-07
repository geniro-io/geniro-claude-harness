# Update Phase 4 — Migration

Phase file for `/geniro:update`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/update/SKILL.md`.

```bash
PLUGIN_PATH="<the path echoed by phase-2-update.md §Discover new plugin path>"
NEW_VERSION="<the version echoed by phase-2-update.md §Discover new plugin path>"

MIGRATION_FILE="$PLUGIN_PATH/MIGRATION.md"
if [ ! -f "$MIGRATION_FILE" ]; then
echo "[info] No MIGRATION.md in v$NEW_VERSION — skipping migration walk."
exit 0
fi
```

When MIGRATION.md is absent, there are no breaking changes to walk — skip the rest of Phase 4 and go straight to the Done — Final report below.

Otherwise walk `$MIGRATION_FILE` — the copy just installed — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/migration-walk.md`, Read before the walk starts and echoed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`: the spine names the `N/A` guard but carries none of its mechanics, and the guard is what keeps an `Auto-detect:` value out of `bash -c`. The same applies to the `PRIMARY_ROOT` Mode A resolver this phase depends on — an unresolved `PRIMARY_ROOT` makes the tamper snapshot come back empty, which this skill then reports as "snapshot missing or empty", indistinguishable from a repo that never had user content: it parses the entries, runs each `Auto-detect:` behind its `N/A` guard, and classifies each entry as applicable or not. Log each not-affected entry as `skipped (not affected): <change-name>` and continue. This section owns the apply policy — what happens to an entry the helper classified as applicable.

For each applicable entry: **live-task guard, then AUQ.**

**Live-task guard (delete-class entries only).** When the entry's `Auto-fix:` is delete-class (contains `rm`, `-delete`, or `-exec rm`) and any detected path sits inside a task-dir (`.geniro/planning/<task-dir>/` or `.geniro/state/<skill>/<slug>/`), read each owning dir's `state.md` before building the AUQ: the task is live when `state.md` exists with a non-terminal `phase:`/`status:` (the same terminal-state test the session-start restore hook applies; when unsure, treat the task as live). A maintainer-written auto-fix matches paths mechanically and cannot know which task is mid-run — the walk supplies that check. Live-task paths are excluded from `Fix it for me` and named in the AUQ question; they re-detect as orphans once their task finishes. Never delete a live task's files even when the documented command would match them.

- **Question:** `Breaking change in v<X.Y.Z>: <change-name>. <Action required text>. Auto-detected N affected files: <first 10 lines truncated>` — when the guard excluded live-task paths, append `; <M> of these belong to a live task (<dir>: <phase/status>) and are excluded from the fix`.
- **Options:**
- `Fix it for me (Recommended)` — Run the `Auto-fix:` commands from the MIGRATION.md entry via `bash -c` (same shell-safety reason as the detect). When the guard excluded live-task paths, do NOT run the blanket documented command — apply the same operation restricted to the orphan path set (narrowing the target set is the one sanctioned deviation; the operation itself stays as documented). If the entry's `Auto-fix:` value begins with `manual-only` (matched case-insensitively, so `Manual-only` is caught too) or the field is absent, fall back to printing the manual instructions and continue. After the fix, verify per the shared walk §6 — if still affected, warn and continue; paths the guard deliberately kept are expected to re-detect on a status-blind detector — log those as deferred-live, not as a fix failure.
- `Show me how to fix manually` — Print the `Action required:` text with exact commands; continue to next entry.
- `Skip for now` — Log skipped; continue to next entry.
- `Cancel migration walk` — Stop here; log remaining; terminate and emit final report.

After last entry: terminate and emit final report.

When the shared walk reports the file as malformed (§3 there), skip the rest of Phase 4 and emit its warning line here: `[warn] MIGRATION.md present but malformed — proceeding without walk`.

**Auto-fix safety:** each `Auto-fix:` command is written by the plugin maintainer and tested, so "Fix it for me" runs those commands and nothing else — an improvised fix is untested against the install it is about to mutate.
