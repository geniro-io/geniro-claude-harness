# Phase 7.5 — Spec challenge

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

State.md `phase: spec-challenge` during this phase. **Fires on every run**, at every effort tier. Entered after the Phase 7 validator passes (or its hard-fails were user-accepted) and before the Phase 8 approval AUQ. At entry the spec is: full text on disk, validator-clean, uncommitted, `lifecycle: draft`.

The user approves this spec at Phase 8, and an approval is only as good as the facts under it. Every gate before this one keys on structure or on the author's own reasoning — the validator reads shape, and the model that wrote the spec is the same one that ranked it. This is the single point in the loop where the spec's claims are read back against the code by a context that did not write them.

Surface a one-line plain-English note before invoking: "Challenging the spec before you approve it...".

**Re-derive the effort tier first, against the spec as it now stands.** The tier was set in Phase 1.2 from the task as understood then, and the spec has since been through the grill, approach selection, and section approval — scope routinely grows across those phases, and nothing recomputes the tier when it does. It is not a label: it gates milestone-mode splitting and the research-agent threshold in validator check 3, so a stale tier silently relaxes both. Where the re-derived tier differs from the recorded one, write the new value to spec frontmatter `effort_tier` and state the change in one line. A tier that grew to Big here re-opens milestone-mode at §7.5.2 rather than leaving the earlier skip settled.

### 7.5.1 Invoke the challenge helper

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` with MODE: plan, SPEC_PATH: `<task-dir>/spec.md`, TASK_DIR: `<task-dir>`, EFFORT_TIER: `<the tier detected in Phase 1.2>`, DEEP: `<true when state.md deep-mode: true, else false>`.

The helper runs VERIFY (every claim in its §3 set, same-file claims clustered into shared verifier spawns per its spawn-batch shape) + RED-TEAM + SYNTHESIZE, and returns a verdict: `keep` / `keep-with-modifications` / `re-plan`.

Cost scales with the spec, not with the tier: the claim set is what the spec itself asserts, and same-file claims share a spawn, so a small spec is a small batch and the whole batch runs in parallel. `/geniro:implement` re-runs the same helper pre-edit, and that stays the backstop for a spec that went stale between planning and building — but it is a backstop, not the first check. A defect found there is found after the user approved the plan and switched context to building it.

### 7.5.2 Verdict handling

- **keep** (clean) — surface a one-line advisory note (top challenge observation, if any) and transition `phase: user-approve` to Phase 8.
- **keep-with-modifications** — fold the helper's must-fixes into the spec by reusing the Phase 6 re-author → overwrite-via-`atomic_state_write` mechanism (§6.1; idempotent regeneration), append a `## Tool log` entry noting `(spec-challenge hardening)`, then re-run the Phase 7 validator AND re-enter this helper with `SCOPE: changed-only` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` §8.5. Folding a fix in rewrites spec content, and the content it rewrites is by definition the content a verifier just found wrong — leaving it checked only by the structural validator is how a hardening step ships an unverified claim under a clean-validator banner. Mirror the Phase 7 max-3-revision-round loop: on a clean re-validation and a clean re-challenge transition `phase: user-approve` to Phase 8; on a round-3 hard-fail follow the §7.3 accept-as-is / re-revise / abort AUQ. The human then approves a hardened spec.
- **re-plan** (the approach itself is refuted) — re-enter approach selection. Transition `phase: approaches` and re-run Phase 4 (re-run Phase 3 first if the refutation invalidates a clarifying answer), inlining the challenge's evidence into the §4.1 approach synthesis and the §4.2 stress-test `PRE_INLINED_CONTEXT`.

### 7.5.3 Advisory + fail-open

The spec challenge hardens the spec but never hard-blocks the Phase 8 human approval gate — same posture as the Phase 4.2 stress-test critic. If the helper or its agent spawns fail, log a `## Errors` entry ("spec-challenge unavailable") via `atomic_state_write` and transition `phase: user-approve` to Phase 8 on the un-challenged spec. The user still gets the final say at the Phase 8 AUQ.
