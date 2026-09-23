#!/usr/bin/env bash
# C10 (plugin-audit 2026-09-23, fix-plan §O / T3-10) — every quoted
# `argument-hint: "..."` line in flags-reference.md's per-skill catalog must
# equal that skill's real SKILL.md frontmatter `argument-hint:`.
#
# Run: bash tests/authoring/lint-flags-reference-sync.sh
#
# Why this exists: skills/_shared/flags-reference.md restates each catalogued
# skill's `argument-hint:` as a quoted line right under its `## /geniro:<slug>`
# heading, so a reader sees the exact CLI shape next to the flag table
# explaining it. T3-10: the catalog drifted (implement's copy was missing
# `--subagent-model`; review's was missing `--focus`, `--subagent-model`, and
# `--brief|--no-brief`) — a copy nobody re-diffs against the frontmatter it
# restates.
#
# Detection: parse flags-reference.md into `<slug>` sections by its own
# `## /geniro:<slug>` headings, take the first quoted `argument-hint: "..."`
# line under each, and byte-compare it against `skills/<slug>/SKILL.md`'s
# frontmatter `argument-hint:` value. A skill the catalog does not cover (no
# `## /geniro:<slug>` heading) is out of scope by construction — the catalog
# itself is scoped to "every flag /plan, /implement, and /review accept" and
# says so, so a 4th skill's absence is not this check's question.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

CATALOG="skills/_shared/flags-reference.md"

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# <catalog-file> -> "<slug><TAB><quoted-argument-hint-value>" for each
# `## /geniro:<slug>` section's first `argument-hint: "..."` line.
_catalog_hints() {
  awk '
    /^## \/geniro:/ { slug = $0; sub(/^## \/geniro:/, "", slug); next }
    /^`argument-hint: "/ && slug != "" {
      line = $0
      sub(/^`argument-hint: "/, "", line)
      sub(/"`?$/, "", line)
      print slug "\t" line
      slug = ""   # only the FIRST hint line per section counts
    }
  ' "$1" 2>/dev/null
}

# <skill.md> -> the quoted value of its frontmatter argument-hint: line.
_skill_hint() {
  awk -F'"' '/^argument-hint:/ { print $2; exit }' "$1" 2>/dev/null
}

checked=0
while IFS=$'\t' read -r slug catalog_hint; do
  [ -n "$slug" ] || continue
  skill_file="skills/$slug/SKILL.md"
  [ -f "$skill_file" ] || continue
  checked=$((checked + 1))
  real_hint="$(_skill_hint "$skill_file")"
  if [ "$catalog_hint" != "$real_hint" ]; then
    report_fail "$CATALOG's /geniro:$slug argument-hint quote is stale — catalog: \"$catalog_hint\" vs $skill_file: \"$real_hint\""
  fi
done < <(_catalog_hints "$CATALOG")

if [ "$FAILS" -eq 0 ]; then
  echo "OK: every flags-reference.md quoted argument-hint matches its SKILL.md frontmatter ($checked skill(s) checked)"
fi

# --- self-test: red on a seeded stale quote, green when catalog == frontmatter ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/_shared" "$SELFTEST_DIR/skills/probe"

cat > "$SELFTEST_DIR/skills/probe/SKILL.md" <<'EOF'
---
name: probe
argument-hint: "[task] [--subagent-model <tier>] [--focus <text>]"
---
EOF

cat > "$SELFTEST_DIR/skills/_shared/stale.md" <<'EOF'
## /geniro:probe

`argument-hint: "[task] [--subagent-model <tier>]"`
EOF

cat > "$SELFTEST_DIR/skills/_shared/fresh.md" <<'EOF'
## /geniro:probe

`argument-hint: "[task] [--subagent-model <tier>] [--focus <text>]"`
EOF

( cd "$SELFTEST_DIR" || exit 1
  v=0
  while IFS=$'\t' read -r slug catalog_hint; do
    [ -n "$slug" ] || continue
    sf="skills/$slug/SKILL.md"
    [ -f "$sf" ] || continue
    rh="$(awk -F'"' '/^argument-hint:/ { print $2; exit }' "$sf")"
    [ "$catalog_hint" != "$rh" ] && v=$((v + 1))
  done < <(awk '
    /^## \/geniro:/ { slug = $0; sub(/^## \/geniro:/, "", slug); next }
    /^`argument-hint: "/ && slug != "" {
      line = $0
      sub(/^`argument-hint: "/, "", line)
      sub(/"`?$/, "", line)
      print slug "\t" line
      slug = ""
    }
  ' skills/_shared/stale.md)
  if [ "$v" -ge 1 ]; then
    echo "OK: self-test — a seeded stale catalog quote (missing --focus) is detected"
  else
    echo "FAIL: self-test — seeded stale quote was NOT detected" >&2
    exit 1
  fi
) || report_fail "self-test — the seeded stale-quote scenario did not fail as expected"

( cd "$SELFTEST_DIR" || exit 1
  c=0
  while IFS=$'\t' read -r slug catalog_hint; do
    [ -n "$slug" ] || continue
    sf="skills/$slug/SKILL.md"
    [ -f "$sf" ] || continue
    rh="$(awk -F'"' '/^argument-hint:/ { print $2; exit }' "$sf")"
    [ "$catalog_hint" != "$rh" ] && c=$((c + 1))
  done < <(awk '
    /^## \/geniro:/ { slug = $0; sub(/^## \/geniro:/, "", slug); next }
    /^`argument-hint: "/ && slug != "" {
      line = $0
      sub(/^`argument-hint: "/, "", line)
      sub(/"`?$/, "", line)
      print slug "\t" line
      slug = ""
    }
  ' skills/_shared/fresh.md)
  if [ "$c" -eq 0 ]; then
    echo "OK: self-test — a catalog quote that matches the frontmatter exactly does not false-positive"
  else
    echo "FAIL: self-test — the matching-quote fixture false-positived ($c mismatch(es))" >&2
    exit 1
  fi
) || report_fail "self-test — the matching-quote (clean) scenario false-positived"

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS flags-reference.md argument-hint drift problem(s)." >&2
  exit 1
fi
echo "OK: flags-reference.md's argument-hint quotes are all in sync with their SKILL.md frontmatter."
