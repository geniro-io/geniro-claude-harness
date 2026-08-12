# Definition of Done — `/geniro:review`

The run-completion checklist of `/geniro:review` (spine: `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md`). Walk it at Phase 6, before the terminal `phase:` write.

Per-phase mechanics live in the phase files; this is the final contract check, and skipping any item leaves the review incomplete or unsafe.

- [ ] Every mandatory reviewer spawned in parallel — every always-fire dimension per §2.1 + every triggered conditional one (optimizations / design / pr-metadata / spec-compliance) + custom dimensions; `spawn_dims_declared[]` recorded before the batch, and §4.0b confirmed declared == actual. On the standard single-pass path, §4.0b also confirmed spawn instances == `spawn_dims_count`; deep mode carries no equivalent per-pass instance count — `deep-mode-reference.md` §2 checks only the declared dimension SET, since deep mode never fires the single batch that count measures.
- [ ] The spawn echo (`Spawning <N> reviewers: ...`), carrying the declared count, went out in the same response that fired the batch (§2.3.1).
- [ ] `steering-note:` was set before the batch fired — the round-≥2 gate's answer, the `--focus` flag, or `none` when neither — and threaded into every reviewer's `USER STEERING:` slot. Any finding it suppressed moved to `## Filtered` only after admission and verification, carries the instruction verbatim as its reason, and is never a CRITICAL (`${CLAUDE_PLUGIN_ROOT}/skills/review/phase-3-4-filter-stratify.md` §4.2).
- [ ] A fresh `finding-verifier-agent` verdict exists for EVERY admitted CRITICAL / HIGH / MEDIUM survivor (same-file findings cluster into a shared spawn at the cluster size in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4); refuted findings demoted to `## Filtered` — a CRITICAL / HIGH refutation only after a second independent verdict agreed, per the same file §5 rule 1.
- [ ] The admission gate was applied per its canonical rule (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5) — not a single confidence threshold.
- [ ] Every kept finding carries a severity (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1), a decision type, and a `[NEW]` / `[PRE-EXISTING]` tag.
- [ ] The needs-your-decision gate fired for every such finding at any severity, and all are resolved or wontfix BEFORE the handoff is offered or anything is posted (§7.0 Pre-Post guard).
- [ ] `phase:` was stamped via `atomic_state_write` on ENTRY to each phase (invariant S3), so both declarations existed before the gates reading them.
- [ ] All three pre-pass checks (lint / schema / secret) ran to a recorded outcome — `findings`, `clean`, or `error` — declared in `mechanical_prepass_attempted`, and §4.0a confirmed it.
- [ ] The handoff was written to `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` via `atomic_state_write`, carrying structured `open_questions[]`.
- [ ] `report_status: draft→final` flipped on this pass once the decision gates cleared — including on a clean review with no gates to fire; on a Post, `[POSTED-TO-PR]` markers persisted.
- [ ] The Action gate fired (always-WAIT) with its pick in `approvals[]`; the chained include-deferred gate fired on the `/geniro:implement findings` pick when set-aside minor findings existed; the round-N gate fired when round ≥3.
- [ ] `--deep` honored when present; approved test authoring stayed additive — never filtering the posted finding set.
