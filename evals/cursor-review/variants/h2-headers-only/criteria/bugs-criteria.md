# Bugs review criteria
## Contents
## What to check
### 1. Null/undefined handling
**Severity:** CRITICAL when the null-deref crashes on a documented common-input path; HIGH when it sits on a non-edge-case path with a lower-traffic trigger; MEDIUM for a null-check gap on a genuinely rare edge case with a cited reachable scenario; LOW for a defensive-coding suggestion with no demonstrated input that reaches the gap.
### 2. Off-by-one errors
**Severity:** HIGH when the boundary error is reachable under normal item counts (e.g., item count equals page size); MEDIUM for an off-by-one with a cited but less common trigger; LOW when the boundary is technically wrong but never reachable under the domain's actual value range.
### 3. State management issues
**Severity:** CRITICAL when the race condition overwrites or corrupts persisted user data; HIGH for a specific reachable scenario without persisted corruption (two concurrent writes to the same in-memory state, no transaction); MEDIUM for a cleanup gap (missing unsubscribe/dispose) that leaks memory or state without corrupting a user-visible result; LOW for an immutability preference with no cited defect.
### 4. Type safety issues
# Loose equality — the character classes exclude `===` and `!==`; a `grep -v "==="` filter keeps every `!==`
**Severity:** HIGH when a coercion or loose-equality bug reaches a non-edge-case path with a wrong result; MEDIUM when missing input validation is reachable but mitigated by a downstream check; LOW for a type-safety style preference with no demonstrated wrong output.
### 5. Error handling gaps
### 5.5. Silent failure & dangerous fallback
### 6. Logic errors
# Unreachable code — a statement (not a closing brace or comment) immediately after return/break/throw/continue
### 7. Resource leaks
### 8. Boundary conditions
### 8.5. Numeric precision & floating-point
### 9. Functional completeness — real-world states the change must handle
### 10. Root cause vs symptom — does the change fix the cause or hide it?
## Common false positives
## Cross-PR API conflicts (peer-PR context)
## Review checklist
## Severity guidelines
