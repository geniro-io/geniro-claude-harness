# Subagent — load project instructions

A subagent starts with **no orchestrator context** — only its spawn prompt. The project rules the orchestrator loaded (search policy, code-style, constraints) do not reach it automatically. So an agent that explores or judges code loads the project's instruction files itself, mirroring what the orchestrator loads via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`.

## What to load

- **`global.md`** — project-wide rules. Load this whenever your work searches or explores the codebase: it may define **how to search this project** — a code index to query before plain-text search, a required lookup tool, a directory that is off-limits — plus other constraints that change which tool you reach for.

  A declared search policy **outranks the default search steps written into your own workflow below**, and it governs every lookup for the whole run. Two failures are worth naming because they look like compliance from the inside: applying the policy to your first lookup and reverting to your default for the remaining thirty, and reading the policy without acting on it because your workflow already told you to search another way. If the policy names a tool you cannot see, load it before concluding it is unavailable — a runtime that defers tool schemas leaves the tool absent from your surface until you search for it by name, which is indistinguishable from the tool not existing.
- **`code-style.md`** — cross-cutting code-style rules. Load this additionally when your work judges or writes code (review, test authoring).
- **`memory.md`** — memory-backend routing (the `## Memory Backend` block). Load this when your work **reads past learnings (L2)**: when the block routes the `learnings` layer to a backend, the local `learnings.jsonl` may be empty (under `mode: replace` it is never written), so the file query returns nothing — you must route the read through the declared backend read tool per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (you have `mcp__*`, so the declared MCP read tool is reachable; fail-open to the file query on a backend error). Absent block → the file query is correct, unchanged.

A project may ship none of these — an absent file is the normal case, not an error. Skip it silently.

## How to resolve each file (first hit wins)

You have Bash, so resolve the path yourself:

1. If `$GENIRO_INSTRUCTIONS_DIR` (or `$CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR`; `$GENIRO_INSTRUCTIONS_DIR` wins when both are set) points to a directory, read `<that-dir>/<file>` (expand a leading `~` to `$HOME`; confirm the dir exists). This is the external-instructions override.
2. Otherwise read `.geniro/instructions/<file>` from the current working directory.
3. On file-not-found, retry `<PRIMARY_ROOT>/.geniro/instructions/<file>`, where `PRIMARY_ROOT` comes from the Mode A snippet in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` — this mirrors the orchestrator's loader fallback so a stale-cwd linked worktree still sees the project's rules.

The orchestrator may have pre-inlined a whole file's content as a labeled slot in your prompt — `PROJECT INSTRUCTIONS:` for `global.md`, `CODE-STYLE INSTRUCTIONS:` for `code-style.md`. A whole-file slot and the on-disk file are the same source (the file is authoritative, the slot is a context-saving copy), so when one is present, skip that file's read.

`PROJECT SEARCH POLICY:` is different in kind and does NOT license skipping anything: it carries only the search-governing subset of `global.md`, so the rest of that file — every project-wide rule that is not about searching — has still not reached you. Read `global.md` as normal; the slot tells you which of its rules govern your lookups, not that you have seen it. A slot reading `none declared` is an answer rather than an omission: the project declared no search policy and your default search applies.

## Echo what you loaded

Print one line naming each file you loaded and the search policy you are about to follow — `Loaded global.md — search policy: <one clause>` or `Loaded global.md — no search policy declared` or `No global.md found`. A silent load is indistinguishable from a skipped one, and this step is the head of a long workflow where a skip costs nothing visible at the time and shapes every lookup afterwards. The echo is what makes the skip surface in your own run.

It surfaces nowhere else: the orchestrator receives your report, never your narration. So carry the same fact into your report's summary section as a `Context loaded:` line, per your own output schema and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The load report. Report what actually happened — a slot you were handed is `slot`, a file you opened is `read`, a project that ships none is `absent`, a read that failed is `unreadable`. An agent reporting a load it did not make removes the one signal the spawn site has.
