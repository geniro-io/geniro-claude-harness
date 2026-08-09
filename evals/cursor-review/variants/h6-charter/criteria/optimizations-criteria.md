# Optimizations review criteria


Find real performance issues on hot paths: N+1 queries, unbounded memory, quadratic loops.

## Common false positives

1. **Detached entity mutation** — `.lean` / `raw:true` / `HYDRATE_ARRAY` / `disableIdentityMap` returns objects that cannot be saved through the ORM. Flag mutate-then-save paths only when the path is read-only; do not flag pure-read paths that already use these mechanisms, and never recommend skipping hydration on a path that calls `.save` afterward.
2. **defer/only/load_only N+1 footgun** — Django `.only` and SQLAlchemy `load_only` trigger an extra `SELECT` when a deferred column is later accessed. Flag deferred-then-accessed patterns; do not flag use of these on truly write-once-read-rare columns where the deferred access path is cold.
3. **Perf claims without profile data** — "missing index" or "lean would speed this up" without execution-plan / profile evidence is speculative. Lower confidence when no measurement exists; prefer concrete mechanism citations (round-trip count, hydration cost) over hand-waved magnitudes.
4. **Premature memoization** — `useMemo` / `useCallback` on cheap computations is overhead, not optimization. Only flag when the wrapped expression is non-trivial AND the consumer is in a render-frequent context (loop, parent re-renders >5x/sec, large memo'd subtree).
5. **Prisma / Drizzle "missing lean"** — these ORMs return POJOs by default; only projection (`select`) applies. Don't flag a missing skip-hydration call where there's no hydration to skip — recommend `select` / `omit` instead, or stay silent.
6. **Single-use `Promise.all` adjacent awaits** — sometimes serial is intentional: the second call depends on the first's success or its side-effects, or the team wants explicit failure ordering. Verify independence (read the variables, follow the data flow) before flagging.


## Severity guidelines

- **CRITICAL**: not emitted. Optimization findings are improvements, not correctness bugs — bugs and security own CRITICAL. Any genuinely critical perf regression (unbounded query, sync I/O on hot path) belongs in architecture
- **HIGH**: per-row INSERT/UPDATE in a loop on a path that processes >100 items; long-list render >1000 rows without virtualization; eager-import of a heavy lib (>100KB minified) used only behind a tab/modal
- **MEDIUM**: missing `.lean` / `raw:true` / projection on hot-path read; sequential awaits on independent calls; missing route code-splitting; missing `React.memo` on demonstrably expensive child; long-list render 100–1000 rows without virtualization; image without modern format / `loading="lazy"` on hero
- **LOW**: minor projection wins on cold paths; below-fold image without `loading="lazy"`; tree-shaking-hostile `import _ from 'lodash'` where only one helper is used

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1 (the optimizations dim specializes HIGH/MEDIUM to the measured thresholds above per §6).
