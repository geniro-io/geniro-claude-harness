---
name: geniro:review
description: "Use when a comprehensive code review of pending changes is needed. 6-phase loop (triage → mechanical pre-pass → LLM reviewers (always-fire + conditional + N custom per §2.1) → filter → stratify → persist → action-gate). MANDATORY spawn list per §2.1. Always-fire dims include `regressions` (catches unintended deletes and behavior changes outside stated intent). Reporter behavior — emits a handoff file at .geniro/state/handoff/from-review-<branch>.md; downstream consumers (/implement, manual) apply fixes. Phase 6 Pre-gate resolves any unresolved open_questions[] from spec-compliance / pr-metadata / plan-context BEFORE the action-gate fires. Optional --simplify flag folds Reuse/Quality/Efficiency criteria into existing dims. Optional --tdd flag tightens Phase 4.2 per-finding verification + Phase 4.3 F→P test-gate. Phase 4.2 verifier runs on every §4.1 survivor (CRITICAL/HIGH/MEDIUM) — no tier-scaling."
context: main
model: inherit
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent, AskUserQuestion, WebSearch, EnterWorktree, ExitWorktree]
argument-hint: "[files, diff range, branch, or PR ref (#N, URL)] [--plan <path>] [--tdd] [--simplify]"
---

# Code Review Skill

Comprehensive code review using parallel multi-agent analysis.

**Detailed phase contracts:**
- `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` — Phase 1 input mode / scope / risk-tier / memory load.
- `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-verification-reference.md` — Phase 4.2 per-finding verifier contract (every CRITICAL/HIGH/MEDIUM survivor of §4.1).
- `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-3-test-gate-reference.md` — Phase 4.3 test-confirmation gate.
- `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` — Phase 6 action-gate hand-off + Post drill.
- `${CLAUDE_PLUGIN_ROOT}/skills/review/plan-context-reference.md` · `incoming-mode-reference.md` · `tdd-mode-reference.md` — PLAN CONTEXT load / INCOMING mode / `--tdd` semantics.

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

**Termination-case mapping** per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` §9. The `## Termination reason` body section is written on `aborted` / `escalated` terminals.

---

## Loop Invariants

The invariants apply unchanged:

1. **One result per tool call.** Phase 2 parallel-spawn reviewer-agents — each must return a structured result; dead spawn → `status: failed` entry in `## Tool log`.
2. **Args validated before execution.** `$ARGUMENTS` flag parsing (semantic, no CLI grammar); PR ref validation via `mcp__github__pull_request_read` or GraphQL fallback.
3. **Permission before side-effect.** Phase 6 "Post Draft PR" requires AUQ approval before posting to GitHub. The post is a single `gh api POST /repos/<owner>/<repo>/pulls/<number>/reviews` call per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` §7.5 — `event` field omitted so the review is created in GitHub's PENDING state (private to the reviewer, no notifications fire). State.md writes via `atomic_state_write`.
4. **Bounded and structured tool results.** Reviewer-agent output ≤4000 chars per dim; truncation marker. Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.
5. **Escalation gates, not silent abort.** Round-N ≥3 → Phase 6 escalation gate.
6. **Final answer grounded in observations — at every kept severity.** Phase 6 hand-off message MUST cite the state.md path; every kept finding body (CRITICAL / HIGH / MEDIUM) MUST include an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` that quotes the cited file or caller chain literally. The Phase 4.2 per-finding verifier (`${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-verification-reference.md` §3) formalizes this for every §4.1 survivor — empirical reproduction of the cited code is the load-bearing check that turns a reviewer's confidence score into grounded evidence.
7. **Errors → structured observations.** Reviewer spawn failures → `## Errors` body section. `gh` fail-open NOT silent — log to `## Errors`.
8. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.
9. **Re-verify ambiguity gates at external-effect boundaries.** §2.5 Pre-gate, §3 Step 0, and the Phase 4.2 per-finding verifier establish gate invariants on `open_questions[].status`, PRODUCT-DECISION `step0_status:`, and kept-finding `Validation:` respectively; §7.0 re-reads ALL THREE before any `gh api POST /reviews` because mid-phase producer writes, parallel resolvers, or orchestrator drift can re-create unresolved ambiguity (or surface a `Validation: refuted` finding that bypassed the upstream filter) between the upstream gate and the external write. Never trust an upstream gate's invariant at a public-surface boundary.

`## Tool log` schema: typical run produces 5-12 entries (1 per reviewer + 1 per Phase 5.3 emit-learning + 1 per PR-side-effect).

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
| LLM reviewer spawn count | always-fire + conditional + custom dims (per §2.1) in parallel | §2.1 dimension grid + Phase 1.5 §1.5.4 custom-reviewer discovery |
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
| `adversarial-tester-agent` (Phase 4.3 only) | OMIT | Frontmatter `model: inherit` |
| Per-finding validation sub-agents (CRITICAL / HIGH / MEDIUM) | OMIT | Frontmatter `model: inherit` |

---

## Phase 1 — Triage & Context Collect

State.md `phase: triage`. **Full contract:** `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md`.

Summary of what Phase 1 does:

1. **Step 0 — Workspace setup** — passive context detection (IN_WORKTREE, REVIEW_HANDOFF, DEBUG_HANDOFF, IMPLEMENT_TASK_STATE, BRANCH_MATCHES_TASK_SLUG, PROTECTED_BRANCH, TARGET_PR_NUMBER, IN_TARGET_WORKTREE) followed by a decision tree with auto-continue branches for in-worktree continuing-work signals. Workspace AUQ (single question — workspace decision) fires only when ambiguous. Inline modifier overrides (`worktree` / `no-worktree` / `current-branch` / `new-branch`) win deterministically. Approvals persist as `review_workspace_setup` to survive compaction and Round 2+ re-runs. /review never mutates workflow tracker status — that is `/geniro:plan` and `/geniro:implement` territory; /review reads tracker context only (see item 5). Fires BEFORE all subsequent items so they operate on the correct working tree. Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §0.
2. **Input mode detect** — OUTGOING / INCOMING / pr-ref routing per `$ARGUMENTS`. Anchored NL signals ("process review on #N") route to INCOMING; PR ref + K>0 unresolved threads fires Mode AUQ.
3. **Scope resolution** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. NEVER invoke `gh pr list` to invent a target.
4. **PR-ref parsing** — `gh pr diff` + `gh pr view --json baseRefName,headRefName,body,title,headRefOid,url,isDraft,author,labels`. From the thread-state fetch (`reviewThreads[]` per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §1), persist every `isResolved == true` thread's `path:line` to state.md frontmatter `resolved-threads-snapshot:` so the Phase 6 Post drill's §7.1 input-side dedup can exclude findings overlapping already-resolved threads. Leave `resolved-threads-snapshot: null` when no PR ref or the fetch fails (§7.1 treats absence as "no dedup").
5. **Workflow integrations** — workflow files (`.geniro/workflow/*.md`) live in the primary worktree per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (Mode A); glob both `./.geniro/workflow/*.md` (cwd-local — uncommitted local edits win) and `<PRIMARY_ROOT>/.geniro/workflow/*.md` (primary fallback). Read them, apply tracker-ID regex against `$ARGUMENTS` + `pr.title` + `pr.body`, AND when a spec.md is resolvable (via `--plan <path>`, `geniro-plan:` PR-body line, walk-up `.geniro/planning/*/spec.md`, or canonical project paths) parse its frontmatter `workflow_refs[]` per `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md`. Accept both `geniro_schema_version: m5-v1` (treat field as absent) and `m5-v2` (read entries). Merge sources by `(kind, issue_id)` — `$ARGUMENTS` reference wins on conflict (user just typed it, fresher signal); PR body next; spec.md frontmatter as fallback. On Linear match with MCP available: fetch issue (+ parent epic + sibling sub-tasks). Build `LINEAR CONTEXT:` block. Persist `linear-task-ref:` + `linear-parent-ref:` to state.md frontmatter, derived from the deduplicated merged list. Read-only — /review never mutates tracker state via MCP. Fail-open if MCP unavailable.
6. **Peer-PR scout** (PR-ref only) — top-10 sibling PRs scored by file overlap + Linear-relatedness bonus (parent-epic / sibling-sub-task matches); inlined into reviewer prompts (architecture + design + bugs + conventions + optimizations + spec-compliance + regressions).
7. **Load custom instructions** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` (MODE: initial-load; scope = `review` + `global` + `code-style` — pipeline tier, 3 files).
8. **Round-N counter** — increments and fires Round-N AUQ when round ≥3.
9. **PLAN CONTEXT load (schema-aware).** Detection per `${CLAUDE_PLUGIN_ROOT}/skills/review/plan-context-reference.md` Structured-section parser when `geniro_kind: design-doc` frontmatter present; prose fallback otherwise.
10. **Risk-tier stratification** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` 9 hard-escalation signals. Sets `risk-tier: standard | high`. Adjusts 4 downstream knobs (severity threshold / validator budget / spec-compliance default / mechanical secret-scan strict mode).
11. **Memory layer load:** `load-custom-instructions` MODE:refresh + `load-semantic` MODE:refresh + `query-learnings` (top-K, K=5 default) + `resolve-conflicts`.
12. **Mode AUQ** (Standard vs TDD) when neither `--tdd` nor `--standard` in `$ARGUMENTS`. Persist to `approvals[]` with category `tdd_mode_choice`.
13. **Size triage** — classify files Trivial / Substantive when diff >8 files or >400 LOC. Controls Phase 2 Standard vs Batched mode.

Exit criterion: state.md frontmatter populated with `mode`, `round`, `risk-tier`, `pr-ref`, `linear-task-ref`, `linear-parent-ref`, `plan-context-ref`, `simplify-mode`, all populated; `approvals[]` carries any AUQ answers; `## Tool log` includes initial load echoes.

Phase 1 PR metadata and tracker context loads are orchestrator-inline (`gh pr diff` / `gh pr view` / `mcp__linear__*` reads). For codebase-research side queries inside this phase (e.g., locating a pattern across the wider repo when scoring peer-PR overlap), spawn `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

---

## Phase 1.5 — Mechanical Pre-pass

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

**Risk-tier:high strict mode** adds:
- `(?:AWS|GCP|AZURE)_(?:SECRET|ACCESS)_KEY=`
- GCP service-account JSON markers (`"type": "service_account"`)
- Azure SAS tokens (`?si=.+&sig=`)
- SSH OPENSSH key patterns

Findings tagged `severity: CRITICAL` (secrets are always critical).

### 1.5.4 Custom-reviewer discovery

**Resolve `PRIMARY_ROOT` first.** Run the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` via Bash before invoking the helper — the helper requires the slot in scope to dual-glob local + main-worktree `review-extra/` files, and a linked worktree's `.geniro/instructions/` is gitignored and may be empty.

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

### 2.1 Dimension grid (11 built-in dimensions + N custom)

| # | Dimension | Spawn rule (MANDATORY) |
|---|---|---|
| 1 | bugs | Always fires — no exception |
| 2 | security | Always fires — no exception |
| 3 | architecture | Always fires — no exception |
| 4 | tests | Always fires — no exception |
| 5 | optimizations | Always fires — no exception |
| 6 | guidelines | Always fires — no exception |
| 7 | conventions | Always fires — no exception. Owns repo-modal-pattern findings exclusively |
| 8 | regressions | Always fires — no exception. Catches unintended deletes + behavior changes outside stated intent (PR body / spec.md / commit msg). 3 signals: deleted-symbol caller-blast, intent-vs-behavior over-reach, test-coverage delta. Criteria: `${CLAUDE_PLUGIN_ROOT}/skills/review/regressions-criteria.md` |
| 9 | design | Fires when UI globs match changed files (see §2.4 UI-file detection rule) |
| 10 | pr-metadata | Fires when `pr-ref:` is non-none |
| 11 | spec-compliance | Fires when PLAN CONTEXT is non-none AND (`pr-ref:` non-none OR risk-tier:high) |
| +N | custom:* | Fires per user-authored `.geniro/instructions/review-extra/<slug>.md`, discovered in Phase 1.5 |

**Spawn-batch size.** Phase 2 MUST spawn a reviewer-agent for every row whose trigger fires:

- 8 always-rows (bugs, security, architecture, tests, optimizations, guidelines, conventions, regressions) fire on every run.
- 3 conditional rows (design, pr-metadata, spec-compliance) fire when their trigger column is satisfied.
- N custom rows fire per the spawn-specs already discovered in Phase 1.5 §1.5.4 (zero discovery work at Phase 2 entry — read the count from state.md frontmatter `custom_reviewers`).

Total batch size = always-fire + triggered conditional + custom rows. Trimming this set silently is the documented anti-pattern — see §Anti-rationalization. Post-spawn verification in Phase 4 §4.0 catches drift.

**Refresh L4 instructions** at Phase 2 entry — apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `MODE: refresh`. Compaction since the previous load may have silently dropped the rules.

**Read custom-reviewer specs** from state.md frontmatter `custom_reviewers[]` — populated in Phase 1.5 §1.5.4 via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` discovery. Append one `Agent(subagent_type="reviewer-agent",...)` per spec to the same parallel batch as the built-ins.

### 2.2 Pre-spawn declaration (state.md write before parallel batch)

Before firing the parallel `Agent(...)` batch, the orchestrator computes the declared spawn list and writes it to state.md via `atomic_state_write`:

```yaml
# frontmatter update
spawn_dims_declared: [bugs, security, architecture, tests, optimizations, guidelines, conventions, regressions, pr-metadata, spec-compliance, custom:manifest-incident-patterns]
spawn_dims_count: 11
```

Plus a `## Tool log` entry:

```
[Phase 2 spawn declaration] dim_list=[bugs, security, architecture, tests, optimizations, guidelines, conventions, regressions, pr-metadata, spec-compliance, custom:manifest-incident-patterns]; count=11; triggers={pr-ref: <ref-or-none>, plan-context: <path-or-none>, linear-task: <id-or-none>, custom-reviewers-discovered: <N>}
```

This is observability for the Phase 4 §4.0 verification gate — declared-vs-actual is one grep away.

### 2.3 Spawn invocation

Before firing the parallel batch, narrate the spawn to the user — read the `spawn_dims_declared[]` list from state.md (written in §2.2), render dim slugs in plain English (`guidelines` -> "code quality", `pr-metadata` -> "PR metadata", `spec-compliance` -> "specification compliance"; the slugs `bugs / security / architecture / tests / optimizations / conventions / regressions` are already plain-English — surface verbatim; custom reviewers render as `custom: <slug>`). Emit a one-line status:

> Spawning <N> reviewers: <comma-separated plain-English list>.

Then fire the parallel batch — single message with N parallel `Agent` tool uses, one per dimension. Each spawn:

- `subagent_type: reviewer-agent` (plugin) — apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration-degradation ladder.
- OMIT `model=` argument — reviewer-agent declares `model: inherit`. Custom reviewers that declare an explicit tier in their `.geniro/instructions/review-extra/<slug>.md` frontmatter pass that tier verbatim; otherwise OMIT.
- Pre-inlined context per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`:
  - Diff of changed files (full content for the batch's files in Batched Mode; all files in Standard Mode).
  - Project conventions from L4 (refreshed).
  - Mechanical pre-pass findings (Phase 1.5) as prior-context under `## Mechanical Pre-pass Findings`.
  - PLAN CONTEXT — spec-compliance + regressions dims ONLY (other dims see `PLAN CONTEXT: <plan tag fields only>` per the schema-aware reference).
  - LINEAR CONTEXT — spec-compliance + pr-metadata + architecture + regressions dims ONLY. Omitted for other dims.
  - PR metadata (pr.body / pr.title / commit messages) — flows via the pr-metadata reviewer's existing context channel; spec-compliance and regressions dims read it through the same channel when fired on a PR ref. No separate `PR CONTEXT:` slot is composed.
  - PRIOR-ROUND FINDINGS (Round-N counter sub-step prior-round-summary, or `none — first review`).
  - PEER-PR CONTEXT — architecture + design + bugs + conventions + optimizations + spec-compliance + regressions dims ONLY.
  - Dimension-specific criteria file body inlined.
  - Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.

After the parallel batch returns, narrate completion before transitioning to §3:

> All <N> reviewers returned. Aggregating findings.

Surface any `status: failed` entries by their plain-English dim name (e.g., "PR metadata reviewer failed — see `## Errors`"), not by raw slug.

**Criteria files** (read once at Phase 2 entry):
- `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md` · `security-criteria.md` · `architecture-criteria.md` · `tests-criteria.md` · `optimizations-criteria.md` · `guidelines-criteria.md` · `conventions-criteria.md` · `regressions-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/design-criteria.md` (conditional per §2.5)
- `${CLAUDE_PLUGIN_ROOT}/skills/review/pr-metadata-criteria.md` (conditional)
- `${CLAUDE_PLUGIN_ROOT}/skills/review/spec-compliance-criteria.md` (conditional per §2.6)
- Custom reviewer criteria from spawn-specs returned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` (≤10 per project)

### 2.4 `--simplify` flag weighting

When `$ARGUMENTS` contains `--simplify` (semantic parse — matches `simplify`, `--simplify`, `simplify mode`), Phase 2 prepends deep-simplify criteria onto 5 of the built-in dimensions:

- **architecture** reviewer — Reuse criteria (existing abstractions, duplicate logic, premature abstraction).
- **conventions** reviewer — repo-modal-pattern aggressive mode (lower ≥80% siblings threshold to ≥60%).
- **guidelines** reviewer — Quality criteria (naming clarity, docs noise, dead code).
- **bugs** reviewer — Quality bug-class extensions (defensive code that masks bugs, redundant null checks).
- **optimizations** reviewer — Efficiency criteria (verbose loops, unnecessary allocations, sync I/O in async paths).

Pre-pend body read from `${CLAUDE_PLUGIN_ROOT}/skills/review/simplify-criteria.md`.

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
- **Convergence_count:** for each dedup'd finding, count how many reviewers + mechanical checks reported the same key. Persisted as a field on the finding (consumed by Phase 5.3 auto-emit threshold).
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
2. Fire `AskUserQuestion` with header `"Review incomplete"`:
   - A) `"Re-run the missing reviewers now"` — issue `Agent(...)` per missing dim; once results land, recompute `actual` and re-verify. (Recommended)
   - B) `"Skip the missing reviewers and continue"` — append to body `## Accepted Gaps`; continue to §4.1.
   - C) `"Abort review"` — terminal `phase: aborted`; `## Termination reason: spawn-batch-incomplete (<missing>)`.

Always-WAIT — empty answer = upstream bug, fall back to plain text. NEVER auto-default to "skip".

When `missing` is empty, proceed directly to §4.1.

### 4.1 Multi-signal threshold filter

`severity ≥ MEDIUM` is necessary but NOT sufficient. A finding admitted to Phase 4 must clear one of FOUR independent signals — any one passes. Convergence + evidence-grounding are documented as more reliable than LLM self-confidence (citations: `${CLAUDE_PLUGIN_ROOT}/skills/review/severity-calibration-reference.md` §4).

KEEP rule (admit to Phase 4.2 verifier + Phase 5 stratify) — `severity >= MEDIUM` AND ONE OF:
1. `convergence_count >= 2` — finding raised by 2+ independent reviewer dims (k-review pattern; cross-dim agreement beats any single dim's self-rating). `convergence_count` is set during §3.1 dedup.
2. `Evidence-Block present AND properly formatted` AND `confidence >= 60` — cites a real file:line per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. "Properly formatted" = Evidence-Block fence OR file:line pattern + ≥2 quoted lines (mechanical check at §4.1 entry on each finding's `Evidence:` field; false on missing; orchestrator does NOT re-read the cited file — Phase 4.2 verifier handles that for every §4.1 survivor).
3. Pre-resolved override marker — tagged by a criteria file as pre-resolved priority (e.g., `simplify-criteria.md` P1/P2; `regressions-criteria.md` signal-table-flagged HIGH).
4. `confidence >= 80` — advisory fallback for findings without convergence or evidence. High tier (`risk-tier: high`) relaxes this to `confidence >= 70` (matches the legacy threshold); other signals unchanged. `--tdd` does not affect §4.1 admission (only Phase 4.2 verifier scope).

Additional admission constraint for MEDIUM: a MEDIUM finding requires signal #2 (Evidence-Block present + properly formatted). Signals #1, #3, #4 alone admit CRITICAL and HIGH but NOT MEDIUM — Loop Invariant #6 mandates Evidence at CRITICAL / HIGH / MEDIUM, so a MEDIUM without Evidence drops to `## Deferred — sub-threshold` regardless of convergence or confidence score.

DEFER rule (write to `## Deferred — sub-threshold` for user awareness; do NOT post to PR; do NOT populate `open_questions[]`):
- `severity < MEDIUM` — always deferred per `${CLAUDE_PLUGIN_ROOT}/skills/review/severity-calibration-reference.md` §5.
- `severity >= MEDIUM` that fails ALL FOUR signals above.

### 4.2 Per-finding empirical-reproduction verification

Every finding surviving Phase 4.1 — CRITICAL, HIGH, AND MEDIUM — gets ONE fresh `reviewer-agent` spawn in verify-finding mode (parallel batch, single assistant turn). No tier-scaling, no severity-scaling — every §4.1 survivor is verified regardless of `risk-tier` or `--tdd`. The §4.1 multi-signal gate already constrains the survivor set to findings with Evidence-Block-grade citations (signal #2 mandatory for MEDIUM per §4.1; Loop Invariant #6 mandates Evidence at every kept severity), so every survivor has a concrete file:line for the verifier to re-read.

For each kept finding, the orchestrator reads the cited `file:line` ± 30 lines, greps the key symbol's 1-hop callers (cap 50 lines) + test dirs (cap 20 lines), then composes a verify-finding spawn carrying ONLY the finding body + cited slice + grep outputs (NOT the full reviewer bundle — isolated context prevents anchoring). All verifier spawns fire in ONE assistant response using the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (OMIT `model=` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`).

Each verifier emits: `validation: confirmed | refuted | clarified`, `recommended_action: fix-now | testable | product-decision | intent-check | drop`, `confidence: 1-5`, `evidence: "<file:line quote>"`.

Aggregation:
- `refuted` findings move to `## Filtered`. Do NOT propagate to §4.3 F→P gate, Phase 5 stratify, or T2 handoff.
- `clarified` findings keep severity but update `decision-type` to the verifier's `recommended_action`; verifier confidence and evidence append to the finding body.
- `confirmed` findings retain decision-type; verifier confidence and evidence append.

A `refuted` verdict on a CRITICAL is high-impact (the finding drops out of the handoff entirely). The verifier contract requires a literal quote from the cited file showing the defect is NOT present (paraphrased "looks fine" is insufficient). See `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-verification-reference.md` §6 for the anti-sycophancy guard.

Full prompt template, isolated-context contract, anti-sycophancy guard, and worked examples: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-verification-reference.md`.

### 4.3 Failing-to-passing test-confirmation gate

**Full contract:** `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-3-test-gate-reference.md`.

Summary:
- Filter findings by decision-type per the runtime-behavior classification rule.
- **Mandatory user-approval gate before any `adversarial-tester-agent` spawn.** Skill MUST NEVER spawn without approval — the gate IS the load-bearing safety property. Persist to `approvals[]` with category `test_gate_choice`.
- `--tdd` flag flips the Recommended option to "Author tests for all eligible findings"; gate itself still fires.
- Spawn ONE adversarial-tester-agent with eligible findings as hypothesis seeds. Orchestrator's independent re-run IS the gate; never trust the agent's red/green claim alone.
- Demote-don't-delete: green tests demote findings to `## Filtered` with `[CHALLENGED-BY-TEST]` tag; original severity preserved for re-elevation.
- Fail-open: agent failures surface "test-gate fail-open" under `## Caveats` + write `## Errors` entry.

### 4.4 `--simplify` flag interaction

`--simplify` does NOT change Phase 4 thresholds or validator behavior. Simplify severities map P1→HIGH, P2→MEDIUM, P3→informational (per `${CLAUDE_PLUGIN_ROOT}/skills/review/simplify-criteria.md`): P1/P2 pass through Phase 4 like native HIGH/MEDIUM findings; P3 is filtered out of Phase 4 unless `--tdd` or risk-tier:high.

---

## Phase 5 — Persist & Emit

State.md `phase: persist`.

### 5.1 Handoff file write

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` per row. `<PRIMARY_ROOT>` resolved per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A.

**Write via `atomic_state_write`** — never direct Edit/Write on the canonical state path (the `enforce-state-helper` hook will warn-mode flag direct writes; PR-final will hard-block).

**`open_questions[]` rich-field authoring contract.** When composing `open_questions[]` entries from kept findings, fill the optional `context` / `evidence` / `options` / `recommendation` fields per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2. The reviewer-agent output already carries Evidence / Why-matters / Suggested-fix / Options per `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format — copy them into the open_question entry, do NOT discard them at composition time. Bare `question:` entries trigger the §2.5 Tier 3 fallback (terse AUQ), which the user experiences as the failure mode the rich-field schema was added to prevent. For non-finding open_questions (e.g., process / scope / verification questions surfaced by spec-compliance or pr-metadata reviewers), author `context` + `options` + `recommendation` inline — the reviewer's `## Why this matters` and `## Suggested fix` synthesis fields are still the source material; the consumer has no other way to render the question richly.

**`step0_status:` producer-side initialization contract.** When writing each PRODUCT-DECISION finding into `## Findings`, also write `step0_status: pending` as the last sub-field of its body block (schema at `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` §"Per-finding body schema"). This is the runtime sentinel §3 flips to `resolved` (or `wontfix`) after the per-finding AUQ pick lands, and the §7.0 Pre-Post guard re-reads to fail-close before posting. Omit the field entirely for non-PRODUCT-DECISION findings — its presence is the marker that §3 owes them an AUQ.

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
geniro_schema_version: m6-v2
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
<reviewer spawns + side-effects>

## Errors
<failed spawns, gh fail-open, mechanical-prepass failures>

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
<!-- Populated when downstream consumer (or /review's §2.5 Pre-gate) resolves an entry; mirrors frontmatter `open_questions[].resolution`. -->

### q1 — <source>: <one-line summary>
**Picked:** <chosen option>
**At:** <ISO-8601 UTC>
**Resolved by:** <skill — review | implement | manual>
**Phase:** <phase that ran the resolution AUQ>

## Termination reason
<rendered per phase-6-handoff-reference.md §9 — only on aborted | escalated state>

## Persisted approvals
<rendered from approvals[] frontmatter for user-readability>
EOF
```

**T2 extensions for in-run state-tracking:** The canonical handoff is a one-shot producer→consumer artifact; /review extends it with `phase:`/`status:`/`round:`/`approvals[]` to enable mid-run compaction recovery. The file functions as a T2 handoff AT REST (after Phase 5 persist) and as a T1-like state file DURING THE RUN.

**Per-finding body schema** — multi-line block per finding under `## Findings` (NOT a one-liner). Full schema + backward-compat parsing contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` §"Per-finding body schema". Phase 4 judge MUST preserve every reviewer-agent field listed there when persisting findings; dropping fields to reach a one-liner is the failure mode the schema exists to prevent.

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

Helper: `${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh`. Dedup + sanitization per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md`.
Threshold is fixed at convergence_count ≥3 (3 reviewers OR 2 reviewers + 1 mechanical check).

Also emit `convention` learnings — NOT for this skill. /implement owns convention emits per patched contract.

### 5.4 PR comment posting (conditional — gated by Phase 6)

If Phase 6 user picks "Post Draft PR" option, post the finding list as a PENDING review per the canonical procedure in `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` §7.5: one `gh api POST /repos/<owner>/<repo>/pulls/<number>/reviews` call, `event` field omitted from the jq payload. GitHub creates the review in PENDING state — visible only to the reviewer on github.com's "Finish your review" panel, no notifications fire until the human clicks Submit. Never pass `event: COMMENT` / `APPROVE` / `REQUEST_CHANGES` (those submit the review and defeat the "draft" semantics the user asked for); `event: "PENDING"` is INVALID — omission is the correct mechanism.

`mcp__github__pull_request_review_write` is NOT used here — the MCP wrapper does not surface the per-comment `path` / `line` / `side` fields required for inline anchoring, so the canonical tool is `gh api` directly per the reference. State persistence per `atomic_state_write`:

```yaml
non-resumable-actions:
- action: pr-review-comment-batch
completed-at: <ISO-8601>
pr-ref: <owner>/<repo>#<num>
finding-count: <N>
comment-ids: [<id1>, <id2>,...]
```

PR post fails fail-closed — on non-zero `gh api` exit (HTTP error, missing scopes, secondary rate limit), write `## Errors` entry + abort Phase 5; never silently downgrade to top-level `gh pr comment` or retry with `event: COMMENT`.

Full Post drill (Steps 0-6) in `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md`.
### 5.5 Idempotent re-entry

If Phase 5 re-enters after compaction:
1. Read state.md `non-resumable-actions[]` — if PR post already completed, skip re-post.
2. Re-read findings from Phase 3 dedup output (held in context OR re-runs Phase 3 if context lost).
3. Re-write `from-review-<branch>.md` (overwrite — `atomic_state_write` handles atomicity).

---

## Phase 6 — Action Gate Hand-off

State.md `phase: action-gate`. **Full contract:** `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md`.

Summary of the gate chain (each gate is its own AUQ — never collapsed):

1. **Pre-gate — Resolve Open Questions** fires first whenever frontmatter `open_questions[]` has any entry with `status: unresolved`. Chain one AUQ per unresolved entry (cap-extension >4). Always-WAIT. Resolutions persist back via `atomic_state_write`. MUST complete before any other gate. Full procedure: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` §2.5. Skipped when zero unresolved entries.
2. **Step 0 — Open-decision** per `Decision Type: PRODUCT-DECISION` finding kept by Phase 4 judge. Skipped when zero.
3. **Action gate** — fire `AskUserQuestion` with the canonical 4 options. Never collapse into chat text ("Want me to apply these now?" / "Should I push?") — that bypasses the persisted-pick contract and silently drops options the user might want (e.g., Post Draft PR review). Option labels (verbatim, do not paraphrase):
   - `"/implement findings"` — append ` (Recommended)` when CRITICAL≥1 OR HIGH≥2; exits /review and the model surfaces `/geniro:implement .geniro/state/handoff/from-review-<branch>.md` as the next command.
   - `"Post Draft PR review"` — OMIT entirely when `pr-ref: none` OR zero unposted findings remain.
   - `"Continue rounds (re-review)"` — Round-N escalation gate fires when round ≥3.
   - `"Skip — keep findings on disk"` — append ` (Recommended)` when CRITICAL=0 AND HIGH≤1.

   Full AskUserQuestion shape (literal block), descriptions, and severity-driven recommendation rule: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` §4. Persist user pick to `approvals[]` with category `action_gate`.
4. **Failing-tests gate** when state.md `## Authored Tests` non-empty.

Operational rules:

- **Reporter behavior** — no fix loop inside /review. /implement self-review (5-dim parallel) is a separate skill with a separate contract.
- **`--simplify`** does NOT change hand-off shape (still reporter).
- **Round-N escalation gate** when round ≥3 + "Continue rounds" pick — secondary AUQ (Continue / Escalate / Abort). Terminal `aborted` records `## Termination reason: repeated-failure: round-limit-3`.
- **Pre-Post unresolved-ambiguity guard** (§7.0) — defensive re-check before `gh api POST /reviews`: aborts the Post drill if any `open_questions[].status == unresolved` OR any PRODUCT-DECISION finding has `step0_status: pending`. Fail-closed second line of defense against producers writing new entries mid-phase or §3 being skipped under drift.
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
| Phase 5.3 | `emit-learning` | write L2 | n/a | producer = /review; type = `pitfall`; trust = `verified` | append to `learnings.jsonl` |
| Phase 6 | `atomic_state_write` | write T2 | n/a | state file path; updated `approvals[]` | whole-file rewrite |

**L2 emit triggers** per patched contract:
- `pitfall` — **YES** — Phase 5.3 auto-emit when convergence ≥3.
- `convention` — Not. /implement owns.
- `decision` — Not. /plan owns.
- `diagnosis` — Not. /debug owns.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "/review should fix its own findings — parity with /implement self-review is good." | /implement self-review is a post-implementation gate inside a mutation skill. /review is a standalone read-only audit consumed by downstream skills (/implement, manual). Different workflows, different output contracts. Surface-level parity creates a false constraint and would re-introduce the deleted fixer responsibility. |
| "Mechanical pre-pass is too slow — skip it, LLM reviewers cover the same ground." | LLM reviewers cover similar ground at ~100× the cost with non-deterministic output. Lint detects a missing import faster and more reliably than a security reviewer would. Run cheap-deterministic first; LLM-spawn second with pre-pass findings as prior-context per Phase 1.5. |
| "I'll spawn only 4 dimensions — they cover the main risk surface for this diff." | Every always-fire dim per §2.1 is MANDATORY. Conditional dims fire per their trigger rule. The cost of N parallel spawns is parallelized — wall-time is ~max(spawn-time), NOT sum. The cost of a missed CRITICAL finding is unbounded. Phase 4 §4.0 verification gate catches the trim; do not require the user to enforce it. |
| "The custom reviewer in `.geniro/instructions/review-extra/<slug>.md` is narrow scope — skip its discovery to save turns." | Discovery is a mechanical Glob + frontmatter parse — cheap. Custom reviewers exist because the user explicitly authored them; silently skipping defeats the entire `instructions/review-extra/` feature. Per Phase 1.5 §1.5.4, discovery runs in the mechanical pre-pass so Phase 2 has zero cognitive load for it. |
| "Just keep guidelines — duplicate finding is a feature, not a bug." | User-facing "told twice" is concrete UX friction. Two reviewers reporting the same thing wastes user attention. The specialized dim (conventions) wins on cost AND quality; let the dedicated reviewer own the finding category. |
| "I'll tag this LOW finding as MEDIUM so it surfaces past the threshold filter." | The Phase 4.1 multi-signal gate (§4.1) provides four independent signals for a correct finding to surface (convergence_count ≥2, Evidence-Block + confidence ≥60, criteria-pre-resolved marker, confidence ≥80 fallback) — the confidence threshold is one of four, not a load-bearing primary. Inflating severity to game the gate corrupts the severity taxonomy for downstream consumers (verifier, stratifier, /implement consumer) AND surfaces low-impact findings on the PR. Trust the multi-signal gate; let LOW be LOW. |
| "Auto-drop MEDIUM findings to reduce user friction." | /review is a Reporter with no fix loop, so no MEDIUM-gate AUQ ever fires here. MEDIUMs run through the §4.1 multi-signal filter: those clearing a signal are admitted to the findings list; sub-threshold MEDIUMs are written to `## Deferred — sub-threshold` for user awareness (never posted to PR, never silently dropped). Auto-dropping makes the skill less trustworthy — users notice when their MEDIUMs vanish silently. |
| "I'll spawn the adversarial-tester-agent and ask the user to confirm later." | Inline-after-action gates rationalize into "this counts as approval". The Phase 4.3 invariant is `AskUserQuestion` BEFORE spawning, not after. The two-step gate (ask → on YES, spawn) is the only rationalization-resistant variant. |
| "The findings look obviously postable — I'll just batch-post to the PR and tell the user after." | Posting to a PR is an external write to a public surface. Phase 6 Action gate's "Post" selection IS the consent — without it, ambiguity that should have been resolved gets pushed onto the PR author or downstream reviewer. |
| "TDD mode is on, user clearly wants tests authored — skip the Phase 4.3 AUQ." | TDD mode flips the *Recommended* highlight, not the *gate*. The Phase 4.3 invariant is non-negotiable in every mode. Empty-answer fallback re-asks rather than auto-defaults. |
| "I'll auto-update Linear status from /review when findings are critical — saves the user a step." | /review is a Reporter. Linear `update_issue` / `create_comment` are external side-effect writes; only /geniro:plan and /geniro:implement run them per their workflow contracts. /review's MCP surface is read-only (`get_issue` / `list_issues`) per ACI. The Open Questions schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 lets /review surface ambiguity without mutating tracker state. |
| "Inline LINEAR CONTEXT into every dim — more context = better review." | Cross-reviewer convergence anti-pattern: LINEAR CONTEXT helps spec-compliance (rubric source), pr-metadata (title-divergence check), architecture (parent-epic linkage), and regressions (intent classification). Other dims see it as noise that biases their per-file rubric. The narrow 4-dim distribution is the documented pattern. |
| "Regressions dim feels redundant with spec-compliance — skip it on PRs that have a spec." | spec-compliance covers diff-omits-spec-item; regressions covers diff-exceeds-stated-intent. They're inverse directions, not duplicates. Regressions also fires on spec-less PRs where spec-compliance can't (matches user mental model: catch unintended changes broadly). |
| "Per-finding verifier agreed with the finding — confirmation logged, done." | Confirmation without an `evidence:` quote from the cited file or caller chain is rationalization theater. If the verifier didn't quote literal code, the verification didn't happen — re-spawn with stricter prompt. Sycophancy is the documented multi-judge failure mode. Additional anti-rationalization guards for the hoisted §4.2 scope (sampling pressure, CRITICAL-skip rationalization) live in `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-verification-reference.md` §6. |
| "Round 1 returned clean. Run round 2 to confirm / get a nicer summary line / second opinion." | Clean = Done. The Round-N escalation gate (Loop Invariant #5) ends the flow on clean result; do not loop back into Phase 2 for cosmetic polish or a "second opinion." Extra rounds waste compute AND risk hallucinated findings against an empty diff. Once a round exits with zero kept findings, the Phase 6 Action gate is the terminal step. |

---

## Definition of Done

Code review is complete when:

- [ ] Phase 1 mode detection ran — Outgoing vs Incoming routed per `$ARGUMENTS` shape
- [ ] Phase 1 PLAN CONTEXT resolved
- [ ] Phase 1 Workflow integrations ran when `.geniro/workflow/*.md` non-empty — tracker ID detected (if present in `$ARGUMENTS` / `pr.title` / `pr.body` / spec.md frontmatter `workflow_refs[]`; sources deduplicated by `(kind, issue_id)`; m5-v1 and m5-v2 specs both accepted); `linear-task-ref` + `linear-parent-ref` populated in frontmatter; `LINEAR CONTEXT:` block built (or fail-open caveat surfaced)
- [ ] Phase 1 Peer-PR scout (PR-ref only) ran with extended scoring — `total_score = file_overlap + linear_bonus`; top-10 kept; per-sibling diff ≤200 lines; total cap 5K chars; PEER-PR CONTEXT fed to (architecture + design + bugs + conventions + optimizations + spec-compliance + regressions)
- [ ] Phase 1 Round-N counter incremented + AUQ fired when round ≥3; risk-tier stratification ran (`risk-tier: <standard|high>` persisted; 4 downstream knobs adjusted); memory layers loaded (L4 instructions + L3 semantic + L2 learnings)
- [ ] Phase 1 git-workspace decision ran when input was a PR ref
- [ ] Phase 1.5 mechanical pre-pass ran — 3 checks (lint / schema / secret scan) with strict-mode secret-scan when risk-tier:high
- [ ] Phase 2 reviewers spawned and executed in parallel, each prompt carrying PLAN CONTEXT (spec-compliance + regressions dims only) + LINEAR CONTEXT (spec-compliance + pr-metadata + architecture + regressions dims only) + PEER-PR CONTEXT (per Phase 1 Peer-PR scout) + PRIOR-ROUND FINDINGS + Mechanical Pre-pass Findings + alignment-tag instruction (PR metadata flows via the pr-metadata reviewer's existing context channel — no separate `PR CONTEXT:` slot)
- [ ] Phase 2 spawn list includes `regressions` (8th always-fire dim) — declared in state.md `spawn_dims_declared[]` before parallel batch
- [ ] Phase 4.2 per-finding verifier spawned for EVERY §4.1 survivor (CRITICAL / HIGH / MEDIUM — no tier-scaling, no severity-scaling); refuted findings demoted to `## Filtered` before §4.3 F→P gate
- [ ] Phase 2 spec-compliance reviewer spawned when PLAN CONTEXT non-`none` AND (input was a PR ref OR risk-tier:high)
- [ ] Phase 2 `--simplify` flag prepended deep-simplify criteria to (architecture / conventions / guidelines / bugs / optimizations) dimensions when present
- [ ] Phase 3 relevance-filter applied; `convergence_count` field populated per finding
- [ ] Phase 4 judge validation complete; Step 0 intent reconciliation applied (plan-authorized divergences demoted to `[INTENT-CHECK]`)
- [ ] Phase 4.1 multi-signal threshold gate applied (convergence ≥2 OR Evidence-Block + confidence ≥60 OR criteria-pre-resolved marker OR confidence ≥80 fallback; high-tier relaxes signal 4 to ≥70; MEDIUM additionally requires signal #2 / Evidence-Block per Loop Invariant #6)
- [ ] Phase 4.3 test-gate evaluated (skipped when no eligible findings or user declines); user approval persisted to `approvals[]`
- [ ] TDD mode only: Phase 4.3 Step 2 AUQ rendered with `(Recommended)` suffix on "Author tests…" (gate itself fired exactly as in Standard mode); Phase 6 Step 3.5 post-set filter applied
- [ ] Issues classified by severity (CRITICAL/HIGH/MEDIUM/LOW per `${CLAUDE_PLUGIN_ROOT}/skills/review/severity-calibration-reference.md` §1) and Decision Type ([FIX-NOW] / [TESTABLE] / [PRODUCT-DECISION] / [INTENT-CHECK])
- [ ] All findings tagged `[NEW]` (in changed lines) or `[PRE-EXISTING]` (in unchanged code) per `agents/reviewer-agent.md` Output Format; build-failure findings additionally tagged per §2.7
- [ ] Phase 5 state artifact written to `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` via `atomic_state_write`
- [ ] Phase 5.3 L2 pitfall auto-emit fired when any finding had `convergence_count ≥3`
- [ ] Phase 6 open-decision gate fired for every `[PRODUCT-DECISION]` finding (always-WAIT)
- [ ] Phase 6 Step 0 per-finding gate completed AND every PRODUCT-DECISION finding's `step0_status` flipped from `pending` to `resolved` (or `wontfix`) BEFORE the Action gate's Post drill fires; §7.0 Pre-Post guard re-reads both `open_questions[]` and `## Findings` and aborts the post on any remaining `unresolved` / `pending` per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` §7.0
- [ ] Phase 6 Action gate fired (always-WAIT) — single consolidated decision; user pick persisted to `approvals[]` (category `action_gate`)
- [ ] Phase 6 Round-N escalation gate fired when round ≥3 + "Continue rounds" pick; terminal state mapped to state.md `## Termination reason`
- [ ] Phase 6 Action == Post drill ran (Steps 1.5-6) when user picked "Post"; `[POSTED-TO-PR]` markers persisted for idempotent re-run
- [ ] Phase 6 Failing-tests gate fired when `## Authored Tests` non-empty; firing order conditional on Action choice per the gate-chain rule
