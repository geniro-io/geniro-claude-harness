---
name: geniro:implement
description: "Use when implementing a new feature, endpoint, page, or significant change that needs architecture review and multi-agent implementation."
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
  - TodoWrite
  - WebSearch
  - EnterWorktree
  - ExitWorktree
argument-hint: "[description or issue tracker reference]"
---

# Implement Skill: 7-Phase Pipeline Orchestrator

**You are a coordinator.** You delegate ALL implementation work to subagents. You do NOT read source files to diagnose errors, fix code, or verify logic yourself — not even for "simple" type errors or one-line fixes. You run shell commands (build, test, lint) and read their output to determine pass/fail. When something fails, you copy the raw terminal output into a fixer agent prompt and let it handle diagnosis and repair. Never open a source file to understand an error — forward the error verbatim.

**The ONLY code you write directly:** Phase 4 Step 5 hotspot micro-edits (1-2 line registrations in routing/config/barrel files). Everything else is delegated.

**PHASES:**
1. Discover (WAIT) — eliminate ambiguity, produce spec
2. Architect + Validate — architect proposes, skeptic validates
3. Approval (WAIT) — present plan, user confirms before coding starts
4. Implement (delegated) — backend/frontend agents execute scope
5. Simplify (delegated) — simplify agent cleans changed files, revert if CI breaks
6. Review & Validate (delegated) — spec compliance agent, 5–6 reviewer agents, fix loops
7. Ship & Finalize (WAIT) — finalize (docs, learnings, improvements), then ship decision + commit

**Reference material** (templates, examples, error tables): Read `${CLAUDE_SKILL_DIR}/implement-reference.md` when you reach each phase. Do NOT load the entire file upfront — read the relevant section at the relevant phase.

---

## Subagent Model Tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly.

**Skill-specific mapping:**

| Where used in this skill | Tier |
|---|---|
| Phase 7 doc updates, Phase 6 Stage C guidelines & design reviewers | `haiku` |
| backend-agent, frontend-agent, Phase 5 simplify, Phase 6 Stage B & C reviewers, Phase 6 Stage D adversarial-tester-agent, relevance-filter | `sonnet` |
| architect-agent (Phase 2) — other phases MUST NOT spawn `opus` directly | `opus` |

**Runtime escalation (Sonnet → Opus on failure):** If a `sonnet` subagent returns wrong output, fails its checklist, or fails tests during Phase 5 implementation or Phase 6 review, re-dispatch ONCE with `model="opus"` plus the failure context appended to the prompt. If the opus retry also fails, escalate to the user. Never bump twice in a row.

---

## Task Directory

```
.geniro/planning/<branch-name>/
```

Derive `<branch-name>` from git branch. Create at start of Phase 1. All artifacts go here: `spec.md`, `state.md`, `notes.md`, `concerns.md`, `review-feedback.md`, `plan-<slug>.md`.

## State Persistence & Phase Checkpoints

**After completing each phase, write a checkpoint to `<task-dir>/state.md`** (`Feature:` / `Spec-file:` MUST stay at the top so PreCompact's first-10-line capture preserves them; written once at end of Phase 1, carried forward unchanged). Read `state.md` on skill start to resume from the next incomplete phase. When running in milestone-mode (plan has `## Milestones` section), the `Milestones:` field tracks per-milestone status — update it in Phase 7 Step 8 when the milestone ships, and read it in the Task Execution Step 0 resume logic.
```
Feature: <F<n> if Geniro feature ID, else "none">
Spec-file: <FEATURES.md Notes-column path, else "none">
Milestones: <"none" | "[1: pending, 2: pending, ...]" — populated by /geniro:decompose and updated by this skill as milestones complete>
Phase [N] completed: [phase name]
Completed phases: [1, 2, ..., N]
Next phase: [N+1]
Key decisions: [brief list]
Files changed: [count or list]
```

---

## Mid-Flow User Input

When the user sends a message while the pipeline is running (not at a WAIT gate), **do not stop or restart**. Classify and handle:

| Type | Signal | Action |
|---|---|---|
| **Note/context** | Informational | Append to `<task-dir>/notes.md`, continue |
| **Preference** | Soft direction | Append to `<task-dir>/notes.md`, apply at next decision point |
| **Correction** | Changes a past decision | Append to `<task-dir>/notes.md`, evaluate impact at next checkpoint |
| **Blocker** | Makes current work invalid | Halt immediately, go to impact assessment |

At the next phase checkpoint, read `notes.md` and assess: (1) no impact -> continue, (2) affects future phases -> update spec, continue, (3) invalidates current output -> backtrack to affected phase only.

---

## PHASE 1: DISCOVER

**Purpose:** Eliminate gray areas, produce executable spec.

**Action:** Read `${CLAUDE_SKILL_DIR}/implement-reference.md` section "Phase 1: Auto-Detection Table" for argument parsing rules.

**Step 0 — Complexity Gate (fast-path check).** Before any discovery work, check whether this request is truly `/geniro:implement`-scope. Skip this gate entirely when: a milestone was detected (Auto-Detection Table rule 0), a plan-file path is present in `$ARGUMENTS` (handled by Phase 2 pre-check rule 4), a plan-mode conversation is active (Phase 2 pre-check rule 2), or `state.md` already contains a `Phase 1 Step 0:` line (resume / second-run already decided). Otherwise apply the rubric in `implement-reference.md` §"Phase 1 Step 0: Complexity Gate" — if the task is Trivial with no hard escalation signals, ask the user whether to hand off to `/geniro:follow-up`. Default is "proceed with full pipeline" for anything uncertain. (auto-mode: see `implement-reference.md` §Auto Mode Behavior)

**Steps:**
1. **Parse `$ARGUMENTS` and load workflow integrations.** Check for `.geniro/workflow/*.md` files — read each one to discover active integrations and their argument detection rules. Apply detection rules from workflow files (e.g., issue tracker patterns), then detect mode signals, extract core description. Follow the workflow file's instructions for any detected references (e.g., fetching issue context, asking about status transitions).
   Also load custom instructions from `.geniro/instructions/global.md` and `.geniro/instructions/implement.md`. Read any found. Apply rules as constraints, additional steps at specified phases, and hard constraints throughout the pipeline.
   Then determine **pipeline mode**: if `$ARGUMENTS` already carried an explicit auto/assumptions signal (rules 3-4 of the Auto-Detection Table), lock to that mode. Otherwise fire the **Mode Selection prompt** from `implement-reference.md` §Phase 1 Auto-Detection Table. Persist `Mode: <interactive|auto|assumptions>` in `<task-dir>/state.md` so all later gates read it without re-prompting.
2. **Bind to feature row (if applicable).** If `$ARGUMENTS` matched rule 2 of the Auto-Detection Table (Geniro feature ID): look up the row in `.geniro/planning/FEATURES.md`; if status is `planned`, run `/geniro:features move <id> in-progress`; if `in-progress`, no action; if `done`/`blocked`, `AskUserQuestion` header "Feature" with options "Re-open and continue" / "Pick a different feature" / "Treat description as new work (skip feature link)". Persist `Feature: <id>` and `Spec-file: <path or "none">` to `<task-dir>/state.md` before Step 3 (carried forward in every later checkpoint). If no feature ID, `Feature:` is "none".
3. **Retrieve prior knowledge.** Spawn `knowledge-retrieval-agent` with task keywords. It searches learnings, sessions, debug history, and planning docs.
4. Scan codebase for relevant patterns, conventions, architecture
5. **Convention Discovery:** Read README, CONTRIBUTING, ADRs. Find 2-3 exemplar files closest to the change area. Capture in CONVENTIONS_BRIEF section within spec file.
6. Identify ambiguities and gray areas. If `state.md` contained `Pipeline: COMPLETE` (second run): use prior `spec.md` and `plan-*.md` already loaded in Step 0 as "Prior iteration context" so gray-area questions reference what was decided before. When the change touches UI, also identify visual gray areas: layout density, interaction patterns, empty/loading/error states, responsive priorities. These are gray areas — resolve with the user in step 7.
7. **MANDATORY: Resolve gray areas.** Read `Mode:` from `<task-dir>/state.md` (set in Step 1) and execute the matching sub-bullet. You MUST stop here and ask the user questions before proceeding (interactive mode). Do NOT synthesize the spec without user input first.
   - **Interactive (default):** Use `AskUserQuestion` with 2-4 options each, recommend default
   - **Auto mode:** Apply rules from `implement-reference.md` §Auto Mode Behavior (Phase 1, Step 7 row) for all gray areas EXCEPT git workspace. Log to `state.md` "Auto-mode decisions" section
   - **Assumptions mode:** Propose plan, let user correct
   - **Plan-provided:** If a detailed plan exists in the conversation (from plan mode) or as a file (from `/geniro:plan`), most gray areas are already resolved. Only ask about decisions the plan doesn't cover (e.g., git workspace). Still write the spec.
   - **Git workspace question is ALWAYS asked via `AskUserQuestion`**, regardless of mode (including auto-mode). Options: new branch / current branch / worktree. This is a deliberate exception to auto-mode's default-picking — where the implementation lands is a consequential decision the user must make explicitly. Ask it standalone (do not batch with other gray areas in auto-mode).
8. Synthesize into spec document (only AFTER step 7). If prior `spec.md` exists, rename to `spec-v{N}.md` (glob `spec-v*.md` for highest N, use N+1; start at 1); rename `plan-<slug>.md` to `plan-<slug>-v{N}.md` likewise. Note which decisions changed vs carried forward. Write to `<task-dir>/spec.md`
9. Document assumptions in spec file
10. **Git workspace setup** — execute user's choice from step 7. Options A and C both need a branch name; read and apply the procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md` once with the spec title and `$ARGUMENTS` to produce `<branch-name>` (e.g., `feat/ci-22-case-radar-timeline`) that follows the repo's convention rather than a hardcoded prefix.
    - **Option A (new branch):** `git checkout -b <branch-name>`. The task directory (already created above) uses this branch name.
    - **Option B (current branch):** No git action. Continue on current branch.
    - **Option C (worktree):** Derive a flat directory name by replacing `/` with `-` in `<branch-name>` (e.g., `feat-ci-22-case-radar-timeline`). Run `git worktree add -b <branch-name> .claude/worktrees/<dir-name>` via Bash — this creates both the worktree and the branch in one step, with the branch name exactly as computed. Then call `EnterWorktree` with `path: ".claude/worktrees/<dir-name>"` to switch the session into the already-created worktree. Do NOT use `EnterWorktree(name: ...)` here — that path auto-creates its own branch with a `worktree-` prefix, which would defeat the convention detection above. After entering, if the project has `.env` or similar gitignored config files but no `.worktreeinclude` file, warn the user that environment files won't be present and suggest creating `.worktreeinclude`.

**Outputs:** spec.md, affected files list, Definition of Done

**Checkpoint:** Write to `<task-dir>/state.md`: "Phase 1 completed."

---

## PHASE 2: ARCHITECT & VALIDATE

**Purpose:** Produce full implementation plan, validate it.

**Pre-check: Existing plan or milestone detection.** Before spawning the architect, check for an existing plan OR a milestone reference from any source:

1. **Milestone reference (highest priority)** — detect a request to implement a single milestone from a decomposed plan. Patterns: `milestone N` argument, milestone-file path, or `continue` with `Milestones:` state. See `${CLAUDE_SKILL_DIR}/implement-reference.md` §Phase 2: Milestone Reference Detection for the full detection rules, skip-architect routing, and milestone-mode scope flag.
2. **Conversation plan (plan mode):** If the conversation contains a structured implementation plan with file-level steps (from Claude Code's plan mode via Shift+Tab, or a prior planning discussion), extract it into `<task-dir>/plan-<slug>.md` following the structure in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-criteria.md`. Set the header `Status: approved | Source: plan-mode`. Detection signal: the conversation has a multi-step plan with specific file paths and implementation details — not just a high-level discussion.
3. **Plan files (from /geniro:plan or /geniro:decompose):** Glob `.geniro/planning/plan-*.md` (flat) AND `.geniro/planning/*/plan-*.md` (task-dir). Read headers, find plans with `Status: approved` that match the current task. If a flat plan matches, move it into `<task-dir>/`. If the plan contains a `## Milestones` section (produced by `/geniro:decompose`) AND `$ARGUMENTS` did not name a specific milestone, use the milestone-mode continue-logic from rule 1 instead of the plan as a whole — warn the user: "This plan is decomposed into N milestones. Running `/geniro:implement continue` or `/geniro:implement milestone <N>` is required. Pick one now." then `AskUserQuestion` listing milestones by name with status.
4. **$ARGUMENTS plan:** If `$ARGUMENTS` contains or references a plan file path (not a milestone file — those are handled in rule 1), read and use it directly.

**If a plan or milestone is found:** Skip architect-agent. Log: "Using existing plan: `<filename>`" or "Using milestone <N>: `<filename>`". Run skeptic-agent to validate (Step 3 below). If skeptic finds blockers, use `AskUserQuestion` (always-WAIT — see implement-reference.md §Auto Mode Behavior): A) Use plan as-is with issues noted, B) Re-architect from scratch (run full architect flow), C) I'll fix the plan manually, then re-validate. Proceed to Phase 3.

**If no plan or milestone found:** Run the full architect flow below.

**Architect flow:**

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-criteria.md` for plan structure
2. **Spawn architect-agent** with `model="opus"` and spec + plan criteria + relevant codebase files (pre-inlined)
3. **Spawn skeptic-agent** with plan + spec. Explicit instruction: "Write report to `<task-dir>/concerns.md`"
4. If NEEDS REVISION: route back to architect. Max 3 iterations.

**Checkpoint:** Write to `<task-dir>/state.md`: "Phase 2 completed. Plan: <filename>. Skeptic: [N blockers, M warnings]."

---

## PHASE 3: APPROVAL (WAIT)

**Purpose:** Present plan to user for approval.

**Action:** Read and present the full plan file (do NOT summarize).

### UI Preview Gate (conditional — runs before Step 1 below)

If any file in the plan's affected-files list matches the UI-file detection rule in `skills/review/SKILL.md` §UI-file detection rule, run the procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` BEFORE the numbered steps below. Pre-inline the spec, plan, and 1-2 exemplar UI files; save the approved description to `<task-dir>/ui-preview.md`. Phase 4 Work Unit agents that touch UI files pick it up via the `## UI Intent` slot in the Phase 4 Agent Delegation Template (see `implement-reference.md`). If the user picks "Adjust the plan instead" inside the procedure, fire `AskUserQuestion` with header "Adjust" to capture what to change, then run the Adjust path below (architect revises with that context, re-validate, re-present). Skip this section entirely when no affected file matches.

1. Read plan from `<task-dir>/plan-<slug>.md`
2. Present complete plan content to user
3. Add metadata: plan location, skeptic validation summary (N blockers, M warnings)

**Gate:**

If `<task-dir>/state.md` shows `Mode: auto`: you MUST first print the full plan content verbatim (same as Step 2 above — the full plan must appear in the transcript, not just a summary or file reference), then print "Auto-approved spec — see `<plan-file>`. Interrupt now if you want to revise.", append the decision to state.md "Auto-mode decisions" section, and proceed to Phase 4. Do NOT call `AskUserQuestion`. The full-plan print is mandatory in auto-mode too — a file path is not the plan content, and the user must be able to audit what was auto-approved.

Otherwise, use the `AskUserQuestion` tool (do NOT output options as plain text):
- A) **Approve — start building**
- B) **Adjust** — user describes changes
- C) **Too large — split** — decompose into smaller pieces

**Routing:** Approve -> Phase 4. Adjust -> architect revises, re-validate, re-present. Too large -> help decompose.

**After approval:** Add remaining phases to TodoWrite checklist:
- Phase 4: Implement — decompose into WUs, execute waves
- Phase 5: Simplify — spawn simplify agent on changed files
- Phase 6: Review & Validate — automated checks, spec compliance, code quality
- Phase 7: Ship & Finalize — finalize (docs, learnings), then ship decision

**Checkpoint:** Write to `<task-dir>/state.md`: "Phase 3 completed. Plan approved."

**Strategic compact point:** All discovery, architecture, and validation context is now captured in files (spec.md, plan.md, concerns.md, state.md). Phases 1-3 consumed significant context that Phase 4 agents don't need — they get fresh context with pre-inlined files.

If state.md shows `Mode: auto`: skip the compact prompt — proceed directly to Phase 4 (matches "Continue now"). Append the decision to state.md "Auto-mode decisions" section.

Otherwise, use the `AskUserQuestion` tool to ask:
- **Question:** "All planning artifacts are saved. Compacting now frees context for higher-quality implementation in Phases 4-7. How would you like to proceed?"
- **Header:** "Compact"
- **Options:**
  - Label: "Compact first (Recommended)" / Description: "Run /compact, then /geniro:implement continue to resume from Phase 4. Best for complex implementations."
  - Label: "Continue now" / Description: "Skip compaction and proceed directly to Phase 4. Fine for smaller tasks."

If the user picks "Compact first": tell them to type `/compact`, then `/geniro:implement continue` to resume.
If the user picks "Continue now": continue normally to Phase 4.

---

## PHASE 4: IMPLEMENT

**Purpose:** Execute architecture with parallel agents.

**Action:** Decompose plan into Work Units, arrange into waves, spawn agents.

Read `${CLAUDE_SKILL_DIR}/implement-reference.md` sections "Phase 4: Decomposition Example", "Phase 4: Agent Delegation Template", and "Phase 4: Error Handling" for templates and examples.

### Step 1: Decompose into Work Units (WUs)

Read the plan's steps and group into WUs — clusters of tightly coupled files. Each WU gets its own agent.

**Rules:**
- Every plan step must be assigned to a WU. No step is "too small" to delegate.
- WU = 1-5 tightly coupled files. 6+ files -> split further.
- **Each WU that creates or modifies source files MUST include corresponding test files in its scope.** If the plan lists `auth.service.ts`, the WU scope must also list `auth.service.test.ts` (or equivalent). No source file without its test file.
- Files in different WUs must be independently changeable
- In milestone-mode (Phase 2 pre-check rule 1 matched): scope is HARD-LIMITED to the milestone's Files Affected table. Any step that would touch a file outside the table must be deferred to a later milestone — do NOT expand scope mid-milestone. Forward-reference files (used only by future milestones) must NOT be created in this milestone.
- Hotspot files (routing, config, barrel exports) -> LAST wave
- Each WU needs a clear Definition of Done (including: "tests written and passing for all new/changed logic")

**Scope-aware ordering:** Backend first -> codegen -> frontend. Never parallel when types flow between stacks.

**When NOT to decompose:** Total change <=3 files -> single agent. **Still delegate even without decomposition.** 1 WU = 1 agent, NOT "orchestrator does it directly."

### Step 2: Arrange into Waves

- **Wave 1:** WUs with no dependencies (all parallel)
- **Wave N:** WUs depending on prior waves
- **Hotspot wave (last):** Orchestrator micro-edits only
- Max 4-5 agents per wave. All spawned in ONE response — multiple Agent() calls in the same assistant turn, NOT one per turn.
- Same-stack agents MUST work on non-overlapping files

### Step 3: Execute waves

For each wave:
1. **Spawn all WU agents in ONE response** — multiple Agent() calls in the same assistant turn, NOT one per turn (use delegation template from reference file — it includes a mandatory `## Tests` section. Do NOT omit it.)
   **Agent context:** The `backend-agent` and `frontend-agent` read `CLAUDE.md` at runtime for project-specific context. No additional context injection is needed — simply spawn the agent.
2. **Collect results** — each agent must report: files created/modified, tests created/modified, test results
3. **Quick gate** (build + test) — pass/fail only. If fails, forward the raw error output to a fixer agent. Do NOT read source files, diagnose the error, or apply fixes yourself — copy the terminal output into the agent prompt and let it handle everything.
4. **Start next wave**

### Step 4: Hotspot files (orchestrator micro-edits only)

Strictly limited to 1-2 line registrations. If >3 lines or any logic -> delegate to subagent.

### Step 5: Post-wave validation

- Run **build + test** — pass/fail gate only. Do NOT include lint (Phase 5 handles that).
- If fails, forward the raw error output to a fixer agent. Do NOT read source files, diagnose the error, or apply fixes yourself — copy the terminal output into the agent prompt and let it handle everything.

### Step 6: Test creation verification

**Action:** Check that tests were actually created for new/changed source files.

1. Get the list of changed source files: `git diff --name-only main...HEAD | grep -v test | grep -v spec | grep -v node_modules`
2. For each new source file, verify a corresponding test file exists (same directory or `__tests__/` directory, matching the project's test file naming convention)
3. If any source file is missing tests, spawn a fixer agent with:
   - The source file contents (pre-inlined)
   - The nearest existing test file as an exemplar pattern
   - Instruction: "Write tests for this file following the exemplar pattern"
4. Re-run tests after fixer completes

**Skip test verification for:** config files, migrations, type-only files, barrel/index files, CSS/style files.

**Anti-rationalization:**
| Your reasoning | Why it's wrong |
|---|---|
| "The implementation agents already wrote tests" | Verify, don't trust. Check the file system. Agents skip tests under context pressure. |
| "Tests will be caught by Phase 6 reviewers" | Phase 6 reviews test QUALITY. Phase 4 must ensure tests EXIST. Don't defer creation to review. |
| "This code is too simple to need tests" | Every new source file gets tests. Simplicity is not an exemption — simple code is the easiest to test. |
| "I'll write the tests myself to save time" | You are an orchestrator. Spawn a fixer agent. |
| "Let me read the file and fix this type error / build error" | You are an orchestrator. Forward the raw terminal output to a fixer agent. Do NOT open source files, diagnose errors, or apply edits — even if the fix looks trivial. The fixer agent has fresh context and will diagnose faster. |

**Checkpoint:** Write to `<task-dir>/state.md`: "Phase 4 completed. Waves: N. Files changed: [list]. Test files created: [list]."

---

## PHASE 5: SIMPLIFY

**Purpose:** Code quality pass on changed files — catch AI-generated anti-patterns.

**Action:** Spawn simplify agent. Read `${CLAUDE_SKILL_DIR}/implement-reference.md` section "Phase 5: Simplify Agent Template" for the agent prompt.

### Step 1: Spawn simplify agent

Read `${CLAUDE_PLUGIN_ROOT}/skills/deep-simplify/simplify-criteria.md`. Spawn a **general-purpose** subagent with `model: "sonnet"` using the template from the reference file. Pre-inline the criteria and the changed file list.

### Step 2: Verify after simplification

1. Run lint/format fix
2. Run build + lint + test
3. **If checks fail:** revert simplification (`git checkout -- .`), note "Simplification skipped — caused CI failures." Proceed to Phase 6.

**Anti-rationalization:**
| Your reasoning | Why it's wrong |
|---|---|
| "The code is already clean enough" | AI-generated code almost always has over-abstraction or verbose patterns. Run the check. |
| "Simplification might break things" | That's why we run checks after. If it breaks, we revert. Zero risk. |
| "Let me run CI first (Stage A), then decide on simplification" | Phase 5 comes BEFORE Phase 6. Simplify first, validate after. Do NOT merge or reorder phases. |

**Checkpoint:** Write to `<task-dir>/state.md`: "Phase 5 completed. Simplify agent ran. Post-simplify verification: PASS/REVERTED."

---

## PHASE 6: REVIEW & VALIDATE

**Purpose:** Single quality gate — verify code compiles, passes tests, meets spec, and is well-written.

**Action:** Run Stage A checks, spawn Stage B agent, spawn Stage C agents, then spawn Stage D adversarial-tester-agent.

Read `${CLAUDE_SKILL_DIR}/implement-reference.md` sections "Phase 6: Stage A", "Phase 6: Stage B", "Phase 6: Stage C", "Phase 6: Fix Loop", and "Phase 6: Stage D" for detailed procedures and templates.

**Four stages, run in order:**

### Stage A — Automated Checks

Run autofix, full check (build + lint + test), codegen check, runtime startup check. If any fails, forward the raw error output to a fixer agent — do NOT read source files, diagnose, or fix it yourself. Max 2 attempts, then continue to Stage B with failures noted.

**Checkpoint:** Update `<task-dir>/state.md`: "Phase 6 Stage A completed."

### Stage B — Spec Compliance

**Action:** Spawn spec-compliance subagent using the template from the reference file. Pre-inline spec, plan, changed files.

Read `<task-dir>/compliance.md` after agent completes. If any requirement unmet -> spawn a fixer agent with the gap details and affected files pre-inlined. Do NOT read source files, diagnose gaps, or apply fixes yourself — delegate to the agent. Max 2 rounds.

**Checkpoint:** Update `<task-dir>/state.md`: "Phase 6 Stage B completed. Compliance: PASS."

### Stage C — Code Quality

**Action:** Spawn 5–6 parallel reviewer agents in ONE response — all Agent() calls in the same assistant turn, NOT one per turn — bugs, security, architecture, tests, guidelines, plus design when changed files include UI (see UI-file detection rule in `skills/review/SKILL.md`). Use templates from reference file.

Aggregate findings. Drop Medium. Pass CRITICAL/HIGH to fix loop. Write `<task-dir>/review-feedback.md`.

**Fix loop:** Max 3 rounds. Spawn NEW fixer + FRESH reviewers each round (anchoring bias). After 3 rounds, present handoff to user (always-WAIT — see implement-reference.md §Auto Mode Behavior).

**Checkpoint:** Update `<task-dir>/state.md`: "Phase 6 Stage C completed."

### Stage D — Adversarial Edge-Case Tests

**Purpose:** Attacker-mindset pass that complements Stage C. Where Stage C's `tests-criteria.md` reviewer REPORTS coverage/quality gaps in EXISTING tests, Stage D AUTHORS NEW failing tests (F→P-verified: red today) for edge cases the implementer's happy-path-plus-2-edge tests missed. Authored tests feed the existing Fix Loop above ("make the red tests green").

**Action:** Spawn one `adversarial-tester-agent` (`model="sonnet"`) with the diff, the shared checklist path `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`, 1-2 exemplar test files, the project test command (from CLAUDE.md or package.json), Stage C findings as hypothesis seeds, and output path `<task-dir>/adversarial-tests.md`. See `${CLAUDE_SKILL_DIR}/implement-reference.md` §Phase 6 Stage D for the full spawn template.

**Orchestrator responsibilities after the agent returns:**
1. **Re-verify F→P independently.** Run the authored tests yourself — do NOT trust the agent's self-report. Any test that passes today is removed from scope; log it and continue.
2. **Route confirmed failing tests into the Fix Loop.** Each F→P-confirmed test becomes a CRITICAL/HIGH item in `<task-dir>/review-feedback.md` with severity from the agent's report. The existing Fix Loop (max 3 rounds) applies — fresh fixer agents make the red tests green. Do NOT skip the flake-recheck on the fixer's output.
3. **Scope hard cap.** The agent authors at most 10 tests per run. If the agent reported hitting the cap with more hypotheses pending, append the overflow to the Phase 7 Step 4 summary under "Deferred ideas" rather than expanding this run.

**Skip Stage D entirely when:** diff contains zero production-code files (docs/config/lockfile-only); OR `Mode: auto` AND diff ≤3 files AND Stage C had zero CRITICAL/HIGH tests-dimension findings (note the skip in state.md "Auto-mode decisions"). Anti-rationalization: "Stage C already covers tests" — NO: Stage C REPORTS gaps; Stage D AUTHORS failing tests (different lifecycle). Never trust the agent's F→P self-report — re-run the tests yourself.

**Checkpoint:** Update `<task-dir>/state.md`: if Stage D ran, write "Phase 6 completed. All stages passed."; if skipped, write "Phase 6 Stage D skipped — <reason>" then "Phase 6 completed."

---

## PHASE 7: SHIP & FINALIZE (WAIT)

**Precondition — do NOT enter Phase 7 until ALL of these are true:**
- Phase 5 completed — check `state.md` for "Phase 5 completed"
- Phase 6 Stage A completed — check `state.md`
- Phase 6 Stage B completed — check `state.md`
- Phase 6 Stage C completed — check `state.md`
- Phase 6 Stage D completed or skipped with logged reason — check `state.md`

If any is missing, go back and complete it. Do NOT skip phases.

### PART A: FINALIZE (Steps 1-4 — runs automatically, no user input needed)

These steps run BEFORE presenting the ship decision. They cannot be skipped.

**Step 1: Update Docs** — Check if existing docs need patching. Delegate if needed, skip silently if not. See reference file for details.

**Step 2: Extract Learnings** — Scan conversation for corrections, gotchas, decisions. Save to learnings.jsonl and/or memory. Write session summary. See reference file for signal table.

**Step 3: Suggest Improvements (project scope only) (WAIT — auto: see implement-reference.md §Auto Mode Behavior)** — Classify each finding by routing target: **CLAUDE.md** (new commands, conventions, project structure), **custom instructions** (quality gates, workflow steps, or constraints the user enforced manually — to `.geniro/instructions/`), **knowledge** (gotchas, workarounds, decisions), **project rules/hooks** (project-level enforceable patterns). Plugin-file improvements (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope — the plugin is global and overwritten on update; use `/improve-template` for plugin maintenance. Present grouped by target via `AskUserQuestion`. See reference file for routing table.

**Step 4: Present Summary**

1. **Features implemented** (list)
2. **Files changed** (grouped by area: backend/frontend/tests/config)
3. **Tests added/modified**
4. **Review feedback addressed** (count of issues fixed)
5. **Validation results** (lint, build, test, startup, codegen — pass/fail each)
6. **Learnings extracted** (count, or "none")
7. **Deferred ideas** (if any)

### Step 4.5: Pre-Ship Visual Verification (WAIT — conditional, runs only if UI changed — auto: see implement-reference.md §Auto Mode Behavior)

If any file in the "Files changed" list from Step 4 matches the UI-file detection rule in `skills/review/SKILL.md` §UI-file detection rule, fire a STANDALONE `AskUserQuestion` with header "Smoke-test" as the ONLY question in that call — never batch it with Step 5's Ship Decision question, because the user must not be offered a commit/push choice until UI verification is resolved:
- **Yes — walk through it** — drive Playwright MCP to smoke-test the change before shipping. Follow the full sequence in `implement-reference.md` §Pre-Ship Visual Verification.
- **Skip — already verified** — record skip reason in `<task-dir>/state.md` and proceed to Step 5.

If verification surfaces issues, route via a second `AskUserQuestion`: "Fix and re-verify" (loop back through Phase 7 Step 6 Small tweak path — Step 4.5 re-fires automatically after Step 4 if UI files remain in the diff), "Ship anyway with noted issues" (record in `state.md` and proceed), or "Abort" (stop pipeline). Skip this step silently when no changed file matches the rule.

### PART B: SHIP DECISION (Steps 5-8 — interactive)

### Step 5: Ship Decision (WAIT — always-WAIT regardless of mode)

Use `AskUserQuestion` (max 4 options). The user can always type a custom response via "Other" (e.g., "review diff first", "leave uncommitted"):
- A) **Commit + PR** — commit, push, and create a pull request via `gh pr create`
- B) **Commit + push** — commit and push to remote (`git push origin [branch]`)
- C) **Commit only** — stage and commit on current branch with conventional commit message
- D) **Minor tweaks needed** — small adjustments before shipping (I'll describe)

**If the user picked A:** immediately fire a SECOND `AskUserQuestion` with header "PR state" and exactly 2 options before proceeding to Step 7:
- **Draft PR** — create as draft (`gh pr create --draft`); blocks merge and suppresses CODEOWNERS review requests until promoted with `gh pr ready`. Choose this when CI validation or follow-up commits are expected before reviewers are pinged. Some orgs configure CI to skip drafts — surface that caveat if you can detect it.
- **Ready for review** — create as a standard PR (`gh pr create`); requests review immediately.

**Routing:**
- **A, B, C** -> proceed to Step 7 (Commit)
- **D** -> proceed to Step 6 (Adjustment Routing)
- **"Review diff"** (via Other) -> show diff, loop back to Step 5
- **"Leave uncommitted"** (via Other) -> skip commit, proceed to Step 8 (Cleanup)

### Step 6: Adjustment Routing (if user chose D)

Ask the user to describe the tweak. Classify by size (Big / Medium / Small), then follow the corresponding action sequence in `${CLAUDE_SKILL_DIR}/implement-reference.md` §Phase 7 Step 6: Adjustment Routing. That section covers the per-tier numbered steps, loop target (always Step 4 summary re-presentation), and soft limits (Big: 2 rounds → `/geniro:implement`; Medium/Small: 3 rounds → `/geniro:follow-up`).

### Step 7: Commit

Execute user's chosen method. See reference file for commit details per option.

### Step 8: Worktree Exit + Integration Updates + Cleanup — auto: see implement-reference.md §Auto Mode Behavior

- **Worktree:** If in worktree, call `ExitWorktree` with the appropriate action:
  - After commit+push or commit+PR: `ExitWorktree` with `action: "keep"` (branch needed for PR review / further work)
  - After commit only: `ExitWorktree` with `action: "keep"` (user may want to push later)
  - After leave uncommitted: warn user that changes remain in the worktree directory, then `ExitWorktree` with `action: "keep"`
  - Only use `action: "remove"` if user explicitly says to abandon the work
- **Integrations:** If workflow files specify completion actions (e.g., issue status updates), follow their instructions (see reference file for details)
- **Cleanup:** Kill orphaned processes (startup checks, dev servers). Remove temp files.
- **State:** If milestone-mode AND any milestone remains non-`completed`, skip this step (pipeline is not complete yet). Otherwise append `Pipeline: COMPLETE` to `<task-dir>/state.md`. In milestone-mode when the LAST milestone completes, also set the master plan's `Status: completed` header.
- **Milestone status update (milestone-mode only):** If this run executed a single milestone (Phase 2 pre-check rule 1 matched), update milestone file + master plan table + state.md, append Implementation Notes, and prompt for next milestone. See `${CLAUDE_SKILL_DIR}/implement-reference.md` §Phase 7 Step 8: Milestone Status Update for the full 6-step procedure and auto-mode behavior.
- **Feature row update:** Read `Feature:` from `<task-dir>/state.md`. If a Geniro feature ID, run `/geniro:features complete <id>` (moves FEATURES.md row to `done`, records the commit). If "none", skip.
- **Planning artifacts:** Use `AskUserQuestion` (do NOT ask as plain text — use the tool):

`AskUserQuestion` with header "Artifacts":
- A) **Keep** — "Useful if you plan to run /geniro:follow-up on this branch"
- B) **Delete** — "Implementation is complete, no further changes expected"

If "Keep": leave `<task-dir>/` as-is (it's already in `.gitignore`).
If "Delete": remove `<task-dir>/` recursively.

**Anti-rationalization:**
| Your reasoning | Why it's wrong |
|---|---|
| "Skip learning extraction, it takes too long" | Learnings make future sessions faster. Part A runs automatically — you cannot skip it. |
| "Skip doc updates, they're boring" | Doc drift is the #1 source of confusion in future sessions. |
| "The user said 'just finish' so skip finalize" | Part A (finalize) runs BEFORE the ship decision. It is not optional regardless of user urgency. |
| "Implementation is done, the user can test it" | Phase 4 is one of 7 phases. Follow the pipeline to completion. |
| "I'll skip review since the agents already tested" | Agent self-reports are unreliable. Phase 6 exists to catch what agents miss. |
| "The tweak is small, I'll skip the re-validation loop" | Every tweak re-runs at minimum Stage A. Small bugs introduced during tweaks are the hardest to catch later. |
| "I'll batch Smoke-test and Ship Decision in one AskUserQuestion to save a round-trip" | Step 5 offers commit/push/PR — asking it alongside the UI-check lets the user commit before verifying UI. The Smoke-test question is a standalone gate; Step 5 fires only after verification is resolved (completed or skipped). |

---

## TASK EXECUTION

0. **Check for existing state.** Glob for `<task-dir>/state.md`. Four cases:
   - **No state.md** → fresh first run, proceed normally.
   - **state.md has `Milestones:` field with at least one non-`completed` milestone AND `$ARGUMENTS` is empty or `continue`** → milestone-mode resume: load the first non-completed milestone (pick `in-progress` over `pending`), set that milestone's file as the implementation target, skip Phase 1 Discover (spec already exists), jump to Phase 2 pre-check rule 1 (milestone reference) which will load the file and go to Phase 3.
   - **state.md exists, no "Pipeline: COMPLETE"** → interrupted run, resume from next incomplete phase.
   - **state.md exists, has "Pipeline: COMPLETE"** → second run with changed requirements. Read all prior artifacts (`spec.md`, `plan-*.md`, `concerns.md`) into context now (before any renames). Proceed to Phase 1 with this prior context available.

1. Take user's description: `$ARGUMENTS`
2. **Create TodoWrite checklist** (planning phases only — implementation phases added after Phase 3 approval):
   - Phase 1: Discover
   - Phase 2: Architect & validate
   - Phase 3: Approval
   Mark Phase 1 as `in_progress`. Update status as each phase completes.
3. Begin Phase 1 (Discover)

**Token conservation — delegate ALL implementation work:**
The orchestrator's job is to coordinate, not to code. Every line of code the orchestrator writes wastes expensive context. Delegate ALL work to subagents — including deletions, cleanups, "simple" edits. If you catch yourself thinking "I'll just do this directly since it's simple" — that's the rationalization. Spawn an agent.

**Anti-rationalization:**
| Your reasoning | Why it's wrong |
|---|---|
| "I'll execute this directly since it's simple / just deletion / cleanup" | Orchestrator tokens are the most expensive resource. Delegate ALL implementation to subagents. |
| "Steps X-Y are small, I'll handle them myself" | Every plan step becomes a WU. Group small related steps into one WU, but never execute as orchestrator. |
| "The build failed, let me read the source and fix it quickly" | Run the check, copy the raw terminal output into a fixer agent prompt. Do NOT open source files, diagnose, search for types, or apply edits yourself. |
| "I'll upgrade this haiku spawn to sonnet just to be safe" | Tier is matched to task nature, not to risk appetite. Upgrading mechanical-task agents (docs, guidelines, design) to sonnet defeats the cost rationale and signals drift. If the task genuinely needs reasoning, re-classify it using the Subagent Model Tiering table — don't silently upsize. |
| "I'll spawn agents one at a time" | All parallel agents MUST be spawned in ONE response — multiple Agent() calls in the same assistant turn. Separate turns = no concurrency, full wall-clock latency per agent. Only sequence when outputs feed into next agent (e.g., plan → skeptic) or files overlap. |

---

## REFERENCE

- Agent templates, examples, error tables: `${CLAUDE_SKILL_DIR}/implement-reference.md`
- Plan criteria: `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-criteria.md`
- Review criteria: `${CLAUDE_PLUGIN_ROOT}/skills/review/` (bugs, security, architecture, tests, guidelines, +design when UI files changed)
- Simplify criteria: `${CLAUDE_PLUGIN_ROOT}/skills/deep-simplify/simplify-criteria.md`
