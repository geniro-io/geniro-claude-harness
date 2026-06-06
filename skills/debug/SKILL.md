---
name: geniro:debug
description: "Use when a bug needs systematic investigation. 3-phase loop (Investigate → Propose → Ship) mirroring /geniro:implement: observe → hypothesize → test → isolate → propose fix → author reproduction test, then escalate to /geniro:implement with a handoff file at .geniro/state/handoff/from-debug-<branch>.md. Adversarial mode authors F→P tests against a diff (verify-changes). Skip for bugs with obvious root cause — go straight to /geniro:implement."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, WebSearch]
argument-hint: "[bug description | verify <diff-range> | verify last changes]"
---

# Debug: Scientific-Method Investigation

Use this skill to systematically debug complex issues. Replaces guessing with evidence gathering and hypothesis testing. 3 phases mirroring `/geniro:implement`.

**Detailed contracts:**
- Infrastructure-cause guidance — see § Infrastructure Investigation below
- Isolation techniques (binary search / git bisect / profiling) — see § Isolation Techniques below
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Investigation-driven fix gate (debug-flavored) — multi-path fix gate and repro-infeasible escape hatch
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` — consumer protocol for downstream skills reading the handoffs this skill writes

---

## Your Role — Investigate, Don't Ship

You investigate. You isolate. You propose. You do NOT apply the fix. Phase 3 handoff is a text proposal + reproduction test on disk + a handoff file at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`. Downstream consumers (`/geniro:implement`, manual user action) apply the patch.

---

## State Machine

state.md `phase:` enum: `mode-detect` → `investigate` → `propose` → `ship` → `done` (Scientific Mode happy path). Terminal states: `done`, `ship-summary-only`, `aborted`, `adversarial-aborted` (SessionStart recovery treats these as complete). Escalation states: `phase-1-escalated`, `phase-2-escalated` (recovery surfaces "task was paused — last AUQ options:" so user re-picks without losing context). Adversarial Mode runs a parallel chain (`adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship` → `done`).

Full ASCII state diagram + non-terminal recovery rules in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §1.

---

## Loop Invariants

The invariants apply unchanged:

1. **One result per tool call.** Adversarial Mode parallel-spawn → each spawn must return a structured result; dead spawn → `status: failed` entry in `## Tool log`.
2. **Args validated before execution.** `$ARGUMENTS` semantic parse; PR ref validation via `mcp__github__pull_request_read` or GraphQL fallback.
3. **Permission before side-effect.** State.md writes via `atomic_state_write`. /geniro:debug performs NO `git push` / `gh pr create` — debug never ships code. Running under a dynamic `Workflow(...)` or ultracode mode does not relax this no-ship contract — the reporter boundary, action gate, and state-write rules bind inside every workflow step per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.
4. **Bounded and structured tool results.** `adversarial-tester-agent` output ≤4K chars per finding block; truncation marker. Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.
5. **Escalation gates, not silent abort.** stall gate (5 inconclusive) + fix-fail gate (2 attempts) escalate to user via AUQ. Never silently fabricate a conclusion.
6. **Final answer grounded in observations.** Evidence Standard for hypothesis confirmation — every Result: field in `## Hypotheses` MUST cite an artifact kind 1-5 per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. "Symptom matches" is correlation, not causation; not allowed.
7. **Errors → structured observations.** Failed `git diff`, denied permission, `adversarial-tester-agent` "agent not found" ladder fallback all become structured `## Tool log` entries before being acted on.
8. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

`## Tool log` schema: typical run produces 0-3 entries (subagent-spawn outcomes for adversarial mode, stall/fix-fail escalation entries). Routine Read / Edit / Bash skipped.

---

## Budgets — Quality-First

This skill has no hard kill caps. Runs at opus by default (deep hypothesis-driven investigation) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`.

**Quality gates (escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Inconclusive hypothesis tests | 5 across all hypotheses | stall gate | AUQ — diagnose-by-missing-component → user supplies missing or picks alternative |
| Fix attempts failed verification | 2 | fix-loop gate | AUQ — try different approach / accept as documented limitation / abort. User picks. |
| Adversarial mode authored tests | 10 hard cap | (delegated to agent contract) | Stop authoring; surface findings |
| Adversarial mode consecutive discards | 5 | (delegated to agent contract) | Stop hypothesis generation; surface partial |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| Subagent spawns | `codebase-research-agent` (Phase 1 codebase mapping, on demand) + `adversarial-tester-agent` (adversarial mode only) | |
| Reproduction-test framework | Project's native (detected from CLAUDE.md Essential Commands) | |

**Explicitly NOT capped:** wall-time, total tool calls, total model turns, total cost. Complex multi-cause bugs may legitimately need hours of investigation; hypothesis testing against a large codebase may need many Read/Grep calls.

---

## Subagent model tiering

Follow the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. OMIT `model=` at every plugin-agent spawn site — the agent's `model: inherit` frontmatter propagates the orchestrator's session tier (passing `model="inherit"` at the call site fails input validation; the runtime resolver picks up inheritance only when `model=` is unset). For plugin-defined subagents (adversarial-tester), also follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — registration ladder (`geniro-claude-plugin:<agent>` → bare `<agent>` → `general-purpose` with agent body inlined). Cache the resolved rung for the rest of the session.

Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site — every Agent prompt MUST satisfy the six pre-inlined fields.

| Spawn | Tier | Why |
|---|---|---|
| `codebase-research-agent` | inherit (OMIT `model=`) | Phase 1 codebase mapping / flow tracing / definition lookups (Loop Invariant #8). Inherits orchestrator tier so research runs at Opus on an Opus session. Targeted file:line reads tied to a specific hypothesis stay orchestrator-inline (Read / Grep / Glob). |
| `adversarial-tester-agent` | inherit (OMIT `model=`) | Reasoning-grade test authoring. Matches the canonical rule in `model-tiering.md` and call sites in `/geniro:review` Phase 4.3, `/geniro:implement` Phase 3. The agent's F→P verification + 3× flake check enforce correctness regardless of inherited tier. |

---

## Evidence Standard

Cite the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` — schema, forbidden phrases, and artifact kinds 1-5 are defined there. This skill applies that standard at every hypothesis-confirmation, fix-verification, and reproduction-test capture.

**Debug-specific framing — hypothesis-confirmation artifact kinds.** A hypothesis is **confirmed** only when its `Result:` field cites one of the artifact kinds 1-5 from the shared rule. Hypothesis-tracking is the most evidence-rigorous flow in the plugin: every entry in state.md § `## Hypotheses` Result must attach a captured artifact (kind 1: file:line + verified snippet; kind 2: captured command/test/build output; kind 3: log line / stack trace; kind 4: datastore query result; kind 5: user-provided artifact). Reasoning is correlation; only reproduction with a captured artifact confirms causation.

If the orchestrator's tools cannot produce evidence for a hypothesis (no DB access, no production logs, no credentials, no environment access), do NOT mark it inconclusive by default — use the missing-data gate in §1.5 to ask the user for the artifact.

---

## Universal Rule: All Choice Questions Use AskUserQuestion

Every user-facing choice in this skill — including ad-hoc gates not explicitly enumerated below — goes through the `AskUserQuestion` tool. Inlining `(A)... or (B)...` in chat skips the structured-answer record the resume hook reads back, so the choice is lost on compaction. The enumerated gates are examples, not an exhaustive list. If you're about to type `(A)... or (B)...` in chat, stop and call the tool instead.

---

## Phase 0 — Mode Detection ($ARGUMENTS routing)

state.md `phase: mode-detect`. **Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: debug`, `LOAD_TIER: pipeline`, `MODE: initial-load`. Echo per the helper's contract.

**Step 0.1 — Branch freshness.** On a fresh run (skip on compaction-resume), apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` — /geniro:debug investigates in place on the current branch, so if that branch is behind the default branch, offer to update it before the investigation starts. Skipped silently when the branch is already current.

$ARGUMENTS routing:

| $ARGUMENTS shape | Mode | Transition |
|---|---|---|
| empty | AUQ with header "Mode" — 4 options: "Describe the symptoms" / "Paste error message" / "Point to a failing test" / "Verify last changes (adversarial)". First 3 → Scientific. Fourth → Adversarial. | `mode-detect` → `investigate` OR `adversarial-mode-detect` |
| matches anchored verify-keyword signals (table below) | Adversarial Mode | `adversarial-mode-detect` |
| otherwise | Scientific Mode | `mode-detect` → `investigate` |

**Anchored verify-keyword signals** (bare keywords alone NOT enough — phrases like "verify that login returns 500" or "stress-test revealed a memory leak" are scientific-method bug reports, not verify requests):

- Anchored keyword signals: `verify <changes|diff|last|recent|my|this|PR>`, `break <my|the> diff`, `hunt for bugs in <diff|change|PR>`, `find edge cases in <diff|change|PR>`, `adversarial <mode|pass|scan|run>`, `stress-test <the diff|my change|last changes>`
- Phrase signals: `verify last changes`, `verify recent changes`, `verify my changes`, `check last changes`, `break my diff`
- Explicit diff range signals: `HEAD~N..HEAD`, `HEAD~N`, `main...HEAD`, bare PR ref (`#1234` or GitHub PR URL), bare branch name + verify keyword

**Approvals-persistence protocol:** before firing the empty-AUQ, check state.md frontmatter `approvals[]` for prior entry with `category: disambiguate_mode`. If found, use prior `picked` value. If not, fire AUQ → on user pick, append to `approvals[]` via `atomic_state_write` before proceeding. The session-start restore re-surfaces this saved choice from `approvals[]` on resume.

When in doubt (ambiguous input), default to Scientific Mode — user can re-invoke with explicit adversarial phrasing if needed.

---

## Phase 1 — Investigate

state.md `phase: investigate`. Mirrors `/geniro:implement` Phase 1 (entry-gate + context load) plus a Phase 2-style inner loop (hypothesis test iterations). Exits to Phase 2 only when a hypothesis is confirmed AND its Result: field cites an artifact per Evidence Standard.

### 1.1 Memory layer load (past-knowledge query)

On Phase 1 entry, in order:

1. **Refresh custom instructions** — `load-custom-instructions(MODE: refresh, scope: debug + global + code-style — pipeline tier, 3 files)` per Echo contract.
2. **Refresh project snapshot** — `load-semantic(MODE: refresh, top-2 default)`. Fingerprint drift check fires if applicable.
3. **Query past learnings** — `query-learnings(tags=<inferred from $ARGUMENTS>, scope=task path)` per "debug session start" trigger. Top-K=5 default, filter superseded + deprecated. Skipped if $ARGUMENTS too generic to infer tags. A matching prior diagnosis primes Phase 1 hypotheses; the recurrence signal that drives the Phase 3 rule-capture offer is the emitted entry's `recurrence_count`, incremented by `emit-learning` each time the same root cause re-emits.
**surfacing convention:** when results include `discarded_hypothesis` entries, display them with a distinct label so the orchestrator can skip dead-ends faster:
```
Past investigations in this scope ruled out:
- <ext.hypothesis> (tested <ts> by <ext.tested_by>)
Past diagnoses:
- <summary> (fixed <ts>)
```
These get surfaced on hypothesis formation so that the orchestrator does NOT re-form a hypothesis equivalent to an already-ruled-out one without explicit re-justification.
4. **Cross-layer conflict resolution** — `resolve-conflicts(L2/L3/L4 loaded)` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md`. Echo lines per each helper's mandatory echo contract.

5. **Workflow refs read (when spec.md is in scope).** When `$ARGUMENTS` points to a spec.md path OR a planning task-dir, parse spec.md frontmatter `workflow_refs[]`. Accept both `geniro_schema_version: m5-v1` (treat field as absent) and `m5-v2` (read the field if present). Use the cached `status` field as hypothesis-priming context — "CI-303 still In Progress" vs "Done" guides whether the bug is in-flight code or already-shipped code. Read-only — /geniro:debug never mutates tracker state via MCP. Skipped silently when no spec.md is in scope.

### 1.2 Observe & repro

- Reproduce the bug consistently. Capture error messages, logs, stack traces.
- Identify what changed (recent commit, config, user action). Record exact repro steps.
- **If repro is unclear/missing:** `AskUserQuestion` with header "Repro details" — 2-4 concrete options (environment / steps to trigger / expected vs actual behavior). Do NOT guess.

Persist to state.md body sections `## Symptom` and `## Reproduction Steps` (per the body-section schema in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2).

### 1.3 Build feedback loop

A feedback loop is a fast (≤30s, ideally ≤5s), deterministic, captured signal that reproduces the bug AND can be re-run cheaply.

**Pick the cheapest option that reliably reproduces:**

| Option | Use when | Example |
|---|---|---|
| Failing assertion in REPL / test runner | Bug is in pure logic, no I/O | `node -e "require('./src/cache').compute(...) // expect 5, got 7"` |
| `curl` against running dev server | Bug is in HTTP/API behavior | `curl -X POST localhost:3000/api/foo -d '{...}' -i` |
| SQL query against test DB | Bug is in query/migration logic | `psql -c "SELECT * FROM users WHERE..."` |
| Headless browser script | Bug is UI-rendered | Playwright snippet that takes one screenshot |
| Differential test (good vs bad commit) | Regression — works at commit X, broken now | `git checkout <good>; <repro>; git checkout <bad>; <repro>` |
| Fuzz / loop reproducer | Bug is intermittent | `for i in {1..100}; do <repro>; done | grep ERROR` |
| Manual click-through script | Genuinely UI-only with no automation seam | numbered steps in state.md (use as fallback only) |

**Quality bar:**
- **Fast** — re-runs in seconds. If only loop possible takes 5 minutes, shrink scope (smaller payload, in-memory mock, skip auth).
- **Deterministic** — same input → same observed failure (3-run signature comparison). If 3 consecutive runs produce 3 different signatures, you have a flake or two bugs — note this in state.md before continuing.
- **Captured** — artifact satisfies Evidence Standard kinds 2-5 (failing assertion, log line, query result). "I see it crash" is not a captured artifact.

If 10 minutes pass without a working feedback loop, do NOT proceed by guessing — `AskUserQuestion` with header "Repro signal" — paste log / run command / mark intermittent + investigate without loop.

Persist to state.md `## Feedback Loop` body section: Command / Expected output / Actual output / Re-run cost / Determinism.

> **NOT the reproduction test.** The reproduction test is a unit/integration test in the project framework that ships with the fix as the regression guard. The feedback loop is a fast-iteration scratch signal so you can move quickly. The test STAYS on disk; the scratch signal is reverted at Cleanup.

### 1.4 Hypothesize

Based on Observation + Feedback Loop output, form **2-3 competing hypotheses**. Each must be testable against the feedback loop — each hypothesis test toggles one variable, re-runs the loop, and observes whether the captured signature changes.

**Consider infrastructure causes alongside code causes** per § Infrastructure Investigation below. If symptoms include timeouts, intermittent failures, or environment-only manifestation, form at least one infrastructure hypothesis.

Persist to state.md `## Hypotheses` body section, one block per hypothesis (Hypothesis / Evidence For / Evidence Against / Status: pending → testing → confirmed | rejected | inconclusive / Test Plan / Result — per the body-section schema in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2).

> **Inconclusive** means the test could not distinguish whether the hypothesis is true or false. Common causes: (1) test environment differs from production, (2) bug is intermittent and didn't manifest, (3) test was too coarse, (4) multiple interacting causes mask effects. Inconclusive is NOT a rejection — you need a better test or more data.

### 1.5 Test each hypothesis + missing-data gate

- Design a minimal test per hypothesis. The test must produce a captured artifact per Evidence Standard kind 2-5.
- Add logging, breakpoints, or unit tests to gather evidence.
- Do NOT implement a fix yet — you're gathering data.
- **Missing-data gate:** if testing requires data the orchestrator's tools cannot reach (production logs, runtime state, third-party API responses, DB rows behind credentials, screenshots), do NOT mark the hypothesis inconclusive by default. `AskUserQuestion` with header "Missing data" — 2-4 concrete options for the specific artifact needed. When the user picks "I don't have it" or "Skip this hypothesis", persist a structured `open_questions[]` entry to state.md frontmatter with `source: phase-1-missing-data-gate`, `question: <verbatim missing-data prompt>`, `related_hypotheses: [<H-ID>]`, `status: unresolved`. The Phase 3 §3.0 Pre-gate surfaces it again before the escalation AUQ — sometimes the user discovers the missing artifact after the investigation completes and wants to amend.
- "Paste the failing log line at the time of the error" / "Paste the request body that triggered the error" / "I don't have it — mark inconclusive"
- "Run this query against the production DB and paste the result: `<query>`" / "I can't run that query" / "Skip this hypothesis"
- "Provide a screenshot of the broken state" / "I don't have it — skip"
- Record results: confirmed / rejected / inconclusive. Every Result: field MUST cite an artifact per Evidence Standard. "Confirmed" with narrative-only Result is rejected.

**L2 emit on REJECTED:** For each hypothesis transitioning to `Status: rejected` (eliminated by a test that produced contradicting evidence), call `emit-learning` with type `discarded_hypothesis`, required `ext.{hypothesis, evidence_against, tested_by}`, trust `verified`. Scope = the file/module the hypothesis targeted. The emit is per-rejection (multiple rejections in one Phase 1 = multiple emits).

Example payload:
```json
{
"producer": "/geniro:debug", "scope": "services/payments/refunds.py",
"summary": "env-vars differ — eliminated (env identical local/CI)",
"tags": ["bug", "ci", "env-vars"], "type": "discarded_hypothesis",
"ext": {
"hypothesis": "env-vars differ between local and CI",
"evidence_against": "diff <(env | sort) <(ssh ci env | sort) returns empty",
"tested_by": "manual env diff"
}, "trust": "verified"
}
```

**Sliding-window cap:** keep at most 5 latest `discarded_hypothesis` entries per `(producer, scope)`. Before emit, count existing non-deprecated entries via `query-learnings --type discarded_hypothesis --scope <scope> --include-superseded`; if ≥5, mark the oldest matching entry `deprecated: true` BEFORE appending the new one. This field-flip is a mutation of `.geniro/knowledge/learnings.jsonl`, which the state-helper enforcement hook guards — perform it through the atomic-write path (rewrite the file via `atomic_state_write`, not a direct `Edit`/`Write`), and rely on the `enforce-state-helper` allow-pattern in `.geniro/safety.json` only if the atomic path is unavailable. Prevents discarded-hypothesis chatter from drowning out `diagnosis` entries at retrieval time.

`rejected` is a normal outcome of hypothesis testing — emit fires in the happy path. `inconclusive` does NOT emit (the data is ambiguous; recording it would seed noise). `confirmed` does NOT emit a `discarded_hypothesis` (it emits a `diagnosis` later at Phase 3 §3.3).

state.md `phase: investigate` throughout. `## Hypotheses` body section grows iteratively.

### 1.6 Isolate root cause

Once a hypothesis is confirmed:
- Identify exact code location. Trace data/control flow. Apply techniques per § Isolation Techniques below (binary search / git bisect / profiling).
- Understand why the bug happens (not just where).
- **Tag emitted findings per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.** `/geniro:debug` is the root-cause flow by definition — a confirmed hypothesis isolates to a `[ROOT-CAUSE]` finding, NOT `[SYMPTOM]`. `[UNKNOWN]` from debug is a failure mode — if you find yourself emitting `[UNKNOWN]`, the hypothesis loop didn't close (escalate via stall gate). `[SYMPTOM]` from debug is also a failure mode — re-enter with a new hypothesis.

Persist to state.md `## Root Cause` body section.

### 1.7 Stall escalation gate

When the hypothesis loop fails to converge — defined as **5 inconclusive hypothesis tests across all hypotheses** — fire the stall gate before declaring the bug unsolvable:

1. **Do not silently report "cannot determine cause".**
2. Apply the 8-category diagnose-by-missing-component taxonomy (`## Stall Diagnosis Taxonomy` below).
3. **Surface to user via `AskUserQuestion`** with header "Stall diagnosis" — render the most likely missing-component categories plus an explicit "Abandon — present partial findings" option (AUQ maxItems=4, so typically the top 3 categories + Abandon; if more categories are relevant, chain a second AUQ per the cap-extension pattern). "Abort" comes via the AUQ "Other" option.
4. state.md marks `phase: phase-1-escalated` with timestamp + inconclusive-test count + categorized stall hypothesis. Transitions:
- User picks a surfaced missing-component category → `phase: investigate` (resume hypothesis loop with new data).
- User picks "Abandon — present partial findings" → `phase: ship-summary-only` (proceed to Phase 3 with a stall-flagged findings summary).
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

## Phase 2 — Propose

state.md `phase: propose`. Output authoring: text fix proposal + F→P reproduction test. **No production-source edits applied.** Exits to Phase 3 when fix proposal AND reproduction test are both verified.

### 2.1 Refresh custom instructions on entry (single — no double-refresh)

On Phase 2 entry, single `load-custom-instructions(MODE: refresh, scope: debug + global + code-style — pipeline tier, 3 files)` call. Mirrors Phase 3 entry contract: always re-fires. Cost: 1 helper read.

### 2.2 Multi-path fix gate (Always-WAIT)

If the confirmed root cause has more than one valid fix path with real trade-offs (e.g., snapshot-vs-live-fetch, COALESCE vs CHECK constraint vs catch+log, fix-at-source vs fix-at-call-site), do NOT pick one and write a single text proposal.

**Fire `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Investigation-driven fix gate (debug-flavored)**:
- `header: "Fix path"`
- `question` text: confirmed root cause's `path:lines` + hypothesis title
- Each option:
- `label` (1-5 words) — name of the path
- `description` — one-line trade-off
- `preview` — investigation context (Root cause / Evidence from `## Hypotheses` Result / Hypothesis-confirmed status + number per the helper's source-field map)

**Approvals-persistence:** before firing, check state.md frontmatter `approvals[]` for prior entry with `category: multi_path_fix` and matching `root_cause` (use root-cause text as the disambiguator). If found, use prior `picked` value. If not, fire AUQ → on user pick, append entry to `approvals[]` via `atomic_state_write`.

**Re-ask trigger:** if the root cause changes (second-pass investigation overturns the prior root cause), the prior `approvals[]` entry is stale — clear it and re-fire. The session-start restore re-surfaces this from `approvals[]` on resume.

The single-text-proposal default applies ONLY when there is one obvious right fix; multi-path is the explicit branch.

### 2.3 Text fix proposal

- Formulate the minimal fix for the root cause as a **text proposal**: file path(s), exact change (unified diff or before/after snippet), one-sentence rationale.
- Do NOT write the fix to production/source files. Write/Edit are available for EXPERIMENTS only (tests, logging, debug scripts, `.geniro/state/debug/<slug>/` artifacts) — not for applying the proposed patch.
- If any experiment modified non-test source, revert those edits before escalation; the escalated skill applies the real fix cleanly.
- Do NOT refactor adjacent code.

Persist to state.md `## Proposed Fix` body section.

### 2.4 Author F→P reproduction test + monkey-patch verify

**Author the reproduction as a unit/integration test in the project's test framework**, placed at the project's normal test path next to the source it covers. Detect framework + naming convention from CLAUDE.md Essential Commands + an exemplar test file. Scripts / curl / ad-hoc queries are NOT acceptable substitutes — they get deleted at Cleanup and leave no regression guard.

**Test name + comments rule.** The reproduction test name AND any comments inside the test describe the bug behavior — the input, condition, or observable failure — never the hypothesis number from `## Hypotheses` or any other thread-local label. Tags like `Bug A/B/C`, `Hypothesis 1/2`, `Test 1`, `Case X`, `Issue #N from this run`, `regression from review run`, `found by review-gate`, or `confirmed by this <skill> run` are meaningless once the investigation ends. Prefer `cacheKey omits userId so role change leaves stale cached profile` over `Bug C`.

**F→P invariant.** Pre-fix: run the authored test ≥2× and confirm the SAME failure signature both times (same exception type + same failing assertion). Two divergent failures are NOT confirmation — investigate flakiness or two bugs before continuing.

**Verify the proposed fix — monkey-patch in the test by default; production-source edits are an explicit escape hatch.** Apply the patch locally as a monkey-patch inside the authored test file (mock, fixture, test-local shim, or a throwaway helper imported only by the test). Re-run the authored test ≥2× post-fix and confirm the failure DISAPPEARS both times. If the bug genuinely cannot be verified without editing production source (hard-to-mock chain — DI container, framework hook, native module, generated code), list every touched production file under "Verification edits to revert:" in the findings, confirm each is reverted before escalation, and re-run `git diff` to prove the working tree contains only the reproduction test.

**Escape hatch — non-deterministic bugs only.** If the bug is genuinely non-reproducible at the test layer (race conditions only seen under load, environment-only failures, UI flake), `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Investigation-driven fix gate (debug-flavored):
- `header: "Repro infeasible"`
- `question`: best-guess root-cause `path:lines` (or "unknown" if not isolated) + hypothesis title
- Options: regression-guard alternatives — "Add runtime assertion" / "Author fuzz seed" / "Add monitor/alert" / "Skip regression guard" (description carries one-line trade-off)

Record the user's selection AND rationale in state.md `## Reproduction Test` body section under "Reproduction Decision". The default is mandatory; escape hatch is opt-in with a paper trail.

Do NOT run the full project test suite here — that's the receiving skill's responsibility. Phase 2's goal is the F→P-verified test artifact + evidence the proposed patch turns it green.

If the project uses code generation (check CLAUDE.md) AND the proposed fix touches DTOs/schemas/controllers: note this in the findings template "Special handling" field.

### 2.5 Fix-loop escalation (2 fix attempts failed → AUQ)

When 2 distinct fix proposals fail F→P verification (each pre/post-fix monkey-patch round counts as one), surface to user — mirrors escalation pattern:

1. Do **not** silently report "no fix works".
2. `AskUserQuestion` with header "Fix-fail" and options:
- **Try different approach** — go back to (Hypothesize) with a fresh angle. state.md transitions back to `phase: investigate`.
- **Accept as documented limitation** — proceed to Phase 3 ship sub-step with `## Accepted Limitations` block in state.md body. state.md transitions to `phase: ship`. Receiving skill sees the unresolved limitation in the findings summary.
- **Abort** — `phase: aborted` (terminal).
3. state.md marks `phase: phase-2-escalated` with timestamp + fix-attempt count + accumulated test outputs. The session-start restore re-surfaces the open question on resume.

**L2 emit on fix-loop exit.** When Phase 2 exits AND `fix_attempts ≥ 2`, call `emit-learning` with type=`retry_failure_sequence`, trust=`verified`, required `ext.{phase: "fix-attempts", attempts: [{round: N, failure: "<why this attempt did not verify>"}], resolution}`. `resolution` ∈ `{passed, escalated, aborted}` (passed = test confirmed fix; escalated = user picked "Try different approach" or "Accept as documented limitation"; aborted = terminal). Sliding-window cap = 3 latest per `(producer, scope, phase)`. Single-attempt exits (fix_attempts == 1) do NOT emit. Scope = the file/module the fix targeted.

---

## Phase 3 — Ship

state.md `phase: ship`. Findings handoff to downstream skill OR user-handles. **No `git push` / `gh pr create`** — debug never ships code, only proposals + tests authored locally.

### 3.0 Pre-gate — Resolve Open Questions

Fires FIRST in Phase 3 — before the findings summary, before the escalation AUQ — whenever state.md frontmatter `open_questions[]` carries any entry with `status: unresolved`. Open questions surface ambiguity that downstream consumers (typically /geniro:implement) need resolved before applying a fix; resolving them here means the escalation AUQ chooses between a known-shape target rather than between paths that still gate on ambiguity.

**Procedure:**

1. Read state.md frontmatter `open_questions[]`. Filter to entries with `status: unresolved`.

2. For each unresolved entry, fire one `AskUserQuestion`:
   - `header`: `"Open question"`
   - `question`: the entry's `question:` field, verbatim
   - `options`: synthesized from the entry's context. Examples:
     - Stall categories (Phase 1 stall gate) → re-render the stall categories surfaced in Phase 1 (the set persisted in this entry's `question:` field) plus the "Abandon" option; do not introduce categories that were not originally surfaced.
     - Multi-path fix deferred → render the original path options.
     - Cannot-verify deferred → render "Provide the missing data" / "Mark as accepted limitation" / "Escalate to /geniro:investigate".
   - Always-WAIT — empty answer = upstream bug, re-ask.

3. Update the entry in-place via `atomic_state_write`: `status: resolved`, `resolution.picked`, `resolution.at`, `resolution.asked_in_phase: phase-3-pre-gate`, `resolution.resolved_by: debug`. Preserve `id`, `source`, `question`, `related_hypotheses`.

4. Mirror the resolution into the body `## Resolved Questions` section per the schema example in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2.

5. When >4 unresolved entries, chain into a second AUQ batch per the AskUserQuestion cap-extension pattern.

6. After the last unresolved entry resolves, verify all `open_questions[].status` are in `{resolved, wontfix}` before proceeding to §3.1. If any `unresolved` remains, loop back to step 2.

**Wontfix path.** If the user picks "Other" with text like "ignore" / "skip" / "not now", set `status: wontfix` and `resolution.picked` to the user's text. Wontfix entries do NOT block downstream consumers — they're recorded but de-prioritized.

**No-skip rule.** This gate cannot be deferred to /geniro:implement or to the user's manual patch path. /geniro:debug is the producer that surfaced the ambiguity; resolving here makes the handoff actionable. Resolving downstream creates the failure mode this gate exists to prevent. The exception: when §3.2 fires and the user picks "Cannot verify — request specific data from user", that response itself IS a resolution path — emit a new `open_questions[]` entry with `source: phase-3-cannot-verify`, `status: unresolved`, then loop back to step 1 above when data arrives.

Skipped silently when `open_questions[]` has zero `unresolved` entries.

### 3.1 Present findings (chat + persist handoff)

Before asking where to route the fix, present a human-readable findings summary to the user. Do NOT jump straight to the escalation AUQ — the user chooses the escalation target based on this summary.

Output the markdown block directly in chat AND write the same content (with full frontmatter wrapping it) to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` via `atomic_state_write`. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so the handoff survives worktree teardown.

**Findings template body:**

```markdown
## Debug Findings

**Source branch:** [from `git branch --show-current`]

**Source worktree:** [from `git rev-parse --show-toplevel`]

**Why escalating to <target>:** [one sentence — which target and concrete reason scope fits it; user makes the final routing choice in the escalation question (§3.2)]

**Root cause:** [one sentence, plain language — why the bug happens]

**Reproduction:** [exact steps that trigger the bug]

**Confirmed hypothesis:** [which numbered hypothesis from `## Hypotheses` was confirmed, and the test result that confirmed it]

**Rejected hypotheses:** [brief — which hypotheses were ruled out and why]

**Proposed fix:**
- Files: [path(s) that need to change]
- Change: [unified diff or before/after snippet]
- Rationale: [one sentence tying the change to the root cause]

**Evidence the fix works:** [default: "failing test went green under in-test monkey-patch; production source untouched"; or "<n> production files edited as escape hatch and reverted; bug stopped reproducing"]

**Reproduction test:** [<path>, <F→P status — example: "verified red on current code; verified green under throwaway patch"> — OR — "escape hatch: <alternative guard with rationale>"]

**Special handling:** [codegen, migrations, schema changes, env/config updates — or "none"]

**Stall-flagged?** [omit if stall gate did NOT fire; if it did: "Yes — cause not fully isolated; <component> identified as missing. Receiving skill should treat this as a starting point, not a closed investigation."]

**Accepted limitations?** [omit unless fix-fail path "Accept as documented limitation" was taken; if so: "<description of limitation>; user accepted on <ISO timestamp>"]
```

**Populate `authored_tests[]` frontmatter (REQUIRED).** Alongside the body template above, write the `authored_tests[]` frontmatter array per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2 and the canonical contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §Producer-specific extensions. Each F→P test authored in §2.4 gets one entry: `{id: t<N>, path: <repo-root-relative>, intent: <one-line guarantee>, mode: scientific, f_to_p_status: <enum>, related_hypotheses: [<H-IDs>]}`. If no test was authored (path B "Accept as documented limitation" or §2.4 escape-hatch with body `**Reproduction test:** escape hatch: <...>`), emit a single entry with `f_to_p_status: escape-hatch` and `intent: "escape-hatch: <verbatim rationale>"` — never omit the array. The body `**Reproduction test:**` line stays as human-readable mirror; the frontmatter is the machine-readable source for /geniro:implement's Phase 1 authored-test extraction (which invokes `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` to verify presence in the consumer's worktree and surface relocation suggestions if MISSING).

The receiving skill pre-loads findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` — the state file is the handoff channel, not a chat paste. Do NOT re-derive, reword, or inline the summary into the escalation command; the file path IS the contract.

### 3.2 Escalation AUQ (4 options)

Only after the summary above is visible AND persisted, `AskUserQuestion` with header "Escalate" and these options:

- **Trivial — run `/geniro:implement`** — ≤2 files, obvious target, no architecture or auth/permissions change.
- **Non-trivial — run `/geniro:implement`** — touches multiple modules, changes interfaces, needs architecture review, or introduces a new pattern. (Both Trivial and Non-trivial route to the same target — `/geniro:implement`. The Trivial/Non-trivial designation surfaces in the spec context the receiving skill loads.)

Both `/geniro:implement` options pre-load findings from the handoff file written above (`from-debug-<branch>.md`); the receiving skill resolves its path itself, so the option labels stay free of internal path placeholders.
- **Cannot verify — request specific data from user** — pick this when one or more hypotheses are unverified because the orchestrator's tools cannot reach the artifact. Trigger a follow-up `AskUserQuestion` with concrete options for the missing data. When data arrives, return to the §3.0 Pre-gate, do NOT escalate yet.
- **Leave it to me** — user will apply the patch manually using the state file as reference. state.md transitions to `phase: ship-summary-only` (terminal).

Do NOT auto-invoke the next skill — surface the suggestion only. State file IS the handoff channel. You do NOT apply the patch yourself.

### 3.3 Emit learnings + offer to capture a recurring diagnosis as a rule

At Phase 3 exit, fire the `diagnosis` emit below, then run the recurring-diagnosis rule offer. Sequence the emit before the phase is declared done — a diagnosis emit left trailing after the handoff is persisted and the answer is delivered is the documented drop vector that kept L2 sparse (confirmed root causes recorded nothing). The visibility + ordering rules bind here: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract". The other two `emit-learning` types fire earlier in their own phases — listed here together so the full debug emit surface is visible in one place:

- **`emit-learning`** — called by /geniro:debug at three distinct points:
- **`diagnosis`** (primary emit type, fires at Phase 3 exit on confirmed root cause) — every confirmed root cause emits one entry with summary, tags (inferred from affected-files + hypothesis category), scope (project-relative path glob), and required `ext.{symptom, root_cause, fix}` per typed-extension table. Default trust `verified`. After a successful emit, echo `Recorded learning: <summary>` to the user — the helper writes silently, so the echo is the only in-session signal the diagnosis was captured.
- **`discarded_hypothesis`** (fires per-rejection during Phase 1) — every rejected hypothesis emits one entry with required `ext.{hypothesis, evidence_against, tested_by}`. Sliding-window cap = 5 latest per `(producer, scope)`. See §1.5 for the payload schema and emit logic.
- **`retry_failure_sequence`** (fires at Phase 2 exit, conditional on `fix_attempts >= 2`) — captures the failed fix-attempt chain with required `ext.{phase, attempts, resolution}`. Single-attempt exits do not emit. See §2.5 for the payload schema and emit logic.
- **NOT emitted :** `pitfall` (/geniro:refactor + /geniro:review own), `convention` (/geniro:implement self-review owns), `decision` (/geniro:plan owns), `discovery` (/geniro:refactor + /geniro:onboard + /geniro:investigate own).

- **Offer to capture a recurring diagnosis as a project rule:** when the emitted diagnosis carries `recurrence_count >= 3` (this exact root cause has now been recorded three or more times — a real recurring pattern, not a one-off), offer to turn it into a project rule. Below the threshold, surface nothing — single or twice-seen diagnoses do not warrant a rule.

  0. **Read back the recurrence count.** `emit-learning` appends silently and echoes nothing, so the count is not available from the emit return. Re-query to read it: `query-learnings --type diagnosis --include-superseded` filtered to the just-written `dedup_key`, and read `recurrence_count` off the matched entry. Gate the steps below on that value — skip the offer entirely if it is below 3.
  1. **Dedupe check first.** Grep the existing project rules under `.geniro/instructions/` (`global.md`, `debug.md`, `code-style.md`) for the diagnosis's root-cause keywords. If a rule already covers this pattern, skip the offer entirely — surface a one-line note that an existing rule already covers it and continue.
  2. **Otherwise, ask.** Fire an `AskUserQuestion` (header "Capture as rule") — question: "This pattern has come up repeatedly — want to capture it as a project rule?" with the recurring diagnosis summary and recurrence count in the description. Options (plain-English labels):
     - **Save as a project rule** — hand off to `/geniro:instructions create` so the user authors the rule there.
     - **Refine, then save as a rule** — same handoff; the user reshapes the wording before saving.
     - **Merge into an existing rule** — same handoff; the user folds it into a related rule.
     - **Don't save** — decline; nothing is written.
  3. **On a save / refine / merge pick:** hand off to `/geniro:instructions create` — the user authors the rule there. Suggest a starting scope from the diagnosis category (style/convention → `code-style.md`; workflow/process → `debug.md`; architecture/global → `global.md`; otherwise the user picks). Do NOT auto-write any instruction file — the user stays the source of truth for project rules.
  4. **Log a decline.** After the AUQ resolves (any outcome), source `${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh` and invoke once; the helper no-ops unless the pick is an explicit decline ("Don't save" or cancel), so a future run does not re-offer a rule the user has already passed on. Pass no recommended arg — the three accept options ("Refine, then save as a rule" / "Merge into an existing rule") are not rejections:

```bash
emit_rejection_if_signal \
"/geniro:debug" "debug/<scope>" "promote_diagnosis_to_rule" \
"Capture recurring diagnosis as project rule" "<picked label>"
```

### 3.4 Suggest improvements (project scope only, routes)

After L2 emit, follow the canonical routing in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md`. Debug runs typically surface:

| Insight category | Target | layer |
|---|---|---|
| Coding conventions / naming patterns discovered during isolation | `.claude/rules/<scope>.md` with `paths:` glob frontmatter | L4 procedural |
| Docs describing behavior not matching reality | `CLAUDE.md` or project docs | L3 semantic |
| New/changed commands discovered during debugging | `CLAUDE.md` (Essential Commands section) | L3 semantic |
| Non-obvious debugging insights / workarounds | `.geniro/knowledge/learnings.jsonl` (via `emit-learning`) | L2 episodic |
| Skill-behavior quality gates / workflow steps user enforced manually | `.geniro/instructions/debug.md` or `.geniro/instructions/global.md` | L4 procedural |

Plugin-internal paths (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope.

### 3.5 Cleanup

After Phase 3 completes (escalated, accepted, or user-handles):

- **Scientific-method mode only:** Remove `.geniro/state/debug/<slug>/state.md` for the current branch's slug only, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract — its useful content has already been saved (root cause, repro, hypotheses-tested-and-rejected, accepted limitations) via L2 emit + persisted handoff. Do NOT delete sibling slugs from concurrent debug sessions on other branches.
- **Clear old state files** (best-effort; any may not exist):
```bash
rm -f ".geniro/debug/HYPOTHESES.md" 2>/dev/null
rm -f ".geniro/debug/HYPOTHESES-${slug}.md" 2>/dev/null
rm -f ".geniro/state/debug/HYPOTHESES-${slug}.md" 2>/dev/null
rm -f ".geniro/state/debug/findings-state.md" 2>/dev/null
rm -f ".geniro/state/debug/adversarial-tests.md" 2>/dev/null
```
- **Scientific-method mode only:** Remove debug scripts, scratch reproductions, the feedback-loop scratch signal, and ad-hoc curl/query files created during investigation. The reproduction test (authored at project's normal test path) STAYS on disk — it ships with the fix as the regression guard.
- **Scientific-method mode only:** `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` must remain on disk as the escalation handoff channel, so do not delete it. Stays until next debug run overwrites it (single file per branch).
- Kill any background processes started during investigation (dev servers, watchers, profilers).
- **Adversarial mode:** `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` may remain as audit trail; authored test files stay on disk (unlike scientific-method experiments which get reverted).

Cleanup is best-effort — if a command fails silently, that's fine.

### 3.6 Atomic non-resumable updates

After each side-effect that cannot be replayed safely (none in baseline — debug performs no `git push` / `gh pr create`), append a structured entry to state.md frontmatter `non-resumable-actions[]` via `atomic_state_write`.

The empty baseline is intentional: debug ships proposals, not commits. If a future user-customization introduces side-effects (e.g. a `.geniro/actions/post-finding-to-slack.md` invocation), THAT action becomes a non-resumable entry — not the standard ship flow.

---

## Adversarial Mode (verify-changes)

state.md `mode: adversarial`. Phases: `adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship`. Parallel to Scientific Mode; shared Phase 0 routes here on anchored verify-keyword signals (Phase 0 above).

### A1. Purpose

Attacker-mindset pass that AUTHORS executable F→P failing tests against a diff. Complements Scientific Mode: Scientific Mode REPORTS hypotheses about a known bug; Adversarial Mode hunts for unknown bugs in recent changes by writing tests that fail on today's code. Test authoring is delegated to `adversarial-tester-agent`; the orchestrator independently re-runs authored tests to confirm the failure before surfacing findings.

### A2. Diff resolution

**Diff resolution follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`** for the default scope + base-branch resolution; the supported explicit input shapes are enumerated below (self-contained — no cross-skill parser dependency).

**Default when no explicit range:** scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` — anchor on the current cwd's worktree + currently-checked-out branch. Resolve the base branch per scope-anchor rule #3 (`git symbolic-ref --short refs/remotes/origin/HEAD`). Compute `git diff <base>...HEAD`. If on the base branch, fall back to `HEAD~1..HEAD`.

**Supported shapes:** bare keyword (`"verify last changes"`) → default; explicit range (`HEAD~3..HEAD`, `abc123..def456`); branch (`feat/foo...HEAD`); PR ref (strip leading `#`, resolve via `gh pr diff <number-or-url>` or `mcp__github__pull_request_read`).

### A3. Skip conditions

Adversarial mode is SKIPPED and the skill reports `"no adversarial pass — <reason>"` when:

- Empty diff (nothing to test).
- Diff contains zero production-code files (docs / config / lock / generated only).
- Diff >50 changed files OR >1000 changed LOC → suggest `/geniro:review` for oversized diffs (the agent's authored-test hard cap wastes budget on diffs this large).

### A4. RED-phase workflow

Runs the **RED phase** of the canonical cycle at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § RED phase: author the failing test FIRST, verify it fails with a real assertion signature, then escalate the fix to the receiving skill (which runs GREEN). Tests are never authored alongside or after the fix in this mode — RED-first ordering is non-negotiable.

1. **Resolve the diff** (A2). Pre-inline full diff + changed-file contents for the spawn prompt.
2. **Detect the project test framework.** Read CLAUDE.md Essential Commands + `package.json` scripts / `pyproject.toml` / `Cargo.toml` to extract test command, naming convention, and 1-2 exemplar test files closest to changed code.
3. **Spawn `adversarial-tester-agent`** to AUTHOR RED tests — see Spawn Template (A5). The agent writes failing tests against today's code; no fix is authored.
4. **Independently verify RED.** Read the agent's report at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`, extract authored test file paths from frontmatter `authored_tests[]` (preferred) or fall back to body `**Test file:**` lines for legacy m7-v1 handoffs. Run the project test command **once per authored test** (single independent re-run — the agent already ran a 3× flake check per its Step 5). Tests that do not fail deterministically are deleted from disk AND removed from the body report AND pruned from the frontmatter `authored_tests[]` array — re-emit the handoff file via `atomic_state_write` so the consumer (/geniro:implement's Phase 1 handoff-resolution step) sees the kept set only. **Re-emit contract:** the only delta is the pruned `authored_tests[]` entries plus the corresponding `**Test file:**` body lines. Preserve every other frontmatter key (`tier`, `producer`, `consumer`, `schema-version`, `branch`, `timestamp`, `worktree`, `geniro_kind`, `geniro_schema_version`, `mode`, `phase`, `status`, `approvals`, `non-resumable-actions`, `open_questions`) and every other body section (Adversarial Findings summary, hypothesis details, Discarded / Inconclusive, etc.) byte-for-byte from the agent's original write — this is a surgical patch, not a rewrite. Mirror `/geniro:implement`'s producer-preserving resolution-write pattern (preserve `id`, `source`, `question`, `related_findings` when writing a resolution). This is the orchestrator-side RED-verification per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § RED phase Step 3.
5. **Present Adversarial Findings** (A6 template).
6. **Escalate fix authoring** — reuse escalation AUQ (Trivial / Non-trivial / Cannot-verify / Leave-it-to-me) with findings file path referencing `from-debug-adversarial-<branch>.md` instead of `from-debug-<branch>.md`. The authored test file paths inside are the escalation targets. The receiving skill writes the fix and runs GREEN verification (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § GREEN phase). If zero red tests survived re-verification, SKIP entirely — report `"no bugs found in scanned diff"` and go directly to Cleanup; terminal state `adversarial-aborted` with `## Termination reason: no-bugs-found-in-diff`.

state.md `## Authored Tests` body section tracks each authored test per the column set in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2.

### A5. Spawn template

Literal `Agent(subagent_type="adversarial-tester-agent", ...)` template — pre-inlined diff, framework detection, F→P invariant, authored-test hard cap, scope anchor — in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §6 (A5 spawn template).

### A6. Findings template

Markdown template for the post-re-verification findings block (Diff scope / Hypotheses generated / Tests authored / Tests discarded / CRITICAL-HIGH / MEDIUM / Discarded-Inconclusive / Zero-red-tests outcome) in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §6 (A6 findings template).

If zero red tests survive, skip escalation entirely and go directly to Cleanup. Otherwise proceed to escalation per A4 step 6.

---

## Stall Diagnosis Taxonomy

When the §1.7 stall gate fires, classify the stall as a missing component (8-category taxonomy A-H: missing instruction / source-of-truth / tool / validator / permission rule / sandbox signal / eval / recovery path). Full table + AUQ rendering + persistence rules in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §5.

---

## State file schema

T1.5 state.md frontmatter (categories `disambiguate_mode`, `multi_path_fix` for `approvals[]`) + body sections (Scientific Mode + Adversarial Mode); T2 handoff schemas for `from-debug-<branch>.md` and `from-debug-adversarial-<branch>.md` including the `open_questions[]` contract — full schemas in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2.

---

## ACI per-phase tool surface

**Phase 0 (Mode Detect):**
- Allowed: Read / Bash (read-only — `git branch --show-current`, `git rev-parse`).
- Explicitly blocked: any Edit/Write, any side-effect tool.

**Phase 1 (Investigate):**
- Allowed: Read / Grep / Glob / Bash (read-only — `git status`, `git log`, `git diff`, `git blame`, `git bisect`, test re-runs without code edits, log inspection, profiler invocations, third-party CLI like `psql -c` against test DB if configured).
- Allowed: Edit / Write for EXPERIMENTS only — debug scripts, logging statements, scratch test files, `.geniro/state/debug/<slug>/` artifacts.
- Explicitly blocked: production-source Edit/Write, `git push`, `gh pr create`, branch switching without user confirmation.

**Phase 2 (Propose):**
- Allowed: Read / Grep / Glob / Bash (read-only + experimental test runs).
- Allowed: Edit / Write for reproduction test authoring + experimental monkey-patches.
- Explicitly blocked: production-source Edit/Write outside the reproduction test file, `git commit`, `git push`, `gh pr create`.

**Phase 3 (Ship):**
- Allowed: Read / Write (T2 handoff persistence via `atomic_state_write`), `emit-learning` helper invocation, `AskUserQuestion`.
- Explicitly blocked: `git commit`, `git push`, `gh pr create`, Agent spawns. Debug NEVER ships code.

**Adversarial Mode (A4 spawn):**
- `adversarial-tester-agent` runs under the spawn-agent ladder.
- Agent's tool surface inherited via the agent's frontmatter (owned by `agents/adversarial-tester-agent.md`).
- Orchestrator's re-verification step uses read-only Bash (run test command).

**Existing safety layer** applies across ALL phases: file-protection hook, git-guardrail hook, `.geniro/` deletion guard (CLAUDE.md § Safety Hooks). Runtime denies stay enforced regardless of ACI doc.

---

## Memory I/O Schedule

| Phase | Helper | Direction | MODE |
|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` |
| Phase 1 entry | `query-learnings` | read L2 | n/a |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a |
| Phase 1 entry (conditional) | spec.md frontmatter `workflow_refs[]` | read external | fires only when `$ARGUMENTS` points to spec.md or task-dir; cached tracker `status` primes hypotheses |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` (single re-fire) |
| Phase 1 (per rejection) | `emit-learning` | write L2 | n/a (type `discarded_hypothesis`; fires per rejected hypothesis; required `ext.{hypothesis, evidence_against, tested_by}`) |
| Phase 2 exit (conditional) | `emit-learning` | write L2 | n/a (type `retry_failure_sequence`; fires when `fix_attempts >= 2`; required `ext.{phase, attempts, resolution}`) |
| Phase 3 exit | `emit-learning` | write L2 | n/a (type `diagnosis`; required `ext.{symptom, root_cause, fix}`) |

`update-semantic` is NOT called. Debug investigates existing code; it does not add modules, move files, or rename — those are /geniro:implement and /geniro:refactor concerns.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "It's probably a cache issue" — guess and code | Guesses waste time. Form a hypothesis, then test it with evidence per Evidence Standard. |
| "The fix is one line, I'll just write it and escalate nothing" | /geniro:debug never applies code. Even one-line fixes go through `/geniro:implement` — the review gate still applies and the reproduction test ships with the fix as the regression guard. |
| "I added experimental logging and while I'm here I'll patch the bug too" | Experiments and fixes are separate deliverables. Phase 2 mandates: revert experimental edits to non-test source; escalate the proposed patch as text. /geniro:implement applies the real fix cleanly. |
| "Changes look fine, I'll skip adversarial mode" | "Looks fine" is the attacker's favorite surface. If user asked for verify-changes, run the adversarial pass — a zero-red-tests outcome is still a valid deliverable. |
| "I'll reason about edges instead of authoring tests" | Reasoning is reviewer-mindset. Adversarial mode AUTHORS executable failing tests because reasoning misses what running code catches. |
| "The agent reported F→P, I'll trust it" | Orchestrator MUST independently re-run authored tests (A4 step 4). Self-reported F→P is evidence, not proof. Same rule applies to scientific-mode hypothesis confirmation — re-run the test / re-read the file:line / re-execute the query yourself before advancing to Isolate. |
| "The findings are in state.md, I'll just ask the escalation question" | state.md is a scratchpad, not a user-facing report. §3.1 requires an explicit findings summary in chat AND persisted to `from-debug-<branch>.md` before the escalation AUQ. The state file IS the handoff channel — inlining the summary into the escalation command lets copies drift. |
| "The hypothesis matches the symptom — that's confirmation" | Symptom-matching is correlation, not causation. Confirmation requires a captured artifact per Evidence Standard kind 1-5 (file:line snippet, captured command output, log line, query result, user-provided artifact). |
| "I have no DB / log / production access — mark this hypothesis inconclusive" | Inconclusive-by-default is a fabrication shortcut. Run the §1.5 missing-data gate first — `AskUserQuestion` asking the user to supply the specific artifact. Only mark inconclusive if user confirms they cannot supply it. |
| "I have a script / curl / query that reproduces the bug, that's enough" | Scripts get deleted at §3.5 Cleanup and leave no regression guard. §2.4 mandates the reproduction be authored as a unit/integration test in the project's framework. Escape hatch (Reproduction Decision) is opt-in for genuinely non-reproducible cases only. |
| "Per protocol I should ask via AskUserQuestion, but this specific intermediate question isn't in the enumerated gates — I'll inline (A)/(B) in chat" | The Universal Rule above makes the tool mandatory for ANY choice question — the enumerated gates are examples, not the complete set. An inline `(A)/(B)` leaves no structured answer for the resume hook to restore. If you catch yourself rationalizing "but this case is different / needs runtime confirmation / is just a quick check" — stop and call the tool. |
| "I'll name the reproduction test after the confirmed hypothesis number from `## Hypotheses`" | state.md gets deleted at Cleanup; the test ships with the fix. A name like `Bug C` or `Hypothesis 2 reproduction` is meaningless to whoever reads the test in CI weeks later. §2.4 mandates: describe the bug behavior, not the thread-local label. |
| "I see two valid fixes for this root cause — I'll just pick one and write the text proposal" | §2.2 multi-path fix gate (Always-WAIT) requires AskUserQuestion whenever the root cause has more than one valid fix path with real trade-offs. Single-text-proposal default applies ONLY when there is one obvious right fix. |
| "Bypass `git guardrail` hooks if a needed `git bisect` step blocks." | Hooks fail for a reason. `git bisect` is permitted (read-only investigation per § ACI per-phase). If a specific guardrail blocks legitimate debug work, the path is `.geniro/safety.json` allow_patterns, not `--no-verify`. |
| "Self-fix indefinitely until verify passes." | §2.5 fix-loop escalation bounds to 2 fix attempts. Past 2, escalate AUQ ("Try different approach" / "Accept as documented limitation" / "Abort"). "Kick it until it passes" is an anti-pattern that wastes budget on a hypothesis that needs revisiting. |

---

## Infrastructure Investigation

When symptoms suggest the bug may not be in the code (timeouts, intermittent failures, environment-only manifestation, post-deployment regressions), form at least one infrastructure hypothesis alongside code hypotheses. Signal list + investigation checklist + hypothesis quality bar in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §3.

---

## Isolation Techniques

Binary search / git bisect / profiling — full procedure + per-language profiler list in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §4. Pick the cheapest technique: binary search for large regions, git bisect for known-good→bad regression boundaries, profiling for quantitative symptoms.

---

## Definition of Done

For each debug session, confirm the checklist for the mode that ran.

### Scientific Mode

- [ ] Bug reproduced consistently with clear steps
- [ ] feedback loop built: command + expected output + captured artifact recorded in state.md `## Feedback Loop`; re-run cost ≤30s preferred; 3-run determinism check passed
- [ ] Custom instructions, project snapshot, and past learnings loaded at the start of investigation
- [ ] All hypotheses recorded in state.md `## Hypotheses`
- [ ] Each hypothesis has a test plan and result citing artifact per Evidence Standard
- [ ] Root cause identified and confirmed (not guessed), tagged `[ROOT-CAUSE]`
- [ ] Proposed fix is minimal, targeted, written as a text patch (NOT applied to source)
- [ ] When multiple valid fix paths exist, multi-path fix gate fired (Always-WAIT) — user chose the path
- [ ] Proposed fix verified against root cause via reverted experiments / monkey-patch
- [ ] Reproduction test authored at project's normal test path, F→P verified, survives Cleanup — OR escape hatch invoked with user-recorded alternative regression guard in state.md "Reproduction Decision"
- [ ] Findings summary presented to user in chat AND persisted to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` via `atomic_state_write` before the escalation question
- [ ] Escalation decision made via AskUserQuestion with options referencing the state file by path
- [ ] All experimental edits to non-test source reverted before handoff
- [ ] L2 emit fired with `diagnosis` type + `ext.{symptom, root_cause, fix}`; rule-capture offer fired when `recurrence_count >= 3` (after dedupe check), decline logged via `emit-rejection.sh`
- [ ] Cleanup completed

### Adversarial Mode

- [ ] Diff scope resolved (range + file list recorded in state.md `## Diff Scope`)
- [ ] Skip conditions checked (and explicitly reported if skipped)
- [ ] Project test framework detected from CLAUDE.md / package.json / pyproject.toml
- [ ] `adversarial-tester-agent` spawned with all 6 context-isolation slots pre-inlined
- [ ] Report written to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`
- [ ] Authored tests independently re-run by orchestrator (1× per test)
- [ ] F→P-confirmed tests retained; any passing-today tests deleted
- [ ] Adversarial Findings summary (A6) presented to user in chat
- [ ] Escalation decision made via AskUserQuestion (or no-bugs-found exit if zero red tests → terminal `adversarial-aborted`)
- [ ] Authored test files left on disk (NOT reverted — unlike scientific-method experiments)
- [ ] Cleanup completed (`from-debug-adversarial-<branch>.md` may remain as audit trail)

---

## Examples

### Example 1: Cache Not Invalidating
```
/geniro:debug User sees stale data after profile update
```
→ Phase 1 Observe: User updates name, refresh page shows old name
→ Hypothesis 1: Cache invalidation broken; Hypothesis 2: Update endpoint not called
→ Test: Add logging to cache invalidation and endpoint
→ Result: Hypothesis 1 confirmed (cache key mismatch) → `[ROOT-CAUSE]`
→ Phase 2 Propose: patch cacheKey builder in `src/cache/user.ts` to include user ID
→ Verify: local experiment shows bug disappears with monkey-patch
→ Phase 3 Findings persisted to `from-debug-<branch>.md`
→ Escalate: /geniro:implement with the proposed patch
→ L2 emit `diagnosis` with tags=[cache, invalidation, user-role]

Additional worked examples (Intermittent Timeout, Verify Recent Changes) live in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §7.
