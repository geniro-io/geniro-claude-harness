---
name: debug
description: "Scientific-method bug investigation with hypothesis tracking. Systematically debug complex issues using Observe → Hypothesize → Test → Isolate → Fix → Verify. Do NOT use for bugs with obvious root cause, already-understood fixes, or system-wide refactors — use /follow-up for simple fixes and /implement for deep rework."
context: main
model: opus
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, WebSearch]
argument-hint: "[bug description or reproduction steps]"
---

# Debug: Scientific-Method Investigation

Use this skill to systematically debug complex issues. Replaces guessing with evidence gathering and hypothesis testing. Each investigation is tracked so you can review what was tried and why.

## The Scientific Debug Loop

```
OBSERVE → HYPOTHESIZE → TEST → ISOLATE → FIX → VERIFY → DOCUMENT
```

This is not a suggestion—it's the required process. Do NOT skip steps or guess.

## Bug Report

$ARGUMENTS

**If `$ARGUMENTS` is empty**, ask the user via `AskUserQuestion` with header "Bug": "What bug are you investigating?" with options "Describe the symptoms" / "Paste error message" / "Point to a failing test". Do not proceed until a bug description is provided.

## Hypothesis Tracking Format

Store hypotheses in `.claude/.artifacts/debug/HYPOTHESES.md`:

```markdown
# Bug: [Bug Title]
**Date:** 2026-04-03
**Description:** [What's broken and how to reproduce]
**Severity:** Critical | High | Medium | Low

## Hypothesis 1
- **Hypothesis:** Cache not invalidating on user role change
- **Evidence For:** User sees stale permissions after role update
- **Evidence Against:** Cache invalidation was tested in unit tests
- **Status:** pending → testing → confirmed | rejected | inconclusive
- **Test Plan:** Trace cache invalidation flow for role changes
- **Result:** [Confirmed/Rejected + why]

## Hypothesis 2
- **Hypothesis:** Race condition between role endpoint and permission check
- **Evidence For:** Bug only occurs under load
- **Evidence Against:** Single-user testing shows issue too
- **Status:** pending
- **Test Plan:** Add async logging to both endpoints, test sequentially
- **Result:** [pending]

## Root Cause
[Only filled once hypothesis is confirmed]

## Fix Applied
[Code change + verification]
```

**Fields:**
- **Hypothesis**: Specific, testable claim ("X is causing Y")
- **Evidence For/Against**: What supports or contradicts this?
- **Status**: pending → testing → confirmed | rejected | inconclusive
- **Test Plan**: How will you confirm or reject this?
- **Result**: What did the test show?

> **Inconclusive** means the test could not distinguish whether the hypothesis is true or false. Common causes: (1) test environment differs from production, (2) bug is intermittent and didn't manifest, (3) test was too coarse to isolate this hypothesis, (4) multiple interacting causes mask effects. An inconclusive result is NOT a rejection — it means you need a better test or more data.

## Workflow: Observe → Hypothesis → Test → Fix

### 0. Retrieve Prior Knowledge (1 min)
Before investigating, check for relevant prior learnings:
- Scan `.claude/.artifacts/knowledge/learnings.jsonl` for gotchas and patterns related to the affected area (use Grep with keywords from the bug description)
- Check `.claude/.artifacts/knowledge/sessions/` for past debug sessions on similar components
- If relevant learnings exist, use them to inform initial hypotheses — don't re-discover known issues

### 1. Observe (5 min)
- Reproduce the bug consistently
- Gather error messages, logs, stack traces
- Identify what changed (recent commit? config? user action?)
- Record the exact steps to reproduce
- **If reproduction steps are unclear or missing:** Use the `AskUserQuestion` tool to ask the user for specific details (environment, steps to trigger, expected vs actual behavior). Do NOT guess at reproduction — ask.

### 2. Hypothesize (5 min)
- Based on observation, form 2–3 competing hypotheses
- Each hypothesis must be testable
- Avoid "it's probably X" without evidence
- Write hypotheses in `.claude/.artifacts/debug/HYPOTHESES.md`
- **Consider infrastructure causes alongside code causes** — connection timeouts, resource exhaustion, DNS failures, container restarts, database connection pool limits, cloud service rate limits, and deployment-related changes (new config, changed env vars, scaled-down replicas) are common root causes that code inspection alone will miss. If symptoms include timeouts, intermittent failures, or errors that only appear in deployed environments, form at least one infrastructure hypothesis.

### 3. Test (10–30 min)
- Design a minimal test for each hypothesis
- Add logging, breakpoints, or unit tests to gather evidence
- Do NOT implement a fix yet—you're gathering data
- Record results: confirmed, rejected, or inconclusive

### 4. Isolate (5–15 min)
- Once hypothesis is confirmed, identify exact code location
- Trace the data flow or control flow leading to the bug
- Understand why the bug happens (not just where)

### 5. Fix (5–15 min)
- Implement minimal fix for root cause
- Do NOT refactor adjacent code
- Test fix against reproduction steps
- Run relevant tests

### 6. Verify (10 min)
- Confirm bug is gone (reproduction fails)
- Check no new tests break
- Verify no regressions in related functionality
- Run the project's full test suite via backpressure: `source .claude/hooks/backpressure.sh && run_silent "Tests" "<test_cmd>"` (use the test command from CLAUDE.md). If backpressure is unavailable, use fail-fast flags (`--bail`, `-x`) to surface one failure at a time.
- If the project uses code generation (check CLAUDE.md) AND the fix modified DTOs, schemas, or controllers: run the codegen command, then re-validate.

### 7. Document
- Update `.claude/.artifacts/debug/HYPOTHESES.md` with final outcome
- **Root causes / gotchas discovered** → save as `project` memory (shared context, benefits all team members)
- **Misleading symptoms / red herrings** → save as `project` memory (prevents others from going down the same wrong path)
- **Debugging techniques that worked/failed** → save as `feedback` memory (operational knowledge, persists across sessions)
- **User corrections during investigation** → save as `feedback` memory (persists across sessions, influences future behavior)

Before writing, check if an existing memory covers this topic — UPDATE rather than duplicate. Skip if nothing novel was discovered.

### 8. Suggest Improvements

After documenting the fix, check if the debug session revealed harness improvement opportunities:

| Category | What to look for | Target files |
|---|---|---|
| **Rules gaps** | Bug was caused by violating an undocumented convention? | `.claude/rules/*.md` |
| **Agent prompt gaps** | An agent produced code with this bug pattern? | `.claude/agents/*.md` |
| **Missing test patterns** | Bug class not covered by review criteria? | `.claude/skills/review/*-criteria.md` |
| **Stale documentation** | Docs described behavior that didn't match reality? | Any doc file |

For each improvement found, use the `AskUserQuestion` tool (do NOT output options as plain text) to present the options:
```
The debug session revealed potential harness improvements:

1. [Rule gap] Backend agent has no guard against [pattern] — suggest adding to backend-conventions.md
2. [Test gap] Review criteria don't check for [bug class] — suggest adding to bugs-criteria.md

A) Apply all improvements
B) Review one-by-one
C) Skip — just fix the bug
```

If user approves, draft and apply the changes. If no improvements found, skip silently.

## Escalation Limits

- **Hypothesis testing**: If 5 hypothesis tests across all hypotheses are inconclusive, stop and escalate to user with findings. May need domain expertise or more reproduction data.
- **Fix attempts**: If 2 fix attempts fail verification, stop and use the `AskUserQuestion` tool (do NOT output options as plain text) to present findings with options: A) Try different approach, B) Escalate to /implement for deeper rework, C) Show investigation summary

## Git Constraint

Do NOT run `git add`, `git commit`, `git push`, or `git checkout`. The orchestrating skill handles all version control. You may use `git bisect`, `git log`, `git diff`, and `git blame` for investigation.

## Isolation Techniques

When narrowing down the bug source:
- **Binary search**: Disable half the relevant code path, check if bug reproduces. Narrow the range iteratively.
- **Git bisect**: For regressions, use `git bisect` to identify the commit that introduced the bug.
- **Profiling**: For performance bugs, use profiling tools to get quantitative data (timing, memory) rather than inspecting code.

## Infrastructure Investigation

When symptoms suggest the bug may not be in the code (timeouts, intermittent failures, environment-specific errors, deployment regressions), investigate infrastructure before or alongside code hypotheses:

**Logs & error tracking:**
- Check application logs for error spikes, unusual patterns, or upstream failures (`docker logs`, cloud logging CLI, log aggregator)
- Look for correlation: did errors start at a specific time? Does that coincide with a deployment, config change, or infrastructure event?

**Service health:**
- Check database connectivity and query performance — connection pool exhaustion and slow queries are common silent killers
- Check external service dependencies — are APIs returning errors or timing out?
- Check container/process health — OOM kills, restart loops, CPU throttling

**Environment & config:**
- Compare environment variables between working and broken environments
- Check for recent config changes, secret rotations, or certificate expirations
- Verify DNS resolution, network connectivity, and firewall rules

**Resource limits:**
- Check memory usage, CPU utilization, disk space, and file descriptor limits
- Check database connection pool size vs active connections
- Check rate limits on external APIs

Form infrastructure hypotheses with the same rigor as code hypotheses — record them in HYPOTHESES.md with test plans. "The database connection pool is exhausted under load" is a testable hypothesis; "something is wrong with the server" is not.

## Compliance — Do Not Skip Steps

| Your reasoning | Why it's wrong |
|---|---|
| "It's probably a cache issue" — guess and code | Guesses waste time. Form a hypothesis, then test it with evidence. |
| "I know what this is, let me just fix it" | Intuition-based fixes mask the real cause. Gather evidence first. |
| "It looks right, no need to test" | "Looks right" is the #1 predictor of broken fixes. Run the tests. |
| "Let me fix these three things at once" | Multi-variable changes make it impossible to know what worked. Test one hypothesis at a time. |
| "The error message says X, so it must be X" | Error messages lie. Verify with logs, debuggers, and traces. |
| "I'll document it later" | You won't. Document the root cause and fix while the context is fresh. |

## Cleanup

After the debug session completes (fix verified or escalated):
- Remove `.claude/.artifacts/debug/HYPOTHESES.md` — its useful content has already been saved to memory (root causes, gotchas, techniques). The file is a working scratchpad, not a permanent record.
- Kill any background processes started during investigation (dev servers, watchers, profilers).
- Remove any temporary test files or debug scripts created during the session.

Cleanup is best-effort — if a command fails silently, that's fine.

## Definition of Done

For each debug session, confirm:

- [ ] Bug reproduced consistently with clear steps
- [ ] All hypotheses recorded in `.claude/.artifacts/debug/HYPOTHESES.md`
- [ ] Each hypothesis has a test plan and result
- [ ] Root cause identified and confirmed (not guessed)
- [ ] Fix is minimal and targeted
- [ ] Bug is gone (reproduction fails)
- [ ] No new test failures introduced
- [ ] Investigation documented for future reference
- [ ] Cleanup completed (HYPOTHESES.md removed, temp files cleaned)

---

## When to Use This Skill

**Use `/debug`:**
- Bug has unclear root cause
- Quick fix didn't work and you need to understand why
- Bug is intermittent or hard to reproduce
- You're tempted to guess at a fix
- Multiple possible causes exist
- Bug involves async code, concurrency, or state

**Don't use:**
- Obvious one-line fix (typo, off-by-one) → use `/follow-up`
- Bug is already understood and fix is clear → just implement it
- Need system-wide refactor → use `/implement`

---

## Examples

### Example 1: Cache Not Invalidating
```
/debug User sees stale data after profile update
```
→ Observe: User updates name, refresh page shows old name
→ Hypothesis 1: Cache invalidation broken
→ Hypothesis 2: Update endpoint not called
→ Test: Add logging to cache invalidation and endpoint
→ Result: Hypothesis 1 confirmed (cache key mismatch)
→ Fix: Update cache key to include user ID
→ Verify: Manually test, run cache tests

### Example 2: Intermittent Timeout
```
/debug API endpoint times out randomly under load
```
→ Observe: Happens ~5% of requests during stress test
→ Hypothesis 1: Database query too slow
→ Hypothesis 2: External service timeout
→ Test: Profile database queries, check service logs
→ Result: Hypothesis 2 confirmed (service is slow)
→ Fix: Add timeout and fallback
→ Verify: Stress test again, no timeouts

### Example 3: Memory Leak
```
/debug Heap grows unbounded in React component
```
→ Observe: Memory increases 10MB/min over 1 hour
→ Hypothesis 1: Event listener not cleaned up
→ Hypothesis 2: Large cache never evicted
→ Test: Add heap snapshot profiling, check cleanup
→ Result: Hypothesis 1 confirmed (useEffect missing cleanup)
→ Fix: Add return cleanup function
→ Verify: Run memory profiler again, heap stabilizes
