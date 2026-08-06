#!/usr/bin/env bash
# Aggregate runner — executes every shell test suite under tests/ and reports a
# combined pass/fail. Exits non-zero if any suite fails, so CI can gate on it.
#
# Run: bash tests/run-all.sh              # parallel, one job per core
#      TEST_JOBS=1 bash tests/run-all.sh  # serial — use when debugging a suite
#
# Discovers tests/**/*.sh (this aggregator excluded). Each suite is expected to
# print its own results and exit non-zero on failure (the convention every
# tests/ suite already follows).
#
# Suites run CONCURRENTLY. They qualify because each is self-contained: no suite
# writes into the repo working tree, and every one that needs scratch space takes
# its own `mktemp -d`. Wall-clock is then the slowest single suite rather than
# the sum — the serial form spent ~6.5 minutes on ~40 seconds of critical path,
# because the cost is spread across many suites rather than concentrated in one.
# Output is captured per suite and replayed in discovery order at the end, so the
# report reads identically to the serial run; only the interleaving is gone.
#
# A new suite that writes to a FIXED path outside its own temp dir breaks this
# and will fail intermittently. Give it `mktemp -d` rather than serializing the
# runner around it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
SELF="$(basename "$0")"

# jq is a hard dependency of the memory/state helpers and the hook tests (which
# build tool-input JSON via jq). Fail fast with a clear message rather than
# letting every suite fail opaquely with "jq: command not found" — or, worse,
# letting a hook test feed empty stdin to a hook and silently invert its
# block/allow expectation.
if ! command -v jq >/dev/null 2>&1; then
  echo "tests/run-all.sh: jq is required to run the suite (memory/state helpers + hook tests depend on it)." >&2
  exit 1
fi

# --run-one is the worker re-entry, not a user-facing flag: xargs cannot call a
# shell function, so each job re-invokes this script. Writing the exit code to a
# sibling file is what lets the parent read a verdict per suite — xargs reports
# only whether the whole batch had a failure.
if [ "${1:-}" = "--run-one" ]; then
  _idx="$2"; _suite="$3"; _outdir="$4"
  bash "$_suite" </dev/null >"$_outdir/$_idx.log" 2>&1
  printf '%s' "$?" > "$_outdir/$_idx.rc"
  exit 0
fi

jobs="${TEST_JOBS:-}"
if [ -z "$jobs" ]; then
  jobs="$( { command -v nproc >/dev/null 2>&1 && nproc; } \
        || sysctl -n hw.ncpu 2>/dev/null \
        || echo 4 )"
fi
case "$jobs" in ''|*[!0-9]*) jobs=4 ;; esac
[ "$jobs" -lt 1 ] && jobs=1

outdir="$(mktemp -d)"
trap 'rm -rf "$outdir"' EXIT INT TERM

# Index each suite so the replay below can restore discovery order regardless of
# the order jobs actually finish in.
idx=0
: > "$outdir/manifest"
while IFS= read -r t; do
  [ "$(basename "$t")" = "$SELF" ] && continue
  idx=$((idx + 1))
  printf '%04d\t%s\n' "$idx" "$t" >> "$outdir/manifest"
done < <(find tests -name '*.sh' -type f | sort)

total=$idx
if [ "$total" -eq 0 ]; then
  echo "No test suites discovered under tests/ — check the runner's working directory." >&2
  exit 1
fi

echo "Running $total suites with $jobs parallel job(s)..."
start=$SECONDS

# A rolling window of background jobs rather than `xargs -P`: `wait -n` needs
# bash 4.3 and macOS ships 3.2, while `xargs -I` and `-n` interact differently
# across BSD and GNU. Polling `jobs -pr` works identically on both.
while IFS=$'\t' read -r i t; do
  while [ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$jobs" ]; do sleep 0.05; done
  bash "$0" --run-one "$i" "$t" "$outdir" &
done < "$outdir/manifest"
wait

failed=0
failed_list=()
while IFS=$'\t' read -r i t; do
  echo "========================================================"
  echo "RUN: $t"
  echo "========================================================"
  cat "$outdir/$i.log"
  rc="$(cat "$outdir/$i.rc" 2>/dev/null || echo 1)"
  if [ "$rc" = "0" ]; then
    echo
  else
    failed=$((failed + 1))
    failed_list+=("$t")
    echo "  ^^ SUITE FAILED" >&2
    echo
  fi
done < "$outdir/manifest"

echo "========================================================"
echo "Suites run:    $total"
echo "Suites failed: $failed"
echo "Wall time:     $((SECONDS - start))s"
if [ "$failed" -gt 0 ]; then
  printf '  FAILED: %s\n' "${failed_list[@]}" >&2
  exit 1
fi
echo "All suites passed."
