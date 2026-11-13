---
name: geniro-plan
description: "Use when turning a vague idea or feature request into an approved spec.md before /geniro:implement: explore, grill, compare approaches, approve. --artifact adds a live visual plan. Skip when a spec exists (/geniro:implement {path})."
context: main
---
<!-- Generated from skills/plan/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->


# /geniro:plan — spec-first planning

## Contents

- Phase structure · Loop invariants · Anti-rationalization
- Budgets · State persistence · ACI per-phase tool surface · Memory I/O · Task execution entry

---

Turn a vague idea into an approved `spec.md` that `/geniro:implement` consumes directly. This skill is a thin wrapper over the planning loop (Phases 0–9; the Phase 7.5 spec-challenge runs on every run, Phase 2 Visual Companion only when the UI trigger matches): the spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`, and each phase's steps live in a sibling `loop-phase-<N>-<name>.md` read on entry to that phase.

**Runtime portability.** If Codex truncated this file, read it in full from its path first. `${CLAUDE_PLUGIN_ROOT}` is a placeholder Claude Code substitutes into file references, not a shell export — it reads empty in Bash under every host, so an empty probe proves nothing (`CLAUDECODE` marks Claude Code). Resolve the root from the first rung that holds: the ancestor of this file's real path (symlinks followed) containing `.claude-plugin/plugin.json`; a copy of the referenced file beside this one (the Cursor build); a plugin checkout in the workspace. The run's first Bash call prints this file's real directory and checks the rungs against it; echo that output verbatim before anything else (a resolved ladder is bookkeeping: add a degraded-run notice only for a rung that failed), then substitute the resolved root everywhere and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. A path the output does not show did not resolve. Before deciding a step cannot run here, read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` — it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not:** name what is unavailable in your first message, run every phase and gate this skill declares, never let project rules stand in for its decision gates, and take no outward-facing action (ready PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

**Output:**
- spec.md at `.geniro/planning/<task-slug>/spec.md` with the fixed section schema (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`), goal-state frontmatter, and all three design-doc detection markers per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`.
- For Big tasks: sibling `milestone-N.md` files.
- state.md at the same task-dir tracking phase progress + AUQ answers.
- `git commit` — fires at Phase 8 post-approve, NOT Phase 6: spec.md (+ milestones) plus the glossary entries and ADR files the Phase 3 grill wrote. When the project ignores `.geniro/planning/` (the default `.gitignore` does), the spec stays on disk uncommitted and only those docs are committed.

The HARD-GATE in `plan-loop.md` blocks any implementation invocation until Phase 8 returns "Approve".

**Flags & presets:** `--artifact` and the launch modifiers (workspace / ship / `freshness:`) that pre-fill the spec's `launch_config` are cataloged in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flags-reference.md`.

---

## Phase structure

```
mode-detect → explore → [visual-companion: UI-conditional] → clarify → approaches → section-approve → write-spec → validate → spec-challenge → user-approve → handoff → done
```

Any phase may branch to the `aborted` terminal on cancel; a Phase 7 validator hard-fail re-enters write-spec and a Phase 8 revision re-enters section-approve; visual-companion "Adjust the plan instead" re-enters explore; a Phase 7.5 `re-plan` verdict re-enters approaches, and a Phase 7.5 milestone re-open re-enters write-spec.

**Terminal states:** `done`, `aborted`. The SessionStart hook treats both as "planning complete or cancelled — no resume needed". Every transition into one first runs the transient cleanup (`clean_task_transients`, `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-9-handoff.md` §9.2) before the terminal `phase:` write.

## Phase 0 — Mode detect
`loop-phase-0-mode-detect.md`

## Phase 1 — Explore
`loop-phase-1-explore.md`

## Phase 2 — Visual Companion (UI-conditional)
`loop-phase-2-visual-companion.md`

## Phase 3 — Grill (decision-tree clarification)
`loop-phase-3-grill.md`

## Phase 4 — Approaches
`loop-phase-4-approaches.md`

## Phase 5 — Section authoring
`loop-phase-5-section-approval.md`

## Phase 6 — Write spec.md
`loop-phase-6-write-spec.md`

## Phase 7 — Mechanical validator
`loop-phase-7-validator.md`

## Phase 7.5 — Spec challenge
`loop-phase-7.5-spec-challenge.md`

## Phase 8 — User approval
`loop-phase-8-user-approval.md`

## Phase 9 — Handoff
`loop-phase-9-handoff.md`

**How to run it.** Read the spine `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` at entry — it carries the HARD-GATE, the gate presentation and echo contracts, the terminal-state rule, more anti-rationalization rows, and the §Phase files table mapping each phase to its steps file. It is the hop most worth guarding: a run that skips straight to the phase files still looks compliant while never having seen the HARD-GATE. This spine read and each phase file's read are bound by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`: read a phase's file on entry, not up front, as its physically-first action with a one-line echo; read the conditional Phase 2 file only once its trigger fires. The spine is the authoritative phase contract; each phase file is authoritative for its own steps.

---

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply across every phase, with plan-specific bindings:

- **Invariant #1 (one result per tool call)** — every user-facing choice, from the Phase 0 mode pick to the Phase 8 approval, is an `AskQuestion`; re-ask a failed call per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions, never auto-default.
- **Invariant #3 (permission before side-effect)** — spec.md (Phase 6) and the Phase 3 glossary and ADR writes follow the user's own answer; `git commit` waits for Phase 8 approval.
- **Invariants #4, #6, #7** — the phase files carry them: the Phase 1 research-output cap (§1.2), Phase 5 `file:line` citations, and failures in state.md `## Errors` / `## Termination reason` / `## Open Questions`.

This skill adds one invariant:

S1. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**Turn boundaries.** A turn ends in exactly three places: on a fired approval question, on reaching a terminal `phase:` state, or when the user asked something and is owed the answer. Everywhere else the next action follows in the same turn, with a tool call — between steps, after a check comes back green, after a state write, at a phase transition, and when a subagent's result lands. A status report, a checkpoint summary, and a list of what remains are continuations, not endings: write one where it helps, then take the next action in that same turn. A decision that needs the user is asked as a real question in the turn that raises it, its render and the question inside that one turn (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard) — a question left in prose, or announced for a later message, leaves the run waiting on an answer the user was never asked for. Reversibility is not the test: a deviation from a rule this run loaded is a gate however cheap it is to undo.

**Compaction.** The host re-attaches only an initial slice of this file, so its later sections arrive missing, with a truncation marker standing in for them. Treat that marker as an instruction: in the turn you notice it — and after any compaction, before acting on the resumed phase — re-read this file, the spine, and the running phase's file (state.md `phase:` names it). The spine and every phase file arrived as Read results and are gone, and the session-restore context carries task state, not the loop's instructions; a resume that skips the re-read walks the phase's irreversible steps — the Phase 8 commit branch and its never-`git add -f` bar, the launch-config spec rewrite, the Phase 9 transient cleanup — with none of their rules in context. When you compose a compaction summary, record state — what ran, what remains, what the user decided — never a directive to yourself about stopping, confirming, or awaiting direction. A resumed session reads its summary as fact and will honour it over this file, so work still to do is recorded as work still to do, not as something to ask permission for.

`## Tool log` schema (selective logging): entry shape is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §Echo contract; each entry is appended via `atomic_state_append_section`. AUQ calls do NOT need logging — `approvals[]` is the structured record.

---

## Anti-rationalization

Loop-level rows live in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §Anti-rationalization, co-loaded with this file; this table keeps the skill-scope rows.

| Your reasoning | Why it's wrong |
|---|---|
| "Skip Phase 2 Visual Companion — UI intent fits in Phase 5 sections later." | When the UI trigger matches, the approved description is the substrate Phase 5 sections 6 + 9 cite; skipping it makes the user describe visual intent twice — in Phase 3, then when /geniro:implement's UI misses. |
| "Cap Phase 3 at ~5 questions, skip the checkpoint, or move to Phase 4 once the tree looks resolved." | Only the user's answer ends the grill (a §3.4 pick or the §3.1 build-nothing confirmation); "resolved" is the model's read of its own tree, and a cap or skipped checkpoint drops the user's off-ramp. |
| "spec.md's fixed section schema is too rigid for small tasks." | Sections 4 / 5 / 10 can be "none with rationale" for Trivial; the schema commits to structure (consumers can rely on section presence), not content. |
| "Drop the milestone-mode AUQ — a Big task can just emit a spec and the user decides later." | Slicing into milestones is a planning decision; left to /geniro:implement, the user finds a 50-step spec unmanageable only after planning has ended. |

---

## Budgets — quality-first framing

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies.

**Quality gates (Class-B — escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Phase 3 grill checkpoint | the checkpoint trigger per §3.4 — no fixed question cap | §3.4 | Running summary, then the user's call — options in §3.4. |
| Phase 3 grill exit | none — fires whenever the tree exhausts | §3.4 | Closing summary, then the user's call — options in §3.4. Skipped when a checkpoint Wrap up pick ended the grill. |
| Phase 7 → Phase 6 auto-revision rounds | §7.3 owns the count | §7.3 | AUQ — accept-as-is / re-revise / abort. |
| Phase 8 user-revision rounds | §8.3 owns the count | §8.3 | AUQ — accept-as-is / re-revise / abort. |

---

## State persistence

**Task directory**: `.geniro/planning/<task-slug>/`

**state.md** — frontmatter schema and body template are in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1; Phase 0 §0.3 creates it.

**Write contract.** Every state.md AND spec.md mutation goes through the `atomic-state-write` helpers from `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh` (**Invariant #3 (Permission before side-effect)**): tmp + fsync + rename, so a reader or a post-crash resume never sees a torn file.

**Validation before resume.** When Phase 0 detects a pre-existing state.md (resume path), pre-flight via `validate_state_file` (`${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh`); on failure, open the recovery AUQ (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency).

---

## ACI per-phase tool surface

Reads and `AskQuestion` are open in every phase; writes are limited to those listed, Bash stays read-only unless listed, and no source is written before the Phase 8 approval (HARD-GATE, `plan-loop.md`).

| Phase | Writes and spawns allowed |
|---|---|
| 0 Mode detect | state.md (§0.3, §0.4) |
| 1 Explore | state.md; research Agents; tracker MCP read; Bash for §1.1b's git `merge` / `rebase` / `pull`, only on the user's answer; `Artifact` publish† |
| 2 Visual Companion | state.md `## UI Preview`; UI-description Agent; `Artifact` + scratchpad `Write`† |
| 3-5 Clarify / Approaches / Sections | state.md, questionnaire.md; glossary entries in the repo's existing glossary file and new files in its existing ADR folder (Phase 3); emit_learning; research, design-generator and critic Agents; `Artifact` + scratchpad `Write`† |
| 6 Write spec | spec.md, each `milestone-N.md`, state.md; `Artifact` + scratchpad `Write`† |
| 7 Validate | state.md `## Open Questions`; failing spec.md sections (§7.3) |
| 7.5 Spec challenge | state.md `## Errors`; claim-verifier Agent |
| 8 User approve | state.md; spec.md rewrite; Bash for §8.4's git and validator calls; `Artifact` + scratchpad `Write`† |
| 9 Handoff | state.md terminal write; removal of this run's own scratch |

†Artifact mode only — call sites in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-artifact-call-sites.md`; `Artifact` stays out of `allowed-tools` so the first publish raises the one-time `claude.ai` consent prompt. Spawns are `session` unless a site names a light class (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Cost classes); Phase 3 grill lookups and Phase 2 UI description (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §Step 1) are **light (mid)**.

---

## Memory I/O

**Reads — all at Phase 1 entry, full tier:** custom instructions via `load-custom-instructions` (L4) · the project snapshot via `load_semantic` (L3) · past learnings via `query-learnings`, backend-override aware (L2). Plus one conditional external read at §1.4 — the matching tracker MCP (the tool named in `.geniro/workflow/<kind>.md`), only when `$ARGUMENTS` carries a tracker URL/ID.

**Writes:** every state.md and spec.md mutation is T1.5 through the `atomic-state-write` helpers (§State persistence) — `atomic_state_set_field` for one frontmatter field, `atomic_state_append_section` / `atomic_state_append_list_item` for an entry, `atomic_state_write` for a whole file. The state.md body-section index — the base sections, the phase that owns each optional one, and the `approvals[]` entry every gate writes — is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1. L2 emits are conditional, and each supplies its own `trust` at its emit site.

**Cross-layer conflict surfacing:** when L4/L3/L2 reads disagree, apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol — soft conflict prints notice and continues; hard conflict halts with AUQ.

---

## Task execution entry

0. **Check for existing state.md.** Glob `.geniro/planning/*/state.md` for a file matching the resolved task slug:
- **No state.md** → fresh run. Proceed to Phase 0.
- **state.md exists, phase in non-terminal set** → resume from `phase:` value, re-Reading the spine and that phase's steps file first (the Compaction paragraph above). The SessionStart hook re-injects task context, not the loop's steps.
- **state.md exists, phase in terminal set** (`done` / `aborted`) → task complete. Surface terminal state to user; if $ARGUMENTS carries a new topic, derive a new slug, fresh run.

1. **Validate state.md if found** (§State persistence). On fail, open the recovery AUQ.

2. **Todo-list checklist.** Add: Detect mode / Offer the plan artifact / Explore codebase / Visual companion / Grill the design decisions / Propose approaches / Author plan sections / Write spec / Validate spec / Challenge spec / User approval / Handoff. Mark the first item in_progress; update each as it completes. The conditional items — plan artifact, visual companion — are marked completed-skipped when their trigger (spine §Phase files) does not fire, so a skipped phase reads as a decision rather than an omission.

3. **Begin Phase 0.** Read the spine `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`, then `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-0-mode-detect.md`, and run Phase 0. Each phase file ends by naming the next `phase:` value.
