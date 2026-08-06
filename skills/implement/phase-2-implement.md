# /geniro:implement — Phase 2: Implement

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/implement/SKILL.md`. Read on entry to Phase 2. The spine keeps the state machine, the loop invariants, the anti-rationalization table, and the tool surface — this file carries the Steps.

## Contents

- Steps 1-6 — read spec source, TodoWrite decomposition, sequential todo loop (incl. the delegation rule, scope + comment discipline, the unbidden-mutation halt), end-of-phase test run, fix loop, per-criterion `verify:` commands (5.5), escalation (6)
- State.md update on phase exit · past-learning emit on retry exit
- Loop visualization

---

## PHASE 2: IMPLEMENT

State.md `phase: implement` on entry.

No custom-instructions or project-snapshot refresh at Phase 2 entry — both remain in context from Phase 1.

### Steps

1. **Read spec source** — Phase 1 resolved either a spec.md path OR wrote `## Inline Plan` to state.md body. Inline-Read the spec.md (full body) and the Codebase-Explorer "Likely-Touched Files" + "Reuse Inventory" sections.

2. **Decompose into todos via TodoWrite (Phase 2 entry — before any Edit).** Author N concrete edit-tasks via TodoWrite. Each todo = one logical unit of change, sliced vertically — one behavior paired with the test that pins it (e.g., "Add migration X + test the new column round-trips", "Add expiry check to Y controller + test expired tokens get 401") — never horizontally (all production edits first, then a trailing "add tests" todo). Tests authored in bulk after the code pass on first run and discriminate nothing; pairing each behavior with its test keeps every test anchored to a change it actually observed. N typically:
   - 1-3 todos for Small scope
   - 3-10 todos for Medium scope
   - up to 15 todos for Big scope (unless already split into milestones)

   All todos initially `status: pending`. Mark the FIRST todo `in_progress` before any Edit.

   A library adopted at the Phase 1 build-vs-buy library-reuse audit (`approvals[]` category `library_adoption`) also becomes a todo here: add it through the package manager (not by editing a lockfile — lockfile writes stay hook-protected) and integrate it in place of the hand-written component.

3. **Work through todos sequentially — one in_progress at a time** (Loop invariant #9):
   ```
   for each todo in pending order:
       a. Mark todo in_progress via TodoWrite
       b. Make the Edit/Write changes for THAT slice ONLY
       c. JIT-load any .claude/rules/*.md whose paths: glob matches an Edit target
          (use the rule list returned by Codebase-Explorer §"Relevant Rules";
          cache rule bodies for the rest of Phase 2)
       d. Mark todo completed via TodoWrite
       e. Move to next todo
   ```

   **Delegating a todo (bounded).** Default is inline — the orchestrator edits directly. Delegate a todo to a `general-purpose` subagent (same worktree, `model="sonnet"` — an execution spawn per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` category 4: the slice, its file set, and its paired test are already decided, so the delegate only applies them) only when the slice is genuinely independent: its file set overlaps no other todo's, it shares no in-flux type/contract/import with concurrently-edited code, and the prompt can carry everything the delegate needs (the todo's spec excerpt, exemplar file paths, the paired test, and the relevant code-style/conventions content inlined — a subagent inherits no orchestrator context). Good candidates: a mechanical wide edit (a rename across many call sites), an isolated leaf module, boilerplate generation. Coupled slices stay inline — splitting them across agents produces the style drift and duplicated implementations that lint/compile cannot catch. Rules: the delegate edits ONLY its named file set; on return, read its diff before marking the todo completed — the orchestrator owns every line it ships; the end-of-phase suite still runs once for the whole phase. Multiple delegates may run in parallel ONLY when their file sets are pairwise disjoint; integrate their results one at a time (invariant #9 governs the todo states, not the spawns).

   **Scope discipline.** Build what the todo's slice requires and nothing beyond it — no speculative abstractions, configuration options, or generalized helpers for needs the spec doesn't name. Generality added "while we're here" is scope the user never approved, and the code-quality reviewer flags it as speculative generality in Phase 3.

   **Comment discipline.** Match the surrounding file's comment density and idiom. Write a comment only where the code cannot show the constraint itself — a non-obvious WHY, an invariant the types don't express, a legal header, a TODO with an issue reference. Never restate what a line does, narrate the change being made ("added X", "now handles Y"), or address the reviewer — those comments are noise the moment the diff merges, and the reviewer reads the diff, not annotations. A per-project `code-style.md` rule overrides this default where they conflict.

   **Halt on unbidden working-tree mutation.** Between Edits, if the working tree changes in ways this run did not make — an Edit/Write repeatedly fails with "file changed since read", or files/tests this run never authored appear on disk — treat it as a concurrent external process, NOT a benign harness restore. Stop and fire an `AskUserQuestion` (header: "Workspace changed", options: "Pause — let me resolve the other process" / "Move my work into a fresh worktree and continue there" / "Abort"). Committing from a working tree another process is mutating risks the commit being orphaned by an external reset.

4. **End-of-phase test run via `test-runner-agent`.** After all todos `completed`, spawn `test-runner-agent` once with the project's pre-resolved TEST_COMMAND (from CLAUDE.md "Essential Commands"), the CHANGED_FILES list, OUTPUT_PATH `<task-dir>/.tr-out.md`, and `MAX_FAILURES_REPORTED` (default per the `test-runner-agent` spawn template in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md`). Spawn `subagent_type="geniro:test-runner-agent"`; on `Agent type not found` or an empty (0-token) result, Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` and apply its ladder / empty-result fallback, then cache the resolved form for the session. OMIT `model=` — test-runner-agent declares `model: sonnet` (mechanical run-and-parse carve-out). Read back the OUTPUT_PATH report. Attach the report's Command / Exit code / Summary / Verdict block as Evidence per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`.

5. **In-phase fix loop on test failure.** Up to 3 retries (full pseudo-code + token-cost analysis: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling"). On each retry: read `.tr-out.md`, escalate-AUQ immediately on `INFRA_ERROR`, edit top-priority failures on `HAS_FAILURES`, re-spawn `test-runner-agent`. On `ALL_GREEN` — by EITHER path (the first-shot end-of-phase run OR a later fix-loop iteration) — run the spec's per-criterion `verify:` commands (step 5.5) BEFORE exiting to Phase 3. Retry exhaust OR an early-escalation trigger (see below) → escalate-AUQ before the 3-retry budget is spent — a loop that is not converging burns the user's tokens on the same wall.

5.5. **Run the spec's per-criterion `verify:` commands once the suite is `ALL_GREEN` (spec-driven runs only).** Fires on the suite's green exit from step 5 by whichever path reached it, so a red→green run never ships without the spec's acceptance checks. Run each section 9 (Validation) criterion's `verify:` command via the orchestrator's own Bash, once, classified on the same `{ALL_GREEN, HAS_FAILURES, INFRA_ERROR}` taxonomy — evidence, not an iterate-to-green loop. **Side-effect screen first:** refuse to auto-run any command carrying a ship / deploy / external-state-mutation verb (`git push`, `gh pr create`, `gh pr merge`, `git commit`, `deploy` / `release` / `publish`). This step runs BEFORE the ship gate, and the safety hooks block a force-push but NOT a plain `git push` / `gh pr create` — so auto-running one would ship past the gate (Loop-Invariant #3). A refused command routes into the Step 6 escalation with a plain-English reason: never executed, never silently skipped. `HAS_FAILURES` / `INFRA_ERROR` feed that same digest, so the user stays the ship decider. Where the project declares a `## Verification Surface` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-surface.md`), the criterion's ground picks the check: run the entry whose covers clause contains it, and where no entry does, report that criterion as uncovered in the Step 6 digest rather than substituting a passing command that proves something else. Inline-task runs carry no `verify:` lines and skip this step. Mechanics: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling", "Per-criterion `verify:` commands".

6. **Escalation on retry exhaust, `INFRA_ERROR`, or a not-converging signal.** Render the failure digest to chat first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering — what failed in plain English, the failing items as a `☐` checklist, why it blocks the phase (worked digest shape: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling", "Phase 2 check-failure escalation digest") — then fire the lean AUQ with the header keyed to what failed (`"Test failure"` for a failing test suite, `"Acceptance check failed"` for a failing spec `verify:` command, `"Checks failed"` when both — per the reference's failure-source table) and these options:
   - A) Hand off to /geniro:debug — state.md `phase: debug-handoff` (terminal)
   - B) Accept the failing check as a documented limitation — state.md `phase: self-review`, append `## Accepted Failures` block (label is source-neutral: the failure may be a test OR a spec `verify:` acceptance check)
   - C) Abort — state.md `phase: aborted` (terminal)

   Empty answer = upstream bug, fall back to plain text and re-ask. Do not auto-default.

   **Early-escalation triggers (derived from state.md `## Errors` + `## Tool log` history — no new state surface).** Fire the same AUQ before retries exhaust when any of these holds, because each is a signal the loop has stalled rather than progressed:
   - **No forward progress between two checkpoints.** Two consecutive retry checkpoints produce no new passing tests AND no forward diff progress (the changed-files set and failing-test set are unchanged across the pair). The fix edits are not moving the suite.
   - **Retry storm — the same failure recurring.** An identical failing test name OR an identical error message / stack-trace recurs across retry attempts (compare the current test-runner output against the prior retry's failing-test list still in context). Re-hitting the same wall means the current approach cannot clear it.
   - **Cost / scope drift.** The run has exceeded its expected size by either of two sub-signals: (a) the codebase-explorer `change_scope` tier from Phase 1 (e.g. a `trivial`/`small` task now spanning many files and edit batches), OR (b) for a spec-driven run, the size the user wrote into the spec — the `budget.max_files_to_edit` / `budget.max_lines_changed` numbers — crossed by the live diff (count files and lines from the CHANGED_FILES set / `git diff --stat`, no new state surface per invariant #5). Each `budget` value is disarmed when null (= unbounded); the inline-task fallback has no `budget` block, so sub-signal (b) never arms there. Whichever sub-signal trips first fires this AUQ once — dedupe with the other so one scope-drift escalation fires per run, and the dedupe spans Phase 2 AND the Phase 3 fix loop (this trigger set is reused there) so it never double-fires across phases. The AUQ question names which bound was crossed.

   When an early trigger fires, state the plain-English reason in the AUQ question text (e.g. "the same test keeps failing across retries" / "this is turning out larger than the size you set in the spec") so the user knows why the gate opened early — never surface the raw signal name (e.g. `max_files_to_edit` / `change_scope` / `budget`).

**State.md update on phase exit.** `phase: self-review` (happy path) or `phase: phase-2-escalated` (if escalation fires). On `aborted`, write `## Termination reason: repeated-failure: phase-2 retry-limit (<N> failing Phase 2 checks)` — source-neutral, since the escalation covers both a failing test suite AND a failing/refused spec `verify:` acceptance check.

**Record a past learning on retry exit.** When Phase 2 exits AND `retry_count ≥ 2` (i.e., at least one fix-iteration happened), call `emit-learning` with `type: retry_failure_sequence`, `trust: verified`, required `ext.{phase: "phase-2-fix-loop", attempts: [...], resolution}`. Each `attempts[]` entry = `{round: N, failure: "<one-line summary>"}`. `resolution ∈ {passed, escalated, aborted}` matches the actual exit state. Sliding-window cap per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Sliding-window caps on bookkeeping types, which owns the window size and the flip-then-append order. Single-retry exits (retry_count == 1) do NOT emit. Future Phase 1 `query-learnings` calls surface this as priming context.

### Loop visualization

```
PHASE 2 (sequential, single-context):

  spec.md + Codebase-Explorer report
       ↓
  [Phase 2 entry] TodoWrite: decompose into N todos
       ↓
  ┌─→ todo[i].in_progress ──→ Edit/Write batch ──→ todo[i].completed ─┐
  │                                                                    │
  │                          [i++; loop until all completed]           │
  │                                                                    │
  └────────────────────────────────────────────────────────────────────┘
       ↓
  [End-of-Phase] test-runner-agent spawn (one shot)
       ↓
  [3-retry fix-loop on failures]
       ↓ (suite ALL_GREEN — by either path)
  [run spec verify: commands] (spec-driven runs only)
       ↓ (all pass)            ↘ (any fail/refused)
  Phase 3              [Step 6 escalation AUQ]
```
