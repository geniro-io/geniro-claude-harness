#!/usr/bin/env bash
# Regenerate a module's variants/champion/ from the shipped plugin files.
#
#   sync-champion.sh --module <name>
#
# The champion variant must stay a faithful snapshot of what ships: files listed
# in the module's target.json `champion_sync` are copied verbatim from the repo
# root. The preamble is maintained in place (it is authored FOR the eval, from
# the reviewer-agent body) and is only checked for existence. Run after any
# landed skill change, before a new sweep.
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

n="$(jq '.champion_sync | length' "$TARGET")"
i=0
while [ "$i" -lt "$n" ]; do
  from="$(jq -r ".champion_sync[$i].from" "$TARGET")"
  to="$(jq -r ".champion_sync[$i].to" "$TARGET")"
  [ -f "$ROOT/$from" ] || { echo "missing source: $ROOT/$from" >&2; exit 66; }
  mkdir -p "$DEST/$(dirname "$to")"
  cp "$ROOT/$from" "$DEST/$to"
  i=$((i + 1))
done
[ -f "$DEST/preamble.md" ] || echo "WARN: $DEST/preamble.md missing — author it before running" >&2
echo "champion synced: $n files -> $DEST"
