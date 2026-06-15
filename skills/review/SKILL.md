---
name: geniro:review
description: "Use when a comprehensive code review of pending changes (a diff, branch, or PR) is needed. Reporter workflow: triage, a cheap mechanical pre-pass, then parallel single-dimension reviewers (bugs, security, architecture, tests, regressions, conventions, and more, plus any custom ones) whose findings are filtered and individually verified, then persisted. Emits a handoff file at .geniro/state/handoff/from-review-<branch>.md; downstream consumers (/geniro:implement, or you manually) apply the fixes — review never edits code itself. Resolves any needs-your-decision questions before offering the handoff. When the review finds testable bugs, it offers to author failing tests for them (gated by your approval). Optional --deep runs each check three times and verifies findings with a 3-agent majority vote (higher quality, higher cost)."
context: main
model: inherit
allowed-tools: [Read, Write, Glob, Grep, Bash, Agent, AskUserQuestion, WebSearch, EnterWorktree, ExitWorktree, Workflow]
argument-hint: "[files, diff range, branch, or PR ref (#N, URL)] [--plan <path>] [--deep]"
---

# Code Review Skill

Comprehensive code review using parallel multi-agent analysis.

**Detailed phase contracts:**
- `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` — Phase 1 input mode / scope / risk-tier / memory load.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` — Phase 4.2 per-finding verifier contract (every CRITICAL/HIGH/MEDIUM survivor of §4.1).
- `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-3-test-gate-reference.md` — Phase 4.3 test-confirmation gate.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` — Phase 6 action-gate handoff + Post drill.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-context.md` — PLAN CONTEXT load.

---

## Your Role — Orchestrate, Don't Review

You are a **coordinator**. You delegate review work to `reviewer-agent` instances via the Agent tool and validate their outputs in the judge pass. You do NOT review code yourself — you read files only to gather context and verify agent findings.

`/geniro:review` is a **Reporter** — it does not apply fixes. The Phase 6 handoff message omits 'I'll fix these now' language, because that phrasing implies a fixer responsibility this skill does not have. Findings persist to a handoff file; downstream consumers (`/geniro:implement`, manual user action) apply fixes. Running `/geniro:review` under a dynamic `Workflow(...)` / ultracode does NOT relax it either — a workflow wrapper parallelizes the reviewer fan-out, not the Reporter contract; full boundary at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.

---

## State Machine

State.md `phase:` enum transitions:

```
[entry] → triage → mechanical-prepass → llm-spawn → filter → stratify → persist → action-gate → done
│
├── escalated ── (round-N user pick)
└── aborted ── (round-limit / safety / tool-unavailable)
```

**Terminal states:** `done`, `aborted`, `escalated`. the SessionStart recovery treats all three as "review complete / cancelled". `done` includes a Phase 6 handoff line; `escalated` (round-limit hand-off) and `aborted` each carry a `## Termination reason`.

**Non-terminal states:** `triage`, `mechanical-prepass`, `llm-spawn`, `filter`, `stratify`, `persist`, `action-gate`. the recovery rolls these back to phase-entry and re-runs from there (idempotent — `approvals[]` ensures Phase 6 AUQ skips already-answered).

**Termination-case mapping** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §9. The `## Termination reason` body section is written on `aborted` / `escalated` terminals.

---

## Loop Invariants

The invariants apply unchanged:

1. **One result per tool call.** Phase 2 parallel-spawn reviewer-agents — each must return a structured result; dead spawn → `status: failed` entry in `## Tool log`.
2. **Args validated before execution.** `$ARGUMENTS` flag parsing (semantic, no CLI grammar); PR ref validation via `mcp__github__pull_request_read` or GraphQL fallback.
3. **Permission before side-effect.** Phase 6 "Post Draft PR" requires AUQ approval before posting to GitHub — the action gate always fires and waits first; never auto-post and never substitute a chat-text suggestion for it. The post is a single `gh api POST /repos/<owner>/<repo>/pulls/<number>/reviews` call per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.5 — `event` field omitted so the review is created in GitHub's PENDING state (private to the reviewer, no notifications fire). /geniro:review never publishes that review (never the `reviews/<id>/events` submit endpoint) — submitting is the user's own github.com action, and this holds across rounds. State.md writes via `atomic_state_write`.
4. **Bounded and structured tool results.** Reviewer-agent output ≤4000 chars per dim; truncation marker. Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.
5. **Escalation gates, not silent abort.** Round-N ≥3 → Phase 6 escalation gate.
6. **Final answer grounded in observations — at every kept severity.** The Phase 6 handoff message cites the state.md path so the user can audit the source; every kept finding body at CRITICAL / HIGH / MEDIUM severity carries an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` that quotes the cited file or caller chain literally, because a severity claim without a literal quote is unverifiable. The Phase 4.2 per-finding verifier (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §3) formalizes this for every §4.1 survivor — empirical reproduction of the cited code is the load-bearing check that turns a reviewer's confidence score into grounded evidence.
7. **Errors → structured observations.** Reviewer spawn failures → `## Errors` body section. `gh` fail-open NOT silent — log to `## Errors`.
8. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.
9. **Re-verify ambiguity gates at external-effect boundaries.** The Pre-gate (`review-handoff.md` §2.5), the open-decision gate (`review-handoff.md` §3 Step 0), the Phase 4.2 per-finding verifier, and the §3.5 finalize step establish gate invariants on `open_questions[].status`, PRODUCT-DECISION `step0_status:`, kept-finding `Validation:`, and `report_status: final` respectively; the Pre-Post guard (`review-handoff.md` §7.0) re-reads ALL FOUR before any `gh api POST /reviews` because mid-phase producer writes, parallel resolvers, or orchestrator drift can re-create unresolved ambiguity (or surface a `Validation: refuted` finding that bypassed the upstream filter, or leave the report at `report_status: draft`) between the upstream gate and the external write. Never trust an upstream gate's invariant at a public-surface boundary.
10. **Stamp `phase:` on entry, before the phase's work.** Write state.md `phase: <X>` via `atomic_state_write` when each phase BEGINS, ahead of that phase's steps — not at persist time. A checkpoint written only at the end records history, not current state: a crash mid-phase leaves no resumable marker, and a declaration the phase produces (e.g. `spawn_dims_declared` written in §2.2, before the spawns) lands ~100 events too late to power the gate that reads it if the whole phase's state is deferred to persist. A phase is stamped DONE only after its trailing steps complete — stamp `persist` only once the §5.3 learning emits have run, OR stamp the next phase at its own entry; never stamp a later phase while an earlier phase's trailing emits are still pending.

**Turn-completion check (canonical, un-numbered).** Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check: never stop on a statement of intent or an announced-but-unfired question — at every gate the render is followed immediately by its lean `AskUserQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard, and an answered question is continued with the next action, never a silent stop.

`## Tool log` schema: typical run produces 5-12 entries (1 per reviewer + 1 per Phase 5.3 emit-learning + 1 per PR-side-effect).

---

## Budgets — Quality-First

This skill has no hard kill caps. Same model as other skills.

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

## Subagent model tiering

Follow the canonical doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Plugin agents (`reviewer-agent`, `adversarial-tester-agent`) declare `model: inherit` in frontmatter — OMIT `model=` at every spawn site so the orchestrator's session tier propagates. Apply the registration-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (`geniro-claude-plugin:<agent>` → bare `<agent>` → `general-purpose` with agent body inlined). Cache the resolved rung for the rest of the session.

The one exception: custom reviewers whose `.geniro/instructions/review-extra/<slug>.md` frontmatter declares an explicit `model:` value. Pass that value verbatim at the spawn site — honor the user's per-reviewer declaration.

Every Agent prompt satisfies the six pre-inlined fields per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`.

| Spawn | Model arg | Why |
|---|---|---|
| `reviewer-agent` (all built-in dims) | OMIT | Frontmatter `model: inherit` — orchestrator tier propagates |
| `reviewer-agent` (custom dim) | OMIT (default) OR explicit value when user-declared | User declaration wins per model-tiering doctrine |
| `adversarial-tester-agent` (Phase 4.3 only) | OMIT | Frontmatter `model: inherit` |
| Per-finding verifier (reviewer-agent in verify-finding mode; CRITICAL / HIGH / MEDIUM) | OMIT | Frontmatter `model: inherit` |

---

## Phase 1 — Triage & Context Collect

State.md `phase: triage`. **Full contract:** `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md`.

Summary of what Phase 1 does:

1. **Step 0 — Workspace setup** — passive context detection (IN_WORKTREE, REVIEW_HANDOFF, DEBUG_HANDOFF, IMPLEMENT_TASK_STATE, PROTECTED_BRANCH, TARGET_PR_NUMBER, IN_TARGET_WORKTREE) followed by a decision tree with auto-continue branches for in-worktree continuing-work signals. Workspace AUQ (single question — workspace decision) fires only when ambiguous. Inline modifier overrides (`worktree` / `no-worktree` / `current-branch` / `new-branch`) win deterministically. On a compaction-resume, persisted `review_workspace_setup` / `deep_mode_choice` approvals are re-applied without re-asking; on a fresh Round 2+ re-run only the workspace location is re-applied (anti-relocation) while depth and re-review scope are re-asked. The recorded workspace location is honored exactly (re-ask only if it no longer applies), so an already-approved workspace is never silently relocated. /geniro:review never mutates workflow tracker status — that is `/geniro:plan` and `/geniro:implement` territory; /geniro:review reads tracker context only (see item 5). Fires BEFORE all subsequent items so they operate on the correct working tree. Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §0.
2. **Input parsing** — resolve the review-target shape from `$ARGUMENTS` (empty / branch name / file paths / diff range / PR ref). A PR ref additionally drives the thread-state + existing-review fetch in item 4. /geniro:review always produces a review of the target — it does not process reviewer comments left on your own PR.
3. **Scope resolution** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. Resolve the review target only from explicit PR-ref forms; running `gh pr list` to invent a target reviews a PR the user never asked about. When the review scopes to fewer files than the PR shows (commonly a stacked PR, base ≠ default branch), the excluded files are surfaced as a Scope-exclusion note (which ancestor PR owns them + its findings) so "reviewed upstream" is never mistaken for "missed" — full contract `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §2.1.
4. **PR-ref parsing** — `gh pr diff` + `gh pr view --json baseRefName,headRefName,body,title,headRefOid,url,isDraft,author,labels`. From the thread-state fetch (`reviewThreads[]` per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §1), persist every `isResolved == true` thread's `path:line` to state.md frontmatter `resolved-threads-snapshot:` so the Phase 6 Post drill's §7.1 already-on-PR dedup can exclude findings overlapping existing PR comments. Leave `resolved-threads-snapshot: null` when no PR ref or the fetch fails (§7.1 treats absence as "no dedup"). Also fetch the existing PR review surface per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §1.1 — both the formal-review summaries (CHANGES_REQUESTED / COMMENTED, human + bot) and inline review-bot comment bodies (CodeRabbit and other `[bot]` reviewers) — persist to `pr-formal-reviews-snapshot:` + `pr-bot-comments-snapshot:`, and feed both to reviewers as prior-context (§2.3).
5. **Workflow integrations** — workflow files (`.geniro/workflow/*.md`) live in the primary worktree per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (Mode A); glob both `./.geniro/workflow/*.md` (cwd-local — uncommitted local edits win) and `<PRIMARY_ROOT>/.geniro/workflow/*.md` (primary fallback). Read them, apply tracker-ID regex against `$ARGUMENTS` + `pr.title` + `pr.body`, AND when a spec.md is resolvable (via `--plan <path>`, `geniro-plan:` PR-body line, walk-up `.geniro/planning/*/spec.md`, or canonical project paths) parse its frontmatter `workflow_refs[]` per `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md`. Accept both `geniro_schema_version: m5-v1` (treat field as absent) and `m5-v2` (read entries). Merge sources by `(kind, issue_id)` — `$ARGUMENTS` reference wins on conflict (user just typed it, fresher signal); PR body next; spec.md frontmatter as fallback. On Linear match with MCP available: fetch issue (+ parent epic + sibling sub-tasks). Build `LINEAR CONTEXT:` block. Persist `linear-task-ref:` + `linear-parent-ref:` to state.md frontmatter, derived from the deduplicated merged list. Read-only — /geniro:review never mutates tracker state via MCP. Fail-open if MCP unavailable.
6. **Peer-PR scout** (PR-ref only) — sibling PRs scored by file overlap + Linear-relatedness bonus (parent-epic / sibling-sub-task matches), capped + ranked per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md`; inlined into reviewer prompts (architecture + design + bugs + conventions + optimizations + spec-compliance + regressions).
7. **Load custom instructions** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` (MODE: initial-load; scope = `review` + `global` + `code-style` — pipeline tier, 3 files).
8. **Round-N counter** — increments; fires the round-≥3 escalation AUQ first, then (on Continue) on a round ≥2 fresh re-run the re-review gate (scope: whole PR vs only changes since last review, + depth) — always asked, never auto-decided. Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §7.
9. **PLAN CONTEXT load (schema-aware).** Detection per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-context.md` Structured-section parser when `geniro_kind: design-doc` frontmatter present; prose fallback otherwise.
10. **Risk-tier stratification** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` 9 hard-escalation signals. Sets `risk-tier: standard | high`. Adjusts 4 downstream knobs (severity threshold / validator budget / spec-compliance default / mechanical secret-scan strict mode).
11. **Memory layer load:** `load-custom-instructions` MODE:refresh + `load-semantic` MODE:refresh + `query-learnings` (top-K, K=5 default) + `resolve-conflicts`.
12. **Mode AUQ** — review depth (Standard / Deep). Fires on a user-invoked run unless `--deep` is in `$ARGUMENTS`, the §7 re-review gate already asked depth this run, or a compaction-resume inherits it — a fresh re-run always re-asks depth (never inherits a prior completed run's pick). Persist the pick → frontmatter `deep-mode: <true|false>` + `approvals[]` category `deep_mode_choice`. Full chooser shape + deep contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §11 + `${CLAUDE_PLUGIN_ROOT}/skills/review/deep-mode-reference.md`.
13. **Size triage** — classify files Trivial / Substantive when diff >8 files or >400 LOC. Controls Phase 2 Standard vs Batched mode.

Exit criterion: state.md frontmatter carries the fields each prior step wrote — `round`, `risk-tier`, `pr-ref`, `linear-task-ref`, `linear-parent-ref`, `plan-context-ref`, plus `deep-mode` (from the Mode AUQ pick or `--deep` parse) when that step ran; `approvals[]` carries any AUQ answers; `## Tool log` includes initial load echoes.

Phase 1 PR metadata and tracker context loads are orchestrator-inline (`gh pr diff` / `gh pr view` / `mcp__linear__*` reads). For codebase-research side queries inside this phase (e.g., locating a pattern across the wider repo when scoring peer-PR overlap), spawn `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

---

## Phase 1.5 — Mechanical Pre-pass

State.md `phase: mechanical-prepass`.

Three deterministic checks BEFORE LLM reviewer spawns. Cheap-deterministic first; LLM-spawn second with pre-pass findings as prior-context. Sequential, not parallel — LLM agents seeing prior mechanical findings produce better-targeted output.

**Each check is must-attempt and lands one of two recorded outcomes** — findings written (Check 1/2 to the finding list, Check 3 tagged CRITICAL), OR a fail-open `## Errors mechanical-prepass-<id>: <reason>` entry. There is no silent third outcome — skipping a check entirely (e.g. running neither lint nor `tsc` on a TS-dominated diff) is the failure this contract closes; a check that does not apply (no lint config, no schema files) still records its outcome as a `## Errors` skip entry so the §4.0 gate can confirm it was reached. Declare the attempted set in state.md frontmatter (§1.5.7) before exiting this phase, mirroring §2.2's spawn-declaration pattern.

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

Each check records exactly one outcome — findings, or a `## Errors` entry. Continue to Phase 2 either way (fail-open, consistent with `gh` fail-open):

- **Check failed** (process exit nonzero with no output OR command not found): write `## Errors mechanical-prepass-<check_id>: command_unavailable_or_failed`.
- **Check not applicable** (no lint config detected for `lint`; no TS / schema / proto files in the diff for `schema`): write `## Errors mechanical-prepass-<check_id>: not_applicable` so the check still has a recorded outcome — a skip with no record is indistinguishable from never reaching the check, which is what the §4.0 declaration gate detects.

Secret scan is a pure-regex pass — it cannot fail or be not-applicable, so its outcome is always its finding set (possibly empty).

### 1.5.7 Pre-pass declaration (state.md write before Phase 2)

Before leaving Phase 1.5, declare the attempted check set in state.md frontmatter via `atomic_state_write`, mirroring §2.2's spawn-declaration pattern:

```yaml
# frontmatter update
mechanical_prepass_attempted: [lint, schema, secret]
```

The list names every check that ran to an outcome (findings or a `## Errors` entry). This is the observability surface the Phase 4 §4.0 verification gate asserts against — a missing declaration, or a listed check with no corresponding outcome (no findings and no `## Errors mechanical-prepass-<id>` entry), is a pre-pass contract miss the gate surfaces.

---

## Phase 2 — LLM Reviewer Spawns

State.md `phase: llm-spawn`.

### 2.1 Dimension grid (12 built-in dimensions + N custom)

| # | Dimension | Spawn rule (always-fire or conditional) |
|---|---|---|
| 1 | bugs | Always fires — no exception |
| 2 | security | Always fires — no exception |
| 3 | architecture | Always fires — no exception |
| 4 | tests | Always fires — no exception |
| 5 | optimizations | Always fires — no exception |
| 6 | guidelines | Always fires — no exception |
| 7 | conventions | Always fires — no exception. Owns repo-modal-pattern findings exclusively (explicit authored rules belong to rules-compliance, #12) |
| 8 | regressions | Always fires — no exception. Catches unintended deletes + behavior changes outside stated intent (PR body / spec.md / commit msg). 4 signals: deleted-symbol caller-blast, intent-vs-behavior over-reach, test-coverage delta, parallel-path symmetry (mirror-gap). Criteria: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/regressions-criteria.md` |
| 9 | design | Fires when UI globs match changed files (see §2.5 UI-file detection rule) |
| 10 | pr-metadata | Fires when `pr-ref:` is non-none |
| 11 | spec-compliance | Fires when PLAN CONTEXT is non-none AND (`pr-ref:` non-none OR risk-tier:high) |
| 12 | rules-compliance | Fires when the repo contains any authored rule file (see §2.8 rules-file detection rule). Checks the diff against the project's own rule files (Cursor / Claude / AGENTS / etc.), citing the exact rule. Criteria: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/rules-compliance-criteria.md` |
| +N | custom:* | Fires per user-authored `.geniro/instructions/review-extra/<slug>.md`, discovered in Phase 1.5 |

**Spawn-batch size.** Phase 2 spawns a reviewer-agent for every row whose trigger fires — trimming the set silently drops a coverage dimension the user expects:

- 8 always-rows (bugs, security, architecture, tests, optimizations, guidelines, conventions, regressions) fire on every run.
- 4 conditional rows (design, pr-metadata, spec-compliance, rules-compliance) fire when their trigger column is satisfied.
- N custom rows fire per the spawn-specs already discovered in Phase 1.5 §1.5.4 (zero discovery work at Phase 2 entry — read the count from state.md frontmatter `custom_reviewers`).

Total batch size = always-fire + triggered conditional + custom rows. Trimming this set silently is the documented anti-pattern — see §Anti-rationalization. Post-spawn verification in Phase 4 §4.0 catches drift.

**Refresh L4 instructions** at Phase 2 entry — apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `MODE: refresh`. Compaction since the previous load may have silently dropped the rules.

**Read custom-reviewer specs** from state.md frontmatter `custom_reviewers[]` — populated in Phase 1.5 §1.5.4 via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` discovery. Append one `Agent(subagent_type="reviewer-agent",...)` per spec to the same parallel batch as the built-ins.

### 2.2 Pre-spawn declaration (state.md write before parallel batch)

Before firing the parallel `Agent(...)` batch, the orchestrator computes the declared spawn list and writes it to state.md via `atomic_state_write`:

The example below is one illustrative run — the actual declared set is whatever the §2.1 grid resolves for THIS run (the conditional rows fire per their triggers), never a fixed list copied verbatim:

```yaml
# frontmatter update
spawn_dims_declared: [bugs, security, architecture, tests, optimizations, guidelines, conventions, regressions, pr-metadata, spec-compliance, rules-compliance, custom:manifest-incident-patterns]
spawn_dims_count: 12
```

Plus a `## Tool log` entry:

```
[Phase 2 spawn declaration] dim_list=[bugs, security, architecture, tests, optimizations, guidelines, conventions, regressions, pr-metadata, spec-compliance, rules-compliance, custom:manifest-incident-patterns]; count=12; triggers={pr-ref: <ref-or-none>, plan-context: <path-or-none>, linear-task: <id-or-none>, rule-files: <yes-or-none>, custom-reviewers-discovered: <N>}
```

This is observability for the Phase 4 §4.0 verification gate — declared-vs-actual is one grep away.

### 2.3 Spawn invocation

**Step 2.3.1 — Emit the spawn echo (welded to the batch fire).** Read the `spawn_dims_declared[]` list from state.md (written in §2.2), render dim slugs in plain English (`guidelines` -> "code quality", `pr-metadata` -> "PR metadata", `spec-compliance` -> "specification compliance", `rules-compliance` -> "rules compliance"; the slugs `bugs / security / architecture / tests / optimizations / conventions / regressions` are already plain-English — surface verbatim; custom reviewers render as `custom: <slug>`). Emit this one-line status in the SAME assistant response that fires the parallel `Agent(...)` batch (Step 2.3.2) — not a separate turn — so the user sees what is being spawned exactly when it spawns:

> Spawning <N> reviewers: <comma-separated plain-English list>.

A dropped echo produces a silent multi-minute window where the user cannot tell the batch fired; the Definition-of-Done line below makes the drop detectable.

**Step 2.3.2 — Fire the batch.**

**Deep-mode branch (`deep-mode: true`).** Do NOT fire the single parallel batch below. Instead invoke the deep recall Workflow — 3× passes per declared dimension with in-script union + dedup — per `${CLAUDE_PLUGIN_ROOT}/skills/review/deep-mode-reference.md` §2, then proceed to Phase 3 over the deduped per-dim sets. The `spawn_dims_declared[]` declaration (§2.2) and the §4.0 verification gate still apply to the declared dimension SET (3× is a multiplier on each declared dim, not a new dim). Fail-safe to the single-pass batch below if the workflow errors (deep-mode-reference §6). Everything below describes the standard single-pass path.

Then fire the parallel batch — single message with N parallel `Agent` tool uses, one per dimension. Each spawn:

- `subagent_type: reviewer-agent` (plugin) — apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration-degradation ladder.
- OMIT `model=` argument — reviewer-agent declares `model: inherit`. Custom reviewers that declare an explicit tier in their `.geniro/instructions/review-extra/<slug>.md` frontmatter pass that tier verbatim; otherwise OMIT.
- Pre-inlined context per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`:
  - Diff of changed files (full content for the batch's files in Batched Mode; all files in Standard Mode).
  - Project conventions from L4 (refreshed).
  - Mechanical pre-pass findings (Phase 1.5) as prior-context under `## Mechanical Pre-pass Findings`.
  - PLAN CONTEXT — spec-compliance + regressions dims ONLY (other dims see `PLAN CONTEXT: <plan tag fields only>` per the schema-aware reference).
  - LINEAR CONTEXT — spec-compliance + pr-metadata + architecture + regressions dims ONLY. Omitted for other dims.
  - CUSTOM CONTEXT — a custom reviewer (`custom:<slug>`) that declares `requires-context:` ONLY. The orchestrator pre-fetches the declared external data (which the subagent can't reach over MCP) and injects it into that one reviewer's spawn, fail-open if unavailable — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Hydrating requires-context. Omitted for all built-in dims and for custom reviewers without the field.
  - PR metadata (pr.body / pr.title / commit messages) — flows via the pr-metadata reviewer's existing context channel; spec-compliance and regressions dims read it through the same channel when fired on a PR ref. No separate `PR CONTEXT:` slot is composed.
  - PRIOR-ROUND FINDINGS (Round-N counter sub-step prior-round-summary, or `none — first review`).
  - PRIOR-ROUND PR BODY — pr-metadata dim ONLY — the `prior-pr-body` captured at re-review detection (per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §1); renders `none — first review` on round 1 or when the prior-run handoff has no `pr-body:`. The pr-metadata reviewer's cross-round drift check (check #11) reads this slot.
  - PEER-PR CONTEXT — architecture + design + bugs + conventions + optimizations + spec-compliance + regressions dims ONLY.
  - `## Existing PR review comments` (from `pr-bot-comments-snapshot:`, per §1.1) — bugs + architecture + regressions + security dims ONLY; omitted when null.
  - `## Existing PR formal reviews` (from `pr-formal-reviews-snapshot:`, per §1.1) — same dims (bugs + architecture + regressions + security); each entry `- <author> (<state>) — <excerpt>`; omitted when null.
  - Dimension-specific criteria file body inlined.
  - Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.

After the parallel batch returns, narrate completion before transitioning to §3:

> All <N> reviewers returned. Aggregating findings.

Surface any `status: failed` entries by their plain-English dim name (e.g., "PR metadata reviewer failed — see `## Errors`"), not by raw slug.

**Criteria files** (read once at Phase 2 entry):
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/bugs-criteria.md` · `security-criteria.md` · `architecture-criteria.md` · `tests-criteria.md` · `optimizations-criteria.md` · `guidelines-criteria.md` · `conventions-criteria.md` · `regressions-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/design-criteria.md` (conditional per §2.5)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/pr-metadata-criteria.md` (conditional)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` (conditional per §2.6)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/rules-compliance-criteria.md` (conditional per §2.8)
- Custom reviewer criteria from spawn-specs returned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` (≤10 per project)

### 2.5 UI-file detection rule (design dim trigger)

A file is a UI file per the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §UI-file detection rule. Design dimension skipped when no changed file matches.

### 2.6 Spec-compliance detection rule

Fires when ALL hold: (a) PLAN CONTEXT is non-`none`; AND (b) either input was a PR ref OR risk-tier:high. Findings carry `File: SPEC-COMPLIANCE` sentinel — Phase 6 Post drill routes them to top-level review `body` under `## Spec Compliance` (no `path:lines` anchor, so they do NOT inline-comment).

### 2.7 Build verification (parallel with reviewers)

Run the project's validation suite in parallel with reviewer agents:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Build Check" "<validation_cmd>"
```

Feed pass/fail into the Phase 3 §3.3 KEEP/FILTER judgment. Failing build is automatically a CRITICAL finding — tag `[NEW]` if the base branch build passes, `[PRE-EXISTING]` if already broken.

### 2.8 Rules-file detection rule (rules-compliance dim trigger)

Fires when the repo contains at least one authored rule file — any of `CLAUDE.md` (root or nested), `.claude/rules/**/*.md`, `.cursor/rules/**/*.mdc`, `.cursorrules`, `.windsurfrules`, `.windsurf/rules/**`, `.github/copilot-instructions.md`, `AGENTS.md`, `.agents.md`. Detect via Glob at Phase 2 entry; skip the dimension when none exist — a repo with no authored rules has nothing for this dimension to check, so it never bloats the always-fire set. The reviewer discovers the files, parses their path-scopes (`.mdc` `globs:`, `.claude/rules` `paths:`), and checks the diff against each in-scope rule per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/rules-compliance-criteria.md`.

---

## Phase 3 — Filter & Aggregate

State.md `phase: filter`.

### 3.1 Orchestrator-side dedup + convergence

The orchestrator reads all per-dimension findings (Phase 2 reviewer-agent outputs + Phase 1.5 mechanical findings) and performs dedup inline — no subagent spawn:

- **Dedup key:** `path:line + finding-title` (case-insensitive title match).
- **Convergence_count:** for each dedup'd finding, count how many reviewers + mechanical checks reported the same key. Persisted as a field on the finding (consumed by Phase 5.3 auto-emit threshold).
- **Drop hallucinations:** findings without a real file:line correspondence (orchestrator verifies file exists and line is within bounds via Read; if not, drop with a `## Caveats` line citing the dropped finding). **Exception — sentinel-`File` findings** (`File: SPEC-COMPLIANCE` / `File: PR-METADATA`) are path-less by design: they cite a plan/PR fragment in `Evidence:`, not a code `file:line`. Do NOT drop them here — they are verified in Phase 4.2 against the diff instead (§4.2 path-less branch).
- **Convention context:** orchestrator reads convention files when present — CONTRIBUTING.md, ADRs at `docs/adr/`, architecture docs. These inform KEEP/FILTER decisions.

### 3.2 Mechanical+LLM dedup

Mechanical findings (Phase 1.5) and LLM findings may overlap (e.g., lint says "unused import on line 42", bugs reviewer says "dead code on line 42"). Orchestrator-inline dedup identifies overlap by dedup key, preserves the mechanical finding (deterministic) + drops the LLM's redundant entry. Convergence_count for that finding gains +1 for the mechanical contribution.

### 3.3 KEEP/FILTER judgment

After dedup, the orchestrator synthesizes per finding: weighs convention-alignment, over-engineering, and pattern-frequency evidence against severity and judges KEEP / FILTER. CRITICAL findings with `safety_override=true` are always KEEP regardless of convention evidence. Pass only KEEP findings to Phase 4. FILTERED appear in the report's `## Filtered` section with reason annotation.

**Intent reconciliation** runs here as part of the per-finding judgment: a finding a reviewer tagged `[ALIGNS-WITH-PLAN]` (or `[DIVERGES-FROM-PLAN]` where the plan authorized the divergence) is demoted to decision-type `[INTENT-CHECK]` rather than kept as a bug. `[PRE-EXISTING]` convention/build findings are demoted the same way. Cite the plan frontmatter or section that authorizes the divergence on the demoted finding so the user can re-elevate.

No external agent to fail — dedup and judgment run in orchestrator's main context.

---

## Phase 4 — Stratification & Test Gate

State.md `phase: stratify`.

### 4.0 Post-spawn verification gate (declared vs actual)

Before stratification fires, run two declared-vs-actual checks.

**4.0a Mechanical pre-pass declaration check.** Assert state.md frontmatter `mechanical_prepass_attempted` (§1.5.7) exists and each listed check (`lint`, `schema`, `secret`) has a recorded outcome — findings on the list, or a `## Errors mechanical-prepass-<id>` entry. A missing `mechanical_prepass_attempted` declaration means the pre-pass was skipped wholesale (a TS-dominated diff that ran no lint and no `tsc` is the documented live miss); a listed check with no outcome means it was declared but never reached. Either is a contract miss: append `## Errors mechanical-prepass-incomplete: declared=<...> missing-outcome=<...>` and surface it in the Phase 6 report `## Caveats`; this is advisory (the pre-pass is fail-open by design and LLM reviewers still ran), so do NOT block — record the gap so the user knows the cheap-deterministic layer was thin this run.

**4.0b Spawn-batch completeness check.** Verify the Phase 2 parallel batch actually delivered every dimension declared in §2.2:

```
declared = state.md frontmatter spawn_dims_declared
actual   = set of dimensions whose reviewer-agent emitted a structured result in Phase 3

missing = declared − actual
```

A `spawn_dims_declared` list that does not exist in frontmatter at this point is itself a contract miss, not a pass: §2.2 writes it BEFORE the parallel batch precisely so this gate has a baseline — if it appears only at persist time (written ~after the spawns), the gate it powers ran inert against a missing baseline. Treat an absent or first-seen-at-persist `spawn_dims_declared` as drift: append `## Errors phase-2-spawn-declaration-missing` and reconstruct `declared` from the §2.1 grid for THIS run before computing `missing`.

If `missing` is non-empty:

1. Append a `## Errors` body entry: `phase-2-spawn-incomplete: declared=<...> actual=<...> missing=<...>`.
2. Render the round summary to chat first — declared vs returned reviewers, with the missing set in plain-English dimension names — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering, then fire a lean `AskUserQuestion` with header `"Review incomplete"`:
   - A) `"Re-run the missing reviewers now"` — issue `Agent(...)` per missing dim; once results land, recompute `actual` and re-verify. (Recommended)
   - B) `"Skip the missing reviewers and continue"` — append to body `## Accepted Gaps`; continue to §4.1.
   - C) `"Abort review"` — terminal `phase: aborted`; `## Termination reason: spawn-batch-incomplete (<missing>)`.

Always-WAIT — an empty answer signals an upstream tool bug; fall back to plain text and re-ask rather than auto-defaulting to the skip-and-continue option, because silently skipping missing reviewers hides a coverage gap the user never consented to.

When `missing` is empty, proceed directly to §4.1.

### 4.1 Multi-signal threshold filter

`severity ≥ MEDIUM` is necessary but NOT sufficient. A finding admitted to Phase 4 must clear one of FOUR independent signals — any one passes. Convergence + evidence-grounding are documented as more reliable than LLM self-confidence (citations: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §4).

KEEP rule (admit to Phase 5 stratify into `## Findings`) — a finding is kept when EITHER admission path holds. **Path A — severity-gated** (also admits to the Phase 4.2 verifier): `severity >= MEDIUM` AND ONE OF:
1. `convergence_count >= 2` — finding raised by 2+ independent reviewer dims (k-review pattern; cross-dim agreement beats any single dim's self-rating). `convergence_count` is set during §3.1 dedup.
2. `Evidence-Block present AND properly formatted` AND `confidence >= 60` — cites a real file:line per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. "Properly formatted" = Evidence-Block fence OR file:line pattern + ≥2 quoted lines — OR, for a sentinel-`File` finding (`File: SPEC-COMPLIANCE` / `File: PR-METADATA`, path-less by design), a verbatim quoted plan/PR fragment in `Evidence:` (a fenced quote or ≥2 quoted lines) standing in for the code citation these dimensions structurally lack (mechanical check at §4.1 entry on each finding's `Evidence:` field; false on missing; orchestrator does NOT re-read the cited file — Phase 4.2 verifier handles that for every §4.1 survivor).
3. Pre-resolved override marker — tagged by a criteria file as pre-resolved priority (e.g., `regressions-criteria.md` signal-table-flagged HIGH).
4. `confidence >= 80` — advisory fallback for findings without convergence or evidence. High tier (`risk-tier: high`) relaxes this to `confidence >= 70` (matches the legacy threshold); other signals unchanged.

Additional admission constraint for MEDIUM: a MEDIUM finding requires signal #2 (Evidence-Block present + properly formatted). Signals #1, #3, #4 alone admit CRITICAL and HIGH but NOT MEDIUM — Loop Invariant #6 mandates Evidence at CRITICAL / HIGH / MEDIUM, so a MEDIUM without Evidence drops to `## Deferred — sub-threshold` regardless of convergence or confidence score. A sentinel-`File` MEDIUM finding (spec-compliance / pr-metadata) satisfies signal #2 via the quoted plan/PR-fragment form above, so it reaches the Phase 4.2 path-less verifier rather than being deferred — its grounding is the verbatim fragment, not a code line.

**Path B — decision-type orthogonal** (`Decision Type == PRODUCT-DECISION`, any severity): a PRODUCT-DECISION names a call the reviewer cannot close — it is the user's to make — so severity (impact-if-wrong) does not gate whether the user sees it. Keep it regardless of severity, mirroring `/geniro:refactor`'s always-WAIT PRODUCT-DECISION escalation. This is admission by decision-type, NOT severity inflation: severity stays as scored (a LOW PRODUCT-DECISION stays LOW — inflating it is the anti-pattern the §4.1 gate and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §2 forbid). A finding admitted by Path B alone (LOW severity) skips the Phase 4.2 verifier (§4.2 runs on Path-A survivors only — a trade-off is not a defect-to-confirm) and lands in `## Findings` with its `File: path:lines` anchor — so the §3 open-decision gate fires and, on a Post, it inline-comments to its line — carrying `step0_status: pending` but no `Validation`/verification fields (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` § Verification fields — presence rules).

DEFER rule (write to `## Deferred — sub-threshold` for user awareness; do NOT post to PR; do NOT populate `open_questions[]`):
- `severity < MEDIUM` AND `Decision Type != PRODUCT-DECISION` — deferred per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5. (A LOW `PRODUCT-DECISION` is kept via Path B above, never deferred — its visibility is the user's call to make, not severity's to suppress.)
- `severity >= MEDIUM` that fails ALL FOUR signals above.

The admission gate is unchanged by the carried-over tier. A repeat finding that re-surfaces unchanged on a re-run is still ADMITTED by this gate — the `repeat-of-prior-round` marker (set at re-review detection per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §7) is a presentation router consumed by Phase 5 stratify, not an admission filter. Demoting it to a visible collapsed digest is a Phase 5 presentation step, never a higher bar here. Raising the admission bar for repeats would make a user's prior MEDIUM vanish — the documented anti-pattern (users notice when their MEDIUMs vanish).

### 4.2 Per-finding empirical-reproduction verification

Every Path-A survivor of Phase 4.1 — CRITICAL, HIGH, AND MEDIUM — gets ONE fresh `reviewer-agent` spawn in verify-finding mode (parallel batch, single assistant turn). No tier-scaling, no severity-scaling within Path A — every severity-gated survivor is verified regardless of `risk-tier`. When `deep-mode: true`, each survivor gets 3 independent verifiers aggregated by 2/3 majority (parse-fail = abstain; quorum < 2 → single-pass fail-safe) per `${CLAUDE_PLUGIN_ROOT}/skills/review/deep-mode-reference.md` §3 — the per-verifier contract is unchanged, only the vote count differs. A finding admitted by §4.1 Path B alone (a LOW `PRODUCT-DECISION`) carries no Evidence-Block to re-read and routes to the §3 open-decision gate rather than defect-confirmation — so it skips this step. The §4.1 multi-signal gate already constrains the survivor set to findings with Evidence-Block-grade citations (signal #2 mandatory for MEDIUM per §4.1; Loop Invariant #6 mandates Evidence at every kept severity), so every code-anchored survivor has a concrete file:line for the verifier to re-read. The two sentinel-`File` dimensions (`SPEC-COMPLIANCE` / `PR-METADATA`) are path-less by design and verify against the diff instead of a code slice — see the path-less branch below.

For each kept finding, the orchestrator reads the cited `file:line` ± 30 lines, greps the key symbol's 1-hop callers (cap 50 lines) + test dirs (cap 20 lines), then composes a verify-finding spawn carrying ONLY the finding body + cited slice + grep outputs (NOT the full reviewer bundle — isolated context prevents anchoring). All verifier spawns fire in ONE assistant response using the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (OMIT `model=` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`).

**Path-less sentinel findings (`File: SPEC-COMPLIANCE` / `File: PR-METADATA`).** These carry no code `path:line`, so there is no code slice to read. The orchestrator composes the verify-finding spawn with the finding body (its `Evidence:` already quotes the spec/PR fragment verbatim), the PR's changed-file list (`git diff --name-only <base>...HEAD`), and — when the Evidence embeds a real code `file:line` (a spec-defect finding cites the code that contradicts the spec premise) — that slice read ± 30 lines. The verifier confirms/refutes against the diff and the cited fragment rather than a code slice: "is the scoped item actually absent from the changed files?" (code-omission) / "does the cited code actually contradict the spec premise?" (spec-defect). The §3.5 confirm/verify resolution and §3.6 actionability bar apply unchanged. Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2.

Each verifier emits: `validation: confirmed | refuted | clarified`, `recommended_action: fix-now | testable | product-decision | intent-check | drop`, `confidence: 1-5`, `evidence: "<file:line quote>"`.

Aggregation:
- `refuted` findings move to `## Filtered`. Do NOT propagate to §4.3 F→P gate, Phase 5 stratify, or T2 handoff.
- `clarified` findings keep severity but update `decision-type` to the verifier's `recommended_action`; verifier confidence and evidence append to the finding body.
- `confirmed` findings retain decision-type; verifier confidence and evidence append.
- A verifier that fails to spawn or returns nothing parseable (after the registration ladder + one retry) → the finding takes `Validation: unverified` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4.5 — kept in the report (fail-open), excluded from the PR post set, surfaced under `## Caveats`.

A `refuted` verdict on a CRITICAL is high-impact (the finding drops out of the handoff entirely). The verifier contract requires a literal quote from the cited file showing the defect is NOT present (paraphrased "looks fine" is insufficient). See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §6 for the anti-sycophancy guard.

Full prompt template, isolated-context contract, anti-sycophancy guard, and worked examples: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md`.

### 4.3 Failing-to-passing test-confirmation gate

**Full contract:** `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-3-test-gate-reference.md`.

Summary:
- Filter findings by decision-type per the runtime-behavior classification rule.
- **Mandatory user-approval gate before any `adversarial-tester-agent` spawn.** Do not spawn without approval — the gate is the load-bearing safety property, since an unapproved spawn authors tests the user never asked for. Persist to `approvals[]` with category `test_gate_choice`.
- The gate fires whenever eligible findings exist — never bypassed, never deferred to end-of-run. When the eligible set is empty, Phase 4.3 is skipped entirely with no AUQ.
- Spawn ONE adversarial-tester-agent with eligible findings as hypothesis seeds. Orchestrator's independent re-run IS the gate; never trust the agent's red/green claim alone.
- Demote-don't-delete: green tests demote findings to `## Filtered` with `[CHALLENGED-BY-TEST]` tag; original severity preserved for re-elevation.
- Fail-open: agent failures surface "test-gate fail-open" under `## Caveats` + write `## Errors` entry.

---

## Phase 5 — Persist & Emit

State.md `phase: persist`.

### 5.0 Carried-over stratification (re-run repeat findings)

On a round ≥2 re-run where the user picked the collapse option at the re-review gate (the "Repeat findings" question, `approvals[]` category `rereview_repeat_handling`), demote each admitted finding carrying the `repeat-of-prior-round` marker into a collapsed `## Carried-over from round <N>` digest — a sibling of `## Deferred — sub-threshold`. A repeat that strengthened this round — fresh cross-reviewer convergence, a newly-reachable code path, or a per-finding verifier `confirmed` verdict absent last round — PROMOTES back to active `## Findings`. Genuinely-new findings keep the standard §4.1 admission gate and render in active `## Findings`. The marker drives which section a finding renders in, never whether it renders: a demoted finding is never dropped, stays in the handoff body, and keeps every gate it had (a needs-your-decision finding still fires the open-decision gate; an `open_questions[]`-linked finding keeps its entry; it stays in the Post drill's eligible set). Skipped entirely when the user kept every repeat in the main list, or on a first review / fresh-PR round (no prior round to carry over from). Full mechanics — what demotes, the promote signals, gate preservation, and the section render — at `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §7.1.

### 5.1 Handoff file write

Path: `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md`. `<PRIMARY_ROOT>` resolved per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A.

**Write via `atomic_state_write`** — never direct Edit/Write on the canonical state path (the `enforce-state-helper` hook flags direct writes in warn-mode initially; it flips to hard-block in a future release).

**`open_questions[]` rich-field authoring contract.** When composing `open_questions[]` entries from kept findings, fill the optional `context` / `evidence` / `options` / `recommendation` fields per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2. The reviewer-agent output already carries Evidence / Why-matters / Suggested-fix / Options per `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format — copy them into the open_question entry, do NOT discard them at composition time. Bare `question:` entries trigger the `review-handoff.md` §2.5 Tier 3 fallback (terse AUQ), which the user experiences as the failure mode the rich-field schema was added to prevent. For non-finding open_questions (e.g., process / scope / verification questions surfaced by spec-compliance or pr-metadata reviewers), author `context` + `options` + `recommendation` inline — the reviewer's `## Why this matters` and `## Suggested fix` synthesis fields are still the source material; the consumer has no other way to render the question richly.

**Verify what's verifiable; record only genuine decisions.** Before writing a finding or an `open_questions[]` entry that asks the author to confirm something, check it yourself against the diff, the code, and git history — a finding states a verified fact, it does not ask the reader to verify what /geniro:review can determine (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §4). Record an `open_questions[]` entry ONLY for a genuine judgment call whose answer changes what /geniro:review posts (e.g. "are these seeder additions in-scope for this PR?" — the answer determines whether that finding gets posted; the `review-handoff.md` §2.5 Pre-gate surfaces these). Do NOT record a "how should X be fixed?" question — a finding carries its own recommended action, and /geniro:implement decides fix specifics when it fixes.

**`step0_status:` producer-side initialization contract.** When writing each PRODUCT-DECISION finding into `## Findings`, also write `step0_status: pending` as the last sub-field of its body block (schema at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §"Per-finding body schema"). This is the runtime sentinel the open-decision gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3) flips to `resolved` (or `wontfix`) after the per-finding AUQ pick lands, and the §7.0 Pre-Post guard re-reads to fail-close before posting. Omit the field entirely for non-PRODUCT-DECISION findings — its presence is the marker that the open-decision gate owes them an AUQ.

**`report_status:` producer-side initialization.** Write frontmatter `report_status: draft` on this Phase 5.1 handoff write. The report is provisional — written now so a mid-gate compaction recovers the findings, but not yet authoritative. The Phase 6 finalize step (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3.5) flips it to `final` only after the decision gates clear; the handoff offer and the §7.0 public-post guard refuse to fire against a `draft`.

Write the full handoff frontmatter + body skeleton from the template at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.6 "Handoff file template" (the `atomic_state_write` heredoc block). Each finding under `## Findings` renders as the multi-line per-finding body block (NOT a one-liner) per §"Per-finding body schema" in that same reference — the Phase 3 §3.3 KEEP/FILTER judgment preserves every reviewer-agent field; dropping fields to reach a one-liner is the failure mode the schema prevents.

### 5.2 Old state-file fallback

If a file exists at `<PRIMARY_ROOT>/.geniro/state/review-findings-state.md`, read it once on Phase 5 entry for resume compatibility, but always write to the canonical path. The old file is NOT auto-deleted (user may have references).

### 5.3 Auto-emit pitfall learnings on convergence

**Trigger condition:** Phase 3 orchestrator-side dedup produced a finding with `convergence_count: ≥3` (3+ reviewers reported same issue OR 2 reviewers + 1 mechanical pre-pass).

When trigger fires, **auto-emit (no AUQ)**. `emit_learning` reads a single JSON object on stdin — pipe the JSON, do not pass YAML key/value lines (a YAML block exits 64, dropping the learning):

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
emit_learning <<'EOF'
{"producer":"/geniro:review","type":"pitfall","scope":"<changed-file-glob>","summary":"<finding title with file:line>","tags":["<dimension>","<project-tech>"],"trust":"verified","body":"Cross-reviewer convergence: <N> reviewers + <mechanical-flag>"}
EOF
```

Required fields are `producer` / `scope` / `summary` / `tags` (a missing one exits 64). Dedup + sanitization per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md`. After a successful emit (`rc=0`), echo `Recorded learning: <summary>` while the report is being assembled (not after it's delivered), per that file's §"Caller contract"; on a non-zero return, print one plain-English line so the dropped learning is visible rather than swallowed.

### 5.4 PR comment posting (conditional — gated by Phase 6)

If Phase 6 user picks "Post Draft PR" option, post the finding list as a PENDING review per the canonical procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.5: one `gh api POST /repos/<owner>/<repo>/pulls/<number>/reviews` call, `event` field omitted from the jq payload. GitHub creates the review in PENDING state — visible only to the reviewer on github.com's "Finish your review" panel, no notifications fire until the human clicks Submit. Never pass `event: COMMENT` / `APPROVE` / `REQUEST_CHANGES` (those submit the review and defeat the "draft" semantics the user asked for); `event: "PENDING"` is INVALID — omission is the correct mechanism. /geniro:review never publishes the review it creates: never call the submit endpoint `gh api --method POST /pulls/<number>/reviews/<id>/events` either — submitting is the user's own action on github.com, and this holds across rounds (a round-2+ re-review also stays PENDING and re-fires the action gate before posting).

`mcp__github__pull_request_review_write` is NOT used here — the MCP wrapper does not surface the per-comment `path` / `line` / `side` fields required for inline anchoring, so the canonical tool is `gh api` directly per the reference. State persistence per `atomic_state_write`:

```yaml
non-resumable-actions:
- action: pr-review-comment-batch
completed-at: $(date -u +%Y-%m-%dT%H:%M:%SZ) # live clock interpolated in the same write call — never model-supplied (atomic-state-write.md §Timestamp sourcing)
pr-ref: <owner>/<repo>#<num>
finding-count: <N>
comment-ids: [<id1>, <id2>,...]
```

PR post fails fail-closed — on non-zero `gh api` exit (HTTP error, missing scopes, secondary rate limit), write `## Errors` entry + abort Phase 5; never silently downgrade to top-level `gh pr comment` or retry with `event: COMMENT`.

Full Post drill (Steps 0-6) in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md`.
### 5.5 Idempotent re-entry

If Phase 5 re-enters after compaction:
1. Read state.md `non-resumable-actions[]` — if PR post already completed, skip re-post.
2. Re-read findings from Phase 3 dedup output (held in context OR re-runs Phase 3 if context lost).
3. Re-write `from-review-<branch>.md` (overwrite — `atomic_state_write` handles atomicity).
4. Re-writing resets `report_status: draft`; Phase 6 finalize re-runs and re-flips to `final` after the decision gates clear (idempotent — re-entry never leaves a stale `final`).

---

## Phase 6 — Action Gate Handoff

State.md `phase: action-gate`. **Full contract:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md`.

Summary of the gate chain (each gate is its own AUQ — never collapsed):

1. **Pre-gate — Resolve Open Questions** fires first whenever frontmatter `open_questions[]` has any entry with `status: unresolved`. Chain one AUQ per such entry (cap-extension >4). Always-WAIT. Resolutions persist back via `atomic_state_write`. Complete this before any other gate, because the later gates act on findings whose ambiguity these questions resolve. Full procedure: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.5. Skipped when zero unresolved entries.
2. **Open-decision gate** — for each kept finding whose state-file `Decision Type:` field is `PRODUCT-DECISION` — judgment calls the reviewer won't resolve for you — render the finding to chat first, then fire one lean AUQ (header `Open decision`), per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering. Skipped when none.
   - **Finalize (silent — no AUQ).** After the open-decision gate clears, flip the report from `draft` to `final` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3.5). The Action gate's handoff option and the public-post guard both require `final`, so the handoff is never offered against a report whose decisions are still open. This is the fix for "the report is finalized before I've decided".
   - **Suggest improvements (reflection, read-only).** After finalize, before the Action gate, spawn `reflection-agent` (read-only, mode `review`) to propose project-rule updates from the kept findings + diff (full spawn slots — rule-file paths + prior declines — in §3.7), per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` §"Reflection-agent feed". /geniro:review never writes project files — route instruction-scoped candidates to `/geniro:instructions create` and surface the rest (CLAUDE.md / `.claude/rules/` / ADR) as advisory notes. **Emit the reflection echo as the closing step of this gate, in the response that completes the reflection pass and BEFORE the Action gate AUQ fires:** `Reviewed for improvements: <N> candidate(s)` (`0 candidate(s)` when the agent returns nothing) — a dropped echo leaves the user unaware the reflection ran; the Definition-of-Done line below makes the drop detectable. Full procedure: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3.7.
3. **Action gate** — render the wrap-up chat message first (all-decided tracker + one-sentence opener + kept-findings severity digest, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §4), then fire `AskUserQuestion` with the canonical 4 options. Never collapse into chat text ("Want me to apply these now?" / "Should I push?" / "apply the fix now" / "add the test now") — that bypasses the persisted-pick contract and silently drops options the user might want (e.g., Post Draft PR review). The canonical 4 option labels below are an allowlist: substituting an ad-hoc "apply the fix" / "add the test" / "what next?" option (or applying any fix from /geniro:review) is forbidden — fixes route to `/geniro:implement findings`. Option labels (verbatim, do not paraphrase):
   - `"/geniro:implement findings"` — append ` (Recommended)` when CRITICAL≥1 OR HIGH≥2; exits /geniro:review and the model surfaces `/geniro:implement .geniro/state/handoff/from-review-<branch>.md` as the next command. Its description must disclose that /geniro:implement applies the fixes and asks before committing/pushing — picking it routes the findings, it does not authorize a ship (per the §4 literal description).
   - `"Post Draft PR review"` — present whenever `pr-ref:` is non-`none` AND at least one finding of any severity (including LOW / deferred / sub-threshold) remains unposted. OMIT only when `pr-ref: none`, OR no findings exist at all, OR every finding already carries `[POSTED-TO-PR]` from a prior round.
   - `"Continue rounds (re-review)"` — Round-N escalation gate fires when round ≥3.
   - `"Skip — keep findings on disk"` — append ` (Recommended)` when CRITICAL=0 AND HIGH≤1.

   Full AskUserQuestion shape (literal block), descriptions, and severity-driven recommendation rule: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §4. Persist user pick to `approvals[]` with category `action_gate` via `atomic_state_write` (never a raw write on the handoff path).
4. **Failing-tests gate** — fires unconditionally whenever state.md `## Authored Tests` is non-empty (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §6). A chat request to commit/push authored tests — whenever it arrives — re-fires this gate instead of executing directly.

Operational rules:

- **Reporter behavior** — no fix loop inside /geniro:review. /geniro:implement self-review (5-dim parallel) is a separate skill with a separate contract.
- **Round-N escalation gate** when round ≥3 + "Continue rounds" pick — secondary AUQ (Continue / Escalate / Abort). Terminal `aborted` records `## Termination reason: repeated-failure: round-limit-3`.
- **Pre-Post unresolved-ambiguity guard** (§7.0) — defensive re-check before `gh api POST /reviews`: aborts the Post drill if any `open_questions[]` entry has `status == unresolved`, OR any PRODUCT-DECISION finding has `step0_status: pending`, OR any kept CRITICAL/HIGH/MEDIUM finding still carries `Validation: refuted` (it should have been filtered at Phase 4.2), OR the report is still `report_status: draft` (the §3.5 finalize step never ran). Fail-closed second line of defense against producers writing new entries mid-phase or the open-decision gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3) being skipped under drift.
---

## ACI per-phase tool surface

| Phase | Allowed tools | Restricted |
|---|---|---|
| Phase 1 / 1.5 | Read, Grep, Glob, Bash (read-only — `gh pr view`, `git diff`, `which <tool>`, lint commands, `tsc --noEmit`), **`mcp__linear__*` (read-only — `get_issue` / `list_issues` for workflow integration; degrade silently if unregistered)** | No Edit/Write apart state.md; no Linear `update_issue` / `create_comment` from /geniro:review (those remain in /geniro:implement Ship) |
| Phase 2 / 3 / 4 | Agent (reviewer-agent, per-finding verifier (reviewer-agent in verify-finding mode), adversarial-tester-agent); Phase 2 read-only Bash (build verification per §2.7 — `tsc --noEmit`, lint, test); Phase 3 dedup orchestrator-inline (no spawn) | No Edit/Write mutations; no Bash mutations |
| Phase 5 | Write (scoped to `.geniro/state/handoff/**`), `Bash` (conditional — `gh api POST /pulls/N/reviews` with `event` omitted; see §5.4), `emit-learning` helper | Direct edits outside scope blocked by hooks; never `gh api` with `event: COMMENT` / `APPROVE` / `REQUEST_CHANGES`, and never the submit endpoint `gh api POST /pulls/N/reviews/<id>/events` (publishing a pending review is the user's action) |
| Phase 6 | AskUserQuestion, Agent (reflection-agent — read-only, §3.7 improvement suggestions) | No Edit/Write on project files (reporter never mutates source/rules; instruction-scoped improvements route to `/geniro:instructions create`) |

Existing safety hooks apply: file-protection, git-guardrails, `.geniro/` deletion guard, state-helper enforcement, plus security-pattern-scan and config-weakening on any Edit/Write.

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
| Phase 5.3 | `emit-learning` | write L2 | n/a | producer = /geniro:review; type = `pitfall`; trust = `verified` | append to `learnings.jsonl` |
| Phase 6 | `atomic_state_write` | write T2 | n/a | state file path; updated `approvals[]` | whole-file rewrite |

**L2 emit triggers**:
- `pitfall` — **YES** — Phase 5.3 auto-emit when convergence ≥3.
- `convention` — Not emitted here; /geniro:implement owns convention emits.
- `decision` — Not emitted here; /geniro:plan owns.
- `diagnosis` — Not emitted here; /geniro:debug owns.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "/geniro:review should fix its own findings — parity with /geniro:implement self-review is good." | /geniro:implement self-review is a post-implementation gate inside a mutation skill. /geniro:review is a standalone read-only audit consumed by downstream skills (/geniro:implement, manual). Different workflows, different output contracts. Surface-level parity creates a false constraint and would re-introduce the deleted fixer responsibility. Running /geniro:review as a self-authored `Workflow(...)` (including the opt-in `--deep` mode's internal recall/vote workflows) or under ultracode does NOT suspend the Reporter boundary, the canonical action-gate options, or the `atomic_state_write` state-write contract — the workflow parallelizes the reviewer fan-out, not the contract; route fixes to /geniro:implement. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`. |
| "Mechanical pre-pass is too slow — skip it, LLM reviewers cover the same ground." | LLM reviewers cover similar ground at ~100× the cost with non-deterministic output. Lint detects a missing import faster and more reliably than a security reviewer would. Run cheap-deterministic first; LLM-spawn second with pre-pass findings as prior-context per Phase 1.5. |
| "I'll spawn only 4 dimensions — they cover the main risk surface for this diff." | Every always-fire dim per §2.1 is MANDATORY. Conditional dims fire per their trigger rule. The cost of N parallel spawns is parallelized — wall-time is ~max(spawn-time), NOT sum. The cost of a missed CRITICAL finding is unbounded. Phase 4 §4.0 verification gate catches the trim; do not require the user to enforce it. |
| "The custom reviewer in `.geniro/instructions/review-extra/<slug>.md` is narrow scope — skip its discovery to save turns." | Discovery is a mechanical Glob + frontmatter parse — cheap. Custom reviewers exist because the user explicitly authored them; silently skipping defeats the entire `instructions/review-extra/` feature. Per Phase 1.5 §1.5.4, discovery runs in the mechanical pre-pass so Phase 2 has zero cognitive load for it. |
| "Just keep guidelines — duplicate finding is a feature, not a bug." | User-facing "told twice" is concrete UX friction. Two reviewers reporting the same thing wastes user attention. The specialized dim (conventions) wins on cost AND quality; let the dedicated reviewer own the finding category. |
| "I'll tag this LOW as MEDIUM to clear the threshold" / "Auto-drop MEDIUMs to reduce user friction" | Both game the Phase 4.1 multi-signal gate (§4.1: convergence_count ≥2, Evidence-Block + confidence ≥60, criteria-pre-resolved marker, confidence ≥80 fallback — the confidence threshold is one of four signals, not a load-bearing primary). Inflating severity corrupts the taxonomy for downstream consumers (verifier, stratifier, /geniro:implement) AND surfaces low-impact findings on the PR. Dropping is equally untrustworthy — /geniro:review has no fix loop, so sub-threshold MEDIUMs go to `## Deferred — sub-threshold` for awareness, never silently dropped (users notice when their MEDIUMs vanish). Trust the gate; let LOW be LOW and keep MEDIUM visible. |
| "This finding is a PRODUCT-DECISION but only LOW severity — it belongs in Deferred." | Severity (impact-if-wrong) and decision-type (who-decides) are orthogonal. A PRODUCT-DECISION names a call the reviewer cannot close — it is the user's — so §4.1 Path B keeps and surfaces it regardless of severity, and the §3 open-decision gate asks the user. This is the inverse of the row above: do NOT inflate its severity (LOW stays LOW), but DO keep it. Silently deferring a LOW PRODUCT-DECISION makes the reviewer decide the user's call — the exact failure the decision-type axis exists to prevent. |
| "I'll spawn the adversarial-tester-agent and ask the user to confirm later." | Inline-after-action gates rationalize into "this counts as approval". The Phase 4.3 invariant is `AskUserQuestion` BEFORE spawning, not after. The two-step gate (ask → on YES, spawn) is the only rationalization-resistant variant. |
| "The findings look obviously postable — I'll just batch-post to the PR and tell the user after." | Posting to a PR is an external write to a public surface. Phase 6 Action gate's "Post" selection IS the consent — without it, ambiguity that should have been resolved gets pushed onto the PR author or downstream reviewer. |
| "Eligible findings exist and the user clearly wants tests — author them without the Phase 4.3 question." | The test-confirmation gate fires whenever eligible findings exist, and authoring without the user's explicit `test_gate_choice` pick is forbidden. No prior signal — an earlier round's approval, the depth pick, an emphatic ask for thoroughness — substitutes for this run's pick. Empty-answer fallback re-asks rather than auto-defaults. |
| "The user told me in chat to push the authored tests — that's explicit consent, I'll just run git push." | Chat text is never a gate. Authored-test pushes route ONLY through the Phase 6 Failing-tests gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §6; reporter-boundary.md §1 triple-scope). Fire the gate and act on its pick — the gate render is what makes the consent auditable and persisted to `approvals[]`. |
| "I'll auto-update Linear status from /geniro:review when findings are critical — saves the user a step." | /geniro:review is a Reporter. Linear `update_issue` / `create_comment` are external side-effect writes; only /geniro:plan and /geniro:implement run them per their workflow contracts. /geniro:review's MCP surface is read-only (`get_issue` / `list_issues`) per ACI. The Open Questions schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 lets /geniro:review surface ambiguity without mutating tracker state. |
| "Inline LINEAR CONTEXT into every dim — more context = better review." | Cross-reviewer convergence anti-pattern: LINEAR CONTEXT helps spec-compliance (rubric source), pr-metadata (title-divergence check), architecture (parent-epic linkage), and regressions (intent classification). Other dims see it as noise that biases their per-file rubric. The narrow 4-dim distribution is the documented pattern. |
| "Regressions dim feels redundant with spec-compliance — skip it on PRs that have a spec." | spec-compliance covers diff-omits-spec-item; regressions covers diff-exceeds-stated-intent. They're inverse directions, not duplicates. Regressions also fires on spec-less PRs where spec-compliance can't (matches user mental model: catch unintended changes broadly). |
| "Per-finding verifier agreed with the finding — confirmation logged, done." | Confirmation without an `evidence:` quote from the cited file or caller chain is rationalization theater. If the verifier didn't quote literal code, the verification didn't happen — re-spawn with stricter prompt. Sycophancy is the documented multi-judge failure mode. Additional anti-rationalization guards for the hoisted §4.2 scope (sampling pressure, CRITICAL-skip rationalization) live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §6. |
| "Round 1 returned clean. Run round 2 to confirm / get a nicer summary line / second opinion." | Clean = Done. The Round-N escalation gate (Loop Invariant #5) ends the flow on clean result; do not loop back into Phase 2 for cosmetic polish or a "second opinion." Extra rounds waste compute AND risk hallucinated findings against an empty diff. Once a round exits with zero kept findings, the Phase 6 Action gate is the terminal step. |

---

## Definition of Done

These are the load-bearing exit gates — the invariants that, if skipped, make the review incomplete or unsafe. Per-phase mechanics (context loading, mode detection, scoring) live in their phase sections; this list is the final correctness/contract check, not a re-listing of every step.

- [ ] The mandatory reviewer spawn list ran in parallel — all 8 always-fire dimensions (including `regressions`) + every applicable conditional dimension (design / pr-metadata / spec-compliance / rules-compliance) + custom dimensions; `spawn_dims_declared[]` recorded before the batch and the post-spawn verification gate confirmed declared == actual.
- [ ] The spawn echo (`Spawning <N> reviewers: ...`) was emitted in the same response that fired the reviewer batch (per §2.3.1).
- [ ] A fresh per-finding verifier ran for EVERY admitted survivor (CRITICAL / HIGH / MEDIUM); refuted findings demoted to `## Filtered`.
- [ ] The multi-signal admission gate was applied (not the legacy single threshold) per Loop Invariant #6.
- [ ] Every kept finding is classified by severity (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1) and decision type, and tagged `[NEW]` / `[PRE-EXISTING]`.
- [ ] The needs-your-decision gate fired for every such finding regardless of severity, and all are resolved (or wontfix) BEFORE the handoff is offered or anything is posted (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.0 Pre-Post guard).
- [ ] State.md `phase:` was stamped via `atomic_state_write` on ENTRY to each phase (per Loop Invariant #10), so the spawn-declaration and pre-pass declaration existed before the gates that read them — not deferred to persist time.
- [ ] The mechanical pre-pass attempted all three checks (lint / schema / secret), each with a recorded outcome (findings or a `## Errors mechanical-prepass-<id>` entry), `mechanical_prepass_attempted[]` was declared, and the §4.0a gate confirmed the declaration.
- [ ] The handoff artifact was written to `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` via `atomic_state_write`, carrying structured `open_questions[]`.
- [ ] The report was finalized (`report_status: draft→final`) only after the decision gate cleared; on Post, `[POSTED-TO-PR]` idempotency markers were persisted.
- [ ] The reflection echo (`Reviewed for improvements: <N> candidate(s)`, including at zero) was emitted before the Action gate AUQ fired (per the Suggest-improvements step).
- [ ] The Action gate fired (always-WAIT); the user pick persisted to `approvals[]`; the round-N escalation gate fired when round ≥3.
- [ ] `--deep` honored when present; test authoring (when approved at the test-confirmation gate) stayed additive — it never filtered the posted finding set.
