# Benchmarks

## External benchmarks (published)

| Benchmark | Compared | Result |
|---|---|---|
| **ContextBench / Turbopuffer** (50 tasks, independent) | baseline vs grep vs semantic | Precision (wasted file reads): baseline 1-in-3 → grep 1-in-5 → semantic 1-in-8. Recall: semantic ≈ grep, sometimes slightly worse. |
| **GrepRAG** (arXiv 2601.23254) | grep vs vector RAG, definition lookup | grep EM 38.6% vs Vanilla RAG 25.0% — for exact identifier lookup, grep beats vectors. |
| **codebase-memory** (arXiv 2603.27277, 31 repos, Opus 4.6) | graph MCP vs grep-explorer | Graph 83% answer quality vs 92% explorer (graph **loses** on quality) but 10× fewer tokens, 2.1× fewer tool calls. Graph matched/beat explorer on relational queries (hubs, caller ranking) on 19/31 langs. |
| **RepoGraph** (arXiv 2410.14684, SWE-bench-Lite) | agent vs agent+graph, real issue resolution | +32.8% avg relative resolve-rate gain; RAG+graph +99.6%; SOTA 29.67%. |
| **grepai** (maintainer, Excalidraw 155k LOC) | semantic vs grep | 97% input-token reduction, 27.5% cost savings. |
| **Sverklo, 12 MCP** | head-to-head F1 | "well-tuned ripgrep ties most graph servers" on reference finding (~0.50 F1). Author verdict: "there is no best." |

**Synthesis:** the strongest configuration is hybrid (BM25 + vector + graph with
RRF). Graph payoff concentrates on relational / blast-radius / semantic queries
and end-to-end resolve; grep already wins exact-identifier lookup; the published
graph wins were measured on large, code-dense codebases (Django-scale, kernel).

## Measured here — this plugin repo

Composition (this repo): **134 Markdown files / 28,229 lines vs 69 shell files /
15,670 lines** → ~37% code by lines. Coupling is dominated by Markdown
cross-references (a skill `.md` naming a helper by path), which an AST graph
cannot represent.

### Blast-radius head-to-head (exact symbols)

The "would-need-attention on change" set = every file referencing the symbol.

| Symbol | True coupling | Code-graph (AST, shell only) | Grep (1 query) |
|---|---|---|---|
| `atomic_state_write` | 52 files (10 sh + 42 md) | 19% (10/52) — blind to 42 md refs | 100% |
| `_geniro_repo_root` | 23 files (15 sh + 8 md) | 65% (15/23) | 100% |
| `query_learnings` | 12 files (4 sh + 8 md) | 33% (4/12) | 100% |

Transitive chains: the graph's only edge over grep here is multi-hop
reachability. For the deepest helper the closure is 3 hops — 1 graph traversal
vs ~3 sequential greps. Marginal on a 34-function shell layer.

### Real `codebase-memory-mcp` run (v0.8.1)

Indexed a clean copy of this repo: **214 files → 3,522 nodes / 4,168 edges in
0.73 s**, headless (GitNexus did not run headless at all).

Graph composition (`get_architecture`): 4,168 edges, of which only **480
`CALLS`**; **1,898 of 3,522 nodes are `Section`** (Markdown headings, not code).
Languages: Bash 71 files + YAML.

Blast-radius for `atomic_state_write`, real tool vs grep:

| Metric | codebase-memory-mcp | grep (1 query) |
|---|---|---|
| Callers found | **5** (via Cypher `query_graph`) | **11 files / 56 call-sites** (exact) |
| `file:line` locations | **`null:null`** — symbol found, no location | exact `path:line` |
| Markdown references (42 files) | **0** | all |
| `trace_path direction=callers` | returned **0** (callers only surfaced via `both` / Cypher) | — |

**Conclusion:** on this Bash+Markdown repo the graph **loses to grep** — confirmed
with the actual product, not just the hand-computed graph. The shell call-edge
extraction is incomplete (5 of 11 callers) and it is blind to doc coupling. This
is exactly what `lib/repo-profile.sh` predicts (`grep-sufficient`, doc-heavy).

### Not yet measured — the "graph wins" zone

`geniro-io/geniro` (TypeScript app) is the inverse profile where the published
benchmarks favor the graph. It could not be cloned in the cloud sandbox
(org-policy 403 at the egress proxy; no `add_repo` tool in-session). Re-run
`scripts/run-on-repo.sh` against it from a machine where the clone is allowed.

## How to reproduce

See `scripts/`. The blast-radius script is parameterized by repo + symbol, so the
same head-to-head runs on any repo.
