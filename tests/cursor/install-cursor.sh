#!/usr/bin/env bash
# Covers scripts/install-cursor.sh — the ~/.cursor/ profile install that gets
# Geniro's skills, subagents, and safety hooks in front of cursor-agent, which
# loads no plugin components at all.
#
# Run: bash tests/cursor/install-cursor.sh
#
# All three destinations are SHARED with the user's own config, so the
# properties that matter are the same for each: the install is idempotent, it
# never overwrites or deletes anything it does not own, and the uninstall
# removes exactly its own entries — including the links a moved checkout left
# dangling. hooks.json adds one of its own: it is a single file holding other
# tools' entries, so a merge that drops one is a config-loss bug.
#
# HOME is redirected to a temp dir for the whole run; the real profile is never
# touched. The repo's own cursor/ tree is read-only input.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/install-cursor.sh"
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT

SKILLS_DIR="$FAKE_HOME/.cursor/skills"
AGENTS_DIR="$FAKE_HOME/.cursor/agents"
HOOKS_FILE="$FAKE_HOME/.cursor/hooks.json"
EXPECTED_SKILLS=$(find "$REPO_ROOT/cursor/skills" -maxdepth 1 -type d -name 'geniro-*' | wc -l | tr -d ' ')
EXPECTED_AGENTS=$(find "$REPO_ROOT/cursor/agents" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')

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
skill_links() { find "$SKILLS_DIR" -maxdepth 1 -name 'geniro-*' | wc -l | tr -d ' '; }
agent_links() { find "$AGENTS_DIR" -maxdepth 1 -name '*.md' | wc -l | tr -d ' '; }
hook_count()  { jq "[.hooks[]?[]] | length" "$HOOKS_FILE" 2>/dev/null || echo ERR; }
ours_hooks()  { jq "[.hooks[]?[] | select(.command | test(\"claude-hook-shim\"))] | length" "$HOOKS_FILE" 2>/dev/null || echo ERR; }

# A pre-existing user hook. Every assertion below re-checks that it survived —
# this file is shared, and clobbering it costs the user their own automation.
mkdir -p "$FAKE_HOME/.cursor"
cat > "$HOOKS_FILE" <<'EOF'
{
  "version": 1,
  "customTopLevelKey": "must survive",
  "hooks": {
    "sessionStart": [ { "command": "/my/own/hook.sh" } ],
    "afterFileEdit": [ { "command": "/my/own/formatter.sh" } ]
  }
}
EOF
SRC_HOOKS=$(jq '[.hooks[]?[]] | length' "$REPO_ROOT/cursor/hooks.json")

# --- install from nothing ---------------------------------------------------
run; rc=$?
check "install exits 0" "$rc" "0"
check "every geniro-* skill is linked" "$(skill_links)" "$EXPECTED_SKILLS"
check "every agent is linked" "$(agent_links)" "$EXPECTED_AGENTS"

resolved=0
for l in "$SKILLS_DIR"/geniro-*; do
  [ -L "$l" ] && [ -f "$l/SKILL.md" ] && resolved=$((resolved + 1))
done
check "every skill link resolves to a real SKILL.md" "$resolved" "$EXPECTED_SKILLS"

resolved=0
for l in "$AGENTS_DIR"/*.md; do
  [ -L "$l" ] && [ -s "$l" ] && resolved=$((resolved + 1))
done
check "every agent link resolves to a real file" "$resolved" "$EXPECTED_AGENTS"

# --- hooks merge ------------------------------------------------------------
check "our hook entries are all present" "$(ours_hooks)" "$SRC_HOOKS"
check "the user's own sessionStart hook survived" \
  "$(jq -r '[.hooks.sessionStart[] | select(.command == "/my/own/hook.sh")] | length' "$HOOKS_FILE")" "1"
check "an event we do not touch survived whole" \
  "$(jq -r '.hooks.afterFileEdit[0].command' "$HOOKS_FILE")" "/my/own/formatter.sh"
check "unknown top-level keys survive" \
  "$(jq -r '.customTopLevelKey' "$HOOKS_FILE")" "must survive"
# Relative "./cursor/..." resolves against a plugin root; nothing resolves it at
# user level, so every installed command must be absolute.
check "no installed hook command is left relative" \
  "$(jq '[.hooks[][] | select(.command | startswith("./"))] | length' "$HOOKS_FILE")" "0"
check "hook commands point into this checkout" \
  "$(jq --arg r "$REPO_ROOT" '[.hooks[][] | select(.command | startswith($r))] | length' "$HOOKS_FILE")" "$SRC_HOOKS"

# --- idempotence ------------------------------------------------------------
before_hooks="$(hook_count)"
run; rc=$?
check "re-run exits 0" "$rc" "0"
check "re-run leaves the same skill count" "$(skill_links)" "$EXPECTED_SKILLS"
check "re-run leaves the same agent count" "$(agent_links)" "$EXPECTED_AGENTS"
check "re-run does not duplicate hook entries" "$(hook_count)" "$before_hooks"

# --- a stale link is re-pointed, not skipped --------------------------------
ln -sfn "/gone/checkout/cursor/skills/geniro-plan" "$SKILLS_DIR/geniro-plan"
ln -sfn "/gone/checkout/cursor/agents/reviewer-agent.md" "$AGENTS_DIR/reviewer-agent.md"
run
check "stale skill link re-points to this checkout" \
  "$(readlink "$SKILLS_DIR/geniro-plan")" "$REPO_ROOT/cursor/skills/geniro-plan"
check "stale agent link re-points to this checkout" \
  "$(readlink "$AGENTS_DIR/reviewer-agent.md")" "$REPO_ROOT/cursor/agents/reviewer-agent.md"

# --- foreign entries are never touched --------------------------------------
mkdir -p "$SKILLS_DIR/my-own-skill"
rm -f "$SKILLS_DIR/geniro-review"
mkdir -p "$SKILLS_DIR/geniro-review"          # a real dir under one of our names
echo "mine" > "$SKILLS_DIR/geniro-review/SKILL.md"
ln -sfn "/elsewhere/geniro-debug" "$SKILLS_DIR/geniro-debug"   # not our layout

echo "mine too" > "$AGENTS_DIR/my-own-agent.md"
rm -f "$AGENTS_DIR/test-runner-agent.md"
echo "also mine" > "$AGENTS_DIR/test-runner-agent.md"          # a real file under our name

run; rc=$?
check "install exits 0 with foreign entries present" "$rc" "0"
check "a real directory under our skill name survives" "$(cat "$SKILLS_DIR/geniro-review/SKILL.md")" "mine"
check "a foreign symlink under our skill name survives" \
  "$(readlink "$SKILLS_DIR/geniro-debug")" "/elsewhere/geniro-debug"
check "an unrelated skill survives" "$([ -d "$SKILLS_DIR/my-own-skill" ] && echo yes)" "yes"
check "a real file under our agent name survives" "$(cat "$AGENTS_DIR/test-runner-agent.md")" "also mine"
check "an unrelated agent survives" "$(cat "$AGENTS_DIR/my-own-agent.md")" "mine too"

# --- a corrupt hooks.json is never rewritten --------------------------------
cp "$HOOKS_FILE" "$FAKE_HOME/hooks.good"
printf '{ not json' > "$HOOKS_FILE"
run
check "an unparseable hooks.json is left byte-identical" "$(cat "$HOOKS_FILE")" "{ not json"
cp "$FAKE_HOME/hooks.good" "$HOOKS_FILE"

# --- uninstall removes only ours, dangling included -------------------------
ln -sfn "/gone/checkout/cursor/skills/geniro-ghost" "$SKILLS_DIR/geniro-ghost"
ln -sfn "/gone/checkout/cursor/agents/ghost-agent.md" "$AGENTS_DIR/ghost-agent.md"

run --uninstall; rc=$?
check "uninstall exits 0" "$rc" "0"
check "a dangling skill link of ours is removed" \
  "$([ -L "$SKILLS_DIR/geniro-ghost" ] && echo present || echo gone)" "gone"
check "a dangling agent link of ours is removed" \
  "$([ -L "$AGENTS_DIR/ghost-agent.md" ] && echo present || echo gone)" "gone"
check "the foreign directory is still there" "$(cat "$SKILLS_DIR/geniro-review/SKILL.md")" "mine"
check "the foreign symlink is still there" \
  "$(readlink "$SKILLS_DIR/geniro-debug")" "/elsewhere/geniro-debug"
check "the unrelated skill is still there" "$([ -d "$SKILLS_DIR/my-own-skill" ] && echo yes)" "yes"
check "the unrelated agent is still there" "$(cat "$AGENTS_DIR/my-own-agent.md")" "mine too"
check "no hook of ours survives" "$(ours_hooks)" "0"
check "the user's own hooks survive the uninstall" \
  "$(jq -r '[.hooks.sessionStart[0].command, .hooks.afterFileEdit[0].command] | join(",")' "$HOOKS_FILE")" \
  "/my/own/hook.sh,/my/own/formatter.sh"
# -lname is GNU-only, so count by reading each link instead.
ours=0
for l in "$SKILLS_DIR"/geniro-* "$AGENTS_DIR"/*.md; do
  [ -L "$l" ] || continue
  case "$(readlink "$l")" in "$REPO_ROOT"/cursor/*) ours=$((ours + 1)) ;; esac
done
check "no link of ours survives" "$ours" "0"

# --- jq absent: the other two components still install ----------------------
rm -rf "$FAKE_HOME/.cursor"
mkdir -p "$FAKE_HOME/.cursor"
printf '{"hooks":{"sessionStart":[{"command":"/my/own/hook.sh"}]}}\n' > "$HOOKS_FILE"
STUB="$FAKE_HOME/nojq"; mkdir -p "$STUB"
for c in sed head find ln basename dirname readlink mkdir rm cat mv cp; do
  p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$STUB/$c"
done
# bash itself must be reached by absolute path — the stubbed PATH is used for
# the interpreter lookup too, and a "command not found" would masquerade as the
# script failing without jq.
BASH_BIN="$(command -v bash)"
out="$(HOME="$FAKE_HOME" PATH="$STUB" "$BASH_BIN" "$SCRIPT" 2>&1)"; rc=$?
check "install exits 0 with no jq on PATH" "$rc" "0"
check "skills still install without jq" "$(skill_links)" "$EXPECTED_SKILLS"
check "agents still install without jq" "$(agent_links)" "$EXPECTED_AGENTS"
check "hooks.json is untouched without jq" \
  "$(cat "$HOOKS_FILE")" '{"hooks":{"sessionStart":[{"command":"/my/own/hook.sh"}]}}'
check "the skipped hook step is reported" "$(printf '%s' "$out" | grep -c 'jq not found')" "1"

# --- a conflicting plugin install is reported -------------------------------
# Cursor deduplicates nothing across sources, so a live plugin install alongside
# this one doubles every skill in the IDE. Warn, never remove.
rm -rf "$FAKE_HOME/.cursor"
PLUGIN_LINK="$FAKE_HOME/.cursor/plugins/local/geniro"
mkdir -p "$(dirname "$PLUGIN_LINK")"
ln -sfn "$REPO_ROOT" "$PLUGIN_LINK"
out="$(HOME="$FAKE_HOME" bash "$SCRIPT" 2>&1)"
check "a conflicting plugin install is warned about" \
  "$(printf '%s' "$out" | grep -c "$PLUGIN_LINK")" "2"
check "the conflicting plugin is NOT removed" "$([ -L "$PLUGIN_LINK" ] && echo present)" "present"

# --- version-independent source resolution ----------------------------------
# A link into ~/.claude/plugins/cache/<mp>/<plugin>/<version>/ dies at the next
# update, so a script invoked from there must link to the marketplace checkout
# beside it — same plugin, no version in the path — and say so.
rm -rf "$FAKE_HOME/.cursor" "$FAKE_HOME/.claude"
CACHE_ROOT="$FAKE_HOME/.claude/plugins/cache/geniro-claude-harness/geniro/9.9.9"
MP_ROOT="$FAKE_HOME/.claude/plugins/marketplaces/geniro-claude-harness"
for root in "$CACHE_ROOT" "$MP_ROOT"; do
  mkdir -p "$root/.claude-plugin" "$root/scripts"
  printf '{\n  "name": "geniro",\n  "version": "9.9.9",\n  "author": { "name": "Geniro" }\n}\n' > "$root/.claude-plugin/plugin.json"
  cp "$SCRIPT" "$root/scripts/install-cursor.sh"
  cp -R "$REPO_ROOT/cursor" "$root/cursor"
done
# A second marketplace holding a different plugin must not be matched.
OTHER_MP="$FAKE_HOME/.claude/plugins/marketplaces/some-other-marketplace/plugins/notgeniro"
mkdir -p "$OTHER_MP/.claude-plugin" "$OTHER_MP/cursor/skills/geniro-plan"
printf '{ "name": "notgeniro" }\n' > "$OTHER_MP/.claude-plugin/plugin.json"

out="$(HOME="$FAKE_HOME" bash "$CACHE_ROOT/scripts/install-cursor.sh" 2>&1)"
check "cache invocation links to the marketplace checkout" \
  "$(readlink "$SKILLS_DIR/geniro-plan")" "$MP_ROOT/cursor/skills/geniro-plan"
check "agents follow the same resolved source" \
  "$(readlink "$AGENTS_DIR/reviewer-agent.md")" "$MP_ROOT/cursor/agents/reviewer-agent.md"
check "no link carries the version" \
  "$(find "$SKILLS_DIR" "$AGENTS_DIR" -maxdepth 1 -type l -exec readlink {} \; | grep -c '9\.9\.9')" "0"
check "no hook command carries the version" \
  "$(jq '[.hooks[][] | select(.command | test("9\\.9\\.9"))] | length' "$HOOKS_FILE")" "0"
check "the resolved source is reported" "$(printf '%s' "$out" | grep -c "source: $MP_ROOT")" "1"
check "no dangling-link warning when a stable source was found" \
  "$(printf '%s' "$out" | grep -c 'WARNING: running from a versioned')" "0"

# Same invocation with no marketplace checkout: the versioned path is all there
# is, so it links there and warns instead of silently shipping doomed links.
rm -rf "$MP_ROOT" "$SKILLS_DIR" "$AGENTS_DIR"
out="$(HOME="$FAKE_HOME" bash "$CACHE_ROOT/scripts/install-cursor.sh" 2>&1)"
check "falls back to the versioned path" \
  "$(readlink "$SKILLS_DIR/geniro-plan")" "$CACHE_ROOT/cursor/skills/geniro-plan"
check "and warns that those links will dangle" \
  "$(printf '%s' "$out" | grep -c 'WARNING: running from a versioned')" "1"

echo "--------------------------------------------------------"
echo "install-cursor: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
