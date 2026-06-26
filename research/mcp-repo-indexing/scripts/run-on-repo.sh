#!/usr/bin/env bash
# Orchestrator: profile a repo with the shipped detector, then run the
# blast-radius head-to-head for a symbol.
#
# Usage:
#   run-on-repo.sh <repo_path> [symbol]
#   CMM_BIN=/path/to/codebase-memory-mcp run-on-repo.sh <repo_path> [symbol]
#
# If no symbol is given, picks a frequently-referenced identifier heuristically.
set -uo pipefail

REPO="${1:?usage: run-on-repo.sh <repo_path> [symbol]}"
SYM="${2:-}"
REPO="$(cd "$REPO" && pwd)"

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# scripts/ -> mcp-repo-indexing/ -> research/ -> repo root
PLUGIN_ROOT="$(cd "$SELF_DIR/../../.." && pwd)"
PROFILE="$PLUGIN_ROOT/lib/repo-profile.sh"

echo "##################################################################"
echo "# 1. Repo profile (decides whether a graph MCP pays off)"
echo "##################################################################"
if [ -x "$PROFILE" ] || [ -f "$PROFILE" ]; then
  bash "$PROFILE" --root "$REPO"
else
  echo "(repo-profile.sh not found at $PROFILE)"
fi

echo ""
echo "##################################################################"
echo "# 2. Blast-radius head-to-head"
echo "##################################################################"
if [ -z "$SYM" ]; then
  # Heuristic: the most frequently referenced exported-looking identifier.
  SYM=$(grep -rhoIE '\b[A-Za-z_][A-Za-z0-9_]{4,}\b' "$REPO" 2>/dev/null \
    | sort | uniq -c | sort -rn \
    | awk '$2 !~ /^(const|function|return|import|export|class|require|module)$/ {print $2; exit}')
  echo "(no symbol given — auto-picked: $SYM)"
fi
bash "$SELF_DIR/blast-radius-benchmark.sh" "$REPO" "$SYM"
