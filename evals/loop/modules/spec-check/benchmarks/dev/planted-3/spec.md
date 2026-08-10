---
geniro_kind: design-doc
effort_tier: medium
lifecycle: approved
---
<!-- geniro:design-doc -->

# Add per-tenant webhook backfill

## 1. Objective

Backfill missed webhook deliveries per tenant.

## 2. Scope — Included
- `src/events.ts`

## 3. Scope — Excluded
- Inbound webhooks.

## 4. Assumptions
- No rate limiting or pacing exists on the outbound path, so a backfill can
  dispatch as fast as the queue drains.
- Three event names are in scope for backfill (`src/events.ts:2`).

## 5. Risks
- Write volume — see step 2.

## 6. Steps
- [ ] 1. Add a backfill entry point beside `fanout` (`src/events.ts:10`). <!-- step-1 -->
- [ ] 2. Budget the run: with 8 event names and 50 subscribers per tenant, one
      tenant backfill issues about 400 deliveries, so a 100-tenant backfill is
      roughly 4,000 deliveries. <!-- step-2 -->

## 7. Tools Required
- none

## 8. Approval Points
- none

## 9. Validation
- Count deliveries emitted for one tenant.

## 10. Rollback-Recovery
- Disable the entry point.

## 11. Done Condition
- Backfill completes for one tenant without queue saturation.
