---
tier: T2
producer: review
schema-version: 1
branch: fix/invoice-rounding
report_status: final
open_questions: []
---

# Review handoff — fix/invoice-rounding

## Findings

- [ ] **MEDIUM** `src/billing/invoice.ts:2` — invoice line totals are rounded
  per line rather than once on the sum, so a 40-line invoice can drift by a
  cent. Unrelated to any CLI work.
