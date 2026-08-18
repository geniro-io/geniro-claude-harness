<!-- Generated from skills/plan/loop-phase-5-section-approval.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 5 — Section approval

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

State.md `phase: section-approve` during this phase.

### 5.1 Section template

Use the **fixed section schema** detailed in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`:

1. Objective
2. Scope — Included
3. Scope — Excluded
4. Assumptions
5. Risks
6. Steps
7. Tools Required
8. Approval Points
9. Validation
10. Rollback-Recovery
11. Done Condition

Every spec.md has exactly the same fixed section set — schema-stable downstream consumers.

For Trivial tasks, sections 4 / 5 / 10 may have body content "none — task scope precludes" with brief rationale. Keep every header present even then; downstream consumers rely on section presence, so a dropped header breaks them where an empty body does not.

### 5.2 Cluster approval — message-first, one decision per cluster

Group the section schema into 3 dependency-ordered clusters, authored and gated in order:

| Cluster | Plain-English name | Sections |
|---|---|---|
| 1 | Goal & scope | 1 Objective, 2 Scope-Included, 3 Scope-Excluded |
| 2 | Approach & steps | 4 Assumptions, 5 Risks, 6 Steps, 7 Tools Required |
| 3 | Safety & done | 8 Approval Points, 9 Validation, 10 Rollback-Recovery, 11 Done Condition |

Author cluster N → render it → gate it → on approve, author cluster N+1. Cluster 1 (Goal & scope) is approved before cluster 2 is authored, so each cluster is grounded in the prior cluster's approved content; this keeps cross-section issues catchable while preserving dependency order. Do NOT author every section before the first gate.

Per cluster, apply the Gate presentation contract:

1. **Author** the cluster's sections inline using Phase 1 research + Phase 3 clarifying answers + Phase 4 picked approach + Phase 2's `## UI Preview`, read against `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel: approved text is substrate; the routed-out sentinel means Phase 2 ran but produced nothing to build from, so author as if Phase 2 never fired; the heading absent, or present but bare, means the producing step's outcome is unknown — re-check the §2.1 trigger against Phase 1's research before authoring as no-UI, since a Phase 2 that ran and skipped its own exit-condition write would otherwise read identically to a task with no UI at all. Cluster 2's section 4 (Assumptions) starts from the Phase 3 termination ledger — one checkable predicate per branch the grill closed without an answer — plus any further premise the picked approach rests on. Then fire the before-gate update for this site (call-site table in `loop-artifact-call-sites.md`) so the artifact mirrors the cluster's pending approval.

2. **Render the cluster to a chat message in the Visual rendering language** (Gate presentation contract): the progress tracker (this cluster `●`, with `step N of 3`), a one-sentence opener stating what the cluster decides, the cluster-level visual (cluster 1: the in-scope/out-of-scope map; cluster 2: the steps flow diagram; cluster 3: the done-condition checklist), then one icon-headed sub-heading per section with its friendly digest block — lead sentence, `**Why:**` grounded in a Phase 1 finding `file:line` + the Phase 4 approach, `**How it gets built:**`, `**You'll see:**` — closing with the section's concrete example (`${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-reference.md` §"Concrete example per section type") and its visual (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §"Plan-unit visual map"). A "none — task scope precludes" section is a one-line note here, not a rendered section.

   **Cluster 2 renders the public surface on its own.** Above the per-section digests, list every public contract the picked approach adds, changes, or removes — exported function and type signatures, endpoints with their request/response shape, emitted events, database or config schema, CLI flags — each tagged new / changed / removed, and each changed one naming the callers it breaks. When the approach changes no public surface, say so in one line. The surface is the most expensive thing in a spec to change once shipped, and it otherwise reaches approval as a side effect of approving Steps: "add `entryPoint` to the assembler contract" reads as an implementation detail at the altitude the Steps digest renders it, and as a compatibility decision only when listed as a contract. A Revise round that alters an already-approved signature re-renders this block, so the change is approved rather than inherited.

3. **Fire ONE lean AUQ for the cluster** — `header` (per the Gate presentation contract's cap) matches the cluster's journey-tracker stop ("Goal & scope" / "Steps" / "Safety"); the chip never reads "Approach", which already tags the Phase 4 decision; options:
   - **Approve all (N sections)** (Recommended) — accept every section in the cluster as rendered.
   - **Explain a section further** — opens the same section picker as Revise. For each picked section, render a deeper walkthrough message — the full evidence chain (additional `file:line` cites), an expanded or alternative diagram, edge-case behavior, and exactly what /geniro:implement will and will not touch — then re-fire this AUQ. A reading aid, not a decision (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Explain-further option): it writes no `approvals[]` entry, never changes section content, and does not count toward the 3 revision rounds.
   - **Revise specific sections** — opens a follow-up multi-select picker of the cluster's section names (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` multi-select schema). For each picked section, capture the revision (free-text), re-author it AND any same-cluster sections that depend on it, re-render the cluster message, then fire the before-gate update for this Revise site (call-site table in `loop-artifact-call-sites.md`) so the page mirrors the re-rendered chat. Then re-fire this AUQ. Max 3 revision rounds per cluster — on a 4th, re-render with Revise dropped (Approve all / Explain a section further / Cancel planning) and note that a change still wanted rides to the final approval gate, whose Request-changes path re-enters this phase.
   - **Cancel planning** — terminal `aborted` + `## Termination reason: user-cancelled-at-phase-5`.

4. **Persist each section pick** to `approvals[]` with category `section_<id>` (e.g., `section_objective`, `section_scope_included`). On "Approve all", append one entry per section in the cluster (`picked: approve`); on "Revise", record the revised sections distinctly (`picked: revised: <summary>`); "Explain a section further" persists nothing — only Approve/Revise picks write entries. The cluster is a presentation grouping only — no `cluster_<id>` category; per-section persistence granularity is unchanged, so compaction re-author (§6.4) and the SessionStart restore hook need no change.

5. **On approve, author the next cluster** (step 1). After all 3 clusters approved → Phase 6. After a cluster's section picks persist, fire the update for this site (call-site table in `loop-artifact-call-sites.md`).

**Tier-scaling.** For Trivial/Small tasks, sections 4 / 5 / 10 may be "none — task scope precludes" — noted in the cluster message, never a separate decision. Collapsing gates is Trivial-only: at Trivial tier the clusters may collapse to 1-2 gates (the progress tracker then shows the collapsed stops); Small, Medium, and Big each keep all 3 cluster gates. Small lightens what a section contains, not how many decisions the user makes — Trivial is the only tier whose loop can drop user-facing decision points at all, and even there the visual-companion and grill phases are skipped under the §1.5 conditions rather than unconditionally.

Full chat-message template + lean-AUQ shape in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §4.1.

### 5.3 Milestone-mode

Fires BEFORE Phase 6 entry when the canonical milestone-output condition in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` is met (the Big-tier milestone threshold). AUQ header "Milestones" with options "Slice into milestones" (Recommended for Big) and "Keep as a single spec"; persist to `approvals[]` with category `milestone_slice` on EITHER pick, recording which was chosen — a Phase 7.5 milestone re-open (§7.5) reads this entry's presence, so "Keep as a single spec" has to settle the decision as durably as "Slice" does. On slice pick, follow-up AUQ proposes 3-7 milestone names; Phase 6 emits sibling `milestone-N.md` files alongside spec.md. Handoff (Phase 9) then prints `/geniro:implement .geniro/planning/<slug>/milestone-1.md`. Full AUQ shape + follow-up procedure in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §4.2. Milestone-mode fires only at Big tier; not Small/Medium/Trivial.
