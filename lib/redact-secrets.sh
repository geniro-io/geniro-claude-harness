#!/usr/bin/env bash
# Secrets sanitization helper.
#
# Spec: skills/_shared/redact-secrets.md
# Pattern set: ARCHITECTURE.md §Memory Layers
#
# API:
#   printf '%s' "$raw" | redact_secrets <producer> <field> <dedup_key>
#   → emits sanitized text on stdout.
#
# Each pattern that fires emits one JSONL line to
# .geniro/knowledge/.redaction-log.jsonl (if audit_log_enabled).
#
# .geniro/safety.json knobs:
#   { "redaction": {
#       "additional_patterns": [ { "name": "...", "regex": "...", "replacement": "..." } ],
#       "ignore_patterns": [ "high-entropy", ... ],
#       "audit_log_enabled": true
#   } }

# Source the shared repo-root helper once.
if [ -z "${_GENIRO_REPO_ROOT_LOADED:-}" ]; then
  # Cross-shell self-location: BASH_SOURCE is bash-only — sourced under zsh it
  # is empty and the sibling `source` calls below would silently load nothing.
  # zsh names the sourced file via the %x prompt escape; eval keeps the
  # zsh-only syntax out of bash's (and ShellCheck's) parser.
  if [ -n "${BASH_SOURCE:-}" ]; then
    _red_self="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval '_red_self="${(%):-%x}"'
  else
    _red_self="$0"
  fi
  _red_script_dir="$(cd "$(dirname "$_red_self")" && pwd)"
  # shellcheck disable=SC1091
  source "$_red_script_dir/repo-root.sh"
  _GENIRO_REPO_ROOT_LOADED=1
fi

_red_safety_json() {
  local root
  root=$(_geniro_repo_root)
  if [ -f "$root/.geniro/safety.json" ]; then
    echo "$root/.geniro/safety.json"
  fi
}

_red_audit_enabled() {
  local sj
  sj=$(_red_safety_json)
  if [ -z "$sj" ]; then
    return 0
  fi
  # NOTE: do NOT write `.audit_log_enabled // true`. The `//` operator treats
  # boolean `false` the same as `null` (returns the right-hand side), so an
  # explicit `false` setting would silently flip to enabled. Instead read the
  # raw value and only treat the literal string "false" as disabled — anything
  # else (missing, true, null) means enabled.
  local v
  v=$(jq -r '.redaction.audit_log_enabled' "$sj" 2>/dev/null) || return 0
  [ "$v" != "false" ]
}

_red_is_ignored() {
  local name="$1" sj
  sj=$(_red_safety_json)
  [ -z "$sj" ] && return 1
  jq -e --arg n "$name" \
    '(.redaction.ignore_patterns // []) | index($n)' \
    "$sj" >/dev/null 2>&1
}

_red_audit_append() {
  local producer="$1" field="$2" pattern="$3" chars="$4" dedup_key="$5"
  local root log ts line
  root=$(_geniro_repo_root)
  log="$root/.geniro/knowledge/.redaction-log.jsonl"
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  line=$(jq -nc \
    --arg ts "$ts" --arg p "$producer" --arg f "$field" \
    --arg pat "$pattern" --argjson c "$chars" --arg k "$dedup_key" \
    '{ts:$ts,producer:$p,field:$f,pattern:$pat,redacted_chars:$c,entry_dedup_key:$k}')

  mkdir -p "$(dirname "$log")"

  if [ -z "${_RED_ATOMIC_LOADED:-}" ]; then
    # Cross-shell self-location (see the header block) — %x inside a function
    # resolves to the file that defined it, matching BASH_SOURCE semantics.
    local script_dir self
    if [ -n "${BASH_SOURCE:-}" ]; then
      self="${BASH_SOURCE[0]}"
    elif [ -n "${ZSH_VERSION:-}" ]; then
      eval 'self="${(%):-%x}"'
    else
      self="$0"
    fi
    script_dir="$(cd "$(dirname "$self")" && pwd)"
    # shellcheck disable=SC1091
    source "$script_dir/atomic-state-write.sh"
    _RED_ATOMIC_LOADED=1
  fi

  printf '%s' "$line" | atomic_state_append "$log"
}

# Built-in patterns (parallel arrays).
# Order matters: longer prefixes before shorter (sk-ant- before sk-).
# `multiline` flag selects newline-tolerant matching via 0x01-substitution
# (NUL itself cannot survive command substitution, which is why 0x01 is used).
_RED_NAMES=(
  jwt
  aws-key
  aws-secret
  api-key:sk-ant
  api-key:sk
  api-key:pk_live
  api-key:pk_test
  api-key:ghp
  api-key:github-pat
  api-key:gitlab
  api-key:xoxb
  api-key:xox
  api-key:google
  bearer
  url-cred
  private-key
)
_RED_REGEXES=(
  'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'
  'AKIA[0-9A-Z]{16}'
  '[Aa][Ww][Ss]_[Ss][Ee][Cc][Rr][Ee][Tt]_[Aa][Cc][Cc][Ee][Ss][Ss]_[Kk][Ee][Yy][[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}'
  'sk-ant-[A-Za-z0-9_-]+'
  'sk-[A-Za-z0-9_-]+'
  'pk_live_[A-Za-z0-9_]+'
  'pk_test_[A-Za-z0-9_]+'
  'ghp_[A-Za-z0-9_-]+'
  'github_pat_[A-Za-z0-9_]+'
  'glpat-[A-Za-z0-9_-]+'
  'xoxb-[A-Za-z0-9_-]+'
  'xox[a-z]-[A-Za-z0-9_-]+'
  'AIza[0-9A-Za-z_-]{35}'
  '[Bb][Ee][Aa][Rr][Ee][Rr] [A-Za-z0-9._-]+'
  '(https?)://[^:/[:space:]]+:[^@/[:space:]]+@'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----.*-----END [A-Z ]*PRIVATE KEY-----'
)
# Replacement labels — DELIBERATELY use provider names instead of the literal
# secret prefix (`sk-`, `pk_live_`, etc.). If the label contained `sk-ant`,
# the subsequent `sk-` pattern would re-match its own replacement, producing
# nested gibberish like `[REDACTED:api-key:[REDACTED:api-key:openai]]`.
# Provider names break that cycle and stay readable.
_RED_REPLACEMENTS=(
  '[REDACTED:jwt]'
  '[REDACTED:aws-key]'
  'aws_secret_access_key=[REDACTED:aws-secret]'
  '[REDACTED:api-key:anthropic]'
  '[REDACTED:api-key:openai-or-similar]'
  '[REDACTED:api-key:stripe-live]'
  '[REDACTED:api-key:stripe-test]'
  '[REDACTED:api-key:github]'
  '[REDACTED:api-key:github-fine-grained]'
  '[REDACTED:api-key:gitlab]'
  '[REDACTED:api-key:slack-bot]'
  '[REDACTED:api-key:slack]'
  '[REDACTED:api-key:google]'
  'Bearer [REDACTED:bearer]'
  '\1://[REDACTED:url-cred]@'
  '[REDACTED:private-key]'
)
_RED_MULTILINE=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1)

redact_secrets() {
  local producer="${1:-unknown}" field="${2:-unknown}" dedup_key="${3:-unknown}"

  local input
  input="$(cat)"

  if [ -z "$input" ]; then
    return 0
  fi

  # Build the per-run pattern list = built-in + safety.json additional.
  # We never mutate the module-level arrays; we copy into local arrays.
  local -a names=("${_RED_NAMES[@]}")
  local -a regexes=("${_RED_REGEXES[@]}")
  local -a replacements=("${_RED_REPLACEMENTS[@]}")
  local -a multiline=("${_RED_MULTILINE[@]}")

  local sj
  sj=$(_red_safety_json)
  if [ -n "$sj" ]; then
    local n r repl
    while IFS=$'\t' read -r n r repl; do
      [ -z "$n" ] && continue
      # Skip a user pattern whose regex is empty or whose regex/replacement
      # contains a control byte we use internally (\002 sed delimiter, \001
      # multiline newline stand-in). Such a byte would corrupt the s/// command,
      # and the failed sed could blank the whole payload.
      [ -z "$r" ] && continue
      case "$r$repl" in *$'\001'*|*$'\002'*) continue ;; esac
      names+=("$n")
      regexes+=("$r")
      replacements+=("$repl")
      multiline+=(0)
    done < <(jq -r '.redaction.additional_patterns[]? | [.name, .regex, .replacement] | @tsv' "$sj" 2>/dev/null)
  fi

  # Iterate the parallel arrays by counter — `${!names[@]}` is bash-only
  # (zsh expands it to the VALUES, silently mis-iterating). Array index base
  # differs too (bash 0, native zsh 1), so probe it instead of branching on
  # shell: a one-element array answers which base this shell uses.
  local -a _red_probe
  _red_probe=(first)
  local base=1
  [ "${_red_probe[0]:-}" = "first" ] && base=0

  local i name regex replacement ml matches total new delim=$'\002'
  local count="${#names[@]}"
  i=0
  while [ "$i" -lt "$count" ]; do
    name="${names[$((i + base))]}"
    regex="${regexes[$((i + base))]}"
    replacement="${replacements[$((i + base))]}"
    ml="${multiline[$((i + base))]}"
    # Increment BEFORE the `continue`s below — after them it would be skipped
    # and the loop would spin forever on the same index.
    i=$((i + 1))

    if _red_is_ignored "$name"; then
      continue
    fi

    total=0
    # `-e <regex>` is required because some patterns start with `-` (e.g. the
    # PEM `-----BEGIN ... PRIVATE KEY-----` regex), which `grep -oE "$regex"`
    # would otherwise misinterpret as a CLI option flag.
    if [ "$ml" = "1" ]; then
      # Multiline: collapse newlines to NUL byte for sed/grep, restore after.
      matches=$(printf '%s' "$input" | tr '\n' '\001' | grep -oE -e "$regex" 2>/dev/null || true)
    else
      matches=$(printf '%s' "$input" | grep -oE -e "$regex" 2>/dev/null || true)
    fi

    if [ -z "$matches" ]; then
      continue
    fi

    local m
    while IFS= read -r m; do
      total=$((total + ${#m}))
    done <<< "$matches"

    # Control-char (\002) sed delimiter so a user pattern containing `|` can't
    # break the s/// command. Guard the assignment: if sed exits non-zero
    # (malformed user regex), keep the prior input rather than blanking it.
    if [ "$ml" = "1" ]; then
      new=$(printf '%s' "$input" | tr '\n' '\001' \
        | sed -E "s${delim}${regex}${delim}${replacement}${delim}g") \
        && input=$(printf '%s' "$new" | tr '\001' '\n')
    else
      new=$(printf '%s' "$input" | sed -E "s${delim}${regex}${delim}${replacement}${delim}g") \
        && input="$new"
    fi

    if [ "$total" -gt 0 ] && _red_audit_enabled; then
      _red_audit_append "$producer" "$field" "$name" "$total" "$dedup_key"
    fi
  done

  printf '%s' "$input"
}
