#!/usr/bin/env bash
# C16 (plugin-audit 2026-09-23, fix-plan §O / T4-1, T4-2) — two single-homed
# constants stay single-homed:
#   1. `20,000` (the host's character re-attach figure) is absent from
#      skills/ entirely — the number has one real home (lint-skills.sh's
#      REATTACH_CHARS) and every skill spine should describe the BEHAVIOR,
#      never restate the figure.
#   2. `400 LOC` (the review size-triage boundary) appears in skills/ ONLY at
#      its declared canonical home, skills/review/phase-1-triage-reference.md.
#
# Run: bash tests/authoring/lint-single-home-constants.sh
#
# Why this exists: D7 §"Prose counts of repo contents" / §"Multi-homed
# constants" — a number restated in ≥2 files is drift-prone even while every
# copy agrees today, because there is no single place left to fix when one of
# them goes stale. T4-1: the ~20,000-char re-attach figure had regressed back
# into eight skill spines (a repeat of a prior fix). T4-2: the >400 LOC review
# boundary was restated outside its declared canonical home.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

CANONICAL_400_LOC="skills/review/phase-1-triage-reference.md"

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

check_absent() {  # <label> <pattern> <dir>
  local label="$1" pattern="$2" dir="$3" hits
  hits=$(grep -rn -- "$pattern" "$dir" 2>/dev/null)
  if [ -n "$hits" ]; then
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      report_fail "$label restated outside its single home: $h"
    done <<< "$hits"
    return 1
  fi
  return 0
}

check_single_home() {  # <label> <pattern> <dir> <canonical-file>
  local label="$1" pattern="$2" dir="$3" canonical="$4" hits
  hits=$(grep -rln -- "$pattern" "$dir" 2>/dev/null)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$f" != "$canonical" ]; then
      report_fail "$label restated outside its declared canonical home ($canonical): $f"
    fi
  done <<< "$hits"
}

check_absent "the '20,000'-char re-attach figure" '20,000' skills
check_single_home "the '400 LOC' review size-triage boundary" '400 LOC' skills "$CANONICAL_400_LOC"

if [ "$FAILS" -eq 0 ]; then
  echo "OK: '20,000' is absent from skills/, and '400 LOC' appears only at its canonical home ($CANONICAL_400_LOC)"
fi

# --- self-test: red on each seeded restatement, green on the canonical-home-only case ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/probe" "$SELFTEST_DIR/skills/review"

cat > "$SELFTEST_DIR/skills/probe/violation.md" <<'EOF'
The host re-attaches only the first 20,000 characters of a skill after a summary.
Group changes above 8 files OR 400 LOC before spawning reviewers.
EOF

cat > "$SELFTEST_DIR/skills/review/phase-1-triage-reference.md" <<'EOF'
**The size threshold — canonical home for the number.** >8 files OR >400 LOC.
EOF

v1=$(grep -rn -- '20,000' "$SELFTEST_DIR/skills" 2>/dev/null | grep -c .)
v2=$(grep -rln -- '400 LOC' "$SELFTEST_DIR/skills" 2>/dev/null | grep -vc "^$SELFTEST_DIR/skills/review/phase-1-triage-reference.md$" || true)
if [ "$v1" -ge 1 ] && [ "$v2" -ge 1 ]; then
  echo "OK: self-test — a seeded '20,000' restatement and an off-canonical-home '400 LOC' restatement are both detected"
else
  report_fail "self-test — expected both seeded violations detected, got 20,000=$v1 400LOC-off-home=$v2"
fi

c1=$(grep -rn -- '20,000' "$SELFTEST_DIR/skills/review" 2>/dev/null | grep -c .)
c2=$(grep -rln -- '400 LOC' "$SELFTEST_DIR/skills/review" 2>/dev/null | grep -c "^$SELFTEST_DIR/skills/review/phase-1-triage-reference.md$" || true)
if [ "$c1" -eq 0 ] && [ "$c2" -eq 1 ]; then
  echo "OK: self-test — '400 LOC' at ITS canonical home does not false-positive"
else
  report_fail "self-test — the canonical-home fixture misbehaved (20,000 in review dir=$c1, 400LOC-at-home=$c2)"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS single-homed constant restatement problem(s)." >&2
  exit 1
fi
echo "OK: both single-homed constants stay single-homed."
