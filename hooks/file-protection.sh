#!/usr/bin/env bash
# file-protection.sh
# PreToolUse hook for Write/Edit/MultiEdit AND Bash — blocks writes to sensitive files.
# Prevents accidental exposure of credentials and protected configurations.
#
# Edit/Write/MultiEdit branch: checks .tool_input.file_path.
# Bash branch: catches shell-side writes the file-tool matcher never sees —
# redirection (>, >>, >|), tee, in-place sed (-i), cp/mv destinations, dd of=,
# and interpreter-mediated writes (a scripting runtime opening a protected
# file for writing, an awk program redirecting `print` into one).
# Read-only access to protected files (cat/grep/cp FROM them) stays allowed.
# Heredoc bodies and quoted string literals are scrubbed before extraction
# (they are data, not syntax) — a deliberately QUOTED redirect target
# (`> ".env"`) is therefore a documented miss, accepted to avoid hard-blocking
# benign commands that merely mention protected names in strings. The scrubbed
# positions that ARE syntax are the shell-indirection payloads — `sh -c "..."`,
# `eval "..."`, a quoted program piped to a shell, a heredoc body fed to one, a
# process substitution a shell reads, an interpreter shelling out: all of them are
# extracted before the scrub and this guard re-runs on each.
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
  local _wv_sh="${_wv_pfx}${_wv_shq}"'([^[:space:];|&<>"'\'']*/)?(sh|bash|zsh|dash|ksh|ash)'"${_wv_shq}"
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
    done <<< "$(printf '%s\n' "$cmd" | grep -oE "${_wv_q}"'([^[:space:];|&<>"'\'']*/)?(sh|bash|zsh|dash|ksh|ash)'"${_wv_q}${_wv_nq}"'*'"${_wv_q}${_wv_cflag}${_wv_q}${_wv_nq}"'*'"${_wv_lit}" 2>/dev/null || true)"

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
  # `writeTextFile` covers Deno.writeTextFile(Sync).
  local _wops_first='((writeFile|appendFile|createWriteStream|outputFile|writeTextFile)(Sync)?|file_put_contents|File\.write|IO\.write)'
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

if [ "$TOOL_NAME" = "Bash" ]; then
  # ---- Bash branch: shell-side writes into protected paths ----
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  if [ -z "$COMMAND" ]; then
    # jq is present, but the command extracted empty — either tool_input.command
    # was genuinely absent, or the payload was malformed JSON the parse above
    # silently swallowed (`|| echo ""`). A malformed payload must not be a free
    # pass: run the same coarse fail-closed raw-text scan the jq-absent branch
    # at the top of this file uses, so a protected-file write still blocks even
    # when parsing broke.
    RAW_TARGETS=$(printf '%s' "$INPUT" \
      | grep -oE '"(file_path|notebook_path|command)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' \
      | sed -E 's/^"[a-z_]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)
    if printf '%s' "$RAW_TARGETS" | grep -qE '\.env($|[^A-Za-z0-9])|\.pem($|[^A-Za-z0-9])|\.key($|[^A-Za-z0-9])|(^|/|[[:space:]])(credentials|secrets)\.'; then
      echo "File protection blocked [jqless-fallback]: the tool input names a protected file (.env, *.pem, *.key, credentials.*, secrets.*) but tool_input.command could not be parsed, so only a coarse raw-text check ran." >&2
      exit 2
    fi
    exit 0
  fi
  # Heredoc bodies are DATA, not shell syntax — a `> .env` inside one is text.
  # Drop body lines (between <<TAG / <<-TAG / <<'TAG' / <<\TAG and the closing TAG)
  # before any extraction; the line carrying the << operator itself is kept, so
  # `cat <<EOF > .env` still yields its redirect target.
  SCRUBBED=$(printf '%s\n' "$COMMAND" | awk '
    hd {
      line = $0
      if (dash) sub(/^\t+/, "", line)   # <<- strips leading TABS from the terminator
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

  # Join backslash-newline continuations.
  JOINED="${SCRUBBED//\\$'\n'/ }"

  # A quoted literal may itself span a newline, and the per-line blanking below
  # would then see an unbalanced quote on each half and scan the second half as
  # syntax. Join the newlines INSIDE such a span first (lossless: a newline
  # inside quotes never separates two commands), leaving every command-separating
  # newline for the pass below. Contract: lib/write-vectors.sh.
  JOINED=$(_geniro_join_quoted_newlines "$JOINED")

  # Quoted string literals are also data (`echo "see > .env"` writes nothing).
  # Blank them out before extraction. Trade-off: a deliberately QUOTED redirect
  # target (`> ".env"`) is no longer caught — accepted; the accidental
  # overwrite shapes this guard exists for are unquoted.
  #
  # Scrubbed per LINE, newlines INTACT, and only THEN collapsed. Collapsing
  # first let two ordinary prose apostrophes on two different lines
  # (`# don't` … `# won't`) pair into one "literal" that swallowed the real
  # command between them — a fail-open on benign input, not on an attack.
  # The span EXCLUDES ; & | (mirrors block-dangerous-git.sh:394's blanking
  # pass, minus its unquote pass — a deliberately QUOTED redirect target is a
  # documented miss this guard keeps) — otherwise two ordinary prose
  # apostrophes straddling a `;` pair across it and blank the real command
  # between them.
  JOINED=$(printf '%s\n' "$JOINED" | sed -E "s/'[^';&|]*'/ /g; s/\"[^\";&|]*\"/ /g")

  # Collapse the remaining (command-separating) newlines so multi-line commands
  # can't split a write apart (mirrors block-dangerous-git.sh).
  ONELINE="${JOINED//$'\n'/ }"

  # A `cd` into `.git/` hides the write target from the redirect/tee/…
  # candidate extraction below: `cd .git && echo x > config` spells no `.git`
  # path in the write operand at all, yet writes exactly where
  # `echo x > .git/config` would. Derive that prefix the same way
  # block-geniro-deletion.sh's CD_PREFIX does (its ~lines 689-738), scoped to a
  # cd target that is itself under `.git/`; add_candidate below re-prefixes
  # each relative operand with it. The LAST such `cd` wins, matching execution
  # order. Filename-matched patterns (.env, *.pem, *.key, …) need no help here
  # — they match on the operand text alone, cd or not.
  CD_PREFIX=""
  while IFS= read -r _cd_span; do
    [ -z "$_cd_span" ] && continue
    set -f
    # shellcheck disable=SC2086
    for _cd_tok in $_cd_span; do
      _cd_tok="${_cd_tok#\\}"
      while [ "${_cd_tok#\(}" != "$_cd_tok" ]; do _cd_tok="${_cd_tok#\(}"; done
      case "$_cd_tok" in cd|*/cd|-*) continue ;; esac
      _cd_tok="${_cd_tok#\"}"; _cd_tok="${_cd_tok%\"}"
      _cd_tok="${_cd_tok#\'}"; _cd_tok="${_cd_tok%\'}"
      case "/${_cd_tok%/}/" in
        */.git/*) CD_PREFIX="${_cd_tok%/}" ;;
      esac
      break
    done
    set +f
  done <<< "$(printf '%s\n' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])cd[[:space:]]+[^|;&]*' || true)"

  CANDIDATES=""
  add_candidate() {
    local c="$1"
    # Trim one layer of surrounding quotes so >"$F"-style targets normalize.
    c="${c#\"}"; c="${c%\"}"
    c="${c#\'}"; c="${c%\'}"
    if [ -n "$c" ]; then
      CANDIDATES="${CANDIDATES}${c}
"
      # Re-prefix a plausible RELATIVE operand with the last `cd .git/…` target
      # so a write that only resolves into .git/ via the shell's cwd still hits
      # the write-git-internal check below. Not re-prefixed: an already-
      # absolute/home/variable operand, and an operand that already carries a
      # .git segment (needs no help, and stops this from recursing).
      if [ -n "$CD_PREFIX" ]; then
        case "$c" in
          -*|/*|'~'*|'$'*) : ;;
          *)
            case "/$c" in
              */.git/*|*/.git) : ;;
              *) CANDIDATES="${CANDIDATES}${CD_PREFIX}/${c}
" ;;
            esac
            ;;
        esac
      fi
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
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])tee[[:space:]]+[^|;&]*' || true)"

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
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])sed[[:space:]]+[^|;&]*' || true)"

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
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])(cp|mv)[[:space:]]+[^|;&]*' || true)"

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
  done <<< "$(printf '%s' "$ONELINE" | grep -oE '(^|[\\|;&(/[:space:]])ln[[:space:]]+[^|;&]*' || true)"

  # 10) Interpreter-mediated writes: a scripting runtime opening a file for
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
