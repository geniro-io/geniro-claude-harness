#!/usr/bin/env bash
# Rejection-class regression for the .geniro/safety.json bypass loader.
#
# Run: bash tests/hooks/safety-json-classes.sh
#
# Every guard that ships a per-project bypass reads allow_patterns the same way:
#
#   jq -r '.allow_patterns[]? | select(type == "string" and (test("[[:space:]]") | not))'
#
# and then tests membership with a substring probe over the space-joined list.
# That pairing is load-bearing in BOTH directions. Without the `select`, one entry
# carrying whitespace ("harmless write-env alsoharmless") silently enables every
# pattern ID spelled inside it — a bypass the project never granted. And the
# probe's own surrounding spaces are what keep a superstring ("write-envx") from
# matching. Each sibling guard carries its own copy of this loader, so the
# property has to be asserted on all of them, not on one.
#
# Six malformed shapes, each asserted to fail CLOSED on every guard, plus the
# exact-ID control asserted to actually bypass — a suite where every class blocks
# would also pass if the bypass were broken outright.
#
# Portability: bash 3.2 / BSD, no writes outside a mktemp sandbox, no network.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="$REPO_ROOT/hooks"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# --- sandbox project -----------------------------------------------------------
# One project dir carries everything the guards need to reach a firing verdict:
# a .geniro/ root, a pinned branch (the TDD state-file slug comes from it), a
# RED-phase TDD state file, and a render-less transcript for the gate guard.
PROJ="$TMPDIR_BASE/proj"
mkdir -p "$PROJ/.geniro/state/tdd"
cd "$PROJ" || exit 1
git init -q 2>/dev/null || true
git checkout -q -b sjc 2>/dev/null || true
printf '## phase\nRED\n' > "$PROJ/.geniro/state/tdd/state-sjc.md"
TRANSCRIPT="$PROJ/transcript.jsonl"
{
  jq -nc '{type:"user", message:{content:"please run the review"}}'
  jq -nc '{type:"assistant", message:{content:[{type:"tool_use", name:"Bash", input:{}}]}}'
} > "$TRANSCRIPT"

# --- per-guard probe -----------------------------------------------------------
# Each probe is one input the guard blocks with no safety.json present, so the
# only thing a class can change is whether the bypass fires. Prints 2 when the
# guard fires, 0 when it does not.
probe() {  # <hook-basename>
  local hook="$HOOKS/$1"
  case "$1" in
    file-protection.sh)
      jq -nc '{tool_name:"Write", tool_input:{file_path:".env", content:"x"}}' | bash "$hook" >/dev/null 2>&1
      echo $? ;;
    block-dangerous-git.sh)
      jq -nc '{tool_name:"Bash", tool_input:{command:"git push --force origin main"}}' | bash "$hook" >/dev/null 2>&1
      echo $? ;;
    block-geniro-deletion.sh)
      jq -nc '{tool_name:"Bash", tool_input:{command:"rm -rf .geniro/"}}' | bash "$hook" >/dev/null 2>&1
      echo $? ;;
    enforce-state-helper.sh)
      jq -nc '{tool_name:"Write", tool_input:{file_path:".geniro/planning/task/state.md", content:"x"}}' | bash "$hook" >/dev/null 2>&1
      echo $? ;;
    enforce-tdd-order.sh)
      jq -nc '{tool_name:"Write", tool_input:{file_path:"src/app.js", content:"x"}}' | bash "$hook" >/dev/null 2>&1
      echo $? ;;
    security-pattern-check.sh)
      jq -nc '{tool_name:"Write", tool_input:{file_path:"x.py", content:"r = eval(user_input)"}}' | bash "$hook" >/dev/null 2>&1
      echo $? ;;
    enforce-gate-render.sh)
      jq -nc --arg t "$TRANSCRIPT" \
        '{tool_name:"AskUserQuestion", transcript_path:$t,
          tool_input:{questions:[{question:"Full explanation above. Approve?", options:[{label:"Approve"},{label:"Cancel"}]}]}}' \
        | bash "$hook" >/dev/null 2>&1
      echo $? ;;
    *) echo "probe: unknown hook $1" >&2; echo 1 ;;
  esac
}

# <hook-basename> <its pattern ID>
GUARDS="file-protection.sh:write-env
block-dangerous-git.sh:force-push
block-geniro-deletion.sh:rm-geniro-tree
enforce-state-helper.sh:enforce-state-helper
enforce-tdd-order.sh:tdd-order
security-pattern-check.sh:sec-eval-exec
enforce-gate-render.sh:gate-render"

# The security scan is Perl-implemented and exits 0 when perl is absent, which
# would read as "bypassed" for every class. Drop it rather than report a verdict
# the host cannot produce.
if ! command -v perl >/dev/null 2>&1; then
  echo "NOTE: perl not found — security-pattern-check.sh excluded from this run." >&2
  GUARDS=$(printf '%s\n' "$GUARDS" | grep -v '^security-pattern-check\.sh:')
fi

# --- classes -------------------------------------------------------------------
# Prints the safety.json body for one class, with the guard's own pattern ID
# substituted. The empty string means "write no file at all".
safety_json() {  # <class> <pattern-id>
  case "$1" in
    exact)       printf '{"allow_patterns":["%s"]}' "$2" ;;
    whitespace)  printf '{"allow_patterns":["harmless %s alsoharmless"]}' "$2" ;;
    superstring) printf '{"allow_patterns":["%s-extra"]}' "$2" ;;
    nonstring)   printf '{"allow_patterns":[{"id":"%s"}]}' "$2" ;;
    string_field) printf '{"allow_patterns":"%s"}' "$2" ;;
    unparseable) printf '{"allow_patterns": ["%s"' "$2" ;;
    empty)       printf '{}' ;;
    absent)      : ;;
  esac
}

# class → expected verdict. `exact` is the only one that may bypass.
verdict_for() {  # <class>
  case "$1" in
    exact) echo 0 ;;
    *)     echo 2 ;;
  esac
}

describe() {  # <class>
  case "$1" in
    exact)        echo "exact pattern ID bypasses" ;;
    whitespace)   echo "whitespace-carrying entry does NOT bypass" ;;
    superstring)  echo "superstring of the ID does NOT bypass" ;;
    nonstring)    echo "non-string entry does NOT bypass" ;;
    string_field) echo "allow_patterns as a string does NOT bypass" ;;
    unparseable)  echo "unparseable safety.json does NOT bypass" ;;
    empty)        echo "empty safety.json does NOT bypass" ;;
    absent)       echo "no safety.json blocks (baseline)" ;;
  esac
}

for class in absent exact whitespace superstring nonstring string_field unparseable empty; do
  want=$(verdict_for "$class")
  desc=$(describe "$class")
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    hook="${row%%:*}"
    pid="${row##*:}"
    rm -f "$PROJ/.geniro/safety.json"
    if [ "$class" != "absent" ]; then
      safety_json "$class" "$pid" > "$PROJ/.geniro/safety.json"
    fi
    got=$(probe "$hook")
    if [ "$got" = "$want" ]; then
      pass "$hook [$class]: $desc"
    else
      fail "$hook [$class]: $desc (expected exit=$want, got exit=$got)"
    fi
  done <<< "$GUARDS"
done

cd "$ORIGINAL_PWD" || exit 1

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
