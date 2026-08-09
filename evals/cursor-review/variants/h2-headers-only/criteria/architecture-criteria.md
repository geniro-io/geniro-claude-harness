# Architecture review criteria
## Contents
## What to check
### 1. Module design & coupling
# Find circular imports — use a graph tool; it catches transitive A->B->C->A cycles a grep can't:
### 1.5. Caller-blast check for semantic mutations
### 1.6. Parallel-path symmetry (mirror-gap)
### 1.7. Type design — make illegal states unrepresentable
### 2. Abstraction & interface design
**Severity:** HIGH when the leak lets a cross-module caller depend on an implementation detail the interface was meant to hide; MEDIUM when it costs a sibling module knowledge of an implementation detail with no cross-module dependency yet in place; LOW for a structural preference with no cited coupling cost. Never CRITICAL — a runtime defect a leaky abstraction causes is owned by the bugs dimension.
### 3. SOLID principles violations
**Severity:** MEDIUM when the violation already forces a ripple edit across multiple call sites (Open/Closed) or a subclass breaks a base contract (Liskov) with a cited caller; LOW when it is a structural preference with no cited defect or growth-pressure ("this would be cleaner as a class"). Never CRITICAL — a runtime defect a SOLID violation causes is owned by the bugs dimension.
### 4. Code organization & structure
# Catch-all modules across the repo — the name is the signal
# Reach — how many distinct areas one file imports from; breadth says it knows too much
# Change coupling — a file in most recent commits is absorbing every feature
### 4.5 Function-level complexity & cognitive load
# Surface deeply-indented lines (a heuristic pointer, not a quality metric).
# {12,} / \t{3,} assume a 4-space or tab indent (~3+ nested levels); for a 2-space-indent file use {8,} to catch the same depth.
**Severity:** LOW by default (readability). MEDIUM when the function sits on a critical path (auth / payment / data-write) where the cognitive load raises real defect risk. Never CRITICAL — a runtime defect this complexity hides is owned by the bugs dimension.
### 5. Error handling architecture
**Severity:** HIGH when the inconsistency spans a module boundary and a caller's catch clause assumes the wrong error contract, so the error propagates uncaught; MEDIUM when errors are swallowed or logged without context but the surrounding code still degrades gracefully; LOW for a stylistic try-catch vs `.catch()` inconsistency with no cited caller impact. Never CRITICAL — an error-handling gap that already causes a crash or data loss is a bugs-dimension finding.
### 6. Performance & scalability
# Potential N+1 — a query in the lines following a loop header. The context flag belongs on the
# file-reading grep; on the filter it scans the piped stream and the recipe finds nothing.
# ORM N+1 — model access inside a loop body
### 7. Technical debt
### 7.5 Reinvented-wheel / build-vs-buy
### 8. Testability of the production code
**Severity:** MEDIUM when the seam forcing heavy mocking sits in code this diff newly introduces; LOW for a pre-existing testability gap the diff does not worsen. Never CRITICAL — a test gap never crashes production on its own; a runtime defect it lets slip through is a bugs-dimension finding.
### 9. Spec done-condition progress (when PLAN CONTEXT present)
## Common false positives
## Severity guidelines
