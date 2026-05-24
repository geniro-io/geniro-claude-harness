#!/usr/bin/env bash
# Shared repo-root resolver.
#
# Returns the absolute path to the project root — where `.geniro/` lives.
# Used by every memory-layer helper that touches paths under `.geniro/`.
#
# Resolution order:
#   1. walk up the directory tree looking for `.geniro/`  (authoritative —
#      this is the canonical marker for "this is a Geniro project root")
#   2. `git rev-parse --show-toplevel`  (fallback for fresh installs where
#      `.geniro/` doesn't exist yet)
#   3. `$PWD`  (last resort — no git, no .geniro)
#
# The walk-up is FIRST so that nested git repos (submodules, vendored
# dependencies) inside a `.geniro/`-rooted project resolve to the outer
# project, not the inner submodule. A prior version preferred git toplevel,
# which silently steered writes into submodules under `.geniro/`.
#
# Pre-consolidation each helper had its own near-copy (_red_repo_root,
# _el_repo_root, _ql_repo_root, _ls_repo_root, _us_repo_root) and a couple
# of them silently disagreed (only redact-secrets walked up for .geniro;
# others returned PWD straight from the fallback). Single source removes
# the drift surface.
#
# Output: prints the resolved path to stdout. Always rc=0.

_geniro_repo_root() {
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
