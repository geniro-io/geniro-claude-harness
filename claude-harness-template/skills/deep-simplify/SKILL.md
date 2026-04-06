---
name: deep-simplify
description: "Three-pass parallel code review. Spawns 3 subagents (reuse, quality, efficiency) on changed files, aggregates findings by severity, applies P1/P2 fixes, reverts if CI breaks. Zero behavior change guaranteed."
context: main
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[files or 'changed' for git diff]"
---

# Deep Simplify — Parallel Code Review

You are a **review orchestrator**. You spawn 3 specialized subagents in parallel, aggregate their findings, apply fixes, and verify. You do NOT analyze code yourself.

**Pipeline:** Scope → Parallel Review (3 agents) → Aggregate → Fix → Verify

---

## Phase 1: Scope

### Step 1: Identify Changed Files

If `$ARGUMENTS` contains "changed", run:
```bash
git diff --name-only origin/main...HEAD | grep -v node_modules | grep -v -E '(\.lock|package-lock)'
```

Otherwise, treat `$ARGUMENTS` as a list of specific files or directories.

**If no changed files found:** report "No changed files to simplify" and stop.
**If more than 20 changed source files:** focus on the 20 most recently modified. Note skipped files.

Exclude: test files (`*.spec.*`, `*.test.*`, `*.int.*`, `*.cy.*`), generated code, type-only files (`*.types.ts`, `*.d.ts`).

### Step 2: Read Criteria and Files

1. Read `${CLAUDE_SKILL_DIR}/simplify-criteria.md` — you will inline the relevant section into each agent's prompt
2. Read each changed source file + immediate neighbors (imports from same module) for context

You need the full contents because you will inline them into agent prompts.

---

## Phase 2: Parallel Review — Spawn 3 Agents

Spawn all 3 agents **in a single message** using the Agent tool. Each agent gets: ground rules, its specific analysis pass criteria, and the full contents of changed files inlined.

**All 3 agents MUST be spawned in one message. Do NOT wait for one before spawning the next.**

### Agent 1: Reuse & Duplication

Spawn a **general-purpose** subagent with `model: "sonnet"`:

```
## Task: Reuse & Duplication Review

You are a code reviewer focused on finding duplication and reuse opportunities.

## Ground Rules
[Inline Ground Rules section from simplify-criteria.md]

## Analysis Criteria — Pass A: Reuse & Duplication
[Inline Pass A table from simplify-criteria.md]

## Changed Files
[Inline full contents of each changed file with filename headers]

## Instructions
1. Read each file's immediate neighbors (imports from same module) for reuse context
2. Analyze each file for Pass A patterns only
3. For each finding report: file, line number, pattern matched, proposed fix
4. Classify: P1 (fix) or P2 (fix if safe) per severity below
5. Do NOT make any edits — report findings only

## Severity
- P1: Duplication with existing utility, dead code
- P2: Similar switch branches consolidation, test setup duplication

## Output Format
Return a JSON array:
[{"file": "path", "line": N, "pattern": "name", "severity": "P1|P2", "description": "what", "fix": "how"}]
If no findings, return: []
```

### Agent 2: Quality & Readability

Spawn a **general-purpose** subagent with `model: "sonnet"`:

```
## Task: Quality & Readability Review

You are a code reviewer focused on readability, naming, and AI-generated anti-patterns.

## Ground Rules
[Inline Ground Rules section from simplify-criteria.md]

## Analysis Criteria — Pass B: Quality & Readability
[Inline Pass B table, AI-Generated Code Anti-Patterns table, and Frontend-Specific table from simplify-criteria.md]

## Changed Files
[Inline full contents of each changed file with filename headers]

## Instructions
1. Analyze each file for Pass B patterns only
2. Actively check for AI-generated code anti-patterns (over-abstraction, verbose error handling, unnecessary wrappers, over-documentation)
3. For each finding report: file, line number, pattern matched, proposed fix
4. Classify: P1 or P2 per severity below
5. Do NOT make any edits — report findings only

## Severity
- P1: Deep nesting fixable with guard clauses, AI over-abstraction, redundant try/catch, commented-out code, dead code
- P2: Naming improvements, comment cleanup, complex boolean extraction, effect splitting

## Output Format
Return a JSON array:
[{"file": "path", "line": N, "pattern": "name", "severity": "P1|P2", "description": "what", "fix": "how"}]
If no findings, return: []
```

### Agent 3: Efficiency & Patterns

Spawn a **general-purpose** subagent with `model: "sonnet"`:

```
## Task: Efficiency & Patterns Review

You are a code reviewer focused on unnecessary complexity and inefficient patterns.

## Ground Rules
[Inline Ground Rules section from simplify-criteria.md]

## Analysis Criteria — Pass C: Efficiency & Patterns
[Inline Pass C table from simplify-criteria.md]

## Changed Files
[Inline full contents of each changed file with filename headers]

## Instructions
1. Analyze each file for Pass C patterns only
2. For each finding report: file, line number, pattern matched, proposed fix
3. Classify: P1, P2, or P3 per severity below
4. Do NOT make any edits — report findings only

## Severity
- P1: Redundant try/catch that just rethrows
- P2: Unnecessary intermediate variables, redundant null checks, manual loops replaceable with builtins
- P3 (report only): Business logic in controllers, N+1 patterns, circular dependencies

## Output Format
Return a JSON array:
[{"file": "path", "line": N, "pattern": "name", "severity": "P1|P2|P3", "description": "what", "fix": "how"}]
If no findings, return: []
```

---

## Phase 3: Aggregate

Collect findings from all 3 agents. Merge into a single list:

1. **Deduplicate** — if two agents flagged the same line, keep the higher-severity finding
2. **Sort** — P1 first, then P2, grouped by file
3. **Separate P3** — report only, never applied
4. **Conflict check** — if two findings target the same code range with contradictory fixes, keep the one with clearer criteria match

---

## Phase 4: Fix

### Step 1: Apply P1 Fixes

Apply all P1 fixes using Edit. If extracting a utility to a new file, update imports in consuming files.

### Step 2: Apply P2 Fixes

Apply P2 fixes. Skip any that feel risky (could change behavior) — note as "skipped — behavior change risk."

**Do NOT run validation after each fix. Batch all fixes, then verify once.**

### Step 3: Fix Test References (if needed)

If source changes broke test imports/references: update imports only. Never change test assertions.

---

## Phase 5: Verify

### Step 1: Autofix

Run the project's format/autofix command from CLAUDE.md.

### Step 2: Full Validation

Run build + lint + test:
```bash
source .claude/hooks/backpressure.sh 2>/dev/null
run_silent "Full Check" "<validation_cmd>" || <validation_cmd> 2>&1 | tail -80
```

### Step 3: Handle Failures

**If validation passes:** Done. Report results.

**If validation fails:**
1. Read errors
2. If caused by a simplification change: revert that file (`git checkout -- <file>`), note "skipped — caused CI failure"
3. Re-run validation
4. **Max 1 revert-and-retry cycle.** If still failing, revert ALL changes (`git checkout -- .`) and report "Simplification aborted — changes caused cascading failures"

---

## Completion Report

```
## Deep Simplify Results

### Applied (N fixes)
- [file:line] — [what changed] (P1/P2) — [agent: Reuse|Quality|Efficiency]

### Skipped (N items)
- [file:line] — [what was found] — skipped because [reason]

### Notes for User (P3)
- [file:line] — [observation] — suggested follow-up

### Verification
- Validation: PASS/FAIL
- Files modified: N
- Lines added/removed: +N/-M
- Agents: 3 parallel (Reuse, Quality, Efficiency)
```

---

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "I can analyze the code myself without spawning agents" | You are an orchestrator. Spawn all 3 agents. Parallel review catches more than a single pass. |
| "One agent is enough for these few files" | Spawn all 3. Each has a different lens — even small files have reuse, quality, AND efficiency dimensions. |
| "I'll spawn agents one at a time to save tokens" | Spawn all 3 in a SINGLE message. Sequential spawning defeats the purpose of parallel review. |
| "These changes are obviously safe" | Run validation. "Obviously safe" is the #1 predictor of broken builds. |
| "I'll fix the P3 items too since I'm here" | P3 is report-only. Fixing P3 risks behavior changes. |

---

## Definition of Done

- [ ] 3 review agents spawned in parallel
- [ ] Findings aggregated and deduplicated
- [ ] All P1 and safe P2 fixes applied
- [ ] Full validation passes
- [ ] No behavior changes (verified by test suite)
- [ ] P3 notes documented for user
- [ ] Completion report presented

## Examples

```
/deep-simplify changed
/deep-simplify src/auth/login.ts src/auth/session.ts
/deep-simplify focus on reducing duplication in utils/
```
