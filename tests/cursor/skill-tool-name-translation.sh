#!/usr/bin/env bash
# Cursor tool-name + frontmatter-field translation in scripts/build-cursor-skills.sh.
#
# Run: bash tests/cursor/skill-tool-name-translation.sh
#
# Regression this guards: a generated cursor/skills/geniro-<slug>/SKILL.md
# that still says `AskUserQuestion` (Claude Code's structured-question tool)
# sends a Cursor run looking for a tool that genuinely does not exist there
# — Cursor's is `AskQuestion` — and it falls back to asking in prose with
# lettered options instead of the structured gate every skill's phase files
# expect. Same failure shape for a frontmatter field Cursor's Agent Skills
# spec does not recognize (`allowed-tools`, `model`, `argument-hint`):
# `allowed-tools` in particular re-asserts the Claude tool name inside the
# frontmatter itself, so dropping the body's AskUserQuestion is not enough
# on its own.
#
# Coverage:
#   - AskUserQuestion appears zero times anywhere under a freshly generated
#     cursor/skills/ (both the body substitution and the allowed-tools drop
#     have to hold for this to be zero — allowed-tools alone names it too).
#     Tree-wide on purpose: the generator translates the sibling phase and
#     reference files it copies alongside each SKILL.md, and those name the
#     question tool far more often than the spine does.
#   - allowed-tools / model / argument-hint are absent from every generated
#     SKILL.md, the file Cursor reads as the skill's manifest. Scoped to
#     SKILL.md, not the tree: a sibling may carry those strings as content
#     and be correct — skills/actions/skill-template.md is a template whose
#     whole purpose is showing an author what a skill's frontmatter looks
#     like, example-actions/*.md are authored skills with real frontmatter of
#     their own, and instructions-authoring-reference.md documents a scaffold.
#     None of them is a Cursor skill manifest, and stripping those lines
#     would corrupt the very content they exist to carry.
#
# Deliberately NOT asserted: absence of Bash / Edit / Agent. Those are
# ordinary English words in running prose ("via Bash", "an Edit target",
# "the agent") and appear verbatim inside fenced shell/heredoc blocks, so
# the generator intentionally leaves them untranslated in the body — see
# scripts/build-cursor-skills.sh's substitution-site comment and
# skills/_shared/runtime-portability.md's name-mapping rule, which is what
# actually covers them at read time. Asserting their absence here would
# fail on every legitimate occurrence and get this test disabled.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

if ! bash "$REPO_ROOT/scripts/build-cursor-skills.sh" "$TMP" >/dev/null 2>&1; then
  echo "FAIL: scripts/build-cursor-skills.sh errored" >&2
  exit 1
fi

REGEN_HINT="run 'bash scripts/build-cursor-skills.sh' and inspect scripts/build-cursor-skills.sh's substitution/drop site — this should not reproduce there"

# --- AskUserQuestion must never survive into a generated Cursor skill ---
HITS="$(grep -rl 'AskUserQuestion' "$TMP" 2>/dev/null || true)"
if [ -z "$HITS" ]; then
  pass "no generated Cursor skill says AskUserQuestion (Cursor's tool is AskQuestion)"
else
  fail "AskUserQuestion leaked into generated Cursor skill(s): $HITS — $REGEN_HINT"
fi

# --- and the translated name actually shows up, so this isn't just "the
#     word never occurs in these skills" passing vacuously ---
if grep -rq 'AskQuestion' "$TMP" 2>/dev/null; then
  pass "AskQuestion (the translated name) is present in the generated output"
else
  fail "AskQuestion never appears in generated output — the substitution may not be running at all"
fi

# --- the three Claude-only frontmatter fields must be dropped from every
#     generated SKILL.md; skills/<slug>/SKILL.md (Claude Code) is untouched
#     and out of scope for this assertion, as are the copied siblings (see
#     the scope note in the header) ---
MANIFESTS="$(find "$TMP" -name SKILL.md)"
if [ -z "$MANIFESTS" ]; then
  fail "no generated SKILL.md found under $TMP — the generator produced nothing to assert on"
fi
for key in allowed-tools model argument-hint; do
  HITS="$(grep -l "^${key}:" $MANIFESTS 2>/dev/null || true)"
  if [ -z "$HITS" ]; then
    pass "generated SKILL.md frontmatter never carries '$key:' (not a Cursor skill field)"
  else
    fail "'$key:' survived into generated SKILL.md frontmatter: $HITS — $REGEN_HINT"
  fi
done

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
