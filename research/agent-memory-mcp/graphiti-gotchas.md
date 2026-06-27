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
- Call `await graphiti.add_episode(...)` directly via the library, or use the
  **MCP server** path, instead of the buggy async `/messages` queue; OR
- patch the server `main.py` to call `async_worker.start()` in the FastAPI
  lifespan/startup; OR pin a version where the worker start is fixed.

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
- LLM configuration (Anthropic needs OpenAI for embeddings/reranking): https://help.getzep.com/graphiti/configuration/llm-configuration
