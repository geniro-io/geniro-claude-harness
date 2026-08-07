#!/usr/bin/env bash
# Guards hook wiring against the prose that describes it.
#
# Run: bash tests/authoring/lint-hook-wiring.sh
#
# Why this exists: the plugin ships two runtimes with two wiring files, and the
# gap between them is documented in prose — "N hooks are deliberately unwired
# for Cursor". A count in prose drifts the moment a hook is added or ported, and
# it drifts silently: the sentence still reads correct. It has drifted before,
# from three to two, and the audit that caught it had to re-derive the answer by
# hand and then wrote a NEW number that could drift again.
#
# This is the decidable half of counter-drift. Generic count-in-prose checking
# is not: the corpus is dominated by local counts ("one reviewer per dimension",
# "two phases"), which name a relationship, not a population. Only a count of
# something the repo can enumerate is checkable, and the runtime wiring gap is
# that.
#
# Coverage:
#   1. Every hook script in hooks/ is either wired in hooks/hooks.json or named
#      in UNWIRED_BY_DESIGN below with the reason it is not.
#   2. The Claude-minus-Cursor wiring gap matches UNWIRED_FOR_CURSOR exactly —
#      a hook ported to Cursor, or a new hook that never was, moves this set.
#   3. Every prose sentence stating a count of Cursor-unwired hooks states the
#      real one.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq unavailable — hook wiring not checked"; exit 0; }

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# Scripts that live in hooks/ but are deliberately not registered as hooks.
# Each is invoked by something else; the note says by what, so a future reader
# does not "fix" the absence.
UNWIRED_BY_DESIGN="
backpressure.sh|invoked by skills (review, refactor), not a registered hook
geniro-statusline.js|installed into the user's settings.json by /geniro:setup, not a hook event
"

# Hooks wired for Claude Code and deliberately absent from cursor/hooks.json,
# because the Cursor runtime has no compatible event slot. Changing this set is
# a product decision — porting one, or adding a hook that cannot be ported —
# so it is spelled out here rather than derived, and the prose is checked
# against it.
UNWIRED_FOR_CURSOR="
enforce-gate-render.sh|Cursor has no AskUserQuestion hook event
geniro-check-update.js|marketplace update check has no Cursor equivalent
"

# Cursor-only entries: the adapter that translates Claude hook payloads into
# Cursor's shape. It has no Claude-side counterpart by construction.
CURSOR_ONLY="claude-hook-shim.sh"

_wired() {  # <hooks.json> -> registered script basenames, one per line
  jq -r '[.. | objects | select(has("command")) | .command] | .[]' "$1" 2>/dev/null \
    | grep -oE '[a-z0-9-]+\.(sh|js)' | sort -u
}

_names() { printf '%s\n' "$1" | sed '/^$/d' | cut -d'|' -f1 | sort -u; }

claude_wired="$(_wired hooks/hooks.json)"
cursor_wired="$(_wired cursor/hooks.json)"

# --- 1. Every script in hooks/ is wired or declared unwired -------------------
present="$(ls hooks/*.sh hooks/*.js 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u)"
undeclared="$(comm -23 <(printf '%s\n' "$present") \
                       <(printf '%s\n%s\n' "$claude_wired" "$(_names "$UNWIRED_BY_DESIGN")" | sort -u))"
if [ -n "$undeclared" ]; then
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    report_fail "hooks/$h is neither wired in hooks/hooks.json nor listed in UNWIRED_BY_DESIGN — a guard nothing registers never runs"
  done <<< "$undeclared"
else
  echo "OK: every hooks/ script is wired or declared unwired by design"
fi

# --- 2. The Claude-minus-Cursor gap is exactly what is declared ---------------
actual_gap="$(comm -23 <(printf '%s\n' "$claude_wired") <(printf '%s\n' "$cursor_wired"))"
declared_gap="$(_names "$UNWIRED_FOR_CURSOR")"
if [ "$actual_gap" != "$declared_gap" ]; then
  report_fail "the Cursor wiring gap moved — declared [$(echo "$declared_gap" | tr '\n' ' ')] but measured [$(echo "$actual_gap" | tr '\n' ' ')]; update UNWIRED_FOR_CURSOR and every prose count with it"
else
  echo "OK: the Cursor wiring gap matches its declaration ($(printf '%s\n' "$actual_gap" | grep -c .) hooks)"
fi

# Cursor-side extras must be the known adapter only.
extra="$(comm -13 <(printf '%s\n' "$claude_wired") <(printf '%s\n' "$cursor_wired") | grep -vxF "$CURSOR_ONLY" || true)"
if [ -n "$extra" ]; then
  report_fail "cursor/hooks.json wires scripts with no Claude-side counterpart: $(echo "$extra" | tr '\n' ' ')"
fi

# --- 3. Prose counts of the gap state the real number ------------------------
gap_n="$(printf '%s\n' "$actual_gap" | grep -c .)"

# A case, not an associative array: the macOS CI runner's /bin/bash is 3.2,
# where `declare -A` is a syntax error. No other script in this repo uses one.
_numword() {
  case "$1" in
    one) echo 1 ;; two) echo 2 ;;   three) echo 3 ;; four) echo 4 ;; five) echo 5 ;;
    six) echo 6 ;; seven) echo 7 ;; eight) echo 8 ;; nine) echo 9 ;; ten) echo 10 ;;
    *) echo "$1" ;;
  esac
}
prose_checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"; text="${rest#*:}"
  word="$(printf '%s' "$text" | grep -oiE '\b(one|two|three|four|five|six|seven|eight|nine|ten|[0-9]{1,2})\b' | head -1 | tr 'A-Z' 'a-z')"
  [ -n "$word" ] || continue
  n="$(_numword "$word")"
  prose_checked=$((prose_checked + 1))
  case "$n" in
    "$gap_n") ;;
    *) report_fail "$f:$ln says $n hooks are unwired for Cursor; the wiring files say $gap_n" ;;
  esac
done < <(grep -rniE '\b(one|two|three|four|five|six|seven|eight|nine|ten|[0-9]{1,2})\b[^.]{0,50}(deliberately[ -]unwired|unwired)[^.]{0,30}cursor' \
            --include='*.md' . 2>/dev/null | grep -v '^\./design/' || true)
[ "$prose_checked" -gt 0 ] && echo "OK: $prose_checked prose count(s) of the Cursor gap agree with the wiring files"

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS hook-wiring problem(s)." >&2
  exit 1
fi
echo "OK: hook wiring and the prose describing it agree."
