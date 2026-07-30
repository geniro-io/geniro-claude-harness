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

profiles=$(grep -v '^#' "$MANIFEST" | grep -v '^[[:space:]]*$' | cut -d"$TAB" -f1 | sort -u)

if [ -z "$want" ]; then
  echo "usage: $(basename "$0") [--detail] <profile>|--all" >&2
  echo "profiles in $(basename "$MANIFEST"): $(echo "$profiles" | tr '\n' ' ')" >&2
  exit 64
fi

# One profile: emit `component<TAB>words<TAB>label` per manifest row, then let awk
# group it. Splitting measurement from aggregation keeps both halves obvious.
measure_profile() {
  _mp_profile="$1"
  _mp_missing=0

  grep -v '^#' "$MANIFEST" | grep -v '^[[:space:]]*$' | while IFS="$TAB" read -r p component mult path; do
    [ "$p" = "$_mp_profile" ] || continue
    if [ ! -f "$REPO_ROOT/$path" ]; then
      echo "MISSING${TAB}0${TAB}$path"
      continue
    fi
    words=$(wc -w < "$REPO_ROOT/$path" | tr -d '[:space:]')
    if [ "$mult" -gt 1 ] 2>/dev/null; then
      echo "${component}${TAB}$((words * mult))${TAB}$path x$mult"
    else
      echo "${component}${TAB}${words}${TAB}$path"
    fi
  done
  return $_mp_missing
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
    { order[$1] = order[$1]; words[$1] += $2; files[$1] += 1; rows[$1] = rows[$1] sprintf("      %-64s %8d\n", $3, $2) }
    END {
      n = split("orchestrator criteria agent-body MISSING", known, " ")
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

  # A MISSING component means the manifest points at a file that is gone.
  if echo "$_rp_rows" | grep -q "^MISSING${TAB}"; then
    echo ""
    echo "  stale manifest rows — these paths no longer exist:" >&2
    echo "$_rp_rows" | grep "^MISSING${TAB}" | cut -d"$TAB" -f3 | sed 's/^/    /' >&2
    return 1
  fi
  return 0
}

rc=0
if [ "$want" = "--all" ]; then
  first=1
  for p in $profiles; do
    [ $first -eq 1 ] || echo ""
    first=0
    report_profile "$p" || rc=1
  done
else
  case "$profiles" in
    *"$want"*) ;;
    *)
      echo "$(basename "$0"): no such profile: $want" >&2
      echo "profiles: $(echo "$profiles" | tr '\n' ' ')" >&2
      exit 64
      ;;
  esac
  report_profile "$want" || rc=1
fi

exit $rc
