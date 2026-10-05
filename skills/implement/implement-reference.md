# Implement skill — reference material

This file contains templates, examples, and detailed procedures referenced by SKILL.md. The orchestrator reads specific sections at the relevant phase — not the entire file upfront.

**Scope:** `/geniro:implement` is a 3-phase autonomous loop (Analyze → Implement → Self-review-and-Ship).

## Contents

- Phase 1: Step 0a signal detection
- Phase 1: Step 0c setup-question templates
- Phase 1: Step 0 setup detail
- Phase 1: $ARGUMENTS semantic-parse table
- Phase 1: Spec discovery walk-list
- Phase 1: Subagent spawn template
- Phase 1: Handoff round-trip write
- Phase 2: Pre-change visual baseline
- Phase 2: Code-delegate spawn template
- Phase 2: test-runner-agent spawn template
- Phase 2: Implement — error-handling
- Phase 3: Self-review reviewer-agent template
- Phase 3: Edge-case test authoring
- Phase 3: Bounded fix loop
- Phase 3: Minor-findings gate
- Phase 3 — Ship sub-step
- Phase 3 — Adjustment Routing (Big / Medium / Small)

---

## Phase 1: Step 0a signal detection

How each Step 0a context signal is detected. `phase-1-analyze.md` Step 0a owns the signal list and what each one means for the Step 0b decision tree; read this section at Step 0a, before that tree is evaluated.

The first four signals — `CURRENT_BRANCH`, `CURRENT_TOPLEVEL`, `IN_WORKTREE`, `PROTECTED_BRANCH` — are defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-signals.md` and detected identically here; the rows below are this skill's own additions.

| Signal | How detected |
|---|---|
| `EXISTING_TASK_STATE` | Glob `.geniro/planning/*/state.md`; any state.md whose frontmatter `branch:` equals `CURRENT_BRANCH` AND `phase:` is terminal ⇒ "prior task on this branch" |
| `REVIEW_HANDOFF` / `DEBUG_HANDOFF` | The matching `<PRIMARY_ROOT>/.geniro/state/handoff/from-<producer>-<CURRENT_BRANCH>.md` file exists. |
| `BRANCH_MATCHES_TASK_SLUG` | Derived-from-spec slug (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`) substring-matches `CURRENT_BRANCH` |
| `SPEC_WORKFLOW_REFS` | If spec.md present at resolved task slug: parse `workflow_refs:` frontmatter list (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md`). Empty list when field absent. |
| `SPEC_LAUNCH_CONFIG` | If spec.md present at resolved task slug: parse the optional `launch_config:` frontmatter block (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`) — `workspace` / `branch_freshness` / `ship_mode`, plus the optional `tracker_status` (present only when the spec had a linked tracker ticket). Empty when the block is absent, on an inline-task run with no spec, or on a pre-`m5-v4` spec that omits it. |
| `BRANCH_FORMAT_RULE` | Extracted at Step 0a from the resolved instructions base dir's `global.md` — detection mechanism and format shape canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md` §Branch-format-rule conformance. Empty when the file is absent or documents no branch rule. The custom-instructions loader at Step 5 re-Reads the same file with the full echo contract; this Step 0a read is a targeted extraction so Step 0c knows the format constraint before authorizing branch creation. |
| `TICKET_ID_IN_SCOPE` | Set to the detected ticket ID when `$ARGUMENTS` contains a Linear URL / `<TEAM>-<N>` ID, OR spec.md frontmatter `workflow_refs[]` carries one, OR `CURRENT_BRANCH` already encodes one. Empty when none in scope. |
| `CONCURRENT_ACTIVITY` | `git worktree list --porcelain` shows a peer worktree already on `CURRENT_BRANCH`, OR `git status --porcelain` at Step 0 entry shows changes this run did not author. |

---

## Phase 1: Step 0c setup-question templates

Literal question shapes for the Step 0c workspace-setup AUQ. `phase-1-analyze.md` Step 0c owns when each fires; these are the verbatim templates.

### Question 1 — workspace (the protected-branch, no-signal, and contested current-branch-continuing rules)

This question instantiates the canonical option catalogue (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §2) under Mode WORK-BASE (§3), and its `(Recommended)` handling follows that helper's §5. The labels below therefore carry NO `(Recommended)` suffix: the current-branch-continuing rule (0b rule 3) and the no-signal rule (0b rule 6) flip the label depending on `CONCURRENT_ACTIVITY`, so a suffix baked in here would render the wrong option as Recommended on every run those rules govern. Append ` (Recommended)` at render time to the one label the fired rule names.

```
header: "Workspace"
question: "Where should /geniro:implement land its edits?"
multiSelect: false
options:
  - label: "New feature branch"
    description: "git checkout -b <derived-slug>. The slug is derived from what you typed, the spec's title, or a suggested name, in that order, falling back to a generated one. If your project defines a branch-name format (in .geniro/instructions/global.md), the slug must match it before the branch is created."
  - label: "Current branch"
    description: "Pre-flight only; no git mutation. Echo 'Continuing on <branch> at <toplevel>.'"
  - label: "Git worktree"
    description: "git worktree add -b <slug> .claude/worktrees/<slug>, then switches your session into it. Isolated parallel work; instant rollback; the checkout you are in is left untouched. Same branch-name-format conformance as 'New feature branch'."
```

### No-ticket-ID sub-flow

```
header: "Ticket ID"
question: "Branch format requires a ticket prefix (per .geniro/instructions/global.md), but no ticket ID was detected in what you typed, the spec, or the current branch. How do you want to proceed?"
multiSelect: false
options:
  - label: "Provide ticket ID inline"
    description: "The ID sent in your next message (e.g. ENG-123) re-derives the slug before the branch is created."
  - label: "Use placeholder slug"
    description: "Slug becomes <type>/no-ticket-<desc>. The branch is created with the placeholder and renameable later via 'git branch -m'."
  - label: "Cancel — I'll get a ticket first"
    description: "No git changes are made. The run ends so a ticket can be created first, then /geniro:implement re-invoked."
```

---

## Phase 1: Step 0 setup detail

The `approvals[]` entry shapes (0d), the edge-case behaviors (0f), and the spec `launch_config` field map (0g). `phase-1-analyze.md` Step 0 owns when each applies.

### 0d — `approvals[]` entry shapes

```yaml
approvals:
  - category: implement_workspace_setup
    prompt: "Where should /geniro:implement land its edits?"
    options: ["New feature branch", "Current branch", "Git worktree (Recommended)"]
    picked: "Git worktree (Recommended)"
    at: <ISO-8601 UTC>
    asked_in_phase: analyze
    why: "the branch already carried a commit from this same work stream"
  - category: implement_workflow_status
    prompt: "Move to In Progress?"
    options: ["Yes — move to In Progress", "No — leave as is"]
    picked: "Yes — move to In Progress"
    at: <ISO-8601 UTC>
    asked_in_phase: analyze
    workflow_file: ".geniro/workflow/linear.md"
    transition: "Todo -> In Progress"
    issue_id: "ENG-303"
    result: "ENG-303 moved to In Progress"
```

Field names are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §"T1.5 optional `approvals` array". Two of them are easy to get wrong here. The timestamp key is `at`, not `timestamp` — the SessionStart restore hook reads `.at`, so an entry keyed `timestamp` loses its time to every later reader. And `why` / `evidence` / `result` are optional: record `why` on a pick a later reader could not reconstruct from `picked` alone, and `result` once the pick has been acted on, which for a tracker transition is the confirmation the transition landed.

A choice a spec `launch_config` pre-answered (0g) carries the same shape plus `source: launch_config`, so a restored run can tell a plan-time pre-set from a choice the user made interactively.

An outward gate — one authorizing an action from the `non-resumable-actions[]` enum (`state-tier-spec.md` §"`non-resumable-actions[]` action enum") — additionally carries `classes_shown: [<action-class>, ...]`, naming every class its question, options, or blast-radius render actually named (schema and fallback: `state-tier-spec.md` §"T1.5 optional `approvals` array"). Neither example above is an outward gate, so neither carries it.

### 0f — Edge cases

| Case | Behavior |
|---|---|
| Workflow MCP unavailable when Question 2 fires | Question 2 still fires; "Yes" answer logs warning and proceeds without MCP call. Non-blocking. |
| Workflow file present but `### On task start` section missing | Question 2 omitted silently. |
| User picks "Other" with custom text on Question 1 | Treat as "Current branch" semantically; no git mutation; echo custom text into state.md `## Workspace decision` body block. |
| Several handoffs for the current branch (any mix of review / debug) | Each satisfies the in-worktree continuing rule (0b rule 2). Echo every matched signal in its plain-English form; behavior otherwise identical. |
| Stale handoff (older than the current work) | Still triggers rule 2. Emit soft notice: `"The <producer> handoff is N days old — re-run /geniro:<producer> if you want fresh findings."` |
| `IN_WORKTREE == true` AND `PROTECTED_BRANCH == true` | Rule 4 fires (worktree-mismatch AUQ) — a worktree checked out on a protected branch is itself the anomaly to surface; rule 5 requires `IN_WORKTREE == false`. |

### 0g — `launch_config` field map

| `launch_config` field | Pre-answers |
|---|---|
| `workspace` | The 0b/0c workspace question. |
| `branch_freshness` | The strategy used when the branch is behind the default branch. |
| `ship_mode` | The Phase 3 Ship-mode AUQ (via the matching sanctioned Ship modifier). |
| `tracker_status` | The Step 0c Question 2 workflow-status question ("Move to In Progress?"). |

---

## Phase 1: $ARGUMENTS semantic-parse table

No CLI flag grammar. The orchestrator parses `$ARGUMENTS` semantically at Phase 1 entry.

| `$ARGUMENTS` shape | Mode |
|---|---|
| empty | Resume current task from `<task-dir>/state.md` if one exists; else error directing the user to provide a task description. |
| contains `continue` / `resume` (standalone word, any casing) | Resume from state.md (compaction-coupled — reads `non-resumable-actions[]` to skip side-effects already completed). |
| matches a filesystem path (rel or abs) to a `.md` file | Load as spec/plan artifact. Frontmatter validated via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`. |
| free-form description, no path match | Inline-task mode: treat `$ARGUMENTS` as a raw spec description; Phase 1 produces a minimal inline plan and proceeds. |
| ambiguous (bare slug that could be a task name OR a description) | AUQ with 2-3 disambiguation options. Persist outcome to state.md frontmatter `approvals[]` with `category: disambiguate_arguments`. |
| natural-language modifier present (`don't push`, `draft only`, `stop after review`, `with PR`, `commit only`) | Honored semantically by the Phase 3 Ship sub-step per §"Inline modifiers from $ARGUMENTS", which owns each modifier's effect. Modifier survives in $ARGUMENTS and is consulted at relevant decision points. |

**Workflow-integration plumbing.** Workflow files (`.geniro/workflow/*.md`) live in the primary worktree per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (Mode A). Glob both `./.geniro/workflow/*.md` (cwd-local — uncommitted local edits win) and `<PRIMARY_ROOT>/.geniro/workflow/*.md` (primary fallback) to find all available tracker integrations. If files exist with argument-detection patterns (e.g., Linear issue IDs, GitHub URLs), apply their patterns FIRST — they may inject extra context (issue body, status transition) before the semantic-parse table above runs. Integrations are non-blocking: if a workflow's backend (e.g., MCP) is unavailable, log a warning and proceed without.

**Approvals-persistence protocol:** before firing the disambiguation AUQ, check state.md frontmatter `approvals[]` for a prior entry with `category: disambiguate_arguments` matching the current $ARGUMENTS shape. If found, use the prior `picked` value and skip the AUQ. If not found, fire AUQ → on user pick, append to `approvals[]` via `atomic_state_append_list_item` before proceeding.

---

## Phase 1: Spec discovery walk-list

When `$ARGUMENTS` does not directly carry a spec path, walk these in order and stop at the first hit:

1. `<task-dir>/spec.md` — preferred (`/geniro:plan` canonical output).
2. `<task-dir>/plan.md` — alias.
3. design-doc frontmatter detect via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` — covers design docs that don't follow naming convention.

If none match AND $ARGUMENTS is non-empty free-form text → enter **inline-task mode**: write a brief inline plan to state.md body under `## Inline Plan` containing one-sentence goal, file list (best-effort), and approach summary. This becomes the source-of-truth for Phase 3 self-review (the `spec` field consumed by reviewer-agents).

---

## Phase 1: Subagent spawn template

Spawn `knowledge-retrieval-agent` and `codebase-explorer-agent` IN PARALLEL — one assistant response, both spawns together (the codebase-explorer alone when the store-empty gate in `phase-1-analyze.md` Step 7 skipped the knowledge-retrieval slot). Agent name per host, model, and spawn-failure ladder: `${CLAUDE_PLUGIN_ROOT}/skills/implement/operations-reference.md` §Subagent model tiering.

### Backgrounding when a handoff gate is pending (idle-overlap)

Default: spawn both agents BLOCKING and read their outputs at Step 8 — the common no-handoff run, unchanged. Engage the overlap ONLY when Step 0a flagged a review or debug handoff for this branch (`REVIEW_HANDOFF` / `DEBUG_HANDOFF`) carrying unresolved open-questions: those questions are on disk and independent of the agents' output, so the Step 12 open-questions AUQ can fire while the agents compute (Shape A of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/idle-overlap.md`). Procedure:

1. Spawn both agents `run_in_background: true` in ONE assistant response (same template + slots below; only the background flag changes).
2. In that same turn, run Step 12 sub-steps 1-7 — read the handoff, persist its body, parse `open_questions[]`, filter to unresolved, fire the open-questions AUQ per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.5 (message-first render, then a lean question), and persist each answer the moment it is picked: round-trip the producer handoff to `status: resolved` (sub-step 6) and append the `review_handoff_resolution` approval to state.md (sub-step 7). Persist in the pick-turn — never defer persistence across the Step 8 drain, where large agent outputs make compaction likely and an unpersisted pick is lost and re-asked (the blocking path persists immediately after each pick; the overlap must not widen that window). These sub-steps consume the handoff and the user's answers, never the agents' output, so they are provably independent.
3. Drain at Step 8: before reading `.kr-out.md` / `.ce-out.md`, confirm both backgrounded agents returned (Read the output file, or resume by ID). This is the first step that consumes their output.
4. After the drain, run Step 12 sub-steps 8-10 (authored-tests extraction) — the answer persistence (sub-steps 6-7) already fired in step 2.

Hard boundary: the overlap changes only WHEN the open-questions AUQ is asked, never the code-edit gate itself — every unresolved entry must still be resolved before `phase: implement`, exactly as in the blocking path.

### Related-task chain priming

Before spawning, apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md` (MODE: implement) to assemble the related-task chain context — the surrounding chain of work that places this task in its done-before / where-we-are / what's-next narrative. Source the tracker half from the spec frontmatter `workflow_refs[]` when present (already enriched by `/geniro:plan` on its newest spec format); when the chain's tracker fetch is stale (older than 1 hour) or absent, the helper refreshes it via MCP (fail-open). Source the milestone half from disk — when `/geniro:implement` is invoked on a `milestone-N.md`, the helper reads the sibling `milestone-*.md` files and the parent `spec.md` to place this milestone in the chain (what shipped before, what is next).

The helper returns a plain-English "TASK CHAIN CONTEXT" block, quoting tracker-fetched ticket and epic text — untrusted per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/untrusted-content-defense.md` §Untrusted-content fence. Inline it into BOTH spawn prompts via the `TASK_CHAIN_CONTEXT` slot below, wrapped in a `TASK-CHAIN` fence. Fail-open: when the helper returns empty (no tracker chain and no milestones), omit the slot from both prompts.

Read-only: `/geniro:implement` never mutates tracker / parent / sibling state from this step. Its existing status transition at Step 0c is unchanged and separate.

### Knowledge-Retrieval spawn

Resolve `PRIMARY_ROOT` per the Phase 1 entry preamble in `phase-1-analyze.md` before substituting the literal `<PRIMARY_ROOT>/` token in these slots — skipping that compute ships literal placeholder paths to the agents.

The orchestrator pre-resolves these slots and inlines them in the prompt:

| Slot | Source |
|---|---|
| `LIB_ROOT` | `${CLAUDE_PLUGIN_ROOT}/lib` — canonical plugin shell helpers |
| `KNOWLEDGE_ROOT` | `<PRIMARY_ROOT>/.geniro/knowledge` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` |
| `PLANNING_ROOT` | `<PRIMARY_ROOT>/.geniro/planning` — cross-session subset (`_FEATURES.md`, `_CODEBASE_MAP.md`, `_focus-*.md`) |
| `TASK_PLANNING_ROOT` | `$(pwd)/.geniro/planning/<task-slug>` — task-local (`spec.md`, prior `plan-*.md`) |
| `HANDOFF_DIR` | `<PRIMARY_ROOT>/.geniro/state/handoff/` |
| `TASK_DESCRIPTION` | `$ARGUMENTS` or `spec.title`; truncation length owned by `${CLAUDE_PLUGIN_ROOT}/agents/knowledge-retrieval-agent.md` §Input contract |
| `INFERRED_TAGS` | Tag list inferred by the orchestrator from task description (e.g., `react,auth,bug`) |
| `TASK_CHAIN_CONTEXT` | The related-task chain block from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md`, or omitted when empty |
| `PROJECT SEARCH POLICY` | Verbatim `global.md` search rules, or `none declared` — governs every lookup, not just the first |
| `OUTPUT_PATH` | `<task-dir>/.kr-out.md` |

```
Agent(subagent_type="knowledge-retrieval-agent", description="Retrieving past learnings", prompt="""
LIB_ROOT: [absolute path]
KNOWLEDGE_ROOT: [absolute path]
PLANNING_ROOT: [absolute path]
TASK_PLANNING_ROOT: [absolute path]
HANDOFF_DIR: [absolute path]
TASK_DESCRIPTION: [pre-inlined]
INFERRED_TAGS: [comma-separated list]
TASK_CHAIN_CONTEXT: [omit this line when empty; otherwise wrap the pre-inlined chain block in ---BEGIN UNTRUSTED TASK-CHAIN--- / ---END UNTRUSTED TASK-CHAIN---]
PROJECT SEARCH POLICY: [verbatim global.md search rules, or `none declared`; governs every lookup, not just the first]

OUTPUT_PATH: [absolute path under <task-dir>]

Follow the procedure in your agent file §Workflow. Write the structured
report to OUTPUT_PATH per the §Output Schema. Do NOT mutate the
codebase or git state — read-only retrieval only.
""")
```

### Codebase-Explorer spawn

The orchestrator pre-resolves these slots and inlines them in the prompt:

| Slot | Source |
|---|---|
| `WORKTREE` | `git rev-parse --show-toplevel` |
| `SPEC_CONTENT` | Pre-inlined `spec.md` body (or `## Inline Plan` from state.md for inline-task mode) |
| `RULES_DIR` | `.claude/rules/` (absolute path under WORKTREE) |
| `SEMANTIC_MAP` | Pre-inlined `_CODEBASE_MAP.md` body (~2K tokens) |
| `TASK_CHAIN_CONTEXT` | Same related-task chain block (or omitted when empty) — gives the explorer the surrounding chain of work |
| `PROJECT SEARCH POLICY` | Verbatim `global.md` search rules, or `none declared` — governs every lookup, not just the first |
| `OUTPUT_PATH` | `<task-dir>/.ce-out.md` |

`SPEC_CONTENT` and `SEMANTIC_MAP` carry content this run did not author — wrap each inside the untrusted-content fence (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/untrusted-content-defense.md`) before substituting; the codebase-explorer-agent contract treats spec and handoff content as untrusted, so the producer side matches.

```
Agent(subagent_type="codebase-explorer-agent", description="Exploring the codebase", prompt="""
WORKTREE: [absolute path]
SPEC_CONTENT:
---BEGIN UNTRUSTED PLAN---
[pre-inlined spec.md body]
---END UNTRUSTED PLAN---
RULES_DIR: [absolute path to .claude/rules/]
SEMANTIC_MAP:
---BEGIN UNTRUSTED SEMANTIC-MAP---
[pre-inlined _CODEBASE_MAP.md body]
---END UNTRUSTED SEMANTIC-MAP---
TASK_CHAIN_CONTEXT: [omit this line when empty; otherwise wrap the pre-inlined chain block in ---BEGIN UNTRUSTED TASK-CHAIN--- / ---END UNTRUSTED TASK-CHAIN---]
PROJECT SEARCH POLICY: [verbatim global.md search rules, or `none declared`; governs every lookup, not just the first]

OUTPUT_PATH: [absolute path under <task-dir>]

Follow the procedure in your agent file §Workflow. Write the
structured report to OUTPUT_PATH per the §Output Schema. Do NOT
mutate the codebase or git state — read-only reconnaissance only.

For `.claude/rules/` matching: parse YAML frontmatter `paths:` field per file;
return the LIST of relevant rule paths only — do NOT inline rule bodies. The
orchestrator JIT-loads rule bodies in Phase 2 when Edit targets match.

Anchor: WORKTREE is your root — run every Bash call from it (`cd <WORKTREE> && …`) and resolve every file path under it.
""")
```

---

## Phase 1: Handoff round-trip write

Step 12 sub-step 6 patches ONE `open_questions[]` entry in the producer's handoff. Use `atomic_state_edit`, anchored on the lines of that entry as they were read in sub-step 3 — the run already has them, because it rendered the question from them.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_edit "$HANDOFF" \
  "    status: unresolved" \
  "    status: resolved
    resolution:
      picked: \"$PICKED\"
      at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
      asked_in_phase: phase-1-step-12
      resolved_by: implement"
```

The anchor must be unique. With several entries still `unresolved`, `status: unresolved` alone matches more than one and the helper refuses (rc 72) rather than picking one — extend the anchor upward through the entry's `id:` line so it names the entry you mean:

```bash
atomic_state_edit "$HANDOFF" \
  "  - id: q2" \
  "  - id: q2
    resolution_marker: pending"   # then anchor the status line inside that entry
```

Every other key, entry and body section is left exactly as the producer wrote it, because the write touches only the anchored span. That is what protects the fields a later step reads back — review's `report_status`, debug's `authored_tests[]`, both `## Findings` bodies — without anyone having to enumerate them.

Canonical schema: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2.

---

## Phase 2: Pre-change visual baseline

The "before" half of the visual evidence pair: a screenshot of the surface as it looks while the pre-change code is still what the dev server serves. Phase 2 Step 2.5 is the only moment that is true — after the first edit a truthful baseline costs a second checkout and a second server, and a run that skipped it arrives at Ship with the changed UI as its only picture and no honest way to caption it "before".

Runs only when BOTH hold: the Phase 1 predicted affected-files list contains a UI file (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §UI-file detection rule), AND this session can drive a browser — the same capability match, and the same tool preference, that §"Pre-Ship Visual Verification" defines. Whichever tool it picks here is the one Ship re-shoots with: two frames from two different browser tools are not a comparison.

1. **Reach the surface.** Resolve and reach the app exactly as §"Pre-Ship Visual Verification" steps 1-2 do — walk up from the primary UI file to the manifest that declares a dev server, reuse a server already serving THIS project, otherwise start it in the background and wait bounded at ~30 seconds — then navigate to the route that file renders at.

2. **Capture.** Full-page screenshot to `<task-dir>/visual-before.png`. When the spec's change is one the user will judge at more than one width, capture the breakpoints too, as `visual-before-<width>.png`.

3. **Persist what Ship has to replay.** Write state.md `## Visual Baseline` via `atomic_state_append_section --create` — the exact URL, the viewport size, the image path, and the dev-server PID when this run started the server. Ship re-shoots at that same URL and viewport, because two frames of different routes or widths compare nothing; and the PID is how Ship's cleanup knows to stop a server this phase started.

**Fail open, and record the reason.** This step produces evidence, not a gate — an unreachable surface (auth wall, feature flag, a server that never answers) must not stall the code the run exists to write, and it must not be asked about before a single edit is made. Skip it, and write the reason into `## Visual Baseline` in place of the path (`image: none — dev server never answered on :3000`). A route that does not exist yet is a legitimate baseline, recorded as such (`image: none — new surface, no prior state`): what makes the record dishonest is silence, not absence.

---

## Phase 2: Code-delegate spawn template

Applies when Phase 2 Step 3's delegation rule (`${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-2-implement.md` §Step 3) selects a group for delegation. Spawn `subagent_type="general-purpose"` — no plugin agent owns this shape, and no `agents/*.md` file carries production-source write authority. Model per `operations-reference.md` §Subagent model tiering: `sonnet` is the ceiling, since the slice, its file set, and its paired test are already decided; a fully determined group (a rename across the named files, a mechanical signature update) takes a cheaper tier, one tier for the whole batch. The template below shows the ceiling form. The delegate runs in the SAME worktree as the orchestrator; the disjoint file-set allowlist is the isolation mechanism, not `isolation: worktree`.

**Pre-spawn ownership assert.** The orchestrator computes the file-set partition into disjoint delegate groups at Phase 2 Step 2 (`${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-2-implement.md` §Step 2) — a delegate never discovers its own file set. Before any delegate fires, verify: every todo in the delegated set appears in exactly one delegate's allowlist; every file those todos touch falls inside exactly one allowlist; anything with no owner is echoed to the user and assigned before spawning.

The orchestrator pre-resolves these slots per delegate:

| Slot | Source |
|---|---|
| `WORKTREE` | `git rev-parse --show-toplevel` |
| `TODO_SPEC_EXCERPT` | The todo's spec excerpt — the behavior it implements |
| `ALLOWED_FILES` | This delegate's file-set allowlist (newline-separated absolute paths) — edit only these |
| `OTHER_DELEGATES_FILES` | Every other in-flight delegate's allowlist, newline-separated — touching one means the slice spans a boundary |
| `EXEMPLAR_FILES` | 1-3 exemplar file paths, pre-inlined content, to mirror |
| `PAIRED_TEST` | The test path this slice must make pass, and what it asserts |
| `CODE_STYLE` | Pre-inlined code-style / conventions content relevant to `ALLOWED_FILES`, or omit when none applies |
| `PROJECT RULES / CONSTRAINTS` | The loaded `global.md` + `implement.md` `## Rules` and `## Constraints` sections, verbatim — a delegate never self-loads either file, so this slot is the only way a project hard gate (e.g. "Database migrations must be backwards-compatible") reaches the code the delegate writes; omit when neither file carries either section |
| `PROJECT SEARCH POLICY` | Verbatim `global.md` search rules, or `none declared` — governs every lookup the delegate makes, not just the first |

```
Agent(subagent_type="general-purpose", model="sonnet", description="Implementing: <todo summary>", prompt="""
WORKTREE: [absolute path]
TODO_SPEC_EXCERPT: [pre-inlined]
ALLOWED_FILES: [newline-separated absolute paths — edit ONLY these]
OTHER_DELEGATES_FILES: [newline-separated absolute paths other delegates own — if the slice needs one
  of these, stop and report that instead of editing it]
EXEMPLAR_FILES: [pre-inlined content of 1-3 files to mirror]
PAIRED_TEST: [path + what it asserts]
CODE_STYLE: [pre-inlined code-style / conventions content, or omit this line when none applies]
PROJECT RULES / CONSTRAINTS: [verbatim ## Rules + ## Constraints content from global.md and implement.md, or omit this line when neither file carries either section]
PROJECT SEARCH POLICY: [verbatim global.md search rules, or `none declared`; governs every lookup, not just the first]

Implement TODO_SPEC_EXCERPT against ALLOWED_FILES only — nothing beyond the slice. Match the
surrounding files' conventions and honor PROJECT RULES / CONSTRAINTS exactly as it would bind the
orchestrator's own edits. When authoring or extending PAIRED_TEST, follow
${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md §"Test design philosophy",
including its §13 pruning rule.
Write comments only for what stays true of the code — how to use
it correctly, an invariant, a legal header, a TODO with an issue reference — each no longer than
the constraint it carries; put rationale, prior behavior, and what you measured in your report
back to the orchestrator, not the source. Do NOT edit OTHER_DELEGATES_FILES or any file outside
ALLOWED_FILES. Do NOT run the full test suite — the orchestrator runs it once at end of phase.

Critical constraints — this file-set boundary and the list below are a prompt-level contract;
general-purpose carries no tool-level restriction to enforce them, so the orchestrator checks
both against your returned diff:
- No git mutation.
- No destructive Bash.
- No subagent spawning (leaf agent).

Report back every path you edited, a one-line summary of the change in each, and — for each
pre-existing test case you pruned under §13 — the removed case and the surviving test that pins
it, as `<test file>: <removed case> → pinned by <surviving test>`. If the slice needs a file
outside ALLOWED_FILES, stop and report that instead of editing it.

Anchor: WORKTREE is your root — run every Bash call from it (`cd <WORKTREE> && …`) and resolve every file path under it.
""")
```

---

## Phase 2: test-runner-agent spawn template

Spawn `test-runner-agent` ONCE at end of Phase 2 (after all TodoWrite todos completed), ONCE per fix-loop retry, and once more with the full command whenever the Phase 3 fix loop's final full-suite trigger fires (§"Phase 3: Bounded fix loop" "Final full-suite trigger"). Agent name per host, model, and spawn-failure ladder: `${CLAUDE_PLUGIN_ROOT}/skills/implement/operations-reference.md` §Subagent model tiering — OMIT `model=` on the end-of-phase run. A fix-loop re-spawn is the sizing case: the first run reported the suite's real shape, so it re-runs on a cheaper tier — smaller still on a Phase 3 fix round, which passes the related-tests command that same section defines rather than the full suite.

The orchestrator pre-resolves these slots:

| Slot | Source |
|---|---|
| `WORKTREE` | `git rev-parse --show-toplevel` |
| `TEST_COMMAND` | Project's test command from CLAUDE.md "Essential Commands" (e.g., `pnpm --filter api test:unit`, `pytest tests/`, `go test ./...`). A Phase 3 fix-round re-spawn instead passes the related-tests command §"Phase 3: Bounded fix loop" "Related-tests scoping" defines, with this command as its fallback. |
| `CHANGED_FILES` | Paths this run edited — by the orchestrator directly or by a code delegate on its behalf (newline-separated) |
| `OUTPUT_PATH` | `<task-dir>/.tr-out.md` (overwritten per retry) |

```
Agent(subagent_type="test-runner-agent", description="Running the test suite", prompt="""
WORKTREE: [absolute path]
TEST_COMMAND: [exact command string]
CHANGED_FILES: [newline-separated paths]

OUTPUT_PATH: [absolute path under <task-dir>]

Follow the procedure in your agent file §Workflow. Run TEST_COMMAND ONCE,
save full stdout+stderr to a /tmp log via tee, parse the saved log (Grep), and
write the structured report to OUTPUT_PATH per the §Output Schema. Verdict ∈
{ALL_GREEN, HAS_FAILURES, INFRA_ERROR}. Do NOT edit source code, do NOT mutate
git, do NOT re-run the suite.

Anchor: WORKTREE is your root — run every Bash call from it (`cd <WORKTREE> && …`) and resolve every file path under it.
""")
```

---

## Phase 2: Implement — error-handling

The Phase 2 fix loop uses the structured `test-runner-agent` output (NOT raw stdout):

```
retry = 1
while retry ≤ RETRY_CAP:                       # cap canonical in SKILL.md §Loop invariants (invariant 5)
  read <task-dir>/.tr-out.md
  if Verdict == ALL_GREEN → run ALL section-9 verify: commands (spec-driven runs only) and the Original-repro: command (debug handoff only);
                            on any verify failure/refusal → Step 6 escalation (one digest naming every failed/refused criterion)
                            else → exit Phase 2 → Phase 3
  if Verdict == INFRA_ERROR → escalate AUQ immediately (don't retry blind)
  inspect the structured Failures list
  edit code (or test) to address top-priority failures
  re-spawn test-runner-agent (overwrites .tr-out.md)
  retry += 1
else:
  escalate via AskUserQuestion (debug-handoff / accept-failure / abort)
```

**Evidence requirement.** The Verdict block from `.tr-out.md` (Command / Exit code / Summary) attaches as the Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` — enforced in consumption via that file's forbidden-phrase list (`"all tests pass"`, `"validation complete"`, `"ready to ship"`).

**Tool log persistence.** Every `test-runner-agent` spawn outcome (Verdict + log-file path) is appended to state.md `## Tool log` via `atomic_state_append_section`. Routine Read/Edit/Bash on local files do NOT need logging.

**Phase 2 check-failure escalation digest (render before the escalation AUQ).** When the Phase 2 escalation fires, render a failure digest to chat as its own message per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, then fire the lean AUQ. The escalation has two failure sources, and the digest + the lean AUQ's `header:` must name the right one — a `verify:`-command failure rendered under a "Test failure" frame with test-specific options mislabels what failed and what the user is deciding:

| Failure source | When | AUQ `header:` | Digest framing |
|---|---|---|---|
| Project test suite | retry exhaust, `INFRA_ERROR`, or an early not-converging trigger on the suite | `"Test failure"` | "the date-parsing tests are still failing" |
| Spec acceptance check (`verify:` command) or the debug handoff's original bug scenario | a section-9 criterion's `verify:` command, or the `Original-repro:` command (it still reproduces the bug), returned `HAS_FAILURES` / `INFRA_ERROR` (see "Per-criterion `verify:` commands" below) | `"Acceptance check failed"` | "the acceptance check the spec attached (its `verify:` command) failed", or "the original bug scenario from the debug run still reproduces" |

A run that hits BOTH sources (a `verify:` failure after a green suite) uses the neutral header `"Checks failed"` (plain-English, no phase-number — the both-source case still has to pass the fresh-user test) and the digest names both. The three options are unchanged across all three headers — hand off to a debug investigation / accept as a documented limitation / stop — and stay accurate for either source.

The digest carries:

- `### 🧭 Decision needed:` with a plain-English one-line title — name the source (e.g. "3 fix attempts spent — the date-parsing tests are still failing", "The spec's acceptance check (its `verify:` command) failed", or "The original bug scenario from the debug run still reproduces").
- `**In one sentence:**` what this decision settles — hand the failure to a debug investigation, accept it as a documented limitation, or stop.
- A conversational lead: what failed in plain English. For a test-suite failure, which behavior the failing tests check and what the fix attempts changed; for a `verify:`-command failure, which spec criterion the command checks and that it ran once and did not pass (acceptance checks are single-shot, not iterated); for an `Original-repro:` failure, that the bug scenario the debug run captured still reproduces after the fix. An `Original-repro:` that could not run is named in the digest as "not run — <reason>", never in the failed checklist. For an early trigger, state the plain-English stall reason (never the raw signal name).
- `**Why it matters:**` why this blocks the phase, in plain words — for a test-suite failure, the self-review that follows assumes green tests, so proceeding means the review reads code the suite says is broken; for a `verify:` failure, the spec's own acceptance criterion is unmet, so the run does not yet satisfy the spec's Done Condition; for an `Original-repro:` failure, the reported bug is not yet fixed.
- The failing items as a `☐` checklist — the failing-test names (test-suite source) OR the failed `verify:` criteria (or the original bug scenario) named by their plain-English intent (acceptance-check source), the test-finding shape from the same contract's §Finding-type visual map — capped at the reported failures.
- `**Technical detail:**` the evidence for the two lines above, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers — the failing command's Command / Exit code / Summary block, or the test-runner report's same block.

Build the test-suite digest from the structured `.tr-out.md` report, never raw test stdout (raw test stdout, often tens of thousands of tokens, never enters the orchestrator's context); build the `verify:`-command digest from the command's captured Command / Exit code / Summary. The lean AUQ that follows carries only the title, the source-appropriate header above, and the three options from `phase-2-implement.md` Step 6.

### Per-criterion `verify:` commands

A spec authored by /geniro:plan may attach an optional `verify: <command>` line to a section 9 (Validation) criterion (the spec field /geniro:plan authors; its read-only doctrine is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §4). It is the acceptance check for that one criterion — distinct from the project-wide TEST_COMMAND that `test-runner-agent` runs. After the end-of-phase suite reaches `ALL_GREEN`, the orchestrator runs each `verify:` command once and attaches the result as evidence.

**Cardinality — run ALL commands, then escalate ONCE.** Run every section-9 `verify:` command and collect the failed/refused set BEFORE escalating, then fire one Step 6 escalation whose `☐` checklist names every failed/refused criterion. The Step 6 escalation fires a blocking AUQ whose options all transition the phase, so it cannot return mid-loop to iterate the rest — a per-criterion "escalate then continue the loop" shape would leave a spec with two failing criteria undefined. Collect-all-then-escalate-once guarantees the user sees the complete failure set in one decision.

```
failed_or_refused = []                                          # collect across ALL criteria first
for each section-9 criterion carrying a `verify:` line:         # spec-driven runs only
  if command tokens contain a ship / deploy / external-state-mutation verb:   # side-effect screen — see below
    add {criterion, reason: "refused — side-effect"} to failed_or_refused     # collected, not executed (screen below)
    continue                                                    # skip executing THIS command, keep collecting
  result = Bash(<verify command>)                               # orchestrator's own Bash, NOT test-runner-agent
  classify result on the SAME verdict taxonomy:
    exit 0                              → ALL_GREEN  (record + continue)
    non-zero assertion-style exit       → HAS_FAILURES → add {criterion, reason} to failed_or_refused
    connection-refused / server-down    → INFRA_ERROR  → add {criterion, reason} to failed_or_refused
    blocked by a safety PreToolUse hook → INFRA_ERROR  → add {criterion, reason} to failed_or_refused  (never a silent skip — surface the block)

if failed_or_refused is non-empty:
  fire ONE Phase 2 check-failure escalation digest above (the SAME message-first AUQ) using its
  acceptance-check header/framing, with EVERY entry in failed_or_refused named in the `☐` checklist
else:
  exit Phase 2 → Phase 3
```

**Side-effect screen — refuse to auto-run a ship / deploy `verify:` command.** A refused command is collected, not executed, and surfaces in the single Step 6 escalation like an `INFRA_ERROR` (the user stays the ship decider; the three options are unchanged) with the plain-English reason: "the spec's acceptance check would push/ship/deploy, which /geniro:implement won't run on its own before the ship gate — run it yourself or remove it from the spec." A quiet skip would hide that an acceptance check was refused, so never skip silently.

This screen is needed because a `verify:` command runs at the Phase 2 green exit — BEFORE self-review and BEFORE the commit-grade Ship AUQ. No hook blocks a `git push`, `gh pr create`, or a `./deploy.sh` invocation — so a spec carrying `verify: gh pr create --fill` (or a deploy script) would otherwise ship the change with no Ship AUQ and no record of the irreversible action. That violates Loop-Invariant #3 (never ship without the gate). The screen is a doctrine guard, not a sandbox — a high-signal mutation-verb check on the command string, not an exhaustive side-effect analyzer. Apply the mutation-verb screen canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §4 (SQL-mutation verbs, `rm`/redirection/`tee`/`sed -i`, command-substitution and wrapped/aliased CLIs are all caught there). For the ship-time concern the most common matches are (case-insensitive, whole-token):

- **Source publish:** `git push` (any form, including `git push --delete`), `gh pr create`, `gh pr merge`, `git commit`.
- **Deploy / release:** `deploy`, `release`, `publish`, any project deploy/release script named in CLAUDE.md, and every wrapped deploy-CLI invocation §4 enumerates.

A read-only acceptance check (`pnpm test`, `curl -fsS localhost:3000/healthz`, `ruff check`, `tsc --noEmit`, a read-query) carries none of these verbs and runs normally.


- **`Original-repro:` from a debug handoff** joins the same loop as one more entry — named "the original bug scenario from the debug run" in the digest — under the same side-effect screen, classification and single escalation — except that a command which cannot run because a precondition is absent (a local server not running, an unset env var, a literal `[REDACTED` marker from secret redaction) is reported "not run — <reason>" rather than classified `INFRA_ERROR`: only a run that executes and still reproduces is a failure.
- **Orchestrator runs it, not `test-runner-agent`.** The runner agent's single-command leaf contract is a deliberate safety boundary — its anti-rationalization forbids it orchestrating multiple commands.
- **Evidence.** Attach each command's Command / Exit code / Summary as an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`, alongside the suite Verdict, and append the outcome to state.md `## Tool log` via `atomic_state_append_section`.

---

## Phase 3: Self-review reviewer-agent template

Spawn reviewer-agents in parallel — one spawn per dimension, all in the SAME assistant response. Agent name per host, model, and spawn-failure ladder: `${CLAUDE_PLUGIN_ROOT}/skills/implement/operations-reference.md` §Subagent model tiering.

**Pass paths, never bodies — for criteria files and for changed files alike.** Criteria files run to tens of thousands of words across the built-in dimensions; inlining them drags every word through the orchestrator's context as payload the reviewer would re-read anyway. CHANGED FILES paid that cost twice: DIFF CONTEXT already carries what changed, so a pre-inlined full body duplicated it once per dimension, every round. `reviewer-agent` can read files and reads whatever paths its prompt names — its §Step 1 for criteria, its §Step 2 for changed files. Inline a criteria body only where the reviewer cannot Read the path but you can, and say so in the slot; when unreadable for you too, pass no criteria and let the reviewer's §Fallback strategy run. Custom reviewers keep passing content — `load-custom-reviewers.md` already returns `criteria-content` from the user's own file.

**The round's review packet — shared context, written once.** Every slot the round's reviewers share goes into files written once, in the response that declares the set, and each prompt names them by path, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` §Required pre-inlined context ("A payload a whole parallel batch shares"): a spawn starts only once its own prompt has been generated, so shared text repeated in every prompt holds the last reviewer back by the whole batch's worth of it. Write a fresh packet each round, since the diff and prior-round findings change between rounds, into the run's scratch space outside the repo — the host's session scratchpad when it has one, else a `mktemp -d` directory. `common.md` carries, in this order: `PROJECT SEARCH POLICY` (the `global.md` search rules verbatim, or `none declared`), CHANGED FILES, SPEC CONTEXT, PROJECT CONTEXT, REUSE INVENTORY, PRIOR-ROUND FINDINGS, and the path of `diff.md`, which holds DIFF CONTEXT.

DIFF CONTEXT, SPEC CONTEXT, and PRIOR-ROUND FINDINGS carry content this run did not author — wrap each in the untrusted-content fence as it is written into the packet, using its canonical label (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/untrusted-content-defense.md` §Untrusted-content fence): `DIFF` for the diff, `PRIOR-ROUND` for prior-round findings, `PLAN` for spec content — the same label the codebase-explorer template above uses for `spec.md`. The search policy, DIMENSION, CRITERIA FILES, CHANGED FILES, PROJECT CONTEXT, and REUSE INVENTORY are this orchestrator's own trusted authorship — paths and text it composed or copied from this run's own codebase-explorer output, not fetched content — and stay unfenced. The packet slots:

- **CHANGED FILES** — round 1: newline-separated absolute paths this run edited; round N+1: only the paths the preceding fix round edited. The reviewer reads each one to review it.
- **DIFF CONTEXT** — `git diff $(git merge-base <base> HEAD) -- <paths>`, working tree included: nothing is committed before Ship, so there is no round sha to diff from. `<base>` resolves per the base-branch resolution rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` §The rule, and diffing from the merge-base keeps the base branch's own later commits out. New untracked files show no hunk; the reviewer reads them from CHANGED FILES. `<paths>` is the same set CHANGED FILES names this round.
- **SPEC CONTEXT** — spec.md, or state.md's `## Inline Plan` section.
- **PROJECT CONTEXT** — stack and conventions from CLAUDE.md.
- **REUSE INVENTORY** — each REUSE-AS-IS and EXTEND row of the `### Reuse Inventory` section in `<task-dir>/.ce-out.md`, reduced to its category, symbol, and `path:line` (drop the free text), every round. The `architecture` reviewer checks the diff used them (`architecture-criteria.md` §7.6). `none — explorer found no reusable analogues` when the section has no such row; `none — no reuse inventory` when the explorer produced no such section.
- **PRIOR-ROUND FINDINGS** — `none — first review` on round 1; round 2+ carries the prior round's CRITICAL/HIGH per `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Step 1.7.

Each prompt then carries only what is its own:

```
Agent(subagent_type="reviewer-agent", description="Self-review: <dim>", prompt="""
WORKTREE: [from `git rev-parse --show-toplevel`]
DIMENSION: bugs | security | architecture | tests | code-quality
REVIEW PACKET: [absolute path of this round's common.md] — read it in full before starting: its sections are part of this prompt, and the diff is reachable only through it.
PROJECT SEARCH POLICY: the packet's first section, verbatim — it governs every lookup you make, not only the first. [When it names a tool, its exact invocation, and load it by name if the runtime defers it. When the project declares none, write `PROJECT SEARCH POLICY: none declared` here instead.]
CRITERIA FILES: [absolute paths only, one per line — this dimension's criteria file(s) from the reviewer dimensions table below, plus `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/architecture-criteria.md` for `code-quality` whenever ARCHITECTURE SCOPE is rendered, and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` for `architecture` whenever SPEC-COMPLIANCE SCOPE is rendered. Read each one before reviewing.]
[ARCHITECTURE SCOPE — render for `code-quality` only, and only when the run's resolved grid (fixed at Phase 3 entry, not the dimensions re-spawned in a later round) has no `architecture` reviewer: `ARCHITECTURE SCOPE: apply only §7.6 of architecture-criteria.md — re-implementation of existing in-repo code and the packet's REUSE INVENTORY; ignore its other sections.`]
[ALSO CHECK — render for `architecture` only: `ALSO CHECK: docs-staleness — README / architecture-doc / contributing-guide references to patterns or files this diff renamed or removed.`]
[SPEC-COMPLIANCE SCOPE — render for `architecture` only, and only when the run resolved a real spec.md (SPEC CONTEXT is the spec, not an `## Inline Plan`): `SPEC-COMPLIANCE SCOPE: apply all of spec-compliance-criteria.md except §LINEAR CONTEXT supplement, §Cross-PR scope split, §Output anchor, the opening paragraph's firing condition (the orchestrator already decided to run this check), the `open_questions[]` entry in §Spec-premise validation (the INTENT-CHECK finding is the gate), and the draft / bot-author / revert bullets of §Common false positives. The packet's SPEC CONTEXT is your PLAN CONTEXT. Run every check against the run's full changed set — the merge-base diff plus untracked files — not this round's CHANGED FILES. No PR exists yet: treat PR-body and PR-metadata evidence as absent, and accept code comments or docs instead. Tag every spec-compliance finding [NEW]: an omission or divergence belongs to this change. Also flag a changed file that the spec's excluded scope names, or that no spec item accounts for, as MEDIUM [INTENT-CHECK]. Anchor each finding to the changed file:line, or to the spec section when no file applies.`]
[AUTHORED RULE FILES — code-quality only, per the slot below]

Review ONLY for [dimension]. Tag findings [SEVERITY] [NEW|PRE-EXISTING] per the output contract in ${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md §Output Format — name it, never restate it: the agent carries that section in its own instructions.

Anchor: WORKTREE is your root — run every Bash call from it (`cd <WORKTREE> && …`) and resolve every file path under it.
""")
```

The diff living only in the packet is what makes its read unskippable; the reviewer's `packet=` load-report item makes a skipped read visible — anything but `read` means that reviewer worked without the diff, so re-spawn it, correcting the path first on `unreadable`.

### The reviewer dimensions

| Dimension | Criteria file | Focus |
|-----------|---------------|-------|
| `bugs` | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/bugs-criteria.md` | Logic errors, null/undefined, off-by-one, race conditions, broken invariants |
| `security` | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/security-criteria.md` | Injection, auth/authz, secret handling, untrusted-input flows, OWASP-top-10 |
| `architecture` | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/architecture-criteria.md` | Layering, coupling, abstractions, dead code, duplication, naming, file placement. **Also covers re-implementation of existing in-repo code** per architecture-criteria.md §7.6: the diff must use the packet's REUSE INVENTORY rows and any other existing helper, component, or enum that already does the job. **Also covers docs-staleness** (ALSO CHECK line) and, on a spec-driven run, **spec-compliance** — diff matches spec.md scope (SPEC-COMPLIANCE SCOPE line); this column never reaches the reviewer. **Also covers parallel-path symmetry (mirror-gap)** per architecture-criteria.md §1.6: when the diff adds a guard / replacement / cleanup on one path, verify every sibling path sharing the invariant got the same treatment. |
| `tests` | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md` | Changed behaviors no test pins, F→P invariant, loose or brittle assertions, redundant or over-layered tests. **Pre-condition:** tests are green per Phase 2; this dim NEVER sees failing tests. |
| `code-quality` | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/optimizations-criteria.md` + `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/guidelines-criteria.md` + `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/conventions-criteria.md` + `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/rules-compliance-criteria.md` | Idiomatic style, readability, comments noise, premature abstractions, simplification opportunities, and compliance with the repo's own authored rule files (the authored-rule-citation class conventions-criteria.md §1 hands off to rules-compliance-criteria.md). When the run's resolved grid has no `architecture` reviewer, it also applies architecture-criteria.md §7.6 only (ARCHITECTURE SCOPE line). |

**Code-style.md** is loaded by every reviewer spawn, not pre-inlined by the orchestrator — each reviewer-agent self-loads it per `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Step 1.6, applying a flagged violation only when it is style-adjacent to its own dimension.

**Authored-rule-files slot (code-quality reviewer only):** pass an `AUTHORED RULE FILES:` slot — one absolute path per line to the repo's own rule files (`CLAUDE.md`, `.claude/rules/`, `.cursor/rules/`, `.cursorrules`, `AGENTS.md`, etc.), discovered via Glob before spawning, or the sentinel `none found` when the repo ships none. Always composed, never omitted — an absent slot and a repo with no rule files read identically to the reviewer, and rules-compliance-criteria.md §1 falls back to its own Glob only when the slot is missing entirely. Other dimensions do NOT get this slot.

**ACI — reviewer tool surface.** Reviewer-agents are pure-compute on the local diff. The `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` frontmatter `tools:` whitelist (`[Read, Glob, Grep, Bash, "mcp__*"]`) blocks Edit / Write / Agent outright — those tool names are absent from the grant. `Bash` and the `mcp__*` grant are not restricted by the whitelist: the agent file's own instructions ask for read-only Bash use, and the spawn template above adds no further restriction.

### Custom reviewer dimensions (`.geniro/instructions/review-extra/`)

Round 1 only — before issuing the built-in spawns, glob `.geniro/instructions/review-extra/*.md` against BOTH cwd AND `<PRIMARY_ROOT>/.geniro/instructions/review-extra/*.md` (`PRIMARY_ROOT` resolved at Phase 3 entry) — `.geniro/instructions/` is gitignored and does not propagate on `git worktree add`, so in a linked worktree the main-worktree path is the only one that finds user-authored review-extra files. **Zero matches is the common case** — skip the rest of this section silently and proceed with the built-in dimensions, without reading `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md`, since there is nothing for it to discover. On ≥1 match, apply that helper to discover and filter the candidate files: it returns a list of spawn-specs (slug, dimension-label `custom:<slug>`, model, criteria-content, severity-default, source-path) after applying its own `paths:` filter against the changed-files list and enforcing its cap — a helper call that filters every candidate back out to zero specs is the same silent no-op, one step later. Append one `Agent(subagent_type="reviewer-agent",...)` call per spec to the SAME parallel batch as the built-in dimensions (one assistant turn, one parallel batch — same rule as `/geniro:review` Phase llm-spawn and `/geniro:refactor` Phase verify per `_shared/load-custom-reviewers.md` §How consumers use the spawn-specs), and each spec's `custom:<slug>` label to `spawn_dims_declared[]` alongside the built-ins (`phase-3-ship.md` Step 1, "Declare the set before firing").

Round N+1: re-fire a custom reviewer only if its prior round flagged a CRITICAL or HIGH finding — the re-fire threshold for custom dimensions (built-ins follow their own actionable-findings re-spawn rule). The custom reviewer's spawn-spec list is recomputed only on round 1; round N+1 reuses the round-1 spec cache.

---

## Phase 3: Edge-case test authoring

An in-phase orchestrator step, not a spawn — Phase 2 already authorizes source mutation, so an orchestrator-authored test file in Phase 3 is symmetric to the code it just wrote, and editing test-file paths is already inside this phase's tool surface (`operations-reference.md` §ACI per-phase tool surface; `SKILL.md` §Loop invariants, invariant S5). It runs alongside Round 1's reviewer-agent batch; the skip conditions are in `phase-3-ship.md` Step 1.

**Read the canonical test-design taxonomy first.** Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md` §"Test design philosophy" and §"Litmus test (the deletion test)" once before hypothesizing — the mocking-discipline tiers and the deletion-test litmus bind here exactly as they bind the `tests` reviewer dimension. Do not duplicate its content into this step's output.

**Hypothesis generation.** Read the diff (`git diff $(git merge-base <base> HEAD)`, working tree included, `<base>` per the base-branch resolution rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` §The rule) with an attacker mindset — what input, ordering, or state would break this specific change, attacking along boundary values, null/empty input, ordering and async races, and critical-path failure modes. Generate 5-12 hypotheses scaled to the size of the changed regions: a ceiling, not a floor — a one-file diff earns fewer hypotheses than a ten-file one, and there is no minimum to hit. **Stop rule:** 5 hypotheses in a row ending `discarded-cannot-repro` or `inconclusive` halts further hypothesis generation for this run — return what survived rather than grinding on a diff that has already yielded what it will.

**F→P verification.** For each hypothesis worth a test, author it under the project's test directory and run it once before touching production code. A test that cannot be demonstrated RED on the current code is discarded — it isn't testing a real gap. **Hard cap: 10 authored tests per run** — at the cap, stop, note the overflow in the round summary, and let the fix loop (or a follow-up run) handle any hypothesis left over. A test that IS red for a confirmed bug survives into the round's findings as a HIGH (§"Phase 3: Bounded fix loop" ACTIONABLE definition) and is fixed in the same fix loop as the reviewer-agent findings; the next round's `test-runner-agent` run is what proves it GREEN. Authored test files stay on disk through Ship — they become part of the commit.

**Flake check (3-run determinism).** Canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flake-check.md` — same determinism procedure, run once a round's kept RED tests are demonstrated and before they enter `## Authored Tests`.

**Weak-test anti-patterns (forbidden).** Never author a test that uses any pattern `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md` §12 lists. Reaching for one is a sign the underlying hypothesis is not strong enough — discard it instead of dressing it up.

**Zero authored tests is a valid, expected outcome.** Nothing here requires production to have a bug; report "edge-case tests: none found" rather than manufacturing a marginal test to fill the slot.

**Persist as each test resolves.** Record every kept test into state.md `## Authored Tests` (the column set canonical at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §`## Authored Tests` body table, shared with `/geniro:debug` Adversarial Mode) via `atomic_state_append_section --create`, as it resolves rather than batched at round end. This is what lets a compaction mid-loop recover the step's outcome instead of re-running it, and what the Bounded fix loop's exit condition and the Ship report's edge-case line (§"Commit + Push + PR" Step 9) read — both consume the persisted record, never working memory.

**Round 2+.** A test still failing after Round 1 fixes stays live into Round 2's fix consideration — re-run it via the round's `test-runner-agent` spawn rather than re-authoring it. Once every authored test passes, this step does not re-run for the remainder of the loop.

---

## Phase 3: Bounded fix loop

```
round = 1
while round ≤ ROUND_CAP:                      # cap canonical in SKILL.md §Loop invariants (invariant 5); reads the
                                                # `Round cap:` line Phase 1 wrote to state.md body when set, else the invariant's default
  round 1: spawn reviewer-agents (resolved grid) + N custom reviewers IN PARALLEL (one
           assistant response); run the edge-case test-authoring step inline (unless skipped)
  round N+1: re-spawn only dims whose round-N ACTIONABLE finding produced an edit;
             re-run any authored edge-case test that still fails (no re-authoring)

  collect findings (reviewer dim outputs +
                    list of authored failing edge-case tests on disk)
  cold-verify: each newly collected CRITICAL/HIGH gets one
                    finding-verifier-agent verdict per phase-3-ship.md Step 2 —
                    refuted findings leave the fix set, clarified ones are
                    amended; skip when none
  partition (scope before severity — findings carry [NEW|PRE-EXISTING] tags):
    OUT-OF-SCOPE = any finding tagged PRE-EXISTING, at ANY severity — it concerns
                 code this change did not introduce, so fixing it silently expands
                 the diff past what the spec authorized. Never auto-fix; route to
                 ## Deferred Findings (severity + "pre-existing" marker preserved)
                 so the minor-findings gate puts the fix-or-defer call to the user.
    ACTIONABLE = NEW findings with severity ≥ MEDIUM, OR Decision Type routes
                 through a user gate (PRODUCT-DECISION / INTENT-CHECK), OR an
                 authored failing edge-case test (always a HIGH)
    NIT        = NEW LOW findings whose fix is mechanical and confined to code this
                 run authored — comment noise, a naming slip, a dead import, a
                 just-added scenery test flagged for removal. Fold into the CURRENT
                 round's fix batch: self-review exists to leave the just-written
                 code clean, and deferring a one-line nit on a line this run wrote
                 costs the user a decision for no risk reduction. Nits never force
                 a round and never block exit.
    MINOR      = remaining NEW LOW findings (judgment-required, or outside the
                 lines this run authored)

  if no ACTIONABLE findings AND no authored edge-case tests THAT STILL FAIL:
    apply this round's NITs inline, if any (same Edit-driven sub-loop as below —
      the full-suite trigger next covers their verification, so no separate
      test-runner-agent re-spawn is needed here)
    apply the final full-suite trigger (§"Final full-suite trigger" below)
    break  # exit → minor-findings gate → test-quality gate → Ship sub-step

  apply ACTIONABLE fixes + NITs inline (single Edit-driven sub-loop, NO further
    agent spawns). Each fix is the smallest change that resolves the finding at
    its cited site — never add an abstraction, option, or generality the finding
    does not require (speculative generality is itself a finding, not a fix); a
    recommendation that amounts to a redesign routes to the escalation AUQ, never
    the inline batch.
  re-spawn test-runner-agent scoped to this round's fixed files (§"Related-tests
    scoping" below); if Verdict != ALL_GREEN, rollback to Phase 2
  round += 1
else:
  # round ROUND_CAP+1 would start — DO NOT enter
  escalate via AskUserQuestion
```

**Related-tests scoping.** A fix round's `test-runner-agent` re-spawn passes the project's related-tests command scoped to that round's fixed files — the runner's own related-tests mode when the project has one (e.g. `vitest related --run`, `jest --findRelatedTests`), else the test files beside those changed files. Fall back to the full `TEST_COMMAND` when the project has no such mode, the scoped selection comes back empty, or the round touched config, shared test setup, fixtures, or another file an import graph can't trace to its tests. A non-green scoped run gets the same rollback-to-Phase-2 handling as a non-green full run.

**Final full-suite trigger.** Whenever the fix loop exits — the clean break above, or the escalation AUQ resolving to "Accept findings and proceed to ship" — check whether the last test run was scoped rather than full, or any edit (a fix or a clean-exit nit) landed after it. If either, run `test-runner-agent` once more with the full `TEST_COMMAND` before Ship; a non-green result gets the same rollback-to-Phase-2 handling as a non-green fix-round run. That final full-suite Verdict is what the Ship sub-step's Test results line quotes. A loop whose last test run was full with no edit after it has nothing to supersede; the suite already known green stands.

**Round N+1 only re-spawns dimensions whose round-N actionable finding produced an edit.** A dimension that reported nothing actionable in round N — clean, or minor-only — is NOT re-spawned, and neither is one whose finding was settled by a user decision with no resulting edit: bounds cost, avoids re-litigating settled code, and keeps round N+1's CHANGED FILES from coming back empty when it does fire. Custom reviewer specs are computed once at Round 1 entry; round N+1 reuses the cache. An authored edge-case test that still fails is re-checked via the round's `test-runner-agent` spawn, not re-authored.

**Minor and out-of-scope findings are collected, not chased.** They never block loop exit and never force a round. On loop exit — the clean break above OR the accepted-findings escalation path — dedupe the surviving MINOR + OUT-OF-SCOPE findings across rounds (drop any a later round's fixes incidentally resolved) and persist them to state.md under a `## Deferred Findings` body section via `atomic_state_append_section --create`, one bullet per finding: short title · severity · `path:lines` · one-line suggested fix · a `pre-existing` marker on out-of-scope entries. This persisted section is the minor-findings gate's compaction-safe input and the ship report's Deferred feeder — both read it from state.md, never from working memory. NITs never persist here — they were fixed in-round. A loop that exits with zero survivors still writes the section, carrying the sentinel `none — the fix loop converged with no minor findings left`: it is what distinguishes a clean convergence from a loop whose persist step never ran, and both consumers read that difference (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel). Alongside it, `atomic_state_set_field` sets frontmatter `reviewed_file_set: [<path>, ...]` — the union of every round's CHANGED FILES — which Ship's commit-time review-coverage guard (§"Commit + Push + PR" Step 2) diffs against what is about to be staged.

**Authored edge-case tests count as HIGH findings for fix purposes** (§"Phase 3: Edge-case test authoring"). Each test's record in state.md `## Authored Tests` is the source this exit condition and the ship report's edge-case line read — update its status there as fixes turn a test GREEN, not only in working memory.

**Escalation at exhaust.** When the loop hits its round cap (`${CLAUDE_PLUGIN_ROOT}/skills/implement/SKILL.md` §Loop invariants, invariant 5) with unresolved findings:

1. Do NOT silently push or claim completion.
2. **Render the unresolved findings to chat first** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering — a separate, already-emitted chat message, so the user decides from explained findings rather than reviewer shorthand. With ≥2 unresolved findings, open with the decision-queue progress tracker, and give each finding the visual-form block, both as that section defines them. The per-dimension findings summary lives in this render — never inside the question.
3. Then fire the lean `AskUserQuestion` (header: `"Unresolved"`) with these options:
   - **A) Hand off to /geniro:debug** — state.md transitions to `phase: debug-handoff` (terminal). No handoff file is written: `/geniro:debug` opens its own investigation from `$ARGUMENTS` and reads no planning `state.md`, so state.md here is the run's audit trail, not a consumer-parsed handoff. Close by naming the unresolved findings in chat so the user can carry them into the `/geniro:debug` invocation.
   - **B) Accept findings and proceed to ship** — apply the final full-suite trigger (§"Final full-suite trigger" above) before transitioning; state.md adds `## Accepted Findings` body block recording the decision. Transitions to `phase: ship`. The architecture reviewer in future runs sees the accepted-findings list and may flag scope concerns.
   - **C) Abort** — state.md transitions to `phase: aborted` (terminal). Work uncommitted on disk for manual takeover.

   The Explain-further reading-aid option and the pre-fire scrub arrive via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` §Single-finding gate — apply that section; don't restate it here.
4. State.md records `## Termination reason` body line on aborted/handoff: `repeated-failure: phase-3 review-round-limit (<N> unresolved findings)`.

The Always-WAIT contract applies: re-ask through the tool first on an empty `AskUserQuestion` answer, falling back to plain text only on a repeated empty-answer loop, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions.

---

## Phase 3: Minor-findings gate

Fires once the bounded fix loop converges (clean exit OR the accepted-findings escalation path), BEFORE the test-quality gate and the Ship sub-step. Same ruling set as the test-quality gate: always-on, skip-when-clean, advisory, fail-open, no new agent spawn — it consumes the `## Deferred Findings` section the fix loop persisted to state.md.

**Skip-when-clean.** When `## Deferred Findings` carries its `none — …` sentinel, skip silently — the gate never fires with nothing to decide.

**A bare or absent section is not clean.** It means the fix loop's persist step never ran, so whether minor findings survived is unknown. The gate is advisory and fail-open, so it still does not block Ship: skip it, and record the unwritten section as one line under the ship report's Deferred bullet, where "nothing deferred" would otherwise assert something the run never established.

**Message-first render.** Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, emit a separate chat message that walks EVERY finding in that section's visual-form shape (tracker when two or more, plain digest, then the `**Technical detail:**` block with the `file:line` cite, and a visual per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` §Finding-type visual map). A count is not this render: the AUQ below states how many there are, so a message that only restates the count leaves the user choosing between "fix" and "leave" with nothing to choose on. Call them "minor findings below the fix threshold", scrubbed per that reference's § Single-finding gate, "Scrub before the AUQ fires". Entries carrying the `pre-existing` marker get an explicit callout — "this one concerns code this change didn't touch; fixing it widens the change" — and a serious-severity pre-existing entry states its severity in plain English ("the review rates this one serious"), so the user can weigh an expand-scope-now decision against a follow-up task.

**Lean AskUserQuestion** (header: `Minor issues`):

```
question: "The review also flagged <N> findings it didn't auto-fix — minor ones
           below the fix threshold<, and M in pre-existing code this change
           didn't touch — omit the clause when M is 0>.
           Fix them now before shipping, or leave them listed in the ship report?"
options:
  - label: "Leave them in the ship report (Recommended)"
    description: "They stay listed in the ship report for follow-up. These came from
                  a single review pass without independent verification, so deferring
                  is the safe default."
  - label: "Fix them all now"
    description: "Fix each one inline, then re-run the test suite before shipping."
  - label: "Let me pick"
    description: "Choose which ones to fix now; the rest stay listed in the ship report."
```

The `(Recommended)` marker follows `per-finding-question.md` §Recommended-label policy — these findings are single-reviewer and unverified, so the conservative disposition carries the label. "Let me pick" runs the same contract's §Multi-select pick loop (≤4 findings per chained call).

**Fix branch** ("Fix them all now", or the picked subset) — mirrors the test-quality gate's tighten-all: re-enter the inline fix sub-loop (Edit-driven, NO new agent spawns; not a review round, so the round-cap prohibition is untouched), then re-spawn `test-runner-agent`; a Verdict other than ALL_GREEN routes through the existing Phase 2 rollback rule. Move fixed entries out of `## Deferred Findings` via `atomic_state_edit` per removed entry (a partial change, never a whole-file rewrite); unfixed picks stay listed. A pre-existing test flagged as redundant is never deleted by this fix — pruning a pre-existing case is Phase 2 authoring's call alone (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md` §13).

**Leave branch** — entries stay in `## Deferred Findings` and feed the ship report's Deferred bullet. This is ordinary deferral, NOT an overridden gate: the ship-mode AUQ's "Disclose overridden gates" stack does not apply to it.

**Persist the pick** to state.md `approvals[]` with `category: minor_findings_disposition` via `atomic_state_append_list_item`. Before firing, check `approvals[]` for a prior `minor_findings_disposition` entry and re-apply it instead of re-asking — the same check-before-fire-on-resume protocol as `ship_mode`.

**Empty answer** — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions: re-ask through the tool; never auto-default to any option, including the leave-listed path. Only a repeated empty-answer loop falls back to a plain-text question in chat.

**Boundary rules:**

- A spec `launch_config.ship_mode` and the natural-language ship modifiers (`don't push`, `commit only`, ...) pre-answer only the ship-mode question — they never skip this gate.
- Findings that arrived as task input from a review handoff's `## Findings` — including `[USER-ELECTED]`-tagged promotions the user opted into upstream — are work items already dispositioned by the user, not minor findings: they flow through the normal fix loop regardless of severity and never enter `## Deferred Findings` (no double-gating).

---

## Phase 3 — Ship sub-step

### Pre-Ship Visual Verification

Assess both conditions before anything else here: (a) the Phase 2 changed-files list contains at least one file matching the UI-file detection rule (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §UI-file detection rule), AND (b) this session can drive a browser. When either fails, persist `ship-verification: none — <reason>` ("no UI file in scope" / "no browser tool available in this session") to state.md `## Visual Baseline` via `atomic_state_append_section --create` and stop here — an absent line means this assessment never ran, not that it found nothing to verify. When both hold, the walkthrough below runs; persist `ship-verification: ran` only once it completes at step 7's post-change capture — a walkthrough that instead stops early (an auth wall, a feature flag, the user picking "Skip verification") persists `ship-verification: none — <reason>` at the point it stops, the same as a run whose trigger never held.

Condition (b) is a capability, not a vendor. Scan the live tool list for anything that opens a URL and reports back what rendered — a browser-automation MCP (Playwright under any prefix, `mcp__plugin_playwright_playwright__browser_navigate` being the sibling-plugin form; a Chrome DevTools or Puppeteer server; an agent-browser tool the harness provides) or, absent one, the project's own end-to-end driver invoked through Bash. Prefer a browser tool that returns the page into context over a scripted driver: a script reports its own exit code, while a tool that hands back the accessibility tree lets the run read what actually rendered.

When both conditions hold, the walkthrough runs automatically — no question asks whether to run it. The run has just changed what the user sees, and loading the page is the only evidence that it renders; a consent question made that evidence optional, and the cheap answer at ship time was always the one that skipped it. Echo a one-line notice to chat before step 1 ("Walking through the changed UI in a browser…") so a browser opening mid-ship reads as part of the run.

Cost is not a reason to skip, and an obstacle — auth wall, feature flag, no running dev server — is not a silent skip either: surface it through the step-1 dev-server choice ("Skip verification" / "Retry" / "Enter URL manually") and let the user, not a unilateral cost judgment, decide.

The steps below name capabilities — navigate, snapshot, console, network, resize, screenshot. Map each to the chosen tool's own call once at step 2 — reusing the tool the Phase 2 baseline capture already picked, when there was one — and keep that tool for the whole sequence; mixing two browser tools mid-walkthrough invalidates the element handles, and a baseline shot with one tool is not comparable to an after-shot from another. A capability the tool does not expose is reported as unchecked, never as clean — an unread console is not a quiet one. Execute this sequence:

1. **Reach the running app.** Resolve WHICH app first: walk up from the primary changed UI file to the nearest manifest that declares a dev server, so a monorepo starts the app the change belongs to rather than the repo root. Then find that dev server if one is already up, and confirm it serves THIS project before navigating — fire an `AskUserQuestion` when that is uncertain, since a stray server on a common port yields a verification of someone else's app. If nothing is serving, start the project's own dev server in the background, record its PID, and wait for it to answer, bounded at ~30 seconds so a server that never comes up cannot hang the run. If it never answers, fire an `AskUserQuestion` offering "Skip verification" / "Retry" / "Enter URL manually".

2. **Open the changed surface.** Navigate to the URL and viewport state.md `## Visual Baseline` recorded, so the after-shot lands on the frame the baseline already holds; with no baseline recorded, infer the route the primary changed UI file renders at and navigate there. A leaf component with no route of its own falls back to `/` and fires an `AskUserQuestion` asking where it renders. If the page that loads is a login / auth-gate page, or the inferred route returns 4xx or redirects away from the target (a feature-flag or permission wall), do NOT snapshot and proceed against the gated page — fire the same "Skip verification" / "Retry" / "Enter URL manually" `AskUserQuestion` so the user, not a unilateral skip, decides.

3. **Element snapshot.** Capture the page as the tool represents it — an accessibility tree, a DOM snapshot, or whatever handles it hands back for elements. Every subsequent interaction (click, type, fill) addresses an element through those handles, so a stale snapshot is the usual cause of an interaction landing on the wrong node.

4. **Console + network sanity check.** Read the browser console — treat any error-level entry as a failure worth reporting — and the network log, flagging same-origin 4xx/5xx responses. Re-read after step 5 and step 6. A tool exposing neither leaves both unchecked in the report.

5. **Targeted interaction.** Using the handles from step 3, perform 1-3 actions that exercise the specific behavior changed in this run. Cap at 5 total interactions. Re-snapshot after each to refresh them. When the changed behavior only exists in a transition — a modal that opens, a validation error that appears, a row that disappears — screenshot each side of that transition as `visual-interaction-<behavior>-before.png` / `-after.png`. A still frame of the settled page cannot show that an interaction did anything.

6. **Responsive sweep** — only when the diff includes any `.css`/`.scss`/`.sass`/`.less`/`.styled.*` file, OR a JSX/TSX hunk touching `className`, `style`, or a CSS-module import. Resize the viewport to 375x667 (mobile), then 768x1024 (tablet), then 1440x900 (desktop), snapshotting each. Skip entirely for pure logic changes; a tool that cannot set a viewport reports the sweep as unchecked.

7. **Post-change capture.** A full-page screenshot saved to `<task-dir>/visual-after.png`, shot at the URL and viewport state.md `## Visual Baseline` recorded — replaying both is what makes the two frames a comparison rather than two unrelated pictures. Capture `visual-after-<width>.png` for every breakpoint the step-6 sweep covered. These images and the baseline survive Ship as durable task artifacts (§Cleanup), so the user still has them when they write the PR description.

8. **Cleanup.** Stop the dev server only if this run started it — either here at step 1 or at the Phase 2 baseline capture, whose PID `## Visual Baseline` recorded. A server the user already had running stays up, since killing it takes down work outside this task.

**Evidence — show the pair, don't describe it.** Render both frames into the chat report, baseline first, each as a markdown image pointing at its on-disk path (`![before](<path>)`), with a one-line caption naming what a reader should see change between them; a host that cannot render images still prints the path. Include any interaction pair from step 5 the same way. Three things keep the pair honest: a frame belongs in it only if it is the same route at the same viewport as its partner; a run whose baseline is absent says so and quotes the recorded reason, rather than presenting the after-shot alone as proof of a change; and what the images are claimed to show is what a reader can see in them — never a pixel-diff, which nothing here computes.

**Reporting:** summarize in 3-5 lines — interaction result, console/network status, responsive issues (if swept), the evidence pair. If issues were found, render them to chat first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering — the issue list as a mini-table (risk · symptom you'd see · severity, the risk-finding shape from the same contract's §Finding-type visual map), each issue described in plain English with the screenshot it appears in referenced by path — then fire the lean `AskUserQuestion` with options: "Fix and re-verify" (route through Adjustment Routing Small tweak path below — this section re-fires after the next clean review if UI files remain in the diff), "Ship anyway with noted issues" (append to state.md `## Visual Verification Notes` and proceed to ship-mode AUQ), or "Abort" (`phase: aborted` terminal).

---

### Commit + Push + PR

**Step 2 — Commit.** Before staging, run `git branch --show-current` and verify the working tree is on the branch this run targeted (the Phase-1 Step-0 captured `CURRENT_BRANCH` / state.md `branch:` field). The session-start / state-snapshot branch field can go stale across compaction or an intervening branch switch — trust the live command, not the snapshot. On a mismatch, do NOT `git add` or `git commit`; fire an `AskUserQuestion` (header: "Branch check", question: "The working tree is on branch `<live>` but this run targeted `<expected>` — committing here would land the change on the wrong branch. How do you want to proceed?", options: "Move my commit to `<expected>` first" / "Commit on `<live>` anyway" / "Stop — let me sort the branch out").

Once the branch is confirmed, run the review-coverage guard BEFORE staging, then the provenance guard after — canonical order, since the coverage guard's re-review branch below can grow CHANGED_FILES with more fixes, and staging first would leave those out of the commit. Diff CHANGED_FILES against frontmatter `reviewed_file_set` (the file list the Phase 3 fix loop's exit recorded — the union of every round's CHANGED FILES; §"Phase 3: Bounded fix loop" above). Equal sets is the common case — nothing diverged, proceed. A file in CHANGED_FILES but absent from `reviewed_file_set` was edited after the round converged and never reviewed: the deferred spec step or reviewer-recommended follow-up implemented after Phase 3's own review closed, then shipped under its earlier clean result. Render the gap message-first (which files, and that they postdate the review) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, then a lean `AskUserQuestion` (header: "Review gap"):
- "Re-review before shipping (Recommended)" — a bounded, out-of-loop re-review, not a fix-loop round: it doesn't count against invariant 5's round cap and `phase:` stays `ship` throughout. Re-spawn the Step 1 built-in reviewer dimensions once, scoped to only the diverged files' diff, and apply any findings under Step 3's existing inline-fix rule (smallest fix at the cited site, no further agent spawns). The edit this performs is the Ship-sub-step allowance invariant S5 grants (`${CLAUDE_PLUGIN_ROOT}/skills/implement/SKILL.md` §Loop invariants). When this re-review applied any fix, re-run `test-runner-agent` once with the full `TEST_COMMAND` before continuing — an edit that lands after the fix loop's last full-suite run must not reach the commit untested; a non-green result gets the same rollback-to-Phase-2 handling as any other non-green run. Update `reviewed_file_set` to the new CHANGED_FILES on a clean result, then continue to staging.
- "Ship anyway — disclose the gap" — append a `## Unreviewed Files` body block naming the diverged files, then proceed; the block rides Step 4's Ship-mode AUQ disclosure ("Disclose overridden gates" below) by name, so the user decides with the gap in view rather than reading the earlier round's clean result as coverage for files it never saw.

Then stage only this run's (possibly grown) CHANGED_FILES set by name (`git add <paths>`, never `-A`/`.`), and only then run the provenance guard: diff `git status --porcelain` against CHANGED_FILES; any production file modified outside that set was authored by something other than this run — fire an `AskUserQuestion` (header: "Extra edits", options: "Include them — I authored them elsewhere" / "Exclude — commit only my files" / "Pause and review") rather than silently folding them into this run's commit.

Then `git commit` with conventional message (e.g., `feat(auth): add OAuth login [ENG-123]`). Task ID inferred from spec.md / state.md metadata. If a workflow file specifies commit-message format (e.g., appending issue ID), follow that format. When state.md `## Pruned Tests` is non-empty, append its lines to the commit body — the record survives even on a ship mode that opens no PR.

**Step 4 — Ship-mode AUQ.** Pushing a private feature branch that has no open PR is draft-grade (it becomes visible on remote but carries no review weight); PR creation is commit-grade. The AUQ gates the PR-creation decision. Two cases make a plain push itself commit-grade, so the "Just push (no PR)" path must surface an explicit confirm rather than auto-approving: (1) the target branch is the repository's default branch or a shared/protected branch (resolve the default via `git symbolic-ref refs/remotes/origin/HEAD`; if that errors — origin/HEAD unset, common in CI shallow clones — fall back to the base-branch resolution rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` §The rule, which resolves the default from local `main`/`master`; or teammates are actively committing to it) — it lands on the shared line with no PR gate; (2) the feature branch already has an open PR (`gh pr view --json state --jq .state` returns `OPEN`) AND this run was entered via a /geniro:review or /geniro:debug handoff — the push updates a live PR (CI re-runs, reviewers see the new commits) and the user's only approval was the upstream "apply the findings" pick, which authorizes editing, not shipping — one instance of the general rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/approval-scope.md`. In both cases, do not widen an upstream "implement the fixes" approval to authorize the push.

**Three advisory annotations ride this AUQ's question text** — the Done-Condition check and the spec-staleness notice (both spec-driven runs only) and the overridden-gate disclosure. Each is skip-when-clean and prepends one plain-English line; any that fire stack into the same question text, and none of them changes the draft-vs-commit-grade push classification or the verbatim option-label allowlist.

**Done-Condition annotation (spec-driven runs).** Before building the AUQ, on a run that resolved a real spec.md, parse the spec's section 11 (Done Condition) and apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/done-condition-check.md`. For each clause that is machine-checkable (matches the validator's stopping-condition ontology) AND affirmatively unsatisfied against the evidence the helper maps, prepend one plain-English line to the AUQ's question text so the user decides with their own completion criterion in view — e.g. "The spec's done-condition lists 'PR approved' — that's not true yet. Ship anyway?". This is advisory and skip-when-clean: when every machine-checkable clause is satisfied (or section 11 carries only free-text clauses), add nothing and proceed silently — the gate never fires with nothing to decide, mirroring the spec fact-check's restraint. Un-parseable / free-text clauses stay human-eyeball-only — never auto-graded, the guard against false-nags. The annotation rides the existing Ship AUQ's question text and obeys the caller-constraints canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/done-condition-check.md` §"What the caller does with the result". This is the ship-time clause-grader to the static diff-check the `architecture`/spec-compliance reviewer dimension runs in Phase 3; both read section 11.

Use `AskUserQuestion` (header: `"Ship mode"`). These three option labels are a canonical allowlist — present them verbatim in the AUQ; never paraphrase, merge, or collapse them (e.g., never combine "Open draft PR (Recommended)" and "Open PR" into a single "open PR" / "Commit + push + open PR" label). "Open draft PR (Recommended)" must always appear as a distinct selectable option so the safe default is surfaced. (Mirrors the canonical-option-allowlist rule in /geniro:review's action gate.)

- **Label:** `"Open draft PR (Recommended)"` / **Description:** `"git push then gh pr create --draft. Safest default — lets you review before marking ready."`
- **Label:** `"Open PR"` / **Description:** `"git push then gh pr create (ready-for-review). Appends task ID to PR title."`
- **Label:** `"Just push (no PR)"` / **Description:** `"git push origin <branch>. No PR created. On your own feature branch with no open PR this is low-stakes; on a shared or default branch — or a feature branch that already has an open PR — the push is immediately visible (reviewers and CI see the new commits), so you'll be asked to confirm first."`

**Compose the PR body from the run's records, not from the ship report.** On a pick that runs `gh pr create`, write the body per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-body.md`, which owns the section order, the project's PR template, the visual menu, and the screen against disproved spec claims (state.md `## Spec Divergences`, written per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` §8); this paragraph only maps records onto its sections. The ship report (Step 9) comes after the PR exists, so the body draws on persisted records plus this session's Phase 3 rounds; the PR outlives the session, so a widened claim is never corrected.
- **Why + ticket** — the spec's goal or the inline task, and the ticket line the workflow file's `## PR description` section prescribes (workflow files globbed as §"Integration Updates" does).
- **Evidence** — `## Authored Tests` rows are added tests that pin a behavior (Phase 3 edge-case tests, red only against this run's own new code); only a debug handoff's reproduction tests (`Authored-tests:`) support a before/after claim. Acceptance results and the original bug scenario's re-run are in `## Tool log` (§"Per-criterion `verify:` commands" Evidence bullet), while `## Phase 2 Completion`'s `verify:` is one aggregate verdict whose `; original-repro: not run — <reason>` suffix (or `verify: none — <reason>` when it was the only check) marks an original bug scenario that was not run. Screenshots: `## Visual Baseline` plus the `visual-after*.png` files, as repo-relative paths (§"Pre-Ship Visual Verification").
- **Merge danger** — the `Risk flags:` line of `<task-dir>/.ce-out.md` (still on disk until Cleanup), the spec's section 10 on spec-driven runs, and the callers the architecture reviewer named when it ran (this skill runs no regressions reviewer); callers are not persisted, so a resumed run omits them.
- **Known limitations** — `## Accepted Failures`, `## Accepted Findings`, `## Unreviewed Files`, `## Accepted Assumptions`, and `## Visual Verification Notes`.
- **Review detail** — per-dimension counts come from this session's Phase 3 rounds and `spawn_dims_declared[]` (not-run marks from `phase-3-ship.md` Step 2's post-spawn check), the deferred count from `## Deferred Findings`; `## Pruned Tests` verbatim when non-empty. A resumed run writes "not recorded" for rounds it never saw.

**Disclose overridden gates.** Before firing this AUQ, check state.md for a `## Accepted Failures` block (Phase 2 test-gate escalation), a `## Accepted Findings` block (Phase 3 review escalation), a `## Unreviewed Files` block (the Step 2 review-coverage guard's ship-anyway pick), or a `## Accepted Assumptions` block (Phase 1's spec pending-decision proceed picks). Any of the four means the working tree is NOT "fully validated" — prepend a one-line disclosure to the AUQ question text: the first two as "Note: N item(s) were accepted as known limitations (<one-line summary>) and remain unresolved. Ship anyway?"; `## Unreviewed Files` as "Note: N file(s) (<list>) were edited after the self-review pass closed and never went through it. Ship anyway?"; `## Accepted Assumptions` as "Note: this builds on N decision(s) someone else still owns (<one-line summary>), taken on a working assumption. Ship anyway?" Never frame the ship decision as fully validated when a gate was overridden. The disclosure also covers failures the orchestrator believes are pre-existing or flaky — Phase 3 entry's green-light verification already routes that classification into the same `## Accepted Failures` acknowledgement rather than exempting it (`${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-3-ship.md` §"Green-light verification on entry"), and this disclosure is where it surfaces at ship time.

**Spec-staleness advisory (spec-driven runs).** Before firing this AUQ, check whether a mid-run gate (an `AskUserQuestion` during Phase 2 or Phase 3) approved a material deviation from the spec's locked approach — a different storage shape, data model, algorithm, or scope than the spec's section 6 (Steps) describes. This is orchestrator judgment and skip-when-clean, matching the Done-Condition annotation's restraint: if the implementation followed the spec's approach, add nothing and proceed silently — the gate never fires with nothing to decide. When a deviation was approved, the saved spec.md now describes the abandoned approach while the shipped code does not — prepend one plain-English line to the AUQ's question text so the user sees the divergence before shipping: "The approved <deviation> differs from the spec's locked approach (<what the spec said>) — the saved spec.md no longer matches the shipped code. Re-run /geniro:plan to re-sync it, or keep the spec as a historical record. Ship anyway?" Never edit or rewrite spec.md from /geniro:implement: the spec.md is the user's approved upstream artifact authored by /geniro:plan, and rewriting it here would force a cross-producer schema lockstep (same reasoning as the spec fact-check's "Do not rewrite the spec" boundary) — the consumer only flags the staleness; the user or a fresh /geniro:plan run re-syncs it.

The user can always type a custom response via "Other":
- **"Review diff"** (via Other) → show diff via `git diff origin/HEAD...HEAD`, loop back to ship-mode AUQ.
- **"Don't push"** (via Other; semantically equivalent to the "don't push" inline modifier below) → commit stays local, no push. State.md → `phase: ship-committed-only` (terminal). The Phase 3 commit (step 2) has already executed at this point — this option only suppresses this step's push, not the upstream commit.

**Approvals-persistence protocol (step 4):** before firing the ship-mode AUQ, check state.md frontmatter `approvals[]` for a prior entry with `category: ship_mode`. If found, use prior `picked` value and skip the AUQ (typical compaction-resume: user already picked in the original flow) — except when the persisted pick is "Just push (no PR)" and the live target is the default or a shared/protected branch, OR a feature branch with an open PR reached via a /geniro:review or /geniro:debug handoff (re-resolve per this step's two-case check): a private-no-PR push approval does not carry to a visible push, so surface the confirm before executing rather than replaying the persisted pick. If not found, fire AUQ → on pick, append to `approvals[]` via `atomic_state_append_list_item` — with `classes_shown: [git-push]` for "Just push (no PR)" or `classes_shown: [git-push, pr-created]` for either PR-creating option, per that field's contract (`state-tier-spec.md` §"T1.5 optional `approvals` array") — before executing the chosen action.

**Record a rejection signal.** AFTER appending to `approvals[]`, source `${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh` and invoke:

```bash
emit_rejection_if_signal \
"/geniro:implement" "<branch>" "ship_mode" \
"<recommended ship-mode label>" "<picked label>" "<recommended label>"
```

`<branch>` = current git branch (or `global` if not detectable). Recommended label is whichever ship-mode option carries the `(Recommended)` suffix — "Open draft PR" by default. Helper detects rejection signals and emits L2 entry — acceptance is a no-op.

**Step 5 — Non-resumable-actions update.** After each side-effect that cannot be replayed safely (`git push`, `gh pr create`, posted PR comment), append a structured entry to state.md frontmatter `non-resumable-actions[]` array via `atomic_state_append_list_item`. Entry schema `{action, completed-at, <action-specific-fields>}`, where `action` is a literal from the enum in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §`non-resumable-actions[]` action enum (`git-push`, `pr-created`, `pr-comment-posted`), and `completed-at` comes from `$(date -u +%Y-%m-%dT%H:%M:%SZ)` in the same write call, never model-supplied (`atomic-state-write.md` §Timestamp sourcing). Write occurs AFTER the side-effect succeeds — atomic, so partial-write corruption is impossible mid-crash.

**Step 9 — Emit the ship report.** After the chosen ship action completes (push / PR create / commit-only) and its side-effect is recorded (step 5), emit a ship report to chat — a human-readable summary of what shipped, carrying the Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. This is the run's final deliverable; the terminal `phase:` transition fires only AFTER this report is emitted — a bare status echo ("opened draft PR") is not a ship report and leaves the user without the Evidence Block the report contract requires. The report covers:

- **What shipped** — the files / scope changed (the CHANGED_FILES set), one line on the change, plus the PR body's Summary visual when it used one (reuse it, never draw a second).
- **Commit + branch + PR** — commit SHA, branch name, and PR URL quoted verbatim from the actual tool output (`git rev-parse HEAD`, `git branch --show-current`, the `gh pr create` URL line) — never "git push succeeded" without the ref, per Loop invariant #6.
- **Test results** — the full-suite `test-runner-agent` Verdict block (Command / Exit code / Summary) quoted as the Evidence Block, from the LAST full-suite run of this run: Phase 2's end-of-phase run, the Phase 3 loop-exit run per the final full-suite trigger (§"Phase 3: Bounded fix loop" "Final full-suite trigger"), or the Step 2 review-coverage re-review's full-suite run when that one fired — whichever ran most recently. When `verify:` records an original-repro "not run", say here that the original bug scenario was never re-run, and why.
- **Review outcome — one line per review dimension, named, with its own result.** Report every dimension in `spawn_dims_declared[]` by name with its found / fixed counts across the rounds ("bugs: 2 found, 2 fixed · security: clean · tests: 1 found, 1 deferred"), every dimension `phase-3-ship.md` Step 2's post-spawn check marked `not-run` by name with its reason, and the edge-case test-authoring step's own outcome by name — its found/fixed counts ("edge-case tests: 1 authored, 1 fixed"), "none found" on a clean pass, or its skip reason ("edge-case tests: skipped — the change was too small to warrant them"). A dimension is never omitted and never folded into a general "verified, not assumed" statement: `spawn_dims_declared[]` is what makes an omission checkable, and a run that skipped the review has no honest way to fill in the per-dimension form it names. Self-run formatting, template-rendering, syntax, and lint checks are evidence that the change is well-formed — the build claim — and never evidence for the review claim, which only the spawned reviewer dimensions and the edge-case test-authoring step produce. Name any `## Accepted Findings` / `## Accepted Failures` / `## Unreviewed Files` / `## Accepted Assumptions` (decision, owner, working assumption) carried as known limitations.
- **Todo completeness — every declared todo named.** State how many of the tasks this run set out to do were finished, and name every one that was not, with the reason it was dropped. A task that is neither finished nor named here as dropped is one this run left open and never disclosed — the report is where that gets said, not folded into "shipped."
- **Visual evidence** — when the run captured a before/after pair, both images rendered inline per §"Pre-Ship Visual Verification" §Evidence, with their durable paths. When it did not, one line saying which half is missing and the reason `## Visual Baseline` recorded — a UI change shipped with no picture is a fact the user should read here, not infer from a silent section. When a PR was opened, add that the PR body lists the images by repo-relative path and the user needs to attach them (the `gh` CLI cannot upload images).
- **Deferred** — minor findings left unfixed, read from the task state's `## Deferred Findings` section, plus the resolved `## Test Quality Audit` and `## Phase 2 Completion` records (`${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-3-ship.md` §"Emit the ship report, then transition") and anything else left for a follow-up (skipped visual verification, docs not yet patched). Write "nothing deferred" only on the Deferred Findings section's `none — …` sentinel, which is the run's own record that the fix loop converged clean; a bare or absent section instead reports that the minor-findings list was never written.
- **Pruned tests** — when state.md `## Pruned Tests` is present, name every removed case and its surviving test verbatim; absent means none were pruned this run.

**Post-report bookkeeping — trailing writes must not contradict what shipped.** Post-ship bookkeeping (a memory-index update, an `atomic_state_write` of the terminal state, a tracker status transition) runs after the ship report. When such a write FAILS — e.g. a file edit rejected by its read-before-edit precondition, or a tracker MCP timeout — do not end the run leaving a record that contradicts the ship that already happened (the real failure mode: an index asserting the task is "not implemented" while the PR is open). Surface the failure in plain English, fix the precondition (Read the file, then Edit), and retry the write ONCE. If the retry also fails, say so explicitly in chat — "the project record still shows this as not-shipped; the PR is open at <url> — update the record manually" — so the user knows the bookkeeping is stale and the actual ship state is the PR, not the record.

**Inline modifiers from $ARGUMENTS** (semantic parsing per Phase 1 table) override the ship-mode AUQ deterministically. A spec `launch_config.ship_mode` (read at Phase 1 Step 0g per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`) pre-answers the AUQ via the same mechanism: `commit-no-push` → "don't push", `draft-pr` → "draft only", `ready-for-review` → "ready-for-review", `stop-after-review` → "stop after review". The commit-grade safeguards (default / shared-branch push, or a handoff-reached open-PR update) still gate regardless of the pre-set.

| Modifier in $ARGUMENTS | Effect |
|---|---|
| "don't push" / "no push" / "commit only" | Commit succeeds, no push. State.md → `phase: ship-committed-only` (terminal). Skip ship-mode AUQ. |
| "draft only" / "draft PR" / "open draft" | Push + `gh pr create --draft`. State.md → `phase: done`. Skip ship-mode AUQ. |
| "ready PR" / "ready-for-review" / "non-draft PR" | Push + `gh pr create` (ready-for-review). State.md → `phase: done`. Skip ship-mode AUQ. |
| "open PR" / "create PR" / "with PR" (no `draft` or `ready` qualifier) | Does NOT skip the AUQ and does NOT silently pick ready-for-review. Fires the ship-mode AUQ so the recommended draft default is surfaced — a bare "open PR" intent is ambiguous between draft and ready, so it routes through the gate rather than defaulting to the visible ready-for-review path. |
| "stop after review" | Exit Phase 3 BEFORE commit. Surface clean review status as the deliverable. State.md → `phase: self-review-only` (terminal). |

---

### Extract Learnings

The emit triggers, trust default, and project-snapshot update live in `phase-3-ship.md` Ship steps 3 and 7; this section carries the promotion suggestion only.

**Promotion suggestion.** When a `convention` entry is emitted, additionally surface a one-line suggestion in the Phase 3 final report:

```
[learnings] Pattern detected ≥3 times: "<convention summary>". Recorded as a learning.
→ Consider /geniro:instructions edit <scope>.md to promote as rule.
```

Scope hint follows reviewer dimension: dim=`code-quality` → suggest `code-style.md`; dim=`architecture` → suggest `global.md`; other → "appropriate scope". Suggestion fires ONLY for `convention` type — single-occurrence `decision` emits do NOT warrant promotion to a custom-instruction rule. The line is informational (no AUQ, no auto-edit) — user remains source-of-truth for custom-instruction curation.

---

### Integration Updates

**Worktree:** if working in a worktree (from Phase 1 workspace decision), leave the session in it. Do NOT leave the worktree proactively — runtime already prompts on session exit to keep or remove the worktree.

**Integrations:** workflow files (`.geniro/workflow/*.md`) live in the primary worktree per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (Mode A) — glob both `./.geniro/workflow/*.md` (cwd-local) and `<PRIMARY_ROOT>/.geniro/workflow/*.md` (primary fallback). If a workflow file specifies completion actions (status transitions, PR linking, comments), re-fetch the tracker issue's current `status` via MCP at ship time (the status may have changed externally during implementation) BEFORE applying the workflow file's `### On task completion` block — the block gates its questions on the current status (e.g., the Linear template skips the "Move to In Review?" prompt when already In Review or terminal). Then apply the workflow file's `### On task completion` block, passing the resolved `status` and the ship action (Commit / Commit + push / Commit + PR / Leave uncommitted) as inputs, firing its questions through an `AskUserQuestion` batch — the same construction Step 0c Question 2 uses at kickoff (`phase-1-analyze.md` §"0c — Setup questions") — before changing external state (issue status, comments), which is visible to the whole team and cannot be taken back. If integration backend is unavailable, log warning and skip both the re-fetch and the questions.

**AI-disclosure prefix.** When the workflow file contains an `## AI-disclosure prefix on authored comments` section, apply the documented prefix to any comment text the skill AUTHORS before posting via the tracker MCP. Status-only updates, assignee-only updates, commit messages, and PR descriptions are excluded per the section's exclusion list. If the AI-Disclosure section is still a TODO stub, skip authoring comments entirely — post only status-only updates.

---

### Custom post-ship steps

Execute any user-authored post-ship steps from the loaded L4 `<skill>.md` (`.geniro/instructions/implement.md`). Per the `load-custom-instructions` §Producer contract, a `## Additional Steps` subsection is anchored to a phase-enum boundary; the canonical post-ship anchor is `### After ship` (`ship` is the final non-terminal phase enum value; post-ship steps run after its work completes). Run any subsection whose phase anchor is post-ship. When a step is conditioned on a PR existing and the run did not create one (ship-mode "commit only" / "no push"), skip it.

Treat each bullet as an imperative to execute in order, honoring any `AskUserQuestion` the user's step prescribes (e.g. "ask the user whether to create a preview environment, then invoke the project's `/preview` skill and append the URLs to the PR description"). Integration Updates reads `.geniro/workflow/*.md` (tracker integrations) — a different channel — so without this step a `### After ship` block in `.geniro/instructions/implement.md` never fires.

---

### Cleanup

Run the transient cleanup directly (no agent needed). The T1 / T1.5 split contract keeps durable artifacts on disk and deletes only transient subagent outputs. This procedure runs at Ship step 8 on the ship path AND immediately before the terminal `phase:` write on every other terminal path (`aborted`, `debug-handoff`, `self-review-only`, `ship-committed-only`) — leftover transients in a finished task-dir resurface as recurring migration-walk warnings on every `/geniro:update`, so cleanup is part of completing the task, not a postscript. `rm -f` is idempotent, so files not yet created on early-exit paths are a no-op.

**Transient outputs — DELETE at terminal exit** (T1 ephemeral):

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/clean-task-transients.sh"
clean_task_transients "<task-dir>"
```

The helper is the single source of the T1 transient list (mirrored, for reading, in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T1). Those files were used once by the orchestrator or subagents during the run; they're dead weight once the task reaches a terminal state. `/geniro:plan` calls the same helper at its own terminal exit, so a plan-only or milestone-sliced run cleans its scratch even when this skill never runs against that task-dir — this run remains the backstop for any leftover from an interrupted `/geniro:plan`.

After the rm, echo `Cleaned up transient working files from <task-dir>` — one plain line; this is the in-session signal the pre-terminal check in Ship step 9 looks for.

**Durable artifacts — PRESERVE** (T1.5 task-bound durable):

```
<task-dir>/spec.md         # /geniro:plan canonical output — needed for /geniro:review spec-compliance
<task-dir>/state.md        # frontmatter + ## Tool log + ## Adjustments — needed for Adjustment Routing
<task-dir>/plan-*.md       # versioned plans from /geniro:plan iterations
<task-dir>/milestone-*.md  # /geniro:plan Big-mode milestone splits
<task-dir>/visual-*.png    # the before/after visual evidence pair
```

Downstream consumers (`/geniro:review`, `/geniro:debug`, `/geniro:refactor`, `/geniro:implement` Adjustment Routing) depend on these surviving Ship, and the user reaches for the visual pair after it — attaching it to the PR, or comparing it against the next run's. Do NOT `rm -rf <task-dir>` — durable artifacts (spec / state / plan / milestone files and the visual evidence) must survive Ship; clean only the targeted T1 scratch files.

Scratch this run created OUTSIDE the task directory — a throwaway script, a captured log — is removed by name, from the set this run actually wrote. Never sweep the user's tree by glob: a pattern like `debug-*` or `*.bak` matches files the user authored and did not ask you to touch. Ship stages by name, so a missed stray dirties the working tree without reaching a commit.

---

## Phase 3 — Adjustment Routing (Big / Medium / Small)

Used when ship-feedback arrives via PR comments or as a follow-up `$ARGUMENTS` invocation. All adjustments route back through `/geniro:implement` itself with the original spec + adjustment description as new $ARGUMENTS.

### Big — changes to data model, API contract, new endpoints

1. Write tweak description to state.md `## Adjustments` body section.
2. Re-enter Phase 1 (Analyze) — the adjusted spec.md or inline-plan becomes the fresh source-of-truth. State.md `phase:` transitions back to `analyze`.
3. Run Phase 2 (Implement) and Phase 3 (Self-review + Ship) per the standard pipeline.

### Medium — new logic, additional fields

1. Write tweak description to state.md `## Adjustments` body section.
2. Re-enter Phase 2 (Implement) — apply the delta, run test suite. State.md `phase:` transitions back to `implement`.
3. On green tests, run Phase 3 (Self-review + Ship).

### Small — styling, typo, logic tweak

1. Write tweak description to state.md `## Adjustments` body section.
2. Apply the edit inline, re-run test suite. State.md updates `## Tool log` with the side-effect.
3. Re-enter Phase 3 self-review (single round usually sufficient).

**Soft limits.** Big tweaks: after 2 rounds, suggest starting a new /geniro:implement session — fresh context provides clean separation. Medium/Small tweaks: after 3 rounds, surface a message recommending the user re-spec via `/geniro:plan`.

**Loop target.** After any tweak, loop back to the Ship sub-step (Phase 3). The Extract Learnings step runs once on first Ship entry and is NOT repeated on tweak rounds unless the tweak materially changes the learnings surface.

---
