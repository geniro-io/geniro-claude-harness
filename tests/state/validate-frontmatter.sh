#!/usr/bin/env bash
# Smoke test for skills/_shared/validate-state-file.sh
#
# Run: bash tests/state/validate-frontmatter.sh
# Exits non-zero on any failure.
#
# Plugin-developer tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/skills/_shared/validate-state-file.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "PASS: $1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "FAIL: $1" >&2
}

# Helper to run validator and capture exit code without aborting set -e
expect_rc() {
  local target="$1" expected="$2" label="$3"
  set +e
  validate_state_file "$target" 2>/dev/null
  local rc=$?
  set -e
  if [ "$rc" -eq "$expected" ]; then
    pass "$label (rc=$rc)"
  else
    fail "$label — expected rc=$expected, got rc=$rc"
  fi
}

# ---------------------------------------------------------------------------
# Happy paths — one per tier
# ---------------------------------------------------------------------------

# Test 1: valid T1 task-bound
cat > "$TMPDIR/t1-task.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: feature/dark-mode
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---

## Body
content
EOF
expect_rc "$TMPDIR/t1-task.md" 0 "valid T1"

# Test 2: valid T2 handoff
cat > "$TMPDIR/t2.md" <<'EOF'
---
tier: T2
producer: debug
schema-version: 1
branch: fix/null-ptr
timestamp: 2026-05-19T14:30:00Z
consumer: implement
---

## Findings
content
EOF
expect_rc "$TMPDIR/t2.md" 0 "valid T2"

# Test 3: valid T3 CRUD
cat > "$TMPDIR/t3-crud.md" <<'EOF'
---
tier: T3
producer: user
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
concurrency: crud
description: Test instruction file
---

Rules content
EOF
expect_rc "$TMPDIR/t3-crud.md" 0 "valid T3 CRUD"

# Test 4: valid T3 append-only sidecar
cat > "$TMPDIR/t3-append.meta.yaml" <<'EOF'
---
tier: T3
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
concurrency: append-only
schema-ref: "M2 §5.1"
---
EOF
expect_rc "$TMPDIR/t3-append.meta.yaml" 0 "valid T3 append-only sidecar"

# ---------------------------------------------------------------------------
# Failure paths — one per exit code
# ---------------------------------------------------------------------------

# Test 5: missing file → 1
expect_rc "$TMPDIR/nonexistent.md" 1 "missing file"

# Test 6: no frontmatter (line 1 != ---) → 2
cat > "$TMPDIR/no-fm.md" <<'EOF'
just a body
no frontmatter at all
EOF
expect_rc "$TMPDIR/no-fm.md" 2 "no frontmatter"

# Test 7: unclosed frontmatter → 3
cat > "$TMPDIR/unclosed.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
EOF
expect_rc "$TMPDIR/unclosed.md" 3 "unclosed frontmatter"

# Test 8: missing common-base field (no tier:) → 4
cat > "$TMPDIR/no-tier.md" <<'EOF'
---
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---
EOF
expect_rc "$TMPDIR/no-tier.md" 4 "missing common-base field 'tier'"

# Test 9: missing T1 tier-specific (no phase:) → 5
cat > "$TMPDIR/t1-no-phase.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
status: in-progress
non-resumable-actions: []
---
EOF
expect_rc "$TMPDIR/t1-no-phase.md" 5 "missing T1-specific field 'phase'"

# Test 10: missing T2 tier-specific (no consumer:) → 5
cat > "$TMPDIR/t2-no-consumer.md" <<'EOF'
---
tier: T2
producer: debug
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
---
EOF
expect_rc "$TMPDIR/t2-no-consumer.md" 5 "missing T2-specific field 'consumer'"

# Test 11: missing T3 tier-specific (no concurrency:) → 5
cat > "$TMPDIR/t3-no-concurrency.md" <<'EOF'
---
tier: T3
producer: user
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
---
EOF
expect_rc "$TMPDIR/t3-no-concurrency.md" 5 "missing T3-specific field 'concurrency'"

# Test 12: schema-version mismatch → 6
cat > "$TMPDIR/sv-mismatch.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 99
branch: main
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---
EOF
expect_rc "$TMPDIR/sv-mismatch.md" 6 "schema-version mismatch"

# Test 13: invalid tier value → 9
cat > "$TMPDIR/bad-tier.md" <<'EOF'
---
tier: T4
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
---
EOF
expect_rc "$TMPDIR/bad-tier.md" 9 "invalid tier value 'T4'"

# Test 14: optional fields don't break validation
cat > "$TMPDIR/with-options.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
description: optional description
tags: [tag-a, tag-b]
notes: free-form notes
geniro_kind: design-doc
---
EOF
expect_rc "$TMPDIR/with-options.md" 0 "optional fields don't break validation"

# Test 15: checksum mismatch → 7
{
  cat <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
checksum: deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
---
EOF
  echo
  echo "actual body content"
} > "$TMPDIR/cksum-bad.md"
expect_rc "$TMPDIR/cksum-bad.md" 7 "checksum mismatch"

# Test 16: worktree path that doesn't exist (inside a real git repo) → 8
cat > "$TMPDIR/bogus-worktree.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
worktree: /nonexistent/worktree/path
---
EOF
# Run from inside the repo so the worktree check fires.
pushd "$REPO_ROOT" >/dev/null
expect_rc "$TMPDIR/bogus-worktree.md" 8 "bogus worktree path (inside git repo)"
popd >/dev/null

# Test 17: caller error — no target path → 64
set +e
validate_state_file "" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "no target path returns 64"
else
  fail "no target path — expected rc=64, got rc=$rc"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
