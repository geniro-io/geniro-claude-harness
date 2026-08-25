# Architecture review criteria

Design patterns, modularity, coupling, performance, scalability, and technical debt assessment.

Find every real defect this dimension owns by reading the changed code and its callers directly — your own analysis is the detector. The sections below are the contract you are held to: what NOT to flag, and how severity is calibrated.

## Contents

- §1.5 — Caller-blast check for semantic mutations
- §1.6 — Parallel-path symmetry (mirror-gap)
- §7.5 — Reinvented-wheel / build-vs-buy
- §8 — Testability of the production code
- Common false positives
- Severity guidelines

## Cross-dimension boundary checks

Two checks stay specified in full: each defines a defect-class boundary with the regressions dimension, and `severity-calibration.md` cites them by number.

### 1.5. Caller-blast check for semantic mutations

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
2. For each candidate symbol whose semantic changed but whose signature / name is stable, count its callers — use the project's code-search tooling (a code index, when one is configured, returns the dependents directly), otherwise a count-mode structured search scoped to the project's language files (pattern `SymbolName`, scoped by language glob — e.g., `*.ts` for TypeScript, `*.py` for Python, `*.rb` for Ruby).
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
- When the semantic change is fail-closed (returns null / empty / throws on what previously succeeded) AND a downstream filter / sort / dispatch / digest relies on non-null / non-empty results — the change silently DROPS data from user-visible surfaces — that is a runtime data-loss defect, not an architecture finding. Route it to the bugs dimension (this dimension never emits CRITICAL, per the Severity Guidelines below); keep the architecture finding scoped to the blast-radius reasoning at HIGH.
- The fix is rarely "revert" — it's "name the affected callers in the PR description, add tests asserting new semantic at each non-trivial caller, and confirm whether each caller still satisfies its own contract under the new semantic."

### 1.6. Parallel-path symmetry (mirror-gap)

When a hunk adds or changes a guard / filter / cleanup / replacement on ONE code path, verify the same treatment reached every sibling path that shares the invariant. The defect is an asymmetric edit: path A gets the new guard, the structurally parallel path B is left in the old behavior, and the gap is invisible at A's diff site. Common pairs: scheduled vs. on-demand (cron ↔ manual trigger), delete vs. replace (a row removed on one branch must be re-created on the mirror branch), cascade vs. single-row wipe, create vs. reclaim, encode ↔ decode, serialize ↔ deserialize.

**How to detect:**
1. Name the invariant the change enforces (e.g., "every deleted row is replaced", "superseded records are synced, not dropped").
2. Identify sibling paths that share it — a sibling function with a parallel name (`syncWeekly` ↔ `syncDaily`), an adjacent `switch` / `if` arm, or a dispatcher where only one variant was edited. Search the enclosing module for the sibling stem — the project's code-search tooling, scoped to the project's language files (e.g., `**/*.{ts,tsx,js,jsx}` / `**/*.py` / `**/*.go`).
3. For each sibling: did the diff apply the same guard / replacement there? A sibling that shares the invariant but is untouched by the diff is the mirror gap.
4. When you confirm one gap, sweep the rest — enumerate ALL siblings in the module / switch / dispatch table and check each; a point-fix on one while C and D stay broken reproduces the asymmetry one level down.

Severity HIGH when the untreated sibling loses or corrupts data; MEDIUM when it degrades gracefully. Anchor the finding at the edited path and name the unedited sibling `path:line`.

This compact form is the primary owner of the check in review contexts that do NOT spawn a separate `regressions` dimension (e.g., `/geniro:implement` Phase 3 self-review), so the asymmetric-edit class is still caught there. In `/geniro:review`, the dedicated `regressions` reviewer runs the fuller procedure at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/regressions-criteria.md` §4 in parallel; both dimensions emitting the same mirror-gap finding is expected convergence, since the two rubrics share this check by construction — Phase 3 dedup merges them, so do not suppress your finding on the assumption another dimension will cover it.

### 7.5. Reinvented-wheel / build-vs-buy

Hand-written code in a domain a maintained external library already solves — crypto, auth, password hashing, tokens, date/time math, parsing or serialization of untrusted input, retry-with-backoff, validation, HTTP clients, compression. Detection-only: this dimension flags the smell and tags the finding `[PRODUCT-DECISION]` so the user decides whether to adopt a library — it does not research candidates itself, since the reviewer-agent has no web-research grant and the review path cannot rely on web reach being present.

Trigger condition, finding shape, and the `Options:` block are canonical at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/library-reuse-audit.md` §MODE: review — apply that section when the diff hand-writes non-trivial functionality in one of the domains above; cite it rather than restating its procedure. Severity feeds the HIGH/MEDIUM rows below: MEDIUM is typical; HIGH only when the hand-written code carries real correctness or security risk a battle-tested library would remove (hand-rolled crypto, auth, timezone math, HTML sanitization); never CRITICAL — a runtime defect in the hand-rolled code itself is a bugs/security-dimension finding, not this one's.

### 8. Testability of the production code

> **Boundary with tests-criteria.md:** this section owns whether the PRODUCTION code can be tested — the seams. Judgments about the tests themselves (coverage gaps, brittle assertions tied to implementation, mocking discipline, critical-path coverage) are owned by the `tests` dimension at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md`, which runs in parallel in both `/geniro:review` and `/geniro:implement` Phase 3. Emitting them here reports the same defect twice under a dimension that cannot act on it. Anchor every finding here at the production symbol whose shape is the problem, never at a test file.

- Code shaped so it cannot be exercised without heavy mocking — a high mock count is the symptom, and the finding names the seam that forces it, not the mocks
- Test-context setup that is difficult or impossible to construct (hidden construction, hardcoded dependencies)
- Logic embedded in infrastructure code with no injectable boundary

**Severity:** MEDIUM when the seam forcing heavy mocking sits in code this diff newly introduces; LOW for a pre-existing testability gap the diff does not worsen. Never CRITICAL — a test gap never crashes production on its own; a runtime defect it lets slip through is a bugs-dimension finding.

## Common false positives

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

5. **Intentional simplification** — Simple code beats perfect design
- Don't flag over-engineering fears
- Some coupling is acceptable for simplicity
- Only flag if causing real problems

## Severity guidelines

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.

- **CRITICAL** — Never emitted by this dimension. Architecture findings cannot block deploy on their own — they signal design risk, not immediate breakage. A semantic mutation that silently drops data from user-visible surfaces (per §1.5 Caller-Blast Check) is a runtime defect owned by the bugs dimension, not an architecture CRITICAL.
- **HIGH** — Caller-blast >= 10 surviving callers, or a public-API / module-export / shared-type change at any count, when a contract changes (per §1.5 Caller-Blast Check thresholds in this file); circular dependency introduced where none existed; new tight coupling between modules that prior architecture explicitly decoupled (cite the decoupling source); new shared mutable state across boundaries; N+1 pattern in a request-handling path; a type-design gap where an escape hatch or public mutable field lets a cross-module caller construct an illegal state a downstream consumer assumes cannot exist; hand-rolled crypto / auth / parsing a battle-tested library would secure (per §7.5 reinvented-wheel).
- **MEDIUM** — Caller-blast 4-9 callers on a contract change; coupling increase with documented future remediation cost (e.g., the dimension flagged a similar coupling in a prior PR surfaced via the inline `PEER-PR CONTEXT:` slot); module-boundary violation that requires a sibling module to know an implementation detail; a type-design gap contained to one module and guarded by convention at each use site today; reinvented-wheel / build-vs-buy where a maintained library already solves the hand-written code (per §7.5, typical tier); function-level complexity / deep nesting on a critical path where the cognitive load raises real defect risk.
- **LOW** — Stylistic structural suggestions ("this would be cleaner as a class"); coupling concerns without measured blast radius; "consider splitting this module" without a defect or growth-pressure citation; excessive function-level nesting / cognitive load on a non-critical path; documentation or PR-description nits about an architectural area.
