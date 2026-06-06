# Debug — Detailed Reference

Detail sections extracted from `skills/debug/SKILL.md` to keep the main skill body lean. The orchestrator reads this file when SKILL.md references one of the sections below by name.

## Contents

1. State machine — full ASCII diagram + state semantics
2. State file schema — frontmatter + body sections (T1.5 state.md, T2 handoff files)
3. Infrastructure Investigation — signals + investigation checklist
4. Isolation Techniques — binary search, git bisect, profiling
5. Stall Diagnosis Taxonomy — 8-component missing-component table
6. Adversarial Mode templates — A5 spawn prompt + A6 findings template
7. Extended examples — Intermittent Timeout + Verify Recent Changes

---

## 1. State machine — full ASCII diagram

state.md `phase:` enum transitions:

```
[entry] → mode-detect ──┬── investigate ──┬── propose ──┬── ship ── done
                        │                 │             └── ship-summary-only (terminal — "Leave it to me")
                        │                 │
                        │                 └── phase-2-escalated ──┬── ship (accept-as-documented-limitation)
                        │                                         ├── propose (try-different-approach loop-back)
                        │                                         └── aborted (terminal)
                        │
                        └── phase-1-escalated ──┬── investigate (supply-data loop-back)
                                                ├── ship-summary-only (abandon — partial findings)
                                                └── aborted (terminal)

[entry] → adversarial-mode-detect ── adversarial-investigate ── adversarial-ship ──┬── done
                                                                                   └── adversarial-aborted (terminal — zero red tests)
```

**Terminal states:** `done`, `ship-summary-only`, `aborted`, `adversarial-aborted`. The SessionStart recovery treats all four as "task complete — no resume needed".

**Non-terminal states:** `mode-detect`, `investigate`, `propose`, `ship`, `adversarial-mode-detect`, `adversarial-investigate`, `adversarial-ship`. The recovery rolls these back to phase-entry and re-runs (idempotent — `approvals[]` ensures gates skip already-answered).

**Escalation states:** `phase-1-escalated`, `phase-2-escalated`. The recovery surfaces these to the user as "task was paused — last AUQ options:" so the user re-picks without losing context.

The `## Termination reason` body section is written on `aborted` / `adversarial-aborted` terminals.

---

## 2. State file schema

### state.md (T1.5 — session-bound, `.geniro/state/debug/<slug>/state.md`)

Frontmatter:

```yaml
---
tier: T1.5
producer: debug
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: <enum per State Machine above>
status: <in-progress|done|failed>
non-resumable-actions: []
approvals: []                         # categories: disambiguate_mode, multi_path_fix
geniro_kind: debug-state
geniro_schema_version: m7-v1
mode: <scientific|adversarial>
task_slug: <slug>
worktree: <abs-path>
---
```

Body sections (Scientific Mode):

- `## Inputs from <producer>` (optional, T2 input consumed at Phase 1)
- `## Symptom`
- `## Reproduction Steps`
- `## Feedback Loop` (Command / Expected output / Actual output / Re-run cost / Determinism)
- `## Hypotheses` (Hypothesis / Evidence For / Evidence Against / Status / Test Plan / Result per hypothesis)
- `## Root Cause`
- `## Proposed Fix`
- `## Reproduction Test`
- `## Accepted Limitations` (optional, path B)
- `## Tool log` — selective logging (adversarial-tester-agent spawns, stall escalations)
- `## Errors`
- `## Open Questions` (stall AUQ + outcome)
- `## Resolved Questions` (Phase 3 §3.0 Pre-gate writes resolution mirror here)
- `## Termination reason` (only on terminal aborted-state)
- `## Persisted approvals` (render of frontmatter approvals[])

Body sections (Adversarial Mode):

- `## Diff Scope` (range + file count + LOC)
- `## Hypothesis Seeds`
- `## Authored Tests` (table: # / Path / Targeted source / Category / Confidence / F→P status)
- `## Re-verification Results`
- `## Tool log`, `## Errors`, `## Termination reason`

### from-debug-<branch>.md (T2 — handoff, Scientific Mode)

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`. Single file per branch, overwritten on next debug run.

```yaml
---
tier: T2
producer: debug
consumer: implement
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
worktree: <abs-path>
geniro_kind: debug-handoff
geniro_schema_version: m7-v2
mode: scientific
phase: ship
status: done
approvals: []
non-resumable-actions: []
authored_tests:                       # MUST be present; MAY be empty []
  - id: t1                            # short stable anchor (t1, t2, ...)
    path: <repo-root-relative path>   # resolve against debug-source-worktree's `git rev-parse --show-toplevel`
    intent: <one-line guarantee>      # e.g., "covers H2 — null-pointer on empty payload"
    mode: scientific                  # MUST match top-level `mode:`
    f_to_p_status: <enum>             # red-on-current | green-under-patch | red-on-current+green-under-patch | escape-hatch
    related_hypotheses: [H2]          # optional — Hypothesis IDs from `## Hypotheses`
    targeted_source: <prod path>      # optional — production file the test targets (used by /geniro:implement for triage)
    confidence: high                  # optional — adversarial mode only (high|medium|low)
open_questions:                       # MUST be present; MAY be empty []
  - id: q1                            # short stable anchor (q1, q2, ...)
    source: <phase-or-step>           # e.g., phase-1-stall-gate, phase-2-multi-path-fix, phase-3-cannot-verify
    question: <verbatim ambiguity question>
    related_hypotheses: [H2, H4]      # optional — Hypotheses IDs from `## Hypotheses` this question is tied to
    status: unresolved                # enum: unresolved | resolved | wontfix
    resolution:                       # populated only when status moves out of `unresolved`
      picked: <chosen option>
      at: <ISO-8601 UTC>
      asked_in_phase: <phase name>
      resolved_by: <skill — debug | implement | manual>
---
```

Body: full content of findings template + body sections (`## Tool log` / `## Errors` / `## Open Questions` (human-readable mirror of frontmatter) / `## Resolved Questions` / `## Persisted approvals`).

The `open_questions[]` frontmatter array is the machine-readable source of truth per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2. The body `## Open Questions` section is a human-readable mirror; the body `## Resolved Questions` section mirrors resolutions written back by the Phase 3 Pre-gate or by /geniro:implement's Phase 1 handoff-resolution step gate.

The `authored_tests[]` frontmatter array is the machine-readable source of truth for the F→P tests this debug run produced — full schema and producer/consumer contracts in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §Producer-specific extensions. Body lines `**Reproduction test:**` (scientific) and `**Test file:**` (adversarial, A6 template) remain as human-readable mirrors of this array. Consumers (notably /geniro:implement Phase 1 handoff-resolution step) prefer the frontmatter; legacy handoffs at `geniro_schema_version: m7-v1` lack this field, so the consumer protocol in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` falls back to body-string parsing in that case.

### from-debug-adversarial-<branch>.md (T2 — handoff, Adversarial Mode)

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`. Same schema as from-debug-<branch>.md with `mode: adversarial` and `phase: adversarial-ship` discriminators. Body: A6 Adversarial Findings template + body sections.

---

## 3. Infrastructure Investigation

When symptoms suggest the bug may not be in the code (timeouts, intermittent failures, environment-specific errors, deployment regressions), investigate infrastructure before or alongside code hypotheses.

**Signals requiring at least one infrastructure hypothesis:**

- Timeouts (request, query, container, deployment)
- Intermittent failures (5xx spike with no code change, error rate >0 but <100%)
- Environment-only manifestation (works locally, breaks in staging/prod)
- Symptoms correlate with a deployment, config change, secret rotation, or scale event
- Latency degradation without code change

**What to investigate:**

- **Logs & error tracking** — application logs for error spikes, upstream failures, correlation with deployments
- **Service health** — database connectivity/query performance, external service dependencies, container/process health (OOM kills, restart loops, CPU throttling)
- **Environment & config** — env var diffs between working/broken environments, recent config changes, secret rotations, certificate expirations, DNS/network/firewall
- **Resource limits** — memory, CPU, disk space, file descriptors, connection pool size vs active connections, external API rate limits

**Hypothesis quality bar:** "The database connection pool is exhausted under load" is testable — names the resource, condition, and observable signature. "Something is wrong with the server" is NOT a hypothesis — no variable to toggle, no falsifiable prediction.

---

## 4. Isolation Techniques

Once a hypothesis is confirmed, narrow down to exact code location.

**Binary search:** Disable half the relevant code path, check if the bug reproduces. Narrow iteratively. O(log N) iterations. Use when the confirmed hypothesis points to a general region but exact line/branch is unclear.

**Git bisect:** For regressions, identify the commit that introduced the bug.

```bash
git bisect start
git bisect bad HEAD
git bisect good <known-good-sha>
# git checks out midpoint; run repro; mark good/bad; repeat
git bisect reset
```

Use when the bug was absent at a prior commit. `git bisect run <repro-script>` automates the walk.

**Profiling:** For performance bugs, use profiling tools for quantitative data (timing, memory, allocation count). Code inspection cannot distinguish "slow because of N+1 query" from "slow because of N^2 allocation."

- Node: `node --prof`, `clinic.js`, `0x`, Chrome DevTools heap snapshots
- Python: `cProfile`, `py-spy`, `memray`
- Go: `pprof`
- JVM: `async-profiler`, JFR
- Browser: Performance panel, Memory panel, Lighthouse

**Pick the cheapest technique:** binary search if the region is large; git bisect if the regression boundary is known; profiling if the symptom is quantitative. Don't run all three.

---

## 5. Stall Diagnosis Taxonomy

When /geniro:debug stalls (the stall gate fires — threshold defined in SKILL.md §1.7), classify the root-cause-of-the-stall as a missing component:

| # | Missing component | Symptom | AUQ option label | AUQ description |
|---|---|---|---|---|
| A | **Missing instruction** | Hypothesis tests don't converge because the orchestrator lacks a project-specific rule (e.g., "we use SQS not Kafka here") | "Missing project rule" | Paste the rule or point to a CLAUDE.md / `.geniro/instructions/*` section |
| B | **Missing source-of-truth** | Test results contradict reasonable assumptions because canonical state (DB row, prod log line, third-party API response) is unreachable | "Missing source of truth" | Paste the DB row / log line / API response |
| C | **Missing tool** | Orchestrator cannot read the artifact format (binary blob, proprietary protocol, sandboxed environment) | "Missing tool" | Provide the parsed/decoded form, or specify a tool the user can run locally |
| D | **Missing validator** | Hypothesis tests "pass" via narrative-only Result but cannot be objectively verified (e.g., race-condition theories) | "Missing validator" | Author a deterministic re-runnable check (curl + grep, SQL query, regex on log) |
| E | **Missing permission rule** | Hypothesis blocked by safety-hook or `.geniro/safety.json` denial | "Missing permission" | Add the relevant pattern to `.geniro/safety.json` `allow_patterns` |
| F | **Missing sandbox signal** | Tests inconclusive because environment differs from production (Docker vs. host, ARM vs. x86) | "Missing sandbox signal" | Re-run in the production-like environment and paste the captured signal |
| G | **Missing eval** | Bug type has no existing regression test pattern in the project — hypotheses cannot be expressed in the existing test framework | "Missing eval pattern" | Author a new test pattern (parameterized fuzzer, mutation-test seed, etc.) |
| H | **Missing recovery path** | All hypotheses confirmed but the fix path is unclear because the bug spans a DI / generated-code / framework-internal layer | "Missing recovery path" | Specify whether the production-source escape hatch is acceptable, or escalate as architectural |

**AUQ rendering:** stall gate fires `AskUserQuestion` with header "Stall diagnosis". Render the most likely missing-component categories plus an "Abandon — present partial findings" option (AUQ maxItems=4, so typically the top 3 categories + Abandon) — the model picks categories based on stall context (inconclusive-test outputs, hypothesis types tried). "Abort" comes via "Other". Each option's `preview` (where helpful) shows what Phase 1 will do next.

**Persistence:** same structured-entry pattern as the Scientific-mode stall gate (SKILL.md §1.7 Stall escalation gate). Write a structured `open_questions[]` entry with `source: phase-1-stall-gate`, `question: <verbatim category text>`, `related_hypotheses: [<inconclusive H-IDs>]`, `status: unresolved`. On user pick of any surfaced missing-component category, update to `status: resolved` with `resolution.picked` and `resolution.resolved_by: debug`. On Abandon or Abort, the entry stays `unresolved` and Phase 3 §3.0 Pre-gate surfaces it before the escalation AUQ.

---

## 6. Adversarial Mode templates

### A5 spawn template

```
Agent(subagent_type="adversarial-tester-agent", prompt="""
## Task: Adversarial Edge-Case Test Authoring (Debug — Verify Changes)

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

### Diff (changed files + contents)
[Pre-inline `git diff <resolved-range>` output AND full contents of every changed source file from Step 1]

### Shared Edge-Case Checklist (READ this file yourself at runtime — do NOT paste here)
`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md`

### Project Test Framework
- Test command (from CLAUDE.md Essential Commands): [e.g. `pnpm test`, `pytest`]
- Test-file naming convention: [project's pattern — e.g. `*.test.ts` adjacent to source]
- Exemplar test files (1-2, pre-inlined): [closest existing test files to the changed code]

### Hypothesis Seeds
none — adversarial mode runs a fresh pass (no prior reviewer findings available in debug).

### Output
Write your report to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` (resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A). Authored test files go to the project's normal test paths. Do NOT git add/commit/push.

The handoff's frontmatter MUST include `authored_tests: [...]` carrying one entry per RED test kept after your 3× flake check. Inline this schema verbatim — the consumer (/geniro:implement Phase 1 handoff-resolution step) reads this field to relocate the tests into its worktree:

```yaml
authored_tests:
  - id: t1                            # stable anchor (t1, t2, ...)
    path: <repo-root-relative path>   # resolve against your current `git rev-parse --show-toplevel`
    intent: <one-line description of what the test guards>
    mode: adversarial                 # MUST be `adversarial` (matches top-level `mode:` discriminator)
    f_to_p_status: red-on-current     # only `red-on-current` is valid for kept adversarial tests
    targeted_source: <prod file path> # the production source the test attacks
    confidence: <high|medium|low>     # mirrors your A6 Confidence column
```

`authored_tests: []` (empty array) is the correct form for the zero-red-tests terminal outcome. Body `**Test file:**` lines remain the human-readable mirror; the frontmatter is the contract.

### F→P Invariant (NON-NEGOTIABLE)
Every test you keep MUST fail 3 times in a row on the current code. If it passes today, delete the test and mark `discarded-cannot-repro`. Flaky = discard.

### Scope
Diff-only — the orchestrator resolved the scope above. Do NOT author tests for files outside the changed-files list. Hard cap: 10 authored tests.

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""", description="Adversarial tests: /geniro:debug verify-changes")
```

### A6 findings template

After re-verification, present this block directly in chat and persist (via the agent's write at A4 step 3 + the orchestrator's re-verify delta if tests were discarded):

```markdown
## Adversarial Findings

**Diff scope:** [range + file count + LOC]

**Hypotheses generated:** [N]
**Tests authored (kept after re-verify):** [M]
**Tests discarded (F→P failed on re-run):** [K]

### CRITICAL / HIGH findings
[For each finding, emit these labelled lines — the `**Test file:**` line is the human-readable mirror of the `authored_tests[]` frontmatter array that consumers fall back to parsing for legacy handoffs:]
- **Test file:** `<path>`
- **Targeted source:** `<file:line>`
- **Category:** <category> · **Confidence:** <0-100>
- **Hypothesis:** <what breaks and why>
- **Reproduction:** `<command>`
- **Suggested direction:** <fix direction, NOT the patch itself>

### MEDIUM findings
[same labelled shape]

### Discarded / Inconclusive
[brief list with reasons]

**Zero red tests?** [If M == 0 after re-verify: state plainly "no bugs found in scanned diff" — this is a valid outcome.]
```

If zero red tests survive, skip escalation entirely and go directly to Cleanup. Otherwise proceed to escalation per A4 step 6.

---

## 7. Extended examples

### Example 2: Intermittent Timeout

```
/geniro:debug API endpoint times out randomly under load
```

→ Phase 1 Observe: Happens ~5% of requests during stress test
→ Hypothesis 1 (code): Database query too slow; Hypothesis 2 (infra): External service timeout
→ Test: Profile database queries, check service logs
→ Result: Hypothesis 2 confirmed (service is slow)
→ Phase 2 Propose: add timeout + fallback around the external service call
→ Verify: local experiment shows timeouts disappear with monkey-patch
→ Phase 3 Escalate: /geniro:implement with the proposed patch

### Example 3: Verify Recent Changes (Adversarial Mode)

```
/geniro:debug verify last changes
```

→ Phase 0 Mode detect: anchored "verify last changes" → Adversarial
→ A2 Diff resolution: `git diff main...HEAD` (per scope-anchor rule #3)
→ A4 Step 3: Spawn `adversarial-tester-agent` with pre-inlined diff + framework + exemplars
→ A4 Step 4: Independently re-run 7 authored tests; 5 fail RED, 2 pass-today (discarded)
→ A6 Adversarial Findings persisted to `from-debug-adversarial-<branch>.md`
→ Escalate: /geniro:implement with the authored tests as escalation targets
