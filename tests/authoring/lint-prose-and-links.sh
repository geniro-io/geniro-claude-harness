#!/usr/bin/env bash
# Guards markdown link targets and the prose conventions that are decidable.
#
# Run: bash tests/authoring/lint-prose-and-links.sh
#
# Why this exists: link rot and terminology drift are the two prose defects with
# an objective answer, and both were being found by reading instead of by CI —
# so every audit round rediscovered them, and the round's own fixes seeded the
# next round's dangling references.
#
# Coverage:
#   1. HARD — every markdown link to a local path resolves.
#   2. ADVISORY — Title-Case headings, against a named allowlist.
#
# What this deliberately does NOT check: terminology. A banned-spelling table
# was built and measured, and it produced only false positives: `dim` is this
# repo's settled vocabulary (`per-dim`, `cross-dim`, `intra-dim`, `dim-slug`
# across ~40 files), not drift from `dimension`. An audit round flagged it as
# drift and rewrote one file to the long form, which made that file the odd one
# out. A terminology check on a corpus whose vocabulary is already consistent
# cannot find drift — it can only manufacture it.
#
# Why heading case is advisory and allowlisted rather than hard: half this
# corpus's Title-Case headings ARE contract tokens — `## Comment Resolution Map`
# is a literal section name a spec is parsed for, `Always-WAIT` and
# `Big / Medium / Small` are strings tests grep for. A blind recase breaks the
# contract while every sentence still reads correct, which is a worse failure
# than the defect. So each accepted heading is named with its reason, and the
# check reports only what is neither fixed nor named.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
WARNS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }
report_warn() { WARNS=$((WARNS + 1)); echo "WARN: $1"; }

# --- 1. Local link targets resolve -------------------------------------------
#
# Path-shaped targets only. This corpus embeds regular expressions inside
# bracket-paren pairs (`(recharts|chart\.js|monaco)` in a review criterion), and
# those parse as links to anything that scans for `](...)`. A target carrying an
# alternation, a backslash escape, or a space is not a path and is not this
# check's business.
_is_pathish() {
  case "$1" in
    *'|'*|*'\'*|*' '*|*'*'*|*'$'*) return 1 ;;
    */*) return 0 ;;
    *.md|*.sh|*.js|*.json|*.txt|*.yml|*.yaml) return 0 ;;
    *) return 1 ;;
  esac
}

links_checked=0
while IFS= read -r file; do
  [ -f "$file" ] || continue
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    target="${raw%%#*}"          # drop the anchor; the file is what must exist
    [ -n "$target" ] || continue
    case "$target" in
      http://*|https://*|mailto:*|'<'*) continue ;;
    esac
    _is_pathish "$target" || continue
    links_checked=$((links_checked + 1))
    [ -e "$(dirname "$file")/$target" ] && continue
    [ -e "$target" ] && continue
    report_fail "$file links to $target — no such file"
  done < <(grep -oE '\]\([^)]+\)' "$file" 2>/dev/null | sed 's/^](//; s/)$//' || true)
done < <(git ls-files '*.md' 2>/dev/null)
[ "$FAILS" -eq 0 ] && echo "OK: all $links_checked local markdown links resolve"

# --- 2. Title-Case headings (advisory) ---------------------------------------
#
# Each accepted heading is named with the reason it stays. A heading that is a
# contract token — a literal string a spec is parsed for or a test greps for —
# is not a style defect, and recasing it breaks the contract silently.
TITLECASE_ALLOWED='
3. Spec `## Comment Resolution Map` (Phase 4)|literal spec section name, parsed by /geniro:resolve
3. Step 0 — Open-decision gate (per-finding, Always-WAIT)|Always-WAIT is a gate contract token
Phase 3 — Adjustment Routing (Big / Medium / Small)|Big/Medium/Small are routing contract tokens
Phase 1: Code Smell Detection|"Code Smell" is a term of art
Phase 3: Atomic Application & Verification (orchestrator-inline)|cited verbatim by the same file'"'"'s contents list
2.5. Pre-gate — Resolve Open Questions|"Pre-gate" is a named gate referenced across five files
'
_allowed_heading() {
  printf '%s\n' "$TITLECASE_ALLOWED" | sed '/^$/d' | cut -d'|' -f1 | grep -qxF "$1"
}
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  h="${hit#*|}"
  _allowed_heading "$h" && continue
  report_warn "${hit%%|*}: Title-Case heading \"$h\" — sentence case, or name it in TITLECASE_ALLOWED with its reason"
done < <(
  git ls-files '*.md' 2>/dev/null | while IFS= read -r f; do
    awk -v F="$f" '
      /^[ \t]*```/ { fence = 1 - fence; next }
      fence        { next }
      /^#{2,4} / {
        h = $0; sub(/^#+ /, "", h)
        n = split(h, w, " "); cap = 0; tot = 0
        for (i = 2; i <= n; i++) {
          if (w[i] ~ /^[A-Z][a-z]/) cap++
          if (w[i] ~ /^[A-Za-z]/)   tot++
        }
        if (tot >= 3 && cap >= tot - 1 && cap >= 3) printf "%s:%d|%s\n", F, FNR, h
      }' "$f"
  done
)

echo
[ "$WARNS" -gt 0 ] && echo "$WARNS advisory warning(s)."
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS broken local link(s)." >&2
  exit 1
fi
echo "OK: local links resolve; every Title-Case heading is an accounted-for contract token."
