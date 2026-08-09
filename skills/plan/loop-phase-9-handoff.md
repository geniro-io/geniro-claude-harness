# Phase 9 — Handoff

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

State.md `phase: handoff` during this phase. Non-interactive — no AskUserQuestion fires here; the release decision was the Phase 8 "Approve", and the spec is already written (Phase 6) and committed (§8.4) before this phase entered.

### 9.1 Print next-step command

1. **Determine the target path.** For milestone-sliced specs (Phase 5 milestone-mode fired): `.geniro/planning/<slug>/milestone-1.md`. Otherwise: `.geniro/planning/<slug>/spec.md`.
2. **Print a short closing message** stating where the plan is saved — and that it is committed, when §8.4's tracked-vs-ignored check took the tracked branch — plus the next-step command. E.g.: `Your plan is saved and committed at .geniro/planning/<slug>/spec.md. To build it, run: /geniro:implement .geniro/planning/<slug>/spec.md`. Do NOT auto-invoke /geniro:implement — printing the command leaves invocation entirely to the user (user agency).

### 9.2 Clean up transient working files

Before the terminal `phase:` write, remove this run's scratch outputs from the planning task-dir — the per-facet `.research-<facet>.md`, the Phase 4 `.research-critique-*.md`, the `.spec-challenge-out.md`, and any `notes.md`. They were each read once during planning and are dead weight now; left behind, they resurface as recurring `/geniro:update` migration-walk warnings (and in a milestone-sliced plan `/geniro:implement` runs in a different task-dir, so it never reaches these — this cleanup is the only one that does). Deleting `/geniro:plan`'s own scratch is not a source mutation, so it stays within the read-only-on-source boundary.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/clean-task-transients.sh"
clean_task_transients ".geniro/planning/<slug>"
```

The helper preserves the durable artifacts (`spec.md`, `state.md`, `plan-*.md`, `milestone-*.md`) and is a no-op on files that were never written, so the same call is safe on the `aborted` terminal path. Run it before every terminal `phase:` write (`done` and `aborted`). After it runs, echo `Cleaned up transient working files from .geniro/planning/<slug>`.

### 9.3 Terminal transition

Write state.md `phase: done` via `atomic_state_write`. SessionStart recovery treats it as completed; a session crashing between the §8.4 transition and the print resumes at `phase: handoff` and re-runs the print + cleanup + done write.
