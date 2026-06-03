# Plan — AUQ Templates & State Schema Reference

Detail sections extracted from `skills/plan/plan-loop.md` to keep the main loop file lean. The orchestrator reads this file when plan-loop references one of the sections below by name.

## Contents

1. state.md frontmatter — initial template (Phase 0.3)
2. Phase 3 clarifying AUQ — shape with `preview` fields
3. Phase 4 approach AUQ — shape with ASCII-sketch previews
4. Phase 5 cluster AUQ — batched cluster approval (3 dependency-ordered gates) + milestone-mode
5. Phase 8 approval AUQ — schema-rich question body

---

## 1. state.md frontmatter — initial template

Written at Phase 0.3 via `atomic_state_write` to `.geniro/planning/<task-slug>/state.md`:

```yaml
---
tier: T1.5
producer: plan
schema-version: 1
branch: <git-branch>
worktree: <git-rev-parse-show-toplevel>     # optional, recommended for cross-worktree resume
timestamp: <ISO-8601 UTC>
phase: mode-detect
status: in-progress
non-resumable-actions: []
approvals: []
task_slug: <slug>
mode: <IDEA|DESIGN_DOC>
prd_mode: true                               # optional, present only when --prd was passed (Phase 0.1)
---

# State: <topic>

## Inputs
- $ARGUMENTS: "<raw>"
- mode: <IDEA|DESIGN_DOC>
- design-doc-path (if DESIGN_DOC): <abs-path>

## Tool log

## Errors

## Open Questions
```

After all 11 sections approved in Phase 5, `## Workflow Refs` (populated by Phase 1.4), `## UI Preview` (populated by Phase 2 when triggered), and `## Problem Framing` (populated by Phase 0.5 when `--prd` was passed) appear as additional body sections. The frontmatter `phase:` field transitions through the state machine (`mode-detect` → `problem-discovery` (only when `prd_mode: true`) → `explore` → `visual-companion` / `clarify` → `approaches` → `section-approve` → `write-spec` → `validate` → `spec-challenge` → `user-approve` → `handoff` → `done`). The optional `prd_mode: true` frontmatter key is set in Phase 0.1 when `$ARGUMENTS` carries `--prd`; absent otherwise.

---

## 2. Phase 3 clarifying AUQ — batched independent questions, sequenced dependents

Batch independent clarifying questions into ONE `AskUserQuestion` call (up to 4 questions per call). Fire questions sequentially only when one question's answer changes another's options (a genuine dependency). Every option carries a **`preview` field** with concrete consequence content (code anchor / config diff / behavior trace, ≤6 lines per preview).

A single batched call carrying two independent questions:

```yaml
questions:
  - header: "Auth method"
    question: "Which auth flow should this endpoint use?"
    options:
      - label: "JWT — existing middleware"
        preview: |
          Adds `@UseGuards(JwtAuthGuard)` to controller. Reads token
          from Authorization header. Throws 401 on missing/invalid.
          Test: `expect(401).toMatchObject({code: 'UNAUTHENTICATED'})`.
      - label: "Session cookie — existing session middleware"
        preview: |
          Adds `@UseGuards(SessionGuard)`. Reads `session_id` cookie.
          Test mirror of /auth/session.spec.ts. Same 401 shape.
      - label: "Skip — proceed assuming JWT"
        preview: |
          Recorded assumption: "endpoint uses JWT middleware (default)".
          Surfaced in spec.md section 4 Assumptions for /geniro:implement to verify.
  - header: "Rate limit"
    question: "Should the endpoint enforce a per-user rate limit?"
    options:
      - label: "Yes — reuse RateLimitGuard"
        preview: |
          Adds `@UseGuards(RateLimitGuard)` (src/common/rate-limit.guard.ts:18).
          Default 60 req/min/user; 429 on exceed.
      - label: "No — unlimited"
        preview: |
          No guard added. Matches sibling read-only endpoints.
      - label: "Skip — proceed assuming no limit"
        preview: |
          Recorded assumption: "no rate limit". Surfaced in section 4 Assumptions.
```

These two questions are independent — auth method does not change the rate-limit options — so they ship in one call. A dependent pair (e.g., "Which datastore?" → then options for "Which migration tool?" that depend on the datastore pick) fires sequentially instead. Every `preview` field carries concrete consequence content — empty options waste user attention. The ≤5-total cap holds across calls; chain a second call if more than 4 independent questions exist rather than dropping or merging any.

Each answered question → append entry to state.md frontmatter `approvals[]` via `atomic_state_write`. A batched call returns all its answers at once — append one entry per answer before proceeding past the batch:

```yaml
approvals:
  - category: clarify_<dim>          # e.g., clarify_auth_method
    prompt: "Which existing auth flow should the new feature integrate with?"
    options: ["OAuth (src/auth/oauth.ts)", "JWT (src/auth/jwt.ts)", "Skip — proceed assuming OAuth"]
    picked: "OAuth (src/auth/oauth.ts)"
    at: 2026-05-17T10:50:00Z
    asked_in_phase: clarify
```

---

## 3. Phase 4 approach AUQ — shape with ASCII-sketch previews

Single-select; `Recommended` first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` (§Recommended-label policy). The `Recommended` marker reflects the Phase 4 §4.2 stress-test ranking — an approach with a blocking feasibility risk is never Recommended. Each option's `preview` contains an ASCII data-flow / architecture sketch (5-10 lines) + key code identifier + one-line dominant tradeoff + the `Stress-test:` verdict line from §4.2:

```yaml
header: "Approach"
question: "Which approach do you want to pursue?"
options:
  - label: "Service-layer fan-out (Recommended)"
    description: "Split per-user backfill into queued jobs; orchestrator dequeues N at a time."
    preview: |
      ┌─────────────┐    ┌──────────────────┐    ┌────────────┐
      │ /backfill    │─→─│ BackfillQueue.add │─→─│ Worker pool│
      └─────────────┘    └──────────────────┘    └────────────┘
      New: src/jobs/BackfillQueue.ts + per-user job class
      Trade-off: +1 infrastructure piece; bounded memory under load.
      Stress-test: no blockers; queue table migration needed (minor, src/db/schema.ts:40).
  - label: "In-process Promise.all"
    description: "Loop users, await Promise.all in chunks of 50."
    preview: |
      for (chunk of chunks(users, 50)) await Promise.all(chunk.map(backfill))
      New: tweaks to src/backfill/runner.ts only
      Trade-off: zero new infrastructure; memory spike on large datasets.
      Stress-test: major — runner.ts:88 already holds full user set in memory; spike compounds.
```

User pick → append to `approvals[]` with category `approach_choice`. Other approaches captured to body section `## Considered Alternatives`. The unsignaled (non-recommended) picks fire L2 emit via `emit-rejection.sh` when the picked label diverges from the recommended label.

---

## 4. Phase 5 cluster AUQ — batched cluster approval + milestone-mode

### 4.1 Cluster authoring procedure

Group the 11-section schema into 3 dependency-ordered clusters. Author and gate cluster-by-cluster; each cluster fires ONE batched `AskUserQuestion` call carrying one question per section:

| Cluster | Plain-English name | Sections | `header` chips (≤12 chars each) |
|---|---|---|---|
| 1 | Goal & scope | 1 Objective, 2 Scope-Included, 3 Scope-Excluded | "Objective" / "In scope" / "Out of scope" |
| 2 | Approach & steps | 4 Assumptions, 5 Risks, 6 Steps, 7 Tools Required | "Assumptions" / "Risks" / "Steps" / "Tools" |
| 3 | Safety & done | 8 Approval Points, 9 Validation, 10 Rollback-Recovery, 11 Done Condition | "Approvals" / "Validation" / "Rollback" / "Done" |

Procedure per cluster:

1. **Author the cluster's sections inline** (in orchestrator working memory) using Phase 1 research findings + Phase 3 clarifying answers + Phase 4 picked approach + (when present) Phase 2 UI Preview as substrate. Do NOT render section bodies to chat — the option `preview` fields ARE the rendering surface.

2. **Print a one-line chat lead-in**, e.g., `"Reviewing the plan's Goal & scope — 3 sections, focus an option to inspect each."` For Trivial/Small tier, a "none — task scope precludes" section is noted here as a one-line aside (no approval question fires for it).

3. **Fire ONE batched AUQ** with one question per section in the cluster. Each question has three options carrying ADR-style `preview` content:

   - **Approve (Recommended)** — `preview`: the ADR digest + concrete example —
     ```
     DECISION: <what this section commits to — 1 line>
     WHY: <rationale grounded in a Phase 1 finding file:line + the Phase 4 chosen approach — 1-2 lines>
     HOW: <how /geniro:implement realizes it — concrete steps / files / identifiers — 1-2 lines>
     <ASCII data-flow / sequence diagram — only for sections that benefit, esp. section 6 Steps>
     Example: <the per-section concrete example from plan-reference.md §"Concrete-example per section type">
     ```
   - **Revise — I'll describe** — `preview`: the current section content + `"Type your revision in Other; I'll re-author and re-ask."`
   - **Skip — accept as-is** — `preview`: the concrete consequence of skipping this section, e.g., `"Validation skipped — /geniro:implement's reviewer cannot verify acceptance criteria; manual checks required."`

4. **Persist each section pick** to `approvals[]` with category `section_<id>` (e.g., `section_objective`, `section_scope_included`). The cluster is a presentation grouping only — no `cluster_<id>` category.

5. **On approve, author the next cluster** (step 1). For any section marked "Revise", re-author it AND any sections in the same cluster that depend on it, then re-fire the cluster's batched AUQ (max 3 revision rounds per cluster). After all 3 clusters approved → Phase 6.

Literal cluster-1 batched AUQ:

```yaml
questions:
  - header: "Objective"
    question: "Approve the objective?"
    options:
      - label: "Approve (Recommended)"
        preview: |
          DECISION: Add a /backfill endpoint that re-derives per-user
          telemetry counts on demand.
          WHY: src/telemetry/aggregate.ts:120 shows counts drift after
          retroactive event edits; chosen approach = service-layer fan-out.
          HOW: /geniro:implement adds BackfillController.run() calling the queued
          BackfillQueue service; no schema change to events.
          Example: "User triggers /backfill → counts reconcile within 30s."
      - label: "Revise — I'll describe"
        preview: |
          Current: "Add a /backfill endpoint that re-derives per-user
          telemetry counts on demand."
          Type your revision in Other; I'll re-author and re-ask.
      - label: "Skip — accept as-is"
        preview: |
          Objective accepted unchanged; downstream sections build on it.
  - header: "In scope"
    question: "Approve what's in scope?"
    options:
      - label: "Approve (Recommended)"
        preview: |
          DECISION: BackfillController + BackfillQueue service + per-user
          job class are in scope.
          WHY: integration surface from Phase 1 — src/jobs/ already hosts
          a queue runner (src/jobs/runner.ts:40); reuse it.
          HOW: /geniro:implement touches src/telemetry/, src/jobs/, src/api/routes.ts.
          Example: bullets map to src/jobs/BackfillQueue.ts (new), routes.ts (edit).
      - label: "Revise — I'll describe"
        preview: |
          Current: BackfillController + BackfillQueue + per-user job class.
          Type your revision in Other; I'll re-author and re-ask.
      - label: "Skip — accept as-is"
        preview: |
          In-scope list accepted; /geniro:implement edits exactly these surfaces.
  - header: "Out of scope"
    question: "Approve what's out of scope?"
    options:
      - label: "Approve (Recommended)"
        preview: |
          DECISION: Event-schema migration and the admin dashboard are
          out of scope.
          WHY: Phase 4 chosen approach reuses existing schema; dashboard is
          a separate Linear epic (no file in the touched surface).
          HOW: /geniro:implement will NOT touch src/db/schema.ts or src/admin/.
          Example: "Backfill runs against the current events table as-is."
      - label: "Revise — I'll describe"
        preview: |
          Current: schema migration + admin dashboard excluded.
          Type your revision in Other; I'll re-author and re-ask.
      - label: "Skip — accept as-is"
        preview: |
          Exclusions accepted; out-of-scope work stays out.
```

**Tier-scaling.** Sections 4 / 5 / 10 may be "none — task scope precludes" for Trivial/Small tasks — note these in the cluster lead-in rather than firing an approval question. At Trivial tier the clusters may collapse to 1-2 batched AUQs; the default 3-cluster grouping applies to Medium/Big.

Empty AUQ options (`Approve / Revise / Skip` text only) degrade trust ("the skill is just clicking through"); the ADR-style `preview` makes each option load-bearing — it re-explains what was decided, why, and how /geniro:implement will build it.

### 4.2 Milestone-mode AUQ (Big tasks only)

Fires BEFORE Phase 6 entry when effort tier is Big AND section 6 "Steps" has ≥10 discrete steps OR estimated wall-time ≥1 day:

```yaml
header: "Milestone slicing"
question: "This task is large enough to slice into milestones. Slice it now or keep as a single spec?"
options:
  - label: "Slice into milestones"            # Recommended for Big
    description: "Model proposes 3-7 milestone names; user approves; the spec write step emits sibling milestone-N.md files alongside spec.md."
  - label: "Keep as a single spec"
    description: "The spec write step emits only spec.md; /geniro:implement consumes the whole thing."
```

If "Slice into milestones" picked:

1. Fire a follow-up AUQ with the proposed milestone names (single-select for "approve all" or multi-select pick per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`).
2. After approval, Phase 6 writes the top-level spec.md (with section 6 "Steps" listing milestones and a new body section `## Milestones` indexing the sibling files) PLUS each `milestone-N.md` with its own 11-section schema scoped to the milestone.
3. Persist to `approvals[]` with category `milestone_slice`.

Hand-off (Phase 9) offers `/geniro:implement .geniro/planning/<slug>/milestone-1.md` for sliced specs. The milestone-mode AUQ fires only at Big tier; not Small/Medium/Trivial.

---

## 5. Phase 8 approval AUQ — schema-rich question body

Multi-line markdown rendering the schema digest inline. User sees the full plan summary in the question body before picking:

```
header: "Approve spec"
question: |
  Spec ready at .geniro/planning/<slug>/spec.md.

  **Objective:** <section 1 body — single sentence>

  **Scope:** <bullet count from section 2 Included + section 3 Excluded summary>

  **Approval Points:** <bullet list from section 8 "Approval Points", max 5 shown with "... and N more" if >5>

  **Risk class:** <auto-computed: "low" / "medium" / "high" based on section 5 Risks bullet count + section 7 forbidden_actions field>

  **Rollback:** <section 10 body summary, 1-2 sentences>

  **Done Condition:** <section 11 body — observable signal>

  **Scope summary:** <touched-file glob count from section 2 Scope.Included>

  **Expiration:** Approval valid for the current planning session; re-approval needed if spec.md is edited after this point.

  How do you want to proceed?

options:
  - label: "Approve — proceed to hand-off"   # Recommended
    description: "The hand-off step runs next."
  - label: "Request changes — I'll describe"
    description: "Fires a sub-AUQ for revision text; revisions re-run affected sections (max 3 user-revision rounds before escalation)."
  - label: "Abort — discard spec"
    description: "Terminal aborted + ## Termination reason: user-rejected-at-phase-8; spec.md remains on disk but not committed."
```

On Approve pick: spec.md `lifecycle: draft` → `approved` flip; `git commit` fires (NOT in Phase 6); `non-resumable-actions[]` updated with the commit SHA; transition to Phase 9.

On Revision pick: max 3 user-revision rounds (Phase 8 → re-enter affected sections in Phase 5 → re-validate in Phase 7 → re-fire Phase 8 AUQ). On round 3 exhaust, escalation AUQ "Revision limit reached" fires with options "Accept as-is" / "Re-revise (kick fresh cycle)" / "Abort".
