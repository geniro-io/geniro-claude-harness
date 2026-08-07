# Guidelines review criteria

Code style, naming conventions, documentation, consistency, and compliance with project standards.

> **Scope:** repo-modal-pattern findings (file placement, declaration order, mixing-of-kinds, error-handling style, sibling consistency, ADR contradictions) are owned exclusively by the modal-pattern class at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/conventions-criteria.md`. Do NOT emit such findings from this style-rubric class — that produces a finding the user is told twice. This file covers style / naming / documentation / formatting / type-safety / public-API surface / dead-code only.

## Contents

- What to check
- Common false positives
- Severity tagging

---

## What to check

### 1. Naming Conventions
- Variable names unclear or misleading (`data`, `x`, `temp`, `result`)
- Inconsistent naming style (camelCase vs snake_case mixed)
- Names don't reflect purpose (`fn`, `proc`, `handler` without context)
- Magic numbers and strings without explanation
- Misleading names (name doesn't match behavior)

**How to detect:**
```bash
# Magic numbers — a multi-digit literal inline in a comparison or argument, minus named-constant
# declarations. A bare digit grep instead reports every version string and CSS length in the file.
grep -nE "(==|<|>|<=|>=|\(|,)[[:space:]]*[0-9]{2,}" file.js | grep -vE "^[0-9]+:[[:space:]]*(const|let|var|static|final)"
```

**Red flags:**
- Variables: `x`, `d`, `v`, `data`, `temp`, `result`, `obj`
- Inconsistent style in same file
- Constants without names (magic numbers/strings)
- Names that don't match what variable stores
- Abbreviations that aren't obvious

### 2. Function & Class Naming
- Generic function names (`process`, `handle`, `do`, `execute` without context)
- Function names not describing what they do
- Inconsistent verb tense (get vs gets, create vs creating)
- Class names that don't represent their purpose
- Private methods without clear naming

**Red flags:**
- Functions: `doSomething`, `processData`, `handleIt`, `executeTask`
- Classes: `UtilityManager`, `DataService`, `GeneralHandler`
- No clear verb (get, create, fetch, validate, check, transform)
- Private methods unclear (\_process, \_handle)

### 3. Code Formatting & Style
- Inconsistent indentation (tabs vs spaces mixed)
- Line length exceeding the project's configured limit (e.g. >120 chars)
- Missing blank lines between logical sections
- Inconsistent brace placement
- Inconsistent spacing around operators

**How to detect:**
```bash
# Check indentation consistency (tabs vs leading spaces — portable, no GNU `cat -A`)
awk '/^\t/{tabs++} /^ /{spaces++} END{print "tab-indented:", tabs+0, "space-indented:", spaces+0}' file.js
```

**Red flags:**
- Mixed tabs and spaces in same file
- Lines >120 characters
- Inconsistent spacing before/after braces
- No blank lines between functions/logic blocks
- Random blank lines within functions

### 4. Comments & Documentation
- Missing comments on complex logic
- Comments that state the obvious
- Comments that don't match code
- Function/method documentation missing
- No JSDoc/docstrings on public APIs
- TODO/FIXME comments without context

**How to detect:**
```bash
# Declarations whose preceding line is not a comment or doc-block close
awk 'prev !~ /(\*\/|"""|^[[:space:]]*(\/\/|#))/ && /^[[:space:]]*(export )?(async )?(function|class|def |public )/ {print NR": "$0} {prev=$0}' file.js
```

**Red flags:**
- Public functions without documentation
- Comments like "// increment counter"
- Complex logic without explanation
- TODO comments without issue reference
- No function parameter/return documentation

### 4.5. Comment Accuracy & Comment-Rot

A comment that lies is worse than no comment — the reader trusts it and reasons from a false premise. Three shapes, all documentation-class (LOW/MEDIUM per the Severity tagging section below):

- **Contradicts the code** — the comment describes behavior the code no longer has ("returns null on miss" above a function that now throws; "sorted ascending" above a descending sort).
- **Stale reference** — names a renamed symbol, a moved path, or a removed flag/parameter ("see `oldHelper()`" when it was renamed; "set `--legacy` to enable" when the flag was deleted; a doc-comment `@param` for an argument the signature dropped).
- **Low-value restatement** — the comment merely re-states the line it sits on, adding no intent or rationale (`i++ // increment i`). Distinct from §4's "comments that state the obvious" only in emphasis; route the finding through whichever phrasing fits.

Do not flag from the comment alone — read the code the comment describes and confirm the mismatch before emitting. A comment about a `why` (business reason, edge-case rationale) that still holds is correct even when terse.

**Red flags:**
- Comment states behavior the adjacent code does not exhibit
- Comment references a symbol / path / flag that grep cannot find in the current tree
- Doc-comment `@param` / `@returns` that no longer matches the signature

### 5. Code Duplication
- Copy-pasted code blocks (>5 lines repeated)
- Similar logic in multiple functions
- Utility code scattered across files
- Tests with duplicate setup code
- Constants defined in multiple places

**Red flags:**
- Same code block appears 2+ times
- Multiple places doing same validation
- Constants defined in multiple files
- Similar function implementations
- Utility code duplicated across tests

### 6. Imports & Dependencies
- Unnecessary imports (unused modules)
- Wildcard imports (import *)
- Circular import patterns
- Incorrect import paths
- Too many imports in single file

**Red flags:**
- `import * as everything from 'module'`
- `const _ = require('lodash')` if only using 2 functions
- Imports not used in file
- Relative imports going up many levels (`../../..`)
- Circular dependency patterns

### 7. Type Annotation Hygiene

This section owns the *declared types* — annotations, `any` breadth, unsafe casts. It does NOT own runtime validation: missing input validation at an API boundary is `security`'s (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/security-criteria.md` §5 Input Validation & Output Encoding), and a missing null / undefined check on external input is `bugs`' (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/bugs-criteria.md` §1). Both reach the user through their own dimension at a severity a style rubric cannot assign — emitting them here caps a real defect at LOW and reports it twice.

- Missing type annotations (if using TypeScript)
- `any` type used too broadly
- Type mismatches in assignments
- Type-unsafe casts and assertions

**How to detect:** No grep separates a deliberately-untyped signature from a missing annotation, so read the changed signatures directly — or take the type-checker's own output where the project runs one (`noImplicitAny`, `mypy`).

**Red flags:**
- Functions without parameter types (TypeScript)
- Return types omitted on public functions
- Broad use of `any` type
- Type-unsafe casts or assertions

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
