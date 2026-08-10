# Run model batch

Four approved items, scoped separately.

## Todos

### todo-1 — Local model backend

Add a locally-hosted model as a selectable agent backend. Runs must be able to
carry it as their kind, and it must survive the round trip to the renderer.

### todo-2 — Per-backend concurrency ceiling

Each agent backend should declare a maximum number of simultaneous runs, and the
scheduler should refuse to start a run past that backend's ceiling.

### todo-3 — Run cancellation reason

When a run is cancelled, record why (user action, timeout, daemon shutdown) and
show it in the run header.

### todo-4 — Settings window keyboard shortcut

Open the settings window with the platform-standard shortcut.
