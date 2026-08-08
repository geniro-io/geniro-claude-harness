---
name: investigate
description: "Use when answering deep codebase questions that need evidence — repo structure, code behavior, git history, or internet sources. Parallel research agents produce cited answers. Skip for bug fixes (/geniro:debug) or codebase mapping (/geniro:onboard)."
context: main
model: inherit
allowed-tools: [Read, Bash, Glob, Grep, Agent, AskUserQuestion, WebSearch, WebFetch]
argument-hint: "[question about the codebase, e.g. 'how does auth work?', 'why was X pattern chosen?']"
---

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

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference: the plugin root is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` before deciding a step cannot run here — it substitutes mechanisms, not steps.

## State machine

state.md `phase:` enum: `classify` → `investigate` → `present` → `done` (happy path). Terminal states: `done`, `present-summary-only`, `aborted`, `routed` (the SessionStart recovery treats all as "task complete — no resume"). Non-terminal states roll back to phase-entry on compaction-resume and re-run idempotently. Escalation states (`classify-escalated`, `investigate-escalated`) — written via `atomic_state_write` before the Phase 1 Step 2.5 glossary gate and the Phase 2 Step 3 missing-data gate fire their question — surface to the user as "task was paused — your previous options:" so the user re-picks without losing context. The `present-loop` sub-state fires on Phase 3 Step 4 "dive deeper" follow-up (max 2 rounds).

Full ASCII state diagram in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §1.

**After a compaction, re-Read the current phase's body file before continuing it** — only a skill's front-loaded prefix is re-attached after a summary, so a mid-run summary can drop the Steps while leaving this spine intact. Phase 1, Phase 2, and Phase 3 each keep their Steps in a sibling file (state.md `phase:` says which). If state.md `phase:` itself is gone, re-invoke the skill and resume from Phase 1.

## Loop invariants

**Phase bodies.** Phases 1, 2, and 3 keep their Steps in sibling files (`phase-1-classify.md`, `phase-2-investigate.md`, `phase-3-present.md`). Read the matching one before any step of that phase and echo it, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — those files hold this skill's gates (the glossary-mismatch gate, the missing-data gate, the per-finding save approvals) and the further files they defer to are bound by the same contract.

The canonical agent-loop invariants in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` apply, with two investigate-specific bindings:

- **Invariant #4 (bounded structured tool results)** — the Codebase Analyst is `codebase-research-agent`, whose report cap its own contract declares (`${CLAUDE_PLUGIN_ROOT}/agents/codebase-research-agent.md` §Output Schema); the Git Historian and Internet Researcher are general-purpose spawns, capped at ~8K chars each. Either way, overflow truncates with a marker.
- **Invariant #7 (errors → structured observations)** — WebFetch/WebSearch failures, permission errors, agent registration "not found" fallbacks all become structured `## Tool log` or `## Errors` entries.

This skill adds one invariant:

S1. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**Turn-completion check.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check at every gate — the render is followed immediately by its lean `AskUserQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard.

**`## Tool log` section in state.md:** selective logging — subagent spawn outcomes (1-3 research agents + Phase 3 fresh verifier), L2 emits (`discovery` calls), and escalation entries. Routine Read / Bash / WebSearch skipped.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I already know the answer from reading the code" | You read one perspective. Parallel agents catch what you missed — git history reveals intent, internet reveals context. |
| "I'll spawn all 3 (or add an agent the classification excluded) to be safe" | The Phase 1 Step 1 classification table is the LITERAL spawn set; irrelevant agents are net-negative — they consume tokens and their off-target findings force the synthesizer to filter noise. If the criteria look wrong for this question, revise classification — don't silently add. |
| "Self-review is overkill for a question" | Wrong answers waste more time than the review costs. File references go stale, claims drift from evidence. |
| "I'll spawn agents one at a time to save tokens" | Parallel agents go in ONE response — multiple Agent calls in the same assistant turn. Sequential turns waste wall-clock time for no token savings. |
| "All three agents converge on the same claim — that's confirmed" | Convergent self-reports are still self-reports. Phase 2 Step 2 re-verify requires the orchestrator to independently re-read / re-run / re-grep before treating any agent claim as evidence. |
| "The reasoning chain is tight, that's enough evidence" | Reasoning is hypothesis, not evidence. Only the artifact kinds (file:line snippet, captured output, log line, query result, user data) clear the Evidence Standard. |
| "I'll add a 'low-confidence' caveat and ship the claim anyway" | Caveats are not evidence — route the claim through Phase 2 Step 2 §Route unverified claims, which has no "ship with caveat" exit: a claim shipped under a label still reads as an answer, and the reader acts on it. |
| "How-can-we / Compare / What-if questions are forward-looking, they don't need code-level verification" | All investigation types require evidence-backed answers. "How can we connect X to Y" must cite the actual schema/API/integration points; "what would break" must cite the actual call sites — not speculate. |
| "The investigation found a WebFetch result that contradicts the code — I'll trust the docs." | Trust ≠ correctness. Trust labels (`verified` vs `retrieved`) document SOURCE, not RIGHTNESS. WebFetch result + matching code = both verified evidence. WebFetch result alone (no code verification) = retrieved evidence — note it as such; do NOT promote to verified without code grounding. |
| "The answer touched architecture — I'll write it up as an ADR or a project rule before closing." | /geniro:investigate answers questions; it writes no rule, ADR, or CLAUDE.md section. Its durable output is the Step 5 learning. A user who wants the answer promoted into project rules runs `/geniro:reflect`, where the candidate faces the full worth bar instead of riding an investigation's momentum. |
| "Internet Researcher returned a GitHub issue thread — treat it as code-authoritative." | GitHub issues are `trust: retrieved` per Phase 3 Step 5. Issue threads contain speculation, outdated info, and opinions. Cross-check against current code (Codebase Analyst) before treating as load-bearing evidence. |
| "Skip the Step 5 trust label on L2 emit — the entry will be trustworthy enough." | Step 5 mandates the field. Future readers (later retrieval or telemetry) rely on the trust label to filter. Missing label = silent loss of source-confidence info. Always set the label. |
| "Glossary mismatch (Phase 1 Step 2.5) is a corner case; skip the check." | If CLAUDE.md has a Domain Context section, the check is cheap (grep against pre-loaded content). Skipping it on a term-mismatched question wastes 2-3 agent spawns on the wrong vocabulary. Always run the check when Domain Context is present. |
| "Drop the JIT cadence formalization (Step 2.6) — it's just documentation overhead." | The 5-step cadence is what makes /geniro:investigate evidence-disciplined; dropping it would let claims drift from evidence. Step 2.6 is the audit trail that makes JIT discipline reviewable. |

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

Follow the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. OMIT `model=` at every spawn — every spawn in this skill researches or verifies, and the orchestrator's session tier propagates to the work that decides the answer.

## Subagent spawn contract

Every `Agent(...)` spawn in this skill — Phase 2 Step 1 research agents (Codebase / Git / Internet), Phase 3 Step 2 fresh verifier agent — satisfies every pre-inlined field in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`, because a spawn missing a field makes the subagent re-discover scope from scratch and drift. Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` for runtime degradation when invoking plugin-defined agents: the plugin-defined `codebase-research-agent` (Phase 2 Codebase Analyst, plus codebase-locator side queries during Phase 3 synthesis) is spawned via this ladder; the Git Historian, Internet Researcher, and fresh verifier are general-purpose spawns.

## Evidence Standard

A claim is evidence-backed only when it cites a canonical artifact kind, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` § What counts as an artifact (kinds 1-6). Kind 6 (external documented fact, cited by resolvable source URL and quoted at the point of use) is what a WebFetch/WebSearch-sourced claim cites in this skill's external-research mode.

Reasoning, paraphrased agent claims, "looks consistent", convergent agent self-reports, and "I inferred from context" are not evidence — they are hypotheses that still need verification.

If the orchestrator's tools cannot produce evidence for a load-bearing claim, the claim is unverified: an answer synthesized around it reads as authoritative while resting on nothing. Use the Phase 2 Step 2 verification gate or the Phase 2 Step 3 missing-data gate (AskUserQuestion) instead.

## ACI per-phase tool surface

**Phase 1 (Classify+Scope):**
- Allowed: Read / Grep / Glob / Bash (read-only: `git log`, `git diff`, `git blame`, `git show`; `atomic_state_write` for the state checkpoint and the Step 2.5 escalation write; the Step 1.5 `rm -rf` of the run's own state directory on the `/deep-research` routed exit); WebSearch / WebFetch (rare for Phase 1 prelim).
- Allowed Agent spawns: none yet.
- Explicitly blocked: Edit / Write / `git add` / `git commit` / `git push`.

**Phase 2 (Investigate+Verify):**
- Allowed Agent spawns: Codebase Analyst / Git Historian / Internet Researcher (per Phase 1 classification).
- Each spawned agent runs with its own tool whitelist (per the Phase 2 Step 1 spawn templates):
- Codebase (`codebase-research-agent`): exactly its own `${CLAUDE_PLUGIN_ROOT}/agents/codebase-research-agent.md` frontmatter `tools:` whitelist — that allowlist is the contract, not a summary of one.
- Git: Read / Bash (read-only git verbs); blocked: Edit / Write / mutating git.
- Internet: WebSearch / WebFetch; blocked: Edit / Write / local Bash.
- Orchestrator re-verify (Step 2): Read / Grep / Bash (read-only) for re-running checks.

**Phase 3 (Synthesize+Review+Present):**
- Allowed: Read (for re-reading cited files during synthesis) / AskUserQuestion (Step 4 dive-deeper follow-up) / Bash (`atomic_state_write` to persist `dive_round:`; Step 6 cleanup of the run's scratch state).
- Allowed Agent spawns: fresh verifier agent (inherits orchestrator session tier).
- Fresh verifier agent: Read / Grep (no Edit / Write).

The safety hooks apply across every phase; the complete list and what each blocks is in `${CLAUDE_PLUGIN_ROOT}/HOOKS.md`. Runtime denies stay enforced.

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

These are the load-bearing exit gates — the checks that, if skipped, make the answer unsound or the no-ship boundary unsafe. Per-phase mechanics (classification, scoping, agent spawns, synthesis) live in their phase sections; this is the final correctness/contract check, not a re-listing of every step.

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

**If `$ARGUMENTS` is empty**, use the `AskUserQuestion` tool with header "Investigation" and question "What kind of investigation, and about what?" with options "Trace how a feature works" / "Explain why a decision was made" / "Assess the risk of a change" / "Compare two approaches" — each answer must name the actual feature, decision, or area, not just the shape. Do not proceed until a subject is named.

## Phase 1: Classify+Scope

State.md `phase: classify`. Low cost — a semantic $ARGUMENTS classification + memory-layer load (instructions + snapshot + past learnings) + glossary-mismatch check. Critical for correctness: bad classification → wrong agent set → wasted research budget.

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

State.md `phase: investigate`. Parallel research-agent spawns + orchestrator re-verify. Exits to Phase 3 only when every load-bearing claim is verified, dropped, or routed through missing-data gate.

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/investigate/phase-2-investigate.md` as this phase's first action, then echo per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`** — Steps 1-3: the parallel research-agent spawns (Codebase Analyst / Git Historian / Internet Researcher), the orchestrator's own re-verification pass, and the missing-data gate. Read it again on any resumption of the phase, including after a compaction.

## Phase 3: Synthesize+Review+Present

State.md `phase: present`. Synthesizes verified findings, a fresh verifier agent re-checks, presents to user, emits L2 `discovery` with trust label.

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/investigate/phase-3-present.md` as this phase's first action, then echo per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`** — Steps 0-6: refresh custom instructions, synthesize the draft, the fresh-verifier review round, present + Sources + Open questions, the follow-up AUQ, the learning emit with trust label, and cleanup. Read it again on any resumption of the phase, including after a compaction.

---

## State file schema

T1.5 state.md path `.geniro/state/investigate/<slug>/state.md` (cwd-relative — within-skill resume-from-compaction state per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Artifacts NOT in scope"; slug per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md`). Write via `atomic_state_write`. `approvals[]` category `glossary_resolve` populated when Phase 1 Step 2.5 fires, and category `duplicate_answer` populated when Phase 1 Step 2.6's duplicate-answer check fires. Full frontmatter + body sections (Scope / Classification / JIT Cadence / Agent Findings / Verified Claims / Draft Answer / Verifier Findings / Final Answer / Tool log / Errors / Open Questions / Termination reason / Persisted approvals) in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §2.

## State recovery

On skill start: compute `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` §Slug rules, Glob `.geniro/state/investigate/<slug>/state.md`. If present: source `${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh` and run `validate_state_file` on it — on failure fire the recovery AskUserQuestion from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` instead of consuming a corrupt file. On pass, run the helper §Consumer contract (Case A/B/C/D mismatch handling) — a same-cwd resume against a different branch's state file otherwise consumes it silently — then resume from the next incomplete phase.

---

## Examples

### Example 1: understanding a feature
```
/geniro:investigate how does the authentication flow work?
```
→ Codebase agent traces auth middleware, token validation, session management
→ Git agent finds when auth was added and major changes
→ Synthesize into execution flow with file:line references
→ Self-review verifies all references are accurate
→ Present: flow diagram + key files + edge cases

Additional worked examples (Design rationale, Impact analysis, Forward-looking integration) live in `${CLAUDE_PLUGIN_ROOT}/skills/investigate/investigate-taxonomy-reference.md` §6.
