#!/usr/bin/env bash
# Mechanical half of the MIGRATION.md walk: parse every `### <name>` entry,
# run its `Auto-detect:` command, classify the entry.
#
# Spec: skills/_shared/migration-walk.md (apply policy stays with the consumer)
# Entry format: MIGRATION.md preamble.
#
# API: migration_walk <migration-md-path> [project-dir]
#   Runs each detector with project-dir (default: cwd) as its working
#   directory and prints one TAB-separated `title  class  detail` row per
#   entry, in file order. class is one of:
#     applies         detector printed output (detail = its first line)
#     not-applicable  detector printed nothing, or the entry has no detector
#     informational   Auto-detect value begins with N/A (any case) — never run
#     detector-error  detector is not valid bash, or exited 126+ with no
#                     output (detail = first stderr line or the exit code)
#   rc 0  — walked every entry
#   rc 64 — no path passed (EX_USAGE)
#   rc 65 — path is not a readable file, or project-dir is not a directory
#   rc 66 — file has no `### ` entries, or ends inside an unterminated fence
#
# Safety: every detector runs in its own `bash -c` child with stdin closed, so
# nothing it does (cd, set -e, exit, unmatched globs) reaches the caller's
# shell, and one failing detector never stops the walk.
#
# Portability: bash 3.2 / BSD userland, sourceable from zsh. No arrays, no
# process substitution, no GNU-only flags.

if [ -z "${_MW_DEPS_LOADED:-}" ]; then
  readonly _MW_NO_TARGET=64
  readonly _MW_UNREADABLE=65
  readonly _MW_UNPARSEABLE=66
  _MW_DEPS_LOADED=1
fi

# Split the file into <dir>/NNNN.title and <dir>/NNNN.cmd (the .cmd exists only
# for an entry carrying an Auto-detect value). Accepts the three shapes
# MIGRATION.md uses: a fenced block after a bare marker, an inline backtick
# span, and plain text (N/A prose).
_mw_split() {  # <file> <dir>
  awk -v dir="$2" '
    function flush() { if (cmdf != "") close(cmdf); cmdf = "" }
    /^```/ && infence {
      infence = 0; armed = 0; flush(); next
    }
    infence { print > cmdf; next }
    /^### / {
      flush(); armed = 0; n++
      t = substr($0, 5); gsub(/\t/, " ", t)
      f = sprintf("%s/%04d.title", dir, n); print t > f; close(f)
      cmdf = ""; next
    }
    n > 0 && /^\*\*Auto-detect:\*\*/ {
      rest = $0; sub(/^\*\*Auto-detect:\*\*[ \t]*/, "", rest)
      cmdf = sprintf("%s/%04d.cmd", dir, n)
      if (rest == "") { armed = 1; printf "" > cmdf; next }
      if (rest ~ /^`.*`[ \t]*$/) { sub(/^`/, "", rest); sub(/`[ \t]*$/, "", rest) }
      print rest > cmdf; flush(); next
    }
    armed && /^```/ { infence = 1; armed = 0; next }
    END { if (infence) exit 3; if (n == 0) exit 4 }
  ' "$1"
}

migration_walk() {
  local file="${1:-}" pdir="${2:-.}" tmp rc idx title cmdf kind out err detail

  [ -n "$file" ] || return "$_MW_NO_TARGET"
  [ -f "$file" ] && [ -r "$file" ] || return "$_MW_UNREADABLE"
  [ -d "$pdir" ] || return "$_MW_UNREADABLE"

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/migration-walk.XXXXXX")" || return "$_MW_UNREADABLE"

  rc=0
  _mw_split "$file" "$tmp" || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -rf "$tmp"
    return "$_MW_UNPARSEABLE"
  fi

  for title in "$tmp"/*.title; do
    idx="${title%.title}"
    cmdf="$idx.cmd"
    kind="not-applicable"
    detail=""
    if [ -s "$cmdf" ]; then
      # N/A (any case) is prose: it must never reach a shell.
      if head -n 1 "$cmdf" | grep -qi '^[[:space:]]*n/a'; then
        kind="informational"
      elif ! bash -n "$cmdf" 2>"$idx.err"; then
        kind="detector-error"
        detail="$(head -n 1 "$idx.err")"
      else
        rc=0
        ( cd "$pdir" && bash "$cmdf" </dev/null >"$idx.out" 2>"$idx.err" ) || rc=$?
        out="$(head -n 1 "$idx.out" 2>/dev/null)"
        if [ -s "$idx.out" ]; then
          kind="applies"; detail="$out"
        elif [ "$rc" -ge 126 ]; then
          kind="detector-error"
          err="$(head -n 1 "$idx.err")"
          detail="${err:-exit $rc}"
        fi
      fi
    fi
    detail="$(printf '%s' "$detail" | tr '\t\r' '  ')"
    printf '%s\t%s\t%s\n' "$(cat "$title")" "$kind" "$detail"
  done

  rm -rf "$tmp"
  return 0
}
