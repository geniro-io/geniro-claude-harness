#!/usr/bin/env bash
# enforce-tdd-order.sh — PreToolUse Edit|Write|MultiEdit|NotebookEdit AND Bash, HARD-BLOCK (exit 2).
# When .geniro/state/tdd/state-<slug>.md shows phase=RED, blocks production-code writes.
#
# Edit/Write/MultiEdit branch: checks .tool_input.file_path.
# Bash branch: catches shell-side authoring the file-tool matcher never sees —
# a `cat > app.js <<EOF`, `printf ... > app.py`, `tee app.ts`, `sed -i`, `cp`/`mv`,
# or `dd of=` write. It extracts the write TARGET the same way file-protection.sh
# does and runs the SAME test-vs-production classification on it, so a heredoc into
# production code during RED is gated exactly like a direct Write. Pseudo-devices
# (/dev/*) and .geniro/ state paths are not production source and are skipped — the
# TDD orchestrator writes its own RED-phase state file under .geniro/state/tdd/ via
# a Bash mktemp + mv (tdd-cycle.md §State file contract), and blocking that would
# deadlock the cycle.
#
# Per skills/_shared/tdd-cycle.md and skills/_shared/within-skill-state-handoff.md (slug rules).
# Bypass: .geniro/safety.json allow_patterns: ["tdd-order"].
set -euo pipefail

# Fail open but LOUDLY if jq is missing: without it the hook cannot parse tool
# input, and a silent exit 0 would leave the user believing the gate is active.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"Geniro hook inactive: jq not found on PATH, so the TDD-order gate is NOT running. Install jq to restore it."}\n'
  exit 0
fi

# Consume stdin - REQUIRED first step
INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# Edit-class tools carry a file path; Bash carries a command. Resolve whichever
# is present and short-circuit when this call writes nothing the gate can see.
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null || echo "")
COMMAND=""
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  if [ -z "$COMMAND" ]; then
    exit 0
  fi
elif [ -z "$FILE_PATH" ]; then
  # No file path found, allow execution
  exit 0
fi

# Compute branch slug per skills/_shared/within-skill-state-handoff.md § Slug rules.
# Single-sourced in lib/branch-slug.sh; the inline fallback keeps the hook working
# on a vendored install without lib/. Producer and consumer must derive the same
# slug or a >60-char branch yields a slug no skill ever wrote and the gate misses.
_geniro_slug_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/branch-slug.sh"
if [ -f "$_geniro_slug_helper" ]; then
  # shellcheck source=/dev/null
  source "$_geniro_slug_helper" 2>/dev/null || true
fi
if ! command -v _geniro_branch_slug >/dev/null 2>&1; then
  _geniro_branch_slug() {
    local b="${1:-}"
    if [ -z "$b" ]; then
      b="$(git branch --show-current 2>/dev/null || true)"
      [ -z "$b" ] && b="detached-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    fi
    local s
    s="$(printf '%s' "$b" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9]+#-#g; s#^-+##; s#-+$##' || true)"
    s="${s:0:60}"
    printf '%s' "${s%-}"
  }
fi
slug="$(_geniro_branch_slug)"

# Resolve the nearest project root (the directory holding .geniro/) by walking
# up from cwd, so the state lookup still works when the session cwd is a
# subdirectory of the project. TDD state is task-local: a linked worktree keeps
# its OWN .geniro/state/tdd/, so this deliberately does NOT redirect to the
# primary worktree (unlike lib/repo-root.sh, which serves cross-session memory
# writers).
_tdd_local_root() {
  local d="$PWD"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -d "$d/.geniro" ]; then printf '%s' "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD"
}
ROOT="$(_tdd_local_root)"

STATE_FILE="${ROOT}/.geniro/state/tdd/state-${slug}.md"

# If state file doesn't exist, skill hasn't opted in to TDD — no surprise blocks
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Bypass: read .geniro/safety.json walking up from cwd
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
  *" tdd-order "*) exit 0 ;;
esac

# Parse the `## phase` section of the state file. Markdown format:
#   ## phase
#   RED
#
# We want the first non-blank line after `## phase` (terminated by next `## ` header or EOF).
PHASE=$(awk '
  /^##[[:space:]]+phase[[:space:]]*$/ { in_phase=1; next }
  in_phase && /^##[[:space:]]/         { in_phase=0 }
  in_phase && NF                       { print; exit }
' "$STATE_FILE" 2>/dev/null | tr -d '[:space:]' || echo "")

# If phase is not RED (i.e., GREEN, REFACTOR, IDLE, or empty/missing) → allow
if [ "$PHASE" != "RED" ]; then
  exit 0
fi

# Phase is RED — check whether file_path matches a test-file pattern.
# Patterns:
#   - any path containing "test" as a directory or filename component
#   - *.spec.* (Jest/Vitest)
#   - *_test.go (Go)
#   - tests/** or test/** prefix
#   - __tests__/** (Jest)
is_test_file() {
  local p="$1"
  # Lowercase compare for case-insensitive directory/filename matching
  local lp
  lp=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')

  # __tests__ directory (anywhere in path)
  case "$lp" in
    *"/__tests__/"*|"__tests__/"*) return 0 ;;
  esac

  # tests/ or test/ as directory anywhere in path
  case "$lp" in
    *"/tests/"*|*"/test/"*|"tests/"*|"test/"*) return 0 ;;
  esac

  # *.spec.* (e.g., foo.spec.ts, foo.spec.tsx, foo.spec.js)
  case "$lp" in
    *.spec.*) return 0 ;;
  esac

  # *_test.go (Go convention)
  case "$lp" in
    *_test.go) return 0 ;;
  esac

  # Filename follows a test-naming convention (anchored, so production files
  # that merely contain the substring "test" — latest_config.py, contestant.ts,
  # testimonials.tsx — are NOT mistaken for tests during RED). Tests laid out
  # under a test/ or __tests__/ directory are already matched above.
  local base="${lp##*/}"
  case "$base" in
    test_*|test-*|*-test.*|*_test.*|*.test.*) return 0 ;;
  esac

  return 1
}

# A target that is not production source: a pseudo-device, or a path under
# .geniro/ (task state / scratch — the TDD orchestrator's own RED-phase state
# write lands here). The gate exists for production-code writes, so these skip.
is_non_production_target() {
  case "$1" in
    /dev/*) return 0 ;;
    *.geniro/*) return 0 ;;
    *) return 1 ;;
  esac
}

block_production() {
  local target="$1"
  cat >&2 <<EOF
[tdd-order] TDD cycle in RED phase — author the failing test BEFORE production code.
See \${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md.
State file: ${STATE_FILE}
Target was: ${target}
Bypass: add "tdd-order" to .geniro/safety.json allow_patterns.
EOF
  exit 2
}

if [ "$TOOL_NAME" = "Bash" ]; then
  # ---- Bash branch: extract write targets exactly as file-protection.sh does ----
  # Heredoc bodies are DATA, not shell syntax — a `> app.js` inside one is text.
  # Drop body lines (between <<TAG / <<-TAG / <<'TAG' and the closing TAG) before
  # any extraction; the line carrying the << operator is kept, so `cat <<EOF > app.js`
  # still yields its redirect target.
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

  # Quoted string literals are data (`echo "writing app.js"` writes nothing).
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

  # 1) Redirection targets: > file, >> file, >| file. fd-dups (>&2) never yield a
  #    target; 2>/dev/null lands on /dev/null, skipped as non-production below.
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

  # 3) In-place sed: file arguments of a `sed -i` span are overwritten. An
  #    UNQUOTED script token (s/.../.../, y|...|...) is skipped — it is sed code,
  #    not a path; quoted scripts were already blanked by the quote scrub above.
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

  # 4) cp/mv: only the DESTINATION (last non-flag token) is a write — copying
  #    FROM a file is a read and stays allowed.
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    last=""
    set -f
    # shellcheck disable=SC2086
    for tok in $span; do
      case "$tok" in -*) continue ;; esac
      last="$tok"
    done
    set +f
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
    if is_non_production_target "$cand"; then continue; fi
    if ! is_test_file "$cand"; then
      block_production "$cand"
    fi
  done <<< "$CANDIDATES"
  exit 0
fi

# ---- Edit/Write/MultiEdit/NotebookEdit branch ----
if is_test_file "$FILE_PATH"; then
  # Test files are allowed — this is the file we're supposed to be writing in RED phase
  exit 0
fi

# Production-code edit attempted during RED phase → hard-block
block_production "$FILE_PATH"
