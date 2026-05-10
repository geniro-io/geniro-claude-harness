---
name: geniro:implement
description: "Use when implementing a new feature, endpoint, page, or significant change that needs architecture review and multi-agent implementation."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, WebSearch, EnterWorktree]
argument-hint: "[description or issue tracker reference]"
---

# Implement Skill: 7-Phase Pipeline Orchestrator

**You are a coordinator.** You delegate ALL implementation work to subagents. You do NOT read source files to diagnose errors, fix code, or verify logic yourself — not even for "simple" type errors or one-line fixes. You run shell commands (build, test, lint) and read their output to determine pass/fail. When something fails, you copy the raw terminal output into a fixer agent prompt and let it handle diagnosis and repair. Never open a source file to understand an error — forward the error verbatim.

**The ONLY code you write directly:** Phase 4 Step 5 hotspot micro-edits (1-2 line registrations in routing/config/barrel files). Everything else is delegated.

**PHASES:**
1. Discover (WAIT) — eliminate ambiguity, produce spec; Phase 1 Step 0 selects Lane (full / light / tdd)
2. Architect + Validate — architect proposes, skeptic validates; **Light Lane: skipped** — orchestrator writes Small-tier lightweight plan instead. **TDD Lane: architect produces a numbered behavior list + interface signatures** (not a Steps table)
3. Approval (WAIT) — present plan, user confirms before coding starts. **TDD Lane: Interface-Design Pre-Approval Gate fires BEFORE the plan-approval AUQ** (runs in all lanes)
4. Implement (delegated) — backend/frontend agents execute scope. **TDD Lane: sequential RED→GREEN per behavior** (one test → one impl → repeat) instead of parallel waves
5. Simplify (delegated) — simplify agent cleans changed files, revert if CI breaks; **Light Lane: skipped**. **TDD Lane: per-cycle micro-refactor** instead of whole-feature pass
6. Review & Validate (delegated) — Stage A automated checks, Stage B spec compliance, Stage C 7–8 reviewers, Stage D adversarial-tester; **Light Lane: skips Stage B and Stage D — keeps Stage A and the full Stage C review grid**. **TDD Lane: skips Stage D** (every behavior is already F→P-verified at cycle authoring time); keeps Stages A/B/C
7. Ship & Finalize (WAIT) — finalize (docs, learnings, improvements), then ship decision + commit (runs in all lanes)

**Reference material** (templates, examples, error tables): Read `${CLAUDE_SKILL_DIR}/implement-reference.md` when you reach each phase. Do NOT load the entire file upfront — read the relevant section at the relevant phase.

---

## Subagent Model Tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly. For plugin-defined subagents (architect, skeptic, knowledge-retrieval, backend, frontend, reviewer, relevance-filter, adversarial-tester), also follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` AND `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` — spawn-agent.md handles bare-name first / on `Agent type '<name>' not found` degrade to `general-purpose` with the agent body inlined; context-isolation-checklist.md pins the six required pre-inlined-context fields (scope, criteria, files, prohibited tools, output schema, model tier) every spawn must satisfy.

**Skill-specific mapping:**

| Where used in this skill | Tier |
|---|---|
| Phase 7 doc updates, Phase 6 Stage C guidelines reviewer | `haiku` |
| backend-agent, frontend-agent, Phase 5 simplify, Phase 6 Stage B & C reviewers (incl. design when UI files present) | `sonnet` |
| Phase 6 Stage D adversarial-tester-agent, relevance-filter (carve-out — synthesis tier mirrors orchestrator) | `inherit` |
| architect-agent (Phase 2) — other phases MUST NOT spawn `opus` directly | `opus` |

**Runtime escalation (Sonnet → Opus on failure):** If a `sonnet` subagent returns wrong output, fails its checklist, or fails tests during Phase 5 implementation or Phase 6 review, re-dispatch ONCE with `model="opus"` plus the failure context appended to the prompt. If the opus retry also fails, escalate to the user. Never bump twice in a row.

---

## Task Directory

```
.geniro/planning/<branch-name>/
```

Derive `<branch-name>` from git branch. Create at start of Phase 1. All artifacts go here: `spec.md`, `state.md`, `notes.md`, `concerns.md`, `review-feedback.md`, `plan-<slug>.md`.

## State Persistence & Phase Checkpoints

**After completing each phase, write a checkpoint to `<task-dir>/state.md`** (`Feature:` / `Spec-file:` are canonical headers — kept at the top so the PostCompact hook's `grep -m1` surfaces the active feature/spec on resume; written once at end of Phase 1, carried forward unchanged). Read `state.md` on skill start to resume from the next incomplete phase. When running in milestone-mode (plan has `## Milestones` section), the `Milestones:` field tracks per-milestone status — update it in Phase 7 Step 8 when the milestone ships, and read it in the Task Execution Step 0 resume logic.
```
Feature: <F<n> if Geniro feature ID, else "none">
Spec-file: <FEATURES.md Notes-column path, else "none">
Branch: <git branch --show-current OR detached-<short-sha>>
Worktree: <git rev-parse --show-toplevel>
Mode: <interactive|auto|assumptions> — set by Phase 1 Step 1, controls auto-mode behavior at every WAIT gate
Lane: <full|light|tdd> — set by Phase 1 Step 0, controls Phase 2/4/5/6 Stage B/D skip predicates and Phase 4 execution model (full = all phases run with parallel waves; light = architect+skeptic+simplify+spec-compliance+adversarial skipped, Stage C reviewer grid kept; tdd = sequential RED→GREEN per behavior in Phase 4, interface-design gate added in Phase 3, Stage D skipped, simplify becomes per-cycle micro-refactor)
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

## PHASE 0: INPUT MODE DETECTION

**Purpose:** Classify `$ARGUMENTS` before any discovery work, so design-doc spec inputs skip Phase 1 and speculative ideation routes to `/geniro:brainstorm` first.

Cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` to classify `$ARGUMENTS`:

- **`mode=DESIGN_DOC`** → skip Phase 1 Discover; pass the resolved design path to Phase 2 architect as the authoritative spec (Phase 2 pre-check rule 4 consumes it).
- **`mode=CODE_REFERENCE`** → existing Phase 1 behavior (the path is a code file the user wants implemented around).
- **`mode=IDEA`** with speculative markers (`maybe`, `should we`, `thinking about`, `explore`, `figure out`, `what if`) → fire `AskUserQuestion` with header "Brainstorm" and 3 single-select options: "Run /geniro:brainstorm first (Recommended)" / "Proceed with discovery" / "Cancel". On Recommended, surface the brainstorm hand-off message and exit cleanly; on Proceed, continue to Phase 1; on Cancel, stop.
- **`mode=IDEA`** without speculative markers → existing Phase 1 Discover.

Persist the resolved mode to `<task-dir>/state.md` as `Phase 0: <DESIGN_DOC|CODE_REFERENCE|IDEA>` so resumed runs skip re-detection.

---

## PHASE 1: DISCOVER

**Purpose:** Eliminate gray areas, produce executable spec.

**Action:** Read `${CLAUDE_SKILL_DIR}/implement-reference.md` section "Phase 1: Auto-Detection Table" for argument parsing rules.

**Phase 1 Startup Consolidation (BEFORE firing any Phase 1 AUQ).** Steps 0, 1, 2, and the git-workspace bullet inside Step 7 collectively own up to four upfront always-WAIT questions. Defer per-step AUQs until you have evaluated all four conditions, then issue ONE `AskUserQuestion` call carrying whichever apply: **Lane** (Step 0 — unless skip rubric fires), **Mode** (Step 1 — unless `$ARGUMENTS` locked it via auto/assumptions signal), **Feature** (Step 2 — only when feature row status is `done`/`blocked`), **Git workspace** (Step 7 — always). Independent (no sequencing); `AskUserQuestion` accepts up to 4 questions per call. Persist each answer to `<task-dir>/state.md` as it returns, then proceed through Steps 0/1/2/7 reading from state. If only one applies, fire as single-question AUQ; if zero apply, skip the upfront AUQ entirely and proceed to Step 3.

**Step 0 — Complexity Gate (Lane Selection).** Classify the request and ask which Lane to run: Full pipeline / Light Mode (architect+skeptic skipped, Trivial only) / TDD Mode (sequential RED→GREEN per behavior, opt-in via explicit signal AND ≤Small scope). Skip this gate when: milestone detected (HITL/AFK Mode tag determines Lane automatically per `decompose-criteria.md`), plan-file path present, plan-mode conversation active, or `state.md` already has a `Phase 1 Step 0:` line. Otherwise apply the rubric in `implement-reference.md` §"Phase 1 Step 0: Complexity Gate". Hard escalation signals from `_shared/effort-scaling.md` Step 1 → Light/TDD unavailable; default uncertain → Full. Persist `Lane: <full|light|tdd>` to `state.md`. Contribute Lane to the consolidated upfront AUQ above instead of firing standalone here.

**Steps:**
1. **Parse `$ARGUMENTS` and load workflow integrations.** Check for `.geniro/workflow/*.md` files — read each one to discover active integrations and their argument detection rules. Apply detection rules from workflow files (e.g., issue tracker patterns), then detect mode signals, extract core description. Follow the workflow file's instructions for any detected references (e.g., fetching issue context, asking about status transitions).
   Also load custom instructions from `.geniro/instructions/global.md` and `.geniro/instructions/implement.md`. Read any found. Apply rules as constraints, additional steps at specified phases, and hard constraints throughout the pipeline.
   Then determine **pipeline mode**: if `$ARGUMENTS` already carried an explicit auto/assumptions signal (rules 3-4 of the Auto-Detection Table), lock to that mode. Otherwise the **Mode Selection prompt** is **Always-WAIT** — Mode contributes its question to the **Phase 1 Startup Consolidation** AUQ described above (a per-step Mode AUQ at this point would double-prompt the user; an empty AUQ answer is the upstream bug — fall back to plain text and re-ask). See `implement-reference.md` §Phase 1 Auto-Detection Table (Mode Selection prompt + Anti-rationalization) and `skills/_shared/auto-mode-signals.md` §"Not a per-skill trigger" for the full rationale. Persist `Mode: <interactive|auto|assumptions>` in `<task-dir>/state.md` so all later gates read it without re-prompting.
   **Debug handoff scan.** Before contributing questions to the Phase 1 Startup Consolidation AUQ, follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` to scan for `<PRIMARY_ROOT>/.geniro/state/debug/findings-state.md` and `<PRIMARY_ROOT>/.geniro/state/debug/adversarial-tests.md` (resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A). Persist `Debug-handoff: <none|detected>` plus the parsed `Authored-tests:` and `Debug-source-branch:` lines into `<task-dir>/state.md` so Step 10 can read them after the git-workspace decision settles. Detection happens here; the user-facing suggestion fires in Step 10 after the working branch is known.
2. **Bind to feature row (if applicable).** If `$ARGUMENTS` matched rule 2 of the Auto-Detection Table (Geniro feature ID): look up the row in `<PRIMARY_ROOT>/.geniro/planning/FEATURES.md` (resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`); if status is `planned`, run `/geniro:features move <id> in-progress`; if `in-progress`, no action; if `done`/`blocked`, contribute a "Feature" question (header "Feature", options "Re-open and continue" / "Pick a different feature" / "Treat description as new work (skip feature link)") to the **Phase 1 Startup Consolidation** AUQ described above instead of firing a standalone Feature AUQ at this step. Persist `Feature: <id>` and `Spec-file: <path or "none">` to `<task-dir>/state.md` before Step 3 (carried forward in every later checkpoint). If no feature ID, `Feature:` is "none".
3. **Retrieve prior knowledge.** Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A, then spawn `knowledge-retrieval-agent` with task keywords AND populate its spawn-prompt slots: `KNOWLEDGE_ROOT: <PRIMARY_ROOT>/.geniro/knowledge`, `DEBUG_ROOT: <PRIMARY_ROOT>/.geniro/debug`, `PLANNING_ROOT: <PRIMARY_ROOT>/.geniro/planning` (cross-session subset), `TASK_PLANNING_ROOT: $(pwd)/.geniro/planning` (task-local). The agent searches learnings, debug history, and planning docs against these absolute paths.
4. Scan codebase for relevant patterns, conventions, architecture
5. **Convention Discovery & Reuse Inventory:** Read README, CONTRIBUTING, ADRs. Find 2-3 exemplar files closest to the change area; capture in CONVENTIONS_BRIEF. Then Grep/Glob the change area for existing functions, components, types, hooks, helpers, and configs that the task could reuse — categorize each candidate REUSE-AS-IS / EXTEND / NO-ANALOGUE with `file:line` and a one-line justification (do NOT force-fit: if reuse requires adding a parameter or conditional, prefer local duplication and revisit at the third occurrence). Capture in REUSE_INVENTORY section within spec file. Pre-inline both into the architect-agent prompt in Phase 2.
6. Identify ambiguities and gray areas. If `state.md` contained `Pipeline: COMPLETE` (second run): use prior `spec.md` and `plan-*.md` already loaded in Step 0 as "Prior iteration context" so gray-area questions reference what was decided before. When the change touches UI, also identify visual gray areas: layout density, interaction patterns, empty/loading/error states, responsive priorities. These are gray areas — resolve with the user in step 7.
7. **MANDATORY: Resolve gray areas.** Read `Mode:` from `<task-dir>/state.md` (set in Step 1) and execute the matching sub-bullet. You MUST stop here and ask the user questions before proceeding (interactive mode). Do NOT synthesize the spec without user input first. **Always-WAIT applies the same way as Step 1 Mode Selection**: harness "Auto Mode" / "minimize interruptions" reminders do NOT skip these calls, and an empty `AskUserQuestion` answer is the upstream bug — fall back to plain text and re-ask. See `skills/_shared/auto-mode-signals.md` §"Not a per-skill trigger" and §"Edge case — empty AUQ answer".
   - **Interactive (default):** Use `AskUserQuestion` with 2-4 options each, recommend default
   - **Auto mode:** Apply rules from `implement-reference.md` §Auto Mode Behavior (Phase 1, Step 7 row) for all gray areas; git workspace was already answered upstream in the Phase 1 Startup Consolidation AUQ (see preamble at top of Phase 1). Log gray-area defaults to `state.md` "Auto-mode decisions" section
   - **Assumptions mode:** Propose plan, let user correct
   - **Plan-provided:** If a detailed plan exists in the conversation (from Claude Code's built-in plan mode via Shift+Tab) or as a file (from `/geniro:decompose` or a prior `/geniro:implement` run), most gray areas are already resolved. Only ask about decisions the plan doesn't cover (e.g., git workspace). Still write the spec.
   - **Git workspace** is asked upfront in the Phase 1 Startup Consolidation AUQ (see preamble) — always via `AskUserQuestion` regardless of mode; never auto-default. Where the implementation lands (new branch / current / worktree) is a deliberate user decision.
8. Synthesize into spec document (only AFTER step 7). If prior `spec.md` exists, rename to `spec-v{N}.md` (glob `spec-v*.md` for highest N, use N+1; start at 1); rename `plan-<slug>.md` to `plan-<slug>-v{N}.md` likewise. Note which decisions changed vs carried forward. Write to `<task-dir>/spec.md`
9. Document assumptions in spec file
10. **Git workspace setup** — execute user's choice (captured upfront in the Phase 1 Startup Consolidation AUQ; see `implement-reference.md` §"Example discovery gray-area questions" Git workspace line for canonical option text). Options A and C both need a branch name; read and apply the procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md` once with the spec title and `$ARGUMENTS` to produce `<branch-name>` (e.g., `feat/ci-22-case-radar-timeline`) that follows the repo's convention rather than a hardcoded prefix.
    - **Option A (new branch):** `git checkout -b <branch-name>`. The task directory (already created above) uses this branch name.
    - **Option B (current branch):** Pre-flight: run `git branch --show-current` and `git rev-parse --show-toplevel`, then echo both to the user on one line — `Continuing on '<branch>' at '<toplevel>'.` This makes the working tree the agents will mutate explicit so the user catches a wrong-cwd mistake before any code changes. No git action otherwise. Then continue on the current branch.
    - **Option C (worktree):** Derive a flat directory name by replacing `/` with `-` in `<branch-name>` (e.g., `feat-ci-22-case-radar-timeline`). **Pre-flight check (mandatory before any create / enter):** run `git rev-parse --show-toplevel` to learn the current worktree root, then `git worktree list --porcelain` to enumerate existing worktrees. Compare and route to exactly one of the three branches below — never run `git worktree add` or `EnterWorktree` without first walking this fork:
       - **Outside any `.claude/worktrees/<dir>` worktree** (toplevel's parent dir basename is NOT `worktrees`): proceed — run `git worktree add -b <branch-name> .claude/worktrees/<dir-name>` via Bash, then call `EnterWorktree` with `path: ".claude/worktrees/<dir-name>"` to switch the session into the already-created worktree.
       - **Already inside `.claude/worktrees/<dir-name>`** (toplevel basename equals the proposed `<dir-name>` AND its parent basename is `worktrees`): skip BOTH `git worktree add` AND `EnterWorktree` — the session is already in the correct worktree. Re-entering would resolve the relative path `.claude/worktrees/<dir-name>` under the current cwd and produce a nested ENOENT (`…/worktrees/<dir-name>/.claude/worktrees/<dir-name>`). Echo `Already in worktree '<dir-name>' — skipping create+enter.` and continue to Phase 2.
       - **Inside a different `.claude/worktrees/<other-dir>` worktree** (parent is `worktrees` but basename is NOT `<dir-name>`): stop and use `AskUserQuestion` header "Worktree" with options "Continue here in `<other-dir>` (skip create+enter)" / "Exit then create `<dir-name>` (call `ExitWorktree`, then re-run this step from repo root)" / "Abort". Do NOT silently create a nested worktree.

       Do NOT use `EnterWorktree(name: ...)` here — that path auto-creates its own branch with a `worktree-` prefix, which would defeat the convention detection above. After this step settles (whether the worktree was just created, the session was already in it, or the user chose to continue in a sibling worktree), if the project has `.env` or similar gitignored config files but no `.worktreeinclude` file, warn the user that environment files won't be present and suggest creating `.worktreeinclude`. Also note: cross-session writes (knowledge/learnings, debug & review handoff state, features registry, codebase maps) auto-route to the main worktree's `.geniro/` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`, so they survive worktree teardown.
    - **Debug handoff verification (post-workspace).** Read `Debug-handoff:`, `Authored-tests:`, and `Debug-source-branch:` from `<task-dir>/state.md` (recorded by Step 1's Debug handoff scan). If `Debug-handoff: detected`, follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` Steps 3-4 against the now-current working tree (which reflects the user's git-workspace choice from the AUQ). When Case B fires (any authored test missing OR branch differs), surface the suggestion block in chat BEFORE proceeding to Phase 2. The user runs the suggested `git checkout` or `cp` commands themselves; do NOT auto-execute. If `Debug-handoff: none`, skip silently.

**Outputs:** spec.md, affected files list, Definition of Done

**Checkpoint:** Write to `<task-dir>/state.md`: "Phase 1 completed."

---

## PHASE 2: ARCHITECT & VALIDATE

**Purpose:** Produce full implementation plan, validate it.

**Pre-check: Existing plan or milestone detection.** Before spawning the architect, check for an existing plan OR a milestone reference from any source:

1. **Milestone reference (highest priority)** — detect a request to implement a single milestone from a decomposed plan. Patterns: `milestone N` argument, milestone-file path, or `continue` with `Milestones:` state. See `${CLAUDE_SKILL_DIR}/implement-reference.md` §Phase 2: Milestone Reference Detection for the full detection rules, skip-architect routing, and milestone-mode scope flag.
2. **Conversation plan (plan mode):** If the conversation contains a structured implementation plan with file-level steps (from Claude Code's plan mode via Shift+Tab, or a prior planning discussion), extract it into `<task-dir>/plan-<slug>.md` following the structure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-criteria.md`. Set the header `Status: approved | Source: plan-mode`. Detection signal: the conversation has a multi-step plan with specific file paths and implementation details — not just a high-level discussion.
3. **Plan files (from /geniro:decompose or a prior /geniro:implement run):** Glob `.geniro/planning/plan-*.md` (flat) AND `.geniro/planning/*/plan-*.md` (task-dir). Read headers, find plans with `Status: approved` that match the current task. If a flat plan matches, move it into `<task-dir>/`. If the plan contains a `## Milestones` section (produced by `/geniro:decompose`) AND `$ARGUMENTS` did not name a specific milestone, use the milestone-mode continue-logic from rule 1 instead of the plan as a whole — warn the user: "This plan is decomposed into N milestones. Running `/geniro:implement continue` or `/geniro:implement milestone <N>` is required. Pick one now." then `AskUserQuestion` listing milestones by name with status.
4. **$ARGUMENTS plan:** If `$ARGUMENTS` contains or references a plan file path (not a milestone file — those are handled in rule 1), read and use it directly.

**Routing (apply the FIRST matching rule):**

1. **If `state.md` shows `Lane: light`:** Skip Phase 2 architect + skeptic entirely. The orchestrator writes a Small-tier lightweight plan directly to `<task-dir>/plan-<slug>.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` Step 3 "Small" tier: Goal + Approach + Steps (no wave grouping, no test scenarios table). Use Phase 1's spec.md, knowledge-retrieval output, and Reuse Inventory as the input. Header: `Status: approved | Source: light-lane`. Skip skeptic-agent. Proceed to Phase 3.
2. **If a plan or milestone is found** (rules 1-4 above matched): Skip architect-agent. Log: "Using existing plan: `<filename>`" or "Using milestone <N>: `<filename>`". Run skeptic-agent to validate (Step 3 below). If skeptic finds blockers, use `AskUserQuestion` (always-WAIT — see implement-reference.md §Auto Mode Behavior): A) Use plan as-is with issues noted, B) Re-architect from scratch (run full architect flow), C) I'll fix the plan manually, then re-validate. Proceed to Phase 3.
3. **If no plan or milestone found AND `Lane: full`:** Run the full architect flow below.

**Architect flow:**

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-criteria.md` for plan structure
2. **Spawn architect-agent** with `model="opus"` and spec + plan criteria + relevant codebase files (pre-inlined). Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` AND `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at this spawn site. **Root-cause classification (mandatory):** spawn prompt MUST require per-design-unit `Root-cause classification` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md` (one of `ROOT-CAUSE`, `SYMPTOM-PATCH`, `MIXED`, `UNKNOWN`, with `Symptom:` + `Suspected root cause:` sub-fields when not ROOT-CAUSE) so Phase 2 routing can fire the gate. **Lane:tdd customization:** when `state.md` shows `Lane: tdd`, the spawn prompt MUST also include the TDD-mode output instructions per `${CLAUDE_SKILL_DIR}/implement-reference.md` §"TDD Mode Semantics" — specifically: "Produce a numbered behavior list (each entry = one future test, ordered for sequential RED→GREEN execution) PLUS a per-module public-interface signature block, INSTEAD OF the standard Steps-table-grouped-by-file plan structure. Each behavior names: the actor, the capability, the trigger condition, the observable outcome. Group behaviors by module so the orchestrator can sort them into cycles. **Read** `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md` §'Test Design Philosophy (canonical)' yourself at runtime (the agent has Read tool) — do NOT pre-inline; it is ~75 lines and re-reading from disk is cheaper than budget bloat in every architect spawn. The behavior list MUST match that rubric so reviewers (Stage C tests-dimension) accept the tests authored against it." Without this customization, the architect would produce a normal Steps table and Lane:tdd's Phase 4 sequential cycles would have no behavior list to drive ordering.
3. **Spawn skeptic-agent** with plan + spec. Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` AND `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`. Explicit instruction: "Write report to `<task-dir>/concerns.md`". **Lane:tdd customization:** when `state.md` shows `Lane: tdd`, the spawn prompt MUST instruct the skeptic to validate the architect's behavior list (NOT a Steps table) against: (a) coverage — every requirement in the spec maps to at least one behavior; (b) ordering — earlier behaviors do not depend on artifacts produced by later behaviors; (c) interface alignment — every behavior names a public interface that appears in the architect's signature blocks. Standard plan-criteria.md dimensions D1-D8 still apply where they make sense (mirage detection, scope, requirement coverage); the file-level dimensions (file count, step count) are skipped — TDD mode has no Steps table to count.
4. **Root-cause gate.** After the architect returns, scan its output for any design unit classified `SYMPTOM-PATCH` or `MIXED`. For each, fire `${CLAUDE_PLUGIN_ROOT}/skills/_shared/root-cause-gate.md` once per unit (Always-WAIT — auto-mode does NOT auto-default). On "Confirmed root cause (proceed)" → re-tag and continue. On "Symptom — escalate to /geniro:debug" → halt the skill and surface the hand-off message. On "Mixed — annotate and proceed" → re-tag `[SYMPTOM-ACK]` and append to the eventual Ship summary's `## Acknowledged tech debt` section. Skip silently when zero SYMPTOM-PATCH/MIXED units exist.
5. If NEEDS REVISION: route back to architect. Max 3 iterations.

**Checkpoint:** Write to `<task-dir>/state.md`: "Phase 2 completed. Plan: <filename>. Skeptic: [N blockers, M warnings]."

---

## PHASE 3: APPROVAL (WAIT)

**Purpose:** Present plan to user for approval.

**Action:** Read and present the full plan file (do NOT summarize).

### Interface-Design Pre-Approval Gate (conditional — Lane:tdd only — runs BEFORE the UI Preview Gate)

If `state.md` shows `Lane: tdd`, run the procedure in `implement-reference.md` §"Interface-Design Pre-Approval Gate (Lane:tdd only)" before any other Phase 3 step. The gate fires `AskUserQuestion` with header "Interface" presenting the architect's proposed public-interface signatures (one code block per module + 1-line "behaviors that exercise this interface") with 3 options: "Interfaces look right (Recommended)" / "Adjust interfaces" / "Restart Phase 2". On "Interfaces look right", write `<task-dir>/interface.md` (canonical reference for all Phase 4 cycles) and proceed to UI Preview Gate (next). On "Adjust" or "Restart", route per the procedure's max-rounds logic. This gate is **Always-WAIT** in Lane:tdd; auto-mode does NOT auto-default. Skip this section entirely when Lane is `full` or `light`.

### UI Preview Gate (conditional — runs before Step 1 below)

If any file in the plan's affected-files list matches the UI-file detection rule in `skills/review/SKILL.md` §UI-file detection rule, run the procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` BEFORE the numbered steps below. Pre-inline the spec, plan, and 1-2 exemplar UI files; save the approved description to `<task-dir>/ui-preview.md`. Phase 4 Work Unit agents that touch UI files pick it up via the `## UI Intent` slot in the Phase 4 Agent Delegation Template (see `implement-reference.md`). If the user picks "Adjust the plan instead" inside the procedure, fire `AskUserQuestion` with header "Adjust" to capture what to change, then run the Adjust path below (architect revises with that context, re-validate, re-present). Skip this section entirely when no affected file matches.

1. Read plan from `<task-dir>/plan-<slug>.md`
2. Present complete plan content to user
3. Add metadata: plan location, skeptic validation summary (N blockers, M warnings)

**Gate:** Always-WAIT — applies in every mode, including `Mode: auto` (see `implement-reference.md` §Auto Mode Behavior, "Plan approval" row). Plan approval gates all Phase 4 code generation, so the LLM MUST get explicit user confirmation; never silently auto-approve.

Use the `AskUserQuestion` tool (do NOT output options as plain text):
- A) **Approve — start building**
- B) **Adjust** — user describes changes
- C) **Too large — split** — decompose into smaller pieces

**Routing:** Approve -> Phase 4. Adjust -> architect revises, re-validate, re-present. Too large -> stop here and tell the user to run `/geniro:decompose <task-dir>/plan-<slug>.md` — the task-dir's spec.md, plan, and concerns.md are preserved so `/geniro:decompose` can pick up where this stopped (skills cannot call skills, the user re-invokes).

**After approval:** Add remaining phases to TodoWrite checklist. Under `Lane: light` (read from state.md), omit phases that Light Mode skips — see `implement-reference.md` §Light Mode Semantics for the full skip list:
- Phase 4: Implement — decompose into WUs, execute waves
- Phase 5: Simplify — spawn simplify agent on changed files (omit under Lane:light)
- Phase 6: Review & Validate — Stage A automated checks, Stage B spec compliance (omit under Lane:light), Stage C code quality, Stage D adversarial tests (omit under Lane:light)
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

**Refresh custom instructions:** re-read `.geniro/instructions/{global,implement,code-style}.md` (if present) — rules survive compaction.

**Purpose:** Execute architecture with parallel agents (Full + Light Lanes) OR sequential RED→GREEN per behavior (TDD Lane).

**Code-style pre-inline preparation:** before Step 1, Read `.geniro/instructions/code-style.md` if it exists; pre-inline its content into each implementation agent's prompt under the `## Code-style instructions` header per the Phase 4 Agent Delegation Template in `${CLAUDE_SKILL_DIR}/implement-reference.md`. If the file does not exist, omit the section entirely.

**Lane gate:** If `state.md` shows `Lane: tdd`, REPLACE the rest of this phase with the sequential cycle procedure in `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 4 in TDD Mode". The TDD procedure replaces parallel waves with one-test-at-a-time RED→GREEN→Refactor cycles, ordered by the architect's behavior list; it does NOT use the Work Unit / Wave / Hotspot model below. Append `Phase 4 (TDD Mode): cycle <N> completed: <behavior summary>` to state.md after each cycle so resume picks up at the next behavior. Test-creation verification (Step 6 below) is REDUNDANT under TDD Mode (every behavior is F→P-verified at cycle authoring); skip it.

**Action (Full + Light Lanes):** Decompose plan into Work Units, arrange into waves, spawn agents.

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
1. **Spawn all WU agents in ONE response** — multiple Agent() calls in the same assistant turn, NOT one per turn (use delegation template from reference file — it includes a mandatory `## Tests` section. Do NOT omit it.). Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` AND `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site.
   **Agent context:** The `backend-agent` and `frontend-agent` read `CLAUDE.md` at runtime for project-specific context. No additional context injection is needed — simply spawn the agent.
2. **Collect results** — each agent must report: files created/modified, tests created/modified, test results
3. **Quick gate** (build + test) — pass/fail only. Every PASS/FAIL claim MUST attach an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` (command, exit code, last 3 lines). If fails, forward the raw error output to a fixer agent. Do NOT read source files, diagnose the error, or apply fixes yourself — copy the terminal output into the agent prompt and let it handle everything.
4. **Start next wave**

### Step 4: Hotspot files (orchestrator micro-edits only)

Strictly limited to 1-2 line registrations. If >3 lines or any logic -> delegate to subagent.

### Step 5: Post-wave validation

- **If only one wave was arranged in Step 2** (i.e., Step 3 ran exactly once — Trivial/Small Full Lane plans typically), skip Step 5 entirely: Step 3's quick-gate after the single wave is the post-wave gate by construction. Append "Phase 4 Step 5 skipped — single wave; Step 3 quick-gate is the post-wave gate" to `<task-dir>/state.md` and proceed.
- **For multi-wave runs**, Step 5 still serves as the inter-wave regression gate. Run **build + test** — pass/fail gate only. Do NOT include lint (Phase 5 handles that). If fails, forward the raw error output to a fixer agent. Do NOT read source files, diagnose the error, or apply fixes yourself — copy the terminal output into the agent prompt and let it handle everything.

### Step 6: Test creation verification

**Action:** Check that tests were actually created for new/changed source files.

1. Get the list of changed source files (resolve the base per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` rule #3 — do NOT hardcode `main`): `BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || (git rev-parse --verify main >/dev/null 2>&1 && echo main) || echo master); git diff --name-only "$BASE"...HEAD | grep -v test | grep -v spec | grep -v node_modules`
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

**Lane gate:** 
- If `state.md` shows `Lane: light`, skip Phase 5 entirely. Append to `state.md`: "Phase 5 skipped — Lane: light (Light Mode skips simplify per implement-reference.md §Light Mode Semantics)." Proceed to Phase 6.
- If `state.md` shows `Lane: tdd`, the whole-feature simplify pass is REPLACED by per-cycle micro-refactors that ran during Phase 4 (step 6 of each TDD cycle). Skip the spawn below; append to `state.md`: "Phase 5 skipped — Lane: tdd (per-cycle micro-refactor in Phase 4 cycles, see Phase 4 (TDD Mode) cycle log)." Proceed to Phase 6.

**Action (Full Lane only):** Spawn simplify agent. Read `${CLAUDE_SKILL_DIR}/implement-reference.md` section "Phase 5: Simplify Agent Template" for the agent prompt.

### Step 1: Spawn simplify agent

Read `${CLAUDE_PLUGIN_ROOT}/skills/deep-simplify/simplify-criteria.md`. Spawn a **general-purpose** subagent with `model: "sonnet"` using the template from the reference file. Pre-inline the criteria and the changed file list.

### Step 2: Verify after simplification

1. Read the simplify-agent's `## Checks Report` from its return (the agent ran autofix + build + lint + test as part of its Definition of Done — see `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 5: Simplify Agent Template"). Every PASS/FAIL claim attached MUST carry an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`.
2. **If the report shows any FAIL or is missing:** revert simplification (`git checkout -- .`), note "Simplification skipped — caused CI failures." Proceed to Phase 6.
3. **Otherwise:** the simplify-agent's PASS verdict carries forward into Phase 6 Stage A's cache check (see `implement-reference.md` §"Phase 6: Stage A — Automated Checks Detail" — cache invalidation governed by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-cache.md`). Do NOT re-run build/lint/test here — that would duplicate Stage A.

**Anti-rationalization:**
| Your reasoning | Why it's wrong |
|---|---|
| "The code is already clean enough" | AI-generated code almost always has over-abstraction or verbose patterns. Run the check. |
| "Simplification might break things" | That's why we run checks after. If it breaks, we revert. Zero risk. |
| "Let me run CI first (Stage A), then decide on simplification" | Phase 5 comes BEFORE Phase 6. Simplify first, validate after. Do NOT merge or reorder phases. |

**Checkpoint:** Write to `<task-dir>/state.md`: "Phase 5 completed. Simplify agent ran. Post-simplify verification: PASS/REVERTED."

---

## PHASE 6: REVIEW & VALIDATE

**Refresh custom instructions:** re-read `.geniro/instructions/{global,implement,code-style}.md` (if present) — rules survive compaction.

**Purpose:** Single quality gate — verify code compiles, passes tests, meets spec, and is well-written.

**Action:** Run Stage A checks, spawn Stage B agent, spawn Stage C agents, then spawn Stage D adversarial-tester-agent.

Read `${CLAUDE_SKILL_DIR}/implement-reference.md` sections "Phase 6: Stage A", "Phase 6: Stage B", "Phase 6: Stage C", "Phase 6: Fix Loop", and "Phase 6: Stage D" for detailed procedures and templates.

**Four stages, run in order:**

### Stage A — Automated Checks

Run autofix, full check (build + lint + test), codegen check, runtime startup check. If any fails, forward the raw error output to a fixer agent — do NOT read source files, diagnose, or fix it yourself. Max 2 attempts, then continue to the next stage with failures noted (Stage B in Full pipeline; Stage C in Light Mode since Stage B is skipped).

**Checkpoint:** Update `<task-dir>/state.md`: "Phase 6 Stage A completed."

### Stage B — Spec Compliance

**Lane gate:** If `state.md` shows `Lane: light`, skip Stage B entirely. Light Mode does not run architect+skeptic and therefore has no full spec.md/plan-spec contract to verify — the lightweight plan from Phase 2 already lists Goal + Approach + Steps; Stage C reviewers verify code-against-plan via the diff. Append to `state.md`: "Phase 6 Stage B skipped — Lane: light." Proceed to Stage C.

**Action:** Spawn spec-compliance subagent using the template from the reference file. Pre-inline spec, plan, changed files.

Read `<task-dir>/compliance.md` after agent completes. If any requirement unmet -> spawn a fixer agent with the gap details and affected files pre-inlined. Do NOT read source files, diagnose gaps, or apply fixes yourself — delegate to the agent. Max 2 rounds.

**Checkpoint:** Update `<task-dir>/state.md`: "Phase 6 Stage B completed. Compliance: PASS."

### Stage C — Code Quality

**Action:** Spawn 7–8 parallel reviewer agents in ONE response — all Agent() calls in the same assistant turn, NOT one per turn — bugs, security, architecture, tests, optimizations, guidelines, conventions, plus design when changed files include UI (see UI-file detection rule in `skills/review/SKILL.md`). Use templates from reference file. If `.geniro/instructions/code-style.md` exists, pre-inline its content into the prompts for the guidelines / conventions / design / architecture reviewers under the `## Code-style instructions` header per the Stage C reviewer template in `${CLAUDE_SKILL_DIR}/implement-reference.md`. Skip the slot for bugs / security / tests / optimizations reviewers (code-style is orthogonal).

Aggregate findings. Pass CRITICAL/HIGH to fix loop; preserve MEDIUM findings (do NOT auto-drop) for the user-gated inclusion check at the top of the Fix Loop — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`. Write `<task-dir>/review-feedback.md` with body sub-fields persisted for both CRITICAL/HIGH and MEDIUM rows so the gate can render bodies correctly. Findings tagged `decision: PRODUCT-DECISION` flow through to the Fix Loop where the open-decision gate (always-WAIT — see implement-reference.md §Auto Mode Behavior, `[PRODUCT-DECISION] finding encountered` row) presents enumerated options to the user before any fixer agent spawns; MEDIUM findings flow through to the same Fix Loop where the MEDIUM inclusion gate (always-WAIT — see implement-reference.md §Auto Mode Behavior, `MEDIUM findings present in fix-loop entry` row) lets the user pick which (if any) to include.

**Fix loop:** Max 3 rounds. Spawn NEW fixer + FRESH reviewers each round (anchoring bias). After 3 rounds, present handoff to user (always-WAIT — see implement-reference.md §Auto Mode Behavior).

**Checkpoint:** Update `<task-dir>/state.md`: "Phase 6 Stage C completed."

### Stage D — Adversarial Edge-Case Tests

**Purpose:** Attacker-mindset pass that complements Stage C. Where Stage C's `tests-criteria.md` reviewer REPORTS coverage/quality gaps in EXISTING tests, Stage D AUTHORS NEW failing tests (F→P-verified: red today) for edge cases the implementer's happy-path-plus-2-edge tests missed. Authored tests feed the existing Fix Loop above ("make the red tests green").

**Action:** Spawn one `adversarial-tester-agent` (per canonical model-tiering carve-out — frontmatter-declared `model: inherit`, omit `model=` at the spawn site to mirror orchestrator tier; reasoning-grade test authoring) with the diff, the shared checklist path `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`, 1-2 exemplar test files, the project test command (from CLAUDE.md or package.json), Stage C findings as hypothesis seeds, and output path `<task-dir>/adversarial-tests.md`. See `${CLAUDE_SKILL_DIR}/implement-reference.md` §Phase 6 Stage D for the full spawn template.

**Orchestrator responsibilities after the agent returns:**
1. **Re-verify F→P independently.** Run the authored tests yourself — do NOT trust the agent's self-report. Any test that passes today is removed from scope; log it and continue.
2. **Route confirmed failing tests into the Fix Loop.** Each F→P-confirmed test becomes a CRITICAL/HIGH item in `<task-dir>/review-feedback.md` with severity from the agent's report. The existing Fix Loop (max 3 rounds) applies — fresh fixer agents make the red tests green. Do NOT skip the flake-recheck on the fixer's output.
3. **Scope hard cap.** The agent authors at most 10 tests per run. If the agent reported hitting the cap with more hypotheses pending, append the overflow to the Phase 7 Step 4 summary under "Deferred ideas" rather than expanding this run.

**Skip Stage D entirely when:** `state.md` shows `Lane: light` (Light Mode skips Stage D — append "Phase 6 Stage D skipped — Lane: light" to state.md); OR `state.md` shows `Lane: tdd` (TDD Mode every-behavior-already-F→P-verified at cycle authoring — append "Phase 6 Stage D skipped — Lane: tdd (every behavior F→P-verified during Phase 4 cycles)" to state.md); OR diff contains zero production-code files (docs/config/lockfile-only); OR `Mode: auto` AND diff ≤3 files AND Stage C had zero CRITICAL/HIGH tests-dimension findings (note the skip in state.md "Auto-mode decisions"). Anti-rationalization: "Stage C already covers tests" — NO: Stage C REPORTS gaps; Stage D AUTHORS failing tests (different lifecycle). Never trust the agent's F→P self-report — re-run the tests yourself.

**Checkpoint:** Update `<task-dir>/state.md`: if Stage D ran, write "Phase 6 completed. All stages passed."; if skipped, write "Phase 6 Stage D skipped — <reason>" then "Phase 6 completed."

---

## PHASE 7: SHIP & FINALIZE (WAIT)

**Refresh custom instructions:** re-read `.geniro/instructions/{global,implement,code-style}.md` (if present) — rules survive compaction.

**Precondition:** Do NOT enter Phase 7 until `state.md` shows Phase 5 completed-or-skipped, Phase 6 Stage A completed, Stage B completed-or-skipped, Stage C completed, and Stage D completed-or-skipped (with logged reason for skips). If any is missing, go back and complete it.

### PART A: FINALIZE (Steps 1-4 — runs automatically, no user input needed)

These steps run BEFORE presenting the ship decision. They cannot be skipped.

**Step 1: Update Docs** — Check if existing docs need patching. Delegate if needed, skip silently if not. See reference file for details.

**Step 2: Extract Learnings** — Scan conversation for corrections, gotchas, decisions. Save to learnings.jsonl and/or memory (resolved via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`). See reference file for signal table.

**Step 3: Suggest Improvements (project scope only) (WAIT — auto: see implement-reference.md §Auto Mode Behavior)** — Follow the canonical routing in `skills/_shared/improvement-routing.md`: **code rules / coding conventions / style or naming patterns / file-pattern constraints → `.claude/rules/<scope>.md` with `paths:` glob** (Anthropic-native, file-scoped — auto-loads when matching files are touched); skill-behavior quality gates / workflow steps / hard constraints → `.geniro/instructions/<skill>.md` (Geniro skill-scoped); CLAUDE.md is reserved for commands, project structure, and compaction-surviving gates; gotchas / decisions → knowledge; auto-enforceable patterns → project rules/hooks. Plugin-file improvements (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope — use `/improve-template`. Present grouped by target via `AskUserQuestion`.

**Step 4: Present Summary**

1. **Features implemented** (list)
2. **Files changed** (grouped by area: backend/frontend/tests/config)
3. **Tests added/modified**
4. **Review feedback addressed** (count of issues fixed; for any deferred MEDIUMs from the Phase 6 Stage C MEDIUM inclusion gate, also report `Deferred MEDIUM: N — see <task-dir>/review-feedback.md ## Deferred MEDIUM` so the user has a documented backlog)
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

### Step 8: Integration Updates + Cleanup — auto: see implement-reference.md §Auto Mode Behavior

- **Worktree:** If working in a worktree, leave the session in it — do NOT call `ExitWorktree`. Per the tool's contract it is invoked only when the user explicitly asks to exit; the runtime already prompts on session exit to keep or remove the worktree. After "leave uncommitted", note that changes remain at `.claude/worktrees/<name>/` so the user knows where to find them.
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
| "Batch Smoke-test + Ship Decision in one AUQ" | Step 5 offers commit/push/PR — asking alongside UI-check lets the user commit before verifying UI. Smoke-test is standalone; Step 5 fires after verification resolves. |
| "Split the Mode/Lane/Feature/Git-workspace questions across separate AUQs" | These four are independent and `AskUserQuestion` accepts 4 questions per call — splitting is pure friction. Phase 1 Startup Consolidation batches them. |
| "Auto-pick the recommended path for a `[PRODUCT-DECISION]` finding" | `[PRODUCT-DECISION]` is Always-WAIT. The `recommendation:` field is a synthesis of valid options, not the chosen path — picking ships an unauthorized product decision. |

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

**Token conservation — delegate ALL implementation work:** The orchestrator's job is to coordinate, not to code. Every line of code the orchestrator writes wastes expensive context. Delegate ALL work to subagents — including deletions, cleanups, "simple" edits. If you catch yourself thinking "I'll just do this directly since it's simple" — that's the rationalization. Spawn an agent.

**Anti-rationalization:**
| Your reasoning | Why it's wrong |
|---|---|
| "Steps X-Y are small, I'll handle them myself" | Every plan step becomes a WU. Group small related steps into one WU, but never execute as orchestrator. |
| "The build failed, let me read the source and fix it quickly" | Run the check, copy the raw terminal output into a fixer agent prompt. Do NOT open source files, diagnose, search for types, or apply edits yourself. |
| "I'll create a new helper / component / type for this — quicker than checking what exists" | Run the Reuse Inventory first (Grep/Glob for analogues with `file:line`). Convention drift is the #1 AI failure mode. Categorize REUSE-AS-IS / EXTEND / NO-ANALOGUE; if reuse requires adding a parameter or conditional to fit, prefer local duplication and revisit at the third occurrence (Rule of Three). |
| "I'll upgrade this haiku spawn to sonnet just to be safe" | Tier matches task nature, not risk appetite. Upgrading mechanical-task agents (docs, guidelines) to sonnet defeats the cost rationale and signals drift. Re-classify via the Subagent Model Tiering table — don't silently upsize. |
| "I'll spawn agents one at a time" | All parallel agents MUST be spawned in ONE response — multiple Agent() calls in the same assistant turn. Separate turns = no concurrency, full wall-clock latency per agent. Only sequence when outputs feed into next agent (e.g., plan → skeptic) or files overlap. |

---

## REFERENCE

- Agent templates, examples, error tables: `${CLAUDE_SKILL_DIR}/implement-reference.md`
- Plan criteria: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-criteria.md`
- Review criteria: `${CLAUDE_PLUGIN_ROOT}/skills/review/` (bugs, security, architecture, tests, optimizations, guidelines, conventions, +design when UI files changed)
- Simplify criteria: `${CLAUDE_PLUGIN_ROOT}/skills/deep-simplify/simplify-criteria.md`
