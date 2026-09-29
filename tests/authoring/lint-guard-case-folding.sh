#!/usr/bin/env bash
# Guards hooks/ and lib/ against a case-sensitive `.geniro` / `safety.json` /
# command-word matcher — the class behind the 2026-08-23 audit's T0-1 through
# T0-4 bypasses.
#
# Run: bash tests/authoring/lint-guard-case-folding.sh
#
# Why this exists: `.GENIRO` and `.geniro` are the same directory on a
# case-insensitive filesystem (macOS's default), and `GIT`/`Git`/`RM` resolve
# on PATH exactly like their lowercase spelling. A matcher written as a bare
# lowercase regex misses every uppercase variant. Three fix shapes pass:
#   - the grep call carries `-i` (`grep -qi`, `grep -oiE`);
#   - only the word is folded via a bracket class (`[gG][iI][tT]`), for when an
#     adjacent flag must stay case-sensitive;
#   - the compared variable was lowered earlier in the same function via
#     `tr '[:upper:]' '[:lower:]'`, so every match against it inherits the fold.
#
# What this checks, mechanically: every grep -q/-o, `case`, or sed-normalizer
# line in hooks/*.sh or lib/*.sh whose pattern holds `.geniro`, `safety.json`,
# or a command word (rm, mv, rmdir, find, rsync, git) as a bare lowercase token
# must carry one of those shapes. The `tr` fold is tracked per function body,
# reset at each `name() {` and at its closing `}`. It is a heuristic pinned to
# the shipped fix shapes, not a prover — a matcher that invents a fourth shape
# needs a matching update here.
#
# Deliberately NOT flagged (false-positive exclusions, not loopholes):
#   - lines that are comments (leading `#` after trimming)
#   - the `tr '[:upper:]' '[:lower:]'` fold line itself
#   - a bare command-word mention with no `[[:space:]]` boundary immediately
#     after it (prose, path examples)

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
    # A sed normalizer whose script opens with an s-command right after the
    # quote (double- or single-quoted, `#` or slash delimited) is a matcher
    # too: it decides whether the surrounding text reads as the command word
    # it rewrites. `.` stands in for the opening quote character so this
    # matches either quoting style without embedding a literal quote in this
    # awk program, which sits inside a single-quoted shell string.
    function is_sed_normalizer(s) {
      return (s ~ /sed[[:space:]]+(-[A-Za-z]+[[:space:]]+)*.s[\/#]/)
    }
    function is_matcher_line(s) {
      return (s ~ /grep[[:space:]]+-[A-Za-z]*[qo][A-Za-z]*/ || s ~ /(^|[^A-Za-z0-9_])case[[:space:]]/ || is_sed_normalizer(s))
    }
    BEGIN { lowered = 0 }
    {
      line = $0
      # Reset per-function tracking at a new top-level function definition AND
      # at the closing brace of that function — resetting only on the next header
      # let top-level lines after a folding function read as still-lowered
      # (2026-09-23 audit T0-4).
      if (line ~ /^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{/) { lowered = 0 }
      if (line ~ /^\}/) { lowered = 0 }
      if (line ~ /tr[[:space:]]+.\[:upper:\].[[:space:]]+.\[:lower:\]./) { lowered = 1; next }
      if (is_comment(line)) next
      if (!is_matcher_line(line)) next

      needs_fold = 0
      if ((line ~ /\.geniro/) && !has_ifold(line) && !lowered) needs_fold = 1
      if ((line ~ /safety\.json/) && !has_ifold(line) && !lowered) needs_fold = 1
      # A command word as a bare token immediately followed by a
      # whitespace-class boundary inside a regex pattern.
      if (line ~ /(^|[^A-Za-z0-9_\[])(rm|mv|rmdir|find|rsync|git)\[\[:space:\]\]/) {
        if (!has_ifold(line) && !has_bracket_fold(line) && !lowered) needs_fold = 1
      }
      # The same words as the first thing after a sed substitution delimiter
      # (`s/git(...`) — the shape a normalizer rewrites rather than matches.
      if (is_sed_normalizer(line) && line ~ /s[\/#](rm|mv|rmdir|find|rsync|git)([^A-Za-z0-9_]|$)/) {
        if (!has_bracket_fold(line) && !lowered) needs_fold = 1
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
normalize_path() {
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
