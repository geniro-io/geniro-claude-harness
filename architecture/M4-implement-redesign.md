# M4 — /geniro:implement Redesign (Skip-Architecture-With-Spec)

**Status:** Specification (pre-implementation, partial — see §10 Open Questions)
**Scope:** Redesign of `/geniro:implement` skill to consume an externally-provided spec/plan (from `/geniro:plan` or `/geniro:brainstorm`) and skip its own architecture/approval phases. Collapses the 7-phase pipeline to a 2-phase flow (Implement → Self-review), removes Lane/TDD/Light/Auto modes, removes parallel work-unit decomposition, removes milestone-mode special-casing.
**Depends on:** M1 (state-files framework — task slug resolution, `validate_state_file`, T1/T2/T3 layout); M2 (memory layers — `load-custom-instructions`, `load-semantic` refresh contracts); M3 (compaction-survival — per-skill refresh sites, `SessionStart` recovery flow); upstream `/geniro:plan` skill (must exist and emit a spec/plan artifact that M4 can consume — out of scope for this doc).
**Followed by:** M5+ (per-skill alignment of `/geniro:debug`, `/geniro:follow-up`, `/geniro:review` to the M4 self-review reviewer-agent contract); future: re-introducing parallel work-unit decomposition behind an explicit opt-in flag if needed.

---

## 1. Purpose

The pre-M4 `/geniro:implement` (496-line `SKILL.md` + 855-line `implement-reference.md`) carried three responsibilities that overlapped with sibling skills:

1. **Discovery / architecture / approval** — duplicated `/geniro:brainstorm` and a (then-missing) `/geniro:plan` skill.
2. **Mode multiplexing** — Lane (TDD / Light / Auto) and milestone-mode special-cases produced four × four = ~16 code-paths, each with subtle gating differences.
3. **Parallel work-unit fan-out** — backend/frontend agent decomposition for "Big" tasks added scheduler complexity and a re-merge contract that few invocations actually exercised.

M4 removes all three. `/geniro:implement` becomes a focused "edit the code, then self-review what you wrote" loop. Anything strategic (problem framing, architecture, milestone slicing) belongs upstream in `/geniro:brainstorm`, `/geniro:plan`, or `/geniro:decompose`; anything ad-hoc (small post-ship tweaks) belongs in `/geniro:follow-up`.

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
| Milestone-mode (`/implement milestone N`) | Special-case logic for an upstream concern | `/geniro:decompose` emits per-milestone spec files; M4 treats them as ordinary input |
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
| **Q7b** | **Drop milestone-mode** entirely from M4 — `/geniro:decompose` owns milestone semantics end-to-end | §3.1, §3.3 |

---

## 5. Entry gate behavior — **OPEN**

**Pinned-down requirements:**

- The skill must refresh L4 custom instructions before any code work (`load-custom-instructions` MODE: refresh, scope: `implement` + `global` + `code-style`) — matches M3 contract.
- The skill must resolve a task slug per M1 (used for state.md path).
- The skill must detect whether frontend files are in scope (gates Pre-Ship Visual Verification + design conventions injection).

**Unresolved sub-questions:**

1. **No-spec fallback:** if `$ARGUMENTS` does not point to a spec/plan artifact, does M4: (a) auto-invoke `/geniro:plan`, (b) error out with directive to run `/plan` first, or (c) proceed treating `$ARGUMENTS` as a raw inline task description?
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
- Adjustment-routing (Big / Medium / Small per L778–812) used when ship feedback arrives via PR comments or follow-up requests.

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
- `CLAUDE.md` plugin-root listing — update `/geniro:implement` row to reflect new 2-phase scope (the table at the top of CLAUDE.md).

---

## 10. Open questions (carried forward)

These were not closed in the design session и must be resolved before M4 implementation lands:

| ID | Topic | Sections affected |
|---|---|---|
| OQ-1 | Phase structure — 2 phases (Implement + Self-review с Ship inside) vs 3 phases (Implement + Self-review + Ship) | §2, §8 |
| OQ-2 | Entry-gate behavior when spec/plan absent — auto-invoke `/plan`, error, or treat `$ARGUMENTS` as inline task | §5.1 |
| OQ-3 | DESIGN_DOC discovery file conventions для M4 entry-gate | §5.2 |
| OQ-4 | `$ARGUMENTS` flag surface after Lane removal (`--draft`, `--no-ship`, `--continue`, others) | §5.3 |
| OQ-5 | Phase 1 inner-loop granularity (file-by-file vs whole-feature) | §6.1 |
| OQ-6 | Phase 1 test-failure handling (in-phase fix vs surface к Phase 2) | §6.2 |
| OQ-7 | Phase 1 debug-handoff semantics (parallel к §7.4, or distinct) | §6.3 |
| OQ-8 | PR-creation default | §8.2 |
| OQ-9 | Docs-update mandatory scope | §8.3 |

The design session closed Q4 / Q6 / Q7 (recorded in §4) и several others whose exact wording was lost к context compaction before this document was written. Treat §10 as the canonical open-questions list going forward; if any of these turn out to have been resolved in conversation history, reconcile by updating the relevant section и striking the row from this table.

---

## 11. Implementation note

When M4 implementation begins (likely via `/geniro:implement` itself, recursively, or by hand on this branch), the work-order is:

1. Resolve OQ-1 through OQ-9 in §10 — these block code changes.
2. Apply §9.2 surgical edits к `implement-reference.md` first (lower-risk, preserves working snippets).
3. Rewrite `skills/implement/SKILL.md` against finalized spec.
4. Update `CLAUDE.md` plugin-root row.
5. Verify `reviewer-agent` supports the 5 dimensions; patch if not.
6. Manual end-to-end test против a small feature task before merging.

Until §10 closes, this document represents the partial spec — sufficient к pin down the self-review subsystem (§7) и cleanup scope (§9), insufficient к ship the full skill rewrite.
