#!/usr/bin/env bash
# Mechanical half of /geniro:implement Ship's review-coverage guard.
#
# Spec: skills/implement/implement-reference.md §"Commit + Push + PR" Step 2.
# The set comparison and the hash comparison are decidable by a command; whether
# a diverged file's edit touches production lines stays orchestrator judgment.
#
# API: review_coverage_diverged <state.md> [changed-file ...]
#   Compares the changed files (arguments; none means an empty set) and the
#   state.md frontmatter lists `reviewed_file_set` and `reviewed_file_hashes`
#   (entries `<path>@<git hash-object>`), both read from the current directory.
#   Prints one TAB-separated `path  reason` line per diverged file:
#     unreviewed  changed file absent from reviewed_file_set
#     nohash      in reviewed_file_set but has no reviewed_file_hashes entry
#     modified    current git hash-object differs from the recorded hash
#     deleted     file no longer exists
#   Every reviewed file is hash-checked, not just the changed ones.
#   rc 0  — nothing diverged
#   rc 1  — at least one file diverged
#   rc 2  — usage or parse error (no state.md, unreadable, a list key missing
#           or not a flow `[a, b]` / block `- a` list)
#
# Lists parse in YAML flow form (`[a, b]`, `[]`) and block form (`- a` lines).
# Paths containing commas or newlines are not supported.
#
# Portability: bash 3.2, no arrays, no GNU-only flags; sourceable from zsh.

# Print the items of frontmatter list <key>, one per line. rc 2 if key absent.
_rc_list() {
  awk -v key="$2" '
    NR == 1 { if ($0 != "---") exit 3; next }
    $0 == "---" { exit found ? 0 : 3 }
    inlist && /^[ \t]*-[ \t]/ { sub(/^[ \t]*-[ \t]+/, ""); emit($0); next }
    inlist && /^[ \t]*$/ { next }
    { inlist = 0 }
    index($0, key ":") == 1 {
      found = 1
      v = substr($0, length(key) + 2)
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      if (v == "") { inlist = 1; next }
      if (v ~ /^\[.*\]$/) {
        v = substr(v, 2, length(v) - 2)
        n = split(v, parts, ",")
        for (i = 1; i <= n; i++) emit(parts[i])
        next
      }
      exit 3
    }
    function emit(s) {
      sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
      if (s ~ /^".*"$/ || s ~ /^'"'"'.*'"'"'$/) s = substr(s, 2, length(s) - 2)
      if (s != "") print s
    }
    END { if (!found) exit 3 }
  ' "$1"
}

review_coverage_diverged() {
  if [ "$#" -lt 1 ] || [ ! -f "$1" ] || [ ! -r "$1" ]; then
    echo "review_coverage_diverged: usage: <state.md> [changed-file ...]" >&2
    return 2
  fi
  _rc_state="$1"
  shift
  _rc_set=$(_rc_list "$_rc_state" reviewed_file_set) || {
    echo "review_coverage_diverged: reviewed_file_set missing or malformed in $_rc_state" >&2
    return 2
  }
  _rc_hashes=$(_rc_list "$_rc_state" reviewed_file_hashes) || {
    echo "review_coverage_diverged: reviewed_file_hashes missing or malformed in $_rc_state" >&2
    return 2
  }

  _rc_out=""
  _rc_seen="
"
  # Changed files absent from the reviewed set.
  for _rc_f in "$@"; do
    case "
$_rc_set
" in
      *"
$_rc_f
"*) ;;
      *) _rc_out="${_rc_out}${_rc_f}	unreviewed
"
         _rc_seen="${_rc_seen}${_rc_f}
" ;;
    esac
  done
  # Every reviewed file: recorded hash vs current content.
  while IFS= read -r _rc_f; do
    [ -n "$_rc_f" ] || continue
    case "$_rc_seen" in *"
$_rc_f
"*) continue ;; esac
    _rc_want=""
    while IFS= read -r _rc_e; do
      [ -n "$_rc_e" ] || continue
      if [ "${_rc_e%@*}" = "$_rc_f" ]; then _rc_want="${_rc_e##*@}"; fi
    done <<EOF2
$_rc_hashes
EOF2
    if [ -z "$_rc_want" ]; then
      _rc_out="${_rc_out}${_rc_f}	nohash
"
    elif [ ! -f "$_rc_f" ]; then
      _rc_out="${_rc_out}${_rc_f}	deleted
"
    else
      _rc_have=$(git hash-object -- "$_rc_f" 2>/dev/null) || _rc_have=""
      [ "$_rc_have" = "$_rc_want" ] || _rc_out="${_rc_out}${_rc_f}	modified
"
    fi
  done <<EOF2
$_rc_set
EOF2

  if [ -n "$_rc_out" ]; then
    printf '%s' "$_rc_out"
    return 1
  fi
  return 0
}
