---
name: geniro:refactor
description: "Use when restructuring code for better organization or reducing tech debt while guaranteeing zero behavior change. M8 3-phase loop (Plan → Apply → Verify) mirroring /implement. Adopts canonical effort-scaling tier rubric (Trivial / Small / Medium / Big). NEVER ships code — diff is the deliverable, working tree is the channel. For behavioral changes use /geniro:implement; for performance optimizations use /geniro:review --simplify."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite]
argument-hint: "[what to refactor and why]"
---

# Refactor with Test Verification (M8)

Safe incremental refactoring that validates behavior is preserved at every step. Restructures code для better organization, reduces tech debt, и improves patterns без changing observable behavior. Pre-M8 5+1-phase workflow collapsed к 3 phases mirroring `/geniro:implement` per master plan §120.

**Architecture spec:** `architecture/M8-refactor-redesign.md`. Detailed contracts:
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` — canonical tier rubric (Trivial / Small / Medium / Big) adopted per M8 §6.3 Q2
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` — smell-detection sub-step per M8 §6.4
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate — PRODUCT-DECISION escalation per M8 §8.3
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` § ADR template — М8 §8.3 ADR-path (4th AUQ option when ADR-eligible)

**Section-reference convention:** plain `§1.x` / `§2.x` / `§3.x` references в this SKILL.md point к local sub-sections (Phase 1, Phase 2, Phase 3 respectively). References к the architecture spec are explicitly prefixed `M8 §X.Y` (e.g. `M8 §6.8`). The architecture spec uses §6/§7/§8 for the same three phases; the SKILL.md mirrors М6/М7 local-numbering convention для readability.

---

## Your Role — Restructure, Don't Ship

You refactor. You validate behavior preservation. You do NOT commit или push the diff. Phase 3 endpoint is а working-tree diff (the deliverable) + а chat completion summary + state.md audit trail. Downstream actors (user `git commit`, `/geniro:implement` to ship through review gate) handle the actual ship.

The constitutional rule (zero behavior change) is enforced per-step via the refactor-agent's regression test gate AND post-execution via the final regression run (§2.4). PRODUCT-DECISION findings ALWAYS escalate (§3.3) — picking one resolution path is а behavior change.

---

## When to use

- Extracting shared logic from multiple modules
- Restructuring а module for clarity или testability
- Consolidating similar patterns across files
- Reducing coupling between components
- Improving module organization within а package

## When NOT to use

- For behavioral changes или feature additions (use `/geniro:implement`)
- To optimize performance (use `/geniro:review --simplify` и measure first — M6 absorbed /deep-simplify as а flag)
- To add error handling not previously present (behavioral change → `/geniro:implement`)
- To reorganize без clear architectural benefit

---

## State Machine (M8 §2.1)

state.md `phase:` enum transitions:

```
[entry] → plan ──┬── apply ──┬── verify ──┬── done
                 │           │             │
                 │           │             └── verify-summary-only (terminal — "Document and ship as-is" path)
                 │           │
                 │           └── apply-escalated ──┬── verify (keep what worked → partial-application note)
                 │                                 ├── reverted (terminal — "Revert all changes")
                 │                                 └── aborted (terminal)
                 │
                 └── plan-escalated ──┬── plan (user supplies missing context)
                                      ├── aborted (terminal)
                                      └── routed (terminal — hard signal "Escalate")

                 verify ──┬── (happy: → done above)
                          │
                          └── verify-escalated ──┬── apply ("Run /implement" on PRODUCT-DECISION → exit /refactor)
                                                 ├── reverted (terminal — "Revert this refactor")
                                                 ├── done ("Document and ship as-is" → done с deferred-decision note)
                                                 └── adr-documented (terminal — "Document as ADR")
```

**Terminal states:** `done`, `verify-summary-only`, `reverted`, `aborted`, `routed`, `adr-documented`. M3 SessionStart recovery treats all six as «task complete — no resume needed».

**Non-terminal states:** `plan`, `apply`, `verify`. M3 recovery rolls these back к phase-entry и re-runs (idempotent — `approvals[]` ensures HIGH-step + PRODUCT-DECISION gates skip already-answered).

**Escalation states:** `plan-escalated` (hard signal OR baseline red), `apply-escalated` (≥30% blocked), `verify-escalated` (PRODUCT-DECISION или 1-round fix-loop exhausted). M3 surfaces к user as "task was paused — last AUQ options:" so user re-picks без losing context.

**Termination-case mapping** per M8 §2.1.1 — see architecture spec для the 8-row table. The `## Termination reason` body section is written on `aborted` / `reverted` / `routed` terminals.

---

## Loop Invariants (M8 §2.2)

M4 §2.2's 7 invariants apply unchanged. Three M8-specific notes:

1. **Invariant #4 (bounded structured tool results)** — refactor-agent's structured execution report (per-step status, blocked-step reasons) capped at ~8K chars; longer truncated с marker.
2. **Invariant #5 (escalation gates, not silent abort)** — §2.3 ≥30% blocked AUQ + §3.3 PRODUCT-DECISION always-WAIT.
3. **Invariant #7 (errors → structured observations)** — refactor-agent per-step blocked rationale, baseline validation failure, и reviewer CRITICAL findings all become structured `## Tool log` / `## Errors` entries.

`## Tool log` schema: typical run produces 3-6 entries (refactor-agent Phase 1 evidence + relevance-filter + refactor-agent Phase 2 execution + reviewer-agent + custom reviewers + escalation entries).

---

## Budgets — Quality-First (M8 §2.3)

M8 has **NO hard kill caps**. Same model as M4 / M5 / M6 / M7.

**Quality gates (escalate к user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Per-step retry в refactor-agent | 3 | §2.2 (agent-internal) | Mark BLOCKED, continue к next step |
| Session-level blocked ratio | 30% (post-rejection denominator) | §2.3 | AUQ — keep what worked & escalate / revert / force-continue. User picks. |
| Phase 3 fix-loop | 1 round | §3.3 | Re-spawn reviewer once; if still failing, AUQ (escalate / accept / abort). |
| Reviewer output size | ~4K chars per dim | §2.2 invariant #4 | Truncation с marker. |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| Parallel reviewer spawns | 1 independent + N custom reviewers | §3.2 |
| Smell-detection rounds | 1 (refactor-agent evidence-only) | §1.4 |
| Relevance-filter rounds | 1 (Medium+ only) | §1.5 |

**Explicitly NOT capped:** wall-time, total tool calls, total model turns, total cost. Same rationale as M4 §2.3.

---

## Subagent Model Tiering

Follow the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly. For plugin-defined subagents (refactor, relevance-filter, reviewer), also follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (registration ladder: `geniro-claude-plugin:<agent>` → bare `<agent>` → `general-purpose` с body inlined). Cache the resolved rung для the rest of the session.

Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site — every Agent() prompt MUST satisfy the six pre-inlined fields.

**Skill-specific mapping** — refactor work is mostly mechanical pattern application; Sonnet handles ~90% of cases:

| Spawn | Tier | When |
|---|---|---|
| `refactor-agent` (LOW or MEDIUM risk) | `sonnet` | Default — pattern application, file moves, rename, extract method |
| `refactor-agent` (HIGH risk) | `opus` | `plan.max_risk == "HIGH"` (15+ files OR cross-module architectural restructure OR public API surface changes) |
| `relevance-filter-agent` | `inherit` | Orchestrator-grade reasoning to weigh repo-convention evidence against detected smells |
| Independent reviewer-agent + custom reviewers | `sonnet` | Phase 3 §3.2 diff review (Medium+ tier only) |
| Focused ADR-drafting agent | `sonnet` | §3.3 ADR path (only fires если ADR-eligible PRODUCT-DECISION) |

## Agent Failure Handling

If any delegated agent fails (timeout, error, empty/garbage result): retry once с the same prompt. If the retry also fails:
- **Phase 1 evidence-gathering agents (refactor-agent §1.4, relevance-filter-agent §1.5):** proceed без the failed agent's output; note "Agent [name] failed — [dimension] not available" в §3.4 completion summary, и offer user the choice via `AskUserQuestion` header "Partial evidence": "Abort refactor" / "Continue с partial evidence (risky)". Default: Abort.
- **Phase 2 execution agent (refactor-agent §2.2):** do NOT silently skip — revert all changes (`git checkout -- .` с user confirmation per §3.1) и escalate к user с failure context.
- **Phase 3 reviewer-agent (§3.2):** note the failure в the completion summary и proceed (fail-open); warn the user that independent review did not complete.

---

## Evidence Standard

Cite the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. М8 applies it at §1.2 baseline validation, §2.2 per-step regression gate (within the refactor-agent), и §2.4 final regression run.

---

## Universal Rule: All Choice Questions Use AskUserQuestion

Every user-facing choice в this skill MUST go through the `AskUserQuestion` tool per the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Universal AskUserQuestion Rule. The enumerated gates (§1.2 baseline, §1.3.3 Big-tier confirmation, §1.6 HIGH-step approval, §2.3 stuck cap, §2.4 regression-failure, §3.3 PRODUCT-DECISION escalation, §3.3 verify-fix) are examples, not an exhaustive list.

---

## Phase 1 — Plan

state.md `phase: plan`. Light by cost vs Phase 2 — а scope-discovery batch (Read + Grep) + 1 baseline validation run + 1 refactor-agent spawn (Medium+) + 1 relevance-filter spawn (Medium+) + orchestrator plan-build.

Exits к Phase 2 only when: (a) baseline validation green, (b) tier classified, (c) hard signals checked, (d) smells identified (Medium+) + relevance-filtered (Medium+), (e) plan built и approved (HIGH-risk steps gated).

### 1.1 Memory layer load (L4 / L3 / L2)

On Phase 1 entry, in order:

1. **L4 refresh** — `load-custom-instructions(MODE: refresh, scope: refactor + global + code-style + user-preferences — M10b pipeline tier, 4 files)` per M3 §7.2 Echo contract.
2. **L3 refresh** — `load-semantic(MODE: refresh, top-2 default)` — `_project.md` + `_CODEBASE_MAP.md`. Fingerprint drift check fires if applicable.
3. **L2 prior-knowledge query** — `query-learnings(tags=<inferred from $ARGUMENTS>, scope=task path)` per M2 §5.3. К find prior discoveries about coupling, pitfalls, и conventions relevant к the refactor scope.
4. **Cross-layer conflict resolution** — `resolve-conflicts(L2/L3/L4 loaded)` per M2 §10.

Echo lines per M3 §7.2 mandatory.

### 1.2 Scope discovery + baseline + Test-first gate

1. **Parse `$ARGUMENTS`** к understand what is being refactored и why.
2. **Use Grep + Glob** к find all related files. Read all files в scope к understand current organization, dependencies, imports, и test coverage.
3. **Prior-planning context.** Scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. Check: `.geniro/planning/*/` (task-local), `.geniro/workflow/*.md`, `<PRIMARY_ROOT>/.geniro/knowledge/learnings.jsonl` (grep для scope-file keywords), git state (`git rev-parse --show-toplevel`, `git branch --show-current`, `git log --oneline -5`, `git status --short`).
4. **Read project convention files** referenced в CLAUDE.md.
5. **Baseline validation** — run the project's validation suite once (read command from CLAUDE.md). Capture as an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. Outcomes:
   - **Red:** `AskUserQuestion` header "Baseline" — "Fix the broken tests first (stop refactoring)" / "Proceed anyway — existing failures are out of scope (risky)". Default: stop. state.md → `phase: plan-escalated`.
   - **No tests exist:** escalate immediately — "Cannot refactor safely без tests. Use `/geniro:implement` к add coverage first." state.md → `phase: routed` (terminal).
   - **Green:** record passing-state fingerprint (test count) в state.md `## Baseline` body section; proceed.
6. **Test-First Gate (behavior-adjacent coverage check).** Before any refactor edit, check whether each function/symbol in scope has at least one test exercising it. If а gap is detected, fire `${CLAUDE_PLUGIN_ROOT}/skills/_shared/test-first-gate.md` — author RED before refactor edit. If every scope-symbol already has coverage, skip silently.

### 1.3 Tier classification (canonical effort-scaling — Q2 closure)

**Adopt canonical effort-scaling.md rubric** (M8 §6.3). /refactor no longer overrides the canonical. Apply effort-scaling Step 1 (hard signals) → Step 2 (5-dim score) → Step 3 (tier behavior). Refactor-specific hard signals (§1.3.2) apply orthogonally — they escalate OUT of /refactor entirely.

#### 1.3.1 Apply canonical effort-scaling

1. **Step 1 (canonical 9 hard signals от effort-scaling.md):** new entity/table/migration, new API endpoint/route, auth/permissions/role changes, new module/subsystem, 3+ modules coordinated, OCP violation, new async/queue/background, new external integration/env vars, ambiguous intent. Any present → **Big tier**, skip к Step 3.
2. **Step 2 (canonical 5-dim score 0-10):** Task type / Cross-boundary scope / Reversibility / Edit scatter / Pattern availability. Score sum:
   - **0** → Trivial (must ALSO be 1-2 files, single module, unambiguous intent — otherwise round up к Small)
   - **1-3** → Small
   - **4-6** → Medium
   - **7+** → Big
3. **Step 3 (refactor-specific tier behavior):**

| Tier | Refactor behavior |
|---|---|
| **Trivial** | 1-2 files, mechanical (rename, single extract). Skip §1.4 smell-detection. Skip §1.5 relevance-filter. Skip §3.2 independent reviewer + custom reviewers. Orchestrator authors the plan directly от $ARGUMENTS + scope-files Read; goes straight к Phase 2 execution. |
| **Small** | Full smell-detection в §1.4 BUT skip §1.5 relevance-filter (scope too narrow к matter). Skip §3.2 independent reviewer + custom reviewers. |
| **Medium** | Full pipeline as specified — refactor-agent smell-detect + relevance-filter dossier + reviewer-agent + custom reviewers. |
| **Big** | Recommend running `/geniro:plan` first к split the refactor into independently shippable milestones; refactor then runs one milestone at а time against an approved spec.md. If user wants к proceed без planning, require explicit confirmation via `AskUserQuestion` header "Scope": "Run /geniro:plan first" / "Proceed без а plan (risky)". On "Proceed без а plan", Big runs the Medium pipeline. The only difference is user has accepted the added risk of proceeding без architectural review. |

#### 1.3.2 Refactor-specific hard escalation signals (escalate OUT — orthogonal к effort-scaling)

These 4 refactor-specific signals are orthogonal к the canonical effort-scaling tier. Any present → escalation AUQ "Scope" — "Escalate to suggested skill" / "Proceed anyway (treat as Big)" / "Reduce scope". Default: Escalate. On "Escalate" pick → state.md `phase: routed` (terminal).

| Signal | Routing target |
|---|---|
| Behavioral change required | `/geniro:implement` |
| New tests required к cover untested code | `/geniro:implement` |
| Test assertions touched (not just imports) | Not refactoring — `/geniro:implement` |
| Auth, crypto, или payment code touched | Escalate (owner review required) — surface к user, не auto-route |

### 1.4 Smell detection (refactor-agent evidence-only — Medium+)

Skipped для Trivial и Small per §1.3.1 Step 3.

Spawn а refactor-agent к detect smells и count consumers — evidence only. The orchestrator then classifies risk, orders the plan, и marks HIGH-risk steps for user confirmation.

```
Agent(subagent_type="refactor-agent", model="sonnet", prompt="""
You are analyzing code for refactoring. Your task:

WHAT TO REFACTOR: $ARGUMENTS

FILES IN SCOPE:
[list the files you read в Phase 1]

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

PROJECT CONVENTIONS:
[paste any relevant conventions from CLAUDE.md или project docs]

PHASE: EVIDENCE GATHERING ONLY.
- Execute ONLY your Phase 1 (Code Smell Detection). Skip all planning, risk scoring, и ordering.
- Skip Phase 2 (Refactoring Plan), Phase 3 (Atomic Application), и Phase 4 (Reporting) entirely.
- Do NOT use Write or Edit tools during this invocation. You are producing raw evidence, not а plan.
- Return smells + consumer counts as your final output.
- For every detected smell, also run the canonical **Existing Abstraction Audit** at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` — apply its Procedure (Grep designated helper directories, categorize REUSE-AS-IS / EXTEND / NO-ANALOGUE, force-fit guard, Rule of Three). Emit candidates inline alongside each smell using the audit's Output format.

Run all 6 smell detection categories (duplication, long methods, god classes, dead code, tight coupling, type/import issues) AND the Deepening Opportunities lens per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/architecture-vocabulary.md`. For each finding, count consumers с Grep.

Return as а flat list:
- Smell 1: [type, file:line references, proposed transformation, consumer count, files affected]
- Smell 2: ...
- Public surface notes: [smells that change public API signature, module export, или shared type — orchestrator will treat these as HIGH risk regardless of consumer count]

Do NOT classify risk (LOW/MEDIUM/HIGH). Do NOT order the smells. Do NOT flag steps for user confirmation. Those are orchestrator decisions.

Anchor: stay within WORKTREE on BRANCH — verify с `pwd && git branch --show-current` on first Bash call; abort if either differs.
""", description="Refactor analyze: $ARGUMENTS")
```

### 1.5 Relevance-filter dossier (Medium+) → orchestrator KEEP/FILTER

Skipped для Trivial и Small. Spawn а relevance-filter-agent к gather evidence on detected smells against repo conventions, then orchestrator decides KEEP vs FILTER:

```
Agent(subagent_type="relevance-filter-agent", model="inherit", prompt="""
FINDINGS: [smells detected by refactor-agent, с file:line references]
CHANGED FILES: [files в refactoring scope from §1.2]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
CONVENTION FILES: [content of CONTRIBUTING.md, ADRs, architecture docs if they exist]

Gather evidence для each detected smell against this repo's actual patterns:
1. Convention alignment — is this "smell" actually the repo's chosen pattern?
2. Over-engineering — would fixing this smell introduce more complexity than it removes?
3. Intentional pattern — does the flagged pattern exist deliberately в 3+ other files?

Return an evidence dossier per smell (ALIGNS/CONTRADICTS/NEUTRAL × APPROPRIATE/OVER-ENGINEERED × ISOLATED/WIDESPREAD). Do NOT tag smells KEEP или FILTER — return evidence only; the orchestrator decides.

Anchor: stay within WORKTREE on BRANCH — verify с `pwd && git branch --show-current` on first Bash call.
""", description="Relevance: refactor smells")
```

After dossier returns, orchestrator synthesizes: для each smell, weigh evidence и tag KEEP or FILTER. Remove FILTERED smells from plan; note в summary. If agent fails, pass all smells through as KEEP (fail-open).

### 1.6 Risk classification + plan build + approval AUQ

Orchestrator builds the plan from refactor-agent output (Medium+) или directly from scope-files (Trivial/Small):

1. **Classify risk per smell** (lookup):
   - 1-3 consumers → LOW
   - 4-9 consumers → MEDIUM
   - 10+ consumers → HIGH
   - Public API / module export / shared type change → HIGH (overrides consumer count)
2. **Order the plan**: safer transformations first (LOW → MEDIUM → HIGH). Within the same tier, group by file к minimize re-reads.
3. **Mark HIGH-risk steps для user confirmation** (presented via `AskUserQuestion`).
4. **Build the final plan** с: smells, ordered steps, risk per step, consumer counts, files that will change, what will NOT change (public APIs, DB schema, test behavior), `max_risk` (max across all step risks).

**Approval gate (Always-WAIT, P-M1-1-aware):** If any steps are **HIGH risk**, present them к user via `AskUserQuestion` header "Approve HIGH-risk steps" и wait для confirmation. Each step rendered с: file path / proposed transformation / consumer count / risk classification / rationale.

**Approvals-persistence (P-M1-1):** before firing, check state.md frontmatter `approvals[]` для prior entries с `category: refactor_high_step` matching the current step. Use prior `picked` if found. On user pick, append entries к `approvals[]` via M1 `atomic_state_write`. M3 §6 Block 5d renders on resume.

If all steps are LOW/MEDIUM: present the plan summary в chat и proceed (no AUQ).

state.md transitions: `plan` → `apply` once approval complete. `## Plan` body section с full plan; `## Persisted approvals` rendered from `approvals[]`.

---

## Phase 2 — Apply

state.md `phase: apply`. Refactor-agent executes the approved plan, one step at а time, с per-step validation. The zero-behavior-change constitutional rule is enforced via the per-step regression test pass.

### 2.1 L4 refresh entry

On Phase 2 entry, single `load-custom-instructions(MODE: refresh, scope: refactor + global + code-style + user-preferences — M10b pipeline tier, 4 files)` call. Mirrors M4 §13.4 Phase 3 entry contract. Pre-M8 had TWO refreshes (Phase 4 + Phase 5 entries) — M8 collapses к one; Phase 3 inherits the Phase 2 refresh (no code-writing в Phase 3).

### 2.2 refactor-agent execution

Spawn the refactor-agent к execute the approved plan. Model tier: `opus` if `plan.max_risk == "HIGH"`, else `sonnet`.

Pre-spawn step: use the content the §1.1 / §2.1 loader echoed as `Loaded code-style.md …` (cwd OR primary-worktree fallback per `load-custom-instructions.md`). Pre-inline content into agent prompt под `## Code-style instructions`. Omit когда loader echoed `No code-style.md found — skipping.`

```
Agent(subagent_type="refactor-agent", model="<sonnet|opus per risk>", prompt="""
You are executing а refactoring plan. Your task:

APPROVED PLAN:
[paste the plan from §1.6, marking any HIGH steps the user rejected]

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

PER-STEP TEST COMMAND: [<test_cmd_affected> from CLAUDE.md if defined, else <test_cmd>]
REGRESSION TEST COMMAND: [<test_cmd> from CLAUDE.md] — full suite; orchestrator runs this separately for §1.2 baseline / §2.4 final regression
AUTOFIX COMMAND: [autofix command from CLAUDE.md, if any]
BACKPRESSURE: source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Tests" "<validation_cmd>". If unavailable, pipe through tail -80.

## Code-style instructions (pre-inlined from `code-style.md` as loaded by §1.1 / §2.1 — cwd OR primary-worktree fallback per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`; omit когда loader echoed `No code-style.md found — skipping.`)
[paste content here, OR omit section when absent]

Execute each step following the Step Execution Protocol в your agent definition.

CRITICAL RULES:
- One logical transformation per step
- Run validation after each step
- If а step fails 3 times: REVERT it, mark as BLOCKED, и CONTINUE к the next step
- Do NOT stop the entire session because one step is blocked
- No git operations (no add, commit, push, checkout)

Return а structured report of what was applied, what was blocked, и final validation status.

Anchor: stay within WORKTREE on BRANCH — verify с `pwd && git branch --show-current` on first Bash call; abort if either differs.
""", description="Refactor execute: $ARGUMENTS")
```

### 2.3 Session-level cap + escalation AUQ

After execution returns, count BLOCKED-к-executed ratio (post-user-rejection denominator: approved plan steps minus user-rejected HIGH-risk steps). **If ≥30% BLOCKED:** stop и escalate via `AskUserQuestion` header "Stuck":

- **Keep what worked и escalate the rest** — proceed к Phase 3 с blocked-steps list noted; user runs `/geniro:implement` separately для blocked items. state.md → `phase: verify` с `## Accepted Blocks` body section.
- **Revert all changes** — `git checkout -- .` (с user confirmation per §3.1). state.md → `phase: reverted` (terminal).
- **Force-continue (not recommended)** — proceed к Phase 3 с blocked work treated as accepted. state.md → `phase: verify`.

Do NOT proceed к Phase 3 automatically когда this cap triggers. state.md marks `phase: apply-escalated` с timestamp + blocked-ratio + blocked-steps list before AUQ; transitions per user pick. М3 §6 Block 5c renders open question on resume.

### 2.4 Final regression run + Evidence Block

After execution returns (или after user pick if §2.3 fired), run the full test suite once (regression gate) и attach the captured run as an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. Reasoning-from-the-diff is forbidden — the captured run is the only proof the zero-behavior-change invariant held.

If regression failed: fire AUQ "Regression" — "Revert all changes" / "Show me the diff first" / "Keep changes для debugging". Default: Revert. On "Revert", `git checkout -- .` after explicit user confirmation. state.md → `phase: reverted` (terminal).

If green: state.md transitions к `phase: verify`. `## Apply Summary` body section captures executed / blocked / final-suite status.

**P-X8-3 L2 emit on retry exit.** When Phase 2 exits AND `blocked_count ≥ 2` (≥2 plan steps reported BLOCKED by refactor-agent, regardless of whether overall ratio triggered §2.3 escalation), call `emit-learning` с type=`retry_failure_sequence`, trust=`verified`, required `ext.{phase: "refactor-apply", attempts: [{round: <step-index>, failure: "<blocked-rationale от refactor-agent>"}], resolution}`. `resolution` ∈ `{passed, escalated, aborted}` — passed when §2.4 regression green AND <30% blocked; escalated when §2.3 fired AND user picked «Keep what worked» or «Force-continue»; aborted on reverted/aborted state. Sliding-window cap = 3 latest per `(producer, scope, phase)`. Single-blocked-step exits (blocked_count == 1) do NOT emit. Scope = the worktree-relative path of the largest-affected file.

---

## Phase 3 — Verify

state.md `phase: verify`. Diff sanity + independent review + completion summary + L2 emit + cleanup. No `git push` / `gh pr create` — refactor never ships code, only produces а working-tree diff (deliverable) и а state-file audit trail.

### 3.1 Diff sanity (all tiers)

Run `git diff --name-only` и `git diff --stat`. Cross-check the refactor-agent's self-reported file list (от §2.2 structured report) against the actual diff — flag mismatches.

If §2.4 final regression failed AND user picked "Revert all changes", state.md is already `phase: reverted` — skip к §3.7 cleanup (no review needed).

### 3.2 Independent reviewer-agent + custom reviewers (Medium+)

Skipped для Trivial и Small per §1.3.1 Step 3.

For Medium и Big: spawn а fresh reviewer-agent. The agent reads its own criteria — do NOT pre-read into orchestrator context.

Pre-inline content the loader echoed (§2.1 refresh): `code-style.md` content под `## Code-style instructions`. Omit когда loader echoed `No code-style.md found — skipping.`

```
Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
## Review: Refactor Diff
This is а refactor — behavior MUST be unchanged. CI already passed. Focus on invariants, not style.

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

DIFF: [paste git diff output]
AGENT SELF-REPORT: [refactor-agent's structured report]
PROJECT CONVENTIONS: [paste relevant conventions от CLAUDE.md]

## Code-style instructions
[content here]

## Focus Areas
- Accidental public-API changes
- Test assertion mutations (imports-only changes are fine; assertion changes are NOT)
- Invariant drift (error shapes, return types, null-vs-undefined, ordering)
- New coupling introduced by extraction/move
- Dead-code removal that actually had references

## Review Criteria
Read и apply these criteria files:
- `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/architecture-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`

Report findings с severity (CRITICAL/HIGH/MEDIUM) и confidence. Return findings as evidence. Do NOT emit an overall verdict — the orchestrating skill synthesizes findings и decides disposition.

Anchor: stay within WORKTREE on BRANCH — verify с `pwd && git branch --show-current` on first Bash call.
""", description="Review: refactor diff")
```

**Custom reviewers (Medium и Big only — same gate):** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` к discover user-authored review dimensions in `.geniro/instructions/review-extra/`. For each spawn-spec returned, append one additional `Agent(subagent_type="reviewer-agent", ...)` к the SAME parallel batch as the independent reviewer above — same assistant response, parallel execution. The helper's `paths:` filter uses the refactor's changed-files list. Custom-reviewer findings flow through the same orchestrator disposition logic as independent-reviewer findings. If the helper aborts on hard-cap error, surface error + skip §3.2; do not proceed с review.

### 3.3 Orchestrator disposition logic

**PRODUCT-DECISION findings → ESCALATE (Always-WAIT, every tier):**

А PRODUCT-DECISION finding implies multiple valid resolution paths, и refactor guarantees zero behavior change. Picking one is а behavior change, contradicting the constitution. Phase 3 ESCALATES PRODUCT-DECISION к `/geniro:implement`; does NOT gate-and-fix в-skill.

Surface every PRODUCT-DECISION finding via `AskUserQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate (`header: "Escalate"`). 4 fixed options (ADR-eligibility determines whether 4th option included):

1. **Run /geniro:implement on this finding (Recommended)** — exit /refactor; user runs /implement separately к apply а behavioral fix. state.md → `phase: verify-escalated` then on pick → exit (out-of-skill).
2. **Revert this refactor и start over** — `git checkout -- .` с user confirmation. state.md → `reverted` (terminal).
3. **Document и ship as-is — accept the open decision** — keep the working-tree diff, note the deferred decision in §3.4 completion summary. state.md → `verify-summary-only` (terminal). The user takes the responsibility of resolving the decision later.
4. **(ADR-eligible only)** **Document as ADR** — spawn а focused agent (`model: sonnet`) к draft the ADR per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` § ADR template; write to `docs/adr/NNNN-<slug>.md` (next sequential N; create directory if missing, after `AskUserQuestion` confirmation). state.md → `adr-documented` (terminal).

**ADR-eligibility check (before adding 4th option):** include the "Document as ADR" option ONLY когда the rejected refactor candidate meets all three criteria from `improvement-routing.md` § ADR target: (1) hard к reverse, (2) surprising без context, (3) result of genuine trade-offs. Examples that qualify: rejecting "split this god-class into 3 modules because the team prefers single-file feature ownership" (the *rejection* is the durable decision); rejecting "switch от inheritance к composition here because the existing inheritance is load-bearing для the plugin system." Examples that do NOT qualify: rejecting а duplicate-extraction smell because the duplication is intentional (Rule of Three not yet met) — that's а learning, not an ADR. If unsure, omit the ADR option; routing к Knowledge is always safe.

**Approvals-persistence (P-M1-1):** before firing the PRODUCT-DECISION AUQ, check state.md frontmatter `approvals[]` для а prior entry с `category: refactor_product_decision` matching the finding (use finding `path:lines` + decision-type as disambiguator). If found, use prior `picked` value. If not found, fire AUQ → on user pick, append к `approvals[]` via M1 `atomic_state_write` BEFORE executing the chosen action.

Fire one `AskUserQuestion` per PRODUCT-DECISION finding; chain across findings — never batch multiple findings into а single question.

**CRITICAL or HIGH (non-PRODUCT-DECISION) findings → fix loop (max 1 round):**

Spawn fresh refactor-agent к address specific findings, then re-spawn reviewer-agent fresh on the updated diff. After 1 round, если still failing — surface к user via AUQ header "Verify-fix" с options: "Escalate к /implement" / "Document remaining findings и ship as-is" / "Revert all changes". state.md → `verify-escalated` с timestamp + 1-round fix attempt summary.

**MEDIUM findings only → note в completion summary; proceed.**

**No findings → proceed.**

### 3.4 Completion summary

Output the markdown block directly в chat. No persistence к а T2 handoff file — diff IS the deliverable (M8 §9 D11-fix decision).

```markdown
## Refactor Complete

### Transformations Applied (N)
- [file:line] — [what changed] — risk: [LOW/MEDIUM/HIGH] — consumers: N

### Blocked Steps (N)
- [file:line] — [what was attempted] — reason: [failure summary]

### Filtered by Relevance (N — omit для Trivial/Small; relevance filter not run)
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
- [P3 item или user-rejected HIGH step]

### Next steps
[The diff is in your working tree. Commit it yourself, или run `/geniro:implement` к ship с а review gate.]
```

### 3.5 L2 auto-emit (M2 §5.3 — discovery + pitfall)

Replaces deleted `/learnings` skill (master plan §69). At Phase 3 exit:

- **`emit-learning` (M2 §5.2)** — called by /refactor для two emit types per M2 §5.3 canonical contract:
  - **`discovery`** — emit когда а pattern was extracted к а shared utility/component (typical /refactor outcome). Required `ext.{area, insight}` per M2 §5.2 typed-extension table. Default trust `verified` per M2 §5.3.
  - **`pitfall`** — emit когда the refactor revealed а footgun (a seemingly-safe pattern that actually breaks under specific conditions). Required `ext.{trap, mitigation}`. Default trust `verified`.
- **NOT emitted by M8:** `diagnosis` (/debug owns); `convention` (/implement self-review owns); `decision` (/plan owns).

**L4 promotion suggestion (P-M4-5 mirror — closes feedback loop):** когда а `discovery` или `pitfall` entry is emitted, surface а one-line suggestion в Phase 3 final report:

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

### 3.6 Suggest improvements (project scope only, M2 §5.4 routes)

After L2 emit, follow the canonical routing в `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md`. Refactor runs typically surface:

| Insight category | Target | M2 layer |
|---|---|---|
| Undocumented coding conventions / style patterns discovered during refactor | `.claude/rules/<scope>.md` с `paths:` glob frontmatter | L4 procedural |
| Surprising coupling between modules revealed during execution | `.geniro/knowledge/learnings.jsonl` (typically already covered by §3.5 discovery emit) | L2 episodic |
| Patterns that should be auto-enforced | Project rules/hooks (out of plugin scope — point user к project tooling) | — |
| Skill-behavior constraints the user enforced manually during refactor | `.geniro/instructions/refactor.md` или `.geniro/instructions/global.md` | L4 procedural |

Plugin-internal paths (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope.

### 3.7 Cleanup

After Phase 3 completes:

- **All tiers:** Remove `<PRIMARY_ROOT>/.geniro/state/refactor/<slug>/state.md` для the current branch's slug only, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract. Useful content already saved (transformations, discoveries) via §3.5 L2 emit + §3.4 chat summary. Do NOT delete sibling slugs от concurrent refactor sessions on other branches.
- **Clear three legacy generations** (best-effort; any may not exist):
  ```bash
  rm -f ".geniro/refactor/state.md"                    2>/dev/null  # Gen 1: original (pre-state-dir, non-scoped)
  rm -f ".geniro/refactor/state-${slug}.md"            2>/dev/null  # Gen 2: intermediate (pre-state-dir, slug-scoped)
  rm -f ".geniro/state/refactor/state-${slug}.md"      2>/dev/null  # Gen 3: pre-M8 (flat, under state-dir)
  ```
- **No T2 handoff к delete или persist** (M8 §9 D11-fix decision: diff IS the deliverable; working tree is the channel).
- Kill any background processes started during the run (test watchers, profilers).

Cleanup is best-effort — failed commands silently OK.

---

## State file schema (M1 §T1 base + M8 extensions — see M8 §9 для full schema)

### state.md (T1 — session-bound, `.geniro/state/refactor/<slug>/state.md`)

Frontmatter (M1 §T1 required + M8 extensions):

```yaml
---
tier: T1
producer: refactor
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: <enum per State Machine above>
status: <in-progress|done|failed>
non-resumable-actions: []                 # typically empty — refactor ships no commits
approvals: []                             # P-M1-1 — categories: refactor_high_step, refactor_product_decision
geniro_kind: refactor-state
geniro_schema_version: m8-v1
effort_tier: <Trivial|Small|Medium|Big>
task_slug: <slug>
worktree: <abs-path>
---
```

Body sections:
- `## Scope` — files + symbols в refactor scope
- `## Baseline` — Evidence Block от §1.2 step 5 (test count + pass status)
- `## Smells Detected` — (Medium+) refactor-agent output от §1.4
- `## Plan` — (after §1.6) ordered steps + risk + consumer counts + KEEP/FILTER decisions
- `## Apply Summary` — (after §2) executed / blocked / final-suite status
- `## Accepted Blocks` — (optional, §2.3 path "Keep what worked")
- `## Review Findings` — (Medium+, after §3.2) CRITICAL/HIGH/MEDIUM lists
- `## Persisted approvals` — M3 §6 Block 5d (render of frontmatter approvals[])
- `## Tool log` — M3 §6 selective logging (refactor-agent + relevance-filter + reviewer spawns, escalations)
- `## Errors` — M3 §6 Block 5b
- `## Open Questions` — M3 §6 Block 5c (escalation AUQs + outcome)
- `## Termination reason` — M3 §6 (only on terminal aborted/reverted/routed states)

**No T2 handoff** (M8 D11-fix): diff IS the deliverable; working tree is the channel.

---

## ACI per-phase tool surface (M8 §10.5)

**Phase 1 (Plan):**
- Allowed: Read / Grep / Glob / Bash (read-only — `git status`, `git log`, `git diff`, `git branch --show-current`, test suite invocation для baseline).
- Allowed Agent spawns: refactor-agent (evidence-only), relevance-filter-agent.
- Explicitly blocked: production-source Edit/Write, `git commit`, `git push`, `gh pr create`.

**Phase 2 (Apply):**
- Allowed Agent spawn: refactor-agent (execution).
- The refactor-agent itself uses Edit / Write / Bash (test cmd) per its agent definition. Orchestrator-level: monitor agent return, run final regression suite.
- Explicitly blocked at orchestrator level: `git add`, `git commit`, `git push`, `gh pr create`, branch switching.

**Phase 3 (Verify):**
- Allowed: Read / Grep / Glob / Bash (`git diff --name-only`, `git diff --stat`, test cmd для re-runs).
- Allowed Agent spawns: reviewer-agent + custom reviewers (Medium+ only), focused ADR-drafting agent (if PRODUCT-DECISION ADR path picked).
- Allowed: `git checkout -- .` (orchestration-level revert per §3.1 / §3.3 / §2.4) — exception к git-write constraint.
- Explicitly blocked: `git commit`, `git push`, `gh pr create`.

**All reviewer / custom reviewer spawns are pure read-only:** tool whitelist via `agents/reviewer-agent.md` frontmatter (Read / Grep / Glob / Bash для read-only checks).

**Existing safety layer** applies across ALL phases: file-protection hook, git-guardrail hook, `.geniro/` deletion guard. Runtime denies stay enforced.

---

## Memory I/O Schedule (M2 §13 obligation — M8 §10)

| Phase | Helper | Direction | MODE |
|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` |
| Phase 1 entry | `query-learnings` | read L2 | n/a (M2 §5.3 trigger) |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` (single re-fire — drops pre-M8 double-refresh) |
| Phase 3 exit (§3.5) | `emit-learning` | write L2 | n/a (emit types: `discovery` с `ext.{area, insight}` OR `pitfall` с `ext.{trap, mitigation}`) |

`update-semantic` writes к `_CODEBASE_MAP.md` для move/rename refactors (bounded auto-incremental per M2 §6.1). Not applicable когда refactor adds modules (would be а behavioral change → escalate per §1.3.2).

---

## Git Constraint

Do NOT run `git add`, `git commit`, или `git push`. The orchestrating workflow handles version control. Exception: `git checkout -- .` is permitted в §2.4 / §3.1 / §3.3 для reverting failed changes — this is an orchestration-level revert, not а version-control operation.

---

## Anti-rationalization (M8 §14 — P-MP-1 closure)

| Your reasoning | Why it's wrong |
|---|---|
| "This smell is too small к fix" | If the plan says fix it, fix it. Small smells compound. |
| "I'll batch multiple transformations" | One atomic transformation at а time. Always. |
| "Tests are passing so I'll skip the blocked step protocol" | The protocol exists для the NEXT failure. Follow it. |
| "This refactoring needs а behavior change" | Then it's not а refactoring. Use `/geniro:implement` instead. |
| "I'll skip reading project conventions" | You'll flag intentional patterns as smells. Read first. |
| "This duplication needs а new shared helper" | Run the Existing Abstraction Audit first. If а utility / service / hook already exists nearby that could absorb this duplication via а small extension, prefer extending it. Only create а new shared helper когда no analogue exists OR когда extending the existing one would require adding а parameter или conditional that complicates it (Rule of Three). |
| "All detected smells are real issues" | Generic smell categories flag intentional repo patterns. Без filtering against THIS repo's conventions, you'll refactor code that was designed that way on purpose. |
| "This is just а refactor" | Refactors break things. Tests и review apply equally. |
| "I'll spawn agents one at а time" | All parallel agents MUST be spawned в ONE response — multiple Agent() calls в the same assistant turn. Separate turns = no concurrency, full wall-clock latency per agent. |
| "The user said go fast — skip phases" | Phase skipping is tied к tier classification, not user impatience. Trivial/Small tiers already skip appropriately. |
| "I noticed а bug mid-refactor, I'll fix it" | That's feature work. Note it для `/geniro:implement` и stay в refactor scope. |
| "This change is obviously safe" | "Obviously safe" is the #1 predictor of broken builds. Run validation. |
| "I'll upgrade this sonnet spawn к opus just to be safe" | Model tier is task-nature-matched, not risk-appetite-matched. Re-classify via Subagent Model Tiering table; don't silently upsize. |
| "Reviewer flagged а `[PRODUCT-DECISION]` finding — I'll route it through the fix loop like any other CRITICAL/HIGH" | А `[PRODUCT-DECISION]` finding has multiple valid resolution paths by definition — picking one is а behavior change, which contradicts refactor's zero-behavior-change guarantee. §3.3 disposition logic ESCALATES PRODUCT-DECISION к `/geniro:implement` (always-WAIT) — never gates-and-fixes them в-skill. If you find yourself spawning the refactor-agent для а PRODUCT-DECISION finding, that's the rationalization. Stop и route the escalation. |
| "Add а wall-time kill cap so long-running refactor sessions abort cleanly." | Class-A hard caps abort legitimate complex refactors mid-stride. M8 §2.3 quality-first — no Class-A caps. §2.3 ≥30% blocked gate + §3.3 PRODUCT-DECISION + 1-round fix-loop gate all escalate к user via AUQ. User has agency. |
| "Auto-handle MEDIUM-tier findings к reduce user friction." | The Metaswarm anti-pattern catalogued в `report.md`. M8 §3.3 routes MEDIUM finds к "note в completion summary; proceed" — visible, not auto-dropped. Never auto-drop. |
| "Auto-promote L2 discoveries к L4 rules когда refactor completes." | §3.5 + P-M4-5 — surface а suggestion line; do NOT auto-promote. User remains source-of-truth для L4 curation. Auto-promotion creates noise + drift. |
| "Skip the §3.4 completion summary; the agent self-report covers it." | Agent self-report is а raw spawn artifact. §3.4 IS the user-facing deliverable — risk classifications, blocked steps, validation status, next-step routing. Без it, user cannot make informed decisions. |
| "Bypass `git guardrail` hooks if а needed `git stash` / `git checkout -- .` step blocks." | The hooks fail-closed для а reason. `git checkout -- .` (revert path) is explicitly permitted per § ACI per-phase. Other git mutations stay blocked. If а specific guardrail blocks legitimate refactor work, the path is `.geniro/safety.json` `allow_patterns`, not `--no-verify`. |
| "Defer M3 compaction-survival к downstream skills — M8 is mostly mechanical." | M3 contract IS M8's contract — state.md frontmatter (M1 §T1), `approvals[]` (P-M1-1 + M3 Block 5d), `## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason`. Без them, compaction mid-execution loses the plan и the per-step audit trail. |
| "Audit trail isn't needed для local /refactor runs — the diff IS the record." | The diff is the OUTPUT, not the audit. `## Tool log` records subagent spawn outcomes (which can drive escalation re-runs). `## Open Questions` records gating decisions. Без them, post-mortem on а failed run is impossible. |
| "PRODUCT-DECISION 4-option AUQ is paternalistic — collapse к 2 options (run /implement / accept-as-is)." | М8 §8.3 explicit: 4 fixed options когда ADR-eligible (3 otherwise). The ADR path captures rejection rationale durably; the Revert path is а user-controlled safety net. Collapsing removes meaningful agency. |
| "Trivial tier should still run а quick reviewer-pass — what if а smell slipped through?" | Trivial is by definition 1-2 files, mechanical, single module, unambiguous. The diff-sanity check в §3.1 + the baseline regression в §2.4 catch behavioral drift. Running а full reviewer-agent batch для а 5-line rename wastes tokens. Tier behavior is intentional. |
| "Subdir-per-slug layout adds nesting overhead — keep flat `state-<slug>.md`." | Flat layout shares concurrency model с M4/M5/M7. Subdir-per-slug matches the cross-skill convention (М4 §5.4 inputs persist, М7 §11.1). Consistency wins over а cosmetic preference. |

---

## Anti-pattern check (P-MP-1)

М8 implementation does NOT reintroduce:

1. ✅ **One giant prompt** — modular SKILL.md + `_shared/*.md` references (effort-scaling, existing-abstraction-audit, per-finding-question, improvement-routing).
2. ✅ **One giant tool** — narrow Read/Edit/Write/Bash + ACI per-phase (§ ACI per-phase tool surface).
3. ✅ **Unbounded autonomous loop** — §2.2 3-retry per step + §2.3 ≥30% session cap + §3.3 1-round fix-loop, all escalating to user via AUQ.
4. ✅ **Autonomous external sends в first release** — N/A для /refactor (no `git push`, no `gh pr create`; `git checkout -- .` revert path только с user confirmation).
5. ✅ **No approval state** — `approvals[]` (P-M1-1) + M3 Block 5d render (categories: refactor_high_step, refactor_product_decision).
6. ✅ **No durable plans или goals** — state.md mandatory (M1 §T1).
7. ✅ **No compaction strategy** — M3 SessionStart re-injects via Block 2-6 (+5b errors + 5c open questions + 5d approvals).
8. ✅ **All connectors loaded up front** — Claude Code's MCP plugin model gates this.
9. ✅ **High-risk tools без policy** — file-protection, git-guardrail, .geniro/ deletion hooks + § ACI per-phase blocks.
10. ⚠️ **Subagents before single-agent MVP measured** — М8 spawns refactor-agent (Phase 1 + Phase 2) + relevance-filter + reviewer + custom reviewers; single-agent measurement deferred к P-X6.
11. ✅ **Dynamic timestamps в plugin-distributed Markdown** — N/A; this SKILL.md has no runtime-timestamp bodies.
12. ✅ **Non-deterministic agent registration order** — N/A; agent registration is alphabetic by slug.

---

## Task Tracking

Use `TodoWrite` к expose per-phase progress. At skill start, create phase-level todos: Plan, Apply, Verify. During Phase 2, add dynamic per-step todos derived от the approved plan. Mark `in_progress` → `completed` as phases run. At most ONE todo is `in_progress` at а time.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Baseline validation never passes | Escalate: tests must be fixed before refactoring can proceed safely |
| Refactor-agent blocked on ≥30% of steps | §2.3 cap hit — stop и escalate; likely scope too large или conventions misread |
| Relevance filter rejects >50% of smells | Likely scope-convention mismatch — confirm с user before proceeding |
| User rejects all HIGH-risk steps | Empty remaining plan → ask whether к proceed с LOW/MEDIUM only или abort |
| Cross-module coupling discovered mid-execution | Follow Blocked Step Protocol; do NOT expand scope mid-session — note для follow-up refactor |
| PRODUCT-DECISION finding repeats across runs | User picked "Document as-is" prior round; check `approvals[]` для prior pick before re-firing AUQ |

---

## Definition of Done

- [ ] L4 / L3 / L2 layers loaded at Phase 1 entry (§1.1)
- [ ] All tests pass before и after each change (§1.2 baseline + §2.4 regression)
- [ ] Tier classified per canonical effort-scaling (§1.3)
- [ ] Hard escalation signals checked (§1.3.2 — refactor-specific orthogonal к effort-scaling)
- [ ] Smell-detection refactor-agent + relevance-filter spawned (Medium+ only)
- [ ] Plan built и presented в chat; HIGH-risk steps gated via AUQ (§1.6 — Always-WAIT, P-M1-1-aware)
- [ ] Refactor-agent executes plan, one transformation at а time (§2.2)
- [ ] ≥30% blocked → §2.3 stuck AUQ fired (User picks; never silent abort)
- [ ] Final regression run captured as Evidence Block (§2.4)
- [ ] Diff sanity check ran (§3.1)
- [ ] Independent reviewer + custom reviewers ran (Medium+ only — §3.2)
- [ ] PRODUCT-DECISION findings escalated к /geniro:implement (always-WAIT, §3.3) — refactor's zero-behavior-change constitution means multi-path findings are NOT fixed in-skill
- [ ] CRITICAL/HIGH non-PD findings → 1-round fix loop; past that → §3.3 verify-fix AUQ
- [ ] MEDIUM findings noted в completion summary; proceeded
- [ ] Completion summary presented в chat (§3.4)
- [ ] L2 emit fired (§3.5) с `discovery` или `pitfall` type + required `ext.*` fields; L4 promotion suggestion surfaced
- [ ] Improvements suggested per M2 §5.4 routes (§3.6)
- [ ] Cleanup completed (§3.7 — state.md removed для current branch's slug only; 3 legacy generations cleared best-effort; temp files cleaned)
- [ ] No `git commit` / `git push` / `gh pr create` — diff stays uncommitted (user или /geniro:implement ships)

---

## Example invocations

```
/geniro:refactor Extract shared validation logic от auth и user modules
/geniro:refactor Consolidate test helpers в utils/ к single module
/geniro:refactor Split 1000-line service into focused domain modules
/geniro:refactor Reduce coupling between database и business logic layers
```
