# M7 — /geniro:debug Redesign (M4-aligned, Adversarial Mode preserved)

**Status:** Specification (pre-implementation)
**Master plan:** `/root/.claude/plans/reactive-dreaming-backus.md` — M7 of the M1–M10 redesign. Master plan §119 mandates: "Align with `/implement` simplification. Reuses M1–M3 conventions."
**Scope:** Redesign of `/geniro:debug` к mirror M4's three-phase structure (Investigate → Propose → Ship) и absorb the `/learnings` skill's auto-emit responsibilities. Preserves Adversarial Mode (verify-changes) per design Q1.
**Depends on:** M1 (state-files — `atomic_state_write`, T1 layout, T2 handoff path `from-debug-<branch>.md`, `approvals[]` P-M1-1); M2 (memory — `query-learnings` Phase 1, `emit-learning` Phase 3, L4 promotion suggestion); M3 (compaction-survival — `## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason`, Block 5d `approvals[]` render); M4 (mirrored phase structure, escalation AUQ pattern §7.4, ACI surface §13.5).
**Follows:** M6 (/review)
**Followed by:** M8 (/refactor), M9 (/onboard + /investigate), M10 (operational skills).

---

## 1. Purpose

The pre-M7 `/geniro:debug` (563-line `SKILL.md`) ships а scientific-method workflow с two top-level concerns wired together:

1. **Scientific-method investigation** — 9 numbered steps (0 Retrieve Prior → 1 Observe → 1.5 Feedback Loop → 2 Hypothesize → 3 Test → 4 Isolate → 5 Propose Fix → 6 Author Repro Test → 6.5a Present Findings → 6.5b Escalation → 7 Document → 8 Suggest Improvements). Custom `HYPOTHESES-<slug>.md` state file. Custom `findings-state.md` T2 handoff format. Universal AskUserQuestion rule duplicates the canonical `per-finding-question.md`.

2. **Adversarial Mode** (verify-changes) — а parallel workflow triggered by `verify last changes` / `HEAD~N..HEAD` / PR-ref keywords. RED-phase F→P test authoring delegated к `adversarial-tester-agent`; fix authoring escalated downstream.

M7 collapses the scientific-method 9 steps к **3 phases mirroring M4** (Investigate → Propose → Ship), migrates state files к M1 canonical schema, absorbs the deleted `/learnings` skill via per-phase auto-emit calls + а P-M4-5-style L4 promotion suggestion, и preserves Adversarial Mode as а co-equal parallel workflow (per design Q1 — "Keep в /debug"). Goal-statement from master plan §34 is preserved verbatim: **«locate the cause»**.

---

## 2. Architecture overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  /geniro:debug $ARGUMENTS                                                    │
└─────────────────────────────┬────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  Phase 0 — Mode detect                  │
        │  • $ARGUMENTS semantic parse            │
        │  • Anchored verify-keyword signals →    │
        │    Adversarial Mode (§9)                │
        │  • Otherwise → Scientific Mode          │
        │  • Empty + interactive → AUQ            │
        └────────────┬────────────────────┬───────┘
                     │                    │
              Scientific             Adversarial
                     │                    │
                     ▼                    ▼
        ┌────────────────────┐   ┌─────────────────────────┐
        │ Phase 1 —          │   │  Adversarial Workflow   │
        │ Investigate (§6)   │   │  (§9 — preserves        │
        │                    │   │   pre-M7 RED-phase      │
        │ 1.1 L4 + L2 load   │   │   test authoring)       │
        │ 1.2 Observe + repro│   │                         │
        │ 1.3 Feedback loop  │   │ 9.2 Diff resolution     │
        │ 1.4 Hypothesize    │   │ 9.3 Skip conditions     │
        │ 1.5 Test + missing-│   │ 9.4 Spawn agent (RED)   │
        │     data gate      │   │ 9.5 Independent re-     │
        │ 1.6 Isolate →      │   │     verify (orchestrator│
        │     [ROOT-CAUSE]   │   │     re-runs)            │
        │ 1.7 STALL gate     │   │ 9.6 Findings persist    │
        │     (P-M7-2)       │   │ 9.7 Reuse §8.2 AUQ      │
        └─────────┬──────────┘   └──────────┬──────────────┘
                  │                         │
                  ▼                         │
        ┌────────────────────┐              │
        │ Phase 2 — Propose  │              │
        │ (§7)               │              │
        │                    │              │
        │ 2.1 L4 refresh     │              │
        │ 2.2 Multi-path     │              │
        │     fix gate       │              │
        │     (P-M1-1)       │              │
        │ 2.3 Text proposal  │              │
        │ 2.4 F→P repro test │              │
        │ 2.5 Fix-loop gate  │              │
        │     (2 attempts)   │              │
        └─────────┬──────────┘              │
                  │                         │
                  ▼                         ▼
        ┌──────────────────────────────────────────┐
        │  Phase 3 — Ship  (§8)                    │
        │                                          │
        │  3.1 Present findings (chat + persist    │
        │      from-debug-<branch>.md)             │
        │  3.2 Escalation AUQ — Trivial /          │
        │      Non-trivial / Cannot-verify /       │
        │      Leave-it-to-me                      │
        │  3.3 L2 emit (diagnosis) +               │
        │      L4 promotion suggestion (P-M4-5)    │
        │  3.4 Suggest improvements (M2 §5.4)      │
        │  3.5 Cleanup (3 legacy generations)      │
        │  3.6 atomic_state_write(non-resumable)   │
        │      after each side-effect              │
        └──────────────────────────────────────────┘
```

### 2.1 State machine

Phase enum (state.md `phase:` field values) и transitions:

```
[entry]
  └── mode-detect ──┬── investigate ──┬── propose ──┬── ship ──┬── done
                    │                  │             │           └── (atomic non-resumable-actions write per side-effect)
                    │                  │             │
                    │                  │             └── ship-summary-only (terminal — "Leave it to me" pick)
                    │                  │
                    │                  └── phase-2-escalated ──┬── debug-handoff (terminal — would normally escalate к /debug, но we ARE /debug → marks fix-fail; user re-enters)
                    │                                          ├── propose (user picks "try different approach" → flows back into hypothesis loop)
                    │                                          └── aborted (terminal)
                    │
                    └── phase-1-escalated ──┬── investigate (user picks "supply data" → resume hypothesis testing)
                                            ├── ship-summary-only (user picks "abandon — present partial findings")
                                            └── aborted (terminal)

      adversarial-mode-detect ──┬── adversarial-investigate ──┬── adversarial-ship ──┬── done
                                │                              │                       └── adversarial-aborted (terminal — zero red tests survived)
                                │                              │
                                │                              └── (no separate escalation — re-uses §8.2 AUQ)
```

**Terminal states:** `done`, `ship-summary-only`, `debug-handoff`, `aborted`, `adversarial-aborted`. M3 SessionStart recovery treats all five as "task complete — no resume needed".

**Non-terminal states:** `mode-detect`, `investigate`, `propose`, `ship`, `adversarial-mode-detect`, `adversarial-investigate`, `adversarial-ship`. M3 recovery rolls these back к their phase-entry point and re-runs (idempotent re-entry per §6.2, §7.1, §8.1, §9.4).

**Escalation states:** `phase-1-escalated` (P-M7-2 stall gate), `phase-2-escalated` (fix-loop exhaustion). M3 surfaces к user as "task was paused — last AUQ options:" so user re-picks без losing context. Note: unlike M4 §6.3 which routes "phase-2-escalated → debug-handoff", M7's debug-handoff means "fix-fail; re-enter debug fresh" — the orchestrator IS /debug, so there's no further handoff к а sibling skill, just а terminal marker that the prior run could not resolve.

### 2.1.1 Termination case → state mapping

Per master plan P-M4-2 (8 canonical termination conditions), М7 mapping:

| # | Termination case | Terminal state | `## Termination reason` body line |
|---|---|---|---|
| 1 | Final answer produced (handoff escalated) | `done` | (omitted — happy path) |
| 2 | Done condition satisfied ("Leave it to me" pick) | `ship-summary-only` | (omitted — modifier-driven) |
| 3 | User approval required | non-terminal `phase-N-escalated`, then terminal via user pick | — |
| 4 | Blocker needs user input | non-terminal `phase-1-escalated` (stall gate § 6.8 OR § 7.5) | — |
| 5 | Budget reached | N/A baseline (§2.3 quality-first — no Class-A caps) | (reserved для cost-aware mode post-P-X6) |
| 6 | Repeated failure threshold exceeded | `aborted` (via §6.8 stall AUQ "abort" pick OR §7.5 fix-fail "abort" pick) | `repeated-failure: <stall-or-fix>` |
| 7 | Safety policy denial (hook-block, dangerous-action veto) | `aborted` | `safety-denied: <hook-or-rule-name>` |
| 8 | Tool unavailability without fallback | `aborted` | `tool-unavailable: <tool-name>` |

Adversarial mode shares cases 6-8 with the adversarial-prefixed terminal states (`adversarial-aborted` for case 6 when zero red tests survive re-verification).

**`## Termination reason` body convention:** On аборт, append one-line entry к state.md body. Mirrors M4 §2.1.1 contract exactly.

### 2.2 Loop invariants

The 7 invariants from M4 §2.2 apply throughout M7's three phases без modification. Reference M4 §2.2 verbatim; do not duplicate. Three M7-specific notes:

1. **Invariant #4 (bounded output) applies to adversarial-tester-agent spawn** — its report at `from-debug-adversarial-<branch>.md` is capped at ~4K chars per finding block; longer truncated с marker.
2. **Invariant #6 (final answer grounded в observations) is the Evidence Standard for hypothesis confirmation** — every Result: field в `## Hypotheses` MUST cite an artifact kind 1-5 per `skills/_shared/evidence-standard.md`. "Symptom matches" is correlation, not causation; not allowed.
3. **Invariant #7 (errors → structured observations)** — failed `git diff`, denied permission on read-only Bash check, `adversarial-tester-agent` "agent not found" registration-ladder fallback all become structured `## Tool log` entries before being acted on.

**Side-effect — `## Tool log` section в state.md (selective logging):** M7 logs **subagent-spawn outcomes** (adversarial mode), **side-effect tool calls** (none в M7 — no `git push` / `gh pr create` — debug never ships), и **escalation entries** (Phase 1 stall, Phase 2 fix-fail). Routine Read / Edit / Bash skipped per M4 contract.

### 2.3 Budgets — quality-first framing

M7 has **NO hard kill caps**. All limits are **escalation gates that surface к user**. Per P-X5 design guidance (master plan §405): per-skill milestones authored after M4 must mirror M4 §2.3 framing.

**Quality gates (escalate к user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Inconclusive hypothesis tests | 5 across all hypotheses | §6.8 stall gate | AUQ — P-M7-2 diagnose-by-missing-component (8 options) → user supplies missing or picks alternative |
| Fix attempts failed verification | 2 | §7.5 fix-loop gate | AUQ — try different approach / accept as documented limitation / abort. **User picks.** |
| Adversarial mode authored tests | 10 hard cap | §9.4 (delegated к agent contract) | Stop authoring; surface findings (preserves pre-M7 agent-level rule) |
| Adversarial mode consecutive discards | 5 | §9.4 (delegated к agent contract) | Stop hypothesis generation; surface partial (preserves pre-M7) |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| Subagent spawns | 1 (adversarial mode only — `adversarial-tester-agent`) | §9.4 |
| Reproduction-test framework | Project's native (detected from CLAUDE.md Essential Commands) | §7.4 |

**Claude Code internals (not under M7 control):**
- Input tokens ≤200K per turn → triggers compaction (M3 hook handles resume).
- Output tokens ≤8K per turn → soft truncation by Claude Code.

**Explicitly NOT capped:**
- **Wall-time per run.** Complex multi-cause bugs may legitimately need hours of investigation.
- **Total tool calls per phase.** Hypothesis testing against а large codebase may need many Read/Grep calls.
- **Total model turns per phase.** Iterative hypothesis refinement is the point of scientific method.
- **Total cost per run.** Deferred к P-X6.

**Rationale.** Same two-class taxonomy as M4 §2.3: Class-A (hard kill caps — would abort legitimate investigation mid-stride; M7 has zero) vs Class-B (escalation gates — protect quality by preventing pointless retry spinning; M7 keeps two scientific + two adversarial-agent-level).

---

## 3. Scope deltas vs. pre-M7 `/geniro:debug`

### 3.1 Removed

| Component | Reason | Replacement |
|---|---|---|
| 9-step numbering (0 / 1 / 1.5 / 2 / 3 / 4 / 5 / 6 / 6.5a / 6.5b / 7 / 8) | Path-explosion с sub-step numbering | 3 phases mirroring M4 — Investigate → Propose → Ship |
| `HYPOTHESES-<slug>.md` filename | Non-M1-conformant (custom `Branch:/Worktree:/Timestamp:` header, no YAML frontmatter) | `state.md` под `.geniro/state/debug/<slug>/state.md` с M1 §T1 frontmatter |
| `findings-state.md` filename | Non-M1-conformant T2 (no frontmatter, no `geniro_kind`) | `.geniro/state/handoff/from-debug-<branch>.md` per M1 §T2 row (M1:502) |
| `adversarial-tests.md` filename | Non-M1-conformant T2 | `.geniro/state/handoff/from-debug-adversarial-<branch>.md` per M1 §T2 row (M1:503) |
| Universal AskUserQuestion Rule (inline) | Duplicate of canonical helper | Reference `skills/_shared/per-finding-question.md` instead |
| Step 5 + Step 6 double "Refresh custom instructions" | M3 SessionStart hook re-injects on compaction; one Phase 2 refresh covers it (mirror M4 §13.4 contract) | Single L4 refresh on Phase 2 entry (§7.1) |
| Step 0 "Retrieve Prior Knowledge" as separate step | Conflates with Phase 1 memory-layer load | Folded into Phase 1.1 (§6.1) |
| Independent "Compliance — Do Not Skip Steps" rationalization table | Cross-skill anti-rationalization is now а master-plan-wide P-MP-1 obligation | §16 anti-rationalization (preserves all 18 rows из pre-M7 + adds cross-cutting LLM rows) |

### 3.2 Kept (with adaptation)

| Component | Notes |
|---|---|
| Adversarial Mode (verify-changes) — RED-phase test authoring | Preserved per design Q1. Diff resolution still delegated к /review Phase 1 parser. State-file paths migrated к M1 §T2. (§9) |
| Multi-path fix gate (Always-WAIT) | Preserved. Now references canonical `per-finding-question.md`. Schema extended с P-M1-1 `approvals[]` persistence — gate result optionally persisted. (§7.2) |
| Missing-data gate (Step 3) | Preserved. Folded into Phase 1.5 (§6.6). |
| Hypothesis-tracking semantics (Hypothesis N — Evidence For/Against/Status/Test Plan/Result) | Preserved verbatim в `## Hypotheses` body section (§11.1.B). |
| Feedback Loop quality bar (fast + deterministic + captured) | Preserved verbatim в `## Feedback Loop` body section (§11.1.B). |
| Scientific Mode + Adversarial Mode dual entry-point | Preserved. Mode detect happens в Phase 0 (§6.1). |
| Infrastructure-cause hypothesis guidance | Preserved. Section moved к `_shared/infrastructure-investigation.md` reference (§14.3). |
| Isolation Techniques (binary search, git bisect, profiling) | Preserved. Section moved к `_shared/isolation-techniques.md` reference (§14.3). |
| F→P invariant + monkey-patch-by-default verification | Preserved verbatim. (§7.4) |
| Reproduction test naming rule (self-contained, no `Bug A/B/C` / `Hypothesis N`) | Preserved verbatim в §7.4. |
| Codegen note (DTOs / schemas / controllers) | Preserved в §8.1 findings template. |

### 3.3 Replaced

| Pre-M7 element | M7 replacement |
|---|---|
| Step 7 Document — Reflect → Abstract → Generalize | Phase 3.3 L2 auto-emit (M2 §5.2 emit-learning helper); /learnings skill drop covered. |
| Step 8 Suggest Improvements | Phase 3.4 — M2 §5.4 L4-aware routing (`.geniro/instructions/<scope>.md`, `code-style.md`, `.claude/rules/<glob>.md`, learnings.jsonl). |
| Step 6.5a Findings template | §8.1 — same shape, but persisted к `from-debug-<branch>.md` (M1 §T2 path) и enriched с `## Persisted approvals` body section. |
| Step 6.5b Escalation AUQ | §8.2 — same 4 options; references state file by path (no inline summary in command). |

---

## 4. Decisions recorded so far

| ID | Decision | Section |
|---|---|---|
| **Q1** | **Keep Adversarial Mode в /debug** — dual-mode preserved | §9 |
| **Q2** | **3 phases (M4 mirror)** — Investigate → Propose → Ship; sub-steps inline | §2, §6, §7, §8 |
| **Q3** | **Rename HYPOTHESES-<slug>.md → state.md** под `.geniro/state/debug/<slug>/state.md` (M1 §T1 **session-bound layout** — second canonical path-root per M1 §T1 Path roots table; the per-skill subdir layout used by session-bound skills like /debug + /refactor, distinct от M4/M5's task-bound `planning/<task-dir>/` layout) | §11.1 |
| **D1-fix** | M1 §T1 frontmatter base + M7 extensions for state.md | §11.1 |
| **D2-fix** | M1 §T2 frontmatter base + M7 extensions for from-debug-<branch>.md | §11.2 |
| **D3-fix** | M3 body sections (`## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason`, Block 5d) обязательны в state.md и from-debug-*.md | §11 |
| **D4-fix** | 3 phases collapse 9 steps; preserve all sub-step semantics | §6, §7, §8 |
| **D5-fix** | Reference M4 §2.2 7 invariants verbatim (no duplication) | §2.2 |
| **D6-fix** | P-X5 quality-first budget section mirror of M4 §2.3 | §2.3 |
| **D7-fix** | P-M7-2 diagnose-by-missing-component taxonomy (8 categories) at §6.8 stall gate | §6.8, §10 |
| **D8-fix** | P-M4-5-style L4 promotion suggestion after L2 emit | §8.3 |
| **D10-fix** | Reference `per-finding-question.md` instead of duplicating Universal AskUserQuestion Rule | §7.2, §16 |
| **D11-fix** | Phase 1.1 L2 query via canonical `query-learnings` helper (M2 §5.3 trigger) | §6.2 |
| **D12-fix** | Phase 3.4 routing follows M2 §5.4 L4 routes | §8.4 |
| **D13-fix** | Multi-path fix gate optionally persists outcome к `approvals[]` (P-M1-1) when gate result re-usable on resume | §7.2 |
| **D14-fix** | Single L4 refresh on Phase 2 entry (drop Step 5 + Step 6 double-refresh) | §7.1 |
| **D15-fix** | Cleanup clears 5 legacy generations (3 hypotheses + 2 handoff) | §14.2 |
| **OQ-M7-1** | M2 §13 memory-I/O obligation — §12 below | §12 |
| **OQ-M7-2** | Adversarial mode test-finding tagging (CRITICAL/HIGH/MEDIUM) — preserves pre-M7 `finding-tagging.md` schema. | §9 |
| **OQ-M7-3** | ACI per-phase tool surface | §12.5 |

---

## 5. Defect inventory (audit 2026-05-18 — before/after)

15 defects identified в pre-M7 audit. Each closed by the section listed.

| ID | Defect | Pre-M7 location | M7 closure |
|---|---|---|---|
| **D1** | `HYPOTHESES-<slug>.md` non-M1-conformant (no YAML frontmatter, custom header) | `skills/debug/SKILL.md:56-107` | §11.1 — full M1 §T1 frontmatter base + M7 extensions |
| **D2** | `findings-state.md` non-M1-conformant T2 | `SKILL.md:218-249` | §11.2 — full M1 §T2 frontmatter base + path migration to `from-debug-<branch>.md` |
| **D3** | No M3 body sections (`## Tool log` / `## Errors` / `## Open Questions` / `## Termination reason`) | throughout | §11.1 + §11.2 — added к both state.md и handoff |
| **D4** | 9 steps confuses сравнение с M4 simplification mandate | `SKILL.md:30-269` | §6/§7/§8 — 3-phase collapse |
| **D5** | No 7 loop invariant reference | throughout | §2.2 — references M4 §2.2 |
| **D6** | No quality-first budget section | throughout | §2.3 — full M4 §2.3 mirror |
| **D7** | No P-M7-2 diagnose-by-missing-component taxonomy for stalls | (absent) | §10 — 8-component taxonomy + Phase 1 stall AUQ render (§6.8) |
| **D8** | "Suggest Improvements" Step 8 not P-M4-5-aware (no promotion suggestion line after L2 emit) | `SKILL.md:267-269` | §8.3 — single-line suggestion after `diagnosis` emit when recurrence detected via Phase 1.1 query-learnings |
| **D9** | Adversarial Mode state file paths non-M1-conformant | `SKILL.md:271-369` | §9.5 + §11.3 — migrated к `from-debug-adversarial-<branch>.md` |
| **D10** | Universal AskUserQuestion Rule duplicates canonical | `SKILL.md:118-120` | §7.2 + §16 — reference `per-finding-question.md` |
| **D11** | Step 0 L2 query lacks canonical helper invocation | `SKILL.md:124-127` | §6.2 — `query-learnings` per M2 §5.3 trigger |
| **D12** | Step 8 routing misses M2 §5.4 L4 routes (e.g. `.claude/rules/<glob>.md` paths-frontmatter) | `SKILL.md:267-269` | §8.4 — canonical M2 §5.4 routing table |
| **D13** | Multi-path fix gate not P-M1-1-aware | `SKILL.md:198` | §7.2 — optionally persists к `approvals[]` |
| **D14** | Double "Refresh custom instructions" (Step 5 + Step 6) wastes context | `SKILL.md:197, 204` | §7.1 — single Phase 2 entry refresh (mirror M4 §13.4) |
| **D15** | Cleanup clears 2 legacy generations only (`.geniro/debug/HYPOTHESES.md` + `.geniro/debug/HYPOTHESES-${slug}.md`) | `SKILL.md:457-460` | §14.2 — 5 generations (pre-existing 2 + current pre-M7 `state/debug/HYPOTHESES-${slug}.md` + `state/debug/findings-state.md` + `state/debug/adversarial-tests.md`) |

---

## 6. Phase 1 — Investigate — **DECIDED**

State.md `phase: investigate`. Mirrors M4 Phase 1 Analyze в spirit (entry-gate + context load) plus M4 Phase 2 Implement-style inner loop (hypothesis test iterations). Exits к Phase 2 only when а hypothesis is confirmed AND its Result: field cites an artifact per Evidence Standard.

### 6.1 Mode detection ($ARGUMENTS routing)

Phase 0 (mode-detect) runs before Phase 1 проper. $ARGUMENTS shape determines routing:

| $ARGUMENTS shape | Mode |
|---|---|
| empty | AUQ с header "Mode" — 4 options: «Describe the symptoms» / «Paste error message» / «Point to а failing test» / «Verify last changes (adversarial)». First 3 → Scientific. Fourth → Adversarial. |
| matches anchored verify signals (per `## Adversarial Mode: Verify Last Changes` § Mode routing — preserved verbatim from pre-M7 `SKILL.md:44-50`) | Adversarial Mode (§9) |
| otherwise | Scientific Mode (this section continues to §6.2) |

**Approvals-persistence protocol (P-M1-1 producer-side contract):** before firing the disambiguation AUQ on empty $ARGUMENTS, check state.md frontmatter `approvals[]` for а prior entry с `category: disambiguate_mode`. If found, use the prior `picked` value. If not, fire AUQ → on user pick, append entry к `approvals[]` via M1 `atomic_state_write` before proceeding. M3 §6 Block 5d renders this on resume.

State.md transitions: `mode-detect` → `investigate` (Scientific) OR `adversarial-mode-detect` → `adversarial-investigate` (Adversarial branch — §9.4).

### 6.2 Memory layer load (L4 instructions + L2 prior-knowledge)

On Phase 1 entry:

1. **L4 refresh** — `load-custom-instructions(MODE: refresh, scope: debug + global + code-style)` per M3 §7.2 Echo contract.
2. **L3 refresh** — `load-semantic(MODE: refresh, top-2 default)`. Fingerprint drift check fires если applicable.
3. **L2 prior-knowledge query** — `query-learnings(tags=<inferred from $ARGUMENTS>, scope=task path)` per M2 §5.3 «debug session start» trigger (replaces pre-M7 Step 0 ad-hoc Grep). Top-K=5 default, filter superseded + deprecated. Skipped если $ARGUMENTS too generic к infer tags.
4. **Cross-layer conflict resolution** — `resolve-conflicts(L2/L3/L4 loaded)` per M2 §10.

Results inlined into context. Echo lines per M3 §7.2 mandatory.

### 6.3 Observe & repro

- Reproduce the bug consistently. Capture error messages, logs, stack traces.
- Identify what changed (recent commit, config, user action). Record exact repro steps.
- **If repro is unclear/missing:** `AskUserQuestion` с header "Repro details" — 2-4 concrete options (environment? steps к trigger? expected vs actual behavior?). Do NOT guess.

Persist to state.md body sections `## Symptom` и `## Reproduction Steps` (§11.1.B).

### 6.4 Build feedback loop

A feedback loop is а fast (≤30s, ideally ≤5s), deterministic, captured signal that reproduces the bug AND can be re-run cheaply.

**Pick the cheapest option that reliably reproduces:** (preserves pre-M7 table verbatim — see `skills/debug/SKILL.md:144-152` for option matrix — failing assertion / curl / SQL / headless browser / differential test / fuzz loop / manual click-through fallback)

**Quality bar:**
- Fast (re-runs в seconds)
- Deterministic (same input → same observed failure, 3-run signature comparison)
- Captured (artifact satisfies Evidence Standard kinds 2-5)

If 10 minutes pass без а working feedback loop, do NOT proceed by guessing — `AskUserQuestion` с header "Repro signal" — paste log / run command / mark intermittent + investigate без loop.

Persist to state.md `## Feedback Loop` body section (§11.1.B — Command / Expected output / Actual output / Re-run cost / Determinism).

### 6.5 Hypothesize

Based on Observation + Feedback Loop output, form **2-3 competing hypotheses**. Each must be testable AGAINST THE FEEDBACK LOOP — Step 1.5's tests will toggle one variable, re-run the loop, observe whether the captured signature changes.

**Consider infrastructure causes alongside code causes** — connection timeouts, resource exhaustion, DNS failures, container restarts, DB connection pool limits, rate limits, deployment changes. If symptoms include timeouts, intermittent failures, or environment-only manifestation, form at least one infrastructure hypothesis. (Infrastructure investigation guidance is referenced — see `skills/_shared/infrastructure-investigation.md` per §14.3 extract.)

Persist к state.md `## Hypotheses` body section, one block per hypothesis (Hypothesis / Evidence For / Evidence Against / Status: pending → testing → confirmed | rejected | inconclusive / Test Plan / Result: per §11.1.B schema).

### 6.6 Test each hypothesis + missing-data gate

- Design а minimal test per hypothesis. The test must produce а captured artifact per Evidence Standard kind 2-5.
- Add logging, breakpoints, или unit tests к gather evidence.
- Do NOT implement а fix yet — you're gathering data.
- **Missing-data gate (preserved from pre-M7 Step 3):** if testing requires data the orchestrator's tools cannot reach (production logs, runtime state, third-party API responses, DB rows behind credentials, screenshots), do NOT mark the hypothesis inconclusive by default. `AskUserQuestion` с header "Missing data" — 2-4 concrete options for the specific artifact needed.
- Record results: confirmed / rejected / inconclusive. Every Result: field MUST cite an artifact. "Confirmed" с narrative-only Result is rejected.

State.md `phase: investigate` throughout. `## Hypotheses` body section grows iteratively.

### 6.7 Isolate root cause → [ROOT-CAUSE] finding

Once а hypothesis is confirmed:
- Identify exact code location. Trace data/control flow.
- Understand why the bug happens (not just where).
- **Tag emitted findings per `skills/_shared/finding-tagging.md`.** `/geniro:debug` is the root-cause flow by definition — а confirmed hypothesis isolates к а `[ROOT-CAUSE]` finding, NOT `[SYMPTOM]`. `[UNKNOWN]` from debug is а failure mode — should not ship. If you find yourself emitting `[UNKNOWN]`, the hypothesis loop didn't close (escalate via §6.8 stall gate). `[SYMPTOM]` from debug is also а failure mode — re-enter §6.5 с а new hypothesis.

Persist к state.md `## Root Cause` body section.

### 6.8 Stall escalation gate (P-M7-2 closure)

When the hypothesis loop fails к converge — defined as **5 inconclusive hypothesis tests across all hypotheses** — fire the stall gate before declaring the bug unsolvable:

1. **Do not silently report "cannot determine cause".**
2. **Apply the P-M7-2 8-component diagnose-by-missing-component taxonomy** (full taxonomy in §10).
3. **Surface к user via `AskUserQuestion`** с header "Stall diagnosis" — render the 8 categories as concrete options. Each option's `label` (1-5 words) names the missing component; `description` carries the one-line trade-off; `preview` (where helpful) shows what the next action would be if picked.
4. State.md marks `phase: phase-1-escalated` с timestamp + inconclusive-test count + categorized stall hypothesis. Exit transitions:
   - User picks (A-G — а concrete missing artifact / category) → `phase: investigate` (resume hypothesis loop с new data).
   - User picks (H — "abandon — present partial findings") → `phase: ship-summary-only` (proceed к Phase 3 §8 с а stall-flagged findings summary; receiving skill is informed the cause was not isolated).
   - User can also pick "abort" → `phase: aborted` (terminal).

State.md `## Open Questions` body section logs the stall question + categorized hypothesis. M3 §6 Block 5c renders this on resume.

---

## 7. Phase 2 — Propose — **DECIDED**

State.md `phase: propose`. Output authoring: text fix proposal + F→P reproduction test. No production-source edits applied. Exits к Phase 3 when fix proposal AND reproduction test are both verified.

### 7.1 L4 refresh entry (single — no double-refresh)

On Phase 2 entry, single `load-custom-instructions(MODE: refresh, scope: debug + global + code-style)` call. Mirrors M4 §13.4 Phase 3 entry contract: always re-fires, drops the conditional-on-marker pattern (no M3 marker dependency). Cost: 1 helper read, within master plan §102 typical baseline.

Drops pre-M7 Step 5 + Step 6 double-refresh (D14 closure) — once at Phase 2 entry covers both Multi-path fix gate (§7.2) и Reproduction test authoring (§7.4).

### 7.2 Multi-path fix gate (Always-WAIT, P-M1-1-aware)

If the confirmed root cause has more than one valid fix path с real trade-offs (e.g., snapshot-vs-live-fetch, COALESCE vs CHECK constraint vs catch+log, fix-at-source vs fix-at-call-site), do NOT pick one и write а single text proposal.

**Fire `AskUserQuestion` per the canonical shape at `skills/_shared/per-finding-question.md` § Investigation-driven fix gate (debug-flavored)**:
- `header: "Fix path"`
- `question` text: confirmed root cause's `path:lines` + hypothesis title
- Each option:
  - `label` (1-5 words) — name of the path
  - `description` — one-line trade-off
  - `preview` — investigation context (Root cause / Evidence from `## Hypotheses`/Hypothesis-confirmed status + number)

**Approvals-persistence (P-M1-1 producer-side contract, D13 closure):** before firing, check state.md frontmatter `approvals[]` for а prior entry с `category: multi_path_fix` and matching `root_cause` (use root-cause text as the disambiguator). If found, use the prior `picked` value. If not, fire AUQ → on user pick, append entry к `approvals[]` via M1 `atomic_state_write`.

**Re-ask trigger:** if the root cause changes (е.g., second-pass investigation overturns the prior root cause), the prior `approvals[]` entry is treated as stale — clear it и re-fire. М3 §6 Block 5d renders this from `approvals[]` on resume.

The single-text-proposal default below applies ONLY when there is one obvious right fix; multi-path is the explicit branch.

### 7.3 Text fix proposal

- Formulate the minimal fix for the root cause as а **text proposal**: file path(s), exact change (unified diff или before/after snippet), one-sentence rationale.
- Do NOT write the fix to production/source files. Write/Edit are available для EXPERIMENTS only (tests, logging, debug scripts, `.geniro/state/debug/<slug>/` artifacts) — not for applying the proposed patch.
- If any experiment modified non-test source, revert those edits before escalation; the escalated skill applies the real fix cleanly.
- Do NOT refactor adjacent code.

Persist к state.md `## Proposed Fix` body section.

### 7.4 Author F→P reproduction test + monkey-patch verify

**Author the reproduction as а unit/integration test в the project's test framework**, placed at the project's normal test path next к the source it covers. Detect framework + naming convention от CLAUDE.md Essential Commands + an exemplar test file. Scripts / curl / ad-hoc queries are NOT acceptable substitutes — they get deleted at Cleanup и leave no regression guard.

**Test name + comments rule (preserved verbatim from pre-M7):** the reproduction test name AND any comments inside the test describe the bug behavior — the input, condition, или observable failure — never the hypothesis number from `## Hypotheses` или any other thread-local label. Tags like `Bug A/B/C`, `Hypothesis 1/2`, `Test 1`, `Case X`, `Issue #N from this run`, `regression from review run`, `found by review-gate`, или `confirmed by this <skill> run` are meaningless once the investigation ends. Prefer `cacheKey omits userId so role change leaves stale cached profile` over `Bug C`.

**F→P invariant.** Pre-fix: run the authored test ≥2× и confirm the SAME failure signature both times (same exception type + same failing assertion). Two divergent failures are NOT confirmation — investigate flakiness or two bugs before continuing.

**Verify the proposed fix — monkey-patch в the test by default; production-source edits are an explicit escape hatch.** Apply the patch locally as а monkey-patch inside the authored test file (mock, fixture, test-local shim, or а throwaway helper imported only by the test). Re-run the authored test ≥2× post-fix и confirm the failure DISAPPEARS both times. If the bug genuinely cannot be verified without editing production source (hard-to-mock chain — DI container, framework hook, native module, generated code), list every touched production file under "Verification edits to revert:" в the §8.1 findings, confirm each is reverted before escalation, и re-run `git diff` to prove the working tree contains only the reproduction test.

**Escape hatch — non-deterministic bugs only.** If the bug is genuinely non-reproducible at the test layer (race conditions only seen under load, environment-only failures, UI flake), `AskUserQuestion` per the canonical shape at `skills/_shared/per-finding-question.md` § Investigation-driven fix gate:
- `header: "Repro infeasible"`
- `question`: best-guess root-cause `path:lines` (or "unknown" if not isolated) + hypothesis title
- Options: regression-guard alternatives — "Add runtime assertion" / "Author fuzz seed" / "Add monitor/alert" / "Skip regression guard" (with description carrying one-line trade-off)

Record the user's selection AND rationale в state.md `## Reproduction Test` body section under "Reproduction Decision". The default is mandatory; escape hatch is opt-in с а paper trail.

Do NOT run the full project test suite here — that's the receiving skill's responsibility. Phase 2's goal is the F→P-verified test artifact + evidence the proposed patch turns it green.

If the project uses code generation (check CLAUDE.md) AND the proposed fix touches DTOs/schemas/controllers: note this в the §8.1 findings template "Special handling" field.

### 7.5 Fix-loop escalation (2 fix attempts failed → AUQ)

When 2 distinct fix proposals fail F→P verification (each pre/post-fix monkey-patch round counts as one), surface к user — mirrors M4 §7.4 escalation pattern:

1. Do **not** silently report "no fix works".
2. `AskUserQuestion` с header "Fix-fail" и options:
   - **Try different approach** — go back to §6.5 (Hypothesize) с а fresh angle. State.md transitions back к `phase: investigate`.
   - **Accept as documented limitation** — proceed to Phase 3 ship sub-step с `## Accepted Limitations` block в state.md body. State.md transitions к `phase: ship`. Receiving skill sees the unresolved limitation in the §8.1 findings summary.
   - **Abort** — `phase: aborted` (terminal).
3. State.md marks `phase: phase-2-escalated` с timestamp + fix-attempt count + accumulated test outputs. M3 §6 Block 5c renders open question on resume.

---

## 8. Phase 3 — Ship — **DECIDED**

State.md `phase: ship`. Findings handoff к downstream skill OR user-handles. No `git push` / `gh pr create` — debug never ships code, only proposals + tests authored locally.

### 8.1 Present findings (chat + persist T2 handoff)

Before asking where к route the fix, present а human-readable findings summary к the user. Do NOT jump straight к the escalation AUQ — the user chooses the escalation target based on this summary.

Output the markdown block directly в chat AND write the same content (с full M1 §T2 frontmatter wrapping it) к `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`. Resolve `<PRIMARY_ROOT>` per `skills/_shared/primary-worktree.md` Mode A so the handoff survives worktree teardown.

**Findings template body (preserved from pre-M7 §6.5a, schema-extended):**

```markdown
## Debug Findings

**Source branch:** [from `git branch --show-current`]

**Source worktree:** [from `git rev-parse --show-toplevel`]

**Why escalating to <target>:** [one sentence — which target и concrete reason scope fits it; user makes final routing choice в §8.2]

**Root cause:** [one sentence, plain language — why the bug happens]

**Reproduction:** [exact steps that trigger the bug]

**Confirmed hypothesis:** [which numbered hypothesis from `## Hypotheses` was confirmed, и the test result that confirmed it]

**Rejected hypotheses:** [brief — which hypotheses were ruled out и why]

**Proposed fix:**
- Files: [path(s) that need to change]
- Change: [unified diff или before/after snippet]
- Rationale: [one sentence tying the change to the root cause]

**Evidence the fix works:** [what happened when you applied the patch (default: "failing test went green under in-test monkey-patch; production source untouched"); или "<n> production files edited as escape hatch и reverted; bug stopped reproducing"]

**Reproduction test:** [<path>, <F→P status — example: "verified red on current code; verified green under throwaway patch">  — OR — "escape hatch: <alternative guard с rationale>"]

**Special handling:** [codegen, migrations, schema changes, env/config updates — или "none"]

**Stall-flagged?** [omit if Phase 1 stall gate did NOT fire; if it did: "Yes — cause not fully isolated; <P-M7-2 component> identified as missing. Receiving skill should treat this as а starting point, not а closed investigation."]

**Accepted limitations?** [omit unless §7.5 fix-fail path "B — accept" was taken; if so: "<description of limitation>; user accepted on <ISO timestamp>"]
```

The receiving skill pre-loads findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` — the state file is the handoff channel, not а chat paste. Do NOT re-derive, reword, or inline the summary into the escalation command; the file path IS the contract.

### 8.2 Escalation AUQ (4 options)

Only after the summary above is visible AND persisted, `AskUserQuestion` с header "Escalate" и these options:

- **Trivial — run `/geniro:implement`; pre-load findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`** — ≤2 files, obvious target, no architecture или auth/permissions change. (Note: pre-M7 routed trivial к /follow-up, но master plan §66 absorbed /follow-up into /implement; M4 handles any size via spec input.)
- **Non-trivial — run `/geniro:implement`; pre-load findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md`** — touches multiple modules, changes interfaces, needs architecture review, или introduces а new pattern. Same target as Trivial; the size designation surfaces в the spec context the receiving skill loads (M4 §5.4 «Inputs from <producer>» persist).
- **Cannot verify — request specific data from user** — pick this when one or more hypotheses are unverified because the orchestrator's tools cannot reach the artifact. Trigger а follow-up `AskUserQuestion` с concrete options for the missing data. When data arrives, return к §6.6, do NOT escalate yet.
- **Leave it to me** — user will apply the patch manually using the state file as reference. State.md transitions к `phase: ship-summary-only` (terminal).

Do NOT auto-invoke the next skill — surface the suggestion only. State file IS the handoff channel. You do NOT apply the patch yourself.

### 8.3 L2 auto-emit + L4 promotion suggestion (P-M4-5 mirror)

Replaces deleted `/learnings` skill (master plan §69). At Phase 3 exit:

- **`emit-learning` (M2 §5.2)** — called by /debug after а confirmed root cause. Per M2 §5.3 «Auto-emit triggers per skill» canonical contract, the **only** emit type for /debug is `diagnosis`:
  - **`diagnosis`** (sole M7 emit type) — every confirmed root cause emits one entry с summary, tags (inferred от affected-files + hypothesis category), scope (project-relative path glob), и `ext.{symptom, root_cause, fix}` per M2 §5.2 typed-extension table. Default trust `verified` per M2 §5.3 row.
  - **NOT emitted by M7:** `pitfall` (owned by /refactor + /review per M2 §5.3); `convention` (owned by /implement self-review reviewer-agent per M2 §5.3 — debug doesn't ship code); `decision` (owned by /plan); `discovery` (owned by /refactor + /onboard + /investigate).

- **L4 promotion suggestion (P-M4-5 mirror — D8 closure):** when the §6.2 prior-knowledge query returned **≥1 matching prior diagnosis** (recurrence signal — the same bug pattern was hit before), surface а one-line suggestion в the Phase 3 final report:

  ```
  [learnings] Diagnosis recorded: "<one-line summary>". Recurrence detected (<n> prior matching entries). Recorded к L2.
    → Consider /geniro:instructions edit <scope>.md к promote as а debug-rule.
  ```

  Scope hint follows the diagnosis category:
  - Style/convention root causes → suggest `code-style.md`
  - Workflow/process root causes → suggest `debug.md`
  - Architecture/global root causes → suggest `global.md`
  - Other → generic "appropriate scope"

  Suggestion fires only when recurrence is detected (Phase 1.1 query-learnings returned ≥1 prior matching entry) — single-occurrence diagnoses не warrant L4 promotion (user remains source-of-truth для L4 curation; auto-promotion creates noise + drift). The line is informational (no AUQ, no auto-edit). Closes the feedback loop: recurring bug pattern → L2 episodic (auto) → L4 procedural (user opt-in). Fully automatic L2→L4 promotion deferred к P-X6.

  **Recurrence signal source:** Phase 1.1 `query-learnings(tags=inferred from $ARGUMENTS)` already runs at session start (§6.2). Its result count IS the recurrence signal — no additional query needed at Phase 3 exit. If Phase 1.1 returned 0 matching entries, the current run is а novel diagnosis и promotion is not suggested.

### 8.4 Suggest improvements (project scope only, M2 §5.4 routes)

After L2 emit, follow the canonical routing в `skills/_shared/improvement-routing.md`. Debug runs typically surface:

| Insight category | Target | M2 layer |
|---|---|---|
| Coding conventions / naming patterns discovered during isolation | `.claude/rules/<scope>.md` с `paths:` glob frontmatter (Anthropic-native, file-scoped — auto-loads when matching files are touched) | L4 procedural |
| Docs describing behavior not matching reality | `CLAUDE.md` или project docs | L3 semantic |
| New/changed commands discovered during debugging | `CLAUDE.md` (Essential Commands section) | L3 semantic |
| Non-obvious debugging insights / workarounds | `.geniro/knowledge/learnings.jsonl` (via `emit-learning`) | L2 episodic |
| Skill-behavior quality gates / workflow steps user enforced manually | `.geniro/instructions/debug.md` или `.geniro/instructions/global.md` | L4 procedural |

Plugin-internal paths (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope — use `/improve-template` (out of M7 design — а separate user-facing channel).

### 8.5 Cleanup

After Phase 3 completes (escalated, accepted, or user-handles):

- **Scientific-method mode only:** Remove `<PRIMARY_ROOT>/.geniro/state/debug/<slug>/state.md` for the current branch's slug only, per `skills/_shared/within-skill-state-handoff.md` § Cleanup contract — its useful content is already saved (root cause, repro, hypotheses-tested-and-rejected, accepted limitations) via L2 emit + persisted handoff. Do NOT delete sibling slugs from concurrent debug sessions on other branches.
- **Clear five legacy generations** (best-effort; any may not exist):
  ```bash
  rm -f ".geniro/debug/HYPOTHESES.md" 2>/dev/null                      # Gen 1: original (pre-state-dir, non-scoped)
  rm -f ".geniro/debug/HYPOTHESES-${slug}.md" 2>/dev/null               # Gen 2: intermediate (pre-state-dir, slug-scoped)
  rm -f ".geniro/state/debug/HYPOTHESES-${slug}.md" 2>/dev/null         # Gen 3: pre-M7 (under state-dir, slug-scoped)
  rm -f ".geniro/state/debug/findings-state.md" 2>/dev/null             # Gen 4: pre-M7 T2 handoff
  rm -f ".geniro/state/debug/adversarial-tests.md" 2>/dev/null          # Gen 5: pre-M7 adversarial T2 handoff
  ```
- **Scientific-method mode only:** Remove debug scripts, scratch reproductions, the §6.4 feedback-loop scratch signal, и ad-hoc curl/query files created during investigation. The §7.4 reproduction test (authored at project's normal test path) STAYS on disk — it ships with the fix as the regression guard. The feedback-loop signal is intentionally throwaway; if its content was load-bearing, it has already been promoted к the reproduction test.
- **Scientific-method mode only:** `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` MUST remain on disk as the escalation handoff channel — do NOT delete. It stays until the next debug run overwrites it (single file per branch).
- Kill any background processes started during investigation (dev servers, watchers, profilers).
- **Adversarial mode:** `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` may remain as audit trail; authored test files stay on disk (unlike scientific-method experiments which get reverted).

Cleanup is best-effort — if а command fails silently, that's fine.

### 8.6 Atomic non-resumable updates

After each side-effect that cannot be replayed safely (none в baseline M7 — debug performs no `git push` / `gh pr create`), append а structured entry к state.md frontmatter `non-resumable-actions[]` via M1 `atomic_state_write`. Mirrors M4 §7.5 step 4.

The empty baseline is intentional: debug ships proposals, not commits. If а future user-customization introduces side-effects (e.g. а `.geniro/actions/post-finding-к-slack.md` invocation), THAT action becomes а non-resumable entry — not the standard ship flow.

---

## 9. Adversarial Mode (verify-changes) — preserved per Q1

State.md `mode: adversarial`. Phases: `adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship`. Parallel к Scientific Mode (§6-§8); shared mode-detect (§6.1) routes here on anchored verify-keyword signals.

### 9.1 Mode triggers (preserved from pre-M7 SKILL.md:46-50)

Anchored verify-keyword signals (full table preserved verbatim в SKILL.md re-implementation):
- `verify <changes|diff|last|recent|my|this|PR>`
- `break <my|the> diff`
- `hunt for bugs in <diff|change|PR>`
- `find edge cases in <diff|change|PR>`
- `adversarial <mode|pass|scan|run>`
- `stress-test <the diff|my change|last changes>`
- Phrase signals: `verify last changes` / `verify recent changes` / `verify my changes` / `check last changes` / `break my diff`
- Explicit diff range signals: `HEAD~N..HEAD`, `HEAD~N`, `main...HEAD`, bare PR ref (`#1234` или GitHub PR URL), bare branch name + verify keyword

Bare keywords alone NOT enough — anchored only.

### 9.2 Diff resolution

**Delegates к /review Phase 1 multi-form parser.** See `skills/review/SKILL.md` §Phase 1: Collect Context & Triage — do NOT duplicate the parser here.

**Default when no explicit range:** scope follows `skills/_shared/scope-anchor.md` — anchor on the current cwd's worktree + currently-checked-out branch. Resolve the base branch per scope-anchor rule #3 (`git symbolic-ref --short refs/remotes/origin/HEAD`). Compute `git diff <base>...HEAD`. If on the base branch, fall back к `HEAD~1..HEAD`.

**Supported shapes:** preserved from pre-M7 §B (bare keyword / explicit range / branch / PR ref).

### 9.3 Skip conditions

Mirror the canonical skip-matrix philosophy at `skills/_shared/scope-anchor.md`. Adversarial mode is SKIPPED и the skill reports `"no adversarial pass — <reason>"` when:

- Empty diff (nothing к test).
- Diff contains zero production-code files (docs / config / lock / generated only).
- Diff >50 changed files OR >1000 changed LOC → suggest `/geniro:review` для oversized diffs (the agent's 10-test hard cap wastes budget on diffs this large).

### 9.4 RED-phase workflow

Mirrors pre-M7 §D verbatim в spirit:

1. **Resolve the diff** (§9.2). Pre-inline full diff + changed-file contents для the spawn prompt.
2. **Detect the project test framework.** Read CLAUDE.md Essential Commands + `package.json` scripts / `pyproject.toml` / `Cargo.toml` к extract test command, naming convention, и 1-2 exemplar test files closest к changed code.
3. **Spawn `adversarial-tester-agent`** к AUTHOR RED tests. Apply the runtime-degradation ladder per `skills/_shared/spawn-agent.md` (prefixed → bare → general-purpose с inline body). The agent writes failing tests against today's code; no fix is authored.
4. **Independently verify RED.** Read the agent's report at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`, extract authored test file paths, run the project test command **once per authored test** (single independent re-run — the agent already ran а 3× flake check per its Step 5). Tests that do not fail deterministically are deleted from disk AND removed from the report. This is the orchestrator-side RED-verification per `skills/_shared/tdd-cycle.md` § RED phase Step 3.
5. **Present Adversarial Findings** (§F template preserved).
6. **Escalate fix authoring** — reuse §8.2 escalation AUQ (Trivial / Non-trivial / Cannot-verify / Leave-it-to-me) с findings file path referencing `from-debug-adversarial-<branch>.md` instead of `from-debug-<branch>.md`. The authored test file paths inside are the escalation targets. The receiving skill writes the fix и runs GREEN verification (`tdd-cycle.md` § GREEN phase). If zero red tests survived re-verification, SKIP §8.2 entirely — report `"no bugs found in scanned diff"` и go directly к Cleanup.

State.md `## Authored Tests` body section tracks each authored test path + status (kept / discarded).

### 9.5 State.md mode=adversarial schema

`state.md` frontmatter и body sections specialize when `mode: adversarial`. See §11.1.C для the schema differences.

### 9.6 Findings persistence

T2 handoff at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` per M1 §T2 row (M1:503). M1 §T2 frontmatter base + M7-adversarial extensions per §11.3.

### 9.7 Escalation (reuse §8.2 AUQ)

The escalation option labels MUST reference `from-debug-adversarial-<branch>.md` by path (e.g., "Trivial — run `/geniro:implement`; pre-load findings from `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`") — preserves pre-M7 §D Step 6 contract.

If zero red tests survived re-verification, SKIP §8.2 entirely — terminal state `adversarial-aborted` с `## Termination reason: no-bugs-found-in-diff`.

---

## 10. P-M7-2 — Diagnose-by-missing-component taxonomy

Per master plan §337: when /debug stalls (5 inconclusive hypothesis tests across all hypotheses, per §6.8), classify the root-cause-of-the-stall as а missing component. 8-component taxonomy:

| # | Missing component | Symptom | AUQ option label | AUQ description |
|---|---|---|---|---|
| A | **Missing instruction** | Hypothesis tests don't converge because the orchestrator lacks а project-specific rule (e.g., "we use SQS not Kafka here") | "Missing project rule" | Paste the rule або point к а CLAUDE.md / `.geniro/instructions/*` section |
| B | **Missing source-of-truth** | Test results contradict reasonable assumptions because canonical state (DB row, prod log line, third-party API response) is unreachable | "Missing source of truth" | Paste the DB row / log line / API response (matches pre-M7 missing-data gate) |
| C | **Missing tool** | Orchestrator cannot read the artifact format (binary blob, proprietary protocol, sandboxed environment) | "Missing tool" | Provide the parsed/decoded form, or specify а tool the user can run locally |
| D | **Missing validator** | Hypothesis tests "pass" via narrative-only Result but cannot be objectively verified (e.g., race-condition theories) | "Missing validator" | Author а deterministic re-runnable check (curl + grep, SQL query, regex on log) |
| E | **Missing permission rule** | Hypothesis blocked by safety-hook or `.geniro/safety.json` denial (e.g., file-protection on а needed test write) | "Missing permission" | Add the relevant pattern к `.geniro/safety.json` `allow_patterns` (advise specific ID) |
| F | **Missing sandbox signal** | Tests inconclusive because environment differs от production (Docker vs. host, ARM vs. x86) | "Missing sandbox signal" | Re-run в the production-like environment и paste the captured signal |
| G | **Missing eval** | Bug type has no existing regression test pattern в the project — hypotheses cannot be expressed в the existing test framework | "Missing eval pattern" | Author а new test pattern (parameterized fuzzer, mutation-test seed, etc.) |
| H | **Missing recovery path** | All hypotheses confirmed но the fix path is unclear because the bug spans а DI / generated-code / framework-internal layer | "Missing recovery path" | Specify whether the production-source escape hatch (§7.4) is acceptable, или escalate как architectural |

**AUQ rendering:** Phase 1 §6.8 stall gate fires `AskUserQuestion` с header "Stall diagnosis". Render 4 of the 8 categories at а time (`AskUserQuestion` maxItems=4) — model picks the most likely 4 based on stall context (inconclusive-test outputs, hypothesis types tried). User picks one or "Other" к open-ended-respond. Selected option's `description` is the actionable next step.

Each option's `preview` (where helpful) shows what Phase 1 will do next: е.g., for option D (missing validator), preview shows а draft validator-script outline based on the failing hypothesis. Helps user gauge whether the option matches their understanding before picking.

State.md `## Open Questions` body section logs the stall AUQ + user's pick + delivered artifact (if applicable). M3 §6 Block 5c renders on resume.

---

## 11. State file schema

### 11.1 state.md (M1 §T1 base + M7 extensions)

#### 11.1.A — Frontmatter

```yaml
---
tier: T1                       # M1 §T1 required
producer: debug                # M1 §T1 required
schema-version: 1              # M1 §T1 required
branch: <git-branch>           # M1 §T1 required
timestamp: <ISO-8601 UTC>      # M1 §T1 required
phase: <enum>                  # M1 §T1 required — values per §2.1 state machine
status: <in-progress|done|failed>  # M1 §T1 required
non-resumable-actions: []      # M1 §T1 required
approvals: []                  # M1 §T1 optional (P-M1-1 schema)
geniro_kind: debug-state       # M7 schema marker (informational; M1 §Frontmatter contract §Producer-specific extensions)
geniro_schema_version: m7-v1   # M7 producer schema-version marker
mode: <scientific|adversarial> # M7 extension — discriminator for body sections
task_slug: <slug>              # M7 extension — slug per `skills/_shared/within-skill-state-handoff.md` § Slug rules
worktree: <abs-path>           # M1 §T1 optional, M7 strongly recommended
---
```

#### 11.1.B — Body sections (Scientific Mode)

```markdown
## Inputs from <producer>        # (optional, present когда T2 input was consumed at Phase 1)

## Symptom

[plain-language description of what's broken]

## Reproduction Steps

[exact steps that trigger the bug]

## Feedback Loop

**Command:** [exact command/script that reproduces]
**Expected output:** [what happens on а working system]
**Actual output:** [captured artifact — error / log line / wrong value]
**Re-run cost:** [seconds; flag if >30s]
**Determinism:** [3-run signature comparison; flag if divergent]

## Hypotheses

### Hypothesis 1
- **Hypothesis:** [specific testable claim]
- **Evidence For:** [...]
- **Evidence Against:** [...]
- **Status:** pending → testing → confirmed | rejected | inconclusive
- **Test Plan:** [...]
- **Result:** [captured artifact per Evidence Standard kind 1-5 — narrative-only NOT allowed]

### Hypothesis 2 [...]

## Root Cause

[once а hypothesis is confirmed]

## Proposed Fix

[file path(s), unified diff or before/after snippet, one-sentence rationale]

## Reproduction Test

[<path>, F→P status, или escape-hatch reproduction decision с rationale]

## Accepted Limitations              # (optional, §7.5 path B)

## Tool log                          # M3 §6 selective logging (adversarial-tester-agent spawns, stall escalations)

## Errors                            # M3 §6 Block 5b — error observations carried across compaction

## Open Questions                    # M3 §6 Block 5c — stall AUQ + outcome

## Termination reason                # M3 §6 — only present on terminal aborted-state

## Persisted approvals               # M3 §6 Block 5d — render of frontmatter approvals[]
```

#### 11.1.C — Body sections (Adversarial Mode)

```markdown
## Diff Scope

[range + file count + LOC]

## Hypothesis Seeds

[from upstream — typically "none" since adversarial is а fresh pass; non-empty if а prior /review surfaced findings]

## Authored Tests

| # | Path | Targeted source | Category | Confidence | F→P status |
|---|---|---|---|---|---|
| 1 | test/auth.test.ts | src/auth.ts:42 | AUTH | HIGH | kept (RED verified) |
| ... |

## Re-verification Results

[orchestrator's re-run outcomes; tests removed = discarded]

## Tool log                          # M3 §6 selective logging (adversarial-tester-agent spawn outcome)

## Errors                            # M3 §6 Block 5b

## Termination reason                # M3 §6 — only on adversarial-aborted state
```

### 11.2 from-debug-<branch>.md (M1 §T2 base + M7 extensions, Scientific Mode)

T2 handoff at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md` per M1 §T2 row (M1:502). Single file per branch, overwritten on next debug run.

```yaml
---
tier: T2                                  # M1 §T2 required
producer: debug                           # M1 §T2 required
consumer: implement                       # M1 §T2 required (also valid: any post-debug skill loading this file)
schema-version: 1                         # M1 §T2 required
branch: <git-branch>                      # M1 §T2 required
timestamp: <ISO-8601 UTC>                 # M1 §T2 required
worktree: <abs-path>                      # M1 §T2 optional, M7 strongly recommended
geniro_kind: debug-handoff                # M7 schema marker
geniro_schema_version: m7-v1              # M7 producer schema-version marker
mode: scientific                          # M7 extension — discriminator
phase: ship                               # M7 — last-known phase
status: done                              # M7 — Phase 3 exit status
approvals: []                             # P-M1-1 — render via §8.1 "## Persisted approvals" body
non-resumable-actions: []                 # M7 — typically empty (debug ships no commits)
---
```

**Note on T2 + state-tracking extensions** (mirrors M6 §15.2 framing): Canonical M1 §T2 is а one-shot producer→consumer handoff. M7 extends с `phase:`/`status:`/`approvals[]`/`mode:` к enable mid-run compaction recovery (M3 SessionStart hook reads this file on resume) and к persist one-time approvals taken during the run. The file functions as а T2 handoff AT REST (after §8.1 persist) и as а state-tracking-extended document DURING THE RUN.

Body: full content of §8.1 findings template, plus M3 body sections (`## Tool log` / `## Errors` / `## Open Questions` / `## Persisted approvals`).

### 11.3 from-debug-adversarial-<branch>.md (M1 §T2 base + M7 extensions, Adversarial Mode)

T2 handoff at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` per M1 §T2 row (M1:503).

```yaml
---
tier: T2                                  # M1 §T2 required
producer: debug                           # M1 §T2 required
consumer: implement                       # M1 §T2 required
schema-version: 1                         # M1 §T2 required
branch: <git-branch>                      # M1 §T2 required
timestamp: <ISO-8601 UTC>                 # M1 §T2 required
geniro_kind: debug-adversarial-handoff    # M7 schema marker
geniro_schema_version: m7-v1              # M7 producer schema-version marker
mode: adversarial                         # M7 extension — discriminator
phase: adversarial-ship                   # M7 — last-known phase
status: done                              # M7 — Phase 3 exit status
non-resumable-actions: []                 # typically empty
---
```

Body: Adversarial Findings template (§9.4 step 5, preserved from pre-M7 §F) + M3 body sections.

---

## 12. Memory I/O (M2 §13 obligation — OQ-M7-1 closure)

### 12.1 Helper-call schedule

| Phase | Helper | Direction | MODE | Inputs | Outputs | Notes |
|---|---|---|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` | scope = `debug` + `global` + `code-style` | concatenated rules inlined | Echo contract per M3 §7.2. M3 SessionStart re-injects on compaction. |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` | top-2 default (`_project.md` + `_CODEBASE_MAP.md`) | inlined into context + drift check | Drift notification surfaces к user if `.fingerprint.json` mismatched. |
| Phase 1 entry | `query-learnings` | read L2 | n/a | tags inferred от $ARGUMENTS (e.g., `cache`, `race-condition`, `infra`); scope = task path | top-K matching entries (K=5 default, filter superseded + deprecated) | Per M2 §5.3 «debug session start» trigger. Replaces pre-M7 Step 0 ad-hoc Grep. |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a | three layers | precedence-resolved или AUQ on hard conflict | Per M2 §10 cross-layer resolution. |
| Phase 1 (hypothesis loop) | none | — | — | — | — | No additional helper calls. L2 results already в context. |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` | same scope as Phase 1 | re-inlined | Single re-fire — drops pre-M7 double-refresh (D14 closure). |
| Phase 3 exit (§8.3) | `emit-learning` | write L2 | n/a | producer = `/geniro:debug`; type = `diagnosis` (sole M7 emit type); scope = changed-file paths or generalized; required `ext.{symptom, root_cause, fix}` | append к `learnings.jsonl` | Dedup + sanitization per M2 §5.2. Default trust `verified` per M2 §5.3. |
| Phase 3 exit (§8.5) | M1 `atomic_state_write` | write T1 | n/a | state.md path; non-resumable entry (typically empty) | whole-file rewrite | Fires only if а side-effect was performed. Baseline M7 has none. |

### 12.2 L2 emit triggers (per M2 §5.3 canonical contract — strict alignment)

| Type | When M7 emits |
|---|---|
| `diagnosis` | **Sole M7 emit type.** Every confirmed root cause (§6.7) emits one entry с summary, tags (inferred от affected-files + hypothesis category), scope (project-relative path glob), и required `ext.{symptom, root_cause, fix}` per M2 §5.2 typed-extension table. Default trust `verified` per M2 §5.3. |
| `pitfall` | NOT emitted by M7. /refactor (footgun) и /review (stratified high-severity) own this trigger per M2 §5.3. |
| `convention` | NOT emitted by M7. /implement self-review (M4 §7.2 architecture/code-quality reviewer ≥3-pattern detection) owns this trigger per M2 §5.3 — debug doesn't ship code. |
| `decision` | NOT emitted by M7. /plan (M5) и /implement inline-task mode own this trigger. |
| `discovery` | NOT emitted by M7. /refactor (M8), /onboard (M9), и /investigate (M9) own this trigger. |

### 12.3 L3 update sites

`update-semantic` is NOT called by M7. Debug investigates existing code; it does not add modules, move files, or rename — those are /implement и /refactor concerns. (Exception: if Phase 2 fix proposal happens to add а module, that update is the receiving skill's responsibility, not /debug's.)

### 12.4 Phase boundary refresh sites (M3 §7.3)

| Boundary | Refresh action | Why |
|---|---|---|
| Phase 1 entry | `load-custom-instructions(MODE: refresh)` + `load-semantic(MODE: refresh)` | Initial context load |
| Phase 2 entry | `load-custom-instructions(MODE: refresh)` — **always** | Survive Phase-1 compaction без M3 marker dependency; mirror M4 §13.4. Cost: 1 extra helper read (4 total per run within typical baseline). |
| Phase 3 entry | none | Phase 2 refresh covers Phase 3 — no additional code-writing happens; only findings persist + AUQ + emit |
| Phase 3 exit | none | Skill terminates; refresh not needed |

### 12.5 ACI per-phase tool surface (OQ-M7-3 closure)

Mirrors M4 §13.5 structure. Per master plan P-M4-6 revised к minimal scope — full 14-class risk taxonomy deferred к а future `_shared/risk-taxonomy.md` helper.

**Phase 1 (Investigate):**
- Allowed: Read / Grep / Glob / Bash (read-only commands like `git status`, `git log`, `git diff`, `git blame`, `git bisect`, test re-runs without code edits, log inspection, profiler invocations, third-party CLI like `psql -c` against test DB if configured).
- Allowed: Edit / Write для EXPERIMENTS only — debug scripts, logging statements, scratch test files, `.geniro/state/debug/<slug>/` artifacts.
- Explicitly blocked: production-source Edit/Write, `git push`, `gh pr create`, branch switching без user confirmation.

**Phase 2 (Propose):**
- Allowed: Read / Grep / Glob / Bash (read-only + experimental test runs).
- Allowed: Edit / Write для reproduction test authoring (§7.4) + experimental monkey-patches (§7.4 escape hatch).
- Explicitly blocked: production-source Edit/Write outside the reproduction test file, `git commit`, `git push`, `gh pr create`.

**Phase 3 (Ship):**
- Allowed: Read / Write (T2 handoff persistence), `emit-learning` helper invocation, `AskUserQuestion`.
- Explicitly blocked: `git commit`, `git push`, `gh pr create`, Agent spawns. Debug NEVER ships code.

**Adversarial Mode (§9.4 spawn):**
- `adversarial-tester-agent` runs under the spawn-agent ladder.
- Agent's tool surface inherited via the agent's frontmatter (out of M7 scope — owned by `agents/adversarial-tester-agent.md`).
- Orchestrator's re-verification step uses read-only Bash (run test command).

**Existing safety layer** applies across ALL phases: file-protection hook, git-guardrail hook, `.geniro/` deletion guard (CLAUDE.md § Safety Hooks). Runtime denies stay enforced regardless of ACI doc.

**Out of scope для M7 (deferred):** 14-class risk taxonomy + 7-decision matrix from agents-best-practices. Useful когда M8-M10 designs require cross-skill consistency.

---

## 13. Open questions

| ID | Topic | Status |
|---|---|---|
| **OQ-M7-1** | Memory I/O (M2 §13 obligation) | ✅ §12 |
| **OQ-M7-2** | Adversarial-mode finding-tagging | ✅ Preserves pre-M7 `finding-tagging.md` schema. No change. |
| **OQ-M7-3** | ACI per-phase tool surface | ✅ §12.5 minimal scope; full taxonomy deferred |
| **OQ-M7-4** | Stall-AUQ category prioritization (which 4 of 8 к render) | ⏳ Deferred к implementation-phase. Model picks the most likely 4 based on stall context (inconclusive-test outputs, hypothesis types tried). Empirical tuning happens during /debug rewrite. |
| **OQ-M7-5** | Approval persistence trigger (multi-path fix gate) — same root cause across resume vs. context change | ⏳ Deferred к implementation. Initial heuristic: stale если root-cause text changes; re-ask otherwise. Refine с empirical data. |

---

## 14. Cleanup checklist

### 14.1 `skills/debug/SKILL.md` — surgical edit (most preserved)

Pre-M7 SKILL.md (563 lines) maps cleanly к M7's 3-phase structure with mechanical re-headings. **Surgical edit, not full rewrite** — most semantic content (feedback-loop table, hypothesis tracking, multi-path gate, missing-data gate, F→P invariant, monkey-patch verification, adversarial workflow, isolation techniques, infrastructure investigation, compliance table) is preserved verbatim under new section headers.

**Sections к delete (line ranges from pre-M7 file):**

- L10-25: "Subagent Model Tiering" — references kept but moved to inline в Adversarial Mode §9.4 spawn site.
- L26-36: Title block "The Scientific Debug Loop" с 9-step header — replaced с 3-phase reference к §2 architecture overview.
- L118-120: Universal AskUserQuestion Rule — D10 closure (reference `per-finding-question.md`).
- L425-451: "Compliance — Do Not Skip Steps" — split into §16 anti-rationalization (most rows preserved verbatim) + М7 cross-cutting rows.
- Step 5 lines L197 + Step 6 line L204 «Refresh custom instructions» — one of the two deleted (D14 closure).

**Sections к rewrite в place:**

- L38-52: Step 0 mode routing → Phase 0 mode-detect (§6.1) — preserved verbatim including anchored verify signals table.
- L54-114: Hypothesis Tracking Format → §11.1.B state.md body section schema.
- L122-269: Workflow Steps 0 through 8 → §6/§7/§8 phase structure. **Mechanical re-headings only** (Step 0 → Phase 1.1, Step 1 → Phase 1.3, etc.). Sub-step content preserved verbatim except where M1/M3 schema differences apply (`HYPOTHESES-<slug>.md` → `state.md`, `findings-state.md` → `from-debug-<branch>.md`).
- L271-369: Adversarial Mode → §9 (Adversarial Workflow preserved verbatim, only state-file paths migrated).
- L371-379: Escalation Limits → §6.8 + §7.5.
- L381-391: Git Constraint + Fix Constraint → §12.5 ACI per-phase tool surface (folded).
- L393-423: Isolation Techniques + Infrastructure Investigation → moved to `skills/_shared/isolation-techniques.md` и `skills/_shared/infrastructure-investigation.md` (§14.3).
- L453-466: Cleanup → §8.5 (5-generation legacy clear).
- L468-501: Definition of Done → preserved verbatim, but Scientific-Method Mode checklist items reference new state-file paths.
- L505-563: When to Use / Examples → preserved verbatim under а new "## When к Use This Skill" heading post-phase 3.

**Target post-rewrite length:** ~600 lines (vs pre-M7 563 — slight increase due к M1 frontmatter schema documentation, but а material chunk migrated out к `_shared/` helpers compensates).

### 14.2 Legacy state file generations (D15 closure)

Three legacy generations to clear at Phase 3 §8.5 Cleanup:

1. `.geniro/debug/HYPOTHESES.md` (original — pre-state-dir, non-scoped)
2. `.geniro/debug/HYPOTHESES-${slug}.md` (intermediate — pre-state-dir, slug-scoped)
3. `.geniro/state/debug/HYPOTHESES-${slug}.md` (pre-M7 — under state-dir, slug-scoped)
4. `.geniro/state/debug/findings-state.md` (pre-M7 — T2 handoff before path migration)
5. `.geniro/state/debug/adversarial-tests.md` (pre-M7 — adversarial T2 handoff before path migration)

Listed как `rm -f` invocations in §8.5 (best-effort, 2>/dev/null wrapper).

### 14.3 `_shared/` helper updates

- `skills/_shared/infrastructure-investigation.md` (NEW) — extracted from pre-M7 `SKILL.md:402-423` (Infrastructure Investigation section). Referenced from §6.5 hypothesize step.
- `skills/_shared/isolation-techniques.md` (NEW) — extracted from pre-M7 `SKILL.md:395-398` (Isolation Techniques section). Referenced from §6.7 isolate step.
- `skills/_shared/per-finding-question.md` — verify § Investigation-driven fix gate (debug-flavored) section exists и matches §7.2 contract. If absent, add the section в the per-skill implementation PR.
- `skills/_shared/within-skill-state-handoff.md` — verify § Slug rules clause supports `.geniro/state/debug/<slug>/state.md` layout (subdir-per-slug pattern). If pre-M7 helper assumed flat `HYPOTHESES-<slug>.md` filename pattern, update к the subdir layout.
- `skills/_shared/spawn-agent.md` — verify Adversarial Mode `adversarial-tester-agent` spawn site follows the ladder. Already used pre-M7; no change expected.
- `skills/_shared/scope-anchor.md` — referenced by §9.2 diff resolution. No change expected (M7 consumes existing contract).
- `skills/_shared/evidence-standard.md` — referenced by §6.6 + §6.7 (hypothesis confirmation must cite an artifact kind 1-5). No change expected.
- `skills/_shared/finding-tagging.md` — referenced by §6.7 ([ROOT-CAUSE] tag) и §9 (Adversarial Mode findings carry CRITICAL/HIGH/MEDIUM severity). No change expected.
- `skills/_shared/tdd-cycle.md` — referenced by §9.4 RED-phase verification. No change expected.
- `skills/_shared/improvement-routing.md` — referenced by §8.4. Verify M2 §5.4 L4 routes table matches §8.4 contract; update if drift.
- `skills/_shared/effort-scaling.md` — line :49 references `/follow-up` Fast Lane (per M4 §9.3). M7 implementation PR should remove the row if M4 hasn't already.
- `skills/_shared/model-tiering.md` — verify `adversarial-tester-agent` row carries `inherit` per pre-M7 §Subagent Model Tiering note. No change expected.
- `skills/_shared/context-isolation-checklist.md` — referenced by §9.4 spawn. No change expected.

---

## 15. Master plan reconciliation

### 15.1 Skill-list status (master plan §20)

М7 finalizes 1 of the 11 surviving skills. State after М7 implementation:

| Skill | Source | Milestone owner |
|---|---|---|
| `/plan` | NEW — replaces `/brainstorm` + `/decompose` | M5 ✅ |
| `/implement` | Redesigned | M4 ✅ |
| `/review` | Consolidated | M6 ✅ |
| **`/debug`** | **Aligned with /implement simplification (this doc)** | **M7 (this doc)** |
| `/refactor` | Distinct zero-behavior-change guarantee | M8 ⏳ |
| `/onboard` | Codebase mapping | M9 ⏳ |
| `/investigate` | Codebase Q&A | M9 ⏳ |
| `/instructions` | CRUD `.geniro/instructions/*` | M10 ⏳ |
| `/actions` | CRUD `.geniro/actions/*` | M10 ⏳ |
| `/setup` | One-time project bootstrap | M10 ⏳ |
| `/update` | Plugin update | M10 ⏳ |

`/learnings` skill absorption complete via §8.3 L2 auto-emit (master plan §69 closure).

### 15.2 М7-specific obligations from master plan

| Master plan ref | Obligation | М7 status |
|---|---|---|
| §34 | "Bug investigation with hypothesis tracking. **Goal: locate the cause.**" | ✅ Preserved verbatim. Goal-statement repeats в §1. |
| §69 | /learnings auto-step replaces standalone skill | ✅ §8.3 L2 emit (mirror of M4 §7.5 step 5 + P-M4-5 promotion suggestion) |
| §119 | "Align with `/implement` simplification. Reuses M1–M3 conventions" | ✅ 3-phase mirror (§6/§7/§8); M1 §T1+§T2 frontmatter (§11); M3 body sections (§11) + Block 5d approvals (§7.2, §6.1); M2 helpers (§12) |
| §332 (P-M7-1) | 8-step feedback loop closing M2 L2 emit auto-step contract | ✅ §6 (validate state → §6.2 query-learnings; gather SoT → §6.3; propose → §7.3; execute → §7.4; validate against objective → §7.4 F→P invariant; capture proof → §7.4 monkey-patch verify; record → §8.1; feed recurring issues → §8.3 + §8.4) |
| §337 (P-M7-2) | Diagnose-by-missing-component taxonomy when /debug stalls | ✅ §10 + §6.8 stall gate AUQ rendering |
| §405 (P-X5 design guidance) | Budget section mirroring M4 §2.3 | ✅ §2.3 |
| Anti-patterns guardrail (P-MP-1) | Anti-pattern check audit | ✅ §16 |

### 15.3 Stale assumptions corrected

| Original /debug behavior | Corrected (M7) |
|---|---|
| Escalation routes к `/geniro:follow-up` (Trivial) или `/geniro:implement` (Non-trivial) | Both options route к `/geniro:implement` (master plan §66 absorbed /follow-up). The Trivial/Non-trivial labels survive for context, but the receiving skill is the same. |
| Pre-M7 `HYPOTHESES-<slug>.md` is canonical | Replaced by `.geniro/state/debug/<slug>/state.md` (M1 §T1 session-bound layout — second path-root в the M1 §T1 Path roots table, used by session-bound skills like /debug + /refactor). 5 legacy generations cleaned. |
| Pre-M7 `findings-state.md` at `.geniro/state/debug/findings-state.md` is canonical T2 | Replaced by `.geniro/state/handoff/from-debug-<branch>.md` (M1 §T2 row, M1:502). |
| Pre-M7 `adversarial-tests.md` at `.geniro/state/debug/adversarial-tests.md` is canonical adversarial T2 | Replaced by `.geniro/state/handoff/from-debug-adversarial-<branch>.md` (M1 §T2 row, M1:503). |
| 9-step numbering implies sub-phase granularity | 3-phase structure (M4 mirror per master plan §119). |
| Universal AskUserQuestion Rule lives inline в /debug | Reference canonical `per-finding-question.md` helper (D10 closure). |
| Double "Refresh custom instructions" в Steps 5 + 6 | Single Phase 2 entry refresh (D14 closure, mirror M4 §13.4). |

---

## 16. Anti-rationalization (P-MP-1 closure)

Per master plan P-MP-1 (lines 162-179): every milestone closes с an explicit anti-pattern check. This section catalogues rationalizations а reader (or а future M-doc) might offer to backtrack M7 decisions. Includes 18 rows preserved verbatim from pre-M7 `SKILL.md:425-451` (the original «Compliance — Do Not Skip Steps» table, which already captured debug-specific rationalization patterns) + cross-cutting LLM-orchestration anti-patterns (auto-handle / kill caps / silent abort / hook bypass) addressed inline where they would apply к M7.

| Your reasoning | Why it's wrong |
|---|---|
| "It's probably а cache issue" — guess и code | Guesses waste time. Form а hypothesis, then test it с evidence. (Preserved from pre-M7.) |
| "I know what this is, let me just fix it" | Intuition-based fixes mask the real cause. Gather evidence first. (Preserved.) |
| "It looks right, no need к test" | "Looks right" is the #1 predictor of broken fixes. Run the tests. (Preserved.) |
| "Let me fix these three things at once" | Multi-variable changes make it impossible к know what worked. Test one hypothesis at а time. (Preserved.) |
| "The error message says X, so it must be X" | Error messages lie. Verify с logs, debuggers, и traces. (Preserved.) |
| "The fix is one line, I'll just write it и escalate nothing" | Escalate every fix. Even one-line fixes go through /implement; architecture/review gate still applies. (Preserved, target updated from /follow-up к /implement per §15.3.) |
| "I added experimental logging и while I'm here I'll patch the bug too" | Experiments и fixes are separate deliverables. Revert experimental edits; escalate the proposed patch. (Preserved.) |
| "The user said just fix it" | If the user explicitly overrides, pick "Leave it к me" в §8.2 и produce the patch as text — still do NOT write it to source. User applies manually. (Preserved.) |
| "Changes look fine, I'll skip adversarial mode" | "Looks fine" is the attacker's favorite surface. If user asked для verify-changes, run the adversarial pass — а zero-red-tests outcome is still а valid deliverable. (Preserved.) |
| "Small diff, adversarial pass is overkill" | The 10-test hard cap и single-agent cost make adversarial mode cheap even on small diffs. Skip only when the skip-matrix rules fire. (Preserved.) |
| "I'll reason about edges instead of authoring tests" | Reasoning is reviewer-mindset. Adversarial mode AUTHORS executable failing tests because reasoning misses what running code catches. (Preserved.) |
| "The agent reported F→P, I'll trust it" | Orchestrator MUST independently re-run authored tests. Self-reported F→P is evidence, not proof. (Preserved.) |
| "А finding improves an agent prompt, I'll include it in §8.4" | Plugin files are out of scope. Suggest only project-owned targets (CLAUDE.md, `.geniro/instructions/`, `.geniro/knowledge/learnings.jsonl`, `.claude/rules/*`). (Preserved, scope migrated к M2 §5.4 routes.) |
| "The findings are в `state.md`, I'll just ask the escalation question" | `state.md` is а scratchpad, not а user-facing report. §8.1 requires explicit findings summary in chat AND persisted к `from-debug-<branch>.md` before §8.2 escalation question. (Preserved, path updated.) |
| "I'll paste the full findings summary into the escalation command" | §8.2 options reference `from-debug-<branch>.md` by path — that file IS the handoff. Inlining bloats context и lets copies drift. (Preserved.) |
| "The hypothesis matches the symptom — that's confirmation" | Symptom-matching is correlation, not causation. Confirmation requires а captured artifact per Evidence Standard kind 1-5. (Preserved.) |
| "I have no DB / log / production access — mark this hypothesis inconclusive" | Inconclusive-by-default is а fabrication shortcut. Run the §6.6 missing-data gate first. Only mark inconclusive if user confirms they cannot supply the artifact. (Preserved.) |
| "The user described the reproduction verbally, that's enough" | Verbal repro is а hypothesis seed, not а re-runnable artifact. §7.4 requires а captured artifact (failing test, script, curl + response). Convert verbal repro к captured form. (Preserved.) |
| "I have а script / curl / query that reproduces the bug, that's enough" | Scripts get deleted at Cleanup и leave no regression guard. §7.4 mandates the reproduction be authored as а unit/integration test. Escape hatch is invoked only for genuinely non-reproducible cases. (Preserved.) |
| "The agent reported the hypothesis confirmed — I'll trust it и move on" | Self-reported confirmation is evidence, not proof. Orchestrator MUST independently re-run the test / re-read the file:line / re-execute the query before advancing к §6.7 Isolate. (Preserved.) |
| "Per protocol I should ask via AskUserQuestion, но this specific intermediate question isn't in the enumerated gates — I'll inline (A)/(B) в chat" | The canonical Universal Rule at `skills/_shared/per-finding-question.md` makes the tool mandatory for ANY choice question, not just enumerated gates. If you catch yourself rationalizing "but this case is different / needs runtime confirmation / is just а quick check" — stop и call the tool. (Preserved, reference updated to canonical helper.) |
| "I'll name the reproduction test after the confirmed hypothesis number from `## Hypotheses`" | `state.md` gets deleted at Cleanup; the test ships с the fix. А name like `Bug C` или `Hypothesis 2 reproduction` is meaningless к whoever reads the test в CI weeks later. (Preserved.) |
| "I see two valid fixes for this root cause — I'll just pick one и write the text proposal" | §7.2 multi-path fix gate (Always-WAIT, per `per-finding-question.md`) requires AskUserQuestion whenever the root cause has more than one valid fix path с real trade-offs. (Preserved.) |
| "Add а wall-time kill cap so long-running debug sessions abort cleanly." | Class-A hard caps abort legitimate complex investigation mid-stride. M7 §2.3 quality-first — no Class-A caps. §6.8 stall gate (5 inconclusive) и §7.5 fix-fail gate (2 attempts) escalate к user via AUQ. User has agency. |
| "Spawn parallel adversarial-tester-agents к speed up diff scan." | M7 §9.4 keeps а single agent spawn (preserves pre-M7 contract). Parallel adversarial agents would double cost для marginal coverage — the 10-test hard cap already bounds scope. |
| "Skip the §8.1 findings summary; the AUQ options carry enough context." | §8.1 makes findings visible BEFORE escalation. Without it, user cannot make а routing decision. M3 §6 Block 5c expects the summary as compaction-recoverable; non-negotiable. |
| "Auto-promote L2 diagnoses к L4 rules when recurrence detected." | §8.3 + P-M4-5 — surface а suggestion line; do NOT auto-promote. User remains source-of-truth для L4 curation. Auto-promotion creates noise + drift. |
| "Defer M3 compaction-survival к downstream skills — M7 is mid-pipeline." | M3 contract IS M7's contract — state.md frontmatter (M1 §T1), `approvals[]` (P-M1-1 + M3 Block 5d), `## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason`. Без them, compaction mid-investigation loses the entire hypothesis trail. |
| "Bypass `git guardrail` hooks if а needed `git bisect` step blocks." | Hooks fail for а reason. `git bisect` is permitted (read-only investigation per §12.5). If а specific guardrail blocks legitimate debug work, the path is `.geniro/safety.json` allow_patterns, not `--no-verify`. |
| "Stall gate is paternalistic — user can just retry с more hypotheses." | §6.8 5-inconclusive gate protects against accidental infinite-loop UX. User retains agency via P-M7-2 8-option AUQ — the gate ADDS optionality (categorize the stall + supply missing component), it doesn't remove it. |
| "Audit trail isn't needed for local /debug runs." | The state.md `## Tool log` IS the audit trail. M3 SessionStart re-injects on compaction; user can resume. Without log, post-mortem on stalled investigations is impossible. M4 §2.2 invariant #6 (referenced in M7 §2.2) requires evidence-grounded final answers. |
| "Auto-handle MEDIUM-tier adversarial findings к reduce user friction." | The Metaswarm anti-pattern catalogued в `report.md`. М7 surfaces all CRITICAL/HIGH/MEDIUM findings в §9.4 step 5 Adversarial Findings template. Never auto-drop. |
| "Re-run tests after each file Edit in Phase 1 к catch regressions early." | Phase 1's Edits are experiments (logging, scratch test files) — not the deliverable. Re-running production test suite after each experiment would explode wall-time. §7.4 runs the authored test ≥2× pre-fix и ≥2× post-fix, scoped к the authored test only. |
| "Self-fix indefinitely until §7.4 verify passes." | §7.5 — bounded к 2 fix attempts. Past 2, escalate AUQ (try different / accept limitation / abort). «Kick it until it passes» is an anti-pattern catalogued в `report.md`. |

---

## 17. Cross-references

- M1 (state-files framework): `architecture/M1-state-files.md` (esp. §T1 frontmatter base; §T2 rows для `from-debug-<branch>.md` (M1:502) и `from-debug-adversarial-<branch>.md` (M1:503); §Frontmatter contract §Producer-specific extensions)
- M2 (memory layers): `architecture/M2-memory-layers.md` (esp. §5.2 emit type taxonomy; §5.3 «debug session start» query trigger; §5.4 L4 routing; §9 emit-learning helper; §10 resolve-conflicts; §13 obligation)
- M3 (compaction-survival): `architecture/M3-compaction-survival.md` (esp. §6 body sections; §7.2 Echo contract; §7.3 phase boundary refresh; §8 non-resumable-actions; §10 systemMessage; Block 5b/5c/5d render)
- M4 (/implement redesign): `architecture/M4-implement-redesign.md` (esp. §2.1.1 termination mapping; §2.2 7 invariants; §2.3 quality-first budgets; §7.4 escalation AUQ pattern; §13.4 phase boundary refresh; §13.5 ACI per-phase; §14 anti-rationalization)
- M5 (/plan redesign): `architecture/M5-plan-redesign.md` (esp. §17 spec.md schema; §22.4 hand-off contract)
- M6 (/review redesign): `architecture/M6-review-redesign.md` (esp. §15.2 state-handoff frontmatter T2 extension pattern; §24 anti-rationalization)
- spawn-agent ladder: `skills/_shared/spawn-agent.md`
- context-isolation checklist: `skills/_shared/context-isolation-checklist.md`
- finding-tagging schema: `skills/_shared/finding-tagging.md`
- evidence-standard: `skills/_shared/evidence-standard.md`
- effort-scaling helper: `skills/_shared/effort-scaling.md`
- model-tiering: `skills/_shared/model-tiering.md`
- primary-worktree: `skills/_shared/primary-worktree.md`
- per-finding-question helper: `skills/_shared/per-finding-question.md` (§ Investigation-driven fix gate (debug-flavored))
- emit-learning helper: `skills/_shared/emit-learning.md`
- within-skill-state-handoff: `skills/_shared/within-skill-state-handoff.md` (§ Slug rules; § Cleanup contract)
- scope-anchor: `skills/_shared/scope-anchor.md`
- tdd-cycle: `skills/_shared/tdd-cycle.md` (§ RED phase Step 3 for adversarial re-verification)
- improvement-routing: `skills/_shared/improvement-routing.md` (M2 §5.4 routes)
- isolation-techniques (NEW): `skills/_shared/isolation-techniques.md` (§14.3 extract)
- infrastructure-investigation (NEW): `skills/_shared/infrastructure-investigation.md` (§14.3 extract)
- adversarial-tester-agent: `agents/adversarial-tester-agent.md`
- Pre-M7 /debug: `skills/debug/SKILL.md` (563 lines — reference for verbatim preservation per §14.1)
