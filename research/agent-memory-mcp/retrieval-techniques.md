# Retrieval techniques over knowledge graphs — what beats plain vector search

Research on token-efficient, high-recall retrieval over knowledge graphs / DBs
for AI agents, and what Graphiti already gives us for it. Informs the Graphiti
integration (`graphiti-integration-plan.md`).

## Headline

Modern KG retrieval beats naive vector top-k **not by replacing it but by fusing
it** with keyword (BM25) + graph traversal, then reranking — and by **limiting
graph expansion** so token budgets stay small. Vector RAG and GraphRAG are
complementary, not rivals.

## Verified findings

| # | Finding | Confidence |
|---|---|---|
| 1 | **Neither vector RAG nor GraphRAG universally wins.** Vector is best/tied on single-hop factual lookup; graph wins on multi-hop reasoning + corpus-level summarization; **combining the two improves over either alone** (arXiv 2502.11371, 2506.05690; HybridRAG 2408.04948). | high |
| 2 | **Entity-centric graph traversal (Personalized PageRank) is the clearest token win.** NodeRAG: MuSiQue 46.29% @ **5.9k tok** vs GraphRAG 41.71%/6.6k, LightRAG 36%/7.4k; HotpotQA 89.5% @ **5.0k tok** vs GraphRAG 89%/6.6k. Shallow PPR (alpha=0.5, t=2) over heterogeneous node types localizes relevance (arXiv 2504.11544). | high |
| 3 | **TERAG: ≥80% of graph-RAG accuracy at 3-11% of the output tokens (89-97% cut, ~9-33×)** via PPR at retrieval, no extra LLM calls (arXiv 2509.18667). ⚠️ The savings are **graph-construction/indexing** output tokens, not query-time. | high |
| 4 | **What beats plain semantic search = cascaded hybrid:** high-recall 1-hop traversal from seed entities ∥ dense vector search → fused via **RRF**. ~12% context-precision improvement over dense vector (arXiv 2507.03226). | high |
| 5 | **Graphiti ships exactly this stack.** Default `search()` = semantic + BM25 + graph traversal, reranked by **RRF**; prebuilt configurable **search recipes** (`SearchConfig` presets) across **Edge / Node / Community** scopes, each pairable with reranker {`rrf`, `mmr`, `node_distance`, `episode_mentions`, `cross_encoder`}. Verifiable in `graphiti_core/search/search_config_recipes.py`. | high |
| 6 | **node-distance (ego-graph) reranking:** `search(query, focal_node_uuid)` reorders by graph proximity to a focal entity — facts about the target entity rank above globally-similar but unrelated facts. This is the NodeRAG/PPR locality principle, built in. | high |
| 7 | **Token-cheap + fast by design:** sub-second retrieval (P95 ~300ms; 155-162ms on LoCoMo/LongMemEval) because Graphiti does **no query-time LLM summarization** (vs Microsoft GraphRAG's seconds-to-tens-of-seconds per-query community summarization). Corroborated by an independent Neo4j blog. | high |
| 8 | **Bi-temporal graph:** facts invalidated (not deleted) with validity intervals → bi-temporal filtering beyond static document RAG (arXiv 2501.13956). | high |
| 9 | **MCP server tools:** `add_episode`/`add_memory`, `search_nodes`, `search_facts`/`search_memory_facts`, `get_episodes`, `delete_episode`, `clear_graph`, `add_triplet`, `build_communities`. Transports: stdio / SSE / HTTP. | high |
| 10 | **Zep (on Graphiti) benchmarks:** DMR 94.8% vs MemGPT 93.4%; LongMemEval +18.5% accuracy / −90% latency vs full-context (arXiv 2501.13956). | medium (vendor self-benchmark, narrow margins) |

## How to apply it — pick the recipe per query type

The single most actionable result: **token efficiency and recall come from
choosing the right search recipe + bounding graph expansion**, not from a bigger
top-k. Map query intent → recipe:

| Query intent | Recipe / call | Why it's token-efficient |
|---|---|---|
| Specific single-hop fact ("what is X's value") | Edge hybrid + RRF (default `search()`) | Vector+BM25 fusion, no traversal blow-up |
| Everything about an entity ("context for user U") | Node/edge hybrid + **`node_distance`** with `focal_node_uuid` | Localizes to the ego-graph; drops globally-similar noise |
| Multi-hop reasoning ("how does A relate to C") | Hybrid + shallow graph traversal | Traversal supplies the hops vector search misses |
| Global / corpus-level sensemaking | Community search recipes (`COMMUNITY_HYBRID_SEARCH_*`) | Pre-built communities vs per-query summarization |
| Diversity needed (avoid near-dupes) | reranker `mmr` | Maximal-marginal-relevance trims redundant facts |
| Precision-critical | reranker `cross_encoder` | Higher accuracy at higher per-result cost |

Bound the expansion (shallow hops, focal-node localization) — that is the
NodeRAG/TERAG lesson and what keeps retrieval at ~5-6k tokens instead of GraphRAG's
larger budgets.

## For Geniro's two surfaces

- **Plugin (MCP):** the knowledge-retrieval read path picks a recipe by intent —
  `node_distance` with a focal entity for "context about X", edge-hybrid+RRF for a
  fact lookup, community for "summarize what we know about area Y". No query-time
  LLM means it stays cheap enough to call on every task.
- **Genera (REST):** same recipe-per-intent routing over `graph_service` search,
  scoped per tenant; bi-temporal filters for "what was true at time T".

## Caveats

- Strongest numbers (Zep DMR/LongMemEval) are vendor self-benchmarks with narrow
  margins — directional, not independently replicated.
- NodeRAG / TERAG are single-paper preprints, not replicated.
- TERAG's 89-97% savings are **indexing** tokens, not query-time retrieval.
- Two granular benchmark figures were refuted in verification — cite the general
  magnitudes (e.g. "~12% context-precision improvement"), not specific table pairs.
- **`group_id` hard tenant isolation is not confirmed by a primary source** —
  verify against Graphiti docs/source before relying on it for multi-tenant
  isolation (open question).
- Graphiti's query-time retrieval token count has not been measured head-to-head
  vs NodeRAG/TERAG/plain vector — measure it in your own benchmark.

## Sources

- RAG vs GraphRAG systematic eval: https://arxiv.org/pdf/2502.11371
- When to use Graphs in RAG: https://arxiv.org/html/2506.05690v3
- NodeRAG: https://arxiv.org/pdf/2504.11544
- TERAG: https://arxiv.org/pdf/2509.18667
- Towards Practical GraphRAG (cascaded 1-hop + RRF): https://arxiv.org/html/2507.03226v3
- Zep/Graphiti paper: https://arxiv.org/abs/2501.13956
- Graphiti search docs: https://help.getzep.com/graphiti/working-with-data/searching
- Graphiti search recipes (source): https://github.com/getzep/graphiti/blob/main/graphiti_core/search/search_config_recipes.py
- Graphiti MCP server: https://github.com/getzep/graphiti/blob/main/mcp_server/README.md
- LazyGraphRAG (cost/quality): https://www.microsoft.com/en-us/research/blog/lazygraphrag-setting-a-new-standard-for-quality-and-cost/
