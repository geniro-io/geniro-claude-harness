#!/usr/bin/env bash
# C5 (plugin-audit 2026-09-23, fix-plan §O / T2-5) — no skills/ or agents/ body
# carries author-facing narration or a maintainer note: "Define ONCE ...
# reference from N consumers", "previously specified inline" / "previously
# borrowed", "reserved ... not yet routed", "in v1", or a design-doc "Block 5b"
# style code.
#
# Run: bash tests/authoring/lint-narration-phrases.sh
#
# Why this exists: skill-authoring.md §3 "Authoring-process narration" and §2
# "plugin-author-internal references" ban exactly this class — text that
# addresses the plugin's OWN authors/maintainers ("here", "N consumers", "this
# design-doc block code") rather than the downstream runtime reader. It is a
# no-op at runtime (the fresh-user test in skill-prose.md never sees it) and
# decidable without taste: each phrase below is evidenced verbatim in the
# finding (T2-5), never a paraphrase a reviewer would need judgment to spot.
#
# Scope decision (stated per the task's instruction to decide and say so):
# the fix-plan's own literal check text also lists a bare `inline-paste`
# alternative. That phrase is dropped here — "Skills cite this file; do NOT
# inline-paste the procedure" is the corpus's own CORRECT single-source-of-
# truth sentence (skill-structure.md §Reference graph), stated verbatim and
# legitimately in at least 8 `_shared/*.md` helpers (data-sources.md,
# spec-challenge.md, task-chain-context.md, tdd-cycle.md,
# verification-surface.md, design-doc-detect.md, memory-backend.md,
# prior-work-scan.md). Including it would hard-fail every one of them on
# their correct, load-bearing text — the opposite of what T2-5 asks for — so
# it fails this check's own zero-false-positive bar and is left out. The five
# phrases that remain are each evidenced by name in the finding and, checked
# individually against the corpus below, hit only genuine narration.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

PHRASES='Define ONCE|previously (specified|borrowed)|not yet routed|\bin v1\b|Block 5[a-z]'

# <dirs...> -> file:line:match for every narration-phrase hit.
_narration_hits() {
  grep -rnoE "$PHRASES" "$@" 2>/dev/null
}

checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  checked=$((checked + 1))
  f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"; m="${rest#*:}"
  report_fail "$f:$l — author-facing narration/maintainer note ships at runtime: \"$m\" — delete it (skill-authoring.md §2/§3)"
done < <(_narration_hits skills agents)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no skills/ or agents/ file carries an author-facing narration phrase ($checked hit(s) found)"
fi

# --- self-test: red on each seeded phrase, green on the excluded inline-paste text ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/_shared"

cat > "$SELFTEST_DIR/skills/_shared/violation.md" <<'EOF'
Canonical procedure for "before creating new code, check what already exists." Define ONCE here; reference from N consumers.
`/geniro:debug` cites this file for the open-PR check it previously specified inline.
This dim previously borrowed that inclusion rule.
- layer: learnings          # learnings (L2). snapshot (L3) reserved — not yet routed
- **layer** — `learnings` (L2) in v1.
## Errors # Block 5b (only on failure)
EOF

cat > "$SELFTEST_DIR/skills/_shared/clean.md" <<'EOF'
Single source of truth for the data-source verification primitive. Skills cite this file; do NOT inline-paste the procedure.
This file is the single source of truth. Skills cite this file; do NOT inline-paste the cycle steps or the state-file contract.
EOF

v=$(_narration_hits "$SELFTEST_DIR/skills/_shared/violation.md" | grep -c .)
if [ "$v" -ge 5 ]; then
  echo "OK: self-test — all 5 seeded narration phrases are detected ($v hit(s))"
else
  report_fail "self-test — expected >=5 seeded narration hits, got $v"
fi

c=$(_narration_hits "$SELFTEST_DIR/skills/_shared/clean.md" | grep -c .)
if [ "$c" -eq 0 ]; then
  echo "OK: self-test — the corpus's correct 'do NOT inline-paste' single-source-of-truth sentence does not false-positive"
else
  report_fail "self-test — the 'do NOT inline-paste' fixture false-positived ($c hit(s))"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS author-facing narration problem(s)." >&2
  exit 1
fi
echo "OK: skills/ and agents/ carry no author-facing narration phrase from the T2-5 list."
