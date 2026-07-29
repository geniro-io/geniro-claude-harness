# Phase 7.5 — Spec challenge

A phase file of the `/geniro:plan` loop. The spine — HARD-GATE, gate presentation contract, echo contract, phase order, terminal states, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`.

State.md `phase: spec-challenge` during this phase. **Fires only when the Phase 1.2 effort tier is Big OR state.md has `deep-mode: true`** (the §7.4 branch); on a standard Trivial/Small/Medium run the loop transitions validator → `phase: user-approve` directly. Entered after the Phase 7 validator passes (or its hard-fails were user-accepted) and before the Phase 8 approval AUQ. At entry the spec is: full text on disk, validator-clean, uncommitted, `lifecycle: draft`.

Surface a one-line plain-English note before invoking: "Challenging the spec before you approve it...".

### 7.5.1 Invoke the challenge helper

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` with MODE: plan, SPEC_PATH: `<task-dir>/spec.md`, TASK_DIR: `<task-dir>`, EFFORT_TIER: `<the tier detected in Phase 1.2>`, DEEP: `<true when state.md deep-mode: true, else false>`.

The helper runs VERIFY (one verifier per `file:line`-cited claim) + generate-ALTERNATIVES + RED-TEAM + SYNTHESIZE, and returns a verdict: `keep` / `keep-with-modifications` / `re-plan`.

On standard Trivial/Small/Medium runs this pass is skipped — `/geniro:implement` runs the same fact-check helper pre-edit on every spec-driven run, so cited-claim verification still happens before any code is written; the plan-side pass adds value where approval-time stakes are highest (Big tier) or the user asked for depth (`--deep`). Once it fires, cost stays bounded because the helper verifies only `file:line`-cited claims.

### 7.5.2 Verdict handling

- **keep** (clean) — surface a one-line advisory note (top challenge observation, if any) and transition `phase: user-approve` to Phase 8.
- **keep-with-modifications** — fold the helper's must-fixes into the spec by reusing the Phase 6 re-author → overwrite-via-`atomic_state_write` mechanism (§6.1; idempotent regeneration), append a `## Tool log` entry noting `(spec-challenge hardening)`, then re-run the Phase 7 validator. Mirror the Phase 7 max-3-revision-round loop: on a clean re-validation transition `phase: user-approve` to Phase 8; on a round-3 hard-fail follow the §7.3 accept-as-is / re-revise / abort AUQ. The human then approves a hardened spec.
- **re-plan** (the approach itself is refuted) — re-enter approach selection. Transition `phase: approaches` and re-run Phase 4 (re-run Phase 3 first if the refutation invalidates a clarifying answer), inlining the challenge's evidence into the §4.1 approach synthesis and the §4.2 stress-test `PRE_INLINED_CONTEXT`.

### 7.5.3 Advisory + fail-open

The spec challenge hardens the spec but never hard-blocks the Phase 8 human approval gate — same posture as the Phase 4.2 stress-test critic. If the helper or its agent spawns fail, log a `## Errors` entry ("spec-challenge unavailable") via `atomic_state_write` and transition `phase: user-approve` to Phase 8 on the un-challenged spec. The user still gets the final say at the Phase 8 AUQ.
