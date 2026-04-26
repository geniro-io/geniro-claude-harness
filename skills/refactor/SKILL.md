---
name: geniro:refactor
description: "Use when restructuring code for better organization, reducing tech debt, or improving patterns while guaranteeing zero behavior change. Ideal for modularization, test refactoring, or pattern consolidation after implementation."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite]
argument-hint: "[what to refactor and why]"
---

# Refactor with Test Verification

Safe incremental refactoring that validates behavior is preserved at every step. Restructures code for better organization, reduces tech debt, and improves patterns without changing observable behavior.

## When to use

- Extracting shared logic from multiple modules
- Restructuring a module for clarity or testability
- Consolidating similar patterns across files
- Reducing coupling between components
- Improving module organization within a package

## When NOT to use

- For behavioral changes or feature additions (use `/geniro:implement` instead)
- To optimize performance (use `/geniro:deep-simplify` and measure first)
- To add error handling not previously present
- To reorganize without clear architectural benefit

## Subagent Model Tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly.

**Skill-specific mapping** — refactor work is mostly mechanical pattern application; Sonnet handles ~90% of cases:

| Spawn | Tier | When |
|---|---|---|
| `refactor-agent` (LOW or MEDIUM risk) | `sonnet` | Default — pattern application, file moves, rename, extract method |
| `refactor-agent` (HIGH risk) | `opus` | 15+ files OR cross-module architectural restructure OR public API surface changes |
| `relevance-filter-agent` | `sonnet` | Adversarial validation against repo conventions |
| Phase 5 reviewer (general-purpose) | `sonnet` | Independent diff review for Medium and Large tiers |

## Agent Failure Handling

If any delegated agent fails (timeout, error, empty/garbage result): retry once with the same prompt. If the retry also fails:
- **Phase 2 evidence-gathering agent (refactor-agent, relevance-filter-agent):** proceed without the failed agent's output; note "Agent [name] failed — [dimension] not available" in the Phase 5 completion summary, and offer user the choice via `AskUserQuestion` header "Partial evidence": "Abort refactor" / "Continue with partial evidence (risky)". Default: Abort.
- **Phase 4 execution agent (refactor-agent):** do NOT silently skip — revert all changes (`git checkout -- .` with user confirmation per Phase 5 Step 1) and escalate to the user with failure context.
- **Phase 5 reviewer-agent:** note the failure in the completion summary and proceed (fail-open); warn the user that independent review did not complete.

---

## Complexity Gate

Match refactor depth to task risk. **File count is a supporting signal, not the primary gate.** Score the task across five dimensions, then check for any hard escalation signal.

### Step 1: Score Complexity Dimensions

| Dimension | Low (0) | Medium (1) | High (2) |
|-----------|---------|------------|----------|
| **Task type** | Mechanical (rename, extract method) | Pattern consolidation | Structural (module moves, cross-boundary) |
| **Cross-boundary scope** | 1 module | 2 modules | 3+ modules or cross-stack |
| **Public surface touched** | None | Internal module exports | Public API |
| **Scale** | ≤5 files | 6-15 files | 15+ files |
| **Test coverage in scope** | Strong | Partial | None-or-unknown |

**Score: sum of all dimensions (0-10)**
- **0-3 → Small**
- **4-6 → Medium**
- **7+ → Large**

### Step 2: Apply Tier Behavior

| Tier | Behavior |
|------|----------|
| **Small** | Skip Phase 3 relevance-filter (scope too narrow to matter). Skip Phase 5 independent reviewer. Proceed through Phases 1-5 with lightweight gates. |
| **Medium** | Full pipeline as specified (relevance-filter + reviewer-agent). |
| **Large** | Recommend running `/geniro:decompose` first to split the refactor into independently shippable milestones; refactor then runs one milestone at a time against an approved plan. If the user wants to proceed without decomposition, require explicit confirmation via `AskUserQuestion` header "Scope": "Run /geniro:decompose first" (description: "Split the refactor into 3-7 milestones so each one can be reviewed and shipped independently") / "Proceed without a plan (risky)". On "Proceed without a plan", Large runs the Medium pipeline (full relevance-filter + independent reviewer-agent in Phase 5). The only difference is the user has accepted the added risk of proceeding without architectural review. |

### Hard Escalation Signals (any ONE escalates)

| Signal | Why it escalates |
|--------|-----------------|
| Behavioral change required | Not a refactor — use `/geniro:implement` |
| New tests required to cover untested code | Add tests first via `/geniro:implement` or escalate |
| Signature/semantics change on public API | Cross-stack coordination — use `/geniro:implement` |
| Auth, crypto, or payment code touched | Owner review required — escalate |
| Ambiguous intent (multiple valid shapes) | Use Claude Code's built-in plan mode (Shift+Tab twice) to draft an approach first, or escalate to `/geniro:implement` |
| Config/migration regeneration needed | Runtime failure modes — use `/geniro:implement` |
| Touching test assertions (not just test imports) | Not refactoring — use `/geniro:implement` |

Any signal → `AskUserQuestion` header "Scope": "Escalate to suggested skill" / "Proceed anyway (treat as Large)" / "Reduce scope". Default to escalate.

---

## State & Resume Semantics

On skill start, `Glob(".geniro/refactor/state.md")`. If present, read it and offer resume via `AskUserQuestion` header "Resume": "Resume from phase [N]" / "Start fresh (discard state)". Otherwise create it with an initial header after Phase 1.

**State file schema (`.geniro/refactor/state.md`):**

```
phase: 1|2|3|4|5
tier: Small|Medium|Large
scope-files: [...]
smells-detected: N
plan-approved: bool
steps-completed: [...]
steps-blocked: [...]
```

State is written on all tiers for consistency. Only strategic compact points are tier-gated (Medium/Large only).

**Strategic compact points:**

- **After Phase 2** (plan built, before Phase 3 approval): write checkpoint, tell user:
  > Plan ready. I recommend `/compact` now to free context for execution. After compacting, type `/geniro:refactor continue` to resume from Phase 3.
- **After Phase 4** (execution complete, before Phase 5 review): same pattern, resume from Phase 5.

**On resume:** read state.md and the scope-files list, skip to the next incomplete phase. The state file is cleaned up at the end of Phase 5.

---

## Process

### Phase 1: Scope & Context

1. Parse `$ARGUMENTS` to understand what is being refactored and why
2. Use Grep and Glob to find all related files
3. Read all files in scope to understand current organization, dependencies, imports, and test coverage
4. **Prior planning/knowledge context** — scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` (anchor on cwd's worktree + current branch; no `gh pr list` / `git checkout` discovery). Check these artifacts and load relevant ones: `.geniro/planning/*/` (match current branch; if found, read `spec.md`, `plan-*.md`, `state.md`, `concerns.md`, `notes.md`), `.geniro/workflow/*.md` (active integrations), `.geniro/knowledge/learnings.jsonl` (grep for scope-file keywords to surface relevant gotchas), and current git state (`git rev-parse --show-toplevel`, `git branch --show-current`, `git log --oneline -5`, `git status --short`).
5. Read any project convention files referenced in CLAUDE.md (coding standards, architecture docs) — understanding project patterns prevents flagging intentional designs as smells
6. Load custom instructions from `.geniro/instructions/global.md` and `.geniro/instructions/refactor.md`. Read any found. Apply rules as constraints, additional steps at specified phases, and hard constraints.

**Step 7 (final): Baseline validation.** Run the project's validation suite once (read command from CLAUDE.md).
- If red: `AskUserQuestion` header "Baseline": "Fix the broken tests first (stop refactoring)" / "Proceed anyway — existing failures are out of scope (risky)". Default to stop.
- If no tests exist at all: escalate immediately — "Cannot refactor safely without tests. Use `/geniro:implement` to add coverage first."
- If tests green: record the passing-state fingerprint (test count) in `state.md` and proceed.

### Phase 2: Analyze (subagent) + Plan (orchestrator)

Spawn a refactor-agent to detect smells and count consumers — evidence only. The orchestrator then classifies risk, orders the plan, and marks HIGH-risk steps for user confirmation.

```
Agent(subagent_type="refactor-agent", model="sonnet", prompt="""
You are analyzing code for refactoring. Your task:

WHAT TO REFACTOR: $ARGUMENTS

FILES IN SCOPE:
[list the files you read in Phase 1]

PROJECT CONVENTIONS:
[paste any relevant conventions from CLAUDE.md or project docs]

PHASE: EVIDENCE GATHERING ONLY.
- Execute ONLY your Phase 1 (Code Smell Detection). Skip all planning, risk scoring, and ordering.
- Skip Phase 2 (Refactoring Plan), Phase 3 (Atomic Application), and Phase 4 (Reporting) entirely.
- Do NOT use Write or Edit tools during this invocation. You are producing raw evidence, not a plan.
- Return smells + consumer counts as your final output.
- For every detected smell, also run the canonical **Existing Abstraction Audit** at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` — apply its Procedure (Grep designated helper directories, categorize REUSE-AS-IS / EXTEND / NO-ANALOGUE, force-fit guard, Rule of Three). Emit candidates inline alongside each smell using the audit's Output format (`reuse-as-is: <file:line>`, `extend-existing: <file:line> — <one-line justification>`, or `no-analogue: rule-of-three=<met|not-met>, call-sites=N`). If a viable extension exists, the orchestrator may prefer it over the smell-local transformation.

Run all 6 smell detection categories (duplication, long methods, god classes, dead code, tight coupling, type/import issues). For each smell, count consumers with Grep (files that import/reference the symbol).

Return as a flat list:
- Smell 1: [type, file:line references, proposed transformation, consumer count, files affected]
- Smell 2: ...
- Public surface notes: [smells that change public API signature, module export, or shared type — orchestrator will treat these as HIGH risk regardless of consumer count]

Do NOT classify risk (LOW/MEDIUM/HIGH). Do NOT order the smells. Do NOT flag steps for user confirmation. Those are orchestrator decisions.
""")
```

After the agent returns, the orchestrator builds the plan:

1. **Classify risk per smell** (lookup rule):
   - 1-3 consumers → LOW
   - 4-9 consumers → MEDIUM
   - 10+ consumers → HIGH
   - Public API / module export / shared type change → HIGH (overrides consumer count)
2. **Order the plan**: safer transformations first (LOW → MEDIUM → HIGH). Within the same tier, group by file to minimize re-reads.
3. **Mark HIGH-risk steps for user confirmation** (presented via `AskUserQuestion` in Phase 3).
4. **Build the final plan** with: smells, ordered steps, risk per step, consumer counts, files that will change, what will NOT change (public APIs, DB schema, test behavior), and `max_risk` (max across all step risks, used to select execution model in Phase 4).

Update `state.md`: `phase: 2`, `smells-detected: N`, `tier: <Small|Medium|Large>`.

### Phase 3: Approval

**Relevance evidence + orchestrator tagging** (Medium and Large only — Small skips this step): Before presenting the plan, spawn a `relevance-filter-agent` to gather evidence on detected smells against repo conventions, then **you (the orchestrator) decide KEEP vs FILTER yourself** from the dossier — do NOT delegate the tagging decision:

```
Agent(subagent_type="relevance-filter-agent", model="sonnet", prompt="""
FINDINGS: [smells detected by refactor-agent, with file:line references and risk levels]
CHANGED FILES: [files in refactoring scope from Phase 1]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
CONVENTION FILES: [content of CONTRIBUTING.md, ADRs, architecture docs if they exist]

Gather evidence for each detected smell against this repo's actual patterns:
1. Convention alignment — is this "smell" actually the repo's chosen pattern?
2. Over-engineering — would fixing this smell introduce more complexity than it removes?
3. Intentional pattern — does the flagged pattern exist deliberately in 3+ other files?

Return an evidence dossier per smell (ALIGNS/CONTRADICTS/NEUTRAL, APPROPRIATE/OVER-ENGINEERED, ISOLATED/WIDESPREAD). Do NOT tag smells KEEP or FILTER — return evidence only; the orchestrator decides.
""")
```

After the dossier returns, synthesize it yourself: for each smell, weigh convention-alignment, over-engineering, and pattern-frequency evidence and tag KEEP or FILTER. Remove FILTERED smells from the plan before presenting to user; note them in the results. If the agent fails, pass all smells through as KEEP (fail-open).

Review the agent's plan:
- If any steps are **HIGH risk**: present them to user via `AskUserQuestion` and wait for confirmation before proceeding
- If all steps are LOW/MEDIUM: present the plan summary and proceed

Update `state.md`: `phase: 3`, `plan-approved: true`.

**Strategic Compact Point (Medium and Large only).** See "State & Resume Semantics" above. After compaction, resume from Phase 4.

### Phase 4: Execute

Spawn the refactor-agent to execute the approved plan:

**Pick model from approved plan:** use `model="opus"` when `plan.max_risk == "HIGH"`, otherwise `model="sonnet"`.

```
Agent(subagent_type="refactor-agent", model="<sonnet|opus per risk>", prompt="""
You are executing a refactoring plan. Your task:

APPROVED PLAN:
[paste the plan from Phase 2, marking any HIGH steps the user rejected]

VALIDATION COMMAND: [test command from CLAUDE.md]
AUTOFIX COMMAND: [autofix command from CLAUDE.md, if any]
BACKPRESSURE: source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Tests" "<validation_cmd>". If unavailable, pipe through tail -80.

Execute each step following the Step Execution Protocol in your agent definition.

CRITICAL RULES:
- One logical transformation per step
- Run validation after each step
- If a step fails 3 times: REVERT it, mark as BLOCKED, and CONTINUE to the next step
- Do NOT stop the entire session because one step is blocked
- No git operations (no add, commit, push, checkout)

Return a structured report of what was applied, what was blocked, and final validation status.
""")
```

**Session-level cap:** After execution returns, count the ratio of BLOCKED to executed steps (post-user-rejection; i.e., denominator = approved plan steps minus user-rejected HIGH-risk steps). If ≥30% BLOCKED: stop and escalate via `AskUserQuestion` header "Stuck": "Keep what worked and escalate the rest" / "Revert all changes" / "Force-continue (not recommended)". Do NOT proceed to Phase 5 automatically when this cap triggers.

Update `state.md`: `phase: 4`, `steps-completed: [...]`, `steps-blocked: [...]`.

**Strategic Compact Point (Medium and Large only).** See "State & Resume Semantics" above. After compaction, resume from Phase 5.

### Phase 5: Review Results

#### Step 1: Diff sanity (all tiers)

Run `git diff --name-only` and `git diff --stat`. Cross-check the refactor-agent's self-reported file list against the actual diff — flag mismatches.

If the agent's final validation failed, fire `AskUserQuestion` header "Revert":
- "Revert all changes" — safe default, matches current behavior
- "Show me the diff first" — print `git diff --stat` and re-ask
- "Keep changes for debugging" — leave uncommitted, print recovery guidance

Default: Revert all changes. On "Revert all changes", run `git checkout -- .` and report failure.

#### Step 2: Independent review (Medium and Large only — skip for Small)

Spawn a fresh reviewer-agent. The agent reads its own criteria — do NOT pre-read into orchestrator context:

```
Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
## Review: Refactor Diff
This is a refactor — behavior MUST be unchanged. CI already passed. Focus on invariants, not style.

DIFF: [paste git diff output]
AGENT SELF-REPORT: [refactor-agent's structured report]
PROJECT CONVENTIONS: [paste relevant conventions from CLAUDE.md]

## Focus Areas
- Accidental public-API changes
- Test assertion mutations (imports-only changes are fine; assertion changes are NOT)
- Invariant drift (error shapes, return types, null-vs-undefined, ordering)
- New coupling introduced by extraction/move
- Dead-code removal that actually had references

## Review Criteria
Read and apply these criteria files:
- `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/architecture-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`

Report findings with severity (CRITICAL/HIGH/MEDIUM) and confidence. Return findings as evidence. Do NOT emit an overall verdict — the orchestrating skill synthesizes findings and decides disposition.
""", description="Review: refactor diff")
```

**Orchestrator disposition logic:**
- **Any CRITICAL or HIGH** → fix loop (max 1 round): spawn fresh refactor-agent to address specific findings, re-review with fresh reviewer.
- **Only MEDIUM** → note in completion summary; proceed.
- **None** → proceed.

#### Step 3: Present Completion Summary

```
## Refactor Complete

### Transformations Applied (N)
- [file:line] — [what changed] — risk: [LOW/MEDIUM/HIGH] — consumers: N

### Blocked Steps (N)
- [file:line] — [what was attempted] — reason: [failure summary]

### Filtered by Relevance (N — omit section for Small tier; relevance filter not run)
- [smell] — [reason filtered]

### Review Findings
- CRITICAL: N, HIGH: M, MEDIUM: K
- Disposition: [proceeded / 1-round fix loop / escalated]

### Validation
- Tests: PASS/FAIL
- Baseline delta: [before→after test count]

### Files Modified: N
- [file path]: [one-line summary]

### Deferred
- [P3 item or user-rejected HIGH step]
```

Delete `.geniro/refactor/state.md` at the very end of Phase 5.

After deleting state.md, tell the user explicitly: "Refactor complete — the diff is in your working tree. Commit it yourself, or run `/geniro:follow-up` to ship with a review gate."

## Git Constraint

Do NOT run `git add`, `git commit`, or `git push`. The orchestrating workflow handles version control. Exception: `git checkout -- .` is permitted in Phase 5 for reverting failed changes — this is an orchestration-level revert, not a version control operation.

## Anti-rationalization constraints

| Your reasoning | Why it's wrong |
|---|---|
| "This smell is too small to fix" | If the plan says fix it, fix it. Small smells compound. |
| "I'll batch multiple transformations" | One atomic transformation at a time. Always. |
| "Tests are passing so I'll skip the blocked step protocol" | The protocol exists for the NEXT failure. Follow it. |
| "This refactoring needs a behavior change" | Then it's not a refactoring. Use `/geniro:implement` instead. |
| "I'll skip reading project conventions" | You'll flag intentional patterns as smells. Read first. |
| "This duplication needs a new shared helper" | Run the Existing Abstraction Audit first. If a utility / service / hook already exists nearby that could absorb this duplication via a small extension, prefer extending it. Only create a new shared helper when no analogue exists OR when extending the existing one would require adding a parameter or conditional that complicates it (Rule of Three: revisit at the third occurrence; until then prefer local duplication over forced abstraction). |
| "All detected smells are real issues" | Generic smell categories flag intentional repo patterns. Without filtering against THIS repo's conventions, you'll refactor code that was designed that way on purpose. |
| "This is just a refactor" | Refactors break things. Tests and review apply equally. |
| "I'll spawn agents one at a time" | All parallel agents MUST be spawned in ONE response — multiple Agent() calls in the same assistant turn. Separate turns = no concurrency, full wall-clock latency per agent. |
| "The user said go fast — skip phases" | Phase skipping is tied to Complexity Gate tier, not user impatience. Small-tier already skips appropriately. |
| "I noticed a bug mid-refactor, I'll fix it" | That's feature work. Note it for `/geniro:follow-up` or `/geniro:implement` and stay in refactor scope. |
| "This change is obviously safe" | "Obviously safe" is the #1 predictor of broken builds. Run validation. |
| "I'll upgrade this sonnet spawn to opus just to be safe" | Model tier is task-nature-matched, not risk-appetite-matched. Re-classify via Subagent Model Tiering table; don't silently upsize. |

## Learn & Improve

After refactoring is complete, extract knowledge and suggest improvements.

### Extract Learnings

Follow the canonical rubric in `skills/_shared/learnings-extraction.md`. Bias hard toward flow, architectural, and recurring-mistake learnings; do NOT save narrow interface/field shapes or facts re-derivable by reading the code. Apply the Reflect → Abstract → Generalize pre-pass before every save: if you cannot restate the finding one level up, drop it.

**Refactor-specific triggers (supplemental bias, not replacement rubric):**
- Blocked transformations → `project` memory (architectural pressure points)
- Convention discoveries from codebase reading → `project` memory
- User corrections ("don't refactor that, it's intentional") → `feedback` memory
- Surprising coupling revealed during execution → `project` memory

UPDATE existing memories instead of duplicating. Skip if nothing novel.

### Suggest Improvements (project scope only)

Check if the refactoring revealed improvement opportunities. Follow the canonical routing in `skills/_shared/improvement-routing.md` — refactoring most often surfaces (a) **undocumented coding conventions / style patterns used consistently across the codebase** → route to **`.claude/rules/<scope>.md`** with `paths:` glob frontmatter (Anthropic-native, file-scoped — auto-loads when matching files are touched); (b) **surprising coupling between modules** → `learnings.jsonl`; (c) **patterns that should be auto-enforced** → project rules/hooks; (d) **skill-behavior constraints the user enforced manually during refactor** → `.geniro/instructions/refactor.md`. Plugin-internal paths (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope — use `/improve-template`.

## Task Tracking

Use `TodoWrite` to expose per-phase progress. At skill start, create phase-level todos: Scope&Context, Analyze&Plan, Approval, Execute, Review. During Phase 4, add dynamic per-step todos derived from the approved plan. Mark `in_progress` → `completed` as phases run. At most ONE todo is `in_progress` at a time.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Baseline validation never passes | Escalate: tests must be fixed before refactoring can proceed safely |
| Refactor-agent blocked on ≥30% of steps | Session-level cap hit — stop and escalate; likely scope too large or conventions misread |
| Relevance filter rejects >50% of smells | Likely scope-convention mismatch — confirm with user before proceeding |
| User rejects all HIGH-risk steps | Empty remaining plan → ask whether to proceed with LOW/MEDIUM only or abort |
| Cross-module coupling discovered mid-execution | Follow Blocked Step Protocol; do NOT expand scope mid-session — note for follow-up refactor |

## Definition of Done

- [ ] All tests pass before and after each change
- [ ] Test suite proves behavior is identical
- [ ] Code organization/clarity improves
- [ ] No public API changes
- [ ] All imports and references updated
- [ ] No new dependencies introduced
- [ ] Blocked steps documented with failure reasons
- [ ] Rationale documented for each transformation
- [ ] Relevance filter applied (smells checked against repo conventions)
- [ ] Learnings extracted and saved
- [ ] Improvement suggestions presented
- [ ] Prior context scan completed
- [ ] Baseline validation passed
- [ ] State persisted and cleaned up
- [ ] Independent reviewer ran (Medium+ only)
- [ ] Completion summary presented

## Example invocations

```
/geniro:refactor Extract shared validation logic from auth and user modules
/geniro:refactor Consolidate test helpers in utils/ to single module
/geniro:refactor Split 1000-line service into focused domain modules
/geniro:refactor Reduce coupling between database and business logic layers
```
