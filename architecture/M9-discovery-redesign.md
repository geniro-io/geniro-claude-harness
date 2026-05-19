# M9 — /geniro:onboard + /geniro:investigate Redesign (Discovery skills, bundled)

**Status:** Specification (pre-implementation)
**Master plan:** `/root/.claude/plans/reactive-dreaming-backus.md` — M9 of the M1–M10 redesign. Master plan §107 milestone queue: "M9 — `/onboard` + `/investigate` — Discovery surface; smaller scope" — bundled into а single doc per design Q1.
**Scope:** Redesign of `/geniro:onboard` и `/geniro:investigate` (Discovery surface). Aligns с M1 §T1 session-bound layout (per M7/M8 precedent), M3 body sections, M4 §2.2/§2.3 invariants/budgets, P-MP-1 anti-pattern check, M2 §5.3 emit triggers (`discovery` type — verified или retrieved per emitter), P-M9-1 5-step just-in-time retrieval cadence (formalizes /investigate's informal approach), P-M9-2 repo-size scan cap (≤50 files default для /onboard), P-M9-3 minimal trust-label propagation (P-M2-3 subset — no envelope wrapping per design Q3). Drops /onboard quick mode entirely per design Q4.
**Depends on:** M1 (state-files — `atomic_state_write`, T1 session-bound layout, `approvals[]` P-M1-1; `_CODEBASE_MAP.md` T3 row per M1:508); M2 (memory — `query-learnings` Phase 1, `emit-learning` Phase 2/3 `discovery` trigger, `trust:` field per P-M2-3, `update-semantic` для /onboard `_CODEBASE_MAP.md` writes); M3 (compaction-survival — `## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason`, Block 5d `approvals[]` render); M4 (mirrored quality-first budgets §2.3, escalation AUQ pattern §7.4, ACI surface §13.5); M7 + M8 (session-bound T1 layout precedent — `state/<skill>/<slug>/state.md`).
**Follows:** M8 (/refactor)
**Followed by:** M10 (operational: /setup + /instructions + /actions + /update).

---

## 1. Purpose

The pre-M9 Discovery skills carry three structural issues per the master plan §107 milestone queue ("Discovery surface; smaller scope") и audit findings:

1. **`/geniro:onboard`** (311-line `SKILL.md`) — codebase mapping skill. Outputs `<PRIMARY_ROOT>/.geniro/planning/CODEBASE_MAP.md` (T3 — M1:508 calls для rename к `_CODEBASE_MAP.md` underscore prefix) и (in `--quick --focus` mode) `focus-<area>.md` (M1:511 calls для rename к `_focus-<area>.md`). Has 8 defects: no M1 §T1 working state for the scan run; no M3 body sections; no M4 §2.2/§2.3 reference; no P-MP-1; stale `/decompose` (L218) и `/follow-up` (L263) references; no P-M9-2 repo-size cap; L2 `discovery` emit не automated.

2. **`/geniro:investigate`** (579-line `SKILL.md`) — deep codebase Q&A с parallel research agents. Has 6 defects: no M1 §T1 state.md; no M3 body sections; no M4 §2.2/§2.3 reference; no P-MP-1; stale `/follow-up` (L484); P-M9-1 5-step JIT cadence не formalized; P-M9-3 trust labeling minimal только в save-routing.

3. **Bundled per master plan §121** — M9 covers both skills в one design doc; shared sections (M1/M3/M4 alignment, P-X5 budgets, P-MP-1 anti-rationalization) appear once; skill-specific subsections cover unique workflows.

M9 produces:
- **`/geniro:onboard`** — 2 phases (Discover → Map), aligns с M1 session-bound T1 layout, adopts P-M9-2 ≤50-file scan cap (configurable expansion via AUQ), L2 `discovery` auto-emit, drops `--quick --focus` mode per design Q4 (mid-task orientation can use single-mode `--focus` as scope-limiter).
- **`/geniro:investigate`** — 3 phases (Classify+Scope → Investigate+Verify → Synthesize+Review+Present), formalizes P-M9-1 5-step JIT retrieval cadence, adopts P-M9-3 minimal trust label propagation (`retrieved` для WebFetch/WebSearch; `verified` для code-grounded) к L2 emit per P-M2-3.
- **Shared** — M1 §T1 session-bound state.md schema, M3 body sections, M4 §2.2/§2.3 mirror, M2 §13 helper-call schedule, P-MP-1 anti-rationalization (split between skills + cross-cutting).

---

## 2. Architecture overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  /geniro:onboard $ARGUMENTS                                                  │
└─────────────────────────────┬────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  Phase 1 — Discover (DECIDED — §6)      │
        │  • Load L4 / L3 / L2                    │
        │  • Repo-size scan (Glob top-level)      │
        │  • P-M9-2 ≤50-file cap (AUQ if >)       │
        │  • Optional --focus scope-limiter       │
        │  • Skip-conditions (empty repo / no     │
        │     source files / permission errors)   │
        │  • State.md `phase: discover`           │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 2 — Map (DECIDED — §7)           │
        │  • Build `_CODEBASE_MAP.md` (M1:508)    │
        │    с 8-section template                 │
        │  • L3 update via `update-semantic`      │
        │  • L2 `discovery` emit (verified)       │
        │  • Next-step AUQ                        │
        │  • State.md `phase: map` → done         │
        └─────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│  /geniro:investigate $ARGUMENTS                                              │
└─────────────────────────────┬────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  Phase 1 — Classify+Scope               │
        │  (DECIDED — §8)                         │
        │  • Load L4 / L3 / L2                    │
        │  • Classify into 9-type taxonomy        │
        │    (preserved) → agent set              │
        │  • Identify scope + skip criteria       │
        │  • Step 2.5 glossary-mismatch check     │
        │    (preserved + P-M1-1 approvals[]      │
        │    persist `glossary_resolve`)          │
        │  • 5-step JIT retrieval cadence         │
        │    (P-M9-1 closure)                     │
        │  • State.md `phase: classify`           │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 2 — Investigate+Verify           │
        │  (DECIDED — §9)                         │
        │  • Parallel agent spawns (Codebase /    │
        │    Git / Internet) per Phase 1 set      │
        │  • Orchestrator re-verify each load-    │
        │    bearing claim (preserved Phase 2.5)  │
        │  • Missing-data gate (AUQ)              │
        │  • State.md `phase: investigate`        │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 3 — Synthesize+Review+Present    │
        │  (DECIDED — §10)                        │
        │  • Synthesize draft answer              │
        │  • Fresh reviewer-agent (sonnet         │
        │    default; opus on cross-subsystem     │
        │    questions)                           │
        │  • Present + Sources + Open questions   │
        │  • Save-routing AUQ (CLAUDE.md domain   │
        │    / ADR / learnings.jsonl / memory)    │
        │  • L2 `discovery` emit с trust label    │
        │    (verified или retrieved per          │
        │    P-M9-3 minimal — §10.5)              │
        │  • State.md `phase: present` → done     │
        └─────────────────────────────────────────┘
```

### 2.1 State machines

**`/geniro:onboard`** phase enum:

```
[entry]
  └── discover ──┬── map ──┬── done
                 │          └── map-truncated (terminal — repo-size cap exceeded + user picked "Truncate")
                 │
                 └── discover-escalated ──┬── discover (user supplies missing access / picks "Continue" → resume)
                                          ├── aborted (terminal — user picks "Cannot proceed")
                                          └── routed (terminal — empty/near-empty repo, recommend `/geniro:investigate`)
```

**`/geniro:investigate`** phase enum:

```
[entry]
  └── classify ──┬── investigate ──┬── present ──┬── done
                 │                  │              └── present-summary-only (terminal — "I'm done с the topic" pick at Phase 3 follow-up)
                 │                  │
                 │                  └── investigate-escalated ──┬── investigate (user supplies missing data → resume)
                 │                                              ├── present (user picks "drop unverified claims" → continue с gaps)
                 │                                              └── aborted (terminal)
                 │
                 └── classify-escalated ──┬── classify (user resolves glossary mismatch → resume)
                                          ├── aborted (terminal)
                                          └── routed (terminal — question intent doesn't match /investigate scope, route к /onboard, /debug, etc.)

      present ──┬── (happy: flows к done)
                │
                └── present-loop ──┬── investigate (Phase 5 follow-up "dive deeper" → re-enter Phase 2 с narrower scope; max 2 rounds)
                                   └── done (user picks "save findings" → save-routing AUQ executes → done)
```

**Terminal states (both skills):** `done`, `map-truncated` (/onboard), `present-summary-only` (/investigate), `aborted`, `routed`. M3 SessionStart recovery treats all as "task complete — no resume".

**Non-terminal states:** `discover`, `map` (/onboard); `classify`, `investigate`, `present` (/investigate). M3 recovery rolls these back к phase-entry и re-runs idempotently.

**Escalation states:** `discover-escalated`, `classify-escalated`, `investigate-escalated`. M3 surfaces к user as "task was paused — last AUQ options:" so user re-picks без losing context.

### 2.1.1 Termination case → state mapping (shared)

Per master plan P-M4-2 (8 canonical termination conditions), M9 mapping:

| # | Termination case | Terminal state | `## Termination reason` body line |
|---|---|---|---|
| 1 | Final answer produced (map shipped / answer presented) | `done` | (omitted — happy path) |
| 2 | Done condition satisfied (modifier exit) | `map-truncated` / `present-summary-only` | (omitted — modifier-driven) |
| 3 | User approval required | non-terminal `*-escalated`, then terminal via user pick | — |
| 4 | Blocker needs user input | non-terminal `*-escalated` | — |
| 5 | Budget reached | N/A baseline (§2.3 quality-first) | (reserved для cost-aware mode post-P-X6) |
| 6 | Repeated failure threshold exceeded | `aborted` (via escalation "abort" pick); /investigate also `routed` если intent mismatch | `repeated-failure: <gate-name>` OR `intent-mismatch: <suggested-skill>` |
| 7 | Safety policy denial (hook-block, dangerous-action veto) | `aborted` | `safety-denied: <hook-or-rule-name>` |
| 8 | Tool unavailability without fallback | `aborted` | `tool-unavailable: <tool-name>` (e.g. WebFetch unavailable for Internet agent) |

`## Termination reason` body convention mirrors M4 §2.1.1.

### 2.2 Loop invariants

The 7 invariants от M4 §2.2 apply throughout M9. Reference M4 §2.2 verbatim; do not duplicate. Two M9-specific notes:

1. **Invariant #4 (bounded structured tool results)** — /investigate's research-agent outputs (Codebase Analyst / Git Historian / Internet Researcher) каждое capped at ~8K chars; longer truncated с marker. /onboard's repo-scan output (file list, directory tree) similarly bounded.
2. **Invariant #7 (errors → structured observations)** — WebFetch/WebSearch failures, permission errors during /onboard scan, agent registration "not found" fallbacks all become structured `## Tool log` or `## Errors` entries.

**Side-effect — `## Tool log` section в state.md (selective logging):** M9 logs **subagent-spawn outcomes** (/investigate's 1-3 research agents + Phase 3 reviewer; save-routing focused agents), **L3 writes** (/onboard's `_CODEBASE_MAP.md` write via `update-semantic`), **L2 emits** (both skills' `discovery` calls), и **escalation entries**. Routine Read / Bash skipped per M4 contract.

### 2.3 Budgets — quality-first framing

M9 has **NO hard kill caps**. All limits are **escalation gates that surface к user**. Per P-X5 design guidance (master plan §405).

**Quality gates (escalate к user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| /onboard scan-size cap (P-M9-2) | 50 files (default) OR user-configured expansion | §6.3 | AUQ — "Truncate at top 50" / "Expand scan (specify cap)" / "Apply --focus" / "Abort". **User picks.** |
| /investigate dive-deeper rounds | 2 | §10.4 follow-up | At max, suggest fresh `/geniro:investigate` с refined question; do not silently re-loop. |
| /investigate reviewer-agent re-review rounds | 1 | §10.2 | At max, present к user с remaining blockers flagged. |
| /investigate research-agent spawn count | 1-3 (literal Phase 1 set, no over-spawn) | §8.2 + §8.3 skip criteria | Hard constraint от Phase 1 classification; не а budget cap. |
| Research-agent output size | ~8K chars per agent | §2.2 invariant #4 | Truncation с marker. |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| Parallel research agents | 1-3 (per Phase 1 type classification) | §8.2 |
| Skip criteria (prune agents from set) | Apply ONLY к classified set; never add | §8.3 |

**Claude Code internals (not under M9 control):**
- Input tokens ≤200K per turn → triggers compaction (M3 hook handles resume).
- Output tokens ≤8K per turn → soft truncation.

**Explicitly NOT capped:**
- **Wall-time per run.** Big monorepo onboard may take 30+ minutes legitimately.
- **Total Read/Grep/Glob calls per phase.** /onboard scans many files. /investigate's research agents Read many.
- **Total cost per run.** Deferred к P-X6.

**Rationale.** Same two-class taxonomy как М4 §2.3: Class-A (hard kill caps — would abort legitimate complex discovery mid-stride; M9 has zero) vs Class-B (escalation gates — protect quality + surface к user; M9 keeps five).

---

## 3. Scope deltas vs. pre-M9 /onboard + /investigate

### 3.1 Removed

| Component | Reason | Replacement |
|---|---|---|
| `/geniro:onboard --quick --focus` mode (quick-mode bypass workflow + focus-<area>.md output) | Per design Q4 — drop entirely. Mid-task orientation use case is rare и `--focus` as scope-limiter on single-mode flow covers most legitimate needs. | Single-mode flow; `--focus` retained as а scope-limiter on the full 8-section template (concentrates mapping на specified areas). |
| Pre-M9 state file (none for /onboard, none for /investigate) — both skills had no M1 §T1 working state | Non-conformant с M1; lost context on compaction mid-scan or mid-investigation | M1 §T1 session-bound layout `.geniro/state/<skill>/<slug>/state.md` per §11. |
| Stale `/geniro:decompose` reference (`/onboard` L218) | Master plan §65 deleted /decompose | Replace с `/geniro:plan` recommendation в Next-step AUQ. |
| Stale `/geniro:follow-up` references (`/onboard` L263, `/investigate` L484) | Master plan §66 absorbed /follow-up into /implement | Replace с `/geniro:implement` recommendation в both Next-step AUQs. |
| 5-phase numbering в /investigate (1 / 2 / 2.5 / 3 / 4 / 5) | Per design Q2 — skill-natural collapse | 3 phases (Classify+Scope → Investigate+Verify → Synthesize+Review+Present) per §8/§9/§10. |
| /onboard `--focus` quick-mode-only validation (must be combined с --quick) | --quick dropped; --focus becomes а normal scope-limiter on the full flow | --focus standalone supported as scope-limiter (concentrates 8-section template content but doesn't change template structure). |

### 3.2 Kept (with adaptation)

| Component | Notes |
|---|---|
| /onboard 8-section CODEBASE_MAP.md template | Preserved verbatim. Path migrated к `_CODEBASE_MAP.md` (M1:508 underscore prefix) per §7.1. |
| /investigate 9-type Phase 1 classification table | Preserved verbatim в §8.2. |
| /investigate parallel agent spawn templates (Codebase / Git / Internet) | Preserved verbatim в §9.1. |
| /investigate Phase 2.5 orchestrator re-verify (independent re-check of each load-bearing claim) | Preserved. Folded into §9.2. |
| /investigate Phase 4 fresh reviewer-agent | Preserved. Folded into §10.2. |
| /investigate Step 2.5 glossary-mismatch check (CLAUDE.md Domain Context vs question vocabulary) | Preserved. Folded into §8.4. P-M1-1 `approvals[]` persistence added для `glossary_resolve` category (§13). |
| /investigate save-routing Step 2a (CLAUDE.md / ADR / learnings.jsonl / memory routing) | Preserved. Folded into §10.4. |
| /investigate Evidence Standard (kinds 1-5) | Preserved verbatim. Cross-references `skills/_shared/evidence-standard.md`. |
| /investigate context-isolation-checklist 6-field pre-inline contract | Preserved. Cross-references `skills/_shared/context-isolation-checklist.md`. |
| /investigate spawn-agent runtime-degradation ladder | Preserved. Cross-references `skills/_shared/spawn-agent.md`. |
| /onboard 3-section directory tree edge cases (empty repo / permission errors / 50,000+ file repos) | Preserved as Phase 1 skip-conditions §6.3 + escalation gates §6.4. |
| /onboard --depth N (limit scanning depth) | Preserved as а scope-limiter flag alongside --focus. |
| /investigate skip criteria (Phase 1 Step 2 — prune agents from classified set, never add) | Preserved verbatim в §8.3. |

### 3.3 Replaced

| Pre-M9 element | M9 replacement |
|---|---|
| Pre-M9 8-section "Compliance — Do Not Over-Document" table (/onboard L201-208) | §16.1 anti-rationalization с P-MP-1 framing + cross-cutting LLM rows. |
| Pre-M9 11-row "Compliance — Do Not Skip Phases" table (/investigate L491-505) | §16.2 anti-rationalization с P-MP-1 framing + cross-cutting LLM rows. |
| /investigate Step 0 LOAD_TIER `rules-only` | Full L4 (load-custom-instructions) + L3 (load-semantic) + L2 (query-learnings prior-knowledge) per M2 contract — mirrors М4/М5/М7/М8 entry pattern. |
| /onboard Step 0 LOAD_TIER `rules-only` | Same — full L4/L3/L2 load. |
| Pre-M9 implicit "save findings к learnings.jsonl" default | §10.5 explicit L2 `discovery` emit с trust label propagation (P-M2-3 + P-M9-3 minimal scope per design Q3). |
| Pre-M9 /investigate save-routing Step 2a uses focused-agent spawn workaround (no Write tool in /investigate frontmatter) | Preserved verbatim in §10.4 — the workaround stays sound; just folded into the new phase structure. |

---

## 4. Decisions recorded so far

| ID | Decision | Section |
|---|---|---|
| **Q1** | **Single M9 doc covering both skills** | This doc (bundled). |
| **Q2** | **Skill-natural phase counts** — /onboard 2 phases (Discover → Map); /investigate 3 phases (Classify+Scope → Investigate+Verify → Synthesize+Review+Present) | §6/§7 + §8/§9/§10 |
| **Q3** | **Minimal trust-label propagation** — L2 emit `trust:` field (P-M2-3) only; no `<untrusted_external_data>` envelope (defer к full P-X4) | §10.5 |
| **Q4** | **Drop /onboard --quick mode entirely** — single-mode flow; `--focus` retained as scope-limiter | §3.1 |
| **D1-fix** | M1 §T1 session-bound layout `.geniro/state/<skill>/<slug>/state.md` per M7/M8 precedent | §11 |
| **D2-fix** | M3 body sections обязательны | §11.3 |
| **D3-fix** | M4 §2.2 7 invariants reference (verbatim, no duplication) | §2.2 |
| **D4-fix** | P-X5 quality-first budget section mirror of M4 §2.3 | §2.3 |
| **D5-fix** | P-MP-1 anti-rationalization framing + cross-cutting LLM rows | §16 |
| **D6-fix** | Replace stale `/decompose` references с `/geniro:plan` recommendation | §7.4, §10.4 |
| **D7-fix** | Replace stale `/follow-up` references с `/geniro:implement` recommendation | §7.4, §10.4 |
| **D8-fix** | P-M9-2 ≤50-file scan cap (default; configurable expansion via AUQ) | §6.3 |
| **D9-fix** | L2 `discovery` auto-emit on Phase 2 (/onboard) и Phase 3 (/investigate) — replaces deleted /learnings skill | §7.3, §10.5 |
| **D10-fix** | P-M9-1 5-step JIT retrieval cadence formalized в Phase 1 (/investigate) | §8.5 |
| **D11-fix** | P-M9-3 minimal trust propagation — `verified` (code-grounded) или `retrieved` (WebFetch/WebSearch) per M2 §5.3 row /investigate | §10.5 |
| **D12-fix** | Full L4/L3/L2 load on Phase 1 entry (replaces `LOAD_TIER: rules-only`) | §6.2, §8.1 |
| **D13-fix** | _CODEBASE_MAP.md и _focus-<area>.md rename per M1:508-511 underscore convention | §7.1 |
| **D14-fix** | P-M1-1 `approvals[]` persistence для glossary_resolve (/investigate) и expand_scope (/onboard) categories | §8.4, §6.3 |
| **OQ-M9-1** | M2 §13 memory-I/O obligation — §12 | §12 |
| **OQ-M9-2** | ACI per-phase tool surface | §12.5 |

---

## 5. Defect inventory (audit 2026-05-18 — before/after)

14 defects identified в pre-M9 audit. Each closed by the section listed.

### /onboard (8 defects)

| ID | Defect | Pre-M9 location | M9 closure |
|---|---|---|---|
| **D1-O** | No M1 §T1 working state for the scan run — compaction mid-scan loses progress | throughout | §11.1 — M1 §T1 session-bound state.md |
| **D2-O** | `focus-<area>.md` filename без underscore prefix vs M1:511 `_focus-<area>.md` | `SKILL.md:35` | §3.1 — `--quick --focus` mode dropped entirely per Q4; focus-only artifact removed |
| **D3-O** | No M3 body sections | throughout | §11.3 — Tool log / Errors / Open Questions / Termination reason / Persisted approvals |
| **D4-O** | No 7 loop invariant reference | throughout | §2.2 — references M4 §2.2 |
| **D5-O** | No quality-first budget section | throughout | §2.3 — full M4 §2.3 mirror |
| **D6-O** | No P-MP-1 anti-rationalization framing | `SKILL.md:201-208` | §16.1 — preserves 4 rows + cross-cutting LLM rows |
| **D7-O** | `/geniro:decompose` reference в Next-step AUQ | `SKILL.md:218` | §7.4 — replace с `/geniro:plan` |
| **D8-O** | `/geniro:follow-up` reference в "Don't use" | `SKILL.md:263` | §3.1 — replace с `/geniro:implement` |
| **D9-O** | P-M9-2 ≤50-file repo-size cap not addressed (mass Glob risk) | (absent) | §6.3 — explicit cap + AUQ on exceedance |
| **D10-O** | L2 `discovery` emit not automated | (absent) | §7.3 — auto-emit at Phase 2 ship-step |
| **D11-O** | `CODEBASE_MAP.md` filename без underscore vs M1:508 `_CODEBASE_MAP.md` | `SKILL.md:23` | §7.1 — migrated к `_CODEBASE_MAP.md` per M1:508 convention |

### /investigate (6 defects)

| ID | Defect | Pre-M9 location | M9 closure |
|---|---|---|---|
| **D1-I** | No M1 §T1 working state.md for the investigation run | throughout | §11.2 — M1 §T1 session-bound state.md |
| **D2-I** | No M3 body sections | throughout | §11.3 — Tool log / Errors / Open Questions / Termination reason / Persisted approvals |
| **D3-I** | No 7 loop invariant reference | throughout | §2.2 — references M4 §2.2 |
| **D4-I** | No quality-first budget section | throughout | §2.3 — full M4 §2.3 mirror |
| **D5-I** | No P-MP-1 framing на 11-row anti-rationalization table | `SKILL.md:491-505` | §16.2 — preserves 11 rows + cross-cutting LLM rows |
| **D6-I** | `/geniro:follow-up` reference в Phase 5 follow-up AUQ | `SKILL.md:484` | §10.4 — replace с `/geniro:implement` |
| **D7-I** | P-M9-1 5-step JIT retrieval cadence not formalized | (informal в SKILL.md throughout) | §8.5 — explicit 5-step procedure |
| **D8-I** | P-M9-3 trust-label propagation minimal только в save-routing | implicit | §10.5 — explicit trust label on L2 emit per P-M2-3 contract |

(Total: 11+8 = 19 defect markers across both skills. Some defects are cross-skill (M1/M3/M4 alignment), counted once per skill для clarity.)

---

## 6. /geniro:onboard — Phase 1 Discover — **DECIDED**

State.md `phase: discover`. Light по cost — а repo-size scan + Glob + initial Read of project entry files. Exits к Phase 2 only when scan is bounded и repo-size cap is respected.

### 6.1 Phase 0 — Mode detect и $ARGUMENTS routing

Pre-Phase-1 detect (state.md `phase: mode-detect` if persisted; routinely lasts а turn без persistence):

| $ARGUMENTS shape | Behavior |
|---|---|
| empty | Full codebase scan (default mode). |
| `--focus <area1,area2,...>` | Scan все, но concentrate mapping output on focus areas; non-focus areas get summary-level coverage в CODEBASE_MAP.md. |
| `--depth N` | Limit directory scanning to N levels deep. Useful для large monorepos. |
| Combined `--depth N --focus area` | Both flags supported. |

Drops pre-M9 `--quick` mode entirely per design Q4. The `focus-<area>.md` artifact is removed; full mode с `--focus` covers concentrated mapping without а separate 1-page output.

### 6.2 Step 1 — Load custom instructions + L2 prior-knowledge

On Phase 1 entry:

1. **L4 refresh** — `load-custom-instructions(MODE: refresh, scope: onboard + global + code-style)` per M3 §7.2 Echo contract.
2. **L3 refresh** — `load-semantic(MODE: refresh, top-2 default: _project.md + _CODEBASE_MAP.md)`. If `_CODEBASE_MAP.md` already exists, the previous map is loaded as context (informs incremental update strategy).
3. **L2 prior-knowledge query** — `query-learnings(tags=onboard,codebase,architecture; scope=task path)` per M2 §5.3 «discovery start» trigger. К find prior architectural decisions and gotchas relevant к the scan.
4. **Cross-layer conflict resolution** — `resolve-conflicts` per M2 §10.

Echo lines per M3 §7.2 mandatory. Replaces pre-M9 `LOAD_TIER: rules-only` (which loaded only L4 global.md) — М9 adopts the full M2 entry pattern per D12-fix.

### 6.3 Step 2 — Repo-size scan + P-M9-2 ≤50-file cap

P-M9-2 obligation: "Avoid loading entire repositories" — bounded scan ≤50 files default.

**Procedure:**

1. **Top-level discovery** — `Glob("*")` at repo root (cwd `git rev-parse --show-toplevel`). Read top-level files for project structure markers: README.md, package.json / pyproject.toml / Cargo.toml / go.mod, .github/, src/ etc.
2. **Estimate scan size** — `find . -type f | wc -l` (or platform equivalent) к count total files. Skip `node_modules`, `.git`, `dist/`, `build/`, `target/`, `.venv`, `vendor/`, `__pycache__` standard ignores.
3. **Apply ≤50-file default cap** (P-M9-2):
   - If total file count ≤50 OR `--focus` provided AND focus-glob hits ≤50: proceed unblocked.
   - If total >50 AND no `--focus`: fire **AUQ "Scope"** — header "Repo-size cap":
     - **"Apply --focus <area>"** — user supplies focus areas; re-run scan с filter.
     - **"Expand scan (specify cap)"** — user provides explicit cap (e.g. 200, 500). Persists к state.md `approvals[]` с category `expand_scope` per P-M1-1.
     - **"Truncate at top 50"** — proceeds с top 50 most-likely-relevant files. Terminal state on completion: `map-truncated`.
     - **"Abort"** — terminal `aborted`.

**Approvals-persistence (P-M1-1 producer-side contract, D14-fix):** before firing the expand-scope AUQ, check state.md frontmatter `approvals[]` for а prior entry с `category: expand_scope`. If found, use prior `picked` (typical compaction-resume scenario). M3 §6 Block 5d renders this.

**Edge cases (preserved от pre-M9):**
- **Empty or near-empty repo** (no source files found): terminal `routed` с suggestion "Repo appears empty. Use `/geniro:investigate` to clarify project state."
- **Permission errors** on key directories: log to `## Errors` body section; note gaps в final map's `## Known Issues & Tech Debt`.
- **Very large repos (50,000+ files)**: auto-applies `--depth 2` AND fires the AUQ above (the 50,000 case routes через the same expand-scope choice — user picks; default к truncate).

### 6.4 Phase 1 — Discover (scan structure)

After §6.3 caps respected:

1. List directories и file counts within scope.
2. Identify language / framework / tools (from package.json / pyproject.toml / Cargo.toml / etc.).
3. Find package managers, config files, CI/CD definitions (.github/workflows/, .gitlab-ci.yml).
4. Spot large monorepos, multi-language projects.
5. Check for documentation (README, ADRs, wiki references).

State.md update: `phase: discover` → `phase: map`. `## Scope` body section captures the scanned-file list и any applied cap.

---

## 7. /geniro:onboard — Phase 2 Map — **DECIDED**

State.md `phase: map`. Builds `_CODEBASE_MAP.md` (M1:508 underscore-prefixed) с 8-section template + optional `--focus` concentration.

### 7.1 Build `_CODEBASE_MAP.md` (M1:508 — D13-fix)

Canonical path: `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` per M1:508 (underscore-prefixed registry file convention). Resolve `<PRIMARY_ROOT>` per `skills/_shared/primary-worktree.md` Mode A so the map persists across worktrees.

**8-section template (preserved from pre-M9):**

1. **Project Overview** — name, purpose, language/stack, entry points.
2. **Directory Structure** — file organization, key folders.
3. **Module Relationships** — module dependency graph.
4. **Architecture Patterns** — recurring design patterns (MVC / DDD / Hexagonal / etc.).
5. **Key Files & Configuration** — package.json, tsconfig, docker-compose, migrations.
6. **Conventions & Defaults** — naming, testing patterns, error handling.
7. **Critical Paths** — user request flow, deployment pipeline, job system.
8. **Tech Debt & Notes** — gotchas, legacy code, anti-patterns.

When `--focus <area1,area2>` is provided: sections 3 / 4 / 6 / 7 concentrate detail on the focus areas; non-focus areas appear as one-line summary entries. Sections 1 / 2 / 5 / 8 cover the full scanned scope regardless of focus.

**Map quality bar:** under 1000 lines, skimmable в 5 minutes (preserved от pre-M9 anti-rationalization).

Backward-compat reads: if а legacy `<PRIMARY_ROOT>/.geniro/planning/CODEBASE_MAP.md` exists (без underscore), Phase 1 §6.2 L3 load reads it once и Phase 2 writes к the new path. Legacy file is NOT auto-deleted (user may have references). Deprecation period of one release cycle precedes deletion.

### 7.2 L3 update via `update-semantic`

After `_CODEBASE_MAP.md` write, call `update-semantic(operation=write-codebase-map, path=<file>, description=<one-line>)` per M2 §6.1. The helper handles bounded auto-incremental updates и lock-guarding via `.codebase-map.lock`.

### 7.3 L2 `discovery` emit — D10-fix

Replaces deleted `/learnings` skill для onboard scope (master plan §69). After `_CODEBASE_MAP.md` write:

- **`emit-learning` (M2 §5.2)** — emit `discovery` type entry per M2 §5.3 row /onboard. Required `ext.{area, insight}`. Default trust `verified` per M2 §5.3 (code-grounded). Summary captures the most significant architectural discovery from the scan (e.g., "Hexagonal architecture: services/ depends on ports/, infrastructure/ depends on adapters/").

Trigger: emit при **first successful onboarding of а new codebase** OR **major architectural shift detected** (existing `_CODEBASE_MAP.md` content significantly diverges от previous version — heuristic from L3 read at §6.2). Skip when re-running onboard against а stable codebase (no architectural change).

### 7.4 Next-step AUQ — D6-fix + D7-fix

After map ships, route user via `AskUserQuestion` header "Next step":

- **"Plan а feature"** — description: "Run `/geniro:plan <feature>` to draft an approved spec (M5 spec.md emits а structured plan you approve before code)" — D6-fix replaces stale `/geniro:implement <feature>` immediate-route и /decompose mention.
- **"Investigate specifics"** — description: "Run `/geniro:investigate <question>` to dig deeper into а subsystem"
- **"Implement а change"** — description: "Run `/geniro:implement` to design и build (consumes а spec.md from /plan OR inline-task mode)" — D7-fix replaces stale `/geniro:follow-up`.
- **"Review feature backlog"** — description: "Read `_FEATURES.md` (manual backlog) or run `/geniro:plan` to author one" — note: `/geniro:features` deleted per master plan §68.

State.md `phase: map` → `done`. Cleanup deletes the working state.md per §11.4 cleanup contract.

---

## 8. /geniro:investigate — Phase 1 Classify+Scope — **DECIDED**

State.md `phase: classify`. Light по cost — а semantic $ARGUMENTS classification + L4/L3/L2 load + glossary-mismatch check. Critical для correctness: bad classification → wrong agent set → wasted research budget.

### 8.1 Step 0 — Load custom instructions + L2 prior-knowledge

On Phase 1 entry:

1. **L4 refresh** — `load-custom-instructions(MODE: refresh, scope: investigate + global + code-style)` per M3 §7.2.
2. **L3 refresh** — `load-semantic(MODE: refresh, top-2 default: _project.md + _CODEBASE_MAP.md)`. Note: `_CODEBASE_MAP.md` content (if exists) primes Phase 2's Codebase Analyst agent — pre-inline relevant sections into the spawn prompt.
3. **L2 prior-knowledge query** — `query-learnings(tags=<inferred from $ARGUMENTS keywords>; scope=task path)` per M2 §5.3 «investigate session start» trigger. К find prior answers и avoid duplicate research.
4. **Cross-layer conflict resolution** — `resolve-conflicts` per M2 §10.

Echo lines per M3 §7.2 mandatory. Replaces pre-M9 `LOAD_TIER: rules-only` per D12-fix.

### 8.2 Step 1 — Classify (9-type taxonomy, preserved)

Classify $ARGUMENTS into one of 9 types. The "Agents needed" column is the LITERAL spawn set — 1, 2, or 3 agents. Skip criteria (§8.3) ONLY prune from this set, never add. Preserved verbatim от pre-M9 SKILL.md:62-74:

| Type | Description | Agents needed |
|---|---|---|
| **Current-code trace** | "How does this function / module work right now?" | Codebase only |
| **Commit archaeology** | "When/who/why did this line change?" | Git only |
| **External docs lookup** | "What does library X's Y API do?" | Internet only |
| **How (current state)** | How does X work today? | Codebase + Git |
| **How (forward-looking)** | How CAN we do X / connect X to Y / integrate W? | Codebase + Git + Internet |
| **Why** | Why was X chosen? | Codebase + Git + Internet |
| **What-if** | What happens if we change X? | Codebase + Internet |
| **Compare** | Compare approaches for X (ours vs alternatives) | Codebase + Internet |
| **Risk** | What are the risks of X? | Codebase + Git + Internet |

### 8.3 Step 2 — Identify scope + skip criteria (preserved)

From $ARGUMENTS, extract:
- **Target area** — which files, modules, или patterns are relevant.
- **Depth needed** — surface-level overview vs deep trace.
- **Skip criteria** (apply ONLY to prune agents from the §8.2 classified set; never add):
  - **Skip Codebase** when answerable purely от git log/blame OR pure external docs.
  - **Skip Git** when about current code only.
  - **Skip Internet** when fully internal (our code, our patterns, our commits) AND no external library/framework references.

### 8.4 Step 2.5 — Glossary-mismatch check (preserved + P-M1-1 approvals[])

Preserved verbatim от pre-M9 SKILL.md:87-103. CLAUDE.md may contain а "Domain Context" section (added by /geniro:setup Phase 3.1 — M10 territory) listing domain entities, safety rules, и API contracts. Before Phase 2 spawn, check whether $ARGUMENTS uses terms that conflict с the documented glossary.

**Procedure (preserved):**
1. Extract proper-noun-shaped tokens / role names / entity names from $ARGUMENTS.
2. Grep CLAUDE.md auto-loaded content для each term.
3. Classify each match: no match (route к save-routing later) / exact match (proceed) / mismatch (fire gate).
4. **If mismatch:** `AskUserQuestion` header "Glossary" — "Use the glossary definition" / "Use my new meaning (note divergence)" / "Both — disambiguating names".

**Approvals-persistence (P-M1-1, D14-fix):** persist user pick к state.md frontmatter `approvals[]` с category `glossary_resolve` per P-M1-1. Subsequent compaction-resume reads prior pick from `approvals[]`. M3 §6 Block 5d renders. Re-ask only if context materially changed (new glossary section added).

Skip Step 2.5 entirely when CLAUDE.md has no Domain Context section, when question has no domain-shaped terms, или when all terms are exact matches.

### 8.5 5-step JIT retrieval cadence — P-M9-1 closure (D10-fix)

Formalizes /investigate's informal approach per master plan §343. 5 steps:

1. **Infer** — extract specific tags, file-paths, и symbols от $ARGUMENTS. Don't broad-scan.
2. **Search** — apply skip criteria от §8.3; spawn только the literal classified set от §8.2.
3. **Read most-relevant** — agents pre-inline relevant file content via орchestrator (§9.1) — agents don't broad-Glob themselves.
4. **Return concise** — agents output structured findings (Evidence Standard kind 1-5 only); no narrative drift.
5. **Store exact refs** — every claim cites file:line / commit-hash / URL with verbatim snippet, не paraphrase.

Step 5 closes M2's L2 emit auto-step (replaces /learnings skill drop per master plan §69) — the "exact refs" are what get persisted в the §10.5 `discovery` emit's `ext.{area, insight}` fields.

State.md `## JIT Cadence` body section logs which steps fired for this run (audit trail).

---

## 9. /geniro:investigate — Phase 2 Investigate+Verify — **DECIDED**

State.md `phase: investigate`. Parallel research-agent spawns + orchestrator re-verify. Exits к Phase 3 only when every load-bearing claim is verified, dropped, or routed through missing-data gate.

### 9.1 Parallel research agents (preserved spawn templates)

Spawn 1-3 agents в ONE response — all `Agent()` calls в the same assistant turn, NOT one per turn — matching the literal "Agents needed" set от §8.2. Each spawn pre-populates the 6-field context-isolation-checklist contract + obeys spawn-agent.md runtime-degradation ladder.

Templates preserved verbatim от pre-M9 SKILL.md:115-244:

- **Agent A: Codebase Analyst** — read-only (`disallowedTools=["Edit", "Write", "NotebookEdit"]`). Pre-inlined files (orchestrator-identified relevant content), structured findings с file:line + verbatim snippet, gaps section. Model: sonnet.
- **Agent B: Git Historian** — read-only + read-only git verbs only (no `git add/commit/push/checkout/reset`). Timeline + findings + patterns. Model: sonnet.
- **Agent C: Internet Researcher** — read-only (WebSearch + WebFetch only). Sources с URLs, findings, consensus, disagreements, reliability labels. Model: sonnet.

When only one agent is spawned, it is still spawned via `Agent(...)` (not inlined) so Phase 3 fresh-reviewer can verify findings against а fresh transcript.

### 9.2 Orchestrator re-verify (Phase 2.5 preserved)

Before synthesizing the answer, the ORCHESTRATOR (not а subagent) independently re-verifies every claim that would appear as `Evidence:` в the synthesized answer. Agent self-reports are inputs, not proof. Preserved от pre-M9 SKILL.md:246-274.

**Procedure:**

1. **Extract load-bearing claims** от agent findings.
2. **Re-verify against ground truth:**
   | Claim kind | Re-verification |
   |---|---|
   | File:line snippet | Read the file, confirm text matches at cited lines |
   | Grep / search result | Re-run, compare hit count и matched lines |
   | Command output | Re-run, compare output |
   | Commit / blame | `git show <hash>` or `git blame -L <range> <file>`, compare |
   | External fact | Re-fetch source URL OR re-search; compare wording |
3. **Route unverified claims:** Drop (answer must work без the claim) OR Request data via Phase 3 Step 0 missing-data gate.

A claim is **verified** when orchestrator's own re-run matches the agent's report. **Unverified** when orchestrator cannot reproduce OR cannot run the check at all (no DB access, no service access, no credentials, no logs).

### 9.3 Missing-data gate

When an unverified claim is load-bearing AND only the user can supply the missing artifact (production logs, runtime state, screenshots, dataset access, credentials), PAUSE и use `AskUserQuestion` BEFORE Phase 3 synthesis. Header: "Missing data" + 2-4 concrete options (paste log line / paste schema / paste screenshot / "I don't have it — proceed without").

If user picks "proceed without", drop the corresponding claim — do NOT synthesize around it. If user provides data, treat as evidence kind 5; re-enter §9.2 step 2 to re-verify против new artifact. Loop max twice; if still unverified, drop claim и note gap explicitly в final answer.

State.md `## Open Questions` body section logs missing-data gate question + user pick.

State.md transitions: `investigate` → `present` once all claims verified or routed.

---

## 10. /geniro:investigate — Phase 3 Synthesize+Review+Present — **DECIDED**

State.md `phase: present`. Synthesizes verified findings, fresh reviewer-agent re-checks, presents к user, offers save-routing AUQ, emits L2 `discovery` с trust label.

### 10.1 Synthesize draft

After §9.2/§9.3 complete (every load-bearing claim verified или routed):

1. **Cross-reference** agent findings — identify agreement и disagreement.
2. **Draft answer** using one of 5 question-type templates (preserved от pre-M9 SKILL.md:296-377):
   - **How** — Overview / Execution Flow / Key Details / Diagram.
   - **Why** — Decision / Evidence / Trade-offs table.
   - **What-if** — Direct Impact / Ripple Effects / Risks / Recommendation.
   - **Compare** — Comparison table / Recommendation.
   - **Risk** — Risk Assessment table / Mitigations.
3. **Confidence-driven action** — every major claim has а verified artifact OR routes to drop. Confidence labels are NOT а substitute for evidence. Per pre-M9 SKILL.md:379-386:
   - **Verified** (artifact 1-5 + §9.2 re-check passed): include с artifact cited inline.
   - **Unverified but verifiable**: re-enter §9.2.
   - **Unverified, only user can supply**: route через §9.3 missing-data gate.
   - **Unverifiable** (no path к evidence): omit, note в answer's "Open questions" section. NO "ship с caveat" path.

### 10.2 Fresh reviewer-agent (preserved Phase 4)

Spawn а fresh review agent that has NOT seen the research prompts — verifies с fresh eyes. Default `sonnet`; escalate к `opus` ONLY if user explicitly opted in to deep synthesis for an ambiguous cross-subsystem question.

Spawn template preserved verbatim от pre-M9 SKILL.md:394-431:
- 6-field context-isolation-checklist contract
- Pre-inlined files (every file cited в the draft answer)
- Draft answer
- 6-item verification checklist: spot-check Phase 2.5 (re-Read 2-3 random load-bearing claims), completeness, honesty (artifacts not caveats), clarity, over-claims, missing context.
- Output: issue list с Location / Issue / Severity (blocker | warning | nit) / Suggested fix; OR literal `VERIFIED — answer is accurate и complete`.

**Process review results (preserved):**
- **Blockers**: fix the answer (orchestrator corrects directly — text edits, not code).
- **Warnings**: add missing context или caveats.
- **Nits**: apply if improves clarity.
- **Verified**: proceed to §10.3.

If blockers: fix и re-verify с another fresh agent. **Max 1 re-review round** (track в orchestrator scratchpad); at limit, present к user с remaining blockers flagged + stop.

### 10.3 Present + Sources + Open questions

Deliver the synthesized, reviewed answer к user. Include:

- **Structured answer** от §10.1 (post-review fixes applied).
- **Sources section** — every cited artifact (file:line / command output / commit / URL / user-provided data) listed.
- **Open questions section** — any sub-question that could not be evidence-backed AND was not resolvable via missing-data gate. Be explicit about what data would settle each one — do NOT paper over с а "low-confidence" caveat.

### 10.4 Save-routing AUQ — D6-fix + D7-fix + preserved Step 2a

Offer follow-up via `AskUserQuestion` header "Follow-up":

- **"Dive deeper into <aspect>"** — re-run с narrower scope; **max 2 rounds** (track в scratchpad). At limit, suggest fresh `/geniro:investigate` с refined question.
- **"I have а follow-up question"** — start а new investigation.
- **"Save key findings к memory"** — execute Step 2a save-routing (per `_shared/improvement-routing.md`).
- **"Done — answer is sufficient"** — chains а second AUQ to route к next action.

**Step 2a save-routing (preserved verbatim от pre-M9 SKILL.md:459-476):** classify each finding к its proper destination — CLAUDE.md Domain Context (new domain term) / ADR (architectural decision meeting all 3 criteria — hard-to-reverse + surprising + genuine trade-offs) / `.geniro/knowledge/learnings.jsonl` (reusable technical insights) / auto-memory `feedback_*` (collaboration preferences). Investigate has no Write tool — spawn а focused Agent (sonnet, no subagent_type) per 6-field checklist + spawn-agent.md ladder с the proposed content pre-inlined; agent does the file write.

**Done-secondary AUQ (D6+D7 fix):**

- **"Fix а bug I found"** — description: "Run `/geniro:debug <symptom>`"
- **"Implement а change"** — description: "Run `/geniro:implement`" (D7-fix — replaces stale `/geniro:follow-up` reference, since /follow-up is absorbed per master plan §66)
- **"Plan а bigger change"** — description: "Run `/geniro:plan <feature>` to draft an approved spec first" (D6-fix — adds /plan routing для multi-step features)
- **"Nothing — just wanted the answer"** — terminal `present-summary-only`.

### 10.5 L2 `discovery` emit с trust label — D11-fix + P-M9-3 closure (minimal)

Per master plan §69 (/learnings deleted) + P-M9-3 (master plan §345) minimal scope per design Q3:

- **`emit-learning` (M2 §5.2)** — emit `discovery` type entry. Required `ext.{area, insight}` per M2 §5.2 typed-extension table.
- **Trust label (P-M2-3 + P-M9-3 minimal scope per design Q3):**
  - `trust: verified` — когда the investigation was code-grounded only (no WebFetch/WebSearch agents spawned, OR WebFetch results were not load-bearing к the final answer).
  - `trust: retrieved` — когда WebFetch/WebSearch findings were load-bearing к the final answer.
  - `trust: inferred` — N/A для /investigate (model-deduced claims do not pass Evidence Standard §10.1 confidence-driven action).

Per M2 §5.3 row /investigate: `Default trust: retrieved if WebFetch/WebSearch used; verified if code-grounded only`.

**No `<untrusted_external_data>` envelope wrapping** per design Q3 — defer к full P-X4 implementation. Trust-label propagation IS sufficient для baseline awareness; full envelope wrapping waits для prompt-injection-priority concern.

**Trigger:** emit when the investigation produced а substantive structured answer (not а quick reference lookup). Heuristic: ≥2 agents spawned OR question type is one of How / Why / What-if / Compare / Risk. Skip for "quick lookup" classifications (Current-code trace / Commit archaeology / External docs lookup) where the answer is already evidence-grounded but не а "discovery" per se.

State.md `phase: present` → `done` after emit. Cleanup deletes working state.md per §11.4.

---

## 11. State file schema (shared)

Both /onboard и /investigate use M1 §T1 session-bound layout (per M7/M8 precedent — the second canonical path-root в M1 §T1 Path roots table).

### 11.1 /onboard state.md

Path: `<PRIMARY_ROOT>/.geniro/state/onboard/<slug>/state.md`.

```yaml
---
tier: T1                                  # M1 §T1 required
producer: onboard                         # M1 §T1 required
schema-version: 1                         # M1 §T1 required
branch: <git-branch>                      # M1 §T1 required
timestamp: <ISO-8601 UTC>                 # M1 §T1 required
phase: <enum>                             # M1 §T1 required — values per §2.1 (mode-detect|discover|map|*-escalated|done|*-aborted|routed)
status: <in-progress|done|failed>         # M1 §T1 required
non-resumable-actions: []                 # M1 §T1 required (typically empty — onboard ships no commits)
approvals: []                             # M1 §T1 optional (P-M1-1; category `expand_scope` if §6.3 fired)
geniro_kind: onboard-state                # M9 schema marker
geniro_schema_version: m9-v1              # M9 producer schema-version marker
task_slug: <slug>                         # M9 extension — slug per `skills/_shared/within-skill-state-handoff.md` § Slug rules; for /onboard, slug = $ARGUMENTS-derived (e.g. `onboard-auth-module` if `--focus auth`)
worktree: <abs-path>                      # M1 §T1 optional, M9 strongly recommended
focus_areas: []                           # M9 optional — present когда --focus flag used
scan_cap: 50                              # M9 optional — present after §6.3 P-M9-2 cap applied (or user-expanded value)
---
```

### 11.2 /investigate state.md

Path: `<PRIMARY_ROOT>/.geniro/state/investigate/<slug>/state.md`.

```yaml
---
tier: T1                                  # M1 §T1 required
producer: investigate                     # M1 §T1 required
schema-version: 1                         # M1 §T1 required
branch: <git-branch>                      # M1 §T1 required
timestamp: <ISO-8601 UTC>                 # M1 §T1 required
phase: <enum>                             # M1 §T1 required — values per §2.1
status: <in-progress|done|failed>         # M1 §T1 required
non-resumable-actions: []                 # M1 §T1 required (typically empty — investigate ships no code)
approvals: []                             # M1 §T1 optional (P-M1-1; category `glossary_resolve` if §8.4 fired)
geniro_kind: investigate-state            # M9 schema marker
geniro_schema_version: m9-v1              # M9 producer schema-version marker
task_slug: <slug>                         # M9 extension — slug derived от question hash + first significant words
worktree: <abs-path>                      # M1 §T1 optional, M9 strongly recommended
question_type: <one of 9 types>           # M9 — from §8.2 classification
agents_spawned: []                        # M9 — list of agent types actually spawned (post-skip-criteria pruning)
dive_deeper_rounds: 0                     # M9 — counter for Phase 5 follow-up "dive deeper" cap
---
```

### 11.3 Body sections (M3 §6 compatibility — both skills)

```markdown
## Inputs from <producer>        # (optional, present когда T2 input was consumed)

## Scope                         # files / symbols / target area от Phase 1

## Classification                # /investigate only — question type + agent set chosen

## JIT Cadence                   # /investigate only — §8.5 5-step audit log

## Agent Findings                # /investigate only — raw output from research agents

## Verified Claims               # /investigate only — §9.2 re-verified evidence

## Draft Answer                  # /investigate only — pre-review version (preserved for compaction-resume)

## Reviewer Findings             # /investigate only — fresh-reviewer issue list

## Final Answer                  # /investigate only — post-review version

## Codebase Map Draft            # /onboard only — incremental scan results before final _CODEBASE_MAP.md write

## Tool log                      # M3 §6 selective logging (subagent spawns, L3/L2 writes, escalations)

## Errors                        # M3 §6 Block 5b — permission errors, tool failures, etc.

## Open Questions                # M3 §6 Block 5c — missing-data gates, glossary mismatches

## Termination reason            # M3 §6 — only on terminal aborted/routed states

## Persisted approvals           # M3 §6 Block 5d — render of frontmatter approvals[]
```

### 11.4 Cleanup contract

After phase = `done` or terminal:

- **Both skills:** Remove `<PRIMARY_ROOT>/.geniro/state/<skill>/<slug>/state.md` per `skills/_shared/within-skill-state-handoff.md` § Cleanup contract. Useful content already saved (CODEBASE_MAP.md / investigate's chat answer / L2 emits). Do NOT delete sibling slugs от concurrent runs on other branches.
- **/onboard:** `_CODEBASE_MAP.md` STAYS (T3 persistent per M1:508). Legacy `CODEBASE_MAP.md` (without underscore) remains on disk until deprecation period ends.
- **/investigate:** No T2 handoff to delete. Chat answer is the deliverable.
- Kill any background processes (rare для these skills).

Cleanup is best-effort. Failed commands silently OK.

---

## 12. Memory I/O (M2 §13 obligation — OQ-M9-1 closure)

### 12.1 Helper-call schedule

#### /geniro:onboard

| Phase | Helper | Direction | MODE | Inputs | Outputs | Notes |
|---|---|---|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` | scope = `onboard` + `global` + `code-style` | concatenated rules inlined | Echo per M3 §7.2. |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` | top-2 default + `_CODEBASE_MAP.md` if exists | inlined; drift check fires | Existing map primes incremental update strategy. |
| Phase 1 entry | `query-learnings` | read L2 | n/a | tags=onboard,architecture; scope=task path | top-K=5 matching entries | Per M2 §5.3 «discovery session start». |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a | three layers | precedence-resolved | Per M2 §10. |
| Phase 2 | `update-semantic` | write L3 | n/a | operation=write-codebase-map; path; description | append к `_CODEBASE_MAP.md` (lock-guarded) | Per M2 §6.1. |
| Phase 2 exit | `emit-learning` | write L2 | n/a | producer = `/geniro:onboard`; type = `discovery`; required `ext.{area, insight}`; trust = `verified` | append к `learnings.jsonl` | Per M2 §5.3 row /onboard. Trigger: first onboarding или major architectural shift. |

#### /geniro:investigate

| Phase | Helper | Direction | MODE | Inputs | Outputs | Notes |
|---|---|---|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` | scope = `investigate` + `global` + `code-style` | rules inlined | Per M3 §7.2. |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` | top-2 default | inlined | `_CODEBASE_MAP.md` content primes Phase 2 Codebase Analyst. |
| Phase 1 entry | `query-learnings` | read L2 | n/a | tags inferred от $ARGUMENTS | top-K=5 entries | Per M2 §5.3 «investigate session start». |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a | three layers | resolved | Per M2 §10. |
| Phase 2 | Codebase / Git / Internet agent spawns (1-3 per §8.2 set) | — | — | pre-inlined files + question | structured findings | Per §9.1. |
| Phase 3 | Reviewer-agent spawn (fresh) | — | — | draft answer + pre-inlined cited files | issue list or `VERIFIED` | Per §10.2. |
| Phase 3 exit | `emit-learning` (conditional) | write L2 | n/a | producer = `/geniro:investigate`; type = `discovery`; required `ext.{area, insight}`; trust = `verified` если code-grounded, `retrieved` если WebFetch/WebSearch load-bearing | append к `learnings.jsonl` | Per M2 §5.3 row /investigate + P-M2-3 trust field + design Q3 minimal scope. |
| Phase 3 (Save-routing) | Focused-agent spawn(s) (sonnet, no subagent_type) | — | — | pre-inlined CLAUDE.md / target path + content | file write | Workaround для /investigate's lack of Write tool. |

### 12.2 L2 emit triggers (per M2 §5.3 canonical contract — strict alignment)

Both /onboard и /investigate emit `discovery` type only. Other types are out of scope:

| Type | M9 emit? | When |
|---|---|---|
| `discovery` | **YES (both skills)** | /onboard: first onboarding of а codebase или major architectural shift. /investigate: substantive answer produced (How / Why / What-if / Compare / Risk types). Trust label per emitter context. |
| `diagnosis` | NO | /debug owns this trigger. |
| `convention` | NO | /implement self-review owns. |
| `decision` | NO | /plan owns. |
| `pitfall` | NO | /refactor + /review own. |

### 12.3 L3 update sites

`update-semantic` writes:
- **/onboard Phase 2** — writes `_CODEBASE_MAP.md` (M1:508). The full map regeneration is а one-shot replace; the helper performs bounded auto-incremental for ongoing additions (per M2 §6.1). NOT а typical single-row append — onboard regenerates the entire map.
- **/investigate** — does NOT call `update-semantic`. /investigate is read-only research; it does not add modules или rename files. Exception: если а save-routing target is `_project.md` or `_architecture.md`, the focused agent writes directly (not via `update-semantic` helper — those files are user-curated per M2 §6.1).

### 12.4 Phase boundary refresh sites (M3 §7.3)

| Skill | Boundary | Refresh action | Why |
|---|---|---|---|
| /onboard | Phase 1 entry | L4 + L3 + L2 load | Initial context |
| /onboard | Phase 2 entry | none | Phase 1 refresh covers; no code-writing в Phase 2 |
| /onboard | Phase 2 exit | none | Skill terminates |
| /investigate | Phase 1 entry | L4 + L3 + L2 load | Initial context |
| /investigate | Phase 2 entry | none | Phase 1 refresh covers |
| /investigate | Phase 3 entry | none | Phase 1 refresh covers |
| /investigate | Phase 3 exit | none | Skill terminates |

Both skills follow а simpler refresh pattern than M4-M8 because they have no code-writing phase that risks compaction-loss of code-style instructions.

### 12.5 ACI per-phase tool surface (OQ-M9-2 closure)

Mirrors M4 §13.5 structure. Per master plan P-M4-6 — minimal scope.

#### /geniro:onboard

**Phase 1 (Discover):**
- Allowed: Read / Grep / Glob / Bash (read-only commands — `git status`, `find . -type f`, `wc -l`).
- Explicitly blocked: production-source Edit/Write, `git add`, `git commit`, `git push`, Agent spawns (/onboard does не spawn subagents).

**Phase 2 (Map):**
- Allowed: Read / Write (для `_CODEBASE_MAP.md` only — scope к `.geniro/planning/**` via existing safety hooks).
- Allowed: `update-semantic` и `emit-learning` helper invocations.
- Explicitly blocked: production-source Edit/Write, `git add`, `git commit`, `git push`.

#### /geniro:investigate

**Phase 1 (Classify+Scope):**
- Allowed: Read / Grep / Glob / Bash (read-only — `git log`, `git diff`, `git blame`, `git show`).
- Allowed: WebSearch / WebFetch (for Phase 1 prelim if needed; rare).
- Allowed Agent spawns: none yet (Phase 2 spawns later).
- Explicitly blocked: Edit / Write / `git add` / `git commit` / `git push`.

**Phase 2 (Investigate+Verify):**
- Allowed: Agent spawns (Codebase Analyst / Git Historian / Internet Researcher).
- Each spawned agent runs с its own tool whitelist (per agent definition):
  - Codebase: Read / Grep / Glob / Bash (read-only); blocked: Edit / Write / NotebookEdit.
  - Git: Read / Bash (read-only git verbs); blocked: Edit / Write / mutating git.
  - Internet: WebSearch / WebFetch; blocked: Edit / Write / local Bash.
- Orchestrator re-verify (§9.2): Read / Grep / Bash (read-only) for re-running checks.

**Phase 3 (Synthesize+Review+Present):**
- Allowed: Read (for re-reading cited files during synthesis).
- Allowed Agent spawns: fresh reviewer-agent (sonnet); save-routing focused agents (when user picks save action).
- Reviewer-agent: Read / Grep (no Edit / Write).
- Save-routing focused agents: Read / Write (scoped к the target path — CLAUDE.md / `docs/adr/` / `.geniro/knowledge/learnings.jsonl`). Each agent's pre-inlined prompt specifies the exact target path; the agent's Write is gated by existing safety hooks (file-protection blocks unauthorized paths).

**Existing safety layer** applies across ALL phases (file-protection / git-guardrail / `.geniro/` deletion guard). Runtime denies stay enforced.

**Out of scope для M9 (deferred):** Full 14-class risk taxonomy + 7-decision matrix; full `<untrusted_external_data>` envelope (defer к P-X4).

---

## 13. Open questions

| ID | Topic | Status |
|---|---|---|
| **OQ-M9-1** | Memory I/O (M2 §13 obligation) | ✅ §12 |
| **OQ-M9-2** | ACI per-phase tool surface | ✅ §12.5 minimal scope |
| **OQ-M9-3** | /onboard "major architectural shift" emit heuristic (§7.3) — how to detect divergence от prior `_CODEBASE_MAP.md` | ⏳ Deferred к implementation. Initial heuristic: compare section counts / module-count delta / new top-level entries. Refine с empirical data. |
| **OQ-M9-4** | /investigate save-routing focused-agent spawn — should the agent use а dedicated subagent_type (e.g., `memory-writer-agent`) instead of generic `general-purpose`? | ⏳ Deferred. Current workaround (focused Agent с sonnet, no subagent_type) is sound; promotion к а custom agent type adds infrastructure for marginal benefit. Re-evaluate если save-routing volume justifies. |
| **OQ-M9-5** | /onboard `--depth N` vs `--focus <area>` interaction — should `--focus` imply auto-depth? | ⏳ Deferred. Keep flags orthogonal; user combines as needed. |

---

## 14. Cleanup checklist

### 14.1 `skills/onboard/SKILL.md` — surgical edit + significant deletions

Pre-M9 SKILL.md (311 lines) collapses к ~250 lines после `--quick` mode + focus-<area>.md removal + M9 frontmatter/section additions.

**Sections к delete (line ranges from pre-M9 file):**

- L16-18: `--quick` flag в Arguments section.
- L35-43: "Quick mode artifact" subsection (focus-<area>.md output description).
- L49-56: Quick-mode bypass step-list в Workflow section.
- L201-208: "Compliance — Do Not Over-Document" table → §16.1 (preserved, P-MP-1-framed).
- L218-220: Stale `/geniro:decompose` + immediate `/geniro:implement` Next-step options → replaced per §7.4.
- L239-248: Quick-Mode Definition of Done section.
- L299-307: Example 4 (Mid-task orientation — quick mode).
- L309-311: "Mid-task usage from other skills" section.

**Sections к rewrite in place:**

- L21-43: Outputs section → §7.1 (single canonical output `_CODEBASE_MAP.md` underscore-prefixed).
- L45-78: Workflow Steps 0-3 + Edge Cases → §6 phases (Discover + Map). Drop quick-mode bypass.
- L210-221: Next Steps AUQ → §7.4 (replace /decompose с /plan; replace /follow-up с /implement).
- L224-237: Definition of Done Full Mode → §11.4 cleanup contract + DoD merge.
- L262-266: "Don't use" → replace `/geniro:follow-up` с `/geniro:implement`.

**Sections к keep as-is:**

- L1-9: Frontmatter (drop `--quick` from argument-hint).
- L10-13: Title + intro.
- L85-199: CODEBASE_MAP.md format example (8 sections).
- L252-260: When к Use This Skill.
- L270-298: Examples 1-3 (drop Example 4).

**Target post-rewrite length:** ~240-260 lines (vs pre-M9 311).

### 14.2 `skills/investigate/SKILL.md` — surgical edit (mostly preserved)

Pre-M9 SKILL.md (579 lines) maps cleanly к M9's 3-phase structure с mechanical re-headings. Most semantic content (Evidence Standard, 9-type classification, parallel spawn templates, Phase 2.5 re-verify, glossary-mismatch check, save-routing Step 2a, fresh reviewer-agent template) is preserved verbatim under new section headers.

**Sections к delete (line ranges):**

- L484: stale `/geniro:follow-up` option в "Done — anything to act on" AUQ → replace с `/geniro:implement` (D6-fix).
- L491-505: "Compliance — Do Not Skip Phases" table → §16.2 (preserved, P-MP-1-framed).

**Sections к rewrite in place:**

- L10-13: Title + intro — minor phrasing к match М9 3-phase structure.
- L48-105: Phase 1 (Classify & Scope) → §8 (Classify+Scope) — preserves classification + scope + glossary check + add P-M1-1 `glossary_resolve` persistence + §8.5 5-step JIT cadence (P-M9-1 closure).
- L107-245: Phase 2 (parallel agents) → §9.1 (preserved spawn templates).
- L246-274: Phase 2.5 (Verify) → §9.2 (orchestrator re-verify).
- L276-386: Phase 3 (Synthesize) → §10.1 + §10.3 (synthesize + present).
- L388-440: Phase 4 (Self-Review) → §10.2 (fresh reviewer-agent).
- L442-485: Phase 5 (Present) → §10.4 (save-routing AUQ + done-secondary AUQ; D6-fix /follow-up→/implement; D7-fix /plan added).
- L506-516: Definition of Done → §11.4 cleanup + DoD merge.
- L519-534: When к Use This Skill — minor update.

**Sections к keep as-is (preserved verbatim):**

- L14-46: Subagent Model Tiering + Spawn Contract + Evidence Standard.
- L107-245: 3 spawn templates (Codebase / Git / Internet).
- L296-377: 5 question-type answer templates.
- L394-431: Fresh reviewer spawn template.
- L459-476: Save-routing Step 2a (preserves focused-agent workaround).
- L487-505: Git Constraint + (preserved) Compliance table content under new §16 framing.
- L537-579: Examples 1-4.

**Target post-rewrite length:** ~520-540 lines (vs pre-M9 579).

### 14.3 `_shared/` helper updates

- `skills/_shared/load-custom-instructions.md` — verify it supports `LOAD_TIER: pipeline` for /onboard and /investigate (pre-M9 used `rules-only`). M9 uses full L4+L3+L2 load via the standard pipeline-tier procedure.
- `skills/_shared/within-skill-state-handoff.md` — verify § Slug rules supports `.geniro/state/onboard/<slug>/` и `.geniro/state/investigate/<slug>/` layouts (per M7/M8 precedent — should already be aligned после M7 implementation PR).
- `skills/_shared/improvement-routing.md` — referenced from §10.4 save-routing Step 2a. Verify L4 routing table matches §8.6 contract.
- `skills/_shared/spawn-agent.md` — referenced from §9.1 research-agent spawns. No change expected.
- `skills/_shared/context-isolation-checklist.md` — referenced from §9.1. No change expected.
- `skills/_shared/evidence-standard.md` — referenced throughout /investigate. No change expected.
- `skills/_shared/primary-worktree.md` — referenced для `<PRIMARY_ROOT>` resolution. No change expected.
- `skills/_shared/scope-anchor.md` — referenced от research-agent anchor lines. No change expected.

---

## 15. Master plan reconciliation

### 15.1 Skill-list status (master plan §20)

M9 finalizes 2 of the 11 surviving skills. State после M9 implementation:

| Skill | Source | Milestone owner |
|---|---|---|
| `/plan` | M5 ✅ |
| `/implement` | M4 ✅ |
| `/review` | M6 ✅ |
| `/debug` | M7 ✅ |
| `/refactor` | M8 ✅ |
| **`/onboard`** | **M9 (this doc, §6-§7)** |
| **`/investigate`** | **M9 (this doc, §8-§10)** |
| `/instructions` | M10 ⏳ |
| `/actions` | M10 ⏳ |
| `/setup` | M10 ⏳ |
| `/update` | M10 ⏳ |

### 15.2 M9-specific obligations от master plan

| Master plan ref | Obligation | M9 status |
|---|---|---|
| §36 | "/onboard: Codebase mapping. Standalone Q&A + context-priming input к /plan on unfamiliar repos" | ✅ Preserved + Next-step AUQ routes к /plan per §7.4 |
| §42 | "/investigate: Codebase Q&A with parallel research agents" | ✅ Preserved + formalized per §8-§10 |
| §69 | /learnings auto-step replaces standalone skill | ✅ §7.3 (onboard) + §10.5 (investigate) — L2 `discovery` auto-emit |
| §121 | "Discovery surface; smaller scope" — bundled | ✅ Single M9 doc per design Q1 |
| §343 (P-M9-1) | 5-step JIT retrieval cadence — formalize /investigate informal approach | ✅ §8.5 |
| §344 (P-M9-2) | "Avoid loading entire repositories" — ≤50-file cap для /onboard | ✅ §6.3 |
| §345 (P-M9-3) | Untrusted-data labeling в /investigate | ✅ Minimal scope per design Q3 — §10.5 trust label propagation (no envelope wrapping) |
| §405 (P-X5) | Quality-first budget section | ✅ §2.3 |
| Anti-patterns guardrail (P-MP-1) | Anti-pattern check audit | ✅ §16 |
| M2 §5.3 rows /onboard, /investigate | `discovery` type; trust varies by emitter context | ✅ §10.5 + §12.2 |

### 15.3 Stale assumptions corrected

| Original /onboard + /investigate behavior | Corrected (M9) |
|---|---|
| `--quick --focus` mode (dual-mode /onboard) | Single-mode; `--focus` retained as scope-limiter per Q4. |
| `focus-<area>.md` artifact | Removed per Q4. |
| `CODEBASE_MAP.md` filename без underscore | Migrated к `_CODEBASE_MAP.md` per M1:508 (D13-fix). Legacy file readable but не canonical. |
| /onboard Next-step AUQ routes к /implement + /decompose | Routes к /plan + /implement (D6+D7 fix). |
| /onboard "Don't use → /follow-up" | "Don't use → /implement" (D7-fix). |
| /investigate save-routing default к learnings.jsonl | 4-way save-routing preserved (CLAUDE.md domain / ADR / learnings / memory). |
| /investigate done-secondary AUQ routes к /follow-up | Routes к /implement (D6-fix); adds /plan option (D6-fix). |
| Pre-M9 state files absent | M1 §T1 session-bound state.md (per M7/M8 precedent) for both skills (D1 onboard + D1 invest). |
| Pre-M9 `LOAD_TIER: rules-only` | Full L4+L3+L2 load на Phase 1 entry (D12-fix). |
| No repo-size cap для /onboard | P-M9-2 ≤50-file cap с AUQ on exceedance (D9-O). |
| /investigate trust label only в save-routing | Explicit `trust:` field on L2 emit per P-M2-3 + P-M9-3 minimal (D8-I, D11-fix). |

---

## 16. Anti-rationalization (P-MP-1 closure)

Per master plan P-MP-1: every milestone closes с an explicit anti-pattern check. This section preserves 4 rows verbatim от pre-M9 /onboard SKILL.md:201-208 + 11 rows от pre-M9 /investigate SKILL.md:491-505 + cross-cutting LLM-orchestration anti-patterns.

### 16.1 /onboard rows (preserved + P-MP-1 framing)

| Your reasoning | Why it's wrong |
|---|---|
| "Let me document every file" | Exhaustive maps are unreadable. Sample key files, focus on structure и relationships. (Preserved.) |
| "I need more detail on this module" | The codebase map captures architecture, not implementation. Keep it под 1000 lines. (Preserved.) |
| "The code is self-documenting" | Code shows what, not why. Note the critical paths (user flow, deploy flow) и what's unclear. (Preserved.) |
| "I'll create the map и move on" | А map nobody references is waste. Update it as you learn more, reference it when planning. (Preserved.) |
| "The repo has 5000 files but I'll just scan everything — better safe than sorry." | Mass-scan violates P-M9-2. The ≤50-file default cap exists для tokens + speed. Fire the §6.3 AUQ — user picks `--focus`, expansion, или truncation. Don't silently broad-scan. |
| "Quick mode would be nice here — I'll informally produce а focus-only output." | Quick mode dropped per design Q4. The single-mode flow + `--focus` scope-limiter covers all legitimate needs. Inventing а quick-mode bypass mid-run breaks the single-mode contract. |

### 16.2 /investigate rows (preserved + P-MP-1 framing)

| Your reasoning | Why it's wrong |
|---|---|
| "I already know the answer from reading the code" | You read one perspective. Parallel agents catch what you missed — git history reveals intent, internet reveals context. (Preserved.) |
| "I'll spawn all 3 to be safe" | Irrelevant agents are net-negative — they consume tokens и their off-target findings force the synthesizer к filter noise. §8.3 skip criteria drive the set, not safety defaults. (Preserved.) |
| "Self-review is overkill для а question" | Wrong answers waste more time than the review costs. File references go stale, claims drift от evidence. (Preserved.) |
| "The question mentions а library, but I'll skip Internet — I can answer от code" | The skip criteria require evidence, not guesses. If the question references an external dependency, framework, или standard, Internet is в the set. Use the §8.3 rules, не intuition. (Preserved.) |
| "The classification says 1 agent but I'll add Codebase для safety" | The §8.2 classification table is the LITERAL spawn set. Adding an agent the skip criteria excluded is the over-spawn anti-pattern. If the criteria look wrong для this question, revise classification — don't silently add. (Preserved.) |
| "I'll spawn agents one at а time to save tokens" | Parallel agents go в ONE response — multiple Agent() calls в the same assistant turn. Sequential turns waste wall-clock time для no token savings. (Preserved.) |
| "The user seems к want а quick answer" | А wrong quick answer is worse than а correct 30-second-slower answer. Run the pipeline. (Preserved.) |
| "All three agents converge on the same claim — that's confirmed" | Convergent self-reports are still self-reports. §9.2 requires the orchestrator к independently re-read / re-run / re-grep before treating any agent claim as evidence. (Preserved.) |
| "The reasoning chain is tight, that's enough evidence" | Reasoning is hypothesis, not evidence. Only the artifact kinds (file:line snippet, captured output, log line, query result, user data) clear the Evidence Standard. (Preserved.) |
| "I'll add а 'low-confidence' caveat и ship the claim anyway" | Caveats are not evidence. §10.1 Step 3 requires verified / re-verify / ask-user / omit — there is no "ship с caveat" path. (Preserved.) |
| "How-can-we / Compare / What-if questions are forward-looking, they don't need code-level verification" | All investigation types require evidence-backed answers. "How can we connect X к Y" must cite the actual schema/API/integration points; "what would break" must cite the actual call sites — не speculate. (Preserved.) |
| "The investigation found а WebFetch result that contradicts the code — I'll trust the docs." | Trust ≠ correctness. P-M9-3 trust labels (`verified` vs `retrieved`) document SOURCE, not RIGHTNESS. WebFetch result + matching code = both verified evidence. WebFetch result alone (no code verification) = retrieved evidence — note it as such; do NOT promote к verified without code grounding. |

### 16.3 Cross-cutting LLM-orchestration rows

| Your reasoning | Why it's wrong |
|---|---|
| "Add а wall-time kill cap так long-running discovery aborts cleanly." | Class-A hard caps abort legitimate complex discovery mid-stride. M9 §2.3 quality-first — no Class-A caps. §6.3 ≤50-file gate (onboard) + §10.4 dive-deeper rounds (investigate) + §10.2 re-review rounds escalate к user via AUQ. User has agency. |
| "Auto-promote /investigate findings к ADR if the answer touched architecture." | §10.4 save-routing AUQ keeps user в the loop on classification. Auto-promote bypasses the ADR 3-criteria gate (hard-to-reverse + surprising + genuine trade-offs). User decides; orchestrator routes. |
| "/onboard scan should bypass the 50-file cap silently if the codebase is monorepo-scale." | Master plan §344 P-M9-2 is explicit — ≤50 default; user-confirmable expansion. Silent bypass defeats the cost-control intent. |
| "Defer M3 compaction-survival к downstream skills — M9 is mostly Q&A." | M3 contract IS M9's contract — state.md frontmatter (M1 §T1), `approvals[]` (P-M1-1 + М3 Block 5d), `## Tool log`, `## Errors`, `## Open Questions`. Без them, compaction mid-scan loses /onboard's scan progress; compaction mid-investigate loses /investigate's verified-claims set. |
| "Bypass `git guardrail` hooks if /investigate's Git Historian needs а write." | Git Historian agent's tool surface explicitly read-only per §12.5 ACI — `git log`, `git blame`, `git show`, `git diff` only. Hook-block on git write is the correct denial; rewrite the agent spawn если it tries а write (it shouldn't). |
| "/investigate Internet Researcher returned а GitHub issue thread — treat it as code-authoritative." | GitHub issues are `trust: retrieved` per §10.5. Issue threads contain speculation, outdated info, и opinions. Cross-check against current code (Codebase Analyst) before treating as load-bearing evidence. |
| "Skip the §10.5 trust label on L2 emit — the entry will be trustworthy enough." | P-M2-3 mandates the field. Future readers (M-later /audit или Р-X6 telemetry) rely on the trust label к filter. Missing label = silent loss of source-confidence info. Always set the label. |
| "Self-review (§10.2) is overkill for а 1-agent investigation." | Phase 1 already pruned к the literal set per §8.2 + §8.3 skip criteria. The fresh reviewer-agent catches over-claims regardless of agent count — а 1-agent investigation can still draft an answer that misreads the agent's evidence. Run the review. |
| "Glossary mismatch (§8.4) is а corner case; skip the check." | If CLAUDE.md has а Domain Context section, the check is cheap (grep against pre-loaded content). Skipping it on а term-mismatched question wastes 2-3 agent spawns на the wrong vocabulary. Always run the check когда Domain Context is present. |
| "Audit trail isn't needed для local /onboard runs — the map IS the record." | The map captures architecture; the state.md `## Tool log` captures the scan process (which directories scanned, permissions errors, time taken). Без the log, debugging а failed onboard is impossible. М3 SessionStart re-injects on compaction; without log, post-mortem requires re-running the scan от scratch. |
| "Drop the JIT cadence formalization (§8.5) — it's just documentation overhead." | P-M9-1 is а master-plan obligation. The 5-step cadence is what makes /investigate evidence-disciplined; dropping it returns the skill к pre-M9 informal-search state where claims drift от evidence. |

---

## 17. Cross-references

- M1 (state-files framework): `architecture/M1-state-files.md` (esp. §T1 Path roots table — session-bound layout used by /onboard + /investigate; §Frontmatter contract; M1:508 `_CODEBASE_MAP.md` row; M1:511 `_focus-<area>.md` row — note: M9 drops /onboard's separate focus output per Q4)
- M2 (memory layers): `architecture/M2-memory-layers.md` (esp. §5.2 emit type taxonomy; §5.3 rows /onboard, /investigate + trust defaults; §5.4 L4 routing; §6.1 L3 update-semantic contract; §9 emit-learning helper; §10 resolve-conflicts; §13 obligation)
- M3 (compaction-survival): `architecture/M3-compaction-survival.md` (esp. §6 body sections; §7.2 Echo contract; §7.3 phase boundary refresh; §10 systemMessage; Block 5b/5c/5d render)
- M4 (/implement redesign): `architecture/M4-implement-redesign.md` (esp. §2.1.1 termination mapping; §2.2 7 invariants; §2.3 quality-first budgets; §13.4 phase boundary refresh; §13.5 ACI per-phase; §14 anti-rationalization)
- M5 (/plan redesign): `architecture/M5-plan-redesign.md` (esp. §17 spec.md schema — referenced from /onboard Next-step AUQ "Plan а feature" option)
- M6 (/review redesign): `architecture/M6-review-redesign.md` (esp. reviewer-agent contract — shared с /investigate Phase 3 fresh reviewer)
- M7 (/debug redesign) + M8 (/refactor redesign): `architecture/M7-debug-redesign.md` + `architecture/M8-refactor-redesign.md` (esp. M1 §T1 session-bound layout precedent — used by M9 для both skills)
- spawn-agent ladder: `skills/_shared/spawn-agent.md`
- context-isolation checklist: `skills/_shared/context-isolation-checklist.md`
- evidence-standard: `skills/_shared/evidence-standard.md`
- improvement-routing: `skills/_shared/improvement-routing.md` (referenced от /investigate save-routing Step 2a)
- primary-worktree: `skills/_shared/primary-worktree.md`
- scope-anchor: `skills/_shared/scope-anchor.md`
- within-skill-state-handoff: `skills/_shared/within-skill-state-handoff.md` (§ Slug rules; § Cleanup contract)
- emit-learning helper: `skills/_shared/emit-learning.md`
- load-custom-instructions: `skills/_shared/load-custom-instructions.md` (verify pipeline-tier procedure для М9 entry pattern)
- Pre-M9 /onboard: `skills/onboard/SKILL.md` (311 lines — reference для verbatim preservation per §14.1)
- Pre-M9 /investigate: `skills/investigate/SKILL.md` (579 lines — reference для verbatim preservation per §14.2)
