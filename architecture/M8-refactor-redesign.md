# M8 — /geniro:refactor Redesign (M4-aligned, zero-behavior-change guarantee preserved)

**Status:** Specification (pre-implementation)
**Master plan:** `/root/.claude/plans/reactive-dreaming-backus.md` — M8 of the M1–M10 redesign. Master plan §120 mandates: "Same" (as M7 — align with `/implement` simplification; reuse M1–M3 conventions). Skill catalog §34 preserves: "Zero-behavior-change restructuring. **Distinct guarantee** from `/implement`."
**Scope:** Redesign of `/geniro:refactor` к mirror M4's three-phase structure (Plan → Apply → Verify), adopt canonical effort-scaling tier rubric (Trivial / Small / Medium / Big), drop the orphaned Phase 6 TDD post-GREEN chain, и migrate state files к M1 canonical schema. Preserves all refactor-specific safety constraints (zero behavior change, refactor-agent + relevance-filter + reviewer spawn contracts, hard escalation signals routing к /implement).
**Depends on:** M1 (state-files — `atomic_state_write`, T1 layout, `approvals[]` P-M1-1); M2 (memory — `query-learnings` Phase 1, `emit-learning` Phase 3 — `discovery` + `pitfall` types per M2 §5.3); M3 (compaction-survival — `## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason`, Block 5d `approvals[]` render); M4 (mirrored phase structure §2.1, 7 invariants §2.2, quality-first budgets §2.3, escalation AUQ pattern §7.4, ACI surface §13.5); effort-scaling.md (canonical tier classifier adopted per design Q2).
**Follows:** M7 (/debug)
**Followed by:** M9 (/onboard + /investigate), M10 (operational skills).

---

## 1. Purpose

The pre-M8 `/geniro:refactor` (510-line `SKILL.md`) ships а 5-phase pipeline (Scope → Analyze+Plan → Approval → Execute → Review) с an optional **Phase 6 TDD post-GREEN chain** invoked only when upstream skills' TDD lane fires. Three structural concerns motivate the redesign:

1. **Phase-count drift vs. М4 simplification mandate.** Master plan §120 says "Same as M7" — align с /implement simplification. /implement (M4) collapsed к 3 canonical phases; /debug (M7) followed; /refactor's 5+1 phase structure breaks the convention.

2. **Refactor-local tier rubric vs. canonical effort-scaling.** Pre-M8 /refactor explicitly opts out of the canonical effort-scaling tier classifier с 3 tiers (Small/Medium/Large) и а 5-dim score over different dimensions than the canonical. Per design Q2, M8 adopts the canonical 4-tier (Trivial/Small/Medium/Big) effort-scaling rubric — while preserving refactor-specific hard escalation signals that force escalation OUT of /refactor entirely (e.g. "behavioral change required" → use /implement).

3. **Orphaned TDD post-GREEN chain (Phase 6).** Master plan §66 deleted /follow-up и М4 §3.1 removed TDD lane mode entirely; Phase 6's two upstream callers no longer exist. Per design Q3, M8 drops Phase 6 entirely.

M8 produces: 3 phases (Plan / Apply / Verify) mirroring M4. State files migrate к M1 canonical schema. The refactor-agent + relevance-filter + reviewer-agent spawn contract is preserved verbatim — these are the workhorses of the skill и were independently audited as sound (М6 borrows the same reviewer-agent contract; М4 borrows the same fix-loop pattern). The zero-behavior-change guarantee (master plan §34 "Distinct guarantee") is preserved as the constitutional rule.

---

## 2. Architecture overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  /geniro:refactor $ARGUMENTS                                                 │
└─────────────────────────────┬────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  Phase 1 — Plan (DECIDED — §6)          │
        │  • Load L4 / L3 / L2                    │
        │  • Scope discovery (Read + Grep)        │
        │  • Baseline validation (project suite)  │
        │  • Test-first gate (behavior-adjacent)  │
        │  • Tier classification — canonical      │
        │    effort-scaling (§6.3)                │
        │  • Refactor-specific hard signals       │
        │    (orthogonal — escalate OUT)          │
        │  • Smell detection (refactor-agent      │
        │    evidence-only, Medium+)              │
        │  • Relevance-filter dossier             │
        │    (Medium+) → orchestrator KEEP/FILTER │
        │  • Plan build + risk classify           │
        │  • Approval AUQ (HIGH steps)            │
        │  • State.md `phase: plan`               │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 2 — Apply (DECIDED — §7)         │
        │  • L4 refresh                           │
        │  • refactor-agent executes plan         │
        │    (model: opus if max_risk=HIGH,       │
        │     else sonnet)                        │
        │  • Per-step validation (test_cmd        │
        │     pre/post; agent's Step Execution    │
        │     Protocol)                           │
        │  • Blocked-step protocol (max 3 retries │
        │     per step, then mark BLOCKED         │
        │     and continue)                       │
        │  • Session-level cap: ≥30% blocked →    │
        │    escalation AUQ (§7.3)                │
        │  • Final regression run + Evidence Block│
        │  • State.md `phase: apply`              │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 3 — Verify (DECIDED — §8)        │
        │  • Diff sanity (all tiers)              │
        │  • Independent reviewer-agent (Medium+) │
        │  • Custom reviewers (Medium+)           │
        │  • Orchestrator disposition:            │
        │    PRODUCT-DECISION → ESCALATE (AUQ)    │
        │      with P-M1-1 approvals[] persist    │
        │    CRITICAL/HIGH non-PD → fix loop      │
        │      (max 1 round)                      │
        │    MEDIUM → note in summary             │
        │  • Completion summary                   │
        │  • L2 auto-emit (discovery + pitfall    │
        │    per M2 §5.3) + L4 promotion          │
        │    suggestion (P-M4-5 mirror)           │
        │  • Suggest improvements (M2 §5.4 routes)│
        │  • Cleanup (2 legacy generations)       │
        │  • State.md `phase: verify` → done      │
        └─────────────────────────────────────────┘
```

### 2.1 State machine

Phase enum (state.md `phase:` field) и transitions:

```
[entry]
  └── plan ──┬── apply ──┬── verify ──┬── done
             │           │             │
             │           │             └── verify-summary-only (terminal — "Document and ship as-is" path on PRODUCT-DECISION)
             │           │
             │           └── apply-escalated ──┬── verify (user picks "keep what worked" → flows к Phase 3 с partial-application note)
             │                                 ├── reverted (terminal — user picks "Revert all changes")
             │                                 └── aborted (terminal — user picks "Force-continue (not recommended)" rejected; OR user picks "abort")
             │
             └── plan-escalated ──┬── plan (user supplies missing context → resume plan loop)
                                  ├── aborted (terminal — user picks "abort")
                                  └── routed (terminal — hard signal triggered "Escalate to suggested skill" pick)

      verify ──┬── (happy: flows к done above)
               │
               └── verify-escalated ──┬── apply (user picks "Run /implement on this finding" for PRODUCT-DECISION → М8 exits, /implement consumes the finding-specific T2 handoff — out of refactor scope after pick)
                                      ├── reverted (terminal — user picks "Revert this refactor and start over")
                                      ├── done (user picks "Document and ship as-is" → flows к done с deferred-decision note in summary)
                                      └── adr-documented (terminal — user picks "Document as ADR")
```

**Terminal states:** `done`, `verify-summary-only`, `reverted`, `aborted`, `routed`, `adr-documented`. M3 SessionStart recovery treats all six as "task complete — no resume needed".

**Non-terminal states:** `plan`, `apply`, `verify`. M3 recovery rolls these back к their phase-entry point и re-runs (idempotent re-entry per §6, §7.1, §8.1).

**Escalation states:** `plan-escalated` (hard signal triggered + tier-routing AUQ; OR baseline validation red + AUQ), `apply-escalated` (≥30% blocked steps), `verify-escalated` (PRODUCT-DECISION finding). M3 surfaces к user as "task was paused — last AUQ options:" so user re-picks без losing context.

### 2.1.1 Termination case → state mapping

Per master plan P-M4-2 (8 canonical termination conditions), M8 mapping:

| # | Termination case | Terminal state | `## Termination reason` body line |
|---|---|---|---|
| 1 | Final answer produced (happy refactor done) | `done` | (omitted — happy path) |
| 2 | Done condition satisfied (modifier exit — e.g. ADR documented, summary-only) | `adr-documented` / `verify-summary-only` | (omitted — modifier-driven) |
| 3 | User approval required | non-terminal `*-escalated`, then terminal via user pick | — |
| 4 | Blocker needs user input | non-terminal `*-escalated` | — |
| 5 | Budget reached | N/A baseline (§2.3 quality-first) | (reserved для cost-aware mode post-P-X6) |
| 6 | Repeated failure threshold exceeded | `aborted` (via §7.3 ≥30% blocked AUQ "abort"); `reverted` (via §7.3 "Revert" or §8.3 disposition "Revert") | `repeated-failure: <blocked-steps-ratio>` OR `revert: <reason>` |
| 7 | Safety policy denial (hook-block, dangerous-action veto) | `aborted` | `safety-denied: <hook-or-rule-name>` |
| 8 | Tool unavailability without fallback | `aborted` | `tool-unavailable: <tool-name>` |

**`## Termination reason` body convention:** On аборт, append one-line entry к state.md body. Mirrors M4 §2.1.1 contract.

### 2.2 Loop invariants

The 7 invariants from M4 §2.2 apply throughout M8's three phases без modification. Reference M4 §2.2 verbatim; do not duplicate. Three M8-specific notes:

1. **Invariant #4 (bounded structured tool results)** applies к the refactor-agent's structured execution report (per-step status, blocked-step reasons) — capped at ~8K chars; longer truncated с marker.
2. **Invariant #5 (escalation gates, not silent abort)** applies к two M8-specific gates: §7.3 ≥30% blocked AUQ (Phase 2 cap), §8.3 PRODUCT-DECISION escalation (Phase 3 always-WAIT).
3. **Invariant #7 (errors → structured observations)** — refactor-agent's per-step blocked rationale, baseline validation failure output, и reviewer-agent CRITICAL findings all become structured `## Tool log` или `## Errors` entries.

**Side-effect — `## Tool log` section в state.md (selective logging):** M8 logs **subagent-spawn outcomes** (refactor-agent Phase 1 evidence-only spawn, relevance-filter spawn, refactor-agent Phase 2 execution spawn, reviewer-agent + custom reviewer spawns), **escalation entries** (§6.6 plan-escalation, §7.3 apply-escalation, §8.3 verify-escalation), и **side-effect tool calls** (none in baseline M8 — refactor never ships code; the diff stays uncommitted). Routine Read / Edit / Bash skipped per M4 contract.

### 2.3 Budgets — quality-first framing

M8 has **NO hard kill caps**. All limits are **escalation gates that surface к user**. Per P-X5 design guidance (master plan §405): per-skill milestones authored after M4 must mirror M4 §2.3 framing.

**Quality gates (escalate к user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Per-step retry в refactor-agent | 3 | §7.2 (agent-internal) | Mark BLOCKED, continue к next step (preserves pre-M8 contract). |
| Session-level blocked ratio | 30% (post-rejection denominator) | §7.3 | AUQ — keep what worked & escalate / revert / force-continue. **User picks.** |
| Phase 3 fix-loop | 1 round | §8.3 | Re-spawn reviewer once on findings; if still failing, surface к user via §8.3 disposition AUQ (escalate / accept / abort). |
| Reviewer output size | ~4K chars per dim | §2.2 invariant #4 | Truncation с marker. |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| Parallel reviewer spawns | 1 (independent reviewer) + N custom reviewers (`load-custom-reviewers.md` derives count from `.geniro/instructions/review-extra/`) | §8.2 |
| Smell-detection rounds | 1 (refactor-agent evidence-only spawn) | §6.4 |
| Relevance-filter rounds | 1 (Medium+ only) | §6.5 |

**Claude Code internals (not under M8 control):**
- Input tokens ≤200K per turn → triggers compaction (M3 hook handles resume).
- Output tokens ≤8K per turn → soft truncation.

**Explicitly NOT capped:**
- **Wall-time per run.** Large refactors (15+ files, Big tier) may legitimately take hours.
- **Total tool calls per phase.** Many Read/Grep calls in Phase 1 scope discovery are expected.
- **Total model turns per phase.** Iterative test re-runs during refactor-agent execution add turns.
- **Total cost per run.** Deferred к P-X6.

**Rationale.** Same two-class taxonomy as M4 §2.3: Class-A (hard kill caps — would abort legitimate complex refactor mid-stride; M8 has zero) vs Class-B (escalation gates — protect quality by preventing pointless blocked-step spinning; M8 keeps four).

---

## 3. Scope deltas vs. pre-M8 `/geniro:refactor`

### 3.1 Removed

| Component | Reason | Replacement |
|---|---|---|
| 5-phase numbering (Scope / Analyze+Plan / Approval / Execute / Review) | Master plan §120 "Same as M7" — align с M4 simplification | 3 phases (Plan / Apply / Verify) per §2 |
| Phase 6 TDD post-GREEN chain | Orphaned (M4 §3.1 removed TDD lane; master plan §66 deleted /follow-up) | Dropped entirely per design Q3 |
| Refactor-local tier rubric (Small / Medium / Large + 5-dim score over Task type / Cross-boundary / Public surface / Scale / Test coverage) | Per design Q2 — adopt canonical effort-scaling for cross-skill consistency | Canonical effort-scaling (Trivial / Small / Medium / Big + 5-dim score) per §6.3 |
| Stale `/geniro:decompose` reference (Large tier → recommend /decompose) | Master plan §65 deleted /decompose | Replace с `/geniro:plan` (M5) recommendation для Big tier per §6.3 |
| Stale `/geniro:follow-up` reference (Phase 5 endpoint message) | Master plan §66 deleted /follow-up | Replace с `/geniro:implement` recommendation per §8.4 |
| Stale `/geniro:deep-simplify` reference ("When NOT to use" — optimize performance) | Master plan §67 absorbed как /review --simplify flag | Replace с `/geniro:review --simplify` per §1 "When NOT к use" |
| Pre-M8 state-file custom header (`Branch:/Worktree:/Timestamp:` capitalized lines, no YAML frontmatter) | Non-M1-conformant | M1 §T1 frontmatter base + M8 extensions per §9.1 |

### 3.2 Kept (with adaptation)

| Component | Notes |
|---|---|
| Zero-behavior-change guarantee | Constitutional — master plan §34 "Distinct guarantee" preserved verbatim. References throughout M8 doc и SKILL.md. |
| Refactor-specific hard escalation signals | Preserved (4 signals — see §6.3.2). Trigger escalation OUT of /refactor entirely (route к /implement или другим skills). Orthogonal к the effort-scaling tier classifier. |
| Phase 1 baseline validation + test-first gate | Preserved verbatim. Folded into Phase 1 §6.2. |
| Phase 2 refactor-agent evidence-only spawn (smell detect + consumer count + Existing Abstraction Audit) | Preserved verbatim. Folded into Phase 1 §6.4. |
| Phase 3 relevance-filter-agent dossier + orchestrator KEEP/FILTER tagging | **Subagent-rationalization update:** dossier-spawn removed; orchestrator-inline smell evidence + KEEP/FILTER runs entirely в §6.5. |
| Phase 4 refactor-agent execution + per-step protocol + blocked-step contract + ≥30% session cap | Preserved verbatim. Folded into Phase 2 §7. |
| Phase 5 reviewer-agent + custom reviewers + orchestrator disposition (PRODUCT-DECISION escalation / CRITICAL-HIGH fix loop / MEDIUM note) | Preserved verbatim. Folded into Phase 3 §8. P-M1-1 `approvals[]` persistence added к PRODUCT-DECISION gate. |
| Refactor-agent model tiering (opus when max_risk=HIGH, else sonnet) | Preserved verbatim. References `_shared/model-tiering.md`. |
| Existing Abstraction Audit pre-spawn step | Preserved verbatim. Folded into Phase 1 §6.4 refactor-agent spawn prompt. |
| Compaction recovery via M3 SessionStart hook | Mandated through state.md schema (M1 §T1 frontmatter + M3 body sections); pre-M8 strategic compact points after Phase 2 + Phase 4 are no longer needed as separate annotations (М3 hook covers all phase boundaries). |

### 3.3 Replaced

| Pre-M8 element | M8 replacement |
|---|---|
| 5-dim refactor-local score (Task type / Cross-boundary / Public surface / Scale / Test coverage) | Canonical effort-scaling 5-dim score (Task type / Cross-boundary / Reversibility / Edit scatter / Pattern availability) per §6.3 |
| Tier behavior "Small skip relevance-filter и reviewer-agent" | Equivalent под Trivial + Small skip both; Medium full pipeline; Big recommend `/geniro:plan` first |
| "Refresh custom instructions" в Phase 4 + Phase 5 (double-refresh) | Single Phase 2 entry refresh (mirror M4 §13.4) — Phase 3 inherits the Phase 2 refresh (no extra reads in /verify phase since no code-writing). |
| Pre-M8 SKILL.md Phase 6 TDD post-GREEN spawn template | Removed. If а future use case re-emerges (e.g., post-/implement TDD-cycle hook), it lives in /implement (M4) own scope, not /refactor. |
| Anti-rationalization table (14 rows) | Extended к §14 — preserves 14 rows verbatim + adds cross-cutting LLM rows (kill caps, silent abort, hook bypass, auto-promote) per P-MP-1 framing. |
| Step 8 "Suggest Improvements" routing | §8.6 — canonical M2 §5.4 L4 routes table. |

---

## 4. Decisions recorded so far

| ID | Decision | Section |
|---|---|---|
| **Q1** | **3 phases (M4 mirror)** — Plan → Apply → Verify | §2, §6, §7, §8 |
| **Q2** | **Adopt canonical effort-scaling (Trivial / Small / Medium / Big)** — drop refactor-local tier rubric | §6.3 |
| **Q3** | **Drop Phase 6 TDD post-GREEN chain entirely** — orphaned by /follow-up deletion + TDD lane removal | §3.1 |
| **D1-fix** | M1 §T1 frontmatter base + M8 extensions for state.md | §9.1 |
| **D2-fix** | Subdir-per-slug state layout (`.geniro/state/refactor/<slug>/state.md`) | §9.1 |
| **D3-fix** | M3 body sections (`## Tool log` / `## Errors` / `## Open Questions` / `## Termination reason` / `## Persisted approvals`) обязательны в state.md | §9 |
| **D4-fix** | Reference M4 §2.2 7 invariants verbatim (no duplication) | §2.2 |
| **D5-fix** | P-X5 quality-first budget section mirror of M4 §2.3 | §2.3 |
| **D6-fix** | P-MP-1 anti-rationalization framing + cross-cutting LLM rows | §14 |
| **D7-fix** | Replace `/geniro:decompose` recommendation с `/geniro:plan` (Big tier routing) | §6.3.3 |
| **D8-fix** | Replace `/geniro:follow-up` recommendation с `/geniro:implement` (Phase 3 endpoint message) | §8.4 |
| **D9-fix** | Replace `/geniro:deep-simplify` reference с `/geniro:review --simplify` ("When NOT к use") | §3.1 |
| **D10-fix** | Drop Phase 6 TDD chain — design Q3 | §3.1 |
| **D11-fix** | NO `from-refactor-<branch>.md` T2 handoff в baseline M8 — diff IS the deliverable; working tree is the channel. М1 §T2 row unchanged. | §9 |
| **D12-fix** | L2 emit types explicit к M2 §5.3: `discovery` (pattern extracted к shared utility/component) + `pitfall` (footgun discovered during refactor) | §8.5, §10.2 |
| **D13-fix** | 3-phase numbering (master plan §120 "Same") | §6/§7/§8 |
| **D14-fix** | Phase 3.6 "Suggest improvements" follows M2 §5.4 L4 routes | §8.6 |
| **D15-fix** | PRODUCT-DECISION escalation gate persists outcome к `approvals[]` (P-M1-1) when user picks а durable resolution | §8.3 |
| **OQ-M8-1** | M2 §13 memory-I/O obligation — §10 | §10 |
| **OQ-M8-2** | ACI per-phase tool surface | §10.5 |

---

## 5. Defect inventory (audit 2026-05-18 — before/after)

15 defects identified в pre-M8 audit. Each closed by the section listed.

| ID | Defect | Pre-M8 location | M8 closure |
|---|---|---|---|
| **D1** | state file non-M1-conformant (custom header, no YAML frontmatter) | `SKILL.md:100-114` | §9.1 — full M1 §T1 frontmatter base + M8 extensions |
| **D2** | Flat state-file path `.geniro/state/refactor/state-<slug>.md` (not subdir-per-slug) | `SKILL.md:98` | §9.1 — migrate к `.geniro/state/refactor/<slug>/state.md` (subdir-per-slug, matches M4/M5/M7 layout) |
| **D3** | No M3 body sections | throughout | §9.2 — Tool log / Errors / Open Questions / Termination reason / Persisted approvals |
| **D4** | No 7 loop invariant reference | throughout | §2.2 — references M4 §2.2 |
| **D5** | No quality-first budget section | throughout | §2.3 — full M4 §2.3 mirror |
| **D6** | Anti-rationalization без P-MP-1 framing + missing cross-cutting LLM rows | `SKILL.md:430-447` | §14 — preserves 14 rows + adds cross-cutting (kill caps, silent abort, hook bypass, auto-promote) |
| **D7** | `/geniro:decompose` reference (deleted master plan §65) | `SKILL.md:78` | §6.3.3 — replace с `/geniro:plan` recommendation |
| **D8** | `/geniro:follow-up` reference (deleted master plan §66) | `SKILL.md:385` | §8.4 — replace с `/geniro:implement` recommendation |
| **D9** | `/geniro:deep-simplify` reference (deleted master plan §67) | `SKILL.md:25` | §3.1 — replace с `/geniro:review --simplify` |
| **D10** | Phase 6 TDD post-GREEN chain references TDD lane (removed M4 §3.1) | `SKILL.md:389-424` | §3.1 — drop entirely per design Q3 |
| **D11** | No M1 §T2 row для refactor handoff | (M1:46-49 — intentionally absent) | §9 — explicit "no T2 handoff" decision (D11-fix): diff IS the deliverable |
| **D12** | L2 emit not explicit к М2 §5.3 (`discovery` + `pitfall`) | `SKILL.md:455-463` | §8.5 + §10.2 — explicit М2 §5.3 alignment |
| **D13** | 5+1 phase numbering vs master plan §120 "Same" | `SKILL.md:127-424` | §6/§7/§8 — 3-phase collapse |
| **D14** | "Suggest Improvements" Step 8 routes без М2 §5.4 canonical table | `SKILL.md:465-467` | §8.6 — canonical М2 §5.4 routing |
| **D15** | PRODUCT-DECISION escalation gate не P-M1-1 approvals[]-aware | `SKILL.md:341` | §8.3 — persist user pick to `approvals[]` when durable resolution; render via М3 §6 Block 5d on resume |

---

## 6. Phase 1 — Plan — **DECIDED**

State.md `phase: plan`. Light по cost vs Phase 2 — а scope-discovery batch (Read + Grep) + 1 baseline validation run + 1 refactor-agent spawn (Medium+) + 1 relevance-filter spawn (Medium+) + orchestrator plan-build. Critical для correctness: bad plan → bad refactor (and refactor preserves the diff в working tree even on failure, so а wrong-direction plan wastes hours of un-reviewed code).

Exits к Phase 2 only when: (a) baseline validation green, (b) tier classified, (c) hard signals checked, (d) smells identified (Medium+) + relevance-filtered (Medium+), (e) plan built и approved (HIGH-risk steps gated).

### 6.1 Load custom instructions + L3/L2

On Phase 1 entry:

1. **L4 refresh** — `load-custom-instructions(MODE: refresh, scope: refactor + global + code-style)` per M3 §7.2 Echo contract.
2. **L3 refresh** — `load-semantic(MODE: refresh, top-2 default)` — `_project.md` + `_CODEBASE_MAP.md`. Fingerprint drift check fires if applicable.
3. **L2 prior-knowledge query** — `query-learnings(tags=<inferred from $ARGUMENTS>, scope=task path)` per M2 §5.3. К find prior discoveries about coupling, pitfalls, и conventions relevant к the refactor scope.
4. **Cross-layer conflict resolution** — `resolve-conflicts(L2/L3/L4 loaded)` per M2 §10.

Echo lines per M3 §7.2 mandatory.

### 6.2 Scope discovery + baseline + Test-first gate

1. **Parse `$ARGUMENTS`** к understand what is being refactored и why.
2. **Use Grep + Glob** к find all related files. Read all files в scope к understand current organization, dependencies, imports, и test coverage.
3. **Prior-planning context (preserved from pre-M8):** check `.geniro/planning/*/` (task-local), `.geniro/workflow/*.md`, `<PRIMARY_ROOT>/.geniro/knowledge/learnings.jsonl` (grep for scope-file keywords), git state (`git rev-parse --show-toplevel`, `git branch --show-current`, `git log --oneline -5`, `git status --short`).
4. **Read project convention files** referenced в CLAUDE.md.
5. **Baseline validation** — run the project's validation suite once (read command from CLAUDE.md). Capture as an Evidence Block per `skills/_shared/evidence-standard.md`. Outcomes:
   - **Red:** AUQ "Baseline" — "Fix the broken tests first (stop refactoring)" / "Proceed anyway — existing failures are out of scope (risky)". Default: stop. State.md → `phase: plan-escalated`.
   - **No tests exist:** escalate immediately — "Cannot refactor safely без tests. Use `/geniro:implement` to add coverage first." State.md → `phase: routed` (terminal).
   - **Green:** record passing-state fingerprint (test count) in state.md `## Baseline` body section; proceed.
6. **Test-First Gate (behavior-adjacent coverage check)** — before any refactor edit, check whether each function/symbol in scope has at least one test exercising it. If а behavior-adjacent test-coverage gap is detected, fire `skills/_shared/test-first-gate.md` — author RED before refactor edit. Если every scope-symbol already has coverage, skip silently.

### 6.3 Tier classification (canonical effort-scaling — Q2 closure)

**Adopt canonical effort-scaling.md rubric.** /refactor no longer overrides the canonical (per design Q2). Apply effort-scaling Step 1 (hard escalation signals) → Step 2 (5-dim score) → Step 3 (tier behavior). Refactor-specific hard signals (next subsection) apply orthogonally — they escalate OUT of /refactor entirely.

#### 6.3.1 Apply canonical effort-scaling

1. **Step 1 (canonical 9 hard signals from effort-scaling.md L11-25):** new entity/table/migration, new API endpoint/route, auth/permissions/role changes, new module/subsystem, 3+ modules coordinated, OCP violation, new async/queue/background, new external integration/env vars, ambiguous intent. Any present → **Big tier**, skip к Step 3.
2. **Step 2 (canonical 5-dim score 0-10 from effort-scaling.md L31-39):** Task type / Cross-boundary scope / Reversibility / Edit scatter / Pattern availability. Score sum:
   - **0** → Trivial (must ALSO be 1-2 files, single module, unambiguous intent — otherwise round up к Small)
   - **1-3** → Small
   - **4-6** → Medium
   - **7+** → Big
3. **Step 3 (refactor-specific tier behavior — replaces effort-scaling planning-depth column для refactor context):**

| Tier | Refactor behavior |
|---|---|
| **Trivial** | 1-2 files, mechanical (rename, single extract). Skip smell-detection refactor-agent (Phase 1 §6.4). Skip relevance-filter (Phase 1 §6.5). Skip independent reviewer + custom reviewers (Phase 3 §8.2). Orchestrator authors the plan directly от $ARGUMENTS + scope-files Read; goes straight к Phase 2 execution. |
| **Small** | Full smell-detection in Phase 1 §6.4 BUT skip relevance-filter (scope too narrow к matter). Skip independent reviewer + custom reviewers Phase 3 §8.2. |
| **Medium** | Full pipeline as specified — refactor-agent smell-detect + relevance-filter dossier + reviewer-agent + custom reviewers. |
| **Big** | Recommend running `/geniro:plan` first (D7-fix) к split the refactor into independently shippable milestones; refactor then runs one milestone at а time against an approved spec.md. If user wants к proceed без planning, require explicit confirmation via `AskUserQuestion` header "Scope": "Run /geniro:plan first" / "Proceed без а plan (risky)". On "Proceed без а plan", Big runs the Medium pipeline. The only difference is user has accepted the added risk of proceeding без architectural review. |

#### 6.3.2 Refactor-specific hard escalation signals (escalate OUT — orthogonal к effort-scaling)

These 4 refactor-specific signals are orthogonal к the canonical effort-scaling tier. Any present → escalation AUQ "Scope" — "Escalate to suggested skill" / "Proceed anyway (treat as Big)" / "Reduce scope". Default: Escalate.

| Signal | Routing target |
|---|---|
| Behavioral change required | `/geniro:implement` |
| New tests required к cover untested code | `/geniro:implement` |
| Test assertions touched (not just imports) | Not refactoring — `/geniro:implement` |
| Auth, crypto, or payment code touched | Escalate (owner review required) — surface к user, не auto-route |

(Pre-M8's 7 signals collapse here: "Signature/semantics change on public API" subsumed by canonical effort-scaling "New API endpoint or new page/route" (hard signal). "Ambiguous intent" subsumed by canonical hard signal "Ambiguous intent". "Config/migration regeneration needed" subsumed by canonical "New entity, table, or migration".)

### 6.4 Smell detection (refactor-agent evidence-only — Medium+)

Skipped для Trivial и Small per §6.3.1 Step 3 (Small может choose к include this — see Small row).

Spawn а refactor-agent to detect smells и count consumers — evidence only. The orchestrator then classifies risk, orders the plan, и marks HIGH-risk steps for user confirmation.

Preserves pre-M8 spawn contract verbatim (SKILL.md:151-183) including:
- WHAT TO REFACTOR / FILES IN SCOPE / WORKTREE / BRANCH / PROJECT CONVENTIONS slots
- PHASE: EVIDENCE GATHERING ONLY directive
- Skip Write/Edit during this invocation
- Run 6 smell categories (duplication, long methods, god classes, dead code, tight coupling, type/import issues) + Deepening Opportunities lens
- For every detected smell, run the canonical Existing Abstraction Audit at `skills/_shared/existing-abstraction-audit.md`
- Output: flat list of smells с file:line / proposed transformation / consumer count / files affected
- Public surface notes treated as HIGH risk by orchestrator regardless of consumer count
- Anchor: stay within WORKTREE on BRANCH (`pwd && git branch --show-current` verification)

Spawn invocation per `skills/_shared/spawn-agent.md` (degradation ladder) + `skills/_shared/context-isolation-checklist.md` (6 fields pre-inlined).

### 6.5 Relevance-filter dossier (Medium+) → orchestrator KEEP/FILTER

Skipped для Trivial и Small. **Orchestrator-side smell evidence + KEEP/FILTER** runs inline — no subagent spawn (subagent rationalization). Orchestrator weighs convention alignment + over-engineering + intentional-pattern signals against detected smells per the synthesis matrix in `${CLAUDE_PLUGIN_ROOT}/skills/refactor/SKILL.md` §1.5.

Spawn contract preserved verbatim:
- FINDINGS / CHANGED FILES / WORKTREE / BRANCH / PROJECT CONTEXT / CONVENTION FILES slots
- 3 evidence dimensions: convention alignment / over-engineering / intentional pattern
- Return evidence dossier per smell (ALIGNS/CONTRADICTS/NEUTRAL × APPROPRIATE/OVER-ENGINEERED × ISOLATED/WIDESPREAD)
- Do NOT tag KEEP/FILTER — orchestrator decides

After dossier returns, orchestrator synthesizes: для each smell, weigh evidence и tag KEEP or FILTER. Remove FILTERED smells from plan before presenting к user; note в summary. If agent fails, pass all smells through as KEEP (fail-open per pre-M8).

### 6.6 Risk classification + plan build + approval AUQ

Orchestrator builds the plan from refactor-agent output (Medium+) or directly from scope-files (Trivial/Small):

1. **Classify risk per smell** (lookup rule, preserves pre-M8 SKILL.md:187-191):
   - 1-3 consumers → LOW
   - 4-9 consumers → MEDIUM
   - 10+ consumers → HIGH
   - Public API / module export / shared type change → HIGH (overrides consumer count)
2. **Order the plan**: safer transformations first (LOW → MEDIUM → HIGH). Within the same tier, group by file к minimize re-reads.
3. **Mark HIGH-risk steps for user confirmation** (presented via `AskUserQuestion` next step).
4. **Build the final plan** с: smells, ordered steps, risk per step, consumer counts, files that will change, what will NOT change (public APIs, DB schema, test behavior), `max_risk` (max across all step risks — used к select execution model in Phase 2).

**Approval gate (Always-WAIT, P-M1-1-aware):** If any steps are **HIGH risk**, present them к user via `AskUserQuestion` header "Approve HIGH-risk steps" и wait для confirmation. Each step rendered с: file path / proposed transformation / consumer count / risk classification / rationale.

**Approvals-persistence (P-M1-1):** before firing, check state.md frontmatter `approvals[]` for prior entries с `category: refactor_high_step` matching the current step. Use prior `picked` if found. On user pick, append entries к `approvals[]` via M1 `atomic_state_write`. М3 §6 Block 5d renders на resume.

If all steps are LOW/MEDIUM: present the plan summary в chat и proceed (no AUQ).

State.md transitions: `plan` → `apply` once approval complete. State.md updates: `## Plan` body section с the full plan (ordered steps + risk classifications + KEEP/FILTER decisions). `## Persisted approvals` rendered from frontmatter `approvals[]`.

---

## 7. Phase 2 — Apply — **DECIDED**

State.md `phase: apply`. Refactor-agent executes the approved plan, one step at а time, с per-step validation. The constitutional rule (zero behavior change) is enforced via the per-step regression test pass.

### 7.1 L4 refresh entry

On Phase 2 entry, single `load-custom-instructions(MODE: refresh, scope: refactor + global + code-style)` call. Mirrors M4 §13.4 Phase 3 entry contract: always re-fires, drops the conditional-on-marker pattern. Cost: 1 helper read.

Pre-M8 had TWO refreshes (Phase 4 + Phase 5 entries). M8 collapses к one — Phase 3 (Verify) inherits the Phase 2 refresh since Phase 3 has no code-writing.

### 7.2 refactor-agent execution

Spawn the refactor-agent к execute the approved plan. Model tier per `model-tiering.md`: `opus` if `plan.max_risk == "HIGH"`, else `sonnet` (preserves pre-M8 SKILL.md:238).

Pre-spawn step: use the content the §6.1 / §7.1 loader echoed as `Loaded code-style.md …` (cwd OR primary-worktree fallback per `load-custom-instructions.md`). Pre-inline content into agent prompt под `## Code-style instructions`. Omit when loader echoed `No code-style.md found — skipping.`

Spawn template preserves pre-M8 SKILL.md:242-272 verbatim:
- APPROVED PLAN slot
- WORKTREE / BRANCH slots
- PER-STEP TEST COMMAND / REGRESSION TEST COMMAND / AUTOFIX COMMAND / BACKPRESSURE slots
- CRITICAL RULES: one logical transformation per step, run validation after each step, max 3 retries per step then mark BLOCKED + continue, no git operations
- Return а structured report (applied / blocked / final validation status)
- Anchor verification

Spawn via `skills/_shared/spawn-agent.md` degradation ladder + `skills/_shared/context-isolation-checklist.md` (6 fields pre-inlined).

### 7.3 Session-level cap + escalation AUQ

After execution returns, count BLOCKED-к-executed ratio (post-user-rejection denominator: approved plan steps minus user-rejected HIGH-risk steps). **If ≥30% BLOCKED:** stop и escalate via `AskUserQuestion` header "Stuck":

- **Keep what worked и escalate the rest** — proceed к Phase 3 с blocked-steps list noted; user runs `/geniro:implement` separately for blocked items. State.md → `phase: verify` (continue) с `## Accepted Blocks` body section.
- **Revert all changes** — `git checkout -- .` (with user confirmation per §8.1). State.md → `phase: reverted` (terminal).
- **Force-continue (not recommended)** — proceed к Phase 3 с the blocked work treated as accepted. State.md → `phase: verify` (continue).

Do NOT proceed к Phase 3 automatically when this cap triggers. State.md marks `phase: apply-escalated` с timestamp + blocked-ratio + blocked-steps list before AUQ; transitions per user pick. М3 §6 Block 5c renders open question on resume.

### 7.4 Final regression run + Evidence Block

After execution returns (or after user pick if §7.3 fired), run the full test suite once (regression gate) и attach the captured run as an Evidence Block per `skills/_shared/evidence-standard.md`. Reasoning-from-the-diff is forbidden — the captured run is the only proof the zero-behavior-change invariant held.

If regression failed: fire AUQ "Regression" — "Revert all changes" / "Show me the diff first" / "Keep changes для debugging". Default: Revert (safe-default preserves pre-M8 SKILL.md:291-296). On "Revert", `git checkout -- .` after explicit user confirmation. State.md → `phase: reverted` (terminal).

If green: state.md transitions к `phase: verify`. `## Apply Summary` body section captures executed / blocked / final-suite status.

---

## 8. Phase 3 — Verify — **DECIDED**

State.md `phase: verify`. Diff sanity + independent review + completion summary + L2 emit + cleanup. No `git push` / `gh pr create` — refactor never ships code, only produces а working-tree diff (deliverable) и а state-file audit trail.

### 8.1 Diff sanity (all tiers)

Run `git diff --name-only` и `git diff --stat`. Cross-check the refactor-agent's self-reported file list (от §7.2 structured report) against the actual diff — flag mismatches.

If §7.4 final regression failed AND user picked "Revert all changes", state.md is already `phase: reverted` — skip к §8.7 cleanup (no review needed).

### 8.2 Independent reviewer-agent + custom reviewers (Medium+)

Skipped для Trivial и Small (preserves pre-M8 SKILL.md:298 — "Medium and Large only — skip for Small"). For Trivial: no review whatsoever (the diff is small enough that diff sanity + completion summary suffices). For Small: skip the independent reviewer + custom reviewers per Q2 tier behavior.

For Medium и Big: spawn а fresh reviewer-agent. The agent reads its own criteria — do NOT pre-read into orchestrator context.

Pre-inline content the loader echoed (§7.1 refresh): `code-style.md` content под `## Code-style instructions` (cwd OR primary-worktree fallback). Omit when loader echoed `No code-style.md found — skipping.`

Spawn template preserves pre-M8 SKILL.md:307-338:
- WORKTREE / BRANCH slots
- DIFF / AGENT SELF-REPORT / PROJECT CONVENTIONS slots
- Focus Areas (5 — preserved verbatim): accidental public-API changes, test-assertion mutations (imports OK, assertions not), invariant drift, new coupling, dead-code removal that had references
- Review Criteria: bugs / architecture / tests (3 dimensions — preserves pre-M8 SKILL.md:330-333)
- Return findings с severity (CRITICAL/HIGH/MEDIUM) и confidence
- Do NOT emit overall verdict
- Anchor verification

**Custom reviewers** (Medium и Big only — same gate as independent reviewer): apply `skills/_shared/load-custom-reviewers.md` к discover user-authored review dimensions в `.geniro/instructions/review-extra/`. For each spawn-spec returned, append one additional `Agent(subagent_type="reviewer-agent", ...)` к the SAME parallel batch as the independent reviewer above (same assistant response, parallel execution, NOT one per turn). Hard-cap error → surface error + skip §8.2; do not proceed с review.

### 8.3 Orchestrator disposition logic

Preserves pre-M8 SKILL.md:340-348 contract verbatim + extends с P-M1-1 `approvals[]` persistence для PRODUCT-DECISION outcomes (D15-fix):

**PRODUCT-DECISION findings → ESCALATE (Always-WAIT, every tier):**

Per pre-M8 SKILL.md:341 — а PRODUCT-DECISION finding implies multiple valid resolution paths, и refactor guarantees zero behavior change. Picking one is а behavior change, contradicting the constitution. Phase 3 ESCALATES PRODUCT-DECISION к /implement; does NOT gate-and-fix в-skill.

Surface every PRODUCT-DECISION finding via `AskUserQuestion` per `skills/_shared/per-finding-question.md` § Single-finding gate (`header: "Escalate"`). 4 fixed options (ADR-eligibility per pre-M8 SKILL.md:343 determines whether 4th option included):

1. **Run /geniro:implement on this finding (Recommended)** — exit /refactor; user runs /implement separately to apply а behavioral fix. State.md → `phase: verify-escalated` then on pick → exit (out-of-skill).
2. **Revert this refactor и start over** — `git checkout -- .` с user confirmation. State.md → `reverted` (terminal).
3. **Document и ship as-is — accept the open decision** — keep the working-tree diff, note the deferred decision in §8.4 completion summary. State.md → `verify-summary-only` (terminal). The user takes the responsibility of resolving the decision later.
4. **(ADR-eligible only)** **Document as ADR** — spawn а focused agent (`model: sonnet`) к draft the ADR per `_shared/improvement-routing.md` § ADR template; write to `docs/adr/NNNN-<slug>.md`. State.md → `adr-documented` (terminal).

ADR-eligibility check preserved verbatim from pre-M8 SKILL.md:343 — include 4th option ONLY when rejection meets all 3 criteria (hard к reverse / surprising без context / result of genuine trade-offs).

**Approvals-persistence (P-M1-1, D15-fix):** before firing the PRODUCT-DECISION AUQ, check state.md frontmatter `approvals[]` for а prior entry с `category: refactor_product_decision` matching the finding (use finding `path:lines` + decision-type as disambiguator). If found, use prior `picked` value (the user already resolved this decision earlier in the run или а prior compaction-recovered state). If not found, fire AUQ → on user pick, append к `approvals[]` via M1 `atomic_state_write` BEFORE executing the chosen action.

Fire one `AskUserQuestion` per PRODUCT-DECISION finding; chain across findings — never batch multiple findings into а single question (preserves pre-M8 contract).

**CRITICAL or HIGH (non-PRODUCT-DECISION) findings → fix loop (max 1 round):**

Spawn fresh refactor-agent к address specific findings, then re-spawn reviewer-agent fresh on the updated diff. After 1 round, если still failing — surface к user via AUQ header "Verify-fix" с options: "Escalate to /implement" / "Document remaining findings и ship as-is" / "Revert all changes". State.md → `verify-escalated` с timestamp + 1-round fix attempt summary.

**MEDIUM findings only → note в completion summary; proceed.**

**No findings → proceed.**

### 8.4 Completion summary

Output the §8.4 markdown block directly в chat. No persistence к а T2 handoff file — diff IS the deliverable (D11-fix decision).

```markdown
## Refactor Complete

### Transformations Applied (N)
- [file:line] — [what changed] — risk: [LOW/MEDIUM/HIGH] — consumers: N

### Blocked Steps (N)
- [file:line] — [what was attempted] — reason: [failure summary]

### Filtered by Relevance (N — omit for Trivial/Small; relevance filter not run)
- [smell] — [reason filtered]

### Review Findings (Medium и Big only — omit для Trivial/Small)
- CRITICAL: N, HIGH: M, MEDIUM: K
- Disposition: [proceeded / 1-round fix loop / escalated / ADR documented]

### Validation
- Tests: PASS/FAIL
- Baseline delta: [before→after test count]

### Files Modified: N
- [file path]: [one-line summary]

### Deferred
- [P3 item or user-rejected HIGH step]

### Next steps
[The diff is in your working tree. Commit it yourself, or run `/geniro:implement` к ship с а review gate.]
```

Endpoint message replaces pre-M8 `/geniro:follow-up` reference с `/geniro:implement` (D8-fix).

### 8.5 L2 auto-emit (M2 §5.3 — discovery + pitfall)

Replaces deleted `/learnings` skill (master plan §69). At Phase 3 exit:

- **`emit-learning` (M2 §5.2)** — called by /refactor for two emit types per M2 §5.3 canonical contract:
  - **`discovery`** — emit когда а pattern was extracted к а shared utility/component (typical /refactor outcome). Required `ext.{area, insight}` per M2 §5.2 typed-extension table. Default trust `verified` per M2 §5.3.
  - **`pitfall`** — emit когда the refactor revealed а footgun (e.g., а seemingly-safe pattern that actually breaks under specific conditions). Required `ext.{trap, mitigation}`. Default trust `verified`.
- **NOT emitted by M8:** `diagnosis` (owned by /debug per M2 §5.3); `convention` (owned by /implement self-review per M2 §5.3); `decision` (owned by /plan).

**L4 promotion suggestion (P-M4-5 mirror — closes feedback loop):** when а `discovery` or `pitfall` entry is emitted, surface а one-line suggestion в Phase 3 final report:

```
[learnings] <Discovery|Pitfall> recorded: "<one-line summary>". Recorded к L2.
  → Consider /geniro:instructions edit <scope>.md к promote as а refactor-rule.
```

Scope hint follows the entry context:
- `discovery` (pattern extracted) → suggest `code-style.md`
- `discovery` (architectural insight) → suggest `global.md`
- `pitfall` (refactor-specific footgun) → suggest `refactor.md`
- Other → generic "appropriate scope"

The line is informational (no AUQ, no auto-edit). User remains source-of-truth для L4 curation. Fully automatic L2→L4 promotion deferred к P-X6.

### 8.6 Suggest improvements (project scope only, M2 §5.4 routes — D14-fix)

After L2 emit, follow the canonical routing в `skills/_shared/improvement-routing.md`. Refactor runs typically surface:

| Insight category | Target | M2 layer |
|---|---|---|
| Undocumented coding conventions / style patterns discovered during refactor | `.claude/rules/<scope>.md` с `paths:` glob frontmatter (Anthropic-native, file-scoped) | L4 procedural |
| Surprising coupling between modules revealed during execution | `.geniro/knowledge/learnings.jsonl` (via `emit-learning` — typically already covered by §8.5 discovery emit) | L2 episodic |
| Patterns that should be auto-enforced | Project rules/hooks (out of plugin scope — point user к project tooling) | — |
| Skill-behavior constraints the user enforced manually during refactor | `.geniro/instructions/refactor.md` or `.geniro/instructions/global.md` | L4 procedural |

Plugin-internal paths (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope — use `/improve-template` (out of M8 design).

### 8.7 Cleanup

After Phase 3 completes:

- **All tiers:** Remove `<PRIMARY_ROOT>/.geniro/state/refactor/<slug>/state.md` for the current branch's slug only, per `skills/_shared/within-skill-state-handoff.md` § Cleanup contract. Useful content already saved (transformations, discoveries) via §8.5 L2 emit + §8.4 chat summary. Do NOT delete sibling slugs from concurrent refactor sessions on other branches.
- **Clear two legacy generations** (best-effort; either may not exist):
  ```bash
  rm -f ".geniro/refactor/state-${slug}.md" 2>/dev/null              # Gen 1: intermediate legacy (pre-state-dir, slug-scoped)
  rm -f ".geniro/refactor/state.md" 2>/dev/null                       # Gen 2: original legacy (pre-slug, non-scoped)
  rm -f ".geniro/state/refactor/state-${slug}.md" 2>/dev/null         # Gen 3: pre-M8 (flat, under state-dir)
  ```
- **No T2 handoff к delete or persist** (D11-fix decision: diff IS the deliverable; working tree is the channel).
- Kill any background processes started during the run (test watchers, profilers).

Cleanup is best-effort — failed commands silently OK.

---

## 9. State file schema

### 9.1 state.md (M1 §T1 base + M8 extensions)

Path: `<PRIMARY_ROOT>/.geniro/state/refactor/<slug>/state.md` (M1 §T1 **session-bound layout** — second canonical path-root per M1 §T1 Path roots table; matches M7's `/debug` layout; **distinct от** M4/M5 task-bound `planning/<task-dir>/` layout — which is correct since /refactor produces no spec/plan artifacts, only transient working state).

#### Frontmatter

```yaml
---
tier: T1                                  # M1 §T1 required
producer: refactor                        # M1 §T1 required
schema-version: 1                         # M1 §T1 required
branch: <git-branch>                      # M1 §T1 required
timestamp: <ISO-8601 UTC>                 # M1 §T1 required
phase: <enum>                             # M1 §T1 required — values per §2.1 state machine
status: <in-progress|done|failed>         # M1 §T1 required
non-resumable-actions: []                 # M1 §T1 required (typically empty — refactor ships no commits)
approvals: []                             # M1 §T1 optional (P-M1-1 schema)
geniro_kind: refactor-state               # M8 schema marker per М1 §Frontmatter contract §Producer-specific extensions
geniro_schema_version: m8-v1              # M8 producer schema-version marker
effort_tier: <Trivial|Small|Medium|Big>   # M8 extension — canonical effort-scaling per §6.3
task_slug: <slug>                         # M8 extension — slug per `skills/_shared/within-skill-state-handoff.md` § Slug rules
worktree: <abs-path>                      # M1 §T1 optional, M8 strongly recommended
---
```

### 9.2 Body sections

```markdown
## Scope                                  # files + symbols в refactor scope

## Baseline                               # Evidence Block from §6.2 step 5 — test count + pass status

## Smells Detected                        # (Medium+) refactor-agent output from §6.4

## Plan                                   # (after §6.6) ordered steps + risk + consumer counts + KEEP/FILTER decisions

## Apply Summary                          # (after §7) executed / blocked / final-suite status

## Accepted Blocks                        # (optional, §7.3 path "Keep what worked")

## Review Findings                        # (Medium+, after §8.2) CRITICAL/HIGH/MEDIUM lists

## Persisted approvals                    # M3 §6 Block 5d — render of frontmatter approvals[] (HIGH-step + PRODUCT-DECISION categories)

## Tool log                               # M3 §6 selective logging (refactor-agent spawns, relevance-filter spawn, reviewer-agent spawns, escalations)

## Errors                                 # M3 §6 Block 5b — error observations carried across compaction

## Open Questions                         # M3 §6 Block 5c — escalation AUQs + outcome

## Termination reason                     # M3 §6 — only on terminal aborted/reverted/routed states
```

---

## 10. Memory I/O (M2 §13 obligation — OQ-M8-1 closure)

### 10.1 Helper-call schedule

| Phase | Helper | Direction | MODE | Inputs | Outputs | Notes |
|---|---|---|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` | scope = `refactor` + `global` + `code-style` | concatenated rules inlined | Echo contract per M3 §7.2. M3 SessionStart re-injects on compaction. |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` | top-2 default (`_project.md` + `_CODEBASE_MAP.md`) | inlined into context + drift check | Drift notification surfaces к user if `.fingerprint.json` mismatched. |
| Phase 1 entry | `query-learnings` | read L2 | n/a | tags inferred от $ARGUMENTS (e.g., `react`, `auth`, `coupling`); scope = task path | top-K matching entries (K=5 default) | Per M2 §5.3. К find prior discoveries about coupling, pitfalls, conventions relevant к the refactor scope. |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a | three layers | precedence-resolved или AUQ on hard conflict | Per M2 §10. |
| Phase 1 (Medium+) | refactor-agent spawn (evidence-only) | — | — | — | smells + consumer counts | One spawn; орchestrator builds plan after. |
| Phase 1 (Medium+) | orchestrator-inline smell evidence | — | — | — | per-smell KEEP/FILTER decision | No spawn — runs in orchestrator's main context. |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` | same scope as Phase 1 | re-inlined | Single re-fire — drops pre-M8 double-refresh. |
| Phase 2 | refactor-agent spawn (execution) | — | — | approved plan + test cmd + autofix cmd | structured execution report | Model: opus if max_risk=HIGH else sonnet. |
| Phase 3 (Medium+) | reviewer-agent spawn (independent) | — | — | diff + agent report + conventions + 3 criteria files | CRITICAL/HIGH/MEDIUM findings | One spawn, parallel с custom reviewers. |
| Phase 3 (Medium+) | custom reviewer-agent spawn(s) | — | — | per `load-custom-reviewers.md` spec | findings per dim | Parallel batch с independent reviewer. |
| Phase 3 exit (§8.5) | `emit-learning` | write L2 | n/a | producer = `/geniro:refactor`; type = `discovery` (pattern extracted) или `pitfall` (footgun discovered); scope = changed-file paths or generalized; required `ext.{area, insight}` (discovery) or `ext.{trap, mitigation}` (pitfall) | append к `learnings.jsonl` | Dedup + sanitization per M2 §5.2. Default trust `verified`. |
| Phase 3 exit (§8.7) | M1 `atomic_state_write` | write T1 | n/a | state.md path | whole-file rewrite | Fires только if а side-effect was performed; baseline M8 has none. |

### 10.2 L2 emit triggers (per M2 §5.3 canonical contract — strict alignment)

| Type | When M8 emits |
|---|---|
| `discovery` | **Primary M8 emit type.** Emit когда а pattern was extracted к а shared utility/component (typical /refactor outcome). Required `ext.{area, insight}`. Default trust `verified`. |
| `pitfall` | Emit когда the refactor revealed а footgun (a seemingly-safe pattern that actually breaks). Required `ext.{trap, mitigation}`. Default trust `verified`. |
| `diagnosis` | NOT emitted by M8. /debug owns this trigger. |
| `convention` | NOT emitted by M8. /implement self-review owns this trigger. |
| `decision` | NOT emitted by M8. /plan и /implement inline-task mode own this trigger. |

### 10.3 L3 update sites

`update-semantic` writes to `_CODEBASE_MAP.md`:
- Add-module: NOT applicable — refactor doesn't add modules (would be а behavioral change → escalate).
- Move: applicable когда refactor moves files. Append-entry per change.
- Rename: applicable. Append-entry per change.

Bounded auto-incremental (M2 §6.1) — does не rewrite entire L3.

NOT `_FEATURES.md` (feature-backlog owned by /plan).
NOT `_project.md` or `_architecture.md` (user-curated).

### 10.4 Phase boundary refresh sites (M3 §7.3)

| Boundary | Refresh action | Why |
|---|---|---|
| Phase 1 entry | `load-custom-instructions(MODE: refresh)` + `load-semantic(MODE: refresh)` | Initial context load |
| Phase 2 entry | `load-custom-instructions(MODE: refresh)` — **always** | Survive Phase-1 compaction без M3 marker dependency; mirror M4 §13.4. |
| Phase 3 entry | none | Phase 2 refresh covers; no code-writing в Phase 3 |
| Phase 3 exit | none | Skill terminates |

### 10.5 ACI per-phase tool surface (OQ-M8-2 closure)

Mirrors M4 §13.5 structure. Per master plan P-M4-6 — minimal scope.

**Phase 1 (Plan):**
- Allowed: Read / Grep / Glob / Bash (read-only — `git status`, `git log`, `git diff`, `git branch --show-current`, test suite invocation для baseline).
- Allowed Agent spawns: refactor-agent (evidence-only). Phase 1 §6.5 smell evidence runs orchestrator-inline.
- Explicitly blocked: production-source Edit/Write, `git commit`, `git push`, `gh pr create`.

**Phase 2 (Apply):**
- Allowed Agent spawn: refactor-agent (execution).
- The refactor-agent itself uses Edit / Write / Bash (test cmd) per its agent definition. Orchestrator-level: monitor agent return, run final regression suite.
- Explicitly blocked at orchestrator level: `git add`, `git commit`, `git push`, `gh pr create`, branch switching.

**Phase 3 (Verify):**
- Allowed: Read / Grep / Glob / Bash (`git diff --name-only`, `git diff --stat`, test cmd для re-runs).
- Allowed Agent spawns: reviewer-agent + custom reviewers (Medium+ only), focused ADR-drafting agent (if PRODUCT-DECISION ADR path picked).
- Allowed: `git checkout -- .` (orchestration-level revert per pre-M8 SKILL.md:428) — exception to git-write constraint.
- Explicitly blocked: `git commit`, `git push`, `gh pr create`.

**All reviewer / custom reviewer spawns are pure read-only (per M4 §13.5 reviewer ACI):** tool whitelist via `agents/reviewer-agent.md` frontmatter `tools:` whitelist (Read / Grep / Glob / Bash for read-only checks).

**Existing safety layer** applies across ALL phases: file-protection hook, git-guardrail hook, `.geniro/` deletion guard (CLAUDE.md § Safety Hooks). Runtime denies stay enforced.

**Out of scope для M8 (deferred):** 14-class risk taxonomy + 7-decision matrix. Useful когда M9-M10 require cross-skill consistency.

---

## 11. Open questions

| ID | Topic | Status |
|---|---|---|
| **OQ-M8-1** | Memory I/O (M2 §13 obligation) | ✅ §10 |
| **OQ-M8-2** | ACI per-phase tool surface | ✅ §10.5 minimal scope |
| **OQ-M8-3** | Tier behavior — Trivial-tier "no smell-detect, no relevance-filter, no review" — risk of missing smells? | ⏳ Deferred к implementation. Trivial tier is by definition 1-2 files, single module, unambiguous intent — risk is bounded. Empirical tuning happens during /refactor rewrite if false negatives emerge. |
| **OQ-M8-4** | Refactor-agent `tools:` frontmatter — Edit/Write/Bash allowed (it executes the plan), but блокировать external commits (`git push`, `gh pr create`)? | ⏳ Deferred к implementation. Initial heuristic: agent frontmatter blocks `git`/`gh` commands entirely except `git checkout` (revert path); orchestrator enforces. |

---

## 12. Cleanup checklist

### 12.1 `skills/refactor/SKILL.md` — surgical edit (significant restructure)

Pre-M8 SKILL.md (510 lines, 5+1 phases) maps mechanically к M8's 3-phase structure but the section reorganization is large. **Surgical edit, not full rewrite** — most semantic content (refactor-agent spawn template, relevance-filter spawn template, reviewer-agent spawn template, anti-rationalization table, Existing Abstraction Audit reference, hard escalation signals) is preserved verbatim under new section headers.

**Sections к delete (line ranges from pre-M8 file):**

- L51-93: "Complexity Gate" с refactor-local 5-dim score — replaced с canonical effort-scaling reference per §6.3.
- L389-424: Phase 6 TDD post-GREEN chain — drop entirely per design Q3.
- Stale tier names в L74-78 ("Small / Medium / Large") — replace с Trivial / Small / Medium / Big.

**Sections к rewrite в place:**

- L96-124: State & Resume Semantics — re-write для M1 §T1 frontmatter + subdir-per-slug + M3 body sections per §9. Drop strategic compact points (М3 hook covers all phase boundaries).
- L127-228 Phase 1+2 (Scope+Analyze+Plan) → consolidate as Phase 1 (Plan) per §6.
- L232-281 Phase 4 (Execute) → Phase 2 (Apply) per §7. Drop the Phase 4 "Refresh custom instructions" (preserved at Phase 2 entry).
- L283-387 Phase 5 (Review Results) → Phase 3 (Verify) per §8. Drop the Phase 5 "Refresh custom instructions" (inherited from Phase 2). Replace `/geniro:follow-up` endpoint message с `/geniro:implement`.
- L430-447 anti-rationalization → §14 (preserves 14 rows + adds cross-cutting rows).
- L455-463 Learn & Improve → §8.5 + §8.6 (М2 §5.3 emit + М2 §5.4 routes).

**Sections к keep as-is:**

- L10-27: When to use / When NOT к use — preserve; replace L25 `/geniro:deep-simplify` с `/geniro:review --simplify` (D9-fix).
- L29-41: Subagent Model Tiering — preserve verbatim.
- L42-47: Agent Failure Handling — preserve verbatim.
- L80-93: Hard Escalation Signals table — preserve refactor-specific signals (D7/8/9/10/12 closures handled separately); orthogonal к effort-scaling, escalate OUT.
- L469-501: Definition of Done — preserve verbatim (state-file paths updated per §9).
- L503-510: Example invocations — preserve verbatim.

**Target post-rewrite length:** ~520-550 lines (vs pre-M8 510 — slight increase due к M1 frontmatter schema documentation; offset partially by Phase 6 deletion).

### 12.2 Legacy state file generations (M8 cleanup contract)

Three legacy generations к clear at Phase 3 §8.7 Cleanup:

1. `.geniro/refactor/state.md` (original — pre-state-dir, non-scoped)
2. `.geniro/refactor/state-${slug}.md` (intermediate — pre-state-dir, slug-scoped)
3. `.geniro/state/refactor/state-${slug}.md` (pre-M8 — flat under state-dir)

Listed как `rm -f` invocations in §8.7 (best-effort, 2>/dev/null wrapper).

### 12.3 `_shared/` helper updates

- `skills/_shared/effort-scaling.md` — **Several edits required:**
  - L3: Remove sentence "/geniro:refactor uses а deliberate override that reweights dimensions toward zero-behavior-change concerns — see skills/refactor/SKILL.md §Complexity Gate." (M8 adopts canonical — no override remains.)
  - L49: Remove `/geniro:follow-up` Fast Lane reference + `/geniro:implement` Light Mode reference (both stale per M4 §9.3 + master plan §66). Replace с simpler "Trivial: skip planning agents и proceed directly к execution" line.
  - L52: Remove `/geniro:decompose` reference (deleted master plan §65). Replace с `/geniro:plan` (M5) recommendation для Big tier.
- `skills/_shared/within-skill-state-handoff.md` — verify § Slug rules clause supports `.geniro/state/refactor/<slug>/state.md` layout (subdir-per-slug). If pre-M7 helper assumed flat filename pattern, update к subdir layout (М7 already did this if M7 implementation PR landed).
- `skills/_shared/spawn-agent.md` — verify refactor-agent + reviewer-agent spawn sites follow the ladder. Already used pre-M8; no change expected.
- `skills/_shared/existing-abstraction-audit.md` — referenced from refactor-agent spawn prompt. No change expected.
- `skills/_shared/evidence-standard.md` — referenced by §6.2 baseline и §7.4 regression. No change expected.
- `skills/_shared/test-first-gate.md` — referenced from §6.2 step 6. No change expected.
- `skills/_shared/improvement-routing.md` — referenced by §8.6. Verify M2 §5.4 L4 routes table matches §8.6 contract; update if drift. ADR template reference still needed для §8.3 ADR path.
- `skills/_shared/per-finding-question.md` — verify § Single-finding gate exists и matches §8.3 PRODUCT-DECISION escalation contract. If absent, add the section в the per-skill implementation PR.
- `skills/_shared/model-tiering.md` — verify refactor-agent (sonnet default / opus on max_risk=HIGH) row. No change expected.
- `skills/_shared/load-custom-reviewers.md` — referenced from §8.2. Verify `paths:` filter uses changed-files list correctly.
- `skills/_shared/architecture-vocabulary.md` — referenced from refactor-agent spawn prompt Deepening Opportunities lens. No change expected.
- `skills/_shared/primary-worktree.md` — referenced для cross-session artifact resolution. No change expected.
- `skills/_shared/scope-anchor.md` — referenced from §6.2 prior-planning context + agent spawn anchors. No change expected.
- `agents/refactor-agent.md` — verify Phase 2 (Execution) и Phase 1 (Evidence Only) contracts both supported. Verify model tier carve-out (sonnet default / opus on HIGH). If pre-M8 included references к Phase 6 TDD post-GREEN, remove those references per Q3 drop. Verify `tools:` frontmatter blocks `git`/`gh` external commits (OQ-M8-4 deferred decision).
- `agents/relevance-filter-agent.md` — ✅ deleted under subagent rationalization; Phase 1 §6.5 now orchestrator-inline.
- `agents/reviewer-agent.md` — verify it accepts refactor-flavored prompts (5 Focus Areas в §8.2). Already used pre-M8; no change expected.

---

## 13. Master plan reconciliation

### 13.1 Skill-list status (master plan §20)

M8 finalizes 1 of the 11 surviving skills. State after M8 implementation:

| Skill | Source | Milestone owner |
|---|---|---|
| `/plan` | NEW — replaces `/brainstorm` + `/decompose` | M5 ✅ |
| `/implement` | Redesigned | M4 ✅ |
| `/review` | Consolidated | M6 ✅ |
| `/debug` | Aligned с /implement simplification | M7 ✅ |
| **`/refactor`** | **Aligned с /implement simplification + canonical effort-scaling adoption (this doc)** | **M8 (this doc)** |
| `/onboard` | Codebase mapping | M9 ⏳ |
| `/investigate` | Codebase Q&A | M9 ⏳ |
| `/instructions` | CRUD `.geniro/instructions/*` | M10 ⏳ |
| `/actions` | CRUD `.geniro/actions/*` | M10 ⏳ |
| `/setup` | One-time project bootstrap | M10 ⏳ |
| `/update` | Plugin update | M10 ⏳ |

### 13.2 M8-specific obligations from master plan

| Master plan ref | Obligation | M8 status |
|---|---|---|
| §34 | "Zero-behavior-change restructuring. **Distinct guarantee** from /implement" | ✅ Preserved verbatim. Constitutional rule referenced throughout §1, §6.2 baseline, §7.4 regression, §8.3 PRODUCT-DECISION escalation. |
| §69 | /learnings auto-step replaces standalone skill | ✅ §8.5 L2 emit (mirror of M4 §7.5 step 5 + P-M4-5 promotion suggestion) |
| §120 | "Same [as M7]" — align с /implement simplification, reuse M1–M3 conventions | ✅ 3-phase mirror (§6/§7/§8); M1 §T1 frontmatter (§9); M3 body sections (§9) + Block 5d approvals (§6.6, §8.3); M2 helpers (§10) |
| §405 (P-X5 design guidance) | Budget section mirroring M4 §2.3 | ✅ §2.3 |
| Anti-patterns guardrail (P-MP-1) | Anti-pattern check audit | ✅ §14 |
| M2 §5.3 row /refactor | Emit `discovery` (pattern extracted) и `pitfall` (footgun discovered) | ✅ §8.5 + §10.2 |

### 13.3 Stale assumptions corrected

| Original /refactor assumption | Corrected (M8) |
|---|---|
| Refactor uses its own complexity rubric (3 tiers, 5-dim refactor-local score) | Adopts canonical effort-scaling per Q2 (4 tiers, 5-dim canonical score). Refactor-specific hard escalation signals retained as orthogonal escalate-OUT layer. effort-scaling.md L3 override sentence removed per §12.3. |
| `/geniro:decompose` is the routing target для Large tier | `/geniro:plan` (M5) per D7-fix. Master plan §65 deleted /decompose. |
| `/geniro:follow-up` is the recommended ship target после refactor | `/geniro:implement` per D8-fix. Master plan §66 absorbed /follow-up. |
| `/geniro:deep-simplify` is the suggested tool для optimization vs refactor | `/geniro:review --simplify` per D9-fix. Master plan §67 absorbed as flag. |
| Phase 6 TDD post-GREEN chain bridges /implement TDD Lane + /follow-up Medium | Dropped entirely per Q3. Master plan §66 deleted /follow-up + М4 §3.1 removed TDD Lane. |
| State file at flat `.geniro/state/refactor/state-<slug>.md` is canonical | Replaced by `.geniro/state/refactor/<slug>/state.md` (subdir-per-slug, mirrors M4/M5/M7). 3 legacy generations cleaned. |
| Double "Refresh custom instructions" в Phase 4 + Phase 5 | Single Phase 2 entry refresh (mirror M4 §13.4). |
| Strategic compact points after Phase 2 + Phase 4 needed as user-facing reminders | M3 SessionStart hook handles all phase-boundary recovery; explicit user-facing reminders no longer needed. |

---

## 14. Anti-rationalization (P-MP-1 closure)

Per master plan P-MP-1 (lines 162-179): every milestone closes с an explicit anti-pattern check. This section preserves 14 rows verbatim from pre-M8 SKILL.md:430-447 (which already captured refactor-specific rationalization patterns) + cross-cutting LLM-orchestration anti-patterns (auto-handle / kill caps / silent abort / hook bypass / auto-promote).

| Your reasoning | Why it's wrong |
|---|---|
| "This smell is too small to fix" | If the plan says fix it, fix it. Small smells compound. (Preserved.) |
| "I'll batch multiple transformations" | One atomic transformation at а time. Always. (Preserved.) |
| "Tests are passing so I'll skip the blocked step protocol" | The protocol exists для the NEXT failure. Follow it. (Preserved.) |
| "This refactoring needs а behavior change" | Then it's not а refactoring. Use `/geniro:implement` instead. (Preserved.) |
| "I'll skip reading project conventions" | You'll flag intentional patterns as smells. Read first. (Preserved.) |
| "This duplication needs а new shared helper" | Run the Existing Abstraction Audit first. If а utility / service / hook already exists nearby that could absorb this duplication via а small extension, prefer extending it. Only create а new shared helper when no analogue exists OR when extending the existing one would require adding а parameter or conditional that complicates it (Rule of Three). (Preserved.) |
| "All detected smells are real issues" | Generic smell categories flag intentional repo patterns. Without filtering against THIS repo's conventions, you'll refactor code that was designed that way on purpose. (Preserved.) |
| "This is just а refactor" | Refactors break things. Tests и review apply equally. (Preserved.) |
| "I'll spawn agents one at а time" | All parallel agents MUST be spawned в ONE response — multiple Agent() calls в the same assistant turn. Separate turns = no concurrency, full wall-clock latency per agent. (Preserved.) |
| "The user said go fast — skip phases" | Phase skipping is tied к tier classification, not user impatience. Trivial/Small tiers already skip appropriately. (Preserved, updated к canonical tier names.) |
| "I noticed а bug mid-refactor, I'll fix it" | That's feature work. Note it для `/geniro:implement` и stay в refactor scope. (Preserved, /follow-up reference removed per D8-fix.) |
| "This change is obviously safe" | "Obviously safe" is the #1 predictor of broken builds. Run validation. (Preserved.) |
| "I'll upgrade this sonnet spawn к opus just to be safe" | Model tier is task-nature-matched, not risk-appetite-matched. Re-classify via Subagent Model Tiering table; don't silently upsize. (Preserved.) |
| "Reviewer flagged а `[PRODUCT-DECISION]` finding — I'll route it through the fix loop like any other CRITICAL/HIGH" | А `[PRODUCT-DECISION]` finding has multiple valid resolution paths by definition — picking one is а behavior change, which contradicts refactor's zero-behavior-change guarantee. §8.3 disposition logic ESCALATES PRODUCT-DECISION к `/geniro:implement` (always-WAIT) — never gates-and-fixes them в-skill. If you find yourself spawning the refactor-agent для а PRODUCT-DECISION finding, that's the rationalization. Stop и route the escalation. (Preserved.) |
| "Add а wall-time kill cap so long-running refactor sessions abort cleanly." | Class-A hard caps abort legitimate complex refactors mid-stride. M8 §2.3 quality-first — no Class-A caps. §7.3 ≥30% blocked gate + §8.3 PRODUCT-DECISION + 1-round fix-loop gate all escalate к user via AUQ. User has agency. |
| "Auto-handle MEDIUM-tier findings к reduce user friction." | The Metaswarm anti-pattern catalogued в `report.md`. M8 §8.3 routes MEDIUM finds к "note в completion summary; proceed" — visible, not auto-dropped. Never auto-drop. |
| "Auto-promote L2 discoveries к L4 rules when refactor completes." | §8.5 + P-M4-5 — surface а suggestion line; do NOT auto-promote. User remains source-of-truth для L4 curation. Auto-promotion creates noise + drift. |
| "Skip the §8.4 completion summary; the agent self-report covers it." | Agent self-report is а raw spawn artifact. §8.4 IS the user-facing deliverable — risk classifications, blocked steps, validation status, next-step routing. Without it, user cannot make informed decisions. |
| "Bypass `git guardrail` hooks if а needed `git stash` / `git checkout -- .` step blocks." | The hooks fail-closed for а reason. `git checkout -- .` (revert path) is explicitly permitted per §8.7 ACI rule + pre-M8 SKILL.md:428 exception. Other git mutations stay blocked. If а specific guardrail blocks legitimate refactor work, the path is `.geniro/safety.json` `allow_patterns`, not `--no-verify`. |
| "Defer M3 compaction-survival к downstream skills — M8 is mostly mechanical." | M3 contract IS M8's contract — state.md frontmatter (M1 §T1), `approvals[]` (P-M1-1 + M3 Block 5d), `## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason`. Без them, compaction mid-execution loses the plan и the per-step audit trail. |
| "Audit trail isn't needed for local /refactor runs — the diff IS the record." | The diff is the OUTPUT, not the audit. `## Tool log` records refactor-agent + relevance-filter + reviewer spawn outcomes (which can drive escalation re-runs). `## Open Questions` records gating decisions. Without them, post-mortem on а failed run is impossible. |
| "PRODUCT-DECISION 4-option AUQ is paternalistic — collapse к 2 options (run /implement / accept-as-is)." | Pre-M8 SKILL.md:341 explicit: 4 fixed options when ADR-eligible (3 otherwise). The ADR path captures rejection rationale durably; the Revert path is а user-controlled safety net. Collapsing removes meaningful agency. |
| "Trivial tier should still run а quick reviewer-pass — what if а smell slipped through?" | Trivial is by definition 1-2 files, mechanical, single module, unambiguous. The diff-sanity check in §8.1 + the baseline regression in §7.4 catch behavioral drift. Running а full reviewer-agent batch for а 5-line rename wastes tokens. Tier behavior is intentional. |
| "Subdir-per-slug layout adds nesting overhead — keep flat `state-<slug>.md`." | Flat layout shares concurrency model с M4/M5/M7. Subdir-per-slug мatches the cross-skill convention (М4 §5.4 inputs persist, М7 §11.1). Consistency wins over а cosmetic preference. |

---

## 15. Cross-references

- M1 (state-files framework): `architecture/M1-state-files.md` (esp. §T1 frontmatter base; §Frontmatter contract §Producer-specific extensions; no §T2 row для refactor per D11-fix)
- M2 (memory layers): `architecture/M2-memory-layers.md` (esp. §5.2 emit type taxonomy; §5.3 row /refactor — discovery + pitfall; §5.4 L4 routing; §9 emit-learning helper; §10 resolve-conflicts; §13 obligation)
- M3 (compaction-survival): `architecture/M3-compaction-survival.md` (esp. §6 body sections; §7.2 Echo contract; §7.3 phase boundary refresh; §10 systemMessage; Block 5b/5c/5d render)
- M4 (/implement redesign): `architecture/M4-implement-redesign.md` (esp. §2.1.1 termination mapping; §2.2 7 invariants; §2.3 quality-first budgets; §7.4 escalation AUQ pattern; §13.4 phase boundary refresh; §13.5 ACI per-phase; §14 anti-rationalization)
- M5 (/plan redesign): `architecture/M5-plan-redesign.md` (esp. §17 spec.md schema — referenced from Big tier "Run /plan first" routing)
- M6 (/review redesign): `architecture/M6-review-redesign.md` (esp. §13 --simplify flag — referenced from §1 "When NOT к use")
- M7 (/debug redesign): `architecture/M7-debug-redesign.md` (esp. §6.7 [ROOT-CAUSE] finding tagging; §11.1 state.md schema patterns)
- spawn-agent ladder: `skills/_shared/spawn-agent.md`
- context-isolation checklist: `skills/_shared/context-isolation-checklist.md`
- effort-scaling: `skills/_shared/effort-scaling.md` (canonical adopted per Q2 — see §12.3 updates)
- existing-abstraction-audit: `skills/_shared/existing-abstraction-audit.md`
- evidence-standard: `skills/_shared/evidence-standard.md`
- test-first-gate: `skills/_shared/test-first-gate.md`
- finding-tagging: `skills/_shared/finding-tagging.md`
- model-tiering: `skills/_shared/model-tiering.md`
- primary-worktree: `skills/_shared/primary-worktree.md`
- per-finding-question: `skills/_shared/per-finding-question.md` (§ Single-finding gate)
- emit-learning helper: `skills/_shared/emit-learning.md`
- within-skill-state-handoff: `skills/_shared/within-skill-state-handoff.md`
- scope-anchor: `skills/_shared/scope-anchor.md`
- load-custom-reviewers: `skills/_shared/load-custom-reviewers.md`
- improvement-routing: `skills/_shared/improvement-routing.md` (§ ADR template)
- architecture-vocabulary: `skills/_shared/architecture-vocabulary.md`
- refactor-agent: `agents/refactor-agent.md`
- reviewer-agent: `agents/reviewer-agent.md`
- Pre-M8 /refactor: `skills/refactor/SKILL.md` (510 lines — reference для verbatim preservation per §12.1)
