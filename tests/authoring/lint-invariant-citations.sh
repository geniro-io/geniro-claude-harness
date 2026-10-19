#!/usr/bin/env bash
# T4-2 (plugin-audit 2026-10-19) — every `Invariant #N (<label>)` citation names
# the label that the Nth invariant of its shared list actually carries.
#
# Run: bash tests/authoring/lint-invariant-citations.sh
#
# Why this exists: skills/_shared/loop-invariants.md and skills/_shared/audit-
# pipeline.md §Shared invariants are numbered lists that a dozen skill bodies
# cite by ordinal. An ordinal is a position, not a name: inserting or reordering
# an item silently re-points every citation, and the citing sentence keeps
# reading as if nothing changed ("invariant #3" meant permission-before-side-
# effect yesterday and means something else today). A citation that carries its
# label — `**Invariant #3 (permission before side-effect)**` — fails loudly the
# day the list moves, because the label no longer belongs to that position.
#
# What is checked: the form `Invariant #N (<label>)` (any case, "Invariants" too,
# "Loop-Invariant #N" included). The label is a SUBSET match, not an equality:
# citing skills abbreviate ("args validated" for "Args validated before
# execution", "bounded results" for "Bounded, structured tool results") and that
# is the established style. Every word of the cited label (lower-cased,
# punctuation dropped) must occur in the Nth canonical label, so a stale or
# swapped label ("#4 (permission before side-effect)") fails while an honest
# abbreviation passes.
#
# Which list: citations in audit files (skills/audit-instructions/,
# .claude/skills/audit-plugin/, skills/_shared/audit-pipeline.md itself) resolve
# against audit-pipeline.md §Shared invariants; every other file resolves
# against loop-invariants.md.
#
# Not checked: a bare ordinal with no parenthesised label ("per invariant #3")
# and a skill's own numbered list (S1-S5 style). Those carry no label to
# compare; the fix for a bare ordinal is to add the label.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

LOOP_FILE="skills/_shared/loop-invariants.md"
AUDIT_FILE="skills/_shared/audit-pipeline.md"

# <file> <section-heading-without-"## "|""> -> `N\t<normalized label words>` for
# each `N. **Label.**` item. With a heading, only that section is read; without
# one, the first occurrence of each N wins (the file's opening list).
list_labels() {
  awk -v want="$2" '
    /^```/ { fence = !fence }
    fence { next }
    /^## / { insec = (want == "" || $0 == "## " want); next }
    want == "" { insec = 1 }
    insec && /^[0-9]+\. \*\*/ {
      n = $0; sub(/\..*/, "", n)
      if (n in seen) next
      seen[n] = 1
      l = $0; sub(/^[0-9]+\. \*\*/, "", l); sub(/\*\*.*/, "", l)
      l = tolower(l); gsub(/[^a-z0-9]+/, " ", l); gsub(/^ +| +$/, "", l)
      printf "%s\t%s\n", n, l
    }
  ' "$1" 2>/dev/null
}

# <label-table> <N> <cited label> -> prints "ok", "missing" (no Nth item) or
# "mismatch:<canonical label>".
check_label() {
  awk -F'\t' -v n="$2" -v cited="$3" '
    $1 == n { canon = $2; found = 1 }
    END {
      if (!found) { print "missing"; exit }
      c = tolower(cited); gsub(/[^a-z0-9]+/, " ", c); gsub(/^ +| +$/, "", c)
      nc = split(canon, cw, " "); for (i = 1; i <= nc; i++) have[cw[i]] = 1
      nw = split(c, w, " ")
      if (nw == 0) { print "mismatch:" canon; exit }
      for (i = 1; i <= nw; i++) if (!(w[i] in have)) { print "mismatch:" canon; exit }
      print "ok"
    }
  ' "$1"
}

# <root> -> one line per bad citation: `<file>:<line>\t<citation>\t<problem>`.
citation_problems() {
  local root="$1" loop_t audit_t hit f rest l cit n label table verdict
  loop_t="$(mktemp)"; audit_t="$(mktemp)"
  ( cd "$root" || exit 0
    list_labels "$LOOP_FILE" "" > "$loop_t"
    list_labels "$AUDIT_FILE" "Shared invariants" > "$audit_t"
    grep -rnoE '[Ii]nvariants? #[0-9]+ \([^)]*\)' skills agents .claude/skills 2>/dev/null
  ) | while IFS= read -r hit; do
    f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"; cit="${rest#*:}"
    n="$(printf '%s' "$cit" | sed -E 's/^[Ii]nvariants? #([0-9]+) .*/\1/')"
    label="$(printf '%s' "$cit" | sed -E 's/^[^(]*\(//; s/\)$//')"
    case "$f" in
      skills/audit-instructions/*|.claude/skills/audit-plugin/*|"$AUDIT_FILE") table="$audit_t" ;;
      *) table="$loop_t" ;;
    esac
    verdict="$(check_label "$table" "$n" "$label")"
    case "$verdict" in
      ok) ;;
      missing) printf '%s:%s\t%s\tthe list has no invariant #%s\n' "$f" "$l" "$cit" "$n" ;;
      mismatch:*) printf '%s:%s\t%s\tinvariant #%s is "%s"\n' "$f" "$l" "$cit" "$n" "${verdict#mismatch:}" ;;
    esac
  done
  rm -f "$loop_t" "$audit_t"
}

if [ ! -f "$LOOP_FILE" ] || [ ! -f "$AUDIT_FILE" ]; then
  report_fail "$LOOP_FILE or $AUDIT_FILE is missing — the lists this check resolves citations against"
else
  total="$(grep -rnoE '[Ii]nvariants? #[0-9]+ \([^)]*\)' skills agents .claude/skills 2>/dev/null | grep -c . || true)"
  while IFS=$'\t' read -r loc cit problem; do
    [ -n "$loc" ] || continue
    report_fail "$loc: \"$cit\" does not match its list — $problem"
  done < <(citation_problems "$REPO_ROOT")
  if [ "$FAILS" -eq 0 ]; then
    echo "OK: all $total labelled 'Invariant #N (label)' citations match the Nth label of their list"
  fi
fi

# --- self-test: red on a swapped label, an out-of-range ordinal and a cross-list label; green on abbreviations ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/_shared" "$SELFTEST_DIR/skills/probe" "$SELFTEST_DIR/skills/audit-instructions" "$SELFTEST_DIR/.claude/skills/audit-plugin"

cat > "$SELFTEST_DIR/$LOOP_FILE" <<'EOF'
# Canonical agent-loop invariants

1. **One result per tool call.** Every call yields one result.
2. **Args validated before execution.** Check inputs.
3. **Permission before side-effect.** Ask first.
4. **Bounded, structured tool results.** Cap output.

**Turn-completion check (deliberately un-numbered).** Not an invariant.
EOF
cat > "$SELFTEST_DIR/$AUDIT_FILE" <<'EOF'
# Audit pipeline

## Shared invariants

1. **No unverified finding ships.** Read the cited line.
2. **Report before fix.** Fix after the gate.

## Fix-round discipline

1. **Echo the owner set.** A different numbered list that must not be read.
EOF

cat > "$SELFTEST_DIR/skills/probe/good.md" <<'EOF'
- **Invariant #2 (args validated)** — flag parsing is semantic.
- **Invariant #4 (bounded results)** — reviewer output is capped.
- invariant #3 (permission before side-effect) on the run path only.
- **Loop-Invariant #1 (one result per tool call)** binds each spawn.
EOF
cat > "$SELFTEST_DIR/skills/probe/bad.md" <<'EOF'
- **Invariant #4 (permission before side-effect)** — the ordinal and the label disagree.
- **Invariant #9 (args validated)** — there is no ninth item.
This violates Loop-Invariant #3 (never ship without the gate).
EOF
cat > "$SELFTEST_DIR/skills/audit-instructions/audit-good.md" <<'EOF'
Per **Invariant #1 (no unverified finding ships)** the orchestrator reads the line.
EOF
cat > "$SELFTEST_DIR/.claude/skills/audit-plugin/audit-bad.md" <<'EOF'
Per **Invariant #1 (one result per tool call)** the orchestrator reads the line.
Per **Invariant #1 (echo the owner set)** the orchestrator echoes owners.
EOF

good_n="$(citation_problems "$SELFTEST_DIR" | grep -c "good.md" || true)"
bad_files="$(citation_problems "$SELFTEST_DIR" | cut -f1 | sed 's|:.*||' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
if [ "$good_n" -eq 0 ]; then
  echo "OK: self-test — abbreviated labels, lower-case 'invariant', 'Loop-Invariant' and an audit-list citation all pass (no false positive)"
else
  report_fail "self-test — $good_n correct citation(s) were flagged"
fi
if [ "$bad_files" = " 3 skills/probe/bad.md; 2 .claude/skills/audit-plugin/audit-bad.md;" ] || \
   [ "$bad_files" = " 2 .claude/skills/audit-plugin/audit-bad.md; 3 skills/probe/bad.md;" ]; then
  echo "OK: self-test — a swapped label, a missing ordinal, a never-ship paraphrase, a loop label cited from an audit file, and the second numbered list in audit-pipeline.md are all detected"
else
  report_fail "self-test — expected 3 hits in bad.md and 2 in audit-bad.md, got: $bad_files"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS invariant-citation problem(s)." >&2
  exit 1
fi
echo "OK: every labelled invariant citation resolves to its list."
