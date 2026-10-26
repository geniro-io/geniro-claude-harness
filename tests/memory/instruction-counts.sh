#!/usr/bin/env bash
# Smoke test for lib/instruction-counts.sh — the Rules/Constraints/Data
# Sources/Additional-Steps counter that skills/_shared/load-custom-instructions.md's
# echo contract quotes instead of a model-counted tally.
#
# Pins for count_instruction_sections: exact counting on a mixed fixture
# (top-level bullets only — nested sub-bullets and fenced-code-block content
# excluded); a non-empty path that is missing or unreadable returns
# $_GIC_UNREADABLE (65) with no stdout, distinguishing "could not read the
# file" from "read it, found nothing"; no path at all and a readable file
# with none of the three sections both still yield "0 0 0" at rc 0 — that's
# a real, present-but-empty result, not an error; and parity between the
# sourced-function call and the direct `bash lib/instruction-counts.sh
# <path>` invocation, for both the success and the error path.
#
# Bullets inside an HTML comment (single- or multi-line) are not counted by
# count_instruction_sections.
#
# Pins for count_additional_steps: scoped to `## Additional Steps` only (a
# same-named `### After` heading elsewhere in the file must not count);
# fence-aware; matches both `After` and `Before` case-insensitively and
# names each match verbatim; counts only subsections with real content (a
# bare heading or a comment-only body is not a step); same no-path /
# missing-path contract as count_instruction_sections.
#
# Run: bash tests/memory/instruction-counts.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO_ROOT/lib/instruction-counts.sh"

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# shellcheck disable=SC1090
source "$LIB"

expect_counts() {
  local file="$1" expected="$2" label="$3"
  local got
  got="$(count_instruction_sections "$file")"
  if [ "$got" = "$expected" ]; then
    pass "$label"
  else
    fail "$label — expected '$expected', got '$got'"
  fi
}

# A path count_instruction_sections could not open: expects no stdout and the
# $_GIC_UNREADABLE exit code, never the misleading "0 0 0".
expect_unreadable() {
  local file="$1" label="$2"
  local got rc
  got="$(count_instruction_sections "$file")"
  rc=$?
  if [ "$rc" -eq "$_GIC_UNREADABLE" ] && [ -z "$got" ]; then
    pass "$label"
  else
    fail "$label — expected empty output and rc $_GIC_UNREADABLE, got '$got' rc $rc"
  fi
}

# --- 1. Mixed fixture: 12 top-level rules (one has a nested sub-bullet that
# must NOT count), 4 top-level constraints (one has a nested sub-bullet),
# 11 data sources, an Additional Steps bullet that belongs to neither section,
# and a fenced code block containing a fake "## Rules" heading + bullet that
# must not be picked up.
fixture="$TMPDIR_BASE/global.md"
cat > "$fixture" <<'EOF'
# Custom Instructions

## Rules
- Rule one
- Rule two
  - nested sub-bullet under rule two (must not count)
- Rule three
- Rule four
- Rule five
- Rule six
- Rule seven
- Rule eight
- Rule nine
- Rule ten
- Rule eleven
- Rule twelve

## Additional Steps
### After ship
- not a rule or constraint — must not count anywhere
```
## Rules
- inside a fenced code block — must not count
```

## Constraints
- Constraint one
- Constraint two
  * nested sub-bullet under constraint two (must not count)
- Constraint three
- Constraint four

## Data Sources
- **source one** (confirms: x) — cmd
- **source two** (confirms: x) — cmd
- **source three** (confirms: x) — cmd
- **source four** (confirms: x) — cmd
- **source five** (confirms: x) — cmd
- **source six** (confirms: x) — cmd
- **source seven** (confirms: x) — cmd
- **source eight** (confirms: x) — cmd
- **source nine** (confirms: x) — cmd
- **source ten** (confirms: x) — cmd
- **source eleven** (confirms: x) — cmd
EOF
expect_counts "$fixture" "12 4 11" \
  "mixed fixture: 12 rules / 4 constraints / 11 data sources, nested + fenced bullets excluded"

# --- 2. Missing path → non-zero rc, no stdout (never the misleading "0 0 0").
expect_unreadable "$TMPDIR_BASE/does-not-exist.md" \
  "missing file → rc $_GIC_UNREADABLE, no output"

# --- 3. Empty argument (no path at all) → "0 0 0" — a caller with nothing to
# load passes no argument by design; this is not the missing-path error case.
expect_counts "" "0 0 0" \
  "empty path argument → 0 0 0"

# --- 4. Readable file with none of the three sections → "0 0 0".
no_sections="$TMPDIR_BASE/no-sections.md"
cat > "$no_sections" <<'EOF'
# Custom Instructions

## Additional Steps
### After ship
- an additional step, not a rule/constraint/source
EOF
expect_counts "$no_sections" "0 0 0" \
  "file with none of the three sections → 0 0 0"

# --- 5. Unreadable file → non-zero rc, no stdout (skip under a root/CI
# runner where chmod 000 doesn't actually block root's own read).
if [ "$(id -u)" != "0" ]; then
  noperm="$TMPDIR_BASE/noperm.md"
  printf '# Custom Instructions\n\n## Rules\n- x\n' > "$noperm"
  chmod 000 "$noperm"
  expect_unreadable "$noperm" \
    "unreadable file → rc $_GIC_UNREADABLE, no output"
  chmod 644 "$noperm"
else
  echo "SKIP: running as root — permission-bit test would not block the read."
fi

# --- 6. Zero-count sections still report their real (zero) count, not an
# absent-file 0-0-0 conflated with a present-but-empty section.
zero_rules="$TMPDIR_BASE/zero-rules.md"
cat > "$zero_rules" <<'EOF'
# Custom Instructions

## Rules

## Constraints
- Only one constraint
EOF
expect_counts "$zero_rules" "0 1 0" \
  "present-but-empty ## Rules section counts as 0, sibling section unaffected"

# --- 6b. Bullets inside HTML comments are no entries: a multi-line comment of
# example bullets, a single-line comment, and a comment left open by a bullet
# line all hide their bullets; a fenced block holding `<!--` opens no comment;
# a `## ` heading inside a comment starts no section.
commented="$TMPDIR_BASE/commented.md"
cat > "$commented" <<'EOF'
# Custom Instructions

## Rules
<!--
- example rule inside a multi-line comment (must not count)
-->
- Real rule
- Rule with a trailing note <!-- inline -->
<!-- - single-line commented bullet -->
- Rule that opens a comment <!-- start
- hidden by the open comment
- hidden too
end -->
- Rule after the comment
```
<!--
```
- Rule after a fenced block holding an opener

## Constraints
<!--
## Rules
- decoy under a heading inside a comment
## Data Sources
- decoy
-->
- Real constraint

## Data Sources
<!-- - **source** (confirms: x) — cmd -->
- **real source** (confirms: x) — cmd
EOF
expect_counts "$commented" "5 1 1" \
  "bullets inside HTML comments (multi-line, single-line, left open, headings in them) are not counted"

commented_only="$TMPDIR_BASE/commented-only.md"
cat > "$commented_only" <<'EOF'
## Rules
<!--
- example one
- example two
-->
EOF
expect_counts "$commented_only" "0 0 0" \
  "a Rules section holding only a commented-out bullet block counts 0"

# --- 7. Direct CLI invocation matches the sourced-function call.
direct_got="$(bash "$LIB" "$fixture")"
if [ "$direct_got" = "12 4 11" ]; then
  pass "direct \`bash lib/instruction-counts.sh <path>\` invocation matches the sourced call"
else
  fail "direct invocation — expected '12 4 11', got '$direct_got'"
fi

# --- 7b. Direct CLI invocation on a missing path matches the sourced call's
# error shape — same rc, no stdout.
direct_err_out="$(bash "$LIB" "$TMPDIR_BASE/does-not-exist.md")"
direct_err_rc=$?
if [ "$direct_err_rc" -eq "$_GIC_UNREADABLE" ] && [ -z "$direct_err_out" ]; then
  pass "direct invocation on a missing path → rc $_GIC_UNREADABLE, no output"
else
  fail "direct invocation on a missing path — expected empty output and rc $_GIC_UNREADABLE, got '$direct_err_out' rc $direct_err_rc"
fi

# --- 8. Direct CLI invocation with no argument still exits 0 with "0 0 0"
# (the no-arg case is normal, not a usage error).
direct_noarg_out="$(bash "$LIB")"
direct_noarg_rc=$?
if [ "$direct_noarg_out" = "0 0 0" ] && [ "$direct_noarg_rc" -eq 0 ]; then
  pass "direct invocation with no argument → '0 0 0', rc 0"
else
  fail "direct invocation with no argument — expected '0 0 0' rc 0, got '$direct_noarg_out' rc $direct_noarg_rc"
fi

# --- 9. Double-sourcing under `set -e` does not crash (helpers get re-sourced
# across the codebase — a redefinition or a stray top-level command would
# abort the caller), matching the guard convention in lib/hash.sh's suite.
if bash -c "set -e; source '$LIB'; source '$LIB'; count_instruction_sections '$fixture' >/dev/null"; then
  pass "double-sourcing lib/instruction-counts.sh under set -e does not crash"
else
  fail "double-sourcing lib/instruction-counts.sh under set -e crashed"
fi

# --- 10. count_additional_steps: scoped to ## Additional Steps, fence-aware,
# case-insensitive on After/Before, canonical + non-canonical case, a fenced
# decoy, and an ### After outside the section that must not count.
steps_fixture="$TMPDIR_BASE/steps.md"
cat > "$steps_fixture" <<'EOF'
# Custom Instructions

### After ship
- outside ## Additional Steps entirely — must not count

## Additional Steps
### After ship
- a normal step

### before Ship
- non-canonical case AND the Before form — must still be matched and named

```
## Additional Steps
### After fenced-decoy
```

### After analyze
- another normal step

## Constraints
- a constraint
EOF
expect_steps() {
  local file="$1" expected="$2" label="$3"
  local got
  got="$(count_additional_steps "$file")"
  if [ "$got" = "$expected" ]; then
    pass "$label"
  else
    fail "$label — expected '$expected', got '$got'"
  fi
}
expect_steps "$steps_fixture" "$(printf '3\nAfter ship\nbefore Ship\nAfter analyze')" \
  "count_additional_steps: 3 matched (outside-section + fenced decoys excluded, non-canonical case + Before form both named)"

# --- 11. count_additional_steps: file with no ## Additional Steps section → "0".
expect_steps "$zero_rules" "0" \
  "count_additional_steps: file with no Additional Steps section → 0"

# --- 12. count_additional_steps: empty argument → "0" rc 0.
got_empty="$(count_additional_steps "")"
rc_empty=$?
if [ "$got_empty" = "0" ] && [ "$rc_empty" -eq 0 ]; then
  pass "count_additional_steps: empty path argument → 0, rc 0"
else
  fail "count_additional_steps: empty path argument — expected '0' rc 0, got '$got_empty' rc $rc_empty"
fi

# --- 13. count_additional_steps: missing path → rc $_GIC_UNREADABLE, no stdout.
got_missing="$(count_additional_steps "$TMPDIR_BASE/does-not-exist.md")"
rc_missing=$?
if [ "$rc_missing" -eq "$_GIC_UNREADABLE" ] && [ -z "$got_missing" ]; then
  pass "count_additional_steps: missing file → rc $_GIC_UNREADABLE, no output"
else
  fail "count_additional_steps: missing file — expected empty output and rc $_GIC_UNREADABLE, got '$got_missing' rc $rc_missing"
fi

# --- 14. count_additional_steps: a freshly scaffolded headings-only file
# reports no steps — an empty subsection is not a step.
scaffold="$TMPDIR_BASE/scaffold.md"
cat > "$scaffold" <<'EOF'
# Custom Instructions

## Rules

## Additional Steps

### After analyze

### After ship

## Constraints

## Data Sources
<!-- append the Data-Sources stub below -->
EOF
expect_steps "$scaffold" "0" \
  "count_additional_steps: headings-only subsections (blank bodies) → 0"

# --- 15. count_additional_steps: a body that is only an HTML comment (one
# line, or spanning lines, or blank lines around it) is not content.
comment_only="$TMPDIR_BASE/comment-only.md"
cat > "$comment_only" <<'EOF'
## Additional Steps

### After analyze
<!-- add a pre-code step here -->

### After ship

<!--
- example bullet inside a comment
### After decoy
-->
   

### After verify
<!-- one --> <!-- two -->
EOF
expect_steps "$comment_only" "0" \
  "count_additional_steps: comment-only bodies (single-line, multi-line, blank-padded) → 0"

# --- 16. count_additional_steps: a subsection with a bullet is counted, and
# so is one whose only content is a fenced block.
with_bullet="$TMPDIR_BASE/with-bullet.md"
cat > "$with_bullet" <<'EOF'
## Additional Steps

### After ship
- Post a summary to the team channel

### After verify
```bash
make smoke
```
EOF
expect_steps "$with_bullet" "$(printf '2\nAfter ship\nAfter verify')" \
  "count_additional_steps: bullet body and fenced-block body are both counted"

# --- 17. count_additional_steps: mixed file — only content-bearing
# subsections are counted and named, in order; a non-After subsection ends the
# previous one; text beside a comment is content; a heading inside a comment
# is not a heading; the last subsection at end of file is judged too.
mixed="$TMPDIR_BASE/mixed.md"
cat > "$mixed" <<'EOF'
## Additional Steps

### After explore

### After user-approve
<!-- placeholder -->

### Notes
- belongs to a non-After subsection, not to "After user-approve"

### After analyze
<!--
### After decoy
- inside a comment
-->
Run the product-discovery stage first <!-- inline note -->

### Before ship
- a Before subsection with content is named too

### After verify
<!-- trailing, empty -->
EOF
expect_steps "$mixed" "$(printf '2\nAfter analyze\nBefore ship')" \
  "count_additional_steps: mixed file → only content-bearing subsections counted and named"

# --- 18. A content-bearing last subsection at end of file, with no trailing
# newline, is still counted.
eof_fixture="$TMPDIR_BASE/eof.md"
printf '## Additional Steps\n\n### After ship\n- last line, no trailing newline' > "$eof_fixture"
expect_steps "$eof_fixture" "$(printf '1\nAfter ship')" \
  "count_additional_steps: content-bearing last subsection at EOF without a newline → counted"

# --- 19. A `<!--` quoted in a backtick code span opens no comment, and a
# comment trailing a heading does not hide the heading.
codespan="$TMPDIR_BASE/codespan.md"
cat > "$codespan" <<'EOF'
## Rules <!-- note -->
- Never leave `<!--` placeholders in a file
- second rule
- third rule

## Constraints
- one constraint
EOF
expect_counts "$codespan" "3 1 0" \
  "count_instruction_sections: backtick-quoted <!-- and a commented heading → nothing hidden"

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
