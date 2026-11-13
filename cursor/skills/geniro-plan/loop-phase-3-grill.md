<!-- Generated from skills/plan/loop-phase-3-grill.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 3 — Grill (decision-tree clarification)

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

## Contents

- 3.1 Build the design tree
- 3.2 Question shape — message-first rounds
- 3.3 Persistence
- 3.4 Checkpoint gate, exit gate, and termination

State.md `phase: clarify` during this phase.

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the frontier in a round (§3.2 sets its size): number each question and give your recommended answer, then wait for the answers before the next round.

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

### 3.1 Build the design tree

Seeds: Phase 1 findings, past learnings, code-style rules. Root = the feature; branches = its design axes.

**Facts versus decisions.** Finding _facts_ is your job, never the user's: don't ask the user for anything you could look up yourself. A single-file fact is one Read; a multi-file question spawns `codebase-research-agent` (invariant S1) as **light (mid)** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Cost classes in the background (Shape A of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md`). Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait.

**Code and glossary.** When the user states how something works, check whether the code agrees. A contradiction becomes a question in the next round: "Your code cancels entire Orders, but you just said partial cancellation is possible. Which is right?" So does a term that conflicts with the project glossary (CLAUDE.md's Domain Context section): "Your glossary defines 'cancellation' as X, but you seem to mean Y. Which is it?" For a vague or overloaded term, propose a precise canonical term — "You're saying 'account': do you mean the Customer or the User? Those are different things." — and use it for the rest of the run. When a concept boundary stays vague after a direct question, re-ask through a concrete edge-case scenario. Once a terminology question resolves, emit an L2 learning per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` (`type: convention`, `trust: verified`, tags including `glossary` plus the task-area terms, summary `<term> means <meaning>`) with the caller contract's echo. Phase 3 never edits source.

**Scope edge.** One branch asks whether the full scope is the right scope: the part carrying most of the value, a strict subset, an existing mechanism or configuration that already meets the need. A reduced scope feeds Phase 4 §4.1. When the honest answer is "build nothing", confirm with the user, run the §9.2 transient cleanup (`clean_task_transients`, `loop-phase-9-handoff.md`), walk `loop-definition-of-done.md` §Abort-path subset, write the terminal `phase: aborted` with a `## Termination reason`, and report it as a decision the planning reached, not a cancelled run.

**Grill early during the explore wait.** While the §1.2 explore agents run in the background, ask only the code-independent branches (past learnings, code-style rules, generic scope edges) — Shape A of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md` — and hold the rest until the §1.5 drain. Persist early answers to `approvals[]`; never re-ask them.

**Seed from the conversation.** List a decision already settled this session for confirmation instead of asking it; a correction reopens it.

### 3.2 Question shape — message-first rounds

Render the round to a chat message first, framed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers, then fire the lean question; regenerate each round from the live tree. Each question's first option is your recommended answer, marked `(Recommended)`. Four rules shape a round:

1. Each question names what it depends on: the settled decision it hangs off, or "nothing".
2. A whole-shape question — confirming a prototype or preview, the overall scope, or the main decision others hang off — is asked alone in its round; the decisions drawn inside it wait for its answer.
3. A round is one question call of at most 4 questions — a ceiling, not a target. When the frontier holds more, ask the highest-leverage ones now and the rest next round; never chain calls to add questions to a round. The only extra calls in a round are a §Cap-extension follow-up (below) for one question's overflow options, or the owner follow-up after a "Someone else decides this" pick.
4. The checkpoint question and the exit gate (§3.4) are each asked alone, never in a call with an open grill question; the exit gate only once the frontier is empty.

Options end with "Skip — proceed with stated assumption" when applicable and include "Someone else decides this" when the decision may not be the user's (policy, budget, another team); past the tool's option cap, follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Cap-extension — never drop Skip. A "Someone else decides this" pick opens the owner follow-up and records `picked: "pending: <owner>"` (quoted — an unquoted colon-space breaks the YAML). A project that wants one question at a time says so in a loaded custom instruction; each round is then the single highest-leverage frontier question. Literal example, including the owner follow-up: `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2.

### 3.3 Persistence

Append each answer to state.md `approvals[]` via `atomic_state_append_list_item` (category `clarify_<dim>`, e.g. `clarify_auth_method`; `asked_in_phase: clarify`; entry shape in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1) before rendering the next round; append a checkpoint or exit pick the same way, category `grill_checkpoint`, before acting on it; on a compaction-resume, re-read `approvals[]` and skip answered questions.

### 3.4 Checkpoint gate, exit gate, and termination

There is no fixed question cap. Checkpoint on whichever comes first: a full branch resolves, 2 rounds have run since the last checkpoint, or the answers signal convergence — replies shrinking to a word, "just pick one", a question waved away. Convergence is the trigger a fixed cadence cannot see: a disengaged user answers as fast as ever, and the cadence reads that speed as progress. The checkpoint escalates to the user; it does not abort. It fires only while open branches remain: an empty frontier goes to termination and the exit gate.

**Artifact** — fire the before-gate update for this site (call-site table in `loop-artifact-call-sites.md`) before the checkpoint and exit questions below.

At a checkpoint, render a running summary, then ask one lean question: **Keep grilling** (Recommended) / **Wrap up now** — remaining open branches become stated assumptions.

**Termination** fires on a Wrap up pick or an empty frontier. Render a closing summary — resolved decisions, deferred work, unaddressed risks — that feeds Phase 4 and seeds Phase 5. When any branch closed `pending: <owner>`, also write `<task-dir>/questionnaire.md` via `atomic_state_write`, using the template in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2.

**The exit is gated.** The grill is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding. When the tree exhausts on its own, not after a Wrap up pick, render the closing summary, then ask one lean question: **Start building** (Recommended) / **Keep grilling deeper** / **Keep grilling on an area I name**. "Nothing left to ask" is the model's read of a tree it built, so keep-grilling stays live on an empty frontier; the gate re-fires at every termination. Checkpoint and exit templates, deeper-pass angles, named-area flow: `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2b.

**Every branch that closes without an answer becomes a written assumption.** Carry each one into the closing summary as a checkable predicate about the code or the environment — "the `users` table has a `deleted_at` column", not "auth is handled elsewhere" — and hold that list for Phase 5 to author into spec section 4; a `pending: <owner>` branch carries over as `pending: <owner> — <decision>; working assumption: <the recommended answer>` instead, since a decision is not a code predicate. A branch left open is a decision the plan makes silently: the Phase 7.5 challenge verifies section 4 assumptions claim by claim against the code, so a predicate written down gets checked and one kept in context does not. Then write `phase: approaches` via `atomic_state_set_field` and proceed to Phase 4.

**Artifact** — once a Start building or Wrap up pick hands off to Phase 4, fire the update for this site (call-site table in `loop-artifact-call-sites.md`).
