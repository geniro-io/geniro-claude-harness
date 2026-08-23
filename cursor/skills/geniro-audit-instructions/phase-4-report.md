<!-- Generated from skills/audit-instructions/phase-4-report.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 4 — Report (steps)

Read on Phase 4 entry from `/geniro:audit-instructions` SKILL.md; the spine's invariants and budgets stay binding here.

Write `.geniro/state/audit-instructions/report-<YYYY-MM-DD>.md` via `atomic_state_write` — it lives outside the slug directory deliberately, so it survives the Phase 5 cleanup and becomes the next run's Phase 0 input. Structure:

1. **Header** — date, scope, which dimensions ran, sharding, and the Phase 0 prior-report read: the prior report's date when one was found and consumed, or `no prior report found` when none existed. A skipped read is otherwise indistinguishable from a genuine first run.
2. **Health summary** — what's strong and must not be over-corrected (feeds the next run's do-not-flag list).
3. **Tier tables T0→T4** — columns: `# | file:line | issue | fix | effort`; convergence noted inline.
4. **Per-dimension verdicts** — the reviewers' 2-3-sentence verdicts, edited for consistency.
5. **Filtered** — dropped findings with one-line reasons (transparency; keeps future runs from re-litigating).
6. **Subtraction sweep** (the subtraction-sweep invariant) — always present, even when empty: what the bloat reviewer examined, and every candidate it considered and rejected with the reason. List whole-surface proposals (D4's surface-level-subtraction check) separately from line-level ones, each carrying inline the evidence §Deletion gate renders, so the user reads the case before the gate rather than for the first time inside it. Record the surfaces the user keeps as considered-and-kept, with the reason — that is what stops the next audit re-proposing them, and it is the half of the sweep that compounds.
7. **Single highest-value fix** — one paragraph naming it and why.

On `--quick` runs, omit section 4 and the convergence notes — no reviewers ran; state "mechanical pre-pass only" in the header. Section 6 still appears, carrying the inline sweep.

In chat, render **every** finding before the action gate — the user approves individual edits to their instruction files, so each one has to be visible, the lowest tier included. Lead with the highest-value fix, then the full tier tables T0→T4 (same rows as the report, each tier introduced in plain English — "leaked secrets and unsafe directives", "instructions that mislead agents"), then the report path. This render is the decision context for the Phase 5 question: emit it as a visible chat message and fire the question immediately after — never stop between render and question — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard. The set the user is about to approve and the set they can see must be the same set.
