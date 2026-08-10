#!/usr/bin/env bash
# Stage one benchmark task into a disposable working tree and materialize its diff.
#
#   stage-task.sh <task-dir> <stage-dir>
#
# Reads <task-dir>/task.json:
#   mode "git":   { "repo_alias", "base_sha", "head_sha" } -> worktree at head, diff base..head
#   mode "patch": { "fixture_cmd" | "tree_dir", "patch" }  -> copy tree, apply patch
# Writes: <stage-dir>/tree/ (the code under review), <stage-dir>/diff.patch,
#         <stage-dir>/changed-files.txt
#
# Committed task files never carry a repo location or name — "repo_alias" is an
# opaque label resolved through the machine-local, gitignored repos.local.json
# (see repos.local.example.json). "repo_path" is accepted as a local-only escape
# hatch for uncommitted scratch tasks.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TASK_DIR="$(cd "$1" && pwd)"
STAGE_DIR="$2"
# The stage is disposable by definition — restage from scratch so a re-run
# never trips over leftovers (a stale tree, an already-committed base).
[ -n "$STAGE_DIR" ] && rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
STAGE_DIR="$(cd "$STAGE_DIR" && pwd)"
TASK_JSON="$TASK_DIR/task.json"

jqr() { jq -r "$1" "$TASK_JSON"; }
MODE="$(jqr '.mode')"

if [ "$MODE" = "git" ]; then
  REPO="$(jqr '.repo_path // empty')"
  if [ -z "$REPO" ]; then
    ALIAS="$(jqr '.repo_alias // empty')"
    [ -n "$ALIAS" ] || { echo "task.json needs repo_alias (or local-only repo_path)" >&2; exit 64; }
    [ -f "$HERE/repos.local.json" ] || { echo "missing $HERE/repos.local.json — copy repos.local.example.json and map alias '$ALIAS' to a local clone" >&2; exit 66; }
    REPO="$(jq -r --arg a "$ALIAS" '.[$a] // empty' "$HERE/repos.local.json")"
    [ -n "$REPO" ] || { echo "alias '$ALIAS' not mapped in $HERE/repos.local.json" >&2; exit 66; }
  fi
  BASE="$(jqr '.base_sha')"
  HEAD="$(jqr '.head_sha')"
  git -C "$REPO" cat-file -e "${BASE}^{commit}" || { echo "base_sha absent in $REPO" >&2; exit 66; }
  git -C "$REPO" cat-file -e "${HEAD}^{commit}" || { echo "head_sha absent in $REPO" >&2; exit 66; }
  git -C "$REPO" diff "$BASE" "$HEAD" > "$STAGE_DIR/diff.patch"
  git -C "$REPO" diff --name-only "$BASE" "$HEAD" > "$STAGE_DIR/changed-files.txt"
  # A plain archive extract, not a linked worktree: the reviewed tree must not
  # register in the source repo's worktree list (no cleanup coupling, no lock risk).
  # Default full: a 2026-08-09 probe measured pruning saving ~nothing on real
  # monorepo tasks ($0.438 vs $0.44/call) — the agent's reads track its own
  # exploration budget, not tree size. "auto" pruning stays as a per-task
  # opt-in for repos/tasks where a narrow slice is the honest workspace.
  SCOPE_MODE="$(jqr '.workspace_scope // "full"')"
  mkdir -p "$STAGE_DIR/tree"
  if [ "$SCOPE_MODE" = "full" ]; then
    git -C "$REPO" archive "$HEAD" | tar -x -C "$STAGE_DIR/tree"
    echo full > "$STAGE_DIR/workspace-scope.txt"
  else
    # Prune the workspace to the diff's neighborhood: agent workspace reads are
    # ~90% of a real task's token bill, and they scale with what exists to read.
    # Scope = depth-2 subtrees holding changed files + workspace packages the
    # changed files import (by package-name match) + root files + rule surfaces.
    # Paths with spaces are unsupported here (fine for the repos we stage).
    FULL="$STAGE_DIR/.full"
    rm -rf "$FULL"; mkdir -p "$FULL"
    git -C "$REPO" archive "$HEAD" | tar -x -C "$FULL"
    SCOPE="$STAGE_DIR/workspace-scope.txt"
    awk -F/ 'NF>=3 {print $1"/"$2} NF==2 {print $1}' "$STAGE_DIR/changed-files.txt" | sort -u > "$SCOPE.tmp"
    NAMES="$STAGE_DIR/.pkgnames"
    ( cd "$FULL" && find . -mindepth 2 -maxdepth 3 -name package.json | sed 's|^\./||' ) | while IFS= read -r pj; do
      n="$(jq -r '.name // empty' "$FULL/$pj" 2>/dev/null)"
      [ -n "$n" ] && printf '%s\t%s\n' "$n" "$(dirname "$pj")"
    done > "$NAMES"
    CF_LIST="$STAGE_DIR/.changed-present"
    : > "$CF_LIST"
    while IFS= read -r f; do
      [ -f "$FULL/$f" ] && echo "$FULL/$f" >> "$CF_LIST"
    done < "$STAGE_DIR/changed-files.txt"
    if [ -s "$CF_LIST" ] && [ -s "$NAMES" ]; then
      while IFS="	" read -r n d; do
        # shellcheck disable=SC2046
        grep -Fq "$n" $(cat "$CF_LIST") 2>/dev/null && echo "$d"
      done < "$NAMES" >> "$SCOPE.tmp"
    fi
    sort -u "$SCOPE.tmp" > "$SCOPE"
    STAGELIST="$STAGE_DIR/.stagelist"
    ( cd "$FULL" && find . -maxdepth 1 -type f | sed 's|^\./||' ) > "$STAGELIST"
    for d in .claude .cursor; do [ -d "$FULL/$d" ] && echo "$d" >> "$STAGELIST"; done
    while IFS= read -r d; do
      [ -e "$FULL/$d" ] && echo "$d"
    done < "$SCOPE" >> "$STAGELIST"
    # shellcheck disable=SC2046
    ( cd "$FULL" && tar -cf - $(cat "$STAGELIST") ) | tar -x -C "$STAGE_DIR/tree"
    rm -rf "$FULL" "$SCOPE.tmp" "$NAMES" "$CF_LIST" "$STAGELIST"
  fi
elif [ "$MODE" = "patch" ]; then
  TREE_DIR="$(jqr '.tree_dir // empty')"
  PATCH="$TASK_DIR/$(jqr '.patch')"
  mkdir -p "$STAGE_DIR/tree"
  if [ -n "$TREE_DIR" ]; then
    cp -R "$TASK_DIR/$TREE_DIR/." "$STAGE_DIR/tree/"
  fi
  ( cd "$STAGE_DIR/tree" && git init -q && git add -A && git -c user.email=e@e -c user.name=eval commit -qm base \
    && git apply --index "$PATCH" )
  cp "$PATCH" "$STAGE_DIR/diff.patch"
  ( cd "$STAGE_DIR/tree" && git diff --cached --name-only ) > "$STAGE_DIR/changed-files.txt"
else
  echo "unknown mode: $MODE" >&2; exit 64
fi

echo "$STAGE_DIR"
