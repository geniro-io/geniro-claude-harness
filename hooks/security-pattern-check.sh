#!/usr/bin/env bash
# security-pattern-check.sh — PreToolUse Edit|Write|MultiEdit|NotebookEdit
#
# Cheap regex scan for high-signal, low-false-positive security anti-patterns
# in file content. Hard-block (exit 2) on pattern hit; per-pattern bypass via
# .geniro/safety.json allow_patterns.
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
#   sec-curl-pipe-sh     curl | sh / wget | sh — supply-chain risk
#   sec-tls-bypass       verify=False / rejectUnauthorized: false / --insecure
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

# This scan is implemented in Perl (PCRE). If perl is absent the scan cannot run;
# say so and exit 0 rather than silently passing every edit — otherwise a
# perl-less host looks "clean" when the guard is actually inert.
if ! command -v perl >/dev/null 2>&1; then
  echo "[security-pattern-check] perl not found — security scan skipped on this host." >&2
  exit 0
fi

# Lowercased extension (no leading dot). Filenames without a dot get the
# whole filename as ext — fine, won't match the ext-list filter.
filename="${FILE_PATH##*/}"
ext_lower=""
if [[ "$filename" == *.* ]]; then
  ext_lower="${filename##*.}"
  ext_lower="$(printf '%s' "$ext_lower" | tr '[:upper:]' '[:lower:]')"
fi
# Dockerfile / Makefile detection by basename.
basename_lower="$(printf '%s' "$filename" | tr '[:upper:]' '[:lower:]')"
case "$basename_lower" in
  dockerfile|dockerfile.*|*.dockerfile) ext_lower="dockerfile" ;;
esac

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

# ----- Pattern definitions (order: more specific first) -----

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

# 5. curl|wget piped to sh/bash. The [^|\n]* spans stay within one physical
#    line (a backslash-newline continuation is explicitly allowed by the middle
#    group), so a curl on line 1 and an unrelated pipe-to-shell lines later can
#    no longer false-positive across the -0777 slurp. The optional wrapper group
#    catches `| sudo bash`, `| env VAR=1 sh`, `| command zsh`, and absolute
#    shell paths (`| /bin/sh`).
check "sec-curl-pipe-sh" "sh bash zsh dockerfile" \
  "curl/wget piped to shell — supply-chain risk (download, verify checksum/signature, then execute)" \
  '(curl|wget)\b[^|\n]*(\\\n[^|\n]*)*\|\s*((sudo|doas)(\s+-\S+)*\s+|command\s+|env(\s+\S+=\S*)*\s+)?(\S*/)?(sh|bash|zsh|dash|ksh)\b'

# 6. TLS bypass
check "sec-tls-bypass" "py pyw pyx pyi" \
  "verify=False — TLS certificate verification disabled" \
  '\bverify\s*=\s*False\b'

check "sec-tls-bypass" "js jsx ts tsx mjs cjs" \
  "rejectUnauthorized: false — TLS certificate verification disabled" \
  '\brejectUnauthorized\s*:\s*false\b'

check "sec-tls-bypass" "sh bash zsh dockerfile" \
  "--insecure / --no-check-certificate — TLS certificate verification disabled" \
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

# No pattern matched — allow.
exit 0
