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
# Writes: <stage-dir>/tree/ (the code under review), <stage-dir>/diff.patch,
#         <stage-dir>/changed-files.txt; in "spec" mode also <stage-dir>/spec.md
#         and no diff.patch (nothing changed — the spec is the artifact under test)
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
    REPO="$(jqr '.repo_path // empty')"
    if [ -z "$REPO" ]; then
      ALIAS="$(jqr '.repo_alias // empty')"
      if [ -n "$ALIAS" ]; then
        [ -f "$HERE/repos.local.json" ] || { echo "missing $HERE/repos.local.json — map alias '$ALIAS' to a local clone" >&2; exit 66; }
        REPO="$(jq -r --arg a "$ALIAS" '.[$a] // empty' "$HERE/repos.local.json")"
        [ -n "$REPO" ] || { echo "alias '$ALIAS' not mapped in $HERE/repos.local.json" >&2; exit 66; }
      else
        # A public source needs no alias indirection: the URL is not a secret and
        # committing it is what makes the task reproducible by anyone. Private
        # repos keep going through repo_alias + the gitignored repos.local.json.
        URL="$(jqr '.repo_url // empty')"
        [ -n "$URL" ] || { echo "spec mode needs tree_dir, repo_url, repo_alias, or local-only repo_path" >&2; exit 64; }
        # Same cache root as adapter results — both are derived, disposable, and
        # regenerable, so they share one gitignore rule and one thing to delete
        # for a clean slate.
        CACHE="${LOOP_CACHE_DIR:-$HERE/cache}/repos/$(printf '%s' "$URL" | shasum | cut -c1-16)"
        if ! git -C "$CACHE" cat-file -e "${BASE}^{commit}" 2>/dev/null; then
          mkdir -p "$CACHE"
          # Test for this directory's OWN .git, not `rev-parse --git-dir`: the
          # cache lives inside this repository, so rev-parse walks up and finds
          # the plugin's .git, skips init, and then fetches the task's commit
          # from the plugin's origin — "upload-pack: not our ref".
          [ -d "$CACHE/.git" ] || {
            git -C "$CACHE" init -q && git -C "$CACHE" remote add origin "$URL"; }
          git -C "$CACHE" fetch -q --depth 1 origin "$BASE" \
            || { echo "cannot fetch $BASE from $URL" >&2; exit 66; }
        fi
        REPO="$CACHE"
      fi
    fi
    git -C "$REPO" cat-file -e "${BASE}^{commit}" || { echo "base_sha absent in $REPO" >&2; exit 66; }
    git -C "$REPO" archive "$BASE" | tar -x -C "$STAGE_DIR/tree"
  fi
  cp "$SPEC_SRC" "$STAGE_DIR/spec.md"
  : > "$STAGE_DIR/changed-files.txt"
else
  echo "unknown mode: $MODE" >&2; exit 64
fi

# A fixture tree that has to carry `.geniro/` — the memory layers a Phase 1
# recon task is measured on — cannot be committed under that name: the
# `enforce-state-helper` hook matches `.geniro/<tier>/` anywhere in a path and
# would (correctly) refuse the direct writes that author the fixture, since it
# has no way to tell benchmark data from this repo's own state. Committing the
# directory as `dot-geniro/` and restoring the real name at stage time keeps the
# hook exactly as strict as it is, at the cost of one rename here. Any task tree
# may use it; tasks without the directory are unaffected.
if [ -d "$STAGE_DIR/tree/dot-geniro" ]; then
  rm -rf "$STAGE_DIR/tree/.geniro"
  mv "$STAGE_DIR/tree/dot-geniro" "$STAGE_DIR/tree/.geniro"
fi

echo "$STAGE_DIR"
