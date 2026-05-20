# spec.md template — P-M5-1 schema

Canonical 10-section markdown template that Phase 6 fills in. One source of truth for §17 schema.

**Spec source:** `architecture/M5-plan-redesign.md` §17 (schema definition), §18 (goal-state frontmatter block), §17.3 (per-section content guidance).

**Status:** Authoritative. Phase 7 mechanical validator (§14 — `validator-checks.md` Check #13 schema_completeness) enforces this layout exactly. Every spec.md emitted by `/geniro:plan` conforms.

## Frontmatter (M5 §17.1)

```yaml
---
tier: T1                                # M1 §T1 required (spec.md lives в task-dir)
producer: plan                          # M1 §T1 required
schema-version: 1                       # M1 §T1 required
branch: <git-branch>                    # M1 §T1 required
timestamp: <ISO-8601 UTC>                # M1 §T1 required
geniro_kind: design-doc                  # design-doc-detect.md contract — required marker
geniro_schema_version: m5-v1             # M5 schema version
task_slug: <slug>                        # M5 extension
topic: <one-sentence-topic>              # M5 extension
mode: <IDEA|DESIGN_DOC-fresh>            # M5 extension
effort_tier: <trivial|medium|big>        # M5 extension
lifecycle: draft                         # M5 design-doc lifecycle (draft|approved|superseded)
budget:                                  # P-M5-2 goal-state block — start
  max_files_to_edit: <int|null>
  max_lines_changed: <int|null>
  time_budget: <duration|null>           # e.g., "4h", "1d", or null for unbounded
checkpoints:                             # list of {step_anchor, name} pairs
  - step_anchor: step-3
    name: "DB migration applied"
  - step_anchor: step-7
    name: "Tests green"
forbidden_actions:                       # list of explicit "don't do this" rules
  - "do NOT modify production database schema directly — use migrations only"
  - "do NOT bypass auth middleware"
approval_required_for:                   # list of step_anchors that require user approval before /implement proceeds
  - step-3
  - step-9
tools_required: ["pnpm", "docker", "gh"]  # CLI tools the implementer needs в env — P-M5-2 goal-state end
---
```

**Field origins:**
- Fields 1-5 (tier → timestamp): M1 §T1 required base.
- Fields 6-11 (geniro_kind → lifecycle): M5 schema markers + extensions.
- Fields 12-17 (budget → tools_required): P-M5-2 goal-state block embedded в frontmatter per H-2.

**`status:` namespace note.** M1 §T1 reserves `status:` для state lifecycle (`in-progress|done|failed`). M5 design-doc lifecycle uses а distinct key (`lifecycle:` — values `draft|approved|superseded`) к avoid clash. State-tracking уже handled via the state.md sibling file, so spec.md doesn't need M1's `status:` field. Phase 8 §8.4 flips `lifecycle: draft` → `lifecycle: approved` on user-approve.

## Body — 10 sections

```markdown
<!-- geniro:design-doc -->

# <Topic Title>

## 1. Objective

<Single declarative sentence stating the goal.>

## 2. Scope — Included

<Bullet list of files / features / behaviors changed by this task.>

## 3. Scope — Excluded

<Bullet list of adjacent things NOT changed. Use "none — open scope" с rationale if scope is intentionally unbounded.>

## 4. Assumptions

<Bullet list of assumptions the plan rests on (e.g., "OAuth library version ≥2.5", "test DB is available"). Use "none" if scope precludes assumptions.>

## 5. Risks

<Bullet list of known risks с severity (low/medium/high) и mitigation. Use "none" с rationale if scope precludes risks.>

## 6. Steps

<Numbered list of implementation steps. Each step:
- has а 1-line description
- cites ≥1 file:line reference (Phase 1 explore-grounded)
- has optional anchor `<!-- step-N -->` for checkpoint/approval-required references>

## 7. Tools Required

<Bullet list of tools the implementer needs (CLI tools, MCP servers, environment variables). Use "none" if the task is а pure-code change.>

## 8. Approval Points

<Bullet list pointing к specific steps that require user-approval gates during /implement run. References step anchors. Use "none" if /implement may run autonomously start-to-finish.>

## 9. Validation

<Body describing how к verify the implementation worked. References test types (unit/integration/e2e) or а manual verification procedure.>

## 10. Rollback-Recovery

<Body describing how к revert the change cleanly if it goes wrong. Includes commit-revert plan, data-migration rollback, feature-flag toggle, или explicit "no rollback needed — pure additive" с rationale.>

## 11. Done Condition

<Single statement of the observable signal that the task is complete. E.g., "all 5 acceptance tests green AND PR approved" / "feature ships behind flag AND telemetry shows ≥1 successful use".>
```

(Note: section 11 «Done Condition» is the 10th sectioned body section but uses heading level «## 11.» — the count starts at 1, не 0; the schema-completeness check counts 10 sections, `## 1` through `## 11` reading «11 = Done Condition» as section 10. Pedantic count adjustment for header consistency.)

Body sections beyond the 10 (allowed):
- `## Considered Alternatives` — captured от Phase 4 §11.3. Always present if Phase 4 ran с ≥2 approaches.
- `## Milestones` — captured от Phase 5 milestone-mode (§12.3). Present only if milestone-mode was picked.

## Per-section content guidance (M5 §17.3)

**Section 1 (Objective):** ONE sentence. NOT а problem statement, NOT а user story, NOT а title — а declarative goal. Examples:
- ✅ "Add OAuth login к the customer portal."
- ❌ "We need OAuth because users keep complaining about password resets." (problem statement, not objective)
- ❌ "As а customer, I want к login с OAuth." (user story, not objective)

**Section 6 (Steps):** Each step cites ≥1 file:line reference unless it's а meta-step (e.g., "Step 1: Create new branch"). Phase 7 validator check #3 enforces this.

**Section 8 (Approval Points):** This is the contract /implement reads to know when к pause for user gates. М4 Phase 2 inner loop checks this at the start of each step и fires `AskUserQuestion` if the step anchor matches an Approval-Points entry. М5 ↔ М4 contract.

**Section 10 (Rollback-Recovery):** «none — pure additive» is а valid body BUT must be explicit. Phase 7 validator does не auto-fail if body is «none» — it auto-fails if body is empty.

**Sections 4, 5, 10 для Trivial tasks:** may have body content «none — task scope precludes» с brief rationale. Headers MUST exist; bodies MAY be «none с rationale».

## Milestone-mode (§12.3)

If Phase 5 §5.3 milestone-mode was picked, Phase 6 emits:
- `spec.md` — top-level с section 6 «Steps» listing milestone names (not raw steps) + а body section `## Milestones` indexing the sibling files.
- `milestone-1.md`, `milestone-2.md`, …, each с its own 10-section schema scoped к the milestone.

Each `milestone-N.md` frontmatter MAY add `parent_spec: <task-slug>` к link back к the top-level spec.md (OQ-M5-4 — tentatively yes; deferred к implementation).
