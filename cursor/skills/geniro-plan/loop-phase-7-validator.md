<!-- Generated from skills/plan/loop-phase-7-validator.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 7 — Mechanical validator

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

State.md `phase: validate` during this phase.

### 7.1 Mechanical pass-through

Phase 7 is a **deterministic validator** — a script plus mechanical rules applied orchestrator-side, with no LLM round-trip per check.

### 7.2 Validator checks

Read `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md` before running anything, echoed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — it is the sole home of the validating command, so a run that narrates "validator passed" without it is clean-looking and wholly unvalidated. Run the full set per its §Running the checks and report per check, not as a tally, per its §Check API contract.

### 7.3 Hard-fail handling

If any check fails:
1. Write findings to state.md `## Open Questions` body as a structured list (one bullet per failed check, with `fix_hint`).
2. Re-author the failing sections (orchestrator-side: model re-reads its own draft + validator findings + `fix_hint`s, and rewrites only the failing sections).
3. Re-run validator. **Max 3 auto-revision rounds.**
4. If round 3 still fails → render the failures to chat, then fire `AskQuestion` with header "Spec checks". Render per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering in the two layers of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers: one plain sentence per still-failing check on what the spec is missing or contradicting and what an implementer would get wrong because of it, then a `**Technical detail:**` block naming the check and the spec section. Without that render, "Accept as-is" asks the user to waive checks they were never shown. Options:
 - **Accept as-is** — proceed to Phase 8 with the failed checks documented in `## Open Questions`; user has final say.
 - **Re-revise** — kick a fresh round-1 cycle.
 - **Abort** — run the §9.2 transient cleanup (`clean_task_transients`, `loop-phase-9-handoff.md`) and walk `loop-definition-of-done.md` §Abort-path subset, then write terminal `aborted` + `## Termination reason: phase-7-validator-hard-fail`.

### 7.4 No transition to Phase 7.5 if validator hard-fails

The validator is a gate, not advisory. Phase 7.5 spec challenge and the Phase 8 user-approve see a validator-clean spec.md, or one whose hard-fails the user explicitly accepted via the §7.3 Accept-as-is option — carrying an unresolved hard-fail into either is the "user approves blind" failure mode. On a clean (or user-accepted) validator pass, transition `phase: spec-challenge` and enter Phase 7.5 — it fires on every run, at every tier. A re-validation arriving from the §7.5.2 hardening loop re-enters Phase 7.5 in its bounded form — `SCOPE: changed-only` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` §8.5. The validator re-reads shape and a re-authored spec preserves shape by construction, so passing it straight to Phase 8 would let new content reach approval fact-checked by nothing. A re-entry with no content edited (formatting-only auto-revision, say) has an empty changed set, which §8.5 carries forward. On a clean re-challenge it transitions `phase: user-approve` per §7.5.2.
