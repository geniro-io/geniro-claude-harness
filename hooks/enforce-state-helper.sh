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
# interpreter-mediated writes (a scripting runtime opening a state file
# for writing, a pathlib write, an interpreter copy/rename landing on one; awk
# redirecting `print` into one), and shell indirection — `sh -c "..."`,
# `eval "..."`, a quoted program piped to a shell, a heredoc body fed to one, a
# process substitution a shell reads, and an interpreter shelling out, each of
# which the guard re-runs on.
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

# Consume stdin — REQUIRED first step for Claude Code hooks.
INPUT=$(cat)

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

if [ "$HAVE_JQ" = "1" ]; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null || echo "")
else
  TOOL_NAME=""
  FILE_PATH=""
fi

# A truncated/malformed payload makes jq fail on EVERY field it would extract
# from $INPUT, not just one — so TOOL_NAME and FILE_PATH both come back empty
# together, control reaches neither the Bash branch (TOOL_NAME != "Bash") nor
# a real Edit/Write/MultiEdit/NotebookEdit call, and the Edit branch's own
# empty-FILE_PATH check further down would otherwise exit 0 on exactly the
# input class this scan exists for. (A well-formed payload with a valid first
# JSON object plus trailing garbage is NOT this case — jq emits the parsed
# value before erroring on the garbage, so TOOL_NAME/FILE_PATH/COMMAND still
# come back populated and the normal per-branch logic already handles it.)
# This same coarse scan is pure grep+sed and needs no jq, so it must run
# BEFORE, not below, the jq-missing fail-open branch further down — a
# canonical state path named in the raw text still blocks even when no
# structured parsing can run at all, instead of jq's absence being a free
# pass for every direct state-path write.
# Mirrors file-protection.sh's identical hoisted scan.
if [ -z "$TOOL_NAME" ] && [ -z "$FILE_PATH" ]; then
  RAW_TARGETS=$(printf '%s' "$INPUT" \
    | grep -oE '"(file_path|notebook_path|command)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' \
    | sed -E 's/^"[a-z_]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)
  if printf '%s' "$RAW_TARGETS" | grep -qE '(^|/|[[:space:]])\.geniro/(state|planning|knowledge|instructions|actions|workflow)/|(^|/|[[:space:]])\.geniro/\.geniro-state\.json|(^|/|[[:space:]])\.geniro/safety\.json'; then
    if [ "$HAVE_JQ" = "1" ]; then
      echo "State-helper [enforce-state-helper] blocked [jqless-fallback]: the tool input names a canonical .geniro/ state path but the payload could not be parsed (tool_name and file_path both came back empty), so only a coarse raw-text check ran." >&2
    else
      echo "State-helper [enforce-state-helper] blocked [jqless-fallback]: the tool input names a canonical .geniro/ state path but jq is not installed, so only a coarse raw-text check ran." >&2
    fi
    exit 2
  fi
fi

# Fail open but LOUDLY if jq is missing: the raw-text scan above still ran,
# but everything past this point needs structured parsing (COMMAND
# extraction, the write-vector scan, the safety.json allow-list), which jq's
# absence takes off the table.
if [ "$HAVE_JQ" = "0" ]; then
  printf '{"systemMessage":"Geniro guard inactive: jq not found on PATH, so direct state-path writes are NOT being checked beyond the coarse raw-text scan above. Install jq to restore the guard."}\n'
  exit 0
fi

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

# The broad "enforce-state-helper" grant is applied per-branch, AFTER
# check_safety_json_write has had a chance to run on the actual write
# target(s) — see the Edit/Write and Bash branches below. It must NOT exit
# here, before that path-specific check: .geniro/safety.json disables every
# guard by pattern ID, so a write to IT stays gated on its own,
# separately-grantable "safety-json-edit" pattern even when the broad grant is
# present. (Measured 2026-08-10: with only "enforce-state-helper" allowed, a
# direct write to safety.json returned rc 0 through an early exit sitting
# here — the same grant meant to unblock ordinary state-file writes also let
# an agent rewrite the file that turns off every other guard in one Write.)

# .geniro/safety.json disables every guard by pattern ID — an agent that can
# freely overwrite it can self-grant any bypass in one Write, so it gets a
# gate of its own rather than riding on matches_state_path's generic T1-T3
# coverage (safety.json sits at .geniro/ top level, outside every guarded
# prefix). Kept as a SEPARATE pattern ID from "enforce-state-helper" on
# purpose: by the time this runs, the broad bypass above has already exited
# if granted, so this is the narrower, independently-grantable route.
# Legitimate user edits stay possible — allow_patterns is read from the
# file's CURRENT content before this check runs, so a human adds
# "safety-json-edit" to it directly (outside the agent, or after explicit
# approval) the same way every other pattern ID here is unlocked; that first
# grant just can't come from the agent overwriting the file itself.
#
# Collapse a path to the exact string the shell/filesystem treats as the
# target, before any prefix/tier regex runs against it: repeated slashes
# (`.geniro//x`), a `.` segment (`.geniro/./x`), and a trailing slash or run of
# them (`.geniro/x/`, `.geniro/x//`) all resolve to the SAME path a bare
# `.geniro/x` spelling does, and every equivalent spelling must decide
# identically or one of them is an open bypass (2026-08-09 audit #1/#2: a
# `/./` segment defeated both is_safety_json_path and matches_state_path).
# Looped to a fixed point so a comb of these in one path
# (`.geniro/./x//./`) fully collapses regardless of order — a single pass only
# shortens a run of 3+ slashes by one. Does NOT resolve `..`: every call site
# here treats a `..` segment as its own separate concern (reject or leave
# alone) rather than resolving it, and folding that in here would silently
# turn a rejection into a resolution.
# Duplicated verbatim in hooks/block-geniro-deletion.sh — lib/write-vectors.sh
# is out of scope for this fix (owned by a different maintainer pass), and
# both guards already vendor their own inline fallbacks of lib/ helpers for
# the same reason (a missing lib/ must never make either guard fail open).
# tests/hooks/path-normalize-matrix.sh feeds both guards every spelling above
# and asserts identical exit codes — a one-sided edit fails it.
_geniro_normalize_path() {
  local p="${1:-}"
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  # Collapse `//` and `/./` with prefix/suffix cuts, looped to a fixed point —
  # NOT ${p//pat/repl}: bash 3.2 (macOS /bin/bash) keeps the backslash of an
  # escaped `/` in the replacement, emitting `\/` into the result and silently
  # un-matching every guard pattern downstream (fails OPEN).
  while :; do
    case "$p" in
      *//*)  p="${p%%//*}/${p#*//}" ;;
      */./*) p="${p%%/./*}/${p#*/./}" ;;
      *) break ;;
    esac
  done
  while [ "${p%/.}" != "$p" ]; do p="${p%/.}"; done
  while [ "${p%/}" != "$p" ] && [ -n "${p%/}" ]; do p="${p%/}"; done
  printf '%s' "$p"
}

# Pattern ID: safety-json-edit
is_safety_json_path() {
  local p
  p="$(_geniro_normalize_path "$1")"
  echo "$p" | grep -qE '(^|/)\.geniro/safety\.json$'
}

check_safety_json_write() {
  local path="$1"
  is_safety_json_path "$path" || return 0
  case " $ALLOWED " in
    *" safety-json-edit "*) return 0 ;;
  esac
  echo "State-helper [safety-json-edit] blocked: direct write to .geniro/safety.json — this file disables every guard by pattern ID, so an agent must not self-grant a bypass in one Write. To allow this, add \"safety-json-edit\" to allow_patterns in .geniro/safety.json." >&2
  exit 2
}

# Check if the path is a canonical state-file path (ARCHITECTURE.md §State Files).
# The (^|/) prefix in the patterns below matches both relative (.geniro/...) and
# absolute (/x/.geniro/...) forms.
matches_state_path() {
  local p="$1"
  # Collapse repeated slashes and `.` segments first: the protected-prefix
  # regexes below require an EXACT `.geniro/<tier>/` span, so a path built by
  # joining a variable that already ends in `/` (`.geniro//planning/foo/state.md`)
  # inserts a second `/` right where "planning" must start, and a `/./` segment
  # (`.geniro/./planning/foo/state.md`) inserts a segment the span doesn't
  # expect either — both silently fail the match without this.
  p="$(_geniro_normalize_path "$p")"
  # Exclusions — files under .geniro/ that are NOT frontmatter-bearing state
  # files and shouldn't trigger the helper warning:
  #   *.lock      — coordination locks (e.g., .geniro/planning/.codebase-map.lock)
  #   .fingerprint.json — pure JSON, no frontmatter
  #   *.tmp / *.tmp.PID.HOST — atomic-write temp files (helper's own intermediate
  #                            file before mv), generic .tmp suffix
  #   *.swp       — vim swap files
  #   *~          — emacs backup files
  #   *.pre-edit.bak — /geniro:actions edit-subcommand's own revert snapshot
  #                    (skills/actions/subcommand-edit.md §Snapshot): a `cp`
  #                    of the file being edited to a sibling backup, restored
  #                    via `mv` or removed via `rm -f` on every exit path —
  #                    not a canonical CRUD target another consumer reads
  #   T1 ephemeral subagent outputs — deterministically transient prose
  #   reports / screenshots, no frontmatter, deleted at the owning run's terminal exit:
  #     .kr-out.md, .ce-out.md, .tr-out.md, .adversarial-out.md, .research-out.md,
  #     .spec-challenge-out.md (spec-challenge pass scratch report)
  #     .research-<facet>.md (per-facet research outputs from /plan Phase 1)
  #     notes.md (ad-hoc scratch under <task-dir>/)
  #     playwright-verify.png (pre-Ship visual verification screenshot)
  if echo "$p" | grep -qE '\.lock$|/\.fingerprint\.json$|\.tmp(\.[^/]+)?$|\.swp$|~$|\.pre-edit\.bak$|/\.(kr|ce|tr|adversarial|research|spec-challenge)-out\.md$|/\.research-[^/]+\.md$|/notes\.md$|/playwright-verify\.png$'; then
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

  echo "$prefix: $body" >&2
  [ -n "$layout_hint" ] && echo "$layout_hint" >&2
  echo "$prefix: To bypass per-project, add \"enforce-state-helper\" to allow_patterns in .geniro/safety.json." >&2
  exit 2
}

# Shell indirection (`sh -c "<payload>"`, `eval "<payload>"`, a program piped to
# a shell, a heredoc fed to one, a process substitution, an interpreter shelling
# out) and interpreter-mediated writes are
# single-sourced in lib/write-vectors.sh. Each inline fallback keeps the guard
# whole on a vendored install shipping hooks/ without lib/ — a missing helper
# must never make this guard fail open — and is a VERBATIM copy of the canonical
# function. A one-sided edit reopens the hole on that install, so edit both or
# neither — parity is enforced by tests/hooks/write-vectors-fallback-parity.sh,
# not by markers on the canonical side (lib/write-vectors.sh carries none).
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
  local _m _pl _lit

  # ONE shell-word matcher for every arm, and every part of it is DERIVED rather
  # than enumerated — including the SHAPE of the shell word itself, not just the
  # list of channels it appears in.
  #
  # A WRAPPER is any command word whose own arguments are flags, `VAR=value`
  # assignments, durations or `{}` placeholders. `sudo`, `nohup`, `timeout 5` and
  # `env FOO=bar` fall out of that shape — and so do `setsid`, `busybox`,
  # `unshare`, `firejail` and whatever ships next, each of which a NAME list would
  # have to grow for one at a time (and did not: `setsid bash` and `busybox sh`
  # both walked past every guard). Keeping the ARGUMENT shape constrained is what
  # stops an ordinary two-word command (`grep foo bash`) from reading as a
  # wrapped shell.
  local _wv_wrd='[^-[:space:];|&<>"'\''=][^[:space:];|&<>"'\'']*'
  local _wv_wargs='([[:space:]]+(-[^[:space:];|&<>]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];|&<>]*|[0-9]+[smhd]?|[{}]+))*'
  local _wv_pfx="(${_wv_wrd}${_wv_wargs}[[:space:]]+)*"
  local _wv_shq='["'\'']?'
  local _wv_sh="${_wv_pfx}${_wv_shq}"'([^[:space:];|&<>"'\'']*/)?(sh|bash|zsh|dash|ksh|ash|fish|csh|tcsh|xonsh|nu|elvish|rc)'"${_wv_shq}"
  # One quoted literal; and the payload operand form, which may also be bare.
  local _wv_lit='("[^"]*"|'\''[^'\'']*'\'')'
  local _wv_arg='("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)'
  # A quote and its negation, for building a sed script whose delimiter is `#`.
  local _wv_q='["'\'']' _wv_nq='[^"'\'']'
  # Any flag cluster; the `-c` cluster in particular (ANY cluster containing c —
  # -c, -lc, -euc); and a token that is provably NOT a `c` cluster (a short
  # cluster with no c, a long option, a redirection, or a plain operand).
  local _wv_flag='-[^[:space:];|&<>]*'
  local _wv_cflag='-[A-Za-z]*c[A-Za-z]*'
  local _wv_nonc='(-[a-bd-zA-BD-Z0-9]*|--[^[:space:];|&]*|[^-[:space:];|&][^[:space:];|&]*)'

  # Arm 1 — interpreter `-c` payload. The `-c` cluster need not sit adjacent to
  # the shell word (`sh -x -c`, `bash --norc -c`) and the payload need not sit
  # adjacent to `-c` (`sh -c -- '<payload>'`): each adjacency is ONE spelling of
  # the channel, and requiring either emptied the extraction on all the others.
  local _wv_cpfx="${_wv_sh}([[:space:]]+${_wv_flag})*[[:space:]]+${_wv_cflag}([[:space:]]+${_wv_flag})*[[:space:]]+"
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    # Strip the matched PREFIX, anchored at the shell word. A greedy `^.*-c `
    # strip cuts at the LAST `-c`-shaped token instead — and `wc -c`, `sort -c`,
    # `grep -c` and `tar -c` inside the payload are ordinary commands, so
    # appending one benign second command disarmed the arm completely.
    _pl=$(printf '%s' "$_m" | sed -E "s#^[^[:alnum:]_]?${_wv_cpfx}##")
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_cpfx}${_wv_arg}" 2>/dev/null || true)"

  # Arm 2 — `eval` payload. The preceding-character class excludes `-` so a long
  # option belonging to another tool (`node --eval`, `perl --eval`) is not read
  # as the shell builtin; those are interpreter payloads, not shell commands.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E 's/^[^[:alnum:]_]?eval[[:space:]]+//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_/-])eval[[:space:]]+'"${_wv_arg}" 2>/dev/null || true)"

  # Arm 3 — a quoted literal piped into a shell. `echo "<program>" | bash`
  # feeds <program> on stdin, so it is neither a `-c` argument nor an `eval`
  # operand, and the guard's quote-scrub blanks it as data. The right-hand side
  # must carry no flag cluster containing `c` (that spelling is arm 1's, and
  # with -c the shell ignores stdin) — expressed as "every following token is
  # provably not a c cluster", NOT as "the shell word ends the pipeline". The
  # latter is a spelling: one trailing `2>/dev/null`, `--`, `-` or `--posix`,
  # the most ordinary things to append to a command, dropped the payload.
  # Only a QUOTED left-hand literal is extractable: a producer that COMPUTES its
  # program (a file read, a network download) carries no literal this scan can
  # read — the download spelling is hooks/security-pattern-check.sh's
  # sec-curl-pipe-sh pattern instead.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    # Drop from the LAST pipe, so a `|` inside the literal survives.
    _pl=$(printf '%s' "$_m" | sed -E 's/[[:space:]]*[|][^|]*$//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE "${_wv_lit}"'[^|"'\'']*\|[[:space:]]*'"${_wv_sh}"'([[:space:]]+'"${_wv_nonc}"')*[[:space:]]*($|[;&|])' 2>/dev/null || true)"

  # Arm 7 — a herestring fed to a shell (`bash <<< '<payload>'`,
  # `sh -s <<< "<payload>"`). `<<<` feeds the right-hand operand on stdin exactly
  # like arm 3's pipe, but the shell word comes FIRST and the payload follows the
  # operator instead of being piped in from the left — the mirror image of arm 3.
  # Neither arm 1 (no `-c` argument here), arm 3 (no pipe) nor the heredoc scrub
  # (which explicitly excludes `<<<` from heredoc-opener detection, so this text
  # survives it unscrubbed) extracts it.
  local _wv_hspfx="${_wv_sh}([[:space:]]+${_wv_flag})*[[:space:]]*<<<[[:space:]]*"
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E "s#^[^[:alnum:]_]?${_wv_hspfx}##")
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_hspfx}${_wv_arg}" 2>/dev/null || true)"

  # Arm 4 — a heredoc body fed to a shell (`bash <<EOF … EOF`, `cat <<EOF | sh`).
  # This is the mirror image of arm 3: the body is stdin, and every guard's
  # heredoc scrub deletes it BEFORE extraction because a heredoc is data in every
  # other position (`cat > notes.md <<EOF`). So the body is re-derived here from
  # the RAW command, and emitted only when the opener line names a shell as a
  # command word. One body LINE per payload: the guards match per line and per
  # `;`-bounded span, and joining the body would let a single `#` comment line
  # swallow the commands after it. The shell-word matcher reaches awk through the
  # environment, not `-v`, because awk processes escape sequences in a `-v`
  # assignment and would eat the regex's own backslashes.
  if [ -n "$raw" ]; then
    printf '%s\n' "$raw" | GENIRO_WV_SHRE='(^|[|;&][[:space:]]*|[[:space:]])'"${_wv_sh}"'([[:space:]]|$)' awk '
      hd {
        line = $0
        if (dash) sub(/^\t+/, "", line)
        if (line == tag) { hd = 0; next }
        if (emit) print line
        next
      }
      match($0, /<<-?[[:space:]]*[\\"'\'']?[A-Za-z_][A-Za-z0-9_]*/) {
        tag = substr($0, RSTART, RLENGTH)
        dash = (tag ~ /^<<-/)
        sub(/^<<-?[[:space:]]*/, "", tag)
        gsub(/[\\"'\'']/, "", tag)
        hd = 1
        emit = ($0 ~ ENVIRON["GENIRO_WV_SHRE"])
        next
      }
    ' 2>/dev/null || true
  fi

  # Arm 5 — a program fed to a shell through process substitution
  # (`bash <(echo "<program>")`, `sh -s < <(printf '<program>')`). The shell reads
  # it from the /dev/fd path the substitution names, so it carries no `-c`, no
  # pipe into the shell and no heredoc — arms 1-4 all miss it. Every quoted
  # literal inside the substitution is a candidate program, the same limit arm 3
  # carries: a substitution that COMPUTES its program leaves nothing to read.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    while IFS= read -r _lit; do
      [ -z "$_lit" ] && continue
      _pl="$_lit"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s' "$_m" | grep -oE "${_wv_lit}" 2>/dev/null || true)"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_sh}"'[^|;&]*[<>]\([^)]*\)' 2>/dev/null || true)"

  # Arm 6 — an interpreter handing a program to a shell. `os.system('<program>')`,
  # `subprocess.run('<program>', shell=True)` and `child_process.execSync(...)`
  # spawn a real shell, but the interpreter is not one, so no arm above sees the
  # call — and the program is not an interpreter FILE op either, so family B below
  # misses it too. That makes any interpreter a laundering channel for every
  # payload the guards block directly. The quoted argument IS the shell command.
  #
  # Gated on an interpreter COMMAND WORD, because the same text is inert without
  # one: `echo "os.system('rm -rf x')" > notes.md` authors a file, it does not
  # shell out, and blocking it would be a false positive on ordinary code
  # authoring. Nothing extractable is lost — a shell-out inside a script FILE
  # carries no literal in the command either way.
  #
  # The left boundary is the same non-word class the shell matcher uses, not a
  # hand-listed set of separators: `(python3 …)` in a subshell and
  # `out=$(python3 …)` in a command substitution disabled this arm and BOTH
  # interpreter families below while the class enumerated `[|;&[:space:]]|/`.
  if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(python[0-9.]*|node|bun|bunx|deno|tsx|perl|ruby|php|lua|tclsh|Rscript)([[:space:]]|$)'; then
    # A dot is allowed before the op name because that is how the ops are normally
    # reached (`require('child_process').execSync(…)`); the cost is that a JS
    # `re.exec("s")` also yields its argument, which re-scans as an inert word.
    local _wv_shellout='(os\.(system|popen|execute)|subprocess\.[A-Za-z_]+|Kernel\.system|IO\.popen|Open3\.[a-z_]+|exec(Sync|FileSync)?|spawn(Sync)?|fork|system|popen|shell_exec|passthru|proc_open)'
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^[^(]*\([[:space:]]*//')
      _pl="${_pl#\\}"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      _pl="${_pl%\\}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_shellout}"'[[:space:]]*\([[:space:]]*\\?'"${_wv_lit}" 2>/dev/null || true)"

    # Arm 6a-bare — Perl/Ruby's `system`/`exec`/`popen` are BUILTINS as well as
    # functions: `system "rm -rf /"` and `exec "rm -rf /"` run with no call
    # parens at all, so 6a's mandatory `\(` laundered every paren-less spelling.
    # Scoped to this narrow bareword set — not the dotted os.system/subprocess.run
    # forms above, which are never spelled without parens — so an ordinary
    # two-word sentence is not swept in.
    local _wv_bareop='(system|exec|popen)'
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^[^[:space:]]*[[:space:]]+//')
      _pl="${_pl#\\}"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      _pl="${_pl%\\}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_bareop}"'[[:space:]]+\\?'"${_wv_lit}" 2>/dev/null || true)"

    # Perl's qx{}/qx() — a backtick equivalent, the two most common delimiters.
    # Other qx delimiters (qx/…/, qx!…!) are not extracted; the payload must
    # carry no closing }/) of its own for these two to match.
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^[^[:alnum:]_]?qx[{(]//; s/[})]$//')
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])qx\{[^}]*\}|(^|[^[:alnum:]_])qx\([^)]*\)' 2>/dev/null || true)"

    # Arm 6b — the same shell-out written as an ARGV SEQUENCE.
    # `subprocess.run(['sh','-c','<program>'])` and
    # `spawnSync('sh',['-c','<program>'])` reach exactly the same shell, but the
    # program is the element AFTER `-c`, not the call's FIRST argument — so 6a's
    # "the payload is argument one" shape laundered every payload written this
    # way. Keyed on the shell word plus the `-c` element rather than on the call
    # name, so an unlisted spawner cannot hide it either.
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E "s#^.*${_wv_q}${_wv_cflag}${_wv_q}${_wv_nq}*##")
      _pl="${_pl#\\}"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      _pl="${_pl%\\}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE "${_wv_q}"'([^[:space:];|&<>"'\'']*/)?(sh|bash|zsh|dash|ksh|ash|fish|csh|tcsh|xonsh|nu|elvish|rc)'"${_wv_q}${_wv_nq}"'*'"${_wv_q}${_wv_cflag}${_wv_q}${_wv_nq}"'*'"${_wv_lit}" 2>/dev/null || true)"

    # Ruby's and Perl's backtick literal is the same shell-out with no call
    # syntax at all. Narrowed to those two command words: elsewhere a backtick
    # span is ordinary shell command substitution, already visible to the
    # guards as syntax, and re-extracting it would only add noise.
    if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(ruby|perl)([[:space:]]|$)'; then
      while IFS= read -r _m; do
        [ -z "$_m" ] && continue
        _pl=$(printf '%s' "$_m" | sed -E 's/^`//; s/`$//')
        [ -n "$_pl" ] && printf '%s\n' "$_pl"
      done <<< "$(printf '%s\n' "$cmd" | grep -oE '`[^`]*`' 2>/dev/null || true)"
    fi
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
  local resolved="$lit" ref vn val val_esc
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    vn="${ref#\$}"; vn="${vn#\{}"; vn="${vn%\}}"
    val=$(printf '%s' "$cmd" \
      | grep -oE "(^|[[:space:];&|])${vn}=[^[:space:];&|\"']+" \
      | tail -1 | sed -E 's/^[^=]*=//' || true)
    if [ -z "$val" ]; then return 1; fi
    # Escape backslash and & before using $val as a sed REPLACEMENT: unescaped,
    # a backslash in the value mangles the substitution (sed reads it as an
    # escape) and an & re-inserts the whole matched text instead of the
    # literal value — either way the write/delete target silently comes out
    # wrong. Order matters: double backslashes FIRST, then escape &, so the
    # backslash this step inserts for & is not itself re-doubled.
    val_esc=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/&/\\\&/g')
    resolved=$(printf '%s' "$resolved" | sed "s|[\$]{${vn}}|${val_esc}|g; s|[\$]${vn}|${val_esc}|g")
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
  # Runtime roster. bun and tsx implement node:fs verbatim and deno ships its own
  # Deno.* file API, so a roster frozen at the 2019 set lets one word bypass the
  # whole channel. The left boundary is the same non-word class the shell matcher
  # uses: enumerating separators omitted `(` and backtick, so a subshell or a
  # command substitution around the interpreter disabled this whole family.
  if ! printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(python[0-9.]*|node|bun|bunx|deno|tsx|perl|ruby|php|lua|tclsh|Rscript|awk|gawk|mawk)([[:space:]]|$)'; then
    return 0
  fi

  # Quote class tolerating a shell backslash-escape (`open(\"x\", \"w\")` is how a
  # double-quoted -c argument reaches a guard).
  local _q="\\\\?[\"']"
  # A non-literal target: a bare identifier or an escaped variable
  # (`fopen(\$f, "w")`), i.e. anything that is not the opening quote of a literal.
  local _nonlit="(\\\\[^\"']|[^\\\\\"'[:space:])])"
  # Ops whose FIRST argument is the target and which write unconditionally.
  # Base-keyed: `writeFile` covers fs.writeFile/writeFileSync/promises.writeFile,
  # `writeTextFile` covers Deno.writeTextFile(Sync), `truncate`/`ftruncate` cover
  # os.truncate/os.ftruncate and fs.truncate(Sync)/fs.ftruncate(Sync) — a
  # truncation is a write (it replaces the file's content with zero-or-fewer
  # bytes) exactly like `truncate -s 0 FILE` on the shell side.
  local _wops_first='((writeFile|appendFile|createWriteStream|outputFile|writeTextFile|truncate|ftruncate)(Sync)?|file_put_contents|File\.write|IO\.write)'
  # Copy/rename: the SECOND argument is the target. This is the interpreter
  # spelling of a cp/mv DESTINATION, which the shell-side cp/mv vector in every
  # calling guard already treats as a write — without it the same clobber walks
  # past that guard just by being written in Python or Node.
  local _wops_second='(shutil\.copy[A-Za-z0-9_]*|shutil\.move|os\.rename|os\.replace|File\.rename|FileUtils\.(cp|mv|copy|move)|(copyFile|rename|cp)(Sync)?)'
  local unresolved=0 has_awk=0 lit resolved
  if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(awk|gawk|mawk)([[:space:]]|$)'; then
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
      # argument — `open('<path>')` is a read and must stay allowed. The Lua
      # io.open('<path>','w') spelling is the same shape and matches on the name.
      printf '%s' "$cmd" \
        | grep -oE "(open|fopen|File\.open)\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*,[[:space:]]*${_q}[waxWAX>]" \
        | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # The 3-argument perl open puts the mode second and the path third
      # (`open(FH, ">", "path")`).
      printf '%s' "$cmd" \
        | grep -oE "open\([^,)]*,[[:space:]]*${_q}[>+]{1,2}${_q}[[:space:]]*,[[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^.*,[[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      printf '%s' "$cmd" \
        | grep -oE "${_wops_first}\([[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # pathlib: the target is the Path(...) argument, not the write_text body.
      printf '%s' "$cmd" \
        | grep -oE "Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)[[:space:]]*\.(write_text|write_bytes|touch|open)" \
        | sed -E "s/^Path\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # (Every comment in this $( ) body keeps its apostrophes and parentheses
      # balanced on purpose: bash 3.2 does not skip comments while scanning the
      # body, so an odd one reads as an unterminated quote or an unclosed group.)
      printf '%s' "$cmd" \
        | grep -oE "${_wops_second}\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*,[[:space:]]*${_q}[^\\\\\"']+${_q}" \
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
  if printf '%s' "$cmd" | grep -qE "open\([[:space:]]*${_nonlit}[^)]*,[[:space:]]*${_q}[waxWAX>]|open\([^)]*mode[[:space:]]*=[[:space:]]*${_q}[wax]|(${_wops_first}|File\.open)\([[:space:]]*${_nonlit}"; then
    unresolved=1
  fi
  # Copy/rename whose DESTINATION (second argument) is a variable or expression.
  if printf '%s' "$cmd" | grep -qE "${_wops_second}\([^,)]*,[[:space:]]*${_nonlit}"; then
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
if ! command -v _geniro_join_quoted_newlines >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_join_quoted_newlines
_geniro_join_quoted_newlines() {
  local cmd="${1:-}"
  [ -z "$cmd" ] && return 0
  printf '%s\n' "$cmd" | awk '
    { buf = buf $0 "\n" }
    END {
      n = length(buf); q = ""; out = ""; seg = ""; cmt = 0; prev = "\n"
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (cmt) {
          out = out c
          if (c == "\n") cmt = 0
        } else if (q == "") {
          if (c == "#" && index("\n \t;&|(", prev) > 0) { cmt = 1; out = out c }
          else if (c == "\"" || c == "'\''") { q = c; seg = c }
          else { out = out c }
        } else if (c == "\n") {
          seg = seg " "
        } else {
          seg = seg c
          if (c == q) { out = out seg; q = ""; seg = "" }
        }
        prev = c
      }
      if (q != "") { printf "%s", buf } else { printf "%s", out }
    }
  ' 2>/dev/null || printf '%s\n' "$cmd"
}
# GENIRO-VENDORED-END _geniro_join_quoted_newlines
fi
if ! command -v _geniro_wv_expand_assignments >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_wv_expand_assignments
_geniro_wv_expand_assignments() {
  local text="${1:-}"
  [ -z "$text" ] && return 0
  local _asn _name _val _pairs=""
  while IFS= read -r _asn; do
    [ -z "$_asn" ] && continue
    _asn="${_asn#"${_asn%%[A-Za-z_]*}"}"
    _name="${_asn%%=*}"
    _val="${_asn#*=}"
    case "$_val" in
      '"'*'"') _val="${_val#\"}"; _val="${_val%\"}" ;;
      "'"*"'") _val="${_val#\'}"; _val="${_val%\'}" ;;
    esac
    case "$_val" in ''|*'$'*|*'`'*) continue ;; esac
    _pairs="${_pairs}${#_name} ${_name} ${_val}"$'\n'
  done <<< "$(printf '%s\n' "$text" | grep -oE '(^|[;&|(]|[[:space:]])[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'\''[^'\'']*'\''|[^[:space:];&|)]*)' || true)"

  while IFS=' ' read -r _ _name _val; do
    [ -z "${_name:-}" ] && continue
    text="${text//\$\{$_name\}/$_val}"
    text="${text//\$$_name/$_val}"
  done <<< "$(printf '%s' "$_pairs" | sort -rn)"
  printf '%s\n' "$text"
}
# GENIRO-VENDORED-END _geniro_wv_expand_assignments
fi
if ! command -v _geniro_wv_unquote_words >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_wv_unquote_words
_geniro_wv_unquote_words() {
  local text="${1:-}"
  [ -z "$text" ] && return 0
  printf '%s\n' "$text" | sed -E "
    s/\\\$([\"'])/\\1/g
    s/\"([^\"[:space:]]*)\"/\\1/g
    s/'([^'[:space:]]*)'/\\1/g
    s/\\\\([A-Za-z0-9._/-])/\\1/g
  "
}
# GENIRO-VENDORED-END _geniro_wv_unquote_words
fi
if ! command -v _geniro_wv_cd_prefix >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_wv_cd_prefix
_geniro_wv_cd_prefix() {
  local text="${1:-}" marker="${2:-}"
  [ -z "$text" ] && return 0
  [ -z "$marker" ] && return 0
  local prefix="" _cd_span _cd_tok
  while IFS= read -r _cd_span; do
    [ -z "$_cd_span" ] && continue
    set -f
    # shellcheck disable=SC2086
    for _cd_tok in $_cd_span; do
      _cd_tok="${_cd_tok#\\}"
      while [ "${_cd_tok#\(}" != "$_cd_tok" ]; do _cd_tok="${_cd_tok#\(}"; done
      case "$_cd_tok" in cd|pushd|*/cd|*/pushd|-*|+*) continue ;; esac
      _cd_tok="${_cd_tok#\"}"; _cd_tok="${_cd_tok%\"}"
      _cd_tok="${_cd_tok#\'}"; _cd_tok="${_cd_tok%\'}"
      case "/${_cd_tok%/}/" in
        */"$marker"/*) prefix="${_cd_tok%/}" ;;
      esac
      break
    done
    set +f
  done <<< "$(printf '%s\n' "$text" | grep -oE '(^|[\\|;&(/[:space:]])(cd|pushd)[[:space:]]+[^|;&]*' || true)"
  printf '%s' "$prefix"
  return 0
}
# GENIRO-VENDORED-END _geniro_wv_cd_prefix
fi

if [ "$TOOL_NAME" = "Bash" ]; then
  # ---- Bash branch: shell-side writes into canonical state paths ----
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  if [ -z "$COMMAND" ]; then
    # jq is present, but the command extracted empty — either tool_input.command
    # was genuinely absent, or the payload was malformed JSON the parse above
    # silently swallowed (`|| echo ""`). A malformed payload must not be a free
    # pass: run the same coarse fail-closed raw-text scan the three peer
    # data-loss guards (file-protection.sh, block-dangerous-git.sh,
    # block-geniro-deletion.sh) run in this exact situation, so a direct write
    # into a canonical state path still blocks even when parsing broke.
    RAW_TARGETS=$(printf '%s' "$INPUT" \
      | grep -oE '"(file_path|notebook_path|command)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' \
      | sed -E 's/^"[a-z_]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)
    if printf '%s' "$RAW_TARGETS" | grep -qE '(^|/|[[:space:]])\.geniro/(state|planning|knowledge|instructions|actions|workflow)/|(^|/|[[:space:]])\.geniro/\.geniro-state\.json'; then
      echo "State-helper [enforce-state-helper] blocked [jqless-fallback]: the tool input names a canonical .geniro/ state path but tool_input.command could not be parsed, so only a coarse raw-text check ran." >&2
      exit 2
    fi
    exit 0
  fi

  # Heredoc bodies are DATA, not shell syntax — a `> .geniro/...` inside one is
  # text. Drop body lines (between <<TAG / <<-TAG / <<'TAG' / <<\TAG and the closing TAG)
  # before any extraction; the line carrying the << operator is kept, so
  # `atomic_state_write x <<EOF > y` still yields its redirect target.
  SCRUBBED=$(printf '%s\n' "$COMMAND" | awk '
    hd {
      line = $0
      if (dash) sub(/^\t+/, "", line)
      if (line == tag) { hd = 0; nbuf = 0; next }
      buf[nbuf++] = $0
      next
    }
    {
      n = length($0); q = ""; pos = 0
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q != "") { if (c == q) q = ""; continue }
        if (c == "\"" || c == "'\''") { q = c; continue }
        if (c == "<" && substr($0, i+1, 1) == "<" && substr($0, i+2, 1) != "<") { pos = i; break }
      }
      if (pos > 0 && match(substr($0, pos), /^<<-?[[:space:]]*[\\"'\'']?[A-Za-z_][A-Za-z0-9_]*/)) {
        tag = substr($0, pos, RLENGTH)
        dash = (tag ~ /^<<-/)
        sub(/^<<-?[[:space:]]*/, "", tag)
        gsub(/[\\"'\'']/, "", tag)
        hd = 1
        nbuf = 0
        print
        next
      }
      print
    }
    END {
      if (hd) for (j = 0; j < nbuf; j++) print buf[j]
    }
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

  # A quoted literal may itself span a newline, and the per-line blanking below
  # would then see an unbalanced quote on each half and scan the second half as
  # syntax — a benign `echo` of a multi-line string that merely MENTIONS a state
  # path blocked. Join the newlines INSIDE such a span first (lossless: a newline
  # inside quotes never separates two commands), leaving every command-separating
  # newline for the pass below. Contract: lib/write-vectors.sh.
  JOINED=$(_geniro_join_quoted_newlines "$JOINED")

  # A variable carries its value into the command the shell runs, so a guard
  # matching literal tokens misses every operand and every command word that
  # arrived through one. Substitute assigned literals back in before matching.
  # Contract: lib/write-vectors.sh §F.
  JOINED=$(_geniro_wv_expand_assignments "$JOINED")

  # Quoted string literals are data (`echo "see > .geniro/x"` writes nothing).
  # Scrubbed per LINE, newlines INTACT: a newline separates two commands exactly
  # as `;` does, and collapsing it to a space first put a canonical multi-line
  # `atomic_state_write … <<EOF` call and a raw redirect on the following line
  # into ONE segment, which the per-segment helper exemption then cleared
  # wholesale. The span EXCLUDES ; & | (mirrors block-dangerous-git.sh's own
  # quoted-literal blanking pass, minus its unquote pass — unquoting a whitespace-free helper
  # NAME here would re-expose a quoted MENTION, e.g. `echo "atomic_state_write"
  # > .geniro/x`, as a real command word, which is exactly what the blank below
  # this comment exists to prevent) — otherwise two ordinary prose apostrophes
  # straddling a `;` pair into one "literal" and blank the real command sitting
  # between them.
  # Recover words the shell would pass but the blanking below would erase — a
  # quoted or backslash-escaped state path (`echo x > '.geniro/.../state.md'`)
  # is one shell word, so blanking it as data lets the write through.
  # Contract: lib/write-vectors.sh §E.
  JOINED=$(_geniro_wv_unquote_words "$JOINED")

  JOINED=$(printf '%s\n' "$JOINED" | sed -E "s/'[^';&|]*'/ /g; s/\"[^\";&|]*\"/ /g")
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
  #
  # The name must be the segment's FIRST command word, not merely present in it.
  # An UNQUOTED mention anywhere (`echo atomic_state_write > <state path>`,
  # `printf %s atomic_state_write > <state path>`) survives the quote scrub the
  # sentence above relies on, and whitelisted the whole segment INCLUDING its raw
  # redirect. `<var>=<value> helper …` is admitted because that assignment
  # prefix is part of the same simple command.
  MASKED=""
  # awk, not a sed REPLACEMENT `\n`: the sed `\n`-as-newline spelling is a GNU
  # extension some BSD sed builds do not honor in the replacement text (they
  # emit the two literal characters `\` `n` instead), which collapses this
  # split into a single segment — and a single segment lets a LEADING
  # `atomic_state_write` whitelist a raw redirect later in the same command
  # (`atomic_state_write x; echo y > .geniro/z/state.md`). awk's own string
  # literals interpret `\n` as newline portably, so building the output with
  # one is not exposed to the same ambiguity.
  # A `|` immediately following a `>` with NO character between them is the
  # noclobber-override operator (`>|`), not a pipe — splitting it here orphans
  # the `>` from its own operand and vector 1's redirect extraction (which
  # already matches `>{1,2}\|?`) never sees it. `prevc` tracks the ORIGINAL
  # character immediately before, so a real pipe after a filename (`cmd >file
  # |grep`) still splits — only the two adjacent operator characters don't.
  _sep_split=$(printf '%s\n' "$JOINED" | awk '
    {
      n = length($0); out = ""; i = 1; prevc = ""
      while (i <= n) {
        c2 = substr($0, i, 2)
        if (c2 == "||" || c2 == "&&") { out = out "\n"; i += 2; prevc = "\n"; continue }
        c = substr($0, i, 1)
        if (c == "|" && prevc == ">") { out = out c; i++; prevc = c; continue }
        if (c == ";" || c == "&" || c == "|") { out = out "\n"; i++; prevc = "\n"; continue }
        out = out c; i++; prevc = c
      }
      print out
    }
  ')
  while IFS= read -r _seg; do
    if printf '%s' "$_seg" | grep -qE '^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(atomic_state_write|atomic_state_append)([[:space:]]|$)'; then
      # Only the helper's own command word (+ optional VAR= prefixes) and its
      # first operand are trusted — NOT the whole segment. A shell redirect
      # riding on the SAME simple command (`atomic_state_write x > <state>`,
      # `… >> <state>`) is not separated from the helper call by `; & |`, so
      # dropping the entire segment here silently exempted that redirect's
      # own target too. Strip just the recognized prefix and keep whatever
      # follows (a trailing `>`/`>>`/`>|` redirect, or nothing for a genuine
      # bare/heredoc invocation) for the extraction vectors below.
      _seg=$(printf '%s' "$_seg" | sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(atomic_state_write|atomic_state_append)[[:space:]]+[^[:space:]]+[[:space:]]*//')
      [ -z "$_seg" ] && continue
    fi
    MASKED="${MASKED}${_seg}
"
  done <<< "$_sep_split"
  ONELINE="$MASKED"

  # A `cd`/`pushd` INTO the guarded tree hides every later write operand from
  # the candidate extraction below: `cd .geniro && echo x > knowledge/learnings.jsonl`
  # (or `pushd .geniro && …`) spells no `.geniro` path in the redirect target
  # at all, yet writes exactly where `echo x > .geniro/knowledge/learnings.jsonl`
  # would. Derive that prefix via the single-sourced helper (contract:
  # lib/write-vectors.sh's `_geniro_wv_cd_prefix`, shared with
  # block-geniro-deletion.sh and file-protection.sh so the derivation cannot
  # drift between them again); add_candidate below re-prefixes each relative
  # operand with it. Each line of $ONELINE is already one separator-bounded
  # simple command (the split above), so — unlike the other guards' PADDED/
  # ONELINE single-string form — no further span extraction is needed here.
  CD_PREFIX=$(_geniro_wv_cd_prefix "$ONELINE" ".geniro")

  CANDIDATES=""
  add_candidate() {
    local c="$1"
    c="${c#\"}"; c="${c%\"}"
    c="${c#\'}"; c="${c%\'}"
    if [ -n "$c" ]; then
      CANDIDATES="${CANDIDATES}${c}
"
      # Re-prefix a plausible RELATIVE operand with the last `cd` target so a
      # write that only resolves into .geniro/ via the shell's cwd still hits
      # matches_state_path below. Not re-prefixed: an already-absolute/home/
      # variable operand, and an operand that already carries a .geniro
      # segment (needs no help, and stops this from recursing).
      if [ -n "$CD_PREFIX" ]; then
        case "$c" in
          -*|/*|'~'*|'$'*) : ;;
          *)
            case "/$c" in
              */.geniro/*|*/.geniro) : ;;
              *) CANDIDATES="${CANDIDATES}${CD_PREFIX}/${c}
" ;;
            esac
            ;;
        esac
      fi
    fi
  }

  # Redirection tokens riding on the SAME simple command (2>/dev/null, 2>&1,
  # >&2, >/dev/null, a spaced "2> file", a bare "<" whose target is the next
  # token) are not a positional operand of cp/mv/install/rsync/ln/sponge/ed/ex
  # — without stripping them first, each vector's "last non-flag token is the
  # destination" scan below picks up the redirect's own target (or the bare
  # operator itself) instead of the command's real destination.
  # `2>/dev/null` is the single most common shell idiom, so this is reachable
  # by accident, not only adversarially. A bare operator with NO target of its
  # own attached (an exact `>`, `>>`, `<`, `2>`, …) also consumes the token
  # that follows it, since that token IS the redirect's target, not a
  # positional argument of the command.
  _geniro_strip_redir_span() {
    local span="$1" out="" tok skip=0
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      if [ "$skip" = "1" ]; then skip=0; continue; fi
      case "$tok" in
        '>'|'>>'|'>|'|'<'|'<<'|'>&'|'&>'|[0-9]'>'|[0-9]'>>'|[0-9]'>|'|[0-9]'<'|[0-9]'<<'|[0-9]'>&'|[0-9]'&>')
          skip=1
          continue
          ;;
        [0-9]'>'*|[0-9]'<'*|'>'*|'<'*|'&>'*)
          continue
          ;;
      esac
      out="${out}${tok} "
    done
    set +f
    printf '%s' "$out"
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
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])tee[[:space:]]+[^|;&]*' || true)"

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
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])sed[[:space:]]+[^|;&]*' || true)"

  # 3b) In-place awk: GNU awk's `-i inplace` extension rewrites each FILE
  #     argument the same way sed -i does above. `-i` and `inplace` are TWO
  #     tokens (unlike sed's attached-suffix `-i.bak`), so the literal word
  #     `inplace` is skipped as the flag's VALUE, not read as a file argument.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    printf '%s' "$span" | grep -qE '[[:space:]]-i[[:space:]]+inplace([[:space:].]|$)' || continue
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      case "$tok" in
        *awk|-*|inplace) continue ;;
      esac
      add_candidate "$tok"
    done
    set +f
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])(awk|gawk|mawk)[[:space:]]+[^|;&]*' || true)"

  # 4) mv: only the DESTINATION (last non-flag token) is a write. An mv whose
  #    SOURCE is itself under .geniro/ is a housekeeping rename of content
  #    already written through the helper (version-it, pre-edit snapshot,
  #    revert) — an atomic filesystem rename, not a torn-write risk — so the
  #    destination is skipped. A source OUTSIDE .geniro/ keeps blocking: that is
  #    a content write into the tree around the helper. `cp` does NOT share
  #    this carve-out (split out below as 4b): a copy always performs a fresh
  #    open+truncate+write at the destination regardless of where its source
  #    lives, so `cp .geniro/snap.md .geniro/planning/t/state.md` is exactly
  #    the torn write this guard exists to prevent.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    span=$(_geniro_strip_redir_span "$span")
    [ -z "$span" ] && continue
    last=""
    first=""
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      case "$tok" in mv|*/mv|-*) continue ;; esac
      [ -z "$first" ] && first="$tok"
      last="$tok"
    done
    set +f
    # A source containing a `..` segment only LOOKS like it is already inside the
    # tree — `.geniro/../evil.md` resolves outside it, which is the content write
    # the carve-out exists to keep blocking. Reject it before the glob, mirroring
    # the `..` rejection in block-geniro-deletion.sh's check_delete_arg.
    # `.geniro` must be a whole path SEGMENT, not a suffix of one: `*.geniro/*`
    # also matches `foo.geniro/a`, an ordinary directory outside the tree, and
    # that carve-out then skipped the destination check entirely.
    case "/$first/" in
      */../*) : ;;
      */.geniro/*) continue ;;
    esac
    case "$last" in ""|mv|*/mv) : ;; *) add_candidate "$last" ;; esac
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])mv[[:space:]]+[^|;&]*' || true)"

  # 4b) cp: only the DESTINATION (last non-flag token) is a write — no
  #     source-under-.geniro/ carve-out (see 4 above): a copy truncates and
  #     rewrites the destination exactly as any other cp does, no matter where
  #     its source lives.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    span=$(_geniro_strip_redir_span "$span")
    [ -z "$span" ] && continue
    last=""
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      case "$tok" in cp|*/cp|-*) continue ;; esac
      last="$tok"
    done
    set +f
    case "$last" in ""|cp|*/cp) : ;; *) add_candidate "$last" ;; esac
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])cp[[:space:]]+[^|;&]*' || true)"

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
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])truncate[[:space:]]+[^|;&]*' || true)"

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
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])shred[[:space:]]+[^|;&]*' || true)"

  # 8) install / rsync SRC... DEST — the DEST (last non-flag token) is written,
  #    like cp/mv; an install `-t DIR` / `--target-directory DIR` writes into DIR.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    span=$(_geniro_strip_redir_span "$span")
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
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])(install|rsync)[[:space:]]+[^|;&]*' || true)"

  # 9) ln -f ... LINK — the LINK (last non-flag token) is created/overwritten
  #    when -f/--force is present (without -f, ln refuses to clobber).
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    span=$(_geniro_strip_redir_span "$span")
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
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])ln[[:space:]]+[^|;&]*' || true)"

  # 10) sponge / ed / ex / patch — ordinary in-place-edit tools with no
  #     redirect, tee, sed -i, cp/mv or interpreter op for the vectors above to
  #     see:
  #       sponge FILE        — soaks stdin, writes FILE (last non-flag token)
  #       ed FILE            — line editor; FILE is written by a script fed on
  #                            stdin (last non-flag token)
  #       ex -sc 'wq' FILE   — ex/vi non-interactive mode; FILE is the buffer
  #                            (last non-flag token)
  #       patch FILE < diff  — rewrites FILE from a unified diff; FILE is the
  #                            FIRST positional (a second positional would be
  #                            the patch file itself, which is read-only)
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    span=$(_geniro_strip_redir_span "$span")
    [ -z "$span" ] && continue
    last=""
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      case "$tok" in sponge|*/sponge|ed|*/ed|ex|*/ex|-*) continue ;; esac
      last="$tok"
    done
    set +f
    case "$last" in ""|sponge|*/sponge|ed|*/ed|ex|*/ex) : ;; *) add_candidate "$last" ;; esac
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])(sponge|ed|ex)[[:space:]]+[^|;&]*' || true)"

  while IFS= read -r span; do
    [ -z "$span" ] && continue
    first=""
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      case "$tok" in patch|*/patch|-*) continue ;; esac
      first="$tok"
      break
    done
    set +f
    [ -n "$first" ] && add_candidate "$first"
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])patch[[:space:]]+[^|;&]*' || true)"

  # 11) curl -o/--output / wget -O/--output-document — a download landing
  #     directly on a protected/state/production path, no redirect needed.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    set -f
    take_next=0
    # shellcheck disable=SC2086
    for tok in $span; do
      if [ "$take_next" = "1" ]; then add_candidate "$tok"; take_next=0; continue; fi
      case "$tok" in
        -o|--output) take_next=1; continue ;;
        --output=*) add_candidate "${tok#--output=}"; continue ;;
      esac
    done
    set +f
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])curl[[:space:]]+[^|;&]*' || true)"

  while IFS= read -r span; do
    [ -z "$span" ] && continue
    set -f
    take_next=0
    # shellcheck disable=SC2086
    for tok in $span; do
      if [ "$take_next" = "1" ]; then add_candidate "$tok"; take_next=0; continue; fi
      case "$tok" in
        -O|--output-document) take_next=1; continue ;;
        --output-document=*) add_candidate "${tok#--output-document=}"; continue ;;
      esac
    done
    set +f
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])wget[[:space:]]+[^|;&]*' || true)"

  # 12) Interpreter-mediated writes: a scripting runtime opening a state
  #     file for writing, a pathlib Path(...) write, an interpreter copy/rename
  #     landing on one, or an awk program redirecting `print` into one. Vectors
  #     1-11 read $ONELINE, whose heredoc bodies and quoted literals were blanked
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
    check_safety_json_write "$cand"
    # The broad grant applies to every OTHER candidate once the narrower
    # safety.json gate above has had its say for THIS one — it must not skip
    # that gate itself (see the comment on ALLOWED's earlier, now-removed
    # early exit). Per-candidate rather than a single exit before the loop:
    # a multi-target command (`cp a b .geniro/safety.json`) can carry a
    # safety.json write alongside ordinary ones, and every candidate needs
    # its own check_safety_json_write call regardless of this grant.
    case " $ALLOWED " in
      *" enforce-state-helper "*) continue ;;
    esac
    # .geniro/state/tdd/ is a documented exception (own mktemp + mv procedure).
    # A `..` segment makes that prefix a lie — `.geniro/state/tdd/../../
    # planning/foo/state.md` contains the substring while resolving to a
    # canonical state file outside it. Reject the traversal (fall through to
    # matches_state_path below, no exemption) before the substring test even
    # runs, mirroring enforce-tdd-order.sh's is_non_production_target.
    case "/$cand/" in
      */../*) ;;
      *.geniro/state/tdd/*) continue ;;
    esac
    if matches_state_path "$cand"; then
      emit_state_helper_decision "$cand"
    fi
  done <<< "$CANDIDATES"
  exit 0
fi

# ---- Edit/Write/MultiEdit branch ----
# FILE_PATH was already extracted above (needed there for the malformed-payload check).
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

check_safety_json_write "$FILE_PATH"

# The broad grant is applied HERE, after the narrower safety.json gate above
# has already had its say — see the comment on ALLOWED's earlier, now-removed
# early exit.
case " $ALLOWED " in
  *" enforce-state-helper "*) exit 0 ;;
esac

# A `..` segment makes the .geniro/state/tdd/ prefix a lie (see the Bash-branch
# comment above); reject the traversal before the exemption is consulted.
case "/$FILE_PATH/" in
  */../*) ;;
  *.geniro/state/tdd/*) exit 0 ;;
esac

if ! matches_state_path "$FILE_PATH"; then
  exit 0
fi

emit_state_helper_decision "$FILE_PATH"
