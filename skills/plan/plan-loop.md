# Plan loop

Canonical phase pattern for `/geniro:plan`, and the spine of the loop: the phase order, the gates that bind every phase, and a pointer to the file holding each phase's steps. This file plus the phase files it names are the single source of truth for the loop. Skills cite them; do NOT inline-paste the loop logic.

**How to run the loop.** Read this spine at entry; Read a phase's steps file on entry to that phase, not up front. Pre-loading every phase file pays the whole loop to run one phase, and Claude Code re-attaches only a skill's front-loaded prefix after a summary — so what a pre-load spends its budget losing is the gates below. Read a conditional phase's file (0.5, 2, 7.5) only once its trigger fires. Each phase file ends by naming the next `phase:` value; look it up in §Phase files and Read that one. On a compaction resume, re-Read this spine plus the current phase's file.

## Contents

- HARD-GATE
- Gate presentation contract (+ Visual rendering language)
- Echo contract
- Phase files — the pointer table
- Phase 0 .. Phase 9 — one stub per phase, naming the file that holds its steps
- Terminal states
- Definition of Done
- Anti-rationalization

---

## HARD-GATE

> Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until the Phase 8 user-approve AUQ has been answered "Approve". The gate is binding for Phases 0–8. The Phase 8 "Approve" answer IS the release decision; Phase 9 only prints the next-step command after it.

---

## Gate presentation contract

Every gate that presents rich, multi-part content — Phase 0.5 problem-discovery, Phase 3 grill questions, Phase 4 approaches, Phase 5 section approval, Phase 8 final approval — follows a two-step shape: **render to chat first, then fire a lean question.**

1. **Render the content as a SEPARATE chat message FIRST.** Write the full detail to chat as its own already-emitted assistant message, in the Visual rendering language below — full width, persists in scrollback, and it is where the user reads and understands the plan. It must exist before the question fires, and the render and the AUQ tool call must never share one assistant turn; the separate-message rule and its rationale are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering.

2. **Then fire a LEAN `AskUserQuestion`.** Options are short decision selectors (Approve / Revise / Cancel-style), each with a one-line `description`. The `preview` side-box is NOT the rendering surface — leave it empty, or use it for a one-line recap only; the reason it cannot carry a digest, code, or diagrams is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions. Before firing, run the canonical render-exists check in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering (the render-exists and resume-path rules apply identically here). Firing is part of the render's own action, never a follow-up that can be dropped — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard.

### Visual rendering language

The Phase 4, Phase 5, and Phase 8 gate messages render in the shared visual language defined canonically in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Visual rendering language — progress tracker, one-sentence opener, friendly digest blocks (lead sentence / `**Why:**` with evidence cite / `**How it gets built:**` / `**You'll see:**`), a visual per unit, light heading icons, closed against the plain-English bar. The plan instantiation:

- **Journey stops.** The tracker runs over the stops `Approach · Goal & scope · Steps · Safety · Final approval` (the three middle stops are the Phase 5 clusters under short display labels). Example at Phase 5 cluster 1: `✔ Approach · ● Goal & scope (step 1 of 3) · ○ Steps · ○ Safety · ○ Final approval`. When Trivial tier collapses clusters, show the collapsed stops.
- **Per-section visuals.** Every section or approach carries the visual shape mapped in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §"Plan-unit visual map" — scope map, steps flow diagram, risks table, done-condition checklist, approach data-flow; render plain text instead only when a section genuinely has nothing to map (e.g., "none — task scope precludes"). Each section also closes on a concrete example of its content, per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-reference.md` §"Concrete example per section type".
- **Section-heading icons** — e.g. 🎯 objective / 📦 included / 🚫 excluded / ⚠️ risks / 🧪 validation / ↩️ rollback / ✅ done.

**One decision per logical unit.** Phase 5 fires ONE question per cluster (not one per section); Phase 4 fires ONE question for the approach choice; Phase 8 fires ONE question for the whole spec. Collapsing per-item questions into one-per-unit stops the gate from re-asking decisions the user already settled upstream (in clarify / approaches), which is the click-through fatigue this contract also prevents. Per-decision persistence granularity is unchanged — a unit-level approval still writes one `approvals[]` entry per item it covers (Phase 5 §5.2).

---

## Echo contract

Cross-phase: Phase 1 research spawns, the Phase 3 grill's on-demand research spawns, the Phase 4 stress-test critics, and the Phase 6 spec write all append an entry of this shape, so it lives in the spine rather than in one phase's file.

Each Phase 1 research spawn writes a structured entry to state.md `## Tool log` via `atomic_state_write`:

```yaml
## Tool log
- ts: 2026-05-17T10:42:13Z
 tool: Agent
 detail: "Research: existing auth flow integration points"
 status: ok
 summary: "found 3 files, 1 convention pattern"
 citations:
 - src/auth/oauth.ts:42-58
 - src/auth/__tests__/oauth.test.ts:14-29
 - src/middleware/session.ts:88-101
```

Phase 7 validator (check #3) requires ≥1 Agent entry with `status: ok` per effort tier (Trivial ≥1 OR explicit "scope-bound, no exploration needed"; Small ≥1; Medium ≥2; Big ≥3). The Echo contract makes "no related code found" auditable via SessionStart re-injection.

---

## Phase files

Each phase's steps live in its own file under `${CLAUDE_PLUGIN_ROOT}/skills/plan/`. Read the file on entry to the phase; when a phase's Fires column names a trigger that did not fire, skip the phase and its file entirely.

| Phase | state.md `phase:` | Fires | Steps file |
|---|---|---|---|
| 0 Mode detect | `mode-detect` | always | `loop-phase-0-mode-detect.md` |
| 0.5 Problem discovery | `problem-discovery` | only when `prd_mode: true` (the `--prd` flag) | `loop-phase-0.5-problem-discovery.md` |
| 1 Explore | `explore` | always | `loop-phase-1-explore.md` |
| 2 Visual Companion | `visual-companion` | only when the §2.1 UI trigger matches | `loop-phase-2-visual-companion.md` |
| 3 Grill | `clarify` | always, except the §1.5 Trivial skip (which drops Phases 2 + 3) | `loop-phase-3-grill.md` |
| 4 Approaches | `approaches` | always | `loop-phase-4-approaches.md` |
| 5 Section approval | `section-approve` | always | `loop-phase-5-section-approval.md` |
| 6 Write spec.md | `write-spec` | always | `loop-phase-6-write-spec.md` |
| 7 Mechanical validator | `validate` | always | `loop-phase-7-validator.md` |
| 7.5 Spec challenge | `spec-challenge` | only when the Phase 1.2 effort tier is Big OR state.md has `deep-mode: true` | `loop-phase-7.5-spec-challenge.md` |
| 8 User approval | `user-approve` | always | `loop-phase-8-user-approval.md` |
| 9 Handoff | `handoff` | always | `loop-phase-9-handoff.md` |

Two cross-phase files, both conditional:

- `loop-artifact-call-sites.md` — the visual plan artifact's first publish plus every per-gate call site. Read at §1.5 only when `artifact_mode: true`; without artifact mode every **Artifact** line in a phase file is a silent no-op and this file is never loaded.
- `loop-definition-of-done.md` — the run-completion checklist. Read at Phase 9, before the terminal `phase:` write.

The table is the phase order. Any phase may branch to the `aborted` terminal on cancel; a Phase 7 validator hard-fail re-enters write-spec, and a Phase 8 revision re-enters section-approve.

---

## Phase 0 — Mode detect

`phase: mode-detect`. Steps in `loop-phase-0-mode-detect.md`: §0.1 $ARGUMENTS + opt-in-flag + launch-modifier resolution · §0.2 DESIGN_DOC mode AUQ · §0.2.5 visual-artifact opt-in · §0.3 task-dir + state.md creation · §0.4 cancel handling.

## Phase 0.5 — Problem discovery (opt-in, fires only on `--prd`)

`phase: problem-discovery`. Steps in `loop-phase-0.5-problem-discovery.md`: §0.5.1 interview dimensions · §0.5.2 persistence · §0.5.3 feed-forward · §0.5.4 transition.

## Phase 1 — Explore

`phase: explore`. Steps in `loop-phase-1-explore.md`: §1.1 memory layer loading · §1.1b branch freshness · §1.2 effort-tier-scaled research spawns · §1.4 workflow refs fetch (tracker linkage) · §1.5 transition to Phase 2 (drain, synthesis, the Trivial skip). §1.3 Echo contract is the §Echo contract above.

## Phase 2 — Visual Companion (UI-conditional)

`phase: visual-companion`. Steps in `loop-phase-2-visual-companion.md`: §2.1 trigger detection · §2.2 UI preview procedure · §2.3 persistence · §2.4 routing-out signal. The §2.1 trigger is evaluated at the §1.5 transition, which also names the phase entered when it does not match.

## Phase 3 — Grill (decision-tree clarification)

`phase: clarify`. Steps in `loop-phase-3-grill.md`: §3.1 build the decision tree · §3.2 AUQ shape · §3.3 persistence · §3.4 checkpoint gate and termination.

## Phase 4 — Approaches

`phase: approaches`. Steps in `loop-phase-4-approaches.md`: the deep-mode branch · §4.1 approach generation · §4.2 independent stress-test · §4.2.5 build-vs-buy library reuse · §4.3 present approaches (message-first) · §4.4 persistence.

## Phase 5 — Section approval

`phase: section-approve`. Steps in `loop-phase-5-section-approval.md`: §5.1 section template (the standard spec schema, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`) · §5.2 cluster approval · §5.3 milestone-mode.

## Phase 6 — Write spec.md

`phase: write-spec`. Steps in `loop-phase-6-write-spec.md`: §6.1 write contract (including the `workflow_refs[]` copy and the `m5-v1`/`m5-v2`/`m5-v3` schema-version rule) · §6.2 no auto-commit · §6.3 milestone-mode write fan-out · §6.4 idempotent re-entry (compaction-safe). This is the canonical writer of all three design-doc detection markers.

## Phase 7 — Mechanical validator

`phase: validate`. Steps in `loop-phase-7-validator.md`: §7.1 mechanical pass-through · §7.2 validator checks · §7.3 hard-fail handling · §7.4 no transition to Phase 7.5 if the validator hard-fails.

## Phase 7.5 — Spec challenge

`phase: spec-challenge`. Steps in `loop-phase-7.5-spec-challenge.md`: §7.5.1 invoke the challenge helper · §7.5.2 verdict handling · §7.5.3 advisory + fail-open. §7.4 owns the gate that decides whether this phase is entered at all.

## Phase 8 — User approval

`phase: user-approve`. Steps in `loop-phase-8-user-approval.md`: §8.1 approval gate · §8.2 shape (message-first) · §8.3 revision-round escalation · §8.3.5 launch config · §8.4 approve → git commit (step 2 carries the write-time `launch_config` enum assertion) · §8.5 L2 emit · §8.6 suggest improvements · §8.7 custom post-approval steps.

## Phase 9 — Handoff

`phase: handoff`. Steps in `loop-phase-9-handoff.md`: §9.1 print next-step command · §9.2 clean up transient working files · §9.3 terminal transition.

---

## Terminal states

`done` and `aborted`. Every transition into either one first runs the §9.2 transient cleanup (`clean_task_transients` against the planning task-dir, in `loop-phase-9-handoff.md`) and only then writes the terminal `phase:` via `atomic_state_write` — a terminal write that skips the cleanup leaves this run's scratch behind, where it resurfaces as a recurring `/geniro:update` migration-walk warning. An `aborted` write also carries a `## Termination reason` body line naming what cancelled it. The cancel paths are §0.4, §5.2, §7.3, and §8.3; each owes the same cleanup-then-write.

## Definition of Done

The run-completion checklist is `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-definition-of-done.md`. Walk it at Phase 9, before the terminal `phase: done` write.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This task is too simple to need a design" | "Simple" projects are where unexamined assumptions cause the most wasted work. Design can be short (Phase 5 Trivial = sections 4 / 5 / 10 with body "none with rationale"); presenting and approving is mandatory. HARD-GATE applies to EVERY task. |
| "I'll skip Phase 8 user re-review, my Phase 7 validator is enough" | Validator catches mechanical defects (placeholders / contradictions / scope creep); user catches intent defects (wrong abstraction / missing constraint). Different defect classes; both required. |
| "I'll cram the section digest into the AUQ `preview` so each option is self-contained" OR "the question can just say 'rendered above' — I'll skip authoring the message" | The `preview` side-box is a narrow monospace panel beside the option list — too small for a section digest, code examples, and diagrams; the user squints at it per option. Render the cluster as a SEPARATE chat message (full width, persists in scrollback) per the Gate presentation contract, in its own turn before the question — never same-turn with the AUQ. A question pointing at "the message above" when no such message was emitted gets a blind approval (observed: a deep run approved 8 sections + the final spec against five non-existent renders). Cramming content into `preview`, or referencing a render that does not exist, are the two failure modes message-first exists to fix. |
| "I'll author all 11 sections and fire one approval for the whole spec — fewer questions is strictly better" | Authoring everything before the first gate surfaces cross-section issues only after the user reads the whole plan — too late to cheaply correct. Author → render → gate ONE cluster, then the next; cluster 1 is approved before cluster 2 is authored, so each cluster builds on grounded prior content. One question per cluster (not per section, not per whole spec) is the chosen granularity — per-section `approvals[]` grain is preserved by the Revise-picker, so collapsing the questions loses no grain. |
| "I'll write the design doc with only the YAML frontmatter — that's enough" | Defense in depth requires all three markers (path + HTML comment + frontmatter). See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` § Why defense in depth — each marker survives a different user action. |
| "Phase 4 — 4 or 5 approaches gives the user more choice" | More than 3 indicates Phase 3 didn't narrow scope; loop back to Phase 3 with a tighter scope-boundary question. |
| "My §4.1 approaches are well-reasoned — the §4.2 stress-test is redundant overhead" | The model that authored the approaches shares their blind spots; ranking them in the same context re-confirms its own bias rather than testing it. An independent codebase-grounded critic catches blockers the author cannot see from generation context alone — hidden coupling, a previously-rejected shape in L2, a convention conflict — which is the load-bearing reason `Recommended` is set from evidence, not self-confidence. It is tier-scaled (skipped on Trivial) so the cost lands only where a wrong approach is expensive. The critic's verdicts are themselves claims: a `blocking` call demotes only after its citation verifies on read, and a no-risks report without its checked-surfaces account is absence of investigation, not evidence of feasibility. |
| "Auto-commit at Phase 6 is convenient — drop a commit if Phase 8 rejects" | Rejection-induced commit-drop = forced `git reset` / `git revert`, polluting git history (every revision round would leave a commit). Phase 8 post-approve commit is a single commit per approved spec. |
| "I'll skip persisting Phase 3 clarifying answers — they're trivial" | Compaction mid-Phase-5 loses 5 AUQs of user input — that data-loss is exactly what `approvals[]` persistence prevents, so it is non-negotiable. |
| "I'll write a file outside `.geniro/planning/**` to save a step — /geniro:plan can touch source directly" | /geniro:plan never writes source. The frontmatter `allowed-tools` omits `Edit`, and the only intended write target is the planning task-dir (spec.md / state.md via `atomic_state_write`); writing source files turns planning into implementation and skips the HARD-GATE that exists to keep code changes behind the Phase 8 approval. |
| "Add a refine/edit mode that re-derives spec sections from an existing design doc — saves three phases of re-work" | Re-deriving sections from prose is structurally-lossy: downstream consumers parse a malformed spec.md. DESIGN_DOC mode offers Start-fresh-with-doc-as-context (or Cancel) precisely because starting fresh produces a schema-clean spec.md. |
| "Handoff should add a separate backlog-capture step for backlog discipline" | The committed spec.md on disk IS the backlog entry — no extra capture step or menu pick needed. Not running the printed `/geniro:implement` command is how a spec stays parked. |
| "Auto-default empty AUQ answer to the Recommended option" | Forbidden. Empty answer = upstream Claude Code bug; fall back to plain-text re-ask. Auto-default silently mutates user intent. |
| "Add a wall-time / token kill cap so runaway /geniro:plan sessions abort cleanly" | Hard kill-caps conflict with quality-first framing. /geniro:plan has bounded gates (Phase 3 grill checkpoint, Phase 5 per-cluster 3-round, Phase 7 3-round, Phase 8 3-round) that escalate to the user; do not abort. |
| "Bypass git pre-commit hooks with --no-verify when committing spec.md in Phase 8.4" | Hooks fail for a reason. Investigate root cause, not bypass. CLAUDE.md-level prohibition; honors it. |
