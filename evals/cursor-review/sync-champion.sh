#!/usr/bin/env bash
# Regenerate variants/champion/ from the shipped skill files.
# The champion variant must stay a faithful snapshot: criteria bodies are copied
# verbatim; dims.json mirrors the phase-2 §2.1 grid rows that fire on a plain
# (PR-less) code diff. Run after any landed skill change, before a new sweep.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DEST="$HERE/variants/champion"

mkdir -p "$DEST/criteria"
for f in bugs security architecture tests regressions optimizations \
         guidelines conventions rules-compliance; do
  cp "$ROOT/skills/_shared/review-criteria/${f}-criteria.md" "$DEST/criteria/"
done

# dims.json — always-fire rows + optimizations (its docs/lockfile-only skip never
# applies to a benchmark task, which always carries executable surface).
cat > "$DEST/dims.json" <<'EOF'
{
  "dims": [
    { "name": "bugs",          "criteria": ["bugs-criteria.md"] },
    { "name": "security",      "criteria": ["security-criteria.md"] },
    { "name": "architecture",  "criteria": ["architecture-criteria.md"] },
    { "name": "tests",         "criteria": ["tests-criteria.md"] },
    { "name": "conventions",   "criteria": ["guidelines-criteria.md", "conventions-criteria.md", "rules-compliance-criteria.md"] },
    { "name": "regressions",   "criteria": ["regressions-criteria.md"] },
    { "name": "optimizations", "criteria": ["optimizations-criteria.md"] }
  ]
}
EOF

echo "champion synced from $ROOT/skills/_shared/review-criteria -> $DEST"
