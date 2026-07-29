#!/usr/bin/env bash
# file-protection.sh
# PreToolUse hook for Write/Edit/MultiEdit AND Bash — blocks writes to sensitive files.
# Prevents accidental exposure of credentials and protected configurations.
#
# Edit/Write/MultiEdit branch: checks .tool_input.file_path.
# Bash branch: catches shell-side writes the file-tool matcher never sees —
# redirection (>, >>, >|), tee, in-place sed (-i), cp/mv destinations, dd of=,
# and interpreter-mediated writes (python/node/perl/ruby/php opening a protected
# file for writing, an awk program redirecting `print` into one).
# Read-only access to protected files (cat/grep/cp FROM them) stays allowed.
# Heredoc bodies and quoted string literals are scrubbed before extraction
# (they are data, not syntax) — a deliberately QUOTED redirect target
# (`> ".env"`) is therefore a documented miss, accepted to avoid hard-blocking
# benign commands that merely mention protected names in strings. The scrubbed
# positions that ARE syntax are the shell-indirection payloads — `sh -c "..."`,
# `eval "..."`, a quoted program piped to a bare shell, a heredoc body fed to
# one: all four are extracted before the scrub and this guard re-runs on each.
#
# Per-project allowlist: .geniro/safety.json (in cwd or any ancestor) can opt out
# of specific patterns by listing pattern IDs in the "allow_patterns" array.
#
# Schema:
#   {
#     "allow_patterns": ["write-env", "write-lockfile"]
#   }
#
# Pattern IDs: write-env, write-git-internal, write-lockfile, write-cert-key,
#              write-credentials, write-tfstate, write-vault

set -euo pipefail

# Fail open but LOUDLY if jq is missing — after a coarse raw scan first. A guard
# whose whole role is preventing credential clobber is the wrong one to fail
# fully open, so the highest-signal protected names still block, exactly as the
# peer data-loss guards do (block-geniro-deletion.sh, block-dangerous-git.sh).
# The scan is confined to the path/command FIELDS of the tool JSON, extracted
# textually: scanning the whole payload would read file CONTENT too, and
# `process.env` or `obj.key` in a source file would false-positive on every
# edit. No allowlist applies in this mode — reading it needs jq.
if ! command -v jq >/dev/null 2>&1; then
  RAW=$(cat)
  RAW_TARGETS=$(printf '%s' "$RAW" \
    | grep -oE '"(file_path|notebook_path|command)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' \
    | sed -E 's/^"[a-z_]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)
  if printf '%s' "$RAW_TARGETS" | grep -qE '\.env($|[^A-Za-z0-9])|\.pem($|[^A-Za-z0-9])|\.key($|[^A-Za-z0-9])|(^|/|[[:space:]])(credentials|secrets)\.'; then
    echo "File protection blocked [jqless-fallback]: the tool input names a protected file (.env, *.pem, *.key, credentials.*, secrets.*) and jq is unavailable, so only a coarse raw-text check ran. Install jq to restore full parsing and the .geniro/safety.json allowlist." >&2
    exit 2
  fi
  printf '{"systemMessage":"Geniro guard inactive: jq not found on PATH, so sensitive-file writes are checked only by a coarse name scan. Install jq to restore the guard."}\n'
  exit 0
fi

# Consume stdin - REQUIRED first step
INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# Find the nearest .geniro/safety.json walking up from cwd
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

is_allowed() {
  local pattern_id="$1"
  case " $ALLOWED " in
    *" $pattern_id "*) return 0 ;;
    *) return 1 ;;
  esac
}

block() {
  local pattern_id="$1"
  local description="$2"
  local path="$3"
  echo "File protection [$pattern_id]: Cannot write to $description: $path" >&2
  if [ -n "$SAFETY_FILE" ]; then
    echo "To allow this pattern, add \"$pattern_id\" to allow_patterns in $SAFETY_FILE" >&2
  else
    echo "To allow this pattern in this project, create .geniro/safety.json with: {\"allow_patterns\": [\"$pattern_id\"]}" >&2
  fi
  exit 2
}

# Run the full pattern set against one candidate path (case-insensitive).
# Order matters: more specific patterns first.
check_protected_path() {
  local p="$1"
  local p_lower
  p_lower=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')

  # 1. .env files (most common false-positive — dev-setup workflows often clone .env from a template)
  if ! is_allowed "write-env"; then
    if printf '%s' "$p_lower" | grep -qE '\.env$|\.env\.'; then
      block "write-env" ".env file" "$p"
    fi
  fi

  # 2. Git internals
  if ! is_allowed "write-git-internal"; then
    if printf '%s' "$p_lower" | grep -qE '\.git/'; then
      block "write-git-internal" "git internal file" "$p"
    fi
  fi

  # 3. Lock files (auto-generated by package managers — manual edits usually wrong)
  if ! is_allowed "write-lockfile"; then
    if printf '%s' "$p_lower" | grep -qE 'pnpm-lock\.yaml$|package-lock\.json$|yarn\.lock$|bun\.lockb$|cargo\.lock$|gemfile\.lock$|composer\.lock$|poetry\.lock$|pipfile\.lock$|go\.sum$'; then
      block "write-lockfile" "package-manager lock file" "$p"
    fi
  fi

  # 4. Certificates and private keys
  if ! is_allowed "write-cert-key"; then
    if printf '%s' "$p_lower" | grep -qE '\.pem$|\.key$|private-key'; then
      block "write-cert-key" "certificate or private key file" "$p"
    fi
  fi

  # 5. Credential / secret files
  if ! is_allowed "write-credentials"; then
    # Anchor to a path-segment boundary so a file literally named credentials.*
    # or secrets.* is blocked, without false-positiving on names that merely
    # contain the substring (e.g. the plugin's own lib/redact-secrets.sh).
    if printf '%s' "$p_lower" | grep -qE '(^|/)(credentials|secrets)\.'; then
      block "write-credentials" "credentials/secrets file" "$p"
    fi
  fi

  # 6. Terraform state
  if ! is_allowed "write-tfstate"; then
    if printf '%s' "$p_lower" | grep -qE '\.tfstate'; then
      block "write-tfstate" "Terraform state file" "$p"
    fi
  fi

  # 7. Vault files
  if ! is_allowed "write-vault"; then
    if printf '%s' "$p_lower" | grep -qE '\.vault'; then
      block "write-vault" "Vault file" "$p"
    fi
  fi
}

# Shell indirection and interpreter-mediated writes are single-sourced in
# lib/write-vectors.sh. Each inline fallback keeps the guard whole on a vendored
# install shipping hooks/ without lib/ — a missing helper must never make this
# guard fail open — and is a VERBATIM copy of the canonical function (delimited
# by GENIRO-VENDORED markers). A one-sided edit reopens the hole on that install,
# so edit both or neither.
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
if ! command -v _geniro_wv_path_tokens >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_wv_path_tokens
_geniro_wv_path_tokens() {
  local cmd="${1:-}"
  [ -z "$cmd" ] && return 0
  local tokre='[^[:space:]"'\''`=(),;|&<>{}]+'
  printf '%s' "$cmd" | grep -oE "$tokre" 2>/dev/null \
    | grep -E '/|\.[A-Za-z0-9]{1,6}$' 2>/dev/null \
    | grep -vE '^-' 2>/dev/null || true
  return 0
}
# GENIRO-VENDORED-END _geniro_wv_path_tokens
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
  # ---- Bash branch: shell-side writes into protected paths ----
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  if [ -z "$COMMAND" ]; then
    exit 0
  fi
  # Heredoc bodies are DATA, not shell syntax — a `> .env` inside one is text.
  # Drop body lines (between <<TAG / <<-TAG / <<'TAG' and the closing TAG)
  # before any extraction; the line carrying the << operator itself is kept, so
  # `cat <<EOF > .env` still yields its redirect target.
  SCRUBBED=$(printf '%s\n' "$COMMAND" | awk '
    hd {
      line = $0
      if (dash) sub(/^\t+/, "", line)   # <<- strips leading TABS from the terminator
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

  # Join backslash-newline continuations, then collapse newlines (mirrors
  # block-dangerous-git.sh) so multi-line commands can't split a write apart.
  JOINED="${SCRUBBED//\\$'\n'/ }"
  ONELINE="${JOINED//$'\n'/ }"

  # Quoted string literals are also data (`echo "see > .env"` writes nothing).
  # Blank them out before extraction. Trade-off: a deliberately QUOTED redirect
  # target (`> ".env"`) is no longer caught — accepted; the accidental
  # overwrite shapes this guard exists for are unquoted.
  ONELINE=$(printf '%s' "$ONELINE" | sed -E "s/'[^']*'/ /g; s/\"[^\"]*\"/ /g")

  CANDIDATES=""
  add_candidate() {
    local c="$1"
    # Trim one layer of surrounding quotes so >"$F"-style targets normalize.
    c="${c#\"}"; c="${c%\"}"
    c="${c#\'}"; c="${c%\'}"
    if [ -n "$c" ]; then
      CANDIDATES="${CANDIDATES}${c}
"
    fi
  }

  # 1) Redirection targets: > file, >> file, >| file. fd-dups (>&2) never yield
  #    a target (the class excludes &); 2>/dev/null lands on /dev/null, which
  #    matches no protected pattern.
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
  #    UNQUOTED script token (s/.../.../, y|...|...) is skipped — it is sed
  #    code, not a path, and a substitution that merely MENTIONS a protected
  #    name (s/.env.a/.env.b/) must not block; quoted scripts were already
  #    blanked by the quote scrub above.
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
  #    FROM a protected file is a read and stays allowed.
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
  #    when -f/--force is present (without -f, ln refuses to clobber an existing
  #    target). A symlink or hardlink over a protected path is a write.
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

  # 10) Interpreter-mediated writes: python/node/perl/ruby/php opening a file for
  #     writing, or an awk program redirecting `print` into one. Vectors 1-9 read
  #     $ONELINE, whose heredoc bodies and quoted literals were blanked as data —
  #     and an interpreter's file write is not shell syntax anywhere, so
  #     `python3 -c "open('.env','w').write(k)"` reaches the filesystem
  #     unchecked. This vector therefore scans the RAW $COMMAND, and fires only
  #     on the conjunction interpreter + write op + target, so a read-only
  #     interpreter call stays allowed. Contract: lib/write-vectors.sh.
  _iw_unresolved=0
  _iw_targets=$(_geniro_interp_write_targets "$COMMAND") || _iw_unresolved=1
  if [ -n "$_iw_targets" ]; then
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      add_candidate "$tok"
    done <<< "$_iw_targets"
  fi
  if [ "$_iw_unresolved" = "1" ]; then
    # The write target is a variable or expression (`open(p,'w')`), unresolvable
    # from the command text. Fall back to every path-shaped token in it: the
    # protected patterns are distinctive filenames, so a token that is not one of
    # them costs nothing, while `p='.env'; open(p,'w')` still lands.
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      add_candidate "$tok"
    done <<< "$(_geniro_wv_path_tokens "$COMMAND")"
  fi

  if [ -z "$CANDIDATES" ]; then
    exit 0
  fi
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    check_protected_path "$cand"
  done <<< "$CANDIDATES"
  exit 0
fi

# ---- Edit/Write/MultiEdit branch ----
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
  # No file path found, allow execution
  exit 0
fi

check_protected_path "$FILE_PATH"

# File is safe to write, allow execution
exit 0
