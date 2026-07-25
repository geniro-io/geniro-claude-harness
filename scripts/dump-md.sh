#!/usr/bin/env bash
# dump-md.sh — print every Markdown file (filename header, then full content).
#
# Full-content alternative to grep when surveying or editing skills: grep shows
# matching lines only, which misses reworded coverage and surrounding context;
# this prints whole files so nothing is skipped.
#
# Usage:
#   scripts/dump-md.sh                    # all git-tracked *.md files in the repo
#   scripts/dump-md.sh skills/plan        # only files under the given paths
#   scripts/dump-md.sh skills lib/README.md
#
# Output per file:
#   ===== <path> =====
#   <full content>
#   (blank line)
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

# Collected with a read loop rather than `mapfile`, which does not exist in bash
# 3.2 — the macOS system shell. CLAUDE.md makes this script the mandated way to
# read plugin content before editing a skill, so a newer bash cannot be assumed
# on PATH: under /bin/bash the mapfile form aborted with rc=127.
files=()
if git rev-parse --git-dir >/dev/null 2>&1; then
  # Tracked files only — skips node_modules, build output, and other ignored trees.
  # With path args, restrict to them; without, list the whole repo.
  while IFS= read -r _dm_f; do
    [ -n "$_dm_f" ] && files+=("$_dm_f")
  done < <(git ls-files -- "${@:-.}" | grep '\.md$' | sort -u)
else
  while IFS= read -r _dm_f; do
    [ -n "$_dm_f" ] && files+=("$_dm_f")
  done < <(find "${@:-.}" -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*' | sort)
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "dump-md.sh: no .md files found for: ${*:-<repo>}" >&2
  exit 1
fi

for f in "${files[@]}"; do
  printf '===== %s =====\n' "$f"
  cat "$f"
  printf '\n'
done
