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

Use the **fixed section schema** detailed in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` — the eleven sections, in the order the §5.2 cluster table lists them.

Every spec.md has exactly the same fixed section set — schema-stable downstream consumers.

A "none — task scope precludes" body (§5.2 Tier-scaling) still keeps its header: downstream consumers rely on section presence, so a dropped header breaks them where an empty body does not.

### 5.2 Cluster authoring — dependency order

Group the section schema into 3 dependency-ordered clusters, authored in order:

| Cluster | Plain-English name | Sections |
|---|---|---|
| 1 | Goal & scope | 1 Objective, 2 Scope-Included, 3 Scope-Excluded |
| 2 | Approach & steps | 4 Assumptions, 5 Risks, 6 Steps, 7 Tools Required |
| 3 | Safety & done | 8 Approval Points, 9 Validation, 10 Rollback-Recovery, 11 Done Condition |

Author cluster N+1 grounded in cluster N's content, and all three before Phase 6. No question gates the section content — Phase 8 renders every cluster for the one final approval (§8.2); this phase asks only the §5.3 milestone questions. A Phase 8 revision round re-enters here: apply only the newest `revision_request` entry in `approvals[]` (earlier ones are already in the sections) to the sections it names and the sections that depend on them.

Author each cluster's sections inline from Phase 1 research + Phase 3 clarifying answers + Phase 4 picked approach + Phase 2's `## UI Preview`, read against `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel: approved text is substrate; the routed-out sentinel means Phase 2 ran but produced nothing to build from, so author as if Phase 2 never fired; the heading absent, or present but bare, means the outcome is unknown — re-check the §2.1 trigger against Phase 1's research before authoring as no-UI, since a Phase 2 that skipped its own exit-condition write reads identically to a task with no UI. Cluster 2's section 4 (Assumptions) starts from the Phase 3 termination ledger — one checkable predicate per branch the grill closed without an answer (a `pending: <owner>` branch keeps its `pending:` line) — plus any further premise the picked approach rests on.

**Cluster 2 also compiles the public surface.** List every public contract the picked approach adds, changes, or removes — exported function and type signatures, endpoints with their request/response shape, emitted events, database or config schema, CLI flags — each tagged new / changed / removed, and each changed one naming the callers it breaks. When the approach changes no public surface, say so in one line. The surface is the most expensive thing in a spec to change once shipped, and otherwise reaches approval as a side effect of approving Steps: "add `entryPoint` to the assembler contract" reads as an implementation detail in the Steps digest, and as a compatibility decision only when listed as a contract.

**Cluster 3 also compiles the test seams.** List where tests plug in — each seam the public entry a real caller uses (exported function, endpoint, CLI command), the section 9 criteria it observes, and the prior-art test file when one exists. As few seams as possible, ideally one: a seam chosen mid-build surfaces as a review finding, where one listed here is confirmed at approval.

**Tier-scaling.** For Trivial/Small tasks, sections 4 / 5 / 10 may be "none — task scope precludes" with a brief rationale — a one-line note in the Phase 8 render, never a separate decision.

**Concrete example per section type.** The example closing each section's Phase 8 digest takes the shape below:

| Section | Concrete example shape |
|---|---|
| 1. Objective | One-line user-visible behavior statement: "User clicks X → sees Y within Z seconds" |
| 2-3. Scope (Included/Excluded) | Bullet list mapping to specific files / endpoints / UI components (path-grounded, not feature-name) |
| 4. Assumptions | Concrete invariants: "`USER.tz` always populated" — cite `file:line` where the invariant is guaranteed |
| 5. Risks | Specific failure scenario + observable symptom: "Concurrent writers race on `events.cursor` → duplicate inserts → telemetry shows 2× `event.create` rate" |
| 6. Steps | Pseudocode block OR file-by-file diff outline (3-5 lines) |
| 7. Tools Required | Concrete CLI / MCP list: "the tracker update tool named in `.geniro/workflow/<kind>.md`, `pnpm test`, `gh pr view`" |
| 8. Approval Points | Named decisions + AUQ shape (header / question / option count) — advisory step anchors for pauses during /geniro:implement, per the section-8 note in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` |
| 9. Validation | Test names + ASCII test outline: `it('rejects negative quantity')` + 3-line body sketch, each criterion closing on its acceptance command: `verify: pnpm test orders.spec` |
| 10. Rollback-Recovery | One-line revert command OR feature-flag toggle pseudocode (e.g., `featureFlag.disable('new-auth')`) |
| 11. Done Condition | Observable signal phrase, plus the production signal when the change is outcome-bearing: "all 5 acceptance tests green AND telemetry shows ≥1 successful event insert; the dashboard metric shows backfill p95 under 5 min, one week after rollout" |

### 5.3 Milestone-mode

Fires BEFORE Phase 6 entry when the canonical milestone-output condition in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` is met (the Big-tier milestone threshold). AUQ header "Milestones" with options "Slice into milestones" (Recommended for Big) and "Keep as a single spec"; persist to `approvals[]` with category `milestone_slice` on EITHER pick, recording which was chosen — a Phase 7.5 milestone re-open (§7.5) reads this entry's presence, so "Keep as a single spec" must persist like "Slice". On slice pick, a follow-up renders 3-7 milestones with each one's deliverable and `blocked_by`, then asks Approve / Merge / Split (header "Breakdown", distinct from this step's "Milestones" question) until approved, persisting the approval to `approvals[]` with category `milestone_breakdown`; Phase 6 emits sibling `milestone-N.md` files alongside spec.md. Handoff (Phase 9) then prints `/geniro:implement .geniro/planning/<slug>/milestone-1.md`. Full AUQ shape + follow-up procedure in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §4.

### 5.4 Transition

With all three clusters authored and §5.3 settled whenever it fires, write `phase: write-spec` via `atomic_state_set_field` and proceed to Phase 6.
