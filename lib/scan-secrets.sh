#!/usr/bin/env bash
# Credential-shape scanner. Reuses the pattern battery of lib/redact-secrets.sh
# (single source of the regexes) in report-only mode.
#
# Usage: scan-secrets.sh <file|dir> [...]
# Output: one `path:line<TAB>pattern-name` per hit. The matched value is never
#         printed. Multi-line patterns (private-key) report their opening line.
# Exit:   0 no hits, 1 hits, 2 usage error (no args, unreadable path).

# Executable only: sourced (as tests/memory/zsh-source-compat.sh does for every
# lib/*.sh) it defines nothing and returns. zsh marks a sourced file with
# ":file" in ZSH_EVAL_CONTEXT; bash with BASH_SOURCE[0] != $0.
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-toplevel}" in *:file*) return 0 ;; esac
elif [ "${BASH_SOURCE[0]:-}" != "${0:-}" ]; then
  return 0
fi

set -u

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$self_dir/redact-secrets.sh"

if [ "$#" -eq 0 ]; then
  echo "usage: scan-secrets.sh <file|dir> [...]" >&2
  exit 2
fi

files=()
for p in "$@"; do
  if [ -d "$p" ]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$p" -type f -not -path '*/.git/*' | LC_ALL=C sort)
  elif [ -f "$p" ] && [ -r "$p" ]; then
    files+=("$p")
  else
    echo "scan-secrets.sh: not a readable file or directory: $p" >&2
    exit 2
  fi
done

hits=0
for f in ${files[@]+"${files[@]}"}; do
  i=0
  while [ "$i" -lt "${#_RED_NAMES[@]}" ]; do
    re="${_RED_REGEXES[$i]}"
    # A multi-line pattern spans lines; match its opening line only.
    [ "${_RED_MULTILINE[$i]}" = "1" ] && re="${re%%.\**}"
    # `cut` drops grep's matched text, so the value never reaches the output.
    nums=$(LC_ALL=C grep -anE -e "$re" "$f" 2>/dev/null | cut -d: -f1)
    for n in $nums; do
      printf '%s:%s\t%s\n' "$f" "$n" "${_RED_NAMES[$i]}"
      hits=$((hits + 1))
    done
    i=$((i + 1))
  done
done

[ "$hits" -eq 0 ]
