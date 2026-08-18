<!-- Generated from skills/actions/subcommand-list.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Actions — `list` sub-command (Phase 2)

Sub-command body for `${CLAUDE_PLUGIN_ROOT}/skills/actions/SKILL.md`. Read on Phase-1 dispatch to `list`. The spine keeps the invariants, the anti-rationalization table, the tool surface and the termination mapping — this file carries the Steps.

## Phase 2: `list` sub-command

### Step 1 — Scan directory

Build the registry index per `${CLAUDE_PLUGIN_ROOT}/skills/actions/actions-reference.md` §Target resolution Step 1 (dual-glob local + main-worktree, deduped by absolute path, `local` wins, each row tagged `local` / `main-worktree`). Without this, list mode misses actions authored in the main worktree but absent from the current linked worktree.

### Step 2 — Present results

If the directory is missing or empty:

```
No custom actions found.

Run `/geniro:actions create <name>` to scaffold your first action,
e.g. `/geniro:actions create slack-release-ping`.
```

Otherwise, for each `.md` file, Read the frontmatter and extract `name`, `description`, `risk_class`, `created`. Tag each row with its `<source>` (`local` / `main-worktree`) from Step 1. Present a markdown table:

```
## Custom Actions

| Name | Description | Risk | Created | Source |
|------|-------------|------|---------|--------|
| daily-recap | Use when wrapping the day's commits + tests | low | 2026-04-12 | local |
| commit-and-pr-summary | Use when finalizing a PR before push | medium | 2026-04-18 | local |
| slack-release-ping | Use when posting a release note to #releases | high | 2026-04-15 | main-worktree |
```

Close with: "Run with `/geniro:actions run <name>`."
