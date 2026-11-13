<!-- Generated from skills/plan/loop-phase-5-section-approval.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 5 — Section authoring

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

State.md `phase: section-approve` during this phase.

## Contents

- 5.1 Section template — the required sections and their order
- 5.2 Cluster authoring — dependency order, public surface, test seams, tier-scaling, concrete example per section type
- 5.3 Milestone-mode
- 5.4 Transition

### 5.1 Section template

Use the fixed section schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` — the same eleven sections on every spec, in the order the §5.2 cluster table lists them.

A "none — task scope precludes" body (§5.2 Tier-scaling) still keeps its header: downstream consumers rely on section presence, so a dropped header breaks them where an empty body does not.

### 5.2 Cluster authoring — dependency order

Group the section schema into 3 dependency-ordered clusters, authored in order:

| Cluster | Plain-English name | Sections |
|---|---|---|
| 1 | Goal & scope | 1 Objective, 2 Scope-Included, 3 Scope-Excluded |
| 2 | Approach & steps | 4 Assumptions, 5 Risks, 6 Steps, 7 Tools Required |
| 3 | Safety & done | 8 Approval Points, 9 Validation, 10 Rollback-Recovery, 11 Done Condition |

Author cluster N+1 grounded in cluster N's content, and all three before Phase 6. No question gates the section content — Phase 8 renders every cluster for the one final approval (§8.2); this phase asks only the §5.3 milestone questions. A Phase 8 revision round re-enters here: apply only the newest `revision_request` entry in `approvals[]` (earlier ones are already in the sections) to the sections it names and the sections that depend on them.

Author each cluster's sections inline from Phase 1 research + Phase 3 clarifying answers + Phase 4 picked approach + Phase 2's `## UI Preview`, read per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel: approved text is substrate; the routed-out sentinel means author as if Phase 2 never fired; a heading absent or bare means the outcome is unknown — re-check the §2.1 trigger against Phase 1's research before authoring as no-UI. Cluster 2's section 4 (Assumptions) starts from the Phase 3 termination ledger — one checkable predicate per branch the grill closed without an answer (a `pending: <owner>` branch keeps its `pending:` line) — plus any further premise the picked approach rests on.

**Cluster 2 also compiles the public surface.** List every public contract the picked approach adds, changes, or removes — exported function and type signatures, endpoints with their request/response shape, emitted events, database or config schema, CLI flags — each tagged new / changed / removed, and each changed one naming the callers it breaks. When the approach changes no public surface, say so in one line. The surface is the most expensive thing in a spec to change once shipped, and otherwise reaches approval as a side effect of approving Steps: "add `entryPoint` to the assembler contract" reads as an implementation detail until listed as a contract.

**Cluster 3 also compiles the test seams.** List where tests plug in — each seam the public entry a real caller uses (exported function, endpoint, CLI command), the section 9 criteria it observes, and the prior-art test file when one exists. As few seams as possible, ideally one: a seam chosen mid-build surfaces as a review finding, where one listed here is confirmed at approval.

**Tier-scaling.** For Trivial/Small tasks, sections 4 / 5 / 10 may be "none — task scope precludes" with a brief rationale — a one-line note in the Phase 8 render, never a separate decision.

**Concrete example per section type.** Each section's Phase 8 digest closes on one example of its content, shaped as below; the render shape per section is `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §"Plan-unit visual map".

| Section | Concrete example shape |
|---|---|
| 1. Objective | User-visible behavior: "User clicks X → sees Y within Z seconds" |
| 2-3. Scope | Bullets naming specific files / endpoints / UI components, not feature names |
| 4. Assumptions | A concrete invariant with the `file:line` that guarantees it: "`USER.tz` always populated" |
| 5. Risks | Failure scenario → observable symptom: "Concurrent writers race on `events.cursor` → duplicate inserts → 2× `event.create` rate" |
| 6. Steps | Pseudocode block OR a 3-5 line file-by-file diff outline |
| 7. Tools Required | Concrete commands and tools: "the tracker update tool named in `.geniro/workflow/<kind>.md`, `pnpm test`" |
| 8. Approval Points | Named decisions + AUQ shape (header / question / option count) |
| 9. Validation | Test names + a 3-line body sketch, each criterion closing on its command: `verify: pnpm test orders.spec` |
| 10. Rollback-Recovery | One-line revert command OR flag toggle: `featureFlag.disable('new-auth')` |
| 11. Done Condition | Observable signal, plus the production signal when outcome-bearing: "all 5 acceptance tests green AND telemetry shows ≥1 successful event insert" |

### 5.3 Milestone-mode

Fires BEFORE Phase 6 entry when the canonical milestone-output condition in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` is met (the Big-tier milestone threshold). Ask the AUQ (header "Milestones") and, on a slice pick, run the breakdown follow-up (header "Breakdown"), both per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §4. Persist the first pick to `approvals[]` with category `milestone_slice` on EITHER answer, recording which was chosen — a Phase 7.5 milestone re-open reads this entry's presence, so "Keep as a single spec" must persist like "Slice". Phase 6 then emits the sibling `milestone-N.md` files (§6.3).

### 5.4 Transition

With all three clusters authored and §5.3 settled whenever it fires, write `phase: write-spec` via `atomic_state_set_field` and proceed to Phase 6.
