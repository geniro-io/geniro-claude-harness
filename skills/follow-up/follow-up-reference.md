# Follow-Up Skill — Reference Material

This file contains templates, examples, and detailed procedures referenced by SKILL.md. The orchestrator reads specific sections at the relevant phase — not the entire file at once.

---

## Phase 1 Step 2.6: Skeptic Hypothesis-Validation Template

Spawn when either Trigger 1 (defensive-removal signal) or Trigger 2 (prior-CRITICAL/HIGH override) fires per SKILL.md Phase 1 Step 2.6. Lane scope: Small + Medium only; Trivial and Big are bypassed.

```
Agent(subagent_type="skeptic-agent", model="sonnet", prompt="""
## Task: Hypothesis Mirror-Check (Follow-Up Pre-Implementation)

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

### Mode
Hypothesis Mirror-Check (NOT Architecture Spec Validation). Apply the mirage-detection primitive in your §"Validation Dimensions" → Mirage detection block, but generalized: validate the orchestrator's claim about the codebase against codebase reality.

### Orchestrator's claim (verbatim)
[paste the 1-2 line claim — e.g. "the excludeCaseId optional parameter at beneficiary-view.service.ts:902 is unused because the multi-case length !== 1 check returns null before excludeCaseId is consulted"]

### Prior review finding (when Trigger 2 fired; omit section otherwise)
[paste the full finding body from review-feedback.md / review-findings-state.md — severity, File:lines, short-title, Cause field, Evidence block, Why-this-matters, Suggested-fix]

### Symbol(s) / branch(es) / test(s) being removed (when Trigger 1 fired; omit otherwise)
[list each item with current file:line]

### Changed-area file contents (pre-inlined from Phase 1)
[paste full content of every changed-area file]

### Required searches (MANDATORY — execute all, do not skip)
1. Grep external call sites for the symbol-to-be-removed (across the whole repo, not just changed files)
2. Read `git log -p` and `git blame` for the line being removed — look for prior-incident commit messages, ticket references (e.g. CI-247), defense-in-depth annotations
3. Read adjacent test files (sibling to the changed file, plus integration test directories) for tests whose names or assertion structure pin the to-be-removed behavior — including tests that share outcome with surviving tests but pin different cause paths
4. Verify each claim in the orchestrator's reasoning by greppable evidence — if the orchestrator claimed "X always returns null in case Y", construct a code-trace from X's body that proves or refutes Y

### Output
Write your report to `.geniro/state/follow-up/skeptic-hypothesis-<slug>.md` (slug provided by orchestrator).

**Producer-contract headers (MANDATORY):** The file MUST begin with three header lines per § Producer contract of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md`:

```
Branch: <git branch --show-current OR detached-<short-sha>>
Worktree: <git rev-parse --show-toplevel>
Timestamp: <ISO-8601 UTC>
```

These headers gate consumer-side Case A/B/C/D mismatch handling when the deletion-class Step 1.5 adversarial-tester or a post-compaction resume reads this file.

The report MUST end with a single-line verdict in this exact format:

VERDICT: ALIGNS | CONTRADICTS | NEUTRAL

Followed by per-claim sub-verdicts and evidence as bulleted findings.

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""", description="Skeptic: hypothesis mirror-check")
```

**Verdict handling (orchestrator responsibility after the skeptic returns):**
- **ALIGNS** (codebase supports the orchestrator's claim — symbol IS unused; prior CRITICAL IS stale; no test pins the to-be-removed behavior) → continue to Step 3 lane routing normally.
- **CONTRADICTS** (codebase refutes the claim — external callers found, prior CRITICAL's scenario still reachable, or adjacent test pins the behavior) → fire `AskUserQuestion` with `header: "Pre-implementation skeptic"`. Surface the contradicting evidence in the question text. Options follow the Recommended-label policy in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Recommended-label policy: "Verify scenario X first / Investigate before changing" carries `(Recommended)`; "Proceed with my interpretation anyway / Override skeptic" does NOT; third option: "Escalate to /geniro:debug to ground-truth the scenario empirically".
- **NEUTRAL** (codebase facts inconclusive) → surface the skeptic's evidence dossier inline in the Step 3 lane-routing AUQ and flag the change as "skeptic-NEUTRAL — Phase 5 Step 1.5 deletion-class override fires automatically; reviewer prompt receives adversarial framing." Continue to Step 3 lane routing.

---

## Phase 2 Step 2: Agent Delegation Templates

**Trivial** (1–2 files, obvious fix): Delegate to a single agent (same template as Small below, without Tests section). Even Trivial goes through agents — orchestrator context is too expensive for implementation.

**Small** (3–5 files, 1–2 modules): Delegate to a single agent:

```
Agent(model="sonnet", prompt="""
## Task
[describe the specific change needed]
## Pre-Inlined Context: [file contents from Phase 1]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
## UI Intent (only when UI Preview Gate ran in Phase 1 Step 4): [paste approved description verbatim; match it exactly; omit this section entirely if the gate did not run]
## Codebase Conventions: match existing patterns exactly. Before writing any new helper / component / type / config, Grep the project for an analogue first — REUSE-AS-IS or EXTEND existing code instead of creating new. If reuse requires adding a parameter or conditional to fit, prefer local duplication (Rule of Three).
## Reuse Inventory (when supplied by Phase 1): [paste REUSE_INVENTORY if present; for Trivial Fast Lane it will be omitted — rely on the verify-before-creating instruction above]
## Code-style instructions (pre-inlined from `.geniro/instructions/code-style.md`, if present)
[content of code-style.md here, or omit section if file absent]
## Tests — MANDATORY: create/update test file per changed source, follow existing patterns, run and report
## Requirements: follow CLAUDE.md, do NOT git add/commit/push, run validation, report changes and issues
After validation, append: ## Checks Report with lines: build: PASS|FAIL, lint: PASS|FAIL, test: PASS|FAIL
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")
```

**Medium** (6–8 files, up to 2 modules): Decompose into 2–3 parallel agents by module/layer, spawn in **ONE response** — all Agent() calls in the same assistant turn, NOT one per turn:

1. Group plan files by module/layer (e.g., backend vs frontend, entity+service vs DTO+hook)
2. Each agent gets its own file group — no overlap
3. Pre-inline the file contents each agent needs from Phase 1

```
# Spawn ALL agents in ONE response — multiple Agent() calls in the same assistant turn, NOT one per turn.
# Per-agent prompt sections: Task, Pre-Inlined Context, Tests — MANDATORY, Requirements (scope/CLAUDE.md/no-git/report)

Agent(model="sonnet", prompt="""
## Task — Group N: [module/layer name]
[changes for this group]
## Pre-Inlined Context: [file contents]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
## UI Intent (only when UI Preview Gate ran in Phase 1 Step 4 AND this group touches UI files): [paste approved description verbatim; match it exactly; omit this section entirely otherwise]
## Codebase Conventions: match existing patterns exactly. Before writing any new helper / component / type / config, Grep the project for an analogue first — REUSE-AS-IS or EXTEND existing code instead of creating new. If reuse requires adding a parameter or conditional to fit, prefer local duplication (Rule of Three).
## Reuse Inventory (when supplied by Phase 1): [paste REUSE_INVENTORY if present; for Trivial Fast Lane it will be omitted — rely on the verify-before-creating instruction above]
## Code-style instructions (pre-inlined from `.geniro/instructions/code-style.md`, if present)
[content of code-style.md here, or omit section if file absent]
## Tests — MANDATORY: create/update test file per changed source, follow existing patterns, run and report
## Requirements: ONLY modify [list files], follow CLAUDE.md, do NOT git add/commit/push, report changes
After validation, append: ## Checks Report with lines: build: PASS|FAIL, lint: PASS|FAIL, test: PASS|FAIL
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""", description="Implement [group N]")
# Repeat the Agent(...) block per group — all in the same assistant turn.
```

If all files are tightly coupled (same module, sequential deps), use a single agent — don't force parallelism.

---

## Phase 5 Step 1: Reviewer Agent Templates

**Small changes in Full pipeline (3–5 files):** Spawn a single reviewer-agent. Pass criteria file paths — the agent reads them itself. Do NOT pre-read criteria into orchestrator context.

```
Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
## Review: Follow-Up Change
This is a follow-up change. CI already passed — that's NOT a green light to ratify. Apply adversarial framing for this review:

**For every removed or changed line, name one scenario where the change CAUSES failure** — even if no existing test exercises that scenario. Operational anomalies count: DLQ replay, queue stale-timestamp re-emit, manual reprocessing, partial transaction commits, retries with cached state, race conditions between SCD2 writes and event publishing, edge timing windows. If you find no failure mode for a given removed/changed line, write `no failure mode identified` verbatim on its own line — that response is valid, but it MUST be explicit (silence is not a pass).

Confirmatory framings ("does it preserve known correctness?" / "tests still pass?") are insufficient here — they're the failure mode this section exists to counter. The orchestrator already ran the tests; the reviewer's job is to find what the tests do NOT exercise.

Keep review proportional to change size, but apply the adversarial framing to every diff hunk regardless of size.

CHANGED FILES (with full contents, pre-inlined): [list each file path followed by its complete content — use the file contents already in orchestrator context from Phase 1]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [paste `git diff <base>...HEAD` output where <base> resolves per skills/_shared/scope-anchor.md rule 3 (origin/HEAD's target, falling back to local main/master) — used to tag findings as [NEW] vs [PRE-EXISTING]]
CHANGE SUMMARY: [summary]

## Code-style instructions (pre-inlined from `.geniro/instructions/code-style.md`, if present — Small single-reviewer covers guidelines/conventions/design/architecture dimensions)
[content of code-style.md here, or omit section if file absent]

## Prior Review Findings (pin-protected pre-inline)

[Orchestrator: paste excerpts from `<task-dir>/planning/*/review-feedback.md` AND `<PRIMARY_ROOT>/.geniro/state/review-findings-state.md` whose `File:` matches any path in the CHANGED FILES list above. Include each prior finding's severity, File:lines, short-title, Cause field, Evidence block, Why-this-matters line, and Suggested-fix synthesis verbatim. Pin-protected = these MUST be re-read against the current diff: any diff hunk that overrides or weakens a prior finding's protection (e.g., removes the guard the prior CRITICAL flagged as load-bearing) is a finding in this review regardless of CI status. If no prior findings reference any changed file, write `No prior /review findings on changed files.` and proceed.]

## Review Criteria
Read and apply the criteria files (7, +design when UI files changed) from `${CLAUDE_PLUGIN_ROOT}/skills/review/`:
- `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/security-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/architecture-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/optimizations-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/guidelines-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/conventions-criteria.md` (self-suppresses when fewer than 3 sibling files exist for modal inference — emits zero findings rather than spawning a useless reviewer)
- `${CLAUDE_PLUGIN_ROOT}/skills/review/design-criteria.md` (conditional — when changed files include UI; see UI-file detection rule in skills/review/SKILL.md)

Review across all listed criteria files (7, or 8 when design is included for UI changes). Report findings with severity (CRITICAL/HIGH/MEDIUM) and confidence. Report ALL severity tiers — the orchestrating skill applies the MEDIUM inclusion gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`) so the user picks which MEDIUMs to include in the fix loop.

Return findings as evidence. Do NOT emit an overall verdict (CHANGES REQUIRED / APPROVED / APPROVED WITH MINOR) — the orchestrating skill synthesizes findings across all reviewers and decides.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""", description="Review: follow-up change")
```

**Medium changes (6–8 files):** Spawn 2–3 reviewer-agent instances in **ONE response** — all Agent() calls in the same assistant turn, NOT one per turn. Each agent reads its own criteria — do NOT pre-read into orchestrator context:

```
# Spawn ALL reviewers in ONE response — multiple Agent() calls in the same assistant turn, NOT one per turn:

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: Bugs & Correctness
CHANGED FILES (with full contents, pre-inlined): [list each file path followed by its complete content — from Phase 1 orchestrator context]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [paste `git diff <base>...HEAD` output where <base> resolves per skills/_shared/scope-anchor.md rule 3 (origin/HEAD's target, falling back to local main/master) — used to tag findings as [NEW] vs [PRE-EXISTING]]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed — that's NOT a green light to ratify. Apply adversarial framing for this review:

**For every removed or changed line, name one scenario where the change CAUSES failure** — even if no existing test exercises that scenario. Operational anomalies count: DLQ replay, queue stale-timestamp re-emit, manual reprocessing, partial transaction commits, retries with cached state, race conditions between SCD2 writes and event publishing, edge timing windows. If you find no failure mode for a given removed/changed line, write `no failure mode identified` verbatim on its own line — that response is valid, but it MUST be explicit (silence is not a pass).

Confirmatory framings ("does it preserve known correctness?" / "tests still pass?") are insufficient here — they're the failure mode this section exists to counter. The orchestrator already ran the tests; the reviewer's job is to find what the tests do NOT exercise.

Keep review proportional to change size, but apply the adversarial framing to every diff hunk regardless of size.
Report findings with severity (CRITICAL/HIGH/MEDIUM) and confidence. Report ALL severity tiers — the orchestrating skill applies the MEDIUM inclusion gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`) so the user picks which MEDIUMs to include in the fix loop. Return findings as evidence; do NOT emit an overall verdict — the orchestrating skill synthesizes across reviewers and decides.

## Prior Review Findings (pin-protected pre-inline)

[Orchestrator: paste excerpts from `<task-dir>/planning/*/review-feedback.md` AND `<PRIMARY_ROOT>/.geniro/state/review-findings-state.md` whose `File:` matches any path in the CHANGED FILES list above. Include each prior finding's severity, File:lines, short-title, Cause field, Evidence block, Why-this-matters line, and Suggested-fix synthesis verbatim. Pin-protected = these MUST be re-read against the current diff: any diff hunk that overrides or weakens a prior finding's protection (e.g., removes the guard the prior CRITICAL flagged as load-bearing) is a finding in this review regardless of CI status. If no prior findings reference any changed file, write `No prior /review findings on changed files.` and proceed.]

## Review Criteria
Read and apply this criteria file: `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md`
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""", description="Review: bugs")

Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: Security & Edge Cases
CHANGED FILES (with full contents, pre-inlined): [list each file path followed by its complete content — from Phase 1 orchestrator context]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [paste `git diff <base>...HEAD` output where <base> resolves per skills/_shared/scope-anchor.md rule 3 (origin/HEAD's target, falling back to local main/master) — used to tag findings as [NEW] vs [PRE-EXISTING]]
CHANGE SUMMARY: [summary]
This is a follow-up change. CI already passed — that's NOT a green light to ratify. Apply adversarial framing for this review:

**For every removed or changed line, name one scenario where the change CAUSES failure** — even if no existing test exercises that scenario. Operational anomalies count: DLQ replay, queue stale-timestamp re-emit, manual reprocessing, partial transaction commits, retries with cached state, race conditions between SCD2 writes and event publishing, edge timing windows. If you find no failure mode for a given removed/changed line, write `no failure mode identified` verbatim on its own line — that response is valid, but it MUST be explicit (silence is not a pass).

Confirmatory framings ("does it preserve known correctness?" / "tests still pass?") are insufficient here — they're the failure mode this section exists to counter. The orchestrator already ran the tests; the reviewer's job is to find what the tests do NOT exercise.

Keep review proportional to change size, but apply the adversarial framing to every diff hunk regardless of size.
Report findings with severity (CRITICAL/HIGH/MEDIUM) and confidence. Report ALL severity tiers — the orchestrating skill applies the MEDIUM inclusion gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`) so the user picks which MEDIUMs to include in the fix loop. Return findings as evidence; do NOT emit an overall verdict — the orchestrating skill synthesizes across reviewers and decides.

## Prior Review Findings (pin-protected pre-inline)

[Orchestrator: paste excerpts from `<task-dir>/planning/*/review-feedback.md` AND `<PRIMARY_ROOT>/.geniro/state/review-findings-state.md` whose `File:` matches any path in the CHANGED FILES list above. Include each prior finding's severity, File:lines, short-title, Cause field, Evidence block, Why-this-matters line, and Suggested-fix synthesis verbatim. Pin-protected = these MUST be re-read against the current diff: any diff hunk that overrides or weakens a prior finding's protection (e.g., removes the guard the prior CRITICAL flagged as load-bearing) is a finding in this review regardless of CI status. If no prior findings reference any changed file, write `No prior /review findings on changed files.` and proceed.]

## Review Criteria
Read and apply this criteria file: `${CLAUDE_PLUGIN_ROOT}/skills/review/security-criteria.md`
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""", description="Review: security")
```

Add a 3rd reviewer (architecture + tests + guidelines) only if changes touch cross-module boundaries. Reads `architecture-criteria.md`, `tests-criteria.md`, `guidelines-criteria.md` under `${CLAUDE_PLUGIN_ROOT}/skills/review/`.
Add a `sonnet` reviewer for the conventions dimension when the diff has ≥3 changed files OR any single changed file lives in a directory with ≥3 siblings of the same kind (criteria: `${CLAUDE_PLUGIN_ROOT}/skills/review/conventions-criteria.md`). Below the N≥3 threshold the modal-inference is unreliable and the criteria file suppresses findings internally — skipping the spawn saves the call.
Add a `sonnet` reviewer for the optimizations dimension when changed files include DB queries, ORM read-paths, hot loops, frontend bundle entry points, or React lists (criteria: `${CLAUDE_PLUGIN_ROOT}/skills/review/optimizations-criteria.md`). Skip otherwise — Medium-tier perf wins matter only when the diff actually touches a perf-sensitive surface.
Add an additional reviewer with `model='sonnet'` for the design dimension when changed files include UI (criteria: `${CLAUDE_PLUGIN_ROOT}/skills/review/design-criteria.md`). Skip otherwise.

**Code-style pre-inline (Medium per-dimension reviewers):** When the spawned reviewer's dimension is one of **guidelines / conventions / design / architecture**, add a `## Code-style instructions (pre-inlined from .geniro/instructions/code-style.md, if present)` section to its prompt (placed just above `## Review Criteria`) and paste the file's content. Skip the section entirely for **bugs / security / tests / optimizations** reviewers — code-style is orthogonal to their criteria. Skip the section when `.geniro/instructions/code-style.md` does not exist.

### Step 1c: Custom reviewers (all sizes that reach Phase 5)

Before completing Step 1's parallel batch, apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` to discover user-authored review dimensions in `.geniro/instructions/review-extra/`. For each spawn-spec returned, append one additional `Agent(subagent_type="reviewer-agent", model="<spec.model>", prompt=...)` call to the SAME parallel batch — same assistant response, parallel execution, NOT one per turn. The helper's `paths:` filter uses Phase 5's changed-files list (the diff being reviewed). This applies to Small AND Medium tiers — both spawn reviewer-agents and both benefit from custom dimensions. For Trivial / Small-Fast-Lane (orchestrator self-review, no reviewer-agent spawned), custom reviewers are skipped — they require the agent-based spawn path. If the helper aborts on the hard-cap error, surface its error to the user and skip Phase 5; do not proceed. Custom-reviewer findings flow through the same Step 2 aggregation, relevance-filter, and fix loop as built-in dimensions.

---

## Phase 5 Step 1.5: Adversarial Tester Template (Medium only)

Spawn the new agent AFTER the Step 1 reviewers return, BEFORE Step 2 aggregation.

```
Agent(subagent_type="adversarial-tester-agent", prompt="""
## Task: Adversarial Edge-Case Test Authoring (Follow-Up — Medium)

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

### Diff (changed files + contents)
[Pre-inline `git diff <base>...HEAD` output where <base> resolves per skills/_shared/scope-anchor.md rule 3 (origin/HEAD's target, falling back to local main/master) AND full contents of every changed source file from Phase 1]

### Shared Edge-Case Checklist (READ this file yourself at runtime — do NOT paste here)
`${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`

### Project Test Framework
- Test command (from CLAUDE.md Essential Commands): [e.g. `pnpm test`, `pytest`]
- Test-file naming convention: [project's pattern — e.g. `*.test.ts` adjacent to source]
- Exemplar test files (1-2, pre-inlined): [closest existing test files to the changed code]

### Hypothesis Seeds (optional)
[Paste CRITICAL/HIGH findings from Step 1 Medium reviewers' tests dimension, if any. Use as seeds only.]

### Output
Write your report to `.geniro/state/debug/follow-up-state-adversarial.md`. Authored test files go to the project's normal test paths. Do NOT git add/commit/push.

### F→P Invariant (NON-NEGOTIABLE)
Every test you keep MUST fail 3 times in a row on the current code. If it passes today, delete the test and mark `discarded-cannot-repro`. Flaky = discard.

### Scope
Diff-only (Medium = 6-8 files). Do NOT author tests for files outside the changed-files list. Hard cap: 10 authored tests.

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""", description="Adversarial tests: follow-up Medium")
```

**Orchestrator synthesis:**
1. Read `.geniro/state/debug/follow-up-state-adversarial.md`, extract authored test file paths.
2. Run the project's test command on each authored test individually — 3 consecutive identical failures = keep; otherwise delete.
3. For each kept test, add a CRITICAL/HIGH entry to the Step 2 aggregate (severity per agent report) tagged `origin: step-1.5-adversarial`.
4. If the agent reported hitting the 10-test cap, note overflow hypotheses in the Phase 6 ship summary under "Deferred".

**Fallback:** If the adversarial-tester-agent fails (timeout, garbage), retry ONCE. Second failure → skip Step 1.5, log "Step 1.5 skipped — adversarial-tester-agent unavailable after retry" and proceed to Step 2. Do NOT block the pipeline on infrastructure failures.

### Deletion-class variant (F→P inverts to "fail-without-the-guard")

When `Phase 5 Step 1.5 deletion-class override` fires (the diff removes a defensive guard / optional parameter / test — see SKILL.md Phase 5 Step 1.5 "Deletion-class override"), use this spawn prompt INSTEAD of the standard Adversarial Tester template above. The agent contract differs: the F→P invariant inverts. Instead of "fail on current code, pass after the change lands," the test must demonstrate that the CHANGE removes load-bearing protection — i.e., fail when the deletion is in effect, pass when the deletion is reverted.

```
Agent(subagent_type="adversarial-tester-agent", prompt="""
## Task: Fail-Without-The-Guard Test Authoring (Follow-Up — Deletion-class)

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

### Mode
Deletion-class — the diff removes a defensive guard, optional parameter, or test. Your task is to author tests that PIN the to-be-removed protection's purpose. The standard F→P invariant inverts: a kept test FAILS on the working tree as-is (with the deletion applied) and PASSES when the deletion is reverted.

### Diff (changed files + contents)
[Pre-inline `git diff <base>...HEAD` output AND full contents of every changed source file from Phase 1]

### Defensive items being removed (orchestrator-provided)
[List each removed item with current file:line, the kind (parameter / branch / test), and the orchestrator's hypothesis about why it's removable]

### Skeptic dossier (when Phase 1 Step 2.6 ran; omit otherwise)
[Pre-inline the contents of `.geniro/state/follow-up/skeptic-hypothesis-<slug>.md` — the skeptic's ALIGNS/CONTRADICTS/NEUTRAL verdict and per-claim evidence are seed hypotheses for your test authoring]

### Shared Edge-Case Checklist (READ this file yourself at runtime — do NOT paste here)
`${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md` (read the new "Test deletions in the diff" section authored as part of this same change series — applies inverse-Deletion-Test logic to your authored tests too)

### Project Test Framework
- Test command (from CLAUDE.md Essential Commands): [e.g. `pnpm test`, `pytest`]
- Test-file naming convention: [project's pattern]
- Exemplar test files (1-2, pre-inlined): [closest existing test files to the changed code]

### Output
Write your report to `.geniro/state/debug/follow-up-state-adversarial.md`. Authored test files go to the project's normal test paths. Do NOT git add/commit/push.

### Inverted F→P Invariant (NON-NEGOTIABLE)
Every test you keep MUST:
1. **Fail** when run against the current working tree (with the deletion applied) — 3 consecutive identical failures.
2. **Pass** when the deletion is reverted.

**Patch-isolated round-trip (required to verify inverted F→P):**

`git stash` would over-include — it stashes ALL working-tree changes (the production-code deletion PLUS any adjacent test edits, comment updates, or sibling-file changes from the same diff). The round-trip must isolate JUST the production-code file(s) whose guard you're verifying.

Use this procedure per production file `<P>`:

1. **Capture the deletion patch:** `git diff HEAD -- <P> > .geniro/state/follow-up/.deletion-<basename>.patch` (writes the working-tree-vs-HEAD diff to a scratch file — same .geniro/state/follow-up/ directory used by the skeptic verdict so cleanup at Phase 6 sweeps it; use a leading dot in the filename to keep it visually grouped as scratch).
2. **Revert just that file's changes:** `git restore --worktree -- <P>` (working-tree restore — does NOT touch other modified files).
3. **Run the candidate test:** project test command on the authored test file. Expected: PASS (with the guard restored, the test that pins the guard now sees the guard's protection).
4. **Re-apply the deletion patch:** `git apply .geniro/state/follow-up/.deletion-<basename>.patch` (puts the deletion back).
5. **Re-run the candidate test:** project test command. Expected: FAIL (3 consecutive identical failures — with the guard removed again, the test fails as the deletion-class adversarial-tester intends).
6. **Cleanup scratch:** `rm -f .geniro/state/follow-up/.deletion-<basename>.patch`.

If the test author added an `it()` block to an EXISTING test file (rather than creating a new untracked file), the same patch-isolated round-trip applies to the production file `<P>` only; the test file is untouched throughout.

If a candidate test passes on the current working tree, the to-be-removed code is genuinely unused — delete the candidate test and mark `discarded-already-uncovered`.

If a candidate test fails on the current working tree AND continues to fail after the deletion is reverted, your hypothesis was wrong — delete the candidate test and mark `discarded-hypothesis-invalid`.

If NO test can be constructed that satisfies the inverted F→P invariant, write a single line in your report: `no fail-without-the-guard test could be constructed — orchestrator should treat the deletion as removing invisible work`. The orchestrator will route this to Phase 5 Step 2 as a HIGH finding with `recommendation: keep the guard / restore the test`.

### Scope
Diff-only — do NOT author tests for files outside the changed-files list. Hard cap: 10 authored tests (deletion-class follow-ups are typically narrow — 1-3 deletions is the common case).

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""", description="Adversarial tests: deletion-class fail-without-the-guard")
```

**Orchestrator synthesis (deletion-class variant):**
1. Read `.geniro/state/debug/follow-up-state-adversarial.md`, extract authored test file paths AND the "no fail-without-the-guard test could be constructed" sentinel (if present).
2. For each authored test, run the project's test command on the current working tree — 3 consecutive identical failures = candidate confirmed. Then perform the patch-isolated round-trip per production file `<P>` whose guard the test pins:

   **Patch-isolated round-trip (required to verify inverted F→P):**

   `git stash` would over-include — it stashes ALL working-tree changes (the production-code deletion PLUS any adjacent test edits, comment updates, or sibling-file changes from the same diff). The round-trip must isolate JUST the production-code file(s) whose guard you're verifying.

   Use this procedure per production file `<P>`:

   1. **Capture the deletion patch:** `git diff HEAD -- <P> > .geniro/state/follow-up/.deletion-<basename>.patch` (writes the working-tree-vs-HEAD diff to a scratch file — same .geniro/state/follow-up/ directory used by the skeptic verdict so cleanup at Phase 6 sweeps it; use a leading dot in the filename to keep it visually grouped as scratch).
   2. **Revert just that file's changes:** `git restore --worktree -- <P>` (working-tree restore — does NOT touch other modified files).
   3. **Run the candidate test:** project test command on the authored test file. Expected: PASS (with the guard restored, the test that pins the guard now sees the guard's protection).
   4. **Re-apply the deletion patch:** `git apply .geniro/state/follow-up/.deletion-<basename>.patch` (puts the deletion back).
   5. **Re-run the candidate test:** project test command. Expected: FAIL (3 consecutive identical failures — with the guard removed again, the test fails as the deletion-class adversarial-tester intends).
   6. **Cleanup scratch:** `rm -f .geniro/state/follow-up/.deletion-<basename>.patch`.

   If the test author added an `it()` block to an EXISTING test file (rather than creating a new untracked file), the same patch-isolated round-trip applies to the production file `<P>` only; the test file is untouched throughout.

   Any test that fails this round-trip is deleted.
3. If the sentinel is present (no test constructable) OR if at least one kept test exists, add a HIGH finding to the Step 2 aggregate with `recommendation: keep the guard / restore the test / revert the deletion`, fold into the fix loop, and re-validate.
4. If zero kept tests AND no sentinel (all candidates self-discarded), the deletion is empirically confirmed as removing-unused-code — proceed to Step 2 normally with a log note: `Deletion-class Step 1.5 confirmed empty: 0 kept tests; deletion appears unused`.
