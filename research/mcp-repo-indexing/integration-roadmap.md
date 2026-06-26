# Integration roadmap — auto-supporting a code-graph MCP

How the plugin would automatically use a code-graph MCP (codebase-memory-mcp /
GitNexus), gated so it activates only where it pays off.

## Status

```
[DONE] Repo-profile gate — lib/repo-profile.sh + tests + skills/_shared/repo-profile.md
[ ] 1. MCP availability probe   — is mcp__<graph>__* registered this session
[ ] 2. Optional-dependency row  — document it in CLAUDE.md §Optional MCP Dependencies
[ ] 3. Index lifecycle          — build/refresh the graph (hardest)
[ ] 4. Agent/skill wiring       — explorer + regressions + architecture, gated, grep fallback
[ ] 5. Shared contract          — _shared/graph-retrieval.md (gate -> probe -> tool map -> degradation)
[ ] 6. /setup integration       — offer to configure the MCP on graph-beneficial repos
[ ] 7. Tests + safety
```

Suggested order: 2 + 1 + 5 (small, unblock everything) → 4 (wire the explorer) →
3 (lifecycle) → 6 (/setup).

## The hard part — index lifecycle (item 3)

- **Non-destructive indexing.** GitNexus `analyze` overwrites `CLAUDE.md`/`AGENTS.md`
  and registers hooks — it must never run against a consumer repo root. Pin an
  index-only mode into an isolated dir. codebase-memory-mcp's `cli
  index_repository` is non-destructive (writes to `~/.cache/...`).
- **Freshness.** The graph staleness on each commit maps onto the existing
  fingerprint-drift mechanism (`lib/load-semantic.sh` `.fingerprint.json`):
  drift → incremental refresh (`detect_changes`).
- **Trigger.** Build on first `graph-beneficial` session where the MCP is
  present; refresh incrementally. SessionStart hook or a Phase-1 step, gated by
  profile + availability.

## "Automatic" has a ceiling

The plugin cannot silently install a third-party MCP / binary — that is a
supply-chain risk and against the plugin's safety posture. The ceiling is:
auto-detect-need + auto-use-when-present + **offer** to configure (write the
`.mcp.json` entry on a `graph-beneficial` repo, with user approval).

## What a graph replaces beyond search

All conditional on `graph-beneficial`; on doc-heavy/small repos these stay grep.

### Full replacements (graph strictly better on code-dense repos)

| Graph op | Current step (grep emulation) | Where |
|---|---|---|
| `impact` / callers | Caller-blast: architecture-criteria.md §1.5 ("Grep `<symbol>` finds all callers") | /review architecture |
| `impact` / callers | Symbol-deletion blast-radius: regressions-criteria.md §1 | /review regressions |
| caller count → severity | Change Impact Scoring (refactor-patterns.md): 1-3 LOW / 4-9 MED / 10+ HIGH | /review, /refactor |
| reverse-deps | "imported by 30+ files" leverage; repeated cross-call orchestration | /refactor |
| dead-code (unreachable nodes) | "Grep for unused vars, unreachable branches, orphaned functions" | /refactor |
| `get_architecture` / `generate_map` | The whole `_CODEBASE_MAP.md` (module graph, entry points, critical paths) | /onboard |
| `trace` / call-chain | Root-cause trace "where did this value originate" | /debug |

### Augment, not replace

- Parallel-path symmetry (regressions §4) — graph finds siblings; "share the invariant?" needs reading.
- In-repo reuse audit (existing-abstraction-audit, explorer REUSE/EXTEND/NO-ANALOGUE) — semantic helps recall; the decision needs reading.
- Risk surface / change-scope (explorer) — impact part only.

### Graph adds (not present today)

- `detect_changes` — diff-impact in one call.
- `route_map` — HTTP route tracing.
- `pdg_query` — program-dependence (data flow).
- `generate_map` — Mermaid architecture diagrams (today `/plan` draws them by hand).

### Not replaceable by a graph (keep as-is)

- Intent-vs-behavior over-reach (needs spec/PR semantics).
- Test-coverage delta (diff analysis).
- Regression provenance (`git blame`).
- External library audit (registry, not code graph).
- Markdown coupling (prose refs — graph is blind; this repo's dominant case).

## Target MCP

`codebase-memory-mcp` (MIT, static binary, headless, non-destructive index,
CLI + Cypher) is the recommended target over GitNexus for automation. The
plugin architecture is identical either way — only the `mcp__<graph>__*` tool
prefix changes.
