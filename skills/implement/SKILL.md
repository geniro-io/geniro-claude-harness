---
name: geniro:implement
description: "Use when shipping a new feature, endpoint, page, or significant change against a spec.md / plan.md (from /geniro:plan) OR a raw inline task description. 3-phase autonomous loop: Analyze → Implement → Self-review-and-Ship."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, WebSearch, EnterWorktree, ExitWorktree]
argument-hint: "[task description | spec.md path | empty to resume | 'continue']"
---

# Implement Skill — 3-Phase Autonomous Loop

You are an autonomous executor. You consume an externally-provided spec (or inline task description), make all required code edits, run the test suite, then run a parallel self-review pass before shipping. Strategic concerns belong upstream in `/geniro:plan`. Single orchestrator owns Phase 2 code-edits — no parallel code-editing subagents.

**Phases:**

1. **Analyze (Phase 1)** — Step 0 workspace setup AUQ (with auto-continue for in-worktree fix-up runs); semantic-parse `$ARGUMENTS`; resolve spec source (spec.md / plan.md / DESIGN_DOC frontmatter OR inline-task fallback); refresh custom instructions + project snapshot; spawn knowledge-retrieval and codebase-explorer agents in parallel; query past learnings; persist review/debug handoffs to state.md.
2. **Implement (Phase 2)** — TodoWrite sequential decomposition (3-15 todos, one in_progress at a time); per-todo Edit/Write batch; end-of-phase test-suite run via `test-runner-agent`; bounded 3-retry fix loop on test failure → escalate-AUQ on exhaust.
3. **Self-review + Ship (Phase 3)** — reviewer-agents in parallel (bugs / security / architecture / tests / code-quality) + 1 adversarial-tester-agent (skipped when codebase-explorer reports `change_scope: trivial` OR when `--no-adversarial` modifier is present in `$ARGUMENTS`) + any custom dimensions discovered via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` (`.geniro/instructions/review-extra/<slug>.md`, ≤10 cap, path-filtered); bounded 3-round fix loop, round N+1 = failing dims only; on clean exit, ship sub-step (Pre-Ship Visual Verification if applicable, commit, ship-mode AUQ, learnings + snapshot writes, cleanup).

**Reference material** (templates, $ARGUMENTS-parse table, subagent spawn templates, fix-loop, ship sub-step): Read `${CLAUDE_SKILL_DIR}/implement-reference.md` AT each phase. Do NOT pre-load the entire file.

---

## State machine

State.md frontmatter `phase:` enum:

```
[entry]
└── analyze ──┬── implement ──┬── self-review ──┬── ship ──┬── done (terminal)
│ │ │ ├── ship-committed-only (terminal — "don't push" / "no push" / "commit only" modifier)
│ │ │ └── (non-resumable-actions[] update per side-effect)
│ │ │
│ │ └── self-review-only (terminal — "stop after review" modifier)
│ │
│ └── phase-2-escalated ──┬── debug-handoff (terminal)
│ ├── self-review (user picked "accept failures")
│ └── aborted (terminal)
│
└── (analyze surface failures inline; no additional escalation state)

self-review ──┬── (happy: → ship)
│
└── phase-3-escalated ──┬── debug-handoff (terminal)
├── ship (user picked "accept findings" → `## Accepted Findings` body block)
└── aborted (terminal)
```

**Terminal states**: `done`, `ship-committed-only`, `self-review-only`, `debug-handoff`, `aborted`.

**Non-terminal states**: `analyze`, `implement`, `self-review`, `ship`.

**Termination reason convention.** When `phase: aborted` is reached, write one line to state.md body under `## Termination reason`: `repeated-failure: phase-N retry-limit` / `safety-denied: <rule>` / `tool-unavailable: <tool>`. The SessionStart hook re-injects this on resume.

---

## Loop invariants

Apply throughout all 3 phases:

1. **One result per tool call.** Every Edit / Write / Bash / Agent spawn produces exactly one structured result. Failed spawn → result with `status: failed`; never absent.
2. **Args validated before execution.** Bash commands constructed from $ARGUMENTS or state.md fields pass input sanity-checks. Paths absolute; slugs match the rules in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`.
3. **Permission before side-effect.** Any tool call mutating external state (`git push`, `gh pr create`, posted PR comment) is preceded by AUQ approval or recorded approval (persisted via schema).
4. **Bounded and structured tool results.** Reviewer-agent output capped at ~4000 chars per dimension; longer truncated with marker. Bash output >8000 chars summarized before downstream use.
5. **Escalation gates, not silent abort.** Bounded retry loops (3 rounds in Phase 2, 3 rounds in Phase 3) surface to user via `AskUserQuestion` at exhaustion — never silent abort, never infinite loop.
6. **Final answer grounded in observations.** Phase 3 Ship result text MUST quote actual tool output (push ref, PR URL, commit SHA) — never "git push succeeded" without evidence. Self-review reads `## Tool log` entries before claiming clean state.
7. **Errors, denials, cancellations, timeouts → structured observations.** Failed `gh pr create`, denied permission, hook-blocked Write, subagent timeout, non-zero Bash exit becomes a structured observation entry — never silently skipped.
8. **Investigation reads delegated to subagents.** Phase 1 inline-Reads only L4 instructions (3 files), L3 semantic snapshot (2 files), spec.md body, and state.md. `.claude/rules/*.md` bodies, exemplar source files, L2 learnings entries, and prior plans are spawned out to Knowledge-Retrieval + Codebase-Explorer subagents and read back as condensed reports. Inline-reading the rest is the documented context-bloat regression. The two primary Phase 1 subagent spawns are the plugin-defined `knowledge-retrieval-agent` and `codebase-explorer-agent` (implementation-specific — takes a spec.md, produces REUSE/EXTEND/NO-ANALOGUE inventory). For ad-hoc cross-file research inside Phase 2 (per-step "trace this flow" / "find all sites that call this helper" queries that aren't covered by Codebase-Explorer's Phase 1 inventory), spawn `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.
9. **One todo in_progress at a time.** Phase 2's TodoWrite decomposition enforces sequential focus. Marking a second todo `in_progress` while another is open is the documented anti-pattern (Claude Code Tasks API enforces single in_progress by design; parallel sequential reasoning shows measured performance drop).
10. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research. (Phase 1's `codebase-explorer-agent` is the implementation-specific spec-scoping spawn per Invariant #8; this invariant covers ad-hoc cross-file research in Phase 2 and elsewhere.)

**Side-effect — `## Tool log` section in state.md.** Invariants 1 and 7 motivate persisting subagent-spawn outcomes and side-effect tool calls (`git push`, `gh pr create`, file deletions) into a body section per `${CLAUDE_SKILL_DIR}/implement-reference.md` §Tool log persistence. Routine Read/Edit/Bash on local files do NOT need logging — Claude Code's tool_result return is sufficient.

---

## Budgets — quality-first framing

**NO hard kill caps.** No wall-time / tool-call / model-turn / cost ceilings. User tokens unlimited.

**Quality gates (Class-B — escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Fix-loop retries per phase | 3 | (Phase 2 test fix), (Phase 3 review round) | AUQ — debug-handoff / accept-failure / abort. User picks. |
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
tier: T1
producer: implement
schema-version: 1
branch: <git-branch>
worktree: <git-rev-parse-show-toplevel>
timestamp: <ISO-8601 UTC>
phase: <state-machine-enum>
status: in-progress
non-resumable-actions: [] # appended after each git push / gh pr create / posted comment
approvals: [] # appended after each one-time AUQ resolution
---
```

**Write contract.** Every state.md mutation goes through `atomic_state_write` (cited from `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh`). NEVER direct `Edit` or `Write` on canonical state paths — the State-helper enforcement hook will warn (and PR-final, hard-block).

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

Phase 1 entry runs Step 0 first (workspace setup — see §PHASE 1 Step 0 below), then six helper calls — five reads + one cross-layer protocol:

0. **Step 0 workspace setup** — passive context detection followed by 1-2 question AUQ (skipped on auto-continue path). Fires BEFORE any L4/L3/L2 helper call; workspace decision determines the worktree the rest of Phase 1 inspects.
1. `load-custom-instructions` (L4) with `MODE: refresh` — see §L4 below.
2. `load-semantic` (L3) with `MODE: refresh` — see §L3 below.
3. **Knowledge-Retrieval subagent spawn** — parallel with Codebase-Explorer; reads back from `<task-dir>/.kr-out.md`. See §Phase 1 subagent spawn.
4. **Codebase-Explorer subagent spawn** — parallel with Knowledge-Retrieval; reads back from `<task-dir>/.ce-out.md`. See §Phase 1 subagent spawn.
5. `query-learnings` — see "past learnings" sub-section below. Tags may be primed by the knowledge-retrieval agent's output.
6. `resolve-conflicts` (L4/L3/L2 protocol) — see §Cross-layer conflict surfacing. Fires only if disagreement detected after the reads.

Phase 2 makes no new helper calls at entry; per-Edit `.claude/rules/*.md` JIT loads fire only when an Edit target matches a rule path returned by Codebase-Explorer (cache scope: Phase 2). Phase 3 entry re-fires `load-custom-instructions(MODE: refresh)` AND fires `load-custom-reviewers` once (round 1 only) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` — spawn-specs are appended to the parallel reviewer batch alongside the 5 built-ins and the adversarial-tester. Phase 3 fix-loop iterations may re-fire `query-learnings`. Phase 3 ship sub-step adds writes: `emit-learning` (L2), `update-semantic` (L3 bounded append), and `atomic_state_write` (state.md frontmatter `non-resumable-actions[]`).

### L4 — Custom instructions (procedural)

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: implement`, `LOAD_TIER: pipeline`, `MODE: refresh`. The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `<slug>.md`, and `code-style.md`; its §Echo contract requires one observable line per file. Both are mandatory.

**Phase boundaries:**
- Phase 1 entry — `MODE: refresh` — scope = `implement` + `global` + `code-style` (3 files). `refresh` re-Reads every file and re-emits the Echo lines; the procedure is identical to initial-load. The mode name signals compaction-survival intent.
- Phase 3 entry — `MODE: refresh` ALWAYS — survives Phase 2 compaction. Cost: 1 extra helper read.

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

Promotion suggestion fires ONLY for `convention` emits — see reference.md §"Extract Learnings".

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
| **Phase 1 (Analyze) — orchestrator** | Read / Grep / Glob / Bash (read-only: `git status`, `gh pr view`, `git worktree add`, `git checkout -b`); Agent spawns for `knowledge-retrieval-agent` + `codebase-explorer-agent` only | Edit / Write on source code; `gh pr create`; commit; Phase 3 agent types |
| **Phase 1 subagents** | Per agent frontmatter `tools:` whitelist — see `agents/knowledge-retrieval-agent.md` and `agents/codebase-explorer-agent.md` | Edit / Write (except their own OUTPUT_PATH); Agent (leaf agents, no nesting) |
| **Phase 2 (Implement) inner loop** | Read / Grep / Glob / Edit / Write / Bash (incl. test runs); `test-runner-agent` spawn at end-of-phase | `git push`, `gh pr create`, `gh pr comment`, Phase 3 agent types |
| **Phase 2 test-runner-agent** | Bash (one test-suite invocation), Read, Grep — enforced by `agents/test-runner-agent.md` frontmatter | Edit / Write on source code; git mutation; destructive Bash; Agent (leaf agent) |
| **Phase 3 reviewer-agent spawns** | Per dim: Read / Grep / Glob / Bash (read-only) — enforced by `agents/reviewer-agent.md` frontmatter `tools:` whitelist | Edit / Write / Agent / mutating Bash / external network |
| **Phase 3 adversarial-tester-agent spawn** | Read / Write / Edit (restricted to test-file paths) / Bash (read-only) / Glob / Grep — enforced by `agents/adversarial-tester-agent.md` frontmatter `tools:` + Critical Constraints | Production-source edits; git mutation; destructive Bash; Agent (leaf agent) |
| **Phase 3 Ship sub-step** | `git commit`, `git push` (draft-grade — auto), `gh pr create` (commit-grade — AUQ-gated) | External commits before AUQ resolution |

**Existing safety layer:** file-protection hook, git-guardrail hook, and `.geniro/` deletion guard apply across ALL phases regardless of this matrix.

---

## PHASE 1: ANALYZE

State.md `phase: analyze` on entry.

**Resolve `PRIMARY_ROOT` once at Phase 1 entry.** Run the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` via Bash. Phase 1 reads handoffs at `<PRIMARY_ROOT>/.geniro/state/handoff/from-*-<branch>.md`, targeted-reads `<PRIMARY_ROOT>/.geniro/instructions/global.md` for the branch-format rule at Step 0a, and spawns knowledge-retrieval + codebase-explorer agents whose spawn-prompt slots (`KNOWLEDGE_ROOT`, `PLANNING_ROOT`, `HANDOFF_DIR`) require this value substituted to absolute paths per Mode B. Without it, the handoff probes / global.md read / subagent spawns silently fall back to cwd-relative paths and miss content in the primary worktree when /implement runs from a linked worktree.

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
| `SPEC_WORKFLOW_REFS` | If spec.md present at resolved task slug: parse `workflow_refs:` frontmatter list (per `skills/plan/spec-template.md` §Frontmatter). Empty list when field absent. |
| `BRANCH_FORMAT_RULE` | Read `<PRIMARY_ROOT>/.geniro/instructions/global.md` directly here at Step 0a. Extract any branch-format directive present (regex pattern, required components such as `<type>/<ticket>-<desc>`, ticket-prefix requirement). Empty when file absent or no branch rule documented. The custom-instructions loader at Step 5 will re-Read the same file with full echo contract; this Step 0a read is a targeted extraction so Step 0c knows the format constraint before authorizing branch creation. Without this signal, Step 0c authorizes branch names that violate project rules and the agent has to rename after the fact. |
| `TICKET_ID_IN_SCOPE` | Set to the detected ticket ID when `$ARGUMENTS` contains a Linear URL / `<TEAM>-<N>` ID, OR spec.md frontmatter `workflow_refs[]` carries one, OR `CURRENT_BRANCH` already encodes one. Empty when none in scope. Cross-checked against `BRANCH_FORMAT_RULE` at Step 0c to decide whether the no-ticket-ID sub-flow fires. |

#### 0b — Decide action

Decision tree (first match wins; evaluate top-down):

```
1. Resumable state.md exists for resolved task slug
   AND state.md frontmatter phase: ∈ {analyze, implement, self-review, ship}
   ⇒ SKIP Step 0 entirely. Resume per state.md.

2. IN_WORKTREE == true
   AND CURRENT_BRANCH ∈ continuing-work set:
     • BRANCH_MATCHES_TASK_SLUG == true, OR
     • REVIEW_HANDOFF == true, OR
     • DEBUG_HANDOFF == true, OR
     • EXISTING_TASK_STATE == true
   ⇒ AUTO-CONTINUE in current worktree. NO workspace AUQ. Echo:
        "Continuing in worktree '<dir>' on '<branch>'.
         Detected signal(s): <REVIEW_HANDOFF | DEBUG_HANDOFF | EXISTING_TASK_STATE | slug match>.
         <when REVIEW_HANDOFF == true:> Handoff carries N unresolved open question(s) — will be resolved before any code changes (open-question gate)."
      Workflow Question 2 still asked if applicable (see 0c).

3. IN_WORKTREE == false
   AND PROTECTED_BRANCH == false
   AND any of {REVIEW_HANDOFF, DEBUG_HANDOFF, EXISTING_TASK_STATE} == true
   ⇒ AUTO-CONTINUE on current branch. NO workspace AUQ. Echo:
        "Continuing on '<branch>' (detected <signal>).
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
   ⇒ Fire the full workspace AUQ (0c). Recommendation flips: "Current branch (Recommended)" since the user is on a feature branch already.
```

**Inline modifier overrides** (parsed from `$ARGUMENTS` per the Phase 1 semantic-parse table; modifiers ALWAYS win over auto-detection):

| Modifier in $ARGUMENTS | Effect |
|---|---|
| `new-branch` / `new branch` | Force rule 5 path even if a "continuing" signal is detected. |
| `current-branch` / `current branch` | Force auto-continue regardless of signals. |
| `worktree` / `new-worktree` | Force worktree creation path. |
| `no-worktree` / `here` | Force in-place execution; skips worktree even if `IN_WORKTREE == false`. |
| `--no-adversarial` | Disables Phase 3 adversarial-tester spawn for this run (skips the 6th slot in Round 1). |

Conflicting modifiers (e.g., `new-branch` AND `current-branch` both present): last-occurrence wins (right-to-left scan). Emit soft notice: `"Both 'new-branch' and 'current-branch' modifiers detected; using <last>."`

#### 0c — AUQ structure

Single `AskUserQuestion` call carrying up to 2 questions (always-WAIT, never auto-resolve):

**Question 1 — always asked when rules 5 or 6 fire:**

```
header: "Git workspace"
question: "Where should /implement land its edits?"
multiSelect: false
options:
  - label: "New feature branch (Recommended)"
    description: "git checkout -b <derived-slug>. Slug source order: $ARGUMENTS / spec.title / suggested-branch / branch-naming.md fallback. If BRANCH_FORMAT_RULE is set, the slug MUST conform to that pattern before this option creates the branch."
  - label: "Current branch"
    description: "Pre-flight only; no git mutation. Echo 'Continuing on <branch> at <toplevel>.'"
  - label: "Git worktree"
    description: "git worktree add -b <slug> .claude/worktrees/<slug>, then EnterWorktree. Isolated parallel work; instant rollback. Same BRANCH_FORMAT_RULE conformance as 'New feature branch'."
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
    description: "Terminal. No git mutation. User exits and re-invokes /implement once a ticket exists."
```

This AUQ does NOT include a "create the ticket for me" option. /implement never creates tracker artifacts — see the anti-rationalization row covering tracker-mutation authority.

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

If `1 + N > 4` (rare — task linked to ≥4 trackers), chain into a second AUQ.

#### 0d — Approvals-persistence

Persist BOTH answers to state.md `approvals[]`:

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

1. **Workspace action** — execute branch creation / worktree create / no-op per `implement_workspace_setup` pick. Slug source: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`.
2. **Workflow status action** — for each persisted `implement_workflow_status` approval, follow the workflow file's `### On task start` instructions. Skill does NOT hardcode MCP call shape — workflow file owns that.
3. **State.md frontmatter update** — `branch:` and `worktree:` reflect the new working tree before Phase 1 continues.

#### 0f — Edge cases

| Case | Behavior |
|---|---|
| Workflow MCP unavailable when Question 2 fires | Question 2 still fires; "Yes" answer logs warning and proceeds without MCP call. Non-blocking. |
| Workflow file present but `### On task start` section missing | Question 2 omitted silently. |
| User picks "Other" with custom text on Question 1 | Treat as "Current branch" semantically; no git mutation; echo custom text into state.md `## Workspace decision` body block. |
| Multiple review/debug handoffs for current branch (review AND debug both produced findings) | Both signals satisfy rule 2 of 0b. Echo both signal names; behavior otherwise identical. |
| Stale review/debug handoff (older than 30 days) | Still triggers rule 2. Emit soft notice: `"Note: review handoff is N days old. Re-run /geniro:review if you want fresh findings."` |
| `IN_WORKTREE == true` AND `PROTECTED_BRANCH == true` | Rule 5 fires (full AUQ); worktree-presence is incidental. |

### Steps (after Step 0 settles)

1. **Semantic-parse `$ARGUMENTS`.** Apply the table in `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 1: $ARGUMENTS semantic-parse table".
2. **Resolve spec source.** Walk the spec discovery list (`${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 1: Spec discovery walk-list"). If no spec.md / plan.md / DESIGN_DOC frontmatter found AND $ARGUMENTS is non-empty → inline-task mode (write `## Inline Plan` to state.md body).
3. **Disambiguate if needed.** If $ARGUMENTS is ambiguous, fire AUQ per Phase 1 table. Persist outcome to state.md frontmatter `approvals[]` with `category: disambiguate_arguments`.
4. **Resolve task slug.** Used for state.md path. If task-dir exists, validate state.md (recovery AUQ on validation fail). If task-dir is fresh, `mkdir -p`.
5. **Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: implement`, `LOAD_TIER: pipeline`, `MODE: refresh`. The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `implement.md`, and `code-style.md` (3 files); the §Echo contract requires one observable line per file. Both are mandatory.
6. **Load project snapshot.** `load_semantic` with default top-2 (`_project.md` + `_CODEBASE_MAP.md`). Optional `--extras _FEATURES.md` if spec mentions feature backlog. Fingerprint drift check fires automatically; surface drift notification to user.
7. **Spawn knowledge-retrieval + codebase-explorer agents in parallel.** ONE assistant response, TWO `Agent(...)` tool calls. Apply the spawn template in `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 1: Subagent spawn template". Apply the registration-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at each spawn site. OMIT `model=` argument — both agents declare `model: inherit`.
8. **Read subagent outputs.** Read `<task-dir>/.kr-out.md` and `<task-dir>/.ce-out.md`. The codebase-explorer's `change_scope` field gates Phase 3 adversarial-tester spawn (`trivial` → skip). Failure handling for either agent: on missing/empty output OR `Agent` tool error, one silent retry; second failure → inline-Read fallback (load top-3 exemplar files + `_CODEBASE_MAP.md` rows by Grep) with `change_scope: medium` as safe default. Emit a `diagnosis` learning with `trust: retrieved`. Echo notice to user.
9. **Query past learnings.** `query_learnings --tag <inferred> --scope <task-path> --limit 5`. Tags may be primed by the knowledge-retrieval output. Skip if task description is too generic.
10. **Resolve cross-layer conflicts.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol if instructions / snapshot / learnings disagree.
11. **Detect frontend files in scope.** Use the codebase-explorer "Likely-Touched Files" report against the UI-file detection rule (`${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` §UI-file detection rule). Gates Phase 3 design-conventions injection and Pre-Ship Visual Verification.
12. **Persist review/debug handoffs AND gate on unresolved open questions.** For every `<PRIMARY_ROOT>/.geniro/state/handoff/from-<producer>-<branch>.md` that exists:
    1. Read the file via `atomic_state_write`-safe Bash `cat` (NOT direct `Edit`/`Write`).
    2. Persist the body under state.md `## Inputs from <producer>` body section.
    3. Parse frontmatter `open_questions[]` per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2.
    4. Filter to entries with `status: unresolved`.
    5. **If the filtered list is non-empty, fire an AUQ batch BEFORE transitioning to `phase: implement`.** Chain one AUQ per unresolved entry (cap-extension when >4). Apply the 3-tier rendering procedure in `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` §2.5 — Tier 1 uses producer-authored `context`/`evidence`/`options`/`recommendation` fields; Tier 2 cross-references `related_findings[]` into the handoff body's `## Findings` section; Tier 3 is the legacy bare-question synth fallback. Set `resolution.asked_in_phase: phase-1-step-12` and `resolution.resolved_by: implement` when persisting answers (vs §2.5's `phase-6-pre-gate` / `review`).
    6. After each user pick, update the entry in the PRODUCER's handoff file via `atomic_state_write` (round-trip update): set `status: resolved`, `resolution.picked`, `resolution.at`, `resolution.asked_in_phase: phase-1-step-12`, `resolution.resolved_by: implement`. Preserve `id`, `source`, `question`, `related_findings`, `related_hypotheses`.
    7. Persist a parallel approval to state.md `approvals[]` with `category: review_handoff_resolution`, `picked: <chosen option>`, `at: <ISO-8601 UTC>`, `source_handoff: <producer>`, `question_id: <id>` for compaction-resume idempotency.
    8. After all entries are `resolved` or `wontfix`, proceed to sub-step 9.
    9. **Extract authored F→P tests when the handoff is from `/debug`.** Skip when `<producer>` is anything other than `debug` (e.g., `review`); fire only for `from-debug-<branch>.md` and `from-debug-adversarial-<branch>.md`. Apply the canonical Scan/Extract/Verify/Decide protocol in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md`:
       - **Extract** — prefer frontmatter `authored_tests[]` (m7-v2+); fall back to body `**Reproduction test:**` / `**Test file:**` parse for legacy m7-v1 handoffs.
       - **Verify** — resolve each path against this skill's current `git rev-parse --show-toplevel` and bucket as PRESENT / MISSING.
       - **Decide and surface** — Case A (all PRESENT, debug-source-branch matches) → one-line acknowledgment in the Phase 1 context summary. Case B1 (any MISSING) → surface the suggest-only relocation block from `_shared/debug-handoff.md` §Step 4; the user runs `git checkout <debug-source-branch> -- <paths>` or `cp` themselves — never auto-execute cross-branch git operations. Case B2 (all PRESENT but branches differ) → one-line "tests carried over" note. Case C (legacy fields missing) → degraded suggestion without explicit checkout command.
       - **Persist** to state.md as `Authored-tests:` (comma-separated relative paths on a single line) plus, when sourced from m7-v2+ frontmatter, `Authored-tests-intent:` (parallel comma-separated intents) and `Debug-source-branch:` / `Debug-source-worktree:`. Phase 2 reads these to prime TodoWrite decomposition — each authored test becomes a pre-existing acceptance gate, surfacing in the relevant todo's description so the production-fix work cannot ship without those tests going GREEN.
       - Authored-tests extraction is informational, NOT a gate — do NOT block transition to `phase: implement` on missing files. The user retains agency to either run the suggested commands, re-author tests in the current branch, or accept the divergence.
    10. After authored-tests handling, proceed to step 13.

   /implement is the consumer; the contract per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 forbids proceeding with Edit/Write while any `unresolved` entry remains. A consumer that ships anyway violates the contract — the producer surfaced the ambiguity precisely so it gets resolved BEFORE code changes.

13. **State.md write.** `atomic_state_write` with `phase: analyze` body sections populated → upon completion, transition `phase: implement`.

**Workflow plumbing.** Workflow integrations (`.geniro/workflow/*.md`) apply their argument-detection patterns BEFORE the semantic-parse table. Non-blocking — log warning if integration backend unavailable.

### Big-task notice

When Codebase-Explorer reports `change_scope: big` AND no `milestone-*.md` files exist alongside spec.md, emit one informational notice (NOT AUQ — just observation):

```
[Phase 1] Codebase-Explorer scope=big — consider running /geniro:plan in
milestone-mode to split into milestone-*.md siblings before /geniro:implement.
Current run will proceed monolithically with TodoWrite decomposition; cleaner
if you split.
```

Milestone-mode is the canonical answer for truly Big tasks (separate worktrees, separate /implement runs). User may cancel and re-run via `/geniro:plan --milestones`; otherwise the run proceeds.

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

4. **End-of-phase test run via `test-runner-agent`.** After all todos `completed`, spawn `test-runner-agent` once with the project's pre-resolved TEST_COMMAND (from CLAUDE.md "Essential Commands"), the CHANGED_FILES list, OUTPUT_PATH `<task-dir>/.tr-out.md`, and `MAX_FAILURES_REPORTED: 15`. Apply the registration-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`. OMIT `model=`. Read back the OUTPUT_PATH report. Attach the report's Command / Exit code / Summary / Verdict block as Evidence per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`.

5. **In-phase fix loop on test failure.** Up to 3 retries (full pseudo-code + token-cost analysis: `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 2: Implement — error-handling"). On each retry: read `.tr-out.md`, exit on `ALL_GREEN`, escalate-AUQ immediately on `INFRA_ERROR`, edit top-priority failures on `HAS_FAILURES`, re-spawn `test-runner-agent`. Retry exhaust → escalate-AUQ.

6. **Escalation on retry exhaust or INFRA_ERROR.** Fire AUQ (header: `"Test failure"`):
   - A) Hand off to /geniro:debug — state.md `phase: debug-handoff` (terminal)
   - B) Accept failing tests as documented limitation — state.md `phase: self-review`, append `## Accepted Failures` block
   - C) Abort — state.md `phase: aborted` (terminal)

   Empty answer = upstream bug, fall back to plain text and re-ask. NEVER auto-default.

**State.md update on phase exit.** `phase: self-review` (happy path) or `phase: phase-2-escalated` (if escalation fires). On `aborted`, write `## Termination reason: repeated-failure: phase-2 retry-limit (<N> failing tests)`.

**L2 emit on retry exit.** When Phase 2 exits AND `retry_count ≥ 2` (i.e., at least one fix-iteration happened), call `emit-learning` with `type: retry_failure_sequence`, `trust: verified`, required `ext.{phase: "phase-2-fix-loop", attempts: [...], resolution}`. Each `attempts[]` entry = `{round: N, failure: "<one-line summary>"}`. `resolution ∈ {passed, escalated, aborted}` matches the actual exit state. Sliding-window cap = 3 latest per `(producer, scope, phase)`; on overflow, mark oldest `deprecated: true` via direct edit BEFORE appending. Single-retry exits (retry_count == 1) do NOT emit. Future Phase 1 `query-learnings` calls surface this as priming context.

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
       ↓
  Phase 3
```

---

## PHASE 3: SELF-REVIEW + SHIP

**State.md `phase: self-review`** on entry.

**Refresh L4 instructions** (always, regardless of compaction-marker presence). Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `MODE: refresh`, scope = same as Phase 1.

**Idempotent green-light verification on entry.** Re-run test suite once. Should be green from Phase 2. If not, rollback to Phase 2 retry loop (treats as a retry round).

**Resolve `PRIMARY_ROOT` before the parallel reviewer batch fires.** Run the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` via Bash. The custom-reviewer discovery in Step 1 calls `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md`, which dual-globs `.geniro/instructions/review-extra/*.md` against cwd AND `<PRIMARY_ROOT>/.geniro/instructions/review-extra/*.md` — without the slot in scope, a linked-worktree session sees an empty `.geniro/instructions/` even when user-authored review-extra files exist on the main worktree.

### Steps

1. **Round 1 parallel spawn — reviewer-agents + 1 adversarial-tester-agent in the SAME assistant response.** Multiple `Agent(...)` tool uses in one message. Apply the registration-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at every spawn site. OMIT `model=` at every spawn site (every agent declares `model: inherit`).

   - **reviewer-agents** — one per dimension. Apply `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 3: Self-review reviewer-agent template". Dimensions: `bugs` / `security` / `architecture` / `tests` / `code-quality`. The `architecture` dim covers docs-staleness AND spec-compliance. See reference.md §"The reviewer dimensions" for full criteria-file mapping.

   - **1 adversarial-tester-agent** — apply `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 3: Adversarial-tester spawn template". The agent authors F→P-verified failing tests against the diff and writes them to the project's test directory. SKIPPED on either of two conditions:
     - Codebase-Explorer `change_scope: trivial`, OR
     - `--no-adversarial` modifier present in `$ARGUMENTS`.

   - **Custom reviewer dimensions** — discovered once at Round 1 entry via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` (`.geniro/instructions/review-extra/<slug>.md`, ≤10 cap, path-filtered). Append one `Agent(subagent_type="reviewer-agent",...)` call per spec to the same parallel batch.

2. **Collect findings.** Reviewer-agent output schema per `agents/reviewer-agent.md` §Output Format. Adversarial-tester output schema per `agents/adversarial-tester-agent.md` §Output Schema AND authored test files on disk under the project's test directory. Cap per-dim output at ~4K chars (invariant #4); truncate with marker on overflow.

3. **Bounded fix loop.** Up to 3 rounds. Full pseudo-code + drop-rules for round N+1 + adversarial-as-6th-dim mechanics: `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 3: Bounded fix loop". Summary: on each round, collect findings from the parallel spawns; if clean AND no authored adversarial tests still fail, exit to Ship; otherwise apply fixes inline (no further agent spawns), re-spawn `test-runner-agent` (rollback to Phase 2 if not green), increment round, then re-spawn ONLY the failing reviewer dims (and the adversarial-tester conditionally). Round 4 entry is forbidden — escalate-AUQ instead.

4. **Escalation on round-3 exhaust.** AUQ (header: `"Resolve findings"`):
   - A) Hand off to /geniro:debug — state.md `phase: debug-handoff` (terminal)
   - B) Accept findings, ship anyway — state.md `phase: ship`, append `## Accepted Findings` block
   - C) Abort — state.md `phase: aborted` (terminal)

   Empty answer = upstream bug, fall back to plain text and re-ask. NEVER auto-default.

### Ship sub-step

State.md `phase: ship` on entry.

1. **Pre-Ship Visual Verification** — fires only when frontend files in scope AND Playwright MCP available. Apply `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Pre-Ship Visual Verification".
2. **Commit.** Stage relevant files, `git commit` with conventional message (e.g., `feat(auth): add OAuth login [ENG-123]`). Task ID inferred from spec.md / state.md metadata.
3. **Ship-mode AUQ.** Push is draft-grade (auto); AUQ gates only commit-grade PR creation. See `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Commit + Push + PR" for the canonical AUQ shape and approvals-persistence protocol. Inline modifiers from $ARGUMENTS (`"don't push"`, `"draft only"`, `"with PR"`, `"stop after review"`) override the AUQ deterministically.
4. **Atomic `non-resumable-actions[]` update.** After each side-effect that cannot be replayed safely (`git push`, `gh pr create`, posted PR comment), append a structured entry to state.md frontmatter `non-resumable-actions[]` array via `atomic_state_write`. Entry schema `{action, completed-at, <action-specific-fields>}`. Write AFTER the side-effect succeeds — atomic, so partial-write corruption is impossible mid-crash.
5. **Emit learnings.** Emit `convention` to learnings.jsonl when ≥3-instance pattern detected; emit `decision` if spec.md recorded a non-trivial approach choice. Default trust = `verified`. Surface promotion suggestion only for `convention` type. Apply `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Extract Learnings".
6. **Update project snapshot.** If Phase 2 added a new module, `update_semantic --file codebase-map --append "..."`. Lock-guarded; rc=11 = recoverable skip.
7. **Update Docs / Suggest Improvements / Integration Updates / Cleanup.** Apply reference.md sub-sections in order. Cleanup deletes only transient subagent outputs — durable artifacts (`spec.md`, `state.md`, `plan-*.md`, `milestone-*.md`) survive Ship for downstream /review / /debug / /refactor / Adjustment Routing consumers:

```bash
rm -f "<task-dir>"/.kr-out.md \
      "<task-dir>"/.ce-out.md \
      "<task-dir>"/.tr-out.md \
      "<task-dir>"/.adversarial-out.md \
      "<task-dir>"/notes.md \
      "<task-dir>"/playwright-verify.png
# spec.md, state.md, plan-*.md, milestone-*.md remain
```
8. **State.md final transition.** Frontmatter `phase: done` (or `ship-committed-only` / `self-review-only` depending on modifier / user pick). The SessionStart hook treats terminal states as "no resume needed".

### Adjustment routing (post-ship feedback)

When ship-feedback arrives via PR comments or as a follow-up `$ARGUMENTS` invocation, route per the Big/Medium/Small classification in `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 3 — Adjustment Routing".

---

## Modifier handling (semantic, deterministic)

Inline modifiers from Phase 1 `$ARGUMENTS` parse override AUQ defaults deterministically. Modifier scope groups: workspace (Step 0), adversarial-tester (Phase 3), ship mode (Ship sub-step).

| Modifier | Effect |
|---|---|
| `new-branch` / `new branch` | Step 0: force "New feature branch" path even if a "continuing" signal is detected. |
| `current-branch` / `current branch` | Step 0: force auto-continue regardless of signals. |
| `worktree` / `new-worktree` | Step 0: force worktree creation path. |
| `no-worktree` / `here` | Step 0: force in-place execution; skips worktree even if `IN_WORKTREE == false`. |
| `--no-adversarial` | Phase 3 Round 1: disable adversarial-tester spawn (reviewer-agents only; custom dimensions still spawn). |
| "don't push" / "no push" / "commit only" | Ship: commit succeeds, no push. State.md → `phase: ship-committed-only` (terminal). Skip ship-mode AUQ. |
| "draft only" / "draft PR" / "open draft" | Ship: push + `gh pr create --draft`. State.md → `phase: done`. Skip ship-mode AUQ. |
| "open PR" / "create PR" / "with PR" | Ship: push + `gh pr create` (ready-for-review). State.md → `phase: done`. Skip ship-mode AUQ. |
| "stop after review" | Ship: exit Phase 3 BEFORE commit. Clean review status is the deliverable. State.md → `phase: self-review-only` (terminal). |

When no ship-mode modifier is present, the ship-mode AUQ fires. Conflicting modifiers (e.g., `new-branch` AND `current-branch`): last-occurrence wins (right-to-left scan); emit soft notice naming both detected variants.

---

## Task execution entry

0. **Check for existing state.md.** Glob `<task-slug>/state.md`:
- **No state.md** → fresh run. Proceed to Phase 1.
- **state.md exists, phase in non-terminal set** → resume from `phase:` value. The SessionStart hook hook re-injects context.
- **state.md exists, phase in terminal set** → task complete. Surface terminal state to user; if `$ARGUMENTS` carries new task description, derive new slug, fresh run.

1. **Validate state.md if found** (`validate_state_file`). On fail, open recovery AUQ (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency).

2. **TodoWrite checklist.** Add: Phase 1 Analyze / Phase 2 Implement / Phase 3 Self-review-and-Ship. Mark Phase 1 in_progress; update each as it completes.

3. **Begin Phase 1.**

---

## Anti-rationalization

These patterns must NOT be reintroduced:

| Your reasoning | Why it's wrong |
|---|---|
| "/implement should ask user before each Edit — safety first." | Phase 2 Implement is the execution phase. Pre-approval lives upstream — /geniro:plan Phase 8 emits the spec.md; that spec.md IS the pre-approval. Per-Edit AUQs defeat the spec-driven autonomy this skill is designed for. |
| "Phase 2 should fan out backend/frontend agents for parallel edits — saves wall-time." | Documented anti-pattern: parallel agents editing tightly-interdependent code (frontend/backend sharing a contract, modules sharing types/imports) produce style drift, duplicated implementations, and contradictions that lint/compile cannot catch. Phase 2 uses sequential TodoWrite decomposition within a single orchestrator — same throughput on truly parallel work-units (rare in real implementation slices), much higher quality on tightly-coupled ones. |
| "Mark all todos in_progress at start so the orchestrator can interleave work." | Forbidden by Loop invariant #9. Single-in-progress is Claude Code's enforced Tasks API design; scattered parallel attempts hurt quality. Mark the next todo `in_progress` only after the current todo completes. |
| "Skip TodoWrite — it's overhead; the orchestrator knows the spec already." | TodoWrite gives the user granular progress visibility. Without it, Phase 2 is a black box until tests run. With it, the user sees real-time per-unit progress. Not optional. |
| "Spawn one subagent per todo to keep context lean." | Hybrid TodoWrite-plus-per-todo-subagent only works if each todo has truly independent spec + tests + worktree. For typical implementation slices that share types, imports, and conventions, per-todo subagents reintroduce the context-sharing problem. Phase 2 todos share too much context — keep single-agent. |
| "Re-run tests after each file Edit to catch regressions early." | Single end-of-Phase-2 test run via `test-runner-agent`. Per-file test runs explode wall-time on slow suites and burn turns inside the runner agent (one invocation per spawn). |
| "/implement should self-fix indefinitely until reviews clean." | Phase 3 fix loop is bounded to 3 rounds. Past 3 unresolved rounds, escalate via AUQ — never silently loop. "Kick it until it passes" is a catalogued anti-pattern; round 4 entry is forbidden. |
| "Skip the ship-mode AUQ — the diff is small / this is a debug-handoff follow-up / user already approved upstream / user can `git reset` afterward." | Push is draft-grade (auto), but PR creation is commit-grade (AUQ-gated). The AUQ fires regardless of diff size, regardless of debug-handoff or review-handoff origin, and regardless of which Phase 2 path led to Ship — none of those are documented modifier-equivalents. The only sanctioned bypass is the 4 inline modifiers (`don't push`, `draft only`, `with PR`, `stop after review`) parsed from `$ARGUMENTS`; everything else fires the AUQ. PR creation is irreversible visibility — CI runs trigger, reviewers get notified, GitHub fires notifications, the URL is shareable — so the gate sits at the visibility boundary, not the diff-size boundary. A small fix opening as a non-draft PR is just as visible as a large refactor opening as a non-draft PR. |
| "Audit trail isn't needed for local /implement runs." | The state.md `## Tool log` IS the audit trail. The SessionStart hook re-injects on compaction. Without log, post-mortem on failed runs is impossible. |
| "Bypass safety hooks with --no-verify when commit-hook fails — saves time." | Hooks fail for a reason. Investigate root cause, not bypass. --no-verify usage is a CLAUDE.md-level prohibition. |
| "Spawn agents one at a time for cleaner orchestration / it's a small diff so a quick `bugs`-only review is enough / 1-2 dimensions cover the important risks." | All Phase 3 Round 1 spawns happen in ONE assistant response (reviewer-agents + adversarial-tester) — multiple `Agent(...)` tool uses in the same message. Diff size does not trim the reviewer count: the reviewer dimensions (`bugs` / `security` / `architecture` / `tests` / `code-quality`) cover orthogonal concerns; spawning only `bugs` blinds the run to security regressions, architectural drift, test gaps, and quality issues. The only sanctioned trims of the parallel batch are: (a) Codebase-Explorer `change_scope: trivial` strips the adversarial slot, (b) `--no-adversarial` modifier strips the same slot. The reviewer slots are mandatory regardless of diff size, regardless of how the change originated (debug-handoff, review-handoff, or fresh spec). Same parallel-spawn rule for Phase 1 KR + CE: ONE response, two spawns. Separate turns = no concurrency. |
| "Pass `model=\"sonnet\"` at every spawn site for predictable cost." | Plugin agents declare `model: inherit` in frontmatter; OMIT `model=` at every spawn site. Passing a hardcoded tier defeats the user's session-level `/model` choice and breaks the universal inherit contract. The only exception is user-authored custom reviewers whose own frontmatter declares an explicit tier — honor the user's declaration. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. |
| "/implement should fire a user-approval AUQ before Phase 3 adversarial-tester spawn, mirroring /review Phase 4c." | /review needs the AUQ because its contract is read-only reporter — spawning a test author is a scope expansion past contract. /implement is already authorized to mutate code (Phase 2 IS the mutation phase). Phase 3 adversarial test authoring is symmetric to Phase 2 code authoring, NOT a new authority surface. Phase 8 spec.md approval covers it. Use `--no-adversarial` modifier for explicit opt-out. |
| "Branch format requires a ticket prefix per global.md — I'll create the Linear / Jira / GitHub-Issues ticket so the slug conforms." | /implement never creates tracker artifacts. Per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-reference.md` mutation-responsibility note: /implement mutates tracker state (status transitions at Step 0c kickoff + Phase 3 Ship completion) but does not create tickets, issues, epics, or sub-tasks. A branch-format rule that demands a ticket ID is satisfied by user-provided ID (Step 0c no-ticket-ID sub-flow option A), placeholder slug (option B), or cancellation (option C) — never by inventing an upstream artifact. Tracker creation is a human authoring action, not a code-execution side-effect; an agent-created ticket appears in the user's tracker without authorization and triggers downstream artifacts (notifications, dashboard rows, sprint-planning surface area) the user did not approve. |
| "/implement should inline-Read every relevant .claude/rules/, exemplar, and prior plan for thoroughness." | Loop invariant #8. Phase 1 delegates investigation reads to Knowledge-Retrieval + Codebase-Explorer subagents; orchestrator inline-Reads only L4 (3 files), L3 (2 files), spec.md, and state.md. `.claude/rules/*.md` bodies and exemplar sources are JIT-loaded in Phase 2 only when an Edit target matches the rule's `paths:` glob (using the path list returned by Codebase-Explorer). Inline-reading the rest is the documented context-bloat regression. |

---

