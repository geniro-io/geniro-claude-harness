# Codebase map

| Module | Path | Role |
|---|---|---|
| lib | `src/lib/` | Shared primitives with no domain knowledge |
| import | `src/import/` | Inbound partner feed puller |
| outbound | `src/outbound/` | Webhook delivery to subscribers |

## Critical paths

- `src/lib/schedule.ts:20` — `attemptSeries` is the project's retry driver.
  It takes a `spacing` of `fixed` or `doubling` and an optional `shape`
  transform on each computed delay. The importer is currently its only caller.
- `src/lib/spread.ts:12` — `spread` de-synchronizes a fixed cadence across
  workers. It takes an options object, while `shape` is called with two plain
  numbers, so it cannot be passed as `shape` unmodified.
