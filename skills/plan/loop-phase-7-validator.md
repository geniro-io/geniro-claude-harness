# Phase 7 — Mechanical validator

A phase file of the `/geniro:plan` loop. The spine — HARD-GATE, gate presentation contract, echo contract, phase order, terminal states, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`.

State.md `phase: validate` during this phase.

### 7.1 Mechanical pass-through (not Opus self-prompt)

Phase 7 uses a **deterministic validator** — script-checkable rules executed orchestrator-side. No LLM round-trip per check.

### 7.2 Validator checks

See `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md` for the canonical check definitions. Each check returns `(check_id, status, finding_text, fix_hint)`. Run the full set in sequence and report per check, not as a tally, per that file's §Check API contract.

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

The validator is a gate, not advisory. Phase 7.5 spec challenge and the Phase 8 user-approve see a validator-clean spec.md, or one whose hard-fails the user explicitly accepted via the §7.3 Accept-as-is option — carrying an unresolved hard-fail into either is the "user approves blind" failure mode. On a clean (or user-accepted) validator pass, branch on the Phase 7.5 gate: when the Phase 1.2 effort tier is Big (on a compaction resume, re-read it from spec frontmatter `effort_tier`) OR state.md has `deep-mode: true`, transition `phase: spec-challenge` and enter Phase 7.5; otherwise transition `phase: user-approve` directly to Phase 8. A re-validation arriving from the §7.5.2 hardening loop does not re-enter Phase 7.5 — the challenge already ran; on a clean pass it transitions `phase: user-approve` per §7.5.2.
