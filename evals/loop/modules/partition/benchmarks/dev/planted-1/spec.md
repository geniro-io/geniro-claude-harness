# Q3 core package work

Five independent-looking pieces of work were approved for `@acme/core` this
sprint. They were planned separately and none of them blocks another.

## Todos

### todo-1 — Restructure user timestamps

`User` currently carries a single flat `createdAt`. Product wants activity
tracking, so replace that flat field with a nested `timestamps` object holding
both `createdAt` and a new `lastSeenAt`. Update the type and anything in the
package that reads the old field.

### todo-2 — Invoice PDF rendering

Add PDF rendering for an invoice. The rendered document shows the invoice
amount, the invoice id, and the account holder's details including when the
account was opened. Add the renderer alongside the existing invoice code and
make it available to consumers of the package.

### todo-3 — Health endpoint

Register a `/health` route that returns `{ ok: true }` so the load balancer has
something to poll. No auth, no body parsing.

### todo-4 — Account summary helper

Add a `summarizeAccount(userId: string)` helper that walks the ledger and
returns `{ invoiceCount, totalCents, voidedCount }` for that account. It reads
invoice records only. Make it available to consumers of the package.

### todo-5 — Configurable session TTL

The session lifetime is hardcoded at 30 minutes. Read it from
`SESSION_TTL_MINUTES` instead, defaulting to 30 when unset, and validate that
the parsed value is a positive integer.
