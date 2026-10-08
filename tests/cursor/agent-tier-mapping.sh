#!/usr/bin/env bash
# The model check in scripts/build-cursor-agents.sh.
#
# Run: bash tests/cursor/agent-tier-mapping.sh   (auto-discovered by tests/run-all.sh)
#
# Agents never pin a model: every agents/*.md declares `model: inherit` and the
# cost class is stated at the spawn site (skills/_shared/model-tiering.md
# §Cost classes). Two properties are worth locking:
#
#   1. Every generated Cursor agent emits `inherit`. A regression that starts
#      writing `auto`, `sonnet` or `claude-4.5-sonnet` there would override the
#      user's session model and rot with Cursor's roster.
#   2. A declared value other than `inherit` (or empty) aborts the build. Mapping
#      a pinned family to a selector would silently drop what the author asked
#      for; refusing to build is what enforces the authoring rule mechanically.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

bash "$REPO_ROOT/scripts/build-cursor-agents.sh" "$TMP" 2>/dev/null || {
  echo "FAIL: build script errored" >&2; exit 1; }

claude_model() { grep -m1 '^model:' "$REPO_ROOT/agents/$1.md" | sed 's/^model:[[:space:]]*//'; }

# --- property 1: every generated agent emits `inherit` ---
BAD=""
for f in "$TMP"/*.md; do
  m="$(grep -m1 '^model:' "$f" | sed 's/^model:[[:space:]]*//')"
  [ "$m" = "inherit" ] || BAD="$BAD $(basename "$f" .md)=$m"
done
if [ -z "$BAD" ]; then pass "every generated agent emits inherit"
else fail "generated agents not inherit:$BAD"; fi

# --- every source agent declares inherit (or nothing), so none carries a pin ---
PINNED=""
for src in "$REPO_ROOT"/agents/*.md; do
  name="$(basename "$src" .md)"
  case "$name" in *-reference) continue ;; esac
  [ -f "$TMP/$name.md" ] || { PINNED="$PINNED $name=absent"; continue; }
  declared="$(claude_model "$name")"
  case "$declared" in
    ""|inherit) ;;
    *) PINNED="$PINNED $name=$declared" ;;
  esac
done
if [ -z "$PINNED" ]; then pass "every agents/*.md declares model: inherit"
else fail "agents pin a model:$PINNED"; fi

# --- the mapping accepts only inherit/empty; every other value is a build error ---
sed -n '/^cursor_model_for()/,/^}/p' "$REPO_ROOT/scripts/build-cursor-agents.sh" > "$TMP/mapfn.sh"
# shellcheck disable=SC1091
. "$TMP/mapfn.sh"
DERIVED="$(cursor_model_for inherit),$(cursor_model_for)"
if [ "$DERIVED" = "inherit,inherit" ]; then
  pass "cursor_model_for maps inherit and empty to inherit"
else
  fail "cursor_model_for produced: $DERIVED (expected inherit,inherit)"
fi
for v in sonnet haiku opus auto; do
  if (cursor_model_for "$v") >/dev/null 2>&1; then
    fail "cursor_model_for accepted '$v' — a pinned model must fail the build"
  else
    pass "cursor_model_for rejects '$v'"
  fi
done

# --- and the whole build fails, not just the helper: the mapping is resolved
#     outside the redirected block that writes the agent file, so the failure
#     cannot be swallowed into an empty `model:` field ---
FAKE="$TMP/fakerepo"
mkdir -p "$FAKE/agents" "$FAKE/scripts"
cp "$REPO_ROOT/scripts/build-cursor-agents.sh" "$FAKE/scripts/"
for v in sonnet opus; do
  rm -rf "$TMP/fakeout"
  printf -- '---\nname: probe-agent\ndescription: probe\nmodel: %s\n---\n\nbody\n' "$v" > "$FAKE/agents/probe-agent.md"
  if bash "$FAKE/scripts/build-cursor-agents.sh" "$TMP/fakeout" >/dev/null 2>&1; then
    fail "build succeeded with a model: $v agent"
  elif [ -s "$TMP/fakeout/probe-agent.md" ]; then
    fail "build failed but still wrote $(grep -m1 '^model:' "$TMP/fakeout/probe-agent.md")"
  else
    pass "a model: $v agent aborts the build without writing a partial file"
  fi
done

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
