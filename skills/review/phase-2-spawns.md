# /geniro:review — Phase 2

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md`. Read on entry to Phase 2.

**Tool surface (Phases 2-4).** Spawn `reviewer-agent`, `finding-verifier-agent`, and — when `brief:` is not `off` — the `general-purpose` brief spawn (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-brief.md` §Spawn template). Read-only shell for the §2.7 build check; `atomic_state_write`, which also materializes the brief's file medium; scratch-directory writes for the review packet (§2.3) and, with native `Artifact` calls, the brief's artifact medium. Web search / fetch only for `finding-verification.md` §2.5's external-evidence pre-run (Phase 4.2, outside-repo claims, tiers 2-3, before the verifier spawn). Questions: Phase 4's declared-vs-actual gate, and the brief's medium sub-question on a `brief: pending` resume (the opt-in itself belongs to Phase 1 §13). Nothing is written outside the run's scratch directory and no other mutating shell runs — the review authors no code and edits no production source; the brief is its own documented deliverable, never a change to the reviewed diff.

## Contents

- Phase 2 — LLM reviewer spawns
  - 2.1 Dimension grid (built-in dimensions + N custom)
  - 2.2 Pre-spawn declaration (state.md write before parallel batch)
  - 2.3 Spawn invocation (2.3.1 spawn echo · 2.3.2 fire the batch + the co-fired optional brief, drained and materialized at the batch's return · the review packet each prompt names · criteria files)
  - 2.4 Spawn ladder and model tier (canonical for every spawn site in this skill)
  - 2.5 UI-file detection rule (design dim trigger)
  - 2.6 Spec-compliance detection rule
  - 2.7 Build verification (parallel with reviewers)
  - 2.8 Rules-file detection rule (conventions dim authored-rule input)
  - 2.9 Optimizations detection rule (docs/lockfile-only skip)

---

## Phase 2 — LLM reviewer spawns

State.md `phase: llm-spawn`.

### 2.1 Dimension grid (built-in dimensions + N custom)

| # | Dimension | Spawn rule (always-fire or conditional) |
|---|---|---|
| 1 | bugs | Always-fire set, every size tier (scaled below) |
| 2 | security | Always-fire set, every size tier (scaled below) |
| 3 | architecture | Always-fire set at or over the size boundary or on `risk-tier:high` (scaled below) |
| 4 | tests | Always-fire set, every size tier (scaled below) |
| 5 | optimizations | Fires when any changed file has an executable surface. Skipped only when EVERY changed file is documentation or a generated lockfile (see §2.9) — a diff with no executable surface has no hot path for its rubric to bind on. Own trigger, independent of the size-tier scaling below |
| 6 | conventions | Always-fire set, every size tier (scaled below). Owns three concern classes: per-file style rubrics (`guidelines-criteria.md`), repo-modal patterns via sibling sampling (`conventions-criteria.md`), and authored-rule citations (`rules-compliance-criteria.md`). When the repo contains authored rule files (see §2.8 rules-file detection), the detected file list is pre-inlined into this dim's prompt and each violation cites the exact rule; when none exist, the dim runs with no authored-rule input (the other two classes unchanged) |
| 7 | regressions | Always-fire set at or over the size boundary or on `risk-tier:high` (scaled below). Catches unintended deletes + behavior changes outside stated intent (PR body / spec.md / commit msg). 4 signals: deleted-symbol caller-blast, intent-vs-behavior over-reach, test-coverage delta, parallel-path symmetry (mirror-gap). Criteria: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/regressions-criteria.md` |
| 8 | intent | Always-fire set, every size tier (scaled below) — a false premise is no smaller in a small diff. Checks why the change was made: each fact it relies on is true in the code, and it solves the stated problem (root cause, full scope, right for existing consumers). Criteria: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/intent-criteria.md` |
| 9 | design | Fires when UI globs match changed files (see §2.5 UI-file detection rule). Own trigger, independent of the size-tier scaling below |
| 10 | pr-metadata | Fires when `pr-ref:` is non-none. Own trigger, independent of the size-tier scaling below |
| 11 | spec-compliance | Fires whenever PLAN CONTEXT is non-none, at any risk tier, PR or not (§2.6). Own trigger, independent of the size-tier scaling below |
| +N | custom:* | Fires per user-authored `.geniro/instructions/review-extra/<slug>.md`, discovered in Phase 1.5 |

**The always-fire set scales by diff size and risk tier.** bugs, security, architecture, tests, conventions, and regressions above are not unconditional — the grid narrows on a small diff and always expands back to the full set on `risk-tier:high`; `intent` fires in every row. Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-grid-scaling.md`'s table to resolve the scaled set for THIS run. `/geniro:review` has no four-level size tier — its only size signal is the §12 boundary (the Standard vs Batched payload threshold) — so resolve the lookup against that boundary plus the `risk-tier` from §9 (both resolved by Phase 2 entry). optimizations, design, pr-metadata, and spec-compliance are unaffected — they keep their own trigger regardless of size tier.

**Spawn-batch size.** Total batch = the scaled always-fire set + the conditional rows whose own trigger fires + N custom rows (the state.md `custom_reviewers` entries whose `paths_matched` is `true` — zero discovery work at Phase 2 entry). The resolved set is recorded in `spawn_dims_declared[]` (§2.2) and announced in the spawn echo (§2.3.1) before the batch fires, so a narrowed grid is a decision the user sees; Phase 4 §4.0 catches drift.

**Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: review`, `LOAD_TIER: pipeline`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract.

**Read custom-reviewer specs** from state.md frontmatter `custom_reviewers[]` — populated in Phase 1.5 §1.5.4 via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` discovery. Each entry carries the short scalars (`slug`, `paths_matched`, `model`, `source_path`, `severity_default`, `requires_context`); the criteria body is not persisted, so **Read each entry's `source_path` here** to recover it — that body is the `CRITERIA:` slot of its spawn. Resolve the path cwd-local first, then under `<PRIMARY_ROOT>` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A), matching the discovery glob. A `source_path` that no longer resolves means the user's file moved or was deleted mid-run: drop that one reviewer, note it under `## Caveats` by slug, and fire the rest — spawning a custom dimension with an empty rubric produces findings against no criteria at all. Append one `Agent(subagent_type="reviewer-agent",...)` per surviving spec to the same parallel batch as the built-ins.

**Gather the entry work in one response.** The instruction refresh, `review-grid-scaling.md`, each custom reviewer's `source_path`, and the §2.5 / §2.8 / §2.9 detections over the changed-file list depend on none of each other's results — issue the reads in parallel and chain the detections into one shell call, rather than spending a turn on each.

### 2.2 Pre-spawn declaration (state.md write before parallel batch)

Before firing the parallel `Agent(...)` batch, the orchestrator computes the declared spawn list and writes it to state.md via `atomic_state_write`:

The example is illustrative — the declared set is whatever the §2.1 grid resolves for THIS run:

```yaml
# frontmatter update
spawn_dims_declared: [bugs, security, architecture, tests, optimizations, conventions, regressions, intent, pr-metadata, spec-compliance, custom:manifest-incident-patterns]
spawn_dims_count: 11
```

Plus a `## Tool log` entry:

```
[Phase 2 spawn declaration] dim_list=[bugs, security, architecture, tests, optimizations, conventions, regressions, intent, pr-metadata, spec-compliance, custom:manifest-incident-patterns]; count=11; triggers={pr-ref: <ref-or-none>, plan-context: <path-or-none>, linear-task: <id-or-none>, rule-files: <yes-or-none>, optimizations: <fired-or-skipped-docs-only>, custom-reviewers-discovered: <N>}
```

This is observability for the Phase 4 §4.0 verification gate — declared-vs-actual is one grep away.

### 2.3 Spawn invocation

**Step 2.3.1 — Emit the spawn echo (welded to the batch fire).** Read the `spawn_dims_declared[]` list from state.md (written in §2.2; `<N>` below is `spawn_dims_count` — identical in Standard and Batched payload mode), render dim slugs in plain English (`intent` -> "intent (why the change was made)", `pr-metadata` -> "PR metadata", `spec-compliance` -> "specification compliance"; the slugs `bugs / security / architecture / tests / optimizations / conventions / regressions` are already plain-English — surface verbatim; custom reviewers render as `custom: <slug>`). Emit this one-line status in the SAME assistant response that fires the parallel `Agent(...)` batch (Step 2.3.2) — not a separate turn — so the user sees what is being spawned exactly when it spawns:

> Spawning <N> reviewers: <comma-separated plain-English list>.

**Step 2.3.2 — Fire the batch.**

Fire the parallel batch — single message with N parallel spawns, one per dimension, plus an `atomic_state_append_section` append of `## Tool log` entry `[Phase 2 spawn batch fired] fired=<count of Agent reviewer spawns issued>`, welded like the §2.3.1 spawn echo into that SAME response so the fired count can never be dropped independently of the batch it records. N = `spawn_dims_count`, in Standard AND Batched payload mode — file grouping structures what each agent reads (triage reference §12), never how many agents spawn.

**Brief co-fire (optional) — in this SAME response, alongside the reviewers.** When Phase 1 §13 resolved `brief:` to `artifact` or `file`, one more spawn rides in the batch: `subagent_type="general-purpose"`, foreground, **session** class, call and prompt slots per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-brief.md` §Spawn template. The §2.3.1 echo then carries one trailing plain-English clause ("…plus the orientation page you asked for, landing when they do") and its count and dimension list stay as specified; `brief: off` spawns nothing and says nothing. A `brief:` still `pending` here is a compaction-resume straight into Phase 2: the accept is already given, so co-fire and ask only the medium in this same response; never re-ask the accept, never hold the spawn for the medium. Why the spawn belongs in this response: `review-brief.md` §Caller contract.

**The review packet — the batch's shared context, written once.** A spawn in the batch starts only once its own prompt has been generated, so context repeated in every prompt holds the last reviewer back by the whole batch's worth of text. Write what the reviewers share once, as files, in the §2.2 declaration's response, and have each prompt name those files:

- **Where.** A fresh directory in the run's scratch space — the host's session scratchpad when it has one, else a `mktemp -d` directory — outside the repo, where the files would otherwise appear as untracked changes in the tree under review. A resume that cannot find the packet writes it again.
- **What it holds.** Every slot below that two or more reviewers receive, written once with its fence applied at write time. A slot only one spawn receives (`AUTHORED RULE FILES`, `PRIOR-ROUND PR BODY`, a custom reviewer's `CRITERIA` and `CUSTOM CONTEXT`) stays inline in that spawn's prompt, and so does a slot whose value is a sentinel (`none declared`, `none — first review`) — one line either way.
- **Files.** `common.md` carries what every reviewer receives, in this order: `PROJECT SEARCH POLICY` verbatim, first so it lands with the task; the change under review (branch, range, size, anything triaged out); the project conventions; the mechanical pre-pass findings; `PRIOR-ROUND FINDINGS`; `USER STEERING`; the constraints, acceptance criteria, and output-format pin every reviewer shares; and the path of `diff.md`, which holds the diff. Each dimension-scoped slot that several reviewers share gets a file of its own named for the slot (`plan.md`, `tracker.md`, `pr.md`, `peer-prs.md`, `pr-reviews.md`), and a prompt names only the files its dimension's routing below gives it — one slot per file is what keeps the routing intact, so tracker text never reaches the bugs reviewer.
- **The prompt keeps only what is its own:** the dimension and its task-scope line; the `WORKTREE:` slot with its anchor line (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`), which stays in every prompt because a subagent's starting directory depends on the host; `REVIEW PACKET:` with the absolute paths of `common.md` and this dimension's slot files, and the instruction to read every one in full before starting, since their sections are part of this prompt and the diff is reachable only through them; one line binding the search policy — `common.md`'s first section, governing every lookup rather than only the first, with the exact invocation when it names a tool, and its shell form when it has one; the criteria paths; and the inline slots above. The diff living only in the packet is what makes the read unskippable, and the reviewer's `packet=` load-report item is what makes a skipped read visible.

Each reviewer spawn is `geniro:reviewer-agent`, ladder and model per §2.4, with pre-inlined context per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`, delivered through the review packet or inline as it directs. Content from outside this orchestrator's own authorship is untrusted and gets wrapped, where it enters the packet or prompt, in `---BEGIN UNTRUSTED <LABEL>---` / `---END UNTRUSTED <LABEL>---` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/untrusted-content-defense.md` §Untrusted-content fence). **Pass-through** marks a slot already fenced at its composition site; **trusted** marks one that stays unfenced — this orchestrator's own authorship, or `USER STEERING:`, the user's own words.

| Slot | Receiving dimensions | Fence |
|---|---|---|
| `PROJECT SEARCH POLICY:` — the `global.md` search rules verbatim, or `none declared`; governs every lookup, not just the first | all | trusted |
| Diff, in the packet's `diff.md`, all files in both modes; Batched payload mode orders groups highest-risk first and last (group size per triage reference §12) under a table of each group's files and line range | all | `DIFF`, one fence around the whole diff |
| Project conventions from L4 (refreshed) | all | trusted |
| Mechanical pre-pass findings, under `## Mechanical Pre-pass Findings` | all | `PRE-PASS` |
| `PRIOR-ROUND FINDINGS:` (or `none — first review`) | all | `PRIOR-ROUND` when non-`none` |
| `USER STEERING:` — this round's free-text steering (triage reference §7 step 5), or `none` | all, built-in and custom | trusted |
| `PLAN CONTEXT:` — every other dimension sees `PLAN CONTEXT: <plan tag fields only>` | spec-compliance, regressions, intent | pass-through (`PLAN`, `plan-context.md`) |
| `LINEAR CONTEXT:` — tracker text biases a per-file rubric, so no other dimension sees it | spec-compliance, pr-metadata, architecture, regressions, intent | pass-through (`TRACKER`, triage reference §3.5.2) |
| PR metadata — `pr.body` / `pr.title` / `pr.labels[]`, the commit messages (bounded; `phase-1-pr-reference.md` §3 on a PR run, triage reference §2 otherwise; commit messages alone with no PR ref), and the scalars `pr.isDraft` / `pr.author.login`, which the draft / bot / generated-PR skip rules key on — omit them and a Dependabot PR draws a full prose review. No separate `PR CONTEXT:` slot | pr-metadata, spec-compliance, regressions, architecture, intent | `PR-BODY` on the free-text fields, labels included (a label is attacker-settable text); scalars unfenced |
| `PRIOR-ROUND PR BODY:` — `prior-pr-body` (triage reference §7 step 3), or `none — first review` | pr-metadata | `PR-BODY` when non-`none` |
| `PEER-PR CONTEXT:` | architecture, design, bugs, conventions, optimizations, spec-compliance, regressions | `PEER-PR` when non-`none` |
| `## Existing PR review comments` and `## Existing PR formal reviews` (the `phase-1-pr-reference.md` §1.1 snapshots; each omitted when null) | bugs, architecture, regressions, security | pass-through (`PR-COMMENTS`, `FORMAL-REVIEWS`) |
| `CUSTOM CONTEXT:` — hydrated once, centrally (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Hydrating requires-context) | a custom reviewer with a non-null `requires_context` | pass-through (`CUSTOM-CONTEXT`) |
| `AUTHORED RULE FILES:` — the §2.8 result, one path per line, or `none found`; always composed. On `none found` the reviewer runs its own search (`rules-compliance-criteria.md` §1) | conventions | trusted |
| Criteria — one absolute path per line, not the body (**Criteria files** below) | per dimension | trusted |
| Output schema — name `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format; the agent carries it, so a copy only drifts | all | trusted |

After the parallel batch returns, read each reviewer's report for its `Context loaded:` line per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` §Reading the load report back — checked per agent, since one reviewer reporting a dropped load while its siblings report clean is a spawn defect, not a project without rules. Act on an `unreadable` or missing line (re-spawn or name the gap) rather than merely noting it. A `packet=` item reading anything but `read` means that reviewer worked without the shared context, diff included — re-spawn it, correcting the path first when it reads `unreadable`. The conventions reviewer's line carries one extra item, `authored-rules=`, and it is the only record that the repo's own rule files were actually read: `absent` means the reviewer's own search also came back empty, so `absent` when §2.8 detected files means the listed paths never reached it, and `unreadable` means a path this orchestrator passed does not resolve — both are this spawn site's defect to fix and re-spawn, not the reviewer's.

The Phase 4 §4.0b completeness check reads `spawn_dims_count` against the `fired=` count on the `[Phase 2 spawn batch fired]` entry written at batch-fire time (Step 2.3.2 above) — the only durable record of the actual; §2.2 persists only the declaration, so without it a compaction-resume into `phase: stratify` cannot evaluate the over-fire / under-fire branch.

**Drain the batch in one turn — do not narrate its arrivals.** Wait for every reviewer and report once, when the last one is in. A progress turn ("7 of 11 back, waiting on the remaining four") re-reads this orchestrator's whole accumulated context — diff, triage, every spawn prompt — to say what the completion line below says anyway. The §2.7 build verification is the one thing worth a turn here, because it does not depend on the batch (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md`).

Narrate completion before transitioning to Phase 3:

> All <N> reviewers returned. Aggregating findings.

Surface any `status: failed` entries by their plain-English dim name (e.g., "PR metadata reviewer failed — see `## Errors`"), not by raw slug.

**Criteria files** — pass the path, never the body, and do not read them here. Pre-reading a full grid's rubrics (tens of thousands of words) to inline them drags every word through the orchestrator's context as pass-through payload, and `reviewer-agent` reads whatever paths its prompt names (its §Step 1). Inline a body only where no readable path exists, and say so in the slot. Custom reviewers are the standing exception: their rubric lives in the user's own `.geniro/instructions/review-extra/` file, which a subagent running in a linked worktree may not be able to resolve, so that spawn passes the body read at §2.1 as `CRITERIA:` content.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/bugs-criteria.md` · `security-criteria.md` · `architecture-criteria.md` · `tests-criteria.md` · `regressions-criteria.md` · `intent-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/optimizations-criteria.md` (conditional per §2.9)
- conventions dim — all three paths passed together: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/guidelines-criteria.md` (per-file style rubrics) · `conventions-criteria.md` (repo-modal patterns) · `rules-compliance-criteria.md` (authored-rule citations)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/design-criteria.md` (conditional per §2.5)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/pr-metadata-criteria.md` (conditional)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` (conditional per §2.6)
- Custom reviewer criteria from spawn-specs returned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` (capped there, per project)

**Brief materialization — in the completion response, ahead of Phase 3.** Materialize the drained brief per `review-brief.md` §Medium selection and surface where it landed once, first in the response, in plain language (a link or a path, never an internal phase name). The end of Phase 4 is the last moment the write and publish are possible, and a later one reaches a reader who already has the findings. The brief never enters any spawn prompt, a reviewer's or a later verifier's (`review-brief.md` §Isolation invariant).

### 2.4 Spawn ladder and model tier

The ladder, session default, and `--subagent-model` pin are in SKILL.md §Subagent spawning; tier values and the inexpressible-tier fallback in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Cost classes and §`--subagent-model`; the registration ladder and empty-result fallback in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`, read when SKILL.md says so. This skill's **session** spawns are `reviewer-agent` (every built-in and custom dimension), `finding-verifier-agent` (Phase 4.2), and the `general-purpose` brief spawn when `brief:` is not `off`; the Phase 1 `codebase-research-agent` lookups (SKILL.md S1) are **light (smallest)**. A custom reviewer declaring an explicit `model:` other than `auto` or `inherit` in its `.geniro/instructions/review-extra/<slug>.md` frontmatter keeps that value verbatim; where the host cannot spell it, omit `model` and announce once that it is not applied. A `--subagent-model` tier beats that declared `model:` at every session spawn and only caps the light lookups.

### 2.5 UI-file detection rule (design dim trigger)

A file is a UI file per the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §UI-file detection rule. Design dimension skipped when no changed file matches.

### 2.6 Spec-compliance detection rule

Fires whenever PLAN CONTEXT is non-`none` (a resolved spec), at any risk tier, with or without a PR — a review that never compared the diff to its spec reads as clean on exactly the spec-shaped defects. With `pr-ref: none` there is no PR body or metadata; the criteria file's opening adapts the evidence to the spec, the diff, and the range's commit messages. Findings carry `File: SPEC-COMPLIANCE` sentinel — Phase 6 Post drill routes them to top-level review `body` under `## Spec Compliance` (no `path:lines` anchor, so they do NOT inline-comment).

### 2.7 Build verification (parallel with reviewers)

Run the project's validation suite in parallel with reviewer agents:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Build Check" "<validation_cmd>"
```

Feed pass/fail into the Phase 3 §3.3 KEEP/FILTER judgment. Failing build is automatically a CRITICAL finding — tag `[NEW]` if the base branch build passes, `[PRE-EXISTING]` if already broken.

### 2.8 Rules-file detection rule (conventions dim authored-rule input)

Detect at Phase 2 entry whether the repo contains any authored rule file — any of `CLAUDE.md` (root or nested), `.claude/rules/**/*.md`, `.cursor/rules/**/*.mdc`, `.cursorrules`, `.windsurfrules`, `.windsurf/rules/**`, `.github/copilot-instructions.md`, `AGENTS.md`, `.agents.md`, `CONTRIBUTING.md`, `CODING_STANDARDS.md` (the last two at the repo root or under `docs/`). The detected file list feeds the conventions dim's context slot (§2.3) — pre-inlined into that dim's spawn prompt, where the reviewer parses each file's path-scopes (`.mdc` `globs:`, `.claude/rules` `paths:`) and checks the diff against each in-scope rule per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/rules-compliance-criteria.md`, citing the exact rule. When none exist, compose the slot anyway carrying `none found` — the reviewer runs its own search, and the dim's style-rubric and modal-pattern classes run unchanged.

### 2.9 Optimizations detection rule (docs/lockfile-only skip)

The optimizations dimension reviews hot-path cost on the changed lines, so it skips only a diff with no executable surface: when EVERY changed file is documentation (`*.md` / `*.rst` / `*.txt`, or under a `docs/` tree) or a generated lockfile (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `poetry.lock`, `go.sum`, and kin), there is nothing for its rubric to bind on. Any other changed file — source, tests, configuration, templates, scripts — keeps the dimension in the batch; configuration is deliberately in scope because pool sizes, cache TTLs, and worker counts are performance surface. The check is mechanical over the changed-file list, evaluated fresh every run — never a judgment call about whether the diff "looks perf-relevant". Record the outcome in the §2.2 triggers entry (`optimizations: fired | skipped-docs-only`); the declared list carries the result, so the §4.0 declared-vs-actual gate audits the skip like any other conditional dimension.

---
