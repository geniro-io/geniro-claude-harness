#!/usr/bin/env bash
# block-geniro-force-add.sh
# PreToolUse hook for Bash — blocks `git add -f` / `--force` (and the plumbing
# twin `git update-index --force`) on .geniro/ paths.
#
# Force-adding a gitignored file puts it in the IDE's Source Control panel,
# where one "Discard All Changes" click deletes it (real incident: a Cursor SCM
# discard wiped force-added .geniro/actions/*.md). To track a .geniro/ subdir,
# negate it in .gitignore instead: `!.geniro/actions/` plus `!.geniro/actions/**`.
#
# The one check kept from block-geniro-deletion.sh, which was deleted on
# 2026-09-29 together with the other command-string guards (HOOKS.md §Removed
# guards). It stays deliberately literal: it reads the command as written and
# does not follow variables, `bash -c` payloads, or interpreter calls — the
# deleted guards chased those and blocked read-only commands far more often
# than they caught a real write.
#
# Bypass: add "git-add-force-geniro" to allow_patterns in .geniro/safety.json.

set -uo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"Geniro force-add guard inactive: jq not found on PATH, so git add -f on .geniro/ is NOT being checked. Install jq to restore it."}\n'
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)

# Nothing to check unless both words appear. -i: macOS resolves `GIT` like
# `git`, and `.GENIRO` is the same directory on a case-insensitive filesystem.
grep -qi 'git' <<< "$COMMAND" || exit 0
grep -qi '\.geniro' <<< "$COMMAND" || exit 0

# Heredoc bodies are data (a handoff that MENTIONS the rule is not a force-add),
# so drop them. Then join backslash-newline continuations, and blank quoted
# spans that contain whitespace — prose such as a commit message — while a
# whitespace-free quoted path (`".geniro/x"`) survives. A quoted span may not
# cross ; & | so two stray apostrophes cannot swallow a live command between them.
SCANNED=$(printf '%s\n' "$COMMAND" | awk '
  tag != "" { t = $0; if (strip) sub(/^\t+/, "", t); if (t == tag) tag = ""; next }
  {
    print
    if (match($0, /(^|[^<])<<-?[ \t]*["'"'"'\\]?[A-Za-z_][A-Za-z0-9_]*/)) {
      h = substr($0, RSTART, RLENGTH)
      sub(/^[^<]?<</, "", h)
      strip = (h ~ /^-/)
      sub(/^-?[ \t]*["'"'"'\\]?/, "", h)
      tag = h
    }
  }' | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }' \
  | sed -E "s/\"[^\";&|]*[[:space:]][^\";&|]*\"/\"\"/g; s/'[^';&|]*[[:space:]][^';&|]*'/''/g")

find_safety_json() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    [ -f "$dir/.geniro/safety.json" ] && { echo "$dir/.geniro/safety.json"; return 0; }
    dir=$(dirname "$dir")
  done
  # A linked worktree never carries the gitignored .geniro/ — fall back to the
  # main checkout, which prints its common dir as an absolute `<main>/.git`.
  dir=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$dir" in
    /*/.git) [ -f "${dir%/.git}/.geniro/safety.json" ] && { echo "${dir%/.git}/.geniro/safety.json"; return 0; } ;;
  esac
  return 1
}

# Returns 0 when one command segment force-adds a .geniro/ path.
segment_force_adds_geniro() {
  local -a toks
  read -r -a toks <<< "$1"
  local i=0 n=${#toks[@]} low
  # Locate the git word (any case, bare or path-qualified).
  while [ "$i" -lt "$n" ]; do
    low=$(printf '%s' "${toks[$i]}" | tr '[:upper:]' '[:lower:]' | tr -d "\"'")
    [ "${low##*/}" = "git" ] && break
    i=$((i + 1))
  done
  [ "$i" -lt "$n" ] || return 1
  i=$((i + 1))
  # Skip git's global options; these take their value as the next word.
  while [ "$i" -lt "$n" ]; do
    case "${toks[$i]}" in
      -C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 1
  case "${toks[$i]}" in add|update-index) ;; *) return 1 ;; esac
  i=$((i + 1))
  # `--force` is git add's only long option starting with `f`, so every
  # unambiguous prefix (`--f` … `--forc`) is the same flag.
  local re_force='^-[a-zA-Z]*f[a-zA-Z]*$|^--f(o(r(c(e)?)?)?)?$'
  local re_geniro='(^|[/:)])\.geniro(/|$)'
  local force=0 geniro=0 opts=1 tok path
  while [ "$i" -lt "$n" ]; do
    tok=${toks[$i]}
    if [ "$opts" -eq 1 ] && [ "$tok" = "--" ]; then
      opts=0
    elif [ "$opts" -eq 1 ] && [[ $tok =~ $re_force ]]; then
      force=1
    else
      path=$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]' | tr -d "\"'")
      [[ $path =~ $re_geniro ]] && geniro=1
    fi
    i=$((i + 1))
  done
  [ "$force" -eq 1 ] && [ "$geniro" -eq 1 ]
}

while IFS= read -r SEGMENT; do
  [ -z "$SEGMENT" ] && continue
  segment_force_adds_geniro "$SEGMENT" || continue
  SAFETY_FILE=$(find_safety_json 2>/dev/null || true)
  if [ -n "$SAFETY_FILE" ] && jq -e '(.allow_patterns // []) | index("git-add-force-geniro")' "$SAFETY_FILE" >/dev/null 2>&1; then
    exit 0
  fi
  {
    echo "Geniro safety blocked [git-add-force-geniro]: git add -f on .geniro/ paths puts ignored files in the IDE's Source Control panel, where one 'Discard All Changes' click deletes them."
    echo "Track a .geniro/ subdir by negating it in .gitignore instead (e.g. \`!.geniro/actions/\` and \`!.geniro/actions/**\`), then use a plain \`git add\`."
    if [ -n "$SAFETY_FILE" ]; then
      echo "To allow it anyway, add \"git-add-force-geniro\" to allow_patterns in $SAFETY_FILE"
    else
      echo "To allow it anyway, create .geniro/safety.json with: {\"allow_patterns\": [\"git-add-force-geniro\"]}"
    fi
  } >&2
  exit 2
done <<< "$(printf '%s\n' "$SCANNED" | tr ';&|()`' '\n\n\n\n\n\n')"

exit 0
