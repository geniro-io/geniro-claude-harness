#!/usr/bin/env bash
# AUQ `header:` values must be <=12 characters.
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
# Scope: `header:` VALUE declarations in skills/** and .claude/skills/**
# (mirroring lint-skills.sh's two-population scan) — not every mention of the
# word "header". Two shapes appear in this corpus and both are scanned:
#   header: "Some label"          (no backticks)
#   header: `"Some label"`        (backtick-wrapped, with or without inner quotes)
# A bare `header:` used to name the FIELD itself, not a value — e.g. "the lean
# AUQ's `header:` must name the right one", or a table column titled `header:`
# — is excluded by construction: every real value declaration in this corpus
# has at least one space between the colon and its quote/backtick, while the
# field-name mentions have the closing backtick touching the colon directly
# (no space). Requiring that space is what keeps this HARD: it has zero
# observed false positives over the full corpus (verified by hand against
# every `header:` hit at authoring time), and a field-name mention with a
# space inserted before its closing backtick does not occur anywhere here.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

HEADER_CAP=12
FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# Emits `<file>:<line>\t<value>` for every `header:` VALUE declaration found
# under the given paths. A value is only ever captured immediately after
# "header:" + at least one space, so a bare `header:` field-name mention
# (no space before its closing backtick/quote) never reaches the sed pass
# below and correctly yields no row.
_auq_headers() {
  grep -rnoE 'header:[[:space:]]+.{0,60}' "$@" 2>/dev/null | while IFS=: read -r f l rest; do
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
}

checked=0
while IFS=$'\t' read -r loc val; do
  [ -n "$loc" ] || continue
  checked=$((checked + 1))
  len=${#val}
  if [ "$len" -gt "$HEADER_CAP" ]; then
    report_fail "$loc: header \"$val\" is $len chars (cap $HEADER_CAP) — the option chip truncates past $HEADER_CAP"
  fi
done < <(_auq_headers skills .claude/skills)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: all $checked AUQ header: value(s) are <=$HEADER_CAP characters"
fi

# --- self-test: the matcher is red on a seeded violation and green after -----
# Fixtures live in a scratch dir, never in the tracked tree: this check's file
# allowlist is tests/authoring/** only, and a self-test that only proves
# something about a temp file proves nothing about the matcher's real
# behavior on this repo's own syntax shapes, so both the violating and the
# clean fixture reuse the exact shapes seen in skills/** (bare-quoted,
# backtick-quoted, and the field-name-mention false-positive guard).
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT

cat > "$SELFTEST_DIR/violation.md" <<'EOF'
Fire an `AskUserQuestion` (header: "Unexpected changes", options: "A" / "B" / "C").
EOF
cat > "$SELFTEST_DIR/clean.md" <<'EOF'
Fire an `AskUserQuestion` (header: "Branch check", options: "A" / "B" / "C").
Use `AskUserQuestion` (header: `"Ship mode"`) for the ship gate.
Use `AskUserQuestion` (header: `Test quality`) for the quality gate.
The lean AUQ's `header:` must name the right failure source.
| Failure source | AUQ `header:` | Digest framing |
EOF

hit_count() { _auq_headers "$1" | grep -c . || true; }

n_violation="$(hit_count "$SELFTEST_DIR/violation.md")"
if [ "$n_violation" -ge 1 ]; then
  echo "OK: self-test — seeded 18-char header ('Unexpected changes') is detected"
else
  report_fail "self-test — seeded violation was NOT detected; the matcher would miss a real one"
fi

n_clean="$(hit_count "$SELFTEST_DIR/clean.md")"
# All four lines in clean.md carry values <=12 chars ("Branch check"=12,
# "Ship mode"=9, "Test quality"=12) or are field-name mentions with no value
# at all — so every extracted row must be <=12, i.e. zero of them fail the cap.
if [ "$n_clean" -ge 3 ]; then
  # Re-run the cap check against the clean fixture's own extracted rows.
  clean_over=0
  while IFS=$'\t' read -r loc val; do
    [ -n "$loc" ] || continue
    [ "${#val}" -gt "$HEADER_CAP" ] && clean_over=$((clean_over + 1))
  done < <(_auq_headers "$SELFTEST_DIR/clean.md")
  if [ "$clean_over" -eq 0 ]; then
    echo "OK: self-test — every value in the clean fixture stays <=$HEADER_CAP chars (no false positive)"
  else
    report_fail "self-test — the clean fixture false-positived on $clean_over value(s)"
  fi
else
  report_fail "self-test — the clean fixture's real header: values were not extracted at all"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS AUQ header: problem(s)." >&2
  exit 1
fi
echo "OK: all AUQ header: values resolve within the $HEADER_CAP-char cap."
