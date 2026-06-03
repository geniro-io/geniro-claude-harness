# spec.md template — schema

## Contents

- Frontmatter
- Body — 11 sections
- Per-section content guidance
- Problem & Evidence (optional — PRD-mode only)
- Milestone-mode

---

Canonical 11-section markdown template that Phase 6 fills in. One source of truth for schema.

**Status:** Authoritative. Phase 7 mechanical validator enforces this layout exactly. Every spec.md emitted by `/geniro:plan` conforms.

## Frontmatter

```yaml
---
tier: T1.5 # required (spec.md lives in task-dir; durable — survives Ship cleanup)
producer: plan # required
schema-version: 1 # required
branch: <git-branch> # required
timestamp: <ISO-8601 UTC> # required
geniro_kind: design-doc # design-doc-detect.md contract — required marker
geniro_schema_version: m5-v2 # schema version (m5-v2 adds workflow_refs[])
task_slug: <slug> # extension
topic: <one-sentence-topic> # extension
mode: <IDEA|DESIGN_DOC> # extension
effort_tier: <trivial|small|medium|big> # extension
lifecycle: draft # design-doc lifecycle (draft|approved|superseded)
workflow_refs: # optional — tracker linkage (Linear / Jira / GitHub Issues / Asana)
- kind: linear # matches .geniro/workflow/<kind>.md filename
  issue_id: CI-303
  url: https://linear.app/manifestlabs/issue/CI-303/...
  fetched_at: 2026-05-26T10:42:13Z # ISO-8601 UTC — staleness check by downstream
  title: "Parallelize Case Radar backfill via per-user jobs"
  suggested_branch: ci-303-parallelize-case-radar-backfill-via-per-user-jobs
  status: Todo # tracker status at fetch time
  parent_ref: # optional — Linear parent epic / Jira epic
    kind: linear
    issue_id: CI-300
    url: https://linear.app/...
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
approval_required_for: # advisory: step_anchors flagged for a user-approval pause — goal-state documentation only (the enforced /geniro:implement Edit/Write gate is the handoff open_questions[] check, not a step-anchor match)
- step-3
- step-9
tools_required: ["pnpm", "docker", "gh"] # CLI tools the implementer needs in env — goal-state end
---
```

**Field origins:**
- Fields 1-5 (tier → timestamp): required base.
- Fields 6-11 (geniro_kind → lifecycle): schema markers + extensions.
- Field `workflow_refs`: optional tracker linkage (m5-v2). Omitted from frontmatter when no tracker was linked (pure inline-task /geniro:plan); downstream skills treat absence as "no tracker linkage".
- Fields 12-17 (budget → tools_required): goal-state block embedded in frontmatter.

**`workflow_refs[]` per-entry shape:**

| Field | Required? | Purpose |
|---|---|---|
| `kind` | yes | Workflow-file slug — `linear` / `jira` / `github-issues` / `asana`. Selects the matching `.geniro/workflow/<kind>.md` contract. |
| `issue_id` | yes | Tracker-native identifier (e.g., `CI-303`, `PROJ-42`). |
| `url` | yes | Full canonical URL. Downstream consumers may open without re-derivation. |
| `fetched_at` | yes | ISO-8601 UTC. Staleness check — downstream skills re-fetch if > 1 hour old. |
| `title`, `suggested_branch`, `status` | no | Cache of last-fetched payload. /geniro:implement Step 0 uses these to pre-fill AUQ defaults without re-fetching. |
| `parent_ref` | no | Epic/parent linkage. /geniro:review Phase 1 peer-PR scout uses this for `linear_bonus` ranking. Same per-entry shape recursively. |

**Schema-version compatibility:** `geniro_schema_version: m5-v1` (legacy, no `workflow_refs`) and `m5-v2` (this template) are both valid downstream. Readers accept both; strict validators (e.g., `validator-checks.md` check #14) verify the field shape only on `m5-v2`.

**`status:` namespace note.** reserves `status:` for state lifecycle (`in-progress|done|failed`). design-doc lifecycle uses a distinct key (`lifecycle:` — values `draft|approved|superseded`) to avoid clash. State-tracking already handled via the state.md sibling file, so spec.md doesn't need the spec's `status:` field. Phase 8 flips `lifecycle: draft` → `lifecycle: approved` on user-approve.

## Body — 11 sections

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

<Bullet list pointing to specific steps that require user-approval gates during /geniro:implement run. References step anchors. Use "none" if /geniro:implement may run autonomously start-to-finish.>

## 9. Validation

<Body describing how to verify the implementation worked. References test types (unit/integration/e2e) or a manual verification procedure.>

## 10. Rollback-Recovery

<Body describing how to revert the change cleanly if it goes wrong. Includes commit-revert plan, data-migration rollback, feature-flag toggle, or explicit "no rollback needed — pure additive" with rationale.>

## 11. Done Condition

<Single statement of the observable signal that the task is complete. E.g., "all 5 acceptance tests green AND PR approved" / "feature ships behind flag AND telemetry shows ≥1 successful use".>
```

The schema has exactly 11 numbered headers (`## 1` … `## 11`); downstream consumers and the validator key off header text, not ordinal count.

Body sections beyond the 11 (allowed):
- `## Considered Alternatives` — captured from Phase 4. Always present if Phase 4 ran with ≥2 approaches.
- `## Milestones` — captured from Phase 5 milestone-mode. Present only if milestone-mode was picked.
- `## Problem & Evidence` — captured from the Phase 0.5 problem-discovery interview. **Optional** — present only when `/geniro:plan --prd` ran (`prd_mode: true`); absent on every normal spec. The Phase 7 validator treats it as allowed-optional, so a normal spec without it still passes the schema check.

## Per-section content guidance

**Section 1 (Objective):** ONE sentence. NOT a problem statement, NOT a user story, NOT a title — a declarative goal. The problem framing belongs in the optional `## Problem & Evidence` section (PRD-mode), never in section 1. Examples:
- ✅ "Add OAuth login to the customer portal."
- ❌ "We need OAuth because users keep complaining about password resets." (problem statement, not objective — belongs in `## Problem & Evidence`)
- ❌ "As a customer, I want to login with OAuth." (user story, not objective)

## Problem & Evidence (optional — PRD-mode only)

Present only when `/geniro:plan --prd` ran. Carries the problem framing from the Phase 0.5 problem-discovery interview — kept separate from section 1 (Objective) so the Objective stays a clean declarative goal while the problem, evidence, and prioritization live here. Omit the whole section on a normal (non-PRD) spec; the Phase 7 validator's `schema_completeness` check allows its absence and allows its presence.

Layout:

```markdown
## Problem & Evidence

**Problem:** <one-sentence pain statement — the problem, not the feature>

**Evidence:** <what proves the problem is real — a metric, support-ticket count, recorded session, or quote. Use "none yet — unvalidated" honestly if no evidence exists; do not invent it.>

**Target user & job-to-be-done:** <who has the problem> — <the job they are trying to get done>

**Hypothesis:** If <X>, then <metric Y> moves by <Z>.

**Success metrics:** <1-3 metrics that confirm the problem is solved — these also seed section 9 Validation and section 11 Done Condition>

**Prioritization (MoSCoW):**
- Must: <...>
- Should: <...>
- Could: <...>
- Won't (this round): <... — seeds section 3 Scope — Excluded>
```

The Must set seeds section 2 (Scope — Included); the Won't set seeds section 3 (Scope — Excluded); the success metrics seed section 9 (Validation) and section 11 (Done Condition).

**Section 6 (Steps):** Each step cites ≥1 file:line reference unless it's a meta-step (e.g., "Step 1: Create new branch"). Phase 7 validator check #3 enforces this.

**Section 8 (Approval Points):** Declares step anchors that warrant a user-approval pause during the /geniro:implement run. These are advisory goal-state documentation — /geniro:implement does not auto-gate on a step-anchor match; the enforced Edit/Write gate in /geniro:implement is the handoff `open_questions[]` check (Phase 1 Step 12). Use "none" if /geniro:implement may run autonomously start-to-finish.

**Section 10 (Rollback-Recovery):** "none — pure additive" is a valid body BUT must be explicit. Phase 7 validator does not auto-fail if body is "none" — it auto-fails if body is empty.

**Sections 4, 5, 10 for Trivial tasks:** may have body content "none — task scope precludes" with brief rationale. Headers MUST exist; bodies MAY be "none with rationale".

## Milestone-mode

If Phase 5 milestone-mode was picked, Phase 6 emits:
- `spec.md` — top-level with section 6 "Steps" listing milestone names (not raw steps) + a body section `## Milestones` indexing the sibling files.
- `milestone-1.md`, `milestone-2.md`, …, each with its own 11-section schema scoped to the milestone.

Each `milestone-N.md` frontmatter MAY add `parent_spec: <task-slug>` to link back to the top-level spec.md.
