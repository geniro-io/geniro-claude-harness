#!/usr/bin/env bash
# Guards every `set -o pipefail` (or `set -euo pipefail`) file, and every lib
# it (transitively) sources, against `<producer> … | grep -q` — the class
# behind the 2026-08-23 audit's T0-5/T0-6/T0-7 fail-open bug.
#
# Run: bash tests/authoring/lint-pipefail-grep.sh
#
# Why this exists: under `pipefail`, `echo "$X" | grep -q PATTERN` reports
# **141**, not 1, when grep MATCHES early — grep exits at the first match, the
# producer dies on SIGPIPE, and the pipeline's own exit status becomes 141
# (measured: force-push alone blocked at rc 2, the identical force-push as
# line 1 of a 114KB command payload passed at rc 0). An `if …| grep -q…; then`
# reads any nonzero rc as "no match" — so a MATCH on large input silently
# reads as a miss, and the SAME bug on a NEGATED gate
# (`if ! …| grep -q…; then return 0; fi`) makes `!` turn 141 into true,
# silently taking the "nothing found" branch. The producer need not be
# echo/printf — `git worktree list | awk … | grep -qxF` (D5b-22) dies the
# identical way; whatever sits immediately before the pipe into `grep -q` is
# the exposed process, so the scan matches on the pipe into `grep -q` itself,
# not on any particular producer command.
#
# The fix shape already lives in this repo with its rationale at
# file-protection.sh's `is_disposable_tree`: a here-string
# (`grep -qE 'PATTERN' <<< "$X"`) never opens a pipe, so grep can never
# SIGPIPE its producer — there is no producer. That is the ONLY allowed shape
# for this class; `<producer> … | grep -q` in a pipefail-reachable file is
# always the bug, never a legitimate use.
#
# Coverage: every hooks/*.sh and lib/*.sh file that itself runs
# `set -o pipefail` / `set -euo pipefail`, PLUS every lib/*.sh file any of
# those (transitively) `source` — it runs in the SAME shell, inheriting the
# pipefail setting, so it is exactly as exposed as the file that sourced it
# (D5b-22: lib/validate-state-file.sh has no pipefail of its own but is
# sourced by hooks/session-start-restore.sh, which does). lib/write-vectors.sh
# is additionally checked unconditionally, since some callers reach it through
# indirection this scan's static source-tracing may not catch — leaving it out
# would silently exclude the file the T0-6/T0-7 canonical fix actually lives
# in.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Emits one "<file>:<line>:<text>" per "<producer> … | grep -q…" site. Any
# producer, not just echo/printf (D5b-22) — the only requirement is an actual
# `|` right before `grep -...q`; a here-string never has one and is correctly
# never matched.
scan_file() {
  local file="$1"
  grep -nE '\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q' "$file" \
    | grep -v '^[0-9]*:[[:space:]]*#' \
    | sed "s#^#${file}:#"
}

# Every lib/*.sh basename a file `source`s, ONE hop — not transitively; the
# caller below loops this to a fixed point. Two sourcing shapes exist in this
# codebase:
#   (a) the filename is literally on the `source` line itself, e.g.
#       `source "$_as_script_dir/repo-root.sh"` or
#       `source "${CLAUDE_PLUGIN_ROOT:-.}/lib/write-vectors.sh"`.
#   (b) the whole path is a bare variable, e.g. `source "$_vsf_helper"`, whose
#       OWN assignment elsewhere in the SAME file carries the literal
#       filename (`_vsf_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/validate-state-file.sh"`).
sourced_libs_direct() {
  local file="$1"
  {
    grep -oE 'source[[:space:]]+"[^"]*[A-Za-z0-9_-]+\.sh"' "$file" 2>/dev/null \
      | grep -oE '[A-Za-z0-9_-]+\.sh"$' | tr -d '"'

    grep -oE 'source[[:space:]]+"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"' "$file" 2>/dev/null \
      | grep -oE '[A-Za-z_][A-Za-z0-9_]*' \
      | while IFS= read -r var; do
          [ "$var" = "source" ] && continue
          grep -E "^[[:space:]]*${var}=" "$file" 2>/dev/null \
            | grep -oE '[A-Za-z0-9_-]+\.sh"' | tr -d '"'
        done
  } | sort -u
}

# Fixed-point closure over sourced_libs_direct: a lib this file sources may
# itself source another lib (hook -> lib A -> lib B), and all of them run in
# the same pipefail-inheriting shell. `seen` is a `|`-delimited set (bash 3.2
# has no associative arrays) so a cycle or a diamond dependency terminates
# instead of looping forever or double-counting.
all_sourced_libs() {
  local file="$1" seen="" queue next lib
  queue="$(sourced_libs_direct "$file")"
  while [ -n "$queue" ]; do
    next=""
    while IFS= read -r lib; do
      [ -z "$lib" ] && continue
      case "$seen" in *"|${lib}|"*) continue ;; esac
      seen="${seen}|${lib}|"
      [ -f "lib/${lib}" ] || continue
      next="${next}
$(sourced_libs_direct "lib/${lib}")"
    done <<< "$queue"
    queue="$next"
  done
  printf '%s' "$seen" | tr '|' '\n' | grep -v '^$' | sort -u
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

# --- the lint: every pipefail-setting file, plus lib/write-vectors.sh,
# plus every lib any of those (transitively) source ---------------------------
FILES="$(pipefail_setting_files)"
if ! printf '%s\n' "$FILES" | grep -qx 'lib/write-vectors.sh'; then
  FILES="${FILES}
lib/write-vectors.sh"
fi

SOURCED=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  while IFS= read -r lib; do
    [ -z "$lib" ] && continue
    SOURCED="${SOURCED}
lib/${lib}"
  done <<< "$(all_sourced_libs "$f")"
done <<< "$FILES"
FILES="$(printf '%s\n%s\n' "$FILES" "$SOURCED" | grep -v '^$' | sort -u)"

HITS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  out="$(scan_file "$f")"
  [ -n "$out" ] && HITS="${HITS}${out}
"
done <<< "$FILES"

if [ -z "$(printf '%s' "$HITS" | tr -d '[:space:]')" ]; then
  pass "no <producer> … | grep -q site in any pipefail-reachable hooks/lib file"
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

# --- self-test: a NON-echo/printf producer is detected too (D5b-22) ---------
# `git worktree list | awk … | grep -qxF` — the real shape at
# lib/validate-state-file.sh:248-250. Neither stage is echo or printf.
NONPRINTF_VIOLATION="$SCRATCH/seeded-awk-pipe.sh"
cat > "$NONPRINTF_VIOLATION" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
check_worktree() {
  if git worktree list --porcelain \
       | awk '/^worktree / {sub(/^worktree /, ""); print}' \
       | grep -qxF "$1"; then
    return 0
  fi
  return 1
}
EOF
nonprintf_hits="$(scan_file "$NONPRINTF_VIOLATION")"
if [ -n "$nonprintf_hits" ]; then
  pass "a non-echo/printf producer (awk) piped into grep -q is detected"
else
  fail "seeded awk|grep -q pipe NOT detected — the lint would miss a non-echo/printf producer"
fi

NONPRINTF_FIXED="$SCRATCH/seeded-awk-herestring.sh"
cat > "$NONPRINTF_FIXED" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
check_worktree() {
  local list
  list="$(git worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print}')"
  if grep -qxF "$1" <<< "$list"; then
    return 0
  fi
  return 1
}
EOF
nonprintf_fixed_hits="$(scan_file "$NONPRINTF_FIXED")"
if [ -z "$nonprintf_fixed_hits" ]; then
  pass "the awk-then-here-string fix does not false-positive"
else
  fail "the awk-then-here-string fix was wrongly flagged: $nonprintf_fixed_hits"
fi

# --- self-test: a lib SOURCED by a pipefail file (no pipefail of its own) is
# pulled into scan scope, same shape as D5b-22's real example
# (lib/validate-state-file.sh sourced by hooks/session-start-restore.sh) -----
mkdir -p "$SCRATCH/lib"
cat > "$SCRATCH/lib/seeded-sourced-lib.sh" <<'EOF'
#!/usr/bin/env bash
# Sourced by a pipefail-setting file; carries no pipefail of its own.
check() {
  printf '%s\n' "$1" | grep -qE '^ok$'
}
EOF
SEEDED_HOOK="$SCRATCH/seeded-hook-direct.sh"
cat > "$SEEDED_HOOK" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
_seeded_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$_seeded_script_dir/seeded-sourced-lib.sh"
EOF
discovered="$(cd "$SCRATCH" && all_sourced_libs "$(basename "$SEEDED_HOOK")")"
if printf '%s\n' "$discovered" | grep -qx 'seeded-sourced-lib.sh'; then
  pass "a lib sourced directly (filename on the source line) is discovered"
else
  fail "direct-source discovery missed seeded-sourced-lib.sh — discovered: '$discovered'"
fi

# The variable-indirection shape (`source "$var"`, filename on a DIFFERENT
# line) — the exact shape hooks/session-start-restore.sh uses for
# lib/validate-state-file.sh.
SEEDED_HOOK_INDIRECT="$SCRATCH/seeded-hook-indirect.sh"
cat > "$SEEDED_HOOK_INDIRECT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
_seeded_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/seeded-sourced-lib.sh"
source "$_seeded_helper" 2>/dev/null || true
EOF
discovered_indirect="$(all_sourced_libs "$SEEDED_HOOK_INDIRECT")"
if printf '%s\n' "$discovered_indirect" | grep -qx 'seeded-sourced-lib.sh'; then
  pass "a lib sourced indirectly (via a variable, filename on a different line) is discovered"
else
  fail "indirect-source discovery missed seeded-sourced-lib.sh — discovered: '$discovered_indirect'"
fi

# End to end: the discovered lib's OWN printf|grep -q violation is flagged —
# proves the discovery feeds the actual scan, not just a standalone lookup.
seeded_lib_hits="$(scan_file "$SCRATCH/lib/seeded-sourced-lib.sh")"
if [ -n "$seeded_lib_hits" ]; then
  pass "the discovered sourced-lib's own printf|grep -q violation is flagged by scan_file"
else
  fail "scan_file missed the violation inside the discovered sourced lib"
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
