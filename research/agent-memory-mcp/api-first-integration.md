# API-first integration (no dashboard)

The intended Geniro architecture: **your own custom UI → your platform backend →
the memory server's REST API**, and **your agents / the Geniro plugin module →
the same server's MCP**. The ready-made dashboard is not used. Both Mem0 and
Graphiti support exactly this — a first-class REST API and an MCP server, both
self-hosted in your docker-compose, dashboard optional/absent.

## Dual-use, one store

```
   custom UI (your platform)
            │
            ▼
   your platform backend ──REST──►  ┌───────────────────────┐
                                    │   memory server       │
   your agents / Geniro module ─MCP─►│  (REST API + MCP)     │
                                    │   + vector/graph store │
                                    └───────────────────────┘
```

The REST API and the MCP server are two front doors to the **same** underlying
memory store. Your backend writes/reads facts over REST; your agents read/write
over MCP; both see the same memories. No dashboard container required.

## REST API surface

### Mem0 self-hosted
- FastAPI; OpenAPI/Swagger at `/docs`; default port 8000 (no `/v1` prefix in OSS).
- Endpoints: `POST /memories` (add), `GET /memories` (list/search), `GET
  /memories/{id}`, `PUT /memories/{id}` (update), `DELETE /memories/{id}`,
  reset. Scope by `user_id` / `agent_id` / `run_id` (multi-tenant per user/agent).
- Auth on by default: JWT or `X-API-Key` header — fits a platform backend.
- Stack (3 containers): FastAPI API + Postgres/pgvector (vectors) + Neo4j (graph
  variant). Vector backend is configurable (Qdrant also supported).
- Also: Python + JS/TS SDKs, and an MCP server (SSE).
- Dashboard is a **separate** frontend container — simply do not start it.
- Docs: https://docs.mem0.ai/open-source/features/rest-api

### Graphiti graph_service
- FastAPI; Swagger at `/docs`, ReDoc at `/redoc`; default port 8000.
- Endpoints for `add_episode` (ingest), `search` (semantic+BM25+graph), plus
  management. Multi-tenancy via `group_id` (one isolated graph per tenant/user).
- Stack: graph_service container + Neo4j (or FalkorDB). Docker image `zepai/graphiti`.
- Also: `graphiti-core` Python SDK, and an MCP server (HTTP `:8000/mcp/`).
- No dashboard; an optional FalkorDB graph-browser only.
- Docs: https://github.com/getzep/graphiti/blob/main/server/README.md

## docker-compose mental model

Add the memory server + its store as services in **your** compose; expose the
REST port to your backend on the internal network, expose the MCP endpoint to
your agents, and do not include the dashboard service.

```yaml
# sketch — confirm image tags/env against the official repos
services:
  memory-api:            # Mem0 FastAPI  OR  Graphiti graph_service
    image: <mem0-server>     # or zepai/graphiti
    environment:
      # fully local: point LLM + embedder at Ollama instead of OpenAI
      - OPENAI_API_KEY=${OPENAI_API_KEY:-}
    ports: ["8000:8000"]     # REST + (Graphiti) MCP
    depends_on: [memory-store]
  memory-store:
    image: pgvector/pgvector:pg16   # Mem0   |   neo4j:5.26 or falkordb/falkordb   # Graphiti
  # NO dashboard service
```

For Mem0, the MCP server rides the same API process over SSE; for Graphiti the
MCP server is at `:8000/mcp/`. Wire agents with `claude mcp add` (see the two
setup docs); wire your platform backend straight to the REST `/docs` endpoints.

## Decision — model-driven (dashboard is off the table)

Since you build the UI yourself, choose purely on memory model and ops:

| If your product's memory is… | Pick | Why |
|---|---|---|
| Facts / preferences, recall-by-similarity; multi-language backend; simplest API + built-in API-key auth | **Mem0** | Vector-first; clean REST; SDKs; lightest store (pgvector) |
| A knowledge graph with relationships and time ("what was true when", evolving facts); per-user isolated graphs | **Graphiti** | Bi-temporal graph; `group_id` multi-tenancy; graph traversal in search |

You said the product builds a graph and this is its memory — if that graph is
genuinely relational/temporal, **Graphiti** aligns with the model and gives
per-tenant `group_id` isolation out of the box. If "graph" is loose and you just
need fact recall, **Mem0** is the simpler, lighter API. Both expose REST + MCP +
compose identically, so the platform wiring is the same shape either way —
benchmark both on your data (`benchmarks.md`) before committing.

## Using it as the Geniro plugin's memory (current repo)

Same server, MCP front door, no dashboard needed here. Wire `mcp__<server>__*`
as an optional dependency the plugin uses when present and degrades from when
absent (the same gate pattern as the other optional MCPs), so the plugin's L2/L3
can be backed by the server while still working without it.
