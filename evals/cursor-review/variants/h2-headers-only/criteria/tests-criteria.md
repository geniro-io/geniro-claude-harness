# Tests review criteria
## Contents
## Test design philosophy (canonical)
### 1. Tests describe behavior, not implementation
### 2. Public interface only
### 3. The "would survive a refactor" rule
### 4. Mocking discipline
### 5. Test names as specifications
### 6. Tests that fail meaningfully
### 7. F→P invariant for new tests
## What to check
### 8. Coverage Gaps
# Does any test file reference the changed file's basename? Search by pathspec — a fixed
# tests/<same-name> layout holds in almost no repo and reports every file as untested there.
# Look for test skips
# Count assertions per test
### 9. Missing Edge Cases
### 10. Test Quality & Maintainability
# Find vague test names (whole-word vague markers; not a bare "test" which re-matches every test_ name)
# Find mocked dependencies
### 11. Async/Promise Testing
# Async test declarations — read each hit's body for a missing await
# Promise tests without .catch
# Tests with real timers
# Find callback-style async without promise wrappers
### 12. Integration Testing
### 13. Test Organization & Structure
# Where the repo keeps tests — unit and integration separated, or interleaved with source
# Look for setup/teardown
# Count test suites
# Look for fixtures or test data
### 14. Mocking & Dependencies
### 15. Critical Path Testing
## Common false positives
## Litmus test (the deletion test)
## Tests of the scenery — never author, flag for removal
## Assertion completeness & spec coverage
### Independent expected values
### Claimed scope vs asserted scope
### Spec-coverage traceability
### Redundancy among newly-authored tests
## Test deletions in the diff (inverse deletion test)
### Cause-path examples (real shape; from prior incident)
### How to apply
### Anti-rationalization
### Litmus test for the inverse (the "would restoring the deletion fail any test?" check)
## Review checklist
## Severity guidelines
