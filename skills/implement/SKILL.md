---
name: geniro:implement
description: "Use when shipping a new feature, endpoint, page, or significant change against a spec.md / plan.md (from /geniro:plan) OR a raw inline task description. 3-phase autonomous loop: Analyze → Implement → Self-review-and-Ship. Optional --deep deepens two phases — a 3× self-review with 3-vote majority verification of findings, and a 3× fact-check of the spec's cited claims before editing (higher quality, higher cost)."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, EnterWorktree, ExitWorktree, Workflow]
argument-hint: "[task description | spec.md path | empty to resume | 'continue'] [--deep]"
---

# Implement Skill — 3-Phase Autonomous Loop

You are an autonomous executor. You consume an externally-provided spec (or inline task description), make all required code edits, run the test suite, then run a parallel self-review pass before shipping. Strategic concerns belong upstream in `/geniro:plan`. Single orchestrator owns Phase 2 code-edits — no parallel code-editing subagents.

**Phases:**

1. **Analyze (Phase 1)** — Step 0 workspace setup AUQ (with auto-continue for in-worktree fix-up runs); semantic-parse `$ARGUMENTS`; resolve spec source (spec.md / plan.md / DESIGN_DOC frontmatter OR inline-task fallback); refresh custom instructions + project snapshot; spawn knowledge-retrieval and codebase-explorer agents in parallel; query past learnings; persist review/debug handoffs to state.md; fact-check the spec against the current code before any edit (spec-driven mode only).
2. **Implement (Phase 2)** — TodoWrite sequential decomposition (3-15 todos, one in_progress at a time); per-todo Edit/Write batch; end-of-phase test-suite run via `test-runner-agent`; bounded 3-retry fix loop on test failure → escalate-AUQ on exhaust.
3. **Self-review + Ship (Phase 3)** — reviewer-agents in parallel (bugs / security / architecture / tests / code-quality) + 1 adversarial-tester-agent (skipped when codebase-explorer reports `change_scope: trivial` OR when `--no-adversarial` modifier is present in `$ARGUMENTS`) + any custom dimensions discovered via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` (`.geniro/instructions/review-extra/<slug>.md`, ≤10 cap, path-filtered); bounded 3-round fix loop, round N+1 = failing dims only; on clean exit, ship sub-step (Pre-Ship Visual Verification if applicable, commit, ship-mode AUQ, learnings + snapshot writes, cleanup).

**Reference material** (templates, $ARGUMENTS-parse table, subagent spawn templates, fix-loop, ship sub-step): Read `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` AT each phase. Do NOT pre-load the entire file.

---

## State machine

State.md frontmatter `phase:` transitions (alignment-immune table; `from-phase → to-phase | trigger`):

| From | To | Trigger |
|---|---|---|
| (entry) | analyze | Phase 1 start |
| analyze | implement | spec parsed, handoffs resolved |
| analyze | (analyze) | surface failures inline; no separate escalation state |
| implement | self-review | Phase 2 todos done, tests green |
| implement | phase-2-escalated | test fix-loop exhausted / not converging |
| phase-2-escalated | debug-handoff | user picked "escalate to debug" (terminal) |
| phase-2-escalated | self-review | user picked "accept failures" |
| phase-2-escalated | aborted | user picked "abort" (terminal) |
| self-review | ship | happy path — review clean |
| self-review | self-review-only | "stop after review" modifier — exit before commit (terminal) |
| self-review | phase-3-escalated | review fix-loop exhausted / not converging |
| phase-3-escalated | debug-handoff | user picked "escalate to debug" (terminal) |
| phase-3-escalated | ship | user picked "accept findings" → `## Accepted Findings` body block |
| phase-3-escalated | aborted | user picked "abort" (terminal) |
| ship | done | committed + pushed + PR (terminal) |
| ship | ship-committed-only | "don't push" / "no push" / "commit only" modifier (terminal) |

Each `git push` / `gh pr create` / posted comment appends to `non-resumable-actions[]` as it fires.

**Terminal states**: `done`, `ship-committed-only`, `self-review-only`, `debug-handoff`, `aborted`. Every transition into a terminal state runs the transient cleanup in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Cleanup" before the terminal `phase:` write — leftover transient files in a finished task-dir resurface as recurring migration warnings on every plugin update.

**Non-terminal states**: `analyze`, `implement`, `self-review`, `ship`.

**Escalation (paused) states**: `phase-2-escalated`, `phase-3-escalated` — a fix-loop exhausted and an AUQ is open. On resume the recovery re-surfaces "task was paused — last AUQ options" so the user re-picks without losing context (mirrors /geniro:debug's escalation states).

**Termination reason convention.** When `phase: aborted` is reached, write one line to state.md body under `## Termination reason`: `repeated-failure: phase-N retry-limit` / `safety-denied: <rule>` / `tool-unavailable: <tool>`. The SessionStart hook re-injects this on resume.

---

## Loop invariants

Apply throughout all 3 phases. Invariants 1-7 are the canonical agent-loop set (stated generically in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`, which `/geniro:onboard` and `/geniro:investigate` cite); 8-10 are implementation-specific:

1. **One result per tool call.** Every Edit / Write / Bash / Agent spawn produces exactly one structured result. Failed spawn → result with `status: failed`; never absent.
2. **Args validated before execution.** Bash commands constructed from $ARGUMENTS or state.md fields pass input sanity-checks. Paths absolute; slugs match the rules in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`.
3. **Permission before side-effect.** Any tool call mutating external state (`git push`, `gh pr create`, posted PR comment) is preceded by AUQ approval or recorded approval (persisted via schema).
4. **Bounded and structured tool results.** Reviewer-agent output capped at ~4000 chars per dimension; longer truncated with marker. Bash output >8000 chars summarized before downstream use.
5. **Escalation gates, not silent abort.** Bounded retry loops (3 rounds in Phase 2, 3 rounds in Phase 3) surface to user via `AskUserQuestion` at exhaustion — and earlier when the loop is not converging (no forward progress across two checkpoints, the same failure recurring, or cost/scope drift past the codebase-explorer effort tier OR the user's spec-declared `budget` per the §PHASE 2 Step 6 trigger list). The scope-drift trigger set is shared across both Phase 2 and the Phase 3 fix loop and dedupes so it fires once per run. Never silent abort, never infinite loop, never spend the full retry budget against an unmoving wall.
6. **Final answer grounded in observations.** Phase 3 Ship result text MUST quote actual tool output (push ref, PR URL, commit SHA) — never "git push succeeded" without evidence. Self-review reads `## Tool log` entries before claiming clean state.
7. **Errors, denials, cancellations, timeouts → structured observations.** Failed `gh pr create`, denied permission, hook-blocked Write, subagent timeout, non-zero Bash exit becomes a structured observation entry — never silently skipped.
8. **Investigation reads delegated to subagents.** Phase 1 inline-Reads only L4 instructions (3 files), L3 semantic snapshot (2 files), spec.md body, and state.md. `.claude/rules/*.md` bodies, exemplar source files, L2 learnings entries, and prior plans are spawned out to Knowledge-Retrieval + Codebase-Explorer subagents and read back as condensed reports. Inline-reading the rest is the documented context-bloat regression. The two primary Phase 1 subagent spawns are the plugin-defined `knowledge-retrieval-agent` and `codebase-explorer-agent` (implementation-specific — takes a spec.md, produces REUSE/EXTEND/NO-ANALOGUE inventory). For ad-hoc cross-file research inside Phase 2 (per-step "trace this flow" / "find all sites that call this helper" queries that aren't covered by Codebase-Explorer's Phase 1 inventory), spawn `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.
9. **One todo in_progress at a time.** Phase 2's TodoWrite decomposition enforces sequential focus. Marking a second todo `in_progress` while another is open is the documented anti-pattern (Claude Code Tasks API enforces single in_progress by design; parallel sequential reasoning shows measured performance drop).
10. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research. (Phase 1's `codebase-explorer-agent` is the implementation-specific spec-scoping spawn per Invariant #8; this invariant covers ad-hoc cross-file research in Phase 2 and elsewhere.)

**Turn-completion check (canonical, un-numbered).** Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check: never stop on a statement of intent or an announced-but-unfired question — at every gate the render is followed immediately by its lean `AskUserQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard, and an answered question is continued with the next action, never a silent stop.

**Side-effect — `## Tool log` section in state.md.** Invariants 1 and 7 motivate persisting subagent-spawn outcomes and side-effect tool calls (`git push`, `gh pr create`, file deletions) into a body section per `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling" (the "Tool log persistence." paragraph). Routine Read/Edit/Bash on local files do NOT need logging — Claude Code's tool_result return is sufficient.

---

## Budgets — quality-first framing

No hard kill caps. No wall-time / tool-call / model-turn / cost ceilings. User tokens unlimited.

**Quality gates (Class-B — escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Fix-loop retries per phase | 3 | (Phase 2 test fix), (Phase 3 review round) | AUQ — debug-handoff / accept-failure / abort. User picks. Fires early (before 3) when the loop is not converging — see §PHASE 2 Step 6 early-escalation triggers. |
| Reviewer output size | ~4K chars per dim | invariant #4 | Truncation with marker, NOT abort. |

**Architecture constraints (design intent, not budget):**
- Parallel spawns at Phase 3 Round 1: reviewer-agents (`bugs` / `security` / `architecture` / `tests` / `code-quality`) + 1 `adversarial-tester-agent`, unless `change_scope: trivial` or `--no-adversarial` modifier strips the adversarial slot. Custom reviewer dimensions from `.geniro/instructions/review-extra/` append to the same batch (≤10 cap, path-filtered).
- Parallel spawns at Phase 1 Step 7: 2 subagents (`knowledge-retrieval-agent` + `codebase-explorer-agent`).

**Explicitly NOT capped:**
- Wall-time per run. Complex implementation can take hours.
- Total tool calls per phase. Large refactors easily exceed 100 calls; no cap.
- Total model turns per phase. Multi-file work needs many turns.
- Total cost per run. Deferred to if a cost-aware mode is opted into.

---

## State persistence

**Task directory**:

```
.geniro/planning/<task-slug>/
```

Where `<task-slug>` is derived from $ARGUMENTS / spec.md filename / git branch per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`. Created at start of Phase 1.

**State.md frontmatter:**

```yaml
---
tier: T1.5
producer: implement
schema-version: 1
branch: <git-branch>
worktree: <git-rev-parse-show-toplevel>
timestamp: <ISO-8601 UTC>
phase: <state-machine-enum>
status: in-progress
non-resumable-actions: [] # appended after each git push / gh pr create / posted comment
approvals: [] # appended after each one-time AUQ resolution
deep-mode: <true|false>   # set by the --deep flag (Phase 1 parse); missing reads as false
---
```

When `deep-mode: true`, Phase 1 (spec fact-check) and Phase 3 (self-review) run their deeper paths per `${CLAUDE_PLUGIN_ROOT}/skills/implement/deep-mode-reference.md`; persist the activation to `approvals[]` category `deep_mode_choice`. When `--deep` is absent, a Standard/Deep depth question folds into the Step 0 workspace AUQ (Question 3); pick Deep there to set `deep-mode: true`, or it stays flag-only on the auto-continue/resume paths where Step 0's AUQ does not fire.

**Write contract.** Route every state.md mutation through `atomic_state_write` (cited from `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh`) — a direct `Edit` or `Write` on a canonical state path bypasses the helper and corrupts the file mid-crash. The State-helper enforcement hook warns on such a direct write (warn-mode initially; it flips to a hard-block in a future release).

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write ".geniro/planning/<task-slug>/state.md" <<'EOF'
---
<frontmatter>
---

<body sections>
EOF
```

**Validation before resume.** When Phase 1 detects a pre-existing state.md (resume path), pre-flight via `validate_state_file`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh"
if ! validate_state_file ".geniro/planning/<task-slug>/state.md"; then
# Open recovery AskUserQuestion (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency)
...
fi
```

---

## Memory I/O

### Phase 1 entry inventory

Phase 1 entry runs Step 0 first (workspace setup — see §PHASE 1 Step 0 below), then six helper calls — two L4/L3 reads, two subagent spawns (Knowledge-Retrieval + Codebase-Explorer), one L2 query, one cross-layer protocol:

0. **Step 0 workspace setup** — passive context detection followed by 1-2 question AUQ (skipped on auto-continue path). Fires BEFORE any L4/L3/L2 helper call; workspace decision determines the worktree the rest of Phase 1 inspects.
1. **Load custom instructions** — `load-custom-instructions` with `MODE: refresh`; see §L4 below.
2. **Load the project snapshot** — `load-semantic` with `MODE: refresh`; see §L3 below.
3. **Knowledge-Retrieval subagent spawn** — parallel with Codebase-Explorer; reads back from `<task-dir>/.kr-out.md`. See §Phase 1 subagent spawn.
4. **Codebase-Explorer subagent spawn** — parallel with Knowledge-Retrieval; reads back from `<task-dir>/.ce-out.md`. See §Phase 1 subagent spawn.
5. **Query past learnings** — `query-learnings`; see "past learnings" sub-section below. Tags may be primed by the knowledge-retrieval agent's output.
6. **Cross-layer conflict resolution** — `resolve-conflicts`; see §Cross-layer conflict surfacing. Fires only if disagreement detected after the reads.

Phase 2 makes no new helper calls at entry; per-Edit `.claude/rules/*.md` JIT loads fire only when an Edit target matches a rule path returned by Codebase-Explorer (cache scope: Phase 2). Phase 3 entry re-fires `load-custom-instructions(MODE: refresh)` AND fires `load-custom-reviewers` once (round 1 only) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` — spawn-specs are appended to the parallel reviewer batch alongside the 5 built-ins and the adversarial-tester. Phase 3 fix-loop iterations may re-fire `query-learnings`. Phase 3 ship sub-step adds writes: `emit-learning` (L2), `update-semantic` (L3 bounded append), and `atomic_state_write` (state.md frontmatter `non-resumable-actions[]`).

### L4 — Custom instructions (procedural)

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: implement`, `LOAD_TIER: pipeline`, `MODE: refresh`. The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `implement.md`, and `code-style.md` (3 files); its §Echo contract requires one observable line per file. Both are mandatory.

**Phase boundaries:**
- Phase 1 entry — `MODE: refresh` — scope = `implement` + `global` + `code-style` (3 files). `refresh` re-Reads every file and re-emits the Echo lines; the procedure is identical to initial-load. The mode name signals compaction-survival intent.
- Phase 3 entry — `MODE: refresh` on every run, because the re-read survives any Phase 2 compaction. Cost: 1 extra helper read.

The Echo contract survives compaction via the SessionStart hook re-injection.

### L3 — Semantic snapshot

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh"
load_semantic # default: _project.md + _CODEBASE_MAP.md
load_semantic --extras "_FEATURES.md" # if spec mentions feature backlog
```

**Phase 1 entry only.** `load_semantic` has no MODE flag — every Read fires unconditionally, fingerprint drift check fires unconditionally. Drift notification surfaces to user if `.fingerprint.json` mismatched. Phase 3 does NOT re-load L3 (Phase 2 doesn't materially mutate L3 — `update-semantic` writes are bounded to single-line append on `_CODEBASE_MAP.md`).

### L2 — Episodic event log

**Read (Phase 1 entry):**

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh"
query_learnings --tag <inferred-tag> --scope <inferred-scope> --limit 5
```

Tags inferred from task description (e.g., `react`, `auth`, `bug`); skipped if task description is too generic. `query-learnings` has no MODE parameter — calls are idempotent.

**Read (Phase 3 fix-loop):**

```bash
query_learnings --tag <inferred-tag> --scope <changed-file-path> --limit 5
```

Used to prime reviewer-agent prompts with known conventions/pitfalls.

**Write (Phase 3 ship sub-step, auto-emit):**

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
echo '{"type":"convention","scope":"...","summary":"...","tags":[...],"trust":"verified"}' | emit_learning
```

Triggers:
- `type=convention` → when Phase 3 architecture or code-quality reviewer reports ≥3 instances of same pattern.
- `type=decision` → when spec.md records a non-trivial approach choice with `## Considered Alternatives` (inline-task path; /geniro:plan emits decisions directly when it owns the upstream step).

Default trust = `verified` (Phase 3 findings are test-validated on entry).

Promotion suggestion fires ONLY for `convention` emits — see reference.md §"Extract Learnings". Echo `Recorded learning: <summary>` after a successful emit and fire it before the Ship-mode AUQ, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract".

### L3 — Bounded write (Phase 3 ship sub-step)

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/update-semantic.sh"
update_semantic --file codebase-map --append "- <path> — <short description>, used by <consumer>"
```

Fires when Phase 2 added a new module. Lock-guarded; rc=11 (lock held) is a recoverable skip-and-defer.

### Cross-layer conflict surfacing

When L4/L3/L2 reads disagree, follow the protocol in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md`:
- **Soft conflict:** print `emit_conflict_notice` text, continue using precedence-winning value.
- **Hard conflict (L4 rule contradicts L3 reality):** halt, call `hard_conflict_block` + `AskUserQuestion` to surface to user.

---

## ACI per-phase tool surface

| Phase | Allowed | Blocked |
|---|---|---|
| **Phase 1 (Analyze) — orchestrator** | Read / Grep / Glob / Bash (`git status`, `gh pr view`, `git worktree add`, `git checkout -b`, and the Step 0 freshness commands `git fetch` / `git merge` / `git rebase` / `git stash` / `git pull --ff-only` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`); Agent spawns for `knowledge-retrieval-agent` + `codebase-explorer-agent`, plus the read-only spec-claim verifier spawns fired by the Step 12.5 spec-challenge gate per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md`; Workflow (`deep-mode: true` only — the internal 3× / 3-vote fan-out for the Phase 1 spec-check and Phase 3 self-review, OMIT `model=`) | Edit / Write on source code; `gh pr create`; commit; Phase 3 agent types |
| **Phase 1 subagents** | Per agent frontmatter `tools:` whitelist — see `agents/knowledge-retrieval-agent.md` and `agents/codebase-explorer-agent.md` | Edit / Write (except their own OUTPUT_PATH); Agent (leaf agents, no nesting) |
| **Phase 2 (Implement) inner loop** | Read / Grep / Glob / Edit / Write / Bash (incl. test runs); `test-runner-agent` spawn at end-of-phase | `git push`, `gh pr create`, `gh pr comment`, Phase 3 agent types |
| **Phase 2 test-runner-agent** | Bash (one test-suite invocation), Read, Grep — enforced by `agents/test-runner-agent.md` frontmatter | Edit / Write on source code; git mutation; destructive Bash; Agent (leaf agent) |
| **Phase 3 reviewer-agent spawns** | Per dim: Read / Grep / Glob / Bash (read-only) — enforced by `agents/reviewer-agent.md` frontmatter `tools:` whitelist | Edit / Write / Agent / mutating Bash / external network |
| **Phase 3 adversarial-tester-agent spawn** | Read / Write / Edit (restricted to test-file paths) / Bash (read-only) / Glob / Grep — enforced by `agents/adversarial-tester-agent.md` frontmatter `tools:` + Critical Constraints | Production-source edits; git mutation; destructive Bash; Agent (leaf agent) |
| **Phase 3 Ship sub-step** | `git commit`, `git push` (draft-grade — auto on a feature branch with no open PR; commit-grade confirm on a default/shared branch, or on a feature branch with an open PR when the run was entered via a /geniro:review or /geniro:debug handoff — an upstream "apply the findings" pick authorizes editing, not shipping), `gh pr create` (commit-grade — AUQ-gated) | External commits before AUQ resolution |

**Existing safety layer:** file-protection hook, git-guardrail hook, and `.geniro/` deletion guard apply across ALL phases regardless of this matrix.

---

## PHASE 1: ANALYZE

State.md `phase: analyze` on entry.

**Resolve `PRIMARY_ROOT` once at Phase 1 entry.** Run the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` via Bash. Phase 1 reads handoffs at `<PRIMARY_ROOT>/.geniro/state/handoff/from-*-<branch>.md`, targeted-reads `<PRIMARY_ROOT>/.geniro/instructions/global.md` for the branch-format rule at Step 0a, and spawns knowledge-retrieval + codebase-explorer agents whose spawn-prompt slots (`KNOWLEDGE_ROOT`, `PLANNING_ROOT`, `HANDOFF_DIR`) require this value substituted to absolute paths per Mode B. Without it, the handoff probes / global.md read / subagent spawns silently fall back to cwd-relative paths and miss content in the primary worktree when /geniro:implement runs from a linked worktree.

### Step 0 — Workspace setup

Step 0 fires BEFORE any L4 / L3 / L2 helper call and BEFORE the Knowledge-Retrieval / Codebase-Explorer spawn. Workspace decision determines the worktree the rest of Phase 1 inspects; running L3 fingerprint drift checks against the wrong worktree is wasted work.

Two sub-steps: **passive detection** (0a, no AUQ) → **decide action** (0b, auto-continue or AUQ).

#### 0a — Detect current context (passive)

Collect these signals before deciding:

| Signal | How detected |
|---|---|
| `CURRENT_BRANCH` | `git branch --show-current` |
| `CURRENT_TOPLEVEL` | `git rev-parse --show-toplevel` |
| `IN_WORKTREE` | `CURRENT_TOPLEVEL` is registered in `git worktree list --porcelain` AND is NOT the porcelain `bare` row or the main worktree row. Porcelain registry is the source of truth; the `.claude/worktrees/<slug>/` path convention is a sanity check, NOT the primary signal. |
| `PROTECTED_BRANCH` | `CURRENT_BRANCH ∈ {main, master, develop, trunk}` (per-project override via `.geniro/safety.json`) |
| `EXISTING_TASK_STATE` | Glob `.geniro/planning/*/state.md`; any state.md whose frontmatter `branch:` equals `CURRENT_BRANCH` AND `phase:` is terminal ⇒ "prior task on this branch" |
| `REVIEW_HANDOFF` | Path `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<CURRENT_BRANCH>.md` exists ⇒ "review just produced findings for this branch" |
| `DEBUG_HANDOFF` | Path `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<CURRENT_BRANCH>.md` exists ⇒ "debug just authored repro tests for this branch" |
| `BRANCH_MATCHES_TASK_SLUG` | Derived-from-spec slug (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`) substring-matches `CURRENT_BRANCH` |
| `SPEC_WORKFLOW_REFS` | If spec.md present at resolved task slug: parse `workflow_refs:` frontmatter list (per `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` §Frontmatter). Empty list when field absent. |
| `BRANCH_FORMAT_RULE` | Read `<PRIMARY_ROOT>/.geniro/instructions/global.md` directly here at Step 0a. Extract any branch-format directive present (regex pattern, required components such as `<type>/<ticket>-<desc>`, ticket-prefix requirement). Empty when file absent or no branch rule documented. The custom-instructions loader at Step 5 will re-Read the same file with full echo contract; this Step 0a read is a targeted extraction so Step 0c knows the format constraint before authorizing branch creation. Without this signal, Step 0c authorizes branch names that violate project rules and the agent has to rename after the fact. |
| `TICKET_ID_IN_SCOPE` | Set to the detected ticket ID when `$ARGUMENTS` contains a Linear URL / `<TEAM>-<N>` ID, OR spec.md frontmatter `workflow_refs[]` carries one, OR `CURRENT_BRANCH` already encodes one. Empty when none in scope. Cross-checked against `BRANCH_FORMAT_RULE` at Step 0c to decide whether the no-ticket-ID sub-flow fires. |
| `CONCURRENT_ACTIVITY` | Set when another agent/session may be mutating this working tree: `git worktree list --porcelain` shows a peer worktree already on `CURRENT_BRANCH`, OR `git status --porcelain` at Step 0 entry shows changes this run did not author. Signals a contested shared working tree where in-place work risks an external reset/rename orphaning a commit. |

#### 0b — Decide action

Decision tree (first match wins; evaluate top-down):

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
         <when a review handoff matched:> Any open questions from that review will be resolved before code changes."
      Workflow Question 2 still asked if applicable (see 0c).

3. IN_WORKTREE == false
   AND PROTECTED_BRANCH == false
   AND any of {REVIEW_HANDOFF, DEBUG_HANDOFF, EXISTING_TASK_STATE} == true
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
| `--no-adversarial` | Disables Phase 3 adversarial-tester spawn for this run (skips the 6th slot in Round 1). |
| `--deep` / `deep` | Sets `deep-mode: true` — deepens Phase 1 (3× spec fact-check) and Phase 3 (3× self-review passes + 3-vote finding verification) via an internal `Workflow(...)` per `${CLAUDE_PLUGIN_ROOT}/skills/implement/deep-mode-reference.md`. Persist to `approvals[]` category `deep_mode_choice`. |

Conflicting modifiers (e.g., `new-branch` AND `current-branch` both present): last-occurrence wins (right-to-left scan). Emit soft notice: `"Both 'new-branch' and 'current-branch' modifiers detected; using <last>."`

#### 0c — AUQ structure

Single `AskUserQuestion` call carrying up to 3 questions (always-WAIT, never auto-resolve):

**Question 1 — always asked when rules 5 or 6 fire:**

```
header: "Git workspace"
question: "Where should /geniro:implement land its edits?"
multiSelect: false
options:
  - label: "New feature branch (Recommended)"
    description: "git checkout -b <derived-slug>. Slug source order: $ARGUMENTS / spec.title / suggested-branch / branch-naming.md fallback. If your project defines a branch-name format (in .geniro/instructions/global.md), the slug must match it before the branch is created."
  - label: "Current branch"
    description: "Pre-flight only; no git mutation. Echo 'Continuing on <branch> at <toplevel>.'"
  - label: "Git worktree"
    description: "git worktree add -b <slug> .claude/worktrees/<slug>, then EnterWorktree. Isolated parallel work; instant rollback. Same branch-name-format conformance as 'New feature branch'."
```

**No-ticket-ID sub-flow.** When BRANCH_FORMAT_RULE requires a ticket prefix AND `TICKET_ID_IN_SCOPE` is empty, the agent cannot derive a conformant slug. Chain a sub-AUQ BEFORE Question 1 fires (or BEFORE the worktree command runs if Question 1 has already resolved to "New feature branch" / "Git worktree"):

```
header: "Ticket ID needed"
question: "Branch format requires a ticket prefix (per .geniro/instructions/global.md), but no ticket ID was detected in $ARGUMENTS, spec.md, or the current branch. How do you want to proceed?"
multiSelect: false
options:
  - label: "Provide ticket ID inline"
    description: "User types the ID (e.g. ENG-123) in the next message; agent re-derives the slug and proceeds."
  - label: "Use placeholder slug"
    description: "Slug becomes <type>/no-ticket-<desc>. Branch is created with the placeholder; user can rename later via 'git branch -m'."
  - label: "Cancel — I'll get a ticket first"
    description: "Terminal. No git mutation. User exits and re-invokes /geniro:implement once a ticket exists."
```

This AUQ does NOT include a "create the ticket for me" option. /geniro:implement never creates tracker artifacts — see the anti-rationalization row covering tracker-mutation authority.

**Question 2 — conditional on workflow_refs OR `.geniro/workflow/*.md` having an `### On task start` section:**

Merge sources for the workflow-refs-to-process list:

```
workflow_refs_to_process = []
if $ARGUMENTS contains tracker URL/ID → append to workflow_refs_to_process
for each ref in spec.md frontmatter workflow_refs[] → append to workflow_refs_to_process
deduplicate by (kind, issue_id) — $ARGUMENTS reference wins on conflict
```

For each entry, find the workflow file with primary-worktree fallback per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A — try `./.geniro/workflow/<ref.kind>.md` (cwd-local; uncommitted local edits win) first; on file-not-found retry against `<PRIMARY_ROOT>/.geniro/workflow/<ref.kind>.md`. If both missing → log warning + skip (graceful degrade). Staleness check: if `fetched_at` is > 1 hour old OR absent → re-fetch via MCP (timeout 3s, fail-open) — the refresh ALSO updates the cached `status` field. Resolve the current `status` (re-fetched value, or cached when fresh) BEFORE applying the workflow block — the workflow file's `### On task start` section gates its question shape on that field (e.g., the Linear template skips the "Move to In Progress?" prompt when status is already "In Progress", rephrases to "Move back?" when in non-terminal non-In-Progress states, and reframes as "Reopen?" when terminal). Apply the workflow file's `### On task start` block — it may append 0-2 questions to the AUQ batch depending on resolved status and assignee fields. Echo any "skipped — already in target state" cases to the user inline (not as an AUQ).

The workflow file IS the source of truth for question text, options, AND status-conditional branching — do NOT hardcode "Linear" / "Jira" labels, and do NOT bypass the status check by firing the prompt unconditionally.

If the batch exceeds 4 questions — `1` (workspace, when rules 5/6 fire) + `N` (workflow) + `1` (depth, when `--deep` is absent) > 4 — chain into a second AUQ.

**Question 3 — implement depth (fired when `$ARGUMENTS` lacks `--deep`):**

```
header: "Implement depth"
question: "How deep should the implementation analysis go?"
multiSelect: false
options:
  - label: "Standard"
    description: "One spec fact-check pass and one self-review pass."
  - label: "Deep — 3× fact-check + 3-vote verify"
    description: "3× spec fact-check before editing plus a 3× self-review with 3-vote finding verification; higher quality at higher token cost."
```

Question 3 joins the Step 0c AUQ batch whenever that AUQ fires and `--deep` is absent. Neither option carries `(Recommended)` — Deep is costlier, not safer. A `--deep` flag pre-resolves depth to Deep, so Question 3 is skipped; an empty answer defaults to Standard (`deep-mode: false`). On the auto-continue / resume paths where the Step 0 AUQ does not fire (decision-tree rules 1-3), depth stays flag-only — re-prompting for depth on continuing work adds friction, the `--deep` flag is always available, and on resume `deep-mode` was already persisted on the original run. Counts toward the batch-exceeds-4 chain rule above.

#### 0d — Approvals-persistence

Persist the workspace and workflow-status answers to state.md `approvals[]`. The depth pick (Question 3) is materialized once at Step 4 — frontmatter `deep-mode` plus its `approvals[]` entry under category `deep_mode_choice` — so the depth choice is written in exactly one place:

```yaml
approvals:
  - category: implement_workspace_setup
    picked: "New feature branch (Recommended)"
    timestamp: <ISO-8601>
  - category: implement_workflow_status
    picked: "Yes — move to In Progress"
    timestamp: <ISO-8601>
    workflow_file: ".geniro/workflow/linear.md"
    transition: "Todo -> In Progress"
    issue_id: "CI-303"
```

On compaction-resume, Step 0 reads `approvals[]` and re-applies prior answers without re-prompting.

#### 0e — Execution after AUQ

1. **Workspace action** — execute branch creation / worktree create / no-op per `implement_workspace_setup` pick. Slug source: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`. Branch and worktree creation cut from the latest default branch — apply Mode FRESH-BASE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` so the new working tree starts from the freshest default-branch tip rather than the current HEAD. For the "Current branch" (no-op) pick, apply Mode FRESH-CONTINUE from the same helper — offer to bring the branch up to date before Phase 1 proceeds.
2. **Workflow status action** — for each persisted `implement_workflow_status` approval, follow the workflow file's `### On task start` instructions. Skill does NOT hardcode MCP call shape — workflow file owns that.
3. **State.md frontmatter update** — `branch:` and `worktree:` reflect the new working tree before Phase 1 continues.

#### 0f — Edge cases

| Case | Behavior |
|---|---|
| Workflow MCP unavailable when Question 2 fires | Question 2 still fires; "Yes" answer logs warning and proceeds without MCP call. Non-blocking. |
| Workflow file present but `### On task start` section missing | Question 2 omitted silently. |
| User picks "Other" with custom text on Question 1 | Treat as "Current branch" semantically; no git mutation; echo custom text into state.md `## Workspace decision` body block. |
| Multiple review/debug handoffs for current branch (review AND debug both produced findings) | Both signals satisfy rule 2 of 0b. Echo both signal names; behavior otherwise identical. |
| Stale review/debug handoff (older than the current work) | Still triggers rule 2. Emit soft notice: `"Note: review handoff is N days old. Re-run /geniro:review if you want fresh findings."` |
| `IN_WORKTREE == true` AND `PROTECTED_BRANCH == true` | Rule 5 fires (full AUQ); worktree-presence is incidental. |

### Steps (after Step 0 settles)

1. **Semantic-parse `$ARGUMENTS`.** Apply the table in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: $ARGUMENTS semantic-parse table".
2. **Resolve spec source.** Walk the spec discovery list (`${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Spec discovery walk-list"). If no spec.md / plan.md / DESIGN_DOC frontmatter found AND $ARGUMENTS is non-empty → inline-task mode (write `## Inline Plan` to state.md body).
3. **Disambiguate if needed.** If $ARGUMENTS is ambiguous, fire AUQ per Phase 1 table. Persist outcome to state.md frontmatter `approvals[]` with `category: disambiguate_arguments`.
4. **Resolve task slug.** Used for state.md path. If task-dir exists, validate state.md (recovery AUQ on validation fail). If task-dir is fresh, `mkdir -p`. Write the resolved depth into the state.md frontmatter at creation: `deep-mode: true` when EITHER Step 1 parsed `--deep` OR the Step 0 Question-3 depth pick was Deep; `deep-mode: false` for a Standard / empty pick. Append the matching `{category: deep_mode_choice, picked: <deep|standard>, at: <ISO-8601 UTC>}` to `approvals[]` via `atomic_state_write` — the resolved depth must be persisted, not just held in working memory, so a compaction-resume re-applies it (a parsed flag or Step 0 pick that is never written is the loading-≠-firing gap that silently drops the depth choice on resume).
5. **Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: implement`, `LOAD_TIER: pipeline`, `MODE: refresh`. The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `implement.md`, and `code-style.md` (3 files); the §Echo contract requires one observable line per file. Both are mandatory.
6. **Load project snapshot.** `load_semantic` with default top-2 (`_project.md` + `_CODEBASE_MAP.md`). Optional `--extras _FEATURES.md` if spec mentions feature backlog. Fingerprint drift check fires automatically; surface drift notification to user.
7. **Spawn knowledge-retrieval + codebase-explorer agents in parallel.** ONE assistant response, TWO `Agent(...)` tool calls. Apply the spawn template in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 1: Subagent spawn template". Apply the registration-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at each spawn site. OMIT `model=` argument — the frontmatter governs (codebase-explorer-agent declares `model: inherit`; knowledge-retrieval-agent declares `model: sonnet`, a mechanical-gather carve-out).
8. **Read subagent outputs.** Read `<task-dir>/.kr-out.md` and `<task-dir>/.ce-out.md`. The codebase-explorer's `change_scope` field gates Phase 3 adversarial-tester spawn (`trivial` → skip). Failure handling for either agent: on missing/empty output OR `Agent` tool error, one silent retry; second failure → inline-Read fallback (load top-3 exemplar files + `_CODEBASE_MAP.md` rows by Grep) with `change_scope: medium` as safe default. Emit a `diagnosis` learning with `trust: retrieved`. Echo notice to user.
9. **Query past learnings.** `query_learnings --tag <inferred> --scope <task-path> --limit 5`. Tags may be primed by the knowledge-retrieval output. Skip if task description is too generic.
10. **Resolve cross-layer conflicts.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol if instructions / snapshot / learnings disagree.
11. **Detect frontend files in scope.** Use the codebase-explorer "Likely-Touched Files" report against the UI-file detection rule (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` §UI-file detection rule). Gates Pre-Ship Visual Verification.
12. **Persist review/debug handoffs AND gate on unresolved open questions.** For every `<PRIMARY_ROOT>/.geniro/state/handoff/from-<producer>-<branch>.md` that exists:
    1. Read the handoff file with the `Read` tool (or Bash `cat`).
    2. Persist the body under state.md `## Inputs from <producer>` body section.
    3. Parse frontmatter `open_questions[]` per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2. Also read `report_status` (review handoffs): an explicit `report_status: draft` (missing reads as `final` per the state-tier-spec back-compat rule) means `/geniro:review` did not finish its decision gates — the handoff is not yet finalized. Surface a one-line warning ("the review handoff is still a draft — its decisions weren't finalized; resolving the open questions below completes it") and require the unresolved-open-questions gate (sub-steps 4-5) to clear before transitioning to `phase: implement`. The draft marker is a signal, not a separate block — the `open_questions[]` gate is the actionable resolution.
    4. Filter to entries with `status: unresolved`.
    5. **If the filtered list is non-empty, fire an AUQ batch BEFORE transitioning to `phase: implement`.** Chain one AUQ per unresolved entry (cap-extension when >4). Apply the 3-tier rendering procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.5 — it renders each question as a self-contained chat message first, then a lean question, per the shared finding-gate contract (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering); which tier fires depends on the producer fields the entry carries (single-sourced in §2.5 — don't restate them here). Set `resolution.asked_in_phase: phase-1-step-12` and `resolution.resolved_by: implement` when persisting answers (vs §2.5's `phase-6-pre-gate` / `review`).
    6. After each user pick, update the entry in the PRODUCER's handoff file via `atomic_state_write` (round-trip update): set `status: resolved`, `resolution.picked`, `resolution.at`, `resolution.asked_in_phase: phase-1-step-12`, `resolution.resolved_by: implement`. **`atomic_state_write` is a full-file overwrite, not a merge — supply the producer's ENTIRE original handoff content; the only delta is this entry's `status` + `resolution` sub-fields.** Preserve byte-for-byte every other frontmatter key the producer wrote — the key set varies by producer, so re-emit whichever keys the file you read actually carries, not just the ones named here. Review handoffs add `pr-ref`/`pr-body`/`resolved-threads-snapshot` + `linear-task-ref`/`linear-parent-ref`; debug handoffs add `geniro_kind`/`geniro_schema_version`/`mode` + the `authored_tests[]` array that sub-step 9 below reads back (drop it and the F→P-test extraction finds nothing). Common to both: `tier`, `producer`, `consumer`, `schema-version`, `branch`, `timestamp`, `worktree`, `approvals`, `non-resumable-actions`, the other `open_questions[]` entries. This list is illustrative, not exhaustive. Also re-emit every body section (`## Findings`, `## Authored Tests`, etc.) unchanged, or a resolution write silently truncates load-bearing producer state a downstream re-review (or sub-step 9's `authored_tests[]` read) reads back. This is a surgical patch, not a rewrite. Within the resolved entry keep `id`, `source`, `question`, `related_findings`, `related_hypotheses` unchanged.
    7. Persist a parallel approval to state.md `approvals[]` with `category: review_handoff_resolution`, `picked: <chosen option>`, `at: <ISO-8601 UTC>`, `source_handoff: <producer>`, `question_id: <id>` for compaction-resume idempotency.
    8. After all entries are `resolved` or `wontfix`, proceed to sub-step 9.
    9. **Extract authored F→P tests when the handoff is from `/geniro:debug`.** Skip when `<producer>` is anything other than `debug` (e.g., `review`); fire only for `from-debug-<branch>.md` and `from-debug-adversarial-<branch>.md`. Apply the canonical Scan/Extract/Verify/Decide protocol in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md`:
       - **Extract** — prefer frontmatter `authored_tests[]` (m7-v2+); fall back to body `**Reproduction test:**` / `**Test file:**` parse for legacy m7-v1 handoffs.
       - **Verify** — resolve each path against this skill's current `git rev-parse --show-toplevel` and bucket as PRESENT / MISSING.
       - **Decide and surface** — Case A (all PRESENT, debug-source-branch matches) → one-line acknowledgment in the Phase 1 context summary. Case B1 (any MISSING) → surface the suggest-only relocation block from `_shared/debug-handoff.md` §Step 4; the user runs `git checkout <debug-source-branch> -- <paths>` or `cp` themselves — never auto-execute cross-branch git operations. Case B2 (all PRESENT but branches differ) → one-line "tests carried over" note. Case C (legacy fields missing) → degraded suggestion without explicit checkout command.
       - **Persist** to state.md as `Authored-tests:` (comma-separated relative paths on a single line) plus, when sourced from m7-v2+ frontmatter, `Authored-tests-intent:` (parallel comma-separated intents) and `Debug-source-branch:` / `Debug-source-worktree:`. Phase 2 reads these to prime TodoWrite decomposition — each authored test becomes a pre-existing acceptance gate, surfacing in the relevant todo's description so the production-fix work cannot ship without those tests going GREEN.
       - Authored-tests extraction is informational, NOT a gate — do NOT block transition to `phase: implement` on missing files. The user retains agency to either run the suggested commands, re-author tests in the current branch, or accept the divergence.
    10. After authored-tests handling, proceed to step 12.5.

   /geniro:implement is the consumer; the contract per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 forbids proceeding with Edit/Write while any `unresolved` entry remains. A consumer that ships anyway violates the contract — the producer surfaced the ambiguity precisely so it gets resolved BEFORE code changes.

12.5. **Spec challenge — fact-check the spec against the current code before editing.** This is the last gate before code edits begin: it confirms the spec's factual claims still hold against the live code the run is about to touch.

   - **Spec-driven mode only.** Run this step only when Step 2 resolved a real spec.md / plan.md / DESIGN_DOC. SKIP it in inline-task fallback mode — there is no written spec to fact-check, so emit a one-line note ("No spec file — skipping the spec fact-check") and proceed to step 13.
   - **Invoke the helper.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` with MODE: implement, SPEC_PATH: \<resolved spec path>, TASK_DIR: \<task-dir>, EFFORT_TIER: \<the codebase-explorer change_scope>, DEEP: \<true when state.md deep-mode: true, else false>. The helper runs VERIFY (one read-only verifier per file:line-cited claim — 3 verifiers per claim with majority vote when DEEP) plus RED-TEAM and returns refuted claims plus blocking risks. RED-TEAM does NOT generate alternative approaches — the spec's design is approved and locked; it only stress-tests the locked approach for blocking risks.
   - **Boundary — verify facts, do not re-open the design.** The pass checks whether the spec's factual claims about the code still hold (does the "X exists at file:line" the spec relied on still match current code?). It does NOT re-litigate the approved design decision. The spec.md is the pre-approval (per the anti-rationalization row on per-Edit AUQs); this gate exists because the code may have drifted since the spec was approved, not to re-debate an approved approach. A clean fact-check preserves spec-driven autonomy — the gate adds friction only when a claim is refuted or a blocking risk surfaces.
   - **Gate — ask only when the fact-check finds a problem.** When the helper returns ≥1 refuted claim OR a blocking red-team risk, render the refuted-claim digest to chat first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering — what the spec claims, what the code actually shows, the evidence cite, the consequence — then fire the lean AskUserQuestion with options "Proceed anyway" / "Fix the spec, then proceed" / "Abort — re-plan via /geniro:plan", unchanged. When the pass is clean (no refuted claims, no blocking risk), emit a one-line advisory note ("Spec fact-check passed — N claims verified against current code") and proceed silently — matching the restraint of the other Phase 1 gates, which never ask when there is nothing to decide.
   - **Do not rewrite the spec.** The spec.md is the user's approved durable artifact authored by /geniro:plan; rewriting it from /geniro:implement would force a cross-producer schema lockstep. "Fix the spec, then proceed" hands the edit back to the user (or a fresh /geniro:plan run) — /geniro:implement does not edit the spec file itself.
   - **Persist the pick.** Record the user's choice in state.md frontmatter `approvals[]` with `category: spec_challenge`, `picked: <chosen option>`, `at: <ISO-8601 UTC>` for compaction-resume idempotency.
   - **Always-on.** This gate fires on every spec-driven /geniro:implement regardless of effort tier — there is no Trivial skip. Cost stays bounded because only file:line-cited claims get a verifier; a spec with few cited claims spawns few verifiers.
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

---

## PHASE 2: IMPLEMENT

State.md `phase: implement` on entry.

No custom-instructions or project-snapshot refresh at Phase 2 entry — both remain in context from Phase 1.

### Steps

1. **Read spec source** — Phase 1 resolved either a spec.md path OR wrote `## Inline Plan` to state.md body. Inline-Read the spec.md (full body) and the Codebase-Explorer "Likely-Touched Files" + "Reuse Inventory" sections.

2. **Decompose into todos via TodoWrite (Phase 2 entry — before any Edit).** Author N concrete edit-tasks via TodoWrite. Each todo = one logical unit of change (e.g., "Add migration X", "Update Y controller", "Add Z test"). N typically:
   - 1-3 todos for Small scope
   - 3-10 todos for Medium scope
   - up to 15 todos for Big scope (unless already split into milestones)

   All todos initially `status: pending`. Mark the FIRST todo `in_progress` before any Edit.

3. **Work through todos sequentially — one in_progress at a time** (Loop invariant #9):
   ```
   for each todo in pending order:
       a. Mark todo in_progress via TodoWrite
       b. Make the Edit/Write changes for THAT slice ONLY
       c. JIT-load any .claude/rules/*.md whose paths: glob matches an Edit target
          (use the rule list returned by Codebase-Explorer §"Relevant Rules";
          cache rule bodies for the rest of Phase 2)
       d. Mark todo completed via TodoWrite
       e. Move to next todo
   ```

   No parallel subagent fan-out for code edits. Single orchestrator owns context throughout Phase 2.

   **Comment discipline.** Match the surrounding file's comment density and idiom. Write a comment only where the code cannot show the constraint itself — a non-obvious WHY, an invariant the types don't express, a legal header, a TODO with an issue reference. Never restate what a line does, narrate the change being made ("added X", "now handles Y"), or address the reviewer — those comments are noise the moment the diff merges, and the reviewer reads the diff, not annotations. A per-project `code-style.md` rule overrides this default where they conflict.

   **Halt on unbidden working-tree mutation.** Between Edits, if the working tree changes in ways this run did not make — an Edit/Write repeatedly fails with "file changed since read", or files/tests this run never authored appear on disk — treat it as a concurrent external process, NOT a benign harness restore. Stop and fire an `AskUserQuestion` (header: "Workspace changed", options: "Pause — let me resolve the other process" / "Move my work into a fresh worktree and continue there" / "Abort"). Committing from a working tree another process is mutating risks the commit being orphaned by an external reset.

4. **End-of-phase test run via `test-runner-agent`.** After all todos `completed`, spawn `test-runner-agent` once with the project's pre-resolved TEST_COMMAND (from CLAUDE.md "Essential Commands"), the CHANGED_FILES list, OUTPUT_PATH `<task-dir>/.tr-out.md`, and `MAX_FAILURES_REPORTED` (default per the `test-runner-agent` spawn template in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md`). Apply the registration-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`. OMIT `model=` — test-runner-agent declares `model: sonnet` (mechanical run-and-parse carve-out). Read back the OUTPUT_PATH report. Attach the report's Command / Exit code / Summary / Verdict block as Evidence per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`.

5. **In-phase fix loop on test failure.** Up to 3 retries (full pseudo-code + token-cost analysis: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling"). On each retry: read `.tr-out.md`, escalate-AUQ immediately on `INFRA_ERROR`, edit top-priority failures on `HAS_FAILURES`, re-spawn `test-runner-agent`. On `ALL_GREEN` — by EITHER path (the first-shot end-of-phase run OR a later fix-loop iteration) — run the spec's per-criterion `verify:` commands (step 5.5) BEFORE exiting to Phase 3. Retry exhaust OR an early-escalation trigger (see below) → escalate-AUQ before the 3-retry budget is spent — a loop that is not converging burns the user's tokens on the same wall.

5.5. **Run the spec's per-criterion `verify:` commands once the suite is `ALL_GREEN` (spec-driven runs only).** This fires on the suite's green exit from step 5 — whichever path reached green — so a red→green run never ships without the spec's acceptance checks. For each section 9 (Validation) criterion that carries a `verify:` line, the orchestrator runs that one command via its own Bash (NOT `test-runner-agent` — its single-command leaf contract forbids it orchestrating several commands) and classifies the result on the same `{ALL_GREEN, HAS_FAILURES, INFRA_ERROR}` taxonomy. Bounded single-shot — run once and attach as evidence; not an iterate-to-green loop. **Side-effect screen first:** before executing each command, refuse to auto-run any that carries a ship / deploy / external-state-mutation verb (`git push`, `gh pr create`, `gh pr merge`, `git commit`, `deploy` / `release` / `publish`, etc.) — this command runs before the ship gate, and the safety hooks block force-push but NOT a plain `git push` / `gh pr create`, so auto-running it would ship past the gate (Loop-Invariant #3). A refused command routes into the same Step 6 escalation with a plain-English reason — never executed, never silently skipped. Any `HAS_FAILURES` / `INFRA_ERROR` (or a refused command) feeds the same Step 6 escalation digest so the user stays the ship decider. Inline-task runs (no spec) have no `verify:` lines and skip this step. Mechanics: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling", "Per-criterion `verify:` commands".

6. **Escalation on retry exhaust, `INFRA_ERROR`, or a not-converging signal.** Render the failure digest to chat first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering — what failed in plain English, the failing items as a `☐` checklist, why it blocks the phase (worked digest shape: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 2: Implement — error-handling", "Phase 2 check-failure escalation digest") — then fire the lean AUQ with the header keyed to what failed (`"Test failure"` for a failing test suite, `"Acceptance check failed"` for a failing spec `verify:` command, `"Checks failed"` when both — per the reference's failure-source table) and these options:
   - A) Hand off to /geniro:debug — state.md `phase: debug-handoff` (terminal — run the transient cleanup first, per §Terminal states)
   - B) Accept the failing check as a documented limitation — state.md `phase: self-review`, append `## Accepted Failures` block (label is source-neutral: the failure may be a test OR a spec `verify:` acceptance check)
   - C) Abort — state.md `phase: aborted` (terminal — run the transient cleanup first, per §Terminal states)

   Empty answer = upstream bug, fall back to plain text and re-ask. NEVER auto-default.

   **Early-escalation triggers (derived from state.md `## Errors` + `## Tool log` history — no new state surface).** Fire the same AUQ before retries exhaust when any of these holds, because each is a signal the loop has stalled rather than progressed:
   - **No forward progress between two checkpoints.** Two consecutive retry checkpoints produce no new passing tests AND no forward diff progress (the changed-files set and failing-test set are unchanged across the pair). The fix edits are not moving the suite.
   - **Retry storm — the same failure recurring.** An identical failing test name OR an identical error message / stack-trace recurs across retry attempts (compare the current test-runner output against the prior retry's failing-test list still in context). Re-hitting the same wall means the current approach cannot clear it.
   - **Cost / scope drift.** The run has exceeded its expected size by either of two sub-signals: (a) the codebase-explorer `change_scope` tier from Phase 1 (e.g. a `trivial`/`small` task now spanning many files and edit batches), OR (b) for a spec-driven run, the size the user wrote into the spec — the `budget.max_files_to_edit` / `budget.max_lines_changed` numbers — crossed by the live diff (count files and lines from the CHANGED_FILES set / `git diff --stat`, no new state surface per invariant #5). Each `budget` value is disarmed when null (= unbounded); the inline-task fallback has no `budget` block, so sub-signal (b) never arms there. Whichever sub-signal trips first fires this AUQ once — dedupe with the other so one scope-drift escalation fires per run, and the dedupe spans Phase 2 AND the Phase 3 fix loop (this trigger set is reused there) so it never double-fires across phases. The AUQ question names which bound was crossed.

   When an early trigger fires, state the plain-English reason in the AUQ question text (e.g. "the same test keeps failing across retries" / "this is turning out larger than the size you set in the spec") so the user knows why the gate opened early — never surface the raw signal name (e.g. `max_files_to_edit` / `change_scope` / `budget`).

**State.md update on phase exit.** `phase: self-review` (happy path) or `phase: phase-2-escalated` (if escalation fires). On `aborted`, write `## Termination reason: repeated-failure: phase-2 retry-limit (<N> failing Phase 2 checks)` — source-neutral, since the escalation covers both a failing test suite AND a failing/refused spec `verify:` acceptance check.

**L2 emit on retry exit.** When Phase 2 exits AND `retry_count ≥ 2` (i.e., at least one fix-iteration happened), call `emit-learning` with `type: retry_failure_sequence`, `trust: verified`, required `ext.{phase: "phase-2-fix-loop", attempts: [...], resolution}`. Each `attempts[]` entry = `{round: N, failure: "<one-line summary>"}`. `resolution ∈ {passed, escalated, aborted}` matches the actual exit state. Sliding-window cap = 3 latest per `(producer, scope, phase)`; on overflow, flip the oldest entry's `deprecated: true` BEFORE appending — this mutates `.geniro/knowledge/learnings.jsonl`, so rewrite the file through the atomic-write path (`atomic_state_write`), not a direct `Edit`/`Write` the state-helper hook guards (mirrors debug §1.5). Single-retry exits (retry_count == 1) do NOT emit. Future Phase 1 `query-learnings` calls surface this as priming context.

### Loop visualization

```
PHASE 2 (sequential, single-context):

  spec.md + Codebase-Explorer report
       ↓
  [Phase 2 entry] TodoWrite: decompose into N todos
       ↓
  ┌─→ todo[i].in_progress ──→ Edit/Write batch ──→ todo[i].completed ─┐
  │                                                                    │
  │                          [i++; loop until all completed]           │
  │                                                                    │
  └────────────────────────────────────────────────────────────────────┘
       ↓
  [End-of-Phase] test-runner-agent spawn (one shot)
       ↓
  [3-retry fix-loop on failures]
       ↓ (suite ALL_GREEN — by either path)
  [run spec verify: commands] (spec-driven runs only)
       ↓ (all pass)            ↘ (any fail/refused)
  Phase 3              [Step 6 escalation AUQ]
```

---

## PHASE 3: SELF-REVIEW + SHIP

**State.md `phase: self-review`** on entry.

**Refresh L4 instructions** (always, regardless of compaction-marker presence). Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `MODE: refresh`, scope = same as Phase 1.

**Idempotent green-light verification on entry.** Re-run the test suite once; it should be green from Phase 2. If it is NOT green, the orchestrator may NOT unilaterally reclassify the failures as pre-existing/flaky and proceed — it routes through the documented gate: roll back to the Phase 2 retry loop, or (on retry-exhaust) the escalation AUQ (`debug-handoff` / `accept-failures` / `abort`), which records a `## Accepted Failures` block that is then disclosed at the ship-mode AUQ. If the orchestrator suspects the failures are pre-existing, it may baseline-prove them (re-run the failing tests on the unchanged base, e.g. via `git stash`) — but that evidence routes INTO the `accept-failures` AUQ for the user to acknowledge; it does not authorize shipping past a RED required suite on the orchestrator's own authority.

**Resolve `PRIMARY_ROOT` before the parallel reviewer batch fires.** Run the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` via Bash. The custom-reviewer discovery in Step 1 calls `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md`, which dual-globs `.geniro/instructions/review-extra/*.md` against cwd AND `<PRIMARY_ROOT>/.geniro/instructions/review-extra/*.md` — without the slot in scope, a linked-worktree session sees an empty `.geniro/instructions/` even when user-authored review-extra files exist on the main worktree.

### Steps

1. **Round 1 parallel spawn IS the Phase 3 review mechanism — reviewer-agents + 1 adversarial-tester-agent in the SAME assistant response.** Multiple `Agent(...)` tool uses in one message. An inline "self-review summary" the orchestrator writes from its own context does NOT satisfy Phase 3: it shares every assumption the implementer just made, so it cannot deliver the independent, anchoring-bias-free read the spawned reviewer-agents (fresh isolated contexts) exist to provide. The fresh parallel spawn fires regardless of how well the orchestrator believes it understands the change. Apply the registration-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at every spawn site. OMIT `model=` at every spawn site (every agent declares `model: inherit`).

   **Deep-mode branch (`deep-mode: true`).** Run Round 1 via the deep self-review `Workflow(...)` instead of the single parallel batch below — each reviewer dimension 3× (union + dedup per dim), then a 3-vote majority verification of each deduped finding, per `${CLAUDE_PLUGIN_ROOT}/skills/implement/deep-mode-reference.md` §3-4. Only majority-confirmed findings enter the fix loop; the `adversarial-tester-agent` stays a single spawn. Fail-safe to the standard single-pass batch below if the workflow errors (deep-mode-reference §7). Fix-loop rounds 2-3 run single-pass regardless. Everything below describes the standard single-pass Round 1.

   - **reviewer-agents** — one per dimension. Apply `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 3: Self-review reviewer-agent template". Dimensions: `bugs` / `security` / `architecture` / `tests` / `code-quality`. The `architecture` dim covers docs-staleness AND spec-compliance. See reference.md §"The reviewer dimensions" for full criteria-file mapping.

   - **1 adversarial-tester-agent** — apply `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 3: Adversarial-tester spawn template". The agent authors F→P-verified failing tests against the diff and writes them to the project's test directory. SKIPPED on either of two conditions:
     - Codebase-Explorer `change_scope: trivial`, OR
     - `--no-adversarial` modifier present in `$ARGUMENTS`.

   - **Custom reviewer dimensions** — discovered once at Round 1 entry via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` (`.geniro/instructions/review-extra/<slug>.md`, ≤10 cap, path-filtered). Append one `Agent(subagent_type="reviewer-agent",...)` call per spec to the same parallel batch.

2. **Collect findings.** Reviewer-agent output schema per `agents/reviewer-agent.md` §Output Format. Adversarial-tester output schema per `agents/adversarial-tester-agent.md` §Output Schema AND authored test files on disk under the project's test directory. Cap per-dim output at ~4K chars (invariant #4); truncate with marker on overflow.

3. **Bounded fix loop.** Up to 3 rounds. Full pseudo-code + drop-rules for round N+1 + adversarial-as-6th-dim mechanics: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 3: Bounded fix loop". Summary: on each round, collect findings from the parallel spawns; if clean AND no authored adversarial tests still fail, exit to Ship; otherwise apply fixes inline (no further agent spawns), re-spawn `test-runner-agent` (rollback to Phase 2 if not green), increment round, then re-spawn ONLY the failing reviewer dims (and the adversarial-tester conditionally). Round 4 entry is forbidden — escalate-AUQ instead.

4. **Escalation on round-3 exhaust or a not-converging signal.** Render the unresolved findings to chat first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, then fire the lean AUQ (header: `"Resolve findings"`) — worked render procedure in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 3: Bounded fix loop", "Escalation at exhaust"; options:
   - A) Hand off to /geniro:debug — state.md `phase: debug-handoff` (terminal — run the transient cleanup first, per §Terminal states)
   - B) Accept findings, ship anyway — state.md `phase: ship`, append `## Accepted Findings` block
   - C) Abort — state.md `phase: aborted` (terminal — run the transient cleanup first, per §Terminal states)

   Empty answer = upstream bug, fall back to plain text and re-ask. NEVER auto-default.

   The Phase 2 early-escalation triggers (§PHASE 2 Step 6) apply to this fix loop too, read from the same state.md `## Errors` + `## Tool log` history: fire this AUQ before round 3 exhausts when two consecutive rounds make no forward progress (same findings survive, no new tests pass, diff unchanged), when an identical finding or identical failing test/stack-trace recurs round-over-round (a fix that does not stick), or when the run has drifted far past the codebase-explorer effort tier OR the user's spec-declared `budget` (the same scope-drift sub-signals Step 6 lists, deduped with the Phase 2 fire so one scope-drift escalation surfaces per run). State the plain-English reason in the AUQ question text — never the raw signal name.

### Ship sub-step

State.md `phase: ship` on entry.

1. **Pre-Ship Visual Verification** — fires only when frontend files in scope AND Playwright MCP available. Apply `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Pre-Ship Visual Verification".
2. **Commit.** Verify the live `git branch --show-current` matches the intended branch before staging — do not trust the session-start branch snapshot (stale across compaction); on mismatch, fire the branch-check `AskUserQuestion` (full procedure in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Step 2 — Commit") rather than committing. Then stage only this run's CHANGED_FILES set by name (`git add <paths>`, never `-A`/`.`). If `git status` shows production files modified outside that set — edits this run did not author — do NOT auto-fold them; fire an `AskUserQuestion` to confirm whether they belong in this commit before staging. Then `git commit` with conventional message (e.g., `feat(auth): add OAuth login [ENG-123]`). Task ID inferred from spec.md / state.md metadata.
3. **Emit learnings.** Fire this before the Ship-mode AUQ — the learning describes the change just committed and doesn't depend on the push outcome, so emitting here makes it part of finalizing the work rather than a postscript that gets dropped once the PR is open (the documented sparse-L2 cause). Emit `convention` when a ≥3-instance pattern was detected; emit `decision` if spec.md recorded a non-trivial approach choice; a clean single-pass change with neither emits nothing. Default trust = `verified`. After a successful emit, echo `Recorded learning: <summary>` to the user, and surface the promotion suggestion only for `convention` type. Apply `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Extract Learnings" plus the visibility + ordering rules in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract".
4. **Suggest improvements (reflection).** Fire before the Ship-mode AUQ — improvement suggestions describe project rules learned from the change and don't depend on the push outcome, so anchoring them here (not after the PR opens) keeps the step from being dropped on wrap-up. Spawn `reflection-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` §"Reflection-agent feed" (mode `implement`; pass the committed diff + Phase 3 findings + rule-file paths + prior declines), then surface its candidates — already filtered through that file's §Candidate bar — via §Presentation. Echo `Reviewed for improvements: <N> candidate(s)`; skip the prompt silently when it returns none (zero bar-passing candidates is the common outcome). Full step: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Suggest Improvements".
5. **Ship-mode AUQ.** Push is draft-grade (auto) on a private feature branch with no open PR; a push to the default or a shared/protected branch — or to a feature branch that already has an open PR when this run was entered via a /geniro:review or /geniro:debug handoff (the user's only approval was the upstream "apply the findings" pick, which authorizes editing, not shipping) — is itself commit-grade and surfaces an explicit confirm rather than auto-approving, because that push updates a live PR (CI re-runs, reviewers see the new commits). AUQ gates commit-grade PR creation. Before firing it, on a spec-driven run annotate the AUQ's question/description text with any machine-checkable Done-Condition clause that is still unsatisfied, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/done-condition-check.md` — advisory and skip-when-clean (a satisfied check proceeds silently), bound to the validator's stopping-condition ontology so free-text clauses stay human-eyeball-only, and attaching to the question/description text ONLY so the verbatim option-label allowlist below is untouched. The AUQ's option labels are a verbatim allowlist — present them as written, and the "Open draft PR (Recommended)" option must always appear; never paraphrase or merge the options into a single "open PR" label. See `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Commit + Push + PR" for the canonical AUQ shape and approvals-persistence protocol. Inline modifiers from $ARGUMENTS (`"don't push"`, `"draft only"`, `"ready-for-review"`, `"stop after review"`) override the AUQ deterministically; a bare "open PR"/"with PR" with no draft-vs-ready qualifier fires the AUQ rather than overriding it.
6. **Atomic `non-resumable-actions[]` update.** After each side-effect that cannot be replayed safely (`git push`, `gh pr create`, posted PR comment), append a structured entry to state.md frontmatter `non-resumable-actions[]` array via `atomic_state_write`. Entry schema `{action, completed-at, <action-specific-fields>}`, where `action` is a literal from the enum in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §`non-resumable-actions[]` action enum (`git-push`, `pr-created`, `pr-comment-posted`), and `completed-at` comes from `$(date -u +%Y-%m-%dT%H:%M:%SZ)` in the same write call, never model-supplied (`atomic-state-write.md` §Timestamp sourcing); write AFTER the side-effect succeeds — atomic, so partial-write corruption is impossible mid-crash.
7. **Update project snapshot.** If Phase 2 added a new module, `update_semantic --file codebase-map --append "..."`. Lock-guarded; rc=11 = recoverable skip.
8. **Update Docs / Integration Updates / Custom post-ship steps / Cleanup.** Apply reference.md sub-sections in order. (Suggest Improvements ran at step 4, pre-AUQ.) Custom post-ship steps run any user-authored `## Additional Steps` subsection from the loaded `<skill>.md` whose anchor is post-ship (e.g. `### After ship`) — these fire after the PR is created (preview-environment creation, PR-description augmentation, external notifications), per `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Custom post-ship steps". Without this step a loaded `### After ship` block has no execution anchor and is silently dropped once Cleanup runs. Cleanup runs the transient cleanup — it deletes only transient subagent outputs; durable artifacts (`spec.md`, `state.md`, `plan-*.md`, `milestone-*.md`) survive Ship for downstream /geniro:review / /geniro:debug / /geniro:refactor / Adjustment Routing consumers. The exact `rm -f` scratch-file list and the preserve set live in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Cleanup" (single source); after the rm runs, echo `Cleaned up transient working files from <task-dir>` — the in-session signal the step 9 pre-terminal check looks for.
9. **Emit the ship report, then transition.** Before the terminal transition, emit the ship report to chat — Evidence Block with what shipped, commit SHA / branch / PR URL quoted from tool output, test Verdict, review-round found/fixed summary, deferred items; a bare status echo is not a ship report (full contract + the trailing-bookkeeping retry rule: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Commit + Push + PR" Steps 5-6). Then write frontmatter `phase: done` (or `ship-committed-only` / `self-review-only` depending on modifier / user pick). Before writing a terminal `phase`, run one combined pre-terminal check: confirm step 3's learning emit fired (or was correctly N/A for a clean single-pass change) AND step 8's transient cleanup ran (the `Cleaned up transient working files` echo is the signal) — a terminal state written over a skipped emit is the sparse-L2 failure mode the §"Caller contract" ordering rule guards against, and one written over skipped cleanup leaves transient files that resurface as recurring migration warnings on every plugin update. The SessionStart hook treats terminal states as "no resume needed".

### Adjustment routing (post-ship feedback)

When ship-feedback arrives via PR comments or as a follow-up `$ARGUMENTS` invocation, route per the Big/Medium/Small classification in `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Phase 3 — Adjustment Routing".

---

## Modifier handling (semantic, deterministic)

Inline modifiers from Phase 1 `$ARGUMENTS` override AUQ defaults deterministically. Two tables own the rows at their point of use:

- **Workspace + adversarial-tester modifiers** — §Step 0b "Inline modifier overrides".
- **Ship-mode modifiers** — `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Inline modifiers from $ARGUMENTS".

When no ship-mode modifier is present, the ship-mode AUQ fires. Conflicting modifiers (e.g., `new-branch` AND `current-branch`): last-occurrence wins (right-to-left scan); emit soft notice naming both detected variants.

---

## Task execution entry

0. **Check for existing state.md.** Glob `<task-slug>/state.md`:
- **No state.md** → fresh run. Proceed to Phase 1.
- **state.md exists, phase in non-terminal set** → resume from `phase:` value. The SessionStart hook re-injects context.
- **state.md exists, phase in terminal set** → task complete. Surface terminal state to user; if `$ARGUMENTS` carries new task description, derive new slug, fresh run.

1. **Validate state.md if found** (`validate_state_file`). On fail, open recovery AUQ (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency).

2. **TodoWrite checklist.** Add: Analyze / Implement / Self-review-and-Ship. Mark Analyze in_progress; update each as it completes.

3. **Begin Phase 1.**

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "/geniro:implement should ask user before each Edit — safety first." | Phase 2 Implement is the execution phase. Pre-approval lives upstream — /geniro:plan Phase 8 emits the spec.md; that spec.md IS the pre-approval. Per-Edit AUQs defeat the spec-driven autonomy this skill is designed for. |
| "Phase 2 should fan out subagents — parallel backend/frontend agents, or one subagent per todo — to save wall-time or keep context lean." | Both are documented anti-patterns. Parallel agents editing tightly-interdependent code (shared contracts, types, imports) produce style drift, duplicated implementations, and contradictions lint/compile cannot catch; per-todo subagents only work when each todo has a truly independent spec + tests + worktree, which typical implementation slices (sharing types, imports, conventions) never have. Phase 2 uses sequential TodoWrite decomposition within a single orchestrator — same throughput on the rare truly-parallel work-unit, much higher quality on coupled ones. |
| "Mark all todos in_progress at start so the orchestrator can interleave work." | Forbidden by Loop invariant #9. Single-in-progress is Claude Code's enforced Tasks API design; scattered parallel attempts hurt quality. Mark the next todo `in_progress` only after the current todo completes. |
| "Skip TodoWrite — it's overhead; the orchestrator knows the spec already." | TodoWrite gives the user granular progress visibility. Without it, Phase 2 is a black box until tests run. With it, the user sees real-time per-unit progress. Not optional. |
| "Re-run tests after each file Edit to catch regressions early." | Single end-of-Phase-2 test run via `test-runner-agent`. Per-file test runs explode wall-time on slow suites and burn turns inside the runner agent (one invocation per spawn). |
| "/geniro:implement should self-fix indefinitely until reviews clean." | Phase 3 fix loop is bounded to 3 rounds. Past 3 unresolved rounds, escalate via AUQ — never silently loop. "Kick it until it passes" is a catalogued anti-pattern; round 4 entry is forbidden. |
| "Skip the ship-mode AUQ — the diff is small / this is a debug-handoff follow-up / user already approved upstream / user can `git reset` afterward." | Pushing a private feature branch is draft-grade (auto), but PR creation is commit-grade (AUQ-gated) — and a push to the repository's default branch or a shared/protected branch is itself commit-grade visibility, so the 'Just push' path on such a branch surfaces an explicit confirm rather than auto-approving (do not widen an 'implement the fixes' approval to cover a shared-branch push — or a feature-branch push that updates an open PR when the run was entered via a /geniro:review or /geniro:debug handoff; both are outward-facing visibility the upstream 'apply' pick never consented to). The AUQ fires regardless of diff size, regardless of debug-handoff or review-handoff origin, and regardless of which Phase 2 path led to Ship — none of those are documented modifier-equivalents. The only sanctioned bypass is the 4 inline modifiers (`don't push`, `draft only`, `ready-for-review`, `stop after review`) parsed from `$ARGUMENTS`; everything else fires the AUQ. A bare "open PR"/"with PR" with no draft-vs-ready qualifier is NOT a bypass — it fires the AUQ so the recommended draft default is surfaced; and the AUQ's option labels must be presented verbatim (never paraphrased or merged into a single "open PR" label). PR creation is irreversible visibility — CI runs trigger, reviewers get notified, GitHub fires notifications, the URL is shareable — so the gate sits at the visibility boundary, not the diff-size boundary. A small fix opening as a non-draft PR is just as visible as a large refactor opening as a non-draft PR. |
| "Audit trail isn't needed for local /geniro:implement runs." | The state.md `## Tool log` IS the audit trail. The SessionStart hook re-injects on compaction. Without log, post-mortem on failed runs is impossible. |
| "Bypass safety hooks with --no-verify when commit-hook fails — saves time." | Hooks fail for a reason. Investigate root cause, not bypass. --no-verify usage is a CLAUDE.md-level prohibition. |
| "Spawn agents one at a time for cleaner orchestration / it's a small diff so a quick `bugs`-only review is enough / 1-2 dimensions cover the important risks / I already know this change well (I just wrote it / it's a debug-handoff follow-up), so an inline self-review summary is enough." | All Phase 3 Round 1 spawns happen in ONE assistant response (reviewer-agents + adversarial-tester) — multiple `Agent(...)` tool uses in the same message. Diff size does not trim the reviewer count: the reviewer dimensions (`bugs` / `security` / `architecture` / `tests` / `code-quality`) cover orthogonal concerns; spawning only `bugs` blinds the run to security regressions, architectural drift, test gaps, and quality issues. The only sanctioned trims of the parallel batch are: (a) Codebase-Explorer `change_scope: trivial` strips the adversarial slot, (b) `--no-adversarial` modifier strips the same slot. The reviewer slots are mandatory regardless of diff size, regardless of how the change originated (debug-handoff, review-handoff, or fresh spec). An inline self-review the orchestrator writes from its own context is NOT a substitute for the parallel reviewer-agent spawn — it shares the implementer's blind spots and cannot defeat anchoring bias; the fresh isolated-context spawn IS the review mechanism and is mandatory regardless of how well the orchestrator believes it understands the change. Same parallel-spawn rule for Phase 1 KR + CE: ONE response, two spawns — and the KR + CE spawns are not optional. "I already explored this branch in the /geniro:review I just ran, so the Phase-1 recon is pure ceremony — proceeding directly" is the continuation-resume drift that silently drops the skill's research contract; the spawns fire regardless of how much context the orchestrator believes it carries from an upstream skill, because a continuation that skips them inherits the upstream run's blind spots. Separate turns = no concurrency; skipping the spawns = no research. |
| "Pass `model=\"sonnet\"` at every spawn site for predictable cost." | Plugin agents declare their tier in frontmatter (`model: inherit`, except the two mechanical carve-outs — test-runner-agent and knowledge-retrieval-agent — which declare `model: sonnet`; see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`); OMIT `model=` at every spawn site so the frontmatter governs. Passing a hardcoded tier at the spawn site defeats the user's session-level `/model` choice for inherit-agents. The only exception is user-authored custom reviewers whose own frontmatter declares an explicit tier — honor the user's declaration. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. |
| "/geniro:implement should fire a user-approval AUQ before Phase 3 adversarial-tester spawn, mirroring /geniro:review Phase 4.3." | /geniro:review needs the AUQ because its contract is read-only reporter — spawning a test author is a scope expansion past contract. /geniro:implement is already authorized to mutate code (Phase 2 IS the mutation phase). Phase 3 adversarial test authoring is symmetric to Phase 2 code authoring, NOT a new authority surface. Phase 8 spec.md approval covers it. Use `--no-adversarial` modifier for explicit opt-out. |
| "Branch format requires a ticket prefix per global.md — I'll create the Linear / Jira / GitHub-Issues ticket so the slug conforms." | /geniro:implement never creates tracker artifacts. Per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-reference.md` mutation-responsibility note: /geniro:implement mutates tracker state (status transitions at Step 0c kickoff + Phase 3 Ship completion) but does not create tickets, issues, epics, or sub-tasks. A branch-format rule that demands a ticket ID is satisfied by user-provided ID (Step 0c no-ticket-ID sub-flow option A), placeholder slug (option B), or cancellation (option C) — never by inventing an upstream artifact. Tracker creation is a human authoring action, not a code-execution side-effect; an agent-created ticket appears in the user's tracker without authorization and triggers downstream artifacts (notifications, dashboard rows, sprint-planning surface area) the user did not approve. |
| "/geniro:implement should inline-Read every relevant .claude/rules/, exemplar, and prior plan for thoroughness." | Loop invariant #8. Phase 1 delegates investigation reads to Knowledge-Retrieval + Codebase-Explorer subagents; orchestrator inline-Reads only L4 (3 files), L3 (2 files), spec.md, and state.md. `.claude/rules/*.md` bodies and exemplar sources are JIT-loaded in Phase 2 only when an Edit target matches the rule's `paths:` glob (using the path list returned by Codebase-Explorer). Inline-reading the rest is the documented context-bloat regression. |
| "The working tree keeps changing on its own — it's just the harness restoring my prior session, or a stale-mtime artifact." | A harness restore re-materializes work THIS session already authored; it does not write new files or tests you never created. Content appearing that this run did not author indicates a concurrent external process. Committing from a working tree another process is mutating risks an external reset orphaning the commit — a real near-data-loss failure mode. Stop and fire the "Workspace changed" AUQ (Phase 2 guard) instead of rationalizing the mutation away. |

---

