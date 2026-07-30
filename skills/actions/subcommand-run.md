# Actions — `run` sub-command (Phase 4)

Sub-command body for `${CLAUDE_PLUGIN_ROOT}/skills/actions/SKILL.md`. Read on Phase-1 dispatch to `run`. The spine keeps the invariants, the anti-rationalization table, the tool surface and the termination mapping — this file carries the Steps.

## Phase 4: `run` sub-command

### Phase 4.1: Resolve, read, parse

Resolve the target via `${CLAUDE_PLUGIN_ROOT}/skills/actions/actions-reference.md` §Target resolution — it handles the empty-input, exact-slug, free-text and main-worktree-fallback cases and returns `<resolved-path>` / `<resolved-slug>` / `<source>`.

Read `<resolved-path>`. Parse frontmatter (`description`, `risk_class`, `model`, `allowed-tools`, `external-send`, `argument-hint`, `created`). Hold body steps in memory for Phase 4.3.

### Phase 4.2: No run-confirmation gate

`run` executes the action's steps directly regardless of `risk_class` — invoking `/geniro:actions run <slug>` IS the authorization, so re-asking "are you sure?" would only repeat a decision the user already made. Proceed straight to Phase 4.3. Scope of that authorization: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/approval-scope.md`. The five WAIT points that survive this rule are enumerated in SKILL.md loop invariant 3. `risk_class` stays as action metadata: it drives the `list` Risk column, the `delete` high-risk warning (Phase 6), the validate lint rules (Phase 7), and the L2 learning tag (Phase 4.4) — it never gates execution.

### Phase 4.3: Execute inline (tool-scope intersection)

Follow the action body's numbered steps directly, inline in the orchestrator (the inline-execution invariant). Pass extra positional `$ARGUMENTS` (after the action name) as input context under a "User-supplied input" heading.

**Tool-scope contract.** BEFORE running any step, intersect the action's frontmatter `allowed-tools` with the orchestrator's own `allowed-tools` ONCE and identify any step whose required tools fall outside the intersection. If gaps exist, surface them in a single AUQ before execution begins:

- **Question:** "The action declares N step(s) using tools outside this run's tool scope: [list step numbers + missing tools]. How should I proceed?"
- **Options:** `Skip the affected steps and run the rest` / `Cancel the run`

If no gaps, proceed without asking. Do not call any tool the action did not declare in `allowed-tools` — the intersection is the action author's stated tool budget. Do not re-prompt mid-execution — the up-front gate is the only tool-scope WAIT point.

**Scope checkpoint.** The action's own `## Steps` declare where its work belongs. Track what the run edits (the same changed-file list Phase 4.4 reports) and pause once — the first time the run edits production files outside the areas those steps name:

- **Question:** "This run has changed <N> files, including <the areas the action's steps don't mention>. How should I continue?"
- **Options:** `Keep going` / `Show me the diff first` / `Stop here, keep what's changed`

`Show me the diff first` renders the diff and re-fires this same question, so the user decides with the diff in view — the one-pause cap counts triggers, not re-renders. `Stop here, keep what's changed` halts execution with the edits left in place and goes to Phase 4.4: print the wrap-up summary, including its `/geniro:review` recommendation, before the terminal transition — the run that most needs an independent look is the one that must not exit silently.

One such trigger per run at most — a second prompt gets less attention than the first, not more — and it is declaration-relative: what the action names versus what the run touched. The count is reported, never the trigger; no number of edits fires this on its own.

**Persistent-path write routing.** When an action step writes to `.geniro/instructions/`, `.geniro/actions/`, or `.geniro/workflow/` via a relative path, resolve the target against `$PRIMARY_ROOT`, recomputed via the Mode A snippet inside the Bash call performing the write — these three families are persistent user-authored content that must survive worktree removal, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`. Task-local writes (`.geniro/planning/`, `.geniro/state/`) stay cwd-relative. Writes still route through the atomic helpers where the state-helper hook requires them.

If a step has a `[AUQ]` or `## Confirm:` annotation, fire AUQ at that step. On non-zero exit or tool failure → halt; transition to `failed` with step number captured.

### Phase 4.4: Wrap-up + record a learning

Print summary:

```
Action `<resolved-slug>` complete.

Steps run: <count>
Steps skipped: <list, or "none">
Files changed: <list, or "none">
External calls: <list, or "none">
```

When the scope checkpoint fired (Phase 4.3), close the summary by recommending an independent look at the diff: "This run went past what the action describes — `/geniro:review` reviews the diff before you push." Recommend it, never run it — `/geniro:actions` spawns no subagent and calls no other skill (the inline-execution invariant); the user decides whether to run it.

**L2 emit on successful external-send run:** if the action's frontmatter declared `external-send: true` AND run succeeded, emit one L2 `discovery` row

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
emit_learning <<'EOF'
{
"type": "discovery",
"trust": "verified",
"skill": "actions",
"tags": ["actions", "run", "<risk_class>"],
"summary": "ran <slug> (risk=<risk_class>, external=true)",
"entry": {"slug": "<slug>", "side_effects": [...]}
}
EOF
```

After a successful emit, echo `Recorded learning: <summary>` to the user, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract" — the helper writes silently, so the echo is the only signal the run was recorded.

Else: no emit (most action runs are not novel-discovery events).
