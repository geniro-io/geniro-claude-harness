#!/usr/bin/env bash
# Authoring lint — mechanizes the manual greps in .claude/rules/skill-structure.md
# §Pre-commit verification and .claude/rules/skill-authoring.md §Hard exclusions.
#
# Run: bash tests/authoring/lint-skills.sh
#
# Two severities:
#   HARD (exit non-zero) — zero-false-positive correctness checks:
#     1. Non-Latin (Cyrillic) letters in skills/ or agents/ bodies.
#     2. Dangling plugin-root file references — ${CLAUDE_PLUGIN_ROOT}/<path> and the
#        $PLUGIN_PATH/<path> form (target must exist).
#     3. Unknown subagent_type spawn names (must resolve to a real agent/builtin).
#   ADVISORY (warn only, exit 0 contribution) — guideline checks the maintainer
#   reads but never auto-trims to satisfy (size targets are guidelines, not limits):
#     4. SKILL.md word count vs the front-load budget and whole-file guideline,
#        across BOTH skill populations (shipped skills/ and internal .claude/skills/).
#     5. Anti-rationalization tables over the 15-row guideline.
#     6. Decaying line-number cross-references (file.md:NNN).
#     7. Normative sentences repeated across 3+ files (say it once, in one place).
#
# Portability: pure POSIX-ish bash + BSD/GNU-portable grep (no -P / PCRE).
# Cyrillic detection uses a byte-class match (UTF-8 lead bytes 0xD0/0xD1) so it
# is precise (does not flag the allowed em-dash / arrows / § / ≥ / curly quotes,
# whose lead bytes are 0xC2/0xC3/0xE2) and runs identically on macOS and Linux.
# Scope note: only Cyrillic (the documented real contamination risk for this
# repo) is hard-gated. Greek/Han/Hiragana are intentionally NOT gated — a broad
# non-ASCII check would false-positive on the very glyphs the repo allows, which
# is exactly why the precise byte-class is used over rule §1's broader net.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

HARD_FAILS=0
WARNS=0
report_fail() { HARD_FAILS=$((HARD_FAILS + 1)); echo "FAIL: $1" >&2; }
report_warn() { WARNS=$((WARNS + 1)); echo "WARN: $1"; }
rel() { printf '%s' "${1#"$REPO_ROOT"/}"; }

echo "=== HARD checks ==="

# 1. Non-Latin (Cyrillic) letters — the documented real contamination risk.
cyr_files=$(LC_ALL=C grep -ralE $'[\xd0\xd1]' skills agents 2>/dev/null || true)
if [ -n "$cyr_files" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    report_fail "non-Latin (Cyrillic) bytes in $(rel "$f") — skill/agent bodies must be English-only"
  done <<< "$cyr_files"
else
  echo "OK: no Cyrillic in skills/ or agents/"
fi

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

echo
echo "=== ADVISORY checks (warn only) ==="

# 4. SKILL.md size, measured in WORDS per skill-structure.md §File-size limits.
#    Not lines: a skill body here runs 9-21 words/line depending on table density,
#    so a line count ranks files backwards (setup 571L/5267W vs resolve 142L/3044W).
#    The front-load budget is the load-bearing figure — Claude Code re-attaches only
#    the first 5,000 tokens of a skill after compaction (~3,000 words of table-dense
#    markdown), so anything past it is absent for the rest of a compacted session.
#
#    Measured over BOTH skill populations: skills/ (shipped to users) and
#    .claude/skills/ (this repo's internal meta-skills — audit-plugin,
#    improve-template, analyze-thread, find-threads). Claude Code loads and
#    compacts them identically, so an unmeasured meta-skill silently drops its
#    own user gates, anti-rationalization table and Definition of Done past the
#    boundary — exactly the failure the check exists to surface.
FRONTLOAD_WORDS=3000
WHOLEFILE_WORDS=5000
check_skill_sizes() {
  local f n cut
  for f in "$@"; do
    [ -f "$f" ] || continue
    n=$(wc -w < "$f" | tr -d ' ')
    if [ "$n" -gt "$WHOLEFILE_WORDS" ]; then
      report_warn "$(rel "$f"): $n words (whole-file guideline <=$WHOLEFILE_WORDS)"
    fi
    if [ "$n" -gt "$FRONTLOAD_WORDS" ]; then
      # Name the last H2 that still fits inside the front-load budget, so the warning
      # says WHICH sections stop being re-attached rather than just that the file is big.
      cut=$(awk -v lim="$FRONTLOAD_WORDS" '
        /^## / { last = $0 }
        { w += NF; if (w > lim && !done) { print last; done = 1 } }
      ' "$f")
      [ -n "$cut" ] && report_warn "$(rel "$f"): compaction boundary (~$FRONTLOAD_WORDS words) falls at \"$cut\" — sections after it are dropped once the session compacts"
    fi
  done
}
check_skill_sizes skills/*/SKILL.md .claude/skills/*/SKILL.md

# Corpus shape, not per-file compliance: a median that creeps up is the signal to
# act on, and one oversize skill among lean ones is a different problem from all of
# them drifting together. INFO, not a warning — it never needs "fixing" on its own.
# Reported per population: the two have different sizes and different owners, so a
# single merged median would hide a drift in either one.
corpus_info() {
  local label="$1"; shift
  local f words
  words=$(for f in "$@"; do [ -f "$f" ] && wc -w < "$f"; done | tr -d ' ')
  [ -n "$words" ] || return 0
  echo "INFO: $label word counts — $(printf '%s\n' "$words" | sort -n | awk -v lim="$FRONTLOAD_WORDS" '
    {a[NR]=$1; if ($1 > lim) over++}
    END {printf "median %d, range %d-%d, %d of %d over the ~%d-word front-load budget",
         (NR%2 ? a[(NR+1)/2] : int((a[NR/2]+a[NR/2+1])/2)), a[1], a[NR], over+0, NR, lim}')"
}
corpus_info "skills/*/SKILL.md (shipped)" skills/*/SKILL.md
corpus_info ".claude/skills/*/SKILL.md (internal meta-skills)" .claude/skills/*/SKILL.md

# 5. Anti-rationalization tables over the 15-row guideline.
for f in skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  rows=$(sed -n '/^## [Aa]nti-[Rr]ationalization/,/^## /p' "$f" | grep -cE '^\|' || true)
  if [ "$rows" -gt 2 ]; then
    rows=$((rows - 2))  # subtract header + separator rows
    if [ "$rows" -gt 15 ]; then report_warn "$(rel "$f"): anti-rationalization table has $rows rows (guideline ≤15)"; fi
  fi
done

# 6. Decaying line-number cross-references (file.md:NNN) — section/content anchors survive edits; line numbers do not.
# -o extracts just the `file.md:NNN` match (with a grep file:line locator prefix);
# advisory only, so a rare URL-with-port (foo.md:8080) miscount is acceptable.
linerefs=$(grep -rnoE '[A-Za-z0-9_-]+\.md:[0-9]+' skills 2>/dev/null || true)
if [ -n "$linerefs" ]; then
  count=$(printf '%s\n' "$linerefs" | grep -c . || true)
  report_warn "found $count line-number cross-reference(s) (file.md:NNN) in skills/ — prefer content anchors"
fi

# 7. The same normative sentence in 3+ files — the mechanical form of "say it
#    once, in the right place". Redundancy across layers costs context budget
#    twice and, when the copies drift apart, forces the model to deliberate over
#    which one governs instead of acting. A cross-reference to the canonical file
#    is the fix; a second copy is the defect.
#    Advisory and deliberately blunt: it cannot tell a deliberate restatement at
#    a load-bearing seam from an accidental copy-paste, so it reports and the
#    maintainer judges. One WARN carries the whole cluster set (a WARN per
#    cluster would drown the per-file warnings above), with the top offenders
#    listed by how many files carry them.
dup_files="$(mktemp)"
dup_hits="$(mktemp)"
trap 'rm -f "$dup_files" "$dup_hits"' EXIT
find skills agents .claude/skills -type f -name '*.md' 2>/dev/null | LC_ALL=C sort > "$dup_files"

# awk reads the file LIST as its input and getline-s each path, so no shell
# word-splitting of a 100+ entry argv and no mapfile/readarray (bash 3.2).
# Sentence split is on ". " / "! " / "? " only — never a bare "." — so file.md
# and v1.2 stay intact. Table cell walls become sentence breaks because in this
# corpus a rule is as often a table cell as a paragraph. Fenced code is skipped.
LC_ALL=C awk '
  function norm(s,   t) {
    gsub(/`/, "", s); gsub(/\*\*/, "", s)
    t = tolower(s)
    gsub(/[ \t]+/, " ", t); sub(/^ +/, "", t); sub(/ +$/, "", t)
    return t
  }
  # Normative force, not boilerplate: punctuation is flattened to spaces first so
  # the keyword test is whole-word (else "per" matches inside "paper") and so both
  # the straight and curly apostrophe in do-not contractions land on " don t ".
  function normative(t,   p) {
    p = " " t " "
    gsub(/[^a-z0-9]/, " ", p)
    gsub(/  +/, " ", p)
    return (p ~ / (never|always|must|only|via|per) / || p ~ / do not / || p ~ / don t /)
  }
  {
    path = $0; fence = 0
    while ((getline line < path) > 0) {
      if (line ~ /^[ \t]*```/) { fence = 1 - fence; continue }
      if (fence) continue
      sub(/^[ \t]*#+[ \t]*/, "", line)          # heading marker
      sub(/^[ \t]*>[ \t]*/, "", line)           # block quote
      sub(/^[ \t]*[-*+][ \t]+/, "", line)       # bullet
      sub(/^[ \t]*[0-9]+\.[ \t]+/, "", line)    # ordered list
      gsub(/\|/, ". ", line)                    # table cell wall -> sentence break
      s = line " "
      gsub(/[.!?] +/, "@@S@@", s)
      n = split(s, part, "@@S@@")
      for (i = 1; i <= n; i++) {
        t = norm(part[i])
        if (length(t) < 40) continue            # too short to be a real rule
        if (!normative(t)) continue
        if ((t SUBSEP path) in seen) continue   # count FILES, not occurrences
        seen[t SUBSEP path] = 1
        cnt[t]++
        flist[t] = (t in flist) ? flist[t] ", " path : path
      }
    }
    close(path)
  }
  END { for (k in cnt) if (cnt[k] >= 3) printf "%d\t%s\t%s\n", cnt[k], k, flist[k] }
' "$dup_files" > "$dup_hits"

dup_total=$(awk 'END {print NR + 0}' "$dup_hits")
if [ "$dup_total" -gt 0 ]; then
  report_warn "$dup_total normative sentence(s) repeated across 3+ files — say it once in the canonical file and cross-reference it. Top 10 by file count:"
  LC_ALL=C sort -rn "$dup_hits" | head -10 | awk -F'\t' '
    {
      txt = $2
      if (length(txt) > 100) { txt = substr(txt, 1, 100); sub(/[^ ]*$/, "", txt); txt = txt "..." }
      n = split($3, fs, ", "); l = ""
      for (i = 1; i <= n && i <= 4; i++) l = l (i > 1 ? ", " : "") fs[i]
      if (n > 4) l = l ", +" (n - 4) " more"
      printf "        %dx  \"%s\"\n             %s\n", $1, txt, l
    }'
else
  echo "OK: no normative sentence repeated across 3+ files"
fi

echo
echo "==================================================="
echo "Hard failures: $HARD_FAILS"
echo "Warnings:      $WARNS"
[ "$HARD_FAILS" -eq 0 ]
