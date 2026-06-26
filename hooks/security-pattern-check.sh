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
# a `cat > x.py <<EOF ... EOF` heredoc, `printf '...' > x.js`, or `echo '...' |
# tee x.sh` writes the SAME flagged content without an Edit. It extracts each
# write's (target, content) pair — the heredoc body, or the echo/printf payload —
# and runs the same scan scoped to the target path's extension. Commands with no
# file-write target (no heredoc/redirect/tee writing a file) no-op allow.
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
# perl-less host looks "clean" when the guard is actually inert.
if ! command -v perl >/dev/null 2>&1; then
  echo "[security-pattern-check] perl not found — security scan skipped on this host." >&2
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
  ALLOWED=$(jq -r '.allow_patterns[]? // empty' "$SAFETY_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
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
# Dockerfile / Makefile are recognized by basename.
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

If this is intentional (input validated, context sanitized, trusted source):
  - Justify in an inline code comment AND retry the edit.
  - Or bypass per-project: add "$pattern_id" to allow_patterns in .geniro/safety.json.
EOF
  if [ -n "$SAFETY_FILE" ]; then
    echo "  (existing safety.json: $SAFETY_FILE)" >&2
  fi
  echo "Logic-level issues (authz bypass, IDOR, race conditions) require /geniro:review." >&2
  exit 2
}

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
  matched=$(printf '%s' "$CONTENT" | RX="$regex" perl -0777 -ne 'if (/$ENV{RX}/) { my $m = $&; my $ln = (substr($_,0,$-[0]) =~ tr/\n//) + 1; $m =~ s/\n/ /g; $m = substr($m,0,160) if length($m) > 160; printf "%d:%s", $ln, $m; exit 0 }' 2>/dev/null | head -1 || true)
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
    "hashlib.md5() / hashlib.sha1() — broken for security (SHA-256+ for auth/integrity; for a non-security checksum, justify inline and bypass via allow_patterns)" \
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
      if (match($0, /<<-?["'\'']?[A-Za-z_][A-Za-z0-9_]*/)) {
        op = substr($0, RSTART, RLENGTH)
        dash = (op ~ /^<<-/)
        tag = op
        sub(/^<<-?/, "", tag)
        gsub(/["'\'']/, "", tag)
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

  # 2) Inline echo/printf content redirected to a file, or piped to tee. Drop
  #    heredoc BODIES first (data — an `echo ... >` inside one is text), keeping
  #    opener lines; join backslash-newline continuations so a wrapped write stays
  #    one logical line. Quotes are PRESERVED here (the quoted payload IS the
  #    content to scan).
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

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      *printf*|*echo*) : ;;
      *) continue ;;
    esac
    # Target: a redirect `> file` / `>> file`, else a `tee file` argument.
    tgt=$(printf '%s' "$line" | grep -oE '>{1,2}\|?[[:space:]]*[^[:space:];|&<>)]+' | head -1 | sed -E 's/^>{1,2}\|?[[:space:]]*//' || true)
    if [ -z "$tgt" ]; then
      tgt=$(printf '%s' "$line" | grep -oE '(^|[|;&[:space:]])tee[[:space:]]+(-a[[:space:]]+)?[^[:space:];|&<>)]+' | head -1 | sed -E 's/^.*tee[[:space:]]+(-a[[:space:]]+)?//' || true)
    fi
    [ -z "$tgt" ] && continue
    tgt="$(strip_quotes "$tgt")"
    # Content: the echo/printf payload — everything after the last echo/printf
    # word, up to the first pipe or redirect.
    content=$(printf '%s' "$line" | sed -E 's/.*(printf|echo)[[:space:]]+//; s/[[:space:]]*(\||>{1,2}).*$//')
    content="$(strip_quotes "$content")"
    [ -z "$content" ] && continue
    scan_one "$tgt" "$content"
  done <<< "$JOINED"

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
