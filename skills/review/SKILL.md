---
name: geniro:review
description: "Use when you want а comprehensive code review of pending changes. М6 6-phase loop (triage → mechanical pre-pass → 9-dim LLM reviewers → filter → stratify → persist → action-gate). Reporter behavior — emits а T2 hand-off at .geniro/state/handoff/from-review-<branch>.md; downstream consumers (/implement, manual) apply fixes. Optional --simplify flag folds Reuse/Quality/Efficiency criteria into existing dims. Optional --tdd flag tightens Phase 4b validation + Phase 4c test-gate."
context: main
model: inherit
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent, AskUserQuestion, WebSearch, EnterWorktree, ExitWorktree]
argument-hint: "[files, diff range, branch, or PR ref (#N, URL)] [--plan <path>] [--tdd] [--simplify]"
---

# Code Review Skill (M6)

Comprehensive code review using parallel multi-agent analysis. ~400 lines orchestration shell + reference files.

**Architecture spec:** `architecture/M6-review-redesign.md`. Detailed phase contracts:
- `${CLAUDE_SKILL_DIR}/phase-1-triage-reference.md` — Phase 1 input mode / scope / risk-tier / memory load.
- `${CLAUDE_SKILL_DIR}/phase-4c-test-gate-reference.md` — Phase 4c test-confirmation gate.
- `${CLAUDE_SKILL_DIR}/phase-6-handoff-reference.md` — Phase 6 action-gate hand-off + Post drill.
- `${CLAUDE_SKILL_DIR}/plan-context-reference.md` — M5 schema-aware PLAN CONTEXT load (D2 fix).
- `${CLAUDE_SKILL_DIR}/incoming-mode-reference.md` — INCOMING mode (PR review-feedback processing).
- `${CLAUDE_SKILL_DIR}/tdd-mode-reference.md` — `--tdd` flag semantics.

---

## Your Role — Orchestrate, Don't Review

You are а **coordinator**. You delegate review work к `reviewer-agent` instances via the Agent tool и validate their outputs в the judge pass. You do NOT review code yourself — you read files only к gather context и verify agent findings.

`/geniro:review` is а **Reporter** (M6 H-2) — it does NOT apply fixes. Phase 6 hand-off message NEVER includes «I'll fix these now» language. Findings persist к а T2 hand-off; downstream consumers (`/implement`, manual user action) apply fixes. The `--simplify` flag does NOT change this.

---

## State Machine (M6 §2.1)

State.md `phase:` enum transitions:

```
[entry] → triage → mechanical-prepass → llm-spawn → filter → stratify → persist → action-gate → done
                                                                                       │
                                                                                       ├── escalated ── (round-N user pick)
                                                                                       └── aborted   ── (round-limit / safety / tool-unavailable)
```

**Terminal states:** `done`, `aborted`. M3 SessionStart recovery treats both as «review complete / cancelled». `done` includes а Phase 6 hand-off line.

**Non-terminal states:** `triage`, `mechanical-prepass`, `llm-spawn`, `filter`, `stratify`, `persist`, `action-gate`. М3 recovery rolls these back к phase-entry и re-runs от there (idempotent — `approvals[]` ensures Phase 6 AUQ skips already-answered).

**Termination-case mapping** per M6 §2.1.1 — see Phase 6 reference for the full table. The `## Termination reason` body section is written on `aborted` / `escalated` terminals.

---

## Loop Invariants (M6 §2.2)

М4 §2.2's 7 invariants apply unchanged:

1. **One result per tool call.** Phase 2 parallel-spawn reviewer-agents — each must return а structured result; dead spawn → `status: failed` entry в `## Tool log`.
2. **Args validated before execution.** `$ARGUMENTS` flag parsing (semantic, no CLI grammar); PR ref validation via `mcp__github__pull_request_read` или GraphQL fallback.
3. **Permission before side-effect.** Phase 6 «Post Draft PR» requires AUQ approval before `mcp__github__pull_request_review_write`. State.md writes via M1 `atomic_state_write`.
4. **Bounded и structured tool results.** Reviewer-agent output ≤4000 chars per dim; truncation marker. Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.
5. **Escalation gates, not silent abort.** Round-N ≥3 → Phase 6 escalation gate.
6. **Final answer grounded в observations.** Phase 6 hand-off message MUST cite the state.md path; finding bodies MUST include Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`.
7. **Errors → structured observations.** Reviewer spawn failures → `## Errors` body section. `gh` fail-open NOT silent — log к `## Errors`.

`## Tool log` schema: typical run produces 5-12 entries (1 per reviewer + 1 per Phase 5b emit-learning + 1 per PR-side-effect).

---

## Budgets — Quality-First (M6 §2.3)

М6 has **NO hard kill caps**. Same model as M4 / M5.

**Quality gates (escalate к user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Round-N reviewer re-spawn | 3 | Phase 6 Round-N gate | AUQ — debug-handoff / continue / abort. User picks. |
| Reviewer output size | ~4K chars per dim | §2.2 invariant #4 | Truncation marker, not abort. |
| Phase 3 dedup pass | 1 per round | Phase 3 | Orchestrator-inline (no subagent — folded under subagent rationalization). Cannot «fail» — runs in orchestrator's main context. |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| LLM reviewer spawn count | 5-9 в parallel | §8 dimension count (9 max after guidelines+conventions collapse) |
| Mechanical pre-pass tools | 3 (lint / schema / secret scan) | Phase 1.5 |

**Explicitly NOT capped:** wall-time, total tool calls, total model turns, total cost. Same rationale as M4 §2.3.

---

## Subagent Model Tiering

Follow the canonical rule в `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Every `Agent(...)` spawn MUST pass `model=` explicitly. For plugin-defined subagents (reviewer, relevance-filter, adversarial-tester), also follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — registration ladder (`geniro-claude-plugin:<agent>` → bare `<agent>` → `general-purpose` с agent body inlined). Cache the resolved rung для the rest of the session.

Co-cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at every spawn site — every Agent() prompt MUST satisfy the six pre-inlined fields.

| Spawn | Tier | Why |
|---|---|---|
| `reviewer-agent` (bugs, security, architecture, tests, optimizations, conventions, design, pr-metadata, spec-compliance) | `sonnet` | Reasoning-heavy review |
| `reviewer-agent` (guidelines) | `haiku` | Rubric-based — pattern matching against checklist |
| `adversarial-tester-agent` (Phase 4c only) | `inherit` | Reasoning-grade test authoring |
| Per-finding validation sub-agents (CRITICAL/HIGH) | `inherit` | Reasoning-grade verification |

---

## Phase 1 — Triage & Context Collect

State.md `phase: triage`. **Full contract:** `${CLAUDE_SKILL_DIR}/phase-1-triage-reference.md`.

Summary of what Phase 1 does:

1. **Input mode detect** — OUTGOING / INCOMING / pr-ref routing per `$ARGUMENTS`. Anchored NL signals («process review on #N») route к INCOMING; PR ref + K>0 unresolved threads fires Mode AUQ.
2. **Scope resolution** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. NEVER invoke `gh pr list` к invent а target.
3. **PR-ref parsing** — `gh pr diff` + `gh pr view --json baseRefName,headRefName,body,title,headRefOid,url,isDraft,author,labels`.
4. **Workflow integrations** (§3.5) — read `.geniro/workflow/*.md`, apply tracker-ID regex against `$ARGUMENTS` + `pr.title` + `pr.body`. On Linear match с MCP available: fetch issue (+ parent epic + sibling sub-tasks). Build `LINEAR CONTEXT:` block. Persist `linear-task-ref:` + `linear-parent-ref:` к state.md frontmatter. Fail-open if MCP unavailable.
5. **Peer-PR scout** (PR-ref only) — top-10 sibling PRs scored by file overlap + Linear-relatedness bonus (parent-epic / sibling-sub-task matches); inlined into 6 reviewer prompts (architecture + design + bugs + conventions + optimizations + spec-compliance).
6. **Worktree pre-flight** (PR-ref only) — 3-branch routing (already-in-target / different-worktree / outside) per the reference file.
7. **Step 0 — Load custom instructions** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` (MODE: initial-load; scope=`review`+`global`+`code-style`+`user-preferences` — M10b pipeline tier, 4 files).
8. **Step 0.5 — Round-N counter** — increments and fires Round-N AUQ когда round ≥3.
9. **Step 0.6 — PLAN CONTEXT load (M5-aware).** Detection per `${CLAUDE_SKILL_DIR}/plan-context-reference.md` §2. Structured-section parser когда `geniro_kind: design-doc` frontmatter present; prose fallback otherwise.
10. **Step 0.7 — Risk-tier stratification** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` 9 hard-escalation signals. Sets `risk-tier: standard | high`. Adjusts 4 downstream knobs (severity threshold / validator budget / spec-compliance default / NEW: mechanical secret-scan strict mode).
11. **Step 0.8 — Memory layer load (M2):** `load-custom-instructions` MODE:refresh + `load-semantic` MODE:refresh + `query-learnings` (top-K, K=5 default) + `resolve-conflicts`.
12. **Mode AUQ** (Standard vs TDD) когда neither `--tdd` nor `--standard` в `$ARGUMENTS`. Persist к `approvals[]` с category `tdd_mode_choice`.
13. **Size triage** — classify files Trivial / Substantive когда diff >8 files или >400 LOC. Controls Phase 2 Standard vs Batched mode.

Exit criterion: state.md frontmatter populated с `mode`, `round`, `risk-tier`, `pr-ref`, `linear-task-ref`, `linear-parent-ref`, `plan-context-ref`, `simplify-mode`, all populated; `approvals[]` carries any AUQ answers; `## Tool log` includes initial load echoes.

---

## Phase 1.5 — Mechanical Pre-pass (NEW — P-M6-2 closure)

State.md `phase: mechanical-prepass`.

Three deterministic checks BEFORE LLM reviewer spawns. Cheap-deterministic first; LLM-spawn second с pre-pass findings as prior-context. Sequential, not parallel — LLM agents seeing prior mechanical findings produce better-targeted output (§7.5 rationale).

### 1.5.1 Check 1 — Lint

Probe project for existing lint config: `eslint.config.{js,mjs,cjs,ts}`, `.eslintrc*`, `pyproject.toml [tool.ruff|black|pylint]`, `Cargo.toml [lints]`, `.rubocop.yml`, etc.

If detected, run the project's own lint command (`pnpm lint`, `npm run lint`, `cargo clippy`, `bundle exec rubocop`) с `--quiet` или equivalent. Capture failures as `{tool, file, line, rule, message}` tuples.

### 1.5.2 Check 2 — Schema

Heuristic: if changed files include TypeScript (`*.ts`, `*.tsx`), run `pnpm tsc --noEmit`. JSON schema (`*.schema.json`, `*.openapi.{json,yaml}`) — probe для `ajv` if present. Protobuf — `buf lint` for `.proto` changes. Capture failures.

### 1.5.3 Check 3 — Secret scan

Regex pass against changed-file content:

- `AKIA[0-9A-Z]{16}` (AWS access keys)
- `sk-[a-zA-Z0-9]{32,}` (OpenAI-style keys)
- `-----BEGIN (?:RSA |EC |OPENSSH |)PRIVATE KEY-----` (PEM markers)
- `ghp_[a-zA-Z0-9]{36}` (GitHub personal tokens)

**Risk-tier:high strict mode (D6 NEW knob)** adds:
- `(?:AWS|GCP|AZURE)_(?:SECRET|ACCESS)_KEY=`
- GCP service-account JSON markers (`"type": "service_account"`)
- Azure SAS tokens (`?si=.+&sig=`)
- SSH OPENSSH key patterns

Findings tagged `severity: CRITICAL` (secrets are always critical).

### 1.5.4 Output handling

Mechanical findings tagged `origin: mechanical:<check_id>`. Routed two ways:

1. **К Phase 2 LLM reviewers as prior-context** — pasted into spawn prompts под а `## Mechanical Pre-pass Findings` section. LLM agents instructed к use those as starting points (avoid duplicating; extend с semantic understanding).
2. **К Phase 5 persist** — included в the state.md finding list с the mechanical tag preserved.

### 1.5.5 Fail-handling

If lint или schema check fails (process exit nonzero с no output OR command not found):
- Write `## Errors` entry: `mechanical-prepass-{check_id}: command_unavailable_or_failed`.
- Continue к Phase 2 без the failed check's findings (fail-open, consistent с `gh` fail-open).

Secret scan is а pure-regex pass — cannot fail.

---

## Phase 2 — LLM Reviewer Spawns

State.md `phase: llm-spawn`.

### 2.1 Dimension grid (9 dimensions after §17 collapse)

| # | Dimension | Always? | Conditional trigger |
|---|---|---|---|
| 1 | bugs | always | — |
| 2 | security | always | — |
| 3 | architecture | always | — |
| 4 | tests | always | — |
| 5 | optimizations | always | — |
| 6 | guidelines | always | — |
| 7 | conventions | always | — (owns repo-modal-pattern findings exclusively per §17 H-3) |
| 8 | design | conditional | UI globs match changed files (see UI-file detection rule) |
| 9 | pr-metadata | conditional | `pr-ref:` non-none |
| 10 | spec-compliance | conditional | PLAN CONTEXT non-none AND (`pr-ref:` non-none OR risk-tier:high) |
| +N | custom:* | conditional | per user-authored `review-extra/*.md` files |

«5-9 dimensions per spawn batch» depending on conditions.

**Refresh L4 instructions** at Phase 2 entry — apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` с MODE: refresh. Compaction since the previous load may have silently dropped the rules.

**Discover custom reviewers (Phase 2 entry — before the parallel spawn batch).** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` к discover user-authored review dimensions в `.geniro/instructions/review-extra/<slug>.md`. The helper returns spawn-specs (slug, dimension-label `custom:<slug>`, model, criteria-content, severity-default, source-path) after applying its `paths:` filter against the changed-files list and enforcing the ≤10 cap. For each spawn-spec returned, append one additional `Agent(subagent_type="reviewer-agent", ...)` к the SAME parallel batch as the 7-9 built-ins (one assistant turn, parallel execution — per helper §How consumers use the spawn-specs). If the helper aborts on hard-cap error, surface error + skip the custom additions; built-ins still fire.

### 2.2 Spawn invocation

Single message с N parallel `Agent` tool uses, one per dimension. Each spawn:

- `subagent_type: reviewer-agent` (plugin) — applies `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration ladder.
- `model`: per Subagent Model Tiering table above.
- Pre-inlined context per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`:
  - Diff of changed files (full content for the batch's files в Batched Mode; all files в Standard Mode).
  - Project conventions from L4 (refreshed).
  - **Mechanical pre-pass findings (Phase 1.5) as prior-context** под `## Mechanical Pre-pass Findings` section.
  - PLAN CONTEXT — spec-compliance dim ONLY (other dims see `PLAN CONTEXT: <plan tag fields only>` per the M5 schema-aware reference).
  - **LINEAR CONTEXT** — spec-compliance + pr-metadata + architecture dims ONLY (per Phase 1 §3.5). Block omitted entirely для other dims. Slot value `none — workflow not configured` когда §3.5 was skipped.
  - PRIOR-ROUND FINDINGS (Step 0.5 prior-round-summary, или `none — first review`).
  - **PEER-PR CONTEXT** — architecture + design + bugs + conventions + optimizations + spec-compliance dims ONLY (per Phase 1 §4, expanded от 2 dims к 6).
  - Dimension-specific criteria file body inlined.
  - Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.

**Criteria files** (read once at Phase 2 entry):
- `${CLAUDE_SKILL_DIR}/bugs-criteria.md` · `security-criteria.md` · `architecture-criteria.md` · `tests-criteria.md` · `optimizations-criteria.md` · `guidelines-criteria.md` · `conventions-criteria.md`
- `${CLAUDE_SKILL_DIR}/design-criteria.md` (conditional)
- `${CLAUDE_SKILL_DIR}/pr-metadata-criteria.md` (conditional)
- `${CLAUDE_SKILL_DIR}/spec-compliance-criteria.md` (conditional)
- Custom reviewers via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` (≤10 per project)

### 2.3 `--simplify` flag weighting (P-M6-deep-simplify, §13)

When `$ARGUMENTS` contains `--simplify` (semantic parse — matches `simplify`, `--simplify`, `simplify mode`), Phase 2 prepends deep-simplify criteria onto 5 of the 9 dimensions:

- **architecture** reviewer — Reuse criteria (existing abstractions, duplicate logic, premature abstraction).
- **conventions** reviewer — repo-modal-pattern aggressive mode (lower ≥80% siblings threshold к ≥60%).
- **guidelines** reviewer — Quality criteria (naming clarity, docs noise, dead code).
- **bugs** reviewer — Quality bug-class extensions (defensive code that masks bugs, redundant null checks).
- **optimizations** reviewer — Efficiency criteria (verbose loops, unnecessary allocations, sync I/O в async paths).

Pre-pend body read от `${CLAUDE_SKILL_DIR}/simplify-criteria.md`.

NO new dimensions added. NO fix-loop added (Reporter behavior per H-2). The flag biases existing reviewers' attention; it does not change output schema или hand-off contract.

### 2.4 UI-file detection rule (design dim trigger)

А file is а UI file if path matches `**/components/**`, `**/pages/**`, `**/app/**`, `**/views/**`, `**/ui/**`, OR extension is `.tsx` / `.jsx` / `.vue` / `.svelte` / `.css` / `.scss` / `.sass` / `.less` / `.styled.ts` / `.styled.tsx`. Design dimension skipped когда no changed file matches.

### 2.5 Spec-compliance detection rule

Fires when ALL hold: (a) PLAN CONTEXT is non-`none`; AND (b) either input was а PR ref OR risk-tier:high. Findings carry `File: SPEC-COMPLIANCE` sentinel — Phase 6 Post drill routes them к top-level review `body` under `## Spec Compliance` (not inline comments — no `path:lines` anchor).

### 2.6 Build verification (parallel с reviewers)

Run the project's validation suite в parallel с reviewer agents:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Build Check" "<validation_cmd>"
```

Feed pass/fail into Phase 4 judge. Failing build is automatically а CRITICAL finding — tag `[NEW]` if the base branch build passes, `[PRE-EXISTING]` if already broken.

---

## Phase 3 — Filter & Aggregate

State.md `phase: filter`.

### 3.1 Orchestrator-side dedup + convergence

The orchestrator reads all per-dimension findings (Phase 2 reviewer-agent outputs + Phase 1.5 mechanical findings) and performs dedup inline — no subagent spawn:

- **Dedup key:** `path:line + finding-title` (case-insensitive title match).
- **Convergence_count:** for each dedup'd finding, count how many reviewers + mechanical checks reported the same key. Persisted as а field on the finding (consumed by Phase 5b auto-emit threshold §5.3).
- **Drop hallucinations:** findings without а real file:line correspondence (orchestrator verifies file exists и line is within bounds via Read; if not, drop with а `## Caveats` line citing the dropped finding).
- **Convention context:** orchestrator reads convention files when present — CONTRIBUTING.md, ADRs at `docs/adr/`, architecture docs. These inform §3.3 KEEP/FILTER decisions.

### 3.2 Mechanical+LLM dedup

Mechanical findings (Phase 1.5) и LLM findings may overlap (e.g., lint says «unused import on line 42», bugs reviewer says «dead code on line 42»). Orchestrator-inline dedup identifies overlap by dedup key (§3.1), preserves the mechanical finding (deterministic) + drops the LLM's redundant entry. Convergence_count для that finding gains +1 для the mechanical contribution.

### 3.3 KEEP/FILTER judgment

After dedup, the orchestrator synthesizes per finding: weighs convention-alignment, over-engineering, и pattern-frequency evidence against severity и judges KEEP / FILTER. CRITICAL findings с `safety_override=true` are always KEEP regardless of convention evidence. Pass only KEEP findings к Phase 4. FILTERED appear в the report's `## Filtered` section с reason annotation.

No external agent к fail — dedup и judgment run в orchestrator's main context.

---

## Phase 4 — Stratification & Test Gate

State.md `phase: stratify`.

### 4.1 Phase 4a — severity threshold

Apply risk-tier threshold:
- standard: keep findings с severity ≥ MEDIUM AND confidence ≥ 80%.
- high: keep findings с severity ≥ MEDIUM AND confidence ≥ 70%.

Sub-threshold findings written к а «Deferred» list (surfaced в `## Open Questions` so user knows what was dropped).

### 4.2 Phase 4b — HIGH validator

Sample HIGH-severity findings и validate via а secondary spawn (`reviewer-agent` clone с prompt emphasizing «confirm or refute, не expand»):

- standard tier: validate top-3 HIGH findings.
- high tier: validate ALL HIGH findings.
- `--tdd` flag: validate ALL HIGH findings regardless of tier.

Output: per-finding `validation: confirmed | refuted | partial` field added.

### 4.3 Phase 4c — F→P test gate

**Full contract:** `${CLAUDE_SKILL_DIR}/phase-4c-test-gate-reference.md`.

Summary:
- Filter findings by decision-type per the runtime-behavior classification rule.
- **Mandatory user-approval gate before any `adversarial-tester-agent` spawn.** Skill MUST NEVER spawn без approval — the gate IS the load-bearing safety property. Persist к `approvals[]` с category `test_gate_choice`.
- `--tdd` flag flips the Recommended option к «Author tests for all eligible findings»; gate itself still fires.
- Spawn ONE adversarial-tester-agent с eligible findings as hypothesis seeds. Orchestrator's independent re-run IS the gate; never trust the agent's red/green claim alone.
- Demote-don't-delete: green tests demote findings к `## Filtered` с `[CHALLENGED-BY-TEST]` tag; original severity preserved для re-elevation.
- Fail-open: agent failures surface "test-gate fail-open" под `## Caveats` + write `## Errors` entry.

### 4.4 `--simplify` flag interaction

`--simplify` does NOT change Phase 4 thresholds or validator behavior. P1/P2/P3 simplify severities mapped к CRITICAL/HIGH/MEDIUM tag pool в Phase 3 — they pass through Phase 4 like native CRITICAL/HIGH/MEDIUM findings.

---

## Phase 5 — Persist & Emit

State.md `phase: persist`.

### 5.1 M1-T2 state file write (D4/D9 fix)

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` per M1 §T2 row. `<PRIMARY_ROOT>` resolved per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A.

**Write via M1 `atomic_state_write`** — never direct Edit/Write на the canonical state path (the `enforce-state-helper` hook will warn-mode flag direct writes; PR-final will hard-block).

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write "<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md" <<'EOF'
---
tier: T2
producer: review
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
consumer: implement
geniro_kind: state-handoff
geniro_schema_version: m6-v1
task_slug: review-<branch>
phase: <triage|mechanical-prepass|llm-spawn|filter|stratify|persist|action-gate|done|aborted|escalated>
status: <in-progress|done|failed>
mode: <standard|tdd>
round: <int>
risk-tier: <standard|high>
pr-ref: <owner/repo#num|null>
pr-url: <https://...|null>
pr-head-sha: <40-char SHA|null>
pr-title: <verbatim title|null>
pr-body: <verbatim body|null>
plan-context-ref: <abs-path|null>
linear-task-ref: <ENG-123|null>
linear-parent-ref: <ENG-100|null>
simplify-mode: <true|false>
resolved-threads-snapshot: [<path:line entries|null>]
approvals: []
non-resumable-actions: []
---

# Review: <topic / branch>

## Summary
- Branch: <branch>
- Mode: <standard|tdd>
- Round: <N>
- Risk-tier: <standard|high>
- Dimensions spawned: [<list>]
- Mechanical pre-pass: [lint:N, schema:M, secrets:K]
- Finding totals: CRITICAL=<X>, HIGH=<Y>, MEDIUM=<Z>

## Findings

### CRITICAL
<list>

### HIGH
<list>

### MEDIUM
<list>

## Deferred — sub-threshold
<list, surfaced for user awareness>

## Tool log
<per M3 §6 Block 2 — reviewer spawns + side-effects>

## Errors
<per M3 §6 Block 5b — failed spawns, gh fail-open, mechanical-prepass failures>

## Open Questions
<per M3 §6 Block 5c — escalation-required items, ambiguous findings>

## Termination reason
<per M4 §2.1.1 — only on aborted | escalated state>

## Persisted approvals
<per M3 §6 Block 5d — rendered from approvals[] frontmatter for user-readability>
EOF
```

**T2 extensions для in-run state-tracking:** Canonical M1 §T2 is а one-shot producer→consumer handoff. M6 extends с `phase:`/`status:`/`round:`/`approvals[]` к enable mid-run compaction recovery (M3 SessionStart hook reads this file on resume). The file functions as а T2 handoff AT REST (after Phase 5 persist) и as а T1-like state file DURING THE RUN.

**Per-finding line schema** with origin tag:

```
- [NEW|PRE-EXISTING] [optional: CONFIRMED-BY-TEST|CHALLENGED-BY-TEST|POSTED-TO-PR|ALREADY-RESOLVED-ON-PR] path:lines — <description> — decision: <FIX-NOW|TESTABLE|PRODUCT-DECISION|INTENT-CHECK> — recommendation: <action> — confidence: NN% — origin: <llm:<dim>|mechanical:<check>>
```

### 5.2 Old state-file fallback

If а file exists at `<PRIMARY_ROOT>/.geniro/state/review-findings-state.md`, read it once on Phase 5 entry for resume compatibility, but always write к the canonical path. The old file is NOT auto-deleted (user may have references).

### 5.3 Phase 5b — L2 pitfall auto-emit (P-M6-learnings, replaces /learnings)

**Trigger condition:** Phase 3 §3.1 orchestrator-side dedup produced а finding с `convergence_count: ≥3` (3+ reviewers reported same issue OR 2 reviewers + 1 mechanical pre-pass).

When trigger fires, **auto-spawn (no AUQ)**:

```yaml
emit-learning:
  producer: /geniro:review
  scope: <changed-file-glob>
  summary: "<finding title with file:line>"
  tags: [<dimension>, <project-tech>]
  type: pitfall
  trust: verified
  note: "Cross-reviewer convergence: <N> reviewers + <mechanical-flag>"
```

Helper: `${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh` (M2 §9). Dedup + sanitization per M2 §5.2.

Threshold tuning (exact «≥3» semantics) — fixed по spec, не deferred. М2 §5.3 codifies this.

Also emit `convention` learnings — NOT for M6. М4 /implement owns convention emits per M2 §5.3 patched contract.

### 5.4 PR comment posting (conditional — gated by Phase 6)

If Phase 6 user picks «Post Draft PR» option, Phase 5 writes the finding list к the PR via `mcp__github__pull_request_review_write` с status `COMMENTED`. M3 `non-resumable-actions[]` entry appended via `atomic_state_write`:

```yaml
non-resumable-actions:
  - action: pr-review-comment-batch
    completed-at: <ISO-8601>
    pr-ref: <owner>/<repo>#<num>
    finding-count: <N>
    comment-ids: [<id1>, <id2>, ...]
```

PR post fails fail-closed — if `mcp__github__pull_request_review_write` errors, write `## Errors` entry + abort Phase 5 (don't proceed к hand-off с а half-posted state).

Full Post drill (Steps 1.5-6) в `${CLAUDE_SKILL_DIR}/phase-6-handoff-reference.md` §7.

### 5.5 Idempotent re-entry

If Phase 5 re-enters after compaction:
1. Read state.md `non-resumable-actions[]` — если PR post already completed, skip re-post.
2. Re-read findings от Phase 3 dedup output (held в context OR re-runs Phase 3 if context lost).
3. Re-write `from-review-<branch>.md` (overwrite — `atomic_state_write` handles atomicity).

---

## Phase 6 — Action Gate Hand-off

State.md `phase: action-gate`. **Full contract:** `${CLAUDE_SKILL_DIR}/phase-6-handoff-reference.md`.

Summary:

- **AUQ с 4 options** — `/implement findings` (Recommended когда CRITICAL/HIGH count >0) / Post Draft PR review (conditional on `pr-ref:` non-none + ≥1 unposted) / Continue rounds (Round-N escalation gate когда round ≥3) / Skip.
- **Reporter behavior** — no fix loop inside /review. М4 /implement self-review (5-dim parallel) is а separate skill с а separate contract.
- **`--simplify`** does NOT change hand-off shape (still reporter).
- **Persist user pick к `approvals[]`** с category `action_gate` (M3 §6 Block 5d).
- **Round-N escalation gate** when round ≥3 + «Continue rounds» pick — secondary AUQ (Continue / Escalate / Abort). Terminal `aborted` records `## Termination reason: repeated-failure: round-limit-3`.

Open questions for Phase 6 deferred per spec OQ-M6-4 (hard-ceiling at round 5 or 6) — see reference file §5.

---

## ACI per-phase tool surface (M6 §13.5 / §19.3)

| Phase | Allowed tools | Restricted |
|---|---|---|
| Phase 1 / 1.5 | Read, Grep, Glob, Bash (read-only — `gh pr view`, `git diff`, `which <tool>`, lint commands, `tsc --noEmit`), **`mcp__linear__*` (read-only — `get_issue` / `list_issues` for §3.5 workflow integration; degrade silently if unregistered)** | No Edit/Write apart от M1 state.md; no Linear `update_issue` / `create_comment` от /review (those remain в /implement Ship) |
| Phase 2 / 3 / 4 | Agent (reviewer-agent, validation sub-agents, adversarial-tester-agent); Phase 3 dedup orchestrator-inline (no spawn) | No Edit/Write/Bash mutations |
| Phase 5 | Write (scoped к `.geniro/state/handoff/**`), `mcp__github__pull_request_review_write` (conditional), `emit-learning` helper | Direct edits outside scope blocked by hooks |
| Phase 6 | AskUserQuestion | Read-only |

Existing safety hooks apply: file-protection, git-guardrails, `.geniro/` deletion guard, state-helper enforcement, plan-mode write-guard.

---

## Memory I/O Schedule (M2 §13 obligation)

| Phase | Helper | Direction | MODE | Inputs | Outputs |
|---|---|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `initial-load` | scope = `review` + `global` + `code-style` + `user-preferences` (M10b — 4 files) | concatenated rule body |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` | top-2: `_project.md` + `_CODEBASE_MAP.md` | inlined + drift check |
| Phase 1 entry | `query-learnings` | read L2 | n/a | tags inferred от changed-file paths; type bias `pitfall` | top-K matching entries (default K=5) |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a | three loaded layers | precedence-resolved |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` | scope = `review` + `global` + `code-style` + `user-preferences` (M10b — 4 files) | rule body (refreshed) |
| Phase 5 | M1 `atomic_state_write` | write T2 | n/a | state file path; full body | whole-file rewrite |
| Phase 5b | `emit-learning` | write L2 | n/a | producer = /review; type = `pitfall`; trust = `verified` | append к `learnings.jsonl` |
| Phase 6 | M1 `atomic_state_write` | write T2 | n/a | state file path; updated `approvals[]` | whole-file rewrite |

**L2 emit triggers** per M6 §19.2 patched contract:
- `pitfall` — **YES** — Phase 5b auto-emit когда convergence ≥3.
- `convention` — Not by M6. M4 /implement owns.
- `decision` — Not by M6. M5 /plan owns.
- `diagnosis` — Not by M6. M7 /debug owns.

---

## Anti-rationalization (M6 §24 — P-MP-1 closure)

Per master plan P-MP-1: every milestone closes с an explicit anti-pattern check.

| Your reasoning | Why it's wrong |
|---|---|
| "/review should fix its own findings — М4 has а fix loop, parity is good." | M4 /implement self-review is а post-implementation gate that ships clean code. /review is а standalone audit consumed by downstream skills. Different workflows, different output contracts. User-picked Reporter behavior (H-2) reflects this. М4 parity is а false constraint. |
| "Mechanical pre-pass is too slow — skip it, LLM reviewers cover the same ground." | LLM reviewers cover similar ground at 100x the cost + non-deterministic. Lint detects а missing import faster и more reliably than а security reviewer would. Run cheap-deterministic first; LLM-spawn second с pre-pass findings as prior-context. |
| "Just keep guidelines §8 — двойное finding is а feature, not а bug." | User-facing «told twice» is concrete UX friction documented в audit. Two reviewers reporting same thing wastes user attention. Specialized dim (conventions, haiku-tier) wins on cost AND quality. |
| "Absorbing /deep-simplify means losing Phase 4 Fix agent." | Phase 4 Fix agent applied automated code edits — fixer responsibility. М6 (/review) is Reporter. Users wanting auto-applied fixes pipe `/review --simplify` output к `/implement`. |
| "spec-compliance check #11 (Tools Required available) requires Bash mutation." | `which <tool>` is read-only Bash. No mutation. Standard ACI surface allows it. |
| "Phase 5b auto-emit pitfall could spam learnings.jsonl с false positives." | Threshold = convergence_count ≥3. Three reviewers (или 2 + 1 mechanical) converging is а strong signal. Dedup + sanitization per M2 §5.2 prevents duplicates. False-positive risk низкий. |
| "SKILL.md trim к 400 lines is а cosmetic concern." | 1025-line monolith hurts onboarding и debug. Reference-file pattern matches M4. Cosmetic surface IS surface. |
| "Risk-tier:high secret scan strict mode adds latency без ROI." | Secret leakage is а CRITICAL-severity event с irreversible consequences. 4 extra regex patterns adds <1s. ROI is asymmetric — small cost, large downside avoided. |
| "Phase 1.5 mechanical pre-pass should run в parallel с Phase 2 LLM spawns." | LLM agents seeing prior mechanical findings produce better-targeted output. Sequential adds ~10-30s; parallel forces post-hoc dedup и dilutes LLM focus. |
| "--simplify flag is а natural place к add `simplify` as а new dimension." | Re-creates /deep-simplify as а disguised skill. Fold-into-existing approach (5 weighted dims) is the only correct absorption. |
| "Round-N hard ceiling at round 6 is paternalistic." | User picking «Continue» 5 times indicates either а bug в stratification или а workflow that should be /debug. Hard ceiling protects against accidental infinite-loop UX. User retains agency via «Escalate» pick. |
| "Auto-drop MEDIUM findings к reduce user friction." | Metaswarm anti-pattern. M6 routes MEDIUM через always-WAIT MEDIUM-gate (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`). Never auto-drop. |
| "Skip Phase 5 approvals[] persistence — Phase 6 hand-off captures everything." | Phase 6 AUQ fires once; compaction mid-Phase-3 (filter) would lose all prior gates без `approvals[]`. M3 §6 Block 5d depends on this persistence; non-negotiable. |
| "Add а wall-time kill cap для long-running /review." | §2.3 quality-first — no Class-A hard caps. Round-N escalation is the Class-B gate; user decides. |
| "Bypass git guardrail hooks when Phase 5 PR comment post fails." | Hooks fail для reason. Phase 5 fail-closed (§5.4) — failure surfaces an error, does NOT auto-retry с `--no-verify`. Investigate, fix, re-fire. |
| "Phase 4c F→P test gate is over-engineered для standard tier — skip it." | F→P verification ensures test-first hygiene. --tdd users specifically benefit; --standard users still get а sanity gate. |
| "I'll spawn the adversarial-tester-agent и ask the user к confirm later." | Inline gates rationalize away into "this counts as approval". Skill MUST `AskUserQuestion` BEFORE spawning. The two-step gate (ask → on YES, spawn) is the only rationalization-resistant variant. |
| "The findings look obviously postable — I'll just batch-post к the PR и tell the user after." | Posting к а PR is an external write к а public surface. Inline gates rationalize away. Phase 6 Action gate's "Post" selection IS the consent. |
| "TDD mode is on, user clearly wants tests authored — skip the Phase 4c AUQ." | TDD mode flips the *Recommended* highlight, not the *gate*. The Phase 4c invariant is non-negotiable in every mode. |
| "I'll auto-update Linear status from /review когда findings are critical — saves user а step." | /review is а Reporter (M6 H-2). Linear `update_issue` / `create_comment` are external side-effect writes; only /implement Ship runs them per `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/linear.md` §Status Transitions, all gated by AUQ. /review's MCP surface is read-only (`get_issue` / `list_issues`) per §13.5 ACI. |
| "Inline LINEAR CONTEXT into ALL 9 reviewer dims — more context = better review." | Cross-reviewer convergence anti-pattern (mirror PEER-PR rationale § 4). LINEAR CONTEXT helps spec-compliance (rubric source), pr-metadata (title-divergence check), architecture (parent-epic linkage); other dims see it as noise that biases their per-file rubric. |
| "Top-10 peer PRs is too noisy — drop к top-5 to keep prompts small." | Total cap is 5K chars (vs old 3K), not raw LOC count. Natural drop kicks в — typical run keeps 3-5 actual siblings in prompts. Top-10 is the candidate pool; ranking + cap selects which survive. Tightening к top-5 candidates risks losing parent-epic linked PRs that score 0 file overlap but +4 linear bonus. |
| "Linear MCP unregistered — surface а HIGH finding so user installs it." | §3.5.4 fail-open contract: degraded paths surface а one-line `## Caveats` note, not findings. The skill doesn't pressure user к install tooling — that's UX hostility. |

---

## Definition of Done

Code review is complete when:

- [ ] Phase 1 mode detection ran — Outgoing vs Incoming routed per `$ARGUMENTS` shape
- [ ] Phase 1 PLAN CONTEXT resolved (M5 schema-aware load когда applicable, fallback к prose detection)
- [ ] Phase 1 §3.5 Workflow integrations ran когда `.geniro/workflow/*.md` non-empty — tracker ID detected (если present в `$ARGUMENTS` / `pr.title` / `pr.body`); `linear-task-ref` + `linear-parent-ref` populated в frontmatter; `LINEAR CONTEXT:` block built (или fail-open caveat surfaced)
- [ ] Phase 1 §4 Peer-PR scout (PR-ref only) ran с extended scoring — `total_score = file_overlap + linear_bonus`; top-10 kept; per-sibling diff ≤200 lines; total cap 5K chars; PEER-PR CONTEXT fed к 6 dims
- [ ] Phase 1 Step 0.5 Round-N gate evaluated — round counter incremented; Round-N AUQ fired когда round ≥3
- [ ] Phase 1 Step 0.7 risk-tier stratification ran — `risk-tier: <standard|high>` persisted; 4 downstream knobs adjusted
- [ ] Phase 1 Step 0.8 M2 memory layers loaded (L4 instructions + L3 semantic + L2 learnings)
- [ ] Phase 1 git-workspace decision ran когда input was а PR ref
- [ ] Phase 1.5 mechanical pre-pass ran — 3 checks (lint / schema / secret scan) с strict-mode secret-scan когда risk-tier:high
- [ ] Phase 2 reviewers spawned и executed в parallel, each prompt carrying PLAN CONTEXT (spec-compliance dim only) + LINEAR CONTEXT (spec-compliance + pr-metadata + architecture dims only) + PEER-PR CONTEXT (6 dims) + PRIOR-ROUND FINDINGS + Mechanical Pre-pass Findings + alignment-tag instruction
- [ ] Phase 2 spec-compliance reviewer spawned когда PLAN CONTEXT non-`none` AND (input was а PR ref OR risk-tier:high)
- [ ] Phase 2 `--simplify` flag prepended deep-simplify criteria к 5 dimensions (architecture / conventions / guidelines / bugs / optimizations) когда present
- [ ] Phase 3 relevance-filter applied; `convergence_count` field populated per finding
- [ ] Phase 4 judge validation complete; Step 0 intent reconciliation applied (plan-authorized divergences demoted к `[INTENT-CHECK]`)
- [ ] Phase 4b per-finding validation run for CRITICAL/HIGH findings
- [ ] Phase 4c test-gate evaluated (skipped когда no eligible findings или user declines); user approval persisted к `approvals[]`
- [ ] TDD mode only: Phase 4c Step 2 AUQ rendered с `(Recommended)` suffix на «Author tests…»; gate itself fired exactly as в Standard mode
- [ ] TDD mode only: Phase 6 Step 3.5 post-set filter applied
- [ ] Confidence scoring applied (≥80 threshold standard; ≥70 высокий tier)
- [ ] Issues classified by severity (Critical, High, Medium) и Decision Type ([FIX-NOW] | [TESTABLE] | [PRODUCT-DECISION] | [INTENT-CHECK])
- [ ] Findings tagged as [NEW] или [PRE-EXISTING] based on diff context
- [ ] Phase 5 state artifact written к `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` (M1 §T2 schema + M3 body sections) via `atomic_state_write`
- [ ] Phase 5b L2 pitfall auto-emit fired когда any finding had `convergence_count ≥3`
- [ ] Phase 6 open-decision gate fired для every `[PRODUCT-DECISION]` finding (always-WAIT)
- [ ] Phase 6 Action gate fired (always-WAIT) — single consolidated decision; user pick persisted к `approvals[]` (category `action_gate`)
- [ ] Phase 6 Round-N escalation gate fired когда round ≥3 + «Continue rounds» pick; terminal state mapped per M6 §2.1.1
- [ ] Phase 6 Action == Post drill ran (Steps 1.5-6) когда user picked «Post»; `[POSTED-TO-PR]` markers persisted для idempotent re-run
- [ ] Phase 6 Failing-tests gate fired когда `## Authored Tests` non-empty; firing order conditional on Action choice per the gate-chain rule
- [ ] Terminal state мapped к state.md `## Termination reason` per M6 §2.1.1 когда `aborted` или `escalated`

---

## Anti-pattern check (P-MP-1)

М6 verified against master-plan P-MP-1 12-item guardrail. Status:
- One giant prompt: ✅ avoided (skill-scoped SKILL.md + reference files + criteria files)
- One giant tool: ✅ N/A
- Unbounded autonomous loop: ✅ Round-N 3-round bound + escalation gate
- Autonomous external sends в first release: ✅ Phase 6 Post drill AUQ-gated
- No approval state: ✅ `approvals[]` field (P-M1-1) с M6 categories (`tdd_mode_choice` / `test_gate_choice` / `action_gate` / `round_n_escalation` / `failing_tests_commit_policy`)
- No durable plans / goals: ✅ M1 T2 state file mandatory
- No compaction strategy: ✅ M3 SessionStart hook re-injects via Block 5b/5c/5d
- All connectors loaded up front: ✅ N/A (MCP plugin model)
- High-risk tools без policy: ✅ existing hooks
- Subagents before single-agent MVP measured: ⚠️ partial (deferred к P-X6)
- Dynamic timestamps в plugin Markdown: ✅ audited — none
- Non-deterministic agent registration: ✅ alphabetic by slug

М6 introduces no new anti-pattern regressions.
