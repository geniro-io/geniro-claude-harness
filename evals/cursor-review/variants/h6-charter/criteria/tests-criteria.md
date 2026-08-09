# Tests review criteria


Assess test coverage and quality for the changed behavior: missing cases, weak assertions, flaky patterns.

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


## Severity guidelines

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.

- **CRITICAL**: No tests for critical business logic; no error-handling tests on payment/auth/data-write paths; assertions test the wrong thing (false confidence) on a critical path
- **HIGH**: Test gap on a critical-path or high-blast-radius behavior — auth, payments, data writes/migrations, security validators, public API contracts, irreversible operations. Or: a test exists but its assertions are too weak to catch the regression it was added to prevent (deletion-test failure on critical code)
- **MEDIUM**: Routine coverage gap on modified code (new util, new helper, new branch); missing edge-case test for non-critical-path code; weak assertions on non-critical code; integration-test placement or organization issue; missing boundary test that wouldn't cause production impact
- **LOW**: Style of tests, naming, organization, or minor coverage improvement on glue/wiring code

**Calibration rule:** When in doubt between HIGH and MEDIUM, default to MEDIUM. HIGH requires a specific blast-radius justification in the finding's "Why this matters" line. Routine "missing test for new function" findings are MEDIUM unless that function is in a critical path.
