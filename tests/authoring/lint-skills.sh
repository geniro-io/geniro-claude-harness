#!/usr/bin/env bash
# Authoring lint — the structural breakage a run actually hits: a skill that does
# not load, a path that does not resolve, a spawn that names no agent. Wording,
# size and style are not checked here (.claude/rules/tests.md).
#
# Run:    bash tests/authoring/lint-skills.sh
#
# Two severities:
#   HARD (exit non-zero) — zero-false-positive correctness checks:
#     1b. Frontmatter required fields on every SKILL.md (name, description,
#        context, model, allowed-tools, argument-hint), minus the documented
#        exemption (skills/actions has no allowed-tools).
#     1c. No XML/HTML tag shape (`<letter`) in a skills/*/SKILL.md `description:`
#        — the one field the host parses to decide whether to trigger a skill.
#     2. Dangling plugin-root file references — ${CLAUDE_PLUGIN_ROOT}/<path> and the
#        $PLUGIN_PATH/<path> form (target must exist).
#     3. Unknown subagent_type spawn names (must resolve to a real agent/builtin).
#     5. Rootless agents/ or skills/ file references in skills/ or agents/.
#     11. ${CLAUDE_PLUGIN_ROOT} inside .claude/skills/ (unset for project-local skills).
#   ADVISORY (warn only, exit 0 contribution):
#     6. Compaction boundary — a SKILL.md longer than the host's re-attach window
#        (REATTACH_CHARS characters), naming the last section that survives it.
#
# Portability: POSIX-ish bash + BSD/GNU-portable grep (no -P / PCRE) and awk.
# The compaction cut counts characters, not bytes, so it uses perl -CSD, present
# by default on macOS and every CI image: BSD/GNU awk disagree on whether
# length() counts bytes or characters.
#
# The checks carry self-tests at the bottom of the file (1b, 1c and the compaction
# cut), run on every invocation against fixtures in a scratch directory: each
# proves a seeded violation red and the allowed shapes green.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

HARD_FAILS=0
WARNS=0
report_fail() { HARD_FAILS=$((HARD_FAILS + 1)); echo "FAIL: $1" >&2; }
report_warn() { WARNS=$((WARNS + 1)); echo "WARN: $1"; }
rel() { printf '%s' "${1#"$REPO_ROOT"/}"; }

echo "=== HARD checks ==="

# 1b. Frontmatter required fields (skill-structure.md §Frontmatter hygiene). A
# SKILL.md missing `model`, `context` or `argument-hint` loads with the host's
# defaults instead of the declared ones, and nothing else looks at the block —
# the audit's frontmatter check was a manual D1 step. Zero false positives by
# construction: key presence at column 0 inside the first `---` block, over the
# 14 shipped and 5 internal SKILL.md files that all carry the six fields today.
FRONTMATTER_REQUIRED="name description context model allowed-tools argument-hint"

# <rel path> <field> -> 0 when that skill is the documented exception. The only
# one is /geniro:actions and `allowed-tools`: the field pre-approves tools and
# restricts nothing, so the skill declares none (skill-structure.md
# §Frontmatter hygiene records the exemption).
frontmatter_exempt() {
  [ "${1:-}:${2:-}" = "skills/actions/SKILL.md:allowed-tools" ]
}

# <file> -> one missing field name per line; "(no frontmatter block)" or
# "(unterminated frontmatter block)" when the block itself is absent.
frontmatter_missing() {
  awk -v req="$FRONTMATTER_REQUIRED" '
    BEGIN { n = split(req, r, " ") }
    NR == 1 { if ($0 != "---") { print "(no frontmatter block)"; bad = 1; exit } next }
    $0 == "---" { closed = 1; exit }
    { if (match($0, /^[A-Za-z][A-Za-z0-9_-]*:/)) have[substr($0, 1, RLENGTH - 1)] = 1 }
    END {
      if (bad) exit
      if (!closed) { print "(unterminated frontmatter block)"; exit }
      for (i = 1; i <= n; i++) if (!(r[i] in have)) print r[i]
    }
  ' "$1"
}

fm_problems=0
for f in skills/*/SKILL.md .claude/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  while IFS= read -r field; do
    [ -z "$field" ] && continue
    frontmatter_exempt "$f" "$field" && continue
    report_fail "$f: frontmatter lacks required field \`$field\` (skill-structure.md §Frontmatter hygiene)"
    fm_problems=$((fm_problems + 1))
  done <<< "$(frontmatter_missing "$f")"
done
[ "$fm_problems" -eq 0 ] && echo "OK: every SKILL.md frontmatter carries the required fields"

# 1c. No XML tags in a SKILL.md `description:` (skill-structure.md §Frontmatter
# hygiene description rule 4). The description is the ONE field Claude Code parses
# to decide whether to trigger a skill, so a stray `<branch>` placeholder (copied
# from a file-path example elsewhere in the body, e.g.
# `.geniro/state/handoff/from-debug-<branch>.md`) reads as an opening tag to
# anything that treats the field as markup.
# Detection: `<` immediately followed by a Latin letter anywhere in the
# description line — the shape an XML/HTML opening tag and a `<placeholder>` both
# take, so there is no "legitimate placeholder" carve-out to construct. `<` before
# a non-letter (a comparison, "latency < 200ms") does not match.
# <file>... -> file:line:description-line for every description: line carrying one.
_check_descriptions() {
  local f line
  for f in "$@"; do
    [ -f "$f" ] || continue
    line=$(grep -n '^description:' "$f" | head -1)
    [ -n "$line" ] || continue
    if printf '%s\n' "$line" | grep -qE '<[A-Za-z]'; then
      printf '%s\n' "$line" | sed "s#^#$f:#"
    fi
  done
}

desc_problems=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  fl="${hit%%:*}:$(printf '%s' "${hit#*:}" | cut -d: -f1)"
  snippet=$(printf '%s' "${hit#*:}" | cut -d: -f2- | sed 's/^[[:space:]]*//')
  report_fail "$fl — description: contains an angle-bracket placeholder (reads as an XML/HTML tag): $snippet"
  desc_problems=$((desc_problems + 1))
done < <(_check_descriptions skills/*/SKILL.md)
[ "$desc_problems" -eq 0 ] && echo "OK: no skills/*/SKILL.md description: contains a '<letter' angle-bracket placeholder"

# 2. Dangling plugin-root file references. Both spellings of the plugin root are
# scanned: ${CLAUDE_PLUGIN_ROOT}/<path>, and the $PLUGIN_PATH/<path> form /geniro:update
# uses against the freshly-installed tree — a rename that leaves one of those behind
# surfaces to the user as an integrity-check failure, so it has to fail here first.
# The trailing boundary stops a `.sha256` suffix from matching as `.sh`.
dangling=0
refs=$(grep -rhoE '(\$\{CLAUDE_PLUGIN_ROOT\}|\$PLUGIN_PATH)/[A-Za-z0-9._/-]+\.(md|sh|js|json)(\.example)?([^A-Za-z0-9]|$)' skills agents 2>/dev/null \
  | sed -E 's#(\$\{CLAUDE_PLUGIN_ROOT\}|\$PLUGIN_PATH)/##; s#[^A-Za-z0-9]$##' | sort -u)
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if [ ! -f "$p" ]; then report_fail "dangling plugin-root reference: $p (target file does not exist)"; dangling=$((dangling + 1)); fi
done <<< "$refs"
[ "$dangling" -eq 0 ] && echo "OK: all plugin-root file references resolve"

# 3. Unknown subagent_type spawn names.
valid_agents="$(mktemp)"
trap 'rm -f "$valid_agents"' EXIT
{ for f in agents/*.md; do basename "$f" .md; done; printf '%s\n' general-purpose Explore Plan statusline-setup; } \
  | sort -u > "$valid_agents"
unknown=0
spawns=$(grep -rhoE 'subagent_type[=:][[:space:]]*"?(geniro:)?[A-Za-z0-9_:-]+' skills agents 2>/dev/null \
  | sed -E 's/.*subagent_type[=:][[:space:]]*"?//; s/^geniro://' | grep -v '^$' | sort -u)
while IFS= read -r s; do
  [ -z "$s" ] && continue
  if ! grep -qxF "$s" "$valid_agents"; then report_fail "unknown subagent_type spawn: '$s' (no agents/$s.md and not a known builtin)"; unknown=$((unknown + 1)); fi
done <<< "$spawns"
rm -f "$valid_agents"
[ "$unknown" -eq 0 ] && echo "OK: all subagent_type spawns resolve to a real agent or builtin"

# 5. Rootless agent/skill file references. A bare `agents/<name>.md` or
# `skills/<x>/<y>.md` resolves against the CONSUMER's repo, where neither
# directory exists, so the runtime Read silently misses. Only ${CLAUDE_PLUGIN_ROOT}/
# (or the $PLUGIN_PATH/ form /geniro:update uses) resolves in an install.
# Two false positives are excluded by construction: a directory mentioned in prose
# carries no file extension and cannot match; and a path already inside a rooted
# reference is preceded by `/`, which the leading character class rejects — the
# same exclusion that keeps repo-local `.claude/skills/...` paths (correctly bare)
# out of the check.
rootless=0
rootless_hits=$(grep -rnoE '(^|[^A-Za-z0-9_./{$-])(agents|skills)/[A-Za-z0-9._/-]+\.(md|sh|js|json)' skills agents 2>/dev/null || true)
while IFS= read -r h; do
  [ -z "$h" ] && continue
  report_fail "rootless plugin file reference: $h — prefix it with \${CLAUDE_PLUGIN_ROOT}/ or it dangles in a consumer install"
  rootless=$((rootless + 1))
done <<< "$rootless_hits"
[ "$rootless" -eq 0 ] && echo "OK: every agents/ and skills/ file reference is plugin-root-rooted"

# 11. `${CLAUDE_PLUGIN_ROOT}` inside `.claude/skills/`. That variable is set by
#     Claude Code only for plugin skills under skills/ — it is unset for the
#     project-local skills under .claude/skills/, so a citation there resolves
#     against an empty prefix (a Read silently misses; a Bash `source` fails
#     outright). Check 2 above cannot catch this: its scope is `skills agents`,
#     and it also requires a trailing /path, which a bare `${CLAUDE_PLUGIN_ROOT}`
#     mention skips. The token has no legitimate use inside .claude/skills/ at
#     all, so the bar here is absolute — zero is the only passing count.
meta_root_refs=$(grep -rlF '${CLAUDE_PLUGIN_ROOT}' .claude/skills 2>/dev/null || true)
if [ -n "$meta_root_refs" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    report_fail "$(rel "$f") references \${CLAUDE_PLUGIN_ROOT}, which is unset for project-local skills — use a repo-relative path"
  done <<< "$meta_root_refs"
else
  echo "OK: .claude/skills/ carries no \${CLAUDE_PLUGIN_ROOT} references"
fi

echo
echo "=== ADVISORY checks (warn only) ==="

# 6. Compaction boundary. Claude Code re-attaches only the first 5,000 tokens of a
#    skill after compaction, so anything past it is absent for the rest of a
#    compacted session. Measured over BOTH skill populations: skills/ (shipped to
#    users) and .claude/skills/ (this repo's internal meta-skills), which Claude
#    Code loads and compacts identically.
#
# The host re-attaches a TRUNCATED skill body after a compaction, and it cuts by
# CHARACTERS, not words: measured at exactly 20,000 in a live session, landing
# mid-sentence with a truncation marker in place of the rest.
REATTACH_CHARS=20000

# The host cuts by CHARACTERS, so everything here counts characters. wc -c and an
# awk length() both count bytes under some locales (an em-dash is 3 bytes; this
# corpus has ~7,800 of them), which put the cut in the wrong place: it named
# "Phase 4" (1 section lost) as the last surviving section of reflect when the
# real figure is REFERENCE (0 lost), and "Memory I/O" (5 lost) for refactor when
# it is Definition of done (4 lost). perl -CSD decodes UTF-8 on read, so
# length() is characters on macOS and Linux alike.
char_count() {
  perl -CSD -0777 -ne 'print length($_)' "$1" 2>/dev/null
}

# Name the last H2 that still fits inside the re-attach window and how many fall past
# it, so the warning says WHICH sections stop being re-attached, not just that the
# file is big. Output: "<last surviving H2>|<count lost>", empty when nothing is lost.
frontload_cut() {
  perl -CSD -e '
    my ($lim, $file) = @ARGV;
    open(my $fh, "<", $file) or exit 0;
    my ($c, $lost, $last) = (0, 0, "");
    while (my $line = <$fh>) {
      chomp $line;
      if ($line =~ /^## /) { if ($c >= $lim) { $lost++ } else { $last = $line } }
      $c += length($line) + 1;
    }
    printf "%s|%d\n", $last, $lost if $lost > 0;
  ' "$REATTACH_CHARS" "$1" 2>/dev/null
}

check_compaction_boundaries() {
  local f r chars cut lost pct
  for f in "$@"; do
    [ -f "$f" ] || continue
    r=$(rel "$f")
    chars=$(char_count "$f")
    if [ "$chars" -gt "$REATTACH_CHARS" ]; then
      cut=$(frontload_cut "$f")
      if [ -n "$cut" ]; then
        lost=${cut##*|}
        cut=${cut%|*}
        pct=$(( (chars - REATTACH_CHARS) * 100 / chars ))
        report_warn "$r: compaction re-attaches only the first $REATTACH_CHARS chars — last surviving section is \"$cut\"; $lost after it ($pct% of the file) are dropped once the session compacts"
      fi
    fi
  done
}

check_compaction_boundaries skills/*/SKILL.md .claude/skills/*/SKILL.md

# === SELF-TESTS ===========================================================
# Each fixture lives in a scratch directory and drives the same functions the
# checks above run, so a seeded violation proves the matcher red and the allowed
# shapes prove it green. A self-test failure is a hard failure: a lint whose
# matcher silently stopped matching is worse than no lint.
echo
echo "=== SELF-TESTS (check 1b, check 1c, compaction cut) ==="
ST="$(mktemp -d)"
trap 'rm -rf "$ST"' EXIT

# Check 1b — frontmatter required fields.
cat > "$ST/fm-complete.md" <<'EOF'
---
name: probe
description: "Use when probing."
context: main
model: inherit
allowed-tools: [Read]
argument-hint: "[x]"
---
# Probe
EOF
cat > "$ST/fm-partial.md" <<'EOF'
---
name: probe
description: "Use when probing."
allowed-tools: [Read]
---
# Probe
model: inherit  (a body line is not frontmatter)
EOF
printf '# No frontmatter at all\n' > "$ST/fm-none.md"
printf -- '---\nname: probe\ncontext: main\n' > "$ST/fm-unterminated.md"

if [ -z "$(frontmatter_missing "$ST/fm-complete.md")" ]; then
  echo "OK: self-test — a SKILL.md carrying all six fields reports nothing missing"
else
  report_fail "self-test — the complete frontmatter fixture reported: $(frontmatter_missing "$ST/fm-complete.md" | tr '\n' ' ')"
fi
if [ "$(frontmatter_missing "$ST/fm-partial.md" | tr '\n' ' ')" = "context model argument-hint " ]; then
  echo "OK: self-test — missing context / model / argument-hint are named (a body line 'model: inherit' does not count)"
else
  report_fail "self-test — partial frontmatter fixture reported: $(frontmatter_missing "$ST/fm-partial.md" | tr '\n' ' ')"
fi
if [ "$(frontmatter_missing "$ST/fm-none.md")" = "(no frontmatter block)" ] && [ "$(frontmatter_missing "$ST/fm-unterminated.md")" = "(unterminated frontmatter block)" ]; then
  echo "OK: self-test — a file with no frontmatter block and one with an unterminated block are both reported"
else
  report_fail "self-test — absent/unterminated frontmatter blocks were not reported"
fi
if frontmatter_exempt skills/actions/SKILL.md allowed-tools \
   && ! frontmatter_exempt skills/actions/SKILL.md model \
   && ! frontmatter_exempt skills/plan/SKILL.md allowed-tools; then
  echo "OK: self-test — the allowed-tools exemption covers skills/actions only, and only that field"
else
  report_fail "self-test — the frontmatter exemption is wider or narrower than skills/actions allowed-tools"
fi

# Check 1c — red on a seeded '<branch>'-style description, green on a clean one.
mkdir -p "$ST/desc-violation" "$ST/desc-clean"
cat > "$ST/desc-violation/SKILL.md" <<'EOF'
---
name: probe
description: "Use when probing. Writes a handoff to .geniro/state/handoff/from-debug-<branch>.md."
context: main
---

# Probe
EOF
cat > "$ST/desc-clean/SKILL.md" <<'EOF'
---
name: probe
description: "Use when probing. Writes a handoff to .geniro/state/handoff/from-debug-{branch}.md. Latency < 200ms."
context: main
---

# Probe
EOF
if [ "$(_check_descriptions "$ST/desc-violation/SKILL.md" | grep -c .)" -ge 1 ]; then
  echo "OK: self-test — a seeded '<branch>' placeholder in description: is detected"
else
  report_fail "self-test — seeded '<branch>' violation in description: was NOT detected"
fi
if [ "$(_check_descriptions "$ST/desc-clean/SKILL.md" | grep -c .)" -eq 0 ]; then
  echo "OK: self-test — a '{branch}' placeholder and a '< 200ms' comparison do not false-positive"
else
  report_fail "self-test — the clean description fixture ('{branch}' + '< 200ms') false-positived"
fi

# Compaction cut — characters, not bytes. The multibyte fixture is ~10,000
# characters but ~30,000 bytes: counting bytes puts its second section past the
# 20,000 cut and invents a loss; counting characters reports none.
perl -CSD -e 'print "## A\n", "\x{2014}" x 10000, "\n## B\nbody\n"' > "$ST/cut-multibyte.md"
perl -e 'print "## A\n", "x" x 20100, "\n## B\n## C\n"' > "$ST/cut-ascii.md"
if [ "$(char_count "$ST/cut-multibyte.md")" = "10016" ] && [ -z "$(frontload_cut "$ST/cut-multibyte.md")" ]; then
  echo "OK: self-test — a 10,016-character / ~30,000-byte file is measured in characters and loses no section"
else
  report_fail "self-test — multibyte cut fixture: chars=$(char_count "$ST/cut-multibyte.md") (want 10016), cut=[$(frontload_cut "$ST/cut-multibyte.md")] (want empty)"
fi
if [ "$(frontload_cut "$ST/cut-ascii.md")" = "## A|2" ]; then
  echo "OK: self-test — the cut names the last section that fits ('## A') and counts the 2 sections after it"
else
  report_fail "self-test — ascii cut fixture reported [$(frontload_cut "$ST/cut-ascii.md")], want [## A|2]"
fi

echo
echo "==================================================="
echo "Hard failures: $HARD_FAILS"
echo "Warnings:      $WARNS"
[ "$HARD_FAILS" -eq 0 ]
