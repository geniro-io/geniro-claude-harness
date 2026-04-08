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
argument-hint: "[what to plan — description, Linear issue ID, or 'review' to list existing plans]"
---

# Plan Skill

Create a detailed, file-level implementation plan before writing any code. The plan is the single source of truth for the entire implementation — all downstream agents reference it.

**When to use:**
- Before `/geniro:implement` — to get the plan approved first, then hand off
- Standalone — when you want to think through an approach before committing
- For planning larger initiatives that span multiple implementation cycles

**Output:** A `plan-<slug>.md` file saved to `.geniro/planning/` (flat when standalone) or `.geniro/planning/<branch-name>/` (when a task directory exists)

**No git operations:** Do NOT run `git add`, `git commit`, or `git push` — the orchestrating skill or user handles all git.

---

## Input Detection

Parse `$ARGUMENTS` to detect intent:

| What you say | What happens |
|---|---|
| `/geniro:plan add OAuth login` | Full planning flow: discover → architect → validate → present |
| `/geniro:plan ENG-123` | Fetch Linear issue, use as context, then plan |
| `/geniro:plan review` or `/geniro:plan list` | List existing plans in `.geniro/planning/` (flat and subdirectories) with status |
| `/geniro:plan update plan-0405-oauth.md` | Re-read and revise an existing plan |
| `/geniro:plan just plan it` or `ASAP` | Auto mode: skip questions, pick recommended defaults |
| `/geniro:plan I think we should add OAuth` | Assumptions mode: propose plan with assumptions, let user correct |
| `/geniro:plan` (no arguments) | Use the `AskUserQuestion` tool to ask "What would you like to plan?" |

**Detection rules (checked in order):**
1. **Empty arguments** → ask what to plan via `AskUserQuestion`
2. **"review" or "list"** → list mode (skip to Plan Listing)
3. **"update" + filename** → revision mode (skip to Plan Revision)
4. **Linear URL** — regex: `https://linear\.app/.+/issue/([A-Z]+-\d+)` → fetch issue
5. **Issue ID** — regex: `\b[A-Z]{2,}-\d+\b` → fetch from Linear MCP
6. **Auto-mode signals** — "just do it", "ASAP", "no questions", "auto", "quick" → skip interactive questions, pick recommended defaults
7. **Assumptions-mode signals** — "I think", "maybe", "what if", "should we" → propose plan with assumptions, let user correct
8. **Plain description** → full interactive planning flow

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
| **Small** | **Lightweight plan:** Goal + Approach + Steps (no wave grouping, no test scenarios table). Skip skeptic validation — present directly. |
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
6. Present diff summary to user
7. Save updated plan (same file, updated timestamp in header)

---

## Full Planning Flow

### Phase 1: Discover Context

1. **Parse `$ARGUMENTS`.** Extract core description, detect Linear reference, detect mode (auto/assumptions/interactive).
   - If Linear issue detected: fetch via MCP, extract title/description/acceptance criteria
   - If Linear MCP unavailable: log warning, proceed without

2. **Check if user provided a detailed plan.** If `$ARGUMENTS` contains structured content with file paths, steps, or a clear implementation breakdown:
   - Skip architect generation entirely
   - Parse the user's plan into the standard plan format (read `plan-criteria.md` for structure)
   - Run skeptic validation on the parsed plan (skip for Small tasks)
   - Present to user for confirmation
   - Save to `.geniro/planning/plan-<slug>.md` (or into the task directory if one exists for the current branch)

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
   - Note: CLAUDE.md and .claude/rules/ are auto-loaded — skip re-reading

5. **Determine effort level** — based on codebase scan and description, classify as Small/Medium/Large (see Effort Scaling above). This determines planning depth for Phase 2-3.

6. **Identify gray areas** — ambiguities that could lead to different implementations

7. **Resolve gray areas** (behavior depends on detected mode):
   - **Interactive (default):** Use `AskUserQuestion` to present structured questions (batch 3-5, recommend defaults):
     - Scope questions (backend-only? frontend? both?)
     - Key design decisions that affect the plan shape
     - Constraints (performance targets, backwards compat, etc.)
   - **Auto mode:** Pick the recommended default for every gray area. Log choices in the plan's Key Decisions section.
   - **Assumptions mode:** Produce a complete proposal with all decisions listed. Use the `AskUserQuestion` tool (do NOT output options as plain text) to present options: A) Looks good, proceed. B) I have corrections.
   - **Do NOT skip this step** — even with a Linear issue or in auto mode, gray areas must be resolved (either by asking or by choosing defaults)

### Phase 2: Generate Plan

1. **Read plan criteria:** Read `.claude/skills/plan/plan-criteria.md` for the plan structure and quality standards.

2. **Spawn architect-agent** via Agent tool with `subagent_type: "architect-agent"`:

   ```markdown
   ## Task: Create Implementation Plan

   Create a detailed implementation plan following the exact structure in the Plan Criteria below.
   Save the plan to: `.geniro/planning/plan-<slug>.md` (or into the task directory if one exists)

   ## Requirements
   [User's description + Linear issue context if any]

   ## User Decisions
   [Gray area answers from Phase 1]

   ## Codebase Context
   [Pre-inlined: relevant file contents, exemplar files, conventions discovered]

   ## Plan Criteria
   [Pre-inline the FULL contents of `.claude/skills/plan/plan-criteria.md`]

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

1. **Spawn skeptic-agent** via Agent tool with `subagent_type: "skeptic-agent"`:

   ```markdown
   ## Task: Validate Implementation Plan

   Review this implementation plan against the 8-dimension validation checklist from plan-criteria.md (pre-inlined below).

   ## Plan
   [Pre-inline the full plan file contents]

   ## Original Requirements
   [Pre-inline the user's description + decisions from Phase 1]

   ## Validation Standard + Mirage Detection
   [Pre-inline the "Validation Standard" section from `.claude/skills/plan/plan-criteria.md` — includes the 8 dimensions AND the mandatory mirage detection instructions]

   ## Output File
   Write your validation report to: `.geniro/planning/validation-report.md`
   (or `<task-dir>/validation-report.md` if a task directory exists)

   You MUST write this file using the Write tool — do NOT just return the report as text.

   ## Report Contents
   - PASS / FAIL for each of the 8 dimensions with evidence
   - Mirages found (hallucinated files/functions/packages)
   - Critical issues (must fix before approval)
   - Warnings (consider before implementing)
   - Overall verdict: PASS / NEEDS REVISION
   ```

2. **Read the validation report** from the file the skeptic wrote. If the file doesn't exist (skeptic failed to write it), treat as NEEDS REVISION and re-spawn with explicit instruction to write the file.

2. **If NEEDS REVISION:** Route feedback back to architect-agent with specific issues. Architect revises the plan file. Re-run skeptic. Max 3 iterations. **If 3 iterations exhausted:** Use the `AskUserQuestion` tool (do NOT output options as plain text) to present the best plan + remaining issues with options: A) Approve as-is with known issues noted. B) Abandon this approach, start fresh. C) I'll fix the plan manually.

3. **If PASS:** Proceed to Phase 4.

### Phase 4: Present Plan to User

1. **Read the plan file** from `.geniro/planning/`

2. **Present the full plan** — output the complete plan content. Do NOT summarize or abbreviate. The user needs to see every step and every file.

3. **Add metadata:**
   - "Full plan saved to `.geniro/planning/<filename>`"
   - "Skeptic validation: PASS — N/8 dimensions verified"
   - If any warnings from skeptic: list them

4. **Ask for approval** using the `AskUserQuestion` tool (do NOT output options as plain text):
   - A) **Approve this plan** — mark as approved, ready for `/geniro:implement`
   - B) **Adjust** — describe what to change (routes back to architect for revision)
   - C) **Too large — split** — decompose into smaller plans
   - D) **Start implementing now** — approve + immediately begin `/geniro:implement` using this plan

5. **Route based on answer:**
   - **A:** Update plan status to `approved`, done
   - **B:** Collect feedback, revise plan (back to Phase 2 with revision context), re-present. Max 3 rounds.
   - **C:** Help decompose into sub-plans, each saved as a separate plan file
   - **D:** Update plan status to `approved`, then invoke the implement skill referencing this plan file

### On approval, update the plan header:

Change `Status: draft` → `Status: approved`

---

## Integration with /geniro:implement

When `/geniro:implement` is invoked:

1. **Check for existing approved plans:** Glob `.geniro/planning/plan-*.md` AND `.geniro/planning/*/plan-*.md`, read headers, find plans with `Status: approved` that match the task description.

2. **If matching approved plan exists:** Skip Phase 2 (Architect) entirely — use the existing plan. Present it in Phase 3 (Approval) with: "Found existing approved plan: `<filename>`. Using this as the implementation plan."

3. **If no matching plan exists:** Run Phase 2 as normal — spawn architect, generate plan following `plan-criteria.md`, validate with skeptic.

4. **If user provides a detailed implementation plan as arguments to /geniro:implement:** Parse into plan format, validate, save, and use — skip architect generation.

---

## Definition of Done

Plan skill is complete when:
- [ ] Plan file written to `.geniro/planning/plan-<slug>.md`
- [ ] Skeptic validation passed (or skipped for Small tasks with reason noted)
- [ ] User approved the plan (or chose to implement immediately)
- [ ] Plan status updated to `approved` in the file header

---

## Error Handling

| Error | Recovery |
|-------|----------|
| Architect produces vague plan (missing files, no verify criteria) | Return with specific gaps from plan-criteria.md checklist |
| Skeptic finds critical gaps after 3 iterations | Present best plan + remaining issues to user for decision |
| Skeptic finds mirages (hallucinated files/functions) | Return to architect with specific mirages, require grep verification |
| Plan has >15 steps | Suggest splitting into sub-plans |
| Linear MCP unavailable | Log warning, proceed without issue context |
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
