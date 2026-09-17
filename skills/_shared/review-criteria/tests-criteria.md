# Tests review criteria

Test coverage analysis, edge case handling, test quality, and critical path coverage assessment.

> **Scope:** this dimension judges the TESTS. Whether the production code is *shaped* so it can be tested — the seam, the injectable boundary, logic buried in infrastructure — is owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/architecture-criteria.md` §8, which runs in parallel. When heavy mocking is the observation, both dimensions can see it: emit the test-side finding here (is the mock hiding a real assertion?) and leave the seam-side finding to architecture, anchored at the production symbol.

## Contents

- Test design philosophy (canonical)
- What to look for
- Common false positives
- Litmus test (the deletion test)
- Tests of the scenery — never author, flag for removal
- Assertion completeness & spec coverage
- Test deletions in the diff (inverse deletion test)
- Review checklist
- Severity guidelines

---

## Test design philosophy (canonical)

This section is the canonical doctrine for what makes a test "good" in this codebase. It is read by every tests-dimension reviewer (`/geniro:review` Phase 2, `/geniro:implement` Phase 3 self-review, `/geniro:refactor` reviewer pass), by `/geniro:implement` Phase 2 test authoring (inline and delegated), and by `/geniro:implement` Phase 3's inline edge-case test authoring step. Write the test according to these principles; review the test against them.

### 1. Tests describe behavior, not implementation

A test should read like a specification of what the system does for a user — not a description of how the code is structured internally. The test name + assertions should make the capability obvious to a reader who has never seen the implementation.

- **Good (behavior)**: `test_user_can_checkout_with_valid_cart` / `expect(orderTotal).toBe(42.50)` / `assert response.status_code == 401 when token expired`
- **Bad (implementation)**: `test_internal_helper_returns_array` / `expect(spy).toHaveBeenCalledWith(...)` / `assert mockDB.query.mock_calls[0].args[0] == "SELECT..."`

The test that verifies implementation breaks every time you refactor the implementation. The test that verifies behavior survives refactors and catches behavior regressions.

### 2. Public interface only

Tests reach the system through the same surfaces real callers use — public functions, exported types, REST endpoints, CLI commands. Reaching through private members, internal helpers, or "test-only" backdoors breaks the spec contract: the test passes when the interface is broken (because it's calling around the interface) or fails when the interface is intact (because internal restructuring shifted the private member).

- **Good**: HTTP test calls `POST /api/orders` and asserts on the response.
- **Bad**: Test imports `_calculateOrderTotal` directly and asserts on its return.
- **Bad**: verifying through a side channel — create a user via `POST /api/users`, then assert with a raw `db.query` instead of `GET /users/<id>`; the side-channel read stays green even when the public read path is broken.
- **Exception**: pure-function utility modules whose public API IS the function set under test — test those functions directly.

If a behavior is hard to test through the public interface, the seam is wrong (see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/architecture-vocabulary.md` — narrow seams over wide seams). Fix the seam, not the test framework.

### 3. The "would survive a refactor" rule

Before keeping a test, ask: "if I rename internal functions, move private state around, switch the implementation language of this module — does this test still pass IF behavior is unchanged?" If no, the test is testing implementation. Either rewrite it to verify the behavior it actually cared about, or delete it.

This is the single highest-leverage rule for test quality. Tests that fail a refactor without a behavior change are net-negative — they slow refactoring without protecting the user-visible contract.

### 4. Mocking discipline

Mocks fall into three tiers:

| Tier | Use when | Example |
|---|---|---|
| **External boundary** (allowed) | Mock services your code does not own — third-party APIs, payment processors, email senders, the wall clock | Mock `stripe.charges.create` — you don't control Stripe; you don't want tests calling production |
| **Internal boundary, expensive** (case-by-case) | Mock owned-by-you modules ONLY when running them in tests is genuinely too slow / too stateful (DB, Redis, S3) — and even then, prefer in-memory test doubles or test containers | Mock the database layer in unit tests; use a real test database in integration tests |
| **Internal collaborators, cheap** (FORBIDDEN) | Do NOT mock pure functions, internal helpers, classes you wrote and could just instantiate | Mocking `OrderCalculator` inside a test of `CheckoutService` couples the test to the wiring; refactor breaks it for no behavior change |

**Smell — over-mocking**: more than 3-4 mocks per test usually means the test has been rewritten to match the implementation's structure rather than the system's behavior. Either the test is testing implementation (Rule 1 violation) or the module being tested is too coupled to its collaborators (the design is the bug — narrower seams + dependency injection at the boundary, not mocks at every internal call). At external boundaries, prefer per-operation interfaces (`api.getUser(id)`, `api.createOrder(data)`) over one generic fetcher — a generic `api.fetch(endpoint, opts)` forces conditional logic inside every mock, while per-operation functions each mock to a single shape.

**Smell — verifying mock interactions**: assertions like `expect(mockUserRepo.save).toHaveBeenCalledWith(...)` test what the implementation does, not what the system produces. Replace with an assertion on the observable outcome (the saved user comes back when you GET /users/<id>; the side effect happened in the system).

### 5. Test names as specifications

Test names are the index into the spec the test suite encodes. Read the test names alone (without bodies) — does the list tell you what the system does? If yes, the names are doing their job. If you have to read every body to know what's covered, the names are noise.

- **Good name format**: `<actor>_<can_do_thing>_when_<condition>` — `user_can_checkout_when_cart_has_at_least_one_item` / `api_returns_401_when_token_is_expired`
- **Bad name format**: `<function>_<works>` / `<bug-id>_<passes>` — `calculateTotal_works` / `bug_C_regression`
- **Anti-pattern: thread-local labels** — `Bug A/B/C`, `Hypothesis 1`, `regression from review run`, `confirmed by debug-skill run` — meaningful in the conversation that authored them, meaningless once the conversation ends. Tests outlive conversations; names must be self-contained.

### 6. Tests that fail meaningfully

When a test fails, the failure message + the test name must tell a maintainer (a) what behavior broke, (b) what input triggered it, and (c) what the actual vs expected outcome was. A test that fails with `AssertionError: expected true got false` is a test that wastes the next maintainer's time.

- Use assertion libraries that produce diff-shaped messages (`expect(actual).toEqual(expected)` not `expect(condition).toBe(true)`)
- Name the inputs in the test's setup so they appear in the failure stack
- For parameterized / table-driven tests, ensure each row's identifier prints in the failure
- Prefer one assertion per behavioral claim — a test that checks 5 unrelated things produces failures that don't localize the bug

### 7. F→P invariant for new tests

Every newly-authored test must demonstrate red-then-green at least once before being committed:

1. **Red**: run the test against current code BEFORE the change → it must fail with the failure signature you expect (the test is real).
2. **Green**: run the test against code WITH the change → it must pass.

A test that passes the first time you run it (without any production change) is testing something that already works — either it's redundant with existing coverage OR it's not actually exercising the new behavior. Investigate before committing. This rule applies to:
- New tests authored during `/geniro:implement` Phase 2
- F→P tests authored during `/geniro:implement` Phase 3's inline edge-case authoring step

`/geniro:implement` Phase 3's inline edge-case authoring enforces F→P with 3-run determinism checks and deletes a test that passes on current code.

### 8. Coverage is behaviors pinned, not tests written

A test earns its place by a regression only it catches. Before authoring a case, name the single-line revert (or mutation) of the change that would turn this case — and no other kept case — red. When every revert it catches already reddens a kept test, the behavior is already pinned; the new case adds maintenance cost, not coverage.

Judge overlap by the reverts a test catches, never by the lines it executes or the outcome it asserts — two tests walking the same lines can still pin different guards (see §Test deletions in the diff's cause-path doctrine). Every changed branch still earns its one pinning test.

### 9. One behavior, one layer

Pin each behavior at the cheapest layer whose public surface still catches its regression. A behavior an integration test already pins gets no unit test re-asserting it through mocks; a journey an end-to-end test already covers gets no component test mirroring it — the second layer doubles the edits every future change to that behavior needs, without narrowing what can break.

When the project declares what each of its checks covers, pick the layer from that declaration (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-surface.md`).

### 10. Input-only variations are one table

Cases that differ only in input and expected value are rows of one parameterized test (`it.each`, `pytest.mark.parametrize`, a table-driven loop) — extending coverage is then a new row, not a new block. Keep a separate case only when the arrange or the assertion genuinely differs; branching inside a table body hides which row checks what. Each row's identifier prints on failure, per §6.

### 11. Shared arrange lives in a builder

Build the shared shape once — a factory or builder with valid defaults, or shared setup — and have each case override only the field it exercises, so the case reads as the one thing that differs. Keep the values a case's assertion depends on visible in the case itself; a test whose inputs hide in shared setup can't be read on its own. Copied setup blocks make up the bulk of most test diffs.

### 12. Assertions pin exact values

Assert the value the behavior produces, not merely that a value exists. A loose matcher stays green on a wrong-but-present value, which the Litmus test cannot catch, because it only proves the test fails once the logic is gone.

Replace each with an exact check or a deterministic signal:
- a sole `toBeDefined()` / `toBeTruthy()` / `!== undefined`
- `expect.any(X)` where the value is pinnable
- `toHaveLength(N)` or a lone `toContain` with no check of which items
- a bare `toThrow()` with no error type or message
- a golden-file or snapshot assertion added purely to capture current behavior
- a sleep-based wait where a deterministic signal (fake timers, a seeded RNG) would do

### 13. Prune redundancy in the test files you touch

Scope: authoring the paired test during `/geniro:implement` Phase 2. Every other reader of this doctrine flags a redundant test instead — never deletes one outside this step.

When a change edits a test file:
- **Delete** a pre-existing case only when a kept case activates the same guard or branch as the pre-existing case and asserts the same outcome — true redundancy, not mere similarity.
- **Fold** a run of near-identical pre-existing cases the change extends into one parameterized table (§10) instead of deleting them — each case survives as a row.

Each deletion passes §Test deletions in the diff first — its cause path must stay pinned by a surviving test. Record each deletion with the surviving test that pins it, and each folded case with the row it became; a reviewer reads a deleted test as a coverage regression until shown otherwise. Test files the change does not otherwise edit stay untouched — this is cleanup in passing, not a suite refactor.

## What to look for

Judge coverage per behavior the diff changed, not by test count, a coverage percentage, or the presence of every test layer.

- **A new or changed behavior — its main path included — with no test that reddens on revert** — the gap that matters.
- **A test that cannot fail, or passes a wrong implementation** — §Litmus test and §12 Assertions pin exact values.
- **Async correctness inside the test itself** — a missing `await`, an unhandled rejection, or a real timer/sleep standing in for a deterministic signal makes the test vacuous or flaky. Nondeterminism from execution order, wall-clock time, or environment is the same defect.
- **Tests coupled to implementation** — §1–§4 above.
- **Redundancy and over-testing** — a case that duplicates coverage another case already provides, at any layer or granularity: §8–§11 and §Redundancy.
- **A skipped, disabled, or focused test the diff adds or leaves in** (`.skip`, `xit`, `xdescribe`, `pending`, `.only`, `fit`, `fdescribe`) — silently drops coverage without looking like a deletion.
- **A test double whose shape diverges from the real collaborator** — a mock exposing an API, data shape, or error the real interface doesn't, certifying a path production never runs.

## Common false positives

1. **Intentional coverage gaps** — Some code doesn't need comprehensive testing
- Glue code without logic might not need tests
- UI display code often undertested (acceptable)
- Check if code has significant logic

2. **Mocking is correct** — Using mocks isn't always a sign of bad design
- External services should be mocked in unit tests
- Real integration tests can use real services
- Check if mix of unit and integration tests exists

3. **Coverage is behavioral, not a percentage** — Judge coverage per behavior the diff changed, not against a coverage-percentage target
- A behavior whose test reddens on revert is covered, whatever the percentage

4. **Framework defaults** — Some frameworks handle testing automatically
- Rails/Django provide built-in test runners
- Some frameworks auto-test certain paths
- Check framework conventions

5. **Documented limitations** — Some edge cases might be known and accepted
- Documentation or issues might address known gaps
- Some edge cases might be "out of scope"
- Check comments and issue tracker

6. **Test parameterization** — Multiple test cases might use compact syntax
- Parameterized tests cover many cases concisely
- One "test" function might test many inputs
- Count test cases, not test functions

7. **Input the changed code doesn't branch on** — A hypothetical edge input (null, empty, max value) the changed code does not branch on needs no test
- Trace whether the changed lines actually contain a conditional on that input
- An untouched null-check elsewhere in the file is not this diff's gap

8. **Behavior already pinned elsewhere** — whether a match counts as confirmed coverage, and what it doesn't, is §Spec-coverage traceability's confirmation gate

## Litmus test (the deletion test)

For every test, ask: **"If I deleted the core logic this test covers, would the test still pass?"**

If the answer is yes, the test is worthless — it's testing mocks, trivial wiring, or nothing at all.

**How to apply:**
1. For each test touching changed code, mentally (or actually) remove the implementation
2. Would the test fail? If not, the test needs strengthening
3. Common causes of false-passing tests:
- Test only asserts that a mock was called (not that the result is correct)
- Test asserts on default/initial values that don't change
- Test has no assertions at all (just runs without error)
- Test imports the module but doesn't exercise the changed code path

**Red flags:**
- Tests with 0 assertions
- Tests that only verify mock call counts
- Tests where removing `expect` lines doesn't cause failure
- "Smoke tests" that import a module and assert `!== undefined`

## Tests of the scenery — never author, flag for removal

A test earns its maintenance cost only by pinning behavior someone could regress. A test that pins the scenery — detail with no behavioral contract — breaks on every refactor and catches nothing:

- **Presentational details**: CSS class names, inline styles, static markup structure, exact copy strings (unless the copy IS the spec'd behavior — e.g. a legally-required disclosure).
- **The framework or library itself**: that React renders a component, that the router routes, that the ORM maps a column — the dependency's own suite covers that.
- **Trivial wiring**: getters/setters with no logic, constant re-exports, pass-through calls.
- **Duplicates of existing suite coverage**: a new test whose every catchable revert already reddens a surviving test at any layer (§Redundancy). The F→P invariant's first-run-green signal usually exposes these.

Never author such a test. When the diff ADDS one, flag it with an explicit removal recommendation — deleting a scenery test is a quality improvement, not a coverage loss (confirm with the Deletion Test / cause-path comparison first). Severity LOW; raise to MEDIUM when the scenery test is the ONLY test on a spec-required behavior, because then the real finding is the coverage gap it masks.

## Assertion completeness & spec coverage

The Deletion Test above catches a test that asserts *nothing real*. This section catches the subtler failures: a test whose expected value *is derived the way the implementation derives it*, a test that asserts *less than it claims*, a behavior the spec required that *no test covers*, and *a new test that pins the same thing an existing test already does*. Run these checks on every newly-authored or modified test.

### Independent expected values

A test whose expected value is recomputed the way the implementation computes it passes by construction — it agrees with any implementation that shares the algorithm, including a wrong one — and the Deletion Test does not catch it. Expected values come from an independent source of truth: a known-good literal, a hand-worked example, or the spec.

- **Bad**: `expect(calculateTotal(items)).toBe(items.reduce((s, i) => s + i.price, 0))` — the assertion re-derives the total with the production algorithm; both sides drift together.
- **Bad**: a snapshot or fixture generated by running the code under test; a constant asserted against the same imported constant.
- **Good**: `expect(calculateTotal([{price: 19.99}, {price: 22.51}])).toBe(42.50)` — the literal comes from a worked example, so a wrong algorithm produces a visible mismatch.

**Red flag:** the test body imports or re-implements the production algorithm to derive `expected`.

### Claimed scope vs asserted scope

A test's name, description, and comments are a promise about what it verifies. When the promise names two or more behaviors but the assertions exercise only one, the test gives false confidence — it reads as covering X and Y, but a regression in Y ships green.

- For each new/changed test, list the behaviors its name + description claim (`processes_and_validates_order` claims processing AND validation; `returns_401_and_logs_attempt` claims the status AND the log).
- Confirm at least one assertion exercises each claimed behavior. An assertion on the processing result with none on the validation path is a claimed-vs-asserted mismatch.
- Flag when the assertions cover a strict subset of the behaviors the name/description enumerates. The fix is to add the missing assertion OR narrow the name to match what the test actually checks — never leave the name over-promising.

**Red flags:**
- Test named for multiple behaviors (`and`, `then`, commas, `+`) with assertions for only one.
- A docstring/comment listing N expectations; fewer than N assertions in the body.
- Assertion count lower than the number of distinct outcomes the test sets up in its Arrange phase.

### Spec-coverage traceability

§What to look for scans for tests of changed *code paths*. This check looks for tests of *required behaviors* — the gap a code-path scan misses, because the spec can require a behavior the diff never branched on.

When a spec / plan is in context (spec.md section 9 Validation criteria, section 2 In-Scope behaviors, or the section-11 Done Condition; or a PR/plan acceptance-criteria list), map each enumerated behavior to a covering test — scoped to the whole suite, not only the tests this run touched. Apply the keyword-anchor traceability mechanism, confirmation gate included, from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` §"4. Tests for stated acceptance criteria".

- A keyword match is a lead, not coverage, and is scoped to the case it lands in, not the file — an unchanged case still counts as unchanged when it sits in a file the diff otherwise edits. Cite a confirmed match (per §4's gate) as a dimension-summary note (`file:line`) — no finding exists for a covered criterion. Behavior the diff introduces or changes needs a new or modified test; flag it when none exists.
- Severity tracks the criterion's blast radius (critical-path behavior → HIGH; routine → MEDIUM).
- When no spec/plan is in context (inline-task runs), this check is a silent no-op — there is no enumerated behavior set to map against.
- A section-11 outcome clause naming a production measurement and a window ("the dashboard metric shows p95 under 400ms, one week after rollout") is not a behavior a test can cover — drop it from the mapping instead of flagging it uncovered. Its enabling artifact stays in scope: where the clause depends on instrumentation the run added, the test for that emission is mappable and missing it is a finding. Same line `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` §10 draws.

**Red flag:** a behavior the spec lists as in-scope or as a Done-Condition / acceptance criterion, with no test — new, modified, or a confirmed pre-existing match — anywhere in the suite that covers it.

### Redundancy

The Inverse Deletion Test below guards *deleted* tests from silent coverage loss. This check guards the opposite direction: a new or changed test that pins a cause path some other test — a sibling this run adds, or a pre-existing test at any layer — already pins. The added test then costs maintenance without adding coverage.

- Compare each new or changed test against (a) sibling tests this run adds, and (b) the existing suite at any layer covering the same behavior — search test files of every layer by the behavior's anchors (entity, endpoint, function names), not only the file the diff touched.
- Redundant means every revert / cause path the test catches is already caught by another test. Outcome match or line overlap alone is not redundancy — the same cause-path doctrine as the Inverse Deletion Test below applies.
- A new test duplicating a sibling is dropped or folded in as a table row (§10); two new duplicates consolidate into one. A new test duplicating a PRE-EXISTING one is a different call — never a deletion from review: drop the new test, or flag the pre-existing one for a follow-up (§13 owns actually pruning it, and only when the diff already touches that file); a pre-existing duplicate in an untouched file is out of scope for this check.

**Red flag:** a new test with the same Arrange shape, the same activated branch, and the same assertion as a sibling or existing test — one is a copy that drifted.

## Test deletions in the diff (inverse deletion test)

The existing Litmus test (above) evaluates a TEST'S strength by mentally deleting the PRODUCTION code. Apply the inverse direction when the diff DELETES one or more tests: evaluate the test's intent by checking what scenario it pinned.

> **Overlap with regressions-criteria.md's test-coverage delta signal is deliberate.** That dimension also scans deleted tests, from the other end: it asks whether the production symbol a deleted test covered still survives (a coverage regression). This section asks whether the deleted test's *cause path* is still pinned by any surviving test. The two questions land on the same deletion and can produce the same finding, which is expected — Phase 3 dedup merges them. Do not suppress yours on the assumption the other dimension covers it: `/geniro:implement` Phase 3 spawns `tests` without `regressions`, so this section is the only owner of the deleted-test class there.

For every test removed by the diff (whole file deleted, OR an `it` / `test` / `describe` block removed from an existing file), ask:

**"What scenario was this test pinning that no surviving test covers?"**

The comparison is by **cause path**, NOT by **outcome**. Two tests that share the same assertion shape (e.g. `expect(result).toBeNull`) can pin radically different cause paths — outcome-match is a false-equivalence signal.

The pattern generalizes to any guard + race-condition combination where the same observable outcome can be reached through multiple causal paths — defensive-branch + happy-path that share a return value, retry/fallback that converges on the same final state as the primary path, two error handlers that produce the same error object via different internal sequences. The concrete example below is from one production incident; treat it as a shape, not a recipe.

### Cause-path examples (real shape; from prior incident)

| Test name | Outcome | Cause path being pinned |
|---|---|---|
| "should return null when the account has 2+ open orders (multi-order fail-closed)" | `expect(result).toBeNull` | The helper's `openOrderIds.length !== 1` guard fires; the history table is never consulted |
| "should return null when excludeOrderId equals the only open order (single-order unassign defense-in-depth)" | `expect(result).toBeNull` | The helper's `orderId === excludeOrderId` carve-out fires; the history table is never consulted; protects against DLQ replay / stale event.occurredAt |

Same outcome (`null`). Two different cause paths. Deleting either test as "duplicate of the other" silently loses coverage on the corresponding race condition.

### How to apply

1. **List every removed test** — from `git diff` output, identify each `-` line that opens an `it` / `test` / `describe` block OR every deleted test file.
2. **Read each removed test's body verbatim** — the deleted code is still in `git diff` output even after the diff applies; pull the test's setup (Arrange), invocation (Act), and assertions (Assert) into your review.
3. **Identify the cause path** — what specific code branch / guard / parameter value / state combination did the deleted test exercise? The cause path is rarely the assertion line; it's the Arrange phase + which guard/branch the Act phase activated.
4. **Search surviving tests for the same cause path** — grep the test directory for tests whose Arrange phase matches (same setup shape: same number of open records, same history-table state, same parameter set). If you find an outcome-matching test, verify it's also cause-path-matching by reading its Arrange phase.
5. **Flag as a finding if any deleted test's cause path is not pinned by a surviving test**:
- **HIGH** when the cause path protects a critical-path behavior (auth, payments, data writes, defense-in-depth guards against operational anomalies like DLQ replay / stale timestamps / partial-commit retries).
- **MEDIUM** when the cause path covers a non-critical-path branch the surviving tests miss.
- Not a finding when a surviving test's cause path AND outcome match the deleted test — record a one-line dimension-summary note naming the surviving test.

### Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "Both tests assert `null` — they're duplicates" | Outcome-match is necessary but not sufficient. Two `expect(x).toBeNull` tests can pin different cause paths. Check the Arrange phase. |
| "The implementer agent said it was a duplicate — they read the test" | Implementer agents have skin in the deletion (they wrote the diff). Reviewer's job is the independent check. Re-derive the cause-path comparison yourself. |
| "There's no surviving test for that cause path, but the production code now also lacks that branch — so there's nothing to test" | When BOTH a defensive branch AND its pinning test get removed together, the "nothing to test" reasoning is circular. The right question is: would a test fail if the defensive branch were restored under the same Arrange conditions? If yes, the removed test was real coverage and the cause path is now unpinned. |
| "The test name uses thread-local labels (Case 5, Bug A) so it's noise" | Test-name quality is orthogonal to cause-path coverage. A poorly-named test that pins a real cause path is still real coverage — rename it, don't delete it. |

### Litmus test for the inverse (the "would restoring the deletion fail any test?" check)

If the diff under review removes BOTH a defensive branch (in production code) AND a test that exercised it, the round-trip litmus is: would temporarily reverting JUST the production-code deletion (without restoring the test) cause any SURVIVING test to fail? If no test fails when the defensive branch is restored, the surviving suite has no pin for that branch — the deleted test was the only pin, and removing both together is a coverage regression that no test failure will surface.

This is the inverse of mutation testing: instead of mutating the code to see what tests fail, restore the deleted code to see what tests pass. Surviving tests must include the deleted test's cause-path coverage, or the deletion drops invisible work.

## Review checklist

- [ ] Litmus test: deleting core logic would cause test failure
- [ ] Every spec-required behavior (section 9 / Done Condition / acceptance criteria) has a covering test
- [ ] No new test duplicates a revert an existing or sibling test already catches

## Severity guidelines

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.

- **HIGH**: No tests for critical business logic; no error-handling tests on payment/auth/data-write paths; assertions test the wrong thing (false confidence) on a critical path; a test gap on a critical-path or high-blast-radius behavior — auth, payments, data writes/migrations, security validators, public API contracts, irreversible operations. Or: a test exists but its assertions are too loose to catch the regression it was added to prevent (deletion-test failure on critical code). This dim's ceiling is HIGH — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1's CRITICAL inclusion list has no coverage-gap class, and §2 caps a missing-test finding at MEDIUM/LOW; a critical-path coverage gap is this dim's own HIGH escalation, not a widening into CRITICAL.
- **MEDIUM**: a changed branch / guard / fallback on non-critical-path code that no test pins; loose assertions on non-critical code
- **LOW**: Style of tests, naming, organization, or minor coverage improvement on glue/wiring code; redundant, over-layered, or copy-pasted tests the diff adds

**Calibration rule:** When in doubt between HIGH and MEDIUM, default to MEDIUM. HIGH requires a specific blast-radius justification in the finding's "Why this matters" line. Routine "missing test for new behavior" findings are MEDIUM unless that behavior sits on a critical path.
