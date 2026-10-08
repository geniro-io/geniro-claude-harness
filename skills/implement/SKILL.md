---
name: implement
description: "Use when shipping a new feature, endpoint, page, or significant change against a spec.md / plan.md (from /geniro:plan) OR a raw inline task description. 3-phase autonomous loop: Analyze → Implement → Self-review-and-Ship."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, EnterWorktree, ExitWorktree]
argument-hint: "[task description | spec.md path | empty to resume | 'continue'] [--subagent-model <tier>]"
---

# Implement: 3-phase autonomous loop

## Contents

- Phases overview, REFERENCE, Turn boundaries, Compaction
- State machine · Loop invariants (S1-S5, inbound handoff gate) · Anti-rationalization
- PHASE 1 / PHASE 2 / PHASE 3 · Task execution entry

---

You are an autonomous executor. Consume an externally-provided spec (or inline task description), make every required code edit, run the test suite, then run a parallel self-review pass before shipping. Strategic concerns belong upstream in `/geniro:plan`. One orchestrator owns the Phase 2 edits; only a genuinely independent group is ever delegated.

**Runtime portability.** If Codex cut this file at 8,000 bytes, read it in full from its path first. `${CLAUDE_PLUGIN_ROOT}` is a placeholder Claude Code substitutes into file references, not a shell export — it reads empty in Bash under every host, so an empty probe proves nothing (`CLAUDECODE` marks Claude Code). Resolve the root from the first rung that holds: the ancestor of this file's real path (symlinks followed) containing `.claude-plugin/plugin.json`; a copy of the referenced file beside this one (the Cursor build); a plugin checkout in the workspace. The run's first Bash call prints this file's real directory and checks the rungs against it; echo that output verbatim before anything else (a resolved ladder is bookkeeping: add a degraded-run notice only for a rung that failed), then substitute the resolved root everywhere and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. A path the output does not show did not resolve. Before deciding a step cannot run here, read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` — it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not:** name what is unavailable in your first message, run every phase and gate this skill declares, never let project rules stand in for its decision gates, and take no outward-facing action (ready PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

**Phases:**

1. **Analyze (Phase 1)** — workspace setup; spec source (spec.md / plan.md / DESIGN_DOC frontmatter, else inline-task fallback); custom-instruction + project-snapshot loads; the knowledge-retrieval + codebase-explorer spawn pair; the handoff open-questions gate; a spec fact-check before any edit.
2. **Implement (Phase 2)** — sequential todo-list decomposition (1-15 todos, one `in_progress` at a time inline); a pre-change screenshot of any UI surface; disjoint-file-set todo groups delegated in parallel by default, coupled work inline; one end-of-phase suite run via `test-runner-agent`; bounded fix loop → escalate-AUQ.
3. **Self-review + Ship (Phase 3)** — parallel reviewer-agents for the `change_scope`-scaled grid plus any custom dimensions; an inline edge-case test-authoring pass; a cold `finding-verifier-agent` verdict on every CRITICAL/HIGH before the fix loop consumes it; bounded fix loop; the pre-ship minor-findings and test-quality gates; then the ship sub-step (visual verification, commit, ship-mode AUQ, learnings + snapshot writes, cleanup).

**REFERENCE.**

- **Phase bodies** — Read the matching one on entry to a phase, and again on any resumption of it, including after a compaction: `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-1-analyze.md`, `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-2-implement.md`, `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-3-ship.md`. That Read is the phase's physically-first action and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the phase files hold this skill's gates and helper call sites, so a run that starts work before the Read has removed the gates rather than merely skipped a description.
- **Operational contracts** — `${CLAUDE_PLUGIN_ROOT}/skills/implement/operations-reference.md`, read in the same action as each phase body: the per-phase tool surface, budgets, subagent model tiering and spawn rule, the state-persistence write contract, memory I/O, the `$ARGUMENTS` modifier table, and the detail behind the invariants below.
- **Templates and procedures** (`$ARGUMENTS`-parse table, spawn templates, fix-loop pseudo-code, ship sub-step, cleanup list): `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` — read only the section the current phase needs.

**Turn boundaries.** A turn ends in exactly three places: on a fired approval question, on reaching a terminal `phase:` state, or when the user asked something and is owed the answer. Everywhere else the next action follows in the same turn, with a tool call — between todos, after a green test run, after a commit, after a state write, at a phase transition, and when a subagent's result lands. A status report, a checkpoint summary, and a list of what remains are continuations, not endings: write one where it helps the user follow along, then take the next action in that same turn. A decision that needs the user is asked as a real question in the turn that raises it, its render and the question inside that one turn (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard) — a question left in prose, or announced for a later message, leaves the run waiting on an answer the user was never asked for. Reversibility is not the test: a deviation from a rule this run loaded is a gate however cheap it is to undo.

**Compaction.** The host re-attaches only an early portion of this file, so its later sections arrive missing, with a truncation marker standing in for them. Treat that marker as an instruction: in the turn you notice it, re-read this file and the running phase's body before relying on anything the truncation removed. When you compose a compaction summary, record state — what ran, what remains, what the user decided — never a directive to yourself about stopping, confirming, or awaiting direction. A resumed session reads its summary as fact and will honour it over this file, so work still to do is recorded as work still to do, not as something to ask permission for.

---

## State machine

State.md `phase:` transitions (`from → to | trigger`):

| From | To | Trigger |
|---|---|---|
| (entry) | analyze | Phase 1 start |
| analyze | implement | spec parsed, handoffs resolved |
| analyze | (analyze) | surface failures inline; no separate escalation state |
| analyze | aborted | a Phase 1 cancel pick (terminal): wrong-worktree abort, no-ticket-ID cancel, spec-challenge abort ("re-plan via /geniro:plan"), or a spec pending-decision stop |
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

**Terminal states**: `done`, `ship-committed-only`, `self-review-only`, `debug-handoff`, `aborted`. Every transition into a terminal state runs the transient cleanup in `implement-reference.md` §"Cleanup" before the terminal `phase:` write — leftover transient files in a finished task-dir resurface as migration warnings on every plugin update.

**Non-terminal states**: `analyze`, `implement`, `self-review`, `ship`. **Escalation (paused) states**: `phase-2-escalated`, `phase-3-escalated` (an AUQ is open; resume re-surfaces it). An aborted run writes a `## Termination reason` line — format and the pre-state.md cancel case in `operations-reference.md` §Loop-invariant detail.

---

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply across all 3 phases. Two apply with implementation-specific bounds: invariant 4 binds reviewer-agent output to the per-dimension report cap its own contract declares (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output cap), and Bash output past 8000 chars is summarized before downstream use — otherwise a long build/test transcript blows the phase's context budget; invariant 5's bounded retry loops are RETRY_CAP = 3 rounds in Phase 2; Phase 3's ROUND_CAP defaults to 3 rounds, or the lower limit the task input states, escalating early when the loop is not converging — canonical trigger list, and the once-per-run dedupe that spans both loops, in `phase-2-implement.md` §Step 6. This skill adds five invariants:

S1. **Investigation reads delegated to subagents.** Phase 1 inline reads only the custom instructions (pipeline load set per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`), the project snapshot (2 files), spec.md body, and state.md. `.claude/rules/*.md` bodies, exemplar source files, past-learning entries, and prior plans are spawned out to the `knowledge-retrieval-agent` + `codebase-explorer-agent` pair (the explorer takes spec.md and returns a REUSE/EXTEND/NO-ANALOGUE inventory) and read back as condensed reports. Inline-reading the rest is the documented context-bloat regression.
S2. **One todo in_progress at a time in the orchestrator's own inline editing loop.** Marking a second todo `in_progress` while another is open inline is the documented anti-pattern (parallel sequential reasoning measurably drops performance). A delegated todo is marked `in_progress` when its delegate spawns and `completed` as that delegate's diff is read, so a parallel delegate batch holds several todos `in_progress` at once.
S3. **Codebase research spawns `codebase-research-agent` — never built-in `Explore`, never a project-local agent from `.claude/agents/`.** It is the tool for Phase 2's ad-hoc cross-file research ("trace this flow", "find every site calling this helper") that the Phase 1 inventory doesn't cover, overriding the system-prompt default and any project-authored substitute. Rationale + invocation contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.
S4. **Every state.md mutation routes through the `atomic-state-write` helpers.** Advance one frontmatter field with `atomic_state_set_field`, append an entry with `atomic_state_append_section` / `atomic_state_append_list_item`, patch one span with `atomic_state_edit`, and reserve `atomic_state_write` for writing a whole file. A direct `Edit`/`Write` on a canonical state path truncates and rewrites in place, so a crash mid-write leaves a partial file. Invocation snippet: `${CLAUDE_PLUGIN_ROOT}/skills/implement/operations-reference.md` §State persistence "Write contract".
S5. **Tool surface is phase-scoped — no source writes or edits outside Phase 2's inner loop, Phase 3's bounded fix loop, Phase 3's edge-case test-authoring step (test files only — never production source), or the Ship sub-step's review-coverage re-review, and no `git commit` / `git push` / `gh pr create` outside the Phase 3 Ship sub-step.** The Ship re-review is narrow (diverged files only, `phase:` stays `ship`), and an unbuilt spec requirement caught at Ship rolls back to `phase: implement` rather than editing inline — detail in `operations-reference.md` §Loop-invariant detail. Full per-phase allow/block table, with the leaf-agent tool ceilings: `operations-reference.md` §ACI per-phase tool surface and each phase body.

**Inbound handoff gate.** A `/geniro:review` or `/geniro:debug` handoff for the current branch — `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` and its `from-debug-` sibling — gates Phase 1 exit: every `open_questions[]` entry carrying `status: unresolved` must be resolved with the user and round-tripped back into the producer's file before the run transitions to `phase: implement`. Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-1-analyze.md` §Step 12.

**Cross-phase rules** (`operations-reference.md` §Loop-invariant detail): the `## Tool log` section in state.md, the custom-instruction load, mandatory in full at every phase entry, and the declared memory backend, which redirects every learnings read.

---

## Anti-rationalization

Rows guarding a single phase live in that phase file's own anti-rationalization table; this one keeps the cross-phase rows.

| Your reasoning | Why it's wrong |
|---|---|
| "/geniro:implement should ask user before each Edit — safety first." | Phase 2 is the execution phase, and pre-approval lives upstream: the spec.md /geniro:plan emitted IS the pre-approval; per-Edit AUQs defeat the spec-driven autonomy. |
| "Pass `model=\"sonnet\"` at every spawn site for predictable cost." / "The run carries `--subagent-model opus`, so the test-runner goes to Opus too." | OMIT `model=` at judgment-grade spawns (Phase 1 researchers, Phase 3 reviewers): a tier passed there defeats the user's session-level `/model` choice on spawns that decide things. Non-judgment spawns take `sonnet` as a ceiling and `--subagent-model` only caps them — a stronger tier buys no depth on a test re-run. Rule: `operations-reference.md` §Subagent model tiering. |
| "Skip the ship-mode AUQ — the diff is small / this is a debug-handoff follow-up / user already approved upstream / user can `git reset` afterward." | A private feature branch with no open PR is draft-grade (auto); everything else — PR creation, default/shared/protected-branch pushes, a handoff-reached open-PR push — is commit-grade and AUQ-gated regardless of diff size or origin (taxonomy: `implement-reference.md` §"Commit + Push + PR" Step 4). Only the inline modifiers (`don't push`, `draft only`, `ready-for-review`, `stop after review`) or a spec `launch_config.ship_mode` pre-answer it; a bare "open PR"/"with PR" with no draft-vs-ready qualifier does not. |
| "Spawn agents one at a time for cleaner orchestration / it's a small diff so a quick `bugs`-only review is enough." | All Phase 3 Round 1 reviewer-agent spawns happen in ONE assistant response; separate turns get no concurrency. The grid scales by `change_scope` only to the tier `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-grid-scaling.md` names, announced and recorded in `spawn_dims_declared[]` before firing — a further ad-hoc cut below it is not a sanctioned trim. The edge-case test-authoring step has its own skip levers: codebase-explorer `change_scope: trivial`, or `--no-adversarial`. |
| "I already know this change well (I just wrote it / it's a debug-handoff follow-up), so an inline self-review summary is enough / the `/geniro:review` I just ran makes Phase 1's knowledge-retrieval + codebase-explorer spawns redundant." | An inline self-review shares the implementer's blind spots and cannot defeat anchoring bias — the fresh isolated-context spawn IS the review mechanism, however well the orchestrator believes it understands the change. Same for the Phase 1 pair: ONE response, spawned together; the only sanctioned skip is the knowledge-retrieval slot's mechanical store-empty gate (`phase-1-analyze.md` Step 7), evaluated fresh against the store, never against the run's own context. |
| "The task is clear from `$ARGUMENTS` — a quick `git status` and I'll pick up the phase file as I go." / "Resuming into `phase: implement` — Phase 1 already loaded the custom instructions, so Phase 2 can skip its own load." | The phase body holds the gates and the ordering: Phase 1's Step 0 decision tree runs BEFORE any inspection of the tree and needs signals an ad-hoc probe never collects, so the run takes an action no branch authorizes. Read the phase body first and echo it (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`). Phases 2 and 3 refresh the custom instructions on every entry because a resume — after a compaction or in a fresh session — carries no rules forward, and Phase 2 is the only code-writing phase. |
| "This mid-phase decision isn't one of the gates SKILL.md or a phase file enumerates — I'll ask directly in chat." | Every user-facing choice routes through the `AskUserQuestion` tool (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions owns the rule); the enumerated gates are not the complete set, and a plain-text question leaves nothing for a resumed session to restore. |

---

## PHASE 1: ANALYZE

State.md `phase: analyze` on entry. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-1-analyze.md` as this phase's first action, then echo per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`** — it carries the Steps. Step 0's workspace decision tree and the project-instruction load both live in it, so no `git` probe, branch creation, or source edit precedes the Read. Exit: `phase: implement`, which the handoff gate blocks while any `unresolved` open question remains.

---

## PHASE 2: IMPLEMENT

State.md `phase: implement` on entry — the execution phase. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-2-implement.md`** — it carries the Steps. Exit: `phase: self-review` on a green suite plus passing spec `verify:` checks, else `phase: phase-2-escalated`.

---

## PHASE 3: SELF-REVIEW + SHIP

State.md `phase: self-review` on entry, `phase: ship` at the Ship sub-step. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-3-ship.md`** — it carries the Steps and the Ship sub-step. Exit: a terminal state, reached only after the ship report and the pre-terminal check.

---

## Task execution entry

0. **Check for existing state.md.** Glob `<task-slug>/state.md`:
- **No state.md** → fresh run. Proceed to Phase 1.
- **state.md exists, phase reads as terminal** → task complete, surfaced to user (or, when `$ARGUMENTS` carries a new task description, derive a new slug and start fresh) — nothing further reads the file.
- **state.md exists, phase reads as non-terminal (or unreadable)** → validate it first via `validate_state_file` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` before trusting it for resume; on failure, open the recovery AUQ (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency). On pass, resume from `phase:` — the SessionStart hook re-injects context.

1. **Todo-list checklist.** Add: Analyze / Implement / Self-review-and-Ship. Mark Analyze in_progress; update each as it completes.

2. **Begin Phase 1.**
