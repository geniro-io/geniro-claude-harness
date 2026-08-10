---
paths: ["src/api/**/*.ts"]
---

# API handler conventions

Handlers are registered by an exported `register*` function taking the Fastify
instance. Never call `app.listen` outside the composition root.

Responses use the shared envelope: `{ "data": ... }` or
`{ "error": { "code", "message" } }`.
