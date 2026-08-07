# Phase 4.3 Test Gate Reference

Detailed contract for `/geniro:review` Phase 4.3 (Test-Confirmation Gate). SKILL.md retains a 2-3 line summary + a pointer here.

State.md `phase: stratify` during Phase 4.3 (which is a sub-phase of Phase 4 stratification).

## Contents

- §1 — Purpose
- §2 — Step 1: Filter findings by decision-type
- §3 — Step 2: User-approval gate (mandatory before any agent spawn)
- §4 — Step 3: Spawn the adversarial-tester-agent
- §5 — Step 4: Independent re-verification by the orchestrator
- §6 — Step 5: Demote-don't-delete logic
- §7 — Step 6: Fail-open

---

## 1. Purpose

Reduce false positives by asking the user whether to spawn `adversarial-tester-agent` to author failing tests that confirm review findings. This is the false-positive reduction stage: independent test-execution catches findings that read as bugs but cannot be reproduced — a different signal than Phase 4.2's read-only verifier. Tests that fail today on independent orchestrator re-run (F→P-confirmed) tag the corresponding finding `[CONFIRMED-BY-TEST]` and stay in the report. Tests that pass today (agent's `discarded-cannot-repro` signal) demote the finding to `## Filtered` with `[CHALLENGED-BY-TEST]` — finding stays visible, deprioritized but not deleted.

**Spawn the agent only after explicit user approval.** The gate is the load-bearing safety property; an inline gate degrades to "this counts as approval".

**Firing phase — during stratify, BEFORE persist.** This gate fires inside Phase 4 stratification (`phase: stratify`), before the Phase 5 persist phase and before the Phase 6 Action gate. It is never deferred to end-of-run and never batched into the same `AskUserQuestion` call as the Action gate. The ordering is load-bearing: a test outcome here can demote a finding to `## Filtered` (a green test → `[CHALLENGED-BY-TEST]`), which changes the finding count the Action gate decides over — so the action decision is downstream of this gate's result. Batching the two into one AUQ lets this gate's answer invalidate the Action gate's own premise ("Review complete: N kept findings") within the same call.

**Two distinct test-related gates — do not conflate.** This Phase 4.3 gate is the test-AUTHORING gate (offer to write failing tests during stratify). The separate commit-policy gate — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §6 Failing-tests gate, which decides whether to commit/push the tests authored here — fires later, in Phase 6. They ask different questions at different phases; an authored test from this gate is what makes the §6 gate fire (via the `## Authored Tests` section, populated in §5 Step 4).

---

## 2. Step 1 — Filter findings by decision-type

**Eligible:**
- Any finding with `Decision Type: [TESTABLE]`.
- CRITICAL or HIGH findings with `Decision Type: [FIX-NOW]` AND whose description names runtime behavior per §2.1's canonical classification.

**Excluded:**
- `Decision Type: [PRODUCT-DECISION]` (multiple valid resolutions — no single behavior to assert).
- `Decision Type: [INTENT-CHECK]` (plan conformance, not runtime).
- `Decision Type: [FIX-NOW]` findings whose description is typo-class per §2.1 (no runtime behavior to test against).

Use the decision-type taxonomy as defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-context.md` §7.
If eligible set is empty after filtering, skip §3's approval gate and §4's agent spawn — do NOT show an AUQ. The §5 Step 4 sentinel write still runs (that step's own note covers exactly this case); once it lands, proceed to Phase 5.

### 2.1 Runtime-behavior classification (canonical rule)

Used by Phase 4.3 Step 1 to decide which `FIX-NOW` findings are test-eligible. A `FIX-NOW` finding's description "names runtime behavior" if and only if it cites at least one of: regex match, parser output, control-flow branch (taken/not-taken), computed result, thrown error type, returned value, mutated state, observable side effect (DOM mutation, file write, API call, db query).

A `FIX-NOW` finding's description is NON-runtime ("typo-class") if it cites: typo / spelling, cross-reference (link, anchor, ref number), wrong import path, dead code that compiles, comment-only edits, formatting, lint-style issues.

The rule is intentionally prose-based and decided at orchestrator-evaluation time; the per-finding line schema does NOT carry a persisted `runtime-class:` tag — Phase 4.3 evaluates it fresh against the finding description each run.

---

## 3. Step 2 — User-approval gate (mandatory before any agent spawn)

This gate is its own `AskUserQuestion` call fired during stratify (per §1 Firing phase) — never batched into the Phase 6 Action gate's AUQ, never deferred to end-of-run. Use `AskUserQuestion` (do NOT print options as plain text). The gate itself is non-negotiable — it fires on every run where the eligible set is non-empty.

**The 3-option set is canonical and rendered verbatim — all three, every run.** Do not drop "Let me pick which findings" because few findings are eligible; do not add an improvised `(Recommended)` to "Skip" or to any option — no option carries a `(Recommended)` suffix.

- **Header:** "Test-gate"
- **Question:** "Author failing tests to confirm review findings? A test that passes today moves the matching finding to a set-aside list — it stays visible, nothing is deleted. No tests are written without your approval."
- **Options (render all three, verbatim):**
- "Author tests for all eligible findings" — never carries a `(Recommended)` suffix
- "Let me pick which findings" — always present; never dropped when the eligible set is small
- "Skip — don't author tests" — never carries a `(Recommended)` suffix

If user picks **"Skip"**, proceed to Phase 5 (no spawn, no state changes, no caveats).

If user picks **"Pick"**, chain `AskUserQuestion` calls (each with `multiSelect: true`) listing eligible findings. Each option's `label` is `path:line — short title — <decision-type in plain English>` (e.g. "automatic fix" / "can be verified with a test" — never the raw taxonomy token, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Multi-select pick loop); each finding's self-contained block is rendered to chat first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering (option `preview` stays empty or a one-line recap — the side-box truncates and is often absent). When more than 4 eligible findings exist, chain follow-up calls per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Cap-extension. If user deselects all, treat as "Skip".

Persist user pick to `approvals[]` with category `test_gate_choice`.

---

## 4. Step 3 — Spawn the adversarial-tester-agent

Spawn ONE `adversarial-tester-agent` (per canonical model-tiering carve-out — frontmatter-declared `model: inherit`, omit `model=` at the spawn site to mirror orchestrator tier; reasoning-grade test authoring) with the eligible findings as hypothesis seeds. The agent already enforces F→P verification, 3× flake check, "test files only", and scope-locked-to-the-diff.

**Resolve the `OUTPUT PATH:` placeholders before sending the prompt** — `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A, `<branch-slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules — and use the same resolved path on every subsequent read in Steps 4 and 5. The agent treats the path as a literal, so an unresolved placeholder creates a literal `<PRIMARY_ROOT>` directory. Keep the `.adversarial-out.md` basename: the state-helper hook exempts that transient-report name, and any other name under `.geniro/state/` is hard-blocked — the agent loses its report rather than merely misfiling it.

```
Agent(subagent_type="adversarial-tester-agent", prompt="""
PROJECT SEARCH POLICY: [the global.md rules governing how to search this codebase, verbatim, or `none declared`]
CHANGED FILES: [list of changed file paths with full content — pre-inlined from Phase 1]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF: [git diff summary]
SHARED EDGE-CASE CHECKLIST: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md (READ at runtime; do not expect it inlined)
PROJECT TEST FRAMEWORK HINTS: [test command from CLAUDE.md, naming convention, 1-2 exemplar test files inlined]
PRIOR REVIEW FINDINGS (hypothesis seeds): [each eligible finding as: path:line — description — decision-type — severity]
OUTPUT PATH: <PRIMARY_ROOT>/.geniro/state/review/<branch-slug>/.adversarial-out.md

Authoring scope: assert on observable business behavior — return values, thrown error shapes, mutated state, side effects at out-of-process boundaries (network/db/queue/file/email/third-party). Do NOT author interaction-style assertions on internal same-process collaborators (`toHaveBeenCalledWith` and equivalents).

For each seeded finding, attempt to author a failing test that reproduces it. If the test cannot be made to fail on current code, mark the hypothesis `discarded-cannot-repro` per your existing protocol — that signal is load-bearing for this caller (it triggers a finding demotion in downstream processing).
Anchor: WORKTREE is your root — run every Bash call from it (`cd <WORKTREE> && …`) and resolve every file path under it.
""")
```

**Overflow caveat (the agent's authored-test cap).** The agent authors at most the number of tests its own contract allows (`${CLAUDE_PLUGIN_ROOT}/agents/adversarial-tester-agent.md` owns the cap). When the eligible set exceeds it, the un-authored findings still post normally — test authoring is additive, never reductive — and the orchestrator surfaces a `## Caveats` note naming them: `N testable findings exceeded the test-authoring cap and post without a failing-test line.`

---

## 5. Step 4 — Independent re-verification by the orchestrator

The agent declares a `Context loaded:` line — check its report for it before consuming the report, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` §Reading the load report back; an `unreadable` path or a missing line is this spawn site's problem to act on, not the agent's.

For EACH authored test in the agent's report's `### Authored Failing Tests (F→P verified)` section, the orchestrator runs the project's test command itself (single re-run; the agent already did 3× flake check). Subagent PASS reports are inputs, not evidence; the orchestrator's independent re-run IS the gate.

Use `backpressure.sh` to keep failing-test output from flooding context:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Test-gate re-run" "<project test command> <test path>"
```

If `backpressure.sh` unavailable: `<project test command> <test path> 2>&1 | tail -80`.

**Capture exit code:**
- Non-zero (red) → test STILL fails on independent re-run → keep authored test on disk; tag the corresponding finding `[CONFIRMED-BY-TEST]`.
- Zero (green) → test passes despite agent reporting it red → likely flake or framework issue. Note "[test path] flipped green on independent re-run" under `## Caveats`. Do NOT delete the test (user reviews authored tests in Phase 6); do NOT tag the finding `[CONFIRMED-BY-TEST]`.

**Persist authored tests for Phase 6.** For every test kept on disk in Step 4 (red on independent re-run), record its path as a row in the state.md `## Authored Tests` body section. Phase 6's Failing-tests gate fires off that section's rows; without this write, the tests authored here never reach the commit-policy gate.

This write also runs when this gate authored nothing — the user declined, the eligible set was empty, or every authored test flipped green. Then the section carries the sentinel `none — the test-authoring gate ran and authored no tests` instead of rows, which is what tells Phase 6 the gate ran at all: a bare section is read as an unwritten result and Phase 6 will not skip on it (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel).

---

## 6. Step 5 — Demote-don't-delete logic

For each eligible finding, correlate to the agent's report by matching its `Targeted source` field against the finding's `path:lines` (proximity match — same file, overlapping line range). Then act per this table:

| Agent's report block | Action on the matching review finding |
|---|---|
| `### Authored Failing Tests` (F→P-confirmed by orchestrator re-run in Step 4) | Tag finding `[CONFIRMED-BY-TEST]` in its severity section. Annotate per-finding line with `confirmed-by: <test path>`. Keep severity unchanged. |
| `### Discarded Hypotheses` with reason "passed on current code" | DEMOTE: remove from current severity section; add to `## Filtered` with reason `test-gate-cannot-reproduce`. Tag `[CHALLENGED-BY-TEST]`. Preserve original severity in the line so user can re-elevate if they disagree. |
| `### Inconclusive` (flaky / framework limitation) | Keep finding unchanged in its severity section. No tag. (The signal is "agent could not decide", not "finding is wrong".) |
| No matching hypothesis at all | Keep finding unchanged. Agent did not attempt this finding (likely deprioritized below its authored-test cap). Orchestrator does NOT infer either way. |

The demote-don't-delete rule is non-negotiable: a green test can mean (a) the bug is not real, (b) the test is wrong, or (c) the test passes for the wrong reason. None of those three is reliable enough to delete a finding on. Preserving the finding in `## Filtered` lets the user re-elevate.

---

## 7. Step 6 — Fail-open

If the adversarial-tester-agent fails to complete, returns malformed output, its report cannot be parsed, or the orchestrator's Step 4 re-run command errors (test framework not installed, exec error): do NOT revoke any findings and do NOT add `[CONFIRMED-BY-TEST]` tags. Surface "test-gate fail-open — bug confirmation skipped for this run" under `## Caveats`. Mirrors the Phase 4.2 verifier fail-open.

Also log a structured entry to state.md `## Errors`:

```yaml
- phase: stratify
stage: phase-4-3
error: adversarial-tester-agent-failed-or-unparseable
consequence: bug-confirmation-skipped
```
