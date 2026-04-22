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
## Codebase Conventions: match existing patterns exactly
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
Agent(model="sonnet", prompt="""
## Review: Follow-Up Change
This is a follow-up change — focus on correctness and regressions. CI already passed. Keep review proportional to change size.

CHANGED FILES: [list]
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

Agent(model="sonnet", prompt="""
DIMENSION: Bugs & Correctness
CHANGED FILES: [list]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed. Keep review proportional.
Report findings with severity (CRITICAL/HIGH/MEDIUM) and confidence. Skip MEDIUM — only report CRITICAL and HIGH. Return findings as evidence; do NOT emit an overall verdict — the orchestrating skill synthesizes across reviewers and decides.

## Review Criteria
Read and apply this criteria file: `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md`
""", description="Review: bugs")

Agent(model="sonnet", prompt="""
DIMENSION: Security & Edge Cases
CHANGED FILES: [list]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed. Keep review proportional.
Report findings with severity (CRITICAL/HIGH/MEDIUM) and confidence. Skip MEDIUM — only report CRITICAL and HIGH. Return findings as evidence; do NOT emit an overall verdict — the orchestrating skill synthesizes across reviewers and decides.

## Review Criteria
Read and apply this criteria file: `${CLAUDE_PLUGIN_ROOT}/skills/review/security-criteria.md`
""", description="Review: security")
```

Add a 3rd reviewer (architecture + tests + guidelines) only if changes touch cross-module boundaries. Reads `architecture-criteria.md`, `tests-criteria.md`, `guidelines-criteria.md` under `${CLAUDE_PLUGIN_ROOT}/skills/review/`.
Add a 4th reviewer with `model='haiku'` for the design dimension when changed files include UI (criteria: `${CLAUDE_PLUGIN_ROOT}/skills/review/design-criteria.md`). Skip otherwise.
