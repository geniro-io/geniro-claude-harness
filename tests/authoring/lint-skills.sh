#!/usr/bin/env bash
# Authoring lint — mechanizes the manual greps in .claude/rules/skill-structure.md
# §Pre-commit verification and .claude/rules/skill-authoring.md §Hard exclusions.
#
# Run:    bash tests/authoring/lint-skills.sh
# Accept: bash tests/authoring/lint-skills.sh --accept <path>...   (one file's size)
#         bash tests/authoring/lint-skills.sh --accept-anchors     (the anchor figure)
#         bash tests/authoring/lint-skills.sh --update-baseline    (everything)
#
# Two severities:
#   HARD (exit non-zero) — zero-false-positive correctness checks:
#     1. Non-Latin (Cyrillic) letters in skills/ or agents/ bodies.
#     2. Dangling plugin-root file references — ${CLAUDE_PLUGIN_ROOT}/<path> and the
#        $PLUGIN_PATH/<path> form (target must exist).
#     3. Unknown subagent_type spawn names (must resolve to a real agent/builtin).
#     4. Reference-graph inversion — a skills/<other-skill>/ path inside skills/_shared/.
#     5. Rootless agents/ or skills/ file references in skills/ or agents/.
#   ADVISORY (warn only, exit 0 contribution) — guideline checks the maintainer
#   reads but never auto-trims to satisfy (size targets are guidelines, not limits):
#     6. SKILL.md word count vs the front-load budget and whole-file guideline,
#        across BOTH skill populations (shipped skills/ and internal .claude/skills/),
#        plus agents/*.md against their own whole-file guideline.
#     7. Anti-rationalization tables over the 15-row guideline.
#     8. Decaying line-number cross-references (file.md:NNN).
#     9. Normative sentences repeated across 3+ files (say it once, in one place).
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

SIZE_BASELINE="tests/authoring/skill-size-baseline.txt"
ANCHOR_BASELINE="tests/authoring/anchor-baseline.txt"

# Emit `<cited-path><TAB><anchor>` for every PATH-ADJACENT section citation whose
# anchor resolves to no heading in the cited file. Used by check 10.
#
# Scoped to path-adjacent citations on purpose. A `§` sitting next to a file path
# names a section in THAT file, which is decidable. A bare `§` — the larger half
# of the anchors in this repo — may name a section in the citing file, in a file
# named a paragraph earlier, or in none; `skills/setup/SKILL.md` cites one file and
# then writes an anchor that resolves only in itself. That binding is not
# mechanically recoverable, so bare anchors are out of scope here and belong to
# /audit-plugin's read-based dimensions.
#
# The anchor's right boundary is also undecidable — prose continues past it with
# no delimiter — so this function matches on the anchor's first two words against
# heading lines only. That yields a count with some noise in it, which is exactly
# why check 10 is a RATCHET on the count rather than a report of sites: a constant
# offset does not matter when only a CHANGE is actionable.
#
# Only REAL headings resolve an anchor. A heading-shaped line inside a fenced code
# block is not one, and accepting it is the one error a ratchet cannot survive: a
# false negative books a deleted heading as still present, so the count does not move
# and the breakage the check exists to catch passes silently. This corpus carries 520
# heading-shaped lines inside fences against 2,048 real headings — a fifth of the
# population — and `# Cleanup contract: rm -rf …` in a bash block is exactly the shape
# that resolves a citation whose heading was renamed away. Check 9 below tracks fence
# state with the same toggle for the same reason.
_real_headings() {
  awk '
    /^[ \t]*```/ { fence = 1 - fence; next }
    fence        { next }
    /^# |^## |^### |^#### / { print }
  ' "$1" 2>/dev/null
}

anchor_unresolved() {
  # No -h: each hit carries the file that cites it, because a citation written as a
  # bare basename (`review-handoff.md §…`, the sibling shape) resolves against the
  # citing file's own directory, not the repo root. 121 of 666 hits are that shape,
  # and testing them only against the root skipped every one of them.
  grep -roE '[A-Za-z0-9_${}/.-]+\.md`?[^§]{0,3}§[^`",;)]{1,48}' \
    skills agents .claude/skills 2>/dev/null \
    | sed 's|\${CLAUDE_PLUGIN_ROOT}/||' \
    | while IFS= read -r _line; do
        _citer=${_line%%:*}
        _hit=${_line#*:}
        _p=$(printf '%s\n' "$_hit" | sed 's|\.md.*|\.md|')
        if [ ! -f "$_p" ]; then
          if [ -f "$(dirname "$_citer")/$_p" ]; then
            _p="$(dirname "$_citer")/$_p"
          elif [ -f "skills/_shared/$_p" ]; then
            _p="skills/_shared/$_p"
          else
            continue
          fi
        fi
        # Strip the quotes some citations wrap the anchor in, then the sentence
        # punctuation that follows it. Without the trailing-punctuation strip a
        # citation reading "§Codebase research." never matches "### Codebase
        # research", and the residue fills with hits that are only punctuation
        # deep — noise that would blunt the ratchet it is measured against.
        _a=$(printf '%s\n' "$_hit" \
          | sed 's|.*§||; s|^"||; s|".*||; s|^[[:space:]]*||; s|[[:space:]]*$||; s|[.,:;]*$||')
        [ -n "$_a" ] || continue
        _h=$(_real_headings "$_p")
        case "$_a" in
          [0-9]*)
            _n=$(printf '%s' "$_a" | sed 's|[^0-9.].*||; s|\.$||')
            printf '%s\n' "$_h" | grep -qE "^#{2,4} ${_n}[.):[:space:]]" && continue
            ;;
          *)
            # Punctuation is stripped AFTER the truncation as well as before it. A
            # period lands mid-string whenever prose continues past the anchor
            # ("§Output Format. The block …"), where the trailing strip above cannot
            # reach it — it survives into the two-word key and "Output Format." then
            # matches no heading. That artifact alone accounted for roughly half the
            # unresolved count, which is the difference between a ratchet guarding
            # real breakage and one padded with its own noise.
            _s=$(printf '%s' "$_a" \
              | awk '{ printf "%s", $1; if (NF > 1) printf " %s", $2 }' \
              | sed 's|[.,:;]*$||')
            [ -n "$_s" ] || continue
            # `--`: an anchor beginning with a dash (a future `§--deep mode`) otherwise
            # reaches grep as an option, exits 2, and books a verbatim-matching
            # citation as dangling — a warning blaming a rename that never happened.
            printf '%s\n' "$_h" | grep -qiF -- "$_s" && continue
            ;;
        esac
        printf '%s\t%s\n' "$_p" "$_a"
      done
}

# The script's single word-count rule. `wc -w` cannot be it, despite being the
# obvious choice: GNU wc decides whether a run of non-blank bytes counts as a word
# using the locale's character classification, so a standalone `—`, `§`, `·`, or `→`
# — which this repo's prose uses constantly as separators — is a word under
# C.UTF-8 and nothing at all under C. The same unchanged file then measures ~3%
# larger for a contributor who exports a UTF-8 locale than for one who does not,
# which silently breaks the ratchet in both directions: a recorded baseline reads as
# phantom growth on one machine, and real growth hides under a too-high baseline on
# the other (measured: audit-plugin/SKILL.md grew past its baseline unreported).
# awk splits fields on ASCII blanks only, so its count is the same everywhere, and
# it is already what frontload_cut uses to locate the compaction boundary — before
# this, the boundary heading was computed on a different scale than the budget it
# was compared against.
words_in() { awk '{ w += NF } END { print w + 0 }' "$1"; }

baseline_words() {  # <relpath> -> its accepted word count, or empty if unrecorded
  [ -f "$SIZE_BASELINE" ] || return 0
  # The count must be numeric: the baseline is a hand-editable tracked file, and a
  # malformed row would otherwise reach `[ -le ]` and leak a raw shell diagnostic
  # into the lint output. A bad row degrades to "unrecorded", which warns.
  awk -v p="$1" '$1 == p && $2 ~ /^[0-9]+$/ { print $2; exit }' "$SIZE_BASELINE"
}

# The baseline writers. All of them record and exit before any check runs, so a
# recorded number can never be one a check just failed on. They live in this script
# rather than a sibling so a recorded number can never be produced by a different
# word-count rule than the one that reads it back — which is why every count goes
# through words_in, never a bare wc.
#
# Three of them, because "accept this size" and "accept every size" are different
# decisions and only one of them is usually meant. --update-baseline rewrites all 27
# rows and the anchor figure together, so a refresh performed to accept ONE file's
# growth silently accepts every other file that grew since, plus any new dangling
# anchor — unreviewed, and invisible in a diff that was expected to move one line.
# That is not hypothetical: 14 of this repo's first 30 baseline transitions moved
# 10-25 rows at once, riding inside commits about unrelated work. So the targeted
# forms are the default gesture and the blanket one is for a genuine repo-wide pass.
#
#   --accept <path>...   record just these files' sizes
#   --accept-anchors     record just the anchor figure
#   --update-baseline    record everything (a repo-wide compression round)

# Rewrite one row of the size baseline in place, preserving every other row and the
# file's LC_ALL=C sort order. Writes through a temp file and renames: a run
# interrupted mid-write leaves the old baseline intact rather than a truncated one,
# and a truncated baseline reads as "every file unrecorded", which warns on all 27.
accept_one() {
  local f r n tmp
  f="$1"
  r="$(rel "$f")"
  if [ ! -f "$f" ]; then
    echo "$(basename "$0"): no such file: $f" >&2
    return 1
  fi
  # Only the measured population has rows. Accepting anything else writes a row no
  # check ever reads, which looks like an accepted size and is not one.
  case "$r" in
    skills/*/SKILL.md|.claude/skills/*/SKILL.md|agents/*.md) ;;
    *)
      echo "$(basename "$0"): $r is not size-checked (skills/*/SKILL.md, .claude/skills/*/SKILL.md, agents/*.md)" >&2
      return 1
      ;;
  esac
  n="$(words_in "$f")"
  local was
  was="$(baseline_words "$r")"
  tmp="$(mktemp)" || return 1
  { [ -f "$SIZE_BASELINE" ] && awk -v p="$r" '$1 != p' "$SIZE_BASELINE"
    printf '%s %s\n' "$r" "$n"
  } | LC_ALL=C sort > "$tmp" && mv "$tmp" "$SIZE_BASELINE" || { rm -f "$tmp"; return 1; }
  if [ -n "$was" ]; then
    echo "Accepted $r at $n words (was $was)."
  else
    echo "Accepted $r at $n words (previously unrecorded)."
  fi
}

case "${1:-}" in
  --accept)
    shift
    [ $# -gt 0 ] || { echo "$(basename "$0"): --accept needs at least one path" >&2; exit 64; }
    rc=0
    for f in "$@"; do accept_one "$f" || rc=1; done
    exit "$rc"
    ;;
  --accept-anchors)
    anchor_unresolved | grep -c . > "$ANCHOR_BASELINE"
    echo "Recorded $(cat "$ANCHOR_BASELINE") unresolved path-adjacent section anchors in $ANCHOR_BASELINE"
    exit 0
    ;;
  --update-baseline)
    for f in skills/*/SKILL.md .claude/skills/*/SKILL.md agents/*.md; do
      [ -f "$f" ] && printf '%s %s\n' "$(rel "$f")" "$(words_in "$f")"
    done | LC_ALL=C sort > "$SIZE_BASELINE"
    echo "Recorded $(grep -c . "$SIZE_BASELINE") skill and agent sizes in $SIZE_BASELINE"
    anchor_unresolved | grep -c . > "$ANCHOR_BASELINE"
    echo "Recorded $(cat "$ANCHOR_BASELINE") unresolved path-adjacent section anchors in $ANCHOR_BASELINE"
    exit 0
    ;;
esac

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

# 3b. Prefixed spawn form stated without its non-Claude-Code counterpart.
# `geniro:` is the namespace Claude Code prefixes onto a marketplace-installed
# plugin's agents. No other host has a plugin namespace, so under Cursor (and
# every other runtime) the prefixed form resolves nowhere — and because
# spawn-agent.md §Parallel-spawn sites degrades a batch as a unit, a fan-out
# that opens at the prefixed rung there burns one dead spawn PER AGENT plus a
# whole turn before any real work starts (observed: an 11-reviewer
# /geniro-review fan-out). spawn-agent.md now enters the ladder at the bare
# rung off-Claude-Code, but that file is a deferred read the happy path never
# opens: what a run actually obeys is the spawn form written at the call site.
# So every call site naming the prefixed form must name the bare one beside it.
# spawn-agent.md itself is exempt — it is where the distinction is defined.
missing_bare=0
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  report_fail "prefixed-only spawn form (no bare-name counterpart for non-Claude-Code hosts): ${hit%%:*} — ${hit#*:}"
  missing_bare=$((missing_bare + 1))
done <<< "$(grep -rnE 'subagent_type[=:][[:space:]]*"?geniro:' skills agents 2>/dev/null \
  | grep -v '^skills/_shared/spawn-agent\.md:' \
  | grep -vE 'bare `?subagent_type|bare name|Claude Code only|bare `<agent>`|→ bare' \
  | cut -d: -f1,2)"
[ "$missing_bare" -eq 0 ] && echo "OK: every prefixed spawn form names its bare non-Claude-Code counterpart"

# 4. Reference-graph inversion — skill-structure.md §Reference graph: skills cite
# DOWNWARD into skills/_shared/, never the reverse. A helper that names a skill
# body as the canonical home of a rule it consumes inverts the graph: the helper
# is loaded by skills that have no reason to read that skill, and the rule then
# lives in a file its own consumers do not open. This class recurred across three
# consecutive audits because nothing mechanized it.
# `_shared/` peers citing each other is the intended shape and must not fire.
#
# What is flagged is the AUTHORITY shape only — a helper introducing a skill path
# as the source of a rule ("per <path>", "see <path>", "defined in <path>").
# §Reference graph forbids pulling runtime instructions upward while explicitly
# allowing topological context, so the naming-a-consumer shape ("Consumer:
# <path>", "Referenced from <path>", "the Phase 3 filter in <path> dedups") is
# correct and must stay silent: 20 of the 21 hits a bare path-shape match
# produced on this corpus were that shape, and a check that cries wolf 20 times
# is one maintainers learn to route around rather than obey.
# A rule sourced upward without an introducing preposition is not mechanically
# distinguishable from a consumer note; /audit-plugin's D4 dimension covers that
# residue by reading, which is the right tool for a semantic distinction.
inversions=0
inv_hits=$(grep -rnoiE '(per|see|defined in|specified in|documented in|canonical in|authoritative in|owned by)[[:space:]]+`?(\$\{CLAUDE_PLUGIN_ROOT\}/)?skills/[A-Za-z0-9_-]+/' skills/_shared 2>/dev/null \
  | awk -F: '{ m = $0; sub(/^[^:]*:[^:]*:/, "", m); if (m !~ /skills\/_shared\//) print $1 ":" $2 ": " m }' \
  | while IFS=: read -r f l rest; do
      # A "see <path>" INSIDE a consumer annotation points at where the consumer
      # applies the rule, not at where the rule is defined — the helper still owns
      # it. Judge the whole line, not the preposition.
      sed -n "${l}p" "$f" 2>/dev/null | grep -qiE '^[[:space:]]*[-*]?[[:space:]]*(consumers?:|referenced from)' && continue
      printf '%s:%s:%s\n' "$f" "$l" "$rest"
    done || true)
while IFS= read -r h; do
  [ -z "$h" ] && continue
  report_fail "reference-graph inversion: $h — a skills/_shared/ helper cites a skill body as the SOURCE of a rule it consumes; re-home the rule into _shared/ and have the skill cite downward"
  inversions=$((inversions + 1))
done <<< "$inv_hits"
[ "$inversions" -eq 0 ] && echo "OK: no skills/_shared/ helper sources a rule from a skill body"

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

echo
echo "=== ADVISORY checks (warn only) ==="

# 6. SKILL.md size, measured in WORDS per skill-structure.md §File-size limits.
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
#    Reported as a RATCHET against `tests/authoring/skill-size-baseline.txt`, not
#    as an absolute bar. The rule this check mechanizes says an oversize file is
#    "a signal to check what is load-bearing and where it sits, not a defect in
#    itself" — so re-reporting the same accepted size every run is noise, and a
#    warning that can never go green stops being read at all. The baseline IS the
#    record that a size was checked and accepted; the warning fires when a file
#    grows past it, or when a file with no recorded baseline exceeds the
#    guideline. Accept a growth with `--accept <path>` after deciding it is
#    load-bearing — never by trimming content to make the number go away, and
#    never with the blanket `--update-baseline` unless every row is meant.
FRONTLOAD_WORDS=3000
WHOLEFILE_WORDS=5000
# Agents get their own, tighter whole-file guideline and NO front-load budget:
# an agent body is injected whole as a subagent system prompt, not Read, so there
# is no compaction boundary to fall past — the entire file is either in the
# prompt or the spawn never happened. What the number bounds is per-spawn prompt
# cost, and a reviewer body is re-injected 7-11 times in one /review run.
AGENT_WHOLEFILE_WORDS=2500


# Name the last H2 that still fits inside the front-load budget, so the warning says
# WHICH sections stop being re-attached rather than just that the file is big.
frontload_cut() {
  awk -v lim="$FRONTLOAD_WORDS" '
    /^## / { last = $0 }
    { w += NF; if (w > lim && !done) { print last; done = 1 } }
  ' "$1"
}

check_skill_sizes() {
  local f n r base cut
  for f in "$@"; do
    [ -f "$f" ] || continue
    r=$(rel "$f")
    n=$(words_in "$f")
    base=$(baseline_words "$r")
    if [ -n "$base" ]; then
      # Recorded: a maintainer already judged this size, so only growth past it is news.
      if [ "$n" -gt "$base" ]; then
        report_warn "$r: grew to $n words (accepted baseline $base) — re-check what is load-bearing and where it sits, then '--accept $r'; do not trim to the number"
      fi
    elif [ "$n" -gt "$WHOLEFILE_WORDS" ]; then
      report_warn "$r: $n words (whole-file guideline <=$WHOLEFILE_WORDS) with no accepted baseline — decide what is load-bearing, then '--accept $r'"
    fi
    # The compaction-boundary notice is UNCONDITIONAL on baseline/growth status, on
    # purpose: an accepted SIZE and where its compaction BOUNDARY falls are different
    # signals. The ratchet above exists so an accepted size is not re-reported every
    # run; the boundary notice has no such reason to go silent for a file sitting AT
    # its baseline — it still drops every section past ~$FRONTLOAD_WORDS words once
    # the session compacts, and "re-check what is load-bearing" needs to say where
    # that line falls whether or not the size itself is news this run. Gating this on
    # `[ -n "$base" ] && [ "$n" -le "$base" ]` used to `continue` before this block ever
    # ran, so a file oversize-but-stable at its recorded baseline never learned its own
    # boundary (skills/implement/SKILL.md, skills/investigate/SKILL.md,
    # .claude/skills/improve-template/SKILL.md all sat in that blind spot).
    if [ "$n" -gt "$FRONTLOAD_WORDS" ]; then
      cut=$(frontload_cut "$f")
      [ -n "$cut" ] && report_warn "$r: compaction boundary (~$FRONTLOAD_WORDS words) falls at \"$cut\" — sections after it are dropped once the session compacts"
    fi
  done
}

check_skill_sizes skills/*/SKILL.md .claude/skills/*/SKILL.md

# Same ratchet, agent guideline, no compaction-boundary line — see AGENT_WHOLEFILE_WORDS.
check_agent_sizes() {
  local f n r base
  for f in "$@"; do
    [ -f "$f" ] || continue
    r=$(rel "$f")
    n=$(words_in "$f")
    base=$(baseline_words "$r")
    if [ -n "$base" ]; then
      [ "$n" -le "$base" ] && continue
      report_warn "$r: grew to $n words (accepted baseline $base) — an agent body is re-injected on every spawn; re-check what is load-bearing, then '--accept $r'"
    elif [ "$n" -gt "$AGENT_WHOLEFILE_WORDS" ]; then
      report_warn "$r: $n words (agent whole-file guideline <=$AGENT_WHOLEFILE_WORDS) with no accepted baseline — decide what is load-bearing, then '--accept $r'"
    fi
  done
}
check_agent_sizes agents/*.md

# Corpus shape, not per-file compliance: a median that creeps up is the signal to
# act on, and one oversize skill among lean ones is a different problem from all of
# them drifting together. INFO, not a warning — it never needs "fixing" on its own.
# Reported per population: the two have different sizes and different owners, so a
# single merged median would hide a drift in either one.
corpus_info() {
  local label="$1" lim="$2" limname="$3"; shift 3
  local f words
  words=$(for f in "$@"; do [ -f "$f" ] && words_in "$f"; done)
  [ -n "$words" ] || return 0
  echo "INFO: $label word counts — $(printf '%s\n' "$words" | sort -n | awk -v lim="$lim" -v limname="$limname" '
    {a[NR]=$1; if ($1 > lim) over++}
    END {printf "median %d, range %d-%d, %d of %d over the ~%d-word %s",
         (NR%2 ? a[(NR+1)/2] : int((a[NR/2]+a[NR/2+1])/2)), a[1], a[NR], over+0, NR, lim, limname}')"
}
corpus_info "skills/*/SKILL.md (shipped)" "$FRONTLOAD_WORDS" "front-load budget" skills/*/SKILL.md
corpus_info ".claude/skills/*/SKILL.md (internal meta-skills)" "$FRONTLOAD_WORDS" "front-load budget" .claude/skills/*/SKILL.md
corpus_info "agents/*.md (spawn system prompts)" "$AGENT_WHOLEFILE_WORDS" "whole-file guideline" agents/*.md

# 7. Anti-rationalization tables over the 15-row guideline.
for f in skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  rows=$(sed -n '/^## [Aa]nti-[Rr]ationalization/,/^## /p' "$f" | grep -cE '^\|' || true)
  if [ "$rows" -gt 2 ]; then
    rows=$((rows - 2))  # subtract header + separator rows
    if [ "$rows" -gt 15 ]; then report_warn "$(rel "$f"): anti-rationalization table has $rows rows (guideline ≤15)"; fi
  fi
done

# 8. Decaying line-number cross-references (file.md:NNN) — section/content anchors survive edits; line numbers do not.
# -o extracts just the `file.md:NNN` match (with a grep file:line locator prefix);
# advisory only, so a rare URL-with-port (foo.md:8080) miscount is acceptable.
linerefs=$(grep -rnoE '[A-Za-z0-9_-]+\.md:[0-9]+' skills 2>/dev/null || true)
if [ -n "$linerefs" ]; then
  count=$(printf '%s\n' "$linerefs" | grep -c . || true)
  report_warn "found $count line-number cross-reference(s) (file.md:NNN) in skills/ — prefer content anchors"
fi

# 9. The same normative sentence in 3+ files — the mechanical form of "say it
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
    # agents/*.md are injected whole as a subagent system prompt. skill-structure.md
    # §File-size limits: relocating a rule there to a cited file "converts free prompt
    # tokens into the same tokens plus a Read the agent may skip — and a rule it skips
    # is silently gone". So a rule shared by N agents MUST be restated in each of them;
    # counting those restatements as duplication argues for the unsafe fix.
    if (path ~ /^agents\//) next
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
        # A sentence that is ONLY a pointer at the canonical file is the prescribed fix,
        # not the defect. But "cite the helper AND restate its parameters" is the
        # commonest duplication shape in this corpus, and skipping on the mere presence
        # of a citation would hide exactly that. So strip the citation and judge what is
        # left: a bare pointer collapses below the length/normative bar and drops out,
        # while a restated rule survives and is counted. Clustering keys on the stripped
        # form too, so two copies that cite the same helper with different wording around
        # it still land in one cluster.
        # The §anchor is a multi-word title, so strip to the first punctuation rather
        # than the first space — otherwise the tail of the anchor name survives and
        # reads as rule text. Anything AFTER that punctuation is real content: a
        # trailing "(3 latest per …, flip the oldest … via …)" is a restatement and
        # must stay visible to the count.
        # Take the introducing preposition with the citation ("per <path>", "see <path>"):
        # left behind, that bare "per" reads as normative force and every pointer would
        # score as a rule. A "via" that belongs to the rule text is not adjacent to a
        # path, so it survives.
        bare = t
        gsub(/(per|see|via|from|at|in) +\$\{claude_plugin_root\}[^ ]*/, " ", bare)
        gsub(/\$\{claude_plugin_root\}[^ ]*/, " ", bare)
        gsub(/\302\247[^,.;(]*/, " ", bare)
        gsub(/  +/, " ", bare); sub(/^ +/, "", bare); sub(/ +$/, "", bare)
        if (length(bare) < 40 || !normative(bare)) continue
        t = bare
        # A trailing colon marks a label introducing a list ("Quality gates (escalate
        # to user, do not abort):"), not a rule stated in that file.
        if (t ~ /:$/) continue
        # Self-referential sentences ("Skills cite this file; do NOT inline-paste the
        # procedure") resolve to a different subject in every file that carries them,
        # so counting them across files is a category error — 14 _shared helpers each
        # declaring their own load contract is the convention, not one rule copied 14
        # times. A genuinely duplicated rule does not say "this file".
        if (index(t, "this file")) continue
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

# 10. Section-anchor citations that resolve to no heading — ratchet, not a report.
#     Step 12-class breakage: a commit deletes or renames a heading and every `§`
#     citation aimed at it dangles silently. No existing check sees it — the
#     plugin-root check above proves the FILE exists, never that the section does.
#
#     ADVISORY by construction, and it must stay that way. HARD is defined at the
#     top of this file as zero-false-positive, and this check cannot clear that
#     bar: the anchor's right boundary is undecidable, so its count carries noise
#     it has no way to remove.
#
#     The ratchet is what makes a noisy count useful. A recorded figure turns the
#     residue into a constant and reports only movement, so the check says "you
#     broke one" rather than re-reading the same standing list every run — the
#     cries-wolf failure noted further up, which maintainers learn to route
#     around. Accept a new figure with --accept-anchors, the same deliberate
#     gesture the size ratchet uses — and one that leaves the size rows alone,
#     so accepting a rename never quietly accepts every file that grew with it.
anchor_out="$(mktemp)"
anchor_unresolved > "$anchor_out" 2>/dev/null || true
anchor_now=$(grep -c . "$anchor_out" || true)
anchor_was=""
[ -f "$ANCHOR_BASELINE" ] && anchor_was=$(awk 'NR == 1 && $1 ~ /^[0-9]+$/ { print $1; exit }' "$ANCHOR_BASELINE")

if [ -z "$anchor_was" ]; then
  report_warn "no recorded section-anchor figure — $anchor_now path-adjacent anchor(s) resolve to no heading; run --accept-anchors to start the ratchet"
elif [ "$anchor_now" -gt "$anchor_was" ]; then
  report_warn "path-adjacent section anchors resolving to no heading rose to $anchor_now (recorded $anchor_was) — a heading was renamed or deleted and its citers now dangle"
  sort "$anchor_out" | uniq -c | sort -rn | head -5 | awk '{
    n = $1; f = $2; $1 = ""; $2 = ""; sub(/^  */, "")
    printf "        %dx  %s  §%s\n", n, f, $0
  }'
else
  echo "OK: no new dangling section anchors ($anchor_now vs recorded $anchor_was)"
fi
rm -f "$anchor_out"

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
echo "==================================================="
echo "Hard failures: $HARD_FAILS"
echo "Warnings:      $WARNS"
[ "$HARD_FAILS" -eq 0 ]
