# Bugs review criteria


Find real defects: logic errors, null/undefined handling, boundary conditions, races, error handling, resource leaks.

## Common false positives

1. **Defensive coding** — Extra null checks aren't always wrong
- `if (obj && obj.field)` might be intentional for safety
- Check if same pattern is used consistently elsewhere

2. **Async complexity** — Async operations appear unsynchronized but may be intentional
- Check for explicit await statements
- Look for Promise.all/race patterns

3. **Flexible equality** — `==` used for deliberate type coercion
- Check context: `if (value == null)` is common for both null/undefined
- Only flag if type coercion causes actual bugs

4. **Intentional mutations** — Some objects are designed to be mutable
- Check for explicit mutable state comments
- Verify no unintended side effects

5. **Configuration-driven** — Behavior controlled by external config
- Check if variables come from config files
- Don't flag if properly validated at load time

6. **Legacy patterns** — Old code may have reasons for unusual patterns
- Check comments or git history
- Only flag if causes demonstrated bugs


## Severity guidelines

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.

- **CRITICAL** — Unbounded recursion on user input; auth-bypass via missing role check; SQL injection in a dynamic query; deadlock with a documented trigger; data-corruption write with no compensating action; infinite loop reachable from a public entry point; an unhandled real-world state on a reachable common path (empty input, concurrent double-submit) that causes data loss or a crash.
- **HIGH** — Race condition with a specific reachable scenario (e.g., two concurrent writes to the same row without a transaction); off-by-one in pagination when item count equals page size; null-dereference on a non-edge-case path; unhandled error path that leaks state or aborts a request mid-write; a masking default that hides a failure on a path where a downstream consumer acts on the fallback as if it were real data (e.g., `.catch(() => [])` feeding a count / filter / dispatch); a missing rollback that leaves a multi-step write half-applied; a missing real-world-state branch (empty / concurrent / partial-failure / dependency-down) with a cited reachable scenario where it yields a wrong result or aborts a flow.
- **MEDIUM** — Edge-case bug with low likelihood and a cited reachable scenario; incorrect-but-mitigated behavior where a downstream layer compensates; pre-existing bug surfaced by this PR's changes that does not make the bug worse; a swallowed error / dropped stack trace that only degrades diagnosability (failure still surfaces elsewhere); a missing timeout on a network/IO call where a hang is reachable but not on the hot path.
- **LOW** — Defensive-coding suggestions without a demonstrated defect ("add a null check here even though the caller always passes a value"); style suggestions on bug-adjacent code; documentation or PR-description nits about a bug area.
