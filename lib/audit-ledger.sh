#!/usr/bin/env bash
# Audit ledger — the tracked record of every finding an audit has ever raised,
# and what was decided about it.
#
# Source it, then call the functions:
#   source "${CLAUDE_PLUGIN_ROOT}/lib/audit-ledger.sh"
#   ledger_fingerprint <file> <line>          -> location key (stdout)
#   ledger_lookup <file> <fingerprint> <class>-> disposition or empty
#   ledger_record <file> <line> <class> <tier> <disposition> <run> <note>
#   ledger_prune                              -> drop rows whose file is gone
#   ledger_validate                           -> schema check, rc=1 on problems
#
# WHY THIS EXISTS
#
# Seven whole-repo audit rounds produced 138, 121, 101, 87 and 130 findings and
# never converged, because each round started blind. The report is written to a
# gitignored working area and each run gets a fresh container, so no run has
# ever read its predecessor's decisions. The only durable memory — the audit
# skill's do-not-flag list — grew from 11 entries to 16 while roughly 700
# findings passed through it. A finding rejected in round 3 is raised again,
# identically, in round 4.
#
# This file is that memory: committed, so it survives the container; keyed by
# content, so it survives edits.
#
# THE KEY, AND WHY IT IS NOT A LINE NUMBER
#
# The fingerprint follows GitHub's SARIF `primaryLocationLineHash`
# (github/codeql-action, src/fingerprints.ts), for the same reason code scanning
# needs it: an alert must survive the file growing above it.
#
#   * BLOCK_SIZE = 100 characters of context, MOD = 37, polynomial rolling hash.
#   * Spaces and tabs are skipped, and CR / LF / CRLF collapse to one form, so
#     reflowing or reindenting a paragraph does not move the key.
#   * The window spans line boundaries, so the key encodes what FOLLOWS the
#     cited line as well — a rewrite of the surrounding passage legitimately
#     reopens the finding, which is the behaviour we want.
#   * The line NUMBER is not an input. Inserting 200 lines above a finding
#     leaves its key untouched.
#
# One deliberate departure. Code scanning keys on the full repo path, and its
# own documentation notes the consequence: "if the filepaths differ for the same
# result, each time there is a new analysis a new alert will be created". This
# repo relocates files often (the _shared/ extractions), so a full path is too
# brittle a key. PVS-Studio's suppress-base solves that by storing the bare
# BASENAME; here that goes too far the other way, because 20 files are named
# SKILL.md and they would all share one key.
#
# So the key is the last TWO path segments — `review/SKILL.md`, not `SKILL.md`
# and not `skills/review/SKILL.md`. A file that moves within its own component
# keeps its key; one that genuinely relocates between components changes it,
# and re-examining a relocated file is the right outcome rather than a lost row.
#
# WHY THERE IS A `class` COLUMN AT ALL
#
# A code-scanning fingerprint is (ruleId, lineHash) — the ruleId is stable
# because a static analyser has a fixed rule set. An LLM reviewer has no ruleId:
# it phrases the same defect differently every run, so its own words cannot key
# anything. `class` is a short human-written slug (`dedup`, `restatement`,
# `stale-ref`, `magic-number`) chosen once, at the action gate, by whoever
# records the decision. Location comes from the machine; what-about-it comes
# from a person. Both are then stable.

set -uo pipefail

# Cross-shell self-location: BASH_SOURCE is bash-only — sourced under zsh it
# is empty and `set -u` makes the bare expansion an error, which zsh reports
# on stderr and then continues with an empty value: _al_self resolves to "",
# dirname("") is ".", and the ledger silently mis-resolves to a path outside
# the repo. zsh names the sourced file via the %x prompt escape; eval keeps
# the zsh-only syntax out of bash's (and ShellCheck's) parser.
if [ -n "${BASH_SOURCE:-}" ]; then
  _al_self="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  eval '_al_self="${(%):-%x}"'
else
  _al_self="$0"
fi
_LEDGER_ROOT="${GENIRO_REPO_ROOT:-$(cd "$(dirname "$_al_self")/.." && pwd)}"
LEDGER_PATH="${GENIRO_AUDIT_LEDGER:-$_LEDGER_ROOT/design/audit-ledger.tsv}"

_LEDGER_HEADER=$'# fingerprint\tfile\tclass\ttier\tdisposition\truns\tnote'

# Valid dispositions. `rejected` binds future reviewers as hard as the
# do-not-flag list; `accepted` records a defect the repo is choosing to carry;
# `fixed` is history, kept so a regression is visibly a REGRESSION.
_LEDGER_DISPOSITIONS='fixed rejected accepted'

ledger_path() { printf '%s\n' "$LEDGER_PATH"; }

# --- fingerprint --------------------------------------------------------------

# ledger_fingerprint <file> <line> -> 12-hex-digit location key
#
# Hashes the BLOCK_SIZE non-blank characters beginning at <line>, spanning into
# following lines. A line whose remaining context is shorter than the block (end
# of file) hashes what it has — short, but stable, which is all the key needs.
ledger_fingerprint() {
  local file="$1" line="$2"
  [ -f "$file" ] || { printf ''; return 1; }
  awk -v start="$line" -v BLOCK=100 -v MOD=37 '
    NR < start { next }
    {
      # Collapse every line ending to one form before hashing, so a CRLF
      # checkout and an LF checkout of the same content agree.
      gsub(/\r/, "", $0)
      buf = buf $0 "\n"
    }
    END {
      h = 0; n = 0
      for (i = 1; i <= length(buf) && n < BLOCK; i++) {
        c = substr(buf, i, 1)
        if (c == " " || c == "\t" || c == "\n") continue
        # 2^32 modulus: keeps every intermediate under 2^53, so awk double
        # arithmetic stays exact and the value is identical on every platform.
        h = (h * MOD + _ord(c)) % 4294967296
        n++
      }
      printf "%012x\n", h
    }
    function _ord(ch,   i) {
      if (_ORD_INIT != 1) {
        for (i = 32; i < 127; i++) _ORD[sprintf("%c", i)] = i
        _ORD_INIT = 1
      }
      # Non-ASCII bytes (this corpus uses em-dashes and § constantly) fall back
      # to a fixed value rather than 0: 0 would make every multi-byte character
      # invisible to the hash, so two passages differing only in punctuation
      # would collide.
      return (ch in _ORD) ? _ORD[ch] : 200
    }
  ' "$file"
}

# --- read ---------------------------------------------------------------------

_ledger_rows() {
  [ -f "$LEDGER_PATH" ] || return 0
  grep -v '^#' "$LEDGER_PATH" 2>/dev/null | grep -v '^[[:space:]]*$' || true
}

# _ledger_key <path> -> the last two path segments, the ledger's file key.
_ledger_key() {
  local p="${1%/}" parent
  parent="$(basename "$(dirname "$p")")"
  case "$parent" in
    .|/) printf '%s' "$(basename "$p")" ;;
    *)   printf '%s/%s' "$parent" "$(basename "$p")" ;;
  esac
}

# ledger_lookup <file> <fingerprint> <class> -> disposition, or empty
ledger_lookup() {
  local file base="" fp="$2" class="$3"
  file="$1"; base="$(_ledger_key "$file")"
  _ledger_rows | awk -F'\t' -v b="$base" -v f="$fp" -v c="$class" \
    '$1 == f && $2 == b && $3 == c { print $5; exit }'
}

# ledger_runs <file> <fingerprint> <class> -> comma-separated run ids seen so far
#
# The convergence signal. A finding with no mechanical oracle — "this reads
# better", "these two sections could merge" — is one reviewer's taste on one
# run, and this repo's own history says 94% of such edits get rewritten by a
# later round. Agreement between INDEPENDENT runs is the only oracle that class
# has, so the count of distinct runs is what a fix decision keys on.
ledger_runs() {
  local base fp="$2" class="$3"
  base="$(_ledger_key "$1")"
  _ledger_rows | awk -F'\t' -v b="$base" -v f="$fp" -v c="$class" \
    '$1 == f && $2 == b && $3 == c { print $6; exit }'
}

ledger_run_count() {
  local runs; runs="$(ledger_runs "$@")"
  [ -n "$runs" ] || { echo 0; return 0; }
  printf '%s' "$runs" | tr ',' '\n' | grep -c .
}

# --- write --------------------------------------------------------------------

# ledger_record <file> <line> <class> <tier> <disposition> <run> [note]
#
# Idempotent per (fingerprint, basename, class): recording the same finding from
# a later run appends that run id and updates the disposition rather than adding
# a second row. That append is what makes ledger_run_count meaningful.
ledger_record() {
  local file="$1" line="$2" class="$3" tier="$4" disp="$5" run="$6" note="${7:-}"
  local base fp tmp prior_runs merged

  case " $_LEDGER_DISPOSITIONS " in
    *" $disp "*) ;;
    *) echo "audit-ledger: unknown disposition '$disp' (want: $_LEDGER_DISPOSITIONS)" >&2; return 64 ;;
  esac
  case "$class" in
    ''|*[!a-z0-9-]*) echo "audit-ledger: class must be a lowercase-hyphen slug, got '$class'" >&2; return 64 ;;
  esac
  # A rejection with no reason is the row a future round cannot act on: it
  # suppresses a finding while telling nobody why, which is how a suppression
  # store rots into an unreviewable blanket.
  if [ "$disp" = rejected ] && [ -z "$note" ]; then
    echo "audit-ledger: a 'rejected' row needs a note saying why" >&2; return 64
  fi

  base="$(_ledger_key "$file")"
  fp="$(ledger_fingerprint "$file" "$line")" || {
    echo "audit-ledger: cannot fingerprint $file:$line" >&2; return 65; }

  prior_runs="$(ledger_runs "$file" "$fp" "$class")"
  if [ -n "$prior_runs" ]; then
    case ",$prior_runs," in
      *",$run,"*) merged="$prior_runs" ;;
      *) merged="$prior_runs,$run" ;;
    esac
  else
    merged="$run"
  fi

  mkdir -p "$(dirname "$LEDGER_PATH")"
  tmp="$(mktemp)" || return 1
  {
    printf '%s\n' "$_LEDGER_HEADER"
    _ledger_rows | awk -F'\t' -v b="$base" -v f="$fp" -v c="$class" \
      '!($1 == f && $2 == b && $3 == c)'
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$fp" "$base" "$class" "$tier" "$disp" "$merged" "$note"
  } > "$tmp" && mv "$tmp" "$LEDGER_PATH" || { rm -f "$tmp"; return 1; }
}

# --- maintenance --------------------------------------------------------------

# ledger_prune — drop rows whose file no longer exists anywhere in the repo.
#
# ESLint's `--prune-suppressions` in miniature, and for the same reason: an
# empirical study of suppression stores (FSE 2025) found most entries are never
# removed, and that the ones eventually removed had already been useless for a
# long time. Staleness is mechanical, so it is removed mechanically rather than
# re-argued by whoever next reads the file.
ledger_prune() {
  local tmp dropped=0 kept=0 root
  # Resolved at CALL time, not at source time: a caller running the prune
  # against a different tree (a test fixture, a worktree) sets GENIRO_REPO_ROOT
  # after this file is already sourced, and a root frozen at source time would
  # silently search the wrong tree and prune every row as missing.
  root="${GENIRO_REPO_ROOT:-$_LEDGER_ROOT}"
  [ -f "$LEDGER_PATH" ] || { echo "audit-ledger: nothing to prune"; return 0; }
  tmp="$(mktemp)" || return 1
  {
    printf '%s\n' "$_LEDGER_HEADER"
    while IFS=$'\t' read -r fp base class tier disp runs note; do
      [ -n "${fp:-}" ] || continue
      # `head -1`, not `-quit`: the latter is GNU find only and the macOS CI
      # runner would treat every row as stale and prune the whole ledger.
      if [ -n "$(find "$root" -path "*/$base" -print 2>/dev/null | head -1)" ]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$fp" "$base" "$class" "$tier" "$disp" "$runs" "$note"
        kept=$((kept + 1))
      else
        echo "pruned: $base ($class) — file no longer in the repo" >&2
        dropped=$((dropped + 1))
      fi
    done < <(_ledger_rows)
  } > "$tmp" && mv "$tmp" "$LEDGER_PATH" || { rm -f "$tmp"; return 1; }
  echo "audit-ledger: kept $kept, pruned $dropped"
}

# ledger_validate — schema check. Run by the test suite and before a resume.
ledger_validate() {
  local problems=0 lineno=0
  [ -f "$LEDGER_PATH" ] || { echo "OK: no ledger yet"; return 0; }
  while IFS= read -r row; do
    lineno=$((lineno + 1))
    [ -n "$row" ] || continue
    local n; n="$(printf '%s' "$row" | awk -F'\t' '{print NF}')"
    if [ "$n" -ne 7 ]; then
      echo "FAIL: ledger row $lineno has $n columns, want 7" >&2; problems=$((problems + 1)); continue
    fi
    local fp class disp note
    fp="$(printf '%s' "$row" | cut -f1)"
    class="$(printf '%s' "$row" | cut -f3)"
    disp="$(printf '%s' "$row" | cut -f5)"
    note="$(printf '%s' "$row" | cut -f7)"
    case "$fp" in
      [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
      *) echo "FAIL: ledger row $lineno fingerprint '$fp' is not 12 hex digits" >&2; problems=$((problems + 1)) ;;
    esac
    case "$class" in
      ''|*[!a-z0-9-]*) echo "FAIL: ledger row $lineno class '$class' is not a lowercase-hyphen slug" >&2; problems=$((problems + 1)) ;;
    esac
    case " $_LEDGER_DISPOSITIONS " in
      *" $disp "*) ;;
      *) echo "FAIL: ledger row $lineno disposition '$disp' unknown" >&2; problems=$((problems + 1)) ;;
    esac
    if [ "$disp" = rejected ] && [ -z "$note" ]; then
      echo "FAIL: ledger row $lineno rejects a finding with no reason" >&2; problems=$((problems + 1))
    fi
  done < <(_ledger_rows)
  [ "$problems" -eq 0 ] && { echo "OK: ledger schema valid ($lineno rows)"; return 0; }
  return 1
}
