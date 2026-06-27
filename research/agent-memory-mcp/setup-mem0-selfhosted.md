# Setup — Mem0 self-hosted (recommended)

Local Docker stack + Claude Code MCP wiring + the end-user memory dashboard.
Verify exact commands/ports against the official quickstart before running —
this space moves fast (the old **OpenMemory** name is deprecated; the unified
**Mem0 self-hosted server** now carries the dashboard).

Official: https://mem0.ai/blog/self-host-mem0-docker · https://docs.mem0.ai/openmemory/quickstart

## Stack

Three containers via Docker Compose: **API server** (hosts the MCP server over
SSE), **Qdrant** (vector store), **Postgres** (metadata). Optional **Neo4j** for
the graph variant. Dashboard (Next.js) on `:3000`.

## Bring it up

```bash
git clone https://github.com/mem0ai/mem0.git
cd mem0/server          # the unified self-hosted server (replaces openmemory/)

# Configure the backend. For a FULLY LOCAL stack, point the LLM + embedder at
# Ollama instead of OpenAI (otherwise extraction/embedding calls leave the box):
#   LLM_PROVIDER=ollama   EMBEDDER_PROVIDER=ollama
#   OLLAMA_BASE_URL=http://host.docker.internal:11434
# Otherwise set OPENAI_API_KEY in the backend .env.
cp .env.example .env     # then edit

make bootstrap           # or: docker compose up -d   (confirm the target in the repo Makefile)
# Dashboard: http://localhost:3000   API/MCP: see the port the server prints
```

To run the embeddings/LLM locally with Ollama: `ollama pull nomic-embed-text`
(embeddings) and a small chat model (e.g. `ollama pull llama3.1`) for fact
extraction. Mem0 supports pluggable providers via the backend config.

## Dashboard (the user-facing memory manager)

`http://localhost:3000` — create / view / update / delete memories, filter by
app / category / date, sort, set memory state (active / pause / archive), revoke
a client's access per app or per memory, with audit logs for every read/write.
This is the "user manages their own memory" surface — no custom UI to build.

## Wire into Claude Code (MCP)

The API hosts an MCP server over **SSE** exposing `add_memories`,
`search_memory`, `list_memories`, `delete_all_memories`. Take the SSE URL the
server prints on startup (per-app / per-user path), then:

```bash
claude mcp add --transport sse mem0 "<SSE_URL_FROM_SERVER>"
```

Or project-scoped `.mcp.json`:

```json
{
  "mcpServers": {
    "mem0": { "type": "sse", "url": "<SSE_URL_FROM_SERVER>" }
  }
}
```

Then Claude can call `search_memory` to fetch context and `add_memories` to
persist new facts. For Geniro, that is the "the plugin may go fetch memory here"
contract — gate it the same way as other optional MCP dependencies (use when
present, degrade gracefully when absent).

## Notes / gotchas

- Real setup can exceed the "~5 min" vendor estimate — Qdrant version /
  embedding-dimension mismatches are the common friction (mem0 issues
  #4056 / #2030). Pin the embedder dimension to your Qdrant collection.
- Fully local = Ollama for both LLM and embedder; with OpenAI the extraction
  step calls out.
- License: Apache 2.0 — safe to wrap and redistribute a UI around.
