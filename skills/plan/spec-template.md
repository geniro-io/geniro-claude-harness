# spec.md template — schema

Canonical 10-section markdown template that Phase 6 fills in. One source of truth for schema.

**Spec source:** *(internal)* (schema definition), (goal-state frontmatter block), (per-section content guidance).

**Status:** Authoritative. Phase 7 mechanical validator enforces this layout exactly. Every spec.md emitted by `/geniro:plan` conforms.

## Frontmatter

```yaml
---
tier: T1 # required (spec.md lives in task-dir)
producer: plan # required
schema-version: 1 # required
branch: <git-branch> # required
timestamp: <ISO-8601 UTC> # required
geniro_kind: design-doc # design-doc-detect.md contract — required marker
geniro_schema_version: m5-v1 # schema version
task_slug: <slug> # extension
topic: <one-sentence-topic> # extension
mode: <IDEA|DESIGN_DOC-fresh> # extension
effort_tier: <trivial|medium|big> # extension
lifecycle: draft # design-doc lifecycle (draft|approved|superseded)
budget: # goal-state block — start
max_files_to_edit: <int|null>
max_lines_changed: <int|null>
time_budget: <duration|null> # e.g., "4h", "1d", or null for unbounded
checkpoints: # list of {step_anchor, name} pairs
- step_anchor: step-3
name: "DB migration applied"
- step_anchor: step-7
name: "Tests green"
forbidden_actions: # list of explicit "don't do this" rules
- "do NOT modify production database schema directly — use migrations only"
- "do NOT bypass auth middleware"
approval_required_for: # list of step_anchors that require user approval before /implement proceeds
- step-3
- step-9
tools_required: ["pnpm", "docker", "gh"] # CLI tools the implementer needs in env — goal-state end
---
```

**Field origins:**
- Fields 1-5 (tier → timestamp): required base.
- Fields 6-11 (geniro_kind → lifecycle): schema markers + extensions.
- Fields 12-17 (budget → tools_required): goal-state block embedded in frontmatter per.

**`status:` namespace note.** reserves `status:` for state lifecycle (`in-progress|done|failed`). design-doc lifecycle uses a distinct key (`lifecycle:` — values `draft|approved|superseded`) to avoid clash. State-tracking already handled via the state.md sibling file, so spec.md doesn't need the spec's `status:` field. Phase 8 flips `lifecycle: draft` → `lifecycle: approved` on user-approve.

## Body — 10 sections

```markdown
<!-- geniro:design-doc -->

# <Topic Title>

## 1. Objective

<Single declarative sentence stating the goal.>

## 2. Scope — Included

<Bullet list of files / features / behaviors changed by this task.>

## 3. Scope — Excluded

<Bullet list of adjacent things NOT changed. Use "none — open scope" with rationale if scope is intentionally unbounded.>

## 4. Assumptions

<Bullet list of assumptions the plan rests on (e.g., "OAuth library version ≥2.5", "test DB is available"). Use "none" if scope precludes assumptions.>

## 5. Risks

<Bullet list of known risks with severity (low/medium/high) and mitigation. Use "none" with rationale if scope precludes risks.>

## 6. Steps

<Numbered list of implementation steps. Each step:
- has a 1-line description
- cites ≥1 file:line reference (Phase 1 explore-grounded)
- has optional anchor `<!-- step-N -->` for checkpoint/approval-required references>

## 7. Tools Required

<Bullet list of tools the implementer needs (CLI tools, MCP servers, environment variables). Use "none" if the task is a pure-code change.>

## 8. Approval Points

<Bullet list pointing to specific steps that require user-approval gates during /implement run. References step anchors. Use "none" if /implement may run autonomously start-to-finish.>

## 9. Validation

<Body describing how to verify the implementation worked. References test types (unit/integration/e2e) or a manual verification procedure.>

## 10. Rollback-Recovery

<Body describing how to revert the change cleanly if it goes wrong. Includes commit-revert plan, data-migration rollback, feature-flag toggle, or explicit "no rollback needed — pure additive" with rationale.>

## 11. Done Condition

<Single statement of the observable signal that the task is complete. E.g., "all 5 acceptance tests green AND PR approved" / "feature ships behind flag AND telemetry shows ≥1 successful use".>
```

(Note: section 11 «Done Condition» is the 10th sectioned body section but uses heading level «## 11.» — the count starts at 1, not 0; the schema-completeness check counts 10 sections, `## 1` through `## 11` reading «11 = Done Condition» as section 10. Pedantic count adjustment for header consistency.)

Body sections beyond the 10 (allowed):
- `## Considered Alternatives` — captured from Phase 4 Always present if Phase 4 ran with ≥2 approaches.
- `## Milestones` — captured from Phase 5 milestone-mode. Present only if milestone-mode was picked.

## Per-section content guidance

**Section 1 (Objective):** ONE sentence. NOT a problem statement, NOT a user story, NOT a title — a declarative goal. Examples:
- ✅ "Add OAuth login to the customer portal."
- ❌ "We need OAuth because users keep complaining about password resets." (problem statement, not objective)
- ❌ "As a customer, I want to login with OAuth." (user story, not objective)

**Section 6 (Steps):** Each step cites ≥1 file:line reference unless it's a meta-step (e.g., "Step 1: Create new branch"). Phase 7 validator check #3 enforces this.

**Section 8 (Approval Points):** This is the contract /implement reads to know when to pause for user gates. Phase 2 inner loop checks this at the start of each step and fires `AskUserQuestion` if the step anchor matches an Approval-Points entry. ↔ the contract.

**Section 10 (Rollback-Recovery):** «none — pure additive» is a valid body BUT must be explicit. Phase 7 validator does not auto-fail if body is «none» — it auto-fails if body is empty.

**Sections 4, 5, 10 for Trivial tasks:** may have body content «none — task scope precludes» with brief rationale. Headers MUST exist; bodies MAY be «none with rationale».

## Milestone-mode

If Phase 5 milestone-mode was picked, Phase 6 emits:
- `spec.md` — top-level with section 6 «Steps» listing milestone names (not raw steps) + a body section `## Milestones` indexing the sibling files.
- `milestone-1.md`, `milestone-2.md`, …, each with its own 10-section schema scoped to the milestone.

Each `milestone-N.md` frontmatter MAY add `parent_spec: <task-slug>` to link back to the top-level spec.md (— tentatively yes; deferred to implementation).
