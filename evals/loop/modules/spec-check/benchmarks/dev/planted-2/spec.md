---
geniro_kind: design-doc
effort_tier: small
lifecycle: approved
---
<!-- geniro:design-doc -->

# Raise the request timeout

## 1. Objective

Raise the default request timeout from 5s to 15s.

## 2. Scope — Included
- `config/default.json`

## 3. Scope — Excluded
- Retry policy.

## 4. Assumptions
- `config/default.json` is the file the service actually reads at startup
  (`src/loader.ts:6`).
- The timeout is expressed in milliseconds (`config/default.json:1`).

## 5. Risks
- none — single constant.

## 6. Steps
- [ ] 1. Change `timeoutMs` to 15000 in `config/default.json:1`. <!-- step-1 -->
- [ ] 2. Confirm no other caller hardcodes the timeout (`src/loader.ts:42`). <!-- step-2 -->

## 7. Tools Required
- none

## 8. Approval Points
- none

## 9. Validation
- Start the service and observe the effective timeout.

## 10. Rollback-Recovery
- Revert the one-line change.

## 11. Done Condition
- Effective timeout is 15s.
