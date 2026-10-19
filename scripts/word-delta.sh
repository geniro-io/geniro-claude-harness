#!/usr/bin/env bash
# word-delta.sh — net word change of the plugin's instruction prose against a base ref.
#
#   scripts/word-delta.sh [base-ref]      (default: the merge-base with origin/main)
#
# Counts words (awk NF — the repo's one counting rule) in every .md file under
# skills/, agents/, .claude/skills/, .claude/rules/ and CLAUDE.md, at the base ref
# and in the working tree, and prints each changed file plus the total. Exits 1
# when the total grew, so a pass that must end net <= 0 can gate on it.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

base="${1:-}"
if [ -z "$base" ]; then
  base="$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)"
fi
if [ -z "$base" ] || ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  echo "word-delta: cannot resolve a base ref (pass one explicitly)" >&2
  exit 2
fi

_words() { awk '{ w += NF } END { print w + 0 }'; }

total=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  before=$(git show "$base:$f" 2>/dev/null | _words)
  after=0
  [ -f "$f" ] && after=$(_words < "$f")
  d=$((after - before))
  [ "$d" -eq 0 ] && continue
  printf '%+6d  %6d -> %6d  %s\n' "$d" "$before" "$after" "$f"
  total=$((total + d))
done < <(
  { git diff --name-only "$base" -- skills agents .claude/skills .claude/rules CLAUDE.md
    git ls-files --others --exclude-standard -- skills agents .claude/skills .claude/rules
  } | grep -E '(\.md$|^CLAUDE\.md$)' | sort -u
)

printf '%+6d  total instruction words vs %s\n' "$total" "$(git rev-parse --short "$base")"
[ "$total" -le 0 ]
