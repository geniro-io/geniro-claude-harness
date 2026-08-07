# Guidelines review criteria

Code style, naming conventions, documentation, consistency, and compliance with project standards.

> **Scope:** repo-modal-pattern findings (file placement, declaration order, mixing-of-kinds, error-handling style, sibling consistency, ADR contradictions) are owned exclusively by the modal-pattern class at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/conventions-criteria.md`. Do NOT emit such findings from this style-rubric class — that produces a finding the user is told twice. This file covers style / naming / documentation / formatting / type-safety / public-API surface / dead-code only.

## Contents

- What to check
- Common false positives
- Severity tagging

---

## What to check

### 1. Naming conventions
- Variable names unclear or misleading (`x`, `d`, `v`, `data`, `temp`, `result`, `obj`)
- Inconsistent naming style (camelCase vs snake_case mixed)
- Names don't reflect purpose (`fn`, `proc`, `handler` without context)
- Magic numbers and strings without explanation
- Misleading names (name doesn't match behavior)
- Abbreviations that aren't obvious

**How to detect:** Look for multi-digit literals used directly in a comparison or argument rather than a named constant — a bare-digit grep over-flags version strings and CSS lengths, so exclude those.

### 2. Function & class naming
- Generic function names (`process`, `handle`, `do`, `execute` without context — e.g. `doSomething`, `processData`, `handleIt`, `executeTask`)
- Function names not describing what they do, or missing a clear verb (get, create, fetch, validate, check, transform)
- Inconsistent verb tense (get vs gets, create vs creating)
- Class names that don't represent their purpose (e.g. `UtilityManager`, `DataService`, `GeneralHandler`)
- Private methods without clear naming (e.g. `_process`, `_handle`)

### 3. Code formatting & style
- Inconsistent indentation (tabs vs spaces mixed in the same file)
- Line length exceeding the project's configured limit (e.g. >120 chars)
- Missing blank lines between logical sections, or random blank lines within functions
- Inconsistent brace placement
- Inconsistent spacing around operators and before/after braces

**How to detect:** Look for tab-indented and space-indented lines mixed within the same file.

### 4. Comments & documentation
- Missing comments on complex logic
- Comments that state the obvious (e.g. `// increment counter`)
- Comments that don't match code
- Function/method documentation missing, including parameter and return documentation
- No JSDoc/docstrings on public APIs
- TODO/FIXME comments without context or an issue reference

**How to detect:** Look for public function/class declarations with no preceding comment or doc-block.

### 4.5. Comment accuracy & comment-rot

A comment that lies is worse than no comment — the reader trusts it and reasons from a false premise. Three shapes, all documentation-class (LOW/MEDIUM per the Severity tagging section below):

- **Contradicts the code** — the comment describes behavior the code no longer has ("returns null on miss" above a function that now throws; "sorted ascending" above a descending sort).
- **Stale reference** — names a renamed symbol, a moved path, or a removed flag/parameter ("see `oldHelper()`" when it was renamed; "set `--legacy` to enable" when the flag was deleted; a doc-comment `@param` for an argument the signature dropped).
- **Low-value restatement** — the comment merely re-states the line it sits on, adding no intent or rationale (`i++ // increment i`). Distinct from §4's "comments that state the obvious" only in emphasis; route the finding through whichever phrasing fits.

Do not flag from the comment alone — read the code the comment describes and confirm the mismatch before emitting. A comment about a `why` (business reason, edge-case rationale) that still holds is correct even when terse.

### 5. Code duplication
- Copy-pasted code blocks (>5 lines repeated, appearing 2+ times)
- Similar logic in multiple functions, including multiple places doing the same validation
- Utility code scattered across files, or duplicated across tests
- Tests with duplicate setup code
- Constants defined in multiple places or multiple files

### 6. Imports & dependencies
- Unnecessary imports (unused modules, or importing an entire module for a couple of functions)
- Wildcard imports (`import * as everything from 'module'`)
- Circular import patterns
- Incorrect import paths, including relative imports going up many levels (`../../..`)
- Too many imports in single file

### 7. Type annotation hygiene

This section owns the *declared types* — annotations, `any` breadth, unsafe casts. It does NOT own runtime validation: missing input validation at an API boundary is `security`'s (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/security-criteria.md` §5 Input Validation & Output Encoding), and a missing null / undefined check on external input is `bugs`' (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/bugs-criteria.md` §1). Both reach the user through their own dimension at a severity a style rubric cannot assign — emitting them here caps a real defect at LOW and reports it twice.

- Missing type annotations (if using TypeScript), including omitted parameter types and return types on public functions
- `any` type used too broadly
- Type mismatches in assignments
- Type-unsafe casts and assertions

**How to detect:** No grep separates a deliberately-untyped signature from a missing annotation, so read the changed signatures directly — or take the type-checker's own output where the project runs one (`noImplicitAny`, `mypy`).

## Common false positives

1. **Single-letter vars in small scope** — OK for short lambdas/loops
- `array.map(x => x * 2)` is acceptable
- `for (let i = 0; i < n; i++)` is standard
- Check scope: if var used in 5+ lines, needs better name

2. **Generic names in tests** — Often acceptable for test setup
- `const user = createTestUser`
- `const data = { id: 1, name: 'Test' }`
- Only flag if confusing within test

3. **Pragmatic duplication** — Sometimes better than premature abstraction
- Two similar implementations might have different requirements
- Duplicating for different contexts is acceptable
- Only flag obvious shared logic

4. **Type-safe "any"** — Exceptions exist for special cases
- `JSON.parse` returns any (by design)
- Bridge code to untyped libraries uses any
- Check if there's legitimate reason

5. **Comments explaining "why"** — These are good, not obvious
- Explaining business logic or tricky decisions is valuable
- Only flag comments that state the obvious code

6. **Linter conflicts** — If codebase uses specific config
- Project might enforce different style than standard
- Check `.eslintrc`, `prettier.config`, etc.
- Don't flag if matches project config

7. **Tagging documentation gaps as MEDIUM** — Documentation polish, PR-description verbosity, comment wording, and naming suggestions are LOW (never MEDIUM). MEDIUM requires the drift to break or degrade a load-bearing tool consumer. If you are uncertain, default to LOW. LOW sits below the Phase 4.1 admission gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5), so it lands in `## Deferred — sub-threshold` rather than on the PR — for a style finding that is the intended disposition, not a reason to inflate the tier.

## Severity tagging

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.

- **CRITICAL** — never emitted by this style-rubric class (style findings cannot be CRITICAL; the modal-pattern and authored-rule classes carry their own ceilings in `severity-calibration.md` §3).
- **HIGH** — never emitted by this style-rubric class.
- **MEDIUM** — Convention drift on a tooling-load-bearing field (e.g., missing `risk_class:` in a `.geniro/actions/*.md` that the action runner requires; missing `name:` in a SKILL.md frontmatter that the loader rejects; missing `paths:` in a `review-extra/<slug>.md` that the dispatcher needs). The drift must demonstrably break or degrade a tool that consumes the field. Documentation gaps, comment wording, naming polish, formatting, and style suggestions are NOT MEDIUM — they are LOW.
- **LOW** — Style / formatting / naming polish; documentation gaps; comment wording; comment-rot (stale references, contradictory or low-value comments) on ordinary code; convention drift on optional fields; mismatched-but-non-load-bearing rule violations. Comment-rot rises to MEDIUM only when the inaccurate comment is a load-bearing doc that a tool or generated API surface consumes (e.g., a stale `@param` in a doc-comment that a docs generator publishes) — same load-bearing test as the MEDIUM tier above.
