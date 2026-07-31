# Bugs review criteria

Logic errors, null/undefined checks, boundary conditions, numeric precision, state management, and type safety issues.

## Contents

- What to Check
- Common false positives
- Cross-PR API Conflicts (peer-PR context)
- Review Checklist
- Severity Guidelines

---

## What to Check

### 1. Null/Undefined Handling
- Variables used without null checks before property access
- Optional chaining `?.` or null coalescing `??` missing
- Conditional checks that don't cover all null cases
- Destructuring assignments without defaults
- Array/object indexing without length/existence check

**How to detect:**
```bash
# Indexing with no length/existence guard on the line
grep -n "\[[0-9]\+\]" file.js | grep -v "length\|size"
```

**Common patterns:**
- `obj.field` without `obj` null check
- `array[0]` without `array.length > 0`
- `config.setting` where config could be undefined

### 2. Off-By-One Errors
- Loop conditions: `i < array.length` vs `i <= array.length`
- Range checks: inclusive vs exclusive boundaries
- Substring positions: start/end indices
- Pagination: limit/offset calculations
- Timeout/delay calculations

**How to detect:**
```bash
# Loop patterns
grep -nE "for\s*\(\s*.*\s*(<=|>=|<|>|==)" file.js
# Range validation
grep -n "indexOf\|slice\|substring" file.js
```

### 3. State Management Issues
- Async state updates without synchronization
- Race conditions in concurrent operations
- State mutations without immutability
- Missing state cleanup/disposal
- Stale closures capturing old state

**How to detect:**
- Look for multiple `setState` calls in same function
- Find async operations modifying shared state
- Identify event listeners/subscriptions without cleanup
- Check for shared mutable objects

### 4. Type Safety Issues
- Type mismatches in comparisons (loose `==` for type-dependent logic)
- Implicit type coercions causing bugs
- Missing type validation for external inputs
- Unsafe array/object destructuring
- Return type mismatches

**How to detect:**
```bash
# Loose equality — the character classes exclude `===` and `!==`; a `grep -v "==="` filter keeps every `!==`
grep -nE "[^=!<>]==[^=]|[^!]!=[^=]" file.js
# Type operations on variables
grep -n "typeof\|instanceof" file.js | grep -v "if\|assert"
```

### 5. Error Handling Gaps
- Try-catch blocks without finally/cleanup
- Errors silently caught and ignored
- Promise rejections not handled
- Callback errors not checked before use
- Missing error propagation
- Fire-and-forget async call — a promise neither awaited nor `.catch`'d, so its rejection vanishes, ordering breaks, or a "done" signal fires before the work finishes

**How to detect:**
- Find `try` blocks followed by empty catch
- Look for unhandled Promise chains
- Check async functions for `await` without error context
- Identify callbacks not checking `err` parameter
- Find async calls used as bare statements with no `await` / `.then` / `.catch` / `void` (floating promises)

### 5.5. Silent Failure & Dangerous Fallback

Distinct from §5 (errors caught but not propagated): here the error path RUNS and returns a plausible-looking value, so the failure is invisible to the caller and downstream code proceeds on bad data.

- **Masking defaults** — returning `[]` / `null` / `0` / a default object on the error branch where the caller cannot distinguish "no data" from "the operation failed". A downstream filter / count / sort then treats the failure as legitimately empty.
- **Swallowing fallback handlers** — `.catch(() => [])` / `.catch(() => {})` / `.catch(() => null)` on a Promise; a `try/except` whose handler returns a fallback without logging or re-raising.
- **Catch-all that drops the exception** — bare `except: pass` (Python), `catch (e) {}` that neither logs nor rethrows, `rescue => e` with an empty body, `recover()` (Go) that discards the panic.
- **Lost or suppressed stack traces** — re-throwing a new error without chaining the original (`throw new Error("failed")` dropping `cause`), logging only `err.message` without the trace, catching and re-raising a different type that loses the original.
- **Missing timeouts** — a `fetch` / HTTP client / DB query / socket read with no timeout, so a hung dependency stalls the caller indefinitely instead of failing fast.
- **Missing rollback / cleanup on partial failure** — a multi-step write (transaction, file move, batch insert) that fails midway and leaves the system in a half-applied state because no rollback / compensating action runs.

**How to detect:**
```bash
# Swallowing fallback handlers
grep -nE "\.catch\(\s*\(\s*\)?\s*=>\s*(\[\]|null|\{\}|undefined)" file.js
# Catch-all that drops the exception
grep -nE "except\s*:\s*pass|except\s+Exception\s*:\s*pass" file.py
grep -nE "catch\s*\([^)]*\)\s*\{\s*\}" file.js
# Default-on-error returns inside catch/except
grep -nA3 "catch\|except" file.js | grep -E "return\s*(\[\]|null|0|\{\})"
# Network/IO calls — check for an accompanying timeout option
grep -nE "fetch\(|axios\.|requests\.(get|post)|http\.(get|request)" file.js | grep -v "timeout\|signal"
```

**Red flags:**
- An error branch returns the same shape as success, so the caller has no way to detect the failure
- `.catch` / `except` body that neither logs, rethrows, nor records the failure
- A network or IO call with no timeout in a request-handling path
- A transaction or multi-step mutation with a failure path but no rollback

### 6. Logic Errors
- Inverted conditionals (`if (!condition)` when should be `if (condition)`)
- Wrong operator used (`&&` instead of `||`, `+` instead of `*`)
- Unreachable code after return/break/throw
- Duplicate/contradictory conditions
- Infinite loops or missing loop termination
- Missing `else` / `default` branch — a conditional or `switch` that silently does nothing on the unmatched case where it should act
- Non-exhaustive `switch` / `match` over an enum or union — a variant added elsewhere falls through unhandled
- Unhandled state — a status / mode / state-machine value with no branch (the "none of these" case)
- Asymmetric guard — handles case X but silently ignores the complementary case Y (checks `> max` but not `< min`)

**How to detect:**
```bash
# Unreachable code — a statement (not a closing brace or comment) immediately after return/break/throw/continue
awk 'prev ~ /^[[:space:]]*(return|break|throw|continue)[^;]*;[[:space:]]*$/ && NF && $0 !~ /^[[:space:]]*([})\]]|\/\/|\/\*|\*|case |default|else|elif|when |catch|finally)/ {print NR": "$0} {prev=$0}' file.js
# Switch/match — read each hit's arms and confirm a default / catch-all exists
grep -nE "switch\s*\(|\bmatch\b" file.js
```
Inverted conditionals and wrong operators have no grep shape — `if (!x) return` is the correct guard idiom far more often than it is a defect, so read the condition against what the branch does.

### 7. Resource Leaks
- File handles not closed
- Database connections not released
- Memory references not cleaned up
- Event listeners registered but not removed
- Timers not cleared
- HTTP connections / sockets not destroyed
- Child processes not killed on parent exit
- Temporary files not cleaned up

**How to detect:**
```bash
# File handles: open without close
grep -n "open\|createReadStream\|createWriteStream" file.js | grep -v "close\|destroy\|end"
# Event listeners without cleanup
grep -n "\.on(\|\.addEventListener(" file.js
grep -n "\.off(\|\.removeListener\|\.removeEventListener(" file.js
# Compare counts — more on than off is suspicious
# Timers without clear
grep -n "setTimeout\|setInterval" file.js | grep -v "clearTimeout\|clearInterval"
# Database connections
grep -n "connect\|createPool\|getConnection" file.js | grep -v "release\|end\|close\|destroy"
# Child processes
grep -n "spawn\|exec\|fork" file.js | grep -v "kill\|close\|exit"
# Temp files
grep -n "mktemp\|tmpfile\|createTempFile\|tmp\." file.js | grep -v "unlink\|remove\|cleanup\|rimraf"
```

- Look for `open` without `close` in same scope
- Find `on` without `off` or `removeListener`
- Check `setTimeout/setInterval` without `clear`
- Identify subscriptions without unsubscribe
- Look for connection pools without release/destroy in finally blocks
- Check child processes spawned without kill-on-exit handlers

### 8. Boundary Conditions
- Empty array/object handling
- Single-element edge cases
- Maximum/minimum value limits
- Negative number handling
- Division by zero
- String edge cases — empty, very long, leading/trailing whitespace, unicode / multibyte / emoji
- Time / date edge cases — timezone & DST boundaries, leap year, epoch overflow, month/day rollover

**How to detect:**
- Look for operations on `array[0]` without length check
- Find math operations that could have zero denominator
- Check boundary value comparisons

### 8.5. Numeric Precision & Floating-Point

Distinct from §8 (which flags missing bounds / limits): here the arithmetic itself is lossy or unstable, so the code runs and returns a plausible-but-wrong number. Floating-point defects are silent — no exception, just a value that is slightly (or catastrophically) off — so they have to be caught at the pattern level rather than by a thrown error.

- **Exact-equality on floats** — `==` / `!=` (or a `>` / `<` threshold that assumes an exact value) on a computed float. `0.1 + 0.2 == 0.3` is false; float comparisons need a tolerance / epsilon, not equality.
- **Accumulated rounding error** — summing or multiplying floats in a loop, a repeated `+=` running total, an iterative numerical method. Per-step error compounds and the result drifts from the mathematically-correct value.
- **Money / currency as a binary float** — amounts stored or computed in a float (`price * quantity`, tax, interest) instead of integer minor units (cents) or a decimal type. Produces off-by-a-cent rounding that fails reconciliation.
- **Lossy int <-> float coercion** — a large integer (ID, timestamp, counter) flowing through a float that cannot represent it exactly (an IEEE-754 double / JS `Number` loses integer precision above 2^53); integer-division truncation where a fraction was intended (or a fraction where integer math was intended).
- **NaN / Infinity propagation** — an unchecked division, `0/0`, `log` / `sqrt` of a negative, or a failed numeric parse yields `NaN` / `Infinity` that flows downstream silently. `NaN` compares false to everything including itself, so a guard like `if (x > 0)` neither catches nor routes it — it slips through every branch.
- **Unit / scale confusion** — mixing values of different unit or magnitude in one expression (ms vs s, bytes vs KiB, percent vs fraction): the arithmetic is precise but the quantity is wrong.

**How to detect:**
```bash
# Exact equality against a float literal (often a computed value)
grep -nE "(==|!=)\s*-?[0-9]+\.[0-9]+" file.js
# Float arithmetic on money-named variables
grep -nE "(price|amount|total|cost|balance|tax|rate|cents?)\b.*[-*/+]" file.js
# Numeric parse / coercion of external input used without a NaN/Infinity guard
grep -nE "parseFloat|parseInt|Number\(" file.js | grep -viE "isNaN|isFinite|Number\.isInteger|toFixed"
```

**Red flags:**
- A float compared with `==` / `!=` where one side is the result of arithmetic
- Currency or financial math in a binary float type rather than integer cents / a decimal library
- A division, `parseFloat`, or external numeric input whose result feeds a comparison or index with no `isNaN` / `isFinite` check
- A 64-bit ID or high-resolution timestamp passed through a language's default float number type

Severity by impact: HIGH when the wrong number drives money, a security / authz threshold, or persisted data (currency-as-float in a billing path; a lost-precision ID that collides). MEDIUM for a float exact-equality or NaN-propagation bug with a cited reachable input. LOW for a precision concern with no demonstrated wrong output. Tag `[FIX-NOW]` when the correct fix is mechanical (epsilon compare, integer cents, `isNaN` guard); `[PRODUCT-DECISION]` only when the acceptable tolerance is itself a judgment call.

### 9. Functional completeness — real-world states the change must handle

Distinct from the checks above (which flag wrong or unsafe code that is PRESENT): this lens flags handling that is ABSENT but that the change needs in order to work in real use. The question is not "does the diff match the spec" — that is the spec-compliance dimension, which deliberately never invents requirements. It is "given what this change is for, is there a real input or state it will actually hit that it silently mishandles?"

Walk the change's purpose against the states a working version encounters:
- **Empty / no-result** — zero rows, empty list, no search hits. Handled, or does it index `[0]`, divide, or render nothing where something is expected?
- **Zero / one / many** — the single-element and large-N cases of what the change iterates, paginates, or batches (and its interaction with an existing limit / page size / cursor).
- **First-run / uninitialized** — no prior record, missing config, a table or cache that does not exist yet.
- **Concurrent access** — two requests on the same resource (double-submit, two edits to one row, a retry firing while the first is in flight) with no lock, version check, or idempotency key.
- **Partial failure mid-flow** — one step of a multi-step operation fails; is there recovery, or is the resource left half-updated?
- **Dependency unavailable** — the called service times out, errors, or is offline; does the change degrade, or hang / crash?
- **Auth / session expiry mid-flow** — a long operation whose credential expires partway through.

**The bar that keeps this from becoming noise:** a completeness finding is valid ONLY when you can name a concrete, reachable input or scenario under the current configuration where the missing handling produces a wrong result, a crash, data loss, or a stuck state — name it the way an Evidence Block names a triggering input. A merely-theoretical "you didn't handle every case" is NOT a finding; it would be correctly refuted at verification for lacking a reachable failure path. Cite the code path that hits the unhandled state and the input that reaches it.

**How to detect:**
- Read the change's entry points; for each input it consumes, ask what the empty / single / huge / concurrent / failed-dependency value is and trace where it flows.
- Walk the success path, then ask which state above has no corresponding branch.

**Finding shape:** "`<fn@file:line>` handles the populated case, but `<concrete reachable scenario>` reaches `<file:line>` with `<empty | concurrent | failed>` input, producing `<crash | wrong result | data loss | hang>`." Name why THIS change reaches the state (e.g. "this PR adds the endpoint that hits the empty-list path"), so the failure is a delta the PR introduces, not a pre-existing gap the verifier will refute. Severity by impact (this dimension may emit CRITICAL): CRITICAL on data loss or a crash on a reachable common path; HIGH / MEDIUM otherwise. Tag `[FIX-NOW]` when it is plainly a bug; `[PRODUCT-DECISION]` when whether to handle the case at all is a judgment call.

### 10. Root cause vs symptom — does the change fix the cause or hide it?

A change can make a failure stop appearing without making it stop happening. That is a defect in its own right, and a distinct one: the code is correct at the line it touches, the tests pass, and the same fault will surface again somewhere with less context around it. This lens reads the fix against the fault, not against the spec.

Shapes to look for:
- **A guard at the read site for a value the write site produced wrong** — the null check stops the crash and leaves the record wrong in the database.
- **A retry around a deterministic failure** — retrying something that fails the same way every time buys latency, not success.
- **A caught-and-logged exception where the caller needed to know** — the flow continues past a step that did not happen.
- **A default substituted for missing configuration** — the run proceeds under a value nobody chose, and the missing config stays missing.
- **A widened type, cast, or ignore directive where the value genuinely arrives in the wrong shape** — the checker stops objecting and the shape mismatch survives.
- **A tolerance loosened, timeout raised, or assertion relaxed to make a failing test pass** — the test now passes on the behavior it was written to reject.

**The bar that keeps this from becoming taste:** name the upstream site where the cause lives, with `file:line`, AND name what is still wrong once the change is in place — a value still incorrect, a state still unreachable, a caller still uninformed. Both halves are required. Without the upstream site it is a hunch about intent; without the surviving consequence it may simply be defense in depth, which is legitimate. "This looks like a band-aid" is not a finding.

Two cases that are NOT this: a deliberate boundary guard whose comment or contract says the upstream value is untrusted, and a stop-gap the change itself labels as temporary with a reference to the real fix. Both are choices, not misreadings.

**How to detect:**
- For each defensive addition in the diff, trace one hop upstream: where did the bad value or missed step originate, and does the diff touch that place?
- For each relaxed check, ask what the original check was asserting and whether that assertion is still true.

**Finding shape:** "`<file:line>` handles `<symptom>`, but the cause is at `<upstream file:line>` where `<what goes wrong>`. With this change in place, `<what remains broken>`." Severity by what survives: HIGH when the surviving fault corrupts or loses data, or leaves a security or authz decision made on a wrong value; MEDIUM when it leaves an incorrect value in a path a user or caller reads; LOW when the consequence is a confusing log or a masked diagnostic. Tag `[FIX-NOW]` when the upstream fix is plainly mechanical and in scope; `[PRODUCT-DECISION]` when fixing the cause means changing behavior someone chose, or reaches outside the change's stated scope.

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

## Cross-PR API Conflicts (peer-PR context)

When the `PEER-PR CONTEXT:` slot is non-`none`, scan kept sibling diffs for API-shape collisions with the current PR's changed files:

- Same exported function / endpoint / type / migration touched by both PRs with incompatible signatures (e.g., PR A adds parameter `foo`; PR B renames the same function).
- Same database column / table modified by both PRs (column added in A, removed in B; type changed in both with different types).
- Same shared module imported and mutated by both PRs (concurrent edits to the same lookup table / config object).

A valid finding shape: "PR #N (peer) modifies `<symbol>` at `<file:line>`; current diff also modifies the same symbol with incompatible <shape | type | side-effect> — coordinate ordering / merge resolution before shipping both". Severity HIGH when shipping both causes runtime breakage; MEDIUM when it's a stale-state coordination concern.

## Review Checklist

- [ ] All variables used have null/undefined checks
- [ ] Loop boundaries are correct (< vs <=, length checks)
- [ ] Async state updates are synchronized
- [ ] Type comparisons are correct (=== for strict)
- [ ] All errors are caught and handled
- [ ] No masking defaults or swallowing fallbacks hide a failure from the caller
- [ ] Network/IO calls have timeouts; multi-step writes have rollback on partial failure
- [ ] Logic flows are correct (no inverted conditions); conditionals/switches are complete (else/default present, exhaustive match, no unhandled state)
- [ ] Resources are cleaned up (files, listeners, timers); no fire-and-forget async calls
- [ ] Edge cases handled (empty, single item, max values, unicode strings, timezone/DST)
- [ ] Numeric/float math is precise (no exact-equality on floats, money not in binary float, NaN/Infinity guarded, no lossy large-int coercion)
- [ ] Real-world states the change will hit are handled (empty / concurrent / partial-failure / dependency-down), evidenced by a concrete reachable scenario

## Severity Guidelines

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.

- **CRITICAL** — Unbounded recursion on user input; auth-bypass via missing role check; SQL injection in a dynamic query; deadlock with a documented trigger; data-corruption write with no compensating action; infinite loop reachable from a public entry point; an unhandled real-world state on a reachable common path (empty input, concurrent double-submit) that causes data loss or a crash.
- **HIGH** — Race condition with a specific reachable scenario (e.g., two concurrent writes to the same row without a transaction); off-by-one in pagination when item count equals page size; null-dereference on a non-edge-case path; unhandled error path that leaks state or aborts a request mid-write; a masking default that hides a failure on a path where a downstream consumer acts on the fallback as if it were real data (e.g., `.catch(() => [])` feeding a count / filter / dispatch); a missing rollback that leaves a multi-step write half-applied; a missing real-world-state branch (empty / concurrent / partial-failure / dependency-down) with a cited reachable scenario where it yields a wrong result or aborts a flow.
- **MEDIUM** — Edge-case bug with low likelihood and a cited reachable scenario; incorrect-but-mitigated behavior where a downstream layer compensates; pre-existing bug surfaced by this PR's changes that does not make the bug worse; a swallowed error / dropped stack trace that only degrades diagnosability (failure still surfaces elsewhere); a missing timeout on a network/IO call where a hang is reachable but not on the hot path.
- **LOW** — Defensive-coding suggestions without a demonstrated defect ("add a null check here even though the caller always passes a value"); style suggestions on bug-adjacent code; documentation or PR-description nits about a bug area.
