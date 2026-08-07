#!/usr/bin/env bash
# measure-run-load.sh — what one run of a skill actually loads, in words.
#
#   scripts/measure-run-load.sh R1
#   scripts/measure-run-load.sh --all
#   scripts/measure-run-load.sh --detail R2
#
# Static repository size and per-run cost are different quantities, and the gap
# between them is where the load axis lives. A file the orchestrator Reads once
# costs its words once. An agent body costs its words on every spawn, because the
# runtime injects it whole as the subagent's system prompt — so a 3,800-word body
# behind fifteen spawns outweighs a 7,000-word reference file read once, even
# though the reference file looks four times bigger on disk.
#
# This script holds no numbers. The composition of each reference run lives in
# scripts/run-load-profiles.tsv, where a disagreement about what a run loads is a
# one-line edit; everything here is arithmetic over that file.
#
# A manifest row naming a file that no longer exists is an error, not a zero.
# After a step that deletes or renames a loaded file, that failure is the point:
# it says the profile went stale rather than quietly reporting a smaller total.
#
# Portability: bash 3.2 / BSD userland as well as GNU. No arrays, no process
# substitution, no GNU-only flags. BSD `wc` left-pads its output, so every count
# is stripped before arithmetic.

set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Overridable so the suite can point the script at a fixture manifest, including
# one with a deliberately stale row — the failure path needs a test as much as the
# arithmetic does.
MANIFEST="${GENIRO_RUN_LOAD_MANIFEST:-$REPO_ROOT/scripts/run-load-profiles.tsv}"
TAB=$(printf '\t')

detail=0
want=""

while [ $# -gt 0 ]; do
  case "$1" in
    --detail) detail=1 ;;
    --all)    want="--all" ;;
    -h|--help)
      echo "usage: $(basename "$0") [--detail] <profile>|--all"
      exit 0
      ;;
    -*)
      echo "$(basename "$0"): unknown option: $1" >&2
      exit 64
      ;;
    *) want="$1" ;;
  esac
  shift
done

if [ ! -f "$MANIFEST" ]; then
  echo "$(basename "$0"): manifest not found: $MANIFEST" >&2
  exit 65
fi

# The single definition of "a data row". A `#` one column in is still a comment,
# and the profile list is built from this same stream — a comment that survived it
# would be read as profile names, one per word.
manifest_rows() {
  grep -v '^[[:space:]]*#' "$MANIFEST" | grep -v '^[[:space:]]*$'
}

# Four non-empty fields is the shape the arithmetic needs, and a row short one is
# not a smaller run — it is an unmeasured one. A blank first field belongs to no
# profile and so contributes to nothing at exit 0; a blank path scores nothing. Both
# report a smaller total than the run they name, which is the failure the stale-row
# check exists to prevent, so they get the same treatment: refuse to measure.
malformed=$(awk -F"$TAB" '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  NF != 4 || $1 == "" || $2 == "" || $3 == "" || $4 == "" { print "    line " NR ": " $0 }
' "$MANIFEST")
if [ -n "$malformed" ]; then
  echo "$(basename "$0"): malformed manifest rows in $MANIFEST — every data row needs four non-empty tab-separated fields:" >&2
  printf '%s\n' "$malformed" >&2
  exit 65
fi

profiles=$(manifest_rows | cut -d"$TAB" -f1 | sort -u)

# No discovered profiles means nothing was measured. `--all` would iterate zero
# times and exit 0 having printed nothing, and the suite reads that 0 as proof every
# path in every profile resolves — total staleness reported as a clean run.
if [ -z "$profiles" ]; then
  echo "$(basename "$0"): no profile rows in $MANIFEST — the file is empty or holds only comments" >&2
  exit 65
fi

if [ -z "$want" ]; then
  echo "usage: $(basename "$0") [--detail] <profile>|--all" >&2
  echo "profiles in $(basename "$MANIFEST"): $(echo "$profiles" | tr '\n' ' ')" >&2
  exit 64
fi

# One profile: emit `component<TAB>words<TAB>label` per manifest row, then let awk
# group it. Splitting measurement from aggregation keeps both halves obvious.
measure_profile() {
  _mp_profile="$1"

  manifest_rows | while IFS="$TAB" read -r p component mult path; do
    [ "$p" = "$_mp_profile" ] || continue
    # Validate the multiplier BEFORE using it. `[ "$mult" -gt 1 ]` exits 2 on a
    # non-integer, which reads as "not greater" and scores an x3 spawn count at 1x;
    # and a leading zero is not a valid decimal literal to $(( )), so `08` fails the
    # expansion and takes the row's whole `echo` with it — the row leaves the report
    # with no marker at all. A count the arithmetic cannot use is the same failure as
    # a path that no longer exists: the printed number describes a different run from
    # the one it names. So it takes the same route MISSING does.
    case "$mult" in
      ''|*[!0-9]*|0*)
        echo "BADMULT${TAB}0${TAB}$path (multiplier: $mult)"
        continue
        ;;
    esac
    if [ ! -f "$REPO_ROOT/$path" ]; then
      echo "MISSING${TAB}0${TAB}$path"
      continue
    fi
    # awk NF, not `wc -w`: GNU wc classifies words by locale, so a standalone `—` /
    # `§` / `·` counts under C.UTF-8 and not under C, and the same file measures ~3%
    # apart on two machines. Same rule as lint-skills.sh §words_in.
    words=$(awk '{ w += NF } END { print w + 0 }' "$REPO_ROOT/$path")
    if [ "$mult" -gt 1 ]; then
      echo "${component}${TAB}$((words * mult))${TAB}$path x$mult"
    else
      echo "${component}${TAB}${words}${TAB}$path"
    fi
  done
}

report_profile() {
  _rp_profile="$1"
  _rp_rows=$(measure_profile "$_rp_profile")

  if [ -z "$_rp_rows" ]; then
    echo "$(basename "$0"): no manifest rows for profile '$_rp_profile'" >&2
    return 65
  fi

  echo "Profile $_rp_profile"
  echo ""
  printf '  %-14s %6s %9s\n' component files words
  printf '  %-14s %6s %9s\n' -------------- ------ ---------

  # Fixed component order so two reports diff cleanly; any component the manifest
  # introduces later still prints, after the known ones.
  echo "$_rp_rows" | awk -F"$TAB" -v detail="$detail" '
    { words[$1] += $2; files[$1] += 1; rows[$1] = rows[$1] sprintf("      %-64s %8d\n", $3, $2) }
    END {
      n = split("orchestrator criteria agent-body MISSING BADMULT", known, " ")
      for (i = 1; i <= n; i++) {
        k = known[i]
        if (k in words) { emit(k); seen[k] = 1 }
      }
      for (k in words) if (!(k in seen)) emit(k)
      printf "  %-14s %6s %9s\n", "--------------", "------", "---------"
      printf "  %-14s %6d %9d\n", "total", tfiles, twords
    }
    function emit(k) {
      printf "  %-14s %6d %9d\n", k, files[k], words[k]
      if (detail == 1) printf "%s", rows[k]
      twords += words[k]; tfiles += files[k]
    }
  '

  _rp_rc=0

  # A MISSING component means the manifest points at a file that is gone.
  if echo "$_rp_rows" | grep -q "^MISSING${TAB}"; then
    echo ""
    echo "  stale manifest rows — these paths no longer exist:" >&2
    echo "$_rp_rows" | grep "^MISSING${TAB}" | cut -d"$TAB" -f3 | sed 's/^/    /' >&2
    _rp_rc=1
  fi

  # A BADMULT component means the row's spawn count is not a positive integer, so
  # its per-run cost is unknown rather than small.
  if echo "$_rp_rows" | grep -q "^BADMULT${TAB}"; then
    echo ""
    echo "  invalid multiplier — these rows carry no positive integer spawn count:" >&2
    echo "$_rp_rows" | grep "^BADMULT${TAB}" | cut -d"$TAB" -f3 | sed 's/^/    /' >&2
    _rp_rc=1
  fi

  return $_rp_rc
}

rc=0
if [ "$want" = "--all" ]; then
  first=1
  # Line-wise, not `for p in $profiles`: unquoted word-splitting turns any profile
  # name carrying a space — or any stray word that reached the list — into several
  # profiles, and measures a real one twice if a duplicate word matches it.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ $first -eq 1 ] || echo ""
    first=0
    report_profile "$p" || rc=1
  done <<< "$profiles"
else
  # Whole-line match. A substring test lets a prefix of a real profile (`R` against
  # a list holding `R1`) past the guard, so a mistyped profile dies further in with
  # the exit code a stale manifest uses instead of the documented 64.
  if ! printf '%s\n' "$profiles" | grep -qxF -- "$want"; then
    echo "$(basename "$0"): no such profile: $want" >&2
    echo "profiles: $(echo "$profiles" | tr '\n' ' ')" >&2
    exit 64
  fi
  report_profile "$want" || rc=1
fi

exit $rc
