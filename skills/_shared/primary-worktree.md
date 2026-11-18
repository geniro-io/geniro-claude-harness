# Primary-worktree resolution for persistent state

Canonical resolver for `.geniro/` artifacts. Every write lands in the repository's main checkout, never in a linked worktree, so everything can be analysed in one place and nothing is lost on `git worktree remove`. Whether a project commits any `.geniro/` file is the project's own call.

## Contents

- Why this exists — writes lost on worktree removal; authored content invisible to fresh worktrees; one place to analyse
- The resolver — Mode A (orchestrator Bash) and Mode B (Bash-less subagents)
- Artifacts that use the resolver
- Anti-rationalization
- Definition of Done

## Why this exists

The default plugin `.gitignore` keeps `.geniro/*` out of git (only `workflow/`, `instructions/`, and `actions/` are negated). Two consequences:

- **(a) Writes lost on worktree removal.** When `/geniro:implement`'s workspace-setup question (Step 0) picks the Git-worktree option, entering the worktree switches the session into `.claude/worktrees/<dir>/` — every cwd-relative `.geniro/<x>` write lands in the worktree's gitignored tree and is destroyed when the user removes the worktree at session end.
- **(b) Authored content invisible to fresh linked worktrees.** Even when the worktree is fresh and persistent, the main checkout's authored content (`.geniro/instructions/<scope>.md`, `.geniro/workflow/<kind>.md`, `.geniro/actions/<slug>.md`) is NOT propagated by `git worktree add` because those paths are gitignored at the project level (negation is a default; project-side `.git/info/exclude` may override). The main repo's `.geniro/<x>` never receives the write, and the linked worktree never sees the read.

Session-bound skill state (`.geniro/state/<skill>/<slug>/`) and planning task-dirs follow the same rule: all of it is main-rooted, so a run in a worktree leaves its trail beside every other run's.

## The resolver

### Mode A — Orchestrator-level Bash

Skills running orchestrator-level Bash compute a single prefix before any persistent read or write:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/repo-root.sh"
PRIMARY_ROOT="$(_geniro_repo_root)"   # absolute path of the main checkout
```

`_geniro_repo_root` is the one resolver of "main" — it handles normal repos, bare hubs, and standalone bare repos; never re-derive it by hand. A caller that must know whether it is in the main checkout compares `"$PRIMARY_ROOT"` with `$(cd "$(git rev-parse --show-toplevel)" && pwd -P)` (physical paths).

Then for every artifact:
- Reads: `Read "$PRIMARY_ROOT/.geniro/knowledge/learnings.jsonl"` (etc.)
- Writes: `mkdir -p "$PRIMARY_ROOT/.geniro/knowledge"` then write at the same prefix.

Without git, the function falls back to the project root, so non-git projects keep working.

**Re-run the snippet inside every Bash call that uses the variable** — shell state does not persist across Bash calls, so a value resolved in an earlier call is gone, and an unset `$PRIMARY_ROOT` expands a `"$PRIMARY_ROOT"/.geniro/...` path to a root-anchored `/.geniro/...` path.

### Mode B — Subagents without Bash

Some agents have read-only tool surfaces (e.g. `tools: [Read, Glob, Grep]`) and cannot run the resolver themselves. The spawning orchestrator must compute `PRIMARY_ROOT` in Mode A and inline absolute paths into the agent's spawn prompt as named slots, mirroring how `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` propagates `WORKTREE` and `BRANCH`. Use narrow per-domain slots (each is an absolute path resolved by the orchestrator) — there is no umbrella slot:

```
KNOWLEDGE_ROOT: <PRIMARY_ROOT>/.geniro/knowledge
HANDOFF_PATHS: <absolute existing handoff files for the branch>
TASK_PLANNING_ROOT: <absolute task-dir, under _geniro_planning_root>
PLANNING_ROOT: <PRIMARY_ROOT>/.geniro/planning
```

The agent reads/globs against the inlined absolute path. It never substitutes its own cwd. If a Bash-less agent is given a cwd-relative `.geniro/...` path, it is a spawn-prompt bug — fix the orchestrator, not the agent.

## Artifacts that use the resolver

The resolver applies to both reads and writes.

| Artifact | Producer(s) | Consumer(s) | Notes |
|---|---|---|---|
| `.geniro/knowledge/learnings.jsonl` | `/geniro:implement`, `/geniro:plan`, `/geniro:debug`, `/geniro:review`, `/geniro:refactor`, `/geniro:onboard`, `/geniro:investigate` | every pipeline skill's Phase-1 `query-learnings` prior-knowledge lookup | structured corpus |
| `<PLANNING_ROOT>/<unit>/` — `spec.md`, `state.md`, `review.md`, `debug.md`, `debug-adversarial.md`, `review-brief-<date>.md`, `investigate-<topic-slug>.md` | `/geniro:plan`, `/geniro:implement`, `/geniro:review`, `/geniro:debug`, `/geniro:investigate` | `/geniro:implement` Phase 1 handoff-resolution step (gates on unresolved open questions) and every skill that reads the task-dir | `<PLANNING_ROOT>` is always `<PRIMARY_ROOT>/.geniro/planning` (`${CLAUDE_PLUGIN_ROOT}/lib/unit-dir.sh` `_geniro_planning_root`); `review.md` carries `[POSTED-TO-PR]` idempotency markers — losing the file = double-posting on re-run |
| `.geniro/state/<skill>/<slug>/state.md` (debug, refactor, onboard, investigate, resolve, audit-instructions) and `.geniro/state/audit-instructions/report-<date>.md` | the session-bound skill | the same skill on resume | main-rooted via `_geniro_state_dir`; contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` |
| `.geniro/planning/_FEATURES.md` | manual (no skill writes it) | `/geniro:implement` (when the spec mentions the feature backlog) | persistent registry |
| `.geniro/planning/_CODEBASE_MAP.md` | `/geniro:onboard` | every skill that consults the map (`/geniro:implement`, `/geniro:plan`, `/geniro:debug`, `/geniro:review`, `/geniro:refactor`, `/geniro:investigate`) | persistent orientation artifact; bounded auto-incremental writes via `update-semantic` |
| `.geniro/planning/_focus-<area>.md` | manual | every skill that consults focused-area context | persistent orientation artifact for a subsystem |
| `.geniro/workflow/<kind>.md` | manual / `/geniro:setup` | `/geniro:plan`, `/geniro:implement`, `/geniro:review`, `/geniro:refactor` | Tracker integration configs (Linear/Jira/GitHub-Issues/Asana); read from `<PRIMARY_ROOT>` only; written by `/geniro:setup` to `<PRIMARY_ROOT>` |
| `.geniro/actions/<slug>.md` | manual / `/geniro:actions create` | `/geniro:actions` (list/run/validate/delete) | User-authored workflow-helper actions; every sub-command reads and writes the `<PRIMARY_ROOT>` copy only |
| `.geniro/instructions/<scope>.md` | manual / `/geniro:setup` / `/geniro:instructions create` | every pipeline skill's Phase 1 `load-custom-instructions` invocation | L4 procedural memory (global / code-style / per-skill / review-extra/<slug>); read from `<PRIMARY_ROOT>` only per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Procedure; `/geniro:instructions` CRUD and `/geniro:setup` scaffolds write to `<PRIMARY_ROOT>`. An external override (`GENIRO_INSTRUCTIONS_DIR` or the plugin's `instructions_dir` option), when configured, takes precedence — see the same loader doc |

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This skill never runs in a worktree" | `/geniro:implement`'s "Git worktree" workspace pick puts the session in a worktree, and orchestrators downstream of it inherit that cwd. Any cross-session write made there is exposed. |
| "I'll commit the file in the worktree to preserve it" | A commit made in the worktree lands on the feature branch, not main, and `git add` is a no-op on the ignored `.geniro/*`. Every write goes to the main checkout; committing it from there is the project's choice. |
| "I'll make `.geniro/knowledge/` not gitignored" | Different fix, different problem. Knowledge bleeds across feature branches → merge conflicts. The resolver writes to main's tree without involving any branch. |
| "The subagent has no Bash, so it'll just resolve the path itself" | It can't. Mode B requires the orchestrator pre-resolve and inline. Cwd-relative paths in a Bash-less agent's prompt are a spawn-prompt bug. |
| "`git rev-parse` might fail — better to error out" | `_geniro_repo_root` already falls back to the project root, and non-git projects have no linked-worktree problem. |

## Definition of Done

- [ ] Every producer in the table above resolves the prefix via Mode A before writing
- [ ] Every consumer reads through the same prefix
- [ ] Subagents that read cross-session state receive narrow `*_ROOT` slots (`KNOWLEDGE_ROOT`, `HANDOFF_PATHS`, `TASK_PLANNING_ROOT`, `PLANNING_ROOT`) in their spawn prompt — never a cwd-relative `.geniro/...` path
- [ ] `/geniro:implement`'s workspace-setup question (Step 0), Git-worktree option, surfaces a one-line worktree-entry note that knowledge writes auto-route to the main worktree
