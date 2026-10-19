#!/usr/bin/env bash
# T4-38 (plugin-audit 2026-10-19) — no step title under skills/<skill>/ carries
# translation-table vocabulary.
#
# Run: bash tests/authoring/lint-step-title-vocabulary.sh
#
# Why this exists: skill-prose.md §"Step titles ARE user-facing" — the model
# echoes a step title when it executes the step, so `5. **Load custom
# instructions.**` is fine and `5. **Load L4 instructions.**` is not. The audit
# found eleven titles that did exactly that ("Escalation AUQ", "Memory layer
# load", "Cross-layer conflict resolution", "PLAN CONTEXT load"), each one read
# aloud to a user who has never met the term.
#
# What counts as a step title (scope = what a run echoes, not every heading):
#   - a `#` heading that opens with a step marker: a number ("3.2 ...",
#     "8. ..."), "Step N", "Phase N" or "PHASE N" — which covers every
#     SKILL.md `## PHASE N` heading and every numbered phase/reference section;
#   - a numbered bold lead-in: `N. **Title**` (the bold span is the title);
#   - a bold `**Step N — Title.**` lead-in.
# Fenced code is skipped.
#
# Out of scope, on purpose:
#   - skills/_shared/** — contract headings there ("Required AUQ shape",
#     "Scrub before the AUQ fires (hard)", the memory-layer helper titles) are
#     author-facing anchors that other files cite by `§`; they are read by
#     authors and renaming them breaks the citations. This lint reads
#     skills/<skill>/ only.
#   - unnumbered headings and bullet lead-ins ("- **L4 instructions**"): they
#     label reference material or a list, not a step the run announces.
#   - skills/plan/plan-auq-reference.md: the reference whose subject IS the
#     question tool; its numbered sections are templates, not steps.
#
# Vocabulary (skill-prose.md §Translation tables): `AUQ`, `Memory layer(s)`,
# `Cross-layer`, `PLAN CONTEXT`, `L1`-`L4` as a word, `KR` / `CE` / `TR` as a
# word. `Memory layer` and `Cross-layer` match in any case — a lower-case
# "Resolve cross-layer conflicts." leaks the same term.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# Reference files whose subject is the vocabulary itself.
EXEMPT_FILES="skills/plan/plan-auq-reference.md"

# <root> -> `<file>:<line>\t<token>\t<title>` for every offending step title
# under <root>/skills/<skill>/ (never _shared).
step_title_hits() {
  local root="$1" f
  ( cd "$root" 2>/dev/null || exit 0
    find skills -type f -name '*.md' -not -path 'skills/_shared/*' 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
      case " $EXEMPT_FILES " in *" $f "*) continue ;; esac
      awk -v f="$f" '
        function word(t, w,   re) {
          re = "(^|[^A-Za-z0-9_])(" w ")($|[^A-Za-z0-9_])"
          if (match(t, re)) { s = substr(t, RSTART, RLENGTH); gsub(/^[^A-Za-z0-9_]+|[^A-Za-z0-9_]+$/, "", s); return s }
          return ""
        }
        function check(title,   tok, lc) {
          tok = word(title, "AUQ|L[1-4]|KR|CE|TR")
          if (tok == "" && index(title, "PLAN CONTEXT") > 0) tok = "PLAN CONTEXT"
          if (tok == "") {
            lc = tolower(title)
            if (index(lc, "memory layer") > 0) tok = "memory layer"
            else if (index(lc, "cross-layer") > 0) tok = "cross-layer"
          }
          if (tok != "") printf "%s:%d\t%s\t%s\n", f, FNR, tok, title
        }
        /^[ \t]*```/ { fence = !fence; next }
        fence { next }
        /^#+ +([0-9]|Step [0-9]|Phase [0-9]|PHASE [0-9])/ {
          t = $0; sub(/^#+ +/, "", t); check(t); next
        }
        /^[ \t]*[0-9]+\. +\*\*[^*]+\*\*/ {
          t = $0; sub(/^[ \t]*[0-9]+\. +\*\*/, "", t); sub(/\*\*.*/, "", t); check(t); next
        }
        /^[ \t]*([-*][ \t]+)?\*\*Step [0-9][^*]*\*\*/ {
          t = $0; sub(/^[ \t]*([-*][ \t]+)?\*\*/, "", t); sub(/\*\*.*/, "", t); check(t); next
        }
      ' "$f"
    done
  )
}

checked="$(find skills -type f -name '*.md' -not -path 'skills/_shared/*' | grep -c . || true)"
while IFS=$'\t' read -r loc tok title; do
  [ -n "$loc" ] || continue
  report_fail "$loc: step title carries \"$tok\": \"$title\" — a run echoes step titles to the user; retitle in plain words (skill-prose.md §Step titles ARE user-facing)"
done < <(step_title_hits "$REPO_ROOT")

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no step title in the $checked skills/<skill>/ files carries translation-table vocabulary"
fi

# --- self-test: red on each seeded title shape, green on plain titles and out-of-scope headings ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/probe" "$SELFTEST_DIR/skills/_shared" "$SELFTEST_DIR/skills/plan"

# The shapes the audit found, one per title form.
cat > "$SELFTEST_DIR/skills/probe/violation.md" <<'EOF'
### 3.2 Escalation AUQ
## 8. Step 0.6 — PLAN CONTEXT load (schema-aware)
### 1.1 Memory layer load (past-knowledge query)
## PHASE 2 — Spawn the KR agent
4. **Cross-layer conflict resolution** — `resolve-conflicts` per the helper.
10. **Resolve cross-layer conflicts.** When the instructions disagree, follow the protocol.
**Step 4 — Ship-mode AUQ.** Pushing a private feature branch is draft-grade.
7. **Load L4 instructions.** Read them.
EOF

cat > "$SELFTEST_DIR/skills/probe/clean.md" <<'EOF'
### 3.2 Ask where to send the fix
## 8. Step 0.6 — Load the plan's context (schema-aware)
10. **Reconcile custom instructions, snapshot and past learnings.** Fire the AUQ and read the CE output; L4 wins.
## PHASE 3 — Ship
**Step 4 — Choose the ship mode.** The AUQ options follow.
- **L4 instructions** — a bullet lead-in labels a list, not a step.
## Required AUQ shape
# Plan — AUQ templates
The cross-layer conflict is resolved by the helper; see the Memory layer table.
```markdown
### 3.2 Escalation AUQ
5. **Load L4 instructions.**
```
EOF

cat > "$SELFTEST_DIR/skills/_shared/contract.md" <<'EOF'
## 2. Gate chain — fire each as a separate AUQ
### 4.1 Update-default AUQ
EOF
cat > "$SELFTEST_DIR/skills/plan/plan-auq-reference.md" <<'EOF'
## 2. Phase 3 grill AUQ — message-first, one round at a time
EOF

v="$(step_title_hits "$SELFTEST_DIR" | grep -c 'violation.md' || true)"
if [ "$v" -eq 8 ]; then
  echo "OK: self-test — all 8 seeded title shapes (numbered heading, 'Step N —', PHASE heading, 'N. **bold**' in both cases, '**Step N**' lead-in, L4) are detected"
else
  report_fail "self-test — expected 8 seeded violation hits, got $v"
fi

c="$(step_title_hits "$SELFTEST_DIR" | grep -vc 'violation.md' || true)"
if [ "$c" -eq 0 ]; then
  echo "OK: self-test — plain titles, bullet lead-ins, unnumbered headings, prose, fenced code, skills/_shared/ and the question-tool reference do not false-positive"
else
  report_fail "self-test — the clean/out-of-scope fixtures false-positived ($c hit(s)): $(step_title_hits "$SELFTEST_DIR" | grep -v 'violation.md' | cut -f1 | tr '\n' ' ')"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS step-title vocabulary problem(s)." >&2
  exit 1
fi
echo "OK: no step title echoes translation-table vocabulary."
