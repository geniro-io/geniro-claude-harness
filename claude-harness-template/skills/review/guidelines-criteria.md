# Guidelines Review Criteria

Code style, naming conventions, documentation, consistency, and compliance with project standards.

## What to Check

### 1. Naming Conventions
- Variable names unclear or misleading (`data`, `x`, `temp`, `result`)
- Inconsistent naming style (camelCase vs snake_case mixed)
- Names don't reflect purpose (`fn`, `proc`, `handler` without context)
- Magic numbers and strings without explanation
- Misleading names (name doesn't match behavior)

**How to detect:**
```bash
# Find single-letter or vague variables
grep -nE "^\s*[a-z]\s*=" file.js
grep -nE "var (x|y|z|data|temp|result|obj|arr|str)\b" file.js
# Check naming inconsistency
grep -n "const\|let\|var" file.js | head -20 | cut -d: -f2 | sort | uniq -c
# Find magic numbers
grep -nE "[0-9]{2,}" file.js | grep -v "200\|404\|timestamp\|size"
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

**How to detect:**
```bash
# Find generic function names
grep -nE "function (do|process|handle|execute|run|work|test)\(" file.js
grep -nE "(async |)function\s+[a-z0-9]+\(" file.js | grep -v "get\|create\|fetch\|validate\|check"
# Look for generic class names
grep -n "class [A-Z]" file.js | grep -E "Utils|Manager|Handler|Service"
```

**Red flags:**
- Functions: `doSomething()`, `processData()`, `handleIt()`, `executeTask()`
- Classes: `UtilityManager`, `DataService`, `GeneralHandler`
- No clear verb (get, create, fetch, validate, check, transform)
- Private methods unclear (\_process, \_handle)

### 3. Code Formatting & Style
- Inconsistent indentation (tabs vs spaces mixed)
- Line length exceeding standard (>100 chars)
- Missing blank lines between logical sections
- Inconsistent brace placement
- Inconsistent spacing around operators

**How to detect:**
```bash
# Check indentation consistency
head -20 file.js | cat -A | grep -E "^\s" | cut -c1-5 | sort | uniq -c
# Check line length
awk 'length > 100 {print NR": length=" length}' file.js
# Check brace style consistency
grep -n "{\|}" file.js | head -10
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
# Find functions without comments
grep -n "^function\|^async function\|^  [a-z].*() {" file.js
# Find obvious comments
grep -n "//" file.js | grep -E "increment|add one|set variable"
# Find TODO/FIXME
grep -n "TODO\|FIXME\|XXX\|HACK" file.js
# Check for JSDoc
grep -B2 "^function\|^class" file.js | grep -c "/\*\*"
```

**Red flags:**
- Public functions without documentation
- Comments like "// increment counter"
- Complex logic without explanation
- TODO comments without issue reference
- No function parameter/return documentation

### 5. Code Duplication
- Copy-pasted code blocks (>5 lines repeated)
- Similar logic in multiple functions
- Utility code scattered across files
- Tests with duplicate setup code
- Constants defined in multiple places

**How to detect:**
```bash
# Find similar code patterns
grep -n "for.*in\|forEach\|map\|reduce" file.js
# Look for repeated constant values
grep -nE ":\s*['\"].*['\"]\s*[,;}]" file.js | cut -d: -f2 | sort | uniq -c | sort -rn
# Find duplicate function definitions
grep -n "function\|const.*=" file.js | awk '{print $1}' | sort | uniq -c | sort -rn
```

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

**How to detect:**
```bash
# Find unused imports
grep -n "^import\|^require" file.js
# Find wildcard imports
grep -n "import \*\|from '.*\*'\|require('.*')" file.js
# Count imports per file
grep -c "^import\|^require" file.js
# Check for unused variables
grep -n "import {.*} from\|const.*require" file.js
```

**Red flags:**
- `import * as everything from 'module'`
- `const _ = require('lodash')` if only using 2 functions
- Imports not used in file
- Relative imports going up many levels (`../../..`)
- Circular dependency patterns

### 7. Type Safety & Validation
- Missing type annotations (if using TypeScript)
- `any` type used too broadly
- Type mismatches in assignments
- No input validation at API boundaries
- Missing null/undefined checks for external input

**How to detect:**
```bash
# Find 'any' usage in TypeScript
grep -n ": any\|as any" file.ts
# Find missing type annotations
grep -n "function.*{" file.ts | grep -v ":"
# Check for loose types
grep -n "Object\|Function" file.ts
```

**Red flags:**
- Functions without parameter types (TypeScript)
- Return types omitted on public functions
- Broad use of `any` type
- Missing input validation in API routes
- Type-unsafe casts or assertions

### 8. Consistency with Codebase (Convention Guard)

This is the most important guideline dimension — AI-generated code's #1 failure mode is introducing new patterns that differ from the repo's existing conventions ("convention drift").

- Different patterns than rest of codebase
- Inconsistent error handling approach
- Different naming style than existing code
- Import styles differ from convention
- Inconsistent module structure
- File placed in wrong directory for its type
- ADR contradictions (violating recorded architectural decisions)

**How to detect — Exemplar File Comparison:**

The key technique: find the closest existing file to each changed file, then diff the patterns.

```bash
# Step 1: Find exemplar files — the closest existing files to the changed ones
# For a new API route:
ls src/routes/ | head -5                    # See existing route files
# For a new component:
ls src/components/ | head -5                # See existing component files
# For a new service:
ls src/services/ | head -5                  # See existing service files

# Step 2: Compare patterns between new code and exemplar
# Naming convention check
grep -n "^export\|^function\|^class\|^const\|^interface" new_file.ts > /tmp/new_exports.txt
grep -n "^export\|^function\|^class\|^const\|^interface" exemplar_file.ts > /tmp/old_exports.txt
# Compare: are they using same naming style? (camelCase vs PascalCase vs snake_case)

# Import style check
head -20 new_file.ts | grep "import"        # New file imports
head -20 exemplar_file.ts | grep "import"   # Exemplar imports
# Compare: relative vs absolute paths? Named vs default? Order?

# Error handling pattern check
grep -n "try\|catch\|throw\|Error\|error" new_file.ts
grep -n "try\|catch\|throw\|Error\|error" exemplar_file.ts
# Compare: same error handling approach?

# File structure check — does new file follow same section ordering?
grep -n "^//\|^/\*\|^export\|^class\|^interface\|^type" new_file.ts | head -20
grep -n "^//\|^/\*\|^export\|^class\|^interface\|^type" exemplar_file.ts | head -20

# Step 3: Check for ADR violations (if ADRs exist)
find . -path "*/adr/*.md" -o -path "*/decisions/*.md" 2>/dev/null | head -10
# Read relevant ADRs and verify new code doesn't contradict them
```

**Convention drift signals (specific to AI-generated code):**
- New code uses a pattern that exists NOWHERE else in the codebase
- Error handling wraps in try/catch when codebase uses Result types (or vice versa)
- File exports a default when codebase uses named exports (or vice versa)
- New utility function duplicates an existing one under a different name
- Code uses a library/package not in package.json when an existing dep does the same thing
- Test file structure doesn't match existing test files (describe/it vs test(), file naming)

**Red flags:**
- New code using different naming style
- Different error handling than existing code
- New patterns not used elsewhere in the codebase
- Breaks existing architectural patterns
- Differs from style guide or linter config
- New dependency added when existing dependency covers the use case
- File placed in unexpected location vs codebase convention

## Output Format

```json
{
  "type": "guidelines",
  "severity": "critical|high|medium",
  "title": "Style or guideline violation",
  "file": "path/to/file.js",
  "line_start": 42,
  "line_end": 48,
  "description": "Description of the guideline violation",
  "category": "naming|formatting|comments|duplication|imports|types|consistency",
  "current": "Current code/pattern",
  "expected": "Expected code/pattern per guidelines",
  "recommendation": "How to fix it",
  "confidence": 92
}
```

## Common False Positives

1. **Single-letter vars in small scope** — OK for short lambdas/loops
   - `array.map(x => x * 2)` is acceptable
   - `for (let i = 0; i < n; i++)` is standard
   - Check scope: if var used in 5+ lines, needs better name

2. **Generic names in tests** — Often acceptable for test setup
   - `const user = createTestUser()`
   - `const data = { id: 1, name: 'Test' }`
   - Only flag if confusing within test

3. **Pragmatic duplication** — Sometimes better than premature abstraction
   - Two similar implementations might have different requirements
   - Duplicating for different contexts is acceptable
   - Only flag obvious shared logic

4. **Type-safe "any"** — Exceptions exist for special cases
   - `JSON.parse()` returns any (by design)
   - Bridge code to untyped libraries uses any
   - Check if there's legitimate reason

5. **Comments explaining "why"** — These are good, not obvious
   - Explaining business logic or tricky decisions is valuable
   - Only flag comments that state the obvious code

6. **Linter conflicts** — If codebase uses specific config
   - Project might enforce different style than standard
   - Check `.eslintrc`, `prettier.config`, etc.
   - Don't flag if matches project config

## Stack-Agnostic Patterns

Works across all languages/frameworks:
- Naming conventions (all languages)
- Code formatting (all languages)
- Documentation (all languages)
- Code duplication (all languages)
- Import/dependency patterns (all languages)
- Consistency patterns (all languages)
- Type safety (statically typed languages)

## Review Checklist

- [ ] Variable names clear and descriptive
- [ ] Function names describe what they do
- [ ] Class names represent their purpose
- [ ] Code formatting consistent
- [ ] Complex logic has explanatory comments
- [ ] Public APIs documented
- [ ] No significant code duplication
- [ ] Imports are necessary and used
- [ ] Type annotations complete (if applicable)
- [ ] Code follows project style guide
- [ ] Naming consistent with codebase
- [ ] No TODO without issue reference

## Severity Guidelines

- **CRITICAL**: Breaks language/framework standards, dangerous patterns
- **HIGH**: Violates team style guide, difficult to understand, significant duplication
- **MEDIUM**: Minor style issues, inconsistency, documentation gaps, naming improvements
