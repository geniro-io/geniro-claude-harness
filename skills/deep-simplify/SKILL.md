---
name: geniro:deep-simplify
description: "Three-pass parallel code review. Spawns 3 subagents (reuse, quality, efficiency) on changed files, aggregates findings by severity, applies P1/P2 fixes, reverts if CI breaks. Zero behavior change guaranteed."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[files or 'changed' for git diff]"
---

# Deep Simplify — Parallel Code Review

You are a **review orchestrator**. You spawn 3 specialized subagents in parallel, aggregate their findings, apply fixes, and verify. You do NOT analyze code yourself.

**Pipeline:** Scope → Parallel Review (3 agents) → Aggregate & Filter → Fix → Verify

## Agent Failure Handling

If any delegated agent fails (timeout, error, empty/garbage result): retry once with the same prompt. If the retry also fails:
- **Phase 2 agents:** proceed without its findings and note "Agent [N] failed — dimension not reviewed" in the Completion Report
- **Phase 4/5 agents:** escalate to the user — fix/verify failures cannot be silently skipped

---

## Subagent Model Tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly.

**Skill-specific mapping** — all three review dimensions are reasoning-heavy (require code understanding to spot duplication, dead code, perf smells), so all stay on `sonnet`:

| Spawn | Tier | Rationale |
|---|---|---|
| Reuse reviewer | `sonnet` | Detecting duplication needs cross-file reasoning |
| Quality reviewer | `sonnet` | Identifying dead code / smells needs intent reasoning |
| Efficiency reviewer | `sonnet` | Spotting perf issues needs algorithmic reasoning |
| `relevance-filter-agent` | `sonnet` | Adversarial validation against repo conventions |

No spawns escalate to `opus` — these reviewers are bounded scope. If a finding requires architectural rework, the user invokes `/geniro:refactor` or `/geniro:implement`.

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

### Step 2: Prepare File List

1. Run `git diff --stat` to get a summary of changes (files + lines changed)
2. Count total changed LOC — this determines Standard vs Batched mode in Phase 2

Do NOT read file contents — agents have their own 200K context windows and will read files themselves. Do NOT pre-read criteria — agents read `${CLAUDE_SKILL_DIR}/simplify-criteria.md` directly.

---

### Mode Selection

Based on Phase 1 diff stats:
- **Standard mode** (≤8 files AND ≤400 total changed LOC): Spawn 3 agents (Reuse, Quality, Efficiency), each gets all files.
- **Batched mode** (>8 files OR >400 LOC): Split files into groups of ~5 by module/directory. For each batch, spawn 3 dimension agents. Cap at 12 total agents (4 batches × 3 dimensions). Triage first: exclude trivially-changed files (renames, formatting-only, generated) from review batches.

All agents in a single mode MUST be spawned in one message.

---

## Phase 2: Parallel Review — Spawn 3 Agents

**All 3 agents MUST be spawned in one message. Do NOT wait for one before spawning the next.**

### Agent 1: Reuse & Duplication

```
Agent(model="sonnet", prompt="""
## Task: Reuse & Duplication Review

You are a code reviewer focused on finding duplication and reuse opportunities.

## Criteria
Read `${CLAUDE_SKILL_DIR}/simplify-criteria.md` — apply Ground Rules and Pass A sections.

## Changed Files
Read each of these files: [list file paths from Phase 1]
Also read each file's immediate neighbors (imports from same module) for reuse context.

## Instructions
0. Read project convention files referenced in the project's CLAUDE.md (if any) — understanding intentional project patterns prevents false-positive detection
1. Analyze each file for Pass A patterns only
2. For any finding that recommends removal (dead code, unused export, unnecessary wrapper): Grep the full project for the symbol name to verify zero cross-file references. If references exist outside changed files, reclassify as P3 (report only)
3. For each finding report: file, line number, pattern matched, proposed fix
4. Classify: P1 (fix) or P2 (fix if safe) per severity below
5. Do NOT make any edits — report findings only

## Severity
- P1: Duplication with existing utility, dead code
- P2: Similar switch branches consolidation, test setup duplication
- P3 (report only): Symbols flagged for removal that have cross-file references

## Output Format
Return a JSON array:
[{"file": "path", "line": N, "pattern": "name", "severity": "P1|P2|P3", "description": "what", "fix": "how"}]
If no findings, return: []
""", description="Review: reuse & duplication")
```

### Agent 2: Quality & Readability

```
Agent(model="sonnet", prompt="""
## Task: Quality & Readability Review

You are a code reviewer focused on readability, naming, and AI-generated anti-patterns.

## Criteria
Read `${CLAUDE_SKILL_DIR}/simplify-criteria.md` — apply Ground Rules and Pass B (+ AI Anti-Patterns + Frontend tables) sections.

## Changed Files
Read each of these files: [list file paths from Phase 1]
Also read each file's immediate neighbors (imports from same module) for reuse context.

## Instructions
0. Read project convention files referenced in the project's CLAUDE.md (if any) — understanding intentional project patterns prevents false-positive detection
1. Analyze each file for Pass B patterns only
2. Actively check for AI-generated code anti-patterns (over-abstraction, verbose error handling, unnecessary wrappers, over-documentation)
3. For any finding that recommends removal: Grep the full project for the symbol name to verify zero cross-file references. If references exist outside changed files, reclassify as P3 (report only)
4. For each finding report: file, line number, pattern matched, proposed fix
5. Classify: P1 or P2 per severity below
6. Do NOT make any edits — report findings only

## Severity
- P1: Deep nesting fixable with guard clauses, AI over-abstraction, redundant try/catch, commented-out code, dead code
- P2: Naming improvements, comment cleanup, complex boolean extraction, effect splitting
- P3 (report only): Symbols flagged for removal that have cross-file references

## Output Format
Return a JSON array:
[{"file": "path", "line": N, "pattern": "name", "severity": "P1|P2|P3", "description": "what", "fix": "how"}]
If no findings, return: []
""", description="Review: quality & readability")
```

### Agent 3: Efficiency & Patterns

```
Agent(model="sonnet", prompt="""
## Task: Efficiency & Patterns Review

You are a code reviewer focused on unnecessary complexity and inefficient patterns.

## Criteria
Read `${CLAUDE_SKILL_DIR}/simplify-criteria.md` — apply Ground Rules and Pass C sections.

## Changed Files
Read each of these files: [list file paths from Phase 1]
Also read each file's immediate neighbors (imports from same module) for reuse context.

## Instructions
0. Read project convention files referenced in the project's CLAUDE.md (if any) — understanding intentional project patterns prevents false-positive detection
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
""", description="Review: efficiency & patterns")
```

**Context checkpoint:** If the 3 agent responses are large (20+ findings total), suggest `/compact` before proceeding to Phase 3.

---

## Phase 3: Aggregate

Collect findings from all 3 agents. Merge into a single list:

1. **Deduplicate** — if two agents flagged the same line, keep the higher-severity finding
2. **Sort** — P1 first, then P2, grouped by file
3. **Separate P3** — report only, never applied
4. **Conflict check** — if two findings target the same code range with contradictory fixes, keep the one with clearer criteria match
5. **Relevance filter** — spawn a `relevance-filter-agent` to check which P1/P2 findings actually apply to this repo's conventions and complexity level:

   ```
   Agent(subagent_type="relevance-filter-agent", model="sonnet", prompt="""
   FINDINGS: [aggregated P1/P2 findings in JSON format]
   CHANGED FILES: [list of changed file paths — the agent reads files itself]
   PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
   CONVENTION FILES: [content of CONTRIBUTING.md, ADRs, architecture docs if they exist]

   Evaluate each finding against this repo's actual patterns. For each finding, check:
   1. Convention alignment — does the suggestion match how this repo already works?
   2. Over-engineering — is this YAGNI for this repo's complexity level?
   3. Intentional pattern — does the flagged "problem" exist in 3+ other files intentionally?

   Tag each finding as KEEP or FILTER with evidence.
   """)
   ```

   Only KEEP findings proceed to Phase 4 (Fix). FILTERED findings appear in the Completion Report's "Skipped" section with filter reasons. If the agent fails, pass all findings through unfiltered (fail-open).

---

## Phase 4: Fix

Delegate ALL fixes to an agent. Do NOT apply fixes directly.

```
Agent(model="sonnet", prompt="""
## Task: Apply Simplification Fixes
Apply the following categorized fixes. Batch all changes, do NOT validate between fixes.

## P1 Fixes (must apply)
[paste P1 findings from Phase 3 aggregation]

## P2 Fixes (apply if safe)
[paste P2 findings — skip any that risk behavior change, note as "skipped"]

## Files to Modify
Read each file before editing: [list unique file paths from P1+P2 findings]

## Rules
- Zero behavior change — preserve exact inputs, outputs, side effects
- If extracting a utility to a new file, update imports in consuming files
- If source changes break test imports/references: update imports only. Never change test assertions.
- Do NOT run git add/commit/push
- Report: files modified, fixes applied, fixes skipped with reason
""", description="Apply: simplify fixes")
```

---

## Phase 5: Verify

Delegate validation to an agent. Do NOT run build/lint/test commands yourself.

```
Agent(model="sonnet", prompt="""
## Task: Verify Simplification Changes
Run the project's full validation suite and report results.

## Steps
1. Run autofix (lint --fix / format) from CLAUDE.md or package.json
2. Run full validation suite (build + lint + test) from CLAUDE.md
3. If validation fails: identify which simplification change caused it, revert that file (git checkout -- <file>), note "skipped — caused CI failure", re-run validation
4. Max 1 revert-and-retry cycle. If still failing: revert ALL changes (git checkout -- .), report "Simplification aborted — changes caused cascading failures"

## Report Format
Return EXACTLY:
- autofix: PASS/FAIL
- build: PASS/FAIL
- lint: PASS/FAIL
- test: PASS/FAIL
- reverted: [list of files reverted, or "none"]
- status: PASS / PARTIAL (some files reverted) / ABORTED (all reverted)

## Requirements
- Do NOT run git add/commit/push
- Do NOT fix issues beyond reverting the problematic simplification
""", description="Verify: post-simplify validation")
```

**If the agent reports ABORTED:** Report to user "Simplification aborted — all changes reverted." and stop.
**If PARTIAL:** Include reverted files in the Completion Report's "Skipped" section.

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

## Phase 6: Learn & Improve

### Extract Learnings
If any simplification pattern appeared 3+ times across files, save it as a `project` memory (anti-pattern specific to this codebase). Before writing, check existing memories for overlap — update rather than duplicate. Skip if nothing novel was discovered.

### Suggest Improvements (project scope only)

If patterns were flagged but couldn't be safely fixed (P3 or skipped P2), suggest project-owned follow-up actions. Do NOT suggest edits to plugin-internal files (`${CLAUDE_PLUGIN_ROOT}/…`) — the plugin is global and overwritten on update; use `/improve-template` for plugin changes.

| Pattern type | Suggested action |
|---|---|
| Architectural issues (P3 items) | "Consider running `/geniro:refactor` on [module]" |
| Recurring anti-patterns | "Add a project lint rule or CI check for [pattern]" |
| Missing utilities causing duplication | "Extract [utility] to shared project module" |
| Quality gate the user enforced during review | "Add rule to `.geniro/instructions/` via `/geniro:instructions create`" |

---

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "I can analyze the code myself without spawning agents" | You are an orchestrator. Spawn all 3 agents. Parallel review catches more than a single pass. |
| "One agent is enough for these few files" | Spawn all 3. Each has a different lens — even small files have reuse, quality, AND efficiency dimensions. |
| "I'll spawn agents one at a time to save tokens" | Spawn all 3 in a SINGLE message. Sequential spawning defeats the purpose of parallel review. |
| "These findings are obviously relevant to this repo" | Reviewers apply generic best practices. Without checking against THIS repo's patterns, you'll apply fixes that contradict repo conventions or add unnecessary complexity. |
| "These changes are obviously safe" | Run validation. "Obviously safe" is the #1 predictor of broken builds. |
| "I'll fix the P3 items too since I'm here" | P3 is report-only. Fixing P3 risks behavior changes. |
| "I'll apply these fixes myself since I can see exactly what to change" | You are an orchestrator. ALL fixes go through agents. Even obvious P1 fixes. |

---

## Definition of Done

- [ ] 3 review agents spawned in parallel
- [ ] Findings aggregated and deduplicated
- [ ] Relevance filter applied (findings checked against repo conventions)
- [ ] All P1 and safe P2 fixes applied
- [ ] Full validation passes
- [ ] No behavior changes (verified by test suite)
- [ ] P3 notes documented for user
- [ ] Completion report presented

## Examples

```
/geniro:deep-simplify changed
/geniro:deep-simplify src/auth/login.ts src/auth/session.ts
/geniro:deep-simplify focus on reducing duplication in utils/
```
