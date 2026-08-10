#!/usr/bin/env bash
# Regenerate AGENTS.md from CLAUDE.md. Run after every CLAUDE.md edit.
set -euo pipefail
cd "$(dirname "$0")/.."
{
  echo "<!-- generated from CLAUDE.md by scripts/gen-agents.sh — do not edit -->"
  echo
  cat CLAUDE.md
} > AGENTS.md
