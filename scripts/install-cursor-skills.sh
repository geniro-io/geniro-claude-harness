#!/usr/bin/env bash
# install-cursor-skills.sh — link cursor/skills/geniro-*/ into ~/.cursor/skills/
# so that `cursor-agent` (the CLI) can see them.
#
# WHY THIS EXISTS. cursor-agent does not register skills from plugins at all —
# not from the Cursor marketplace, not from a local plugin directory, not via
# `--plugin-dir`, not through the Claude Code compatibility cache. The IDE does;
# the CLI does not (forum.cursor.com/t/158947, confirmed by Cursor staff). The
# CLI scans four hard-coded directories only:
#
#     <repo>/.claude/skills/   <repo>/.cursor/skills/
#     ~/.cursor/skills/        ~/.cursor/skills-cursor/
#
# Measured 2026-08-26 against cursor-agent 2026.08.11-e8db854: of the four
# install routes, only a link in the profile directory made the agent see the
# skill. The two in-repo directories are not an option — they land in the
# user's `git status` and diffs. So: the profile directory, ~/.cursor/skills/.
#
# The same bug was fixed once by a server-side feature flag (v2026.05.05) and
# regressed. Re-check on every CLI update; when a plain plugin install is
# enough, delete this script, its test, and the README subsection together.
#
# ~/.cursor/skills/ is SHARED with the user's own skills, so this script only
# ever touches names it owns: a `geniro-` prefixed entry that is a symlink into
# some checkout's cursor/skills/. Anything else under that name is left alone
# and reported. --uninstall removes exactly what install created, including
# links left dangling by a moved or deleted checkout.
#
# THE LINK TARGET MUST NOT CARRY A VERSION. Under Claude Code this script is
# usually invoked from the versioned install cache
# (~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/), and a link into
# that path is dead the moment the next version lands. The marketplace checkout
# beside it — ~/.claude/plugins/marketplaces/<marketplace>/ — holds the same
# plugin at a path with no version in it and is refreshed in place by
# `claude plugin marketplace update`, so §Resolve a version-independent source
# below redirects there and the links stay live across every update with nothing
# to re-run. A git checkout or a Cursor local-plugin directory is already
# version-independent and is used as-is.
#
# Usage: scripts/install-cursor-skills.sh [--uninstall]
set -euo pipefail

MODE=install
case "${1:-}" in
  ''            ) ;;
  --uninstall   ) MODE=uninstall ;;
  -h|--help     ) sed -n '2,42p' "$0"; exit 0 ;;
  *             ) echo "usage: $(basename "$0") [--uninstall]" >&2; exit 2 ;;
esac

SELF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="$HOME/.cursor/skills"

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

# A link is ours when its target path ends in /cursor/skills/<name> — the layout
# only scripts/build-cursor-skills.sh produces. The test reads the LINK STRING
# rather than the resolved file, so a link whose checkout has since moved or
# been deleted is still recognisably ours; that dangling case is the one
# --uninstall most needs to clean up.
is_ours() {
  local link="$1" name="$2" target
  [ -L "$link" ] || return 1
  target="$(readlink "$link")"
  case "$target" in
    */cursor/skills/"$name"|*/cursor/skills/"$name"/) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "$MODE" = uninstall ]; then
  removed=0 kept=0
  for link in "$DEST_DIR"/geniro-*; do
    # bash 3.2 has no nullglob: an unmatched glob arrives as the literal pattern.
    [ -e "$link" ] || [ -L "$link" ] || continue
    name="$(basename "$link")"
    if is_ours "$link" "$name"; then
      rm -f "$link"
      removed=$((removed + 1))
    else
      echo "KEPT: $link is not a Geniro link — left in place" >&2
      kept=$((kept + 1))
    fi
  done
  echo "removed $removed link(s) from $DEST_DIR, left $kept foreign entry/entries alone" >&2
  exit 0
fi

# --- Resolve a version-independent source -----------------------------------
# Every link this script writes must survive the next plugin update, so the
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
      echo "        (the marketplace checkout — no version in the path, so these links stay live across updates;" >&2
      echo "         it tracks the marketplace's branch, which plugin updates refresh in place)" >&2
    else
      echo "WARNING: running from a versioned install cache ($SELF_ROOT) and no marketplace checkout of this" >&2
      echo "         plugin was found, so the links carry a version and will dangle at the next update." >&2
      echo "         Re-run this from a git checkout, or re-run it after the update to re-point them." >&2
    fi
    ;;
esac
SRC_DIR="$SRC_ROOT/cursor/skills"

[ -d "$SRC_DIR" ] || { echo "ERROR: $SRC_DIR missing — run scripts/build-cursor-skills.sh first" >&2; exit 1; }

mkdir -p "$DEST_DIR"

linked=0 skipped=0
for dir in "$SRC_DIR"/*/; do
  name="$(basename "$dir")"
  case "$name" in geniro-*) ;; *) continue ;; esac

  dest="$DEST_DIR/$name"
  if { [ -e "$dest" ] || [ -L "$dest" ]; } && ! is_ours "$dest" "$name"; then
    echo "SKIP: $dest exists and is not a Geniro link — leaving it alone" >&2
    skipped=$((skipped + 1))
    continue
  fi

  # -n so an existing link to a directory is REPLACED, not followed (which would
  # create the new link inside the old target). -f so a re-run re-points a link
  # from a stale checkout to this one instead of failing.
  ln -sfn "${dir%/}" "$dest"
  linked=$((linked + 1))
done

echo "linked $linked skill(s) into $DEST_DIR, skipped $skipped foreign entry/entries" >&2
echo "Start a new cursor-agent session to pick them up; remove with: scripts/install-cursor-skills.sh --uninstall" >&2
