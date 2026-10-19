#!/usr/bin/env bash
# AUQ header values must be <=12 characters.
#
# Run: bash tests/authoring/lint-auq-headers.sh
#
# Why this exists: `skills/_shared/gate-rendering.md` §Lean-question conventions
# sets the cap ("`header` <=12 characters. The option chip hard-truncates past
# that") because the AskUserQuestion option chip hard-truncates a longer header
# mid-word, which reads as a rendering glitch rather than a label the user can
# scan. Nothing enforced it: a plugin audit round found 22 sites across 9 files
# breaking it, up to 18 characters, because every author re-derives "does this
# fit" by eye rather than by count.
#
# Scope: header VALUE declarations in skills/** and .claude/skills/**
# (mirroring lint-skills.sh's two-population scan) — not every mention of the
# word "header". Five spellings appear in this corpus and all are scanned:
#   header: "Some label"          (the key form, no backticks)
#   header: `"Some label"`        (the key form, backtick-wrapped, with or without inner quotes)
#   header "Some label"           (the prose form: no colon, a quoted value)
#   header `"Some label"`         (the prose form, backtick-wrapped)
#   header `Some label`           (the prose form, backticks only)
# Most skill bodies name a gate's header in the prose form, so scanning only the
# `header:` key form missed 16 over-cap sites that the option chip truncates
# exactly the same way.
#
# A bare `header:` used to name the FIELD itself, not a value — e.g. "the lean
# AUQ's `header:` must name the right one", or a table column titled `header:`
# — is excluded by construction: every real key-form value declaration in this
# corpus has at least one space between the colon and its quote/backtick, while
# the field-name mentions have the closing backtick touching the colon directly
# (no space). Requiring that space keeps this HARD: it has zero observed false
# positives over the full corpus (verified by hand against every `header:` hit
# at authoring time), and a field-name mention with a space inserted before its
# closing backtick does not occur anywhere here. The prose form needs the word
# `header`, whitespace, an optional backtick and an opening double quote, so a
# `header` mention with no quoted value right after it (a table column, "a
# header row", "the header must name...") never matches.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

HEADER_CAP=12
FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# Emits `<file>:<line>\t<value>` for every header VALUE declaration found
# under the given paths, in either spelling.
_auq_headers() {
  # -H is load-bearing, not redundant with -r: given a SINGLE FILE argument, GNU
  # grep omits the filename prefix while BSD grep emits it. Without -H the
  # `IFS=: read -r f l rest` below binds the line number as the filename on Linux
  # and the extraction silently yields nothing — green on macOS, blind on CI.
  # The self-tests pass one file at a time, so they are exactly that path.
  grep -rHnoE 'header:[[:space:]]+.{0,60}' "$@" 2>/dev/null | while IFS=: read -r f l rest; do
    val=$(printf '%s\n' "$rest" | sed -E '
      s/^header:[[:space:]]+`?"([^"]*)".*/\1/
      t end
      s/^header:[[:space:]]+`([^`"]*)`.*/\1/
      t end
      s/.*//
      : end
    ')
    [ -n "$val" ] || continue
    printf '%s:%s\t%s\n' "$f" "$l" "$val"
  done
  # The prose form. `header` must be followed by whitespace (so the key form
  # above is never counted twice) and then a quoted value.
  grep -rHnoE 'header[[:space:]]+(`?"[^"]{1,60}"|`[^`"]{1,60}`)' "$@" 2>/dev/null | while IFS=: read -r f l rest; do
    val=$(printf '%s\n' "$rest" | sed -E '
      s/^header[[:space:]]+`?"([^"]*)".*/\1/
      t end
      s/^header[[:space:]]+`([^`"]*)`.*/\1/
      : end
    ')
    [ -n "$val" ] || continue
    printf '%s:%s\t%s\n' "$f" "$l" "$val"
  done
}

# <paths...> -> `<loc>\t<value>` for every extracted header value over the cap.
_over_cap() {
  local loc val
  while IFS=$'\t' read -r loc val; do
    [ -n "$loc" ] || continue
    [ "${#val}" -gt "$HEADER_CAP" ] && printf '%s\t%s\n' "$loc" "$val"
  done < <(_auq_headers "$@")
}

checked="$(_auq_headers skills .claude/skills | grep -c . || true)"
while IFS=$'\t' read -r loc val; do
  [ -n "$loc" ] || continue
  report_fail "$loc: header \"$val\" is ${#val} chars (cap $HEADER_CAP) — the option chip truncates past $HEADER_CAP"
done < <(_over_cap skills .claude/skills)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: all $checked AUQ header value(s) are <=$HEADER_CAP characters"
fi

# --- self-test: the matcher is red on a seeded violation and green after -----
# Fixtures live in a scratch dir, never in the tracked tree: this check's file
# allowlist is tests/authoring/** only, and a self-test that only proves
# something about a temp file proves nothing about the matcher's real
# behavior on this repo's own syntax shapes, so both the violating and the
# clean fixture reuse the exact shapes seen in skills/** (bare-quoted,
# backtick-quoted, the prose forms, and the field-name-mention false-positive
# guard). The self-test drives the same _over_cap the real scan uses.
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT

cat > "$SELFTEST_DIR/violation-key.md" <<'EOF'
Fire an `AskUserQuestion` (header: "Unexpected changes", options: "A" / "B" / "C").
EOF
cat > "$SELFTEST_DIR/violation-prose.md" <<'EOF'
Then fire the lean `AskUserQuestion` with header "Spec checks not passing" and three options.
Fire `AskUserQuestion` (header `"Review rounds"`, question `"Continue?"`) with options.
Fire one lean AUQ (header `Open decision`) per unresolved entry.
EOF
cat > "$SELFTEST_DIR/clean.md" <<'EOF'
Fire an `AskUserQuestion` (header: "Branch check", options: "A" / "B" / "C").
Use `AskUserQuestion` (header: `"Ship mode"`) for the ship gate.
Use `AskUserQuestion` (header: `Test quality`) for the quality gate.
Fire the lean question with header "Mode" and four options.
Fire one lean AUQ (header `Decision`) per unresolved entry.
A run that hits both sources uses the neutral header `"Checks fail"` here.
The lean AUQ's `header:` must name the right failure source.
The header must name the right failure source, and a header row is not a value.
| Failure source | AUQ `header:` | Digest framing |
EOF

n_key="$(_over_cap "$SELFTEST_DIR/violation-key.md" | grep -c . || true)"
if [ "$n_key" -eq 1 ]; then
  echo "OK: self-test — seeded 18-char header: value ('Unexpected changes') is detected"
else
  report_fail "self-test — seeded header: violation expected 1 hit, got $n_key; the matcher would miss a real one"
fi

n_prose="$(_over_cap "$SELFTEST_DIR/violation-prose.md" | grep -c . || true)"
if [ "$n_prose" -eq 3 ]; then
  echo "OK: self-test — all three prose forms (header \"...\", header \`\"...\"\`, header \`...\`) over the cap are detected"
else
  report_fail "self-test — seeded prose-form violations expected 3 hits, got $n_prose; the matcher would miss real ones"
fi

# The clean fixture must be EXTRACTED (otherwise "zero over cap" proves nothing)
# and must produce no over-cap row.
n_clean_values="$(_auq_headers "$SELFTEST_DIR/clean.md" | grep -c . || true)"
n_clean_over="$(_over_cap "$SELFTEST_DIR/clean.md" | grep -c . || true)"
if [ "$n_clean_values" -eq 6 ] && [ "$n_clean_over" -eq 0 ]; then
  echo "OK: self-test — the clean fixture yields its 6 real values, none over the cap (no false positive)"
else
  report_fail "self-test — clean fixture: expected 6 extracted values and 0 over cap, got $n_clean_values and $n_clean_over"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS AUQ header problem(s)." >&2
  exit 1
fi
echo "OK: all AUQ header values resolve within the $HEADER_CAP-char cap."
