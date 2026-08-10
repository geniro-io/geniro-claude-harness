# Codebase map

| Module | Path | Role |
|---|---|---|
| notify | `src/notify/` | Delivery channels — one module per transport |
| queue | `src/queue/worker.ts` | BullMQ worker that drains the `notify` queue |
