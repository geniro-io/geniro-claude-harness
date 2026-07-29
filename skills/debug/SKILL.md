---
name: debug
description: "Use when a bug needs systematic investigation. 3-phase loop (Investigate → Propose → Ship) mirroring /geniro:implement: observe → hypothesize → test → isolate → propose fix → author reproduction test, then escalate to /geniro:implement with a handoff file at .geniro/state/handoff/from-debug-<branch>.md. Adversarial mode authors F→P tests against a diff (verify-changes). Skip for bugs with obvious root cause — go straight to /geniro:implement."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, Workflow]
argument-hint: "[bug description | verify <diff-range> | verify last changes] [--deep]"
---

# Debug: scientific-method investigation

## Contents

- Your role — investigate, don't ship
- State machine
- Loop invariants
- Universal rule: all choice questions use AskUserQuestion
- Anti-rationalization
- Budgets — quality-first
- Subagent model tiering
- Evidence Standard
- Definition of done
- ACI per-phase tool surface
- Memory I/O schedule
- State file schema
- Phase 0 (mode detection) · Phase 1 (investigate) · Phase 2 (propose) · Phase 3 (ship) · Adversarial Mode
- REFERENCE

---

Use this skill to systematically debug complex issues. Replaces guessing with evidence gathering and hypothesis testing across 3 phases.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference: the plugin root is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. Tool and hook substitutions for non-Claude-Code runtimes: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md`.

**Progressive load.** This file is the spine — role, invariants, gates, budgets, tool surface. Each phase's Steps live in a sibling file you Read on entry to that phase; the phase sections below carry the paths.

**Section-reference convention.** A bare `§N.M` names a sub-step of Phase N and lives in that phase's file (`${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-N-*.md`), never in this spine. A `§N` written after a file path names that file's own top-level section.

---

## Your role — investigate, don't ship

You investigate. You isolate. You propose. You do NOT apply the fix. Phase 3 handoff is a text proposal + reproduction test on disk + a handoff file at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`. Downstream consumers (`/geniro:implement`, manual user action) apply the patch.

---

## State machine

state.md `phase:` enum: `mode-detect` → `investigate` → `propose` → `ship` → `done` (Scientific Mode happy path). Terminal states: `done`, `ship-summary-only`, `aborted`, `adversarial-aborted` (SessionStart recovery treats these as complete). Escalation states: `phase-1-escalated`, `phase-2-escalated` (recovery surfaces "task was paused — last AUQ options:" so user re-picks without losing context). Adversarial Mode runs a parallel chain (`adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship` → `done`).

Full ASCII state diagram + non-terminal recovery rules in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §1.

---

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply, with debug-specific bindings:

- **Invariant #3 (permission before side-effect)** — /geniro:debug performs NO `git push` / `gh pr create`; the no-ship boundary holds under a dynamic `Workflow(...)` or ultracode mode too, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.
- **Invariant #4 (bounded results)** — `adversarial-tester-agent` output is bounded by the hard cap on authored tests its own contract declares (`${CLAUDE_PLUGIN_ROOT}/agents/adversarial-tester-agent.md`); finding schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.
- **Invariant #5 (escalation gates)** — stall gate (5 inconclusive) + fix-fail gate (2 attempts) escalate via AUQ; never fabricate a conclusion.
- **Invariant #6 (grounded in observations)** — every `Result:` field in `## Hypotheses` cites a captured artifact per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` (§ Evidence Standard below carries the confirmation bar).

This skill adds one invariant:

8. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**Turn-completion check.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check at every gate — the render is followed immediately by its lean `AskUserQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard.

`## Tool log` schema: typical run produces 0-3 entries (subagent-spawn outcomes for adversarial mode, stall/fix-fail escalation entries). Routine Read / Edit / Bash skipped. **Deep mode** (opt-in, default off): `--deep` (or the Phase 0 Debug-depth chooser when `--deep` is absent) deepens Phase 1 hypothesis generation (3× fan-out + dedup) and Phase 2 fix/reproduction verification (3 verifiers, majority vote) per `${CLAUDE_PLUGIN_ROOT}/skills/debug/deep-mode-reference.md` — higher quality at higher token cost, no change to gates or the no-ship boundary.

---

## Universal rule: all choice questions use AskUserQuestion

Route every user-facing choice in this skill through the `AskUserQuestion` tool per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions, which owns the rule and the reason. The gates enumerated below are this skill's, not the complete set; the anti-rationalization row below carries why.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "It's probably a cache issue" — guess and code | Guesses waste time. Form a hypothesis, then test it with evidence per Evidence Standard. |
| "The fix is one line, I'll just write it and escalate nothing" | /geniro:debug never applies code. Even one-line fixes go through `/geniro:implement` — the review gate still applies and the reproduction test ships with the fix as the regression guard. |
| "I added experimental logging and while I'm here I'll patch the bug too" | Experiments and fixes are separate deliverables. Phase 2 mandates: revert experimental edits to non-test source; escalate the proposed patch as text. /geniro:implement applies the real fix cleanly. |
| "Changes look fine, I'll skip adversarial mode" | "Looks fine" is the attacker's favorite surface. If user asked for verify-changes, run the adversarial pass — a zero-red-tests outcome is still a valid deliverable. |
| "I'll reason about edges instead of authoring tests" | Reasoning is reviewer-mindset. Adversarial mode AUTHORS executable failing tests because reasoning misses what running code catches. |
| "The agent reported F→P, I'll trust it" | Orchestrator MUST independently re-run authored tests (A4 step 4). Self-reported F→P is evidence, not proof. Same rule applies to scientific-mode hypothesis confirmation — re-run the test / re-read the file:line / re-execute the query yourself before advancing to Isolate. |
| "The findings are in state.md, I'll just ask the escalation question" | state.md is a scratchpad, not a user-facing report. §3.1 requires an explicit findings summary in chat AND persisted to `from-debug-<branch>.md` before the escalation AUQ. The state file IS the handoff channel — inlining the summary into the escalation command lets copies drift. |
| "The hypothesis matches the symptom — that's confirmation" | Symptom-matching is correlation, not causation. Confirmation requires a captured artifact per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` § What counts as an artifact. |
| "I have no DB / log / production access — mark this hypothesis inconclusive" | No-access-by-default is the same fabrication shortcut as inconclusive-by-default: a limit on your own reach is a claim and carries the same artifact requirement (Evidence Standard). Attempt the read with the tools you have and capture what fails; the §1.5 missing-data gate opens on that captured failure. Handing the user a manual checklist your own shell answers in seconds skips the probe that would have settled it. |
| "I have a script / curl / query that reproduces the bug, that's enough" | Scripts get deleted at §3.5 Cleanup and leave no regression guard. §2.4 mandates the reproduction be authored as a unit/integration test in the project's framework. Escape hatch (Reproduction Decision) is opt-in for genuinely non-reproducible cases only. |
| "Per protocol I should ask via AskUserQuestion, but this specific intermediate question isn't in the enumerated gates — I'll inline (A)/(B) in chat" | The Universal Rule above makes the tool mandatory for ANY choice question — the enumerated gates are examples, not the complete set. An inline `(A)/(B)` leaves no structured answer for the resume hook to restore. If you catch yourself rationalizing "but this case is different / needs runtime confirmation / is just a quick check" — stop and call the tool. |
| "I'll name the reproduction test after the confirmed hypothesis number from `## Hypotheses`" | state.md gets deleted at Cleanup; the test ships with the fix. A name like `Bug C` or `Hypothesis 2 reproduction` is meaningless to whoever reads the test in CI weeks later. §2.4 mandates: describe the bug behavior, not the thread-local label. |
| "I see two valid fixes for this root cause — I'll just pick one and write the text proposal" | §2.2 multi-path fix gate (Always-WAIT) requires AskUserQuestion whenever the root cause has more than one valid fix path with real trade-offs. Single-text-proposal default applies ONLY when there is one obvious right fix. |
| "Bypass `git guardrail` hooks if a needed `git bisect` step blocks." | Hooks fail for a reason. `git bisect` is permitted (read-only investigation per § ACI per-phase). If a specific guardrail blocks legitimate debug work, the path is `.geniro/safety.json` allow_patterns, not `--no-verify`. |
| "Self-fix indefinitely until verify passes." | §2.5 fix-loop escalation bounds to 2 fix attempts. Past 2, escalate AUQ ("Try different approach" / "Accept as documented limitation" / "Abort"). "Kick it until it passes" is an anti-pattern that wastes budget on a hypothesis that needs revisiting. |

---

## Budgets — quality-first

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Budgets — quality-first (canonical). Deep hypothesis-driven investigation merits a strong session tier; the skill inherits the session's model (see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`).

**Quality gates (escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Inconclusive hypothesis tests | 5 across all hypotheses | stall gate | AUQ — diagnose-by-missing-component → user supplies missing or picks alternative |
| Fix attempts failed verification | 2 | fix-loop gate | AUQ — try different approach / accept as documented limitation / abort. User picks. |
| Adversarial mode authored tests | 10 hard cap | (delegated to agent contract) | Stop authoring; surface findings |
| Adversarial mode consecutive discards | 5 | (delegated to agent contract) | Stop hypothesis generation; surface partial |

**Architecture constraints (design intent, not budget):**

| Constraint | Value |
|---|---|
| Subagent spawns | `codebase-research-agent` (Phase 1 codebase mapping, on demand) + `adversarial-tester-agent` (adversarial mode only) |
| Reproduction-test framework | Project's native (detected from CLAUDE.md Essential Commands) |

---

## Subagent model tiering

OMIT `model=` at every plugin-agent spawn site, per the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Spawn plugin-defined subagents through the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (`geniro:<agent>` → bare `<agent>` → `general-purpose` with agent body inlined); cache the resolved rung for the rest of the session.

Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site — every Agent prompt satisfies the six pre-inlined fields, because a spawn missing a field makes the subagent re-discover scope from scratch and drift.

| Spawn | When |
|---|---|
| `codebase-research-agent` | Phase 1 codebase mapping / flow tracing / definition lookups (Loop Invariant #8). Targeted file:line reads tied to a specific hypothesis stay orchestrator-inline (Read / Grep / Glob). |
| `adversarial-tester-agent` | Adversarial mode test authoring. The agent's F→P verification + 3× flake check enforce correctness regardless of inherited tier. |

---

## Evidence Standard

Cite the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` — schema, forbidden phrases, and the artifact kinds are defined there. This skill applies that standard at every hypothesis-confirmation, fix-verification, and reproduction-test capture.

**Debug-specific framing — hypothesis confirmation.** A hypothesis is **confirmed** only when its `Result:` field cites an artifact from that file's § What counts as an artifact. Hypothesis-tracking is the most evidence-rigorous flow in the plugin: reasoning is correlation; only reproduction with a captured artifact confirms causation.

---

## Definition of done

The full per-mode checklists live with their mode — Scientific Mode in `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-3-ship.md`, Adversarial Mode in `${CLAUDE_PLUGIN_ROOT}/skills/debug/adversarial-mode.md`. Read the matching one before declaring the run complete.

Four gates are cross-cutting — they bind from Phase 1 onward, not only at the exit, so they are stated here rather than only in the phase file that checks them:

- [ ] **The no-ship boundary held.** A proposed fix is a text patch, never applied to source.
- [ ] **Every experimental edit to non-test source was reverted before handoff.** Authored *tests* are the exception in Adversarial Mode — they stay on disk.
- [ ] **The root cause is cited per the Evidence Standard, not guessed** — tagged `[ROOT-CAUSE]`, or honestly `[SYMPTOM]` / `[UNKNOWN]` when it is not established.
- [ ] **The findings handoff was persisted via `atomic_state_write` BEFORE the escalation question fired** — an unpersisted handoff is lost if the user aborts at the gate.

## ACI per-phase tool surface

**Phase 0 (Mode Detect):**
- Allowed: Read / Bash (read-only — `git branch --show-current`, `git rev-parse`; plus `atomic_state_write` to persist the mode/depth pick) / AskUserQuestion (the mode + depth gate).
- Explicitly blocked: any Edit/Write to project files, any ship/side-effect tool (`git commit`, `git push`, `gh pr create`).

**Phase 1 (Investigate):**
- Allowed: Read / Grep / Glob / Bash (read-only — `git status`, `git log`, `git diff`, `git blame`, `git bisect`, read-only `gh pr list` / `gh pr view` / `gh pr diff` for the Phase 1 open-PR scan, test re-runs without code edits, log inspection, profiler invocations, third-party CLI like `psql -c` against test DB if configured).
- Allowed: Edit / Write for EXPERIMENTS only — debug scripts, logging statements, scratch test files, `.geniro/state/debug/<slug>/` artifacts.
- Allowed Agent spawns: `codebase-research-agent` for codebase mapping / flow tracing (Loop Invariant #8); `knowledge-retrieval-agent` scoped `learnings-backend` (§1.1, only under a declared memory-backend block). `Workflow(...)` for the deep-mode hypothesis fan-out (§1.4, `deep-mode: true` only).
- Explicitly blocked: production-source Edit/Write, `git push`, `gh pr create`, branch switching without user confirmation.

**Phase 2 (Propose):**
- Allowed: Read / Grep / Glob / Bash (read-only + experimental test runs).
- Allowed: Edit / Write for reproduction test authoring + experimental monkey-patches.
- Allowed: `Workflow(...)` for the deep-mode 3-verifier majority vote (§2.4, `deep-mode: true` only). No Agent spawns.
- Explicitly blocked: production-source Edit/Write outside the reproduction test file, `git commit`, `git push`, `gh pr create`.

**Phase 3 (Ship):**
- Allowed: Read / Write (T2 handoff persistence via `atomic_state_write`), `emit-learning` helper invocation, `AskUserQuestion`.
- Explicitly blocked: `git commit`, `git push`, `gh pr create`, Agent spawns. Debug stops before shipping — pushing and PR creation are the consumer skill's job (`/geniro:implement`).

**Adversarial Mode (A4 spawn):**
- `adversarial-tester-agent` runs under the spawn-agent ladder.
- Agent's tool surface inherited via the agent's frontmatter (owned by `${CLAUDE_PLUGIN_ROOT}/agents/adversarial-tester-agent.md`).
- Orchestrator's re-verification step uses read-only Bash (run test command).

**Existing safety layer** applies across ALL phases: file-protection hook, git-guardrail hook, `.geniro/` deletion guard (`${CLAUDE_PLUGIN_ROOT}/HOOKS.md`). Runtime denies stay enforced regardless of ACI doc.

---

## Memory I/O schedule

| Phase | Helper | Direction | MODE |
|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` |
| Phase 1 entry | `query-learnings` | read L2 | n/a |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a |
| Phase 1 entry (conditional) | spec.md frontmatter `workflow_refs[]` | read external | fires only when `$ARGUMENTS` points to spec.md or task-dir; cached tracker `status` primes hypotheses, and on `m5-v3` the cached parent-epic and sibling statuses do too |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` (single re-fire) |
| Phase 1 (per rejection) | `emit-learning` | write L2 | n/a (type `discarded_hypothesis` — §1.5) |
| Phase 2 exit (conditional) | `emit-learning` | write L2 | n/a (type `retry_failure_sequence` — §2.5) |
| Phase 3 exit | `emit-learning` | write L2 | n/a (type `diagnosis` — §3.3) |

`update-semantic` is not called. Debug investigates existing code; it does not add modules, move files, or rename — those are /geniro:implement and /geniro:refactor concerns.

---

## State file schema

T1.5 state.md frontmatter (categories `disambiguate_mode`, `multi_path_fix`, `deep_mode_choice`, `existing_fix_pr` for `approvals[]`; `deep-mode: <true|false>` — set by the `--deep` flag or the Phase 0 Debug-depth chooser, missing reads as false) + body sections (Scientific Mode + Adversarial Mode); T2 handoff schemas for `from-debug-<branch>.md` and `from-debug-adversarial-<branch>.md` including the `open_questions[]` contract — full schemas in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2.

`open_questions[]` entries carry `status: unresolved | resolved | wontfix`; an `unresolved` entry blocks the Phase 3 escalation until the §3.0 pre-gate clears it.

---

## Phase 0 — mode detection ($ARGUMENTS routing)

state.md `phase: mode-detect`. Loads custom instructions, checks branch freshness, resolves debug depth, and routes `$ARGUMENTS` to Scientific Mode or Adversarial Mode.

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-0-mode-detect.md`** — Steps, routing table, anchored verify-keyword signals. Exits when the mode is picked and persisted to `approvals[]`: Scientific → `phase: investigate`, Adversarial → `phase: adversarial-mode-detect`.

---

## Phase 1 — investigate

state.md `phase: investigate`. An entry-gate + context load plus an inner hypothesis-test loop. Exits to Phase 2 only when a hypothesis is confirmed AND its Result: field cites an artifact per Evidence Standard.

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-1-investigate.md`** — Steps 1.1-1.7, the missing-data and stall gates, infrastructure-cause guidance, isolation techniques.

---

## Phase 2 — propose

state.md `phase: propose`. Output authoring: text fix proposal + F→P reproduction test. **No production-source edits applied.** Exits to Phase 3 when fix proposal AND reproduction test are both verified.

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-2-propose.md`** — Steps 2.1-2.5, the multi-path fix gate, the monkey-patch verification contract.

---

## Phase 3 — ship

state.md `phase: ship`. Findings handoff to downstream skill OR user-handles — proposals + tests authored locally (no-ship boundary per § Your role, § ACI per-phase).

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-3-ship.md`** — Steps 3.0-3.6, the Debug Findings template, the cleanup contract, and the Scientific-Mode Definition of done. The handoff is persisted via `atomic_state_write` BEFORE the escalation `AskUserQuestion` fires, and every `open_questions[]` entry reaches `resolved` or `wontfix` first.

---

## Adversarial Mode (verify-changes)

state.md `mode: adversarial`. Phases: `adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship`. Parallel to Scientific Mode; shared Phase 0 routes here on anchored verify-keyword signals (Phase 0 above).

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/debug/adversarial-mode.md`** — A1-A6 (purpose, diff resolution, skip conditions, RED-phase workflow, spawn template, findings template) and this mode's Definition of done. Zero surviving red tests is a valid deliverable: terminal `adversarial-aborted`.

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` — state diagram (§1), state.md + handoff schemas (§2), infrastructure checklist (§3), isolation procedures (§4), stall taxonomy table (§5), adversarial spawn + findings templates (§6), worked examples — Cache Not Invalidating / Intermittent Timeout / Verify Recent Changes (§7), open-PR scan (§8), emit payload shapes (§9).
- `${CLAUDE_PLUGIN_ROOT}/skills/debug/deep-mode-reference.md` — depth question (§1), hypothesis fan-out (§2), 3-verifier majority vote (§3).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Investigation-driven fix gate (debug-flavored) — multi-path fix gate and repro-infeasible escape hatch.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` — consumer protocol for downstream skills reading the handoffs this skill writes.
