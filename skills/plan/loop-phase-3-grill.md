# Phase 3 — Grill (decision-tree clarification)

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

## Contents

- 3.1 Build the decision tree
- 3.2 AUQ shape — message-first, one question at a time
- 3.3 Persistence
- 3.4 Checkpoint gate and termination

State.md `phase: clarify` during this phase.

This phase is a decision-tree grill: walk the design's open decisions depth-first, one question at a time, until the branches that shape the spec resolve. A real plan is a tree of dependent decisions — resolving a parent reshapes (or removes) its children, so the question set cannot be enumerated up front.

### 3.1 Build the decision tree

Build the tree from:
- Phase 1 research findings ("found 3 auth flows — which one is the integration surface?")
- L2 query-learnings ("a prior decision favored Approach X — does it apply here?")
- L4 code-style rules

Root = the feature. Branches = its major design axes (data model, integration surface, failure handling, UX, scope edges). A child decision that only matters under a particular parent answer hangs off that parent.

**Codebase-first.** Before asking anything the code can answer, read it — for a multi-file question spawn `codebase-research-agent` (invariant S1). Ask only what the code cannot settle: a question answerable from L3 `_project.md` ("what test runner?") is forbidden — answer it silently and move on. The same bar applies to the user's answers: when an answer asserts how the system behaves today, verify the assertion against the code before building the tree on it — one targeted Read, or a research spawn for a multi-file claim. On a contradiction, make it the next question ("the code cancels whole orders at `src/orders/cancel.ts:40`, but you said partial cancellation exists — which is right?") rather than planning on the stated version. When a concept boundary stays vague after a direct question, re-ask through a concrete edge-case scenario — a specific case forces a precise answer where a repeated abstract question invites another vague one.

**Terminology check.** When CLAUDE.md carries a Domain Context glossary, check the topic's and each answer's domain terms against it — a plan authored with mismatched vocabulary produces a spec /geniro:implement builds wrong. On a conflict ("the glossary defines *cancellation* as void-before-capture; this answer uses it as refund-after-capture"), surface it as the next grill question rather than silently picking a meaning. When a term is fuzzy or overloaded ("account" — the Customer or the User?), propose one canonical term and use it for the rest of the run.

**Grill early during the explore wait.** When the §1.2 explore agents were backgrounded, the orchestrator MAY fire the code-independent grill branches early — during that wait — per Shape A of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md`. Eligible early: branches sourced from L2 learnings, L4 rules, and task-generic scope edges (feature-flag / rollout / in-scope-surface) — questions the code cannot answer. HELD until the §1.5 drain: the Phase-1-findings-derived branch and anything L3 `_project.md` could answer — exactly the "Codebase-first" forbidden set, whose complement is the safe overlap set. Ask each early question one at a time per §3.2 and persist to `approvals[]`; Phase 3 regenerates its tree skipping the already-answered branches (never re-ask). If no code-independent question exists, wait for the drain.

**Walk depth-first.** Pick the highest-leverage unresolved branch, drill it to its leaves in parent→child order, then backtrack to the next branch. Depth-first keeps each line of questioning coherent instead of scattering across unrelated axes.

### 3.2 AUQ shape — message-first, one question at a time

Apply the Gate presentation contract. Ask one question at a time — one `AskUserQuestion` call per question, never a multi-question batch. Before each question render its framing to a chat message first, sized to the question: a one-line orientation when every option is self-explanatory, a short per-option consequence block (a code anchor, config diff, or behavior trace) when an option's consequence needs more than its one-line `description`. Then fire the lean single-question AUQ with short labels + one-line `description`s. Give a recommended answer for every question (Recommended-first option) — the user is confirming a default, not authoring from scratch.

Each answer reshapes the tree frontier — a still-pending child can become moot (drop it) or need reworded options — so do NOT pre-generate a fixed question list; regenerate the next question from the live tree after each answer. Each question uses a `header` per the Gate presentation contract's cap, `question` 1-2 sentences ending in a question mark, `options[]` of 2-4 explicit choices, `multiSelect: false` unless explicitly multi-select. Include a "Skip — proceed with stated assumption" option as the last choice when applicable. The grill is uncapped but bounded by the §3.4 checkpoint gate. Full literal example with the per-question chat message + single-question AUQ in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2.

When `--deep` is absent, ask the planning-depth question (Standard / Deep) once at grill wrap-up (§3.4) — full rules (checkpoint-cadence exemption, persistence, empty-answer default, Trivial flag-only) and the AUQ shape in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2a.

### 3.3 Persistence

Each answered question → append entry to state.md frontmatter `approvals[]` via `atomic_state_write`. Append the `approvals[]` entry for each answer before rendering the next question — so a context reset mid-sequence preserves every answer already given. Entry shape in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1; category `clarify_<dim>`.

On compaction-resume, the SessionStart re-injector renders `approvals[]` and the model re-reads it to skip already-answered questions.

### 3.4 Checkpoint gate and termination

There is no fixed question cap — the grill runs until the spec-shaping branches resolve. To keep it bounded, pause for a checkpoint whichever comes first: a full design branch resolves, OR ~6 questions have been asked since the last checkpoint. This is an escalation gate, not an abort — the user, not a fixed number, decides when to stop.

**Artifact** — fire the before-gate update for this site (call-site table in `loop-artifact-call-sites.md`) before the checkpoint AUQ.

At a checkpoint, render a running summary to a chat message — resolved decisions, deferred items, and the open branches still to walk — then fire ONE lean AUQ:
- **Keep grilling** (Recommended while open branches remain) — continue the walk.
- **Wrap up now** — stop; remaining open branches become stated assumptions.
- **Skip remaining branches with stated assumptions** — same as wrap-up, but name the skipped branches explicitly in the Assumptions section for /geniro:implement to verify.

Persist each checkpoint decision to `approvals[]` category `grill_checkpoint` via `atomic_state_write` before continuing.

**Termination** fires when all branches resolve, the user picks Wrap up / Skip, or no spec-shaping question remains. On termination, render a closing summary — resolved decisions, deferred work, and any unaddressed risks — and hold it in context: it feeds Phase 4 approach generation and seeds Phase 5 sections (Steps / Validation / Done Condition).

**Every branch that closes without an answer becomes a written assumption.** Carry each one into the closing summary as a checkable predicate about the code or the environment — "the `users` table has a `deleted_at` column", not "auth is handled elsewhere" — and hold that list for Phase 5 to author into spec section 4. A branch left open is a decision the plan makes silently, and an unwritten one is invisible to every gate that follows: the Phase 7.5 challenge verifies section 4 assumptions claim by claim against the code, so a predicate written down gets checked and one kept in context does not. Then ask the planning-depth question (`${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2a) when `--deep` is absent, and transition to Phase 4. The checkpoint and termination summary templates are in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2.

**Artifact** — on termination, fire the update for this site (call-site table in `loop-artifact-call-sites.md`).
