---
name: geniro:implement
description: "Use when shipping а new feature, endpoint, page, or significant change against а spec.md / plan.md (from /geniro:plan) OR а raw inline task description. M4 2-phase autonomous loop: Analyze → Implement → Self-review-and-Ship."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite, WebSearch, EnterWorktree]
argument-hint: "[task description | spec.md path | empty к resume | 'continue']"
---

# Implement Skill — M4 2-Phase Autonomous Loop

**You are an autonomous executor.** You consume an externally-provided spec (or inline task description), make all required code edits, run the test suite, then run а 5-dim self-review pass before shipping. Pre-M4 architect / skeptic / approval / simplify phases are removed — strategic concerns belong upstream в `/geniro:plan` (M5). Pre-M4 Lane modes (TDD / Light / Auto) и per-WU parallel decomposition are removed — М4 runs а single solo execution path per task.

**Phases (M4 §2):**

1. **Analyze (Phase 1)** — semantic-parse `$ARGUMENTS`, resolve spec source (spec.md / plan.md / DESIGN_DOC frontmatter OR inline-task fallback), refresh L4+L3 memory, persist T2 handoffs к state.md.
2. **Implement (Phase 2)** — single whole-feature edit batch; one end-of-phase test-suite run; bounded 3-retry fix loop on test failure → escalate-AUQ on exhaust.
3. **Self-review + Ship (Phase 3)** — 5 reviewer-agents в parallel (bugs / security / architecture / tests / code-quality); bounded 3-round fix loop, round N+1 = failing dims only; on clean exit, ship sub-step (Pre-Ship Visual Verification if applicable, commit, ship-mode AUQ, L2/L3 writes, cleanup).

**Reference material** (templates, $ARGUMENTS-parse table, reviewer-agent spawn template, fix-loop, ship sub-step): Read `${CLAUDE_SKILL_DIR}/implement-reference.md` AT each phase. Do NOT pre-load the entire file.

---

## State machine (M4 §2.1)

State.md frontmatter `phase:` enum:

```
[entry]
  └── analyze ──┬── implement ──┬── self-review ──┬── ship ──┬── done (terminal)
                │               │                  │           ├── ship-committed-only (terminal — "don't push" / "no push" / "commit only" modifier)
                │               │                  │           └── (non-resumable-actions[] update per side-effect)
                │               │                  │
                │               │                  └── self-review-only (terminal — "stop after review" modifier)
                │               │
                │               └── phase-2-escalated ──┬── debug-handoff (terminal)
                │                                       ├── self-review (user picked "accept failures")
                │                                       └── aborted (terminal)
                │
                └── (analyze surface failures inline; no дополнительная escalation state)

      self-review ──┬── (happy: → ship)
                    │
                    └── phase-3-escalated ──┬── debug-handoff (terminal)
                                            ├── ship (user picked "accept findings" → `## Accepted Findings` body block)
                                            └── aborted (terminal)
```

**Terminal states** (M3 SessionStart treats as "task complete — no resume needed"): `done`, `ship-committed-only`, `self-review-only`, `debug-handoff`, `aborted`.

**Non-terminal states** (M3 rolls back к phase-entry point on resume): `analyze`, `implement`, `self-review`, `ship`.

**Termination reason convention (M4 §2.1.1).** When `phase: aborted` is reached, write one line to state.md body under `## Termination reason`: `repeated-failure: phase-N retry-limit` / `safety-denied: <rule>` / `tool-unavailable: <tool>`. M3 SessionStart re-injects this on resume.

---

## Loop invariants (M4 §2.2)

Apply throughout all 3 phases:

1. **One result per tool call.** Every Edit / Write / Bash / Agent spawn produces exactly one structured result. Failed spawn → result с `status: failed`; never absent.
2. **Args validated before execution.** Bash commands constructed from $ARGUMENTS or state.md fields pass input sanity-checks. Paths absolute; slugs match M1 §Slug rules.
3. **Permission before side-effect.** Any tool call mutating external state (`git push`, `gh pr create`, posted PR comment) is preceded by AUQ approval or recorded approval (persisted via P-M1-1 schema).
4. **Bounded и structured tool results.** Reviewer-agent output capped at ~4000 chars per dimension; longer truncated с marker. Bash output >8000 chars summarized before downstream use.
5. **Escalation gates, not silent abort.** Bounded retry loops (3 rounds в §6.2, 3 rounds в §7.3) surface к user via `AskUserQuestion` at exhaustion — never silent abort, never infinite loop.
6. **Final answer grounded в observations.** Phase 3 Ship result text MUST quote actual tool output (push ref, PR URL, commit SHA) — never "git push succeeded" без evidence. Self-review reads `## Tool log` entries before claiming clean state.
7. **Errors, denials, cancellations, timeouts → structured observations.** Failed `gh pr create`, denied permission, hook-blocked Write, subagent timeout, non-zero Bash exit becomes а structured observation entry — never silently skipped.

**Side-effect — `## Tool log` section в state.md.** Invariants 1 и 7 motivate persisting subagent-spawn outcomes и side-effect tool calls (`git push`, `gh pr create`, file deletions) into а body section per the schema in `${CLAUDE_SKILL_DIR}/implement-reference.md`. Routine Read/Edit/Bash on local files do NOT need logging — Claude Code's tool_result return is sufficient.

---

## Budgets — quality-first framing (M4 §2.3, P-M4-3 revised)

**NO hard kill caps.** No wall-time / tool-call / model-turn / cost ceilings. User tokens unlimited.

**Quality gates (Class-B — escalate к user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Fix-loop retries per phase | 3 | §6.2 (Phase 2 test fix), §7.3 (Phase 3 review round) | AUQ — debug-handoff / accept-failure / abort. User picks. |
| Reviewer output size | ~4K chars per dim | §2.2 invariant #4 | Truncation с marker, NOT abort. |

**Architecture constraints (design intent, not budget):**
- Parallel reviewer spawns per round: 5 dimensions (`bugs` / `security` / `architecture` / `tests` / `code-quality`).

**Explicitly NOT capped:**
- Wall-time per run. Complex implementation can take hours.
- Total tool calls per phase. Large refactors easily exceed 100 calls; no cap.
- Total model turns per phase. Multi-file work needs many turns.
- Total cost per run. Deferred к P-X6 if а cost-aware mode is opted into.

---

## State persistence (M1 + M4)

**Task directory** (M1 T1):

```
.geniro/planning/<task-slug>/
```

Where `<task-slug>` is derived from $ARGUMENTS / spec.md filename / git branch per M1 §Slug rules. Created at start of Phase 1.

**State.md frontmatter (M1 §T1 + M4 §5):**

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
non-resumable-actions: []   # appended after each git push / gh pr create / posted comment
approvals: []               # appended after each one-time AUQ resolution (P-M1-1)
---
```

**Write contract.** Every state.md mutation goes through `atomic_state_write` (cited from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.sh`). NEVER direct `Edit` или `Write` on canonical state paths — the State-helper enforcement hook will warn (and в M1 PR-final, hard-block).

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.sh"
atomic_state_write ".geniro/planning/<task-slug>/state.md" <<'EOF'
---
<frontmatter>
---

<body sections>
EOF
```

**Validation before resume.** When Phase 1 detects а pre-existing state.md (resume path), pre-flight via `validate_state_file`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.sh"
if ! validate_state_file ".geniro/planning/<task-slug>/state.md"; then
  # Open recovery AskUserQuestion (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency)
  ...
fi
```

---

## Memory I/O (M4 §13)

### L4 — Custom instructions (procedural)

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` с `SKILL_SLUG: implement`, `LOAD_TIER: pipeline`, `MODE: initial-load` (Phase 1) или `MODE: refresh` (Phase 3 entry). The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `<slug>.md`, и `code-style.md`; its §Echo contract requires one observable line per file. Both are mandatory.

**Phase boundaries (M3 §7.3 + M4 §13.4):**
- Phase 1 entry — `MODE: initial-load` — scope = `implement` + `global` + `code-style`.
- Phase 3 entry — `MODE: refresh` ALWAYS — survives Phase 2 compaction без requiring an M3 marker contract. Cost: 1 extra helper read.

The Echo contract survives compaction via M3 SessionStart re-injection.

### L3 — Semantic snapshot

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.sh"
load_semantic                                # default: _project.md + _CODEBASE_MAP.md
load_semantic --extras "_FEATURES.md"        # if spec mentions feature backlog
```

**Phase 1 entry only.** Drift notification surfaces к user if `.fingerprint.json` mismatched. Phase 3 does NOT re-load L3 (Phase 2 doesn't materially mutate L3 — `update-semantic` writes are bounded к single-line append on `_CODEBASE_MAP.md`).

### L2 — Episodic event log

**Read (Phase 1 entry):**

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.sh"
query_learnings --tag <inferred-tag> --scope <inferred-scope> --limit 5
```

Tags inferred from task description (e.g., `react`, `auth`, `bug`); skipped if task description is too generic.

**Read (Phase 3 fix-loop):**

```bash
query_learnings --tag <inferred-tag> --scope <changed-file-path> --limit 5
```

Used к prime reviewer-agent prompts с known conventions/pitfalls.

**Write (Phase 3 ship sub-step, auto-emit):**

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.sh"
echo '{"type":"convention","scope":"...","summary":"...","tags":[...],"trust":"verified"}' | emit_learning
```

Triggers per M4 §13.2 (M2 §5.3 patched contract):
- `type=convention` → when Phase 3 architecture или code-quality reviewer reports ≥3 instances of same pattern.
- `type=decision` → when spec.md records а non-trivial approach choice с `## Considered Alternatives` (M4-only path; once /plan M5 ships, /plan emits decisions directly).

Default trust = `verified` (Phase 3 findings are test-validated на entry).

Promotion suggestion (P-M4-5) fires ONLY for `convention` emits — see reference.md §"Extract Learnings".

### L3 — Bounded write (Phase 3 ship sub-step)

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/update-semantic.sh"
update_semantic --file codebase-map --append "- <path> — <short description>, used by <consumer>"
```

Fires when Phase 2 added а new module. Lock-guarded; rc=11 (lock held) is а recoverable skip-and-defer.

### Cross-layer conflict surfacing (M2 §10)

When L4/L3/L2 reads disagree, follow the protocol in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md`:
- **Soft conflict:** print `emit_conflict_notice` text, continue using precedence-winning value.
- **Hard conflict (L4 rule contradicts L3 reality):** halt, call `hard_conflict_block` + `AskUserQuestion` к surface к user.

---

## ACI per-phase tool surface (M4 §13.5)

| Phase | Allowed | Blocked |
|---|---|---|
| **Phase 1 (Analyze)** | Read / Grep / Glob / Bash (read-only: `git status`, `gh pr view`) | All mutations |
| **Phase 2 (Implement) inner loop** | Read / Grep / Glob / Edit / Write / Bash (incl. test runs) | `git push`, `gh pr create`, `gh pr comment`, Agent spawns (Phase 3 territory only) |
| **Phase 3 reviewer-agent spawns** | Per dim: Read / Grep / Glob / Bash (read-only) — enforced by `agents/reviewer-agent.md` frontmatter `tools:` whitelist | Edit / Write / Agent / mutating Bash / external network |
| **Phase 3 Ship sub-step** | `git commit`, `git push` (draft-grade — auto per P-M4-4), `gh pr create` (commit-grade — AUQ-gated) | External commits before AUQ resolution |

**Existing safety layer:** file-protection hook, git-guardrail hook, и `.geniro/` deletion guard apply across ALL phases regardless of this matrix.

---

## PHASE 1: ANALYZE

**Load L4 instructions (first action).** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` с `SKILL_SLUG: implement`, `LOAD_TIER: pipeline`, `MODE: initial-load`. The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `implement.md`, и `code-style.md`; the §Echo contract requires one observable line per file. Both are mandatory.

**Refresh L3 semantic snapshot.** `load_semantic` с default top-2 (`_project.md` + `_CODEBASE_MAP.md`). Optional `--extras _FEATURES.md` if spec mentions feature backlog. Fingerprint drift check fires automatically; surface drift notification к user.

### Steps

1. **Semantic-parse `$ARGUMENTS`.** Apply the M4 §5.1 table в `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 1: $ARGUMENTS semantic-parse table".
2. **Resolve spec source.** Walk the spec discovery list (`${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 1: Spec discovery walk-list"). If no spec.md / plan.md / DESIGN_DOC frontmatter found AND $ARGUMENTS is non-empty → inline-task mode (write `## Inline Plan` к state.md body).
3. **Disambiguate if needed.** If $ARGUMENTS is ambiguous, fire AUQ per Phase 1 table. Persist outcome к state.md frontmatter `approvals[]` с `category: disambiguate_arguments` (P-M1-1 protocol — check `approvals[]` first to skip already-decided).
4. **Resolve task slug per M1.** Used для state.md path. If task-dir exists, validate state.md (recovery AUQ on validation fail). If task-dir is fresh, `mkdir -p`.
5. **Query L2 learnings.** `query_learnings --tag <inferred> --scope <task-path> --limit 5`. Skip if task description is too generic к infer tags.
6. **Resolve cross-layer conflicts.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` protocol if L4/L3/L2 disagree.
7. **Detect frontend files в scope.** Gates Phase 3 reviewer-agent design-conventions injection и Phase 3 Pre-Ship Visual Verification.
8. **Persist T2 handoffs.** If `.geniro/state/handoff/from-<producer>-<branch>.md` exists, read и persist под state.md `## Inputs from <producer>` body section. M3 §9 obligation.
9. **State.md write.** `atomic_state_write` с frontmatter `phase: analyze` → upon completion `phase: implement`.

**Workflow plumbing.** Workflow integrations (`.geniro/workflow/*.md`) apply their argument-detection patterns BEFORE the semantic-parse table. Non-blocking — log warning if integration backend unavailable.

**Git-workspace setup.** Setup happens via workflow integration OR inline modifier OR existing checkout. Если user provided а bare task description с no workspace hint, fire а single workspace AUQ (header: `"Git workspace"`):
- A) New feature branch (recommended for most features)
- B) Current branch
- C) Git worktree (`.claude/worktrees/<dir>` — isolated; allows parallel work or instant rollback)

Persist choice к state.md `## Workspace`. Pre-M4 multi-question Phase 1 Startup Consolidation is removed (no Lane / Mode / Feature questions remain).

---

## PHASE 2: IMPLEMENT

**State.md `phase: implement`** during this phase.

**No L4 / L3 refresh at Phase 2 entry** — code-style instructions from Phase 1 remain в context.

### Steps

1. **Read spec source** (Phase 1 resolved either а spec.md path OR wrote `## Inline Plan` к state.md body).
2. **Whole-feature edit batch** (M4 §6.1). Make all required Edit/Write changes к the codebase в а single phase pass. NOT file-by-file. NOT sub-task decomposition.
3. **Run project test suite ONCE at end-of-phase.** Use commands from CLAUDE.md's Essential Commands section. Attach an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` (command, exit code, last 3 lines).
4. **In-phase mini fix loop on test failure (M4 §6.2).** Up к 3 retries:
   ```
   retry = 1
   while retry ≤ 3:
       inspect failing test output
       edit code (or test) к address the failure
       re-run test suite
       if all green → exit Phase 2 к Phase 3
       retry += 1
   else:
       escalate (§6.3 below)
   ```
5. **Escalation on retry exhaust (M4 §6.3).** Fire AUQ (header: `"Test failure"`):
   - A) Hand off к /geniro:debug — state.md `phase: debug-handoff` (terminal)
   - B) Accept failing tests as documented limitation — state.md `phase: self-review`, append `## Accepted Failures` block
   - C) Abort — state.md `phase: aborted` (terminal)

   Empty answer = upstream bug, fall back к plain text and re-ask. NEVER auto-default.

**State.md update on phase exit.** `phase: self-review` (happy path) или `phase: phase-2-escalated` (если §6.3 fires). On `aborted`, write `## Termination reason: repeated-failure: phase-2 retry-limit (<N> failing tests)`.

---

## PHASE 3: SELF-REVIEW + SHIP

**State.md `phase: self-review`** on entry.

**Refresh L4 instructions** (always, regardless of compaction-marker presence). Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` с `MODE: refresh`, scope = same as Phase 1.

**Idempotent green-light verification on entry.** Re-run test suite once. Should be green from Phase 2. If not, rollback к Phase 2 §6.2 retry loop (treats as а retry round).

### Steps

1. **Round 1 spawn — all 5 dims в parallel.** Apply `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 3: Self-review reviewer-agent template". One `Agent(subagent_type="reviewer-agent", ...)` call per dimension, all five в the SAME assistant response.

   Dimensions: `bugs` / `security` / `architecture` / `tests` / `code-quality`. Architecture dim covers docs-staleness + spec-compliance (OQ-9 + master plan §139). See reference.md §"The 5 dimensions" table for full criteria-file mapping.

2. **Collect findings.** Reviewer-agent output schema per `agents/reviewer-agent.md` §Output Format. Cap per-dim output at ~4K chars (invariant #4); truncate с marker on overflow.

3. **Bounded fix loop (M4 §7.3).** Up к 3 rounds:
   ```
   round = 1
   while round ≤ 3:
       collect findings from this round's spawns
       if no findings across all dimensions:
           break  # exit к Ship sub-step
       apply fixes inline (single Edit-driven sub-loop, NO further agent spawns)
       re-run project test suite (must stay green; if not, rollback к Phase 2 §6.2)
       round += 1
       spawn reviewer-agents on failing dimensions only (round N+1 ≠ all 5)
   else:
       # round 4 would start — DO NOT enter
       escalate via AskUserQuestion (§7.4 in reference.md)
   ```

4. **Escalation on round-3 exhaust (M4 §7.4).** AUQ (header: `"Resolve findings"`):
   - A) Hand off к /geniro:debug — state.md `phase: debug-handoff` (terminal)
   - B) Accept findings, ship anyway — state.md `phase: ship`, append `## Accepted Findings` block
   - C) Abort — state.md `phase: aborted` (terminal)

   Empty answer = upstream bug, fall back к plain text and re-ask. NEVER auto-default.

### Ship sub-step (M4 §7.5)

State.md `phase: ship` on entry.

1. **Pre-Ship Visual Verification** — fires only когда frontend files в scope AND Playwright MCP available. Apply `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Pre-Ship Visual Verification".
2. **Commit.** Stage relevant files, `git commit` с conventional message (e.g., `feat(auth): add OAuth login [ENG-123]`). Task ID inferred from spec.md / state.md metadata.
3. **Ship-mode AUQ (M4 §7.5 step 3, P-M4-4).** Push is draft-grade (auto); AUQ gates only commit-grade PR creation. See `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Commit + Push + PR" for the canonical AUQ shape and approvals-persistence protocol (P-M1-1 — check state.md `approvals[]` с `category: ship_mode` before firing). Inline modifiers from $ARGUMENTS (`"don't push"`, `"draft only"`, `"with PR"`, `"stop after review"`) override the AUQ deterministically.
4. **Atomic `non-resumable-actions[]` update (M3 §8).** After each side-effect that cannot be replayed safely (`git push`, `gh pr create`, posted PR comment), append а structured entry к state.md frontmatter `non-resumable-actions[]` array via `atomic_state_write`. Entry schema per M3 §8: `{action, completed-at, <action-specific-fields>}`. Write AFTER the side-effect succeeds — atomic, so partial-write corruption is impossible mid-crash.
5. **L2 auto-emit (M4 §13.2 + P-M4-5).** Emit `convention` к learnings.jsonl when ≥3-instance pattern detected; emit `decision` if spec.md recorded а non-trivial approach choice. Default trust = `verified`. Surface promotion suggestion only for `convention` type. Apply `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Extract Learnings".
6. **L3 update (M4 §13.3).** If Phase 2 added а new module, `update_semantic --file codebase-map --append "..."`. Lock-guarded; rc=11 = recoverable skip.
7. **Update Docs / Suggest Improvements / Integration Updates / Cleanup.** Apply reference.md sub-sections в order. Cleanup deletes `<task-dir>` per M1 T1 contract (ephemeral, deleted at Phase Ship).
8. **State.md final transition.** Frontmatter `phase: done` (or `ship-committed-only` / `self-review-only` depending on modifier / user pick). M3 SessionStart treats terminal states as "no resume needed".

### Adjustment routing (post-ship feedback)

When ship-feedback arrives via PR comments или as а follow-up `$ARGUMENTS` invocation, route per the Big/Medium/Small classification в `${CLAUDE_SKILL_DIR}/implement-reference.md` §"Phase 3 — Adjustment Routing". Pre-M4 the legacy `/follow-up` handled this; M4 absorbs it (master plan §27 — /implement "handles any size via spec input").

---

## Modifier handling (semantic, deterministic)

Inline modifiers from Phase 1 `$ARGUMENTS` parse override the ship-mode AUQ деterministically (M4 §7.5 step 3):

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
   - **No state.md** → fresh run. Proceed к Phase 1.
   - **state.md exists, phase in non-terminal set** → resume from `phase:` value. M3 SessionStart hook re-injects context.
   - **state.md exists, phase в terminal set** → task complete. Surface terminal state к user; if `$ARGUMENTS` carries new task description, derive new slug, fresh run.

1. **Validate state.md if found** (`validate_state_file`). On fail, open recovery AUQ (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency).

2. **TodoWrite checklist.** Add: Phase 1 Analyze / Phase 2 Implement / Phase 3 Self-review-and-Ship. Mark Phase 1 in_progress; update each as it completes.

3. **Begin Phase 1.**

---

## Anti-rationalization

Per master plan P-MP-1 anti-patterns guardrail — М4 must NOT reintroduce these:

| Your reasoning | Why it's wrong |
|---|---|
| "/implement should ask user before each Edit — safety first." | Phase 2 Implement is the **execution** phase. Pre-approval lives upstream — /plan (M5) Phase 8 emits the spec.md; that spec.md IS the pre-approval. Per-Edit AUQs defeat the spec-driven autonomy M4 is designed for. |
| "Add а wall-time kill cap so long-running tasks abort cleanly." | Class-A hard caps abort legitimate complex work mid-stride. M4 §2.3 quality-first framing — no Class-A caps. Past three failed Phase-2 retries (§6.2) escalates к user via AUQ. |
| "Phase 2 should fan out backend/frontend agents для parallel edits." | M4 §3.1 — work-unit decomposition removed. Scheduler complexity overwhelmed the value. Single solo inner loop, one test run at end. |
| "Re-run tests after each file Edit к catch regressions early." | M4 §6.1 — single end-of-Phase-2 test run. Per-file test runs explode wall-time on slow suites. |
| "/implement should self-fix indefinitely until reviews clean." | M4 §7.3 — bounded к 3 rounds. Past 3, escalate AUQ. «Kick it until it passes» is а catalogued anti-pattern. |
| "Skip the ship-mode AUQ — user can `git reset` if they wanted а draft PR." | M4 §7.5 step 3 — push is draft-grade (auto), но PR creation is commit-grade (AUQ-gated). Inline modifiers provide deterministic overrides. |
| "Auto-promote L2 conventions к L4 rules when ≥3-pattern detected." | M4 §7.5 step 5 + P-M4-5 — surface а suggestion line; do NOT auto-promote. User remains source-of-truth для L4 rule curation. |
| "Defer M3 compaction-survival к downstream skills — M4 is too complex к wire it up." | M3 contract IS M4's contract — state.md frontmatter (M1 §T1), `non-resumable-actions[]` (M3 §8), `## Tool log` (§2.2). Без these, compaction mid-Phase-2 loses the entire run. Non-negotiable. |
| "Run reviewers серийно — easier к debug than parallel-spawn batch." | M4 §7.2 — parallel spawn в ONE assistant response. Serial spawn doubles wall-time. Wrong trade-off. |
| "Audit trail isn't needed для local /implement runs." | The state.md `## Tool log` IS the audit trail. M3 SessionStart re-injects on compaction. Без log, post-mortem on failed runs is impossible. |
| "Bypass safety hooks с --no-verify when commit-hook fails — saves time." | Hooks fail для а reason. Investigate root cause, не bypass. --no-verify usage is а CLAUDE.md-level prohibition. |
| "Spawn agents one at а time для cleaner orchestration." | All 5 reviewer spawns в ONE assistant response — multiple `Agent(...)` tool uses в the same message. Separate turns = no concurrency, full wall-clock latency per agent. |
| "Fall back к sonnet → opus escalation on reviewer failure." | M4 doesn't ship runtime-escalation. Reviewer at `sonnet` (declared в agents/reviewer-agent.md frontmatter) handles all dimensions. Sonnet-Opus escalation belongs к а future review-tier-escalation feature, not the baseline self-review loop. |

---

## REFERENCE

- Templates, $ARGUMENTS-parse table, reviewer-agent spawn template, fix-loop, ship sub-step: `${CLAUDE_SKILL_DIR}/implement-reference.md`
- Reviewer-agent contract: `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md`
- Review criteria files: `${CLAUDE_PLUGIN_ROOT}/skills/review/` (bugs, security, architecture, tests, optimizations, guidelines, conventions, +design when UI files changed)
- State helpers: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.sh`, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.sh`
- Memory helpers: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` (L4 directive doc), `load-semantic.sh`, `query-learnings.sh`, `emit-learning.sh`, `update-semantic.sh`, `resolve-conflicts.sh` (+ companion `.md` API docs)
- Agent spawn-degradation ladder: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`
- Evidence standard: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`
- Architecture spec: `architecture/M4-implement-redesign.md`
