#!/usr/bin/env bash
# Install the codebase-memory-mcp binary to a local directory (no sudo, no PATH
# changes). Single static binary, ~266 MB, MIT.
#
# Usage:
#   install-codebase-memory.sh [install_dir]   # default: ./.cmm-bin
#
# Then either add <install_dir> to PATH, or pass it through to the other scripts.
set -euo pipefail

DIR="${1:-$PWD/.cmm-bin}"
mkdir -p "$DIR"

echo "Installing codebase-memory-mcp into: $DIR"
# The upstream installer downloads a checksum-verified release binary over HTTPS
# and wraps execution in main() so a truncated pipe never runs partially.
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh \
  | bash -s -- --dir="$DIR" --skip-config

BIN="$DIR/codebase-memory-mcp"
if [ -x "$BIN" ]; then
  echo "OK: $("$BIN" --version 2>&1 | tail -1)"
  echo "Binary: $BIN"
else
  echo "Install failed — $BIN not executable" >&2
  exit 1
fi
