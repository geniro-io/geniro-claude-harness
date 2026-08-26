<!-- Generated from skills/plan/plan-auq-reference.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Plan — AUQ templates and state-schema reference

Literal `AskQuestion` templates and state-schema blocks for the `/geniro:plan` loop. A phase file states its gate's rules and cites the section here that holds the literal template; read the named section when you reach that gate.

## Contents

1. state.md body template (Phase 0.3) + the `approvals[]` entry shape every gate below writes
1b. Artifact opt-in question — Phase 0, asked once when `--artifact` is absent
2. Phase 3 grill AUQ — message-first, one question at a time
3. Phase 4 approach AUQ — message-first (diagrams in chat, lean AUQ)
4. Phase 5 cluster AUQ — message-first cluster approval (3 dependency-ordered gates) + milestone-mode
5. Phase 8 approval — message-first (summary in chat, lean AUQ)
5b. Phase 8 launch-config AUQ — pre-define implement settings (opt-in)

---

## 1. state.md body template

The frontmatter field set is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/SKILL.md` §"State persistence" — read the schema there rather than re-deriving it; a second copy here is what lets the two drift. Phase 0.3 writes it via `atomic_state_write` to `.geniro/planning/<task-slug>/state.md`, over this body:

```markdown
# State: <topic>

## Inputs
- $ARGUMENTS: "<raw>"
- mode: <IDEA|DESIGN_DOC>
- design-doc-path (if DESIGN_DOC): <abs-path>

## Tool log

## Errors

## Open Questions
```

Three further body sections are optional, each written by the phase that populates it and assembled into the spec body alongside the standard schema's sections approved in Phase 5 (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`): `## Workflow Refs` (Phase 1.4), `## UI Preview` (Phase 2, when triggered — assemble per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel: both the approved-text form and the routed-out sentinel assemble into the spec verbatim, since a dropped sentinel reads identically to Phase 2 never having triggered at all — indistinguishable to every downstream reader of spec.md; drop the section only when the heading is absent or present-but-bare, meaning the producing step did not run), `## Considered Alternatives` (Phase 4.4).

### `approvals[]` entry shape — every gate below writes this

Each answered gate appends one entry to state.md frontmatter `approvals[]` via `atomic_state_write`. The shape is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §"T1.5 optional `approvals` array" — six required fields, `category` / `prompt` (the verbatim question) / `options` (the labels offered) / `picked` / `at` (ISO-8601 UTC) / `asked_in_phase`, plus three optional ones, `why` / `evidence` / `result`:

```yaml
approvals:
  - category: deep_mode_choice
    prompt: "How deep should the planning go?"
    options: ["Standard", "Deep — wider search + 3-vote verify"]
    picked: "Standard"
    at: 2026-05-17T10:50:00Z
    asked_in_phase: clarify
    why: "Two of the three open decisions were already settled by the explore pass, so the extra verification passes had little left to contest."
```

Record `why` on a gate whose answer a later reader could not reconstruct from `picked` alone — a scope call, a tier hold, a pick made against the recommendation. Add `evidence` when the reason rests on something checkable, and `result` once the pick has been acted on. Omit all three where the pick speaks for itself; a `why` that paraphrases `picked` is noise the reader still pays for.

The sections below name only their `category` slug and the phase they are asked in; §5b adds a nested `launch_config:` sub-block, the one gate whose entry carries a field beyond the nine. Write the entry before rendering the next question, so a context reset mid-sequence preserves every answer already given.

---

## 1b. Artifact opt-in question (Phase 0, asked once when `--artifact` is absent)

Fires at the very start of planning (Phase 0) — after the mode resolves, before exploration begins — so the page can be built up from the first phase. When the `--artifact` flag was present in the run's arguments, skip this question: the flag is the opt-in. Mirrors the shape of the §2a planning-depth question — its own single-question AUQ, no `(Recommended)` marker (the page is a richer surface, not a safer plan). This section owns the question text and both option labels — use them verbatim:

```yaml
- header: "Visual plan"
  question: "Build a live visual artifact of this plan as it develops? It publishes a private, auto-updating page to claude.ai."
  options:
    - label: "Yes — build it and keep it updated"
      description: "The page grows with the plan and is revised in place at each phase."
    - label: "No — keep planning in chat only"
      description: "Plan in chat with no page."
```

Empty answer → re-ask, never auto-default, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions. On the "Yes" pick, the run is in artifact mode — set `artifact_mode: true` and `artifact_status: pending` in the §1 frontmatter; on "No", leave all artifact fields absent.

Persist the pick to `approvals[]` (§1 entry shape) with category `artifact_choice`, `asked_in_phase: mode-detect`, so a resume after compaction doesn't re-ask.

The full artifact lifecycle (availability detection, create, per-phase update, URL persistence, unavailable/skip handling) is owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md` — Read it only once the run is in artifact mode, starting from the Phase 1 `loop-artifact-call-sites.md` read; this section owns the opt-in question template and the choice that gets persisted.

---

## 2. Phase 3 grill AUQ — message-first, one question at a time

The grill procedure — message-first framing sized to the question, then a lean single-question AUQ, one question at a time, frontier regenerated after each answer — is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-3-grill.md` §3.2; the two-step shape it applies is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §"Gate presentation contract". This section holds the literal templates.

Chat message rendered before the FIRST question:

```markdown
First decision before I lock the approach:

**Auth method** — how should callers of the new endpoint prove who they are?

- **A token sent with each request.** The caller attaches a token; anyone without a
  valid one is turned away. This is the same check the rest of the API already does,
  so there is nothing new to build or maintain.
  **Technical detail:** `@UseGuards(JwtAuthGuard)`; token read from the Authorization
  header; 401 on missing/invalid, `code: 'UNAUTHENTICATED'`.
- **The browser's login cookie.** The caller is recognised by the session they already
  have from logging in. Same rejection behavior for anyone not logged in, but the API
  then has two ways of proving identity to keep working.
  **Technical detail:** `@UseGuards(SessionGuard)`; reads the `session_id` cookie;
  mirrors `/auth/session.spec.ts`; same 401 shape.
- **Decide later.** I write down "tokens, unless told otherwise" as a stated assumption,
  and the build step confirms it against the code before relying on it.

I recommend the token check — it already exists and is already tested; the cookie route
would add a second way in for the project to keep working.
```

Then the LEAN single-question AUQ — options are short selectors carrying the plain layer only (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions); the identifiers live in the message above, so `preview` is omitted. Per the §3.2 recommended-answer rule, the framing message names the recommendation and the AUQ's first option carries the `(Recommended)` marker:

```yaml
questions:
  - header: "Auth method"
    question: "How should callers of this endpoint prove who they are? (Options explained above.)"
    options:
      - label: "A token per request (Recommended)"
        description: "The check the rest of the API already uses; nothing new to maintain."
      - label: "The browser's login cookie"
        description: "Recognises an already-logged-in user; adds a second way in to maintain."
      - label: "Decide later — assume tokens"
        description: "Recorded as a stated assumption for the build step to confirm."
```

After the user answers, persist it (below), then render the next question's framing and fire its own single-question AUQ. If an earlier answer makes a pending question moot (e.g., "Skip auth entirely" removes a follow-up auth-scope question), drop it rather than asking it — depth-first walking exists precisely to let one answer reshape what follows.

Each answered question → one `approvals[]` entry (§1 entry shape) with category `clarify_<dim>` (e.g. `clarify_auth_method`), `asked_in_phase: clarify`.

### 2a. Planning-depth question (asked once at grill wrap-up when `--deep` is absent)

When `$ARGUMENTS` does not carry `--deep`, ask a planning-depth question once at grill wrap-up (§2b termination) — its own single-question AUQ, after the substance is settled. It never depends on a clarifying answer, so it goes last by convention (a mode question). This depth question is exempt from the §2b checkpoint cadence — it is a mode question, not a clarification, and never triggers a wrap-up. When `--deep` is present, depth is already Deep — skip this question. No `(Recommended)` marker: Deep is costlier, not safer.

```yaml
- header: "Plan depth"
  question: "How deep should the planning go?"
  options:
    - label: "Standard"
      description: "Single-pass approach search and a single verification pass over the spec's cited claims."
    - label: "Deep — wider search + 3-vote verify"
      description: "A judge-panel approach search plus 3x verification of the spec's cited claims with majority vote; higher quality at higher token cost."
```

Empty answer → re-ask, never auto-default, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions. Phase 3 is skipped on Trivial tasks, so depth there stays flag-only.

Persist the pick to state.md frontmatter `deep-mode: <true|false>` and append an `approvals[]` entry (§1 entry shape) with category `deep_mode_choice`, `asked_in_phase: clarify`.

### 2b. Checkpoint gate and termination summary

The checkpoint trigger is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-3-grill.md` §3.4. At a checkpoint, render a running summary to a chat message FIRST, then fire ONE lean AUQ.

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

Persist each checkpoint decision to `approvals[]` (§1 entry shape) with category `grill_checkpoint`, `asked_in_phase: clarify`.

**Termination** rules are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-3-grill.md` §3.4 (closing summary → the §2a planning-depth question when `--deep` is absent → Phase 4).

---

## 3. Phase 4 approach AUQ — message-first (diagrams in chat, lean AUQ)

Apply the Gate presentation contract (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Visual rendering language). Render the approaches to a chat message — progress tracker, one-sentence opener, then per approach a plain-English summary + trade-off, followed by that approach's `**Technical detail:**` block holding the ASCII diagram, what-changes, and the stress-test verdict with its cite (the plain-then-technical split is canonical in that file's §Two explanation layers) — and fire ONE lean AUQ whose options are just the approach names.

Chat message rendered before the AUQ:

```markdown
Plan approval — choosing the approach
● Approach · ○ Goal & scope · ○ Steps · ○ Safety · ○ Final approval

**In one sentence:** picking how to rebuild drifted telemetry counts — two ways to build it; I recommend the first.

### Service-layer fan-out  ✅ Recommended
Line the users up in a queue and rebuild their counts a few at a time, so the
job uses the same amount of memory whether there are 100 users or a million.
Trade-off: one more moving part to run and monitor, in exchange for a backfill
that can't run the server out of memory.

**Technical detail:**

  ┌─────────────┐    ┌──────────────────┐    ┌────────────┐
  │ /backfill    │─→─│ BackfillQueue.add │─→─│ Worker pool│
  └─────────────┘    └──────────────────┘    └────────────┘

  What changes: new `src/jobs/BackfillQueue.ts` + a per-user job class.
  Stress-test: no blockers; queue-table migration needed (minor, src/db/schema.ts:40).

### In-process Promise.all
Rebuild the counts in batches of 50 inside the server that's already running —
nothing new to deploy or operate. Trade-off: on a large customer the whole user
list sits in memory at once, so this is the option that can fall over under size.

**Technical detail:**

  for (chunk of chunks(users, 50)) await Promise.all(chunk.map(backfill))

  What changes: tweaks to `src/backfill/runner.ts` only.
  Stress-test: major — runner.ts:88 already holds the full user set in memory; the spike compounds.
```

Then the LEAN AUQ — single-select; `Recommended` first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` (§Recommended-label policy); `preview` omitted:

```yaml
header: "Approach"
question: "Which approach do you want to pursue? (Details in the message above.)"
options:
  - label: "Service-layer fan-out (Recommended)"
    description: "Rebuilds counts a few at a time; memory stays flat. One new piece to run."
  - label: "In-process Promise.all"
    description: "Nothing new to deploy; can run out of memory on large customers."
```

The `Recommended` marker reflects the §4.2 stress-test ranking — an approach with a verified blocking feasibility risk is never Recommended. User pick → append to `approvals[]` with category `approach_choice`. Other approaches captured to body section `## Considered Alternatives`. The unsignaled (non-recommended) picks fire L2 emit via `emit-rejection.sh` when the picked label diverges from the recommended label.

---

## 4. Phase 5 cluster AUQ — message-first cluster approval (3 dependency-ordered gates) + milestone-mode

### 4.1 Cluster authoring procedure — message-first, one decision per cluster

The cluster set (which sections group into which of the 3 dependency-ordered clusters, each cluster's AUQ `header`) and the per-cluster procedure (author → render → gate → persist → next cluster, plus the Explain and Revise paths) are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-5-section-approval.md` §5.2. Each section's concrete example shape is in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-reference.md` §"Concrete example per section type" and its visual shape in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §"Plan-unit visual map". This section holds the literal templates.

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
Add a way to ask the system to recount a user's telemetry on demand.
- **Why:** the counts drift out of date whenever past events get edited, and
  today there is no way to correct them short of a manual fix.
- **You'll see:** trigger a backfill → that user's counts are correct within ~30s.
- **Technical detail:** a `/backfill` endpoint —`BackfillController.run()`
  calling the queued `BackfillQueue` service, the service-layer fan-out approach
  you picked. Drift evidence: src/telemetry/aggregate.ts:120. No change to the
  events schema.

### 📦 What's included
The endpoint itself, the queue that paces the work, and the per-user recount job.
- **Why:** the project already runs a queue for other background work, so this
  reuses it instead of adding a second one.
- **You'll see:** the scope map above — 2 new files, 2 edited areas.
- **Technical detail:** the existing runner is src/jobs/runner.ts:40; the new
  files land beside it in src/jobs/.

### 🚫 What's excluded
Changing how events are stored, and any admin screen for triggering this.
- **Why:** the approach works with the storage as it is, and the admin screen is
  its own tracked piece of work.
- **You'll see:** nothing in the database schema or the admin area changes.
- **Technical detail:** src/db/schema.ts and src/admin/ untouched after implementation.
```

Then the LEAN AUQ:

```yaml
header: "Goal & scope"
question: "Approve the Goal & scope step (3 sections above)?"
options:
  - label: "Approve all (3 sections) (Recommended)"
    description: "Objective + In scope + Out of scope as rendered."
  - label: "Explain a section further"
    description: "Pick a section; I'll walk through it in more depth, then re-ask."
  - label: "Revise specific sections"
    description: "Pick which of the 3 to change; I'll re-author and re-ask."
  - label: "Cancel planning"
    description: "Abort; spec not written."
```

**Tier-scaling** — which tiers may render a section as "none — task scope precludes", and which may collapse cluster gates — is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-5-section-approval.md` §5.2.

The chat message is the load-bearing surface — it re-explains what was decided, why, and how /geniro:implement will build it, with room for the code and diagrams the `preview` side-box cannot fit. The AUQ stays lean.

### 4.2 Milestone-mode AUQ (Big tasks only)

Fires BEFORE Phase 6 entry when the canonical milestone-output condition in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` is met (the Big-tier milestone threshold):

```yaml
header: "Milestones"
question: "This task is large enough to slice into milestones. Slice it now or keep as a single spec?"
options:
  - label: "Slice into milestones"            # Recommended for Big
    description: "Splits into 3-7 milestone files instead of one spec.md — you approve the names, then build and ship each one as its own /geniro:implement session."
  - label: "Keep as a single spec"
    description: "The spec write step emits only spec.md; /geniro:implement consumes the whole thing."
```

Persist the pick to `approvals[]` with category `milestone_slice` regardless of which option is chosen — the §7.5 milestone re-open guard reads this entry's presence, not its value, to tell an already-settled "Keep as a single spec" from a question never asked; skipping the write on that branch reopens the exact re-ask this gate exists to prevent.

If "Slice into milestones" picked:

Propose the milestones as vertical slices: each cuts a narrow but complete path through every affected layer (schema, API, UI, tests), is demoable or verifiable on its own, and fits one fresh /geniro:implement session; prefactoring that eases later milestones lands in milestone-1. A layer-per-milestone split leaves nothing verifiable until the last milestone lands — the failure mode vertical slicing prevents. A wide mechanical refactor that cannot slice vertically sequences expand–contract instead, per the Big-tier row in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`.

1. Fire a follow-up AUQ with the proposed milestone names (single-select for "approve all" or multi-select pick per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`).
2. After approval, Phase 6 writes the top-level spec.md (with section 6 "Steps" listing milestones and a new body section `## Milestones` indexing the sibling files) PLUS each `milestone-N.md` with its own copy of the standard spec schema (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`) scoped to the milestone. A milestone that depends on specific earlier milestones (not merely everything before it) lists them in its `blocked_by:` frontmatter, and the `## Milestones` index mirrors those edges (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` §Milestone-mode).

Handoff (Phase 9) prints `/geniro:implement .geniro/planning/<slug>/milestone-1.md` for sliced specs. The milestone-mode AUQ fires only at Big tier; not Small/Medium/Trivial.

---

## 5. Phase 8 approval — message-first (summary in chat, lean AUQ)

Apply the Gate presentation contract (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Visual rendering language). Render the full plan summary to a chat message (with the concrete examples already authored per section), then fire a lean AUQ.

Chat message rendered before the AUQ:

```markdown
Plan approval — final step
✔ Approach · ✔ Goal & scope · ✔ Steps · ✔ Safety · ● Final approval

**In one sentence:** the full spec is written and checked — this is the last look
before it's committed and handed to implementation.

**🎯 The goal:** <section 1 body — single sentence>
**📦 In / out:** <section 2 Included bullets + section 3 Excluded summary — reuse
the in/out scope map from the Goal & scope step>
**🙋 Where you'll be asked mid-build:** <section 8 list, max 5 shown with
"... and N more" if >5>
**⚠️ Risk level:** <the highest per-risk severity in section 5, raised one level
when frontmatter forbidden_actions is non-empty> — <one-line why, naming the risk
that set the level>
**↩️ If something goes wrong:** <section 10 summary, 1-2 sentences>
**✅ How we'll know it's done:**
☐ <section 11 — one checkbox per observable signal, e.g. "all 5 acceptance tests green">
☐ <"telemetry shows ≥1 successful event insert">

**Technical detail:** spec on disk at `.geniro/planning/<slug>/spec.md`;
<glob count from section 2 Scope.Included> files in the touched surface.

Approval is valid for this planning session; re-approval is needed if the spec is
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
    description: "Describe what needs to change — I'll revise and re-check just the affected sections."
  - label: "Abort — discard spec"
    description: "Stops planning here — spec.md stays on disk but nothing is committed."
```

What each pick then does — the lifecycle flip, the commit, the revision-round ladder — is in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-8-user-approval.md` §8.3–§8.4. This section holds the template only.

---

## 5b. Phase 8 launch-config AUQ — pre-define implement settings (opt-in)

Fires at the very end of planning — Phase 8, AFTER the user approves the spec (§5 above) and BEFORE the §8.4 git commit. Replaced by the flag-driven build in §8.3.5 when launch modifiers (workspace / `freshness:` / ship) are present in `$ARGUMENTS`; this interactive gate fires only when no launch modifier was passed. `--deep` alone does not replace it. It captures `/geniro:implement`'s launch settings at plan time so `/implement` runs without re-asking. Field semantics, enum values, and the doctrine boundary are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` — this section is the question wording only.

Two steps: a gate question, then (only on "Yes") a batched capture.

### Step 1 — gate question

A lean single-question AUQ. The gate question never auto-defaults — an empty answer is re-asked, not defaulted, because opting in is a real choice (unlike the per-field defaults in Step 2, which presuppose a "Yes"):

```yaml
header: "Setup"
question: "Pre-define the implementation settings now, so /implement can run on its own?"
options:
  - label: "Yes — set them now"
    description: "Pick the workspace, depth, branch handling, and ship mode here; /implement skips those questions and runs on its own."
  - label: "No — /implement will ask when it runs"
    description: "Leave the settings unset; /implement asks them interactively at start, exactly as it does today."
```

On "No" → write no `launch_config:` block; persist the declined gate answer to `approvals[]` (Step 3) and proceed to §8.4 with the spec unchanged. On "Yes" → fire Step 2.

### Step 2 — batched capture (only on "Yes")

A batched capture. The four always-present settings (workspace / depth / branch handling / ship mode) fill ONE AUQ call — the 4-question-per-call tool cap. When the spec has a linked tracker ticket (state.md `## Workflow Refs` / held `workflow_refs[]` non-empty), a fifth setting — the kickoff tracker-status pre-answer — chains into a SECOND AUQ call rather than displacing one of the four: chain, never drop. With no linked tracker ticket, only the first four-question call fires. Each field carries a recommended default; an empty answer on a field falls back to that field's recommended value (the user already opted in by picking "Yes"), so no field can block. Recommended defaults: `new-branch`, Standard (`deep_mode: false`), `rebase`, `draft-pr`, and (when offered) `move-to-in-progress`.

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
  - header: "Run depth"
    question: "How deep should the implementation review go?"
    options:
      - label: "Standard"                     # Recommended → deep_mode: false
        description: "Single self-review pass; standard cost."
      - label: "Deep"
        description: "Multi-angle self-review plus a pre-edit fact-check; higher quality, higher cost."
  - header: "Branch sync"
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

**Chained second call — only when a tracker ticket is linked** (`workflow_refs[]` non-empty). Fire a SECOND `AskQuestion` immediately after the first resolves, carrying the single tracker-status question — never appended to the first call:

```yaml
questions:
  - header: "Task status"
    question: "When /geniro:implement starts, move the linked tracker task to In Progress?"
    options:
      - label: "Yes — move to In Progress"        # Recommended → tracker_status: move-to-in-progress
        description: "/geniro:implement confirms the kickoff move on its own. It still skips the move when the task is already In Progress."
      - label: "No — leave the status unchanged"   # → tracker_status: leave-unchanged
        description: "/geniro:implement won't change the tracker status at kickoff."
```

Map the picks to the `launch_config:` block values (`workspace` / `deep_mode` / `branch_freshness` / `ship_mode`, plus `tracker_status` when the chained tracker-status call fired) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"The block". Omit `tracker_status` from the block when no tracker ticket was linked (the chained call did not fire). Hold the block for the §8.4 spec rewrite.

### Step 3 — persistence

Append one entry to `approvals[]` with category `launch_config`, `asked_in_phase: user-approve` — the §1 entry shape plus a nested `launch_config:` sub-block holding the captured fields:

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
      tracker_status: move-to-in-progress   # present only when a tracker ticket was linked
    at: 2026-05-17T11:20:00Z
    asked_in_phase: user-approve
```

On "No", omit the `launch_config:` sub-block and record `picked: "No — /implement will ask when it runs"`.
