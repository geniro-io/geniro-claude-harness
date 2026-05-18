# M5 — /geniro:plan Redesign (Refined-Keep from /brainstorm)

**Status:** Specification (pre-implementation, partial — see §23 Open Questions)
**Master plan:** `/root/.claude/plans/reactive-dreaming-backus.md` — this doc is M5 of an M1–M10 architecture redesign that collapses 18 skills → 11 and replaces the legacy `/geniro:brainstorm` + `/geniro:decompose` with а single spec-driven planning skill `/geniro:plan`. See §24 for skill-list reconciliation.
**Scope:** Redesign of `/geniro:brainstorm` → `/geniro:plan` skill. Keeps the proven 8-phase ideation→approval loop (with two phases dropped as redundant), fixes 5 defects, closes 5 P-M5 schema/persistence/guard gaps, integrates M1 (state-files), M2 (memory layers), M3 (compaction-survival). Output artifact: canonical `spec.md` (consumed by M4 `/implement`); milestone-mode emits sibling `milestone-N.md` artifacts.
**Depends on:** M1 (state-files — task slug resolution, `atomic_state_write`, T1 frontmatter, `approvals[]` schema P-M1-1); M2 (memory layers — `load-custom-instructions`, `load-semantic`, `query-learnings` at Phase 1 entry); M3 (compaction-survival — `## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason` body conventions; `SessionStart` re-injection).
**Sequencing note:** master plan orders M4 (`/implement`) **before** M5 (this doc). М4 ships with an inline-task fallback that works when /plan does not yet exist (M4 §5.3); once M5 lands, /implement's preferred entry-mode is а spec.md emitted by /plan.
**Followed by:** M6 (`/review` — consumes spec.md `## Approval Points` for spec-compliance dim); M7 (`/debug` — may emit T2 hand-back to /plan when root cause changes scope); M8+ per master plan §107.

---

## 1. Purpose

The pre-M5 `/geniro:brainstorm` (118-line `SKILL.md` + 166-line `brainstorming-loop.md`) carried two responsibilities that overlapped с sibling skills и а handful of correctness defects:

1. **Free-form section authoring** — Phase 5 emitted "1-6 sections scaled by complexity" without а fixed schema. Downstream consumers (M4 /implement, M6 /review's spec-compliance dim) cannot reliably extract Objective vs Done Condition vs Rollback path. The proxy effect: every consumer re-derived structure ad-hoc, which is exactly the friction M5 is supposed to remove.
2. **Mixed strategic + tactical loop** — Phase 2 visual companion + Phase 1 ≥2-file-citation rule were busy-work for trivial config tweaks and not adequately scaled for Big tasks. /decompose's milestone slicing lived в а separate skill (deleted under master plan §65); /brainstorm did not absorb it.

М5 keeps the proven 8-phase user experience (mode-detect → explore → clarify → approaches → section-approve → write → validate → user-approve → hand-off) and:

- **Renames** /brainstorm → /plan (master plan §20 vocabulary).
- **Drops** Phase 2 visual companion и Phase 0 Refine path (Section 9, 7).
- **Fixes** 5 defects (Section 5).
- **Closes** 5 P-M5 schema/persistence/guard gaps (P-M5-1 through P-M5-5, Sections 17–19, 14–15).
- **Integrates** M1 state.md lifecycle, M2 L2/L3/L4 helpers, M3 compaction-survival.
- **Absorbs** /decompose: milestone-mode эмбеддится в Phase 5 (emit sibling milestone-N.md alongside spec.md when Big task detected).

The branch name **`claude/skip-architecture-with-spec-yjx8x`** (shared с M4) captures the upstream-side of the same idea: M5 produces the spec.md that lets M4 skip architecture.

---

## 2. Architecture overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  /geniro:plan $ARGUMENTS                                                     │
└─────────────────────────────┬────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  Phase 0 — Mode detect (§7)             │
        │  • design-doc-detect.md helper          │
        │  • IDEA → continue к Phase 1            │
        │  • DESIGN_DOC → confirm "start fresh    │
        │    with this as context?"               │
        │  • CODE_REFERENCE → error               │
        │  • Cancel → terminal `aborted` +        │
        │    ## Termination reason: user-cancel   │
        │  • Create task-dir + state.md           │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 1 — Explore (§8)                 │
        │  • Refresh L4 (load-custom-instructions │
        │    MODE: refresh, scope=plan+global+    │
        │    code-style)                          │
        │  • Refresh L3 (load-semantic MODE:      │
        │    refresh, _project.md +               │
        │    _CODEBASE_MAP.md)                    │
        │  • query-learnings (L2)                 │
        │  • Effort-scaled Explore spawns         │
        │    (Trivial 1 / Medium 2 / Big 3-4)     │
        │  • Echo contract — per-file Read        │
        │    surfaces к user (verifiable)         │
        │  • Persist spawns к ## Tool log         │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 2 — DROPPED (§9 rationale)       │
        │  (was: textual UI companion)            │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 3 — Clarifying questions (§10)   │
        │  • ≤5 one-at-a-time AUQs                │
        │  • Each answer persisted к              │
        │    approvals[] (P-M1-1) с category      │
        │    clarify_<dim>                        │
        │  • Compaction-safe (M3 §6 Block 5d)     │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 4 — Approaches (§11)             │
        │  • 2-3 approaches с Recommended first   │
        │  • AUQ → user picks                     │
        │  • Pick persisted к approvals[] с       │
        │    category approach_choice             │
        │  • Other approaches captured к          │
        │    ## Considered Alternatives           │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 5 — Section approval (§12)       │
        │  • 10-section P-M5-1 schema as template │
        │  • One AUQ per section (Approve/Revise) │
        │  • Each section approval persisted к    │
        │    approvals[] с category section_<id>  │
        │  • Big-task detection inside Phase 5 →  │
        │    milestone slicing decision           │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 6 — Write spec.md (§13)          │
        │  • Path: .geniro/planning/<task-dir>/   │
        │    spec.md (M1 canonical)               │
        │  • 10-section schema (P-M5-1)           │
        │  • Frontmatter с goal-state block       │
        │    (P-M5-2 — status / budget /          │
        │    checkpoints / forbidden_actions /    │
        │    approval_required_for)               │
        │  • NO auto-commit — defer к Phase 8     │
        │  • Milestone-mode: emit sibling         │
        │    milestone-N.md per slice             │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 7 — Mechanical validator (§14)   │
        │  • Deterministic checks (no Opus self-  │
        │    prompt):                             │
        │    1. 10-section schema completeness    │
        │    2. 9 good-goal criteria (P-M5-4)     │
        │    3. Placeholder scan                  │
        │    4. Contradiction heuristics          │
        │    5. Scope-creep markers               │
        │  • Findings → ## Open Questions         │
        │  • Hard fail → revision sub-loop        │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 8 — User approval (§15)          │
        │  • AUQ body inlines P-M5-5 schema:      │
        │    Objective summary, Risks digest,     │
        │    Approval Points, Rollback,           │
        │    Done Condition, Scope summary        │
        │  • Approve → git commit fires here      │
        │    (NOT in Phase 6)                     │
        │  • Request changes → revision round     │
        │    (max 3, then escalate AUQ)           │
        │  • Final answer persisted к             │
        │    approvals[] с category final_approve │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 9 — Hand-off (§16)               │
        │  • 2 options: /implement / stop         │
        │  • Milestone-mode: /implement           │
        │    milestone 1 OR /implement <slice>    │
        │  • Persist hand-off choice к            │
        │    approvals[] с category handoff       │
        │  • Terminal: `done`                     │
        └─────────────────────────────────────────┘
```

---

### 2.1 State machine

Phase enum (state.md `phase:` field values) и transitions:

```
[entry]
  └── mode-detect ──┬── explore ──┬── clarify ──┬── approaches ──┬── section-approve ──┬── write-spec ──┬── validate ──┬── user-approve ──┬── handoff ──┬── done
                    │             │             │                │                     │                │              │                  │             │
                    │             │             │                │                     │                │              │                  │             └── (terminal)
                    │             │             │                │                     │                │              │                  │
                    │             │             │                │                     │                │              │                  └── (revision rounds 1-3; on round 3 exhaust → phase-8-escalated)
                    │             │             │                │                     │                │              │
                    │             │             │                │                     │                │              └── (mechanical pass-through — no user gate; on hard-fail → revision sub-loop)
                    │             │             │                │                     │                │
                    │             │             │                │                     │                └── (no auto-commit; commit deferred к Phase 8 approve)
                    │             │             │                │                     │
                    │             │             │                │                     └── (Big task detected → milestone-mode; emit sibling milestone files)
                    │             │             │                │
                    │             │             │                └── (user picks; ## Considered Alternatives captured)
                    │             │             │
                    │             │             └── (≤5 AUQs one-at-a-time)
                    │             │
                    │             └── (effort-tier-scaled; Echo contract)
                    │
                    └── aborted (terminal — user-cancel at Phase 0)

phase-8-escalated ──┬── user-approve (user picks "approve as-is")
                    ├── write-spec (user picks "re-revise" → forces fresh round-1 cycle)
                    └── aborted (terminal — user picks "abort")
```

**Terminal states:** `done`, `aborted`. M3 SessionStart recovery treats any terminal state as «planning complete или cancelled — no resume needed». For `done`, M3 surfaces the hand-off line ("Pick /implement to proceed") so the user is not left wondering what comes next.

**Non-terminal states:** `mode-detect`, `explore`, `clarify`, `approaches`, `section-approve`, `write-spec`, `validate`, `user-approve`, `handoff`. M3 recovery rolls these back к their phase-entry point and re-runs from there (idempotent re-entry — `approvals[]` ensures already-answered AUQs are skipped per P-M1-1).

**Escalation state:** `phase-8-escalated`. M3 surfaces к user as "planning was paused awaiting your decision — last shown AUQ options:" so the user re-picks без losing prior section approvals.

### 2.1.1 Termination case → state mapping

Per master plan P-M4-2 (extended к M5), the 8 canonical termination conditions map к M5 state values:

| # | Termination case | Terminal state | `## Termination reason` body line |
|---|---|---|---|
| 1 | Final answer produced (happy hand-off) | `done` | (omitted — happy path) |
| 2 | Done condition satisfied (modifier exit — e.g., "plan only, no hand-off") | `done` | `modifier-exit: plan-only` (when modifier present) |
| 3 | User approval required | non-terminal `user-approve`, then terminal via user pick | — |
| 4 | Blocker needs user input | non-terminal `phase-8-escalated` | — |
| 5 | Budget reached | N/A в baseline M5 — per §2.3 quality-first framing, no Class-A hard kill caps. | (reserved) |
| 6 | Repeated failure threshold exceeded | `aborted` (via Phase 8 revision-round exhaust → "abort" pick) | `repeated-failure: phase-8 revision-limit-3` |
| 7 | Safety policy denial (e.g., mutation hook block) | `aborted` | `safety-denied: <hook-or-rule-name>` |
| 8 | Tool unavailability without fallback | `aborted` | `tool-unavailable: <tool-name>` |

**`## Termination reason` body convention:** identical к M4 §2.1.1. М5 on `aborted` writes one-line entry в state.md body. M3 SessionStart hook surfaces it via state.md re-inject. Notable M5-specific cases:

- **User cancels at Phase 0** (`mode-detect`'s "Cancel" option): `user-cancelled-at-phase-0`.
- **Phase 8 revision-round 3 exhaust → abort**: `repeated-failure: phase-8 revision-limit-3`.
- **DESIGN_DOC mode + user picks "start fresh"**: NOT а termination — flows к Phase 1 с the prior doc inlined as context.

State-machine §2.1 diagram remains source-of-truth для transitions; this subsection is the **why** layer.

---

### 2.2 Loop invariants

These 7 invariants apply throughout M5's nine phases. Identical к M4 §2.2 conceptually; phase numbers и tool surface differ.

1. **One result per tool call.** Every AskUserQuestion / Edit / Write / Bash / Agent spawn produces exactly one structured result. Failed AUQ (empty-answer bug) → fall back to plain text re-ask; never auto-default.

2. **Args validated before execution.** Bash commands constructed from $ARGUMENTS или state.md fields pass input sanity-checks. Path-based detection (design-doc-detect.md helper) validates file existence before treating $ARGUMENTS as а path.

3. **Permission before side-effect.** Phase 6 `Write` к `.geniro/planning/<task-dir>/spec.md` is the only mutation в the loop. `git commit` deferred к Phase 8 post-approval. No auto-mutations elsewhere — this is enforced by the §19 plan-mode mutation guard (frontmatter `allowed-tools` minus `Edit`; PreToolUse Bash guard allows `Write` only под `.geniro/planning/**`).

4. **Bounded и structured tool results.** Phase 1 Explore-agent output capped at ~4000 chars per agent; longer truncated с marker. Output schema: `[{file, lines, observation}]`. Phase 7 validator output is а structured pass/fail list per check.

5. **Escalation gates, not silent abort.** Phase 8 revision-round 3 surfaces к user via AUQ. Phase 7 validator hard-fail can also escalate если 3 rounds of automated revision-retry exhaust (rare — usually means schema-misunderstanding by the model, which а user re-prompt fixes faster than yet another auto-revise).

6. **Final answer grounded в observations.** Phase 5 section content MUST cite Phase 1 explore findings (`file:line` references) — not generic prose. Phase 7 validator includes а "citations present" check (P-M5-4 #3 source-materials criterion).

7. **Errors, denials, cancellations, timeouts → structured observations.** Phase 1 Explore-agent failures → structured entry в `## Errors`. Phase 0 cancel → `## Termination reason`. Phase 7 validator findings → `## Open Questions`. Never silently skipped.

**Side-effect — `## Tool log` section в state.md (selective logging):** invariants 1 и 7 motivate persisting **Phase 1 Explore-agent spawns** и **Phase 6 `Write` spec.md** к the `## Tool log` body section. AUQ calls do NOT need logging — `approvals[]` is the structured record. M5 typical run produces 3-5 log entries (2-4 Explore spawns + 1 Write); not hundreds.

Schema (identical к M4):

```yaml
## Tool log
- ts: 2026-05-17T10:42:13Z
  tool: Agent
  detail: "Explore: existing auth flow"
  status: ok
  summary: "found 3 relevant files, 1 convention pattern"
- ts: 2026-05-17T11:08:00Z
  tool: Write
  detail: ".geniro/planning/<task-dir>/spec.md"
  status: ok
  result_ref: "1247 bytes"
```

Each entry written via M1 `atomic_state_write`.

---

### 2.3 Budgets — quality-first framing

M5 has **NO hard kill caps**. All limits are **escalation gates that surface к user**, not abort triggers. Per master plan P-M4-3 (revised) extended к M5: user tokens unlimited → no «task aborted: budget exhausted» failure modes.

**Quality gates (escalate к user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Phase 3 clarifying-question count | ≤5 one-at-a-time AUQs | §10 | If model wants а 6th, force consolidation OR proceed to Phase 4 с stated assumptions. |
| Phase 7 → Phase 6 auto-revision rounds | 3 | §14.3 | AUQ — accept-as-is / re-revise / abort. User picks. |
| Phase 8 user-revision rounds | 3 | §15.3 | AUQ — accept-as-is / re-revise / abort. User picks. |
| Phase 1 Explore-agent output size | ~4K chars per agent | §2.2 invariant #4 | Truncation с marker, not abort. |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| Parallel Explore spawns per Phase 1 | 1-4 (effort-tier-scaled) | §8.2 effort-tier mapping |
| spec.md section count | exactly 10 | §17 P-M5-1 schema |

**Explicitly NOT capped (intentional):** wall-time, total tool calls, total model turns, total cost. Same rationale as M4 §2.3.

**Rationale.** Master plan §102 phrasing "≤3 AUQ gates per-run, ≤5 helper reads, ≤5 spawns" applies к /implement, NOT /plan. /plan is а **clarification-heavy** skill — its job IS к ask questions (Phase 3 ≤5 AUQs, Phase 4 1 AUQ, Phase 5 up к 10 AUQs one per section, Phase 8 1 AUQ → ~17 AUQs typical, not 3). The pre-redesign /brainstorm shipped that pattern и user feedback was «нравится как работает» — М5 preserves it.

---

## 3. Scope deltas vs. pre-M5 `/geniro:brainstorm`

### 3.1 Removed

| Component | Reason | Replacement |
|---|---|---|
| Phase 2: Visual companion (textual UI sketch + haiku spawn + 3-revision sub-loop) | Sketch не persists в design doc; Phase 6 doesn't cite ui-preview.md; Phase 5 sections и так cover UI when topic warrants | Inlined в Phase 5 section content when topic warrants |
| Phase 0 Refine path (DESIGN_DOC → jump к Phase 5 с existing sections as starting state) | Lossy section re-derivation (no machine-readable boundaries в prose doc) | DESIGN_DOC → AUQ "start fresh с this doc as context?"; force-restart from Phase 1 |
| Auto-commit at Phase 6 (`git commit` immediately after Write) | Violates Always-WAIT contract — Phase 8 "Request changes" would force second commit per round | Commit deferred к Phase 8 post-approval (§15.4) |
| Phase 7 Opus self-prompt (placeholders/contradictions/ambiguous/scope-creep — free-form review) | Linter-grade work; deterministic checks are cheaper and more reliable | Mechanical validator (§14 — script-checkable 9 P-M5-4 + 4 legacy checks) |
| Hand-off menu options pointing к `/features add` and `/decompose` | Both skills deleted (master plan §65, §68) | 2 options remain: `/implement directly` / `stop`; milestone-mode handled in Phase 5 (§12.3) |

### 3.2 Kept (with adaptation)

| Component | Notes |
|---|---|
| 8-phase user-facing flow (mode-detect → explore → clarify → approaches → section-approve → write → validate → user-approve → handoff) | Proven UX; user feedback positive |
| Section-by-section approval в Phase 5 | Proven pattern; per-section AUQ is the granularity users want |
| One-at-a-time clarifying questions в Phase 3 | Empirically better than multi-question forms |
| 2-3 approaches с Recommended first в Phase 4 | Pattern from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md` AUQ shape |
| design-doc-detect.md helper at Phase 0 | Unchanged (Markdown-linter-pattern path/HTML-marker/frontmatter 3-way OR) |
| `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` runtime degradation ladder | Applied к Phase 1 Explore spawns |
| `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` | Applied к every Phase 1 Explore spawn |

### 3.3 Replaced

| Pre-M5 form | M5 form |
|---|---|
| Free-form 1-6 sections "scaled by complexity" (`brainstorming-loop.md:67-82`) | Fixed 10-section P-M5-1 schema (§17) |
| spec.md frontmatter — none mandated | Frontmatter с M1 T1 schema + P-M5-2 goal block (§18) |
| `allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task, AskUserQuestion, TodoWrite, WebSearch, WebFetch]` | `[Read, Write, Bash, Glob, Grep, Task, AskUserQuestion, TodoWrite, WebSearch, WebFetch]` (Edit removed); plus PreToolUse guard for Write scope (§19) |
| Phase 8 AUQ body = "Spec committed к <path>. Review it before hand-off?" | Phase 8 AUQ body inlines P-M5-5 schema (Objective digest / Risks / Approval Points / Rollback / Done Condition / Scope) (§15) |
| Phase 1 `≥2 file citations OR "no related code"` (unverifiable) | Phase 1 Echo contract — Read invocations surface к user; effort-tier-scaled spawn count (§8.2) |
| LOAD_TIER: rules-only (L4 only) | LOAD_TIER: full (L4 + L3 `_project.md`/`_CODEBASE_MAP.md` + L2 query-learnings) at Phase 1 entry (§21) |

---

## 4. Decisions recorded so far

| ID | Decision | Section |
|---|---|---|
| **H-1** | Approach = **Refined Keep**. 8 phases preserved (Phase 0 Mode detect, Phase 1 Explore, Phase 3 Clarify, Phase 4 Approaches, Phase 5 Section approval, Phase 6 Write, Phase 7 Validator, Phase 8 User approval, Phase 9 Hand-off); Phase 2 Visual + Phase 0 Refine dropped; all 5 defects fixed; all 5 P-M5 gaps closed; full M1/M2/M3 integration | §2, §3, §5 |
| **H-2** | goal-state lives **in spec.md frontmatter**, NOT а separate goal.md | §18 |
| **H-3** | Phase 7 = **mechanical validator** (deterministic, script-checkable), not Opus self-prompt | §14 |
| **H-4** | **No auto-commit** at Phase 6; `git commit` fires only after Phase 8 user-approve | §13, §15.4 |
| **H-5** | Plan-mode mutation guard: frontmatter `allowed-tools` minus `Edit`; PreToolUse hook scopes `Write` к `.geniro/planning/**` only | §19 |
| **H-6** | Phase 5 10-section schema (P-M5-1) | §17 |
| **H-7** | Phase 8 AUQ schema (P-M5-5) с 7 fields | §15.2 |
| **H-8** | Milestone-mode эмбеддится в Phase 5 (Big detection → emit sibling milestone-N.md files) — replaces deleted /decompose | §12.3 |
| **H-9** | Hand-off menu = 2 options only (/implement / stop); milestone-mode offers `/implement milestone N` | §16 |
| **H-10** | DESIGN_DOC mode at Phase 0 → "start fresh с this doc as context?" AUQ; Refine path removed (lossy) | §7.2 |

Open questions: see §23.

---

## 5. Defect inventory (current /brainstorm — before/after)

Five defects identified by audit (2026-05-18, recorded в OQ-resolution session). M5 closes all 5.

| # | Defect | Pre-M5 location | M5 fix | Section |
|---|---|---|---|---|
| **D1** | Phase 6 auto-commits before Phase 8 approve — violates Always-WAIT; if Phase 8 "Request changes" → second commit per round, polluting git history | `brainstorming-loop.md:109` | Drop auto-commit от Phase 6; commit deferred к Phase 8 §15.4 post-approval | §13, §15 |
| **D2** | No state.md created — compaction mid-Phase 5 round 2 = total loss of approved sections, revision count, prior AUQ answers | `SKILL.md`, `brainstorming-loop.md` (no state.md mentions) | M1 T1 state.md created в Phase 0; lives throughout; `approvals[]` schema P-M1-1 persists every AUQ answer | §7, §21 |
| **D3** | Phase 0 Refine path lossy — design doc has no machine-readable section boundaries; "jump к Phase 5 с existing sections as starting state" guesses what а section is | `SKILL.md:46-49`, `brainstorm-reference.md:9-16` | Refine path removed (§3.1). DESIGN_DOC → "start fresh с this as context?" AUQ; if user picks "start fresh", flows к Phase 1 с the doc inlined as Phase 1 explore context (not as section template) | §7.2 |
| **D4** | Phase 1 "≥2 file citations OR 'no related code'" rule unverifiable — model can write "I looked around and didn't find anything" without spawning Explore agents | `brainstorming-loop.md:17` | Echo contract — each Phase 1 Explore spawn writes а structured entry к `## Tool log` (surfaces в user view per M3 §6); Phase 7 validator checks `## Tool log` has ≥1 spawn entry per effort tier | §8.3, §14.2 check #3 |
| **D5** | Hand-off menu routes к `/features add` and `/decompose` — both deleted (master plan §65, §68) | `SKILL.md:81` | Hand-off menu = 2 options (`/implement` / `stop`); milestone-mode handled inline в Phase 5 (§12.3) — Big detection → emit sibling milestone-N.md, hand-off offers `/implement milestone 1` | §16 |

---

## 6. Phase 0 — Mode detect — **DECIDED** {#phase-0-overview}

The entry-gate phase. Resolves $ARGUMENTS к а mode (IDEA / DESIGN_DOC / CODE_REFERENCE) and creates state.md. Light cost — а single design-doc-detect.md helper call.

(Detailed contract in §7. Section number 6 reserved для the phase-overview entry-point; subsequent sections enumerate phase contracts.)

---

## 7. Phase 0 detail

State.md `phase: mode-detect` during this phase.

### 7.1 $ARGUMENTS resolution

Use `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` helper unchanged. Returns:

- **IDEA(topic)** — free-form text; flows к Phase 1 c topic as initial context.
- **DESIGN_DOC(path)** — existing design doc; flows к §7.2 AUQ.
- **CODE_REFERENCE(path)** — error per design-doc-detect.md per-consumer table.
- **None** (empty $ARGUMENTS) — fires empty-argument AUQ: "What do you want к plan?" с three options ("New feature" / "Existing problem to solve" / "Cancel") followed by free-text capture; non-empty answer → IDEA mode; "Cancel" → terminal.

### 7.2 DESIGN_DOC mode (Refine path removed — D3 fix)

When detection returns DESIGN_DOC:

1. Fire `AskUserQuestion` с header "Existing design doc":
   - **Start fresh с this as context** (Recommended) — load the doc into Phase 1 explore context; run full 8-phase loop; produce а new spec.md at а new task-dir.
   - **Cancel** — exit without writing state.md или creating task-dir.

2. If "Start fresh" → proceed к Phase 1 с the doc body inlined into the Phase 1 Explore-agent prompts under а `## Prior Design Doc` section. The doc is NOT used as section template (per D3 fix) — Phase 5 uses the 10-section P-M5-1 schema unconditionally.

3. If "Cancel" → exit immediately. Do NOT create state.md (no resume to recover). Surface terminal message: "Cancelled before planning started".

Rationale: The pre-M5 "Refine" option silently re-derived sections from prose, which downstream consumers couldn't parse reliably. "Start fresh" is honest about what happens; "Cancel" preserves the no-op exit path. The two intermediate options ("Keep doc verbatim" / "Edit sections directly") were considered и rejected: both require machine-readable section boundaries that the doc may not have.

### 7.3 Task-dir + state.md creation

After mode is resolved (IDEA или DESIGN_DOC-with-fresh-start), Phase 0 creates the task-dir и state.md:

1. **Resolve task slug** per M1 §Slug rules. Inputs: $ARGUMENTS topic (IDEA) или basename(design-doc) sans extension (DESIGN_DOC). Output: kebab-case slug ≤40 chars.
2. **Task-dir path:** `.geniro/planning/<task-slug>/` (М1 canonical).
3. **state.md path:** `.geniro/planning/<task-slug>/state.md`. Write via M1 `atomic_state_write`. Initial content:

```yaml
---
tier: T1                       # M1 §T1 required
producer: plan                 # M1 §T1 required
schema-version: 1              # M1 §T1 required
branch: <git-branch>           # M1 §T1 required
timestamp: <ISO-8601 UTC>      # M1 §T1 required
phase: mode-detect             # M1 §T1 required (free-form per-skill; M5 enum в §2.1)
status: in-progress            # M1 §T1 required (in-progress|done|failed)
non-resumable-actions: []      # M1 §T1 required
approvals: []                  # M1 §T1 optional (P-M1-1 schema)
task_slug: <slug>              # M5 extension
mode: <IDEA|DESIGN_DOC>        # M5 extension
---

# State: <topic>

## Inputs
- $ARGUMENTS: "<raw>"
- mode: <IDEA|DESIGN_DOC>
- design-doc-path (if DESIGN_DOC): <abs-path>

## Tool log

## Errors

## Open Questions
```

4. **Transition к Phase 1.** Update `phase: explore` via `atomic_state_write`.

### 7.4 Cancel handling

User picks "Cancel" в the empty-argument AUQ или the DESIGN_DOC AUQ → terminal `aborted` state. If state.md was NOT yet created (cancelled before task-slug resolution) → just emit terminal message и exit. If state.md WAS created (e.g., cancel happens deeper) → write `phase: aborted` + `## Termination reason: user-cancelled-at-phase-0` via `atomic_state_write` before exit.

---

## 8. Phase 1 — Explore

State.md `phase: explore` during this phase.

### 8.1 Memory layer loading (replaces pre-M5 LOAD_TIER: rules-only)

At Phase 1 entry, load **L4 + L3 + L2** (full tier, not rules-only):

| Helper | Inputs | Outputs | Echo contract |
|---|---|---|---|
| `load-custom-instructions` MODE: refresh | scope = `plan` + `global` + `code-style` | concatenated rule body inlined into context | per M3 §7.2 |
| `load-semantic` MODE: refresh | top-2 default: `_project.md` + `_CODEBASE_MAP.md` | inlined into context; fingerprint drift check | drift surfaces к user |
| `query-learnings` | tags inferred from $ARGUMENTS topic (e.g., `auth`, `caching`, `react`); scope = topic-area | top-K matching L2 entries (default K=5, filter superseded + deprecated) | n/a (read-only) |

Rationale: pre-M5 /brainstorm loaded только L4 rules. The audit found Phase 1 Explore agents worked blind к prior decisions (L2) и codebase map (L3) → repeated rediscovery of patterns already known. M5 closes this с full-tier load.

### 8.2 Effort-tier-scaled Explore spawns

Heuristic: detect effort tier from $ARGUMENTS shape using `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` rules.

| Tier | $ARGUMENTS examples | Explore spawns |
|---|---|---|
| Trivial | "rename foo → bar in CONFIG.md", single-file config tweaks, typo fixes | 1 agent (or 0 if obviously scope-bound) |
| Medium | "add OAuth to existing auth flow", feature additions touching 2-5 files | 2 agents (existing-impl + integration-surface) |
| Big | "redesign /implement", subsystem-level changes touching ≥10 files | 3-4 agents (subsystem-A + subsystem-B + cross-cutting + conventions) |

Each spawn uses the `Explore` agent type per the system-prompt's registered agents list (NOT а plugin-defined agent — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` ladder is for plugin agents only). Spawn prompts pre-inline context per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` (6 required fields).

Per-spawn output schema: `[{file, lines, observation}]` — a JSON-shaped finding list. Cap: ~4000 chars per agent (truncation marker).

### 8.3 Echo contract (D4 fix — replaces pre-M5 unverifiable ≥2-citation rule)

Each Phase 1 Explore spawn writes а structured entry к state.md `## Tool log` body section via `atomic_state_write`:

```yaml
## Tool log
- ts: 2026-05-17T10:42:13Z
  tool: Agent
  detail: "Explore: existing auth flow integration points"
  status: ok
  summary: "found 3 files, 1 convention pattern"
  citations:
    - src/auth/oauth.ts:42-58
    - src/auth/__tests__/oauth.test.ts:14-29
    - src/middleware/session.ts:88-101
```

Phase 7 validator checks (§14.2 check #3): `## Tool log` has ≥1 Agent entry с `status: ok` per effort tier. Trivial: ≥1 (or explicit `## Tool log` entry «scope-bound, no exploration needed» с rationale). Medium: ≥2. Big: ≥3.

The `## Tool log` entries surface к user via M3 SessionStart re-injection on resume — so claims of «no related code» are auditable.

### 8.4 Transition к Phase 3

After Explore spawns return (parallel batch in а single message — per system-prompt parallel rule), the model synthesizes findings into а brief inline summary held в context. No separate artifact written — the summary feeds Phase 3 question generation и Phase 5 section authoring directly. State.md `phase: clarify` written before Phase 3 entry.

**Skip к Phase 4 if Trivial:** when effort tier is Trivial AND Explore returned 0-1 findings AND topic is а narrow text-edit (rename / config tweak / typo fix), Phase 3 (clarifying questions) is skipped — flow goes directly к Phase 4 (approaches). The model writes а one-line note к state.md `## Open Questions` confirming "Phase 3 skipped — trivial task, no ambiguity surfaced". User can re-enter Phase 3 if needed via а revision pass.

---

## 9. Phase 2 — DROPPED (rationale)

Phase 2 of pre-M5 /brainstorm was а "visual companion" — textual UI sketch produced by а haiku-tier general-purpose agent, presented к user, with up к 3 revision rounds. M5 drops it. Three reasons:

1. **Sketch doesn't persist into spec.md.** Phase 6 of pre-M5 /brainstorm wrote the design doc directly от Phase 5 approved sections; ui-preview.md was не cited. The sketch died в chat. Any UI intent the user wanted к pin down had к be re-described в Phase 5 anyway.

2. **Phase 5 sections cover UI when topic warrants.** The P-M5-1 schema (§17) section 6 ("Steps") и section 9 ("Validation") naturally absorb UI sketches when the task is UI-bearing. Implementation agents (M4 backend/frontend) read the section content directly от spec.md. The pre-M5 ui-preview-gate.md procedure can be invoked by /implement Phase 1 if it predicts UI files в scope (M4 §6 already mentions Pre-Ship Visual Verification via Playwright).

3. **Sub-loop cost не worth it.** Visual companion fired UNCONDITIONALLY for every /brainstorm run regardless of whether the topic was UI. Even на а DB migration ideation pass, the visual companion fired ("describe the UI" with а note that there is no UI). Cost = 1 AUQ + 1 haiku spawn + potentially 3 revision rounds = up к 4 AUQs of friction для near-zero UI tasks.

**Migration note:** existing /brainstorm flows that relied on the visual companion для UI tasks should now describe UI intent в Phase 3 clarifying questions ("Should we add а new screen или extend an existing view?" — the model proactively asks if Phase 1 explore found UI-bearing files в scope) и в Phase 5 section content ("Steps" section captures UI structure при authoring).

---

## 10. Phase 3 — Clarifying questions

State.md `phase: clarify` during this phase.

### 10.1 Question generation

The model identifies up к 5 highest-leverage ambiguities в the task definition. Sources:
- Phase 1 Explore findings ("found 3 auth flows — which one is the integration surface?")
- L2 query-learnings ("prior decision favored Approach X — does it apply here?")
- L4 code-style rules ("project uses event-sourcing pattern; does the new feature follow it?")

Per the audit (§5 #D4), questions MUST be grounded в Phase 1 findings — generic "what tech stack?" questions are forbidden (the model can answer those from L3 `_project.md`).

### 10.2 One-at-a-time AUQ shape

Fire questions sequentially, **never** as а multi-question form. Each AUQ:
- `header`: short label (≤12 chars), e.g., "Auth method", "Integration", "Scope".
- `question`: 1-2 sentences ending in а question mark.
- `options[]`: 2-4 explicit choices. ALWAYS include а "Skip — proceed с stated assumption" option as the last choice when applicable.
- `multiSelect: false` unless explicitly multi-select.

Empirically — confirmed via pre-M5 /brainstorm user feedback — one-at-a-time is preferred to multi-question forms. M5 preserves it.

### 10.3 Persistence (P-M1-1 closure)

Each answered AUQ → append entry к state.md frontmatter `approvals[]` via `atomic_state_write` BEFORE proceeding to the next question. Entry schema per M1 P-M1-1:

```yaml
approvals:
  - category: clarify_auth_method
    prompt: "Which existing auth flow should the new feature integrate with?"
    options: ["OAuth (src/auth/oauth.ts)", "JWT (src/auth/jwt.ts)", "Skip — proceed assuming OAuth"]
    picked: "OAuth (src/auth/oauth.ts)"
    at: 2026-05-17T10:50:00Z
    asked_in_phase: clarify
```

On compaction-resume, M3 §6 Block 5d renders this — the model re-reads `approvals[]` и skips already-answered questions.

### 10.4 Cap exhaustion

If the model has identified а 6th clarification к ask, force consolidation OR proceed к Phase 4 с stated assumptions. The 5-AUQ cap is а quality-first signal: more than 5 means Phase 1 explore underspecified the problem или the topic is too vague для а single /plan session. Surfacing the consolidation choice к the model (not к the user) is the right level — the user already shoulders 5 AUQs of friction; а 6th is friction-noise.

---

## 11. Phase 4 — Approaches

State.md `phase: approaches` during this phase.

### 11.1 Approach generation

The model synthesizes Phase 1 explore findings + Phase 3 clarifying answers into 2-3 distinct approaches к the problem. Each approach:
- **Name** (3-5 word label, e.g., "Wrapper Service", "Inline Refactor", "Event-Sourced Path").
- **Summary** (2-3 sentences).
- **Trade-off** (1 sentence: what you gain, what you give up).
- **Effort estimate** (Trivial / Medium / Big per effort-scaling.md).

### 11.2 AUQ shape

Single-select AUQ; `Recommended` first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md` pattern.

- `header`: "Approach"
- `question`: "Which approach do you want к pursue?"
- `options[]`:
  - Approach 1 (Recommended) — `label`: "<Name> (Recommended)"; `description`: summary + trade-off
  - Approach 2 — `label`: "<Name>"; `description`: summary + trade-off
  - Approach 3 (if generated) — `label`: "<Name>"; `description`: summary + trade-off

### 11.3 Persistence

User pick → append к `approvals[]` с category `approach_choice`:

```yaml
- category: approach_choice
  prompt: "Which approach do you want к pursue?"
  options: ["Wrapper Service (Recommended)", "Inline Refactor", "Event-Sourced Path"]
  picked: "Wrapper Service (Recommended)"
  at: 2026-05-17T10:55:00Z
  asked_in_phase: approaches
```

Other approaches captured к а body section `## Considered Alternatives`:

```markdown
## Considered Alternatives

### Inline Refactor (rejected)
Summary: ...
Trade-off: smaller surface change, but locks us into existing module shape.
Why rejected: violates new boundary established in Q3 2026 architecture review.

### Event-Sourced Path (rejected)
Summary: ...
Trade-off: future-flex, but ≥3 weeks of build-out for а feature this small.
Why rejected: overkill given scope.
```

`## Considered Alternatives` is later copied к the spec.md body verbatim (Phase 6 §13). M4 /implement reads it but is not bound by it — it informs context, not gating.

---

## 12. Phase 5 — Section approval

State.md `phase: section-approve` during this phase.

### 12.1 Section template (P-M5-1 closure)

Use the **fixed 10-section P-M5-1 schema** detailed in §17. М5 does NOT support "1-6 sections scaled by complexity" (pre-M5 free-form). Every spec.md has exactly the same 10 sections — schema-stable downstream consumers.

For trivial tasks (effort tier Trivial), sections 4 (Assumptions), 5 (Risks), 10 (Rollback-Recovery) may have body content "none — task scope precludes" с brief rationale. They MUST exist as section headers; they MUST NOT be omitted.

### 12.2 Per-section AUQ

One AUQ per section, sequentially. For each:

1. **Author the section content** based on Phase 1 explore + Phase 3 answers + Phase 4 picked approach. Pre-fill all 10 sections in а single batch BEFORE the first per-section AUQ — this lets the user see flow и identify cross-section issues early.
2. **Render the section to the user** (the model writes the section content to chat as а markdown block).
3. **Fire AUQ** с header "Section: <name>":
   - **Approve** (Recommended) — proceed к next section.
   - **Revise — I'll describe** — user provides revision text; model re-authors the section и re-fires the AUQ (max 3 revisions per section).
   - **Skip — accept as-is с warning** — proceed without explicit approve (rare; for sections like Rollback-Recovery on trivial tasks).
4. **Persist** each pick к `approvals[]` с category `section_<id>` (e.g., `section_objective`, `section_scope_included`).

After 10 sections approved → transition к Phase 6.

### 12.3 Milestone-mode (absorbs /decompose)

If during section authoring the model detects а Big task (effort tier Big AND section 6 «Steps» has ≥10 discrete steps OR estimated wall-time ≥1 day), fire а new AUQ before Phase 6 entry:

- `header`: "Milestone slicing"
- `question`: "This task is large enough to slice into milestones. Slice it now или keep as а single spec?"
- `options[]`:
  - **Slice into milestones** (Recommended for Big) — model proposes 3-7 milestone names; user approves; Phase 6 emits sibling milestone-N.md files alongside spec.md.
  - **Keep as а single spec** — Phase 6 emits only spec.md; /implement consumes the whole thing.

If "Slice into milestones" picked:
1. Fire а follow-up AUQ с the proposed milestone names (single-select for "approve all" / multi-select for "edit which") — multi-select pattern с preview per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`.
2. After approval, Phase 6 writes:
   - `.geniro/planning/<task-slug>/spec.md` — top-level spec с the 10 sections; section 6 «Steps» lists milestones (not raw steps); section 11 (added body section beyond the 10) «Milestones» indexes the sibling files.
   - `.geniro/planning/<task-slug>/milestone-1.md`, `milestone-2.md`, …, each с its own 10-section P-M5-1 schema scoped к the milestone.

Hand-off (Phase 9 §16) offers `/implement milestone 1` for sliced specs.

Rationale: /decompose was deleted (master plan §65). М5 absorbs the milestone-authoring responsibility — but only when the task warrants it. For Medium/Trivial, the milestone-mode AUQ does not fire.

---

## 13. Phase 6 — Write spec.md

State.md `phase: write-spec` during this phase.

### 13.1 Write contract

Path: `.geniro/planning/<task-slug>/spec.md` (M1 canonical).

Content structure: §17 P-M5-1 schema (10 sections) + frontmatter с §18 P-M5-2 goal block + body sections (`## Considered Alternatives` от Phase 4, `## Tool log` references к state.md).

Use the `Write` tool. The plan-mode mutation guard (§19) allows `Write` only under `.geniro/planning/**` — а write к anywhere else is blocked at PreToolUse.

After writing spec.md, append а `## Tool log` entry to state.md via `atomic_state_write`:

```yaml
- ts: 2026-05-17T11:08:00Z
  tool: Write
  detail: ".geniro/planning/<slug>/spec.md"
  status: ok
  result_ref: "<bytes-count>"
```

### 13.2 NO auto-commit (D1 fix)

М5 does **not** `git commit` at Phase 6 exit. The pre-M5 auto-commit (`brainstorming-loop.md:109`) violated Always-WAIT — if Phase 8 returned "Request changes", а second commit fired per round, polluting git history.

The `git commit` is deferred к Phase 8 post-approval (§15.4). At Phase 6 exit, spec.md sits unstaged on disk; state.md `phase: validate` written before Phase 7 entry.

### 13.3 Milestone-mode write fan-out

If milestone-mode was picked в Phase 5 (§12.3), Phase 6 writes the top-level spec.md AND every milestone-N.md в а single phase pass. Each milestone-N.md follows the same P-M5-1 schema scoped к its slice. After all writes, transition к Phase 7 once.

### 13.4 Idempotent re-entry (compaction-safe)

If Phase 6 is re-entered after compaction (M3 SessionStart), the model:
1. Reads state.md `approvals[]` — every section_<id> approval is present per Phase 5 §12.2.
2. Re-authors spec.md content от the persisted approvals.
3. Re-writes spec.md (overwrite — `Write`, not `Edit`, since this is idempotent regeneration).
4. Re-appends а `## Tool log` entry с note `(re-entry — post-compaction regeneration)`.

This is why Phase 5 per-section approvals MUST include the section content (or а pointer к it). M1 §T1 schema for `approvals[]` carries а `body_ref` field for content too long к inline; the body_ref points к а task-dir-scoped append-only log (`.geniro/planning/<slug>/section-bodies.jsonl`) — schema TBD в implementation phase (OQ-M5-2).

---

## 14. Phase 7 — Mechanical validator

State.md `phase: validate` during this phase.

### 14.1 Replaces pre-M5 self-review (D-not-numbered: not а defect, but а quality bug)

Pre-M5 Phase 7 was а free-form Opus self-prompt against 4 checks (placeholders / contradictions / ambiguous wording / scope creep). The audit (§5) noted this is linter-grade work better mechanized.

М5 Phase 7 is а **deterministic validator** — script-checkable rules executed by the orchestrator (no LLM round-trip per check). Total cost: ~50 lines of orchestrator-side logic, near-zero token usage, deterministic. Replaces the pre-M5 Opus self-prompt (~3000-5000 tokens per invocation, non-deterministic).

### 14.2 Validator checks (P-M5-4 closure)

Run all 13 checks in sequence; each returns pass/fail с а structured finding entry если fail. Output: list of `(check_id, status, finding_text, fix_hint)` tuples.

**P-M5-4 good-goal criteria (9 checks):**

1. **single_objective** — section 1 (Objective) body contains exactly one sentence ending в а period, declarative form (not imperative, not interrogative). Heuristic: sentence-count and final-token check.
2. **bounded_scope** — sections 2 (Scope.Included) и 3 (Scope.Excluded) BOTH have at least one bullet OR section 3 has body content "none — open scope" с explicit rationale. Heuristic: bullet-count.
3. **source_materials** — `## Tool log` body of state.md has ≥1 Agent entry с `status: ok` per effort tier (Trivial ≥1 OR explicit "scope-bound" note; Medium ≥2; Big ≥3). Also: spec.md section 6 (Steps) cites ≥1 file:line reference per non-trivial step.
4. **allowed_tools** — frontmatter `tools_required` field is а non-empty list (если spec section 7 «Tools Required» is non-empty body) OR field is `null` (если section 7 body is "none"). Field presence + body alignment.
5. **forbidden_actions** — frontmatter `forbidden_actions` is а non-empty list when the task touches sensitive areas (auto-detected: presence of `auth`/`secret`/`migration`/`payment` keywords в section 1 Objective или section 2 Scope.Included). Otherwise `null` OK.
6. **budget** — frontmatter `budget` block has all 3 sub-fields (max_files_to_edit / max_lines_changed / time_budget). Values may be `null` for unbounded, but the keys MUST be present.
7. **checkpoints** — frontmatter `checkpoints` is а non-empty list if section 6 (Steps) has ≥5 steps. Each checkpoint MUST reference а step-N anchor or section-name.
8. **validation_method** — section 9 (Validation) has body content; either references а test type (`unit`, `integration`, `e2e`) или specifies а manual-verification procedure.
9. **stopping_condition** — section 11 (Done Condition) has body content matching pattern «<observable signal>» (e.g., «all 5 acceptance tests green», «PR approved by stakeholder X»). Heuristic: regex match against а small ontology of observable-signal phrases.

**Legacy checks (4, retained from pre-M5):**

10. **placeholder_scan** — body of spec.md contains zero of: `TODO`, `XXX`, `FIXME`, `<placeholder>`, `[fill in]`, three-dot ellipsis as а standalone token. Heuristic: regex.
11. **contradiction_heuristic** — section 2 (Scope.Included) и section 3 (Scope.Excluded) have no shared bullet token (case-insensitive whole-word). Heuristic: token-set intersection.
12. **scope_creep_marker** — section 6 (Steps) contains no step beyond the file/feature surface declared в section 2 (Scope.Included). Heuristic: extract file paths from section 6 bullets и check each is а subset of paths в section 2 OR matches а glob declared в section 2.
13. **schema_completeness** — all 10 P-M5-1 sections present с correct header text (case-sensitive match against the spec в §17). NO extra top-level sections beyond the 10 + the optional body sections `## Considered Alternatives`, `## Milestones`.

### 14.3 Hard-fail handling

If any check fails:
1. Write findings к state.md `## Open Questions` body section as а structured list (one bullet per failed check, с `fix_hint`).
2. Re-author the failing sections (orchestrator-side: the model re-reads its own draft + the validator findings + the `fix_hint`s, и rewrites only the failing sections).
3. Re-run validator. Max 3 auto-revision rounds.
4. If round 3 still fails → fire `AskUserQuestion` с header "Validator hard-fail":
   - **Accept as-is** — proceed к Phase 8 user-approve с the failed checks documented in `## Open Questions`; user has final say.
   - **Re-revise** — kick а fresh round-1 cycle (rare; usually indicates schema misunderstanding the LLM cannot self-correct).
   - **Abort** — terminal `aborted` + `## Termination reason: phase-7-validator-hard-fail`.

### 14.4 No state transition к Phase 8 if validator hard-fails

The validator is а gate, not advisory. Phase 8 user-approve MUST see а validator-clean spec.md (or one где hard-fails were explicitly accepted by the user via §14.3 path A). This protects Phase 8 от the «user approves blind» failure mode (D-related к P-M5-5 closure).

---

## 15. Phase 8 — User approval

State.md `phase: user-approve` during this phase.

### 15.1 Approval AUQ — P-M5-5 closure

The pre-M5 Phase 8 AUQ body was «Spec committed to <path>. Review it?» — user approved blind without seeing the substance. M5 fires а **schema-rich AUQ** carrying the 7 P-M5-5 fields inline in the question body.

### 15.2 AUQ shape

- `header`: "Approve spec"
- `question`: multi-line markdown rendering the schema digest:

```
Spec ready at .geniro/planning/<slug>/spec.md.

**Objective:** <section 1 body — single sentence>

**Scope:** <bullet count from section 2 Included + section 3 Excluded summary>

**Approval Points:** <bullet list от section 8 «Approval Points», max 5 shown с «… and N more» if >5>

**Risk class:** <auto-computed: «low» / «medium» / «high» based on section 5 Risks bullet count + section 7 forbidden_actions field>

**Rollback:** <section 10 body summary, 1-2 sentences>

**Done Condition:** <section 11 body — observable signal>

**Scope summary:** <touched-file glob count from section 2 Scope.Included>

**Expiration:** Approval valid for the current planning session; re-approval needed if spec.md is edited after this point.

How do you want к proceed?
```

- `options[]`:
  - **Approve — proceed к hand-off** (Recommended) — Phase 9 hand-off menu fires next.
  - **Request changes — I'll describe** — fires а sub-AUQ for user revision text; revisions re-run sections affected (max 3 user-revision rounds before §15.3 escalation).
  - **Abort — discard spec** — terminal `aborted` + `## Termination reason: user-rejected-at-phase-8`; spec.md remains on disk но не committed.

### 15.3 Revision-round escalation

Max 3 user-revision rounds (Phase 8 → re-enter affected sections in Phase 5 → re-validate в Phase 7 → re-fire Phase 8 AUQ).

On round 3 exhaust, fire escalation AUQ с header "Phase 8 exhausted":
- **Accept as-is** — final answer; proceed к hand-off.
- **Re-revise (kick fresh cycle)** — full round-1 restart; rare.
- **Abort** — terminal `aborted` + `## Termination reason: repeated-failure: phase-8 revision-limit-3`.

### 15.4 Approve → git commit (D1 fix)

On user picks "Approve":
1. **Persist approval** к `approvals[]` с category `final_approve`:
   ```yaml
   - category: final_approve
     prompt: "Approve spec at <path>?"
     options: [...]
     picked: "Approve — proceed к hand-off"
     at: 2026-05-17T11:25:00Z
     asked_in_phase: user-approve
   ```
2. **`git commit`** fires here (NOT in Phase 6):
   - `git add .geniro/planning/<slug>/spec.md` + every sibling milestone-N.md
   - `git commit -m "plan: <task-slug> — <one-line summary от section 1 Objective>"`
3. **Append к `non-resumable-actions[]`** per M3 §8 schema:
   ```yaml
   non-resumable-actions:
     - action: git-commit
       completed-at: 2026-05-17T11:25:30Z
       commit-sha: <sha>
       files: [".geniro/planning/<slug>/spec.md"]
   ```
4. **Transition к Phase 9** (`phase: handoff`).

If the commit fails (pre-commit hook denial, working-tree-dirty conflict, etc.), surface а structured error к user — do NOT proceed к Phase 9 with а stale state. Fall back к Phase 8 escalation (§15.3) с the error inlined в the question.

---

## 16. Phase 9 — Hand-off

State.md `phase: handoff` during this phase.

### 16.1 Hand-off menu (D5 fix — 2 options replaces 4)

Fire `AskUserQuestion` с header "Next step":

- **/implement directly** (Recommended) — exit /plan, suggest the next command. For non-milestone specs: `/implement .geniro/planning/<slug>/spec.md`. For milestone specs: `/implement .geniro/planning/<slug>/milestone-1.md`.
- **Stop — keep spec for later** — terminal exit; spec sits на disk; user resumes when ready via `/implement <path>`.

Pre-M5 options for `Add to backlog (/features add)` and `Decompose (/decompose)` are removed — both skills deleted per master plan §65, §68. The milestone responsibility is absorbed into Phase 5 (§12.3); the «backlog» responsibility was always vestigial — а design doc on disk is already а backlog item.

### 16.2 Persistence

User pick → append к `approvals[]` с category `handoff`:

```yaml
- category: handoff
  prompt: "Next step?"
  options: ["/implement directly", "Stop — keep spec for later"]
  picked: "/implement directly"
  at: 2026-05-17T11:30:00Z
  asked_in_phase: handoff
```

### 16.3 Terminal transition

After hand-off pick:
- **/implement** picked → emit а one-line directive in chat (`Next: /implement .geniro/planning/<slug>/spec.md`); do NOT auto-invoke /implement (that's user agency). State.md `phase: done`.
- **Stop** picked → emit а one-line directive in chat (`Spec saved. Resume via: /implement .geniro/planning/<slug>/spec.md`); state.md `phase: done`.

Both paths terminate в `done`. М3 SessionStart recovery treats it as completed.

---

## 17. spec.md schema — P-M5-1 closure {#spec-schema}

The canonical 10-section schema. Every spec.md emitted by М5 conforms к this schema (validated by Phase 7 §14.2 check #13).

### 17.1 Frontmatter

```yaml
---
tier: T1                                # M1 §T1 required (spec.md lives в task-dir)
producer: plan                          # M1 §T1 required
schema-version: 1                       # M1 §T1 required
branch: <git-branch>                    # M1 §T1 required
timestamp: <ISO-8601 UTC>                # M1 §T1 required
geniro_kind: design-doc                  # design-doc-detect.md contract — required marker
geniro_schema_version: m5-v1             # M5 schema version
task_slug: <slug>                        # M5 extension
topic: <one-sentence-topic>              # M5 extension
mode: <IDEA|DESIGN_DOC-fresh>            # M5 extension
effort_tier: <trivial|medium|big>        # M5 extension
lifecycle: draft                         # M5 design-doc lifecycle (draft|approved|superseded); renamed от `status:` to avoid clash с M1 §T1 state `status: in-progress|done|failed`
budget:                                  # P-M5-2 goal-state block — start
  max_files_to_edit: <int|null>
  max_lines_changed: <int|null>
  time_budget: <duration|null>           # e.g., "4h", "1d", or null for unbounded
checkpoints:                             # list of {step_anchor, name} pairs
  - step_anchor: step-3
    name: "DB migration applied"
  - step_anchor: step-7
    name: "Tests green"
forbidden_actions:                       # list of explicit "don't do this" rules
  - "do NOT modify production database schema directly — use migrations only"
  - "do NOT bypass auth middleware"
approval_required_for:                   # list of step_anchors что require user approval before /implement proceeds
  - step-3
  - step-9
tools_required: ["pnpm", "docker", "gh"]  # CLI tools the implementer needs in env — P-M5-2 goal-state end
---
```

Fields 1-5 (tier through timestamp) are M1 §T1 required base. Fields 6-12 (geniro_kind through lifecycle) are M5 schema markers + extensions. Fields 13-17 (budget through tools_required) are the P-M5-2 goal-state block embedded в frontmatter per H-2.

**Note on `status:` namespace.** M1 §T1 reserves `status:` для state lifecycle (`in-progress|done|failed`). M5 design-doc lifecycle uses а distinct key (`lifecycle:` — values `draft|approved|superseded`) к avoid clash. State-tracking уже handled via the state.md sibling file (§7.3), so spec.md doesn't need the M1 `status:` field.

### 17.2 Body — 10 sections

```markdown
<!-- geniro:design-doc -->

# <Topic Title>

## 1. Objective

<Single declarative sentence stating the goal.>

## 2. Scope — Included

<Bullet list of files / features / behaviors changed by this task.>

## 3. Scope — Excluded

<Bullet list of adjacent things NOT changed. Use "none — open scope" с rationale if scope is intentionally unbounded.>

## 4. Assumptions

<Bullet list of assumptions the plan rests on (e.g., "OAuth library version ≥2.5", "test DB is available"). Use "none" if scope precludes assumptions.>

## 5. Risks

<Bullet list of known risks с severity (low/medium/high) и mitigation. Use "none" с rationale if scope precludes risks.>

## 6. Steps

<Numbered list of implementation steps. Each step:
- has а 1-line description
- cites ≥1 file:line reference (Phase 1 explore-grounded)
- has optional anchor `<!-- step-N -->` for checkpoint/approval-required references>

## 7. Tools Required

<Bullet list of tools the implementer needs (CLI tools, MCP servers, environment variables). Use "none" if the task is а pure-code change.>

## 8. Approval Points

<Bullet list pointing к specific steps что require user-approval gates during /implement run. References step anchors. Use "none" if /implement may run autonomously start-to-finish.>

## 9. Validation

<Body describing how к verify the implementation worked. References test types (unit/integration/e2e) or а manual verification procedure.>

## 10. Rollback-Recovery

<Body describing how к revert the change cleanly if it goes wrong. Includes commit-revert plan, data-migration rollback, feature-flag toggle, или explicit "no rollback needed — pure additive" с rationale.>

## 11. Done Condition

<Single statement of the observable signal that the task is complete. E.g., "all 5 acceptance tests green AND PR approved" / "feature ships behind flag AND telemetry shows ≥1 successful use".>
```

(Note: section 11 is the 10th sectioned body section but uses heading level «## 11.» — the count starts at 1, not 0; the schema-completeness check counts 10 sections, ## 1 through ## 11 reading «11 = Done Condition» as section 10. Pedantic count adjustment for header consistency.)

Body sections beyond the 10 (allowed):
- `## Considered Alternatives` — captured от Phase 4 (§11.3). Always present if Phase 4 ran с ≥2 approaches.
- `## Milestones` — captured от Phase 5 milestone-mode (§12.3). Present only if milestone-mode was picked.

### 17.3 Per-section content guidance

**Section 1 (Objective):** ONE sentence. NOT а problem statement, NOT а user story, NOT а title — а declarative goal. Examples:
- ✅ "Add OAuth login к the customer portal."
- ❌ "We need OAuth because users keep complaining about password resets." (problem statement, not objective)
- ❌ "As а customer, I want к login с OAuth." (user story, not objective)

**Section 6 (Steps):** Each step cites ≥1 file:line reference unless it's а meta-step (e.g., "Step 1: Create new branch"). Phase 7 validator §14.2 check #3 enforces this.

**Section 8 (Approval Points):** This is the contract /implement reads to know when к pause for user gates. М4 Phase 2 inner loop checks this at the start of each step и fires an AskUserQuestion if the step anchor matches an Approval-Points entry. М5 ↔ М4 contract.

**Section 10 (Rollback-Recovery):** «none — pure additive» is а valid body BUT must be explicit. Phase 7 validator does not auto-fail if body is «none» — it auto-fails if body is empty.

---

## 18. goal-state frontmatter block — P-M5-2 closure {#goal-state}

Per H-2 decision: goal-state lives **in spec.md frontmatter**, NOT а separate goal.md file. Rationale:
- 1 fewer file to maintain consistency between.
- M4 /implement already reads spec.md frontmatter at Phase 1 (M4 §5.4) — adding goal-state к the same place is а zero-cost integration.
- Separate goal.md is an SDD-canonical pattern (Forge, OpenSpec), но they target а different audience (humans reading а planning canvas). M5's audience is the model + а compaction-safe harness — frontmatter wins.

The 6 P-M5-2 goal-state fields:

| Field | Type | Purpose | Phase 7 check |
|---|---|---|---|
| `status` | enum: `draft` / `approved` / `superseded` | Lifecycle marker. `draft` during /plan run; `approved` set by Phase 8 §15.4; `superseded` set by а future /plan run that explicitly replaces this spec | — |
| `budget.max_files_to_edit` | int / null | Soft cap M4 checks during Phase 1 analyze — if predicted file count > cap, M4 surfaces а warning AUQ | #6 (presence) |
| `budget.max_lines_changed` | int / null | Soft cap M4 checks during Phase 2 implement — if diff line count > cap, M4 surfaces а warning AUQ | #6 (presence) |
| `budget.time_budget` | duration / null | Informational; M4 does not enforce, but М6 /review may flag if wall-time of /implement run exceeds budget | #6 (presence) |
| `checkpoints` | list of {step_anchor, name} | M4 reads at Phase 1; M4 Phase 2 surfaces а progress note at each checkpoint | #7 |
| `forbidden_actions` | list of strings | Hard-block list — М4 Phase 2 inner loop spawns an additional guard pass that checks each Edit/Write/Bash against these rules. Violation = М4 escalation | #5 |
| `approval_required_for` | list of step_anchors | М4 fires AskUserQuestion at each anchor before proceeding | — |
| `tools_required` | list of strings | М4 Phase 1 checks env for each tool; missing tool → escalation | #4 |

**Migration note:** Pre-M5 specs (legacy /brainstorm design docs) have no goal-state block. М4 /implement treats missing goal-state as «no budget, no checkpoints, no forbidden_actions, no approval_required_for, tools_required = whatever Phase 1 infers». Backward-compat path; no migration script needed.

---

## 19. Plan-mode mutation guard — P-M5-3 closure {#mutation-guard}

М5 /plan is а planning skill — it does NOT write code. The pre-M5 /brainstorm shipped с `allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task, AskUserQuestion, TodoWrite, WebSearch, WebFetch]` — mutation tools fully allowed. The audit (§5) noted this is а defect by design — а user-prompt mishap could induce /plan к write code mid-planning.

### 19.1 Two-layer guard

**Layer 1 — frontmatter `allowed-tools` minus `Edit`:**

```yaml
---
name: /geniro:plan
description: ...
allowed-tools: [Read, Write, Bash, Glob, Grep, Task, AskUserQuestion, TodoWrite, WebSearch, WebFetch]
---
```

Edit is removed entirely. Write is retained (needed для spec.md emission и state.md atomic writes via М1 helpers).

**Layer 2 — PreToolUse Bash guard scopes `Write`:**

A new hook in `hooks/plan-mode-write-guard.sh` (referenced via plugin.json's `hooks.preToolUse`) checks: when the active skill is `/geniro:plan` AND the tool call is `Write`, the target path MUST match the glob `.geniro/planning/**` OR `.geniro/state/**`. Otherwise block.

Hook pseudo-code:

```bash
# plan-mode-write-guard.sh
# Invoked by Claude Code PreToolUse hook on Write tool calls.
# Stdin: JSON envelope с {tool_name, args, active_skill}.
# Stdout: pass (exit 0) or block с message (exit 1 + stderr).

skill=$(jq -r '.active_skill' <<<"$payload")
[ "$skill" = "geniro:plan" ] || exit 0   # not /plan — pass

target=$(jq -r '.args.path' <<<"$payload")
if [[ "$target" == *.geniro/planning/* ]] || [[ "$target" == *.geniro/state/* ]]; then
  exit 0
else
  echo "plan-mode write-guard: /plan may only Write к .geniro/planning/** или .geniro/state/**" >&2
  exit 1
fi
```

Bypass: add `plan-mode-mutation` к `.geniro/safety.json` `allow_patterns` (per CLAUDE.md «Per-project allowlist for safety guardrails»).

### 19.2 Why two layers

Layer 1 (frontmatter) catches the easy 95% — Claude Code skill-frontmatter `allowed-tools` field is enforced by Claude Code's permission engine. But Write is retained (needed for spec.md), and unbounded Write is а risk.

Layer 2 (PreToolUse hook) scopes Write к safe paths. Belt + suspenders — а Skill frontmatter mod or а directive «write а draft of the implementation» from а compromised prompt cannot bypass the hook.

### 19.3 Bash exception

Bash is allowed in /plan для read-only operations (`git status`, `git log`, `git diff`, `gh pr view` для context-gathering). The PreToolUse Bash guard checks command shape — write-class Bash commands (`git push`, `gh pr create`, `rm`, `mv` outside `.geniro/`, etc.) ARE blocked by the existing safety hooks (CLAUDE.md «Safety Hooks» — git guardrails, file protection). Phase 8 §15.4 `git commit` IS allowed (specific commit-message pattern matched).

---

## 20. Cleanup checklist {#cleanup}

The pre-M5 surface and what changes под M5.

### 20.1 `skills/brainstorm/` — rename + rewrite

The directory is renamed `skills/brainstorm/` → `skills/plan/`. Files within:

- `SKILL.md` (118 lines, 9-phase loop coordinator) → **full rewrite** against this spec. Pre-M5 SKILL.md is structurally incompatible — surface area difference too large для surgical edit.
- `brainstorm-reference.md` (if present in repo — verify в implementation) → renamed `plan-reference.md`; surgical edit к match М5 phase structure.
- New: `spec-template.md` — the 10-section markdown template Phase 6 fills in. One source of truth для §17 schema.
- New: `validator-checks.md` — the 13 mechanical checks (§14.2) as а structured document the Phase 7 logic reads.

### 20.2 `skills/_shared/brainstorming-loop.md` — rename + rewrite

The directory is renamed `brainstorming-loop.md` → `plan-loop.md`. Full rewrite — pre-М5 166-line loop file is keyed к the 9-phase free-form pattern; М5's 10-phase fixed-schema pattern requires fresh prose.

### 20.3 `plugin.json` — slash command registration

Rename slash command registration from `/geniro:brainstorm` к `/geniro:plan`. Add а one-cycle alias entry: `/geniro:brainstorm` continues to work but logs а deprecation warning to chat, pointing к `/geniro:plan`. Remove the alias after one release cycle.

### 20.4 `CLAUDE.md` — skill-table row

The skill-table row for /brainstorm becomes:

| Skill | Purpose |
|---|---|
| `/geniro:plan` | Spec-first planning — 10-section spec.md + goal-state + mechanical validator. Replaces /brainstorm и /decompose. Absorbs milestone-mode для Big tasks. |

Remove the /decompose row entirely (already slated for deletion per master plan §65 / M4 §9.3).

### 20.5 `skills/_shared/design-doc-detect.md` — per-consumer table

Per-consumer behavior table needs the «/geniro:brainstorm» row renamed к «/geniro:plan» and the «AUQ "Design exists at <path>. Refine / Start over / Cancel"» line updated к the М5 contract (§7.2 — «Start fresh с this as context?» / «Cancel»). Refine path removed.

### 20.6 `skills/_shared/ui-preview-gate.md`

The ui-preview-gate.md procedure is no longer invoked by М5 /plan (Phase 2 dropped — §9). Verify other consumers — M4 /implement Phase 1 may invoke it pre-implementation если frontend files predicted. Keep the file. (Pre-M5 brainstorming-loop.md:21-40 invoked it; that invocation site is deleted under §20.2.)

### 20.7 `architecture/` — sibling docs

М5 is а sibling к M4 in `architecture/`. No cross-doc changes needed — M4 already references «/geniro:plan (M5 deliverable)» (M4 §5.1, §5.3, §12.1).

### 20.8 Hooks directory

Add `hooks/plan-mode-write-guard.sh` (per §19) — а new PreToolUse hook. Register в `plugin.json` `hooks.preToolUse[]`. Add «`plan-mode-mutation`» к the safety-allowlist documentation в CLAUDE.md «Per-project allowlist» section.

---

## 21. Memory I/O — M2 §13 obligation {#memory-io}

М2 §13 obligation: every pipeline skill's `.md` declares which L2/L3/L4 helpers it calls и at what phase boundaries. М5 inventory:

### 21.1 Helper-call schedule

| Phase | Helper | Direction | MODE | Inputs | Outputs | Notes |
|---|---|---|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` | scope = `plan` + `global` + `code-style` | concatenated rule body inlined into context | Echo contract per М3 §7.2. |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` | top-2 default (`_project.md` + `_CODEBASE_MAP.md`) | inlined into context + fingerprint drift check | Drift notification surfaces к user. Pre-M5 /brainstorm did NOT call this — M5 closes the gap. |
| Phase 1 entry | `query-learnings` | read L2 | n/a | tags inferred от $ARGUMENTS topic | top-K matching entries (default K=5) | Pre-M5 /brainstorm did NOT call this — M5 closes the gap. |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a | three loaded layers | precedence-resolved или AUQ on hard conflict | Transitive per М2 §10. |
| Phase 3 (Clarify) | none | — | — | — | — | Already-loaded L4/L3/L2 in context. |
| Phase 4 (Approaches) | none | — | — | — | — | Same. |
| Phase 5 (Section approve) | none | — | — | — | — | Same. |
| Phase 6 (Write spec) | M1 `atomic_state_write` | write T1 | n/a | state.md path; new ## Tool log entry | whole-file rewrite | After spec.md `Write`. |
| Phase 7 (Validate) | none | — | — | — | — | Deterministic — no helpers needed. |
| Phase 8 (User approve) | M1 `atomic_state_write` | write T1 | n/a | state.md path; append approvals[] + non-resumable-actions[] | whole-file rewrite | After `git commit`. |
| Phase 8 emit | `emit-learning` (conditional) | write L2 | n/a | producer = `/geniro:plan`; scope = task-area; summary = «approach: <name>»; type = `decision`; required `ext.{options, chosen, reasoning}` per M2 §5.2 typed-extension table | append к `learnings.jsonl` | Fires только if Phase 4 had ≥2 distinct approaches AND picked approach has «non-trivial trade-off» (heuristic flag set by Phase 4 prompt). Default trust `verified` per M2 §5.3 row /plan. Dedup + sanitization per М2 §5.2. |
| Phase 9 (Hand-off) | none | — | — | — | — | terminal — no helpers needed. |

### 21.2 L2 emit triggers (per М2 §5.3 patched contract)

| Type | When М5 emits |
|---|---|
| `convention` | Not emitted by М5. Conventions emerge from code, not plans. М4 /implement owns this trigger. |
| `decision` | Phase 8 approve — when Phase 4 had ≥2 distinct approaches AND the picked approach has а recorded trade-off rationale. M5 mirrors the decision к L2 для cross-session recall (e.g., future /plan на а similar topic queries L2 и surfaces the prior choice). |
| `diagnosis` | Not emitted by М5. /geniro:debug owns this. |
| `pitfall` | Not emitted by М5. /geniro:review owns this. |
| `discovery` | Not emitted by М5. /refactor и /onboard own this. |

### 21.3 L3 update sites

М5 does not write к L3. Spec.md is а planning artifact, not codebase. М4 /implement и М7 /debug handle `update-semantic` writes when code changes land.

### 21.4 Phase boundary refresh sites (М3 §7.3)

| Boundary | Refresh action | Why |
|---|---|---|
| Phase 1 entry | `load-custom-instructions(MODE: refresh)` + `load-semantic(MODE: refresh)` | Initial context load |
| Other phases | none | Sufficient к load once at Phase 1 entry. Phases 3-9 work от Phase-1-loaded context. Compaction mid-loop triggers М3 SessionStart re-injection, which re-reads layers via а fresh /plan turn. |

### 21.5 ACI per-phase tool surface

**Phase 0 (Mode detect):** Read / Bash (read-only — `ls`, `file` for path validation). No mutations.

**Phase 1 (Explore):** Read / Grep / Glob / Bash (read-only — `git status`, `gh pr view` для context). Agent spawns allowed (`Explore` agent type). No Edit/Write.

**Phase 2:** DROPPED.

**Phase 3-5 (Clarify / Approaches / Section approve):** Read / Grep / Glob / AskUserQuestion. No Edit/Write/Bash mutations. М1 `atomic_state_write` к state.md is allowed via Write tool — scoped by §19 PreToolUse guard к `.geniro/state/**`.

**Phase 6 (Write spec):** Write (scoped к `.geniro/planning/**` by §19 guard). М1 `atomic_state_write` к state.md (scoped к `.geniro/state/**`). No Edit, no Bash mutations.

**Phase 7 (Validate):** Read (read spec.md back to validate). No mutations. М1 `atomic_state_write` к state.md (for `## Open Questions` body — scoped).

**Phase 8 (User approve):** AskUserQuestion + Bash (`git add`, `git commit` — pattern-matched к а commit-message convention; blocked otherwise). М1 `atomic_state_write` (state.md updates).

**Phase 9 (Hand-off):** AskUserQuestion + Read (read spec.md path back). No mutations.

**Existing safety layer:** file-protection hook, git-guardrails, `.geniro/` deletion guard apply across all phases (CLAUDE.md «Safety Hooks»).

---

## 22. Cross-M dependencies & Implementation note {#cross-m}

### 22.1 М1 dependencies

- **M1 PR-0 (helpers)** must land before M5 implementation. Specifically: `atomic_state_write`, `validate_state_file`, `compute_task_slug`, plus T1 frontmatter schema including `approvals[]` (P-M1-1).
- **M1 P-M1-1** (approvals schema) — extended to М5 use. Phase 3, 4, 5, 8, 9 each persist entries к `approvals[]`. М1 schema MUST support categories: `clarify_<dim>`, `approach_choice`, `section_<id>`, `milestone_slice`, `final_approve`, `handoff`, `disambiguate_arguments` (last one for Phase 0 if AUQ fires).

### 22.2 М2 dependencies

- **М2 §13** (Memory I/O obligation) — §21 above closes М5's obligation.
- **М2 §5.3** (L2 emit triggers patched contract) — М5 emits `decision` per §21.2; trigger threshold tuning (P-M5 lacks dedicated threshold-OQ since the trigger condition is binary — ≥2 approaches + recorded trade-off).
- **М2 §9** (query-learnings helper) — М5 calls at Phase 1 entry (§21.1).

### 22.3 М3 dependencies

- **М3 SessionStart hook** — М5 state.md is recoverable via the same re-injection contract as М4. The hook re-reads `state.md` + `.geniro/instructions/plan.md` + `.geniro/instructions/global.md` + `.geniro/instructions/code-style.md` on session restart.
- **М3 §6 Block 5d** (approvals[] rendering) — М5 relies on this к present prior AUQ answers on resume.
- **М3 §7.2** (Echo contract) — М5 Phase 1 Phase-1-Explore-spawn echoes per this rule.

### 22.4 М4 ↔ M5 contract

М4 /implement reads:
1. spec.md frontmatter — primarily `goal-state` block (§18 — budget / checkpoints / forbidden_actions / approval_required_for / tools_required).
2. spec.md body — 10-section schema. М4 Phase 1 analyze validates the schema (per М4 §5.2 spec discovery) и errors if violated.
3. spec.md body — `## Considered Alternatives` is informational for М4; not gating.

М4 does NOT read state.md от /plan — state.md is /plan's internal lifecycle artifact. When /plan terminates, state.md sits на disk for audit but is not consumed downstream.

### 22.5 Work order

Implementation work-order:

1. ~~**Resolve Phase-level decisions (H-1 through H-10)**~~ ✅ DONE in this doc (§4).
2. **Apply §20.5 surgical edits к `design-doc-detect.md`** first (lowest risk).
3. **Add §20.8 PreToolUse hook** (`hooks/plan-mode-write-guard.sh`) + register в plugin.json.
4. **Write `skills/_shared/plan-loop.md`** (renamed/rewritten от brainstorming-loop.md) per §20.2.
5. **Write `skills/plan/SKILL.md`** per §20.1 — coordinator pointing к plan-loop.md.
6. **Write `skills/plan/spec-template.md`** + `skills/plan/validator-checks.md` per §20.1.
7. **Update plugin.json** slash registration per §20.3 (add alias `/geniro:brainstorm`).
8. **Update CLAUDE.md** skill-table per §20.4.
9. **Delete `skills/brainstorm/` directory** — git rm.
10. **Manual end-to-end test** against а small IDEA-mode and а small DESIGN_DOC-mode task before merging.

**Skill-deletion sequencing:** М5 deletes /brainstorm и replaces with /plan. M4 hand-off (M4 §3.1) mentions «/plan owns milestone semantics — /decompose deleted» — this М5 doc absorbs /decompose's responsibility (§12.3 milestone-mode). The /decompose directory deletion happens under М5's commit, not М4's. М4 must work whether /decompose or /brainstorm directory is present или already deleted; М4's spec discovery (M4 §5.2) reads spec.md, not those legacy directories.

---

## 23. Open questions (carried forward) {#open-questions}

All 10 design decisions (H-1 through H-10) closed in §4. М5-specific implementation-detail OQs:

| ID | Topic | Status |
|---|---|---|
| **OQ-M5-1** | **Phase 7 validator implementation surface** — should validator checks live in а dedicated Python script invoked by Bash, or be enumerated as inline orchestrator-side logic в SKILL.md/plan-loop.md? Trade-off: script = testable, has а DAG; inline = no infra, harder к unit-test. | ⏳ Deferred к implementation phase. Likely inline initially; promote к script if complexity grows. |
| **OQ-M5-2** | **section-bodies.jsonl schema** — Phase 5 per-section approvals need а place к store section content (too long для inline frontmatter). Schema: одна line per section_<id> approval? Append-only log? Versioned? | ⏳ Deferred к implementation. Schema lives in М1 helper, not in this doc. |
| **OQ-M5-3** | **Phase 1 Explore agent — bare `Explore` vs plugin-defined** — currently §8.2 uses Claude Code's built-in `Explore` agent. Should М5 спaspawn а plugin-defined `knowledge-retrieval-agent` instead (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` ladder)? `knowledge-retrieval-agent` queries L2 directly; `Explore` does not. | ⏳ Deferred. Tentative: keep `Explore` для file/code search; supplement с `query-learnings` direct call (already in §21.1) для L2. |
| **OQ-M5-4** | **Milestone-mode emit format** — milestone-N.md uses the same 10-section P-M5-1 schema scoped к the milestone. But should milestone-N.md frontmatter include а `parent_spec: <slug>` link к the top-level spec.md? | ⏳ Deferred. Tentative yes — М4 may need it для cross-milestone context. |
| **OQ-M5-5** | **Validator threshold tuning** — Phase 7 check #2 (bounded_scope) requires «at least one bullet OR rationale» в each scope section. Is this strict enough? Should we require N≥2 для non-trivial tasks? | ⏳ Deferred к implementation. Start с the loose form; tune based on real spec quality data. |

---

## 24. Master plan reconciliation {#master-plan}

The authoritative redesign reference is `/root/.claude/plans/reactive-dreaming-backus.md`. This section reconciles М5 (this doc) с the master plan.

### 24.1 Skill-list status (master plan §20 + §60)

М5 ships **`/plan`** as а new skill (master plan §22 entry). Replaces:
- `/geniro:brainstorm` — directory deleted under М5 commit.
- `/geniro:decompose` — directory deleted under М5 commit (responsibility absorbed via §12.3 milestone-mode).

М5 does NOT modify any other skill. М6 (`/review`), М7 (`/debug`), М4 (`/implement`) consume spec.md via their own М-doc contracts.

### 24.2 М5-specific obligations from master plan

| Master plan ref | Obligation | М5 status |
|---|---|---|
| §20 (skill rename) | `/brainstorm` → `/plan` | ✅ §3, §20.3 |
| §65 (delete /decompose) | Skill removed; responsibility absorbed somewhere | ✅ §12.3 milestone-mode |
| §68 (delete /features) | Skill removed; replaced by manual FEATURES.md or via /plan | ✅ §16.1 (hand-off menu /features removed) |
| §107 (P-M5-1) | spec.md 10-section schema | ✅ §17 |
| §107 (P-M5-2) | goal-state block (status/budget/checkpoints/forbidden_actions/approval_required_for) | ✅ §18 |
| §107 (P-M5-3) | plan-mode mutation block | ✅ §19 |
| §107 (P-M5-4) | 9 good-goal criteria checklist | ✅ §14.2 checks #1-9 |
| §107 (P-M5-5) | approval request schema (summary/exact actions/risk class/expected outcome/rollback path/scope/expiration) | ✅ §15.2 |

### 24.3 Stale assumptions corrected since draft

| Original draft assumption | Corrected (this rev) |
|---|---|
| Phase 0 Refine path is convenient — preserve it | Audit (§5 D3) — Refine is lossy. Force start-over. |
| Phase 2 visual companion is useful — preserve it | Audit — sketch doesn't persist. Drop. |
| Phase 7 Opus self-prompt is sufficient | Audit — linter-grade work. Mechanize. |
| Auto-commit at Phase 6 is fine | Audit (D1) — violates Always-WAIT. Defer commit к Phase 8. |
| /plan does NOT need plan-mode mutation guard — model judgment will suffice | Audit (P-M5-3) — model judgment is unaudited. Add guard. |
| Free-form sections scale better | Audit (P-M5-1) — downstream consumers can't reliably extract. Fix schema. |

---

## 25. Anti-rationalization (P-MP-1 closure) {#anti-rationalization}

Per master plan P-MP-1 (lines 162-179): every milestone closes с an explicit anti-pattern check. This section catalogues rationalizations а reader might offer to backtrack M5 decisions, paired с the counter-argument grounded в audit findings и architectural intent. Cross-cutting LLM-orchestration anti-patterns (auto-handle / hard kill caps / silent abort / bypass safety hooks) are addressed inline below where they would apply to M5.

| Your reasoning | Why it's wrong |
|---|---|
| "Phase 2 visual companion should stay — it's nice when planning UI." | UI intent that matters belongs в spec.md section 6 (Steps) и section 9 (Validation). The companion's textual sketch dies в chat — it's not cited by Phase 6 spec.md write, so any UI thinking it captured has к be re-described later. Phase 5 sections absorb the intent at the right granularity. |
| "Phase 0 Refine path saves three phases of re-work — keep it." | Refine path re-derived sections from prose. Prose doc → 10-section schema is а structurally-lossy operation; the model guesses, the user accepts а guess-with-side-effects, the downstream consumer parses а malformed-spec.md. "Start fresh с doc as context" is honest about what's actually happening and produces а schema-clean spec.md. |
| "Phase 7 mechanical validator misses cases а smart LLM would catch." | The 13 checks (§14.2) cover all 9 P-M5-4 criteria + 4 legacy linter checks. Phase 8 user-approve catches everything else — the user IS the smart-LLM check. Free-form Opus self-prompt was non-deterministic — sometimes caught issues, sometimes confabulated, always burned tokens. Mechanical = cheaper, faster, repeatable, и Phase 8 backs it up. |
| "Auto-commit at Phase 6 is convenient — drop а commit if Phase 8 rejects." | Rejection-induced commit-drop = forced `git reset` or `git revert` in а downstream branch. Pre-M5 /brainstorm shipped this pattern; it polluted git history (every revision round left а commit). Phase 8 post-approve commit is а single commit per approved spec — clean log. The «convenience» of auto-commit is а phantom — only the first commit is needed, every revision-induced commit is wasted. |
| "Plan-mode mutation guard is over-engineered — model can be trusted." | The model can be reasoned-with, jailbroken, or instructed via а compromised CLAUDE.md. The frontmatter `allowed-tools` field + PreToolUse Bash guard are the only mechanical layers between а bad-intent prompt и а modified source tree. Belt + suspenders. |
| "Goal-state в spec.md frontmatter conflates planning and execution metadata — split к а separate goal.md." | Separate goal.md is а UX-targeted artifact for human-readable planning canvases (Forge, OpenSpec). М5's consumer is М4 /implement reading spec.md frontmatter at Phase 1 analyze — one file is а zero-overhead read. Splitting creates а two-file consistency problem (does goal.md.budget agree с spec.md frontmatter? Who updates which when revising?). One canonical source. |
| "5 clarifying questions is too few для complex tasks." | Phase 3 ≤5 is а quality-first signal. If а task needs >5, Phase 1 explore underspecified the problem (Phase 1 should have surfaced the ambiguities) OR the task is too vague для а single /plan session. Force consolidation — better consolidated questions, NOT more questions. |
| "10-section spec.md schema is too rigid для small tasks." | For Trivial tasks, sections 4/5/10 can have body content `none — task scope precludes` с brief rationale (§12.1). The 10-section schema is structural commitment — every consumer can rely on section presence — not content commitment. Section 11 «Done Condition» is enforced (it's the observable signal) but its body для а Trivial task can be one sentence. |
| "Phase 7 validator hard-fail blocks user — they're stuck с automated revision rounds." | Phase 7 has а 3-round escalation cap. On round 3, AUQ surfaces к user (§14.3) с 3 options including «accept as-is». User has agency at all times — not blocked. |
| "Drop the milestone-mode AUQ — а Big task can just emit а spec and the user decides later." | The decision к slice into milestones IS а planning decision. Punting it к the user post-spec means they discover at /implement time that а 50-step spec is unmanageable, и must come back к re-plan. Surfacing the choice at Phase 5 (when both context AND user attention are present) is the right gate. |
| "Hand-off menu should keep `/features add` for backlog discipline." | /features is deleted (master plan §68). А «backlog» is а plan-shaped artifact on disk; spec.md saved-on-disk IS the backlog entry. No separate skill needed. |
| "Add а wall-time / token kill cap so runaway /plan sessions abort cleanly." | Class-A hard caps are forbidden by §2.3 quality-first framing. M5 has Class-B gates — Phase 7 validator 3-round cap (§14.3), Phase 8 user-revision 3-round cap (§15.3) — both escalate к user, do not abort. |
| "Auto-default empty AUQ answer к the Recommended option." | Forbidden by §10.2 («never auto-default»). Empty answer = upstream Claude Code bug; fall back к plain-text re-ask. Auto-default silently mutates user intent — а catalogued LLM-orchestration anti-pattern. |
| "Skip persisting Phase 3 clarifying answers — they're trivial." | The Metaswarm anti-pattern. Compaction mid-Phase-5 round 2 loses 5 AUQs of user input. P-M1-1 `approvals[]` persistence is the bulwark. Non-negotiable. |
| "Phase 6 should bypass the plan-mode mutation guard для performance." | §19 mutation guard is а safety contract, not а perf knob. The guard adds <1ms per Write (path glob check). Bypass invites the failure mode the guard exists to prevent. |
| "Bypass git pre-commit hooks с --no-verify when committing spec.md в Phase 8.4." | Hooks fail для а reason. Investigate root cause, не bypass. CLAUDE.md-level prohibition; M5 honors it. |

---

## 26. Cross-references {#cross-references}

- М1 (state-files framework): `architecture/M1-state-files.md`
- М2 (memory layers): `architecture/M2-memory-layers.md`
- М3 (compaction-survival): `architecture/M3-compaction-survival.md`
- М4 (/implement redesign): `architecture/M4-implement-redesign.md`
- design-doc-detect helper: `skills/_shared/design-doc-detect.md`
- spawn-agent ladder: `skills/_shared/spawn-agent.md`
- context-isolation checklist: `skills/_shared/context-isolation-checklist.md`
- effort-scaling helper: `skills/_shared/effort-scaling.md`
- per-finding-question helper: `skills/_shared/per-finding-question.md`
- medium-gate AUQ pattern: `skills/_shared/medium-gate.md`
- ui-preview-gate (now unused by М5; M4 retains): `skills/_shared/ui-preview-gate.md`

End of M5.
