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
geniro_schema_version: m5-v3 # schema version — set to m5-v4 when launch_config is present; m5-v3 when >=1 chain-enrichment field is present (parent_ref.title|status|scope, siblings, chain_fetched_at); else m5-v2 (workflow_refs[] w/o enrichment) or m5-v1 (no workflow_refs[]); m5-v1..v4 all valid downstream
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
    title: "Case Radar performance epic" # optional (m5-v3) — epic title
    status: In Progress # optional (m5-v3) — epic status
    scope: "Cut Case Radar backfill latency below 5 min across all tenants." # optional (m5-v3) — short epic scope, <=280 chars, trimmed at a sentence boundary
  siblings: # optional (m5-v3) — depth-1 sibling sub-tasks under the same parent; <=8 entries; omit key when none
  - issue_id: CI-301
    title: "Add per-user job partitioning"
    status: Done
  - issue_id: CI-302
    title: "Backfill progress telemetry"
    status: In Progress
  chain_fetched_at: 2026-05-26T10:42:15Z # optional (m5-v3) — when the related-task chain was fetched; staleness-checked INDEPENDENTLY of fetched_at
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
launch_config: # optional, SEPARATE block (NOT goal-state) — present only when the user pre-defined /geniro:implement settings at plan time (m5-v4). Absent block = /geniro:implement asks its Step 0 setup questions interactively.
  workspace: new-branch # new-branch | current-branch | worktree | here
  deep_mode: false # true | false
  branch_freshness: rebase # merge | rebase | skip
  ship_mode: draft-pr # commit-no-push | draft-pr | ready-for-review | stop-after-review
  tracker_status: move-to-in-progress # OPTIONAL even within the block: move-to-in-progress | leave-unchanged — written only when the spec has a linked tracker ticket (workflow_refs[]); pre-answers /geniro:implement's kickoff "Move to In Progress?" question
---
```

**Field origins:**
- `tier` → `timestamp`: required base.
- `geniro_kind` → `lifecycle`: schema markers + extensions.
- `workflow_refs`: optional tracker linkage (m5-v2). Omitted from frontmatter when no tracker was linked (pure inline-task /geniro:plan); downstream skills treat absence as "no tracker linkage". The m5-v3 chain-enrichment fields (`parent_ref.title`/`status`/`scope`, `siblings[]`, `chain_fetched_at`) are optional additions written by the related-task chain context helper (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md`); their absence is m5-v2-equivalent.
- `budget` → `tools_required`: goal-state block embedded in frontmatter.
- `launch_config`: optional, SEPARATE block (NOT part of the goal-state block — goal-state encodes the task's constraints; `launch_config` encodes how `/geniro:implement` is invoked). Written at Phase 8 approval, inside the same approval-time spec rewrite that flips `lifecycle: draft` → `lifecycle: approved`, only when the user opts into pre-defining `/geniro:implement` settings; `/geniro:implement` reads it at Step 0 and skips the corresponding setup questions, treating an absent block as "ask interactively". Bumps `geniro_schema_version` to `m5-v4` when present. When the spec carries a linked tracker ticket, the block also carries the optional `tracker_status` key (`move-to-in-progress` | `leave-unchanged`), pre-answering `/geniro:implement`'s kickoff move-to-In-Progress question; it is omitted when no tracker was linked, and rides inside `m5-v4` with no version bump. Canonical contract (shape, enums, version rule, doctrine boundary): `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`.

**`workflow_refs[]` per-entry shape + schema-version compatibility:** canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md` — the per-entry required/optional fields (`kind` / `issue_id` / `url` / `fetched_at` required; the optional cache + m5-v3 chain-enrichment fields), the m5-v1/m5-v2/m5-v3/m5-v4 version rule (m5-v4 carries `workflow_refs[]` identically; see line 85 for its `launch_config` block), and the tracker mutation-responsibility note. /geniro:plan writes the frontmatter shown in the example above; the structured field is the cross-skill contract every consumer reads from that shared schema.

**`status:` namespace note.** The state-tier schema reserves `status:` for state lifecycle (`in-progress|done|failed`). design-doc lifecycle uses a distinct key (`lifecycle:` — values `draft|approved|superseded`) to avoid clash. State-tracking already handled via the state.md sibling file, so spec.md doesn't need the spec's `status:` field. Phase 8 flips `lifecycle: draft` → `lifecycle: approved` on user-approve.

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

<Checklist of implementation steps — each step is a markdown checkbox, written unchecked, that the person building ticks off as it lands (often building one step at a time). Each step:
- renders as `- [ ] N. <1-line description>` — the unchecked `- [ ]` checkbox, then the literal step number, then the description
- cites ≥1 file:line reference (Phase 1 explore-grounded)
- keeps its optional `<!-- step-N -->` anchor for checkpoint/approval-required references>

## 7. Tools Required

<Bullet list of tools the implementer needs (CLI tools, MCP servers, environment variables). Use "none" if the task is a pure-code change.>

## 8. Approval Points

<Bullet list pointing to specific steps that require user-approval gates during /geniro:implement run. References step anchors. Use "none" if /geniro:implement may run autonomously start-to-finish.>

## 9. Validation

<Body describing how to verify the implementation worked. References test types (unit/integration/e2e) or a manual verification procedure.

A criterion MAY carry an optional `verify: <shell command>` line — a single executable command that proves that one criterion (e.g. `verify: pnpm --filter api test:contract`, `verify: curl -fsS localhost:3000/healthz`). /geniro:implement runs each `verify:` command once at the end of its implementation phase and attaches the result as evidence. Omit `verify:` for any criterion checked by hand or by the project-wide test suite — absent `verify:` is the default and keeps today's prose-only behavior. When present, `verify:` must be a non-empty command string. A `verify:` command must be a READ-ONLY acceptance check (tests, health probes, lint, type-check, a read-only query) — NOT a ship / deploy / side-effecting command. /geniro:implement screens each command and refuses to auto-run any that pushes, opens a PR, or deploys (`git push` / `gh pr create` / `deploy` / `release`, etc.), because it runs before the ship gate; a ship/deploy `verify:` is surfaced for you to run yourself or remove.>

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
- `## Comment Resolution Map` — captured by `/geniro:resolve` (`producer: resolve`). **Optional** — present only on a resolve-produced spec, mapping each PR review comment to its verdict + fix Step; absent on every `/geniro:plan` spec. Allowed-optional, so a plan spec without it still passes.

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

**Section 6 (Steps):** Each step is written as an unchecked markdown checkbox — `- [ ] N. <description> <!-- step-N -->` — so the person building can tick `- [ ]` → `- [x]` by hand as each step lands (a workflow that suits building one step at a time). The checkbox is a tracking aid only — like /geniro:review's finding checkbox, no validator or downstream consumer reads its checked state, and /geniro:implement never edits spec.md to tick it (the spec is the user's upstream artifact). Keep the literal `N.` step number and the `<!-- step-N -->` anchor — checkpoints and the Phase 7 step-count check (check #7) resolve steps by them, not by a bare leading digit. Each step cites ≥1 file:line reference unless it's a meta-step (e.g., "Create new branch"); Phase 7 validator check #3 enforces this and matches the citation anywhere on the line, so the `- [ ] N.` prefix does not affect it. Example:

```markdown
- [ ] 1. Add `entryPoint` enum (`constants.ts:12`) and `ContextBundle` types (`context-bundle.types.ts:1`). <!-- step-1 -->
- [ ] 2. Widen the contract in `context-assembler.interface.ts:3-9` (`+userId`, `+entryPoint`). <!-- step-2 -->
```

**Section 8 (Approval Points):** Declares step anchors that warrant a user-approval pause during the /geniro:implement run. These are advisory goal-state documentation — /geniro:implement does not auto-gate on a step-anchor match; the enforced Edit/Write gate in /geniro:implement is the handoff `open_questions[]` check (Phase 1 handoff-resolution step). Use "none" if /geniro:implement may run autonomously start-to-finish.

**Section 10 (Rollback-Recovery):** "none — pure additive" is a valid body BUT must be explicit. Phase 7 validator does not auto-fail if body is "none" — it auto-fails if body is empty.

**Sections 4, 5, 10 for Trivial tasks:** may have body content "none — task scope precludes" with brief rationale. All 11 headers stay present even for Trivial tasks — the Phase 7 schema_completeness check parses the section headers and fails validation if one is missing; the body under a non-applicable header may be "none with rationale".

## Milestone-mode

If Phase 5 milestone-mode was picked, Phase 6 emits:
- `spec.md` — top-level with section 6 "Steps" listing milestone names as the same `- [ ] N. <milestone name>` checkboxes (not raw steps) + a body section `## Milestones` indexing the sibling files.
- `milestone-1.md`, `milestone-2.md`, …, each with its own 11-section schema scoped to the milestone.

Each `milestone-N.md` frontmatter MAY add `parent_spec: <task-slug>` to link back to the top-level spec.md.
