# Graphiti gotchas — "saved but nothing persisted"

Real failure observed during integration: the full flow ran, Neo4j + the
Anthropic LLM each worked in isolation, the call returned success — but nothing
landed in the graph, with no errors. This is a known, reported class of bug.
Two distinct root causes share this symptom; diagnose before fixing.

## Diagnose first

Run in Neo4j:

```cypher
MATCH (n) RETURN labels(n) AS label, count(*) ORDER BY count(*) DESC
```

- **Nothing at all** → Cause A (server async worker / write path).
- **`Episodic` present but no `Entity` / relationship nodes** → Cause B
  (extraction or embedder returned empty).

## Cause A — REST server async worker never starts (issue #566)

- The `graph_service` REST endpoint (`/messages`) returns **HTTP 202 Accepted**,
  queues the job to `async_worker.queue`, but **`async_worker.start()` is never
  called in `main.py`** — so the worker thread never processes the queue.
  Nothing persists, no errors logged, Neo4j shows no rejects. (Occasionally 1-2
  messages succeed right after a restart — same issue.)
- This is the **REST server**, not the core library. A direct, awaited
  `graphiti.add_episode(...)` from `graphiti-core` persists fine.
- Reported unresolved at time of writing — verify against your version.
- Related: issue #345 is a *different* server failure (MCP SSE
  `ServerSession._receive_loop` pydantic validation error on `mcp==1.5.0`).

**Fix / workaround:**
- Call `await graphiti.add_episode(...)` directly via the library instead of the
  buggy async `/messages` queue; OR
- patch the server `main.py` to call `async_worker.start()` in the FastAPI
  lifespan/startup; OR pin a version where the worker start is fixed.

### Cause A on the MCP server (different mechanism, same empty graph)

The **MCP server** is not the REST `/messages` server — but it has its own
asynchronous **episode queue**. `add_memory`/`add_episode` enqueues the episode
(the worker logs `Starting episode queue worker for group_id ...`) and **returns
success to the MCP client immediately**; extraction + embedding + the Neo4j write
run in a **background worker**. If that worker throws, the client already saw
success and the graph stays empty — no error reaches the client.

So a totally-empty graph on the MCP path is almost always a **silent
background-worker failure**. The real error is in the **MCP server's own
stderr / container logs**, not the client. Read those first. Most common causes:

- **Embedder fails in the background.** The embedder is separate from the LLM and
  defaults to OpenAI. With Anthropic as the LLM but no valid `OPENAI_API_KEY`
  (or a local embedder), the embedding step throws and the episode never
  persists. Issue **#1116**: the OpenAI provider **ignores `api_base`** and falls
  back to the official API → **401 with Ollama / a local embedder** — the most
  common "empty on MCP".
- **`group_id` mismatch.** `add_memory` without an explicit group writes to the
  default **`main`**; inspecting a different group looks empty. Check what was
  actually written:
  `MATCH (n) RETURN DISTINCT n.group_id AS group, count(*) ORDER BY count(*) DESC`.
- **429 / 401 / 400 in the queue** — rate-limit or auth during background
  processing → silent non-persist.

**Fix / workaround (MCP):** read the server logs to find the thrown error;
provision a valid embedder (real `OPENAI_API_KEY`, or a local embedder whose
`api_base` is actually honored — watch #1116); pass an explicit `group_id` and
inspect that same group; confirm the server's `NEO4J_URI`/database is the one you
open.

## Cause B — extraction / embedder returned empty (common with Anthropic)

The episodic node saves but no entities/edges appear. Causes:

- **Embedder not configured.** Anthropic provides **no embeddings** — Graphiti
  still needs an embedder (OpenAI, or a local OpenAI-compatible endpoint like
  Ollama `nomic-embed-text`). Setting only `ANTHROPIC_API_KEY` and no embedder
  means entity nodes cannot be created. This is the #1 Anthropic gotcha.
- **`max_tokens` truncates extraction** (issue #763): clients pin 8192 and
  ignore a higher `LLMConfig.max_tokens`, so the structured-output JSON gets cut
  → "could not parse response" → zero entities (issue #871).
- **Structured-output reliability:** Graphiti depends on schema-valid JSON for
  extraction/dedup; weak/small models emit malformed JSON → ingestion failures.

**Fix / workaround:**
- Configure an embedder: `OPENAI_API_KEY` for OpenAI embeddings, or a local
  OpenAI-compatible embedder. Required even when the LLM is Anthropic.
- Raise `max_tokens` so extraction JSON is not truncated.
- Use a capable model for extraction; verify it returns schema-valid JSON.
- If calling the library, **`await` the call** — an un-awaited `add_episode`
  silently persists nothing.
- Ensure Neo4j 5.26+; tune `SEMAPHORE_LIMIT` for concurrency.

## Maintenance status (why this matters for the decision)

This is a **long-standing, low-priority** area, not a one-off. Issue #566 was
opened **2025-06-08** and is **still OPEN ~a year later** with no assignee, label,
milestone, linked PR, or visible maintainer response. It is one of a recurring
family of MCP/ingestion issues spanning many releases: #325/#450 (mid-2025) →
#566 (Jun 2025) → #871 (Aug 2025) → #1062 / #1116 → #1469 (`graphiti-core`
0.29.0, 2026).

Split by layer: **`graphiti-core` is actively maintained** (frequent releases);
the **OSS MCP server is a reference/example surface whose hardening lags** —
Zep's commercial focus is the hosted product, and the community routed around
the queue bug with forks rather than an upstream fix. Decision implication: build
on the maintained core (synchronous, awaited writes), not the neglected
MCP-server async queue. If depending on the wrapper at all is unacceptable,
switching to a more battle-tested store (Mem0) or a files-as-truth store (Basic
Memory) is a legitimate call.

## Community forks that address this

The silent-non-persist problem drove community forks. Ranked by "fixes the bug
AND actively maintained" (commit recency checked 2026-06):

- **`michabbb/graphiti-mcp-but-working`** — **recommended working+active pick.**
  Directly fixes the MCP queue persistence class: replaces the in-memory queue
  with a **Redis-backed persistent queue** (BRPOPLPUSH, survives crashes/restarts
  — the "1-2 episodes after a reboot then nothing" pattern), adds
  **`get_queue_status`** + `list_group_ids` so silent drops become visible,
  graceful shutdown (SIGTERM/SIGINT), token auth, health checks; a complete
  working server on current Graphiti core. Last commit **2026-06-02** (plus a
  Dec-2025 cluster). Caveat: small (9★, single maintainer) → bus-factor.
  `docker compose up` brings up Neo4j + server on `/mcp` + `/sse`.
- **`FalkorDB/graphiti`** — **company-backed, actively maintained** (Jan-Feb 2026
  activity, 750 commits, open PRs); ships an MCP server and is heavily documented
  for Graphiti+FalkorDB. Best institutional longevity, but its value-add is the
  FalkorDB backend, not an MCP-queue rewrite — **verify persistence yourself**
  (it may inherit the upstream async queue).
- **`mandelbro/graphiti-memory`** — first-class **Ollama for LLM and embeddings**
  (`--ollama-embedding-model`, default `nomic-embed-text`, dim 768; CLI/env/YAML),
  which sidesteps the #1116 OpenAI-fallback embedder trap.
- `rawr-ai/mcp-graphiti` — multi-project DX, but **stale (last commit 2025-07-23)**
  and does not address persistence. Avoid for "active".

Diagnostic shortcut: run `michabbb/graphiti-mcp-but-working`, add an episode,
call `get_queue_status` + a read-back search — it shows immediately whether jobs
queue and die in the background (→ embedder/auth cause) or never enqueue at all.

For production, the most robust path remains `graphiti-core` directly
(synchronous awaited writes, no queue); use an MCP fork only as the agent-facing
front door.

## Integration implication

For the Geniro integration, prefer the **core library (awaited) or the MCP
server** over the REST `/messages` async queue until #566 is confirmed fixed in
the pinned version, and always provision an embedder alongside the Anthropic LLM.
Add a post-write verification (the Cypher count above, or a read-back search) to
the integration's smoke test so a silent non-persist is caught immediately.

## Sources

- #566 (202 but no persist; async worker not started): https://github.com/getzep/graphiti/issues/566
- #345 (SSE ServerSession validation): https://github.com/getzep/graphiti/issues/345
- #763 (max_tokens not respected): https://github.com/getzep/graphiti/issues/763
- #871 (add_episode invalid JSON / index out of range): https://github.com/getzep/graphiti/issues/871
- #1153 (neo4j data write error): https://github.com/getzep/graphiti/issues/1153
- #1116 (OpenAI provider ignores api_base → 401 with local/Ollama embedder): https://github.com/getzep/graphiti/issues/1116
- MCP server (async episode queue, env, group_id default 'main'): https://github.com/getzep/graphiti/blob/main/mcp_server/README.md
- LLM configuration (Anthropic needs OpenAI for embeddings/reranking): https://help.getzep.com/graphiti/configuration/llm-configuration
- Fork `graphiti-mcp-but-working` (Redis persistent queue + get_queue_status): https://github.com/michabbb/graphiti-mcp-but-working
- Fork `graphiti-memory` (Ollama LLM + embeddings): https://github.com/mandelbro/graphiti-memory
- Fork `rawr-ai/mcp-graphiti` (multi-project DX): https://github.com/rawr-ai/mcp-graphiti
