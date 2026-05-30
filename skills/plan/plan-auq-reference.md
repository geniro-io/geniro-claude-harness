# Plan — AUQ Templates & State Schema Reference

Detail sections extracted from `skills/plan/plan-loop.md` to keep the main loop file lean. The orchestrator reads this file when plan-loop references one of the sections below by name.

## Contents

1. state.md frontmatter — initial template (Phase 0.3)
2. Phase 3 clarifying AUQ — shape with `preview` fields
3. Phase 4 approach AUQ — shape with ASCII-sketch previews
4. Phase 5 per-section AUQ — incremental authoring details + milestone-mode
5. Phase 8 approval AUQ — schema-rich question body

---

## 1. state.md frontmatter — initial template

Written at Phase 0.3 via `atomic_state_write` to `.geniro/planning/<task-slug>/state.md`:

```yaml
---
tier: T1
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

After all 10 sections approved in Phase 5, `## Workflow Refs` (populated by Phase 1.4) and `## UI Preview` (populated by Phase 2 when triggered) appear as additional body sections. The frontmatter `phase:` field transitions through the state machine (`mode-detect` → `explore` → `visual-companion` / `clarify` → `approaches` → `section-approve` → `write-spec` → `validate` → `user-approve` → `handoff` → `done`).

---

## 2. Phase 3 clarifying AUQ — shape with `preview` fields

Each Phase 3 question is fired one-at-a-time via `AskUserQuestion`. Every option carries a **`preview` field** with concrete consequence content (code anchor / config diff / behavior trace, ≤6 lines per preview):

```yaml
header: "Auth method"
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
      Surfaced in spec.md section 4 Assumptions for /implement to verify.
```

Every `preview` field carries concrete consequence content — empty `Approve / Revise / Skip` options waste user attention.

Each answered AUQ → append entry to state.md frontmatter `approvals[]` via `atomic_state_write` BEFORE proceeding to the next question:

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

Single-select; `Recommended` first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`. The `Recommended` marker reflects the Phase 4 §4.2 stress-test ranking — an approach with a blocking feasibility risk is never Recommended. Each option's `preview` contains an ASCII data-flow / architecture sketch (5-10 lines) + key code identifier + one-line dominant tradeoff + the `Stress-test:` verdict line from §4.2:

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

## 4. Phase 5 per-section AUQ — incremental authoring + milestone-mode

### 4.1 Per-section authoring procedure

One AUQ per section, sequentially. Do NOT pre-fill all 10 sections in a batch — pre-fill makes per-section approval redundant (the user has already read the content). Section N+1 is authored only after section N approval.

1. **Author section N inline** (in orchestrator working memory) using Phase 1 research findings + Phase 3 clarifying answers + Phase 4 picked approach + (when present) Phase 2 UI Preview as substrate. Do NOT render the section to chat at this step — the AUQ `preview` field IS the rendering surface.

2. **Fire AUQ** with header `"Section: <name>"`. Chat-side companion is one short line: `"Section: <name> — focus an option to inspect"`. The AUQ options carry concrete content in their `preview` field:

   - **Approve (Recommended)** — `preview`: the section content + ONE concrete example (per section type, see `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-reference.md` §"Concrete-example per section type").
   - **Revise — I'll describe** — `preview`: the section content + a placeholder line `"Type your revision text in Other"`. User types text → model re-authors → re-fires the AUQ (max 3 revisions per section).
   - **Skip — accept as-is with warning** — `preview`: brief consequence statement, e.g., `"Section 9 Validation skipped — /implement Phase 3 reviewer-agent cannot verify section-9 acceptance criteria; manual checks required."`

3. **Persist** each pick to `approvals[]` with category `section_<id>` (e.g., `section_objective`, `section_scope_included`).

4. **Transition to section N+1** authoring (step 1). After all 10 sections approved → Phase 6.

The `preview` field replaces the prior "render section to chat then ask for approval" pattern — the chat output was redundant with the section content the user was about to approve. Empty AUQ options (`Approve / Revise / Skip` text only) degrade trust ("the skill is just clicking through"); concrete preview content makes the AUQ load-bearing.

### 4.2 Milestone-mode AUQ (Big tasks only)

Fires BEFORE Phase 6 entry when effort tier is Big AND section 6 "Steps" has ≥10 discrete steps OR estimated wall-time ≥1 day:

```yaml
header: "Milestone slicing"
question: "This task is large enough to slice into milestones. Slice it now or keep as a single spec?"
options:
  - label: "Slice into milestones"            # Recommended for Big
    description: "Model proposes 3-7 milestone names; user approves; the spec write step emits sibling milestone-N.md files alongside spec.md."
  - label: "Keep as a single spec"
    description: "The spec write step emits only spec.md; /implement consumes the whole thing."
```

If "Slice into milestones" picked:

1. Fire a follow-up AUQ with the proposed milestone names (single-select for "approve all" or multi-select pick per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`).
2. After approval, Phase 6 writes the top-level spec.md (with section 6 "Steps" listing milestones and a new body section `## Milestones` indexing the sibling files) PLUS each `milestone-N.md` with its own 10-section schema scoped to the milestone.
3. Persist to `approvals[]` with category `milestone_slice`.

Hand-off (Phase 9) offers `/implement milestone 1` for sliced specs. Milestone-mode fires only when the task warrants it — for Medium/Trivial, the milestone-mode AUQ does not fire.

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

On Revision pick: max 3 user-revision rounds (Phase 8 → re-enter affected sections in Phase 5 → re-validate in Phase 7 → re-fire Phase 8 AUQ). On round 3 exhaust, escalation AUQ "Phase 8 exhausted" fires with options "Accept as-is" / "Re-revise (kick fresh cycle)" / "Abort".
