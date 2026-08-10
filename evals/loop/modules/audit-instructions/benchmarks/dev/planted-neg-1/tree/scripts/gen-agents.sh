#!/usr/bin/env bash
# Regenerate AGENTS.md from CLAUDE.md so tools reading either surface agree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
{
  echo "<!-- Generated from CLAUDE.md by scripts/gen-agents.sh — do not edit. -->"
  echo
  cat "$ROOT/CLAUDE.md"
} > "$ROOT/AGENTS.md"
