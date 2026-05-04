---
name: primary-worktree
description: "Canonical resolver for cross-session persistent state. Ensures writes/reads land in the main repo's working tree even when the session is in a linked worktree (the gitignored `.geniro/*` would otherwise be lost on `git worktree remove`)."
---

# Primary-worktree resolution for persistent state

## Why this exists

The default plugin `.gitignore` keeps `.geniro/*` out of git (only `workflow/`, `instructions/`, and `actions/` are negated). When `/geniro:implement` Phase 1 Step 10 picks Option C, `EnterWorktree` switches the session into `.claude/worktrees/<dir>/`. From that point, every cwd-relative `.geniro/<x>` write lands in the worktree's gitignored tree — and is destroyed when the user removes the worktree at session end. The main repo's `.geniro/<x>` never receives the write.

This affects every artifact designed to outlive the current task. Task-local state (planning/<task-dir>/* — explicitly cleaned at Phase 7) is unaffected and stays cwd-relative.

## The resolver

### Mode A — Orchestrator-level Bash

Skills running orchestrator-level Bash compute a single prefix before any persistent read or write:

```bash
TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null)"
PRIMARY="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2; exit}')"
if [ -z "$TOPLEVEL" ] || [ -z "$PRIMARY" ] || [ "$TOPLEVEL" = "$PRIMARY" ]; then
  PRIMARY_ROOT="."        # main worktree (or non-git project); cwd-relative is fine
else
  PRIMARY_ROOT="$PRIMARY"  # linked worktree; route writes to main
fi
```

Then for every cross-session artifact:
- Reads: `Read "$PRIMARY_ROOT/.geniro/knowledge/learnings.jsonl"` (etc.)
- Writes: `mkdir -p "$PRIMARY_ROOT/.geniro/knowledge"` then Edit/Write at the same prefix.

If `git` is missing or the project isn't a git repo, both probes return empty → fall back to cwd-relative. Non-git projects have no linked-worktree problem.

### Mode B — Subagents without Bash

Some agents (`knowledge-retrieval-agent` has `tools: [Read, Glob, Grep]` only — no Bash) cannot run the resolver themselves. The spawning orchestrator must compute `PRIMARY_ROOT` in Mode A and inline absolute paths into the agent's spawn prompt as named slots, mirroring how `_shared/scope-anchor.md` propagates `WORKTREE` and `BRANCH`. Use narrow per-domain slots (each is `PRIMARY_ROOT/.geniro/<domain>`) — there is no umbrella slot:

```
KNOWLEDGE_ROOT: <PRIMARY_ROOT>/.geniro/knowledge
DEBUG_ROOT: <PRIMARY_ROOT>/.geniro/debug
PLANNING_ROOT: <PRIMARY_ROOT>/.geniro/planning   # cross-session subset only
TASK_PLANNING_ROOT: <current-cwd>/.geniro/planning  # task-local; intentionally cwd-relative
```

The agent reads/globs against the inlined absolute path. It never substitutes its own cwd. If a Bash-less agent is given a cwd-relative `.geniro/...` path, it is a spawn-prompt bug — fix the orchestrator, not the agent.

## Artifacts that MUST use the resolver (cross-session)

These are intended to outlive any single task. The resolver applies to both reads and writes.

| Artifact | Producer(s) | Consumer(s) | Notes |
|---|---|---|---|
| `.geniro/knowledge/learnings.jsonl` | `/learnings`, `/implement` Phase 7, `/follow-up` Phase 6, `/debug` Step 7, `/refactor` Phase 6, `/investigate` Step 2a | `knowledge-retrieval-agent`, `/refactor` Phase 1, `/decompose`, `/debug` Step 1, `/features` triage, `/investigate` Step 1 | structured corpus |
| `.geniro/debug/findings-state.md` | `/debug` Step 6.5a | `/follow-up`, `/implement` Phase 1 Step 1 | carries `Source branch:` / `Source worktree:` already; resolver removes the need to copy across worktrees |
| `.geniro/debug/adversarial-tests.md` | `/debug` adversarial mode | `/follow-up`, `/implement` Phase 1 Step 1 | same handoff |
| `.geniro/review-findings-state.md` | `/review` | `/follow-up`, `/implement` Phase 6 fix-loop | carries `[POSTED-TO-PR]` idempotency markers — losing the file = double-posting on rerun |
| `.geniro/planning/FEATURES.md` | `/features` (CRUD) | `/implement` (binding), `/decompose` | persistent registry |
| `.geniro/planning/CODEBASE_MAP.md`, `.geniro/planning/focus-<area>.md` | `/onboard` | every skill that consults the map | persistent orientation artifacts |

## Artifacts NOT in scope (task-local — keep cwd-relative)

These are intentionally ephemeral with the current task. Promoting them to the resolver would introduce false durability where none is wanted.

- `.geniro/planning/<task-dir>/*` — spec.md, plan-*.md, state.md, concerns.md, notes.md, milestone-*.md. Removed at `/implement` Phase 7 cleanup.
- `.geniro/debug/HYPOTHESES.md` — deleted at `/debug` cleanup.
- `.geniro/follow-up-state.md`, `.geniro/refactor/state.md`, `.geniro/improve-template-state.md` — within-skill resume-from-compaction state.
- `.geniro/state/pre-compact-snapshot.json` — per-session compaction snapshot.

If a within-skill state file is later promoted to cross-session use, add it to the cross-session table above.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This skill never runs in a worktree" | `/geniro:implement` Option C puts the session in a worktree, and orchestrators downstream of it inherit that cwd. Any cross-session write made there is exposed. |
| "I'll commit the file in the worktree to preserve it" | `.geniro/*` is gitignored — `git add` is a no-op. Even if not, the commit lands on the feature branch, not main. |
| "I'll make `.geniro/knowledge/` not gitignored" | Different fix, different problem. Knowledge bleeds across feature branches → merge conflicts. The resolver writes to main's tree without involving any branch. |
| "The subagent has no Bash, so it'll just resolve the path itself" | It can't. Mode B requires the orchestrator pre-resolve and inline. Cwd-relative paths in a Bash-less agent's prompt are a spawn-prompt bug. |
| "I'll apply the resolver to within-skill state files for safety" | Don't. Those are intentionally task-scoped. Adding the resolver promotes them to cross-session, which they're not, and breaks the cleanup contract. |
| "`git rev-parse` might fail — better to error out" | Falling back to cwd-relative is correct: non-git projects have no linked-worktree problem, so cwd-relative is durable there. |

## Definition of Done

- [ ] Every cross-session producer in the table above resolves the prefix via Mode A before writing
- [ ] Every cross-session consumer reads through the same prefix
- [ ] Subagents that read cross-session state receive narrow `*_ROOT` slots (`KNOWLEDGE_ROOT`, `DEBUG_ROOT`, `PLANNING_ROOT`, `TASK_PLANNING_ROOT`) in their spawn prompt — never a cwd-relative `.geniro/...` path
- [ ] Within-skill state files remain cwd-relative (intentional, not regressed)
- [ ] `/implement` Phase 1 Step 10 surfaces a one-line worktree-entry note that knowledge/handoff writes auto-route to the main worktree
