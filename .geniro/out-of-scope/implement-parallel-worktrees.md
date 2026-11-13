# Per-ticket parallel worktrees in /geniro:implement

Each ticket's implementer subagent runs in its own worktree on its own branch, in parallel, and the branches are integrated afterwards (Pocock's `implement-spec`).

## Why this is out of scope

`/geniro:implement` works in the one workspace the run chose (`skills/_shared/workspace-chooser.md`) and delegates only disjoint file sets in parallel (`skills/implement/phase-2-implement.md`). Disjoint ownership already stops agents overwriting each other. Per-ticket worktrees add base-reset, branch-integration and cleanup steps for a failure the current loop has not shown.

## Prior requests

- 2026-10-05: raised while comparing Pocock's skills with Geniro's; not adopted.
