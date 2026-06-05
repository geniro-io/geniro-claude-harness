#!/usr/bin/env bash
# Aggregate runner — executes every shell test suite under tests/ and reports a
# combined pass/fail. Exits non-zero if any suite fails, so CI can gate on it.
#
# Run: bash tests/run-all.sh
#
# Discovers tests/**/*.sh (this aggregator excluded). Each suite is expected to
# print its own results and exit non-zero on failure (the convention every
# tests/ suite already follows).

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

total=0
failed=0
failed_list=()

while IFS= read -r t; do
  [ "$(basename "$t")" = "$SELF" ] && continue
  total=$((total + 1))
  echo "========================================================"
  echo "RUN: $t"
  echo "========================================================"
  if bash "$t"; then
    echo
  else
    failed=$((failed + 1))
    failed_list+=("$t")
    echo "  ^^ SUITE FAILED" >&2
    echo
  fi
done < <(find tests -name '*.sh' -type f | sort)

echo "========================================================"
echo "Suites run:    $total"
echo "Suites failed: $failed"
if [ "$total" -eq 0 ]; then
  echo "No test suites discovered under tests/ — check the runner's working directory." >&2
  exit 1
fi
if [ "$failed" -gt 0 ]; then
  printf '  FAILED: %s\n' "${failed_list[@]}" >&2
  exit 1
fi
echo "All suites passed."
