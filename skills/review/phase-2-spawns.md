# /geniro:review — Phase 2

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md`. Read on entry to Phase 2. The spine keeps the phase headings, the loop invariants, the anti-rationalization table, and the Definition of done — this file carries the Steps.

## Contents

- Phase 2 — LLM reviewer spawns
  - 2.1 Dimension grid (10 built-in dimensions + N custom)
  - 2.2 Pre-spawn declaration (state.md write before parallel batch)
  - 2.3 Spawn invocation (2.3.1 spawn echo · 2.3.2 fire the batch · criteria files)
  - 2.5 UI-file detection rule (design dim trigger)
  - 2.6 Spec-compliance detection rule
  - 2.7 Build verification (parallel with reviewers)
  - 2.8 Rules-file detection rule (conventions dim authored-rule input)

---

## Phase 2 — LLM reviewer spawns

State.md `phase: llm-spawn`.

### 2.1 Dimension grid (10 built-in dimensions + N custom)

| # | Dimension | Spawn rule (always-fire or conditional) |
|---|---|---|
| 1 | bugs | Always fires — no exception |
| 2 | security | Always fires — no exception |
| 3 | architecture | Always fires — no exception |
| 4 | tests | Always fires — no exception |
| 5 | optimizations | Always fires — no exception |
| 6 | conventions | Always fires — no exception. Owns three concern classes: per-file style rubrics (`guidelines-criteria.md`), repo-modal patterns via sibling sampling (`conventions-criteria.md`), and authored-rule citations (`rules-compliance-criteria.md`). When the repo contains authored rule files (see §2.8 rules-file detection), the detected file list is pre-inlined into this dim's prompt and each violation cites the exact rule; when none exist, the dim runs with no authored-rule input (the other two classes unchanged) |
| 7 | regressions | Always fires — no exception. Catches unintended deletes + behavior changes outside stated intent (PR body / spec.md / commit msg). 4 signals: deleted-symbol caller-blast, intent-vs-behavior over-reach, test-coverage delta, parallel-path symmetry (mirror-gap). Criteria: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/regressions-criteria.md` |
| 8 | design | Fires when UI globs match changed files (see §2.5 UI-file detection rule) |
| 9 | pr-metadata | Fires when `pr-ref:` is non-none |
| 10 | spec-compliance | Fires when PLAN CONTEXT is non-none AND (`pr-ref:` non-none OR risk-tier:high) |
| +N | custom:* | Fires per user-authored `.geniro/instructions/review-extra/<slug>.md`, discovered in Phase 1.5 |

**Spawn-batch size.** Phase 2 spawns a reviewer-agent for every row whose trigger fires — trimming the set silently drops a coverage dimension the user expects:

- 7 always-rows (bugs, security, architecture, tests, optimizations, conventions, regressions) fire on every run.
- 3 conditional rows (design, pr-metadata, spec-compliance) fire when their trigger column is satisfied.
- N custom rows fire per the spawn-specs already discovered in Phase 1.5 §1.5.4 — the state.md frontmatter `custom_reviewers` entries whose `paths_matched` is `true` (zero discovery work at Phase 2 entry; that count is N).

Total batch size = always-fire + triggered conditional + custom rows. Trimming this set silently is the documented anti-pattern — see §Anti-rationalization. Post-spawn verification in Phase 4 §4.0 catches drift.

**Refresh L4 instructions** at Phase 2 entry — apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `MODE: refresh`. Compaction since the previous load may have silently dropped the rules.

**Read custom-reviewer specs** from state.md frontmatter `custom_reviewers[]` — populated in Phase 1.5 §1.5.4 via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` discovery. Each entry carries the short scalars (`slug`, `paths_matched`, `model`, `source_path`, `severity_default`, `requires_context`); the criteria body is not persisted, so **Read each entry's `source_path` here** to recover it — that body is the `CRITERIA:` slot of its spawn. Resolve the path cwd-local first, then under `<PRIMARY_ROOT>` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A), matching the discovery glob. A `source_path` that no longer resolves means the user's file moved or was deleted mid-run: drop that one reviewer, note it under `## Caveats` by slug, and fire the rest — spawning a custom dimension with an empty rubric produces findings against no criteria at all. Append one `Agent(subagent_type="reviewer-agent",...)` per surviving spec to the same parallel batch as the built-ins.

### 2.2 Pre-spawn declaration (state.md write before parallel batch)

Before firing the parallel `Agent(...)` batch, the orchestrator computes the declared spawn list and writes it to state.md via `atomic_state_write`:

The example below is one illustrative run — the actual declared set is whatever the §2.1 grid resolves for THIS run (the conditional rows fire per their triggers), never a fixed list copied verbatim:

```yaml
# frontmatter update
spawn_dims_declared: [bugs, security, architecture, tests, optimizations, conventions, regressions, pr-metadata, spec-compliance, custom:manifest-incident-patterns]
spawn_dims_count: 10
```

Plus a `## Tool log` entry:

```
[Phase 2 spawn declaration] dim_list=[bugs, security, architecture, tests, optimizations, conventions, regressions, pr-metadata, spec-compliance, custom:manifest-incident-patterns]; count=10; triggers={pr-ref: <ref-or-none>, plan-context: <path-or-none>, linear-task: <id-or-none>, rule-files: <yes-or-none>, custom-reviewers-discovered: <N>}
```

This is observability for the Phase 4 §4.0 verification gate — declared-vs-actual is one grep away.

### 2.3 Spawn invocation

**Step 2.3.1 — Emit the spawn echo (welded to the batch fire).** Read the `spawn_dims_declared[]` list from state.md (written in §2.2; `<N>` below is `spawn_dims_count` — identical in Standard and Batched payload mode), render dim slugs in plain English (`pr-metadata` -> "PR metadata", `spec-compliance` -> "specification compliance"; the slugs `bugs / security / architecture / tests / optimizations / conventions / regressions` are already plain-English — surface verbatim; custom reviewers render as `custom: <slug>`). Emit this one-line status in the SAME assistant response that fires the parallel `Agent(...)` batch (Step 2.3.2) — not a separate turn — so the user sees what is being spawned exactly when it spawns:

> Spawning <N> reviewers: <comma-separated plain-English list>.

SKILL.md's Definition of done makes a dropped echo detectable.

**Step 2.3.2 — Fire the batch.**

**Deep-mode branch (`deep-mode: true`).** Do NOT fire the single parallel batch below. Instead invoke the deep recall Workflow — 3 angle-diverse passes per declared dimension with in-script union + dedup — per `${CLAUDE_PLUGIN_ROOT}/skills/review/deep-mode-reference.md` §2, then proceed to Phase 3 over the deduped per-dim sets. The `spawn_dims_declared[]` declaration (§2.2) and the §4.0 verification gate still apply to the declared dimension SET (the 3 angles are a multiplier on each declared dim, not a new dim). Fail-safe to the single-pass batch below if the workflow errors (deep-mode-reference §6). Everything below describes the standard single-pass path.

Then fire the parallel batch — single message with N parallel `Agent` tool uses, one per dimension. N = `spawn_dims_count`, in Standard AND Batched payload mode — file grouping structures what each agent reads (triage reference §12), never how many agents spawn. Each spawn:

- `subagent_type: reviewer-agent` (plugin) — apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration-degradation ladder.
- OMIT `model=` argument — reviewer-agent declares `model: inherit`. Custom reviewers that declare an explicit tier in their `.geniro/instructions/review-extra/<slug>.md` frontmatter pass that tier verbatim; otherwise OMIT.
- Pre-inlined context per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`:
  - Diff of changed files — all files in both modes; in Batched payload mode organized into ~5-file groups as a structured reading order (highest-risk groups first and last), per the triage reference §12.
  - Project conventions from L4 (refreshed).
  - Mechanical pre-pass findings (Phase 1.5) as prior-context under `## Mechanical Pre-pass Findings`.
  - PLAN CONTEXT — spec-compliance + regressions dims ONLY (other dims see `PLAN CONTEXT: <plan tag fields only>` per the schema-aware reference).
  - LINEAR CONTEXT — spec-compliance + pr-metadata + architecture + regressions dims ONLY. Omitted for other dims.
  - CUSTOM CONTEXT — a custom reviewer whose `custom_reviewers[]` entry carries a non-null `requires_context` ONLY. The orchestrator pre-fetches the declared external data (which the subagent can't reach over MCP) and injects it into that one reviewer's spawn, fail-open if unavailable — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Hydrating requires-context. Omitted for all built-in dims and for custom reviewers whose `requires_context` is null.
  - PR metadata (pr.body / pr.title / commit messages) — flows via the pr-metadata reviewer's existing context channel; spec-compliance and regressions dims read it through the same channel when fired on a PR ref. No separate `PR CONTEXT:` slot is composed.
  - PRIOR-ROUND FINDINGS (Round-N counter sub-step prior-round-summary, or `none — first review`).
  - PRIOR-ROUND PR BODY — pr-metadata dim ONLY — the `prior-pr-body` captured at re-review detection (per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §1); renders `none — first review` on round 1 or when the prior-run handoff has no `pr-body:`. The pr-metadata reviewer's cross-round drift check (check #11) reads this slot.
  - PEER-PR CONTEXT — architecture + design + bugs + conventions + optimizations + spec-compliance + regressions dims ONLY.
  - `## Existing PR review comments` (from `pr-bot-comments-snapshot:`, per §1.1) — bugs + architecture + regressions + security dims ONLY; omitted when null.
  - `## Existing PR formal reviews` (from `pr-formal-reviews-snapshot:`, per §1.1) — same dims (bugs + architecture + regressions + security); each entry `- <author> (<state>) — <excerpt>`; omitted when null.
  - Authored rule-file list (per §2.8 detection) — conventions dim ONLY; omitted when the repo has no authored rule files.
  - Dimension-specific criteria file path(s) — one absolute path per line, not the body (see **Criteria files** below).
  - Output schema per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`.

After the parallel batch returns, narrate completion before transitioning to §3:

> All <N> reviewers returned. Aggregating findings.

Surface any `status: failed` entries by their plain-English dim name (e.g., "PR metadata reviewer failed — see `## Errors`"), not by raw slug.

**Criteria files** — pass the path, never the body, and do not read them here. Across a full grid these rubrics run to tens of thousands of words; pre-reading them to inline drags every word through the orchestrator's own context as pass-through payload, and `reviewer-agent` holds `Read` and reads whatever paths its prompt names (its §Step 1). Inline a body only where no readable path exists, and say so in the slot. Custom reviewers are the standing exception: their rubric lives in the user's own `.geniro/instructions/review-extra/` file, which a subagent running in a linked worktree may not be able to resolve, so that spawn passes the body read at §2.1 as `CRITERIA:` content.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/bugs-criteria.md` · `security-criteria.md` · `architecture-criteria.md` · `tests-criteria.md` · `optimizations-criteria.md` · `regressions-criteria.md`
- conventions dim — all three paths passed together: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/guidelines-criteria.md` (per-file style rubrics) · `conventions-criteria.md` (repo-modal patterns) · `rules-compliance-criteria.md` (authored-rule citations)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/design-criteria.md` (conditional per §2.5)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/pr-metadata-criteria.md` (conditional)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` (conditional per §2.6)
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

### 2.8 Rules-file detection rule (conventions dim authored-rule input)

Detect at Phase 2 entry, via Glob, whether the repo contains any authored rule file — any of `CLAUDE.md` (root or nested), `.claude/rules/**/*.md`, `.cursor/rules/**/*.mdc`, `.cursorrules`, `.windsurfrules`, `.windsurf/rules/**`, `.github/copilot-instructions.md`, `AGENTS.md`, `.agents.md`. The detected file list feeds the conventions dim's context slot (§2.3) — pre-inlined into that dim's spawn prompt, where the reviewer parses each file's path-scopes (`.mdc` `globs:`, `.claude/rules` `paths:`) and checks the diff against each in-scope rule per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/rules-compliance-criteria.md`, citing the exact rule. When none exist, the conventions dim simply has no authored-rule input — its style-rubric and modal-pattern classes run unchanged.

---
