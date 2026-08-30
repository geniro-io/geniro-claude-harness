<!-- Generated from skills/implement/operations-reference.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# /geniro:implement — operations reference

Read at every phase entry, alongside that phase's own body file. `${CLAUDE_PLUGIN_ROOT}/skills/implement/SKILL.md` keeps the role, the state machine, the loop invariants and the anti-rationalization table; this file carries the operational contracts every phase runs under.

These sections live here rather than in SKILL.md's tail because a compaction re-attaches only the first ~20,000 characters of a skill body. Left there they were silently absent from every phase after the first compaction; read here they are present in all three.

## Contents

- ACI per-phase tool surface
- Budgets — quality-first framing
- Subagent model tiering
- State persistence
- Memory I/O
- Modifier handling (semantic, deterministic)

---

## ACI per-phase tool surface

| Phase | Allowed | Blocked |
|---|---|---|
| **Phase 1 (Analyze) — orchestrator** | Read / Grep / Glob / Bash (`git status`, `gh pr view`, `git worktree add`, `git checkout -b`, and the Step 0 freshness commands `git fetch` / `git merge` / `git rebase` / `git stash` / `git pull --ff-only` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`); subagent spawns for `knowledge-retrieval-agent` + `codebase-explorer-agent`, the read-only spec-claim verifiers of the spec-challenge gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md`), and one `general-purpose` web-research spawn (WebSearch + WebFetch) for the library-reuse audit; Workflow (`deep-mode: true` only); AskQuestion. Model per §Subagent model tiering | Edit / Write on source code; `gh pr create`; commit; Phase 3 agent types |
| **Phase 2 (Implement) inner loop** | Read / Grep / Glob / Edit / Write / Bash (`verify:` commands, targeted single-test runs, and the Step 2.5 background dev-server start — full-suite runs go through `test-runner-agent`); browser automation, Step 2.5 pre-change baseline capture only; `test-runner-agent` spawn at end-of-phase; bounded code-delegate spawns (`general-purpose`, disjoint file sets, model per §Subagent model tiering — `sonnet` by default) per the delegation rule in `phase-2-implement.md` §Step 3 and the spawn template in `implement-reference.md` §"Phase 2: Code-delegate spawn template"; AskQuestion | `git push`, `gh pr create`, `gh pr comment`, Phase 3 agent types |
| **Phase 3 (Self-review) — orchestrator** | Read / Grep / Glob / Edit / Write (bounded fix loop; the edge-case test-authoring step, test files only) / Bash (`test-runner-agent` re-spawn per fix round, `query_learnings`); subagent spawns for the reviewer-agent batch and `finding-verifier-agent` (CRITICAL/HIGH cold-verify) — these are the "Phase 3 agent types" the Phase 1 and Phase 2 rows block; Workflow (`deep-mode: true` only); AskQuestion | `git push`, `gh pr create`, commit (those live in the Ship sub-step) |
| **Every spawned subagent** (knowledge-retrieval, codebase-explorer, test-runner, reviewer, finding-verifier, Phase 2 code delegate) | Exactly its own `agents/<name>.md` frontmatter `tools:` whitelist — that allowlist is the contract, not a summary of one; the code delegate has no such file — its ceiling is the spawn template's constraints block instead (`implement-reference.md` §"Phase 2: Code-delegate spawn template") | Agent (all are leaf agents — no nesting); git mutation; destructive Bash; Edit / Write beyond the agent's declared surface; the read-only agents write only their own OUTPUT_PATH |
| **Phase 3 Ship sub-step** | Browser automation + a background dev-server start, for the Pre-Ship Visual Verification pass; `git commit`, `git push`, `gh pr create` — each gated by the push-grade doctrine (§Anti-rationalization, ship-mode row); `gh api` thread reply + `resolveReviewThread` (resolve-handoff only — action-gated, after the push, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md` write side); Edit/Write, scoped to the review-coverage guard's re-review of diverged files only (invariant S5); AskQuestion | External commits before AUQ resolution |

The safety hooks apply across every phase; the complete list and what each blocks is in `${CLAUDE_PLUGIN_ROOT}/HOOKS.md`. Runtime denies stay enforced.

---

## Budgets — quality-first framing

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Budgets — quality-first (canonical). This skill's own gates:

**Quality gates (escalate to user, do not abort):**

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Fix-loop retries per phase | 3 | (Phase 2 test fix), (Phase 3 review round) | AUQ — debug-handoff / accept-failure / abort. User picks. Fires early (before 3) when the loop is not converging — early-escalation triggers in `phase-2-implement.md` §Step 6, reused by the Phase 3 loop. |
| Edge-case authored tests | 10 per run | Phase 3 edge-case test-authoring step (`implement-reference.md` §"Phase 3: Edge-case test authoring") | Stop authoring; surface the tests kept so far |
| Edge-case consecutive discards | 5 consecutive | Phase 3 edge-case test-authoring step (same reference) | Stop hypothesis generation; surface partial |

**Architecture constraint (design intent, not budget):** the Phase 1 knowledge-retrieval + codebase-explorer pair is a fixed spawn set, not size-scaled (skip conditions per the anti-rationalization row above; store-empty gate at `phase-1-analyze.md` Step 7). The Phase 3 Round 1 reviewer grid scales by `change_scope` — the tier-to-dimension mapping is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-grid-scaling.md`; the resolved set is always announced to the user and recorded in `spawn_dims_declared[]` before firing, plus any custom dimensions from `.geniro/instructions/review-extra/` (path-filtered and capped per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Step 6).

---

## Subagent model tiering

Plugin agents declare their tier in frontmatter (`model: inherit`, except `test-runner-agent` and `knowledge-retrieval-agent`, both `model: sonnet`) — OMIT `model=` at every judgment-grade spawn site so it governs. Spawn `subagent_type="geniro:<agent>"` under Claude Code, bare `subagent_type="<agent>"` under any other host; on a spawn that fails to start or returns empty, Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` and apply its registration ladder and empty-result fallback, then cache the resolved rung for the session.

**The three non-judgment spawns — `test-runner-agent`, `knowledge-retrieval-agent`, the Phase 2 code-delegate — take `sonnet` as a ceiling, not a fixed value.** Pass a cheaper tier, with a one-clause reason, where the workload is visibly smaller than the ceiling assumes: a suite re-run after a one-line fix, a delegate slice that is a mechanical rename across its named files. Take the ceiling while the size is still unknown — the run's first test spawn against an unfamiliar suite. One tier per parallel batch, set by its largest member, so delegates spawned together keep a shared cache prefix. Conditions and the haiku caveat: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Sizing a non-judgment spawn.

**`--subagent-model <tier>` pins the judgment spawns for this run and caps the rest.** When `$ARGUMENTS` carries the flag, pass `model="<tier>"` at every judgment-grade spawn — codebase-explorer, every Phase 3 reviewer-agent (built-in and custom, beating a custom reviewer's own declared `model:`), `finding-verifier-agent`, the `codebase-research-agent` side-query spawns of loop invariant S3, the spec-challenge verifiers, the library-reuse-audit web-research spawn — including inside a deep-mode Workflow fan-out. The three non-judgment spawns take it only when it names a tier cheaper than theirs: the flag buys reasoning depth, and none of the three reasons. Values, the per-batch caching rule, and the fallback routes when the value is inexpressible: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §`--subagent-model`. Announce the pinned tier once at run start; phase files apply it without re-stating this rule. Persisted to state.md frontmatter `subagent-model:` at Phase 1 Step 4 (§State persistence above) so a compaction before Phase 2 or Phase 3 does not silently revert every spawn back to inherit.

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
subagent-model: <tier>    # set by --subagent-model (Phase 1 Step 1 parse); missing reads as inherit
spawn_dims_declared: []   # Phase 3 Round 1 declare-before-fire list — resolved reviewer grid + custom:<slug> entries (phase-3-ship.md Step 1)
spawn_dims_count: <int>   # count of spawn_dims_declared[], written alongside it in the same atomic_state_write
reviewed_file_set: []     # CHANGED_FILES the final fix-loop round's reviewer-agents actually received (implement-reference.md §"Phase 3: Bounded fix loop" loop-exit); Ship's review-coverage guard diffs this against what is about to be staged
---
```

When `deep-mode: true`, Phase 1 (spec fact-check) and Phase 3 (self-review) run their deeper paths per `${CLAUDE_PLUGIN_ROOT}/skills/implement/deep-mode-reference.md`. Activation follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §2 — the `--deep` flag pre-resolves it, else the Step 0 depth question asks, else (auto-continue / resume paths, where that question never fires) depth is flag-only. The resolved depth is persisted once, in Phase 1.

`subagent-model` has no chooser question — it is flag-only, parsed at Phase 1 Step 1 and persisted at Step 4 alongside `deep-mode` so a compaction before Phase 2 or Phase 3 fires does not silently revert every spawn back to inherit.

**Write contract.** Route every state.md mutation through `atomic_state_write` — a direct `Edit` or `Write` on a canonical state path bypasses the helper and corrupts the file mid-crash; the State-helper enforcement hook hard-blocks such a direct write (exit 2). Invocation snippet: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`.

---

## Memory I/O

Which helper fires where. Step 0 workspace setup precedes every Phase 1 call in this table — its decision picks the worktree the rest of Phase 1 inspects, so a snapshot or drift check run first inspects the wrong tree.

| Phase | Calls |
|---|---|
| **Phase 1 entry** | `load-custom-instructions` (`MODE: refresh`) → `load-semantic` → the `knowledge-retrieval-agent` + `codebase-explorer-agent` spawn pair (knowledge slot gated by the Step 7 store-empty check), read back from `<task-dir>/.kr-out.md` and `<task-dir>/.ce-out.md` → `query-learnings` |
| **Phase 2** | Entry: `load-custom-instructions` (`MODE: refresh`) — every entry, including a resume, since Phase 1's load does not carry forward. Its other loads are the per-Edit `.claude/rules/*.md` JIT reads (cache scope: Phase 2) |
| **Phase 3** | Entry: `load-custom-instructions` (`MODE: refresh`) + `load-custom-reviewers` (round 1 only). Fix loop: `query-learnings` per round. Ship sub-step: `emit-learning`, `update-semantic`, and the `non-resumable-actions[]` write via `atomic_state_write` |
| **Any phase** | `resolve-conflicts` when the layers disagree — a soft conflict prints the notice and continues on the precedence-winning value; a hard conflict (a custom-instruction rule contradicts project reality) halts and asks. `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` |

Each helper's arguments, echo contract, and failure semantics live with the step that calls it. Two rules span all of them — "Custom-instruction load is mandatory in full at every phase entry" and "A declared memory backend redirects every learnings read", both in §Loop invariants above.

---

## Modifier handling (semantic, deterministic)

Inline modifiers from Phase 1 `$ARGUMENTS` override AUQ defaults deterministically. Two tables own the rows AND their semantics at the point of use — consult them there, never a restated copy:

- **Workspace and run-behavior modifiers** — `${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-1-analyze.md` §Step 0b "Inline modifier overrides" (also owns the conflicting-modifiers rule and its soft notice).
- **Ship-mode modifiers** — `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Inline modifiers from $ARGUMENTS".
