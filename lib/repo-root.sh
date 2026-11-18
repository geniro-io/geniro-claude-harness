#!/usr/bin/env bash
# Shared repo-root resolver.
#
# Returns the absolute path to the project root — where `.geniro/` lives.
# Used by every memory-layer helper that touches paths under `.geniro/`.
#
# Resolution order:
#   1. main checkout of the repository, when cwd is in a different checkout.
#      Every `.geniro/` write lands there (skills/_shared/primary-worktree.md),
#      otherwise it is lost when a linked worktree is removed. "Main" is the
#      parent of the git common dir when that parent's own `.git` (a directory,
#      or a file `gitdir: <path>`) resolves to the common dir: a normal repo, or
#      a bare hub (`<hub>/.bare` + `<hub>/.git` file) -> `<hub>`. Else a bare
#      common dir is its own main. Else the first non-bare entry of
#      `git worktree list --porcelain`. A common dir with `core.worktree` set
#      (submodule) names its main checkout there, never the git dir: a submodule's main is its own checkout, then the
#      walk-up from there, so every worktree of it resolves alike. This MUST run before the
#      walk-up below: a linked worktree may have its own `.geniro/` directory,
#      and the walk-up would otherwise return it and never reach main.
#   2. walk up the directory tree looking for `.geniro/` (authoritative
#      marker for "this is a Geniro project root"; handles nested git
#      repos like submodules inside a Geniro-rooted project)
#   3. `git rev-parse --show-toplevel` (fallback for fresh installs where
#      `.geniro/` doesn't exist yet)
#   4. `$PWD` (last resort — no git, no .geniro)
#
# Every printed path is physical (`pwd -P`). A worktree whose main checkout was
# moved or renamed makes git fail; that case warns on stderr (once per shell that exports the guard) (stdout stays the fallback path) and continues at 2.
#
# Pre-consolidation each helper had its own near-copy (_red_repo_root,
# _el_repo_root, _ql_repo_root, _ls_repo_root, _us_repo_root) and a couple
# of them silently disagreed (only redact-secrets walked up for .geniro;
# others returned PWD straight from the fallback). Single source removes
# the drift surface.
#
# Output: prints the resolved path to stdout. Always rc=0, also under `set -e`.

# Physical (symlink-free) absolute form of directory $1; prints nothing if absent.
_gr_phys() {
  (cd "$1" 2>/dev/null && pwd -P)
}

# Main checkout from the physical git common dir $1; prints nothing when it cannot tell.
_gr_main_from_common() {
  local common="$1" p g w cfg line key val bare=""
  [ -n "$common" ] || return 0
  p="$(dirname "$common")"
  g=""
  if [ -d "$p/.git" ]; then
    g="$p/.git"
  elif [ -f "$p/.git" ]; then
    g="$(sed -n 's/^gitdir: *//p' "$p/.git" 2>/dev/null | head -n 1)" || true
    case "$g" in /*) ;; *) g="$p/$g" ;; esac
  fi
  if [ -n "$g" ] && [ "$(_gr_phys "$g" || true)" = "$common" ]; then
    echo "$p"
    return 0
  fi
  w=""
  cfg="$(git --git-dir="$common" config --get-regexp '^core\.(worktree|bare)$' 2>/dev/null || true)"
  while IFS= read -r line; do
    case "$line" in
      *" "*) key="${line%% *}"; val="${line#* }" ;;
      *) key="$line"; val="true" ;;
    esac
    case "$key" in
      core.worktree) w="$val" ;;
      core.bare) bare="$val" ;;
    esac
  done <<EOF
$cfg
EOF
  if [ -n "$w" ]; then
    case "$w" in /*) ;; *) w="$common/$w" ;; esac
    w="$(_gr_phys "$w" || true)"
    # Walk up from the submodule checkout so a linked worktree of it and the
    # checkout itself agree on one root (a superproject's `.geniro/` wins).
    if [ -n "$w" ]; then _gr_walk_root "$w"; return 0; fi
  fi
  case "$bare" in
    true|True|TRUE|yes|Yes|YES|on|On|ON|1) echo "$common" ;;
  esac
  return 0
}

# Nearest `.git` file above $PWD whose `gitdir:` target is missing: prints
# `<worktree dir><TAB><gitdir>` for the caller to report.
_gr_stale_gitdir() {
  local d="$PWD" g
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -f "$d/.git" ]; then
      g="$(sed -n 's/^gitdir: *//p' "$d/.git" 2>/dev/null | head -n 1)" || true
      case "$g" in /*) ;; *) g="$d/$g" ;; esac
      if [ -n "$g" ] && [ ! -e "$g" ]; then printf '%s\t%s\n' "$d" "$g"; fi
      return 0
    fi
    d="$(dirname "$d")"
  done
}

_gr_walk_root() {  # [start dir, default $PWD] [toplevel the caller already resolved, "" = none]
  local d="${1:-$PWD}" t
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -d "$d/.geniro" ]; then
      _gr_phys "$d" || echo "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  if [ $# -ge 2 ]; then
    t="$2"
  else
    t="$(git rev-parse --show-toplevel 2>/dev/null)" || t=""
  fi
  [ -z "${1:-}" ] || t="$1"
  if [ -n "$t" ]; then
    _gr_phys "$t" || echo "$t"
    return 0
  fi
  _gr_phys "$PWD" || echo "$PWD"
  return 0
}

_geniro_repo_root() {
  local raw nl common toplevel main out stale tab g
  nl=$'\n'
  raw="$(git rev-parse --path-format=absolute --git-common-dir --show-toplevel 2>/dev/null)" || true
  case "$raw" in
    "--path-format=absolute"|"--path-format=absolute$nl"*) raw="${raw#--path-format=absolute}"; raw="${raw#"$nl"}" ;;
  esac
  common="${raw%%"$nl"*}"
  toplevel=""
  case "$raw" in
    *"$nl"*) toplevel="${raw#*"$nl"}"; toplevel="${toplevel%%"$nl"*}" ;;
  esac
  [ -z "$toplevel" ] || toplevel="$(_gr_phys "$toplevel")" || true
  [ -z "$common" ] || common="$(_gr_phys "$common")" || true
  main=""
  [ -z "$common" ] || main="$(_gr_main_from_common "$common")" || true
  if [ -z "$main" ] && [ -n "$toplevel" ]; then
    # Porcelain stanzas are `worktree <path>` followed by attribute lines
    # (`bare` / `HEAD …` / `branch …`), blank-line separated. Skip bare
    # entries: in a worktree of a bare repo the FIRST entry is the bare dir
    # itself, which is not a checkout.
    # If every entry is bare, print nothing → fall through to the walk-up.
    main="$(git worktree list --porcelain 2>/dev/null | awk '
      /^worktree / { path = $0; sub(/^worktree /, "", path) }
      /^bare$/     { path = "" }
      /^$/         { if (path != "") { done = 1; print path; exit } }
      END          { if (!done && path != "") print path }
    ')" || true
    [ -z "$main" ] || main="$(_gr_phys "$main")" || true
    # `--separate-git-dir` repos: git lists the git dir itself as the main
    # worktree. A git dir is not a checkout, so fall through to the walk-up.
    if [ -n "$main" ] && [ "$main" = "$common" ]; then
      main=""
    fi
  fi
  if [ -n "$main" ] && [ "$toplevel" != "$main" ]; then
    echo "$main"
    return 0
  fi

  out="$(_gr_walk_root "" "$toplevel")" || true
  if [ -z "$main" ] && [ -z "$toplevel" ]; then
    tab="$(printf '\t')"
    stale="$(_gr_stale_gitdir)" || true
    if [ -n "$stale" ] && [ -z "${_GENIRO_ROOT_WARNED:-}" ]; then
      export _GENIRO_ROOT_WARNED=1
      g="${stale#*"$tab"}"
      echo "geniro: this worktree's main checkout is missing at ${g%/.git/worktrees/*} (moved or renamed?) — .geniro/ writes fall back to $out; run 'git worktree repair ${stale%%"$tab"*}' from the main checkout's new location." >&2
    fi
  fi
  echo "$out"
}

# Resolve the directory the L4 custom-instruction files are loaded from.
# Honors an external override so instructions can live outside the repo
# (e.g. a clean fresh-clone environment where .geniro/instructions/ is not
# committed). Precedence: GENIRO_INSTRUCTIONS_DIR > the plugin install
# option's CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR > <repo-root>/.geniro/instructions.
# A configured-but-missing external dir falls back to the in-repo default
# (fail-open). Always rc=0; prints an absolute path.
_geniro_instructions_dir() {
  local ext="${GENIRO_INSTRUCTIONS_DIR:-}"
  [ -z "$ext" ] && ext="${CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR:-}"
  if [ -n "$ext" ]; then
    # shellcheck disable=SC2088  # literal tilde match patterns, not expansions
    case "$ext" in
      "~")   ext="$HOME" ;;
      "~/"*) ext="$HOME/${ext#"~/"}" ;;
    esac
    if [ -d "$ext" ]; then
      echo "$ext"
      return 0
    fi
    # configured but not a directory → fail-open to the in-repo default
  fi
  echo "$(_geniro_repo_root)/.geniro/instructions"
}
