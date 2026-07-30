# Actions — `validate` sub-command (Phase 7)

Sub-command body for `${CLAUDE_PLUGIN_ROOT}/skills/actions/SKILL.md`. Read on Phase-1 dispatch to `validate`. The spine keeps the invariants, the anti-rationalization table, the tool surface and the termination mapping — this file carries the Steps.

## Phase 7: `validate` sub-command

### Step 1 — Resolve scope

When validating all actions (no `<slug>` provided), build the registry per `${CLAUDE_PLUGIN_ROOT}/skills/actions/actions-reference.md` §Target resolution Step 1 (dual-glob local + main-worktree, deduped, `local` wins, source-tagged). Without this, validate run from a linked worktree misses primary-worktree actions and produces a false-pass.

If `<slug>` provided: resolve via §Target resolution Steps 1-3 to get `<resolved-path>` and `<source>`, then validate only that single file. Else validate the deduped union from the dual-glob above. Read-only; never mutates.

### Step 2 — Lint rule set

Run `${CLAUDE_PLUGIN_ROOT}/skills/actions/actions-reference.md` §Validation gate once per file in scope — same checks and severities the create gate uses. `validate` never writes, so the gate's entry-mode rollback does not apply here; collect the rows and report them.

Then add these validate-only rows:

| Check | Severity |
|---|---|
| `description:` passes the three rules in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/description-quality.md` — that file is the shared source for these rows and their severity | LOW |
| `allowed-tools:` field present (if action mutates) | LOW |
| No references to dropped skills in body | HIGH |

Dropped-skill ref check uses the list: `/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`.

### Step 3 — Output format

```
$ /geniro:actions validate

Validation results: 3 actions checked, 1 issue found.

✓ daily-recap.md (local) no issues
⚠ slack-release-ping.md (main-worktree) 1 HIGH
└── Line 4: risk_class missing — REQUIRED field
✓ commit-and-pr-summary.md (local) no issues

To fix: /geniro:actions edit slack-release-ping
```

Exit non-zero if any CRITICAL or HIGH. MEDIUM / LOW are warnings.
