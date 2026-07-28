# Visual plan artifact — publish and call sites

A conditional file of the `/geniro:plan` loop (spine: `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`). Read it at §1.5 only when state.md carries `artifact_mode: true`; on a run without artifact mode every **Artifact** line in the phase files is a silent no-op and this file is never loaded.

**Visual plan artifact — first publish.** When `artifact_mode: true`, build the live page now so it grows from the first phase: `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Availability detection & create`, passing the task-dir, the plan title, and the planning-journey stops. After it returns, persist the result via `atomic_state_write` per the helper's § URL persistence; when no `claude.ai` URL comes back, record the page unavailable per its § Unavailable / skip handling — every call in the table below then skips for the rest of the run. Skip this whole step when `artifact_mode` is unset.

**Artifact call sites — the shared rule.** Every later artifact call runs only when `artifact_mode: true` AND the page is not recorded unavailable (`artifact_status` is not `unavailable`); skip silently otherwise. Each call reads the saved `artifact_url` from state.md frontmatter when present, so a resumed/compacted session revises the same page rather than publishing a duplicate. Use the verbatim invocation string for the call's kind in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md` § Caller contract, passing the `PHASE:` and the content this table names. At a Before-gate site the chat render stays the primary surface — the panel only mirrors the pending decision.

The sites, in loop order — a site missing from this table is an artifact update silently skipped, so keep it in lockstep with the phase files:

| Site | Kind (`PHASE:`) | Content |
|---|---|---|
| §3.4 before the grill checkpoint question | Before-gate (`clarify`) | the pending checkpoint decision; refresh here only, never per grill question |
| §3.4 on grill termination | Update (`clarify`) | the decision log |
| §4.3 before the approach question | Before-gate (`approach`) | approach write-ups, stress-test evidence, data-flow diagram |
| §4.4 after the approach pick persists | Update (`approach`) | chosen approach + considered alternatives |
| §5.2 step 1, before each cluster gate | Before-gate (`sections`) | the cluster's section digests + steps-flow diagram |
| §5.2 Revise path, after re-authoring | Before-gate (`sections`) | the revised sections — refresh the panel, don't blank it; the gate is being re-presented |
| §5.2 step 5, after a cluster's picks persist | Update (`sections`) | that cluster's approved sections |
| §6.1 after spec.md is written | Update (`spec`) | steps / validation / done conditions |
| §8.2 before the final-approval question | Before-gate (`approval`) | the pending approval decision, per option |
| §8.4 step 5 after approval | Update (`approval`) | approved state — status badge approved, every tracker stop done |
