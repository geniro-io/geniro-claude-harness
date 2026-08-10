# Scheduler tuning

Three approved items, reported by different teams.

## Todos

### todo-1 — Raise queue capacity

The queue rejects work during peak hours. Raise the depth it accepts to 2000.

### todo-2 — Per-priority concurrency

Introduce high and low priority jobs, each with its own concurrency ceiling
instead of the single global one, and have draining respect both.

### todo-3 — Human-readable durations over a minute

Durations past 60 seconds should read as minutes and seconds rather than a bare
second count.
