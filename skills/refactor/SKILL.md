---
name: refactor
description: "Use when restructuring code for better organization or reducing tech debt with zero behavior change. 3-phase loop (Plan → Apply → Verify); never ships — the diff is the deliverable. For behavioral changes use /geniro:implement; for performance use /geniro:review (optimizations dimension)."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite]
argument-hint: "[what to refactor and why]"
---

# Refactor with test verification

## Contents

- Your role — restructure, don't ship
- State machine
- Loop invariants
- Anti-rationalization
- Budgets — quality-first
- Subagent model tiering · Agent failure handling
- Evidence Standard
- Universal rule: all choice questions use AskUserQuestion
- ACI per-phase tool surface
- Git constraint
- Memory I/O schedule
- Definition of done
- Phase 1 (plan) · Phase 2 (apply) · Phase 3 (verify)
- State file schema
- Task tracking

---

Safe incremental refactoring that validates behavior is preserved at every step. Restructures code for better organization, reduces tech debt, and improves patterns without changing observable behavior. 3 phases mirroring `/geniro:implement`.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference: the plugin root is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. Tool and hook substitutions for non-Claude-Code runtimes: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md`.

**Detailed contracts:**
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` — canonical tier rubric (Trivial / Small / Medium / Big)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` — the smell-detection sub-step (reuse-vs-create audit per detected smell)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate — the single-finding AskUserQuestion gate
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` § Visual rendering language — the shared visual language for gate messages rendered to chat before a lean question
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` § ADR template — the PRODUCT-DECISION ADR-path (4th AskUserQuestion option, included only when ADR-eligible)

**Phase bodies.** Phase 1's Steps stay in this file; Phase 2 and Phase 3 live in sibling files, Read on entry to that phase and again on any resumption of it, including after a compaction: `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-2-apply.md`, `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-3-verify.md`.

**Section-reference convention:** bare `§N.M` refs point to Phase sub-sections — `§1.M` here in the spine, `§2.M` in `phase-2-apply.md`, `§3.M` in `phase-3-verify.md`; `§ <name>` refs name a section inside the cited `_shared` helper. `refactor-reference.md` numbers its own top-level sections 1-3 (State machine / Schema / Spawn template), so any Phase reference there is written `Phase N §N.M` to avoid colliding with those.

---

## Your role — restructure, don't ship

You refactor. You validate behavior preservation. You do NOT commit or push the diff. Phase 3 endpoint is a working-tree diff (the deliverable) + a chat completion summary + state.md audit trail. Downstream actors (user `git commit`, `/geniro:implement` to ship through review gate) handle the actual ship. Running under a dynamic `Workflow(...)` or ultracode mode does not relax this no-ship contract — the reporter boundary, action gate, and state-write rules bind inside every workflow step per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.

The zero-behavior-change guarantee is enforced per-step via the orchestrator-inline regression test gate AND post-execution via the final regression run.

---

## State machine

state.md `phase:` enum: `plan` → `apply` → `verify` → `done` (happy path). Terminal states: `done`, `verify-summary-only`, `reverted`, `aborted`, `routed`, `adr-documented` (SessionStart recovery treats all six as "task complete — no resume needed"). Escalation states: `plan-escalated` (hard signal OR baseline red), `apply-escalated` (≥30% blocked), `verify-escalated` (PRODUCT-DECISION or 1-round fix-loop exhausted). Recovery surfaces escalation states as "task was paused — your previous options:" so the user re-picks without losing context.

Full ASCII state diagram in `${CLAUDE_PLUGIN_ROOT}/skills/refactor/refactor-reference.md` §1.

**After a compaction, re-Read the current phase's body file before continuing it** — only a skill's front-loaded prefix is re-attached after a summary, so a mid-run summary can drop the Steps while leaving this spine intact. state.md `phase:` says which file that is.

---

## Loop invariants

The canonical loop invariants 1-7 (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply, with three refactor-specific bindings:

- **Invariant #4 (bounded structured tool results)** — orchestrator-inline execution writes per-step status and blocked-step reasons to state.md `## Plan steps`; total file body capped at ~8K chars via atomic_state_write truncation marker.
- **Invariant #5 (escalation gates, not silent abort)** — ≥30% blocked AUQ + PRODUCT-DECISION always waits for the user.
- **Invariant #7 (errors → structured observations)** — per-step blocked rationale, baseline validation failure, and reviewer CRITICAL findings all become structured `## Tool log` / `## Errors` entries.

This skill adds one invariant:

8. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**Turn-completion check.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check at every gate — the render is followed immediately by its lean `AskUserQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard.

`## Tool log` schema: typical run produces 3-6 entries (reviewer-agent + custom reviewers + escalation entries; smell detection and per-step execution run orchestrator-inline and emit to state.md `## Plan steps` directly).

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This smell is too small to fix" | If the plan says fix it, fix it. Small smells compound. |
| "I'll batch multiple transformations" | One atomic transformation at a time. Always. The per-step regression gate exists to catch behavior drift on the smallest possible unit. |
| "Tests are passing so I'll skip the blocked step protocol" | The protocol exists for the NEXT failure. Follow it — Phase 2 §2.2 Blocked Step Protocol applies to ALL transformations regardless of prior-step success. |
| "This refactoring needs a behavior change" | Then it's not a refactoring. Use `/geniro:implement` instead. The zero-behavior-change guarantee is non-negotiable. |
| "This duplication needs a new shared helper" | Run the Existing Abstraction Audit first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md`. If a utility / service / hook already exists nearby that could absorb this duplication via a small extension, prefer extending it. Only create a new shared helper when no analogue exists OR when extending the existing one would require adding a parameter or conditional that complicates it (Rule of Three). |
| "All detected smells are real issues" | Generic smell categories flag intentional repo patterns. Without filtering against THIS repo's conventions via Phase 1 §1.5 smell evidence + KEEP/FILTER synthesis matrix, you'll refactor code that was designed that way on purpose. |
| "I'll spawn agents one at a time" | All parallel agents MUST be spawned in ONE response — multiple Agent calls in the same assistant turn. Separate turns = no concurrency, full wall-clock latency per agent. |
| "I noticed a bug mid-refactor, I'll fix it" | That's feature work. Note it for `/geniro:implement` and stay in refactor scope. The zero-behavior-change guarantee applies even when the in-scope behavior is buggy. |
| "Reviewer flagged a `[PRODUCT-DECISION]` finding — I'll route it through the fix loop like any other CRITICAL/HIGH" | A `[PRODUCT-DECISION]` finding has multiple valid resolution paths by definition — picking one is a behavior change, which contradicts refactor's zero-behavior-change guarantee. Phase 3 §3.3 disposition logic ESCALATES PRODUCT-DECISION to `/geniro:implement` (always-WAIT) — never gates-and-fixes them in-skill. If you find yourself orchestrator-inline editing for a PRODUCT-DECISION finding, that's the rationalization. Stop and route the escalation. |
| "Auto-promote a recorded discovery into a project rule when refactor completes." | Phase 3 §3.5 offers to capture it via `/geniro:instructions create` and only when the same pattern has recurred (`recurrence_count >= 3`) — do NOT auto-write the rule. The user authors and curates project rules; auto-promotion creates noise + drift. |
| "The revert step needs `git checkout -- .` / `git restore .`, but the guard blocks it — I'll bypass the hook or run `git stash`." | The guard is blocking a mass discard, not the revert. Use the targeted form § Git constraint defines; a bypass or `git stash` reaches the same uncommitted work the guard exists to protect. If some other guardrail blocks legitimate refactor work, the path is `.geniro/safety.json` `allow_patterns`, not `--no-verify`. |
| "PRODUCT-DECISION 4-option AUQ is paternalistic — collapse to 2 options (run /geniro:implement / accept-as-is)." | Phase 3 §3.3 is explicit: 4 fixed options when ADR-eligible (3 otherwise). The ADR path captures rejection rationale durably; the Revert path is a user-controlled safety net. Collapsing removes meaningful agency. |
| "Trivial tier should still run a quick reviewer-pass — what if a smell slipped through?" | Trivial is by definition 1-2 files, mechanical, single module, unambiguous. The diff-sanity check in Phase 3 §3.1 + the baseline regression in Phase 2 §2.4 catch behavioral drift. Running a full reviewer-agent batch for a 5-line rename wastes tokens. Tier behavior is intentional. |

---

## Budgets — quality-first

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Budgets — quality-first (canonical). This skill's own gates:

**Quality gates (escalate to user, do not abort):**

| Gate | Cap | Past threshold |
|---|---|---|
| Per-step retry (orchestrator-inline Blocked Step Protocol) | 3 | Mark BLOCKED, continue to next step |
| Session-level blocked ratio | 30% (post-rejection denominator) | AUQ — keep what worked & escalate / revert / force-continue. User picks. |
| Phase 3 fix-loop | 1 round | Re-spawn reviewer once; if still failing, AUQ (escalate / accept / abort). |
| Reviewer output size | the per-dimension report cap in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output cap | Truncation with marker (canonical invariant #4). |

**Architecture constraints (design intent, not budget):**

| Constraint | Value |
|---|---|
| Parallel reviewer spawns | 1 independent + N custom reviewers |
| Smell-detection rounds | 1 (orchestrator-inline) |
| Smell-evidence filter rounds | 1 (Medium+ only) |

---

## Subagent model tiering

OMIT `model=` at every plugin-agent spawn site, per the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Spawn plugin-defined subagents (reviewer-agent, custom reviewers) through the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (`geniro:<agent>` → bare `<agent>` → `general-purpose` with body inlined); cache the resolved rung for the rest of the session.

Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site — every Agent prompt satisfies the six pre-inlined fields, because a spawn missing a field makes the subagent re-discover scope from scratch and drift.

| Spawn | Tier | When |
|---|---|---|
| Orchestrator-inline execution (any risk) | Orchestrator's model | Smell detection + per-step execution run on orchestrator's main thread (no subagent — no tiering decision) |
| Independent reviewer-agent + custom reviewers | inherit (OMIT `model=`) | Phase 3 diff review (Medium+ tier only); inheritance lets the user's session-level `/model` choice propagate |
| Focused ADR-drafting agent | inherit (OMIT `model=`) | ADR path (only fires if ADR-eligible PRODUCT-DECISION) |

## Agent failure handling

If a delegated agent fails (timeout, error, empty/garbage result): retry once with the same prompt. If the retry also fails, the **Phase 3 reviewer batch** (reviewer-agent + custom reviewers) is fail-open — note the failure in the completion summary, proceed, and warn the user that independent review did not complete.

---

## Evidence Standard

Cite the canonical rule at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. /geniro:refactor applies it at baseline validation, the per-step regression gate (orchestrator-inline pre/post-check), and the final regression run.

---

## Universal rule: all choice questions use AskUserQuestion

Route every user-facing choice in this skill through the `AskUserQuestion` tool per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions, which owns the rule and the reason. The gates enumerated below are this skill's, not the complete set.

---

## ACI per-phase tool surface

**Phase 1 (Plan):**
- Allowed: Read / Grep / Glob / Bash (read-only — `git status`, `git log`, `git diff`, `git branch --show-current`, test suite invocation for baseline).
- Allowed Agent spawns: `codebase-research-agent` for wide cross-file locator queries during smell detection (§1.4). smell detection + smell evidence otherwise run orchestrator-inline.
- Explicitly blocked: production-source Edit/Write, `git commit`, `git push`, `gh pr create`.

**Phase 2 (Apply):**
- Allowed Agent spawns: none. Per-step execution runs orchestrator-inline (Edit + Bash for tests).
- Orchestrator uses Edit / Write / Bash (test cmd) directly. Per-step regression runs via backpressure helper.
- Explicitly blocked at orchestrator level: `git add`, `git commit`, `git push`, `gh pr create`, branch switching.

**Phase 3 (Verify):**
- Allowed: Read / Grep / Glob / Bash (`git diff --name-only`, `git diff --stat`, test cmd for re-runs) / Edit (fix-loop-scoped — the §3.3 1-round CRITICAL/HIGH non-PRODUCT-DECISION fix applies findings inline).
- Allowed Agent spawns: reviewer-agent + custom reviewers (Medium+ only), focused ADR-drafting agent (if PRODUCT-DECISION ADR path picked).
- Allowed: targeted per-file revert per § Git constraint — the one orchestration-level exception to the git-write constraint.
- Explicitly blocked: `git commit`, `git push`, `gh pr create`.

**All reviewer / custom reviewer spawns are pure read-only:** tool whitelist via `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` frontmatter (Read / Grep / Glob / Bash for read-only checks).

The safety hooks apply across ALL phases; the complete list and what each blocks is in `${CLAUDE_PLUGIN_ROOT}/HOOKS.md`. Runtime denies stay enforced.

---

## Git constraint

Do NOT run `git add`, `git commit`, or `git push`. The orchestrating workflow handles version control. Exception: revert a failed transformation in Phase 2 / Phase 3 with a targeted `git restore --source=HEAD -- <each changed path>`, listing only the specific paths the step touched — this is an orchestration-level revert, not a version-control operation. Never reach for a bare `.` or `*` pathspec (`git checkout -- .` / `git restore .`): the git-guardrail hook blocks the mass-discard form because it would wipe every uncommitted change, including work outside the current step.

---

## Memory I/O schedule

| Phase | Helper | Direction | MODE |
|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `refresh` |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` |
| Phase 1 entry | `query-learnings` | read L2 | n/a |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a |
| Phase 1 entry (conditional) | spec.md frontmatter `workflow_refs[]` | read external | fires only when `$ARGUMENTS` points to spec.md or task-dir; cached tracker `status` primes scope decisions |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` (single re-fire) |
| Phase 3 exit | `emit-learning` | write L2 | n/a (emit types: `discovery` with `ext.{area, insight}` OR `pitfall` with `ext.{trap, mitigation}`) |

`update-semantic` writes to `_CODEBASE_MAP.md` for move/rename refactors (bounded auto-incremental write). Not applicable when refactor adds modules (would be a behavioral change → escalate to `/geniro:implement`).

---

## Definition of done

These are the load-bearing exit gates and safety invariants — the checks that, if skipped, break the zero-behavior-change guarantee or the no-ship boundary. Per-phase mechanics (tier classification, smell detection, plan building) live in their phase sections; this is the final correctness/contract check, not a re-listing of every step.

- [ ] Tests green before AND after the run — baseline captured (Phase 1) and final regression run captured as an Evidence Block (Phase 2 §2.4); the zero-behavior-change guarantee held
- [ ] PRODUCT-DECISION findings escalated to `/geniro:implement` (always-WAIT), never fixed in-skill
- [ ] CRITICAL/HIGH non-PD findings → 1-round fix loop; past that → "Findings remain" AUQ
- [ ] ≥30% blocked → stuck AUQ fired (user picks; never silent abort)
- [ ] L2 emit fired with `discovery` or `pitfall` type + required `ext.*` fields; rule-capture offer fired when `recurrence_count >= 3` (after dedupe check), decline logged via `emit-rejection.sh`
- [ ] No `git commit` / `git push` / `gh pr create` — diff stays uncommitted (user or /geniro:implement ships)
- [ ] Cleanup completed

---

## Phase 1 — plan

state.md `phase: plan`. Light by cost vs Phase 2 — a scope-discovery batch (Read + Grep) + 1 baseline validation run + orchestrator-inline smell detection (Medium+) + orchestrator-inline smell evidence (Medium+) + orchestrator plan-build.

Exits to Phase 2 only when: (a) baseline validation green, (b) tier classified, (c) hard signals checked, (d) smells identified (Medium+) + smell-evidence filtered (Medium+), (e) plan built and approved (HIGH-risk steps gated).

### 1.1 Memory layer load (instructions / snapshot / learnings)

On Phase 1 entry, in order:

1. **Refresh custom instructions** — `load-custom-instructions(MODE: refresh, scope: refactor + global + code-style — pipeline tier, 3 files)` per Echo contract.
2. **Refresh project snapshot** — `load-semantic(MODE: refresh, top-2 default)` — `_project.md` + `_CODEBASE_MAP.md`. Fingerprint drift check fires if applicable.
3. **Query past learnings** — `query-learnings(tags=<inferred from $ARGUMENTS>, scope=task path)` to find prior discoveries about coupling, pitfalls, and conventions relevant to the refactor scope — route per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (under a declared `## Memory Backend` block routing `learnings`, /geniro:refactor's own tools can't call the backend read tool, so it delegates that read to a scoped `knowledge-retrieval-agent` spawn — `SCOPE: learnings-backend` — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md` §3 and uses the returned learnings; the local file is empty under `mode: replace`; no block → the inline file query runs unchanged).
4. **Cross-layer conflict resolution** — `resolve-conflicts` with all three layers loaded; precedence: custom instructions > project snapshot > past learnings when layers disagree; halt with AUQ on hard conflict. Echo lines from each loader are mandatory per its §Echo contract.
5. **Workflow refs read (when spec.md is in scope).** When `$ARGUMENTS` points to a spec.md path OR a planning task-dir, parse spec.md frontmatter `workflow_refs[]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md` — that file owns which schema versions a reader accepts and the rule that every consumer but /geniro:implement is tracker-read-only. Use the cached `status` field as scope-priming context — refactor scope decisions favor "still In Progress" specs (active editing area) over "Done" specs (stable code, smaller perturbation surface). On `m5-v3` the cached parent-epic status and sibling sub-task statuses also prime scope decisions (e.g. an in-flight sibling touching the same module argues for a smaller perturbation surface). Skipped silently when no spec.md is in scope.
6. **Branch freshness.** On a fresh run (skip on compaction-resume), apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` — /geniro:refactor applies changes in place on the current branch, so if that branch is behind the default branch, offer to update it before scope discovery and baseline validation run against stale code. Skipped silently when the branch is already current.

### 1.2 Scope discovery + baseline + coverage check

1. **Parse `$ARGUMENTS`** to understand what is being refactored and why.
2. **Find all related files** with the project's code-search tooling (follow the project's search policy from `global.md` — reach for its code index when one is configured). Read all files in scope to understand current organization, dependencies, imports, and test coverage.
3. **Prior-planning context.** Scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. Check: `.geniro/planning/*/` (task-local), workflow files (cwd-first, then `<PRIMARY_ROOT>/.geniro/workflow/*.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A), `<PRIMARY_ROOT>/.geniro/knowledge/learnings.jsonl` (search for scope-file keywords — a different query from §1.1's inferred-tag query, routed through the same memory-backend delegation), and git state (worktree root, current branch, recent commits, working-tree status).
4. **Read project convention files** referenced in CLAUDE.md.
5. **Baseline validation** — run the project's validation suite once (read command from CLAUDE.md). Capture as an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. Outcomes:
- **Red:** `AskUserQuestion` header "Baseline" — "Fix the broken tests first (stop refactoring)" / "Proceed anyway — existing failures are out of scope (risky)". Default: stop. state.md → `phase: plan-escalated`.
- **No tests exist:** escalate immediately — "Cannot refactor safely without tests. Use `/geniro:implement` to add coverage first." state.md → `phase: routed` (terminal).
- **Green:** record passing-state fingerprint (test count) in state.md `## Baseline` body section; proceed.
6. **Coverage check on the symbols in scope.** Check whether each function/symbol in scope has at least one test exercising it — the zero-behavior-change guarantee is only as strong as the tests locking current behavior. A gap is the "new tests required to cover untested code" hard signal in §1.3.2; carry it there rather than authoring the missing test here, because a test authored now would be a characterization test that passes on current code (not a test-first cycle), and §1.3.2 lets the user decide whether the symbol belongs in scope at all. If every scope-symbol already has coverage, skip silently.

### 1.3 Tier classification (canonical effort-scaling)

**Apply the canonical effort-scaling rubric** from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`: Step 1 (hard signals) → Step 2 (5-dim score) → Step 3 (tier behavior). Refactor-specific hard signals apply orthogonally — they escalate OUT of /geniro:refactor entirely.

#### 1.3.1 Apply canonical effort-scaling

1. **Steps 1-2 (canonical):** run the hard-escalation-signal check (Step 1) and the 5-dimension 0-10 score → tier band (Step 2) exactly as defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`. Any hard signal forces Big; otherwise the score band sets the tier (Trivial / Small / Medium / Big). effort-scaling.md is the single source — do not restate the signals or bands here.
2. **Step 3 (refactor-specific tier behavior):**

| Tier | Refactor behavior |
|---|---|
| **Trivial** | 1-2 files, mechanical (rename, single extract). Skip smell detection. Skip the smell-evidence filter. Skip independent reviewer + custom reviewers. Orchestrator authors the plan directly from $ARGUMENTS + scope-files Read; goes straight to Phase 2 execution. |
| **Small** | Full smell detection in Phase 1 BUT skip smell evidence (scope too narrow to matter). Skip independent reviewer + custom reviewers. |
| **Medium** | Full pipeline as specified — orchestrator-inline smell detection + orchestrator-inline smell evidence + reviewer-agent + custom reviewers. |
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

The orchestrator runs the 6 smell detection categories + Deepening Opportunities lens inline — no subagent spawn, for the state-continuity reason spelled out at Phase 2 §2.2. For wide cross-file locator queries that would otherwise require many inline Reads (e.g., "find all definitions of the duplicated helper across the repo"), spawn `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research. The smell-evidence pass itself stays orchestrator-inline so state continuity and the per-step regression-skip predicate are preserved.

**Reference:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` Phase 1 — full smell taxonomy + change-impact scoring + escalation rules. The orchestrator reads this file once at entry and applies the rubric inline.

**Per-smell procedure:**

1. Apply the 6 smell categories (duplication / long methods / god classes / dead code / tight coupling / type+import issues) via Read + the project's code-search tooling against the FILES IN SCOPE from Phase 1 §1.2.
2. Apply the Deepening Opportunities lens — read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/architecture-vocabulary.md` first for vocabulary grounding, then scan for wide-interface shallow modules / pass-through wrappers / repeated cross-call orchestration / high-leverage shallow code.
3. For every detected smell, run the canonical **Existing Abstraction Audit** at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` — apply its Procedure (search designated helper directories, categorize REUSE-AS-IS / EXTEND / NO-ANALOGUE, force-fit guard, Rule of Three). Emit candidates inline alongside each smell using the audit's Output format.
4. Count consumers per smell with the project's code-search tooling (a code index returns dependents directly when configured; otherwise a count-mode structured search), scoped by language (`*.ts` / `*.py` / etc).
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

Risk classification (LOW / MEDIUM / HIGH) and ordering happen in §1.6 (orchestrator decisions, not the smell-detector's job).

Anchor: stay within WORKTREE on BRANCH — orchestrator verifies with `pwd && git branch --show-current` once at entry; abort if either differs.

### 1.5 Orchestrator-side smell evidence — keep or filter each smell

Skipped for Trivial and Small. The orchestrator gathers evidence on detected smells against repo conventions inline — no subagent spawn (folded under subagent rationalization; light reasoning that fits orchestrator's main context cleanly should not be spawned).

For each smell detected in §1.4, the orchestrator weighs three signals inline:

1. **Convention alignment** — is this "smell" actually the repo's chosen pattern? Cross-check with CONTRIBUTING.md, ADRs at `docs/adr/`, architecture docs (when present) and CLAUDE.md.
2. **Over-engineering** — would fixing this smell introduce more complexity than it removes? Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md` mental check.
3. **Intentional pattern** — does the flagged pattern exist deliberately in 3+ other files? A quick search over similar paths confirms.

Synthesis matrix per smell:

| Convention | Complexity | Frequency | Decision |
|---|---|---|---|
| ALIGNS | * | * | FILTER (repo's chosen pattern) |
| CONTRADICTS | OVER-ENGINEERED | * | FILTER (cure worse than disease) |
| CONTRADICTS | APPROPRIATE | WIDESPREAD | FILTER OR consult user (intentional rather than smell) |
| CONTRADICTS | APPROPRIATE | ISOLATED | KEEP (genuine smell) |
| NEUTRAL | APPROPRIATE | ISOLATED | KEEP (default) |

KEEP smells enter plan-build. FILTERED smells are noted in state.md `## Filtered smells` section with the synthesis reason. No fail-open caveat needed — dedup and judgment run in orchestrator's main context.

### 1.6 Risk classification, plan build, and approval

Orchestrator builds the plan from the smell-evidence inline output (Medium+) or directly from scope-files (Trivial/Small):

1. **Classify risk per smell** using the consumer-count table in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refactor-patterns.md` Phase 1 § "Step 2: Change Impact Scoring" (public API / module export / shared-type change is HIGH regardless of consumer count).
2. **Order the plan**: safer transformations first (LOW → MEDIUM → HIGH). Within the same tier, group by file to minimize re-reads.
3. **Mark HIGH-risk steps for user confirmation** (gated via the approval gate below).
4. **Build the final plan** with: smells, ordered steps, risk per step, consumer counts, files that will change, what will NOT change (public APIs, DB schema, test behavior), `max_risk` (max across all step risks).

**Approval gate (Always-WAIT):** If any steps are **HIGH risk**, gate them in two steps — render first, then ask — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering (separate-message rule, render-exists check), with the pre-fire scrub per the same contract's § Single-finding gate, "Scrub before the AUQ fires", using the elements from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` § Visual rendering language:

1. **Render the HIGH-risk step plan to ONE chat message first.** Skip the progress tracker — this is a single gate, not a decision queue. Open with `**In one sentence:**` stating what is being approved (the higher-risk transformations in this refactor plan, before any edit runs). Then, with a light icon on each heading:
   - **Steps flow diagram** over the FULL ordered plan (`step 1 ▸ step 2 ▸ step 3 …`), HIGH-risk steps marked (e.g. `⚠ step 3`), so the user sees where the gated steps sit in the run.
   - **Per HIGH-risk step, a friendly digest block:** a lead sentence naming the transformation and the file in plain words; `**Why it matters:**` with the consumer count and evidence cite (`path:lines`); and the expected behavior-preservation check — which test run proves the step changed nothing observable.
   - **Per HIGH-risk step, the risk mini-table:** risk · symptom you'd see · severity (the "Refactor step set" row of per-finding-question.md § Finding-type visual map).
2. **Then fire ONE lean `AskUserQuestion`** (header "Approve HIGH-risk steps", conventions per gate-rendering.md § Lean-question conventions) and wait for confirmation: approve all HIGH-risk steps, or reject specific steps (rejected steps are skipped in Phase 2; on that pick, run a follow-up multi-select picker over the HIGH-risk steps per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Multi-select pick loop). One question covers the whole HIGH-risk set; per-step grain lives in `approvals[]`, not in extra questions.

**Approvals-persistence:** before firing, check state.md frontmatter `approvals[]` for prior entries with `category: refactor_high_step` matching the current step. Use prior `picked` if found. On user pick, append one entry per HIGH-risk step the pick covers via `atomic_state_write` — per-step grain unchanged even though one question covers the set. The persisted-approvals render surfaces these on resume.

If all steps are LOW/MEDIUM: present the plan summary in chat and proceed (no AUQ).

state.md transitions: `plan` → `apply` once approval complete. `## Plan` body section with full plan; `## Persisted approvals` rendered from `approvals[]`.

---

## Phase 2 — apply

state.md `phase: apply`. The orchestrator executes the approved plan one step at a time, each transformation gated by its own regression run. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-2-apply.md`** — it carries the Steps (§2.1 instruction refresh · §2.2 per-step execution and the Blocked Step Protocol · §2.3 the ≥30%-blocked escalation · §2.4 final regression + the retry-exit emit), and every `Phase 2 §2.M` citation in this skill resolves there. Exit: `phase: verify` on a green regression run, `phase: apply-escalated` at the blocked cap, `phase: reverted` when the user reverts.

---

## Phase 3 — verify

state.md `phase: verify`. Diff sanity + independent review + completion summary + L2 emit + cleanup. **On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/refactor/phase-3-verify.md`** — it carries the Steps (§3.1 diff sanity · §3.2 the reviewer batch · §3.3 disposition, including the PRODUCT-DECISION escalation and the ADR path · §3.4 completion summary · §3.5 learnings · §3.6 cleanup), and every `Phase 3 §3.M` citation in this skill resolves there. Exit: a terminal state — `done`, `verify-summary-only`, `reverted`, `routed`, `adr-documented`, or `verify-escalated` when the 1-round fix loop exhausts. No `git push` / `gh pr create`: refactor never ships code, only a working-tree diff and a state-file audit trail.

---

## State file schema

T1.5 state.md at `.geniro/state/refactor/<slug>/state.md`; `approvals[]` categories `refactor_high_step`, `refactor_product_decision`; `effort_tier` ∈ {Trivial, Small, Medium, Big}. `## Plan steps` holds the per-step execution rows (schema at Phase 2 §2.2), distinct from `## Plan` which holds the ordered plan summary. No T2 handoff — diff IS the deliverable. Full frontmatter + body-section schema in `${CLAUDE_PLUGIN_ROOT}/skills/refactor/refactor-reference.md` §2.

---

## Task tracking

Use `TodoWrite` to expose per-phase progress. At skill start, create phase-level todos: Plan, Apply, Verify. During Phase 2, add dynamic per-step todos derived from the approved plan. Mark `in_progress` → `completed` as phases run. At most ONE todo is `in_progress` at a time.

---
