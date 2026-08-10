#!/usr/bin/env bash
# Regenerate src/generated/ from proto/. Hand edits there are overwritten.
set -euo pipefail
cargo build
