# M6 — /geniro:review Redesign (Consolidate)

**Status:** Specification (pre-implementation, partial — see §22 Open Questions)
**Master plan:** `/root/.claude/plans/reactive-dreaming-backus.md` — this doc is M6 of an M1–M10 architecture redesign that collapses 18 skills → 11. M6 consolidates `/geniro:review` (largest skill in the plugin — 1025-line `SKILL.md` + 10 criteria files = 3951 LOC) and **absorbs `/geniro:deep-simplify`** as а `--simplify` flag per master plan §67.
**Scope:** Redesign of `/geniro:review` skill. Closes 10 audit defects (state.md/M1 non-conformance, missing M3 compaction blocks, stale M5-schema integration, guidelines+conventions wholesale duplication, 1025-line SKILL.md surface inflation). Closes 6 of 8 P-M6 master-plan obligations (spec-compliance к M5, /deep-simplify absorb, learnings pitfall auto-emit, mechanical pre-pass, budgets quality-first, anti-pattern audit). Defers 2 obligations (4-tier risk model, trace-grading) к M-later.
**Depends on:** M1 (state-files — `atomic_state_write`, T2 handoff schema, `approvals[]` P-M1-1); M2 (memory layers — `query-learnings` Phase 1, `emit-learning` Phase 5 pitfall trigger); M3 (compaction-survival — `## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason`); M4 (`/implement` — consumes review-findings via T2 hand-off); M5 (`/plan` — emits spec.md 10-section schema).
**Sequencing note:** M6 ships after M5 lands. М5's spec.md schema (§17) is the canonical input для М6's `spec-compliance` dimension. М6 implementation can start before М5 implementation если frontend writes а stub spec.md by hand для testing.
**Followed by:** M7 (`/debug` — consumes review T2 hand-off `from-review-<branch>.md`); M8+ per master plan §107.

---

## 1. Purpose

The pre-M6 `/geniro:review` (1025-line `SKILL.md` + 10 criteria files + 4 reference files = 3951 LOC) is the largest skill в the plugin. Audit (2026-05-18) identified 10 defects — most importantly: state.md non-conformance к M1, missing M3 compaction blocks, stale M5-schema integration в `plan-context-reference.md` + `spec-compliance-criteria.md`, и а wholesale duplication между `guidelines §8` и the `conventions` dimension that produces user-facing «told twice» findings.

М6 consolidates the surface AND closes pipeline integration gaps. Three responsibilities:

1. **Pipeline integration debt.** Pre-M6 /review pre-dates M1/M3 milestones; state.md is custom-schema, compaction-survival blocks absent. M5 introduced а 10-section spec.md schema that `spec-compliance` dimension does not consume. M6 fixes the integrations.
2. **/deep-simplify absorption (master plan §67).** /deep-simplify (552 LOC) shares conceptual surface с /review's `architecture` + `guidelines` + `optimizations` dimensions but uses а divergent severity tier (P1/P2/P3 not CRITICAL/HIGH/MEDIUM) и independent fix-loop. М6 absorbs it as а `--simplify` flag, folding the 3 simplify passes into the existing dimension grid.
3. **Surface inflation.** SKILL.md grew от ~270 lines (2026-04) → 1025 lines without а defect-pass since report.md v8. М6 trims to ~400 lines orchestration shell + reference files (M4 reference-pattern).

М6 preserves /review's **reporter behavior** — it does NOT apply fixes. Findings are persisted to М1-T2 hand-off; downstream consumers (`/implement`, manual user action) apply fixes. The `--simplify` flag does NOT change this (the user explicitly picked Reporter mode over Fixer mode during M6 design — §4 H-2).

---

## 2. Architecture overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  /geniro:review $ARGUMENTS [--simplify] [--tdd] [--plan <path>]              │
└─────────────────────────────┬────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  Phase 1 — Triage & Context Collect     │
        │  • Input mode detect (OUTGOING /        │
        │    INCOMING / pr-ref) — preserved       │
        │  • Worktree pre-flight, peer-PR scout   │
        │  • Risk-tier (standard / high) от 9     │
        │    hard-escalation signals в            │
        │    effort-scaling.md                    │
        │  • PLAN CONTEXT load (М5 schema-aware,  │
        │    §11)                                 │
        │  • L4 refresh + L3 + L2 query-learnings │
        │  • Round counter increment (Step 0.5)   │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 1.5 — Mechanical Pre-pass (NEW)  │
        │  • Lint check (existing project config) │
        │  • Schema check (TS/JSON/proto)         │
        │  • Secret scan (AKIA*/sk-*/PEM regex)   │
        │  • Findings → fed к Phase 2 LLM         │
        │    reviewers AS PRIOR-CONTEXT (NOT      │
        │    raw findings — orchestrator-      │
        │    surfaced)                            │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 2 — LLM Reviewer Spawns          │
        │  • 9 dimensions (was 10 — guidelines    │
        │    §8 collapsed к conventions, §17)     │
        │  • Conditional spawns: design (UI),     │
        │    pr-metadata (pr-ref), spec-         │
        │    compliance (PLAN CONTEXT + risk-     │
        │    tier:high OR pr-ref)                 │
        │  • --simplify flag triples weight on    │
        │    architecture + conventions +         │
        │    guidelines + bugs + optimizations    │
        │    (P-M6-deep-simplify, §13)            │
        │  • Parallel batch (single message)      │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 3 — Filter & Aggregate           │
        │  • relevance-filter-agent dedup         │
        │  • Cross-reviewer convergence detection │
        │    (≥3 reviewers → pitfall candidate    │
        │    per M2 §5.3 P-M6-learnings)          │
        │  • Severity rollup: CRITICAL / HIGH /   │
        │    MEDIUM (P1/P2/P3 от --simplify mode  │
        │    reconciled here)                     │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 4 — Stratification & Test Gate   │
        │  • Phase 4a: severity threshold         │
        │    (standard: ≥80; high: ≥70)           │
        │  • Phase 4b: HIGH-tier validator        │
        │    (--tdd: validates all HIGH; standard │
        │    samples top-3)                       │
        │  • Phase 4c: F→P test gate (--tdd:      │
        │    "Author tests…(Recommended)" default,│
        │    §14)                                 │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 5 — Persist & Emit               │
        │  • Write М1-T2 conformant state at      │
        │    .geniro/state/handoff/from-review-   │
        │    <branch>.md (D4/D9 fix)              │
        │  • M3 body sections: ## Tool log /      │
        │    ## Errors / ## Open Questions /      │
        │    ## Termination reason / ## Persisted │
        │    approvals (P-M3-1, P-M3-2)           │
        │  • Phase 5b: L2 pitfall auto-emit when  │
        │    cross-reviewer convergence ≥3        │
        │    (P-M6-learnings — replaces deleted   │
        │    /learnings)                          │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 6 — Action Gate Hand-off         │
        │  • AUQ с 4 options preserved:           │
        │    /implement / Post Draft PR /         │
        │    Continue rounds (round≥3 → Escalate) │
        │    / Skip                               │
        │  • Reporter behavior — NO fix loop      │
        │    inside /review                       │
        │  • --simplify flag does NOT change      │
        │    hand-off shape (still reporter)      │
        │  • Persist user pick к approvals[]      │
        │  • Terminal: done / aborted             │
        └─────────────────────────────────────────┘
```

---

### 2.1 State machine

State.md `phase:` enum transitions:

```
[entry]
  └── triage ──┬── mechanical-prepass ──┬── llm-spawn ──┬── filter ──┬── stratify ──┬── persist ──┬── action-gate ──┬── done
               │                        │                │            │              │             │                 │
               │                        │                │            │              │             │                 ├── (terminal — happy)
               │                        │                │            │              │             │                 │
               │                        │                │            │              │             │                 └── escalated ──┬── debug-handoff (terminal — user picks "/debug")
               │                        │                │            │              │             │                                ├── continue (round-N+1, re-enters llm-spawn с only failing dims)
               │                        │                │            │              │             │                                └── aborted (terminal — user picks "abort")
               │                        │                │            │              │             │
               │                        │                │            │              │             └── (atomic non-resumable-actions write per side-effect — PR comment posts)
               │                        │                │            │              │
               │                        │                │            │              └── (severity rollup; --simplify P1/P2/P3 mapped к HIGH/MED/info)
               │                        │                │            │
               │                        │                │            └── (relevance-filter-agent dedup; cross-reviewer convergence detect)
               │                        │                │
               │                        │                └── (5-9 parallel reviewer spawns; conditional dimensions; --simplify weights)
               │                        │
               │                        └── (lint / schema / secret regex; mechanical findings → Phase 2 prior-context)
               │
               └── (input mode detect, risk-tier, worktree, PLAN CONTEXT)
```

**Terminal states:** `done`, `aborted`. М3 SessionStart recovery treats both as «review complete / cancelled». `done` includes а Phase 6 hand-off line ("Findings written к .geniro/state/handoff/from-review-<branch>.md — pick /implement к apply").

**Non-terminal states:** `triage`, `mechanical-prepass`, `llm-spawn`, `filter`, `stratify`, `persist`, `action-gate`. М3 recovery rolls these back к phase-entry и re-runs from there (idempotent — `approvals[]` ensures Phase 6 AUQ skips already-answered).

**Escalation state:** `escalated`. Round-N (≥3) с unresolved findings fires the gate. User picks debug-handoff / continue / abort.

### 2.1.1 Termination case → state mapping

Per master plan P-M4-2 extended к M6. Identical pattern к M4 §2.1.1, M5 §2.1.1.

| # | Termination case | Terminal state | `## Termination reason` body line |
|---|---|---|---|
| 1 | Final answer produced (Phase 6 hand-off picked) | `done` | (omitted) |
| 2 | Done modifier — e.g., user picks "Skip" | `done` | `modifier-exit: skip-action` |
| 3 | User approval required | non-terminal `action-gate`, then terminal via user pick | — |
| 4 | Blocker needs user input | non-terminal `escalated` | — |
| 5 | Budget reached | N/A — quality-first per §2.3 | — |
| 6 | Repeated failure threshold exceeded | `aborted` (round ≥3 + user picks abort) | `repeated-failure: round-limit-3` |
| 7 | Safety policy denial (hook block) | `aborted` | `safety-denied: <rule>` |
| 8 | Tool unavailability without fallback | `aborted` | `tool-unavailable: <tool>` (e.g., `gh` unavailable когда PR mode picked) |

М3 SessionStart hook surfaces `## Termination reason` on resume so the model и user see context, not bare «aborted».

---

### 2.2 Loop invariants

М4 §2.2's 7 invariants apply к M6 unchanged. Notable per-phase application:

1. **One result per tool call.** Phase 2 parallel-spawn 5-9 reviewer-agents — each must return а structured result; dead spawn → `status: failed` entry в `## Tool log` (not silent drop).
2. **Args validated before execution.** `$ARGUMENTS` flag parsing (semantic, no CLI grammar); PR ref validation via `mcp__github__pull_request_read` или GraphQL fallback.
3. **Permission before side-effect.** Phase 6 «Post Draft PR» action requires AUQ approval before `mcp__github__pull_request_review_write` посчitcalls. State.md writes via M1 `atomic_state_write` (permission-checked at hook layer).
4. **Bounded и structured tool results.** Reviewer-agent output ≤4000 chars per dim; truncation marker. Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.
5. **Escalation gates, not silent abort.** Round-N ≥3 → Phase 6 escalation gate. relevance-filter-agent recursion bounded by reviewer-count.
6. **Final answer grounded в observations.** Phase 6 hand-off message MUST cite the state.md path; finding bodies MUST include Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`.
7. **Errors, denials, cancellations, timeouts → structured observations.** Reviewer spawn failures → `## Errors` body section. `gh` failures fail-open per existing logic — но НОВЫЙ обязательство: log fail-open к `## Errors` (currently silent).

`## Tool log` schema unchanged от M4 §2.2 — reviewer spawns are the dominant entry type; typical run produces 5-12 entries (1 per reviewer + 1 per Phase 5b emit-learning + 1 per PR-side-effect).

---

### 2.3 Budgets — quality-first framing

М6 has **NO hard kill caps**. Same model as M4 §2.3, M5 §2.3. Per master plan P-X5 carry-over (lines 397-405): all milestones M5-M8 must include this section.

**Quality gates (escalate к user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Round-N reviewer re-spawn | 3 | Phase 6 Round-N gate | AUQ — debug-handoff / continue / abort. User picks. |
| Reviewer output size | ~4K chars per dim | §2.2 invariant #4 | Truncation marker, not abort. |
| relevance-filter-agent dedup pass | 1 per round | Phase 3 | If filter agent fails, fall back к orchestrator-side dedup heuristic + `## Errors` entry. |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| LLM reviewer spawn count | 5-9 в parallel | §17 dimension count (9 max after guidelines+conventions collapse) |
| Mechanical pre-pass tools | 3 (lint / schema / secret scan) | §7 Phase 1.5 |

**Explicitly NOT capped:** wall-time, total tool calls, total model turns, total cost. Same rationale as M4 §2.3.

---

## 3. Scope deltas vs. pre-M6 `/geniro:review` + `/geniro:deep-simplify`

### 3.1 Removed

| Component | Reason | Replacement |
|---|---|---|
| `guidelines-criteria.md §8 "Consistency with Codebase / Convention Guard"` (~30 lines) | Wholesale duplication of the `conventions` dimension — same repo-modal-pattern detection. Users saw same finding twice. | Route all repo-modal-pattern findings exclusively к `conventions` dimension (§17). |
| `skills/deep-simplify/` directory entirely (552 LOC) | Master plan §67 — absorb as а flag. P1/P2/P3 severity tier divergent от /review's CRITICAL/HIGH/MEDIUM. | `/review --simplify` flag (§13) folds the 3 simplify passes (Reuse / Quality / Efficiency) into existing dimensions. Severity reconciled: P1→HIGH, P2→MEDIUM, P3→informational. |
| Custom state.md schema (`.geniro/state/review-findings-state.md` overwrite-per-run) | М1 §T2 non-conformance (no frontmatter, no `geniro_kind`, no `approvals[]`). | Path: `.geniro/state/handoff/from-review-<branch>.md`. Schema: М1-T1 frontmatter + М3 body sections (§15). |
| Inline 280+120+250 = ~650 lines из SKILL.md (Phase 1 triage / Phase 4c test-gate / Phase 6 hand-off) | Surface inflation (D8). Reduces readability + dilutes orchestration shell. | Extract к 3 reference files (§18): `phase-1-triage-reference.md`, `phase-4c-test-gate-reference.md`, `phase-6-handoff-reference.md`. SKILL.md target: ~400 lines orchestration shell. |
| Phase 5b «emit pitfall via AUQ» | Master plan §69 — /learnings deleted; auto-emit replaces. | Auto-emit `pitfall` к L2 when relevance-filter-agent reports ≥3-reviewer convergence (P-M6-learnings, §11.2). |

### 3.2 Kept (with adaptation)

| Component | Notes |
|---|---|
| 10-dimension grid (→ 9 after §17 collapse) | Survives с guidelines+conventions consolidation. Conditional firing (design / pr-metadata / spec-compliance) preserved. |
| Round-N counter + Phase 6 escalation gate | Preserved unchanged. Round ≥3 → AUQ с continue / debug-handoff / abort. |
| Input mode detection (OUTGOING / INCOMING / pr-ref) | Preserved unchanged in Phase 1. |
| `effort-scaling.md` 9 hard-escalation signals → risk-tier | Preserved. Pre-M6 only adjusted 3 downstream knobs (threshold, validator budget, spec-compliance default); М6 adds а 4th: risk-tier:high gates mechanical pre-pass secret scan к «strict mode» (additional patterns scanned). |
| --tdd flag (F→P test gate, Phase 4c) | Preserved verbatim. Cross-checked against M4 §3.1 ("TDD discipline belongs к external guidance, not gating") — the M6 --tdd flag is не gating, it's а Phase-4c default-flip. M4's removal of TDD «lane» mode is а different feature; M6 --tdd is reviewer-side test-gate emphasis. Names differ; semantics differ. |
| relevance-filter-agent (Phase 3 dedup) | Preserved. М6 extends its output к include а `convergence_count` field per finding — required для P-M6-learnings auto-emit trigger. |
| 4-option action-gate AUQ (Phase 6) | Preserved options: `/implement` / Post Draft PR / Continue / Skip. Defaults к Recommended /implement when CRITICAL/HIGH count >0. |

### 3.3 Replaced

| Pre-M6 form | M6 form |
|---|---|
| `plan-context-reference.md §1` prose-keyword detection (PR body / `--plan` / `docs/spec.md` / `PLAN.md` etc.) | Schema-aware detection: М5 `geniro_kind: design-doc` frontmatter + 10 named sections (§16.1). Backward-compat fallback к prose detection если frontmatter absent. |
| `spec-compliance-criteria.md` 9 checks (scope / migration / rollback / ACs / flag / deploy / semantics / config / observability) | 11 checks aligned с М5 §17 — adds: **Done Condition met** (§16.2 check #10), **Tools Required available** (§16.2 check #11), refines existing к cite per-section refs. |
| No mechanical pre-pass | Phase 1.5 (NEW) — lint / schema / secret scan BEFORE LLM reviewers (§7 — P-M6-2). |
| State.md custom schema | M1 §T2 conformant — frontmatter + М3 body sections (§15). |
| Pre-load: 11 supporting files inline + 4-5 `_shared/` helpers (D8) | Pre-load remains comparable surface — М6 does not reduce helper count (the criteria files ARE the dimension contracts; can't remove). The 1025→400 line trim is in SKILL.md orchestration shell only. Inline pre-load count: ~14 files (10 criteria + 4 reference) — accepted scope (M-later may revisit). |

---

## 4. Decisions recorded so far

| ID | Decision | Section |
|---|---|---|
| **H-1** | Approach = **H2 Consolidate**. Closes 10 audit defects + 6 of 8 P-M6 obligations. Defers 4-tier risk model (P-M6-1) и trace-grading (P-M6-3) к M-later. | §3, §5 |
| **H-2** | Fix application = **Reporter (current)**. /review reports findings only; does NOT apply fixes. Hand-off к /implement (or manual user action) для applying. `--simplify` flag does NOT change this. | §12, §13 |
| **H-3** | guidelines §8 ("Consistency with Codebase / Convention Guard") collapsed к conventions dim — 10→9 dimensions | §17 |
| **H-4** | /deep-simplify absorbed as `--simplify` flag. Severity map: P1→HIGH, P2→MEDIUM, P3→informational. Folds 3 simplify passes (Reuse / Quality / Efficiency) into existing grid. | §13 |
| **H-5** | Mechanical pre-pass (Phase 1.5) BEFORE LLM reviewers — lint / schema / secret scan. P-M6-2 closure. | §7 |
| **H-6** | State.md migrated к M1 §T2: `.geniro/state/handoff/from-review-<branch>.md` с frontmatter + М3 body sections. | §15 |
| **H-7** | `spec-compliance-criteria.md` rewritten против M5 §17 10-section schema. Adds Done Condition + Tools Required checks. | §16 |
| **H-8** | Phase 5b pitfall auto-emit on ≥3-reviewer convergence (P-M6-learnings). Replaces deleted /learnings skill. | §11.2 |
| **H-9** | SKILL.md trim plan — extract Phase 1 triage / Phase 4c test-gate / Phase 6 hand-off к reference files. Target: ~400 lines orchestration shell. | §18 |
| **H-10** | --tdd flag preserved verbatim. Not conflated с M4's removed TDD lane mode (semantics differ). | §14 |

Open questions: see §17.

---

## 5. Defect inventory (audit 2026-05-18 — before/after)

| # | Defect | Pre-M6 location | M6 fix | Section |
|---|---|---|---|---|
| **D1** | Fix-loop semantics inconsistent с M4 §7.3 — /review reports but doesn't fix; only Phase 6 hand-off | `SKILL.md:75-76` | Confirmed as design choice (H-2 Reporter); NOT а defect. M4's fix-loop pattern applies to /implement self-review only. /review's reporter contract is intentional. Phase 6 hand-off documents the routing. | §12 |
| **D2** | `plan-context-reference.md` stale vs М5 §17 (treats spec as opaque prose, ~3000-char cap) | `plan-context-reference.md:7-14, 56-62` | Rewrite — schema-aware (frontmatter detect + named-section parser). Backward-compat fallback к prose if frontmatter absent. | §16.1 |
| **D3** | `spec-compliance-criteria.md` has 9 checks, M5 §17 has 10 sections — missing Done Condition / Tools Required / Assumptions / Risks checks | `spec-compliance-criteria.md:9-114` | Add 2 new checks (Done Condition met + Tools Required available); refine 4 existing к cite Assumptions / Risks sections explicitly | §16.2 |
| **D4** | State.md non-conformant к M1 §T2 (no frontmatter / no `geniro_kind` / no `approvals[]`) | `SKILL.md:740-806` | Migrate path к `.geniro/state/handoff/from-review-<branch>.md`; M1-T1 frontmatter + canonical body sections | §15 |
| **D5** | M3 compaction blocks absent: no `## Tool log` / `## Termination reason` / `## Errors` / `## Open Questions` / `## Persisted approvals` | `SKILL.md:111, 749-806` | Add all 5 body sections per M3 §6 producer-responsibility contract | §15.2 |
| **D6** | effort-scaling integration thin — risk-tier only adjusts 3 knobs (threshold / validator budget / spec-compliance default); not used к scale spawn count | `SKILL.md:89-97` | Extend: risk-tier:high adds а 4th knob — gates mechanical pre-pass secret scan к strict mode (additional patterns: AWS access keys / GCP keys / Azure SAS / SSH private keys). Spawn count remains 5-9 (architectural constraint). | §7.3 |
| **D7** | No defect-pass в report.md since v8 (2026-04); SKILL.md grew 270→1025 lines | `report.md:3479-3636` | М6 commit lands а full surface refresh; add «v9 audit (M6)» section к report.md noting which dimensions/files were touched и why | §21.5 |
| **D8** | Pre-load: 11+ supporting files inline + 4-5 helpers (exceeds M4's «≤5 typical baseline») | `SKILL.md` (whole file) | Accepted scope — criteria files ARE the dimension contracts, can't elide. SKILL.md trim к ~400 lines removes orchestration-shell bloat (different problem than helper count). Helper count revisit deferred к M-later. | §18 |
| **D9** | State file path predates M1 T2 migration | `SKILL.md:740-741` | Path migration к `.geniro/state/handoff/from-review-<branch>.md` (D4 fix subsumes) | §15 |
| **D10** | /deep-simplify uses P1/P2/P3 (not CRITICAL/HIGH/MEDIUM); independent state model; absorption requires reconciliation | `deep-simplify/SKILL.md:114-117` | Severity map: P1→HIGH, P2→MEDIUM, P3→informational. /deep-simplify directory deleted; logic folded into Phase 2 dimensions weighted by --simplify flag | §13 |

---

## 6. Phase 1 — Triage & Context Collect

State.md `phase: triage` during this phase.

### 6.1 Input mode detection (preserved)

The 3-mode detection (OUTGOING / INCOMING / pr-ref) preserved verbatim от pre-M6 `SKILL.md` Phase 1. М6 documents it for reference в `phase-1-triage-reference.md` (§18) without semantic changes. Detection signals:

| Mode | Trigger | Routing |
|---|---|---|
| OUTGOING | empty `$ARGUMENTS`, branch name, file paths, or diff range | Default — Phase 1.5 mechanical pre-pass |
| INCOMING | PR ref с `K>0` unresolved threads (после AUQ pick) OR anchored NL signals («process review on #N») | `incoming-mode-reference.md` Phase I |
| PR ref + K=0 / K=unknown | `gh` fetch fail-open or no unresolved threads | Direct OUTGOING |

Detection helpers: `mcp__github__pull_request_read` preferred, GraphQL `reviewThreads` paginated fetch fallback.

### 6.2 Risk-tier (preserved + extended)

Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` для the 9 hard-escalation signals → set `risk-tier: standard|high`. Existing downstream knobs (3) preserved:

1. Phase 4 severity threshold (standard: ≥80; high: ≥70).
2. Phase 4b validator coverage (standard: top-3 sample; high: all HIGH).
3. spec-compliance dimension default-on когда risk-tier:high (otherwise gated on PR ref).

**NEW knob (D6 fix):** Phase 1.5 mechanical pre-pass secret scan strictness — risk-tier:high adds patterns AKIA*/sk-*/PEM + AWS access keys / GCP service-account JSON / Azure SAS tokens / SSH `-----BEGIN OPENSSH PRIVATE KEY-----` markers. Standard tier scans only the first 4 (preserved от pre-M6).

### 6.3 Worktree pre-flight + workflow integrations + peer-PR scout

Worktree pre-flight preserved verbatim. Logic moves к `phase-1-triage-reference.md` (§18).

**Workflow integrations (NEW §3.5).** Mirrors `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md:22` plumbing — reads `.geniro/workflow/*.md` files, applies tracker-ID regex against `$ARGUMENTS` + `pr.title` + `pr.body`. On Linear match с MCP available: fetches issue + parent epic + sibling sub-tasks. Persists `linear-task-ref:` + `linear-parent-ref:` к state.md frontmatter. Builds `LINEAR CONTEXT:` block (cap ~2K chars) inlined для **3 reviewer dims only**: spec-compliance + pr-metadata + architecture. Fail-open: missing workflow OR unavailable MCP → degraded к regex-only с `## Caveats` one-liner. /review is read-only от Linear's perspective — status/comment updates remain в /implement Ship per `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/linear.md` §AI-Disclosure Prefix.

**Peer-PR scout expansion.** Pre-M6 top-3 by file-overlap, 300-line per-sibling cap, 3K total cap, fed к architecture + design only. M6-extended: top-10 by `file_overlap + linear_bonus` (+2 if sibling carries `linear-parent-ref` or matches sibling sub-task IDs от §3.5). Per-sibling cap 200 lines (tightened); total cap 5K chars. Fed к **6 reviewer dims**: architecture + design + bugs + conventions + optimizations + spec-compliance (skipped для tests + security + guidelines + pr-metadata — orthogonal или target-PR-specific).

### 6.4 PLAN CONTEXT load (M5-aware — §16.1)

If `$ARGUMENTS` contains а `--plan <path>` flag, OR if PR body contains а `geniro_kind: design-doc` frontmatter reference, OR if any of legacy paths exist (`docs/spec.md`, `docs/plan.md`, `PLAN.md`, `SPEC.md`), Phase 1 loads PLAN CONTEXT.

М6 schema-aware load:
1. Read first 20 lines — if `geniro_kind: design-doc` frontmatter present, switch к structured-section parser (§16.1).
2. Parse the 10 named sections (Objective / Scope.Included / Scope.Excluded / Assumptions / Risks / Steps / Tools Required / Approval Points / Validation / Rollback-Recovery / Done Condition) per М5 §17.2.
3. If frontmatter absent (legacy/unstructured), fall back к prose-keyword detection с ~3000-char cap (preserved).

PLAN CONTEXT body inlined в spec-compliance reviewer spawn prompt only (Phase 2). Other dimensions don't see it.

### 6.5 Memory layer load (M2)

| Helper | Inputs | Outputs |
|---|---|---|
| `load-custom-instructions` MODE: refresh | scope = `review` + `global` + `code-style` | concatenated rule body |
| `load-semantic` MODE: refresh | top-2 default (`_project.md` + `_CODEBASE_MAP.md`) | inlined + fingerprint drift check |
| `query-learnings` | tags inferred от change scope; scope = changed-file paths | top-K matching L2 entries (default K=5; filter superseded/deprecated) |
| `resolve-conflicts` | transitive | hard conflict → AUQ |

### 6.6 Round counter (preserved)

Increment `round:` field в state.md frontmatter. When round ≥3 + unresolved findings exist (detected post-Phase-5), Phase 6 Round-N AUQ fires.

---

## 7. Phase 1.5 — Mechanical Pre-pass (NEW — P-M6-2 closure)

State.md `phase: mechanical-prepass` during this phase.

### 7.1 Rationale

Master plan §329 (P-M6-2): "Mechanical validators BEFORE LLM reviewers (lint / schema / PII scan) — cheaper, more reliable on known patterns." LLM reviewers are expensive (token cost + non-deterministic). Known-pattern checks (deterministic) should run first. Findings either:
- **Resolved automatically** — added к а CRITICAL/HIGH pool with mechanical-source tag.
- **Surfaced к LLM reviewers as prior-context** — LLM agents see «3 lint errors на line 42, 88, 191» в prompt + are instructed к prioritize their own analysis around those areas.

### 7.2 Three checks (М6 baseline)

**Check 1 — Lint check.**
- Probe project for existing lint config: `eslint.config.{js,mjs,cjs,ts}`, `.eslintrc*`, `pyproject.toml [tool.ruff|black|pylint]`, `Cargo.toml [lints]`, `.rubocop.yml`, etc. (heuristic — read project root + adjacent dirs).
- If detected, run the project's own lint command (`pnpm lint`, `npm run lint`, `cargo clippy`, `bundle exec rubocop`) с `--quiet` или equivalent.
- Capture failures as `{tool, file, line, rule, message}` tuples.

**Check 2 — Schema check.**
- Heuristic: if changed files include TypeScript (`*.ts`, `*.tsx`), run `pnpm tsc --noEmit` (project's own command, не invent new ones).
- If JSON schema files (`*.schema.json`, `*.openapi.{json,yaml}`), probe для schema validation command (e.g., `ajv` if present).
- Protobuf — if `.proto` files changed, probe для `buf lint`.
- Capture failures.

**Check 3 — Secret scan.**
- Regex pass against changed-file content (read each, scan body):
  - `AKIA[0-9A-Z]{16}` (AWS access keys)
  - `sk-[a-zA-Z0-9]{32,}` (OpenAI-style keys)
  - `-----BEGIN (?:RSA |EC |OPENSSH |)PRIVATE KEY-----` (PEM markers)
  - `ghp_[a-zA-Z0-9]{36}` (GitHub personal tokens)
- Risk-tier:high strict mode (per §6.2) adds:
  - `(?:AWS|GCP|AZURE)_(?:SECRET|ACCESS)_KEY=` pattern
  - GCP service-account JSON markers (`"type": "service_account"`)
  - Azure SAS tokens (`?si=.+&sig=`)
  - SSH OPENSSH key patterns
- Findings tagged severity:CRITICAL (secrets are always critical).

### 7.3 Output handling

Mechanical findings tagged `mechanical:<check_id>` (e.g., `mechanical:lint`, `mechanical:schema`, `mechanical:secret-scan`). Routed two ways:

1. **К Phase 2 LLM reviewers as prior-context** — pasted into reviewer-agent spawn prompts под а `## Mechanical Pre-pass Findings` section. LLM agents see «3 mechanical findings already detected» и are instructed к use those as starting points (avoid duplicating; extend с semantic understanding).
2. **К Phase 5 persist** — included в the state.md finding list с the mechanical tag preserved. М6 Phase 6 hand-off message surfaces «Mechanical findings: N (lint:X, schema:Y, secret:Z)» as а separate line for visibility.

### 7.4 Idempotency / fail-handling

If lint or schema check command fails (process exit nonzero with no output OR command not found):
- Write `## Errors` entry: `mechanical-prepass-{check_id}: command_unavailable_or_failed`.
- Continue к Phase 2 без the failed check's findings.
- Do NOT abort — fail-open (consistent с pre-M6 `gh` fail-open pattern).

Secret scan is а pure-regex pass — cannot fail (no external command).

### 7.5 Why before LLM (not parallel)

Tempting к parallel-spawn mechanical + LLM. Rejected — LLM agents seeing prior mechanical findings produces better-targeted output (агенты know which areas are already-flagged). Parallel would force post-hoc dedup. Sequential is а ~10-30s wall-time cost для much cleaner output.

---

## 8. Phase 2 — LLM Reviewer Spawns

State.md `phase: llm-spawn` during this phase.

### 8.1 Dimension grid (9 dimensions after §17 collapse)

| # | Dimension | Always? | Conditional trigger |
|---|---|---|---|
| 1 | bugs | always | — |
| 2 | security | always | — |
| 3 | architecture | always | — |
| 4 | tests | always | — |
| 5 | optimizations | always | — |
| 6 | guidelines | always | — |
| 7 | conventions | always | — (absorbs repo-modal-pattern findings exclusively per §17) |
| 8 | design | conditional | UI globs match changed files |
| 9 | pr-metadata | conditional | `pr-ref:` non-none |
| 10 | spec-compliance | conditional | PLAN CONTEXT non-none AND (`pr-ref:` non-none OR risk-tier:high) |
| +N | custom:* | conditional | per user-authored review-extra files |

(10 is а number — but only 7 «always», + 2-3 conditional. The pre-M6 «10» count became 9-10 due к guidelines §8 collapse. М6 reports «5-9 dimensions per spawn batch» depending on conditions.)

### 8.2 Spawn invocation

Single message с N parallel `Agent` tool uses, one per dimension. Per system-prompt parallel rule. Each spawn:
- `subagent_type`: `reviewer-agent` (plugin) — applies `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration ladder
- `model`: per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — typically `sonnet`, `haiku` for guidelines+conventions
- Pre-inlined context per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`:
  - Diff of changed files
  - Project conventions из L4
  - Mechanical pre-pass findings (§7.3) as prior-context
  - PLAN CONTEXT (spec-compliance dim only)
  - Dimension-specific criteria file body inlined
  - Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`

### 8.3 --simplify flag weighting (P-M6-deep-simplify, §13)

When `--simplify` flag present, Phase 2 spawns increase emphasis on Reuse / Quality / Efficiency:

- `architecture` reviewer prompt prepended с deep-simplify Phase-2 Reuse criteria (look for existing abstractions, duplicate logic, premature abstraction).
- `conventions` reviewer prompt prepended с repo-modal-pattern aggressive mode (lower the «≥80% siblings» threshold к ≥60%).
- `guidelines` reviewer prompt prepended с deep-simplify Quality criteria (naming clarity, docs noise, dead code).
- `bugs` reviewer prompt prepended с deep-simplify Quality bug-class extensions (defensive code that masks bugs, redundant null checks, etc.).
- `optimizations` reviewer prompt prepended с deep-simplify Efficiency criteria (verbose loops, unnecessary allocations, sync I/O in async paths).

NO new dimensions added. NO fix-loop added (Reporter behavior per H-2). The flag biases existing reviewers' attention; it does не change output schema или hand-off contract.

### 8.4 Output

Each reviewer returns а list of findings per finding-tagging.md schema. Findings include `severity` (CRITICAL/HIGH/MEDIUM) + `dimension` tag + `evidence` block + `suggested fix` (advisory text, not applied) + `confidence` + `origin` (`mechanical:<check>` for pre-pass findings OR `llm:<dim>` for reviewer findings).

---

## 9. Phase 3 — Filter & Aggregate

State.md `phase: filter` during this phase.

### 9.1 relevance-filter-agent spawn

Spawn `relevance-filter-agent` (plugin) с the full per-dimension findings list. Agent's job:
- Dedup cross-reviewer duplicates (same `path:line` + same finding-title across 2-9 reviewers).
- Tag converged findings с а `convergence_count` field (= N reviewers reported same issue).
- Drop irrelevant findings (e.g., LLM hallucinations с no real file:line correspondence).

М6 NEW: relevance-filter-agent output schema extended к include `convergence_count: int` per dedup'd finding (required для P-M6-learnings auto-emit trigger §11.2).

### 9.2 Mechanical+LLM dedup

Mechanical pre-pass findings (Phase 1.5) and LLM findings may overlap (e.g., lint says «unused import on line 42», bugs reviewer says «dead code on line 42»). filter-agent identifies overlap, preserves the mechanical finding (deterministic) + drops the LLM's redundant entry. The convergence_count for that finding gains +1 for the mechanical contribution.

### 9.3 Severity rollup

Output of Phase 3 is а unified finding list:

```yaml
findings:
  - id: f-001
    severity: CRITICAL
    dimension: security
    file: src/api/user.ts
    line: 42
    title: "SQL injection via unsanitized req.params.id"
    evidence: "..."
    suggested_fix: "..."
    confidence: high
    convergence_count: 3
    origin: ["llm:security", "llm:bugs", "mechanical:lint"]
  - id: f-002
    ...
```

---

## 10. Phase 4 — Stratification & Test Gate

State.md `phase: stratify` during this phase.

### 10.1 Phase 4a — severity threshold

Apply risk-tier threshold:
- standard: keep findings с severity ≥ MEDIUM AND confidence ≥ 80%
- high: keep findings с severity ≥ MEDIUM AND confidence ≥ 70%

Sub-threshold findings written к а «filtered» list (surfaced в `## Open Questions` so user knows what was dropped).

### 10.2 Phase 4b — HIGH validator

Sample HIGH-severity findings и validate via а secondary spawn:
- standard tier: validate top-3 HIGH findings
- high tier: validate ALL HIGH findings
- --tdd flag: validate ALL HIGH findings regardless of tier (--tdd implies «strict mode»)

Validator agent is а `reviewer-agent` clone с prompt emphasizing «confirm or refute, не expand». Output: per-finding `validation: confirmed | refuted | partial` field added.

### 10.3 Phase 4c — F→P test gate

`tdd-mode-reference.md` logic preserved verbatim. М6 documents it в а dedicated `phase-4c-test-gate-reference.md` (§18). Summary:
- --tdd flag default-flips Phase 4c AUQ к «Author tests…(Recommended)» option.
- Phase 6 post-set filtered к [CONFIRMED-BY-TEST] + non-runtime FIX-NOW + INTENT/PRODUCT decisions.
- Without --tdd: Phase 4c AUQ defaults к «Skip — proceed без F→P verification (Recommended)».

### 10.4 --simplify flag interaction

`--simplify` does NOT change Phase 4 thresholds or validator behavior. P1/P2/P3 simplify severities are mapped к CRITICAL/HIGH/MEDIUM tag pool в Phase 3 — they pass through Phase 4 like native CRITICAL/HIGH/MEDIUM findings.

---

## 11. Phase 5 — Persist & Emit

State.md `phase: persist` during this phase.

### 11.1 М1-T2 state file write (D4 fix)

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` per М1 §T2 row.

Content schema in §15. Write via M1 `atomic_state_write` (whole-file rewrite for frontmatter changes; append-safe for body sections).

If pre-M6 file exists at legacy path `.geniro/state/review-findings-state.md`, М6 reads it once on Phase 5 entry (for backward-compat resume) but writes к the new path. Legacy file is NOT auto-deleted (user may have references); а post-M6 deprecation period of one release cycle precedes deletion.

### 11.2 Phase 5b — L2 pitfall auto-emit (P-M6-learnings closure)

Trigger condition: relevance-filter-agent (Phase 3 §9.1) reported а finding с `convergence_count: ≥3` (3+ reviewers reported same issue OR 2 reviewers + 1 mechanical pre-pass).

When trigger fires, auto-spawn (no AUQ — replaces deleted /learnings skill per master plan §69):

```yaml
emit-learning:
  producer: /geniro:review
  scope: <changed-file-glob>
  summary: "<finding title with file:line>"
  tags: [<dimension>, <project-tech>]
  type: pitfall
  trust: verified
  note: "Cross-reviewer convergence: <N> reviewers + <mechanical-flag>"
```

Helper: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` (М2 §9). Dedup + sanitization per М2 §5.2.

Threshold tuning (exact «≥3» semantics) — fixed по spec, не deferred. М2 §5.3 line 164 codifies this.

### 11.3 PR comment posting (conditional)

If Phase 6 user picks «Post Draft PR» option (§12), Phase 5 writes the finding list к the PR via `mcp__github__pull_request_review_write` с status `COMMENTED`. M3 `non-resumable-actions[]` entry appended via `atomic_state_write`:

```yaml
non-resumable-actions:
  - action: pr-review-comment-batch
    completed-at: <ISO-8601>
    pr-ref: <owner>/<repo>#<num>
    finding-count: <N>
    comment-ids: [<id1>, <id2>, ...]
```

PR post fails fail-closed — if `mcp__github__pull_request_review_write` errors, write `## Errors` entry + abort Phase 5 (don't proceed к hand-off with а half-posted state).

### 11.4 Idempotent re-entry

If Phase 5 re-enters after compaction, the model:
1. Reads state.md `non-resumable-actions[]` — если PR post already completed, skip re-post.
2. Re-reads findings от Phase 3 dedup output (held в context OR re-runs Phase 3 if context lost).
3. Re-writes from-review-<branch>.md (overwrite — `atomic_state_write` handles atomicity).

---

## 12. Phase 6 — Action Gate Hand-off

State.md `phase: action-gate` during this phase.

### 12.1 AUQ shape (preserved + persistence)

4 options preserved от pre-M6:

- **/implement findings** (Recommended when CRITICAL/HIGH count >0) — exit /review, suggest the next command `/implement .geniro/state/handoff/from-review-<branch>.md`.
- **Post Draft PR review** — fires Phase 5 PR post (§11.3) then exits.
- **Continue rounds (re-review)** — if round ≥3, fires Round-N escalation gate (§12.2); otherwise loops back к Phase 1 increment round counter.
- **Skip — keep findings on disk** — terminal exit; user can resume later.

М6 NEW: persist user pick к `approvals[]` с category `action_gate`. Resume-safe per P-M1-1.

### 12.2 Round-N escalation gate (preserved)

When round ≥3 AND user picks «Continue rounds», fire а secondary AUQ:
- **Continue (round 4)** — re-enter Phase 1 with round counter incremented; risk of infinite loop if user picks repeatedly (capped at round 5 hard ceiling — round 6 attempts auto-trigger «Escalate к user» path).
- **Escalate к user — structured handoff** — terminal `escalated` state; writes а structured «next steps» summary к chat AND к state.md `## Open Questions` section.
- **Abort** — terminal `aborted` state.

### 12.3 Reporter behavior — no fix loop (H-2)

М6 confirms: /review does NOT apply fixes. Phase 6 hand-off message NEVER includes «I'll fix these now» language. The /implement option routes к /implement skill (manual or via Phase 6 hand-off line).

`--simplify` flag does NOT change this. The flag biases Phase 2 reviewer attention (§8.3) but the output is still а finding list для consumption by other skills, not auto-applied fixes.

### 12.4 Reporter contract vs M4

М4 §7 (/implement self-review) has 5 reviewer dimensions + а bounded fix loop. М6 (/review) has 9 reviewer dimensions + а Reporter hand-off. Semantically different skills:
- /implement self-review = post-implementation gate that fixes its own findings before ship.
- /review = standalone audit с findings consumed by another skill.

М6 does NOT collapse these. They serve different workflows. М4 §3.1 explicitly preserved this split.

---

## 13. --simplify flag — P-M6-deep-simplify closure

Master plan §67: «/deep-simplify → optional flag on /review».

### 13.1 Trigger

`$ARGUMENTS` contains а `--simplify` token. Semantic parse — matches whole-word `simplify`, `--simplify`, `simplify mode`, или similar. Detection at Phase 1 triage (§6).

### 13.2 Effect on Phase 2 spawn weighting

Per §8.3 — prepend deep-simplify criteria onto 5 of the 9 dimensions (architecture / conventions / guidelines / bugs / optimizations).

### 13.3 Severity reconciliation

Pre-M6 /deep-simplify used P1/P2/P3 severities. М6 maps:
- P1 → HIGH
- P2 → MEDIUM
- P3 → informational (filtered out of Phase 4 stratification unless --tdd or risk-tier:high)

М6 reviewer-agent output schema is canonical CRITICAL/HIGH/MEDIUM (per `finding-tagging.md`). The simplify-tagged findings get CRITICAL/HIGH/MEDIUM tag at output time. No special P1/P2/P3 fields в schema.

### 13.4 What's NOT carried over from /deep-simplify

- **Phase 4 Fix agent** (pre-M6 /deep-simplify Phase 4 applied P1+safe-P2 fixes автоматically). М6 does NOT carry — Reporter behavior (H-2). User who wants applied fixes uses /implement с the review state file as input.
- **Phase 5 Verify agent** (pre-M6 ran validation then auto-reverted на failure). М6 does NOT carry — same reason. /implement has its own test-fail handling per M4 §6.2.
- **Independent state model.** М6 uses canonical М1 §T2 state file (§15).

### 13.5 simplify-criteria.md migration

`skills/deep-simplify/simplify-criteria.md` (135 lines) is preserved as а reference document at `skills/review/simplify-criteria.md` after М6 deletion of /deep-simplify directory. Phase 2 spawn prepend reads from this file. The file is NOT а new dimension — it's prepended onto 5 existing dimensions.

### 13.6 Anti-pattern: don't recreate /deep-simplify

М6 explicitly rejects: «add а `simplify` dimension к the 9 grid». This would re-create а separate skill in disguise. The fold-into-existing-dimensions approach is the only correct absorption.

---

## 14. --tdd flag — preserved + clarified

М6 preserves `--tdd` verbatim. Section here exists primarily к clarify scope vs M4's removed «TDD lane».

### 14.1 What --tdd does в /review

- Phase 4b: validates ALL HIGH findings (not top-3 sample).
- Phase 4c: F→P test-gate AUQ defaults к «Author tests…(Recommended)».
- Phase 6 post-set filtered к [CONFIRMED-BY-TEST] + non-runtime FIX-NOW + INTENT/PRODUCT decisions.

### 14.2 What --tdd does NOT do

- Does NOT change Phase 1 triage logic.
- Does NOT trigger /review's fix loop (there isn't one — Reporter, H-2).
- Does NOT conflict с the M4 TDD lane removal — those are separate features. M4 removed «TDD lane» from /implement (а multiplexer flag affecting parallel WU agents и pre-approval gates). М6 --tdd is а reviewer-side test-gate emphasis only.

### 14.3 Mode AUQ

When neither --tdd nor --standard flag present в `$ARGUMENTS`, Phase 1 fires а mode AUQ asking the user к pick. Logic preserved от pre-M6 `SKILL.md:99-107`. Persist к `approvals[]` с category `tdd_mode_choice`.

---

## 15. State.md — M1 §T2 conformance

### 15.1 Path

`<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md`

Per М1 §T2 «Handoff state file naming convention» row. `<PRIMARY_ROOT>` resolved per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A.

### 15.2 Frontmatter schema

```yaml
---
tier: T2                                  # M1 §T2 required (handoff file)
producer: review                          # M1 §T2 required
schema-version: 1                         # M1 §T2 required
branch: <branch>                          # M1 §T2 required
timestamp: <ISO-8601 UTC>                  # M1 §T2 required (last-write — replaces М6-draft `last_updated_at`)
consumer: implement                       # M1 §T2 required (primary downstream)
geniro_kind: state-handoff                 # M6 schema marker (informational; M1 derives tier-by-frontmatter)
geniro_schema_version: m6-v1               # M6 schema version
task_slug: review-<branch>                 # M6 extension
phase: <triage|mechanical-prepass|llm-spawn|filter|stratify|persist|action-gate|done|aborted|escalated>   # M6 extension (in-skill state tracking; M3 recovery surfaces)
status: <in-progress|done|failed>          # M1 §T1-style state lifecycle (extension — applied here to enable mid-run compaction recovery)
mode: <standard|tdd>                       # M6 extension
round: <int>                               # M6 extension
risk-tier: <standard|high>                  # M6 extension
pr-ref: <owner/repo#num|null>               # M6 extension
plan-context-ref: <abs-path|null>           # M6 extension
simplify-mode: <true|false>                 # M6 extension
approvals: []                               # M1 optional (P-M1-1 schema)
non-resumable-actions: []                   # M1 optional (M3 §8 schema)
---
```

**Note on T2 + state-tracking extensions.** Canonical M1 §T2 is а one-shot producer→consumer handoff с frontmatter fields `tier/producer/schema-version/branch/timestamp/consumer`. M6 extends с `phase:`/`status:`/`round:`/`approvals[]` to enable mid-run compaction recovery (M3 SessionStart hook reads this file on resume). The file functions as а T2 handoff AT REST (after Phase 5 persist) и as а T1-like state file DURING THE RUN.

### 15.3 Body sections (M3 compaction-survival — D5 fix)

```markdown
# Review: <topic / branch>

## Summary
- Branch: <branch>
- Mode: <standard|tdd>
- Round: <N>
- Risk-tier: <standard|high>
- Dimensions spawned: [<list>]
- Mechanical pre-pass: [lint:N, schema:M, secrets:K]
- Finding totals: CRITICAL=<X>, HIGH=<Y>, MEDIUM=<Z>

## Findings

### CRITICAL
<list>

### HIGH
<list>

### MEDIUM
<list>

## Deferred — sub-threshold
<list, surfaced for user awareness>

## Tool log
<per M3 §6 Block 2 — reviewer spawns + side-effects>

## Errors
<per M3 §6 Block 5b — failed spawns, gh fail-open, mechanical-prepass failures>

## Open Questions
<per M3 §6 Block 5c — escalation-required items, ambiguous findings>

## Termination reason
<per M4 §2.1.1 — only on aborted state>

## Persisted approvals
<per M3 §6 Block 5d — rendered from approvals[] frontmatter for user-readability>
```

### 15.4 М4 ↔ M6 hand-off contract

М4 /implement reads `from-review-<branch>.md`:
- **Summary block** — quick orientation (mode, round, risk-tier).
- **CRITICAL / HIGH / MEDIUM finding lists** — applies findings (with M4 §7.3 fix loop, 3 rounds).
- **Tool log** — informational; not consumed by М4.
- **Persisted approvals** — М4 may inspect for prior /review user picks (e.g., если user picked «Post Draft PR» in /review, /implement knows the PR was already informed).

М4 does NOT delete the state file after consuming. М6's terminal `done` state means /review is done; the file's lifetime is owned by the user (manual cleanup OR retention as audit trail).

---

## 16. spec-compliance redesign — D2/D3 + P-M6-spec.md closure

### 16.1 plan-context-reference.md rewrite

Pre-M6 §1 (lines 7-14) enumerates PR body / `--plan` / legacy filenames as opaque-prose sources с ~3000-char cap.

М6 rewrite:

```markdown
# PLAN CONTEXT — schema-aware load

## Detection (in order)

1. **М5 frontmatter detect.** Read first 20 lines of the candidate file (PR body's `geniro-plan: <path>` reference, OR `--plan <path>` flag value, OR walk-up search for `.geniro/planning/*/spec.md`). If `geniro_kind: design-doc` + `geniro_schema_version: m5-v1` present, switch to structured-section parser.
2. **Legacy prose detect (fallback).** If frontmatter absent, treat as opaque prose с ~3000-char cap (pre-M6 behavior preserved).

## Structured-section parser

When frontmatter present, parse the 10 named sections per M5 §17.2:
- Section 1: Objective
- Section 2: Scope — Included
- Section 3: Scope — Excluded
- Section 4: Assumptions
- Section 5: Risks
- Section 6: Steps
- Section 7: Tools Required
- Section 8: Approval Points
- Section 9: Validation
- Section 10: Rollback-Recovery
- Section 11: Done Condition

Section bodies inlined в spec-compliance reviewer spawn prompt с per-section markers.

## Output к reviewer prompt

Pre-M6: 3000-char prose blob.
М6: Section-tagged blob с frontmatter goal-state (budget / checkpoints / forbidden_actions / approval_required_for / tools_required) inlined at top. Reviewer agent can cite specific section names в findings.
```

### 16.2 spec-compliance-criteria.md — 11 checks (D3 fix)

| # | Check | Pre-M6 | M6 |
|---|---|---|---|
| 1 | Scope items present в diff | ✅ | ✅ refined: cite section 2 explicitly |
| 2 | Migration steps applied | ✅ | ✅ refined: cite section 6 (Steps) and section 10 (Rollback) |
| 3 | Rollback documented | ✅ | ✅ refined: cite section 10 |
| 4 | Acceptance criteria addressed | ✅ | ✅ refined: cite section 9 (Validation) |
| 5 | Feature flag wired | ✅ | ✅ refined: cite section 6 + section 8 (Approval Points) |
| 6 | Deploy order respected | ✅ | ✅ refined: cite section 6 |
| 7 | Semantics match spec | ✅ | ✅ refined: cite section 1 (Objective) |
| 8 | Config / env vars updated | ✅ | ✅ refined: cite section 7 (Tools Required) |
| 9 | Observability hooks added | ✅ | ✅ refined: cite section 9 (Validation) |
| 10 | **Done Condition met** | ❌ | ✅ NEW: check section 11 — does diff achieve the observable signal? |
| 11 | **Tools Required available** | ❌ | ✅ NEW: check section 7 — does environment have all listed tools? (cross-check `which <tool>` via Bash). |
| — | Assumptions cited / Risks cited | (implicit) | sections 4+5 inlined; findings reference sections explicitly when contradicted |

Output schema preserved. Confidence ratings calibrated к the per-section evidence.

### 16.3 Backward-compat fallback

When М5 frontmatter absent (legacy spec.md, или а PR with prose-only PLAN CONTEXT):
- Run 9 pre-M6 checks (unchanged).
- Skip new checks #10 and #11 (no section anchors к cite).
- Note в `## Open Questions`: «PLAN CONTEXT lacks М5 schema — falling back к prose checks; Done Condition + Tools Required не verified».

---

## 17. Dimension collapse — guidelines §8 → conventions

### 17.1 What gets removed

`guidelines-criteria.md §8 "Consistency with Codebase (Convention Guard)"` (~30 lines). Currently this section directs the guidelines reviewer к check repo-modal patterns (file structure / naming conventions / coding style consistency с existing siblings).

This is _the same job_ as the `conventions` dimension (per `conventions-criteria.md:5` «Modal-pattern statistical inference (≥80% siblings)»). Two reviewers reporting the same findings → user-facing «told twice».

### 17.2 What gets preserved

- `guidelines-criteria.md §1-7` (style / naming-style / documentation / comment-quality / formatting / public-API surface / dead-code) preserved.
- `conventions-criteria.md` preserved verbatim — it's already the modal-pattern dim.
- All repo-modal-pattern findings routed exclusively к `conventions` after the collapse.

### 17.3 Migration

М6 commit edits `guidelines-criteria.md`:
1. Remove §8 lines.
2. Add а note at the top: «Repo-modal patterns are owned by the `conventions` dimension; do not duplicate them here».
3. Renumber subsequent sections if any (likely just §8 → end; §9+ if any) — check during implementation.

No changes к `conventions-criteria.md`.

### 17.4 Why not the reverse (delete `conventions`, keep `guidelines §8`)?

`conventions` runs at haiku-tier and is statistically inferential (samples N sibling files, computes modal patterns, flags deviations ≥80%). `guidelines §8` runs at sonnet-tier as part of the broader guidelines rubric — more expensive, less specialized.

Routing repo-modal-pattern detection к the specialized dim (conventions, haiku) wins on cost AND quality.

---

## 18. SKILL.md trim plan — D8 partial fix

Pre-M6: 1025 lines monolith. Target: ~400 lines orchestration shell.

### 18.1 Extract к `phase-1-triage-reference.md` (~280 lines)

Contents:
- Input mode detection (OUTGOING / INCOMING / pr-ref) — pre-M6 lines 36-78
- Worktree pre-flight — pre-M6 lines 80-87
- Step 0.5 round counter — pre-M6 lines 67-79
- Step 0.7 risk-tier signals — pre-M6 lines 89-97
- Peer-PR scout — pre-M6 lines ~200-280

SKILL.md retains а 2-3 line summary + `→ See phase-1-triage-reference.md`.

### 18.2 Extract к `phase-4c-test-gate-reference.md` (~120 lines)

Contents:
- F→P test gate AUQ shapes (--tdd vs --standard defaults)
- Test-gate finding-tag rules ([CONFIRMED-BY-TEST] / [INTENT] / [PRODUCT])
- Post-set filtering rules

SKILL.md retains а 2-3 line summary + ref.

### 18.3 Extract к `phase-6-handoff-reference.md` (~250 lines)

Contents:
- 4-option action-gate AUQ
- Round-N escalation AUQ
- Failing-tests handling (post-gate logic)
- Post Draft PR comment flow
- PR-ref scope expansion logic

SKILL.md retains а 2-3 line summary + ref.

### 18.4 What stays в SKILL.md

- Frontmatter (allowed-tools, description, etc.) — required by Claude Code skill framework.
- High-level 6-phase orchestration map.
- Per-phase entry/exit transition rules.
- AUQ schemas (referenced; не fully spelled out — links к reference files).
- Tool log / Errors / Open Questions M3 contract reminder.
- Memory I/O obligation references.

Net: SKILL.md becomes а thin orchestration shell pointing к dimension criteria files (10 unchanged) + 4 reference files (3 NEW + tdd-mode-reference.md unchanged).

### 18.5 Anti-pattern: don't inline criteria files

Tempting к inline some criteria к SKILL.md «для readability». Reject — the criteria files are dimension contracts; orchestration shell should reference, не reproduce.

---

## 19. Memory I/O — M2 §13 obligation

Per M2 §13: every pipeline skill declares helpers + boundaries.

### 19.1 Helper-call schedule

| Phase | Helper | Direction | MODE | Inputs | Outputs |
|---|---|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` | scope = `review` + `global` + `code-style` | concatenated rule body |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` | top-2: `_project.md` + `_CODEBASE_MAP.md` | inlined + drift check |
| Phase 1 entry | `query-learnings` | read L2 | n/a | tags inferred от changed-file paths + `pitfall` type bias | top-K matching entries (default K=5) |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a | three loaded layers | precedence-resolved |
| Phase 1.5 (mechanical pre-pass) | none | — | — | — | — |
| Phase 2 (LLM spawn) | none | — | — | — | — |
| Phase 3 (filter) | none | — | — | — | — |
| Phase 4 (stratify) | none | — | — | — | — |
| Phase 5 (persist) | M1 `atomic_state_write` | write T2 | n/a | state file path; full body | whole-file rewrite |
| Phase 5b (emit) | `emit-learning` | write L2 | n/a | producer = /review; type = `pitfall`; trust = `verified` | append к `learnings.jsonl` |
| Phase 6 (action-gate) | M1 `atomic_state_write` | write T2 | n/a | state file path; updated approvals[] | whole-file rewrite |

### 19.2 L2 emit triggers (М2 §5.3 patched)

| Type | М6 emits |
|---|---|
| `convention` | Not by М6. М4 /implement owns. |
| `decision` | Not by М6. М5 /plan owns. |
| `diagnosis` | Not by М6. М7 /debug owns. |
| `pitfall` | **YES** — Phase 5b auto-emit when relevance-filter-agent reports convergence ≥3. Replaces deleted /learnings skill per master plan §69. |
| `discovery` | Not by М6. |

### 19.3 ACI per-phase tool surface

**Phase 1 / 1.5:** Read / Grep / Glob / Bash (read-only — `gh pr view`, `git diff`, `which <tool>`, project lint commands, `tsc --noEmit`). No Edit/Write apart от М1 state.md.

**Phase 2 / 3 / 4:** Agent spawns (`reviewer-agent`, `relevance-filter-agent`). No Edit/Write/Bash mutations.

**Phase 5:** Write (scoped к `.geniro/state/handoff/**` via existing safety hooks). `mcp__github__pull_request_review_write` (conditional). `emit-learning` helper writes к `.geniro/learnings.jsonl`.

**Phase 6:** AskUserQuestion. Read-only.

Existing safety hooks (file-protection, git-guardrails, `.geniro/` deletion guard) apply.

---

## 20. Cleanup checklist

### 20.1 `skills/review/SKILL.md` — trim (D8/§18)

Surgical edit — extract 3 reference files; reduce monolith к ~400 lines orchestration shell.

### 20.2 `skills/review/plan-context-reference.md` — rewrite (D2/§16.1)

Full rewrite for M5 schema-aware detection.

### 20.3 `skills/review/spec-compliance-criteria.md` — extend (D3/§16.2)

Surgical edit — add checks #10 (Done Condition) + #11 (Tools Required); refine 9 existing к cite per-section references.

### 20.4 `skills/review/guidelines-criteria.md` — surgical edit (H-3/§17)

Delete §8 «Consistency with Codebase (Convention Guard)»; add top-of-file note routing repo-modal-pattern findings к `conventions`.

### 20.5 `skills/deep-simplify/` — delete entire directory (H-4/§13)

Remove `SKILL.md` + `simplify-criteria.md`. Move `simplify-criteria.md` к `skills/review/simplify-criteria.md` (preserved as а reference document for Phase 2 spawn prepending).

### 20.6 `plugin.json` — slash command + agent registration

- Remove `/geniro:deep-simplify` slash command.
- Add new reference files к skill's auto-pre-load list (if explicit list maintained).

### 20.7 `CLAUDE.md` — skill-table

- Remove `/geniro:deep-simplify` row.
- Update `/geniro:review` row: append `--simplify` к the flags list; mention «absorbs /deep-simplify».

### 20.8 М1 §T2 row update

Per audit D4/D9, `from-review-<branch>.md` is the canonical T2 row in М1 §T2 (confirmed at M1:497 in the migration-from-pre-redesign table). М6 implements the producer side; consumer side (/implement) implemented under M4 §5.4 «Inputs from <producer>» persist.

### 20.9 New files created by М6

- `skills/review/phase-1-triage-reference.md` (~280 lines)
- `skills/review/phase-4c-test-gate-reference.md` (~120 lines)
- `skills/review/phase-6-handoff-reference.md` (~250 lines)
- `skills/review/simplify-criteria.md` (relocated от /deep-simplify, 135 lines)

### 20.10 report.md — v9 audit entry (D7)

Append а «v9 audit (M6)» section noting:
- Surface refresh после 1 year of no defect-pass.
- 10 audit defects closed.
- /deep-simplify absorbed.
- guidelines §8 collapsed.

---

## 21. Cross-M dependencies & Implementation note

### 21.1 М1 dependencies

- **М1 PR-0 (helpers)** must land before М6 implementation.
- **М1 §T2** row for `from-review-<branch>.md` must be canonical (verify M1 doc).
- **М1 P-M1-1** `approvals[]` schema extended к M6 categories. As-built set (per implementation pass): `tdd_mode_choice` (Phase 1 Mode AUQ), `test_gate_choice` (Phase 4c spawn approval), `action_gate` (Phase 6 4-option pick — Post selection IS the pr-post consent, so no separate `pr_post_confirm` category), `round_n_escalation` (Phase 6 secondary AUQ когда round ≥3), `failing_tests_commit_policy` (Phase 6 commit policy для AI-authored tests). Spec draft listed `pr_post_confirm` as а candidate; implementation collapsed pr-post consent into `action_gate` since picking «Post Draft PR review» в the Action gate IS the approval per phase-6-handoff-reference.md §4 contract.

### 21.2 М2 dependencies

- **М2 §5.3** patched contract for `pitfall` emission triggered by relevance-filter-agent convergence_count.
- **М2 §9** `emit-learning` helper called Phase 5b.
- **М2 §13** Memory I/O obligation closed (§19).

### 21.3 М3 dependencies

- **М3 SessionStart hook** — М6 state.md is recoverable via re-injection contract. Hook re-reads `from-review-<branch>.md` + `.geniro/instructions/review.md` + `.geniro/instructions/global.md` + `.geniro/instructions/code-style.md`.
- **М3 §6 Block 5d** — М6 relies on this к render `approvals[]` on resume.
- **М3 §7.2** Echo contract — М6 Phase 1 helper-calls echo per the rule.

### 21.4 М4 ↔ М6 contract

М4 /implement consumes `from-review-<branch>.md` per §15.4. М4 also CAN trigger /review post-ship (Phase 3 self-review uses 5-dim reviewer-agent spawns — different skill, same underlying agent contract).

### 21.5 М5 ↔ М6 contract

М6's spec-compliance dimension consumes M5's spec.md schema (§16). М6 does NOT modify M5's emitted artifacts.

### 21.6 Work order

1. ~~**Resolve H-1 through H-10**~~ ✅ DONE in this doc (§4).
2. **Apply §20.4 surgical edit к `guidelines-criteria.md`** first (lowest risk).
3. **Apply §20.3 surgical edit к `spec-compliance-criteria.md`** (add 2 new checks).
4. **Write §20.2 rewrite of `plan-context-reference.md`** для M5 schema-aware.
5. **Write 3 new reference files** (`phase-1-triage`, `phase-4c-test-gate`, `phase-6-handoff`).
6. **Surgically edit `SKILL.md`** — extract phases into refs (§18).
7. **Add Phase 1.5 mechanical pre-pass logic** (§7) к `SKILL.md`.
8. **Add Phase 5b pitfall auto-emit logic** (§11.2) к `SKILL.md`.
9. **Migrate state.md schema** (§15) — add new path write logic; preserve backward-compat resume read для legacy path.
10. **Delete `skills/deep-simplify/`** dir (§20.5); move simplify-criteria.md.
11. **Update `plugin.json` + `CLAUDE.md`** per §20.6 / §20.7.
12. **Manual end-to-end test:** small OUTGOING review с --simplify flag, small INCOMING review с PR ref, small spec-compliance check against а М5-emitted spec.md.

**Skill-deletion sequencing:** /deep-simplify deletion under М6 commit. М4 had а guard «work whether /deep-simplify is present or already deleted» (M4 §9.3) — М6 honors that contract by performing the deletion cleanly.

---

## 22. Open questions

| ID | Topic | Status |
|---|---|---|
| **OQ-M6-1** | **Phase 1.5 mechanical pre-pass — script vs inline orchestrator logic?** Lint/schema/secret checks could live in а Bash script invoked once OR be enumerated as orchestrator-side tool-call sequence in SKILL.md. Trade-off: script = testable, has а DAG; inline = no infra. | ⏳ Deferred к implementation. Tentative: inline initially; promote к script if complexity grows. |
| **OQ-M6-2** | **Risk-tier:high strict secret scan pattern list — versioned ontology?** The 8 patterns в §7.2 are baseline. Should they live в а separate `secret-patterns.md` reference file (versioned, project-overridable) или inline? | ⏳ Deferred. Tentative inline initially; promote к file if project-overrides become а common feature request. |
| **OQ-M6-3** | **relevance-filter-agent output schema extension** — adding `convergence_count` field. Does the existing agent prompt support this, или needs amendment? | ⏳ Deferred к implementation step 8. Verify agent file + amend prompt if needed. |
| **OQ-M6-4** | **Round-N hard ceiling at round 5 (§12.2) — accidentally infinite loop guard.** Pre-M6 had no hard ceiling. The proposed ceiling is fail-safe but never tested. Should this be soft (warning) или hard (force-escalate)? | ⏳ Deferred. Tentative hard ceiling at round 6 (so user has 3 free rounds + 1 round-3-escalation-pick + 2 «Continue»-picks + automatic escalate at round 6). |
| **OQ-M6-5** | **--simplify + risk-tier:high interaction** — does --simplify imply high tier? Or are they orthogonal? | ⏳ Deferred. Tentative: orthogonal (user can run --simplify on а standard-tier task). |

P-M6 obligations deferred к M-later:
- **P-M6-1 4-tier risk model.** Pre-M6 has 2 tiers (standard/high). Master plan §328 specifies 4 (Low/Medium/High/Regulated). Heavy infrastructure (audit log dir, rollback contract, post-action verifier agent). Deferred — implement when а regulated-industry user actually requires it.
- **P-M6-3 trace-grading hooks.** 5-question eval grading after each tool call. Useful для P-X6 telemetry pipeline; standalone value unclear. Deferred к P-X6.

---

## 23. Master plan reconciliation

### 23.1 Skill-list status

М6 keeps `/review` (master plan §22). Deletes `/deep-simplify` (master plan §67). Master plan list of 11 surviving skills unchanged.

### 23.2 М6-specific obligations from master plan

| Master plan ref | Obligation | М6 status |
|---|---|---|
| §22 | /review survives redesign | ✅ §2 (preserves 9 dimensions, 6-phase structure) |
| §67 | /deep-simplify absorbed as flag | ✅ §13 |
| §69 | /learnings deleted; auto-emit replaces | ✅ §11.2 |
| §328 (P-M6-1) | 4-tier risk model | ⏳ Deferred к M-later (§22) |
| §329 (P-M6-2) | Mechanical validators before LLM | ✅ §7 |
| §330 (P-M6-3) | Trace-grading hooks | ⏳ Deferred к P-X6 (§22) |
| Anti-patterns guardrail (P-MP-1) | Anti-pattern audit | ✅ §25 |
| Per-skill quality-first budget guidance (P-X5) | Budgets quality-first | ✅ §2.3 |
| M5 §22.4 | spec.md consumption | ✅ §16 |
| M2 §5.3 | pitfall auto-emit trigger | ✅ §11.2 |

### 23.3 Stale assumptions corrected

| Original draft assumption | Corrected (this rev) |
|---|---|
| /review is «unchanged» under М6 (per M4 §12.1) | Major surface refresh required (10 audit defects + 6 P-M6 obligations) — «unchanged» was а stale outline written before М5 redefined spec.md schema. |
| /deep-simplify can stay as а separate skill | Master plan §67 — absorb as flag. М6 deletes the directory. |
| Mechanical pre-pass would over-engineer the loop | P-M6-2 is а master-plan-mandated layer. Cost (~10-30s wall-time per run) recouped by cleaner LLM output. |
| guidelines §8 + conventions duplication is acceptable | Audit shows user-facing «told twice» findings. Collapse improves UX. |

---

## 24. Anti-rationalization (P-MP-1 closure)

Per master plan P-MP-1 (lines 162-179): every milestone closes с an explicit anti-pattern check. This section catalogues rationalizations а reader might offer к backtrack M6 decisions. Cross-cutting LLM-orchestration anti-patterns (auto-handle / kill caps / silent abort / hook bypass) are addressed inline below where they would apply к M6.

| Your reasoning | Why it's wrong |
|---|---|
| "/review should fix its own findings — М4 has а fix loop, parity is good." | M4 /implement self-review is а post-implementation gate that ships clean code. /review is а standalone audit consumed by downstream skills. Different workflows, different output contracts. User-picked Reporter behavior (H-2) reflects this. М4 parity is а false constraint. |
| "Mechanical pre-pass is too slow — skip it, LLM reviewers cover the same ground." | LLM reviewers cover similar ground at 100x the cost + non-deterministic. Lint detects а missing import faster и more reliably than а security reviewer would. Run cheap-deterministic first; LLM-spawn second с pre-pass findings as prior-context. |
| "Just keep guidelines §8 — двойное finding is а feature, not а bug." | User-facing «told twice» is concrete UX friction documented в audit. Two reviewers reporting same thing wastes user attention. Specialized dim (conventions, haiku-tier) wins on cost AND quality. |
| "Absorbing /deep-simplify means losing Phase 4 Fix agent — что-то ценное теряется." | Phase 4 Fix agent applied automated code edits which is а fixer responsibility. М6 (/review) is Reporter. Users wanting auto-applied fixes pipe /review --simplify output к /implement. Same outcome, cleaner separation of concerns. |
| "spec-compliance check #11 (Tools Required available) requires Bash mutation — that's а risk." | `which <tool>` is read-only Bash. No mutation. Standard ACI surface allows it (§19.3). |
| "Phase 5b auto-emit pitfall could spam learnings.jsonl с false positives." | Threshold = convergence_count ≥3. Three reviewers (or 2 reviewers + 1 mechanical pre-pass) converging on same finding is а strong signal. dedup + sanitization per M2 §5.2 prevents duplicates. False-positive risk низкий. |
| "SKILL.md trim к 400 lines is а cosmetic concern." | 1025-line monolith hurts onboarding (new contributors / users reading the skill к understand behavior) и debug (search-and-find for а specific phase rule). Reference-file pattern matches M4. Cosmetic surface IS surface. |
| "Risk-tier:high secret scan strict mode adds latency without ROI." | Secret leakage is а CRITICAL-severity event с irreversible consequences (key rotation, blast radius). 4 extra regex patterns на а changed-file scan adds <1s. ROI is asymmetric — small cost, large downside avoided. |
| "Phase 1.5 mechanical pre-pass should run in parallel с Phase 2 LLM spawns — same wall-time." | Tempting но wrong. LLM agents seeing prior mechanical findings produce better-targeted output. Sequential adds ~10-30s; parallel forces post-hoc dedup и dilutes LLM focus. Sequential wins on output quality. |
| "--simplify flag is а natural place to add `simplify` as а new dimension." | This re-creates /deep-simplify as а disguised skill. The fold-into-existing approach (5 weighted dims) is the only correct absorption. Adding а new dim defeats the master-plan-§67 collapse intent. |
| "Round-N hard ceiling at round 6 is paternalistic — user knows what they want." | User picking «Continue» 5 times in а row indicates either а bug in stratification OR а workflow that should be /debug. Hard ceiling protects against accidental infinite-loop UX. User retains agency via «Escalate» pick. |
| "Auto-drop MEDIUM findings к reduce user friction." | The Metaswarm anti-pattern catalogued в `report.md`. M6 routes MEDIUM findings через the always-WAIT MEDIUM-gate (per `skills/_shared/medium-gate.md`). Never auto-drop. |
| "Skip Phase 5 approvals[] persistence — Phase 6 hand-off captures everything." | Phase 6 AUQ fires once; compaction mid-Phase-3 (filter) would lose all prior gates без `approvals[]`. M3 §6 Block 5d depends on this persistence; non-negotiable. |
| "Add а wall-time kill cap для long-running /review с many dimensions." | §2.3 quality-first — no Class-A hard caps. Round-N escalation (§12.2) is the Class-B gate; user decides. |
| "Bypass git guardrail hooks when Phase 5 PR comment post fails." | Hooks fail для reason. Phase 5 fail-closed semantics (§11.3) — PR-post failure surfaces an error, does NOT auto-retry с --no-verify. Investigate, fix, re-fire. |
| "Phase 4c F→P test gate is over-engineered для standard tier — skip it." | F→P verification ensures test-first hygiene (CRITICAL/HIGH findings should fail а test BEFORE а fix lands). Pre-M6 logic preserved verbatim. --tdd users specifically benefit; --standard users still get а sanity gate. |

---

## 25. Cross-references

- М1 (state-files framework): `architecture/M1-state-files.md` (esp. §T2 row для `from-review-<branch>.md`)
- М2 (memory layers): `architecture/M2-memory-layers.md` (esp. §5.3 patched contract; §9 emit-learning; §13 obligation)
- М3 (compaction-survival): `architecture/M3-compaction-survival.md` (esp. §6 body sections; §7.2 Echo contract; §8 non-resumable-actions)
- М4 (/implement redesign): `architecture/M4-implement-redesign.md` (esp. §2.1.1 termination mapping; §2.2 invariants; §2.3 budgets; §7.3 fix-loop; §12.1 skill list)
- М5 (/plan redesign): `architecture/M5-plan-redesign.md` (esp. §17 spec.md schema; §18 frontmatter goal-state; §22.4 M6 contract)
- spawn-agent ladder: `skills/_shared/spawn-agent.md`
- context-isolation checklist: `skills/_shared/context-isolation-checklist.md`
- finding-tagging schema: `skills/_shared/finding-tagging.md`
- evidence-standard: `skills/_shared/evidence-standard.md`
- effort-scaling helper: `skills/_shared/effort-scaling.md`
- model-tiering: `skills/_shared/model-tiering.md`
- primary-worktree: `skills/_shared/primary-worktree.md`
- per-finding-question helper: `skills/_shared/per-finding-question.md`
- emit-learning helper: `skills/_shared/emit-learning.md`
- review criteria files: `skills/review/{bugs,security,architecture,tests,optimizations,guidelines,conventions,design,pr-metadata,spec-compliance}-criteria.md`
- review reference files: `skills/review/{incoming-mode,tdd-mode,plan-context}-reference.md`
- /deep-simplify (slated для deletion): `skills/deep-simplify/{SKILL,simplify-criteria}.md`

End of M6.
