#!/usr/bin/env bash
# build-cursor-skills.sh — regenerate cursor/skills/ from the canonical
# skills/<slug>/ sources.
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
#   - every other frontmatter field copied verbatim except three Claude-only
#     fields Cursor's Agent Skills spec does not recognize (allowed-tools,
#     model, argument-hint), which are dropped; the body copied verbatim
#     except AskUserQuestion -> AskQuestion (Cursor's tool name for it) —
#     both call sites below carry the full rationale. Output is prefixed
#     with a generated-file marker.
#
# Sibling files (skills/<slug>/phase-*.md, *-reference.md, templates, and any
# subdirectory) ARE copied alongside the SKILL.md, verbatim but for the same
# AskUserQuestion -> AskQuestion translation and a generated-file marker.
#
# They were deliberately left out until 2026-08, on the reasoning that every
# intra-skill reference already resolves through the fully-qualified
# `${CLAUDE_PLUGIN_ROOT}/skills/<slug>/...` form
# (`.claude/rules/skill-structure.md` §Cross-skill references) and that
# `${CLAUDE_PLUGIN_ROOT}` resolves regardless of which SKILL.md copy is doing
# the reading. That holds only while the plugin root resolves at all. A run
# that cannot resolve it reaches a SKILL.md whose every operative reference —
# the phase bodies holding the gates, the reference file holding the ship
# contract — is one unreachable hop away, and the observed failure is not a
# stalled run but a confident one that reconstructs the flow from the host
# project's own rules. Shipping the siblings makes rung 3 of
# `runtime-portability.md` §Plugin-root resolution ("a sibling copy of the
# target file beside this one") satisfiable per-file, with no root resolution
# needed. skills/_shared/ and agents/ are NOT copied: they are cross-cutting,
# so a per-skill copy would duplicate ~900KB fourteen times and drift.
#
# Cross-skill `/geniro:<slug>` references are left as-is: `runtime-
# portability.md` §Skill and agent naming already defines that token as "the
# skill in skills/<slug>/", resolved per-runtime — not a literal invocation
# string to rewrite.
#
# Run after any edit under skills/<slug>/ and commit the output;
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
  # Frontmatter fields Cursor's Agent Skills spec does not recognize:
  #   - allowed-tools names tools by their Claude Code identifiers (Bash,
  #     AskUserQuestion, ...) — worst of the three, since it asserts the
  #     question tool is called AskUserQuestion, which is false here.
  #   - model: inherit is a Claude Code SUBAGENT field, not a skill field.
  #   - argument-hint has no Cursor skill counterpart.
  # Dropped for the Cursor copy only; skills/<slug>/SKILL.md (Claude Code)
  # keeps all three untouched.
  frontmatter="$(awk 'c<2 && /^---$/{c++; next} c==1' "$src" | sed -e "s/^name:.*/name: $prefixed/" -e '/^allowed-tools:/d' -e '/^model:/d' -e '/^argument-hint:/d')"
  # Translate AskUserQuestion -> AskQuestion (Cursor's structured-question
  # tool) and nothing else. This is the one Claude-only tool name rewritten
  # here, not because it matters more than the others but because it is the
  # only one safe to rewrite with a blind sed: it is an exact identifier
  # that never occurs as an English word, so every occurrence IS the tool
  # name. The other Claude-only names that show up in these bodies — Bash,
  # Edit, Agent — are also ordinary English words in running prose ("via
  # Bash", "an Edit target", "the agent") and appear verbatim inside fenced
  # shell/heredoc blocks; a blunt substitution across those would corrupt
  # generated files in ways a diff review would not reliably catch. Those
  # are left as-is and handled instead by the name-mapping rule in
  # skills/_shared/runtime-portability.md, which every skill's preamble
  # already points readers at.
  body="$(awk 'c<2 && /^---$/{c++; next} c>=2' "$src" | sed 's/AskUserQuestion/AskQuestion/g')"

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
  # Clear first so a sibling deleted from the source disappears from the copy
  # instead of lingering as an orphan that only tests/cursor/build-skills-
  # fresh.sh's diff would ever surface. Bounded: $prefixed was validated to
  # a-z0-9- above, so this can only ever name a direct child of $OUT_DIR.
  rm -rf "$skill_out"
  mkdir -p "$skill_out"
  {
    printf -- '---\n'
    printf '%s\n' "$frontmatter"
    printf -- '---\n'
    printf '<!-- Generated from skills/%s/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->\n\n' "$name"
    printf '%s\n' "$body"
  } > "$skill_out/SKILL.md"

  # Sibling files, subdirectories preserved. The marker goes in as a leading
  # HTML comment, except on a file that opens with a `---` frontmatter fence
  # (skills/actions/example-actions/*.md) — anything before that fence stops it
  # parsing as frontmatter, so those copy through unmarked.
  #
  # Dot-files are skipped: a macOS `.DS_Store` picked up here would be
  # committed as generated output and then fail tests/cursor/build-skills-
  # fresh.sh on any machine that does not produce one. Nothing a skill Reads
  # at runtime is dot-prefixed.
  find "$dir" -type f ! -name SKILL.md ! -name '.*' | while IFS= read -r sib; do
    rel="${sib#"$dir"}"
    dest="$skill_out/$rel"
    mkdir -p "$(dirname "$dest")"
    case "$sib" in
      *.md)
        if [ "$(head -n 1 "$sib")" = "---" ]; then
          sed 's/AskUserQuestion/AskQuestion/g' "$sib" > "$dest"
        else
          {
            printf -- '<!-- Generated from skills/%s/%s by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->\n\n' "$name" "$rel"
            sed 's/AskUserQuestion/AskQuestion/g' "$sib"
          } > "$dest"
        fi
        ;;
      *) cp "$sib" "$dest" ;;
    esac
  done

  count=$((count + 1))
done

siblings=$(find "$OUT_DIR" -type f ! -name SKILL.md | wc -l | tr -d ' ')
echo "generated $count skills (+ $siblings sibling files) into $OUT_DIR" >&2
