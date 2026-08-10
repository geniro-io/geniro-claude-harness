# Backlog batch 14

Five approved items. They were written by different people and none of them was
described as blocking another.

## Todos

### todo-1 — Refunds endpoint

Add a refunds handler exposing `/refunds` with a `get(refund_id)` method,
following the shape of the handlers already in the package. It must be
reachable through the normal dispatch path.

### todo-2 — Inbound webhooks endpoint

Add a webhooks handler exposing `/webhooks` with a `get(event_id)` method. Same
shape as the existing handlers, and it must be reachable through the normal
dispatch path.

### todo-3 — Order status column

Orders need a `status` column. Add the schema change so a fresh database and an
already-deployed one both end up with the column.

### todo-4 — Soft-delete users

Users need a `deleted_at` column for soft deletion. Add the schema change so a
fresh database and an already-deployed one both end up with the column.

### todo-5 — Raise the request timeout

The request timeout is too tight for the reporting endpoints. Raise it from 15
to 45 seconds.
