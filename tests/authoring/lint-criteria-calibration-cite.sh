#!/usr/bin/env bash
# Every skills/_shared/review-criteria/*.md file cites severity-calibration.md.
#
# Run: bash tests/authoring/lint-criteria-calibration-cite.sh
#
# Why this exists: `severity-calibration.md` is the canonical CRITICAL/HIGH/
# MEDIUM/LOW rubric every review dimension specializes from — eleven of the
# twelve `review-criteria/*.md` files say so explicitly ("Canonical decision
# rules: `.../severity-calibration.md` §1"). A file with zero citations has no
# tether to the shared rubric at all, and it shows: `spec-compliance-
# criteria.md` drifted its own CRITICAL tier to admit classes the canonical
# inclusion list does not, and nothing caught it because nothing asserted the
# citation was there to drift away from. This is the cheapest possible guard
# against that recurring — one grep, scoped to the one directory where every
# file is expected to carry the same citation for the same reason.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

_missing_calibration_cite() {  # <dir> -> one path per line lacking the citation
  local f
  for f in "$1"/*.md; do
    [ -f "$f" ] || continue
    grep -q 'severity-calibration\.md' "$f" || printf '%s\n' "$f"
  done
}

checked=0
for f in skills/_shared/review-criteria/*.md; do
  [ -f "$f" ] && checked=$((checked + 1))
done

while IFS= read -r f; do
  [ -n "$f" ] || continue
  report_fail "$f cites severity-calibration.md nowhere — its severity tiers have no tether to the canonical rubric"
done < <(_missing_calibration_cite skills/_shared/review-criteria)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: all $checked review-criteria/*.md file(s) cite severity-calibration.md"
fi

# --- self-test: red on a fixture missing the citation, green once present ---
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/review-criteria"

cat > "$SELFTEST_DIR/review-criteria/violation-criteria.md" <<'EOF'
# Probe review criteria

- **CRITICAL** — a made-up class with no tether to the shared rubric.
EOF
cat > "$SELFTEST_DIR/review-criteria/clean-criteria.md" <<'EOF'
# Probe review criteria

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.
EOF

missing="$(_missing_calibration_cite "$SELFTEST_DIR/review-criteria")"
n_violation=$(printf '%s\n' "$missing" | grep -c 'violation-criteria.md' || true)
n_clean_flagged=$(printf '%s\n' "$missing" | grep -c 'clean-criteria.md' || true)

if [ "$n_violation" -eq 1 ]; then
  echo "OK: self-test — a criteria file with zero citations is detected"
else
  report_fail "self-test — seeded violation was NOT detected"
fi
if [ "$n_clean_flagged" -eq 0 ]; then
  echo "OK: self-test — a criteria file that cites severity-calibration.md stays silent"
else
  report_fail "self-test — the clean fixture false-positived"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS review-criteria calibration-citation problem(s)." >&2
  exit 1
fi
echo "OK: every review-criteria/*.md file cites severity-calibration.md."
