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

At Phase 1 entry, load **L3 + L2**:

- **Project snapshot:** `source "${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh" && load_semantic`. Surface any fingerprint drift to the user.
- **Past learnings:** route the read per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override": `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --tag <inferred> --scope <topic-area> --limit 5`. Skipped if topic is too generic to infer tags. Then always run a second file query, merging any backend matches and not skipped on a generic topic, for approaches earlier runs declined — `--type user_rejected_suggestion --tag approach_choice --limit 10`, with no `--tag <inferred>` or `--scope` (a rejection is tagged by category only, and its topic string rarely repeats). Keep entries about the current topic and display each as "User previously rejected <suggestion> on <ts>" so Phase 4's approach AUQ (§4.3/§4.4) can re-rank or omit it.
- **Cross-layer resolution:** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol if the Phase 0 instruction load, L3 and L2 disagree.

### 1.1b Branch freshness

On a fresh run (skip on compaction-resume), before research spawns apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`, so the spec is grounded in fresh code; skip silently only when `BEHIND == 0`.

The update is an offer, never auto-run — a merge moves HEAD. Fire that file's update-default or catch-up question verbatim when behind; before any action that moves HEAD, run `git status --porcelain`, and any output chains its unsaved-work question first. Append the pick and resolved `behind` count to `approvals[]` (category `branch_freshness`) via `atomic_state_append_list_item`.

A `freshness:merge` / `freshness:rebase` / `freshness:skip` modifier in `$ARGUMENTS` (§0.1) answers the question: apply that strategy directly (`freshness:skip` means do not update), with the same dirty-tree check and `approvals[]` entry; a real conflict still surfaces interactively per `branch-freshness.md`.

### 1.2 Effort-tier-scaled research spawns

Detect effort tier from $ARGUMENTS shape using `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`:

| Tier | Spawns |
|---|---|
| Trivial (typo / config tweak / mechanical rename — no logic change) | 1 agent OR 0 if obviously scope-bound |
| Small (localized, single-concern change) | 1-2 agents (existing-impl; integration-surface only if it spans a boundary) |
| Medium (a feature, or a change that touches a contract / boundary) | 2 agents (existing-impl + integration-surface) |
| Big (a hard escalation signal is present, or the Big dimension-score band per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`) | 3-4 agents (subsystem-A + subsystem-B + cross-cutting + conventions) |

Spawn `codebase-research-agent` (`model=` from `subagent-model:` when set, else omitted) for each primary Phase 1 facet per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research. Facet-specific slot values: `RESEARCH_QUESTION` = the facet's research goal; `DELIVERABLE_SHAPE` = `"table of [{file, lines, observation}] verified findings"`; `SCOPE_HINT` = the facet's path globs; `OUTPUT_PATH` = `<task-dir>/.research-<facet>.md`; `THOROUGHNESS` = `medium`, or `very thorough` only for a facet whose Tool log entry states why (e.g. a subsystem with no prior map and many entry points); `RETURN: path + summary`.

When `$ARGUMENTS` carries a tracker reference, finish §1.4 first — it produces the "TASK CHAIN CONTEXT" block these spawns receive as added context. Then issue all spawns `run_in_background: true` in a single assistant response (Shape A of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md` — with no `### After explore` steps in the loaded plan.md, fire code-independent grill questions per §3.1 during the wait; drain per §1.5). Each spawn writes its full report to `OUTPUT_PATH` and returns only the path plus a ≤ ~1,000-char summary of key findings with `file:line`. The cap's home is `${CLAUDE_PLUGIN_ROOT}/agents/codebase-research-agent.md`.

### 1.3 Echo contract

Canonical in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §Echo contract — it binds Phases 1, 3, 4, and 6, so it lives in the spine.

### 1.4 Workflow refs fetch (tracker linkage)

Runs only when `$ARGUMENTS` carries a tracker reference (Linear URL/ID, Jira key, GitHub issue URL, Asana task URL), and before the §1.2 spawns. Without one the spec has no `workflow_refs[]`.

1. **Fetch.** Each tracker's patterns live in `<PRIMARY_ROOT>/.geniro/workflow/<kind>.md` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A). Fetch through the MCP tool that file names for `<kind>`; a project may register any client under any tool name.
2. **Persist.** Append the ref to state.md `## Workflow Refs` via `atomic_state_append_section --create`, in the `workflow_refs[]` entry shape of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` §Frontmatter. The fetched payload feeds the research-agent prompts, and Phase 6 copies this block into the spec frontmatter.
3. **Assemble the chain.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md` (MODE: plan) to the fetched ref(s) and the task-dir; merge its `ENRICHED_REFS` into the `## Workflow Refs` block via `atomic_state_edit`; hold the "TASK CHAIN CONTEXT" block fenced as `TASK-CHAIN` (that file's §5; `${CLAUDE_PLUGIN_ROOT}/skills/_shared/untrusted-content-defense.md` §Untrusted-content fence) for the spawn prompts. The milestone half is derived fresh each run and never persisted.

The tracker stays read-only — never mutate the parent or siblings — and every call is fail-open: an unregistered MCP or a timeout logs a `## Errors` entry and the run continues without that step.

### 1.5 Transition to Phase 2

**Drain the backgrounded explore agents first.** Before synthesizing, confirm every §1.2 explore spawn returned — Read each `<task-dir>/.research-<facet>.md`, or resume the agent by ID if an output is missing. Check each report for its `Context loaded:` line, acting on an `unreadable` or missing one per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The load report.

Synthesize findings into a brief inline summary held in context, feeding Phase 2 UI trigger detection, Phase 3 questions and Phase 5 sections.

**Prior-work scan.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/prior-work-scan.md` against the topic this run is about to plan — a named target, inside the read-only carve-out of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` §Forbidden discovery moves. On a hit, §4 owns the gate shape; persist the pick under `category: prior_work_scan` via `atomic_state_append_list_item` and fold it into the summary above so it reaches Phase 4 approach design before any approach is proposed.

**Custom post-explore steps.** Run the user-authored steps under `### After explore` in the plan custom-instructions file loaded at Phase 0 or on resume (anchor per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Producer contract), each bullet as an imperative in order, honoring any `AskUserQuestion` it prescribes. They run after the drain and the prior-work scan, against the mapped codebase, before any grill question and before the transition write, so a step that changes what the plan is about shapes Phase 3's questions and Phase 4's approaches. Skip silently when no such subsection is loaded.

**Transition.** Resolve the Trivial skip below before evaluating the §2.1 UI trigger, then write the `phase:` of the phase actually being entered — Trivial skip → Phase 4; UI trigger matches → Phase 2; neither → Phase 3 (each phase's enum is in the spine §Phase files table). A stale `phase:` sends a compaction-resume back into a skipped phase.

**Visual plan artifact.** When `artifact_mode: true`, Read `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-artifact-call-sites.md` now — it holds the first publish and every later call site. When `artifact_mode` is unset, skip that file and treat every **Artifact** line in the phase files as a no-op.

**Skip to Phase 4 if Trivial:** when effort tier is Trivial AND research returned 0-1 findings AND topic is a narrow text-edit, Phases 2 + 3 are skipped. Write a one-line note to state.md `## Open Questions`: "Phases 2-3 skipped — trivial task, no ambiguity surfaced".
