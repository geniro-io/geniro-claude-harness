#!/usr/bin/env bash
# C8 (plugin-audit 2026-09-23, fix-plan §O) — a same-file directional section
# citation ("§X above" / "§X below") must resolve to a heading that is
# actually on that side of the citing line, in the SAME file.
#
# Run: bash tests/authoring/lint-directional-anchors.sh
#
# Why this exists: skill-structure.md §Cross-skill references endorses content
# anchors over line numbers because content anchors "survive edits" — but a
# directional anchor ("§ACI per-phase tool surface above") is really a
# position claim smuggled into a content anchor, and a section move breaks it
# exactly the way a line number would while reading as if it survived. T2-8
# (plugin-audit-2026-09-23.md): implement/SKILL.md:86 cited "§ACI per-phase
# tool surface above" after the section moved to operations-reference.md, and
# operations-reference.md in turn cited "§State persistence above" when that
# heading sits below the citation.
#
# Scope: every `*.md` under skills/ and agents/ — the shipped population.
# Only a citation whose anchor RESOLVES to a real heading in the SAME file is
# judged; an anchor that resolves nowhere is dangling, and dangling anchors
# (same-file or cross-file) are already tests/authoring/lint-skills.sh check
# 10's job (a count ratchet, because that check's anchor right-boundary is
# undecidable). This check narrows to what IS decidable: given a resolved
# heading and its line number, "above" or "below" is a plain integer compare.
#
# False-positive guard: "the §4.1 gate — which reads severity directly at
# HIGH and above" (review/SKILL.md) is English prose using "above" as an
# ordering word, not a section pointer, and its apparent anchor ("4.1") does
# not resolve to any real heading in that file (§4.1 is a Phase-numbering
# reference, not a markdown heading there) — so it is skipped by the same
# resolve-or-skip rule, not specially excluded.
#
# Self-test: the check logic lives in the check_tree function, called directly
# (in-process, inside a subshell that `cd`s into a throwaway fixture) rather
# than by symlinking and re-invoking this file — re-invoking would re-run this
# very self-test section inside the child, which re-invokes it again in ITS
# child, unbounded. Calling the function directly gets the same fixture
# isolation (a subshell's report_fail/FAILS never leaks to the parent) with no
# recursion hazard.
#
# Portability: bash 3.2 / BSD userland as well as GNU — no process
# substitution feeding a variable that must survive the loop, no grep -P, no
# \s in grep -E, tolower() (POSIX awk) instead of gawk-only IGNORECASE.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# <file> -> "<lineno><TAB><heading line>" for every REAL heading (not inside a
# fenced code block — a `# comment` in a bash fence is not a heading; this
# corpus carries hundreds of them, per lint-skills.sh's own _real_headings).
_real_headings() {
  awk '
    /^[ \t]*```/ { fence = 1 - fence; next }
    fence        { next }
    /^# |^## |^### |^#### / { print NR "\t" $0 }
  ' "$1" 2>/dev/null
}

# First two whitespace-separated tokens of the anchor text, trailing sentence
# punctuation stripped — the same reduction lint-skills.sh's anchor resolver
# uses, so a heading this check calls "resolved" is one that check 10 would
# also call resolved (no new resolution rule to audit separately).
_anchor_key() {
  printf '%s' "$1" \
    | awk '{ printf "%s", $1; if (NF > 1) printf " %s", $2 }' \
    | sed 's|[.,:;)]*$||'
}

# <headings-blob> <key> -> first matching heading's line number, or empty.
_first_match_line() {
  printf '%s\n' "$1" | awk -F'\t' -v k="$2" '
    { if (index(tolower($2), tolower(k)) > 0) { print $1; exit } }'
}

# <headings-blob> <citing-line> -> the line number of the heading whose
# section CONTAINS the citing line (the nearest real heading at or above it),
# or 0 when the citation precedes every heading.
_containing_heading_line() {
  printf '%s\n' "$1" | awk -F'\t' -v ln="$2" '
    { if ($1 <= ln) last = $1 } END { print last + 0 }'
}

# Runs the whole battery against the CURRENT directory's skills/ + agents/,
# setting $LAST_CHECKED to the resolved-citation count. Call it WITHOUT
# wrapping in `$( )` when the caller needs report_fail's increments to reach
# this script's own $FAILS — command substitution forks a subshell, and a
# subshell's variable writes never propagate back. The self-test below calls
# it INSIDE a deliberate subshell instead, for the opposite reason: isolating
# a seeded violation's $FAILS from the real-repo verdict already computed.
LAST_CHECKED=0
check_tree() {
  local file headings headings_loaded hit lineno rest dir anchor num key hline n
  n=0
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    headings=""
    headings_loaded=0
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      lineno="${hit%%:*}"
      rest="${hit#*:}"

      dir=$(printf '%s' "$rest" | grep -oE '(above|below)$')
      [ -n "$dir" ] || continue
      anchor=$(printf '%s' "$rest" | sed -E 's/§//; s/[[:space:]]+(above|below)$//')
      anchor=$(printf '%s' "$anchor" | sed 's|^[[:space:]]*||; s|[[:space:]]*$||')
      [ -n "$anchor" ] || continue

      # A citation inside a table-of-contents/section-index bullet list
      # ("- §5 reserved — scope resolution is covered under §2 above") points
      # at the LIST ITEM above it, not at the distant real heading the same
      # number happens to title later in the file — resolving against real
      # headings here would misjudge the pointer's actual target. Skip: this
      # shape is a same-list cross-reference, not a heading-position claim.
      sed -n "${lineno}p" "$file" 2>/dev/null | grep -qE '^[[:space:]]*[-*][[:space:]]*§' && continue

      if [ "$headings_loaded" -eq 0 ]; then
        headings="$(_real_headings "$file")"
        headings_loaded=1
      fi

      case "$anchor" in
        [0-9]*)
          num=$(printf '%s' "$anchor" | sed 's|[^0-9.].*||; s|\.$||')
          hline=$(printf '%s\n' "$headings" | awk -F'\t' -v n="$num" '
            { if ($2 ~ ("^#{2,4} " n "[.):[:space:]]")) { print $1; exit } }')
          ;;
        *)
          key="$(_anchor_key "$anchor")"
          [ -n "$key" ] || continue
          hline=$(_first_match_line "$headings" "$key")
          ;;
      esac
      [ -n "$hline" ] || continue   # doesn't resolve in this file — check 10's job

      # A resolution landing on the heading that CONTAINS the citation itself
      # is a self-match artifact, not the citation's real target — a sentence
      # inside "### Step 4 — Candidate bar" citing "§Candidate bar (cited
      # below)" is pointing at content elsewhere with that name, not declaring
      # its own containing heading to be positioned above or below itself.
      containing="$(_containing_heading_line "$headings" "$lineno")"
      [ "$hline" = "$containing" ] && continue

      n=$((n + 1))
      if [ "$dir" = "above" ] && [ "$hline" -ge "$lineno" ]; then
        report_fail "$file:$lineno cites §$anchor above, but its heading is at line $hline ($([ "$hline" -eq "$lineno" ] && echo "same line" || echo "actually below this citation"))"
      elif [ "$dir" = "below" ] && [ "$hline" -le "$lineno" ]; then
        report_fail "$file:$lineno cites §$anchor below, but its heading is at line $hline ($([ "$hline" -eq "$lineno" ] && echo "same line" || echo "actually above this citation"))"
      fi
    done < <(grep -noE '§[^§`",;)]{1,60}[[:space:]](above|below)\b' "$file" 2>/dev/null)
  done < <(find skills agents -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
  LAST_CHECKED=$n
}

check_tree

if [ "$FAILS" -eq 0 ]; then
  echo "OK: every same-file directional section anchor ($LAST_CHECKED resolved citation(s) checked) points the way it claims"
fi

# --- self-test: red on a seeded reversed anchor, green on a correct one ------
TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
selftest_fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

TMPBASE="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMPBASE"' EXIT

new_tree() {
  local d
  d="$(mktemp -d "$TMPBASE/tree.XXXXXXXX")" || return 1
  mkdir -p "$d/skills/probe" "$d/agents"
  printf '%s\n' "$d"
}

# Runs check_tree in a subshell cd'd into the fixture — a subshell's FAILS and
# report_fail output never reach this process's own $FAILS, so probing a
# seeded violation here cannot corrupt the real-repo verdict computed above.
run_check() { ( cd "$1" && check_tree ) 2>&1; }

# Reversed: the citation claims "above" but the real heading is below it.
tree=$(new_tree)
cat > "$tree/skills/probe/wrong.md" <<'EOF'
# Probe

## Alpha section

text

The rule lives in §Beta section above — read it there.

## Beta section

more text
EOF
out=$(run_check "$tree")
if printf '%s\n' "$out" | grep -q 'cites §Beta section above'; then
  pass "self-test: a citation claiming 'above' whose heading is actually below is detected"
else
  selftest_fail "self-test: the seeded reversed-direction anchor was NOT detected. Output: $out"
fi

# Correct: the citation claims "below" and the real heading IS below it.
tree=$(new_tree)
cat > "$tree/skills/probe/right.md" <<'EOF'
# Probe

## Alpha section

The rule lives in §Beta section below — read it there.

text

## Beta section

more text
EOF
out=$(run_check "$tree")
if printf '%s\n' "$out" | grep -q 'FAIL:'; then
  selftest_fail "self-test: a correctly-directioned '§Beta section below' fixture false-positived. Output: $out"
else
  pass "self-test: a correctly-directioned anchor stays clean"
fi

# Non-directional "above" ("HIGH and above") must not false-positive even when
# it happens to look numeric-anchor-shaped and the number resolves to nothing.
tree=$(new_tree)
cat > "$tree/skills/probe/severity.md" <<'EOF'
# Probe

Inflating a finding games the §4.1 gate — which reads severity directly at HIGH and above, so inflation buys admission outright.
EOF
out=$(run_check "$tree")
if ! printf '%s\n' "$out" | grep -q 'FAIL:'; then
  pass "self-test: 'HIGH and above' (an unresolvable numeric pseudo-anchor) does not false-positive"
else
  selftest_fail "self-test: the severity-ordering false-positive guard failed. Output: $out"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ] || FAILS=$((FAILS + TESTS_FAILED))

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: directional section-anchor problem(s) and/or self-test failure(s)." >&2
  exit 1
fi
echo "OK: every same-file directional anchor resolves on the side it claims, and the self-test passes."
