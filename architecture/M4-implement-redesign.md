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
        │  Phase 1 — Analyze (DECIDED — §5)       │
        │  • Semantic parse of $ARGUMENTS         │
        │    (no CLI flags — see OQ-4 closure)    │
        │  • Resolve spec.md OR inline-task path  │
        │  • Refresh L4 (load-custom-instructions │
        │    MODE: refresh, scope=implement +     │
        │    global + code-style)                 │
        │  • Refresh L3 (load-semantic MODE:      │
        │    refresh)                             │
        │  • Resolve task slug (M1)               │
        │  • Detect frontend files в scope        │
        │  • Persist T2 handoffs к state.md       │
        │    (`## Inputs from <producer>`)        │
        └─────────────────────────────┬───────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  Phase 2 — Implement (DECIDED — §6)     │
        │  • Whole-feature edit batch             │
        │    (no file-by-file, no sub-tasks)      │
        │  • Single test run at end of phase      │
        │  • In-phase fix loop on test failure    │
        │    (max 3 retries, then §7.4-style      │
        │    escalation: debug / accept / abort)  │
        │  • State.md `phase: implement`          │
        └─────────────────────────────┬───────────┘
                                      │
                                      ▼
        ┌─────────────────────────────────────────┐
        │  Phase 3 — Self-review + Ship           │
        │                       (DECIDED — §7+§8) │
        │  • 5 reviewer-agents в parallel:        │
        │    bugs, security, architecture (incl   │
        │    docs-staleness), tests, code-quality │
        │  • Bounded fix loop, max 3 rounds       │
        │  • Round N+1 = only failing dims        │
        │  • After 3 rounds → AUQ (§7.4)          │
        │  • L2 emit (`convention` on ≥3-pattern) │
        │  • Ship sub-step: commit → AUQ          │
        │    (push / push+PR / push+draft-PR)     │
        │  • atomic_state_append(non-resumable)   │
        │    after each side-effect               │
        └─────────────────────────────────────────┘
```

---

### 2.1 State machine

Phase enum (state.md `phase:` field values) и transitions:

```
[entry]
  └── analyze ──┬── implement ──┬── self-review ──┬── ship ──┬── done
                │               │                  │           ├── ship-committed-only (terminal — "don't push" modifier)
                │               │                  │           └── (atomic non-resumable-actions write per side-effect)
                │               │                  │
                │               │                  └── self-review-only (terminal — "stop after review" modifier)
                │               │
                │               └── phase-2-escalated ──┬── debug-handoff (terminal — user picks "hand off к /debug")
                │                                       ├── self-review (user picks "accept failures" → flows back into happy path с accepted-failures note)
                │                                       └── aborted (terminal — user picks "abort")
                │
                └── (analyze does not have its own escalation — failures here surface к user at Phase 1 exit, model retries или escalates inline)

      self-review ──┬── (happy: flows к ship as shown above)
                    │
                    └── phase-3-escalated ──┬── debug-handoff (terminal)
                                            ├── ship (user picks "accept findings" → flows к ship с accepted-findings note)
                                            └── aborted (terminal)
```

**Terminal states:** `done`, `ship-committed-only`, `self-review-only`, `debug-handoff`, `aborted`. M3 SessionStart recovery treats any terminal state as «task complete — no resume needed».

**Non-terminal states:** `analyze`, `implement`, `self-review`, `ship`. M3 recovery rolls these back к their phase-entry point and re-runs from there (idempotent re-entry per §5.4, §6, §7.1).

**Escalation states:** `phase-2-escalated`, `phase-3-escalated`. M3 recovery surfaces к user as "task was paused awaiting your decision — last shown AUQ options:" so the user re-picks без losing context.

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
| **Q6** | Phase 3 self-review spawns **5 reviewer-agents** in parallel: `bugs`, `security`, `architecture` (incl. docs-staleness per OQ-9), `tests`, `code-quality` | §7.2 |
| **Q7a** | Cleanup strategy — **Hybrid**: `SKILL.md` full rewrite (structurally different); `implement-reference.md` surgical edit (preserves proven templates/snippets) | §9 |
| **Q7b** | **Drop milestone-mode** entirely from M4 — `/geniro:plan` (M5) owns milestone semantics end-to-end as one of its output modes; the legacy `/geniro:decompose` is deleted (master plan §65) | §3.1, §3.3 |
| **OQ-1** | **3 named phases** — Phase 1 Analyze → Phase 2 Implement → Phase 3 Self-review-and-Ship. Matches master plan §27 ("analyze → implement → self-review"). Ship is а terminal sub-step of Phase 3. | §2, §5, §6, §7 |
| **OQ-2** | **Inline-task fallback as default** when no spec.md found. Pre-M5: $ARGUMENTS treated as raw task description. Post-M5: a semantic "plan first" intent in $ARGUMENTS may route к /plan as an opt-in. | §5 |
| **OQ-3** | spec.md canonical filename (master plan §26) с plan.md as legacy alias и design-doc-detect.md helper for backward-compat frontmatter detection. | §5 |
| **OQ-4** | **No CLI flags.** Semantic parsing of $ARGUMENTS at Phase 1 entry. Canonical vocabulary: empty/"continue"/"resume" → resume; file path → spec; free-form → inline task; natural-language modifiers honored semantically. | §5 |
| **OQ-5** | **Whole-feature edit batch** in Phase 2 — single test run at end (not file-by-file, not sub-task decomposition). Matches master plan §102 friction reduction. | §6 |
| **OQ-6** | **In-phase mini fix loop** on Phase 2 test failure — bounded 3 retries, then escalation. Phase 3 only ever sees green tests. | §6 |
| **OQ-7** | Phase 2 fix-loop exhaustion mirrors **§7.4 escalation pattern** (Q4) — AUQ с debug-handoff / accept-failure / abort. | §6 |
| **OQ-8** | **Preserve pre-M4 AUQ flow** at ship time: push / push+PR / push+draft-PR (`gh pr create [--draft]`). | §7 (Ship sub-step) |
| **OQ-9** | **Fold docs-staleness scan into Phase 3 architecture reviewer** — no extra subagent spawn. Findings come back as Phase 3 review finding и fixed inline. | §7.2 architecture dim |
| **OQ-10** | Memory I/O obligation (M2 §13) — see §13. | §13 |
| **OQ-11** | ACI spec (master plan §134) — deferred к M4 implementation phase pending SWE-agent ACI research. | Deferred |
| **OQ-12** | L2 trigger threshold ("≥3 instances of same pattern") — implementation detail for reviewer-agent spawn prompt; deferred к M4 impl. | Deferred |

---

## 5. Phase 1 — Analyze — **DECIDED**

The entry-gate phase. Light по cost — а few file reads и а semantic $ARGUMENTS parse — но critical для correctness. State.md transitions к `phase: analyze` for M3 recovery granularity.

### 5.1 $ARGUMENTS parsing (OQ-4 closure)

**No CLI flag grammar.** $ARGUMENTS is parsed semantically. The Phase 1 entry instruction prompts the model к classify intent before дополнительных reads. Canonical detection:

| $ARGUMENTS shape | Mode |
|---|---|
| empty | Resume current task from state.md (if state.md exists) OR error с directive to provide а task. |
| contains "continue" / "resume" (any casing, standalone word) | Resume from state.md (M3-coupled — reads `non-resumable-actions[]` к skip already-completed side-effects). |
| matches а filesystem path (rel или abs) к а .md file | Load as spec/plan artifact. Validates frontmatter per design-doc-detect.md helper. |
| free-form description с no path match | Inline-task mode (OQ-2 fallback). Model treats $ARGUMENTS as а raw spec description; Phase 1 produces а minimal inline plan от что the task is, files likely touched, и approach к take. |
| ambiguous (e.g., а bare slug that could be а task name OR а task description) | AUQ с 2-3 disambiguation options. |
| natural-language modifiers ("don't push", "draft only", "stop after review", "...and update README") | Honored semantically by Phase 3 — no formal mode keyword; the modifier survives in $ARGUMENTS и is consulted at Ship time или relevant decision points. |

### 5.2 Spec discovery (OQ-3 closure)

Canonical filename: **`spec.md`** в the task-dir (master plan §26 — `/plan` emits "approved spec.md"). Backward-compat fallbacks:

1. `${task-dir}/spec.md` — preferred
2. `${task-dir}/plan.md` — legacy alias (pre-M4 convention)
3. design-doc-detect.md frontmatter detection — for legacy /brainstorm-emitted design docs that don't follow naming convention

Phase 1 walks these в order and stops at the first hit.

### 5.3 No-spec fallback (OQ-2 closure)

If no spec.md, plan.md, or DESIGN_DOC frontmatter is found AND $ARGUMENTS is non-empty free-form text → enter **inline-task mode**: treat $ARGUMENTS as а raw spec description.

Phase 1 produces а brief inline plan recorded в state.md body under `## Inline Plan` containing: one-sentence goal, file list (best-effort), approach summary. This becomes the source-of-truth для Phase 3 self-review (the `spec` field consumed by reviewer-agents).

**Pre-M5 reality:** /plan не yet exists; inline-task mode is the only viable path for users без а hand-authored spec.md. Post-M5: semantic detection of "plan this first" intent в $ARGUMENTS may route к /plan as an opt-in.

### 5.4 Pinned-down requirements (all phases prelude)

- Refresh L4 custom instructions (`load-custom-instructions` MODE: refresh, scope: `implement` + `global` + `code-style`) — matches M3 contract.
- Refresh L3 semantic layer (`load-semantic` MODE: refresh, top-2 default) — fingerprint drift check fires.
- Resolve task slug per M1 (used для state.md path).
- Detect frontend files в scope (gates Pre-Ship Visual Verification + design conventions injection in Phase 3 reviewer prompts).
- Persist any T2 handoff (e.g., `from-debug-<branch>.md`) into state.md body under `## Inputs from <producer>` — per M3 §11 obligation.

---

## 6. Phase 2 — Implement — **DECIDED**

State.md `phase: implement` during this phase. Code edits + test verification. Exits к Phase 3 only when tests are green.

### 6.1 Inner-loop granularity (OQ-5 closure)

**Whole-feature edit batch.** Read spec.md (or inline plan from Phase 1) → make all required Edit/Write changes к the codebase в а single phase pass → run the project test suite once.

Не file-by-file (high test cost on slow suites; granular state recovery rarely worth it). Не sub-task decomposition (overhead doesn't pay для typical M4 task sizes).

State.md tracks the file-edit list but не per-file phase transitions. Recovery от mid-batch crash: M3 SessionStart reloads state.md, model sees `phase: implement`, re-reads spec, re-checks current file diff vs. spec to decide whether к continue editing или skip к test-run.

### 6.2 Test-failure handling (OQ-6 closure)

**In-phase mini fix loop.** If the end-of-phase test run fails:

```
retry = 1
while retry ≤ 3:
    inspect failing test output
    edit code (or test) к address the failure (model's call)
    re-run test suite
    if all green → exit Phase 2 к Phase 3
    retry += 1
else:
    escalate (§6.3)
```

Phase 3 only sees green tests. The `tests` reviewer dimension в Phase 3 then evaluates coverage / edge cases / brittle assertions — но never "tests are failing".

### 6.3 Debug-handoff (OQ-7 closure)

When the §6.2 retry loop exhausts (3 failed retries), Phase 2 escalates **с the same AUQ pattern as §7.4**:

1. Surface к user via `AskUserQuestion` с:
   - Failing-test summary (top 3 failures, error messages, suspect lines).
   - Options: (A) hand off к `/geniro:debug` с state.md snapshot, (B) accept failing tests as documented limitation and proceed к Phase 3 anyway (records the decision в state.md `## Accepted Failures`), (C) abort и leave work uncommitted for manual takeover.
2. State.md marks `phase: phase-2-escalated` с timestamp + retry count + failing-test list. Exit transitions:
   - User picks (A) → `phase: debug-handoff` (terminal, M4 exits — caller resumes via `/geniro:debug` с the T2 handoff containing failing-test diagnostics).
   - User picks (B) → `phase: self-review` (proceeds к Phase 3 с `## Accepted Failures` block в state.md body).
   - User picks (C) → `phase: aborted` (terminal — work uncommitted on disk).

Option (B) ("accept") triggers а warning в Phase 3 architecture reviewer prompt — it'll see the accepted-failures list и may flag scope concerns.

### 6.4 Pinned-down requirements

- Single solo inner loop (no parallel WU agents — see §3.1).
- Code-style instructions pre-loaded в context от Phase 1's L4 refresh.
- Project test suite runs at the end of Phase 2 (provides input к `tests` reviewer dimension в Phase 3).
- State.md transitions per M1 schema; phase marker `phase: implement` during this phase, `phase: phase-2-escalated` если §6.3 triggers.
- **L2 auto-emit (replaces /learnings)** — master plan §69: `/learnings` skill deleted; learning capture becomes auto-step at end of /implement (this skill) и /debug. M4 calls `emit-learning` (M2 §9 helper) from Phase 3 (not Phase 2) когда reviewer findings warrant it; see §7 и §13 для emit sites.

---

## 7. Phase 3 — Self-review + Ship — **DECIDED**

### 7.1 Trigger

Phase 2 reports green tests → state.md transitions к `phase: self-review`. No user prompt between phases (continuous flow). On entry, model re-runs the project test suite once (idempotent — cheap green-light verification post-compaction); if not green, rolls back к Phase 2 retry loop (§6.2).

### 7.2 Reviewer-agent spawns (Q6 + OQ-9)

**Five reviewer-agents in parallel**, one spawn per dimension. Use `reviewer-agent` (plugin-defined; falls back per the registration ladder в `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`).

| Dimension | Scope |
|---|---|
| `bugs` | Logic errors, off-by-one, null/undefined paths, race conditions, broken invariants |
| `security` | Injection, auth/authz, secret handling, untrusted-input flows, OWASP-top-10 surface |
| `architecture` | Layering, coupling, abstractions, dead code, duplication, naming, file/module placement, **docs-staleness** (OQ-9 closure — explicit check for stale README/architecture-doc/contributing-guide references к patterns/files renamed in Phase 2), **spec-compliance** (master plan §139 research deliverable #8 — explicit check that Phase 2 diff matches spec.md scope: no unspec'd files touched, no spec'd requirements unaddressed) |
| `tests` | Coverage of changed lines, edge cases, F→P invariant, brittle assertions, missing negative cases. Pre-condition: tests are green (per Phase 2 §6.2). |
| `code-quality` | Idiomatic style, readability, comments noise, premature abstractions, simplification opportunities (subsumes pre-M4 Phase 5 SIMPLIFY) |

**Spawn template:** reuse pre-M4 Phase 6 Stage C Reviewer Template (`implement-reference.md` L480–560), trimmed к the dimension-specific scope. Each reviewer receives: spec/plan, diff of Phase 2 changes, code-style instructions, project conventions, и (для `architecture` dim) the project's docs files list для staleness scan.

**Spawn invocation:** single message с five `Agent` tool uses (parallel) — matches the parallel-spawn rule в the system prompt.

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
3. State.md marks `phase: phase-3-escalated` with timestamp + round count + unresolved-findings list. Exit transitions:
   - User picks (A) → `phase: debug-handoff` (terminal, M4 exits — caller resumes via `/geniro:debug`).
   - User picks (B) → `phase: ship` (proceeds into §7.5 Ship sub-step с `## Accepted Findings` block в state.md body).
   - User picks (C) → `phase: aborted` (terminal — work uncommitted on disk).

This explicitly avoids the "kick it until it passes" anti-pattern: M4 has а terminal state, и unresolvable findings are the user's call, not the agent's.

### 7.5 Ship sub-step — **DECIDED**

Once Phase 3 self-review exits clean (all dims clean OR §7.4 path B/C taken), Phase 3 transitions к its Ship terminal sub-step. State.md `phase: ship`.

**Steps:**

1. **Pre-Ship Visual Verification** — fires only when frontend files в scope AND Playwright MCP is available (per CLAUDE.md "Optional MCP Dependencies"). Otherwise skipped.
2. **Commit** — `git add <changed files>`, `git commit` с conventional message (e.g., `feat(auth): add OAuth login [ENG-123]`). Task ID inferred от spec/state metadata. Inherits pre-M4 commit pattern от `implement-reference.md:733–740`.
3. **Ship-mode AUQ (OQ-8 closure)** — `AskUserQuestion` с options:
   - **Push only** — `git push origin <branch>`. Done.
   - **Push + open PR** — `git push` then `gh pr create` (ready for review). Append task ID к PR title.
   - **Push + open draft PR** — `git push` then `gh pr create --draft`. `--draft` incompatible с `--web` — if user wants browser, create first then `gh pr view --web`.
4. **Atomic `non-resumable-actions` append (M3 §8, M1 helpers)** — after each side-effect that cannot be replayed safely (`git push`, `gh pr create`, etc.), append а structured entry к state.md frontmatter `non-resumable-actions[]` array via M1 `atomic_state_append`. Entry schema per M3 §8: `{action, completed-at, <action-specific-fields>}`. The append occurs **after** the side-effect succeeds; atomic (so partial-write corruption is impossible mid-crash).
5. **L2 auto-emit (master plan §69, OQ-12)** — emit `convention` к learnings.jsonl когда Phase 3 architecture или code-quality reviewer reported ≥3-instance patterns; emit `decision` if spec.md recorded а non-trivial approach choice (per M2 §5.3 patched trigger contract). Threshold tuning (exact «≥3» semantics) — implementation-detail of reviewer-agent spawn prompt, deferred.
6. **Adjustment-routing (Big / Medium / Small per `implement-reference.md` L778–812)** used когда ship-feedback arrives via PR comments. Since /follow-up is dropped, all adjustment requests route back through /implement itself с the original spec + adjustment description as new $ARGUMENTS.

**Inline modifiers from Phase 1 $ARGUMENTS** (semantic parsing, §5.1) honored here as deterministic overrides — they collapse the ship-mode AUQ:
- **"don't push" / "no push" / "commit only"** → skip ship-mode AUQ entirely. Commit succeeds, no push. State.md transitions к `phase: ship-committed-only` (terminal).
- **"draft only" / "draft PR" / "open draft"** → skip ship-mode AUQ. Push + `gh pr create --draft`. State.md transitions к `phase: done`.
- **"open PR" / "create PR" / "with PR"** → skip ship-mode AUQ. Push + `gh pr create` (ready-for-review). State.md transitions к `phase: done`.
- **"stop after review"** → exit Phase 3 before commit. Surface clean review status as the deliverable. State.md transitions к `phase: self-review-only` (terminal).

When no modifier is present, ship-mode AUQ fires per step 3 above. Modifiers are deterministic — if "draft PR" is in $ARGUMENTS, the model proceeds directly to push+draft without asking.

---

## 8. Ship — see §7.5

Per OQ-1 closure (3-phase structure where Ship is а terminal sub-step of Phase 3), Ship is no longer а standalone numbered phase. The detailed Ship contract lives в §7.5 Ship sub-step above. State.md `phase: ship` during execution, transitions к `phase: done` on clean exit. Section number reserved для backward-compat с cross-doc references; do not renumber subsequent sections.

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
- `skills/_shared/test-first-gate.md:20` — contains "`Lane: full or Lane: light` — those Lanes use the architect's plan + Phase 6 reviewer pipeline as the test-coverage gate". Both Lane terminology AND architect's plan reference are stale. Rewrite to reference M4 self-review (Phase 3, 5 reviewer dimensions §7.2). If the gate's premise (Lane-gated test coverage) no longer applies, consider deleting the file entirely.
- `skills/_shared/effort-scaling.md:49` — references "`/implement` Light Mode vs `/follow-up` Fast Lane trade-off". Both Lane terminology and /follow-up reference stale. Rewrite or delete the row.
- `skills/decompose/`, `skills/follow-up/`, `skills/brainstorm/`, `skills/deep-simplify/`, `skills/features/`, `skills/learnings/`, `skills/cleanup/`, `skills/vendor/` — **entire directories к delete** per master plan §60. NOTE: deletions may land in later milestones (M5+ as each is replaced), not necessarily synchronously with M4. M4 commit must NOT depend on these being deleted yet — M4 SKILL.md и reference.md must work с the deletions either present or pending.

---

## 10. Open questions (carried forward)

All 9 design OQs closed в the OQ-resolution session (recorded в §4 Decisions table). 3 admin items remain:

| ID | Topic | Status |
|---|---|---|
| **OQ-10** | **Memory I/O section (M2 §13 obligation)** — formal enumeration of L2/L3/L4 helpers M4 calls и at which phase boundaries. | ✅ **DONE** — see §13 below. |
| **OQ-11** | **Agent-Computer Interface (ACI) spec (master plan §134, §141)** — explicit tool surface для reviewer-agent spawns + inner-loop Edit/Write/Bash tools + restricted tool list per spawn. | ⏳ **Deferred к M4 implementation phase.** Research-blocked: master plan §134 requires SWE-agent ACI study (1-page minimal spec) before drafting. Implementation phase work-order step 1.5. |
| **OQ-12** | **L2 trigger threshold tuning** — exact «≥3 instances of same pattern» semantics for `type=convention` emit. | ⏳ **Deferred к M4 implementation phase.** Implementation detail of reviewer-agent spawn prompt — the prompt template owns the threshold semantics. M2 §5.3 contract patched; finer-grained tuning happens когда reviewer prompt is drafted. |

---

## 11. Implementation note

When M4 implementation begins (likely via `/geniro:implement` itself, recursively, or by hand on this branch), the work-order is:

1. ~~**Resolve OQ-1 through OQ-9**~~ ✅ **DONE** in M4 v3 — all 9 design OQs closed (see §4 Decisions table).
2. ~~**Reconcile M1 ↔ M3 hook-name drift**~~ ✅ **DONE** in M4 v3.
3. ~~**Reconcile M2 ↔ M4 L2 auto-emit triggers**~~ ✅ **DONE** in M4 v3 (M2 §5.3 patched). OQ-12 threshold tuning deferred к step 1.5.
4. ~~**Memory I/O section**~~ ✅ **DONE** — §13 below (OQ-10).
5. **Research deliverable: ACI spec (OQ-11)** — master plan §134 mandates SWE-agent ACI study before SKILL.md rewrite. Output: 1-page minimal ACI spec defining tool surface для each reviewer-agent spawn type + Phase 2 inner-loop tools. Blocks step 8.
6. **Apply §9.2 surgical edits к `implement-reference.md` first** (lower-risk, preserves working snippets).
7. **Update `_shared/` helpers** per §9.3: `plan-criteria.md`, `root-cause-gate.md`, `test-first-gate.md`, `effort-scaling.md`.
8. **Rewrite `skills/implement/SKILL.md`** against finalized spec + ACI spec (step 5).
9. **Update `CLAUDE.md` full skill-table** per §9.3 (8 skill deletions + add /plan placeholder).
10. **Verify `reviewer-agent` supports the 5 dimensions** including the `architecture` dim's docs-staleness extension (OQ-9); patch if not.
11. **Manual end-to-end test** против а small feature task before merging. Use inline-task ($ARGUMENTS-only) entry-mode since /plan не yet exists.

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
| §102 | "≤3 AUQ gates per-run, ≤5 helper-file reads, ≤5 subagent spawns" | **Spawns:** Phase 3 spawns exactly 5 reviewer-agents (§7.2). ✅ at cap. **Helper reads:** 5 (Phase 1: load-custom-instructions, load-semantic, query-learnings, resolve-conflicts [transitive] + Phase 3: load-custom-instructions always-refresh). ✅ at cap. **AUQ count (per-run):** 1 in happy path (ship-mode §7.5 step 3, suppressed by inline modifiers), 2–3 in error paths (§5.1 disambiguation, §6.3 Phase 2 escalation, §7.4 Phase 3 escalation are all conditional), 4 worst-case. Spec-defined gates total 4 but per-run actual averages 1; master plan §102 budget читается as per-run-actual per its "today's 22" baseline framing. ✅ within budget for happy + typical error runs. |
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

---

## 13. Memory I/O (OQ-10 closure)

M2 §13 obligation: every pipeline skill's `.md` declares which L2/L3/L4 helpers it calls и at what phase boundaries. M4 inventory:

### 13.1 Helper-call schedule

| Phase | Helper | Direction | MODE | Inputs | Outputs | Notes |
|---|---|---|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` | scope = `implement` + `global` + `code-style` | concatenated rule body inlined into context | Echo contract per M2 §7. Survives compaction via M3 SessionStart re-injection. |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` | top-2 default (`project.md` + `codebase-map.md`); optional `features.md` если spec mentions feature backlog | inlined into context + fingerprint drift check | Drift notification surfaces к user если `.fingerprint.json` mismatched. |
| Phase 1 entry | `query-learnings` | read L2 | n/a | tags inferred от task description (e.g., `react`, `auth`, `bug`); scope = task path | top-K matching entries (default K=5, filter superseded + deprecated) | Skipped если task description is too generic к infer tags. |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a | the three loaded layers | precedence-resolved или AUQ on hard conflict | Called transitively by load-* helpers per M2 §7. |
| Phase 2 (Implement) | none | — | — | — | — | No new helper calls during edit batch. Code-style instructions от Phase 1 L4 refresh remain в context. |
| Phase 3 entry | `load-custom-instructions` | read L4 | `refresh` | same scope as Phase 1 | re-inlined | Always re-fires at Phase 3 entry. Drops the conditional-on-marker pattern from M4 v3 draft — simpler, no M3 marker contract needed. Cost: 1 helper read, within master plan §102 cap of ≤5. |
| Phase 3 fix-loop iteration | `query-learnings` | read L2 | n/a | tags + scope = changed-file paths | similar past findings | Used к prime reviewer-agent prompts с known conventions/pitfalls. |
| Phase 3 ship sub-step | `emit-learning` | write L2 | n/a | producer = `/geniro:implement`; scope = changed-file paths; summary, tags, type, ext | append к `learnings.jsonl` | Fires когда §7.5 step 5 conditions are met (≥3-instance pattern OR spec.md-recorded decision). Dedup + sanitization per M2 §5.2. |
| Phase 3 ship sub-step | `update-semantic` | write L3 | n/a | operation (add-module / move / rename); path; description | append к `codebase-map.md` (lock-guarded) | Fires когда Phase 2 added а new module / file the L3 codebase-map should index. |
| Phase 3 ship sub-step | M1 `atomic_state_append` | write T1 | n/a | state.md path; new entry к `non-resumable-actions[]` | append-only update | Fires after each `git push`, `gh pr create`, posted comment, etc. M3 §8 schema. |

### 13.2 L2 emit triggers (per M2 §5.3 patched contract)

| Type | When M4 emits |
|---|---|
| `convention` | Phase 3 architecture или code-quality reviewer reports ≥3 instances of same pattern в changed code. Threshold tuning lives в reviewer-agent spawn prompt (OQ-12 deferred). |
| `decision` | Spec.md records а non-trivial approach choice с `## Considered Alternatives` section. M4 mirrors that decision к L2 для cross-session recall. (Note: when /plan exists post-M5, /plan emits the `decision` entry directly; M4-only path для inline-task mode.) |
| `diagnosis` | Not emitted by M4 directly. `/geniro:debug` owns this trigger. M4 may consume а T2 handoff from /debug containing а diagnosis (per §5.4) — but does не re-emit. |
| `pitfall` | Not emitted by M4. `/geniro:review` owns this trigger. |
| `discovery` | Not emitted by M4. `/refactor` и `/onboard` own this trigger. |

### 13.3 L3 update sites

`update-semantic` writes to:
- `codebase-map.md` — add-module / move / rename operations from Phase 2 file diffs. Bounded auto-incremental (M2 §6.1) — does не rewrite entire L3, just appends а single-line entry per change.
- NOT `features.md` — feature-backlog updates owned by /plan (M5) per master plan §68 (`/features` skill deleted).
- NOT `project.md` или `architecture.md` — those are user-curated, не auto-updated.

### 13.4 Phase boundary refresh sites (M3 §7.3)

| Boundary | Refresh action | Why |
|---|---|---|
| Phase 1 entry | `load-custom-instructions(MODE: refresh)` + `load-semantic(MODE: refresh)` | Initial context load |
| Phase 3 entry | `load-custom-instructions(MODE: refresh)` — **always** | Survive Phase-2 compaction without requiring а M3 marker contract; M3 hook remains read-only. Cost: 1 extra helper read (5 total per run within master plan §102 budget). |
| Phase 3 ship sub-step exit | none | Skill terminates; refresh not needed |

Other helpers (`load-semantic`, `query-learnings`, `emit-learning`, `update-semantic`, `resolve-conflicts`) have no `MODE: refresh` semantic per M3 §7.3 (only the two readers do).
