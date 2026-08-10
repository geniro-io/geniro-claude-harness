#!/usr/bin/env bash
# Guards canonical-home declarations — the repo's single-source contract.
#
# Run: bash tests/authoring/lint-canonical-homes.sh
#
# Why this exists: 100+ sites declare "X is canonical in FILE §SECTION". That
# declaration is what keeps a fact from growing a second home — it is the only
# reason a reader knows which of two copies to trust, and the only reason an
# audit can call a restatement a defect rather than a style opinion. Nothing
# checked it. A heading recase or a section move in the owner silently dangles
# every citation into it, and the citation still READS correct, so review does
# not catch it either. One audit round dangled this class four times in a single
# fix pass; the same round shipped two citations of a `§Constraints` heading
# that had not existed for weeks.
#
# Why HARD rather than a count ratchet: lint-skills.sh check 10 counts
# unresolved section anchors because a BARE `§` has no mechanically recoverable
# binding — it may name a section in the citing file, in a file named a
# paragraph earlier, or in none. A canonical declaration is the decidable case:
# the owning path sits inside the same sentence, so the binding is explicit and
# a failure names its site instead of moving a number.
#
# Coverage:
#   1. Every declared owner path resolves to a real file.
#   2. Every declared §section resolves to a real heading in that file.
#   3. Both run over ALL tracked markdown — .claude/skills/ and the root docs
#      included, which checks 2 and 5 of lint-skills.sh deliberately skip.
#
# One exclusion: `evals/loop/modules/` is eval data, not repo prose. Its champion
# directories are machine-generated snapshots of files this check already reads
# at their real home, where their relative citations resolve and in the copy
# cannot; its benchmark trees are synthetic repos whose dangling references are
# the planted ground truth. Both would fail here for being exactly what they are
# meant to be.
#
# Scope discipline: only a backticked token carrying a file extension is treated
# as a path. `owned by \`/geniro:instructions validate\`` names a skill command
# and `lives in \`_shared/\`` names a directory — neither is a claim this check
# can decide, so both are skipped rather than guessed at.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# The declaration vocabulary. Each of these introduces an OWNER — the file a
# fact lives in — as opposed to a consumer note ("referenced from", "read by"),
# which names a reader and carries no single-source claim.
KEYWORDS='canonical in|canonical home is|single-sourced in|single-sourced into|owned by|authoritative in|the single home for'

# Only real headings resolve an anchor. A heading-shaped line inside a fenced
# code block is not one, and accepting it is the error this check cannot
# survive: a false negative books a renamed-away heading as still present, which
# is exactly the breakage the check exists to catch. This corpus carries ~520
# heading-shaped lines inside fences.
_real_headings() {
  awk '
    /^[ \t]*```/ { fence = 1 - fence; next }
    fence        { next }
    /^# |^## |^### |^#### |^##### / { print }
  ' "$1" 2>/dev/null
}

# Resolve an owner token to a path. Three roots, in the order a reader would try
# them: the plugin root (after stripping either spelling of it), the citing
# file's own directory (the sibling-basename shape), and skills/_shared/ (the
# helper shape that other helpers cite by bare basename).
_resolve_owner() {
  local tok="$1" citer="$2" p
  p="${tok#\$\{CLAUDE_PLUGIN_ROOT\}/}"
  p="${p#\$PLUGIN_PATH/}"
  [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  [ -f "$(dirname "$citer")/$p" ] && { printf '%s' "$(dirname "$citer")/$p"; return 0; }
  [ -f "skills/_shared/$p" ] && { printf '%s' "skills/_shared/$p"; return 0; }
  return 1
}

# Reduce an anchor to the key matched against headings: first two words, with
# sentence punctuation stripped BOTH before and after the truncation. Prose
# continues past an anchor with no delimiter ("§Output Format. The block …"), so
# a period lands mid-string where a trailing strip cannot reach it, and the key
# "Output Format." then matches no heading. That artifact alone accounted for
# roughly half of the unresolved count the sibling check first measured.
_anchor_key() {
  printf '%s' "$1" \
    | awk '{ printf "%s", $1; if (NF > 1) printf " %s", $2 }' \
    | sed 's|[.,:;)]*$||'
}

checked=0
while IFS= read -r file; do
  [ -f "$file" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    lineno="${hit%%:*}"
    rest="${hit#*:}"

    # Parse by parameter expansion rather than a greedy sed: an anchor may
    # itself be backticked (§`atomic_state_append <target>`), and a greedy
    # match would then return the ANCHOR as the owner path.
    case "$rest" in *'`'*) ;; *) continue ;; esac
    after="${rest#*\`}"
    token="${after%%\`*}"
    tail="${after#*\`}"

    case "$token" in
      *.md|*.sh|*.js|*.json) ;;
      *) continue ;;   # a command or a directory — not decidable here
    esac

    checked=$((checked + 1))

    if ! target="$(_resolve_owner "$token" "$file")"; then
      report_fail "$file:$lineno declares a canonical home that does not exist: $token"
      continue
    fi

    # An anchor is present only when § follows the owner's closing backtick.
    case "$tail" in
      *§*) ;;
      *) continue ;;
    esac
    anchor="${tail#*§}"
    anchor="$(printf '%s' "$anchor" \
      | sed 's|^[[:space:]]*||; s|^`||; s|`.*||; s|^"||; s|".*||; s|[[:space:]]*$||; s|[.,:;)]*$||')"
    [ -n "$anchor" ] || continue

    headings="$(_real_headings "$target")"
    case "$anchor" in
      [0-9]*)
        # A numeric anchor (§4, §3.4) names a numbered heading in the owner.
        num="$(printf '%s' "$anchor" | sed 's|[^0-9.].*||; s|\.$||')"
        printf '%s\n' "$headings" | grep -qE "^#{2,5} ${num}[.):[:space:]]" && continue
        report_fail "$file:$lineno cites $target §$num — no heading numbered $num in that file"
        ;;
      *)
        key="$(_anchor_key "$anchor")"
        [ -n "$key" ] || continue
        # `--`: an anchor beginning with a dash would otherwise reach grep as an
        # option, exit 2, and book a verbatim-matching citation as dangling.
        printf '%s\n' "$headings" | grep -qiF -- "$key" && continue
        # Report the KEY, not the raw anchor: prose runs past an anchor with no
        # delimiter, so the raw capture is bounded by a byte count that can cut a
        # multi-byte character in half and print mojibake into the failure.
        report_fail "$file:$lineno cites $target §$key — no heading matching that in the cited file"
        ;;
    esac
  done < <(grep -noiE "($KEYWORDS)[[:space:]]+\`[^\`]+\`([[:space:]]*§[^|]{0,90})?" "$file" 2>/dev/null || true)
done < <(git ls-files '*.md' 2>/dev/null | grep -v '^evals/loop/modules/')

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS of $checked canonical-home declarations do not resolve." >&2
  echo "A declaration naming a home that moved is worse than none: readers trust it and stop looking." >&2
  exit 1
fi
echo "OK: all $checked canonical-home declarations resolve (file and section)."
