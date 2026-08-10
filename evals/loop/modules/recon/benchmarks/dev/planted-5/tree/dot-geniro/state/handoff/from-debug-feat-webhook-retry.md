---
tier: T2
producer: debug
schema-version: 2
branch: feat/webhook-retry
authored_tests:
  - path: src/outbound/webhook.retry.test.ts
    intent: "a subscriber returning 503 twice then 200 receives exactly one successful delivery"
open_questions: []
---

# Debug handoff — feat/webhook-retry

## Reproduction

A subscriber returning 503 loses the delivery permanently: `deliver` throws and
nothing retries it. Confirmed against `src/outbound/webhook.ts:11`.

## Reproduction test

- **Test file:** `src/outbound/webhook.retry.test.ts` — red on current code.
