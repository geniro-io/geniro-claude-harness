# Agent-memory MCP research

Self-hostable (Docker), MCP-compatible long-term memory for an AI agent — for
wiring into Claude Code / the Geniro plugin, and as a candidate to replace a
hand-written memory store with a ready MCP + an end-user management UI.

Companion to `../mcp-repo-indexing/` (that one is code-graph/search; this one is
agent memory). Committed so the experiments can be re-run from any machine.

> **Decision: Graphiti** is the chosen engine — to be integrated into both the
> Genera product memory (REST + FalkorDB, per-tenant `group_id`) and the Geniro
> plugin (optional MCP backing L2/L3, gated with fallback). Plan:
> `graphiti-integration-plan.md`.

## TL;DR

- The two leading self-hostable options are **Mem0 (self-hosted server)** and
  **Graphiti**. They are different memory philosophies, not better/worse.
- **Mem0** — vector-first (Qdrant) + LLM fact extraction; hybrid
  semantic+BM25+entity retrieval; **ships an end-user memory-management
  dashboard** (CRUD memories, pause/archive, per-app access, audit) at
  `localhost:3000`; Apache 2.0; lighter ops. The old **OpenMemory** name is
  **deprecated** — use the unified Mem0 self-hosted server (`cd server && make
  bootstrap`), which now carries the dashboard.
- **Graphiti** — bi-temporal knowledge graph (FalkorDB/Neo4j); facts carry
  validity windows (valid-time + transaction-time) and are superseded, not
  deleted; semantic+BM25+graph-traversal retrieval; ships a graph-explorer UI,
  not a memory-management console; FalkorDB bundles into a single container.
- **For Geniro's API-first plan** (custom UI you build yourself → your backend
  over REST, and agents over MCP — no ready dashboard): both expose REST + MCP +
  docker-compose, so the choice is **model-driven**, not dashboard-driven. See
  `api-first-integration.md`. **Graphiti** is the more modern/advanced technique
  (bi-temporal knowledge graph, fact invalidation, real-time incremental, graph
  traversal) and fits a graph-shaped product memory + per-tenant `group_id`;
  **Mem0** is the simpler, lighter vector-first option with the broadest SDKs.

## Why a dedicated memory system over DIY embeddings + vector search

Verified (3-0) under adversarial review. Flat vector similarity gives only
"similar chunks by cosine." A dedicated memory system adds:

| Capability | What it does | Why flat vector search can't |
|---|---|---|
| LLM fact extraction | Pulls atomic facts from raw text | Vector stores text as-is, extracts nothing |
| Conflict resolution / invalidation | New fact checked against similar old ones; contradictions marked invalid | Cosine returns both contradictory chunks |
| Bi-temporal graph | Each edge has valid-time + transaction-time; history preserved | Vectors have no time axis |
| Entity linking | Facts tied to entities; relations affect ranking/traversal | Chunks are isolated |
| Hybrid retrieval | semantic + BM25 + graph/entity in one score | One signal only; exact matches lost |

Second differentiator — tokens: Mem0 reports ~26K → ~7K tokens per conversation
by retrieving only relevant memories (vendor figure, medium confidence).

## Benchmarks — read `benchmarks.md`, but do not select on them

Almost all LoCoMo/LongMemEval numbers are vendor self-reported and collapsed
under verification (e.g. the Zep-vs-Mem0 LongMemEval gap was refuted; a Mem0
"92.5 LoCoMo" combined claim was refuted). Treat "most effective" as a
capability + self-hostability judgment. Run your own benchmark — see
`benchmarks.md` for the method.

## Files

| File | Contents |
|---|---|
| `graphiti-vs-mem0.md` | Focused head-to-head and which fits Geniro. |
| `setup-mem0-selfhosted.md` | Docker bring-up + Claude Code MCP wiring + dashboard. Recommended path. |
| `setup-graphiti-falkordb.md` | Docker bring-up (FalkorDB single container) + MCP wiring. Alternative. |
| `benchmarks.md` | Disputed-number caveats + how to run your own LoCoMo/LongMemEval. |

## Sources

- Introducing OpenMemory MCP (now folded into Mem0 self-hosted): https://mem0.ai/blog/introducing-openmemory-mcp
- Self-hosting Mem0 (Docker): https://mem0.ai/blog/self-host-mem0-docker
- Mem0 paper (arXiv 2504.19413): https://arxiv.org/abs/2504.19413
- Graphiti: https://github.com/getzep/graphiti
- Graphiti MCP server README: https://github.com/getzep/graphiti/blob/main/mcp_server/README.md
- Graphiti MCP + FalkorDB: https://docs.falkordb.com/agentic-memory/graphiti-mcp-server.html
- Zep paper (arXiv 2501.13956): https://arxiv.org/abs/2501.13956
