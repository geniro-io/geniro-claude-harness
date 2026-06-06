#!/usr/bin/env bash
# Build a small REALISTIC target repo for the Phase-0 /plan trial.
#
# Why realistic (not an empty temp dir): with an empty target the model has nothing
# to plan against and wanders into CLAUDE_PLUGIN_ROOT, planning against the plugin
# source instead (Phase-0 finding). A self-contained mini-project gives the task an
# obvious home so the spec lands in THIS repo's .geniro/planning.
#
# Prints the repo path on the LAST stdout line. Base branch: main.
set -euo pipefail

REPO="$(mktemp -d "${TMPDIR:-/tmp}/geniro-plan-fixture-XXXXXX")"
cd "$REPO"
git init -q -b main
git config user.email eval@geniro.local
git config user.name geniro-eval

cat > package.json <<'EOF'
{
  "name": "mathlib",
  "version": "1.0.0",
  "description": "Tiny arithmetic utility library.",
  "main": "src/math.js",
  "scripts": { "test": "node --test" }
}
EOF

mkdir -p src test

cat > src/math.js <<'EOF'
// Tiny arithmetic helpers. Each takes two finite numbers and returns a number.
function add(a, b) {
  return a + b;
}

function subtract(a, b) {
  return a - b;
}

module.exports = { add, subtract };
EOF

cat > test/math.test.js <<'EOF'
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { add, subtract } = require('../src/math');

test('add sums two numbers', () => {
  assert.equal(add(2, 3), 5);
});

test('subtract subtracts two numbers', () => {
  assert.equal(subtract(5, 3), 2);
});
EOF

cat > README.md <<'EOF'
# mathlib

A tiny arithmetic utility library exposing `add` and `subtract` from `src/math.js`,
with unit tests under `test/` run via `node --test`.
EOF

git add -A
git commit -q -m "mathlib: add and subtract helpers with tests"

echo "$REPO"
