#!/usr/bin/env bash
# Regenerate a module's variants/champion/ from the shipped plugin files.
#
#   sync-champion.sh --module <name>
#
# The champion variant must stay a faithful snapshot of what ships: files listed
# in the module's target.json `champion_sync` are copied verbatim from the repo
# root. An entry may name a `section` instead, in which case only that `## `
# section of the source is copied — for skills whose per-dimension rubrics live
# as sections of one reference file, and whose orchestrator pastes exactly one
# of them per reviewer. The preamble is maintained in place (it is authored FOR
# the eval, from the reviewer-agent body) and is only checked for existence.
# Run after any landed skill change, before a new sweep.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
MODULE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --module) MODULE="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 64;;
  esac
done
[ -n "$MODULE" ] || { echo "usage: sync-champion.sh --module <name>" >&2; exit 64; }

TARGET="$HERE/modules/$MODULE/target.json"
DEST="$HERE/modules/$MODULE/variants/champion"
[ -f "$TARGET" ] || { echo "no module target: $TARGET" >&2; exit 66; }
mkdir -p "$DEST"

# Extract one `## ` section, fence-aware: a spawn template inside a fenced block
# carries `## ` lines of its own, and a naive scan would truncate the section there.
extract_section() { # <file> <heading text without the "## ">
  awk -v want="$2" '
    /^```/ { fence = !fence }
    !fence && /^## / {
      hdr = $0; sub(/^## /, "", hdr); sub(/[ \t]+$/, "", hdr)
      if (found) exit
      if (hdr == want) { found = 1; print; next }
    }
    found { print }
    END { exit(found ? 0 : 3) }
  ' "$1"
}

n="$(jq '.champion_sync | length' "$TARGET")"
i=0
while [ "$i" -lt "$n" ]; do
  from="$(jq -r ".champion_sync[$i].from" "$TARGET")"
  to="$(jq -r ".champion_sync[$i].to" "$TARGET")"
  section="$(jq -r ".champion_sync[$i].section // empty" "$TARGET")"
  [ -f "$ROOT/$from" ] || { echo "missing source: $ROOT/$from" >&2; exit 66; }
  mkdir -p "$DEST/$(dirname "$to")"
  if [ -n "$section" ]; then
    # A renamed heading upstream must break the sync loudly: silently syncing an
    # empty criteria file would read downstream as "this dimension found nothing".
    extract_section "$ROOT/$from" "$section" > "$DEST/$to" \
      || { echo "section '## $section' not found in $from" >&2; exit 66; }
  else
    cp "$ROOT/$from" "$DEST/$to"
  fi
  i=$((i + 1))
done
[ -f "$DEST/preamble.md" ] || echo "WARN: $DEST/preamble.md missing — author it before running" >&2
echo "champion synced: $n files -> $DEST"
