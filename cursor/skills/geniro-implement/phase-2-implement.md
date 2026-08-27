<!-- Generated from skills/implement/phase-2-implement.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# /geniro:implement — Phase 2: Implement

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/implement/SKILL.md`. Read on entry to Phase 2. The spine keeps the state machine, the loop invariants and the anti-rationalization table; this file carries the Steps. **Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/operations-reference.md` in the same action as this file** — it carries the tool surface, the state-persistence write contract, subagent model tiering, budgets, memory I/O and the modifier table, all of which bind in this phase.

## Contents

- Steps 1-6 — read spec source, TodoWrite decomposition + file-set partition, sequential todo loop (incl. the delegation rule, scope + comment discipline, the unbidden-mutation halt), end-of-phase test run, fix loop, per-criterion `verify:` commands (5.5), escalation (6)
- State.md update on phase exit · the `## Phase 2 Completion` sentinel · past-learning emit on retry exit
- Loop visualization

---

## PHASE 2: IMPLEMENT

**Advance state.md to `phase: implement` as this phase's first write**, via `atomic_state_write`. Phase 1 leaves the file at `phase: analyze` and this phase entry owns the advance. The helper overwrites rather than merges, so every later Phase 2 write re-emits whatever `phase:` it finds — the field moves only in a write that moves it, and a body section describing Phase 2 work alongside `phase: analyze` is the shape this omission leaves behind. A resume routes on this field alone: left at `analyze`, it sends the next session back into Phase 1 to re-run Step 0 and the research spawns, and the state file cannot be quoted as saying where the run picks up.

**Refresh the custom instructions on entry** (always, regardless of compaction-marker presence). Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: implement`, `LOAD_TIER: pipeline`, `MODE: refresh`, per its §Echo contract. Phase 2 is the only code-writing phase, and a resume — a compaction, or a fresh session that reads `phase: implement` from state.md — enters it with no rules in context unless this refresh runs; "still in context from Phase 1" holds only within one uninterrupted turn sequence. No project-snapshot reload here — `load_semantic` runs once at Phase 1 entry and Phase 3 does not re-load it either (`${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-1-analyze.md` §Step 6).

### Steps

1. **Read spec source** — Phase 1 resolved either a spec.md path OR wrote `## Inline Plan` to state.md body. Inline-Read the spec.md (full body) and the Codebase-Explorer "Likely-Touched Files" + "Reuse Inventory" sections.

2. **Decompose into todos via TodoWrite (Phase 2 entry — before any Edit).** Author N concrete edit-tasks via TodoWrite. Each todo = one logical unit of change, sliced vertically — one behavior paired with the test that pins it (e.g., "Add migration X + test the new column round-trips", "Add expiry check to Y controller + test expired tokens get 401") — never horizontally (all production edits first, then a trailing "add tests" todo). Tests authored in bulk after the code pass on first run and discriminate nothing; pairing each behavior with its test keeps every test anchored to a change it actually observed.

   When state.md carries `Authored-tests:` (a resolved `/geniro:debug` handoff's pre-existing reproduction tests), name each path — and its `Authored-tests-intent:` annotation when present — in the description of the todo whose slice it pins, so the pre-existing test surfaces as that todo's acceptance gate and the production-fix work cannot ship without it going GREEN.

   N typically:
   - 1-3 todos for Small scope
   - 3-10 todos for Medium scope
   - up to 15 todos for Big scope (unless already split into milestones)

   All todos initially `status: pending`. Mark the FIRST todo `in_progress` before any Edit.

   A library adopted at the Phase 1 build-vs-buy library-reuse audit (`approvals[]` category `library_adoption`) also becomes a todo here: add it through the package manager (not by editing a lockfile — lockfile writes stay hook-protected) and integrate it in place of the hand-written component.

   **Partition the todos by file set.** Name each todo's file set from the Codebase-Explorer "Likely-Touched Files" inventory and the spec, then form delegate groups: a group may bundle several todos whose file sets are pairwise disjoint from each other and from every other group's, and that together share no in-flux type, contract, or import with any other group. A todo whose file set overlaps another todo's, or that shares in-flux type/contract/import with work outside its own group, joins the single coupled group instead, edited inline. This partition is the orchestrator's own call, recorded against the todos (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §"What this category does NOT cover"). Fewer than 2 disjoint groups is the common case, not a shortfall: the single group stays inline unless it is itself a decided mechanical slice (Step 3).

3. **Work through todos sequentially — one in_progress at a time** (Loop invariant S2):
   ```
   for each todo in pending order:
       a. Mark todo in_progress via TodoWrite
       b. Make the Edit/Write changes for THAT slice ONLY
       c. JIT-load any .claude/rules/*.md whose paths: glob matches an Edit target
          (use the rule list returned by Codebase-Explorer §"Relevant Rules";
          cache rule bodies for the rest of Phase 2)
       d. Mark todo completed via TodoWrite — only once its content and this turn's
          state.md write agree the slice is finished, not merely attempted
       e. Move to next todo
   ```

   The loop runs to completion in one continuous stretch. A completed todo, a green check, and a commit are checkpoints inside it, not handoff points — mark the next todo `in_progress` and keep going in the same turn. Where a checkpoint summary helps the user follow along, write one and then take the next action in that same turn. When the last todo completes, Step 4's test run follows without returning control, and a green suite carries the run into Phase 3.

   **Delegating a group.** Step 2's partition sets the default: 2 or more disjoint groups delegate, one `general-purpose` subagent per group — model per `operations-reference.md` §Subagent model tiering (`model="sonnet"` as the ceiling, category 4: the slice is already decided, so the delegate only applies it; pass a cheaper tier for a group that is a mechanical rename or an equally determined edit, one tier for the whole batch). A single group delegates too when it is a decided mechanical slice — fully determined, no design judgment required (a rename across many call sites is the canonical case); otherwise it stays inline as the common case, the orchestrator editing directly. Delegated todos are marked `in_progress` at spawn and `completed` on diff read (invariant S2 covers the exception). Delegate every group the partition yielded, spawned in ONE assistant response, same assistant turn, NOT one per turn — separate turns serialize the spawns and the delegation buys nothing. The binding constraint is the orchestrator's own context: each returned diff is read into the one context that also holds the spec, the rules, and the remaining todos, so when returns come back large, integrate before spawning more. Spawn per the template at `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Code-delegate spawn template". Rules: a delegate edits ONLY its named file set; on return, read its diff and check every reported path against that allowlist — an out-of-bounds path is a boundary violation to surface, not to fold in — then fold the in-bounds paths into `CHANGED_FILES` and mark its todos completed; integrate multiple delegates' returns one at a time.

   A delegate that returns empty, errors, or can't finish its slice: check its allowlist for edits already made — a tool error returns no path list; a boundary stop after partial progress often leaves files changed. Surface any out-of-allowlist path as a boundary violation rather than folding it in; fold the rest into `CHANGED_FILES`, reconcile the inline work against that state, then take the rest inline. Never re-spawn the same slice, and never mark a todo `completed` while the work it names is unfinished — a delegate's todo needs a diff to read before it counts as done; an inline todo needs its own content and this turn's state.md write to actually agree the slice is finished (Step 3d).

   **Scope discipline.** Build what the todo's slice requires and nothing beyond it — no speculative abstractions, configuration options, or generalized helpers for needs the spec doesn't name. Generality added "while we're here" is scope the user never approved, and the code-quality reviewer flags it as speculative generality in Phase 3.

   **Comment discipline.** Write a comment for what stays true of the code — how to use it correctly, an invariant the types don't express, a legal header, a TODO with an issue reference — at the surrounding file's comment density. Point-in-time facts — why this approach won, what the code used to do, what was measured, what a reviewer should check — belong in the pull-request description or commit message, the non-obvious ones included, since nothing updates a comment when the code around it moves. Keep each comment to the length of the constraint it carries: a block running past a few lines is pull-request text in the wrong file, and a line restating what the code plainly does carries no constraint at all. A per-project `code-style.md` rule overrides this default where they conflict.

   **Halt on unbidden working-tree mutation.** Between Edits, if the working tree changes in ways no in-flight delegate's declared file set accounts for — an Edit/Write repeatedly fails with "file changed since read", or files/tests appear on disk — treat it as a concurrent external process, NOT a benign harness restore. Stop and fire an `AskQuestion` (header: "Tree changed", options: "Pause — let me resolve the other process" / "Move my work into a fresh worktree and continue there" / "Abort"). Committing from a working tree another process is mutating risks the commit being orphaned by an external reset.

4. **End-of-phase test run via `test-runner-agent`.** After all todos `completed`, spawn `test-runner-agent` once with the project's pre-resolved TEST_COMMAND (from CLAUDE.md "Essential Commands"), the CHANGED_FILES list, OUTPUT_PATH `<task-dir>/.tr-out.md`, and `MAX_FAILURES_REPORTED` (default per the `test-runner-agent` spawn template in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md`). Spawn `subagent_type="geniro:test-runner-agent"` under Claude Code, bare `subagent_type="test-runner-agent"` under any other host (`geniro:` is Claude Code's plugin namespace); on a spawn that fails to start or an empty (0-token) result, Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` and apply its ladder / empty-result fallback, then cache the resolved form for the session. Model per `operations-reference.md` §Subagent model tiering — OMIT `model=` so the agent's `model: sonnet` governs on the first run of the phase, and pass a cheaper tier on a fix-loop re-spawn once the first run has shown how large this suite's output actually is. Read back the OUTPUT_PATH report. Attach the report's Command / Exit code / Summary / Verdict block as Evidence per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`.

5. **In-phase fix loop on test failure.** Up to 3 retries (full pseudo-code + token-cost analysis: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling"). On each retry: read `.tr-out.md`, escalate-AUQ immediately on `INFRA_ERROR`, edit top-priority failures on `HAS_FAILURES`, re-spawn `test-runner-agent`. On `ALL_GREEN` — by EITHER path (the first-shot end-of-phase run OR a later fix-loop iteration) — run the spec's per-criterion `verify:` commands (step 5.5) BEFORE exiting to Phase 3. Retry exhaust OR an early-escalation trigger (see below) → escalate-AUQ before the 3-retry budget is spent — a loop that is not converging burns the user's tokens on the same wall.

5.5. **Run the spec's per-criterion `verify:` commands once the suite is `ALL_GREEN` (spec-driven runs only).** Fires on the suite's green exit from step 5 by whichever path reached it, so a red→green run never ships without the spec's acceptance checks. Run each section 9 (Validation) criterion's `verify:` command via the orchestrator's own Bash, once, classified on the same `{ALL_GREEN, HAS_FAILURES, INFRA_ERROR}` taxonomy — evidence, not an iterate-to-green loop. **Side-effect screen first:** refuse to auto-run any command carrying a ship / deploy / external-state-mutation verb (`git push`, `gh pr create`, `gh pr merge`, `git commit`, `deploy` / `release` / `publish`). A refused command routes into the Step 6 escalation with a plain-English reason: never executed, never silently skipped. `HAS_FAILURES` / `INFRA_ERROR` feed that same digest, so the user stays the ship decider. Where the project declares a `## Verification Surface` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-surface.md`), the criterion's ground picks the check: run the entry whose covers clause contains it, and where no entry does, report that criterion as uncovered in the Step 6 digest rather than substituting a passing command that proves something else. Inline-task runs carry no `verify:` lines and skip this step. Mechanics: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling", "Per-criterion `verify:` commands".

6. **Escalation on retry exhaust, `INFRA_ERROR`, or a not-converging signal.** Render the failure digest to chat first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering — what failed in plain English, the failing items as a `☐` checklist, why it blocks the phase (worked digest shape: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling", "Phase 2 check-failure escalation digest") — then fire the lean AUQ with the header keyed to what failed (`"Test failure"` for a failing test suite, `"Acceptance check failed"` for a failing spec `verify:` command, `"Checks failed"` when both — per the reference's failure-source table) and these options:
   - A) Hand off to /geniro:debug — state.md `phase: debug-handoff` (terminal)
   - B) Accept the failing check as a documented limitation — state.md `phase: self-review`, append `## Accepted Failures` block (label is source-neutral: the failure may be a test OR a spec `verify:` acceptance check)
   - C) Abort — state.md `phase: aborted` (terminal)

   Empty answer — re-ask through the tool first; fall back to plain text only on a repeated empty-answer loop, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions.

   **Early-escalation triggers (derived from state.md `## Errors` + `## Tool log` history — no new state surface).** Fire the same AUQ before retries exhaust when any of these holds, because each is a signal the loop has stalled rather than progressed:
   - **No forward progress between two checkpoints.** Two consecutive retry checkpoints produce no new passing tests AND no forward diff progress (the changed-files set and failing-test set are unchanged across the pair). The fix edits are not moving the suite.
   - **Retry storm — the same failure recurring.** An identical failing test name OR an identical error message / stack-trace recurs across retry attempts (compare the current test-runner output against the prior retry's failing-test list still in context). Re-hitting the same wall means the current approach cannot clear it.
   - **Cost / scope drift.** The run has exceeded its expected size by either of two sub-signals: (a) the codebase-explorer `change_scope` tier from Phase 1 (e.g. a `trivial`/`small` task now spanning many files and edit batches), OR (b) for a spec-driven run, the size the user wrote into the spec — the `budget.max_files_to_edit` / `budget.max_lines_changed` numbers — crossed by the live diff (count files and lines from the CHANGED_FILES set / `git diff --stat`, no new state surface per invariant #5). Each `budget` value is disarmed when null (= unbounded); the inline-task fallback has no `budget` block, so sub-signal (b) never arms there. Whichever sub-signal trips first fires this AUQ once — dedupe with the other so one scope-drift escalation fires per run, and the dedupe spans Phase 2 AND the Phase 3 fix loop (this trigger set is reused there) so it never double-fires across phases. The AUQ question names which bound was crossed.

   When an early trigger fires, state the plain-English reason in the AUQ question text (e.g. "the same test keeps failing across retries" / "this is turning out larger than the size you set in the spec") so the user knows why the gate opened early — never surface the raw signal name (e.g. `max_files_to_edit` / `change_scope` / `budget`).

**State.md update on phase exit.** On escalation, write `phase: phase-2-escalated`. On `aborted`, write `## Termination reason: repeated-failure: phase-2 retry-limit (<N> failing Phase 2 checks)` — source-neutral, since the escalation covers both a failing test suite AND a failing/refused spec `verify:` acceptance check. The happy path writes too, via the same `atomic_state_write` call as the block below: the helper overwrites rather than merges, so this write re-emits whatever `phase:` value it finds, unchanged — it exists only to carry the block. The `implement → self-review` transition is otherwise Phase 3 entry's alone; Step 6 option B is the one exception, advancing `phase:` directly because accepting the failure there is itself the phase-exit decision.

**Every exit's write carries a `## Phase 2 Completion` block** (happy path, escalation, aborted alike) — the assessed sentinel per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel, covering this phase's two silent-skip-prone obligations:

```
## Phase 2 Completion
instructions-refreshed: <yes|no>
verify: <ALL_GREEN|HAS_FAILURES|INFRA_ERROR|none — <reason>>
```

`instructions-refreshed` reports whether this entry's refresh (above) actually ran, not whether it should have. `verify` carries step 5.5's classification when it ran, or its own `none —` sentinel naming why it didn't (no spec `verify:` lines; suite never reached `ALL_GREEN`). The phase-body Read itself needs no field: skipping it skips this instruction too, so the block's absence in state.md — not a value inside it — is what tells the Phase 3 pre-terminal check that a resumed or compacted run never passed through this exit.

**Record a past learning on retry exit.** When Phase 2 exits AND `retry_count ≥ 2` (i.e., at least one fix-iteration happened), call `emit-learning` with `type: retry_failure_sequence`, `trust: verified`, required `ext.{phase: "phase-2-fix-loop", attempts: [...], resolution}`. Each `attempts[]` entry = `{round: N, failure: "<one-line summary>"}`. `resolution ∈ {passed, escalated, aborted}` matches the actual exit state. Sliding-window cap per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Sliding-window caps on bookkeeping types, which owns the window size and the flip-then-append order. Single-retry exits (retry_count == 1) do NOT emit. Future Phase 1 `query-learnings` calls surface this as priming context.

### Loop visualization

```
PHASE 2 (todo loop — coupled work inline, disjoint groups delegated, both running at once):

  spec.md + Codebase-Explorer report
       ↓
  [Phase 2 entry] TodoWrite: decompose into N todos
       ↓
  Partition by file set (Step 2 close)
       │
       ├─ coupled work (inline, sequential):
       │    ┌─→ todo[i].in_progress ──→ Edit/Write batch ──→ todo[i].completed ─┐
       │    │                  [i++; loop until all completed]                  │
       │    └───────────────────────────────────────────────────────────────────┘
       │
       └─ disjoint groups (delegated, spawned together in one response):
            mark in_progress at spawn, completed on diff read,
            fold in-bounds paths into CHANGED_FILES (integrate large returns before spawning more)
       ↓  (both tracks run at once — rejoin here)
  [End-of-Phase] test-runner-agent spawn (one shot)
       ↓
  [3-retry fix-loop on failures]
       ↓ (suite ALL_GREEN — by either path)
  [run spec verify: commands] (spec-driven runs only)
       ↓ (all pass)            ↘ (any fail/refused)
  Phase 3              [Step 6 escalation AUQ]
```
