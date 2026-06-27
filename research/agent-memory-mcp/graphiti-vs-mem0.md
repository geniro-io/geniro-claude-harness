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

## The one difference that decides it for Geniro

Geniro's two goals:

1. **MCP memory the plugin/Claude can query** — both deliver this. Mem0 is
   lighter (a vector store vs running a graph DB).
2. **A UI wrapper where the end user manages their own memory, on a ready MCP,
   instead of a hand-written store** — **Mem0 self-hosted ships exactly that
   dashboard**: create/view/update/delete memories, filter by app/category/date,
   pause/archive, revoke a client's access, audit every read/write. Graphiti's UI
   is a *graph explorer*, not a memory-management console — you would build that
   dashboard yourself.

So **Mem0 self-hosted** covers both goals out of the box. Choose **Graphiti**
only if the memory genuinely needs temporal/relationship reasoning — "what did
the user believe about X at time T", evolving project facts that supersede each
other — and you accept Neo4j/FalkorDB plus building your own management UI.

## Mapping onto Geniro's memory layers

- `learnings.jsonl` (L2 episodic) is already an event log with supersede chains
  + trust + recency scoring. **Mem0 maps onto L2 almost 1:1** and adds semantic
  retrieval + the management UI — the smallest conceptual jump from the current
  store.
- Graphiti is a richer model (temporal graph) and a bigger shift; it would
  subsume L2 *and* parts of L3 (entity relationships) but at higher ops cost and
  with no ready user-facing management surface.

## Recommendation

Default to **Mem0 self-hosted** for the Geniro memory wrapper. Keep Graphiti as
the upgrade path if temporal reasoning becomes a first-class requirement. Either
way the plugin wiring is the same shape — only the MCP endpoint and tool names
change. Benchmark both on your own data before committing (`benchmarks.md`).
