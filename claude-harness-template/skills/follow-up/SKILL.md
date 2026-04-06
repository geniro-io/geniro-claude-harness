---
name: follow-up
description: "Use when making small post-implementation changes that skip architecture. Assesses complexity (trivial/small/medium), implements, validates, reviews, ships. Escalates to /implement if scope is too large. Do NOT use for new features, new entities, new endpoints/pages, auth/permissions changes, new modules, or changes requiring architecture decisions."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, WebSearch]
argument-hint: "[description of the change]"
---

# Follow-Up Change Pipeline

**You are a coordinator.** You delegate implementation work to subagents. You do NOT write code directly — except Trivial changes (1-2 files, obvious fix, no logic). For Small and Medium changes, you MUST delegate to subagents. You run shell commands (build, test, lint) and read their output to determine pass/fail. When something fails, you forward the raw error output to a fixer agent.

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

1. **Load prior planning context** — `Glob(".claude/.artifacts/planning/*/")`, match against current branch (`git branch --show-current`). If found, read: `spec.md`, `plan-*.md`, `state.md`, `concerns.md`, `notes.md`, `review-feedback.md`. These prevent re-discovering conventions and contradicting prior decisions. If none found, proceed without.

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

#### Hard Escalation Signals (any ONE triggers escalation to /implement)

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
- **Too large**: 9+ files, OR any hard escalation signal above. Escalate to `/implement`.

**File count is a smell detector, not a complexity detector.** A 2-file change adding a new entity is "Too large." A 7-file change propagating an existing filter is "Medium." When file count is high, ask "why?" — the answer contains the actual complexity signal.

### Step 3: Escalation Gate

**If complexity is "Too large":**

Present escalation signals to user. `AskUserQuestion` with header "Scope":
- "Escalate to /implement" → output `/implement [change request]` and stop
- "Proceed anyway" → continue, treat as Medium complexity (full validation + review)
- "Reduce scope" → ask what to cut, re-assess, loop back to Step 2

**→ Proceed to Phase 2.**

---

## Phase 2: Implement

### Step 1: Plan (Medium complexity only)

For **Medium** complexity changes, write a brief implementation plan before coding:

1. List each file to change and what changes
2. Identify dependencies between changes (order matters)
3. Note any risks or things to verify

Present the plan to the user:

`AskUserQuestion` with header "Plan":
- "Looks good — proceed"
- "Adjust" — I want to change the approach

### Step 2: Execute

**Trivial** (1–2 files, obvious fix): Implement directly using Edit/Write tools. No subagent needed. **Guard:** If you find yourself reading more than 2 files or the fix touches logic (not just text/config), re-assess — it's probably Small, not Trivial. Delegate instead.

**Small** (3–5 files, 1–2 modules): Delegate to a single agent:

```
Agent(model="sonnet", prompt="""
## Task
[describe the specific change needed]

## Pre-Inlined Context
[paste the content of files you read in Phase 1 — save the agent from re-reading them]

## Codebase Conventions
Match existing patterns exactly. Find the closest existing example and follow it.

## Tests — MANDATORY
- For each new/changed source file, create or update the corresponding test file
- Follow existing test patterns in the same module (find the nearest test file as exemplar)
- Run tests after changes and report results

## Requirements
- Follow project rules in CLAUDE.md and docs/
- Do NOT run git add/commit/push — the orchestrator handles git
- Run the project's validation commands after changes
- Report: files changed, what was done, any issues encountered
""")
```

**Medium** (6–8 files, up to 2 modules): Decompose into 2–3 parallel agents by module/layer and spawn in a **single message**:

1. Group the files from your plan by module or layer (e.g., backend vs frontend, entity+service vs DTO+hook)
2. Each agent gets its own file group — no overlap between agents
3. Pre-inline the file contents each agent needs from Phase 1

```
# Spawn ALL agents in a SINGLE message for parallel execution:

Agent(model="sonnet", prompt="""
## Task — Group 1: [module/layer name]
[changes for this group]

## Pre-Inlined Context
[file contents this agent needs]

## Tests — MANDATORY
- For each new/changed source file, create or update the corresponding test file
- Follow existing test patterns in the same module (find the nearest test file as exemplar)
- Run tests after changes and report results

## Requirements
- Scope: ONLY modify files in your group: [list files]
- Follow project rules in CLAUDE.md and docs/
- Do NOT run git add/commit/push
- Report: files changed, what was done, any issues
""", description="Implement [group 1]")

Agent(model="sonnet", prompt="""
## Task — Group 2: [module/layer name]
[changes for this group]
...
""", description="Implement [group 2]")
```

If all files are tightly coupled (same module, sequential dependencies), use a single agent instead — don't force parallelism where it doesn't fit.

**→ After implementation, proceed to Phase 3.**

---

## Phase 3: Simplify (Medium and "Proceed anyway" only)

**Purpose:** Code quality pass on changed files — catch AI-generated anti-patterns before validation.

**Skip for Trivial and Small changes** — proceed directly to Phase 4 (Validate).

### Step 1: Spawn simplify agent

Pre-read `.claude/skills/deep-simplify/simplify-criteria.md`. Spawn a **general-purpose** subagent with `model: "sonnet"`:

```
Agent(model="sonnet", prompt="""
## Task: Simplify Changed Files
You are a code simplifier. Make changed files cleaner, simpler, more consistent — without changing behavior.

## Criteria
[Pre-inline `.claude/skills/deep-simplify/simplify-criteria.md`]

## Changed Files: [List from git diff --name-only]

## Pipeline
1. Read each changed file + immediate neighbors for context
2. Run three analysis passes (Reuse, Quality, Efficiency) from criteria
3. Classify findings as P1/P2/P3 — apply P1+P2, report P3 only
4. Report using Completion Report format from criteria

## Requirements
- Zero behavior change — preserve exact inputs, outputs, side effects
- Do NOT run git add/commit/push
- Do NOT modify files outside changed list (unless extracting shared utility)
- Never delete or weaken test assertions
""", description="Simplify: changed files")
```

### Step 2: Verify after simplification

1. Run lint/format fix
2. Run build + lint + test
3. **If checks fail:** revert simplification (`git checkout -- .`), note "Simplification skipped — caused CI failures." Proceed to Phase 4.

**→ Proceed to Phase 4 (Validate).**

---

## Phase 4: Validate

### Step 1: Autofix

Run the project's autofix command from CLAUDE.md (e.g., `lint --fix`, `format`). If CLAUDE.md doesn't specify one, check `package.json` scripts. If still unknown, ask the user via `AskUserQuestion`.
```bash
<lint_fix_cmd> 2>/dev/null || true
```

### Step 2: Full Check

Run the project's full validation suite (build + lint + test) from CLAUDE.md. Prefer backpressure if available (`source .claude/hooks/backpressure.sh && run_silent "Full Check" "<cmd>"`), otherwise pipe to temp file (`<cmd> 2>&1 | tee /tmp/ci-output.log | tail -80`). Search saved output: `grep -i "error\|fail" /tmp/ci-output.log | head -20`

### Step 3: Codegen Check

If the project uses code generation AND DTOs/schemas/controllers changed: run codegen, then re-run validation.

### Step 4: Runtime Startup Check (Medium complexity only)

Start the changed side in background, wait 10–15s, check for startup errors (DI failures, missing providers, compilation). Kill afterward. Startup errors → fix and re-validate.

### Step 5: Test Coverage Check (Small/Medium complexity)

Check each test type based on what changed. Use `git diff --name-only` against main to identify changed files.

#### Unit Tests

1. Find test files adjacent to changed source files (Glob), grep for changed function/class names
2. Tests exist but don't cover change → delegate: "Add test cases in [existing test file]. Extend, don't rewrite."
3. No tests + non-trivial logic changed → delegate: "Create test file next to source. Follow existing patterns."
4. Run unit tests after any new/updated test files.

#### Integration Tests — only if DAO/query/multi-service logic changed

1. Check for existing integration tests covering the changed module
2. Tests exist but don't cover change → delegate to extend. No tests + change warrants them → delegate to create.
3. Minor change (field addition, filter tweak) + existing tests pass → skip, note in Ship summary.

### Step 6: Fix Loop

If validation, startup, or tests fail:
1. Lint/format only → autofix, re-validate
2. Type/build/test → fix directly (Trivial) or delegate with exact error output
3. After each fix round, run codegen check if applicable, then re-validate
4. **Max 2 fix rounds** — then escalate: present structured handoff (Fixed / Still failing with error+file+suggested fix / CI status per category). `AskUserQuestion` with header "Stuck": "Try a different approach" / "Escalate to /implement" / "Show current state". Do NOT retry same approach a 3rd time.

**→ After validation passes, proceed to Phase 5.**

---

## Phase 5: Review

### Step 1: Code Review

Capture the changed file list from the diff against main.

**Trivial changes (1–2 files):** Review the diff yourself — no subagent needed. Check for: typos in the fix itself, accidental deletions, logic inversion, missed second occurrence. If anything looks off, fix it and re-validate (Phase 4 Step 2 only). This takes 30 seconds and catches "obvious fix" mistakes that cause rollbacks.

**Small changes (3–5 files):** Pre-read all 5 review criteria files from `.claude/skills/review/` (bugs-criteria.md, security-criteria.md, architecture-criteria.md, tests-criteria.md, guidelines-criteria.md). Spawn a single reviewer-agent with the criteria pre-inlined and the change summary + changed file list:

```
Agent(model="sonnet", prompt="""
## Review: Follow-Up Change
This is a follow-up change — focus on correctness and regressions. CI already passed. Keep review proportional to change size.

CHANGED FILES: [list]
CHANGE SUMMARY: [summary]

## Review Criteria
[Pre-inline the contents of all 5 criteria files from `.claude/skills/review/`]

Review across all 5 dimensions. Report findings with severity (CRITICAL/HIGH/MEDIUM). Skip MEDIUM — only report CRITICAL and HIGH.
""", description="Review: follow-up change")
```

**Medium changes (6–8 files):** Pre-read the relevant criteria files from `.claude/skills/review/`. Spawn 2–3 reviewer-agent instances in a **single message**, each reviewing its own dimension with the corresponding criteria file pre-inlined:

```
# Spawn ALL reviewers in a SINGLE message for parallel execution:

Agent(model="sonnet", prompt="""
DIMENSION: Bugs & Correctness
[Pre-inline `.claude/skills/review/bugs-criteria.md`]
CHANGED FILES: [list]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed. Keep review proportional.
""", description="Review: bugs")

Agent(model="sonnet", prompt="""
DIMENSION: Security & Edge Cases
[Pre-inline `.claude/skills/review/security-criteria.md`]
CHANGED FILES: [list]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed. Keep review proportional.
""", description="Review: security")
```

Add a 3rd reviewer (architecture + tests + guidelines criteria combined from `.claude/skills/review/architecture-criteria.md`, `tests-criteria.md`, `guidelines-criteria.md`) only if changes touch cross-module boundaries.

### Step 2: Process Results

Aggregate findings from all reviewers. Deduplicate (same file:line from multiple reviewers = single finding, keep highest severity).

- Any reviewer **CHANGES REQUIRED** → fix loop: delegate to fresh agent, re-validate (Step 2 only — skip autofix/startup), re-review with **fresh** reviewer (avoid anchoring). Max 1 fix round for follow-ups.
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
1. Ask what to change
2. **Assess the tweak** — if it's another small fix, apply it directly. If it expands scope significantly (new files, new endpoints), warn:
   > "This is growing beyond follow-up scope. Want to continue here or escalate to `/implement`?"
3. Apply changes (directly or via agent)
4. Re-run validation (Phase 4 Step 2 only)
5. If 10+ lines changed, re-run reviewer (Phase 5). Max 1 review round for tweaks.
6. **Loop back to Step 1** — re-present summary and ask the Review question again. Do NOT skip ahead to Step 2.
7. Soft limit: after 3 tweak rounds, suggest creating a new `/follow-up` or `/implement` for remaining changes.

**If "Done":** Leave changes uncommitted, skip to cleanup.

**If "Looks good":** Proceed to Step 2.

### Step 2: Learn & Improve

Two jobs: save what we learned, suggest improvements. **Skip entirely for Trivial changes** (1-2 files, obvious fix). This runs BEFORE committing so that doc/rule changes are included in the commit.

#### Extract Learnings

Scan conversation for learnings. Save as `feedback` memory: user corrections/preferences, workarounds, non-obvious fix resolutions. Save as `project` memory: discovered bugs/gotchas. Check existing memories first — UPDATE rather than duplicate. Skip if nothing novel.

#### Suggest Improvements (WAIT)

**Skip for Small changes** — only run for Medium complexity or "Proceed anyway" escalated changes.

Check if the pipeline run revealed:
- **Rules gaps** — agent made a mistake a rule would have prevented
- **Rules conflicts** — a rule contradicted what actually works
- **Stale documentation** — rules reference patterns/files that no longer exist

For each improvement, draft: which file, what to change, why.

`AskUserQuestion` with header "Improve":
- "Apply all" — implement proposed changes
- "Review one-by-one" — approve each separately
- "Skip" — done

### Step 3: Ship Decision

**Only reach this step when the user explicitly chose "Looks good" in Step 1.** Never auto-commit — always ask.

`AskUserQuestion` with header "Ship" and options:
- "Commit" — add to current branch (includes all changes: implementation + docs + rule updates)
- "Commit + push" — commit and push to remote
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
| "This doesn't need a complexity assessment" | The assessment takes 30 seconds. Skipping it risks building something that should be `/implement`. |
| "I can do this in one step" | Multi-step exists for a reason. Each step catches different failures. |
| "The user seems impatient" | Cutting corners costs more time than following the process. |
| "I'll implement this Medium change in one agent" | If files span 2 modules, decompose into parallel agents. Single-agent Medium misses parallelism. |
| "One reviewer is enough for Medium" | Single reviewers miss cross-dimensional issues. Spawn 2–3 in parallel — it's the same wall-clock time. |
| "I'll spawn agents one at a time" | All parallel agents MUST be in a SINGLE message. Sequential spawning defeats the purpose. |
| "I'll implement this Small/Medium change directly — it's straightforward" | Orchestrator tokens are the most expensive resource. Small/Medium changes MUST be delegated to subagents. Only Trivial (1-2 files, no logic) can be done directly. |
| "I'll just quickly edit these files myself since I already read them" | Reading files for assessment is fine. Writing code is implementation — delegate it. The assessment context goes into the agent prompt. |
| "Spawning an agent for this is overkill" | A single-agent delegation costs fewer tokens than the orchestrator doing the work, because the orchestrator's context window is more expensive and accumulates garbage. |

---

## Task Tracking

Use `TodoWrite` to track progress:
- Create todos at the start: Assess complexity, Implement, Simplify, Validate, Review, Ship
- Mark each as `in_progress` when starting, `completed` when done
- For medium complexity: add the plan outline as a todo before implementation

## Definition of Done

For each change, confirm:

- [ ] Complexity assessed and routed correctly (trivial/small/escalated)
- [ ] Prior context loaded (spec, plan, concerns, notes, review-feedback from task directory if they exist)
- [ ] Implementation complete and matches `$ARGUMENTS`
- [ ] Simplification pass completed (Medium) or skipped (Trivial/Small)
- [ ] All tests pass (new and existing)
- [ ] No type/lint errors
- [ ] Code quality reviewed for edge cases and clarity
- [ ] User approved the change before shipping
- [ ] Change is committed or staged (or delivered for user to commit)

---

## When to Use This Skill vs. `/implement`

**`/follow-up`:** Change builds on existing code, scope is clear and bounded, no new architecture, complexity ≤ Medium.

**`/implement`:** New major feature/component, ambiguous intent, new entity/endpoint/auth, 3+ modules, multiple decision points, needs design review.

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Validation fails after 2 fix rounds | Agent is stuck on the same error | Present error to user with structured handoff |
| Change is larger than expected | Scope grew beyond follow-up | Escalate to `/implement` |
| Agent re-reads files already scanned | Pre-inlined context was not passed | Always paste file contents from Phase 1 into the agent delegation prompt |
| Reviewer finds architectural issues | Change needs design work | Escalate to `/implement` with reviewer findings as context |
| Codegen not detected | Schema/DTO changes not showing in diff | Run codegen manually if API surface changed |

---

## Examples

- **Trivial:** `/follow-up Fix typo in src/auth.ts line 42` → Read, fix, validate, review, ship
- **Small:** `/follow-up Better error message when API returns 429` → Find call sites, improve, test, review, ship
- **Small:** `/follow-up Fix double-render bug in Dashboard` → Reproduce, fix, test, review, ship
- **Medium:** `/follow-up Rename userId to ownerId across UserService` → Plan, refactor all sites, simplify, validate, review, ship
- **Too Large:** `/follow-up Add Notifications service with websockets` → Escalate to `/implement`
