---
geniro_kind: design-doc
effort_tier: trivial
lifecycle: approved
---
<!-- geniro:design-doc -->

# Cap slug length

## 1. Objective

Truncate generated slugs to a maximum length.

## 2. Scope — Included
- `src/slug.ts`

## 3. Scope — Excluded
- Uniqueness checks.

## 4. Assumptions
- `slugify` lowercases its input and collapses non-alphanumeric runs to single
  hyphens (`src/slug.ts:2`).
- Leading and trailing hyphens are already stripped (`src/slug.ts:2`).

## 5. Risks
- Truncation could split a word; acceptable.

## 6. Steps
- [ ] 1. Truncate the result to a maximum length before returning it
      (`src/slug.ts:2`). <!-- step-1 -->

## 7. Tools Required
- none

## 8. Approval Points
- none

## 9. Validation
- A long input produces a capped slug.

## 10. Rollback-Recovery
- Revert.

## 11. Done Condition
- Slugs never exceed the cap.
