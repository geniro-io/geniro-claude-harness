#!/usr/bin/env bash
# Suite for lib/validate-action-file.sh — the 10 create/validate gate checks.
#
# Run: bash tests/actions/validate-action-file.sh
# Exits non-zero on any failure.
#
# Every blocking check gets a paired control: one fixture that must fail it and
# one otherwise-identical fixture that must pass, so a check that silently stops
# firing cannot look green.
#
# Plugin-developer tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/validate-action-file.sh"

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
          source "$REPO_ROOT/lib/validate-action-file.sh"
          source "$REPO_ROOT/lib/validate-action-file.sh"
          echo RESOURCE_OK) 2>&1 )
if printf '%s' "$resrc" | grep -q RESOURCE_OK; then
  pass "double-source is idempotent (no readonly crash under set -e)"
else
  fail "double-source crashed: $resrc"
fi

# Writes a valid action file at $TMPDIR/<slug>.md, then applies an optional sed
# program to mutate exactly one thing. Keeping one base fixture is what makes
# each failure attributable to the single mutation under test.
make_action() {
  local slug="$1" sedprog="${2:-}"
  local path="$TMPDIR/$slug.md"
  cat > "$path" <<EOF
---
name: $slug
description: "Use when wrapping up the day's commits and posting a recap. Skip for release branches."
model: inherit
allowed-tools: [Read, Bash(git *)]
argument-hint: "[since]"
risk_class: low
created: 2026-07-29
created-by: geniro:actions
---

# $slug

Summarizes the day's commits.

## When to use

- At the end of a working day.

## Steps

1. Run \`git log --since=yesterday --oneline\`.
2. Summarize the result in chat.

## Output

A short recap in chat.

## Test cases

1. Run it on a repo with commits today; expect a non-empty recap.
EOF
  if [ -n "$sedprog" ]; then
    sed "$sedprog" "$path" > "$path.new" && mv "$path.new" "$path"
  fi
  printf '%s' "$path"
}

# Runs the validator, capturing rows and rc without tripping the harness.
run_validator() {
  local target="$1"
  VAF_OUT="$(validate_action_file "$target" 2>/dev/null)"
  VAF_RC=$?
}

expect_clean() {
  local target="$1" label="$2"
  run_validator "$target"
  if [ "$VAF_RC" -eq 0 ] && [ -z "$VAF_OUT" ]; then
    pass "$label (rc=0, no rows)"
  else
    fail "$label — expected rc=0 with no rows, got rc=$VAF_RC rows: $VAF_OUT"
  fi
}

# Asserts the named check fired at the named severity and that the exit code
# matches the severity class (CRITICAL/HIGH blocking, MEDIUM/LOW warn).
expect_check() {
  local target="$1" check="$2" severity="$3" label="$4"
  local want_rc=2
  case "$severity" in MEDIUM|LOW) want_rc=1 ;; esac
  run_validator "$target"
  if ! printf '%s\n' "$VAF_OUT" | grep -q "^$severity	$check	"; then
    fail "$label — no '$severity $check' row; got: $VAF_OUT"
    return
  fi
  if [ "$VAF_RC" -ne "$want_rc" ]; then
    fail "$label — expected rc=$want_rc, got rc=$VAF_RC"
    return
  fi
  pass "$label (rc=$VAF_RC, $severity $check)"
}

# ---------------------------------------------------------------------------
# Usage / reachability codes — distinct from a bad file
# ---------------------------------------------------------------------------

validate_action_file >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 64 ]; then
  pass "no argument returns rc=64 (usage), not a content verdict"
else
  fail "no argument — expected rc=64, got rc=$rc"
fi

validate_action_file "$TMPDIR/does-not-exist.md" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 65 ]; then
  pass "missing target returns rc=65 (unreadable), not a content verdict"
else
  fail "missing target — expected rc=65, got rc=$rc"
fi

# ---------------------------------------------------------------------------
# Happy path — the control every mutation below is measured against
# ---------------------------------------------------------------------------

good="$(make_action daily-recap)"
expect_clean "$good" "a well-formed action file passes every check"

# ---------------------------------------------------------------------------
# Check 1 — frontmatter parses
# ---------------------------------------------------------------------------

no_fm="$TMPDIR/no-frontmatter.md"
{ echo "# no-frontmatter"; echo; echo "## Steps"; echo; echo "1. Do nothing."; } > "$no_fm"
expect_check "$no_fm" frontmatter-parse CRITICAL "missing frontmatter is CRITICAL"

unclosed="$TMPDIR/unclosed.md"
{ echo "---"; echo "name: unclosed"; echo "risk_class: low"; echo; echo "# unclosed"; } > "$unclosed"
expect_check "$unclosed" frontmatter-parse CRITICAL "unclosed frontmatter is CRITICAL"

# A frontmatter line that is neither key-shaped, a list item, nor a continuation.
bad_key="$(make_action bad-key 's|^model: inherit$|this line has no colon|')"
expect_check "$bad_key" frontmatter-parse CRITICAL "malformed frontmatter line is CRITICAL"

# Control: an indented continuation and a block list item are both legal YAML
# shapes and must NOT be reported as malformed.
block_list="$TMPDIR/block-list.md"
cat > "$block_list" <<'EOF'
---
name: block-list
description: "Use when checking that a block-style list parses cleanly."
allowed-tools:
  - Read
  - Glob
risk_class: low
---

# block-list

## Steps

1. Do the thing.
EOF
expect_clean "$block_list" "block-style list + indented continuation parse cleanly"

# ---------------------------------------------------------------------------
# Check 2 — name matches the filename slug
# ---------------------------------------------------------------------------

name_mismatch="$(make_action name-mismatch 's|^name: name-mismatch$|name: something-else|')"
expect_check "$name_mismatch" name-matches-filename CRITICAL "name not matching the filename is CRITICAL"

# ---------------------------------------------------------------------------
# Checks 3-4 — description opener and length
# ---------------------------------------------------------------------------

no_use_when="$(make_action no-use-when 's|^description: .*$|description: "Posts a recap to chat."|')"
expect_check "$no_use_when" description-use-when HIGH "description without a 'Use when' opener is HIGH"

# Control: the opener is matched case-insensitively.
lower_opener="$(make_action lower-opener 's|^description: .*$|description: "use when wrapping up the day."|')"
expect_clean "$lower_opener" "a lowercase 'use when' opener still passes"

long_desc_val="Use when $(printf 'x%.0s' $(seq 1 260))"
long_desc="$(make_action long-desc "s|^description: .*\$|description: \"$long_desc_val\"|")"
expect_check "$long_desc" description-length HIGH "a description past the 250-char cap is HIGH"

# Control: a description sitting exactly at the cap must pass.
at_cap_tail="$(printf 'y%.0s' $(seq 1 241))"
at_cap_val="Use when $at_cap_tail"
at_cap="$(make_action at-cap "s|^description: .*\$|description: \"$at_cap_val\"|")"
if [ "${#at_cap_val}" -ne 250 ]; then
  fail "fixture bug: at-cap description is ${#at_cap_val} chars, expected exactly 250"
else
  expect_clean "$at_cap" "a description exactly at the 250-char cap passes"
fi

# ---------------------------------------------------------------------------
# Check 5 — no unsubstituted placeholders
# ---------------------------------------------------------------------------

placeholder="$(make_action placeholder 's|^A short recap in chat.$|{{output_summary}}|')"
expect_check "$placeholder" no-placeholders HIGH "a leftover {{placeholder}} is HIGH"

# ---------------------------------------------------------------------------
# Check 6 — file length is a warning, never blocking
# ---------------------------------------------------------------------------

long_file="$(make_action long-file)"
{ i=0; while [ "$i" -lt 520 ]; do echo "filler line $i"; i=$((i + 1)); done; } >> "$long_file"
expect_check "$long_file" file-length MEDIUM "an over-long file warns (rc=1) rather than blocking"

# ---------------------------------------------------------------------------
# Check 7 — `## Steps` present with at least one numbered item
# ---------------------------------------------------------------------------

no_steps="$(make_action no-steps 's|^## Steps$|## Procedure|')"
expect_check "$no_steps" steps-section HIGH "a missing '## Steps' section is HIGH"

empty_steps="$TMPDIR/empty-steps.md"
cat > "$empty_steps" <<'EOF'
---
name: empty-steps
description: "Use when checking that an unnumbered Steps section is caught."
risk_class: low
---

# empty-steps

## Steps

Just some prose, no numbered items.

## Output

Nothing.
EOF
expect_check "$empty_steps" steps-section HIGH "a '## Steps' section with no numbered item is HIGH"

# ---------------------------------------------------------------------------
# Checks 8-9 — risk_class present and in range
# ---------------------------------------------------------------------------

no_risk="$(make_action no-risk '/^risk_class: low$/d')"
expect_check "$no_risk" risk-class-present CRITICAL "a missing risk_class is CRITICAL"

bad_risk="$(make_action bad-risk 's|^risk_class: low$|risk_class: extreme|')"
expect_check "$bad_risk" risk-class-value CRITICAL "an out-of-range risk_class is CRITICAL"

# ---------------------------------------------------------------------------
# Check 10 — external-send implies medium-or-high risk
# ---------------------------------------------------------------------------

ext_low="$(make_action ext-low 's|^risk_class: low$|risk_class: low\
external-send: true|')"
expect_check "$ext_low" external-send-risk HIGH "external-send: true at risk_class low is HIGH"

ext_med="$(make_action ext-med 's|^risk_class: low$|risk_class: medium\
external-send: true|')"
expect_clean "$ext_med" "external-send: true at risk_class medium passes"

# ---------------------------------------------------------------------------
# Direct execution path — same verdict as the sourced function
# ---------------------------------------------------------------------------

bash "$REPO_ROOT/lib/validate-action-file.sh" "$good" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "direct execution agrees with the sourced call on a clean file"
else
  fail "direct execution on a clean file — expected rc=0, got rc=$rc"
fi

direct_out="$(bash "$REPO_ROOT/lib/validate-action-file.sh" "$bad_risk" 2>/dev/null)"
rc=$?
if [ "$rc" -eq 2 ] && printf '%s\n' "$direct_out" | grep -q '^CRITICAL	risk-class-value	'; then
  pass "direct execution agrees with the sourced call on a blocking file"
else
  fail "direct execution on a blocking file — got rc=$rc rows: $direct_out"
fi

# ---------------------------------------------------------------------------

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
