---
tier: T2
producer: review
schema-version: 1
branch: feat/export-limits
report_status: final
open_questions: []
---

# Review handoff — feat/export-limits

## Findings

- [ ] **HIGH** `src/routes/export.ts:10` — the export handler holds a database
  cursor for the duration of the response. Any limiter added here must reject
  BEFORE the handler opens the cursor, or a limited request still costs a
  connection.
- [ ] **MEDIUM** `src/lib/redis.ts:9` — `bumpCounter` sets the expiry only when
  the counter is first created. A bucket that is incremented forever without
  ever hitting 1 again never expires.
