---
name: geniro:refactor
description: "Use when restructuring code for better organization or reducing tech debt while guaranteeing zero behavior change. 3-phase loop (Plan → Apply → Verify) mirroring /implement. Adopts canonical effort-scaling tier rubric (Trivial / Small / Medium / Big). NEVER ships code — diff is the deliverable, working tree is the channel. For behavioral changes use /geniro:implement; for performance optimizations use /geniro:review --simplify."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite]
argument-hint: "[what to refactor and why]"
---

# Refactor with Test Verification

Safe incremental refactoring that validates behavior is preserved at every step. Restructures code for better organization, reduces tech debt, and improves patterns without changing observable behavior. 3 phases mirroring `/geniro:implement`.

**Architecture spec:** *(internal)*. Detailed contracts:
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` — canonical tier rubric (Trivial / Small / Medium / Big) adopted per Q2
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` — smell-detection sub-step per- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate — PRODUCT-DECISION escalation per- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` § ADR template — ADR-path (4th AUQ option when ADR-eligible)

**Section-reference convention:** references in this SKILL.md point to local sub-sections (Phase 1, Phase 2, Phase 3 respectively).

---

## Your Role — Restructure, Don't Ship

You refactor. You validate behavior preservation. You do NOT commit or push the diff. Phase 3 endpoint is a working-tree diff (the deliverable) + a chat completion summary + state.md audit trail. Downstream actors (user `git commit`, `/geniro:implement` to ship through review gate) handle the actual ship.

The constitutional rule (zero behavior change) is enforced per-step via the orchestrator-inline regression test gate AND post-execution via the final regression run. PRODUCT-DECISION findings ALWAYS escalate — picking one resolution path is a behavior change.

---

## When to use

- Extracting shared logic from multiple modules
- Restructuring a module for clarity or testability
- Consolidating similar patterns across files
- Reducing coupling between components
- Improving module organization within a package

## When NOT to use

- For behavioral changes or feature additions (use `/geniro:implement`)
- To optimize performance (use `/geniro:review --simplify` and measure first)
- To add error handling not previously present (behavioral change → `/geniro:implement`)
- To reorganize without clear architectural benefit

---

## State Machine

state.md `phase:` enum transitions:

```
[entry] → plan ──┬── apply ──┬── verify ──┬── done
│ │ │
│ │ └── verify-summary-only (terminal — "Document and ship as-is" path)
│ │
│ └── apply-escalated ──┬── verify (keep what worked → partial-application note)
│ ├── reverted (terminal — "Revert all changes")
│ └── aborted (terminal)
│
└── plan-escalated ──┬── plan (user supplies missing context)
├── aborted (terminal)
└── routed (terminal — hard signal "Escalate")

verify ──┬── (happy: → done above)
│
└── verify-escalated ──┬── apply ("Run /implement" on PRODUCT-DECISION → exit /refactor)
├── reverted (terminal — "Revert this refactor")
├── done ("Document and ship as-is" → done with deferred-decision note)
└── adr-documented (terminal — "Document as ADR")
```

**Terminal states:** `done`, `verify-summary-only`, `reverted`, `aborted`, `routed`, `adr-documented`. the SessionStart recovery treats all six as «task complete — no resume needed».

**Non-terminal states:** `plan`, `apply`, `verify`. the recovery rolls these back to phase-entry and re-runs (idempotent — `approvals[]` ensures HIGH-step + PRODUCT-DECISION gates skip already-answered).

**Escalation states:** `plan-escalated` (hard signal OR baseline red), `apply-escalated` (≥30% blocked), `verify-escalated` (PRODUCT-DECISION or 1-round fix-loop exhausted). the surfaces to user as "task was paused — last AUQ options:" so user re-picks without losing context.

**Termination-case mapping** per — see architecture spec for the 8-row table. The `## Termination reason` body section is written on `aborted` / `reverted` / `routed` terminals.

---

## Loop Invariants

The 7 invariants apply unchanged. Three skill-specific notes:

1. **Invariant #4 (bounded structured tool results)** — orchestrator-inline execution writes per-step status and blocked-step reasons to state.md `## Plan steps`; total file body capped at ~8K chars via atomic_state_write truncation marker.
2. **Invariant #5 (escalation gates, not silent abort)** — ≥30% blocked AUQ + PRODUCT-DECISION always-WAIT.
3. **Invariant #7 (errors → structured observations)** — per-step blocked rationale, baseline validation failure, and reviewer CRITICAL findings all become structured `## Tool log` / `## Errors` entries.

`## Tool log` schema: typical run produces 3-6 entries (reviewer-agent + custom reviewers + escalation entries; smell detection and per-step execution run orchestrator-inline and emit to state.md `## Plan steps` directly).

---

## Budgets — Quality-First

This skill has **NO hard kill caps**. Same model as other skills /
**Quality gates (escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Per-step retry (orchestrator-inline Blocked Step Protocol) | 3 | | Mark BLOCKED, continue to next step |
| Session-level blocked ratio | 30% (post-rejection denominator) | | AUQ — keep what worked & escalate / revert / force-continue. User picks. |
| Phase 3 fix-loop | 1 round | | Re-spawn reviewer once; if still failing, AUQ (escalate / accept / abort). |
| Reviewer output size | ~4K chars per dim | invariant #4 | Truncation with marker. |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| Parallel reviewer spawns | 1 independent + N custom reviewers | |
| Smell-detection rounds | 1 (orchestrator-inline) | |
| Relevance-filter rounds | 1 (Medium+ only) | |

**Explicitly NOT capped:** wall-time, total tool calls, total model turns, total cost. Same rationale.
---

## Subagent Model Tiering

Follow the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly. For plugin-defined subagents (refactor, relevance-filter, reviewer), also follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (registration ladder: `geniro-claude-plugin:<agent>` → bare `<agent>` → `general-purpose` with body inlined). Cache the resolved rung for the rest of the session.

Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site — every Agent prompt MUST satisfy the six pre-inlined fields.

**Skill-specific mapping** — refactor work is mostly mechanical pattern application; Sonnet handles ~90% of cases:

| Spawn | Tier | When |
|---|---|---|
| Orchestrator-inline execution (LOW or MEDIUM risk) | Orchestrator's model | Smell detection + per-step execution run on orchestrator's main thread (typically Opus 4.7) |
| Orchestrator-inline execution (HIGH risk) | Orchestrator's model | Same — orchestrator already on highest tier; HIGH-risk plan steps don't warrant a separate tier (no subagent to re-tier) |
| Independent reviewer-agent + custom reviewers | `sonnet` | Phase 3 diff review (Medium+ tier only) |
| Focused ADR-drafting agent | `sonnet` | ADR path (only fires if ADR-eligible PRODUCT-DECISION) |

## Agent Failure Handling

If any delegated agent fails (timeout, error, empty/garbage result): retry once with the same prompt. If the retry also fails:
- **Smell detection and smell evidence** run orchestrator-inline and cannot fail separately — failures bubble up as normal orchestrator errors (Read / Grep / Glob unavailable would halt the skill).
- **Per-step execution** failures: do NOT silently skip. If a step's Blocked Step Protocol exhausts 3 retries, revert that step and continue per (≥30% blocked → AUQ). Catastrophic Edit failures (filesystem error) → revert all changes (`git checkout --.` with user confirmation per) and escalate to user with failure context.
- **Phase 3 reviewer-agent:** note the failure in the completion summary and proceed (fail-open); warn the user that independent review did not complete.

---

## Evidence Standard

Cite the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. applies it at baseline validation, per-step regression gate (orchestrator-inline pre/post-check), and final regression run.

---

## Universal Rule: All Choice Questions Use AskUserQuestion

Every user-facing choice in this skill MUST go through the `AskUserQuestion` tool per the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Universal AskUserQuestion Rule. The enumerated gates are examples, not an exhaustive list.

---

## Phase 1 — Plan

state.md `phase: plan`. Light by cost vs Phase 2 — a scope-discovery batch (Read + Grep) + 1 baseline validation run + orchestrator-inline smell detection (Medium+) + orchestrator-inline smell evidence (Medium+) + orchestrator plan-build.

Exits to Phase 2 only when: (a) baseline validation green, (b) tier classified, (c) hard signals checked, (d) smells identified (Medium+) + relevance-filtered (Medium+), (e) plan built and approved (HIGH-risk steps gated).

### 1.1 Memory layer load (L4 / L3 / L2)

On Phase 1 entry, in order:

1. **L4 refresh** — `load-custom-instructions(MODE: refresh, scope: refactor + global + code-style — pipeline tier, 3 files)` per Echo contract.
2. **L3 refresh** — `load-semantic(MODE: refresh, top-2 default)` — `_project.md` + `_CODEBASE_MAP.md`. Fingerprint drift check fires if applicable.
3. **L2 prior-knowledge query** — `query-learnings(tags=<inferred from $ARGUMENTS>, scope=task path)` per To find prior discoveries about coupling, pitfalls, and conventions relevant to the refactor scope.
4. **Cross-layer conflict resolution** — `resolve-conflicts(L2/L3/L4 loaded)` per
Echo lines per mandatory.

### 1.2 Scope discovery + baseline + Test-first gate

1. **Parse `$ARGUMENTS`** to understand what is being refactored and why.
2. **Use Grep + Glob** to find all related files. Read all files in scope to understand current organization, dependencies, imports, and test coverage.
3. **Prior-planning context.** Scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. Check: `.geniro/planning/*/` (task-local), `.geniro/workflow/*.md`, `<PRIMARY_ROOT>/.geniro/knowledge/learnings.jsonl` (grep for scope-file keywords), git state (`git rev-parse --show-toplevel`, `git branch --show-current`, `git log --oneline -5`, `git status --short`).
4. **Read project convention files** referenced in CLAUDE.md.
5. **Baseline validation** — run the project's validation suite once (read command from CLAUDE.md). Capture as an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. Outcomes:
- **Red:** `AskUserQuestion` header "Baseline" — "Fix the broken tests first (stop refactoring)" / "Proceed anyway — existing failures are out of scope (risky)". Default: stop. state.md → `phase: plan-escalated`.
- **No tests exist:** escalate immediately — "Cannot refactor safely without tests. Use `/geniro:implement` to add coverage first." state.md → `phase: routed` (terminal).
- **Green:** record passing-state fingerprint (test count) in state.md `## Baseline` body section; proceed.
6. **Test-First Gate (behavior-adjacent coverage check).** Before any refactor edit, check whether each function/symbol in scope has at least one test exercising it. If a gap is detected, fire `${CLAUDE_PLUGIN_ROOT}/skills/_shared/test-first-gate.md` — author RED before refactor edit. If every scope-symbol already has coverage, skip silently.

### 1.3 Tier classification (canonical effort-scaling — Q2 closure)

**Adopt canonical effort-scaling.md rubric**. /refactor no longer overrides the canonical. Apply effort-scaling Step 1 (hard signals) → Step 2 (5-dim score) → Step 3 (tier behavior). Refactor-specific hard signals apply orthogonally — they escalate OUT of /refactor entirely.

#### 1.3.1 Apply canonical effort-scaling

1. **Step 1 (canonical 9 hard signals from effort-scaling.md):** new entity/table/migration, new API endpoint/route, auth/permissions/role changes, new module/subsystem, 3+ modules coordinated, OCP violation, new async/queue/background, new external integration/env vars, ambiguous intent. Any present → **Big tier**, skip to Step 3.
2. **Step 2 (canonical 5-dim score 0-10):** Task type / Cross-boundary scope / Reversibility / Edit scatter / Pattern availability. Score sum:
- **0** → Trivial (must ALSO be 1-2 files, single module, unambiguous intent — otherwise round up to Small)
- **1-3** → Small
- **4-6** → Medium
- **7+** → Big
3. **Step 3 (refactor-specific tier behavior):**

| Tier | Refactor behavior |
|---|---|
| **Trivial** | 1-2 files, mechanical (rename, single extract). Skip smell-detection. Skip relevance-filter. Skip independent reviewer + custom reviewers. Orchestrator authors the plan directly from $ARGUMENTS + scope-files Read; goes straight to Phase 2 execution. |
| **Small** | Full smell-detection in BUT skip relevance-filter (scope too narrow to matter). Skip independent reviewer + custom reviewers. |
| **Medium** | Full pipeline as specified — orchestrator-inline smell-detect + orchestrator-inline smell evidence + reviewer-agent + custom reviewers. |
| **Big** | Recommend running `/geniro:plan` first to split the refactor into independently shippable milestones; refactor then runs one milestone at a time against an approved spec.md. If user wants to proceed without planning, require explicit confirmation via `AskUserQuestion` header "Scope": "Run /geniro:plan first" / "Proceed without a plan (risky)". On "Proceed without a plan", Big runs the Medium pipeline. The only difference is user has accepted the added risk of proceeding without architectural review. |

#### 1.3.2 Refactor-specific hard escalation signals (escalate OUT — orthogonal to effort-scaling)

These 4 refactor-specific signals are orthogonal to the canonical effort-scaling tier. Any present → escalation AUQ "Scope" — "Escalate to suggested skill" / "Proceed anyway (treat as Big)" / "Reduce scope". Default: Escalate. On "Escalate" pick → state.md `phase: routed` (terminal).

| Signal | Routing target |
|---|---|
| Behavioral change required | `/geniro:implement` |
| New tests required to cover untested code | `/geniro:implement` |
| Test assertions touched (not just imports) | Not refactoring — `/geniro:implement` |
| Auth, crypto, or payment code touched | Escalate (owner review required) — surface to user, not auto-route |

### 1.4 Smell detection (orchestrator-inline — Medium+)

Skipped for Trivial and Small per Step 3.

The orchestrator runs the 6 smell detection categories + Deepening Opportunities lens inline — no subagent spawn (subagent rationalization; sequential refactoring is exactly the failure mode the Google/MIT 2025 study predicts for multi-agent variants, arXiv 2512.08296: −70% accuracy on sequential reasoning).

**Reference:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` Phase 1 — full smell taxonomy + change-impact scoring + escalation rules. The orchestrator reads this file once at entry and applies the rubric inline.

**Per-smell procedure:**

1. Apply the 6 smell categories (duplication / long methods / god classes / dead code / tight coupling / type+import issues) via Read + Grep against the FILES IN SCOPE from2. Apply the Deepening Opportunities lens — read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/architecture-vocabulary.md` first for vocabulary grounding, then scan for wide-interface shallow modules / pass-through wrappers / repeated cross-call orchestration / high-leverage shallow code.
3. For every detected smell, run the canonical **Existing Abstraction Audit** at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` — apply its Procedure (Grep designated helper directories, categorize REUSE-AS-IS / EXTEND / NO-ANALOGUE, force-fit guard, Rule of Three). Emit candidates inline alongside each smell using the audit's Output format.
4. Count consumers per smell via Grep (`Grep(pattern="SymbolName", output_mode="count")`). Adjust glob filter based on language (`*.ts` / `*.py` / etc).
5. Public-surface guard: flag smells that change public API signature, module export, or shared type — these are HIGH-risk regardless of consumer count.

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
```

Risk classification (LOW / MEDIUM / HIGH) and ordering happen in (orchestrator decisions, not's job).

Anchor: stay within WORKTREE on BRANCH — orchestrator verifies with `pwd && git branch --show-current` once at entry; abort if either differs.

### 1.5 Orchestrator-side smell evidence + KEEP/FILTER

Skipped for Trivial and Small. The orchestrator gathers evidence on detected smells against repo conventions inline — no subagent spawn (folded under subagent rationalization; light reasoning that fits orchestrator's main context cleanly should not be spawned).

For each smell detected per, the orchestrator weighs three signals inline:

1. **Convention alignment** — is this «smell» actually the repo's chosen pattern? Cross-check with CONTRIBUTING.md, ADRs at `docs/adr/`, architecture docs (when present) and CLAUDE.md.
2. **Over-engineering** — would fixing this smell introduce more complexity than it removes? Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` mental check.
3. **Intentional pattern** — does the flagged pattern exist deliberately in 3+ other files? Quick Grep pass over similar paths confirms.

Synthesis matrix per smell:

| Convention | Complexity | Frequency | Decision |
|---|---|---|---|
| ALIGNS | * | * | FILTER (repo's chosen pattern) |
| CONTRADICTS | OVER-ENGINEERED | * | FILTER (cure worse than disease) |
| CONTRADICTS | APPROPRIATE | WIDESPREAD | FILTER OR consult user (intentional rather than smell) |
| CONTRADICTS | APPROPRIATE | ISOLATED | KEEP (genuine smell) |
| NEUTRAL | APPROPRIATE | ISOLATED | KEEP (default) |

KEEP smells enter plan-build. FILTERED smells are noted in state.md `## Filtered smells` section with the synthesis reason. No fail-open caveat needed — dedup and judgment run in orchestrator's main context.

### 1.6 Risk classification + plan build + approval AUQ

Orchestrator builds the plan from-inline output (Medium+) or directly from scope-files (Trivial/Small):

1. **Classify risk per smell** (lookup):
- 1-3 consumers → LOW
- 4-9 consumers → MEDIUM
- 10+ consumers → HIGH
- Public API / module export / shared type change → HIGH (overrides consumer count)
2. **Order the plan**: safer transformations first (LOW → MEDIUM → HIGH). Within the same tier, group by file to minimize re-reads.
3. **Mark HIGH-risk steps for user confirmation** (presented via `AskUserQuestion`).
4. **Build the final plan** with: smells, ordered steps, risk per step, consumer counts, files that will change, what will NOT change (public APIs, DB schema, test behavior), `max_risk` (max across all step risks).

**Approval gate (Always-WAIT, ):** If any steps are **HIGH risk**, present them to user via `AskUserQuestion` header "Approve HIGH-risk steps" and wait for confirmation. Each step rendered with: file path / proposed transformation / consumer count / risk classification / rationale.

**Approvals-persistence:** before firing, check state.md frontmatter `approvals[]` for prior entries with `category: refactor_high_step` matching the current step. Use prior `picked` if found. On user pick, append entries to `approvals[]` via `atomic_state_write`. Block 5d renders on resume.

If all steps are LOW/MEDIUM: present the plan summary in chat and proceed (no AUQ).

state.md transitions: `plan` → `apply` once approval complete. `## Plan` body section with full plan; `## Persisted approvals` rendered from `approvals[]`.

---

## Phase 2 — Apply

state.md `phase: apply`. Refactor-agent executes the approved plan, one step at a time, with per-step validation. The zero-behavior-change constitutional rule is enforced via the per-step regression test pass.

### 2.1 L4 refresh entry

On Phase 2 entry, single `load-custom-instructions(MODE: refresh, scope: refactor + global + code-style — pipeline tier, 3 files)` call. Phase 3 inherits the Phase 2 refresh (no code-writing in Phase 3).

### 2.2 Per-step execution (orchestrator-inline)

The orchestrator executes the approved plan inline, one step at a time — no subagent spawn. Sequential refactoring with per-step regression is exactly the failure mode the Google/MIT 2025 study predicts for multi-agent variants (arXiv 2512.08296: -70% accuracy on sequential reasoning); orchestrator-inline preserves state continuity and halves test runs via the skip predicate.

**Reference:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` Phase 3 — full Step Execution Protocol + Blocked Step Protocol + skip-predicate rules. The orchestrator applies this verbatim inline.

**Pre-loop setup:**

- Read the approved plan from state.md `## Plan steps` (skipping any HIGH steps the user rejected in).
- Read code-style content as echoed by / loader (cwd OR primary-worktree fallback per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`). Use it inline when applying transformations. Skip when loader echoed `No code-style.md found — skipping.`
- Resolve test commands: `<test_cmd_affected>` from CLAUDE.md's Essential Commands (per-step gate; falls back to `<test_cmd>` if undefined); `<test_cmd>` for final regression.
- Anchor: verify `pwd && git branch --show-current` once at entry; abort if either differs from baseline.

**Per-step loop** (orchestrator runs sequentially for each pending step):

For each step N in `## Plan steps` where `status: pending`:

1. **Re-read the target files** (Read tool) — capture current state of files affected by step N.
2. **Pre-condition check** (orchestrator applies skip predicate per `refactor-patterns.md` Phase 3 Step 2):
- REQUIRED if N == 1, OR `last_post_check == unset|REVERTED`, OR external edits intervened
- SKIPPED if N > 1 AND `last_post_check == PASS` (no edits intervene between sequential transformations — the previous step's post-check already validated the same baseline)
- When required: `source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Pre-check step <N>" "<test_cmd_affected>"`. On fail: stop and report (broken baseline).
3. **Apply change** (Edit tool, surgical, scope-bounded to step's `files_affected`).
4. **Post-condition check**: `source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Post-check step <N>" "<test_cmd_affected>"`. Persist result to state.md `## Plan steps` row as `last_post_check: PASS|FAIL` (atomic_state_write).
5. **Result handling**:
- **PASS**: mark `status: complete`, `attempts: <N>`, `last_post_check: PASS`. Continue to next step.
- **FAIL**: enter Blocked Step Protocol (below).

**Blocked Step Protocol** (orchestrator-inline per `refactor-patterns.md`):

1. Attempt 1: analyze failure from tail-80 output, fix issue, re-run `<test_cmd_affected>`.
2. Attempt 2: try a different approach to the same transformation, re-run.
3. Attempt 3: try one more variation, re-run.
4. After 3 failures: REVERT step's Edit changes (orchestrator uses Edit tool's `old_string`/`new_string` reversal or re-reads file and rewrites to pre-step content), mark `status: blocked`, `attempts: 3`, `last_post_check: REVERTED`, append blocked-rationale row to state.md. Continue to next step (NOT stop session).

State.md `## Plan steps` body schema captures per-step status (per `refactor-patterns.md` Phase 2 schema): `step` / `smell` / `risk` / `consumers` / `transformation` / `before` / `after` / `test_strategy` / `files_affected` / `rollback` / `status` / `attempts` / `last_post_check`. Orchestrator updates the row after each step via `atomic_state_write`.

Model tier note: the orchestrator's own model (Opus 4.7 typically) runs the loop. HIGH-risk plan steps don't need separate model tiering — orchestrator is already on the highest tier; per-step reasoning runs at orchestrator-grade quality throughout.

### 2.3 Session-level cap + escalation AUQ

After execution returns, count BLOCKED-to-executed ratio (post-user-rejection denominator: approved plan steps minus user-rejected HIGH-risk steps). **If ≥30% BLOCKED:** stop and escalate via `AskUserQuestion` header "Stuck":

- **Keep what worked and escalate the rest** — proceed to Phase 3 with blocked-steps list noted; user runs `/geniro:implement` separately for blocked items. state.md → `phase: verify` with `## Accepted Blocks` body section.
- **Revert all changes** — `git checkout --.` (with user confirmation per). state.md → `phase: reverted` (terminal).
- **Force-continue (not recommended)** — proceed to Phase 3 with blocked work treated as accepted. state.md → `phase: verify`.

Do NOT proceed to Phase 3 automatically when this cap triggers. state.md marks `phase: apply-escalated` with timestamp + blocked-ratio + blocked-steps list before AUQ; transitions per user pick. Block 5c renders open question on resume.

### 2.4 Final regression run + Evidence Block

After execution returns (or after user pick if fired), run the full test suite once (regression gate) and attach the captured run as an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. Reasoning-from-the-diff is forbidden — the captured run is the only proof the zero-behavior-change invariant held.

If regression failed: fire AUQ "Regression" — "Revert all changes" / "Show me the diff first" / "Keep changes for debugging". Default: Revert. On "Revert", `git checkout --.` after explicit user confirmation. state.md → `phase: reverted` (terminal).

If green: state.md transitions to `phase: verify`. `## Apply Summary` body section captures executed / blocked / final-suite status.

**L2 emit on retry exit.** When Phase 2 exits AND `blocked_count ≥ 2` (≥2 plan steps reported BLOCKED per orchestrator-inline Blocked Step Protocol, regardless of whether overall ratio triggered escalation), call `emit-learning` with type=`retry_failure_sequence`, trust=`verified`, required `ext.{phase: "refactor-apply", attempts: [{round: <step-index>, failure: "<blocked-rationale from state.md ## Plan steps row>"}], resolution}`. `resolution` ∈ `{passed, escalated, aborted}` — passed when regression green AND <30% blocked; escalated when fired AND user picked «Keep what worked» or «Force-continue»; aborted on reverted/aborted state. Sliding-window cap = 3 latest per `(producer, scope, phase)`. Single-blocked-step exits (blocked_count == 1) do NOT emit. Scope = the worktree-relative path of the largest-affected file.

---

## Phase 3 — Verify

state.md `phase: verify`. Diff sanity + independent review + completion summary + L2 emit + cleanup. No `git push` / `gh pr create` — refactor never ships code, only produces a working-tree diff (deliverable) and a state-file audit trail.

### 3.1 Diff sanity (all tiers)

Run `git diff --name-only` and `git diff --stat`. Cross-check state.md `## Plan steps` rows' `files_affected` aggregated list against the actual diff — flag mismatches.

If final regression failed AND user picked "Revert all changes", state.md is already `phase: reverted` — skip to cleanup (no review needed).

### 3.2 Independent reviewer-agent + custom reviewers (Medium+)

Skipped for Trivial and Small per Step 3.

For Medium and Big: spawn a fresh reviewer-agent. The agent reads its own criteria — do NOT pre-read into orchestrator context.

Pre-inline content the loader echoed: `code-style.md` content under `## Code-style instructions`. Omit when loader echoed `No code-style.md found — skipping.`

```
Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
## Review: Refactor Diff
This is a refactor — behavior MUST be unchanged. CI already passed. Focus on invariants, not style.

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

DIFF: [paste git diff output]
PLAN-STEPS REPORT: [paste state.md `## Plan steps` rows with final status]
PROJECT CONVENTIONS: [paste relevant conventions from CLAUDE.md]

## Code-style instructions
[content here]

## Focus Areas
- Accidental public-API changes
- Test assertion mutations (imports-only changes are fine; assertion changes are NOT)
- Invariant drift (error shapes, return types, null-vs-undefined, ordering)
- New coupling introduced by extraction/move
- Dead-code removal that actually had references

## Review Criteria
Read and apply these criteria files:
- `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/architecture-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`

Report findings with severity (CRITICAL/HIGH/MEDIUM) and confidence. Return findings as evidence. Do NOT emit an overall verdict — the orchestrating skill synthesizes findings and decides disposition.

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call.
""", description="Review: refactor diff")
```

**Custom reviewers (Medium and Big only — same gate):** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` to discover user-authored review dimensions in `.geniro/instructions/review-extra/`. For each spawn-spec returned, append one additional `Agent(subagent_type="reviewer-agent",...)` to the SAME parallel batch as the independent reviewer above — same assistant response, parallel execution. The helper's `paths:` filter uses the refactor's changed-files list. Custom-reviewer findings flow through the same orchestrator disposition logic as independent-reviewer findings. If the helper aborts on hard-cap error, surface error + skip; do not proceed with review.

### 3.3 Orchestrator disposition logic

**PRODUCT-DECISION findings → ESCALATE (Always-WAIT, every tier):**

A PRODUCT-DECISION finding implies multiple valid resolution paths, and refactor guarantees zero behavior change. Picking one is a behavior change, contradicting the constitution. Phase 3 ESCALATES PRODUCT-DECISION to `/geniro:implement`; does NOT gate-and-fix in-skill.

Surface every PRODUCT-DECISION finding via `AskUserQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate (`header: "Escalate"`). 4 fixed options (ADR-eligibility determines whether 4th option included):

1. **Run /geniro:implement on this finding (Recommended)** — exit /refactor; user runs /implement separately to apply a behavioral fix. state.md → `phase: verify-escalated` then on pick → exit (out-of-skill).
2. **Revert this refactor and start over** — `git checkout --.` with user confirmation. state.md → `reverted` (terminal).
3. **Document and ship as-is — accept the open decision** — keep the working-tree diff, note the deferred decision in completion summary. state.md → `verify-summary-only` (terminal). The user takes the responsibility of resolving the decision later.
4. **(ADR-eligible only)** **Document as ADR** — spawn a focused agent (`model: sonnet`) to draft the ADR per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` § ADR template; write to `docs/adr/NNNN-<slug>.md` (next sequential N; create directory if missing, after `AskUserQuestion` confirmation). state.md → `adr-documented` (terminal).

**ADR-eligibility check (before adding 4th option):** include the "Document as ADR" option ONLY when the rejected refactor candidate meets all three criteria from `improvement-routing.md` § ADR target: (1) hard to reverse, (2) surprising without context, (3) result of genuine trade-offs. Examples that qualify: rejecting "split this god-class into 3 modules because the team prefers single-file feature ownership" (the *rejection* is the durable decision); rejecting "switch from inheritance to composition here because the existing inheritance is load-bearing for the plugin system." Examples that do NOT qualify: rejecting a duplicate-extraction smell because the duplication is intentional (Rule of Three not yet met) — that's a learning, not an ADR. If unsure, omit the ADR option; routing to Knowledge is always safe.

**Approvals-persistence:** before firing the PRODUCT-DECISION AUQ, check state.md frontmatter `approvals[]` for a prior entry with `category: refactor_product_decision` matching the finding (use finding `path:lines` + decision-type as disambiguator). If found, use prior `picked` value. If not found, fire AUQ → on user pick, append to `approvals[]` via `atomic_state_write` BEFORE executing the chosen action.

Fire one `AskUserQuestion` per PRODUCT-DECISION finding; chain across findings — never batch multiple findings into a single question.

**CRITICAL or HIGH (non-PRODUCT-DECISION) findings → fix loop (max 1 round):**

Orchestrator-inline addresses specific findings (Edit per finding); then re-spawn reviewer-agent fresh on the updated diff. After 1 round, if still failing — surface to user via AUQ header "Verify-fix" with options: "Escalate to /implement" / "Document remaining findings and ship as-is" / "Revert all changes". state.md → `verify-escalated` with timestamp + 1-round fix attempt summary.

**MEDIUM findings only → note in completion summary; proceed.**

**No findings → proceed.**

### 3.4 Completion summary

Output the markdown block directly in chat. No persistence to a T2 handoff file — diff IS the deliverable.

```markdown
## Refactor Complete

### Transformations Applied (N)
- [file:line] — [what changed] — risk: [LOW/MEDIUM/HIGH] — consumers: N

### Blocked Steps (N)
- [file:line] — [what was attempted] — reason: [failure summary]

### Filtered by Relevance (N — omit for Trivial/Small; relevance filter not run)
- [smell] — [reason filtered]

### Review Findings (Medium and Big only — omit for Trivial/Small)
- CRITICAL: N, HIGH: M, MEDIUM: K
- Disposition: [proceeded / 1-round fix loop / escalated / ADR documented]

### Validation
- Tests: PASS/FAIL
- Baseline delta: [before→after test count]

### Files Modified: N
- [file path]: [one-line summary]

### Deferred
- [P3 item or user-rejected HIGH step]

### Next steps
[The diff is in your working tree. Commit it yourself, or run `/geniro:implement` to ship with a review gate.]
```

### 3.5 L2 auto-emit

At Phase 3 exit:

- **`emit-learning`** — called by /refactor for two emit types per canonical contract:
- **`discovery`** — emit when a pattern was extracted to a shared utility/component (typical /refactor outcome). Required `ext.{area, insight}` per typed-extension table. Default trust `verified` per- **`pitfall`** — emit when the refactor revealed a footgun (a seemingly-safe pattern that actually breaks under specific conditions). Required `ext.{trap, mitigation}`. Default trust `verified`.
- **NOT emitted :** `diagnosis` (/debug owns); `convention` (/implement self-review owns); `decision` (/plan owns).

**L4 promotion suggestion:** when a `discovery` or `pitfall` entry is emitted, surface a one-line suggestion in Phase 3 final report:

```
[learnings] <Discovery|Pitfall> recorded: "<one-line summary>". Recorded to L2.
→ Consider /geniro:instructions edit <scope>.md to promote as a refactor-rule.
```

Scope hint follows the entry context:
- `discovery` (pattern extracted) → suggest `code-style.md`
- `discovery` (architectural insight) → suggest `global.md`
- `pitfall` (refactor-specific footgun) → suggest `refactor.md`
- Other → generic "appropriate scope"

The line is informational (no AUQ, no auto-edit). User remains source-of-truth for L4 curation. Fully automatic L2→L4 promotion deferred to a future release.

### 3.6 Suggest improvements (project scope only, routes)

After L2 emit, follow the canonical routing in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md`. Refactor runs typically surface:

| Insight category | Target | layer |
|---|---|---|
| Undocumented coding conventions / style patterns discovered during refactor | `.claude/rules/<scope>.md` with `paths:` glob frontmatter | L4 procedural |
| Surprising coupling between modules revealed during execution | `.geniro/knowledge/learnings.jsonl` (typically already covered by discovery emit) | L2 episodic |
| Patterns that should be auto-enforced | Project rules/hooks (out of plugin scope — point user to project tooling) | — |
| Skill-behavior constraints the user enforced manually during refactor | `.geniro/instructions/refactor.md` or `.geniro/instructions/global.md` | L4 procedural |

Plugin-internal paths (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope.

### 3.7 Cleanup

After Phase 3 completes:

- **All tiers:** Remove `<PRIMARY_ROOT>/.geniro/state/refactor/<slug>/state.md` for the current branch's slug only, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract. Useful content already saved (transformations, discoveries) via L2 emit + chat summary. Do NOT delete sibling slugs from concurrent refactor sessions on other branches.
- **Clear old state files** (best-effort; any may not exist):
```bash
rm -f ".geniro/refactor/state.md" 2>/dev/null
rm -f ".geniro/refactor/state-${slug}.md" 2>/dev/null
rm -f ".geniro/state/refactor/state-${slug}.md" 2>/dev/null
```
- **No T2 handoff to delete or persist**.
- Kill any background processes started during the run (test watchers, profilers).

Cleanup is best-effort — failed commands silently OK.

---

## State file schema

### state.md (T1 — session-bound, `.geniro/state/refactor/<slug>/state.md`)

Frontmatter:

```yaml
---
tier: T1
producer: refactor
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: <enum per State Machine above>
status: <in-progress|done|failed>
non-resumable-actions: [] # typically empty — refactor ships no commits
approvals: [] # — categories: refactor_high_step, refactor_product_decision
geniro_kind: refactor-state
geniro_schema_version: m8-v1
effort_tier: <Trivial|Small|Medium|Big>
task_slug: <slug>
worktree: <abs-path>
---
```

Body sections:
- `## Scope` — files + symbols in refactor scope
- `## Baseline` — Evidence Block from step 5 (test count + pass status)
- `## Smells Detected` — (Medium+) orchestrator-inline output from- `## Plan` — (after) ordered steps + risk + consumer counts + KEEP/FILTER decisions
- `## Apply Summary` — (after) executed / blocked / final-suite status
- `## Accepted Blocks` — (optional, path "Keep what worked")
- `## Review Findings` — (Medium+, after) CRITICAL/HIGH/MEDIUM lists
- `## Persisted approvals` — Block 5d (render of frontmatter approvals[])
- `## Tool log` — selective logging (reviewer + custom reviewer spawns, escalations; smell detection and per-step execution log to `## Plan steps`)
- `## Errors` — Block 5b
- `## Open Questions` — Block 5c (escalation AUQs + outcome)
- `## Termination reason` — (only on terminal aborted/reverted/routed states)

**No T2 handoff**: diff IS the deliverable; working tree is the channel.

---

## ACI per-phase tool surface

**Phase 1 (Plan):**
- Allowed: Read / Grep / Glob / Bash (read-only — `git status`, `git log`, `git diff`, `git branch --show-current`, test suite invocation for baseline).
- Allowed Agent spawns: none. smell detection + smell evidence both run orchestrator-inline.
- Explicitly blocked: production-source Edit/Write, `git commit`, `git push`, `gh pr create`.

**Phase 2 (Apply):**
- Allowed Agent spawns: none. Per-step execution runs orchestrator-inline (Edit + Bash for tests).
- Orchestrator uses Edit / Write / Bash (test cmd) directly. Per-step regression runs via backpressure helper.
- Explicitly blocked at orchestrator level: `git add`, `git commit`, `git push`, `gh pr create`, branch switching.

**Phase 3 (Verify):**
- Allowed: Read / Grep / Glob / Bash (`git diff --name-only`, `git diff --stat`, test cmd for re-runs).
- Allowed Agent spawns: reviewer-agent + custom reviewers (Medium+ only), focused ADR-drafting agent (if PRODUCT-DECISION ADR path picked).
- Allowed: `git checkout --.` (orchestration-level revert per / /) — exception to git-write constraint.
- Explicitly blocked: `git commit`, `git push`, `gh pr create`.

**All reviewer / custom reviewer spawns are pure read-only:** tool whitelist via `agents/reviewer-agent.md` frontmatter (Read / Grep / Glob / Bash for read-only checks).

**Existing safety layer** applies across ALL phases: file-protection hook, git-guardrail hook, `.geniro/` deletion guard. Runtime denies stay enforced.

---

## Memory I/O Schedule

| Phase | Helper | Direction | MODE |
|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` |
| Phase 1 entry | `query-learnings` | read L2 | n/a |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` (single re-fire) |
| Phase 3 exit | `emit-learning` | write L2 | n/a (emit types: `discovery` with `ext.{area, insight}` OR `pitfall` with `ext.{trap, mitigation}`) |

`update-semantic` writes to `_CODEBASE_MAP.md` for move/rename refactors (bounded auto-incremental ). Not applicable when refactor adds modules (would be a behavioral change → escalate per).

---

## Git Constraint

Do NOT run `git add`, `git commit`, or `git push`. The orchestrating workflow handles version control. Exception: `git checkout --.` is permitted in / / for reverting failed changes — this is an orchestration-level revert, not a version-control operation.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This smell is too small to fix" | If the plan says fix it, fix it. Small smells compound. |
| "I'll batch multiple transformations" | One atomic transformation at a time. Always. |
| "Tests are passing so I'll skip the blocked step protocol" | The protocol exists for the NEXT failure. Follow it. |
| "This refactoring needs a behavior change" | Then it's not a refactoring. Use `/geniro:implement` instead. |
| "I'll skip reading project conventions" | You'll flag intentional patterns as smells. Read first. |
| "This duplication needs a new shared helper" | Run the Existing Abstraction Audit first. If a utility / service / hook already exists nearby that could absorb this duplication via a small extension, prefer extending it. Only create a new shared helper when no analogue exists OR when extending the existing one would require adding a parameter or conditional that complicates it (Rule of Three). |
| "All detected smells are real issues" | Generic smell categories flag intentional repo patterns. Without filtering against THIS repo's conventions, you'll refactor code that was designed that way on purpose. |
| "This is just a refactor" | Refactors break things. Tests and review apply equally. |
| "I'll spawn agents one at a time" | All parallel agents MUST be spawned in ONE response — multiple Agent calls in the same assistant turn. Separate turns = no concurrency, full wall-clock latency per agent. |
| "The user said go fast — skip phases" | Phase skipping is tied to tier classification, not user impatience. Trivial/Small tiers already skip appropriately. |
| "I noticed a bug mid-refactor, I'll fix it" | That's feature work. Note it for `/geniro:implement` and stay in refactor scope. |
| "This change is obviously safe" | "Obviously safe" is the #1 predictor of broken builds. Run validation. |
| "I'll upgrade this sonnet spawn to opus just to be safe" | Model tier is task-nature-matched, not risk-appetite-matched. Re-classify via Subagent Model Tiering table; don't silently upsize. |
| "Reviewer flagged a `[PRODUCT-DECISION]` finding — I'll route it through the fix loop like any other CRITICAL/HIGH" | A `[PRODUCT-DECISION]` finding has multiple valid resolution paths by definition — picking one is a behavior change, which contradicts refactor's zero-behavior-change guarantee. disposition logic ESCALATES PRODUCT-DECISION to `/geniro:implement` (always-WAIT) — never gates-and-fixes them in-skill. If you find yourself orchestrator-inline editing for a PRODUCT-DECISION finding, that's the rationalization. Stop and route the escalation. |
| "Add a wall-time kill cap so long-running refactor sessions abort cleanly." | Class-A hard caps abort legitimate complex refactors mid-stride. quality-first — no Class-A caps. ≥30% blocked gate + PRODUCT-DECISION + 1-round fix-loop gate all escalate to user via AUQ. User has agency. |
| "Auto-handle MEDIUM-tier findings to reduce user friction." | The Metaswarm anti-pattern catalogued in `report.md`. routes MEDIUM finds to "note in completion summary; proceed" — visible, not auto-dropped. Never auto-drop. |
| "Auto-promote L2 discoveries to L4 rules when refactor completes." | + — surface a suggestion line; do NOT auto-promote. User remains source-of-truth for L4 curation. Auto-promotion creates noise + drift. |
| "Skip the completion summary; the agent self-report covers it." | Agent self-report is a raw spawn artifact. IS the user-facing deliverable — risk classifications, blocked steps, validation status, next-step routing. Without it, user cannot make informed decisions. |
| "Bypass `git guardrail` hooks if a needed `git stash` / `git checkout --.` step blocks." | The hooks fail-closed for a reason. `git checkout --.` (revert path) is explicitly permitted per § ACI per-phase. Other git mutations stay blocked. If a specific guardrail blocks legitimate refactor work, the path is `.geniro/safety.json` `allow_patterns`, not `--no-verify`. |
| "Defer compaction-survival to downstream skills — This skill is mostly mechanical." | The contract IS this skill's contract — state.md frontmatter, `approvals[]`, `## Tool log`, `## Errors`, `## Open Questions`, `## Termination reason`. Without them, compaction mid-execution loses the plan and the per-step audit trail. |
| "Audit trail isn't needed for local /refactor runs — the diff IS the record." | The diff is the OUTPUT, not the audit. `## Tool log` records subagent spawn outcomes (which can drive escalation re-runs). `## Open Questions` records gating decisions. Without them, post-mortem on a failed run is impossible. |
| "PRODUCT-DECISION 4-option AUQ is paternalistic — collapse to 2 options (run /implement / accept-as-is)." | explicit: 4 fixed options when ADR-eligible (3 otherwise). The ADR path captures rejection rationale durably; the Revert path is a user-controlled safety net. Collapsing removes meaningful agency. |
| "Trivial tier should still run a quick reviewer-pass — what if a smell slipped through?" | Trivial is by definition 1-2 files, mechanical, single module, unambiguous. The diff-sanity check in + the baseline regression in catch behavioral drift. Running a full reviewer-agent batch for a 5-line rename wastes tokens. Tier behavior is intentional. |
| "Subdir-per-slug layout adds nesting overhead — keep flat `state-<slug>.md`." | Flat layout shares concurrency model with other skills. Subdir-per-slug matches the cross-skill convention. Consistency wins over a cosmetic preference. |

---

## Anti-pattern check

implementation does NOT reintroduce:

1. ✅ **One giant prompt** — modular SKILL.md + `_shared/*.md` references (effort-scaling, existing-abstraction-audit, per-finding-question, improvement-routing).
2. ✅ **One giant tool** — narrow Read/Edit/Write/Bash + ACI per-phase (§ ACI per-phase tool surface).
3. ✅ **Unbounded autonomous loop** — 3-retry per step + ≥30% session cap + 1-round fix-loop, all escalating to user via AUQ.
4. ✅ **Autonomous external sends in first release** — N/A for /refactor (no `git push`, no `gh pr create`; `git checkout --.` revert path only with user confirmation).
5. ✅ **No approval state** — `approvals[]` + Block 5d render (categories: refactor_high_step, refactor_product_decision).
6. ✅ **No durable plans or goals** — state.md mandatory.
7. ✅ **No compaction strategy** — the SessionStart re-injects via Block 2-6 (+5b errors + 5c open questions + 5d approvals).
8. ✅ **All connectors loaded up front** — Claude Code's MCP plugin model gates this.
9. ✅ **High-risk tools without policy** — file-protection, git-guardrail,.geniro/ deletion hooks + § ACI per-phase blocks.
10. ⚠️ **Subagents before single-agent MVP measured** — now spawns only reviewer + custom reviewers (Phase 3); smell detection, smell evidence, and per-step execution all orchestrator-inline. Single-agent measurement of remaining reviewer spawns deferred to a future release.
11. ✅ **Dynamic timestamps in plugin-distributed Markdown** — N/A; this SKILL.md has no runtime-timestamp bodies.
12. ✅ **Non-deterministic agent registration order** — N/A; agent registration is alphabetic by slug.

---

## Task Tracking

Use `TodoWrite` to expose per-phase progress. At skill start, create phase-level todos: Plan, Apply, Verify. During Phase 2, add dynamic per-step todos derived from the approved plan. Mark `in_progress` → `completed` as phases run. At most ONE todo is `in_progress` at a time.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Baseline validation never passes | Escalate: tests must be fixed before refactoring can proceed safely |
| Refactor-agent blocked on ≥30% of steps | cap hit — stop and escalate; likely scope too large or conventions misread |
| Relevance filter rejects >50% of smells | Likely scope-convention mismatch — confirm with user before proceeding |
| User rejects all HIGH-risk steps | Empty remaining plan → ask whether to proceed with LOW/MEDIUM only or abort |
| Cross-module coupling discovered mid-execution | Follow Blocked Step Protocol; do NOT expand scope mid-session — note for follow-up refactor |
| PRODUCT-DECISION finding repeats across runs | User picked "Document as-is" prior round; check `approvals[]` for prior pick before re-firing AUQ |

---

## Definition of Done

- [ ] L4 / L3 / L2 layers loaded at Phase 1 entry
- [ ] All tests pass before and after each change
- [ ] Tier classified per canonical effort-scaling
- [ ] Hard escalation signals checked
- [ ] Smell detection + smell evidence ran orchestrator-inline (Medium+ only)
- [ ] Plan built and presented in chat; HIGH-risk steps gated via AUQ
- [ ] Refactor-agent executes plan, one transformation at a time
- [ ] ≥30% blocked → stuck AUQ fired (User picks; never silent abort)
- [ ] Final regression run captured as Evidence Block
- [ ] Diff sanity check ran
- [ ] Independent reviewer + custom reviewers ran (Medium+ only —)
- [ ] PRODUCT-DECISION findings escalated to /geniro:implement (always-WAIT,) — refactor's zero-behavior-change constitution means multi-path findings are NOT fixed in-skill
- [ ] CRITICAL/HIGH non-PD findings → 1-round fix loop; past that → verify-fix AUQ
- [ ] MEDIUM findings noted in completion summary; proceeded
- [ ] Completion summary presented in chat
- [ ] L2 emit fired with `discovery` or `pitfall` type + required `ext.*` fields; L4 promotion suggestion surfaced
- [ ] Improvements suggested per routes
- [ ] Cleanup completed
- [ ] No `git commit` / `git push` / `gh pr create` — diff stays uncommitted (user or /geniro:implement ships)

---

## Example invocations

```
/geniro:refactor Extract shared validation logic from auth and user modules
/geniro:refactor Consolidate test helpers in utils/ to single module
/geniro:refactor Split 1000-line service into focused domain modules
/geniro:refactor Reduce coupling between database and business logic layers
```
