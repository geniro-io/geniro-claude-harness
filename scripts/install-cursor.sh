#!/usr/bin/env bash
# install-cursor.sh — install Geniro into the Cursor USER PROFILE, the only
# place both Cursor surfaces read from:
#
#     skills  -> ~/.cursor/skills/geniro-*        symlinks into cursor/skills/
#     agents  -> ~/.cursor/agents/<name>.md       symlinks into cursor/agents/
#     hooks   -> ~/.cursor/hooks.json             our entries merged in
#
# WHY THIS EXISTS. `cursor-agent` — the CLI, and therefore ACP, which is the
# same binary over stdio — does not load PLUGINS at all. Not from the Cursor
# marketplace, not from ~/.cursor/plugins/local/, not via `--plugin-dir`, not
# through the Claude Code compatibility cache. Cursor staff put it plainly:
# "plugins are not currently working in the CLI" (forum.cursor.com/t/158947).
# That is plugin-WIDE, not skills-only: under a plugin install a cursor-agent
# session gets no Geniro skills, no Geniro subagents, and — the part that bites
# hardest — none of the safety hooks. The IDE loads all three; the CLI loads
# none. Measured 2026-08-26 against cursor-agent 2026.08.11-e8db854.
#
# The fix is to stop shipping through the plugin and use the per-component user
# directories the CLI does read, all three documented and all three shared with
# the user's own config:
#
#     ~/.cursor/skills/     cursor.com/docs/skills
#     ~/.cursor/agents/     cursor.com/docs/subagents   ("editor, CLI, and Cloud Agents")
#     ~/.cursor/hooks.json  cursor.com/docs/hooks       (merged, User priority)
#
# THIS ROUTE AND A PLUGIN INSTALL ARE MUTUALLY EXCLUSIVE. Cursor performs no
# deduplication across skill sources — it scans every known directory and loads
# every SKILL.md it finds, staff-confirmed and unfixed
# (forum.cursor.com/t/150137). With both routes live the IDE lists every skill
# twice and pays for both descriptions in its system prompt. §Conflicting
# plugin install below warns when it sees one; there is no config that merges
# them.
#
# EVERY DESTINATION IS SHARED, so this script only ever touches what it owns —
# a symlink whose target lies in some checkout's cursor/skills/ or
# cursor/agents/, and a hooks.json entry invoking cursor/hooks/claude-hook-shim.sh.
# Anything else under one of our names is left alone and reported, and
# --uninstall removes exactly what install created, links left dangling by a
# moved checkout included.
#
# THE LINK TARGET MUST NOT CARRY A VERSION. Under Claude Code this script is
# usually invoked from the versioned install cache
# (~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/), and a link into
# that path is dead the moment the next version lands. The marketplace checkout
# beside it — ~/.claude/plugins/marketplaces/<marketplace>/ — holds the same
# plugin at a path with no version in it and is refreshed in place by
# `claude plugin marketplace update`, so §Resolve a version-independent source
# below redirects there and the installation stays live across every update with
# nothing to re-run. A git checkout is already version-independent and is used
# as-is.
#
# Usage: scripts/install-cursor.sh [--uninstall]
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install-cursor.sh [--uninstall]

  (no flag)     link cursor/skills/ and cursor/agents/ into ~/.cursor/,
                and merge cursor/hooks.json into ~/.cursor/hooks.json
  --uninstall   remove exactly what install created, and nothing else

Read the header of this file for why the Cursor plugin install does not cover
the CLI, and why the two routes must not both be active.
USAGE
}

MODE=install
case "${1:-}" in
  ''            ) ;;
  --uninstall   ) MODE=uninstall ;;
  -h|--help     ) usage; exit 0 ;;
  *             ) usage >&2; exit 2 ;;
esac

SELF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DEST="$HOME/.cursor/skills"
AGENTS_DEST="$HOME/.cursor/agents"
HOOKS_DEST="$HOME/.cursor/hooks.json"

# The marker that makes a hooks.json entry ours. Every Geniro hook runs through
# the shim, and no other tool's entry would name that path.
SHIM_MARKER='/cursor/hooks/claude-hook-shim\.sh'

# The first "name" in a plugin manifest is the plugin's own; author.name comes
# later, so the first match is the right one.
plugin_name_of() {
  local manifest="$1/.claude-plugin/plugin.json"
  [ -f "$manifest" ] || return 1
  sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -1
}

# Resolve a version-independent source root: the marketplace checkout that holds
# this same plugin. Match by manifest name rather than by directory name — a
# marketplace repo may host several plugins under plugins/<name>/, and its
# directory is named after the marketplace, not the plugin.
find_stable_root() {
  local want="$1" cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" mp manifest cand
  [ -d "$cfg/plugins/marketplaces" ] || return 1
  for mp in "$cfg"/plugins/marketplaces/*/; do
    [ -d "$mp" ] || continue
    while IFS= read -r manifest; do
      cand="$(cd "$(dirname "$manifest")/.." && pwd)"
      [ -d "$cand/cursor/skills" ] || continue
      [ "$(plugin_name_of "$cand")" = "$want" ] || continue
      printf '%s\n' "$cand"
      return 0
    done < <(find "$mp" -maxdepth 4 -path '*/.claude-plugin/plugin.json' -type f 2>/dev/null)
  done
  return 1
}

# A link is ours when its target path ends in /cursor/<kind>/<name> — the layout
# only scripts/build-cursor-{skills,agents}.sh produce. The test reads the LINK
# STRING rather than the resolved file, so a link whose checkout has since moved
# or been deleted is still recognisably ours; that dangling case is the one
# --uninstall most needs to clean up.
is_ours() {
  local link="$1" kind="$2" name="$3" target
  [ -L "$link" ] || return 1
  target="$(readlink "$link")"
  case "$target" in
    */cursor/"$kind"/"$name"|*/cursor/"$kind"/"$name"/) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Conflicting plugin install ---------------------------------------------
# Warn, never remove: this is the user's Cursor config, and a plugin directory
# may be something they installed deliberately. Naming the exact path is enough
# to act on.
warn_plugin_conflict() {
  local d name
  for d in "$HOME"/.cursor/plugins/local/*; do
    [ -e "$d" ] || [ -L "$d" ] || continue
    [ -f "$d/.cursor-plugin/plugin.json" ] || continue
    name="$(plugin_name_of "$d" 2>/dev/null || true)"
    [ "$name" = "geniro" ] || continue
    echo "WARNING: a Geniro plugin install is also active at $d." >&2
    echo "         Cursor does not deduplicate across sources, so the IDE will list every skill" >&2
    echo "         twice. Remove it — the profile install below covers the IDE too:" >&2
    echo "             rm '$d'" >&2
  done
}

# --- Symlink one generated directory into the profile -----------------------
# kind: skills|agents. Skills are directories named geniro-*; agents are .md
# files under their bare names (a skill's spawn call names the agent, so a
# prefix here would break every spawn).
link_kind() {
  local kind="$1" src_dir="$2" dest_dir="$3" pattern="$4"
  local item name dest linked=0 skipped=0

  [ -d "$src_dir" ] || {
    echo "ERROR: $src_dir missing — run scripts/build-cursor-$kind.sh first" >&2
    return 1
  }
  mkdir -p "$dest_dir"

  for item in "$src_dir"/$pattern; do
    # bash 3.2 has no nullglob: an unmatched glob arrives as the literal pattern.
    [ -e "$item" ] || continue
    name="$(basename "${item%/}")"
    dest="$dest_dir/$name"

    if { [ -e "$dest" ] || [ -L "$dest" ]; } && ! is_ours "$dest" "$kind" "$name"; then
      echo "SKIP: $dest exists and is not a Geniro link — leaving it alone" >&2
      skipped=$((skipped + 1))
      continue
    fi

    # -n so an existing link to a directory is REPLACED, not followed (which
    # would create the new link inside the old target). -f so a re-run re-points
    # a link from a stale checkout to this one instead of failing.
    ln -sfn "${item%/}" "$dest"
    linked=$((linked + 1))
  done

  echo "linked $linked $kind into $dest_dir, skipped $skipped foreign entry/entries" >&2
}

unlink_kind() {
  local kind="$1" dest_dir="$2" pattern="$3"
  local link name removed=0 kept=0
  [ -d "$dest_dir" ] || { echo "removed 0 $kind link(s) — $dest_dir does not exist" >&2; return 0; }

  for link in "$dest_dir"/$pattern; do
    [ -e "$link" ] || [ -L "$link" ] || continue
    name="$(basename "$link")"
    if is_ours "$link" "$kind" "$name"; then
      rm -f "$link"
      removed=$((removed + 1))
    else
      kept=$((kept + 1))
    fi
  done
  echo "removed $removed $kind link(s) from $dest_dir, left $kept foreign entry/entries alone" >&2
}

# --- ~/.cursor/hooks.json ----------------------------------------------------
# A single shared file, not a directory, so this is a merge and never a
# write-over: the user's own entries and any other tool's survive untouched, and
# only entries carrying the shim marker are replaced or dropped. Cursor merges
# hooks across Enterprise -> Team -> Project -> User and runs every match, so
# our entries coexist with a project-level hooks.json rather than competing.
#
# jq is required for this component alone. Without it the skills and agents
# still install and this step reports itself skipped — hand-rolling a JSON merge
# in sed would be a far worse failure mode than not installing hooks.
hooks_apply() {
  local ours_json="$1"       # '{}' to uninstall
  local current='{"version": 1, "hooks": {}}'
  local merged tmp

  if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not found — $HOOKS_DEST left untouched. Geniro's safety hooks will not run" >&2
    echo "      in Cursor until you install jq and re-run this script." >&2
    return 0
  fi

  if [ -f "$HOOKS_DEST" ]; then
    if ! jq empty "$HOOKS_DEST" >/dev/null 2>&1; then
      echo "SKIP: $HOOKS_DEST is not valid JSON — refusing to rewrite it. Fix or move it, then re-run." >&2
      return 0
    fi
    current="$(cat "$HOOKS_DEST")"
  fi

  # Keep every top-level key the file already carries; only .hooks is rebuilt.
  # Per event: the user's non-Geniro entries first, ours appended.
  merged="$(jq -n \
    --argjson cur "$current" \
    --argjson ours "$ours_json" \
    --arg marker "$SHIM_MARKER" '
      ($cur.hooks // {})  as $ch |
      ($ours.hooks // {}) as $oh |
      $cur
      | .version = (.version // 1)
      | .hooks = (
          (($ch | keys) + ($oh | keys) | unique) as $ks
          | reduce $ks[] as $k ({};
              . + { ($k):
                    ( ($ch[$k] // [] | map(select(((.command // "") | test($marker)) | not)))
                      + ($oh[$k] // []) ) })
          | with_entries(select(.value | length > 0))
        )
    ')" || {
    echo "SKIP: could not merge $HOOKS_DEST — left untouched" >&2
    return 0
  }

  mkdir -p "$(dirname "$HOOKS_DEST")"
  tmp="$HOOKS_DEST.tmp.$$"
  printf '%s\n' "$merged" > "$tmp"
  mv -f "$tmp" "$HOOKS_DEST"
}

# Read the plugin's cursor/hooks.json and make it profile-installable: its
# commands are written "./cursor/hooks/..." for a plugin runtime that resolves
# them against the plugin root. Nothing resolves a relative path at user level,
# so each one is rewritten to an absolute path under the resolved source root.
hooks_ours() {
  local src="$1/cursor/hooks.json"
  [ -f "$src" ] || { printf '{}\n'; return 0; }
  command -v jq >/dev/null 2>&1 || { printf '{}\n'; return 0; }
  jq --arg root "$1" '
    .hooks |= with_entries(
      .value |= map(.command |= sub("^\\./"; $root + "/"))
    )' "$src" 2>/dev/null || printf '{}\n'
}

# --- Uninstall ---------------------------------------------------------------
if [ "$MODE" = uninstall ]; then
  unlink_kind skills "$SKILLS_DEST" 'geniro-*'
  unlink_kind agents "$AGENTS_DEST" '*.md'
  hooks_apply '{}'
  echo "Geniro removed from the Cursor profile. Start a new session for it to take effect." >&2
  exit 0
fi

# --- Resolve a version-independent source ------------------------------------
# Everything this script writes must survive the next plugin update, so the
# source root is chosen for its PATH, not for where this file happens to sit.
SRC_ROOT="$SELF_ROOT"
case "$SELF_ROOT" in
  */plugins/cache/*)
    want="$(plugin_name_of "$SELF_ROOT" 2>/dev/null || true)"
    [ -n "$want" ] || want=geniro
    stable="$(find_stable_root "$want" || true)"
    if [ -n "$stable" ]; then
      SRC_ROOT="$stable"
      echo "source: $SRC_ROOT" >&2
      echo "        (the marketplace checkout — no version in the path, so this install stays live across updates;" >&2
      echo "         it tracks the marketplace's branch, which plugin updates refresh in place)" >&2
    else
      echo "WARNING: running from a versioned install cache ($SELF_ROOT) and no marketplace checkout of this" >&2
      echo "         plugin was found, so the links carry a version and will dangle at the next update." >&2
      echo "         Re-run this from a git checkout, or re-run it after the update to re-point them." >&2
    fi
    ;;
esac

warn_plugin_conflict

link_kind skills "$SRC_ROOT/cursor/skills" "$SKILLS_DEST" 'geniro-*/'
link_kind agents "$SRC_ROOT/cursor/agents" "$AGENTS_DEST" '*.md'
hooks_apply "$(hooks_ours "$SRC_ROOT")"

echo "Start a new Cursor session (IDE, CLI, or ACP) to pick this up; remove with: scripts/install-cursor.sh --uninstall" >&2
