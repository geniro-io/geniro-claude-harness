# Optimizations review criteria

Concrete, measurable performance wins on the changed lines: skip ORM hydration on read-only paths, project columns, parallelize independent awaits, batch per-row writes, hygiene React re-renders, and ship the frontend bundle leanly.

Find every real defect this dimension owns by reading the changed code and its callers directly — your own analysis is the detector. The sections below are the contract you are held to: what NOT to flag, and how severity is calibrated.

## Scope boundary — defers to `architecture-criteria.md`
This dimension owns *micro-level* optimization wins observable on the diff. The following six concerns are **not** owned here — they are systemic performance issues handled by `architecture-criteria.md` (Performance & Scalability). Defer to that section; do not duplicate findings:

1. **N+1 query patterns** — queries inside loops without batching → architecture
2. **ORM eager-loading** — `include` / `prefetch_related` / `joinedload` design → architecture
3. **Caching / memoization at the architecture level** — missing layers, not micro-memo → architecture
4. **Missing pagination on unbounded queries** → architecture
5. **Sync I/O in async context** — `readFileSync` etc. on hot paths → architecture
6. **Inefficient algorithms (O(n²) where O(n) possible)** → architecture
If a finding fits one of those six, emit it as an architecture finding (its Performance & Scalability section) instead. Optimizations stays focused on the six categories below.

## Common false positives

1. **Detached entity mutation** — `.lean` / `raw:true` / `HYDRATE_ARRAY` / `disableIdentityMap` returns objects that cannot be saved through the ORM. Flag mutate-then-save paths only when the path is read-only; do not flag pure-read paths that already use these mechanisms, and never recommend skipping hydration on a path that calls `.save` afterward.
2. **defer/only/load_only N+1 footgun** — Django `.only` and SQLAlchemy `load_only` trigger an extra `SELECT` when a deferred column is later accessed. Flag deferred-then-accessed patterns; do not flag use of these on truly write-once-read-rare columns where the deferred access path is cold.
3. **Perf claims without profile data** — "missing index" or "lean would speed this up" without execution-plan / profile evidence is speculative. Lower confidence when no measurement exists; prefer concrete mechanism citations (round-trip count, hydration cost) over hand-waved magnitudes.
4. **Premature memoization** — `useMemo` / `useCallback` on cheap computations is overhead, not optimization. Only flag when the wrapped expression is non-trivial AND the consumer is in a render-frequent context (loop, parent re-renders >5x/sec, large memo'd subtree).
5. **Prisma / Drizzle "missing lean"** — these ORMs return POJOs by default; only projection (`select`) applies. Don't flag a missing skip-hydration call where there's no hydration to skip — recommend `select` / `omit` instead, or stay silent.
6. **Single-use `Promise.all` adjacent awaits** — sometimes serial is intentional: the second call depends on the first's success or its side-effects, or the team wants explicit failure ordering. Verify independence (read the variables, follow the data flow) before flagging.

## Cross-PR hot-path work (peer-PR context)

When the `PEER-PR CONTEXT:` slot is non-`none`, scan kept sibling diffs for parallel optimization work on the same hot path:

- Same query / endpoint / render path independently optimized in both PRs — risk of compounded changes overshooting (e.g., both PRs add caching layers at different levels).
- Sibling PR moves a hot-path resource (e.g., replaces ORM with raw SQL) while current PR also touches the same path — coordination needed on which optimization wins.
- Sibling PR introduces a new bulk-operation helper that current PR's per-row loop should use — surfaces reuse opportunity before merge.

A valid finding shape: "PR #N (peer) optimizes `<path>` at `<file:line>` via <mechanism>; current diff touches the same path with different / overlapping approach — coordinate optimization strategy before shipping both". Severity MEDIUM (optimization findings cap at HIGH per Severity Guidelines).

## Severity guidelines

- **CRITICAL**: not emitted. Optimization findings are improvements, not correctness bugs — bugs and security own CRITICAL. Any genuinely critical perf regression (unbounded query, sync I/O on hot path) belongs in architecture
- **HIGH**: per-row INSERT/UPDATE in a loop on a path that processes >100 items; long-list render >1000 rows without virtualization; eager-import of a heavy lib (>100KB minified) used only behind a tab/modal
- **MEDIUM**: missing `.lean` / `raw:true` / projection on hot-path read; sequential awaits on independent calls; missing route code-splitting; missing `React.memo` on demonstrably expensive child; long-list render 100–1000 rows without virtualization; image without modern format / `loading="lazy"` on hero
- **LOW**: minor projection wins on cold paths; below-fold image without `loading="lazy"`; tree-shaking-hostile `import _ from 'lodash'` where only one helper is used

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1 (the optimizations dim specializes HIGH/MEDIUM to the measured thresholds above per §6).
