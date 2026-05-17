# M4 — /geniro:implement Redesign (Skip-Architecture-With-Spec)

**Status:** Specification (pre-implementation, partial — see §10 Open Questions)
**Master plan:** `/root/.claude/plans/reactive-dreaming-backus.md` — this doc is M4 of an M1–M10 architecture redesign that collapses 18 skills → 11 and replaces the legacy 8-phase `/implement` with а spec-driven autonomous-harness loop. See §12 for skill-list reconciliation.
**Scope:** Redesign of `/geniro:implement` skill to consume an externally-provided spec/plan (from `/geniro:plan` — M5 deliverable) and skip its own architecture/approval phases. Collapses the 7-phase pipeline to a 2-phase flow (Implement → Self-review), removes Lane/TDD/Light/Auto modes, removes parallel work-unit decomposition, removes milestone-mode special-casing, and absorbs the (dropped) `/geniro:follow-up` skill's small-scope work via spec-driven entry.
**Depends on:** M1 (state-files framework — task slug resolution, `validate_state_file`, T1/T2/T3 layout); M2 (memory layers — `load-custom-instructions`, `load-semantic` refresh contracts, L2 auto-emit triggers); M3 (compaction-survival — per-skill refresh sites, `SessionStart` recovery flow, `non-resumable-actions` schema).
**Sequencing note:** master plan orders M4 (this doc) **before** M5 (`/plan`). M4 must therefore ship with а fallback entry-gate path that works when `/plan` does not yet exist (see §5, OQ-2).
**Followed by:** M5 (`/plan` — emits the spec/plan artifact M4 consumes; also absorbs `/decompose`'s milestone authoring); M6 (`/review`); M7 (`/debug` — same exhaust-escalation contract as §7.4); M8+ per master plan §107.

---

## 1. Purpose

The pre-M4 `/geniro:implement` (496-line `SKILL.md` + 855-line `implement-reference.md`) carried three responsibilities that overlapped with sibling skills:

1. **Discovery / architecture / approval** — duplicated the (then-existing) `/geniro:brainstorm` skill и а not-yet-existent `/geniro:plan` skill.
2. **Mode multiplexing** — Lane (TDD / Light / Auto) and milestone-mode special-cases produced four × four = ~16 code-paths, each with subtle gating differences.
3. **Parallel work-unit fan-out** — backend/frontend agent decomposition for "Big" tasks added scheduler complexity and a re-merge contract that few invocations actually exercised.

M4 removes all three. `/geniro:implement` becomes a focused "edit the code, then self-review what you wrote" loop. Anything strategic (problem framing, architecture, milestone slicing) belongs upstream в `/geniro:plan` (M5 deliverable — consolidates the prior /brainstorm + /decompose responsibilities per master plan §20). Small post-ship tweaks formerly handled by `/geniro:follow-up` are absorbed into `/implement` itself — master plan §27 says /implement "handles any size via spec input"; no separate skill needed.

The branch name **`claude/skip-architecture-with-spec-yjx8x`** captures the core idea: when a spec is provided, `/implement` skips its own architecture phase.

---

## 2. Architecture overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  /geniro:implement $ARGUMENTS                                                │
└─────────────────────────────┬────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  Entry gate (TBD — see §5)              │
        │  • Resolve spec/plan artifact OR fail   │
        │  • Refresh L4 custom-instruction layer  │
        │  • Resolve task slug (M1)               │
        │  • Detect frontend files in scope       │
        └─────────────────────────────┬───────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  Phase 1 — Implement (TBD — see §6)     │
        │  • Read spec/plan                       │
        │  • Edit / Write code changes            │
        │  • Run project test suite               │
        │  • State.md updates per M1 schema       │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 2 — Self-review (DECIDED — §7)   │
        │  • Spawn 5 reviewer-agents in parallel  │
        │    (bugs, security, architecture,       │
        │     tests, code-quality)                │
        │  • Bounded fix loop, max 3 rounds       │
        │  • Round N+1 only re-runs failing dims  │
        │  • After 3 rounds → escalate-AUQ        │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Ship (TBD — see §8)                    │
        │  • Commit / push / docs / cleanup       │
        │  • Adjustment-routing for ship feedback │
        └─────────────────────────────────────────┘
```

---

## 3. Scope deltas vs. pre-M4 `/geniro:implement`

### 3.1 Removed

| Component | Reason | Replacement |
|---|---|---|
| Phase 2: ARCHITECT | Strategic concern, not execution | `/geniro:plan` owns it |
| Phase 3: APPROVAL | Coupled to ARCHITECT | `/geniro:plan` owns approval handshake |
| Phase 5: SIMPLIFY (standalone agent) | Overlapped с review; cheap to fold into self-review | Inlined as one dimension of code-quality reviewer (§7) |
| Lane modes — TDD, Light, Auto | Path explosion; TDD discipline belongs к external guidance, not gating | Single solo execution path |
| Phase 4 Decomposition (backend/frontend WUs) | Scheduler complexity; rarely justified | Single solo inner loop |
| Phase 6 Stage A (Automated Checks as separate stage) | Conceptually part of self-review | Folded into reviewer-agent test-dimension input |
| Phase 6 Stage D (Adversarial Edge-Case Tests) | Heavy machinery for marginal value at this scope | Tests dimension в self-review covers happy + edge cases |
| Milestone-mode (`/implement milestone N`) | Special-case logic for an upstream concern | `/geniro:plan` (M5) emits per-milestone spec files as one of its output modes; M4 treats each milestone file as ordinary spec input. The legacy `/geniro:decompose` skill is being deleted entirely (master plan §65). |
| Interface-Design Pre-Approval Gate (Lane:tdd) | Tied к removed TDD lane | None |
| Anti-rationalization (TDD Mode) | Tied к removed TDD lane | None |
| Auto Mode Behavior | Tied к removed Auto lane | None |

### 3.2 Kept (with adaptation)

| Component | Notes |
|---|---|
| Phase 1: Auto-Detection Table | `$ARGUMENTS` parsing rules — needed for entry-gate (§5) |
| Phase 6: Fix Loop (max 3 rounds) | Pattern adopted directly as Phase 2 self-fix loop (§7.3) |
| Phase 6: Stage C Reviewer Template | Template format reused for 5-spawn self-review (§7.2) |
| Phase 7: Finalize Steps Detail | Commit, integration updates, cleanup — preserved largely as-is |
| Phase 7 Step 6: Adjustment Routing (Big / Medium / Small) | Used during ship-feedback handling |
| Pre-Ship Visual Verification (Playwright MCP) | Conditional on frontend files + MCP availability — unchanged |
| Code-style instruction loading | `load-custom-instructions` (MODE: refresh) at Phase 1 entry — unchanged |
| Debug-handoff to `/geniro:debug` | Available when self-fix loop exhausts (escalation path — §7.4) |

### 3.3 Dropped from `implement-reference.md` (line ranges in pre-M4 file)

- L62–109: Phase 1 Step 0 — Complexity Gate
- L110–145: Light Mode Semantics
- L146–173: TDD Mode Semantics
- L174–189: Phase 4 in TDD Mode
- L190–208: Interface-Design Pre-Approval Gate (Lane:tdd only)
- L209–220: Anti-rationalization (TDD Mode)
- L221–246: Auto Mode Behavior
- L247–269: Phase 4 Decomposition Example
- L270–348: Phase 4 Agent Delegation Template
- L363–410: Phase 5 Simplify Agent Template
- L611–668: Phase 6 Stage D Adversarial Edge-Case Tests
- L765–778: Phase 7 Step 8 Milestone Status Update
- L813–835: Phase 2 Milestone Reference Detection

---

## 4. Decisions recorded so far

| ID | Decision | Section |
|---|---|---|
| **Q4** | Self-fix bounded loop — max 3 rounds, then escalate-AUQ к user (no infinite retry) | §7.3, §7.4 |
| **Q6** | Phase 2 self-review spawns **5 reviewer-agents** in parallel: `bugs`, `security`, `architecture`, `tests`, `code-quality` | §7.2 |
| **Q7a** | Cleanup strategy — **Hybrid**: `SKILL.md` full rewrite (structurally different); `implement-reference.md` surgical edit (preserves proven templates/snippets) | §9 |
| **Q7b** | **Drop milestone-mode** entirely from M4 — `/geniro:plan` (M5) owns milestone semantics end-to-end as one of its output modes; the legacy `/geniro:decompose` is deleted (master plan §65) | §3.1, §3.3 |

---

## 5. Entry gate behavior — **OPEN**

**Pinned-down requirements:**

- The skill must refresh L4 custom instructions before any code work (`load-custom-instructions` MODE: refresh, scope: `implement` + `global` + `code-style`) — matches M3 contract.
- The skill must resolve a task slug per M1 (used for state.md path).
- The skill must detect whether frontend files are in scope (gates Pre-Ship Visual Verification + design conventions injection).

**Unresolved sub-questions:**

1. **No-spec fallback:** if `$ARGUMENTS` does not point to a spec/plan artifact, does M4: (a) auto-invoke `/geniro:plan`, (b) error out with directive to run `/plan` first, or (c) proceed treating `$ARGUMENTS` as a raw inline task description? **Sequencing constraint:** master plan orders M4 before M5, so option (a) is unavailable on the M4 ship-date — must pick (b) or (c) as the interim default and let option (a) become opt-in once /plan exists.
2. **DESIGN_DOC discovery rules:** what file conventions count as "spec/plan provided"? (current pre-M4 logic: look for `${task-dir}/spec.md`, `${task-dir}/plan.md`, or DESIGN_DOC frontmatter — does M4 inherit unchanged?)
3. **`$ARGUMENTS` flag surface:** which flags survive Lane removal? Candidates: `--draft` (commit but skip push/PR), `--no-ship` (stop after Phase 2), `--continue` (resume from state.md). None confirmed.

These were not resolved in the design session and are recorded as open.

---

## 6. Phase 1 — Implement — **OPEN**

**Pinned-down requirements:**

- Single solo inner loop (no parallel WU agents — see §3.1).
- Code-style instructions pre-loaded в context before first Edit/Write.
- Project test suite runs at least once before Phase 2 entry (provides input to `tests` reviewer dimension).
- State.md transitions per M1 schema; phase marker `phase: implement` during this phase.
- **L2 auto-emit (replaces /learnings)** — master plan §69: `/learnings` skill deleted; learning capture becomes an auto-step at end of /implement и /debug. M4 calls `emit-learning` (M2 §9 helper) when self-review surfaces а recurring pattern (≥3 reviewer matches across dimensions, type=convention), а novel diagnosis (type=diagnosis from debug-handoff), or а meaningful architectural decision (type=decision). M2 §5.3 trigger rules need reconciliation — the legacy "architect-agent picks alternatives → decision" trigger is obsolete (no architect-agent in M4); replacement trigger source is /plan output recorded in spec.md.

**Unresolved sub-questions:**

1. **Inner-loop granularity:** file-by-file edits with per-file test runs? Or whole-feature edit batch followed by one test run? Or decomposed into local sub-tasks tracked в state.md?
2. **Test-failure handling within Phase 1:** if tests fail during Phase 1, does M4 self-correct in-phase (mini fix loop) or proceed к Phase 2 and surface tests-failing as a reviewer finding?
3. **Hand-off to `/geniro:debug`** during Phase 1 when self-correction stalls — same exhaust-then-escalate semantics as §7.4, or different?

Recorded as open.

---

## 7. Phase 2 — Self-review — **DECIDED**

### 7.1 Trigger

Phase 1 reports completion → state.md transitions к `phase: self-review`. No user prompt between phases (continuous flow).

### 7.2 Reviewer-agent spawns (Q6)

**Five reviewer-agents in parallel**, one spawn per dimension. Use `reviewer-agent` (plugin-defined; falls back per the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`).

| Dimension | Scope |
|---|---|
| `bugs` | Logic errors, off-by-one, null/undefined paths, race conditions, broken invariants |
| `security` | Injection, auth/authz, secret handling, untrusted-input flows, OWASP-top-10 surface |
| `architecture` | Layering, coupling, abstractions, dead code, duplication, naming, file/module placement |
| `tests` | Coverage of changed lines, edge cases, F→P invariant, brittle assertions, missing negative cases |
| `code-quality` | Idiomatic style, readability, comments noise, premature abstractions, simplification opportunities (subsumes pre-M4 Phase 5 SIMPLIFY) |

**Spawn template:** reuse pre-M4 Phase 6 Stage C Reviewer Template (`implement-reference.md` L480–560), trimmed to the dimension-specific scope. Each reviewer receives: spec/plan, diff of Phase 1 changes, code-style instructions, project conventions.

**Spawn invocation:** single message with five `Agent` tool uses (parallel) — matches the parallel-spawn rule in the system prompt.

### 7.3 Bounded fix loop (Q4)

```
round = 1
while round ≤ 3:
    spawn reviewer-agents on failing dimensions only
        (round 1: all 5; round N+1: only those that failed round N)
    collect findings
    if no findings across all dimensions:
        break  # exit к ship
    apply fixes inline (single Edit-driven sub-loop, no further agent spawns)
    re-run project test suite
    round += 1
else:
    # round 4 would start — DO NOT enter it
    escalate via AskUserQuestion (§7.4)
```

**Round N+1 only re-runs failing dimensions** — dimensions that passed round N are not re-spawned. This bounds cost и avoids re-litigating already-clean code.

### 7.4 Escalation path (Q4 — exhaust case)

When the loop hits round 3 with unresolved findings:

1. Do **not** silently push or claim completion.
2. Surface to user via `AskUserQuestion` с:
   - Summary of unresolved findings per dimension (top 3 each).
   - Options: (A) hand off к `/geniro:debug` with current state.md snapshot, (B) accept findings and proceed к ship anyway (records the decision in state.md), (C) abort и leave работу uncommitted for manual takeover.
3. State.md marks `phase: escalated` with timestamp + round count.

This explicitly avoids the "kick it until it passes" anti-pattern: M4 has a terminal state, и unresolvable findings are the user's call, not the agent's.

---

## 8. Ship — **OPEN (mostly preserved)**

**Pinned-down:**

- Inherits pre-M4 Phase 7 Finalize Steps Detail (`implement-reference.md` L684–763 minus L765–778 Milestone Status — see §3.3).
- Pre-Ship Visual Verification fires only when frontend files в scope AND Playwright MCP is available (per CLAUDE.md "Optional MCP Dependencies").
- Adjustment-routing (Big / Medium / Small per L778–812) used when ship feedback arrives via PR comments (since /follow-up is dropped, all adjustment requests route back through /implement itself with the original spec + adjustment description as new $ARGUMENTS).
- **T2-handoff persist (M3 §11 obligation):** when M4 consumes а T2 handoff (e.g., `from-debug-<branch>.md` after а /debug investigation), persist key findings into state.md body under а `## Inputs from <producer>` section before Phase 1 first Edit/Write. Format: producer name, timestamp, top-3 findings as bullets, link к original T2 path. Survives compaction via M3 SessionStart recovery.
- **`non-resumable-actions` atomic append (M3 §8, M1 helpers):** after each side-effect that cannot be re-played safely (`git push`, PR/issue comment post, Slack/webhook dispatch), append а structured entry к state.md frontmatter `non-resumable-actions[]` array via M1 `atomic_state_append` helper. Entry schema per M3 §8: `{action, completed-at, <action-specific-fields>}`. The append must occur **after** the side-effect succeeds (so failed pushes don't pollute the array), and must be atomic (so partial-write corruption is impossible mid-crash).

**Unresolved:**

1. **Phase-or-not:** is Ship a third numbered phase, or a sub-step of Phase 2 exit? Affects state.md schema (3 phases vs 2 phases + finalization).
2. **PR creation default:** push only, or push + open PR, or governed by `$ARGUMENTS` flag?
3. **Docs update scope:** README / CHANGELOG / inline only — what's mandatory vs optional?

Recorded as open.

---

## 9. Cleanup checklist (Q7a — Hybrid)

### 9.1 `skills/implement/SKILL.md` — full rewrite

The pre-M4 SKILL.md (496 lines, 7 phases) is structurally incompatible с the 2-phase M4 flow. Rewrite from scratch против this spec. Do not attempt section-by-section edit — the surface area difference is too large и leaves orphaned references.

### 9.2 `skills/implement/implement-reference.md` — surgical edit

**Sections to delete** (line ranges from pre-M4 file — listed in §3.3 above):

- L62–109, L110–145, L146–173, L174–189, L190–208, L209–220, L221–246, L247–269, L270–348, L363–410, L611–668, L765–778, L813–835

**Sections to rewrite in place:**

- L411–441 — Phase 6 Stage A Automated Checks Detail → fold into Phase 2 reviewer input (the `tests` dimension references the failing test output directly).
- L442–479 — Phase 6 Stage B Spec Compliance Agent Template → adapt as the contract входа для each of the 5 reviewers (each receives spec/plan, not just diff).
- L480–560 — Phase 6 Stage C Code Quality Reviewers Template → this is the **canonical template** for the 5 self-review spawns. Trim to dimension-specific scope, parameterize the dimension name.
- L561–610 — Phase 6 Fix Loop → adapt language to match §7.3 (drop "round 1: all 5" caveat — that's already inherent).

**Sections to keep as-is:**

- L7–61 — Phase 1 Auto-Detection Table (used by entry-gate §5; specific flag rows may still be deleted once §5 is decided).
- L684–763 — Phase 7 Finalize Steps Detail (minus L765–778 Milestone Status).
- L778–812 — Phase 7 Step 6 Adjustment Routing.

### 9.3 Other artifacts

- `agents/reviewer-agent.md` — review против §7.2 dimension list; if it already supports a `dimension` parameter, no change needed. If it doesn't, add one (deferred until M4 implementation).
- `agents/backend-agent.md`, `agents/frontend-agent.md` — primary consumer (`/implement` parallel WU spawns + `/follow-up` Phase 5) deleted under M4 + master plan §66. Verify no other consumers exist; if not, delete both agent files.
- `agents/simplify-agent.md` — /deep-simplify being deleted (master plan §67). Verify if `/review --simplify` flag (master plan replacement) plans to reuse this agent; otherwise delete.
- `agents/adversarial-tester-agent.md` — primary consumer pre-M4 was /implement Phase 6 Stage D (removed §3.1) + /follow-up Phase 5 Step 1.5 (skill deleted). /debug Adversarial Mode may still spawn it — verify; keep only if /debug needs it.
- `CLAUDE.md` — **full skill-table rewrite required**. Current table lists 18 skills (pre-redesign). Post-M4 + M5–M10 it must list 11 (master plan §22 — /plan, /implement, /review, /debug, /refactor, /onboard, /investigate, /instructions, /actions, /setup, /update). Also remove /geniro:decompose, /geniro:follow-up, /geniro:brainstorm, /geniro:deep-simplify, /geniro:features, /geniro:learnings, /geniro:cleanup, /geniro:vendor rows. Add /geniro:plan row (placeholder until M5 lands).
- `skills/_shared/plan-criteria.md` — currently says "Pre-inlined into architect-agent prompts by `/geniro:implement` (Phase 2) and `/geniro:decompose`". Both consumers wrong: M4 removes architect-agent; /decompose deleted. Rewrite to "Pre-inlined into architect-agent prompts by `/geniro:plan` (M5)" — defers maintenance к M5.
- `skills/_shared/root-cause-gate.md:46` — references `/geniro:implement Phase 2: from the architect-agent's design unit fields`. Update reference к /plan-emitted spec.md root-cause fields (or remove the /implement-specific clause and let /plan own root-cause tagging).
- `skills/_shared/test-first-gate.md:20` — contains "`Lane: full or Lane: light` — those Lanes use the architect's plan + Phase 6 reviewer pipeline as the test-coverage gate". Both Lane terminology AND architect's plan reference are stale. Rewrite to reference M4 self-review (Phase 2, 5 reviewer dimensions §7.2). If the gate's premise (Lane-gated test coverage) no longer applies, consider deleting the file entirely.
- `skills/_shared/effort-scaling.md:49` — references "`/implement` Light Mode vs `/follow-up` Fast Lane trade-off". Both Lane terminology and /follow-up reference stale. Rewrite or delete the row.
- `skills/decompose/`, `skills/follow-up/`, `skills/brainstorm/`, `skills/deep-simplify/`, `skills/features/`, `skills/learnings/`, `skills/cleanup/`, `skills/vendor/` — **entire directories к delete** per master plan §60. NOTE: deletions may land in later milestones (M5+ as each is replaced), not necessarily synchronously with M4. M4 commit must NOT depend on these being deleted yet — M4 SKILL.md и reference.md must work с the deletions either present or pending.

---

## 10. Open questions (carried forward)

These were not closed in the design session и must be resolved before M4 implementation lands:

| ID | Topic | Sections affected |
|---|---|---|
| OQ-1 | Phase structure — 2 phases (Implement + Self-review с Ship inside) vs 3 phases (Implement + Self-review + Ship) | §2, §8 |
| OQ-2 | Entry-gate behavior when spec/plan absent — pre-M5 interim: error-with-directive OR treat `$ARGUMENTS` as inline task (auto-invoke /plan is post-M5 only) | §5.1 |
| OQ-3 | DESIGN_DOC discovery file conventions для M4 entry-gate | §5.2 |
| OQ-4 | `$ARGUMENTS` flag surface after Lane removal (`--draft`, `--no-ship`, `--continue`, others) | §5.3 |
| OQ-5 | Phase 1 inner-loop granularity (file-by-file vs whole-feature) | §6.1 |
| OQ-6 | Phase 1 test-failure handling (in-phase fix vs surface к Phase 2) | §6.2 |
| OQ-7 | Phase 1 debug-handoff semantics (parallel к §7.4, or distinct) | §6.3 |
| OQ-8 | PR-creation default | §8.2 |
| OQ-9 | Docs-update mandatory scope | §8.3 |
| **OQ-10** | **Memory I/O section (M2 §13 obligation)** — formal enumeration of L2/L3/L4 helpers M4 calls и at which phase boundaries. Needed before SKILL.md rewrite. | New §13 (TBD) |
| **OQ-11** | **Agent-Computer Interface (ACI) spec (master plan §141)** — explicit tool surface для reviewer-agent spawns + inner-loop Edit/Write/Bash tools + restricted tool list per spawn. Master plan calls this а mandatory M4 design output. | New §14 (TBD) |
| **OQ-12** | **L2 auto-emit trigger reconciliation** — M2 §5.3 trigger rules for /implement reference architect-agent и pre-M4 reviewer-agent pattern-discovery, both obsolete. New triggers must be defined: under which Phase 2 reviewer findings does M4 emit `type=convention`? Does /plan output emit `type=decision` instead of /implement? | §6 pinned-down, M2 ↔ M4 reconciliation |

The design session closed Q4 / Q6 / Q7 (recorded in §4) и several others whose exact wording was lost к context compaction before this document was written. Treat §10 as the canonical open-questions list going forward; if any of these turn out to have been resolved in conversation history, reconcile by updating the relevant section и striking the row from this table.

---

## 11. Implementation note

When M4 implementation begins (likely via `/geniro:implement` itself, recursively, or by hand on this branch), the work-order is:

1. **Resolve OQ-1 through OQ-12 in §10** — these block code changes. OQ-10 (Memory I/O) и OQ-11 (ACI spec) are master-plan obligations, not optional.
2. **Reconcile M1 ↔ M3 hook-name drift** — M1 line 463 still says `post-compact-notification.sh`; M3 renames к `session-start-restore.sh`. Patch M1 to match M3.
3. **Reconcile M2 ↔ M4 L2 auto-emit triggers** — see OQ-12; either revise M2 §5.3 trigger rules или document M4's replacement triggers.
4. **Apply §9.2 surgical edits к `implement-reference.md` first** (lower-risk, preserves working snippets).
5. **Rewrite `skills/implement/SKILL.md`** against finalized spec.
6. **Update `CLAUDE.md` full skill-table** per §9.3 (8 skill deletions + add /plan placeholder, не just /implement row).
7. **Update `_shared/` helpers** per §9.3: `plan-criteria.md`, `root-cause-gate.md`, `test-first-gate.md`, `effort-scaling.md`.
8. **Verify `reviewer-agent` supports the 5 dimensions**; patch if not.
9. **Manual end-to-end test** против a small feature task before merging. Use inline-spec ($ARGUMENTS-only) entry-mode since /plan не yet exists.

**Skill-deletion sequencing (master plan §60):**

The 8 dropped skills (`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`) do NOT need к be deleted synchronously with M4. Each gets its replacement landing under а later milestone (M5 for /plan absorbing /brainstorm+/decompose; M6+ for the rest). M4 must work whether these dirs are present or already deleted — М4 simply does not invoke them.

**Master plan research deliverables (§130–139) — partial deferral:**

Master plan §141 lists 8 research deliverables (OpenHands deep-dive, Forge analog, SWE-agent ACI, 4-phase SDD verification, Cline Plan/Act UX, multi-agent decision rule, self-validation contract, self-review contract) expected before M4 design. This doc was drafted без those deliverables — the design is sound for the self-review subsystem (§7) и cleanup scope (§9), but ACI spec (OQ-11) and the multi-agent decision rule are explicitly research-blocked. Treat M4 implementation as conditional on completing those two before SKILL.md rewrite (work-order step 5).

Until §10 closes, this document represents the partial spec — sufficient к pin down the self-review subsystem (§7) и cleanup scope (§9), insufficient к ship the full skill rewrite.

---

## 12. Master plan reconciliation

The authoritative redesign reference is `/root/.claude/plans/reactive-dreaming-backus.md`. This section reconciles M4 (this doc) с the master plan's locked-in decisions.

### 12.1 Skill-list status (master plan §20 + §60)

**11 skills survive** (master plan §22–§56):

| Skill | Source skill(s) | Milestone owner |
|---|---|---|
| `/plan` | NEW — replaces `/brainstorm` + `/decompose` | M5 |
| `/implement` | Redesigned (this doc); absorbs `/follow-up` | **M4 (this doc)** |
| `/review` | Unchanged | M6 |
| `/debug` | Aligned with /implement simplification | M7 |
| `/refactor` | Distinct zero-behavior-change guarantee | M8 |
| `/onboard` | Codebase mapping | M9 |
| `/investigate` | Codebase Q&A | M9 |
| `/instructions` | CRUD `.geniro/instructions/*` | M10 |
| `/actions` | CRUD `.geniro/actions/*` | M10 |
| `/setup` | One-time project bootstrap | M10 |
| `/update` | Plugin update | M10 |

**8 skills deleted** (master plan §60–§71):

| Deleted | Replacement |
|---|---|
| `/brainstorm` | Merged → `/plan` (M5) |
| `/decompose` | Merged → `/plan` (M5, milestones as output mode) |
| `/follow-up` | Absorbed → `/implement` (this doc) |
| `/deep-simplify` | Optional flag on `/review` (M6) |
| `/features` | Manual `FEATURES.md` or via `/plan` |
| `/learnings` | Auto-step в `/implement` (§6 L2 auto-emit) и `/debug` (M7) |
| `/cleanup` | Dropped — niche |
| `/vendor` | Dropped — no cloud-runner requirement |

### 12.2 M4-specific obligations from master plan

| Master plan ref | Obligation | M4 status |
|---|---|---|
| §27 | "/implement: 3 phases max — analyze → implement → self-review" | M4 ships 2 phases (Implement + Self-review). Analyze is folded into Phase 1 entry (entry-gate refresh + spec read). Within master plan's "≤3 phases" cap. ✅ |
| §102 | "≤3 AUQ gates, ≤5 helper-file reads, ≤5 subagent spawns" | Phase 2 spawns exactly 5 reviewer-agents (§7.2). AUQ count: 1 (Phase 2 escalation §7.4). Helper-read count TBD pending OQ-10 Memory I/O section. Within budget. ✅ |
| §130–§139 | 8 research deliverables before М4 design | Deferred — §11 work-order step 5 gates SKILL.md rewrite on completing OQ-11 (ACI) + multi-agent decision rule. ⚠️ |
| §141 | M4 output: SKILL.md draft + ACI spec + self-validation/self-review contract docs | Self-review contract: ✅ §7. ACI spec: ⚠️ OQ-11. Self-validation contract: ⚠️ OQ-6 (test-failure handling) + §6 test-suite-once. |

### 12.3 Stale assumptions corrected since v1 draft

| Original M4 assumption (v1) | Corrected (v2 — this rev) |
|---|---|
| /decompose owns milestone semantics, M4 consumes its output | /plan (M5) owns milestone semantics; /decompose deleted |
| /follow-up handles ad-hoc post-ship tweaks | /follow-up deleted; /implement absorbs |
| /brainstorm is upstream for strategic framing | /brainstorm deleted; /plan absorbs |
| Cleanup checklist scope = `skills/implement/*` + reviewer-agent + CLAUDE.md /implement row | Cleanup scope adds 8 skill-dir deletions, CLAUDE.md full-table rewrite, и 4 `_shared/` helper updates (§9.3) |
| /plan is а prerequisite that M4 depends on | /plan is M5 — ships AFTER M4. M4 needs interim no-/plan fallback (OQ-2) |
