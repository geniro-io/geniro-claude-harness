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
if [ "$failed" -gt 0 ]; then
  printf '  FAILED: %s\n' "${failed_list[@]}" >&2
  exit 1
fi
echo "All suites passed."
