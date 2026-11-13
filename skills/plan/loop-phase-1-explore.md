# Phase 1 — Explore

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

## Contents

- 1.1 Load project snapshot and past learnings
- 1.1b Branch freshness
- 1.2 Effort-tier-scaled research spawns
- 1.3 Echo contract (in the spine)
- 1.4 Workflow refs fetch (tracker linkage)
- 1.5 Transition to Phase 2 (drain · synthesis · prior-work scan · custom post-explore steps · transition)

State.md `phase: explore` during this phase.

### 1.1 Load project snapshot and past learnings

At Phase 1 entry, load **L4 + L3 + L2** (full tier, NOT rules-only):

- **Custom instructions:** apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: plan`, `LOAD_TIER: pipeline`, `MODE: refresh`.
- **Project snapshot:** `source "${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh" && load_semantic`. Surface any fingerprint drift to the user.
- **Past learnings:** route the read per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override": `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --tag <inferred> --scope <topic-area> --limit 5`. Skipped if topic is too generic to infer tags. Then always run a second file query, merging any backend matches and not skipped on a generic topic, for approaches earlier runs declined — `--type user_rejected_suggestion --tag approach_choice --limit 10`, with no `--tag <inferred>` or `--scope` (a rejection is tagged by category only, and its topic string rarely repeats). Keep entries whose suggestion concerns the current topic and display each as "User previously rejected <suggestion> on <ts>" so Phase 4's approach AUQ (§4.3/§4.4) can re-rank or omit it.
- **Cross-layer resolution:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol if L4/L3/L2 disagree.

### 1.1b Branch freshness

On a fresh run (skip on compaction-resume), before research spawns apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`, so the spec is grounded in fresh code; skip silently only when `BEHIND == 0`.

The update is an offer, never auto-run — an unasked merge moves the user's HEAD. Fire that file's update-default or catch-up question verbatim when behind; before any action that moves HEAD, run `git status --porcelain`, and any output chains its unsaved-work question first. Append the pick and resolved `behind` count to `approvals[]` (category `branch_freshness`) via `atomic_state_append_list_item`.

A `freshness:merge` / `freshness:rebase` / `freshness:skip` modifier in `$ARGUMENTS` (§0.1) answers the question: apply that strategy directly (`freshness:skip` means do not update), with the same dirty-tree check and `approvals[]` entry; a real conflict still surfaces interactively per `branch-freshness.md`.

### 1.2 Effort-tier-scaled research spawns

Detect effort tier from $ARGUMENTS shape using `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`:

| Tier | Spawns |
|---|---|
| Trivial (typo / config tweak / mechanical rename — no logic change) | 1 agent OR 0 if obviously scope-bound |
| Small (localized, single-concern change) | 1-2 agents (existing-impl; integration-surface only if it spans a boundary) |
| Medium (a feature, or a change that touches a contract / boundary) | 2 agents (existing-impl + integration-surface) |
| Big (a hard escalation signal is present, or the Big dimension-score band per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`) | 3-4 agents (subsystem-A + subsystem-B + cross-cutting + conventions) |

Spawn `codebase-research-agent` for each primary Phase 1 facet per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research. Facet-specific slot values: `RESEARCH_QUESTION` = the facet's research goal; `DELIVERABLE_SHAPE` = `"table of [{file, lines, observation}] verified findings"`; `SCOPE_HINT` = the facet's path globs; `OUTPUT_PATH` = `<task-dir>/.research-<facet>.md`; `THOROUGHNESS` = `medium` (default) or `very thorough` for Big-tier subsystem facets.

When `$ARGUMENTS` carries a tracker reference, finish §1.4 first — it produces the "TASK CHAIN CONTEXT" block these spawns receive as added context. Then issue all spawns `run_in_background: true` in a single assistant response (Shape A of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md` — the orchestrator fires code-independent grill questions per §3.1 during the wait; the drain is §1.5). Per-spawn output schema: `[{file, lines, observation}]`; cap ~4000 chars (truncate with marker) — this section is that cap's single home, cited rather than restated at the other `/geniro:plan` sites.

### 1.3 Echo contract

Canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §Echo contract — it binds Phases 1, 3, 4, and 6, so it lives in the spine.

### 1.4 Workflow refs fetch (tracker linkage)

Runs only when `$ARGUMENTS` carries a tracker reference (Linear URL/ID, Jira key, GitHub issue URL, Asana task URL), and before the §1.2 spawns. Without one the spec has no `workflow_refs[]`.

1. **Fetch.** Each tracker's patterns live in `.geniro/workflow/<kind>.md` — `./` first, then `<PRIMARY_ROOT>/` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A). Fetch through the MCP tool that file names for `<kind>`; a project may register any client under any tool name.
2. **Persist.** Append the ref to state.md `## Workflow Refs` via `atomic_state_append_section --create`, in the `workflow_refs[]` entry shape of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` §Frontmatter. The fetched payload feeds the research-agent prompts, and Phase 6 copies this block into the spec frontmatter.
3. **Assemble the chain.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md` (MODE: plan) to the fetched ref(s) and the task-dir; merge its `ENRICHED_REFS` into the `## Workflow Refs` block via `atomic_state_edit`; hold the "TASK CHAIN CONTEXT" block fenced as `TASK-CHAIN` (that file's §5; `${CLAUDE_PLUGIN_ROOT}/skills/_shared/untrusted-content-defense.md` §Untrusted-content fence) for the spawn prompts. The milestone half is derived fresh each run and never persisted.

The tracker stays read-only — never mutate the parent or siblings — and every call is fail-open: an unregistered MCP or a timeout logs a `## Errors` entry and the run continues without that step.

### 1.5 Transition to Phase 2

**Drain the backgrounded explore agents first.** Before synthesizing, confirm every §1.2 explore spawn returned — Read each `<task-dir>/.research-<facet>.md`, or resume the agent by ID if an output is missing. Read each report for its `Context loaded:` line and act on an `unreadable` or missing one, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The load report.

Model synthesizes findings into a brief inline summary held in context (no separate artifact). The summary feeds Phase 2 UI trigger detection, Phase 3 question generation, and Phase 5 section authoring.

**Prior-work scan.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/prior-work-scan.md` against the topic this run is about to plan — already named by `$ARGUMENTS` or the resolved tracker ref, so it falls inside the read-only carve-out `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` §Forbidden discovery moves allows for a named target. On a hit, §4 owns the gate shape; persist the pick under `category: prior_work_scan` via `atomic_state_append_list_item` and fold it into the summary above so it reaches Phase 4 approach design before any approach is proposed.

**Custom post-explore steps.** Run the user-authored steps under `### After explore` in the plan custom-instructions file loaded at §1.1 (anchor per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Producer contract), each bullet as an imperative in order, honoring any `AskUserQuestion` it prescribes. They run against the mapped codebase and before the transition write, so a step that changes what the plan is about still reaches Phase 3's questions and Phase 4's approaches. Skip silently when no such subsection is loaded.

**Transition.** Resolve the Trivial skip below before evaluating the §2.1 UI trigger, then write the `phase:` of the phase actually being entered — Trivial skip → Phase 4; UI trigger matches → Phase 2; neither → Phase 3 (each phase's enum is in the spine §Phase files table). Leaving `phase:` on a phase this step just decided to skip sends a compaction-resume back into it.

**Visual plan artifact.** When `artifact_mode: true`, Read `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-artifact-call-sites.md` now — it holds the first publish and every later call site. When `artifact_mode` is unset, skip that file and treat every **Artifact** line in the phase files as a no-op.

**Skip to Phase 4 if Trivial:** when effort tier is Trivial AND research returned 0-1 findings AND topic is a narrow text-edit, Phases 2 + 3 are skipped. Write a one-line note to state.md `## Open Questions`: "Phases 2-3 skipped — trivial task, no ambiguity surfaced".
