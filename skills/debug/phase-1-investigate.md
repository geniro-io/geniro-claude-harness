# Debug Phase 1 — investigate

Phase file for `/geniro:debug`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`.

state.md `phase: investigate`. An entry-gate + context load plus an inner hypothesis-test loop. Exits to Phase 2 only when a hypothesis is confirmed AND its Result: field cites an artifact per Evidence Standard.

## Contents

- §1.1 Memory layer load · §1.2 Observe & repro · §1.3 Build feedback loop · §1.4 Hypothesize
- §1.5 Test each hypothesis + missing-data gate · §1.6 Isolate root cause · §1.7 Stall escalation gate
- Infrastructure investigation · Isolation techniques · Stall diagnosis taxonomy

### 1.1 Memory layer load (past-knowledge query)

On Phase 1 entry, in order:

1. **Refresh custom instructions** — `load-custom-instructions(SKILL_SLUG: debug, LOAD_TIER: pipeline, MODE: refresh)` per Echo contract; the pipeline tier's load set is owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`.
2. **Refresh project snapshot** — `load-semantic(MODE: refresh, top-2 default)`. Fingerprint drift check fires if applicable.
3. **Query past learnings** — `query-learnings(tags=<inferred from $ARGUMENTS>, scope=task path)` per "debug session start" trigger — route per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (under a declared `## Memory Backend` block routing `learnings`, /geniro:debug's own tools can't call the backend read tool, so it delegates that read to a scoped `knowledge-retrieval-agent` spawn — `SCOPE: learnings-backend` — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md` §3 and uses the returned learnings; the local file is empty under `mode: replace`, so the spawn is the only way to recall anything; no block → the inline file query runs unchanged). Pass `--limit 5` and filter superseded + deprecated. Skipped if $ARGUMENTS too generic to infer tags. A matching prior diagnosis primes Phase 1 hypotheses; the recurrence signal that drives the Phase 3 rule-capture offer is the emitted entry's `recurrence_count` (incremented by `emit-learning` on the file path; under `replace` the file counter no-ops, so recurrence is available only if the backend tracks it — see `recurrence-rule-capture.md` §0).
**surfacing convention:** when results include `discarded_hypothesis` entries, display them with a distinct label so the orchestrator can skip dead-ends faster:
```
Past investigations in this scope ruled out:
- <ext.hypothesis> (tested <ts> by <ext.tested_by>)
Past diagnoses:
- <summary> (fixed <ts>)
```
These get surfaced on hypothesis formation so that the orchestrator does NOT re-form a hypothesis equivalent to an already-ruled-out one without explicit re-justification.
4. **Cross-layer conflict resolution** — `resolve-conflicts(L2/L3/L4 loaded)` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md`. Echo lines per each helper's mandatory echo contract.

5. **Workflow refs read (when spec.md is in scope).** When `$ARGUMENTS` points to a spec.md path OR a planning task-dir, parse spec.md frontmatter `workflow_refs[]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md` — that file owns which schema versions a reader accepts and the rule that every consumer but /geniro:implement is tracker-read-only. Use the cached `status` field as hypothesis-priming context — "CI-303 still In Progress" vs "Done" guides whether the bug is in-flight code or already-shipped code. On `m5-v3` the cached parent-epic status and sibling sub-task statuses are also available to prime hypotheses (e.g. a sibling already shipped a related fix, so the regression may live in shared code). Skipped silently when no spec.md is in scope.

### 1.2 Observe & repro

- Reproduce the bug consistently and capture what the failure emits. Identify what changed. Record exact repro steps.
- **If repro is unclear/missing:** `AskUserQuestion` with header "Repro details" — 2-4 concrete options (environment / steps to trigger / expected vs actual behavior). Do NOT guess.
- **Check open PRs for an existing fix.** Before forming hypotheses, scan open PRs for one that may already fix this bug (ranked by overlap with the suspect / recently-changed files + symptom-keyword match in the PR title/body) — so the session does not re-investigate something already being patched. Surface matches as hypothesis-priming context; on a strong hit (file overlap AND keyword match) fire an `AskUserQuestion` (header "Existing fix") — review that PR's diff first / test it as a hypothesis / keep investigating — and persist the pick to `approvals[]` category `existing_fix_pr`. Read-only, fail-open (skipped with no GitHub remote or `gh` unavailable), Scientific Mode only. Full mechanism: `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §8.

Persist to state.md body sections `## Symptom` and `## Reproduction Steps` (per the body-section schema in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2).

### 1.3 Build feedback loop

A feedback loop is a fast (≤30s, ideally ≤5s), deterministic, captured signal that reproduces the bug AND can be re-run cheaply.

**Pick the cheapest mechanism that reliably reproduces** — an assertion, a request, a query, or a browser script, whichever matches the layer the bug lives at; a manual click-through is the fallback for a UI with no automation seam. Two shapes are not interchangeable with the rest: a regression that worked at commit X wants a differential test (good vs bad commit), and an intermittent bug wants a fuzz / loop reproducer feeding the reproduction-rate rule below.

**Quality bar:**
- **Fast** — re-runs in seconds. If only loop possible takes 5 minutes, shrink scope (smaller payload, in-memory mock, skip auth).
- **Deterministic** — same input → same observed failure (3-run signature comparison). If 3 consecutive runs produce 3 different signatures, you have a flake or two bugs — note this in state.md before continuing.
- **Intermittent?** Raise the reproduction rate rather than chasing a clean single-shot repro — loop the trigger 100×, parallelise, add load, inject sleeps to widen timing windows; remove unrelated nondeterminism by pinning time, seeding RNG, and isolating the filesystem. A 50% failure rate is debuggable; 1% is not. Record the attempt and its outcome in `## Feedback Loop` — the §2.4 repro-infeasible escape hatch opens only after this record exists.
- **Captured** — artifact satisfies Evidence Standard kind 1, 3, 4, or 5 (captured command output such as a failing assertion, log line, query result, or user-provided artifact — a run artifact, not the static file:line citation of kind 2). "I see it crash" is not a captured artifact.
- **Red on the right bug** — exit loop construction only when you can name one command, already run at least once with its invocation and captured output recorded, whose failure IS the symptom the user described — not a nearby failure. The wrong bug yields the wrong fix. Reading code to build a theory before this command exists is the tell: stop and return to loop construction.

If 10 minutes pass without a working feedback loop, do NOT proceed by guessing — `AskUserQuestion` with header "Repro signal" — paste log / run command / mark intermittent + investigate without loop.

**Minimise.** Once the loop is red on the right bug, shrink the repro to the smallest scenario that still fails: cut inputs, config, data, and steps one at a time, re-running the loop after each cut. Done when every remaining element is load-bearing — removing any one turns the loop green. A minimal repro shrinks the §1.4 hypothesis space and converts into the §2.4 reproduction test with little rework.

Persist to state.md `## Feedback Loop` body section: Command (the minimised form) / Expected output / Actual output / Re-run cost / Determinism (including any rate-raising attempt + outcome for intermittent bugs).

> **NOT the reproduction test.** The reproduction test is a unit/integration test in the project framework that ships with the fix as the regression guard. The feedback loop is a fast-iteration scratch signal so you can move quickly. The test STAYS on disk; the scratch signal is reverted at Cleanup.

### 1.4 Hypothesize

Based on Observation + Feedback Loop output, form **2-3 competing hypotheses**. Each must be testable against the feedback loop — each hypothesis test toggles one variable, re-runs the loop, and observes whether the captured signature changes. State each hypothesis as a falsifiable prediction — "if <X> is the cause, then <toggling Y> changes the captured signature in <way Z>". A hypothesis whose prediction you cannot state is a vibe, not a hypothesis — sharpen it or discard it.

**Consider infrastructure causes alongside code causes** per § Infrastructure investigation below — when the symptom matches any signal on that section's list, at least one hypothesis has to be an infrastructure hypothesis. **Deep-mode branch (`deep-mode: true`):** generate the hypothesis set via a 3× independent fan-out inside an internal `Workflow(...)`, then UNION + DEDUP (dedup key = hypothesis mechanism + targeted file/module) into one candidate set before the §1.5 test loop consumes it; the §1.5 testing stays orchestrator-inline (recall multiplies generation, not testing). Per `${CLAUDE_PLUGIN_ROOT}/skills/debug/deep-mode-reference.md` §2; fail-safe to the single-pass synthesis below if the workflow errors.

Persist to state.md `## Hypotheses` body section, one block per hypothesis (Hypothesis / Evidence For / Evidence Against / Status: pending → testing → confirmed | rejected | inconclusive / Test Plan / Result — per the body-section schema in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2).

**Render the ranked hypothesis list to chat before testing begins** — plain narration, NOT a gate: do not fire AskUserQuestion and do not block for a response. The user often re-ranks the list instantly from domain knowledge or names a hypothesis already ruled out, and a correction that arrives before the first test costs nothing.

> **Inconclusive** means the test could not distinguish whether the hypothesis is true or false. Common causes: (1) test environment differs from production, (2) bug is intermittent and didn't manifest, (3) test was too coarse, (4) multiple interacting causes mask effects. Inconclusive is NOT a rejection — you need a better test or more data.

### 1.5 Test each hypothesis + missing-data gate

- Design a minimal test per hypothesis. The test must produce a captured run artifact per Evidence Standard (kind 1, 3, 4, or 5 — command output, log line, query result, or user-provided artifact; not the static file:line citation of kind 2).
- Add logging, breakpoints, or unit tests to gather evidence. Tag every debug log line with one unique per-run prefix (e.g. `[DBG-a4f2]`) — §3.5 cleanup then reduces to a single grep, and no untagged straggler survives into the escalated diff. For performance symptoms, logs are the wrong instrument: capture a baseline measurement first (timing harness, profiler, query plan — § Isolation techniques) and test hypotheses against the number.
- Do NOT implement a fix yet — you're gathering data.
- **Missing-data gate:** when a probe you actually ran failed to reach the data the test requires (production logs, runtime state, third-party API responses, DB rows behind credentials, screenshots), do NOT mark the hypothesis inconclusive by default. `AskUserQuestion` with header "Missing data" — 2-4 concrete options for the specific artifact needed. When the user picks "I don't have it" or "Skip this hypothesis", persist a structured `open_questions[]` entry to state.md frontmatter with `source: phase-1-missing-data-gate`, `question: <verbatim missing-data prompt>`, `related_hypotheses: [<H-ID>]`, `status: unresolved`. The Phase 3 §3.0 Pre-gate surfaces it again before the escalation AUQ — sometimes the user discovers the missing artifact after the investigation completes and wants to amend.
- Example option set: "Paste the failing log line at the time of the error" / "Paste the request body that triggered the error" / "I don't have it — mark inconclusive"
- Record results: confirmed / rejected / inconclusive. Every Result: field cites an artifact per Evidence Standard — a "confirmed" carrying a narrative-only Result is rejected, because the next phase builds a fix proposal on it.

**Record a past learning for each rejected hypothesis.** For each hypothesis transitioning to `Status: rejected` (eliminated by a test that produced contradicting evidence), call `emit-learning` with type `discarded_hypothesis`, required `ext.{hypothesis, evidence_against, tested_by}`, trust `verified`. Scope = the file/module the hypothesis targeted. The emit is per-rejection (multiple rejections in one Phase 1 = multiple emits). Canonical payload shape: `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §9.

**Sliding-window cap:** 5 latest `discarded_hypothesis` entries per `(producer, scope)` — unbounded, discarded-hypothesis chatter drowns out `diagnosis` entries at retrieval time. Before emit, count existing non-deprecated entries via `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --type discarded_hypothesis --scope <scope> --include-superseded`; at 5 or more, prune per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Sliding-window caps on bookkeeping types, which owns the flip-then-append order and the locking that rewrite needs.

`rejected` is a normal outcome of hypothesis testing — emit fires in the happy path. `inconclusive` does NOT emit (the data is ambiguous; recording it would seed noise). `confirmed` does NOT emit a `discarded_hypothesis` (it emits a `diagnosis` later at Phase 3 §3.3).

state.md `phase: investigate` throughout. `## Hypotheses` body section grows iteratively.

### 1.6 Isolate root cause

Once a hypothesis is confirmed:
- Identify exact code location. Trace data/control flow. Apply techniques per § Isolation techniques below (binary search / git bisect / profiling).
- Understand why the bug happens (not just where).
- **Tag emitted findings per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.** `/geniro:debug` is the root-cause flow by definition — a confirmed hypothesis isolates to a `[ROOT-CAUSE]` finding, NOT `[SYMPTOM]`. `[UNKNOWN]` from debug is a failure mode — if you find yourself emitting `[UNKNOWN]`, the hypothesis loop didn't close (escalate via stall gate). `[SYMPTOM]` from debug is also a failure mode — re-enter with a new hypothesis.

Persist to state.md `## Root Cause` body section.

### 1.7 Stall escalation gate

When the hypothesis loop fails to converge — defined as **5 inconclusive hypothesis tests across all hypotheses** (enough attempts for the scientific-method loop to isolate a cause, few enough that a genuinely stuck investigation surfaces to the user before more turns are burned) — fire the stall gate before declaring the bug unsolvable:

1. **Do not silently report "cannot determine cause".**
2. Apply the 8-category diagnose-by-missing-component taxonomy (`## Stall diagnosis taxonomy` below).
3. **Render the investigation status to chat first** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering — what was tested (per-hypothesis results as a short `☐`/`✔` checklist) and which component categories remain unexplored — then fire the lean `AskUserQuestion` with header "Stall diagnosis": the most likely missing-component categories plus an explicit "Abandon — present partial findings" option (AUQ maxItems=4, so typically the top 3 categories + Abandon; if more categories are relevant, chain a second AUQ per the cap-extension pattern). "Abort" comes via the AUQ "Other" option.
4. state.md marks `phase: phase-1-escalated` with timestamp + inconclusive-test count + categorized stall hypothesis. Transitions:
- User picks a surfaced missing-component category → `phase: investigate` (resume hypothesis loop with new data).
- User picks "Abandon — present partial findings" → keep `phase: ship` (NOT the terminal yet) and proceed to Phase 3 with a stall-flagged findings summary; Phase 3 exit writes the terminal `ship-summary-only` (§3.2). Writing the terminal at the gate would strand a compaction-resume as "complete" before the summary + handoff are produced.
- User picks "Abort" (via "Other") → `phase: aborted` (terminal).

**Persist the stall as a structured open_questions[] entry** in state.md frontmatter (and mirror to the body `## Open Questions` section for human readability). Schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2:

```yaml
open_questions:
  - id: q<N>
    source: phase-1-stall-gate
    question: <verbatim stall question — the categories that were surfaced>
    related_hypotheses: [<inconclusive hypothesis IDs from ## Hypotheses>]
    status: unresolved
```

When the user picks a missing-component category, update the entry: `status: resolved`, `resolution.picked: <user pick>`, `resolution.resolved_by: debug`, `resolution.asked_in_phase: phase-1-stall-gate`. When the user picks Abandon or Abort, the entry remains `unresolved` — Phase 3 Pre-gate (§3.0) will surface it again before escalation.

---

## Infrastructure investigation

When the symptom matches any signal in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §3, form at least one infrastructure hypothesis alongside the code hypotheses. That section owns the signal list, the investigation checklist, and the hypothesis quality bar — read it rather than deciding from memory which symptoms qualify.

---

## Isolation techniques

Binary search / git bisect / profiling — full procedure in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §4. Pick the cheapest technique: binary search for large regions, git bisect for known-good→bad regression boundaries, profiling for quantitative symptoms.

---

## Stall diagnosis taxonomy

When the §1.7 stall gate fires, classify the stall as a missing component (8-category taxonomy A-H: missing instruction / source-of-truth / tool / validator / permission rule / sandbox signal / eval / recovery path). Full table + AUQ rendering + persistence rules in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §5.
