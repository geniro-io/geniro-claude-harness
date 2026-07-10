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

if git rev-parse --git-dir >/dev/null 2>&1; then
  # Tracked files only — skips node_modules, build output, and other ignored trees.
  # With path args, restrict to them; without, list the whole repo.
  mapfile -t files < <(git ls-files -- "${@:-.}" | grep '\.md$' | sort -u)
else
  mapfile -t files < <(find "${@:-.}" -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*' | sort)
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
