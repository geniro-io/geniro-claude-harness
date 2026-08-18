<!-- Generated from skills/setup/phase-5-done.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Setup Phase 5 — Done

Phase file for `/geniro:setup`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`.

### 5.1 Final report

```
✓ /geniro:setup complete (init)

Wrote:
CLAUDE.md (45 lines — project-specific only)
.gitignore (updated .geniro/ ignores)

Detected:
Stack: node/npm + jest tests + ESLint
Default branch: main (auto-detected)

Next:
• Commit: git add CLAUDE.md
• Run a real task: /geniro:plan "your-task-here"
• Or browse skills: /geniro:investigate "what does /geniro:debug do?"
```

(re-run mode prepends a "Migration sweep" section listing applied auto-fixes and any manual-only items requiring user action, then a "Changed since last setup" section with the section-level diff summary.)

### 5.2 Offer to map the codebase

After printing the final report, ask the user if they want to map the codebase:

Use `AskQuestion` (header: `"Onboard"`):

- **Label:** `"Map codebase now (Recommended)"` / **Description:** `"Run /geniro:onboard to scan the codebase and produce _CODEBASE_MAP.md — gives all skills structural awareness of your project."`
- **Label:** `"Skip — I'll do it later"` / **Description:** `"You can run /geniro:onboard any time."`

Run §5.3 state file cleanup next regardless of the pick — the Definition of done requires it to run on every success path, not only "Skip" (§5.3 itself carries the one carve-out). Then: on "Map codebase now" → print `Running /geniro:onboard...` and invoke the onboard skill inline (same session, no restart needed); on "Skip" → done.

**Skip this AUQ in re-run mode** — the user already has a codebase map from a prior `/geniro:onboard` run (or chose to skip it). Re-run is for refreshing CLAUDE.md and running migrations, not re-onboarding.

### 5.3 State file cleanup

Delete `<PRIMARY_ROOT>/.geniro/state/setup/state.md`, then remove the now-empty `state/setup/` directory (ignore the failure when it is not empty) — unless `mode == re-run` AND the user opted for `accept-with-warnings` at round 4, in which case keep the state file instead, with `phase: done` and `## Open Questions` populated as a surface for the next re-run. Outside that one carve-out, this is the **only** Geniro state file deleted on success — the named exception recorded in §State file schema.

### 5.4 Restart-session warning (re-run only, plugin-version delta)

Fires only when `mode == re-run` AND the current `.claude-plugin/plugin.json` version differs from the `plugin_version:` recorded in the prior state file. Init runs write `plugin_version` fresh and never emit this. The warning text and the missing-field case are in `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` §5.4; Read the file here if this phase resumed after a compaction.

