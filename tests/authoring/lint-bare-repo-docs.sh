#!/usr/bin/env bash
# C3 (plugin-audit 2026-09-23, fix-plan §O / T2-3) — no skills/ or agents/ body
# cites this repo's own `ARCHITECTURE.md` or `CLAUDE.md` by a BARE (unrooted)
# section reference.
#
# Run: bash tests/authoring/lint-bare-repo-docs.sh
#
# Why this exists: a bare `` `ARCHITECTURE.md` §State Files `` in a shipped
# skill body resolves — at runtime, via a plain Read of a relative path —
# against the CONSUMER's own project root, not against this plugin's install
# directory, because Claude Code's cwd during a skill run is the user's
# project. A consumer session either has no such file, or has their OWN
# project's ARCHITECTURE.md, which is not this plugin's design-rationale doc.
# T2-3: `state-tier-spec.md`, `atomic-state-write.md`, `validate-state-file.md`,
# `model-tiering.md`, and `reporter-boundary.md` all cited one of these two
# repo-root docs bare.
#
# Scope decision (stated per the task's instruction to decide and say so): a
# ROOTED citation (`` `${CLAUDE_PLUGIN_ROOT}/ARCHITECTURE.md` §... ``, used at
# skills/implement/phase-3-ship.md:41 and implement-reference.md:576) is a
# DIFFERENT question from this one. It resolves correctly — ARCHITECTURE.md
# genuinely ships as part of the plugin's own repo/install tree — so it is
# not a dangling reference. Whether a shipped body should still point a
# downstream reader at this repo's OWN contributor design-rationale doc at
# all is a `skill-authoring.md` §2 "plugin-author-internal references"
# judgment call (taste: is the rationale worth the pointer, or should it be
# inlined), not a decidable file-resolution question — so it is out of scope
# here and stays a prose/D4 reviewer call. Only the BARE form, which is
# unambiguously broken regardless of taste, is hard-gated.
#
# Precision: bare mentions of `ARCHITECTURE.md` alone (with no section anchor)
# are common and legitimate — `skills/setup/phase-1-detect.md` and
# `phase-3-generate.md` list it as one of several candidate filenames a
# CONSUMER's own project might have (README.md, CONTRIBUTING.md, ARCHITECTURE.md,
# ...). Requiring an immediately-following `§` is what distinguishes "this repo's
# own contributor doc, cited for its content" from "a generic filename named
# as an example" — every real T2-3 site carries a `§`, and the setup candidate
# lists never do.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# <dirs...> -> file:line:match. A backtick immediately followed by the bare
# filename (no ${CLAUDE_PLUGIN_ROOT}/ or $PLUGIN_PATH/ prefix inside the
# backticks) excludes the rooted form by construction — the rooted spelling
# never has the filename right after the opening backtick.
_bare_doc_refs() {
  grep -rnoE '`(ARCHITECTURE|CLAUDE)\.md`[[:space:]]*§' "$@" 2>/dev/null
}

checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  checked=$((checked + 1))
  f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"; m="${rest#*:}"
  report_fail "$f:$l cites bare $m — resolves against the CONSUMER's project root, not this plugin's own doc; root it with \${CLAUDE_PLUGIN_ROOT}/ or delete the pointer per skill-authoring.md §2"
done < <(_bare_doc_refs skills agents)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no skills/ or agents/ file cites ARCHITECTURE.md or CLAUDE.md by a bare section reference ($checked candidate(s) found)"
fi

# --- self-test: red on a seeded bare citation; green on rooted + generic-list shapes ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/_shared" "$SELFTEST_DIR/skills/setup"

cat > "$SELFTEST_DIR/skills/_shared/violation.md" <<'EOF'
**Canonical reference for every state file.** See `ARCHITECTURE.md` §State Files for the design decisions behind this spec.
EOF

cat > "$SELFTEST_DIR/skills/_shared/rooted.md" <<'EOF'
See `${CLAUDE_PLUGIN_ROOT}/ARCHITECTURE.md` §State Files for the design decisions behind this spec.
The Skill routing rule is cited rooted too: `${CLAUDE_PLUGIN_ROOT}/CLAUDE.md` §Skill routing.
EOF

cat > "$SELFTEST_DIR/skills/setup/phase-1-detect.md" <<'EOF'
Candidate project doc filenames to look for:
- `README.md`, `CONTRIBUTING.md`, `CONVENTIONS.md`, `ARCHITECTURE.md`, `SECURITY.md`
EOF

v=$(_bare_doc_refs "$SELFTEST_DIR/skills/_shared/violation.md" | grep -c .)
if [ "$v" -ge 1 ]; then
  echo "OK: self-test — a seeded bare 'ARCHITECTURE.md §State Files' citation is detected"
else
  report_fail "self-test — seeded bare citation was NOT detected"
fi

c1=$(_bare_doc_refs "$SELFTEST_DIR/skills/_shared/rooted.md" | grep -c .)
c2=$(_bare_doc_refs "$SELFTEST_DIR/skills/setup/phase-1-detect.md" | grep -c .)
if [ "$c1" -eq 0 ] && [ "$c2" -eq 0 ]; then
  echo "OK: self-test — a \${CLAUDE_PLUGIN_ROOT}/-rooted citation and a generic candidate-filename list do not false-positive"
else
  report_fail "self-test — rooted ($c1 hit(s)) or generic-list ($c2 hit(s)) fixture false-positived"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS bare repo-doc citation problem(s)." >&2
  exit 1
fi
echo "OK: every ARCHITECTURE.md / CLAUDE.md section citation in skills/ and agents/ is plugin-root-rooted."
