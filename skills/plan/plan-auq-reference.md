# Plan — AUQ Templates & State Schema Reference

Detail sections extracted from `skills/plan/plan-loop.md` to keep the main loop file lean. The orchestrator reads this file when plan-loop references one of the sections below by name.

## Contents

1. state.md frontmatter — initial template (Phase 0.3)
2. Phase 3 clarifying AUQ — message-first, batched independent, sequenced dependents
3. Phase 4 approach AUQ — message-first (diagrams in chat, lean AUQ)
4. Phase 5 cluster AUQ — message-first cluster approval (3 dependency-ordered gates) + milestone-mode
5. Phase 8 approval — message-first (summary in chat, lean AUQ)

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

## 2. Phase 3 clarifying AUQ — message-first, batched independent, sequenced dependents

Apply the Gate presentation contract (`${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §"Gate presentation contract"). When an option's consequence needs more than a one-line `description` (code anchor / config diff / behavior trace), render those consequences to a chat message FIRST, then fire a LEAN batched AUQ. Batch independent questions into ONE call (≤4 per call); sequence only a genuine dependency (one answer changes another's options).

Chat message rendered before the AUQ (two independent questions):

```markdown
Two things to confirm before I lock the approach:

**Auth method** — how should the new endpoint authenticate?
- JWT (existing middleware) — adds `@UseGuards(JwtAuthGuard)`; reads the token from the
  Authorization header; 401 on missing/invalid. Test: `expect(401)...code: 'UNAUTHENTICATED'`.
- Session cookie — adds `@UseGuards(SessionGuard)`; reads the `session_id` cookie;
  mirrors `/auth/session.spec.ts`; same 401 shape.
- Skip — record assumption "endpoint uses JWT (default)" in the Assumptions section for /geniro:implement to verify.

**Rate limit** — enforce a per-user rate limit?
- Yes — reuse `RateLimitGuard` (src/common/rate-limit.guard.ts:18); 60 req/min/user; 429 on exceed.
- No — unlimited; matches sibling read-only endpoints.
- Skip — record assumption "no rate limit" in the Assumptions section.
```

Then the LEAN batched AUQ — options are short selectors; the consequences live in the message above, so `preview` is omitted:

```yaml
questions:
  - header: "Auth method"
    question: "Which auth flow should this endpoint use?"
    options:
      - label: "JWT — existing middleware"
        description: "@UseGuards(JwtAuthGuard); 401 on missing/invalid."
      - label: "Session cookie"
        description: "@UseGuards(SessionGuard); reads session_id cookie."
      - label: "Skip — assume JWT"
        description: "Recorded as an assumption for /geniro:implement to verify."
  - header: "Rate limit"
    question: "Should the endpoint enforce a per-user rate limit?"
    options:
      - label: "Yes — reuse RateLimitGuard"
        description: "60 req/min/user; 429 on exceed."
      - label: "No — unlimited"
        description: "Matches sibling read-only endpoints."
      - label: "Skip — assume no limit"
        description: "Recorded as an assumption."
```

These two questions are independent — auth method does not change the rate-limit options — so they ship in one call. A dependent pair (e.g., "Which datastore?" → then "Which migration tool?" whose options depend on the datastore pick) fires sequentially instead. When every option is self-explanatory in one line, skip the message and fire the AUQ directly. The ≤5-total cap holds across calls; chain a second call if more than 4 independent questions exist rather than dropping or merging any.

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

## 3. Phase 4 approach AUQ — message-first (diagrams in chat, lean AUQ)

Apply the Gate presentation contract. Render the approaches to a chat message (full ASCII diagrams + code identifiers + trade-offs + stress-test verdicts), then fire ONE lean AUQ whose options are just the approach names.

Chat message rendered before the AUQ:

```markdown
Two approaches for the backfill — I recommend the first.

### Service-layer fan-out  ✅ Recommended
Split per-user backfill into queued jobs; the orchestrator dequeues N at a time.

  ┌─────────────┐    ┌──────────────────┐    ┌────────────┐
  │ /backfill    │─→─│ BackfillQueue.add │─→─│ Worker pool│
  └─────────────┘    └──────────────────┘    └────────────┘

New: `src/jobs/BackfillQueue.ts` + a per-user job class.
Trade-off: +1 infrastructure piece; bounded memory under load.
Stress-test: no blockers; queue-table migration needed (minor, src/db/schema.ts:40).

### In-process Promise.all
Loop users, await `Promise.all` in chunks of 50.

  for (chunk of chunks(users, 50)) await Promise.all(chunk.map(backfill))

New: tweaks to `src/backfill/runner.ts` only.
Trade-off: zero new infrastructure; memory spike on large datasets.
Stress-test: major — runner.ts:88 already holds the full user set in memory; the spike compounds.
```

Then the LEAN AUQ — single-select; `Recommended` first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` (§Recommended-label policy); `preview` omitted:

```yaml
header: "Approach"
question: "Which approach do you want to pursue? (Details in the message above.)"
options:
  - label: "Service-layer fan-out (Recommended)"
    description: "Queued jobs; bounded memory; minor migration. No blockers."
  - label: "In-process Promise.all"
    description: "Zero new infra; memory spike on large datasets (major risk)."
```

The `Recommended` marker reflects the §4.2 stress-test ranking — an approach with a blocking feasibility risk is never Recommended. User pick → append to `approvals[]` with category `approach_choice`. Other approaches captured to body section `## Considered Alternatives`. The unsignaled (non-recommended) picks fire L2 emit via `emit-rejection.sh` when the picked label diverges from the recommended label.

---

## 4. Phase 5 cluster AUQ — batched cluster approval + milestone-mode

### 4.1 Cluster authoring procedure — message-first, one decision per cluster

Group the 11-section schema into 3 dependency-ordered clusters. Author and gate cluster-by-cluster; each cluster renders to a chat message, then fires ONE lean AUQ:

| Cluster | Plain-English name | Sections | AUQ `header` (≤12 chars) |
|---|---|---|---|
| 1 | Goal & scope | 1 Objective, 2 Scope-Included, 3 Scope-Excluded | "Goal & scope" |
| 2 | Approach & steps | 4 Assumptions, 5 Risks, 6 Steps, 7 Tools Required | "Approach" |
| 3 | Safety & done | 8 Approval Points, 9 Validation, 10 Rollback-Recovery, 11 Done Condition | "Safety" |

Procedure per cluster (Gate presentation contract):

1. **Author the cluster's sections inline** using Phase 1 research findings + Phase 3 clarifying answers + Phase 4 picked approach + (when present) Phase 2 UI Preview as substrate.

2. **Render the cluster to a chat message** — one sub-heading per section; under each, the Decision → Why → How digest + concrete example + an ASCII diagram where it helps (especially section 6 Steps). A "none — task scope precludes" section is a one-line note here, not a rendered section.

3. **Fire ONE lean AUQ for the cluster** — three options, no `preview` (the message above carries the content): Approve all / Revise specific sections / Cancel planning.

4. **Persist each section pick** to `approvals[]` with category `section_<id>` (e.g., `section_objective`, `section_scope_included`). On "Approve all", append one entry per section (`picked: approve`); on "Revise", record revised sections distinctly (`picked: revised: <summary>`). The cluster is a presentation grouping only — no `cluster_<id>` category.

5. **On approve, author the next cluster** (step 1). After all 3 clusters approved → Phase 6.

**Revise path.** "Revise specific sections" opens a follow-up multi-select picker of the cluster's section names (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` multi-select schema). For each picked section, capture the revision (free-text via Other), re-author it AND any same-cluster sections that depend on it, re-render the cluster message, re-fire this AUQ. Max 3 revision rounds per cluster.

Literal cluster-1 chat message (rendered before the AUQ):

```markdown
## Goal & scope — 3 sections

### 1. Objective
**Decision:** Add a `/backfill` endpoint that re-derives per-user telemetry counts on demand.
**Why:** src/telemetry/aggregate.ts:120 shows counts drift after retroactive event edits;
chosen approach = service-layer fan-out.
**How:** /geniro:implement adds `BackfillController.run()` calling the queued `BackfillQueue`
service; no schema change to events.
Example: "User triggers /backfill → counts reconcile within 30s."

### 2. Scope — Included
**Decision:** BackfillController + BackfillQueue service + per-user job class.
**Why:** integration surface from Phase 1 — src/jobs/ already hosts a queue runner
(src/jobs/runner.ts:40); reuse it.
**How:** /geniro:implement touches src/telemetry/, src/jobs/, src/api/routes.ts.
Example: bullets map to src/jobs/BackfillQueue.ts (new), routes.ts (edit).

### 3. Scope — Excluded
**Decision:** Event-schema migration and the admin dashboard are out of scope.
**Why:** the chosen approach reuses the existing schema; the dashboard is a separate
Linear epic (no file in the touched surface).
**How:** /geniro:implement will NOT touch src/db/schema.ts or src/admin/.
Example: "Backfill runs against the current events table as-is."
```

Then the LEAN AUQ:

```yaml
header: "Goal & scope"
question: "Approve the Goal & scope cluster (3 sections above)?"
options:
  - label: "Approve all (3 sections)"
    description: "Objective + In scope + Out of scope as rendered."
  - label: "Revise specific sections"
    description: "Pick which of the 3 to change; I'll re-author and re-ask."
  - label: "Cancel planning"
    description: "Abort; spec not written."
```

**Tier-scaling.** Sections 4 / 5 / 10 may be "none — task scope precludes" for Trivial/Small tasks — note these in the cluster message rather than as a rendered section. At Trivial tier the clusters may collapse to 1-2 gates; the default 3-cluster grouping applies to Medium/Big.

The chat message is the load-bearing surface — it re-explains what was decided, why, and how /geniro:implement will build it, with room for the code and diagrams the `preview` side-box cannot fit. The AUQ stays lean.

### 4.2 Milestone-mode AUQ (Big tasks only)

Fires BEFORE Phase 6 entry when the canonical milestone-output condition in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` is met (the Big-tier milestone threshold):

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

Handoff (Phase 9) offers `/geniro:implement .geniro/planning/<slug>/milestone-1.md` for sliced specs. The milestone-mode AUQ fires only at Big tier; not Small/Medium/Trivial.

---

## 5. Phase 8 approval — message-first (summary in chat, lean AUQ)

Apply the Gate presentation contract. Render the full plan summary to a chat message (with the concrete examples already authored per section), then fire a lean AUQ.

Chat message rendered before the AUQ:

```markdown
The spec is ready at `.geniro/planning/<slug>/spec.md`. Summary before you approve:

**Objective:** <section 1 body — single sentence>
**Scope:** <section 2 Included bullets + section 3 Excluded summary>
**Approval Points:** <section 8 list, max 5 shown with "... and N more" if >5>
**Risk class:** <auto-computed: low / medium / high from section 5 Risks count + section 7 forbidden_actions>
**Rollback:** <section 10 summary, 1-2 sentences>
**Done Condition:** <section 11 observable signal>
**Touched files:** <glob count from section 2 Scope.Included>

Example (Done Condition): "all 5 acceptance tests green AND telemetry shows ≥1 successful event insert."

Approval is valid for this planning session; re-approval is needed if spec.md is edited after this point.
```

Then the LEAN AUQ — `question` is a one-line recap pointing at the message:

```yaml
header: "Approve spec"
question: "Approve the spec summarized above? (Full text: .geniro/planning/<slug>/spec.md)"
options:
  - label: "Approve — proceed to handoff"   # Recommended
    description: "The handoff step runs next."
  - label: "Request changes — I'll describe"
    description: "Fires a sub-AUQ for revision text; revisions re-run affected sections (max 3 rounds)."
  - label: "Abort — discard spec"
    description: "Terminal aborted; spec.md remains on disk but not committed."
```

On Approve pick: spec.md `lifecycle: draft` → `approved` flip; `git commit` fires (NOT in Phase 6); `non-resumable-actions[]` updated with the commit SHA; transition to Phase 9.

On Revision pick: max 3 user-revision rounds (Phase 8 → re-enter affected sections in Phase 5 → re-validate in Phase 7 → re-fire Phase 8 AUQ). On round 3 exhaust, escalation AUQ "Revision limit reached" fires with options "Accept as-is" / "Re-revise (kick fresh cycle)" / "Abort".
