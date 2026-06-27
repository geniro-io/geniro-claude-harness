# Graphiti vs Mem0 — for Geniro

Two different memory philosophies. Pick by storage model and by whether you need
a ready end-user management UI.

## Side by side

| Axis | Mem0 (self-hosted) | Graphiti |
|---|---|---|
| Storage model | Vector-first (Qdrant) + extracted facts; optional graph (Mem0g) | Bi-temporal knowledge graph (FalkorDB / Neo4j) |
| Core idea | "Remember salient facts/preferences; retrieve the relevant ones" | "Model facts as a temporal graph; track when each became true/false" |
| Retrieval | Hybrid semantic + BM25 + entity → flat list of facts | semantic + BM25 + graph traversal → connected subgraph |
| Temporal model | Basic recency | Bi-temporal: valid-time + transaction-time; supersede, never delete |
| Relationships | Entity linking influences ranking; no traversal | First-class edges; multi-hop traversal |
| Ops weight | API + Qdrant + Postgres | FalkorDB (single bundled container) or Neo4j |
| End-user UI | Memory dashboard: CRUD, filter/sort, pause/archive, per-app access, audit logs (`:3000`) | Graph-explorer UI (FalkorDB browser) — explore the graph, not manage memories |
| MCP | Yes (SSE): `add_memories`, `search_memory`, `list_memories`, `delete_all_memories` | Yes (HTTP `:8000/mcp/`): episode/entity management, semantic/hybrid search |
| License | Apache 2.0 | OSS |
| Best when | Simple facts/preferences; want a ready management UI; light ops | Relationships + time matter; evolving/contradicting facts |

## What decides it for Geniro (API-first, own UI)

The plan is API-first: you build the UI yourself (`api-first-integration.md`), so
the ready dashboard is irrelevant and the decision is purely the **memory model
and how modern the technique is** — not the UI.

Both expose a REST API + an MCP server + docker-compose, so the wiring is the
same shape either way. The difference that matters:

- **Graphiti** is the more advanced/modern architecture — a bi-temporal
  knowledge graph with LLM contradiction detection + fact invalidation,
  real-time incremental updates (no batch recompute), and hybrid
  semantic+BM25+graph-traversal retrieval. It matches a graph-shaped product
  memory and gives per-tenant `group_id` isolation. Cost: Neo4j/FalkorDB ops,
  Python-centric.
- **Mem0** is the simpler, lighter vector-first technique (extract facts → embed
  → hybrid recall, optional graph), with the broadest SDKs and built-in API-key
  auth. Cost: a more conventional model with weaker temporal/relational reach.

## Mapping onto Geniro's memory layers

- `learnings.jsonl` (L2 episodic) is already an event log with supersede chains
  + trust + recency scoring. **Mem0 maps onto L2 almost 1:1** and adds semantic
  retrieval + the management UI — the smallest conceptual jump from the current
  store.
- Graphiti is a richer model (temporal graph) and a bigger shift; it would
  subsume L2 *and* parts of L3 (entity relationships) but at higher ops cost and
  with no ready user-facing management surface.

## Recommendation

For an API-first build where the product memory is graph-shaped and you want the
more modern technique, lean **Graphiti** (bi-temporal graph + `group_id`
multi-tenancy, exposed via REST + MCP). Choose **Mem0** when you want the
simplest vector-first store with the broadest SDKs and lightest ops, and don't
need temporal/relational reasoning. The plugin/platform wiring is the same shape
either way — only the endpoint and tool names change. Benchmark both on your own
data before committing (`benchmarks.md`).
