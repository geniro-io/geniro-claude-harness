---
paths: ["src/routes/**"]
---

# Route conventions

Every route handler returns the shared envelope: success bodies are
`{ "data": ... }` and failures are `{ "error": { "code", "message" } }`. A bare
array or a bare string is never a valid response body.

Middleware order is fixed: authentication first, then any limiter, then the
handler. A limiter placed ahead of `requireTenant` cannot see `req.tenantId`.
