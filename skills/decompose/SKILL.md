---
name: geniro:decompose
description: "Decompose a Big/complex task into 3-7 independently shippable milestones. Produces a master plan plus per-milestone detail files that /geniro:implement can consume one at a time via `/geniro:implement milestone <N>`. Use when /geniro:plan says 'too large' or when a single-shot /geniro:implement run would exceed context. Do NOT use for Small/Medium tasks (/geniro:plan is lighter) or when an approved non-staged plan already exists."
context: main
model: inherit
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - WebSearch
argument-hint: "[task description, existing plan path, or 'update <plan-file>' to re-decompose]"
---

# Decompose Skill

Turn a Big task into 3-7 **independently shippable milestones**, each self-contained enough that a fresh `/geniro:implement milestone <N>` invocation can execute it with no memory of the other milestones. Used when `/geniro:plan` says "too large", when a single-shot `/geniro:implement` would exhaust context, or when the user invokes `/geniro:decompose` directly on a complex initiative.

**Output:**
- The existing `.geniro/planning/<task-dir>/plan-<slug>.md` master plan, extended with a `## Milestones` section
- Per-milestone detail files at `.geniro/planning/<task-dir>/milestone-<N>-<slug>.md`
- `state.md` updated with a `Milestones:` roll-up field

**No git operations:** Do NOT run `git add`, `git commit`, or `git push` — this is a planning skill. The orchestrating skill or user handles all git.

---

## Subagent Model Tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly.

**Skill-specific mapping:**

| Spawn | Tier | Rationale |
|---|---|---|
| `architect-agent` (Phase 2 — master plan + milestone list) | `opus` | Architecture design — always opus per canonical hard rule |
| `architect-agent` (Phase 3 — per-milestone detail files, spawned in parallel) | `opus` | Same agent in decomposition mode, one spawn per milestone |
| `skeptic-agent` (Phase 4 — cross-milestone validation) | `sonnet` | Read-only validation over architect output |

---

## Input Detection

Parse `$ARGUMENTS` to detect intent:

| What you say | What happens |
|---|---|
| `/geniro:decompose add multi-tenant billing` | Full decomposition flow: discover → architect → detail files → validate → present |
| `/geniro:decompose .geniro/planning/foo/plan-bar.md` | Re-decompose mode: read the existing plan as the source of truth, then decompose |
| `/geniro:decompose update plan-0405-oauth.md` | Revision mode: re-stage an already-decomposed plan |
| `/geniro:decompose review` or `/geniro:decompose list` | List plans that have a `## Milestones` section, with milestone status roll-up |
| `/geniro:decompose ENG-123` | Fetch issue from configured tracker (see workflow files), use as context, then decompose |
| `/geniro:decompose just do it` / `ASAP` | Auto mode: skip questions, pick recommended defaults |
| `/geniro:decompose` (no arguments) | Use the `AskUserQuestion` tool (do NOT output options as plain text) to ask "What big task should I decompose?" |

**Detection rules (checked in order):**
1. **Empty arguments** → ask what to decompose via `AskUserQuestion`
2. **"review" or "list"** → list mode (skip to Decomposed Plan Listing)
3. **"update" + filename** → revision mode (skip to Milestone Revision)
4. **Path to existing `plan-*.md`** → re-decompose mode: read file, treat as master-plan source
5. **Issue tracker reference** — check `.geniro/workflow/*.md` for argument detection patterns. If a match is found, follow the workflow file's fetch instructions. If the integration backend is unavailable, log a warning and proceed without.
6. **Auto-mode signals** — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/auto-mode-signals.md` for the canonical phrase list (`"just do it"`, `"ASAP"`, `"no questions"`). `"auto"` and `"quick"` are NOT triggers. On match: skip interactive questions, pick recommended defaults.
7. **Assumptions-mode signals** — "I think", "maybe", "what if", "should we" → propose decomposition with assumptions, let user correct
8. **Plain description** → full interactive decomposition flow

---

## When NOT to use this skill

- Task classifies Small or Medium on the effort-scaling rubric (see `skills/plan/SKILL.md` §Effort Scaling). Use `/geniro:plan` — it's lighter and faster.
- An approved non-staged plan already exists and re-staging would waste work. Run `/geniro:implement` on the existing plan instead.
- The change is a bug fix. Use `/geniro:debug` for root cause and `/geniro:follow-up` for the patch.
- Fewer than 3 meaningful shippable slices exist. Decomposition below 3 milestones is a false signal — run `/geniro:plan`.

---

## Decomposed Plan Listing (`/geniro:decompose review` or `list`)

1. Glob for `.geniro/planning/plan-*.md` AND `.geniro/planning/*/plan-*.md`.
2. For each file, read the first 60 lines; keep only those containing a `## Milestones` heading.
3. Present a table:

```
Decomposed Plans:
| # | File | Title | Milestones | Status | Date |
|---|------|-------|------------|--------|------|
| 1 | foo/plan-0405-billing.md | Multi-Tenant Billing | 5 (2 completed, 1 in-progress, 2 pending) | approved | 2026-04-05 |
```

4. Use the `AskUserQuestion` tool (do NOT output options as plain text) to ask "Open a plan to view milestone details, re-decompose an existing plan, or start a new one?"
5. If glob returns nothing decomposed: "No decomposed plans found. Describe a big task to decompose, or pass a path to an existing plan."

---

## Full Decomposition Flow

### Phase 1: Discover Context

1. **Parse `$ARGUMENTS` and load workflow integrations** — same pattern as `skills/plan/SKILL.md` Phase 1 Step 1. Read `.geniro/workflow/*.md` integration files, detect issue-tracker refs, detect mode (auto/assumptions/interactive). Also load `.geniro/instructions/global.md` and `.geniro/instructions/decompose.md` (if present) and apply as constraints.

2. **Check for existing plan path in `$ARGUMENTS`.** If it's a path to an existing `plan-*.md`:
   - Read the plan file in full
   - Use it as the master-plan source of truth; skip architect's Phase 2a "approach proposal" step
   - Jump straight to Phase 2 "Generate milestone list" with the existing plan pre-inlined

3. **Load prior context.** Before scanning fresh:
   - Existing plans in `.geniro/planning/plan-*.md` and `.geniro/planning/*/plan-*.md`
   - Existing specs in `.geniro/planning/*/spec.md`
   - Learnings in `.geniro/knowledge/learnings.jsonl` — gotchas relevant to this area
   - Prior session summaries in `.geniro/knowledge/sessions/`
   - FEATURES.md if present — known backlog items that may overlap

4. **Scan codebase** for relevant patterns, conventions, architecture (`README.md`, `CONTRIBUTING.md`, ADRs under `**/adr/**/*.md` or `**/decisions/**/*.md`, 2-3 exemplar files near the change area). CLAUDE.md is auto-loaded — skip re-reading.

5. **Classify effort** using the rubric in `skills/plan/SKILL.md` §Effort Scaling (hard signals + 5-dimension complexity score). Decompose is valid ONLY when classification is **Big** (score 7+ OR any hard-escalation signal) AND one of:
   - A would-be single plan would have >15 steps
   - Complexity score is 9+
   - The user explicitly invoked `/geniro:decompose` after `/geniro:plan` said "too large"

   **If classification is Small or Medium**: STOP. Tell the user the computed score and recommend `/geniro:plan` instead. Do not proceed.

6. **Identify gray areas** — ambiguities in scope, boundaries, integration surfaces, sequencing constraints.

7. **Resolve gray areas** (behavior depends on detected mode):
   - **Interactive (default):** Use `AskUserQuestion` (do NOT output options as plain text) — batch 3-5 questions with recommended defaults. Focus on shipping-order constraints (what must ship first? what can be feature-flagged? is there a pilot surface?), scope boundaries, and acceptance bar per slice.
   - **Auto mode:** Pick the recommended default for every gray area. Log choices in the master plan's Key Decisions section.
   - **Assumptions mode:** Produce a complete proposal with all decisions listed. Use `AskUserQuestion` to present options: A) Looks good, proceed. B) I have corrections.

### Phase 2: Generate Master Plan + Milestone List

1. **Read criteria files:**
   - `${CLAUDE_SKILL_DIR}/decompose-criteria.md` — milestone schema and validation checklist
   - `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-criteria.md` — the underlying plan structure (master plan reuses it)

2. **Spawn architect-agent** via the Agent tool with `subagent_type: "architect-agent"`, `model="opus"`, in decomposition mode:

   ```markdown
   ## Task: Decompose into Milestones

   Operate in DECOMPOSITION mode per your Decomposition Mode section.

   Produce:
   (a) A master plan body that follows the structure in Plan Criteria (pre-inlined below), PLUS a new `## Milestones` section placed before `## Files Affected`.
   (b) The `## Milestones` section listing 3-7 milestones. Each row: number, name, one-sentence goal, upstream dependency milestone numbers (or "none"), wave number for parallelism, and a one-line rationale for why this slice is independently shippable.

   Write the master plan to: `.geniro/planning/<task-dir>/plan-<slug>.md` (or into the task directory if one exists for the current branch — see branch-naming rules).

   ## Requirements
   [User's description + issue tracker context if any]

   ## User Decisions
   [Gray area answers from Phase 1]

   ## Codebase Context
   [Pre-inlined: relevant file contents, exemplar files, conventions discovered]

   ## Plan Criteria (master plan structure)
   [Pre-inline the FULL contents of `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-criteria.md`]

   ## Decompose Criteria (milestone schema + sizing rules + anti-patterns)
   [Pre-inline the FULL contents of `${CLAUDE_SKILL_DIR}/decompose-criteria.md`]

   ## Instructions
   - Follow plan-criteria.md structure EXACTLY for the master plan body
   - The `## Milestones` section is MANDATORY and must satisfy every sizing rule and anti-pattern check in decompose-criteria.md
   - Vertical slices only — NO "backend milestone" / "frontend milestone" / "tests milestone"
   - 3 ≤ milestone count ≤ 7, hard cap
   - Write the master plan file yourself using the Write tool — do NOT return it as text only
   ```

3. **Post-write verification.** Glob the task dir for `plan-<slug>.md` to confirm architect wrote it. If missing, retry once with explicit "Write the file at <path>". If still missing, fall back to treating the architect's response as the plan body and Write it yourself.

4. **Read the master plan file** — confirm the `## Milestones` section is present and lists 3-7 entries.

### Phase 3: Generate Per-Milestone Detail Files

For each milestone listed in the master plan, produce a self-contained `milestone-<N>-<slug>.md` file at `.geniro/planning/<task-dir>/`.

**Spawn all milestone-detail agents in ONE response — all Agent() calls in the same assistant turn, NOT one per turn.** This is the canonical parallel-spawn pattern used elsewhere in the plugin.

Per-milestone Agent call with `subagent_type: "architect-agent"`, `model="opus"`:

```markdown
## Task: Generate Milestone Detail File

Operate in DECOMPOSITION mode per your Decomposition Mode section.

Write a self-contained milestone detail file at: `.geniro/planning/<task-dir>/milestone-<N>-<slug>.md`

The file must follow the Milestone File Schema in Decompose Criteria (pre-inlined below) — every section present, every field populated.

## Master Plan (pre-inlined)
[Full master plan content]

## This Milestone
Milestone number: <N>
Name: <name>
Goal (from master plan): <one-sentence goal>
Upstream dependencies: <milestone numbers or "none">
Wave: <wave number>

## Upstream Milestones (for dependency summary)
[Pre-inline the Goal + Files Affected + Acceptance Criteria of every upstream milestone so this milestone's "Upstream Dependencies" section can summarize what it depends on]

## Decompose Criteria (milestone schema + sizing rules)
[Pre-inline the FULL contents of `${CLAUDE_SKILL_DIR}/decompose-criteria.md`]

## Instructions
- Follow the Milestone File Schema EXACTLY
- Every step 1-5 files; milestone total 1-12 files
- Acceptance Criteria must be concrete and testable at milestone boundary
- Include `## Prior Milestones Context` as an EMPTY slot — pre-inlining happens at /geniro:implement time, not now
- Set Status header to `pending`
- Write the file yourself using the Write tool — do NOT return it as text only
```

**Post-write verification.** Glob for `milestone-*-*.md` in the task dir. Confirm one file per milestone. Retry any missing file once with explicit "Write the file at <path>".

### Phase 4: Validate (Skeptic)

1. **Spawn skeptic-agent** ONCE via the Agent tool with `subagent_type: "skeptic-agent"`, `model="sonnet"`:

   ```markdown
   ## Task: Validate Decomposed Plan

   Review this decomposed plan against the 8-dimension validation checklist from plan-criteria.md AND the 2 additional cross-milestone dimensions from decompose-criteria.md (pre-inlined below).

   ## Master Plan
   [Pre-inline the full master plan]

   ## Milestone Files
   [Pre-inline EVERY milestone file, in order]

   ## Original Requirements
   [User's description + Phase 1 decisions]

   ## Validation Standard (8 base dimensions + mirage detection)
   [Pre-inline "Validation Standard" from `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-criteria.md`]

   ## Cross-Milestone Validation Dimensions (D9, D10)
   [Pre-inline the "Cross-Milestone Validation Dimensions" section from `${CLAUDE_SKILL_DIR}/decompose-criteria.md`]

   ## Output File
   Write your validation report to: `<task-dir>/concerns.md`
   You MUST write this file using the Write tool — do NOT just return the report as text.

   ## Report Contents
   - For each dimension (D1-D10): findings with evidence (file:line, grep/glob results), classified BLOCKER or WARNING with confidence
   - Mirages (hallucinated files/functions/packages) — always BLOCKER
   - Cross-milestone coverage gaps (D9): any requirement in master Goal not covered by any milestone's Acceptance Criteria
   - Cross-milestone dependency-ordering violations (D10): forward references, circular deps, milestones in wrong wave
   - Do NOT emit an overall verdict — the orchestrating skill decides
   ```

2. **Read the validation report.** If the file is missing, re-spawn the skeptic with an explicit "Write the file" instruction; if it still fails, treat as "needs revision" with the failure noted.

3. **Orchestrator synthesis — decide disposition yourself:**
   - Any BLOCKER (mirage, dropped requirement across milestones, forward dep, non-serializable slice, shared primary file in same wave) → NEEDS REVISION.
   - WARNINGS only → proceed to Phase 5, surface warnings in the approval step.
   - Zero blockers and warnings → proceed to Phase 5 as PASS.

4. **If NEEDS REVISION:** Route feedback to architect-agent with specific blockers. Architect revises the master plan and/or affected milestone files. Re-run skeptic. **Max 3 revision rounds.** If exhausted, use `AskUserQuestion` (do NOT output options as plain text): A) Approve as-is with known issues noted. B) Abandon this approach, start fresh. C) I'll fix the plan manually.

### Phase 5: Present to User

1. **Read the master plan + all milestone files** from the task dir.

2. **Present the milestone summary** — do NOT paste every milestone file in full. For each milestone, output: number, name, goal, upstream deps, wave, file list (count), acceptance-criteria count, verify-command list. Link each milestone file path so the user can open it.

3. **Add metadata:**
   - "Master plan: `.geniro/planning/<task-dir>/plan-<slug>.md`"
   - "Milestones: N files at `.geniro/planning/<task-dir>/milestone-*.md`"
   - "Skeptic validation: [N blockers, M warnings] across 10 dimensions (D1-D8 base + D9-D10 cross-milestone)"
   - If warnings from skeptic: list them

4. **Ask for approval** using `AskUserQuestion` (do NOT output options as plain text):
   - A) **Approve all milestones** — ready for `/geniro:implement milestone 1`
   - B) **Adjust** — describe what to change (routes back to architect for revision)
   - C) **Merge milestones** — too granular, combine adjacent slices
   - D) **Split further** — a milestone is still too big; re-partition it

5. **Route based on answer:**
   - **A:** Write `state.md` with `Milestones: [1: pending, 2: pending, 3: pending, ...]`, update master plan header `Status: draft` → `Status: approved`, tell the user: "Decomposition approved. Run `/geniro:implement milestone 1` (or `/geniro:implement .geniro/planning/<task-dir>/milestone-1-<slug>.md` for the explicit path). After each milestone ships, `/geniro:implement continue` picks up the next pending milestone automatically."
   - **B:** Collect feedback, route to architect revision (Phase 2 or Phase 3 depending on scope), re-validate, re-present. Max 3 rounds.
   - **C:** Architect re-partitions: merge the adjacent milestones named by the user, regenerate affected milestone files, re-validate.
   - **D:** Architect re-partitions the named milestone into 2-3 slices (respecting the 7-milestone cap across the whole set), regenerate files, re-validate.

### On approval — state.md write

Write (or update) `.geniro/planning/<task-dir>/state.md` to include at minimum:

```
Plan: plan-<slug>.md
Milestones: [1: pending, 2: pending, 3: pending, ...]
DecomposedAt: 2026-04-22
```

If state.md already exists (e.g., from a prior `/geniro:plan` run), preserve existing fields and add/overwrite the `Milestones:` line. Keep it a single file per task-dir — the pre-compact hook at `hooks/pre-compact-state-save.sh` globs `.geniro/planning/*/state.md` and expects one file per dir.

---

## Milestone Revision (`/geniro:decompose update <plan-file>`)

1. Read the existing master plan and all `milestone-*-*.md` siblings.
2. Read `state.md` — identify already-completed milestones (preserve their Status).
3. Use `AskUserQuestion` (do NOT output options as plain text) to ask what needs to change (scope additions, re-partition, add/remove milestones).
4. Spawn architect-agent (`model="opus"`, decomposition mode) with the existing master plan + milestone files + revision request pre-inlined. Architect revises the master plan and affected milestone files in place; completed milestones are NEVER modified.
5. Re-run skeptic validation (Phase 4).
6. Present diff summary to user: which milestones changed, which stayed the same.
7. Save updated files (same paths, updated timestamps in headers). Update state.md `Milestones:` roll-up if milestone count changed.

---

## Integration with /geniro:implement

- **Milestone reference detection.** `/geniro:implement` Phase 2 pre-check detects milestone references via `$ARGUMENTS`: `milestone N` (N = 1-7), a path to `.../milestone-<N>-*.md`, or `continue` (reads state.md `Milestones:` and picks the first non-completed one).
- **Execution contract.** Each `/geniro:implement milestone <N>` run is fresh — no conversation memory from decomposition. The milestone file must be self-contained. `/geniro:implement` pre-inlines the `## Prior Milestones Context` slot from the prior milestones' `## Implementation Notes (Milestone K)` appendices on the master plan file.
- **Post-milestone appendix.** When a milestone ships, `/geniro:implement` Phase 7 appends `## Implementation Notes (Milestone N)` to the master plan file — short section: what shipped, any deviations from the milestone file, open follow-ups. The next milestone's run pre-reads it.
- **Status roll-up.** `/geniro:implement` updates the milestone file's Status header (`pending` → `in-progress` → `completed` or `blocked`), the master plan's `## Milestones` table row, and the state.md `Milestones:` line. Decompose establishes the format; implement owns the writes.
- **Completion.** After the last milestone ships and all statuses are `completed`, `/geniro:implement` marks the master plan `Status: completed`.

---

## Anti-Rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This task is only Medium, I'll decompose anyway — more structure never hurts" | Decompose is for Big tasks only (score 7+ with hard signal OR score 9+ OR >15 steps). Re-classify and use `/geniro:plan`. Over-decomposing adds orchestration cost with no benefit. |
| "I'll skip Phase 3 and let `/geniro:implement` decompose per-milestone later" | Pre-generating milestone files is the whole point. `/geniro:implement milestone N` assumes the file already exists and is self-contained. Without Phase 3, the fresh-subagent-per-milestone discipline breaks. |
| "I'll make milestones horizontal — one for backend, one for frontend, one for tests" | Horizontal slices are not independently shippable (backend-only milestone has no user-visible change and no acceptance criterion). Vertical slices only — see decompose-criteria.md Anti-Patterns. |
| "I'll spawn the milestone-detail agents one at a time so I can validate each before the next" | Spawn all milestone-detail Agent() calls in ONE response — all Agent() calls in the same assistant turn, NOT one per turn. Validation happens once in Phase 4 across the whole set. |
| "The milestone files are short, I'll write them myself instead of spawning architect" | Orchestrator synthesizes — architect-agent authors plans. This is the hard no-orchestrator-edits rule. Opus-tier reasoning belongs in the agent spawn, not in orchestrator turn. |
| "5 milestones already — I'll add a 6th for 'misc polish'" | Each milestone must be independently shippable with its own Acceptance Criteria. Polish belongs inside its owning milestone, or is the explicit last milestone (Setup → Foundational → Features → Polish) with concrete acceptance criteria like "docs updated, feature flag flipped, telemetry dashboards live". |
| "Task has 2 meaningful slices — I'll decompose into 3 by splitting one slice" | <3 means the task isn't actually Big. Tell the user to use `/geniro:plan`. Forcing 3+ milestones creates non-serializable slices. |

---

## Definition of Done

Decompose skill is complete when:

- [ ] Master plan written to `.geniro/planning/<task-dir>/plan-<slug>.md` with a `## Milestones` section present
- [ ] 3-7 milestone files written to `.geniro/planning/<task-dir>/milestone-<N>-<slug>.md`, each self-contained (every field in the Milestone File Schema populated)
- [ ] Skeptic validation passed across D1-D10 (8 base + 2 cross-milestone dimensions), with zero BLOCKER findings
- [ ] `state.md` updated with `Milestones:` roll-up line, one file per task-dir
- [ ] Master plan `Status: approved`
- [ ] User approved the decomposition via `AskUserQuestion`
- [ ] No git operations performed

---

## Error Handling

| Error | Recovery |
|-------|----------|
| Task scores Small or Medium on effort scaling | Refuse to decompose. Report the computed score and recommend `/geniro:plan`. |
| Architect proposes <3 milestones | Return to architect: "The task is too small to decompose (<3 slices). Re-assess effort; if still Big, identify additional shippable slices." If architect holds at <3, fall back to `/geniro:plan`. |
| Architect proposes >7 milestones | Return to architect: "Exceeds the 7-milestone cap. Merge adjacent slices that share a user-facing outcome." |
| Adjacent same-wave milestones share a primary file | Return to architect: "Vertical-slice violation — milestones N and M share `<file>` in wave W. Re-partition to move one of them to a different wave or a different file boundary." |
| Skeptic finds cross-milestone coverage gap (requirement dropped between milestones, D9) | Route to architect with the specific requirement; architect adds it to the owning milestone's Acceptance Criteria or Steps. |
| Skeptic finds dependency-ordering violation (D10: milestone K references output of milestone K+N) | Route to architect with the forward reference; architect re-orders or moves the referenced work earlier. |
| Architect fails to write master plan file | Retry once with explicit "Write the file at <path>"; if still missing, orchestrator writes the architect's returned plan body via the Write tool. |
| Architect fails to write a milestone detail file | Retry just that one milestone via a fresh architect spawn; if still missing, orchestrator writes from returned text. |
| `.geniro/planning/<task-dir>/` doesn't exist | Create it (derive task-dir from branch name per `skills/_shared/branch-naming.md`). |
| Plan file already exists with a `## Milestones` section | Treat as revision mode — route to Milestone Revision instead of overwriting. |
| Empty `$ARGUMENTS` | Use `AskUserQuestion` (do NOT output options as plain text) to ask what to decompose. |

---

## Compliance — Do NOT Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "The user just wants a quick split, skip discovery" | Discovery catches gray areas in shipping order and pilot surface that define milestone boundaries. Skip it and you will produce a sequence the user rejects. |
| "Phase 2 and Phase 3 can be one agent call" | Phase 2 produces the milestone list; Phase 3 produces self-contained files. Collapsing them into one spawn produces shallow milestone files with no upstream-dependency summaries. Fresh-subagent-per-milestone is load-bearing. |
| "Skip skeptic — architect already thought about dependencies" | D9 (coverage) and D10 (ordering) catch exactly the errors architects make when generating 5+ milestones in one pass. Skipping is how requirements get silently dropped. |
| "I can put `## Milestones` in a separate file instead of the master plan" | The master plan is the single file that `/geniro:implement` appends `## Implementation Notes (Milestone N)` to. Splitting breaks the appendix contract and the pre-compact hook's one-file-per-dir assumption. |
| "User said 'just approve everything' — skip the approval step" | The approval step is where the user catches mis-partitioning. Skipping it is how non-serializable decompositions reach `/geniro:implement` and waste real code generation. |
