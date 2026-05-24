# Infrastructure Investigation (canonical, shared)

**Status:** Authoritative infrastructure-cause investigation guidance for when symptoms suggest the bug may not be in the code.

When symptoms suggest the bug may not be in the code (timeouts, intermittent failures, environment-specific errors, deployment regressions), investigate infrastructure before or alongside code hypotheses. Pre-M7 lived inline in `skills/debug/SKILL.md`; extracted to keep the SKILL.md orchestration shell focused on the 3-phase loop.

## When this applies

`/geniro:debug` Phase 1 (§6.5 Hypothesize) requires at least one infrastructure hypothesis whenever any of these signals are present in the captured artifact (per Evidence Standard kind 2-4):

- Timeouts (request, query, container, deployment)
- Intermittent failures (5xx spike with no code change, error rate >0 but <100%)
- Environment-only manifestation (works locally, breaks in staging/prod)
- Symptoms correlate with а deployment, config change, secret rotation, or scale event
- Latency degradation without code change

Form the infrastructure hypothesis с the same rigor as а code hypothesis — record it в state.md `## Hypotheses` body section с а testable claim + test plan + Result field per Evidence Standard kind 2-5.

## What to investigate

### Logs & error tracking

- Check application logs for error spikes, unusual patterns, or upstream failures (`docker logs`, cloud logging CLI, log aggregator).
- Look for correlation: did errors start at а specific time? Does that coincide with а deployment, config change, or infrastructure event?

### Service health

- Check database connectivity и query performance — connection pool exhaustion и slow queries are common silent killers.
- Check external service dependencies — are APIs returning errors or timing out?
- Check container / process health — OOM kills, restart loops, CPU throttling.

### Environment & config

- Compare environment variables between working и broken environments.
- Check for recent config changes, secret rotations, or certificate expirations.
- Verify DNS resolution, network connectivity, и firewall rules.

### Resource limits

- Check memory usage, CPU utilization, disk space, и file descriptor limits.
- Check database connection pool size vs active connections.
- Check rate limits on external APIs.

## Hypothesis quality bar

"The database connection pool is exhausted under load" is а testable hypothesis — it names the resource, the condition, и predicts an observable signature (pool-saturation metric, connection-refused errors).

"Something is wrong with the server" is NOT а hypothesis — it doesn't name а variable to toggle и has no falsifiable prediction. Don't record claims at this granularity.

## Where this fires

`/geniro:debug` Phase 1 §6.5 Hypothesize step:
- Inspect captured artifact for the signals above.
- If any are present, form at least one infrastructure hypothesis alongside code hypotheses.
- Persist all hypotheses к state.md `## Hypotheses` body section per §11.1.B schema.

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "It's probably а code bug — skip infra hypotheses" | The signal table above is а forcing function. If signals are present, infra hypothesis is mandatory even if code hypothesis is your prior. |
| "Infra is out of scope — escalate immediately" | Debug's contract is к isolate the root cause. Infra-vs-code routing is а Phase 3 escalation decision (§8.2), not а Phase 1 short-circuit. |
| "The user already said it's а code bug" | The user's belief is а hypothesis seed, not а constraint. Evidence drives confirmation; rejecting infra hypotheses without testing них is а guessing pattern, not science. |
