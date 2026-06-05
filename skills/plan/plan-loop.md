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
- Phase 3 — Clarifying questions
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

> Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until the Phase 8 user-approve AUQ has been answered "Approve". The gate is binding for Phases 0–8. The Phase 9 handoff is the only authorized release point.

---

## Gate presentation contract

Every gate that presents rich, multi-part content — Phase 0.5 problem-discovery, Phase 3 clarifying questions, Phase 4 approaches, Phase 5 section approval, Phase 8 final approval — follows a two-step shape: **render to chat first, then fire a lean question.**

1. **Render the content to a chat message FIRST.** Write the full detail to chat: a heading per item, the Decision → Why → How digest, concrete code examples, and an ASCII diagram wherever it aids comprehension (especially section 6 Steps and Phase 4 data-flow). This message is where the user reads and understands the plan — it has full width and persists in scrollback.

2. **Then fire a LEAN `AskUserQuestion`.** Options are short decision selectors (Approve / Revise / Cancel-style), each with a one-line `description`. The `preview` side-box is NOT the rendering surface — leave it empty, or use it for a one-line recap only.

Why this shape: `AskUserQuestion` renders `preview` as a narrow monospace panel beside a vertical option list, so a Decision/Why/How digest, code, and diagrams crammed there are unreadable — the failure mode this contract exists to prevent. Rendering to chat gives the content full width; the lean question then captures only the decision.

**One decision per logical unit.** Phase 5 fires ONE question per cluster (not one per section); Phase 4 fires ONE question for the approach choice; Phase 8 fires ONE question for the whole spec. Collapsing per-item questions into one-per-unit stops the gate from re-asking decisions the user already settled upstream (in clarify / approaches), which is the click-through fatigue this contract also prevents. Per-decision persistence granularity is unchanged — a unit-level approval still writes one `approvals[]` entry per item it covers (Phase 5 §5.2).

---

## Phase 0 — Mode detect

State.md `phase: mode-detect` during this phase. Light cost — a single design-doc-detect.md helper call.

### 0.1 $ARGUMENTS resolution

**`--prd` flag detection (opt-in).** If `$ARGUMENTS` contains the token `--prd`, note that the flag was passed and strip the token before passing the remaining text to mode detection. state.md does not exist yet at this point — it is created in §0.3 — so do NOT write frontmatter here; instead carry the flag forward and write `prd_mode: true` into the INITIAL state.md frontmatter at the §0.3 creation step. `prd_mode` turns on the Phase 0.5 problem-discovery interview and the spec's optional `## Problem & Evidence` body section. When `--prd` is absent, `prd_mode` stays unset and Phase 0.5 is skipped.

**`--deep` flag detection (opt-in).** Semantic-parse `$ARGUMENTS` for `--deep` / `deep` / `deep mode` the same way; strip the token before mode detection. Carry it forward and write `deep-mode: true` into the §0.3 initial frontmatter (false/omitted when absent), and persist the activation to `approvals[]` category `deep_mode_choice`. `deep-mode` deepens Phase 4 (judge-panel approach search + 3× feasibility critics) and Phase 7.5 (3× claim verification) per `${CLAUDE_PLUGIN_ROOT}/skills/plan/deep-mode-reference.md`; it is orthogonal to `--prd` (both may be passed). When absent, those phases run their standard single-pass paths.

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

### 0.3 Task-dir + state.md creation

After mode is resolved (IDEA or DESIGN_DOC):

1. **Resolve task slug.** Inputs: $ARGUMENTS topic OR basename(design-doc) sans extension. Output: kebab-case slug ≤40 chars.
2. **Task-dir:** `.geniro/planning/<task-slug>/`.
3. **state.md:** `.geniro/planning/<task-slug>/state.md`. Write via `atomic_state_write`. Full frontmatter + body template (frontmatter fields `tier`/`producer`/`branch`/`phase`/`status`/`non-resumable-actions`/`approvals`/`task_slug`/`mode`; plus `prd_mode: true` when the `--prd` flag was present in §0.1, omitted otherwise; plus `deep-mode: <true|false>` from the `--deep` flag in §0.1 (false when absent); body sections `# State: <topic>` / `## Inputs` / `## Tool log` / `## Errors` / `## Open Questions`) in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1.
4. **Transition.** Branch on the `--prd` flag from §0.1: when it was present, set `phase: problem-discovery` via `atomic_state_write` and proceed to Phase 0.5; otherwise set `phase: explore` and proceed to Phase 1. Phase 0.5 itself sets `phase: explore` on completion (§0.5.4), so a `--prd` run flows through problem-discovery then rejoins the normal loop at Phase 1.

### 0.4 Cancel handling

If state.md already created when user cancels (e.g., deep cancel via Other): write `phase: aborted` + `## Termination reason: user-cancelled-at-phase-0` via `atomic_state_write` before exit.

---

## Phase 0.5 — Problem discovery (opt-in, fires only on `--prd`)

State.md `phase: problem-discovery` during this phase. **Fires only when `prd_mode: true`** (set in Phase 0.1 from a `--prd` flag in `$ARGUMENTS`). When `prd_mode` is unset, skip this phase entirely — the loop transitions Phase 0 → Phase 1 unchanged.

This phase runs a problem-first discovery interview BEFORE explore and clarify, so the eventual spec is grounded in a validated problem rather than a presumed solution. It reuses the Phase 3 batched-AUQ pattern (independent questions batched into one call, ≤4 per call; chain a second call past the cap rather than drop a question — the 4-option-per-call tool limit applies here too).

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
- **L2:** `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --tag <inferred> --scope <topic-area> --limit 5`. Skipped if topic is too generic to infer tags.
- **Cross-layer resolution:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol if L4/L3/L2 disagree.

Loading all three layers ensures research agents have full context — prior decisions (L2), codebase map (L3), and user rules (L4) — preventing repeated rediscovery.

### 1.1b Branch freshness

On a fresh run (skip on compaction-resume), apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`. /geniro:plan does not create branches, but when the session sits on a feature branch behind the default branch, offer to update it before research spawns — so the spec is grounded in fresh code rather than a stale tree. Skipped silently when the branch is already current.

### 1.2 Effort-tier-scaled research spawns

Detect effort tier from $ARGUMENTS shape using `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`:

| Tier | Spawns |
|---|---|
| Trivial (single-file config tweak, typo fix, rename) | 1 agent OR 0 if obviously scope-bound |
| Small (localized change, 1-2 files) | 1-2 agents (existing-impl; integration-surface only if it spans a boundary) |
| Medium (feature addition touching 2-5 files) | 2 agents (existing-impl + integration-surface) |
| Big (subsystem-level change ≥10 files) | 3-4 agents (subsystem-A + subsystem-B + cross-cutting + conventions) |

Spawn `codebase-research-agent` for each primary Phase 1 facet per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research. Facet-specific slot values: `RESEARCH_QUESTION` = the facet's research goal; `DELIVERABLE_SHAPE` = `"table of [{file, lines, observation}] verified findings"`; `SCOPE_HINT` = the facet's path globs; `OUTPUT_PATH` = `<task-dir>/.research-<facet>.md`; `THOROUGHNESS` = `medium` (default) or `very thorough` for Big-tier subsystem facets.

All spawns in a single assistant response per the parallel-spawn rule. Per-spawn output schema: `[{file, lines, observation}]`; cap ~4000 chars (truncate with marker).

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
```

3. The fetched payload feeds Phase 1 research-agent prompts (existing behavior) AND becomes the canonical source for Phase 6 frontmatter copy. Skipped when `$ARGUMENTS` carries no tracker reference — pure inline-task /geniro:plan emits a spec.md without `workflow_refs[]`.

### 1.5 Transition to Phase 2

Model synthesizes findings into a brief inline summary held in context (no separate artifact). The summary feeds Phase 2 UI trigger detection, Phase 3 question generation, and Phase 5 section authoring. State.md `phase: visual-companion` written before Phase 2 entry (`phase: clarify` if Phase 2 trigger doesn't fire).

**Skip to Phase 4 if Trivial:** when effort tier is Trivial AND research returned 0-1 findings AND topic is a narrow text-edit, Phases 2 + 3 are skipped. Write a one-line note to state.md `## Open Questions`: "Phases 2-3 skipped — trivial task, no ambiguity surfaced".

---

## Phase 2 — Visual Companion (UI-conditional)

State.md `phase: visual-companion` during this phase. Fires only when a UI trigger matches.

### 2.1 Trigger detection

Fire Phase 2 if **either** condition holds:

- Phase 1 explore-agent surfaced any path matching a UI file — path matches `**/components/**`, `**/pages/**`, `**/app/**`, `**/views/**`, `**/ui/**`, OR extension is `.tsx` / `.jsx` / `.vue` / `.svelte` / `.css` / `.scss` / `.sass` / `.less` / `.styled.ts` / `.styled.tsx`, OR
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

## Phase 3 — Clarifying questions

State.md `phase: clarify` during this phase.

### 3.1 Question generation

Model identifies up to 5 highest-leverage ambiguities from:
- Phase 1 research findings ("found 3 auth flows — which one is the integration surface?")
- L2 query-learnings ("prior decision favored Approach X — does it apply here?")
- L4 code-style rules

Questions MUST be grounded in Phase 1 findings. Generic "what tech stack?" questions are forbidden — the model can answer those from L3 `_project.md`.

### 3.2 AUQ shape — message-first, batch independent, sequence dependent

Apply the Gate presentation contract. When an option's consequence needs more than its one-line `description` (a code anchor, config diff, or behavior trace), render those consequences to a chat message first — one short block per option per question — then fire the AUQ with short labels + one-line `description`s. When every option is self-explanatory in one line, the message step is unnecessary — fire the AUQ directly.

Batch independent clarifying questions into ONE `AskUserQuestion` call (up to 4 questions per call). Fire questions sequentially only when one question's answer changes another's options (a genuine dependency) — batching independent questions cuts wall-time and click-through. Each question uses `header` ≤12 chars, `question` 1-2 sentences ending in a question mark, `options[]` of 2-4 explicit choices, `multiSelect: false` unless explicitly multi-select. Include a "Skip — proceed with stated assumption" option as the last choice when applicable. The ≤5-total cap (§3.4) holds across calls; if more than 4 independent questions exist, chain a second call rather than dropping or merging any question. Full literal example with the chat message + batched AUQ in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2.

### 3.3 Persistence

Each answered question → append entry to state.md frontmatter `approvals[]` via `atomic_state_write`. A batched AUQ returns all its answers at once — append one `approvals[]` entry per answer before proceeding past the batch (or to the next sequential question). Entry shape (category `clarify_<dim>` / prompt / options / picked / at / asked_in_phase) in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2.

On compaction-resume, the SessionStart re-injector renders `approvals[]` and the model re-reads it to skip already-answered questions.

### 3.4 Cap exhaustion

If a 6th clarification arises, force consolidation OR proceed to Phase 4 with stated assumptions. The 5-question cap is a quality-first signal — more than 5 means Phase 1 underspecified OR the topic is too vague for a single /geniro:plan session.

---

## Phase 4 — Approaches

State.md `phase: approaches` during this phase.

**Deep-mode branch (`deep-mode: true`).** Do NOT run the single-pass §4.1 synthesis + tier-scaled §4.2 critics below. Instead run the judge-panel approach search (3-4 diverse-lens generators → dedup → rank) and the 3× feasibility critics with majority vote, both inside an internal `Workflow(...)`, per `${CLAUDE_PLUGIN_ROOT}/skills/plan/deep-mode-reference.md` §2-3. Fold the top 2-3 ranked candidates into the §4.3 chat message + AUQ exactly as standard mode does. Fail-safe to the single-pass path below if the workflow errors (deep-mode-reference §6). Everything below describes the standard single-pass path.

### 4.1 Approach generation

Model synthesizes Phase 1 explore + Phase 3 answers into 2-3 distinct approaches. Each approach:
- **Name** (3-5 word label)
- **Summary** (2-3 sentences)
- **Trade-off** (1 sentence: gain vs give-up)
- **Effort estimate** (Trivial / Medium / Big per effort-scaling.md)

### 4.2 Independent stress-test (adversarial weighing)

The model that generated the approaches in §4.1 also ranks them in the §4.3 AUQ — same context, same blind spots, so its `Recommended` pick just re-confirms its own bias. Before ranking, get an independent challenge grounded in the actual codebase, so the `Recommended` marker reflects feasibility evidence rather than the author's confidence.

Effort-tier-scaled (tier already detected in Phase 1.2 — the critic cost lands only where a wrong approach is expensive):

| Tier | Stress-test spawns |
|---|---|
| Trivial | Skipped — single narrow approach, no ranking risk |
| Small | Skipped — too narrow to warrant a critic; if Phase 4 produced ≥2 genuinely competing approaches, treat as Medium (1 comparative critic) |
| Medium | 1 `codebase-research-agent` — stress-tests all approaches comparatively in one spawn |
| Big | 1 `codebase-research-agent` per approach (2-3 in parallel) — each independently challenges its assigned approach |

Spawn per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research, all in a single assistant response (parallel-spawn rule), OMIT `model=`, apply the `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration ladder. Per-spawn slots:

- `RESEARCH_QUESTION`: "Stress-test approach '<name>' against this codebase: find blockers, hidden coupling, convention conflicts, and prior rejected attempts that would make it fail or cost more than its stated effort estimate." (Medium tier: enumerate all approaches in one question.)
- `DELIVERABLE_SHAPE`: `"table of [{approach, risk, evidence file:line, severity: blocking|major|minor}]"`
- `SCOPE_HINT`: path globs from the approach's touched surface (Phase 1 echo entries).
- `PRE_INLINED_CONTEXT`: the §4.1 approach list + relevant Phase 1 `query-learnings` entries — especially any prior `user_rejected_suggestion` for this topic-area, which is itself a blocking signal.
- `OUTPUT_PATH`: `<task-dir>/.research-critique-<approach-slug>.md` (Big) or `<task-dir>/.research-critique.md` (Medium) — T1 ephemeral, within the documented `.research-<facet>.md` glob.
- `THOROUGHNESS`: `medium`.

After the batch returns, fold the critiques into the ranking:

- An approach carrying a `blocking` risk is never the `Recommended` option — demote it. If every approach carries a blocking risk, loop back to Phase 3 with a tighter scope question rather than recommend a non-viable plan.
- `major` / `minor` risks annotate an approach but do not bar recommendation.
- Each approach gains a one-line `Stress-test:` verdict (top risk + evidence file:line) carried into the §4.3 chat message (per the Gate presentation contract) and the §4.4 `## Considered Alternatives` body.

Append a `## Tool log` Echo entry per spawn (same shape as §1.3). Fail-open: if a critic spawn fails, log a `## Errors` entry and proceed to §4.3 on the model's own ranking, noting "stress-test unavailable" on each approach in the §4.3 chat message — the weighing is advisory, not a hard gate.

### 4.3 Present approaches — message-first

Apply the Gate presentation contract.

1. **Render the approaches to a chat message.** For each of the 2-3 approaches: name, 2-3 sentence summary, an ASCII data-flow / architecture diagram (5-10 lines), the key code identifier (new class / function / file), the dominant trade-off, and the approach's `Stress-test:` verdict line from §4.2 (top risk + evidence `file:line`). Lead with the Recommended approach. When the §4.2 critic was unavailable, note "stress-test unavailable" on each approach.

2. **Fire ONE lean AUQ.** Single-select; header "Approach"; one option per approach, `Recommended` first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` (§Recommended-label policy). Option `label` = approach name; `description` = 1-line summary + trade-off; `preview` empty or a one-line recap. The `Recommended` marker reflects the §4.2 stress-test ranking — an approach carrying a blocking feasibility risk is never Recommended.

Full literal example (chat message + lean AUQ: Service-layer fan-out vs in-process Promise.all) in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §3.

### 4.4 Persistence

User pick → append to `approvals[]` with category `approach_choice`. Other approaches captured to body section `## Considered Alternatives`, each carrying its §4.2 `Stress-test:` verdict line + evidence; an approach demoted for a blocking risk records `Why not recommended: <blocking risk + file:line>`.

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

1. **Author** the cluster's sections inline using Phase 1 research + Phase 3 clarifying answers + Phase 4 picked approach + (when present) Phase 2 UI Preview as substrate.

2. **Render the cluster to a chat message.** One sub-heading per section; under each, the Decision → Why (grounded in a Phase 1 finding `file:line` + the Phase 4 approach) → How (how /geniro:implement realizes it) digest, the section's concrete example (per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-reference.md` §"Concrete-example per section type"), and an ASCII diagram where it aids comprehension (especially section 6 Steps). A "none — task scope precludes" section is a one-line note here, not a rendered section.

3. **Fire ONE lean AUQ for the cluster** — `header` = a ≤12-char chip of the cluster name ("Goal & scope" / "Approach" / "Safety"); options:
   - **Approve all (N sections)** (Recommended) — accept every section in the cluster as rendered.
   - **Revise specific sections** — opens a follow-up multi-select picker of the cluster's section names (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` multi-select schema). For each picked section, capture the revision (free-text), re-author it AND any same-cluster sections that depend on it, re-render the cluster message, re-fire this AUQ. Max 3 revision rounds per cluster.
   - **Cancel planning** — terminal `aborted` + `## Termination reason: user-cancelled-at-phase-5`.

4. **Persist each section pick** to `approvals[]` with category `section_<id>` (e.g., `section_objective`, `section_scope_included`). On "Approve all", append one entry per section in the cluster (`picked: approve`); on "Revise", record the revised sections distinctly (`picked: revised: <summary>`). The cluster is a presentation grouping only — no `cluster_<id>` category; per-section persistence granularity is unchanged, so compaction re-author (§6.4) and the SessionStart restore hook need no change.

5. **On approve, author the next cluster** (step 1). After all 3 clusters approved → Phase 6.

**Tier-scaling.** For Trivial/Small tasks, sections 4 / 5 / 10 may be "none — task scope precludes" — noted in the cluster message, never a separate decision. At Trivial tier the clusters may collapse to 1-2 gates; the default 3-cluster grouping applies to Medium/Big.

Full chat-message template + lean-AUQ shape + the Revise picker in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §4.1.

### 5.3 Milestone-mode

Fires BEFORE Phase 6 entry when the canonical milestone-output condition in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` is met (the Big-tier milestone threshold). AUQ header "Milestone slicing" with options "Slice into milestones" (Recommended for Big) and "Keep as a single spec". On slice pick, follow-up AUQ proposes 3-7 milestone names; Phase 6 emits sibling `milestone-N.md` files alongside spec.md. Persist to `approvals[]` with category `milestone_slice`. Handoff (Phase 9) then offers `/geniro:implement .geniro/planning/<slug>/milestone-1.md`. Full AUQ shape + follow-up procedure in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §4.2. Milestone-mode fires only at Big tier; not Small/Medium/Trivial.

---

## Phase 6 — Write spec.md

State.md `phase: write-spec` during this phase.

### 6.1 Write contract

Path: `.geniro/planning/<task-slug>/spec.md`.

Content: schema (11 sections) + frontmatter with goal block + optional `workflow_refs[]` + body sections (`## Considered Alternatives` from Phase 4, optional `## Milestones` from Phase 5 milestone-mode, optional `## Problem & Evidence` from Phase 0.5 when `prd_mode: true`).

**`## Problem & Evidence` (PRD-mode only):** when `prd_mode: true`, copy state.md `## Problem Framing` (populated by Phase 0.5) into the spec's `## Problem & Evidence` body section per the layout in `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` § Problem & Evidence. The section's success metrics also seed section 1 (Objective) phrasing and section 11 (Done Condition). Omit the section entirely when `prd_mode` is unset — a normal spec carries only the standard sections, and the Phase 7 validator treats `## Problem & Evidence` as allowed-optional (never required).

**Frontmatter assembly — `workflow_refs[]`:** copy state.md `## Workflow Refs` block (populated by Phase 1.4) into spec.md frontmatter `workflow_refs:` field verbatim (YAML re-emission). Skip when state.md `## Workflow Refs` is empty / absent — `workflow_refs:` is then omitted from spec.md frontmatter entirely (the field is OPTIONAL per `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` §workflow_refs).

Set `geniro_schema_version: m5-v2` whenever `workflow_refs:` is present — the Phase 7 validator only shape-checks `workflow_refs` on m5-v2, so an m5-v1 spec carrying the field would escape validation. For pure inline-task /geniro:plan with no tracker linkage, `m5-v1` and `m5-v2` are both valid (downstream readers accept both).

Use the `Write` tool. `/geniro:plan` writes only spec/state artifacts under `.geniro/planning/**` and `.geniro/state/**`; the skill's frontmatter `allowed-tools` omits `Edit`, so the only write surface is `Write` to those planning paths.

After writing spec.md, append a `## Tool log` entry to state.md via `atomic_state_write`:

```yaml
- ts: 2026-05-17T11:08:00Z
 tool: Write
 detail: ".geniro/planning/<slug>/spec.md"
 status: ok
 result_ref: "<bytes-count>"
```

### 6.2 NO auto-commit

`git commit` does NOT fire at Phase 6 exit — it is deferred to Phase 8 post-approval to avoid per-revision commits polluting git history. At Phase 6 exit, spec.md sits unstaged on disk; state.md `phase: validate` is written before Phase 7 entry.

### 6.3 Milestone-mode write fan-out

If milestone-mode was picked in Phase 5, Phase 6 writes the top-level spec.md AND every `milestone-N.md` in a single phase pass. Each `milestone-N.md` follows the same schema scoped to its slice.

### 6.4 Idempotent re-entry (compaction-safe)

If Phase 6 is re-entered after compaction, the model:
1. Reads state.md `approvals[]` — every `section_<id>` approval is present per Phase 5.
2. Re-authors spec.md content from the persisted approvals.
3. Re-writes spec.md (overwrite — `Write`, not `Edit`, since this is idempotent regeneration).
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
- **keep-with-modifications** — fold the helper's must-fixes into the spec by reusing the Phase 6 re-author → overwrite-via-`Write` mechanism (§6.1; idempotent regeneration, `Write` not `Edit`), append a `## Tool log` entry noting `(spec-challenge hardening)`, then re-run the Phase 7 validator. Mirror the Phase 7 max-3-revision-round loop: on a clean re-validation transition `phase: user-approve` to Phase 8; on a round-3 hard-fail follow the §7.3 accept-as-is / re-revise / abort AUQ. The human then approves a hardened spec.
- **re-plan** (the approach itself is refuted) — re-enter approach selection. Transition `phase: approaches` and re-run Phase 4 (re-run Phase 3 first if the refutation invalidates a clarifying answer), inlining the challenge's evidence into the §4.1 approach synthesis and the §4.2 stress-test `PRE_INLINED_CONTEXT`.

### 7.5.3 Advisory + fail-open

The spec challenge hardens the spec but never hard-blocks the Phase 8 human approval gate — same posture as the Phase 4.2 stress-test critic. If the helper or its agent spawns fail, log a `## Errors` entry ("spec-challenge unavailable") via `atomic_state_write` and transition `phase: user-approve` to Phase 8 on the un-challenged spec. The user still gets the final say at the Phase 8 AUQ.

---

## Phase 8 — User approval

State.md `phase: user-approve` during this phase.

### 8.1 Approval gate — closure

Phase 8 closes the loop with a final whole-spec approval. Apply the Gate presentation contract.

### 8.2 Shape — message-first

1. **Render the spec summary to a chat message** — Objective (section 1) / Scope summary (sections 2-3) / Approval Points (section 8) / Risk class auto-computed from section 5 + section 7 / Rollback (section 10) / Done Condition (section 11) / touched-file glob count / approval-expiration notice. Include the concrete examples already authored per section so the user reviews the real plan, not a label list.

2. **Fire ONE lean AUQ** — header "Approve spec"; `question` a one-line recap pointing at the message above; options: "Approve — proceed to handoff" (Recommended) / "Request changes — I'll describe" / "Abort — discard spec". Full literal message + AUQ template in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §5.

### 8.3 Revision-round escalation

Max 3 user-revision rounds (Phase 8 → re-enter affected sections in Phase 5 → re-validate in Phase 7 → re-fire Phase 8 AUQ). On round 3 exhaust, fire escalation AUQ with header "Revision limit reached":
- **Accept as-is** — final answer; proceed to handoff.
- **Re-revise (kick fresh cycle)** — full round-1 restart; rare.
- **Abort** — terminal `aborted` + `## Termination reason: repeated-failure: phase-8 revision-limit-3`.

### 8.4 Approve → git commit

On user picks "Approve":

1. **Persist approval** to `approvals[]` with category `final_approve`.
2. **Flip spec.md `lifecycle: draft` → `lifecycle: approved`** in spec.md frontmatter via a fresh Write (idempotent regeneration — the only field changing is `lifecycle:`). Per design-doc lifecycle marker.
3. **`git commit`** fires HERE (NOT in Phase 6):
 - `git add .geniro/planning/<slug>/spec.md` + every sibling `milestone-N.md`
 - `git commit -m "plan: <task-slug> — <one-line summary from section 1 Objective>"`
4. **Append to `non-resumable-actions[]`**
 ```yaml
 non-resumable-actions:
 - action: git-commit
 completed-at: <ISO-8601 UTC>
 commit-sha: <sha>
 files: [".geniro/planning/<slug>/spec.md"]
 ```
5. **Transition to Phase 9** (`phase: handoff`).

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

---

## Phase 9 — Handoff

State.md `phase: handoff` during this phase.

### 9.1 Handoff menu

Fire `AskUserQuestion` with header "Next step":

- **/geniro:implement directly** (Recommended) — exit /geniro:plan, suggest the next command. For non-milestone specs: `/geniro:implement .geniro/planning/<slug>/spec.md`. For milestone specs: `/geniro:implement .geniro/planning/<slug>/milestone-1.md`.
- **Stop — keep spec for later** — terminal exit; spec sits on disk; user resumes when ready via `/geniro:implement <path>`.

Two options: `/geniro:implement directly` or `Stop — keep spec for later`. A design doc on disk IS the backlog entry.

### 9.2 Persistence

User pick → append to `approvals[]` with category `handoff`:

```yaml
- category: handoff
 prompt: "Next step?"
 options: ["/geniro:implement directly", "Stop — keep spec for later"]
 picked: "/geniro:implement directly"
 at: <ISO-8601 UTC>
 asked_in_phase: handoff
```

### 9.3 Terminal transition

- **/geniro:implement** picked → emit a one-line directive in chat (`Next: /geniro:implement .geniro/planning/<slug>/spec.md`); do NOT auto-invoke /geniro:implement (user agency). State.md `phase: done`.
- **Stop** picked → emit a one-line directive (`Spec saved. Resume via: /geniro:implement .geniro/planning/<slug>/spec.md`); state.md `phase: done`.

Both paths terminate in `done`. SessionStart recovery treats it as completed.

---

## Definition of Done

`/geniro:plan` run is complete when:

- [ ] Phase 0 mode detection ran via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`; mode is IDEA or DESIGN_DOC; CODE_REFERENCE errored with corrective hint.
- [ ] state.md created at `.geniro/planning/<slug>/state.md` via `atomic_state_write` with frontmatter.
- [ ] Phase 0.5 problem-discovery interview ran ONLY when `--prd` was passed (`prd_mode: true`); six dimensions captured (problem / evidence / target user + job / hypothesis / success metrics / MoSCoW), each persisted to `approvals[]` (`prd_<dim>`) + synthesized to state.md `## Problem Framing`; skipped silently when `--prd` absent (no behavior change).
- [ ] Phase 1 loaded L4 + L3 + L2 (full tier); per-spawn Echo contract entries persisted to `## Tool log`.
- [ ] Phase 1.4 fetched `workflow_refs` via the matching MCP when `$ARGUMENTS` carried a tracker reference; payload persisted to state.md `## Workflow Refs` (skipped when no tracker reference).
- [ ] Phase 2 (Visual Companion) fired only when UI trigger matched; approved description persisted to state.md `## UI Preview` (skipped when no trigger).
- [ ] Phase 3 rendered any non-trivial option consequences to a chat message, then batched independent clarifying questions into one `AskUserQuestion` call (≤4 per call, dependent questions fired sequentially), ≤5 questions total, with lean options; each answer persisted to `approvals[]`.
- [ ] Phase 4 rendered the 2-3 approaches to a chat message (ASCII diagram + code identifier + trade-off + stress-test verdict), then fired ONE lean AUQ with Recommended first; pick persisted to `approvals[]`; other approaches captured to `## Considered Alternatives`.
- [ ] Phase 4 ran the independent stress-test (Trivial: skipped; Medium: 1 critic; Big: 1 per approach) before ranking; a blocking-risk approach was demoted from Recommended (or Phase 3 re-entered if all blocked); critique verdicts carried into the Phase 4 chat message + `## Considered Alternatives`; critic-spawn failures logged to `## Errors` (fail-open).
- [ ] Phase 5 grouped the fixed 11-section schema into 3 dependency-ordered clusters (Goal & scope / Approach & steps / Safety & done); authored cluster-by-cluster in order; rendered each cluster to a chat message (per-section Decision → Why → How → optional diagram → example), then gated it with ONE lean AUQ (Approve all / Revise specific sections → picker / Cancel); each section pick persisted to `approvals[]` category `section_<id>` (no `cluster_<id>` category introduced).
- [ ] Phase 5 milestone-mode AUQ fired if Big-task detected.
- [ ] Phase 6 wrote spec.md to `.geniro/planning/<slug>/spec.md` with all three design-doc markers; `workflow_refs[]` copied from state.md when present; `geniro_schema_version: m5-v2` when `workflow_refs[]` is present; `## Problem & Evidence` written from state.md `## Problem Framing` ONLY when `prd_mode: true` (omitted on normal specs).
- [ ] Phase 6 did NOT auto-commit.
- [ ] Phase 7 mechanical validator ran the full check set defined in `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md`; hard-fail surfaced findings to `## Open Questions`; max 3 auto-revision rounds respected.
- [ ] Phase 7.5 spec challenge ran on every plan (no Trivial skip) via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` (MODE: plan); `keep-with-modifications` folded must-fixes through the Phase 6 re-author + Phase 7 re-validate loop; `re-plan` re-entered Phase 4; helper/spawn failure logged to `## Errors` and proceeded to Phase 8 (advisory, fail-open).
- [ ] Phase 8 rendered the spec summary to a chat message (fields + examples), then fired ONE lean AUQ; user picked one of 3 options; max 3 user-revision rounds respected.
- [ ] On Phase 8 Approve: `git commit` fired; `non-resumable-actions[]` updated; L2 `decision` emit conditional fired.
- [ ] Phase 9 handoff AUQ fired with 2 options; pick persisted to `approvals[]`.
- [ ] HARD-GATE released only on Phase 8 "Approve".
- [ ] Terminal state.md `phase: done` (or `aborted` with `## Termination reason` body line).

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This task is too simple to need a design" | "Simple" projects are where unexamined assumptions cause the most wasted work. Design can be short (Phase 5 Trivial = sections 4 / 5 / 10 with body "none with rationale"); presenting and approving is mandatory. HARD-GATE applies to EVERY task. |
| "I'll skip Phase 8 user re-review, my Phase 7 validator is enough" | Validator catches mechanical defects (placeholders / contradictions / scope creep); user catches intent defects (wrong abstraction / missing constraint). Different defect classes; both required. |
| "I'll cram the section ADR digest into the AUQ `preview` so each option is self-contained" | The `preview` side-box is a narrow monospace panel beside the option list — too small for a Decision/Why/How digest, code examples, and diagrams; the user squints at it per option. Render the cluster to a chat message (full width, persists in scrollback) per the Gate presentation contract, then keep the AUQ options lean. Cramming content into `preview` is the exact failure mode message-first exists to fix. |
| "I'll author all 11 sections and fire one approval for the whole spec — fewer questions is strictly better" | Authoring everything before the first gate surfaces cross-section issues only after the user reads the whole plan — too late to cheaply correct. Author → render → gate ONE cluster, then the next; cluster 1 is approved before cluster 2 is authored, so each cluster builds on grounded prior content. One question per cluster (not per section, not per whole spec) is the chosen granularity — per-section `approvals[]` grain is preserved by the Revise-picker, so collapsing the questions loses no grain. |
| "I'll write the design doc with only the YAML frontmatter — that's enough" | Defense in depth requires all three markers (path + HTML comment + frontmatter). See `design-doc-detect.md` § Why defense in depth — each marker survives a different user action. |
| "Phase 4 — 4 or 5 approaches gives the user more choice" | More than 3 indicates Phase 3 didn't narrow scope; loop back to Phase 3 with a tighter scope-boundary question. |
| "My §4.1 approaches are well-reasoned — the §4.2 stress-test is redundant overhead" | The model that authored the approaches shares their blind spots; ranking them in the same context re-confirms its own bias rather than testing it. An independent codebase-grounded critic catches blockers the author cannot see from generation context alone — hidden coupling, a previously-rejected shape in L2, a convention conflict — which is the load-bearing reason `Recommended` is set from evidence, not self-confidence. It is tier-scaled (skipped on Trivial) so the cost lands only where a wrong approach is expensive. |
| "Auto-commit at Phase 6 is convenient — drop a commit if Phase 8 rejects" | Rejection-induced commit-drop = forced `git reset` / `git revert`, polluting git history (every revision round would leave a commit). Phase 8 post-approve commit is a single commit per approved spec. |
| "I'll skip persisting Phase 3 clarifying answers — they're trivial" | Compaction mid-Phase-5 loses 5 AUQs of user input — that data-loss is exactly what `approvals[]` persistence prevents, so it is non-negotiable. |
| "I'll `Write` outside `.geniro/planning/**` to save a step — /geniro:plan can touch source directly" | /geniro:plan never writes source. The frontmatter `allowed-tools` omits `Edit`, and the only intended `Write` target is the planning task-dir; writing source files turns planning into implementation and skips the HARD-GATE that exists to keep code changes behind the Phase 8 approval. |
| "Add a refine/edit mode that re-derives spec sections from an existing design doc — saves three phases of re-work" | Re-deriving sections from prose is structurally-lossy: downstream consumers parse a malformed spec.md. DESIGN_DOC mode offers Start-fresh-with-doc-as-context (or Cancel) precisely because starting fresh produces a schema-clean spec.md. |
| "Handoff menu should add a separate backlog-capture step for backlog discipline" | A backlog IS a spec.md saved on disk. No separate step needed — picking "Stop — keep spec for later" at Phase 9 leaves the committed spec on disk as the backlog entry. |
| "Auto-default empty AUQ answer to the Recommended option" | Forbidden. Empty answer = upstream Claude Code bug; fall back to plain-text re-ask. Auto-default silently mutates user intent. |
| "Add a wall-time / token kill cap so runaway /geniro:plan sessions abort cleanly" | Hard kill-caps conflict with quality-first framing. /geniro:plan has bounded gates (Phase 3 ≤5 questions, Phase 7 3-round, Phase 8 3-round) that escalate to the user; do not abort. |
| "Bypass git pre-commit hooks with --no-verify when committing spec.md in Phase 8.4" | Hooks fail for a reason. Investigate root cause, not bypass. CLAUDE.md-level prohibition; honors it. |
