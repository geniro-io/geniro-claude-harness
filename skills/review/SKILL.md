---
name: review
description: "Use when a comprehensive code review of pending changes (a diff, branch, or PR) is needed. Reporter workflow: triage, a cheap mechanical pre-pass, then parallel single-dimension reviewers (bugs, security, architecture, tests, regressions, conventions, and more, plus any custom ones) whose findings are filtered and individually verified, then persisted. Emits a handoff file at .geniro/state/handoff/from-review-<branch>.md; downstream consumers (/geniro:implement, or you manually) apply the fixes — review never edits code itself, and asks before authoring tests or posting to a PR. Optional --deep reviews each check from several angles and majority-verifies contested findings (higher quality, higher cost)."
context: main
model: inherit
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent, AskUserQuestion, WebSearch, EnterWorktree, ExitWorktree, Workflow]
argument-hint: "[files, diff range, branch, or PR ref (#N, URL)] [--plan <path>] [--deep]"
---

# Code review skill

Comprehensive code review using parallel multi-agent analysis. This file is the spine — role, invariants, gates, phase map. **Read the phase's Steps on entry to that phase**, from `${CLAUDE_PLUGIN_ROOT}/skills/review/`: `phase-1-triage.md` (Phases 1 + 1.5) · `phase-2-spawns.md` (Phase 2) · `phase-3-4-filter-stratify.md` (Phases 3 + 4) · `phase-5-6-emit-handoff.md` (Phases 5 + 6).

**Runtime portability.** Claude Code sets `${CLAUDE_PLUGIN_ROOT}`. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference — it is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it everywhere and export it in every Bash call. Tool and hook substitutions: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md`.

---

## Your role — orchestrate, don't review

You are a **coordinator**. Delegate review work to `reviewer-agent` instances via the Agent tool and validate their outputs in the judge pass. Do NOT review code yourself — read files only to gather context and verify agent findings.

`/geniro:review` is a **Reporter**: it never applies fixes. Findings persist to a handoff file; downstream consumers (`/geniro:implement`, manual user action) apply them. The Phase 6 handoff message omits "I'll fix these now" language — that phrasing implies a fixer responsibility this skill does not have. A `Workflow(...)` / ultracode wrapper parallelizes the reviewer fan-out, not the Reporter contract; full boundary at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.

---

## State machine

State.md `phase:` enum transitions:

```
[entry] → triage → mechanical-prepass → llm-spawn → filter → stratify → persist → action-gate → done
│
├── escalated ── (round-N user pick)
└── aborted ── (round-limit / safety / tool-unavailable)
```

**Terminal states:** `done`, `aborted`, `escalated` — SessionStart recovery treats all three as "review complete / cancelled". `done` includes a Phase 6 handoff line; `aborted` writes a `## Termination reason` body section; `escalated` (round-limit hand-off) surfaces its reason in `## Open Questions` instead (mapping: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §9). Recovery rolls the seven **non-terminal** states back to phase-entry and re-runs from there — idempotent, because `approvals[]` makes the Phase 6 AUQ skip already-answered picks.

**After a compaction, Read the phase file for the phase you are resuming.** Claude Code re-attaches only this spine; the Steps are gone. Reconstructing a phase from a summary's recollection instead of its actual steps is how a spawn batch or a gate gets skipped. `phase:` says where to resume.

---

## Loop invariants

1. **One result per tool call.** Phase 2 parallel-spawn reviewer-agents — each must return a structured result; a dead spawn gets a `status: failed` entry in `## Tool log`.
2. **Args validated before execution.** `$ARGUMENTS` flag parsing (semantic, no CLI grammar); PR ref validation via `mcp__github__pull_request_read` or GraphQL fallback.
3. **Permission before side-effect.** Phase 6 "Post Draft PR" requires AUQ approval before posting to GitHub — the action gate always fires and waits first; never auto-post, never substitute a chat-text suggestion for it. The post creates a PENDING review that /geniro:review never submits, on every round — submitting is the user's own github.com action (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.4). State.md writes go through `atomic_state_write`.
4. **Bounded and structured tool results.** Reviewer-agent output ~4000 chars per dim; truncation marker. Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.
5. **Escalation gates, not silent abort.** Round-N ≥3 → Phase 6 escalation gate.
6. **Final answer grounded in observations — at every kept severity.** The Phase 6 handoff message cites the state.md path so the user can audit the source; every REPORTED CRITICAL / HIGH / MEDIUM finding carries an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` quoting the cited file or caller chain literally, because a severity claim without a literal quote is unverifiable. This binds at emit, not at admission: a CRITICAL or HIGH may enter Phase 4.2 on a thin citation, and the verifier (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §3) is what supplies the quote for every §4.1 survivor.
7. **Errors → structured observations.** Reviewer spawn failures → `## Errors` body section. `gh` fail-open is NOT silent — log it there too.
8. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.
9. **Re-verify ambiguity gates at external-effect boundaries.** Upstream gates establish invariants on `open_questions[].status`, PRODUCT-DECISION `step0_status:`, kept-finding `Validation:`, and `report_status:`; the Pre-Post guard (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.0) re-reads all four before any `gh api POST /reviews`, because mid-phase producer writes, parallel resolvers, or drift can re-create ambiguity between gate and write. Never trust an upstream gate's invariant at a public-surface boundary.
10. **Stamp `phase:` on entry, before the phase's work.** A checkpoint written only at the end records history, not current state: a crash mid-phase leaves no resumable marker, and a declaration the phase produces (`spawn_dims_declared`, written before the spawns) lands too late to power the gate reading it. A phase counts DONE only once its trailing steps complete — stamp `persist` only after the §5.3 emits have run, or stamp the next phase at its own entry.

**Turn-completion check (canonical, un-numbered).** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard: never stop on an announced-but-unfired question.

`## Tool log`: a typical run produces 5-12 entries (1 per reviewer + 1 per Phase 5.3 emit-learning + 1 per PR-side-effect).

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "/geniro:review should fix its own findings — parity with /geniro:implement self-review" / "I'll auto-update Linear status when findings are critical" | Both breach the Reporter boundary. That self-review is a post-implementation gate inside a mutation skill; this is a read-only audit consumed downstream, so parity would restore the deleted fixer responsibility — route fixes to /geniro:implement. Linear `update_issue` / `create_comment` belong to /geniro:plan and /geniro:implement; this skill's MCP surface is read-only per ACI, and `open_questions[]` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2) surfaces ambiguity without mutating tracker state. A `Workflow(...)` wrapper (including `--deep`'s recall/vote workflows) or ultracode suspends none of it. |
| "Mechanical pre-pass is too slow — skip it, LLM reviewers cover the same ground." | LLM reviewers cover similar ground at ~100× the cost with non-deterministic output; lint detects a missing import faster and more reliably than a security reviewer would. Run cheap-deterministic first, LLM-spawn second with the pre-pass findings as prior-context. |
| "I'll spawn only 4 dimensions — they cover the main risk surface" / "skip custom-reviewer discovery, that `review-extra/<slug>.md` is narrow scope" / "the conventions dim is overloaded — drop its authored-rule check or sibling-sampling pass" | Each is a silent coverage cut. Every always-fire dim per §2.1 is MANDATORY and conditionals fire per their trigger: N parallel spawns cost ~max(spawn-time), NOT sum, while a missed CRITICAL costs unboundedly, and §4.0 catches the trim rather than the user. Custom-reviewer discovery is a cheap Glob + parse already done in the pre-pass (§1.5.4), and those reviewers exist because the user authored them. The conventions dim owns three concern classes by contract (style rubrics, repo-modal patterns, authored-rule citations); its only sanctioned quiet path is structural — no authored rule files in the repo → no authored-rule input (§2.8), the other two unchanged. |
| "I'll tag this LOW as MEDIUM to clear the threshold" / "Auto-drop MEDIUMs to reduce friction" / "This PRODUCT-DECISION is only LOW — defer it" | Severity (impact-if-wrong) and decision-type (who-decides) are orthogonal — never collapse one into the other. Inflating LOW→MEDIUM games the §4.1 multi-signal gate (convergence, evidence-plus-confidence, the pre-resolved marker, the confidence fallback — confidence is one signal of four, never load-bearing alone) and corrupts the taxonomy for the verifier, the stratifier, and /geniro:implement. Dropping is equally untrustworthy: with no fix loop here, sub-threshold MEDIUMs go to `## Deferred — sub-threshold` for awareness (users notice when their MEDIUMs vanish). A PRODUCT-DECISION names a call only the user can close, so §4.1 Path B keeps and surfaces it at any severity. |
| "The user clearly wants tests — author them without the test-confirmation question" / "I'll spawn the adversarial-tester-agent and confirm later." | The test-confirmation gate is `AskUserQuestion` BEFORE spawning, never after — inline-after-action gates rationalize into "this counts as approval". No prior signal substitutes for this run's explicit `test_gate_choice` pick: not an earlier round's approval, not the depth pick, not an emphatic ask for thoroughness. An empty answer re-asks rather than auto-defaults. |
| "The findings look obviously postable — batch-post and tell the user after" / "the user told me in chat to push the authored tests, that's consent" | Both are external writes escaping their gate, and chat text is never a gate (invariant #3). The Action gate's "Post" pick IS the consent for a PR post; authored-test pushes route ONLY through the Phase 6 Failing-tests gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §6; reporter-boundary.md §1 triple-scope). Fire the gate and act on its pick — the render is what makes consent auditable and persisted to `approvals[]`. Skipping it pushes unresolved ambiguity onto the PR author. |
| "Inline LINEAR CONTEXT into every dim — more context = better review" / "regressions feels redundant with spec-compliance, skip it when there's a spec" | Both re-design the dimension grid from intuition. LINEAR CONTEXT helps spec-compliance (rubric source), pr-metadata (title divergence), architecture (parent-epic linkage), regressions (intent classification); other dims read it as noise biasing their per-file rubric. And spec-compliance covers diff-omits-spec-item while regressions covers diff-exceeds-stated-intent — inverse directions, not duplicates; regressions also fires on spec-less PRs where spec-compliance cannot. |
| "Per-finding verifier agreed with the finding — confirmation logged, done." | Confirmation without an `evidence:` quote from the cited file or caller chain is rationalization theater. If the verifier didn't quote literal code the verification didn't happen — re-spawn with a stricter prompt. Sycophancy is the documented multi-judge failure mode; guards at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §6. |
| "Round 1 returned clean. Run round 2 to confirm / get a nicer summary / second opinion." | Clean = Done. The Round-N escalation gate (invariant #5) ends the flow on a clean result; extra rounds waste compute AND risk hallucinated findings against an empty diff. Once a round exits with zero kept findings, the Action gate is terminal. |
| "The spawn list is already visible in the tool calls — the echo line is redundant." | The echo is the user's only plain-English record of what fired, and the human-visible baseline for the §4.0b instance check. A dropped echo preceded a real incident: 33 undisclosed spawns, user interrupt mid-run. Emit it in the SAME message that fires the batch — welded, never a separate turn. |

---

## Budgets — quality-first

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. The one cap escalates rather than aborts: **round-N reviewer re-spawn caps at 3**, and the Phase 6 Round-N gate then fires an AUQ (Continue / Escalate / Abort). Over-size reviewer output truncates (invariant #4); the Phase 3 dedup pass runs once per round inline, so it cannot fail.

---

## Subagent model tiering

Plugin agents declare `model: inherit` — OMIT `model=` at every spawn site so the session tier propagates (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`) — and apply the registration-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (`geniro:<agent>` → bare `<agent>` → `general-purpose` with the agent body inlined), caching the resolved rung for the session.

Spawn sites: `reviewer-agent` (every built-in and custom dimension, Phase 2), the per-finding verifier (`reviewer-agent` in verify-finding mode, Phase 4.2), `adversarial-tester-agent` (Phase 4.3). One exception to OMIT: a custom reviewer declaring an explicit `model:` in its `.geniro/instructions/review-extra/<slug>.md` frontmatter — pass that value verbatim. Every Agent prompt satisfies the six pre-inlined fields per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`.

---

## Spec metadata contract (/geniro:plan → /geniro:review)

When a spec.md is resolvable, parse its frontmatter `workflow_refs[]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md`. Accepted `geniro_schema_version`: `m5-v1` (treat `workflow_refs` as absent), `m5-v2`, `m5-v3` (entries also carry parent-epic + sibling chain fields), `m5-v4` (same `workflow_refs[]`, may add a `launch_config` block /geniro:review ignores). Merge with tracker refs in `$ARGUMENTS` and the PR body by `(kind, issue_id)`: `$ARGUMENTS` wins, then PR body, then spec frontmatter. Read-only — never mutate tracker state.

---

## ACI per-phase tool surface

| Phase | Allowed tools | Restricted |
|---|---|---|
| Phase 1 / 1.5 | Read, Grep, Glob, read-only Bash (`gh pr view`, `git diff`, lint, `tsc --noEmit`), **read-only `mcp__linear__*` (`get_issue` / `list_issues`; degrade silently if unregistered)** | No Edit/Write apart from state.md; no Linear `update_issue` / `create_comment` (those stay in /geniro:implement Ship) |
| Phase 2 / 3 / 4 | Agent (reviewer-agent, the per-finding verifier in verify-finding mode, adversarial-tester-agent); read-only Bash for §2.7 build verification; Phase 3 dedup inline | No Edit/Write mutations; no Bash mutations |
| Phase 5 / 6 | Write scoped to `.geniro/state/handoff/**`; `atomic_state_write` on the handoff path (gate resolutions, `approvals[]`); `emit-learning`; `gh api POST /pulls/N/reviews` with `event` omitted (§5.4, Post drill only); Phase 6 AskUserQuestion; Agent — one verify-finding spawn, only on the "Challenge this finding" pick (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3 Step 0) | No Edit/Write on project files (a reporter never mutates source or rules); edits outside the handoff scope are hook-blocked; never `gh api` with `event: COMMENT` / `APPROVE` / `REQUEST_CHANGES`, never the submit endpoint `gh api POST /pulls/N/reviews/<id>/events` (publishing a pending review is the user's action); no reviewer re-spawn without the Round-N gate pick |

Safety hooks apply throughout: file-protection, git-guardrails, `.geniro/` deletion guard, state-helper enforcement, security-pattern-scan on any Edit/Write.

---

## Memory I/O schedule

| Phase | Helper |
|---|---|
| Phase 1 entry | `load-custom-instructions` (read L4, `initial-load`, scope `review` + `global` + `code-style`) · `load-semantic` (read L3, `refresh`: `_project.md` + `_CODEBASE_MAP.md`, with drift check) · `query-learnings` (read L2: tags from changed-file paths, type bias `pitfall`, top-K default 5) · `resolve-conflicts` over the three |
| Phase 2 entry | `load-custom-instructions` (read L4, `refresh`, same scope) — compaction may have dropped the rules |
| Phase 5 · 6 | `atomic_state_write` (write T2) — handoff path, full body; then updated `approvals[]` |
| Phase 5.3 | `emit-learning` (write L2) — producer /geniro:review, type `pitfall`, trust `verified` |

`pitfall` is the only L2 type /geniro:review emits (on convergence ≥3). `convention` belongs to /geniro:implement, `decision` to /geniro:plan, `diagnosis` to /geniro:debug.

---

## Definition of done

The load-bearing exit gates — skipping any makes the review incomplete or unsafe. Per-phase mechanics live in the phase files; this is the final contract check.

- [ ] Every mandatory reviewer spawned in parallel — 7 always-fire dimensions (including `regressions`) + every triggered conditional one (design / pr-metadata / spec-compliance) + custom dimensions; `spawn_dims_declared[]` recorded before the batch, and §4.0b confirmed declared == actual AND spawn instances == `spawn_dims_count`.
- [ ] The spawn echo (`Spawning <N> reviewers: ...`), carrying the declared count, went out in the same response that fired the batch (§2.3.1).
- [ ] A fresh verify-finding verdict exists for EVERY admitted CRITICAL / HIGH / MEDIUM survivor (verifiers cluster up to 3 same-file findings); refuted findings demoted to `## Filtered`.
- [ ] The multi-signal admission gate was applied — not a single confidence threshold (invariant #6).
- [ ] Every kept finding carries a severity (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1), a decision type, and a `[NEW]` / `[PRE-EXISTING]` tag.
- [ ] The needs-your-decision gate fired for every such finding at any severity, and all are resolved or wontfix BEFORE the handoff is offered or anything is posted (§7.0 Pre-Post guard).
- [ ] `phase:` was stamped via `atomic_state_write` on ENTRY to each phase (invariant #10), so both declarations existed before the gates reading them.
- [ ] All three pre-pass checks (lint / schema / secret) ran to a recorded outcome, `mechanical_prepass_attempted[]` was declared, and §4.0a confirmed it.
- [ ] The handoff was written to `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` via `atomic_state_write`, carrying structured `open_questions[]`.
- [ ] `report_status: draft→final` flipped only after the decision gate cleared; on a Post, `[POSTED-TO-PR]` markers persisted.
- [ ] The Action gate fired (always-WAIT) with its pick in `approvals[]`; the chained include-deferred gate fired on the `/geniro:implement findings` pick when set-aside minor findings existed; the round-N gate fired when round ≥3.
- [ ] `--deep` honored when present; approved test authoring stayed additive — never filtering the posted finding set.

---

## Phase 1 — Triage & context collect

`phase: triage` · Steps: `phase-1-triage.md` (13 Steps). Resolve the review target; load PR, tracker, plan, and memory context. Exit when frontmatter holds `round`, `risk-tier`, `pr-ref`, `linear-task-ref`, `linear-parent-ref`, `plan-context-ref` — plus `deep-mode` when the depth step ran — and `approvals[]` holds any AUQ answers.

## Phase 1.5 — Mechanical pre-pass

`phase: mechanical-prepass` · Steps: `phase-1-triage.md` §1.5.1-§1.5.7. Three deterministic checks (lint / schema / secret scan) before any LLM spawn, so reviewers get their output as prior-context. Exit when each check has landed exactly one recorded outcome — findings, or a `## Errors mechanical-prepass-<id>` entry — and `mechanical_prepass_attempted[]` is declared.

## Phase 2 — LLM reviewer spawns

`phase: llm-spawn` · Steps: `phase-2-spawns.md` §2.1-§2.8. Fire one `reviewer-agent` per triggered dimension as a single parallel batch. Exit when every declared dimension returned a structured result or a `status: failed` entry, with `spawn_dims_declared[]` + `spawn_dims_count` written BEFORE the batch fired.

## Phase 3 — Filter & aggregate

`phase: filter` · Steps: `phase-3-4-filter-stratify.md` §3.1-§3.3. Orchestrator-inline dedup, convergence counting, KEEP/FILTER judgment — no subagent. Exit when every finding is deduped with a `convergence_count` and is either KEEP or in `## Filtered` with a reason.

## Phase 4 — Stratification & test gate

`phase: stratify` · Steps: `phase-3-4-filter-stratify.md` §4.0-§4.3 — the post-spawn verification gate, **§4.1 multi-signal threshold filter**, per-finding empirical-reproduction verification, failing-to-passing test-confirmation gate. Exit when every admitted CRITICAL / HIGH / MEDIUM finding carries a verifier verdict (or `Validation: unverified`), refuted findings have moved to `## Filtered`, and the test gate has fired — or was skipped on an empty eligible set.

## Phase 5 — Persist & emit

`phase: persist` · Steps: `phase-5-6-emit-handoff.md` §5.0-§5.5, opening with **§5.0 repeat findings**. Exit when `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` exists via `atomic_state_write` with `report_status: draft` and structured `open_questions[]`, and the §5.3 convergence emits have run.

## Phase 6 — Action gate handoff

`phase: action-gate` · Steps: `phase-5-6-emit-handoff.md` (its Phase 6 section) plus `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §1-§6 and §8-§9; read §7 (the Post drill) only on the "Post Draft PR review" pick — a third of that file, unreachable when `pr-ref: none`. Each gate is its own AUQ, never collapsed into chat text. Exit when the open-question, open-decision, and Action gates — plus the Failing-tests gate when `## Authored Tests` is non-empty — have each fired with their picks persisted to `approvals[]`.

---

## REFERENCE

Beyond the four phase files named in the header, each phase file cites its own deeper contracts. Under `${CLAUDE_PLUGIN_ROOT}/skills/review/`: `phase-1-triage-reference.md` (Phase 1 input mode / scope / risk-tier / memory load) · `deep-mode-reference.md` (`--deep` recall + vote) · `phase-4-3-test-gate-reference.md`. Under `${CLAUDE_PLUGIN_ROOT}/skills/_shared/`: `finding-verification.md` (Phase 4.2 verifier) · `review-handoff.md` (Phase 6 handoff; §7 is the Post drill) · `plan-context.md` · `flags-reference.md`.
