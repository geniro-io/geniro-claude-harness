# Reliability sprint

Four approved items, planned independently.

## Todos

### todo-1 — Retry user reads

User reads fail intermittently against the upstream. Wrap the user read path in
a retry with exponential backoff — three attempts, jittered.

### todo-2 — Retry order reads

Order reads fail intermittently against the same upstream. Wrap the order read
path in a retry with exponential backoff — three attempts, jittered.

### todo-3 — Metrics endpoint

Expose a `/metrics` endpoint returning Prometheus text format. Registration
only; the collector already exists elsewhere.

### todo-4 — Rename the read method

`Fetch` is ambiguous next to the newer streaming calls. Rename the single-record
read method to `Get` everywhere it is defined and called.
