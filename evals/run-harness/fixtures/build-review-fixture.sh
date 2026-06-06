#!/usr/bin/env bash
# Build a throwaway git repo with a planted-issue diff for the Phase-0 /review trial.
#
# The diff is engineered to surface, in one /review pass:
#   - a CLEAR security bug (SQL injection via string interpolation) -> CRITICAL/HIGH,
#     which drives the Phase-6 Action gate toward "/geniro:implement (Recommended)";
#   - an AMBIGUOUS behavior change (dropped input validation + changed not-found
#     contract null->undefined) -> a likely PRODUCT-DECISION ("is this intended?");
#   - a NEW destructive op with no authorization (hard deleteUser) -> a likely
#     open_question ("should this require auth / be a soft-delete?").
#
# Prints the repo path on the LAST stdout line. The base branch is `main`; the planted
# changes live on `fixture/planted-01`, so review the range `main..HEAD`.
set -euo pipefail

REPO="$(mktemp -d "${TMPDIR:-/tmp}/geniro-review-fixture-XXXXXX")"
cd "$REPO"
git init -q -b main
git config user.email eval@geniro.local
git config user.name geniro-eval
mkdir -p src

cat > src/db.js <<'EOF'
// Minimal stand-in data layer. query(sql, params) runs a parameterized query.
module.exports = {
  query: async (_sql, _params) => [],
};
EOF

cat > src/users.js <<'EOF'
const db = require('./db');

/**
 * Look up a user by numeric id.
 * @returns {Promise<object|null>} the user row, or null when not found.
 */
async function getUser(id) {
  if (!Number.isInteger(id)) {
    throw new Error('id must be an integer');
  }
  const rows = await db.query('SELECT * FROM users WHERE id = $1', [id]);
  return rows[0] ?? null;
}

module.exports = { getUser };
EOF

git add -A
git commit -q -m "base: getUser with id validation and null-safe not-found contract"

git checkout -q -b fixture/planted-01

cat > src/users.js <<'EOF'
const db = require('./db');

/**
 * Look up a user by id.
 */
async function getUser(id) {
  const rows = await db.query(`SELECT * FROM users WHERE id = ${id}`);
  return rows[0];
}

/**
 * Permanently delete a user by id.
 */
async function deleteUser(id) {
  await db.query(`DELETE FROM users WHERE id = ${id}`);
  return true;
}

module.exports = { getUser, deleteUser };
EOF

git add -A
git commit -q -m "feat: add deleteUser; simplify getUser query"

echo "$REPO"
