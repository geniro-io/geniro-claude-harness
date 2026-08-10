# Phase 7 — Mechanical validator

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

State.md `phase: validate` during this phase.

### 7.1 Mechanical pass-through

Phase 7 uses a **deterministic validator** — most of it a script, the rest mechanical rules applied orchestrator-side. No LLM round-trip per check.

### 7.2 Validator checks

Read `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md` before running anything, echoed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — it is the sole home of the shell command that actually validates, so a run that narrates "validator passed" without it produces a clean-looking, wholly unvalidated spec. It holds the canonical check definitions, and its §Running the checks carries the command that executes the scripted checks plus the judgment checks you apply yourself. Each check returns `(check_id, status, finding_text, fix_hint)`. Run the full set and report per check, not as a tally, per that file's §Check API contract.

### 7.3 Hard-fail handling

If any check fails:
1. Write findings to state.md `## Open Questions` body as a structured list (one bullet per failed check, with `fix_hint`).
2. Re-author the failing sections (orchestrator-side: model re-reads its own draft + validator findings + `fix_hint`s, and rewrites only the failing sections).
3. Re-run validator. **Max 3 auto-revision rounds.**
4. If round 3 still fails → fire `AskUserQuestion` with header "Spec checks not passing":
 - **Accept as-is** — proceed to Phase 8 with the failed checks documented in `## Open Questions`; user has final say.
 - **Re-revise** — kick a fresh round-1 cycle (rare; usually indicates schema misunderstanding).
 - **Abort** — terminal `aborted` + `## Termination reason: phase-7-validator-hard-fail`.

### 7.4 No transition to Phase 7.5 if validator hard-fails

The validator is a gate, not advisory. Phase 7.5 spec challenge and the Phase 8 user-approve see a validator-clean spec.md, or one whose hard-fails the user explicitly accepted via the §7.3 Accept-as-is option — carrying an unresolved hard-fail into either is the "user approves blind" failure mode. On a clean (or user-accepted) validator pass, transition `phase: spec-challenge` and enter Phase 7.5 — it fires on every run, at every tier. A re-validation arriving from the §7.5.2 hardening loop re-enters Phase 7.5 in its bounded form — `SCOPE: changed-only` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` §8.5 — because the spec it is validating is not the spec the challenge read. Passing it straight through to Phase 8 is what let re-authored content reach approval fact-checked by nothing: the validator re-reads shape, and a re-authored spec preserves shape by construction. On a clean re-challenge it transitions `phase: user-approve` per §7.5.2.

A spec that reaches this validator having had no content edited since its last challenge (the §7.3 auto-revision touched only formatting, say) re-enters with an empty changed set, which §8.5 resolves to a carry-forward of every prior verdict — cheap, and visible in the scratch report rather than assumed.
