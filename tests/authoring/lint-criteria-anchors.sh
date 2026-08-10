#!/usr/bin/env bash
# In-file §N / §N.M anchors inside skills/_shared/review-criteria/*.md must
# resolve to a numbered heading in that SAME file.
#
# Run: bash tests/authoring/lint-criteria-anchors.sh
#
# Why this exists: the twelve `review-criteria/*.md` dimension bodies cite
# their own numbered sub-sections constantly — "per §1.5 Caller-Blast Check",
# "CRITICAL for §1 AND HIGH for §3" — and nothing checks that the number still
# names a real heading. A section gets renumbered or compressed out and every
# bare `§N` citing it dangles silently: the sentence still reads correct, and
# `lint-skills.sh` check 10 explicitly does not cover this shape (it is scoped
# to PATH-ADJACENT anchors only — a `§` sitting next to a file path — because a
# bare `§` is not mechanically recoverable IN GENERAL: it may name a section in
# the citing file, a file named a paragraph earlier, or none). This directory
# is the one subtree where the general case IS recoverable, because a bare `§N`
# here has exactly one legitimate referent — the citing file's own numbered
# heading — UNLESS the citation is itself introduced by a named file a few
# words earlier in the same sentence ("Belongs to `pr-metadata-criteria.md`
# §11"), which is the one shape this check must not flag.
#
# What makes the self/cross-file split decidable: scanning strictly
# LEFT-TO-RIGHT within one sentence (table cell walls count as sentence
# breaks, same convention lint-skills.sh check 9 uses), a `§N` is CROSS-FILE
# only if a backtick-quoted `something.md` path appears EARLIER in that same
# sentence — order matters, not mere co-occurrence. "Emit the §3 finding...;
# the cause-path verification belongs to `tests-criteria.md` §Test Deletions"
# has a path AFTER the `§3`, so `§3` is still this file's own — a same-LINE
# (order-blind) check would wrongly clear it. This was verified against every
# `§N` occurrence across all twelve files at authoring time: the order-aware
# rule produces zero false positives on this corpus, including two sentences
# that name `severity-calibration.md` by anaphora ("...that file's §1... and
# its §6...") rather than restating the path — those happen to coincide with a
# same-numbered heading in the citing file too, so they resolve either way,
# but the rule that matters is the path-precedes-citation ordering, not luck.
#
# Portability: no -P, no mapfile, no associative arrays. The § scan runs under
# LC_ALL=C with the UTF-8 lead-byte pair (0xC2 0xA7) written as octal escapes —
# the same technique `lint-skills.sh`'s check 9 uses — because awk's `match()`
# on a literal `§` character is locale-dependent (verified: matches under a
# UTF-8 locale, silently fails to match under `C`/`POSIX`), and CI's locale is
# not guaranteed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# Only real headings resolve an anchor — a heading-shaped line inside a fenced
# code block is not one (same rule as lint-skills.sh's `_real_headings`).
_real_headings() {
  awk '
    /^[ \t]*```/ { fence = 1 - fence; next }
    fence        { next }
    /^# |^## |^### |^#### / { print }
  ' "$1" 2>/dev/null
}

# `<file>:<line>\t<bare §N anchor>` for every in-file (non-cross-file) numeric
# anchor that does not resolve to a heading in that same file.
_unresolved_criteria_anchors() {
  local f heads nums
  for f in "$@"; do
    [ -f "$f" ] || continue
    heads="$(_real_headings "$f")"
    nums="$(printf '%s\n' "$heads" \
      | sed -E 's/^#{1,4} //; s/[^0-9.].*//; s/\.$//' \
      | grep -E '^[0-9]+(\.[0-9]+)?$' | sort -u | tr '\n' ' ')"
    LC_ALL=C awk -v nums=" $nums" -v fname="$f" '
      function resolves(num,   needle) {
        needle = " " num " "
        return index(nums, needle) > 0
      }
      /^[ \t]*```/ { fence = 1 - fence; next }
      fence { next }
      {
        line = $0
        gsub(/\|/, ". ", line)   # table-cell wall -> sentence break
        n = split(line, chunks, /[.!?] +/)
        for (i = 1; i <= n; i++) {
          s = chunks[i]
          pos = 1; seen_path = 0
          while (1) {
            rest = substr(s, pos)
            if (match(rest, /`[^`]*\.md`/)) { p_start = RSTART; p_len = RLENGTH } else { p_start = 0 }
            if (match(rest, /\302\247[0-9]+(\.[0-9]+)?/)) { c_start = RSTART; c_len = RLENGTH } else { c_start = 0 }
            if (p_start == 0 && c_start == 0) break
            if (p_start > 0 && (c_start == 0 || p_start < c_start)) {
              seen_path = 1
              pos = pos + p_start + p_len - 1
            } else {
              cite = substr(rest, c_start, c_len)
              num = cite
              sub(/^\302\247/, "", num)
              if (!seen_path && !resolves(num)) {
                print fname ":" FNR "\t\302\247" num
              }
              pos = pos + c_start + c_len - 1
            }
          }
        }
      }
    ' "$f"
  done
}

checked=0
for f in skills/_shared/review-criteria/*.md; do
  [ -f "$f" ] && checked=$((checked + 1))
done

while IFS=$'\t' read -r loc anchor; do
  [ -n "$loc" ] || continue
  report_fail "$loc cites $anchor — no heading numbered ${anchor#*§} in that file"
done < <(_unresolved_criteria_anchors skills/_shared/review-criteria/*.md)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: every in-file §N/§N.M anchor across $checked review-criteria/*.md file(s) resolves"
fi

# --- self-test: red on a seeded dangling in-file anchor, silent on a --------
# cross-file citation of the SAME missing number and on a resolving one ------
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT

cat > "$SELFTEST_DIR/violation.md" <<'EOF'
# Probe criteria

### 1.5. Caller-blast check

- **HIGH** — a contract change (per §1.5); a type-design gap (per §7.5) where an escape hatch exists.
EOF

cat > "$SELFTEST_DIR/clean.md" <<'EOF'
# Probe criteria

### 1.5. Caller-blast check
### 7.5. Reinvented-wheel

- **HIGH** — a contract change (per §1.5); a type-design gap (per §7.5) where an escape hatch exists.
- Belongs to `other-criteria.md` §9 (a number this file does not define at all).
EOF

n_violation="$(_unresolved_criteria_anchors "$SELFTEST_DIR/violation.md" | grep -c . || true)"
if [ "$n_violation" -eq 1 ]; then
  echo "OK: self-test — a dangling in-file §7.5 (no matching heading) is detected, and the resolving §1.5 stays silent"
else
  report_fail "self-test — expected exactly 1 unresolved anchor in the seeded violation, got $n_violation"
fi

n_clean="$(_unresolved_criteria_anchors "$SELFTEST_DIR/clean.md" | grep -c . || true)"
if [ "$n_clean" -eq 0 ]; then
  echo "OK: self-test — both in-file anchors resolve once the headings exist, and the cross-file §9 stays silent"
else
  report_fail "self-test — the clean fixture false-positived ($n_clean hit(s)): $(_unresolved_criteria_anchors "$SELFTEST_DIR/clean.md" | tr '\n' ' ')"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS review-criteria anchor problem(s)." >&2
  exit 1
fi
echo "OK: all in-file §N/§N.M anchors in review-criteria/*.md resolve."
