---
geniro_kind: design-doc
effort_tier: small
lifecycle: approved
---
<!-- geniro:design-doc -->

# Add exponential backoff

## 1. Objective

Add exponential backoff to the client's retry behavior.

## 2. Scope — Included
- `src/retry.ts`

## 3. Scope — Excluded
- Timeouts.

## 4. Assumptions
- Every client call already goes through `withRetry` (`src/client.ts:2`), so
  adding backoff inside it covers the whole surface.
- `withRetry` currently waits between attempts and only the delay curve changes
  (`src/retry.ts:4`).

## 5. Risks
- Longer tail latency.

## 6. Steps
- [ ] 1. Replace the fixed wait with an exponential curve (`src/retry.ts:4`). <!-- step-1 -->

## 7. Tools Required
- none

## 8. Approval Points
- none

## 9. Validation
- Observed delays grow between attempts.

## 10. Rollback-Recovery
- Revert.

## 11. Done Condition
- Backoff is exponential.
