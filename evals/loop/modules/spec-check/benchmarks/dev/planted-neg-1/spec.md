---
geniro_kind: design-doc
effort_tier: trivial
lifecycle: approved
---
<!-- geniro:design-doc -->

# Make the cache TTL configurable

## 1. Objective

Allow the cache TTL to be set at startup instead of being fixed.

## 2. Scope — Included
- `src/cache.ts`

## 3. Scope — Excluded
- Cache eviction policy.

## 4. Assumptions
- The TTL is a single exported constant, currently 60000 ms (`src/cache.ts:2`).
- Expiry is evaluated lazily on read rather than by a background sweep
  (`src/cache.ts:7`).

## 5. Risks
- none — the constant has one writer and one reader.

## 6. Steps
- [ ] 1. Replace the `CACHE_TTL_MS` constant with a value supplied at startup,
      keeping the same default (`src/cache.ts:2`). <!-- step-1 -->
- [ ] 2. Keep the lazy-expiry read path unchanged (`src/cache.ts:7`). <!-- step-2 -->

## 7. Tools Required
- none

## 8. Approval Points
- none

## 9. Validation
- A cache configured with a short TTL expires entries sooner.

## 10. Rollback-Recovery
- Restore the constant.

## 11. Done Condition
- TTL is configurable and defaults to the current value.
