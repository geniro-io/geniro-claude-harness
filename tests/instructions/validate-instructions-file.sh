#!/usr/bin/env bash
# Suite for lib/validate-instructions-file.sh — the decidable /geniro:instructions
# `validate` lint checks.
#
# Run: bash tests/instructions/validate-instructions-file.sh
# Exits non-zero on any failure.
#
# Every blocking/warning check gets a paired control: one fixture that must
# fail it (red) and one otherwise-identical fixture that must pass (green), so
# a check that silently stops firing cannot look green on its own.
#
# Plugin-developer tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/validate-instructions-file.sh"

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

# Double-source under `set -e` must not abort on readonly re-assignment.
resrc=$( (set -e
          source "$REPO_ROOT/lib/validate-instructions-file.sh"
          source "$REPO_ROOT/lib/validate-instructions-file.sh"
          echo RESOURCE_OK) 2>&1 )
if printf '%s' "$resrc" | grep -q RESOURCE_OK; then
  pass "double-source is idempotent (no readonly crash under set -e)"
else
  fail "double-source crashed: $resrc"
fi

# Runs the validator, capturing rows and rc without tripping the harness.
run_validator() {
  VIF_OUT="$(validate_instructions_file "$@" 2>/dev/null)"
  VIF_RC=$?
}

expect_clean() {
  local label="$1"; shift
  run_validator "$@"
  if [ "$VIF_RC" -eq 0 ] && [ -z "$VIF_OUT" ]; then
    pass "$label (rc=0, no rows)"
  else
    fail "$label — expected rc=0 with no rows, got rc=$VIF_RC rows: $VIF_OUT"
  fi
}

# Asserts the named check fired at the named severity and that the exit code
# matches the severity class (CRITICAL/HIGH blocking, MEDIUM/LOW warn).
expect_check() {
  local check="$1" severity="$2" label="$3"; shift 3
  local want_rc=2
  case "$severity" in MEDIUM|LOW) want_rc=1 ;; esac
  run_validator "$@"
  if ! printf '%s\n' "$VIF_OUT" | grep -q "^$severity	$check	"; then
    fail "$label — no '$severity $check' row; got: $VIF_OUT"
    return
  fi
  if [ "$VIF_RC" -ne "$want_rc" ]; then
    fail "$label — expected rc=$want_rc, got rc=$VIF_RC"
    return
  fi
  pass "$label (rc=$VIF_RC, $severity $check)"
}

# ---------------------------------------------------------------------------
# Usage / reachability codes — distinct from a bad file
# ---------------------------------------------------------------------------

validate_instructions_file >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 64 ]; then
  pass "no argument returns rc=64 (usage), not a content verdict"
else
  fail "no argument — expected rc=64, got rc=$rc"
fi

validate_instructions_file "$TMPDIR/does-not-exist.md" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 65 ]; then
  pass "missing target returns rc=65 (unreadable), not a content verdict"
else
  fail "missing target — expected rc=65, got rc=$rc"
fi

# ---------------------------------------------------------------------------
# Happy path — the control every mutation below is measured against
# ---------------------------------------------------------------------------

good="$TMPDIR/global.md"
cat > "$good" <<'EOF'
# Custom Instructions

## Rules

- Run the project's own lint before committing.

## Constraints

- Maximum 500 lines changed per PR.
EOF
expect_clean "a well-formed global.md passes every check" "$good" global

# ---------------------------------------------------------------------------
# Check — `## Rules` heading present
# ---------------------------------------------------------------------------

no_rules="$TMPDIR/no-rules.md"
cat > "$no_rules" <<'EOF'
# Custom Instructions

## Constraints

- Maximum 500 lines changed per PR.
EOF
expect_check rules-heading-present HIGH "a missing '## Rules' heading is HIGH" "$no_rules" global

# ---------------------------------------------------------------------------
# Check — `## Constraints` heading present
# ---------------------------------------------------------------------------

no_constraints="$TMPDIR/no-constraints.md"
cat > "$no_constraints" <<'EOF'
# Custom Instructions

## Rules

- Run the project's own lint before committing.
EOF
expect_check constraints-heading-present HIGH "a missing '## Constraints' heading is HIGH" "$no_constraints" global

# Control: memory.md and review-extra/<slug>.md carry neither heading by
# design — the scope skip must not misfire on them.
memory_file="$TMPDIR/memory.md"
cat > "$memory_file" <<'EOF'
# Memory

## Memory Backend

- layer: learnings
EOF
expect_clean "memory.md scope skips the Rules/Constraints heading checks" "$memory_file" memory

mkdir -p "$TMPDIR/review-extra"
re_file="$TMPDIR/review-extra/sql-bindings.md"
cat > "$re_file" <<'EOF'
---
slug: sql-bindings
description: All SQL queries use parameterized bindings, never string concatenation
---

# Criteria

What to flag:
- String concatenation building a SQL string with a runtime variable.
EOF
expect_clean "review-extra/<slug>.md scope skips the Rules/Constraints heading checks" "$re_file" review-extra

# Scope auto-detect: parent-dir "review-extra" wins even with no explicit arg.
expect_clean "scope auto-detects to review-extra from the parent directory" "$re_file"
expect_clean "scope auto-detects to memory from the filename" "$memory_file"

# ---------------------------------------------------------------------------
# Check — file length
# ---------------------------------------------------------------------------

long_file="$TMPDIR/long.md"
{
  echo "# Custom Instructions"
  echo
  echo "## Rules"
  echo
  echo "- r"
  echo
  echo "## Constraints"
  echo
  echo "- c"
  i=0
  while [ "$i" -lt 310 ]; do
    echo "filler line $i"
    i=$((i + 1))
  done
} > "$long_file"
expect_check file-length LOW "a file over the 300-line default threshold is LOW" "$long_file" global

# Control: the same file passes when the threshold is raised via the
# positional arg, and again via the env var, and again when disabled with 0.
expect_clean "an over-threshold file passes when max_lines is raised (arg)" "$long_file" global 1000
GENIRO_INSTRUCTIONS_MAX_LINES=1000 run_validator "$long_file" global
if [ "$VIF_RC" -eq 0 ] && [ -z "$VIF_OUT" ]; then
  pass "an over-threshold file passes when GENIRO_INSTRUCTIONS_MAX_LINES is raised (env)"
else
  fail "GENIRO_INSTRUCTIONS_MAX_LINES override — expected rc=0 with no rows, got rc=$VIF_RC rows: $VIF_OUT"
fi
expect_clean "max_lines=0 disables the length check entirely" "$long_file" global 0

# ---------------------------------------------------------------------------
# Check — dropped-skill slug references
# ---------------------------------------------------------------------------

dropped="$TMPDIR/dropped.md"
cat > "$dropped" <<'EOF'
# Custom Instructions

## Rules

- Do not route this through the dropped /learnings skill.

## Constraints

- none
EOF
expect_check dropped-skill-reference HIGH "a reference to a dropped skill slug is HIGH" "$dropped" global

# Control: a near-miss substring (a state-file path, not the dropped command)
# must NOT fire — the check has to distinguish the two.
near_miss="$TMPDIR/near-miss.md"
cat > "$near_miss" <<'EOF'
# Custom Instructions

## Rules

- Cite .geniro/knowledge/learnings.jsonl for prior facts, and read
  knowledge/learnings for context.

## Constraints

- none
EOF
expect_clean "a learnings.jsonl path / knowledge/learnings substring is not a false positive" "$near_miss" global

# ---------------------------------------------------------------------------
# Check — Additional-Steps anchor legality
# ---------------------------------------------------------------------------

legal_anchor="$TMPDIR/implement.md"
cat > "$legal_anchor" <<'EOF'
# Custom Instructions

## Rules

- r

## Additional Steps

### After analyze
- Run product discovery when no spec exists.

### After ship
- Post a summary to #eng-ships.

## Constraints

- c
EOF
expect_clean "implement.md's two legal anchors (analyze, ship) pass" "$legal_anchor" implement

illegal_anchor="$TMPDIR/global-illegal.md"
cat > "$illegal_anchor" <<'EOF'
# Custom Instructions

## Rules

- r

## Additional Steps

### After ship
- Post a summary.

## Constraints

- c
EOF
expect_check anchor-illegal MEDIUM "an 'After <phase>' anchor illegal for this scope is MEDIUM" "$illegal_anchor" global

# Control: the one anchor global DOES accept.
legal_global="$TMPDIR/global-legal.md"
sed 's/After ship/After worktree-setup/' "$illegal_anchor" > "$legal_global"
expect_clean "global's one legal anchor (worktree-setup) passes" "$legal_global" global

before_form="$TMPDIR/before-form.md"
cat > "$before_form" <<'EOF'
# Custom Instructions

## Rules

- r

## Additional Steps

### Before ship
- Do a thing first.

## Constraints

- c
EOF
expect_check anchor-illegal MEDIUM "a '### Before <phase>' subsection is always MEDIUM (no skill reads the prefix)" "$before_form" implement

freeform="$TMPDIR/freeform.md"
cat > "$freeform" <<'EOF'
# Custom Instructions

## Rules

- r

## Additional Steps

### A custom step with no anchor shape

## Constraints

- c
EOF
expect_check anchor-freeform LOW "a free-form Additional Steps subsection (no After/Before shape) is LOW" "$freeform" implement

# Control: a scope with NO legal anchors at all (e.g. review) still correctly
# rejects any 'After <phase>' subsection, even a real-sounding one.
no_anchor_scope="$TMPDIR/review.md"
cat > "$no_anchor_scope" <<'EOF'
# Custom Instructions

## Rules

- r

## Additional Steps

### After triage
- do something

## Constraints

- c
EOF
expect_check anchor-illegal MEDIUM "a scope with no legal anchors (review) rejects any 'After <phase>' subsection" "$no_anchor_scope" review

# ---------------------------------------------------------------------------
# Direct execution path — same verdict as the sourced function
# ---------------------------------------------------------------------------

bash "$REPO_ROOT/lib/validate-instructions-file.sh" "$good" global >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "direct execution agrees with the sourced call on a clean file"
else
  fail "direct execution on a clean file — expected rc=0, got rc=$rc"
fi

direct_out="$(bash "$REPO_ROOT/lib/validate-instructions-file.sh" "$dropped" global 2>/dev/null)"
rc=$?
if [ "$rc" -eq 2 ] && printf '%s\n' "$direct_out" | grep -q '^HIGH	dropped-skill-reference	'; then
  pass "direct execution agrees with the sourced call on a blocking file"
else
  fail "direct execution on a blocking file — got rc=$rc rows: $direct_out"
fi

# ---------------------------------------------------------------------------

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
