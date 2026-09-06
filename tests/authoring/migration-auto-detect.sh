#!/usr/bin/env bash
# Tests the Auto-detect blocks published in MIGRATION.md by RUNNING them.
#
# Run: bash tests/authoring/migration-auto-detect.sh
#
# An entry's Auto-detect output is the sole relevance signal a consumer has
# (MIGRATION.md's own preamble, and skills/_shared/migration-walk.md: an entry
# carrying no detect "carries no relevance signal. Treat it as not applicable").
# So a detect that runs clean but matches nothing does not fail loudly — the
# entry silently never fires, and the migration is invisible to every upgrader.
#
# That is not hypothetical. The deep-mode detects shipped anchored on
# `[[:space:]]*$`, which matches a bare `deep_mode: false` and misses
# `deep_mode: false # true | false` — and the commented form is what every
# schema template renders, so it is the shape a producer actually writes. Both
# forms are asserted below.
#
# The commands are EXTRACTED from MIGRATION.md rather than restated here. A copy
# would let the doc and the test drift apart, which is the same silence again.
#
# Portability: bash 3.2 / BSD userland — no process substitution, no grep -P.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1
MIGRATION="$REPO_ROOT/MIGRATION.md"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

if [ ! -f "$MIGRATION" ]; then
  echo "FAIL: $MIGRATION is missing"
  exit 1
fi

TMPBASE="$(mktemp -d)" || exit 1
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPBASE"' EXIT

# --- 1. Every Auto-detect block in the file is syntactically runnable ---------
# Extracts each ```bash fence that follows an **Auto-detect:** marker.
awk '
  /^\*\*Auto-detect:\*\*/ { armed = 1; next }
  armed && /^```/         { infence = !infence; if (!infence) { armed = 0; print "---BLOCK---" }; next }
  infence                 { print }
' "$MIGRATION" > "$TMPBASE/blocks.txt"

block_count=0
bad_syntax=0
: > "$TMPBASE/one.sh"
while IFS= read -r line; do
  if [ "$line" = "---BLOCK---" ]; then
    block_count=$((block_count + 1))
    bash -n "$TMPBASE/one.sh" 2>/dev/null || bad_syntax=$((bad_syntax + 1))
    : > "$TMPBASE/one.sh"
  else
    printf '%s\n' "$line" >> "$TMPBASE/one.sh"
  fi
done < "$TMPBASE/blocks.txt"

if [ "$block_count" -gt 0 ]; then
  pass "found $block_count Auto-detect block(s) to exercise"
else
  fail "no Auto-detect blocks found — the extractor or the file's shape changed"
fi
[ "$bad_syntax" -eq 0 ] \
  && pass "every Auto-detect block parses under bash -n" \
  || fail "$bad_syntax Auto-detect block(s) are not valid shell"

# --- 2. The deep-mode detects match the shapes producers actually write ------
awk '
  /^### Deep mode is removed/       { inentry = 1 }
  inentry && /^\*\*Auto-detect:\*\*/ { armed = 1; next }
  armed && /^```/                   { infence = !infence; if (!infence) exit; next }
  infence                           { print }
' "$MIGRATION" > "$TMPBASE/deep-detect.sh"

if [ ! -s "$TMPBASE/deep-detect.sh" ]; then
  fail "could not extract the deep-mode Auto-detect block from MIGRATION.md"
  echo; echo "Tests run:    $TESTS_RUN"; echo "Tests failed: $TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ] || exit 1
  exit 0
fi

FIX="$TMPBASE/fixture"
mkdir -p "$FIX/.geniro/planning" "$FIX/.geniro/state"

# Bare values.
printf 'launch_config:\n  deep_mode: false\n'                     > "$FIX/.geniro/planning/spec-bare.md"
printf -- '---\ndeep-mode: true\n---\n'                           > "$FIX/.geniro/state/state-bare.md"
# Commented values — the form spec-template.md, launch-config-schema.md,
# review-handoff.md and debug-state-reference.md all render.
printf 'launch_config:\n  deep_mode: false # true | false\n'      > "$FIX/.geniro/planning/spec-commented.md"
printf -- '---\ndeep-mode: false   # propagated from state.md\n---\n' > "$FIX/.geniro/state/handoff-commented.md"
# An approvals entry.
printf -- '---\napprovals:\n  - category: deep_mode_choice\n---\n' > "$FIX/.geniro/state/approvals.md"
# Controls that must NOT match: a commented-out line, and a non-enum value.
printf '# deep_mode: false\n'                                     > "$FIX/.geniro/planning/control-commented-out.md"
printf 'launch_config:\n  deep_mode_notes: false\n'               > "$FIX/.geniro/planning/control-other-key.md"

cd "$FIX" || exit 1
sh "$TMPBASE/deep-detect.sh" > "$TMPBASE/hits.txt" 2>/dev/null
cd "$REPO_ROOT" || exit 1

for want in spec-bare.md spec-commented.md state-bare.md handoff-commented.md approvals.md; do
  if grep -q "$want" "$TMPBASE/hits.txt"; then
    pass "Auto-detect finds $want"
  else
    fail "Auto-detect MISSED $want — the entry would silently never fire for it"
  fi
done

for unwanted in control-commented-out.md control-other-key.md; do
  if grep -q "$unwanted" "$TMPBASE/hits.txt"; then
    fail "Auto-detect false-positives on $unwanted"
  else
    pass "Auto-detect ignores $unwanted"
  fi
done

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
