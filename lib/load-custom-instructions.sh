#!/usr/bin/env bash
# Custom-instruction (L4) loader: resolves each instruction file, prints its
# one-line load echo, then lists the absolute path of every file the run must
# Read. Content is never printed: a shell call's output past ~30K characters is
# cut to a preview, and a project's instruction files can total more than that.
#
# Spec: skills/_shared/load-custom-instructions.md
# Counts: lib/instruction-counts.sh (count_instruction_sections /
#   count_additional_steps) — the echo quotes their output, never a tally by eye.
# Memory Backend block: the same `## Memory Backend` section hooks/session-start-restore.sh
#   scans, parsed here for its layer + mode.
#
# API:
#   load_custom_instructions <SKILL_SLUG> <LOAD_TIER>
#       LOAD_TIER pipeline   -> global.md, memory.md, <SKILL_SLUG>.md, code-style.md
#       LOAD_TIER rules-only -> global.md, memory.md
#       Base dir: $GENIRO_INSTRUCTIONS_DIR, then $CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR
#       (flat layout, no fallback; a configured-but-missing dir prints a caveat and
#       the in-repo default applies). Otherwise the current checkout's
#       `.geniro/instructions/<file>` first (its git top level, `$PWD` outside git),
#       then `<_geniro_repo_root>/.geniro/instructions/<file>`.
#       One echo line per file in the load set, then one `Read: <absolute path>`
#       line per file the run must Read. A file not found or unreadable is
#       echoed only; a readable file the counters fail on is echoed as
#       `Loaded … (counts unavailable: …)` and still listed. Everything goes to stdout.
#       Fail-open: rc 0 for any missing or unloadable file. rc 64 (usage error,
#       message on stderr) only for a missing argument or an unknown LOAD_TIER.

if [ -z "${_LCI_DEPS_LOADED:-}" ]; then
  # Cross-shell self-location: BASH_SOURCE is bash-only — sourced under zsh it
  # is empty and the sibling `source` calls below would silently load nothing.
  # zsh names the sourced file via the %x prompt escape; eval keeps the
  # zsh-only syntax out of bash's (and ShellCheck's) parser.
  if [ -n "${BASH_SOURCE:-}" ]; then
    _lci_self="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval '_lci_self="${(%):-%x}"'
  else
    _lci_self="$0"
  fi
  _lci_script_dir="$(cd "$(dirname "$_lci_self")" && pwd)"
  # shellcheck disable=SC1091
  source "$_lci_script_dir/repo-root.sh"
  # shellcheck disable=SC1091
  source "$_lci_script_dir/instruction-counts.sh"
  _LCI_DEPS_LOADED=1
fi

# "<n> <singular>" for 1, "<n> <plural>" otherwise.
_lci_n_label() {
  if [ "${1:-}" = "1" ]; then
    printf '%s %s' "${1:-}" "${2:-}"
  else
    printf '%s %s' "${1:-}" "${3:-}"
  fi
}

# Prints "<layer> <mode>" per entry of the `## Memory Backend` section, nothing
# when the section declares no entry. Fence-aware and HTML-comment-aware: the
# scaffolded memory.md carries its example entry inside `<!-- -->`, which must
# not read as a declared backend. `mode` defaults to mirror when omitted.
_lci_memory_entries() {
  awk '
    BEGIN { in_sec = 0; fence = 0; cm = 0; n = 0 }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^```/) { fence = !fence; next }
      if (fence) { next }
      if (cm) {
        if (match(line, /-->/)) { line = substr(line, RSTART + RLENGTH); cm = 0 } else { next }
      }
      while (match(line, /<!--/)) {
        pre = substr(line, 1, RSTART - 1)
        rest = substr(line, RSTART + 4)
        if (match(rest, /-->/)) { line = pre substr(rest, RSTART + RLENGTH) }
        else { line = pre; cm = 1; break }
      }
      if (line ~ /^## /) {
        heading = line
        sub(/^## /, "", heading)
        gsub(/[ \t]+$/, "", heading)
        in_sec = (tolower(heading) == "memory backend")
        next
      }
      if (!in_sec) { next }
      sub(/[ \t]#.*$/, "", line)
      if (line ~ /^[ \t]*-[ \t]+layer:[ \t]*[^ \t]/) {
        v = line
        sub(/^[ \t]*-[ \t]+layer:[ \t]*/, "", v)
        sub(/[ \t].*$/, "", v)
        n++
        layer[n] = v
        mode[n] = "mirror"
      } else if (n > 0 && line ~ /^[ \t]*(-[ \t]+)?mode:[ \t]*[^ \t]/) {
        v = line
        sub(/^[ \t]*(-[ \t]+)?mode:[ \t]*/, "", v)
        sub(/[ \t].*$/, "", v)
        mode[n] = v
      }
    }
    END { for (i = 1; i <= n; i++) print layer[i], mode[i] }
  ' "${1:-}"
}

# Prints the echo parenthetical for memory.md: the routed layer + mode, or the
# no-backend form. Non-zero when the file cannot be parsed.
_lci_memory_detail() {
  local entries="" out="" entry_layer="" entry_mode=""
  entries="$(_lci_memory_entries "${1:-}")" || return 1
  if [ -z "$entries" ]; then
    printf 'no memory backend declared'
    return 0
  fi
  while read -r entry_layer entry_mode; do
    out="${out:+$out, }$entry_layer → $entry_mode"
  done <<< "$entries"
  printf 'memory backend: %s' "$out"
}

# Prints the echo parenthetical for a rules-bearing file: rules, constraints,
# additional steps with their literal anchor names, data sources. Non-zero when
# either counter cannot open the file.
_lci_counts_detail() {
  local target="${1:-}" counts="" steps="" n_rules="" n_cons="" n_src="" n_steps="" names="" anchors="" nm=""
  local detail=""
  counts="$(count_instruction_sections "$target" 2>/dev/null)" || return 1
  steps="$(count_additional_steps "$target" 2>/dev/null)" || return 1
  read -r n_rules n_cons n_src <<< "$counts"
  n_steps="${steps%%$'\n'*}"

  detail="$(_lci_n_label "$n_rules" rule rules), $(_lci_n_label "$n_cons" constraint constraints)"
  if [ "$n_steps" != "0" ]; then
    names="${steps#*$'\n'}"
    while IFS= read -r nm; do
      anchors="${anchors:+$anchors, }$nm"
    done <<< "$names"
    detail="$detail, $(_lci_n_label "$n_steps" "additional step" "additional steps"): $anchors"
  fi
  if [ "$n_src" != "0" ]; then
    detail="$detail, $(_lci_n_label "$n_src" "data source" "data sources")"
  fi
  printf '%s' "$detail"
}

# Print one file's echo line and queue its path on _LCI_READS.
#   $1 file name   $2 external dir ("" = in-repo mode)   $3 primary root ("" in external mode)
#   $4 "1" when the primary root is a different checkout than the current one
#   $5 the current checkout's root ("" in external mode)
# The resolved file lives in `target`, never `path`: under zsh `path` is tied to
# PATH, so assigning it empties the command search path and the awk calls fail.
_lci_load_one() {
  local file="${1:-}" ext="${2:-}" primary_root="${3:-}" other_checkout="${4:-}" cwd_root="${5:-}"
  local target="" where="" reason="" no_counts="" detail=""

  if [ -n "$ext" ]; then
    where=" from external instructions dir"
    [ -e "$ext/$file" ] && target="$ext/$file"
  elif [ -e "$cwd_root/.geniro/instructions/$file" ]; then
    target="$cwd_root/.geniro/instructions/$file"
  elif [ -n "$primary_root" ] && [ -e "$primary_root/.geniro/instructions/$file" ]; then
    [ -n "$other_checkout" ] && where=" from primary worktree"
    target="$primary_root/.geniro/instructions/$file"
  fi

  if [ -z "$target" ]; then
    printf 'No %s found — skipping.\n' "$file"
    return 0
  fi

  if [ -d "$target" ]; then
    reason="is a directory"
  elif [ ! -f "$target" ]; then
    reason="not a regular file"
  elif [ ! -r "$target" ]; then
    reason="permission denied"
  else
    # Queued before the counters run: a counting failure must not hide a readable file.
    _LCI_READS="${_LCI_READS}Read: $target"$'\n'
    if [ "$file" = "memory.md" ]; then
      detail="$(_lci_memory_detail "$target")" || no_counts="memory backend block not parsed"
    else
      detail="$(_lci_counts_detail "$target")" || no_counts="section counters failed"
    fi
  fi
  if [ -n "$reason" ]; then
    printf 'Failed to load %s: %s — skipping.\n' "$file" "$reason"
    return 0
  fi
  [ -n "$no_counts" ] && detail="counts unavailable: $no_counts"

  printf 'Loaded %s%s (%s).\n' "$file" "$where" "$detail"
  return 0
}

load_custom_instructions() {
  local slug="${1:-}" tier="${2:-}"
  local ext="" primary_root="" other_checkout="" toplevel="" cwd_root=""

  if [ -z "$slug" ] || [ -z "$tier" ]; then
    echo "load_custom_instructions: usage: load_custom_instructions <SKILL_SLUG> <LOAD_TIER>" >&2
    return 64
  fi
  case "$tier" in
    pipeline|rules-only) ;;
    *)
      echo "load_custom_instructions: LOAD_TIER must be 'pipeline' or 'rules-only', got '$tier'" >&2
      return 64
      ;;
  esac

  # Same precedence and tilde expansion as _geniro_instructions_dir() in
  # lib/repo-root.sh, kept inline because a configured-but-missing dir has to be
  # reported, which that function folds silently into the in-repo default.
  ext="${GENIRO_INSTRUCTIONS_DIR:-}"
  [ -z "$ext" ] && ext="${CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR:-}"
  if [ -n "$ext" ]; then
    # shellcheck disable=SC2088  # literal tilde match patterns, not expansions
    case "$ext" in
      "~")   ext="${HOME:-}" ;;
      "~/"*) ext="${HOME:-}/${ext#"~/"}" ;;
    esac
    if [ ! -d "$ext" ]; then
      printf 'External instructions dir %s not found — using in-repo instructions.\n' "$ext"
      ext=""
    else
      case "$ext" in
        /*) ;;
        *)  ext="$PWD/${ext#./}" ;;
      esac
    fi
  fi
  if [ -z "$ext" ]; then
    primary_root="$(_geniro_repo_root)"
    # The first lookup is the current checkout's root, so a subdirectory of a
    # linked worktree still finds that worktree's own files.
    toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || toplevel=""
    cwd_root="${toplevel:-$PWD}"
    # Label the fallback by checkout, not by cwd: a subdirectory of the main
    # checkout resolves that checkout's own file, which is not "primary worktree".
    if [ "$toplevel" != "$(git -C "$primary_root" rev-parse --show-toplevel 2>/dev/null)" ]; then
      other_checkout=1
    fi
  fi

  _LCI_READS=""
  # One call per file, not a loop: each call shells out to awk.
  _lci_load_one global.md "$ext" "$primary_root" "$other_checkout" "$cwd_root"
  _lci_load_one memory.md "$ext" "$primary_root" "$other_checkout" "$cwd_root"
  if [ "$tier" = "pipeline" ]; then
    _lci_load_one "$slug.md" "$ext" "$primary_root" "$other_checkout" "$cwd_root"
    _lci_load_one code-style.md "$ext" "$primary_root" "$other_checkout" "$cwd_root"
  fi
  printf '%s' "$_LCI_READS"
  return 0
}
