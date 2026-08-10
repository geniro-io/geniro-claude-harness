---
tier: T1
producer: plan
schema-version: 1
task-slug: ndjson-export
---

# Plan v1 — streaming NDJSON export

## Approach

Emit one JSON object per ledger row directly to the stream as `fetch_rows()`
yields it, so memory stays flat regardless of result-set size.

## Decisions

- **REJECTED — reuse `reporting/table.py:render` as the shared write path.**
  `render` materializes the whole row iterator before emitting its first line,
  because fixed-width columns cannot be sized until the widest cell is known.
  Routing a streaming format through it reintroduces the exact memory ceiling
  the format exists to avoid. Any streaming format writes to the stream itself.
- **ACCEPTED — write directly to the `TextIO` the CLI passes in.** No
  buffering layer, no registry entry: `reporting/cli.py:available_formats`
  discovers format modules by scanning the package directory, so a new module
  file is the whole registration.
- **OPEN — flush cadence.** Left unresolved in v1; per-row flush was measured
  4x slower on the nightly job than flushing every 1000 rows.
