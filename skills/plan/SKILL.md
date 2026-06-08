---
name: geniro:plan
description: "Use when turning a vague idea or feature request into an approved spec.md before /geniro:implement. Spec-first planning workflow: explore → clarify (≤5 questions) → propose 2-3 approaches → approve sections → write spec.md → mechanical validate → user approve → handoff. Skip for well-formed specs already authored — use /geniro:implement <path> directly. Optional --deep deepens the analysis — a wider approach search plus a 3-vote majority verification of the spec's cited claims (higher quality, higher cost)."
context: main
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, WebSearch, WebFetch]
model: inherit
argument-hint: "<topic-string-or-design-doc-path> [--prd] [--deep]"
---

# /geniro:plan — Spec-first planning

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

Turn a vague idea into an approved `spec.md` that `/geniro:implement` can consume directly. This skill is a thin wrapper around the canonical planning loop (Phases 0–9 plus the conditional Phase 0.5 problem-discovery and the always-on Phase 7.5 spec-challenge; Phase 2 Visual Companion is UI-conditional — fires only when the UI trigger matches) in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`. It applies the loop verbatim.

**Output:**
- spec.md at `.geniro/planning/<task-slug>/spec.md` with the fixed 11-section schema, goal-state frontmatter, and all three design-doc detection markers per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`.
- For Big tasks: sibling `milestone-N.md` files.
- state.md at the same task-dir tracking phase progress + AUQ answers.
- `git commit` of spec.md (+ milestones) — fires at Phase 8 post-approve, NOT Phase 6.
- Phase 9 handoff — 2-option menu (`/geniro:implement directly` / `Stop`).

The HARD-GATE in `plan-loop.md` prevents any implementation invocation until Phase 8 user-approve returns "Approve".

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
mode-detect → [problem-discovery: --prd only] → explore → [visual-companion: UI-conditional] → clarify → approaches → section-approve → write-spec → validate → spec-challenge → user-approve → handoff → done
```

Any phase may branch to the `aborted` terminal on cancel; phase-8 revision / validator hard-fail re-enters write-spec or section-approve.

**Terminal states:** `done`, `aborted`. The SessionStart hook treats both as "planning complete or cancelled — no resume needed".

**Phase contracts** are defined in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`:

| Phase | Purpose | Plan-loop section |
|---|---|---|
| 0 | Mode detect (also detects the opt-in `--prd` and `--deep` flags) | §"Phase 0 — Mode detect" |
| 0.5 | Problem discovery (opt-in — fires only with `--prd`: problem-first interview before explore, feeds the spec's optional `## Problem & Evidence` section) | §"Phase 0.5 — Problem discovery" |
| 1 | Explore (effort-tier-scaled spawns + custom-instructions/project-snapshot/past-learnings refresh + workflow_refs fetch) | §"Phase 1 — Explore" |
| 2 | Visual Companion (UI-conditional — calls ui-preview-gate.md) | §"Phase 2 — Visual Companion" |
| 3 | Clarifying questions (≤5 total — non-trivial option consequences rendered to a chat message first, independent ones batched into one lean AUQ, dependent ones sequenced), plus the Standard/Deep depth question when `--deep` is absent | §"Phase 3 — Clarifying questions" |
| 4 | Approaches (2-3 rendered to a chat message with diagrams, then ONE lean AUQ with Recommended first; `--deep`: judge-panel approach search + 3× feasibility critics with majority vote — `${CLAUDE_PLUGIN_ROOT}/skills/plan/deep-mode-reference.md`) | §"Phase 4 — Approaches" |
| 5 | Cluster approval (fixed 11-section schema grouped into 3 dependency-ordered clusters; each cluster rendered to a chat message, then ONE lean AUQ — Approve all / Revise specific sections / Cancel; milestone-mode) | §"Phase 5 — Section approval" |
| 6 | Write spec.md (NO auto-commit; `workflow_refs[]` copied from state.md) | §"Phase 6 — Write spec.md" |
| 7 | Mechanical validator (full check set — adds `workflow_refs_consistency`) | §"Phase 7 — Mechanical validator" |
| 7.5 | Spec challenge (always-on adversarial pass — verify claims, generate alternatives, red-team; advisory, fail-open; `--deep`: 3× verify per cited claim with majority vote) | §"Phase 7.5 — Spec challenge" |
| 8 | User approve (schema-rich AUQ + git commit) | §"Phase 8 — User approval" |
| 9 | Handoff (2 options: /geniro:implement / Stop) | §"Phase 9 — Handoff" |

Execute `plan-loop.md` end-to-end. The loop encodes every defect fix and schema gap.

---

## Loop invariants

These invariants apply throughout all phases; phase numbers and tool surface differ.

1. **One result per tool call.** Every AskUserQuestion / Write / Bash / Agent spawn produces exactly one structured result. Failed AUQ (empty-answer bug) → fall back to plain-text re-ask; never auto-default.
2. **Args validated before execution.** Bash commands constructed from $ARGUMENTS or state.md fields pass input sanity-checks. Path-based detection (design-doc-detect.md) validates file existence before treating $ARGUMENTS as a path.
3. **Permission before side-effect.** Phase 6 `Write` to `.geniro/planning/<task-dir>/spec.md` is the only mutation in the loop. `git commit` deferred to Phase 8 post-approval. No auto-mutations elsewhere — enforced by the plan-mode mutation guard (frontmatter `allowed-tools` minus `Edit`; PreToolUse Bash guard allows `Write` only under `.geniro/planning/**` or `.geniro/state/**`).
4. **Bounded and structured tool results.** Phase 1 research-agent output capped at ~4000 chars per agent; longer truncated with marker. Output schema: `[{file, lines, observation}]`. Phase 7 validator output is a structured pass/fail list per check.
5. **Escalation gates, not silent abort.** Phase 7 validator 3-round → AUQ. Phase 8 user-revision 3-round → AUQ. Phase 3 ≤5 questions → consolidation forced. NO Class-A hard kill caps.
6. **Final answer grounded in observations.** Phase 5 section content cites Phase 1 explore findings (`file:line` references), not generic prose — the Phase 7 validator includes a "citations present" check that fails an uncited section.
7. **Errors, denials, cancellations, timeouts → structured observations.** Phase 1 research-agent failures → structured entry in state.md `## Errors`. Phase 0 cancel → `## Termination reason`. Phase 7 validator findings → `## Open Questions`. Never silently skipped.
8. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

`## Tool log` schema (selective logging): entry shape is the single source of truth in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §1.3 Echo contract — fields `ts` / `tool` / `detail` / `status` plus `summary` (Agent) or `result_ref` (Write). Each entry written via `atomic_state_write`. AUQ calls do NOT need logging — `approvals[]` is the structured record.

---

## Budgets — quality-first framing

This skill has no hard kill caps. All limits are escalation gates that surface to the user, not abort triggers. User tokens are unlimited — no "task aborted: budget exhausted" failure modes.

**Quality gates (Class-B — escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Phase 3 clarifying-question count | ≤5 total (independent questions batched into one AUQ call, ≤4 per call; dependent ones sequenced) | plan-loop.md | Force consolidation OR proceed with stated assumptions. |
| Phase 7 → Phase 6 auto-revision rounds | 3 | plan-loop.md | AUQ — accept-as-is / re-revise / abort. |
| Phase 8 user-revision rounds | 3 | plan-loop.md | AUQ — accept-as-is / re-revise / abort. |
| Phase 1 research-agent output size | ~4K chars per agent | invariant #4 | Truncation with marker, not abort. |

**Architecture constraints (design intent, not budget):**
- Parallel research spawns per Phase 1: 1-4 (effort-tier-scaled per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`).
- spec.md section count: exactly 11.

**Explicitly NOT capped:** wall-time, total tool calls, total model turns, total cost. Same rationale.
**Rationale.** The ≤3 AUQ gates guideline applies to /geniro:implement, NOT /geniro:plan. /geniro:plan is a **clarification-heavy** skill — its job IS to ask questions. Rich content is rendered to chat messages (the Gate presentation contract); each gate then fires ONE lean question: Phase 3 ≤5 questions in 1-2 batched calls + Phase 4 ×1 + Phase 5 ×3 (one per cluster, not per section) + Phase 8 ×1 → ~6-7 lean AUQ calls typical. Collapsing Phase 5 from one question per section to one per cluster drops the questions the user answers there from ~11 to 3.

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
---
```

When `deep-mode: true`, Phase 4 and Phase 7.5 run their deeper paths via an internal `Workflow(...)` per `${CLAUDE_PLUGIN_ROOT}/skills/plan/deep-mode-reference.md`; persist the activation to `approvals[]` category `deep_mode_choice` so a resume re-applies it. When `--deep` is absent, a Standard/Deep depth question folds into the Phase 3 clarify AUQ (skipped on a Trivial task → flag-only there); pick Deep there to set `deep-mode: true`.

**Write contract.** Every state.md mutation goes through `atomic_state_write` from `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh`, never direct `Edit`/`Write` on canonical state paths — the State-helper enforcement hook warns now and flips to hard-block in a future release. The plan-mode mutation guard restricts Write tool to `.geniro/planning/**` OR `.geniro/state/**` while a /geniro:plan run is active.

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
| Phase 6 | `atomic_state_write` | write T1.5 | state.md `## Tool log` after spec.md Write |
| Phase 6 | `Write` | write T1.5 | spec.md frontmatter `workflow_refs[]` copied from state.md `## Workflow Refs` when present |
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
| Phase 1 (Explore) | Read / Grep / Glob / Bash (read-only) / Agent (research spawn — OMIT `model=`) / tracker MCP read (`mcp__linear__get_issue`, etc.) | Edit / Write outside state.md |
| Phase 2 (Visual Companion, UI-conditional) | Read / Agent (UI description spawn, OMIT `model=` — inherits orchestrator tier per `ui-preview-gate.md`) / AskUserQuestion / atomic_state_write (state.md `## UI Preview`) | Edit / Write outside state.md |
| Phase 3-5 (Clarify / Approaches / Section approve) | Read / Grep / Glob / AskUserQuestion / Write (state.md only via atomic_state_write) / Workflow (Phase 4 approach panel + critics, `deep-mode: true` only — OMIT `model=`) | Edit / mutating Bash |
| Phase 6 (Write spec) | Write (scoped to `.geniro/planning/**` by guard) / atomic_state_write (state.md) | Edit / mutating Bash |
| Phase 7 (Validate) | Read / atomic_state_write (state.md `## Open Questions`) | All other mutations |
| Phase 7.5 (Spec challenge, always-on) | Read / Grep / Glob / Bash (read-only) / Agent (claim-verifier spawn — OMIT `model=`) / Workflow (3× claim verify, `deep-mode: true` only) / atomic_state_write (state.md `## Errors`) | Edit / Write outside state.md / mutating Bash |
| Phase 8 (User approve) | AskUserQuestion / Bash (`git add`, `git commit` only) / atomic_state_write | Edit / general-purpose Bash |
| Phase 9 (Handoff) | AskUserQuestion / Read | All mutations |

**Mutation enforcement:** frontmatter `allowed-tools` excludes `Edit` (this skill never edits in place).

**Existing safety layer:** file-protection hook, git-guardrails, `.geniro/` deletion guard apply across all phases.

---

## Task execution entry

0. **Check for existing state.md.** Glob `.geniro/planning/*/state.md` for a file matching the resolved task slug:
- **No state.md** → fresh run. Proceed to Phase 0.
- **state.md exists, phase in non-terminal set** → resume from `phase:` value. the SessionStart hook re-injects context.
- **state.md exists, phase in terminal set** (`done` / `aborted`) → task complete. Surface terminal state to user; if $ARGUMENTS carries a new topic, derive a new slug, fresh run.

1. **Validate state.md if found** (`validate_state_file`). On fail, open recovery AUQ.

2. **TodoWrite checklist.** Add: Detect mode / Problem discovery (--prd only) / Explore codebase / Visual companion / Clarify / Propose approaches / Approve plan in groups / Write spec / Validate spec / Challenge spec / User approval / Handoff. Mark the first item in_progress; update each as it completes. The problem-discovery item is marked completed-skipped when `--prd` was not passed; Phase 2 is marked completed-skipped when the UI trigger doesn't fire.

3. **Begin Phase 0.** Execute `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` end-to-end.

---

## Anti-rationalization

Do NOT reintroduce these anti-patterns:

| Your reasoning | Why it's wrong |
|---|---|
| "I'll cram the section ADR digest into the AUQ `preview` so each option is self-contained." | The `preview` side-box is a narrow monospace panel beside the option list — too small for a Decision/Why/How digest, code examples, and diagrams; the user squints at it per option. Render the cluster to a chat message (full width, persists in scrollback) per the Gate presentation contract, then keep the AUQ options lean. Cramming content into `preview` is the exact failure mode message-first exists to fix. |
| "I'll author all 11 sections and fire one approval for the whole spec — fewer questions is strictly better." | Authoring everything before the first gate surfaces cross-section issues only after the user reads the whole plan — too late to cheaply correct. Author → render → gate ONE cluster, then the next; cluster 1 is approved before cluster 2 is authored, so each cluster builds on grounded prior content. One question per cluster (not per section, not per whole spec) is the chosen granularity — per-section `approvals[]` grain is preserved by the Revise-picker. |
| "Skip Phase 2 Visual Companion — UI intent fits in Phase 5 sections later." | Phase 2 fires only when the UI trigger matches (Phase 1 found UI files OR topic carries a UI noun). When it fires, the approved description IS the substrate Phase 5 sections 6 + 9 cite. Skipping it forces the user to describe visual intent twice (once in Phase 3 prose, again to /geniro:implement when the rendered UI doesn't match). |
| "Add a refine/edit mode that re-derives spec sections from an existing design doc — saves three phases of re-work." | Re-deriving sections from prose is structurally-lossy: downstream consumers parse a malformed spec.md. DESIGN_DOC mode offers Start-fresh-with-doc-as-context (or Cancel) precisely because starting fresh produces a schema-clean spec.md. |
| "Phase 7 mechanical validator misses cases a smart LLM would catch." | The validator checks cover the mechanical surface (including `workflow_refs_consistency`). Phase 8 user-approve catches everything else — the user IS the smart-LLM check. |
| "Auto-commit at Phase 6 is convenient — drop a commit if Phase 8 rejects." | Rejection-induced commit-drop = forced `git reset` / `git revert`, polluting git history (every revision round would leave a commit). Phase 8 post-approve commit is a single commit per approved spec. |
| "Plan-mode mutation guard is over-engineered — model can be trusted." | The model can be reasoned-with, jailbroken, or instructed via a compromised CLAUDE.md. The frontmatter `allowed-tools` field + PreToolUse Bash guard are the only mechanical layers between a bad-intent prompt and a modified source tree. Belt + suspenders. |
| "5 clarifying questions is too few for complex tasks." | Phase 3 ≤5 is a quality-first signal. >5 means Phase 1 underspecified OR the task is too vague. Force consolidation — better questions, not more questions. |
| "11-section spec.md schema is too rigid for small tasks." | Sections 4 / 5 / 10 can be "none with rationale" for Trivial. The schema is structural commitment (every consumer can rely on section presence), not content commitment. |
| "Phase 7 validator hard-fail blocks user — they're stuck with auto-revision rounds." | 3-round escalation cap. On round 3, AUQ surfaces to user with "accept as-is" option. User has agency at all times. |
| "Drop the milestone-mode AUQ — a Big task can just emit a spec and the user decides later." | Slicing into milestones IS a planning decision. Punting it to /geniro:implement time means the user discovers a 50-step spec is unmanageable, and must come back to re-plan. Phase 5 surfaces the choice when context AND attention are present. |
| "Add a wall-time / token kill cap so runaway /geniro:plan sessions abort cleanly." | Class-A hard caps forbidden by Class-B gates only (Phase 3 ≤5, Phase 7 3-round, Phase 8 3-round) — all escalate to user, not abort. |
| "Auto-default empty AUQ answer to the Recommended option." | Forbidden. Empty answer = upstream Claude Code bug; fall back to plain-text re-ask. Auto-default silently mutates user intent. |
| "Skip persisting Phase 3 clarifying answers — they're trivial." | Compaction mid-Phase-5 round 2 loses 5 AUQs of user input — that data-loss is exactly what `approvals[]` persistence prevents, so it is non-negotiable. |
| "Bypass git pre-commit hooks with --no-verify when committing spec.md in Phase 8.4." | Hooks fail for a reason. Investigate root cause, not bypass. CLAUDE.md-level prohibition; honors it. |

---

