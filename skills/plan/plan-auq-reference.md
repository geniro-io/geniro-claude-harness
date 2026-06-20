# Plan — AUQ Templates & State Schema Reference

Detail sections extracted from `skills/plan/plan-loop.md` to keep the main loop file lean. The orchestrator reads this file when plan-loop references one of the sections below by name.

## Contents

1. state.md frontmatter — initial template (Phase 0.3)
2. Phase 3 grill AUQ — message-first, one question at a time
3. Phase 4 approach AUQ — message-first (diagrams in chat, lean AUQ)
4. Phase 5 cluster AUQ — message-first cluster approval (3 dependency-ordered gates) + milestone-mode
5. Phase 8 approval — message-first (summary in chat, lean AUQ)
5b. Phase 8 launch-config AUQ — pre-define implement settings (opt-in)

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
deep-mode: <true|false>                      # optional, set by the --deep flag (Phase 0.1); missing reads as false
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

Three optional body sections — `## Workflow Refs` (populated in Phase 1.4), `## UI Preview` (populated in Phase 2 when triggered), and `## Problem Framing` (populated in Phase 0.5 when `--prd` was passed) — are written in those earlier phases and assembled into the spec body alongside the 11 sections approved in Phase 5. The frontmatter `phase:` field transitions through the state machine (`mode-detect` → `problem-discovery` (only when `prd_mode: true`) → `explore` → `visual-companion` / `clarify` → `approaches` → `section-approve` → `write-spec` → `validate` → `spec-challenge` → `user-approve` → `handoff` → `done`). The optional `prd_mode: true` frontmatter key is set in Phase 0.1 when `$ARGUMENTS` carries `--prd`; absent otherwise. The optional `deep-mode` key is set in Phase 0.1 when `$ARGUMENTS` carries `--deep`; a missing value reads as `false`. This is the single-source-of-truth template — `${CLAUDE_PLUGIN_ROOT}/skills/plan/SKILL.md` and `plan-loop.md` §0.3 mirror it and must carry the same field set.

---

## 2. Phase 3 grill AUQ — message-first, one question at a time

Apply the Gate presentation contract (`${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §"Gate presentation contract"). Phase 3 is a decision-tree grill — walk the design's open decisions depth-first (plan-loop §3.1). Ask the grill questions **one at a time** — one `AskUserQuestion` call per question, never a multi-question batch. Before each question, render its framing to a chat message FIRST, then fire a LEAN single-question AUQ. Size the framing to the question: a one-line orientation when every option is self-explanatory, a full per-option consequence breakdown (code anchor / config diff / behavior trace) when an option's consequence needs more than its one-line `description`. Give a recommended answer for every question (Recommended-first option).

One question at a time (over batching) because each answer reshapes the tree frontier — a still-pending child can become moot or need reworded options. Do NOT pre-generate a fixed question list; regenerate the next question from the live tree after each answer. The cost is more round-trips than a batch; that is the deliberate trade for per-question clarity and a frontier that adapts to each answer.

Chat message rendered before the FIRST question:

```markdown
First decision before I lock the approach:

**Auth method** — how should the new endpoint authenticate?
- JWT (existing middleware) — adds `@UseGuards(JwtAuthGuard)`; reads the token from the
  Authorization header; 401 on missing/invalid. Test: `expect(401)...code: 'UNAUTHENTICATED'`.
- Session cookie — adds `@UseGuards(SessionGuard)`; reads the `session_id` cookie;
  mirrors `/auth/session.spec.ts`; same 401 shape.
- Skip — record assumption "endpoint uses JWT (default)" in the Assumptions section for /geniro:implement to verify.
```

Then the LEAN single-question AUQ — options are short selectors; the consequences live in the message above, so `preview` is omitted:

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
```

After the user answers, persist it (below), then render the next question's framing and fire its own single-question AUQ — e.g. the rate-limit decision:

```yaml
questions:
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

There is no fixed question cap — the grill runs until the spec-shaping branches resolve, bounded by the §2b checkpoint gate. If an earlier answer makes a pending question moot (e.g., "Skip auth entirely" removes a follow-up auth-scope question), drop it rather than asking it — depth-first walking exists precisely to let one answer reshape what follows.

Each answered question → append entry to state.md frontmatter `approvals[]` via `atomic_state_write`. Append the entry for each answer before rendering the next question:

```yaml
approvals:
  - category: clarify_<dim>          # e.g., clarify_auth_method
    prompt: "Which existing auth flow should the new feature integrate with?"
    options: ["OAuth (src/auth/oauth.ts)", "JWT (src/auth/jwt.ts)", "Skip — proceed assuming OAuth"]
    picked: "OAuth (src/auth/oauth.ts)"
    at: 2026-05-17T10:50:00Z
    asked_in_phase: clarify
```

### 2a. Planning-depth question (asked once at grill wrap-up when `--deep` is absent)

When `$ARGUMENTS` does not carry `--deep`, ask a planning-depth question once at grill wrap-up (§2b termination) — its own single-question AUQ, after the substance is settled. It never depends on a clarifying answer, so it goes last by convention (a mode question). This depth question is exempt from the §2b checkpoint cadence — it is a mode question, not a clarification, and never triggers a wrap-up. When `--deep` is present, depth is already Deep — skip this question. No `(Recommended)` marker: Deep is costlier, not safer.

```yaml
- header: "Plan depth"
  question: "How deep should the planning go?"
  options:
    - label: "Standard"
      description: "Single-pass approach search and one verifier per cited claim."
    - label: "Deep — wider search + 3-vote verify"
      description: "A judge-panel approach search plus 3x verification of the spec's cited claims with majority vote; higher quality at higher token cost."
```

Empty answer → default Standard (`deep-mode: false`). Phase 3 is skipped on Trivial tasks, so depth there stays flag-only.

Persist the pick to state.md frontmatter `deep-mode: <true|false>` and append an `approvals[]` entry with category `deep_mode_choice`:

```yaml
approvals:
  - category: deep_mode_choice
    prompt: "How deep should the planning go?"
    options: ["Standard", "Deep — wider search + 3-vote verify"]
    picked: "Standard"
    at: 2026-05-17T10:50:00Z
    asked_in_phase: clarify
```

### 2b. Checkpoint gate and termination summary

No fixed cap bounds the grill (§2 above) — instead pause for a checkpoint whichever comes first: a full design branch resolves, OR ~6 questions have been asked since the last checkpoint (plan-loop §3.4). At a checkpoint, render a running summary to a chat message FIRST, then fire ONE lean AUQ.

Chat message rendered before the checkpoint AUQ:

```markdown
Quick checkpoint — 6 decisions in, here's where we are:

**Resolved**
- Auth: JWT via existing middleware
- Rate limit: 60 req/min/user (reuse RateLimitGuard)
- Storage: append to the existing events table (no new table)

**Deferred / assumed**
- Backfill ordering — assuming newest-first unless you say otherwise

**Still open to walk**
- Failure handling (retries / dead-letter)
- Admin visibility (in scope at all?)
```

Then the LEAN AUQ — `preview` omitted (the summary is the message above):

```yaml
header: "Checkpoint"
question: "Keep grilling the open branches, or wrap up here?"
options:
  - label: "Keep grilling"                         # Recommended while open branches remain
    description: "Continue the walk through failure handling + admin visibility."
  - label: "Wrap up now"
    description: "Stop; the open branches become stated assumptions in the spec."
  - label: "Skip remaining with stated assumptions"
    description: "Same as wrap-up, but I name the skipped branches in Assumptions for /geniro:implement to verify."
```

Persist each checkpoint decision to `approvals[]` category `grill_checkpoint`:

```yaml
approvals:
  - category: grill_checkpoint
    prompt: "Keep grilling the open branches, or wrap up here?"
    options: ["Keep grilling", "Wrap up now", "Skip remaining with stated assumptions"]
    picked: "Keep grilling"
    at: 2026-05-17T11:05:00Z
    asked_in_phase: clarify
```

**Termination** fires when all branches resolve, the user picks Wrap up / Skip, or no spec-shaping question remains. Render a closing summary (resolved decisions / deferred work / unaddressed risks) and hold it in context — it feeds Phase 4 approach generation and seeds Phase 5 sections (Steps / Validation / Done Condition). Then ask the §2a planning-depth question when `--deep` is absent, and transition to Phase 4.

---

## 3. Phase 4 approach AUQ — message-first (diagrams in chat, lean AUQ)

Apply the Gate presentation contract (§Visual rendering language). Render the approaches to a chat message — progress tracker, one-sentence opener, then per approach a plain-English summary + ASCII diagram + what-changes + trade-off + stress-test verdict — and fire ONE lean AUQ whose options are just the approach names.

Chat message rendered before the AUQ:

```markdown
Plan approval — choosing the approach
● Approach · ○ Goal & scope · ○ Steps · ○ Safety · ○ Final approval

**In one sentence:** picking how to rebuild drifted telemetry counts — two ways to build it; I recommend the first.

### Service-layer fan-out  ✅ Recommended
Split the per-user backfill into queued jobs; a worker pool takes N at a time, so memory stays flat no matter how many users.

  ┌─────────────┐    ┌──────────────────┐    ┌────────────┐
  │ /backfill    │─→─│ BackfillQueue.add │─→─│ Worker pool│
  └─────────────┘    └──────────────────┘    └────────────┘

What changes: new `src/jobs/BackfillQueue.ts` + a per-user job class.
Trade-off: +1 infrastructure piece; bounded memory under load.
Stress-test: no blockers; queue-table migration needed (minor, src/db/schema.ts:40).

### In-process Promise.all
Loop the users and run 50 backfills at a time inside the existing process — nothing new to deploy.

  for (chunk of chunks(users, 50)) await Promise.all(chunk.map(backfill))

What changes: tweaks to `src/backfill/runner.ts` only.
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

The `Recommended` marker reflects the §4.2 stress-test ranking — an approach with a verified blocking feasibility risk is never Recommended. User pick → append to `approvals[]` with category `approach_choice`. Other approaches captured to body section `## Considered Alternatives`. The unsignaled (non-recommended) picks fire L2 emit via `emit-rejection.sh` when the picked label diverges from the recommended label.

---

## 4. Phase 5 cluster AUQ — message-first cluster approval (3 dependency-ordered gates) + milestone-mode

### 4.1 Cluster authoring procedure — message-first, one decision per cluster

Group the 11-section schema into 3 dependency-ordered clusters. Author and gate cluster-by-cluster; each cluster renders to a chat message, then fires ONE lean AUQ:

| Cluster | Plain-English name | Sections | AUQ `header` (≤12 chars) |
|---|---|---|---|
| 1 | Goal & scope | 1 Objective, 2 Scope-Included, 3 Scope-Excluded | "Goal & scope" |
| 2 | Approach & steps | 4 Assumptions, 5 Risks, 6 Steps, 7 Tools Required | "Approach" |
| 3 | Safety & done | 8 Approval Points, 9 Validation, 10 Rollback-Recovery, 11 Done Condition | "Safety" |

Procedure per cluster (Gate presentation contract):

1. **Author the cluster's sections inline** using Phase 1 research findings + Phase 3 clarifying answers + Phase 4 picked approach + (when present) Phase 2 UI Preview as substrate.

2. **Render the cluster to a chat message in the Visual rendering language** (Gate presentation contract) — progress tracker (`step N of 3`), one-sentence opener, the cluster-level visual (cluster 1: in/out scope map; cluster 2: steps flow diagram; cluster 3: done-condition checklist), then one icon-headed sub-heading per section with its friendly digest block (lead sentence / `**Why:**` with evidence cite / `**How it gets built:**` / `**You'll see:**`) closed by the concrete example + visual per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-reference.md` §"Concrete example + visual per section type". A "none — task scope precludes" section is a one-line note here, not a rendered section.

3. **Fire ONE lean AUQ for the cluster** — four options, no `preview` (the message above carries the content): Approve all / Explain a section further / Revise specific sections / Cancel planning.

4. **Persist each section pick** to `approvals[]` with category `section_<id>` (e.g., `section_objective`, `section_scope_included`). On "Approve all", append one entry per section (`picked: approve`); on "Revise", record revised sections distinctly (`picked: revised: <summary>`); "Explain a section further" persists nothing. The cluster is a presentation grouping only — no `cluster_<id>` category.

5. **On approve, author the next cluster** (step 1). After all 3 clusters approved → Phase 6.

**Explain path.** "Explain a section further" opens the same section picker as Revise. For each picked section, render a deeper walkthrough message — the full evidence chain (additional `file:line` cites), an expanded or alternative diagram, edge-case behavior, and exactly what /geniro:implement will and will not touch — then re-fire the cluster AUQ. A reading aid, not a decision: it writes no `approvals[]` entry, never changes section content, and does not count toward the 3 revision rounds.

**Revise path.** "Revise specific sections" opens a follow-up multi-select picker of the cluster's section names (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` multi-select schema). For each picked section, capture the revision (free-text via Other), re-author it AND any same-cluster sections that depend on it, re-render the cluster message, re-fire this AUQ. Max 3 revision rounds per cluster.

Literal cluster-1 chat message (rendered before the AUQ):

```markdown
Plan approval — step 1 of 3
✔ Approach · ● Goal & scope · ○ Steps · ○ Safety · ○ Final approval

**In one sentence:** we're agreeing on what the backfill feature will do, what's
included, and what stays out.

┌─ In scope ──────────────────────┐   ┌─ Out of scope ──────────────┐
│ + src/jobs/BackfillQueue.ts     │   │ x event-schema migration    │
│ + per-user job class            │   │ x admin dashboard           │
│ ~ src/api/routes.ts             │   └─────────────────────────────┘
│ ~ src/telemetry/                │       + new file   ~ edited file
└─────────────────────────────────┘

### 🎯 Objective
We'll add a `/backfill` endpoint that re-derives per-user telemetry counts on demand.
- **Why:** counts drift after retroactive event edits (evidence:
  src/telemetry/aggregate.ts:120); the approach you picked is service-layer fan-out.
- **How it gets built:** a `BackfillController.run()` calling the queued
  `BackfillQueue` service; no change to the events schema.
- **You'll see:** trigger `/backfill` → counts reconcile within ~30s.

### 📦 What's included
We'll build the controller, the queue service, and a per-user job class.
- **Why:** src/jobs/ already hosts a queue runner (src/jobs/runner.ts:40) — we
  reuse it instead of adding new infrastructure.
- **You'll see:** the scope map above — 2 new files, 2 edited areas.

### 🚫 What's excluded
The event-schema migration and the admin dashboard stay out.
- **Why:** the chosen approach reuses the existing schema; the dashboard is a
  separate tracker epic (no file in the touched surface).
- **You'll see:** src/db/schema.ts and src/admin/ untouched after implementation.
```

Then the LEAN AUQ:

```yaml
header: "Goal & scope"
question: "Approve the Goal & scope step (3 sections above)?"
options:
  - label: "Approve all (3 sections)"
    description: "Objective + In scope + Out of scope as rendered."
  - label: "Explain a section further"
    description: "Pick a section; I'll walk through it in more depth, then re-ask."
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

Handoff (Phase 9) prints `/geniro:implement .geniro/planning/<slug>/milestone-1.md` for sliced specs. The milestone-mode AUQ fires only at Big tier; not Small/Medium/Trivial.

---

## 5. Phase 8 approval — message-first (summary in chat, lean AUQ)

Apply the Gate presentation contract (§Visual rendering language). Render the full plan summary to a chat message (with the concrete examples already authored per section), then fire a lean AUQ.

Chat message rendered before the AUQ:

```markdown
Plan approval — final step
✔ Approach · ✔ Goal & scope · ✔ Steps · ✔ Safety · ● Final approval

**In one sentence:** the full spec is written and checked — this is the last look
before it's committed and handed to implementation.

Spec on disk: `.geniro/planning/<slug>/spec.md`

**🎯 The goal:** <section 1 body — single sentence>
**📦 In / out:** <section 2 Included bullets + section 3 Excluded summary — reuse
the in/out scope map from the Goal & scope step>
**🙋 Where you'll be asked mid-build:** <section 8 list, max 5 shown with
"... and N more" if >5>
**⚠️ Risk level:** <auto-computed: low / medium / high from section 5 Risks count
+ section 7 forbidden_actions> — <one-line why>
**↩️ If something goes wrong:** <section 10 summary, 1-2 sentences>
**✅ How we'll know it's done:**
☐ <section 11 — one checkbox per observable signal, e.g. "all 5 acceptance tests green">
☐ <"telemetry shows ≥1 successful event insert">
**Touched files:** <glob count from section 2 Scope.Included>

Approval is valid for this planning session; re-approval is needed if spec.md is
edited after this point.
```

Then the LEAN AUQ — `question` is a one-line recap pointing at the message:

```yaml
header: "Approve spec"
question: "Approve the spec summarized above? (Full text: .geniro/planning/<slug>/spec.md)"
options:
  - label: "Approve — commit the plan"   # Recommended
    description: "Commits spec.md and prints the /geniro:implement command to build it."
  - label: "Request changes — I'll describe"
    description: "Fires a sub-AUQ for revision text; revisions re-run affected sections (max 3 rounds)."
  - label: "Abort — discard spec"
    description: "Terminal aborted; spec.md remains on disk but not committed."
```

On Approve pick: spec.md `lifecycle: draft` → `approved` flip; `git commit` fires (NOT in Phase 6); `non-resumable-actions[]` updated with the commit SHA; transition to Phase 9.

On Revision pick: max 3 user-revision rounds (Phase 8 → re-enter affected sections in Phase 5 → re-validate in Phase 7 → re-fire Phase 8 AUQ). On round 3 exhaust, escalation AUQ "Revision limit reached" fires with options "Accept as-is" / "Re-revise (kick fresh cycle)" / "Abort".

---

## 5b. Phase 8 launch-config AUQ — pre-define implement settings (opt-in)

Fires at the very end of planning — Phase 8, AFTER the user approves the spec (§5 above) and BEFORE the §8.4 git commit. Skipped entirely when `$ARGUMENTS` modifiers already set these (workspace / depth / branch-handling / ship modifiers). It captures `/geniro:implement`'s launch settings at plan time so `/implement` runs without re-asking. Field semantics, enum values, and the doctrine boundary are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` — this section is the question wording only.

Two steps: a gate question, then (only on "Yes") a batched capture.

### Step 1 — gate question

A lean single-question AUQ. The gate question never auto-defaults — an empty answer is re-asked, not defaulted, because opting in is a real choice (unlike the per-field defaults in Step 2, which presuppose a "Yes"):

```yaml
header: "Implement setup"
question: "Pre-define the implementation settings now, so /implement can run on its own?"
options:
  - label: "Yes — set them now"
    description: "Pick the workspace, depth, branch handling, and ship mode here; /implement skips those questions and runs on its own."
  - label: "No — /implement will ask when it runs"
    description: "Leave the settings unset; /implement asks them interactively at start, exactly as it does today."
```

On "No" → write no `launch_config:` block; persist the declined gate answer to `approvals[]` (Step 3) and proceed to §8.4 with the spec unchanged. On "Yes" → fire Step 2.

### Step 2 — batched capture (only on "Yes")

ONE batched AUQ (up to 4 questions). Each field carries a recommended default; an empty answer on a field falls back to that field's recommended value (the user already opted in by picking "Yes"), so no field can block. Recommended defaults: `new-branch`, Standard (`deep_mode: false`), `rebase`, `draft-pr`.

```yaml
questions:
  - header: "Workspace"
    question: "Where should /implement do the work?"
    options:
      - label: "New branch"                  # Recommended → workspace: new-branch
        description: "Cut a fresh branch from the latest default branch."
      - label: "Current branch"
        description: "Work in place on the current branch."
      - label: "Worktree"
        description: "Cut a separate worktree so the current checkout is untouched."
      - label: "Here"
        description: "Work in the current directory as-is, no branch change."
  - header: "Depth"
    question: "How deep should the implementation review go?"
    options:
      - label: "Standard"                     # Recommended → deep_mode: false
        description: "Single self-review pass; standard cost."
      - label: "Deep"
        description: "Multi-angle self-review plus a pre-edit fact-check; higher quality, higher cost."
  - header: "Branch handling"
    question: "If the branch is behind the default branch, how should /implement catch it up?"
    options:
      - label: "Rebase"                       # Recommended → branch_freshness: rebase
        description: "Replay your commits on top of the latest default branch."
      - label: "Merge"
        description: "Merge the latest default branch into yours."
      - label: "Skip"
        description: "Leave the branch as-is; don't update it before working."
  - header: "Ship mode"
    question: "How should /implement finish — what should it do at ship time?"
    options:
      - label: "Draft PR"                     # Recommended → ship_mode: draft-pr
        description: "Push and open a draft pull request."
      - label: "PR ready for review"
        description: "Push and open a pull request marked ready for review."
      - label: "Commit only, don't push"
        description: "Commit locally; don't push or open a PR."
      - label: "Stop after review"
        description: "Stop before any commit or push."
```

Map the picks to the `launch_config:` block values (`workspace` / `deep_mode` / `branch_freshness` / `ship_mode`) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"The block". Hold the block for the §8.4 spec rewrite.

### Step 3 — persistence

Append one entry to state.md `approvals[]` with category `launch_config` via `atomic_state_write` — mirror the `deep_mode_choice` shape (§2a above), recording the gate answer and, on "Yes", the captured fields:

```yaml
approvals:
  - category: launch_config
    prompt: "Pre-define the implementation settings now, so /implement can run on its own?"
    options: ["Yes — set them now", "No — /implement will ask when it runs"]
    picked: "Yes — set them now"
    launch_config:
      workspace: new-branch
      deep_mode: false
      branch_freshness: rebase
      ship_mode: draft-pr
    at: 2026-05-17T11:20:00Z
    asked_in_phase: user-approve
```

On "No", omit the `launch_config:` sub-block and record `picked: "No — /implement will ask when it runs"`.

Doctrine: these four fields pre-answer SETUP only. They do NOT pre-authorize the new-dependency adoption gate, the runaway-scope / budget escalation, the handoff open-questions gate, or the spec-challenge-on-drift gate — each of those still fires on its own real trigger during `/geniro:implement` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"Doctrine boundary — setup only, never safety").
