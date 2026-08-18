# spec.md template — schema

## Contents

- Frontmatter
- Body — 11 sections
- Per-section content guidance
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
geniro_schema_version: m5-v4 # schema version — this example carries a launch_config block (below), which requires m5-v4; a spec with no launch_config and no m5-v3 chain-enrichment fields uses m5-v2. Version-selection rule canonical in workflow-refs-schema.md § Schema-version compatibility
task_slug: <slug> # extension
topic: <one-sentence-topic> # extension
mode: <IDEA|DESIGN_DOC> # extension
effort_tier: <trivial|small|medium|big> # extension
lifecycle: draft # design-doc lifecycle (draft|approved|superseded)
workflow_refs: # optional — tracker linkage (Linear / Jira / GitHub Issues / Asana)
- kind: linear # matches .geniro/workflow/<kind>.md filename
  issue_id: ENG-303
  url: https://linear.app/.../issue/ENG-303/...
  fetched_at: 2026-05-26T10:42:13Z # ISO-8601 UTC — staleness check by downstream
  title: "Parallelize telemetry backfill via per-user jobs"
  suggested_branch: ci-303-parallelize-case-radar-backfill-via-per-user-jobs
  status: Todo # tracker status at fetch time
  parent_ref: # optional — Linear parent epic / Jira epic
    kind: linear
    issue_id: ENG-300
    url: https://linear.app/...
    title: "Telemetry performance epic" # optional (m5-v3)
    status: In Progress # optional (m5-v3)
    scope: "Cut telemetry backfill latency below 5 min across all tenants." # optional (m5-v3)
  siblings: # optional (m5-v3)
  - issue_id: ENG-301
    title: "Add per-user job partitioning"
    status: Done
  - issue_id: ENG-302
    title: "Backfill progress telemetry"
    status: In Progress
  chain_fetched_at: 2026-05-26T10:42:15Z # optional (m5-v3)
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

**`workflow_refs[]` per-entry shape + schema-version compatibility:** canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md` — the per-entry required/optional fields (`kind` / `issue_id` / `url` / `fetched_at` required; the optional cache + m5-v3 chain-enrichment fields), the m5-v1/m5-v2/m5-v3/m5-v4 version rule (m5-v4 carries `workflow_refs[]` identically; see the `launch_config` bullet above for that block), and the tracker mutation-responsibility note. /geniro:plan writes the frontmatter shown in the example above; the structured field is the cross-skill contract every consumer reads from that shared schema.

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

<Bullet list of the premises the plan rests on, each written as a predicate a reader can check against the code or the environment — "the `users` table has a `deleted_at` column", "OAuth library version ≥2.5", "the test DB is available" — never a gesture at an area ("auth is handled elsewhere"). Every design branch the planning grill closed without an answer belongs here; a premise stated this way is verified claim by claim before approval, and one left in prose is not. Use "none" if scope precludes assumptions.>

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

Author a `verify: <shell command>` line on every criterion a single read-only command can prove (e.g. `verify: pnpm --filter api test:contract`, `verify: curl -fsS localhost:3000/healthz`) — a criterion a command decides is settled by the run itself, while a prose criterion is settled only when a human later re-reads the spec. /geniro:implement runs each `verify:` command once at the end of its implementation phase and attaches the result as evidence. Reserve prose-only for the criteria a command cannot settle: a visual check, third-party state, a judgment call. Scope each command to its own criterion — restating the project-wide test command duplicates a run /geniro:implement has already made. The field stays structurally optional: a criterion without `verify:` still validates. When present, `verify:` must be a non-empty command string. A `verify:` command must be a READ-ONLY acceptance check (tests, health probes, lint, type-check, a read-only query) — NOT a ship / deploy / side-effecting command. /geniro:implement screens each command and refuses to auto-run any that pushes, opens a PR, or deploys (`git push` / `gh pr create` / `deploy` / `release`, etc.), because it runs before the ship gate; a ship/deploy `verify:` is surfaced for you to run yourself or remove.>

## 10. Rollback-Recovery

<Body describing how to revert the change cleanly if it goes wrong. Includes commit-revert plan, data-migration rollback, feature-flag toggle, or explicit "no rollback needed — pure additive" with rationale.>

## 11. Done Condition

<Single statement of the observable signal that the task is complete. E.g., "all 5 acceptance tests green AND PR approved" / "feature ships behind flag AND telemetry shows ≥1 successful use". An outcome-bearing change adds a second clause naming the production signal that would show it worked — see the section-11 guidance below.>
```

The schema has exactly 11 numbered headers (`## 1` … `## 11`); downstream consumers and the validator key off header text, not ordinal count.

Body sections beyond the 11 (allowed):
- `## Considered Alternatives` — captured from Phase 4. Always present if Phase 4 ran with ≥2 approaches.
- `## Milestones` — captured when `approvals[]` carries a `milestone_slice` entry picked "Slice into milestones" (Phase 5, or a Phase 7.5 milestone re-open). Present only then.
- `## Comment Resolution Map` — captured by `/geniro:resolve` (`producer: resolve`). **Optional** — present only on a resolve-produced spec, mapping each PR review comment to its verdict + fix Step; absent on every `/geniro:plan` spec. Allowed-optional, so a plan spec without it still passes.

## Per-section content guidance

**Code snippets (any section):** a snippet belongs in a section only when it encodes a decision more precisely than prose can — a schema, type shape, state machine, or API contract — trimmed to the decision-rich parts. Keep working-demo code out of the spec: it goes stale fast, and /geniro:implement re-derives it from the cited files anyway.

**Section 1 (Objective):** ONE sentence. NOT a problem statement, NOT a user story, NOT a title — a declarative goal. Examples:
- ✅ "Add OAuth login to the customer portal."
- ❌ "We need OAuth because users keep complaining about password resets." (problem statement, not objective)
- ❌ "As a customer, I want to login with OAuth." (user story, not objective)

**Section 6 (Steps):** Each step is written as an unchecked markdown checkbox — `- [ ] N. <description> <!-- step-N -->` — so the person building can tick `- [ ]` → `- [x]` by hand as each step lands (a workflow that suits building one step at a time). The checkbox is a tracking aid only — like /geniro:review's finding checkbox, no validator or downstream consumer reads its checked state, and /geniro:implement never edits spec.md to tick it (the spec is the user's upstream artifact). Keep the literal `N.` step number and the `<!-- step-N -->` anchor — checkpoints and the Phase 7 step-count check (`checkpoints`) resolve steps by them, not by a bare leading digit. Each step cites ≥1 file:line reference unless it's a meta-step (e.g., "Create new branch"); the Phase 7 validator's `source_materials` check enforces this and matches the citation anywhere on the line, so the `- [ ] N.` prefix does not affect it. Example:

```markdown
- [ ] 1. Add `entryPoint` enum (`constants.ts:12`) and `ContextBundle` types (`context-bundle.types.ts:1`). <!-- step-1 -->
- [ ] 2. Widen the contract in `context-assembler.interface.ts:3-9` (`+userId`, `+entryPoint`). <!-- step-2 -->
```

**Section 8 (Approval Points):** Declares step anchors that warrant a user-approval pause during the /geniro:implement run. These are advisory goal-state documentation — /geniro:implement does not auto-gate on a step-anchor match; the enforced Edit/Write gate in /geniro:implement is the handoff `open_questions[]` check (Phase 1 handoff-resolution step). Use "none" if /geniro:implement may run autonomously start-to-finish.

**Section 9 (Validation):** for each criterion verified by tests, name the public seam the test enters through — the exported function, endpoint, or CLI command a real caller uses (e.g. `POST /api/orders`, `checkout(cart, payment)`). Prefer an existing seam over a new one, and the highest seam that still observes the behavior (seam vocabulary: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/architecture-vocabulary.md`); cite prior art — a similar existing test file — when one exists. Leaving the seam unnamed defers the choice to /geniro:implement mid-build, where a wrong seam surfaces as a review finding instead of at the section-approval gate.

**Section 10 (Rollback-Recovery):** "none — pure additive" is a valid body BUT must be explicit. Phase 7 validator does not auto-fail if body is "none" — it auto-fails if body is empty.

**Section 11 (Done Condition):** the first clause states when the work is *built* — tests green, PR approved. When the change is also meant to move something in production — adoption, latency, error rate, conversion, cost — add a second clause naming the signal that would show it worked, the source that reads it, and when to look: "the APM dashboard metric shows p95 checkout latency under 400ms, one week after rollout". Word it in one of the observable-signal shapes (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/done-condition-check.md` §"Stopping-condition ontology") — a clause matching none of them is free-text, and free-text is never graded, so at ship time the user is not told the outcome criterion is still open. Take the source from the project's declared `## Data Sources` block (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`) and read the current value through it, so the target sits against a measured baseline rather than a guess. Where no declared source can read the signal, write that gap in place of the number — "no source currently measures checkout latency" — which is a finding the user can act on; a baseline nobody measured reads as measured, and the first person to act on it is the one who discovers it was invented. Internal refactors, pure bug fixes, and tooling changes carry no outcome clause.

**Sections 4, 5, 10 for Trivial tasks:** may have body content "none — task scope precludes" with brief rationale. All 11 headers stay present even for Trivial tasks — the Phase 7 schema_completeness check parses the section headers and fails validation if one is missing; the body under a non-applicable header may be "none with rationale".

## Milestone-mode

If Phase 5 milestone-mode was picked, Phase 6 emits:
- `spec.md` — top-level with section 6 "Steps" listing milestone names as the same `- [ ] N. <milestone name>` checkboxes (not raw steps) + a body section `## Milestones` indexing the sibling files.
- `milestone-1.md`, `milestone-2.md`, …, each with its own 11-section schema scoped to the milestone.

Each `milestone-N.md` frontmatter MAY add `parent_spec: <task-slug>` to link back to the top-level spec.md, and MAY add `blocked_by: [<milestone numbers>]` listing the milestones that must land first — omit `blocked_by` when strict ordinal order is the real dependency. The `## Milestones` index in spec.md mirrors the `blocked_by` edges, so the user can work the frontier — any milestone whose blockers are all done — rather than only top-to-bottom.

In `milestone-N.md` for N ≥ 2, pair each step's `file:line` citation with a symbol anchor (the function or type name at the cite) — earlier milestones shift line numbers before this spec is consumed, and the symbol lets /geniro:implement's spec fact-check re-resolve the reference instead of flagging it stale.
