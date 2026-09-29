# Update Phase 4 — Migration

Phase file for `/geniro:update`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/update/SKILL.md`.

**Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: update`, `LOAD_TIER: rules-only`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract. Phase 1's initial load is the only prior load; two phases of downloads, integrity checks, and snapshot diffs sit between it and this walk through every `MIGRATION.md` entry.

```bash
PLUGIN_PATH="<the path echoed by phase-2-update.md §Discover new plugin path>"
NEW_VERSION="<the version echoed by phase-2-update.md §Discover new plugin path>"

MIGRATION_FILE="$PLUGIN_PATH/MIGRATION.md"
if [ ! -f "$MIGRATION_FILE" ]; then
echo "[info] No MIGRATION.md in v$NEW_VERSION — skipping migration walk."
exit 0
fi
```

When MIGRATION.md is absent, there are no breaking changes to walk — skip the rest of Phase 4 and go straight to Phase Done (`${CLAUDE_PLUGIN_ROOT}/skills/update/done-final-report.md`).

Otherwise walk `$MIGRATION_FILE` — the copy just installed — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/migration-walk.md`, Read before the walk starts and echoed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`: the spine names the `N/A` guard but carries none of its mechanics, and the guard is what keeps an `Auto-detect:` value out of `bash -c`: it parses the entries, runs each `Auto-detect:` behind its `N/A` guard, and classifies each entry as applicable or not. Separately: an unresolved `PRIMARY_ROOT` — the Mode A resolver this phase also depends on — makes the tamper snapshot come back empty, which this skill then reports as "snapshot missing or empty", indistinguishable from a repo that never had user content. Log each not-affected entry as `skipped (not affected): <change-name>` and continue. This section owns the apply policy — what happens to an entry the helper classified as applicable.

For each applicable entry, first settle what `Fix it for me` would do — the `Auto-fix:` shape is defined in the shared walk §5:

- **Command** — run it via `bash -c` (same shell-safety reason as the detect).
- **Described edit** — the description (or, with no `Auto-fix:` field, the `Action required:` text) names an edit to files in this repo: drop an ID from `allow_patterns`, delete a stale frontmatter line. Make that edit yourself, on exactly the files the detect listed. A `.geniro/` state path is written through the helpers in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`, and an edit repeated across many files is one loop, not one call per file. On such an entry, `Manual-only` means no script ships for it — not that the run may not make the edit. A user who picks `Fix it for me` asked for exactly that edit, so printing the steps back to them is the failure. When the description leaves a choice to the user (drop a reference or re-point it; which IDs to keep), ask that choice with the detected lines in the question, then apply the answer.
- **Nothing to do here** — the action is `none required`, or it lives outside this repo: another session's plugin version, the global plugin registry, or an interactive skill run. Fire no AUQ, because a question whose recommended fix can only print text is a dead end. Log `noted: <change-name> — <the action, one line>`, carry it into the final report, and continue.

For a command or a described edit: **live-task guard, then AUQ.**

**Live-task guard (delete-class fixes only).** When the fix deletes files — a command containing `rm`, `-delete`, or `-exec rm`, or a described edit that removes files — and any detected path sits inside a task-dir (`.geniro/planning/<task-dir>/` or `.geniro/state/<skill>/<slug>/`), read each owning dir's `state.md` before building the AUQ: the task is live when `state.md` exists with a non-terminal `phase:`/`status:` (the same terminal-state test the session-start restore hook applies; when unsure, treat the task as live). A maintainer-written auto-fix matches paths mechanically and cannot know which task is mid-run — the walk supplies that check. Live-task paths are excluded from `Fix it for me` and named in the AUQ question; they re-detect as orphans once their task finishes. Never delete a live task's files even when the documented command would match them.

- **Question:** `Breaking change in v<X.Y.Z>: <change-name>. <Action required text>. Auto-detected N affected files: <first 10 lines truncated>` — when the guard excluded live-task paths, append `; <M> of these belong to a live task (<dir>: <phase/status>) and are excluded from the fix`.
- **Options:**
- `Fix it for me (Recommended)` — Apply the command or described edit settled above. When the guard excluded live-task paths, do NOT run the blanket documented fix — apply the same operation restricted to the orphan path set (narrowing the target set is the one sanctioned deviation; the operation itself stays as documented). After the fix, verify per the shared walk §6 — if still affected, warn and continue; paths the guard deliberately kept are expected to re-detect on a status-blind detector — log those as deferred-live, not as a fix failure.
- `Show me how to fix manually` — Print the `Action required:` text with exact commands; continue to next entry.
- `Skip for now` — Log skipped; continue to next entry.
- `Cancel migration walk` — Stop here; log remaining; terminate and emit final report.

After last entry: terminate and emit final report.

When the shared walk reports the file as malformed (§3 there), skip the rest of Phase 4 and emit its warning line here: `[warn] MIGRATION.md present but malformed — proceeding without walk`.

**Fix scope:** the entry is the spec, the detect output is the target set, and the §6 re-detect is the check. A command runs as written and a described edit is made as described. Widen neither the operation nor the file set — the change has to stay inside what the user was shown when they picked `Fix it for me`.
