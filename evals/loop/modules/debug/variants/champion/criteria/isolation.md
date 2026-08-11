## 4. Isolation techniques

Once a hypothesis is confirmed, narrow down to exact code location.

**Binary search:** Disable half the relevant code path, check if the bug reproduces. Narrow iteratively. O(log N) iterations. Use when the confirmed hypothesis points to a general region but exact line/branch is unclear.

**Git bisect:** For regressions, walk the good→bad range to identify the commit that introduced the bug. Use when the bug was absent at a prior commit.

**Profiling:** For performance bugs, use the language's profiler for quantitative data (timing, memory, allocation count). Code inspection cannot distinguish "slow because of N+1 query" from "slow because of N^2 allocation."

**Pick the cheapest technique:** binary search if the region is large; git bisect if the regression boundary is known; profiling if the symptom is quantitative. Don't run all three.

---

