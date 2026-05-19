#!/usr/bin/env bash
# State-file validator.
#
# Spec: skills/_shared/validate-state-file.md
# Tier schema: skills/_shared/state-tier-spec.md
# Design rationale: architecture/M1-state-files.md §Validation helper
#
# API: validate_state_file <target-path>
#   Returns 0 on success.
#   Non-zero on failure; prints structured error to stderr.
#
# YAML parsing strategy (per M1 §Open Q1): shell-line only.
# We never need nested-structure parsing — required-field check is
# key-presence, schema-version is an integer scalar.

# Exit codes
readonly _VSF_OK=0
readonly _VSF_NO_FILE=1
readonly _VSF_NO_FRONTMATTER=2
readonly _VSF_UNCLOSED_FRONTMATTER=3
readonly _VSF_MISSING_BASE_FIELD=4
readonly _VSF_MISSING_TIER_FIELD=5
readonly _VSF_SCHEMA_VERSION_MISMATCH=6
readonly _VSF_CHECKSUM_MISMATCH=7
readonly _VSF_WORKTREE_NOT_FOUND=8
readonly _VSF_BAD_TIER_VALUE=9

readonly _VSF_SUPPORTED_SCHEMA_VERSION=1

# Extract frontmatter block (everything between line-1 `---` and next `---`).
# Prints frontmatter body to stdout; returns non-zero if no closing fence found.
_vsf_extract_frontmatter() {
  local file="$1"
  awk '
    NR == 1 && $0 != "---" { exit 2 }
    NR == 1 { in_fm = 1; next }
    in_fm && $0 == "---" { found_close = 1; exit }
    in_fm { print }
    END { if (!found_close) exit 3 }
  ' "$file"
}

# Extract body (everything after closing `---`).
_vsf_extract_body() {
  local file="$1"
  awk '
    /^---$/ { count++; next }
    count == 2 { print }
  ' "$file"
}

# Check if key is present in frontmatter (case-sensitive, line-anchored).
_vsf_fm_has_key() {
  local fm="$1" key="$2"
  printf '%s\n' "$fm" | grep -qE "^${key}:"
}

# Extract scalar value for a key. Strips surrounding whitespace and quotes.
_vsf_fm_get_value() {
  local fm="$1" key="$2"
  printf '%s\n' "$fm" \
    | awk -v k="$key" '
        $0 ~ "^" k ":" {
          sub("^" k ":[[:space:]]*", "")
          gsub(/^[\"'\'']+|[\"'\'']+$/, "")
          print
          exit
        }
      '
}

validate_state_file() {
  local target="$1"
  if [ -z "$target" ]; then
    echo "validate_state_file: target path required" >&2
    return 64
  fi

  # Step 1: file exists.
  if [ ! -f "$target" ]; then
    echo "validate_state_file: $target — file does not exist" >&2
    return "$_VSF_NO_FILE"
  fi

  # Step 1.5: must start with `---` on line 1.
  local first_line
  IFS= read -r first_line < "$target"
  if [ "$first_line" != "---" ]; then
    echo "validate_state_file: $target — line 1 is not '---' (got: '$first_line')" >&2
    return "$_VSF_NO_FRONTMATTER"
  fi

  # Step 2: parse frontmatter.
  local fm
  fm="$(_vsf_extract_frontmatter "$target")"
  local awk_rc=$?
  if [ "$awk_rc" -eq 2 ]; then
    echo "validate_state_file: $target — line 1 not '---'" >&2
    return "$_VSF_NO_FRONTMATTER"
  elif [ "$awk_rc" -eq 3 ]; then
    echo "validate_state_file: $target — no closing '---' found" >&2
    return "$_VSF_UNCLOSED_FRONTMATTER"
  fi

  # Step 3: common-base required fields.
  local field
  for field in tier producer schema-version branch timestamp; do
    if ! _vsf_fm_has_key "$fm" "$field"; then
      echo "validate_state_file: $target — missing required field '$field' (common base)" >&2
      return "$_VSF_MISSING_BASE_FIELD"
    fi
  done

  # Step 4: tier-specific required fields.
  local tier
  tier="$(_vsf_fm_get_value "$fm" tier)"
  case "$tier" in
    T1)
      for field in phase status non-resumable-actions; do
        if ! _vsf_fm_has_key "$fm" "$field"; then
          echo "validate_state_file: $target — missing required field '$field' (T1 schema)" >&2
          return "$_VSF_MISSING_TIER_FIELD"
        fi
      done
      ;;
    T2)
      if ! _vsf_fm_has_key "$fm" consumer; then
        echo "validate_state_file: $target — missing required field 'consumer' (T2 schema)" >&2
        return "$_VSF_MISSING_TIER_FIELD"
      fi
      ;;
    T3)
      if ! _vsf_fm_has_key "$fm" concurrency; then
        echo "validate_state_file: $target — missing required field 'concurrency' (T3 schema)" >&2
        return "$_VSF_MISSING_TIER_FIELD"
      fi
      ;;
    *)
      echo "validate_state_file: $target — invalid 'tier' value '$tier' (expected T1, T2, or T3)" >&2
      return "$_VSF_BAD_TIER_VALUE"
      ;;
  esac

  # Step 5: schema-version match.
  local sv
  sv="$(_vsf_fm_get_value "$fm" schema-version)"
  if [ "$sv" != "$_VSF_SUPPORTED_SCHEMA_VERSION" ]; then
    echo "validate_state_file: $target — schema-version mismatch (got '$sv', supported '$_VSF_SUPPORTED_SCHEMA_VERSION')" >&2
    return "$_VSF_SCHEMA_VERSION_MISMATCH"
  fi

  # Step 6: checksum (optional).
  if _vsf_fm_has_key "$fm" checksum; then
    local declared actual
    declared="$(_vsf_fm_get_value "$fm" checksum)"
    actual="$(_vsf_extract_body "$target" | sha256sum | awk '{print $1}')"
    if [ "$declared" != "$actual" ]; then
      echo "validate_state_file: $target — checksum mismatch (declared '$declared', computed '$actual')" >&2
      return "$_VSF_CHECKSUM_MISMATCH"
    fi
  fi

  # Step 7 (P-M1-2): worktree path check (optional).
  if _vsf_fm_has_key "$fm" worktree; then
    local wt
    wt="$(_vsf_fm_get_value "$fm" worktree)"
    # Graceful skip if not inside a git repo.
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if ! git worktree list --porcelain 2>/dev/null \
           | awk '/^worktree / {print $2}' \
           | grep -qxF "$wt"; then
        echo "validate_state_file: $target — worktree path '$wt' not found in 'git worktree list' (worktree may have been removed)" >&2
        return "$_VSF_WORKTREE_NOT_FOUND"
      fi
    fi
  fi

  return "$_VSF_OK"
}
