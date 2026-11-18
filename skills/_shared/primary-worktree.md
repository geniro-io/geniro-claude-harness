# Primary-worktree resolution for persistent state

Canonical resolver for cross-session persistent state. Ensures writes/reads land in the main repo's working tree even when the session is in a linked worktree (the gitignored `.geniro/*` would otherwise be lost on `git worktree remove`).

## Contents

- Why this exists — writes lost on worktree removal; authored content invisible to fresh worktrees
- The resolver — Mode A (orchestrator Bash) and Mode B (Bash-less subagents)
- Artifacts that must use the resolver (cross-session)
- Artifacts NOT in scope (within-skill state — keep cwd-relative)
- Anti-rationalization
- Definition of Done

## Why this exists

The default plugin `.gitignore` keeps `.geniro/*` out of git (only `workflow/`, `instructions/`, and `actions/` are negated). Two consequences:

- **(a) Writes lost on worktree removal.** When `/geniro:implement`'s workspace-setup question (Step 0) picks the Git-worktree option, entering the worktree switches the session into `.claude/worktrees/<dir>/` — every cwd-relative `.geniro/<x>` write lands in the worktree's gitignored tree and is destroyed when the user removes the worktree at session end.
- **(b) Authored content invisible to fresh linked worktrees.** Even when the worktree is fresh and persistent, the primary worktree's authored content (`.geniro/instructions/<scope>.md`, `.geniro/workflow/<kind>.md`, `.geniro/actions/<slug>.md`) is NOT propagated by `git worktree add` because those paths are gitignored at the project level (negation is a default; project-side `.git/info/exclude` may override). The main repo's `.geniro/<x>` never receives the write, and the linked worktree never sees the read.

This affects every artifact designed to outlive the current task, planning task-dirs and their handoffs included.

## The resolver

### Mode A — Orchestrator-level Bash

Skills running orchestrator-level Bash compute a single prefix before any persistent read or write:

```bash
TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null)"
# Bare entries are skipped (mirrors lib/repo-root.sh) — writes must never land inside the bare hub dir.
PRIMARY="$(git worktree list --porcelain 2>/dev/null | awk '
  /^worktree / { path = $0; sub(/^worktree /, "", path) }
  /^bare$/     { path = "" }
  /^$/         { if (path != "") { done = 1; print path; exit } }
  END          { if (!done && path != "") print path }
')"
if [ -z "$TOPLEVEL" ] || [ -z "$PRIMARY" ] || [ "$TOPLEVEL" = "$PRIMARY" ]; then
 PRIMARY_ROOT="." # main worktree (or non-git project); cwd-relative is fine
else
 PRIMARY_ROOT="$PRIMARY" # linked worktree; route writes to main
fi
```

Then for every cross-session artifact:
- Reads: `Read "$PRIMARY_ROOT/.geniro/knowledge/learnings.jsonl"` (etc.)
- Writes: `mkdir -p "$PRIMARY_ROOT/.geniro/knowledge"` then write at the same prefix.

If `git` is missing or the project isn't a git repo, both probes return empty → fall back to cwd-relative. Non-git projects have no linked-worktree problem.

**Re-run the snippet inside every Bash call that uses the variable** — shell state does not persist across Bash calls, so a value resolved in an earlier call is gone, and an unset `$PRIMARY_ROOT` expands a `"$PRIMARY_ROOT"/.geniro/...` path to a root-anchored `/.geniro/...` path.

Where a call already sources `lib/` (any `atomic_state_write` site does), `source "${CLAUDE_PLUGIN_ROOT}/lib/repo-root.sh"; PRIMARY_ROOT="$(_geniro_repo_root)"` is the same resolution in one line — the function this snippet mirrors, so per-call re-resolution costs a line instead of twelve. It always prints an absolute path, never `.`, so reach for it where the prefix is only pasted into paths and keep the snippet where a caller branches on `PRIMARY_ROOT = "."` (the cwd-first loaders do).

### Mode B — Subagents without Bash

Some agents have read-only tool surfaces (e.g. `tools: [Read, Glob, Grep]`) and cannot run the resolver themselves. The spawning orchestrator must compute `PRIMARY_ROOT` in Mode A and inline absolute paths into the agent's spawn prompt as named slots, mirroring how `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` propagates `WORKTREE` and `BRANCH`. Use narrow per-domain slots (each is an absolute path resolved by the orchestrator) — there is no umbrella slot:

```
KNOWLEDGE_ROOT: <PRIMARY_ROOT>/.geniro/knowledge
HANDOFF_PATHS: <absolute existing handoff files for the branch>
TASK_PLANNING_ROOT: <absolute task-dir, under _geniro_planning_root>
PLANNING_ROOT: <PRIMARY_ROOT>/.geniro/planning
```

The agent reads/globs against the inlined absolute path. It never substitutes its own cwd. If a Bash-less agent is given a cwd-relative `.geniro/...` path, it is a spawn-prompt bug — fix the orchestrator, not the agent.

## Artifacts that must use the resolver (cross-session)

These are intended to outlive any single task. The resolver applies to both reads and writes.

| Artifact | Producer(s) | Consumer(s) | Notes |
|---|---|---|---|
| `.geniro/knowledge/learnings.jsonl` | `/geniro:implement`, `/geniro:plan`, `/geniro:debug`, `/geniro:review`, `/geniro:refactor`, `/geniro:onboard`, `/geniro:investigate` | every pipeline skill's Phase-1 `query-learnings` prior-knowledge lookup | structured corpus |
| `<PLANNING_ROOT>/<unit>/` — `spec.md`, `state.md`, `review.md`, `debug.md`, `debug-adversarial.md`, `review-brief-<date>.md`, `investigate-<topic-slug>.md` | `/geniro:plan`, `/geniro:implement`, `/geniro:review`, `/geniro:debug`, `/geniro:investigate` | `/geniro:implement` Phase 1 handoff-resolution step (gates on unresolved open questions) and every skill that reads the task-dir | `<PLANNING_ROOT>` is the current worktree's `.geniro/planning` when git does not ignore it, else `<PRIMARY_ROOT>/.geniro/planning` (`${CLAUDE_PLUGIN_ROOT}/lib/unit-dir.sh` `_geniro_planning_root`); `review.md` carries `[POSTED-TO-PR]` idempotency markers — losing the file = double-posting on re-run |
| `.geniro/planning/_FEATURES.md` | manual (no skill writes it) | `/geniro:implement` (when the spec mentions the feature backlog) | persistent registry |
| `.geniro/planning/_CODEBASE_MAP.md` | `/geniro:onboard` | every skill that consults the map (`/geniro:implement`, `/geniro:plan`, `/geniro:debug`, `/geniro:review`, `/geniro:refactor`, `/geniro:investigate`) | persistent orientation artifact; bounded auto-incremental writes via `update-semantic` |
| `.geniro/planning/_focus-<area>.md` | manual | every skill that consults focused-area context | persistent orientation artifact for a subsystem |
| `.geniro/workflow/<kind>.md` | manual / `/geniro:setup` | `/geniro:plan`, `/geniro:implement`, `/geniro:review`, `/geniro:refactor` | Tracker integration configs (Linear/Jira/GitHub-Issues/Asana); read with cwd-first / primary-fallback per per-site preambles; written by `/geniro:setup` to `<PRIMARY_ROOT>` |
| `.geniro/actions/<slug>.md` | manual / `/geniro:actions create` | `/geniro:actions` (list/run/validate/delete) | User-authored workflow-helper actions; glob BOTH the local and `<PRIMARY_ROOT>` copies and, when the same slug appears in both, the local one wins (uncommitted local edits are the newer intent); `/geniro:actions` create/edit/delete operate on the `<PRIMARY_ROOT>` copy (run keeps local-wins) |
| `.geniro/instructions/<scope>.md` | manual / `/geniro:setup` / `/geniro:instructions create` | every pipeline skill's Phase 1 `load-custom-instructions` invocation | L4 procedural memory (global / code-style / per-skill / review-extra/<slug>); checkout-root-first / primary-fallback per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Procedure; `/geniro:instructions` CRUD and `/geniro:setup` scaffolds write to `<PRIMARY_ROOT>` (loaders keep checkout-root-first / primary-fallback). An external override (`GENIRO_INSTRUCTIONS_DIR` or the plugin's `instructions_dir` option), when configured, takes precedence over the checkout-root-first/primary-fallback resolution — see the same loader doc |

## Artifacts NOT in scope (within-skill state — keep cwd-relative)

These are intentionally ephemeral with the current task.

- `.geniro/state/refactor/<slug>/state.md`, `.geniro/state/debug/<slug>/state.md`, `.geniro/state/onboard/<slug>/state.md`, `.geniro/state/investigate/<slug>/state.md`, `.geniro/state/audit-instructions/<slug>/state.md`, `.geniro/state/resolve/<slug>/state.md` — within-skill resume-from-compaction state, branch-scoped per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md`. Each is deleted at its skill's cleanup phase.

If a within-skill state file is later promoted to cross-session use, add it to the cross-session table above.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This skill never runs in a worktree" | `/geniro:implement`'s "Git worktree" workspace pick puts the session in a worktree, and orchestrators downstream of it inherit that cwd. Any cross-session write made there is exposed. |
| "I'll commit the file in the worktree to preserve it" | `git add` is a no-op on the ignored `.geniro/*`, and a commit made there lands on the feature branch, not main; only a `.geniro/planning` git does not ignore is committable, and `<PLANNING_ROOT>` then resolves to the worktree. |
| "I'll make `.geniro/knowledge/` not gitignored" | Different fix, different problem. Knowledge bleeds across feature branches → merge conflicts. The resolver writes to main's tree without involving any branch. |
| "The subagent has no Bash, so it'll just resolve the path itself" | It can't. Mode B requires the orchestrator pre-resolve and inline. Cwd-relative paths in a Bash-less agent's prompt are a spawn-prompt bug. |
| "I'll apply the resolver to within-skill state files for safety" | Don't. Those are intentionally task-scoped. Use `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` instead — it solves their parallel-session collision via branch slug + Branch/Worktree/Timestamp headers + Case-C mismatch AUQ, while keeping the cleanup contract intact. |
| "`git rev-parse` might fail — better to error out" | Falling back to cwd-relative is correct: non-git projects have no linked-worktree problem, so cwd-relative is durable there. |

## Definition of Done

- [ ] Every cross-session producer in the table above resolves the prefix via Mode A before writing
- [ ] Every cross-session consumer reads through the same prefix
- [ ] Subagents that read cross-session state receive narrow `*_ROOT` slots (`KNOWLEDGE_ROOT`, `HANDOFF_PATHS`, `TASK_PLANNING_ROOT`, `PLANNING_ROOT`) in their spawn prompt — never a cwd-relative `.geniro/...` path
- [ ] Within-skill state files remain cwd-relative (intentional, not regressed)
- [ ] `/geniro:implement`'s workspace-setup question (Step 0), Git-worktree option, surfaces a one-line worktree-entry note that knowledge writes auto-route to the main worktree
