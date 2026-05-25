# Phase 4c Test Gate Reference

Detailed contract for `/geniro:review` Phase 4c (Test-Confirmation Gate). Extracted from SKILL.md (design fix). SKILL.md retains a 2-3 line summary + a pointer here.

State.md `phase: stratify` during Phase 4c (which is a sub-phase of Phase 4 stratification).

---

## 1. Purpose

Reduce false positives by asking the user whether to spawn `adversarial-tester-agent` to author failing tests that confirm review findings. Tests that fail today on independent orchestrator re-run (F→P-confirmed) tag the corresponding finding `[CONFIRMED-BY-TEST]` and stay in the report. Tests that pass today (agent's `discarded-cannot-repro` signal) demote the finding to `## Filtered` with `[CHALLENGED-BY-TEST]` — finding stays visible, deprioritized but not deleted.

**The skill MUST NEVER spawn the agent without explicit user approval.** The gate IS the load-bearing safety property; inline gates degrade to "this counts as approval".

---

## 2. Step 1 — Filter findings by decision-type

**Eligible:**
- Any finding with `decision: TESTABLE`.
- CRITICAL or HIGH findings with `decision: FIX-NOW` AND whose description names runtime behavior (regex match, parser output, control-flow branch, computed result, thrown error type, returned value, mutated state, observable side effect — DOM/file/API/db).

**Excluded:**
- `decision: PRODUCT-DECISION` (multiple valid resolutions — no single behavior to assert).
- `decision: INTENT-CHECK` (plan conformance, not runtime).
- `decision: FIX-NOW` findings whose description names typo / spelling / cross-reference / wrong import path / dead code that compiles / comment-only edits / formatting / lint-style (no runtime behavior to test against).

Use the decision-type taxonomy as defined in `${CLAUDE_SKILL_DIR}/plan-context-reference.md`
If eligible set is empty after filtering, skip the rest of Phase 4c entirely — do NOT show an AUQ. Proceed to Phase 5.

### 2.1 Runtime-behavior classification (canonical rule)

Used by both Phase 4c Step 1 AND Phase 6 Step 3.5. A `FIX-NOW` finding's description "names runtime behavior" if and only if it cites at least one of: regex match, parser output, control-flow branch (taken/not-taken), computed result, thrown error type, returned value, mutated state, observable side effect (DOM mutation, file write, API call, db query).

A `FIX-NOW` finding's description is NON-runtime ("typo-class") if it cites: typo / spelling, cross-reference (link, anchor, ref number), wrong import path, dead code that compiles, comment-only edits, formatting, lint-style issues.

The rule is intentionally prose-based and decided at orchestrator-evaluation time; the per-finding line schema does NOT carry a persisted `runtime-class:` tag — both phases evaluate the rule fresh against the same finding description, so they cannot diverge.

---

## 3. Step 2 — User-approval gate (mandatory before any agent spawn)

Use `AskUserQuestion` (do NOT print options as plain text). When the state-file `mode:` is `tdd`, render the first option's label with literal ` (Recommended)` suffix; in Standard mode, render without the suffix. The gate itself is non-negotiable in every mode.

- **Header:** "Test-gate"
- **Question:** "Author failing tests to confirm review findings? Tests that pass today demote the corresponding finding to ## Filtered (kept visible, not deleted). The skill never writes tests without your approval."
- **Options:**
- "Author tests for all eligible findings" — first option's literal label gains a ` (Recommended)` suffix when `mode: tdd`
- "Let me pick which findings"
- "Skip — don't author tests"

If user picks **"Skip"**, proceed to Phase 5 (no spawn, no state changes, no caveats).

If user picks **"Pick"**, chain `AskUserQuestion` calls (each with `multiSelect: true`) listing eligible findings. Each option's `label` is `path:line — short title — decision: <type>`; each option's `preview` carries the finding's full body (Evidence / Suggested-fix / Confidence / Origin) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Multi-select pick loop. AUQ has a 4-option cap; when more than 4 eligible findings exist, batch across multiple chained questions (≤4 per call) — never drop or merge options. Aggregate selections across all calls. If user deselects all, treat as "Skip".

Persist user pick to `approvals[]` with category `test_gate_choice`.

---

## 4. Step 3 — Spawn the adversarial-tester-agent

Spawn ONE `adversarial-tester-agent` (per canonical model-tiering carve-out — frontmatter-declared `model: inherit`, omit `model=` at the spawn site to mirror orchestrator tier; reasoning-grade test authoring) with the eligible findings as hypothesis seeds. The agent already enforces F→P verification, 3× flake check, "test files only", and scope-locked-to-the-diff.

**Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A before sending the prompt:** substitute the absolute path into `OUTPUT PATH:`, and use the same resolved path on every subsequent read in Steps 4 and 5. The agent treats the path as a literal — passing the unresolved placeholder creates a literal `<PRIMARY_ROOT>` directory.

```
Agent(subagent_type="adversarial-tester-agent", prompt="""
CHANGED FILES: [list of changed file paths with full content — pre-inlined from Phase 1]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF: [git diff summary]
SHARED EDGE-CASE CHECKLIST: ${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md (READ at runtime; do not expect it inlined)
PROJECT TEST FRAMEWORK HINTS: [test command from CLAUDE.md, naming convention, 1-2 exemplar test files inlined]
PRIOR REVIEW FINDINGS (hypothesis seeds): [each eligible finding as: path:line — description — decision-type — severity]
OUTPUT PATH: <PRIMARY_ROOT>/.geniro/state/review-findings-adversarial.md

Authoring scope: assert on observable business behavior — return values, thrown error shapes, mutated state, side effects at out-of-process boundaries (network/db/queue/file/email/third-party). Do NOT author interaction-style assertions on internal same-process collaborators (`toHaveBeenCalledWith` and equivalents).

For each seeded finding, attempt to author a failing test that reproduces it. If the test cannot be made to fail on current code, mark the hypothesis `discarded-cannot-repro` per your existing protocol — that signal is load-bearing for this caller (it triggers a finding demotion in downstream processing).
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")
```

---

## 5. Step 4 — Independent re-verification by the orchestrator

For EACH authored test in the agent's report's `### Authored Failing Tests (F→P verified)` section, the orchestrator runs the project's test command itself (single re-run; the agent already did 3× flake check). Cache invalidation rules governed by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-cache.md` (single source of truth). Sub-agent PASS reports are inputs, not evidence; the orchestrator's independent re-run IS the gate.

Use `backpressure.sh` to keep failing-test output from flooding context:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Test-gate re-run" "<project test command> <test path>"
```

If `backpressure.sh` unavailable: `<project test command> <test path> 2>&1 | tail -80`.

**Capture exit code:**
- Non-zero (red) → test STILL fails on independent re-run → keep authored test on disk; tag the corresponding finding `[CONFIRMED-BY-TEST]`.
- Zero (green) → test passes despite agent reporting it red → likely flake or framework issue. Note "[test path] flipped green on independent re-run" under `## Caveats`. Do NOT delete the test (user reviews authored tests in Phase 6); do NOT tag the finding `[CONFIRMED-BY-TEST]`.

Never trust the agent's red/green claim alone — the orchestrator's independent re-run IS the gate.

---

## 6. Step 5 — Demote-don't-delete logic

For each eligible finding, correlate to the agent's report by matching its `Targeted source` field against the finding's `path:lines` (proximity match — same file, overlapping line range). Then act per this table:

| Agent's report block | Action on the matching review finding |
|---|---|
| `### Authored Failing Tests` (F→P-confirmed by orchestrator re-run in Step 4) | Tag finding `[CONFIRMED-BY-TEST]` in its severity section. Annotate per-finding line with `confirmed-by: <test path>`. Keep severity unchanged. |
| `### Discarded Hypotheses` with reason "passed on current code" | DEMOTE: remove from current severity section; add to `## Filtered` with reason `test-gate-cannot-reproduce`. Tag `[CHALLENGED-BY-TEST]`. Preserve original severity in the line so user can re-elevate if they disagree. |
| `### Inconclusive` (flaky / framework limitation) | Keep finding unchanged in its severity section. No tag. (The signal is "agent could not decide", not "finding is wrong".) |
| No matching hypothesis at all | Keep finding unchanged. Agent did not attempt this finding (likely deprioritized below the hard cap of 10 authored tests). Orchestrator does NOT infer either way. |

The demote-don't-delete rule is non-negotiable: a green test can mean (a) the bug is not real, (b) the test is wrong, or (c) the test fails for the wrong reason ([PoC-Gym, arXiv 2602.04165](https://arxiv.org/html/2602.04165v1)). Preserving the finding in `## Filtered` lets the user re-elevate.

---

## 7. Step 6 — Fail-open

If the adversarial-tester-agent fails to complete, returns malformed output, its report cannot be parsed, or the orchestrator's Step 4 re-run command errors (test framework not installed, exec error): do NOT revoke any findings and do NOT add `[CONFIRMED-BY-TEST]` tags. Surface "test-gate fail-open — bug confirmation skipped for this run" under `## Caveats`. Mirrors Phase 4b validator and Phase 3 relevance-filter fail-open.

Also log a structured entry to state.md `## Errors`:

```yaml
- phase: stratify
stage: phase-4c
error: adversarial-tester-agent-failed-or-unparseable
consequence: bug-confirmation-skipped
```

---

## 8. Why Phase 4c exists

Phase 4c is the false-positive reduction stage. Independent test-execution catches findings that read as bugs but cannot be reproduced — a different signal than Phase 4b's read-only validation. The gate is non-negotiable: the user can decline, but the offer is not orchestrator's to skip.
