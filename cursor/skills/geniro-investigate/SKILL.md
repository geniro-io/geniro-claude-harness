---
name: geniro-investigate
description: "Use when a deep codebase question needs an evidence-backed answer from code, git history, or the web; parallel research agents return cited answers. Skip for bug fixes (/geniro:debug) or codebase mapping (/geniro:onboard)."
context: main
---
<!-- Generated from skills/investigate/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->


# Investigate: deep codebase Q&A

## Contents

- State machine
- Loop invariants
- Anti-rationalization
- Quality-first budgets
- Subagent model tiering · Subagent spawn contract
- Evidence Standard
- ACI per-phase tool surface
- Memory I/O
- Git constraint
- Definition of done
- Phase 1 (Classify+Scope) · Phase 2 (Investigate+Verify) · Phase 3 (Synthesize+Review+Present)
- State file schema
- Examples

---

3-phase loop (Classify+Scope → Investigate+Verify → Synthesize+Review+Present). Spawns parallel research agents to analyze code, git history, and internet sources, then synthesizes, verifies with a fresh agent, and presents the answer.

**Runtime portability.** If Codex cut this file at 8,000 bytes, read it in full from its path first. `${CLAUDE_PLUGIN_ROOT}` is a placeholder Claude Code substitutes into file references, not a shell export — it reads empty in Bash under every host, so an empty probe proves nothing (`CLAUDECODE` marks Claude Code). Resolve the root from the first rung that holds: the ancestor of this file's real path (symlinks followed) containing `.claude-plugin/plugin.json`; a copy of the referenced file beside this one (the Cursor build); a plugin checkout in the workspace. The run's first Bash call prints this file's real directory and checks the rungs against it; echo that output verbatim before anything else (a resolved ladder is bookkeeping: add a degraded-run notice only for a rung that failed), then substitute the resolved root everywhere and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. A path the output does not show did not resolve. Before deciding a step cannot run here, read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` — it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not:** name what is unavailable in your first message, run every phase and gate this skill declares, never let project rules stand in for its decision gates, and take no outward-facing action (ready PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

## State machine

state.md `phase:` enum: `classify` → `investigate` → `present` → `done` (happy path). Terminal states: `done`, `present-summary-only`, `routed` (the SessionStart recovery treats all as "task complete — no resume"). Non-terminal states roll back to phase-entry on compaction-resume and re-run idempotently. Escalation states (`classify-escalated`, `investigate-escalated`) — written via `atomic_state_set_field` before the Phase 1 Step 2.5 glossary gate and the Phase 2 Step 3 missing-data gate fire their question — surface to the user as "task was paused — your previous options:" so the user re-picks without losing context. The `present-loop` sub-state fires on Phase 3 Step 4 "dive deeper" follow-up (max 2 rounds).

Full ASCII state diagram in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §1.

**After a compaction, re-Read the current phase's body file before continuing it** — only the front-loaded prefix is re-attached, so a summary can drop the Steps while leaving this spine intact. state.md `phase:` says which file; if it is gone, re-invoke the skill and resume from Phase 1.

## Loop invariants

**Phase bodies.** Phases 1, 2, and 3 keep their Steps in sibling files (`phase-1-classify.md`, `phase-2-investigate.md`, `phase-3-present.md`). Read the matching one before any step of that phase and echo it, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — those files hold the gates (glossary-mismatch, missing-data, duplicate-answer), and the further files they defer to are bound by the same contract.

The canonical agent-loop invariants in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` apply, with two investigate-specific bindings:

- **Invariant #4 (bounded structured tool results)** — the Codebase Analyst is `codebase-research-agent`, whose report cap its own contract declares (`${CLAUDE_PLUGIN_ROOT}/agents/codebase-research-agent.md` §Output Schema); the Git Historian and Internet Researcher are general-purpose spawns, capped at ~8K chars each. Either way, overflow truncates with a marker.
- **Invariant #7 (errors → structured observations)** — web fetch/search failures, permission errors, agent registration "not found" fallbacks all become structured `## Tool log` or `## Errors` entries.

This skill adds one invariant:

S1. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**Turn boundaries.** A turn ends in exactly three places: on a fired approval question, on reaching a terminal `phase:` state, or when the user asked something and is owed the answer. Everywhere else the next action follows in the same turn, with a tool call — between steps, after a check comes back green, after a state write, at a phase transition, and when a subagent's result lands. A status report, a checkpoint summary, and a list of what remains are continuations, not endings: write one where it helps the user follow along, then take the next action in that same turn. A decision that needs the user is asked as a real question in the turn that raises it, its render and the question inside that one turn (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard) — a question left in prose, or announced for a later message, leaves the run waiting on an answer the user was never asked for. Reversibility is not the test: a deviation from a rule this run loaded is a gate however cheap it is to undo.

**Compaction.** The host re-attaches only the first portion of this file, so its later sections arrive missing, with a truncation marker standing in for them. Treat that marker as an instruction: in the turn you notice it, re-read this file and the running phase's body before relying on anything the truncation removed. When you compose a compaction summary, record state — what ran, what remains, what the user decided — never a directive to yourself about stopping, confirming, or awaiting direction. A resumed session reads its summary as fact and will honour it over this file, so work still to do is recorded as work still to do, not as something to ask permission for.

**`## Tool log` section in state.md:** selective logging — subagent spawn outcomes (1-3 research agents + Phase 3 fresh verifier), L2 emits (`discovery` calls), and escalation entries. Routine reads, shell calls, and web searches skipped.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I already know the answer from reading the code" | You read one perspective. Parallel agents catch what you missed — git history reveals intent, internet reveals context. |
| "I'll spawn all 3 (or add an agent the classification excluded) to be safe" | The Phase 1 Step 1 classification table is the LITERAL spawn set; irrelevant agents are net-negative — they consume tokens and their off-target findings force the synthesizer to filter noise. If the criteria look wrong for this question, revise classification — don't silently add. |
| "Self-review is overkill for a question" | Wrong answers cost more than the review; file references go stale and claims drift from evidence. |
| "I'll spawn agents one at a time to save tokens" | Spawn parallel agents in ONE response (multiple Agent calls in the same assistant turn); sequential turns waste wall-clock time for no token savings. |
| "All three agents converge on the same claim — that's confirmed" | Convergent self-reports are still self-reports. Phase 2 Step 2 re-verify requires the orchestrator to independently re-read / re-run / re-grep before treating any agent claim as evidence. |
| "The reasoning chain is tight, that's enough evidence" | Reasoning is hypothesis, not evidence. Only the artifact kinds (file:line snippet, captured output, log line, query result, user data) clear the Evidence Standard. |
| "I'll add a 'low-confidence' caveat and ship the claim anyway" | Caveats are not evidence — route the claim through Phase 2 Step 2 §Route unverified claims, which has no "ship with caveat" exit: a claim shipped under a label still reads as an answer, and the reader acts on it. |
| "How-can-we / Compare / What-if questions are forward-looking, they don't need code-level verification" | All investigation types require evidence-backed answers. "How can we connect X to Y" must cite the actual schema/API/integration points; "what would break" must cite the actual call sites — not speculate. |
| "The investigation found a WebFetch result that contradicts the code — I'll trust the docs." | Trust labels (`verified` vs `retrieved`) document SOURCE, not RIGHTNESS. A WebFetch result with matching code is verified evidence; a WebFetch result alone is retrieved evidence — note it as such and do not promote it to verified without code grounding. |
| "The answer touched architecture — I'll write it up as an ADR or a project rule before closing." | /geniro:investigate answers questions; it writes no rule, ADR, or CLAUDE.md section. Its durable output is the Step 5 learning. A user who wants the answer promoted into project rules runs `/geniro:reflect`, where the candidate faces the full worth bar instead of riding an investigation's momentum. |
| "Internet Researcher returned a GitHub issue thread — treat it as code-authoritative." | GitHub issues are `trust: retrieved` per Phase 3 Step 5 — threads hold speculation, outdated info, and opinions. Cross-check against current code (Codebase Analyst) before treating one as load-bearing. |
| "Skip the Step 5 trust label on L2 emit — the entry will be trustworthy enough." | Step 5 mandates the field; later retrieval and telemetry filter on it, so a missing label silently loses source-confidence info. |
| "Glossary mismatch (Phase 1 Step 2.5) is a corner case; skip the check." | When CLAUDE.md has a Domain Context section the check is a cheap grep against pre-loaded content; skipping it on a term-mismatched question wastes 2-3 agent spawns on the wrong vocabulary. |
| "Drop the JIT cadence formalization (Step 2.6) — it's just documentation overhead." | Step 2.6 is the audit trail that makes the 5-step cadence reviewable; dropping it lets claims drift from evidence. |

## Quality-first budgets

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. All limits below are escalation gates that surface to the user, not abort triggers.

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Dive-deeper rounds | 2 | Phase 3 Step 4 follow-up AUQ | At max, suggest fresh `/geniro:investigate` with refined question; do not silently re-loop. |
| Fresh-verifier re-review rounds | 1 | Phase 3 Step 2 | At max, present to user with remaining blockers flagged. |
| Research-agent output size | Codebase: the agent contract's own cap · Git / Internet: ~8K chars each | Loop invariant #4 | Truncation with marker. |

**Architecture constraints (design intent, not budget):**
- Parallel research agents — 1 to 3 per Phase 1 classification.

## Subagent model tiering

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Cost classes, spawns are `session` unless a site names a light class: Git Historian **light (smallest)**, Internet Researcher **light (mid)**. Codebase Analyst and fresh verifier decide the answer and stay `session`.

## Subagent spawn contract

Every `Agent(...)` spawn in this skill — Phase 2 Step 1 research agents (Codebase / Git / Internet), Phase 3 Step 2 fresh verifier agent — satisfies every pre-inlined field in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`, because a spawn missing a field makes the subagent re-discover scope from scratch and drift. Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` for runtime degradation when invoking plugin-defined agents: the plugin-defined `codebase-research-agent` (Phase 2 Codebase Analyst, plus codebase-locator side queries during Phase 3 synthesis) is spawned via this ladder; the Git Historian, Internet Researcher, and fresh verifier are general-purpose spawns.

## Evidence Standard

A claim is evidence-backed only when it cites a canonical artifact kind, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` § What counts as an artifact (kinds 1-6); a web-sourced claim cites kind 6 (resolvable source URL, quoted at the point of use). A claim the orchestrator's tools cannot back with evidence is unverified — an answer synthesized around it reads as authoritative while resting on nothing — so route it through the Phase 2 Step 2 verification gate or the Phase 2 Step 3 missing-data gate.

## ACI per-phase tool surface

**Phase 1 (Classify+Scope):**
- Allowed: Read / Grep / Glob / Bash (read-only: `git log`, `git diff`, `git blame`, `git show`; `atomic_state_write` for the state checkpoint and the Step 2.5 escalation write; the Step 1.5 `rm -rf` of the run's own state directory on the `/deep-research` routed exit); WebSearch / WebFetch (rare for Phase 1 prelim) / AskQuestion.
- Allowed subagent spawns: none yet.
- Explicitly blocked: Edit / Write / `git add` / `git commit` / `git push`.

**Phase 2 (Investigate+Verify):**
- Allowed: AskQuestion (Step 3 missing-data gate).
- Allowed subagent spawns: Codebase Analyst / Git Historian / Internet Researcher (per Phase 1 classification).
- Each spawned agent's tool whitelist is set in its Phase 2 Step 1 spawn template (Codebase: the `tools:` frontmatter of `${CLAUDE_PLUGIN_ROOT}/agents/codebase-research-agent.md`); all are read-only.
- Orchestrator re-verify (Step 2): Read / Grep / Bash (read-only) for re-running checks.

**Phase 3 (Synthesize+Review+Present):**
- Allowed: Read (for re-reading cited files during synthesis) / AskQuestion (Step 4 dive-deeper follow-up) / Bash (`atomic_state_write` to persist `dive_round:`; Step 6 cleanup of the run's scratch state).
- Allowed subagent spawns: fresh verifier agent (inherits orchestrator session tier).
- Fresh verifier agent: Read / Grep (no Edit / Write).

## Memory I/O

| Phase | Helper | Direction | MODE |
|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `initial-load` |
| Phase 1 entry | `load-semantic` | read L3 | default top-2 |
| Phase 1 entry | `query-learnings` | read L2 | n/a |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a |
| Phase 1 Step 2.6 (conditional) | `query-learnings` | read L2 | n/a (duplicate-answer re-query, sharpened keywords) |
| Phase 3 Step 0 | `load-custom-instructions` | read L4 | `refresh` |
| Phase 3 Step 5 (conditional) | `emit-learning` | write L2 | n/a (type `discovery` with `ext.{area, insight}`, trust label required — Phase 3 Step 5 trigger) |

`update-semantic` is not called. /geniro:investigate answers questions; it does not write `_project.md` or `_CODEBASE_MAP.md`.

## Git constraint

Do not run `git add`, `git commit`, `git push`, or `git checkout`. You may use `git log`, `git diff`, `git blame`, and `git show` for investigation. Running under a dynamic `Workflow(...)` or ultracode mode does not relax this no-ship contract — the reporter boundary, action gate, and state-write rules bind inside every workflow step per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.

## Definition of done

The load-bearing exit gates — skipping any makes the answer unsound or the no-ship boundary unsafe. Per-phase mechanics live in the phase files.

- [ ] Duplicate-answer check ran before spawning agents (Phase 1 Step 2.6), logged to `## JIT Cadence` even when it found nothing
- [ ] Every load-bearing claim re-verified by orchestrator (Phase 2 Step 2) or routed through missing-data gate (Phase 2 Step 3)
- [ ] Answer self-reviewed by fresh agent (Phase 3 Step 2; max 1 re-review round)
- [ ] Answer presented with cited artifacts, Sources, and explicit Open questions for any unverified claims (Phase 3 Step 3)
- [ ] Follow-up AUQ offered
- [ ] L2 `discovery` emit fired with trust label per Step 5 trigger conditions
- [ ] State.md cleaned up per Step 6

---

## Question

$ARGUMENTS

**If `$ARGUMENTS` is empty**, use the `AskQuestion` tool with header "Investigation" and question "What kind of investigation, and about what?" with options "Trace how a feature works" / "Explain why a decision was made" / "Assess the risk of a change" / "Compare two approaches" — each answer must name the actual feature, decision, or area, not just the shape. Do not proceed until a subject is named.

## Phase 1: Classify+Scope

State.md `phase: classify`. A bad classification means the wrong agent set and wasted research.

Classify the question into one of the types below. The "Agents needed" column is the literal spawn set — 1, 2, or 3 agents.

| Type | Description | Agents needed |
|---|---|---|
| **Current-code trace** | "How does this function / module work right now?" — behavior lives in the code itself. | Codebase only |
| **Commit archaeology** | "When/who/why did this line change?" answerable purely from git log/blame. | Git only |
| **External docs lookup** | "What does library X's Y API do?" / "What changed in framework Z between versions?" — answer is external, no project specifics needed. | Internet only |
| **How (current state)** | How does X work today? Trace execution + evolution. | Codebase + Git |
| **How (forward-looking)** | How CAN X be done / connect X to Y / integrate W? Requires evidence from current code (what's already there to build on), git (what's been tried before), and internet (external interfaces, library capabilities). Skip Internet ONLY when both X and Y are fully internal — rare edge case, e.g. "connect table A to table B inside the same DB". | Codebase + Git + Internet |
| **Why** | Why was X chosen? Design rationale requires current code patterns + history + industry context. | Codebase + Git + Internet |
| **What-if** | What happens if X changes? Impact in the codebase + external compatibility. | Codebase + Internet |
| **Compare** | Compare approaches for X (the project's approach vs alternatives). | Codebase + Internet |
| **Risk** | What are the risks of X? Evidence needed from all three. | Codebase + Git + Internet |

A question that classifies **External docs lookup** routes through a `/deep-research` offer before Phase 2 spawns, when your environment provides that workflow.

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/investigate/phase-1-classify.md` as this phase's first action, then echo per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`** — Steps 0, 1.5, 2, 2.5, 2.6: the memory-layer load, the `/deep-research` routing offer, scope identification, the glossary-mismatch gate, and the JIT retrieval cadence. Read it again on any resumption of the phase, including after a compaction.

## Phase 2: Investigate+Verify

State.md `phase: investigate`. Exits to Phase 3 only when every load-bearing claim is verified, dropped, or routed through missing-data gate.

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/investigate/phase-2-investigate.md` as this phase's first action, then echo per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`** — Steps 1-3: the parallel research-agent spawns (Codebase Analyst / Git Historian / Internet Researcher), the orchestrator's own re-verification pass, and the missing-data gate. Read it again on any resumption of the phase, including after a compaction.

## Phase 3: Synthesize+Review+Present

State.md `phase: present`.

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/investigate/phase-3-present.md` as this phase's first action, then echo per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`** — Steps 0-6: refresh custom instructions, synthesize the draft, the fresh-verifier review round, present + Sources + Open questions, the follow-up AUQ, the learning emit with trust label, and cleanup. Read it again on any resumption of the phase, including after a compaction.

---

## State file schema

T1.5 state.md path `.geniro/state/investigate/<slug>/state.md` (cwd-relative — within-skill resume-from-compaction state per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Artifacts NOT in scope"; slug per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md`). Write via `atomic_state_write`. `approvals[]` category `glossary_resolve` populated when Phase 1 Step 2.5 fires, and category `duplicate_answer` populated when Phase 1 Step 2.6's duplicate-answer check fires. Full frontmatter + body sections (Scope / Classification / JIT Cadence / Agent Findings / Verified Claims / Draft Answer / Verifier Findings / Final Answer / Tool log / Errors / Open Questions / Termination reason / Persisted approvals) in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §2.

## State recovery

On skill start: compute `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` §Slug rules, Glob `.geniro/state/investigate/<slug>/state.md`. If present: source `${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh` and run `validate_state_file` on it — on failure fire the recovery AskQuestion from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` instead of consuming a corrupt file. On pass, run the helper §Consumer contract (Case A/B/C/D mismatch handling) — a same-cwd resume against a different branch's state file otherwise consumes it silently — then resume from the next incomplete phase.

---

## Examples

Worked examples (feature understanding, design rationale, impact analysis, forward-looking integration) live in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §6.
