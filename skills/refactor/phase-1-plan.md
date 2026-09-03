# /geniro:refactor — Phase 1: plan

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/refactor/SKILL.md`. Read on entry to Phase 1, and again on any resumption of it, including after a compaction. The spine keeps the state machine, the loop invariants, the anti-rationalization table, the budgets, §Git constraint and the tool surface — this file carries the Steps. Bare `§1.M` refs below point at this file's own sub-sections; `§ <name>` refs name a section inside the cited helper, and a `Phase 2 §2.M` / `Phase 3 §3.M` ref points at the sibling phase file (`refactor/phase-2-apply.md` for Phase 2, `refactor/phase-3-verify.md` for Phase 3).

## Contents

- 1.1 Memory layer load (instructions / snapshot / learnings)
- 1.2 Scope discovery + baseline + coverage check
- 1.3 Tier classification (canonical effort-scaling)
- 1.4 Smell detection (orchestrator-inline — Medium+)
- 1.5 Orchestrator-side smell evidence — keep or filter each smell
- 1.6 Risk classification, plan build, and approval

---

## Phase 1 — plan

state.md `phase: plan`. Light by cost vs Phase 2 — a scope-discovery batch (Read + Grep) + 1 baseline validation run + orchestrator-inline smell detection (Medium+) + orchestrator-inline smell evidence (Medium+) + orchestrator plan-build.

Exits to Phase 2 only when: (a) baseline validation green, (b) tier classified, (c) hard signals checked, (d) smells identified (Medium+) + smell-evidence filtered (Medium+), (e) plan built and approved (HIGH-risk steps gated).

### 1.1 Memory layer load (instructions / snapshot / learnings)

On Phase 1 entry, in order:

1. **Refresh custom instructions** — `load-custom-instructions(SKILL_SLUG: refactor, LOAD_TIER: pipeline, MODE: refresh)` per Echo contract; the pipeline tier's load set is owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`.
2. **Refresh project snapshot** — `load-semantic(MODE: refresh, top-2 default)` — `_project.md` + `_CODEBASE_MAP.md`.
3. **Query past learnings** — `query-learnings(tags=<inferred from $ARGUMENTS>, scope=task path)` to find prior discoveries about coupling, pitfalls, and conventions relevant to the refactor scope — route per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (under a declared `## Memory Backend` block routing `learnings`, delegate the read to a scoped `knowledge-retrieval-agent` spawn — `SCOPE: learnings-backend` — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md` §3; no block → the inline file query runs unchanged). The agent declares a `Context loaded:` line; the empty-vs-unread reading rule is single-sourced at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md` §3.
4. **Cross-layer conflict resolution** — `resolve-conflicts` with all three layers loaded; precedence: custom instructions > project snapshot > past learnings when layers disagree; halt with AUQ on hard conflict. Echo lines from each loader are mandatory per its §Echo contract.
5. **Workflow refs read (when spec.md is in scope).** When `$ARGUMENTS` points to a spec.md path OR a planning task-dir, parse spec.md frontmatter `workflow_refs[]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md` — that file owns which schema versions a reader accepts and the rule that every consumer but /geniro:implement is tracker-read-only. Use the cached `status` field as scope-priming context — refactor scope decisions favor "still In Progress" specs (active editing area) over "Done" specs (stable code, smaller perturbation surface). The `m5-v3` cached parent-epic and sibling-sub-task statuses, when present, are a co-signal alongside §1.2's prior-work scan on the in-flight-sibling question: that scan's ticket probe finds unnamed tickets by keyword and, by design, never walks the known parent/sibling chain (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/prior-work-scan.md` §2), so a KNOWN in-flight sibling under the same epic surfaces only through this cached status. Skipped silently when no spec.md is in scope.
6. **Branch freshness.** On a fresh run (skip on compaction-resume), apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` — /geniro:refactor applies changes in place on the current branch, so if that branch is behind the default branch, offer to update it before scope discovery and baseline validation run against stale code. Skipped silently when the branch is already current.

### 1.2 Scope discovery + baseline + coverage check

1. **Parse `$ARGUMENTS`** to understand what is being refactored and why.
2. **Find all related files** with the project's code-search tooling (follow the project's search policy from `global.md` — reach for its code index when one is configured). Read all files in scope to understand current organization, dependencies, imports, and test coverage.
2.5. **Prior-work scan.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/prior-work-scan.md` against the refactor target parsed in step 1 and the scope files step 2 just found — already named, so this is the read-only carve-out `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` §Forbidden discovery moves draws around an already-named target, not target discovery. An open PR or ticket touching the same module is live evidence a sibling is in flight and argues for a smaller perturbation surface, ahead of tier classification (§1.3) and plan-build (§1.6) where that scope call is made. On a hit, §4 owns the gate shape; persist the pick under `category: prior_work_scan` via `atomic_state_append_list_item`.
3. **Prior-planning context.** Scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. Check: `.geniro/planning/*/` (task-local), workflow files (cwd-first, then `<PRIMARY_ROOT>/.geniro/workflow/*.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A), `<PRIMARY_ROOT>/.geniro/knowledge/learnings.jsonl` (search for scope-file keywords — a different query from §1.1's inferred-tag query, routed through the same memory-backend delegation), and git state (worktree root, current branch, recent commits, working-tree status).
4. **Read project convention files** referenced in CLAUDE.md.
5. **Baseline validation** — run the project's validation suite once (read command from CLAUDE.md). Capture as an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. Outcomes:
- **Red:** state.md → `phase: plan-escalated` via `atomic_state_set_field`, then `AskUserQuestion` header "Baseline" — "Fix the broken tests first (stop refactoring)" / "Proceed anyway — existing failures are out of scope (risky)". Default: stop. On "Fix the broken tests first (stop refactoring)": state.md → `phase: aborted` (terminal) via `atomic_state_write` with a `## Termination reason` line naming the red baseline, then run `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-3-verify.md` §3.7 Cleanup. On "Proceed anyway — existing failures are out of scope (risky)": state.md → `phase: plan`, note the accepted red baseline in `## Baseline`, and continue to step 6.
- **No tests exist:** escalate immediately — "Cannot refactor safely without tests. Use `/geniro:implement` to add coverage first." state.md → `phase: routed` (terminal).
- **Green:** record passing-state fingerprint (test count) in state.md `## Baseline` body section; proceed.
6. **Coverage check on the symbols in scope.** Check whether each function/symbol in scope has at least one test exercising it — the zero-behavior-change guarantee is only as strong as the tests locking current behavior. A gap is the "new tests required to cover untested code" hard signal in §1.3.2; carry it there rather than authoring the missing test here, because a test authored now would be a characterization test that passes on current code (not a test-first cycle), and §1.3.2 lets the user decide whether the symbol belongs in scope at all. If every scope-symbol already has coverage, skip silently.

### 1.3 Tier classification (canonical effort-scaling)

**Apply the canonical effort-scaling rubric** from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`: Step 1 (hard signals) → Step 2 (5-dim score) → Step 3 (tier behavior). Refactor-specific hard signals apply orthogonally — they escalate OUT of /geniro:refactor entirely.

#### 1.3.1 Apply canonical effort-scaling

1. **Steps 1-2 (canonical):** run the hard-escalation-signal check (Step 1) and the dimension score → tier band (Step 2) exactly as defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`. Any hard signal forces Big; otherwise the score band sets the tier (Trivial / Small / Medium / Big). effort-scaling.md is the single source — do not restate the signals, the dimension count, the score range, or the bands here.
2. **Step 3 (refactor-specific tier behavior):**

| Tier | Refactor behavior |
|---|---|
| **Trivial** | 1-2 files, mechanical (rename, single extract). Skip smell detection. Skip the smell-evidence filter. Skip independent reviewer + custom reviewers. Orchestrator authors the plan directly from $ARGUMENTS + scope-files Read; goes straight to Phase 2 execution. |
| **Small** | Skip smell detection and the smell-evidence filter (scope too narrow to matter). Skip independent reviewer + custom reviewers. |
| **Medium** | Full pipeline as specified — orchestrator-inline smell detection + orchestrator-inline smell evidence + reviewer-agent + custom reviewers. |
| **Big** | Recommend running `/geniro:plan` first to split the refactor into independently shippable milestones; refactor then runs one milestone at a time against an approved spec.md. If user wants to proceed without planning, require explicit confirmation via `AskUserQuestion` header "Scope": "Run /geniro:plan first" / "Proceed without a plan (risky)". On "Proceed without a plan", Big runs the Medium pipeline. The only difference is user has accepted the added risk of proceeding without architectural review. |

#### 1.3.2 Refactor-specific hard escalation signals (escalate OUT — orthogonal to effort-scaling)

These 4 refactor-specific signals are orthogonal to the canonical effort-scaling tier. Any present → state.md `phase: plan-escalated` via `atomic_state_set_field`, then escalation AUQ "Scope" — "Escalate to suggested skill" / "Proceed anyway (treat as Big)" / "Reduce scope". Default: Escalate. On "Escalate" pick → state.md `phase: routed` (terminal). On "Proceed anyway (treat as Big)" → state.md `phase: plan`, continue §1.3.1's Big-tier pipeline. On "Reduce scope" → drop the flagged item from scope (or narrow `$ARGUMENTS`), state.md `phase: plan`, and re-run scope discovery (§1.2) from step 1.

| Signal | Routing target |
|---|---|
| Behavioral change required | `/geniro:implement` |
| New tests required to cover untested code | `/geniro:implement` |
| Test assertions touched (not just imports) | Not refactoring — `/geniro:implement` |
| Auth, crypto, or payment code touched | Escalate (owner review required) — surface to user, not auto-route |

### 1.4 Smell detection (orchestrator-inline — Medium+)

Skipped for Trivial and Small per Step 3.

The orchestrator runs the 6 smell detection categories, the Named smell baseline, the Helper Placement rule, and the Deepening Opportunities lens inline — no subagent spawn, for the state-continuity reason spelled out at Phase 2 §2.2. For wide cross-file locator queries that would otherwise require many inline Reads (e.g., "find all definitions of the duplicated helper across the repo"), spawn `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research. The smell-evidence pass itself stays orchestrator-inline so state continuity and the per-step regression-skip predicate are preserved.

**Reference:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` § Code Smell Detection — full smell taxonomy + change-impact scoring + escalation rules. Bound by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`: Read it before the step that needs it and echo it. It is the sole home of the Data Safety Rule (no `DROP TABLE` / `TRUNCATE` / volume removal during a refactor) and of the test-file approval gate — and `/geniro:refactor` runs those phases orchestrator-inline, so no injected agent body carries them and no hook covers the commands they name. The orchestrator reads this file once at entry and applies the rubric inline.

**Per-smell procedure:**

1. Apply the 6 smell categories (duplication / long methods / god classes / dead code / tight coupling / type+import issues) via Read + the project's code-search tooling against the FILES IN SCOPE from Phase 1 §1.2.
2. Match the scope files against the **Named smell baseline** in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` § Code Smell Detection — the named smells (Feature Envy, Shotgun Surgery, Primitive Obsession, and the rest of that list) that fall outside the 6 categories above.
3. Apply the **Helper Placement** rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` § Helper Placement — flag an extracted helper sitting away from its one non-test call site without clearing one of the three bars (Rule of Three, hidden complexity callers need not know, a tested seam).
4. Apply the Deepening Opportunities lens — read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/architecture-vocabulary.md` first for vocabulary grounding, then scan for wide-interface shallow modules / pass-through wrappers / repeated cross-call orchestration / high-leverage shallow code.
5. For every detected smell, run the canonical **Existing Abstraction Audit** at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` — apply its Procedure (search designated helper directories, categorize REUSE-AS-IS / EXTEND / NO-ANALOGUE, force-fit guard, Rule of Three). Emit candidates inline alongside each smell using the audit's Output format. A NO-ANALOGUE result is where the plan would hand-extract a new shared helper. Before that, check the smell's domain against the trigger-domain list and severity guidance in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/library-reuse-audit.md` § MODE: review — canonical there, not restated here — substituting the smell's domain for that mode's diff-scoped trigger, since Phase 1 plans against no diff. On a match, write the maintained-library category (or `none found`) straight into the smell's `library_reuse` field: refactor borrows only that domain check and severity reasoning, never the mode's reviewer-agent output contract, so no `[PRODUCT-DECISION]` tag, `Options:` block, candidate research, install, manifest entry, gate, or routing to `/geniro:implement` applies.
6. Count consumers per smell with the project's code-search tooling (a code index returns dependents directly when configured; otherwise a count-mode structured search), scoped by language (`*.ts` / `*.py` / etc).
7. Public-surface guard: flag smells that change public API signature, module export, or shared type — these are HIGH-risk regardless of consumer count.

Output (write directly to state.md `## Smells Detected`):

```yaml
smells:
- id: s-001
category: duplication
file_lines: <file:line references>
proposed_transformation: <mechanical description>
consumer_count: <int>
files_affected: <bounded list>
public_surface: <true|false>
abstraction_audit: <REUSE-AS-IS|EXTEND|NO-ANALOGUE — per audit output>
library_reuse: <omit unless abstraction_audit is NO-ANALOGUE and the smell's domain matches the trigger-domain list in library-reuse-audit.md § MODE: review; when it matches, the matched library category, or `none found`>
optimization_evidence: <omit for every category other than premature-optimization; for that category, the three-way search result for profiler/benchmark data, an identified hot path, and a stated performance budget — each stated present or absent, per the smell's own evidence requirement in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` § Code Smell Detection>
```

Risk classification (LOW / MEDIUM / HIGH) and ordering happen in §1.6 (orchestrator decisions, not the smell-detector's job).

Anchor: stay within WORKTREE on BRANCH — orchestrator verifies with `pwd && git branch --show-current` once at entry; abort if either differs.

### 1.5 Orchestrator-side smell evidence — keep or filter each smell

Skipped for Trivial and Small. The orchestrator gathers evidence on detected smells against repo conventions inline — no subagent spawn: light synthesis that fits the orchestrator's own context cleanly does not need one, since a spawn's only payoff here would be isolation the work does not need.

For each smell detected in §1.4, the orchestrator weighs three signals inline:

1. **Convention alignment** — is this "smell" actually the repo's chosen pattern? Cross-check with CONTRIBUTING.md, ADRs at `docs/adr/`, architecture docs (when present) and CLAUDE.md.
2. **Over-engineering** — would fixing this smell introduce more complexity than it removes? Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` mental check.
3. **Intentional pattern** — does the flagged pattern exist deliberately in 3+ other files? A quick search over similar paths confirms.

Synthesis matrix per smell:

| Convention | Complexity | Frequency | Decision |
|---|---|---|---|
| ALIGNS | * | * | FILTER (repo's chosen pattern) |
| CONTRADICTS | OVER-ENGINEERED | * | FILTER (cure worse than disease) |
| CONTRADICTS | APPROPRIATE | WIDESPREAD | ASK USER (ambiguous — house pattern or entrenched debt) |
| CONTRADICTS | APPROPRIATE | ISOLATED | KEEP (genuine smell) |
| NEUTRAL | APPROPRIATE | ISOLATED | KEEP (default) |

KEEP smells enter plan-build. FILTERED smells are noted in state.md `## Filtered smells` section with the synthesis reason. No fail-open caveat needed — dedup and judgment run in orchestrator's main context.

The ASK USER row is the one the matrix can't resolve alone: appropriate + contradicts convention + widespread reads equally as a deliberate house pattern or as debt nobody caught, and only the user knows which. When ≥1 smell lands there — the other four rows still resolve silently — render each to chat first (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering: name the pattern, how many files it spans, and the ambiguity), then fire ONE multi-select `AskUserQuestion` (header: "Intentional?", § Multi-select pick loop, chaining past 4 matches): the user picks which are real debt to KEEP — the rest FILTER as intentional. Persisted picks land in `## Filtered smells` / feed KEEP smells into plan-build same as any other row.

### 1.6 Risk classification, plan build, and approval

Orchestrator builds the plan from the smell-evidence inline output (Medium+) or directly from scope-files (Trivial/Small):

1. **Classify risk per smell** using the consumer-count table in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` § "Step 2: Change Impact Scoring" (public API / module export / shared-type change is HIGH regardless of consumer count).
2. **Order the plan**: safer transformations first (LOW → MEDIUM → HIGH). Within the same tier, group by file to minimize re-reads.
3. **Mark HIGH-risk steps for user confirmation** (gated via the approval gate below).
4. **Build the final plan** with: smells, ordered steps, risk per step, consumer counts, files that will change, what will NOT change (public APIs, DB schema, test behavior), `max_risk` (max across all step risks).

**Approval gate (Always-WAIT):** If any steps are **HIGH risk**, gate them in two steps — render first, then ask — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering (separate-message rule, render-exists check), with the pre-fire scrub per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` § Single-finding gate, "Scrub before the AUQ fires", using the elements from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` § Visual rendering language:

1. **Render the HIGH-risk step plan to ONE chat message first.** Skip the progress tracker — this is a single gate, not a decision queue. Open with `**In one sentence:**` stating what is being approved (the higher-risk transformations in this refactor plan, before any edit runs). Then, with a light icon on each heading:
   - **Steps flow diagram** over the FULL ordered plan (`step 1 ▸ step 2 ▸ step 3 …`), HIGH-risk steps marked (e.g. `⚠ step 3`), so the user sees where the gated steps sit in the run.
   - **Per HIGH-risk step, a friendly digest block:** a lead sentence describing the transformation in plain words; `**Why it matters:**` naming how many places depend on the code being moved and what would break if the move is wrong; and the expected behavior-preservation check — which test run proves the step changed nothing observable. Then that step's `**Technical detail:**` block with the file, the symbol, and the evidence cite (`path:lines`), per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers.
   - **Per HIGH-risk step, the risk mini-table:** risk · symptom you'd see · severity (the "Refactor step set" row of per-finding-question-reference.md § Finding-type visual map).
2. **Then fire ONE lean `AskUserQuestion`** (header "Approve HIGH-risk steps", conventions per gate-rendering.md § Lean-question conventions) and wait for confirmation: approve all HIGH-risk steps, or reject specific steps (rejected steps are skipped in Phase 2; on that pick, run a follow-up multi-select picker over the HIGH-risk steps per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Multi-select pick loop). One question covers the whole HIGH-risk set; per-step grain lives in `approvals[]`, not in extra questions.

**Approvals-persistence:** before firing, check state.md frontmatter `approvals[]` for prior entries with `category: refactor_high_step` matching the current step. Use prior `picked` if found. On user pick, append one entry per HIGH-risk step the pick covers via `atomic_state_append_list_item` — per-step grain unchanged even though one question covers the set. The persisted-approvals render surfaces these on resume.

If all steps are LOW/MEDIUM: present the plan summary in chat and proceed (no AUQ).

state.md transitions: `plan` → `apply` once approval complete. `## Plan` body section with full plan; `## Persisted approvals` rendered from `approvals[]`.
