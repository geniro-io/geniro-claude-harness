# Setup — Graphiti + FalkorDB (alternative)

Local Docker bring-up + Claude Code MCP wiring for the bi-temporal knowledge
graph. Use this when temporal/relationship reasoning is the priority. FalkorDB
is the default and is the simplest path (single bundled container).

Official: https://github.com/getzep/graphiti/blob/main/mcp_server/README.md ·
https://docs.falkordb.com/agentic-memory/graphiti-mcp-server.html

## Stack

FalkorDB (Redis-based graph DB) is bundled with the Graphiti MCP server in a
single container, plus the FalkorDB browser UI. Neo4j 5.26+ is the alternative
backend (separate container). An LLM (OpenAI by default) does entity/edge
extraction and contradiction detection.

## Bring it up (FalkorDB, single container)

```bash
git clone https://github.com/getzep/graphiti.git
cd graphiti/mcp_server

# Configure the LLM used for extraction. For a fully local stack point it at
# Ollama (OPENAI_BASE_URL=http://host.docker.internal:11434/v1 + a local model);
# otherwise set OPENAI_API_KEY.
cp .env.example .env     # then edit

docker compose up        # starts FalkorDB + FalkorDB browser + Graphiti MCP
# MCP endpoint (HTTP): http://localhost:8000/mcp/
# FalkorDB: redis://localhost:6379   browser UI: per compose (graph explorer)
```

A prebuilt image also exists: `falkordb/graphiti-knowledge-graph-mcp`.

## What the graph gives you

Every fact is an edge with four timestamps (valid-time + transaction-time). When
a new fact contradicts an existing one, the LLM marks the old edge invalid
(sets `t_invalid`) rather than deleting it — history stays queryable. Retrieval
combines semantic embeddings + BM25 + graph traversal. The UI is a **graph
explorer** (inspect nodes/edges), not a memory-management dashboard — build that
yourself if end users need CRUD over memories.

## Wire into Claude Code (MCP)

HTTP transport at `http://localhost:8000/mcp/`:

```bash
claude mcp add --transport http graphiti "http://localhost:8000/mcp/"
```

Or `.mcp.json`:

```json
{
  "mcpServers": {
    "graphiti": { "type": "http", "url": "http://localhost:8000/mcp/" }
  }
}
```

Tools cover episode management (ingest text/conversations), entity management,
and semantic/hybrid search over the graph.

## Notes / gotchas

- Heavier ops than Mem0 (a graph DB to run; OpenAI by default for extraction).
- Kuzu backend is marked deprecated upstream; FalkorDB is the recommended local
  default, Neo4j the alternative.
- No first-class end-user memory-management UI — this is the main gap vs Mem0
  for the "user manages their own memory" goal.
