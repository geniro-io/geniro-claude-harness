---
geniro_kind: design-doc
effort_tier: small
lifecycle: approved
---

<!-- geniro:design-doc -->

# Add sliding-window session expiry

## 1. Objective

Extend session lifetime while a user stays active.

## 2. Scope — Included

- `src/auth/session.ts` — expiry policy
- `src/api/routes.ts` — session route

## 3. Scope — Excluded

- Login and logout flows.

## 4. Assumptions

- Sessions are stored in Redis (`src/auth/store.ts:1`).
- The session TTL is 1800 seconds and is defined as a single constant (`src/auth/session.ts:3`).
- No rate limiting exists anywhere on the API surface, so adding a refresh call on
  each request adds no throttling interaction to consider.

## 5. Risks

- Redis write volume — low; see step 2.

## 6. Steps

- [ ] 1. `touchSession` already re-issues the session and writes Redis on every
      request (`src/auth/session.ts:13`), so the sliding window is half-built:
      only the TTL argument needs changing. <!-- step-1 -->
- [ ] 2. Write volume is bounded by the four routes registered in
      `src/api/routes.ts:3`; at most four Redis writes per request cycle. <!-- step-2 -->
- [ ] 3. Keep the logout route untouched (`src/api/routes.ts:6`). <!-- step-3 -->

## 7. Tools Required

- none

## 8. Approval Points

- none

## 9. Validation

- Unit test on `touchSession`.

## 10. Rollback-Recovery

- Revert the commit; no data migration.

## 11. Done Condition

- Session extends on activity and expires after inactivity.
