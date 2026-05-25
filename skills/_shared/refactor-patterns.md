---
name: refactor-patterns
description: "Smell taxonomy, change-impact scoring, and atomic per-step execution protocol for /geniro:refactor. Orchestrator-inline reference."
---

# Refactor Patterns Reference

Smell detection + change-impact scoring + per-step execution protocol for `/geniro:refactor`. The orchestrator reads this file in Phase 1 (smell detection) and Phase 2 (per-step execution) and applies the patterns inline.

## Core Principle

**If you cannot prove behavior is preserved through tests, you must stop and ask for a safety net.** Never make transformations that cannot be validated.

## Data Safety Rule

Do NOT run `docker volume rm`, `podman volume rm`, `docker compose down -v`, `podman compose down -v`, `DROP TABLE`, `DROP DATABASE`, `TRUNCATE`, or any command that removes local database data or Docker/Podman volumes. Local data is untouchable. This rule has no exceptions.

---

## Phase 1: Code Smell Detection

### Step 0: Read Project Conventions

Before analyzing code, read any project convention files referenced in the orchestrator's pre-inlined context or in CLAUDE.md (coding standards, architecture docs, project structure guides). Also Read `.geniro/instructions/code-style.md` if present — cwd first; on file-not-found, retry against `<PRIMARY_ROOT>/.geniro/instructions/code-style.md` where `PRIMARY_ROOT` is computed via the Mode A snippet in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`. It contains cross-cutting code-style rules (naming patterns, structure preferences, common idioms) that apply to all refactoring. These supplement CLAUDE.md conventions. If no references are provided, check for CONTRIBUTING.md, docs/architecture.md, or ADRs in adr/ or decisions/ directories. Understanding intentional project patterns prevents false-positive smell detection.

### Step 1: Scan for Smells

Scan the target codebase for:

#### Duplication Patterns
- Use Grep to find identical or near-identical code blocks across files
- Identify repeated logic that could be extracted to shared utilities
- Flag magic numbers, repeated conditions, or boilerplate patterns
- Report: file paths, line ranges, similarity scores

#### Long Methods & Deep Nesting
- Search for methods/functions exceeding 30 lines of significant logic
- Identify nested blocks deeper than 4 levels (loops within conditionals within loops)
- Report: function signatures, complexity metrics, extraction opportunities

#### God Classes & Large Modules
- Locate classes/modules handling 5+ distinct responsibilities
- Check for methods with unrelated concerns (auth + business logic + formatting)
- Report: class structure, responsibility breakdown

#### Dead Code
- Use Grep to find unused variables, unreachable branches, orphaned functions
- Cross-reference against test files and call graphs
- Confirm unused status by checking imports and references
- Report: confirmed dead code with confidence levels

#### Tight Coupling
- Identify circular dependencies, deep inheritance chains
- Find hard-coded dependencies that should be injected
- Report: coupling patterns, refactoring surface

#### Type & Import Issues
- Unused imports or missing type definitions
- Inconsistent error handling or null-safety patterns
- Report: code quality impacts

#### Deepening Opportunities
**Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/architecture-vocabulary.md` first** to ground the vocabulary (depth, seam, adapter, leverage, locality, deep vs shallow modules).

This lens is orthogonal to the 6 smell categories above — it asks "is this module **shallow** when it could be **deep**?" rather than "is there a smell?" A shallow module exposes nearly all its internal complexity through a wide interface; a deep module hides a lot of behavior behind a small interface.

Look for:
- **Wide-interface modules with low internal logic** — e.g., a util file with 12 exported helpers each used once. The exports are the interface; the implementation is trivial. Consider absorbing the callers' logic INTO the module so the module hides more behavior behind fewer exports.
- **Pass-through wrappers / leaky abstractions** — modules that re-export third-party types or expose adapter internals. These widen the seam without adding depth. Either deepen (absorb more behavior) or remove the wrapper.
- **Repeated cross-call orchestration at call sites** — same 3-4 module calls in sequence, repeated across files. The orchestration belongs INSIDE one of those modules (deepening it) or in a new orchestrator module (narrowing the seam at every caller).
- **High-leverage code with shallow implementation** — types or functions imported by 30+ files but with trivial internal logic. The leverage is wasted; deepening would let callers offload more responsibility.

For each deepening opportunity, report:
- **Module**: file:line of the current shallow module
- **Current interface size**: count of exported symbols
- **Proposed deepening**: what behavior to absorb (1-2 sentences)
- **Affected call sites**: count of consumers (use Grep — this drives risk classification per Step 2)
- **Vocabulary tag**: which terms apply (depth / seam / adapter / leverage / locality)

Deepening findings are subject to the same Step 2 Change Impact Scoring as smells. They are typically MEDIUM or HIGH risk because they touch the seam between modules and their consumers — flag accordingly.

### Step 2: Change Impact Scoring

For each detected smell, score its change impact before including it in the plan:

1. **Count consumers**: Use the Grep tool (not bash grep) to count files that import or reference the symbol being changed:
 ```
 Grep(pattern="SymbolName", output_mode="count")
 ```
 Adjust the glob filter based on the project's language (e.g., `glob: "*.ts"` for TypeScript, `glob: "*.py"` for Python).
2. **Classify risk** based on consumer count:

| Consumers | Risk | Action |
|-----------|------|--------|
| 1-3 files | **LOW** | Proceed immediately |
| 4-9 files | **MEDIUM** | Proceed with extra test verification |
| 10+ files | **HIGH** | Flag for user confirmation — do NOT proceed without approval |

3. **Escalation override**: Any transformation that changes a public API signature, module export, or shared type is **HIGH** regardless of consumer count.

---

## Phase 2: Refactoring Plan

The orchestrator builds a structured, prioritized plan in /refactor SKILL.md (plan-build), persisted to state.md `## Plan steps`. Plan-line schema:

```
- step: <N>
 smell: <detected smell description>
 impact: <why this matters — duplication, clarity, performance>
 risk: <LOW|MEDIUM|HIGH>
 consumers: <count>
 transformation: <mechanical description>
 before: <code snippet or structure>
 after: <code snippet or structure>
 test_strategy: <which tests validate this>
 files_affected: <bounded list>
 rollback: <how to undo if tests fail>
 status: <pending|in-progress|complete|blocked|reverted>
 attempts: <0-3>
 last_post_check: <PASS|FAIL|REVERTED|unset>
```

HIGH-risk steps require user confirmation via /refactor AUQ before Phase 2 executes them.

---

## Phase 3: Atomic Application & Verification (orchestrator-inline)

Apply **one transformation at a time** and verify tests pass between steps. The orchestrator runs the loop inline.

### Step Execution Protocol

For each transformation in `## Plan steps`:

1. **Re-read the target** — read the current file(s) before making changes (in case earlier steps altered them).

2. **Pre-condition check** — required only when one of the following holds: (a) this is the FIRST transformation in the plan (no `last_post_check` recorded yet), OR (b) `last_post_check` is unset OR `last_post_check == REVERTED` (the previous step entered the Blocked Step Protocol and was reverted — the revert touched the working tree but no post-condition was successfully recorded, so the baseline must be re-verified before the next transformation), OR (c) anything other than this skill's transformations has touched the working tree since the last post-check (e.g., user interrupt that the session routed back). For step 2..N when `last_post_check == PASS`, **skip the pre-condition test** — the post-condition of the previous step already verified the same baseline (no edits intervene between consecutive transformations in this strictly-sequential atomic protocol). Skipping eliminates ~50% of test runs in the typical N-step plan (2N → N+1).

 **Test command selection:** if CLAUDE.md's Essential Commands section defines `<test_cmd_affected>` (an incremental command that targets only tests affected by the current diff — e.g., `npm test -- --findRelatedTests <files>`, `vitest --changed`, `pytest --testmon`, `nx affected:test`), use it for the per-step pre-check and per-step post-check below — these are tight per-step gates, not regression gates. /refactor Phase 1 Step 6 (final) baseline and Phase 2.4 final regression run keep `<test_cmd>` (full suite). If `<test_cmd_affected>` is not defined in CLAUDE.md, fall back to `<test_cmd>` (current behavior).

 When the pre-condition IS required, run tests via backpressure to preserve context:
 ```bash
 source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Pre-check" "[test command]"
 ```
 If backpressure is unavailable, run directly with output capped: `[test command] 2>&1 | tail -80`.
 If pre-tests fail, stop and report — do not make changes on a broken baseline.

3. **Apply change** — use the Edit tool for surgical, line-aware modifications. Keep changes within scope boundaries. Preserve code style and formatting.

4. **Post-condition check** — run tests via backpressure:
 ```bash
 source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Post-check" "[test command]"
 ```
 If backpressure is unavailable: `[test command] 2>&1 | tail -80`.
 Record the result as `last_post_check: PASS|FAIL` for the next iteration's Step 2 skip predicate (persisted to state.md `## Plan steps` row).

5. **Result handling**:
 - **Tests pass**: log transformation as complete, set `last_post_check = PASS`, move to next step (which will use the skip predicate above to skip its pre-check)
 - **Tests fail**: enter the Blocked Step Protocol (below) — when the protocol's revert action restores the baseline, set `last_post_check = REVERTED` so the next step's pre-check predicate (b) triggers and re-runs the baseline

### Blocked Step Protocol

When a transformation fails tests:

For all attempt re-runs below, use the same test command selection as Step 2 / Step 4 above (`<test_cmd_affected>` if CLAUDE.md defines it, else the supplied test command). Each attempt runs the test ONCE — there is no separate pre-check/post-check pair, since the protocol enters from an already-failed post-condition.

1. **Attempt 1**: Analyze failure, fix the issue, re-run tests.
2. **Attempt 2**: Try a different approach to the same transformation, re-run tests.
3. **Attempt 3**: Try one more variation, re-run tests.
4. **After 3 failures**: **REVERT** the step entirely using Edit (undo all changes from this step), mark the step as **BLOCKED** in state.md, and **CONTINUE to the next step**.

Do NOT stop the entire refactoring session because one step is blocked. Blocked steps are reported at the end for user attention.

Per-step blocked rationale schema in state.md:

```yaml
- step: <N>
 blocked: true
 attempts: 3
 last_failure: <test name and assertion>
 root_cause: <analysis>
 action: Reverted all changes — continuing to next step
 recommendation: <what the user could do manually>
```

---

## Phase 4: Structured Reporting

After all transformations, /refactor emits the completion summary using this schema:

```
Refactoring Summary
===================

Transformations Applied: [count]
 [Transformation 1 name] — LOW risk, consumers: 2
 [Transformation 2 name] — MEDIUM risk, consumers: 5
 ...

Transformations Blocked: [count]
 [Transformation N name] — BLOCKED after 3 attempts: [brief reason]
 ...

Code Health Improvements:
 - Duplication reduced: [X lines -> Y lines]
 - Long methods simplified: [N methods -> M methods]
 - Dead code removed: [N files, M lines]
 - Coupling improved: [specific examples]

Test Results:
 - All tests passing: YES/NO
 - Regressions introduced: 0

Files Modified: [count]
 [file path]: [brief changes]
 ...

Next Steps:
 - [blocked transformations that need manual attention]
 - [optional follow-up smells to address]
```

---

## Guardrails (Always Enforce)

**Never do this without explicit request:**
- Change public interfaces (method signatures, API contracts)
- Alter business logic (unless you add tests proving the change)
- Touch authentication, cryptography, or payment code (requires owner review)
- Remove code flagged as "unused" without confirming no hidden references
- Rewrite SQL/data logic without validating output equivalence and performance
- Modify test files themselves (document what you would change, ask for approval)

**Always do this:**
- Run tests before and after every transformation (subject to skip predicate Step 2)
- Keep changes scoped to 1-2 files per transformation
- Report plainly if tests failed or were not run (no "should pass" language)
- Preserve existing code style and formatting
- Document mechanical transformations for easy review
- Score change impact before proposing transformations

## When to Stop the Session & Report Back

Stop the entire refactoring session when:

- Tests do not exist for the code you're changing — no safety net
- Public interface changes are required — needs user approval before proceeding
- Business logic changes cannot be validated by existing tests
- Code involves security-critical systems — requires owner review
- Requested change contradicts guardrails
- Codebase has no test infrastructure

**Note:** If a single transformation fails after 3 attempts, use the **Blocked Step Protocol** (Phase 3) — revert that step and continue to the next. Do NOT stop the session for per-step failures.

## Git Operations

No Git operations from within this protocol. The /refactor skill's verify phase and user-driven commits handle all version control. Do NOT run `git add`, `git commit`, `git push`, `git checkout` during atomic application.
