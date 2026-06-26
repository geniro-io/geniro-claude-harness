# Memory backend — route L2 learnings through a project-declared backend

Single source of truth for the memory-backend routing primitive. Skills cite this file; do NOT inline-paste the procedure.

Applied at the L2 memory call-sites (`emit-learning` / `query-learnings`) so a project can store and retrieve agentic learnings through a custom backend — typically an MCP server (a hosted memory service, a vector store, a knowledge graph) — instead of, or alongside, the built-in `.geniro/knowledge/learnings.jsonl` file. Declarative, orchestrator-consumed, read-only-screened, fail-open. With no declaration: the built-in file, unchanged.

## Contents

- §1 What it consumes — the `## Memory Backend` block
- §2 Block schema
- §3 Why the orchestrator routes (not the shell helper)
- §4 Procedure — DISCOVER → SCREEN → ROUTE
- §5 Modes — mirror vs replace
- §6 Fail-open
- §7 Plain-English echo
- §8 Anti-rationalization

## 1. What it consumes

A `## Memory Backend` block authored in `.geniro/instructions/global.md` and surfaced by the L4 loader (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`). Absent block → no routing; L2 reads/writes use the built-in file helpers exactly as today. Project-wide concern, so it lives in `global.md` (not a per-skill file).

## 2. Block schema

One entry per layer the project routes. v1 covers L2 (`learnings`); other layers are reserved.

```markdown
## Memory Backend
<!-- Route agent knowledge/memory through a custom backend. Default = built-in .geniro files. The `read` tool/command MUST be read-only. -->
- layer: learnings          # learnings (L2). snapshot (L3) reserved — not yet routed
  mode: mirror              # mirror = write file AND backend; replace = backend only
  write: mcp tool `mcp__memory__upsert`     # store op for an emitted learning
  read:  mcp tool `mcp__memory__search`     # query op for retrieval
```

- **layer** — `learnings` (L2) in v1.
- **mode** — `mirror` (keep the file as the durable mirror, also write the backend) | `replace` (backend is the store; skip the file write). Omitted → `mirror`.
- **write / read** — one MCP tool name (`mcp__...`) or action name each. `write` performs the store on an `emit_learning`; `read` performs the query on a `query_learnings`.

## 3. Why the orchestrator routes

The L2 helpers (`emit-learning.sh` / `query-learnings.sh`) are shell — shell cannot call MCP tools (MCP is an orchestrator capability). So routing happens at the ORCHESTRATOR call-sites, around the shell-helper call — exactly as `## Data Sources` is consumed by the orchestrator, not by a helper. This primitive is the call-site contract the `emit-learning.md` / `query-learnings.md` docs cite; the shell scripts are unchanged.

## 4. Procedure — DISCOVER → SCREEN → ROUTE

- **DISCOVER.** Read the `## Memory Backend` entries surfaced by the L4 loader. Absent → built-in file only; stop.
- **SCREEN.** The `read` tool/command passes the read-only screen in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §4 before it runs (a query / search / get tool). A `read` that fails the screen is skipped with a caveat → fall back to the file query. The `write` tool is the declared mutator (storing a learning is its job), exempt from the read-only screen but still screened against non-memory destructive ops.
- **ROUTE (per L2 op).**
  - On `emit_learning` (write): the helper's own redaction runs FIRST, then the declared op per §5 — the backend receives sanitized text, never raw.
  - On `query_learnings` (read): per §5, query the backend, the file, or both (merge + dedup by `dedup_key`, backend-first).

## 5. Modes — mirror vs replace

| mode | emit (write) | query (read) |
|---|---|---|
| `mirror` | file helper AND backend write | merge file + backend results (dedup by `dedup_key`) |
| `replace` | backend write only (skip the file) | backend query only |

Default when `mode` is omitted is `mirror` — never silently lose the local audit trail.

## 6. Fail-open

A backend error never blocks the run or the learning.

| Situation | Behavior |
|---|---|
| `mirror`, backend write/read errors | Use the file result; one-line caveat. The local file is authoritative, so nothing is lost. |
| `replace`, backend errors | Drop to the file helper for THIS op + caveat — a learning is never lost to an unreachable backend, even under replace. |
| `read` tool fails the read-only screen | Skip it; fall back to the file query; caveat. |
| No `## Memory Backend` block | Built-in file only; no caveat; unchanged behavior. |

The SessionStart auto-archive operates on the file mirror only; under `replace` with no local file written, it has nothing to scan — documented, not an error.

## 7. Plain-English echo

Name what happened in plain words, using the backend's label, not the raw tool id:

```
Storing learnings in your memory backend (and keeping the local copy).
Couldn't reach your memory backend — saved the learning to the local file instead.
Retrieved past learnings from your memory backend.
```

## 8. Anti-rationalization

| Reasoning | Why it is wrong |
|---|---|
| "Put the MCP call inside `emit-learning.sh`." | Shell cannot call MCP. Routing is orchestrator-level, around the helper — that is why this contract lives at the call-site, not in the script. |
| "Use `replace` by default to fully offload memory." | Default is `mirror`. `replace` silently drops the local audit trail and disables SessionStart auto-archive — use it only when the user explicitly wants the backend as the sole store. |
| "Skip the read-only screen — it's the user's own tool." | The `read` op must be read-only; the screen is non-negotiable because a misdeclared read tool could mutate. The `write` op is the declared mutator (exempt from the read-only screen) but still screened against non-memory destructive ops. |
| "Backend is down — fail the emit so nothing is lost." | Fail-open: drop to the file helper for that op. Blocking a learning on an unreachable backend is how a learning is lost; the file fallback never loses it. |
| "Send the learning to the backend, then redact." | Redact FIRST (the helper's own sanitization), then store — the backend must never receive un-redacted secrets, same bar as the local file. |
