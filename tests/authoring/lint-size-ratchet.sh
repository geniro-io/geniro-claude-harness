#!/usr/bin/env bash
# Tests for the size ratchet of tests/authoring/lint-skills.sh — specifically that
# its word count means the same thing on every machine.
#
# Run: bash tests/authoring/lint-size-ratchet.sh
#
# The failure this guards is silent in both directions and was live in this repo.
# `wc -w` decides whether a run of non-blank bytes is a word using the locale's
# character classification, so a standalone `—`, `§`, `·`, or `→` — separators this
# repo's prose uses constantly — counts as a word under C.UTF-8 and as nothing at
# all under C. A baseline recorded on one machine then reads ~3% off on another:
# every file reports phantom growth for one contributor, while real growth hides
# under a too-high baseline for the other. Both look exactly like a normal run.
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

# A body whose word count differs between locales under `wc -w`: the separators are
# standalone multibyte tokens, which is the shape that makes the two disagree.
SEPARATOR_BODY='Phase 1 — parse · Phase 2 — detect · Phase 3 — filter → done.
See §Budgets and §Loop invariants — both ≥ 2 sections — for the rest.
Steps · one · two · three · four → the gate fires ≤ 4 options per call.'

# The two locales to compare. C is always present; the UTF-8 one may not be built on
# a given box, and a BSD userland does not vary its character classification by
# locale at all — there `wc -w` returns the same count for every one of them. So
# probe for the DIVERGENCE, measured on the very body these assertions use, rather
# than for the alternate locale's own count: that weaker test is satisfied on a
# platform which cannot exhibit the hazard, which then selects a locale that agrees
# with C and makes every comparison below vacuous. A vacuous PASS is worse than a
# skip. Measuring the real body also keeps the probe and the self-test below from
# ever disagreeing about whether this platform can demonstrate the bug.
ALT_LOCALE=""
_probe_c="$(printf '%s\n' "$SEPARATOR_BODY" | LC_ALL=C wc -w | tr -d ' ')"
for cand in C.UTF-8 en_US.UTF-8; do
  if [ "$(printf '%s\n' "$SEPARATOR_BODY" | LC_ALL="$cand" wc -w | tr -d ' ')" != "$_probe_c" ]; then
    ALT_LOCALE="$cand"
    break
  fi
done

# new_tree — a minimal tree the HARD checks pass clean, with the real lint script
# symlinked in so it treats the fixture as its repo. No size baseline is written;
# each test records its own.
new_tree() {
  local d
  d="$(mktemp -d "$TMPBASE/tree.XXXXXXXX")" || return 1
  mkdir -p "$d/tests/authoring" "$d/skills/probe" "$d/agents" "$d/.claude/skills"
  ln -s "$LINT" "$d/tests/authoring/lint-skills.sh"
  printf '0\n' > "$d/tests/authoring/anchor-baseline.txt"
  mkdir -p "$d/skills/probe2"
  cat > "$d/skills/probe/SKILL.md" <<EOF
---
name: probe
description: Use when probing the size ratchet.
---

# Probe

$SEPARATOR_BODY
EOF
  # A second recorded file, so a writer that claims to touch one row can be caught
  # touching two. With a single-file fixture, blanket and targeted writes are
  # indistinguishable and every assertion below would pass either way.
  cat > "$d/skills/probe2/SKILL.md" <<EOF
---
name: probe2
description: Use when probing that a neighbouring row stays put.
---

# Probe two

$SEPARATOR_BODY
EOF
  printf '%s\n' "$d"
}

run_lint()     { ( cd "$1" && LC_ALL="$2" bash "$1/tests/authoring/lint-skills.sh" 2>&1 ); }
record_base()  { ( cd "$1" && LC_ALL="$2" bash "$1/tests/authoring/lint-skills.sh" --update-baseline >/dev/null 2>&1 ); }
probe_size()   { awk '$1 == "skills/probe/SKILL.md"  { print $2 }' "$1/tests/authoring/skill-size-baseline.txt"; }
probe2_size()  { awk '$1 == "skills/probe2/SKILL.md" { print $2 }' "$1/tests/authoring/skill-size-baseline.txt"; }

# --- self-test: the fixture body is one the two locales would disagree about ----
# Without this, a body of plain ASCII would make every assertion below pass while
# measuring nothing — the exact green-for-the-wrong-reason the ratchet cannot afford.
if [ -n "$ALT_LOCALE" ]; then
  tree=$(new_tree)
  c_wc=$(LC_ALL=C wc -w < "$tree/skills/probe/SKILL.md" | tr -d ' ')
  u_wc=$(LC_ALL="$ALT_LOCALE" wc -w < "$tree/skills/probe/SKILL.md" | tr -d ' ')
  if [ "$c_wc" != "$u_wc" ]; then
    pass "self-test: the fixture body is locale-sensitive under wc -w ($c_wc vs $u_wc)"
  else
    fail "self-test: wc -w agrees ($c_wc) on the fixture, so these tests measure nothing — the body needs standalone multibyte separators"
  fi
else
  echo "SKIP: this platform's wc -w does not vary by locale (no UTF-8 locale built, or a BSD userland that classifies these bytes identically everywhere) — the cross-locale assertions cannot run here, and the portability they guard has to be proved on a GNU box"
fi

# --- 1. a baseline recorded in one locale reads back clean in the other ---------
# This is the bug in its natural shape: nobody edits the file, and the second
# contributor's lint reports growth that never happened.
if [ -n "$ALT_LOCALE" ]; then
  tree=$(new_tree)
  record_base "$tree" "$ALT_LOCALE"
  out=$(run_lint "$tree" C)
  if printf '%s\n' "$out" | grep -q 'grew to'; then
    fail "a baseline recorded under $ALT_LOCALE reports phantom growth when read back under C. Output: $(printf '%s\n' "$out" | grep 'grew to')"
  else
    pass "a baseline recorded under $ALT_LOCALE reads back clean under C"
  fi

  tree=$(new_tree)
  record_base "$tree" C
  out=$(run_lint "$tree" "$ALT_LOCALE")
  if printf '%s\n' "$out" | grep -q 'grew to'; then
    fail "a baseline recorded under C reports phantom growth when read back under $ALT_LOCALE. Output: $(printf '%s\n' "$out" | grep 'grew to')"
  else
    pass "a baseline recorded under C reads back clean under $ALT_LOCALE"
  fi
fi

# --- 2. the recorded number itself is the same either way -----------------------
# The read-back test above would also pass if the count merely happened to fall on
# the permissive side. The recorded figure has to be identical, because it is what
# a later contributor's growth is measured against.
if [ -n "$ALT_LOCALE" ]; then
  t1=$(new_tree); record_base "$t1" C
  t2=$(new_tree); record_base "$t2" "$ALT_LOCALE"
  n1=$(probe_size "$t1"); n2=$(probe_size "$t2")
  if [ -n "$n1" ] && [ "$n1" = "$n2" ]; then
    pass "the recorded size is identical across locales ($n1)"
  else
    fail "the recorded size differs by locale: C=$n1 $ALT_LOCALE=$n2 — the baseline is not portable"
  fi
fi

# --- 3. real growth is still caught --------------------------------------------
# A count that is stable but never moves would pass every assertion above. The
# ratchet has to keep working.
tree=$(new_tree)
record_base "$tree" C
printf '%s\n' "$SEPARATOR_BODY $SEPARATOR_BODY" >> "$tree/skills/probe/SKILL.md"
out=$(run_lint "$tree" C)
if printf '%s\n' "$out" | grep -q 'skills/probe/SKILL.md: grew to'; then
  pass "growth past a recorded baseline still warns"
else
  fail "growth past the baseline did not warn — the ratchet is inert. Output: $out"
fi

# --- 4. the repo's own baseline agrees with the script's rule -------------------
# A row that disagrees was recorded by some other rule — a bare wc, a hand edit, or
# a run on a box whose locale changed the answer — and it silently re-permits that
# file to grow to the wrong number. Only rows recorded ABOVE the true size are a
# defect: a file may legitimately shrink after its baseline was accepted.
overstated=""
while read -r p n; do
  [ -f "$REPO_ROOT/$p" ] || continue
  actual=$(awk '{ w += NF } END { print w + 0 }' "$REPO_ROOT/$p")
  [ "$n" -gt "$actual" ] && overstated="$overstated $p(recorded=$n actual=$actual)"
done < "$REPO_ROOT/tests/authoring/skill-size-baseline.txt"
if [ -z "$overstated" ]; then
  pass "no recorded baseline row is above its file's true size"
else
  fail "baseline rows recorded above the file's real size — refresh with --update-baseline:$overstated"
fi

# --- 5. --accept moves the named row and only the named row ---------------------
# The whole reason the targeted form exists: --update-baseline rewrites all rows, so
# a refresh meant to accept one file's growth also accepts every neighbour that grew
# since, unreviewed and invisible in a diff expected to move one line.
tree=$(new_tree)
record_base "$tree" C
before2=$(probe2_size "$tree")
printf '%s\n' "$SEPARATOR_BODY" >> "$tree/skills/probe/SKILL.md"
printf '%s\n' "$SEPARATOR_BODY" >> "$tree/skills/probe2/SKILL.md"   # neighbour grew too
( cd "$tree" && bash "$tree/tests/authoring/lint-skills.sh" --accept skills/probe/SKILL.md >/dev/null 2>&1 )
after1=$(probe_size "$tree"); after2=$(probe2_size "$tree")
grown1=$(awk '{ w += NF } END { print w + 0 }' "$tree/skills/probe/SKILL.md")
if [ "$after1" = "$grown1" ]; then
  pass "--accept records the named file's new size"
else
  fail "--accept did not record the named file: recorded=$after1 actual=$grown1"
fi
if [ "$after2" = "$before2" ]; then
  pass "--accept leaves an unnamed neighbour's row untouched"
else
  fail "--accept moved a row it was not given: probe2 was $before2, now $after2 — this is the blanket-refresh hazard the flag exists to avoid"
fi

# Contrast: the blanket form is expected to move both. If this ever stops being
# true, the two modes have collapsed into one and the targeted test above is vacuous.
tree=$(new_tree)
record_base "$tree" C
printf '%s\n' "$SEPARATOR_BODY" >> "$tree/skills/probe2/SKILL.md"
b2_before=$(probe2_size "$tree")
record_base "$tree" C
if [ "$(probe2_size "$tree")" != "$b2_before" ]; then
  pass "--update-baseline still records every row (the two modes remain distinct)"
else
  fail "--update-baseline did not re-record a grown neighbour — the blanket mode is broken"
fi

# --- 6. --accept refuses what the size checks never read ------------------------
# A row for an unchecked path looks like an accepted size and is not one: nothing
# reads it, so it silently records a judgment that has no effect.
tree=$(new_tree)
record_base "$tree" C
rows_before=$(grep -c . "$tree/tests/authoring/skill-size-baseline.txt")
printf 'notes\n' > "$tree/README.md"
( cd "$tree" && bash "$tree/tests/authoring/lint-skills.sh" --accept README.md >/dev/null 2>&1 )
rc=$?
rows_after=$(grep -c . "$tree/tests/authoring/skill-size-baseline.txt")
if [ "$rc" -ne 0 ] && [ "$rows_before" = "$rows_after" ]; then
  pass "--accept rejects a path outside the measured population and writes nothing"
else
  fail "--accept on an unchecked path: rc=$rc rows $rows_before -> $rows_after (expected non-zero rc, no new row)"
fi

# --- 7. --accept-anchors touches the anchor figure, not the sizes ---------------
tree=$(new_tree)
record_base "$tree" C
printf '%s\n' "$SEPARATOR_BODY" >> "$tree/skills/probe/SKILL.md"
sizes_before=$(cat "$tree/tests/authoring/skill-size-baseline.txt")
( cd "$tree" && bash "$tree/tests/authoring/lint-skills.sh" --accept-anchors >/dev/null 2>&1 )
if [ "$(cat "$tree/tests/authoring/skill-size-baseline.txt")" = "$sizes_before" ]; then
  pass "--accept-anchors leaves the size baseline alone"
else
  fail "--accept-anchors rewrote size rows — accepting an anchor count must not accept sizes"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
