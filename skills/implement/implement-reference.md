# Implement Skill — Reference Material

This file contains templates, examples, error tables, and detailed procedures referenced by SKILL.md. The orchestrator reads specific sections at the relevant phase — not the entire file at once.

---

## Phase 1: Auto-Detection Table

| What you say | What the skill detects | Behavior |
|---|---|---|
| `/geniro:implement milestone 2` or `/geniro:implement milestone 2 ship it` | Milestone reference (from /geniro:decompose) | Glob `<task-dir>/milestone-2-*.md`, load that milestone file as the implementation target; skip Phase 1 discovery |
| `/geniro:implement <path-to-milestone-N-foo.md>` | Explicit milestone path | Load that milestone file as the implementation target; skip Phase 1 discovery |
| `/geniro:implement continue` | Continue a decomposed pipeline | Read `<task-dir>/state.md` `Milestones:` field, pick the first non-completed milestone, load its file |
| `/geniro:implement add OAuth login` | Plain description | Full discovery with interactive questions |
| `/geniro:implement ENG-123` | Issue tracker reference (from workflow) | Fetches issue via configured integration, uses as context |
| `/geniro:implement https://linear.app/team/issue/ENG-123` | Issue tracker URL (from workflow) | Extracts issue ID, fetches via configured integration |
| `/geniro:implement ENG-123 add OAuth login` | Issue reference + description | Fetches issue, supplements with description |
| `/geniro:implement F3` or `/geniro:implement F3 add OAuth login` | Geniro feature ID (`F<n>`) | Read `.geniro/planning/FEATURES.md`, look up the row for the matching ID, use its description (and linked spec file in the Notes column, if present) as the implementation target |
| `/geniro:implement just do it` or `ASAP` | Urgency signals | Auto mode: skip interactive questions |
| `/geniro:implement I think we should add OAuth` | Tentative language | Assumptions mode: propose plan |

**Detection rules (checked in order):**
0. **Milestone reference** — patterns (checked in priority order): (a) `^milestone\s+(\d+)\b` at start of `$ARGUMENTS`, (b) `$ARGUMENTS` references a path ending in `milestone-<N>-*.md`, (c) `$ARGUMENTS` equals `continue` AND `<task-dir>/state.md` contains a `Milestones:` field. If any matches, load the milestone file via Phase 2 pre-check rule 1 and skip remaining rules. Milestone detection takes priority over workflow files and feature IDs because the user explicitly pointed at a specific unit of work.
1. Check `.geniro/workflow/*.md` for argument detection patterns. Apply them in order before falling through to mode signal detection.
2. **Geniro feature ID** — pattern `^F\d+(\s|$)` at start of `$ARGUMENTS`. Read `.geniro/planning/FEATURES.md` if present and look up the matching row. If FEATURES.md is missing or the ID is not found, treat the rest of `$ARGUMENTS` as a plain description and warn the user once. If found, capture the row's description and spec-file path (from the Notes column) — these get persisted to `state.md` (see SKILL.md Phase 1).
3. **Auto-mode signals** — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/auto-mode-signals.md` for the canonical phrase list. If any canonical phrase is matched, skip interactive questions, pick recommended defaults for non-workspace gray areas. `"auto"` and `"quick"` are NOT triggers — they collide with common technical vocabulary (`auto-save`, `quick-action`).
4. **Assumptions-mode signals** — tentative language like "I think", "maybe", "what if", "should we" -> propose plan with assumptions, let user correct
5. **No special signals** — MUST ask the user which mode to use via `AskUserQuestion` (see "Mode Selection prompt" below). This is **Always-WAIT**: do NOT silently default to a mode even when a harness "Auto Mode" / "minimize interruptions" system reminder is active — the harness Auto Mode is a permission classifier, not a per-skill mode answer. Default-to-recommend is interactive

If a workflow integration's backend (e.g., MCP) is unavailable, log a warning and proceed without — all integrations are non-blocking.

**Mode Selection prompt** (Always-WAIT — MUST fire from Step 1 of SKILL.md when no explicit signal was detected in `$ARGUMENTS`. Do NOT skip even when a harness-level "Auto Mode" / "minimize interruptions" system reminder is present — the harness Auto Mode is a permission classifier, not a per-skill mode answer; the three skill modes have user-distinguishable trade-offs and the choice gates 8+ downstream WAIT gates. If `AskUserQuestion` returns an empty answer, fall back to plain-text and re-ask):

Use `AskUserQuestion`:
- **Question:** "How should I run this implementation?"
- **Header:** "Mode"
- **Options:**
  - Label: "Interactive (Recommended)" / Description: "Full discovery — I'll ask about gray areas, confirm the architect's plan, and check before shipping."
  - Label: "Auto mode" / Description: "Pick recommended defaults for gray areas. I still WAIT at git workspace, existing-plan skeptic blockers, plan approval, Stage C fix-loop after 3 rounds, Pre-Ship Visual Verification follow-up, and the ship decision — auto mode never silently approves a plan. See §Auto Mode Behavior for the full list."
  - Label: "Assumptions" / Description: "I'll propose a plan with my best guesses on gray areas — you correct anything wrong before architecting."

Skip the prompt entirely if `$ARGUMENTS` already contained an explicit auto-mode signal (rule 3) or assumptions-mode signal (rule 4). Persist the chosen mode in `<task-dir>/state.md` under a `Mode:` line so resumed runs and downstream phases read it without re-prompting.

**Anti-rationalization (Mode Selection prompt):**

| Reasoning | Why it's wrong |
|---|---|
| "Harness 'Auto Mode' is on — user must want auto, skip the prompt" | Harness Auto Mode is a permission classifier (Anthropic engineering: claude-code auto mode), not a per-skill mode answer. The three modes (Interactive / Auto / Assumptions) have user-distinguishable trade-offs — Assumptions exists specifically for users who want a plan with explicit guesses to correct, which auto-defaulting to "Auto" loses. |
| "The user picked auto last time, just pick it again" | Mode is per-run, not per-user. Re-asking each invocation is the contract. Memory of past choices is not a substitute for the current `AskUserQuestion`. |
| "AskUserQuestion returned empty, treat as 'auto'" | Empty answer is the upstream Claude Code bug (#29547), not a user choice. Fall back to plain text and re-ask. Do NOT pick any default on empty. |

**Example discovery gray-area questions (interactive mode, batch 3-5). The git workspace question is NOT in this batch — it fires earlier as part of the upfront always-WAIT consolidated AUQ alongside Mode + Lane + Feature (see SKILL.md §Phase 1 Step 7 git-workspace bullet); the "Git workspace" line at the end of the list below is kept for canonical option-text reference. In auto-mode the gray-area batch is silent (defaults applied per §Auto Mode Behavior); the git workspace question still fires upfront in the consolidated AUQ:**
- Scope: Backend-only? Frontend? Both? (recommend: match existing split)
- Backwards compat: Support old API during transition? (recommend: yes, deprecation warning)
- Performance: Any constraints or targets? (recommend: <100ms latency for endpoints)
- Testing: Unit/integration/e2e? (recommend: maintain current test coverage)
- Rollout: Gradual rollout or all-at-once? (recommend: feature flag + gradual)
- **Git workspace:** A) New feature branch (recommend for most features), B) Current branch, C) Git worktree (for risky/experimental changes with instant rollback without touching main working directory, parallel work when running multiple Claude sessions on same repo, or long-running features where you need to context-switch — isolates entire implementation in a separate working tree)

---

## Phase 1 Step 0: Complexity Gate

**Purpose:** Classify the request and ask the user which Lane to run: Full pipeline, Light Mode (Trivial tasks), or TDD Mode (small focused features where the user wants RED→GREEN-per-behavior discipline). Each Lane has different skip/keep semantics — see §"Light Mode Semantics" and §"TDD Mode Semantics" below for the full deltas.

**When to SKIP the gate (any of these applies → proceed straight to Step 1, Lane defaults to `full`, no prompt):**
1. Milestone reference detected (Auto-Detection Table rule 0 matched).
2. On-disk plan-file path present in `$ARGUMENTS` (handled by Phase 2 pre-check rule 4).
3. Plan-mode conversation plan is active (handled by Phase 2 pre-check rule 2).
4. `state.md` already contains a `Phase 1 Step 0:` line (resume or second-run already decided this gate).
5. `<task-dir>/state.md` `Completed phases` includes Phase 1 (interrupted after Phase 1 — do not re-prompt).

**When the gate FIRES:** none of the skip conditions apply AND `$ARGUMENTS` is a natural-language request describing the change.

**Signals used (canonical rubric — do NOT duplicate):**

Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` for the canonical 9 hard escalation signals and the Trivial/Small/Medium/Big tiers. Apply those definitions here verbatim.

**Decision procedure:**

1. **Hard-signal scan.** Read `$ARGUMENTS` and any obvious file mentions. If any of effort-scaling's 9 hard escalation signals fire (new entity/table/migration, new endpoint/page, auth/permissions, new module, 3+ modules, open-closed violation, new async/queue, new external integration, ambiguous intent) → proceed silently to Step 1 with `Lane: full`, no prompt. Do NOT offer Light Mode OR TDD Mode — both are unavailable when any hard signal is present (Light Mode skips architect; TDD Mode skips the parallel-waves model — neither is safe under hard escalation).
2. **Explicit-TDD signal scan.** If `$ARGUMENTS` contains an explicit TDD request (`tdd`, `test-driven`, `red-green`, `RED→GREEN`, `behavior-by-behavior`, `one test at a time`) AND no hard signal fired AND scope is Small (1 module, ≤5 distinct behaviors, ≤8 files) → present TDD Mode as the recommended option (see Step 4 below). TDD Mode is opt-in via this signal OR via the "Pick Lane" UI in Step 4 — it is NEVER the silent default.
3. **Trivial assessment.** Otherwise, estimate whether the request reads as Trivial per effort-scaling's Trivial definition (score 0 + 1-2 files + single module + unambiguous intent — see `skills/_shared/effort-scaling.md` Step 2). If unclear, proceed silently to Step 1 with `Lane: full` — the gate only fires on a clear Trivial signal.
4. **If Trivial OR explicit-TDD signal AND no hard signals:** use `AskUserQuestion` with header "Lane" — pass the options as separate `label` and `description` fields. Composition depends on which signal fired:
   - **Trivial only (no TDD signal):** present 2 options:
     - **Label:** "Light Mode (Recommended)" / **Description:** "Skip architect + simplify + spec-compliance + adversarial-tester. Keep knowledge retrieval, lightweight plan + approval, full Stage C review grid (6–7 reviewers + relevance-filter), and ship gates. ~70% cheaper, ~30% faster."
     - **Label:** "Full pipeline" / **Description:** "Architect + skeptic + every Phase 6 stage. Choose this when you want maximum architectural rigor even on small changes."
   - **Explicit TDD signal AND Trivial:** present 3 options (TDD recommended):
     - **Label:** "TDD Mode (Recommended)" / **Description:** "RED→GREEN per behavior; sequential WUs (one test at a time); pre-code interface-design gate; refactor-after-green per cycle. Best for small focused features where you want behavior-incremental verification. Skips Phase 6 Stage D adversarial-tester (every behavior is already F→P-verified)."
     - **Label:** "Light Mode" / **Description:** "Skip architect + simplify + spec-compliance + adversarial-tester. Keep parallel waves + Stage C review. Faster than TDD for trivial changes that don't benefit from behavior-incremental design."
     - **Label:** "Full pipeline" / **Description:** "Architect + skeptic + parallel waves + every Phase 6 stage. Choose for maximum architectural rigor."
   - **Explicit TDD signal AND Small (not Trivial):** present 2 options:
     - **Label:** "TDD Mode (Recommended)" / **Description:** "RED→GREEN per behavior; sequential WUs; pre-code interface-design gate. Recommended for the explicit TDD request. Phase 2 architect still runs (validates the test list + interface design)."
     - **Label:** "Full pipeline" / **Description:** "Standard parallel-waves implementation. Use if you want architect + parallel WU execution despite asking for TDD."
5. **Persist the choice.** After Step 1 writes the `Mode:` line to state.md, append `Lane: <light|full|tdd>` and `Phase 1 Step 0: <full pipeline | light mode | tdd mode | full pipeline (forced — hard signal)>`. (If the gate was skipped before reaching the AUQ branch, use `Phase 1 Step 0: skipped — <reason>` instead, where reason is one of: `milestone`, `plan-path`, `plan-mode`, `resume`. Hard-signal forcing is NOT a "skipped" reason — the gate fires and runs Step 1 of the decision procedure; it just bypasses the AUQ branch in Step 4 and proceeds with `Lane: full`. The `Lane:` line is always written — `light`/`tdd` only when the user explicitly picks it, `full` in every other case.)
6. **If not clearly Trivial AND no explicit-TDD signal (Small/Medium/unclear):** proceed silently to Step 1 with `Lane: full` — do NOT prompt. The gate is biased toward the heavier lane — only fires on clear Trivial signal or explicit-TDD signal.

**Anti-rationalization:**

| Reasoning | Why it's wrong |
|---|---|
| "Looks Trivial enough, skip even with a hard signal" | Hard signals override size. A 1-file auth change is Medium-complexity minimum — Light Mode is unavailable. |
| "User said it's simple, trust them" | User-stated simplicity is not a signal — apply the rubric objectively. |
| "Skip the prompt, just pick Light Mode silently" | The gate is an `AskUserQuestion` WAIT. User must confirm — they may want architect review even for a typo. Silent routing removes the safety gate. |
| "Pick Light Mode by default for Trivial" | Default is Full for anything the user did not explicitly opt into. Recommend Light Mode in the AUQ description, but the user's explicit answer decides. |
| "Also offer /geniro:follow-up as an option" | Out of scope for this gate. /follow-up is its own skill with its own entry. /implement Light Mode stays in /implement. |

---

## Light Mode Semantics

What Light Mode changes within /implement. Read this when `Lane: light` is set in state.md.

**Skipped in Light Mode:**
- Phase 2 — architect-agent + skeptic-agent. Replaced with: orchestrator writes a Small-tier lightweight plan to `<task-dir>/plan-<slug>.md` directly, using Phase 1's spec.md + knowledge-retrieval output + Reuse Inventory as input. Plan structure: Goal + Approach + Steps per `_shared/effort-scaling.md` Step 3 "Small" tier.
- Phase 5 — simplify agent. Code quality is covered by Stage C reviewers in Light Mode.
- Phase 6 Stage B — spec-compliance subagent. Light Mode has no architect-produced spec contract to verify; the lightweight plan's Goal + Steps are validated against the diff in Stage C.
- Phase 6 Stage D — adversarial-tester-agent. Stage C tests-dimension reviewer still runs (it REPORTS gaps); Stage D's F→P-authoring is the cost-trade in Light Mode.

**NEVER skipped in Light Mode (these run identically to Full):**
- Phase 1 Step 3 — knowledge-retrieval-agent
- Phase 1 Step 5 — Convention Discovery + Reuse Inventory
- Phase 1 Step 7 — gray-area resolution AUQ (git workspace AUQ fires upstream in the Phase 1 Startup Consolidation; only the git workspace **setup** at Step 10 happens here in pipeline-order)
- Phase 3 — plan approval gate (presents the lightweight plan; user can still pick Adjust / Too large)
- Phase 4 — backend/frontend parallel waves; Zero Direct Edits applies at every lane
- Phase 6 Stage A — automated checks (build + lint + test + codegen + runtime startup)
- **Phase 6 Stage C — full 6–7 parallel reviewer agents + relevance-filter-agent** (the safety contract for Light Mode hinges on writer/reviewer separation; never collapse Stage C in Light Mode)
- Phase 6 Fix Loop (max 3 rounds, fresh fixers + fresh reviewers)
- Phase 7 — Pre-Ship Visual Verification, ship decision, learnings, doc updates

**Hard escalation signals make Light Mode unavailable** — Phase 1 Step 0 silently forces `Lane: full` when any of the 9 hard signals from `_shared/effort-scaling.md` Step 1 fire.

**Mid-flight escalation:** If Phase 4 reveals signals that should have forced Full (e.g., the implementation requires a migration that wasn't visible in `$ARGUMENTS`), the Phase 4 fix loop and Stage C reviewers are the safety net — they catch the issue at review time. There is no in-flight `light → full` lane switch; the user re-invokes /implement with the corrected request when re-architecture is needed (matching Phase 7 Step 6 Big tweak path).

**Anti-rationalization:**

| Reasoning | Why it's wrong |
|---|---|
| "Phase 6 Stage C is heavy too — collapse to 1 reviewer for Light Mode" | Stage C is the safety contract for Light Mode. Architect-skip is acceptable BECAUSE writer/reviewer separation is preserved at review time. Collapsing Stage C removes the contract — at that point you should be in /follow-up Fast Lane, not /implement Light Mode. |
| "I'll write the lightweight plan as I implement" | Plan must be written and approved at Phase 3 BEFORE Phase 4 begins. Light Mode reduces plan depth (Small structure), not plan timing. |
| "Phase 1 Step 5 Reuse Inventory is heavy — skip it in Light Mode" | Reuse Inventory IS the convention-discovery substitute for the architect's pattern-research. Skipping it in Light Mode means agents in Phase 4 reinvent helpers — a worse outcome than Full. |
| "Skip the gray-area AUQ in Light Mode — Trivial tasks have no gray areas" | Trivial tasks routinely have unstated gray areas (which file location? which existing helper to extend?). Phase 1 Step 7 stays mandatory; Light Mode does not change interaction style. |

---

## TDD Mode Semantics

What TDD Mode changes within /implement. Read this when `Lane: tdd` is set in state.md.

**Constitution:** TDD Mode replaces the parallel-waves model in Phase 4 with sequential RED→GREEN per behavior. Each behavior is one test, then one implementation, then verify. This trades parallelism for behavior-incremental discipline — best for small features where the user wants the test list itself to drive the design.

**Skipped in TDD Mode:**
- Phase 4 parallel waves — replaced with sequential RED→GREEN cycles (one test at a time, see "Phase 4 in TDD Mode" below).
- Phase 6 Stage D — adversarial-tester-agent. Every behavior in TDD Mode is already F→P-verified at authoring time (RED before GREEN); adding a second F→P pass is redundant. Stage C tests-dimension reviewer still runs.

**Modified in TDD Mode:**
- Phase 1 Step 5 — Reuse Inventory still runs, but its scope expands to include "what existing public interfaces does the test list need to call?" The test list IS the design exploration; reuse decisions feed it.
- Phase 2 — architect-agent runs (Phase 2 is NOT skipped in TDD Mode; it produces the test list + interface design + ordering). Architect output is structured differently: instead of a Steps table grouped by file, it produces a numbered behavior list (each behavior = one future test). Skeptic validates the behavior list for coverage + ordering.
- Phase 3 — gains Interface-Design Pre-Approval Gate (see "Interface-Design Pre-Approval Gate (Lane:tdd only)" below). User confirms the public interface signatures BEFORE plan approval. Plan approval still gates code generation; interface gate gates plan presentation.
- Phase 4 — see "Phase 4 in TDD Mode" below.
- Phase 5 — Simplify still runs but is scoped per-cycle (after each RED→GREEN, optional micro-refactor with `git stash` checkpoint). The whole-feature simplify pass is REPLACED by per-cycle passes.
- Phase 6 Stage A/B/C — run as in Full Lane.

**NEVER skipped in TDD Mode (run identically to Full):**
- Phase 1 Step 3 — knowledge-retrieval-agent
- Phase 1 Step 7 — gray-area resolution AUQ (git workspace AUQ fires upstream in the Phase 1 Startup Consolidation; only the git workspace **setup** at Step 10 happens here in pipeline-order)
- Phase 3 — plan approval gate (presents the behavior list + interface design)
- Phase 6 Stage A — automated checks
- Phase 6 Stage C — full reviewer grid + relevance-filter
- Phase 7 — ship gates, learnings, doc updates

**Hard escalation signals make TDD Mode unavailable** — Phase 1 Step 0 silently forces `Lane: full` when any of the 9 hard signals fire. TDD Mode's sequential model cannot keep up with cross-stack coordination at hard-signal scale.

### Phase 4 in TDD Mode

Replace the standard parallel-waves model with sequential cycles. The architect's behavior list (from Phase 2) drives the cycle ordering.

For each behavior in the architect's numbered list:

1. **Re-read the behavior** — what does this cycle add? What's the assertion?
2. **RED — author the test.** Spawn ONE backend or frontend agent (matched to the behavior's surface) with a single instruction: "Author one test for behavior #N: <behavior text>. Use the public interface signatures from the approved Interface-Design (in `<task-dir>/interface.md`). Do NOT touch implementation. The test MUST fail on current code."
3. **Verify RED.** Orchestrator runs the test; confirm failure with a real-looking signature (`AssertionError: ...` or equivalent). If the test passes on current code, REJECT — the test is testing existing behavior, not the new behavior. Re-spawn the test author with the rejection reason.
4. **GREEN — minimal implementation.** Spawn ONE agent with: "Make test #N pass with minimal code. Do NOT add anything not required by this test. Do NOT anticipate behavior #N+1."
5. **Verify GREEN.** Orchestrator runs the test + the full project test suite; confirm both pass. If the new test passes but other tests fail, the implementation regressed — fixer agent loop (max 1 round), then escalate.
6. **REFACTOR (optional, post-GREEN).** If the cycle's GREEN code introduces obvious duplication or muddies an interface, spawn a focused refactor agent. Constraint: refactor preserves all tests green. If refactor breaks anything, `git stash` the refactor and continue to next behavior.
7. **Update state.md** — append `Cycle <N> completed: <behavior summary>` so resume picks up at cycle N+1.

**Cycle ordering is DETERMINED by the architect's list** — orchestrator does NOT re-order. If the architect's list has dependencies (cycle 5 depends on cycle 3), the architect should have ordered them correctly; the skeptic validates.

**Parallelism is OFF in TDD Mode** — agents are spawned sequentially. The whole point is per-behavior RED→GREEN verification; parallelism breaks the discipline.

**Hotspot files (registrations) still happen** — but inside the cycle that introduces the behavior they expose, not in a separate "hotspot wave."

### Interface-Design Pre-Approval Gate (Lane:tdd only)

Before Phase 3's plan approval gate, fire a SECOND `AskUserQuestion` with header "Interface" — only when `Lane: tdd`.

Procedure:
1. Read the architect's behavior list (Phase 2 output).
2. Read the architect's proposed public interface signatures (function names, parameter types, return shapes, error modes — for each module the test list will exercise).
3. Format as a single code block per module: signature lines + 1-line "behaviors that exercise this interface" each.
4. Fire `AskUserQuestion` with header "Interface" and 3 options:
   - **Label:** "Interfaces look right — proceed to plan approval (Recommended)" / **Description:** "Phase 3 plan approval will follow next."
   - **Label:** "Adjust interfaces" / **Description:** "Describe what to change. Architect re-runs with the corrections; interface gate re-fires."
   - **Label:** "Restart Phase 2" / **Description:** "The interface design is fundamentally wrong. Architect re-runs from scratch."

5. **If user picks "Interfaces look right"**: write the approved interface to `<task-dir>/interface.md` (canonical reference for all Phase 4 cycles); proceed to Phase 3 plan approval.
6. **If user picks "Adjust"**: collect adjustment via plain text (NOT a second AUQ — gives the user freeform feedback); re-spawn architect with the corrections; re-fire the interface gate. Max 3 adjustment rounds; after 3, present the final state via plain text and ask "Approve as-is or restart?"
7. **If user picks "Restart"**: re-run Phase 2 architect from scratch; re-fire the interface gate. Max 1 restart per session — if interface design is still wrong after a full restart, the request is too ambiguous for TDD Mode → escalate to Full Lane.

This gate is **Always-WAIT** in `Lane: tdd` — the interface design is the foundational decision in TDD; getting it wrong cascades into every cycle. Auto Mode does NOT auto-default — see Auto Mode Behavior table.

### Anti-rationalization (TDD Mode)

| Reasoning | Why it's wrong |
|---|---|
| "TDD is just writing tests first — I'll spawn parallel WUs as usual and call it TDD" | TDD's discipline is RED→GREEN-per-behavior, not "tests first." Parallel WUs let test N pass while implementation N+1 is in flight — that's not TDD, that's standard implementation with tests. Sequential cycles or no TDD. |
| "The architect's behavior list has 8 behaviors — that's too many for sequential. I'll batch 2-3 per cycle" | Each cycle is ONE behavior. Batching is the horizontal-slicing anti-pattern (write all tests then all impl) that produces "tests of the shape of things, not actual behavior" — see `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md` Test Design Philosophy §1-2. If 8 behaviors is too many, the scope is too large for TDD Mode — escalate to Full. |
| "I'll skip the interface gate — the architect's plan already has signatures" | The interface gate is what makes TDD Mode work. Without explicit interface confirmation BEFORE the cycle starts, every cycle re-litigates the signature and the test churn explodes. Always-WAIT — fire the gate. |
| "Stage D is also F→P; I'll keep it for extra safety" | Every test in TDD Mode is already F→P-verified at the cycle boundary. Stage D's value-add is "tests for missed edges" — but TDD Mode's behavior list is the spec the user explicitly approved at the interface gate, so missed edges are a spec gap, not a test gap. Skip Stage D; if the user wants more edges, they re-invoke /implement after the TDD run. |
| "Refactor-after-green is optional — skip it to ship faster" | Skipping the refactor step accumulates the design debt that TDD specifically prevents. Even a 30-second refactor (rename a poorly-named local, extract a duplicated helper) compounds into a clean codebase across cycles. Don't skip — use `git stash` on regressions if needed. |

---

## Auto Mode Behavior

Canonical table for what every WAIT gate does when `<task-dir>/state.md` shows `Mode: auto` (set either by rule 3 of §Phase 1 Auto-Detection Table or by the Mode Selection prompt). Skill orchestrator MUST read `Mode:` from state.md at every gate and consult this table — do not auto-resolve gates not listed here.

| Gate | Phase / Step | Auto-mode action |
|---|---|---|
| Complexity gate (Lane Selection) | Phase 1, Step 0 | **Always-WAIT.** Fire `AskUserQuestion` with the Lane options (Light Mode / TDD Mode / Full pipeline — composition depends on signals per Phase 1 Step 0 Decision Procedure) regardless of auto-mode. Lane choice gates ~5 downstream phases (Phase 2, 5, 6 Stage B, 6 Stage D) and has user-distinguishable trade-offs (depth vs. speed vs. behavior-discipline) — same shape as plan approval and ship decision. Do NOT auto-default. If hard escalation signals fire, the gate is bypassed silently to `Lane: full` — that's not an auto-mode override, it's the rubric forcing Full. Empty AUQ answer = upstream Claude Code bug — fall back to plain text and re-ask. |
| Interface-design pre-approval gate | Phase 3 (TDD Mode only) | **Always-WAIT.** Fire `AskUserQuestion` with header "Interface" with the 3 options from §"Interface-Design Pre-Approval Gate (Lane:tdd only)" — proceed / adjust / restart. Auto Mode does NOT auto-default — interface design is the foundational decision that drives every TDD cycle; getting it wrong cascades. Empty AUQ answer = upstream Claude Code bug — fall back to plain text and re-ask. |
| Gray-area resolution | Phase 1, Step 7 | Pick recommended default for each gray-area question; do NOT include git workspace here — it's resolved upstream in the Phase 1 Startup Consolidation AUQ (see Git workspace row below). Append one-liner per gray-area decision to `state.md` "Auto-mode decisions" |
| Git workspace | Phase 1 (upfront consolidated AUQ) | **Always-WAIT.** Asked via `AskUserQuestion` even in auto-mode — where the change lands (new branch / current / worktree) is a deliberate user decision, not a gray-area default. Do NOT auto-pick Option A or Option B. Batched into the upfront always-WAIT AUQ call alongside Mode/Lane/Feature when those apply (see SKILL.md §Phase 1 Step 7 git-workspace bullet) — one consolidated call instead of 2-4 sequential prompts. |
| Existing-plan skeptic blockers | Phase 2 pre-check | Always-WAIT (auto-using a flagged plan is unsafe — user must see the concerns) |
| Plan approval | Phase 3 | **Always-WAIT.** Print the full plan content verbatim (per Phase 3 header "present the full plan file (do NOT summarize)") and the skeptic validation summary (N blockers, M warnings), then ask via `AskUserQuestion` regardless of mode. Auto mode never silently approves a plan — plan approval gates all Phase 4 code generation, so the LLM MUST get explicit user confirmation |
| Compact prompt | Phase 3 (post-approval) | "Continue now" (skip compaction). Skip `AskUserQuestion` |
| Stage C fix loop after 3 rounds | Phase 6 | **Always-WAIT.** Auto-shipping known CRITICAL/HIGH issues is unsafe. Surface the `AskUserQuestion` regardless of mode |
| `[PRODUCT-DECISION]` finding encountered | Phase 6 Stage C fix loop (this skill) + consumer skills (`/review` Phase 6, `/follow-up` Phase 5, `/refactor` Phase 5, `/debug` Step 5) | **Always-WAIT.** Auto-shipping a chosen-but-not-authorized product path is unsafe. When any finding has `decision: PRODUCT-DECISION`, fire `AskUserQuestion` with the finding's enumerated `Options:` (per the schema in `agents/reviewer-agent.md` §Output Format) BEFORE any fix-path selection. Empty answer = upstream Claude Code bug — fall back to plain text and re-ask; never auto-default. Auto-mode does NOT auto-resolve — multi-path resolution is a user judgment call, not a gray-area default. When >4 options exist, chain `AskUserQuestion` calls per the cap-extension pattern in `skills/review/SKILL.md` Phase 6 "Failing tests" block — never split or drop options to fit a single question. **Refactor variant:** in `/refactor` Phase 5, the AUQ presents escalation choices (Run /implement / Revert / Document) instead of the finding's `Options:` — refactor's zero-behavior-change constitution forbids picking a fix-path in-skill, so a multi-path finding is escalated, not gated-and-fixed. |
| Suggest improvements | Phase 7, Step 3 | "Skip" (defer improvements; user can run `/geniro:follow-up` later) |
| Pre-Ship Visual Verification | Phase 7, Step 4.5 | "Skip — already verified". If Step 4.5 itself was forced and surfaced issues, the follow-up question is **always-WAIT** (auto-shipping UI regressions is unsafe) |
| Ship decision | Phase 7, Step 5 | **Always-WAIT.** Controls commit/push/PR. User must explicitly choose |
| Cleanup planning artifacts | Phase 7, Step 8 | "Keep" (preserve artifacts; safe default) |
| Next-milestone prompt | Phase 7 Step 8 (milestone-mode only) | "Compact first, then continue". Print the `/compact` instruction + `/geniro:implement continue` resume command. Skip `AskUserQuestion` |

**Auditability:** every auto-resolved decision MUST be appended to `<task-dir>/state.md` under a section named "Auto-mode decisions" with one line per gate: `Phase X Step Y — <gate name> → <chosen option>`.

---

## Phase 4: Decomposition Example

**Example decomposition for "Add user settings page with API":**
```
WU-1 (backend-agent): DB migration + Settings model + repository    [files: migration.sql, settings.model.ts, settings.repo.ts]
WU-2 (backend-agent): Settings service + validation logic            [files: settings.service.ts, settings.validator.ts, settings.service.test.ts]
WU-3 (backend-agent): API route + controller + API tests             [files: settings.controller.ts, settings.routes.ts, settings.api.test.ts]
WU-4 (frontend-agent): Settings page component + state               [files: SettingsPage.tsx, useSettings.ts, SettingsPage.test.tsx]
WU-5 (frontend-agent): Settings form components + styling            [files: SettingsForm.tsx, SettingsField.tsx, settings.css]
WU-6 (backend-agent): Infra cleanup — env vars + terraform + codegen [files: .env.example, main.tf, generated/api-client.ts]

Dependency graph:
  Wave 1: WU-1 (no deps)  |  WU-4 (no backend deps - uses mock API)  |  WU-5 (no deps)
  Wave 2: WU-2 (depends on WU-1 model)
  Wave 3: WU-3 (depends on WU-2 service)  ->  WU-6 (codegen + cleanup, depends on WU-3 API)
  Wave 4: update WU-4 with real API types from WU-6 codegen
  Hotspot: routes/index.ts (register new route) — done last (Step 5 micro-edit)
```

Note: WU-6 groups three small steps (env vars, terraform, codegen) into one WU — more efficient than 3 separate agents, but still delegated, never done by orchestrator.

---

## Phase 4: Agent Delegation Template

When spawning any implementation agent, use this template:

```markdown
## Task — Work Unit [WU-N]
[Copy the relevant Steps from the plan file for this WU — NOT the entire plan, just this WU's steps with their files, details, and verify criteria]

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

## Definition of Done
- [ ] [File X created/modified with specific content]
- [ ] [Test file Y created with unit/integration tests for all new logic]
- [ ] [Tests pass for this WU's scope — new AND existing]
- [ ] [No changes outside the listed files]

## Pre-Inlined Context
[Paste file contents you already read — saves agent from re-reading]
[If Wave 2+: include relevant outputs from prior wave agents]

## Codebase Conventions
[Paste the CONVENTIONS_BRIEF section from spec file — naming patterns, file structure, error handling, import style, test patterns. Include 1-2 exemplar file snippets showing the patterns to follow.]
Match existing patterns exactly. Find the closest existing example and follow it.

## Reuse Inventory (verify-before-creating)

[paste REUSE_INVENTORY from spec.md inline]

Before writing any new helper, component, type, or config: Grep the project for an analogue. If one exists, REUSE-AS-IS or EXTEND it instead of creating new. Only create new when the inventory categorized this candidate NO-ANALOGUE (with the architect's justification) — and even then, do NOT force-fit by adding a parameter or conditional to an existing helper just to reuse it; pragmatic local duplication is preferred until the third occurrence (Rule of Three).

## Design Conventions (when frontend files in scope)
[If the spec's CONVENTIONS_BRIEF includes a DESIGN_CONVENTIONS subsection, paste it here. Frontend-agent uses this as anchor context for tokens, primitives, exemplars, scales — so design isn't re-discovered every cycle. If no design system was detectable, paste the greenfield baseline statement from the spec.]

## UI Intent (when UI Preview Gate ran — paste contents of `<task-dir>/ui-preview.md` if it exists; otherwise omit this section entirely)
[The approved textual UI description from Phase 3 Step 0. Treat as authoritative visual intent — match it exactly. If it contradicts the plan, the UI Intent wins; stop and surface the contradiction.]

## Milestone Context (when milestone-mode — paste the milestone's `## Upstream Dependencies` section + the master plan's most recent `## Implementation Notes (Milestone <N-1>)` entry here; otherwise omit this section entirely)
[Upstream milestone summaries and non-obvious gotchas from prior milestones. Treat as authoritative context — do NOT re-derive what prior milestones already decided. If this contradicts the milestone's Files Affected table, the Files Affected table wins and you surface the contradiction.]

## Tests — MANDATORY (do not skip)
Write tests alongside your implementation. Every new source file MUST have a corresponding test file.
- Unit tests next to the source file for every new/changed service, function, or component
- Integration tests if touching data access, multi-service logic, or API endpoints
- Follow patterns from nearby existing test files. Extend existing specs — don't rewrite.
- Test file naming: match the project's convention (e.g., `foo.test.ts`, `foo.spec.ts`, `__tests__/foo.test.ts`)
- Test case naming: each test name and any comments inside the test describe the scenario, condition, or observable behavior under verification — never thread-local labels like `Bug A/B/C`, `Hypothesis 1/2`, `Test 1`, `Case X`, `Issue #N from this run`, `regression from review run`, `found by review-gate`, or `confirmed by this <skill> run`. Those labels are meaningless once the conversation that produced them ends; the test ships with the code and a future reader won't have that conversation.
- Minimum per source file: 1 happy path test + 2 edge case/error tests

## Verify Your Work
After implementation and tests are written, run these checks yourself:
1. Run the project's test command — all tests must pass (new and existing)
2. Run the project's lint/format command — fix any issues
3. Run the project's build/typecheck command — must compile cleanly
If any check fails, fix the issue and re-run. Do not report success with failing checks.

After all checks pass, include this structured section at the end of your response:

## Checks Report
- build: PASS|FAIL [error summary if fail]
- lint: PASS|FAIL [error summary if fail]
- test: PASS|FAIL [error summary if fail]
- typecheck: PASS|FAIL|SKIP [error summary if fail]

## Requirements
- Follow project conventions as documented in the Codebase Conventions section above
- Do NOT run git add/commit/push — the orchestrator handles git
- Do NOT modify files outside your WU scope: [list files]
- Do NOT add abstractions, wrappers, or patterns not present in the exemplar files — a separate simplification pass handles code quality
- Report: files changed, **test files created**, what was done, test results, checks report, any issues encountered

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
```

---

## Phase 4: Error Handling

| Error | Recovery |
|-------|----------|
| Agent produces non-compiling code | Forward raw error output to fixer agent — do NOT diagnose or read source files yourself |
| Agent creates a file not in the milestone's Files Affected table (milestone-mode) | Revert that file, re-run agent with explicit scope constraint: "Files Affected table is the hard boundary; if the milestone is missing a file, STOP and report back — do NOT add it." |
| Agent modifies files outside its WU scope | Revert those changes, re-run agent with stricter scope constraint |
| Agent ignores conventions | Re-spawn agent with exemplar files pre-inlined and stricter convention instructions |
| Agent timeout or garbage output | **RETRY:** re-dispatch with enriched context (add error details, relevant files, conventions). If retry fails: **DECOMPOSE** the WU into smaller sub-tasks. If still failing: **PRUNE** — revert WU, mark BLOCKED, continue to next WU |

**Blocked WU handling:** When a WU is marked BLOCKED, commit successful WUs from the wave, defer WUs that depend on the blocked one, continue independent WUs in the next wave. Present all blocked WUs to user after independent work completes.

---

## Phase 5: Simplify Agent Template

Spawn a **general-purpose** subagent with `model="sonnet"` and the simplify criteria. Sonnet is sufficient for cleanup work that follows explicit criteria — opus-level reasoning is unnecessary here. Pre-read the criteria file and the changed file list, then delegate:

```markdown
## Task: Simplify Changed Files

You are a code simplifier. Review the changed files and make them cleaner, simpler, and more consistent — without changing behavior.

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

## Criteria
[Pre-inline the contents of `${CLAUDE_PLUGIN_ROOT}/skills/deep-simplify/simplify-criteria.md` AND `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` here — read both first, paste them in. The audit defines the procedure Pass A's reuse work depends on.]

## Changed Files
[List the files changed by implementation, from git diff --name-only]

## Pipeline
1. Read each changed file + its immediate neighbors for context
2. Run three analysis passes (Reuse, Quality, Efficiency) from the criteria
3. Classify findings as P1/P2/P3
4. Apply P1 and P2 fixes. Skip P3 (report only).
5. Report what was changed using the Completion Report format from the criteria
6. Run the project's autofix command (lint --fix / format) per CLAUDE.md, then run build + lint + test. Capture pass/fail per command. Emit a `## Checks Report` block at the END of your return with the format:
   ```
   ## Checks Report
   - autofix: PASS|FAIL [error summary if FAIL]
   - build: PASS|FAIL [error summary if FAIL]
   - lint: PASS|FAIL [error summary if FAIL]
   - test: PASS|FAIL [error summary if FAIL]
   ```
   Do NOT skip this step. The orchestrator's Phase 6 Stage A cache rule depends on this report.

## Requirements
- Zero behavior change — preserve exact inputs, outputs, side effects
- Do NOT run git add/commit/push
- Do NOT modify files outside the changed file list (unless extracting a shared utility)
- Never delete or weaken test assertions
- Report: files modified, fixes applied, P3 notes
- Emit `## Checks Report` per Step 6 — without it, Phase 6 Stage A re-runs build/lint/test redundantly
- If your edits break tests/lint/build, do NOT mask the failure — report FAIL honestly. The orchestrator will revert your changes; that is the safe, correct outcome.

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
```

---

## Phase 6: Stage A — Automated Checks Detail

Before running checks, inspect implementation agent reports for `## Checks Report` sections. The cache fires (skip Steps 1–2 below — proceed directly to Step 3 codegen check) when ALL of the following hold: (a) every Phase 4 implementation agent reported PASS for build, lint, and test; (b) if Phase 5 simplify-agent ran, it ALSO reported PASS for autofix, build, lint, and test in its Checks Report (the simplify pass is now a Checks-Report producer per the Phase 5 template above); (c) no code was modified AFTER the last reporting agent (no fixer agent touched code, no orchestrator hotspot edits since). If any of the three conditions fails — any FAIL, any missing Checks Report, or any later code mutation — run all checks below.

If checks need to run: delegate the **fix** to an implementer agent — do not fix code yourself.

1. **Autofix:** Run lint/format fix commands from CLAUDE.md. Attempt auto-fixable issues first.

2. **Full check:** Run build + lint + test using the backpressure wrapper:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh"
   run_silent "Build" "<build_cmd>"
   run_silent "Lint" "<lint_cmd>"
   run_silent "Tests" "<test_cmd>"
   ```
   Use commands from CLAUDE.md's Essential Commands section. If backpressure.sh is not available, run commands directly but pipe passing output to /dev/null and capture only stderr + exit code.

3. **Codegen check** (if applicable — GraphQL, OpenAPI, proto, DTO/controller changes):
   - Run codegen command from CLAUDE.md (if configured)
   - Ensure no diff on committed files
   - If DTOs/controllers changed, regenerate API client and re-run full check

4. **Runtime startup check:** Boot the app, wait 15 seconds, check for DI/compilation/runtime errors that static checks miss, then kill the process.
   - Use a non-conflicting port (offset from default dev port)
   - Check stderr/stdout for dependency injection failures, missing providers, env validation crashes
   - Kill process once verified

**If any check fails:** forward raw error output to a fixer agent. Re-run failed checks after fix. If still failing after 2 attempts, continue to Stage B and include failures in the review context — the reviewers may identify the root cause.

---

## Phase 6: Stage B — Spec Compliance Agent Template

Spawn a **general-purpose** subagent with `model="sonnet"` to verify spec compliance. The orchestrator does NOT read source files to check requirements — delegate it.

```markdown
## Task: Verify Spec Compliance

Check whether the implementation matches the spec requirements.

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

## Spec
[Pre-inline contents of <task-dir>/spec.md]

## Plan
[Pre-inline contents of <task-dir>/plan-<slug>.md]

## Changed Files
[List files from git diff --name-only]

## Instructions
1. For each requirement in the spec, read the implementation files and verify:
   - The file listed in the plan exists and contains the expected logic
   - API signatures match the spec contracts
   - Edge cases from the spec have corresponding test cases
2. For each acceptance criterion in Definition of Done, verify it passes
3. Produce a compliance report: requirement -> PASS/FAIL with evidence (file:line)
4. Write your report to `<task-dir>/compliance.md`

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
```

Read `<task-dir>/compliance.md` after the agent completes. If ANY requirement is unmet -> spawn a fixer agent with the specific gaps and affected files pre-inlined. Do NOT read source files, diagnose gaps, or apply fixes yourself — delegate to the agent. Do NOT proceed to Stage C until gaps are resolved.
- **Max 2 rounds.** After round 1 failure, spawn a fresh fixer agent. After round 2 failure: if gaps are in <=3 requirements, present to user with option to ship with documented gaps. If gaps are systemic (>3 requirements), escalate to Phase 2 re-architecture.

---

## Phase 6: Stage C — Code Quality Reviewers

Only reached after Stage B passes.

1. **Collect context:** Capture the changed file list (`git diff --name-only <base>...HEAD` where <base> resolves per skills/_shared/scope-anchor.md rule 3), read all changed files, build a summary of what changed and why.

2. **Load review criteria:** Pre-read these criteria files from `${CLAUDE_PLUGIN_ROOT}/skills/review/`:
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md` — logic errors, null checks, off-by-one, state issues
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/security-criteria.md` — injection, auth/authz, secrets, crypto
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/architecture-criteria.md` — design patterns, modularity, coupling
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md` — coverage gaps, missing edge cases, test quality
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/guidelines-criteria.md` — style, naming, documentation, compliance
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/conventions-criteria.md` — codebase-pattern conformance via modal-pattern inference (sample siblings, flag deviations from ≥80% modal)
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/design-criteria.md` (conditional — only when changed files include UI per the UI-file detection rule in `skills/review/SKILL.md`)

3. **Spawn 6 or 7 parallel reviewer agents** (6 always, +1 design when UI files are in the changed-files list — see UI-file detection rule in `skills/review/SKILL.md`) in ONE response — all Agent() calls in the same assistant turn, NOT one per turn — each with `subagent_type: "reviewer-agent"`:

   | Agent | Model | Criteria File | Focus |
   |-------|-------|--------------|-------|
   | 1 | `sonnet` | bugs-criteria.md | Logic errors, null checks, off-by-one, state issues |
   | 2 | `sonnet` | security-criteria.md | Injection, auth/authz, secrets, validation |
   | 3 | `sonnet` | architecture-criteria.md | Patterns, modularity, coupling |
   | 4 | `sonnet` | tests-criteria.md | Coverage gaps, edge cases, test quality |
   | 5 | `haiku` | guidelines-criteria.md | Style, naming, documentation |
   | 6 | `sonnet` | conventions-criteria.md | Codebase-pattern conformance via modal-pattern inference (sample siblings, flag deviations from ≥80% modal) |
   | 7 | `sonnet` | design-criteria.md (conditional) | Visual quality: tokens, spacing/type scale, state completeness, WCAG AA, responsive, exemplar drift |

   Row 7 fires only when at least one changed file is a UI file (see detection rule in `skills/review/SKILL.md`). The Model column is authoritative — pass it as `model="..."` at each spawn; the `reviewer-agent` frontmatter default is `sonnet` and the spawn-time value overrides it.

   Each reviewer gets:
   - Its criteria file content (pre-inlined — one dimension per agent, no cross-reviewing)
   - All changed file contents (pre-inlined)
   - spec file + plan file for context
   - Previous feedback (if round 2+)
   - Instruction: produce confidence-scored findings (Critical/High/Medium)

   For large diffs (>8 files or >400 LOC): split files into batches of ~5, spawn reviewers per batch x dimension. Skip irrelevant dimensions per batch (e.g., test-only batch skips security).

4. **Aggregate findings:** Collect all reviewer outputs. Deduplicate findings that appear in multiple reviewers. Drop findings scored Medium by the reviewer (informational only).

5. **Relevance evidence + orchestrator tagging:** Spawn a `relevance-filter-agent` to gather evidence per CRITICAL/HIGH finding, then **you (the orchestrator) decide KEEP vs FILTER yourself** from the dossier — do NOT delegate the tagging decision:

   ```
   Agent(subagent_type="relevance-filter-agent", model="inherit", prompt="""
   WORKTREE: [from `git rev-parse --show-toplevel`]
   BRANCH: [from `git branch --show-current`]
   FINDINGS: [aggregated CRITICAL/HIGH findings from all reviewers]
   CHANGED FILES: [list of changed file paths — the agent reads files itself]
   PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
   CONVENTION FILES: [content of CONTRIBUTING.md, ADRs, architecture docs if they exist]

   Gather evidence for each finding against this repo's actual patterns:
   1. Convention alignment — does the suggestion match how this repo already works?
   2. Over-engineering — is this YAGNI for this repo's complexity level?
   3. Intentional pattern — does the flagged "problem" exist in 3+ other files intentionally?

   Return an evidence dossier per finding (ALIGNS/CONTRADICTS/NEUTRAL, APPROPRIATE/OVER-ENGINEERED, ISOLATED/WIDESPREAD, safety_override for CRITICAL findings). Do NOT tag findings KEEP or FILTER — return evidence only; the orchestrator decides.

   Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
   """)
   ```

   After the dossier returns, synthesize it yourself: weigh evidence against severity and tag each finding KEEP or FILTER. CRITICAL findings (safety_override=true) are always KEEP. Only KEEP findings proceed to the fix loop. If the agent fails, pass all findings through as KEEP (fail-open).

6. **Output:** Write `<task-dir>/review-feedback.md` with KEEP findings by file and severity. For each `[PRODUCT-DECISION]` finding, preserve the reviewer-agent's `Options:` sub-list verbatim AND the body sub-fields `evidence:`, `why-matters:`, `suggested-fix:` (copied from the reviewer-agent's `Evidence:` / `Why this matters:` / `Suggested fix:` fields) — the Fix Loop Pre-step below reads all of these to populate `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate, where the body sub-fields render in each option's `preview`. The persisted shape mirrors `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 5 per-finding line schema. Note FILTERED findings separately for transparency.

---

## Phase 6: Fix Loop (max 3 rounds)

After Stage C produces findings:

1. **Pre-step — Open-decision gate (Always-WAIT).** Before spawning the fixer, scan `<task-dir>/review-feedback.md` for any KEEP finding with `decision: PRODUCT-DECISION`. For each such finding, fire `AskUserQuestion` per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate (set `header: "Open decision"`). Read the finding's `Options:` sub-list AND the body sub-fields (`evidence:`, `why-matters:`, `suggested-fix:`) from `<task-dir>/review-feedback.md` per the schema preserved by Phase 4 Step 6 above — the body fields populate `preview` per option so the user can actually exercise judgment. Replace the finding's free-text `recommendation:` with the user's chosen option text in the file before continuing; preserve `options:` / `evidence:` / `why-matters:` / `suggested-fix:` as audit trail. Use the chained-AUQ pattern when >4 options exist (see `skills/review/SKILL.md` Phase 6 "Failing tests" block). This gate is **Always-WAIT** in every mode (see §Auto Mode Behavior, `[PRODUCT-DECISION] finding encountered` row) — empty answer = upstream bug, fall back to plain text and re-ask. Skip this pre-step only when zero PRODUCT-DECISION findings remain after Phase 4 judge filtering.

2. **Spawn a NEW fixer agent** (same agent type as the original WU — e.g., `backend-agent`). Do NOT reuse the original Phase 4 agent instance — it no longer exists and its context was full of implementation reasoning. A fresh agent with targeted context is more effective. Provide:
   - The specific review findings from `<task-dir>/review-feedback.md` (only CRITICAL/HIGH items, with PRODUCT-DECISION findings now carrying user-chosen `recommendation:` from the pre-step above)
   - Current file contents (pre-inlined — the code as it exists NOW, not as it was planned)
   - Spec file and conventions brief for reference
   - Instruction: "Fix these specific issues. Do NOT refactor beyond what's needed to resolve each finding."
   - The agents read CLAUDE.md at runtime for project context — no separate context injection needed.

3. **Re-run Stage A** (autofix + full check + codegen if schema changed).

4. **Spawn FRESH reviewer agents** for re-review in ONE response — all Agent() calls in the same assistant turn, NOT one per turn. Never reuse previous reviewer instances (anchoring bias: reviewers anchor to their prior findings instead of evaluating code as-is). Only re-review dimensions that had CRITICAL/HIGH findings in the previous round (saves tokens). For each dimension that had findings:

   ```
   Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
   WORKTREE: [from `git rev-parse --show-toplevel`]
   BRANCH: [from `git branch --show-current`]
   DIMENSION: [bugs|security|architecture|tests|guidelines|conventions|design]
   CRITERIA (pre-inlined): [content of <dimension>-criteria.md]
   CHANGED FILES (with full contents, pre-inlined): [list each file path followed by its current content AFTER the fix round — NOT the pre-fix version]
   DIFF CONTEXT: [paste `git diff <base>...HEAD` output reflecting the post-fix state where <base> resolves per skills/_shared/scope-anchor.md rule 3 (origin/HEAD's target, falling back to local main/master)]
   PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
   PREVIOUS ROUND FINDINGS: [paste the CRITICAL/HIGH findings from the prior reviewer output for this dimension — so you can verify whether each was actually resolved, not just moved]
   Review ONLY for [dimension]. For each prior-round finding, tag: RESOLVED / PARTIALLY-RESOLVED / NOT-RESOLVED / REGRESSED. Also report any NEW findings introduced by the fix round.

   Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
   """, description="Re-review: [dimension]")
   ```

5. If the same error persists across 2+ rounds with no progress -> escalate to re-architecture (Phase 2) with failure context

6. **After 3 rounds:** Stop iterating. Present a structured handoff:
   - List what was fixed vs. what remains
   - Classify remaining issues: spec gap (-> needs re-architecture) vs. code quality (-> `/geniro:follow-up` later)
   - Use the `AskUserQuestion` tool (do NOT output options as plain text) to present: A) Ship as-is with known issues documented, B) Re-run Phase 2 (re-architect the approach), C) Create `/geniro:follow-up` tasks for remaining items

**Scope constraints (anti-rationalization):**
- Reviews must stay in-scope (code exists, not feature creep)
- Reject "while we're here" refactoring
- Flag out-of-scope suggestions as "nice-to-have only"
- No moving goalposts (review against original spec file)

---

## Phase 6: Stage D — Adversarial Edge-Case Tests

Only reached after the Stage C Fix Loop exits cleanly (zero remaining CRITICAL/HIGH findings). Skip Stage D entirely when the Stage C Fix Loop exhausted its 3-round cap and the user chose to ship with known issues — authoring more red tests into a ship-as-is decision is user-hostile. Log "Stage D skipped — Stage C Fix Loop exhausted with user-accepted known issues" to `<task-dir>/state.md`.

**Spawn template:**

```
Agent(subagent_type="adversarial-tester-agent", model="inherit", prompt="""
## Task: Adversarial Edge-Case Test Authoring

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

### Diff (changed files + contents)
[Pre-inline `git diff <base>...HEAD` output AND full contents of every changed source file, where <base> resolves per skills/_shared/scope-anchor.md rule 3 (origin/HEAD's target, falling back to local main/master)]

### Shared Edge-Case Checklist (READ this file yourself at runtime — do NOT paste here)
`${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`

### Project Test Framework
- Test command (from CLAUDE.md Essential Commands): [e.g. `pnpm test`, `pytest`, `go test ./...`]
- Test-file naming convention: [from project — e.g. `*.test.ts` adjacent to source, `__tests__/`, `*_test.go`]
- Exemplar test files (1-2, pre-inlined): [closest existing test files to the changed code]

### Hypothesis Seeds (optional)
[Paste CRITICAL/HIGH findings from Stage C tests-dimension reviewer — if any. Use as seeds, not substitutes for independent hypothesis generation.]

### Output
Write your report to `<task-dir>/adversarial-tests.md`. Authored test files go to the project's normal test paths (adjacent to source or in the project test dir). Do NOT git add/commit/push.

### F→P Invariant (NON-NEGOTIABLE)
Every test you keep MUST fail 3 times in a row on the current code. If it passes, delete the test and mark the hypothesis `discarded-cannot-repro`. Flaky = discard.

### Scope
Diff-only. Do NOT author tests for files outside the changed-files list.

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""", description="Adversarial tests: edge-case hunt")
```

**Orchestrator synthesis after the agent returns:**

1. **Read `<task-dir>/adversarial-tests.md`.** Extract the authored test file paths.
2. **Independent re-verification.** Run the project's test command on each authored test file individually. Record: 3 consecutive failures with identical error = keep; anything else = delete the file and remove from scope.
3. **Append to `<task-dir>/review-feedback.md`.** For each kept test, add a CRITICAL or HIGH entry (severity per the agent's report) with the test file path, targeted source, and failure output. Mark these entries with `origin: stage-d-adversarial` so the Fix Loop distinguishes them.
4. **Run a dedicated Stage D Fix Loop.** If any kept tests exist, spawn a fresh fixer agent whose Definition of Done is "every stage-d-adversarial test passes AND existing tests still pass." Max 2 rounds (dedicated to Stage D, separate from Stage C's 3-round cap that already ran to clean exit). After 2 rounds, present remaining red tests to the user via `AskUserQuestion` (always-WAIT — see §Auto Mode Behavior): A) Ship with documented red tests as known issues, B) Escalate to `/geniro:follow-up` for the remaining fixes.
5. **Overflow.** If the agent report says it hit the 10-test hard cap, append overflow hypotheses (title + category only) to `<task-dir>/notes.md` under `## Stage D deferred` for surfacing in Phase 7 Step 4 "Deferred ideas".

**Fallback:**
- If the adversarial-tester-agent fails (timeout, garbage output), retry ONCE with the same prompt. If the retry also fails, skip Stage D, write "Stage D skipped — adversarial-tester-agent unavailable after retry" to `<task-dir>/state.md`, and continue to Phase 7. Do NOT block shipping on agent infrastructure failures.

**Scope constraints:**
- Diff-only — never author tests for untouched code paths even if the agent suggests them
- Test files only — if the agent somehow edited production code, revert those files and re-spawn with stricter scope instruction
- No flake tolerance — 3/3 deterministic failures is the F→P bar; nothing softer counts

---

## Phase 6: Error Handling

| Error | Recovery |
|-------|----------|
| Build/lint/test fails | Delegate fix to implementer, re-run Stage A |
| Codegen diff | Update generated files, re-run full check |
| Startup fails | Return to Phase 4 with DI/runtime error details |
| Spec gap found | Spawn fixer agent with gap details and affected files pre-inlined |
| Review finds critical bug | Agent fixes, re-run Stage A, re-review |
| Review too subjective | Focus on: bugs, coverage, architecture alignment |
| Fix rounds exceed 3 | Surface to user with current state, ask: proceed or iterate? |
| Adversarial test cannot be made to fail (F→P violation) | Delete the test, mark hypothesis `discarded-cannot-repro`, continue — do not weaken test to force failure |

---

## Phase 7: Finalize Steps Detail

### Update Docs

Check whether existing documentation needs updating based on what was implemented. **Skip if nothing changed that affects documented surfaces.**

Scan the diff against main and check:
- Do any existing docs reference patterns/files that were renamed, moved, or superseded?
- Did this implementation introduce a new pattern that should be documented as a canonical example?
- Do README, architecture docs, or contributing guides need patches?

If updates needed, delegate to a subagent (e.g., general-purpose with `model="haiku"`) with the diff summary and the doc files to patch. Keep changes minimal and focused — patch what's stale or add a new reference, don't rewrite docs. If no docs need updating, skip silently.

### Extract Learnings

Follow the canonical rubric in `skills/_shared/learnings-extraction.md`. Bias hard toward flow, architectural, and recurring-mistake learnings; do NOT save narrow interface/field shapes, single-file behaviors, or facts re-derivable by reading the code. Apply the Reflect → Abstract → Generalize pre-pass before every save: if you cannot restate the finding one level up, drop it.

Save the generalized form to `.geniro/knowledge/learnings.jsonl` and/or memory (route per the canonical's "Storage routing" section). Write a session summary to `.geniro/knowledge/sessions/YYYY-MM-DD-<feature-name>.md` with: summary, key decisions, discoveries, files changed, unresolved items.

UPDATE existing entries rather than append duplicates. Skip the entire step if nothing genuinely novel was discovered — empty extraction is the correct outcome for routine sessions.

### Suggest Improvements (project scope only)

Follow the canonical routing in `skills/_shared/improvement-routing.md` — it owns the routing table, decision logic, and presentation pattern. Skip findings already captured in Extract Learnings (Step 2); this step focuses on **structural improvements** (where the project records the rule) rather than knowledge capture.

### Pre-Ship Visual Verification

Runs only when BOTH conditions hold: (a) the Phase 7 Step 4 "Files changed" list contains at least one file matching the UI-file detection rule (`skills/review/SKILL.md` §UI-file detection rule), AND (b) Playwright MCP is available — check that `mcp__plugin_playwright_playwright__browser_navigate` is in your tool list. If Playwright MCP is NOT available, skip this entire section and note in the Phase 7 report: "Pre-Ship Visual Verification skipped — Playwright MCP not installed. Install the `playwright` marketplace plugin to enable smoke-tests." Do not attempt the steps below without the MCP; the tool calls will fail and the pipeline will stall.

When both conditions hold, prompt the user via a STANDALONE `AskUserQuestion` with header "Smoke-test" as the only question in that call — never batch it with Step 5's Ship Decision question. If the user picks "Yes — walk through it", execute this sequence:

1. **Detect target URL.** Probe dev-server ports in order — 3000 (Next.js), 5173 (Vite), 8080 (generic), 4321 (Astro), 4200 (Angular) — via `curl -s -o /dev/null -w "%{http_code}" http://localhost:PORT`. On the first 200, fetch `/` and check the response `<title>` or a known marker matches the project's `package.json` `name`; if it doesn't, or you're uncertain, `AskUserQuestion` "Detected server on :PORT — is this the project under test?" before navigating. If no port responds, walk up from the primary changed UI file to the nearest `package.json` containing a `dev`/`start`/`serve` script (monorepo layouts: `apps/<name>/package.json`, `packages/<name>/package.json`) — spawn from that directory, not the repo root, so `turbo`/`nx`/`pnpm -w` orchestrators don't misfire. Choose the package manager by lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb` → bun, else npm). Run with `run_in_background: true`, record the PID, and poll `GET /` until 200 or 30s timeout. On timeout, report the failure and ask the user "Skip verification" / "Retry" / "Enter URL manually".

2. **Infer the target route.** Map the primary changed UI file to a URL path: `app/<segment>/page.tsx` → `/<segment>`, `pages/<name>.tsx` → `/<name>`, `src/routes/<name>/+page.svelte` → `/<name>`. If the changed file is a leaf component (e.g., `components/Button.tsx`), fall back to `/` and ask the user where it renders. Navigate with `mcp__plugin_playwright_playwright__browser_navigate`.

3. **Baseline snapshot.** Call `mcp__plugin_playwright_playwright__browser_snapshot` to capture the accessibility tree with element refs. Every subsequent interaction (`browser_click`, `browser_type`, `browser_fill_form`) requires a `ref` from this snapshot — without one, the tool errors.

4. **Console + network sanity check.** Call `mcp__plugin_playwright_playwright__browser_console_messages` — treat any `error`-level entry as a failure worth reporting. Call `mcp__plugin_playwright_playwright__browser_network_requests` — flag same-origin 4xx/5xx responses. Re-run after step 5 and step 6.

5. **Targeted interaction.** Using refs from step 3, perform 1-3 actions that exercise the specific behavior changed in this pipeline (not a generic site tour). Cap at 5 total interactions to stay scoped to the diff. Re-snapshot after each to get fresh refs.

6. **Responsive sweep** — only when the diff includes any `.css`/`.scss`/`.sass`/`.less`/`.styled.*` file, OR a JSX/TSX hunk that touches `className`, `style`, or a CSS-module import. Call `mcp__plugin_playwright_playwright__browser_resize` to `{width: 375, height: 667}` (mobile) then `{width: 1280, height: 800}` (desktop). Snapshot each. Skip entirely for pure logic changes.

7. **Visual record.** Final `mcp__plugin_playwright_playwright__browser_take_screenshot` with `fullPage: true`, saved under `<task-dir>/playwright-verify.png`. This is the artifact — do NOT claim a pixel-diff against a prior state (no baseline image exists).

8. **Cleanup.** If step 1 spawned a dev server (you recorded a PID), send `kill -TERM <pid>`; if still alive after 3s, escalate with `kill -KILL <pid>`. Never kill servers the user had running before verification — only clean up what this step spawned.

**Reporting:** Summarize in 3-5 lines — interaction result, console/network status, responsive issues (if swept), screenshot path. If issues were found, route via `AskUserQuestion`: "Fix and re-verify" (loop back through Phase 7 Step 6 Small tweak path — this section re-fires after Step 4 if UI files remain in the diff), "Ship anyway with noted issues" (append to `<task-dir>/state.md` and proceed to Step 5), or "Abort" (stop pipeline; keep the task dir intact for the next session).

### Commit

Execute the user's chosen ship method:
- **Commit + PR**: Stage relevant files, `git commit` with conventional message (e.g., `feat(auth): add OAuth login [ENG-123]`). If a workflow file specifies commit message format (e.g., appending issue ID), follow that format. `git push origin [branch]`, then `gh pr create` with summary — append `--draft` when the user picked "Draft PR" in the follow-up "PR state" prompt, otherwise create as ready for review. Include task ID in PR title. `--draft` is incompatible with `--web` (gh CLI rejects the combination); if the user wants the PR in a browser, create first and then run `gh pr view --web`.
- **Commit + push**: Same commit, then `git push origin [branch]`
- **Commit only**: Stage relevant files, `git commit` with conventional message. Include doc updates, learning files, and improvement changes in the commit.
- **Leave uncommitted**: `git add` changed files only, skip commit

### Integration Updates

**Worktree:** If working in a worktree (from Phase 1 Step 10 option C), leave the session in it. Do NOT call `ExitWorktree` — the tool's contract is "do not call proactively, only when the user asks", and the runtime already prompts on session exit to keep or remove the worktree. After a "leave uncommitted" ship choice, tell the user the uncommitted changes remain at `.claude/worktrees/<name>/`. If the user later asks to exit the worktree, that is when `ExitWorktree` is invoked — outside this skill's flow.

**Integrations:** If workflow files in `.geniro/workflow/` specify completion actions (status transitions, PR linking, comments), follow their instructions. Always ask the user before changing external state (issue status, comments). Never auto-update. If integration backend is unavailable, log warning and skip (non-blocking).

**AI-disclosure prefix on authored tracker comments:** When the workflow file contains an `## AI-Disclosure Prefix` section (Linear template ships with one; setup-generated stubs include it as a TODO section), apply the documented prefix to any comment text the skill AUTHORS before posting via the tracker MCP. Status-only updates (e.g., transitioning state without a comment body), assignee-only updates, commit messages, and PR descriptions are excluded per the section's exclusion list. If the workflow file's AI-Disclosure section is still a TODO stub (no concrete prefix string filled in), skip authoring comments entirely — post only status-only updates — and report the missing configuration to the user once at the end of Phase 7 Step 8.

### Cleanup

Run cleanup directly (no agent needed):

**Pipeline artifacts** — remove the task directory and all its contents:
```bash
rm -rf <task-dir>  # e.g., .geniro/planning/feat-eng-123-add-oauth/
```
This deletes `spec.md`, `state.md`, `notes.md`, `notes-resolved.md`, `concerns.md`, `review-feedback.md`, `plan-*.md`, and any other files created during the pipeline. These artifacts served their purpose during the pipeline run — the commit message, PR description, learnings file, and session summary are the durable records.

**Temp files** — remove temporary screenshots, .tmp, .bak, debug-* files (not in node_modules or .git). Kill orphaned processes on agent ports (avoid touching standard dev ports). Remove stray .log files.

If any command fails silently, that's fine — cleanup is best-effort.

---

## Phase 7 Step 8: Milestone Status Update (milestone-mode)

Milestone status update (milestone-mode only): If this run executed a single milestone (Phase 2 pre-check rule 1 matched):

1. Update the milestone file's Status header from `in-progress` to `completed`.
2. Update the master plan's `## Milestones` section table: change the milestone's row Status to `completed`.
3. Update `state.md` `Milestones:` field to reflect the new status.
4. Append an `## Implementation Notes (Milestone <N>)` subsection to the master plan file containing: 3-8 bullet summary of non-obvious gotchas discovered, patterns to reuse, convention decisions worth propagating to later milestones. This is pre-inlined by the next milestone's Phase 2 run. Skip if nothing non-obvious was discovered — empty implementation notes are worse than none.
5. If more milestones are `pending`, use the `AskUserQuestion` tool (do NOT output options as plain text): "Milestone <N> shipped. How to proceed?" with options A) "Continue to milestone <N+1> now" — print the `/geniro:implement milestone <N+1>` command for the user to re-invoke (skills cannot call skills), B) "Compact first, then continue" — tell the user to type `/compact` then `/geniro:implement continue`, C) "Stop for now — resume later with `/geniro:implement continue`". In auto-mode, default to B: fresh context per milestone is the entire point — treat the compact recommendation as auto-approved and print the resume command. See implement-reference.md §Auto Mode Behavior row "Next-milestone prompt".
6. Do NOT append `Pipeline: COMPLETE` to state.md if milestones remain — that sentinel is only written after the LAST milestone (enforced by the conditional State bullet above).

---

## Phase 7 Step 6: Adjustment Routing (Big / Medium / Small)

### Big — changes to data model, API contract, new endpoints

1. Write tweak description to `<task-dir>/notes.md`
2. Rewrite `state.md`: keep only Phase 1 checkpoint, remove all Phase 2, 3, 4, 5, 6 markers. Add `Tweak round: N (Big) — [description]`
3. Update existing `plan-<slug>.md` via architect-agent with tweak context (do NOT create a new plan file)
4. Full pipeline re-entry: Phase 2 (architect revision + skeptic) → Phase 3 (re-approval) → Phase 4 (implement delta only) → Phase 5 (simplify) → Phase 6 (all stages) → Phase 7 Step 4 summary re-presentation

### Medium — new logic, additional fields

1. Write tweak description to `<task-dir>/notes.md`
2. Update `state.md`: add `Tweak round: N (Medium) — [description]`
3. Spawn implementer agent with tweak context + affected files pre-inlined
4. Re-run Phase 6 Stage A (build + test + lint)
5. Re-run Phase 6 Stage B (spec compliance) with tweak description as context
6. Re-run Phase 6 Stage C with fresh reviewer agents
7. Loop to Step 4 summary re-presentation

### Small — styling, typo, logic tweak

1. Write tweak description to `<task-dir>/notes.md`
2. Update `state.md`: add `Tweak round: N (Small) — [description]`
3. Spawn implementer agent with tweak context
4. Re-run Phase 6 Stage A (build + test + lint)
5. Loop to Step 4 summary re-presentation

**Loop target:** After any tweak, loop back to **Step 4 summary re-presentation only**. Steps 1-3 (docs, learnings, improvements) run once on first entry to Phase 7 and are NOT repeated on tweak rounds.

**Soft limits (by size):**
- **Big tweaks:** After 2 rounds, suggest starting a new `/geniro:implement` session. Big tweaks compound risk — a fresh pipeline provides clean context and proper architecture review.
- **Medium/Small tweaks:** After 3 rounds, suggest `/geniro:follow-up` for remaining changes.

---

## Phase 2: Milestone Reference Detection

**Milestone reference (highest priority)** — detect a request to implement a single milestone from a decomposed plan:
- `$ARGUMENTS` matches `^milestone\s+(\d+)\b` (e.g., `/geniro:implement milestone 2`) — glob `<task-dir>/milestone-<N>-*.md` where N is the captured digit. If exactly one matches, load it.
- `$ARGUMENTS` references a path ending in `milestone-<N>-*.md` — load that file directly.
- `$ARGUMENTS` is `continue` AND `<task-dir>/state.md` contains a `Milestones:` field — pick the first milestone with status `pending` or `in-progress` and load its file.

If a milestone file loads, also load the master plan (`<task-dir>/plan-<slug>.md`) for its Goal + Approach + Implementation Notes. The master plan's per-step details are NOT pre-inlined — only the milestone file is authoritative for what to execute. Skip architect-agent. Set mode flag `milestone-mode: true` for Phase 4 scope constraint (only files listed in the milestone's Files Affected table may change). Run skeptic-agent on the milestone file (skeptic pre-inlines the master plan and prior-milestone Implementation Notes for context). Proceed to Phase 3 with the milestone's Goal as the presented summary.

**HITL/AFK Mode tag → Lane translation (milestone-mode only):** Read the milestone file's status header for the `Mode:` field with value HITL or AFK (set by `/geniro:decompose` per `decompose-criteria.md` HITL/AFK Mode classification). Note the field-name collision: the milestone file's `Mode: HITL|AFK` is a *risk-tier* field (set by decompose author), distinct from state.md's `Mode: interactive|auto|assumptions` which is an *interaction-mode* field (set by Phase 1 Step 1 Mode Selection). The translation below maps from the former to the latter. If milestone-file Mode is absent, fall back to reading the master plan's `## Milestones` table row. Apply this translation BEFORE Phase 1 Step 0:
- `Mode: AFK` (milestone-file) → set `Lane: light` and `Mode: auto` (state.md) in state.md, write `Phase 1 Step 0: skipped — milestone (AFK -> light)`. The Phase 1 Step 0 Complexity Gate AskUserQuestion is BYPASSED.
- `Mode: HITL` (milestone-file) → set `Lane: full` and `Mode: interactive` (state.md) in state.md, write `Phase 1 Step 0: skipped — milestone (HITL -> full)`. Phase 1 Step 0 Complexity Gate is BYPASSED.
- `Mode:` field missing AND no master-plan row → fall back to running Phase 1 Step 0 normally (treat as un-decomposed task). This preserves backwards compatibility with milestone files written before the HITL/AFK Mode tag existed.

**Always-WAIT reconciliation:** The Phase 1 Step 1 Mode-Selection prompt is documented as Always-WAIT — MUST fire `AskUserQuestion` regardless of harness auto-mode signals. The HITL/AFK translation BYPASSES this prompt because the user already authorized the interaction mode upstream at `/geniro:decompose` Phase 5 Approval (the user picked "Approve all milestones (Mode tags as shown)" or used "Adjust" to flip Mode tags before approving — both are explicit AskUserQuestion confirmations). This is the same reconciliation principle as plan-mode resume: when an upstream skill captured the user's authorization via AskUserQuestion, the downstream skill consumes it instead of re-asking. The bypass is logged in state.md (`Phase 1 Step 0: skipped — milestone (HITL -> full)`) so the audit trail records that Phase 1 Step 0/1 fired upstream rather than silently auto-defaulting.

This translation is the contract `/geniro:decompose` and `/geniro:implement` agreed on at HITL/AFK introduction: decompose-time judgment about per-milestone risk drives execution-time Lane selection. The user can still override at the Phase 3 plan-approval gate (the plan presentation surfaces the resolved Lane); HITL milestones cannot be silently downgraded by `$ARGUMENTS` auto signals.

**`continue` parser format:** state.md `Milestones:` lines after Wave 2 carry per-entry Mode suffixes (`1: pending (AFK), 2: pending (HITL)`). The `continue` selector matches against the status word (`pending` / `in-progress`) — substring match is sufficient; the `(AFK)` / `(HITL)` suffix is parsed separately by the translation above. Pre-Wave-2 state.md without suffixes parses correctly via the same substring rule, preserving backwards compatibility.

---

## Definition of Done

Feature implementation is complete when:
- [ ] spec file written and user-approved
- [ ] Plan file written to `<task-dir>/` and skeptic-validated
- [ ] Implementation plan presented and user-approved (Phase 3)
- [ ] Simplification pass completed (or skipped with reason)
- [ ] All code compiles/builds without errors
- [ ] All tests pass (100% pass rate, coverage maintained/improved)
- [ ] Linter passes (zero warnings)
- [ ] Codegen check passes (if applicable)
- [ ] Runtime startup check passes
- [ ] Review complete (<=3 fix rounds)
- [ ] User approves for commit
- [ ] Learnings extracted and saved
- [ ] Plugin improvements applied (if found) or noted in summary
- [ ] Code committed (with message referencing feature and task ID if applicable)
- [ ] FEATURES.md row moved to `done` (only if `/implement` was invoked with a Geniro feature ID — the `Feature:` field in state.md is set)
- [ ] Code pushed to remote (if requested)
- [ ] Integration actions offered to user per workflow files (if any) — never auto-updated
- [ ] Cleanup completed (temp files removed, orphaned processes killed)
