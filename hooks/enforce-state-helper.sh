#!/usr/bin/env bash
# enforce-state-helper.sh
# PreToolUse hook for Write/Edit/MultiEdit AND Bash — blocks direct writes to
# canonical state paths under .geniro/, steering skills to atomic-state-write.
#
# Scope: writes to canonical state paths under .geniro/ must go through the
# atomic-state-write helper (lib/atomic-state-write.sh), not direct
# Edit/Write/Bash calls. The helper guarantees tmp + fsync + rename + fsync-dir
# atomicity. Direct calls truncate-and-rewrite — a reader during the window
# sees a partial file.
#
# Edit/Write/MultiEdit branch: checks .tool_input.file_path.
# Bash branch: catches shell-side writes the file-tool matcher never sees —
# redirection (>, >>, >|), tee, in-place sed (-i), cp/mv destinations, dd of=,
# interpreter-mediated writes (python/node/perl/ruby opening a state file
# for writing, a pathlib write, an interpreter copy/rename landing on one; awk
# redirecting `print` into one), and shell indirection — `sh -c "..."`,
# `eval "..."`, a quoted program piped to a bare shell, and a heredoc body fed
# to one, each of which the guard re-runs on.
# Reads (cat/grep) stay allowed. Commands invoking the sanctioned helpers
# (atomic_state_write / atomic_state_append) are allowed — they write via their
# own mktemp + mv. Paths under .geniro/state/tdd/ are exempt: the TDD-order
# hook's state file is a documented exception written via its own mktemp + mv
# procedure (skills/_shared/tdd-cycle.md §State file contract).
#
# Per-project bypass:
#   .geniro/safety.json — { "allow_patterns": ["enforce-state-helper"] }
#
# Pattern ID: enforce-state-helper
#
# Design rationale: ARCHITECTURE.md §State Files

set -euo pipefail

MODE="block"

# Fail open but LOUDLY if jq is missing: without it the hook cannot parse tool
# input, and a silent exit 0 would leave the user believing the guard is active.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"Geniro guard inactive: jq not found on PATH, so direct state-path writes are NOT being checked. Install jq to restore the guard."}\n'
  exit 0
fi

# Consume stdin — REQUIRED first step for Claude Code hooks.
INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# Locate nearest .geniro/safety.json walking up from cwd.
find_safety_json() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.geniro/safety.json" ]; then
      echo "$dir/.geniro/safety.json"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

ALLOWED=""
SAFETY_FILE=$(find_safety_json 2>/dev/null || true)
if [ -n "$SAFETY_FILE" ] && [ -f "$SAFETY_FILE" ]; then
  # allow_patterns entries name exact pattern IDs. The membership test below is a
  # substring probe over the space-joined list, so a single entry that CARRIES
  # whitespace ("harmless write-env alsoharmless") would silently enable every ID
  # spelled inside it. Reject those at load rather than weaken the probe.
  ALLOWED=$(jq -r '.allow_patterns[]? | select(type == "string" and (test("[[:space:]]") | not))' "$SAFETY_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
fi

case " $ALLOWED " in
  *" enforce-state-helper "*) exit 0 ;;
esac

# Check if the path is a canonical state-file path (ARCHITECTURE.md §State Files).
# The (^|/) prefix in the patterns below matches both relative (.geniro/...) and
# absolute (/x/.geniro/...) forms.
matches_state_path() {
  local p="$1"
  # Exclusions — files under .geniro/ that are NOT frontmatter-bearing state
  # files and shouldn't trigger the helper warning:
  #   *.lock      — coordination locks (e.g., .geniro/planning/.codebase-map.lock)
  #   .fingerprint.json — pure JSON, no frontmatter
  #   *.tmp / *.tmp.PID.HOST — atomic-write temp files (helper's own intermediate
  #                            file before mv), generic .tmp suffix
  #   *.swp       — vim swap files
  #   *~          — emacs backup files
  #   T1 ephemeral subagent outputs — deterministically transient prose
  #   reports / screenshots, no frontmatter, deleted at the owning run's terminal exit:
  #     .kr-out.md, .ce-out.md, .tr-out.md, .adversarial-out.md, .research-out.md,
  #     .spec-challenge-out.md (spec-challenge pass scratch report)
  #     .research-<facet>.md (per-facet research outputs from /plan Phase 1)
  #     notes.md (ad-hoc scratch under <task-dir>/)
  #     playwright-verify.png (pre-Ship visual verification screenshot)
  #     .verify-cache.json + its .cache.XXXXXX mktemp form — the /implement
  #       verification cache, written via mktemp + mv (state-tier-spec.md), no
  #       frontmatter, so the atomic-helper warning does not apply
  if echo "$p" | grep -qE '\.lock$|/\.fingerprint\.json$|\.tmp(\.[^/]+)?$|\.swp$|~$|/\.(kr|ce|tr|adversarial|research|spec-challenge)-out\.md$|/\.research-[^/]+\.md$|/notes\.md$|/playwright-verify\.png$|/\.verify-cache\.json$|/\.verify-cache\.cache\.[A-Za-z0-9]+$'; then
    return 1
  fi
  # T1, T2, T3 directories under .geniro/.
  if echo "$p" | grep -qE '(^|/)\.geniro/(state|planning|knowledge|instructions|actions|workflow)/'; then
    return 0
  fi
  # Plugin metadata file (T3 CRUD).
  if echo "$p" | grep -qE '(^|/)\.geniro/\.geniro-state\.json$'; then
    return 0
  fi
  return 1
}

# Match the right helper to the tier.
suggested_helper() {
  local p="$1"
  if echo "$p" | grep -qE '\.geniro/knowledge/.*\.jsonl$'; then
    echo "atomic_state_append"
  else
    echo "atomic_state_write"
  fi
}

# A path directly under .geniro/state/ that conforms to none of the canonical
# layouts is invisible to the validator and session-restore (ad-hoc schema-less
# files were observed in the wild). Recognized layouts:
#   state/<skill>/<slug>/state.md  ·  state/setup/state.md singleton
#   state/handoff/from-<producer>-<branch>.md  ·  state/tdd/state-<slug>.md
non_canonical_state_layout() {
  local p="$1"
  echo "$p" | grep -qE '(^|/)\.geniro/state/' || return 1
  if echo "$p" | grep -qE '(^|/)\.geniro/state/[^/]+/[^/]+/state\.md$'; then return 1; fi
  if echo "$p" | grep -qE '(^|/)\.geniro/state/setup/state\.md$'; then return 1; fi
  if echo "$p" | grep -qE '(^|/)\.geniro/state/handoff/from-[^/]+\.md$'; then return 1; fi
  if echo "$p" | grep -qE '(^|/)\.geniro/state/tdd/state-[^/]+\.md$'; then return 1; fi
  return 0
}

# Emit the block message for one matched state path, then exit 2 (block) or 0 (warn).
emit_state_helper_decision() {
  local path="$1"
  local helper
  helper=$(suggested_helper "$path")

  local prefix="State-helper [enforce-state-helper]"
  local body="Direct write to canonical state path: $path
$prefix:   Use \`$helper\` via Bash for atomicity guarantee.
$prefix:   Pattern:
$prefix:     source \"\${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh\"
$prefix:     $helper \"$path\" <<'EOF'
$prefix:     ...content...
$prefix:     EOF
$prefix:   Spec: skills/_shared/atomic-state-write.md"

  local layout_hint=""
  if non_canonical_state_layout "$path"; then
    layout_hint="$prefix:   This path under .geniro/state/ matches no canonical layout (state/<skill>/<slug>/state.md, the state/setup/state.md singleton, state/handoff/from-<producer>-<branch>.md, or state/tdd/state-<slug>.md) — ad-hoc files there are invisible to the validator and session-restore."
  fi

  if [ "$MODE" = "block" ]; then
    echo "$prefix: $body" >&2
    [ -n "$layout_hint" ] && echo "$layout_hint" >&2
    echo "$prefix: To bypass per-project, add \"enforce-state-helper\" to allow_patterns in .geniro/safety.json." >&2
    exit 2
  fi

  echo "$prefix (warn): $body" >&2
  [ -n "$layout_hint" ] && echo "$layout_hint" >&2
  jq -nc --arg p "$path" --arg h "$helper" \
    '{systemMessage: ("Geniro: direct write to state path " + $p + " — use the " + $h + " helper (atomic write) instead. Bypass: \"enforce-state-helper\" in .geniro/safety.json.")}'
  exit 0
}

# Shell indirection (`sh -c "<payload>"`, `eval "<payload>"`, a program piped to
# a bare shell, a heredoc fed to one) and interpreter-mediated writes are
# single-sourced in lib/write-vectors.sh. Each inline fallback keeps the guard
# whole on a vendored install shipping hooks/ without lib/ — a missing helper
# must never make this guard fail open — and is a VERBATIM copy of the canonical
# function (delimited by GENIRO-VENDORED markers). A one-sided edit reopens the
# hole on that install, so edit both or neither.
_geniro_wv_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/write-vectors.sh"
if [ -f "$_geniro_wv_helper" ]; then
  # shellcheck source=/dev/null
  source "$_geniro_wv_helper" 2>/dev/null || true
fi
if ! command -v _geniro_extract_inner_payloads >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_extract_inner_payloads
_geniro_extract_inner_payloads() {
  local cmd="${1:-}"
  local raw="${2:-}"
  if [ -z "$cmd" ] && [ -z "$raw" ]; then
    return 0
  fi
  local _m _pl

  # Arm 1 — interpreter `-c` payload.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E 's/^.*[[:space:]]-[A-Za-z]*c[A-Za-z]*[[:space:]]+//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_/])(sh|bash|zsh|dash|ksh|ash)[[:space:]]+-[A-Za-z]*c[A-Za-z]*[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)' 2>/dev/null || true)"

  # Arm 2 — `eval` payload. The preceding-character class excludes `-` so a long
  # option belonging to another tool (`node --eval`, `perl --eval`) is not read
  # as the shell builtin; those are interpreter payloads, not shell commands.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E 's/^[^[:alnum:]_]?eval[[:space:]]+//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_/-])eval[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)' 2>/dev/null || true)"

  # Arm 3 — a quoted literal piped into a BARE shell. `echo "<program>" | bash`
  # feeds <program> on stdin, so it is neither a `-c` argument nor an `eval`
  # operand, and the guard's quote-scrub blanks it as data. The right-hand side
  # must carry no flag cluster containing `c` (that spelling is arm 1's, and
  # with -c the shell ignores stdin). Only a QUOTED left-hand literal is
  # extractable: a producer that COMPUTES its program (a file read, a network
  # download) carries no literal this scan can read — the download spelling is
  # hooks/security-pattern-check.sh's sec-curl-pipe-sh pattern instead.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    # Drop from the LAST pipe, so a `|` inside the literal survives.
    _pl=$(printf '%s' "$_m" | sed -E 's/[[:space:]]*[|][^|]*$//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '("[^"]*"|'\''[^'\'']*'\'')[^|"'\'']*\|[[:space:]]*((sudo|command|env|exec)[[:space:]]+)*([^[:space:]|;&<>]*/)?(sh|bash|zsh|dash|ksh|ash)([[:space:]]+-[a-bd-zA-BD-Z0-9]+)*[[:space:]]*($|[;&|])' 2>/dev/null || true)"

  # Arm 4 — a heredoc body fed to a bare shell (`bash <<EOF … EOF`,
  # `cat <<EOF | sh`). This is the mirror image of arm 3: the body is stdin, and
  # every guard's heredoc scrub deletes it BEFORE extraction because a heredoc is
  # data in every other position (`cat > notes.md <<EOF`). So the body is
  # re-derived here from the RAW command, and emitted only when the opener line
  # names a bare shell as a command word. One body LINE per payload: the guards
  # match per line and per `;`-bounded span, and joining the body would let a
  # single `#` comment line swallow the commands after it.
  if [ -n "$raw" ]; then
    printf '%s\n' "$raw" | awk '
      hd {
        line = $0
        if (dash) sub(/^\t+/, "", line)
        if (line == tag) { hd = 0; next }
        if (emit) print line
        next
      }
      match($0, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z0-9_]*/) {
        tag = substr($0, RSTART, RLENGTH)
        dash = (tag ~ /^<<-/)
        sub(/^<<-?[[:space:]]*/, "", tag)
        gsub(/["'\'']/, "", tag)
        hd = 1
        emit = ($0 ~ /(^|[|;&][[:space:]]*|[[:space:]])(sudo[[:space:]]+|command[[:space:]]+|env[[:space:]]+|exec[[:space:]]+)*([^[:space:]|;&<>]*\/)?(sh|bash|zsh|dash|ksh|ash)([[:space:]]|$)/)
        next
      }
    ' 2>/dev/null || true
  fi

  return 0
}
# GENIRO-VENDORED-END _geniro_extract_inner_payloads
fi
if ! command -v _geniro_wv_resolve >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_wv_resolve
_geniro_wv_resolve() {
  local lit="${1:-}" cmd="${2:-}"
  case "$lit" in
    *'`'*) return 1 ;;
    *'$'*) : ;;
    *) printf '%s' "$lit"; return 0 ;;
  esac
  local resolved="$lit" ref vn val
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    vn="${ref#\$}"; vn="${vn#\{}"; vn="${vn%\}}"
    val=$(printf '%s' "$cmd" \
      | grep -oE "(^|[[:space:];&|])${vn}=[^[:space:];&|\"']+" \
      | tail -1 | sed -E 's/^[^=]*=//' || true)
    if [ -z "$val" ]; then return 1; fi
    resolved=$(printf '%s' "$resolved" | sed "s|[\$]{${vn}}|${val}|g; s|[\$]${vn}|${val}|g")
  done <<< "$(printf '%s' "$lit" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' || true)"
  printf '%s' "$resolved"
  return 0
}
# GENIRO-VENDORED-END _geniro_wv_resolve
fi
if ! command -v _geniro_interp_write_targets >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_interp_write_targets
_geniro_interp_write_targets() {
  local cmd="${1:-}"
  [ -z "$cmd" ] && return 0
  if ! printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(python[0-9.]*|node|perl|ruby|php|awk|gawk|mawk)([[:space:]]|$)'; then
    return 0
  fi

  # Quote class tolerating a shell backslash-escape (`open(\"x\", \"w\")` is how a
  # double-quoted -c argument reaches a guard).
  local _q="\\\\?[\"']"
  # A non-literal target: a bare identifier or an escaped variable
  # (`fopen(\$f, "w")`), i.e. anything that is not the opening quote of a literal.
  local _nonlit="(\\\\[^\"']|[^\\\\\"'[:space:])])"
  local unresolved=0 has_awk=0 lit resolved
  if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(awk|gawk|mawk)([[:space:]]|$)'; then
    has_awk=1
  fi

  # --- targets named by a quoted literal ---
  while IFS= read -r lit; do
    [ -z "$lit" ] && continue
    if resolved=$(_geniro_wv_resolve "$lit" "$cmd"); then
      printf '%s\n' "$resolved"
    else
      unresolved=1
    fi
  done <<< "$(
    {
      # open()/fopen()/File.open() count only with a write mode in the second
      # argument — `open('<path>')` is a read and must stay allowed.
      printf '%s' "$cmd" \
        | grep -oE "(open|fopen|File\.open)\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*,[[:space:]]*${_q}[waxWAX>]" \
        | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # perl's 3-argument open puts the mode second and the path third
      # (`open(FH, ">", "path")`).
      printf '%s' "$cmd" \
        | grep -oE "open\([^,)]*,[[:space:]]*${_q}[>+]{1,2}${_q}[[:space:]]*,[[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^.*,[[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # These write unconditionally, so their first argument is the target.
      printf '%s' "$cmd" \
        | grep -oE "(writeFileSync|appendFileSync|createWriteStream|writeFile|file_put_contents|File\.write|IO\.write)\([[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # pathlib: the target is the Path(...) argument, not write_text's content.
      printf '%s' "$cmd" \
        | grep -oE "Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)[[:space:]]*\.(write_text|write_bytes|touch|open)" \
        | sed -E "s/^Path\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # Copy/rename: the SECOND argument is the target. This is the interpreter
      # spelling of a cp/mv DESTINATION, which the shell-side cp/mv vector in
      # every calling guard already treats as a write — without it the same
      # clobber walks past that guard just by being written in Python or Node.
      # (No apostrophe above on purpose: bash 3.2 does not skip comments while
      # scanning a $( ) body, so one would read as an unterminated quote.)
      printf '%s' "$cmd" \
        | grep -oE "(shutil\.copy[A-Za-z0-9_]*|shutil\.move|os\.rename|os\.replace|copyFileSync|renameSync|File\.rename)\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*,[[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^.*,[[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # awk: `print`/`printf` redirected to a quoted literal, the shape that
      # writes a file from inside an awk program
      # (`awk 'BEGIN{print "x" > "path"}'`). The redirect lives inside the
      # program string, so every shell-syntax redirection vector blanks it as
      # data. Only a QUOTED target counts: an awk redirect to a bare identifier
      # is indistinguishable from a numeric comparison (`print (a > b)`), and
      # firing on that shape would block read-only awk one-liners.
      if [ "$has_awk" = "1" ]; then
        printf '%s' "$cmd" \
          | grep -oE "(print|printf)[^;}]*>{1,2}[[:space:]]*${_q}[^\\\\\"']+${_q}" \
          | sed -E "s/^.*>{1,2}[[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      fi
    } 2>/dev/null || true
  )"

  # --- targets this scan cannot resolve ---
  # A write op whose target is a variable or expression, and the in-place
  # interpreter edits (perl -pi -e, ruby -i, perl -i.bak) whose target is the
  # file operand. The flag must end at a word or suffix boundary so an unrelated
  # long option (`ruby -version`) does not read as `-i`.
  if printf '%s' "$cmd" | grep -qE "open\([[:space:]]*${_nonlit}[^)]*,[[:space:]]*${_q}[waxWAX>]|open\([^)]*mode[[:space:]]*=[[:space:]]*${_q}[wax]|(writeFileSync|appendFileSync|createWriteStream|writeFile|file_put_contents|File\.write|File\.open|IO\.write)\([[:space:]]*${_nonlit}"; then
    unresolved=1
  fi
  # Copy/rename whose DESTINATION (second argument) is a variable or expression.
  if printf '%s' "$cmd" | grep -qE "(shutil\.copy[A-Za-z0-9_]*|shutil\.move|os\.rename|os\.replace|copyFileSync|renameSync|File\.rename)\([^,)]*,[[:space:]]*${_nonlit}"; then
    unresolved=1
  fi
  # pathlib's write_text/write_bytes carry CONTENT, not a path — the target sits
  # in the Path(...) call. A literal there was already emitted above; every other
  # spelling (`p.write_text(d)` on a Path built earlier) leaves it unknown.
  if printf '%s' "$cmd" | grep -qE '(write_text|write_bytes)\('; then
    if ! printf '%s' "$cmd" | grep -qE "Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)[[:space:]]*\.(write_text|write_bytes)"; then
      unresolved=1
    fi
  fi
  if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(perl|ruby)[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*i([[:space:].]|$)'; then
    unresolved=1
  fi

  [ "$unresolved" = "1" ] && return 10
  return 0
}
# GENIRO-VENDORED-END _geniro_interp_write_targets
fi

if [ "$TOOL_NAME" = "Bash" ]; then
  # ---- Bash branch: shell-side writes into canonical state paths ----
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  if [ -z "$COMMAND" ]; then
    exit 0
  fi

  # Heredoc bodies are DATA, not shell syntax — a `> .geniro/...` inside one is
  # text. Drop body lines (between <<TAG / <<-TAG / <<'TAG' and the closing TAG)
  # before any extraction; the line carrying the << operator is kept, so
  # `atomic_state_write x <<EOF > y` still yields its redirect target.
  SCRUBBED=$(printf '%s\n' "$COMMAND" | awk '
    hd {
      line = $0
      if (dash) sub(/^\t+/, "", line)
      if (line == tag) hd = 0
      next
    }
    match($0, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z0-9_]*/) {
      tag = substr($0, RSTART, RLENGTH)
      dash = (tag ~ /^<<-/)
      sub(/^<<-?[[:space:]]*/, "", tag)
      gsub(/["'\'']/, "", tag)
      hd = 1
      print
      next
    }
    { print }
  ')

  # Re-run THIS guard on each extracted payload (unblanked); a block inside
  # propagates out. Nested indirection terminates because each payload is
  # strictly shorter than the command it came from. Arms 1-3 read the
  # heredoc-scrubbed text; arm 4 needs the RAW command, whose heredoc bodies the
  # scrub above dropped as data.
  _geniro_self="${BASH_SOURCE[0]:-$0}"
  INNER_PAYLOADS=$(_geniro_extract_inner_payloads "$SCRUBBED" "$COMMAND")
  if [ -n "$INNER_PAYLOADS" ]; then
    while IFS= read -r _pl; do
      [ -z "$_pl" ] && continue
      if ! printf '%s' "$_pl" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' | bash "$_geniro_self"; then
        exit 2
      fi
    done <<< "$INNER_PAYLOADS"
  fi

  JOINED="${SCRUBBED//\\$'\n'/ }"

  # Quoted string literals are data (`echo "see > .geniro/x"` writes nothing).
  # Scrubbed per LINE, newlines INTACT: a newline separates two commands exactly
  # as `;` does, and collapsing it to a space first put a canonical multi-line
  # `atomic_state_write … <<EOF` call and a raw redirect on the following line
  # into ONE segment, which the per-segment helper exemption then cleared
  # wholesale.
  JOINED=$(printf '%s\n' "$JOINED" | sed -E "s/'[^']*'/ /g; s/\"[^\"]*\"/ /g")
  # Strip trailing comments. Quotes are already blanked above, so a `#` at a
  # word boundary is a real comment — drop it (to the end of ITS line, which is
  # why this also runs before the split) so a helper name in a comment can't gate
  # the allow-check below.
  JOINED=$(printf '%s\n' "$JOINED" | sed -E 's/(^|[[:space:]])#.*$//')

  # Sanctioned helpers write via their own mktemp + mv. A helper call in ONE
  # segment must not whitelist a raw redirect in ANOTHER (`atomic_state_write x;
  # echo y > .geniro/z/state.md`), so the allow is applied PER segment: split on
  # ; && || | AND on newline, drop only the segments that actually invoke a
  # helper, and keep the rest for the write-vector extraction below. This runs
  # AFTER the quote+comment scrub, so the helper name counts only as a real
  # command word — a name in data (`echo "atomic_state_write" > .geniro/x`) no
  # longer short-circuits.
  MASKED=""
  _sep_split=$(printf '%s\n' "$JOINED" | sed -E 's/(\|\||&&|[;&|])/\n/g')
  while IFS= read -r _seg; do
    if printf '%s' "$_seg" | grep -qE '\b(atomic_state_write|atomic_state_append)\b'; then
      continue
    fi
    MASKED="${MASKED}${_seg}
"
  done <<< "$_sep_split"
  ONELINE="$MASKED"

  CANDIDATES=""
  add_candidate() {
    local c="$1"
    c="${c#\"}"; c="${c%\"}"
    c="${c#\'}"; c="${c%\'}"
    if [ -n "$c" ]; then
      CANDIDATES="${CANDIDATES}${c}
"
    fi
  }

  # 1) Redirection targets: > file, >> file, >| file.
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    add_candidate "$(printf '%s' "$tok" | sed -E 's/^>{1,2}\|?[[:space:]]*//')"
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '>{1,2}\|?[[:space:]]*[^[:space:];|&<>)]+' || true)"

  # 2) tee: every non-flag argument of a tee invocation is written to.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      case "$tok" in *tee|-*) continue ;; esac
      add_candidate "$tok"
    done
    set +f
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[|;&[:space:]])tee[[:space:]]+[^|;&]*' || true)"

  # 3) In-place sed: file arguments of a `sed -i` span are overwritten.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    printf '%s' "$span" | grep -qE '[[:space:]]-i|[[:space:]]--in-place' || continue
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      case "$tok" in
        *sed|-*) continue ;;
        s[!a-zA-Z0-9]*|y[!a-zA-Z0-9]*) continue ;;
      esac
      add_candidate "$tok"
    done
    set +f
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[|;&[:space:]])sed[[:space:]]+[^|;&]*' || true)"

  # 4) cp/mv: only the DESTINATION (last non-flag token) is a write. A cp/mv
  #    whose SOURCE is itself under .geniro/ is a housekeeping rename/copy of
  #    content already written through the helper (version-it, pre-edit snapshot,
  #    revert) — an atomic filesystem move, not a torn-write risk — so the
  #    destination is skipped. A source OUTSIDE .geniro/ keeps blocking: that is
  #    a content write into the tree around the helper.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    last=""
    first=""
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      case "$tok" in cp|mv|*/cp|*/mv|-*) continue ;; esac
      [ -z "$first" ] && first="$tok"
      last="$tok"
    done
    set +f
    # A source containing a `..` segment only LOOKS like it is already inside the
    # tree — `.geniro/../evil.md` resolves outside it, which is the content write
    # the carve-out exists to keep blocking. Reject it before the glob, mirroring
    # the `..` rejection in block-geniro-deletion.sh's check_delete_arg.
    case "/$first/" in
      */../*) : ;;
      *)
        case "$first" in
          *.geniro/*) continue ;;
        esac
        ;;
    esac
    case "$last" in ""|cp|mv|*/cp|*/mv) : ;; *) add_candidate "$last" ;; esac
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[|;&[:space:]])(cp|mv)[[:space:]]+[^|;&]*' || true)"

  # 5) dd of=target
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    add_candidate "${tok#of=}"
  done <<< "$(printf '%s' "$ONELINE" | grep -oE 'of=[^[:space:];|&]+' || true)"

  # 6) truncate -s <size> FILE... — each FILE is emptied/rewritten. Skip the size
  #    operand (the token after -s/--size) and a -r/--reference source.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    set -f
    skip_next=0
    # shellcheck disable=SC2086
    for tok in $span; do
      if [ "$skip_next" = "1" ]; then skip_next=0; continue; fi
      case "$tok" in
        *truncate) continue ;;
        -s|--size|-r|--reference) skip_next=1; continue ;;
        -*) continue ;;
      esac
      add_candidate "$tok"
    done
    set +f
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[|;&[:space:]])truncate[[:space:]]+[^|;&]*' || true)"

  # 7) shred FILE... — destroys/overwrites each FILE in place. Skip -n/-s count
  #    and size operands.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    set -f
    skip_next=0
    # shellcheck disable=SC2086
    for tok in $span; do
      if [ "$skip_next" = "1" ]; then skip_next=0; continue; fi
      case "$tok" in
        *shred) continue ;;
        -n|--iterations|-s|--size) skip_next=1; continue ;;
        -*) continue ;;
      esac
      add_candidate "$tok"
    done
    set +f
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[|;&[:space:]])shred[[:space:]]+[^|;&]*' || true)"

  # 8) install / rsync SRC... DEST — the DEST (last non-flag token) is written,
  #    like cp/mv; an install `-t DIR` / `--target-directory DIR` writes into DIR.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    last=""
    tgt_dir=""
    take_dir=0
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      if [ "$take_dir" = "1" ]; then tgt_dir="$tok"; take_dir=0; continue; fi
      case "$tok" in
        install|rsync|*/install|*/rsync) continue ;;
        -t|--target-directory) take_dir=1; continue ;;
        --target-directory=*) tgt_dir="${tok#--target-directory=}"; continue ;;
        -*) continue ;;
      esac
      last="$tok"
    done
    set +f
    if [ -n "$tgt_dir" ]; then
      # install -t DIR form: DIR is the write target; trailing tokens are sources.
      add_candidate "$tgt_dir"
    else
      case "$last" in ""|install|rsync|*/install|*/rsync) : ;; *) add_candidate "$last" ;; esac
    fi
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[|;&[:space:]])(install|rsync)[[:space:]]+[^|;&]*' || true)"

  # 9) ln -f ... LINK — the LINK (last non-flag token) is created/overwritten
  #    when -f/--force is present (without -f, ln refuses to clobber).
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    printf '%s' "$span" | grep -qE '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force' || continue
    last=""
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      case "$tok" in ln|*/ln|-*) continue ;; esac
      last="$tok"
    done
    set +f
    case "$last" in ""|ln|*/ln) : ;; *) add_candidate "$last" ;; esac
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[|;&[:space:]])ln[[:space:]]+[^|;&]*' || true)"

  # 10) Interpreter-mediated writes: python/node/perl/ruby/php opening a state
  #     file for writing, a pathlib Path(...) write, an interpreter copy/rename
  #     landing on one, or an awk program redirecting `print` into one. Vectors
  #     1-9 read $ONELINE, whose heredoc bodies and quoted literals were blanked
  #     as data — and an interpreter's file write is not shell syntax anywhere, so
  #     `python3 - "$S" <<'PY' … open(p,'w').write(b) … PY` reaches the filesystem
  #     completely unchecked. This vector therefore scans the RAW $COMMAND, and
  #     fires only on the conjunction interpreter + write op + target, so a
  #     read-only interpreter call stays allowed. Contract: lib/write-vectors.sh —
  #     which is the single source of the op list precisely so this guard cannot
  #     drift behind its five siblings again.
  _isw_unresolved=0
  _isw_targets=$(_geniro_interp_write_targets "$COMMAND") || _isw_unresolved=1
  if [ -n "$_isw_targets" ]; then
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      add_candidate "$tok"
    done <<< "$_isw_targets"
  fi
  if [ "$_isw_unresolved" = "1" ]; then
    # rc=10: at least one write target is a variable or expression
    # (`open(p,'w')`), unresolvable from the command text. Fall back to the
    # .geniro/ paths named anywhere in the command — the state paths this guard
    # protects are distinctive, so a path that is not the real target costs
    # nothing, while `S=.geniro/…; python3 -c "open(p,'w')"` still lands.
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      add_candidate "$tok"
    done <<< "$(printf '%s' "$COMMAND" | grep -oE "[^[:space:]\"'=(),;|&<>]*\.geniro/[^[:space:]\"'(),;|&<>]*" || true)"
  fi

  if [ -z "$CANDIDATES" ]; then
    exit 0
  fi
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    # .geniro/state/tdd/ is a documented exception (own mktemp + mv procedure).
    case "$cand" in *.geniro/state/tdd/*) continue ;; esac
    if matches_state_path "$cand"; then
      emit_state_helper_decision "$cand"
    fi
  done <<< "$CANDIDATES"
  exit 0
fi

# ---- Edit/Write/MultiEdit branch ----
# Extract file path from tool input JSON (NotebookEdit carries notebook_path).
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

case "$FILE_PATH" in *.geniro/state/tdd/*) exit 0 ;; esac

if ! matches_state_path "$FILE_PATH"; then
  exit 0
fi

emit_state_helper_decision "$FILE_PATH"
