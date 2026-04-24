---
name: geniro:plan
description: "Create a detailed implementation plan for a feature or change. Spawns architect-agent, validates with skeptic-agent, saves to .geniro/planning/. Use before /geniro:implement or standalone. Do NOT use for trivial 1-2 file changes (/geniro:follow-up is better) or when an approved plan already exists."
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
argument-hint: "[what to plan — description, issue tracker reference, or 'review' to list existing plans]"
---

# Plan Skill

Create a detailed, file-level implementation plan before writing any code. The plan is the single source of truth for the entire implementation — all downstream agents reference it.

**When to use:**
- Before `/geniro:implement` — to get the plan approved first, then hand off
- Standalone — when you want to think through an approach before committing
- For planning larger initiatives that span multiple implementation cycles

**Output:** A `plan-<slug>.md` file saved to `.geniro/planning/` or `.geniro/planning/<branch-name>/` (when a task directory exists)

**No git operations:** Do NOT run `git add`, `git commit`, or `git push` — the orchestrating skill or user handles all git.

---

## Subagent Model Tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly.

**Skill-specific mapping:**

| Spawn | Tier | Rationale |
|---|---|---|
| `architect-agent` (Phase 2) | `opus` | Architecture design — always opus per canonical hard rule |
| `skeptic-agent` (validation phase) | `sonnet` | Read-only validation, reasoning over architect output |

---

## Input Detection

Parse `$ARGUMENTS` to detect intent:

| What you say | What happens |
|---|---|
| `/geniro:plan add OAuth login` | Full planning flow: discover → architect → validate → present |
| `/geniro:plan ENG-123` | Fetch issue from configured tracker (see workflow files), use as context, then plan |
| `/geniro:plan review` or `/geniro:plan list` | List existing plans in `.geniro/planning/` (flat and subdirectories) with status |
| `/geniro:plan update plan-0405-oauth.md` | Re-read and revise an existing plan |
| `/geniro:plan add OAuth — just do it` or `/geniro:plan ASAP: add rate limiter` | Auto mode: skip questions, pick recommended defaults |
| `/geniro:plan I think we should add OAuth` | Assumptions mode: propose plan with assumptions, let user correct |
| `/geniro:plan` (no arguments) | Use the `AskUserQuestion` tool to ask "What would you like to plan?" |

**Detection rules (checked in order):**
1. **Empty arguments** → ask what to plan via `AskUserQuestion`
2. **"review" or "list"** → list mode (skip to Plan Listing)
3. **"update" + filename** → revision mode (skip to Plan Revision)
4. **Issue tracker reference** — check `.geniro/workflow/*.md` for argument detection patterns (URLs, issue ID regexes). If a match is found, follow the workflow file's fetch instructions.
5. **Auto-mode signals** — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/auto-mode-signals.md` for the canonical phrase list (`"just do it"`, `"ASAP"`, `"no questions"`). `"auto"` and `"quick"` are NOT triggers. On match: skip interactive questions, pick recommended defaults.
6. **Assumptions-mode signals** — "I think", "maybe", "what if", "should we" → propose plan with assumptions, let user correct
7. **Plain description** → full interactive planning flow

---

## Plan Listing (`/geniro:plan review` or `/geniro:plan list`)

1. Glob for `.geniro/planning/plan-*.md` AND `.geniro/planning/*/plan-*.md` (finds plans in both flat and branch-subdirectory locations)
2. For each file, read the first 5 lines to extract: title, date, status
3. Present as a table:

```
Existing Plans:
| # | File | Title | Status | Date |
|---|------|-------|--------|------|
| 1 | plan-0405-add-oauth.md | Add OAuth Login | approved | 2026-04-05 |
| 2 | plan-0403-fix-pagination.md | Fix Pagination | completed | 2026-04-03 |
```

4. Use the `AskUserQuestion` tool (do NOT output options as plain text) to ask "Open a plan to view details, or start a new one?"
5. If `.geniro/planning/` doesn't exist or glob returns no results: "No plans found. Describe what you'd like to plan."

---

## Effort Scaling

Match planning depth to task complexity. **File count is a smell detector, not a complexity detector.** A 2-file migration + API contract change is Large. A 10-file rename propagation is Small.

### Step 1: Check for Hard Escalation Signals

These signals force **Large** classification regardless of file count:

| Signal | Why it's hard |
|--------|---------------|
| New entity, table, or migration | Irreversible schema change |
| New API endpoint or new page/route | Cross-stack coordination, auth decisions |
| Auth, permissions, or role changes | Unbounded blast radius |
| New module or subsystem | Architectural decision, no existing pattern to follow |
| 3+ modules coordinated | Distributed coordination complexity |
| Open-closed principle violation | Modifying behavior for all consumers; regression risk unbounded |
| New async/queue/background work | Runtime failure modes not caught by tests |
| New external integration or env vars | Cross-cutting infrastructure |
| Ambiguous intent | Multiple valid design approaches |

**If ANY hard signal is present → Large, skip to Step 3.**

### Step 2: Assess Complexity Dimensions

If no hard signals, score these dimensions:

| Dimension | Low (0) | Medium (1) | High (2) |
|-----------|---------|------------|----------|
| **Task type** | Bug fix, rename, config change | Extend existing feature with existing patterns | New feature, greenfield, no exemplar to follow |
| **Cross-boundary scope** | Single module/layer | 2 layers (e.g., service + route) | 3+ layers (DB + API + UI) or cross-stack |
| **Reversibility** | Pure source code changes | New files + test changes | Stateful side effects (migrations, API contracts, external calls) |
| **Edit scatter** | Changes concentrated in 1-2 locations | 3-5 distinct edit sites | 6+ sites across different modules |
| **Pattern availability** | Strong exemplar exists in codebase | Partial pattern, needs adaptation | No existing pattern, greenfield design |

**Score: sum of all dimensions (0-10)**
- **0-3 → Small**
- **4-6 → Medium**
- **7+ → Large**

### Step 3: Apply Planning Depth

| Size | Planning Depth |
|------|----------------|
| **Small** | **Lightweight plan:** Goal + Approach + Steps (no wave grouping, no test scenarios table). Skip skeptic validation, then route to Phase 4 Steps 1-4 (full plan print + approval ask) — the full-plan print is mandatory even for Small tasks. |
| **Medium** | **Standard plan:** Full structure from `plan-criteria.md`. Architect + skeptic validation. |
| **Large** | **Progressive delivery:** Phase 2a approach summary first → user confirmation → Phase 2b full plan + skeptic. |

For Large tasks, Phase 2 becomes two sub-phases:
1. **Phase 2a: Approach Proposal** — architect produces a brief proposal (not full plan): recommended approach + 1-2 alternatives with trade-offs + key decisions + risk assessment. Use the `AskUserQuestion` tool (do NOT output options as plain text) to present options: A) Looks good, proceed to full plan. B) I'd prefer a different approach. C) This is too big, help me split it.
2. **Phase 2b: Full Plan** — only after user confirms approach.

---

## Plan Revision (`/geniro:plan update <filename>`)

1. Read the existing plan file
2. Ask the user what needs to change
3. Spawn architect-agent with the existing plan + revision request
4. Architect produces updated plan (preserves structure, updates changed sections)
5. Run skeptic validation on the revised plan
6. Save updated plan (same file, updated timestamp in header)
7. Route to Phase 4 Steps 1-4 — print a short changelog of what changed in this revision FIRST (not a summary of the plan itself), then the full revised plan content verbatim, then the approval ask. A changelog alone is not enough; the user must see the complete revised plan.

---

## Full Planning Flow

### Phase 1: Discover Context

1. **Parse `$ARGUMENTS` and load workflow integrations.** Check for `.geniro/workflow/*.md` files — read each one to discover active integrations and their argument detection rules. Extract core description, detect issue tracker references per workflow rules, detect mode (auto/assumptions/interactive).
   - If issue tracker reference detected: follow the workflow file's fetch instructions (e.g., fetch via MCP, extract title/description/acceptance criteria)
   - If integration backend unavailable: log warning, proceed without (non-blocking)
   Also load custom instructions from `.geniro/instructions/global.md` and `.geniro/instructions/plan.md`. Read any found. Apply rules as constraints, additional steps at specified phases, and hard constraints throughout the pipeline.

2. **Check if user provided a detailed plan.** If `$ARGUMENTS` contains structured content with file paths, steps, or a clear implementation breakdown:
   - Skip architect generation entirely
   - Parse the user's plan into the standard plan format (read `plan-criteria.md` for structure)
   - Run skeptic validation on the parsed plan (skip for Small tasks)
   - Save to `.geniro/planning/plan-<slug>.md` (or into the task directory if one exists for the current branch)
   - Route to Phase 4 Steps 1-4 (full plan print + approval ask) — parsing a user-provided plan does NOT exempt this path from the Phase 4 full-plan print

3. **Load prior context.** Before scanning the codebase fresh, check for existing artifacts:
   - Existing plans in `.geniro/planning/plan-*.md` and `.geniro/planning/*/plan-*.md` — avoid re-planning what's already decided
   - Existing spec files in `.geniro/planning/*/spec.md` — prior discovery decisions
   - Learnings in `.geniro/knowledge/learnings.jsonl` — past gotchas relevant to this area
   - Prior session summaries in `.geniro/knowledge/sessions/` — related work
   - Use findings to inform discovery — don't re-discover what previous sessions already found

4. **Scan codebase** for relevant patterns, conventions, architecture:
   - Read `README.md`, `CONTRIBUTING.md` if they exist
   - Search for ADRs: `Glob("**/adr/**/*.md")` or `Glob("**/decisions/**/*.md")`
   - Find 2-3 exemplar files closest to the change area
   - Note: CLAUDE.md is auto-loaded — skip re-reading

5. **Determine effort level** — based on codebase scan and description, classify as Small/Medium/Large (see Effort Scaling above). This determines planning depth for Phase 2-3.

6. **Identify gray areas** — ambiguities that could lead to different implementations

7. **Resolve gray areas** (behavior depends on detected mode):
   - **Interactive (default):** Use `AskUserQuestion` to present structured questions (batch 3-5, recommend defaults):
     - Scope questions (backend-only? frontend? both?)
     - Key design decisions that affect the plan shape
     - Constraints (performance targets, backwards compat, etc.)
   - **Auto mode:** Pick the recommended default for every gray area. Log choices in the plan's Key Decisions section.
   - **Assumptions mode:** Produce a complete proposal with all decisions listed. Use the `AskUserQuestion` tool (do NOT output options as plain text) to present options: A) Looks good, proceed. B) I have corrections.
   - **Do NOT skip this step** — even with an issue tracker reference or in auto mode, gray areas must be resolved (either by asking or by choosing defaults)

### Phase 2: Generate Plan

1. **Read plan criteria:** Read `${CLAUDE_SKILL_DIR}/plan-criteria.md` for the plan structure and quality standards.

2. **Spawn architect-agent** via Agent tool with `subagent_type: "architect-agent"`, `model="opus"`:

   ```markdown
   ## Task: Create Implementation Plan

   Create a detailed implementation plan following the exact structure in the Plan Criteria below.
   Save the plan to: `.geniro/planning/plan-<slug>.md` (or into the task directory if one exists)

   ## Requirements
   [User's description + issue tracker context if any]

   ## User Decisions
   [Gray area answers from Phase 1]

   ## Codebase Context
   [Pre-inlined: relevant file contents, exemplar files, conventions discovered]

   ## Plan Criteria
   [Pre-inline the FULL contents of `${CLAUDE_SKILL_DIR}/plan-criteria.md`]

   ## Instructions
   - Follow the plan structure EXACTLY as specified in the criteria
   - Generate a unique filename using the slug rules from the criteria
   - Write the plan file to `.geniro/planning/` (or into the task directory if one exists for the current branch)
   - Ensure every step has exact file paths, action verbs, and verify criteria
   - The plan must be "decision-complete" — leave zero decisions to the implementer
   ```

3. **Read the generated plan** — verify the architect actually wrote it to `.geniro/planning/`

### Phase 3: Validate Plan

**Skip for Small tasks** — lightweight plans don't need adversarial validation. Go directly to Phase 4.

For Medium and Large tasks:

1. **Spawn skeptic-agent** via Agent tool with `subagent_type: "skeptic-agent"`, `model="sonnet"`:

   ```markdown
   ## Task: Validate Implementation Plan

   Review this implementation plan against the 8-dimension validation checklist from plan-criteria.md (pre-inlined below).

   ## Plan
   [Pre-inline the full plan file contents]

   ## Original Requirements
   [Pre-inline the user's description + decisions from Phase 1]

   ## Validation Standard + Mirage Detection
   [Pre-inline the "Validation Standard" section from `${CLAUDE_SKILL_DIR}/plan-criteria.md` — includes the 8 dimensions AND the mandatory mirage detection instructions]

   ## Output File
   Write your validation report to: `.geniro/planning/validation-report.md`
   (or `<task-dir>/validation-report.md` if a task directory exists)

   You MUST write this file using the Write tool — do NOT just return the report as text.

   ## Report Contents
   - For each of the 8 dimensions: findings with evidence (file:line, grep/glob results, etc.), classified as BLOCKER or WARNING with confidence
   - Mirages found (hallucinated files/functions/packages) — always BLOCKER
   - Convention fit evidence: does the plan's architecture match existing repo patterns? Report over-engineering signals (enterprise patterns for simple repos, abstractions the codebase doesn't use, DI when repo uses simple functions) with confidence
   - Do NOT emit an overall PASS / NEEDS REVISION / ISSUES_FOUND verdict — the orchestrating skill synthesizes blockers and warnings and decides.
   ```

2. **Read the validation report** from the file the skeptic wrote. If the file doesn't exist (skeptic failed to write it), re-spawn the skeptic with explicit instruction to write the file and retry once; if it still fails, fall back to treating the plan as "needs revision" with the failure noted.

3. **Orchestrator synthesis — decide the disposition yourself from the report:**
   - If the report contains ANY BLOCKER (mirage, dropped requirement, circular dependency, missing verification for explicit requirements): treat as NEEDS REVISION.
   - If only WARNINGS: proceed to Phase 4, surface the warnings to the user in Phase 4 Step 3.
   - If zero blockers and zero warnings: proceed to Phase 4 as PASS.

4. **If NEEDS REVISION:** Route feedback back to architect-agent with the specific BLOCKERS. Architect revises the plan file. Re-run skeptic. Max 3 iterations. **If 3 iterations exhausted:** Use the `AskUserQuestion` tool (do NOT output options as plain text) to present the best plan + remaining blockers with options: A) Approve as-is with known issues noted. B) Abandon this approach, start fresh. C) I'll fix the plan manually.

5. **If PASS or WARNINGS-ONLY:** Proceed to Phase 4.

### Phase 4: Present Plan to User

1. **Read the plan file** from `.geniro/planning/`

2. **Present the full plan** — output the entire plan file content verbatim in an assistant message. Do NOT summarize, abbreviate, paraphrase, or replace it with a "see the file" reference. The plan text MUST appear in the transcript before the `AskUserQuestion` call — either in a preceding message, or as text content that precedes the tool call in the same assistant turn. Never lead with `AskUserQuestion` when the plan has not yet been printed. The user needs to see every step, every file path, and every verify criterion before approving.

3. **Add metadata:**
   - "Full plan saved to `.geniro/planning/<filename>`"
   - "Skeptic validation: [N blockers, M warnings] across 8 dimensions"
   - If any warnings from skeptic: list them

4. **Ask for approval** using the `AskUserQuestion` tool (do NOT output options as plain text):
   - A) **Approve this plan** — mark as approved, ready for `/geniro:implement`
   - B) **Adjust** — describe what to change (routes back to architect for revision)
   - C) **Too large — decompose into milestones** — hand off to `/geniro:decompose` which produces 3-7 independently shippable milestone files that `/geniro:implement` consumes one at a time
   - D) **Approve — ready for `/geniro:implement`** — mark as approved; user re-invokes `/geniro:implement` separately (skills cannot call skills)

5. **Route based on answer:**
   - **A:** Update plan status to `approved`, done
   - **B:** Collect feedback, revise plan (back to Phase 2 with revision context), re-present. Max 3 rounds.
   - **C:** Tell the user: "This plan is a good candidate for decomposition. Run `/geniro:decompose <path-to-this-plan>` — it will restage into 3-7 independently shippable milestones and hand off to `/geniro:implement milestone 1` afterwards." Skills cannot call skills — the user re-invokes. Do NOT attempt to restage the plan yourself.
   - **D:** Update plan status to `approved`, then tell the user: "Plan approved and saved. Run `/geniro:implement` — it will auto-detect this approved plan and skip architect generation."

### On approval, update the plan header:

Change `Status: draft` → `Status: approved`

---

## Integration with /geniro:implement and /geniro:decompose

When `/geniro:implement` is invoked, its Phase 2 pre-check detects approved plans from three sources: conversation context (plan mode), plan files on disk, and `$ARGUMENTS`. If an approved plan is found, the architect-agent is skipped and the plan goes directly to skeptic validation, then Phase 3 (Approval). See implement SKILL.md Phase 2 for the full detection and routing logic.

If a plan is too large to ship in one `/geniro:implement` run (score 9+ on the complexity scale, >15 steps, or any Big hard-escalation signal), hand off to `/geniro:decompose <plan-path>` — it produces per-milestone detail files that `/geniro:implement milestone <N>` consumes one at a time. See `${CLAUDE_PLUGIN_ROOT}/skills/decompose/SKILL.md` for the full decomposition flow.

---

## Definition of Done

Plan skill is complete when:
- [ ] Plan file written to `.geniro/planning/plan-<slug>.md`
- [ ] Skeptic validation passed including convention-fit check (or skipped for Small tasks with reason noted)
- [ ] User approved the plan (or chose to implement immediately)
- [ ] Plan status updated to `approved` in the file header

---

## Error Handling

| Error | Recovery |
|-------|----------|
| Architect produces vague plan (missing files, no verify criteria) | Return with specific gaps from plan-criteria.md checklist |
| Skeptic finds critical gaps after 3 iterations | Present best plan + remaining issues to user for decision |
| Skeptic finds mirages (hallucinated files/functions) | Return to architect with specific mirages, require grep verification |
| Plan has >15 steps | Recommend `/geniro:decompose <this-plan-path>` — a plan this size is a Big task that needs milestone decomposition, not a flat sub-plan split |
| Issue tracker integration unavailable | Log warning, proceed without issue context |
| `.geniro/planning/` doesn't exist | Create it |
| Plan file already exists with same slug | Append `-v2`, `-v3`, etc. |
| Empty $ARGUMENTS | Use `AskUserQuestion` to ask what to plan |

---

## Compliance — Do NOT Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "The change is too small for a full plan" | Use effort scaling to produce a lightweight plan — but still produce one. Plans encode traceability. |
| "I already know the approach, skip discovery" | Discovery catches gray areas and loads prior context. You will miss something. |
| "The user provided a clear description, no questions needed" | Gray areas always exist — even clear descriptions leave scope, testing, and rollback decisions open. |
| "Skeptic validation is overkill for this" | The skeptic catches hallucinated files and dropped requirements before they waste implementation time. Skip only for Small tasks. |
| "The user seems impatient, skip straight to plan" | A bad plan costs more time than the 30 seconds saved by skipping questions. |
| "I can merge the plan into conversation instead of writing a file" | Plans must be files — conversation memory is lost on compaction. All downstream agents reference the file. |
| "The plan is already saved, I'll skip printing it and just ask for approval" | The user needs to see the plan to approve it. A saved file is not the same as a visible transcript — the approval is blind without the full content in the message immediately before the `AskUserQuestion`. Phase 4 Step 2 full-plan print is mandatory for every path (Small, Medium, Large, user-provided, revision). |
| "I'll just link to the saved plan file and ask for approval" | A file path is not the plan content. The approval ask must follow a message containing the complete plan text. If the plan is too long to print comfortably, that is a decomposition signal — offer `/geniro:decompose`, do not truncate the print. |
