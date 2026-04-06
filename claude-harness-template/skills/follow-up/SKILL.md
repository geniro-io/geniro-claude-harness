---
name: follow-up
description: "Use when making small post-implementation changes that skip architecture. Assesses complexity (trivial/small/medium), implements, validates, reviews, ships. Escalates to /implement if scope is too large. Do NOT use for new features, new entities, new endpoints/pages, auth/permissions changes, new modules, or changes requiring architecture decisions."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, WebSearch]
argument-hint: "[description of the change]"
---

# Follow-Up Change Pipeline

You are a **lightweight implementation orchestrator**. This skill handles changes that don't need the full `/implement` pipeline — streamlined assessment, implementation, validation, review, and ship.

**Pipeline:** Assess → Implement → Validate → Review → Ship (includes Learn & Improve before commit)

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

1. **Load prior planning context** — check if a prior `/implement` run left artifacts:
   ```
   Glob(".claude/.artifacts/planning/*/")
   ```
   Match against the current branch name (`git branch --show-current`). If a matching directory exists (e.g., `feat-add-oauth/`), read these files for context:
   - `spec.md` — requirements and acceptance criteria (use to validate your change doesn't contradict the design)
   - `plan-*.md` — implementation plan (understand what was built and why)
   - `state.md` — how far the implement pipeline got
   - `concerns.md` — skeptic-agent's findings (known risks, edge cases to watch)
   - `notes.md` — user corrections and preferences captured during implementation
   - `review-feedback.md` — reviewer findings (may flag areas relevant to your follow-up)
   
   These files prevent re-discovering conventions and avoid contradicting prior architectural decisions. If no matching directory exists, proceed without prior context.

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
| **New entity, table, or migration** | Irreversible schema change, requires architecture |
| **New API endpoint or new page/route** | Cross-stack coordination, API spec change, auth decisions |
| **Auth, permissions, or role changes** | Infinite blast radius, failure mode is invisible |
| **New module or module layer promotion** | Architectural decision about dependency graph and public API |
| **3+ modules coordinated** | Distributed-transaction-level coordination, needs a spec |
| **Open-closed principle violation** — e.g., changing a public method signature, altering shared validation/middleware, modifying switch/if routing logic instead of adding a handler | Modifies existing behavior for all consumers; regression risk is unbounded, needs rollback strategy |
| **New async/queue/background work** | Runtime failure modes not caught by static checks |
| **New external integration or new env vars** | Cross-cutting infra work |
| **Ambiguous intent** — multiple valid design approaches | Needs Discovery phase to resolve before implementation |

#### Complexity Levels (when no hard escalation signal is present)

- **Trivial**: 1–2 files, single module, fix/patch to existing logic, intent is unambiguous. *Examples: fix a validation message, correct a query filter, adjust a CSS class.*
- **Small**: 3–5 files, 1–2 modules, modifies existing endpoints/pages/fields, clear bounded logic. *Examples: add a filter param to an existing endpoint + DTO + query + hook, rename a response field across DTO and consumer.*
- **Medium**: 6–8 files, up to 2 modules, may add fields to existing entities (no new tables), non-trivial but clear logic. *Examples: add a column to an entity + migration + DTO + query + UI table + test, change an existing calculation.*
- **Too large**: 9+ files, OR any hard escalation signal above. Escalate to `/implement`.

**File count is a smell detector, not a complexity detector.** A 2-file change that adds a new entity is "Too large." A 7-file change that propagates an existing filter through DTO → service → query → hook → test is "Medium." When file count is high, ask "why?" — the answer contains the actual complexity signal.

### Step 3: Escalation Gate

**If complexity is "Too large":**

Present findings to the user:

> This change is larger than a follow-up:
> - [specific escalation signals detected]
>
> Recommend running `/implement [description]` for proper architecture and planning.

`AskUserQuestion` with header "Scope":
- "Escalate to /implement" — hand off to the full pipeline
- "Proceed anyway" — I understand the risk, keep going as follow-up
- "Reduce scope" — I'll narrow what I want changed

If user selects "Escalate to /implement": output the command `/implement [original change request]` and stop.
If user selects "Reduce scope": ask what to cut, re-assess, loop back to Step 2.
If user selects "Proceed anyway": continue — but enforce full validation and review (treat as Medium complexity).

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
Agent(prompt="""
## Task
[describe the specific change needed]

## Pre-Inlined Context
[paste the content of files you read in Phase 1 — save the agent from re-reading them]

## Codebase Conventions
Match existing patterns exactly. Find the closest existing example and follow it.

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

Agent(prompt="""
## Task — Group 1: [module/layer name]
[changes for this group]

## Pre-Inlined Context
[file contents this agent needs]

## Requirements
- Scope: ONLY modify files in your group: [list files]
- Follow project rules in CLAUDE.md and docs/
- Do NOT run git add/commit/push
- Report: files changed, what was done, any issues
""", description="Implement [group 1]")

Agent(prompt="""
## Task — Group 2: [module/layer name]
[changes for this group]
...
""", description="Implement [group 2]")
```

If all files are tightly coupled (same module, sequential dependencies), use a single agent instead — don't force parallelism where it doesn't fit.

**→ After implementation, proceed to Phase 3.**

---

## Phase 3: Validate

### Step 1: Autofix

Run the project's autofix command from CLAUDE.md (e.g., `lint --fix`, `format`). If CLAUDE.md doesn't specify one, check `package.json` scripts. If still unknown, ask the user via `AskUserQuestion`.
```bash
<lint_fix_cmd> 2>/dev/null || true
```

### Step 2: Full Check

Run the project's full validation suite (build + lint + test) from CLAUDE.md via backpressure to preserve context:
```bash
source .claude/hooks/backpressure.sh
run_silent "Full Check" "<validation_cmd>"
```
If backpressure is unavailable, run commands directly and pipe to a temp file:
```bash
<validation_cmd> 2>&1 | tee /tmp/ci-output.log | tail -80
```

To search saved output later: `grep -i "error\|fail" /tmp/ci-output.log | head -20`

### Step 3: Codegen Check

If the project uses code generation AND DTOs/schemas/controllers changed:
1. Run the project's codegen command
2. Re-run validation to verify codegen didn't break anything

### Step 4: Runtime Startup Check (Medium complexity only)

Verify the app can boot. Start whichever side was changed in the background, wait 10–15 seconds, check output for startup errors (DI failures, missing providers, compilation errors). Kill the process afterward.

If startup errors found, treat like validation failures — fix and re-validate.

### Step 5: Test Coverage Check (Small/Medium complexity)

Check each test type based on what changed. Use `git diff --name-only` against main to identify changed files.

#### Unit Tests

1. **Find test files** adjacent to changed source files (Glob for test files near each changed file)
2. **Grep** existing tests for the changed function/class names
3. **If tests exist but don't cover the change**: delegate to a fresh agent: "Add unit test cases for [function/class] in [existing test file]. Extend, don't rewrite."
4. **If no tests exist and non-trivial logic changed** (not just a field rename or style fix): delegate to a fresh agent: "Create test file next to the source. Test [function/class] with [key scenarios]. Follow existing test patterns in the same module."

Run unit tests after any new/updated test files.

#### Integration Tests — only if DAO/query/multi-service logic changed

1. **Check** for existing integration tests covering the changed module
2. **If tests exist but don't cover the change**: delegate to a fresh agent to extend them
3. **If no tests exist and the change warrants them** (new query method, complex multi-service interaction): delegate to create one
4. **If the change is minor** (field addition, filter tweak) and existing tests pass: skip — note in Ship summary if you think coverage should be expanded later

### Step 6: Fix Loop

If validation, startup, or tests fail:

1. **Lint/format errors only?** Run autofix, then re-validate
2. **Type/build/test errors:** Fix directly (Trivial) or delegate to fresh agent with exact error output
3. After each fix round, run codegen check if applicable, then re-validate
4. **Max 2 fix rounds** — then escalate with structured handoff:

```
## Remaining Failures
### Fixed
- [what was fixed, which round]
### Still failing
- **Error**: [message] — **File**: [path:line] — **Suggested fix**: [steps]
### CI status
- Lint: PASS/FAIL — Types: PASS/FAIL — Build: PASS/FAIL — Tests: N/M passing
```

Use `AskUserQuestion` with header "Stuck": "Validation still failing after 2 fix rounds."
- "Try a different approach" — I'll rethink the implementation strategy
- "Escalate to /implement" — hand off to full architecture review
- "Show current state" — let me guide you manually

Do NOT retry the same approach a 3rd time — if it didn't work twice, the strategy is wrong.

**→ After validation passes, proceed to Phase 4.**

---

## Phase 4: Review

### Step 1: Code Review

Capture the changed file list from the diff against main.

**Trivial changes (1–2 files):** Review the diff yourself — no subagent needed. Check for: typos in the fix itself, accidental deletions, logic inversion, missed second occurrence. If anything looks off, fix it and re-validate (Phase 3 Step 2 only). This takes 30 seconds and catches "obvious fix" mistakes that cause rollbacks.

**Small changes (3–5 files):** Spawn a single `reviewer-agent` with: change summary and changed file list. **Tell the reviewer:** "This is a follow-up change — focus on correctness and regressions. CI already passed. Keep review proportional to change size."

**Medium changes (6–8 files):** Spawn 2–3 `reviewer-agent` instances in a **single message**, each reviewing a different dimension:

```
# Spawn ALL reviewers in a SINGLE message for parallel execution:

Agent(subagent_type="reviewer-agent", prompt="""
DIMENSION: Correctness & Regressions
Review ONLY for: logic bugs, null/undefined risks, state issues, off-by-one errors, missing error handling.
CHANGED FILES: [list]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed. Keep review proportional.
""", description="Review: correctness")

Agent(subagent_type="reviewer-agent", prompt="""
DIMENSION: Security & Edge Cases
Review ONLY for: injection risks, auth/authz gaps, input validation, data exposure, race conditions.
CHANGED FILES: [list]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed. Keep review proportional.
""", description="Review: security")
```

Add a 3rd reviewer (architecture/patterns) only if changes touch cross-module boundaries.

### Step 2: Process Results

Aggregate findings from all reviewers. Deduplicate (same file:line from multiple reviewers = single finding, keep highest severity).

- Any reviewer **CHANGES REQUIRED** → fix loop: delegate to fresh agent, re-validate (Step 2 only — skip autofix/startup), re-review with **fresh** reviewer (avoid anchoring). Max 1 fix round for follow-ups.
- All reviewers **APPROVED WITH MINOR** → note improvements in Ship summary. Only fix MEDIUM+ findings — delegate if any, then proceed.
- All reviewers **APPROVED** → proceed directly.

**→ Proceed to Phase 5.**

---

## Phase 5: Ship (WAIT)

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
4. Re-run validation (Phase 3 Step 2 only)
5. If 10+ lines changed, re-run reviewer (Phase 4). Max 1 review round for tweaks.
6. **Loop back to Step 1** — re-present summary and ask the Review question again. Do NOT skip ahead to Step 2.
7. Soft limit: after 3 tweak rounds, suggest creating a new `/follow-up` or `/implement` for remaining changes.

**If "Done":** Leave changes uncommitted, skip to cleanup.

**If "Looks good":** Proceed to Step 2.

### Step 2: Learn & Improve

Two jobs: save what we learned, suggest improvements. **Skip entirely for Trivial changes** (1-2 files, obvious fix). This runs BEFORE committing so that doc/rule changes are included in the commit.

#### Extract Learnings

Scan the conversation for learnings and save them with the appropriate memory type:
- **User corrections/preferences** — "don't do X", "do Y instead" → save as `feedback` memory (persists across sessions, influences future behavior)
- **Discovered problems** — bugs, gotchas, unexpected behaviors ��� save as `project` memory (shared context, benefits all team members)
- **Workarounds/patterns that failed** — documented approach didn't work, non-obvious fix required → save as `feedback` memory (operational knowledge, persists across sessions)
- **Validation failure resolutions** that required non-obvious fixes → save as `feedback` memory (operational knowledge for future sessions)

Before writing, check if an existing memory covers this topic — UPDATE rather than duplicate. Skip if nothing novel was discovered.

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

---

## Task Tracking

Use `TodoWrite` to track progress:
- Create todos at the start: Assess complexity, Implement, Validate, Review, Ship
- Mark each as `in_progress` when starting, `completed` when done
- For medium complexity: add the plan outline as a todo before implementation

## Definition of Done

For each change, confirm:

- [ ] Complexity assessed and routed correctly (trivial/small/escalated)
- [ ] Prior context loaded (spec, plan, concerns, notes, review-feedback from task directory if they exist)
- [ ] Implementation complete and matches `$ARGUMENTS`
- [ ] All tests pass (new and existing)
- [ ] No type/lint errors
- [ ] Code quality reviewed for edge cases and clarity
- [ ] User approved the change before shipping
- [ ] Change is committed or staged (or delivered for user to commit)

---

## When to Use This Skill vs. `/implement`

**Use `/follow-up`:**
- Change builds on existing code
- Scope is clear and bounded
- No new architecture needed
- Complexity is ≤ Medium

**Use `/implement`:**
- New major feature or component
- Ambiguous intent or scope creep risk
- New entity, endpoint, or auth concern
- 3+ modules coordinated
- Multiple decision points needed
- Full design review needed

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

### Trivial: Fix a typo
`/follow-up Fix typo in src/auth.ts line 42`
→ Read file, fix typo, validate tests pass, review (should be clean), ship

### Small: Add error message
`/follow-up Better error message when API returns 429`
→ Find call sites (likely 2–3 places), improve message, test error path works, review for clarity, ship

### Small: Debug a bug
`/follow-up Fix double-render bug in Dashboard component`
→ Reproduce, identify cause, apply fix, run tests, review for correctness, ship

### Medium: Refactor parameter
`/follow-up Rename userId to ownerId across UserService`
→ Outline which files change, ask user to confirm, search for all usages, refactor all call sites, validate tests, review for consistency, ship

### Too Large: Escalate
`/follow-up Add a new Notifications service with websocket support`
→ "This is a new module with async communication—should escalate to `/implement` for full design."
