# Agent CLI expansion

Four approved items for the daemon. They were scoped separately and none was
described as blocking another.

## Todos

### todo-1 — Gemini CLI support

Add support for driving the Gemini CLI as an agent backend, following the shape
of the adapters already present. A run whose kind is `gemini` must dispatch to
it, and `GET /v1/capabilities` must report it like the others.

### todo-2 — Aider CLI support

Add support for driving the Aider CLI as an agent backend, same shape as the
existing adapters. A run whose kind is `aider` must dispatch to it, and
`GET /v1/capabilities` must report it like the others.

### todo-3 — Structured adapter timings

Every adapter should emit a duration metric per turn. Add the timing emission
inside the shared adapter base so individual adapters need no change.

### todo-4 — UI empty-state copy

The chats list shows a bare "No chats yet" string once the first fetch has
settled on an empty list. Replace it with the designed empty state:
illustration, headline, and a primary action that starts a chat.
