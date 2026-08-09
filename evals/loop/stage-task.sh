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
  # A plain archive extract, not a linked worktree: the reviewed tree must not
  # register in the source repo's worktree list (no cleanup coupling, no lock risk).
  mkdir -p "$STAGE_DIR/tree"
  git -C "$REPO" archive "$HEAD" | tar -x -C "$STAGE_DIR/tree"
  git -C "$REPO" diff "$BASE" "$HEAD" > "$STAGE_DIR/diff.patch"
  git -C "$REPO" diff --name-only "$BASE" "$HEAD" > "$STAGE_DIR/changed-files.txt"
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
