---
name: geniro:follow-up
description: "Use when making small post-implementation changes that skip architecture. Assesses complexity (trivial/small/medium), implements, validates, reviews, ships. Escalates to /geniro:implement if scope is too large. Do NOT use for new features, new entities, new endpoints/pages, auth/permissions changes, new modules, or changes requiring architecture decisions."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, WebSearch]
argument-hint: "[description of the change]"
---

# Follow-Up Change Pipeline

**You are a coordinator.** Delegate ALL implementation to subagents — no exceptions, not even Trivial. Every code change goes through a subagent. You run shell commands (build, test, lint) and read their pass/fail output.

**Pipeline:** Assess → Implement → Simplify → Validate → Review → Ship (includes Learn & Improve before commit). **(WAIT)** phases require user input.

## Operating Rules

**AskUserQuestion**: Every user question uses `AskUserQuestion` with 2-4 labeled options (auto-adds "Other"). **Agent failure**: Retry once on timeout/error/empty-or-garbage result; if retry fails, escalate to user with context (skip / different approach / abort). **Codegen**: If the project uses codegen (OpenAPI, GraphQL, Prisma, etc.), run it after modifying generator inputs (DTOs, schemas, controllers); run manually if automated detection missed it — see CLAUDE.md or package.json.

## Subagent Model Tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly.

**Skill-specific mapping** (`/follow-up` never spawns `opus` directly — escalate to `/geniro:implement` or `/geniro:debug` for opus-tier work):

| Where used in this skill | Tier |
|---|---|
| Trivial Fast Lane implementation, Phase 4 validation, Phase 5 design-dimension review | `haiku` |
| Small/Medium implementation, Phase 3 simplify, Phase 5 single/multi-dimension reviewers, Phase 5 Step 1.5 adversarial-tester-agent (Medium only) | `sonnet` |

## Change Request

$ARGUMENTS

**If `$ARGUMENTS` is empty**, `AskUserQuestion` header "Change": "What would you like to change?" options "Describe the change" / "Fix a specific issue". Do not proceed until a change is provided.

---

## Phase 1: Assess

Determine what needs to change, how complex it is, and whether this skill can handle it.

### Step 1: Context Scan

1. **Prior planning context** — `Glob(".geniro/planning/*/")`, match current branch. If found, read `spec.md`, `plan-*.md`, `state.md`, `concerns.md`, `notes.md`, `review-feedback.md` to avoid re-discovery or contradicting prior decisions.
2. **Workflow integrations & custom instructions** — check `.geniro/workflow/*.md` for active integrations and argument detection rules; apply to `$ARGUMENTS`. Follow matching workflow instructions (fetch issue context, status transitions). Load `.geniro/instructions/global.md` and `.geniro/instructions/follow-up.md` as hard constraints.
3. **Read the change request** and identify likely files.
4. **Codebase scan** (Glob/Grep) to find exact files and patterns.
5. **Reuse Inventory** — search the change area for existing functions / components / types / hooks / helpers / configs the change could reuse; categorize each candidate REUSE-AS-IS / EXTEND / CREATE-NEW with `file:line` and a one-line justification (do NOT force-fit: if reuse requires adding a parameter or conditional, prefer local duplication and revisit at the third occurrence — Rule of Three). Produce a CONVENTIONS_BRIEF + REUSE_INVENTORY pair to pre-inline into the Phase 2 implementer agent prompt. **Skipped in Trivial Fast Lane** — rely on the implementer's in-prompt verify-before-creating instruction (see follow-up-reference.md).
6. **Read the files** that will be modified.
7. **Check state:** scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` — anchor on the current cwd's worktree and currently checked-out branch; do NOT `gh pr list` or `git checkout` to discover targets. Run `git rev-parse --show-toplevel`, `git branch --show-current`, `git log --oneline -5`, `git status --short`.

### Step 2: Complexity Assessment

Check for **hard escalation signals first**, then evaluate overall complexity. File count is a supporting signal, not the primary gate.

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

**File count is a smell detector, not a complexity detector.** A 2-file change adding a new entity is "Too large"; a 7-file change propagating an existing filter is "Medium." When file count is high, ask "why?" — the answer contains the real complexity signal.

### Step 3: Route to Lane

One `AskUserQuestion` routes the change. Record `lane` (Fast or Full) and reference it through the rest of the pipeline. Default to Full for anything the user did not explicitly opt into.

**Too large** → `AskUserQuestion` header "Scope":
- "Decompose into milestones" — output `/geniro:decompose [change request]` and stop (recommended for Big tasks that would exceed a single /implement run — 3+ modules, new subsystem, or 9+ files across unrelated slices)
- "Escalate to /geniro:implement" → output `/geniro:implement [change request]` and stop (single-pipeline implementation — best when the task is big but cohesive)
- "Proceed anyway" → continue as Full pipeline, treat as Medium (full validation + review)
- "Reduce scope" → ask what to cut, re-assess, loop back to Step 2

**Medium** → no question; proceed to Phase 2 Full (unchanged).

**Trivial or Small** with zero hard-escalation signals → `AskUserQuestion` header "Lane":
- "Fast Lane" — collapse optional phases (see Fast Lane Semantics below)
- "Full pipeline" — run every phase

Recommend: Fast for Trivial, Full for Small. If any hard-escalation signal is present, Fast Lane is unavailable — only Full-pipeline or Escalate are offered.

### Fast Lane — What it changes

**Skipped in Fast Lane:**
- Phase 2 Step 1 Plan presentation
- Phase 3 Simplify
- Phase 5 agent reviewer — use orchestrator diff review (Trivial pattern) for Trivial AND Small
- Phase 5 Step 1.5 Adversarial Edge-Case Tests (Medium-only anyway; reiterated for clarity)
- Phase 6 Step 2 Learn & Improve entirely
- Strategic Compact points (Phase 2 end, Phase 4 end)

**NEVER skipped in Fast Lane:**
- Agent delegation for implementation — Zero Direct Edits applies at every complexity and lane
- Phase 4 Validate — build + lint + test must run, or be confirmed via agent Checks Report
- Phase 6 Step 0 Pre-Ship Smoke Test offer (when conditions hold), Step 1 Review Gate, and Step 3 Ship question
- Hard escalation signals — if any are present, Fast Lane is not offered

**Model selection in Fast Lane:** Trivial impl agent: `model="haiku"` (mechanical edit). Small impl agent: `model="sonnet"` (unchanged).

**Escape hatch:** If Phase 5 orchestrator diff review finds anything ambiguous or potentially CRITICAL (logic inversion, suspected regression, unclear diff, or any doubt), escalate to a single Sonnet reviewer agent — do not proceed on Fast Lane alone.

### Step 4: UI Preview Gate (conditional — runs for both Fast and Full lanes)

If any file in the predicted affected-files list from Step 1 matches the UI-file detection rule in `skills/review/SKILL.md` §UI-file detection rule, run the procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` BEFORE Phase 2. Pre-inline the change request, the affected-files list, and 1-2 exemplar UI files. Phase 2 Step 2 implementation agents pick up the approved description via the `## UI Intent` slot in their prompt template (below). If the user picks "Adjust the plan instead" inside the procedure, fire `AskUserQuestion` with header "Adjust" to capture what to change in the approach, then: for Medium, feed the captured text into Phase 2 Step 1 Plan revision; for Trivial/Small, re-enter Phase 1 Step 1 Context Scan with the updated description. Skip this step entirely when no affected file matches.

**→ Proceed to Phase 2.**

---

## Phase 2: Implement

### Step 1: Plan (Medium complexity only)

Write a brief plan: each file, what changes, dependencies, risks. Present via `AskUserQuestion` header "Plan": "Looks good — proceed" / "Adjust — change the approach".

### Step 2: Execute

Spawn the implementation agent(s) using the templates in `${CLAUDE_SKILL_DIR}/follow-up-reference.md` §Phase 2 Step 2: Agent Delegation Templates. Select the template matching the complexity level (Trivial / Small / Medium). Medium decomposes into 2–3 parallel agents spawned in ONE response — all Agent() calls in the same assistant turn, NOT one per turn. If all files are tightly coupled (same module, sequential deps), use a single agent — don't force parallelism.

### Step 3: Completion Check

After agents report done, verify completion — do NOT read source code for correctness:

1. Run `git diff --name-only` and `git status --short` — confirm expected files changed (diff shows tracked, status shows untracked)
2. Check the agent's report covers all items in the change request
3. If missed or partial: delegate a follow-up agent with the gap description. Do NOT fill gaps yourself.

### Strategic Compact Point (Small/Medium Full pipeline only — skipped in Fast Lane and for Trivial)

After agents complete, context is loaded with pre-inlined file contents and reports. Before validation/review, checkpoint and suggest compaction:

1. Write state to `.geniro/follow-up-state.md`:
   ```
   complexity: [trivial/small/medium]
   change: [one-line description]
   phase: 2-complete
   changed-files: [list from git diff --name-only]
   branch: [current branch]
   ```
2. Tell the user:
   > Implementation complete. I recommend `/compact` now to free context for validation and review. After compacting, type `/geniro:follow-up continue` to resume from Phase 3.

**After compaction (or if skipped):** Read `.geniro/follow-up-state.md` and `git diff --name-only` to restore context. Proceed to Phase 3 (Medium) or Phase 4 (Small).

**DO NOT present a summary or ask "anything else?" here. Phases 3-6 have not run yet.**

---

## Phase 3: Simplify (Medium and "Proceed anyway" only — always skipped in Fast Lane)

**Purpose:** Code quality pass on changed files — catch AI anti-patterns before validation.

### Step 1: Spawn simplify agent

Spawn a **general-purpose** subagent with `model: "sonnet"`. The agent reads its own criteria — do NOT pre-read into orchestrator context:

```
Agent(model="sonnet", prompt="""
## Task: Simplify Changed Files
Make changed files cleaner, simpler, more consistent — without changing behavior.
Read and apply `${CLAUDE_PLUGIN_ROOT}/skills/deep-simplify/simplify-criteria.md`
Changed files: [list from git diff --name-only]
Apply P1+P2 findings, report P3 only. Zero behavior change. Do NOT git add/commit/push.
Do NOT modify files outside changed list. Never delete or weaken test assertions.
""", description="Simplify: changed files")
```

### Step 2: Verify after simplification

Spawn a validation agent (Phase 4 Step 2 template) to check simplification didn't break anything. If FAIL: revert (`git checkout -- .`), note "Simplification skipped — caused CI failures." Proceed to Phase 4.

**→ You MUST proceed to Phase 4 (Validate). DO NOT present a summary or ask "anything else?" — validation has not run yet.**

---

## Phase 4: Validate

**Your role:** verify the diff matches expectations, delegate heavy validation only if needed. First check agent reports for a `## Checks Report`. If ALL agents reported PASS for build+lint+test AND no code changed after their checks (Phase 3 skipped or didn't run), skip Step 2 — proceed to Step 3. If any FAIL, any missing Checks Report, or Phase 3 touched files, spawn the validation agent in Step 2. You do NOT run build/lint/test yourself or read source code.

### Step 1: Diff Check

Verify completeness via the diff:

```bash
git diff --name-only
git status --short | head -20
```

Confirm: (1) expected files created/modified, (2) no unexpected changes, (3) no untracked files that should be tracked. If missing or unexpected, delegate a fix agent before proceeding.

### Step 2: Validation Agent

Spawn a validation agent that runs the project's check suite. The agent runs commands; you read its pass/fail summary.

```
Agent(model="haiku", prompt="""
## Task: Run Full Validation Suite
Run the project's validation commands and report pass/fail results.

## Steps
1. Run autofix (lint --fix / format) per CLAUDE.md or package.json
2. Run full validation suite (build + lint + test) per CLAUDE.md
3. If codegen is used AND DTOs/schemas/controllers changed: run codegen, re-validate
4. [Medium only] Start app in background, wait 10-15s, check for startup errors (DI, missing providers). Kill after.
5. Test coverage: for each changed source in [list from git diff --name-only HEAD], verify a `.test.*` or `.spec.*` exists adjacent

## Report Format
Return EXACTLY this structure:
- autofix: PASS/FAIL [failing-file: path, error summary if fail]
- build: PASS/FAIL [failing-file: path, error summary if fail]
- lint: PASS/FAIL [failing-file: path, error summary if fail]
- test: PASS/FAIL [failing-file: path, error summary if fail]
- codegen: PASS/SKIP/FAIL [failing-file: path, error summary if fail]
- startup: PASS/SKIP/FAIL [failing-file: path, error summary if fail]
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
2. **Type/build/test failure** → spawn a fixer with the exact error output. Do NOT read source to diagnose.
3. **Missing test files** → spawn: "Create test file next to source. Follow existing patterns."
4. After each fix round, re-run validation (Step 2)
5. **Max 2 fix rounds** — then escalate: present the report. `AskUserQuestion` header "Stuck": "Try a different approach" / "Escalate to /geniro:implement" / "Show current state". Do NOT retry the same approach a 3rd time.

### Strategic Compact Point (Medium Full pipeline only — skipped in Fast Lane and for Trivial/Small)

Validation accumulated fix-loop context. Before spawning reviewers:

1. Update `.geniro/follow-up-state.md`: set `phase: 4-complete`
2. Tell the user:
   > Validation passed. For best review quality I recommend `/compact`. After compacting, type `/geniro:follow-up continue` to resume review.

**After compaction (or if skipped):** Read `.geniro/follow-up-state.md` and `git diff --name-only` to restore context.

**→ You MUST proceed to Phase 5 (Review). DO NOT present results or ask "anything else?" — review has not run yet.**

---

## Phase 5: Review

### Step 1: Code Review

Capture the changed file list from the diff against main.

**Trivial (any lane) and Small (Fast Lane):** Review the diff yourself — no subagent. Check for: typos in the fix, accidental deletions, logic inversion, missed second occurrence. If anything looks off, delegate the fix to an agent and re-validate. Do NOT fix code directly. If ambiguous or potentially CRITICAL, escalate to a single Sonnet reviewer (Fast Lane escape hatch).

**Small (Full pipeline, 3–5 files) and Medium (6–8 files):** Spawn reviewer-agent(s) using the templates in `${CLAUDE_SKILL_DIR}/follow-up-reference.md` §Phase 5 Step 1: Reviewer Agent Templates. Small = single reviewer. Medium = 2–3 reviewers spawned in ONE response — all Agent() calls in the same assistant turn, NOT one per turn. Each agent reads its own criteria; do NOT pre-read criteria into orchestrator context. Add a 3rd reviewer (architecture + tests + guidelines) only if changes touch cross-module boundaries. Add a 4th `haiku` reviewer for the design dimension when changed files include UI.

### Step 1.5: Adversarial Edge-Case Tests (Medium only — skipped for Trivial, Small, and all Fast Lane runs)

**Purpose:** Attacker-mindset pass that complements the reviewer-agents from Step 1. Where the Step 1 tests-dimension reviewer REPORTS coverage gaps, Step 1.5 AUTHORS NEW failing tests (F→P-verified: red today) for edge cases the Phase 2 implementer's happy-path tests missed.

**Action:** Spawn one `adversarial-tester-agent` (`model="sonnet"`) using the template in `${CLAUDE_SKILL_DIR}/follow-up-reference.md` §Phase 5 Step 1.5: Adversarial Tester Template. Pre-inline the diff, the shared checklist path `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`, 1-2 exemplar test files, the project test command, and Step 1 findings as hypothesis seeds.

**Orchestrator responsibilities after the agent returns:**
1. **Independently re-run the authored tests** — do NOT trust the agent's F→P self-report. Any test that passes today is deleted and removed from scope.
2. **Merge F→P-confirmed failing tests into the Step 2 aggregate.** Each kept test becomes a CRITICAL or HIGH finding (per the agent's severity) that Step 2's disposition loop handles via a fresh fixer agent.
3. **Cap applies:** the agent authors at most 10 tests. Overflow hypotheses surface in the Phase 6 ship summary under "Deferred".

**Skip Step 1.5 entirely when:**
- Lane is Fast (Fast Lane never authors adversarial tests)
- Complexity is Trivial or Small (amortization gate)
- Diff contains zero production-code files

**Anti-rationalization:**
| Your reasoning | Why it's wrong |
|---|---|
| "Medium is small enough that Step 1 covers it" | Step 1 reviewers REPORT gaps; Step 1.5 AUTHORS failing tests. Different lifecycle. Medium is exactly the tier where the extra cost is justified. |
| "I'll trust the agent's F→P self-report" | Run the authored tests yourself. F→P only counts when the orchestrator independently confirms the failure. |

### Step 2: Process Results

**Relevance evidence + orchestrator tagging (Medium only):** Spawn a `relevance-filter-agent` for evidence per finding, then the orchestrator decides KEEP vs FILTER from the dossier — do NOT delegate the tagging decision. Skip the filter entirely for Trivial/Small — scope too limited. If the agent fails, pass all findings through as KEEP (fail-open).

Aggregate findings. Deduplicate (same file:line across reviewers = single finding, highest severity). Then the orchestrator synthesizes findings and decides the disposition:

- **Any CRITICAL or HIGH finding (kept)** → fix loop: delegate to fresh agent, re-validate (Step 2 only), re-review with **fresh** reviewer (avoid anchoring). Max 1 fix round for follow-ups. If findings persist after the fix round: `AskUserQuestion` header "Review": "Try different approach" / "Accept with known issues" / "Escalate to /geniro:implement".
- **Zero CRITICAL, zero HIGH findings** → proceed directly; note any MEDIUM findings in Ship summary.

Disposition is an orchestrator decision based on aggregated evidence, not a reviewer verdict.

**→ Proceed to Phase 6.**

---

## Phase 6: Ship (WAIT)

Show a summary:

**Done. Here's what changed:**
- [file]: [what changed]
- Validation: PASS/FAIL
- Review: [disposition — "proceeded directly" / "1 HIGH fixed inline" / "fix-loop completed"]
- Test coverage: [covered / gaps noted / tests added]
- Smoke-test: [PASS / issues noted / skipped / n/a]   ← include only when Step 0 ran

### Step 0: Pre-Ship Smoke Test (conditional — runs for Fast AND Full lanes before Review Gate)

Runs only when BOTH conditions hold: (a) `git diff --name-only` contains at least one file matching the UI-file detection rule in `skills/review/SKILL.md` §UI-file detection rule, AND (b) Playwright MCP is available — check that `mcp__plugin_playwright_playwright__browser_navigate` is in your tool list. If either condition fails, skip silently to Step 1 and omit the Smoke-test line from the summary.

When both hold, fire a STANDALONE `AskUserQuestion` header "Smoke-test" as the only question in that call — never batch it with Step 3's Ship Decision question — options "Yes — walk through it" / "Skip — go to review". On "Yes", follow the 8-step procedure in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §Pre-Ship Visual Verification verbatim (detect URL → baseline snapshot → console/network → targeted interaction → responsive sweep → visual record → cleanup). Append the result to the summary as the Smoke-test line, then proceed to Step 1 — do not re-show the summary.

### Step 1: Review Gate (loop entry point)

`AskUserQuestion` header "Review":
- "Looks good" — I'm happy with the changes
- "Needs tweaks" — I want small adjustments (I'll describe)
- "Done" — leave uncommitted, I'll handle it myself

**If "Needs tweaks":**
1. `AskUserQuestion` header "Tweak": "Describe what to change" (free-text via Other)
2. **Assess** — if it expands scope (new files, new endpoints), warn via `AskUserQuestion` header "Scope": "Continue here" / "Escalate to /geniro:implement".
3. Delegate changes to an agent (never apply directly)
4. Re-run validation (Phase 4 Step 2 only)
5. If 10+ lines changed, re-run reviewer (Phase 5). Max 1 review round for tweaks.
6. **Loop back to Step 1** — re-present summary, re-ask Review. Do NOT skip to Step 2.
7. Soft limit: after 3 tweak rounds, suggest a new `/geniro:follow-up` or `/geniro:implement` for remaining changes.

**If "Done":** Leave uncommitted, skip to cleanup.  **If "Looks good":** Proceed to Step 2.

### Step 2: Learn & Improve

**Skipped entirely for Trivial changes and Fast Lane runs.** Runs BEFORE committing so doc/rule changes are included.

**Extract Learnings** (skipped for Trivial and Fast Lane runs): Follow the canonical rubric in `skills/_shared/learnings-extraction.md`. Bias hard toward flow, architectural, and recurring-mistake learnings; do NOT save narrow interface/field shapes, single-file behaviors, or facts re-derivable by reading the code. Apply the Reflect → Abstract → Generalize pre-pass before every save: if you cannot restate the finding one level up, drop it. Route per canonical (`feedback_*` memory for user-preference corrections, `project_*` memory for project facts, `learnings.jsonl` for transferable rules). UPDATE existing entries rather than duplicate. Skip if nothing novel.

**Suggest Improvements (WAIT) — skipped for Small, Trivial, and Fast Lane runs**; runs for Medium or "Proceed anyway" only. Follow the canonical routing in `skills/_shared/improvement-routing.md`: **code rules / coding conventions / style or naming patterns / file-pattern constraints → `.claude/rules/<scope>.md` with `paths:` glob** (Anthropic-native, file-scoped); skill-behavior quality gates / workflow / hard constraints → `.geniro/instructions/<skill>.md` (Geniro skill-scoped); CLAUDE.md is reserved for commands, project structure, and compaction-surviving gates; gotchas → `learnings.jsonl`; auto-enforceable patterns → project rules/hooks. Plugin-internal paths (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope — use `/improve-template`.

### Step 3: Ship Decision

**NEVER run `git commit` or `git push` without reaching this step and the user's explicit choice via `AskUserQuestion` below.** Only reach this step after the user chose "Looks good" in Step 1.

`AskUserQuestion` header "Ship":
- "Commit" — add to current branch (implementation + docs + rule updates)
- "Commit + push" — commit and push to remote
- "Commit + PR" — commit, push, create pull request
- "Leave as-is" — don't commit, I'll handle git myself

If the user picked "Commit + PR", immediately fire a SECOND `AskUserQuestion` with header "PR state" and exactly 2 options before committing:
- **Draft PR** — `gh pr create --draft`; blocks merge and suppresses CODEOWNERS review requests until promoted with `gh pr ready`. Some orgs skip CI on drafts.
- **Ready for review** — `gh pr create`; requests review immediately.

Execute the user's choice by appending `--draft` for "Draft PR" (omit for "Ready for review"). `--draft` is incompatible with `--web` — create first, then `gh pr view --web` to open in browser.

**Commit message:** conventional commits, e.g. `fix(module): description of what changed`.

### Integration Updates

If `.geniro/workflow/*.md` specifies completion actions (issue status, PR linking), follow them after the user commits. Always ask before changing external state — never auto-update.

### Cleanup

Kill orphaned background processes from validation (startup checks, dev servers, etc.).

**→ Pipeline complete.**

---

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "The change is too small for full review" | Small changes cause production incidents too. Follow the process. |
| "I already know how to do this" | Skills encode process knowledge beyond individual capability. Follow them. |
| "I'll create a new helper / component / type for this — quicker than checking what exists" | Run the Reuse Inventory in Step 1 (Glob/Grep for analogues with `file:line`). Convention drift is the #1 AI failure mode. Categorize REUSE-AS-IS / EXTEND / CREATE-NEW; if reuse requires adding a parameter or conditional to fit, prefer local duplication and revisit at the third occurrence (Rule of Three). |
| "The tests are obviously fine" | Run them. "Obviously fine" is the #1 predictor of broken tests. |
| "This doesn't need a complexity assessment" | The assessment takes 30 seconds. Skipping it risks building something that should be `/geniro:implement`. |
| "I can do this in one step" | Multi-step exists for a reason. Each step catches different failures. |
| "The user seems impatient" | Cutting corners costs more time than following the process. |
| "I'll implement this Medium change in one agent" | If files span 2 modules, decompose into parallel agents. Single-agent Medium misses parallelism. |
| "One reviewer is enough for Medium" | Single reviewers miss cross-dimensional issues. Spawn 2–3 in parallel — it's the same wall-clock time. |
| "I'll spawn agents one at a time" | All parallel agents MUST be spawned in ONE response — multiple Agent() calls in the same assistant turn. Separate turns = no concurrency, full wall-clock latency per agent. |
| "I'll implement this directly — it's straightforward / Trivial / I'll quickly fix it myself" | Orchestrator tokens are the most expensive resource. ALL changes MUST be delegated to subagents — no exceptions, not even Trivial. |
| "I'll just quickly edit these files myself since I already read them" | Reading files for assessment is fine. Writing code is implementation — delegate it, for ALL changes without exception. The assessment context goes into the agent prompt. |
| "Spawning an agent is overkill / I can fix this type error faster myself" | Every change, even 1-line fixes, goes through agents regardless of complexity. Context you accumulate reading source to "quickly fix" always exceeds the cost of spawning and degrades coordination for Phases 5-6. |
| "I noticed a bug during validation — I'll fix it now since I'm already here" | Bug-finding is Phase 5 (Review). Phase 4 runs commands and reads pass/fail output. If automated checks pass, the code moves to Review where fresh-context agents find bugs. Fixing bugs in Phase 4 steals Review's job and accumulates context that degrades your coordination. |
| "The user said 'looks good' so I'll commit and push" | NEVER run git commit or git push without the user choosing a specific ship option via AskUserQuestion in Phase 6 Step 3. "Looks good" means proceed to the ship question — not auto-commit. |
| "I'll pick Fast Lane silently — it's obviously Trivial" | Fast Lane is the user's choice, not the orchestrator's. Ask via AskUserQuestion in Phase 1 Step 3 — silent routing removes the safety gate the user asked for. |
| "This Medium change has simple logic — I'll offer Fast Lane" | Only Trivial or Small with zero hard-escalation signals qualify. Medium always runs Full. File-count-adjacent Small changes that touched any escalation signal also get Full. |
| "We're in Fast Lane — I'll fix this one-liner directly instead of spawning an agent" | Delegation is mandatory at every complexity level and every lane. Fast Lane collapses phases; it does not permit orchestrator edits. Any exception becomes rationalization (5 audits eliminated the 'Trivial inline' exception). |
| "Fast Lane reviewer spotted a bug — I'll fix it here" | Still delegate fixes to a fresh agent. Fast Lane reduces review depth, not accountability. If the diff-review raises any doubt, escalate to a Sonnet reviewer per the Fast Lane escape hatch. |
| "I'll upgrade this haiku spawn to sonnet just to be safe" | Tier is matched to task nature, not to risk appetite. Upgrading mechanical-task agents to sonnet defeats the cost rationale and signals drift. If the task genuinely needs reasoning, re-classify it using the Subagent Model Tiering table — don't silently upsize. |
| "Validation passed and the diff is small — I'll skip the smoke-test offer" | Phase 6 Step 0 is conditional on UI file + Playwright MCP presence, not on change size or confidence. When both conditions hold, fire the `AskUserQuestion` — the user chooses whether to walk through it, not you. |
| "Medium change but no obvious edge cases — I'll skip Step 1.5" | Step 1.5 is mandatory for Medium. The adversarial-tester-agent discovers edge cases the reviewers miss precisely because they're not obvious. Orchestrator does not pre-filter which Mediums get it. |

---

## Task Tracking

Use `TodoWrite`: create todos (Assess, Implement, Simplify, Validate, Review, Ship) at start. Mark `in_progress` → `completed` as phases run. For Medium: add plan outline as todo before implementation.

## Definition of Done

- [ ] Complexity assessed and routed correctly
- [ ] Prior planning context loaded if available
- [ ] Implementation matches `$ARGUMENTS`
- [ ] Simplification run (Medium Full) or skipped (Trivial/Small/Fast Lane)
- [ ] All tests pass; no type/lint errors
- [ ] Code quality reviewed
- [ ] Relevance filter applied (Medium only)
- [ ] Adversarial edge-case tests run (Medium only) or skipped (Trivial/Small/Fast Lane)
- [ ] User approved before shipping
- [ ] Change committed or delivered for user to commit

---

## When to Use This Skill vs. `/geniro:implement` or `/geniro:decompose`

**`/geniro:follow-up`:** Builds on existing code, scope clear and bounded, no new architecture, complexity ≤ Medium.
**`/geniro:implement`:** New feature/entity/endpoint/auth, ambiguous intent, 3+ modules, needs design review.
**`/geniro:decompose`:** Big task that would exceed a single /implement run (score 9+ on complexity, >15 plan steps, or multiple unrelated vertical slices). Produces a master plan + 3-7 milestone files that /implement consumes one at a time.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Validation fails after 2 fix rounds | Present structured handoff to user |
| Change larger than expected | Escalate to `/geniro:implement` |
| Agent re-reads files already scanned | Pre-inline file contents from Phase 1 |
| Reviewer finds architectural issues | Escalate to `/geniro:implement` with findings |

---

## Examples

- **Trivial:** `/geniro:follow-up Fix typo in src/auth.ts line 42`
- **Small:** `/geniro:follow-up Better error message when API returns 429`
- **Medium:** `/geniro:follow-up Rename userId to ownerId across UserService`
- **Too Large (cohesive):** `/geniro:follow-up Add Notifications service with websockets` → Escalate to `/geniro:implement`
- **Too Large (multi-slice):** `/geniro:follow-up Migrate auth to OAuth + add MFA + rewrite session storage` → Decompose via `/geniro:decompose`
