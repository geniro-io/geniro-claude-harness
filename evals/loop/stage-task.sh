#!/usr/bin/env bash
# Stage one benchmark task into a disposable working tree and materialize its diff.
#
#   stage-task.sh <task-dir> <stage-dir>
#
# Reads <task-dir>/task.json:
#   mode "git":   { "repo_alias", "base_sha", "head_sha" } -> worktree at head, diff base..head
#   mode "patch": { "fixture_cmd" | "tree_dir", "patch" }  -> copy tree, apply patch
#   mode "spec":  { "tree_dir" | ("repo_url"|"repo_alias")+"base_sha", "spec" }
#                                                          -> tree at base, no diff
#   mode "audit": { "tree_dir" | ("repo_url"|"repo_alias")+"base_sha" }
#                                                          -> tree at base, no diff,
#                                                             no artifact: the tree
#                                                             audits itself
# Writes: <stage-dir>/tree/ (the code under review), <stage-dir>/diff.patch,
#         <stage-dir>/changed-files.txt; in "spec" mode also <stage-dir>/spec.md
#         and no diff.patch (nothing changed — the spec is the artifact under test);
#         in "audit" mode <stage-dir>/surfaces.txt and neither diff nor artifact
#
# A task sourced from a PRIVATE repo never carries its location or name —
# "repo_alias" is an opaque label resolved through the machine-local, gitignored
# repos.local.json (see repos.local.example.json). A task sourced from a PUBLIC
# repo uses "repo_url" instead: the URL is not a secret, and committing it is
# what lets anyone else stage the task. Spec mode shallow-fetches that URL into
# cache/repos/ on first use. "repo_path" is accepted as a local-only escape
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

resolve_repo() { # <base-sha-or-empty> <what-this-mode-accepts> -> repo path on stdout
  # A PRIVATE task resolves through repo_alias + the gitignored repos.local.json;
  # a PUBLIC one commits repo_url, which is shallow-fetched at <base-sha>. Pass an
  # empty base from a mode that needs more than one commit present: a shallow
  # fetch of one sha cannot serve it, so repo_url is refused there rather than
  # failing later on a missing ref.
  local base="$1" accepts="$2" repo alias url cache
  repo="$(jqr '.repo_path // empty')"
  if [ -n "$repo" ]; then echo "$repo"; return 0; fi
  alias="$(jqr '.repo_alias // empty')"
  if [ -n "$alias" ]; then
    [ -f "$HERE/repos.local.json" ] || { echo "missing $HERE/repos.local.json — copy repos.local.example.json and map alias '$alias' to a local clone" >&2; exit 66; }
    repo="$(jq -r --arg a "$alias" '.[$a] // empty' "$HERE/repos.local.json")"
    [ -n "$repo" ] || { echo "alias '$alias' not mapped in $HERE/repos.local.json" >&2; exit 66; }
    echo "$repo"; return 0
  fi
  url="$(jqr '.repo_url // empty')"
  [ -n "$url" ] && [ -n "$base" ] || { echo "task.json needs $accepts" >&2; exit 64; }
  # Same cache root as adapter results — both are derived, disposable, and
  # regenerable, so they share one gitignore rule and one thing to delete for a
  # clean slate.
  cache="${LOOP_CACHE_DIR:-$HERE/cache}/repos/$(printf '%s' "$url" | shasum | cut -c1-16)"
  if ! git -C "$cache" cat-file -e "${base}^{commit}" 2>/dev/null; then
    mkdir -p "$cache"
    # Test for this directory's OWN .git, not `rev-parse --git-dir`: the cache
    # lives inside this repository, so rev-parse walks up and finds the plugin's
    # .git, skips init, and then fetches the task's commit from the plugin's
    # origin — "upload-pack: not our ref".
    [ -d "$cache/.git" ] || {
      git -C "$cache" init -q && git -C "$cache" remote add origin "$url"; }
    git -C "$cache" fetch -q --depth 1 origin "$base" \
      || { echo "cannot fetch $base from $url" >&2; exit 66; }
  fi
  echo "$cache"
}

if [ "$MODE" = "git" ]; then
  REPO="$(resolve_repo '' 'repo_alias (or local-only repo_path)')"
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
elif [ "$MODE" = "spec" ]; then
  # An artifact-under-test task: the tree is the code a spec makes claims ABOUT,
  # pinned at the commit the spec was written against, and the artifact is the
  # spec itself. There is no diff — nothing changed; the question is whether the
  # spec's claims hold against this tree. Pinning is what separates "the claim
  # was wrong" from "the tree moved on", which an unpinned run cannot tell apart.
  TREE_DIR="$(jqr '.tree_dir // empty')"
  SPEC_SRC="$TASK_DIR/$(jqr '.spec')"
  [ -f "$SPEC_SRC" ] || { echo "task.json .spec does not resolve: $SPEC_SRC" >&2; exit 66; }
  mkdir -p "$STAGE_DIR/tree"
  if [ -n "$TREE_DIR" ]; then
    cp -R "$TASK_DIR/$TREE_DIR/." "$STAGE_DIR/tree/"
  else
    BASE="$(jqr '.base_sha')"
    REPO="$(resolve_repo "$BASE" 'tree_dir, repo_url, repo_alias, or local-only repo_path')"
    git -C "$REPO" cat-file -e "${BASE}^{commit}" || { echo "base_sha absent in $REPO" >&2; exit 66; }
    git -C "$REPO" archive "$BASE" | tar -x -C "$STAGE_DIR/tree"
  fi
  cp "$SPEC_SRC" "$STAGE_DIR/spec.md"
  : > "$STAGE_DIR/changed-files.txt"
elif [ "$MODE" = "audit" ]; then
  # A repo-under-test task: no diff and no separate artifact — the tree's own
  # instruction, rule, and skill files are what the run audits, and the ground
  # truth is planted in them. surfaces.txt is the staged stand-in for the
  # skill's mechanical pre-pass: the file list a reviewer is handed instead of
  # rediscovering, so what the run measures is adjudication, not globbing.
  TREE_DIR="$(jqr '.tree_dir // empty')"
  mkdir -p "$STAGE_DIR/tree"
  if [ -n "$TREE_DIR" ]; then
    [ -d "$TASK_DIR/$TREE_DIR" ] || { echo "task.json .tree_dir does not resolve: $TASK_DIR/$TREE_DIR" >&2; exit 66; }
    cp -R "$TASK_DIR/$TREE_DIR/." "$STAGE_DIR/tree/"
  else
    BASE="$(jqr '.base_sha')"
    REPO="$(resolve_repo "$BASE" 'tree_dir, repo_url, repo_alias, or local-only repo_path')"
    git -C "$REPO" cat-file -e "${BASE}^{commit}" || { echo "base_sha absent in $REPO" >&2; exit 66; }
    git -C "$REPO" archive "$BASE" | tar -x -C "$STAGE_DIR/tree"
  fi
  ( cd "$STAGE_DIR/tree" && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) | while IFS= read -r f; do
    printf '%s\t%s words\n' "$f" "$(awk '{w+=NF} END {print w+0}' "$STAGE_DIR/tree/$f")"
  done > "$STAGE_DIR/surfaces.txt"
  : > "$STAGE_DIR/changed-files.txt"
else
  echo "unknown mode: $MODE" >&2; exit 64
fi

echo "$STAGE_DIR"
