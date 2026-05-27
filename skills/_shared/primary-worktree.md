# Primary-worktree resolution for persistent state

Canonical resolver for cross-session persistent state. Ensures writes/reads land in the main repo's working tree even when the session is in a linked worktree (the gitignored `.geniro/*` would otherwise be lost on `git worktree remove`).

## Why this exists

The default plugin `.gitignore` keeps `.geniro/*` out of git (only `workflow/`, `instructions/`, and `actions/` are negated). Two consequences:

- **(a) Writes lost on worktree removal.** When `/geniro:implement` Phase 1 Step 10 picks Option C, `EnterWorktree` switches the session into `.claude/worktrees/<dir>/` — every cwd-relative `.geniro/<x>` write lands in the worktree's gitignored tree and is destroyed when the user removes the worktree at session end.
- **(b) Authored content invisible to fresh linked worktrees.** Even when the worktree is fresh and persistent, the primary worktree's authored content (`.geniro/instructions/<scope>.md`, `.geniro/workflow/<kind>.md`, `.geniro/actions/<slug>.md`) is NOT propagated by `git worktree add` because those paths are gitignored at the project level (negation is a default; project-side `.git/info/exclude` may override). The main repo's `.geniro/<x>` never receives the write, and the linked worktree never sees the read.

This affects every artifact designed to outlive the current task. Task-local state (planning/<task-dir>/* — explicitly cleaned at Phase 7) is unaffected and stays cwd-relative.

## The resolver

### Mode A — Orchestrator-level Bash

Skills running orchestrator-level Bash compute a single prefix before any persistent read or write:

```bash
TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null)"
PRIMARY="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')"
if [ -z "$TOPLEVEL" ] || [ -z "$PRIMARY" ] || [ "$TOPLEVEL" = "$PRIMARY" ]; then
 PRIMARY_ROOT="." # main worktree (or non-git project); cwd-relative is fine
else
 PRIMARY_ROOT="$PRIMARY" # linked worktree; route writes to main
fi
```

Then for every cross-session artifact:
- Reads: `Read "$PRIMARY_ROOT/.geniro/knowledge/learnings.jsonl"` (etc.)
- Writes: `mkdir -p "$PRIMARY_ROOT/.geniro/knowledge"` then Edit/Write at the same prefix.

If `git` is missing or the project isn't a git repo, both probes return empty → fall back to cwd-relative. Non-git projects have no linked-worktree problem.

### Mode B — Subagents without Bash

Some agents have read-only tool surfaces (e.g. `tools: [Read, Glob, Grep]`) and cannot run the resolver themselves. The spawning orchestrator must compute `PRIMARY_ROOT` in Mode A and inline absolute paths into the agent's spawn prompt as named slots, mirroring how `_shared/scope-anchor.md` propagates `WORKTREE` and `BRANCH`. Use narrow per-domain slots (each is `PRIMARY_ROOT/.geniro/<domain>`) — there is no umbrella slot:

```
KNOWLEDGE_ROOT: <PRIMARY_ROOT>/.geniro/knowledge
DEBUG_ROOT: <PRIMARY_ROOT>/.geniro/debug
PLANNING_ROOT: <PRIMARY_ROOT>/.geniro/planning # cross-session subset only
TASK_PLANNING_ROOT: <current-cwd>/.geniro/planning # task-local; intentionally cwd-relative
```

The agent reads/globs against the inlined absolute path. It never substitutes its own cwd. If a Bash-less agent is given a cwd-relative `.geniro/...` path, it is a spawn-prompt bug — fix the orchestrator, not the agent.

## Artifacts that MUST use the resolver (cross-session)

These are intended to outlive any single task. The resolver applies to both reads and writes.

| Artifact | Producer(s) | Consumer(s) | Notes |
|---|---|---|---|
| `.geniro/knowledge/learnings.jsonl` | `/implement`, `/plan`, `/debug`, `/review`, `/refactor`, `/onboard`, `/investigate` | every pipeline skill's Phase-1 `query-learnings` prior-knowledge lookup | structured corpus |
| `.geniro/state/handoff/from-debug-<branch>.md` | `/debug` Phase 3 | `/implement` Phase 1 Step 1 | carries frontmatter `branch:` / `worktree:` fields; resolver removes the need to copy across worktrees |
| `.geniro/state/handoff/from-debug-adversarial-<branch>.md` | `/debug` adversarial mode | `/implement` Phase 1 Step 1 | same handoff |
| `.geniro/state/handoff/from-review-<branch>.md` | `/review` | `/implement` Phase 1 step 8 «Persist T2 handoffs» | carries `[POSTED-TO-PR]` idempotency markers — losing the file = double-posting on rerun |
| `.geniro/planning/_FEATURES.md` | manual or `/plan` | `/implement` (binding), `/plan` | persistent registry |
| `.geniro/planning/_CODEBASE_MAP.md` | `/onboard` | every skill that consults the map (`/implement`, `/plan`, `/debug`, `/review`, `/refactor`, `/investigate`) | persistent orientation artifact; bounded auto-incremental writes via `update-semantic`.1 |
| `.geniro/planning/_focus-<area>.md` | `/onboard <area>` (manual scope-limiter via `--focus` flag persists a concentrated map alongside the full `_CODEBASE_MAP.md`); `/investigate --persist` | every skill that consults focused-area context | persistent orientation artifact for a subsystem |
| `.geniro/workflow/<kind>.md` | manual / `/setup` | `/plan`, `/implement`, `/review`, `/refactor` | Tracker integration configs (Linear/Jira/GitHub-Issues/Asana); read with cwd-first / primary-fallback per per-site preambles |
| `.geniro/actions/<slug>.md` | manual / `/actions create` | `/actions` (list/run/validate/delete) | User-authored workflow-helper actions; dual-glob with local-wins-on-slug-collision per `skills/actions/SKILL.md` Phase 5.0 Step 1 |
| `.geniro/instructions/<scope>.md` | manual / `/setup` / `/instructions create` | every pipeline skill's Phase 1 `load-custom-instructions` invocation | L4 procedural memory (global / code-style / per-skill / review-extra/<slug>); cwd-first / primary-fallback per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md:44` |

## Artifacts NOT in scope (task-local — keep cwd-relative)

These are intentionally ephemeral with the current task. Promoting them to the resolver would introduce false durability where none is wanted.

- `.geniro/planning/<task-dir>/*` — spec.md, plan-*.md, state.md, concerns.md, notes.md, milestone-*.md. Removed at `/implement` Phase 3 ship-cleanup.
- `.geniro/state/refactor/<slug>/state.md`, `.geniro/state/debug/<slug>/state.md`, `.geniro/state/onboard/<slug>/state.md`, `.geniro/state/investigate/<slug>/state.md` — within-skill resume-from-compaction state, branch-scoped per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md`. Each is deleted at its skill's cleanup phase.

If a within-skill state file is later promoted to cross-session use, add it to the cross-session table above.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This skill never runs in a worktree" | `/geniro:implement` Option C puts the session in a worktree, and orchestrators downstream of it inherit that cwd. Any cross-session write made there is exposed. |
| "I'll commit the file in the worktree to preserve it" | `.geniro/*` is gitignored — `git add` is a no-op. Even if not, the commit lands on the feature branch, not main. |
| "I'll make `.geniro/knowledge/` not gitignored" | Different fix, different problem. Knowledge bleeds across feature branches → merge conflicts. The resolver writes to main's tree without involving any branch. |
| "The subagent has no Bash, so it'll just resolve the path itself" | It can't. Mode B requires the orchestrator pre-resolve and inline. Cwd-relative paths in a Bash-less agent's prompt are a spawn-prompt bug. |
| "I'll apply the resolver to within-skill state files for safety" | Don't. Those are intentionally task-scoped. Use `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` instead — it solves their parallel-session collision via branch slug + Branch/Worktree/Timestamp headers + Case-C mismatch AUQ, while keeping the cleanup contract intact. |
| "`git rev-parse` might fail — better to error out" | Falling back to cwd-relative is correct: non-git projects have no linked-worktree problem, so cwd-relative is durable there. |

## Definition of Done

- [ ] Every cross-session producer in the table above resolves the prefix via Mode A before writing
- [ ] Every cross-session consumer reads through the same prefix
- [ ] Subagents that read cross-session state receive narrow `*_ROOT` slots (`KNOWLEDGE_ROOT`, `DEBUG_ROOT`, `PLANNING_ROOT`, `TASK_PLANNING_ROOT`) in their spawn prompt — never a cwd-relative `.geniro/...` path
- [ ] Within-skill state files remain cwd-relative (intentional, not regressed)
- [ ] `/implement` Phase 1 Step 10 surfaces a one-line worktree-entry note that knowledge/handoff writes auto-route to the main worktree
