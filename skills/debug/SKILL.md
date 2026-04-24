---
name: geniro:debug
description: "Two modes — scientific-method bug investigation (default) or adversarial verify-changes (edge-case test authoring against a diff). Default: Observe → Hypothesize → Test → Isolate → Propose Fix → Verify Root Cause, then ESCALATE the proposed patch to /geniro:follow-up (trivial) or /geniro:implement (non-trivial). Adversarial: authors F→P failing tests against a diff via adversarial-tester-agent. This skill does NOT apply production fixes itself — it produces a report + proposed patch. Do NOT use for bugs with obvious root cause or already-understood fixes — use /geniro:follow-up directly."
context: main
model: opus
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, WebSearch]
argument-hint: "[bug description | verify <diff-range> | verify last changes]"
---

## Subagent Model Tiering

| Subagent | Model | Why |
|---|---|---|
| `adversarial-tester-agent` | `sonnet` | Matches existing call sites in `/geniro:implement` Phase 6 Stage D and `/geniro:follow-up` Medium Phase 5. Test-authoring + F→P verification workload is well-suited to sonnet's latency/cost profile. |

Every `Agent(...)` spawn in this skill MUST pass an explicit `model=` argument per the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`.

# Debug: Scientific-Method Investigation

Use this skill to systematically debug complex issues. Replaces guessing with evidence gathering and hypothesis testing. Each investigation is tracked so you can review what was tried and why.

## The Scientific Debug Loop

```
OBSERVE → HYPOTHESIZE → TEST → ISOLATE → PROPOSE FIX → VERIFY ROOT CAUSE → ESCALATE → DOCUMENT
```

This is not a suggestion—it's the required process. Do NOT skip steps or guess.

## Input

$ARGUMENTS

**Mode routing (inspect `$ARGUMENTS` BEFORE the empty-check):**

- If `$ARGUMENTS` matches any **verify-intent signal**, route to **Adversarial Mode** (see `## Adversarial Mode: Verify Last Changes` below) and skip the scientific-method Workflow. Every signal below is **anchored** — bare keywords alone are NOT enough, because phrases like "verify that login returns 500" or "stress-test revealed a memory leak" are scientific-method bug reports, not verify requests:
  - Anchored keyword signals (keyword + anchor token): `verify <changes|diff|last|recent|my|this|PR>`, `break <my|the> diff`, `hunt for bugs in <diff|change|PR>`, `find edge cases in <diff|change|PR>`, `adversarial <mode|pass|scan|run>`, `stress-test <the diff|my change|last changes>`
  - Phrase signals: `verify last changes`, `verify recent changes`, `verify my changes`, `check last changes`, `break my diff`
  - Explicit diff range signals: `HEAD~N..HEAD`, `HEAD~N`, `main...HEAD`, a bare PR ref (`#1234` or GitHub PR URL), or a bare branch name used alongside any verify keyword
- Otherwise → standard scientific-method flow (the `## Workflow: Observe → ...` section, unchanged). When in doubt (ambiguous input), default to scientific-method mode — the user can re-invoke with explicit adversarial phrasing if needed.

**If `$ARGUMENTS` is empty**, ask the user via `AskUserQuestion` with header "Mode": "What are we doing?" with options "Describe the symptoms" / "Paste error message" / "Point to a failing test" / "Verify last changes (adversarial)". The first three route to scientific-method mode (the selected option becomes the initial bug description seed); the fourth routes to Adversarial Mode. Do not proceed until the user answers.

## Hypothesis Tracking Format

Store hypotheses in `.geniro/debug/HYPOTHESES.md`:

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

## Proposed Fix
[File path(s), diff or before/after snippet, one-sentence rationale — text only, NOT applied to source]

## Fix Evidence (experimental)
[How the patch was verified locally (throwaway experiment), reproduction result, confirmation that experimental edits were reverted]

## Escalation
[/geniro:follow-up or /geniro:implement; handoff via `.geniro/debug/findings-state.md`]
```

**Fields:**
- **Hypothesis**: Specific, testable claim ("X is causing Y")
- **Evidence For/Against**: What supports or contradicts this?
- **Status**: pending → testing → confirmed | rejected | inconclusive
- **Test Plan**: How will you confirm or reject this?
- **Result**: What did the test show?

> **Inconclusive** means the test could not distinguish whether the hypothesis is true or false. Common causes: (1) test environment differs from production, (2) bug is intermittent and didn't manifest, (3) test was too coarse to isolate this hypothesis, (4) multiple interacting causes mask effects. An inconclusive result is NOT a rejection — it means you need a better test or more data.

## Workflow: Observe → Hypothesis → Test → Propose Fix → Escalate

### 0. Retrieve Prior Knowledge & Custom Instructions (1 min)
Before investigating, check for relevant prior learnings:
- Scan `.geniro/knowledge/learnings.jsonl` for gotchas and patterns related to the affected area (use Grep with keywords from the bug description)
- Check `.geniro/knowledge/sessions/` for past debug sessions on similar components
- If relevant learnings exist, use them to inform initial hypotheses — don't re-discover known issues
- Load custom instructions from `.geniro/instructions/global.md` and `.geniro/instructions/debug.md`. Read any found. Apply rules as constraints, additional steps at specified phases, and hard constraints.

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
- Write hypotheses in `.geniro/debug/HYPOTHESES.md`
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

### 5. Propose Fix (5–15 min)
- Formulate the minimal fix for the root cause as a **text proposal**: file path(s), exact change (unified diff or before/after snippet), and a one-sentence rationale.
- Do NOT write the fix to production/source files. Write/Edit are available for EXPERIMENTS only (tests, logging, debug scripts, `.geniro/debug/` artifacts) — not for applying the proposed patch.
- Do NOT refactor adjacent code.
- If experiments modified non-test source to prove the hypothesis (e.g., added a temporary log line, patched a value), revert those experimental edits before escalation. The escalated skill applies the real fix cleanly.

### 6. Verify Root Cause (5–10 min)
- Prove the proposed fix resolves the root cause using experiments only: apply the patch locally in a throwaway way (e.g., monkey-patch in a test, branch-local scratch edit you will revert), run the reproduction, confirm the bug disappears, then revert the experimental change.
- Do NOT run the full project test suite here — that belongs to the escalated skill. The goal is evidence that the proposed patch is correct, not CI-green.
- Record the experimental evidence in `.geniro/debug/HYPOTHESES.md` under "Fix Evidence".
- If the project uses code generation (check CLAUDE.md) AND the proposed fix touches DTOs, schemas, or controllers: note this in the escalation so the receiving skill runs codegen.

### 6.5. Present Findings & Escalate (WAIT)

Before asking where to route the fix, you MUST present a human-readable findings summary to the user. Do NOT jump straight to `AskUserQuestion` — the user chooses the escalation target based on this summary, so it has to be visible first. HYPOTHESES.md is a working scratchpad, not a substitute for a user-facing report.

#### 6.5a — Present Findings Summary & Persist State

Output the following markdown block directly in the chat AND write the same block to `.geniro/debug/findings-state.md` (single file per branch, overwritten on each run — mirrors the `/geniro:review` state-artifact convention). Fill with the actual values from your investigation. Use "none" for any field that truly doesn't apply — don't omit fields. Prepend an ISO-8601 timestamp header (`# Debug Findings — <timestamp>`) to the file version so downstream skills and resumed sessions can tell stale artifacts from fresh ones.

```markdown
## Debug Findings

**Root cause:** [one sentence, plain language — why the bug happens]

**Reproduction:** [exact steps that trigger the bug]

**Confirmed hypothesis:** [which numbered hypothesis from HYPOTHESES.md was confirmed, and the test result that confirmed it]

**Rejected hypotheses:** [brief — which hypotheses were ruled out and why, so the user sees what was considered]

**Proposed fix:**
- Files: [path(s) that need to change]
- Change: [unified diff or before/after snippet]
- Rationale: [one sentence tying the change to the root cause]

**Evidence the fix works:** [what happened when you applied the patch as a throwaway experiment in Step 6 — e.g., "bug stopped reproducing; experimental edits reverted"]

**Tests that should pass after the fix:** [test names, criteria, or "new test needed: <description>"]

**Special handling:** [codegen, migrations, schema changes, env/config updates — or "none"]
```

The receiving skill pre-loads findings from `.geniro/debug/findings-state.md` — the state file is the handoff channel, not a chat paste. Do NOT re-derive, reword, or inline the summary into the escalation command; the file path is the contract.

#### 6.5b — Escalation Decision

Only after the summary above is visible AND written to `.geniro/debug/findings-state.md`, use `AskUserQuestion` with header "Escalate" and these options:
- **Trivial — run `/geniro:follow-up`; pre-load findings from `.geniro/debug/findings-state.md`** — ≤2 files, obvious target, no architecture or auth/permissions change.
- **Non-trivial — run `/geniro:implement`; pre-load findings from `.geniro/debug/findings-state.md`** — touches multiple modules, changes interfaces, needs architecture review, or introduces a new pattern.
- **Leave it to me** — the user will apply the patch manually using the state file as reference. Skip to Step 7.

Do NOT auto-invoke the next skill — surface the suggestion only. The user runs the slash command themselves; the state file is the handoff channel. You do NOT apply the patch yourself. Full-suite validation is the receiving skill's responsibility.

### 7. Document
- Update `.geniro/debug/HYPOTHESES.md` with final outcome
- **Extract Learnings:** Follow the canonical rubric in `skills/_shared/learnings-extraction.md`. Bias hard toward flow, architectural, and recurring-mistake learnings; do NOT save narrow interface/field shapes, single-file behaviors, or facts re-derivable by reading the code. Apply the Reflect → Abstract → Generalize pre-pass before every save: if you cannot restate the finding one level up, drop it. Route per canonical: transferable debugging insights and class-of-bugs patterns → `learnings.jsonl`; user corrections during investigation → `feedback_*` memory; project-wide ongoing-investigation facts → `project_*` memory. UPDATE existing entries rather than duplicate. Skip if nothing novel.

### 8. Suggest Improvements (project scope only)

After documenting, classify each finding by its **routing target**. ONLY route to project-owned files — do NOT suggest edits to plugin-internal files (`${CLAUDE_PLUGIN_ROOT}/agents/*.md`, `${CLAUDE_PLUGIN_ROOT}/skills/**`, `${CLAUDE_PLUGIN_ROOT}/hooks/**`). The plugin is installed globally and overwritten on update; plugin maintenance is out of scope for debug.

| What was discovered | Route to | Why |
|---|---|---|
| Docs described behavior that didn't match reality | **CLAUDE.md** or **docs** | Future agents need correct project info |
| Non-obvious debugging insight or workaround | **Knowledge** (`.geniro/knowledge/learnings.jsonl`) | Searchable by knowledge-retrieval-agent |
| New/changed command discovered during debugging | **CLAUDE.md** | All agents read CLAUDE.md for commands |
| Quality gate or workflow step the user enforced manually | **Custom instructions** (`.geniro/instructions/`) | Project-specific skill behavior rules |

Present via `AskUserQuestion` with header "Improvements": "Apply all" / "Review one-by-one" / "Skip". Group by target. If no improvements found, skip silently.

## Adversarial Mode: Verify Last Changes

### A. Purpose

Attacker-mindset pass that AUTHORS executable F→P failing tests against a diff. Complements the scientific-method mode: that mode REPORTS hypotheses about a known bug; adversarial mode hunts for unknown bugs in recent changes by writing tests that fail on today's code. Test authoring is delegated to `adversarial-tester-agent`; the orchestrator independently re-runs authored tests to confirm the failure before surfacing findings.

### B. Diff Resolution

Resolve the diff scope using the same multi-form parser as `/geniro:review` Phase 1 (see `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` §Phase 1: Collect Context & Triage — do NOT duplicate the parser here).

**Default when no explicit range is passed:** `git diff main...HEAD` (covers everything on the current branch not on main). Also compute `git diff --name-only main...HEAD` to get the file list. If the branch is `main`, fall back to `HEAD~1..HEAD`. Include uncommitted work via a trailing `git diff` (unstaged) + `git diff --cached` (staged) snapshot when present.

**Supported shapes:**
- Bare keyword (`"verify last changes"`) → default (`main...HEAD`, or `HEAD~1..HEAD` if on main)
- Explicit range (`HEAD~3..HEAD`, `abc123..def456`)
- Branch (`feat/foo...HEAD`)
- PR ref (strip leading `#`, resolve via `gh pr diff <number-or-url>`)

### C. Skip Conditions

Apply the same skip-matrix philosophy as `skills/follow-up/SKILL.md` Step 1.5 (see that file for the canonical matrix — do NOT duplicate). Adversarial mode is SKIPPED and the skill reports `"no adversarial pass — <reason>"` when any of these hold:

- Empty diff (nothing to test)
- Diff contains zero production-code files (docs / config / lock / generated only)
- Diff is >50 changed files OR >1000 changed LOC → suggest `/geniro:review` for oversized diffs (the agent's 10-test hard cap wastes budget on diffs this large)

### D. Adversarial Workflow

1. **Resolve the diff** (see B). Pre-inline full diff + changed-file contents for the spawn prompt.
2. **Detect the project test framework.** Read `CLAUDE.md` Essential Commands section + `package.json` scripts / `pyproject.toml` / `Cargo.toml` to extract (a) the test command, (b) test-file naming convention, (c) 1–2 exemplar test files closest to the changed code.
3. **Spawn `adversarial-tester-agent`** — see Spawn Template in §E below.
4. **Independently re-run authored tests.** Read the agent's report at `.geniro/debug/adversarial-tests.md`, extract authored test file paths, then run the project test command **once per authored test**. Single independent re-run per authored test (the agent already ran its own 3× flake check per its Step 5; duplicating would waste budget). Any test that does not fail deterministically on the re-run is deleted from disk AND removed from the report.
5. **Present Adversarial Findings** — see §F below.
6. **Escalate.** Reuse Step 6.5b `AskUserQuestion` (header "Escalate") with the same three options — Trivial → `/geniro:follow-up`, Non-trivial → `/geniro:implement`, Leave-it-to-me. Before asking, ensure the Adversarial Findings summary from §F has been written to `.geniro/debug/adversarial-tests.md` (the agent already wrote it at Step 3; append the re-verification delta if tests were discarded). The escalation option labels MUST reference that file by path (e.g., "Trivial — run `/geniro:follow-up`; pre-load findings from `.geniro/debug/adversarial-tests.md`") — the authored test file paths inside are the escalation targets, and the receiving skill applies the fix and confirms the now-green test suite. If zero red tests survived re-verification, SKIP Step 6.5b entirely — report `"no bugs found in scanned diff"` and go to DoD.

### E. Spawn Template

```
Agent(subagent_type="adversarial-tester-agent", model="sonnet", prompt="""
## Task: Adversarial Edge-Case Test Authoring (Debug — Verify Changes)

### Diff (changed files + contents)
[Pre-inline `git diff <resolved-range>` output AND full contents of every changed source file from Step 1]

### Shared Edge-Case Checklist (READ this file yourself at runtime — do NOT paste here)
`${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`

### Project Test Framework
- Test command (from CLAUDE.md Essential Commands): [e.g. `pnpm test`, `pytest`]
- Test-file naming convention: [project's pattern — e.g. `*.test.ts` adjacent to source]
- Exemplar test files (1-2, pre-inlined): [closest existing test files to the changed code]

### Hypothesis Seeds
none — adversarial mode runs a fresh pass (no prior reviewer findings available in debug).

### Output
Write your report to `.geniro/debug/adversarial-tests.md`. Authored test files go to the project's normal test paths. Do NOT git add/commit/push.

### F→P Invariant (NON-NEGOTIABLE)
Every test you keep MUST fail 3 times in a row on the current code. If it passes today, delete the test and mark `discarded-cannot-repro`. Flaky = discard.

### Scope
Diff-only — the orchestrator resolved the scope above. Do NOT author tests for files outside the changed-files list. Hard cap: 10 authored tests.
""", description="Adversarial tests: /geniro:debug verify-changes")
```

### F. Findings Summary

After re-verification, present this block directly in chat:

```markdown
## Adversarial Findings

**Diff scope:** [range + file count + LOC]

**Hypotheses generated:** [N]
**Tests authored (kept after re-verify):** [M]
**Tests discarded (F→P failed on re-run):** [K]

### CRITICAL / HIGH findings
[For each: test file path, targeted source, category, confidence, hypothesis, reproduction command, suggested direction for fix (NOT the patch itself)]

### MEDIUM findings
[same shape]

### Discarded / Inconclusive
[brief list with reasons]

**Zero red tests?** [If M == 0 after re-verify: state plainly "no bugs found in scanned diff" — this is a valid outcome.]
```

If zero red tests survive, skip escalation entirely and go directly to Cleanup/DoD. Otherwise proceed to escalation per §D Step 6.

## Escalation Limits (Scientific-Method Mode)

These limits apply to scientific-method mode only. Adversarial mode inherits the agent-level stop rules defined in `agents/adversarial-tester-agent.md` (5 consecutive discards stop hypothesis generation; 10 authored tests is the hard cap per run).

- **Hypothesis testing**: If 5 hypothesis tests across all hypotheses are inconclusive, stop and escalate to user with findings. May need domain expertise or more reproduction data.
- **Fix attempts**: If 2 fix attempts fail verification, stop and use the `AskUserQuestion` tool (do NOT output options as plain text) to present findings with options: A) Try different approach, B) Escalate to /geniro:implement for deeper rework, C) Show investigation summary

## Git Constraint

Do NOT run `git add`, `git commit`, `git push`, or `git checkout`. The orchestrating skill handles all version control. You may use `git bisect`, `git log`, `git diff`, and `git blame` for investigation.

## Fix Constraint

Do NOT apply the bug fix to production/source code. You MAY Write/Edit for **experiments only**:
- Test files (new or existing) that reproduce or verify the bug
- Debug logging, temporary print statements, or scratch scripts
- `.geniro/debug/HYPOTHESES.md` and other investigation artifacts
- Throwaway patches used in Step 6 to verify the root cause — these MUST be reverted before escalation

The actual fix is delivered as a **text proposal** (diff or before/after) and escalated via Step 6.5 to `/geniro:follow-up` (trivial) or `/geniro:implement` (non-trivial). This keeps architecture/review gates in play and preserves a clean audit trail.

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
| "The fix is one line, I'll just write it and escalate nothing" | Escalate every fix. One-line fixes go to `/geniro:follow-up`; the architecture/review gate still applies. |
| "I added experimental logging and while I'm here I'll patch the bug too" | Experiments and fixes are separate deliverables. Revert experimental edits; escalate the proposed patch. |
| "The user said just fix it" | If the user explicitly overrides, pick "Leave it to me" in Step 6.5 and produce the patch as text — still do NOT write it to source. The user applies it manually. |
| "Changes look fine, I'll skip adversarial mode" | "Looks fine" is the attacker's favorite surface. If the user asked for verify-changes, run the adversarial pass — a zero-red-tests outcome is still a valid deliverable, but only after the agent actually ran. |
| "Small diff, adversarial pass is overkill" | The 10-test hard cap and single-agent cost make adversarial mode cheap even on small diffs. Skip only when the skip-matrix rules fire (empty / docs-only / oversized), not on vibes. |
| "I'll reason about edges instead of authoring tests" | Reasoning is reviewer-mindset. Adversarial mode AUTHORS executable failing tests because reasoning misses what running code catches. Delegate to the agent. |
| "The agent reported F→P, I'll trust it" | The orchestrator MUST independently re-run authored tests per the agent's own Delegation Boundary. Self-reported F→P is evidence, not proof. |
| "A finding improves an agent prompt, I'll include it in Step 8" | Plugin files are out of scope. Suggest only project-owned targets (CLAUDE.md, `.geniro/instructions/`, `.geniro/knowledge/learnings.jsonl`). |
| "The findings are in HYPOTHESES.md, I'll just ask the escalation question" | HYPOTHESES.md is a scratchpad, not a user-facing report. Step 6.5a requires an explicit findings summary in chat AND persisted to `.geniro/debug/findings-state.md` before the escalation question — the user decides where to route based on the chat summary, and the receiving skill pre-loads from the state file. |
| "I'll paste the full findings summary into the escalation command" | The escalation options reference `.geniro/debug/findings-state.md` by path — that file IS the handoff. Inlining the summary into the command bloats context and lets the two copies drift. File path only. |

## Cleanup

After the debug session completes (fix verified or escalated):
- **Scientific-method mode only:** Remove `.geniro/debug/HYPOTHESES.md` — its useful content has already been saved to memory (root causes, gotchas, techniques). The file is a working scratchpad, not a permanent record.
- **Scientific-method mode only:** Remove any temporary test files or debug scripts created during the session (adversarial mode authors keeper tests — those stay on disk).
- **Scientific-method mode only:** `.geniro/debug/findings-state.md` MUST remain on disk as the escalation handoff channel — do NOT delete it. It stays until the next debug run overwrites it (single file per branch, same as `/geniro:review`'s state artifact).
- Kill any background processes started during investigation (dev servers, watchers, profilers).
- **Adversarial mode:** `.geniro/debug/adversarial-tests.md` may remain as audit trail per plugin convention; authored test files stay on disk.

Cleanup is best-effort — if a command fails silently, that's fine.

## Definition of Done

For each debug session, confirm the checklist for the mode that ran.

### Scientific-Method Mode

- [ ] Bug reproduced consistently with clear steps
- [ ] All hypotheses recorded in `.geniro/debug/HYPOTHESES.md`
- [ ] Each hypothesis has a test plan and result
- [ ] Root cause identified and confirmed (not guessed)
- [ ] Proposed fix is minimal, targeted, and written as a text patch (not applied to source)
- [ ] Proposed fix verified against the root cause via reverted experiments
- [ ] Findings summary (Step 6.5a) presented to user in chat AND persisted to `.geniro/debug/findings-state.md` before the escalation question
- [ ] Escalation decision made via Step 6.5b AskUserQuestion with options referencing the state file by path (follow-up / implement / user-handles)
- [ ] All experimental edits to non-test source reverted before handoff
- [ ] Investigation documented for future reference
- [ ] Cleanup completed (HYPOTHESES.md removed, temp files cleaned)

### Adversarial Mode

- [ ] Diff scope resolved (range + file list recorded)
- [ ] Skip conditions checked (and explicitly reported if skipped)
- [ ] Project test framework detected from CLAUDE.md / package.json / pyproject.toml
- [ ] `adversarial-tester-agent` spawned with all 5 Input Contract slots pre-inlined
- [ ] Report written to `.geniro/debug/adversarial-tests.md`
- [ ] Authored tests independently re-run by orchestrator (1× per test)
- [ ] F→P-confirmed tests retained; any passing-today tests deleted
- [ ] Adversarial Findings summary (§F) presented to user in chat
- [ ] Escalation decision made via Step 6.5b (or "no bugs found" exit if zero red tests)
- [ ] Authored test files left on disk (NOT reverted — unlike scientific-method experiments)
- [ ] Cleanup completed (`.geniro/debug/adversarial-tests.md` can remain as audit trail per plugin convention)

---

## When to Use This Skill

**Use `/geniro:debug`:**
- Bug has unclear root cause
- Quick fix didn't work and you need to understand why
- Bug is intermittent or hard to reproduce
- You're tempted to guess at a fix
- Multiple possible causes exist
- Bug involves async code, concurrency, or state

**Don't use:**
- Obvious one-line fix (typo, off-by-one) — go straight to `/geniro:follow-up`
- Bug is already understood and fix is clear — `/geniro:follow-up` or `/geniro:implement` directly
- Need system-wide refactor — `/geniro:implement`

**Remember:** debug investigates and *proposes* — it never applies the fix. If the proposed patch looks obvious after Step 4, that's a signal you should have gone straight to `/geniro:follow-up` in the first place.

---

## Examples

### Example 1: Cache Not Invalidating
```
/geniro:debug User sees stale data after profile update
```
→ Observe: User updates name, refresh page shows old name
→ Hypothesis 1: Cache invalidation broken
→ Hypothesis 2: Update endpoint not called
→ Test: Add logging to cache invalidation and endpoint
→ Result: Hypothesis 1 confirmed (cache key mismatch)
→ Propose: patch cacheKey builder in `src/cache/user.ts` to include user ID
→ Verify root cause: local experiment shows bug disappears with patch (reverted)
→ Escalate: /geniro:follow-up with the proposed patch

### Example 2: Intermittent Timeout
```
/geniro:debug API endpoint times out randomly under load
```
→ Observe: Happens ~5% of requests during stress test
→ Hypothesis 1: Database query too slow
→ Hypothesis 2: External service timeout
→ Test: Profile database queries, check service logs
→ Result: Hypothesis 2 confirmed (service is slow)
→ Propose: add timeout and fallback around the external service call
→ Verify root cause: local experiment shows timeouts disappear with patch (reverted)
→ Escalate: /geniro:implement with the proposed patch

### Example 3: Memory Leak
```
/geniro:debug Heap grows unbounded in React component
```
→ Observe: Memory increases 10MB/min over 1 hour
→ Hypothesis 1: Event listener not cleaned up
→ Hypothesis 2: Large cache never evicted
→ Test: Add heap snapshot profiling, check cleanup
→ Result: Hypothesis 1 confirmed (useEffect missing cleanup)
→ Propose: add return cleanup function to the offending useEffect
→ Verify root cause: local experiment shows heap stabilizes with patch (reverted)
→ Escalate: /geniro:follow-up with the proposed patch
