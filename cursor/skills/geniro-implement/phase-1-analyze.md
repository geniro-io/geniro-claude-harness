<!-- Generated from skills/implement/phase-1-analyze.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# /geniro:implement — Phase 1: Analyze

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/implement/SKILL.md`. Read on entry to Phase 1. **On this session's first phase entry, and again after a compaction, read `${CLAUDE_PLUGIN_ROOT}/skills/implement/operations-reference.md` in the same action as this file.**

## Contents

- Phase 1 entry — resolve `PRIMARY_ROOT`
- Step 0 — Workspace setup (0a detect · 0b decide · 0c setup questions · 0d approvals · 0e execute · 0f edge cases · 0g spec `launch_config`)
- Steps 1-13 (after Step 0 settles) — parse, spec source, task slug, prior-work scan (Step 4.5), memory loads, the knowledge-retrieval + codebase-explorer spawns (Step 7 — knowledge slot gated on a non-empty memory store), library-reuse audit, handoff open-questions gate (Step 12), spec challenge (Step 12.5), custom post-analyze steps (Step 12.6)
- Big-task notice
- Anti-rationalization (Phase 1)

---

## PHASE 1: ANALYZE

State.md `phase: analyze` on entry.

**Resolve `PRIMARY_ROOT` once at Phase 1 entry.** Run the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` in a shell call. Phase 1 reads handoffs at `<PRIMARY_ROOT>/.geniro/state/handoff/from-*-<branch>.md`, reads `global.md`'s branch-format rule at Step 0a from the resolved instructions base dir (`$GENIRO_INSTRUCTIONS_DIR` / `$CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR` when set and a valid directory, else `<PRIMARY_ROOT>/.geniro/instructions`), and hands the spawn-prompt slots `KNOWLEDGE_ROOT`, `PLANNING_ROOT`, `HANDOFF_DIR` to the knowledge-retrieval and codebase-explorer agents as absolute paths per Mode B. Without it, a run from a linked worktree falls back to cwd-relative paths and misses primary-worktree content.

### Step 0 — Workspace setup

Step 0 fires BEFORE any L4 / L3 / L2 helper call and BEFORE the Knowledge-Retrieval / Codebase-Explorer spawn — the workspace decision picks the worktree the rest of Phase 1 inspects.

#### 0a — Detect current context (passive)

Collect every signal below by its command, not by inference — an ad-hoc `git status` collects none of them. Detection commands: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Step 0a signal detection", read here before Step 0b evaluates the decision tree.

| Signal | What it tells Step 0b |
|---|---|
| `CURRENT_BRANCH` / `CURRENT_TOPLEVEL` | The branch the working tree is on, and its root. |
| `IN_WORKTREE` | The session is in a linked worktree rather than the main one. |
| `PROTECTED_BRANCH` | The current branch is one the project protects (`main` / `master` / `develop` / `trunk`). |
| `EXISTING_TASK_STATE` | A prior task on this branch left task state behind. |
| `REVIEW_HANDOFF` / `DEBUG_HANDOFF` | `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<CURRENT_BRANCH>.md` / `from-debug-<CURRENT_BRANCH>.md` exists ⇒ "review just produced findings for this branch" / "debug just authored repro tests for this branch". |
| `BRANCH_MATCHES_TASK_SLUG` | The current branch name matches this task's derived slug. |
| `SPEC_WORKFLOW_REFS` | The spec's linked tracker tickets, empty when none. |
| `SPEC_LAUNCH_CONFIG` | The spec's `launch_config:` block, which pre-answers setup questions (Step 0g); empty when absent. |
| `BRANCH_FORMAT_RULE` | The project's branch-name format, when `global.md` documents one. Without it, Step 0c authorizes branch names that violate project rules. |
| `TICKET_ID_IN_SCOPE` | The ticket ID this run already has, or empty; drives the no-ticket-ID sub-flow. |
| `CONCURRENT_ACTIVITY` | Another agent or session may be mutating this working tree, so in-place work risks an external reset orphaning this run's commit. |

#### 0b — Decide action

Decision tree (first match wins; evaluate top-down) — under Mode WORK-BASE of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §3. Only rules 1-3 skip the question, each on a mechanical signal — a spec that names the branch, a settled ticket slug, or a default that looks plainly right is not a fourth exit, since none says whether the user wants a worktree, this branch, or that slug (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/approval-scope.md`: reversibility is not the test):

```
1. Resumable state.md exists for resolved task slug
   AND state.md frontmatter phase: ∈ {analyze, implement, self-review, ship, phase-2-escalated, phase-3-escalated}
   ⇒ SKIP Step 0 entirely. Resume per state.md — a non-terminal phase rolls back to phase entry; an escalation (paused) phase re-surfaces its last AUQ options.

2. IN_WORKTREE == true
   AND CURRENT_BRANCH ∈ continuing-work set:
     • BRANCH_MATCHES_TASK_SLUG == true, OR
     • REVIEW_HANDOFF == true, OR
     • DEBUG_HANDOFF == true, OR
     • EXISTING_TASK_STATE == true
   ⇒ AUTO-CONTINUE in current worktree. NO workspace AUQ. Echo the continue in plain English — translate the matched signal to its meaning, never surface the raw token (REVIEW_HANDOFF → "a review just produced findings for this branch"; DEBUG_HANDOFF → "a debug run just authored reproduction tests for this branch"; EXISTING_TASK_STATE → "a prior task on this branch"; slug match → "the branch name matches this task"):
        "Continuing in worktree '<dir>' on '<branch>' — <plain-English reason>.
         <when a review handoff matched:> Any open questions from it will be resolved before code changes."
      Workflow Question 2 still asked if applicable (see 0c).

3. IN_WORKTREE == false
   AND PROTECTED_BRANCH == false
   AND any of {REVIEW_HANDOFF, DEBUG_HANDOFF, EXISTING_TASK_STATE} == true
   ⇒ When CONCURRENT_ACTIVITY is set, do NOT auto-continue in place — fire the full
      workspace AUQ (0c) with the recommendation flipped to "Git worktree (Recommended)"
      (an isolated worktree keeps a concurrent process from orphaning this run's commit). Otherwise AUTO-CONTINUE on
      current branch, NO workspace AUQ. Echo (translate <signal> to the plain-English reason per rule 2's mapping — never the raw token):
        "Continuing on '<branch>' — <plain-English reason>.
         Reverse with: re-run with 'new-branch' modifier in arguments."
      Workflow Question 2 still asked if applicable.

4. IN_WORKTREE == true
   AND CURRENT_BRANCH ∉ continuing-work set
   ⇒ Fire 3-option AUQ (header: "Wrong tree"):
        A) "Continue here in '<dir>'" — recommended if user explicitly cd'd here
        B) "Exit to repo root and create new worktree '<new-slug>'" — call ExitWorktree, then standard new-worktree flow
        C) "Abort — I'm in the wrong place" — terminal, no-op
      Workflow Question 2 omitted (mismatch hint suggests confusion; don't pile on).

5. IN_WORKTREE == false AND PROTECTED_BRANCH == true
   ⇒ Fire the full workspace AUQ (0c) with "Git worktree (Recommended)". A continuing signal does not auto-continue here: the current branch is protected, and starting work on it in place is exactly the outcome this AUQ exists to check with the user. The worktree carries the recommendation because it is the only option that leaves the protected checkout on its branch — `git checkout -b` still mutates the tree the user is standing in. This also covers the contested-tree case rules 3 and 6 flip to a worktree for, so rule 5 needs no CONCURRENT_ACTIVITY branch.

6. IN_WORKTREE == false, PROTECTED_BRANCH == false, no continuing signals
   ⇒ Fire the full workspace AUQ (0c). Recommendation flips: "Current branch (Recommended)" since the user is on a feature branch already — unless CONCURRENT_ACTIVITY is set, in which case it is "Git worktree (Recommended)".
```

On any AUTO-CONTINUE path (rule 2, and rule 3 when it auto-continues), apply 0e item 1's Mode FRESH-CONTINUE handling (an offer, never auto-run) right after the continue echo, before Phase 1 begins; skip it silently when the branch is already current, and entirely on a compaction-resume.

**Inline modifier overrides** (parsed from `$ARGUMENTS` per the Phase 1 semantic-parse table; an explicit modifier beats an inferred signal):

| Modifier in $ARGUMENTS | Effect |
|---|---|
| `new-branch` / `new branch` | Force branch creation even if a "continuing" signal is detected; skips the workspace question like the other three, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flags-reference.md`. |
| `current-branch` / `current branch` | Force auto-continue regardless of signals. |
| `worktree` / `new-worktree` | Force worktree creation path. |
| `no-worktree` / `here` | Force in-place execution; skips worktree even if `IN_WORKTREE == false`. |
| `--no-adversarial` | Skips Phase 3's edge-case test-authoring step for this run. |
| `--subagent-model <tier>` | Pins every `session` spawn this run makes to `<tier>` and caps the light ones, per `operations-reference.md` §Subagent model tiering. Sets `subagent-model: <tier>` (Step 4 persists it; missing reads as `inherit`). |

Conflicting modifiers (e.g., `new-branch` AND `current-branch` both present): last-occurrence wins (right-to-left scan). Emit soft notice: `"Both 'new-branch' and 'current-branch' modifiers detected; using <last>."`

Full modifier catalog: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flags-reference.md`.

#### 0c — Setup questions

Before firing this AUQ, read `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Step 0 setup detail" (the `approvals[]` entry shapes, the 0f edge cases, the 0g `launch_config` field map); the literal question templates are in §"Phase 1: Step 0c setup-question templates".

Single `AskQuestion` call carrying up to 4 questions (always-WAIT, never auto-resolve). When a spec `launch_config` pre-answered a question (Step 0g), drop that question from the batch — the pre-set is its answer; if `launch_config` pre-answers every question that would otherwise fire, the AUQ does not fire at all.

**Question 1 — always asked when rules 3, 5, or 6 fire** (header: `"Workspace"`) — offers "New feature branch" / "Current branch" / "Git worktree", un-suffixed in the template. Append ` (Recommended)` to the one the fired 0b rule names, and fire with exactly one so the set is never rudderless. Template: reference §"Phase 1: Step 0c setup-question templates".

**No-ticket-ID sub-flow.** When BRANCH_FORMAT_RULE requires a ticket prefix AND `TICKET_ID_IN_SCOPE` is empty, chain a sub-AUQ BEFORE Question 1 fires (or BEFORE the worktree command when Question 1 already resolved to a branch or worktree) — options: provide the ticket ID inline / use a placeholder slug (`<type>/no-ticket-<desc>`, renameable later) / cancel (terminal, no git mutation); literal template in the same reference section. There is no "create the ticket for me" option: /geniro:implement never creates tracker artifacts (§Anti-rationalization (Phase 1) below).

**Question 2 — conditional on workflow_refs OR `.geniro/workflow/*.md` having an `### On task start` section.** Refs come from a tracker URL/ID in `$ARGUMENTS` plus spec.md `workflow_refs[]`, deduplicated by `(kind, issue_id)` with the `$ARGUMENTS` reference winning. For each, find the workflow file (cwd-local `./.geniro/workflow/<ref.kind>.md`, else `<PRIMARY_ROOT>/.geniro/workflow/<ref.kind>.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A; both missing → warn and skip), resolve the current `status` BEFORE applying its `### On task start` block — cached when `fetched_at` is fresh, else re-fetched via MCP (timeout 3s, fail-open) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md` — then apply the block: it owns question text, options, and status-conditional branching, and may append 0-2 questions to the batch. Hardcode no tracker labels, never fire its prompt unconditionally, and echo "skipped — already in target state" cases inline.

A spec `launch_config.tracker_status` (Step 0g) pre-answers this question, still subject to the block's status gate (a pre-set `move-to-in-progress` is skipped when the task is already In Progress); it is a no-op with no tracker ref in scope and fail-open when the MCP is unavailable (warn, proceed without the transition).

A batch over 4 questions — `1` (workspace, when rules 3, 5, or 6 fire) + `N` (workflow) — chains a second AUQ.

#### 0d — Approvals-persistence

Hold the workspace and workflow-status answers as `approvals[]` entries (shapes: reference §"Phase 1: Step 0 setup detail"). state.md does not exist until Step 4, so an append here fails (rc 73); Step 4 writes the held entries, and the flag-derived `subagent-model`, into the file. On compaction-resume, Step 0 reads `approvals[]` and re-applies prior answers without re-prompting.

#### 0e — Execution after the setup questions

1. **Workspace action** — branch creation / worktree create / no-op per the `implement_workspace_setup` pick; slug per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`. Creation applies Mode FRESH-BASE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`; the "Current branch" pick applies Mode FRESH-CONTINUE from the same helper — an offer, never auto-run, because an unasked merge moves the user's HEAD. Fire that file's update-default or catch-up question verbatim when behind; before any action that moves HEAD run `git status --porcelain`, and any output chains its unsaved-work question first. Hold the pick and `behind` count with the 0d entries (`approvals[]`, category `branch_freshness`); a set `launch_config.branch_freshness` is the pre-chosen strategy, though a dirty tree or real conflict still surfaces interactively.
2. **Workflow status action** — for each `implement_workflow_status` entry held from 0d, follow the workflow file's `### On task start` instructions. The workflow file owns the MCP call shape.
3. **State.md frontmatter** — Step 4 writes `branch:` and `worktree:` for the working tree this step settled.

#### 0f — Edge cases

Resolved by the table in reference §"Phase 1: Step 0 setup detail" (workflow MCP down, missing `### On task start`, an "Other" pick on Question 1, several or stale handoffs, a worktree on a protected branch).

#### 0g — Apply spec `launch_config` (pre-answer setup)

When `SPEC_LAUNCH_CONFIG` is non-empty, apply its fields per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` (enum values and per-field semantics live there; the field → decision map is in reference §"Phase 1: Step 0 setup detail"): each pre-answers one setup question, which then does not fire. An absent block leaves every setup question interactive. Two deltas the schema does not own:

1. `workspace` does NOT override an auto-continue / resume signal — when rules 1-3 already skip the workspace question, that path wins.
2. Record applied choices in `approvals[]` as interactive answers would be — `implement_workspace_setup`, `ship_mode`, and, when `tracker_status` was set, `implement_workflow_status` — each with `source: launch_config`, so a compaction-resume re-applies them without re-asking.

`launch_config` pre-answers SETUP questions only; the safety gates stay Always-WAIT (`launch-config-schema.md` §"Doctrine boundary — setup only, never safety").

### Steps (after Step 0 settles)

1. **Semantic-parse `$ARGUMENTS`.** Apply the table, and the workflow-integration plumbing under it, in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: $ARGUMENTS semantic-parse table".
2. **Resolve spec source.** Walk the spec discovery list (`${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Spec discovery walk-list"). If no spec.md, plan.md, or DESIGN_DOC frontmatter is found AND $ARGUMENTS is non-empty → inline-task mode (write `## Inline Plan` to state.md body).
3. **Disambiguate if needed.** If $ARGUMENTS is ambiguous, fire AUQ per Phase 1 table. Hold the outcome with the Step 0 picks; Step 4 writes it to `approvals[]` with `category: disambiguate_arguments`.
4. **Resolve task slug.** Used for state.md path. If task-dir exists, validate state.md (recovery AUQ on validation fail); if fresh, `mkdir -p`. With no state.md yet, create it here via `atomic_state_write`: frontmatter `branch:` / `worktree:` for the working tree Step 0 settled, the held Step 0 picks, the Step 3 pick, and a ship modifier that pre-answers the ship question (`category: ship_mode`, `source: arguments`) as `approvals[]` entries (the `source: arguments` `ship_mode` entry wins and replaces Step 0g's `launch_config` one), `subagent-model: <tier>` when Step 1 parsed `--subagent-model <tier>` (else omitted; missing reads as `inherit`), and `no-adversarial: true` when it parsed `--no-adversarial`. The flags have no AUQ and no `approvals[]` entry, but persist them before Phase 3's reviewer batch or a compaction-resume drops them. When a validated state.md already exists, append the held entries with `atomic_state_append_list_item`.
4.5. **Prior-work scan.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/prior-work-scan.md` against the spec / plan / DESIGN_DOC resolved at Step 2, or the inline task description in inline-task mode — already named, so this is the read-only carve-out `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` §Forbidden discovery moves draws around an already-named target, not target discovery. Running before Step 7 settles `change_scope` lets a hit still narrow or redirect scope. On a hit, §4 owns the gate shape; persist the pick under `category: prior_work_scan` via `atomic_state_append_list_item`.
5. **Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: implement`, `LOAD_TIER: pipeline`, `MODE: refresh`. Its §Procedure is one helper call, then a Read of every path it lists; both are mandatory.
6. **Load project snapshot.** Phase 1 entry only — Phase 3 does not re-load it.

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh"
   load_semantic # default: _project.md + _CODEBASE_MAP.md
   load_semantic --extras "_FEATURES" # if spec mentions feature backlog
   ```

   `load_semantic` has no MODE flag — the Reads and the fingerprint drift check fire unconditionally; a mismatched `.fingerprint.json` surfaces a drift notification to the user.
7. **Spawn knowledge-retrieval + codebase-explorer agents in parallel** in ONE assistant response (just the codebase-explorer when the store-empty gate below skips the knowledge-retrieval slot). Apply `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Subagent spawn template", first priming both spawns with the related-task chain context (parent epic, sibling tasks, neighboring milestones) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md`. Under a `## Memory Backend` block routing `learnings`, read the backend first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md` §3 with the `INFERRED_TAGS` terms and pass the entries as the `BACKEND_LEARNINGS` slot. Spawn `knowledge-retrieval-agent` as **light (mid)** and `codebase-explorer-agent` as `session` (agent name per host and spawn-failure ladder: `operations-reference.md` §Subagent model tiering).

   **Store-empty gate on the knowledge-retrieval slot — a mechanical check every run evaluates fresh, continuations included.** The agent sweeps four sources (past learnings, project snapshots, prior handoffs, prior task plans); spawn it when ANY of them holds content, skip it only when ALL are empty:
   - `<PRIMARY_ROOT>/.geniro/knowledge/` contains any file (a non-empty `learnings.jsonl` or an archive);
   - any `<PRIMARY_ROOT>/.geniro/state/handoff/from-*.md` exists;
   - any `<PRIMARY_ROOT>/.geniro/planning/_*.md` snapshot exists;
   - any `<task-dir>/plan-*.md` prior plan exists;
   - OR `memory.md` (loaded at Step 5) declares a `## Memory Backend` block — backend-routed learnings are invisible to a directory check, which is exactly why this condition exists.

   The gate reads the store, never the orchestrator's own context — "I already hold this from an earlier run" satisfies no bullet. On skip, say so in plain English and record `Knowledge sweep: skipped — memory store empty` in the state.md body (with the Step 13 write), so downstream steps read skipped-empty rather than failed. The codebase-explorer spawn is unconditional.

   **Backgrounding when a handoff gate is pending:** when Step 0a flagged a review or debug handoff (`REVIEW_HANDOFF` / `DEBUG_HANDOFF`) carrying unresolved open-questions, spawn both agents `run_in_background: true` and run Step 12 sub-steps 1-7 during their compute (procedure: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Backgrounding when a handoff gate is pending"). Otherwise — the common case — spawn both BLOCKING.
8. **Read subagent outputs — drain point.** Confirm every spawned agent returned before reading `<task-dir>/.kr-out.md` and `<task-dir>/.ce-out.md` (resume by ID when an output file has not landed). Check each report's `Context loaded:` line before consuming it, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` §Reading the load report back — an `unreadable` path or a missing line is this spawn site's problem to act on. When the store-empty gate skipped the knowledge-retrieval spawn, `.kr-out.md` legitimately does not exist: drain `.ce-out.md` alone. When Step 7 backgrounded the agents, this drain is the first step to consume their output and waits for both. The codebase-explorer's `change_scope` gates the Phase 3 edge-case test-authoring step (`trivial` → skip). On missing/empty output or a spawn error, retry once silently; a second failure falls back to an inline read (top-3 exemplar files + `_CODEBASE_MAP.md` rows by Grep) with `change_scope: medium` as the safe default, emits a `diagnosis` learning with `trust: retrieved`, and echoes a notice to the user.
8.5. **Library reuse audit (build-vs-buy).** For each codebase-explorer `NO-ANALOGUE` component, when `change_scope` is small / medium / big (skip trivial), apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/library-reuse-audit.md` with MODE: implement — its message-first confirmation gate requires explicit approval before any library is adopted (persists `approvals[]` category `library_adoption`). Steps 1-4 skip silently when there is no package manifest or no NO-ANALOGUE component, Step 0 always runs, and a research/registry error fails open. A library the spec already names is re-verified for existence and health before it is confirmed — a spec can go stale between planning and implementation.
9. **Query past learnings.**

    ```bash
    source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh"
    query_learnings --tag <inferred-tag> --limit 5
    ```

    Query by tag alone: review and debug store glob scopes, which `--scope` never matches against a task path. Under a `## Memory Backend` block, this read is the Step 7 backend read (re-run it if a compaction dropped the result), merged with this file query under `mirror` and replacing it under `replace`. Tags are inferred from the task description (e.g. `react`, `auth`, `bug`) and may be primed by the knowledge-retrieval output; skip when the description is too generic. `query_learnings` has no MODE parameter — calls are idempotent.
10. **Reconcile custom instructions, snapshot and past learnings.** When the custom instructions, project snapshot, and past learnings disagree, follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md`: a **soft conflict** prints the `emit_conflict_notice` text and continues on the precedence-winning value; a **hard conflict** (a custom-instruction rule contradicts project reality) halts and calls `hard_conflict_block` + `AskQuestion` to surface it to the user.
11. (reserved — held open on purpose; `Step 12` and `Step 12.6` are cited by number from other files, so do not renumber.)
12. **Persist review / debug handoffs AND gate on unresolved open questions.** When Step 7 backgrounded the agents, sub-steps 1-7 already ran during the knowledge-retrieval / codebase-explorer wait (per the reference §"Backgrounding when a handoff gate is pending", including its persist-in-the-pick-turn rule) — do NOT re-run them; run sub-steps 8-10 here. Otherwise run all sub-steps in order here. Either way every unresolved entry must be resolved before transitioning to `phase: implement`. For every `<PRIMARY_ROOT>/.geniro/state/handoff/from-<producer>-<branch>.md` that exists:
    1. Read the handoff file directly (or `cat` it in a shell call).
    2. Persist the body under state.md `## Inputs from <producer>`, plus a `Not sent to the fix loop:` line naming (id and marker) every finding carrying `step0_status: wontfix`, `post-disposition: off-pr`, or `post-disposition: no-action` — the user, or a verifier quoting documented intent, settled these with no code change, so Phase 2 and Phase 3 take no work item from them. `Validation: unverified` is no such marker: that finding stays fixable, with a one-line warning that no verifier checked it; a finding with no `Validation:` field (legacy handoff) reads as `confirmed`, with a one-line warning that its verification was not run.
    3. Parse frontmatter `open_questions[]` per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2. Also read `report_status` (review handoffs): an explicit `report_status: draft` (missing reads as `final` per the state-tier-spec back-compat rule) means `/geniro:review` did not finish its decision gates — the handoff is not yet finalized. Surface a one-line warning ("the review handoff is still a draft — its decisions weren't finalized; resolving the open questions below completes it") and require the unresolved-open-questions gate (sub-steps 4-5) to clear before transitioning to `phase: implement`. The draft marker is a signal, not a separate block.
    4. Filter to entries with `status: unresolved`. A handoff carrying no `open_questions` key at all is not an empty list, and what a missing key obliges is in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 — resolve it before this run edits anything.
    5. **If the filtered list is non-empty, ask the user about each entry BEFORE transitioning to `phase: implement`.** Chain one AUQ per unresolved entry (cap-extension when >4). Apply the 3-tier rendering procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.5 — it renders each question as a self-contained chat message first, then a lean question, per the shared finding-gate contract (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering); which tier fires depends on the producer fields the entry carries (single-sourced in §2.5 — don't restate them here). Set `resolution.asked_in_phase: phase-1-step-12` and `resolution.resolved_by: implement` when persisting answers (vs §2.5's `phase-6-pre-gate` / `review`).
    6. After each user pick, patch that one entry in the PRODUCER's handoff file with `atomic_state_edit`, anchored on the entry's own lines as you read them: set `status: resolved` plus `resolution.picked` / `.at` / `.asked_in_phase: phase-1-step-12` / `.resolved_by: implement`. Nothing else in the file is rewritten, so no other key, entry, or body section can be dropped. Procedure: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Handoff round-trip write".
    7. Persist a parallel approval to state.md `approvals[]` with `category: review_handoff_resolution`, `picked: <chosen option>`, `at: <ISO-8601 UTC>`, `source_handoff: <producer>`, `question_id: <id>` for compaction-resume idempotency.
    8. After all entries are `resolved` or `wontfix`, proceed to sub-step 9.
    9. **Extract authored F→P tests when the handoff is from `/geniro:debug`** (`from-debug-<branch>.md` and `from-debug-adversarial-<branch>.md` only; skip any other producer). Apply the Scan / Extract / Verify / Decide protocol in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md`, including its suggest-only relocation block for MISSING paths — the user runs any checkout or copy, never this run. **Persist** to state.md as `Authored-tests:` (comma-separated relative paths on a single line) plus, when sourced from m7-v2+ frontmatter, `Authored-tests-intent:` (parallel comma-separated intents) and `Debug-source-branch:` / `Debug-source-worktree:`, plus `Original-repro:` (the command verbatim) when extracted. Phase 2 reads these to prime the todo decomposition — each authored test becomes a pre-existing acceptance gate, surfacing in the relevant todo's description so the production-fix work cannot ship without those tests going GREEN. The extraction is informational, NOT a gate: missing files never block the transition to `phase: implement`.
    10. After authored-tests handling, proceed to the spec pending-decisions check below.

    **Spec pending decisions (spec-driven mode, once after the handoff loop — also when no handoff exists).** Every section-4 line of the spec shaped `pending: <owner> — <decision>; working assumption: <X>` is a decision someone else still owns; building on it silently would bake an unanswered question into code. Skip an entry whose recorded `review_handoff_resolution` approval (`source_handoff: spec`) picked proceed (compaction-resume); a recorded stop never skips, because a stop ends the run. Render each remaining entry message-first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering (owner, decision, working assumption in plain English), then ask one lean question per entry (cap-extension when >4): proceed on the working assumption / stop until the owner decides. Persist each pick like sub-step 7 (`picked`, `at`, `source_handoff: spec`, `question_id: pending-<n>`) and append a proceed pick's assumption under a `## Accepted Assumptions` body section via `atomic_state_append_section --create`, which Ship's disclosure and the PR description name (`${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Commit + Push + PR"). A stop pick is terminal before any edit: run the §"Cleanup" transient cleanup, write `## Termination reason` as `user-cancelled: pending-decision`, then `phase: aborted`, and tell the user to replace the spec's section-4 `pending:` line with the decision (or re-run /geniro:plan) and re-run /geniro:implement.

12.5. **Spec challenge — fact-check the spec against the current code before editing.** The last plugin-defined gate before code edits begin. Spec-driven mode only: when Step 2 resolved no real spec.md / plan.md / DESIGN_DOC (inline-task fallback), emit "No spec file — skipping the spec fact-check" and proceed to step 13. Otherwise apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` with MODE: implement, SPEC_PATH: \<resolved spec path>, TASK_DIR: \<task-dir>, EFFORT_TIER: \<the codebase-explorer change_scope>. That file's §8 owns verdict handling — the skip-when-clean advisory and, on `defects-found`, the message-first render (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering) followed by the lean AskQuestion with its option set verbatim; read it there, not from a second copy. One option applies a bounded fact correction to the spec in place, so this step may write the spec via `atomic_state_write` — facts only, never the approach, and the corrected claims re-enter the helper per its §8.5. Record the pick in state.md frontmatter `approvals[]` with `category: spec_challenge`, `picked: <chosen option>`, `at: <ISO-8601 UTC>` for compaction-resume idempotency. Fail-open: if the helper or any verifier spawn fails, write a line to state.md `## Errors`, emit a one-line notice, and proceed to step 13.

12.6. **Custom post-analyze steps.** Execute any user-authored post-analyze steps from the L4 `implement.md` instruction file (`.geniro/instructions/implement.md`) loaded at Step 5: per the `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Producer contract, the canonical post-analyze anchor is `### After analyze` (the spec, the handoffs and the codebase map are all resolved by now, and no production file has been edited yet). Run any subsection anchored to the end of `analyze`, treating each bullet as an imperative to execute in order and honoring any `AskQuestion` the step prescribes. This is the extension point for project work that must precede code edits — most often the product question an inline-task run never had a spec to answer; record its outcome into the `## Inline Plan` Step 13 writes. Without this step a loaded `### After analyze` block is silently dropped once Phase 2 begins. Skip silently when none is loaded.

13. **State.md write.** Add the `phase: analyze` body sections to the state.md Step 4 created via `atomic_state_append_section --create` per section — a whole-file `atomic_state_write` regenerates the frontmatter and drops the `approvals[]` and `non-resumable-actions[]` entries Steps 4-12 appended. In inline-task mode the `## Inline Plan` ends with a `Premises:` line, the load-bearing facts about existing code the approach relies on, each with `file:line` from the exploration above, which the Phase 3 `intent` reviewer checks. Add a `Round cap: <N>` body line when $ARGUMENTS stated a self-review round limit lower than Phase 3's ROUND_CAP default (`SKILL.md` §Loop invariants); Phase 3's fix loop reads it back instead of re-parsing $ARGUMENTS after a compaction. Leave `phase:` at `analyze` — Phase 2 entry owns the advance to `implement`, so the file names the phase actually completed if the run stops between the two.

   When the exit continues into Phase 2, its last action, in this same turn, is to Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-2-implement.md`, the Phase 2 entry.

### Big-task notice

When Codebase-Explorer reports `change_scope: big` AND no `milestone-*.md` files exist alongside spec.md, emit one informational notice (NOT AUQ — just observation):

```
This is a large change. Consider running /geniro:plan in milestone mode to
split it into separate milestone files before implementing. This run will
proceed as a single pass with a step-by-step task list; splitting is cleaner.
```

### Anti-rationalization (Phase 1)

| Your reasoning | Why it's wrong |
|---|---|
| "Branch format requires a ticket prefix per global.md — I'll create the Linear / Jira / GitHub-Issues ticket so the slug conforms." | /geniro:implement never creates tracker artifacts. Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md` §Mutation responsibility it transitions tracker status (Phase 1 kickoff, Phase 3 Ship completion) but creates no tickets, issues, epics, or sub-tasks. A branch-format rule demanding a ticket ID is satisfied by the no-ticket-ID sub-flow's three options. An agent-created ticket triggers notifications and sprint-planning rows the user never approved. |
| "/geniro:implement should inline read every relevant .claude/rules/, exemplar, and prior plan for thoroughness." | Loop invariant S1 bounds the orchestrator's own reads and delegates the rest. `.claude/rules/*.md` bodies and exemplar sources are JIT-loaded in Phase 2 only when an Edit target matches the rule's `paths:` glob, using the path list the codebase-explorer returned. |
