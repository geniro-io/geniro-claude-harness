# Architecture Review Criteria

Design patterns, modularity, coupling, performance, scalability, and technical debt assessment.

## What to Check

### 1. Module Design & Coupling
- Circular dependencies between modules
- High coupling: too many imports from other modules
- Low cohesion: module doing multiple unrelated things
- Missing abstraction layers
- Tight coupling to external services/libraries

**How to detect:**
```bash
# Count imports per file
grep -c "^import\|^require\|^from" file.js
# Find circular imports — build dependency graph and check for cycles
# Step 1: Extract all import relationships
grep -rn "import.*from\|require(" src/ | awk -F: '{print $1, $0}' > /tmp/deps.txt
# Step 2: For each file, check if any of its imports also import it back
for file in $(grep -rl "import\|require" src/); do
  deps=$(grep "import\|require" "$file" | grep -oP "from ['\"]\./(.*?)['\"]" | sed "s/from ['\"]\.\\///;s/['\"]//g")
  for dep in $deps; do
    grep -q "$(basename "$file" .js)\|$(basename "$file" .ts)" "src/$dep"* 2>/dev/null && echo "CIRCULAR: $file <-> src/$dep"
  done
done
# Check dependency directions
grep "import\|require" file.js | sort
```

**Circular dependency verification:** Don't just grep for import patterns — actually trace the dependency chain. A→B→C→A is circular even though no single file imports from its direct importer. Use `madge --circular` (Node) or equivalent tooling when available.

**Red flags:**
- Single file with 20+ imports
- A imports from B, B imports from A (direct circular)
- A→B→C→A (transitive circular — equally dangerous)
- File doing auth AND data processing AND caching
- Direct external API calls scattered throughout
- Hard to test due to tight coupling

### 2. Abstraction & Interface Design
- Missing abstraction layers (business logic tightly coupled to implementation)
- Poor interface design (leaky abstractions)
- Violation of Dependency Injection pattern
- Hard dependencies on concrete implementations
- Public methods/properties that expose internals

**How to detect:**
- Look for direct database queries in business logic
- Find service classes importing UI components
- Check for hardcoded configuration values
- Identify classes/modules with unclear purpose
- Look for "god objects" doing too much

**Red flags:**
- Business logic directly calls database driver
- Controllers importing service implementation details
- Utils importing from domain layers
- Files/modules that are hard to name (too many responsibilities)
- Difficult to mock/test due to hard dependencies

### 3. SOLID Principles Violations
- **Single Responsibility**: Classes doing multiple things
- **Open/Closed**: Hard to extend without modifying
- **Liskov Substitution**: Subclasses breaking base contracts
- **Interface Segregation**: Forced to depend on unused methods
- **Dependency Inversion**: High-level modules depending on low-level

**How to detect:**
- Find classes with mixed responsibilities
- Look for `if` statements checking subclass types
- Identify base classes with many unused methods
- Check if changing one thing breaks unrelated code
- Find hard dependencies on implementations

### 4. Code Organization & Structure
- Inconsistent file structure across codebase
- Related functionality scattered across modules
- Poor naming conventions (unclear file/function purposes)
- Missing separation of concerns (UI, business logic, data)
- Inconsistent patterns/styles

**How to detect:**
```bash
# Find files that are hard to categorize
ls -la | grep "util\|misc\|temp\|helper"
# Check function/class naming consistency
grep "^class\|^function\|^export" file.js
# Look for large files (potential split opportunity)
wc -l file.js | awk '$1 > 500 {print $0}'
```

**Red flags:**
- Many "utils" or "misc" modules
- Same feature scattered across multiple directories
- Inconsistent naming patterns
- Very large files (500+ lines)
- Functions with vague names (do, process, handle)

### 5. Error Handling Architecture
- Inconsistent error handling patterns
- Missing error context propagation
- Poor error recovery strategies
- Swallowing errors without logging
- No error hierarchy/classification

**How to detect:**
- Look for inconsistent try-catch patterns
- Find places where errors are silently caught
- Check if errors are logged with context
- Identify error types being thrown
- Look for recovery strategies

**Red flags:**
- Some functions use try-catch, others use .catch()
- `catch (e) {}` (empty catch)
- Errors logged without context
- No error hierarchy
- Different error handling per layer

### 6. Performance & Scalability
- N+1 query patterns (queries inside loops instead of batched/joined queries)
- Inefficient algorithms (O(n²) where O(n) possible)
- Unnecessary data loading/processing
- Synchronous operations in async context
- Missing caching or memoization opportunities
- Resource exhaustion (unbounded loops, memory growth)

**N+1 vs Batching — the key distinction:**
- **N+1 pattern (BAD):** Loop over items, execute one query per item. E.g., `for (user of users) { await db.query("SELECT * FROM orders WHERE user_id = ?", user.id) }` — this is O(N) queries.
- **Batched query (GOOD):** Collect all IDs, execute one query. E.g., `await db.query("SELECT * FROM orders WHERE user_id IN (?)", userIds)` — this is O(1) queries.
- **Joined query (GOOD):** Use a JOIN to fetch related data in the original query. E.g., `SELECT u.*, o.* FROM users u LEFT JOIN orders o ON u.id = o.user_id` — this is O(1) queries.
- **ORM eager loading (GOOD):** Use the ORM's built-in mechanism. E.g., `User.findAll({ include: Order })` (Sequelize), `User.objects.prefetch_related('orders')` (Django).

**How to detect:**
```bash
# Find nested loops
grep -n "for.*for\|while.*while" file.js
# Potential N+1 patterns — queries inside loops
grep -n "for\|while\|\.map(\|\.forEach(" file.js | grep -A5 "query\|fetch\|request\|findOne\|findById\|get("
# ORM N+1 — model access in loops
grep -n "\.map(\|\.forEach(\|for " file.js | grep -A3 "\.\(find\|get\|load\|fetch\)"
# Blocking operations
grep -n "readFileSync\|query\|request" file.js | grep -v "async"
```

**Red flags:**
- Queries in loops without batching (the classic N+1)
- ORM lazy-loading inside iteration (e.g., accessing `.related_model` in a loop)
- Nested loops without obvious reason
- Large data structures not paginated
- Synchronous I/O in main code path
- No caching for repeated expensive operations

### 7. Technical Debt
- Deprecated patterns or libraries still in use
- TODO/FIXME comments indicating unresolved issues
- Inconsistent with team/project standards
- Ad-hoc solutions when proper patterns exist
- Code that works but is hard to understand/maintain

**How to detect:**
```bash
# Find TODO/FIXME comments
grep -n "TODO\|FIXME\|XXX\|HACK" file.js
# Deprecated API usage
grep -n "deprecated\|obsolete" file.js
# Comments indicating problems
grep -n "workaround\|temporary\|quick fix" file.js
```

**Red flags:**
- Many unresolved TODO comments
- Using deprecated library versions
- Inconsistent patterns (old style mixed with new)
- Comments saying "this is hacky but it works"
- Code that duplicates existing patterns elsewhere

### 8. Testing Architecture
- Code designed to be difficult to test
- Heavy use of mocks indicates poor design
- Brittle tests tied to implementation details
- No test coverage for critical paths
- Difficult to set up test context

**How to detect:**
- Check if functions are testable (pure or injectable)
- Look for functions with many side effects
- Identify areas with complex setup required
- Check for hardcoded values/dependencies
- See if logic is embedded in infrastructure code

**Red flags:**
- Pure business logic mixed with I/O
- Global state or singletons used throughout
- Functions doing both computation and side effects
- Difficult to create isolated test contexts
- External API calls in core logic

## Output Format

```json
{
  "type": "architecture",
  "severity": "critical|high|medium",
  "title": "Brief architecture issue",
  "file": "path/to/file.js",
  "line_start": 42,
  "line_end": 48,
  "description": "Detailed description of architectural concern",
  "category": "coupling|abstraction|solid|organization|errorhandling|performance|debt|testing",
  "pattern_location": ["file.js:42", "other.js:15"],
  "current_design": "How it's currently structured",
  "impact": "Why this matters (maintainability, scalability, etc.)",
  "recommendation": "Proposed refactoring or improvement",
  "confidence": 85
}
```

## Common False Positives

1. **Pragmatic design** — Sometimes coupling is acceptable for simplicity
   - Framework integration often requires tight coupling
   - Small projects don't need full SOLID adherence
   - Check project size and constraints

2. **Intentional repetition** — Code reuse isn't always beneficial
   - Duplicating code for different contexts is sometimes correct
   - Premature abstraction creates worse problems
   - Only flag if obvious shared logic exists

3. **Framework patterns** — Many frameworks violate SOLID on purpose
   - Rails/Django models do multiple things by design
   - Framework code patterns don't apply to app code
   - Check if pattern is framework-recommended

4. **Configuration-driven behavior** — Behavior controlled externally
   - Configuration injection addresses tight coupling
   - Check if values come from proper config sources
   - Don't flag if using DI framework

5. **Learning code** — New developers might use older patterns
   - Code reviews should mentor, not just criticize
   - Consistency matters, but growth is important
   - Consider context and codebase age

6. **Intentional simplification** — Simple code beats perfect design
   - Don't flag over-engineering fears
   - Some coupling is acceptable for simplicity
   - Only flag if causing real problems

## Stack-Agnostic Patterns

Works across languages/frameworks:
- Module/package import patterns (all languages)
- Dependency directions (acyclic dependencies)
- Class/function responsibility (all OOP languages)
- Error handling strategies (all languages)
- Performance patterns (all runtimes)
- Code organization principles (language-agnostic)

## Review Checklist

- [ ] Module dependencies are acyclic
- [ ] Each module has clear, single purpose
- [ ] Abstractions properly hide implementation details
- [ ] SOLID principles generally followed
- [ ] Code organization is consistent
- [ ] Error handling follows patterns
- [ ] No obvious performance red flags
- [ ] Technical debt is documented/addressed
- [ ] Code is designed to be testable
- [ ] Patterns align with codebase standards

## Severity Guidelines

- **CRITICAL**: Circular dependencies, architectural patterns preventing scalability
- **HIGH**: High coupling, missing abstractions, SOLID violations, N+1 patterns
- **MEDIUM**: Inconsistent patterns, minor organizational improvements, refactoring opportunities
