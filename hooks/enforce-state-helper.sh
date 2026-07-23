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
# and interpreter-mediated writes (python/node/perl/ruby opening a state file
# for writing, including from a heredoc body).
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
  ALLOWED=$(jq -r '.allow_patterns[]? // empty' "$SAFETY_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
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

  JOINED="${SCRUBBED//\\$'\n'/ }"
  ONELINE="${JOINED//$'\n'/ }"

  # Quoted string literals are data (`echo "see > .geniro/x"` writes nothing).
  ONELINE=$(printf '%s' "$ONELINE" | sed -E "s/'[^']*'/ /g; s/\"[^\"]*\"/ /g")
  # Strip trailing comments. Quotes are already blanked above, so a `#` at a
  # word boundary is a real comment — drop it so a helper name in a comment
  # can't gate the allow-check below.
  ONELINE=$(printf '%s' "$ONELINE" | sed -E 's/(^|[[:space:]])#.*$//')

  # Sanctioned helpers write via their own mktemp + mv. A helper call in ONE
  # segment must not whitelist a raw redirect in ANOTHER (`atomic_state_write x;
  # echo y > .geniro/z/state.md`), so the allow is applied PER segment: split on
  # ; && || |, drop only the segments that actually invoke a helper, and keep the
  # rest for the write-vector extraction below. This runs AFTER the quote+comment
  # scrub, so the helper name counts only as a real command word — a name in data
  # (`echo "atomic_state_write" > .geniro/x`) no longer short-circuits.
  MASKED=""
  _sep_split=$(printf '%s' "$ONELINE" | sed -E 's/(\|\||&&|[;&|])/\n/g')
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
    case "$first" in
      *.geniro/*) continue ;;
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

  # 10) Interpreter-mediated writes: python/node/perl/ruby opening a state file
  #     for writing. Vectors 1-9 read $ONELINE, whose heredoc bodies were dropped
  #     as data — and an interpreter's file write is not shell syntax anywhere, so
  #     `python3 - "$S" <<'PY' … open(p,'w').write(b) … PY` reaches the filesystem
  #     completely unchecked. This vector therefore scans the RAW $COMMAND.
  #     It fires only on the conjunction interpreter + write-mode file op + state
  #     path, so a read-only interpreter call stays allowed. When every write op
  #     names a quoted literal and none of those literals is a state path, the
  #     script provably writes elsewhere and the vector skips; a write op whose
  #     target is a variable is unresolvable here, so a state path anywhere in the
  #     command is treated as its target.
  if printf '%s' "$COMMAND" | grep -qE '(^|[|;&[:space:]]|/)(python[0-9.]*|node|perl|ruby|php)([[:space:]]|$)'; then
    _interp_eligible=0
    # Quote class tolerating a shell backslash-escape (`open(\"x\", \"w\")` is how
    # a double-quoted -c argument reaches us).
    _q="\\\\?[\"']"

    # Write op with an unresolvable (non-literal) target — the real-world shape.
    # A target is non-literal when it is not a quoted string — a bare identifier,
    # or a shell-escaped variable (`fopen(\$f, "w")` is how a variable survives a
    # double-quoted -c/-r script), so a backslash counts as non-literal unless it
    # is escaping the opening quote of a real literal.
    _nonlit="(\\\\[^\"']|[^\\\\\"'[:space:])])"
    if printf '%s' "$COMMAND" | grep -qE "open\([[:space:]]*${_nonlit}[^)]*,[[:space:]]*${_q}[waxWAX>]|open\([^)]*mode[[:space:]]*=[[:space:]]*${_q}[wax]|write_text\(|(writeFileSync|appendFileSync|createWriteStream|writeFile|file_put_contents|File\.write|File\.open|IO\.write)\([[:space:]]*${_nonlit}"; then
      _interp_eligible=1
    fi

    # In-place interpreter edit (perl -pi -e, ruby -i, perl -i.bak) — the target
    # is the file operand on the command line, which the state-path scan below
    # resolves. The flag must end at a word or suffix boundary so an unrelated
    # long option (`ruby -version`) does not read as `-i`.
    if printf '%s' "$COMMAND" | grep -qE '(^|[|;&[:space:]]|/)(perl|ruby)[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*i([[:space:].]|$)'; then
      _interp_eligible=1
    fi

    # Write op naming a quoted literal that is itself a state path.
    if [ "$_interp_eligible" = "0" ]; then
      while IFS= read -r _lit; do
        [ -z "$_lit" ] && continue
        # A quoted target carrying a shell expansion (`open('$S','w')`) only looks
        # literal. Resolve each variable against its assignment in the same
        # command — the shape that writes state files assigns the path right
        # there (`S=.geniro/planning/x/state.md; python3 …`). A variable with no
        # visible assignment stays unresolvable, so any state path in the command
        # is treated as its target.
        case "$_lit" in
          *'`'*) _interp_eligible=1; break ;;
          *'$'*)
            _resolved="$_lit"
            while IFS= read -r _ref; do
              [ -z "$_ref" ] && continue
              _vn="${_ref#\$}"; _vn="${_vn#\{}"; _vn="${_vn%\}}"
              _val=$(printf '%s' "$COMMAND" \
                | grep -oE "(^|[[:space:];&|])${_vn}=[^[:space:];&|\"']+" \
                | tail -1 | sed -E 's/^[^=]*=//' || true)
              if [ -z "$_val" ]; then _resolved=""; break; fi
              _resolved=$(printf '%s' "$_resolved" | sed "s|[\$]{${_vn}}|${_val}|g; s|[\$]${_vn}|${_val}|g")
            done <<< "$(printf '%s' "$_lit" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' || true)"
            if [ -z "$_resolved" ] || matches_state_path "$_resolved"; then
              _interp_eligible=1
              break
            fi
            ;;
          *)
            if matches_state_path "$_lit"; then
              _interp_eligible=1
              break
            fi
            ;;
        esac
      done <<< "$(
        {
          # open()/File.open() count only with a write mode in the second arg —
          # `open('<state>')` is a read and must stay allowed.
          printf '%s' "$COMMAND" \
            | grep -oE "(open|File\.open)\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*,[[:space:]]*${_q}[waxWAX>]" \
            | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
          # These write unconditionally, so their first argument is the target.
          printf '%s' "$COMMAND" \
            | grep -oE "(write_text|writeFileSync|appendFileSync|createWriteStream|writeFile|file_put_contents|File\.write|IO\.write)\([[:space:]]*${_q}[^\\\\\"']+${_q}" \
            | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
        } 2>/dev/null || true
      )"
    fi

    if [ "$_interp_eligible" = "1" ]; then
      while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        add_candidate "$tok"
      done <<< "$(printf '%s' "$COMMAND" | grep -oE "[^[:space:]\"'=(),;|&<>]*\.geniro/[^[:space:]\"'(),;|&<>]*" || true)"
    fi
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
