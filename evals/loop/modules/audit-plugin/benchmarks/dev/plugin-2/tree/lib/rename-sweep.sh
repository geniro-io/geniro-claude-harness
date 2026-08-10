#!/usr/bin/env bash
# Rewrite every reference to a renamed file across the repo.
set -euo pipefail

# sweep_rename <old-basename> <new-basename>
sweep_rename() {
  local old="$1" new="$2"
  grep -rl "$old" . --include='*.md' | while IFS= read -r f; do
    sed -i.bak "s|${old}|${new}|g" "$f"
    rm -f "$f.bak"
  done
}
