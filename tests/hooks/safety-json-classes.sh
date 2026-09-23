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
# carrying whitespace ("harmless write-cert-key alsoharmless") silently enables every
# pattern ID spelled inside it — a bypass the project never granted. And the
# probe's own surrounding spaces are what keep a superstring ("write-cert-keyx") from
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
# a .geniro/ root and a pinned branch.
PROJ="$TMPDIR_BASE/proj"
mkdir -p "$PROJ/.geniro"
cd "$PROJ" || exit 1
git init -q 2>/dev/null || true
git checkout -q -b sjc 2>/dev/null || true

# --- per-pattern-ID probe -------------------------------------------------------
# T4-4: the bypass branch used to be asserted for one representative ID per
# guard while the guards' OTHER pattern IDs had their block path
# tested elsewhere but never their bypass — the allow_patterns wiring for
# those 20+ IDs was unverified. Every pattern ID a guard exposes is its own
# independently-grantable bypass (`is_allowed("<id>")` gates a distinct
# block() call site), so each one needs its own grant+control pair, not a
# single stand-in per guard file.
#
# probe_for_id dispatches on the pattern ID (globally unique across every
# guard) to the EXACT minimal input that trips that ID's own block() call —
# not merely "a" block in that guard, which would validate the wrong
# is_allowed() check. Prints "<hook-basename> <exit-code>".
#
# The remote-download-piped-to-a-shell probe text is assembled from two
# variables set on separate lines rather than as one contiguous literal: this
# suite is itself a .sh file, and security-pattern-check.sh's own matcher for
# that pattern applies to .sh content — a contiguous match in THIS file's
# source would block this suite's own edits. That matcher is newline-bounded,
# so splitting the download half and the shell-pipe half across two lines is
# enough; the runtime-joined string still matches when the probe hands it to
# the hook under test.
probe_for_id() {  # <pattern-id>
  local pid="$1" hook
  case "$pid" in
    # --- block-dangerous-git.sh ---
    force-push)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git push --force origin main"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    force-push-with-lease)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git push --force-with-lease origin main"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    push-delete)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git push origin --delete feature-x"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    reset-hard)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git reset --hard"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    branch-delete-force)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git branch -D feature"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    clean-fd)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git clean -fd"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    checkout-mass-discard)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git checkout ."}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    restore-mass-discard)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git restore ."}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    update-ref-delete)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git update-ref -d refs/heads/x"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    filter-branch)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git filter-branch --tree-filter true HEAD"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    stash-drop)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git stash drop"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    worktree-remove-force)
      hook=block-dangerous-git.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git worktree remove --force /tmp/wt"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    # --- block-geniro-deletion.sh ---
    rm-geniro-tree)
      hook=block-geniro-deletion.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"rm -rf .geniro/"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    rm-geniro-subdir)
      hook=block-geniro-deletion.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"rm -rf .geniro/instructions/"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    rm-geniro-state-subdir)
      hook=block-geniro-deletion.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"rm -rf .geniro/state/review/"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    find-geniro-delete)
      hook=block-geniro-deletion.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"find .geniro -name \"*.md\" -delete"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    worktree-remove-with-state)
      hook=block-geniro-deletion.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git worktree remove ../wt"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    git-add-force-geniro)
      hook=block-geniro-deletion.sh
      jq -nc '{tool_name:"Bash", tool_input:{command:"git add -f .geniro/actions/foo.md"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    # --- file-protection.sh ---
    # write-cert-key is ONE pattern ID gating BOTH *.key and *.pem (a single
    # is_allowed "write-cert-key" call site in file-protection.sh covers both
    # extensions) — a second `write-cert-key)` case arm here for server.pem
    # was DEAD CODE (bash's `case` only ever reaches the first matching arm),
    # so the .pem shape was silently never probed through this suite; it is
    # covered instead by tests/hooks/file-protection.sh's own .pem block/
    # bypass assertions, so removing the dead arm loses no coverage
    # (2026-09-23 audit T1-3/D5b-20/D8-11).
    write-cert-key)
      hook=file-protection.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"tls.key", content:"x"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    write-git-internal)
      hook=file-protection.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:".git/config", content:"x"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    write-lockfile)
      hook=file-protection.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"package-lock.json", content:"x"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    write-credentials)
      hook=file-protection.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"credentials.json", content:"x"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    write-tfstate)
      hook=file-protection.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"terraform.tfstate", content:"x"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    write-vault)
      hook=file-protection.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"config.vault", content:"x"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    # --- enforce-state-helper.sh ---
    enforce-state-helper)
      hook=enforce-state-helper.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:".geniro/planning/task/state.md", content:"x"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    safety-json-edit)
      hook=enforce-state-helper.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:".geniro/safety.json", content:"x"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    # --- security-pattern-check.sh ---
    sec-eval-exec)
      hook=security-pattern-check.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"x.py", content:"r = eval(user_input)"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    sec-pickle)
      hook=security-pattern-check.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"x.py", content:"o = pickle.loads(data)"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    sec-yaml-unsafe)
      hook=security-pattern-check.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"x.py", content:"cfg = yaml.load(data)"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    sec-shell-injection)
      hook=security-pattern-check.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"x.py", content:"os.system(cmd)"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    sec-curl-pipe-sh)
      hook=security-pattern-check.sh
      _cp_dl="curl http://example.com/install.sh"
      _cp_pipe="| sh"
      jq -nc --arg c "$_cp_dl $_cp_pipe" '{tool_name:"Write", tool_input:{file_path:"x.sh", content:$c}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    sec-tls-bypass)
      hook=security-pattern-check.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"x.py", content:"requests.get(url, verify=False)"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    sec-xss-sink)
      hook=security-pattern-check.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"x.js", content:"el.innerHTML = data"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    sec-weak-crypto)
      hook=security-pattern-check.sh
      jq -nc '{tool_name:"Write", tool_input:{file_path:"x.py", content:"h = hashlib.md5(data)"}}' | bash "$HOOKS/$hook" >/dev/null 2>&1 ;;
    *)
      echo "probe_for_id: unknown pattern ID $pid" >&2
      hook=""
      false ;;
  esac
  local rc=$?
  echo "$hook $rc"
}

# The full pattern-ID roster this guard set exposes — one entry per
# probe_for_id() case above (a count is deliberately not stated here: it is
# correct today and stale on the next ID either file adds; the roster-
# completeness check below is what actually keeps this list honest, by
# failing when a hook's own is_allowed("<id>") literal has no match here).
GUARDS="force-push
force-push-with-lease
push-delete
reset-hard
branch-delete-force
clean-fd
checkout-mass-discard
restore-mass-discard
update-ref-delete
filter-branch
stash-drop
worktree-remove-force
rm-geniro-tree
rm-geniro-subdir
rm-geniro-state-subdir
find-geniro-delete
worktree-remove-with-state
git-add-force-geniro
write-cert-key
write-git-internal
write-lockfile
write-credentials
write-tfstate
write-vault
enforce-state-helper
safety-json-edit
sec-eval-exec
sec-pickle
sec-yaml-unsafe
sec-shell-injection
sec-curl-pipe-sh
sec-tls-bypass
sec-xss-sink
sec-weak-crypto"

# --- roster completeness (2026-09-23 audit T1-3/D5b-20/D8-11) ---------------
# GUARDS above is hand-maintained; a new is_allowed("<id>") call site with no
# matching entry here stayed invisible until an audit found it by hand
# (stash-drop and worktree-remove-force shipped in block-dangerous-git.sh
# with no test for either, and no suite anywhere mentioned "stash" or
# "worktree-remove-force"). Every guard that calls is_allowed with a LITERAL
# id (block-dangerous-git.sh, block-geniro-deletion.sh, file-protection.sh)
# must have that id somewhere in GUARDS — a missing one now fails the suite.
# security-pattern-check.sh's sec-* ids are dispatched through a variable
# (`is_allowed "$id"`) and enforce-state-helper.sh's two ids through an
# inline `case " $ALLOWED "` rather than a literal is_allowed call, so this
# grep cannot see either; both stay in GUARDS by hand.
DERIVED_IDS=$(grep -ohE 'is_allowed "[a-z-]+"' "$HOOKS"/*.sh | sed -E 's/is_allowed "//; s/"$//' | sort -u)
while IFS= read -r did; do
  [ -z "$did" ] && continue
  if grep -qx -- "$did" <<< "$GUARDS"; then
    pass "roster completeness: is_allowed(\"$did\") is covered by GUARDS"
  else
    fail "roster completeness: is_allowed(\"$did\") has no entry in GUARDS — a new pattern ID shipped with no bypass test"
  fi
done <<< "$DERIVED_IDS"

# The security scan is Perl-implemented and exits 0 when perl is absent, which
# would read as "bypassed" for every class. Drop its IDs rather than report a
# verdict the host cannot produce.
if ! command -v perl >/dev/null 2>&1; then
  echo "NOTE: perl not found — security-pattern-check.sh's sec-* IDs excluded from this run." >&2
  GUARDS=$(printf '%s\n' "$GUARDS" | grep -v '^sec-')
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
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    rm -f "$PROJ/.geniro/safety.json"
    if [ "$class" != "absent" ]; then
      safety_json "$class" "$pid" > "$PROJ/.geniro/safety.json"
    fi
    result=$(probe_for_id "$pid")
    hook="${result%% *}"
    got="${result##* }"
    if [ "$got" = "$want" ]; then
      pass "$hook [$pid] [$class]: $desc"
    else
      fail "$hook [$pid] [$class]: $desc (expected exit=$want, got exit=$got)"
    fi
  done <<< "$GUARDS"
done

# --- cross_grant class -----------------------------------------------------
# Every class above grants and probes the SAME pattern ID. This one grants a
# DIFFERENT ID than it probes — the shape T0 #3 (2026-08-10) exploited:
# enforce-state-helper.sh's broad "enforce-state-helper" bypass sat as an
# early exit ABOVE check_safety_json_write, so granting it also silently
# disabled the narrower "safety-json-edit" gate on .geniro/safety.json itself
# — the one file that can grant every other guard's bypass in a single write.
# Both directions are probed: the actual regression (broad grant must not leak
# into the narrow gate) plus the control (the narrow grant must not leak the
# other way either, which was already correctly scoped and stays that way).
cross_grant_check() {  # <grant-id> <probe-id> <label>
  rm -f "$PROJ/.geniro/safety.json"
  printf '{"allow_patterns":["%s"]}' "$1" > "$PROJ/.geniro/safety.json"
  local result hook got
  result=$(probe_for_id "$2")
  hook="${result%% *}"
  got="${result##* }"
  if [ "$got" = "2" ]; then
    pass "$hook [$2] [cross_grant]: $3"
  else
    fail "$hook [$2] [cross_grant]: $3 (expected exit=2, got exit=$got)"
  fi
}
cross_grant_check "enforce-state-helper" "safety-json-edit" \
  "granting enforce-state-helper does NOT also bypass safety-json-edit"
cross_grant_check "safety-json-edit" "enforce-state-helper" \
  "granting safety-json-edit does NOT also bypass enforce-state-helper"

# --- linked worktree outside the project -------------------------------------
# .geniro/ is gitignored, so a worktree never carries safety.json, and one
# checked out outside the project never walks up to it: each guard falls back
# to the main checkout's copy. One ID per guard — the fallback lives in each
# guard's own find_safety_json; the per-ID dispatch after it is covered above.
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
WT="$TMPDIR_BASE/wt"
git worktree add -q "$WT" -b sjc-wt 2>/dev/null
cd "$WT" || exit 1
for pid in force-push rm-geniro-tree write-lockfile enforce-state-helper sec-pickle; do
  grep -qx -- "$pid" <<<"$GUARDS" || continue
  for class in absent exact; do
    rm -f "$PROJ/.geniro/safety.json"
    [ "$class" = exact ] && safety_json exact "$pid" > "$PROJ/.geniro/safety.json"
    want=$(verdict_for "$class")
    result=$(probe_for_id "$pid")
    hook="${result%% *}"
    got="${result##* }"
    if [ "$got" = "$want" ]; then
      pass "$hook [$pid] [worktree-$class]: $(describe "$class") from a linked worktree"
    else
      fail "$hook [$pid] [worktree-$class]: $(describe "$class") from a linked worktree (expected exit=$want, got exit=$got)"
    fi
  done
done

cd "$ORIGINAL_PWD" || exit 1

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
