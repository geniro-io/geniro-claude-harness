---
name: geniro:review
description: "Use when you want a comprehensive code review of pending changes. 6-phase loop (triage → mechanical pre-pass → 10-dim LLM reviewers + N custom → filter → stratify → persist → action-gate). MANDATORY spawn list per §2.1 (7 always-fire + 3 conditional + N custom). Reporter behavior — emits a handoff file at .geniro/state/handoff/from-review-<branch>.md; downstream consumers (/implement, manual) apply fixes. Phase 6 Pre-gate resolves any unresolved open_questions[] from spec-compliance / pr-metadata / plan-context BEFORE the action-gate fires. Optional --simplify flag folds Reuse/Quality/Efficiency criteria into existing dims. Optional --tdd flag tightens Phase 4b validation + Phase 4c test-gate."
context: main
model: inherit
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent, AskUserQuestion, WebSearch, EnterWorktree, ExitWorktree]
argument-hint: "[files, diff range, branch, or PR ref (#N, URL)] [--plan <path>] [--tdd] [--simplify]"
---

# Code Review Skill

Comprehensive code review using parallel multi-agent analysis. ~400 lines orchestration shell + reference files.

**Architecture spec:** *(internal)*. Detailed phase contracts:
- `${CLAUDE_SKILL_DIR}/phase-1-triage-reference.md` — Phase 1 input mode / scope / risk-tier / memory load.
- `${CLAUDE_SKILL_DIR}/phase-4c-test-gate-reference.md` — Phase 4c test-confirmation gate.
- `${CLAUDE_SKILL_DIR}/phase-6-handoff-reference.md` — Phase 6 action-gate hand-off + Post drill.
- `${CLAUDE_SKILL_DIR}/plan-context-reference.md` — schema-aware PLAN CONTEXT load (design fix).
- `${CLAUDE_SKILL_DIR}/incoming-mode-reference.md` — INCOMING mode (PR review-feedback processing).
- `${CLAUDE_SKILL_DIR}/tdd-mode-reference.md` — `--tdd` flag semantics.

---

## Your Role — Orchestrate, Don't Review

You are a **coordinator**. You delegate review work to `reviewer-agent` instances via the Agent tool and validate their outputs in the judge pass. You do NOT review code yourself — you read files only to gather context and verify agent findings.

`/geniro:review` is a **Reporter** — it does NOT apply fixes. Phase 6 hand-off message NEVER includes "I'll fix these now" language. Findings persist to a handoff file; downstream consumers (`/implement`, manual user action) apply fixes. The `--simplify` flag does NOT change this.

---

## State Machine

State.md `phase:` enum transitions:

```
[entry] → triage → mechanical-prepass → llm-spawn → filter → stratify → persist → action-gate → done
│
├── escalated ── (round-N user pick)
└── aborted ── (round-limit / safety / tool-unavailable)
```

**Terminal states:** `done`, `aborted`. the SessionStart recovery treats both as "review complete / cancelled". `done` includes a Phase 6 hand-off line.

**Non-terminal states:** `triage`, `mechanical-prepass`, `llm-spawn`, `filter`, `stratify`, `persist`, `action-gate`. the recovery rolls these back to phase-entry and re-runs from there (idempotent — `approvals[]` ensures Phase 6 AUQ skips already-answered).

**Termination-case mapping** per — see Phase 6 reference for the full table. The `## Termination reason` body section is written on `aborted` / `escalated` terminals.

---

## Loop Invariants

The 7 invariants apply unchanged:

1. **One result per tool call.** Phase 2 parallel-spawn reviewer-agents — each must return a structured result; dead spawn → `status: failed` entry in `## Tool log`.
2. **Args validated before execution.** `$ARGUMENTS` flag parsing (semantic, no CLI grammar); PR ref validation via `mcp__github__pull_request_read` or GraphQL fallback.
3. **Permission before side-effect.** Phase 6 "Post Draft PR" requires AUQ approval before posting to GitHub. The post is a single `gh api POST /repos/<owner>/<repo>/pulls/<number>/reviews` call per `${CLAUDE_SKILL_DIR}/phase-6-handoff-reference.md` §7.5 — `event` field omitted so the review is created in GitHub's PENDING state (private to the reviewer, no notifications fire). State.md writes via `atomic_state_write`.
4. **Bounded and structured tool results.** Reviewer-agent output ≤4000 chars per dim; truncation marker. Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.
5. **Escalation gates, not silent abort.** Round-N ≥3 → Phase 6 escalation gate.
6. **Final answer grounded in observations.** Phase 6 hand-off message MUST cite the state.md path; finding bodies MUST include Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`.
7. **Errors → structured observations.** Reviewer spawn failures → `## Errors` body section. `gh` fail-open NOT silent — log to `## Errors`.

`## Tool log` schema: typical run produces 5-12 entries (1 per reviewer + 1 per Phase 5b emit-learning + 1 per PR-side-effect).

---

## Budgets — Quality-First

This skill has **NO hard kill caps**. Same model as other skills.

**Quality gates (escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Round-N reviewer re-spawn | 3 | Phase 6 Round-N gate | AUQ — debug-handoff / continue / abort. User picks. |
| Reviewer output size | ~4K chars per dim | invariant #4 | Truncation marker, not abort. |
| Phase 3 dedup pass | 1 per round | Phase 3 | Orchestrator-inline (no subagent — folded under subagent rationalization). Cannot "fail" — runs in orchestrator's main context. |

**Architecture constraints (design intent, not budget):**

| Constraint | Value | Source |
|---|---|---|
| LLM reviewer spawn count | 7 always + (0-3 conditional) + (0-N custom) in parallel | §2.1 dimension grid + Phase 1.5 §1.5.4 custom-reviewer discovery |
| Mechanical pre-pass tools | 3 (lint / schema / secret scan) | Phase 1.5 |

**Explicitly NOT capped:** wall-time, total tool calls, total model turns, total cost. Same rationale.
---

## Subagent Model Tiering

Follow the canonical doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Plugin agents (`reviewer-agent`, `adversarial-tester-agent`) declare `model: inherit` in frontmatter — OMIT `model=` at every spawn site so the orchestrator's session tier propagates. Apply the registration-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (`geniro-claude-plugin:<agent>` → bare `<agent>` → `general-purpose` with agent body inlined). Cache the resolved rung for the rest of the session.

The one exception: custom reviewers whose `.geniro/instructions/review-extra/<slug>.md` frontmatter declares an explicit `model:` value. Pass that value verbatim at the spawn site — honor the user's per-reviewer declaration.

Every Agent prompt satisfies the six pre-inlined fields per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`.

| Spawn | Model arg | Why |
|---|---|---|
| `reviewer-agent` (all built-in dims) | OMIT | Frontmatter `model: inherit` — orchestrator tier propagates |
| `reviewer-agent` (custom dim) | OMIT (default) OR explicit value when user-declared | User declaration wins per model-tiering doctrine |
| `adversarial-tester-agent` (Phase 4c only) | OMIT | Frontmatter `model: inherit` |
| Per-finding validation sub-agents (CRITICAL/HIGH) | OMIT | Frontmatter `model: inherit` |

---

## Phase 1 — Triage & Context Collect

State.md `phase: triage`. **Full contract:** `${CLAUDE_SKILL_DIR}/phase-1-triage-reference.md`.

Summary of what Phase 1 does:

1. **Step 0 — Workspace setup** — passive context detection (IN_WORKTREE, REVIEW_HANDOFF, DEBUG_HANDOFF, IMPLEMENT_TASK_STATE, BRANCH_MATCHES_TASK_SLUG, PROTECTED_BRANCH, TARGET_PR_NUMBER, IN_TARGET_WORKTREE) followed by a 7-rule decision tree with auto-continue branches for in-worktree continuing-work signals. Workspace AUQ (single question — workspace decision) fires only when ambiguous. Inline modifier overrides (`worktree` / `no-worktree` / `current-branch` / `new-branch`) win deterministically. Approvals persist as `review_workspace_setup` to survive compaction and Round 2+ re-runs. /review never mutates workflow tracker status — that is `/geniro:plan` and `/geniro:implement` territory; /review reads tracker context only (see item 5). Fires BEFORE all subsequent items so they operate on the correct working tree. Full contract: `${CLAUDE_SKILL_DIR}/phase-1-triage-reference.md` §0.
2. **Input mode detect** — OUTGOING / INCOMING / pr-ref routing per `$ARGUMENTS`. Anchored NL signals ("process review on #N") route to INCOMING; PR ref + K>0 unresolved threads fires Mode AUQ.
3. **Scope resolution** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. NEVER invoke `gh pr list` to invent a target.
4. **PR-ref parsing** — `gh pr diff` + `gh pr view --json baseRefName,headRefName,body,title,headRefOid,url,isDraft,author,labels`.
5. **Workflow integrations** — read `.geniro/workflow/*.md`, apply tracker-ID regex against `$ARGUMENTS` + `pr.title` + `pr.body`, AND when a spec.md is resolvable (via `--plan <path>`, `geniro-plan:` PR-body line, walk-up `.geniro/planning/*/spec.md`, or canonical project paths) parse its frontmatter `workflow_refs[]` per `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md`. Accept both `geniro_schema_version: m5-v1` (treat field as absent) and `m5-v2` (read entries). Merge sources by `(kind, issue_id)` — `$ARGUMENTS` reference wins on conflict (user just typed it, fresher signal); PR body next; spec.md frontmatter as fallback. On Linear match with MCP available: fetch issue (+ parent epic + sibling sub-tasks). Build `LINEAR CONTEXT:` block. Persist `linear-task-ref:` + `linear-parent-ref:` to state.md frontmatter, derived from the deduplicated merged list. Read-only — /review never mutates tracker state via MCP. Fail-open if MCP unavailable.
6. **Peer-PR scout** (PR-ref only) — top-10 sibling PRs scored by file overlap + Linear-relatedness bonus (parent-epic / sibling-sub-task matches); inlined into 6 reviewer prompts (architecture + design + bugs + conventions + optimizations + spec-compliance).
7. **Load custom instructions** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` (MODE: initial-load; scope = `review` + `global` + `code-style` — pipeline tier, 3 files).
8. **Round-N counter** — increments and fires Round-N AUQ when round ≥3.
9. **PLAN CONTEXT load (schema-aware).** Detection per `${CLAUDE_SKILL_DIR}/plan-context-reference.md` Structured-section parser when `geniro_kind: design-doc` frontmatter present; prose fallback otherwise.
10. **Risk-tier stratification** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` 9 hard-escalation signals. Sets `risk-tier: standard | high`. Adjusts 4 downstream knobs (severity threshold / validator budget / spec-compliance default / mechanical secret-scan strict mode).
11. **Memory layer load:** `load-custom-instructions` MODE:refresh + `load-semantic` MODE:refresh + `query-learnings` (top-K, K=5 default) + `resolve-conflicts`.
12. **Mode AUQ** (Standard vs TDD) when neither `--tdd` nor `--standard` in `$ARGUMENTS`. Persist to `approvals[]` with category `tdd_mode_choice`.
13. **Size triage** — classify files Trivial / Substantive when diff >8 files or >400 LOC. Controls Phase 2 Standard vs Batched mode.

Exit criterion: state.md frontmatter populated with `mode`, `round`, `risk-tier`, `pr-ref`, `linear-task-ref`, `linear-parent-ref`, `plan-context-ref`, `simplify-mode`, all populated; `approvals[]` carries any AUQ answers; `## Tool log` includes initial load echoes.

Phase 1 PR metadata and tracker context loads are orchestrator-inline (`gh pr diff` / `gh pr view` / `mcp__linear__*` reads). For codebase-research side queries inside this phase (e.g., locating a pattern across the wider repo when scoring peer-PR overlap), spawn `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

---

## Phase 1.5 — Mechanical Pre-pass (NEW — closure)

State.md `phase: mechanical-prepass`.

Three deterministic checks BEFORE LLM reviewer spawns. Cheap-deterministic first; LLM-spawn second with pre-pass findings as prior-context. Sequential, not parallel — LLM agents seeing prior mechanical findings produce better-targeted output.

### 1.5.1 Check 1 — Lint

Probe project for existing lint config: `eslint.config.{js,mjs,cjs,ts}`, `.eslintrc*`, `pyproject.toml [tool.ruff|black|pylint]`, `Cargo.toml [lints]`, `.rubocop.yml`, etc.

If detected, run the project's own lint command (`pnpm lint`, `npm run lint`, `cargo clippy`, `bundle exec rubocop`) with `--quiet` or equivalent. Capture failures as `{tool, file, line, rule, message}` tuples.

### 1.5.2 Check 2 — Schema

Heuristic: if changed files include TypeScript (`*.ts`, `*.tsx`), run `pnpm tsc --noEmit`. JSON schema (`*.schema.json`, `*.openapi.{json,yaml}`) — probe for `ajv` if present. Protobuf — `buf lint` for `.proto` changes. Capture failures.

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

### 1.5.4 Custom-reviewer discovery

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` to enumerate user-authored review dimensions in `.geniro/instructions/review-extra/<slug>.md`. The helper applies its `paths:` filter against the changed-files list, enforces the ≤10 cap, and returns spawn-specs: `{slug, dimension-label: custom:<slug>, model, criteria-content, severity-default, source-path}`.

Persist the result to state.md frontmatter `custom_reviewers[]`:

```yaml
custom_reviewers:
  - slug: manifest-incident-patterns
    paths_matched: true               # whether the spec's `paths:` matched any changed file (`true` when no paths filter declared — always-fires)
    model: inherit                    # frontmatter value, or `inherit` when OMITTED in the spec
    source_path: .geniro/instructions/review-extra/manifest-incident-patterns.md
    severity_default: HIGH
```

Phase 2 reads `custom_reviewers[]` from frontmatter — zero discovery work at Phase 2 entry. Discovery lives here because Phase 1.5 already has Bash tooling primed (lint, schema, secret-scan); adding one Glob + frontmatter parse is cheap. Phase 2 is cognitively heavy (parallel spawn-template assembly), so this offload reduces silent-skip risk.

On helper hard-cap error (>10 custom reviewers), surface the error to chat, persist `custom_reviewers: []`, and let Phase 2 fire only the built-ins.

### 1.5.5 Output handling

Mechanical findings tagged `origin: mechanical:<check_id>`. Routed two ways:

1. **To Phase 2 LLM reviewers as prior-context** — pasted into spawn prompts under a `## Mechanical Pre-pass Findings` section. LLM agents use those as starting points (avoid duplicating; extend with semantic understanding).
2. **To Phase 5 persist** — included in the state.md finding list with the mechanical tag preserved.

### 1.5.6 Fail-handling

If lint or schema check fails (process exit nonzero with no output OR command not found):
- Write `## Errors` entry: `mechanical-prepass-{check_id}: command_unavailable_or_failed`.
- Continue to Phase 2 without the failed check's findings (fail-open, consistent with `gh` fail-open).

Secret scan is a pure-regex pass — cannot fail.

---

## Phase 2 — LLM Reviewer Spawns

State.md `phase: llm-spawn`.

### 2.1 Dimension grid (10 built-in dimensions + N custom)

| # | Dimension | Spawn rule (MANDATORY) |
|---|---|---|
| 1 | bugs | Always fires — no exception |
| 2 | security | Always fires — no exception |
| 3 | architecture | Always fires — no exception |
| 4 | tests | Always fires — no exception |
| 5 | optimizations | Always fires — no exception |
| 6 | guidelines | Always fires — no exception |
| 7 | conventions | Always fires — no exception. Owns repo-modal-pattern findings exclusively |
| 8 | design | Fires when UI globs match changed files (see §2.4 UI-file detection rule) |
| 9 | pr-metadata | Fires when `pr-ref:` is non-none |
| 10 | spec-compliance | Fires when PLAN CONTEXT is non-none AND (`pr-ref:` non-none OR risk-tier:high) |
| +N | custom:* | Fires per user-authored `.geniro/instructions/review-extra/<slug>.md`, discovered in Phase 1.5 |

**Spawn-batch size.** Phase 2 MUST spawn a reviewer-agent for every row whose trigger fires:

- 7 always-rows (bugs, security, architecture, tests, optimizations, guidelines, conventions) fire on every run.
- 3 conditional rows (design, pr-metadata, spec-compliance) fire when their trigger column is satisfied.
- N custom rows fire per the spawn-specs already discovered in Phase 1.5 §1.5.4 (zero discovery work at Phase 2 entry — read the count from state.md frontmatter `custom_reviewers`).

Total batch size = 7 + (0-3 conditional) + (0-N custom). Trimming this set silently is the documented anti-pattern — see §Anti-rationalization. Post-spawn verification in Phase 4 §4.0 catches drift.

**Refresh L4 instructions** at Phase 2 entry — apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `MODE: refresh`. Compaction since the previous load may have silently dropped the rules.

**Read custom-reviewer specs** from state.md frontmatter `custom_reviewers[]` — populated in Phase 1.5 §1.5.4 via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` discovery. Append one `Agent(subagent_type="reviewer-agent",...)` per spec to the same parallel batch as the built-ins.

### 2.2 Pre-spawn declaration (state.md write before parallel batch)

Before firing the parallel `Agent(...)` batch, the orchestrator computes the declared spawn list and writes it to state.md via `atomic_state_write`:

```yaml
# frontmatter update
spawn_dims_declared: [bugs, security, architecture, tests, optimizations, guidelines, conventions, pr-metadata, spec-compliance, custom:manifest-incident-patterns]
spawn_dims_count: 10
```

Plus a `## Tool log` entry:

```
[Phase 2 spawn declaration] dim_list=[bugs, security, architecture, tests, optimizations, guidelines, conventions, pr-metadata, spec-compliance, custom:manifest-incident-patterns]; count=10; triggers={pr-ref: <ref-or-none>, plan-context: <path-or-none>, linear-task: <id-or-none>, custom-reviewers-discovered: <N>}
```

This is observability for the Phase 4 §4.0 verification gate — declared-vs-actual is one grep away.

### 2.3 Spawn invocation

Single message with N parallel `Agent` tool uses, one per dimension. Each spawn:

- `subagent_type: reviewer-agent` (plugin) — apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration-degradation ladder.
- OMIT `model=` argument — reviewer-agent declares `model: inherit`. Custom reviewers that declare an explicit tier in their `.geniro/instructions/review-extra/<slug>.md` frontmatter pass that tier verbatim; otherwise OMIT.
- Pre-inlined context per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`:
  - Diff of changed files (full content for the batch's files in Batched Mode; all files in Standard Mode).
  - Project conventions from L4 (refreshed).
  - Mechanical pre-pass findings (Phase 1.5) as prior-context under `## Mechanical Pre-pass Findings`.
  - PLAN CONTEXT — spec-compliance dim ONLY (other dims see `PLAN CONTEXT: <plan tag fields only>` per the schema-aware reference).
  - LINEAR CONTEXT — spec-compliance + pr-metadata + architecture dims ONLY. Block omitted entirely for other dims.
  - PRIOR-ROUND FINDINGS (Round-N counter sub-step prior-round-summary, or `none — first review`).
  - PEER-PR CONTEXT — architecture + design + bugs + conventions + optimizations + spec-compliance dims ONLY.
  - Dimension-specific criteria file body inlined.
  - Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.

**Criteria files** (read once at Phase 2 entry):
- `${CLAUDE_SKILL_DIR}/bugs-criteria.md` · `security-criteria.md` · `architecture-criteria.md` · `tests-criteria.md` · `optimizations-criteria.md` · `guidelines-criteria.md` · `conventions-criteria.md`
- `${CLAUDE_SKILL_DIR}/design-criteria.md` (conditional per §2.5)
- `${CLAUDE_SKILL_DIR}/pr-metadata-criteria.md` (conditional)
- `${CLAUDE_SKILL_DIR}/spec-compliance-criteria.md` (conditional per §2.6)
- Custom reviewer criteria from spawn-specs returned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` (≤10 per project)

### 2.4 `--simplify` flag weighting

When `$ARGUMENTS` contains `--simplify` (semantic parse — matches `simplify`, `--simplify`, `simplify mode`), Phase 2 prepends deep-simplify criteria onto 5 of the built-in dimensions:

- **architecture** reviewer — Reuse criteria (existing abstractions, duplicate logic, premature abstraction).
- **conventions** reviewer — repo-modal-pattern aggressive mode (lower ≥80% siblings threshold to ≥60%).
- **guidelines** reviewer — Quality criteria (naming clarity, docs noise, dead code).
- **bugs** reviewer — Quality bug-class extensions (defensive code that masks bugs, redundant null checks).
- **optimizations** reviewer — Efficiency criteria (verbose loops, unnecessary allocations, sync I/O in async paths).

Pre-pend body read from `${CLAUDE_SKILL_DIR}/simplify-criteria.md`.

The flag biases existing reviewers' attention; it does not add new dimensions, change output schema, or alter the reporter-mode hand-off contract.

### 2.5 UI-file detection rule (design dim trigger)

A file is a UI file if path matches `**/components/**`, `**/pages/**`, `**/app/**`, `**/views/**`, `**/ui/**`, OR extension is `.tsx` / `.jsx` / `.vue` / `.svelte` / `.css` / `.scss` / `.sass` / `.less` / `.styled.ts` / `.styled.tsx`. Design dimension skipped when no changed file matches.

### 2.6 Spec-compliance detection rule

Fires when ALL hold: (a) PLAN CONTEXT is non-`none`; AND (b) either input was a PR ref OR risk-tier:high. Findings carry `File: SPEC-COMPLIANCE` sentinel — Phase 6 Post drill routes them to top-level review `body` under `## Spec Compliance` (no `path:lines` anchor, so they do NOT inline-comment).

### 2.7 Build verification (parallel with reviewers)

Run the project's validation suite in parallel with reviewer agents:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Build Check" "<validation_cmd>"
```

Feed pass/fail into Phase 4 judge. Failing build is automatically a CRITICAL finding — tag `[NEW]` if the base branch build passes, `[PRE-EXISTING]` if already broken.

---

## Phase 3 — Filter & Aggregate

State.md `phase: filter`.

### 3.1 Orchestrator-side dedup + convergence

The orchestrator reads all per-dimension findings (Phase 2 reviewer-agent outputs + Phase 1.5 mechanical findings) and performs dedup inline — no subagent spawn:

- **Dedup key:** `path:line + finding-title` (case-insensitive title match).
- **Convergence_count:** for each dedup'd finding, count how many reviewers + mechanical checks reported the same key. Persisted as a field on the finding (consumed by Phase 5b auto-emit threshold).
- **Drop hallucinations:** findings without a real file:line correspondence (orchestrator verifies file exists and line is within bounds via Read; if not, drop with a `## Caveats` line citing the dropped finding).
- **Convention context:** orchestrator reads convention files when present — CONTRIBUTING.md, ADRs at `docs/adr/`, architecture docs. These inform KEEP/FILTER decisions.

### 3.2 Mechanical+LLM dedup

Mechanical findings (Phase 1.5) and LLM findings may overlap (e.g., lint says "unused import on line 42", bugs reviewer says "dead code on line 42"). Orchestrator-inline dedup identifies overlap by dedup key, preserves the mechanical finding (deterministic) + drops the LLM's redundant entry. Convergence_count for that finding gains +1 for the mechanical contribution.

### 3.3 KEEP/FILTER judgment

After dedup, the orchestrator synthesizes per finding: weighs convention-alignment, over-engineering, and pattern-frequency evidence against severity and judges KEEP / FILTER. CRITICAL findings with `safety_override=true` are always KEEP regardless of convention evidence. Pass only KEEP findings to Phase 4. FILTERED appear in the report's `## Filtered` section with reason annotation.

No external agent to fail — dedup and judgment run in orchestrator's main context.

---

## Phase 4 — Stratification & Test Gate

State.md `phase: stratify`.

### 4.0 Post-spawn verification gate (declared vs actual)

Before stratification fires, verify the Phase 2 parallel batch actually delivered every dimension declared in §2.2:

```
declared = state.md frontmatter spawn_dims_declared
actual   = set of dimensions whose reviewer-agent emitted a structured result in Phase 3

missing = declared − actual
```

If `missing` is non-empty:

1. Append a `## Errors` body entry: `phase-2-spawn-incomplete: declared=<...> actual=<...> missing=<...>`.
2. Fire `AskUserQuestion` with header `"Spawn batch incomplete"`:
   - A) `"Re-spawn missing dims now"` — issue `Agent(...)` per missing dim; once results land, recompute `actual` and re-verify. (Recommended)
   - B) `"Skip missing dims and proceed with the rest"` — append to body `## Accepted Gaps`; continue to §4.1.
   - C) `"Abort review"` — terminal `phase: aborted`; `## Termination reason: spawn-batch-incomplete (<missing>)`.

Always-WAIT — empty answer = upstream bug, fall back to plain text. NEVER auto-default to "skip".

When `missing` is empty, proceed directly to §4.1.

### 4.1 Severity threshold filter

Apply risk-tier threshold:
- standard: keep findings with severity ≥ MEDIUM AND confidence ≥ 80%.
- high: keep findings with severity ≥ MEDIUM AND confidence ≥ 70%.

Sub-threshold findings written to a "Deferred" list (surfaced in body `## Deferred — sub-threshold` so user knows what was dropped). Deferred findings do NOT populate `open_questions[]` — that array is reserved for ambiguous-how-to-fix decisions that gate downstream action, not for awareness-only dropouts.

### 4.2 HIGH-severity validation pass

Sample HIGH-severity findings and validate via a secondary spawn (`reviewer-agent` clone with prompt emphasizing "confirm or refute, not expand"):

- standard tier: validate top-3 HIGH findings.
- high tier: validate ALL HIGH findings.
- `--tdd` flag: validate ALL HIGH findings regardless of tier.

Output: per-finding `validation: confirmed | refuted | partial` field added.

### 4.3 Failing-to-passing test-confirmation gate

**Full contract:** `${CLAUDE_SKILL_DIR}/phase-4c-test-gate-reference.md`.

Summary:
- Filter findings by decision-type per the runtime-behavior classification rule.
- **Mandatory user-approval gate before any `adversarial-tester-agent` spawn.** Skill MUST NEVER spawn without approval — the gate IS the load-bearing safety property. Persist to `approvals[]` with category `test_gate_choice`.
- `--tdd` flag flips the Recommended option to "Author tests for all eligible findings"; gate itself still fires.
- Spawn ONE adversarial-tester-agent with eligible findings as hypothesis seeds. Orchestrator's independent re-run IS the gate; never trust the agent's red/green claim alone.
- Demote-don't-delete: green tests demote findings to `## Filtered` with `[CHALLENGED-BY-TEST]` tag; original severity preserved for re-elevation.
- Fail-open: agent failures surface "test-gate fail-open" under `## Caveats` + write `## Errors` entry.

### 4.4 `--simplify` flag interaction

`--simplify` does NOT change Phase 4 thresholds or validator behavior. P1/P2/P3 simplify severities mapped to CRITICAL/HIGH/MEDIUM tag pool in Phase 3 — they pass through Phase 4 like native CRITICAL/HIGH/MEDIUM findings.

---

## Phase 5 — Persist & Emit

State.md `phase: persist`.

### 5.1 Handoff file write

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` per row. `<PRIMARY_ROOT>` resolved per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A.

**Write via `atomic_state_write`** — never direct Edit/Write on the canonical state path (the `enforce-state-helper` hook will warn-mode flag direct writes; PR-final will hard-block).

**`open_questions[]` rich-field authoring contract.** When composing `open_questions[]` entries from kept findings, fill the optional `context` / `evidence` / `options` / `recommendation` fields per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2. The reviewer-agent output already carries Evidence / Why-matters / Suggested-fix / Options per `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format — copy them into the open_question entry, do NOT discard them at composition time. Bare `question:` entries trigger the §2.5 Tier 3 fallback (terse AUQ), which the user experiences as the failure mode the rich-field schema was added to prevent. For non-finding open_questions (e.g., process / scope / verification questions surfaced by spec-compliance or pr-metadata reviewers), author `context` + `options` + `recommendation` inline — the reviewer's `## Why this matters` and `## Suggested fix` synthesis fields are still the source material; the consumer has no other way to render the question richly.

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
open_questions:                       # MUST be present; MAY be empty []
  - id: q1                            # short stable anchor
    source: <reviewer-dim or producer-step>
    question: <verbatim question text>
    related_findings: [F1, F4]        # optional — finding IDs this question gates
    status: unresolved                # enum: unresolved | resolved | wontfix
    resolution:                       # populated when status moves out of `unresolved`
      picked: <chosen option>
      at: <ISO-8601 UTC>
      asked_in_phase: <phase name>
      resolved_by: <skill that ran the resolution AUQ>
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
<per Block 2 — reviewer spawns + side-effects>

## Errors
<per Block 5b — failed spawns, gh fail-open, mechanical-prepass failures>

## Open Questions
<!-- Human-readable mirror of frontmatter `open_questions[]`. Frontmatter is source of truth. -->

### q1 — <source>: <one-line summary>
**Status:** unresolved
**Question:** <verbatim question>
**Related findings:** F1, F4
**Why this gates downstream action:** <one sentence — e.g., "drives whether to revert api seeders or update spec.forbidden_actions">

### q2 — ...

<!-- If open_questions[] is empty, this section reads: "No open questions — handoff is unconditionally actionable." -->

## Resolved Questions
<!-- Populated when downstream consumer (or /review's Phase 6 Step -1 gate) resolves an entry; mirrors frontmatter `open_questions[].resolution`. -->

### q1 — <source>: <one-line summary>
**Picked:** <chosen option>
**At:** <ISO-8601 UTC>
**Resolved by:** <skill — review | implement | manual>
**Phase:** <phase that ran the resolution AUQ>

## Termination reason
<per — only on aborted | escalated state>

## Persisted approvals
<per Block 5d — rendered from approvals[] frontmatter for user-readability>
EOF
```

**T2 extensions for in-run state-tracking:** Canonical is a one-shot producer→consumer handoff. extends with `phase:`/`status:`/`round:`/`approvals[]` to enable mid-run compaction recovery. The file functions as a T2 handoff AT REST (after Phase 5 persist) and as a T1-like state file DURING THE RUN.

**Per-finding body schema** — multi-line block per finding under `## Findings` (NOT a one-liner). Full schema + backward-compat parsing contract: `${CLAUDE_SKILL_DIR}/phase-6-handoff-reference.md` §"Per-finding body schema". Phase 4 judge MUST preserve every reviewer-agent field listed there when persisting findings; dropping fields to reach a one-liner is the failure mode the schema exists to prevent.

### 5.2 Old state-file fallback

If a file exists at `<PRIMARY_ROOT>/.geniro/state/review-findings-state.md`, read it once on Phase 5 entry for resume compatibility, but always write to the canonical path. The old file is NOT auto-deleted (user may have references).

### 5.3 Auto-emit pitfall learnings on convergence

**Trigger condition:** Phase 3 orchestrator-side dedup produced a finding with `convergence_count: ≥3` (3+ reviewers reported same issue OR 2 reviewers + 1 mechanical pre-pass).

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

Helper: `${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh`. Dedup + sanitization per
Threshold tuning (exact "≥3" semantics) — fixed per spec, not deferred. codifies this.

Also emit `convention` learnings — NOT for this skill. /implement owns convention emits per patched contract.

### 5.4 PR comment posting (conditional — gated by Phase 6)

If Phase 6 user picks "Post Draft PR" option, post the finding list as a PENDING review per the canonical procedure in `${CLAUDE_SKILL_DIR}/phase-6-handoff-reference.md` §7.5: one `gh api POST /repos/<owner>/<repo>/pulls/<number>/reviews` call, `event` field omitted from the jq payload. GitHub creates the review in PENDING state — visible only to the reviewer on github.com's "Finish your review" panel, no notifications fire until the human clicks Submit. Never pass `event: COMMENT` / `APPROVE` / `REQUEST_CHANGES` (those submit the review and defeat the "draft" semantics the user asked for); `event: "PENDING"` is INVALID — omission is the correct mechanism.

`mcp__github__pull_request_review_write` is NOT used here — the MCP wrapper does not surface the per-comment `path` / `line` / `side` fields required for inline anchoring, so the canonical tool is `gh api` directly per the reference. State persistence per `atomic_state_write`:

```yaml
non-resumable-actions:
- action: pr-review-comment-batch
completed-at: <ISO-8601>
pr-ref: <owner>/<repo>#<num>
finding-count: <N>
comment-ids: [<id1>, <id2>,...]
review-state: PENDING
```

PR post fails fail-closed — on non-zero `gh api` exit (HTTP error, missing scopes, secondary rate limit), write `## Errors` entry + abort Phase 5; never silently downgrade to top-level `gh pr comment` or retry with `event: COMMENT`.

Full Post drill (Steps 0-6) in `${CLAUDE_SKILL_DIR}/phase-6-handoff-reference.md`.
### 5.5 Idempotent re-entry

If Phase 5 re-enters after compaction:
1. Read state.md `non-resumable-actions[]` — if PR post already completed, skip re-post.
2. Re-read findings from Phase 3 dedup output (held in context OR re-runs Phase 3 if context lost).
3. Re-write `from-review-<branch>.md` (overwrite — `atomic_state_write` handles atomicity).

---

## Phase 6 — Action Gate Hand-off

State.md `phase: action-gate`. **Full contract:** `${CLAUDE_SKILL_DIR}/phase-6-handoff-reference.md`.

Summary of the gate chain (each gate is its own AUQ — never collapsed):

1. **Pre-gate — Resolve Open Questions** fires first whenever frontmatter `open_questions[]` has any entry with `status: unresolved`. Chain one AUQ per unresolved entry (cap-extension >4). Always-WAIT. Resolutions persist back via `atomic_state_write`. MUST complete before any other gate. Full procedure: `${CLAUDE_SKILL_DIR}/phase-6-handoff-reference.md` §2.5. Skipped when zero unresolved entries.
2. **Step 0 — Open-decision** per `decision: PRODUCT-DECISION` finding kept by Phase 4 judge. Skipped when zero.
3. **Action gate** — fire `AskUserQuestion` with the canonical 4 options. Never collapse into chat text ("Want me to apply these now?" / "Should I push?") — that bypasses the persisted-pick contract and silently drops options the user might want (e.g., Post Draft PR review). Option labels (verbatim, do not paraphrase):
   - `"/implement findings"` — append ` (Recommended)` when CRITICAL≥1 OR HIGH≥2; exits /review and the model surfaces `/geniro:implement .geniro/state/handoff/from-review-<branch>.md` as the next command.
   - `"Post Draft PR review"` — OMIT entirely when `pr-ref: none` OR zero unposted findings remain.
   - `"Continue rounds (re-review)"` — Round-N escalation gate fires when round ≥3.
   - `"Skip — keep findings on disk"` — append ` (Recommended)` when CRITICAL=0 AND HIGH≤1.

   Full AskUserQuestion shape (literal block), descriptions, and severity-driven recommendation rule: `${CLAUDE_SKILL_DIR}/phase-6-handoff-reference.md` §4. Persist user pick to `approvals[]` with category `action_gate`.
4. **Failing-tests gate** when state.md `## Authored Tests` non-empty.

Operational rules:

- **Reporter behavior** — no fix loop inside /review. /implement self-review (5-dim parallel) is a separate skill with a separate contract.
- **`--simplify`** does NOT change hand-off shape (still reporter).
- **Round-N escalation gate** when round ≥3 + "Continue rounds" pick — secondary AUQ (Continue / Escalate / Abort). Terminal `aborted` records `## Termination reason: repeated-failure: round-limit-3`.
- **Pre-Post unresolved-questions guard** (§7.0) — defensive re-check before `gh api POST /reviews`: aborts the Post drill if any `open_questions[].status == unresolved` remain. Fail-closed second line of defense against producers writing new entries mid-phase.
---

## ACI per-phase tool surface

| Phase | Allowed tools | Restricted |
|---|---|---|
| Phase 1 / 1.5 | Read, Grep, Glob, Bash (read-only — `gh pr view`, `git diff`, `which <tool>`, lint commands, `tsc --noEmit`), **`mcp__linear__*` (read-only — `get_issue` / `list_issues` for workflow integration; degrade silently if unregistered)** | No Edit/Write apart state.md; no Linear `update_issue` / `create_comment` from /review (those remain in /implement Ship) |
| Phase 2 / 3 / 4 | Agent (reviewer-agent, validation sub-agents, adversarial-tester-agent); Phase 3 dedup orchestrator-inline (no spawn) | No Edit/Write/Bash mutations |
| Phase 5 | Write (scoped to `.geniro/state/handoff/**`), `Bash` (conditional — `gh api POST /pulls/N/reviews` with `event` omitted; see §5.4), `emit-learning` helper | Direct edits outside scope blocked by hooks; never `gh api` with `event: COMMENT` / `APPROVE` / `REQUEST_CHANGES` |
| Phase 6 | AskUserQuestion | Read-only |

Existing safety hooks apply: file-protection, git-guardrails, `.geniro/` deletion guard, state-helper enforcement, plan-mode write-guard.

---

## Memory I/O Schedule

| Phase | Helper | Direction | MODE | Inputs | Outputs |
|---|---|---|---|---|---|
| Phase 1 entry | `load-custom-instructions` | read L4 | `initial-load` | scope = `review` + `global` + `code-style` | concatenated rule body |
| Phase 1 entry | `load-semantic` | read L3 | `refresh` | top-2: `_project.md` + `_CODEBASE_MAP.md` | inlined + drift check |
| Phase 1 entry | `query-learnings` | read L2 | n/a | tags inferred from changed-file paths; type bias `pitfall` | top-K matching entries (default K=5) |
| Phase 1 entry | `resolve-conflicts` | read L2/L3/L4 | n/a | three loaded layers | precedence-resolved |
| Phase 2 entry | `load-custom-instructions` | read L4 | `refresh` | scope = `review` + `global` + `code-style` | rule body (refreshed) |
| Phase 5 | `atomic_state_write` | write T2 | n/a | state file path; full body | whole-file rewrite |
| Phase 5b | `emit-learning` | write L2 | n/a | producer = /review; type = `pitfall`; trust = `verified` | append to `learnings.jsonl` |
| Phase 6 | `atomic_state_write` | write T2 | n/a | state file path; updated `approvals[]` | whole-file rewrite |

**L2 emit triggers** per patched contract:
- `pitfall` — **YES** — Phase 5b auto-emit when convergence ≥3.
- `convention` — Not. /implement owns.
- `decision` — Not. /plan owns.
- `diagnosis` — Not. /debug owns.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "/review should fix its own findings — parity with /implement self-review is good." | /implement self-review is a post-implementation gate inside a mutation skill. /review is a standalone read-only audit consumed by downstream skills (/implement, manual). Different workflows, different output contracts. Surface-level parity creates a false constraint and would re-introduce the deleted fixer responsibility. |
| "Mechanical pre-pass is too slow — skip it, LLM reviewers cover the same ground." | LLM reviewers cover similar ground at ~100× the cost with non-deterministic output. Lint detects a missing import faster and more reliably than a security reviewer would. Run cheap-deterministic first; LLM-spawn second with pre-pass findings as prior-context per Phase 1.5. |
| "I'll spawn only 4 dimensions — they cover the main risk surface for this diff." | All 7 always-dims are MANDATORY per §2.1. Conditional dims fire per their trigger rule. The cost of N parallel spawns is parallelized — wall-time is ~max(spawn-time), NOT sum. The cost of a missed CRITICAL finding is unbounded. Phase 4 §4.0 verification gate catches the trim; do not require the user to enforce it. |
| "The custom reviewer in `.geniro/instructions/review-extra/<slug>.md` is narrow scope — skip its discovery to save turns." | Discovery is a mechanical Glob + frontmatter parse — cheap. Custom reviewers exist because the user explicitly authored them; silently skipping defeats the entire `instructions/review-extra/` feature. Per Phase 1.5 §1.5.4, discovery runs in the mechanical pre-pass so Phase 2 has zero cognitive load for it. |
| "Just keep guidelines — duplicate finding is a feature, not a bug." | User-facing "told twice" is concrete UX friction. Two reviewers reporting the same thing wastes user attention. The specialized dim (conventions) wins on cost AND quality; let the dedicated reviewer own the finding category. |
| "Round-N hard ceiling at round 6 is paternalistic." | User picking "Continue" 5 times indicates either a bug in stratification or a workflow that belongs to /geniro:debug. Hard ceiling protects against accidental infinite-loop UX. User retains agency via the "Escalate" pick. |
| "Auto-drop MEDIUM findings to reduce user friction." | MEDIUM routes through the always-WAIT MEDIUM-gate per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`. Auto-dropping makes the skill less trustworthy — users notice when their MEDIUMs vanish silently. Never auto-drop. |
| "Bypass git guardrail hooks when Phase 5 PR comment post fails." | Hooks fail for a reason. Phase 5 is fail-closed — failure surfaces an error to chat and `## Errors`, does NOT auto-retry with `--no-verify`. Investigate root cause, fix, re-fire. |
| "I'll spawn the adversarial-tester-agent and ask the user to confirm later." | Inline-after-action gates rationalize into "this counts as approval". The Phase 4c invariant is `AskUserQuestion` BEFORE spawning, not after. The two-step gate (ask → on YES, spawn) is the only rationalization-resistant variant. |
| "The findings look obviously postable — I'll just batch-post to the PR and tell the user after." | Posting to a PR is an external write to a public surface. Phase 6 Action gate's "Post" selection IS the consent — without it, ambiguity that should have been resolved gets pushed onto the PR author or downstream reviewer. |
| "TDD mode is on, user clearly wants tests authored — skip the Phase 4c AUQ." | TDD mode flips the *Recommended* highlight, not the *gate*. The Phase 4c invariant is non-negotiable in every mode. Empty-answer fallback re-asks rather than auto-defaults. |
| "I'll auto-update Linear status from /review when findings are critical — saves the user a step." | /review is a Reporter. Linear `update_issue` / `create_comment` are external side-effect writes; only /geniro:plan and /geniro:implement run them per their workflow contracts. /review's MCP surface is read-only (`get_issue` / `list_issues`) per ACI. The Open Questions schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 lets /review surface ambiguity without mutating tracker state. |
| "Inline LINEAR CONTEXT into ALL 10 reviewer dims — more context = better review." | Cross-reviewer convergence anti-pattern: LINEAR CONTEXT helps spec-compliance (rubric source), pr-metadata (title-divergence check), and architecture (parent-epic linkage). Other dims see it as noise that biases their per-file rubric. The narrow 3-dim distribution is the documented pattern. |
| "--simplify is a natural place to add `simplify` as a new dimension." | That re-creates the deleted /deep-simplify skill as a disguised dim. The fold-into-existing approach (5 weighted dims via simplify-criteria.md prefix) is the documented absorption pattern — no new dim, no new fix-loop. |
| "Linear MCP unregistered — surface a HIGH finding so the user installs it." | Fail-open contract: degraded paths surface a one-line `## Caveats` note, not findings. The skill doesn't pressure users to install tooling — that's UX hostility. |

---

## Definition of Done

Code review is complete when:

- [ ] Phase 1 mode detection ran — Outgoing vs Incoming routed per `$ARGUMENTS` shape
- [ ] Phase 1 PLAN CONTEXT resolved
- [ ] Phase 1 Workflow integrations ran when `.geniro/workflow/*.md` non-empty — tracker ID detected (if present in `$ARGUMENTS` / `pr.title` / `pr.body` / spec.md frontmatter `workflow_refs[]`; sources deduplicated by `(kind, issue_id)`; m5-v1 and m5-v2 specs both accepted); `linear-task-ref` + `linear-parent-ref` populated in frontmatter; `LINEAR CONTEXT:` block built (or fail-open caveat surfaced)
- [ ] Phase 1 Peer-PR scout (PR-ref only) ran with extended scoring — `total_score = file_overlap + linear_bonus`; top-10 kept; per-sibling diff ≤200 lines; total cap 5K chars; PEER-PR CONTEXT fed to 6 dims
- [ ] Phase 1 Step 0.5 Round-N gate evaluated — round counter incremented; Round-N AUQ fired when round ≥3
- [ ] Phase 1 Step 0.7 risk-tier stratification ran — `risk-tier: <standard|high>` persisted; 4 downstream knobs adjusted
- [ ] Phase 1 Step 0.8 memory layers loaded (L4 instructions + L3 semantic + L2 learnings)
- [ ] Phase 1 git-workspace decision ran when input was a PR ref
- [ ] Phase 1.5 mechanical pre-pass ran — 3 checks (lint / schema / secret scan) with strict-mode secret-scan when risk-tier:high
- [ ] Phase 2 reviewers spawned and executed in parallel, each prompt carrying PLAN CONTEXT (spec-compliance dim only) + LINEAR CONTEXT (spec-compliance + pr-metadata + architecture dims only) + PEER-PR CONTEXT (6 dims) + PRIOR-ROUND FINDINGS + Mechanical Pre-pass Findings + alignment-tag instruction
- [ ] Phase 2 spec-compliance reviewer spawned when PLAN CONTEXT non-`none` AND (input was a PR ref OR risk-tier:high)
- [ ] Phase 2 `--simplify` flag prepended deep-simplify criteria to 5 dimensions (architecture / conventions / guidelines / bugs / optimizations) when present
- [ ] Phase 3 relevance-filter applied; `convergence_count` field populated per finding
- [ ] Phase 4 judge validation complete; Step 0 intent reconciliation applied (plan-authorized divergences demoted to `[INTENT-CHECK]`)
- [ ] Phase 4b per-finding validation run for CRITICAL/HIGH findings
- [ ] Phase 4c test-gate evaluated (skipped when no eligible findings or user declines); user approval persisted to `approvals[]`
- [ ] TDD mode only: Phase 4c Step 2 AUQ rendered with `(Recommended)` suffix on "Author tests…"; gate itself fired exactly as in Standard mode
- [ ] TDD mode only: Phase 6 Step 3.5 post-set filter applied
- [ ] Confidence scoring applied (≥80 threshold standard; ≥70 high tier)
- [ ] Issues classified by severity (Critical, High, Medium) and Decision Type ([FIX-NOW] | [TESTABLE] | [PRODUCT-DECISION] | [INTENT-CHECK])
- [ ] Findings tagged as [NEW] or [PRE-EXISTING] based on diff context
- [ ] Phase 5 state artifact written to `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` via `atomic_state_write`
- [ ] Phase 5b L2 pitfall auto-emit fired when any finding had `convergence_count ≥3`
- [ ] Phase 6 open-decision gate fired for every `[PRODUCT-DECISION]` finding (always-WAIT)
- [ ] Phase 6 Action gate fired (always-WAIT) — single consolidated decision; user pick persisted to `approvals[]` (category `action_gate`)
- [ ] Phase 6 Round-N escalation gate fired when round ≥3 + "Continue rounds" pick; terminal state mapped per- [ ] Phase 6 Action == Post drill ran (Steps 1.5-6) when user picked "Post"; `[POSTED-TO-PR]` markers persisted for idempotent re-run
- [ ] Phase 6 Failing-tests gate fired when `## Authored Tests` non-empty; firing order conditional on Action choice per the gate-chain rule
- [ ] Terminal state mapped to state.md `## Termination reason` per when `aborted` or `escalated`

---

## Anti-pattern check

This skill verified against master-plan 12-item guardrail. Status:
- One giant prompt: ✅ avoided (skill-scoped SKILL.md + reference files + criteria files)
- One giant tool: ✅ N/A
- Unbounded autonomous loop: ✅ Round-N 3-round bound + escalation gate
- Autonomous external sends in first release: ✅ Phase 6 Post drill AUQ-gated
- No approval state: ✅ `approvals[]` field with the categories (`tdd_mode_choice` / `test_gate_choice` / `action_gate` / `round_n_escalation` / `failing_tests_commit_policy`)
- No durable plans / goals: ✅ T2 state file mandatory
- No compaction strategy: ✅ the SessionStart hook re-injects via Block 5b/5c/5d
- All connectors loaded up front: ✅ N/A (MCP plugin model)
- High-risk tools without policy: ✅ existing hooks
- Subagents before single-agent MVP measured: ⚠️ partial (deferred to a future release)
- Dynamic timestamps in plugin Markdown: ✅ audited — none
- Non-deterministic agent registration: ✅ alphabetic by slug

This skill introduces no new anti-pattern regressions.
