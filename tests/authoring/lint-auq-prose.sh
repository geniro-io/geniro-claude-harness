#!/usr/bin/env bash
# A user-facing choice put to the user in prose instead of through `AskUserQuestion`.
#
# Run: bash tests/authoring/lint-auq-prose.sh
#
# Why this exists: `skills/_shared/gate-rendering.md` §Lean-question conventions
# is canonical — "every user-facing choice goes through the tool", because a
# plain-text `(A)/(B)` in chat captures no structured answer, so a resumed
# session re-asks what the user already decided. A real run put its opening
# decision to the user as "A) Merge / B) Rebase / C) Skip — Reply with A, B,
# or C" in a runtime where `AskUserQuestion` existed. An audit of the whole
# corpus then found ~20 authoring sites where a skill's own text instructed a
# prose ask or described a user decision with no tool named — fixed in the
# same pass that added this lint. Nothing mechanized it before now: there is
# no `Stop` hook (`MIGRATION.md` — removed because Stop hooks fire only
# 50-80% of the time), and Cursor's hook shim has no `AskUserQuestion` event,
# so this authoring lint is the only mechanical surface available.
#
# The audit found four shapes; this lint catches two of them and says so:
#
#   1. CAUGHT — a confirmation put in prose: "ask/confirm with/check with
#      (the) user whether/if/before ...", e.g. "ask the user before
#      replacing" or "ask the user whether to proceed without it". Tractable:
#      the "whether/if/before" tail is what turns a generic verb into a
#      confirmation being asked of the user, and it is what every real fixed
#      violation shared syntactically. Bare "ask the user about X" or "ask
#      the user to name X" (a free-text request, not a decision) does NOT
#      match this shape and is correctly silent — see "What this deliberately
#      excludes" below.
#   2. CAUGHT — options enumerated in prose as the gate's own mechanism, in
#      the one narrow form that is unambiguous: "ask/reply with (the) user
#      ... "<label>" / "<label>"" — a prose instruction to literally pose
#      quoted, slash-separated options. The broader "Reply with A, B, or C" /
#      "let me know which you prefer" phrasings from the audit do not recur
#      anywhere in the current corpus outside the two documented quoting
#      sites (see exclusions), so widening the net to match them would be
#      untested against zero real hits — narrower and proven beats broad and
#      guessed.
#   3. NOT ATTEMPTED — "a gate described but never wired" (a step says the
#      user chooses or approves, with no tool call specified anywhere). This
#      is a semantic gap between prose and a missing tool call with no
#      syntactic tell — a regex cannot tell "the user decides X" (a correct,
#      common sentence in a skill that WILL fire an AUQ two paragraphs later)
#      from the same sentence in a skill that never does. `/audit-plugin`'s
#      read-based dimensions are the right tool for this; a hard lint here
#      would either miss it (matching nothing) or fire on every gate
#      description in the corpus (matching everything).
#   4. NOT ATTEMPTED — "offer to X" as a disguised question. "Offer" is used
#      constantly in this corpus for both a real prose offer (a violation)
#      and a description of an AUQ option's own label ("offer to map the
#      codebase" describing an option's text) — the two are lexically
#      identical and only the surrounding gate structure (already fired vs.
#      not) tells them apart. Same reasoning as #3.
#
# Scope: skills/** and .claude/skills/** (mirroring lint-skills.sh's two-
# population scan) — every other tracked file is author-facing or generated,
# not a runtime instruction a skill body follows.
#
# What this deliberately excludes, and why each is safe to stay silent on:
#
# - A question put to a SUBAGENT, or written into a FILE, is not user-facing
#   at all — out of scope by definition, not an exclusion this lint has to
#   apply: neither shape's regex fires on "ask the agent" / "ask it to write".
# - Prose describing an AUQ's own OPTION LABELS ("ask the user if they want
#   to map the codebase:" immediately followed by "Use `AskUserQuestion`") is
#   the wired, correct shape — excluded BY PROXIMITY (see below), not by an
#   exception list, because the very thing that makes it correct (the tool
#   fires right there) is what the proximity check reads.
# - An ANTI-RATIONALIZATION table quotes the bad shape only to forbid it
#   ("| \"I'll ask the user how to resolve it.\" | A reporter doesn't decide
#   fixes... |"). Excluded BY CONSTRUCTION: every such row in this corpus
#   opens with a quoted string as its first cell (`| "..."`), which a real
#   instruction never does — an instruction is prose, not a quotation of
#   itself. Matching that shape at the start of the flagged line is a
#   structural fact about the table format, not a list of table locations.
# - A free-text DATA request ("ask the user to name the area to improve
#   instead") is not a decision with options — nothing in the audit's fixed
#   diff touched this shape, and it is excluded by construction: it carries
#   none of the "whether/if/before" tail Shape 1 requires, and no quoted
#   slash-separated pair for Shape 2.
# - A PERSONA paragraph describing a skill's own high-level behavior in one
#   sentence ("You are a read-only spec producer... ask the user about
#   ambiguous ones, then write...") reads as English prose about what the
#   skill does, not as a step instructing HOW to ask — same reason as the
#   data-request case: no "whether/if/before" tail, no quoted options.
# - Four sites state or quote the rule itself and must not fire on their own
#   canonical text — kept as a short, commented path list because none of
#   them share a structural marker the other three exclusions above use:
#     * skills/_shared/gate-rendering.md — states "every user-facing choice
#       goes through the tool" and quotes the forbidden `(A)/(B)` shape as
#       the example of what it forbids.
#     * skills/_shared/runtime-portability.md — documents the ONE legitimate
#       substitution: asking in prose when a runtime genuinely lacks the
#       tool (confirmed absent from that session's tool surface).
#     * .claude/skills/analyze-thread/checks-reference.md — the K4 check
#       definition, which quotes the violating shapes as the patterns its
#       OWN judge should look for.
#     * .claude/skills/find-threads/ — a documented, deliberate exception:
#       it takes a free-text pick because a project can hold hundreds of
#       threads against the tool's 4-option cap (`gate-rendering.md`
#       §Lean-question conventions, "Exception: an unbounded option set").
#
# Proximity is the "is it wired" signal for both shapes: a hit is silent when
# `AskUserQuestion` or the bare `AUQ` abbreviation appears within
# $CONTEXT_WINDOW lines either side of it in the SAME file — the tool being
# named right next to the prose is what makes "ask the user if they want to
# map the codebase:" followed two lines later by "Use `AskUserQuestion`"
# correct instead of a bypass. $CONTEXT_WINDOW=6 is the smallest value that
# passes the full corpus clean at authoring time (verified by hand against
# every hit both shapes produce here); false negatives this proximity check
# lets through — a genuinely unwired ask sitting coincidentally near an
# unrelated AUQ mention — are the accepted cost of a mechanical proxy, and
# `/audit-plugin`'s read-based dimensions are the backstop for those.
#
# The proximity window is NOT the recall limiter that mattered in practice.
# The one real violation the audit fixed that this lint's own shape can't
# reach was `.claude/skills/improve-template/phase-4-6-implement-review.md`'s
# original "...report the exact `git push -u origin <branch>` command and ask
# the user to confirm before running it" — Shape 1's rigid adjacency
# (`user[[:space:]]+(whether|if|before)`, nothing but whitespace between
# "user" and the tail) never matched it because "to confirm " sits between
# them, and the nearest `AskUserQuestion` was 11 lines away, outside
# $CONTEXT_WINDOW either way — proximity was never even reached. The known
# gap is this shape rigidity: "ask the user to confirm/to decide/to choose"
# and "ask the user about/on whether" read as the same confirmation to a
# human but don't match. Left unwidened per the header's opening trade-off —
# the corpus residue for `ask (the )?user (to confirm|to decide|to choose|
# about whether|on whether)` is zero right now, so this gap is theoretical,
# not a currently-missed violation; re-check that residue before spending on
# it.
#
# Zero observed false positives over the full corpus at authoring time,
# verified by hand against every hit; this is what earns HARD status. Only
# these two narrow, syntactically-anchored shapes are checked — the broader
# "ask the user" / "confirm with the user" / "check with the user" phrase set
# alone (with no whether/if/before tail) was tried first and produced 3 false
# positives (the persona paragraph and free-text-request cases above), so it
# was narrowed rather than shipped noisy; see the calibration trail in the
# commit/PR that introduced this file for the discarded broader pattern.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

CONTEXT_WINDOW=6
FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# Shape 1 — a confirmation put in prose: ask/confirm-with/check-with (the)
# user, then a whether/if/before tail. Case-insensitive; "the" is optional
# ("ask user before each Edit" appears in this corpus, inside a quoted
# anti-rationalization cell it is legitimately silent on).
SHAPE1_RE='(ask|confirm with|check with)( the)?[[:space:]]user[[:space:]]+(whether|if|before)'

# Shape 2 — an ask instruction followed by quoted, slash-separated option
# labels: the literal "ask the user \"X\" / \"Y\"" mechanism. Bounded to 60
# chars between "user" and the first quote so it cannot bridge two unrelated
# sentences.
SHAPE2_RE='(ask|reply with)( the)?[[:space:]]user.{0,60}"[^"]+"[[:space:]]*/[[:space:]]*"[^"]+"'

# Paths excluded by construction cannot cover: each states, quotes, or
# documents the exception to the rule this lint enforces (see header).
is_excluded_path() {
  case "$1" in
    skills/_shared/gate-rendering.md) return 0 ;;
    skills/_shared/runtime-portability.md) return 0 ;;
    .claude/skills/analyze-thread/checks-reference.md) return 0 ;;
    .claude/skills/find-threads/*) return 0 ;;
    *) return 1 ;;
  esac
}

# A markdown table row whose first cell is itself a quoted string is an
# anti-rationalization row quoting the bad shape to forbid it, never a real
# instruction — a real instruction is prose, not a self-quotation. This is a
# structural fact about the row, not a location, so it applies wherever it
# occurs.
is_antirationalization_row() {
  printf '%s' "$1" | grep -qE '^[[:space:]]*\|[[:space:]]*"'
}

# True when `AskUserQuestion` or the bare `AUQ` token appears within
# $CONTEXT_WINDOW lines either side of line $2 in file $1 — the proximity
# proxy for "already wired to the tool". `AUQ` is padded with non-letter
# boundaries so it does not match inside a longer token.
is_wired_nearby() {
  local file="$1" line="$2" lo hi
  lo=$((line - CONTEXT_WINDOW)); [ "$lo" -lt 1 ] && lo=1
  hi=$((line + CONTEXT_WINDOW))
  sed -n "${lo},${hi}p" "$file" 2>/dev/null | grep -qE 'AskUserQuestion|([^A-Za-z]|^)AUQ([^A-Za-z]|$)'
}

# Emits `<file>:<line>` for every raw regex hit of either shape under the
# given paths, deduplicated — before any of the three exclusions below are
# applied. This is the candidate population `_auq_prose_hits` filters and the
# count the OK line below reports, so a pattern that silently stopped
# matching shows up as "0 candidates" instead of being indistinguishable from
# "0 violations, N candidates all cleared".
#
# -H is load-bearing, not redundant with -r: given a SINGLE FILE argument, GNU
# grep omits the filename prefix while BSD grep emits it. Without -H the
# `cut -d: -f1-2` below takes the line number as the "file" field and the
# `while IFS=: read -r f l` loop (in `_auq_prose_hits` below) binds the real
# line number to `l` from a fabricated `<num>:<num>` pair — `is_wired_nearby`
# then calls `sed` on a nonexistent path, which fails silently under
# `2>/dev/null`, so the whole pipeline yields zero hits: green on macOS,
# blind on CI. The self-tests pass one file at a time, so they are exactly
# that path.
_auq_prose_raw_hits() {
  { grep -rHinoE "$SHAPE1_RE" "$@" 2>/dev/null | cut -d: -f1-2
    grep -rHinoE "$SHAPE2_RE" "$@" 2>/dev/null | cut -d: -f1-2
  } | sort -u -t: -k1,1 -k2,2n
}

# Emits `<file>:<line>` for every unresolved hit of either shape under the
# given paths — `_auq_prose_raw_hits` above, after applying all three
# exclusions.
_auq_prose_hits() {
  while IFS=: read -r f l; do
    [ -n "$f" ] || continue
    is_excluded_path "$f" && continue
    line_text=$(sed -n "${l}p" "$f" 2>/dev/null)
    is_antirationalization_row "$line_text" && continue
    is_wired_nearby "$f" "$l" && continue
    printf '%s:%s\n' "$f" "$l"
  done < <(_auq_prose_raw_hits "$@")
}

candidates=$(_auq_prose_raw_hits skills .claude/skills | grep -c . || true)

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  f="${hit%%:*}"; l="${hit##*:}"
  text=$(sed -n "${l}p" "$f" 2>/dev/null | sed -E 's/^[[:space:]]+//')
  report_fail "$hit: user-facing choice put in prose, not AskUserQuestion — \"$text\""
done < <(_auq_prose_hits skills .claude/skills)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no prose-ask or prose-enumerated-option violations found ($candidates raw candidate hit(s) scanned across skills/** and .claude/skills/**, every one wired or excluded)"
fi

# --- self-test: red on a seeded violation of each shape, green on the wired,
# excluded, and anti-rationalization forms that must NOT fire -------------
# Fixtures live in a scratch dir, never the tracked tree, and reuse the exact
# shapes seen in skills/** — a self-test proving something only about a temp
# file's own invented syntax proves nothing about the matcher's behavior on
# this repo's real prose.
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT

cat > "$SELFTEST_DIR/violation.md" <<'EOF'
If the branch has no upstream, ask the user before pushing it.
If it never answers, ask the user "Skip verification" / "Retry" / "Enter URL manually".
EOF

cat > "$SELFTEST_DIR/clean.md" <<'EOF'
After printing the final report, ask the user if they want to map the codebase:

Use `AskUserQuestion` (header: "Onboard"):

| "I'll ask the user how to resolve it." | A reporter doesn't decide fixes — leave it to the action gate. |

You are a read-only spec producer. You read the PR, ask the user about ambiguous ones, then write a spec.

If absent, report that no handoff exists and ask the user to name the area to improve instead.
EOF

hit_count() {
  ( _auq_prose_hits "$1" ) | grep -c . || true
}

n_violation="$(hit_count "$SELFTEST_DIR/violation.md")"
if [ "$n_violation" -ge 2 ]; then
  echo "OK: self-test — both seeded violations (Shape 1 'ask the user before', Shape 2 quoted-options) are detected"
else
  report_fail "self-test — seeded violation(s) were NOT detected (found $n_violation, want 2); the matcher would miss a real one"
fi

n_clean="$(hit_count "$SELFTEST_DIR/clean.md")"
if [ "$n_clean" -eq 0 ]; then
  echo "OK: self-test — the wired ask, the anti-rationalization quote, the persona sentence, and the free-text request all stay silent"
else
  report_fail "self-test — the clean fixture false-positived on $n_clean line(s) that must stay silent"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS AUQ-prose problem(s)." >&2
  exit 1
fi
echo "OK: every user-facing choice in skills/** and .claude/skills/** routes through AskUserQuestion (or is a documented exception)."
