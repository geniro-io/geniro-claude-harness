---
name: geniro:plan
description: "Use when turning a vague idea or feature request into an approved spec.md before /geniro:implement. Spec-first planning workflow: explore → grill (decision-tree clarification) → propose 2-3 approaches → approve sections → write spec.md → mechanical validate → user approve → handoff. Skip for well-formed specs already authored — use /geniro:implement <path> directly. Optional --deep deepens the analysis — a wider approach search plus a 3-vote majority verification of the spec's cited claims (higher quality, higher cost). Optional --artifact builds a live, auto-updating visual artifact of the plan as it develops."
context: main
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, Workflow]
model: inherit
argument-hint: "<topic-string-or-design-doc-path> [--prd] [--deep] [--artifact]"
---

# /geniro:plan — spec-first planning

## Contents

- When to use / When NOT to use
- Phase structure
- Loop invariants
- Budgets — quality-first framing
- State persistence
- Memory I/O
- ACI per-phase tool surface
- Task execution entry
- Anti-rationalization

---

Turn a vague idea into an approved `spec.md` that `/geniro:implement` can consume directly. This skill is a thin wrapper around the canonical planning loop (Phases 0–9 plus the conditional Phase 0.5 problem-discovery and the Phase 7.5 spec-challenge, which fires on Big effort tier or `--deep`; Phase 2 Visual Companion is UI-conditional — fires only when the UI trigger matches) in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`. It applies the loop verbatim.

**Output:**
- spec.md at `.geniro/planning/<task-slug>/spec.md` with the fixed 11-section schema, goal-state frontmatter, and all three design-doc detection markers per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`.
- For Big tasks: sibling `milestone-N.md` files.
- state.md at the same task-dir tracking phase progress + AUQ answers.
- `git commit` of spec.md (+ milestones) — fires at Phase 8 post-approve, NOT Phase 6.
- Phase 8.7 executes any user-authored `### After user-approve` steps loaded from `.geniro/instructions/plan.md` — the generic extension point for project-specific post-plan work (e.g. duplicating the approved plan into an OpenSpec change via the project's own tooling). The plugin stays tool-agnostic; the procedure lives in the project's instruction file.
- Phase 9 handoff — prints the milestone-aware `/geniro:implement <path>` command (no question — the spec is already saved and committed at Phase 8).

The HARD-GATE in `plan-loop.md` prevents any implementation invocation until Phase 8 user-approve returns "Approve".

**Flags & presets:** `--prd`, `--deep`, `--artifact`, and the launch modifiers (workspace / ship / `freshness:`) that pre-fill the spec's `launch_config` are cataloged in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flags-reference.md`.

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
mode-detect → [problem-discovery: --prd only] → explore → [visual-companion: UI-conditional] → clarify → approaches → section-approve → write-spec → validate → [spec-challenge: Big tier or --deep] → user-approve → handoff → done
```

Any phase may branch to the `aborted` terminal on cancel; phase-8 revision / validator hard-fail re-enters write-spec or section-approve.

**Terminal states:** `done`, `aborted`. The SessionStart hook treats both as "planning complete or cancelled — no resume needed". Every transition into a terminal state first runs the transient cleanup in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §9.2 (`clean_task_transients` against the planning task-dir) before the terminal `phase:` write; rationale and the preserved-durables list live there.

**Phase contracts** are defined in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`:

| Phase | Purpose | Plan-loop section |
|---|---|---|
| 0 | Mode detect (also detects the opt-in `--prd`, `--deep`, and `--artifact` flags; asks the visual-artifact opt-in question when `--artifact` is absent, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md`) | §"Phase 0 — Mode detect" |
| 0.5 | Problem discovery (opt-in — fires only with `--prd`: problem-first interview before explore, feeds the spec's optional `## Problem & Evidence` section) | §"Phase 0.5 — Problem discovery" |
| 1 | Explore (effort-tier-scaled spawns + custom-instructions/project-snapshot/past-learnings refresh + workflow_refs fetch) | §"Phase 1 — Explore" |
| 2 | Visual Companion (UI-conditional — calls ui-preview-gate.md) | §"Phase 2 — Visual Companion" |
| 3 | Grill — depth-first decision-tree clarification, one message-first framing + lean single-question AUQ per decision; uncapped, checkpoint-bounded; Standard/Deep depth question at wrap-up when `--deep` is absent | §"Phase 3 — Grill (decision-tree clarification)" |
| 4 | Approaches — 2-3 rendered message-first in the visual language, then ONE lean AUQ with Recommended first; build-vs-buy folded into the trade-offs per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/library-reuse-audit.md` MODE: plan; `--deep` path per `${CLAUDE_PLUGIN_ROOT}/skills/plan/deep-mode-reference.md` | §"Phase 4 — Approaches" |
| 5 | Cluster approval — the fixed 11-section schema in 3 dependency-ordered clusters, each rendered message-first then gated by ONE lean AUQ (Approve all / Explain a section further / Revise specific sections / Cancel); milestone-mode | §"Phase 5 — Section approval" |
| 6 | Write spec.md (NO auto-commit; `workflow_refs[]` copied from state.md) | §"Phase 6 — Write spec.md" |
| 7 | Mechanical validator (full check set — adds `workflow_refs_consistency` and `launch_config_consistency`) | §"Phase 7 — Mechanical validator" |
| 7.5 | Spec challenge (Big tier or `--deep` — adversarial pass: verify claims, generate alternatives, red-team; advisory, fail-open; skipped runs transition validate → user-approve directly; `--deep`: 3× verify per cited claim with majority vote) | §"Phase 7.5 — Spec challenge" |
| 8 | User approve (visual summary message + lean AUQ + git commit; §8.7 executes any user-authored `### After user-approve` steps from `.geniro/instructions/plan.md`) | §"Phase 8 — User approval" |
| 9 | Handoff (non-interactive — prints the milestone-aware `/geniro:implement <path>` command, writes terminal `phase: done`) | §"Phase 9 — Handoff" |

Execute `plan-loop.md` end-to-end; it is the authoritative phase contract.

---

## Loop invariants

These invariants apply throughout all phases; phase numbers and tool surface differ.

1. **One result per tool call.** Every AskUserQuestion / Write / Bash / Agent spawn produces exactly one structured result. Failed AUQ (empty-answer bug) → fall back to plain-text re-ask; never auto-default.
2. **Args validated before execution.** Bash commands constructed from $ARGUMENTS or state.md fields pass input sanity-checks. Path-based detection (design-doc-detect.md) validates file existence before treating $ARGUMENTS as a path.
3. **Permission before side-effect.** Phase 6 `atomic_state_write` to `.geniro/planning/<task-dir>/spec.md` is the only mutation in the loop. `git commit` deferred to Phase 8 post-approval. No auto-mutations elsewhere — the frontmatter `allowed-tools` omits `Edit`, and the `enforce-state-helper` PreToolUse hook hard-blocks any direct `Edit`/`Write` to canonical state paths (`.geniro/planning/**`, `.geniro/state/**`), so every state write routes through `atomic_state_write`.
4. **Bounded and structured tool results.** Phase 1 research-agent output capped at ~4000 chars per agent; longer truncated with marker. Output schema: `[{file, lines, observation}]`. Phase 7 validator output is a structured pass/fail list per check.
5. **Escalation gates, not silent abort.** Phase 7 validator 3-round → AUQ. Phase 8 user-revision 3-round → AUQ. Phase 3 grill → summarize-and-continue checkpoint AUQ (~6 questions or at branch completion; canonical: plan-loop §3.4), never a hard cap. NO Class-A hard kill caps.
6. **Final answer grounded in observations.** Phase 5 section content cites Phase 1 explore findings (`file:line` references), not generic prose — the Phase 7 validator includes a "citations present" check that fails an uncited section.
7. **Errors, denials, cancellations, timeouts → structured observations.** Phase 1 research-agent failures → structured entry in state.md `## Errors`. Phase 0 cancel → `## Termination reason`. Phase 7 validator findings → `## Open Questions`. Never silently skipped.
8. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**Turn-completion check (canonical, un-numbered).** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard: never stop on an announced-but-unfired question.

`## Tool log` schema (selective logging): entry shape is the single source of truth in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §1.3 Echo contract — fields `ts` / `tool` / `detail` / `status` plus `summary` (Agent) or `result_ref` (Write). Each entry written via `atomic_state_write`. AUQ calls do NOT need logging — `approvals[]` is the structured record.

---

## Budgets — quality-first framing

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. All limits are escalation gates that surface to the user, not abort triggers.

**Quality gates (Class-B — escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Phase 3 grill checkpoint | summarize-and-continue every ~6 questions OR at branch completion (no fixed question cap) | plan-loop.md | Render running summary → AUQ: Keep grilling / Wrap up now / Skip remaining as stated assumptions. |
| Phase 7 → Phase 6 auto-revision rounds | 3 | plan-loop.md | AUQ — accept-as-is / re-revise / abort. |
| Phase 8 user-revision rounds | 3 | plan-loop.md | AUQ — accept-as-is / re-revise / abort. |
| Phase 1 research-agent output size | ~4000 chars per agent | invariant #4 | Truncation with marker, not abort. |

**Architecture constraints (design intent, not budget):**
- Parallel research spawns per Phase 1: 1-4 (effort-tier-scaled per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`).
- spec.md section count: exactly 11.

**Rationale.** /geniro:plan is a **clarification-heavy** skill — its job IS to ask questions; every limit above escalates to the user instead of aborting. Question cadence per gate is defined in the phase table above and invariant 5 (Phase 3 uncapped grill with the checkpoint off-ramp; Phase 4 ×1; Phase 5 ×3, one per cluster; Phase 8 ×1).

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
prd_mode: true                   # optional, present only when --prd was passed (Phase 0)
deep-mode: <true|false>          # optional, set by the --deep flag (Phase 0); missing reads as false
artifact_mode: true              # optional, present only when the user opted into the visual artifact (Phase 0 question or --artifact)
artifact_status: pending|live|unavailable  # optional, present only in artifact mode — publish lifecycle state
artifact_url: "<url>"            # optional, present once the page is published live
---
```

The visual-artifact lifecycle is owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md`; the captured `claude.ai` URL persists in state.md so a later session re-targets the same page instead of publishing a duplicate.

When `deep-mode: true`, Phase 4 runs its deeper path and Phase 7.5 fires on any effort tier (deep mode satisfies its Big-tier-or-deep gate) with 3× claim verification, both via an internal `Workflow(...)` per `${CLAUDE_PLUGIN_ROOT}/skills/plan/deep-mode-reference.md`; persist the activation to `approvals[]` category `deep_mode_choice` so a resume re-applies it. When `--deep` is absent, the Standard/Deep depth question fires at Phase 3 wrap-up per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2a.

**Write contract.** Every state.md AND spec.md mutation goes through `atomic_state_write` from `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh` — direct `Edit`/`Write` on canonical state paths is hook-blocked per invariant #3, so the helper is the only working write path for both artifacts.

**Validation before resume.** When Phase 0 detects a pre-existing state.md (resume path), pre-flight via `validate_state_file`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh"
if ! validate_state_file ".geniro/planning/<task-slug>/state.md"; then
# Open recovery AskUserQuestion (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency)
...
fi
```

---

## Memory I/O

Full Phase 1 entry inventory + per-phase write sites. See `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` for full call signatures.

| Phase | Helper | Direction | Notes |
|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` (MODE: refresh) | read L4 | scope = `plan` + `global` + `code-style` |
| Phase 1 entry | `load_semantic` | read L3 | top-2 default; fingerprint drift check |
| Phase 1 entry | `query_learnings` | read L2 | tags inferred from $ARGUMENTS topic |
| Phase 1 entry | `resolve-conflicts` | read protocol | fires only if L4/L3/L2 disagree |
| Phase 1.4 (conditional) | matching tracker MCP (`mcp__linear__get_issue`, etc.) | read external | fires only when `$ARGUMENTS` carries a tracker URL/ID; payload → state.md `## Workflow Refs` |
| Phase 1.4 (conditional) | `atomic_state_write` | write T1.5 | state.md `## Workflow Refs` body section |
| Phase 2 (conditional) | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` | helper procedure | fires only when UI trigger matches; approved description → state.md `## UI Preview` |
| Phase 6 | `atomic_state_write` | write T1.5 | state.md `## Tool log` after the spec.md write |
| Phase 6 | `atomic_state_write` | write T1.5 | spec.md frontmatter `workflow_refs[]` copied from state.md `## Workflow Refs` when present |
| Phase 7 (hard-fail) | `atomic_state_write` | write T1.5 | state.md `## Open Questions` |
| Phase 8.4 | `atomic_state_write` | write T1.5 | state.md `non-resumable-actions[]` after git commit |
| Phase 8.5 (conditional) | `emit_learning` | write L2 | `decision` type when Phase 4 had ≥2 approaches with trade-off |

**Default trust for L2 emits**: `verified` (planning decisions are user-validated via Phase 8 AUQ).

**Cross-layer conflict surfacing:** when L4/L3/L2 reads disagree, apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol — soft conflict prints notice and continues; hard conflict halts with AUQ.

---

## ACI per-phase tool surface

| Phase | Allowed | Blocked |
|---|---|---|
| Phase 0 (Mode detect) | Read / Bash (read-only: `ls`, `file`) | All mutations |
| Phase 1 (Explore) | Read / Grep / Glob / Bash (read-only) / Agent (research spawn — OMIT `model=`) / tracker MCP read (`mcp__linear__get_issue`, etc.) / native `Artifact` publish (when artifact mode is on, via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md`) | Edit / Write outside state.md |
| Phase 2 (Visual Companion, UI-conditional) | Read / Agent (UI description spawn, OMIT `model=` — inherits orchestrator tier per `ui-preview-gate.md`) / AskUserQuestion / atomic_state_write (state.md `## UI Preview`) | Edit / Write outside state.md |
| Phase 3-5 (Clarify / Approaches / Section approve) | Read / Grep / Glob / AskUserQuestion / atomic_state_write (state.md only) / Agent (Phase 3 codebase-research + Phase 4 stress-test critic spawns — OMIT `model=`) / Workflow (Phase 4 approach panel + critics, `deep-mode: true` only — OMIT `model=`) | Edit / mutating Bash |
| Phase 6 (Write spec) | atomic_state_write (spec.md + state.md) | Edit / direct Write / mutating Bash |
| Phase 7 (Validate) | Read / atomic_state_write (state.md `## Open Questions`) | All other mutations |
| Phase 7.5 (Spec challenge — Big tier or `--deep`) | Read / Grep / Glob / Bash (read-only) / Agent (claim-verifier spawn — OMIT `model=`) / Workflow (3× claim verify, `deep-mode: true` only) / atomic_state_write (state.md `## Errors`) | Edit / Write outside state.md / mutating Bash |
| Phase 8 (User approve) | AskUserQuestion / Bash (`git add`, `git commit` only) / atomic_state_write | Edit / general-purpose Bash |
| Phase 9 (Handoff) | Read / Bash (terminal state.md write via atomic_state_write; `clean_task_transients` rm of this run's own scratch in the planning task-dir) | All file mutations except the state.md terminal write and the transient-scratch cleanup (deleting the skill's own scratch is not a source mutation) |

**Mutation enforcement:** frontmatter `allowed-tools` excludes `Edit` (this skill never edits in place).

**Existing safety layer:** file-protection hook, git-guardrails, `.geniro/` deletion guard apply across all phases.

---

## Task execution entry

0. **Check for existing state.md.** Glob `.geniro/planning/*/state.md` for a file matching the resolved task slug:
- **No state.md** → fresh run. Proceed to Phase 0.
- **state.md exists, phase in non-terminal set** → resume from `phase:` value. the SessionStart hook re-injects context.
- **state.md exists, phase in terminal set** (`done` / `aborted`) → task complete. Surface terminal state to user; if $ARGUMENTS carries a new topic, derive a new slug, fresh run.

1. **Validate state.md if found** (`validate_state_file`). On fail, open recovery AUQ.

2. **TodoWrite checklist.** Add: Detect mode / Problem discovery (--prd only) / Offer the plan artifact / Explore codebase / Visual companion / Grill the design decisions / Propose approaches / Approve plan in groups / Write spec / Validate spec / Challenge spec / User approval / Handoff. Mark the first item in_progress; update each as it completes. The problem-discovery item is marked completed-skipped when `--prd` was not passed; Phase 2 is marked completed-skipped when the UI trigger doesn't fire; the challenge-spec item is marked completed-skipped when its gate doesn't fire (effort tier below Big and standard depth); the plan-artifact item is marked completed-skipped when the user declines the opt-in or the session can't publish.

3. **Begin Phase 0.** Execute `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` end-to-end.

---

## Anti-rationalization

Do NOT reintroduce these anti-patterns. Loop-level rows (commit timing, empty-AUQ defaults, message-first rendering, refine/edit mode, kill caps, `--no-verify`, Phase 3 persistence) live in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §Anti-rationalization — co-loaded with this file; this table keeps only the skill-scope rows:

| Your reasoning | Why it's wrong |
|---|---|
| "Skip Phase 2 Visual Companion — UI intent fits in Phase 5 sections later." | Phase 2 fires only when the UI trigger matches (Phase 1 found UI files OR topic carries a UI noun). When it fires, the approved description IS the substrate Phase 5 sections 6 + 9 cite. Skipping it forces the user to describe visual intent twice (once in Phase 3 prose, again to /geniro:implement when the rendered UI doesn't match). |
| "Phase 7 mechanical validator misses cases a smart LLM would catch." | The validator checks cover the mechanical surface (including `workflow_refs_consistency`). Phase 8 user-approve catches everything else — the user IS the smart-LLM check. |
| "The state-write enforcement is over-engineered — model can be trusted." | The model can be reasoned-with, jailbroken, or instructed via a compromised CLAUDE.md. The frontmatter `allowed-tools` field (omits `Edit`) + the `enforce-state-helper` PreToolUse hook (hard-blocks direct `Edit`/`Write` to canonical state paths) are the only mechanical layers between a bad-intent prompt and a modified source tree. Belt + suspenders. |
| "Re-cap Phase 3 at ~5 questions like before, OR just grill forever without pausing." | Phase 3 is an uncapped decision-tree grill, bounded by the checkpoint gate — summarize-and-continue every ~6 questions or when a branch resolves (plan-loop §3.4). Re-imposing a flat cap drops the relentless property the grill exists to provide; skipping the checkpoint drops the user's off-ramp. Keep both: no fixed cap, always a checkpoint. |
| "11-section spec.md schema is too rigid for small tasks." | Sections 4 / 5 / 10 can be "none with rationale" for Trivial. The schema is structural commitment (every consumer can rely on section presence), not content commitment. |
| "Phase 7 validator hard-fail blocks user — they're stuck with auto-revision rounds." | 3-round escalation cap. On round 3, AUQ surfaces to user with "accept as-is" option. User has agency at all times. |
| "Drop the milestone-mode AUQ — a Big task can just emit a spec and the user decides later." | Slicing into milestones IS a planning decision. Punting it to /geniro:implement time means the user discovers a 50-step spec is unmanageable, and must come back to re-plan. Phase 5 surfaces the choice when context AND attention are present. |

---

