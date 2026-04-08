# Bugs Review Criteria

Logic errors, null/undefined checks, boundary conditions, state management, and type safety issues.

## What to Check

### 1. Null/Undefined Handling
- Variables used without null checks before property access
- Optional chaining `?.` or null coalescing `??` missing
- Conditional checks that don't cover all null cases
- Destructuring assignments without defaults
- Array/object indexing without length/existence check

**How to detect:**
```bash
# Find property access patterns
grep -n "^\s*[a-zA-Z_][a-zA-Z0-9_]*\." file.js | grep -v "if\|?.\|&&\|??"
# Find array indexing without guards
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
# Loose equality in comparisons
grep -nE "==\s|!=\s" file.js | grep -v "==="
# Type operations on variables
grep -n "typeof\|instanceof" file.js | grep -v "if\|assert"
```

### 5. Error Handling Gaps
- Try-catch blocks without finally/cleanup
- Errors silently caught and ignored
- Promise rejections not handled
- Callback errors not checked before use
- Missing error propagation

**How to detect:**
- Find `try` blocks followed by empty catch
- Look for unhandled Promise chains
- Check async functions for `await` without error context
- Identify callbacks not checking `err` parameter

### 6. Logic Errors
- Inverted conditionals (`if (!condition)` when should be `if (condition)`)
- Wrong operator used (`&&` instead of `||`, `+` instead of `*`)
- Unreachable code after return/break/throw
- Duplicate/contradictory conditions
- Infinite loops or missing loop termination

**How to detect:**
```bash
# Find inverted conditions
grep -n "if\s*(\s*!" file.js | grep -A2 "return\|throw"
# Find unreachable code
grep -n "return\|break\|throw" file.js | grep -A1 "^"
```

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
# Compare counts — more on() than off() is suspicious
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

**How to detect:**
- Look for operations on `array[0]` without length check
- Find math operations that could have zero denominator
- Check boundary value comparisons

## Output Format

```json
{
  "type": "bug",
  "severity": "critical|high|medium",
  "title": "Brief issue title",
  "file": "path/to/file.js",
  "line_start": 42,
  "line_end": 48,
  "description": "Detailed description of the bug",
  "code_snippet": "Relevant code lines",
  "evidence": "Why this is a bug (execution path, condition)",
  "impact": "What could go wrong",
  "recommendation": "How to fix it",
  "confidence": 95
}
```

## Common False Positives

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

## Stack-Agnostic Patterns

This criteria works across languages:
- Use language-specific grep/pattern equivalents
- JavaScript: `obj.field`, `obj?.field`, `obj ?? default`
- Python: `obj['field']`, `getattr(obj, 'field')`, `obj is None`
- Go: pointer dereference checks, nil checks
- Rust: `Option<T>`, `Result<T,E>` unwrap patterns

## Review Checklist

- [ ] All variables used have null/undefined checks
- [ ] Loop boundaries are correct (< vs <=, length checks)
- [ ] Async state updates are synchronized
- [ ] Type comparisons are correct (=== for strict)
- [ ] All errors are caught and handled
- [ ] Logic flows are correct (no inverted conditions)
- [ ] Resources are cleaned up (files, listeners, timers)
- [ ] Edge cases handled (empty, single item, max values)

## Severity Guidelines

- **CRITICAL**: Null pointer exception, infinite loop, logic inversion causing wrong behavior
- **HIGH**: Race condition, off-by-one in critical path, unhandled error
- **MEDIUM**: Potential panic in edge case, missing edge case handling, type confusion
