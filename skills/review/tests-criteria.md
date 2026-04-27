# Tests Review Criteria

Test coverage analysis, edge case handling, test quality, and critical path coverage assessment.

## What to Check

### 1. Coverage Gaps
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

### 2. Missing Edge Cases
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

### 3. Test Quality & Maintainability
- Brittle tests tied to implementation details
- Missing test documentation
- Unclear test purposes (vague test names)
- Difficult to understand test setup
- Flaky tests (non-deterministic)
- Heavy use of mocks/stubs (indicates design issues)

**How to detect:**
```bash
# Find vague test names
grep -n "test_.*\|it\s*(\s*'[^']*should.*\|fit\|fdescribe" test_file.js | grep -E "do|work|pass|test"
# Look for complex setup
grep -B10 "expect\|assert" test_file.js | grep -c "setup\|fixture\|mock"
# Find mocked dependencies
grep -n "jest.mock\|sinon.stub\|mock\|spy" test_file.js
```

**Red flags:**
- Test names: "test1", "shouldWork", "test_function"
- Thread-local labels in test names: "Bug A/B/C", "Hypothesis 1/2", "Test 1", "Case X", "Issue #N from this run" — these are specific but meaningless once the originating conversation ends; same red flag for comments inside the test
- Setup takes more lines than the actual test
- Many mocks/stubs per test (indicates tight coupling)
- Tests that fail intermittently
- Comments like "this is fragile" or "fix this test"

### 4. Async/Promise Testing
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
grep -n "\.then\|\.catch" test_file.js | grep -v ".catch"
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
- `.then()` without `.catch()` handling
- No timeout handling in async tests
- Tests that pass sometimes but fail others
- Missing error case tests for promises
- Event emitter / stream code with no corresponding test
- Callback-based async tested without done() or promisification

### 5. Integration Testing
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

### 6. Test Organization & Structure
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

### 7. Mocking & Dependencies
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

### 8. Critical Path Testing
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
- Payment logic with <10 test cases
- Auth code with no failure scenario tests
- Critical functions with 1-2 tests
- No tests for recovery from failure states
- Permission/authorization gaps in tests

## Output Format

```json
{
  "type": "test",
  "severity": "critical|high|medium",
  "title": "Test coverage or quality issue",
  "file": "path/to/file.js",
  "test_file": "path/to/test.js",
  "line_start": 42,
  "line_end": 48,
  "description": "Detailed description of test gap",
  "category": "coverage|edge_cases|quality|async|integration|organization|mocking|critical_path",
  "missing_tests": ["null input", "empty array", "timeout scenario"],
  "current_coverage": "What's currently tested",
  "recommendation": "What tests to add",
  "impact": "Risk if this isn't tested",
  "confidence": 88
}
```

## Common False Positives

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

## Stack-Agnostic Patterns

Works across languages/frameworks:
- Coverage analysis (tools available for all languages)
- Edge case patterns (language-agnostic)
- Async testing patterns (promise/callback/async)
- Integration test structure (all languages)
- Mocking patterns (all frameworks)
- Test organization (language-independent)

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
- Tests where removing `expect()` lines doesn't cause failure
- "Smoke tests" that import a module and assert `!== undefined`

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

## Severity Guidelines

- **CRITICAL**: No tests for critical business logic; no error-handling tests on payment/auth/data-write paths; assertions test the wrong thing (false confidence) on a critical path
- **HIGH**: Test gap on a critical-path or high-blast-radius behavior — auth, payments, data writes/migrations, security validators, public API contracts, irreversible operations. Or: a test exists but its assertions are too weak to catch the regression it was added to prevent (deletion-test failure on critical code)
- **MEDIUM**: Routine coverage gap on modified code (new util, new helper, new branch); missing edge-case test for non-critical-path code; weak assertions on non-critical code; integration-test placement or organization issue; missing boundary test that wouldn't cause production impact
- **LOW**: Style of tests, naming, organization, or minor coverage improvement on glue/wiring code

**Calibration rule:** When in doubt between HIGH and MEDIUM, default to MEDIUM. HIGH requires a specific blast-radius justification in the finding's "Why this matters" line. Routine "missing test for new function" findings are MEDIUM unless that function is in a critical path.
