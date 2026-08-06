#!/usr/bin/env bash
# Guards the subagent spawn anchor.
#
# Run: bash tests/authoring/lint-spawn-anchor.sh
#
# Why this exists: a subagent's starting cwd is runtime-dependent — Claude Code
# passes the parent's down, other hosts start at the workspace root. A spawn
# that hands over a WORKTREE slot but never tells the agent to cd into it runs
# against whatever tree the host picked. That is silent: a reviewer reports
# findings for the wrong branch, and a test-runner reports the wrong tree's
# suite as green.
#
# The earlier form of this check was file-granular ("does this file mention
# cd <WORKTREE> anywhere"), which passed a file whose OTHER spawn block was
# anchored while two blocks had no anchor at all. Hence check 2: counts, per
# file, so one anchored block cannot vouch for an unanchored sibling.
#
# Coverage:
#   1. No spawn prompt makes the subagent verify its inherited cwd.
#   2. Every WORKTREE slot is matched by an anchor line in the same file.
#      The anchor covers path resolution too, not just Bash: Read/Glob/Grep
#      resolve relative paths against the subagent's own cwd, so a glob the
#      agent writes itself scans the wrong tree even when Bash is anchored.
#   3. Every Agent(...) spawn block carries an anchor, slot or not.
#   4. scope-anchor.md still carries the canonical template.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

CANON="skills/_shared/scope-anchor.md"
ANCHOR='WORKTREE is your root'

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# --- 1. no subagent re-verifies its inherited cwd ----------------------------
#
# Orchestrator-side anchors are exempt: an orchestrator IS the session, so its
# own cwd is authoritative per § The rule and cannot drift. They are marked by
# "orchestrator verifies" or by running "once at entry" rather than per Bash
# call. The branch check itself is not banned — it moved TO the orchestrator,
# which resolved BRANCH once and owns the abort paths.
offenders="$(grep -rn 'stay within WORKTREE on BRANCH\|pwd && git branch --show-current' \
  --include='*.md' skills | grep -v 'orchestrator verifies\|once at entry' || true)"
if [ -z "$offenders" ]; then
  pass "no spawn prompt makes the subagent verify its inherited cwd"
else
  fail "subagent-side cwd verification found — it aborts the spawn on a host that does not inherit cwd, and the check belongs to the orchestrator:"
  printf '  %s\n' "$offenders" >&2
fi

# --- 2. every WORKTREE slot has a matching anchor line -----------------------
mismatched=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  slots="$(grep -c '^WORKTREE:' "$f" || true)"
  anchors="$(grep -cF "$ANCHOR" "$f" || true)"
  [ "$slots" -eq "$anchors" ] || \
    mismatched="$mismatched  $f: $slots WORKTREE slot(s), $anchors anchor line(s)"$'\n'
done < <(grep -rl '^WORKTREE:' --include='*.md' skills | sort)

if [ -z "$mismatched" ]; then
  pass "every WORKTREE slot is matched by an anchor line"
else
  fail "spawn block hands over a WORKTREE slot with no anchor telling the agent to cd into it:"
  printf '%s' "$mismatched" >&2
fi

# --- 3. every Agent(...) spawn block carries an anchor ----------------------
#
# Check 2 counts anchors against WORKTREE slots, so it is blind to the case that
# matters most for a NEW spawn site: a block with neither. This check walks the
# fenced blocks instead and requires an anchor in every one that spawns an agent
# with a prompt, whether or not it declares a slot.
#
# Scope is the `Agent(subagent_type=...  prompt=...)` form — unambiguously a
# spawn site. Bare prompt templates (a fenced block continuing an already-shown
# spawn, as in investigate-taxonomy-reference.md) carry slots today and stay
# covered by check 2.
#
# EXEMPT_AGENTS lists spawns that genuinely do not need the anchor. Keep the
# reason with the entry — an exemption nobody can justify later becomes the
# hole this check exists to close.
#   knowledge-retrieval-agent — its Input Contract declares every slot an
#   absolute path (LIB_ROOT / KNOWLEDGE_ROOT / PLANNING_ROOT / HANDOFF_DIR /
#   OUTPUT_PATH), so no path it touches resolves against cwd.
EXEMPT_AGENTS="knowledge-retrieval-agent"

unanchored="$(
  find skills -name '*.md' -type f | sort | while IFS= read -r f; do
    awk -v file="$f" -v anchor="is your root — run every Bash call from it" \
        -v exempt="$EXEMPT_AGENTS" '
      /^```/ { if (infence) { flush() } else { infence=1; start=NR; buf="" } ; next }
      infence { buf = buf $0 "\n" }
      END { if (infence) flush() }
      function flush(   agent) {
        infence = 0
        if (index(buf, "Agent(subagent_type=") == 0) return
        if (index(buf, "prompt=") == 0) return
        if (index(buf, anchor) > 0) return
        agent = "?"
        if (match(buf, /Agent\(subagent_type="[^"]+"/)) {
          agent = substr(buf, RSTART, RLENGTH)
          sub(/^Agent\(subagent_type="/, "", agent)
          sub(/"$/, "", agent)
          if (index(exempt, agent) > 0) return
        }
        printf "  %s:%d  spawns %s with no anchor\n", file, start, agent
      }
    ' "$f"
  done
)"

if [ -z "$unanchored" ]; then
  pass "every Agent(...) spawn block carries an anchor"
else
  fail "spawn block has no anchor at all — the agent has no way to know which tree it belongs to:"
  printf '%s\n' "$unanchored" >&2
fi

# --- 4. the canonical template still carries the rule -----------------------
# Copies derive from this block; a regression here propagates outward.
if grep -qF "$ANCHOR" "$CANON"; then
  pass "$CANON carries the canonical anchor template"
else
  fail "$CANON no longer carries the canonical anchor template"
fi

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
exit "$TESTS_FAILED"
