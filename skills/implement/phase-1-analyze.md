# /geniro:implement — Phase 1: Analyze

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/implement/SKILL.md`. Read on entry to Phase 1. The spine keeps the state machine, the loop invariants, the anti-rationalization table, the handoff contract, and the tool surface — this file carries the Steps.

## Contents

- Phase 1 entry — resolve `PRIMARY_ROOT`
- Step 0 — Workspace setup (0a detect · 0b decide · 0c setup questions · 0d approvals · 0e execute · 0f edge cases · 0g spec `launch_config`)
- Steps 1-13 (after Step 0 settles) — parse, spec source, task slug, memory loads, the knowledge-retrieval + codebase-explorer spawns (Step 7 — knowledge slot gated on a non-empty memory store), library-reuse audit, handoff open-questions gate (Step 12), spec challenge (Step 12.5)
- Big-task notice

---

## PHASE 1: ANALYZE

State.md `phase: analyze` on entry.

**Resolve `PRIMARY_ROOT` once at Phase 1 entry.** Run the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` via Bash. Phase 1 reads handoffs at `<PRIMARY_ROOT>/.geniro/state/handoff/from-*-<branch>.md`, targeted-reads `global.md` for the branch-format rule at Step 0a from the resolved instructions base dir (the external override `$GENIRO_INSTRUCTIONS_DIR` / `$CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR` when set and a valid directory, else `<PRIMARY_ROOT>/.geniro/instructions`), and spawns knowledge-retrieval + codebase-explorer agents whose spawn-prompt slots (`KNOWLEDGE_ROOT`, `PLANNING_ROOT`, `HANDOFF_DIR`) require this value substituted to absolute paths per Mode B. Without it, the handoff probes / global.md read / subagent spawns silently fall back to cwd-relative paths and miss content in the primary worktree when /geniro:implement runs from a linked worktree.

### Step 0 — Workspace setup

Step 0 fires BEFORE any L4 / L3 / L2 helper call and BEFORE the Knowledge-Retrieval / Codebase-Explorer spawn. Workspace decision determines the worktree the rest of Phase 1 inspects; running L3 fingerprint drift checks against the wrong worktree is wasted work.

Two sub-steps: **passive detection** (0a, no AUQ) → **decide action** (0b, auto-continue or AUQ).

#### 0a — Detect current context (passive)

Collect every signal below before deciding. How each is detected: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Step 0a signal detection" — read it here, before Step 0b evaluates the decision tree.

| Signal | What it tells Step 0b |
|---|---|
| `CURRENT_BRANCH` | The branch the working tree is on. |
| `CURRENT_TOPLEVEL` | The working tree's root. |
| `IN_WORKTREE` | The session is in a linked worktree rather than the main one. |
| `PROTECTED_BRANCH` | The current branch is one the project protects (`main` / `master` / `develop` / `trunk`). |
| `EXISTING_TASK_STATE` | A prior task on this branch left task state behind. |
| `REVIEW_HANDOFF` | `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<CURRENT_BRANCH>.md` exists ⇒ "review just produced findings for this branch". |
| `DEBUG_HANDOFF` | `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<CURRENT_BRANCH>.md` exists ⇒ "debug just authored repro tests for this branch". |
| `RESOLVE_HANDOFF` | `<PRIMARY_ROOT>/.geniro/state/handoff/from-resolve-<CURRENT_BRANCH>.md` exists ⇒ "PR-feedback triage just produced a fix plan for this branch". `EXISTING_TASK_STATE` does not cover it — /geniro:resolve keeps its state outside `.geniro/planning/`. Without this signal the run falls through to the workspace question and can be steered onto a new branch, off the PR branch the fixes must land on. |
| `BRANCH_MATCHES_TASK_SLUG` | The current branch name matches this task's derived slug. |
| `SPEC_WORKFLOW_REFS` | The spec's linked tracker tickets, empty when the spec carries none. |
| `SPEC_LAUNCH_CONFIG` | The spec's `launch_config:` block, which pre-answers the matching Step 0 setup questions per Step 0g below. Empty on an inline-task run or a spec without the block. |
| `BRANCH_FORMAT_RULE` | The project's branch-name format, when `global.md` documents one. Without this signal, Step 0c authorizes branch names that violate project rules and the agent has to rename after the fact. |
| `TICKET_ID_IN_SCOPE` | The ticket ID this run already has, or empty. Cross-checked against `BRANCH_FORMAT_RULE` at Step 0c to decide whether the no-ticket-ID sub-flow fires. |
| `CONCURRENT_ACTIVITY` | Another agent or session may be mutating this working tree — a contested shared tree where in-place work risks an external reset or rename orphaning this run's commit. |

#### 0b — Decide action

Decision tree (first match wins; evaluate top-down). Only rules 1-3 skip the question, and each turns on a mechanical signal — a spec that names the branch, a ticket whose slug is settled, or a default that looks plainly right is not a fourth exit, because none of them says whether the user wants a worktree, this branch, or that slug (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/approval-scope.md` — reversibility is not the test):

```
1. Resumable state.md exists for resolved task slug
   AND state.md frontmatter phase: ∈ {analyze, implement, self-review, ship, phase-2-escalated, phase-3-escalated}
   ⇒ SKIP Step 0 entirely. Resume per state.md — a non-terminal phase rolls back to phase entry; an escalation (paused) phase re-surfaces its last AUQ options.

2. IN_WORKTREE == true
   AND CURRENT_BRANCH ∈ continuing-work set:
     • BRANCH_MATCHES_TASK_SLUG == true, OR
     • REVIEW_HANDOFF == true, OR
     • DEBUG_HANDOFF == true, OR
     • RESOLVE_HANDOFF == true, OR
     • EXISTING_TASK_STATE == true
   ⇒ AUTO-CONTINUE in current worktree. NO workspace AUQ. Echo the continue in plain English — translate the matched signal to its meaning, never surface the raw token (REVIEW_HANDOFF → "a review just produced findings for this branch"; DEBUG_HANDOFF → "a debug run just authored reproduction tests for this branch"; RESOLVE_HANDOFF → "a PR-feedback triage just produced a fix plan for this branch"; EXISTING_TASK_STATE → "a prior task on this branch"; slug match → "the branch name matches this task"):
        "Continuing in worktree '<dir>' on '<branch>' — <plain-English reason>.
         <when a review or resolve handoff matched:> Any open questions from it will be resolved before code changes."
      Workflow Question 2 still asked if applicable (see 0c).

3. IN_WORKTREE == false
   AND PROTECTED_BRANCH == false
   AND any of {REVIEW_HANDOFF, DEBUG_HANDOFF, RESOLVE_HANDOFF, EXISTING_TASK_STATE} == true
   ⇒ When CONCURRENT_ACTIVITY is set, do NOT auto-continue in place — fire the full
      workspace AUQ (0c) with the recommendation flipped to "Git worktree (Recommended)"
      (an isolated worktree prevents a concurrent process from orphaning this run's commit
      via an external reset/rename on the shared working tree). Otherwise AUTO-CONTINUE on
      current branch, NO workspace AUQ. Echo (translate <signal> to the plain-English reason per rule 2's mapping — never the raw token):
        "Continuing on '<branch>' — <plain-English reason>.
         Reverse with: re-run with 'new-branch' modifier in arguments."
      Workflow Question 2 still asked if applicable.

4. IN_WORKTREE == true
   AND CURRENT_BRANCH ∉ continuing-work set
   ⇒ Fire 3-option AUQ (header: "Worktree mismatch"):
        A) "Continue here in '<dir>'" — recommended if user explicitly cd'd here
        B) "Exit to repo root and create new worktree '<new-slug>'" — call ExitWorktree, then standard new-worktree flow
        C) "Abort — I'm in the wrong place" — terminal, no-op
      Workflow Question 2 omitted (mismatch hint suggests confusion; don't pile on).

5. IN_WORKTREE == false, PROTECTED_BRANCH == true, no continuing signals
   ⇒ Fire the full workspace AUQ (0c). "New feature branch (Recommended)" stays default.

6. IN_WORKTREE == false, PROTECTED_BRANCH == false, no continuing signals
   ⇒ Fire the full workspace AUQ (0c). Recommendation flips: "Current branch (Recommended)" since the user is on a feature branch already — unless CONCURRENT_ACTIVITY is set, in which case the recommendation is "Git worktree (Recommended)" so a concurrent process mutating the shared working tree cannot orphan this run's work.
```

On any AUTO-CONTINUE path (rule 2, and rule 3 when it auto-continues — both skip the AUQ), apply Mode FRESH-CONTINUE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` right after the continue echo — offer to update a branch that is behind the default branch before Phase 1 begins. It skips silently when the branch is already current, and is skipped entirely on a compaction-resume (the branch was synced when the run first started).

**Inline modifier overrides** (parsed from `$ARGUMENTS` per the Phase 1 semantic-parse table; an explicit modifier wins over auto-detection, because the user's stated intent overrides an inferred signal):

| Modifier in $ARGUMENTS | Effect |
|---|---|
| `new-branch` / `new branch` | Force rule 5 path even if a "continuing" signal is detected. |
| `current-branch` / `current branch` | Force auto-continue regardless of signals. |
| `worktree` / `new-worktree` | Force worktree creation path. |
| `no-worktree` / `here` | Force in-place execution; skips worktree even if `IN_WORKTREE == false`. |
| `--no-adversarial` | Disables Phase 3 adversarial-tester spawn for this run (skips the adversarial-tester slot in Round 1). |
| `--deep` / `deep` | Sets `deep-mode: true` — the deeper Phase 1 + Phase 3 paths per `${CLAUDE_PLUGIN_ROOT}/skills/implement/deep-mode-reference.md`. |

Conflicting modifiers (e.g., `new-branch` AND `current-branch` both present): last-occurrence wins (right-to-left scan). Emit soft notice: `"Both 'new-branch' and 'current-branch' modifiers detected; using <last>."`

The full cross-skill catalog of modifiers and the spec `launch_config` block (workspace / ship / depth / freshness / tracker_status) lives in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flags-reference.md`.

#### 0c — Setup questions

Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Step 0 setup detail" before firing this AUQ — it carries the `approvals[]` entry shapes, the edge-case behaviors (0f), and the spec `launch_config` field map (0g); the literal question templates live in §"Phase 1: Step 0c setup-question templates".

Single `AskUserQuestion` call carrying up to 4 questions (always-WAIT, never auto-resolve). When a spec `launch_config` pre-answered a question (Step 0g), drop that question from the batch — the pre-set is its answer; if `launch_config` pre-answers every question that would otherwise fire, the AUQ does not fire at all.

**Question 1 — always asked when rules 5 or 6 fire** (header: `"Git workspace"`) — offers "New feature branch (Recommended)" / "Current branch" / "Git worktree"; literal template in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Step 0c setup-question templates".

**No-ticket-ID sub-flow.** When BRANCH_FORMAT_RULE requires a ticket prefix AND `TICKET_ID_IN_SCOPE` is empty, the agent cannot derive a conformant slug. Chain a sub-AUQ BEFORE Question 1 fires (or BEFORE the worktree command runs if Question 1 has already resolved to "New feature branch" / "Git worktree") — options: provide the ticket ID inline / use a placeholder slug (`<type>/no-ticket-<desc>`, renameable later) / cancel (terminal, no git mutation); literal template in the same reference section. This AUQ does NOT include a "create the ticket for me" option — /geniro:implement never creates tracker artifacts (`SKILL.md` §Anti-rationalization, the tracker-mutation-authority row).

**Question 2 — conditional on workflow_refs OR `.geniro/workflow/*.md` having an `### On task start` section:**

Build the workflow-refs-to-process list from a tracker URL/ID in `$ARGUMENTS` plus the spec.md frontmatter `workflow_refs[]`, deduplicated by `(kind, issue_id)` — the `$ARGUMENTS` reference wins a collision, because the user just typed it.

For each entry, find the workflow file with primary-worktree fallback per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A — try `./.geniro/workflow/<ref.kind>.md` (cwd-local; uncommitted local edits win) first; on file-not-found retry against `<PRIMARY_ROOT>/.geniro/workflow/<ref.kind>.md`. If both missing → log warning + skip (graceful degrade). Staleness check: if `fetched_at` is > 1 hour old OR absent → re-fetch via MCP (timeout 3s, fail-open) — the refresh ALSO updates the cached `status` field. Resolve the current `status` (re-fetched value, or cached when fresh) BEFORE applying the workflow block — the workflow file's `### On task start` section gates its question shape on that field (e.g., the Linear template skips the "Move to In Progress?" prompt when status is already "In Progress", rephrases to "Move back?" when in non-terminal non-In-Progress states, and reframes as "Reopen?" when terminal). Apply the workflow file's `### On task start` block — it may append 0-2 questions to the AUQ batch depending on resolved status and assignee fields. Echo any "skipped — already in target state" cases to the user inline (not as an AUQ).

The workflow file IS the source of truth for question text, options, AND status-conditional branching — do NOT hardcode "Linear" / "Jira" labels, and do NOT bypass the status check by firing the prompt unconditionally.

When the spec's `launch_config.tracker_status` is set (applied at Step 0g), it pre-answers this workflow-status question — `/geniro:implement` auto-applies the answer the workflow file's `### On task start` block would have asked for, still subject to that block's status-conditional gate (a pre-set `move-to-in-progress` is skipped when the task is already In Progress and reframed/omitted in other states), so the question does not fire interactively. The pre-set is a no-op when no tracker ref is in scope, and fail-open when the workflow MCP is unavailable (logs a warning and proceeds without the transition — same as an interactive "Yes").

If the batch exceeds 4 questions — `1` (workspace, when rules 5/6 fire) + `N` (workflow) + `1` (depth, when `--deep` is absent) > 4 — chain into a second AUQ.

**Question 3 — implement depth (fired when `$ARGUMENTS` lacks `--deep`)** (header: `"Implement depth"`) — "Standard" (one fact-check pass, one self-review pass) vs "Deep — 3× fact-check + multi-angle self-review"; literal template in §"Phase 1: Step 0c setup-question templates". Question 3 joins the Step 0c question batch whenever that AUQ fires and `--deep` is absent, and counts toward the batch-exceeds-4 chain rule above. Neither option carries `(Recommended)` — Deep is costlier, not safer. An empty answer is an upstream tool bug, not a Standard pick: re-ask per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions rather than defaulting. Only the path where this question never fires at all — an auto-continue or resume, where Step 0c is skipped — falls back to flag-only Standard (`deep-mode: false`). Activation and that flag-only fallback: `SKILL.md` §State persistence.

#### 0d — Approvals-persistence

Persist the workspace and workflow-status answers to state.md `approvals[]` (entry shapes: reference §"Phase 1: Step 0 setup detail"). The depth pick (Question 3) is NOT written here — it is materialized once at Step 4, so the depth choice lives in exactly one place.

On compaction-resume, Step 0 reads `approvals[]` and re-applies prior answers without re-prompting.

#### 0e — Execution after the setup questions

1. **Workspace action** — execute branch creation / worktree create / no-op per `implement_workspace_setup` pick (which a spec `launch_config.workspace` may have pre-answered at Step 0g). Slug source: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`. Branch and worktree creation cut from the latest default branch — apply Mode FRESH-BASE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` so the new working tree starts from the freshest default-branch tip rather than the current HEAD. For the "Current branch" (no-op) pick, apply Mode FRESH-CONTINUE from the same helper — offer to bring the branch up to date before Phase 1 proceeds. When `launch_config.branch_freshness` is set, pass it as the pre-chosen strategy so a clean fast-forward applies it without asking; a real conflict still surfaces interactively.
2. **Workflow status action** — for each persisted `implement_workflow_status` approval, follow the workflow file's `### On task start` instructions. Skill does NOT hardcode MCP call shape — workflow file owns that.
3. **State.md frontmatter update** — `branch:` and `worktree:` reflect the new working tree before Phase 1 continues.

#### 0f — Edge cases

Resolved by the table in reference §"Phase 1: Step 0 setup detail" (workflow MCP down · missing `### On task start` · an "Other" pick on Question 1 · several handoffs on one branch · a stale handoff · a worktree on a protected branch).

#### 0g — Apply spec `launch_config` (pre-answer setup)

When `SPEC_LAUNCH_CONFIG` is non-empty (a spec carried a `launch_config:` block), apply its fields per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` — each field pre-answers one Step 0 setup question, so the matching question does not fire; the enum values and per-field semantics are owned by that schema file. Absent block (no spec, inline-task run, or a pre-`m5-v4` spec without the block) ⇒ behavior is unchanged: every setup question fires interactively exactly as it does today.

Field → decision it pre-answers: the map in reference §"Phase 1: Step 0 setup detail". Two caller-side deltas the schema file does not own:

1. `workspace` does NOT override an active auto-continue / resume signal — when a continuing signal already skips the workspace question (decision-tree rules 1-3), that path wins; the plan-time pre-set is not a directive to abandon an in-flight workspace.
2. Record the applied choices in `approvals[]` the same way the interactive answers would — `implement_workspace_setup`, `deep_mode_choice`, `ship_mode`, and — when `tracker_status` was set — `implement_workflow_status` — each carrying `source: launch_config` so a compaction-resume re-applies them without re-asking.

**Doctrine — setup only, never safety.** `launch_config` pre-answers SETUP questions only; it does NOT pre-authorize the genuine safety gates, which stay Always-WAIT and fire only when actually triggered — the gate list + rationale: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"Doctrine boundary — setup only, never safety".

### Steps (after Step 0 settles)

1. **Semantic-parse `$ARGUMENTS`.** Apply the table in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: $ARGUMENTS semantic-parse table".
2. **Resolve spec source.** Walk the spec discovery list (`${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Spec discovery walk-list"). Its first entry follows a `spec_path:` in whichever handoff Step 0a flagged for this branch — that is the only route to a `/geniro:resolve` spec, which lives outside `.geniro/planning/`. If no handoff `spec_path:`, spec.md, plan.md, or DESIGN_DOC frontmatter is found AND $ARGUMENTS is non-empty → inline-task mode (write `## Inline Plan` to state.md body).
3. **Disambiguate if needed.** If $ARGUMENTS is ambiguous, fire AUQ per Phase 1 table. Persist outcome to state.md frontmatter `approvals[]` with `category: disambiguate_arguments`.
4. **Resolve task slug.** Used for state.md path. If task-dir exists, validate state.md (recovery AUQ on validation fail). If task-dir is fresh, `mkdir -p`. Write the resolved depth into the state.md frontmatter at creation: `deep-mode: true` when EITHER Step 1 parsed `--deep` OR the Step 0 Question-3 depth pick was Deep; `deep-mode: false` for a Standard / empty pick. Append the matching `{category: deep_mode_choice, picked: <deep|standard>, at: <ISO-8601 UTC>}` to `approvals[]` via `atomic_state_write` — the resolved depth must be persisted, not just held in working memory, so a compaction-resume re-applies it.
5. **Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: implement`, `LOAD_TIER: pipeline`, `MODE: refresh`. The helper's §Procedure prescribes imperative `Read` directives on every file in the pipeline load set; the §Echo contract requires one observable line per file. Both are mandatory.
6. **Load project snapshot.** Phase 1 entry only — Phase 3 does not re-load it.

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh"
   load_semantic # default: _project.md + _CODEBASE_MAP.md
   load_semantic --extras "_FEATURES.md" # if spec mentions feature backlog
   ```

   `load_semantic` has no MODE flag — the Reads and the fingerprint drift check fire unconditionally; a mismatched `.fingerprint.json` surfaces a drift notification to the user.
7. **Spawn knowledge-retrieval + codebase-explorer agents in parallel.** ONE assistant response — both `Agent(...)` tool calls together (just the codebase-explorer call when the store-empty gate below skips the knowledge-retrieval slot). Apply the spawn template in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Subagent spawn template" — first prime both spawns with the related-task chain context (parent epic + sibling tasks + neighboring milestones) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md`. Subagent model selection: follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Judgment-grade spawns OMIT `model=`; execution spawns pin `model="sonnet"` per its category 4. Spawn `subagent_type="geniro:<agent>"`; on `Agent type not found` or an empty (0-token) result, Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` and apply its ladder / empty-result fallback, then cache the resolved form for the session. Both spawns here OMIT `model=` — the frontmatter governs (codebase-explorer-agent declares `model: inherit`; knowledge-retrieval-agent declares `model: sonnet`, a mechanical-gather carve-out).

   **Store-empty gate on the knowledge-retrieval slot — a mechanical check every run evaluates fresh, continuations included.** The agent's sweep covers four sources (past learnings, project snapshots, prior handoffs, prior task plans); spawn it when ANY of them holds content, skip it only when ALL are empty:
   - `<PRIMARY_ROOT>/.geniro/knowledge/` contains any file (a non-empty `learnings.jsonl` or an archive);
   - any `<PRIMARY_ROOT>/.geniro/state/handoff/from-*.md` exists;
   - any `<PRIMARY_ROOT>/.geniro/planning/_*.md` snapshot exists;
   - any `<task-dir>/plan-*.md` prior plan exists;
   - OR `memory.md` (loaded at Step 5) declares a `## Memory Backend` block — backend-routed learnings are invisible to a directory check, which is exactly why this condition exists.

   The gate reads the store, never the orchestrator's own context — "I already hold this from an earlier run" satisfies no bullet, and the continuation-run anti-rationalization rule in `SKILL.md` stands unweakened. On skip, say so in plain English and record `Knowledge sweep: skipped — memory store empty` in the state.md body (with the Step 13 write), so downstream steps read skipped-empty rather than failed. The codebase-explorer spawn is unconditional.

   **Backgrounding when a handoff gate is pending:** when Step 0a flagged a review, debug, or resolve handoff for this branch (`REVIEW_HANDOFF` / `DEBUG_HANDOFF` / `RESOLVE_HANDOFF`) that carries unresolved open-questions, spawn both agents `run_in_background: true` and run the Step 12 open-questions gate (sub-steps 1-7) during their compute — procedure in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Backgrounding when a handoff gate is pending". Otherwise — the common case, no such handoff — spawn both BLOCKING exactly as before.
8. **Read subagent outputs — drain point.** Confirm every spawned agent returned before reading: `Read` `<task-dir>/.kr-out.md` and `<task-dir>/.ce-out.md`, or resume by ID when the output file has not yet landed. When the Step 7 store-empty gate skipped the knowledge-retrieval spawn, `.kr-out.md` legitimately does not exist — drain `.ce-out.md` alone and skip the failure handling for that slot. When Step 7 backgrounded the agents, this drain is the first step that consumes their output — it must not proceed until both have returned (reference §"Backgrounding when a handoff gate is pending"). The codebase-explorer's `change_scope` field gates the Phase 3 adversarial-tester spawn (`trivial` → skip). Failure handling for either agent: on missing/empty output OR `Agent` tool error, one silent retry; second failure → inline-Read fallback (load top-3 exemplar files + `_CODEBASE_MAP.md` rows by Grep) with `change_scope: medium` as safe default. Emit a `diagnosis` learning with `trust: retrieved`. Echo notice to user.
8.5. **Library reuse audit (build-vs-buy).** For each codebase-explorer `NO-ANALOGUE` component, when `change_scope` is small / medium / big (skip trivial), apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/library-reuse-audit.md` with MODE: implement — a web-research agent finds candidate libraries in the project's detected ecosystem, filters them (existence-verified against the real registry), and a message-first confirmation gate requires explicit approval before any library is adopted (persists `approvals[]` category `library_adoption`). Skip silently when there is no package manifest or no NO-ANALOGUE component; fail-open on a research/registry error.
9. **Query past learnings.**

    ```bash
    source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh"
    query_learnings --tag <inferred-tag> --scope <task-path> --limit 5
    ```

    Route per the memory-backend override in `SKILL.md` §Memory I/O — a declared backend redirects this read to its own read tool, and under `mode: replace` the local file is empty. Tags are inferred from the task description (e.g. `react`, `auth`, `bug`) and may be primed by the knowledge-retrieval output; skip when the description is too generic. `query_learnings` has no MODE parameter — calls are idempotent.
10. **Resolve cross-layer conflicts.** When the custom instructions, project snapshot, and past learnings disagree, follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md`: a **soft conflict** prints the `emit_conflict_notice` text and continues on the precedence-winning value; a **hard conflict** (a custom-instruction rule contradicts project reality) halts and calls `hard_conflict_block` + `AskUserQuestion` to surface it to the user.
11. **Detect frontend files in scope.** Use the codebase-explorer "Likely-Touched Files" report against the UI-file detection rule (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §UI-file detection rule). Gates Pre-Ship Visual Verification.
12. **Persist review / debug / resolve handoffs AND gate on unresolved open questions.** When Step 7 backgrounded the agents, sub-steps 1-7 already ran during the knowledge-retrieval / codebase-explorer wait (per the reference §"Backgrounding when a handoff gate is pending", including its persist-in-the-pick-turn rule) — do NOT re-run them; run sub-steps 8-11 here. Otherwise run all sub-steps in order here. Either way the Edit/Write boundary is unchanged: every unresolved entry must be resolved before transitioning to `phase: implement`, regardless of when it was asked. For every `<PRIMARY_ROOT>/.geniro/state/handoff/from-<producer>-<branch>.md` that exists:
    1. Read the handoff file with the `Read` tool (or Bash `cat`).
    2. Persist the body under state.md `## Inputs from <producer>` body section.
    3. Parse frontmatter `open_questions[]` per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2. Also read `report_status` (review handoffs): an explicit `report_status: draft` (missing reads as `final` per the state-tier-spec back-compat rule) means `/geniro:review` did not finish its decision gates — the handoff is not yet finalized. Surface a one-line warning ("the review handoff is still a draft — its decisions weren't finalized; resolving the open questions below completes it") and require the unresolved-open-questions gate (sub-steps 4-5) to clear before transitioning to `phase: implement`. The draft marker is a signal, not a separate block — the `open_questions[]` gate is the actionable resolution.
    4. Filter to entries with `status: unresolved`. A handoff carrying no `open_questions` key at all is not an empty list, and what a missing key obliges is in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 — resolve it before this run edits anything.
    5. **If the filtered list is non-empty, fire an AUQ batch BEFORE transitioning to `phase: implement`.** Chain one AUQ per unresolved entry (cap-extension when >4). Apply the 3-tier rendering procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.5 — it renders each question as a self-contained chat message first, then a lean question, per the shared finding-gate contract (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering); which tier fires depends on the producer fields the entry carries (single-sourced in §2.5 — don't restate them here). When the entry carries `related_comments` (a `/geniro:resolve` handoff — the review-thread id(s) that raised the question), name that thread in the render's conversational lead and quote the matching `comment_resolutions[]` entry from the handoff body already read at sub-step 1: the user is being re-asked a question a reviewer raised, and the review comment is the context that makes it answerable. Set `resolution.asked_in_phase: phase-1-step-12` and `resolution.resolved_by: implement` when persisting answers (vs §2.5's `phase-6-pre-gate` / `review`).
    6. After each user pick, round-trip the update into the PRODUCER's handoff file via `atomic_state_write`: set `status: resolved` plus `resolution.picked` / `.at` / `.asked_in_phase: phase-1-step-12` / `.resolved_by: implement` on that entry, and re-emit the file's ENTIRE original content around it — the helper overwrites rather than merges, so every other frontmatter key and body section the producer wrote must survive byte-for-byte or the write silently truncates state a downstream consumer (including sub-step 9's `authored_tests[]` read) depends on. Per-producer key inventory: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Handoff round-trip write".
    7. Persist a parallel approval to state.md `approvals[]` with `category: review_handoff_resolution`, `picked: <chosen option>`, `at: <ISO-8601 UTC>`, `source_handoff: <producer>`, `question_id: <id>` for compaction-resume idempotency.
    8. After all entries are `resolved` or `wontfix`, proceed to sub-step 9.
    9. **Extract authored F→P tests when the handoff is from `/geniro:debug`.** Skip when `<producer>` is anything other than `debug` (e.g., `review`); fire only for `from-debug-<branch>.md` and `from-debug-adversarial-<branch>.md`. Apply the canonical Scan/Extract/Verify/Decide protocol in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md`:
       - **Extract** — prefer frontmatter `authored_tests[]` (m7-v2+); fall back to body `**Reproduction test:**` / `**Test file:**` parse for legacy m7-v1 handoffs.
       - **Verify** — resolve each path against this skill's current `git rev-parse --show-toplevel` and bucket as PRESENT / MISSING.
       - **Decide and surface** — Case A (all PRESENT, debug-source-branch matches) → one-line acknowledgment in the Phase 1 context summary. Case B1 (any MISSING) → surface the suggest-only relocation block from `_shared/debug-handoff.md` §Step 4; the user runs `git checkout <debug-source-branch> -- <paths>` or `cp` themselves — never auto-execute cross-branch git operations. Case B2 (all PRESENT but branches differ) → one-line "tests carried over" note. Case C (legacy fields missing) → degraded suggestion without explicit checkout command.
       - **Persist** to state.md as `Authored-tests:` (comma-separated relative paths on a single line) plus, when sourced from m7-v2+ frontmatter, `Authored-tests-intent:` (parallel comma-separated intents) and `Debug-source-branch:` / `Debug-source-worktree:`. Phase 2 reads these to prime TodoWrite decomposition — each authored test becomes a pre-existing acceptance gate, surfacing in the relevant todo's description so the production-fix work cannot ship without those tests going GREEN.
       - Authored-tests extraction is informational, NOT a gate — do NOT block transition to `phase: implement` on missing files. The user retains agency to either run the suggested commands, re-author tests in the current branch, or accept the divergence.
    10. **Stash `/geniro:resolve` comment-resolutions.** When `<producer>` is `resolve`, also parse the handoff's `comment_resolutions[]` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §`/geniro:resolve` producer fields) and persist it to state.md under `## Inputs from resolve` for the Phase 3 Ship "Resolve PR review threads" sub-step. It is informational, NOT an Edit/Write gate — only `open_questions[]` blocks editing; a `fix` whose thread is closed later still flows through the normal fix loop.
    11. After authored-tests and comment-resolutions handling, proceed to step 12.5.

   /geniro:implement is the consumer; the contract per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 forbids proceeding with Edit/Write while any `unresolved` entry remains. A consumer that ships anyway violates the contract — the producer surfaced the ambiguity precisely so it gets resolved BEFORE code changes.

12.5. **Spec challenge — fact-check the spec against the current code before editing.** The last gate before code edits begin.

   - **Spec-driven mode only.** Run this step only when Step 2 resolved a real spec.md / plan.md / DESIGN_DOC. SKIP it in inline-task fallback mode — there is no written spec to fact-check, so emit a one-line note ("No spec file — skipping the spec fact-check") and proceed to step 13.
   - **Invoke the helper.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` with MODE: implement, SPEC_PATH: \<resolved spec path>, TASK_DIR: \<task-dir>, EFFORT_TIER: \<the codebase-explorer change_scope>, DEEP: \<true when state.md deep-mode: true, else false>. Verdict handling — the skip-when-clean advisory and, on `defects-found`, the message-first render (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering) followed by the lean AskUserQuestion with options "Proceed anyway" / "Fix the spec, then proceed" / "Abort — re-plan via /geniro:plan" — is owned by that file's §8.
   - **Persist the pick.** Record the user's choice in state.md frontmatter `approvals[]` with `category: spec_challenge`, `picked: <chosen option>`, `at: <ISO-8601 UTC>` for compaction-resume idempotency.
   - **Fail-open.** If the helper or any verifier spawn fails, write a line to state.md `## Errors`, emit a one-line notice to the user, and proceed to step 13 — a fact-check failure does not hard-block the run.

13. **State.md write.** `atomic_state_write` with `phase: analyze` body sections populated → upon completion, transition `phase: implement`.

**Workflow plumbing.** Workflow integrations (`.geniro/workflow/*.md`) apply their argument-detection patterns BEFORE the semantic-parse table. Non-blocking — log warning if integration backend unavailable.

### Big-task notice

When Codebase-Explorer reports `change_scope: big` AND no `milestone-*.md` files exist alongside spec.md, emit one informational notice (NOT AUQ — just observation):

```
This is a large change. Consider running /geniro:plan in milestone mode to
split it into separate milestone files before implementing. This run will
proceed as a single pass with a step-by-step task list; splitting is cleaner.
```

Milestone-mode is the canonical answer for truly Big tasks (separate worktrees, separate /geniro:implement runs). User may cancel and re-run `/geniro:plan` on this task — /geniro:plan emits milestone files automatically when it classifies the task as Big; otherwise the run proceeds.
