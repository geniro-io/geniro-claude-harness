#!/usr/bin/env bash
# T4-62 (plugin-audit 2026-10-19) — no tracked shell script assigns a variable it
# never reads (ShellCheck SC2034).
#
# Run: bash tests/authoring/lint-unused-variables.sh
#
# Why this exists: `N_FACETS="$(jq '.facets | length' ...)"` in evals/loop/run.sh
# ran a subprocess on every run for a value nothing read. ShellCheck reports it
# at warning severity, which CI runs as an advisory step that never fails the
# build, so the one real finding sat in a log nobody opens. SC2034 alone is
# promoted to a failure here: the tree is clean for it, an unused assignment is
# dead code (or a typo'd name that the intended reader never sees), and the
# check is decidable by a tool rather than by taste.
#
# Scope: the path set CI's ShellCheck step lints — lib hooks tests evals cursor
# scripts — taken from git so ignored scratch files never count (the audit's
# own battery swept 490 gitignored files into a false-positive report).
#
# ShellCheck is a dev/CI tool, not a runtime dependency. When it is not
# installed this suite says so and passes; CI installs it in the ShellCheck job.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "SKIP: shellcheck is not installed — SC2034 (unused variable) not checked here; CI's ShellCheck job installs it"
  exit 0
fi

SC_ARGS=(--include=SC2034 --severity=warning -f gcc)

# <files...> -> `file:line:col: warning: <message> [SC2034]` per unused assignment.
_unused() {
  [ "$#" -gt 0 ] || return 0
  shellcheck "${SC_ARGS[@]}" "$@" 2>/dev/null
}

# Tracked and not-yet-committed (non-ignored) scripts; find when this is not a git tree.
if git rev-parse --git-dir >/dev/null 2>&1; then
  files="$(git ls-files -co --exclude-standard lib hooks tests evals cursor scripts 2>/dev/null | grep '\.sh$' || true)"
else
  files="$(find lib hooks tests evals cursor scripts -name '*.sh' -type f 2>/dev/null)"
fi

checked="$(printf '%s\n' "$files" | grep -c . || true)"
if [ "$checked" -eq 0 ]; then
  report_fail "no shell scripts found under lib hooks tests evals cursor scripts — the file list is broken, so this check would pass vacuously"
else
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    report_fail "$line — delete the assignment, or use the variable (an unused value is dead work or a misspelled name)"
  done < <(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 shellcheck "${SC_ARGS[@]}" 2>/dev/null)
  if [ "$FAILS" -eq 0 ]; then
    echo "OK: no unused variable (SC2034) in $checked tracked shell script(s)"
  fi
fi

# --- self-test: red on an unused assignment, green on a read, an export and a sourced-library var ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT

cat > "$SELFTEST_DIR/violation.sh" <<'EOF'
#!/usr/bin/env bash
N_FACETS="$(echo 3)"
echo done
EOF
cat > "$SELFTEST_DIR/clean.sh" <<'EOF'
#!/usr/bin/env bash
used="$(echo 3)"
echo "$used"
export EXPORTED_FOR_CHILDREN=1
# shellcheck disable=SC2034  # read by the sourcing script
READ_BY_CALLER=1
EOF

v="$(_unused "$SELFTEST_DIR/violation.sh" | grep -c 'SC2034' || true)"
if [ "$v" -eq 1 ]; then
  echo "OK: self-test — a seeded unused assignment (N_FACETS) is detected"
else
  report_fail "self-test — expected 1 SC2034 hit on the seeded violation, got $v"
fi

c="$(_unused "$SELFTEST_DIR/clean.sh" | grep -c 'SC2034' || true)"
if [ "$c" -eq 0 ]; then
  echo "OK: self-test — a read variable, an export and an explicitly disabled caller-read variable do not false-positive"
else
  report_fail "self-test — the clean fixture false-positived ($c hit(s))"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS unused-variable problem(s)." >&2
  exit 1
fi
echo "OK: no tracked shell script carries an unused variable."
