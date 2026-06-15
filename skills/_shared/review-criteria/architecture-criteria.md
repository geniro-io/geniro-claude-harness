# Architecture Review Criteria

Design patterns, modularity, coupling, performance, scalability, and technical debt assessment.

## Contents

- What to Check
- Output Format
- Common False Positives
- Stack-Agnostic Patterns
- Review Checklist
- Severity Guidelines

---

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
deps=$(grep "import\|require" "$file" | grep -oE "from ['\"]\./[^'\"]+['\"]" | sed "s/from ['\"]\.\\///;s/['\"]//g")  # -oE (portable ERE), not -oP (PCRE) — BSD/macOS grep lacks -P and the snippet exits rc=2
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

### 1.5. Caller-Blast Check for Semantic Mutations

A "semantic mutation" is a code change where a function / method / field / operator / comparison / return-value's BEHAVIORAL CONTRACT changes but its signature / name stays stable. The signature stability means `Grep <symbol>` finds all callers, but every caller is silently exposed to the new behavior without a single line of code change at the call site. These changes look local in the diff but have global blast radius.

**Common shapes:**
- Operator flips: `>` → `>=`, `===` → `==`, `&&` → `||` in a shared helper or comparison
- Return-value semantic change: `null` → `[]`, `undefined` → default-object, throwing → returning, `false` → `null`
- New branch added to a previously-total function: new fail-closed path, new short-circuit, new default
- Regex / parser tightening: `\d+` → `\d{4}`, lookahead added, anchor moved
- Default-argument shift: default value of a parameter changed
- Order-of-operations change: `sort by A, B` → `sort by A, B, C`
- Time semantics flip: `now` → `event_time` or vice versa
- SQL / ORM hydration mode flip: lazy → eager or vice versa (the OPTIMIZATION dimension may also catch this, but the BLAST radius reasoning is architecture's)

**How to detect:**
1. From `DIFF CONTEXT`, scan changed hunks for: operator changes (`>` ↔ `>=`, `===` ↔ `==`), return-value type or value changes, default-argument changes, regex changes, new conditional branches in shared helpers.
2. For each candidate symbol whose semantic changed but whose signature / name is stable, count callers via the Grep tool (NOT bash grep): `Grep(pattern="SymbolName", output_mode="count", glob="<project-language-glob>")`. Adjust `glob` per the project's languages (e.g., `*.ts` for TypeScript, `*.py` for Python, `*.rb` for Ruby).
3. Classify risk per the canonical Change Impact Scoring rubric at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` § "Step 2: Change Impact Scoring" (1-3 callers LOW / 4-9 MEDIUM / 10+ HIGH). Apply the same escalation override: any public API / module export / shared type change is HIGH regardless of count.
4. For each caller above LOW: open the call site, read the surrounding context (5-10 lines), and ask: does the new semantic break THIS caller's assumption? Did the PR description mention this caller? Are there tests asserting THIS caller's behavior under the new semantic?
5. Surface findings as: "Symbol `<name>` at `<file:line>` had a semantic mutation (was `<old>`, now `<new>`) with N callers; caller at `<callsite-path:line>` reads the result and `<does-X>` — verify intent or add test."

**Red flags:**
- A 1-line diff in a shared helper / utility / comparison function (operator flip, return-value change) with >0 callers outside the changed file
- A new conditional branch added to a function that previously fell through (silent change in fall-through callers' behavior)
- A regex / pattern tightening in a shared validator with no test asserting the new tighter match
- A semantic mutation in a symbol named in the PR description as "unchanged" or "refactor only" — the description claim is wrong
- A change to a primitive's behavior with multiple unnamed callers; PR description names only one caller

**Output guidance:**
- Severity HIGH when callers >= 10 OR symbol is a public API / module export / shared type.
- Severity MEDIUM when callers 4-9 AND not a public API (callers 1-3 → LOW per the step 3 rubric above).
- Severity CRITICAL when the semantic change is fail-closed (returns null / empty / throws on what previously succeeded) AND a downstream filter / sort / dispatch / digest relies on non-null / non-empty results — the change silently DROPS data from user-visible surfaces.
- The fix is rarely "revert" — it's "name the affected callers in the PR description, add tests asserting new semantic at each non-trivial caller, and confirm whether each caller still satisfies its own contract under the new semantic."

### 1.6. Parallel-path symmetry (mirror-gap)

When a hunk adds or changes a guard / filter / cleanup / replacement on ONE code path, verify the same treatment reached every sibling path that shares the invariant. The defect is an asymmetric edit: path A gets the new guard, the structurally parallel path B is left in the old behavior, and the gap is invisible at A's diff site. Common pairs: scheduled vs. on-demand (cron ↔ manual trigger), delete vs. replace (a row removed on one branch must be re-created on the mirror branch), cascade vs. single-row wipe, create vs. reclaim, encode ↔ decode, serialize ↔ deserialize.

**How to detect:**
1. Name the invariant the change enforces (e.g., "every deleted row is replaced", "superseded records are synced, not dropped").
2. Identify sibling paths that share it — a sibling function with a parallel name (`syncWeekly` ↔ `syncDaily`), an adjacent `switch` / `if` arm, or a dispatcher where only one variant was edited. `Grep(pattern="<sibling-stem>", output_mode="files_with_matches", glob="<project-language-glob>")` the enclosing module (adjust `glob` per the project's languages — e.g., `**/*.{ts,tsx,js,jsx}` / `**/*.py` / `**/*.go`).
3. For each sibling: did the diff apply the same guard / replacement there? A sibling that shares the invariant but is untouched by the diff is the mirror gap.
4. When you confirm one gap, sweep the rest — enumerate ALL siblings in the module / switch / dispatch table and check each; a point-fix on one while C and D stay broken reproduces the asymmetry one level down.

Severity HIGH when the untreated sibling loses or corrupts data; MEDIUM when it degrades gracefully. Anchor the finding at the edited path and name the unedited sibling `path:line`.

This compact form is the primary owner of the check in review contexts that do NOT spawn a separate `regressions` dimension (e.g., `/geniro:implement` Phase 3 self-review), so the asymmetric-edit class is still caught there. In `/geniro:review`, the dedicated `regressions` reviewer runs the fuller procedure at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/regressions-criteria.md` §4 in parallel; both dimensions emitting the same mirror-gap finding is expected convergence — Phase 3 dedup merges them and treats the agreement as a strong keep signal, so do not suppress your finding on the assumption another dimension will cover it.

### 1.7. Type design — make illegal states unrepresentable

When a type can hold a combination of values that the domain forbids, every consumer must defensively guard against the impossible case, and one missed guard is a latent bug. Strong types push invariant enforcement to construction time so the compiler — not scattered runtime checks — rejects illegal states. Flag a change that introduces or extends a type whose shape admits states the domain rules out.

**Common shapes:**
- **Invariant not expressed in the type** — two fields whose validity is coupled but typed independently (`status: string` + `error: string` where `error` is meaningful only when `status === "failed"`; a `start` / `end` pair with no construction-time ordering guarantee). Model as a discriminated union / sum type so the invalid combination cannot be built.
- **Public mutable field breaking encapsulation** — an invariant-bearing field exposed as a public mutable property, so any caller can set it to a value that violates the invariant after construction. Make it private + validate on the setter, or immutable.
- **Stringly-typed value where an enum/union fits** — a fixed finite set of states carried as a free `string` / `int` (e.g., `role: string` for a known `{admin, member, guest}` set), so the type permits the typo `"admni"` and forces a string-compare guard at every use site.
- **Optional field that should be required by construction** — a field typed `T | null` / `Option<T>` / `?` only because of construction-order convenience, where the value is always present once the object is fully built; every reader then null-checks a value that is never actually null.
- **Escape hatch bypassing the type's guarantee** — a cast / `as any` / `unwrap()` / `!` non-null assertion / reflection write that lets a caller route around the invariant the type was designed to enforce, re-admitting the illegal state through the back door.

**How to detect:**
1. From `DIFF CONTEXT`, find new or widened type / class / struct / interface declarations and their field types.
2. For each, ask: is there a combination of these field values the domain forbids? Can a caller construct or mutate the object into that combination? Is a finite set of states carried as an unconstrained primitive?
3. Check call sites for the symptom — repeated defensive guards (`if (x.status === "failed" && x.error)`, null-checks on a never-null field, string-equality switches over a stringly-typed value). Repeated guards across callers indicate the invariant belongs IN the type.
4. Check for escape hatches added in the same diff that bypass an existing type guarantee (`as any`, `unwrap`, non-null `!`, public mutable field added to a previously-encapsulated type).
5. Surface as: "Type `<name>` at `<file:line>` permits the illegal state `<combination>`; callers at `<file:line>` guard against it at runtime — model as `<discriminated union | enum | required field | private+validated>` so the invalid case cannot be constructed."

**Red flags:**
- Coupled fields typed independently, validated by convention at each use site rather than at construction
- A known finite set carried as a free string / int
- A field typed optional purely for construction order, null-checked everywhere despite never being null
- A public mutable field on a type whose other invariants assume that field is controlled
- An `as any` / cast / non-null assertion / `unwrap` added to route around a type's guarantee

Severity MEDIUM when the unrepresentable-state risk is contained to one module and guarded today; HIGH when an escape hatch or public mutable field lets a cross-module caller construct the illegal state and a downstream consumer assumes the invariant holds. Per the CRITICAL tier in the Severity Guidelines below, this dimension does not emit CRITICAL on its own — if an illegal state actually corrupts data at runtime, that runtime defect is owned by the bugs dimension.

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
- Some functions use try-catch, others use.catch
- `catch (e) {}` (empty catch)
- Errors logged without context
- No error hierarchy
- Different error handling per layer

### 6. Performance & Scalability

> **Boundary with optimizations-criteria.md:** below owns architecture-level perf concerns — N+1 query patterns, ORM eager-loading, missing caching/memoization, missing pagination on unbounded queries, sync I/O in async context, O(n²) algorithms. ORM hydration-skip mechanisms (`.lean`, `disableIdentityMap`, `raw:true`, `getRawMany`, `HYDRATE_ARRAY`, `.values`, `.pluck`), column/field projection on the wire, React re-render hygiene, frontend bundle/asset perf, async parallelization, and per-row → bulk INSERT/UPDATE rewrites are owned by the **optimizations** review dimension at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/optimizations-criteria.md`. If a finding fits both, prefer optimizations when the fix is a per-row → bulk write rewrite or a wire-projection / hydration-skip change; keep N+1 read patterns, caching layers, and pagination contracts with architecture (optimizations-criteria explicitly routes N+1 back here, and the HIGH tier below owns "N+1 in a request-handling path" — so routing a query-shape N+1 to optimizations would let it fall between the two dimensions).

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
- Code that duplicates existing patterns elsewhere — "elsewhere" includes peer PRs surfaced via the `PEER-PR CONTEXT:` slot in this prompt (when non-`none`); a valid finding shape is "PR #N (peer) introduces helper `<name>` at `<file:line>` — current change reimplements it inline, consider reusing or coordinating"
- **Linear parent-epic awareness** — when the `LINEAR CONTEXT:` slot shows a non-`none` parent + sibling sub-tasks AND `PEER-PR CONTEXT:` lists a sibling PR carrying one of those sub-task IDs, flag architectural divergence between parallel sub-tasks of the same epic. Valid finding shape: "Parent epic <ENG-100> distributes work across <current PR sub-task X> and <sibling PR #N sub-task Y>; the two PRs adopt incompatible <data model | API contract | layer boundary> for the shared epic surface — coordinate before either lands". Severity HIGH when the divergence creates a runtime contract collision; MEDIUM otherwise.

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

### 9. Spec done-condition progress (when PLAN CONTEXT present)

When a plan / spec is attached to this review, the spec's "Done Condition" names an observable signal that defines completion (e.g., "all 5 acceptance tests green", "feature ships behind flag AND telemetry shows ≥1 successful use", "PR approved by stakeholder X"). Beyond checking that the diff stays inside the stated scope, ask whether the diff **achieves, or visibly progresses toward, that done signal** — not just whether it touches the named files. A change can land every scoped file and still carry no artifact moving toward the completion signal (the test the signal names was never written, the telemetry the signal expects is never emitted).

This is a **static diff-inspection check only — no command execution.** Read the diff against the stated signal; do not run the test suite or any other command to confirm the signal (that runtime confirmation is a separate concern, owned elsewhere). The point here is: does the diff contain the *artifact* the signal would need?

**Single-source the signal ontology.** The observable-signal definitions (test-green / telemetry-shows / approval / shipped-to patterns) and the per-signal detection guidance live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` §"10. Done Condition Met". Read that section for the signal taxonomy; do not re-derive or copy the patterns here — the dedicated dimension owns the canonical ontology and a copy would drift.

**How to detect:**
1. Confirm PLAN CONTEXT carries structured frontmatter (`geniro_kind: design-doc`) so the Done Condition has a citable section anchor. If it does not — unstructured / prose-only PLAN CONTEXT — **skip this check silently**: emit nothing (no finding, no `open_questions[]` entry). An unstructured plan has no citable Done-Condition anchor, so the static §9 check has nothing to verify against; upgrading the plan to the structured `geniro_kind: design-doc` schema re-enables the check.
2. With structured context, read the Done Condition's observable signal (per the ontology in spec-compliance-criteria.md §10).
3. Check whether the diff carries the artifact that signal needs — the new/updated assertions for a test-based signal, the metric/log emission at the named boundary for a telemetry-based signal, the wiring for a flag-gated signal. **Anchor the finding to the real production code location that lacks the artifact**, not to the plan fragment: the function or branch the named test would exercise but doesn't, the boundary in the source where the expected metric/log is never emitted, the flag-check site that was never wired. Cite that code path as the finding's `File:line` (structurally like the §1.6 mirror-gap finding, which anchors at an existing code path whose mirror is missing). Anchoring to a code location — not a spec excerpt — is what lets the finding survive `/geniro:review`'s drop-on-no-`file:line` filter; a finding whose only citation is the plan text gets suppressed.
4. Classify the divergence before flagging it (the spec is the primary intent rubric but a fallible artifact). If the diff looks like it deliberately and correctly departed from a stale or wrong Done Condition — the signal references a file / endpoint / behavior the live code contradicts — this is a possibly-stale-spec case, not an implementation gap: route it to needs-intent-confirmation (`[INTENT-CHECK]`) at MEDIUM, not an implementation defect, mirroring how the dedicated spec-compliance dimension separates a code-defect from a spec-defect (spec-compliance-criteria.md §"Spec-premise validation"). Otherwise, when the signal still holds and the diff simply carries nothing moving toward it, surface the gap at HIGH.

**Red flags:**
- The Done Condition names "all acceptance tests green" but the diff adds no test asserting the named behavior.
- The Done Condition names a telemetry / log signal but the diff emits no metric or log at the relevant boundary.
- The Done Condition names a flag-gated rollout but the diff has no flag wiring.

**Finding text:** "The plan's completion signal is `<signal>`, but `<code path at File:line>` — the function the named test would exercise / the boundary where the expected metric is emitted / the flag-check site — carries no artifact moving toward it: `<what's missing>`." Anchor the finding at that production `File:line` and cite the spec's Done Condition fragment verbatim as the rubric. Severity caps at HIGH here (per the Severity Guidelines below, this dimension never emits CRITICAL); a possibly-stale-spec divergence caps at MEDIUM with `[INTENT-CHECK]`.

This check **complements** the dedicated spec-compliance dimension rather than duplicating it. In `/geniro:review`, spec-compliance runs as its own reviewer and owns the fuller Done-Condition audit (it is the canonical owner of the section-11 ontology). This subsection is the compact form that runs in review contexts which do NOT spawn a separate spec-compliance dimension (e.g., `/geniro:implement` Phase 3 self-review), so the done-signal-progress class is still caught there. In `/geniro:review`, both dimensions may independently surface the same done-condition gap — that is expected overlap, not a merge: the two findings do not dedup into one, because spec-compliance anchors its finding with the `File: SPEC-COMPLIANCE` sentinel while this dimension anchors at the production code path that lacks the artifact, so the two carry different `File:line` keys and stand as separate findings. Surface yours anyway; the convergence on the same gap is itself a strong keep signal. In `/geniro:implement` Phase 3 (no separate spec-compliance reviewer), this subsection is the only place the gap is caught.

## Output Format

Emit findings in the standard reviewer-agent output format defined in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format.

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
- [ ] Types make illegal states unrepresentable (invariants enforced at construction, not by convention)
- [ ] Abstractions properly hide implementation details
- [ ] SOLID principles generally followed
- [ ] Code organization is consistent
- [ ] Error handling follows patterns
- [ ] No obvious performance red flags
- [ ] Technical debt is documented/addressed
- [ ] Code is designed to be testable
- [ ] Patterns align with codebase standards
- [ ] When a plan is attached, the change carries an artifact moving toward its stated completion signal

## Severity Guidelines

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.

- **CRITICAL** — Never emitted by this dimension. Architecture findings cannot block deploy on their own — they signal design risk, not immediate breakage. A semantic mutation that silently drops data from user-visible surfaces (per §1.5 Caller-Blast Check) is the rare CRITICAL path, and even then the finding is logged under the bugs or optimizations dimension that owns the runtime defect.
- **HIGH** — Caller-blast >= 10 surviving callers, or a public-API / module-export / shared-type change at any count, when a contract changes (per §1.5 Caller-Blast Check thresholds in this file); circular dependency introduced where none existed; new tight coupling between modules that prior architecture explicitly decoupled (cite the decoupling source); new shared mutable state across boundaries; N+1 pattern in a request-handling path; a type-design gap (per §1.7) where an escape hatch or public mutable field lets a cross-module caller construct an illegal state a downstream consumer assumes cannot exist.
- **MEDIUM** — Caller-blast 4-9 callers on a contract change; coupling increase with documented future remediation cost (e.g., the dimension flagged a similar coupling in a prior PR surfaced via the inline `PEER-PR CONTEXT:` slot); module-boundary violation that requires a sibling module to know an implementation detail; a type-design gap (per §1.7) contained to one module and guarded by convention at each use site today.
- **LOW** — Stylistic structural suggestions ("this would be cleaner as a class"); coupling concerns without measured blast radius; "consider splitting this module" without a defect or growth-pressure citation; documentation or PR-description nits about an architectural area.
