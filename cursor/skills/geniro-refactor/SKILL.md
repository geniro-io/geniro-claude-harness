---
name: geniro-refactor
description: "Use when restructuring code or paying down tech debt with zero behavior change; the working-tree diff is the deliverable, never shipped. Skip for behavior changes (/geniro:implement) or performance (/geniro:review)."
context: main
---
<!-- Generated from skills/refactor/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->


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
- Universal rule: all choice questions use AskQuestion
- ACI per-phase tool surface
- Git constraint
- Memory I/O schedule
- Definition of done
- Phase 1 (plan) · Phase 2 (apply) · Phase 3 (verify)
- State file schema

---

**Runtime portability.** If Codex truncated this file, read it in full from its path first. `${CLAUDE_PLUGIN_ROOT}` is a placeholder Claude Code substitutes into file references, not a shell export — it reads empty in Bash under every host, so an empty probe proves nothing (`CLAUDECODE` marks Claude Code). Resolve the root from the first rung that holds: the ancestor of this file's real path (symlinks followed) containing `.claude-plugin/plugin.json`; a copy of the referenced file beside this one (the Cursor build); a plugin checkout in the workspace. The run's first Bash call prints this file's real directory and checks the rungs against it; echo that output verbatim before anything else (a resolved ladder is bookkeeping: add a degraded-run notice only for a rung that failed), then substitute the resolved root everywhere and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. A path the output does not show did not resolve. Before deciding a step cannot run here, read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` — it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not:** name what is unavailable in your first message, run every phase and gate this skill declares, never let project rules stand in for its decision gates, and take no outward-facing action (ready PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

**Phase bodies** live in sibling files — the pointer sits under each `## Phase N` heading below — Read on entry to that phase and again on any resumption, including after a compaction; state.md `phase:` says which. That Read is the phase's first action and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the phase files hold the gates and helper call sites, so work started before the Read runs outside them.

**Section-reference convention:** bare `§N.M` refs point to Phase sub-sections — `§1.M` in `phase-1-plan.md`, `§2.M` in `phase-2-apply.md`, `§3.M` in `phase-3-verify.md`; `§ <name>` refs name a section inside the cited `_shared` helper. `refactor-reference.md` numbers its own top-level sections 1-3 (State machine / Schema / Spawn template), so any Phase reference there is written `Phase N §N.M` to avoid colliding with those.

---

## Your role — restructure, don't ship

You refactor and validate behavior preservation. Phase 3 ends at a working-tree diff (the deliverable), a chat completion summary and the state.md audit trail; the user's `git commit`, or `/geniro:implement` through its review gate, ships it. Running under a dynamic `Workflow(...)` or ultracode mode does not relax §Git constraint — the reporter boundary, action gate, and state-write rules bind inside every workflow step per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.

---

## Phases overview

1. **Plan** — discover scope, capture a baseline, classify effort tier, detect and filter smells, build and approve the transformation plan.
2. **Apply** — execute the approved plan one step at a time, each transformation gated by its own regression run.
3. **Verify** — diff sanity check, independent review, disposition (fix loop / escalate / document-and-keep), completion summary, and cleanup.

---

## State machine

state.md `phase:` enum: `plan` → `apply` → `verify` → `done` on the happy path, with the escalation states `plan-escalated`, `apply-escalated` (blocked-ratio cap, §Budgets) and `verify-escalated`. The full diagram, the terminal and escalation lists, and how SessionStart recovery treats each: `${CLAUDE_PLUGIN_ROOT}/skills/refactor/refactor-reference.md` §1.

---

## Terminal states

`done`, `verify-summary-only`, `reverted`, `aborted`, `routed`. Within Phase 3 the terminal `phase:` is written exactly once, at the §3.6 point in `phase-3-verify.md`; §3.3 only records the outcome, so a resume before it still runs the summary, emit and post-verify steps. A path that reaches a terminal without entering Phase 3 — a Phase 1 or Phase 2 exit — writes the terminal and then runs §3.7 Cleanup itself, in that order. A `reverted` / `routed` / `aborted` write also carries a `## Termination reason` body line naming what ended the run.

---

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply, with three refactor-specific bindings:

- **Invariant #4 (bounded structured tool results)** — orchestrator-inline execution writes per-step status and blocked-step reasons to state.md `## Plan steps`; total file body capped at ~8K chars via atomic_state_write truncation marker.
- **Invariant #5 (escalation gates, not silent abort)** — the blocked-ratio cap AUQ (§Budgets) + PRODUCT-DECISION always waits for the user.
- **Invariant #7 (errors → structured observations)** — per-step blocked rationale, baseline validation failure, and reviewer CRITICAL findings all become structured `## Tool log` / `## Errors` entries.

This skill adds two invariants:

S1. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

S2. **One todo in_progress at a time.** Expose progress in the todo list: phase-level todos (Plan, Apply, Verify) from skill start, each completed when its phase ends and `in_progress` only while no per-step todo is; in Phase 2, per-step todos from the approved plan, each `in_progress` → `completed` in turn.

**Turn boundaries.** A turn ends in exactly three places: on a fired approval question, on reaching a terminal `phase:` state, or when the user asked something and is owed the answer. Everywhere else the next action follows in the same turn, with a tool call — between steps, after a check comes back green, after a state write, at a phase transition, and when a subagent's result lands. A status report, a checkpoint summary, and a list of what remains are continuations, not endings: write one where it helps the user follow along, then take the next action in that same turn. A decision that needs the user is asked as a real question in the turn that raises it, its render and the question inside that one turn (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard) — a question left in prose, or announced for a later message, leaves the run waiting on an answer the user was never asked for. Reversibility is not the test: a deviation from a rule this run loaded is a gate however cheap it is to undo.

**Compaction.** The host re-attaches only the first portion of this file, so its later sections arrive missing, with a truncation marker standing in for them. Treat that marker as an instruction: in the turn you notice it, re-read this file and the running phase's body before relying on anything the truncation removed. When you compose a compaction summary, record state — what ran, what remains, what the user decided — never a directive to yourself about stopping, confirming, or awaiting direction. A resumed session reads its summary as fact and will honour it over this file, so work still to do is recorded as work still to do, not as something to ask permission for.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This smell is too small to fix" | A smell that survived Phase 1 §1.5's KEEP/FILTER matrix is a vetted target; skipping it after approval reopens the filtering §1.5 centralizes. |
| "I'll batch multiple transformations" | The per-step regression gate (Phase 2 §2.2) isolates behavior drift to the smallest possible unit — a batched failure leaves no way to tell which transformation caused it. |
| "Tests are passing so I'll skip the blocked step protocol" | The protocol exists for the NEXT failure. Follow it — Phase 2 §2.2 Blocked Step Protocol applies to ALL transformations regardless of prior-step success. |
| "This refactoring needs a behavior change" | Then it's not a refactoring. Use `/geniro:implement` instead. The zero-behavior-change guarantee is non-negotiable. |
| "This duplication needs a new shared helper" | Run the Existing Abstraction Audit first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md`. Prefer a small extension of a utility / service / hook that already exists nearby; create a new shared helper only when no analogue exists or extending one would add a parameter or conditional that complicates it (Rule of Three). |
| "All detected smells are real issues" | Generic smell categories flag intentional repo patterns. Without filtering against THIS repo's conventions via Phase 1 §1.5 smell evidence + KEEP/FILTER synthesis matrix, you'll refactor code that was designed that way on purpose. |
| "I noticed a bug mid-refactor, I'll fix it" | That's feature work. Note it for `/geniro:implement` and stay in refactor scope. The zero-behavior-change guarantee applies even when the in-scope behavior is buggy. |
| "Reviewer flagged a `[PRODUCT-DECISION]` finding — I'll route it through the fix loop like any other CRITICAL/HIGH" | A `[PRODUCT-DECISION]` finding has multiple valid resolution paths by definition — picking one is a behavior change, which contradicts refactor's zero-behavior-change guarantee. Phase 3 §3.3 disposition logic ESCALATES PRODUCT-DECISION to `/geniro:implement` (always-WAIT) — never gates-and-fixes them in-skill. |
| "Auto-promote a recorded discovery into a project rule when refactor completes." | The durable output is the learning emitted at Phase 3 §3.5; rule mining is `/geniro:reflect`, which the user invokes — an unasked rule offer interrupts the diff review the run exists to deliver. |
| "The revert step is simpler as `git checkout -- .` / `git restore .`." | A bare pathspec discards every uncommitted change in the tree, including work outside this refactor. Use the targeted form § Git constraint defines; `git stash` reaches the same unrelated work. |
| "PRODUCT-DECISION 3-option AUQ is paternalistic — collapse to 2 options (run /geniro:implement / accept-as-is)." | Phase 3 §3.3 is explicit: 3 fixed options. The Revert path is a user-controlled safety net, and dropping it leaves a user who dislikes the diff with no in-skill way out. Collapsing removes meaningful agency. |

---

## Budgets — quality-first

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Budgets — quality-first (canonical). This skill's own gates:

**Quality gates (escalate to user, do not abort):**

| Gate | Cap | Past threshold |
|---|---|---|
| Per-step retry (orchestrator-inline Blocked Step Protocol) | 3 | Mark BLOCKED, continue to next step |
| Session-level blocked ratio | 30% (post-rejection denominator) | AUQ — keep what worked & escalate / revert / force-continue. User picks. |
| Phase 3 fix-loop | 1 round | Re-spawn reviewer once; if still failing, AUQ (escalate / accept / abort). |
| Reviewer output size | the per-dimension report cap in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output cap | That section's overflow rule (canonical invariant #4). |

**Architecture constraints (design intent, not budget):**

| Constraint | Value |
|---|---|
| Parallel reviewer spawns | 1 independent + N custom reviewers |
| Smell-detection rounds | 1 (orchestrator-inline) |
| Smell-evidence filter rounds | 1 (Medium+ only) |

---

## Subagent model tiering

Spawns are **session** (no `model=`) unless a site names a light class (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Cost classes). Spawn plugin-defined subagents through the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (`geniro:<agent>` under Claude Code → bare `<agent>` where the host lists it → `general-purpose` + agent-file path); cache the resolved rung for the session.

Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site — every Agent prompt satisfies every pre-inlined field, because a spawn missing a field makes the subagent re-discover scope from scratch and drift.

Smell detection and per-step execution run orchestrator-inline (no spawn, no tiering decision). The Phase 3 reviewer-agent and custom reviewers (Medium+ only) are **session**, so the user's session-level `/model` choice propagates.

## Agent failure handling

If a delegated agent fails (timeout, error, empty/garbage result): retry once with the same prompt. If the retry also fails, the **Phase 3 reviewer batch** (reviewer-agent + custom reviewers) is fail-open — note the failure in the completion summary, proceed, and warn the user that independent review did not complete.

---

## Evidence Standard

Cite the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. /geniro:refactor applies it at baseline validation, the per-step regression gate (orchestrator-inline pre/post-check), and the final regression run.

---

## Universal rule: all choice questions use AskQuestion

Route every user-facing choice in this skill through the `AskQuestion` tool per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions, which owns the rule and the reason.

---

## ACI per-phase tool surface

**Phase 1 (Plan):**
- Allowed: Read / Grep / Glob / Bash (read-only — `git status`, `git log`, `git diff`, `git branch --show-current`, test suite invocation for baseline) / the declared memory backend's read tool / AskQuestion.
- Allowed subagent spawns: `codebase-research-agent` (**light (smallest)**) for wide cross-file locator queries during smell detection (Phase 1 §1.4). smell detection + smell evidence otherwise run orchestrator-inline.
- Blocked: production-source writes and edits; git and PR writes per §Git constraint.

**Phase 2 (Apply):**
- Allowed subagent spawns: none. Per-step execution runs orchestrator-inline (Edit + Bash for tests).
- Orchestrator uses Edit / Write / Bash (test cmd) / AskQuestion directly. Per-step regression runs via backpressure helper.
- Blocked at orchestrator level: branch switching; git and PR writes per §Git constraint.

**Phase 3 (Verify):**
- Allowed: Read / Grep / Glob / Bash (`git diff --name-only`, `git diff --stat`, test cmd for re-runs) / AskQuestion / Edit (fix-loop-scoped — the §3.3 1-round CRITICAL/HIGH non-PRODUCT-DECISION fix applies findings inline).
- Allowed subagent spawns: reviewer-agent + custom reviewers (Medium+ only).
- Allowed: targeted per-file revert per § Git constraint — the one orchestration-level exception to the git-write ban. Blocked: every other git and PR write.

**All reviewer / custom reviewer spawns are pure read-only:** tool whitelist via `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` frontmatter (Read / Grep / Glob / Bash for read-only checks).

---

## Git constraint

Do not run `git add`, `git commit`, `git push` or `gh pr create`; the orchestrating workflow handles version control. Exception: revert applied work in Phase 2 / Phase 3 with a targeted `git restore --source=HEAD -- <paths>`, where `<paths>` is the aggregated `files_affected` from state.md's executed `## Plan steps` rows (plus, in Phase 3, any path a fix-loop finding touched) — never `git diff --name-only`, which would also sweep up any unrelated uncommitted work already in the tree (Phase 1 §1.2 does not require a clean working tree before scope discovery starts). Never reach for a bare `.` or `*` pathspec (`git checkout -- .` / `git restore .`): the mass-discard form wipes every uncommitted change, including work outside this refactor entirely.

---

## Memory I/O schedule

| Phase | Helper | Direction | MODE |
|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` |
| Phase 1 entry | `load-semantic` | read L3 | n/a |
| Phase 1 entry | `query-learnings` | read L2 | n/a |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a |
| Phase 1 entry (conditional) | spec.md frontmatter `workflow_refs[]` | read external | fires only when `$ARGUMENTS` points to spec.md or task-dir; cached tracker `status` primes scope decisions |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` (single re-fire) |
| Phase 3 entry | `load-custom-instructions` | read L4 | `refresh` (single re-fire) |
| Phase 2 exit (conditional) | `emit-learning` | write L2 | n/a (type `retry_failure_sequence`; trigger per Phase 2 §2.4) |
| Phase 3 exit | `emit-learning` | write L2 | n/a (emit types: `discovery` with `ext.{area, insight}` OR `pitfall` with `ext.{trap, mitigation}`) |

---

## Definition of done

`${CLAUDE_PLUGIN_ROOT}/skills/refactor/refactor-definition-of-done.md` carries the load-bearing exit gates and safety invariants, including the no-ship boundary; walk it before the terminal `phase:` write.

---

## Phase 1 — plan

state.md `phase: plan`. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-1-plan.md`** — the Steps §1.0-§1.6; every `Phase 1 §1.M` citation resolves there. Exit: `phase: apply` once the plan is built and approved (HIGH-risk steps gated), `phase: plan-escalated` on a hard signal or a red baseline, `phase: routed` (terminal) when no tests exist, `phase: done` (terminal) when no smell is worth keeping.

---

## Phase 2 — apply

state.md `phase: apply`. The orchestrator executes the approved plan one step at a time, each transformation gated by its own regression run. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-2-apply.md`** — the Steps §2.1-§2.4; every `Phase 2 §2.M` citation resolves there. Exit: `phase: verify` on a green regression run, `phase: apply-escalated` at the blocked cap, `phase: reverted` when the user reverts.

---

## Phase 3 — verify

state.md `phase: verify`. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-3-verify.md`** — the Steps §3.1-§3.7; every `Phase 3 §3.M` citation resolves there. Exit: a terminal state — `done`, `verify-summary-only`, `reverted`, `aborted`, or `routed` — or the paused escalation state `verify-escalated` when the 1-round fix loop exhausts.

---

## State file schema

T1.5 state.md at `.geniro/state/refactor/<slug>/state.md` (resumed or created at Phase 1 §1.0); `approvals[]` categories `refactor_high_step`, `refactor_product_decision`; `effort_tier` ∈ {unset, Trivial, Small, Medium, Big}. `## Plan steps` holds the per-step execution rows (schema at Phase 2 §2.2), distinct from `## Plan` which holds the ordered plan summary. No T2 handoff — diff IS the deliverable. Full frontmatter + body-section schema in `${CLAUDE_PLUGIN_ROOT}/skills/refactor/refactor-reference.md` §2.

---
