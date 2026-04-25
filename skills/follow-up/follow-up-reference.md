# Follow-Up Skill — Reference Material

This file contains templates, examples, and detailed procedures referenced by SKILL.md. The orchestrator reads specific sections at the relevant phase — not the entire file at once.

---

## Phase 2 Step 2: Agent Delegation Templates

**Trivial** (1–2 files, obvious fix): Delegate to a single agent (same template as Small below, without Tests section). Even Trivial goes through agents — orchestrator context is too expensive for implementation.

**Small** (3–5 files, 1–2 modules): Delegate to a single agent:

```
Agent(model="sonnet", prompt="""
## Task
[describe the specific change needed]
## Pre-Inlined Context: [file contents from Phase 1]
## UI Intent (only when UI Preview Gate ran in Phase 1 Step 4): [paste approved description verbatim; match it exactly; omit this section entirely if the gate did not run]
## Codebase Conventions: match existing patterns exactly. Before writing any new helper / component / type / config, Grep the project for an analogue first — REUSE-AS-IS or EXTEND existing code instead of creating new. If reuse requires adding a parameter or conditional to fit, prefer local duplication (Rule of Three).
## Reuse Inventory (when supplied by Phase 1): [paste REUSE_INVENTORY if present; for Trivial Fast Lane it will be omitted — rely on the verify-before-creating instruction above]
## Tests — MANDATORY: create/update test file per changed source, follow existing patterns, run and report
## Requirements: follow CLAUDE.md, do NOT git add/commit/push, run validation, report changes and issues
After validation, append: ## Checks Report with lines: build: PASS|FAIL, lint: PASS|FAIL, test: PASS|FAIL
""")
```

**Medium** (6–8 files, up to 2 modules): Decompose into 2–3 parallel agents by module/layer, spawn in **ONE response** — all Agent() calls in the same assistant turn, NOT one per turn:

1. Group plan files by module/layer (e.g., backend vs frontend, entity+service vs DTO+hook)
2. Each agent gets its own file group — no overlap
3. Pre-inline the file contents each agent needs from Phase 1

```
# Spawn ALL agents in ONE response — multiple Agent() calls in the same assistant turn, NOT one per turn.
# Per-agent prompt sections: Task, Pre-Inlined Context, Tests — MANDATORY, Requirements (scope/CLAUDE.md/no-git/report)

Agent(model="sonnet", prompt="""
## Task — Group N: [module/layer name]
[changes for this group]
## Pre-Inlined Context: [file contents]
## UI Intent (only when UI Preview Gate ran in Phase 1 Step 4 AND this group touches UI files): [paste approved description verbatim; match it exactly; omit this section entirely otherwise]
## Codebase Conventions: match existing patterns exactly. Before writing any new helper / component / type / config, Grep the project for an analogue first — REUSE-AS-IS or EXTEND existing code instead of creating new. If reuse requires adding a parameter or conditional to fit, prefer local duplication (Rule of Three).
## Reuse Inventory (when supplied by Phase 1): [paste REUSE_INVENTORY if present; for Trivial Fast Lane it will be omitted — rely on the verify-before-creating instruction above]
## Tests — MANDATORY: create/update test file per changed source, follow existing patterns, run and report
## Requirements: ONLY modify [list files], follow CLAUDE.md, do NOT git add/commit/push, report changes
After validation, append: ## Checks Report with lines: build: PASS|FAIL, lint: PASS|FAIL, test: PASS|FAIL
""", description="Implement [group N]")
# Repeat the Agent(...) block per group — all in the same assistant turn.
```

If all files are tightly coupled (same module, sequential deps), use a single agent — don't force parallelism.

---

## Phase 5 Step 1: Reviewer Agent Templates

**Small changes in Full pipeline (3–5 files):** Spawn a single reviewer-agent. Pass criteria file paths — the agent reads them itself. Do NOT pre-read criteria into orchestrator context.

```
Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
## Review: Follow-Up Change
This is a follow-up change — focus on correctness and regressions. CI already passed. Keep review proportional to change size.

CHANGED FILES (with full contents, pre-inlined): [list each file path followed by its complete content — use the file contents already in orchestrator context from Phase 1]
DIFF CONTEXT: [paste `git diff main...HEAD` output — used to tag findings as [NEW] vs [PRE-EXISTING]]
CHANGE SUMMARY: [summary]

## Review Criteria
Read and apply the criteria files (5, +design when UI files changed) from `${CLAUDE_PLUGIN_ROOT}/skills/review/`:
- `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/security-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/architecture-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/guidelines-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/design-criteria.md` (conditional — when changed files include UI; see UI-file detection rule in skills/review/SKILL.md)

Review across all listed criteria files (5, or 6 when design is included for UI changes). Report findings with severity (CRITICAL/HIGH/MEDIUM) and confidence. Skip MEDIUM — only report CRITICAL and HIGH.

Return findings as evidence. Do NOT emit an overall verdict (CHANGES REQUIRED / APPROVED / APPROVED WITH MINOR) — the orchestrating skill synthesizes findings across all reviewers and decides.
""", description="Review: follow-up change")
```

**Medium changes (6–8 files):** Spawn 2–3 reviewer-agent instances in **ONE response** — all Agent() calls in the same assistant turn, NOT one per turn. Each agent reads its own criteria — do NOT pre-read into orchestrator context:

```
# Spawn ALL reviewers in ONE response — multiple Agent() calls in the same assistant turn, NOT one per turn:

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: Bugs & Correctness
CHANGED FILES (with full contents, pre-inlined): [list each file path followed by its complete content — from Phase 1 orchestrator context]
DIFF CONTEXT: [paste `git diff main...HEAD` output — used to tag findings as [NEW] vs [PRE-EXISTING]]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed. Keep review proportional.
Report findings with severity (CRITICAL/HIGH/MEDIUM) and confidence. Skip MEDIUM — only report CRITICAL and HIGH. Return findings as evidence; do NOT emit an overall verdict — the orchestrating skill synthesizes across reviewers and decides.

## Review Criteria
Read and apply this criteria file: `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md`
""", description="Review: bugs")

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: Security & Edge Cases
CHANGED FILES (with full contents, pre-inlined): [list each file path followed by its complete content — from Phase 1 orchestrator context]
DIFF CONTEXT: [paste `git diff main...HEAD` output — used to tag findings as [NEW] vs [PRE-EXISTING]]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed. Keep review proportional.
Report findings with severity (CRITICAL/HIGH/MEDIUM) and confidence. Skip MEDIUM — only report CRITICAL and HIGH. Return findings as evidence; do NOT emit an overall verdict — the orchestrating skill synthesizes across reviewers and decides.

## Review Criteria
Read and apply this criteria file: `${CLAUDE_PLUGIN_ROOT}/skills/review/security-criteria.md`
""", description="Review: security")
```

Add a 3rd reviewer (architecture + tests + guidelines) only if changes touch cross-module boundaries. Reads `architecture-criteria.md`, `tests-criteria.md`, `guidelines-criteria.md` under `${CLAUDE_PLUGIN_ROOT}/skills/review/`.
Add a 4th reviewer with `model='haiku'` for the design dimension when changed files include UI (criteria: `${CLAUDE_PLUGIN_ROOT}/skills/review/design-criteria.md`). Skip otherwise.

---

## Phase 5 Step 1.5: Adversarial Tester Template (Medium only)

Spawn the new agent AFTER the Step 1 reviewers return, BEFORE Step 2 aggregation.

```
Agent(subagent_type="adversarial-tester-agent", model="sonnet", prompt="""
## Task: Adversarial Edge-Case Test Authoring (Follow-Up — Medium)

### Diff (changed files + contents)
[Pre-inline `git diff main...HEAD` output AND full contents of every changed source file from Phase 1]

### Shared Edge-Case Checklist (READ this file yourself at runtime — do NOT paste here)
`${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`

### Project Test Framework
- Test command (from CLAUDE.md Essential Commands): [e.g. `pnpm test`, `pytest`]
- Test-file naming convention: [project's pattern — e.g. `*.test.ts` adjacent to source]
- Exemplar test files (1-2, pre-inlined): [closest existing test files to the changed code]

### Hypothesis Seeds (optional)
[Paste CRITICAL/HIGH findings from Step 1 Medium reviewers' tests dimension, if any. Use as seeds only.]

### Output
Write your report to `.geniro/follow-up-state-adversarial.md`. Authored test files go to the project's normal test paths. Do NOT git add/commit/push.

### F→P Invariant (NON-NEGOTIABLE)
Every test you keep MUST fail 3 times in a row on the current code. If it passes today, delete the test and mark `discarded-cannot-repro`. Flaky = discard.

### Scope
Diff-only (Medium = 6-8 files). Do NOT author tests for files outside the changed-files list. Hard cap: 10 authored tests.
""", description="Adversarial tests: follow-up Medium")
```

**Orchestrator synthesis:**
1. Read `.geniro/follow-up-state-adversarial.md`, extract authored test file paths.
2. Run the project's test command on each authored test individually — 3 consecutive identical failures = keep; otherwise delete.
3. For each kept test, add a CRITICAL/HIGH entry to the Step 2 aggregate (severity per agent report) tagged `origin: step-1.5-adversarial`.
4. If the agent reported hitting the 10-test cap, note overflow hypotheses in the Phase 6 ship summary under "Deferred".

**Fallback:** If the adversarial-tester-agent fails (timeout, garbage), retry ONCE. Second failure → skip Step 1.5, log "Step 1.5 skipped — adversarial-tester-agent unavailable after retry" and proceed to Step 2. Do NOT block the pipeline on infrastructure failures.
