---
geniro_kind: design-doc
effort_tier: medium
lifecycle: approved
---
<!-- geniro:design-doc -->

# Remove the legacy ledger read path

## 1. Objective

Delete the legacy ledger read path now that the unified path is fully rolled out.

## 2. Scope — Included
- `src/ledger.ts`

## 3. Scope — Excluded
- Write paths.

## 4. Assumptions
- The `unified-ledger` flag has been at 100% for all cohorts long enough that no
  traffic still takes the legacy branch (`deploy/rollout.yaml:2`).

## 5. Risks
- none, given the assumption above.

## 6. Steps
- [ ] 1. Delete `readLegacy` and the branch that calls it (`src/ledger.ts:4`). <!-- step-1 -->
- [ ] 2. Drop the now-unused `legacy-ledger-read` flag entry (`deploy/rollout.yaml:7`). <!-- step-2 -->

## 7. Tools Required
- none

## 8. Approval Points
- none

## 9. Validation
- All ledger reads return the unified source.

## 10. Rollback-Recovery
- Revert the deletion commit.

## 11. Done Condition
- Legacy read path gone.
