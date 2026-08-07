# /geniro:refactor — Phase 2: apply

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/refactor/SKILL.md`. Read on entry to Phase 2, and again on any resumption of it, including after a compaction. The spine keeps the state machine, the loop invariants, the anti-rationalization table, the budgets, §Git constraint and the tool surface — this file carries the Steps. Bare `§2.M` refs below point at this file's own sub-sections; `§ <name>` refs name a section inside the cited helper, and a `Phase 1 §1.M` / `Phase 3 §3.M` ref points at the sibling phase file (`refactor/phase-1-plan.md` for Phase 1, `refactor/phase-3-verify.md` for Phase 3).

## Contents

- 2.1 Refresh custom instructions on entry
- 2.2 Per-step execution (orchestrator-inline) — pre-loop setup, the per-step loop, the Blocked Step Protocol
- 2.3 Session-level cap + escalation gate
- 2.4 Final regression run + Evidence Block · past-learning emit on retry exit

---

## Phase 2 — apply

state.md `phase: apply`. The orchestrator executes the approved plan, one step at a time, with per-step validation. The zero-behavior-change guarantee is enforced via the per-step regression test pass.

### 2.1 Refresh custom instructions on entry

On Phase 2 entry, single `load-custom-instructions(SKILL_SLUG: refactor, LOAD_TIER: pipeline, MODE: refresh)` call (pipeline tier's load set owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`). Phase 3 inherits the Phase 2 refresh (no code-writing in Phase 3).

### 2.2 Per-step execution (orchestrator-inline)

The orchestrator executes the approved plan inline, one step at a time — no subagent spawn. Sequential per-step refactoring needs continuous state across steps, which a spawned subagent loses; running inline preserves state continuity and halves test runs via the per-step regression-skip predicate.

**Reference:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` Phase 3 — full Step Execution Protocol + Blocked Step Protocol + skip-predicate rules. Bound by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`: Read it before the first transformation and echo it — it also carries the Data Safety Rule and the test-file approval gate, and a refactor that rewrote an assertion to make a step pass yields a green suite, which is the very evidence the behavior-preservation claim rests on. The orchestrator applies this verbatim inline.

**Pre-loop setup:**

- Read the approved plan from state.md `## Plan steps` (skipping any HIGH steps the user rejected in the Phase 1 §1.6 approval gate).
- Read code-style content as echoed by the load-custom-instructions loader (cwd OR primary-worktree fallback per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`). Use it inline when applying transformations. Skip when loader echoed `No code-style.md found — skipping.`
- Resolve test commands: `<test_cmd_affected>` from CLAUDE.md's Essential Commands (per-step gate; falls back to `<test_cmd>` if undefined); `<test_cmd>` for final regression.
- Anchor: verify `pwd && git branch --show-current` once at entry; abort if either differs from baseline.

**Per-step loop** (orchestrator runs sequentially for each pending step):

For each step N in `## Plan steps` where `status: pending`:

1. **Re-read the target files** (Read tool) — capture current state of files affected by step N.
2. **Pre-condition check** (orchestrator applies skip predicate per `refactor-patterns.md` Phase 3 Step 2):
- REQUIRED if N == 1, OR `last_post_check == unset|REVERTED`, OR external edits intervened
- SKIPPED if N > 1 AND `last_post_check == PASS` (no edits intervene between sequential transformations — the previous step's post-check already validated the same baseline)
- When required: `source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Pre-check step <N>" "<test_cmd_affected>"`. On fail: stop and report (broken baseline).
3. **Apply change** (Edit tool, surgical, scope-bounded to step's `files_affected`).
4. **Post-condition check**: `source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Post-check step <N>" "<test_cmd_affected>"`. Persist result to state.md `## Plan steps` row as `last_post_check: PASS|FAIL` (atomic_state_write).
5. **Result handling**:
- **PASS**: mark `status: complete`, `attempts: <N>`, `last_post_check: PASS`. Continue to next step.
- **FAIL**: enter Blocked Step Protocol (below).

**Blocked Step Protocol** — run the three bounded attempts in `refactor-patterns.md` §Blocked Step Protocol, orchestrator-inline. On the revert after attempt 3, write `status: blocked`, `attempts: 3`, `last_post_check: REVERTED` and the blocked-rationale row to state.md, then continue to the next step — never stop the session. `last_post_check: REVERTED` is what makes the next step's pre-condition check fire (predicate (b) above); omitting it silently skips the baseline re-verification after a revert touched the tree.

A catastrophic Edit failure (filesystem error, unreadable target) is the one exit from this loop: revert the refactor's changes per SKILL.md §Git constraint with user confirmation, then escalate to the user with the failure context — retrying a transformation against a tree the tool cannot write leaves the working tree half-applied.

State.md `## Plan steps` body schema captures per-step status (per `refactor-patterns.md` Phase 2 schema): `step` / `smell` / `impact` / `risk` / `consumers` / `transformation` / `before` / `after` / `test_strategy` / `files_affected` / `rollback` / `status` / `attempts` / `last_post_check`. Orchestrator updates the row after each step via `atomic_state_write`.

### 2.3 Session-level cap + escalation gate

After execution returns, count BLOCKED-to-executed ratio (post-user-rejection denominator: approved plan steps minus user-rejected HIGH-risk steps). **Past the session-level blocked-ratio cap (`${CLAUDE_PLUGIN_ROOT}/skills/refactor/SKILL.md` §Budgets — quality-first):** stop and escalate in two steps per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering — render the run outcome to a chat message first (`**In one sentence:**` opener + a blocked-steps mini-table: step · what blocked it · retries used), then fire the lean `AskUserQuestion` header "Stuck":

- **Keep what worked and escalate the rest** — proceed to Phase 3 with blocked-steps list noted; user runs `/geniro:implement` separately for blocked items. state.md → `phase: verify` with `## Accepted Blocks` body section.
- **Revert all changes** — `git restore --source=HEAD -- <each path from git diff --name-only>` (per SKILL.md §Git constraint; with user confirmation). state.md → `phase: reverted` (terminal).
- **Force-continue (not recommended)** — proceed to Phase 3 with blocked work treated as accepted. state.md → `phase: verify`.

Do NOT proceed to Phase 3 automatically when this cap triggers. state.md marks `phase: apply-escalated` with timestamp + blocked-ratio + blocked-steps list before AUQ; transitions per user pick. The open-question render surfaces this on resume.

### 2.4 Final regression run + Evidence Block

After execution returns (or after user pick if fired), run the full test suite once (regression gate) and attach the captured run as an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. Reasoning-from-the-diff is forbidden — the captured run is the only proof the zero-behavior-change guarantee held.

If regression failed: render the regression outcome to a chat message first (which tests broke, baseline→after delta) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering, then fire the lean AUQ "Regression" — "Revert all changes" / "Show me the diff first" / "Keep changes for debugging". Default: Revert. On "Revert", `git restore --source=HEAD -- <each path from git diff --name-only>` (per SKILL.md §Git constraint) after explicit user confirmation. state.md → `phase: reverted` (terminal).

If green: state.md transitions to `phase: verify`. `## Apply Summary` body section captures executed / blocked / final-suite status.

**L2 emit on retry exit.** When Phase 2 exits AND `blocked_count ≥ 2` (≥2 plan steps reported BLOCKED per orchestrator-inline Blocked Step Protocol, regardless of whether overall ratio triggered escalation), call `emit-learning` with type=`retry_failure_sequence`, trust=`verified`, required `ext.{phase: "refactor-apply", attempts: [{round: <step-index>, failure: "<blocked-rationale from state.md ## Plan steps row>"}], resolution}`. `resolution` ∈ `{passed, escalated, aborted}` — passed when regression green AND under the blocked-ratio cap (SKILL.md §Budgets — quality-first); escalated when fired AND user picked "Keep what worked" or "Force-continue"; aborted on reverted/aborted state. Sliding-window cap per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Sliding-window caps on bookkeeping types, which owns the window size and the flip-then-append order. Single-blocked-step exits (blocked_count == 1) do NOT emit. Scope = the worktree-relative path of the largest-affected file.
