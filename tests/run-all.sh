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

# Captured BEFORE the cd below: the worker re-entry at --run-one invokes this
# exact path, and a `$0` that was relative to the original working directory
# (e.g. `bash run-all.sh` from inside tests/, or `bash ../tests/run-all.sh`)
# resolves to nothing once the cwd has moved to $REPO_ROOT. An absolute path
# survives the cd.
SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

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
#
# Bounded watchdog: a suite with no timeout of its own can wedge this worker
# (and the parent's unbounded `wait`) forever, with no diagnostic pointing at
# which suite hung. `timeout`/`gtimeout` are not guaranteed present (BSD/macOS
# ships neither by default), so poll the child's liveness by PID instead — this
# works identically under bash 3.2 and GNU bash. rc=124 mirrors the coreutils
# `timeout` convention so the replay can tell a hang apart from a real failure.
if [ "${1:-}" = "--run-one" ]; then
  _idx="$2"; _suite="$3"; _outdir="$4"
  # 300, not 120: this guard exists to tell a HANG from a slow suite, and a hang
  # is unbounded, so headroom costs nothing while a tight cap kills real work.
  # Measured: obfuscation-matrix.sh runs 412 assertions, each spawning a guard
  # process — 39s locally, and a macOS CI runner got 265 of them done in 120s
  # (~186s for the full set). At 120 it was killed at two-thirds and reported as
  # a failure. The next-heaviest suites are 19s and 17s locally, so 300 leaves
  # every other suite an order of magnitude of slack.
  _suite_timeout="${TEST_SUITE_TIMEOUT_SECS:-300}"
  case "$_suite_timeout" in ''|*[!0-9]*) _suite_timeout=300 ;; esac
  bash "$_suite" </dev/null >"$_outdir/$_idx.log" 2>&1 &
  _child=$!
  _waited=0
  while kill -0 "$_child" 2>/dev/null; do
    if [ "$_waited" -ge "$_suite_timeout" ]; then
      kill -TERM "$_child" 2>/dev/null
      sleep 1
      kill -KILL "$_child" 2>/dev/null
      echo "run-all.sh: suite exceeded ${_suite_timeout}s (TEST_SUITE_TIMEOUT_SECS) — killed" >> "$_outdir/$_idx.log"
      printf '%s' "124" > "$_outdir/$_idx.rc"
      exit 0
    fi
    sleep 1
    _waited=$((_waited + 1))
  done
  wait "$_child"
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
# Split by signal rather than one EXIT/INT/TERM trap: a trap body that only
# cleans up does not itself terminate the process — bash resumes the script
# right after the interrupted command once the handler returns. That let a
# cancelled run fall through to the replay loop with $outdir already deleted,
# read zero suites, and print "All suites passed." at exit 0 (a cancelled CI
# job reading as a passing gate). EXIT still needs its own arm for the normal
# (non-signal) cleanup path.
trap 'rm -rf "$outdir"' EXIT
trap 'rm -rf "$outdir"; exit 130' INT
trap 'rm -rf "$outdir"; exit 143' TERM

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
  bash "$SELF_PATH" --run-one "$i" "$t" "$outdir" &
done < "$outdir/manifest"
wait

failed=0
replayed=0
failed_list=()
while IFS=$'\t' read -r i t; do
  echo "========================================================"
  echo "RUN: $t"
  echo "========================================================"
  cat "$outdir/$i.log"
  rc="$(cat "$outdir/$i.rc" 2>/dev/null || echo 1)"
  replayed=$((replayed + 1))
  if [ "$rc" = "0" ]; then
    echo
  else
    failed=$((failed + 1))
    failed_list+=("$t")
    echo "  ^^ SUITE FAILED" >&2
    echo
  fi
done < "$outdir/manifest"

# Guard the success message on having actually replayed every suite. Without
# this, any path that leaves the manifest short (an interrupted run whose trap
# does not exit, a truncated read) would fall through to "All suites passed."
# having verified nothing — the exact false-green shape this file exists to
# rule out.
if [ "$replayed" -ne "$total" ]; then
  echo "run-all.sh: replayed $replayed of $total suites — the run did not complete cleanly (interrupted?)." >&2
  exit 1
fi

echo "========================================================"
echo "Suites run:    $total"
echo "Suites failed: $failed"
echo "Wall time:     $((SECONDS - start))s"
if [ "$failed" -gt 0 ]; then
  printf '  FAILED: %s\n' "${failed_list[@]}" >&2
  exit 1
fi
echo "All suites passed."
