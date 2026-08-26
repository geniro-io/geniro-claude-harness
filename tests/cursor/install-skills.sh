#!/usr/bin/env bash
# Covers scripts/install-cursor-skills.sh — the ~/.cursor/skills/ symlink
# workaround for cursor-agent not registering plugin skills.
#
# Run: bash tests/cursor/install-skills.sh
#
# ~/.cursor/skills/ is a SHARED directory, so the three properties that matter
# are: the install is idempotent, it never overwrites or deletes an entry it
# does not own, and the uninstall removes exactly its own links — including the
# dangling ones a moved checkout leaves behind.
#
# HOME is redirected to a temp dir for the whole run; the real profile is never
# touched. The repo's own cursor/skills/ is read-only input.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/install-cursor-skills.sh"
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT

SKILLS_DIR="$FAKE_HOME/.cursor/skills"
EXPECTED=$(find "$REPO_ROOT/cursor/skills" -maxdepth 1 -type d -name 'geniro-*' | wc -l | tr -d ' ')

pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
    pass=$((pass + 1))
  else
    echo "FAIL: $1 (expected '$3', got '$2')" >&2
    fail=$((fail + 1))
  fi
}

run() { HOME="$FAKE_HOME" bash "$SCRIPT" "$@" 2>/dev/null; }
links() { find "$SKILLS_DIR" -maxdepth 1 -name 'geniro-*' | wc -l | tr -d ' '; }

# --- install from nothing -------------------------------------------------
run; rc=$?
check "install exits 0" "$rc" "0"
check "every geniro-* skill is linked" "$(links)" "$EXPECTED"

resolved=0
for l in "$SKILLS_DIR"/geniro-*; do
  [ -L "$l" ] && [ -f "$l/SKILL.md" ] && resolved=$((resolved + 1))
done
check "every link resolves to a real SKILL.md" "$resolved" "$EXPECTED"

# --- idempotence ----------------------------------------------------------
run; rc=$?
check "re-run exits 0" "$rc" "0"
check "re-run leaves the same link count" "$(links)" "$EXPECTED"

# --- a stale link is re-pointed, not skipped ------------------------------
ln -sfn "/gone/checkout/cursor/skills/geniro-plan" "$SKILLS_DIR/geniro-plan"
run
check "stale link re-points to this checkout" \
  "$(readlink "$SKILLS_DIR/geniro-plan")" "$REPO_ROOT/cursor/skills/geniro-plan"

# --- foreign entries are never touched ------------------------------------
mkdir -p "$SKILLS_DIR/my-own-skill"
rm -f "$SKILLS_DIR/geniro-review"
mkdir -p "$SKILLS_DIR/geniro-review"          # a real dir under one of our names
echo "mine" > "$SKILLS_DIR/geniro-review/SKILL.md"
ln -sfn "/elsewhere/geniro-debug" "$SKILLS_DIR/geniro-debug"   # not our layout

run; rc=$?
check "install exits 0 with foreign entries present" "$rc" "0"
check "a real directory under our name survives" "$(cat "$SKILLS_DIR/geniro-review/SKILL.md")" "mine"
check "a foreign symlink under our name survives" \
  "$(readlink "$SKILLS_DIR/geniro-debug")" "/elsewhere/geniro-debug"
check "an unrelated skill survives" "$([ -d "$SKILLS_DIR/my-own-skill" ] && echo yes)" "yes"

# --- uninstall removes only ours, dangling included -----------------------
ln -sfn "/gone/checkout/cursor/skills/geniro-ghost" "$SKILLS_DIR/geniro-ghost"

run --uninstall; rc=$?
check "uninstall exits 0" "$rc" "0"
check "a dangling link of ours is removed" \
  "$([ -L "$SKILLS_DIR/geniro-ghost" ] && echo present || echo gone)" "gone"
check "the foreign directory is still there" "$(cat "$SKILLS_DIR/geniro-review/SKILL.md")" "mine"
check "the foreign symlink is still there" \
  "$(readlink "$SKILLS_DIR/geniro-debug")" "/elsewhere/geniro-debug"
check "the unrelated skill is still there" "$([ -d "$SKILLS_DIR/my-own-skill" ] && echo yes)" "yes"
# -lname is GNU-only, so count by reading each link instead.
ours=0
for l in "$SKILLS_DIR"/geniro-*; do
  [ -L "$l" ] || continue
  case "$(readlink "$l")" in "$REPO_ROOT"/cursor/skills/*) ours=$((ours + 1)) ;; esac
done
check "no link of ours survives" "$ours" "0"

# --- version-independent source resolution --------------------------------
# A link into ~/.claude/plugins/cache/<mp>/<plugin>/<version>/ dies at the next
# update, so a script invoked from there must link to the marketplace checkout
# beside it — same plugin, no version in the path — and say so.
rm -rf "$FAKE_HOME/.cursor" "$FAKE_HOME/.claude"
CACHE_ROOT="$FAKE_HOME/.claude/plugins/cache/geniro-claude-harness/geniro/9.9.9"
MP_ROOT="$FAKE_HOME/.claude/plugins/marketplaces/geniro-claude-harness"
for root in "$CACHE_ROOT" "$MP_ROOT"; do
  mkdir -p "$root/.claude-plugin" "$root/scripts"
  printf '{\n  "name": "geniro",\n  "version": "9.9.9",\n  "author": { "name": "Geniro" }\n}\n' > "$root/.claude-plugin/plugin.json"
  cp "$SCRIPT" "$root/scripts/install-cursor-skills.sh"
  cp -R "$REPO_ROOT/cursor" "$root/cursor"
done
# A second marketplace holding a different plugin must not be matched.
OTHER_MP="$FAKE_HOME/.claude/plugins/marketplaces/some-other-marketplace/plugins/notgeniro"
mkdir -p "$OTHER_MP/.claude-plugin" "$OTHER_MP/cursor/skills/geniro-plan"
printf '{ "name": "notgeniro" }\n' > "$OTHER_MP/.claude-plugin/plugin.json"

out="$(HOME="$FAKE_HOME" bash "$CACHE_ROOT/scripts/install-cursor-skills.sh" 2>&1)"
check "cache invocation links to the marketplace checkout" \
  "$(readlink "$SKILLS_DIR/geniro-plan")" "$MP_ROOT/cursor/skills/geniro-plan"
check "no link carries the version" \
  "$(find "$SKILLS_DIR" -maxdepth 1 -type l -exec readlink {} \; | grep -c '9\.9\.9')" "0"
check "the resolved source is reported" "$(printf '%s' "$out" | grep -c "source: $MP_ROOT")" "1"
check "no dangling-link warning when a stable source was found" \
  "$(printf '%s' "$out" | grep -c 'WARNING')" "0"

# Same invocation with no marketplace checkout: the versioned path is all there
# is, so it links there and warns instead of silently shipping doomed links.
rm -rf "$MP_ROOT" "$SKILLS_DIR"
out="$(HOME="$FAKE_HOME" bash "$CACHE_ROOT/scripts/install-cursor-skills.sh" 2>&1)"
check "falls back to the versioned path" \
  "$(readlink "$SKILLS_DIR/geniro-plan")" "$CACHE_ROOT/cursor/skills/geniro-plan"
check "and warns that those links will dangle" "$(printf '%s' "$out" | grep -c 'WARNING')" "1"

echo "--------------------------------------------------------"
echo "install-skills: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
