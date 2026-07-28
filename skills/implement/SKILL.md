---
name: implement
description: "Use when shipping a new feature, endpoint, page, or significant change against a spec.md / plan.md (from /geniro:plan) OR a raw inline task description. 3-phase autonomous loop: Analyze → Implement → Self-review-and-Ship. Optional --deep deepens two phases — a multi-angle self-review with verification escalated only where the call is contested, and a 3× fact-check of the spec's cited claims before editing (higher quality, higher cost)."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, EnterWorktree, ExitWorktree, Workflow]
argument-hint: "[task description | spec.md path | empty to resume | 'continue'] [--deep]"
---

# Implement Skill — 3-Phase Autonomous Loop

You are an autonomous executor. Consume an externally-provided spec (or inline task description), make every required code edit, run the test suite, then run a parallel self-review pass before shipping. Strategic concerns belong upstream in `/geniro:plan`. One orchestrator owns the Phase 2 edits; only a genuinely independent, self-contained slice is ever delegated.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference — it is the ancestor directory of this file containing `.claude-plugin/plugin.json` — then substitute it everywhere and export it in every Bash call. Tool and hook substitutions: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md`.

**Phases:**

1. **Analyze (Phase 1)** — workspace setup; spec source (spec.md / plan.md / DESIGN_DOC frontmatter, else inline-task fallback); custom-instruction + project-snapshot loads; the knowledge-retrieval + codebase-explorer spawn pair; past learnings; the handoff open-questions gate; a spec fact-check before any edit.
2. **Implement (Phase 2)** — TodoWrite sequential decomposition (3-15 todos, one `in_progress` at a time); per-todo Edit/Write batch, with an independent slice optionally delegated; one end-of-phase suite run via `test-runner-agent`; bounded 3-retry fix loop → escalate-AUQ.
3. **Self-review + Ship (Phase 3)** — parallel reviewer-agents (`bugs` / `security` / `architecture` / `tests` / `code-quality`) + 1 `adversarial-tester-agent` + any custom dimensions; bounded 3-round fix loop; the pre-ship minor-findings and test-quality gates; then the ship sub-step (visual verification, commit, ship-mode AUQ, learnings + snapshot writes, cleanup).

**REFERENCE.**

- **Phase bodies** — Read the matching one on entry to a phase, and again on any resumption of it, including after a compaction: `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-1-analyze.md`, `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-2-implement.md`, `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-3-ship.md`.
- **Templates and procedures** (`$ARGUMENTS`-parse table, spawn templates, fix-loop pseudo-code, ship sub-step, cleanup list): `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` — read only the section the current phase needs.
- **Deep-mode paths** (`deep-mode: true` only): `${CLAUDE_PLUGIN_ROOT}/skills/implement/deep-mode-reference.md`.

---

## State machine

State.md frontmatter `phase:` transitions (`from-phase → to-phase | trigger`):

| From | To | Trigger |
|---|---|---|
| (entry) | analyze | Phase 1 start |
| analyze | implement | spec parsed, handoffs resolved |
| analyze | (analyze) | surface failures inline; no separate escalation state |
| implement | self-review | Phase 2 todos done, tests green |
| implement | phase-2-escalated | test fix-loop exhausted / not converging |
| phase-2-escalated | debug-handoff \| self-review \| aborted | the escalation AUQ pick: escalate to debug (terminal) \| accept failures \| abort (terminal) |
| self-review | ship | happy path — review clean |
| self-review | self-review-only | "stop after review" modifier — exit before commit (terminal) |
| self-review | phase-3-escalated | review fix-loop exhausted / not converging |
| phase-3-escalated | debug-handoff \| ship \| aborted | the escalation AUQ pick: escalate to debug (terminal) \| accept findings, which appends a `## Accepted Findings` body block \| abort (terminal) |
| ship | done | committed + pushed + PR (terminal) |
| ship | ship-committed-only | "don't push" / "no push" / "commit only" modifier (terminal) |

Each `git push` / `gh pr create` / posted comment appends to `non-resumable-actions[]` as it fires.

**Terminal states**: `done`, `ship-committed-only`, `self-review-only`, `debug-handoff`, `aborted`. Every transition into a terminal state runs the transient cleanup in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Cleanup" before the terminal `phase:` write — leftover transient files in a finished task-dir resurface as recurring migration warnings on every plugin update.

**Non-terminal states**: `analyze`, `implement`, `self-review`, `ship`. **Escalation (paused) states**: `phase-2-escalated`, `phase-3-escalated` — a fix-loop exhausted and an AUQ is open. On resume the recovery re-surfaces "task was paused — last AUQ options" so the user re-picks without losing context.

**Termination reason convention.** When `phase: aborted` is reached, write one line to state.md body under `## Termination reason`: `repeated-failure: phase-N retry-limit` / `safety-denied: <rule>` / `tool-unavailable: <tool>`. The SessionStart hook re-injects this on resume.

---

## Loop invariants

The canonical loop invariants 1-7 (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply across all 3 phases. Two apply with implementation-specific bounds: invariant 4 caps reviewer-agent output at ~4000 chars per dimension (Bash output >8000 chars summarized before downstream use); invariant 5's bounded retry loops are 3 rounds in Phase 2 and 3 rounds in Phase 3, escalating early when the loop is not converging — canonical trigger list, and the once-per-run dedupe that spans both loops, in `phase-2-implement.md` §Step 6. This skill adds three invariants:

8. **Investigation reads delegated to subagents.** Phase 1 inline-Reads only the custom instructions (3 files), the project snapshot (2 files), spec.md body, and state.md. `.claude/rules/*.md` bodies, exemplar source files, past-learning entries, and prior plans are spawned out to the `knowledge-retrieval-agent` + `codebase-explorer-agent` pair (the explorer takes spec.md and returns a REUSE/EXTEND/NO-ANALOGUE inventory) and read back as condensed reports. Inline-reading the rest is the documented context-bloat regression.
9. **One todo in_progress at a time.** Phase 2's TodoWrite decomposition enforces sequential focus. Marking a second todo `in_progress` while another is open is the documented anti-pattern (Claude Code Tasks API enforces single in_progress by design; parallel sequential reasoning shows measured performance drop).
10. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool. It is the tool for ad-hoc cross-file research inside Phase 2 — the per-step "trace this flow" / "find every site calling this helper" queries the Phase 1 codebase-explorer inventory doesn't cover. Rationale + invocation contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**Turn-completion check.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check at every gate: the render is followed immediately by its lean `AskUserQuestion` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard).

**Side-effect — `## Tool log` section in state.md.** Invariants 1 and 7 motivate persisting subagent-spawn outcomes and side-effect tool calls (`git push`, `gh pr create`, file deletions) into that body section — shape in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling". Routine Read/Edit/Bash on local files need no logging: the tool_result return is sufficient.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "/geniro:implement should ask user before each Edit — safety first." | Phase 2 is the execution phase, and pre-approval lives upstream: the spec.md /geniro:plan emitted IS the pre-approval. Per-Edit AUQs defeat the spec-driven autonomy this skill is designed for. |
| "Phase 2 should fan out subagents — parallel backend/frontend agents, or one subagent per todo — to save wall-time or keep context lean." | Fan-out of COUPLED work is the documented anti-pattern: parallel agents editing tightly-interdependent code (shared contracts, types, imports) produce style drift, duplicated implementations, and contradictions lint/compile cannot catch. The sanctioned form is Phase 2's delegation rule — only an independent, self-contained slice with a disjoint file set, and only such slices in parallel; everything coupled stays with the one orchestrator, which reads every delegate's diff before accepting it. |
| "Mark all todos in_progress at start so the orchestrator can interleave work." | Forbidden by Loop invariant #9. Mark the next todo `in_progress` only after the current todo completes. |
| "Skip TodoWrite — it's overhead; the orchestrator knows the spec already." | TodoWrite gives the user real-time per-unit progress visibility; without it, Phase 2 is a black box until tests run. Not optional. |
| "Re-run tests after each file Edit to catch regressions early." | Single end-of-Phase-2 test run via `test-runner-agent`. Per-file test runs explode wall-time on slow suites and burn turns inside the runner agent (one invocation per spawn). |
| "/geniro:implement should self-fix indefinitely until reviews clean." | Phase 3 fix loop is bounded to 3 rounds. Past 3 unresolved rounds, escalate via AUQ — never silently loop. "Kick it until it passes" is a catalogued anti-pattern; round 4 entry is forbidden. |
| "Skip the ship-mode AUQ — the diff is small / this is a debug-handoff follow-up / user already approved upstream / user can `git reset` afterward." | Pushing a private feature branch with no open PR is draft-grade (auto). Everything else is commit-grade and AUQ-gated: PR creation; a push to the default, shared, or protected branch; and a feature-branch push that updates an open PR when the run was entered via a /geniro:review or /geniro:debug handoff — an 'implement the fixes' approval does not stretch to outward-facing visibility the upstream pick never consented to. The AUQ fires regardless of diff size, handoff origin, or which Phase 2 path reached Ship; none of those is a documented modifier-equivalent. The only bypass is the 4 inline modifiers (`don't push`, `draft only`, `ready-for-review`, `stop after review`) parsed from `$ARGUMENTS`. A bare "open PR"/"with PR" with no draft-vs-ready qualifier is NOT one — it fires the AUQ so the recommended draft default is surfaced — and the option labels are presented verbatim, never merged into a single "open PR" label. PR creation is irreversible visibility: CI runs trigger, reviewers get notified, the URL is shareable. |
| "Audit trail isn't needed for local /geniro:implement runs." | The state.md `## Tool log` IS the audit trail. The SessionStart hook re-injects on compaction. Without log, post-mortem on failed runs is impossible. |
| "Bypass safety hooks with --no-verify when commit-hook fails — saves time." | Hooks fail for a reason. Investigate root cause, not bypass. --no-verify usage is a CLAUDE.md-level prohibition. |
| "Spawn agents one at a time for cleaner orchestration / it's a small diff so a quick `bugs`-only review is enough / 1-2 dimensions cover the important risks / I already know this change well (I just wrote it / it's a debug-handoff follow-up), so an inline self-review summary is enough." | All Phase 3 Round 1 spawns happen in ONE assistant response (reviewer-agents + adversarial-tester) — multiple `Agent(...)` tool uses in the same message; separate turns get no concurrency. Diff size does not trim the reviewer count: `bugs` / `security` / `architecture` / `tests` / `code-quality` cover orthogonal concerns, so a `bugs`-only spawn blinds the run to security regressions, architectural drift, test gaps, and quality issues. The only sanctioned trims — codebase-explorer `change_scope: trivial`, or the `--no-adversarial` modifier — strip the adversarial slot alone; the reviewer slots stand regardless of diff size and of how the change originated (debug-handoff, review-handoff, or fresh spec). An inline self-review written from the orchestrator's own context is not a substitute: it shares the implementer's blind spots and cannot defeat anchoring bias, which is why the fresh isolated-context spawn IS the review mechanism, mandatory however well the orchestrator believes it understands the change. Same rule for the Phase 1 knowledge-retrieval + codebase-explorer pair: ONE response, two spawns, not optional — "I already explored this branch in the /geniro:review I just ran" is the continuation-resume drift that silently drops the research contract, and a continuation that skips the spawns inherits the upstream run's blind spots. |
| "Pass `model=\"sonnet\"` at every spawn site for predictable cost." | Plugin agents declare their tier in frontmatter (`model: inherit`, except the two mechanical carve-outs — `test-runner-agent` and `knowledge-retrieval-agent` — which declare `model: sonnet`), so OMIT `model=` at every spawn site and let the frontmatter govern. A hardcoded tier at the spawn site defeats the user's session-level `/model` choice for inherit-agents. The only exception is a user-authored custom reviewer whose own frontmatter declares a tier — honor that declaration. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. |
| "/geniro:implement should fire a user-approval AUQ before Phase 3 adversarial-tester spawn, mirroring /geniro:review Phase 4.3." | /geniro:review needs that AUQ because its contract is read-only reporter — spawning a test author expands its scope past contract. /geniro:implement is already authorized to mutate code (Phase 2 IS the mutation phase), so Phase 3 adversarial test authoring is symmetric to Phase 2 code authoring, NOT a new authority surface; the approved spec.md covers it. Explicit opt-out: the `--no-adversarial` modifier. |
| "Branch format requires a ticket prefix per global.md — I'll create the Linear / Jira / GitHub-Issues ticket so the slug conforms." | /geniro:implement never creates tracker artifacts. Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md` §Mutation responsibility it mutates tracker state (status transitions at Phase 1 kickoff + Phase 3 Ship completion) but creates no tickets, issues, epics, or sub-tasks. A branch-format rule demanding a ticket ID is satisfied by the no-ticket-ID sub-flow's three options — user-provided ID, placeholder slug, or cancellation — never by inventing an upstream artifact. Tracker creation is a human authoring action, not a code-execution side-effect; an agent-created ticket appears in the user's tracker without authorization and triggers downstream artifacts (notifications, dashboard rows, sprint-planning surface area) the user did not approve. |
| "/geniro:implement should inline-Read every relevant .claude/rules/, exemplar, and prior plan for thoroughness." | Loop invariant #8 bounds the orchestrator's own reads and delegates the rest. `.claude/rules/*.md` bodies and exemplar sources are JIT-loaded in Phase 2 only when an Edit target matches the rule's `paths:` glob, using the path list the codebase-explorer returned. |
| "The working tree keeps changing on its own — it's just the harness restoring my prior session, or a stale-mtime artifact." | A harness restore re-materializes work THIS session already authored; it never writes files or tests you did not create, so content this run did not author means a concurrent external process. Committing from a working tree another process is mutating risks an external reset orphaning the commit — a real near-data-loss failure mode. Stop and fire the "Workspace changed" AUQ (Phase 2 guard) instead of rationalizing the mutation away. |

---

## Budgets — quality-first framing

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Budgets — quality-first (canonical): no hard kill caps, no wall-time / tool-call / model-turn / cost ceiling. This skill's own gates:

**Quality gates (escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Fix-loop retries per phase | 3 | (Phase 2 test fix), (Phase 3 review round) | AUQ — debug-handoff / accept-failure / abort. User picks. Fires early (before 3) when the loop is not converging — early-escalation triggers in `phase-2-implement.md` §Step 6, reused by the Phase 3 loop. |

**Architecture constraint (design intent, not budget):** the parallel spawn batches are fixed sets, not a size-scaled choice — 2 subagents at Phase 1 (knowledge-retrieval + codebase-explorer), and at Phase 3 Round 1 the five reviewer dimensions + the adversarial-tester + any custom dimensions from `.geniro/instructions/review-extra/` (≤10 cap, path-filtered per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md`).

---

## ACI per-phase tool surface

| Phase | Allowed | Blocked |
|---|---|---|
| **Phase 1 (Analyze) — orchestrator** | Read / Grep / Glob / Bash (`git status`, `gh pr view`, `git worktree add`, `git checkout -b`, and the Step 0 freshness commands `git fetch` / `git merge` / `git rebase` / `git stash` / `git pull --ff-only` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`); Agent spawns for `knowledge-retrieval-agent` + `codebase-explorer-agent`, the read-only spec-claim verifiers of the spec-challenge gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md`), and one `general-purpose` web-research spawn (WebSearch + WebFetch) for the library-reuse audit; Workflow (`deep-mode: true` only). OMIT `model=` at every spawn | Edit / Write on source code; `gh pr create`; commit; Phase 3 agent types |
| **Phase 2 (Implement) inner loop** | Read / Grep / Glob / Edit / Write / Bash (incl. test runs); `test-runner-agent` spawn at end-of-phase; bounded code-delegate spawns (`general-purpose`, disjoint file sets) per the delegation rule in `phase-2-implement.md` §Step 3 | `git push`, `gh pr create`, `gh pr comment`, Phase 3 agent types |
| **Every spawned subagent** (knowledge-retrieval, codebase-explorer, test-runner, reviewer, adversarial-tester) | Exactly its own `agents/<name>.md` frontmatter `tools:` whitelist — that allowlist is the contract, not a summary of one | Agent (all are leaf agents — no nesting); git mutation; destructive Bash; Edit / Write beyond the agent's declared surface — the adversarial-tester writes test-file paths only, never production source; the read-only agents write only their own OUTPUT_PATH |
| **Phase 3 Ship sub-step** | `git commit`, `git push`, `gh pr create` — each gated by the push-grade doctrine (§Anti-rationalization, ship-mode row); `gh api` thread reply + `resolveReviewThread` (resolve-handoff only — action-gated, after the push, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md` write side) | External commits before AUQ resolution |

**Existing safety layer:** file-protection hook, git-guardrail hook, and `.geniro/` deletion guard apply across ALL phases regardless of this matrix.

---

## Handoff contract (inbound)

`/geniro:review`, `/geniro:debug`, and `/geniro:resolve` each write a handoff this skill consumes, at `<PRIMARY_ROOT>/.geniro/state/handoff/from-<producer>-<branch>.md` — `from-review-<branch>.md`, `from-debug-<branch>.md`, `from-resolve-<branch>.md`. Phase 1 reads every one that exists for the current branch, persists its body to state.md, and parses its frontmatter `open_questions[]` (canonical schema: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2).

**The gate.** Every `open_questions[]` entry carrying `status: unresolved` is resolved with the user — and the answer round-tripped back into the producer's file — BEFORE the run transitions to `phase: implement`. /geniro:implement is the consumer, and the §T2 contract forbids proceeding with Edit/Write while any `unresolved` entry remains: the producer surfaced that ambiguity precisely so it gets settled before code changes. An `open_questions: []` clears the gate; a missing key is a malformed handoff.

Procedure — rendering, the round-trip write, approvals persistence, the `/geniro:debug` authored-tests extraction, and the `/geniro:resolve` comment-resolutions stash — is in `phase-1-analyze.md` §Step 12.

---

## State persistence

**After a compaction, this file survives and the phase bodies do not — Read the phase file again on entry to (or resumption of) a phase.** Claude Code re-attaches only the first ~5,000 tokens of a skill after a summary; the Steps live in the sibling phase files precisely so they can be re-Read on demand. Working from a summary's recollection of a phase instead of its actual Steps is how a run silently skips a gate. state.md tells you which phase to resume; the phase file tells you how.

**Task directory**:

```
.geniro/planning/<task-slug>/
```

Where `<task-slug>` is derived from $ARGUMENTS / spec.md filename / git branch per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`. Created at start of Phase 1.

**State.md frontmatter:**

```yaml
---
tier: T1.5
producer: implement
schema-version: 1
branch: <git-branch>
worktree: <git-rev-parse-show-toplevel>
timestamp: <ISO-8601 UTC>
phase: <state-machine-enum>
status: in-progress
non-resumable-actions: [] # appended after each git push / gh pr create / posted comment
approvals: [] # appended after each one-time AUQ resolution
deep-mode: <true|false>   # set by the --deep flag (Phase 1 parse); missing reads as false
---
```

When `deep-mode: true`, Phase 1 (spec fact-check) and Phase 3 (self-review) run their deeper paths per `${CLAUDE_PLUGIN_ROOT}/skills/implement/deep-mode-reference.md`. Activation follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §2 — the `--deep` flag pre-resolves it, else the Step 0 depth question asks, else (auto-continue / resume paths, where that question never fires) depth is flag-only. The resolved depth is persisted once, in Phase 1.

**Write contract.** Route every state.md mutation through `atomic_state_write` — a direct `Edit` or `Write` on a canonical state path bypasses the helper and corrupts the file mid-crash; the State-helper enforcement hook hard-blocks such a direct write (exit 2). Invocation snippet: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`.

---

## Memory I/O

Which helper fires where. Step 0 workspace setup precedes every Phase 1 call in this table — its decision picks the worktree the rest of Phase 1 inspects, so a snapshot or drift check run first inspects the wrong tree.

| Phase | Calls |
|---|---|
| **Phase 1 entry** | `load-custom-instructions` (`MODE: refresh`) → `load-semantic` → the `knowledge-retrieval-agent` + `codebase-explorer-agent` spawn pair, read back from `<task-dir>/.kr-out.md` and `<task-dir>/.ce-out.md` → `query-learnings` |
| **Phase 2** | None at entry. Its only loads are the per-Edit `.claude/rules/*.md` JIT reads (cache scope: Phase 2) |
| **Phase 3** | Entry: `load-custom-instructions` (`MODE: refresh`) + `load-custom-reviewers` (round 1 only). Fix loop: `query-learnings` per round. Ship sub-step: `emit-learning`, `update-semantic`, and the `non-resumable-actions[]` write via `atomic_state_write` |
| **Any phase** | `resolve-conflicts` when the layers disagree — a soft conflict prints the notice and continues on the precedence-winning value; a hard conflict (a custom-instruction rule contradicts project reality) halts and asks. `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` |

Each helper's arguments, echo contract, and failure semantics live with the step that calls it. Two rules span all of them:

- **The custom-instruction load is mandatory in full** — 3 files (`global.md`, `implement.md`, `code-style.md`) and one observable Echo line per file, at Phase 1 entry and again at Phase 3 entry.
- **A declared memory backend redirects every learnings read.** When `memory.md` carries a `## Memory Backend` block for `learnings`, query the declared read tool instead of the file helper per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" — under `mode: replace` the local `learnings.jsonl` is never written, so the file query returns nothing and only the backend read recalls anything. Absent block → the file query is correct, unchanged.

---

## PHASE 1: ANALYZE

State.md `phase: analyze` on entry. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-1-analyze.md`** — it carries the Steps, and `implement-reference.md`'s `§PHASE 1 …` citations resolve there. Exit: `phase: implement`, which the handoff gate blocks while any `unresolved` open question remains.

---

## PHASE 2: IMPLEMENT

State.md `phase: implement` on entry — the execution phase. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-2-implement.md`** — it carries the Steps, and `implement-reference.md`'s `§PHASE 2 …` citations resolve there. Exit: `phase: self-review` on a green suite plus passing spec `verify:` checks, else `phase: phase-2-escalated`.

---

## PHASE 3: SELF-REVIEW + SHIP

State.md `phase: self-review` on entry, `phase: ship` at the Ship sub-step. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-3-ship.md`** — it carries the Steps and the Ship sub-step, and `implement-reference.md`'s `§PHASE 3 …` citations resolve there. Exit: a terminal state, reached only after the ship report and the pre-terminal check.

---

## Modifier handling (semantic, deterministic)

Inline modifiers from Phase 1 `$ARGUMENTS` override AUQ defaults deterministically. Two tables own the rows at their point of use:

- **Workspace + adversarial-tester modifiers** — `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-1-analyze.md` §Step 0b "Inline modifier overrides".
- **Ship-mode modifiers** — `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Inline modifiers from $ARGUMENTS".

When no ship-mode modifier is present, the ship-mode AUQ fires. On conflicting modifiers, last-occurrence wins; emit a soft notice naming both detected variants.

---

## Task execution entry

0. **Check for existing state.md.** Glob `<task-slug>/state.md`:
- **No state.md** → fresh run. Proceed to Phase 1.
- **state.md exists, phase in non-terminal set** → resume from `phase:` value. The SessionStart hook re-injects context.
- **state.md exists, phase in terminal set** → task complete. Surface terminal state to user; if `$ARGUMENTS` carries new task description, derive new slug, fresh run.

1. **Validate state.md if found.** Pre-flight the resume path via `validate_state_file` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md`; on failure, open the recovery AUQ (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency).

2. **TodoWrite checklist.** Add: Analyze / Implement / Self-review-and-Ship. Mark Analyze in_progress; update each as it completes.

3. **Begin Phase 1.**

---
