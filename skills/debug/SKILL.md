---
name: geniro:debug
description: "Use when a bug needs systematic investigation. 3-phase loop (Investigate → Propose → Ship) mirroring /implement: observe → hypothesize → test → isolate → propose fix → author reproduction test, then escalate to /geniro:implement with a T2 hand-off at .geniro/state/handoff/from-debug-<branch>.md. Adversarial mode authors F→P tests against a diff (verify-changes). Skip for bugs with obvious root cause — go straight to /geniro:implement."
context: main
model: opus
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, WebSearch]
argument-hint: "[bug description | verify <diff-range> | verify last changes]"
---

# Debug: Scientific-Method Investigation

Use this skill to systematically debug complex issues. Replaces guessing with evidence gathering and hypothesis testing. 3 phases mirroring `/geniro:implement`.

**Architecture spec:** *(internal)*. Detailed contracts:
- Infrastructure-cause guidance — see § Infrastructure Investigation below
- Isolation techniques (binary search / git bisect / profiling) — see § Isolation Techniques below
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Investigation-driven fix gate (debug-flavored) — multi-path fix gate and repro-infeasible escape hatch
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` — consumer protocol for downstream skills reading our T2 hand-offs

**Section-reference convention:** references in this SKILL.md point to local sub-sections (Phase 1, Phase 2, Phase 3 respectively — header lines `### 1.1`, `### 2.4`, etc. below).

---

## Your Role — Investigate, Don't Ship

You investigate. You isolate. You propose. You do NOT apply the fix. Phase 3 hand-off is a text proposal + reproduction test on disk + a T2 hand-off file at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`. Downstream consumers (`/geniro:implement`, manual user action) apply the patch.

---

## State Machine

state.md `phase:` enum transitions:

```
[entry] → mode-detect ──┬── investigate ──┬── propose ──┬── ship ── done
│ │ │
│ │ └── ship-summary-only (terminal — "Leave it to me")
│ │
│ └── phase-2-escalated ──┬── debug-handoff (terminal — fix-fail)
│ ├── propose (try-different-approach loop-back)
│ └── aborted (terminal)
│
└── phase-1-escalated ──┬── investigate (supply-data loop-back)
├── ship-summary-only (abandon — partial findings)
└── aborted (terminal)

[entry] → adversarial-mode-detect ── adversarial-investigate ── adversarial-ship ──┬── done
└── adversarial-aborted (terminal — zero red tests)
```

**Terminal states:** `done`, `ship-summary-only`, `debug-handoff`, `aborted`, `adversarial-aborted`. the SessionStart recovery treats all five as «task complete — no resume needed».

**Non-terminal states:** `mode-detect`, `investigate`, `propose`, `ship`, `adversarial-mode-detect`, `adversarial-investigate`, `adversarial-ship`. the recovery rolls these back to phase-entry and re-runs (idempotent — `approvals[]` ensures gates skip already-answered).

**Escalation states:** `phase-1-escalated`, `phase-2-escalated`. the surfaces to user as "task was paused — last AUQ options:" so user re-picks without losing context.

**Termination-case mapping** per — see architecture spec for the full 8-row table. The `## Termination reason` body section is written on `aborted` / `adversarial-aborted` terminals.

---

## Loop Invariants

The 7 invariants apply unchanged:

1. **One result per tool call.** Adversarial Mode parallel-spawn → each spawn must return a structured result; dead spawn → `status: failed` entry in `## Tool log`.
2. **Args validated before execution.** `$ARGUMENTS` semantic parse; PR ref validation via `mcp__github__pull_request_read` or GraphQL fallback.
3. **Permission before side-effect.** State.md writes via `atomic_state_write`. /debug performs NO `git push` / `gh pr create` — debug never ships code.
4. **Bounded and structured tool results.** `adversarial-tester-agent` output ≤4K chars per finding block; truncation marker. Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.
5. **Escalation gates, not silent abort.** stall gate (5 inconclusive) + fix-fail gate (2 attempts) escalate to user via AUQ. Never silently fabricate a conclusion.
6. **Final answer grounded in observations.** Evidence Standard for hypothesis confirmation — every Result: field in `## Hypotheses` MUST cite an artifact kind 1-5 per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. "Symptom matches" is correlation, not causation; not allowed.
7. **Errors → structured observations.** Failed `git diff`, denied permission, `adversarial-tester-agent` "agent not found" ladder fallback all become structured `## Tool log` entries before being acted on.

`## Tool log` schema: typical run produces 0-3 entries (subagent-spawn outcomes for adversarial mode, escalation entries for /). Routine Read / Edit / Bash skipped.

---

## Budgets — Quality-First

This skill has **NO hard kill caps**. Same model as other skills.

**Quality gates (escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Inconclusive hypothesis tests | 5 across all hypotheses | stall gate | AUQ — diagnose-by-missing-component (8 options) → user supplies missing or picks alternative |
| Fix attempts failed verification | 2 | fix-loop gate | AUQ — try different approach / accept as documented limitation / abort. User picks. |
| Adversarial mode authored tests | 10 hard cap | (delegated to agent contract) | Stop authoring; surface findings |
| Adversarial mode consecutive discards | 5 | (delegated to agent contract) | Stop hypothesis generation; surface partial |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| Subagent spawns | 1 (adversarial mode only — `adversarial-tester-agent`) | |
| Reproduction-test framework | Project's native (detected from CLAUDE.md Essential Commands) | |

**Explicitly NOT capped:** wall-time, total tool calls, total model turns, total cost. Same rationale as — complex multi-cause bugs may legitimately need hours of investigation; hypothesis testing against a large codebase may need many Read/Grep calls.

---

## Subagent Model Tiering

Follow the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly. For plugin-defined subagents (adversarial-tester), also follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — registration ladder (`geniro-claude-plugin:<agent>` → bare `<agent>` → `general-purpose` with agent body inlined). Cache the resolved rung for the rest of the session.

Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site — every Agent prompt MUST satisfy the six pre-inlined fields.

| Spawn | Tier | Why |
|---|---|---|
| `adversarial-tester-agent` | `inherit` | Reasoning-grade test authoring. Matches the canonical rule in `model-tiering.md` and call sites in `/geniro:review` Phase 4c, `/geniro:implement` Phase 3. The agent's F→P verification + 3× flake check enforce correctness regardless of inherited tier. |

---

## Evidence Standard

Cite the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` — schema, forbidden phrases, and artifact kinds 1-5 are defined there. This skill applies that standard at every hypothesis-confirmation, fix-verification, and reproduction-test capture.

**Debug-specific framing — hypothesis-confirmation artifact kinds.** A hypothesis is **confirmed** ONLY when its `Result:` field cites one of the artifact kinds 1-5 from the shared rule. Hypothesis-tracking is the most evidence-rigorous flow in the plugin: every entry in state.md § `## Hypotheses` Result MUST attach a captured artifact (kind 1: file:line + verified snippet; kind 2: captured command/test/build output; kind 3: log line / stack trace; kind 4: datastore query result; kind 5: user-provided artifact). Reasoning is correlation; only reproduction with a captured artifact confirms causation.

If the orchestrator's tools cannot produce evidence for a hypothesis (no DB access, no production logs, no credentials, no environment access), do NOT mark it inconclusive by default — use the missing-data gate in to ask the user for the artifact.

---

## Universal Rule: All Choice Questions Use AskUserQuestion

Every user-facing choice in this skill — including ad-hoc gates NOT explicitly enumerated below — MUST go through the `AskUserQuestion` tool per the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Universal AskUserQuestion Rule. The enumerated gates are examples, not an exhaustive list. If you're about to type `(A)... or (B)...` in chat, stop and call the tool instead.

---

## Phase 0 — Mode Detection ($ARGUMENTS routing)

state.md `phase: mode-detect`. **Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: debug`, `LOAD_TIER: pipeline`, `MODE: initial-load`. Echo per the helper's contract.

$ARGUMENTS routing:

| $ARGUMENTS shape | Mode | Transition |
|---|---|---|
| empty | AUQ with header "Mode" — 4 options: «Describe the symptoms» / «Paste error message» / «Point to a failing test» / «Verify last changes (adversarial)». First 3 → Scientific. Fourth → Adversarial. | `mode-detect` → `investigate` OR `adversarial-mode-detect` |
| matches anchored verify-keyword signals (table below) | Adversarial Mode | `adversarial-mode-detect` |
| otherwise | Scientific Mode | `mode-detect` → `investigate` |

**Anchored verify-keyword signals** (bare keywords alone NOT enough — phrases like "verify that login returns 500" or "stress-test revealed a memory leak" are scientific-method bug reports, not verify requests):

- Anchored keyword signals: `verify <changes|diff|last|recent|my|this|PR>`, `break <my|the> diff`, `hunt for bugs in <diff|change|PR>`, `find edge cases in <diff|change|PR>`, `adversarial <mode|pass|scan|run>`, `stress-test <the diff|my change|last changes>`
- Phrase signals: `verify last changes`, `verify recent changes`, `verify my changes`, `check last changes`, `break my diff`
- Explicit diff range signals: `HEAD~N..HEAD`, `HEAD~N`, `main...HEAD`, bare PR ref (`#1234` or GitHub PR URL), bare branch name + verify keyword

**Approvals-persistence protocol:** before firing the empty-AUQ, check state.md frontmatter `approvals[]` for prior entry with `category: disambiguate_mode`. If found, use prior `picked` value. If not, fire AUQ → on user pick, append to `approvals[]` via `atomic_state_write` before proceeding. Block 5d renders this on resume.

When in doubt (ambiguous input), default to Scientific Mode — user can re-invoke with explicit adversarial phrasing if needed.

---

## Phase 1 — Investigate

state.md `phase: investigate`. Mirrors Phase 1 (entry-gate + context load) plus Phase 2-style inner loop (hypothesis test iterations). Exits to Phase 2 only when a hypothesis is confirmed AND its Result: field cites an artifact per Evidence Standard.

### 1.1 Memory layer load (L2 prior-knowledge query)

On Phase 1 entry, in order:

1. **L4 refresh** — `load-custom-instructions(MODE: refresh, scope: debug + global + code-style + user-preferences — pipeline tier, 4 files)` per Echo contract.
2. **L3 refresh** — `load-semantic(MODE: refresh, top-2 default)`. Fingerprint drift check fires if applicable.
3. **L2 prior-knowledge query** — `query-learnings(tags=<inferred from $ARGUMENTS>, scope=task path)` per «debug session start» trigger. Top-K=5 default, filter superseded + deprecated. Skipped if $ARGUMENTS too generic to infer tags. Result count IS the recurrence signal used by L4-promotion suggestion.

**surfacing convention:** when results include `discarded_hypothesis` entries, display them with a distinct label so the orchestrator can skip dead-ends faster:
```
Past investigations in this scope ruled out:
- <ext.hypothesis> (tested <ts> by <ext.tested_by>)
Past diagnoses:
- <summary> (fixed <ts>)
```
These get surfaced on hypothesis formation so that the orchestrator does NOT re-form a hypothesis equivalent to an already-ruled-out one without explicit re-justification.
4. **Cross-layer conflict resolution** — `resolve-conflicts(L2/L3/L4 loaded)` per
Echo lines per mandatory.

### 1.2 Observe & repro

- Reproduce the bug consistently. Capture error messages, logs, stack traces.
- Identify what changed (recent commit, config, user action). Record exact repro steps.
- **If repro is unclear/missing:** `AskUserQuestion` with header "Repro details" — 2-4 concrete options (environment / steps to trigger / expected vs actual behavior). Do NOT guess.

Persist to state.md body sections `## Symptom` and `## Reproduction Steps` (B).

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

Persist to state.md `## Feedback Loop` body section: Command / Expected output / Actual output / Re-run cost / Determinism (perB).

> **NOT the reproduction test.** authors a unit/integration test in the project framework that ships with the fix as the regression guard. builds a fast-iteration scratch signal so-can move quickly. The test STAYS on disk; the scratch signal is reverted at Cleanup.

### 1.4 Hypothesize

Based on Observation + Feedback Loop output, form **2-3 competing hypotheses**. Each must be testable AGAINST THE FEEDBACK LOOP —'s tests will toggle one variable, re-run the loop, observe whether the captured signature changes.

**Consider infrastructure causes alongside code causes** per § Infrastructure Investigation below. If symptoms include timeouts, intermittent failures, or environment-only manifestation, form at least one infrastructure hypothesis.

Persist to state.md `## Hypotheses` body section, one block per hypothesis (Hypothesis / Evidence For / Evidence Against / Status: pending → testing → confirmed | rejected | inconclusive / Test Plan / Result perB schema).

> **Inconclusive** means the test could not distinguish whether the hypothesis is true or false. Common causes: (1) test environment differs from production, (2) bug is intermittent and didn't manifest, (3) test was too coarse, (4) multiple interacting causes mask effects. Inconclusive is NOT a rejection — you need a better test or more data.

### 1.5 Test each hypothesis + missing-data gate

- Design a minimal test per hypothesis. The test must produce a captured artifact per Evidence Standard kind 2-5.
- Add logging, breakpoints, or unit tests to gather evidence.
- Do NOT implement a fix yet — you're gathering data.
- **Missing-data gate:** if testing requires data the orchestrator's tools cannot reach (production logs, runtime state, third-party API responses, DB rows behind credentials, screenshots), do NOT mark the hypothesis inconclusive by default. `AskUserQuestion` with header "Missing data" — 2-4 concrete options for the specific artifact needed:
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

**Sliding-window cap (Reflexion bound):** keep at most 5 latest `discarded_hypothesis` entries per `(producer, scope)`. Before emit, count existing non-deprecated entries via `query-learnings --type discarded_hypothesis --scope <scope> --include-superseded`; if ≥5, mark the oldest matching entry `deprecated: true` via direct edit to `learnings.jsonl` BEFORE appending the new one. Prevents discarded-hypothesis chatter from drowning out `diagnosis` entries at retrieval time.

`rejected` is a normal outcome of hypothesis testing — emit fires in the happy path. `inconclusive` does NOT emit (the data is ambiguous; recording it would seed noise). `confirmed` does NOT emit a `discarded_hypothesis` (it emits a `diagnosis` later at).

state.md `phase: investigate` throughout. `## Hypotheses` body section grows iteratively.

### 1.6 Isolate root cause → [ROOT-CAUSE] finding

Once a hypothesis is confirmed:
- Identify exact code location. Trace data/control flow. Apply techniques per § Isolation Techniques below (binary search / git bisect / profiling).
- Understand why the bug happens (not just where).
- **Tag emitted findings per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.** `/geniro:debug` is the root-cause flow by definition — a confirmed hypothesis isolates to a `[ROOT-CAUSE]` finding, NOT `[SYMPTOM]`. `[UNKNOWN]` from debug is a failure mode — if you find yourself emitting `[UNKNOWN]`, the hypothesis loop didn't close (escalate via stall gate). `[SYMPTOM]` from debug is also a failure mode — re-enter with a new hypothesis.

Persist to state.md `## Root Cause` body section.

### 1.7 Stall escalation gate

When the hypothesis loop fails to converge — defined as **5 inconclusive hypothesis tests across all hypotheses** — fire the stall gate before declaring the bug unsolvable:

1. **Do not silently report "cannot determine cause".**
2. Apply the 8-component diagnose-by-missing-component taxonomy (`## Stall Diagnosis Taxonomy` below).
3. **Surface to user via `AskUserQuestion`** with header "Stall diagnosis" — render 4 of the 8 categories (AUQ maxItems=4; pick the most likely 4 based on stall context).
4. state.md marks `phase: phase-1-escalated` with timestamp + inconclusive-test count + categorized stall hypothesis. Transitions:
- User picks (A-G — a concrete missing artifact / category) → `phase: investigate` (resume hypothesis loop with new data).
- User picks (H — "abandon — present partial findings") → `phase: ship-summary-only` (proceed to Phase 3 with a stall-flagged findings summary).
- User can also pick "abort" → `phase: aborted` (terminal).

state.md `## Open Questions` body section logs the stall question + categorized hypothesis. Block 5c renders on resume.

---

## Phase 2 — Propose

state.md `phase: propose`. Output authoring: text fix proposal + F→P reproduction test. **No production-source edits applied.** Exits to Phase 3 when fix proposal AND reproduction test are both verified.

### 2.1 L4 refresh entry (single — no double-refresh)

On Phase 2 entry, single `load-custom-instructions(MODE: refresh, scope: debug + global + code-style + user-preferences — pipeline tier, 4 files)` call. Mirrors Phase 3 entry contract: always re-fires, drops the conditional-on-marker pattern. Cost: 1 helper read.

### 2.2 Multi-path fix gate (Always-WAIT, )

If the confirmed root cause has more than one valid fix path with real trade-offs (e.g., snapshot-vs-live-fetch, COALESCE vs CHECK constraint vs catch+log, fix-at-source vs fix-at-call-site), do NOT pick one and write a single text proposal.

**Fire `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Investigation-driven fix gate (debug-flavored)**:
- `header: "Fix path"`
- `question` text: confirmed root cause's `path:lines` + hypothesis title
- Each option:
- `label` (1-5 words) — name of the path
- `description` — one-line trade-off
- `preview` — investigation context (Root cause / Evidence from `## Hypotheses` Result / Hypothesis-confirmed status + number per the helper's source-field map)

**Approvals-persistence:** before firing, check state.md frontmatter `approvals[]` for prior entry with `category: multi_path_fix` and matching `root_cause` (use root-cause text as the disambiguator). If found, use prior `picked` value. If not, fire AUQ → on user pick, append entry to `approvals[]` via `atomic_state_write`.

**Re-ask trigger:** if the root cause changes (second-pass investigation overturns the prior root cause), the prior `approvals[]` entry is stale — clear it and re-fire. Block 5d renders this from `approvals[]` on resume.

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

**Escape hatch — non-deterministic bugs only.** If the bug is genuinely non-reproducible at the test layer (race conditions only seen under load, environment-only failures, UI flake), `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Investigation-driven fix gate:
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
3. state.md marks `phase: phase-2-escalated` with timestamp + fix-attempt count + accumulated test outputs. Block 5c renders open question on resume.

**L2 emit on fix-loop exit.** When Phase 2 exits AND `fix_attempts ≥ 2`, call `emit-learning` with type=`retry_failure_sequence`, trust=`verified`, required `ext.{phase: "fix-attempts", attempts: [{round: N, failure: "<why this attempt did not verify>"}], resolution}`. `resolution` ∈ `{passed, escalated, aborted}` (passed = test confirmed fix; escalated = user picked "Try different approach" or "Accept as documented limitation"; aborted = terminal). Sliding-window cap = 3 latest per `(producer, scope, phase)`. Single-attempt exits (fix_attempts == 1) do NOT emit. Scope = the file/module the fix targeted.

---

## Phase 3 — Ship

state.md `phase: ship`. Findings hand-off to downstream skill OR user-handles. **No `git push` / `gh pr create`** — debug never ships code, only proposals + tests authored locally.

### 3.1 Present findings (chat + persist T2 handoff)

Before asking where to route the fix, present a human-readable findings summary to the user. Do NOT jump straight to the escalation AUQ — the user chooses the escalation target based on this summary.

Output the markdown block directly in chat AND write the same content (with full frontmatter wrapping it) to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` via `atomic_state_write`. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so the handoff survives worktree teardown.

**Findings template body:**

```markdown
## Debug Findings

**Source branch:** [from `git branch --show-current`]

**Source worktree:** [from `git rev-parse --show-toplevel`]

**Why escalating to <target>:** [one sentence — which target and concrete reason scope fits it; user makes final routing choice in]

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

The receiving skill pre-loads findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` — the state file is the handoff channel, not a chat paste. Do NOT re-derive, reword, or inline the summary into the escalation command; the file path IS the contract.

### 3.2 Escalation AUQ (4 options)

Only after the summary above is visible AND persisted, `AskUserQuestion` with header "Escalate" and these options:

- **Trivial — run `/geniro:implement`; pre-load findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`** — ≤2 files, obvious target, no architecture or auth/permissions change.
- **Non-trivial — run `/geniro:implement`; pre-load findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`** — touches multiple modules, changes interfaces, needs architecture review, or introduces a new pattern. (Both Trivial and Non-trivial route to the same target — `/geniro:implement`. The Trivial/Non-trivial designation surfaces in the spec context the receiving skill loads.)
- **Cannot verify — request specific data from user** — pick this when one or more hypotheses are unverified because the orchestrator's tools cannot reach the artifact. Trigger a follow-up `AskUserQuestion` with concrete options for the missing data. When data arrives, return to, do NOT escalate yet.
- **Leave it to me** — user will apply the patch manually using the state file as reference. state.md transitions to `phase: ship-summary-only` (terminal).

Do NOT auto-invoke the next skill — surface the suggestion only. State file IS the handoff channel. You do NOT apply the patch yourself.

### 3.3 L2 auto-emit + L4 promotion suggestion

At Phase 3 exit:

- **`emit-learning`** — called by /debug at two distinct points:
- **`diagnosis`** (primary emit type, fires at Phase 3 exit on confirmed root cause) — every confirmed root cause emits one entry with summary, tags (inferred from affected-files + hypothesis category), scope (project-relative path glob), and required `ext.{symptom, root_cause, fix}` per typed-extension table. Default trust `verified` per- **`discarded_hypothesis` (, fires at per-rejection during Phase 1)** — every rejected hypothesis emits one entry with required `ext.{hypothesis, evidence_against, tested_by}`. Sliding-window cap = 5 latest per `(producer, scope)`. See for the payload schema and emit logic.
- **NOT emitted :** `pitfall` (/refactor + /review own), `convention` (/implement self-review owns), `decision` (/plan owns), `discovery` (/refactor + /onboard + /investigate own).

- **L4 promotion suggestion:** when the prior-knowledge query returned **≥1 matching prior diagnosis** (recurrence signal), surface a one-line suggestion in the Phase 3 final report:

```
[learnings] Diagnosis recorded: "<one-line summary>". Recurrence detected (<n> prior matching entries). Recorded to L2.
→ Consider /geniro:instructions edit <scope>.md to promote as a debug-rule.
```

Scope hint follows the diagnosis category:
- Style/convention root causes → suggest `code-style.md`
- Workflow/process root causes → suggest `debug.md`
- Architecture/global root causes → suggest `global.md`
- Other → generic "appropriate scope"

Suggestion fires only when recurrence is detected — single-occurrence diagnoses not warrant L4 promotion (user remains source-of-truth for L4 curation). The line is informational (no AUQ, no auto-edit). Fully automatic L2→L4 promotion deferred to a future release.

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

- **Scientific-method mode only:** Remove `<PRIMARY_ROOT>/.geniro/state/debug/<slug>/state.md` for the current branch's slug only, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract — its useful content has already been saved (root cause, repro, hypotheses-tested-and-rejected, accepted limitations) via L2 emit + persisted handoff. Do NOT delete sibling slugs from concurrent debug sessions on other branches.
- **Clear old state files** (best-effort; any may not exist):
```bash
rm -f ".geniro/debug/HYPOTHESES.md" 2>/dev/null
rm -f ".geniro/debug/HYPOTHESES-${slug}.md" 2>/dev/null
rm -f ".geniro/state/debug/HYPOTHESES-${slug}.md" 2>/dev/null
rm -f ".geniro/state/debug/findings-state.md" 2>/dev/null
rm -f ".geniro/state/debug/adversarial-tests.md" 2>/dev/null
```
- **Scientific-method mode only:** Remove debug scripts, scratch reproductions, the feedback-loop scratch signal, and ad-hoc curl/query files created during investigation. The reproduction test (authored at project's normal test path) STAYS on disk — it ships with the fix as the regression guard.
- **Scientific-method mode only:** `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` MUST remain on disk as the escalation handoff channel — do NOT delete. Stays until next debug run overwrites it (single file per branch).
- Kill any background processes started during investigation (dev servers, watchers, profilers).
- **Adversarial mode:** `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` may remain as audit trail; authored test files stay on disk (unlike scientific-method experiments which get reverted).

Cleanup is best-effort — if a command fails silently, that's fine.

### 3.6 Atomic non-resumable updates

After each side-effect that cannot be replayed safely (none in baseline — debug performs no `git push` / `gh pr create`), append a structured entry to state.md frontmatter `non-resumable-actions[]` via `atomic_state_write`. Mirrors step 4.

The empty baseline is intentional: debug ships proposals, not commits. If a future user-customization introduces side-effects (e.g. a `.geniro/actions/post-finding-to-slack.md` invocation), THAT action becomes a non-resumable entry — not the standard ship flow.

---

## Adversarial Mode (verify-changes)

state.md `mode: adversarial`. Phases: `adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship`. Parallel to Scientific Mode; shared Phase 0 routes here on anchored verify-keyword signals (Phase 0 above).

### A1. Purpose

Attacker-mindset pass that AUTHORS executable F→P failing tests against a diff. Complements Scientific Mode: Scientific Mode REPORTS hypotheses about a known bug; Adversarial Mode hunts for unknown bugs in recent changes by writing tests that fail on today's code. Test authoring is delegated to `adversarial-tester-agent`; the orchestrator independently re-runs authored tests to confirm the failure before surfacing findings.

### A2. Diff resolution

**Delegates to /review Phase 1 multi-form parser.** See `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 1 — do NOT duplicate the parser here.

**Default when no explicit range:** scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` — anchor on the current cwd's worktree + currently-checked-out branch. Resolve the base branch per scope-anchor rule #3 (`git symbolic-ref --short refs/remotes/origin/HEAD`). Compute `git diff <base>...HEAD`. If on the base branch, fall back to `HEAD~1..HEAD`.

**Supported shapes:** bare keyword (`"verify last changes"`) → default; explicit range (`HEAD~3..HEAD`, `abc123..def456`); branch (`feat/foo...HEAD`); PR ref (strip leading `#`, resolve via `gh pr diff <number-or-url>` or `mcp__github__pull_request_read`).

### A3. Skip conditions

Mirror canonical skip-matrix at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. Adversarial mode is SKIPPED and the skill reports `"no adversarial pass — <reason>"` when:

- Empty diff (nothing to test).
- Diff contains zero production-code files (docs / config / lock / generated only).
- Diff >50 changed files OR >1000 changed LOC → suggest `/geniro:review` for oversized diffs (the agent's 10-test hard cap wastes budget on diffs this large).

### A4. RED-phase workflow

Runs the **RED phase** of the canonical cycle at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § RED phase: author the failing test FIRST, verify it fails with a real assertion signature, then escalate the fix to the receiving skill (which runs GREEN). Tests are never authored alongside or after the fix in this mode — RED-first ordering is non-negotiable.

1. **Resolve the diff** (A2). Pre-inline full diff + changed-file contents for the spawn prompt.
2. **Detect the project test framework.** Read CLAUDE.md Essential Commands + `package.json` scripts / `pyproject.toml` / `Cargo.toml` to extract test command, naming convention, and 1-2 exemplar test files closest to changed code.
3. **Spawn `adversarial-tester-agent`** to AUTHOR RED tests — see Spawn Template (A5). The agent writes failing tests against today's code; no fix is authored.
4. **Independently verify RED.** Read the agent's report at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`, extract authored test file paths, run the project test command **once per authored test** (single independent re-run — the agent already ran a 3× flake check per its Step 5). Tests that do not fail deterministically are deleted from disk AND removed from the report. This is the orchestrator-side RED-verification per `tdd-cycle.md` § RED phase Step 3.
5. **Present Adversarial Findings** (A6 template).
6. **Escalate fix authoring** — reuse escalation AUQ (Trivial / Non-trivial / Cannot-verify / Leave-it-to-me) with findings file path referencing `from-debug-adversarial-<branch>.md` instead of `from-debug-<branch>.md`. The authored test file paths inside are the escalation targets. The receiving skill writes the fix and runs GREEN verification (`tdd-cycle.md` § GREEN phase). If zero red tests survived re-verification, SKIP entirely — report `"no bugs found in scanned diff"` and go directly to Cleanup; terminal state `adversarial-aborted` with `## Termination reason: no-bugs-found-in-diff`.

state.md `## Authored Tests` body section tracks each authored test path + status (kept / discarded).

### A5. Spawn template

```
Agent(subagent_type="adversarial-tester-agent", model=<inherit>, prompt="""
## Task: Adversarial Edge-Case Test Authoring (Debug — Verify Changes)

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

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
Write your report to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` (resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A). Authored test files go to the project's normal test paths. Do NOT git add/commit/push.

### F→P Invariant (NON-NEGOTIABLE)
Every test you keep MUST fail 3 times in a row on the current code. If it passes today, delete the test and mark `discarded-cannot-repro`. Flaky = discard.

### Scope
Diff-only — the orchestrator resolved the scope above. Do NOT author tests for files outside the changed-files list. Hard cap: 10 authored tests.

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""", description="Adversarial tests: /geniro:debug verify-changes")
```

### A6. Findings template

After re-verification, present this block directly in chat and persist (via the agent's write at A4 step 3 + the orchestrator's re-verify delta if tests were discarded):

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

If zero red tests survive, skip escalation entirely and go directly to Cleanup. Otherwise proceed to escalation per A4 step 6.

---

## Stall Diagnosis Taxonomy

When /debug stalls (5 inconclusive hypothesis tests, stall gate), classify the root-cause-of-the-stall as a missing component:

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

**AUQ rendering:** stall gate fires `AskUserQuestion` with header "Stall diagnosis". Render 4 of the 8 categories at a time (AUQ maxItems=4) — model picks the most likely 4 based on stall context (inconclusive-test outputs, hypothesis types tried). User picks one or "Other". Each option's `preview` (where helpful) shows what Phase 1 will do next.

state.md `## Open Questions` logs the stall AUQ + user's pick + delivered artifact (if applicable). Block 5c renders on resume.

---

## State file schema

### state.md (T1 — session-bound, `.geniro/state/debug/<slug>/state.md`)

Frontmatter:

```yaml
---
tier: T1
producer: debug
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: <enum per State Machine above>
status: <in-progress|done|failed>
non-resumable-actions: []
approvals: [] # — categories: disambiguate_mode, multi_path_fix
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
- `## Errors` — Block 5b
- `## Open Questions` — Block 5c (stall AUQ + outcome)
- `## Termination reason` — (only on terminal aborted-state)
- `## Persisted approvals` — Block 5d (render of frontmatter approvals[])

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
geniro_schema_version: m7-v1
mode: scientific
phase: ship
status: done
approvals: []
non-resumable-actions: []
---
```

Body: full content of findings template + body sections (`## Tool log` / `## Errors` / `## Open Questions` / `## Persisted approvals`).

### from-debug-adversarial-<branch>.md (T2 — handoff, Adversarial Mode)

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`. Same schema as from-debug-<branch>.md with `mode: adversarial` and `phase: adversarial-ship` discriminators. Body: A6 Adversarial Findings template + body sections.

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
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` (single re-fire) |
| Phase 3 exit | `emit-learning` | write L2 | n/a (sole emit type: `diagnosis`; required `ext.{symptom, root_cause, fix}` ) |

`update-semantic` is NOT called. Debug investigates existing code; it does not add modules, move files, or rename — those are /implement and /refactor concerns.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "It's probably a cache issue" — guess and code | Guesses waste time. Form a hypothesis, then test it with evidence. |
| "I know what this is, let me just fix it" | Intuition-based fixes mask the real cause. Gather evidence first. |
| "It looks right, no need to test" | "Looks right" is the #1 predictor of broken fixes. Run the tests. |
| "Let me fix these three things at once" | Multi-variable changes make it impossible to know what worked. Test one hypothesis at a time. |
| "The error message says X, so it must be X" | Error messages lie. Verify with logs, debuggers, and traces. |
| "The fix is one line, I'll just write it and escalate nothing" | Escalate every fix. Even one-line fixes go through `/geniro:implement`; the review gate still applies. |
| "I added experimental logging and while I'm here I'll patch the bug too" | Experiments and fixes are separate deliverables. Revert experimental edits; escalate the proposed patch. |
| "The user said just fix it" | If user explicitly overrides, pick "Leave it to me" in and produce the patch as text — still do NOT write it to source. User applies manually. |
| "Changes look fine, I'll skip adversarial mode" | "Looks fine" is the attacker's favorite surface. If user asked for verify-changes, run the adversarial pass — a zero-red-tests outcome is still a valid deliverable. |
| "Small diff, adversarial pass is overkill" | The 10-test hard cap and single-agent cost make adversarial mode cheap even on small diffs. Skip only when the skip-matrix rules fire. |
| "I'll reason about edges instead of authoring tests" | Reasoning is reviewer-mindset. Adversarial mode AUTHORS executable failing tests because reasoning misses what running code catches. |
| "The agent reported F→P, I'll trust it" | Orchestrator MUST independently re-run authored tests. Self-reported F→P is evidence, not proof. |
| "A finding improves an agent prompt, I'll include it in" | Plugin files are out of scope. Suggest only project-owned targets (CLAUDE.md, `.geniro/instructions/`, `.geniro/knowledge/learnings.jsonl`, `.claude/rules/*`). |
| "The findings are in state.md, I'll just ask the escalation question" | state.md is a scratchpad, not a user-facing report. requires explicit findings summary in chat AND persisted to `from-debug-<branch>.md` before escalation question. |
| "I'll paste the full findings summary into the escalation command" | options reference `from-debug-<branch>.md` by path — that file IS the handoff. Inlining bloats context and lets copies drift. |
| "The hypothesis matches the symptom — that's confirmation" | Symptom-matching is correlation, not causation. Confirmation requires a captured artifact per Evidence Standard kind 1-5. |
| "I have no DB / log / production access — mark this hypothesis inconclusive" | Inconclusive-by-default is a fabrication shortcut. Run the missing-data gate first. Only mark inconclusive if user confirms they cannot supply the artifact. |
| "The user described the reproduction verbally, that's enough" | Verbal repro is a hypothesis seed, not a re-runnable artifact. requires a captured artifact (failing test, script, curl + response). Convert verbal repro to captured form. |
| "I have a script / curl / query that reproduces the bug, that's enough" | Scripts get deleted at Cleanup and leave no regression guard. mandates the reproduction be authored as a unit/integration test. Escape hatch is invoked only for genuinely non-reproducible cases. |
| "The agent reported the hypothesis confirmed — I'll trust it and move on" | Self-reported confirmation is evidence, not proof. Orchestrator MUST independently re-run the test / re-read the file:line / re-execute the query before advancing to Isolate. |
| "Per protocol I should ask via AskUserQuestion, but this specific intermediate question isn't in the enumerated gates — I'll inline (A)/(B) in chat" | The canonical Universal Rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` makes the tool mandatory for ANY choice question. If you catch yourself rationalizing "but this case is different / needs runtime confirmation / is just a quick check" — stop and call the tool. |
| "I'll name the reproduction test after the confirmed hypothesis number from `## Hypotheses`" | state.md gets deleted at Cleanup; the test ships with the fix. A name like `Bug C` or `Hypothesis 2 reproduction` is meaningless to whoever reads the test in CI weeks later. |
| "I see two valid fixes for this root cause — I'll just pick one and write the text proposal" | multi-path fix gate (Always-WAIT) requires AskUserQuestion whenever the root cause has more than one valid fix path with real trade-offs. |
| "Add a wall-time kill cap so long-running debug sessions abort cleanly." | Class-A hard caps abort legitimate complex investigation mid-stride. quality-first — no Class-A caps. stall gate (5 inconclusive) and fix-fail gate (2 attempts) escalate to user via AUQ. |
| "Spawn parallel adversarial-tester-agents to speed up diff scan." | A4 keeps a single agent spawn. Parallel adversarial agents would double cost for marginal coverage — the 10-test hard cap already bounds scope. |
| "Skip the findings summary; the AUQ options carry enough context." | makes findings visible BEFORE escalation. Without it, user cannot make a routing decision. Block 5c expects the summary as compaction-recoverable; non-negotiable. |
| "Auto-promote L2 diagnoses to L4 rules when recurrence detected." | + — surface a suggestion line; do NOT auto-promote. User remains source-of-truth for L4 curation. Auto-promotion creates noise + drift. |
| "Defer compaction-survival to downstream skills — This skill is mid-pipeline." | The contract IS this skill's contract — state.md frontmatter, `approvals[]`, `## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason`. Without them, compaction mid-investigation loses the entire hypothesis trail. |
| "Bypass `git guardrail` hooks if a needed `git bisect` step blocks." | Hooks fail for a reason. `git bisect` is permitted (read-only investigation per § ACI per-phase). If a specific guardrail blocks legitimate debug work, the path is `.geniro/safety.json` allow_patterns, not `--no-verify`. |
| "Stall gate is paternalistic — user can just retry with more hypotheses." | 5-inconclusive gate protects against accidental infinite-loop UX. User retains agency via 8-option AUQ. |
| "Self-fix indefinitely until verify passes." | — bounded to 2 fix attempts. Past 2, escalate AUQ. «Kick it until it passes» is an anti-pattern. |
| "Auto-handle MEDIUM-tier adversarial findings to reduce user friction." | The Metaswarm anti-pattern. the surfaces all CRITICAL/HIGH/MEDIUM findings in A6 Adversarial Findings template. Never auto-drop. |

---

## Infrastructure Investigation

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

## Isolation Techniques

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

## Anti-pattern check

This implementation does NOT reintroduce:

1. ✅ **One giant prompt** — modular SKILL.md + `_shared/*.md` references (per-finding-question.md, debug-handoff.md) + inlined guidance sections.
2. ✅ **One giant tool** — narrow Read/Edit/Write/Bash + ACI per-phase (§ ACI).
3. ✅ **Unbounded autonomous loop** — 5-inconclusive + 2-attempt + adversarial 10-test hard cap, all escalating to user via AUQ.
4. ✅ **Autonomous external sends in first release** — N/A for /debug (no `git push`, no `gh pr create`).
5. ✅ **No approval state** — `approvals[]` + Block 5d render (categories: disambiguate_mode, multi_path_fix).
6. ✅ **No durable plans or goals** — state.md mandatory.
7. ✅ **No compaction strategy** — the SessionStart re-injects via Block 2-6 (+5b errors + 5c open questions + 5d approvals).
8. ✅ **All connectors loaded up front** — Claude Code's MCP plugin model gates this.
9. ✅ **High-risk tools without policy** — file-protection, git-guardrail,.geniro/ deletion hooks + § ACI per-phase blocks.
10. ⚠️ **Subagents before single-agent MVP measured** — Adversarial Mode spawns 1 agent (adversarial-tester); single-agent measurement deferred to a future release.
11. ✅ **Dynamic timestamps in plugin-distributed Markdown** — N/A; this SKILL.md has no runtime-timestamp bodies.
12. ✅ **Non-deterministic agent registration order** — N/A; agent registration is alphabetic by slug.

---

## Definition of Done

For each debug session, confirm the checklist for the mode that ran.

### Scientific Mode

- [ ] Bug reproduced consistently with clear steps
- [ ] feedback loop built: command + expected output + captured artifact recorded in state.md `## Feedback Loop`; re-run cost ≤30s preferred; 3-run determinism check passed
- [ ] L4 / L3 / L2 layers loaded at Phase 1 entry
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
- [ ] L2 emit fired with `diagnosis` type + `ext.{symptom, root_cause, fix}`; L4 promotion suggestion surfaced when recurrence detected
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
- [ ] Escalation decision made via (or "no bugs found" exit if zero red tests → terminal `adversarial-aborted`)
- [ ] Authored test files left on disk (NOT reverted — unlike scientific-method experiments)
- [ ] Cleanup completed (`from-debug-adversarial-<branch>.md` may remain as audit trail)

---

## When to Use This Skill

**Use `/geniro:debug`:**
- Bug has unclear root cause
- Quick fix didn't work and you need to understand why
- Bug is intermittent or hard to reproduce
- You're tempted to guess at a fix
- Multiple possible causes exist
- Bug involves async code, concurrency, or state
- You want to verify recent changes (adversarial mode)

**Don't use:**
- Obvious one-line fix (typo, off-by-one) — go straight to `/geniro:implement`
- Bug is already understood and fix is clear — `/geniro:implement` directly
- Need system-wide refactor — `/geniro:implement` or `/geniro:refactor`

**Remember:** debug investigates and *proposes* — it never applies the fix. If the proposed patch looks obvious after, that's a signal you should have gone straight to `/geniro:implement`.

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
