# Isolation Techniques (canonical, shared)

**Status:** Authoritative isolation techniques for narrowing the bug source after a hypothesis is confirmed.

## When this applies

`/geniro:debug` Phase 1 Isolate — once a hypothesis is confirmed per Evidence Standard, narrow down to exact code location and trace data/control flow.

## Techniques

### Binary search

Disable half the relevant code path, check if the bug reproduces. Narrow the range iteratively. Each iteration halves the candidate set; log<sub>2</sub>(N) iterations to isolate one offending line out of N candidates.

**When to use:** the confirmed hypothesis points to a general region (a module, a transformation pipeline) but the exact line/branch is unclear. Combine with the feedback loop — each "half disabled" toggle is one feedback-loop re-run.

### Git bisect

For regressions, use `git bisect` to identify the commit that introduced the bug. Permitted under .5 Phase 1 ACI (read-only investigation).

```bash
git bisect start
git bisect bad HEAD # current commit reproduces
git bisect good <known-good-sha> # known-working commit
# git checks out the midpoint; run repro; mark good/bad; repeat.
git bisect reset # when done
```

**When to use:** the bug was definitively absent at a prior commit and appeared later. Combine with the feedback loop — `git bisect run <repro-script>` automates the entire walk if the loop is scripted.

### Profiling

For performance bugs, use profiling tools to get quantitative data (timing, memory, allocation count) rather than inspecting code. Code inspection cannot distinguish "slow because of N+1 query" from "slow because of N²-allocation" — profilers can.

**When to use:** symptom is timing-related (latency, throughput, memory growth, CPU saturation). Form the hypothesis in terms of a measurable metric, then have the profiler refute or confirm it.

**Tool options (project-dependent):**
- Node: `node --prof`, `clinic.js`, `0x`, Chrome DevTools heap snapshots.
- Python: `cProfile`, `py-spy`, `memray`.
- Go: `pprof`.
- JVM: `async-profiler`, JFR.
- Browser: Performance panel, Memory panel, Lighthouse.

## Pick the cheapest technique

Same principle as feedback loop selection: binary search is cheapest if the region is large; git bisect is cheapest if the regression boundary is known; profiling is cheapest if the symptom is quantitative. Don't run all three.

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I can intuit the line by reading the code" | Code-reading without binary search or a profiler scales as O(N) lines · O(N) re-reads. The techniques here scale as O(log N) or pull quantitative ground truth. Use them. |
| "Git bisect is overkill for a small regression" | If the bisect range is < 5 commits, manual checkout per commit is acceptable. If > 5, bisect is faster and less error-prone. |
| "Profilers add overhead — skip them" | Microbenchmarks can be inaccurate; full profilers ARE the ground truth. Run them in a representative environment (staging, not prod) per the §Infrastructure Investigation contract. |
