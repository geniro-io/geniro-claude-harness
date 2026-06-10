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
# redirection (>, >>, >|), tee, in-place sed (-i), cp/mv destinations, dd of=.
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
  #   reports / screenshots, no frontmatter, deleted at Phase Ship:
  #     .kr-out.md, .ce-out.md, .tr-out.md, .adversarial-out.md, .research-out.md
  #     .research-<facet>.md (per-facet research outputs from /plan Phase 1)
  #     notes.md (ad-hoc scratch under <task-dir>/)
  #     playwright-verify.png (pre-Ship visual verification screenshot)
  if echo "$p" | grep -qE '\.lock$|/\.fingerprint\.json$|\.tmp(\.[^/]+)?$|\.swp$|~$|/\.(kr|ce|tr|adversarial|research)-out\.md$|/\.research-[^/]+\.md$|/notes\.md$|/playwright-verify\.png$'; then
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
  # Sanctioned helpers write via their own mktemp + mv — allow the command.
  if printf '%s' "$COMMAND" | grep -qE '\b(atomic_state_write|atomic_state_append)\b'; then
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
    match($0, /<<-?["'\'']?[A-Za-z_][A-Za-z0-9_]*/) {
      tag = substr($0, RSTART, RLENGTH)
      dash = (tag ~ /^<<-/)
      sub(/^<<-?/, "", tag)
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
    printf '%s' "$span" | grep -qE '[[:space:]]-i' || continue
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
