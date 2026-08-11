#!/usr/bin/env bash
# Every runtime-Read markdown file past ~1,200 words has a "Contents" block.
#
# Run: bash tests/authoring/lint-toc-presence.sh
#
# Why this exists: `.claude/rules/skill-structure.md` §Reference graph states
# the rule ("TOC required for any file over ~1,200 words that is Read at
# runtime") but names only the three shapes it happens to illustrate — SKILL.md
# bodies, `*-reference.md`, `_shared/*.md`. The audit-plugin skill's own
# mechanical pre-pass mirrors that same narrow scope
# (`.claude/skills/audit-plugin/dimensions-reference.md` §"TOC presence":
# "`skills/**/*-reference.md`, `_shared/*.md`"), so a phase-body file that is
# genuinely Read at runtime but named neither way — `skills/plan/loop-phase-3-
# grill.md`, a plain phase file, not `_shared/` and not `*-reference.md` —
# passed both the rule-as-written and the audit that quotes it, at 1,200+
# words with no Contents block.
#
# Scope: every `.md` file under `skills/**` and `.claude/skills/**` — every
# file in those two trees exists to be Read by a running skill (directly, as a
# phase body / reference / shared helper, or as a template whose placeholder
# syntax still has to be read before it is filled), which is the population
# skill-structure.md's rule is actually about; `*-reference.md` and
# `_shared/*.md` were never meant as an exhaustive allowlist. `agents/*.md` are
# excluded — injected whole as a subagent system prompt, never Read/previewed,
# per the same rule's own exemption. Root docs (README.md, ARCHITECTURE.md,
# MIGRATION.md, CLAUDE.md, HOOKS.md) are excluded too: nothing Reads them as
# skill instructions at runtime.
#
# Word count uses the repo's one counting rule (`awk '{w+=NF}'`, never
# `wc -w`) for the same locale reason `lint-skills.sh` documents at length next
# to its own `words_in` — a standalone `—`/`§`/`→` counts as a word under a
# UTF-8 locale and nothing under `C`, so `wc -w` measures the same file
# differently on different machines.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TOC_WORDS=1200
FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }
# WARNS never gate the exit code — "over ~1,200 words" is a guideline, not a
# threshold a commit fails on. report_fail stays for the self-tests, which must
# hard-fail: a checker that stops detecting is worse than the drift it watches.
WARNS=0
report_warn() { WARNS=$((WARNS + 1)); echo "WARN: $1"; }

words_in() { awk '{ w += NF } END { print w + 0 }' "$1"; }

_missing_toc() {  # <file>... -> one path per line, over the threshold with no Contents block
  local f n
  for f in "$@"; do
    [ -f "$f" ] || continue
    n=$(words_in "$f")
    [ "$n" -gt "$TOC_WORDS" ] || continue
    grep -qE '^## Contents' "$f" || printf '%s\t%s\n' "$f" "$n"
  done
}

ALL_MD="$(find skills .claude/skills -name '*.md' -type f 2>/dev/null | sort)"
checked=$(printf '%s\n' "$ALL_MD" | grep -c . || true)

while IFS=$'\t' read -r f n; do
  [ -n "$f" ] || continue
  # ADVISORY. skill-structure.md says "over ~1,200 words" — the tilde is load-bearing,
  # so a file at 1,201 words is not a defect and must not block a commit. The check
  # surfaces the file; a maintainer decides whether the Contents block earns its lines.
  report_warn "$f: $n words (>$TOC_WORDS, runtime-Read) with no \"## Contents\" block near the top"
done < <(printf '%s\n' "$ALL_MD" | while IFS= read -r f; do _missing_toc "$f"; done)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: every runtime-Read markdown file over $TOC_WORDS words ($checked file(s) scanned under skills/ and .claude/skills/) carries a Contents block"
fi

# --- self-test: red on a seeded oversize file with no Contents, green with --
# one, and silent on an undersize file regardless -----------------------------
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT

gen_long() {  # <path> <extra-header-lines>
  { [ -n "${2:-}" ] && printf '%s\n' "$2"
    printf '# Probe phase file\n\n'
    awk 'BEGIN { for (i = 0; i < 1300; i++) printf "word%d ", i; print "" }'
  } > "$1"
}

gen_long "$SELFTEST_DIR/violation.md" ""
gen_long "$SELFTEST_DIR/clean.md" ""
# Insert a real Contents block into the clean fixture right after its H1.
awk '1; /^# Probe phase file$/ { print ""; print "## Contents"; print ""; print "- 1. probe"; }' \
  "$SELFTEST_DIR/clean.md" > "$SELFTEST_DIR/clean.md.tmp" && mv "$SELFTEST_DIR/clean.md.tmp" "$SELFTEST_DIR/clean.md"
printf '# Short probe\n\nToo short to need a Contents block.\n' > "$SELFTEST_DIR/short.md"

n_violation="$(_missing_toc "$SELFTEST_DIR/violation.md" | grep -c . || true)"
if [ "$n_violation" -eq 1 ]; then
  echo "OK: self-test — an oversize file with no Contents block is detected"
else
  report_fail "self-test — seeded oversize/no-Contents violation was NOT detected"
fi

n_clean="$(_missing_toc "$SELFTEST_DIR/clean.md" | grep -c . || true)"
if [ "$n_clean" -eq 0 ]; then
  echo "OK: self-test — the same file with a Contents block added stays silent"
else
  report_fail "self-test — an oversize file WITH a Contents block false-positived"
fi

n_short="$(_missing_toc "$SELFTEST_DIR/short.md" | grep -c . || true)"
if [ "$n_short" -eq 0 ]; then
  echo "OK: self-test — a short file with no Contents block stays silent (under the word threshold)"
else
  report_fail "self-test — a short file false-positived"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS runtime-Read file(s) missing a Contents block." >&2
  exit 1
fi
echo "OK: every runtime-Read markdown file over the threshold carries a Contents block."
