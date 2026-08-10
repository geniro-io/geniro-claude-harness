#!/usr/bin/env bash
# build-cursor-agents.sh — regenerate cursor/agents/ from the canonical
# agents/*.md definitions.
#
# agents/*.md is the single source of truth (Claude Code frontmatter: name,
# description, tools, model, maxTurns). Cursor subagents understand a smaller
# frontmatter (name, description, model, readonly), so each agent gets a
# derived copy under cursor/agents/ with:
#   - tools/maxTurns dropped (not enforceable in Cursor)
#   - model forced to `inherit` ("sonnet" is not a Cursor model id)
#   - readonly set from the agent's documented write contract below
#   - the body copied verbatim, prefixed with a generated-file marker and a
#     plugin-root resolution note (the bodies cite ${CLAUDE_PLUGIN_ROOT})
#
# Run after any edit to agents/*.md and commit the output;
# tests/cursor/build-agents-fresh.sh fails CI when the copies drift.
#
# Usage: scripts/build-cursor-agents.sh [output-dir]   (default: cursor/agents)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/cursor/agents}"
mkdir -p "$OUT_DIR"

# Write contract per agent: readonly=true for agents that never modify files.
readonly_for() {
  case "$1" in
    adversarial-tester-agent|test-runner-agent) echo "false" ;; # author tests / execute the suite
    *) echo "true" ;;
  esac
}

for src in "$REPO_ROOT"/agents/*.md; do
  base="$(basename "$src")"
  name="${base%.md}"

  # agents/<name>-reference.md files are body companions of an agent (per
  # .claude/rules/skill-structure.md §File-size limits), not agents themselves:
  # they carry no frontmatter and nothing spawns them. The agent body cites them
  # via ${CLAUDE_PLUGIN_ROOT}, which resolves in both runtimes, so they are not
  # packaged as Cursor subagents.
  case "$name" in *-reference) continue ;; esac

  # Frontmatter = lines between the first two --- fences; body = the rest.
  # `c<2 &&` bounds the fence match to those first two lines only — without it,
  # `next` fires on EVERY line equal to `---` (a body-level horizontal rule, or
  # a `---` inside a fenced code block/heredoc), silently deleting each one
  # from the extracted text.
  description_line="$(awk 'c<2 && /^---$/{c++; next} c==1 && /^description:/' "$src")"
  if [ -z "$description_line" ]; then
    echo "ERROR: no description in $src frontmatter" >&2
    exit 1
  fi
  body="$(awk 'c<2 && /^---$/{c++; next} c>=2' "$src")"

  # Content-integrity guard: a regression in the fence-consumption awk above
  # would corrupt every body-level "---" identically on both sides of the
  # freshness diff — the freshly regenerated copy and an already-corrupted
  # committed copy would match each other, so tests/cursor/build-agents-fresh.sh
  # alone cannot catch it. Assert directly against the source instead: every
  # "---" beyond the frontmatter's own two fences must survive into the body.
  src_fences=$(awk '/^---$/{n++} END{print n+0}' "$src")
  body_fences=$(printf '%s\n' "$body" | awk '/^---$/{n++} END{print n+0}')
  if [ "$body_fences" -ne "$((src_fences - 2))" ]; then
    echo "ERROR: $src has $src_fences '---' line(s); expected $((src_fences - 2)) to survive into the body (2 consumed as frontmatter fences), but found $body_fences. The fence-extraction awk ate one — refusing to write a corrupted $base." >&2
    exit 1
  fi

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf '%s\n' "$description_line"
    printf 'model: inherit\n'
    printf 'readonly: %s\n' "$(readonly_for "$name")"
    printf -- '---\n'
    printf '<!-- Generated from agents/%s by scripts/build-cursor-agents.sh. Edit the source and re-run; do not edit this copy. -->\n\n' "$base"
    printf '> Runtime note: `${CLAUDE_PLUGIN_ROOT}` below means the plugin root — the ancestor directory of this file containing `.claude-plugin/plugin.json`. Resolve it and export it as `CLAUDE_PLUGIN_ROOT` before sourcing any `lib/*.sh` helper.\n'
    printf '%s\n' "$body"
  } > "$OUT_DIR/$base"
done

echo "generated $(ls "$OUT_DIR"/*.md | wc -l | tr -d ' ') agents into $OUT_DIR" >&2
