# Tests review criteria

Test coverage analysis, edge case handling, test quality, and critical path coverage assessment.

## Contents

- Test Design Philosophy (canonical)
- What to Check
- Common false positives
- Litmus Test (The Deletion Test)
- Tests of the scenery — never author, flag for removal
- Assertion completeness & spec coverage
- Test Deletions in the Diff (Inverse Deletion Test)
- Review Checklist
- Severity Guidelines

---

## Test Design Philosophy (canonical)

This section is the canonical doctrine for what makes a test "good" in this codebase. It is read by every tests-dimension reviewer (`/geniro:review` Phase 2, `/geniro:implement` Phase 3 self-review, `/geniro:refactor` reviewer pass), the `adversarial-tester-agent` when authoring F→P tests (`/geniro:implement` Phase 3 self-review (Round 1), `/geniro:debug` Adversarial Mode), and the `/geniro:debug` reproduction-test author. Write the test according to these principles; review the test against them.

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
- Reproduction tests authored during `/geniro:debug` Phase 2
- F→P tests authored during `/geniro:debug` Adversarial Mode and `/geniro:review`'s Phase 4.3 test-confirmation gate

`/geniro:debug` Adversarial Mode and `/geniro:review`'s Phase 4.3 test-confirmation gate both enforce F→P with 3-run determinism checks; the `adversarial-tester-agent` deletes tests that pass on current code.

## What to Check

### 8. Coverage Gaps
- Missing tests for new/modified code paths
- No tests for error conditions
- Missing happy-path tests
- Untested edge cases and boundary conditions
- No tests for async/concurrent scenarios

**How to detect:**
```bash
# Find test files corresponding to changed files
ls tests/ | grep -i "auth\|login\|payment"
# Check if tests exist for modified code
for file in src/*.js; do [ ! -f "tests/$(basename "$file")" ] && echo "No test: $file"; done
# Look for test skips
grep -n "skip\|xit\|xdescribe\|pending" test_file.js
# Count assertions per test
grep -c "expect\|assert\|should" test_file.js
```

**Red flags:**
- New code with no corresponding tests
- Modified functions without updated tests
- Skipped tests in main branch
- Single assertion per test file
- Tests only covering success cases

### 9. Missing Edge Cases
- Null/undefined input handling
- Empty collections (arrays, objects, strings)
- Boundary values (0, -1, max_int, min_int)
- Negative/invalid inputs
- Very large inputs
- Concurrent/race condition scenarios
- State transitions edge cases

**How to detect:**
- Look at function parameters: are all edge cases tested?
- Check test names: do they mention edge cases?
- Count test cases per function (1-2 tests is likely insufficient)
- Look for parameterized/table-driven tests covering ranges
- Check for timeout/async race condition tests

**Red flags:**
- Only positive/happy-path tests
- No tests for `null`, `undefined`, `0`, `""`, `[]`
- No tests for concurrent calls
- Missing tests for error states
- No tests for state transitions

### 10. Test Quality & Maintainability
- Brittle tests tied to implementation details
- Missing test documentation
- Unclear test purposes (vague test names)
- Difficult to understand test setup
- Flaky tests (non-deterministic)
- Heavy use of mocks/stubs (indicates design issues)

**How to detect:**
```bash
# Find vague test names (whole-word vague markers; not a bare "test" which re-matches every test_ name)
grep -n "test_.*\|it\s*(\s*'[^']*should.*\|fit\|fdescribe" test_file.js | grep -wiE "do|work|works|pass|stuff|thing"
# Look for complex setup
grep -B10 "expect\|assert" test_file.js | grep -c "setup\|fixture\|mock"
# Find mocked dependencies
grep -n "jest.mock\|sinon.stub\|mock\|spy" test_file.js
```

**Red flags:**
- Test names: "test1", "shouldWork", "test_function"
- Thread-local labels in test names: "Bug A/B/C", "Hypothesis 1/2", "Test 1", "Case X", "Issue #N from this run", "regression from review run", "found by review-gate", "confirmed by this <skill> run" — these are specific but meaningless once the originating conversation ends; same red flag for comments inside the test
- Setup takes more lines than the actual test
- Many mocks/stubs per test (indicates tight coupling)
- Tests that fail intermittently
- Comments like "this is fragile" or "fix this test"

### 11. Async/Promise Testing
- Missing async/await in async tests
- Unhandled promise rejections in tests
- Not testing error cases in async code
- Missing timeout handling in async tests
- Race conditions in test execution
- Missing stream/event-based async patterns
- Callback-style async not converted to promise tests

**How to detect:**
```bash
# Find async tests without await
grep -n "async.*=>\|function.*async" test_file.js
grep -A5 "async.*=>" test_file.js | grep -v "await\|done\|return"
# Promise tests without .catch
grep -n "\.then\|\.catch" test_file.js | grep -v "\.catch("
# Tests with setTimeout
grep -n "setTimeout\|setInterval" test_file.js | grep -v "jest.useFakeTimers\|sinon.useFakeTimers"
# Find untested event emitters / streams
grep -n "on('data\|on('error\|on('end\|pipe(" src/*.js | while read line; do
fname=$(echo "$line" | cut -d: -f1 | xargs basename)
grep -q "$fname" tests/*.js || echo "No async stream test: $line"
done
# Find callback-style async without promise wrappers
grep -n "callback\|cb(" test_file.js | grep -v "promisify\|async\|await"
```

**Red flags:**
- Async test functions without `await`
- `.then` without `.catch` handling
- No timeout handling in async tests
- Tests that pass sometimes but fail others
- Missing error case tests for promises
- Event emitter / stream code with no corresponding test
- Callback-based async tested without done or promisification

### 12. Integration Testing
- No integration tests for critical paths
- Integration tests only testing happy paths
- No database/service integration tests
- Missing end-to-end scenario tests
- Integration tests too brittle or slow

**How to detect:**
- Look for test directory structure: are integration tests separate?
- Check if tests hit actual services or are mocked
- Find slow tests (might be integration)
- Look for setup/teardown of actual resources
- Check for database/API integration tests

**Red flags:**
- All tests are unit tests (no integration coverage)
- Integration tests skipped or disabled
- Critical APIs not tested with real backend
- Database operations only tested in isolation
- Missing end-to-end scenarios

### 13. Test Organization & Structure
- Tests grouped by file (not by functionality)
- No clear test suite organization
- Mixed unit and integration tests
- No setup/teardown or fixtures
- Inconsistent test structure across codebase

**How to detect:**
```bash
# Check test directory structure
find tests/ -type f | head -20
# Look for setup/teardown
grep -n "beforeEach\|afterEach\|setUp\|tearDown" test_file.js
# Count test suites
grep -c "describe\|TestCase\|class.*Test" test_file.js
# Look for fixtures or test data
grep -n "fixture\|TestData\|MOCK_\|test_" test_file.js
```

**Red flags:**
- Test directory mirrors source structure but nothing else
- No clear organization of test suites
- `beforeEach` has massive setup (100+ lines)
- Inconsistent test patterns across files
- Tests importing from many different modules

### 14. Mocking & Dependencies
- Over-mocking that defeats testing purpose
- Missing real integration tests (everything mocked)
- Mock objects not verifying behavior
- Mocks out of sync with real implementation
- Test doubles not matching real API

**How to detect:**
- Count mocks per test (more than 3-4 is a smell)
- Look for "happy-path-only" mocks
- Check if behavior verification exists
- Find tests that only mock everything
- Verify mocks match real interface

**Red flags:**
- Every dependency mocked
- Mocks that accept any arguments
- No assertion on mock calls/behavior
- Mocks with different API than real object
- Hard to understand what's being tested vs mocked

### 15. Critical Path Testing
- Core business logic not thoroughly tested
- Authentication/authorization paths undertested
- Payment/transaction logic not well covered
- Error recovery paths not tested
- User input validation paths not covered

**How to detect:**
- Identify critical paths in code
- Count test cases for each critical path
- Check if all branches in critical code are tested
- Look for error handling tests in critical functions
- Verify authorization checks are tested

**Red flags:**
- Payment logic with no failure-scenario or boundary tests (only happy-path coverage)
- Auth code with no failure scenario tests
- Critical functions with 1-2 tests
- No tests for recovery from failure states
- Permission/authorization gaps in tests

## Common false positives

1. **Intentional coverage gaps** — Some code doesn't need comprehensive testing
- Glue code without logic might not need tests
- UI display code often undertested (acceptable)
- Check if code has significant logic

2. **Mocking is correct** — Using mocks isn't always a sign of bad design
- External services should be mocked in unit tests
- Real integration tests can use real services
- Check if mix of unit and integration tests exists

3. **Pragmatic testing** — Perfect test coverage is diminishing returns
- 80% coverage is often sufficient
- Testing all branches can be overkill
- Check what coverage threshold is for project

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

## Litmus Test (The Deletion Test)

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
- **Duplicates of existing suite coverage**: a new test whose cause path AND outcome are already pinned by a surviving test at the same seam — the same pairwise rule as §Redundancy among newly-authored tests, extended to the existing suite. The F→P invariant's first-run-green signal usually exposes these.

Never author such a test. When the diff ADDS one, flag it with an explicit removal recommendation — deleting a scenery test is a quality improvement, not a coverage loss (confirm with the Deletion Test / cause-path comparison first). Severity LOW; raise to MEDIUM when the scenery test is the ONLY test on a spec-required behavior, because then the real finding is the coverage gap it masks.

## Assertion completeness & spec coverage

The Deletion Test above catches a test that asserts *nothing real*. This section catches the subtler failures: a test whose expected value *is derived the way the implementation derives it*, a test that asserts *less than it claims*, a behavior the spec required that *no test covers*, and *two new tests that pin the same thing*. Run these checks on every newly-authored or modified test.

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

The coverage checks in §8 look for tests of changed *code paths*. This check looks for tests of *required behaviors* — the gap a code-path scan misses, because the spec can require a behavior the diff never branched on.

When a spec / plan is in context (spec.md section 9 Validation criteria, section 2 In-Scope behaviors, or the section-11 Done Condition; or a PR/plan acceptance-criteria list), map each enumerated behavior to a covering test. Apply the keyword-anchor traceability mechanism from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` §"4. Tests for stated acceptance criteria" (derive 2–4 anchors per criterion, grep the run's test files, flag any criterion whose anchors appear in no test) — scoped to the tests authored or changed in this run.

- Flag any spec-enumerated behavior with no covering assertion. Severity tracks the criterion's blast radius (critical-path behavior → HIGH; routine → MEDIUM).
- When no spec/plan is in context (inline-task runs), this check is a silent no-op — there is no enumerated behavior set to map against.

**Red flag:** a behavior the spec lists as in-scope or as a Done-Condition / acceptance criterion, with no test in the diff that references it.

### Redundancy among newly-authored tests

The Inverse Deletion Test below guards *deleted* tests from silent coverage loss. The forward complement: two tests *added in the same run* that pin the same cause path AND the same outcome are redundant — the second adds maintenance cost without adding coverage.

- Compare new tests pairwise by cause path (the Arrange setup + the branch/guard the Act activates), not by assertion shape alone — the same outcome via different cause paths is NOT redundant (see the Inverse Deletion Test's cause-path doctrine below).
- Flag as redundant only when cause path AND outcome both match. Recommend consolidating into one test; never silently delete — the author may have intended a parameterized case.

**Red flag:** two new tests with identical Arrange shape, the same activated branch, and the same assertion — one is a copy that drifted.

## Test Deletions in the Diff (Inverse Deletion Test)

The existing Litmus Test (above) evaluates a TEST'S strength by mentally deleting the PRODUCTION code. Apply the inverse direction when the diff DELETES one or more tests: evaluate the test's intent by checking what scenario it pinned.

For every test removed by the diff (whole file deleted, OR an `it` / `test` / `describe` block removed from an existing file), ask:

**"What scenario was this test pinning that no surviving test covers?"**

The comparison is by **cause path**, NOT by **outcome**. Two tests that share the same assertion shape (e.g. `expect(result).toBeNull`) can pin radically different cause paths — outcome-match is a false-equivalence signal.

The pattern generalizes to any guard + race-condition combination where the same observable outcome can be reached through multiple causal paths — defensive-branch + happy-path that share a return value, retry/fallback that converges on the same final state as the primary path, two error handlers that produce the same error object via different internal sequences. The concrete example below is from one production incident; treat it as a shape, not a recipe.

### Cause-path examples (real shape; from prior incident)

| Test name | Outcome | Cause path being pinned |
|---|---|---|
| "should return null when beneficiary has 2+ open cases (multi-case fail-closed)" | `expect(result).toBeNull` | The helper's `openCaseIds.length !== 1` guard fires; SCD2 is never consulted |
| "should return null when excludeCaseId equals the only open case (single-case unassign defense-in-depth)" | `expect(result).toBeNull` | The helper's `caseId === excludeCaseId` carve-out fires; SCD2 is never consulted; protects against DLQ replay / stale event.occurredAt |

Same outcome (`null`). Two different cause paths. Deleting either test as "duplicate of the other" silently loses coverage on the corresponding race condition.

### How to apply

1. **List every removed test** — from `git diff` output, identify each `-` line that opens an `it` / `test` / `describe` block OR every deleted test file.
2. **Read each removed test's body verbatim** — the deleted code is still in `git diff` output even after the diff applies; pull the test's setup (Arrange), invocation (Act), and assertions (Assert) into your review.
3. **Identify the cause path** — what specific code branch / guard / parameter value / state combination did the deleted test exercise? The cause path is rarely the assertion line; it's the Arrange phase + which guard/branch the Act phase activated.
4. **Search surviving tests for the same cause path** — grep the test directory for tests whose Arrange phase matches (same setup shape: same number of open cases, same SCD2 state, same parameter set). If you find an outcome-matching test, verify it's also cause-path-matching by reading its Arrange phase.
5. **Flag as a finding if any deleted test's cause path is not pinned by a surviving test**:
- **HIGH** when the cause path protects a critical-path behavior (auth, payments, data writes, defense-in-depth guards against operational anomalies like DLQ replay / stale timestamps / partial-commit retries).
- **MEDIUM** when the cause path covers a non-critical-path branch the surviving tests miss.
- **LOW** when the deleted test was genuinely redundant (cause-path AND outcome match a surviving test) — note as informational confirmation.

### Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "Both tests assert `null` — they're duplicates" | Outcome-match is necessary but not sufficient. Two `expect(x).toBeNull` tests can pin different cause paths. Check the Arrange phase. |
| "The implementer agent said it was a duplicate — they read the test" | Implementer agents have skin in the deletion (they wrote the diff). Reviewer's job is the independent check. Re-derive the cause-path comparison yourself. |
| "There's no surviving test for that cause path, but the production code now also lacks that branch — so there's nothing to test" | When BOTH a defensive branch AND its pinning test get removed together, the "nothing to test" reasoning is circular. The right question is: would a test fail if the defensive branch were restored under the same Arrange conditions? If yes, the removed test was real coverage and the cause path is now unpinned. |
| "The test name uses thread-local labels (Case 5, Bug A) so it's noise" | Test-name quality is orthogonal to cause-path coverage. A poorly-named test that pins a real cause path is still real coverage — rename it, don't delete it. |

### Litmus Test for the Inverse (the "would restoring the deletion fail any test?" check)

If the diff under review removes BOTH a defensive branch (in production code) AND a test that exercised it, the round-trip litmus is: would temporarily reverting JUST the production-code deletion (without restoring the test) cause any SURVIVING test to fail? If no test fails when the defensive branch is restored, the surviving suite has no pin for that branch — the deleted test was the only pin, and removing both together is a coverage regression that no test failure will surface.

This is the inverse of mutation testing: instead of mutating the code to see what tests fail, restore the deleted code to see what tests pass. Surviving tests must include the deleted test's cause-path coverage, or the deletion drops invisible work.

## Review Checklist

- [ ] New/modified code has corresponding tests
- [ ] Tests cover happy path and error cases
- [ ] Edge cases tested (null, empty, boundaries)
- [ ] Async code tested with proper await/then (including streams, events, callbacks)
- [ ] Integration tests exist for critical paths
- [ ] Test organization is clear and consistent
- [ ] Mocking is appropriate (not overused)
- [ ] Critical paths have comprehensive coverage
- [ ] Flaky tests are identified and fixed
- [ ] Test setup is clear and maintainable
- [ ] Litmus test: deleting core logic would cause test failure
- [ ] Each test asserts everything its name/description claims (no "tests X and Y" with only X asserted)
- [ ] Expected values are independent of the implementation (literal / worked example / spec — not re-derived by the production algorithm)
- [ ] Every spec-required behavior (section 9 / Done Condition / acceptance criteria) has a covering test
- [ ] No two newly-authored tests pin the same cause path and outcome
- [ ] No new test pins scenery (presentational detail, framework behavior, trivial wiring) or duplicates existing suite coverage — such additions are flagged for removal

## Severity Guidelines

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.

- **CRITICAL**: No tests for critical business logic; no error-handling tests on payment/auth/data-write paths; assertions test the wrong thing (false confidence) on a critical path
- **HIGH**: Test gap on a critical-path or high-blast-radius behavior — auth, payments, data writes/migrations, security validators, public API contracts, irreversible operations. Or: a test exists but its assertions are too weak to catch the regression it was added to prevent (deletion-test failure on critical code)
- **MEDIUM**: Routine coverage gap on modified code (new util, new helper, new branch); missing edge-case test for non-critical-path code; weak assertions on non-critical code; integration-test placement or organization issue; missing boundary test that wouldn't cause production impact
- **LOW**: Style of tests, naming, organization, or minor coverage improvement on glue/wiring code

**Calibration rule:** When in doubt between HIGH and MEDIUM, default to MEDIUM. HIGH requires a specific blast-radius justification in the finding's "Why this matters" line. Routine "missing test for new function" findings are MEDIUM unless that function is in a critical path.
