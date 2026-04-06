#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────
# install.sh — Bootstrap the Claude Code harness into a repo
#
# Usage:
#   /path/to/claude-harness-template/install.sh [TARGET_DIR]
#
# If TARGET_DIR is omitted, installs into the current directory.
#
# What it does:
#   1. Copies ALL template files into .claude/.artifacts/template-source/
#      (git-ignored — never committed, cleaned up after /setup)
#   2. Copies ONLY the /setup skill into .claude/skills/setup/
#      (so Claude Code can see it when you run `claude`)
#   3. Ensures .claude/.artifacts/ is git-ignored
#   4. Prints next steps
#
# After running this script:
#   cd <TARGET_DIR> && claude
#   /setup
#
# The /setup skill reads from .claude/.artifacts/template-source/,
# installs everything, then removes itself and the temp source.
# ──────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-.}"

# Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  echo "Error: Target directory '$1' does not exist."
  exit 1
}

# Verify this is the template repo
if [[ ! -d "$SCRIPT_DIR/agents" ]] || [[ ! -d "$SCRIPT_DIR/skills" ]]; then
  echo "Error: Cannot find agents/ or skills/ in $SCRIPT_DIR"
  echo "Are you running this from the claude-harness-template directory?"
  exit 1
fi

echo "╔══════════════════════════════════════════════════╗"
echo "║  Claude Code Harness Installer                   ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Template:  $SCRIPT_DIR"
echo "Target:    $TARGET_DIR"
echo ""

# ── Step 1: Create directories ──────────────────────────
TEMP_SOURCE="$TARGET_DIR/.claude/.artifacts/template-source"
SETUP_SKILL="$TARGET_DIR/.claude/skills/setup"

mkdir -p "$TEMP_SOURCE"
mkdir -p "$SETUP_SKILL"

# ── Step 2: Copy ALL template files to temp source ──────
echo "→ Copying template files to .claude/.artifacts/template-source/ ..."

# Copy each directory, excluding .git and .DS_Store
for dir in agents hooks rules skills _reference; do
  if [[ -d "$SCRIPT_DIR/$dir" ]]; then
    cp -r "$SCRIPT_DIR/$dir" "$TEMP_SOURCE/"
  fi
done

# Copy root files
for file in HOOKS.md README.md settings.json CLAUDE.md; do
  if [[ -f "$SCRIPT_DIR/$file" ]]; then
    cp "$SCRIPT_DIR/$file" "$TEMP_SOURCE/"
  fi
done

echo "  ✓ Template files staged"

# ── Step 3: Copy ONLY setup skill to .claude/skills/ ────
echo "→ Installing /setup skill ..."
cp "$SCRIPT_DIR/skills/setup/SKILL.md" "$SETUP_SKILL/SKILL.md"
# Copy supporting files that SKILL.md references via Read tool
for support_file in conflict-resolution.md verification-checks.md; do
  if [[ -f "$SCRIPT_DIR/skills/setup/$support_file" ]]; then
    cp "$SCRIPT_DIR/skills/setup/$support_file" "$SETUP_SKILL/$support_file"
  fi
done
echo "  ✓ /setup skill ready"

# ── Step 4: Ensure .artifacts is git-ignored (root .gitignore only) ──
ROOT_GITIGNORE="$TARGET_DIR/.gitignore"
if [[ -f "$ROOT_GITIGNORE" ]]; then
  if ! grep -q "\.claude/\.artifacts" "$ROOT_GITIGNORE" 2>/dev/null; then
    echo "" >> "$ROOT_GITIGNORE"
    echo "# Claude Code harness (transient data)" >> "$ROOT_GITIGNORE"
    echo ".claude/.artifacts/" >> "$ROOT_GITIGNORE"
    echo "  ✓ Updated root .gitignore"
  else
    echo "  ✓ .claude/.artifacts/ already in root .gitignore"
  fi
else
  echo ".claude/.artifacts/" > "$ROOT_GITIGNORE"
  echo "  ✓ Created root .gitignore"
fi

# ── Done ─────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Ready! Next steps:                              ║"
echo "║                                                  ║"
echo "║  1. cd $TARGET_DIR"
echo "║  2. claude                                       ║"
echo "║  3. /setup                                       ║"
echo "║                                                  ║"
echo "║  The /setup skill will:                          ║"
echo "║  • Analyze your codebase                         ║"
echo "║  • Ask about your preferences                    ║"
echo "║  • Install agents, skills, hooks                 ║"
echo "║  • Generate a tailored CLAUDE.md                 ║"
echo "║  • Clean up the temp files automatically         ║"
echo "╚══════════════════════════════════════════════════╝"
