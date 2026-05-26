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
| `.geniro/planning/<task-dir>/` | Multi-file task-dir (`state.md` + `spec.md` + `plan-*.md` + `milestone-*.md`) | **Task-bound skills** producing durable artifacts — M4 (`/implement`), M5 (`/plan`) |
| `.geniro/state/<skill>/<slug>/` | Subdir-per-slug; canonical `state.md` inside | **Session-bound skills** — M7 (`/debug`), M8 (`/refactor`), M9 (`/onboard`, `/investigate`) |
| `.geniro/state/<skill>/state.md` | **Singleton** — no `<slug>/` subdir | **Singleton-lifecycle skills** — M10a (`/setup`) |

### T2

- `.geniro/state/handoff/from-<producer>-<branch>.md`

### T3

- `.geniro/knowledge/` — append-only (`learnings.jsonl`)
- `.geniro/instructions/` — CRUD (rule sets)
- `.geniro/actions/` — CRUD (workflow actions)
- `.geniro/workflow/` — CRUD (integration config)
- `.geniro/planning/_FEATURES.md`, `_CODEBASE_MAP.md`, `_project.md`, `_architecture.md`, `_focus-<area>.md` — CRUD global registries (`_` prefix = visual cue for persistent-global)
- `.geniro/docs/` — CRUD (M10a §3.4 spin-out targets — `hooks.md`, `mcp.md`, `agent-runtime.md`)

---

## Frontmatter contract

### Common base — required on every state file

| Field | Type | Example |
|---|---|---|
| `tier` | enum `T1.5\|T2\|T3` (T1 = no frontmatter; not in enum) | `T1.5` |
| `producer` | string | `implement` |
| `schema-version` | integer | `1` |
| `branch` | string | `feature/dark-mode` |
| `timestamp` | ISO-8601 UTC | `2026-05-19T14:30:00Z` |

**Legacy:** pre-v3 state.md files declared `tier: T1`. The validator continues to accept `T1` for backward compat (treated identically to `T1.5`). New emissions from v3 producers use `T1.5`.

### Tier-specific required

| Tier | Additional required fields |
|---|---|
| T1 (legacy) | `phase`, `status`, `non-resumable-actions` |
| T1.5 | `phase`, `status`, `non-resumable-actions` (same as T1; differs only in lifecycle) |
| T2 | `consumer` |
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

### T1 optional `approvals` array (P-M1-1)

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

### Producer-specific extensions

Producers MAY add fields (e.g., M5 `task_slug`, `mode`, `effort_tier`; M6 `phase`, `round`, `risk-tier`). Constraints:
- MUST NOT shadow common-base or tier-specific field names with different semantics.
- MUST be documented in the producer's M-doc frontmatter example block.
- The validator silently passes them through — only required-field presence and enum values are checked.

---

## Format rules

- Frontmatter MUST start on line 1 with `---`.
- Closing `---` on its own line.
- Empty line after closing fence before body.
- Body MAY use `## Section` headers; per-skill conventions for content.

---

## Concrete examples

### T1.5 — task-bound (M4 `/implement`)

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

### T1.5 — session-bound (M7 `/debug`)

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

### T1.5 — singleton (M10a `/setup`)

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
producer: debug
schema-version: 1
branch: fix/null-pointer
timestamp: 2026-05-19T14:30:00Z
consumer: implement
severity-summary: "1 P0, 2 P2"
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
schema-ref: "M2 §5.1 (canonical L2 entry schema)"
---
```

Per-line JSONL schema (canonical in M2 §5.1): `ts`, `producer`, `scope`, `summary`, `tags`, plus optional `body`, `links`, `dedup_key`, `supersedes`, `deprecated`, `trust`, `type`, `ext`.

---

## Validation rules (summary)

The `validate_state_file` helper enforces:

1. File exists and starts with `---` on line 1.
2. Frontmatter parses (closing `---` present).
3. Common-base required fields present and non-empty.
4. Tier-specific required fields present per the `tier:` value.
5. `schema-version: 1` (fall-through to migration prompt on mismatch).
6. If `checksum` present, body sha256 matches.
7. If `worktree` present, path exists in `git worktree list` output (P-M1-2; graceful skip on non-repo paths).

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
