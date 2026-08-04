# Phase 4 — Report (steps)

Read on Phase 4 entry from `/geniro:audit-instructions` SKILL.md; the spine's invariants and budgets stay binding here.

Write `.geniro/state/audit-instructions/report-<YYYY-MM-DD>.md` via `atomic_state_write` — it lives outside the slug directory deliberately, so it survives the Phase 5 cleanup and becomes the next run's Phase 0 input. Structure:

1. **Header** — date, scope, which dimensions ran, sharding.
2. **Health summary** — what's strong and must not be over-corrected (feeds the next run's do-not-flag list).
3. **Tier tables T0→T5** — columns: `# | file:line | issue | fix | effort`; convergence noted inline.
4. **Per-dimension verdicts** — the reviewers' 2-3-sentence verdicts, edited for consistency.
5. **Filtered** — dropped findings with one-line reasons (transparency; keeps future runs from re-litigating).
6. **Subtraction sweep** (invariant #13) — always present, even when empty: what the bloat reviewer examined, and every candidate it considered and rejected with the reason.
7. **Single highest-value fix** — one paragraph naming it and why.

On `--quick` runs, omit section 4 and the convergence notes — no reviewers ran; state "mechanical pre-pass only" in the header. Section 6 still appears, carrying the inline sweep.

In chat, render **every** finding before the action gate — the user approves individual edits to their instruction files, so each one has to be visible, low and cosmetic included. Lead with the highest-value fix, then the full tier tables T0→T5 (same rows as the report, each tier introduced in plain English — "leaked secrets and unsafe directives", "instructions that mislead agents"), then the report path. This render is the decision context for the Phase 5 question: emit it as a visible chat message and fire the question immediately after — never stop between render and question — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard. The set the user is about to approve and the set they can see must be the same set.
