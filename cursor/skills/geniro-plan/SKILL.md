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

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is a placeholder Claude Code substitutes into file references, not a shell export — it reads empty in Bash under every host, so an empty probe proves nothing (`CLAUDECODE` marks Claude Code). Resolve the root from the first rung that holds: the ancestor of this file's real path (symlinks followed) containing `.claude-plugin/plugin.json`; a copy of the referenced file beside this one (the Cursor build); a plugin checkout in the workspace. The run's first Bash call prints this file's real directory and checks the rungs against it; echo that output verbatim before anything else (a resolved ladder is bookkeeping: add a degraded-run notice only for a rung that failed), then substitute the resolved root everywhere and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. A path the output does not show did not resolve. Before deciding a step cannot run here, read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` — it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not:** name what is unavailable in your first message, run every phase and gate this skill declares, never let project rules stand in for its decision gates, and take no outward-facing action (ready PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

**Output:**
- spec.md at `.geniro/planning/<task-slug>/spec.md` with the fixed section schema (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`), goal-state frontmatter, and all three design-doc detection markers per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`.
- For Big tasks: sibling `milestone-N.md` files.
- state.md at the same task-dir tracking phase progress + AUQ answers.
- `git commit` of spec.md (+ milestones) — fires at Phase 8 post-approve, NOT Phase 6; skipped, with the spec left on disk, when the project ignores `.geniro/planning/` (the default `.gitignore` does).

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

## Phase 5 — Section approval
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

- **Invariant #1 (one result per tool call)** — a failed `AskQuestion` (the empty-answer bug) is re-asked per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions, which also owns the rule that every user-facing choice routes through this tool — Phase 0 mode-detect, Phase 1 branch-freshness, Phase 3 grill, Phase 4 approach choice, Phase 5 cluster approval + milestone-mode, Phase 7 validator hard-fail, Phase 7.5 milestone re-open, and Phase 8 final approval are this skill's gates; never auto-default.
- **Invariant #3 (permission before side-effect)** — Phase 6's `atomic_state_write` to `.geniro/planning/<task-dir>/spec.md` is the loop's only mutation, and `git commit` is deferred to Phase 8 post-approval.
- **Invariant #4 (bounded results)** — Phase 1 research-agent output carries the per-spawn cap declared in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-1-explore.md` §1.2, which owns that value; schema `[{file, lines, observation}]`. Phase 7 validator output is a structured pass/fail list per check.
- **Invariant #6 (grounded in observations)** — Phase 5 section content cites Phase 1 explore findings by `file:line`, not generic prose; the Phase 7 validator's citation check fails an uncited section.
- **Invariant #7 (structured observations)** — a Phase 1 research-agent failure lands in state.md `## Errors`; a Phase 0 cancel in `## Termination reason`; Phase 7 validator findings in `## Open Questions`.

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
| "Skip Phase 2 Visual Companion — UI intent fits in Phase 5 sections later." | Phase 2 fires only when the UI trigger matches (Phase 1 found UI files OR topic carries a UI noun). When it fires, the approved description IS the substrate Phase 5 sections 6 + 9 cite. Skipping it forces the user to describe visual intent twice (once in Phase 3 prose, again to /geniro:implement when the rendered UI doesn't match). |
| "Re-cap Phase 3 at ~5 questions, grill forever without pausing, OR walk into Phase 4 the moment the tree looks resolved." | Phase 3 is an uncapped decision-tree grill bounded by two gates, and each of the three drops one. Re-imposing a flat cap drops the relentless property the grill exists to provide. Skipping the §3.4 checkpoint gate drops the user's off-ramp. Exiting on an exhausted tree without the §3.4 exit gate drops the user's on-ramp — exhaustion is the model's read of a tree the model built, and it reads that way after two questions as easily as after twenty, so keep-grilling stays live on an empty frontier. |
| "spec.md's fixed section schema is too rigid for small tasks." | Sections 4 / 5 / 10 can be "none with rationale" for Trivial. The schema is structural commitment (every consumer can rely on section presence), not content commitment. |
| "Drop the milestone-mode AUQ — a Big task can just emit a spec and the user decides later." | Slicing into milestones IS a planning decision. Punting it to /geniro:implement time means the user discovers a 50-step spec is unmanageable, and must come back to re-plan. Phase 5 surfaces the choice when context AND attention are present. |

---

## Budgets — quality-first framing

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies.

**Quality gates (Class-B — escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Phase 3 grill checkpoint | the checkpoint trigger per §3.4 — no fixed question cap | §3.4 | Render running summary → AUQ: Keep grilling / Wrap up now / Skip remaining as stated assumptions. |
| Phase 3 grill exit | none — fires whenever the tree exhausts | §3.4 | Render closing summary → AUQ: Start building / Keep grilling deeper / Keep grilling on a named area. Keep-grilling reopens the walk and the gate re-fires at the next termination. Skipped when a checkpoint Wrap up / Skip pick ended the grill. |
| Phase 5 per-cluster revision rounds | §5.2 owns the count | §5.2 | Cluster AUQ re-fires without Revise — approve-as-rendered / explain-further / cancel; an unresolved change carries to the Phase 8 gate. |
| Phase 7 → Phase 6 auto-revision rounds | §7.3 owns the count | §7.3 | AUQ — accept-as-is / re-revise / abort. |
| Phase 8 user-revision rounds | §8.3 owns the count | §8.3 | AUQ — accept-as-is / re-revise / abort. |

---

## State persistence

**Task directory**: `.geniro/planning/<task-slug>/`

**state.md** — frontmatter schema and body template are in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1; Phase 0 §0.3 creates it.

**Write contract.** Every state.md AND spec.md mutation goes through the `atomic-state-write` helpers from `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh` (invariant #3): tmp + fsync + rename, so a reader or a post-crash resume never sees a torn file.

**Validation before resume.** When Phase 0 detects a pre-existing state.md (resume path), pre-flight via `validate_state_file` (`${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh`); on failure, open the recovery AUQ (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency).

---

## ACI per-phase tool surface

| Phase | Allowed | Blocked |
|---|---|---|
| Phase 0 (Mode detect) | Read / Bash (read-only: `ls`, `file`) / AskQuestion / atomic_state_write (state.md creation §0.3, cancel write §0.4) | Edit / Write outside state.md / mutating Bash |
| Phase 1 (Explore) | Read / Grep / Glob / Bash (read-only) / AskQuestion / atomic_state_write (state.md `## Workflow Refs` §1.4, the `phase:` transition + Trivial-skip note §1.5, Tool-log entries) / Agent (research spawn) / tracker MCP read (the tool named in `.geniro/workflow/<kind>.md`) / native `Artifact` publish in artifact mode (via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md`; deliberately absent from `allowed-tools` so the first publish raises the one-time `claude.ai` consent prompt) | Edit / Write outside state.md |
| Phase 2 (Visual Companion, UI-conditional) | Read / Agent (UI description spawn) / AskQuestion / atomic_state_write (state.md `## UI Preview`) / native `Artifact` calls + scratchpad `Write`† | Edit / Write outside state.md and the artifact scratchpad |
| Phase 3-5 (Clarify / Approaches / Section approve) | Read / Grep / Glob / AskQuestion / atomic_state_write (state.md; Phase 3 questionnaire.md) / emit_learning (Phase 3 glossary) / Agent (Phase 3 research + Phase 4 design-generator and critic spawns) / native `Artifact` calls + scratchpad `Write`† | Edit / mutating Bash |
| Phase 6 (Write spec) | atomic_state_write (spec.md + state.md) / native `Artifact` call + scratchpad `Write`† | Edit / direct Write outside the artifact scratchpad / mutating Bash |
| Phase 7 (Validate) | Read / AskQuestion / atomic_state_write (state.md `## Open Questions`; spec.md re-author of failing sections only, §7.3 step 2) | All other mutations |
| Phase 7.5 (Spec challenge) | Read / Grep / Glob / Bash (read-only) / AskQuestion / Agent (claim-verifier spawn) / atomic_state_write (state.md `## Errors`) | Edit / Write outside state.md / mutating Bash |
| Phase 8 (User approve) | AskQuestion / Bash (`git add`, `git commit` only) / atomic_state_write / native `Artifact` calls + scratchpad `Write`† | Edit / general-purpose Bash |
| Phase 9 (Handoff) | Read / Bash (terminal state.md write via atomic_state_write; `clean_task_transients` rm of this run's own scratch in the planning task-dir) | All file mutations except the state.md terminal write and the transient-scratch cleanup (deleting the skill's own scratch is not a source mutation) |

†Artifact mode only — the update/before-gate/finalize calls at each phase's own gate sites, plus a write to the session-scratchpad HTML file; exact call sites are in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-artifact-call-sites.md`'s table.

Every subagent spawn above OMITs `model=` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`) — except the Phase 2 UI-description spawn, whose `sonnet` is a ceiling the orchestrator may size below, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §Step 1.

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

2. **Todo-list checklist.** Add: Detect mode / Offer the plan artifact / Explore codebase / Visual companion / Grill the design decisions / Propose approaches / Approve plan in groups / Write spec / Validate spec / Challenge spec / User approval / Handoff. Mark the first item in_progress; update each as it completes. The conditional items — plan artifact, visual companion — are marked completed-skipped when their trigger (spine §Phase files) does not fire, so a skipped phase reads as a decision rather than an omission.

3. **Begin Phase 0.** Read the spine `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`, then `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-0-mode-detect.md`, and run Phase 0. Each phase file ends by naming the next `phase:` value.
