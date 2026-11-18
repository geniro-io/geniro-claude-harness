#!/usr/bin/env bash
# Unit dir resolver: every human-facing artifact of one unit of work lives in
# ONE folder, <PLANNING_ROOT>/<unit>/, next to spec.md and state.md.
#
# PLANNING_ROOT (_geniro_planning_root) = <_geniro_repo_root>/.geniro/planning:
#   always the main checkout, never a linked worktree.
#
# _geniro_state_dir <skill> [branch] prints <_geniro_repo_root>/.geniro/state/<skill>/<branch slug>
#   (default: the current branch). Never creates it. No skill: prints nothing.
#
# _geniro_unit_dir [branch] prints the absolute unit dir for the branch (default:
#   the current branch). Never creates it. First match wins:
#   1. No branch (detached/non-git), or an integration branch (main, master,
#      develop, trunk, the target of refs/remotes/origin/HEAD):
#      <PLANNING_ROOT>/<branch slug>. No binding search: every plan authored on
#      main records `branch: main`.
#   2. Explicit binding: a dir directly under PLANNING_ROOT (names starting with
#      `_` or `.` skipped) where state.md, review.md, debug.md or
#      debug-adversarial.md has a first-frontmatter-block `branch:` equal to the
#      branch. Several: the one with the newest matching file.
#   3. Name: T = slug of the branch minus its first segment when it has exactly
#      one `/` (two segments) (feat/ci-1-x -> ci-1-x; a/b/c and x keep the full slug);
#      S = the full slug. First of T, S that exists and is not bound to ANOTHER
#      branch (one of the four files declares a branch that is neither this one
#      nor an integration branch).
#   4. Ticket: K = first [A-Za-z][A-Za-z0-9]*-[0-9]+ in the branch (first
#      segment dropped as in 3), lowercased. Exactly ONE dir named K or K-* not
#      bound to another branch is returned; zero or several fall through.
#   5. <PLANNING_ROOT>/T, unless a dir T exists bound to another branch: then S.
#
# _geniro_handoff_target <review|debug|debug-adversarial> [branch] prints the path
#   a PRODUCER writes: the newest existing <name>.md among all dirs bound to the
#   branch (rule 2) and the unit dir; else <unit>/<name>.md. Never the legacy path.
#
# _geniro_handoff_path <review|debug|debug-adversarial> [branch] prints the path
#   a CONSUMER reads: the target path if that file exists, else the legacy
#   <repo-root>/.geniro/state/handoff/from-<name>-<branch slug>.md if it exists,
#   else the target path.
#
# Always rc 0. Bash 3.2 and zsh compatible.

if [ -z "${_UD_DEPS_LOADED:-}" ]; then
  # Cross-shell self-location (see emit-learning.sh): BASH_SOURCE is bash-only.
  if [ -n "${BASH_SOURCE:-}" ]; then
    _ud_self="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval '_ud_self="${(%):-%x}"'
  else
    _ud_self="$0"
  fi
  _ud_script_dir="$(cd "$(dirname "$_ud_self")" && pwd)"
  # shellcheck disable=SC1091
  source "$_ud_script_dir/repo-root.sh"
  # shellcheck disable=SC1091
  source "$_ud_script_dir/branch-slug.sh"
  _UD_DEPS_LOADED=1
fi

_geniro_planning_root() {
  printf '%s' "$(_geniro_repo_root)/.geniro/planning"
}

_geniro_state_dir() {
  local skill="${1-}" branch="${2-}" root
  [ -n "$skill" ] || return 0
  [ -z "$branch" ] && branch="$(git branch --show-current 2>/dev/null || true)"
  root="$(_geniro_repo_root)" || true
  [ -n "$root" ] || return 0
  printf '%s' "$root/.geniro/state/$skill/$(_geniro_branch_slug "$branch")"
}

# One scan of every candidate file's first-frontmatter-block `branch:` value
# (quotes and blanks stripped), newest file first. Lines: <dir><TAB><branch>.
_ud_scan_load() {
  _ud_scan=""
  [ -d "$1" ] || return 0
  _ud_scan="$(find "$1" -mindepth 2 -maxdepth 2 -type f \( -name state.md -o -name review.md -o -name debug.md -o -name debug-adversarial.md \) -exec ls -t {} + 2>/dev/null | awk '
    {
      f = $0; d = f; sub(/\/[^\/]*$/, "", d); base = d; sub(/.*\//, "", base)
      if (base ~ /^[_.]/) next
      n = 0
      while ((getline line < f) > 0) {
        n++
        if (n == 1) { if (line != "---") break; continue }
        if (line ~ /^---[ \t]*$/) break
        if (line ~ /^branch:/) {
          v = line; sub(/^branch:/, "", v); gsub(/["'"'"' \t\r]/, "", v)
          if (v != "") printf "%s\t%s\n", d, v
          break
        }
      }
      close(f)
    }' 2>/dev/null)"
}

_ud_load_head() {
  _ud_head="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
}

_ud_is_integration() {
  case "$1" in main|master|develop|trunk) return 0 ;; esac
  [ -n "${_ud_head:-}" ] && [ "$1" = "${_ud_head#*/}" ]
}

# rc 0 when the dir declares a branch that is neither $2 nor an integration branch.
_ud_bound_other() {
  local d="$1" b="$2" sd sb tab
  tab="$(printf '\t')"
  while IFS="$tab" read -r sd sb; do
    [ "$sd" = "$d" ] || continue
    [ "$sb" = "$b" ] && continue
    _ud_is_integration "$sb" && continue
    return 0
  done <<EOF
$_ud_scan
EOF
  return 1
}

_ud_subdirs() {
  find "$1" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

# Bound dirs of branch $1, newest first, one per line.
_ud_bound_dirs() {
  local b="$1" sd sb tab seen="
"
  tab="$(printf '\t')"
  while IFS="$tab" read -r sd sb; do
    [ "$sb" = "$b" ] || continue
    case "$seen" in *"
$sd
"*) continue ;; esac
    seen="$seen$sd
"
    printf '%s\n' "$sd"
  done <<EOF
$_ud_scan
EOF
}

# Unit dir for branch $1 under root $2; needs _ud_scan and _ud_head loaded.
_ud_resolve() {
  local branch="$1" root="$2" s t rest k d name found n
  s="$(_geniro_branch_slug "$branch")"
  if [ -z "$branch" ] || _ud_is_integration "$branch"; then
    printf '%s' "$root/$s"
    return 0
  fi

  d="$(_ud_bound_dirs "$branch" | head -n 1)"
  if [ -n "$d" ]; then printf '%s' "$d"; return 0; fi

  rest="$branch"
  case "$branch" in
    */*/*) ;;
    */*) rest="${branch#*/}" ;;
  esac
  t="$(_geniro_branch_slug "$rest")"
  for name in "$t" "$s"; do
    if [ -d "$root/$name" ] && ! _ud_bound_other "$root/$name" "$branch"; then
      printf '%s' "$root/$name"
      return 0
    fi
  done

  k="$(printf '%s' "$rest" | grep -oE '[A-Za-z][A-Za-z0-9]*-[0-9]+' 2>/dev/null | head -n 1 | tr '[:upper:]' '[:lower:]')"
  if [ -n "$k" ] && [ -d "$root" ]; then
    n=0
    found=""
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      name="${d%/}"; name="${name##*/}"
      case "$name" in "$k"|"$k"-*) ;; *) continue ;; esac
      _ud_bound_other "$d" "$branch" && continue
      n=$((n + 1))
      found="$d"
    done <<EOF
$(_ud_subdirs "$root")
EOF
    if [ "$n" -eq 1 ]; then printf '%s' "$found"; return 0; fi
  fi

  if [ -d "$root/$t" ] && _ud_bound_other "$root/$t" "$branch"; then
    printf '%s' "$root/$s"
  else
    printf '%s' "$root/$t"
  fi
}

_geniro_unit_dir() {
  local branch="${1-}" root
  [ -z "$branch" ] && branch="$(git branch --show-current 2>/dev/null || true)"
  root="$(_geniro_planning_root)"
  _ud_load_head
  _ud_scan_load "$root"
  _ud_resolve "$branch" "$root"
}

_geniro_handoff_target() {
  local name="${1-}" branch="${2-}" root unit d
  [ -z "$branch" ] && branch="$(git branch --show-current 2>/dev/null || true)"
  root="$(_geniro_planning_root)"
  _ud_load_head
  _ud_scan_load "$root"
  unit="$(_ud_resolve "$branch" "$root")"
  set --
  [ -f "$unit/$name.md" ] && set -- "$unit/$name.md"
  if [ -n "$branch" ] && ! _ud_is_integration "$branch"; then
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      [ "$d" = "$unit" ] && continue
      [ -f "$d/$name.md" ] && set -- "$@" "$d/$name.md"
    done <<EOF
$(_ud_bound_dirs "$branch")
EOF
  fi
  case $# in
    0) printf '%s' "$unit/$name.md" ;;
    1) printf '%s' "$1" ;;
    *) command ls -t -- "$@" 2>/dev/null | head -n 1 | tr -d '\n' ;;
  esac
}

_geniro_handoff_path() {
  local name="${1-}" branch="${2-}" target legacy
  [ -z "$branch" ] && branch="$(git branch --show-current 2>/dev/null || true)"
  target="$(_geniro_handoff_target "$name" "$branch")"
  legacy="$(_geniro_repo_root)/.geniro/state/handoff/from-$name-$(_geniro_branch_slug "$branch").md"
  if [ -f "$target" ]; then
    printf '%s' "$target"
  elif [ -f "$legacy" ]; then
    printf '%s' "$legacy"
  else
    printf '%s' "$target"
  fi
}
