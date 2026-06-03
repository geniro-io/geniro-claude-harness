#!/usr/bin/env bash
# L3 semantic-memory read helper + fingerprint drift detection.
#
# Spec: skills/_shared/load-semantic.md
# L3 layout & cadence: ARCHITECTURE.md §Memory Layers
#
# API:
#   load_semantic [--extras "name1 name2 ..."] [--quiet]
#       Loads default L3 files (top-2: _project.md + _CODEBASE_MAP.md)
#       and any extras, emits concatenated content to stdout. Soft drift
#       warning to stderr if .fingerprint.json diverges from current files
#       (never auto-overwrites per M2 §6.2).
#
#   update_fingerprint [<path1> <path2> ...]
#       Recomputes hashes for the given files (or a sensible default
#       fingerprint set if none given) and writes
#       .geniro/planning/.fingerprint.json atomically via atomic_state_write.

if [ -z "${_LS_DEPS_LOADED:-}" ]; then
  _ls_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "$_ls_script_dir/repo-root.sh"
  # shellcheck disable=SC1091
  source "$_ls_script_dir/atomic-state-write.sh"
  # shellcheck disable=SC1091
  source "$_ls_script_dir/hash.sh"
  _LS_DEPS_LOADED=1
fi

# Default fingerprint candidates — every file from this list that EXISTS in
# the repo gets hashed by `update_fingerprint` when called with no args.
# Languages covered intentionally biased toward JS/TS (the plugin's primary
# target audience); Python/Rust/Go candidates included for portability.
_LS_DEFAULT_FINGERPRINT_FILES=(
  "package.json"
  "pnpm-lock.yaml"
  "tsconfig.json"
  "vite.config.ts"
  "vite.config.js"
  "next.config.ts"
  "next.config.js"
  "pyproject.toml"
  "requirements.txt"
  "Cargo.toml"
  "go.mod"
)

# Hash one file; emit `sha256:<hex>` or empty if missing / no hasher.
_ls_hash_file() {
  local path="$1" h
  if [ -f "$path" ]; then
    h="$(_geniro_sha256 "$path" 2>/dev/null | awk '{print $1}')"
    # Emit the prefix only with a real digest. A degraded host with no hasher
    # otherwise yields a bogus `sha256:` (empty) that reads as a fingerprint
    # change on every load — false drift. Empty hash is skipped downstream.
    [ -n "$h" ] && printf 'sha256:%s' "$h"
  fi
}

# Compare current hashes against .fingerprint.json.
# Emits drift warning to stderr (one block per diverged file).
# Returns 0 always — drift is informational, never fatal.
_ls_check_drift() {
  local root="$1"
  local fp="$root/.geniro/planning/.fingerprint.json"

  if [ ! -f "$fp" ]; then
    return 0
  fi

  local diverged=()
  local captured_at
  captured_at=$(jq -r '.captured_at // "(unknown)"' "$fp" 2>/dev/null)

  local entry
  while IFS= read -r entry; do
    local path expected actual
    path=$(printf '%s' "$entry" | jq -r .key)
    expected=$(printf '%s' "$entry" | jq -r .value)

    if [ -f "$root/$path" ]; then
      actual=$(_ls_hash_file "$root/$path")
      if [ -n "$actual" ] && [ "$actual" != "$expected" ]; then
        diverged+=("$path")
      fi
    fi
  done < <(jq -c '.files // {} | to_entries[]' "$fp" 2>/dev/null)

  if [ "${#diverged[@]}" -gt 0 ]; then
    local list
    list=$(printf ', %s' "${diverged[@]}")
    list="${list:2}"
    echo "[L3 drift] Tech stack fingerprint diverged — $list changed since fingerprint captured on $captured_at." >&2
    echo "[L3 drift] Consider re-running /geniro:onboard. Continuing with current memory." >&2
  fi
  return 0
}

load_semantic() {
  local extras=""
  local quiet=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --extras) extras="$2"; shift 2 ;;
      --quiet)  quiet=true; shift ;;
      *)
        echo "load_semantic: unknown flag '$1'" >&2
        return 64
        ;;
    esac
  done

  local root
  root=$(_geniro_repo_root)

  if [ "$quiet" = "false" ]; then
    _ls_check_drift "$root"
  fi

  # Default top-2 per M2 §6.4 + any extras.
  local -a names=("_project" "_CODEBASE_MAP")
  if [ -n "$extras" ]; then
    # `read -ra` splits on IFS (default whitespace) into the array WITHOUT
    # glob-expanding tokens. Bare `for e in $extras` would word-split AND
    # glob-expand against cwd — a token like `_focus-*` would expand to
    # matching files instead of staying literal.
    local -a extras_arr
    IFS=' ' read -ra extras_arr <<< "$extras"
    local e
    for e in "${extras_arr[@]}"; do
      [ -z "$e" ] && continue
      # Accept either bare name or with leading underscore.
      case "$e" in
        _*) names+=("$e") ;;
        *)  names+=("_$e") ;;
      esac
    done
  fi

  local n path
  for n in "${names[@]}"; do
    path="$root/.geniro/planning/${n}.md"
    if [ -f "$path" ]; then
      printf '=== file: .geniro/planning/%s.md ===\n' "$n"
      cat "$path"
      printf '\n'
    fi
  done
}

update_fingerprint() {
  local root
  root=$(_geniro_repo_root)
  local fp="$root/.geniro/planning/.fingerprint.json"

  # Collect files to hash: explicit args, or every default candidate that
  # actually exists at repo root.
  local -a candidates=()
  if [ "$#" -gt 0 ]; then
    candidates=("$@")
  else
    local c
    for c in "${_LS_DEFAULT_FINGERPRINT_FILES[@]}"; do
      [ -f "$root/$c" ] && candidates+=("$c")
    done
  fi

  if [ "${#candidates[@]}" -eq 0 ]; then
    # Nothing to fingerprint — drop a stub fingerprint so callers can still
    # detect "we've run setup" via file presence.
    local ts_only
    ts_only=$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{captured_at:$ts, files:{}}')
    printf '%s\n' "$ts_only" | atomic_state_write "$fp"
    return 0
  fi

  local kv_pairs
  kv_pairs=$(jq -nc '{}')
  local c hash
  for c in "${candidates[@]}"; do
    hash=$(_ls_hash_file "$root/$c")
    if [ -n "$hash" ]; then
      kv_pairs=$(printf '%s' "$kv_pairs" | jq -c --arg p "$c" --arg h "$hash" '. + {($p):$h}')
    fi
  done

  local ts payload
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  payload=$(jq -nc --arg ts "$ts" --argjson files "$kv_pairs" '{captured_at:$ts, files:$files}')
  printf '%s\n' "$payload" | atomic_state_write "$fp"
}
