#!/usr/bin/env bash
# Head-to-head: blast-radius recall for one symbol — grep vs codebase-memory-mcp.
#
# Establishes the grep ground truth (every file referencing the symbol, split by
# code vs docs), then — if codebase-memory-mcp is on PATH or passed via
# CMM_BIN — indexes the repo and asks the graph for the same callers, so the two
# can be compared on the same target.
#
# Usage:
#   blast-radius-benchmark.sh <repo_path> <symbol>
#   CMM_BIN=/path/to/codebase-memory-mcp blast-radius-benchmark.sh <repo> <symbol>
#
# Exit 0 always (a benchmark, not a gate). Requires: grep, jq (for the graph side).
set -uo pipefail

REPO="${1:?usage: blast-radius-benchmark.sh <repo_path> <symbol>}"
SYM="${2:?usage: blast-radius-benchmark.sh <repo_path> <symbol>}"
REPO="$(cd "$REPO" && pwd)"
BIN="${CMM_BIN:-$(command -v codebase-memory-mcp || true)}"

echo "=================================================================="
echo "Blast-radius head-to-head — symbol: $SYM"
echo "repo: $REPO"
echo "=================================================================="

# ---- GREP ground truth (exact string, one query each) -------------------
code_files=$(grep -rlI --include='*.ts' --include='*.tsx' --include='*.js' \
  --include='*.jsx' --include='*.py' --include='*.go' --include='*.rs' \
  --include='*.java' --include='*.rb' --include='*.php' --include='*.sh' \
  -- "$SYM" "$REPO" 2>/dev/null | sort -u | wc -l)
doc_files=$(grep -rlI --include='*.md' --include='*.mdx' --include='*.rst' \
  -- "$SYM" "$REPO" 2>/dev/null | sort -u | wc -l)
total_files=$(grep -rlI -- "$SYM" "$REPO" 2>/dev/null | sort -u | wc -l)
call_sites=$(grep -rhI -- "$SYM" "$REPO" 2>/dev/null | grep -c "$SYM")

echo ""
echo "--- GREP (exact, 1 query) ---"
echo "  files referencing symbol : $total_files  ($code_files code + $doc_files docs)"
echo "  total occurrences        : $call_sites"

# ---- GRAPH (codebase-memory-mcp) ----------------------------------------
echo ""
echo "--- GRAPH (codebase-memory-mcp) ---"
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
  echo "  (binary not found — set CMM_BIN or add to PATH; run install-codebase-memory.sh)"
  echo ""
  echo "Skipping graph side. Grep ground truth above stands."
  exit 0
fi

"$BIN" cli index_repository "{\"repo_path\":\"$REPO\"}" >/dev/null 2>&1
PROJ=$("$BIN" cli list_projects '{}' 2>/dev/null \
  | jq -r --arg r "$REPO" '.projects[]? | select(.root_path==$r) | .name' | head -1)
if [ -z "$PROJ" ]; then
  # Fall back to the most recently indexed project.
  PROJ=$("$BIN" cli list_projects '{}' 2>/dev/null | jq -r '.projects[-1].name' 2>/dev/null)
fi
echo "  project: $PROJ"

callers=$("$BIN" cli query_graph \
  "{\"project\":\"$PROJ\",\"query\":\"MATCH (c)-[:CALLS]->(f:Function {name:'$SYM'}) RETURN c.name, c.file\"}" \
  2>/dev/null | jq -r '.rows[]? | "    \(.[0])  \(.[1])"')
n_callers=$(printf '%s\n' "$callers" | grep -c . )
echo "  callers found (CALLS edges): $n_callers"
[ -n "$callers" ] && printf '%s\n' "$callers"

echo ""
echo "--- VERDICT ---"
echo "  grep: $total_files coupled files (100%, exact, 1 query)"
echo "  graph: $n_callers code callers; blind to the $doc_files doc references"
echo ""
echo "On a doc-heavy or shallow repo grep wins. On a large code-dense repo the"
echo "graph's transitive/relational reach is where it pays off — run this against"
echo "such a repo to see the inverse. Also run lib/repo-profile.sh for the verdict."
exit 0
