# Codebase map

## Modules

| Module | Path | Role |
|---|---|---|
| routes | `src/routes/` | Express routers, one file per resource family |
| middleware | `src/middleware/` | Cross-cutting request handlers — auth, limiting |
| lib | `src/lib/` | Infrastructure clients (Redis, Postgres) |

## Critical paths

- `src/middleware/throttle.ts:20` — the only request limiter in the service.
  Every rate-limited route composes it; there is no second implementation.
- `src/middleware/auth.ts:10` — attaches `req.tenantId`; everything tenant-scoped
  depends on running after it.
- `src/lib/redis.ts:6` — `bumpCounter` sets the TTL only when the counter is
  created.
