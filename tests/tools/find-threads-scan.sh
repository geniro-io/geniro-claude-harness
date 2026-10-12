#!/usr/bin/env bash
# Regression test for .claude/skills/find-threads/scan.py thread classification.
#
# Run: bash tests/tools/find-threads-scan.sh
#      SCAN_PY=/path/to/other/scan.py bash tests/tools/find-threads-scan.sh   # test another copy
# Exits non-zero on any failure.
#
# Current session logs carry a prompt_snapshot attachment listing the tool DEFINITIONS
# (Agent, Edit, ...). Classification must key on real tool_use calls, not on those names.
#
# Plugin-developer tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCAN_PY="${SCAN_PY:-$REPO_ROOT/.claude/skills/find-threads/scan.py}"

# Physical path: scan.py realpath()s its roots and prints the resolved path (/var -> /private/var on macOS).
WORKDIR="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORKDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "PASS: $1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "FAIL: $1" >&2
}

PROJ="$WORKDIR/projects/-tmp-fixture"
mkdir -p "$PROJ" "$WORKDIR/home"

SNAPSHOT='{"type":"attachment","attachment":{"type":"prompt_snapshot","tools":[{"name":"Agent","description":"Launch"},{"name":"Edit","description":"Edit"},{"name":"Skill","description":"Skill"},{"name":"Write","description":"Write"}]},"cwd":"/tmp/fixture"}'
USER_TXT='{"type":"user","message":{"role":"user","content":"hello"},"cwd":"/tmp/fixture"}'
ASSIST_TXT='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}'
call_line() {  # $1 = tool name
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01ABCdef","name":"%s","input":{}}]}}\n' "$1"
}

# 1. definitions only + plain text exchange -> dropped
printf '%s\n%s\n%s\n' "$SNAPSHOT" "$USER_TXT" "$ASSIST_TXT" > "$PROJ/defs-only.jsonl"
# 2. real Edit call -> edited
{ printf '%s\n%s\n' "$SNAPSHOT" "$USER_TXT"; call_line Edit; } > "$PROJ/edited.jsonl"
# 3. real Skill call, no edit -> read-only
{ printf '%s\n%s\n' "$SNAPSHOT" "$USER_TXT"; call_line Skill; } > "$PROJ/skill.jsonl"
# 3b. real Agent call, no edit -> read-only
{ printf '%s\n%s\n' "$SNAPSHOT" "$USER_TXT"; call_line Agent; } > "$PROJ/agent.jsonl"
# 4. Edit call whose match straddles the 256 KB read-chunk boundary, with 66 of its 70 chars
#    before the boundary -> edited. 66 > 64, so a carried tail of the old 64 chars loses it.
python3 - "$PROJ/straddle.jsonl" <<'PY'
import sys
CHUNK = 256 * 1024
BEFORE = 66  # chars of the tool_use match that land in the first chunk
head = '{"type":"user","message":{"content":"'
call = ('{"type":"assistant","message":{"content":[{"type":"tool_use",'
        '"id":"toolu_01MCfKpa88vGaZ1q6krBErq6","name":"Write","input":{}}]}}\n')
match_at = call.index('"type":"tool_use"')
pad = 'x' * (CHUNK - BEFORE - match_at - len(head) - len('"}}\n'))
out = '%s%s"}}\n%s' % (head, pad, call)
assert out[CHUNK - BEFORE:].startswith('"type":"tool_use"')
open(sys.argv[1], 'w').write(out)
PY

OUT="$(HOME="$WORKDIR/home" CLAUDE_CONFIG_DIR="" FIND_THREADS_EXTRA_ROOTS="$WORKDIR/projects" \
  python3 "$SCAN_PY" 2>/dev/null)"

kind_of() {  # $1 = fixture basename; prints the kind column, or "dropped"
  local k
  k="$(printf '%s\n' "$OUT" | awk -F'\t' -v p="$PROJ/$1" '$10 == p { print $4 }')"
  printf '%s' "${k:-dropped}"
}

check() {  # $1 = fixture, $2 = expected kind
  local got
  got="$(kind_of "$1")"
  if [ "$got" = "$2" ]; then pass "$1 -> $2"; else fail "$1 expected $2, got $got"; fi
}

check defs-only.jsonl dropped
check edited.jsonl edited
check skill.jsonl read-only
check agent.jsonl read-only
check straddle.jsonl edited

echo "---"
echo "Ran $TESTS_RUN, failed $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
