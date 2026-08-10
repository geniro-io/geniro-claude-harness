#!/usr/bin/env bash
# The Claude-tier -> Cursor-tier mapping in scripts/build-cursor-agents.sh.
#
# Run: bash tests/cursor/agent-tier-mapping.sh   (auto-discovered by tests/run-all.sh)
#
# The mapping is between INTENTS, not model names: a judgment-grade agent keeps
# the tier the user chose (`inherit`), and a mechanical carve-out that declares
# a concrete cheaper tier on the Claude side hands the choice to Cursor's own
# `auto` selector. Two properties are worth locking:
#
#   1. No model id is ever emitted into cursor/agents/. Cursor's roster changes
#      constantly and a pinned id silently falls back when unavailable, so a
#      regression that starts writing `sonnet` or `claude-4.5-sonnet` there is a
#      real defect, not a cosmetic one.
#   2. Every agent declaring `model: inherit` still emits `inherit`. Mapping a
#      judgment-grade spawn to `auto` would override the user's `/model` choice
#      — the paternalism anti-pattern in model-tiering.md §Anti-rationalization.
#   3. A tier the mapping cannot express (anything above the session's, i.e.
#      `opus`) aborts the build. Silently sending it to `auto` would invert the
#      declaration — a downgrade where the author asked for an upgrade.
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

cursor_model() { grep -m1 '^model:' "$TMP/$1.md" | sed 's/^model:[[:space:]]*//'; }
claude_model() { grep -m1 '^model:' "$REPO_ROOT/agents/$1.md" | sed 's/^model:[[:space:]]*//'; }

# --- property 1: the emitted value is always a selector, never a model id ---
BAD=""
for f in "$TMP"/*.md; do
  m="$(grep -m1 '^model:' "$f" | sed 's/^model:[[:space:]]*//')"
  case "$m" in
    inherit|auto) ;;
    *) BAD="$BAD $(basename "$f" .md)=$m" ;;
  esac
done
if [ -z "$BAD" ]; then pass "every generated agent emits a selector (inherit|auto), never a model id"
else fail "generated agents pin a model id:$BAD"; fi

# --- property 2: the mapping follows the source tier, per agent ---
MISMAPPED=""
for src in "$REPO_ROOT"/agents/*.md; do
  name="$(basename "$src" .md)"
  case "$name" in *-reference) continue ;; esac
  [ -f "$TMP/$name.md" ] || { MISMAPPED="$MISMAPPED $name=absent"; continue; }
  declared="$(claude_model "$name")"
  got="$(cursor_model "$name")"
  case "$declared" in
    ""|inherit) want="inherit" ;;
    *)          want="auto" ;;
  esac
  [ "$got" = "$want" ] || MISMAPPED="$MISMAPPED $name(claude=$declared cursor=$got want=$want)"
done
if [ -z "$MISMAPPED" ]; then pass "each agent's Cursor tier follows its declared Claude tier"
else fail "tier mapping wrong for:$MISMAPPED"; fi

# --- the two mechanical carve-outs are the ones that delegate ---
for a in knowledge-retrieval-agent test-runner-agent; do
  if [ "$(cursor_model "$a")" = "auto" ]; then
    pass "$a delegates to Cursor's auto selector"
  else
    fail "$a should map to auto, got $(cursor_model "$a")"
  fi
done

# --- a judgment-grade agent must NOT be downgraded ---
for a in reviewer-agent codebase-explorer-agent finding-verifier-agent adversarial-tester-agent; do
  if [ "$(cursor_model "$a")" = "inherit" ]; then
    pass "$a keeps the user's tier (inherit)"
  else
    fail "$a was downgraded to $(cursor_model "$a") — overrides the user's /model choice"
  fi
done

# --- the mapping is computed from the declared tier, not a hardcoded list of
#     agent names: a future agent declaring any concrete tier must delegate
#     without anyone editing the script ---
sed -n '/^cursor_model_for()/,/^}/p' "$REPO_ROOT/scripts/build-cursor-agents.sh" > "$TMP/mapfn.sh"
# shellcheck disable=SC1091
. "$TMP/mapfn.sh"
DERIVED="$(cursor_model_for haiku),$(cursor_model_for sonnet),$(cursor_model_for inherit),$(cursor_model_for)"
if [ "$DERIVED" = "auto,auto,inherit,inherit" ]; then
  pass "mapping is computed from the declared tier, so a new carve-out needs no script edit"
else
  fail "cursor_model_for produced: $DERIVED (expected auto,auto,inherit,inherit)"
fi

# --- a tier Cursor cannot express must stop the build, not map silently.
#     `opus` means "stronger than the session"; mapping it to `auto` would
#     invert the declaration, which is worse than refusing to build. ---
if (cursor_model_for opus) >/dev/null 2>&1; then
  fail "cursor_model_for accepted 'opus' — a stronger-than-session tier mapped to a selector silently"
else
  pass "an inexpressible tier (opus) fails the build instead of mapping silently"
fi

# --- and the whole build fails, not just the helper: the mapping is resolved
#     outside the redirected block that writes the agent file, so the failure
#     cannot be swallowed into an empty `model:` field ---
FAKE="$TMP/fakerepo"
mkdir -p "$FAKE/agents" "$FAKE/scripts"
cp "$REPO_ROOT/scripts/build-cursor-agents.sh" "$FAKE/scripts/"
printf -- '---\nname: probe-agent\ndescription: probe\nmodel: opus\n---\n\nbody\n' > "$FAKE/agents/probe-agent.md"
if bash "$FAKE/scripts/build-cursor-agents.sh" "$TMP/fakeout" >/dev/null 2>&1; then
  fail "build succeeded with an opus-declaring agent"
elif [ -s "$TMP/fakeout/probe-agent.md" ]; then
  fail "build failed but still wrote $(grep -m1 '^model:' "$TMP/fakeout/probe-agent.md")"
else
  pass "an opus-declaring agent aborts the build without writing a partial file"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
