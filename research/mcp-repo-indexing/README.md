# Code-graph / repo-indexing MCP research

Investigation into MCP servers that index a repository, build a code/knowledge
graph, and serve AI-powered retrieval — and whether wiring one into this plugin
would improve repo search and the memory layers.

This directory is the durable record so the experiments can be re-run from any
machine. It is committed (unlike `design/scratch/`, which is git-ignored).

## TL;DR

- A code-graph MCP indexes the **call graph of code** (functions / classes /
  call edges). It wins on **large, code-dense repos** where coupling IS code
  call edges, and **loses to grep** on **doc-heavy or small/shallow repos**,
  where coupling is prose cross-references an AST graph cannot see.
- Measured on this plugin repo (64% Markdown, ~16k lines of shell): for an exact
  symbol, **grep reaches 100% of coupled files in one query**; the real
  `codebase-memory-mcp` graph found only ~5 of 11 shell callers and **0 of 42**
  Markdown references, with no `file:line` locations. Grep wins here.
- The shipped gate for this is `lib/repo-profile.sh` (the **repo-profile
  detector**): it classifies a repo `graph-beneficial` / `grep-sufficient` /
  `borderline` so a skill spins up a graph MCP only where it pays off.
- **Target MCP, if integrated: `codebase-memory-mcp`** (MIT, single static
  binary, runs headless, non-destructive index, CLI + Cypher). GitNexus is a
  worse fit — its `analyze` overwrites `CLAUDE.md`/hooks and its native bindings
  did not run headless.

## Files

| File | Contents |
|---|---|
| `landscape.md` | Survey of the tools by category (graph / LSP / vector / context-pack / commercial), license, maturity. |
| `benchmarks.md` | External benchmarks + the head-to-head measured here (grep vs graph), incl. the real `codebase-memory-mcp` run. |
| `integration-roadmap.md` | What the detector already does, the remaining work to auto-support a graph MCP, and the list of pipeline steps a graph would replace beyond search. |
| `scripts/install-codebase-memory.sh` | Install the `codebase-memory-mcp` binary to a local dir. |
| `scripts/blast-radius-benchmark.sh` | For one symbol: grep ground truth vs graph callers — the head-to-head. |
| `scripts/run-on-repo.sh` | Orchestrator: profile a repo, then (if graph-beneficial) index + benchmark. |

## Reproduce

```bash
# 1. Profile any repo (no install needed) — decides if a graph helps.
bash lib/repo-profile.sh --root /path/to/repo

# 2. Install the graph MCP locally (static binary, ~266 MB).
bash research/mcp-repo-indexing/scripts/install-codebase-memory.sh ./.cmm-bin

# 3. Full run: profile -> index -> blast-radius head-to-head for a symbol.
PATH="$PWD/.cmm-bin:$PATH" \
  bash research/mcp-repo-indexing/scripts/run-on-repo.sh /path/to/repo <symbol>
```

To test the "graph wins" zone, point step 3 at a large code-dense repo (a real
TypeScript / Python / Go application). On a public repo that is not yet in the
session's allowlist, clone it first from a machine with network access to it —
the cloud sandbox blocks out-of-scope clones with an org-policy 403.
