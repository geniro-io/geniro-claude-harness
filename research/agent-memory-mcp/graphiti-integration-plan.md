# Decision & integration plan — Graphiti

**Decision: adopt Graphiti as the agent-memory engine.** Chosen over Mem0 for the
more modern technique (bi-temporal knowledge graph, LLM contradiction detection +
fact invalidation, real-time incremental graph updates, hybrid
semantic+BM25+graph-traversal retrieval) and because it matches a graph-shaped,
multi-tenant product memory with `group_id` isolation — exposed via both REST and
MCP, self-hosted, no forced dashboard. Store: **FalkorDB** (single container,
lightest way to run the graph). Trade-off accepted: heavier ops than vector-first
and higher per-write LLM cost (extraction + contradiction detection).

Setup details: `setup-graphiti-falkordb.md`. API-first wiring:
`api-first-integration.md`. Benchmark before/while integrating: `benchmarks.md`.

## Two integration surfaces

Graphiti is integrated in two places that share one running server (or one
deployment pattern), via its two front doors — REST for backends, MCP for agents.

### A. Genera product memory (REST-first)

The product's own memory, queried by your platform backend; the custom UI you
build sits above the backend.

```
custom UI (Genera) → Genera backend ──REST──► Graphiti graph_service ──► FalkorDB
                     product agents ──MCP───► Graphiti MCP            ──► (same graph)
```

- **Run:** add `graph_service` + `falkordb` (+ optional `graphiti-mcp`) as
  services in the Genera docker-compose. Fully local: point the extraction LLM +
  embedder at Ollama (no OpenAI egress).
- **Tenancy:** one `group_id` per tenant/user → isolated graph per customer. The
  backend passes the caller's `group_id` on every `add_episode` / `search`.
- **Backend ↔ REST:** ingest with `add_episode` (conversations / events / docs),
  read with `search` (semantic + BM25 + graph traversal). OpenAPI at `/docs`.
- **UI:** entirely yours, over the backend — no Graphiti dashboard involved.

### B. Geniro plugin memory (MCP-first, optional + gated)

The plugin uses Graphiti as an **optional** memory backend for its episodic /
semantic layers, degrading to the current local stores when the server is absent
— the same graceful-degradation discipline as the other optional MCP
dependencies.

- **Register** `mcp__graphiti__*` in `CLAUDE.md` §Optional MCP Dependencies
  (tool prefix + what it enables + degrade-to-local note).
- **Availability probe + gate:** use Graphiti when its MCP tools are registered
  this session; otherwise fall back to `lib/query-learnings.sh` / `learnings.jsonl`
  (L2) and `_CODEBASE_MAP.md` (L3). Mirror the optional-dependency pattern and the
  `lib/repo-profile.sh` gate shape.
- **Wire points (read):** `agents/knowledge-retrieval-agent.md` — when Graphiti
  is present, query its `search` for relevant prior knowledge in addition to /
  instead of the lexical `query-learnings.sh`. Keep the local read as the fallback.
- **Wire points (write):** the L2 emit path (`lib/emit-learning.sh` callers) —
  also push an `add_episode` to Graphiti so learnings land in the graph; the
  JSONL store remains the offline fallback and audit trail.
- **Shared contract:** add `skills/_shared/graphiti-memory.md` (gate → probe →
  tool map → degradation) so skills reference one contract instead of duplicating
  logic (1-hop rule).
- **Layer mapping:** Graphiti backs **L2** (episodic learnings) 1:1 and the
  relationship/entity part of **L3**; L1 (task state) and L4 (instructions) stay
  as-is.

## Phasing

1. **Stand up + benchmark (your PC).** `setup-graphiti-falkordb.md`; run the
   `benchmarks.md` head-to-head (Graphiti vs a DIY vector baseline) on your data.
2. **Product backend (A).** Add services to the Genera compose; wire the backend
   to REST with per-tenant `group_id`; build the custom UI over the backend.
3. **Plugin MCP (B).** Register the optional dependency + probe/gate + the shared
   contract; wire the knowledge-retrieval read and the emit write; keep local
   stores as fallback.
4. **Dual-run.** Keep `learnings.jsonl` / `_CODEBASE_MAP` as the offline fallback
   and migration source while Graphiti proves out; remove nothing until B is
   validated.

## Open decisions / risks

- **Per-write cost.** Extraction + contradiction detection cost tokens/latency on
  every `add_episode`; batch low-value events or gate which learnings get pushed.
- **Local LLM quality.** Fully-local (Ollama) extraction quality must be checked —
  weak extraction degrades the graph; validate during phase 1.
- **Fallback parity.** The degraded (no-Graphiti) path must stay first-class so
  the plugin works for users who never run the server.
- **Zep CE vs Graphiti core.** Build on open Graphiti core + `graph_service` +
  MCP (actively developed); do not depend on Zep's deprecated hosted CE.
