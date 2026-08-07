---
name: refactor
description: "Use when restructuring code for better organization or reducing tech debt with zero behavior change. 3-phase loop (Plan → Apply → Verify); never ships — the diff is the deliverable. For behavioral changes use /geniro:implement; for performance use /geniro:review (optimizations dimension)."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite]
argument-hint: "[what to refactor and why]"
---

# Refactor with test verification

## Contents

- Your role — restructure, don't ship
- Phases overview
- State machine
- Terminal states
- Loop invariants
- Anti-rationalization
- Budgets — quality-first
- Subagent model tiering · Agent failure handling
- Evidence Standard
- Universal rule: all choice questions use AskUserQuestion
- ACI per-phase tool surface
- Git constraint
- Memory I/O schedule
- Definition of done
- Phase 1 (plan) · Phase 2 (apply) · Phase 3 (verify)
- State file schema
- Task tracking

---

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference: the plugin root is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` before deciding a step cannot run here — it substitutes mechanisms, not steps.

**Detailed contracts:**
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` — canonical tier rubric (Trivial / Small / Medium / Big)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` — the smell-detection sub-step (reuse-vs-create audit per detected smell)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` § Single-finding gate — the single-finding AskUserQuestion gate
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` § Visual rendering language — the shared visual language for gate messages rendered to chat before a lean question

**Phase bodies.** Phase 1, Phase 2, and Phase 3 all live in sibling files, Read on entry to that phase and again on any resumption of it, including after a compaction: `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-1-plan.md`, `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-2-apply.md`, `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-3-verify.md`. That Read is the phase's physically-first action and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the phase files hold this skill's gates and its helper call sites, so work started before the Read runs outside them.

**Section-reference convention:** bare `§N.M` refs point to Phase sub-sections — `§1.M` in `phase-1-plan.md`, `§2.M` in `phase-2-apply.md`, `§3.M` in `phase-3-verify.md`; `§ <name>` refs name a section inside the cited `_shared` helper. `refactor-reference.md` numbers its own top-level sections 1-3 (State machine / Schema / Spawn template), so any Phase reference there is written `Phase N §N.M` to avoid colliding with those.

---

## Your role — restructure, don't ship

You refactor. You validate behavior preservation. You do not commit or push the diff. Phase 3 endpoint is a working-tree diff (the deliverable) + a chat completion summary + state.md audit trail. Downstream actors (user `git commit`, `/geniro:implement` to ship through review gate) handle the actual ship. Running under a dynamic `Workflow(...)` or ultracode mode does not relax this no-ship contract — the reporter boundary, action gate, and state-write rules bind inside every workflow step per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.

The zero-behavior-change guarantee is enforced per-step via the orchestrator-inline regression test gate AND post-execution via the final regression run.

---

## Phases overview

1. **Plan** — discover scope, capture a baseline, classify effort tier, detect and filter smells, build and approve the transformation plan.
2. **Apply** — execute the approved plan one step at a time, each transformation gated by its own regression run.
3. **Verify** — diff sanity check, independent review, disposition (fix loop / escalate / ADR), completion summary, and cleanup.

---

## State machine

state.md `phase:` enum: `plan` → `apply` → `verify` → `done` (happy path). Terminal states: `done`, `verify-summary-only`, `reverted`, `aborted`, `routed` (SessionStart recovery treats all five as "task complete — no resume needed"). Escalation states: `plan-escalated` (hard signal OR baseline red), `apply-escalated` (session-level blocked-ratio cap exceeded — §Budgets), `verify-escalated` (1-round fix-loop exhausted). Recovery surfaces escalation states as "task was paused — your previous options:" so the user re-picks without losing context.

Full ASCII state diagram in `${CLAUDE_PLUGIN_ROOT}/skills/refactor/refactor-reference.md` §1.

**After a compaction, re-Read the current phase's body file before continuing it** — only a skill's front-loaded prefix is re-attached after a summary, so a mid-run summary can drop the Steps while leaving this spine intact. state.md `phase:` says which file that is.

---

## Terminal states

`done`, `verify-summary-only`, `reverted`, `aborted`, `routed`. Every transition into any of the five first runs `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-3-verify.md` §3.7 Cleanup (the slug-dir sweep + background-process kill) and only then writes the terminal `phase:` via `atomic_state_write` — a terminal write that skips cleanup leaves the slug dir behind, where nothing else sweeps `.geniro/state/`. `done`, `verify-summary-only`, and the `reverted` / `routed` picks inside Phase 3 §3.3 get this for free, since §3.7 is the phase's own next step. The paths that reach a terminal WITHOUT otherwise entering Phase 3 owe the call explicitly: Phase 1 §1.2 (no tests exist → `routed`), §1.3.2 (hard-signal "Escalate" → `routed`), the `plan-escalated` "Abort" resolution (→ `aborted`), and Phase 2 §2.3 / §2.4 (either revert pick → `reverted`). A `reverted` / `routed` / `aborted` write also carries a `## Termination reason` body line naming what ended the run.

---

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply, with three refactor-specific bindings:

- **Invariant #4 (bounded structured tool results)** — orchestrator-inline execution writes per-step status and blocked-step reasons to state.md `## Plan steps`; total file body capped at ~8K chars via atomic_state_write truncation marker.
- **Invariant #5 (escalation gates, not silent abort)** — the blocked-ratio cap AUQ (§Budgets) + PRODUCT-DECISION always waits for the user.
- **Invariant #7 (errors → structured observations)** — per-step blocked rationale, baseline validation failure, and reviewer CRITICAL findings all become structured `## Tool log` / `## Errors` entries.

This skill adds one invariant:

S1. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**Turn-completion check.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check at every gate — the render is followed immediately by its lean `AskUserQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard.

`## Tool log` schema: typical run produces 3-6 entries (reviewer-agent + custom reviewers + escalation entries; smell detection and per-step execution run orchestrator-inline and emit to state.md `## Plan steps` directly).

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This smell is too small to fix" | Phase 1 §1.5's KEEP/FILTER matrix already filtered it from noise — a smell that survived is a vetted target, and skipping it after approval reopens the filtering §1.5 exists to centralize. |
| "I'll batch multiple transformations" | The per-step regression gate (Phase 2 §2.2) isolates behavior drift to the smallest possible unit — a batched failure leaves no way to tell which transformation caused it. |
| "Tests are passing so I'll skip the blocked step protocol" | The protocol exists for the NEXT failure. Follow it — Phase 2 §2.2 Blocked Step Protocol applies to ALL transformations regardless of prior-step success. |
| "This refactoring needs a behavior change" | Then it's not a refactoring. Use `/geniro:implement` instead. The zero-behavior-change guarantee is non-negotiable. |
| "This duplication needs a new shared helper" | Run the Existing Abstraction Audit first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md`. If a utility / service / hook already exists nearby that could absorb this duplication via a small extension, prefer extending it. Only create a new shared helper when no analogue exists OR when extending the existing one would require adding a parameter or conditional that complicates it (Rule of Three). |
| "All detected smells are real issues" | Generic smell categories flag intentional repo patterns. Without filtering against THIS repo's conventions via Phase 1 §1.5 smell evidence + KEEP/FILTER synthesis matrix, you'll refactor code that was designed that way on purpose. |
| "I'll spawn agents one at a time" | All parallel agents MUST be spawned in ONE response — multiple Agent calls in the same assistant turn. Separate turns = no concurrency, full wall-clock latency per agent. |
| "I noticed a bug mid-refactor, I'll fix it" | That's feature work. Note it for `/geniro:implement` and stay in refactor scope. The zero-behavior-change guarantee applies even when the in-scope behavior is buggy. |
| "Reviewer flagged a `[PRODUCT-DECISION]` finding — I'll route it through the fix loop like any other CRITICAL/HIGH" | A `[PRODUCT-DECISION]` finding has multiple valid resolution paths by definition — picking one is a behavior change, which contradicts refactor's zero-behavior-change guarantee. Phase 3 §3.3 disposition logic ESCALATES PRODUCT-DECISION to `/geniro:implement` (always-WAIT) — never gates-and-fixes them in-skill. If you find yourself orchestrator-inline editing for a PRODUCT-DECISION finding, that's the rationalization. Stop and route the escalation. |
| "Auto-promote a recorded discovery into a project rule when refactor completes." | /geniro:refactor proposes no project rules at all — its durable output is the `discovery` / `pitfall` learning emitted at Phase 3 §3.5. Rule mining is `/geniro:reflect`, which the user invokes when they want it; a rule offer bolted onto a refactor interrupts the diff review the run exists to deliver. |
| "The revert step needs `git checkout -- .` / `git restore .`, but the guard blocks it — I'll bypass the hook or run `git stash`." | The guard is blocking a mass discard, not the revert. Use the targeted form § Git constraint defines; a bypass or `git stash` reaches the same uncommitted work the guard exists to protect. If some other guardrail blocks legitimate refactor work, the path is `.geniro/safety.json` `allow_patterns`, not `--no-verify`. |
| "PRODUCT-DECISION 3-option AUQ is paternalistic — collapse to 2 options (run /geniro:implement / accept-as-is)." | Phase 3 §3.3 is explicit: 3 fixed options. The Revert path is a user-controlled safety net, and dropping it leaves a user who dislikes the diff with no in-skill way out. Collapsing removes meaningful agency. |
| "Trivial tier should still run a quick reviewer-pass — what if a smell slipped through?" | Trivial is by definition 1-2 files, mechanical, single module, unambiguous. The diff-sanity check in Phase 3 §3.1 + the baseline regression in Phase 2 §2.4 catch behavioral drift. Running a full reviewer-agent batch for a 5-line rename wastes tokens. Tier behavior is intentional. |

---

## Budgets — quality-first

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Budgets — quality-first (canonical). This skill's own gates:

**Quality gates (escalate to user, do not abort):**

| Gate | Cap | Past threshold |
|---|---|---|
| Per-step retry (orchestrator-inline Blocked Step Protocol) | 3 | Mark BLOCKED, continue to next step |
| Session-level blocked ratio | 30% (post-rejection denominator) | AUQ — keep what worked & escalate / revert / force-continue. User picks. |
| Phase 3 fix-loop | 1 round | Re-spawn reviewer once; if still failing, AUQ (escalate / accept / abort). |
| Reviewer output size | the per-dimension report cap in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output cap | Truncation with marker (canonical invariant #4). |

**Architecture constraints (design intent, not budget):**

| Constraint | Value |
|---|---|
| Parallel reviewer spawns | 1 independent + N custom reviewers |
| Smell-detection rounds | 1 (orchestrator-inline) |
| Smell-evidence filter rounds | 1 (Medium+ only) |

---

## Subagent model tiering

OMIT `model=` at every plugin-agent spawn site, per the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Spawn plugin-defined subagents (reviewer-agent, custom reviewers) through the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (`geniro:<agent>` → bare `<agent>` → `general-purpose` with body inlined); cache the resolved rung for the rest of the session.

Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site — every Agent prompt satisfies every pre-inlined field, because a spawn missing a field makes the subagent re-discover scope from scratch and drift.

| Spawn | Tier | When |
|---|---|---|
| Orchestrator-inline execution (any risk) | Orchestrator's model | Smell detection + per-step execution run on orchestrator's main thread (no subagent — no tiering decision) |
| Independent reviewer-agent + custom reviewers | inherit (OMIT `model=`) | Phase 3 diff review (Medium+ tier only); inheritance lets the user's session-level `/model` choice propagate |

## Agent failure handling

If a delegated agent fails (timeout, error, empty/garbage result): retry once with the same prompt. If the retry also fails, the **Phase 3 reviewer batch** (reviewer-agent + custom reviewers) is fail-open — note the failure in the completion summary, proceed, and warn the user that independent review did not complete.

---

## Evidence Standard

Cite the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. /geniro:refactor applies it at baseline validation, the per-step regression gate (orchestrator-inline pre/post-check), and the final regression run.

---

## Universal rule: all choice questions use AskUserQuestion

Route every user-facing choice in this skill through the `AskUserQuestion` tool per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions, which owns the rule and the reason. This skill's gates live in the phase files — Phase 1 §1.2 (baseline-red) and §1.3.2 (hard-signal escalation), §Budgets above (blocked-ratio cap, fix-loop), and Phase 3 §3.3 (disposition) — not a single list here.

---

## ACI per-phase tool surface

**Phase 1 (Plan):**
- Allowed: Read / Grep / Glob / Bash (read-only — `git status`, `git log`, `git diff`, `git branch --show-current`, test suite invocation for baseline).
- Allowed Agent spawns: `codebase-research-agent` for wide cross-file locator queries during smell detection (Phase 1 §1.4). smell detection + smell evidence otherwise run orchestrator-inline.
- Explicitly blocked: production-source Edit/Write, `git commit`, `git push`, `gh pr create`.

**Phase 2 (Apply):**
- Allowed Agent spawns: none. Per-step execution runs orchestrator-inline (Edit + Bash for tests).
- Orchestrator uses Edit / Write / Bash (test cmd) directly. Per-step regression runs via backpressure helper.
- Explicitly blocked at orchestrator level: `git add`, `git commit`, `git push`, `gh pr create`, branch switching.

**Phase 3 (Verify):**
- Allowed: Read / Grep / Glob / Bash (`git diff --name-only`, `git diff --stat`, test cmd for re-runs) / Edit (fix-loop-scoped — the §3.3 1-round CRITICAL/HIGH non-PRODUCT-DECISION fix applies findings inline).
- Allowed Agent spawns: reviewer-agent + custom reviewers (Medium+ only).
- Allowed: targeted per-file revert per § Git constraint — the one orchestration-level exception to the git-write constraint.
- Explicitly blocked: `git commit`, `git push`, `gh pr create`.

**All reviewer / custom reviewer spawns are pure read-only:** tool whitelist via `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` frontmatter (Read / Grep / Glob / Bash for read-only checks).

The safety hooks apply across every phase; the complete list and what each blocks is in `${CLAUDE_PLUGIN_ROOT}/HOOKS.md`. Runtime denies stay enforced.

---

## Git constraint

Do not run `git add`, `git commit`, or `git push`. The orchestrating workflow handles version control. Exception: revert a failed transformation in Phase 2 / Phase 3 with a targeted `git restore --source=HEAD -- <each changed path>`, listing only the specific paths the step touched — this is an orchestration-level revert, not a version-control operation. Never reach for a bare `.` or `*` pathspec (`git checkout -- .` / `git restore .`): the git-guardrail hook blocks the mass-discard form because it would wipe every uncommitted change, including work outside the current step.

---

## Memory I/O schedule

| Phase | Helper | Direction | MODE |
|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` |
| Phase 1 entry | `query-learnings` | read L2 | n/a |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a |
| Phase 1 entry (conditional) | spec.md frontmatter `workflow_refs[]` | read external | fires only when `$ARGUMENTS` points to spec.md or task-dir; cached tracker `status` primes scope decisions |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` (single re-fire) |
| Phase 2 exit (conditional) | `emit-learning` | write L2 | n/a (type `retry_failure_sequence` — fires when `blocked_count ≥ 2`, per Phase 2 §2.4) |
| Phase 3 exit | `emit-learning` | write L2 | n/a (emit types: `discovery` with `ext.{area, insight}` OR `pitfall` with `ext.{trap, mitigation}`) |

`update-semantic` writes to `_CODEBASE_MAP.md` for move/rename refactors (bounded auto-incremental write). Not applicable when refactor adds modules (would be a behavioral change → escalate to `/geniro:implement`).

---

## Definition of done

These are the load-bearing exit gates and safety invariants — the checks that, if skipped, break the zero-behavior-change guarantee or the no-ship boundary. Per-phase mechanics (tier classification, smell detection, plan building) live in their phase sections; this is the final correctness/contract check, not a re-listing of every step.

- [ ] Tests green before AND after the run — baseline captured (Phase 1) and final regression run captured as an Evidence Block (Phase 2 §2.4); the zero-behavior-change guarantee held
- [ ] PRODUCT-DECISION findings escalated to `/geniro:implement` (always-WAIT), never fixed in-skill
- [ ] CRITICAL/HIGH non-PD findings → 1-round fix loop; past that → "Findings remain" AUQ
- [ ] Blocked-ratio cap exceeded (§Budgets) → stuck AUQ fired (user picks; never silent abort)
- [ ] L2 emit fired with `discovery` or `pitfall` type + required `ext.*` fields
- [ ] Custom post-verify steps executed — any `### After verify` subsection in the loaded `.geniro/instructions/refactor.md` ran, or none was loaded (Phase 3 §3.6)
- [ ] No `git commit` / `git push` / `gh pr create` — diff stays uncommitted (user or /geniro:implement ships)
- [ ] Cleanup completed

---

## Phase 1 — plan

state.md `phase: plan`. Light by cost vs Phase 2 — a scope-discovery batch (Read + Grep) + 1 baseline validation run + orchestrator-inline smell detection (Medium+) + orchestrator-inline smell evidence (Medium+) + orchestrator plan-build. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-1-plan.md`** — it carries the Steps (§1.1 memory layer load · §1.2 scope discovery, baseline, and coverage check · §1.3 tier classification · §1.4 smell detection · §1.5 smell evidence · §1.6 risk classification, plan build, and approval), and every `Phase 1 §1.M` citation in this skill resolves there. Exit: `phase: apply` once the plan is built and approved (HIGH-risk steps gated), `phase: plan-escalated` on a hard signal or a red baseline, `phase: routed` (terminal) when no tests exist.

---

## Phase 2 — apply

state.md `phase: apply`. The orchestrator executes the approved plan one step at a time, each transformation gated by its own regression run. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-2-apply.md`** — it carries the Steps (§2.1 instruction refresh · §2.2 per-step execution and the Blocked Step Protocol · §2.3 the blocked-ratio escalation (§Budgets) · §2.4 final regression + the retry-exit emit), and every `Phase 2 §2.M` citation in this skill resolves there. Exit: `phase: verify` on a green regression run, `phase: apply-escalated` at the blocked cap, `phase: reverted` when the user reverts.

---

## Phase 3 — verify

state.md `phase: verify`. Diff sanity + independent review + completion summary + L2 emit + cleanup. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-3-verify.md`** — it carries the Steps (§3.1 diff sanity · §3.2 the reviewer batch · §3.3 disposition, including the PRODUCT-DECISION escalation · §3.4 completion summary · §3.5 learnings · §3.6 custom post-verify steps · §3.7 cleanup), and every `Phase 3 §3.M` citation in this skill resolves there. Exit: a terminal state — `done`, `verify-summary-only`, `reverted`, `routed`, or `verify-escalated` when the 1-round fix loop exhausts. No `git push` / `gh pr create`: refactor never ships code, only a working-tree diff and a state-file audit trail.

---

## State file schema

T1.5 state.md at `.geniro/state/refactor/<slug>/state.md`; `approvals[]` categories `refactor_high_step`, `refactor_product_decision`; `effort_tier` ∈ {Trivial, Small, Medium, Big}. `## Plan steps` holds the per-step execution rows (schema at Phase 2 §2.2), distinct from `## Plan` which holds the ordered plan summary. No T2 handoff — diff IS the deliverable. Full frontmatter + body-section schema in `${CLAUDE_PLUGIN_ROOT}/skills/refactor/refactor-reference.md` §2.

---

## Task tracking

Use `TodoWrite` to expose per-phase progress. At skill start, create phase-level todos: Plan, Apply, Verify. During Phase 2, add dynamic per-step todos derived from the approved plan. Mark `in_progress` → `completed` as phases run. At most ONE todo is `in_progress` at a time.

---
