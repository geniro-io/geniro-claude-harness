# Simplify Analysis Criteria

Reference file shared between `/geniro:deep-simplify` skill and `/geniro:implement` Phase 5. Contains the three analysis passes, severity classification, anti-patterns, and ground rules for code simplification.

---

## Ground Rules

1. **Zero behavior change.** Every fix must preserve the exact same inputs, outputs, and side effects. If unsure, don't touch it.
2. **Only changed files.** Never modify files outside the diff unless extracting a shared utility that changed files will import.
3. **No feature work.** Don't add functionality, improve error handling for new cases, or add validation. Only simplify what exists.
4. **Preserve test coverage.** Never delete or weaken test assertions. You may simplify test setup/helpers if it improves clarity.
5. **Small, incremental changes.** Each fix should be independently revertable. Don't chain fixes that depend on each other.
6. **Verify before removing.** Before classifying code as dead or unused, Grep the full project for the symbol name (as both an identifier and a string literal). Check barrel/index files for re-exports. If any reference exists outside the changed files, do NOT remove — report as P3 instead.

---

## Pass A: Reuse & Duplication

Before flagging duplication or recommending extraction, run the canonical **Existing Abstraction Audit** at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` — Grep designated helper directories (`utils/`, `lib/`, `shared/`, `helpers/`, `services/`) for analogues that could be reused or extended instead of creating new code. Apply its Procedure, force-fit guard, and Rule of Three threshold to every Pass A finding.

| Pattern | What to do |
|---------|-----------|
| **Duplicated logic across changed files** | Extract to a shared utility file in the nearest common module — only if the audit returned NO-ANALOGUE and Rule of Three (≥3 distinct call sites) applies |
| **Duplicated logic within a single file** | Extract to a private helper function in the same file |
| **Re-implementation of existing utilities** | Replace with the existing utility (the audit identifies analogues in `utils/`, `lib/`, `shared/`, `helpers/`, `services/` and barrel files) |
| **Copy-pasted test setup** | Extract to a test helper or `beforeEach` block |
| **Similar switch/if-else branches** | Consolidate using a map/lookup pattern |

**Do NOT remove** an export if it is re-exported from any `index.*` or barrel file — it is part of the module's public API regardless of whether you see internal consumers.

---

## Pass B: Quality & Readability

| Pattern | What to do |
|---------|-----------|
| **Deep nesting (3+ levels)** | Apply guard clauses / early returns to flatten |
| **Nested ternaries** | Replace with `if`/`else` or `switch` |
| **Complex boolean expressions** (`if (a && b \|\| !c && d)`) | Extract to a named boolean variable or predicate function |
| **Functions > 50 lines of logic** | Extract coherent blocks into named helper functions |
| **Services/classes > 500 lines** | Note as P3 — candidate for splitting (too risky for simplify) |
| **Functions with 4+ parameters** | Group into an options object (only if this is a new function in the diff) |
| **Vague names** (`data`, `result`, `temp`, `item`, `val`) | Rename to describe the domain concept |
| **Comments restating what code does** | Remove (keep comments that explain *why*) |
| **Commented-out code blocks** | Remove entirely (git has history) |
| **Meaningful comments** (explain *why*, legal/copyright headers, TODO/FIXME with ticket refs, consequence warnings, complex algorithm explanations) | **Preserve** — never remove during simplification. When editing code that has adjacent meaningful comments, keep the comments and update them if the code change alters their meaning |
| **Dead code** (unreachable branches, unused variables/imports) | Remove |
| **`any` type usage** (TypeScript) | Replace with specific type, generic, or `unknown` + type guard |
| **Type assertions** bypassing type safety | Replace with type guards or proper typing |
| **Bare `return promise`** without `await` | Add `await` (preserves stack traces) |
| **Missing braces** on `if`/`else`/`for`/`while` | Add braces |
| **Inline `require()` calls** (JS/TS) | Move to top-level import |

### AI-Generated Code Anti-Patterns

These are common when code was written by AI agents — actively look for them:

| Pattern | What to do |
|---------|-----------|
| **Over-abstraction** — unnecessary wrapper classes, premature generics, factory patterns for single use | Inline the abstraction, remove the wrapper |
| **Verbose error handling** — catch blocks that just log and rethrow without adding context | Remove the try/catch or add meaningful context |
| **Unnecessary wrapper functions** that just forward to another function with same signature | Grep repo-wide for all callers. Replace call sites with the direct function only if ALL callers are within the changed file set. Otherwise report as P2 (fix if safe) with a note listing external callers |
| **Over-documented obvious code** — JSDoc/docstring on every method restating the function name | Remove — keep only docs on public API surfaces and non-obvious behavior |

### Frontend-Specific (if applicable)

| Pattern | What to do |
|---------|-----------|
| **Components with multiple responsibilities** | Extract sub-components (only if the boundary is clear and >30 lines) |
| **Complex logic in inline event handlers** (>3 lines) | Extract to a named handler function |
| **Effects doing too much** — single effect with multiple unrelated concerns | Split into separate effects with focused dependency arrays |
| **Prop drilling through 3+ levels** | Note as P3 — may warrant context/composition refactor |
| **Stale closures in hooks** — callbacks capturing outdated state | Use functional updater or add to dependency array |

---

## Pass C: Efficiency & Patterns

| Pattern | What to do |
|---------|-----------|
| **Unnecessary intermediate variables** | Inline if used only once and the expression is clear |
| **Redundant null checks** where types guarantee non-null | Remove |
| **Business logic in controllers/handlers** | Note as P3 — don't move automatically (too risky for simplify) |
| **N+1 query patterns** | Note as P3 — don't fix automatically (behavior change risk) |
| **Circular dependency signals** (barrel re-exports, `forwardRef` usage) | Note as P3 — flag for user attention |
| **Redundant `try/catch` that just rethrows** | Remove the try/catch |
| **Manual loops** replaceable with `.map()/.filter()/.reduce()` | Replace (only when the replacement is equally or more readable) |
| **Over-defensive coding** — checks for impossible states based on types | Remove the dead branch |
| **Redundant spread** — `{ ...obj }` when `obj` could be used directly | Remove the spread if no mutation risk |

---

## Severity Classification

- **P1 (fix):** Dead code, commented-out code, duplication with existing utility, style violations of project conventions, deep nesting fixable with guard clauses, AI over-abstraction (unnecessary wrappers/factories), redundant try/catch
- **P2 (fix if safe):** Naming improvements, unnecessary intermediate variables, redundant null checks, comment cleanup, complex boolean extraction, verbose error handling, effect splitting, inline handler extraction
- **P3 (note only):** Business logic in controllers, N+1 patterns, circular dependencies, large classes >500 lines, prop drilling, architectural suggestions — report but don't fix

---

## Anti-Rationalization Constraints

**NEVER do these:**
- Change function signatures or exports (even if it would be cleaner)
- Reorder parameters in function calls
- Rename public APIs or re-export patterns
- Add error handling not previously present
- Remove code because "it seems unused" (respect existing design — only remove provably dead code)
- Optimize for performance without measurement (avoid premature optimization)
- Extract pure utility functions purely for testability (only if it improves readability)
- "Fix" style issues not in the scope of simplification

---

## Completion Report Format

```
## Simplification Results

### Applied (N fixes)
- [file:line] — [what changed] (P1/P2)
- ...

### Skipped (N items)
- [file:line] — [what was found] — skipped because [reason: CI failure / P3 note / behavior change risk]

### Notes for User (P3)
- [file:line] — [observation] — suggested follow-up: [what to do]

### Verification
- Validation: PASS/FAIL
- Files modified: N
- Lines added/removed: +N/-M
```
