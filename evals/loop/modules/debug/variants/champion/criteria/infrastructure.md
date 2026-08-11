## 3. Infrastructure investigation

When symptoms suggest the bug may not be in the code (timeouts, intermittent failures, environment-specific errors, deployment regressions), investigate infrastructure before or alongside code hypotheses.

**Signals requiring at least one infrastructure hypothesis:** timeouts; intermittent failures (error rate >0 but <100%); environment-only manifestation (works locally, breaks in staging/prod); latency degradation without a code change; symptoms correlating with a deployment, config change, secret rotation, or scale event.

**What to investigate:** logs, service health, environment/config diffs between the working and broken environments, and resource limits. The entries that get missed sit inside those categories — **certificate expiry**, **secret rotation**, and **connection-pool size vs active connections** — each breaks a running system while every code path is still correct.

**Hypothesis quality bar:** "The database connection pool is exhausted under load" is testable — names the resource, condition, and observable signature. "Something is wrong with the server" is NOT a hypothesis — no variable to toggle, no falsifiable prediction.

---

