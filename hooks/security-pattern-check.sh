#!/usr/bin/env bash
# security-pattern-check.sh — PreToolUse Edit|Write|MultiEdit|NotebookEdit AND Bash
#
# Cheap regex scan for high-signal, low-false-positive security anti-patterns
# in file content. Hard-block (exit 2) on pattern hit; per-pattern bypass via
# .geniro/safety.json allow_patterns.
#
# Edit/Write/MultiEdit branch: scans .tool_input.content / .new_string against
# the patterns scoped to .tool_input.file_path's extension.
# Bash branch: catches shell-side authoring the file-tool matcher never sees —
# a `cat > x.py <<EOF ... EOF` heredoc, `printf '...' > x.js`, `echo '...' |
# tee x.sh`, or an interpreter-mediated `node -e "fs.writeFileSync('x.js', ...)"`
# writes the SAME flagged content without an Edit. It extracts each write's
# (target, content) pair — the heredoc body, the echo/printf payload, or the
# interpreter call's path and body arguments — and runs the same scan scoped to
# the target path's extension. A write hidden behind shell indirection
# (`sh -c "..."`, `eval "..."`, a quoted program piped to a shell, a heredoc body
# fed to one, a process substitution, an interpreter shelling out) is extracted
# first and this scan re-runs on that payload. Commands with no file-write target
# (no heredoc/redirect/tee writing a file) no-op allow.
#
# Scope: catches obvious string-level wins at edit time WITHOUT the LLM-cost
# of an ambient Stop-hook review. Logic-level issues (authz bypass, IDOR,
# race conditions, mass assignment) are not regex-detectable and require
# /geniro:review.
#
# Pattern IDs (all bypassable via .geniro/safety.json):
#   sec-eval-exec        eval() / exec() / new Function() — code from string
#   sec-pickle           pickle.load(s) — unsafe deserialization
#   sec-yaml-unsafe      yaml.load(...) without explicit SafeLoader
#   sec-shell-injection  subprocess shell=True / os.system / os.popen
#   sec-curl-pipe-sh     remote-download piped to a shell — supply-chain risk
#   sec-tls-bypass       verify=False / rejectUnauthorized: false / cert-check off
#   sec-xss-sink         .innerHTML= / dangerouslySetInnerHTML / document.write
#   sec-weak-crypto      MD5 / SHA1 used for security
#
# Per-project bypass:
#   .geniro/safety.json — {"allow_patterns": ["sec-eval-exec", "sec-xss-sink"]}

set -euo pipefail

# Fail open but LOUDLY if jq is missing: without it the hook cannot parse tool
# input, and a silent exit 0 would leave the user believing the scan is active.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"Geniro hook inactive: jq not found on PATH, so the security-pattern scan is NOT running. Install jq to restore it."}\n'
  exit 0
fi

# Consume stdin — REQUIRED first step.
INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# This scan is implemented in Perl (PCRE). If perl is absent the scan cannot run;
# say so and exit 0 rather than silently passing every edit — otherwise a
# perl-less host looks "clean" when the guard is actually inert. The notice goes
# out as a stdout systemMessage, like the jq-absent branch above: hook stderr on a
# rc=0 exit is not surfaced to the user at all, and the Cursor shim discards it
# outright — so a notice written to stderr here would reach nobody.
if ! command -v perl >/dev/null 2>&1; then
  printf '{"systemMessage":"Geniro hook inactive: perl not found on PATH, so the security-pattern scan is NOT running. Install perl to restore it."}\n'
  exit 0
fi

# Per-project allowlist.
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
  case " $ALLOWED " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Per-scan globals (set by derive_ext / the scan drivers): FILE_PATH, CONTENT,
# ext_lower, basename_lower. block() and check() read them.
FILE_PATH=""
CONTENT=""
ext_lower=""
basename_lower=""

# Derive the lowercased extension + basename from a target path.
# Filenames without a dot get an empty ext (won't match the ext-list filter).
# Dockerfile / Makefile are recognized by basename. A `.ipynb` notebook maps
# onto the Python ext set (single-sourced here rather than restated on every
# `check "sec-*" "py pyw pyx pyi"` call site): a NotebookEdit payload always
# carries `notebook_path: *.ipynb`, and cell code is Python — without this
# mapping every Python pattern's ext-list silently excludes every notebook.
derive_ext() {
  local fp="$1"
  local filename="${fp##*/}"
  ext_lower=""
  if [[ "$filename" == *.* ]]; then
    ext_lower="${filename##*.}"
    ext_lower="$(printf '%s' "$ext_lower" | tr '[:upper:]' '[:lower:]')"
  fi
  basename_lower="$(printf '%s' "$filename" | tr '[:upper:]' '[:lower:]')"
  case "$basename_lower" in
    dockerfile|dockerfile.*|*.dockerfile) ext_lower="dockerfile" ;;
  esac
  case "$ext_lower" in
    ipynb) ext_lower="py" ;;
  esac
}

# Returns 0 if $ext_lower is in space-separated list; "*" matches all.
ext_matches() {
  local list=" $1 "
  if [[ "$list" == *" * "* ]]; then return 0; fi
  if [ -z "$ext_lower" ]; then return 1; fi
  case "$list" in
    *" $ext_lower "*) return 0 ;;
    *) return 1 ;;
  esac
}

block() {
  local pattern_id="$1" description="$2" matched_line="$3"
  cat >&2 <<EOF
[security-pattern-check] $pattern_id — $description
  File:    $FILE_PATH
  Matched: $matched_line

Two ways forward — a code comment does NOT clear this block, the scan reads content only:
  - Rewrite the edit so the flagged construct is gone (safe API, argv list, sanitizer).
  - Or, if the pattern is intentional here (input validated, trusted source), add
    "$pattern_id" to allow_patterns in .geniro/safety.json — the per-project bypass
    this hook reads.
EOF
  if [ -n "$SAFETY_FILE" ]; then
    echo "  (existing safety.json: $SAFETY_FILE)" >&2
  fi
  echo "Logic-level issues (authz bypass, IDOR, race conditions) require /geniro:review." >&2
  exit 2
}

# Matched-construct truncation length for the block message (see `check`
# below): long enough to show the whole flagged expression in every pattern
# here, short enough that a minified bundle line cannot flood the block
# message and push the two remediation options off the user's screen. Single
# variable so the perl one-liner's two uses (the length test, then the cut)
# can't drift apart.
GENIRO_SPC_TRUNC_LEN=160

# check <id> <ext-list> <description> <PCRE regex>
check() {
  local id="$1" exts="$2" desc="$3" regex="$4"
  if is_allowed "$id"; then return 0; fi
  if ! ext_matches "$exts"; then return 0; fi
  local matched=""
  # Echo only the matched construct ($&), not the whole source line ($_): the
  # full line can carry an adjacent secret, and this string is printed to stderr.
  # Slurp the whole CONTENT (-0777) so an anti-pattern split across physical
  # lines (a download-to-shell construct broken with a backslash-newline) still
  # matches; derive the line number from the match offset and flatten newlines
  # in the echoed construct so the stderr message stays one line.
  # The construct is truncated to $GENIRO_SPC_TRUNC_LEN chars — single-sourced
  # above so the perl script's two uses (the length test, then the cut) read
  # the same value rather than restating the literal twice.
  matched=$(printf '%s' "$CONTENT" | RX="$regex" TRUNC="$GENIRO_SPC_TRUNC_LEN" perl -0777 -ne 'if (/$ENV{RX}/) { my $m = $&; my $ln = (substr($_,0,$-[0]) =~ tr/\n//) + 1; $m =~ s/\n/ /g; $m = substr($m,0,$ENV{TRUNC}) if length($m) > $ENV{TRUNC}; printf "%d:%s", $ln, $m; exit 0 }' 2>/dev/null | head -1 || true)
  if [ -n "$matched" ]; then
    block "$id" "$desc" "$matched"
  fi
}

# Run the full pattern set against the current $CONTENT / $ext_lower.
# Order: more specific first.
run_pattern_scan() {
  # 1. eval/exec — code execution from string
  check "sec-eval-exec" "py pyw pyx pyi" \
    "Python eval()/exec() — executes a string as code" \
    '(?<![._a-zA-Z0-9])(eval|exec)\s*\('

  check "sec-eval-exec" "js jsx ts tsx mjs cjs" \
    "JavaScript eval()/new Function() — executes a string as code" \
    '(?<![._a-zA-Z0-9])(eval\s*\(|new\s+Function\s*\()'

  # 2. pickle — unsafe deserialization
  check "sec-pickle" "py pyw pyx pyi" \
    "pickle.load(s) — arbitrary code execution on untrusted input (use json or a signed format)" \
    '\bpickle\.loads?\s*\('

  # 3. yaml.load without SafeLoader
  check "sec-yaml-unsafe" "py pyw pyx pyi" \
    "yaml.load() — use yaml.safe_load() or pass Loader=yaml.SafeLoader" \
    '\byaml\.load\s*\('

  # 4. shell injection — subprocess shell=True / os.system / os.popen
  check "sec-shell-injection" "py pyw pyx pyi" \
    "shell=True / os.system() / os.popen() — shell injection risk (pass argv as a list)" \
    '(\bsubprocess\.(call|run|check_call|check_output|Popen)\s*\([^)]*shell\s*=\s*True|\bos\.(system|popen)\s*\()'

  # 5. remote download piped to a shell. The [^|\n]* spans stay within one
  #    physical line (a backslash-newline continuation is explicitly allowed by
  #    the middle group), so a download on line 1 and an unrelated pipe-to-shell
  #    lines later can no longer false-positive across the -0777 slurp. The
  #    optional wrapper group catches a sudo/doas/command/env prefix and an
  #    absolute shell path.
  check "sec-curl-pipe-sh" "sh bash zsh dockerfile" \
    "remote download piped to a shell — supply-chain risk (download, verify checksum/signature, then execute)" \
    '(curl|wget)\b[^|\n]*(\\\n[^|\n]*)*\|\s*((sudo|doas)(\s+-\S+)*\s+|command\s+|env(\s+\S+=\S*)*\s+)?(\S*/)?(sh|bash|zsh|dash|ksh)\b'

  # 6. TLS bypass
  check "sec-tls-bypass" "py pyw pyx pyi" \
    "verify=False — TLS certificate verification disabled" \
    '\bverify\s*=\s*False\b'

  check "sec-tls-bypass" "js jsx ts tsx mjs cjs" \
    "rejectUnauthorized: false — TLS certificate verification disabled" \
    '\brejectUnauthorized\s*:\s*false\b'

  check "sec-tls-bypass" "sh bash zsh dockerfile" \
    "TLS certificate verification disabled on a download flag" \
    '(^|\s)(--insecure|--no-check-certificate)(\s|$)'

  # 7. XSS sinks
  check "sec-xss-sink" "js jsx ts tsx html mjs cjs vue svelte" \
    ".innerHTML= / dangerouslySetInnerHTML / document.write — XSS sink (sanitize or use textContent / safe-by-default renderer)" \
    '(\.innerHTML\s*=|\bdangerouslySetInnerHTML\b|\bdocument\.write(ln)?\s*\()'

  # 8. weak crypto for security
  check "sec-weak-crypto" "js jsx ts tsx mjs cjs" \
    "createHash('md5'|'sha1') — broken for security (SHA-256+ for auth/integrity; OK for non-security checksums)" \
    "createHash\\s*\\(\\s*[\"'](md5|sha1)[\"']"

  check "sec-weak-crypto" "py pyw pyx pyi" \
    "hashlib.md5() / hashlib.sha1() — broken for security (SHA-256+ for auth/integrity; for a non-security checksum, bypass via allow_patterns)" \
    '\bhashlib\.(md5|sha1)\s*\('
}

# Scan one extracted (target, content) pair from a Bash write.
scan_one() {
  local tgt="$1" body="$2"
  [ -z "$tgt" ] && return 0
  [ -z "$body" ] && return 0
  FILE_PATH="$tgt"
  CONTENT="$body"
  derive_ext "$tgt"
  run_pattern_scan
}

# Strip one layer of surrounding quotes from a token (mirrors file-protection.sh).
strip_quotes() {
  local c="$1"
  c="${c#\"}"; c="${c%\"}"
  c="${c#\'}"; c="${c%\'}"
  printf '%s' "$c"
}

if [ "$TOOL_NAME" = "Bash" ]; then
  # ---- Bash branch: scan content authored via heredoc / echo / printf ----
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  if [ -z "$COMMAND" ]; then
    exit 0
  fi

  # 0) Shell indirection. `sh -c "<payload>"` and `eval "<payload>"` pass a
  #    program as an ARGUMENT; `echo "<payload>" | bash` and `bash <<EOF … EOF`
  #    pass it on STDIN. In each case the flagged write lives inside the payload,
  #    where the heredoc/echo extraction below reads it as a quoted operand of
  #    `sh`, not as a write with a target — so `sh -c "echo '...' > bad.py"` was
  #    scanned as nothing while the bare `echo '...' > bad.py` was blocked. Same
  #    extractor, same re-run contract, as the five sibling Bash guards.
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

  # Heredoc bodies are DATA for the PAYLOAD extraction (an `sh -c` mentioned
  # inside a body written to a file is text), so arms 1-3 read the scrubbed
  # command; arm 4 re-derives the bodies that are fed to a shell from the raw one.
  # Opener lines are kept, so step 2's redirect/tee target detection still works.
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
  JOINED="${SCRUBBED//\\$'\n'/ }"
  # A quoted payload may itself span a newline (`printf '%s' 'line one
  # line two' > bad.py`). Step 2 below is line-oriented and pairs a payload with
  # the redirect target found on the SAME line, so a multi-line literal never
  # reached its target and the write went unscanned. Join the newlines INSIDE a
  # quoted span — lossless, since a newline inside quotes never separates two
  # commands — which is what the heredoc arm already does for a multi-line body.
  # Contract: lib/write-vectors.sh.
  JOINED=$(_geniro_join_quoted_newlines "$JOINED")

  # Re-run THIS scan on each extracted payload; a block inside propagates out.
  # Nested indirection terminates because each payload is strictly shorter than
  # the command it came from.
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

  # 1) Heredoc bodies paired with their redirect/tee target. Mirrors
  #    file-protection.sh's heredoc detection, but CAPTURES the body (the content
  #    being written) instead of dropping it, and records the redirect/tee target
  #    from the opener line so the body is scanned at the target's extension.
  #    Per heredoc that writes to a file, awk emits:
  #      @@HD_BEGIN@@ <target>
  #      <body lines...>
  #      @@HD_END@@
  RECORDS=$(printf '%s\n' "$COMMAND" | awk '
    hd {
      line = $0
      if (dash) sub(/^\t+/, "", line)
      if (line == tag) { print "@@HD_END@@"; hd = 0; next }
      print
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
        op = substr($0, pos, RLENGTH)
        dash = (op ~ /^<<-/)
        tag = op
        sub(/^<<-?[[:space:]]*/, "", tag)
        gsub(/[\\"'\'']/, "", tag)
        target = ""
        if (match($0, />{1,2}[[:space:]]*[^[:space:];|&<>)]+/)) {
          target = substr($0, RSTART, RLENGTH)
          sub(/^>{1,2}[[:space:]]*/, "", target)
        } else if (match($0, /tee[[:space:]]+(-a[[:space:]]+)?[^[:space:];|&<>)]+/)) {
          target = substr($0, RSTART, RLENGTH)
          sub(/^tee[[:space:]]+(-a[[:space:]]+)?/, "", target)
        }
        hd = 1
        print "@@HD_BEGIN@@ " target
        next
      }
    }
  ')

  hd_target=""
  hd_body=""
  hd_in=0
  while IFS= read -r line; do
    case "$line" in
      "@@HD_END@@")
        hd_in=0
        scan_one "$(strip_quotes "$hd_target")" "$hd_body"
        hd_target=""
        hd_body=""
        ;;
      "@@HD_BEGIN@@ "*)
        hd_target="${line#@@HD_BEGIN@@ }"
        hd_body=""
        hd_in=1
        ;;
      *)
        if [ "$hd_in" = "1" ]; then
          hd_body="${hd_body}${line}
"
        fi
        ;;
    esac
  done <<< "$RECORDS"

  # 2) Inline echo/printf content redirected to a file, or piped to tee. Reads
  #    $JOINED from step 0 — heredoc bodies dropped (data: an `echo ... >` inside
  #    one is text), opener lines kept, backslash-newline continuations joined so
  #    a wrapped write stays one logical line. Quotes are PRESERVED there (the
  #    quoted payload IS the content to scan).
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      *printf*|*echo*) : ;;
      *) continue ;;
    esac
    # Split on UNQUOTED ; && || first (tracking quote state char-by-char, so a
    # literal separator INSIDE a quoted payload never splits it; a bare & or |
    # is left alone — see the split's own comment). Without this, a chained
    # `echo "safe" > f.js; echo done` on one line paired f.js's target (found by
    # head -1, the FIRST redirect) with the LAST echo's payload — the greedy
    # content match below binds to the LAST printf/echo — so a trailing echo
    # silently replaced the real payload, no apostrophe or indirection needed.
    # Each simple command now gets its own target+content pairing.
    while IFS= read -r seg; do
      [ -z "$seg" ] && continue
      case "$seg" in
        *printf*|*echo*) : ;;
        *) continue ;;
      esac
      # Target detection runs on a quote-blanked copy of the segment so a `>` or
      # `|` INSIDE the quoted payload (`echo "a=x > 0" > f.js`) can't be grabbed
      # as the redirect target — `head -1` must land on the real target, not an
      # in-payload one, or the derived extension is wrong and the scan is
      # skipped. The raw segment is kept below for the content (the quoted
      # payload IS what we scan).
      #
      # UNQUOTE whitespace-free tokens first, THEN blank what's left: a quoted
      # redirect target (`> 'bad.py'`) is one whitespace-free shell word, and
      # blanking it outright (without unquoting first) erased it completely —
      # `tgt` came back empty and the whole write was skipped unscanned
      # (2026-08-09 audit #7: `printf 'eval(x)' > 'bad.py'` scanned as nothing
      # while the unquoted `printf 'eval(x)' > bad.py` correctly blocked). The
      # in-payload case above still works after this: "a=x > 0" carries
      # whitespace, so the unquote pass leaves it quoted and the blank below
      # still erases it. Contract: lib/write-vectors.sh §E.
      seg_nq=$(_geniro_wv_unquote_words "$seg")
      seg_nq=$(printf '%s' "$seg_nq" | sed -E "s/'[^']*'/ /g; s/\"[^\"]*\"/ /g")
      # Target: a redirect `> file` / `>> file`, else a `tee file` argument.
      tgt=$(printf '%s' "$seg_nq" | grep -oE '>{1,2}\|?[[:space:]]*[^[:space:];|&<>)]+' | head -1 | sed -E 's/^>{1,2}\|?[[:space:]]*//' || true)
      if [ -z "$tgt" ]; then
        tgt=$(printf '%s' "$seg_nq" | grep -oE '(^|[\\|;&(/[:space:]])tee[[:space:]]+(-a[[:space:]]+)?[^[:space:];|&<>)]+' | head -1 | sed -E 's/^.*tee[[:space:]]+(-a[[:space:]]+)?//' || true)
      fi
      [ -z "$tgt" ] && continue
      tgt="$(strip_quotes "$tgt")"
      # Content: the echo/printf payload — everything after the COMMAND WORD
      # (the FIRST/leftmost printf|echo), up to the first pipe or redirect. A
      # greedy `.*(printf|echo)` strip is anchored to the LAST occurrence of
      # either word in the whole segment — including one appearing INSIDE the
      # quoted payload itself (`printf 'eval(u) echo ok' > bad.py`), which
      # dropped everything up to and including that in-payload "echo" and
      # silently lost the flagged text ahead of it. awk's match() finds the
      # leftmost occurrence — the true command word — so the payload text after
      # it (including any "echo"/"printf" substring inside it) survives intact.
      content=$(printf '%s' "$seg" | awk '
        match($0, /(printf|echo)[[:space:]]+/) { print substr($0, RSTART + RLENGTH); next }
        { print }
      ' | sed -E 's/[[:space:]]*(\||>{1,2}).*$//')
      content="$(strip_quotes "$content")"
      [ -z "$content" ] && continue
      scan_one "$tgt" "$content"
    done <<< "$(printf '%s' "$line" | awk '
      {
        n = length($0); q = ""; out = ""
        i = 1
        while (i <= n) {
          c = substr($0, i, 1)
          if (q != "") {
            out = out c
            if (c == q) q = ""
            i++
            continue
          }
          if (c == "\"" || c == "'\''") { q = c; out = out c; i++; continue }
          # Only ; && || split into separate simple commands. A BARE & or |
          # stays in the segment — a bare | is the `echo … | tee target`
          # pipeline this scan explicitly reads as ONE write, and splitting it
          # would separate the payload from its own target.
          if (c == ";") { out = out "\n"; i++; continue }
          if (c == "&" && substr($0, i+1, 1) == "&") { out = out "\n"; i += 2; continue }
          if (c == "|" && substr($0, i+1, 1) == "|") { out = out "\n"; i += 2; continue }
          out = out c
          i++
        }
        print out
      }')"
  done <<< "$JOINED"

  # 3) Interpreter-authored writes: `node -e "fs.writeFileSync('app.js','<body>')"`
  #    writes the SAME flagged content as `printf '<body>' > app.js`, and none of
  #    it is shell syntax, so steps 1 and 2 see neither the target nor the body.
  #    The interpreter+op+target conjunction is single-sourced in
  #    lib/write-vectors.sh, the same helper the five sibling Bash guards consume;
  #    this scan additionally needs the CONTENT, so it re-reads the raw command for
  #    the (target, body) pairs whose body is a literal. A write whose body is a
  #    variable is not scannable at all — there is no content to match against.
  _spc_interp_targets=$(_geniro_interp_write_targets "$COMMAND" || true)
  if [ -n "$_spc_interp_targets" ]; then
    _q_spc="\\\\?[\"']"
    while IFS= read -r _pair; do
      [ -z "$_pair" ] && continue
      # Target: the first quoted literal. Content: everything past the first
      # comma, which the match already bounds at the body's closing quote.
      _ptgt=$(printf '%s' "$_pair" | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//")
      _pbody=$(printf '%s' "$_pair" | sed -E "s/^[^,]*,[[:space:]]*//")
      scan_one "$(strip_quotes "$_ptgt")" "$(strip_quotes "$_pbody")"
    done <<< "$(
      {
        # Ops whose first argument is the path and second is the body.
        printf '%s' "$COMMAND" \
          | grep -oE "((writeFile|appendFile|outputFile|writeTextFile)(Sync)?|file_put_contents|File\.write|IO\.write)\([[:space:]]*${_q_spc}[^\\\\\"']+${_q_spc}[[:space:]]*,[[:space:]]*${_q_spc}[^\\\\\"']*${_q_spc}"
        # pathlib: Path('<path>').write_text('<body>').
        printf '%s' "$COMMAND" \
          | grep -oE "Path\([[:space:]]*${_q_spc}[^\\\\\"']+${_q_spc}[[:space:]]*\)[[:space:]]*\.write_(text|bytes)\([[:space:]]*${_q_spc}[^\\\\\"']*${_q_spc}" \
          | sed -E "s/\)[[:space:]]*\.write_(text|bytes)\(/, /"
      } 2>/dev/null || true
    )"
    # `open('<path>','w').write('<body>')` splits the pair across two calls, so the
    # body sits after the LAST paren, not after a comma.
    while IFS= read -r _pair; do
      [ -z "$_pair" ] && continue
      _ptgt=$(printf '%s' "$_pair" | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//")
      _pbody=$(printf '%s' "$_pair" | sed -E "s/^.*\.write\([[:space:]]*//")
      scan_one "$(strip_quotes "$_ptgt")" "$(strip_quotes "$_pbody")"
    done <<< "$(printf '%s' "$COMMAND" | grep -oE "(open|fopen|io\.open)\([[:space:]]*${_q_spc}[^\\\\\"']+${_q_spc}[[:space:]]*,[[:space:]]*${_q_spc}[waxWAX>][^)]*\)[[:space:]]*\.write\([[:space:]]*${_q_spc}[^\\\\\"']*${_q_spc}" 2>/dev/null || true)"
  fi

  exit 0
fi

# ---- Edit/Write/MultiEdit/NotebookEdit branch ----
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null || echo "")
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Write has `.content`; Edit has `.new_string`; MultiEdit has `.edits[].new_string`;
# NotebookEdit has `.new_source`. Scan whichever is present (MultiEdit: all edit
# bodies joined so the scan sees them).
CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // .tool_input.new_source // ([.tool_input.edits[]?.new_string] | join("\n")) // ""' 2>/dev/null || echo "")
if [ -z "$CONTENT" ]; then
  exit 0
fi

derive_ext "$FILE_PATH"
run_pattern_scan

# No pattern matched — allow.
exit 0
