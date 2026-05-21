---
name: geniro:debug
description: "Use when a bug needs systematic investigation. M7 3-phase loop (Investigate → Propose → Ship) mirroring /implement: observe → hypothesize → test → isolate → propose fix → author reproduction test, then escalate to /geniro:implement with а T2 hand-off at .geniro/state/handoff/from-debug-<branch>.md. Adversarial mode authors F→P tests against а diff (verify-changes). Skip for bugs with obvious root cause — go straight to /geniro:implement."
context: main
model: opus
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, WebSearch]
argument-hint: "[bug description | verify <diff-range> | verify last changes]"
---

# Debug: Scientific-Method Investigation (M7)

Use this skill к systematically debug complex issues. Replaces guessing with evidence gathering и hypothesis testing. Pre-M7 9-step workflow collapsed к 3 phases mirroring `/geniro:implement` per master plan §119.

**Architecture spec:** `architecture/M7-debug-redesign.md`. Detailed contracts:
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/infrastructure-investigation.md` — infrastructure-cause guidance (M7 §6.5)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/isolation-techniques.md` — binary search / git bisect / profiling (M7 §6.7)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Investigation-driven fix gate (debug-flavored) — multi-path fix gate (M7 §7.2) и repro-infeasible escape hatch (M7 §7.4)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` — consumer protocol для downstream skills reading our T2 hand-offs

**Section-reference convention:** plain `§1.x` / `§2.x` / `§3.x` references in this SKILL.md point к local sub-sections (Phase 1, Phase 2, Phase 3 respectively — header lines `### 1.1`, `### 2.4`, etc. below). References к the architecture spec are explicitly prefixed `M7 §X.Y` (e.g. `M7 §6.8 stall gate`). The architecture spec uses §6/§7/§8 numbering for the same three phases; the SKILL.md mirrors М6's local-numbering convention для readability.

---

## Your Role — Investigate, Don't Ship

You investigate. You isolate. You propose. You do NOT apply the fix. Phase 3 hand-off is а text proposal + reproduction test on disk + а T2 hand-off file at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`. Downstream consumers (`/geniro:implement`, manual user action) apply the patch.

---

## State Machine (M7 §2.1)

state.md `phase:` enum transitions:

```
[entry] → mode-detect ──┬── investigate ──┬── propose ──┬── ship ── done
                        │                  │             │
                        │                  │             └── ship-summary-only (terminal — "Leave it to me")
                        │                  │
                        │                  └── phase-2-escalated ──┬── debug-handoff (terminal — fix-fail)
                        │                                          ├── propose (try-different-approach loop-back)
                        │                                          └── aborted (terminal)
                        │
                        └── phase-1-escalated ──┬── investigate (supply-data loop-back)
                                                 ├── ship-summary-only (abandon — partial findings)
                                                 └── aborted (terminal)

[entry] → adversarial-mode-detect ── adversarial-investigate ── adversarial-ship ──┬── done
                                                                                    └── adversarial-aborted (terminal — zero red tests)
```

**Terminal states:** `done`, `ship-summary-only`, `debug-handoff`, `aborted`, `adversarial-aborted`. M3 SessionStart recovery treats all five as «task complete — no resume needed».

**Non-terminal states:** `mode-detect`, `investigate`, `propose`, `ship`, `adversarial-mode-detect`, `adversarial-investigate`, `adversarial-ship`. M3 recovery rolls these back к phase-entry и re-runs (idempotent — `approvals[]` ensures gates skip already-answered).

**Escalation states:** `phase-1-escalated` (§6.8 stall gate), `phase-2-escalated` (§7.5 fix-fail). M3 surfaces к user as "task was paused — last AUQ options:" so user re-picks без losing context.

**Termination-case mapping** per M7 §2.1.1 — see architecture spec for the full 8-row table. The `## Termination reason` body section is written on `aborted` / `adversarial-aborted` terminals.

---

## Loop Invariants (M7 §2.2)

М4 §2.2's 7 invariants apply unchanged:

1. **One result per tool call.** Adversarial Mode parallel-spawn → each spawn must return а structured result; dead spawn → `status: failed` entry в `## Tool log`.
2. **Args validated before execution.** `$ARGUMENTS` semantic parse; PR ref validation via `mcp__github__pull_request_read` или GraphQL fallback.
3. **Permission before side-effect.** State.md writes via M1 `atomic_state_write`. /debug performs NO `git push` / `gh pr create` — debug never ships code.
4. **Bounded и structured tool results.** `adversarial-tester-agent` output ≤4K chars per finding block; truncation marker. Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.
5. **Escalation gates, not silent abort.** §6.8 stall gate (5 inconclusive) + §7.5 fix-fail gate (2 attempts) escalate к user via AUQ. Never silently fabricate а conclusion.
6. **Final answer grounded в observations.** Evidence Standard для hypothesis confirmation — every Result: field в `## Hypotheses` MUST cite an artifact kind 1-5 per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. "Symptom matches" is correlation, not causation; not allowed.
7. **Errors → structured observations.** Failed `git diff`, denied permission, `adversarial-tester-agent` "agent not found" ladder fallback all become structured `## Tool log` entries before being acted on.

`## Tool log` schema: typical run produces 0-3 entries (subagent-spawn outcomes for adversarial mode, escalation entries for §6.8 / §7.5). Routine Read / Edit / Bash skipped per M4 contract.

---

## Budgets — Quality-First (M7 §2.3)

М7 has **NO hard kill caps**. Same model as M4 / M5 / M6.

**Quality gates (escalate к user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Inconclusive hypothesis tests | 5 across all hypotheses | §6.8 stall gate | AUQ — P-M7-2 diagnose-by-missing-component (8 options) → user supplies missing or picks alternative |
| Fix attempts failed verification | 2 | §7.5 fix-loop gate | AUQ — try different approach / accept as documented limitation / abort. User picks. |
| Adversarial mode authored tests | 10 hard cap | §9.4 (delegated к agent contract) | Stop authoring; surface findings (preserves pre-M7 agent-level rule) |
| Adversarial mode consecutive discards | 5 | §9.4 (delegated к agent contract) | Stop hypothesis generation; surface partial |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| Subagent spawns | 1 (adversarial mode only — `adversarial-tester-agent`) | §9.4 |
| Reproduction-test framework | Project's native (detected from CLAUDE.md Essential Commands) | §7.4 |

**Explicitly NOT capped:** wall-time, total tool calls, total model turns, total cost. Same rationale as M4 §2.3 — complex multi-cause bugs may legitimately need hours of investigation; hypothesis testing against а large codebase may need many Read/Grep calls.

---

## Subagent Model Tiering

Follow the canonical rule в `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly. For plugin-defined subagents (adversarial-tester), also follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — registration ladder (`geniro-claude-plugin:<agent>` → bare `<agent>` → `general-purpose` с agent body inlined). Cache the resolved rung для the rest of the session.

Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site — every Agent() prompt MUST satisfy the six pre-inlined fields.

| Spawn | Tier | Why |
|---|---|---|
| `adversarial-tester-agent` | `inherit` | Reasoning-grade test authoring. Matches the canonical rule in `model-tiering.md` and call sites в `/geniro:review` Phase 4c, `/geniro:implement` Phase 3. The agent's F→P verification + 3× flake check enforce correctness regardless of inherited tier. |

---

## Evidence Standard

Cite the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` — schema, forbidden phrases, и artifact kinds 1-5 are defined there. This skill applies that standard at every hypothesis-confirmation, fix-verification, и §7.4 reproduction-test capture.

**Debug-specific framing — hypothesis-confirmation artifact kinds.** A hypothesis is **confirmed** ONLY when its `Result:` field cites one of the artifact kinds 1-5 from the shared rule. Hypothesis-tracking is the most evidence-rigorous flow в the plugin: every entry в state.md § `## Hypotheses` Result MUST attach a captured artifact (kind 1: file:line + verified snippet; kind 2: captured command/test/build output; kind 3: log line / stack trace; kind 4: datastore query result; kind 5: user-provided artifact). Reasoning is correlation; only reproduction with a captured artifact confirms causation.

If the orchestrator's tools cannot produce evidence for а hypothesis (no DB access, no production logs, no credentials, no environment access), do NOT mark it inconclusive by default — use the missing-data gate в §6.6 to ask the user for the artifact.

---

## Universal Rule: All Choice Questions Use AskUserQuestion

Every user-facing choice в this skill — including ad-hoc gates NOT explicitly enumerated below — MUST go through the `AskUserQuestion` tool per the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Universal AskUserQuestion Rule. The enumerated gates (§6.1 mode, §6.3 repro details, §6.4 repro signal, §6.6 missing data, §6.8 stall diagnosis, §7.2 fix path, §7.4 repro infeasible, §7.5 fix-fail, §8.2 escalate) are examples, not an exhaustive list. If you're about to type `(A)... or (B)...` в chat, stop и call the tool instead.

---

## Phase 0 — Mode Detection ($ARGUMENTS routing)

state.md `phase: mode-detect`. **Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: debug`, `LOAD_TIER: pipeline`, `MODE: initial-load`. Echo per the helper's contract.

$ARGUMENTS routing:

| $ARGUMENTS shape | Mode | Transition |
|---|---|---|
| empty | AUQ с header "Mode" — 4 options: «Describe the symptoms» / «Paste error message» / «Point to а failing test» / «Verify last changes (adversarial)». First 3 → Scientific. Fourth → Adversarial. | `mode-detect` → `investigate` OR `adversarial-mode-detect` |
| matches anchored verify-keyword signals (table below) | Adversarial Mode | `adversarial-mode-detect` |
| otherwise | Scientific Mode | `mode-detect` → `investigate` |

**Anchored verify-keyword signals** (bare keywords alone NOT enough — phrases like "verify that login returns 500" or "stress-test revealed a memory leak" are scientific-method bug reports, not verify requests):

- Anchored keyword signals: `verify <changes|diff|last|recent|my|this|PR>`, `break <my|the> diff`, `hunt for bugs in <diff|change|PR>`, `find edge cases in <diff|change|PR>`, `adversarial <mode|pass|scan|run>`, `stress-test <the diff|my change|last changes>`
- Phrase signals: `verify last changes`, `verify recent changes`, `verify my changes`, `check last changes`, `break my diff`
- Explicit diff range signals: `HEAD~N..HEAD`, `HEAD~N`, `main...HEAD`, bare PR ref (`#1234` или GitHub PR URL), bare branch name + verify keyword

**Approvals-persistence protocol (P-M1-1 producer-side):** before firing the empty-AUQ, check state.md frontmatter `approvals[]` для prior entry с `category: disambiguate_mode`. If found, use prior `picked` value. If not, fire AUQ → on user pick, append к `approvals[]` via M1 `atomic_state_write` before proceeding. M3 §6 Block 5d renders this on resume.

When in doubt (ambiguous input), default to Scientific Mode — user can re-invoke с explicit adversarial phrasing if needed.

---

## Phase 1 — Investigate

state.md `phase: investigate`. Mirrors M4 Phase 1 (entry-gate + context load) plus M4 Phase 2-style inner loop (hypothesis test iterations). Exits к Phase 2 only when а hypothesis is confirmed AND its Result: field cites an artifact per Evidence Standard.

### 1.1 Memory layer load (L2 prior-knowledge query)

On Phase 1 entry, in order:

1. **L4 refresh** — `load-custom-instructions(MODE: refresh, scope: debug + global + code-style + user-preferences — M10b pipeline tier, 4 files)` per M3 §7.2 Echo contract.
2. **L3 refresh** — `load-semantic(MODE: refresh, top-2 default)`. Fingerprint drift check fires если applicable.
3. **L2 prior-knowledge query** — `query-learnings(tags=<inferred from $ARGUMENTS>, scope=task path)` per M2 §5.3 «debug session start» trigger. Top-K=5 default, filter superseded + deprecated. Skipped если $ARGUMENTS too generic к infer tags. Result count IS the recurrence signal used by §8.3 L4-promotion suggestion.

   **P-X8 surfacing convention:** when results include `discarded_hypothesis` entries (P-X8-1), display them с а distinct label so the orchestrator can skip dead-ends faster:
   ```
   Past investigations в this scope ruled out:
     - <ext.hypothesis> (tested <ts> by <ext.tested_by>)
   Past diagnoses:
     - <summary> (fixed <ts>)
   ```
   These get surfaced при §1.4 hypothesis formation так that the orchestrator does NOT re-form а hypothesis equivalent к an already-ruled-out one without explicit re-justification.
4. **Cross-layer conflict resolution** — `resolve-conflicts(L2/L3/L4 loaded)` per M2 §10.

Echo lines per M3 §7.2 mandatory.

### 1.2 Observe & repro

- Reproduce the bug consistently. Capture error messages, logs, stack traces.
- Identify what changed (recent commit, config, user action). Record exact repro steps.
- **If repro is unclear/missing:** `AskUserQuestion` с header "Repro details" — 2-4 concrete options (environment / steps к trigger / expected vs actual behavior). Do NOT guess.

Persist к state.md body sections `## Symptom` и `## Reproduction Steps` (§11.1.B).

### 1.3 Build feedback loop

A feedback loop is а fast (≤30s, ideally ≤5s), deterministic, captured signal that reproduces the bug AND can be re-run cheaply.

**Pick the cheapest option that reliably reproduces:**

| Option | Use when | Example |
|---|---|---|
| Failing assertion в REPL / test runner | Bug is в pure logic, no I/O | `node -e "require('./src/cache').compute(...) // expect 5, got 7"` |
| `curl` against running dev server | Bug is в HTTP/API behavior | `curl -X POST localhost:3000/api/foo -d '{...}' -i` |
| SQL query against test DB | Bug is в query/migration logic | `psql -c "SELECT * FROM users WHERE ..."` |
| Headless browser script | Bug is UI-rendered | Playwright snippet that takes one screenshot |
| Differential test (good vs bad commit) | Regression — works at commit X, broken now | `git checkout <good>; <repro>; git checkout <bad>; <repro>` |
| Fuzz / loop reproducer | Bug is intermittent | `for i in {1..100}; do <repro>; done | grep ERROR` |
| Manual click-through script | Genuinely UI-only с no automation seam | numbered steps в state.md (use as fallback only) |

**Quality bar:**
- **Fast** — re-runs в seconds. If only loop possible takes 5 minutes, shrink scope (smaller payload, in-memory mock, skip auth).
- **Deterministic** — same input → same observed failure (3-run signature comparison). If 3 consecutive runs produce 3 different signatures, you have а flake or two bugs — note this в state.md before continuing.
- **Captured** — artifact satisfies Evidence Standard kinds 2-5 (failing assertion, log line, query result). "I see it crash" is not а captured artifact.

If 10 minutes pass без а working feedback loop, do NOT proceed by guessing — `AskUserQuestion` с header "Repro signal" — paste log / run command / mark intermittent + investigate без loop.

Persist к state.md `## Feedback Loop` body section: Command / Expected output / Actual output / Re-run cost / Determinism (per §11.1.B).

> **NOT the §7.4 reproduction test.** §7.4 authors а unit/integration test в the project framework that ships с the fix as the regression guard. §1.3 builds а fast-iteration scratch signal so §1.4-§1.6 can move quickly. The §7.4 test STAYS on disk; the §1.3 scratch signal is reverted at Cleanup.

### 1.4 Hypothesize

Based on Observation + Feedback Loop output, form **2-3 competing hypotheses**. Each must be testable AGAINST THE FEEDBACK LOOP — §1.5's tests will toggle one variable, re-run the loop, observe whether the captured signature changes.

**Consider infrastructure causes alongside code causes** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/infrastructure-investigation.md`. If symptoms include timeouts, intermittent failures, или environment-only manifestation, form at least one infrastructure hypothesis.

Persist к state.md `## Hypotheses` body section, one block per hypothesis (Hypothesis / Evidence For / Evidence Against / Status: pending → testing → confirmed | rejected | inconclusive / Test Plan / Result per §11.1.B schema).

> **Inconclusive** means the test could not distinguish whether the hypothesis is true or false. Common causes: (1) test environment differs from production, (2) bug is intermittent и didn't manifest, (3) test was too coarse, (4) multiple interacting causes mask effects. Inconclusive is NOT а rejection — you need а better test or more data.

### 1.5 Test each hypothesis + missing-data gate

- Design а minimal test per hypothesis. The test must produce а captured artifact per Evidence Standard kind 2-5.
- Add logging, breakpoints, или unit tests к gather evidence.
- Do NOT implement а fix yet — you're gathering data.
- **Missing-data gate:** if testing requires data the orchestrator's tools cannot reach (production logs, runtime state, third-party API responses, DB rows behind credentials, screenshots), do NOT mark the hypothesis inconclusive by default. `AskUserQuestion` с header "Missing data" — 2-4 concrete options для the specific artifact needed:
  - "Paste the failing log line at the time of the error" / "Paste the request body that triggered the error" / "I don't have it — mark inconclusive"
  - "Run this query against the production DB и paste the result: `<query>`" / "I can't run that query" / "Skip this hypothesis"
  - "Provide а screenshot of the broken state" / "I don't have it — skip"
- Record results: confirmed / rejected / inconclusive. Every Result: field MUST cite an artifact per Evidence Standard. "Confirmed" с narrative-only Result is rejected.

**P-X8-1 L2 emit on REJECTED:** For each hypothesis transitioning к `Status: rejected` (eliminated by а test that produced contradicting evidence), call `emit-learning` с type `discarded_hypothesis`, required `ext.{hypothesis, evidence_against, tested_by}`, trust `verified`. Scope = the file/module the hypothesis targeted. The emit is per-rejection (multiple rejections в one Phase 1 = multiple emits).

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

**Sliding-window cap (Reflexion bound):** keep at most 5 latest `discarded_hypothesis` entries per `(producer, scope)`. Before emit, count existing non-deprecated entries via `query-learnings --type discarded_hypothesis --scope <scope> --include-superseded`; if ≥5, mark the oldest matching entry `deprecated: true` via direct edit к `learnings.jsonl` (M2 §5.2 manual deprecation) BEFORE appending the new one. Prevents discarded-hypothesis chatter от drowning out `diagnosis` entries at retrieval time.

`rejected` is а normal outcome of hypothesis testing — emit fires в the happy path. `inconclusive` does NOT emit (the data is ambiguous; recording it would seed noise). `confirmed` does NOT emit а `discarded_hypothesis` (it emits а `diagnosis` later at §3.3).

state.md `phase: investigate` throughout. `## Hypotheses` body section grows iteratively.

### 1.6 Isolate root cause → [ROOT-CAUSE] finding

Once а hypothesis is confirmed:
- Identify exact code location. Trace data/control flow. Apply techniques per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/isolation-techniques.md` (binary search / git bisect / profiling).
- Understand why the bug happens (not just where).
- **Tag emitted findings per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.** `/geniro:debug` is the root-cause flow by definition — а confirmed hypothesis isolates к а `[ROOT-CAUSE]` finding, NOT `[SYMPTOM]`. `[UNKNOWN]` from debug is а failure mode — if you find yourself emitting `[UNKNOWN]`, the hypothesis loop didn't close (escalate via §6.8 stall gate). `[SYMPTOM]` from debug is also а failure mode — re-enter §1.4 с а new hypothesis.

Persist к state.md `## Root Cause` body section.

### 1.7 Stall escalation gate (P-M7-2 closure)

When the hypothesis loop fails к converge — defined as **5 inconclusive hypothesis tests across all hypotheses** — fire the stall gate before declaring the bug unsolvable:

1. **Do not silently report "cannot determine cause".**
2. Apply the P-M7-2 8-component diagnose-by-missing-component taxonomy (`## Stall Diagnosis Taxonomy (P-M7-2)` below).
3. **Surface к user via `AskUserQuestion`** с header "Stall diagnosis" — render 4 of the 8 categories (AUQ maxItems=4; pick the most likely 4 based on stall context).
4. state.md marks `phase: phase-1-escalated` с timestamp + inconclusive-test count + categorized stall hypothesis. Transitions:
   - User picks (A-G — а concrete missing artifact / category) → `phase: investigate` (resume hypothesis loop с new data).
   - User picks (H — "abandon — present partial findings") → `phase: ship-summary-only` (proceed к Phase 3 с а stall-flagged findings summary).
   - User can also pick "abort" → `phase: aborted` (terminal).

state.md `## Open Questions` body section logs the stall question + categorized hypothesis. M3 §6 Block 5c renders on resume.

---

## Phase 2 — Propose

state.md `phase: propose`. Output authoring: text fix proposal + F→P reproduction test. **No production-source edits applied.** Exits к Phase 3 when fix proposal AND reproduction test are both verified.

### 2.1 L4 refresh entry (single — no double-refresh)

On Phase 2 entry, single `load-custom-instructions(MODE: refresh, scope: debug + global + code-style + user-preferences — M10b pipeline tier, 4 files)` call. Mirrors M4 §13.4 Phase 3 entry contract: always re-fires, drops the conditional-on-marker pattern. Cost: 1 helper read.

### 2.2 Multi-path fix gate (Always-WAIT, P-M1-1-aware)

If the confirmed root cause has more than one valid fix path с real trade-offs (e.g., snapshot-vs-live-fetch, COALESCE vs CHECK constraint vs catch+log, fix-at-source vs fix-at-call-site), do NOT pick one и write а single text proposal.

**Fire `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Investigation-driven fix gate (debug-flavored)**:
- `header: "Fix path"`
- `question` text: confirmed root cause's `path:lines` + hypothesis title
- Each option:
  - `label` (1-5 words) — name of the path
  - `description` — one-line trade-off
  - `preview` — investigation context (Root cause / Evidence от `## Hypotheses` Result / Hypothesis-confirmed status + number per the helper's source-field map)

**Approvals-persistence (P-M1-1 producer-side):** before firing, check state.md frontmatter `approvals[]` для prior entry с `category: multi_path_fix` and matching `root_cause` (use root-cause text as the disambiguator). If found, use prior `picked` value. If not, fire AUQ → on user pick, append entry к `approvals[]` via M1 `atomic_state_write`.

**Re-ask trigger:** if the root cause changes (second-pass investigation overturns the prior root cause), the prior `approvals[]` entry is stale — clear it и re-fire. M3 §6 Block 5d renders this from `approvals[]` on resume.

The single-text-proposal default (§2.3) applies ONLY when there is one obvious right fix; multi-path is the explicit branch.

### 2.3 Text fix proposal

- Formulate the minimal fix for the root cause as а **text proposal**: file path(s), exact change (unified diff или before/after snippet), one-sentence rationale.
- Do NOT write the fix to production/source files. Write/Edit are available для EXPERIMENTS only (tests, logging, debug scripts, `.geniro/state/debug/<slug>/` artifacts) — not for applying the proposed patch.
- If any experiment modified non-test source, revert those edits before escalation; the escalated skill applies the real fix cleanly.
- Do NOT refactor adjacent code.

Persist к state.md `## Proposed Fix` body section.

### 2.4 Author F→P reproduction test + monkey-patch verify

**Author the reproduction as а unit/integration test в the project's test framework**, placed at the project's normal test path next к the source it covers. Detect framework + naming convention от CLAUDE.md Essential Commands + an exemplar test file. Scripts / curl / ad-hoc queries are NOT acceptable substitutes — they get deleted at Cleanup и leave no regression guard.

**Test name + comments rule.** The reproduction test name AND any comments inside the test describe the bug behavior — the input, condition, или observable failure — never the hypothesis number from `## Hypotheses` или any other thread-local label. Tags like `Bug A/B/C`, `Hypothesis 1/2`, `Test 1`, `Case X`, `Issue #N from this run`, `regression from review run`, `found by review-gate`, или `confirmed by this <skill> run` are meaningless once the investigation ends. Prefer `cacheKey omits userId so role change leaves stale cached profile` over `Bug C`.

**F→P invariant.** Pre-fix: run the authored test ≥2× и confirm the SAME failure signature both times (same exception type + same failing assertion). Two divergent failures are NOT confirmation — investigate flakiness or two bugs before continuing.

**Verify the proposed fix — monkey-patch в the test by default; production-source edits are an explicit escape hatch.** Apply the patch locally as а monkey-patch inside the authored test file (mock, fixture, test-local shim, или а throwaway helper imported only by the test). Re-run the authored test ≥2× post-fix и confirm the failure DISAPPEARS both times. If the bug genuinely cannot be verified без editing production source (hard-to-mock chain — DI container, framework hook, native module, generated code), list every touched production file под "Verification edits to revert:" в the §8.1 findings, confirm each is reverted before escalation, и re-run `git diff` к prove the working tree contains only the reproduction test.

**Escape hatch — non-deterministic bugs only.** If the bug is genuinely non-reproducible at the test layer (race conditions only seen under load, environment-only failures, UI flake), `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Investigation-driven fix gate:
- `header: "Repro infeasible"`
- `question`: best-guess root-cause `path:lines` (или "unknown" if not isolated) + hypothesis title
- Options: regression-guard alternatives — "Add runtime assertion" / "Author fuzz seed" / "Add monitor/alert" / "Skip regression guard" (description carries one-line trade-off)

Record the user's selection AND rationale в state.md `## Reproduction Test` body section under "Reproduction Decision". The default is mandatory; escape hatch is opt-in с а paper trail.

Do NOT run the full project test suite here — that's the receiving skill's responsibility. Phase 2's goal is the F→P-verified test artifact + evidence the proposed patch turns it green.

If the project uses code generation (check CLAUDE.md) AND the proposed fix touches DTOs/schemas/controllers: note this в the §8.1 findings template "Special handling" field.

### 2.5 Fix-loop escalation (2 fix attempts failed → AUQ)

When 2 distinct fix proposals fail F→P verification (each pre/post-fix monkey-patch round counts as one), surface к user — mirrors M4 §7.4 escalation pattern:

1. Do **not** silently report "no fix works".
2. `AskUserQuestion` с header "Fix-fail" и options:
   - **Try different approach** — go back к §1.4 (Hypothesize) с а fresh angle. state.md transitions back к `phase: investigate`.
   - **Accept as documented limitation** — proceed к Phase 3 ship sub-step с `## Accepted Limitations` block в state.md body. state.md transitions к `phase: ship`. Receiving skill sees the unresolved limitation в the §8.1 findings summary.
   - **Abort** — `phase: aborted` (terminal).
3. state.md marks `phase: phase-2-escalated` с timestamp + fix-attempt count + accumulated test outputs. M3 §6 Block 5c renders open question on resume.

**P-X8-3 L2 emit on fix-loop exit.** When Phase 2 exits AND `fix_attempts ≥ 2`, call `emit-learning` с type=`retry_failure_sequence`, trust=`verified`, required `ext.{phase: "fix-attempts", attempts: [{round: N, failure: "<why this attempt did not verify>"}], resolution}`. `resolution` ∈ `{passed, escalated, aborted}` (passed = test confirmed fix; escalated = user picked "Try different approach" or "Accept as documented limitation"; aborted = terminal). Sliding-window cap = 3 latest per `(producer, scope, phase)`. Single-attempt exits (fix_attempts == 1) do NOT emit. Scope = the file/module the fix targeted.

---

## Phase 3 — Ship

state.md `phase: ship`. Findings hand-off к downstream skill OR user-handles. **No `git push` / `gh pr create`** — debug never ships code, only proposals + tests authored locally.

### 3.1 Present findings (chat + persist T2 handoff)

Before asking where к route the fix, present а human-readable findings summary к the user. Do NOT jump straight к the escalation AUQ — the user chooses the escalation target based on this summary.

Output the markdown block directly в chat AND write the same content (с full M1 §T2 frontmatter wrapping it) к `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` via `atomic_state_write`. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so the handoff survives worktree teardown.

**Findings template body:**

```markdown
## Debug Findings

**Source branch:** [from `git branch --show-current`]

**Source worktree:** [from `git rev-parse --show-toplevel`]

**Why escalating to <target>:** [one sentence — which target и concrete reason scope fits it; user makes final routing choice в §3.2]

**Root cause:** [one sentence, plain language — why the bug happens]

**Reproduction:** [exact steps that trigger the bug]

**Confirmed hypothesis:** [which numbered hypothesis from `## Hypotheses` was confirmed, и the test result that confirmed it]

**Rejected hypotheses:** [brief — which hypotheses were ruled out и why]

**Proposed fix:**
- Files: [path(s) that need to change]
- Change: [unified diff или before/after snippet]
- Rationale: [one sentence tying the change to the root cause]

**Evidence the fix works:** [default: "failing test went green under in-test monkey-patch; production source untouched"; или "<n> production files edited as escape hatch и reverted; bug stopped reproducing"]

**Reproduction test:** [<path>, <F→P status — example: "verified red on current code; verified green under throwaway patch">  — OR — "escape hatch: <alternative guard с rationale>"]

**Special handling:** [codegen, migrations, schema changes, env/config updates — или "none"]

**Stall-flagged?** [omit if §1.7 stall gate did NOT fire; if it did: "Yes — cause not fully isolated; <P-M7-2 component> identified as missing. Receiving skill should treat this as а starting point, not а closed investigation."]

**Accepted limitations?** [omit unless §2.5 fix-fail path "Accept as documented limitation" was taken; if so: "<description of limitation>; user accepted on <ISO timestamp>"]
```

The receiving skill pre-loads findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` — the state file is the handoff channel, not а chat paste. Do NOT re-derive, reword, или inline the summary into the escalation command; the file path IS the contract.

### 3.2 Escalation AUQ (4 options)

Only after the summary above is visible AND persisted, `AskUserQuestion` с header "Escalate" и these options:

- **Trivial — run `/geniro:implement`; pre-load findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`** — ≤2 files, obvious target, no architecture или auth/permissions change.
- **Non-trivial — run `/geniro:implement`; pre-load findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`** — touches multiple modules, changes interfaces, needs architecture review, или introduces а new pattern. (Both Trivial и Non-trivial route к the same target — `/geniro:implement` per master plan §66 absorbed `/follow-up`. The Trivial/Non-trivial designation surfaces в the spec context the receiving skill loads.)
- **Cannot verify — request specific data from user** — pick this когда one or more hypotheses are unverified because the orchestrator's tools cannot reach the artifact. Trigger а follow-up `AskUserQuestion` с concrete options для the missing data. Когда data arrives, return к §1.5, do NOT escalate yet.
- **Leave it to me** — user will apply the patch manually using the state file as reference. state.md transitions к `phase: ship-summary-only` (terminal).

Do NOT auto-invoke the next skill — surface the suggestion only. State file IS the handoff channel. You do NOT apply the patch yourself.

### 3.3 L2 auto-emit + L4 promotion suggestion (P-M4-5 mirror — replaces deleted /learnings)

At Phase 3 exit:

- **`emit-learning` (M2 §5.2)** — called by /debug at two distinct points:
  - **`diagnosis`** (primary M7 emit type, fires at Phase 3 exit on confirmed root cause) — every confirmed root cause emits one entry с summary, tags (inferred от affected-files + hypothesis category), scope (project-relative path glob), и required `ext.{symptom, root_cause, fix}` per M2 §5.2 typed-extension table. Default trust `verified` per M2 §5.3.
  - **`discarded_hypothesis` (P-X8-1, fires at §1.5 per-rejection during Phase 1)** — every rejected hypothesis emits one entry с required `ext.{hypothesis, evidence_against, tested_by}`. Sliding-window cap = 5 latest per `(producer, scope)`. See §1.5 for the payload schema и emit logic.
  - **NOT emitted by M7:** `pitfall` (/refactor + /review own), `convention` (/implement self-review owns), `decision` (/plan owns), `discovery` (/refactor + /onboard + /investigate own).

- **L4 promotion suggestion (P-M4-5 mirror):** когда the §1.1 prior-knowledge query returned **≥1 matching prior diagnosis** (recurrence signal), surface а one-line suggestion в the Phase 3 final report:

  ```
  [learnings] Diagnosis recorded: "<one-line summary>". Recurrence detected (<n> prior matching entries). Recorded к L2.
    → Consider /geniro:instructions edit <scope>.md к promote as а debug-rule.
  ```

  Scope hint follows the diagnosis category:
  - Style/convention root causes → suggest `code-style.md`
  - Workflow/process root causes → suggest `debug.md`
  - Architecture/global root causes → suggest `global.md`
  - Other → generic "appropriate scope"

  Suggestion fires only когда recurrence is detected — single-occurrence diagnoses не warrant L4 promotion (user remains source-of-truth для L4 curation). The line is informational (no AUQ, no auto-edit). Fully automatic L2→L4 promotion deferred к P-X6.

### 3.4 Suggest improvements (project scope only, M2 §5.4 routes)

After L2 emit, follow the canonical routing в `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md`. Debug runs typically surface:

| Insight category | Target | M2 layer |
|---|---|---|
| Coding conventions / naming patterns discovered during isolation | `.claude/rules/<scope>.md` с `paths:` glob frontmatter | L4 procedural |
| Docs describing behavior not matching reality | `CLAUDE.md` или project docs | L3 semantic |
| New/changed commands discovered during debugging | `CLAUDE.md` (Essential Commands section) | L3 semantic |
| Non-obvious debugging insights / workarounds | `.geniro/knowledge/learnings.jsonl` (via `emit-learning`) | L2 episodic |
| Skill-behavior quality gates / workflow steps user enforced manually | `.geniro/instructions/debug.md` или `.geniro/instructions/global.md` | L4 procedural |

Plugin-internal paths (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope.

### 3.5 Cleanup

After Phase 3 completes (escalated, accepted, или user-handles):

- **Scientific-method mode only:** Remove `<PRIMARY_ROOT>/.geniro/state/debug/<slug>/state.md` для the current branch's slug only, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract — its useful content has already been saved (root cause, repro, hypotheses-tested-and-rejected, accepted limitations) via L2 emit + persisted handoff. Do NOT delete sibling slugs from concurrent debug sessions on other branches.
- **Clear five legacy generations** (best-effort; any may not exist):
  ```bash
  rm -f ".geniro/debug/HYPOTHESES.md" 2>/dev/null                      # Gen 1: original (pre-state-dir, non-scoped)
  rm -f ".geniro/debug/HYPOTHESES-${slug}.md" 2>/dev/null               # Gen 2: intermediate (pre-state-dir, slug-scoped)
  rm -f ".geniro/state/debug/HYPOTHESES-${slug}.md" 2>/dev/null         # Gen 3: pre-M7 (under state-dir, slug-scoped)
  rm -f ".geniro/state/debug/findings-state.md" 2>/dev/null             # Gen 4: pre-M7 T2 handoff
  rm -f ".geniro/state/debug/adversarial-tests.md" 2>/dev/null          # Gen 5: pre-M7 adversarial T2 handoff
  ```
- **Scientific-method mode only:** Remove debug scripts, scratch reproductions, the §1.3 feedback-loop scratch signal, и ad-hoc curl/query files created during investigation. The §2.4 reproduction test (authored at project's normal test path) STAYS on disk — it ships с the fix as the regression guard.
- **Scientific-method mode only:** `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` MUST remain on disk as the escalation handoff channel — do NOT delete. Stays until next debug run overwrites it (single file per branch).
- Kill any background processes started during investigation (dev servers, watchers, profilers).
- **Adversarial mode:** `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` may remain as audit trail; authored test files stay on disk (unlike scientific-method experiments which get reverted).

Cleanup is best-effort — if а command fails silently, that's fine.

### 3.6 Atomic non-resumable updates

After each side-effect that cannot be replayed safely (none в baseline M7 — debug performs no `git push` / `gh pr create`), append а structured entry к state.md frontmatter `non-resumable-actions[]` via M1 `atomic_state_write`. Mirrors M4 §7.5 step 4.

The empty baseline is intentional: debug ships proposals, not commits. If а future user-customization introduces side-effects (e.g. а `.geniro/actions/post-finding-to-slack.md` invocation), THAT action becomes а non-resumable entry — not the standard ship flow.

---

## Adversarial Mode (verify-changes)

state.md `mode: adversarial`. Phases: `adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship`. Parallel к Scientific Mode; shared Phase 0 routes here on anchored verify-keyword signals (Phase 0 above).

### A1. Purpose

Attacker-mindset pass that AUTHORS executable F→P failing tests against а diff. Complements Scientific Mode: Scientific Mode REPORTS hypotheses about а known bug; Adversarial Mode hunts for unknown bugs в recent changes by writing tests that fail on today's code. Test authoring is delegated к `adversarial-tester-agent`; the orchestrator independently re-runs authored tests к confirm the failure before surfacing findings.

### A2. Diff resolution

**Delegates к /review Phase 1 multi-form parser.** See `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 1 — do NOT duplicate the parser here.

**Default когда no explicit range:** scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` — anchor on the current cwd's worktree + currently-checked-out branch. Resolve the base branch per scope-anchor rule #3 (`git symbolic-ref --short refs/remotes/origin/HEAD`). Compute `git diff <base>...HEAD`. If on the base branch, fall back к `HEAD~1..HEAD`.

**Supported shapes:** bare keyword (`"verify last changes"`) → default; explicit range (`HEAD~3..HEAD`, `abc123..def456`); branch (`feat/foo...HEAD`); PR ref (strip leading `#`, resolve via `gh pr diff <number-or-url>` или `mcp__github__pull_request_read`).

### A3. Skip conditions

Mirror canonical skip-matrix at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. Adversarial mode is SKIPPED и the skill reports `"no adversarial pass — <reason>"` когда:

- Empty diff (nothing к test).
- Diff contains zero production-code files (docs / config / lock / generated only).
- Diff >50 changed files OR >1000 changed LOC → suggest `/geniro:review` для oversized diffs (the agent's 10-test hard cap wastes budget on diffs this large).

### A4. RED-phase workflow

Runs the **RED phase** of the canonical cycle at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § RED phase: author the failing test FIRST, verify it fails с а real assertion signature, then escalate the fix к the receiving skill (which runs GREEN). Tests are never authored alongside или after the fix в this mode — RED-first ordering is non-negotiable.

1. **Resolve the diff** (A2). Pre-inline full diff + changed-file contents для the spawn prompt.
2. **Detect the project test framework.** Read CLAUDE.md Essential Commands + `package.json` scripts / `pyproject.toml` / `Cargo.toml` к extract test command, naming convention, и 1-2 exemplar test files closest к changed code.
3. **Spawn `adversarial-tester-agent`** к AUTHOR RED tests — see Spawn Template (A5). The agent writes failing tests against today's code; no fix is authored.
4. **Independently verify RED.** Read the agent's report at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`, extract authored test file paths, run the project test command **once per authored test** (single independent re-run — the agent already ran а 3× flake check per its Step 5). Tests that do not fail deterministically are deleted from disk AND removed from the report. This is the orchestrator-side RED-verification per `tdd-cycle.md` § RED phase Step 3.
5. **Present Adversarial Findings** (A6 template).
6. **Escalate fix authoring** — reuse §3.2 escalation AUQ (Trivial / Non-trivial / Cannot-verify / Leave-it-to-me) с findings file path referencing `from-debug-adversarial-<branch>.md` instead of `from-debug-<branch>.md`. The authored test file paths inside are the escalation targets. The receiving skill writes the fix и runs GREEN verification (`tdd-cycle.md` § GREEN phase). If zero red tests survived re-verification, SKIP §3.2 entirely — report `"no bugs found in scanned diff"` и go directly к Cleanup; terminal state `adversarial-aborted` с `## Termination reason: no-bugs-found-in-diff`.

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
none — adversarial mode runs а fresh pass (no prior reviewer findings available in debug).

### Output
Write your report к `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` (resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A). Authored test files go к the project's normal test paths. Do NOT git add/commit/push.

### F→P Invariant (NON-NEGOTIABLE)
Every test you keep MUST fail 3 times in а row on the current code. If it passes today, delete the test и mark `discarded-cannot-repro`. Flaky = discard.

### Scope
Diff-only — the orchestrator resolved the scope above. Do NOT author tests for files outside the changed-files list. Hard cap: 10 authored tests.

Anchor: stay within WORKTREE on BRANCH — verify с `pwd && git branch --show-current` on first Bash call; abort if either differs. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""", description="Adversarial tests: /geniro:debug verify-changes")
```

### A6. Findings template

After re-verification, present this block directly в chat и persist (via the agent's write at A4 step 3 + the orchestrator's re-verify delta if tests were discarded):

```markdown
## Adversarial Findings

**Diff scope:** [range + file count + LOC]

**Hypotheses generated:** [N]
**Tests authored (kept after re-verify):** [M]
**Tests discarded (F→P failed on re-run):** [K]

### CRITICAL / HIGH findings
[For each: test file path, targeted source, category, confidence, hypothesis, reproduction command, suggested direction для fix (NOT the patch itself)]

### MEDIUM findings
[same shape]

### Discarded / Inconclusive
[brief list с reasons]

**Zero red tests?** [If M == 0 after re-verify: state plainly "no bugs found in scanned diff" — this is а valid outcome.]
```

If zero red tests survive, skip escalation entirely и go directly к Cleanup. Otherwise proceed к escalation per A4 step 6.

---

## Stall Diagnosis Taxonomy (P-M7-2)

When /debug stalls (5 inconclusive hypothesis tests, §1.7 stall gate), classify the root-cause-of-the-stall as а missing component:

| # | Missing component | Symptom | AUQ option label | AUQ description |
|---|---|---|---|---|
| A | **Missing instruction** | Hypothesis tests don't converge because the orchestrator lacks а project-specific rule (e.g., "we use SQS not Kafka here") | "Missing project rule" | Paste the rule или point к а CLAUDE.md / `.geniro/instructions/*` section |
| B | **Missing source-of-truth** | Test results contradict reasonable assumptions because canonical state (DB row, prod log line, third-party API response) is unreachable | "Missing source of truth" | Paste the DB row / log line / API response |
| C | **Missing tool** | Orchestrator cannot read the artifact format (binary blob, proprietary protocol, sandboxed environment) | "Missing tool" | Provide the parsed/decoded form, или specify а tool the user can run locally |
| D | **Missing validator** | Hypothesis tests "pass" via narrative-only Result but cannot be objectively verified (e.g., race-condition theories) | "Missing validator" | Author а deterministic re-runnable check (curl + grep, SQL query, regex on log) |
| E | **Missing permission rule** | Hypothesis blocked by safety-hook or `.geniro/safety.json` denial | "Missing permission" | Add the relevant pattern к `.geniro/safety.json` `allow_patterns` |
| F | **Missing sandbox signal** | Tests inconclusive because environment differs от production (Docker vs. host, ARM vs. x86) | "Missing sandbox signal" | Re-run в the production-like environment и paste the captured signal |
| G | **Missing eval** | Bug type has no existing regression test pattern в the project — hypotheses cannot be expressed в the existing test framework | "Missing eval pattern" | Author а new test pattern (parameterized fuzzer, mutation-test seed, etc.) |
| H | **Missing recovery path** | All hypotheses confirmed но the fix path is unclear because the bug spans а DI / generated-code / framework-internal layer | "Missing recovery path" | Specify whether the production-source escape hatch (§2.4) is acceptable, или escalate as architectural |

**AUQ rendering:** §1.7 stall gate fires `AskUserQuestion` с header "Stall diagnosis". Render 4 of the 8 categories at а time (AUQ maxItems=4) — model picks the most likely 4 based on stall context (inconclusive-test outputs, hypothesis types tried). User picks one or "Other". Each option's `preview` (where helpful) shows what Phase 1 will do next.

state.md `## Open Questions` logs the stall AUQ + user's pick + delivered artifact (if applicable). M3 §6 Block 5c renders on resume.

---

## State file schema (M1 §T1 base + M7 extensions — see M7 §11 для full schema)

### state.md (T1 — session-bound, `.geniro/state/debug/<slug>/state.md`)

Frontmatter (M1 §T1 required + M7 extensions):

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
approvals: []                  # P-M1-1 — categories: disambiguate_mode, multi_path_fix
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
- `## Accepted Limitations` (optional, §2.5 path B)
- `## Tool log` — M3 §6 selective logging (adversarial-tester-agent spawns, stall escalations)
- `## Errors` — M3 §6 Block 5b
- `## Open Questions` — M3 §6 Block 5c (stall AUQ + outcome)
- `## Termination reason` — M3 §6 (only on terminal aborted-state)
- `## Persisted approvals` — M3 §6 Block 5d (render of frontmatter approvals[])

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

Body: full content of §3.1 findings template + M3 body sections (`## Tool log` / `## Errors` / `## Open Questions` / `## Persisted approvals`).

### from-debug-adversarial-<branch>.md (T2 — handoff, Adversarial Mode)

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`. Same schema as from-debug-<branch>.md with `mode: adversarial` и `phase: adversarial-ship` discriminators. Body: A6 Adversarial Findings template + M3 body sections.

---

## ACI per-phase tool surface (M7 §12.5)

**Phase 0 (Mode Detect):**
- Allowed: Read / Bash (read-only — `git branch --show-current`, `git rev-parse`).
- Explicitly blocked: any Edit/Write, any side-effect tool.

**Phase 1 (Investigate):**
- Allowed: Read / Grep / Glob / Bash (read-only — `git status`, `git log`, `git diff`, `git blame`, `git bisect`, test re-runs без code edits, log inspection, profiler invocations, third-party CLI like `psql -c` against test DB if configured).
- Allowed: Edit / Write для EXPERIMENTS only — debug scripts, logging statements, scratch test files, `.geniro/state/debug/<slug>/` artifacts.
- Explicitly blocked: production-source Edit/Write, `git push`, `gh pr create`, branch switching без user confirmation.

**Phase 2 (Propose):**
- Allowed: Read / Grep / Glob / Bash (read-only + experimental test runs).
- Allowed: Edit / Write для reproduction test authoring (§2.4) + experimental monkey-patches (§2.4 escape hatch).
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

## Memory I/O Schedule (M2 §13 obligation — M7 §12)

| Phase | Helper | Direction | MODE |
|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` |
| Phase 1 entry | `query-learnings` | read L2 | n/a (M2 §5.3 «debug session start» trigger) |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` (single re-fire — drops pre-M7 double-refresh per §2.1) |
| Phase 3 exit (§3.3) | `emit-learning` | write L2 | n/a (sole emit type: `diagnosis`; required `ext.{symptom, root_cause, fix}` per M2 §5.2) |

`update-semantic` is NOT called by M7. Debug investigates existing code; it does not add modules, move files, или rename — those are /implement и /refactor concerns.

---

## Anti-rationalization (M7 §16 — P-MP-1 closure)

| Your reasoning | Why it's wrong |
|---|---|
| "It's probably а cache issue" — guess и code | Guesses waste time. Form а hypothesis, then test it с evidence. |
| "I know what this is, let me just fix it" | Intuition-based fixes mask the real cause. Gather evidence first. |
| "It looks right, no need к test" | "Looks right" is the #1 predictor of broken fixes. Run the tests. |
| "Let me fix these three things at once" | Multi-variable changes make it impossible к know what worked. Test one hypothesis at а time. |
| "The error message says X, so it must be X" | Error messages lie. Verify с logs, debuggers, и traces. |
| "The fix is one line, I'll just write it и escalate nothing" | Escalate every fix. Even one-line fixes go through `/geniro:implement`; architecture/review gate still applies. |
| "I added experimental logging и while I'm here I'll patch the bug too" | Experiments и fixes are separate deliverables. Revert experimental edits; escalate the proposed patch. |
| "The user said just fix it" | If user explicitly overrides, pick "Leave it to me" в §3.2 и produce the patch as text — still do NOT write it to source. User applies manually. |
| "Changes look fine, I'll skip adversarial mode" | "Looks fine" is the attacker's favorite surface. If user asked for verify-changes, run the adversarial pass — а zero-red-tests outcome is still а valid deliverable. |
| "Small diff, adversarial pass is overkill" | The 10-test hard cap и single-agent cost make adversarial mode cheap even on small diffs. Skip only когда the skip-matrix rules fire. |
| "I'll reason about edges instead of authoring tests" | Reasoning is reviewer-mindset. Adversarial mode AUTHORS executable failing tests because reasoning misses what running code catches. |
| "The agent reported F→P, I'll trust it" | Orchestrator MUST independently re-run authored tests. Self-reported F→P is evidence, not proof. |
| "A finding improves an agent prompt, I'll include it в §3.4" | Plugin files are out of scope. Suggest only project-owned targets (CLAUDE.md, `.geniro/instructions/`, `.geniro/knowledge/learnings.jsonl`, `.claude/rules/*`). |
| "The findings are в state.md, I'll just ask the escalation question" | state.md is а scratchpad, not а user-facing report. §3.1 requires explicit findings summary в chat AND persisted к `from-debug-<branch>.md` before §3.2 escalation question. |
| "I'll paste the full findings summary into the escalation command" | §3.2 options reference `from-debug-<branch>.md` by path — that file IS the handoff. Inlining bloats context и lets copies drift. |
| "The hypothesis matches the symptom — that's confirmation" | Symptom-matching is correlation, not causation. Confirmation requires а captured artifact per Evidence Standard kind 1-5. |
| "I have no DB / log / production access — mark this hypothesis inconclusive" | Inconclusive-by-default is а fabrication shortcut. Run the §1.5 missing-data gate first. Only mark inconclusive if user confirms they cannot supply the artifact. |
| "The user described the reproduction verbally, that's enough" | Verbal repro is а hypothesis seed, not а re-runnable artifact. §2.4 requires а captured artifact (failing test, script, curl + response). Convert verbal repro к captured form. |
| "I have а script / curl / query that reproduces the bug, that's enough" | Scripts get deleted at Cleanup и leave no regression guard. §2.4 mandates the reproduction be authored as а unit/integration test. Escape hatch is invoked only для genuinely non-reproducible cases. |
| "The agent reported the hypothesis confirmed — I'll trust it и move on" | Self-reported confirmation is evidence, not proof. Orchestrator MUST independently re-run the test / re-read the file:line / re-execute the query before advancing к §1.6 Isolate. |
| "Per protocol I should ask via AskUserQuestion, но this specific intermediate question isn't в the enumerated gates — I'll inline (A)/(B) в chat" | The canonical Universal Rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` makes the tool mandatory for ANY choice question. If you catch yourself rationalizing "but this case is different / needs runtime confirmation / is just а quick check" — stop и call the tool. |
| "I'll name the reproduction test after the confirmed hypothesis number from `## Hypotheses`" | state.md gets deleted at Cleanup; the test ships с the fix. А name like `Bug C` или `Hypothesis 2 reproduction` is meaningless к whoever reads the test в CI weeks later. |
| "I see two valid fixes для this root cause — I'll just pick one и write the text proposal" | §2.2 multi-path fix gate (Always-WAIT) requires AskUserQuestion whenever the root cause has more than one valid fix path с real trade-offs. |
| "Add а wall-time kill cap so long-running debug sessions abort cleanly." | Class-A hard caps abort legitimate complex investigation mid-stride. M7 §2.3 quality-first — no Class-A caps. §1.7 stall gate (5 inconclusive) и §2.5 fix-fail gate (2 attempts) escalate к user via AUQ. |
| "Spawn parallel adversarial-tester-agents к speed up diff scan." | M7 A4 keeps а single agent spawn. Parallel adversarial agents would double cost для marginal coverage — the 10-test hard cap already bounds scope. |
| "Skip the §3.1 findings summary; the AUQ options carry enough context." | §3.1 makes findings visible BEFORE escalation. Without it, user cannot make а routing decision. M3 §6 Block 5c expects the summary as compaction-recoverable; non-negotiable. |
| "Auto-promote L2 diagnoses к L4 rules когда recurrence detected." | §3.3 + P-M4-5 — surface а suggestion line; do NOT auto-promote. User remains source-of-truth для L4 curation. Auto-promotion creates noise + drift. |
| "Defer M3 compaction-survival к downstream skills — M7 is mid-pipeline." | M3 contract IS M7's contract — state.md frontmatter (M1 §T1), `approvals[]` (P-M1-1 + M3 Block 5d), `## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason`. Без them, compaction mid-investigation loses the entire hypothesis trail. |
| "Bypass `git guardrail` hooks if а needed `git bisect` step blocks." | Hooks fail for а reason. `git bisect` is permitted (read-only investigation per § ACI per-phase). If а specific guardrail blocks legitimate debug work, the path is `.geniro/safety.json` allow_patterns, not `--no-verify`. |
| "Stall gate is paternalistic — user can just retry с more hypotheses." | §1.7 5-inconclusive gate protects против accidental infinite-loop UX. User retains agency via P-M7-2 8-option AUQ. |
| "Self-fix indefinitely until §2.4 verify passes." | §2.5 — bounded к 2 fix attempts. Past 2, escalate AUQ. «Kick it until it passes» is an anti-pattern. |
| "Auto-handle MEDIUM-tier adversarial findings к reduce user friction." | The Metaswarm anti-pattern. M7 surfaces all CRITICAL/HIGH/MEDIUM findings в A6 Adversarial Findings template. Never auto-drop. |

---

## Anti-pattern check (P-MP-1)

Per master plan P-MP-1, this M7 implementation does NOT reintroduce:

1. ✅ **One giant prompt** — modular SKILL.md + `_shared/*.md` references (infrastructure-investigation.md, isolation-techniques.md, per-finding-question.md, debug-handoff.md).
2. ✅ **One giant tool** — narrow Read/Edit/Write/Bash + ACI per-phase (§ ACI).
3. ✅ **Unbounded autonomous loop** — §1.7 5-inconclusive + §2.5 2-attempt + adversarial 10-test hard cap, all escalating to user via AUQ.
4. ✅ **Autonomous external sends в first release** — N/A для /debug (no `git push`, no `gh pr create`).
5. ✅ **No approval state** — `approvals[]` (P-M1-1) + M3 Block 5d render (categories: disambiguate_mode, multi_path_fix).
6. ✅ **No durable plans or goals** — state.md mandatory (M1 §T1).
7. ✅ **No compaction strategy** — M3 SessionStart re-injects via Block 2-6 (+5b errors + 5c open questions + 5d approvals).
8. ✅ **All connectors loaded up front** — Claude Code's MCP plugin model gates this.
9. ✅ **High-risk tools без policy** — file-protection, git-guardrail, .geniro/ deletion hooks + § ACI per-phase blocks.
10. ⚠️ **Subagents before single-agent MVP measured** — Adversarial Mode spawns 1 agent (adversarial-tester); single-agent measurement deferred к P-X6.
11. ✅ **Dynamic timestamps в plugin-distributed Markdown** — N/A; this SKILL.md has no runtime-timestamp bodies.
12. ✅ **Non-deterministic agent registration order** — N/A; agent registration is alphabetic by slug.

---

## Definition of Done

For each debug session, confirm the checklist для the mode that ran.

### Scientific Mode

- [ ] Bug reproduced consistently с clear steps (§1.2)
- [ ] §1.3 feedback loop built: command + expected output + captured artifact recorded в state.md `## Feedback Loop`; re-run cost ≤30s preferred; 3-run determinism check passed
- [ ] L4 / L3 / L2 layers loaded at Phase 1 entry (§1.1)
- [ ] All hypotheses recorded в state.md `## Hypotheses`
- [ ] Each hypothesis has а test plan и result citing artifact per Evidence Standard
- [ ] Root cause identified и confirmed (not guessed), tagged `[ROOT-CAUSE]`
- [ ] Proposed fix is minimal, targeted, written as а text patch (NOT applied к source)
- [ ] When multiple valid fix paths exist, §2.2 multi-path fix gate fired (Always-WAIT) — user chose the path
- [ ] Proposed fix verified against root cause via reverted experiments / monkey-patch
- [ ] Reproduction test authored at project's normal test path, F→P verified, survives Cleanup — OR escape hatch invoked с user-recorded alternative regression guard в state.md "Reproduction Decision"
- [ ] Findings summary (§3.1) presented к user в chat AND persisted к `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` via `atomic_state_write` before the escalation question
- [ ] Escalation decision made via §3.2 AskUserQuestion с options referencing the state file by path
- [ ] All experimental edits к non-test source reverted before handoff
- [ ] L2 emit fired (§3.3) с `diagnosis` type + `ext.{symptom, root_cause, fix}`; L4 promotion suggestion surfaced когда recurrence detected
- [ ] Cleanup completed (§3.5 — state.md removed для current branch's slug only, 5 legacy generations cleared best-effort, temp files cleaned)

### Adversarial Mode

- [ ] Diff scope resolved (range + file list recorded в state.md `## Diff Scope`)
- [ ] Skip conditions checked (and explicitly reported if skipped)
- [ ] Project test framework detected from CLAUDE.md / package.json / pyproject.toml
- [ ] `adversarial-tester-agent` spawned с all 6 context-isolation slots pre-inlined
- [ ] Report written к `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`
- [ ] Authored tests independently re-run by orchestrator (1× per test)
- [ ] F→P-confirmed tests retained; any passing-today tests deleted
- [ ] Adversarial Findings summary (A6) presented к user в chat
- [ ] Escalation decision made via §3.2 (или "no bugs found" exit if zero red tests → terminal `adversarial-aborted`)
- [ ] Authored test files left on disk (NOT reverted — unlike scientific-method experiments)
- [ ] Cleanup completed (`from-debug-adversarial-<branch>.md` may remain as audit trail)

---

## When to Use This Skill

**Use `/geniro:debug`:**
- Bug has unclear root cause
- Quick fix didn't work и you need к understand why
- Bug is intermittent или hard к reproduce
- You're tempted к guess at а fix
- Multiple possible causes exist
- Bug involves async code, concurrency, или state
- You want к verify recent changes (adversarial mode)

**Don't use:**
- Obvious one-line fix (typo, off-by-one) — go straight к `/geniro:implement`
- Bug is already understood и fix is clear — `/geniro:implement` directly
- Need system-wide refactor — `/geniro:implement` or `/geniro:refactor`

**Remember:** debug investigates и *proposes* — it never applies the fix. If the proposed patch looks obvious after §1.6, that's а signal you should have gone straight к `/geniro:implement`.

---

## Examples

### Example 1: Cache Not Invalidating
```
/geniro:debug User sees stale data after profile update
```
→ Phase 1 §1.2 Observe: User updates name, refresh page shows old name
→ §1.4 Hypothesis 1: Cache invalidation broken; Hypothesis 2: Update endpoint not called
→ §1.5 Test: Add logging к cache invalidation и endpoint
→ §1.6 Result: Hypothesis 1 confirmed (cache key mismatch) → `[ROOT-CAUSE]`
→ Phase 2 §2.3 Propose: patch cacheKey builder в `src/cache/user.ts` к include user ID
→ §2.4 Verify: local experiment shows bug disappears с monkey-patch
→ Phase 3 §3.1 Findings persisted к `from-debug-<branch>.md`
→ §3.2 Escalate: /geniro:implement с the proposed patch
→ §3.3 L2 emit `diagnosis` с tags=[cache, invalidation, user-role]

### Example 2: Intermittent Timeout
```
/geniro:debug API endpoint times out randomly under load
```
→ Phase 1 §1.2 Observe: Happens ~5% of requests during stress test
→ §1.4 Hypothesis 1 (code): Database query too slow; Hypothesis 2 (infra per `_shared/infrastructure-investigation.md`): External service timeout
→ §1.5 Test: Profile database queries, check service logs
→ §1.6 Result: Hypothesis 2 confirmed (service is slow)
→ Phase 2 §2.3 Propose: add timeout + fallback around the external service call
→ §2.4 Verify: local experiment shows timeouts disappear с monkey-patch
→ Phase 3 §3.2 Escalate: /geniro:implement с the proposed patch

### Example 3: Verify Recent Changes (Adversarial Mode)
```
/geniro:debug verify last changes
```
→ Phase 0 Mode detect: anchored "verify last changes" → Adversarial
→ A2 Diff resolution: `git diff main...HEAD` (per scope-anchor rule #3)
→ A4 Step 3: Spawn `adversarial-tester-agent` с pre-inlined diff + framework + exemplars
→ A4 Step 4: Independently re-run 7 authored tests; 5 fail RED, 2 pass-today (discarded)
→ A6 Adversarial Findings persisted к `from-debug-adversarial-<branch>.md`
→ §3.2 Escalate: /geniro:implement с the authored tests as escalation targets
