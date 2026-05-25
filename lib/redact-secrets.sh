#!/usr/bin/env bash
# Secrets sanitization helper.
#
# Spec: skills/_shared/redact-secrets.md
# Pattern set: architecture/M2-memory-layers.md §5.4
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
  _red_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$script_dir/atomic-state-write.sh"
    _RED_ATOMIC_LOADED=1
  fi

  printf '%s' "$line" | atomic_state_append "$log"
}

# Built-in patterns (parallel arrays).
# Order matters: longer prefixes before shorter (sk-ant- before sk-).
# `multiline` flag selects newline-tolerant matching via NUL-substitution.
_RED_NAMES=(
  jwt
  aws-key
  aws-secret
  api-key:sk-ant
  api-key:sk
  api-key:pk_live
  api-key:pk_test
  api-key:ghp
  api-key:xoxb
  bearer
  url-cred
  private-key
)
_RED_REGEXES=(
  'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'
  'AKIA[0-9A-Z]{16}'
  'aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}'
  'sk-ant-[A-Za-z0-9_-]+'
  'sk-[A-Za-z0-9_-]+'
  'pk_live_[A-Za-z0-9_]+'
  'pk_test_[A-Za-z0-9_]+'
  'ghp_[A-Za-z0-9_-]+'
  'xoxb-[A-Za-z0-9_-]+'
  'Bearer [A-Za-z0-9._-]+'
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
  '[REDACTED:api-key:slack-bot]'
  'Bearer [REDACTED:bearer]'
  '\1://[REDACTED:url-cred]@'
  '[REDACTED:private-key]'
)
_RED_MULTILINE=(0 0 0 0 0 0 0 0 0 0 0 1)

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
      names+=("$n")
      regexes+=("$r")
      replacements+=("$repl")
      multiline+=(0)
    done < <(jq -r '.redaction.additional_patterns[]? | [.name, .regex, .replacement] | @tsv' "$sj" 2>/dev/null)
  fi

  local i name regex replacement ml matches total
  for i in "${!names[@]}"; do
    name="${names[$i]}"
    regex="${regexes[$i]}"
    replacement="${replacements[$i]}"
    ml="${multiline[$i]}"

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

    if [ "$ml" = "1" ]; then
      input=$(printf '%s' "$input" | tr '\n' '\001' | sed -E "s|$regex|$replacement|g" | tr '\001' '\n')
    else
      input=$(printf '%s' "$input" | sed -E "s|$regex|$replacement|g")
    fi

    if [ "$total" -gt 0 ] && _red_audit_enabled; then
      _red_audit_append "$producer" "$field" "$name" "$total" "$dedup_key"
    fi
  done

  printf '%s' "$input"
}
