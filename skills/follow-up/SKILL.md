---
name: geniro:follow-up
description: "Use when making small post-implementation changes that skip architecture. Assesses complexity (trivial/small/medium), implements, validates, reviews, ships. Escalates to /geniro:implement if scope is too large. Do NOT use for new features, new entities, new endpoints/pages, auth/permissions changes, new modules, or changes requiring architecture decisions."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, WebSearch]
argument-hint: "[description of the change]"
---

# Follow-Up Change Pipeline

**You are a coordinator.** You delegate ALL implementation work to subagents. You do NOT write code directly — no exceptions, not even for Trivial changes. Every code change (implementation, fixes, tweaks) goes through a subagent. You run shell commands (build, test, lint) and read their output to determine pass/fail.

**Pipeline:** Assess → Implement → Simplify → Validate → Review → Ship (includes Learn & Improve before commit)

Phases marked **(WAIT)** require user input before proceeding.

## AskUserQuestion

Every question to the user should use `AskUserQuestion`. Formulate 2-4 options with short labels and descriptions. The tool auto-adds "Other" for custom input.

## Agent Failure Handling

If any delegated agent fails (timeout, error, empty/garbage result): retry once with the same prompt. If the retry also fails, escalate to the user with the error context and ask whether to skip that step, try a different approach, or abort.

## Codegen Rule

If the project uses code generation (e.g., OpenAPI client generation, GraphQL codegen, Prisma client, etc.), run the appropriate codegen command after any step that modifies files that feed into the generator (DTOs, schemas, controllers, etc.). This prevents stale generated types from causing downstream failures. Check CLAUDE.md or package.json for the project's codegen commands.

## Change Request

$ARGUMENTS

**If `$ARGUMENTS` is empty**, ask the user via `AskUserQuestion` with header "Change": "What would you like to change?" with options "Describe the change" / "Fix a specific issue". Do not proceed until a change is provided.

---

## Phase 1: Assess

Determine what needs to change, how complex it is, and whether this skill can handle it.

### Step 1: Context Scan

1. **Load prior planning context** — `Glob(".geniro/planning/*/")`, match against current branch (`git branch --show-current`). If found, read: `spec.md`, `plan-*.md`, `state.md`, `concerns.md`, `notes.md`, `review-feedback.md`. These prevent re-discovering conventions and contradicting prior decisions. If none found, proceed without.

2. **Read the change request** and identify which files likely need to change
3. **Codebase scan** (Glob/Grep) to find the exact files and understand current patterns
4. **Read the files** that will be modified — understand current state before changing anything
5. **Check current state:**
   ```bash
   git branch --show-current
   git log --oneline -5
   git status --short
   ```

### Step 2: Complexity Assessment

Assess the change by checking for **hard escalation signals first**, then evaluating overall complexity. File count is a supporting signal, not the primary gate.

#### Hard Escalation Signals (any ONE triggers escalation to /geniro:implement)

| Signal | Why it escalates |
|--------|-----------------|
| New entity/table/migration | Irreversible schema change, requires architecture |
| New API endpoint or page/route | Cross-stack coordination, API spec, auth decisions |
| Auth/permissions/role changes | Infinite blast radius, invisible failure mode |
| New module or layer promotion | Architectural decision about dependency graph |
| 3+ modules coordinated | Distributed-transaction-level coordination |
| Open-closed violation (changing public signatures, shared middleware, routing logic) | Unbounded regression risk |
| New async/queue/background work | Runtime failures not caught by static checks |
| New external integration or env vars | Cross-cutting infra work |
| Ambiguous intent — multiple valid approaches | Needs Discovery phase first |

#### Complexity Levels (when no hard escalation signal is present)

- **Trivial**: 1–2 files, single module, fix/patch to existing logic, intent is unambiguous. *Examples: fix a validation message, correct a query filter, adjust a CSS class.*
- **Small**: 3–5 files, 1–2 modules, modifies existing endpoints/pages/fields, clear bounded logic. *Examples: add a filter param to an existing endpoint + DTO + query + hook, rename a response field across DTO and consumer.*
- **Medium**: 6–8 files, up to 2 modules, may add fields to existing entities (no new tables), non-trivial but clear logic. *Examples: add a column to an entity + migration + DTO + query + UI table + test, change an existing calculation.*
- **Too large**: 9+ files, OR any hard escalation signal above. Escalate to `/geniro:implement`.

**File count is a smell detector, not a complexity detector.** A 2-file change adding a new entity is "Too large." A 7-file change propagating an existing filter is "Medium." When file count is high, ask "why?" — the answer contains the actual complexity signal.

### Step 3: Escalation Gate

**If complexity is "Too large":**

Present escalation signals to user. `AskUserQuestion` with header "Scope":
- "Escalate to /geniro:implement" → output `/geniro:implement [change request]` and stop
- "Proceed anyway" → continue, treat as Medium complexity (full validation + review)
- "Reduce scope" → ask what to cut, re-assess, loop back to Step 2

**→ Proceed to Phase 2.**

---

## Phase 2: Implement

### Step 1: Plan (Medium complexity only)

Write a brief plan: list each file and what changes, dependencies, risks. Present it via `AskUserQuestion` header "Plan": "Looks good — proceed" / "Adjust — change the approach".

### Step 2: Execute

**Trivial** (1–2 files, obvious fix): Delegate to a single agent (same template as Small below, without Tests section). Even Trivial changes go through agents — orchestrator context is too expensive to spend on implementation.

**Small** (3–5 files, 1–2 modules): Delegate to a single agent:

```
Agent(model="sonnet", prompt="""
## Task
[describe the specific change needed]
## Pre-Inlined Context: [file contents from Phase 1]
## Codebase Conventions: match existing patterns exactly
## Tests — MANDATORY: create/update test file per changed source, follow existing patterns, run and report
## Requirements: follow CLAUDE.md, do NOT git add/commit/push, run validation, report changes and issues
""")
```

**Medium** (6–8 files, up to 2 modules): Decompose into 2–3 parallel agents by module/layer and spawn in a **single message**:

1. Group the files from your plan by module or layer (e.g., backend vs frontend, entity+service vs DTO+hook)
2. Each agent gets its own file group — no overlap between agents
3. Pre-inline the file contents each agent needs from Phase 1

```
# Spawn ALL agents in a SINGLE message for parallel execution:
# Each agent prompt: Task, Pre-Inlined Context, Tests — MANDATORY, Requirements (scope/CLAUDE.md/no-git/report)

Agent(model="sonnet", prompt="""
## Task — Group 1: [module/layer name]
[changes for this group]
## Pre-Inlined Context: [file contents]
## Tests — MANDATORY: create/update test file per changed source, follow existing patterns, run and report
## Requirements: ONLY modify [list files], follow CLAUDE.md, do NOT git add/commit/push, report changes
""", description="Implement [group 1]")

Agent(model="sonnet", prompt="""
## Task — Group 2: [module/layer name]
[changes for this group]
## Pre-Inlined Context: [file contents]
## Tests — MANDATORY: create/update test file per changed source, follow existing patterns, run and report
## Requirements: ONLY modify [list files], follow CLAUDE.md, do NOT git add/commit/push, report changes
""", description="Implement [group 2]")
```

If all files are tightly coupled (same module, sequential dependencies), use a single agent instead — don't force parallelism where it doesn't fit.

### Step 3: Completion Check

After agents report done, verify the task was completed — do NOT read source code to verify correctness:

1. Run `git diff --name-only` and `git status --short` — confirm expected files were created/modified (diff shows tracked changes, status shows new untracked files)
2. Check the agent's report covers all items from the change request
3. If the agent missed files or partially completed: delegate a follow-up agent with the gap description. Do NOT fill in the gaps yourself.

### Strategic Compact Point (Small/Medium only)

**Skip for Trivial changes** — proceed directly to Phase 3/4.

After implementation agents complete, your context is loaded with pre-inlined file contents and agent reports. Before continuing to validation/review, checkpoint and suggest compaction:

1. Write state to `.geniro/follow-up-state.md`:
   ```
   complexity: [trivial/small/medium]
   change: [one-line description]
   phase: 2-complete
   changed-files: [list from git diff --name-only]
   branch: [current branch]
   ```
2. Tell the user:
   > Implementation complete. I recommend running `/compact` now to free context for validation and review phases. After compacting, type `/geniro:follow-up continue` to resume from Phase 3.

**After compaction (or if user skips):** Read `.geniro/follow-up-state.md` and `git diff --name-only` to restore context. Proceed to Phase 3 (Medium) or Phase 4 (Small).

**DO NOT present a summary or ask "anything else?" here. Phases 3-6 have not run yet.**

---

## Phase 3: Simplify (Medium and "Proceed anyway" only)

**Purpose:** Code quality pass on changed files — catch AI-generated anti-patterns before validation.

**Skip for Trivial and Small changes** — proceed directly to Phase 4 (Validate).

### Step 1: Spawn simplify agent

Spawn a **general-purpose** subagent with `model: "sonnet"`. The agent reads its own criteria file — do NOT pre-read criteria into orchestrator context:

```
Agent(model="sonnet", prompt="""
## Task: Simplify Changed Files
Make changed files cleaner, simpler, more consistent — without changing behavior.
Read and apply `.claude/skills/deep-simplify/simplify-criteria.md`
Changed files: [list from git diff --name-only]
Apply P1+P2 findings, report P3 only. Zero behavior change. Do NOT git add/commit/push.
Do NOT modify files outside changed list. Never delete or weaken test assertions.
""", description="Simplify: changed files")
```

### Step 2: Verify after simplification

Spawn a validation agent (same template as Phase 4 Step 2) to check simplification didn't break anything. If FAIL: revert simplification (`git checkout -- .`), note "Simplification skipped — caused CI failures." Proceed to Phase 4.

**→ You MUST proceed to Phase 4 (Validate) now. DO NOT present a summary or ask "anything else?" — validation has not run yet.**

---

## Phase 4: Validate

**Your role in this phase:** verify the diff matches expectations, then delegate all heavy validation (build, lint, test) to a validation agent. You do NOT run build/lint/test commands yourself — that accumulates context that degrades your coordination for Phases 5-6. You do NOT read source code — that is Phase 5's job.

### Step 1: Diff Check

Verify implementation completeness by checking the diff:

```bash
git diff --name-only
git status --short | head -20
```

Confirm: (1) expected files were created/modified, (2) no unexpected files changed, (3) no untracked files that should be tracked. If files are missing or unexpected, delegate a fix agent before proceeding.

### Step 2: Validation Agent

Spawn a validation agent that runs the project's full check suite. The agent runs commands, you read its pass/fail summary.

```
Agent(model="sonnet", prompt="""
## Task: Run Full Validation Suite
Run the project's validation commands and report pass/fail results.

## Steps
1. Run autofix (lint --fix / format) from CLAUDE.md or package.json
2. Run full validation suite (build + lint + test) from CLAUDE.md
3. If project uses codegen AND DTOs/schemas/controllers changed: run codegen, then re-validate
4. [Medium only] Start the app in background, wait 10-15s, check for startup errors (DI, missing providers). Kill afterward.
5. Check test file existence: for each changed source file in [list from git diff --name-only], verify a corresponding .test.* or .spec.* file exists adjacent to it

## Report Format
Return EXACTLY this structure:
- autofix: PASS/FAIL [details if fail]
- build: PASS/FAIL [details if fail]
- lint: PASS/FAIL [details if fail]
- test: PASS/FAIL [details if fail]
- codegen: PASS/SKIP/FAIL [details if fail]
- startup: PASS/SKIP/FAIL [details if fail]
- test-coverage: [list of source files missing test files, or "all covered"]

## Requirements
- Do NOT run git add/commit/push
- Do NOT fix any issues — only report them
- Capture full error output for any failures
""", description="Validate: full check suite")
```

### Step 3: Fix Loop

If the validation agent reports failures:
1. **Lint/format only** → spawn a fixer agent with the lint errors
2. **Type/build/test failure** → spawn a fixer agent with the exact error output from the validation report. Do NOT read source code to diagnose.
3. **Missing test files** → spawn an agent: "Create test file next to source. Follow existing patterns."
4. After each fix round, re-run the validation agent (Step 2)
5. **Max 2 fix rounds** — then escalate: present the validation report to the user. `AskUserQuestion` with header "Stuck": "Try a different approach" / "Escalate to /geniro:implement" / "Show current state". Do NOT retry same approach a 3rd time.

### Strategic Compact Point (Medium only)

**Skip for Trivial and Small changes** — proceed directly to Phase 5.

Validation accumulated fix-loop context. Before spawning review agents:

1. Update `.geniro/follow-up-state.md`: set `phase: 4-complete`
2. Tell the user:
   > Validation passed. For best review quality, I recommend `/compact` now. After compacting, type `/geniro:follow-up continue` to resume the review phase.

**After compaction (or if user skips):** Read `.geniro/follow-up-state.md` and `git diff --name-only` to restore context.

**→ You MUST proceed to Phase 5 (Review) now. DO NOT present results to the user or ask "anything else?" — review has not run yet.**

---

## Phase 5: Review

### Step 1: Code Review

Capture the changed file list from the diff against main.

**Trivial changes (1–2 files):** Review the diff yourself — no subagent needed. Check for: typos in the fix itself, accidental deletions, logic inversion, missed second occurrence. If anything looks off, delegate the fix to an agent and re-validate. Do NOT fix code directly.

**Small changes (3–5 files):** Spawn a single reviewer-agent. Pass the criteria file paths — the agent reads them itself. Do NOT pre-read criteria files into orchestrator context.

```
Agent(model="sonnet", prompt="""
## Review: Follow-Up Change
This is a follow-up change — focus on correctness and regressions. CI already passed. Keep review proportional to change size.

CHANGED FILES: [list]
CHANGE SUMMARY: [summary]

## Review Criteria
Read and apply all 5 criteria files from `.claude/skills/review/`:
- `.claude/skills/review/bugs-criteria.md`
- `.claude/skills/review/security-criteria.md`
- `.claude/skills/review/architecture-criteria.md`
- `.claude/skills/review/tests-criteria.md`
- `.claude/skills/review/guidelines-criteria.md`

Review across all 5 dimensions. Report findings with severity (CRITICAL/HIGH/MEDIUM). Skip MEDIUM — only report CRITICAL and HIGH.
Conclude with verdict: CHANGES REQUIRED / APPROVED WITH MINOR / APPROVED.
""", description="Review: follow-up change")
```

**Medium changes (6–8 files):** Spawn 2–3 reviewer-agent instances in a **single message**. Each agent reads its own criteria file — do NOT pre-read criteria into orchestrator context:

```
# Spawn ALL reviewers in a SINGLE message for parallel execution:

Agent(model="sonnet", prompt="""
DIMENSION: Bugs & Correctness
CHANGED FILES: [list]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed. Keep review proportional.
Report findings with severity (CRITICAL/HIGH/MEDIUM). Skip MEDIUM — only report CRITICAL and HIGH.
Conclude with verdict: CHANGES REQUIRED / APPROVED WITH MINOR / APPROVED.

## Review Criteria
Read and apply this criteria file: `.claude/skills/review/bugs-criteria.md`
""", description="Review: bugs")

Agent(model="sonnet", prompt="""
DIMENSION: Security & Edge Cases
CHANGED FILES: [list]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed. Keep review proportional.
Report findings with severity (CRITICAL/HIGH/MEDIUM). Skip MEDIUM — only report CRITICAL and HIGH.
Conclude with verdict: CHANGES REQUIRED / APPROVED WITH MINOR / APPROVED.

## Review Criteria
Read and apply this criteria file: `.claude/skills/review/security-criteria.md`
""", description="Review: security")
```

Add a 3rd reviewer (architecture + tests + guidelines) only if changes touch cross-module boundaries. That agent reads `.claude/skills/review/architecture-criteria.md`, `tests-criteria.md`, and `guidelines-criteria.md` itself.

### Step 2: Process Results

Aggregate findings from all reviewers. Deduplicate (same file:line from multiple reviewers = single finding, keep highest severity).

- Any reviewer **CHANGES REQUIRED** → fix loop: delegate to fresh agent, re-validate (Step 2 only), re-review with **fresh** reviewer (avoid anchoring). Max 1 fix round for follow-ups. If still CHANGES REQUIRED after 1 round: `AskUserQuestion` header "Review": "Try different approach" / "Accept with known issues" / "Escalate to /geniro:implement".
- All reviewers **APPROVED WITH MINOR** → note improvements in Ship summary. Only fix MEDIUM+ findings — delegate if any, then proceed.
- All reviewers **APPROVED** → proceed directly.

**→ Proceed to Phase 6.**

---

## Phase 6: Ship (WAIT)

Show a summary:

**Done. Here's what changed:**
- [file]: [what changed]
- Validation: PASS/FAIL
- Review: [verdict]
- Test coverage: [covered / gaps noted / tests added]

### Step 1: Review Gate (loop entry point)

`AskUserQuestion` with header "Review" and options:
- "Looks good" — I'm happy with the changes
- "Needs tweaks" — I want small adjustments (I'll describe)
- "Done" — leave uncommitted, I'll handle it myself

**If "Needs tweaks":**
1. `AskUserQuestion` header "Tweak": "Describe what to change" (free-text via Other)
2. **Assess the tweak** — if it expands scope significantly (new files, new endpoints), warn via `AskUserQuestion` header "Scope": "Continue here" / "Escalate to /geniro:implement".
3. Delegate changes to an agent (never apply directly)
4. Re-run validation (Phase 4 Step 2 only)
5. If 10+ lines changed, re-run reviewer (Phase 5). Max 1 review round for tweaks.
6. **Loop back to Step 1** — re-present summary and ask the Review question again. Do NOT skip ahead to Step 2.
7. Soft limit: after 3 tweak rounds, suggest creating a new `/geniro:follow-up` or `/geniro:implement` for remaining changes.

**If "Done":** Leave changes uncommitted, skip to cleanup.

**If "Looks good":** Proceed to Step 2.

### Step 2: Learn & Improve

**Skip entirely for Trivial changes.** Runs BEFORE committing so doc/rule changes are included.

**Extract Learnings:** Scan conversation. Save `feedback` memory (user corrections, workarounds, non-obvious resolutions) and `project` memory (discovered bugs/gotchas). UPDATE existing memories rather than duplicate. Skip if nothing novel.

**Suggest Improvements (WAIT) — Skip for Small changes**, run for Medium or "Proceed anyway" only. Check for: rules gaps, rules conflicts, stale documentation. Draft: file, change, why. `AskUserQuestion` header "Improve": "Apply all" / "Review one-by-one" / "Skip".

### Step 3: Ship Decision

**Only reach this step when the user explicitly chose "Looks good" in Step 1.** Never auto-commit — always ask.

`AskUserQuestion` with header "Ship" and options:
- "Commit" — add to current branch (includes all changes: implementation + docs + rule updates)
- "Commit + push" — commit and push to remote
- "Commit + PR" — commit, push, and create pull request
- "Leave as-is" — don't commit, I'll handle git myself

**Commit message format:** Follow conventional commits:
```
fix(module): description of what changed
```

### Cleanup

Kill any orphaned background processes started during validation (startup checks, dev servers, etc.).

**→ Pipeline complete.**

---

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "The change is too small for full review" | Small changes cause production incidents too. Follow the process. |
| "I already know how to do this" | Skills encode process knowledge beyond individual capability. Follow them. |
| "The tests are obviously fine" | Run them. "Obviously fine" is the #1 predictor of broken tests. |
| "This doesn't need a complexity assessment" | The assessment takes 30 seconds. Skipping it risks building something that should be `/geniro:implement`. |
| "I can do this in one step" | Multi-step exists for a reason. Each step catches different failures. |
| "The user seems impatient" | Cutting corners costs more time than following the process. |
| "I'll implement this Medium change in one agent" | If files span 2 modules, decompose into parallel agents. Single-agent Medium misses parallelism. |
| "One reviewer is enough for Medium" | Single reviewers miss cross-dimensional issues. Spawn 2–3 in parallel — it's the same wall-clock time. |
| "I'll spawn agents one at a time" | All parallel agents MUST be in a SINGLE message. Sequential spawning defeats the purpose. |
| "I'll implement this change directly — it's straightforward" | Orchestrator tokens are the most expensive resource. ALL changes MUST be delegated to subagents — no exceptions, not even Trivial. |
| "I'll quickly fix this Trivial change myself" | No exceptions. Even Trivial fixes go through agents. Orchestrator context is the most expensive resource. |
| "I'll just quickly edit these files myself since I already read them" | Reading files for assessment is fine. Writing code is implementation — delegate it, for ALL changes without exception. The assessment context goes into the agent prompt. |
| "Spawning an agent for this is overkill" | Every change, even 1-line fixes, goes through agents. The context cost of orchestrator implementation always exceeds the cost of spawning. |
| "I noticed a bug during validation — I'll fix it now since I'm already here" | Bug-finding is Phase 5 (Review). Phase 4 runs commands and reads pass/fail output. If automated checks pass, the code moves to Review where fresh-context agents find bugs. Fixing bugs in Phase 4 steals Review's job and accumulates context that degrades your coordination. |
| "I can see the type error — I'll fix it faster than spawning an agent" | ALL fixes go through agents regardless of complexity level. Context you accumulate reading source code to "quickly fix" errors degrades your coordination for Phases 5-6. |

---

## Task Tracking

Use `TodoWrite`: create todos (Assess, Implement, Simplify, Validate, Review, Ship) at the start. Mark `in_progress` → `completed` as each phase runs. For Medium: add plan outline as todo before implementation.

## Definition of Done

- [ ] Complexity assessed and routed correctly
- [ ] Prior planning context loaded if available
- [ ] Implementation matches `$ARGUMENTS`
- [ ] Simplification pass run (Medium) or skipped (Trivial/Small)
- [ ] All tests pass; no type/lint errors
- [ ] Code quality reviewed
- [ ] User approved before shipping
- [ ] Change committed or delivered for user to commit

---

## When to Use This Skill vs. `/geniro:implement`

**`/geniro:follow-up`:** Builds on existing code, scope clear and bounded, no new architecture, complexity ≤ Medium.
**`/geniro:implement`:** New feature/entity/endpoint/auth, ambiguous intent, 3+ modules, needs design review.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Validation fails after 2 fix rounds | Present structured handoff to user |
| Change larger than expected | Escalate to `/geniro:implement` |
| Agent re-reads files already scanned | Pre-inline file contents from Phase 1 into agent prompt |
| Reviewer finds architectural issues | Escalate to `/geniro:implement` with reviewer findings |
| Codegen not detected | Run codegen manually if API surface changed |

---

## Examples

- **Trivial:** `/geniro:follow-up Fix typo in src/auth.ts line 42`
- **Small:** `/geniro:follow-up Better error message when API returns 429`
- **Medium:** `/geniro:follow-up Rename userId to ownerId across UserService`
- **Too Large:** `/geniro:follow-up Add Notifications service with websockets` → Escalate to `/geniro:implement`
