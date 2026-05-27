#!/usr/bin/env bash
# Shared repo-root resolver.
#
# Returns the absolute path to the project root — where `.geniro/` lives.
# Used by every memory-layer helper that touches paths under `.geniro/`.
#
# Resolution order:
#   1. linked-worktree check via `git worktree list --porcelain` — if cwd
#      is in a LINKED git worktree, return the PRIMARY worktree's path.
#      Cross-session helpers (learnings, semantic snapshots, archive
#      sweeps) MUST land in the primary worktree per primary-worktree.md;
#      otherwise the writes are lost when the linked worktree is removed.
#      This MUST run before the walk-up below: a linked worktree may have
#      its own `.geniro/` directory (planning/<task-dir>/* gets created
#      there as the user works), and the walk-up would otherwise return
#      the linked-worktree path and never reach primary.
#   2. walk up the directory tree looking for `.geniro/` (authoritative
#      marker for "this is a Geniro project root"; handles nested git
#      repos like submodules inside a Geniro-rooted project)
#   3. `git rev-parse --show-toplevel` (fallback for fresh installs where
#      `.geniro/` doesn't exist yet)
#   4. `$PWD` (last resort — no git, no .geniro)
#
# Pre-consolidation each helper had its own near-copy (_red_repo_root,
# _el_repo_root, _ql_repo_root, _ls_repo_root, _us_repo_root) and a couple
# of them silently disagreed (only redact-secrets walked up for .geniro;
# others returned PWD straight from the fallback). Single source removes
# the drift surface.
#
# Output: prints the resolved path to stdout. Always rc=0.

_geniro_repo_root() {
  local toplevel primary
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$toplevel" ]; then
    primary="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')"
    if [ -n "$primary" ] && [ "$toplevel" != "$primary" ]; then
      echo "$primary"
      return 0
    fi
  fi

  local d="$PWD"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -d "$d/.geniro" ]; then
      echo "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return 0
  fi
  echo "$PWD"
}
