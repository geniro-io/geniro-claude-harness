#!/usr/bin/env bash
# build-cursor-agents.sh — regenerate cursor/agents/ from the canonical
# agents/*.md definitions.
#
# agents/*.md is the single source of truth (Claude Code frontmatter: name,
# description, tools, model, maxTurns). Cursor subagents understand a smaller
# frontmatter (name, description, model, readonly), so each agent gets a
# derived copy under cursor/agents/ with:
#   - tools/maxTurns dropped (not enforceable in Cursor)
#   - model mapped from the source tier by cursor_model_for() below
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

# Tier mapping, Claude Code -> Cursor. The two runtimes name models differently
# and Cursor's roster changes constantly (193 ids as of 2026-08), so nothing here
# names a model: the mapping is between INTENTS.
#
#   inherit (or unset) -> inherit
#       Judgment-grade spawns. `model-tiering.md` §The rule keeps these on the
#       tier the USER chose; Cursor's `inherit` means exactly that.
#
#   any concrete tier  -> auto
#       The mechanical carve-outs (`model-tiering.md` category 3 — currently
#       knowledge-retrieval-agent and test-runner-agent, which declare a cheaper
#       tier in their own frontmatter). `auto` is Cursor's built-in selector,
#       the first entry in `cursor-agent --list-models` and its documented
#       default: a server-side classifier picks the model per task. That is the
#       closest honest expression of "this workload is mechanical, spend
#       accordingly" WITHOUT pinning a model id — which is what we want, since a
#       pinned id rots with Cursor's roster and, when it is unavailable or
#       blocked by a team policy, Cursor silently falls back to something else.
#
# Note `auto` is "Cursor decides", not "always cheaper": a session already
# running a cheap model could see `auto` pick something dearer. It is the right
# semantic for a mechanical agent regardless — the point is that the tier stops
# being the user's reasoning-grade choice.
cursor_model_for() {
  case "${1:-}" in
    ""|inherit) echo "inherit" ;;
    *)          echo "auto" ;;
  esac
}

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
  description_line="$(awk '/^---$/{c++; next} c==1 && /^description:/' "$src")"
  if [ -z "$description_line" ]; then
    echo "ERROR: no description in $src frontmatter" >&2
    exit 1
  fi
  body="$(awk '/^---$/{c++; next} c>=2' "$src")"
  declared_model="$(awk '/^---$/{c++; next} c==1 && /^model:[[:space:]]*/ {sub(/^model:[[:space:]]*/,""); gsub(/[[:space:]"'"'"']/,""); print; exit}' "$src")"

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf '%s\n' "$description_line"
    printf 'model: %s\n' "$(cursor_model_for "$declared_model")"
    printf 'readonly: %s\n' "$(readonly_for "$name")"
    printf -- '---\n'
    printf '<!-- Generated from agents/%s by scripts/build-cursor-agents.sh. Edit the source and re-run; do not edit this copy. -->\n\n' "$base"
    printf '> Runtime note: `${CLAUDE_PLUGIN_ROOT}` below means the plugin root — the ancestor directory of this file containing `.claude-plugin/plugin.json`. Resolve it and export it as `CLAUDE_PLUGIN_ROOT` before sourcing any `lib/*.sh` helper.\n'
    printf '%s\n' "$body"
  } > "$OUT_DIR/$base"
done

echo "generated $(ls "$OUT_DIR"/*.md | wc -l | tr -d ' ') agents into $OUT_DIR" >&2
