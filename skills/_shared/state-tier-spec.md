# Canonical state-tier specification

**Canonical reference for every state file in `.geniro/`.** See `ARCHITECTURE.md` §State Files for the design decisions behind this spec.

Helpers reference this spec:
- `skills/_shared/atomic-state-write.md` — write helper for T1, T3 CRUD, and append-only.
- `skills/_shared/validate-state-file.md` — validates frontmatter against this spec.

---

## Tier model

Every state file in `.geniro/` belongs to exactly one tier, determined by its path root and lifecycle contract.

| Tier | Purpose | Lifecycle | Worktree routing | Concurrency |
|---|---|---|---|---|
| **T1 — TASK ephemeral** | Transient subagent outputs / scratch (no frontmatter) | Created mid-run; deleted at Phase Ship | cwd-relative | path-scoped via `<task-dir>` |
| **T1.5 — TASK durable** | Frontmatter-bearing task artifacts owned by one skill run, but needed by downstream consumer skills (`/review` spec-compliance, `/implement` Adjustment Routing, `/debug`, `/refactor`) | Created at Phase 0; **survives Phase Ship** | cwd-relative | path-scoped via `<task-dir>` or `<skill>/<slug>` or singleton `<skill>/state.md` |
| **T2 — HANDOFF** | Inter-skill data hand-off | Created by producer; overwritten on next produce; not auto-deleted | primary-worktree (via `primary-worktree.md` Mode A) | branch-scoped path |
| **T3 — PERSISTENT** | Cross-session knowledge & user content | Never auto-deleted; CRUD or append-only | primary-worktree always | declared via `concurrency:` sub-attribute |

**T1 vs T1.5 distinction.** T1 = ephemeral transient outputs without frontmatter (subagent reports — `.kr-out.md`, `.ce-out.md`, `.tr-out.md`, `.adversarial-out.md`; ad-hoc scratch `notes.md`; screenshots `playwright-verify.png`). They never pass through `validate_state_file`. T1.5 = frontmatter-bearing durable artifacts (`spec.md`, `state.md`, `plan-*.md`, `milestone-*.md`) that downstream consumer skills read after the producing skill ships. The Phase-Ship cleanup contract `rm -f`s ONLY the T1 ephemeral list; T1.5 durable files persist for skill chains.

---

## Path roots

### T1 — ephemeral transient outputs (no frontmatter; deleted at Ship)

| Path | Producer |
|---|---|
| `.geniro/planning/<task-dir>/.kr-out.md` | knowledge-retrieval-agent (subagent report) |
| `.geniro/planning/<task-dir>/.ce-out.md` | codebase-explorer-agent (subagent report) |
| `.geniro/planning/<task-dir>/.tr-out.md` | test-runner-agent (subagent report) |
| `.geniro/planning/<task-dir>/.adversarial-out.md` | adversarial-tester-agent (subagent report) |
| `.geniro/planning/<task-dir>/notes.md` | Orchestrator ad-hoc scratch |
| `.geniro/planning/<task-dir>/playwright-verify.png` | Pre-Ship Visual Verification screenshot |

These files do NOT carry frontmatter and are NEVER validated via `validate_state_file`. They are cleaned mechanically at Phase Ship via targeted `rm -f`.

### T1.5 — three valid layouts (producer-bound; survives Ship)

| Path root | Layout | Producer category |
|---|---|---|
| `.geniro/planning/<task-dir>/` | Multi-file task-dir (`state.md` + `spec.md` + `plan-*.md` + `milestone-*.md`) | **Task-bound skills** producing durable artifacts — `/implement`, `/plan` |
| `.geniro/state/<skill>/<slug>/` | Subdir-per-slug; canonical `state.md` inside | **Session-bound skills** — `/debug`, `/refactor`, `/onboard`, `/investigate` |
| `.geniro/state/<skill>/state.md` | **Singleton** — no `<slug>/` subdir | **Singleton-lifecycle skills** — `/setup` |

### T2

- `.geniro/state/handoff/from-<producer>-<branch>.md`

### T3

- `.geniro/knowledge/` — append-only (`learnings.jsonl`)
- `.geniro/instructions/` — CRUD (rule sets)
- `.geniro/actions/` — CRUD (workflow actions)
- `.geniro/workflow/` — CRUD (integration config)
- `.geniro/planning/_FEATURES.md`, `_CODEBASE_MAP.md`, `_project.md`, `_architecture.md`, `_focus-<area>.md` — CRUD global registries (`_` prefix = visual cue for persistent-global)
- `.geniro/docs/` — CRUD (`/setup` spin-out targets — `hooks.md`, `mcp.md`, `agent-runtime.md`)

---

## Frontmatter contract

### Common base — required on every state file

| Field | Type | Example |
|---|---|---|
| `tier` | enum `T1\|T1.5\|T2\|T3` (T1 used for transient outputs that omit frontmatter; not enforced when present) | `T1.5` |
| `producer` | string | `implement` |
| `schema-version` | integer | `1` |
| `branch` | string | `feature/dark-mode` |
| `timestamp` | ISO-8601 UTC | `2026-05-19T14:30:00Z` |

### Tier-specific required

| Tier | Additional required fields |
|---|---|
| T1 | `phase`, `status`, `non-resumable-actions` |
| T1.5 | `phase`, `status`, `non-resumable-actions` (same shape as T1; differs in lifecycle) |
| T2 | `consumer`, `open_questions` (array; MAY be empty `[]` when producer surfaced none) |
| T3 | `concurrency` (enum `append-only\|crud`) |

### Optional everywhere

| Field | When useful |
|---|---|
| `description` | T3 user-CRUD (editor display) |
| `tags` | T3 user-CRUD (editor search) |
| `worktree` | Cross-worktree debugging — absolute path to a worktree |
| `checksum` | Manual-edit corruption detection (sha256 of body) |
| `notes` | Free-form |
| `geniro_kind` | Producer schema marker — informational only |
| `geniro_schema_version` | Producer schema-version marker — informational only |

### T1 optional `approvals` array

Persisted AUQ outcomes for compaction-survival. Only **one-time** decisions (e.g., `$ARGUMENTS` disambiguation, ship-mode). Context-dependent decisions (escalation, retry choices) are NOT persisted.

```yaml
approvals:
  - category: <category-slug>      # canonical slug
    prompt: <verbatim AUQ prompt>
    options: [<opt1>, <opt2>, ...]
    picked: <chosen option>
    at: <ISO-8601 UTC>
    asked_in_phase: <phase name>
```

### T2 required `open_questions` array

Producers that surface ambiguous-how-to-fix decisions or scope questions write them as structured entries. Consumers (downstream skills) MUST gate on `status: unresolved` before taking any mutating action — code edits, posting to external systems, status transitions, etc.

```yaml
open_questions:
  - id: q1                                          # short stable anchor (used by AUQ chaining and resolution writes)
    source: spec-compliance                         # the reviewer dim / producer step that surfaced it
    question: "API seeder additions in-scope or split into separate PR?"  # the actual question, verbatim
    context: |                                      # OPTIONAL but RECOMMENDED — 2-6 line problem framing rendered with the question
      The PR includes 3 new seeder files under db/seeders/ alongside the API
      endpoint changes. spec.md §Forbidden Actions lists "seeder modifications
      outside dedicated seeder PRs". Reviewer flagged scope mismatch; the right
      resolution depends on whether the seeders are mandatory for the endpoint
      to function (in-scope) or coincidental cleanup (split).
    evidence:                                       # OPTIONAL but RECOMMENDED — code anchors with snippets, rendered in AUQ preview
      - file: db/seeders/api_users.sql
        lines: 1-12
        snippet: |
          -- Seed initial API users so the new /api/v2/users endpoint has data.
          INSERT INTO api_users (id, email, role) VALUES ...
      - file: spec.md
        lines: 145-149
        snippet: |
          ## Forbidden Actions
          - No seeder modifications outside dedicated seeder PRs.
    options:                                        # OPTIONAL but RECOMMENDED — pre-authored options used directly by the AUQ renderer
      - id: A
        label: "In scope — keep seeders in this PR"
        description: "Seeders are required for the endpoint smoke-test; splitting would block the endpoint reviewer from running tests."
        preview: |
          ## Effect
          - 3 seeder files stay in this PR
          - spec.md §Forbidden Actions gets a per-task exception line
          - PR description annotated: "Seeders bundled — required for smoke-test"
      - id: B
        label: "Split — revert seeders to a separate PR"
        description: "Honors spec.md forbidden-actions verbatim. Endpoint PR ships without seeders; reviewer must trust unit tests."
        preview: |
          ## Effect
          - `git checkout HEAD~ -- db/seeders/` reverts seeder additions
          - New branch `chore/api-seeders` for seeders alone
          - Endpoint PR description updated: "Seeders split to #N+1"
      - id: C
        label: "Out of scope — drop entirely"
        description: "Seeders weren't planned in spec.md; treat them as accidental scope creep. Lose the smoke-test data."
        preview: |
          ## Effect
          - `git checkout HEAD~ -- db/seeders/` reverts seeder additions
          - No follow-up PR — seeders deferred to backlog
    recommendation:                                 # OPTIONAL — producer's recommended option + rationale
      option_id: B
      rationale: "Spec.md is explicit; honoring it preserves the project's PR-scope hygiene. The smoke-test data gap is recoverable via a follow-up seeder PR."
    related_findings: [F1, F4]                      # optional — finding IDs this question gates (cross-reference into ## Findings body)
    status: unresolved                              # enum: unresolved | resolved | wontfix
    resolution:                                     # populated when status moves out of `unresolved`
      picked: "Split — revert api seeders to a separate PR"
      at: 2026-05-26T13:45:00Z
      asked_in_phase: phase-6-gate
      resolved_by: review                           # which skill ran the resolution AUQ
```

**Producer responsibilities:**
- Initialize `open_questions: []` in the handoff frontmatter. NEVER use a free-text `## Open Questions` Markdown bucket — body sections are not machine-readable.
- Each entry MUST have `id`, `source`, `question`, `status` set; all other fields (`context`, `evidence`, `options`, `recommendation`, `related_findings`, `related_hypotheses`, `resolution`) are optional. `related_hypotheses` is the `/debug`-producer equivalent of `related_findings` — it links a question to Hypothesis IDs from the debug run's `## Hypotheses` body.
- **Fill `context` + `evidence` + `options` + `recommendation` whenever feasible** — they're the substrate the consumer renders into a rich `AskUserQuestion` preview per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Single-finding gate. A bare `question:` field leaves the consumer to synthesize options at render time (legacy fallback), which produces terse AUQs that erode user trust. Producer-side context is cheaper to author once than to reconstruct downstream.
- When the question gates a reviewer finding, populate `related_findings` so the consumer can cross-reference into the body `## Findings` section for additional detail (Confidence / Origin).
- IDs are stable within a single handoff file (q1, q2, …); they may collide across handoffs.

**Consumer responsibilities:**
- Before any mutating action that depends on the handoff (Edit/Write in /implement; `gh api POST /reviews` in /review's draft-post path; status transitions in /implement Phase 3 Ship), check `open_questions[].status`. If any entry is `unresolved`, fire an AUQ batch chained across the unresolved entries (cap-extension when >4), persist each answer back to the producer's file via `atomic_state_write`, then proceed.
- A consumer that finds `unresolved` entries and ships anyway is a contract violation.

**Free-text body fallback:** the body section `## Open Questions` MAY mirror the frontmatter as a human-readable view (Markdown bullet list with `id` anchors), but the frontmatter is the source of truth. Validators check the frontmatter only; the body is informational.

### Producer-specific extensions

Producers MAY add fields (e.g., `task_slug`, `mode`, `effort_tier`, `round`, `risk-tier`). Constraints:
- MUST NOT shadow common-base or tier-specific field names with different semantics.
- MUST be documented in the producer's M-doc frontmatter example block.
- The validator silently passes them through — only required-field presence and enum values are checked.

**`/review` producer-specific fields:**

- `spawn_dims_declared: [<dim-slug>, ...]` — declared parallel-spawn list, written at Phase 2 entry before the batch fires. Consumed by Phase 4 §4.0 verification gate (declared-vs-actual diff).
- `spawn_dims_count: <int>` — denormalized length of `spawn_dims_declared`.
- `custom_reviewers: [{slug, paths_matched, model, source_path, severity_default}, ...]` — discovered in Phase 1.5 §1.5.4 via `load-custom-reviewers.md`. Consumed by Phase 2 to merge into the spawn batch.

**`/debug` producer-specific `authored_tests` array (T2 handoff only):**

Carries every F→P reproduction test authored during the debug run as the machine-readable source-of-truth for downstream consumers. The body `**Reproduction test:**` line (scientific mode) and `**Test file:**` lines (adversarial mode) remain as a human-readable mirror; consumers prefer this frontmatter array and fall back to body parse only for legacy handoffs (m7-v1).

```yaml
authored_tests:
  - id: t1                            # short stable anchor (t1, t2, ...) — collision-safe within one handoff
    path: tests/api/handler.test.ts   # relative to git rev-parse --show-toplevel of debug-source-worktree
    intent: "covers H2 — null-pointer on empty payload"   # one-line description of what the test guards
    mode: scientific                  # enum: scientific | adversarial
    f_to_p_status: red-on-current     # enum: red-on-current | green-under-patch | red-on-current+green-under-patch | escape-hatch
    related_hypotheses: [H2]          # optional — Hypothesis IDs from `## Hypotheses` body (scientific mode)
    targeted_source: src/api/handler.ts  # optional — production file the test targets (used in adversarial mode for triage)
    confidence: high                  # optional — adversarial mode only (high | medium | low)
```

**Producer responsibilities:**
- Initialize `authored_tests: []` in the handoff frontmatter even when no test was authored (e.g., scientific path B "accept as documented limitation" or adversarial zero-red-tests terminal). The empty-array form lets consumers distinguish "no tests by design" from "field absent in legacy handoff".
- One entry per authored test file. If a single test file holds multiple test cases, one entry covers it; the `intent` field summarizes the file-level guarantee.
- `path` is repo-root relative. Consumers re-resolve against their own `git rev-parse --show-toplevel` to handle cross-worktree consumption.
- `mode` MUST match the handoff's top-level `mode:` discriminator (`scientific` for `from-debug-<branch>.md`, `adversarial` for `from-debug-adversarial-<branch>.md`).
- Scientific mode `f_to_p_status: escape-hatch` paired with an `intent: "escape-hatch: <rationale>"` is valid — surfaces the §2.4 hard-to-mock chain case where the bug cannot be verified without temporary production edits (which are reverted before escalation).

**Consumer responsibilities:**
- Read `authored_tests[]` before falling back to body-string parsing. The shared consumer protocol at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` codifies the prefer-frontmatter / fallback-to-body order.
- Resolve each `path` against the current `git rev-parse --show-toplevel` and bucket as PRESENT / MISSING. On MISSING, surface the cross-worktree relocation suggestion from `_shared/debug-handoff.md` §Step 4 Case B1 — never auto-execute `git checkout <debug-source-branch> -- <path>`.
- The array is informational, not a gate — consumers do NOT block on its presence or content. The `open_questions[]` gate remains the only Edit/Write blocker for /implement Phase 1.

---

## Format rules

- Frontmatter MUST start on line 1 with `---`.
- Closing `---` on its own line.
- Empty line after closing fence before body.
- Body MAY use `## Section` headers; per-skill conventions for content.

---

## Concrete examples

### T1.5 — task-bound (`/implement`)

```yaml
---
tier: T1.5
producer: implement
schema-version: 1
branch: feature/dark-mode
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---

## Phase log
- analyze done at 14:25:00Z
- implement started at 14:30:00Z
```

### T1.5 — session-bound (`/debug`)

```yaml
---
tier: T1.5
producer: debug
schema-version: 1
branch: fix/null-pointer
timestamp: 2026-05-19T14:30:00Z
phase: investigate
status: in-progress
non-resumable-actions: []
geniro_kind: debug-state
---
```

### T1.5 — singleton (`/setup`)

```yaml
---
tier: T1.5
producer: setup
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
phase: detect
status: in-progress
non-resumable-actions: []
mode: init
---
```

### T2 — handoff

```yaml
---
tier: T2
producer: review
schema-version: 1
branch: feat/ci-277
timestamp: 2026-05-26T13:30:00Z
consumer: implement
severity-summary: "1 CRITICAL, 7 HIGH, 5 MEDIUM"
open_questions:
  - id: q1
    source: spec-compliance
    question: "API seeder additions in-scope or split into separate PR?"
    related_findings: [F1]
    status: unresolved
  - id: q2
    source: architecture
    question: "Accept parallel CwCaseCardAdapter chrome or refactor to delegate?"
    related_findings: [F3]
    status: unresolved
---
```

### T3 — CRUD (instructions)

```yaml
---
tier: T3
producer: user
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
concurrency: crud
description: "TypeScript strict-mode style rules"
tags: [typescript, style]
---
```

### T3 — append-only (learnings sidecar)

`learnings.jsonl` itself is JSONL with no frontmatter. The sidecar `learnings.jsonl.meta.yaml` carries the tier metadata:

```yaml
---
tier: T3
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
concurrency: append-only
schema-ref: "canonical L2 entry schema"
---
```

Per-line JSONL schema (canonical L2 entry schema): `ts`, `producer`, `scope`, `summary`, `tags`, plus optional `body`, `links`, `dedup_key`, `supersedes`, `deprecated`, `trust`, `type`, `ext`.

---

## Validation rules (summary)

The `validate_state_file` helper enforces:

1. File exists and starts with `---` on line 1.
2. Frontmatter parses (closing `---` present).
3. Common-base required fields present and non-empty.
4. Tier-specific required fields present per the `tier:` value.
5. `schema-version: 1` (fall-through to migration prompt on mismatch).
6. If `checksum` present, body sha256 matches.
7. If `worktree` present, path exists in `git worktree list` output (graceful skip on non-repo paths).

On failure: hard-fail with a recovery AskUserQuestion (per Q5 — delete-and-restart / open-in-editor / update-worktree-path / skip-emergency).

JSONL files use line-by-line validation: malformed lines logged and skipped.

---

## Slug rule (T1 session-bound layouts)

```bash
slug=$(git branch --show-current | tr '[:upper:]' '[:lower:]' | sed 's#[^a-z0-9]\+#-#g')
if [ "${#slug}" -gt 60 ]; then
  slug="$(printf '%s' "$slug" | head -c 52)-$(printf '%s' "$slug" | sha256sum | head -c 8)"
fi
```

Truncation + hash suffix prevents long-branch collisions to the same 60-char prefix.
