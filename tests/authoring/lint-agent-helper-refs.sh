#!/usr/bin/env bash
# An agent body is injected whole as a leaf subagent's system prompt, with no
# orchestrator context and no cwd it can rely on. A helper cited only as a bare
# `<helper>.md` therefore names a file the subagent has no way to resolve — it
# reads as a real pointer, so the agent proceeds as if it had followed one.
#
# The rule is per FILE, not per mention: an agent must root a helper at least
# once, after which short back-references to it are ordinary prose and cost
# nothing. Flagging every bare mention would condemn the idiomatic shape
# `adversarial-tester-agent.md` uses — one rooted READ directive up top, then
# the short name at each point of use.
#
# lint-skills.sh check 5 already rejects a PATH-shaped rootless reference
# (`skills/foo/bar.md`). It cannot see this shape: a bare basename has no path
# component for its leading-segment pattern to match. The two are
# complementary.

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

fails=0
report_fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

# Real helper paths, so a filename that merely looks like one cannot trip this,
# and so a helper under review-criteria/ is matched at its true path.
shopt -s nullglob
helper_paths=(skills/_shared/*.md skills/_shared/review-criteria/*.md)
shopt -u nullglob

if [ "${#helper_paths[@]}" -eq 0 ]; then
  echo "FAIL: no helpers found under skills/_shared/ — wrong working directory?" >&2
  exit 1
fi

# Returns 0 when $2 (an agent file) cites helper path $1 rooted at least once.
cites_rooted() { grep -qF "$1" "$2"; }

# Returns 0 when $2 mentions the bare basename of helper path $1 at all.
mentions_bare() { grep -qF "$(basename "$1")" "$2"; }

checked=0
for agent in agents/*.md; do
  [ -f "$agent" ] || continue
  for hp in "${helper_paths[@]}"; do
    mentions_bare "$hp" "$agent" || continue
    checked=$((checked + 1))
    cites_rooted "$hp" "$agent" && continue
    line=$(grep -n -F "$(basename "$hp")" "$agent" | head -1 | cut -d: -f1)
    report_fail "${agent}:${line} cites \`$(basename "$hp")\` and never roots it — a leaf subagent cannot resolve it. Write \${CLAUDE_PLUGIN_ROOT}/${hp} at the first mention; short back-references after that are fine"
  done
done

# Self-test: the check must be able to go red. A fixture agent that names a real
# helper and never roots it has to be rejected by the same predicates.
selftest_dir=$(mktemp -d)
trap 'rm -rf "$selftest_dir"' EXIT INT TERM
fixture="$selftest_dir/fixture-agent.md"
printf 'Route the read per `%s` for the contract.\n' "$(basename "${helper_paths[0]}")" > "$fixture"

if mentions_bare "${helper_paths[0]}" "$fixture" && ! cites_rooted "${helper_paths[0]}" "$fixture"; then
  echo "PASS: self-test — an agent naming a helper it never roots is detected"
else
  report_fail "self-test: the fixture's unrooted citation was NOT detected — the check cannot see its own defect class"
fi

# Second self-test: the idiomatic shape must NOT be flagged, or the check would
# force noise into every point of use.
printf 'READ `${CLAUDE_PLUGIN_ROOT}/%s` first.\nLater, apply `%s` at each step.\n' \
  "${helper_paths[0]}" "$(basename "${helper_paths[0]}")" > "$fixture"
if cites_rooted "${helper_paths[0]}" "$fixture"; then
  echo "PASS: self-test — one rooted mention plus short back-references is accepted"
else
  report_fail "self-test: the rooted-once shape was rejected — the check is too strict and would flag idiomatic agent prose"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "OK: all $checked agent/helper citation(s) are rooted at least once per file."
  exit 0
fi
echo "Failures: $fails" >&2
exit 1
