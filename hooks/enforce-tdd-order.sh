#!/usr/bin/env bash
# enforce-tdd-order.sh — PreToolUse Edit|Write|MultiEdit|NotebookEdit AND Bash, HARD-BLOCK (exit 2).
# When .geniro/state/tdd/state-<slug>.md shows phase=RED, blocks production-code writes.
#
# Edit/Write/MultiEdit branch: checks .tool_input.file_path.
# Bash branch: catches shell-side authoring the file-tool matcher never sees —
# a `cat > app.js <<EOF`, `printf ... > app.py`, `tee app.ts`, `sed -i`, `cp`/`mv`,
# `dd of=`, or interpreter-mediated (`python3 -c "open('app.js','w')…"`,
# `awk 'BEGIN{print s > "app.js"}'`) write.
# It extracts the write TARGET the same way file-protection.sh
# does and runs the SAME test-vs-production classification on it, so a heredoc into
# production code during RED is gated exactly like a direct Write. A write hidden
# behind shell indirection (`sh -c "..."`, `eval "..."`, a quoted program piped to
# a shell, a heredoc body fed to one, a process substitution, an interpreter
# shelling out) is extracted before the quote scrub and
# the gate re-runs on that payload. Pseudo-devices (/dev/*), .geniro/ state paths,
# temp directories and generated build-output directories are not production
# source and are skipped — the TDD orchestrator writes its own RED-phase state
# file under .geniro/state/tdd/ via a Bash mktemp + mv (tdd-cycle.md §State file
# contract), and capturing the failing test's output into a temp file is the work
# RED exists to do; blocking either would deadlock the cycle.
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
  # allow_patterns entries name exact pattern IDs. The membership test below is a
  # substring probe over the space-joined list, so a single entry that CARRIES
  # whitespace ("harmless write-env alsoharmless") would silently enable every ID
  # spelled inside it. Reject those at load rather than weaken the probe.
  ALLOWED=$(jq -r '.allow_patterns[]? | select(type == "string" and (test("[[:space:]]") | not))' "$SAFETY_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
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

# A target that is not production source: a pseudo-device, a path under .geniro/
# (task state / scratch — the TDD orchestrator's own RED-phase state write lands
# here), a temp-directory path, or a generated build-output directory. The gate
# exists for production-code writes.
#
# The temp and build sets are load-bearing, not conveniences: RED is exactly the
# phase that RUNS the failing test, and capturing its output
# (`npm test > /tmp/out.log`, `git diff > /tmp/d.patch`,
# `jq . package.json > /tmp/pkg.json`) is a redirect whose target is not
# test-shaped. Without them the gate hard-blocks the work it is supposed to be
# waiting for. The temp set is scoped to paths OUTSIDE $ROOT — see below.
is_non_production_target() {
  case "$1" in
    /dev/*) return 0 ;;
    *.geniro/*) return 0 ;;
    # Generated build output — never hand-authored production source.
    */node_modules/*|node_modules/*) return 0 ;;
    */dist/*|dist/*|*/build/*|build/*) return 0 ;;
    */target/*|target/*|*/coverage/*|coverage/*|*/.next/*|.next/*) return 0 ;;
  esac

  # Scratch OUTSIDE the project tree. The inside-the-project test comes FIRST and
  # is load-bearing: on macOS `mktemp -d` hands out /var/folders/… paths that a
  # whole checkout can legitimately live under, so exempting that prefix
  # unconditionally would disarm the gate for any project rooted there.
  case "$1" in
    "$ROOT"/*) return 1 ;;
    /tmp/*|/private/tmp/*|/var/tmp/*|/var/folders/*) return 0 ;;
    # The UNEXPANDED spelling of $TMPDIR: the gate reads command TEXT, so a
    # portable `npm test > $TMPDIR/out.log` arrives with the variable intact.
    '$TMPDIR'*|'${TMPDIR}'*) return 0 ;;
  esac
  # A custom $TMPDIR (macOS points it at /var/folders/…, already covered above,
  # but the variable is what a portable script actually writes through).
  if [ -n "${TMPDIR:-}" ]; then
    case "$1" in "${TMPDIR%/}"/*) return 0 ;; esac
  fi
  return 1
}

# Shell indirection (`sh -c "<payload>"`, `eval "<payload>"`, a program piped to
# a shell, a heredoc fed to one, a process substitution, an interpreter shelling
# out) and interpreter-mediated writes are
# single-sourced in lib/write-vectors.sh. Each inline fallback keeps the gate
# whole on a vendored install shipping hooks/ without lib/ — a missing helper
# must never make this gate fail open — and is a VERBATIM copy of the canonical
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
  local _m _pl _lit

  # ONE shell-word matcher for every arm. The wrapper prefix consumes its own
  # flags, `VAR=value` assignments, durations and `{}` placeholders — never an
  # arbitrary word, which would let any two-word command read as a shell.
  local _wv_pfx='((sudo|doas|command|env|exec|nohup|nice|timeout|stdbuf|ionice|xargs)([[:space:]]+(-[^[:space:];|&<>]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];|&<>]*|[0-9]+[smhd]?|[{}]+))*[[:space:]]+)*'
  local _wv_shq='["'\'']?'
  local _wv_sh="${_wv_pfx}${_wv_shq}"'([^[:space:];|&<>"'\'']*/)?(sh|bash|zsh|dash|ksh|ash)'"${_wv_shq}"
  # One quoted literal; and the payload operand form, which may also be bare.
  local _wv_lit='("[^"]*"|'\''[^'\'']*'\'')'
  local _wv_arg='("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)'

  # Arm 1 — interpreter `-c` payload.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E 's/^.*[[:space:]]-[A-Za-z]*c[A-Za-z]*[[:space:]]+//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_sh}"'[[:space:]]+-[A-Za-z]*c[A-Za-z]*[[:space:]]+'"${_wv_arg}" 2>/dev/null || true)"

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
  done <<< "$(printf '%s\n' "$cmd" | grep -oE "${_wv_lit}"'[^|"'\'']*\|[[:space:]]*'"${_wv_sh}"'([[:space:]]+-[a-bd-zA-BD-Z0-9]+)*[[:space:]]*($|[;&|])' 2>/dev/null || true)"

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
      match($0, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z0-9_]*/) {
        tag = substr($0, RSTART, RLENGTH)
        dash = (tag ~ /^<<-/)
        sub(/^<<-?[[:space:]]*/, "", tag)
        gsub(/["'\'']/, "", tag)
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
  if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(python[0-9.]*|node|bun|bunx|deno|tsx|perl|ruby|php|lua|tclsh|Rscript)([[:space:]]|$)'; then
    # A dot is allowed before the op name because that is how the ops are normally
    # reached (`require('child_process').execSync(…)`); the cost is that a JS
    # `re.exec("s")` also yields its argument, which re-scans as an inert word.
    local _wv_shellout='(os\.(system|popen)|subprocess\.[A-Za-z_]+|Kernel\.system|IO\.popen|Open3\.[a-z_]+|exec(Sync|FileSync)?|system|popen|shell_exec|passthru|proc_open)'
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^[^(]*\([[:space:]]*//')
      _pl="${_pl#\\}"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      _pl="${_pl%\\}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_shellout}"'[[:space:]]*\([[:space:]]*\\?'"${_wv_lit}" 2>/dev/null || true)"

    # Ruby's backtick literal is the same shell-out with no call syntax at all.
    # Narrowed further to a `ruby` command word: elsewhere a backtick span is
    # ordinary shell command substitution, already visible to the guards as
    # syntax, and re-extracting it would only add noise.
    if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)ruby([[:space:]]|$)'; then
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
  # Runtime roster. bun and tsx implement node:fs verbatim and deno ships its own
  # Deno.* file API, so a roster frozen at the 2019 set lets one word bypass the
  # whole channel.
  if ! printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(python[0-9.]*|node|bun|bunx|deno|tsx|perl|ruby|php|lua|tclsh|Rscript|awk|gawk|mawk)([[:space:]]|$)'; then
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
  # `writeTextFile` covers Deno.writeTextFile(Sync).
  local _wops_first='((writeFile|appendFile|createWriteStream|outputFile|writeTextFile)(Sync)?|file_put_contents|File\.write|IO\.write)'
  # Copy/rename: the SECOND argument is the target. This is the interpreter
  # spelling of a cp/mv DESTINATION, which the shell-side cp/mv vector in every
  # calling guard already treats as a write — without it the same clobber walks
  # past that guard just by being written in Python or Node.
  local _wops_second='(shutil\.copy[A-Za-z0-9_]*|shutil\.move|os\.rename|os\.replace|File\.rename|FileUtils\.(cp|mv|copy|move)|(copyFile|rename|cp)(Sync)?)'
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

  # Re-run THIS gate on each extracted payload (unblanked); a block inside
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

  # 10) Interpreter-mediated writes: a scripting runtime opening a file for
  #     writing, or an awk program redirecting `print` into one. Vectors 1-9 read
  #     $ONELINE, whose heredoc bodies and quoted literals were blanked as data —
  #     and an interpreter's file write is not shell syntax anywhere, so
  #     `python3 -c "open('src/app.js','w').write(s)"` authored production code
  #     during RED completely unchecked. Contract: lib/write-vectors.sh.
  #
  #     Only targets the scan resolves to a literal are gated. This gate classifies
  #     EVERY path as production unless it looks like a test, so falling back to
  #     the path-shaped tokens of a command whose target is a variable would block
  #     on an incidental filename — and a false RED-phase block stalls the cycle
  #     the same way a missed write corrupts it.
  _iw_unresolved=0
  _iw_targets=$(_geniro_interp_write_targets "$COMMAND") || _iw_unresolved=1
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    add_candidate "$tok"
  done <<< "$_iw_targets"

  # 11) In-place interpreter edit: `perl -pi -e 's/…/…/' src/app.js`,
  #     `ruby -i -pe … src/app.js`. The helper reports rc=10 for these because the
  #     target is not a literal inside the SCRIPT — but it is the file operand on
  #     the command line, resolvable exactly as vector 3 resolves `sed -i`. That
  #     is the one rc=10 shape this gate can act on without guessing, so it is
  #     resolved here rather than discarded: without it the interpreter spelling
  #     of an in-place edit rewrites production source during RED while the `sed`
  #     spelling is blocked. An UNQUOTED script token (s/…/…/, y|…|…) is skipped
  #     as sed-style code, not a path; quoted scripts the scrub already blanked.
  if [ "$_iw_unresolved" = "1" ]; then
    while IFS= read -r span; do
      [ -z "$span" ] && continue
      printf '%s' "$span" | grep -qE '[[:space:]]-[a-zA-Z]*i([[:space:].]|$)' || continue
      set -f
      # shellcheck disable=SC2086
      for tok in $span; do
        case "$tok" in
          perl|ruby|*/perl|*/ruby|-*) continue ;;
          s[!a-zA-Z0-9]*|y[!a-zA-Z0-9]*) continue ;;
        esac
        add_candidate "$tok"
      done
      set +f
    done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[|;&[:space:]])(perl|ruby)[[:space:]]+[^|;&]*' || true)"
  fi

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
