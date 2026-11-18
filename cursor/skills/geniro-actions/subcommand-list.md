<!-- Generated from skills/actions/subcommand-list.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Actions — `list` sub-command (Phase 2)

Sub-command body for `${CLAUDE_PLUGIN_ROOT}/skills/actions/SKILL.md`. Read on Phase-1 dispatch to `list`. The spine keeps the invariants, the anti-rationalization table and the termination mapping — this file carries the Steps.

## Phase 2: `list` sub-command

**Tool surface.** Allowed: `Read`, `Glob`, `Bash(ls...)`, `AskQuestion`. Forbidden: `Write`, `Edit`, `Agent`, `mcp__*`.

### Step 1 — Scan directory

Build the registry index per `${CLAUDE_PLUGIN_ROOT}/skills/actions/actions-reference.md` §Target resolution Step 1 (the main checkout's `.geniro/actions/`).

### Step 2 — Present results

If the directory is missing or empty:

```
No custom actions found.

Run `/geniro:actions create <name>` to scaffold your first action,
e.g. `/geniro:actions create slack-release-ping`.
```

Otherwise, for each `.md` file, Read the frontmatter and extract `name`, `description`, `risk_class`, `created`. Present a markdown table:

```
## Custom Actions

| Name | Description | Risk | Created |
|------|-------------|------|---------|
| daily-recap | Use when wrapping the day's commits + tests | low | 2026-04-12 |
| commit-and-pr-summary | Use when finalizing a PR before push | medium | 2026-04-18 |
| slack-release-ping | Use when posting a release note to #releases | high | 2026-04-15 |
```

Close with: "Run with `/geniro:actions run <name>`."
