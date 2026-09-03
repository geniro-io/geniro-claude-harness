---
name: implement
description: "Use when shipping a new feature, endpoint, page, or significant change against a spec.md / plan.md (from /geniro:plan) OR a raw inline task description. 3-phase autonomous loop: Analyze → Implement → Self-review-and-Ship. Optional --deep deepens two phases — a multi-angle self-review with verification escalated only where the call is contested, and a 3× fact-check of the spec's cited claims before editing (higher quality, higher cost)."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, EnterWorktree, ExitWorktree, Workflow]
argument-hint: "[task description | spec.md path | empty to resume | 'continue'] [--deep] [--subagent-model <tier>]"
---

# Implement: 3-phase autonomous loop

## Contents

- Phases overview + REFERENCE
- Turn boundaries + Compaction
- State machine — `phase:` enum, terminal states, termination reasons
- Loop invariants (canonical, plus 8-10, and the inbound handoff gate)
- Anti-rationalization
- PHASE 1 / PHASE 2 / PHASE 3
- Task execution entry
- Operational contracts — tool surface, budgets, subagent tiering, state persistence, memory I/O, modifiers — in `operations-reference.md`, read at every phase entry

---

You are an autonomous executor. Consume an externally-provided spec (or inline task description), make every required code edit, run the test suite, then run a parallel self-review pass before shipping. Strategic concerns belong upstream in `/geniro:plan`. One orchestrator owns the Phase 2 edits; only a genuinely independent, self-contained group is ever delegated.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is a path placeholder Claude Code substitutes into file references, never a shell export — it reads empty in a Bash call under every host, Claude Code included, so an empty probe is no evidence of another runtime (`CLAUDECODE` in the environment marks Claude Code). Resolve the root by working these in order: the ancestor directory of this file containing `.claude-plugin/plugin.json`; a copy of the referenced file sitting beside this one (the Cursor build ships each skill's own phase and reference files there); a plugin checkout inside the workspace. Substitute the resolved root for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. **Work the rungs with a command, not a judgment:** the run's first Bash call lists the directory this file was read from and each candidate root, and its output is echoed verbatim before anything else. Read the rungs against that output — a path it does not show did not resolve, and a file it does not show cannot be read, however confidently a later step would report otherwise. A ladder that resolves is bookkeeping, not a finding: keep the echo to the probe output and the resolved root, and reserve a degraded-run notice for a rung that actually failed. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` before deciding a step cannot run here: it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not** — open your first message by naming what is unavailable, run every phase and gate this skill declares, never let the project's own rules stand in for its decision gates, and take no outward-facing action (ready-for-review PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

**Phases:**

1. **Analyze (Phase 1)** — workspace setup; spec source (spec.md / plan.md / DESIGN_DOC frontmatter, else inline-task fallback); custom-instruction + project-snapshot loads; the knowledge-retrieval + codebase-explorer spawn pair; past learnings; the handoff open-questions gate; a spec fact-check before any edit.
2. **Implement (Phase 2)** — sequential todo-list decomposition (1-15 todos, one `in_progress` at a time inline); a pre-change screenshot of any UI surface in scope, captured before the first edit as the "before" half of the ship report's evidence pair; per-todo edit batch, disjoint-file-set todo groups delegated in parallel by default, coupled work inline; one end-of-phase suite run via `test-runner-agent`; bounded 3-retry fix loop → escalate-AUQ.
3. **Self-review + Ship (Phase 3)** — parallel reviewer-agents, spawned for the `change_scope`-scaled grid (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-grid-scaling.md`) plus any custom dimensions; an inline edge-case test-authoring pass (attacker-mindset hypotheses, F→P-verified failing tests); a cold `finding-verifier-agent` verdict on every CRITICAL/HIGH before the fix loop consumes it; bounded 3-round fix loop; the pre-ship minor-findings and test-quality gates; then the ship sub-step (visual verification, commit, ship-mode AUQ, learnings + snapshot writes, cleanup).

**REFERENCE.**

- **Phase bodies** — Read the matching one on entry to a phase, and again on any resumption of it, including after a compaction: `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-1-analyze.md`, `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-2-implement.md`, `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-3-ship.md`. That Read is the phase's physically-first action and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the phase files hold this skill's gates and its helper call sites, so a run that starts work before the Read has removed the gates rather than merely skipped a description.
- **Templates and procedures** (`$ARGUMENTS`-parse table, spawn templates, fix-loop pseudo-code, ship sub-step, cleanup list): `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` — read only the section the current phase needs.
- **Operational contracts** — `${CLAUDE_PLUGIN_ROOT}/skills/implement/operations-reference.md`, read together with the phase body at every phase entry, as part of that same physically-first action: the per-phase tool surface, budgets, subagent model tiering, the state-persistence write contract, memory I/O, and the `$ARGUMENTS` modifier table. Every one of those binds in the phase being entered, so a phase that skips this read runs with no tool-surface boundary and no state-write contract.
- **Deep-mode paths** (`deep-mode: true` only): `${CLAUDE_PLUGIN_ROOT}/skills/implement/deep-mode-reference.md`.

**Turn boundaries.** A turn ends in exactly three places: on a fired approval question, on reaching a terminal `phase:` state, or when the user asked something and is owed the answer. Everywhere else the next action follows in the same turn, with a tool call — between todos, after a green test run, after a commit, after a state write, at a phase transition, and when a subagent's result lands. A status report, a checkpoint summary, and a list of what remains are continuations, not endings: write one where it helps the user follow along, then take the next action in that same turn. A decision that needs the user is asked as a real question in the turn that raises it, its render and the question inside that one turn (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard) — a question left in prose, or announced for a later message, leaves the run waiting on an answer the user was never asked for. Reversibility is not the test: a deviation from a rule this run loaded is a gate however cheap it is to undo.

**Compaction.** The host re-attaches only the first ~20,000 characters of this file, so its later sections arrive missing, with a truncation marker standing in for them. Treat that marker as an instruction: in the turn you notice it, re-read this file and the running phase's body before relying on anything the truncation removed. When you compose a compaction summary, record state — what ran, what remains, what the user decided — never a directive to yourself about stopping, confirming, or awaiting direction. A resumed session reads its summary as fact and will honour it over this file, so work still to do is recorded as work still to do, not as something to ask permission for.

---

## State machine

State.md frontmatter `phase:` transitions (`from-phase → to-phase | trigger`):

| From | To | Trigger |
|---|---|---|
| (entry) | analyze | Phase 1 start |
| analyze | implement | spec parsed, handoffs resolved |
| analyze | (analyze) | surface failures inline; no separate escalation state |
| analyze | aborted | a Phase 1 cancel pick (terminal): the worktree-mismatch "Abort — I'm in the wrong place", the no-ticket-ID "Cancel — I'll get a ticket first", or the spec-challenge "Abort — re-plan via /geniro:plan" |
| implement | self-review | Phase 2 todos done, tests green |
| implement | phase-2-escalated | test fix-loop exhausted / not converging |
| phase-2-escalated | debug-handoff \| self-review \| aborted | the escalation AUQ pick: escalate to debug (terminal) \| accept failures \| abort (terminal) |
| self-review | ship | happy path — review clean |
| self-review | self-review-only | "stop after review" modifier — exit before commit (terminal) |
| self-review | implement | Phase 3 fix-loop re-spawn of `test-runner-agent` comes back non-green — rollback into the Phase 2 retry loop (`phase-3-ship.md` Step 3, `implement-reference.md` §"Phase 3: Bounded fix loop") |
| self-review | phase-3-escalated | review fix-loop exhausted / not converging |
| phase-3-escalated | debug-handoff \| ship \| aborted | the escalation AUQ pick: escalate to debug (terminal) \| accept findings, which appends a `## Accepted Findings` body block \| abort (terminal) |
| ship | done | committed + pushed + PR (terminal) |
| ship | ship-committed-only | "don't push" / "no push" / "commit only" modifier (terminal) |

Each `git push` / `gh pr create` / posted comment appends to `non-resumable-actions[]` as it fires.

**Terminal states**: `done`, `ship-committed-only`, `self-review-only`, `debug-handoff`, `aborted`. Every transition into a terminal state runs the transient cleanup in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Cleanup" before the terminal `phase:` write — leftover transient files in a finished task-dir resurface as recurring migration warnings on every plugin update.

**Non-terminal states**: `analyze`, `implement`, `self-review`, `ship`. **Escalation (paused) states**: `phase-2-escalated`, `phase-3-escalated` — a fix-loop exhausted and an AUQ is open. On resume the recovery re-surfaces "task was paused — your previous options:" so the user re-picks without losing context.

**Termination reason convention.** When `phase: aborted` is reached, write one line to state.md body under `## Termination reason`: `repeated-failure: phase-N retry-limit` / `safety-denied: <rule>` / `tool-unavailable: <tool>` / `user-cancelled: <wrong-worktree | no-ticket-id | spec-replan>` for the three Phase 1 cancel picks above. The SessionStart hook re-injects this on resume. A Step 0 cancel that fires before Phase 1 Step 4 created the task directory has no state.md to write — say so in plain English and exit; nothing was mutated and there is nothing to resume.

---

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply across all 3 phases. Two apply with implementation-specific bounds: invariant 4 binds reviewer-agent output to the per-dimension report cap its own contract declares (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output cap), and Bash output past 8000 chars is summarized before downstream use — otherwise a long build/test transcript blows the phase's context budget; invariant 5's bounded retry loops are 3 rounds in Phase 2 and 3 rounds in Phase 3, escalating early when the loop is not converging — canonical trigger list, and the once-per-run dedupe that spans both loops, in `phase-2-implement.md` §Step 6. This skill adds five invariants:

S1. **Investigation reads delegated to subagents.** Phase 1 inline reads only the custom instructions (the pipeline load set per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`), the project snapshot (2 files), spec.md body, and state.md. `.claude/rules/*.md` bodies, exemplar source files, past-learning entries, and prior plans are spawned out to the `knowledge-retrieval-agent` + `codebase-explorer-agent` pair (the explorer takes spec.md and returns a REUSE/EXTEND/NO-ANALOGUE inventory) and read back as condensed reports. Inline-reading the rest is the documented context-bloat regression.
S2. **One todo in_progress at a time in the orchestrator's own inline editing loop.** Marking a second todo `in_progress` while another is open inline is the documented anti-pattern (parallel sequential reasoning shows measured performance drop). A delegated todo is marked `in_progress` when its delegate spawns and `completed` as that delegate's diff is read, so a parallel delegate batch legitimately holds several todos `in_progress` at once without violating this invariant.
S3. **Codebase research spawns `codebase-research-agent` — never built-in `Explore`, never a project-local agent from `.claude/agents/`.** Overrides the system-prompt agent list's default codebase-research tool and any project-authored substitute. It is the tool for ad-hoc cross-file research inside Phase 2 — the per-step "trace this flow" / "find every site calling this helper" queries the Phase 1 codebase-explorer inventory doesn't cover. Rationale + invocation contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.
S4. **Every state.md mutation routes through the `atomic-state-write` helpers.** Advance one frontmatter field with `atomic_state_set_field`, append an entry with `atomic_state_append_section` / `atomic_state_append_list_item`, patch one span with `atomic_state_edit`, and reserve `atomic_state_write` for writing a whole file. A direct `Edit`/`Write` on a canonical state path bypasses the helper and corrupts the file mid-crash; the State-helper enforcement hook hard-blocks it (exit 2). Invocation snippet: `${CLAUDE_PLUGIN_ROOT}/skills/implement/operations-reference.md` §State persistence "Write contract".
S5. **Tool surface is phase-scoped — no source writes or edits outside Phase 2's inner loop, Phase 3's bounded fix loop, Phase 3's edge-case test-authoring step (test files only — never production source), or the Ship sub-step's review-coverage re-review, and no `git commit` / `git push` / `gh pr create` outside the Phase 3 Ship sub-step.** The Ship exception is narrow: when its review-coverage guard finds staged files the fix loop's last round never reviewed, editing reopens once for those diverged files only, fixes go through the fix loop's existing inline-fix rule, it counts against neither the 3-round cap nor a new one, and `phase:` stays `ship` throughout. Full per-phase allow/block table, including the leaf-agent tool ceilings: §ACI per-phase tool surface above, and each phase's own body file at phase entry.

**Inbound handoff gate.** A `/geniro:review` or `/geniro:debug` handoff for the current branch — `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` and its `from-debug-` sibling — gates Phase 1 exit: every `open_questions[]` entry carrying `status: unresolved` must be resolved with the user and round-tripped back into the producer's file before the run transitions to `phase: implement`. Full contract, schema, and procedure: `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-1-analyze.md` §Step 12.

**Side-effect — `## Tool log` section in state.md.** Invariants 1 and 7 motivate persisting subagent-spawn outcomes and side-effect tool calls (`git push`, `gh pr create`, file deletions) into that body section — shape in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling". Routine Read/Edit/Bash on local files need no logging: the tool_result return is sufficient.

**Custom-instruction load is mandatory in full at every phase entry.** The pipeline load set per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Procedure, with one observable Echo line per file, fires at Phase 1 entry, again at Phase 2 entry, and again at Phase 3 entry.

**A declared memory backend redirects every learnings read.** When `memory.md` carries a `## Memory Backend` block for `learnings`, query the declared read tool instead of the file helper per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" — under `mode: replace` the local `learnings.jsonl` is never written, so the file query returns nothing and only the backend read recalls anything. Absent block → the file query is correct, unchanged.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "/geniro:implement should ask user before each Edit — safety first." | Phase 2 is the execution phase, and pre-approval lives upstream: the spec.md /geniro:plan emitted IS the pre-approval. Per-Edit AUQs defeat the spec-driven autonomy this skill is designed for. |
| "Phase 2 should fan out subagents — parallel backend/frontend agents, or one subagent per todo — to save wall-time or keep context lean." | Fan-out of COUPLED work is the documented anti-pattern: parallel agents editing tightly-interdependent code (shared contracts, types, imports) produce style drift, duplicated implementations, and contradictions lint/compile cannot catch. The sanctioned form is the partition the orchestrator computes — todo groups with disjoint file sets and no shared in-flux type, contract, or import, delegated in parallel — never a split by role or by todo count; everything coupled stays with the one orchestrator, which reads every delegate's diff before accepting it. |
| "Skip TodoWrite — it's overhead, the orchestrator knows the spec already." / "Mark all todos in_progress at start so the orchestrator can interleave work." | TodoWrite gives the user real-time per-unit progress visibility; without it Phase 2 is a black box until tests run, so it is not optional. Marking the whole list `in_progress` destroys that visibility just as thoroughly — it reports everything as started and nothing as finished. Loop invariant S2 binds in the orchestrator's own inline loop: mark the next todo `in_progress` only after the current one completes. |
| "Pass `model=\"sonnet\"` at every spawn site for predictable cost." / "The run carries `--subagent-model opus`, so the test-runner goes to Opus too." | Plugin agents declare their tier in frontmatter (`model: inherit`, except the two mechanical carve-outs — `test-runner-agent` and `knowledge-retrieval-agent` — which declare `model: sonnet`), so OMIT `model=` at their spawn sites and let the frontmatter govern. A tier passed on a Phase 1 researcher or a Phase 3 reviewer defeats the user's session-level `/model` choice — those spawns decide things. Non-judgment sites are the opposite case and go the other way: `sonnet` is their ceiling, the orchestrator sizes below it when the workload is visibly smaller, and `--subagent-model` caps them rather than raising them — a flag naming a stronger tier buys deeper judgment, and a test re-run has none to deepen. `${CLAUDE_PLUGIN_ROOT}/skills/implement/operations-reference.md` §Subagent model tiering; band and rationale in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Sizing a non-judgment spawn. |
| "Re-run tests after each file Edit to catch regressions early." | Single end-of-Phase-2 test run via `test-runner-agent`. Per-file test runs explode wall-time on slow suites and burn turns inside the runner agent (one invocation per spawn). |
| "/geniro:implement should self-fix indefinitely until reviews clean." | Phase 3 fix loop is bounded per §Loop invariants (invariant 5). Past the round cap, escalate via AUQ — never silently loop. "Kick it until it passes" is a catalogued anti-pattern; entry past the cap is forbidden. |
| "Skip the ship-mode AUQ — the diff is small / this is a debug-handoff follow-up / user already approved upstream / user can `git reset` afterward." | Pushing a private feature branch with no open PR is draft-grade (auto); everything else is commit-grade and AUQ-gated — full taxonomy (PR creation, default/shared/protected-branch pushes, the handoff-reached open-PR case) in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Commit + Push + PR" Step 4. The AUQ fires regardless of diff size, handoff origin, or which Phase 2 path reached Ship. The only bypass is the 4 inline modifiers (`don't push`, `draft only`, `ready-for-review`, `stop after review`) parsed from `$ARGUMENTS` — a bare "open PR"/"with PR" with no draft-vs-ready qualifier is NOT one. |
| "Spawn agents one at a time for cleaner orchestration / it's a small diff so a quick `bugs`-only review is enough / 1-2 dimensions cover the important risks." | All Phase 3 Round 1 reviewer-agent spawns happen in ONE assistant response — multiple spawns in the same message; separate turns get no concurrency. The reviewer grid DOES scale by `change_scope`, but only to the tier `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-grid-scaling.md` names — announced to the user and recorded in `spawn_dims_declared[]` before firing. A further ad-hoc cut below that tier's set (a `bugs`-only spawn on a `medium` diff, or any unannounced narrowing) is not a sanctioned trim. The edge-case test-authoring step has its own separate skip levers — codebase-explorer `change_scope: trivial`, or the `--no-adversarial` modifier. |
| "I already know this change well (I just wrote it / it's a debug-handoff follow-up), so an inline self-review summary is enough / I already explored this branch in the `/geniro:review` I just ran, so Phase 1's knowledge-retrieval + codebase-explorer spawns are redundant." | An inline self-review written from the orchestrator's own context is not a substitute: it shares the implementer's blind spots and cannot defeat anchoring bias, which is why the fresh isolated-context spawn IS the review mechanism, mandatory however well the orchestrator believes it understands the change. Same rule for the Phase 1 knowledge-retrieval + codebase-explorer pair: ONE response, spawned together, not optional — the only sanctioned skip is the knowledge-retrieval slot's mechanical store-empty gate (`phase-1-analyze.md` Step 7), which every run evaluates fresh against the store, never against its own context. |
| "/geniro:implement should fire a user-approval AUQ before Phase 3's edge-case test-authoring step, mirroring /geniro:review Phase 4.3." | /geniro:review needs that AUQ because its contract is read-only reporter — authoring a test expands its scope past contract. /geniro:implement is already authorized to mutate code (Phase 2 IS the mutation phase), so Phase 3 edge-case test authoring is symmetric to Phase 2 code authoring, NOT a new authority surface; the approved spec.md covers it. Explicit opt-out: the `--no-adversarial` modifier. |
| "Branch format requires a ticket prefix per global.md — I'll create the Linear / Jira / GitHub-Issues ticket so the slug conforms." | /geniro:implement never creates tracker artifacts. Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md` §Mutation responsibility it mutates tracker state (status transitions at Phase 1 kickoff + Phase 3 Ship completion) but creates no tickets, issues, epics, or sub-tasks. A branch-format rule demanding a ticket ID is satisfied by the no-ticket-ID sub-flow's three options — user-provided ID, placeholder slug, or cancellation — never by inventing an upstream artifact. Tracker creation is a human authoring action, not a code-execution side-effect — an agent-created ticket triggers downstream artifacts (notifications, dashboard rows, sprint-planning surface area) the user never approved. |
| "/geniro:implement should inline read every relevant .claude/rules/, exemplar, and prior plan for thoroughness." | Loop invariant S1 bounds the orchestrator's own reads and delegates the rest. `.claude/rules/*.md` bodies and exemplar sources are JIT-loaded in Phase 2 only when an Edit target matches the rule's `paths:` glob, using the path list the codebase-explorer returned. |
| "The working tree keeps changing on its own — it's just the harness restoring my prior session, or a stale-mtime artifact." | A harness restore re-materializes work THIS session already authored; it never writes files or tests you did not create. A change inside an in-flight delegate's declared file set is this run's own work, not a halt signal; one landing outside it is a concurrent external process. Committing from a working tree another process is mutating risks an external reset orphaning the commit — a real near-data-loss failure mode. Stop and fire the "Tree changed" AUQ (Phase 2 guard) instead of rationalizing the mutation away. |
| "The task is clear from `$ARGUMENTS` — I'll get oriented with a quick `git status` and start, and pick up the phase file as I go." / "Resuming into `phase: implement` — Phase 1 already loaded the custom instructions, so Phase 2 can skip its own load." | Phase 1's body is where Step 0's workspace decision tree and the project-instruction load live, and both are ordered BEFORE any inspection of the tree. Starting with an ad-hoc probe collects none of Step 0a's signals (`CURRENT_BRANCH`, `IN_WORKTREE`, `PROTECTED_BRANCH`), so the decision tree cannot be evaluated even in principle, and the run silently takes an action no branch of that tree authorizes. Read the phase body first and echo it, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`. The same drift resurfaces at Phase 2 entry on a resume: that Phase 1 load lived in a context the resume does not carry forward, whether the resume followed a compaction or a fresh session reading `phase: implement` from state.md. Phase 2 is the only code-writing phase, so entering it without current project rules means the edits it makes go unreviewed against them until Phase 3 — too late to shape how they were written. `phase-2-implement.md` refreshes the custom instructions on every entry for exactly this reason. |
| "This mid-phase decision isn't one of the gates SKILL.md or a phase file enumerates — I'll ask directly in chat." | Every user-facing choice in this skill routes through the `AskUserQuestion` tool (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions owns the rule); this skill's gates live across the Steps in `phase-1-analyze.md`, `phase-2-implement.md`, and `phase-3-ship.md`, and that set is not the complete one — a plain-text question leaves nothing for a resumed session to restore. |

---

## PHASE 1: ANALYZE

State.md `phase: analyze` on entry. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-1-analyze.md` as this phase's first action, then echo per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`** — it carries the Steps, and `implement-reference.md`'s `§PHASE 1 …` citations resolve there. Step 0's workspace decision tree and the project-instruction load both live in it, so no `git` probe, branch creation, or source edit precedes the Read. Exit: `phase: implement`, which the handoff gate blocks while any `unresolved` open question remains.

---

## PHASE 2: IMPLEMENT

State.md `phase: implement` on entry — the execution phase. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-2-implement.md`** — it carries the Steps, and `implement-reference.md`'s `§PHASE 2 …` citations resolve there. Exit: `phase: self-review` on a green suite plus passing spec `verify:` checks, else `phase: phase-2-escalated`.

---

## PHASE 3: SELF-REVIEW + SHIP

State.md `phase: self-review` on entry, `phase: ship` at the Ship sub-step. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-3-ship.md`** — it carries the Steps and the Ship sub-step, and `implement-reference.md`'s `§PHASE 3 …` citations resolve there. Exit: a terminal state, reached only after the ship report and the pre-terminal check.

---

## Task execution entry

0. **Check for existing state.md.** Glob `<task-slug>/state.md`:
- **No state.md** → fresh run. Proceed to Phase 1.
- **state.md exists, phase in non-terminal set** → resume from `phase:` value. The SessionStart hook re-injects context.
- **state.md exists, phase in terminal set** → task complete. Surface terminal state to user; if `$ARGUMENTS` carries new task description, derive new slug, fresh run.

1. **Validate state.md if found.** Pre-flight the resume path via `validate_state_file` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md`; on failure, open the recovery AUQ (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency).

2. **Todo-list checklist.** Add: Analyze / Implement / Self-review-and-Ship. Mark Analyze in_progress; update each as it completes.

3. **Begin Phase 1.**

---
