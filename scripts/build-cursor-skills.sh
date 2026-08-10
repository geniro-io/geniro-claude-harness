#!/usr/bin/env bash
# build-cursor-skills.sh — regenerate cursor/skills/ from the canonical
# skills/<slug>/SKILL.md definitions.
#
# skills/<slug>/SKILL.md is the single source of truth. Claude Code namespaces
# every skill by plugin (`/geniro:<slug>`), so a bare directory name never
# collides. Cursor has no namespacing: it registers each skill under its bare
# directory name alongside its own built-in skills and reserved CLI slash
# commands, with no de-duplication or precedence rule for a clash — `review`
# and `onboard` collide with Cursor built-ins, `plan`, `debug`, and `update`
# collide with reserved CLI commands (cursor/README.md records the set).
#
# Every skill gets a derived copy at cursor/skills/geniro-<slug>/SKILL.md:
#   - directory renamed geniro-<slug>, frontmatter `name:` matched to it — the
#     Agent Skills spec requires `name` to be 1-64 chars of a-z0-9- and to
#     equal the parent directory. Prefixing is applied to EVERY skill, not
#     only the current colliders: a mixed bare/prefixed scheme would still
#     need a per-skill collision table, and a Cursor built-in added later
#     could collide with a name left bare — uniform prefixing needs neither.
#   - every other frontmatter field and the body copied verbatim, prefixed
#     with a generated-file marker.
#
# Sibling phase/reference files (skills/<slug>/phase-*.md, *-reference.md) are
# NOT copied. Every intra-skill reference in a skill body already resolves
# through the fully-qualified `${CLAUDE_PLUGIN_ROOT}/skills/<slug>/...` form
# (`.claude/rules/skill-structure.md` §Cross-skill references), and
# `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin root regardless of which
# directory the SKILL.md copy itself lives in (`runtime-portability.md`
# §Plugin-root resolution) — so those reads land on the one source of truth
# in skills/<slug>/ whether read from the Claude Code copy or this Cursor
# copy. Cross-skill `/geniro:<slug>` references are left as-is for the same
# reason: `runtime-portability.md` §Skill and agent naming already defines
# that token as "the skill in skills/<slug>/", resolved per-runtime — not a
# literal invocation string to rewrite.
#
# Run after any edit to skills/*/SKILL.md and commit the output;
# tests/cursor/build-skills-fresh.sh fails CI when the copies drift.
#
# Usage: scripts/build-cursor-skills.sh [output-dir]   (default: cursor/skills)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/cursor/skills}"
mkdir -p "$OUT_DIR"

count=0
for dir in "$REPO_ROOT"/skills/*/; do
  name="$(basename "$dir")"
  src="${dir}SKILL.md"
  [ -f "$src" ] || continue   # skills/_shared/ carries no SKILL.md — not a skill

  prefixed="geniro-$name"
  case "$prefixed" in
    *[!a-z0-9-]*)
      echo "ERROR: generated name '$prefixed' (from $src) has characters outside a-z0-9-" >&2
      exit 1
      ;;
  esac
  if [ "${#prefixed}" -gt 64 ]; then
    echo "ERROR: generated name '$prefixed' (from $src) exceeds the 64-char Agent Skills limit" >&2
    exit 1
  fi

  # Frontmatter = lines between the first two --- fences; body = the rest.
  # `c<2 &&` bounds the fence match to those first two lines only — without it,
  # `next` fires on EVERY line equal to `---` (a body-level horizontal rule, or
  # a `---` inside a fenced code block/heredoc), silently deleting each one
  # from the extracted text.
  name_line="$(awk 'c<2 && /^---$/{c++; next} c==1 && /^name:/' "$src")"
  if [ -z "$name_line" ]; then
    echo "ERROR: no name in $src frontmatter" >&2
    exit 1
  fi
  frontmatter="$(awk 'c<2 && /^---$/{c++; next} c==1' "$src" | sed "s/^name:.*/name: $prefixed/")"
  body="$(awk 'c<2 && /^---$/{c++; next} c>=2' "$src")"

  # Content-integrity guard: a regression in the fence-consumption awk above
  # would corrupt every body-level "---" (a horizontal rule, or a fence inside
  # a fenced heredoc) identically on both sides of the freshness diff — the
  # freshly regenerated copy and the already-corrupted committed copy would
  # match each other, so tests/cursor/build-skills-fresh.sh alone cannot catch
  # it. Assert directly against the source instead: every "---" beyond the
  # frontmatter's own two fences must survive into the body unchanged.
  src_fences=$(awk '/^---$/{n++} END{print n+0}' "$src")
  body_fences=$(printf '%s\n' "$body" | awk '/^---$/{n++} END{print n+0}')
  if [ "$body_fences" -ne "$((src_fences - 2))" ]; then
    echo "ERROR: $src has $src_fences '---' line(s); expected $((src_fences - 2)) to survive into the body (2 consumed as frontmatter fences), but found $body_fences. The fence-extraction awk ate one — refusing to write a corrupted $prefixed/SKILL.md." >&2
    exit 1
  fi

  skill_out="$OUT_DIR/$prefixed"
  mkdir -p "$skill_out"
  {
    printf -- '---\n'
    printf '%s\n' "$frontmatter"
    printf -- '---\n'
    printf '<!-- Generated from skills/%s/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->\n\n' "$name"
    printf '%s\n' "$body"
  } > "$skill_out/SKILL.md"
  count=$((count + 1))
done

echo "generated $count skills into $OUT_DIR" >&2
