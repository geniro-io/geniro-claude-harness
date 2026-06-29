# Subagent — load project instructions

A subagent starts with **no orchestrator context** — only its spawn prompt. The project rules the orchestrator loaded (search policy, code-style, constraints) do not reach it automatically. So an agent that explores or judges code loads the project's instruction files itself, mirroring what the orchestrator loads via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`.

## What to load

- **`global.md`** — project-wide rules. Load this whenever your work searches or explores the codebase: it may define **how to search this project** (e.g. a policy to query the project's code index before a plain-text search) plus other constraints that change which tool you reach for. Follow that policy when you locate code.
- **`code-style.md`** — cross-cutting code-style rules. Load this additionally when your work judges or writes code (review, test authoring).
- **`memory.md`** — memory-backend routing (the `## Memory Backend` block). Load this when your work **reads past learnings (L2)**: when the block routes the `learnings` layer to a backend, the local `learnings.jsonl` may be empty (under `mode: replace` it is never written), so the file query returns nothing — you must route the read through the declared backend read tool per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (you have `mcp__*`, so the declared MCP read tool is reachable; fail-open to the file query on a backend error). Absent block → the file query is correct, unchanged.

A project may ship none of these — an absent file is the normal case, not an error. Skip it silently.

## How to resolve each file (first hit wins)

You have Bash, so resolve the path yourself:

1. If `$GENIRO_INSTRUCTIONS_DIR` (or `$CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR`; `$GENIRO_INSTRUCTIONS_DIR` wins when both are set) points to a directory, read `<that-dir>/<file>` (expand a leading `~` to `$HOME`; confirm the dir exists). This is the external-instructions override.
2. Otherwise read `.geniro/instructions/<file>` from the current working directory.
3. On file-not-found, retry `<PRIMARY_ROOT>/.geniro/instructions/<file>`, where `PRIMARY_ROOT` comes from the Mode A snippet in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` — this mirrors the orchestrator's loader fallback so a stale-cwd linked worktree still sees the project's rules.

The orchestrator may have pre-inlined a file's content as a labeled slot in your prompt (`PROJECT INSTRUCTIONS:` for `global.md`, `CODE-STYLE INSTRUCTIONS:` for `code-style.md`). When a slot is present, treat it and the on-disk file as the same source — the file is authoritative, the slot is a context-saving copy — and skip the read.
