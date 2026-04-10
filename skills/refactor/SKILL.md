---
name: geniro:refactor
description: "Use when restructuring code for better organization, reducing tech debt, or improving patterns while guaranteeing zero behavior change. Ideal for modularization, test refactoring, or pattern consolidation after implementation."
context: main
model: sonnet
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[what to refactor and why]"
disable-model-invocation: false
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

## Process

### Phase 1: Scope & Context

1. Parse `$ARGUMENTS` to understand what is being refactored and why
2. Use Grep and Glob to find all related files
3. Read all files in scope to understand current organization, dependencies, imports, and test coverage
4. Read any project convention files referenced in CLAUDE.md (coding standards, architecture docs) — understanding project patterns prevents flagging intentional designs as smells
5. Load custom instructions from `.geniro/instructions/global.md` and `.geniro/instructions/refactor.md`. Read any found. Apply rules as constraints, additional steps at specified phases, and hard constraints.

### Phase 2: Analyze & Plan

Spawn a refactor-agent to analyze the scoped files and produce a refactoring plan:

```
Agent(subagent_type="refactor-agent", prompt="""
You are analyzing code for refactoring. Your task:

WHAT TO REFACTOR: $ARGUMENTS

FILES IN SCOPE:
[list the files you read in Phase 1]

PROJECT CONVENTIONS:
[paste any relevant conventions from CLAUDE.md or project docs]

PHASE: ANALYSIS ONLY.
- Execute ONLY your Phase 1 (Code Smell Detection) and Phase 2 (Refactoring Plan).
- Skip Phase 3 (Atomic Application) and Phase 4 (Reporting) entirely.
- Do NOT use Write or Edit tools during this invocation. You are producing a plan, not making changes.
- Return the plan as your final output.

1. Run all 6 smell detection categories (duplication, long methods, god classes, dead code, tight coupling, type/import issues)
2. For each smell found, score Change Impact:
   - Count consumers: use Grep to count files that import/reference the symbol
   - 1-3 consumers = LOW risk
   - 4-9 consumers = MEDIUM risk
   - 10+ consumers = HIGH risk (regardless of transformation type)
3. Produce an ordered refactoring plan with risk levels per step
4. HIGH RISK steps must be flagged for user confirmation

Return the plan in this format:
- Smells detected (with file:line references)
- Ordered steps with risk classification and consumer counts
- Files that will change per step
- What will NOT change (public APIs, DB schema, test behavior)
""")
```

### Phase 3: Approval

**Relevance filter:** Before presenting the plan, spawn a `relevance-filter-agent` to check detected smells against repo conventions:

```
Agent(subagent_type="relevance-filter-agent", prompt="""
FINDINGS: [smells detected by refactor-agent, with file:line references and risk levels]
CHANGED FILES: [files in refactoring scope from Phase 1]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
CONVENTION FILES: [content of CONTRIBUTING.md, ADRs, architecture docs if they exist]

Evaluate each detected smell against this repo's actual patterns. For each smell, check:
1. Convention alignment — is this "smell" actually the repo's chosen pattern?
2. Over-engineering — would fixing this smell introduce more complexity than it removes?
3. Intentional pattern — does the flagged pattern exist deliberately in 3+ other files?

Tag each smell as KEEP or FILTER with evidence.
""")
```

Remove FILTERED smells from the plan before presenting to user. Note filtered smells in the results. If the agent fails, proceed with all smells unfiltered (fail-open).

Review the agent's plan:
- If any steps are **HIGH risk**: present them to user via `AskUserQuestion` and wait for confirmation before proceeding
- If all steps are LOW/MEDIUM: present the plan summary and proceed

### Phase 4: Execute

Spawn the refactor-agent to execute the approved plan:

```
Agent(subagent_type="refactor-agent", prompt="""
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

### Phase 5: Review Results

After the agent completes:
1. Check if any steps were marked BLOCKED — report these to the user with failure reasons
2. Verify the agent's final validation passed
3. If validation failed, revert all changes (`git checkout -- .`) and report failure
4. Present the completion report

## Git Constraint

Do NOT run `git add`, `git commit`, or `git push`. The orchestrating workflow handles version control. Exception: `git checkout -- .` is permitted in Phase 5 for reverting failed changes — this is an orchestration-level revert, not a version control operation.

## Anti-rationalization constraints

| Your reasoning | Why it's wrong |
|---|---|
| "This smell is too small to fix" | If the plan says fix it, fix it. Small smells compound. |
| "I'll batch multiple transformations" | One transformation per step. Always. |
| "Tests are passing so I'll skip the blocked step protocol" | The protocol exists for the NEXT failure. Follow it. |
| "This refactoring needs a behavior change" | Then it's not a refactoring. Use `/geniro:implement` instead. |
| "I'll skip reading project conventions" | You'll flag intentional patterns as smells. Read first. |
| "All detected smells are real issues" | Generic smell categories flag intentional repo patterns. Without filtering against THIS repo's conventions, you'll refactor code that was designed that way on purpose. |
| "This is just a refactor" | Refactors break things. Tests and review apply equally. |

## Learn & Improve

After refactoring is complete, extract knowledge and suggest improvements.

### Extract Learnings

Scan the refactoring session for patterns worth remembering:
- **Blocked transformations** — steps that couldn't be done safely → save as `project` memory (flags areas needing deeper rework)
- **Convention discoveries** — patterns found during codebase reading that weren't documented → save as `project` memory (helps future sessions)
- **User corrections** — "don't refactor that, it's intentional" → save as `feedback` memory (calibrates future refactoring scope)
- **Surprising coupling** — modules that turned out to be tightly coupled in non-obvious ways → save as `project` memory (architectural insight)

Before writing, check if an existing memory covers this topic — UPDATE rather than duplicate. Skip if nothing novel was discovered.

### Suggest Improvements

Check if the refactoring revealed improvement opportunities. Classify each by **routing target**:

| What was discovered | Route to | Why |
|---|---|---|
| Undocumented convention used consistently across codebase | **CLAUDE.md** | All agents inherit CLAUDE.md conventions |
| Agent produces code that consistently needs same refactoring | **Agent prompt** | `${CLAUDE_PLUGIN_ROOT}/agents/*.md` |
| Surprising coupling between modules | **Knowledge** (learnings.jsonl) | Architectural insight for future changes |
| Pattern that should be enforced automatically | **Rules/hooks** | Automated enforcement beats manual memory |

Present via `AskUserQuestion` with header "Improvements": "Apply all" / "Review one-by-one" / "Skip". Group by target. If no improvements found, skip silently.

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

## Example invocations

```
/geniro:refactor Extract shared validation logic from auth and user modules
/geniro:refactor Consolidate test helpers in utils/ to single module
/geniro:refactor Split 1000-line service into focused domain modules
/geniro:refactor Reduce coupling between database and business logic layers
```
