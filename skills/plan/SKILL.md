---
name: plan
description: "Use when turning a vague idea or feature request into an approved spec.md before /geniro:implement. Spec-first planning workflow: explore → grill (decision-tree clarification) → propose 2-3 approaches → approve sections → write spec.md → mechanical validate → user approve → handoff. Skip for well-formed specs already authored — use /geniro:implement <path> directly. Optional --deep deepens the analysis — a wider approach search plus a 3-vote majority verification of the spec's cited claims (higher quality, higher cost). Optional --artifact builds a live, auto-updating visual artifact of the plan as it develops."
context: main
model: inherit
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, Workflow]
argument-hint: "<topic-string-or-design-doc-path> [--deep] [--artifact]"
---

# /geniro:plan — spec-first planning

## Contents

- When to use / When NOT to use
- Phase structure
- Loop invariants
- Anti-rationalization
- Budgets — quality-first framing
- State persistence
- ACI per-phase tool surface
- Memory I/O
- Task execution entry

---

Turn a vague idea into an approved `spec.md` that `/geniro:implement` can consume directly. This skill is a thin wrapper around the canonical planning loop (Phases 0–9, including the Phase 7.5 spec-challenge on every run; Phase 2 Visual Companion is the one conditional phase — it fires only when the UI trigger matches). The loop is a tree of files: its spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`, and each phase's steps live in a sibling `loop-phase-<N>-<name>.md` read on entry to that phase.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve every reference it appears in, working these in order: the env var of that name; the ancestor directory of this file containing `.claude-plugin/plugin.json`; a copy of the referenced file sitting beside this one (the Cursor build ships each skill's own phase and reference files there); a plugin checkout inside the workspace. Where a rung yields a root, substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. **Work the rungs with a command, not a judgment:** the run's first Bash call lists the directory this file was read from and each candidate root, and its output is echoed verbatim before anything else. Read the rungs against that output — a path it does not show did not resolve, and a file it does not show cannot be read, however confidently a later step would report otherwise. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` before deciding a step cannot run here: it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not** — open your first message by naming what is unavailable, run every phase and gate this skill declares, never let the project's own rules stand in for its decision gates, and take no outward-facing action (ready-for-review PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

**Output:**
- spec.md at `.geniro/planning/<task-slug>/spec.md` with the fixed section schema (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`), goal-state frontmatter, and all three design-doc detection markers per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`.
- For Big tasks: sibling `milestone-N.md` files.
- state.md at the same task-dir tracking phase progress + AUQ answers.
- `git commit` of spec.md (+ milestones) — fires at Phase 8 post-approve, NOT Phase 6; skipped, with the spec left on disk, when the project ignores `.geniro/planning/` (the default `.gitignore` does).
- Phase 8.6 executes any user-authored `### After user-approve` steps loaded from `.geniro/instructions/plan.md` — the generic, tool-agnostic extension point for project-specific post-plan work.
- Phase 9 handoff — prints the milestone-aware `/geniro:implement <path>` command; no question, since the spec is already saved and committed.

The HARD-GATE in `plan-loop.md` prevents any implementation invocation until Phase 8 user-approve returns "Approve".

**Flags & presets:** `--deep`, `--artifact`, and the launch modifiers (workspace / ship / `freshness:`) that pre-fill the spec's `launch_config` are cataloged in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flags-reference.md`.

---

## When to use

- User has an idea but no spec yet.
- $ARGUMENTS contains a topic string OR a path to an existing design doc.
- Topic spans new functionality (vs a bug fix, which routes to `/geniro:debug`).
- Pre-implementation refinement (vs in-implementation tweaks, which route to `/geniro:implement` with the original spec + adjustment description as new $ARGUMENTS).

## When NOT to use

- Spec already written → use `/geniro:implement <design-path>` directly. Detection is automatic per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`.
- Bug to fix → `/geniro:debug` for root cause; `/geniro:implement` for the patch.
- Code-file path (NOT a design doc) passed as $ARGUMENTS → error per Phase 0 (design-doc-detect CODE_REFERENCE branch).

---

## Phase structure

```
mode-detect → explore → [visual-companion: UI-conditional] → clarify → approaches → section-approve → write-spec → validate → spec-challenge → user-approve → handoff → done
```

Any phase may branch to the `aborted` terminal on cancel; phase-8 revision / validator hard-fail re-enters write-spec or section-approve; visual-companion "Adjust the plan instead" re-enters explore; a Phase 7.5 `re-plan` verdict re-enters approaches, and a Phase 7.5 milestone re-open re-enters write-spec.

**Terminal states:** `done`, `aborted`. The SessionStart hook treats both as "planning complete or cancelled — no resume needed". Every transition into a terminal state first runs the transient cleanup (`clean_task_transients` against the planning task-dir, `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-9-handoff.md` §9.2) before the terminal `phase:` write; rationale and the preserved-durables list live there.

## Phase 0 — Mode detect
$ARGUMENTS, opt-in flags, task-dir, initial state.md

## Phase 1 — Explore
Tier-scaled research spawns, memory refresh, `workflow_refs` fetch

## Phase 2 — Visual Companion (UI-conditional)
UI preview: a rendered mockup on the plan page in artifact mode, a text description otherwise

## Phase 3 — Grill (decision-tree clarification)
Uncapped, checkpoint-bounded decision-tree clarification

## Phase 4 — Approaches
2-3 stress-tested, one lean AUQ, Recommended first

## Phase 5 — Section approval
The fixed section schema in 3 cluster gates; milestone-mode

## Phase 6 — Write spec.md
NO auto-commit

## Phase 7 — Mechanical validator
The full check set in `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md`

## Phase 7.5 — Spec challenge
The spec's claims re-read against the code; advisory, fail-open

## Phase 8 — User approval
Visual summary, lean AUQ, launch config, git commit

## Phase 9 — Handoff
Prints the `/geniro:implement <path>` command, terminal `phase: done`

**How to run it.** Read the spine `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` at entry — it carries the HARD-GATE, the gate presentation contract, the state-file echo contract, the terminal-state rule, the anti-rationalization table, and the §Phase files table mapping every phase to the file holding its steps. It is the hop most worth guarding: a run that skips straight to the phase files still emits every per-phase line and looks compliant, while never having seen the HARD-GATE. Both this spine read and each phase file's own read are bound by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — read a phase's file on entry to that phase, not up front, as its physically-first action with a one-line echo; read a conditional phase's file (2) only once its trigger fires. The spine is the authoritative phase contract; each phase file is authoritative for its own steps.

**Re-Read the spine and the current phase's file after a compaction, before acting on the resumed phase.** Only this SKILL.md is re-attached after a summary — the spine and every phase file arrived as Read results and are gone, and the session-restore context carries task state, not the loop's instructions. state.md `phase:` names which phase file to read. A resume that skips this walks the phase's irreversible steps — the Phase 8 commit branch and its never-`git add -f` bar, the launch-config spec rewrite, the Phase 9 transient cleanup — with none of their rules in context.

---

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply across every phase, with plan-specific bindings:

- **Invariant #1 (one result per tool call)** — a failed `AskUserQuestion` (the empty-answer bug) is re-asked per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions, which also owns the rule that every user-facing choice routes through this tool — Phase 0 mode-detect, Phase 1 branch-freshness, Phase 3 grill, Phase 4 approach choice, Phase 5 cluster approval + milestone-mode, Phase 7 validator hard-fail, Phase 7.5 milestone re-open, and Phase 8 final approval are this skill's gates; never auto-default.
- **Invariant #3 (permission before side-effect)** — Phase 6's `atomic_state_write` to `.geniro/planning/<task-dir>/spec.md` is the loop's only mutation, and `git commit` is deferred to Phase 8 post-approval. The `enforce-state-helper` PreToolUse hook hard-blocks any direct `Edit`/`Write` to canonical state paths (`.geniro/planning/**`, `.geniro/state/**`) regardless of `allowed-tools`, so every state write routes through `atomic_state_write` — omitting `Edit` from `allowed-tools` reflects that the skill never needs it, not an enforcement of its own. `Write` stays granted because `--artifact` mode needs it for the HTML file it authors in the session scratchpad before publishing; the hook is belt-and-suspenders on the two state paths, never a source-tree boundary.
- **Invariant #4 (bounded results)** — Phase 1 research-agent output carries the per-spawn cap declared in `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-1-explore.md` §1.2, which owns that value; schema `[{file, lines, observation}]`. Phase 7 validator output is a structured pass/fail list per check.
- **Invariant #6 (grounded in observations)** — Phase 5 section content cites Phase 1 explore findings by `file:line`, not generic prose; the Phase 7 validator's citation check fails an uncited section.
- **Invariant #7 (structured observations)** — a Phase 1 research-agent failure lands in state.md `## Errors`; a Phase 0 cancel in `## Termination reason`; Phase 7 validator findings in `## Open Questions`.

This skill adds one invariant:

S1. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**Turn-completion check (canonical, un-numbered).** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard: never stop on an announced-but-unfired question.

`## Tool log` schema (selective logging): entry shape is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §Echo contract; each entry is written via `atomic_state_write`. AUQ calls do NOT need logging — `approvals[]` is the structured record.

---

## Anti-rationalization

Do NOT reintroduce these anti-patterns. Loop-level rows (commit timing, message-first rendering, `--no-verify`, Phase 3 persistence) live in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §Anti-rationalization — co-loaded with this file, and counted against the same ≤15-row cap as one table; this table keeps only the skill-scope rows. The empty-AUQ-default rule is Loop invariant #1, above — not restated here.

| Your reasoning | Why it's wrong |
|---|---|
| "Skip Phase 2 Visual Companion — UI intent fits in Phase 5 sections later." | Phase 2 fires only when the UI trigger matches (Phase 1 found UI files OR topic carries a UI noun). When it fires, the approved description IS the substrate Phase 5 sections 6 + 9 cite. Skipping it forces the user to describe visual intent twice (once in Phase 3 prose, again to /geniro:implement when the rendered UI doesn't match). |
| "Re-cap Phase 3 at ~5 questions, OR just grill forever without pausing." | Phase 3 is an uncapped decision-tree grill, bounded by the checkpoint gate — summarize-and-continue every ~6 questions or when a branch resolves (the Phase 3 checkpoint gate). Re-imposing a flat cap drops the relentless property the grill exists to provide; skipping the checkpoint drops the user's off-ramp. Keep both: no fixed cap, always a checkpoint. |
| "spec.md's fixed section schema is too rigid for small tasks." | Sections 4 / 5 / 10 can be "none with rationale" for Trivial. The schema is structural commitment (every consumer can rely on section presence), not content commitment. |
| "Drop the milestone-mode AUQ — a Big task can just emit a spec and the user decides later." | Slicing into milestones IS a planning decision. Punting it to /geniro:implement time means the user discovers a 50-step spec is unmanageable, and must come back to re-plan. Phase 5 surfaces the choice when context AND attention are present. |

---

## Budgets — quality-first framing

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. All limits are escalation gates that surface to the user, not abort triggers.

**Quality gates (Class-B — escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Phase 3 grill checkpoint | the checkpoint trigger per §3.4 — no fixed question cap | §3.4 | Render running summary → AUQ: Keep grilling / Wrap up now / Skip remaining as stated assumptions. |
| Phase 5 per-cluster revision rounds | §5.2 owns the count | §5.2 | Cluster AUQ re-fires without Revise — approve-as-rendered / explain-further / cancel; an unresolved change carries to the Phase 8 gate. |
| Phase 7 → Phase 6 auto-revision rounds | §7.3 owns the count | §7.3 | AUQ — accept-as-is / re-revise / abort. |
| Phase 8 user-revision rounds | §8.3 owns the count | §8.3 | AUQ — accept-as-is / re-revise / abort. |
| Phase 1 research-agent output size | per `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-1-explore.md` §1.2 | invariant #4 | Truncation with marker, not abort. |

**Question cadence:** Phase 3 uncapped; Phase 4 ×1; Phase 5 ×3, one per cluster; Phase 8 ×1.

---

## State persistence

**Task directory**: `.geniro/planning/<task-slug>/`

**state.md frontmatter:**

```yaml
---
tier: T1.5
producer: plan
schema-version: 1
branch: <git-branch>
worktree: <git-rev-parse-show-toplevel>     # optional, recommended for cross-worktree resume
timestamp: <ISO-8601 UTC>
phase: <state-machine-enum>
status: in-progress
non-resumable-actions: []
approvals: []
task_slug: <slug>
mode: <IDEA|DESIGN_DOC>
deep-mode: <true|false>          # optional, set by the --deep flag (Phase 0); missing reads as false
artifact_mode: true              # optional, present only when the user opted into the visual artifact (Phase 0 question or --artifact)
artifact_status: pending|live|unavailable  # optional, present only in artifact mode — publish lifecycle state
artifact_url: "<url>"            # optional, present once the page is published live
---
```

The visual-artifact lifecycle is owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md`; the captured `claude.ai` URL persists in state.md so a later session re-targets the same page instead of publishing a duplicate.

When `deep-mode: true`, Phase 4 runs its deeper path and Phase 7.5 — which fires on every run regardless of `deep-mode` — runs its 3-verifier majority claim verification instead of a single pass, per `${CLAUDE_PLUGIN_ROOT}/skills/plan/deep-mode-reference.md`; persist the activation to `approvals[]` category `deep_mode_choice` so a resume re-applies it.

**Write contract.** Every state.md AND spec.md mutation goes through `atomic_state_write` from `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh` (invariant #3) — the only working write path for both artifacts.

**Validation before resume.** When Phase 0 detects a pre-existing state.md (resume path), pre-flight via `validate_state_file` (`${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh`); on failure, open the recovery AUQ (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency).

---

## ACI per-phase tool surface

| Phase | Allowed | Blocked |
|---|---|---|
| Phase 0 (Mode detect) | Read / Bash (read-only: `ls`, `file`) / AskUserQuestion / atomic_state_write (state.md creation §0.3, cancel write §0.4) | Edit / Write outside state.md / mutating Bash |
| Phase 1 (Explore) | Read / Grep / Glob / Bash (read-only) / AskUserQuestion / atomic_state_write (state.md `## Workflow Refs` §1.4, the `phase:` transition + Trivial-skip note §1.5, Tool-log entries) / Agent (research spawn — OMIT `model=`) / tracker MCP read (`mcp__linear__get_issue`, etc.) / native `Artifact` publish in artifact mode (via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md`; deliberately absent from `allowed-tools` so the first publish raises the one-time `claude.ai` consent prompt) | Edit / Write outside state.md |
| Phase 2 (Visual Companion, UI-conditional) | Read / Agent (UI description spawn) / AskUserQuestion / atomic_state_write (state.md `## UI Preview`) / native `Artifact` calls + scratchpad `Write`† | Edit / Write outside state.md and the artifact scratchpad |
| Phase 3-5 (Clarify / Approaches / Section approve) | Read / Grep / Glob / AskUserQuestion / atomic_state_write (state.md only) / Agent (Phase 3 codebase-research + Phase 4 stress-test critic spawns) / Workflow (Phase 4 approach panel + critics, `deep-mode: true` only) / native `Artifact` calls + scratchpad `Write`† | Edit / mutating Bash |
| Phase 6 (Write spec) | atomic_state_write (spec.md + state.md) / native `Artifact` call + scratchpad `Write`† | Edit / direct Write outside the artifact scratchpad / mutating Bash |
| Phase 7 (Validate) | Read / AskUserQuestion / atomic_state_write (state.md `## Open Questions`; spec.md re-author of failing sections only, §7.3 step 2) | All other mutations |
| Phase 7.5 (Spec challenge) | Read / Grep / Glob / Bash (read-only) / AskUserQuestion / Agent (claim-verifier spawn) / Workflow (3× claim verify, `deep-mode: true` only) / atomic_state_write (state.md `## Errors`) | Edit / Write outside state.md / mutating Bash |
| Phase 8 (User approve) | AskUserQuestion / Bash (`git add`, `git commit` only) / atomic_state_write / native `Artifact` calls + scratchpad `Write`† | Edit / general-purpose Bash |
| Phase 9 (Handoff) | Read / Bash (terminal state.md write via atomic_state_write; `clean_task_transients` rm of this run's own scratch in the planning task-dir) | All file mutations except the state.md terminal write and the transient-scratch cleanup (deleting the skill's own scratch is not a source mutation) |

†Artifact mode only — the update/before-gate/finalize calls at each phase's own gate sites, plus a `Write` to the session-scratchpad HTML file; exact call sites are `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-artifact-call-sites.md`'s table, not repeated per-row here.

Every `Agent` and `Workflow` spawn above OMITs `model=` — subagents inherit the orchestrator's tier — except the Phase 2 UI-description spawn, a category-4 execution spawn whose `sonnet` is a ceiling the orchestrator may size below, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §Step 1.

---

## Memory I/O

Call signatures live in each site's phase file (spine §Phase files).

**Reads — all at Phase 1 entry, full tier:** custom instructions via `load-custom-instructions` (L4) · the project snapshot via `load_semantic` (L3) · past learnings via `query-learnings`, backend-override aware (L2). Plus one conditional external read at §1.4 — the matching tracker MCP (`mcp__linear__get_issue`, etc.), only when `$ARGUMENTS` carries a tracker URL/ID.

**Writes:** every state.md and spec.md mutation is T1.5 through `atomic_state_write` (invariant #3). The state.md body-section index — the base sections, the phase that owns each optional one, and the `approvals[]` entry every gate writes — is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1. L2 emits are conditional, and each supplies its own `trust` at its emit site.

**Cross-layer conflict surfacing:** when L4/L3/L2 reads disagree, apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol — soft conflict prints notice and continues; hard conflict halts with AUQ.

---

## Task execution entry

0. **Check for existing state.md.** Glob `.geniro/planning/*/state.md` for a file matching the resolved task slug:
- **No state.md** → fresh run. Proceed to Phase 0.
- **state.md exists, phase in non-terminal set** → resume from `phase:` value, re-Reading the spine and that phase's steps file first (§How to run it). The SessionStart hook re-injects task context, not the loop's steps.
- **state.md exists, phase in terminal set** (`done` / `aborted`) → task complete. Surface terminal state to user; if $ARGUMENTS carries a new topic, derive a new slug, fresh run.

1. **Validate state.md if found** (`validate_state_file`). On fail, open recovery AUQ.

2. **TodoWrite checklist.** Add: Detect mode / Offer the plan artifact / Explore codebase / Visual companion / Grill the design decisions / Propose approaches / Approve plan in groups / Write spec / Validate spec / Challenge spec / User approval / Handoff. Mark the first item in_progress; update each as it completes. The conditional items — plan artifact, visual companion — are marked completed-skipped when their trigger (spine §Phase files) does not fire, so a skipped phase reads as a decision rather than an omission.

3. **Begin Phase 0.** Read the spine `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`, then `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-0-mode-detect.md`, and run Phase 0. Each phase file ends by naming the next `phase:` value — look it up in the spine's §Phase files table and Read that file on entry.

