#!/usr/bin/env bash
# Shared repo-root resolver.
#
# Returns the absolute path to the project root — where `.geniro/` lives.
# Used by every memory-layer helper that touches paths under `.geniro/`.
#
# Resolution order:
#   1. git rev-parse --show-toplevel  (if cwd is inside a git work tree)
#   2. walk up the directory tree looking for `.geniro/`
#   3. fall back to $PWD
#
# Pre-consolidation each helper had its own near-copy (_red_repo_root,
# _el_repo_root, _ql_repo_root, _ls_repo_root, _us_repo_root) and a couple
# of them silently disagreed (only redact-secrets walked up for .geniro;
# others returned PWD straight from the fallback). Single source removes
# the drift surface.
#
# Output: prints the resolved path to stdout. Always rc=0.

_geniro_repo_root() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return 0
  fi
  local d="$PWD"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -d "$d/.geniro" ]; then
      echo "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  echo "$PWD"
}
