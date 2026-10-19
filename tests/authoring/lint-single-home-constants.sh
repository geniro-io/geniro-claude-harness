#!/usr/bin/env bash
# C16 (plugin-audit 2026-09-23, fix-plan §O / T4-1, T4-2; extended 2026-10-19,
# T4-1 / T4-3) — four single-homed constants stay single-homed:
#   1. `20,000` (the host's character re-attach figure) is absent from
#      skills/ entirely — the number has one real home (lint-skills.sh's
#      REATTACH_CHARS) and every skill spine should describe the BEHAVIOR,
#      never restate the figure.
#   2. `400 LOC` (the review size-triage boundary) appears in skills/ ONLY at
#      its declared canonical home, skills/review/phase-1-triage-reference.md.
#   3. The question tool's option cap (spelled "4-option", "<=4 options", "at
#      most 4 options", "caps at 4 options" or "maxItems=4") appears in
#      skills/, agents/ and .claude/skills/ ONLY at its home,
#      skills/_shared/per-finding-question.md §Cap-extension. Every other site
#      names the cap without the number and cites the home.
#   4. The Codex truncation figure ("8,000 bytes") is absent from skills/. The
#      runtime-portability preamble in every SKILL.md says "If Codex truncated
#      this file"; the figure was restated 13 times with no home and drifted
#      against ARCHITECTURE.md's "8 KB".
#
# Run: bash tests/authoring/lint-single-home-constants.sh
#
# Why this exists: D7 §"Prose counts of repo contents" / §"Multi-homed
# constants" — a number restated in ≥2 files is drift-prone even while every
# copy agrees today, because there is no single place left to fix when one of
# them goes stale. T4-1: the ~20,000-char re-attach figure had regressed back
# into eight skill spines (a repeat of a prior fix). T4-2: the >400 LOC review
# boundary was restated outside its declared canonical home.
#
# T4-1: the AskUserQuestion option cap was restated at 19 sites in 15 files.
# The home keeps the number; a host that changes the cap then has one place to
# update, and every other site stays true by not asserting it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

CANONICAL_400_LOC="skills/review/phase-1-triage-reference.md"
CANONICAL_OPTION_CAP="skills/_shared/per-finding-question.md"
# The cap's spellings. `4-option` is the compound ("the 4-option cap"); the
# others are the verb phrases and the tool-schema form.
OPTION_CAP_PATTERN='4-option|≤ ?4 options|at most 4 options|[Cc]aps? at 4 options|maxItems ?= ?4'

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# <pattern> <dir> -> `file:line:text` for every hit.
absent_hits() {
  grep -rnE -- "$1" "$2" 2>/dev/null
}

# <pattern> <dir> <canonical-file> -> each file other than the canonical one
# that carries the pattern.
single_home_offenders() {
  local f
  grep -rlE -- "$1" "$2" 2>/dev/null | while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$f" = "$3" ] || printf '%s\n' "$f"
  done
}

check_absent() {  # <label> <pattern> <dir>
  local label="$1" pattern="$2" dir="$3" hits h
  hits=$(absent_hits "$pattern" "$dir")
  [ -n "$hits" ] || return 0
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    report_fail "$label restated outside its single home: $h"
  done <<< "$hits"
  return 1
}

check_single_home() {  # <label> <pattern> <dir> <canonical-file>
  local label="$1" pattern="$2" dir="$3" canonical="$4" f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    report_fail "$label restated outside its declared canonical home ($canonical): $f"
  done < <(single_home_offenders "$pattern" "$dir" "$canonical")
}

check_absent "the '20,000'-char re-attach figure" '20,000' skills
check_single_home "the '400 LOC' review size-triage boundary" '400 LOC' skills "$CANONICAL_400_LOC"
for d in skills agents .claude/skills; do
  # Per site, not per file: the home is the only file allowed to carry it, and
  # the finding the maintainer acts on is the line.
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    f="${h%%:*}"
    [ "$f" = "$CANONICAL_OPTION_CAP" ] && continue
    report_fail "the question tool's option cap restated outside its home ($CANONICAL_OPTION_CAP): $h"
  done < <(absent_hits "$OPTION_CAP_PATTERN" "$d" | cut -c1-200)
done
check_absent "the Codex '8,000 bytes' truncation figure" '8,000 bytes' skills

if [ "$FAILS" -eq 0 ]; then
  echo "OK: '20,000' and '8,000 bytes' are absent from skills/; '400 LOC' appears only at $CANONICAL_400_LOC; the option cap appears only at $CANONICAL_OPTION_CAP"
fi

# --- self-test: red on each seeded restatement, green on the canonical-home-only case ----
# Every scenario drives the same helpers the scan above uses, so a change to a
# pattern or to the home exemption is exercised, not re-implemented here.
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/probe" "$SELFTEST_DIR/skills/review" "$SELFTEST_DIR/skills/_shared" "$SELFTEST_DIR/agents"

cat > "$SELFTEST_DIR/skills/probe/violation.md" <<'EOF'
The host re-attaches only the first 20,000 characters of a skill after a summary.
Group changes above 8 files OR 400 LOC before spawning reviewers.
If Codex cut this file at 8,000 bytes, read it in full from its path first.
Six options overflow the 4-option cap, so chain a follow-up question.
EOF
cat > "$SELFTEST_DIR/skills/probe/cap-variants.md" <<'EOF'
Present findings with multi-select questions (≤4 options per call; chain past the cap).
Present at most 4 options per call.
An AskUserQuestion caps at 4 options, so one option per thread cannot present them.
The tool schema sets maxItems=4 on the options list.
EOF
cat > "$SELFTEST_DIR/agents/violation.md" <<'EOF'
Cap at 4 options (matches the tool's 4-option ceiling).
EOF

cat > "$SELFTEST_DIR/skills/review/phase-1-triage-reference.md" <<'EOF'
**The size threshold — canonical home for the number.** >8 files OR >400 LOC.
EOF
cat > "$SELFTEST_DIR/skills/_shared/per-finding-question.md" <<'EOF'
## Cap-extension for >4 options
Present at most 4 options per call, never drop options across calls.
EOF
cat > "$SELFTEST_DIR/skills/probe/clean.md" <<'EOF'
If Codex truncated this file, read it in full from its path first.
Six options overflow the question tool's option cap, so chain a follow-up per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Cap-extension.
Pick 4 of the 14 options; the four options of the Ship gate are canonical.
EOF

v1=$(absent_hits '20,000' "$SELFTEST_DIR/skills/probe" | grep -c . || true)
v2=$(single_home_offenders '400 LOC' "$SELFTEST_DIR/skills" "$SELFTEST_DIR/skills/review/phase-1-triage-reference.md" | grep -c . || true)
v3=$(absent_hits '8,000 bytes' "$SELFTEST_DIR/skills" | grep -c . || true)
if [ "$v1" -eq 1 ] && [ "$v2" -eq 1 ] && [ "$v3" -eq 1 ]; then
  echo "OK: self-test — a seeded '20,000', an off-home '400 LOC' and a '8,000 bytes' restatement are all detected"
else
  report_fail "self-test — expected one seeded hit each, got 20,000=$v1 400LOC-off-home=$v2 8,000-bytes=$v3"
fi

# The option cap: five skill-body hits across violation.md and cap-variants.md
# (the compound, <=4, at most 4, caps at 4 and maxItems=4 spellings; the home
# file is filtered out) and one agent hit.
cap_skills=$(absent_hits "$OPTION_CAP_PATTERN" "$SELFTEST_DIR/skills" | grep -v "skills/_shared/per-finding-question.md" | grep -c . || true)
cap_agents=$(absent_hits "$OPTION_CAP_PATTERN" "$SELFTEST_DIR/agents" | grep -c . || true)
if [ "$cap_skills" -eq 5 ] && [ "$cap_agents" -eq 1 ]; then
  echo "OK: self-test — every option-cap spelling (4-option, <=4 options, at most 4 options, caps at 4 options, maxItems=4) is detected in skills/ and agents/"
else
  report_fail "self-test — expected 5 skill hits and 1 agent hit for the option cap, got skills=$cap_skills agents=$cap_agents"
fi

c1=$(absent_hits '20,000' "$SELFTEST_DIR/skills/review" | grep -c . || true)
c2=$(single_home_offenders '400 LOC' "$SELFTEST_DIR/skills/review" "$SELFTEST_DIR/skills/review/phase-1-triage-reference.md" | grep -c . || true)
c3=$(single_home_offenders "$OPTION_CAP_PATTERN" "$SELFTEST_DIR/skills/_shared" "$SELFTEST_DIR/skills/_shared/per-finding-question.md" | grep -c . || true)
c4=$(absent_hits "$OPTION_CAP_PATTERN|8,000 bytes" "$SELFTEST_DIR/skills/probe/clean.md" | grep -c . || true)
if [ "$c1" -eq 0 ] && [ "$c2" -eq 0 ] && [ "$c3" -eq 0 ] && [ "$c4" -eq 0 ]; then
  echo "OK: self-test — constants at their canonical homes, and prose that names the cap without the number, do not false-positive"
else
  report_fail "self-test — the canonical-home fixtures misbehaved (20,000 in review dir=$c1, 400LOC-at-home=$c2, cap-at-home=$c3, clean=$c4)"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS single-homed constant restatement problem(s)." >&2
  exit 1
fi
echo "OK: all single-homed constants stay single-homed."
