# Landscape — repo-indexing / code-graph MCP servers

Four architecturally distinct ways to give an AI agent understanding of a repo.
There is no single winner; effectiveness depends on the query type.

| Approach | What it does | Strong at | Weak at |
|---|---|---|---|
| **Knowledge graph (AST)** | Parses code into a graph of functions/classes → calls/imports/inheritance | Relational queries, blast radius, impact | Needs an index phase; blind to prose coupling |
| **LSP / symbol** | Uses language servers (like an IDE) for exact references | Exact, canonical refs; editing | Depends on LSP servers per language |
| **Vector RAG (embeddings)** | Semantic search over embedded code chunks | Name-unknown "find code that does X" | Approximate; needs a vector store |
| **Context packing / repo-map** | BM25+vector+structure, or a Tree-sitter repo map | Balance of precision and coverage | Varies by implementation |

## Knowledge-graph engines (the category matching "Nexus")

| Tool | License | Notes |
|---|---|---|
| **CodeGraph** | MIT | ~47k stars; embedded SQLite; 21 languages; ~91% solo commits (concentration risk). |
| **GitNexus** | PolyForm NC | ~42k stars; LadybugDB; 16 MCP tools (impact/rename/detect_changes/generate_map). `analyze` overwrites `CLAUDE.md`/`AGENTS.md` + registers hooks. Native bindings did **not** run headless in the cloud sandbox. Non-commercial license. |
| **codebase-memory-mcp** | MIT | Single static binary, zero deps, **runs headless**. 158 langs via tree-sitter + "Hybrid LSP" for 9. Persistent SQLite graph; team `.codebase-memory/graph.db.zst` snapshot. CLI + Cypher. PreToolUse hook enriching grep/glob. **Best automation fit.** |
| **CodeGraphContext** | MIT | Pluggable backends (FalkorDB / KuzuDB / Neo4j). |
| **code-graph-mcp** (sdsrss) | — | Call-graph traversal, route tracing, impact; 10 langs. |
| **Axon** | MIT | WebGL viz; **abandoned** (no commits since Mar 2026). |

## LSP / symbol

| Tool | License | Notes |
|---|---|---|
| **Serena** | MIT | ~25k stars; LSP-based exact refs + symbol-level editing; 40+ langs. Strongest non-graph alternative; supports editing, not just retrieval. |
| **Octocode MCP** | MIT | Symbol search + "PR archaeology"; 14 tools. |

## Vector / semantic RAG

| Tool | License | Notes |
|---|---|---|
| **claude-context** (Zilliz) | MIT | Hybrid BM25 + vector; OpenAI/Voyage/Ollama/Gemini embeddings; Milvus/Zilliz. Cloud-leaning by default. |
| **CocoIndex Code** | — | AST-aware; local SentenceTransformer (no API key); incremental. |
| **codesearch** (flupkede) | — | Rust; multi-repo; vector+BM25+RRF; offline; 16 langs. |
| **grepai** | MIT | Hybrid vector + call-graph; 100% local via Ollama. |

## Context packing

| Tool | Notes |
|---|---|
| **Repomix** | ~26k stars; packs a repo into one file; ~70% tree-sitter compression. |
| **Aider repo-map** | Tree-sitter signatures + PageRank to prioritize symbols. Structural, not embeddings. |

## Commercial / SaaS

| Tool | Notes |
|---|---|
| **Sourcegraph Cody / MCP** | Cross-repo, SCIP index, RAG. Enterprise. |
| **Greptile** | Builds a semantic graph; AI code review with architectural impact. YC. |
| **Augment Context Engine** | Closed-source MCP; local + cloud modes; vendor-claimed 70%+ gains. |
| **DeepWiki** | Free cloud AI docs for public GitHub repos. |

## Sources

- Ry Walker — Code Intelligence Tools Compared: https://rywalker.com/research/code-intelligence-tools
- GitNexus: https://github.com/abhigyanpatwari/GitNexus
- codebase-memory-mcp: https://github.com/DeusData/codebase-memory-mcp
- Serena: https://github.com/oraios/serena
- claude-context: https://github.com/zilliztech/claude-context
- Sverklo, 12 MCP compared: https://sverklo.com/blog/practical-guide-mcp-code-intelligence/
