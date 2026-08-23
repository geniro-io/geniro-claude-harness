#!/usr/bin/env bash
# Guards every `set -o pipefail` (or `set -euo pipefail`) file against
# `echo|printf … | grep -q` — the class behind the 2026-08-23 audit's
# T0-5/T0-6/T0-7 fail-open bug.
#
# Run: bash tests/authoring/lint-pipefail-grep.sh
#
# Why this exists: under `pipefail`, `echo "$X" | grep -q PATTERN` reports
# **141**, not 1, when grep MATCHES early — grep exits at the first match, the
# echo/printf producer dies on SIGPIPE, and the pipeline's own exit status
# becomes 141 (measured: force-push alone blocked at rc 2, the identical
# force-push as line 1 of a 114KB command payload passed at rc 0). An `if …|
# grep -q…; then` reads any nonzero rc as "no match" — so a MATCH on large
# input silently reads as a miss, and the SAME bug on a NEGATED gate
# (`if ! …| grep -q…; then return 0; fi`) makes `!` turn 141 into true,
# silently taking the "nothing found" branch.
#
# The fix shape already lives in this repo with its rationale at
# file-protection.sh's `is_disposable_tree`: a here-string
# (`grep -qE 'PATTERN' <<< "$X"`) never opens a pipe, so grep can never
# SIGPIPE its producer — there is no producer. That is the ONLY allowed shape
# for this class; `echo|printf … | grep -q` in a pipefail-setting file is
# always the bug, never a legitimate use.
#
# Coverage: every hooks/*.sh and lib/*.sh file that itself runs
# `set -o pipefail` / `set -euo pipefail`. lib/write-vectors.sh does not set
# pipefail itself but is always SOURCED into a file that does, so it is
# checked unconditionally alongside the pipefail-setting set — leaving it out
# would silently exclude the file the T0-6/T0-7 canonical fix actually lives
# in.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Emits one "<file>:<line>:<text>" per `echo|printf … | grep -q…` site.
scan_file() {
  local file="$1"
  grep -nE '(^|[^A-Za-z0-9_])(echo|printf)[[:space:]].*\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q' "$file" \
    | grep -v '^[0-9]*:[[:space:]]*#' \
    | sed "s#^#${file}:#"
}

pipefail_setting_files() {
  git ls-files 'hooks/*.sh' 'lib/*.sh' | while IFS= read -r f; do
    [ -f "$f" ] || continue
    # A `set` line naming pipefail — `set -euo pipefail`, `set -o pipefail`,
    # or any other flag-cluster spelling. The word only appears in this
    # shape's own `set` invocation anywhere in this repo (verified: no file
    # mentions "pipefail" without a `set` line naming it), so testing for the
    # word on a `set` line is exact, not a heuristic.
    if grep -qE '^[[:space:]]*set[[:space:]].*pipefail' "$f" 2>/dev/null; then
      printf '%s\n' "$f"
    fi
  done
}

# --- the lint: every pipefail-setting file, plus lib/write-vectors.sh -------
FILES="$(pipefail_setting_files)"
if ! printf '%s\n' "$FILES" | grep -qx 'lib/write-vectors.sh'; then
  FILES="${FILES}
lib/write-vectors.sh"
fi

HITS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  out="$(scan_file "$f")"
  [ -n "$out" ] && HITS="${HITS}${out}
"
done <<< "$FILES"

if [ -z "$(printf '%s' "$HITS" | tr -d '[:space:]')" ]; then
  pass "no echo|printf … | grep -q site in any pipefail-setting hooks/lib file"
else
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    fail "pipe-fed grep -q under pipefail (use a here-string instead): $hit"
  done <<< "$HITS"
fi

# --- self-test: red on a seeded violation, green on the fix ------------------
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

VIOLATION="$SCRATCH/seeded-pipe.sh"
cat > "$VIOLATION" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
check() {
  if echo "$1" | grep -qE 'force'; then
    return 0
  fi
  return 1
}
EOF
seeded_hits="$(scan_file "$VIOLATION")"
if [ -n "$seeded_hits" ]; then
  pass "seeded echo|grep -q pipe is detected"
else
  fail "seeded violation NOT detected — the lint would miss a real regression"
fi

FIXED="$SCRATCH/seeded-herestring.sh"
cat > "$FIXED" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
check() {
  if grep -qE 'force' <<< "$1"; then
    return 0
  fi
  return 1
}
EOF
fixed_hits="$(scan_file "$FIXED")"
if [ -z "$fixed_hits" ]; then
  pass "the here-string form does not false-positive"
else
  fail "the here-string form was wrongly flagged: $fixed_hits"
fi

# A file that does NOT set pipefail is out of scope for this class (a
# `grep -q` pipe there can still misread on a huge match, but without
# pipefail the pipeline's exit status is `tail`/the last command's, not
# grep's — a different bug, not this one).
NO_PIPEFAIL="$SCRATCH/no-pipefail.sh"
cat > "$NO_PIPEFAIL" <<'EOF'
#!/usr/bin/env bash
set -eu
check() {
  if echo "$1" | grep -qE 'force'; then
    return 0
  fi
  return 1
}
EOF
if grep -qE '^[[:space:]]*set[[:space:]].*pipefail' "$NO_PIPEFAIL"; then
  fail "the pipefail-file detector wrongly matched a file with no pipefail"
else
  pass "a file with no pipefail is correctly excluded from the pipefail-file set"
fi

rm -rf "$SCRATCH"
trap - EXIT

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
