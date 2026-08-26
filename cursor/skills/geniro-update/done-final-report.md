<!-- Generated from skills/update/done-final-report.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Update — Done: final report

Phase file for `/geniro:update`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/update/SKILL.md`.

`/geniro:update` always emits the restart warning — a version transition leaves in-memory skill bodies pointing at the old version until the session restarts. The `/geniro:setup` re-run recommendation is **conditional**: `/geniro:setup`'s only work `/geniro:update` has not already done is regenerate the project CLAUDE.md (its `.geniro/` migration sweep re-walks the same MIGRATION.md entries Phase 4 just walked), so recommend it only when the run leaves setup-relevant work.

Recommend `/geniro:setup` (append the re-setup section below) when ANY of these hold:

- Phase 4 surfaced at least one applicable MIGRATION.md entry — any entry whose `Auto-detect:` returned non-empty for this install (i.e. you fired its AUQ). Applied, deferred, or skipped, that work still needs follow-through.
- The major (first) version component increased (e.g. `2.13.0 → 3.0.0`). A major release can refresh CLAUDE.md's project sections (stack, commands, conventions) without any per-entry `Auto-detect:` firing, so CLAUDE.md may be stale even at zero applicable entries.
- The Phase 3 user-content survival diff reported `CHANGED`.

Otherwise — a clean minor/patch transition with no applicable entries, no major bump, and user content intact — emit the restart warning alone. Appending a step to regenerate an already-current CLAUDE.md is empty friction.

### Final report

Emit the report below. When none of the three conditions above hold (a clean minor/patch transition), drop the final paragraph — everything from "After restart, run /geniro:setup" onward — and end at the restart warning.

```
✓ /geniro:update complete.

Updated: v<CURRENT_VERSION> → v<NEW_VERSION>
Plugin path: <PLUGIN_PATH>
Integrity check: <PASS | WARN>
User content: <UNCHANGED | CHANGED — see /tmp/geniro-content-diff.log>
Update cache: <refreshed | refresh failed — "update available" may still show>
Statusline: <refreshed | not installed — no prior /geniro:setup>
Cursor profile: <re-pointed at the new install | not installed — nothing to refresh>
Migration walked: <N changes — M applied, K skipped, L deferred>

⚠ Restart your Claude Code session to load v<NEW_VERSION>.
   Claude Code resolves ${CLAUDE_PLUGIN_ROOT} once at session start — in-memory
   skill bodies still point at v<CURRENT_VERSION> until you restart.

After restart, run /geniro:setup — re-run mode will:
   • Auto-migrate your .geniro/ directory (rename files, add missing fields) — safe mechanical fixes apply silently; destructive cleanups like orphan deletion are surfaced for your review, not auto-applied, so anything you deferred in this walk is never silently reversed
   • Regenerate CLAUDE.md's project sections (stack, commands, conventions)
   • Preserve your custom instructions, actions, and knowledge

If you have multiple repos with .geniro/, run /geniro:setup in each one after restart.
```

