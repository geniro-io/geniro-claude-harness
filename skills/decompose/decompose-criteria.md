# Decompose Criteria

This file is the structure contract for decomposed plans. Architect-agent (decomposition mode) follows it when generating the master plan's `## Milestones` section AND every per-milestone detail file. Skeptic-agent validates decomposed plans against both the base plan-criteria.md dimensions (D1-D8) AND the Cross-Milestone Validation Dimensions (D9-D10) defined here.

---

## Trigger Criteria — When to Decompose

Decompose is valid ONLY when classification is **Big** AND at least one additional gate fires:

- (a) A would-be single plan would have **>15 steps**
- (b) The complexity score (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` — Assess Complexity Dimensions) is **9 or 10 on the 0-10 scale**
- (c) The user picked "Too large — split" at `/geniro:implement`'s Phase 3 approval gate

See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` for the hard-escalation signals and the 5-dimension complexity-score table. Do NOT duplicate those tables here — `skills/_shared/effort-scaling.md` is the canonical source (Canonical rules, no duplication).

If the task classifies Small or Medium on effort scaling, decompose does not apply — use `/geniro:implement` directly (its Phase 2 architect+skeptic handles Medium tasks).

---

## Master Plan File — Extended Structure

The master plan lives at `.geniro/planning/<task-dir>/plan-<slug>.md` (the canonical task-dir plan path that `/geniro:implement` detects). It follows the base structure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-criteria.md` PLUS a new `## Milestones` section placed **before `## Files Affected`**.

Example of the new section:

```markdown
## Milestones

| # | Name | Goal | Upstream Deps | Wave | Mode | Status | File |
|---|------|------|---------------|------|------|--------|------|
| 1 | Setup | Scaffolding and shared types | none | 1 | AFK | pending | milestone-1-setup.md |
| 2 | Foundational data layer | Migrations + repositories | 1 | 2 | HITL | pending | milestone-2-data.md |
| 3 | User-story: OAuth flow | End-to-end OAuth login | 2 | 3 | HITL | pending | milestone-3-oauth.md |
| 4 | User-story: Token refresh | Refresh endpoint + client hook | 2 | 3 | AFK | pending | milestone-4-refresh.md |
| 5 | Polish | Docs, telemetry, feature flag | 3,4 | 4 | AFK | pending | milestone-5-polish.md |

## Implementation Notes
_Appended by `/geniro:implement` after each milestone ships. Empty initially._
```

**Rules:**
- `#` starts at 1 (not 0-padded).
- `Upstream Deps` lists milestone numbers (comma-separated) or `none`.
- `Wave` is an integer; milestones with the same wave number may run in parallel if their Upstream Deps permit. Milestones in the same wave MUST NOT share primary files.
- `Mode` values: `HITL` (human-in-the-loop — milestone needs human review at completion; `/geniro:implement` runs Lane:full + interactive mode) or `AFK` (autonomous — agent can ship without human review; `/geniro:implement` runs Lane:light + auto mode). Default to HITL when uncertain — AFK is opt-in for milestones with low blast radius and no product decisions. See "HITL/AFK Mode classification" below for the decision rubric.
- `Status` values: `pending | in-progress | completed | blocked`.
- `File` is a relative filename only (no path prefix) — it is always a sibling of the master plan.

### HITL/AFK Mode classification (decision rubric)

Each milestone is tagged with one Mode at decompose time. The user can override during the Phase 5 Approval gate.

**Tag as `AFK` (autonomous) when ALL of these hold:**
- Files Affected stays within a single subsystem (no cross-stack contracts changing)
- Acceptance Criteria are mechanical (lint passes, test count increases, migration applies cleanly) — not "user can do X" with subjective UX judgment
- No new external API contract, no new auth/permissions surface, no new payment/financial code
- Reversible — if the milestone ships wrong, a follow-up commit can fix it without data migration or coordinated deploy
- No `[PRODUCT-DECISION]` findings expected (i.e., no UX trade-off or business-rule choice)

**Tag as `HITL` (human-in-the-loop) when ANY of these hold:**
- Cross-stack contract change (backend + frontend + types must move together)
- User-visible behavior change (the kind users notice on the next page load)
- Auth, payments, crypto, PII handling, or any other security-sensitive surface
- New external API surface (callers outside this codebase will integrate against it)
- Migration with non-trivial backfill or rollback complexity
- Architecture decision still open (likely to surface `[PRODUCT-DECISION]` findings)

**Default to HITL when uncertain.** AFK is opt-in for milestones the architect can confidently mark as low-risk; HITL is the safe default. The "Setup" and "Polish" milestones in the suggested taxonomy are typically AFK; "Foundational" and "Feature" milestones are typically HITL unless their scope is unusually narrow.

**How `/geniro:implement` reads Mode:** when a milestone is detected (Phase 2 pre-check rule 1), the orchestrator reads the milestone file's Mode field (or master plan's `## Milestones` row). If `Mode: AFK`, Phase 1 Step 0 sets `Lane: light` and Phase 1 Step 1 sets `Mode: auto` automatically — no Mode-Selection prompt fires. If `Mode: HITL`, full Lane and interactive Mode are forced regardless of any auto-mode signals in `$ARGUMENTS`. The user can still override at the Phase 3 approval gate; HITL milestones cannot be silently downgraded to AFK by `$ARGUMENTS` mode signals.

---

## Milestone File Schema

Each `milestone-<N>-<slug>.md` is self-contained. A fresh `/geniro:implement milestone <N>` invocation with no conversation memory MUST be able to execute it.

```markdown
# Milestone <N>: <name>

> Status: pending | in-progress | completed | blocked | Mode: HITL | AFK | Master: plan-<slug>.md | Upstream: [milestone-2, milestone-3]

## Goal
One sentence: what ships at the end of this milestone.

## Why this is independently shippable
One sentence: why tests pass / the product works meaningfully after this milestone alone (feature flag, pilot surface, dark-launch, etc.).

## Standalone-Verifiability (D11)
Declare ONE concrete way the user (or CI) verifies this milestone shipped correctly WITHOUT needing any later milestone. Pick exactly one:

- **Demoable URL**: `<URL or route>` — what the user clicks to see the change
- **CLI command**: `<exact command + expected output>` — runnable smoke test
- **UI screen**: `<page or component name + visible affordance>` — manual check
- **Measurable behavior change**: `<metric / log line / DB row count + expected value>` — observable signal in the running system

If you cannot fill in one of the four, the milestone is NOT standalone-verifiable — re-partition before shipping the decomposition.

## Tracer-Bullet Layer Checklist
Per the layer checklist in "Milestone Sizing Rules" below. Mark each layer touched (✓), skipped-with-reason (`N/A — <reason>`), or omitted (a milestone that fails this is NOT a tracer bullet — re-partition).

- [ ] **Schema / migration**: ✓ | N/A — <reason>
- [ ] **API / interface**: ✓ | N/A — <reason>
- [ ] **Business logic / handler**: ✓ | N/A — <reason>
- [ ] **UI / surface**: ✓ | N/A — <reason>
- [ ] **Tests**: ✓ (always required for new behavior; N/A only when no new behavior is introduced — rare)
- [ ] **Docs**: ✓ | N/A — <reason>

## Upstream Dependencies
- Milestone <N-1>: [what it produced that this milestone relies on — types, tables, endpoints, contracts]
- (repeat per upstream)

## Files Affected
| File | Action | Step | Purpose |
|------|--------|------|---------|

## Steps
(Same Step schema as plan-criteria.md: Action verb, Files, Details, Depends on, Verify, Rollback. Each step touches 1-5 files.)

### Step 1: <action verb + target>
- **Files:** `path/to/file.ts`
- **Details:** [what exactly to change — precise enough that a fresh subagent can execute without re-reading the master plan]
- **Depends on:** [prior step numbers or "none"]
- **Verify:** [exact command + expected assertion]
- **Rollback:** [commands / reverts to undo this step]

## Acceptance Criteria
- Concrete, testable assertions that must hold at milestone boundary. Each must be checkable by a command or a visual check.
- (3-8 bullets)

## Verify Commands
- `npm test -- <scope>` (or equivalent)
- `npm run build`
- Any milestone-specific smoke test

## Rollback
- Commands / git operations to undo this milestone if downstream reveals problems.

## Prior Milestones Context (pre-inline slot)
_Pre-inlined at execution time by `/geniro:implement` from prior milestones' `## Implementation Notes (Milestone K)` appendices on the master plan. Empty when generated by `/geniro:decompose`._
```

---

## Milestone Sizing Rules (hard caps)

- **3 ≤ milestone count ≤ 7.** Fewer than 3 means the task isn't actually Big — decline and use `/geniro:implement` directly. More than 7 means over-decomposed — merge adjacent slices.
- **Each milestone: 1-8 steps.** 9+ → split the milestone. 0 → merge with a neighbor.
- **Each milestone: 1-12 files across all steps.** 13+ → split.
- **Independently shippable.** Tests pass at the milestone boundary; the repo is deployable mid-sequence (feature may be behind a flag or gated route).
- **No shared primary files with an adjacent milestone in the same wave** — tracer-bullet vertical-slice rule. If milestones M and M+1 both modify `src/auth/session.ts` as a primary file in the same wave, re-partition.
- **Tracer-bullet vertical slices only.** No "backend milestone", "frontend milestone", or "tests milestone". Each milestone is a *tracer bullet* — a narrow but COMPLETE path through every layer it needs to touch. Use the layer checklist below.
- **Prefer thinner over thicker (within the 3-7 cap).** When in doubt between N and N+1 milestones (both serializable, both independently shippable), pick N+1. Thinner slices land sooner, get reviewed faster, and reveal misunderstandings earlier.

### Tracer-bullet layer checklist

For each milestone, confirm it touches every layer that the slice's behavior change depends on. The slice MUST be end-to-end through these layers (when applicable to the slice):

- [ ] **Schema / migration** — if the slice persists data or changes a stored shape, the migration ships in this milestone (not deferred to a later one)
- [ ] **API / interface** — if the slice exposes a new endpoint, function signature, or contract, it ships in this milestone
- [ ] **Business logic / handler** — the actual behavior change is implemented here, not stubbed for a later milestone
- [ ] **UI / surface** — if the slice is user-visible, the visible affordance ships in this milestone (behind a feature flag is fine; not-shipped is not)
- [ ] **Tests** — every new behavior gets at least one test in this milestone (Stage D adversarial pass at /implement Phase 6 will add F→P tests for missed edges)
- [ ] **Docs** — if the slice introduces a new concept users or callers must learn, the doc patch ships in this milestone (not deferred)

A milestone that touches only schema (no API), or only API (no UI when the slice is user-facing), or only logic (no tests) is NOT a tracer bullet — it's a horizontal slice. Re-partition.

If a layer genuinely doesn't apply to the slice (e.g., a backend-only data-model change with no UI), explicitly mark "N/A — <reason>" in the milestone's `## Tracer-Bullet Layer Checklist` section (NOT in Standalone-Verifiability — those are separate concerns: D11 declares the verification path, the layer checklist declares the layer coverage). Reviewers (D11 + tracer-bullet check in skeptic) read both sections to confirm the slice was considered and rejected per layer, not forgotten.

### Suggested starting taxonomy (adapt, don't force)

`Setup → Foundational → Feature milestones → Polish`

- **Setup** (optional): scaffolding, shared types, CI config, feature flag created (off). Skip if the repo is already set up for this feature.
- **Foundational** (optional): migrations, repositories, core contracts that every downstream milestone needs. Skip if the data layer already exists.
- **Feature milestones** (required — this is the body): 1-5 user-story slices, each a vertical cut.
- **Polish** (optional): docs, telemetry, flag flip, deprecation cleanup. Skip if every Feature milestone handles its own docs/telemetry inline.

Setup and Polish are optional and should be omitted when not needed. The point is 3-7 meaningful slices, not 3-7 slots filled.

---

## Cross-Milestone Validation Dimensions

These extend skeptic-agent's 8 base dimensions (D1-D8 from `skills/_shared/plan-criteria.md`) when validating decomposed plans.

### D9. Milestone coverage
Every requirement from the master plan's **Goal** and any spec referenced in **User Decisions** must be covered by at least one milestone's **Acceptance Criteria**. Silent drops between milestones are BLOCKER-severity.

How to check:
- Extract requirements from the master Goal (each clause is usually one requirement).
- For each requirement, grep across all milestone files' Acceptance Criteria sections.
- If no match: BLOCKER, name the missing requirement and propose which milestone should own it.

### D10. Milestone dependency ordering
`Upstream Deps` across all milestones must form a DAG with no forward references. If milestone 3's Steps reference "the API created in milestone 5", that's a BLOCKER.

How to check:
- Build the dependency graph from each milestone's `Upstream:` header + explicit Upstream Dependencies section.
- Walk the graph — any cycle, any edge pointing forward in the numbered order, any milestone whose Steps reference artifacts that don't exist until a later milestone is a BLOCKER.
- Wave numbering must be consistent with the DAG: a milestone's wave must be strictly greater than the max wave of its upstream deps.

### D11. Standalone-verifiability
Every milestone must have a populated `## Standalone-Verifiability (D11)` section declaring exactly ONE of: demoable URL, CLI command, UI screen, or measurable behavior change. The declared verification must NOT depend on any later milestone (a milestone whose only verification path is "ship milestone N+1 too" is not standalone-shippable — that's a D10 forward-reference dressed up).

How to check:
- For each milestone file, grep for the `## Standalone-Verifiability (D11)` heading.
- If missing → BLOCKER: the milestone declared no verification path.
- If present, parse the declared verification (URL / command / UI / behavior change). Trace its dependencies — does executing it require artifacts from a later milestone? If yes → BLOCKER (D10 + D11 combined: the slice isn't a tracer bullet).
- A milestone that legitimately has no user-visible change (e.g., a Setup milestone) MUST declare a CLI command or measurable behavior change (e.g., "CI green with feature flag created and OFF" / "DB migration applied; new table exists with row count = 0"). "It compiles" is not enough.

---

## Anti-Patterns

Do NOT produce any of these when partitioning:

- **Horizontal slicing** — one milestone per layer (all backend, then all frontend, then all tests). Breaks independent-shippability and the tracer-bullet rule; the "backend milestone" has no user-visible acceptance criterion. Use the layer checklist above — every applicable layer ships in the slice.
- **"Misc polish" milestones** that bundle unrelated cleanups with no coherent goal. Polish either belongs inside its owning feature milestone or is the explicit last milestone with concrete acceptance criteria (docs published, telemetry live, flag flipped).
- **Milestones that can't be tested at their own boundary** — if the only way to verify milestone N is to also ship milestone N+1, merge them.
- **Internal-refactor-only milestones** with no user-visible change AND no infrastructural role. Allowed exception: a Setup milestone whose acceptance criterion is "CI green with empty feature flag" or similar concrete signal.
- **Adjacent same-wave milestones sharing primary files** — causes merge conflicts and breaks the independently-shippable-in-parallel contract for that wave.
- **Milestones with >12 files or >8 steps** — split. Milestones with 0 steps or 0 files — merge.
- **Forward references** — Step wording like "uses the service from milestone 5" appearing in milestone 3.

---

## Quality Checklist

Run this checklist before presenting the decomposition to the user (Phase 5). Every item must be green.

- [ ] Milestone count is 3-7
- [ ] Every milestone has Goal, "Why this is independently shippable", "Standalone-Verifiability (D11)", Upstream Dependencies, Files Affected, Steps (with Verify + Rollback per step), Acceptance Criteria, Verify Commands, Rollback, and an empty `## Prior Milestones Context` slot
- [ ] Every milestone is independently shippable (stated explicitly in "Why this is independently shippable" with a concrete mechanism — feature flag, pilot surface, gated route, dark-launch)
- [ ] Every milestone declares ONE concrete verification path in `## Standalone-Verifiability (D11)` (URL / CLI command / UI screen / measurable behavior change) that does NOT depend on a later milestone
- [ ] Upstream Deps form a DAG with no forward refs; wave numbers are consistent with the DAG
- [ ] No adjacent same-wave milestones share a primary file
- [ ] Master plan `## Milestones` section table is present, has 3-7 rows including a `Mode` column (HITL or AFK per row), and matches the milestone files on disk (filename, number, name, goal, mode)
- [ ] Every milestone has a Mode tag (HITL or AFK) in the table AND in its file's status header; default to HITL when the AFK criteria don't all apply
- [ ] Every requirement in the master Goal maps to at least one milestone's Acceptance Criteria (D9 check)
- [ ] Tracer-bullet layer checklist green for every milestone (schema/API/handler/UI/tests/docs — each applicable layer touched, N/A documented for those that genuinely don't apply)
- [ ] Each milestone: 1-8 steps, 1-12 files
- [ ] No horizontal slices (no "backend milestone" / "frontend milestone" / "tests milestone")
- [ ] No "misc polish" bundles — polish either lives inside its owning milestone or is the explicit last milestone with concrete acceptance criteria
- [ ] `state.md` (on approval) contains a `Milestones:` roll-up line with one entry per milestone; single file per task-dir
