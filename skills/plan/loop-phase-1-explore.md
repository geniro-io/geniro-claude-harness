# Phase 1 — Explore

A phase file of the `/geniro:plan` loop. The spine — HARD-GATE, gate presentation contract, echo contract, phase order, terminal states, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`.

## Contents

- 1.1 Memory layer loading
- 1.1b Branch freshness
- 1.2 Effort-tier-scaled research spawns
- 1.3 Echo contract (in the spine)
- 1.4 Workflow refs fetch (tracker linkage)
- 1.5 Transition to Phase 2

State.md `phase: explore` during this phase.

### 1.1 Memory layer loading

At Phase 1 entry, load **L4 + L3 + L2** (full tier, NOT rules-only):

- **Custom instructions:** apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: plan`, `LOAD_TIER: pipeline`, `MODE: refresh`. Scope = `plan` + `global` + `code-style`.
- **Project snapshot:** `source "${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh" && load_semantic`. Default top-2 (`_project.md` + `_CODEBASE_MAP.md`). Fingerprint drift check fires; surface drift to user.
- **Past learnings:** route the read per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override" (a declared `## Memory Backend` block redirects this to its read tool; the file is empty under `mode: replace`), else `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --tag <inferred> --scope <topic-area> --limit 5`. Skipped if topic is too generic to infer tags.
- **Cross-layer resolution:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol if L4/L3/L2 disagree.

### 1.1b Branch freshness

On a fresh run (skip on compaction-resume), apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`. /geniro:plan does not create branches, but when the current branch is behind the latest default branch, the freshness step grounds the spec in fresh code rather than a stale tree. When a `freshness:merge` / `freshness:rebase` / `freshness:skip` modifier was passed in `$ARGUMENTS` (§0.1), apply that strategy directly without firing the offer AUQ — `freshness:skip` means do not update; `freshness:merge` / `freshness:rebase` apply that strategy on a clean fast-forward, while a real conflict still surfaces interactively per `branch-freshness.md`. When no `freshness:` modifier is present, offer the update before research spawns. This covers BOTH cases the helper handles: a feature branch behind the default (offer merge/rebase), AND sitting on the default branch itself while its remote moved ahead (offer pull) — do not skip the gate just because HEAD is on the default branch. Skipped silently only when the branch already contains everything on the default.

### 1.2 Effort-tier-scaled research spawns

Detect effort tier from $ARGUMENTS shape using `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`:

| Tier | Spawns |
|---|---|
| Trivial (typo / config tweak / mechanical rename — no logic change) | 1 agent OR 0 if obviously scope-bound |
| Small (localized, single-concern change) | 1-2 agents (existing-impl; integration-surface only if it spans a boundary) |
| Medium (a feature, or a change that touches a contract / boundary) | 2 agents (existing-impl + integration-surface) |
| Big (a hard escalation signal is present, or dimension score 7+ per effort-scaling.md) | 3-4 agents (subsystem-A + subsystem-B + cross-cutting + conventions) |

Spawn `codebase-research-agent` for each primary Phase 1 facet per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research. Facet-specific slot values: `RESEARCH_QUESTION` = the facet's research goal; `DELIVERABLE_SHAPE` = `"table of [{file, lines, observation}] verified findings"`; `SCOPE_HINT` = the facet's path globs; `OUTPUT_PATH` = `<task-dir>/.research-<facet>.md`; `THOROUGHNESS` = `medium` (default) or `very thorough` for Big-tier subsystem facets.

When `$ARGUMENTS` carries a tracker reference, complete §1.4's tracker fetch + chain assembly **before** issuing these spawns — §1.4 produces the "TASK CHAIN CONTEXT" block these spawns consume, so it must run first or the block does not exist yet. Then issue all spawns `run_in_background: true` in a single assistant response per the parallel-spawn rule (Shape A of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md` — backgrounding frees the orchestrator to fire code-independent grill questions per §3.1 during the explore wait; the drain is §1.5 synthesis), each additionally receiving the "TASK CHAIN CONTEXT" block (when present) as added context so the spec is grounded in where this task sits in the larger chain of work. Per-spawn output schema: `[{file, lines, observation}]`; cap ~4000 chars (truncate with marker) — this section is that cap's single home, cited rather than restated at the other `/geniro:plan` sites.

### 1.3 Echo contract

Canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §Echo contract — it binds Phases 1, 4, and 6, so it lives in the spine.

### 1.4 Workflow refs fetch (tracker linkage)

If `$ARGUMENTS` contains a tracker reference (Linear URL/ID, Jira key, GitHub issue URL, Asana task URL), fetch via the matching MCP and persist to state.md `## Workflow Refs` body section. This block is the source-of-truth for Phase 6 frontmatter assembly.

**Detection:** existing workflow-plumbing already detects tracker references at Phase 1 entry. Workflow files (`.geniro/workflow/<kind>.md`) live in the primary worktree per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (Mode A) — try `./.geniro/workflow/<kind>.md` (cwd-local; uncommitted local edits win) first, on file-not-found retry against `<PRIMARY_ROOT>/.geniro/workflow/<kind>.md`. Each file defines per-tracker patterns. When a match resolves to `kind=<linear|jira|github-issues|asana>` and `issue_id=<id>`:

1. Fetch via the matching MCP (`mcp__linear__get_issue` for Linear, etc.). If MCP unregistered, log a `## Errors` entry and continue without persistence — graceful degrade per existing pattern.
2. Append to state.md `## Workflow Refs` via `atomic_state_write`:

```yaml
## Workflow Refs
- kind: linear
  issue_id: CI-303
  url: https://linear.app/.../CI-303/...
  fetched_at: 2026-05-26T10:42:13Z
  title: "..."
  suggested_branch: ci-303-...
  status: Todo
  parent_ref:
    kind: linear
    issue_id: CI-300
    url: ...
    title: "Case Radar performance epic"    # chain enrichment (§1.4 step 4)
    status: In Progress                      # chain enrichment
    scope: "Cut backfill latency below 5 min."  # chain enrichment — bounds per workflow-refs-schema.md
  siblings:                                  # chain enrichment — bounds per workflow-refs-schema.md, omit when none
  - issue_id: CI-301
    title: "..."
    status: Done
  chain_fetched_at: 2026-05-26T10:42:15Z     # chain enrichment, independent staleness from fetched_at
```

3. The fetched payload feeds Phase 1 research-agent prompts (existing behavior) AND becomes the canonical source for Phase 6 frontmatter copy. Skipped when `$ARGUMENTS` carries no tracker reference — pure inline-task /geniro:plan emits a spec.md without `workflow_refs[]`.

4. **Assemble the related-task chain.** After the current issue resolves, apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md` (MODE: plan) with the fetched ref(s) + the task-dir to gather the chain of related work — the parent epic (title / status / scope), the sibling sub-tasks (each with its status), and neighboring milestone files on disk — and to derive the done-before / where-we-are / what's-next narrative. The helper also cross-checks each load-bearing chain fact against the project's declared `## Data Sources` (read-only, fail-open) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`, marking any status no source can confirm as unconfirmed and surfacing conflicts rather than assuming a single fetch. Merge the helper's `ENRICHED_REFS` (the tracker half: `parent_ref.{title,status,scope}` + `siblings[]` + `chain_fetched_at`) into the state.md `## Workflow Refs` block via `atomic_state_write`. Stay read-only on the tracker — never mutate the parent or siblings. Fail-open: on MCP unregistered/timeout, skip enrichment, log a `## Errors` entry, and continue. Run this assembly before the §1.2 research spawns and hold the assembled "TASK CHAIN CONTEXT" block in context for their prompts; the milestone half is derived fresh each run and is never persisted.

### 1.5 Transition to Phase 2

**Drain the backgrounded explore agents first.** Before synthesizing, confirm every §1.2 explore spawn returned — Read each `<task-dir>/.research-<facet>.md`, or resume the agent by ID if an output is missing. This is the drain that closes the §1.2 overlap (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md`): synthesis consumes the research, so it cannot start against an in-flight agent. Read each report for its `Context loaded:` line and act on an `unreadable` or missing one, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The load report — an agent that skipped its project-rules load is otherwise indistinguishable from one that ran it.

Model synthesizes findings into a brief inline summary held in context (no separate artifact). The summary feeds Phase 2 UI trigger detection, Phase 3 question generation, and Phase 5 section authoring.

**Transition.** Resolve the Trivial skip below before evaluating the §2.1 UI trigger, then write the `phase:` of the phase actually being entered — Trivial skip → Phase 4; UI trigger matches → Phase 2; neither → Phase 3 (each phase's enum is in the spine §Phase files table). Leaving `phase:` on a phase this step just decided to skip sends a compaction-resume back into it.

**Visual plan artifact.** When `artifact_mode: true`, Read `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-artifact-call-sites.md` now — it holds the first publish and every later call site. When `artifact_mode` is unset, skip that file and treat every **Artifact** line in the phase files as a no-op.

**Skip to Phase 4 if Trivial:** when effort tier is Trivial AND research returned 0-1 findings AND topic is a narrow text-edit, Phases 2 + 3 are skipped. Write a one-line note to state.md `## Open Questions`: "Phases 2-3 skipped — trivial task, no ambiguity surfaced".
