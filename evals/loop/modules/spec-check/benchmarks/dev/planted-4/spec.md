---
geniro_kind: design-doc
effort_tier: small
lifecycle: approved
forbidden_actions:
  - "do NOT run any job inline that performs network I/O — docs/conventions.md:5 calls inline network work forbidden"
---
<!-- geniro:design-doc -->

# Add a scheduled report build

## 1. Objective

Build the nightly report through the job system.

## 2. Scope — Included
- `src/report.ts`

## 3. Scope — Excluded
- Email delivery.

## 4. Assumptions
- The conventions doc bans inline network I/O outright (`docs/conventions.md:5`),
  so `buildReport` must be moved onto the queue before anything else changes.
- `buildReport` currently violates that ban (`src/report.ts:5`).

## 5. Risks
- Queue latency — low.

## 6. Steps
- [ ] 1. Move `buildReport` onto the queue (`src/report.ts:4`). <!-- step-1 -->
- [ ] 2. Add entry/exit info logs per the logging convention (`docs/conventions.md:11`). <!-- step-2 -->

## 7. Tools Required
- none

## 8. Approval Points
- none

## 9. Validation
- The report job appears on the queue.

## 10. Rollback-Recovery
- Revert.

## 11. Done Condition
- Nightly report runs via the queue.
