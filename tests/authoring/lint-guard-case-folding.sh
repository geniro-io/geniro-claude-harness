#!/usr/bin/env bash
# Guards hooks/ and lib/ against a case-sensitive `.geniro` / `safety.json` /
# destructive-command-word matcher — the class behind the 2026-08-23 audit's
# T0-1 through T0-4 bypasses.
#
# Run: bash tests/authoring/lint-guard-case-folding.sh
#
# Why this exists: `.GENIRO` and `.geniro` are the same inode on a
# case-insensitive filesystem (macOS's default), and `RM`/`Rm`/`GIT`/`Git` all
# resolve on PATH exactly like their lowercase spelling. A guard whose matcher
# is a bare-lowercase regex misses every uppercase variant — `Write
# .GENIRO/safety.json`, `rm -rf .Geniro`, `RM -rf .geniro`, `Git push --force`
# all returned rc 0 (measured by executing the shipped hooks, not by reading
# them). Each of the four sites was fixed by ONE of two shapes:
#   - the whole grep call gets `-i` (`grep -qiE`, `grep -oiE`) — used where
#     folding the surrounding flags/subcommand text does no harm, or
#   - only the specific word is folded via a bracket class (`[gG][iI][tT]`)
#     — used where an adjacent FLAG must stay case-sensitive (block-dangerous-git.sh:
#     `--FORCE` is not a real git flag, so folding it would invent false
#     positives), or
#   - the compared VARIABLE is lowered once, upstream, via
#     `tr '[:upper:]' '[:lower:]'` (as `_geniro_normalize_path` and
#     `find_glob_covers_geniro`/`find_span_targets_geniro` do) — every match
#     against that variable inherits the fold for free.
#
# What this checks, mechanically: every line in hooks/*.sh or lib/*.sh whose
# grep/case pattern contains the literal `.geniro`, `safety.json`, or one of
# the destructive command words (rm, mv, rmdir, find, rsync, git) spelled as a
# bare lowercase token PASSES if the SAME line carries `-i` on the grep call, a
# same-line bracket-class fold, OR the enclosing function already ran
# `tr '[:upper:]' '[:lower:]'` on some variable before this line (tracked by
# function body, reset at each new `name() {`). It is a heuristic pinned to the
# three fix shapes actually shipped, not a formal prover — a new matcher that
# invents a fourth shape needs a matching update here, the same way
# lint-shipped-shas.sh's resolution check is a heuristic pinned to its own
# fix shape.
#
# Deliberately NOT flagged (false-positive exclusions, not loopholes):
#   - lines that are comments (leading `#` after trimming)
#   - the `tr '[:upper:]' '[:lower:]'` fold line itself
#   - `case "$cmdword"` / `"$cmdword"` comparisons — these compare against a
#     variable holding the ALREADY-MATCHED word, not a fresh literal
#   - a bare filename mention with no `[[:space:]]` boundary immediately after
#     the command word (comments, prose, path examples)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Emits one "<file>:<line>:<text>" per unfolded case-sensitive matcher line
# found in the given file.
scan_file() {
  local file="$1"
  awk -v FILE="$file" '
    function trimmed(s) { sub(/^[[:space:]]+/, "", s); return s }
    function is_comment(s) { return (substr(trimmed(s), 1, 1) == "#") }
    function has_ifold(s) {
      # grep called with an -i somewhere in its flag cluster: -qi, -qiE, -iE, -oiE …
      return (s ~ /grep[[:space:]]+-[A-Za-z]*i[A-Za-z]*/)
    }
    function has_bracket_fold(s) {
      # A same-line bracket-class case fold, e.g. [gG][iI][tT] or [rR].
      return (s ~ /\[[a-z][A-Z]\]|\[[A-Z][a-z]\]/)
    }
    # Only a line that is ACTUALLY deciding something (a grep -q/-o call, or a
    # `case … in` glob match) is a matcher. Ordinary path construction
    # (`log="$root/.geniro/x"`, a message string, a comment) mentions
    # `.geniro`/`safety.json` far more often than it MATCHES against them, and
    # is not this class of bug.
    function is_matcher_line(s) {
      return (s ~ /grep[[:space:]]+-[A-Za-z]*[qo][A-Za-z]*/ || s ~ /(^|[^A-Za-z0-9_])case[[:space:]]/)
    }
    BEGIN { lowered = 0 }
    {
      line = $0
      # Reset per-function tracking at a new top-level function definition.
      if (line ~ /^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{/) { lowered = 0 }
      if (line ~ /tr[[:space:]]+.\[:upper:\].[[:space:]]+.\[:lower:\]./) { lowered = 1; next }
      # A call to the shared path-normalizer (which case-folds internally)
      # lowers whatever variable it assigns into for the rest of this
      # function body — every match against that variable below inherits it.
      if (line ~ /_geniro_normalize_path/) { lowered = 1; next }
      if (is_comment(line)) next
      if (line ~ /"\$cmdword"/) next
      if (!is_matcher_line(line)) next

      needs_fold = 0
      if ((line ~ /\.geniro/) && !has_ifold(line) && !lowered) needs_fold = 1
      if ((line ~ /safety\.json/) && !has_ifold(line) && !lowered) needs_fold = 1
      # Destructive command word as a bare token immediately followed by a
      # whitespace-class boundary inside a regex pattern — the shape every
      # span-extraction / jqless-fallback matcher in this repo uses.
      if (line ~ /(^|[^A-Za-z0-9_\[])(rm|mv|rmdir|find|rsync|git)\[\[:space:\]\]/) {
        if (!has_ifold(line) && !has_bracket_fold(line) && !lowered) needs_fold = 1
      }
      if (needs_fold) {
        printf "%s:%d:%s\n", FILE, NR, trimmed(line)
      }
    }
  ' "$file"
}

HITS=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  out="$(scan_file "$f")"
  [ -n "$out" ] && HITS="${HITS}${out}
"
done < <(git ls-files 'hooks/*.sh' 'lib/*.sh')

if [ -z "$(printf '%s' "$HITS" | tr -d '[:space:]')" ]; then
  pass "no unfolded .geniro/safety.json/command-word matcher in hooks/ or lib/"
else
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    fail "case-sensitive matcher not folded: $hit"
  done <<< "$HITS"
fi

# --- self-test: red on a seeded violation, green on the fix ------------------
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

cat > "$SCRATCH/seeded-violation.sh" <<'EOF'
#!/usr/bin/env bash
check_it() {
  local p="$1"
  if echo "$p" | grep -qE '(^|/)\.geniro/safety\.json$'; then
    return 0
  fi
  return 1
}
EOF
seeded_hits="$(scan_file "$SCRATCH/seeded-violation.sh")"
if [ -n "$seeded_hits" ]; then
  pass "seeded case-sensitive .geniro matcher is detected"
else
  fail "seeded violation NOT detected — the lint would miss a real regression"
fi

cat > "$SCRATCH/folded-i.sh" <<'EOF'
#!/usr/bin/env bash
check_it() {
  local p="$1"
  if echo "$p" | grep -qiE '(^|/)\.geniro/safety\.json$'; then
    return 0
  fi
  return 1
}
EOF
folded_hits="$(scan_file "$SCRATCH/folded-i.sh")"
if [ -z "$folded_hits" ]; then
  pass "a -i-folded .geniro matcher does not false-positive"
else
  fail "a properly -i-folded matcher was wrongly flagged: $folded_hits"
fi

cat > "$SCRATCH/folded-normalize.sh" <<'EOF'
#!/usr/bin/env bash
_geniro_normalize_path() {
  local p="${1:-}"
  p="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
  echo "$p" | grep -qE '(^|/)\.geniro/safety\.json$'
}
EOF
normalize_hits="$(scan_file "$SCRATCH/folded-normalize.sh")"
if [ -z "$normalize_hits" ]; then
  pass "a pre-lowered-variable matcher (post-tr, same function) does not false-positive"
else
  fail "a matcher against an already-lowered variable was wrongly flagged: $normalize_hits"
fi

cat > "$SCRATCH/seeded-command-word.sh" <<'EOF'
#!/usr/bin/env bash
RM_SPANS=$(printf '%s' "$PADDED" | grep -oE '(^|[[:space:]])rm[[:space:]]+[^|;&]*' || true)
EOF
cmdword_hits="$(scan_file "$SCRATCH/seeded-command-word.sh")"
if [ -n "$cmdword_hits" ]; then
  pass "seeded case-sensitive command-word matcher is detected"
else
  fail "seeded command-word violation NOT detected"
fi

cat > "$SCRATCH/folded-command-word.sh" <<'EOF'
#!/usr/bin/env bash
RM_SPANS=$(printf '%s' "$PADDED" | grep -oiE '(^|[[:space:]])rm[[:space:]]+[^|;&]*' || true)
EOF
cmdword_ok_hits="$(scan_file "$SCRATCH/folded-command-word.sh")"
if [ -z "$cmdword_ok_hits" ]; then
  pass "a -i-folded command-word matcher does not false-positive"
else
  fail "a properly -i-folded command-word matcher was wrongly flagged: $cmdword_ok_hits"
fi

rm -rf "$SCRATCH"
trap - EXIT

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
