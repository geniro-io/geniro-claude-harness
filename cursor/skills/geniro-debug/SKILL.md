---
name: geniro-debug
description: "Use when a bug needs systematic root-cause investigation: hypothesize, test, isolate, reproduce, then hand the fix to /geniro:implement. Adversarial mode (verify-changes) writes failing tests for a diff. Skip for obvious causes (/geniro:implement)."
context: main
---
<!-- Generated from skills/debug/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->


# Debug: scientific-method investigation

## Contents

- Your role — investigate, don't ship
- State machine
- Loop invariants
- Anti-rationalization
- Budgets — quality-first
- Subagent model tiering
- Definition of done
- State file schema
- Phase 0 (mode detection) · Phase 1 (investigate) · Phase 2 (propose) · Phase 3 (ship) · Adversarial Mode
- Task execution entry / state recovery
- REFERENCE

---

**Runtime portability.** If Codex cut this file at 8,000 bytes, read it in full from its path first. `${CLAUDE_PLUGIN_ROOT}` is a placeholder Claude Code substitutes into file references, not a shell export — it reads empty in Bash under every host, so an empty probe proves nothing (`CLAUDECODE` marks Claude Code). Resolve the root from the first rung that holds: the ancestor of this file's real path (symlinks followed) containing `.claude-plugin/plugin.json`; a copy of the referenced file beside this one (the Cursor build); a plugin checkout in the workspace. The run's first Bash call prints this file's real directory and checks the rungs against it; echo that output verbatim before anything else (a resolved ladder is bookkeeping: add a degraded-run notice only for a rung that failed), then substitute the resolved root everywhere and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. A path the output does not show did not resolve. Before deciding a step cannot run here, read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` — it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not:** name what is unavailable in your first message, run every phase and gate this skill declares, never let project rules stand in for its decision gates, and take no outward-facing action (ready PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

**Progressive load.** This file is the spine — role, invariants, gates, budgets. Each phase's Steps and tool surface live in a sibling file you Read on entry to that phase; the phase sections below carry the paths. That Read is the phase's physically-first action and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the phase files hold this skill's gates and its helper call sites, so work started before the Read runs outside them.

**`phase:` → phase file, for a post-compaction resume that can no longer see the phase sections below:**

| `phase:` value | Read |
|---|---|
| `mode-detect` | `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-0-mode-detect.md` |
| `investigate`, `phase-1-escalated`, `phase-1-verification-stalled` | `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-1-investigate.md` |
| `propose`, `phase-2-escalated` | `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-2-propose.md` |
| `ship` | `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-3-ship.md` |
| `adversarial-mode-detect`, `adversarial-investigate`, `adversarial-ship` | `${CLAUDE_PLUGIN_ROOT}/skills/debug/adversarial-mode.md` |

**Section-reference convention.** A bare `§N.M` names a sub-step of Phase N and lives in that phase's file (`${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-N-*.md`), never in this spine. A `§N` written after a file path names that file's own top-level section.

---

## Your role — investigate, don't ship

You investigate. You isolate. You propose. You do not apply the fix. Phase 3 handoff is a text proposal + reproduction test on disk + a handoff file at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`. Downstream consumers (`/geniro:implement`, manual user action) apply the patch.

---

## State machine

state.md `phase:` enum: `mode-detect` → `investigate` → `propose` → `ship` → `done` (Scientific Mode happy path). Terminal states: `done`, `ship-summary-only`, `aborted`, `adversarial-aborted`, `adversarial-ship-summary-only` (SessionStart recovery treats these as complete). Escalation states: `phase-1-escalated`, `phase-1-verification-stalled`, `phase-2-escalated` (recovery surfaces "task was paused — your previous options:" so user re-picks without losing context). Adversarial Mode runs a parallel chain (`adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship` → `done` | `adversarial-ship-summary-only`).

ASCII state diagram + recovery rules in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §1.

---

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply, with debug-specific bindings:

- **Invariant #3 (permission before side-effect)** — /geniro:debug performs NO `git push` / `gh pr create`; the no-ship boundary holds under a dynamic `Workflow(...)` or ultracode mode too, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.
- **Invariant #4 (bounded results)** — Adversarial Mode's authored-test output is bounded per `${CLAUDE_PLUGIN_ROOT}/skills/debug/adversarial-mode.md` §A4 step 3, which owns the hard cap and the hypothesis-generation stop rule; finding schema per that file's §A6.
- **Invariant #5 (escalation gates)** — stall gate (§1.7) + fix-fail gate (§2.5) escalate via AUQ; never fabricate a conclusion.
- **Invariant #6 (grounded in observations)** — a hypothesis is **confirmed** only when its `Result:` field in `## Hypotheses` cites an artifact from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` § What counts as an artifact. That standard also binds every fix-verification and reproduction-test capture: reasoning is correlation, and only reproduction with a captured artifact confirms causation.

This skill adds one invariant:

S1. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**Turn boundaries.** A turn ends in exactly three places: on a fired approval question, on reaching a terminal `phase:` state, or when the user asked something and is owed the answer. Everywhere else the next action follows in the same turn, with a tool call — between steps, after a check comes back green, after a state write, at a phase transition, and when a subagent's result lands. A status report, a checkpoint summary, and a list of what remains are continuations, not endings: write one where it helps the user follow along, then take the next action in that same turn. A decision that needs the user is asked as a real question in the turn that raises it, its render and the question inside that one turn (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard) — a question left in prose, or announced for a later message, leaves the run waiting on an answer the user was never asked for. Reversibility is not the test: a deviation from a rule this run loaded is a gate however cheap it is to undo.

**Compaction.** The host re-attaches only an initial slice of this file, so its later sections arrive missing, with a truncation marker standing in for them. Treat that marker as an instruction: in the turn you notice it, re-read this file and the running phase's body before relying on anything the truncation removed. When you compose a compaction summary, record state — what ran, what remains, what the user decided — never a directive to yourself about stopping, confirming, or awaiting direction. A resumed session reads its summary as fact and will honour it over this file, so work still to do is recorded as work still to do, not as something to ask permission for.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "It's probably a cache issue" — guess and code | Guesses waste time. Form a hypothesis, then test it with evidence per Evidence Standard. |
| "The fix is one line, I'll just write it and escalate nothing" | /geniro:debug never applies code. Even one-line fixes go through `/geniro:implement` — the review gate still applies and the reproduction test ships with the fix as the regression guard. |
| "I added experimental logging and while I'm here I'll patch the bug too" | Experiments and fixes are separate deliverables. Phase 2 mandates: revert experimental edits to non-test source; escalate the proposed patch as text. /geniro:implement applies the real fix cleanly. |
| "Changes look fine, I'll skip adversarial mode" | "Looks fine" is the attacker's favorite surface. If user asked for verify-changes, run the adversarial pass — a zero-red-tests outcome is still a valid deliverable. |
| "I'll reason about edges instead of authoring tests" | Reasoning is reviewer-mindset. Adversarial mode AUTHORS executable failing tests because reasoning misses what running code catches. |
| "This test would obviously fail — I don't need to actually run it before counting it" | Reasoning from the diff is not F→P. Adversarial Mode authors a test AND runs it to a real assertion failure before counting it (A4 step 3) — a test never observed red is not a finding. Same rule applies to scientific-mode hypothesis confirmation — re-run the test / re-read the file:line / re-execute the query yourself before advancing to Isolate. |
| "The findings are in state.md, I'll just ask the escalation question" | state.md is a scratchpad, not a user-facing report. §3.1 requires an explicit findings summary in chat AND persisted to `from-debug-<branch>.md` before the escalation AUQ. The state file IS the handoff channel — inlining the summary into the escalation command lets copies drift. |
| "The hypothesis matches the symptom — that's confirmation" | Symptom-matching is correlation, not causation. Confirmation requires a captured artifact per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` § What counts as an artifact. |
| "I have no DB / log / production access — mark this hypothesis inconclusive" | No-access-by-default is the same fabrication shortcut as inconclusive-by-default: a limit on your own reach is a claim and carries the same artifact requirement (Evidence Standard). Attempt the read with the tools you have and capture what fails; the §1.5 missing-data gate opens on that captured failure. Handing the user a manual checklist your own shell answers in seconds skips the probe that would have settled it. |
| "I have a script / curl / query that reproduces the bug, that's enough" | Scripts get deleted at §3.4 Cleanup and leave no regression guard. §2.4 mandates the reproduction be authored as a unit/integration test in the project's framework. Escape hatch (Reproduction Decision) is opt-in for genuinely non-reproducible cases only. |
| "Per protocol I should ask via AskQuestion, but this specific intermediate question isn't in the enumerated gates — I'll inline (A)/(B) in chat" | Every user-facing choice in this skill routes through the `AskQuestion` tool (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions owns the rule) — the enumerated gates are examples, not the complete set. An inline `(A)/(B)` leaves no structured answer for the resume hook to restore. If you catch yourself rationalizing "but this case is different / needs runtime confirmation / is just a quick check" — stop and call the tool. |
| "I'll name the reproduction test after the confirmed hypothesis number from `## Hypotheses`" | state.md gets deleted at Cleanup; the test ships with the fix. A name like `Bug C` or `Hypothesis 2 reproduction` is meaningless to whoever reads the test in CI weeks later. §2.4 mandates: describe the bug behavior, not the thread-local label. |
| "I see two valid fixes for this root cause — I'll just pick one and write the text proposal" | §2.2 multi-path fix gate (Always-WAIT) requires AskQuestion whenever the root cause has more than one valid fix path with real trade-offs. Single-text-proposal default applies ONLY when there is one obvious right fix. |
| "Self-fix indefinitely until verify passes." | §2.5 fix-loop escalation bounds the fix-attempt count and, past it, escalates AUQ ("Try different approach" / "Accept as documented limitation" / "Abort"). "Kick it until it passes" is an anti-pattern that wastes budget on a hypothesis that needs revisiting. |

---

## Budgets — quality-first

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Budgets — quality-first (canonical).

**Quality gates (escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Inconclusive hypothesis tests | per §1.7 | stall gate | AUQ — diagnose-by-missing-component → user supplies missing or picks alternative |
| Fix attempts failed verification | per §2.5 | fix-loop gate | AUQ — try different approach / accept as documented limitation / abort. User picks. |
| Adversarial mode authored tests | per A4 step 3 | A4 step 3 (hypothesis-authoring loop) | Stop authoring; surface findings |
| Adversarial mode consecutive discards | per A4 step 3 | A4 step 3 (hypothesis-authoring loop) | Stop hypothesis generation; surface partial |

---

## Subagent model tiering

OMIT `model=` at every plugin-agent spawn site, per the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Spawn plugin-defined subagents through the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (`geniro:<agent>` under Claude Code → bare `<agent>` where the host lists it → `general-purpose` with agent body inlined); cache the resolved rung for the rest of the session.

Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site — every Agent prompt satisfies every pre-inlined field, because a spawn missing a field makes the subagent re-discover scope from scratch and drift.

| Spawn | When |
|---|---|
| `codebase-research-agent` | Phase 1 codebase mapping / flow tracing / definition lookups (Loop Invariant S1). Targeted file:line reads tied to a specific hypothesis stay orchestrator-inline (Read / Grep / Glob). |
| `finding-verifier-agent` | Phase 1 §1.6, always-on — re-verifies the confirmed root cause cold before Phase 2 opens; single spawn, never a fan-out. |

---

## Definition of done

The full per-mode checklists live with their mode — Scientific Mode in `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-3-ship.md`, Adversarial Mode in `${CLAUDE_PLUGIN_ROOT}/skills/debug/adversarial-mode.md`. Read the matching one before declaring completion.

Four gates are cross-cutting — they bind from Phase 1 onward, not only at the exit, so they are stated here rather than only in the phase file that checks them:

- [ ] **The no-ship boundary held.** A proposed fix is a text patch, never applied to source.
- [ ] **Every experimental edit to non-test source was reverted before handoff.** Authored *tests* are the exception in Adversarial Mode — they stay on disk.
- [ ] **The root cause is cited per the Evidence Standard, not guessed** — tagged `[ROOT-CAUSE]`, or honestly `[SYMPTOM]` / `[UNKNOWN]` when it is not established.
- [ ] **The findings handoff was persisted via `atomic_state_write_cmd` through `redact_secrets` BEFORE the escalation question fired** — an unpersisted handoff is lost if the user aborts at the gate.

## State file schema

T1.5 state.md frontmatter (categories `branch_freshness`, `disambiguate_mode`, `multi_path_fix`, `verification_stalled`, `existing_fix_pr`, `debug_workspace_setup` for `approvals[]`) + body sections (Scientific Mode + Adversarial Mode); T2 handoff schemas for `from-debug-<branch>.md` and `from-debug-adversarial-<branch>.md` including the `open_questions[]` contract — full schemas in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2.

`open_questions[]` entries carry `status: unresolved | resolved | wontfix`; an `unresolved` entry blocks the Phase 3 escalation until the §3.0 pre-gate clears it.

---

## Phase 0 — mode detection ($ARGUMENTS routing)

state.md `phase: mode-detect`. Loads custom instructions, records the starting working-tree state, decides where the investigation runs, checks branch freshness, and routes `$ARGUMENTS` to Scientific Mode or Adversarial Mode.

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-0-mode-detect.md`** — Steps, routing table, anchored verify-keyword signals, this phase's tool surface.

---

## Phase 1 — investigate

state.md `phase: investigate`. An entry-gate + context load plus an inner hypothesis-test loop.

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-1-investigate.md`** — Steps 1.1-1.7, the missing-data and stall gates, infrastructure-cause guidance, isolation techniques, this phase's tool surface and exit condition.

---

## Phase 2 — propose

state.md `phase: propose`. Output authoring: text fix proposal + F→P reproduction test. **No production-source edits applied.**

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-2-propose.md`** — Steps 2.1-2.5, the multi-path fix gate, the monkey-patch verification contract, this phase's tool surface and exit condition.

---

## Phase 3 — ship

state.md `phase: ship`. Findings handoff to downstream skill OR user-handles — proposals + tests authored locally (no-ship boundary per § Your role).

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-3-ship.md`** — Steps 3.0-3.4, the Debug Findings template, the cleanup contract, this phase's tool surface and exit condition, and the Scientific-Mode Definition of done.

---

## Adversarial Mode (verify-changes)

state.md `mode: adversarial`. Phases: `adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship`. Parallel to Scientific Mode; shared Phase 0 routes here on anchored verify-keyword signals (Phase 0 above).

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/debug/adversarial-mode.md`** — A1-A7 (purpose, diff resolution, skip conditions, RED-phase workflow, handoff persistence, findings template, cleanup), this mode's tool surface and exit condition, and its Definition of done.

---

## Task execution entry / state recovery

State file: `.geniro/state/debug/<slug>/state.md` (T1.5, `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules). On entry, glob for it; if present, validate via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` before acting on it, then route per the helper's § Consumer contract and resume from the persisted `phase:` value. No state file found → fresh run, proceed to Phase 0. Write each phase transition through `atomic_state_set_field`; a terminal phase (§ State machine) is final.

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` — state diagram, state/handoff schemas, infrastructure reference, stall taxonomy, adversarial templates, open-PR scan, emit payload shapes (see its own Contents).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` § Investigation-driven fix gate (debug-flavored) — multi-path fix gate and repro-infeasible escape hatch.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` — consumer protocol for downstream skills reading the handoffs this skill writes.
