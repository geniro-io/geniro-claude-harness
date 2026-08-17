---
name: geniro-review
description: "Use when a comprehensive code review of pending changes (a diff, branch, or PR) is needed. Reporter workflow: triage, a cheap mechanical pre-pass, then parallel single-dimension reviewers (bugs, security, architecture, tests, regressions, conventions, and more, plus any custom ones) whose findings are filtered and individually verified, then persisted. Emits a handoff file at .geniro/state/handoff/from-review-<branch>.md; downstream consumers (/geniro:implement, or the user manually) apply the fixes and author any confirming tests — review never edits code itself, and asks before posting to a PR. Optional --deep reviews each check from several angles and majority-verifies contested findings (higher quality, higher cost)."
context: main
---
<!-- Generated from skills/review/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->


# Code review skill

## Contents

- Your role — orchestrate, don't review
- State machine
- Loop invariants
- Anti-rationalization
- Budgets — quality-first
- Subagent model tiering
- Spec metadata contract
- ACI per-phase tool surface
- Memory I/O schedule
- Definition of done
- Phase 1 / 1.5 / 2 / 3 / 4 / 5 / 6 — one section each, pointing at that phase's file
- REFERENCE

---

This file is the spine — role, invariants, gates, phase map. **Read the phase's Steps on entry to that phase**, from `${CLAUDE_PLUGIN_ROOT}/skills/review/`: `phase-1-triage.md` (Phases 1 + 1.5) · `phase-2-spawns.md` (Phase 2) · `phase-3-4-filter-stratify.md` (Phases 3 + 4) · `phase-5-6-emit-handoff.md` (Phases 5 + 6). That Read is the phase's physically-first action and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the phase files hold this skill's gates and its helper call sites, so work started before the Read runs outside them.

**Runtime portability.** Claude Code sets `${CLAUDE_PLUGIN_ROOT}`. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference — it is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it everywhere and export it in every Bash call. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` before deciding a step cannot run here — it substitutes mechanisms, not steps.

---

## Your role — orchestrate, don't review

You are a **coordinator**. Delegate review work to `reviewer-agent` instances via the Agent tool and validate their outputs in the judge pass. Read files only to gather context and verify agent findings — a coordinator that reviews inline inherits the reviewers' blind spots, so the judge pass stops being independent.

`/geniro:review` is a **Reporter**: it never applies fixes. Findings persist to a handoff file; downstream consumers (`/geniro:implement`, manual user action) apply them. A `Workflow(...)` / ultracode wrapper parallelizes the reviewer fan-out, not the Reporter contract; full boundary at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.

---

## State machine

State.md `phase:` enum transitions:

```
[entry] → triage → mechanical-prepass → llm-spawn → filter → stratify → persist → action-gate → done
│
├── escalated ── (round-N user pick)
└── aborted ── (round-limit / safety / tool-unavailable)
```

**Terminal states:** `done`, `aborted`, `escalated` — SessionStart recovery treats all three as "review complete / cancelled". `done` includes a Phase 6 handoff line; `aborted` writes a `## Termination reason` body section; `escalated` (round-limit hand-off) surfaces its reason in `## Open Questions` instead (mapping: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §9). Recovery rolls every **non-terminal** state back to phase-entry and re-runs from there — idempotent, because `approvals[]` makes the Phase 6 AUQ skip already-answered picks.

**After a compaction, re-Read the phase file for the phase `phase:` says you are resuming** — only this spine is re-attached, the Steps are gone, and reconstructing a phase from a summary's recollection is how a spawn batch or a gate gets skipped.

---

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply, with review-specific bindings:

- **Invariant #1 (one result per tool call)** — binds each Phase 2 parallel reviewer spawn; a dead one gets its `status: failed` entry in `## Tool log`.
- **Invariant #2 (args validated)** — `$ARGUMENTS` flag parsing is semantic, no CLI grammar; a PR ref validates via `mcp__github__pull_request_read` or the GraphQL fallback.
- **Invariant #3 (permission before side-effect)** — the Phase 6 Action gate always fires and waits before any post to GitHub; never auto-post, never substitute a chat-text suggestion for it. The post creates a PENDING review that /geniro:review never submits, on every round — submitting is the user's own github.com action (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.4). State.md writes go through `atomic_state_write`. Every user-facing choice routes through `AskQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions — Phase 1's workspace decision, round-N escalation, and re-review/depth questions (`phase-1-triage-reference.md` §0b, §7, §11), Phase 4's post-spawn verification gate (`phase-3-4-filter-stratify.md` §4.0), and Phase 6's gate chain (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §1-§5).
- **Invariant #4 (bounded results)** — reviewer-agent output is capped per dimension by its own contract (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output cap); output schema per the same file's §Output Format.
- **Invariant #5 (escalation gates)** — round-N ≥3 fires the Phase 1 round-N gate first (`phase-1-triage-reference.md` §7 step 4, two options: Continue / Escalate); Escalate exits terminal before Phase 6 is reached. A Continue pick lets the Phase 6 Round-N gate (`review-handoff.md` §5, Continue / Escalate / Abort) fire as its conditional follow-on.
- **Invariant #6 (grounded in observations) — binds at every kept severity.** The Phase 6 handoff message cites the state.md path so the user can audit the source; every REPORTED CRITICAL / HIGH / MEDIUM finding carries an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` quoting the cited file or caller chain literally, because a severity claim without a literal quote is unverifiable. This binds at emit, not at admission: a CRITICAL or HIGH may enter Phase 4.2 on a thin citation, and the verifier (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §3) is what supplies the quote for every §4.1 survivor.
- **Invariant #7 (errors → structured observations)** — reviewer spawn failures land in the `## Errors` body section; `gh` fail-open is not silent — log it there too.

This skill adds three invariants:

S1. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.
S2. **Re-verify ambiguity gates at external-effect boundaries.** Upstream gates establish invariants on `open_questions[].status`, PRODUCT-DECISION `step0_status:`, kept-finding `Validation:`, and `report_status:`; the Pre-Post guard (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.0) re-reads all four before any `gh api POST /reviews`, because mid-phase producer writes, parallel resolvers, or drift can re-create ambiguity between gate and write. Never trust an upstream gate's invariant at a public-surface boundary.
S3. **Stamp `phase:` on entry, before the phase's work.** A checkpoint written only at the end records history, not current state: a crash mid-phase leaves no resumable marker, and a declaration the phase produces (`spawn_dims_declared`, written before the spawns) lands too late to power the gate reading it. A phase counts DONE only once its trailing steps complete — stamp `persist` only after the §5.3 emits have run, or stamp the next phase at its own entry.

**Turn-completion check (canonical, un-numbered).** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard: never stop on an announced-but-unfired question.

`## Tool log`: one entry per reviewer spawn, one per Phase 5.3 emit-learning, and one per PR-side-effect.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "/geniro:review should fix its own findings — parity with /geniro:implement self-review" / "I'll auto-update Linear status when findings are critical" | Both breach the Reporter boundary. That self-review is a post-implementation gate inside a mutation skill; this is a read-only audit consumed downstream, so parity would hand this skill a fixer role it does not hold — route fixes to /geniro:implement. Linear `update_issue` / `create_comment` belong to /geniro:plan and /geniro:implement; this skill's MCP surface is read-only per ACI, and `open_questions[]` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2) surfaces ambiguity without mutating tracker state. A `Workflow(...)` wrapper (including `--deep`'s recall/vote workflows) or ultracode suspends none of it. |
| "Mechanical pre-pass is too slow — skip it, LLM reviewers cover the same ground." | LLM reviewers cover similar ground at ~100× the cost with non-deterministic output; lint detects a missing import faster and more reliably than a security reviewer would. Run cheap-deterministic first, LLM-spawn second with the pre-pass findings as prior-context. |
| "I'll spawn only 4 dimensions — they cover the main risk surface." | Silent coverage cut: an orchestrator-judgment trim is forbidden at any diff size. The only sanctioned narrowing is the declared, size-and-risk-tier scaling in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-grid-scaling.md` — forced back to the full grid at `risk-tier:high` — and even that narrowed set is always recorded in `spawn_dims_declared[]` and announced in the spawn echo before the batch fires. A count you arrived at by "this diff feels small" rather than by that table is exactly the cut this row blocks. N parallel spawns cost ~max(spawn-time), NOT sum, while a missed CRITICAL costs unboundedly — §4.0 catches an undeclared trim, never a declared one, which is why the declaration is what keeps this checkable at all. |
| "Skip custom-reviewer discovery — that `review-extra/<slug>.md` is narrow scope." | Silent coverage cut: discovery is a cheap Glob + parse already done in the pre-pass (§1.5.4), and those reviewers exist because the user authored them. |
| "The conventions dim is overloaded — drop its authored-rule check or sibling-sampling pass." | Silent coverage cut: the conventions dim owns three concern classes by contract (style rubrics, repo-modal patterns, authored-rule citations); its only sanctioned quiet path is structural — no authored rule files in the repo → no authored-rule input (§2.8), the other two unchanged. |
| "I'll tag this LOW as MEDIUM to clear the threshold" / "Auto-drop MEDIUMs to reduce friction" / "This PRODUCT-DECISION is only LOW — defer it" | Severity (impact-if-wrong) and decision-type (who-decides) are orthogonal — never collapse one into the other. Inflating LOW→MEDIUM games the §4.1 gate — which reads severity directly at HIGH and above, so inflation buys admission outright rather than nudging a score — and corrupts the taxonomy for the verifier, the stratifier, and /geniro:implement. What disqualifies the inflation is §1's per-tier EXCLUSION lists (cosmetic and process items are excluded from MEDIUM by name), backed by the Phase 4.2 verifier re-reading the code of everything admitted. Dropping is equally untrustworthy: with no fix loop here, sub-threshold MEDIUMs go to `## Deferred — sub-threshold` for awareness (users notice when their MEDIUMs vanish). A PRODUCT-DECISION names a call only the user can close, so §4.1 Path B keeps and surfaces it at any severity. |
| "The findings look obviously postable — batch-post and tell the user after" | An external write escaping its gate is never justified by how obvious the outcome looks, and chat text is never a gate (invariant #3). The Action gate's "Post" pick IS the consent for a PR post. Fire the gate and act on its pick — the render is what makes consent auditable and persisted to `approvals[]`. Skipping it pushes unresolved ambiguity onto the PR author. |
| "Inline LINEAR CONTEXT into every dim — more context = better review" / "regressions feels redundant with spec-compliance, skip it when there's a spec" | Both re-design the dimension grid from intuition. LINEAR CONTEXT helps spec-compliance (rubric source), pr-metadata (title divergence), architecture (parent-epic linkage), regressions (intent classification); other dims read it as noise biasing their per-file rubric. And spec-compliance covers diff-omits-spec-item while regressions covers diff-exceeds-stated-intent — inverse directions, not duplicates; regressions also fires on spec-less PRs where spec-compliance cannot. |
| "Per-finding verifier agreed with the finding — confirmation logged, done." | Confirmation without an `evidence:` quote from the cited file or caller chain is rationalization theater. If the verifier didn't quote literal code the verification didn't happen — re-spawn with a stricter prompt. Sycophancy is the documented multi-judge failure mode; guards at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §6. |
| "Round 1 returned clean. Run round 2 to confirm / get a nicer summary / second opinion." | Clean = Done. The Round-N escalation gate (invariant #5) ends the flow on a clean result; extra rounds waste compute AND risk hallucinated findings against an empty diff. Once a round exits with zero kept findings, the Action gate is terminal. |
| "The spawn list is already visible in the tool calls — the echo line is redundant." | The echo is the user's only plain-English record of what fired, and the human-visible baseline for the §4.0b instance check. A dropped echo preceded a real incident: 33 undisclosed spawns, user interrupt mid-run. Emit it in the SAME message that fires the batch — welded, never a separate turn. |

---

## Budgets — quality-first

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. The one bound escalates rather than aborts: at **round 3 the Phase 1 round-N gate fires first** (two options, Continue / Escalate — `phase-1-triage-reference.md` §7 step 4); an Escalate pick exits terminal before Phase 6 is ever reached. A Continue pick lets the run proceed into the **Phase 6 Round-N gate** as its conditional follow-on (Continue / Escalate / Abort); its hard ceiling lives in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §5. Over-size reviewer output truncates (invariant #4); the Phase 3 dedup pass runs once per round inline, so it cannot fail.

---

## Subagent model tiering

Plugin agents declare `model: inherit` — OMIT `model=` at every spawn site so the session tier propagates (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` carries the rationale and carve-outs). Spawn `subagent_type="geniro:<agent>"` under Claude Code, bare `subagent_type="<agent>"` under any other host — `geniro:` is Claude Code's plugin namespace, so on Cursor the prefixed form cannot resolve and the whole reviewer fan-out is spent discovering that. Only on a spawn that fails to start or an empty (0-token) result, Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` and apply its registration ladder (`geniro:<agent>` under Claude Code → bare `<agent>`, the entry rung everywhere else → `general-purpose` with the agent body inlined) and empty-result fallback, then cache the resolved rung for the session. Neither helper is read on the happy path — this summary is the operative rule until a spawn fails.

Spawn sites: `reviewer-agent` (every built-in and custom dimension, Phase 2), `finding-verifier-agent` (the per-finding verifier, Phase 4.2). One exception to OMIT absent the flag below: a custom reviewer declaring an explicit `model:` in its `.geniro/instructions/review-extra/<slug>.md` frontmatter — pass that value verbatim. Every Agent prompt satisfies every pre-inlined field per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`.

**`--subagent-model <tier>` overrides all of the above, uniformly, for this run — including inside a deep-mode Workflow fan-out.** When `$ARGUMENTS` carries the flag, pass `model="<tier>"` at every Agent spawn this run makes — `reviewer-agent`, `finding-verifier-agent`, and the `codebase-research-agent` side-query spawns (§Loop invariants S1) alike — beating both the inherit default and a custom reviewer's own declared `model:` — the flag is the user's own election for the run, the same shape as that declaration but scoped wider. Values, the caching reason for applying it uniformly rather than per-dimension, and the fallback routes when the value is inexpressible: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §`--subagent-model`. Announce the pinned tier once at run start; every phase file's spawn sites below apply it without re-stating this rule. Persisted to state.md frontmatter `subagent-model:` at the §1 flag parse (`phase-1-triage-reference.md` §1) so a compaction before Phase 2 fires does not silently revert every reviewer spawn back to the frontmatter default.

---

## Spec metadata contract (/geniro:plan → /geniro:review)

When a spec.md is resolvable, parse its frontmatter `workflow_refs[]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md`. Accepted `geniro_schema_version`: `m5-v1` (treat `workflow_refs` as absent), `m5-v2`, `m5-v3` (entries also carry parent-epic + sibling chain fields), `m5-v4` (same `workflow_refs[]`, may add a `launch_config` block /geniro:review ignores). Merge with tracker refs in `$ARGUMENTS` and the PR body by `(kind, issue_id)`: `$ARGUMENTS` wins, then PR body, then spec frontmatter. Read-only — never mutate tracker state.

---

## ACI per-phase tool surface

| Phase | Allowed tools | Restricted |
|---|---|---|
| Phase 1 / 1.5 | Read, Grep, Glob, read-only Bash (`gh pr view`, `git diff`, lint, `tsc --noEmit`) plus `atomic_state_write`, **read-only `mcp__linear__*` (`get_issue` / `list_issues`; degrade silently if unregistered)**, Agent (`codebase-research-agent`, for codebase-research side queries), AskQuestion (workspace decision, round-N escalation, re-review scope + depth) | No Edit/Write — the state file goes through the helper; no Linear `update_issue` / `create_comment` (those stay in /geniro:implement Ship) |
| Phase 2 / 3 / 4 | Agent (reviewer-agent, finding-verifier-agent); WebSearch / WebFetch (`finding-verification.md` §2.5 external-evidence pre-run, Phase 4.2 only, outside-repo claims only, tiers 2-3, before the verifier spawn); read-only Bash for §2.7 build verification plus `atomic_state_write`; Phase 3 dedup inline; AskQuestion (Phase 4's post-spawn declared-vs-actual gate) | No Edit/Write — the state file goes through the helper; no other mutating Bash |
| Phase 5 / 6 | `Bash` for `atomic_state_write` on the handoff path (the Phase 5.1 write, gate resolutions, `approvals[]`); `emit-learning`; `gh api POST /pulls/N/reviews` with `event` omitted (§5.4, Post drill only); Phase 6 AskQuestion; Agent — one `finding-verifier-agent` spawn, only on the "Challenge this finding" pick (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3 Step 0) | No Edit/Write anywhere — a reporter never mutates source or rules, and the state-helper hook hard-blocks direct writes under `.geniro/state/`, so the helper is the only route to the handoff. Never `gh api` with `event: COMMENT` / `APPROVE` / `REQUEST_CHANGES`, never the submit endpoint `gh api POST /pulls/N/reviews/<id>/events` (publishing a pending review is the user's action); no reviewer re-spawn without the Round-N gate pick |

The safety hooks apply across every phase; the complete list and what each blocks is in `${CLAUDE_PLUGIN_ROOT}/HOOKS.md`. Runtime denies stay enforced.

---

## Memory I/O schedule

| Phase | Helper |
|---|---|
| Phase 1 entry | `load-custom-instructions` (read L4, `initial-load`) · `load-semantic` (read L3, `refresh`: `_project.md` + `_CODEBASE_MAP.md`, with drift check) · `query-learnings` (read L2: tags from changed-file paths, type bias `pitfall`, top-K default 5) · `resolve-conflicts` over the three |
| Phase 2 entry | `load-custom-instructions` (read L4, `refresh`, same scope) — compaction may have dropped the rules |
| Phase 5 entry | `load-custom-instructions` (read L4, `refresh`, same scope) — compaction may have dropped the rules |
| Phase 5 · 6 | `atomic_state_write` (write T2) — handoff path, full body; then updated `approvals[]` |
| Phase 5.3 | `emit-learning` (write L2) — producer /geniro:review, type `pitfall`, trust `verified` |

`pitfall` is the only L2 type /geniro:review emits, and only on the convergence threshold `phase-5-6-emit-handoff.md` §5.3 defines.

---

## Definition of done

The run-completion checklist is `${CLAUDE_PLUGIN_ROOT}/skills/review/review-definition-of-done.md`. Walk it at Phase 6, before the terminal `phase:` write.

---

## Phase 1 — Triage & context collect

`phase: triage` · Steps: `phase-1-triage.md`. Resolve the review target; load PR, tracker, plan, and memory context. Exit when frontmatter holds `round`, `risk-tier`, `pr-ref`, `linear-task-ref`, `linear-parent-ref`, `plan-context-ref`, `subagent-model` — plus `deep-mode` when the depth step ran — and `approvals[]` holds any AUQ answers.

## Phase 1.5 — Mechanical pre-pass

`phase: mechanical-prepass` · Steps: `phase-1-triage.md` §1.5.1-§1.5.7. Three deterministic checks (lint / schema / secret scan) before any LLM spawn, so reviewers get their output as prior-context. Exit when each check has landed exactly one recorded outcome — `findings`, `clean`, or `error` — declared in `mechanical_prepass_attempted`.

## Phase 2 — LLM reviewer spawns

`phase: llm-spawn` · Steps: `phase-2-spawns.md` §2.1-§2.3 and §2.5-§2.9 (§2.4 is reserved). Fire one `reviewer-agent` per triggered dimension as a single parallel batch. Exit when every declared dimension returned a structured result or a `status: failed` entry, with `spawn_dims_declared[]` + `spawn_dims_count` written BEFORE the batch fired.

## Phase 3 — Filter & aggregate

`phase: filter` · Steps: `phase-3-4-filter-stratify.md` §3.1-§3.3. Orchestrator-inline dedup, convergence counting, KEEP/FILTER judgment — no subagent. Exit when every finding is deduped with a `convergence_count` and is either KEEP or in `## Filtered` with a reason.

## Phase 4 — Stratification & verification

`phase: stratify` · Steps: `phase-3-4-filter-stratify.md` §4.0-§4.2 — the post-spawn verification gate, **§4.1 multi-signal admission gate**, per-finding empirical-reproduction verification. Exit when every admitted CRITICAL / HIGH / MEDIUM finding carries a verifier verdict (or `Validation: unverified`) and refuted findings have moved to `## Filtered`.

## Phase 5 — Persist & emit

`phase: persist` · Steps: `phase-5-6-emit-handoff.md` §5.0, §5.1 and §5.3-§5.5 (§5.2 is reserved), opening with **§5.0 repeat findings**. Exit when `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` exists via `atomic_state_write` with `report_status: draft` and structured `open_questions[]`, and the §5.3 convergence emits have run.

## Phase 6 — Action gate handoff

`phase: action-gate` · Steps: `phase-5-6-emit-handoff.md` (its Phase 6 section) plus `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §1-§5 and §8-§9; the Post drill (§7.0-§7.8) is its own file, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff-post.md` — read it only on the "Post Draft PR review" pick, unreachable when `pr-ref: none`. Each gate is its own AUQ, never collapsed into chat text. Exit when the open-question, open-decision, and Action gates have each fired with their picks persisted to `approvals[]`.

---

## REFERENCE

Beyond the four phase files named in the header, each phase file cites its own deeper contracts. Under `${CLAUDE_PLUGIN_ROOT}/skills/review/`: `phase-1-triage-reference.md` (Phase 1 input mode / scope / risk-tier / memory load) · `phase-1-pr-reference.md` (PR-side fetches + peer-PR scout, PR-ref runs only) · `deep-mode-reference.md` (`--deep` recall + vote). Under `${CLAUDE_PLUGIN_ROOT}/skills/_shared/`: `review-grid-scaling.md` (dimension-grid scaling) · `finding-verification.md` (Phase 4.2 verifier) · `review-handoff.md` (Phase 6 handoff) · `review-handoff-post.md` (§7 Post drill, Post pick only) · `plan-context.md` · `flags-reference.md`.
