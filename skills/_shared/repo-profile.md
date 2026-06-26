# Repo-profile detector

Decides whether a code-graph index pays off for a repository, or whether plain
grep/Read retrieval is already complete enough. Implemented by
`${CLAUDE_PLUGIN_ROOT}/lib/repo-profile.sh`; this file is its contract.

## Why it exists

A code-graph / AST-index MCP (GitNexus, codebase-memory, Serena, and peers)
indexes the **call graph of code** — functions, classes, call edges, imports.
That model wins on large, code-dense repositories where coupling IS code call
edges (the published gains were measured on Django-scale and kernel-scale
codebases). Two repo shapes defeat it, and on them grep is both more complete
and cheaper:

- **Doc-heavy repos.** Coupling lives in prose cross-references — a Markdown
  file naming a helper by path — which an AST graph structurally cannot
  represent. Measured on this plugin: for the symbol `atomic_state_write`, grep
  reaches all 52 coupled files in one exact-match query; a code-graph reaches
  only the 10 shell call-sites (19% recall) and is blind to the 42 Markdown
  contract references.
- **Small / shallow code layers.** The graph's only edge over grep is
  transitive multi-hop reachability and name-unknown semantic search. On a
  layer of a few dozen functions with call-depth ~3, that edge is marginal and
  does not justify the index + maintenance overhead.

The detector separates the two shapes so a skill activates a graph MCP only
where it helps and falls back to grep/Read everywhere else — the same
graceful-degradation discipline as the other optional MCP dependencies.

## API

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/repo-profile.sh"
repo_profile [--root <dir>] [--json]
```

Default root is the resolved repo root. Prints the measured signals and a final
verdict. Returns 0 on a clean measurement; on any failure it still prints
`verdict=grep-sufficient` and returns 0 — fail-open never forces a graph onto a
repo that could not be measured.

Default output is `key=value` lines (`verdict`, `code_share_pct`, `code_lines`,
`doc_lines`, `code_files`, `doc_files`, `symbols_est`, `reason`). `--json` emits
the same fields as one JSON object.

## Verdicts

| Verdict | Meaning | Caller action |
|---|---|---|
| `graph-beneficial` | Code-dense and large/deep enough that a graph index likely beats grep on relational / blast-radius / semantic queries. | Spin up the graph MCP if one is available; else grep. |
| `grep-sufficient` | Doc-heavy, small, or shallow. Grep/Read is already complete and cheaper. | Use grep/Read. Do NOT spin up a graph. |
| `borderline` | Mixed signals. | Default to grep when unsure; optionally A/B or ask the user. |

## Signals and thresholds

- `code_share_pct` — code lines as a percent of (code + doc) lines. A code-graph
  is blind to the doc half, so a low share caps its achievable recall.
- `code_lines` — absolute code volume. Index + maintenance overhead amortizes
  only on large codebases.
- `symbols_est` — rough definition count (a call-graph-depth proxy via a regex
  union over `def`/`class`/`func`/`fn`/`function`/`interface`/`struct`/`impl`/
  `trait` and shell `name() {`). Separates a shallow layer (tens) from a deep
  one (thousands); it is not an exact parser.

`grep-sufficient` wins on **any** disqualifying signal — the failure modes
(doc-heavy / small / shallow) are independent, so any one is fatal to graph
payoff. `graph-beneficial` requires code density **and** scale:

- grep-sufficient when `code_share_pct < 40` OR `code_lines < 5000` OR `symbols_est < 150`.
- graph-beneficial when `code_share_pct >= 55` AND (`code_lines >= 20000` OR `symbols_est >= 800`).
- borderline otherwise.

Code volume is measured over graph-indexable languages (TS/JS, Python, Go, Rust,
Java/Kotlin, C/C++, C#, Ruby, PHP, Swift, Scala, plus shell as a weak-graph
language); docs are Markdown / reStructuredText / AsciiDoc / plain text. File
lists come from `git ls-files` (honoring `.gitignore` so vendored / build output
does not skew the profile), falling back to `find` outside a git repo.

## Consumption contract

A skill that can route retrieval through a graph MCP calls `repo_profile` once at
research entry, before choosing its retrieval path:

- `graph-beneficial` → prefer the graph MCP's tools (impact / call-chain /
  semantic) when registered; fall back to grep/Read when it is not.
- `grep-sufficient` / `borderline` → use grep/Read; skip graph spin-up.

The detector decides *whether* a graph helps, not *which* graph MCP to use — tool
selection and the registration-degradation ladder remain the caller's concern.
