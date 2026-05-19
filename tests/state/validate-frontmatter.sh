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

# Test 15b: positive checksum — body contains markdown `---` horizontal rule.
# Regression test for the body-extractor bug where any `---` rule in the body
# advanced the fence counter past 2, silently dropping content after it.
# Steps: build body, compute sha256, write file with that checksum, validate.
body_15b=$'\n## Section A\nFirst part.\n\n---\n\n## Section B\nAfter the rule.\n'
cksum_15b=$(printf '%s' "$body_15b" | sha256sum | awk '{print $1}')
{
  cat <<EOF
---
tier: T1
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
checksum: $cksum_15b
---
EOF
  printf '%s' "$body_15b"
} > "$TMPDIR/cksum-good.md"
expect_rc "$TMPDIR/cksum-good.md" 0 "positive checksum — body with markdown --- rule preserved"

# Test 15c: trailing whitespace on tier value passes (regression).
# Regression test for `tier: T1 ` (trailing space) yielding rc=9 'invalid tier value T1 '.
cat > "$TMPDIR/trailing-ws.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---
EOF
expect_rc "$TMPDIR/trailing-ws.md" 0 "trailing whitespace on tier value tolerated"

# Test 15d: empty required-field value rejected.
# Regression test — previously key-presence alone passed, so `branch:` (empty
# value) yielded rc=0 instead of rc=4.
cat > "$TMPDIR/empty-branch.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch:
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
---
EOF
expect_rc "$TMPDIR/empty-branch.md" 4 "empty 'branch:' value rejected as missing base field"

# Test 15e: positive checksum — body has NO trailing newline.
# Regression test for the awk-print body extractor that always appended `\n`,
# causing false-positive checksum-mismatch for byte-exact producers
# (e.g., `printf '%s'`, Python, jq pipelines).
body_15e="one line no terminator"
cksum_15e=$(printf '%s' "$body_15e" | sha256sum | awk '{print $1}')
{
  cat <<EOF
---
tier: T1
producer: implement
schema-version: 1
branch: main
timestamp: 2026-05-19T14:30:00Z
phase: implement
status: in-progress
non-resumable-actions: []
checksum: $cksum_15e
---
EOF
  printf '%s' "$body_15e"
} > "$TMPDIR/cksum-no-trailing-nl.md"
expect_rc "$TMPDIR/cksum-no-trailing-nl.md" 0 "positive checksum — body without trailing newline (byte-exact)"

# Test 15f: balanced quote-strip preserves embedded apostrophes (unit test).
# Regression test — old `gsub(/^["']+|["']+$/, "")` was greedy and would
# turn `"im'plement'"` into `im'plement` (stripping the trailing apos
# along with the outer quote). New balanced-pair logic keeps inner quotes.
set +e
fm_in=$'producer: "im\047plement\047"\n'
val=$(_vsf_fm_get_value "$fm_in" producer)
set -e
if [ "$val" = "im'plement'" ]; then
  pass "balanced quote-strip preserves embedded apostrophes (got: '$val')"
else
  fail "balanced quote-strip mangled value (got: '$val', want: \"im'plement'\")"
fi

# Test 15g: single-quoted value strips one outer pair only.
set +e
fm_in=$'producer: \047refactor\047\n'
val=$(_vsf_fm_get_value "$fm_in" producer)
set -e
if [ "$val" = "refactor" ]; then
  pass "single-quoted scalar strips one outer pair (got: '$val')"
else
  fail "single-quote strip wrong (got: '$val', want: 'refactor')"
fi

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
