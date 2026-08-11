# Memory backend — route L2 learnings through a project-declared backend

Single source of truth for the memory-backend routing primitive. Skills cite this file; do NOT inline-paste the procedure.

Applied at the L2 memory call-sites (`emit-learning` / `query-learnings`) so a project can store and retrieve agentic learnings through a custom backend — typically an MCP server (a hosted memory service, a vector store, a knowledge graph) — instead of, or alongside, the built-in `.geniro/knowledge/learnings.jsonl` file. Declarative, orchestrator-consumed, read-only-screened, fail-open. With no declaration: the built-in file, unchanged.

## Contents

- §1 What it consumes — the `## Memory Backend` block
- §2 Block schema
- §3 Where routing happens — call-site inline, agent when spawned
- §4 Procedure — DISCOVER → SCREEN → ROUTE
- §5 Modes — mirror vs replace
- §6 Fail-open
- §7 Plain-English echo
- §8 Anti-rationalization

## 1. What it consumes

A `## Memory Backend` block authored in the dedicated `.geniro/instructions/memory.md` file and surfaced by the L4 loader (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`, which loads `memory.md` alongside `global.md` for every consumer). Absent file or block → no routing; L2 reads/writes use the built-in file helpers exactly as today. Memory routing is its own concern, so it lives in its own file (not mixed into `global.md`'s behavioral rules and not a per-skill file).

## 2. Block schema

One entry per layer the project routes. v1 covers L2 (`learnings`); other layers are reserved.

```markdown
## Memory Backend
<!-- Route agent knowledge/memory through a custom backend. Default = built-in .geniro files. The `read` tool/command has to be read-only — a misdeclared one mutates on every recall. -->
- layer: learnings          # learnings (L2). snapshot (L3) reserved — not yet routed
  mode: mirror              # mirror = write file AND backend; replace = backend only
  write: mcp tool `mcp__memory__upsert`     # store op for an emitted learning
  read:  mcp tool `mcp__memory__search`     # query op for retrieval
```

- **layer** — `learnings` (L2) in v1.
- **mode** — `mirror` (keep the file as the durable mirror, also write the backend) | `replace` (backend is the store; skip the file write). Omitted → `mirror`.
- **write / read** — one MCP tool name (`mcp__...`) or action name each. `write` performs the store on an `emit_learning`; `read` performs the query on a `query_learnings`.

## 3. Where routing happens

The L2 helpers (`emit-learning.sh` / `query-learnings.sh`) are shell — shell cannot call MCP tools, full stop. So routing happens at the call-site around the shell-helper call — the orchestrator, or a spawned agent, never the helper itself — exactly as `## Data Sources` is consumed by the orchestrator, not by a helper. This primitive is the call-site contract the `emit-learning.md` / `query-learnings.md` docs cite; the shell scripts are unchanged.

**The orchestrator calls the declared tool itself.** A skill's `allowed-tools` frontmatter pre-approves tools so they skip a permission prompt; it does not restrict which tools the orchestrator can call — every tool stays reachable, gated only by the user's permission settings. So on a routed `learnings` block the orchestrator runs this DISCOVER → SCREEN → ROUTE inline and calls the declared `read` / `write` tool directly, whether or not `mcp__*` happens to be pre-approved in its own `allowed-tools`. A call outside the pre-approved set may raise a permission prompt — the user, present at the orchestrator, resolves it like any other unlisted-tool call.

**A spawned agent is different: `tools:` is a hard allowlist.** A leaf agent without `mcp__*` in its own `tools:` genuinely cannot call an MCP tool. `knowledge-retrieval-agent` and `reflection-agent` carry `mcp__*` and, on a routed `learnings` block, apply this same DISCOVER → SCREEN → ROUTE for their OWN read — necessary because the read runs inside the fork, which shares no memory or working state with the orchestrator, and because under `replace` the file it would otherwise read is empty. Spawned scoped `SCOPE: learnings-backend` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` ladder, OMIT `model=`), `knowledge-retrieval-agent` returns a ≤3K-char condensed report as its final message instead of the raw backend-query results — the same context-isolation trade `/implement`'s full four-step sweep makes, and one an orchestrator may take over the inline call to keep those raw results out of its own context. Pass it the standard Input Contract slots — at minimum `SCOPE: learnings-backend`, `INFERRED_TAGS` (empty ⇒ empty read), `LIB_ROOT`, `KNOWLEDGE_ROOT`, `TASK_DESCRIPTION` — and gate the spawn on the block's presence: no `## Memory Backend` block routing `learnings` → no spawn, the inline read runs unchanged.

## 4. Procedure — DISCOVER → SCREEN → ROUTE

- **DISCOVER.** Read the `## Memory Backend` entries surfaced by the L4 loader. Absent → built-in file only; stop.
- **SCREEN.** The `read` tool/command passes the read-only screen in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §4 before it runs (a query / search / get tool). A `read` that fails the screen is skipped with a caveat → fall back to the file query. The `write` tool is the declared mutator — storing a learning is its job — so it is exempt from the read-only screen, but it must be a STORE op (`upsert` / `store` / `save` / `put` / `add` semantics); reject it if its name carries a clearly out-of-scope destructive verb (`rm` / `drop` / `delete` / `deploy` / `push`). The write is a store, never a delete or deploy.
- **ROUTE (per L2 op).** Redact BEFORE any backend store — the backend is an external sink and must never receive raw repo text, so the backend always receives sanitized text either way. The orchestrator-reachable redaction primitive is `lib/redact-secrets.sh` (standalone); `emit_learning`'s redaction is internal to the shell helper, applies only when the helper runs, and the helper ALWAYS appends to the file (no skip mode) — which is why it appears only on the file/mirror path. The per-mode write and read behavior is the §5 table.

## 5. Modes — mirror vs replace

| mode | emit (write) | query (read) |
|---|---|---|
| `mirror` | `emit_learning` (file append, redacts internally) AND `redact-secrets.sh` → backend write | merge file + backend results (dedup by `dedup_key`, backend-first) |
| `replace` | `redact-secrets.sh` → backend write only; `emit_learning` is NOT called (it always appends, so calling it would write the file) | backend query only |

## 6. Fail-open

A backend error never blocks the run or the learning.

| Situation | Behavior |
|---|---|
| `mirror`, backend write/read errors | Use the file result; one-line caveat. The local file is authoritative, so nothing is lost. |
| `replace`, backend errors | Drop to the file helper for THIS op + caveat — a learning is never lost to an unreachable backend, even under replace. |
| `read` tool fails the read-only screen | Skip it; fall back to the file query; caveat. |
| No `## Memory Backend` block | Built-in file only; no caveat; unchanged behavior. |

The SessionStart auto-archive operates on the file mirror only; under `replace` with no local file written, it has nothing to scan — documented, not an error. For the same reason, under `replace` the file-based access counter (`record_access`) and the dedup / supersede chain also no-op (there is no file to rewrite) — the backend owns ranking and dedup. This is a documented consequence of `replace`, not a silent break; `mirror` keeps all of them on the local file.

One more file-based reader degrades the same way under `replace`, by design: the SessionStart **verification-coverage line** is computed over the local file, so under `replace` it is empty — the hook is shell and cannot query the backend, so it emits a short `memory backend active` notice in that slot instead of a fraction. `mirror` keeps it on the local file.

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
| "Skip the read-only screen — it's the user's own tool." | The `read` op must be read-only; the screen is non-negotiable because a misdeclared read tool could mutate. The `write` op is the declared mutator (exempt from the read-only screen), but it must be a STORE op — reject a `write` whose name carries `rm` / `drop` / `delete` / `deploy` / `push` (§4 SCREEN). |
| "Backend is down — fail the emit so nothing is lost." | Fail-open: drop to the file helper for that op. Blocking a learning on an unreachable backend is how a learning is lost; the file fallback never loses it. |
| "On `replace`, call `emit_learning` and just point it at the backend." | `emit_learning` ALWAYS appends to the local file (no skip mode), so it cannot be pointed elsewhere — calling it under `replace` silently turns the routing into `mirror`. Redact via `lib/redact-secrets.sh` standalone, then call the `write` tool (§4 ROUTE, §5); skipping the standalone redaction egresses un-redacted text, because the helper's own redaction never ran. |
