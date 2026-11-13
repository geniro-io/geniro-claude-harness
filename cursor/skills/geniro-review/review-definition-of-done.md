<!-- Generated from skills/review/review-definition-of-done.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Definition of Done — `/geniro:review`

The run-completion checklist (spine: `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md`). Walk it at Phase 6, before the terminal `phase:` write; skipping any item leaves the review incomplete or unsafe.

- [ ] Every always-fire dimension (§2.1), every triggered conditional one (optimizations / design / pr-metadata / spec-compliance), and every custom dimension spawned in parallel; `spawn_dims_declared[]` recorded before the batch; §4.0b confirmed declared == actual and instances == `spawn_dims_count`.
- [ ] The spawn echo (`Spawning <N> reviewers: ...`) went out in the response that fired the batch (§2.3.1).
- [ ] The brief opt-in was settled in Phase 1 (§13). Unless `off`, the brief spawn rode in the batch's response and was materialized before Phase 3 with its location surfaced once (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-brief.md` §Caller contract); `off` produced nothing.
- [ ] `steering-note:` was set before the batch (the round-≥2 gate's answer, `--focus`, or `none`) and threaded into every reviewer's `USER STEERING:` slot. A finding it suppressed moved to `## Filtered` after admission and verification, with the instruction verbatim as its reason, and is never a CRITICAL (`${CLAUDE_PLUGIN_ROOT}/skills/review/phase-3-4-filter-stratify.md` §4.2).
- [ ] Every admitted CRITICAL / HIGH / MEDIUM survivor has a `Validation:` verdict — from a fresh `finding-verifier-agent` spawn or the inline route in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §1 (shared-code findings cluster per its §4). Refuted findings sit in `## Filtered`, a CRITICAL / HIGH one only after a second independent verdict (its §5 guard).
- [ ] The admission gate followed `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5, not a single confidence threshold.
- [ ] Every kept finding carries a severity (`severity-calibration.md` §1), a decision type, and a `[NEW]` / `[PRE-EXISTING]` tag.
- [ ] The needs-your-decision gate fired for every such finding at any severity, all resolved or wontfix BEFORE the handoff is offered or anything is posted (§7.0 Pre-Post guard).
- [ ] `phase:` was stamped via `atomic_state_set_field` on ENTRY to each phase (invariant S3).
- [ ] All three pre-pass checks (lint / schema / secret) have a recorded outcome — `findings`, `clean`, or `error` — in `mechanical_prepass_attempted`, confirmed by §4.0a.
- [ ] The handoff was written to `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` via `atomic_state_write`, with structured `open_questions[]`.
- [ ] `report_status` flipped `draft→final` once the decision gates cleared, a clean review included; on a Post, `[POSTED-TO-PR]` markers persisted.
- [ ] The Action gate fired (always-WAIT) with its pick in `approvals[]`; the chained include-deferred gate fired on the `/geniro:implement findings` pick when set-aside minor findings existed; the round-N gate fired past the round threshold (`${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §7 step 4).
- [ ] The final chat message states the verdict (kept-finding counts by severity, or the clean-pass affirmation) and the handoff's ABSOLUTE path; the repo-relative form alone, or either half missing, fails.
- [ ] No test was authored — a testable finding's `Decision Type` carries into the handoff unchanged for `/geniro:implement`.
