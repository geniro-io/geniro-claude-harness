# /geniro:review — Phase 1 & Phase 1.5

Phase bodies for `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md`. Read on entry to Phase 1. The spine keeps the phase headings, the loop invariants, the anti-rationalization table, and the Definition of done — this file carries the Steps.

## Contents

- Phase 1 — Triage & context collect (13 steps; exit criterion at the end)
- Phase 1.5 — Mechanical pre-pass
  - 1.5.1 Check 1 — Lint
  - 1.5.2 Check 2 — Schema
  - 1.5.3 Check 3 — Secret scan
  - 1.5.4 Custom-reviewer discovery
  - 1.5.5 Output handling
  - 1.5.6 Fail-handling
  - 1.5.7 Pre-pass declaration (state.md write before Phase 2)

---

## Phase 1 — Triage & context collect

State.md `phase: triage`. **Full contract:** `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md`.

**Flags & presets:** `--deep`, `--plan <path>`, and the workspace modifiers are cataloged with the cross-skill flag set in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flags-reference.md`.

Summary of what Phase 1 does:

1. **Step 0 — Workspace setup** — passive context detection, then a decision tree that settles the working tree, with auto-continue branches for in-worktree continuing-work signals; the workspace AUQ fires only when the tree is ambiguous, and inline modifier overrides (`worktree` / `no-worktree` / `current-branch` / `new-branch`) win deterministically. Prior picks are re-applied per triage reference §0-pre — the approved workspace location always and exactly (anti-relocation), depth and re-review scope only on a compaction-resume. Fires BEFORE all subsequent items so they operate on the correct working tree. Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §0.
2. **Input parsing** — resolve the review-target shape from `$ARGUMENTS` (empty / branch name / file paths / diff range / PR ref) per triage reference §1, which also owns the produce-only boundary. A PR ref additionally drives the thread-state + existing-review fetch in item 4.
3. **Scope resolution** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. Resolve the review target only from explicit PR-ref forms; running `gh pr list` to invent a target reviews a PR the user never asked about. When the review scopes to fewer files than the PR shows (commonly a stacked PR, base ≠ default branch), the excluded files are surfaced as a Scope-exclusion note (which ancestor PR owns them + its findings) so "reviewed upstream" is never mistaken for "missed" — full contract `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §2.1. A target sanity gate closes this step: an unresolvable ref or an empty resolved diff aborts with a plain-English report before any reviewer spawns — failing inside the parallel batch wastes it and invites findings against nothing (triage reference §2).
4. **PR-ref parsing** — materialize the diff and fetch PR metadata (base/head refs, body/title, head SHA, URL, draft/author/labels) per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §3. Persist three state.md snapshots later phases read: `resolved-threads-snapshot:` (every resolved thread's `path:line` from the §1 thread-state fetch, so the Phase 6 Post drill's §7.1 already-on-PR dedup can exclude findings overlapping existing PR comments — leave `null` when there is no PR ref or the fetch fails, which §7.1 treats as "no dedup"), plus `pr-formal-reviews-snapshot:` and `pr-bot-comments-snapshot:` from the §1.1 existing-review ingest, both fed to reviewers as prior-context (§2.3).
5. **Workflow integrations** — workflow files (`.geniro/workflow/*.md`) live in the primary worktree per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (Mode A); glob both `./.geniro/workflow/*.md` (cwd-local — uncommitted local edits win) and `<PRIMARY_ROOT>/.geniro/workflow/*.md` (primary fallback). Read them, apply tracker-ID regex against `$ARGUMENTS` + `pr.title` + `pr.body`, AND when a spec.md is resolvable (via `--plan <path>`, `geniro-plan:` PR-body line, walk-up `.geniro/planning/*/spec.md`, or canonical project paths) parse its frontmatter `workflow_refs[]` and merge it with the tracker refs found in `$ARGUMENTS` and the PR body — accepted schema versions and the merge precedence are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` §Spec metadata contract (the `$ARGUMENTS` reference wins on conflict because the user just typed it — the fresher signal). On Linear match with MCP available: fetch issue (+ parent epic + sibling sub-tasks). Build `LINEAR CONTEXT:` block. Persist `linear-task-ref:` + `linear-parent-ref:` to state.md frontmatter, derived from the deduplicated merged list. Read-only — /geniro:review never mutates tracker state via MCP. Fail-open if MCP unavailable.
6. **Peer-PR scout** (PR-ref only) — sibling PRs scored by file overlap + Linear-relatedness bonus, capped and ranked per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §4; the resulting `PEER-PR CONTEXT:` slot is inlined identically into the 7 receiving reviewer prompts named there.
7. **Load custom instructions** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` (MODE: initial-load; scope = `review` + `global` + `code-style` — pipeline tier, 3 files).
8. **Round-N counter** — increments; fires the round-≥3 escalation AUQ first, then (on Continue) on a round ≥2 fresh re-run the re-review gate (scope + depth) — always asked, never auto-decided. Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §7.
9. **PLAN CONTEXT load (schema-aware).** Detection per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-context.md` Structured-section parser when `geniro_kind: design-doc` frontmatter present; prose fallback otherwise.
10. **Risk-tier stratification** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` 9 hard-escalation signals. Sets `risk-tier: standard | high`. Adjusts 4 downstream knobs (severity threshold / validator budget / spec-compliance default / mechanical secret-scan strict mode).
11. **Memory layer load:** `load-semantic` MODE:refresh + `query-learnings` (top-K, K=5 default; when `memory.md` declares a `## Memory Backend` block routing `learnings`, /geniro:review's own tools can't reach the backend read tool, so it delegates that read to a scoped `knowledge-retrieval-agent` spawn — `SCOPE: learnings-backend` — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md` §3 and uses the returned report in place of the file query, which is empty under `mode: replace`; no block → the inline file query runs unchanged) + `resolve-conflicts`.
12. **Size triage** — classify files Trivial / Substantive once the diff crosses the size threshold in `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §12. Controls each reviewer's payload shape: Standard (diff as-is) vs Batched (grouped reading order — never extra spawns). Runs before the depth question so the reviewer count is known at ask time.
13. **Mode AUQ** — review depth (Standard / Deep). Fires on a user-invoked run unless `--deep` is in `$ARGUMENTS`, the §7 re-review gate already asked depth this run, or a compaction-resume inherits it — a fresh re-run always re-asks depth (never inherits a prior completed run's pick). Persist the pick → frontmatter `deep-mode: <true|false>` + `approvals[]` category `deep_mode_choice`. Full chooser shape + deep contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §11 + `${CLAUDE_PLUGIN_ROOT}/skills/review/deep-mode-reference.md`.

Exit criterion: state.md frontmatter carries the fields each prior step wrote — `round`, `risk-tier`, `pr-ref`, `linear-task-ref`, `linear-parent-ref`, `plan-context-ref`, plus `deep-mode` (from the Mode AUQ pick or `--deep` parse) when that step ran; `approvals[]` carries any AUQ answers; `## Tool log` includes initial load echoes.

Phase 1 PR metadata and tracker context loads are orchestrator-inline (`gh pr diff` / `gh pr view` / `mcp__linear__*` reads). For codebase-research side queries inside this phase (e.g., locating a pattern across the wider repo when scoring peer-PR overlap), spawn `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

---

## Phase 1.5 — Mechanical pre-pass

State.md `phase: mechanical-prepass`.

Three deterministic checks BEFORE LLM reviewer spawns. Cheap-deterministic first; LLM-spawn second with pre-pass findings as prior-context. Sequential, not parallel — LLM agents seeing prior mechanical findings produce better-targeted output.

**Each check is must-attempt and lands exactly one of three recorded outcomes** — `findings` (written to the finding list; Check 3's tagged CRITICAL), `clean` (the check ran and found nothing), or `error` (a fail-open `## Errors mechanical-prepass-<id>: <reason>` entry, which also covers not-applicable). There is no silent fourth outcome — skipping a check entirely (e.g. running neither lint nor `tsc` on a TS-dominated diff) is the failure this contract closes, and a clean run is a real result, not the absence of one. Record each check's outcome in state.md frontmatter (§1.5.7) before exiting this phase, mirroring §2.2's spawn-declaration pattern.

### 1.5.1 Check 1 — Lint

Detect the project's own lint setup and run its lint command over the changed files, quietest output the tool offers. Capture failures as `{tool, file, line, rule, message}` tuples.

### 1.5.2 Check 2 — Schema

Run whichever type / schema checks the diff's file types call for — compiler no-emit type check, JSON-Schema or OpenAPI validation, protobuf lint. Capture failures in the same tuple shape.

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

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` to enumerate user-authored review dimensions in `.geniro/instructions/review-extra/<slug>.md`. The helper applies its `paths:` filter against the changed-files list, enforces the ≤10 cap, and returns spawn-specs: `{slug, dimension-label: custom:<slug>, model, criteria-content, severity-default, requires-context, source-path}`.

Persist the result to state.md frontmatter `custom_reviewers[]` — every short spawn-spec scalar, one entry per surviving reviewer (canonical field list: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §"`/geniro:review` producer-specific fields"):

```yaml
custom_reviewers:
  - slug: manifest-incident-patterns
    paths_matched: true               # whether the spec's `paths:` matched any changed file (`true` when no paths filter declared — always-fires)
    model: inherit                    # frontmatter value, or `inherit` when OMITTED in the spec
    source_path: .geniro/instructions/review-extra/manifest-incident-patterns.md
    severity_default: HIGH
    requires_context: "fetch the live incident report, latest entry, and provide its pattern list"   # verbatim `requires-context:` directive, or null when unset
```

The one spawn-spec field this list deliberately omits is `criteria-content` — the user file's whole body. Writing it here would drag every word of every custom rubric through `atomic_state_write` into a durable handoff that ships downstream, then back out at Phase 2: the same pass-through cost §2.3's "pass the path, never the body" rule exists to avoid, paid twice. `source_path` is the anchor instead — Phase 2 re-reads it for the body at the moment it composes the spawn.

Phase 2 reads `custom_reviewers[]` from frontmatter and re-reads each `source_path` for the criteria body — no discovery, globbing, path-filtering, or cap-checking at Phase 2 entry (discovery lives here because Phase 1.5 already has Bash tooling primed, keeping the cognitively heavy Phase 2 spawn assembly free of it).

On helper hard-cap error (>10 custom reviewers), surface the error to chat, persist `custom_reviewers: []`, and let Phase 2 fire only the built-ins. A helper batch-size *warning* is advice to the user about how many custom reviewers to keep — it never trims the batch: the §2.1 always-fire rows fire on every run regardless of how many custom reviewers discovery returned.

### 1.5.5 Output handling

Mechanical findings tagged `origin: mechanical:<check_id>`. Routed two ways:

1. **To Phase 2 LLM reviewers as prior-context** — pasted into spawn prompts under a `## Mechanical Pre-pass Findings` section. LLM agents use those as starting points (avoid duplicating; extend with semantic understanding).
2. **To Phase 5 persist** — included in the state.md finding list with the mechanical tag preserved.

### 1.5.6 Fail-handling

Each check records exactly one outcome. Continue to Phase 2 whatever it is (fail-open, consistent with `gh` fail-open):

- **Check produced findings** → outcome `findings`.
- **Check ran and found nothing** → outcome `clean`. A green lint or type-check is the common case on a healthy diff, and it is a result the §4.0a gate reads as a pass — not a gap.
- **Check failed** (process exit nonzero with no output OR command not found) → outcome `error`; write `## Errors mechanical-prepass-<check_id>: command_unavailable_or_failed`.
- **Check not applicable** (no lint config detected for `lint`; no TS / schema / proto files in the diff for `schema`) → outcome `error`; write `## Errors mechanical-prepass-<check_id>: not_applicable`, so a deliberate skip stays distinguishable from never reaching the check — which is what the §4.0a gate detects.

Secret scan is a pure-regex pass — it cannot fail or be not-applicable, so its outcome is `findings` or `clean`.

### 1.5.7 Pre-pass declaration (state.md write before Phase 2)

Before leaving Phase 1.5, declare each check's outcome in state.md frontmatter via `atomic_state_write`, mirroring §2.2's spawn-declaration pattern:

```yaml
# frontmatter update — one entry per check, value in {findings, clean, error}
mechanical_prepass_attempted:
  lint: findings
  schema: error
  secret: clean
```

Every check that ran gets an entry; a check with no entry is one that was never reached. This is the observability surface the Phase 4 §4.0a verification gate asserts against — a missing declaration, a missing check, or an outcome the run cannot corroborate (`findings` with nothing on the finding list, `error` with no `## Errors mechanical-prepass-<id>` entry) is a pre-pass contract miss the gate surfaces.

---
