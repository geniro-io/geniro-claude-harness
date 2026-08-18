#!/usr/bin/env bash
# Tests for check 10 of tests/authoring/lint-skills.sh — the section-anchor ratchet
# and the anchor_unresolved resolver behind it.
#
# Run: bash tests/authoring/lint-anchor-ratchet.sh
#
# The check exists for one failure: a heading is renamed or deleted, and every `§`
# citation aimed at it dangles with nothing to notice. Its output is a single
# number compared against a recorded figure, which makes both directions of error
# invisible in normal use — an anchor wrongly counted disappears into the baseline
# on the next --update-baseline, and an anchor wrongly resolved never shows up at
# all. Neither can be read off the repo's own run, where the count is 69 either
# way. So the resolver is exercised against trees whose right answer is known.
#
# The lint script derives its repo root from $0 (`dirname $0/../..`), so a symlink
# to the real script inside a fixture tree makes that script scan the fixture.
# Nothing here copies the code under test.
#
# Portability: bash 3.2 / BSD userland as well as GNU — no process substitution,
# no grep -P, no GNU-only flags.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1
LINT="$REPO_ROOT/tests/authoring/lint-skills.sh"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

if [ ! -f "$LINT" ]; then
  echo "FAIL: $LINT is missing"
  exit 1
fi

TMPBASE="$(mktemp -d)" || exit 1
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPBASE"' EXIT

# new_tree <recorded-figure> — a minimal tree the HARD checks pass clean, with the
# real lint script symlinked in so it treats the fixture as its repo.
new_tree() {
  local d
  d="$(mktemp -d "$TMPBASE/tree.XXXXXXXX")" || return 1
  mkdir -p "$d/tests/authoring" "$d/skills/probe" "$d/agents" "$d/.claude/skills"
  ln -s "$LINT" "$d/tests/authoring/lint-skills.sh"
  printf '%s\n' "$1" > "$d/tests/authoring/anchor-baseline.txt"
  printf '%s\n' "$d"
}

# cite <tree> <anchor> — a citing skill body whose one path-adjacent `§` names the
# given section of skills/probe/ref.md. Rooted with ${CLAUDE_PLUGIN_ROOT}/ because
# a bare path is a HARD failure of its own (check 5) and would mask this check.
cite() {
  cat > "$1/skills/probe/SKILL.md" <<EOF
---
name: probe
description: Use when probing the anchor resolver.
---

# Probe

The procedure is in \`\${CLAUDE_PLUGIN_ROOT}/skills/probe/ref.md\` §$2 — read it there.
EOF
}

run_lint() { bash "$1/tests/authoring/lint-skills.sh" 2>&1; }

# --- self-test: the resolver and this harness are both live -----------------
# A citation naming a section that is in no heading of the cited file must raise
# the count. If this goes green-in-the-wrong-direction, every assertion below is
# measuring an empty fixture rather than the resolver.
tree=$(new_tree 0)
cat > "$tree/skills/probe/ref.md" <<'EOF'
# Ref

## Real heading

text
EOF
cite "$tree" "Missing section"
out=$(run_lint "$tree")
rc=$?
if grep -q 'rose to 1 (recorded 0)' <<<"$out"; then
  pass "self-test: a citation naming no heading in the cited file raises the count"
else
  fail "self-test: a plainly dangling anchor did not raise the count — the fixture, not the resolver, is being measured. Output: $out"
fi
if [ "$rc" -eq 0 ]; then
  pass "self-test: the check stays advisory — a raised count does not change the exit status"
else
  fail "self-test: lint exited $rc on a tree whose only finding is the advisory anchor count"
fi

# --- a heading-shaped line inside a code fence is not a heading -------------
# The resolver matches `^#{1,4} ` over the whole cited file, fences included, so a
# shell comment in a bash block can resolve a citation whose real heading is gone.
# Check 9 in the same script tracks fence state for exactly this reason
# (`if (line ~ /^[ \t]*```/) { fence = 1 - fence; continue }`), so the file already
# holds the standard this one misses.
tree=$(new_tree 0)
cat > "$tree/skills/probe/ref.md" <<'EOF'
# Ref

## Real heading

The section this file used to have was called "Cleanup contract" and was renamed.

```bash
# Cleanup contract: rm -rf the slug dir before the terminal write
run_cleanup
```
EOF
cite "$tree" "Cleanup contract"
out=$(run_lint "$tree")
if grep -q 'rose to 1 (recorded 0)' <<<"$out"; then
  pass "a citation is unresolved when its only match is a comment inside a code fence"
else
  fail "the deleted heading 'Cleanup contract' left its citer dangling and the count did not move — the resolver accepted '# Cleanup contract:' from inside a bash fence as the heading. This is the rename the check exists to catch, and code fences carrying '# ' comment lines are everywhere in this corpus. Output: $(printf '%s\n' "$out" | grep -i anchor)"
fi

# --- an anchor beginning with a dash reaches grep as an option --------------
# `grep -qiF "$_s"` is called without `--`, so a two-word anchor starting with `-`
# makes grep exit 2 on an unrecognized option (BSD and GNU alike). The error goes
# to /dev/null and the citation is booked as dangling, which reports a rename that
# never happened and can only be silenced by accepting a higher baseline.
tree=$(new_tree 0)
cat > "$tree/skills/probe/ref.md" <<'EOF'
# Ref

## --deep mode activation

text
EOF
cite "$tree" "--deep mode activation"
out=$(run_lint "$tree")
if grep -q 'rose to ' <<<"$out"; then
  fail "the anchor '--deep mode activation' matches the heading '## --deep mode activation' verbatim, yet the count rose — the first two words go to grep unquoted-by-option ('grep -qiF \"--deep mode\"' exits 2), so a valid citation is reported as a heading that was renamed or deleted. Output: $(printf '%s\n' "$out" | grep -i anchor)"
else
  pass "an anchor beginning with a dash resolves against the heading that carries it"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
