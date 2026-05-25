---
name: geniro:implement
description: "Use when shipping a new feature, endpoint, page, or significant change against a spec.md / plan.md (from /geniro:plan) OR a raw inline task description. 2-phase autonomous loop: Analyze → Implement → Self-review-and-Ship."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, WebSearch, EnterWorktree]
argument-hint: "[task description | spec.md path | empty to resume | 'continue']"
---

# Implement Skill — 2-Phase Autonomous Loop

**You are an autonomous executor.** You consume an externally-provided spec (or inline task description), make all required code edits, run the test suite, then run a 5-dim self-review pass before shipping. Strategic concerns belong upstream in `/geniro:plan`. runs a single solo execution path per task.

**Phases:**

1. **Analyze (Phase 1)** — semantic-parse `$ARGUMENTS`, resolve spec source (spec.md / plan.md / DESIGN_DOC frontmatter OR inline-task fallback), refresh L4+L3 memory, persist T2 handoffs to state.md.
2. **Implement (Phase 2)** — single whole-feature edit batch; one end-of-phase test-suite run; bounded 3-retry fix loop on test failure → escalate-AUQ on exhaust.
3. **Self-review + Ship (Phase 3)** — 5 built-in reviewer-agents in parallel (bugs / security / architecture / tests / code-quality) + any custom dimensions discovered via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` (`.geniro/instructions/review-extra/<slug>.md`, ≤10 cap, path-filtered); bounded 3-round fix loop, round N+1 = failing dims only; on clean exit, ship sub-step (Pre-Ship Visual Verification if applicable, commit, ship-mode AUQ, L2/L3 writes, cleanup).

**Reference material** (templates, $ARGUMENTS-parse table, reviewer-agent spawn template, fix-loop, ship sub-step): Read `${CLAUDE_SKILL_DIR}/implement-reference.md` AT each phase. Do NOT pre-load the entire file.

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

**Termination reason convention.** When `phase: aborted` is reached, write one line to state.md body under `## Termination reason`: `repeated-failure: phase-N retry-limit` / `safety-denied: <rule>` / `tool-unavailable: <tool>`. the SessionStart re-injects this on resume.

---

## Loop invariants

Apply throughout all 3 phases:

1. **One result per tool call.** Every Edit / Write / Bash / Agent spawn produces exactly one structured result. Failed spawn → result with `status: failed`; never absent.
2. **Args validated before execution.** Bash commands constructed from $ARGUMENTS or state.md fields pass input sanity-checks. Paths absolute; slugs match §Slug rules.
3. **Permission before side-effect.** Any tool call mutating external state (`git push`, `gh pr create`, posted PR comment) is preceded by AUQ approval or recorded approval (persisted via schema).
4. **Bounded and structured tool results.** Reviewer-agent output capped at ~4000 chars per dimension; longer truncated with marker. Bash output >8000 chars summarized before downstream use.
5. **Escalation gates, not silent abort.** Bounded retry loops (3 rounds in, 3 rounds in) surface to user via `AskUserQuestion` at exhaustion — never silent abort, never infinite loop.
6. **Final answer grounded in observations.** Phase 3 Ship result text MUST quote actual tool output (push ref, PR URL, commit SHA) — never "git push succeeded" without evidence. Self-review reads `## Tool log` entries before claiming clean state.
7. **Errors, denials, cancellations, timeouts → structured observations.** Failed `gh pr create`, denied permission, hook-blocked Write, subagent timeout, non-zero Bash exit becomes a structured observation entry — never silently skipped.

**Side-effect — `## Tool log` section in state.md.** Invariants 1 and 7 motivate persisting subagent-spawn outcomes and side-effect tool calls (`git push`, `gh pr create`, file deletions) into a body section per the schema in `${CLAUDE_SKILL_DIR}/implement-reference.md`. Routine Read/Edit/Bash on local files do NOT need logging — Claude Code's tool_result return is sufficient.

---

## Budgets — quality-first framing

**NO hard kill caps.** No wall-time / tool-call / model-turn / cost ceilings. User tokens unlimited.

**Quality gates (Class-B — escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Fix-loop retries per phase | 3 | (Phase 2 test fix), (Phase 3 review round) | AUQ — debug-handoff / accept-failure / abort. User picks. |
| Reviewer output size | ~4K chars per dim | invariant #4 | Truncation with marker, NOT abort. |

**Architecture constraints (design intent, not budget):**
- Parallel reviewer spawns per round: 5 dimensions (`bugs` / `security` / `architecture` / `tests` / `code-quality`).

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

Where `<task-slug>` is derived from $ARGUMENTS / spec.md filename / git branch §Slug rules. Created at start of Phase 1.

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

Phase 1 entry triggers four helper calls — three reads + one cross-layer protocol:

1. `load-custom-instructions` (L4) with `MODE: refresh` — see §L4 below.
2. `load-semantic` (L3) with `MODE: refresh` — see §L3 below. Procedure identical under both modes ; the mode name signals compaction-survival intent.
3. `query-learnings` (L2) — see §L2 below.
4. `resolve-conflicts` (L4/L3/L2 protocol) — see §Cross-layer conflict surfacing. Fires only if disagreement detected after the three reads.

Phase 2 makes no new helper calls. Phase 3 entry re-fires `load-custom-instructions(MODE: refresh)` AND fires `load-custom-reviewers` once (round 1 only) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` — spawn-specs are appended to the parallel reviewer batch alongside the 5 built-ins. Phase 3 fix-loop iterations may re-fire `query-learnings`. Phase 3 ship sub-step adds writes: `emit-learning` (L2), `update-semantic` (L3 bounded append), and `atomic_state_write` (T1 frontmatter `non-resumable-actions[]`).

### L4 — Custom instructions (procedural)

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: implement`, `LOAD_TIER: pipeline`, `MODE: refresh` (used at both Phase 1 entry and Phase 3 entry ). The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `<slug>.md`, and `code-style.md`; its §Echo contract requires one observable line per file. Both are mandatory.

**Phase boundaries:**
- Phase 1 entry — `MODE: refresh` — scope = `implement` + `global` + `code-style` (3 files). makes `refresh` the universal "re-Read and announce" pattern; procedure identical to initial-load (every Read fires) but the mode name signals compaction-survival intent.
- Phase 3 entry — `MODE: refresh` ALWAYS — survives Phase 2 compaction without requiring an marker contract. Cost: 1 extra helper read.

The Echo contract survives compaction via the SessionStart re-injection.

### L3 — Semantic snapshot

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh"
load_semantic # default: _project.md + _CODEBASE_MAP.md
load_semantic --extras "_FEATURES.md" # if spec mentions feature backlog
```

**Phase 1 entry only.** Conceptual `MODE: refresh` per — no MODE flag on the function; procedure identical under both modes (every Read fires, fingerprint drift check fires). Drift notification surfaces to user if `.fingerprint.json` mismatched. Phase 3 does NOT re-load L3 (Phase 2 doesn't materially mutate L3 — `update-semantic` writes are bounded to single-line append on `_CODEBASE_MAP.md`).

### L2 — Episodic event log

**Read (Phase 1 entry):**

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh"
query_learnings --tag <inferred-tag> --scope <inferred-scope> --limit 5
```

Tags inferred from task description (e.g., `react`, `auth`, `bug`); skipped if task description is too generic. Compaction-immune helper per — no MODE parameter.

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

Triggers
- `type=convention` → when Phase 3 architecture or code-quality reviewer reports ≥3 instances of same pattern.
- `type=decision` → when spec.md records a non-trivial approach choice with `## Considered Alternatives` (inline-task path only; once /plan ships, /plan emits decisions directly).

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
| **Phase 1 (Analyze)** | Read / Grep / Glob / Bash (read-only: `git status`, `gh pr view`) | All mutations |
| **Phase 2 (Implement) inner loop** | Read / Grep / Glob / Edit / Write / Bash (incl. test runs) | `git push`, `gh pr create`, `gh pr comment`, Agent spawns (Phase 3 territory only) |
| **Phase 3 reviewer-agent spawns** | Per dim: Read / Grep / Glob / Bash (read-only) — enforced by `agents/reviewer-agent.md` frontmatter `tools:` whitelist | Edit / Write / Agent / mutating Bash / external network |
| **Phase 3 Ship sub-step** | `git commit`, `git push` (draft-grade — auto per ), `gh pr create` (commit-grade — AUQ-gated) | External commits before AUQ resolution |

**Existing safety layer:** file-protection hook, git-guardrail hook, and `.geniro/` deletion guard apply across ALL phases regardless of this matrix.

---

## PHASE 1: ANALYZE

**Load L4 instructions (first action).** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: implement`, `LOAD_TIER: pipeline`, `MODE: refresh`. The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `implement.md`, and `code-style.md` (3 files, pipeline tier); the §Echo contract requires one observable line per file. Both are mandatory.

**Refresh L3 semantic snapshot.** `load_semantic` with default top-2 (`_project.md` + `_CODEBASE_MAP.md`). Optional `--extras _FEATURES.md` if spec mentions feature backlog. Fingerprint drift check fires automatically; surface drift notification to user.

### Steps

1. **Semantic-parse `$ARGUMENTS`.** Apply the table in `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 1: $ARGUMENTS semantic-parse table".
2. **Resolve spec source.** Walk the spec discovery list (`${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 1: Spec discovery walk-list"). If no spec.md / plan.md / DESIGN_DOC frontmatter found AND $ARGUMENTS is non-empty → inline-task mode (write `## Inline Plan` to state.md body).
3. **Disambiguate if needed.** If $ARGUMENTS is ambiguous, fire AUQ per Phase 1 table. Persist outcome to state.md frontmatter `approvals[]` with `category: disambiguate_arguments`.
4. **Resolve task slug.** Used for state.md path. If task-dir exists, validate state.md (recovery AUQ on validation fail). If task-dir is fresh, `mkdir -p`.
5. **Query L2 learnings.** `query_learnings --tag <inferred> --scope <task-path> --limit 5`. Skip if task description is too generic to infer tags.
6. **Resolve cross-layer conflicts.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol if L4/L3/L2 disagree.
7. **Detect frontend files in scope.** Gates Phase 3 reviewer-agent design-conventions injection and Phase 3 Pre-Ship Visual Verification.
8. **Persist T2 handoffs.** If `.geniro/state/handoff/from-<producer>-<branch>.md` exists, read and persist under state.md `## Inputs from <producer>` body section. obligation.
9. **State.md write.** `atomic_state_write` with frontmatter `phase: analyze` → upon completion `phase: implement`.

**Workflow plumbing.** Workflow integrations (`.geniro/workflow/*.md`) apply their argument-detection patterns BEFORE the semantic-parse table. Non-blocking — log warning if integration backend unavailable.

**Git-workspace setup.** Setup happens via workflow integration OR inline modifier OR existing checkout. If user provided a bare task description with no workspace hint, fire a single workspace AUQ (header: `"Git workspace"`):
- A) New feature branch (recommended for most features)
- B) Current branch
- C) Git worktree (`.claude/worktrees/<dir>` — isolated; allows parallel work or instant rollback)

Persist choice to state.md `## Workspace`.

---

## PHASE 2: IMPLEMENT

**State.md `phase: implement`** during this phase.

**No L4 / L3 refresh at Phase 2 entry** — code-style instructions from Phase 1 remain in context.

### Steps

1. **Read spec source** (Phase 1 resolved either a spec.md path OR wrote `## Inline Plan` to state.md body).
2. **Whole-feature edit batch**. Make all required Edit/Write changes to the codebase in a single phase pass. NOT file-by-file. NOT sub-task decomposition.
3. **Run project test suite ONCE at end-of-phase.** Use commands from CLAUDE.md's Essential Commands section. Attach an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` (command, exit code, last 3 lines).
4. **In-phase mini fix loop on test failure.** Up to 3 retries:
```
retry = 1
while retry ≤ 3:
inspect failing test output
edit code (or test) to address the failure
re-run test suite
if all green → exit Phase 2 to Phase 3
retry += 1
else:
escalate
```
5. **Escalation on retry exhaust.** Fire AUQ (header: `"Test failure"`):
- A) Hand off to /geniro:debug — state.md `phase: debug-handoff` (terminal)
- B) Accept failing tests as documented limitation — state.md `phase: self-review`, append `## Accepted Failures` block
- C) Abort — state.md `phase: aborted` (terminal)

Empty answer = upstream bug, fall back to plain text and re-ask. NEVER auto-default.

**State.md update on phase exit.** `phase: self-review` (happy path) or `phase: phase-2-escalated` (if fires). On `aborted`, write `## Termination reason: repeated-failure: phase-2 retry-limit (<N> failing tests)`.

**L2 emit on retry exit.** When Phase 2 exits AND `retry_count ≥ 2` (i.e., at least one fix-iteration happened), call `emit-learning` with type=`retry_failure_sequence`, trust=`verified`, required `ext.{phase: "self-review-fix-loop", attempts: [...], resolution}`. Each `attempts[]` entry = `{round: N, failure: "<one-line summary of what was wrong on that round>"}`. `resolution` ∈ `{passed, escalated, aborted}` matching the actual exit state. Sliding-window cap = 3 latest per `(producer, scope, phase)`; on overflow, mark oldest `deprecated: true` via direct edit BEFORE appending. Single-retry exits (retry_count == 1) do NOT emit — too-noisy for useful pattern detection. Future Phase 1 query-learnings calls surface this as «past similar work needed N rounds; common misses: <...>» to prime reviewer-agent prompts.

---

## PHASE 3: SELF-REVIEW + SHIP

**State.md `phase: self-review`** on entry.

**Refresh L4 instructions** (always, regardless of compaction-marker presence). Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `MODE: refresh`, scope = same as Phase 1.

**Idempotent green-light verification on entry.** Re-run test suite once. Should be green from Phase 2. If not, rollback to Phase 2 retry loop (treats as a retry round).

### Steps

1. **Round 1 spawn — all 5 dims in parallel.** Apply `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 3: Self-review reviewer-agent template". One `Agent(subagent_type="reviewer-agent",...)` call per dimension, all five in the SAME assistant response.

Dimensions: `bugs` / `security` / `architecture` / `tests` / `code-quality`. Architecture dim covers docs-staleness + spec-compliance (OQ-9 + master plan). See reference.md §"The 5 dimensions" table for full criteria-file mapping.

2. **Collect findings.** Reviewer-agent output schema per `agents/reviewer-agent.md` §Output Format. Cap per-dim output at ~4K chars (invariant #4); truncate with marker on overflow.

3. **Bounded fix loop.** Up to 3 rounds:
```
round = 1
while round ≤ 3:
collect findings from this round's spawns
if no findings across all dimensions:
break # exit to Ship sub-step
apply fixes inline (single Edit-driven sub-loop, NO further agent spawns)
re-run project test suite (must stay green; if not, rollback to Phase 2)
round += 1
spawn reviewer-agents on failing dimensions only (round N+1 ≠ all 5)
else:
# round 4 would start — DO NOT enter
escalate via AskUserQuestion
```

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
5. **L2 auto-emit.** Emit `convention` to learnings.jsonl when ≥3-instance pattern detected; emit `decision` if spec.md recorded a non-trivial approach choice. Default trust = `verified`. Surface promotion suggestion only for `convention` type. Apply `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Extract Learnings".
6. **L3 update.** If Phase 2 added a new module, `update_semantic --file codebase-map --append "..."`. Lock-guarded; rc=11 = recoverable skip.
7. **Update Docs / Suggest Improvements / Integration Updates / Cleanup.** Apply reference.md sub-sections in order. Cleanup deletes `<task-dir>` per T1 contract (ephemeral, deleted at Phase Ship).
8. **State.md final transition.** Frontmatter `phase: done` (or `ship-committed-only` / `self-review-only` depending on modifier / user pick). the SessionStart treats terminal states as "no resume needed".

### Adjustment routing (post-ship feedback)

When ship-feedback arrives via PR comments or as a follow-up `$ARGUMENTS` invocation, route per the Big/Medium/Small classification in `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 3 — Adjustment Routing".

---

## Modifier handling (semantic, deterministic)

Inline modifiers from Phase 1 `$ARGUMENTS` parse override the ship-mode AUQ deterministically:

| Modifier | Effect |
|---|---|
| "don't push" / "no push" / "commit only" | Commit succeeds, no push. State.md → `phase: ship-committed-only` (terminal). Skip ship-mode AUQ. |
| "draft only" / "draft PR" / "open draft" | Push + `gh pr create --draft`. State.md → `phase: done`. Skip ship-mode AUQ. |
| "open PR" / "create PR" / "with PR" | Push + `gh pr create` (ready-for-review). State.md → `phase: done`. Skip ship-mode AUQ. |
| "stop after review" | Exit Phase 3 BEFORE commit. Clean review status is the deliverable. State.md → `phase: self-review-only` (terminal). |

When no modifier is present, the ship-mode AUQ fires.

---

## Task execution entry

0. **Check for existing state.md.** Glob `<task-slug>/state.md`:
- **No state.md** → fresh run. Proceed to Phase 1.
- **state.md exists, phase in non-terminal set** → resume from `phase:` value. the SessionStart hook re-injects context.
- **state.md exists, phase in terminal set** → task complete. Surface terminal state to user; if `$ARGUMENTS` carries new task description, derive new slug, fresh run.

1. **Validate state.md if found** (`validate_state_file`). On fail, open recovery AUQ (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency).

2. **TodoWrite checklist.** Add: Phase 1 Analyze / Phase 2 Implement / Phase 3 Self-review-and-Ship. Mark Phase 1 in_progress; update each as it completes.

3. **Begin Phase 1.**

---

## Anti-rationalization

Per master plan anti-patterns guardrail — must NOT reintroduce these:

| Your reasoning | Why it's wrong |
|---|---|
| "/implement should ask user before each Edit — safety first." | Phase 2 Implement is the **execution** phase. Pre-approval lives upstream — /plan Phase 8 emits the spec.md; that spec.md IS the pre-approval. Per-Edit AUQs defeat the spec-driven autonomy This skill is designed for. |
| "Add a wall-time kill cap so long-running tasks abort cleanly." | Class-A hard caps abort legitimate complex work mid-stride. quality-first framing — no Class-A caps. Past three failed Phase-2 retries escalates to user via AUQ. |
| "Phase 2 should fan out backend/frontend agents for parallel edits." | — work-unit decomposition removed. Scheduler complexity overwhelmed the value. Single solo inner loop, one test run at end. |
| "Re-run tests after each file Edit to catch regressions early." | — single end-of-Phase-2 test run. Per-file test runs explode wall-time on slow suites. |
| "/implement should self-fix indefinitely until reviews clean." | — bounded to 3 rounds. Past 3, escalate AUQ. «Kick it until it passes» is a catalogued anti-pattern. |
| "Skip the ship-mode AUQ — user can `git reset` if they wanted a draft PR." | step 3 — push is draft-grade (auto), but PR creation is commit-grade (AUQ-gated). Inline modifiers provide deterministic overrides. |
| "Auto-promote L2 conventions to L4 rules when ≥3-pattern detected." | step 5 + — surface a suggestion line; do NOT auto-promote. User remains source-of-truth for L4 rule curation. |
| "Defer compaction-survival to downstream skills — This skill is too complex to wire it up." | The contract IS this skill's contract — state.md frontmatter, `non-resumable-actions[]`, `## Tool log`. Without these, compaction mid-Phase-2 loses the entire run. Non-negotiable. |
| "Run reviewers serially — easier to debug than parallel-spawn batch." | — parallel spawn in ONE assistant response. Serial spawn doubles wall-time. Wrong trade-off. |
| "Audit trail isn't needed for local /implement runs." | The state.md `## Tool log` IS the audit trail. the SessionStart re-injects on compaction. Without log, post-mortem on failed runs is impossible. |
| "Bypass safety hooks with --no-verify when commit-hook fails — saves time." | Hooks fail for a reason. Investigate root cause, not bypass. --no-verify usage is a CLAUDE.md-level prohibition. |
| "Spawn agents one at a time for cleaner orchestration." | All 5 reviewer spawns in ONE assistant response — multiple `Agent(...)` tool uses in the same message. Separate turns = no concurrency, full wall-clock latency per agent. |
| "Fall back to sonnet → opus escalation on reviewer failure." | doesn't ship runtime-escalation. Reviewer at `sonnet` (declared in agents/reviewer-agent.md frontmatter) handles all dimensions. Sonnet-Opus escalation belongs to a future review-tier-escalation feature, not the baseline self-review loop. |

---

## REFERENCE

- Templates, $ARGUMENTS-parse table, reviewer-agent spawn template, fix-loop, ship sub-step: `${CLAUDE_SKILL_DIR}/implement-reference.md`
- Reviewer-agent contract: `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md`
- Review criteria files: `${CLAUDE_PLUGIN_ROOT}/skills/review/` (bugs, security, architecture, tests, optimizations, guidelines, conventions, +design when UI files changed)
- State helpers: `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh`, `${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh`
- Memory helpers: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` (L4 directive doc), `${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh`, `query-learnings.sh`, `emit-learning.sh`, `update-semantic.sh`, `resolve-conflicts.sh` (+ companion `.md` API docs in `skills/_shared/`)
- Agent spawn-degradation ladder: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`
- Evidence standard: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`
- Architecture spec: *(internal)*
