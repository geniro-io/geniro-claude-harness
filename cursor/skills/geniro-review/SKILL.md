---
name: geniro-review
description: "Use when pending changes (a diff, branch, or PR) need a code review. Parallel per-dimension reviewers; verified findings land in a handoff for /geniro:implement. Never edits code; asks before posting to a PR."
context: main
---
<!-- Generated from skills/review/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->


# Code review skill

## Contents

- Your role · State machine · Loop invariants
- Anti-rationalization · Definition of done · Spec metadata contract · Subagent spawning
- Phase 1 / 1.5 / 2 / 3 / 4 / 5 / 6 — one section each, pointing at that phase's file · REFERENCE

---

This file is the spine. **Read the phase's Steps on entry to that phase** — the file each Phase section below names, under `${CLAUDE_PLUGIN_ROOT}/skills/review/`. That Read is the phase's physically-first action and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the phase files hold this skill's gates and helper call sites, so work started before the Read runs outside them.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is a placeholder Claude Code substitutes into file references, not a shell export — it reads empty in Bash under every host, so an empty probe proves nothing (`CLAUDECODE` marks Claude Code). Resolve the root from the first rung that holds: the ancestor of this file's real path (symlinks followed) containing `.claude-plugin/plugin.json`; a copy of the referenced file beside this one (the Cursor build); a plugin checkout in the workspace. The run's first Bash call prints this file's real directory and checks the rungs against it; echo that output verbatim before anything else (a resolved ladder is bookkeeping: add a degraded-run notice only for a rung that failed), then substitute the resolved root everywhere and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. A path the output does not show did not resolve. Before deciding a step cannot run here, read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` — it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not:** name what is unavailable in your first message, run every phase and gate this skill declares, never let project rules stand in for its decision gates, and take no outward-facing action (ready PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

---

## Your role — orchestrate, don't review

You are a **coordinator**. Delegate review work to parallel `reviewer-agent` spawns and validate their outputs in the judge pass. Read files only to gather context and verify findings — a coordinator that reviews inline inherits the reviewers' blind spots, so the judge pass stops being independent.

`/geniro:review` is a **Reporter**: it never applies fixes. Findings persist to a handoff file; downstream consumers (`/geniro:implement`, manual user action) apply them. Full boundary: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`. Each phase file states its own tool surface; in every phase, production source and rules stay unedited and writes beyond state files are limited to the run's scratch directory (review packet, optional brief).

---

## State machine

State.md `phase:` enum transitions:

```
[entry] → triage → mechanical-prepass → llm-spawn → filter → stratify → persist → action-gate → done
│
├── escalated ── (round-N user pick)
└── aborted ── (round-limit / safety / tool-unavailable)
```

**Terminal states:** `done` (includes a Phase 6 handoff line), `aborted` (writes a `## Termination reason` body section), `escalated` (round-limit hand-off; the reason lands in `## Open Questions` — mapping: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §9). A review resumes only when the user re-invokes `/geniro:review`: Phases 1-4 persist directly to `from-review-<branch>.md` (the handoff file — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §"`/review`" producer note), which the SessionStart restore hook does not surface. Re-invoking rolls every **non-terminal** state back to phase-entry and re-runs from there — idempotent, because `approvals[]` makes the Phase 6 AUQ skip already-answered picks.

**After a compaction, re-Read the phase file for the phase `phase:` says you are resuming** — a phase reconstructed from a summary's recollection is how a spawn batch or a gate gets skipped.

---

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply, with review-specific bindings:

- **Invariant #1 (one result per tool call)** — binds each Phase 2 parallel reviewer spawn; a dead one gets its `status: failed` entry in `## Tool log`.
- **Invariant #2 (args validated)** — `$ARGUMENTS` flag parsing is semantic, no CLI grammar; a PR ref validates via a live GitHub lookup (`phase-1-pr-reference.md` §1).
- **Invariant #3 (permission before side-effect)** — the Phase 6 Action gate always fires and waits before any post to GitHub; never auto-post, never substitute a chat-text suggestion for it. The post creates a PENDING review that /geniro:review never submits, on any round — submitting is the user's own github.com action (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.4). Every user-facing choice routes through `AskQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions.
- **Invariant #4 (bounded results)** — reviewer-agent output is capped per dimension by its own contract (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output cap).
- **Invariant #5 (escalation gates)** — round-N ≥3 fires the Phase 1 round-N gate first (`phase-1-triage-reference.md` §7 step 4: Continue / Escalate); Escalate exits terminal before Phase 6 is reached. A Continue pick lets the Phase 6 Round-N gate (`review-handoff.md` §5, Continue / Escalate / Abort) fire as its conditional follow-on, whose hard ceiling lives there. No other hard kill caps — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies.
- **Invariant #6 (grounded in observations) — binds at every kept severity.** The Phase 6 handoff message cites the state.md path so the user can audit the source; every REPORTED CRITICAL / HIGH / MEDIUM finding carries an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` quoting the cited file or caller chain literally, because a severity claim without a literal quote is unverifiable. This binds at emit, not at admission: a CRITICAL or HIGH may enter Phase 4.2 on a thin citation, and the verifier (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §3) supplies the quote.
- **Invariant #7 (errors → structured observations)** — reviewer spawn failures land in the `## Errors` body section; `gh` fail-open is not silent — log it there too.

This skill adds three invariants:

S1. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.
S2. **Re-verify ambiguity gates at external-effect boundaries.** Upstream gates establish invariants on `open_questions[].status`, PRODUCT-DECISION `step0_status:`, kept-finding `Validation:`, and `report_status:`; the Pre-Post guard (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.0) re-reads all four before any `gh api POST /reviews`, because mid-phase producer writes, parallel resolvers, or drift can re-create ambiguity between gate and write.
S3. **Stamp `phase:` on entry, before the phase's work.** A checkpoint written only at the end records history, not current state: a crash mid-phase leaves no resumable marker, and a declaration the phase produces (`spawn_dims_declared`, written before the spawns) lands too late to power the gate reading it. A phase counts DONE only once its trailing steps complete — stamp `persist` only after the §5.3 emits have run, or stamp the next phase at its own entry.

**Turn boundaries.** A turn ends in exactly three places: on a fired approval question, on reaching a terminal `phase:` state, or when the user asked something and is owed the answer. Everywhere else the next action follows in the same turn, with a tool call — between steps, after a check comes back green, after a state write, at a phase transition, and when a subagent's result lands. A status report, a checkpoint summary, and a list of what remains are continuations, not endings: write one where it helps the user follow along, then take the next action in that same turn. A decision that needs the user is asked as a real question in the turn that raises it, its render and the question inside that one turn (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard) — a question left in prose, or announced for a later message, leaves the run waiting on an answer the user was never asked for. Reversibility is not the test: a deviation from a rule this run loaded is a gate however cheap it is to undo.

**Compaction.** The host re-attaches only the first stretch of this file after a summary, so its later sections arrive missing, with a truncation marker standing in for them. Treat that marker as an instruction: in the turn you notice it, re-read this file and the running phase's body before relying on anything the truncation removed. When you compose a compaction summary, record state — what ran, what remains, what the user decided — never a directive to yourself about stopping, confirming, or awaiting direction. A resumed session reads its summary as fact and will honour it over this file, so work still to do is recorded as work still to do, not as something to ask permission for.

`## Tool log`: one entry per reviewer spawn, one per Phase 5.3 emit-learning, and one per PR-side-effect.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "/geniro:review should fix its own findings — parity with /geniro:implement self-review" / "I'll auto-update Linear status when findings are critical" | Both breach the Reporter boundary. That self-review is a post-implementation gate inside a mutation skill; this is a read-only audit consumed downstream — route fixes to /geniro:implement. Linear `update_issue` / `create_comment` belong to /geniro:plan and /geniro:implement; this skill's MCP surface is read-only, and `open_questions[]` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2) surfaces ambiguity without mutating tracker state. A `Workflow(...)` wrapper or ultracode suspends none of it. |
| "Mechanical pre-pass is too slow — skip it, LLM reviewers cover the same ground." | LLM reviewers cover similar ground at ~100× the cost with non-deterministic output; lint detects a missing import faster and more reliably than a security reviewer would. Run the cheap-deterministic pass first and feed its findings to the LLM spawns as prior-context. |
| "I'll spawn only 4 dimensions — they cover the main risk surface." | Silent coverage cut: an orchestrator-judgment trim is forbidden at any diff size. The only sanctioned narrowing is the declared, size-and-risk-tier scaling in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-grid-scaling.md` — forced back to the full grid at `risk-tier:high` — and even that narrowed set is recorded in `spawn_dims_declared[]` and announced in the spawn echo before the batch fires. A count reached by "this diff feels small" rather than by that table is the cut this row blocks. N parallel spawns cost ~max(spawn-time), NOT sum, while a missed CRITICAL costs unboundedly; §4.0 catches an undeclared trim, never a declared one. |
| "Skip custom-reviewer discovery — that `review-extra/<slug>.md` is narrow scope." | Silent coverage cut: discovery is a cheap Glob + parse done in the pre-pass (§1.5.4), and the user authored those reviewers on purpose. |
| "The conventions dim is overloaded — drop its authored-rule check or sibling-sampling pass." | Silent coverage cut: the conventions dim owns three concern classes by contract (§2.1); its only sanctioned quiet path is structural — no authored rule files in the repo → no authored-rule input (§2.8), the other two unchanged. |
| "I'll tag this LOW as MEDIUM to clear the threshold" / "Auto-drop MEDIUMs to reduce friction" / "This PRODUCT-DECISION is only LOW — defer it" | Severity (impact-if-wrong) and decision-type (who-decides) are orthogonal — never collapse one into the other. Inflating LOW→MEDIUM games the §4.1 gate, which reads severity directly, and corrupts the taxonomy for the verifier, the stratifier, and /geniro:implement; §1's per-tier EXCLUSION lists (cosmetic and process items are excluded from MEDIUM by name) and the Phase 4.2 verifier re-reading everything admitted are what disqualify it. Dropping is equally untrustworthy: sub-threshold MEDIUMs go to `## Deferred — sub-threshold` for awareness (users notice when their MEDIUMs vanish). A PRODUCT-DECISION names a call only the user can close, so §4.1 Path B keeps and surfaces it at any severity. |
| "The findings look obviously postable — batch-post and tell the user after" | An external write escaping its gate is never justified by how obvious the outcome looks, and chat text is never a gate (invariant #3). The Action gate's "Post" pick IS the consent for a PR post. Fire the gate and act on its pick — the render is what makes consent auditable and persisted to `approvals[]`. |
| "Inline LINEAR CONTEXT into every dim — more context = better review" / "regressions feels redundant with spec-compliance, skip it when there's a spec" | Both re-design the dimension grid from intuition. LINEAR CONTEXT helps spec-compliance, pr-metadata, architecture, and regressions; other dims read it as noise biasing their per-file rubric. Spec-compliance covers diff-omits-spec-item while regressions covers diff-exceeds-stated-intent — inverse directions, not duplicates; regressions also fires on spec-less PRs. |
| "Per-finding verifier agreed with the finding — confirmation logged, done." | Confirmation without an `evidence:` quote from the cited file or caller chain is rationalization theater: no literal code quoted means no verification happened — re-spawn with a stricter prompt. Sycophancy guards: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §6. |
| "Round 1 returned clean. Run round 2 to confirm / get a nicer summary / second opinion." | Clean = Done. Extra rounds waste compute AND risk hallucinated findings against an empty diff; once a round exits with zero kept findings, the Action gate is terminal. |
| "The spawn list is already visible in the tool calls — the echo line is redundant." | The echo is the user's only plain-English record of what fired, and the human-visible baseline for the §4.0b instance check. A dropped echo preceded a real incident: 33 undisclosed spawns, user interrupt mid-run. Emit it in the SAME message that fires the batch — welded, never a separate turn. |

---

## Definition of done

The run-completion checklist is `${CLAUDE_PLUGIN_ROOT}/skills/review/review-definition-of-done.md`. Walk it at Phase 6, before the terminal `phase:` write.

## Spec metadata contract (/geniro:plan → /geniro:review)

When a spec.md is resolvable, parse its frontmatter `workflow_refs[]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md`. Accepted `geniro_schema_version`: `m5-v1` (treat `workflow_refs` as absent), `m5-v2`, `m5-v3`, `m5-v4`; per-version fields and the merge with `$ARGUMENTS` / PR-body tracker refs: `phase-1-triage-reference.md` §3.5.1 step 4. Never mutate tracker state.

---

## Subagent spawning

Plugin agents declare `model: inherit` — OMIT `model=` at every spawn site. Spawn `subagent_type="geniro:<agent>"` under Claude Code, bare `subagent_type="<agent>"` on any other host whose agent-type list carries it, else that host's general-purpose type with the agent body inlined. `--subagent-model <tier>` in `$ARGUMENTS` passes `model="<tier>"` at every judgment-grade spawn instead — announce the pinned tier once at run start. The flag only lowers the scoped `knowledge-retrieval-agent` (Phase 1), whose ceiling is `sonnet`; it never raises it. Spawn list, registration ladder, and the flag's reach: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-2-spawns.md` §2.4.

---

## Phase 1 — Triage & context collect

`phase: triage` · Steps: `phase-1-triage.md`. Resolve the target; load PR, tracker, plan, memory context. Exit when frontmatter holds `round`, `risk-tier`, `pr-ref`, `linear-task-ref`, `linear-parent-ref`, `plan-context-ref`, `subagent-model`, a `brief` resolved to `artifact` / `file` / `off`, and `approvals[]` holds any AUQ answers.

## Phase 1.5 — Mechanical pre-pass

`phase: mechanical-prepass` · Steps: `phase-1-triage.md` §1.5.1-§1.5.7. Three deterministic checks (lint / schema / secret scan) before any LLM spawn. Exit when each check has landed exactly one recorded outcome — `findings`, `clean`, or `error` — declared in `mechanical_prepass_attempted`.

## Phase 2 — LLM reviewer spawns

`phase: llm-spawn` · Steps: `phase-2-spawns.md` §2.1-§2.9. Fire one `reviewer-agent` per triggered dimension as a single parallel batch — each prompt naming the review packet (the batch's shared context, written once beforehand, §2.3) — joined in that same response by the orientation-brief spawn when Phase 1 §13 accepted one (§2.3.2). Exit when every declared dimension returned a structured result or a `status: failed` entry, with `spawn_dims_declared[]` + `spawn_dims_count` written BEFORE the batch fired.

## Phase 3 — Filter & aggregate

`phase: filter` · Steps: `phase-3-4-filter-stratify.md` §3.1-§3.3. Orchestrator-inline dedup, convergence counting, KEEP/FILTER judgment — no subagent. Exit when every finding is deduped with a `convergence_count` and is either KEEP or in `## Filtered` with a reason.

## Phase 4 — Stratification & verification

`phase: stratify` · Steps: `phase-3-4-filter-stratify.md` §4.0-§4.2 — post-spawn verification gate, **§4.1 multi-signal admission gate**, per-finding verification. Exit when every admitted CRITICAL / HIGH / MEDIUM finding carries a verifier verdict (or `Validation: unverified`) and refuted ones sit in `## Filtered`.

## Phase 5 — Persist & emit

`phase: persist` · Steps: `phase-5-6-emit-handoff.md` §5.0, §5.1 and §5.3-§5.5. Exit when `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` exists via `atomic_state_write` with `report_status: draft` and structured `open_questions[]`, and the §5.3 convergence emits have run.

## Phase 6 — Action gate handoff

`phase: action-gate` · Steps: `phase-5-6-emit-handoff.md` plus `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §1-§5 and §8-§9; the Post drill (§7.0-§7.8) is `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff-post.md`, read only on the "Post Draft PR review" pick. Exit when the open-question, open-decision, and Action gates have each fired with their picks persisted to `approvals[]`.

---

## REFERENCE

Each phase file cites its own deeper contracts. Under `${CLAUDE_PLUGIN_ROOT}/skills/review/`: `phase-1-triage-reference.md` (Phase 1 contract) · `phase-1-pr-reference.md` (PR-side fetches + peer-PR scout, PR-ref runs only). Under `${CLAUDE_PLUGIN_ROOT}/skills/_shared/`, beyond those cited above: `plan-context.md` · `review-brief.md` · `flags-reference.md`.
