# Simplify Analysis Criteria

Reference file for the `/geniro:review --simplify` flag. When `--simplify` is present in `$ARGUMENTS`, /geniro:review's Phase 2 prepends these criteria onto 5 dimension reviewer prompts: **architecture** (Reuse), **conventions** (aggressive modal-pattern threshold), **guidelines** (Quality), **bugs** (Quality bug-class extensions), **optimizations** (Efficiency).

/geniro:review is a Reporter — every entry in the tables below is a finding to flag and a recommendation to attach, never an edit to apply. The reviewer-agent emits findings (severity + decision-type + evidence + suggested-fix); the user (or `/geniro:implement`) applies the suggested fix later. Read the "What to flag" column as "report this pattern, recommend this change."

Severity reconciliation: P1 → HIGH, P2 → MEDIUM, P3 → informational (filtered out of Phase 4 unless `--tdd` or `risk-tier: high`).

NOT a new dimension — folds into existing dims. Users wanting auto-applied fixes pipe `/geniro:review --simplify` output to `/geniro:implement`.

(`/geniro:refactor` does NOT reference this file — its smell-detection routes through `existing-abstraction-audit.md` + orchestrator-inline deepening lens + `_shared/refactor-patterns.md`.)

## Contents

- Ground Rules
- Pass A: Reuse & Duplication
- Pass B: Quality & Readability
- Pass C: Efficiency & Patterns
- Severity Classification
- Recommendation boundaries
- Output shape

---

## Ground Rules

1. **Zero behavior change.** Only recommend a change that preserves the exact same inputs, outputs, and side effects. If the recommendation could alter behavior, don't flag it.
2. **Only changed files.** Scope findings to the diff; the one exception is a recommendation to extract a shared utility that changed files will import.
3. **No feature work.** Don't recommend new functionality, error handling for new cases, or validation. Flag only simplifications of what exists.
4. **Preserve test coverage.** Never recommend deleting or weakening test assertions. A recommendation to simplify test setup/helpers is fine when it improves clarity.
5. **Small, incremental changes.** Each finding should describe an independently applicable change. Don't bundle interdependent recommendations into one finding.
6. **Verify before flagging dead code.** Before classifying code as dead or unused, Grep the full project for the symbol name (as both an identifier and a string literal). Check barrel/index files for re-exports. If any reference exists outside the changed files, do NOT recommend removal — report as P3 instead.

---

## Pass A: Reuse & Duplication

Before flagging duplication or recommending extraction, run the canonical **Existing Abstraction Audit** at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` — Grep designated helper directories (`utils/`, `lib/`, `shared/`, `helpers/`, `services/`) for analogues that could be reused or extended instead of creating new code. Apply its Procedure, force-fit guard, and Rule of Three threshold to every Pass A finding.

| Pattern | What to flag / recommend |
|---------|-----------|
| **Duplicated logic across changed files** | Recommend extracting to a shared utility file in the nearest common module — only if the audit returned NO-ANALOGUE and Rule of Three (≥3 distinct call sites) applies |
| **Duplicated logic within a single file** | Recommend extracting to a private helper function in the same file |
| **Re-implementation of existing utilities** | Recommend replacing with the existing utility (the audit identifies analogues in `utils/`, `lib/`, `shared/`, `helpers/`, `services/` and barrel files) |
| **Copy-pasted test setup** | Recommend extracting to a test helper or `beforeEach` block |
| **Similar switch/if-else branches** | Recommend consolidating using a map/lookup pattern |

**Do NOT recommend removing** an export if it is re-exported from any `index.*` or barrel file — it is part of the module's public API regardless of whether you see internal consumers.

---

## Pass B: Quality & Readability

| Pattern | What to flag / recommend |
|---------|-----------|
| **Deep nesting (3+ levels)** | Recommend guard clauses / early returns to flatten |
| **Nested ternaries** | Recommend replacing with `if`/`else` or `switch` |
| **Complex boolean expressions** (`if (a && b \|\| !c && d)`) | Recommend extracting to a named boolean variable or predicate function |
| **Functions > 50 lines of logic** | Recommend extracting coherent blocks into named helper functions |
| **Services/classes > 500 lines** | Note as P3 — candidate for splitting (too risky for simplify) |
| **Functions with 4+ parameters** | Recommend grouping into an options object (only if this is a new function in the diff) |
| **Vague names** (`data`, `result`, `temp`, `item`, `val`) | Recommend renaming to describe the domain concept |
| **Comments restating what code does** | Recommend removing (keep comments that explain *why*) |
| **Commented-out code blocks** | Recommend removing entirely (git has history) |
| **Meaningful comments** (explain *why*, legal/copyright headers, TODO/FIXME with ticket refs, consequence warnings, complex algorithm explanations) | **Preserve** — never recommend removing during simplification. When a recommended code change touches adjacent meaningful comments, flag that the comments stay and may need updating to match the change |
| **Dead code** (unreachable branches, unused variables/imports) | Recommend removing |
| **`any` type usage** (TypeScript) | Recommend a specific type, generic, or `unknown` + type guard |
| **Type assertions** bypassing type safety | Recommend type guards or proper typing |
| **Bare `return promise`** without `await` | Recommend adding `await` (preserves stack traces) |
| **Missing braces** on `if`/`else`/`for`/`while` | Recommend adding braces |
| **Inline `require` calls** (JS/TS) | Recommend moving to top-level import |

### AI-Generated Code Anti-Patterns

These are common when code was written by AI agents — actively look for them:

| Pattern | What to flag / recommend |
|---------|-----------|
| **Over-abstraction** — unnecessary wrapper classes, premature generics, factory patterns for single use | Recommend inlining the abstraction and removing the wrapper |
| **Verbose error handling** — catch blocks that just log and rethrow without adding context | Recommend removing the try/catch or adding meaningful context |
| **Unnecessary wrapper functions** that just forward to another function with same signature | Grep repo-wide for all callers. Recommend replacing call sites with the direct function only if ALL callers are within the changed file set. Otherwise report as P2 (fix if safe) with a note listing external callers |
| **Over-documented obvious code** — JSDoc/docstring on every method restating the function name | Recommend removing — keep only docs on public API surfaces and non-obvious behavior |

### Frontend-Specific (if applicable)

| Pattern | What to flag / recommend |
|---------|-----------|
| **Components with multiple responsibilities** | Recommend extracting sub-components (only if the boundary is clear and >30 lines) |
| **Complex logic in inline event handlers** (>3 lines) | Recommend extracting to a named handler function |
| **Effects doing too much** — single effect with multiple unrelated concerns | Recommend splitting into separate effects with focused dependency arrays |
| **Prop drilling through 3+ levels** | Note as P3 — may warrant context/composition refactor |
| **Stale closures in hooks** — callbacks capturing outdated state | Recommend a functional updater or adding to the dependency array |

---

## Pass C: Efficiency & Patterns

| Pattern | What to flag / recommend |
|---------|-----------|
| **Unnecessary intermediate variables** | Recommend inlining if used only once and the expression is clear |
| **Redundant null checks** where types guarantee non-null | Recommend removing |
| **Business logic in controllers/handlers** | Note as P3 — don't recommend moving automatically (too risky for simplify) |
| **N+1 query patterns** | Note as P3 — don't recommend a fix automatically (behavior change risk) |
| **Circular dependency signals** (barrel re-exports, `forwardRef` usage) | Note as P3 — flag for user attention |
| **Redundant `try/catch` that just rethrows** | Recommend removing the try/catch |
| **Manual loops** replaceable with `.map/.filter/.reduce` | Recommend replacing (only when the replacement is equally or more readable) |
| **Over-defensive coding** — checks for impossible states based on types | Recommend removing the dead branch |
| **Redundant spread** — `{...obj }` when `obj` could be used directly | Recommend removing the spread if no mutation risk |

---

## Severity Classification

Map these reviewer-prioritization tiers onto the reviewer-agent severity scale: P1 → HIGH, P2 → MEDIUM, P3 → informational.

- **P1 (recommend fixing):** Dead code, commented-out code, duplication with existing utility, style violations of project conventions, deep nesting fixable with guard clauses, AI over-abstraction (unnecessary wrappers/factories), redundant try/catch
- **P2 (recommend fixing if safe):** Naming improvements, unnecessary intermediate variables, redundant null checks, comment cleanup, complex boolean extraction, verbose error handling, effect splitting, inline handler extraction
- **P3 (note only):** Business logic in controllers, N+1 patterns, circular dependencies, large classes >500 lines, prop drilling, architectural suggestions — report as an observation, no concrete recommendation

---

## Recommendation boundaries

Don't flag a finding that recommends any of these — each changes behavior, exceeds simplify scope, or rests on a guess rather than evidence:

- Changing function signatures or exports (even if it would be cleaner) — alters the contract callers depend on.
- Reordering parameters in function calls — silent behavior change at every call site.
- Renaming public APIs or re-export patterns — breaks downstream consumers outside the diff.
- Adding error handling not previously present — that is feature work, not simplification.
- Removing code because "it seems unused" — respect existing design; recommend removal only for provably dead code (Ground Rule 6).
- Optimizing for performance without measurement — premature optimization trades clarity for an unverified gain.
- Extracting pure utility functions purely for testability — recommend extraction only when it improves readability.
- Style issues outside the scope of simplification — out of band for this flag.

---

## Output shape

These criteria fold into a dimension reviewer, so emit findings in the reviewer-agent Output Format (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format) — one finding per simplification, never an applied-changes report. Each finding carries:

- **Severity** — P1 → HIGH, P2 → MEDIUM, P3 → informational.
- **File:** the `file:line` where the pattern was found.
- **Decision Type** — `[FIX-NOW]` for a mechanical simplification with one obvious change; `[PRODUCT-DECISION]` for a structural recommendation with trade-offs (then populate `Options:`).
- **Evidence** — the cited code slice showing the pattern (mandatory for HIGH/MEDIUM).
- **Suggested fix** — the recommended change in plain text; the user or `/geniro:implement` applies it.

P3 observations surface as informational findings with no concrete suggested-fix — flag for user attention only.
