# Plan Loop

Canonical phase pattern for `/geniro:plan`.

This file is the single source of truth. Skills cite this file; do NOT inline-paste the loop logic.

## Contents

- HARD-GATE
- Gate presentation contract
- Phase 0 — Mode detect
- Phase 0.5 — Problem discovery (opt-in, `--prd`)
- Phase 1 — Explore
- Phase 2 — Visual Companion (UI-conditional)
- Phase 3 — Grill (decision-tree clarification)
- Phase 4 — Approaches
- Phase 5 — Section approval
- Phase 6 — Write spec.md
- Phase 7 — Mechanical validator
- Phase 7.5 — Spec challenge
- Phase 8 — User approval
- Phase 9 — Handoff
- Definition of Done
- Anti-rationalization

---

## HARD-GATE

> Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until the Phase 8 user-approve AUQ has been answered "Approve". The gate is binding for Phases 0–8. The Phase 8 "Approve" answer IS the release decision; Phase 9 only prints the next-step command after it.

---

## Gate presentation contract

Every gate that presents rich, multi-part content — Phase 0.5 problem-discovery, Phase 3 grill questions, Phase 4 approaches, Phase 5 section approval, Phase 8 final approval — follows a two-step shape: **render to chat first, then fire a lean question.**

1. **Render the content as a SEPARATE chat message FIRST.** Write the full detail to chat as its own already-emitted assistant message, in the Visual rendering language below — progress tracker, one-sentence opener, friendly digest blocks, concrete code examples, and the per-unit visual (especially section 6 Steps and Phase 4 data-flow). It must exist before the question fires; the render and the AUQ tool call must never share one assistant turn (same-turn text may not display, and a question pointing at "the message above" with no such message obtains an uninformed approval). This message is where the user reads and understands the plan — full width, persists in scrollback.

2. **Then fire a LEAN `AskUserQuestion`.** Options are short decision selectors (Approve / Revise / Cancel-style), each with a one-line `description`. The `preview` side-box is NOT the rendering surface — leave it empty, or use it for a one-line recap only. Before firing, run the canonical render-exists check in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering (the render-exists and resume-path rules apply identically here). Firing is part of the render's own action: once the render message exists, the question follows immediately — never stop on the render alone or on a statement of intent to ask, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard.

Why this shape: `AskUserQuestion` renders `preview` as a narrow monospace panel beside a vertical option list, so a section digest, code, and diagrams crammed there are unreadable — the failure mode this contract exists to prevent. Rendering to chat gives the content full width; the lean question then captures only the decision.

### Visual rendering language

The Phase 4, Phase 5, and Phase 8 gate messages render in the shared visual language defined canonically in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Visual rendering language — progress tracker, one-sentence opener, friendly digest blocks (lead sentence / `**Why:**` with evidence cite / `**How it gets built:**` / `**You'll see:**`), a visual per unit, light heading icons, closed against the plain-English bar. The plan instantiation:

- **Journey stops.** The tracker runs over the stops `Approach · Goal & scope · Steps · Safety · Final approval` (the three middle stops are the Phase 5 clusters under short display labels). Example at Phase 5 cluster 1: `✔ Approach · ● Goal & scope (step 1 of 3) · ○ Steps · ○ Safety · ○ Final approval`. When Trivial tier collapses clusters, show the collapsed stops.
- **Per-section visuals.** Every section or approach carries the visual shape mapped in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-reference.md` §"Concrete example + visual per section type" — scope map, steps flow diagram, risks table, done-condition checklist, approach data-flow; render plain text instead only when a section genuinely has nothing to map (e.g., "none — task scope precludes").
- **Section-heading icons** — e.g. 🎯 objective / 📦 included / 🚫 excluded / ⚠️ risks / 🧪 validation / ↩️ rollback / ✅ done.

**One decision per logical unit.** Phase 5 fires ONE question per cluster (not one per section); Phase 4 fires ONE question for the approach choice; Phase 8 fires ONE question for the whole spec. Collapsing per-item questions into one-per-unit stops the gate from re-asking decisions the user already settled upstream (in clarify / approaches), which is the click-through fatigue this contract also prevents. Per-decision persistence granularity is unchanged — a unit-level approval still writes one `approvals[]` entry per item it covers (Phase 5 §5.2).

---

## Phase 0 — Mode detect

State.md `phase: mode-detect` during this phase. Light cost — a single design-doc-detect.md helper call.

### 0.1 $ARGUMENTS resolution

**`--prd` flag detection (opt-in).** If `$ARGUMENTS` contains the token `--prd`, note that the flag was passed and strip the token before passing the remaining text to mode detection. state.md does not exist yet at this point — it is created in §0.3 — so do NOT write frontmatter here; instead carry the flag forward and write `prd_mode: true` into the INITIAL state.md frontmatter at the §0.3 creation step. `prd_mode` turns on the Phase 0.5 problem-discovery interview and the spec's optional `## Problem & Evidence` body section. When `--prd` is absent, `prd_mode` stays unset and Phase 0.5 is skipped.

**`--deep` flag detection (opt-in).** Semantic-parse `$ARGUMENTS` for `--deep` / `deep` / `deep mode` the same way; strip the token before mode detection. Carry it forward and write `deep-mode: true` into the §0.3 initial frontmatter (false/omitted when absent), and persist the activation to `approvals[]` category `deep_mode_choice`. `deep-mode` deepens Phase 4 (judge-panel approach search + 3× feasibility critics) and Phase 7.5 (3× claim verification) per `${CLAUDE_PLUGIN_ROOT}/skills/plan/deep-mode-reference.md`; it is orthogonal to `--prd` (both may be passed). When absent, those phases run their standard single-pass paths unless the user picks Deep in the Phase 3 depth question (folded into the clarify AUQ — see §Phase 3 and `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2). On a Trivial task that skips Phase 3, depth stays flag-only.

**`--artifact` flag detection (opt-in).** If `$ARGUMENTS` contains the token `--artifact`, note it and strip the token before mode detection. state.md does not exist yet — carry the flag forward and write `artifact_mode: true` + `artifact_status: pending` into the §0.3 initial frontmatter. The flag turns on the live visual plan artifact (per the §0.2.5 opt-in step and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md`); when the flag is present, skip the §0.2.5 opt-in question — the flag is the opt-in. When `--artifact` is absent, the §0.2.5 question decides whether artifact mode turns on.

**Launch-modifier detection (opt-in pre-fill of `launch_config`).** `/geniro:plan` also recognizes the `/geniro:implement` launch modifiers so a `/plan <topic> worktree ship:draft` invocation pre-fills the plan's `launch_config` block instead of discarding them. Semantic-parse `$ARGUMENTS` for the workspace modifiers (`new-branch` / `current-branch` / `worktree` / `no-worktree` / `here`), the ship modifiers (`don't push` / `no push` / `commit only` → commit-no-push, `draft only` → draft-pr, `ready-for-review` → ready-for-review, `stop after review` → stop-after-review), and a `freshness:merge` / `freshness:rebase` / `freshness:skip` modifier (colon form only — bare `merge` / `skip` are too ambiguous inside a free-text planning topic); `--deep` is already handled above. Strip the matched tokens from the topic text before mode detection, then carry the recognized set forward to two places: the `freshness:` token feeds §1.1b (the Phase 1 branch-freshness step applies the strategy directly), and the full launch-modifier set feeds §8.3.5 to pre-fill `launch_config` non-interactively. When no launch modifier is present, both steps run their interactive paths.

Use `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` helper unchanged. Returns:

- **IDEA(topic)** — free-form text; proceeds to Phase 1 with topic as initial context.
- **DESIGN_DOC(path)** — existing design doc; flows to AUQ.
- **CODE_REFERENCE(path)** — error per design-doc-detect.md per-consumer table: "code reference passed to /geniro:plan; pass a topic or design-doc path. Did you mean /geniro:implement <path>?". Exit without writing state.md.
- **None** (empty $ARGUMENTS) — fires empty-argument AUQ:
 - `header`: "Topic"
 - `question`: "What do you want to plan?"
 - `options[]` (single-select, 3 options + Other free-text): "New feature" / "Existing problem to solve" / "Cancel"
 - Non-empty answer (via a picked option OR free-text Other) → IDEA mode; "Cancel" → terminal without state.md.
 - Persist outcome to `approvals[]` with `category: disambiguate_arguments` .

### 0.2 DESIGN_DOC mode AUQ

Fire `AskUserQuestion` with:
- `header`: "Existing design doc"
- `question`: "Design doc already exists at `<path>`. What now?"
- `options[]` (single-select, 2 options):
 - **Start fresh with this as context** (Recommended) — load the doc into Phase 1 explore context; run the full planning loop (Phases 0–9 plus the always-on Phase 7.5 spec-challenge; Phase 2 fires only when the UI trigger matches per §"Phase 2 — Visual Companion"); emit a new spec.md at a fresh task-dir.
 - **Cancel** — exit without writing state.md.

**On "Start fresh"** → flow to Phase 1 with the doc body inlined into Phase 1 research-agent prompts under a `## Prior Design Doc` section. The doc is NOT used as section template; Phase 5 uses the 11-section schema unconditionally.

**On "Cancel"** → exit immediately. Surface terminal message: "Cancelled before planning started".

### 0.2.5 Visual artifact opt-in

After mode resolves (IDEA or DESIGN_DOC) and before the §0.3 state.md write. When the `--artifact` flag was present in §0.1, skip this question — the flag is the opt-in, the run is in artifact mode. When the flag was absent, fire the single opt-in `AskUserQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md` § The opt-in question (formal template in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1b). On the "Yes" pick (or flag present) the run is in artifact mode — the §0.3 frontmatter gets `artifact_mode: true` + `artifact_status: pending`; on "No" artifact mode stays off and no artifact fields are written. Persist the pick to `approvals[]` category `artifact_choice` so a resume doesn't re-ask.

### 0.3 Task-dir + state.md creation

After mode is resolved (IDEA or DESIGN_DOC):

1. **Resolve task slug.** Inputs: $ARGUMENTS topic OR basename(design-doc) sans extension. Output: kebab-case slug ≤40 chars.
2. **Task-dir:** `.geniro/planning/<task-slug>/`.
3. **state.md:** `.geniro/planning/<task-slug>/state.md`. Write via `atomic_state_write`. Full frontmatter + body template (frontmatter fields `tier`/`producer`/`schema-version`/`branch`/`worktree`/`timestamp`/`phase`/`status`/`non-resumable-actions`/`approvals`/`task_slug`/`mode`; plus `prd_mode: true` when the `--prd` flag was present in §0.1, omitted otherwise; plus `deep-mode: <true|false>` from the `--deep` flag in §0.1 (false when absent); plus `artifact_mode: true` and `artifact_status: pending` written together when artifact mode is on (the `--artifact` flag was present OR the §0.2.5 opt-in answered Yes), both omitted otherwise; body sections `# State: <topic>` / `## Inputs` / `## Tool log` / `## Errors` / `## Open Questions`) in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1.
4. **Transition.** Branch on the `--prd` flag from §0.1: when it was present, set `phase: problem-discovery` via `atomic_state_write` and proceed to Phase 0.5; otherwise set `phase: explore` and proceed to Phase 1. Phase 0.5 itself sets `phase: explore` on completion (§0.5.4), so a `--prd` run flows through problem-discovery then rejoins the normal loop at Phase 1.

### 0.4 Cancel handling

If state.md already created when user cancels (e.g., deep cancel via Other): write `phase: aborted` + `## Termination reason: user-cancelled-at-phase-0` via `atomic_state_write` before exit.

---

## Phase 0.5 — Problem discovery (opt-in, fires only on `--prd`)

State.md `phase: problem-discovery` during this phase. **Fires only when `prd_mode: true`** (set in Phase 0.1 from a `--prd` flag in `$ARGUMENTS`). When `prd_mode` is unset, skip this phase entirely — the loop transitions Phase 0 → Phase 1 unchanged.

This phase runs a problem-first discovery interview BEFORE explore and clarify, so the eventual spec is grounded in a validated problem rather than a presumed solution. Unlike the Phase 3 clarifying questions (asked one at a time), the six discovery dimensions are a fixed independent interview set, so batch them into AUQ calls (≤4 questions per call; chain a second call past the cap rather than drop a question — the 4-question-per-call tool limit applies here too) to keep the upfront interview compact.

### 0.5.1 Interview dimensions

Ask one question per dimension. These are independent, so batch them — two calls of ≤4 questions each (the six dimensions exceed the 4-per-call cap, so chain a second call per the cap-extension rule):

| Dimension | What it captures | Why it's load-bearing |
|---|---|---|
| Problem statement | The problem in one sentence, framed as the pain — not a feature ("users abandon checkout at the address step", not "add address autocomplete"). | A solution chosen before the problem is named bakes in the wrong assumption. |
| Evidence | What proves the problem is real — a metric, a support-ticket count, a recorded session, a quote. | Distinguishes a real problem from a guessed one; an unevidenced problem routes to "gather evidence first". |
| Target user + job-to-be-done | Who has the problem and the job they are trying to get done. | Scopes the solution to a user and a job, not "everyone, vaguely". |
| Hypothesis | A testable "if we do X, then metric Y moves by Z" statement. | Makes success falsifiable — the spec can be validated against it. |
| Success metrics | The 1-3 metrics that confirm the problem is solved. | Feeds spec section 9 (Validation) and section 11 (Done Condition). |
| Prioritization | Rough MoSCoW split (Must / Should / Could / Won't) of the candidate scope. | Pre-sorts scope before Phase 5; the Must set seeds section 2 (Scope — Included), the Won't set seeds section 3 (Scope — Excluded). |

Apply the Gate presentation contract: when a dimension needs framing the user can't act on from a one-line option (why the dimension is load-bearing, an example of a good answer), render that framing to a chat message first, then fire the batched AUQ with short option labels. Offer a free-text "Other" path on every question; for the open-ended dimensions (problem statement, evidence, hypothesis) the user will usually type rather than pick a canned option, so the canned options are illustrative anchors, not an exhaustive menu. When the user has no evidence, capture that honestly: record "evidence: none yet" and surface a one-line note that the problem is unvalidated — do not invent evidence.

### 0.5.2 Persistence

Append one entry to state.md frontmatter `approvals[]` per answered question via `atomic_state_write`, category `prd_<dim>` (e.g., `prd_problem_statement`, `prd_evidence`, `prd_target_user`, `prd_hypothesis`, `prd_success_metrics`, `prd_prioritization`). Same entry shape as Phase 3 (category / prompt / options / picked / at / asked_in_phase). Persisting here is non-negotiable: a context reset mid-plan would otherwise lose the entire problem framing, and the SessionStart re-injector renders `approvals[]` so a resumed session re-reads the answers and skips re-asking.

Also append a `## Problem Framing` body section to state.md capturing the synthesized free-text answers (problem / evidence / user + job / hypothesis / metrics / MoSCoW), so Phase 6 can copy it into the spec without re-deriving from `approvals[]`:

```markdown
## Problem Framing
- problem: <one-sentence pain statement>
- evidence: <metric / ticket count / quote, OR "none yet — unvalidated">
- target_user: <who> — job: <job-to-be-done>
- hypothesis: if <X> then <metric Y> moves by <Z>
- success_metrics: <1-3 metrics>
- moscow:
    must: [...]
    should: [...]
    could: [...]
    wont: [...]
```

### 0.5.3 Feed-forward

The problem framing feeds two downstream sites:

- **Phase 1 explore** — inline the `## Problem Framing` body into research-agent prompts under a `## Problem Framing` section, so research targets the named problem and its evidence rather than a presumed solution.
- **Phase 3 clarify + Phase 5 section authoring** — the Must/Should set seeds section 2 (Scope — Included); the Won't set seeds section 3 (Scope — Excluded); the success metrics seed section 9 (Validation) and section 11 (Done Condition); the problem statement and evidence populate the spec's optional `## Problem & Evidence` body section (Phase 6).

Section 1 (Objective) stays a single declarative goal sentence — NOT the problem statement (the validator's `single_objective` check enforces this). The problem framing lives in the separate `## Problem & Evidence` section; the Objective is the solution-goal derived from it.

### 0.5.4 Transition

After the interview persists, transition `phase: explore` and proceed to Phase 1 normally. Phase 1 now carries the problem framing as added context. All subsequent phases run unchanged except for the two feed-forward sites above and the Phase 6 `## Problem & Evidence` write.

---

## Phase 1 — Explore

State.md `phase: explore` during this phase.

### 1.1 Memory layer loading

At Phase 1 entry, load **L4 + L3 + L2** (full tier, NOT rules-only):

- **L4:** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: plan`, `LOAD_TIER: pipeline`, `MODE: refresh`. Scope = `plan` + `global` + `code-style`.
- **L3:** `source "${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh" && load_semantic`. Default top-2 (`_project.md` + `_CODEBASE_MAP.md`). Fingerprint drift check fires; surface drift to user.
- **L2:** read past learnings — route per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (a declared `## Memory Backend` block redirects this to its read tool; the file is empty under `mode: replace`), else `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --tag <inferred> --scope <topic-area> --limit 5`. Skipped if topic is too generic to infer tags.
- **Cross-layer resolution:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol if L4/L3/L2 disagree.

Loading all three layers ensures research agents have full context — prior decisions (L2), codebase map (L3), and user rules (L4) — preventing repeated rediscovery.

### 1.1b Branch freshness

On a fresh run (skip on compaction-resume), apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`. /geniro:plan does not create branches, but when the current branch is behind the latest default branch, the freshness step grounds the spec in fresh code rather than a stale tree. When a `freshness:merge` / `freshness:rebase` / `freshness:skip` modifier was passed in `$ARGUMENTS` (§0.1), apply that strategy directly without firing the offer AUQ — `freshness:skip` means do not update; `freshness:merge` / `freshness:rebase` apply that strategy on a clean fast-forward, while a real conflict still surfaces interactively per `branch-freshness.md`. When no `freshness:` modifier is present, offer the update before research spawns. This covers BOTH cases the helper handles: a feature branch behind the default (offer merge/rebase), AND sitting on the default branch itself while its remote moved ahead (offer pull) — do not skip the gate just because HEAD is on the default branch. Skipped silently only when the branch already contains everything on the default.

### 1.2 Effort-tier-scaled research spawns

Detect effort tier from $ARGUMENTS shape using `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`:

| Tier | Spawns |
|---|---|
| Trivial (typo / config tweak / mechanical rename — no logic change) | 1 agent OR 0 if obviously scope-bound |
| Small (localized, single-concern change) | 1-2 agents (existing-impl; integration-surface only if it spans a boundary) |
| Medium (a feature, or a change that touches a contract / boundary) | 2 agents (existing-impl + integration-surface) |
| Big (a hard escalation signal is present, or dimension score 7+ per effort-scaling.md) | 3-4 agents (subsystem-A + subsystem-B + cross-cutting + conventions) |

Spawn `codebase-research-agent` for each primary Phase 1 facet per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research. Facet-specific slot values: `RESEARCH_QUESTION` = the facet's research goal; `DELIVERABLE_SHAPE` = `"table of [{file, lines, observation}] verified findings"`; `SCOPE_HINT` = the facet's path globs; `OUTPUT_PATH` = `<task-dir>/.research-<facet>.md`; `THOROUGHNESS` = `medium` (default) or `very thorough` for Big-tier subsystem facets.

When `$ARGUMENTS` carries a tracker reference, complete §1.4's tracker fetch + chain assembly **before** issuing these spawns — §1.4 produces the "TASK CHAIN CONTEXT" block these spawns consume, so it must run first or the block does not exist yet. Then issue all spawns `run_in_background: true` in a single assistant response per the parallel-spawn rule (Shape A of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md` — backgrounding frees the orchestrator to fire code-independent grill questions per §3.1 during the explore wait; the drain is §1.5 synthesis), each additionally receiving the "TASK CHAIN CONTEXT" block (when present) as added context so the spec is grounded in where this task sits in the larger chain of work. Per-spawn output schema: `[{file, lines, observation}]`; cap ~4000 chars (truncate with marker).

### 1.3 Echo contract

Each Phase 1 research spawn writes a structured entry to state.md `## Tool log` via `atomic_state_write`:

```yaml
## Tool log
- ts: 2026-05-17T10:42:13Z
 tool: Agent
 detail: "Research: existing auth flow integration points"
 status: ok
 summary: "found 3 files, 1 convention pattern"
 citations:
 - src/auth/oauth.ts:42-58
 - src/auth/__tests__/oauth.test.ts:14-29
 - src/middleware/session.ts:88-101
```

Phase 7 validator (check #3) requires ≥1 Agent entry with `status: ok` per effort tier (Trivial ≥1 OR explicit "scope-bound, no exploration needed"; Small ≥1; Medium ≥2; Big ≥3). The Echo contract makes "no related code found" auditable via SessionStart re-injection.

### 1.4 Workflow refs fetch (tracker linkage)

If `$ARGUMENTS` contains a tracker reference (Linear URL/ID, Jira key, GitHub issue URL, Asana task URL), fetch via the matching MCP and persist to state.md `## Workflow Refs` body section. This block is the source-of-truth for Phase 6 frontmatter assembly.

**Detection:** existing workflow-plumbing already detects tracker references at Phase 1 entry. Workflow files (`.geniro/workflow/<kind>.md`) live in the primary worktree per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (Mode A) — try `./.geniro/workflow/<kind>.md` (cwd-local; uncommitted local edits win) first, on file-not-found retry against `<PRIMARY_ROOT>/.geniro/workflow/<kind>.md`. Each file defines per-tracker patterns. When a match resolves to `kind=<linear|jira|github-issues|asana>` and `issue_id=<id>`:

1. Fetch via the matching MCP (`mcp__linear__get_issue` for Linear, etc.). If MCP unregistered, log a `## Errors` entry and continue without persistence — graceful degrade per existing pattern.
2. Append to state.md `## Workflow Refs` via `atomic_state_write`:

```yaml
## Workflow Refs
- kind: linear
  issue_id: CI-303
  url: https://linear.app/.../CI-303/...
  fetched_at: 2026-05-26T10:42:13Z
  title: "..."
  suggested_branch: ci-303-...
  status: Todo
  parent_ref:
    kind: linear
    issue_id: CI-300
    url: ...
    title: "Case Radar performance epic"    # chain enrichment (§1.4 step 4)
    status: In Progress                      # chain enrichment
    scope: "Cut backfill latency below 5 min."  # chain enrichment, ≤280 chars
  siblings:                                  # chain enrichment, ≤8 entries, omit when none
  - issue_id: CI-301
    title: "..."
    status: Done
  chain_fetched_at: 2026-05-26T10:42:15Z     # chain enrichment, independent staleness from fetched_at
```

3. The fetched payload feeds Phase 1 research-agent prompts (existing behavior) AND becomes the canonical source for Phase 6 frontmatter copy. Skipped when `$ARGUMENTS` carries no tracker reference — pure inline-task /geniro:plan emits a spec.md without `workflow_refs[]`.

4. **Assemble the related-task chain.** After the current issue resolves, apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md` (MODE: plan) with the fetched ref(s) + the task-dir to gather the chain of related work — the parent epic (title / status / scope), the sibling sub-tasks (each with its status), and neighboring milestone files on disk — and to derive the done-before / where-we-are / what's-next narrative. The helper also cross-checks each load-bearing chain fact against the project's declared `## Data Sources` (read-only, fail-open) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`, marking any status no source can confirm as unconfirmed and surfacing conflicts rather than assuming a single fetch. Merge the helper's `ENRICHED_REFS` (the tracker half: `parent_ref.{title,status,scope}` + `siblings[]` + `chain_fetched_at`) into the state.md `## Workflow Refs` block via `atomic_state_write`. Stay read-only on the tracker — never mutate the parent or siblings. Fail-open: on MCP unregistered/timeout, skip enrichment, log a `## Errors` entry, and continue. Run this assembly before the §1.2 research spawns and hold the assembled "TASK CHAIN CONTEXT" block in context for their prompts; the milestone half is derived fresh each run and is never persisted.

### 1.5 Transition to Phase 2

**Drain the backgrounded explore agents first.** Before synthesizing, confirm every §1.2 explore spawn returned — Read each `<task-dir>/.research-<facet>.md`, or resume the agent by ID if an output is missing. This is the drain that closes the §1.2 overlap (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md`): synthesis consumes the research, so it cannot start against an in-flight agent.

Model synthesizes findings into a brief inline summary held in context (no separate artifact). The summary feeds Phase 2 UI trigger detection, Phase 3 question generation, and Phase 5 section authoring. State.md `phase: visual-companion` written before Phase 2 entry (`phase: clarify` if Phase 2 trigger doesn't fire).

**Visual plan artifact — first publish.** When `artifact_mode: true`, build the live page now so it grows from the first phase: `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Availability detection & create`, passing the task-dir, the plan title, and the planning-journey stops. After it returns, persist the result via `atomic_state_write` per the helper's § URL persistence — `artifact_status: live` + `artifact_url` on a returned `claude.ai` URL, or `artifact_status: unavailable` when no URL comes back (the helper shows the one-time skip notice and the later Update calls then skip). Skip this whole step when `artifact_mode` is unset.

**Skip to Phase 4 if Trivial:** when effort tier is Trivial AND research returned 0-1 findings AND topic is a narrow text-edit, Phases 2 + 3 are skipped. Write a one-line note to state.md `## Open Questions`: "Phases 2-3 skipped — trivial task, no ambiguity surfaced".

---

## Phase 2 — Visual Companion (UI-conditional)

State.md `phase: visual-companion` during this phase. Fires only when a UI trigger matches.

### 2.1 Trigger detection

Fire Phase 2 if **either** condition holds:

- Phase 1 research surfaced any path matching a UI file — path matches `**/components/**`, `**/pages/**`, `**/app/**`, `**/views/**`, `**/ui/**`, OR extension is `.tsx` / `.jsx` / `.vue` / `.svelte` / `.css` / `.scss` / `.sass` / `.less` / `.styled.ts` / `.styled.tsx`, OR
- $ARGUMENTS topic string contains a UI noun: `page`, `screen`, `modal`, `form`, `dashboard`, `button`, `view`, `panel`, `widget`.

No trigger → skip Phase 2 entirely. Transition `phase: clarify` and proceed to Phase 3.

### 2.2 UI preview procedure

Trigger fires → run the procedure documented at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` end-to-end. That helper spawns the UI description agent, presents the textual preview, runs the revision loop (max 3 rounds), and returns the approved description.

Caller contract (this skill's side):
- Provide the predicted affected-files list (from Phase 1 echo entries with UI-file matches), $ARGUMENTS topic, 1-2 exemplar UI files (path-only — agent reads them itself).
- Destination path: hold in-memory as Phase 5 substrate. Do NOT write a separate `ui-preview.md` artifact at the planning task-dir — the approved description feeds Phase 5 section 6 (Steps) + section 9 (Validation) directly.

### 2.3 Persistence

The approved description is appended to state.md `## UI Preview` body section via `atomic_state_write`:

```markdown
## UI Preview
<approved description verbatim, ≤200 lines per ui-preview-gate.md output constraint>
```

Phase 5 section 6 / section 9 authoring cites this block as substrate. Phase 7 validator does not gate on `## UI Preview` presence (Phase 2 is conditional; absence is valid).

### 2.4 Routing-out signal

If the user picks "Adjust the plan instead" at any revision round of ui-preview-gate.md, return to Phase 1 with the user's feedback inlined into research-agent prompts. State.md transitions `phase: explore` (re-enter) — round-count not incremented since the user is correcting the plan substrate, not the UI preview itself.

---

## Phase 3 — Grill (decision-tree clarification)

State.md `phase: clarify` during this phase.

This phase is a decision-tree grill: walk the design's open decisions depth-first, one question at a time, until the branches that shape the spec resolve. It replaces a flat fixed-size question list — a real plan is a tree of dependent decisions, so resolving a parent decision reshapes (or removes) its children, which means the question set cannot be enumerated up front.

### 3.1 Build the decision tree

Build the tree from:
- Phase 1 research findings ("found 3 auth flows — which one is the integration surface?")
- L2 query-learnings ("a prior decision favored Approach X — does it apply here?")
- L4 code-style rules
- the Phase 0.5 problem framing when `--prd` was passed

Root = the feature. Branches = its major design axes (data model, integration surface, failure handling, UX, scope edges). A child decision that only matters under a particular parent answer hangs off that parent.

**Codebase-first.** Before asking anything the code can answer, read it — for a multi-file question spawn `codebase-research-agent` (invariant #8). Ask only what the code cannot settle: a question answerable from L3 `_project.md` ("what test runner?") is forbidden — answer it silently and move on.

**Grill early during the explore wait.** When the §1.2 explore agents were backgrounded, the orchestrator MAY fire the code-independent grill branches early — during that wait — per Shape A of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md`. Eligible early: branches sourced from L2 learnings, L4 rules, the `--prd` problem framing, and task-generic scope edges (feature-flag / rollout / in-scope-surface) — questions the code cannot answer. HELD until the §1.5 drain: the Phase-1-findings-derived branch and anything L3 `_project.md` could answer — exactly the "Codebase-first" forbidden set, whose complement is the safe overlap set. Ask each early question one at a time per §3.2 and persist to `approvals[]`; Phase 3 regenerates its tree skipping the already-answered branches (never re-ask). If no code-independent question exists, wait for the drain — behavior is then unchanged.

**Walk depth-first.** Pick the highest-leverage unresolved branch, drill it to its leaves in parent→child order, then backtrack to the next branch. Depth-first keeps each line of questioning coherent instead of scattering across unrelated axes.

### 3.2 AUQ shape — message-first, one question at a time

Apply the Gate presentation contract. Ask one question at a time — one `AskUserQuestion` call per question, never a multi-question batch. Before each question render its framing to a chat message first, sized to the question: a one-line orientation when every option is self-explanatory, a short per-option consequence block (a code anchor, config diff, or behavior trace) when an option's consequence needs more than its one-line `description`. Then fire the lean single-question AUQ with short labels + one-line `description`s. Give a recommended answer for every question (Recommended-first option) — the user is confirming a default, not authoring from scratch.

One question per call, not a batch, because each answer reshapes the tree frontier: a still-pending child can become moot (drop it) or need reworded options. Do NOT pre-generate a fixed question list — regenerate the next question from the live tree after each answer. Each question uses `header` ≤12 chars, `question` 1-2 sentences ending in a question mark, `options[]` of 2-4 explicit choices, `multiSelect: false` unless explicitly multi-select. Include a "Skip — proceed with stated assumption" option as the last choice when applicable. The grill is uncapped but bounded by the §3.4 checkpoint gate. Full literal example with the per-question chat message + single-question AUQ in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2.

When `--deep` is absent, ask the planning-depth question (Standard / Deep) once at grill wrap-up (§3.4) — its own single-question AUQ, after the substance is settled. The depth question is a mode question, not a clarifying ambiguity, so it is exempt from the §3.4 checkpoint cadence and never triggers a wrap-up. When `--deep` is present, depth is already Deep, so skip the question. Persist the pick to frontmatter `deep-mode` and `approvals[]` category `deep_mode_choice`; an empty answer defaults to Standard (`deep-mode: false`). Phase 3 is skipped on Trivial tasks (§1.5), so on Trivial depth stays flag-only. The exact AUQ shape is in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2.

### 3.3 Persistence

Each answered question → append entry to state.md frontmatter `approvals[]` via `atomic_state_write`. Append the `approvals[]` entry for each answer before rendering the next question — so a context reset mid-sequence preserves every answer already given. Entry shape (category `clarify_<dim>` / prompt / options / picked / at / asked_in_phase) in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2.

On compaction-resume, the SessionStart re-injector renders `approvals[]` and the model re-reads it to skip already-answered questions.

### 3.4 Checkpoint gate and termination

There is no fixed question cap — the grill runs until the spec-shaping branches resolve. To keep it bounded without a hard number, pause for a checkpoint whichever comes first: a full design branch resolves, OR ~6 questions have been asked since the last checkpoint. This is an escalation gate, not an abort — consistent with the clarification-heavy budget framing, which caps no total AUQ count; the user, not a fixed number, decides when to stop.

**Mirror the pending decision onto the artifact first.** When `artifact_mode: true` and the page is not recorded unavailable (`artifact_status` is not `unavailable`), refresh the Current decision panel before the checkpoint AUQ so the user can read it on the page: `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Before-gate update with PHASE: clarify and the pending decision with full per-option detail + the supporting deep-dive content now available`. The chat summary below stays the primary render; the panel only mirrors it. Refresh the panel only at this checkpoint, never per grill question.

At a checkpoint, render a running summary to a chat message — resolved decisions, deferred items, and the open branches still to walk — then fire ONE lean AUQ:
- **Keep grilling** (Recommended while open branches remain) — continue the walk.
- **Wrap up now** — stop; remaining open branches become stated assumptions.
- **Skip remaining branches with stated assumptions** — same as wrap-up, but name the skipped branches explicitly in the Assumptions section for /geniro:implement to verify.

Persist each checkpoint decision to `approvals[]` category `grill_checkpoint` via `atomic_state_write` before continuing.

**Termination** fires when all branches resolve, the user picks Wrap up / Skip, or no spec-shaping question remains. On termination, render a closing summary — resolved decisions, deferred work, and any unaddressed risks — and hold it in context: it feeds Phase 4 approach generation and seeds Phase 5 sections (Steps / Validation / Done Condition). Then ask the planning-depth question (§3.2) when `--deep` is absent, and transition to Phase 4. The checkpoint and termination summary templates are in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2.

**Visual plan artifact — decision log.** When `artifact_mode: true` and the page is not recorded unavailable (`artifact_status` is not `unavailable`), on termination revise the page with the resolved decisions: `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Update with PHASE: clarify and the content just produced` (the decision log). The Update call reads `artifact_url` from state.md frontmatter when present, so a resumed/compacted session revises the same page rather than creating a duplicate.

---

## Phase 4 — Approaches

State.md `phase: approaches` during this phase.

**Deep-mode branch (`deep-mode: true`).** Do NOT run the single-pass §4.1 synthesis + tier-scaled §4.2 critics below. Instead run the judge-panel approach search (3-4 diverse-lens generators → dedup → rank) and the 3× feasibility critics with majority vote, both inside an internal `Workflow(...)`, per `${CLAUDE_PLUGIN_ROOT}/skills/plan/deep-mode-reference.md` §2-3. Fold the top 2-3 ranked candidates into the §4.3 chat message + AUQ exactly as standard mode does. Fail-safe to the single-pass path below if the workflow errors (deep-mode-reference §6). Everything below describes the standard single-pass path.

### 4.1 Approach generation

Model synthesizes Phase 1 explore + Phase 3 answers into 2-3 distinct approaches. Each approach:
- **Name** (3-5 word label)
- **Summary** (2-3 sentences)
- **Trade-off** (1 sentence: gain vs give-up)
- **Effort estimate** (Trivial / Small / Medium / Big per effort-scaling.md)

### 4.2 Independent stress-test (adversarial weighing)

The model that generated the approaches in §4.1 also ranks them in the §4.3 AUQ — same context, same blind spots, so its `Recommended` pick just re-confirms its own bias. Before ranking, get an independent challenge grounded in the actual codebase, so the `Recommended` marker reflects feasibility evidence rather than the author's confidence.

Effort-tier-scaled (tier already detected in Phase 1.2 — the critic cost lands only where a wrong approach is expensive):

| Tier | Stress-test spawns |
|---|---|
| Trivial | Skipped — single narrow approach, no ranking risk |
| Small | Skipped — too narrow to warrant a critic; if Phase 4 produced ≥2 genuinely competing approaches, treat as Medium (1 comparative critic) |
| Medium | 1 `codebase-research-agent` — stress-tests all approaches comparatively in one spawn |
| Big | 1 `codebase-research-agent` per approach (2-3 in parallel) — each independently challenges its assigned approach |

Spawn per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research, all in a single assistant response (parallel-spawn rule), OMIT `model=`, apply the `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration ladder. The §4.2.5 library-research agent — when it fires for this tier — joins this same-response batch: both feed the §4.3 gate and are mutually independent (critics read the codebase, the web agent reads the web), so they co-fire per Shape B of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md`; the orchestrator MAY draft the §4.3 approach render during the shared wait, splicing each approach's `Stress-test:` verdict and any library recommendation in on return. Both are drained before §4.3. Per-spawn slots:

- `RESEARCH_QUESTION`: "Stress-test approach '<name>' against this codebase: find blockers, hidden coupling, convention conflicts, and prior rejected attempts that would make it fail or cost more than its stated effort estimate. Work to disprove the approach's feasibility, not to confirm it — the approach text reads plausible because its author believed it, and plausibility is not evidence. A no-risks verdict is credible only when you list the surfaces you checked and found clean." (Medium tier: enumerate all approaches in one question.)
- `DELIVERABLE_SHAPE`: `"table of [{approach, risk, evidence file:line, severity: blocking|major|minor}], plus one 'Checked:' line per approach listing the files/surfaces examined — required even, and especially, when no risks were found"`
- `SCOPE_HINT`: path globs from the approach's touched surface (Phase 1 echo entries).
- `PRE_INLINED_CONTEXT`: the §4.1 approach list + relevant Phase 1 `query-learnings` entries — especially any prior `user_rejected_suggestion` for this topic-area, which is itself a blocking signal.
- `OUTPUT_PATH`: `<task-dir>/.research-critique-<approach-slug>.md` (Big) or `<task-dir>/.research-critique.md` (Medium) — T1 ephemeral, within the documented `.research-<facet>.md` glob.
- `THOROUGHNESS`: `medium`.

After the batch returns, fold the critiques into the ranking — trust a verdict only as far as its evidence:

- **Verify before demoting.** A `blocking` verdict demotes only on verified evidence: read the cited `file:line` (one targeted Read) and confirm the quoted code grounds the risk. A `blocking` row with no `file:line` citation, or whose citation does not hold on read, downgrades to `major` with the note `evidence did not verify` — an unanchored blocker is a hypothesis, not a risk, and demoting the strongest approach on a hypothesis is the over-flagging failure this bar exists to stop.
- An approach carrying a verified `blocking` risk is never the `Recommended` option — demote it. If every approach carries a verified blocking risk, loop back to Phase 3 with a tighter scope question rather than recommend a non-viable plan.
- `major` / `minor` risks annotate an approach but do not bar recommendation.
- **A clean verdict needs a checked account.** A critique reporting no risks for an approach without its `Checked:` line is silence, not feasibility evidence — treat that approach as un-stress-tested (note "stress-test inconclusive" on it in the §4.3 chat message) rather than feasibility-confirmed.
- Each approach gains a one-line `Stress-test:` verdict (top risk + evidence file:line) carried into the §4.3 chat message (per the Gate presentation contract) and the §4.4 `## Considered Alternatives` body.

Append a `## Tool log` Echo entry per spawn (same shape as §1.3). Fail-open: if a critic spawn fails, log a `## Errors` entry and proceed to §4.3 on the model's own ranking, noting "stress-test unavailable" in the §4.3 chat message on every approach whose critique did not return — on the Big tier (one critic per approach) that is only the failed critic's assigned approach; on the Medium tier the single comparative critic covers all approaches, so its failure marks all of them. The weighing is advisory, not a hard gate.

### 4.2.5 Build-vs-buy library reuse (per approach)

**When it fires.** During approach generation, for feature components an approach would otherwise hand-write, when the effort tier (detected in Phase 1.2) is Small / Medium / Big. Skip Trivial — a one-liner never justifies a new dependency, and the supply-chain surface a dependency adds outweighs the saved lines. Skip silently when the project has no package manifest — there is nothing to buy from, and surfacing the audit on a manifest-less repo is noise.

**What it does.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/library-reuse-audit.md` MODE: plan:

1. Detect the ecosystem from the project snapshot / lockfile glob (language-agnostic — read the manifest nearest the code under audit; never assume npm).
2. Spawn ONE top-level `general-purpose` web-research agent (it needs `WebSearch` + `WebFetch`, which the read-only codebase agents lack) to find and rank 2-3 candidate libraries; OMIT `model=`; apply the `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration ladder. Co-fire this spawn in the SAME assistant response as the §4.2 stress-test batch rather than after it (Shape B of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md`) — co-fire only whichever of the two actually fires for the current tier (§4.2 skips Trivial/Small; §4.2.5 skips Trivial and manifest-less repos), and if only one fires it runs as today. Orchestrate at the top level — subagents cannot spawn sub-agents.
3. Run the existence-verify + disqualifier funnel (helper Step 3 Stage 0 + Step 4) on each candidate.
4. Fold the build-vs-buy choice into the approach trade-offs — e.g. "Approach A: adopt `<library>` with links + signals; Approach B: hand-write it" — or, when one approach dominates, note the recommended library inline in that approach's §4.3 digest with its registry + repository links as the evidence cite.

Carry the recommendation into the spec's Approach and Steps prose (Phase 5 / Phase 6) so /geniro:implement inherits it. Do NOT fire a separate adoption AUQ here — the §4.3 approach-approval gate is the confirmation that a library belongs in the plan; the binding install confirmation is deferred to /geniro:implement. Never write an unverified package name into the spec — existence-verify first (the anti-slopsquatting floor: language models invent plausible package names that do not exist, and a fake name written into a spec becomes an install target downstream). Fail-open: on a research or registry error, log a `## Errors` entry and proceed to §4.3 with the hand-write approach, noting "library audit unavailable" on the affected component.

### 4.3 Present approaches — message-first

Apply the Gate presentation contract.

**Mirror the pending decision onto the artifact first.** When `artifact_mode: true` and the page is not recorded unavailable, refresh the Current decision panel before the approach AUQ: `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Before-gate update with PHASE: approach and the pending decision with full per-option detail + the supporting deep-dive content now available` — the candidate approaches' full write-ups, the stress-test evidence, and the data-flow diagram now available. The chat message below stays the primary render; the panel only mirrors it.

1. **Render the approaches to a chat message in the Visual rendering language** (Gate presentation contract): open with the progress tracker (`● Approach` current) and a one-sentence opener naming the decision. For each of the 2-3 approaches: name, a plain-English 1-2 sentence summary, an ASCII data-flow / architecture diagram (5-10 lines), `What changes:` (the key new/edited files), `Trade-off:` (gain vs give-up in plain words), and the approach's `Stress-test:` verdict line from §4.2 (top risk + evidence `file:line`). Lead with the Recommended approach. Where no usable verdict exists, render the note in the verdict line's place: "stress-test unavailable" on an approach whose §4.2 critique did not return, "stress-test inconclusive" on an approach whose no-risks critique lacked its `Checked:` account.

2. **Fire ONE lean AUQ.** Single-select; header "Approach"; one option per approach, `Recommended` first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` (§Recommended-label policy). Option `label` = approach name; `description` = 1-line summary + trade-off; `preview` empty or a one-line recap. The `Recommended` marker reflects the §4.2 stress-test ranking — an approach carrying a verified blocking feasibility risk is never Recommended.

Full literal example (chat message + lean AUQ: Service-layer fan-out vs in-process Promise.all) in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §3.

### 4.4 Persistence

User pick → append to `approvals[]` with category `approach_choice`. Other approaches captured to body section `## Considered Alternatives`, each carrying its §4.2 `Stress-test:` verdict line + evidence; an approach demoted for a verified blocking risk records `Why not recommended: <blocking risk + file:line>`.

**L2 emit on rejection signal:** After appending to `approvals[]`, source `${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh` and invoke:

```bash
emit_rejection_if_signal \
 "/geniro:plan" "<topic>" "approach_choice" \
 "<recommended approach label>" "<picked label>" "<recommended label>"
```

Where `<topic>` = $ARGUMENTS topic OR `global` if not inferable. Helper detects whether picked != recommended OR picked is explicit-cancel/no/skip and emits L2 `user_rejected_suggestion` only when signal fires. Acceptance (picked == recommended, no rejection keyword) is a no-op.

**Read side:** Phase 1 query-learnings on /geniro:plan entry already runs once. Extend its consumers to surface entries with `type=user_rejected_suggestion AND tags includes 'approach_choice'` matching the current topic — display as "User previously rejected <suggestion> on <ts>" so the orchestrator can re-rank or omit the rejected approach from AUQ.

Example body:

```markdown
## Considered Alternatives

### Inline Refactor (rejected)
Summary: ...
Trade-off: smaller surface change, but locks into existing module shape.
Stress-test: shared mutable cache in src/store/cache.ts:88 is read by 3 other modules — refactor would break them (severity: major).
Why rejected: violates new boundary established in Q3 2026 architecture review.
```

`## Considered Alternatives` is copied to spec.md body verbatim in Phase 6. /geniro:implement reads but not gates on it.

**Visual plan artifact — approach.** When `artifact_mode: true` and the page is not recorded unavailable, after the approach pick persists revise the page with the chosen approach + the considered alternatives: `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Update with PHASE: approach and the content just produced`. The call reads the saved `artifact_url` from state.md when present, so a resumed session revises the same page.

---

## Phase 5 — Section approval

State.md `phase: section-approve` during this phase.

### 5.1 Section template

Use the **fixed 11-section schema** detailed in `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md`:

1. Objective
2. Scope — Included
3. Scope — Excluded
4. Assumptions
5. Risks
6. Steps
7. Tools Required
8. Approval Points
9. Validation
10. Rollback-Recovery
11. Done Condition

Every spec.md has exactly the same 11 sections — schema-stable downstream consumers.

For Trivial tasks, sections 4 / 5 / 10 may have body content "none — task scope precludes" with brief rationale. Headers MUST exist; bodies MAY be "none with rationale".

### 5.2 Cluster approval — message-first, one decision per cluster

Group the 11-section schema into 3 dependency-ordered clusters, authored and gated in order:

| Cluster | Plain-English name | Sections |
|---|---|---|
| 1 | Goal & scope | 1 Objective, 2 Scope-Included, 3 Scope-Excluded |
| 2 | Approach & steps | 4 Assumptions, 5 Risks, 6 Steps, 7 Tools Required |
| 3 | Safety & done | 8 Approval Points, 9 Validation, 10 Rollback-Recovery, 11 Done Condition |

Author cluster N → render it → gate it → on approve, author cluster N+1. Cluster 1 (Goal & scope) is approved before cluster 2 is authored, so each cluster is grounded in the prior cluster's approved content; this keeps cross-section issues catchable while preserving dependency order. Do NOT author all 11 sections before the first gate.

Per cluster, apply the Gate presentation contract:

1. **Author** the cluster's sections inline using Phase 1 research + Phase 3 clarifying answers + Phase 4 picked approach + (when present) Phase 2 UI Preview as substrate. Then, when `artifact_mode: true` and the page is not recorded unavailable, mirror this cluster's approval decision onto the artifact before the gate: `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Before-gate update with PHASE: sections and the pending decision with full per-option detail + the supporting deep-dive content now available` — the cluster's section digests with their code examples and the steps-flow diagram now available. The chat render in step 2 stays primary; the panel only mirrors it.

2. **Render the cluster to a chat message in the Visual rendering language** (Gate presentation contract): the progress tracker (this cluster `●`, with `step N of 3`), a one-sentence opener stating what the cluster decides, the cluster-level visual (cluster 1: the in-scope/out-of-scope map; cluster 2: the steps flow diagram; cluster 3: the done-condition checklist), then one icon-headed sub-heading per section with its friendly digest block — lead sentence, `**Why:**` grounded in a Phase 1 finding `file:line` + the Phase 4 approach, `**How it gets built:**`, `**You'll see:**` — closing with the section's concrete example + visual per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-reference.md` §"Concrete example + visual per section type". A "none — task scope precludes" section is a one-line note here, not a rendered section.

3. **Fire ONE lean AUQ for the cluster** — `header` = a ≤12-char chip of the cluster name ("Goal & scope" / "Approach" / "Safety"); options:
   - **Approve all (N sections)** (Recommended) — accept every section in the cluster as rendered.
   - **Explain a section further** — opens the same section picker as Revise. For each picked section, render a deeper walkthrough message — the full evidence chain (additional `file:line` cites), an expanded or alternative diagram, edge-case behavior, and exactly what /geniro:implement will and will not touch — then re-fire this AUQ. A reading aid, not a decision (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Explain-further option): it writes no `approvals[]` entry, never changes section content, and does not count toward the 3 revision rounds.
   - **Revise specific sections** — opens a follow-up multi-select picker of the cluster's section names (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` multi-select schema). For each picked section, capture the revision (free-text), re-author it AND any same-cluster sections that depend on it, re-render the cluster message, then — when `artifact_mode: true` and the page is not recorded unavailable (`artifact_status` is not `unavailable`) — re-sync the page so it mirrors the re-rendered chat rather than the stale pre-revision plan: `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Before-gate update with PHASE: sections and the revised section content`. The call reads the saved `artifact_url` from state.md, so a resumed session revises the same page; refresh the panel — don't blank it — since the cluster gate is being re-presented. Then re-fire this AUQ. Max 3 revision rounds per cluster.
   - **Cancel planning** — terminal `aborted` + `## Termination reason: user-cancelled-at-phase-5`.

4. **Persist each section pick** to `approvals[]` with category `section_<id>` (e.g., `section_objective`, `section_scope_included`). On "Approve all", append one entry per section in the cluster (`picked: approve`); on "Revise", record the revised sections distinctly (`picked: revised: <summary>`); "Explain a section further" persists nothing — only Approve/Revise picks write entries. The cluster is a presentation grouping only — no `cluster_<id>` category; per-section persistence granularity is unchanged, so compaction re-author (§6.4) and the SessionStart restore hook need no change.

5. **On approve, author the next cluster** (step 1). After all 3 clusters approved → Phase 6. When `artifact_mode: true` and the page is not recorded unavailable, after a cluster's section picks persist revise the page with that cluster's approved sections: `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Update with PHASE: sections and the content just produced` — the call reads the saved `artifact_url` from state.md so a resumed session revises the same page.

**Tier-scaling.** For Trivial/Small tasks, sections 4 / 5 / 10 may be "none — task scope precludes" — noted in the cluster message, never a separate decision. At Trivial tier the clusters may collapse to 1-2 gates (the progress tracker then shows the collapsed stops); the default 3-cluster grouping applies to Medium/Big.

Full chat-message template + lean-AUQ shape + the Revise picker in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §4.1.

### 5.3 Milestone-mode

Fires BEFORE Phase 6 entry when the canonical milestone-output condition in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` is met (the Big-tier milestone threshold). AUQ header "Milestone slicing" with options "Slice into milestones" (Recommended for Big) and "Keep as a single spec". On slice pick, follow-up AUQ proposes 3-7 milestone names; Phase 6 emits sibling `milestone-N.md` files alongside spec.md. Persist to `approvals[]` with category `milestone_slice`. Handoff (Phase 9) then prints `/geniro:implement .geniro/planning/<slug>/milestone-1.md`. Full AUQ shape + follow-up procedure in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §4.2. Milestone-mode fires only at Big tier; not Small/Medium/Trivial.

---

## Phase 6 — Write spec.md

State.md `phase: write-spec` during this phase.

### 6.1 Write contract

Path: `.geniro/planning/<task-slug>/spec.md`.

Content: schema (11 sections) + frontmatter with goal block + optional `workflow_refs[]` + body sections (`## Considered Alternatives` from Phase 4, optional `## Milestones` from Phase 5 milestone-mode, optional `## Problem & Evidence` from Phase 0.5 when `prd_mode: true`).

**`## Problem & Evidence` (PRD-mode only):** when `prd_mode: true`, copy state.md `## Problem Framing` (populated by Phase 0.5) into the spec's `## Problem & Evidence` body section per the layout in `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` § Problem & Evidence. The section's success metrics also seed section 1 (Objective) phrasing and section 11 (Done Condition). Omit the section entirely when `prd_mode` is unset — a normal spec carries only the standard sections, and the Phase 7 validator treats `## Problem & Evidence` as allowed-optional (never required).

**Frontmatter assembly — `workflow_refs[]`:** copy state.md `## Workflow Refs` block (populated by Phase 1.4) into spec.md frontmatter `workflow_refs:` field verbatim (YAML re-emission). Skip when state.md `## Workflow Refs` is empty / absent — `workflow_refs:` is then omitted from spec.md frontmatter entirely (the field is OPTIONAL per `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` §workflow_refs).

Set the schema version from what the copied `workflow_refs[]` actually carry:
- `m5-v3` when any copied entry carries a chain-enrichment field — `parent_ref.title`, `parent_ref.status`, `parent_ref.scope`, `siblings[]`, or `chain_fetched_at` (populated by Phase 1.4's chain assembly).
- `m5-v2` when `workflow_refs:` is present but carries no enrichment field (a plain tracker fetch with no chain).
- `m5-v1` / `m5-v2` both stay valid for pure inline-task /geniro:plan with no tracker linkage; downstream readers accept all three.

The Phase 7 validator shape-checks `workflow_refs` on m5-v2 OR m5-v3, so an m5-v1 spec carrying the field would escape validation — never emit m5-v1 when `workflow_refs:` is present.

Write spec.md (and state.md / each `milestone-N.md`) via `atomic_state_write` — source `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh`, then feed the full file content on stdin via a heredoc, the same helper used for every state.md write. The `enforce-state-helper` hook hard-blocks a direct `Edit`/`Write` to anything under `.geniro/planning/**` or `.geniro/state/**`, so the helper is the only working write path for these artifacts; the skill's frontmatter `allowed-tools` also omits `Edit`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write ".geniro/planning/<slug>/spec.md" <<'EOF'
---
<spec frontmatter>
---

<spec body — 11 sections>
EOF
```

After writing spec.md, append a `## Tool log` entry to state.md via `atomic_state_write`:

```yaml
- ts: 2026-05-17T11:08:00Z
 tool: atomic_state_write
 detail: ".geniro/planning/<slug>/spec.md"
 status: ok
 result_ref: "<bytes-count>"
```

**Visual plan artifact — spec.** When `artifact_mode: true` and the page is not recorded unavailable, after spec.md is written revise the page with the written plan (steps / validation / done conditions): `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Update with PHASE: spec and the content just produced`. The call reads the saved `artifact_url` from state.md when present, so a resumed session revises the same page.

### 6.2 NO auto-commit

`git commit` does NOT fire at Phase 6 exit — it is deferred to Phase 8 post-approval to avoid per-revision commits polluting git history. At Phase 6 exit, spec.md sits unstaged on disk; state.md `phase: validate` is written before Phase 7 entry.

### 6.3 Milestone-mode write fan-out

If milestone-mode was picked in Phase 5, Phase 6 writes the top-level spec.md AND every `milestone-N.md` in a single phase pass. Each `milestone-N.md` follows the same schema scoped to its slice.

### 6.4 Idempotent re-entry (compaction-safe)

If Phase 6 is re-entered after compaction, the model:
1. Reads state.md `approvals[]` — every `section_<id>` approval is present per Phase 5.
2. Re-authors spec.md content from the persisted approvals.
3. Re-writes spec.md (overwrite via `atomic_state_write`, since this is idempotent regeneration).
4. Re-appends a `## Tool log` entry with note `(re-entry — post-compaction regeneration)`.

---

## Phase 7 — Mechanical validator

State.md `phase: validate` during this phase.

### 7.1 Mechanical pass-through (not Opus self-prompt)

Phase 7 uses a **deterministic validator** — script-checkable rules executed orchestrator-side. No LLM round-trip per check.

### 7.2 Validator checks

See `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md` for the canonical check definitions. Each check returns `(check_id, status, finding_text, fix_hint)`. Run the full set in sequence.

### 7.3 Hard-fail handling

If any check fails:
1. Write findings to state.md `## Open Questions` body as a structured list (one bullet per failed check, with `fix_hint`).
2. Re-author the failing sections (orchestrator-side: model re-reads its own draft + validator findings + `fix_hint`s, and rewrites only the failing sections).
3. Re-run validator. **Max 3 auto-revision rounds.**
4. If round 3 still fails → fire `AskUserQuestion` with header "Spec checks not passing":
 - **Accept as-is** — proceed to Phase 8 with the failed checks documented in `## Open Questions`; user has final say.
 - **Re-revise** — kick a fresh round-1 cycle (rare; usually indicates schema misunderstanding).
 - **Abort** — terminal `aborted` + `## Termination reason: phase-7-validator-hard-fail`.

### 7.4 No transition to Phase 7.5 if validator hard-fails

The validator is a gate, not advisory. Phase 7.5 spec challenge and the Phase 8 user-approve MUST see a validator-clean spec.md (or one where hard-fails were explicitly accepted by the user via the §7.3 Accept-as-is option). Protects from the "user approves blind" failure mode. On a clean (or user-accepted) validator pass, transition `phase: spec-challenge` before Phase 7.5 entry.

---

## Phase 7.5 — Spec challenge

State.md `phase: spec-challenge` during this phase. Entered after the Phase 7 validator passes (or its hard-fails were user-accepted) and before the Phase 8 approval AUQ. At entry the spec is: full text on disk, validator-clean, uncommitted, `lifecycle: draft`.

Surface a one-line plain-English note before invoking: "Challenging the spec before you approve it...".

### 7.5.1 Invoke the challenge helper

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` with MODE: plan, SPEC_PATH: `<task-dir>/spec.md`, TASK_DIR: `<task-dir>`, EFFORT_TIER: `<the tier detected in Phase 1.2>`, DEEP: `<true when state.md deep-mode: true, else false>`.

The helper runs VERIFY (one verifier per `file:line`-cited claim) + generate-ALTERNATIVES + RED-TEAM + SYNTHESIZE, and returns a verdict: `keep` / `keep-with-modifications` / `re-plan`.

This fires on every plan regardless of effort tier — no Trivial skip. Cost stays bounded because the helper verifies only `file:line`-cited claims, of which a Trivial spec has few.

### 7.5.2 Verdict handling

- **keep** (clean) — surface a one-line advisory note (top challenge observation, if any) and transition `phase: user-approve` to Phase 8.
- **keep-with-modifications** — fold the helper's must-fixes into the spec by reusing the Phase 6 re-author → overwrite-via-`atomic_state_write` mechanism (§6.1; idempotent regeneration), append a `## Tool log` entry noting `(spec-challenge hardening)`, then re-run the Phase 7 validator. Mirror the Phase 7 max-3-revision-round loop: on a clean re-validation transition `phase: user-approve` to Phase 8; on a round-3 hard-fail follow the §7.3 accept-as-is / re-revise / abort AUQ. The human then approves a hardened spec.
- **re-plan** (the approach itself is refuted) — re-enter approach selection. Transition `phase: approaches` and re-run Phase 4 (re-run Phase 3 first if the refutation invalidates a clarifying answer), inlining the challenge's evidence into the §4.1 approach synthesis and the §4.2 stress-test `PRE_INLINED_CONTEXT`.

### 7.5.3 Advisory + fail-open

The spec challenge hardens the spec but never hard-blocks the Phase 8 human approval gate — same posture as the Phase 4.2 stress-test critic. If the helper or its agent spawns fail, log a `## Errors` entry ("spec-challenge unavailable") via `atomic_state_write` and transition `phase: user-approve` to Phase 8 on the un-challenged spec. The user still gets the final say at the Phase 8 AUQ.

---

## Phase 8 — User approval

State.md `phase: user-approve` during this phase.

### 8.1 Approval gate — closure

Phase 8 closes the loop with a final whole-spec approval. Apply the Gate presentation contract.

### 8.2 Shape — message-first

**Mirror the pending decision onto the artifact first.** When `artifact_mode: true` and the page is not recorded unavailable, refresh the Current decision panel before the final-approval AUQ: `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Before-gate update with PHASE: approval and the pending decision with full per-option detail + the supporting deep-dive content now available`. The chat summary below stays the primary render; the panel only mirrors it.

1. **Render the spec summary to a chat message in the Visual rendering language** (Gate presentation contract) — the progress tracker with every prior stop `✔` and `● Final approval`, a one-sentence opener restating the Objective in plain English, then an at-a-glance digest: scope summary (sections 2-3, reusing the in/out scope map), Approval Points (section 8 — where the user will be asked mid-build), Risk class auto-computed from section 5 + section 7 with a one-line why, Rollback (section 10, one line), Done Condition (section 11 rendered as a `☐` checklist — one box per observable signal), touched-file glob count, approval-expiration notice. Include the concrete examples already authored per section so the user reviews the real plan, not a label list.

2. **Fire ONE lean AUQ** — header "Approve spec"; `question` a one-line recap pointing at the message above; options: "Approve — commit the plan" (Recommended) / "Request changes — I'll describe" / "Abort — discard spec". Full literal message + AUQ template in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §5.

### 8.3 Revision-round escalation

Max 3 user-revision rounds (Phase 8 → re-enter affected sections in Phase 5 → re-validate in Phase 7 → re-fire Phase 8 AUQ). On round 3 exhaust, fire escalation AUQ with header "Revision limit reached":
- **Accept as-is** — final answer; route through §8.3.5 (the launch-config offer — this is a user-acceptance-to-commit path, same as an §8.2 Approve) and then run the §8.4 post-approve steps (commit, then Phase 9 prints the implement command).
- **Re-revise (kick fresh cycle)** — full round-1 restart; rare.
- **Abort** — terminal `aborted` + `## Termination reason: repeated-failure: phase-8 revision-limit-3`.

### 8.3.5 Launch config — pre-define implement settings (flag-driven or opt-in)

Fires after the user accepts the spec for commit — via the §8.2 "Approve" pick OR the §8.3 "Accept as-is" revision-wall terminal (never on Request changes / Abort / Re-revise). This step pre-answers the four `/geniro:implement` setup questions at plan time so `/implement` runs on its own — the full field semantics, enum values, and the doctrine boundary live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`; do not restate them here. The launch-config block is built one of two ways:

**Flag-driven (any launch modifier present in `$ARGUMENTS`).** When §0.1 recognized any launch modifier — a workspace modifier, a ship modifier, `freshness:<strategy>`, or `--deep` — build the `launch_config:` block directly from them and SKIP the interactive opt-in AUQ entirely; the flags ARE the opt-in. Map each specified modifier to its field (`new-branch` / `current-branch` / `worktree` / `here` → `workspace`, with `no-worktree` → `here`; `freshness:merge` / `freshness:rebase` / `freshness:skip` → `branch_freshness`; `--deep` → `deep_mode: true`; the ship modifier → `ship_mode` per its commit-no-push / draft-pr / ready-for-review / stop-after-review mapping). For each always-present field the user did NOT specify, fall back to that field's recommended default (`workspace: new-branch`, `deep_mode: false`, `branch_freshness: rebase`, `ship_mode: draft-pr`). Include `tracker_status` only when the spec has a linked tracker ticket (state.md `## Workflow Refs` non-empty), defaulting to `move-to-in-progress`; omit it otherwise. Hold the block for the §8.4 write and persist to `approvals[]` category `launch_config` via `atomic_state_write`, noting the source was `$ARGUMENTS` modifiers.

**Opt-in (no launch modifier present).** Fall back to the interactive opt-in:

1. **Ask the launch-config gate question** per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §5b — "Pre-define the implementation settings now, so /geniro:implement can run on its own?" The gate question never auto-defaults; an empty answer is re-asked.

2. **On "No"** — write no `launch_config:` block. The spec carries no pre-set; `/geniro:implement` asks its setup questions interactively as it does today. Proceed to §8.4 with the spec unchanged.

3. **On "Yes"** — fire the batched capture per §5b. The four always-present settings — `workspace` (new branch / current branch / worktree / here), `deep_mode` (Standard / Deep), `branch_freshness` (rebase / merge / skip), `ship_mode` (draft PR / PR ready for review / commit only don't push / stop after review) — fill ONE AUQ call (the 4-question-per-call cap). When the spec has a linked tracker ticket (state.md `## Workflow Refs` non-empty), a fifth setting — `tracker_status` (move to In Progress / leave unchanged), pre-answering `/geniro:implement`'s kickoff workflow-status question — chains into a SECOND AUQ call rather than displacing one of the four (chain past the cap, never drop a question). An empty answer on any single field falls back to that field's recommended default (`new-branch` / `false` / `rebase` / `draft-pr`, and `move-to-in-progress` when the tracker-status call fired) — the user already opted in by picking "Yes". Capture the values into a `launch_config:` block held for the §8.4 write; omit `tracker_status` when no tracker ticket was linked.

4. **Persist the pick** to `approvals[]` with category `launch_config` via `atomic_state_write` (the gate answer + the captured fields). On "No", record the declined gate answer; no block is held.

Doctrine: `launch_config` pre-answers SETUP only. It does NOT pre-authorize the new-dependency adoption gate, the runaway-scope / budget escalation, the handoff open-questions gate, or the spec-challenge-on-drift gate — each of those still fires on its own real trigger during `/geniro:implement` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"Doctrine boundary — setup only, never safety").

### 8.4 Approve → git commit

On user picks "Approve":

1. **Persist approval** to `approvals[]` with category `final_approve`.
2. **Flip spec.md `lifecycle: draft` → `lifecycle: approved`** in spec.md frontmatter via a fresh `atomic_state_write` that rewrites the whole spec (idempotent regeneration — the fields changing are `lifecycle:`, plus the `launch_config:` block + `geniro_schema_version: m5-v4` when §8.3.5 captured one; an in-place `Edit` is hard-blocked by the `enforce-state-helper` hook on `.geniro/planning/**`). Per design-doc lifecycle marker. **Fold the launch-config write into this SAME rewrite — zero extra writes:** when §8.3.5 produced a `launch_config:` block (whether from passed modifiers or the interactive opt-in), write it into the spec frontmatter and set `geniro_schema_version: m5-v4` (additive-optional per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"Version & backward-compat"; the m5-v3/m5-v2/m5-v1 chain-enrichment version rule of §6.1 still applies when no launch_config was captured). When §8.3.5 wrote no block (user picked "No" in the opt-in path), leave the spec's version and frontmatter unchanged — only `lifecycle:` flips.
3. **`git commit`** fires HERE (NOT in Phase 6):
 - `git add .geniro/planning/<slug>/spec.md` + every sibling `milestone-N.md`
 - `git commit -m "plan: <task-slug> — <one-line summary from section 1 Objective>"`
4. **Append to `non-resumable-actions[]`**
 ```yaml
 non-resumable-actions:
 - action: git-commit
 completed-at: $(date -u +%Y-%m-%dT%H:%M:%SZ)  # live clock read in the same write call — never model-supplied (atomic-state-write.md §Timestamp sourcing)
 commit-sha: <sha>
 files: [".geniro/planning/<slug>/spec.md"]
 ```
5. **Finalize the visual plan artifact.** When `artifact_mode: true` and the page is not recorded unavailable, revise the page to its approved state — status badge to approved, every tracker stop done: `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Update with PHASE: approval and the content just produced`. The call reads the saved `artifact_url` from state.md when present, so a resumed session finalizes the same page.
6. **Transition to Phase 9** (`phase: handoff`).

If commit fails (pre-commit hook denial, working-tree-dirty conflict, etc.), surface a structured error to user — do NOT proceed to Phase 9 with a stale state. Fall back to escalation with the error inlined.

### 8.5 L2 emit (conditional)

If Phase 4 had ≥2 distinct approaches AND the picked approach has a recorded trade-off rationale, emit a `decision` type entry to L2:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
echo '{
 "type":"decision",
 "scope":"<task-area>",
 "summary":"approach: <name>",
 "tags":[...],
 "trust":"verified",
 "ext":{"options":[...], "chosen":"<picked>", "reasoning":"<trade-off>"}
}' | emit_learning
```

Dedup + sanitization automatic. Skipped if Phase 4 had ≤1 approach or no trade-off rationale recorded. After a successful emit, echo `Recorded learning: <summary>` to the user, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract".

### 8.6 Suggest improvements (inline)

After the §8.5 emit, before Phase 9. The approved spec was already committed at §8.4, so this step is anchored after the Phase 8 approval and before the terminal Phase 9 print — a named, numbered step in the phase sequence, not a droppable trailer after the run's last user interaction. Source candidates inline — no agent, since you already hold the full approved spec and there is no fresh diff for an isolated read to find — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` §"Reflection-agent feed" (inline path) + §Routing table. Planning most often surfaces an architectural decision worth an ADR (route per §"ADR target — when to use it") or a convention clarified during approach selection worth a rule — discovery-derived per the bar's Evidence gate (the just-approved spec section plus the dedup grep is their evidence; no failure incident needed). Apply the §Candidate bar in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` to every draft (four gates + significance floor + cap; zero candidates is the common outcome), then route survivors per §Routing table; present them via §Presentation, hand instruction-scoped rules to `/geniro:instructions create`, and echo `Reviewed for improvements: <N> candidate(s)` even at zero — only the prompt is skipped when none. Declines log via `emit_rejection_if_signal` (scope `plan/<task-area>`, category `improvement_candidate`).

### 8.7 Custom post-approval steps

After §8.6, before Phase 9. Execute any user-authored post-approval steps from the L4 `plan.md` instruction file (`.geniro/instructions/plan.md`) loaded at Phase 1 §1.1. Per the `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Producer contract, a `## Additional Steps` subsection is anchored to a phase-enum boundary; the canonical post-approval anchor is `### After user-approve` (`user-approve` is the Phase 8 enum value, and the spec is committed at §8.4, so an `### After user-approve` subsection runs against an approved, committed spec). Run any subsection anchored to the end of `user-approve`, treating each bullet as an imperative to execute in order and honoring any `AskUserQuestion` the user's step prescribes.

This is the generic extension point for project-specific post-plan work — e.g. duplicating the approved plan into a spec-driven-development tool's change format (OpenSpec, etc.) using the project's own tooling. The plugin stays tool-agnostic: the procedure lives entirely in the project's instruction file, not in this loop. Without this step a loaded `### After user-approve` block has no execution anchor and is silently dropped once Phase 9 runs (the same failure mode `/geniro:implement`'s `### After ship` step prevents). Skip silently when no such subsection is loaded.

---

## Phase 9 — Handoff

State.md `phase: handoff` during this phase. Non-interactive — no AskUserQuestion fires here; the release decision was the Phase 8 "Approve", and the spec is already written (Phase 6) and committed (§8.4) before this phase entered.

### 9.1 Print next-step command

1. **Determine the target path.** For milestone-sliced specs (Phase 5 milestone-mode fired): `.geniro/planning/<slug>/milestone-1.md`. Otherwise: `.geniro/planning/<slug>/spec.md`.
2. **Print a short closing message** stating the plan is saved and committed, plus the next-step command — e.g.: `Your plan is saved and committed at .geniro/planning/<slug>/spec.md. To build it, run: /geniro:implement .geniro/planning/<slug>/spec.md`. Do NOT auto-invoke /geniro:implement — printing the command leaves invocation entirely to the user (user agency).

### 9.2 Clean up transient working files

Before the terminal `phase:` write, remove this run's scratch outputs from the planning task-dir — the per-facet `.research-<facet>.md`, the Phase 4 `.research-critique-*.md`, the `.spec-challenge-out.md`, and any `notes.md`. They were each read once during planning and are dead weight now; left behind, they resurface as recurring `/geniro:update` migration-walk warnings (and in a milestone-sliced plan `/geniro:implement` runs in a different task-dir, so it never reaches these — this cleanup is the only one that does). Deleting `/geniro:plan`'s own scratch is not a source mutation, so it stays within the read-only-on-source boundary.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/clean-task-transients.sh"
clean_task_transients ".geniro/planning/<slug>"
```

The helper preserves the durable artifacts (`spec.md`, `state.md`, `plan-*.md`, `milestone-*.md`) and is a no-op on files that were never written, so the same call is safe on the `aborted` terminal path. Run it before every terminal `phase:` write (`done` and `aborted`). After it runs, echo `Cleaned up transient working files from .geniro/planning/<slug>`.

### 9.3 Terminal transition

Write state.md `phase: done` via `atomic_state_write`. SessionStart recovery treats it as completed; a session crashing between the §8.4 transition and the print resumes at `phase: handoff` and re-runs the print + cleanup + done write.

---

## Definition of Done

`/geniro:plan` run is complete when:

- [ ] Phase 0 mode detection ran via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`; mode is IDEA or DESIGN_DOC; CODE_REFERENCE errored with corrective hint.
- [ ] state.md created at `.geniro/planning/<slug>/state.md` via `atomic_state_write` with frontmatter.
- [ ] Phase 0.5 problem-discovery interview ran ONLY when `--prd` was passed (`prd_mode: true`); six dimensions captured (problem / evidence / target user + job / hypothesis / success metrics / MoSCoW), each persisted to `approvals[]` (`prd_<dim>`) + synthesized to state.md `## Problem Framing`; skipped silently when `--prd` absent (no behavior change).
- [ ] Phase 1 loaded L4 + L3 + L2 (full tier); per-spawn Echo contract entries persisted to `## Tool log`.
- [ ] Phase 1.4 fetched `workflow_refs` via the matching MCP when `$ARGUMENTS` carried a tracker reference; payload persisted to state.md `## Workflow Refs`; the related-task chain was assembled via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md` (MODE: plan) with the tracker half (parent epic + siblings + `chain_fetched_at`) merged into `## Workflow Refs` and the "TASK CHAIN CONTEXT" block held for the research spawns; fail-open on MCP unavailable (skipped when no tracker reference).
- [ ] Phase 2 (Visual Companion) fired only when UI trigger matched; approved description persisted to state.md `## UI Preview` (skipped when no trigger).
- [ ] Phase 3 grilled the design as a depth-first decision-tree walk — one question at a time, each preceded by a message-first framing then a lean single-question `AskUserQuestion` with a recommended answer, regenerating the frontier after each answer (dropping any child an earlier answer made moot); no fixed cap, with a summarize-and-continue checkpoint AUQ every ~6 questions or at branch completion; each answer and each `grill_checkpoint` decision persisted to `approvals[]` before continuing; a termination summary held for Phase 4/5.
- [ ] Phase 4 rendered the 2-3 approaches to a chat message in the Visual rendering language (progress tracker + one-sentence opener + per-approach plain-English summary, ASCII diagram, what-changes file list, trade-off, stress-test verdict), then fired ONE lean AUQ with Recommended first; pick persisted to `approvals[]`; other approaches captured to `## Considered Alternatives`.
- [ ] Phase 4 ran the independent stress-test (Trivial: skipped; Medium: 1 critic; Big: 1 per approach) before ranking; a verified-blocking-risk approach was demoted from Recommended (or Phase 3 re-entered if all blocked); clean verdicts carried a `Checked:` account (else noted "stress-test inconclusive"); critique verdicts carried into the Phase 4 chat message + `## Considered Alternatives`; critic-spawn failures logged to `## Errors` (fail-open).
- [ ] Phase 4 considered build-vs-buy for non-trivial components (effort tier Small/Medium/Big — skipped Trivial and projects with no package manifest); any library folded into an approach was existence-verified per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/library-reuse-audit.md` (MODE: plan) and carried into the spec's Approach/Steps prose; no separate adoption AUQ fired (approach approval is the confirmation); research/registry errors failed open.
- [ ] Phase 5 grouped the fixed 11-section schema into 3 dependency-ordered clusters (Goal & scope / Approach & steps / Safety & done); authored cluster-by-cluster in order; rendered each cluster in the Visual rendering language (progress tracker + one-sentence opener + cluster visual + icon-headed friendly digest per section with concrete example), then gated it with ONE lean AUQ (Approve all / Explain a section further / Revise specific sections → picker / Cancel); Explain rounds wrote no approvals and did not count toward revision rounds; each section pick persisted to `approvals[]` category `section_<id>` (no `cluster_<id>` category introduced).
- [ ] Phase 5 milestone-mode AUQ fired if Big-task detected.
- [ ] Phase 6 wrote spec.md to `.geniro/planning/<slug>/spec.md` with all three design-doc markers; `workflow_refs[]` copied from state.md when present; `geniro_schema_version: m5-v3` when chain-enriched, else `m5-v2` when `workflow_refs[]` is present; `## Problem & Evidence` written from state.md `## Problem Framing` ONLY when `prd_mode: true` (omitted on normal specs).
- [ ] Phase 6 did NOT auto-commit.
- [ ] Phase 7 mechanical validator ran the full check set defined in `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md`; hard-fail surfaced findings to `## Open Questions`; max 3 auto-revision rounds respected.
- [ ] Phase 7.5 spec challenge ran on every plan (no Trivial skip) via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` (MODE: plan); `keep-with-modifications` folded must-fixes through the Phase 6 re-author + Phase 7 re-validate loop; `re-plan` re-entered Phase 4; helper/spawn failure logged to `## Errors` and proceeded to Phase 8 (advisory, fail-open).
- [ ] Phase 8 rendered the spec summary to a chat message in the Visual rendering language (all-prior-stops-✔ tracker + one-sentence opener + at-a-glance digest with done-condition checklist + concrete examples), then fired ONE lean AUQ; user picked one of 3 options; max 3 user-revision rounds respected.
- [ ] After Phase 8 Approve, the launch-config question was offered (skipped only when `$ARGUMENTS` modifiers already set workspace / depth / branch-handling / ship); on opt-in, the settings were captured to a `launch_config:` block (the four always-present settings, plus `tracker_status` when the spec had a linked tracker ticket — chained into a second AUQ call past the 4-question cap), persisted to `approvals[]` category `launch_config`, and the block + `geniro_schema_version: m5-v4` were written into the committed spec inside the §8.4 lifecycle-flip rewrite (no extra write); on decline / skip, no block was written and the version was unchanged.
- [ ] On Phase 8 Approve: `git commit` fired; `non-resumable-actions[]` updated; L2 `decision` emit conditional fired.
- [ ] Phase 8.7 executed any user-authored `### After user-approve` subsection loaded from `.geniro/instructions/plan.md` (the generic custom-post-approval anchor, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Producer contract); skipped silently when none was loaded.
- [ ] Phase 9 printed the milestone-aware `/geniro:implement <path>` command and wrote terminal `phase: done`.
- [ ] Phase 9 ran `clean_task_transients` against the planning task-dir before the terminal `phase:` write (`done` and `aborted`), removing this run's `.research-*.md` / `.spec-challenge-out.md` / `notes.md` scratch while preserving `spec.md` / `state.md` / `plan-*.md` / `milestone-*.md`.
- [ ] HARD-GATE released only on Phase 8 "Approve".
- [ ] Terminal state.md `phase: done` (or `aborted` with `## Termination reason` body line).

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This task is too simple to need a design" | "Simple" projects are where unexamined assumptions cause the most wasted work. Design can be short (Phase 5 Trivial = sections 4 / 5 / 10 with body "none with rationale"); presenting and approving is mandatory. HARD-GATE applies to EVERY task. |
| "I'll skip Phase 8 user re-review, my Phase 7 validator is enough" | Validator catches mechanical defects (placeholders / contradictions / scope creep); user catches intent defects (wrong abstraction / missing constraint). Different defect classes; both required. |
| "I'll cram the section digest into the AUQ `preview` so each option is self-contained" OR "the question can just say 'rendered above' — I'll skip authoring the message" | The `preview` side-box is a narrow monospace panel beside the option list — too small for a section digest, code examples, and diagrams; the user squints at it per option. Render the cluster as a SEPARATE chat message (full width, persists in scrollback) per the Gate presentation contract, in its own turn before the question — never same-turn with the AUQ. A question pointing at "the message above" when no such message was emitted gets a blind approval (observed: a deep run approved 8 sections + the final spec against five non-existent renders). Cramming content into `preview`, or referencing a render that does not exist, are the two failure modes message-first exists to fix. |
| "I'll author all 11 sections and fire one approval for the whole spec — fewer questions is strictly better" | Authoring everything before the first gate surfaces cross-section issues only after the user reads the whole plan — too late to cheaply correct. Author → render → gate ONE cluster, then the next; cluster 1 is approved before cluster 2 is authored, so each cluster builds on grounded prior content. One question per cluster (not per section, not per whole spec) is the chosen granularity — per-section `approvals[]` grain is preserved by the Revise-picker, so collapsing the questions loses no grain. |
| "I'll write the design doc with only the YAML frontmatter — that's enough" | Defense in depth requires all three markers (path + HTML comment + frontmatter). See `design-doc-detect.md` § Why defense in depth — each marker survives a different user action. |
| "Phase 4 — 4 or 5 approaches gives the user more choice" | More than 3 indicates Phase 3 didn't narrow scope; loop back to Phase 3 with a tighter scope-boundary question. |
| "My §4.1 approaches are well-reasoned — the §4.2 stress-test is redundant overhead" | The model that authored the approaches shares their blind spots; ranking them in the same context re-confirms its own bias rather than testing it. An independent codebase-grounded critic catches blockers the author cannot see from generation context alone — hidden coupling, a previously-rejected shape in L2, a convention conflict — which is the load-bearing reason `Recommended` is set from evidence, not self-confidence. It is tier-scaled (skipped on Trivial) so the cost lands only where a wrong approach is expensive. The critic's verdicts are themselves claims: a `blocking` call demotes only after its citation verifies on read, and a no-risks report without its checked-surfaces account is absence of investigation, not evidence of feasibility. |
| "Auto-commit at Phase 6 is convenient — drop a commit if Phase 8 rejects" | Rejection-induced commit-drop = forced `git reset` / `git revert`, polluting git history (every revision round would leave a commit). Phase 8 post-approve commit is a single commit per approved spec. |
| "I'll skip persisting Phase 3 clarifying answers — they're trivial" | Compaction mid-Phase-5 loses 5 AUQs of user input — that data-loss is exactly what `approvals[]` persistence prevents, so it is non-negotiable. |
| "I'll write a file outside `.geniro/planning/**` to save a step — /geniro:plan can touch source directly" | /geniro:plan never writes source. The frontmatter `allowed-tools` omits `Edit`, and the only intended write target is the planning task-dir (spec.md / state.md via `atomic_state_write`); writing source files turns planning into implementation and skips the HARD-GATE that exists to keep code changes behind the Phase 8 approval. |
| "Add a refine/edit mode that re-derives spec sections from an existing design doc — saves three phases of re-work" | Re-deriving sections from prose is structurally-lossy: downstream consumers parse a malformed spec.md. DESIGN_DOC mode offers Start-fresh-with-doc-as-context (or Cancel) precisely because starting fresh produces a schema-clean spec.md. |
| "Handoff should add a separate backlog-capture step for backlog discipline" | The committed spec.md on disk IS the backlog entry — no extra capture step or menu pick needed. Not running the printed `/geniro:implement` command is how a spec stays parked. |
| "Auto-default empty AUQ answer to the Recommended option" | Forbidden. Empty answer = upstream Claude Code bug; fall back to plain-text re-ask. Auto-default silently mutates user intent. |
| "Add a wall-time / token kill cap so runaway /geniro:plan sessions abort cleanly" | Hard kill-caps conflict with quality-first framing. /geniro:plan has bounded gates (Phase 3 grill checkpoint, Phase 7 3-round, Phase 8 3-round) that escalate to the user; do not abort. |
| "Bypass git pre-commit hooks with --no-verify when committing spec.md in Phase 8.4" | Hooks fail for a reason. Investigate root cause, not bypass. CLAUDE.md-level prohibition; honors it. |
