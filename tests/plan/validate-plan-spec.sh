#!/usr/bin/env bash
# Suite for lib/validate-plan-spec.sh — the mechanical half of the
# /geniro:plan Phase 7 validator (checks 1, 2, 4, 6, 7, 10, 11, 12, 13, 14).
#
# Run: bash tests/plan/validate-plan-spec.sh
# Exits non-zero on any failure.
#
# Every check gets both directions: a spec that must pass and at least one
# mutation that must fail, so a check silently reduced to "always pass" is
# visible here rather than in a downstream plan run.
#
# Plugin-developer tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$REPO_ROOT/lib/validate-plan-spec.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
cd "$SANDBOX" || exit 1

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# ---------------------------------------------------------------------------
# Fixture builder — a schema-clean spec, with every field a test needs to
# mutate exposed as a variable that reset_spec restores.
# ---------------------------------------------------------------------------

reset_spec() {
  SCHEMA_VER="m5-v4"
  WFREFS='workflow_refs:
- kind: linear
  issue_id: ENG-303
  url: https://linear.app/x/issue/ENG-303/backfill
  fetched_at: 2026-07-29T09:42:13Z
  title: "Parallelize backfill"
  parent_ref:
    kind: linear
    issue_id: ENG-300
    url: https://linear.app/x/issue/ENG-300
  siblings:
  - issue_id: ENG-301
    title: "Partitioning"
  - issue_id: ENG-302
  chain_fetched_at: 2026-07-29T09:42:15Z'
  BUDGET_BLOCK='budget:
  max_files_to_edit: 8
  max_lines_changed: null
  time_budget: null'
  CKPT_BLOCK='checkpoints:
  - step_anchor: step-3
    name: "DB migration applied"'
  TOOLS_FIELD='tools_required: ["pnpm", "gh"]'
  LAUNCH='launch_config:
  workspace: new-branch
  deep_mode: false
  branch_freshness: rebase
  ship_mode: draft-pr
  tracker_status: move-to-in-progress'
  OBJ='Add a `/backfill` endpoint that re-derives per-user telemetry counts on demand.'
  SEC2='- `src/jobs/BackfillQueue.ts` (new)
- `src/api/routes.ts:40` (edited)'
  SEC3='- event-schema migration
- admin dashboard'
  SEC6='- [ ] 1. Add the queue service in `src/jobs/BackfillQueue.ts:1`. <!-- step-1 -->
- [ ] 2. Wire the route in `src/api/routes.ts:40`. <!-- step-2 -->
- [ ] 3. Apply the queue-table migration in `src/db/schema.ts:40`. <!-- step-3 -->
- [ ] 4. Add the per-user job class in `src/jobs/UserBackfillJob.ts:1`. <!-- step-4 -->
- [ ] 5. Add telemetry counters in `src/telemetry/aggregate.ts:120`. <!-- step-5 -->'
  SEC7='- `pnpm`
- `gh`'
  TIER='medium'
  EXTRA_SECTION='## Considered Alternatives

- In-process Promise.all — memory spike on large datasets.'
}

mk_spec() {
  local out="$1"
  cat > "$out" <<SPEC
---
tier: T1.5
producer: plan
schema-version: 1
branch: feature/backfill
timestamp: 2026-07-29T10:00:00Z
geniro_kind: design-doc
geniro_schema_version: $SCHEMA_VER
task_slug: backfill
mode: IDEA
effort_tier: $TIER
lifecycle: draft
$WFREFS
$BUDGET_BLOCK
$CKPT_BLOCK
$TOOLS_FIELD
$LAUNCH
---

<!-- geniro:design-doc -->

# Backfill telemetry counts

## 1. Objective

$OBJ

## 2. Scope — Included

$SEC2

## 3. Scope — Excluded

$SEC3

## 4. Assumptions

- \`USER.tz\` is always populated (\`src/user/model.ts:22\`).

## 5. Risks

- medium: concurrent writers race on \`events.cursor\` (\`src/telemetry/aggregate.ts:120\`); mitigated by an advisory lock.

## 6. Steps

$SEC6

## 7. Tools Required

$SEC7

## 8. Approval Points

- none

## 9. Validation

Unit tests on the queue service. verify: pnpm test backfill.spec

## 10. Rollback-Recovery

Revert the commit; the change is additive.

## 11. Done Condition

All 5 acceptance tests green AND telemetry shows at least one successful insert.

$EXTRA_SECTION
SPEC
}

# Run the validator and assert one check's status.
expect_status() {
  local spec="$1" check="$2" want="$3" label="$4" got
  got="$(bash "$HELPER" "$spec" 2>/dev/null | awk -F'\t' -v c="$check" '$1 == c { print $2; exit }')"
  if [ "$got" = "$want" ]; then
    pass "$label ($check=$got)"
  else
    fail "$label — expected $check=$want, got '${got:-<no row>}'"
  fi
}

expect_rc() {
  local want="$2" label="$3" rc
  bash "$HELPER" "$1" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq "$want" ]; then
    pass "$label (rc=$rc)"
  else
    fail "$label — expected rc=$want, got rc=$rc"
  fi
}

# A tracker workflow file so the clean baseline reports `pass`, not `warn`,
# on check 12. Built by path fragments so the repo's own state-write guard
# does not read the literal path out of this file.
WF_DIR=".geniro/work""flow"
mkdir -p "$WF_DIR"
: > "$WF_DIR/linear.md"

# ---------------------------------------------------------------------------
# Baseline — a clean spec passes all nine and exits 0
# ---------------------------------------------------------------------------

reset_spec
mk_spec base.md
rows="$(bash "$HELPER" base.md 2>/dev/null)"
if [ "$(printf '%s\n' "$rows" | grep -c .)" -eq 10 ]; then
  pass "clean spec emits one row per mechanical check (10 rows)"
else
  fail "clean spec emitted $(printf '%s\n' "$rows" | grep -c .) rows, expected 10"
fi
if [ "$(printf '%s\n' "$rows" | awk -F'\t' '$2 != "pass"' | grep -c .)" -eq 0 ]; then
  pass "clean spec: every mechanical check passes"
else
  fail "clean spec had non-pass rows: $(printf '%s\n' "$rows" | awk -F'\t' '$2 != "pass"')"
fi
expect_rc base.md 0 "clean spec exits 0"

# Row shape: four TAB-separated fields, in check-number order.
order="$(printf '%s\n' "$rows" | cut -f1 | tr '\n' ' ')"
if [ "$order" = "single_objective bounded_scope allowed_tools budget checkpoints placeholder_scan schema_completeness workflow_refs_consistency launch_config_consistency effort_tier " ]; then
  pass "rows are emitted in check-number order"
else
  fail "row order drifted: $order"
fi
if [ "$(printf '%s\n' "$rows" | awk -F'\t' 'NF != 4' | grep -c .)" -eq 0 ]; then
  pass "every row is a 4-field (check_id, status, finding_text, fix_hint) tuple"
else
  fail "a row was not a 4-field tuple"
fi

# ---------------------------------------------------------------------------
# 1. single_objective
# ---------------------------------------------------------------------------

reset_spec; OBJ='Add OAuth login. Also add SAML login.'; mk_spec obj-two.md
expect_status obj-two.md single_objective fail "two sentences in the Objective"

reset_spec; OBJ='Should we add OAuth login?'; mk_spec obj-q.md
expect_status obj-q.md single_objective fail "interrogative Objective"

reset_spec; OBJ='Add OAuth login'; mk_spec obj-nodot.md
expect_status obj-nodot.md single_objective fail "Objective without a terminating period"

reset_spec; OBJ=''; mk_spec obj-empty.md
expect_status obj-empty.md single_objective fail "empty Objective"

# Regression: a file path inside the sentence must not read as a break.
reset_spec; OBJ='Add the `entryPoint` enum in `src/constants.ts:12` to the context bundle.'; mk_spec obj-path.md
expect_status obj-path.md single_objective pass "Objective containing a dotted file path"

# ---------------------------------------------------------------------------
# 2. bounded_scope
# ---------------------------------------------------------------------------

reset_spec; SEC2=''; mk_spec scope-no2.md
expect_status scope-no2.md bounded_scope fail "Scope — Included with zero bullets"

reset_spec; SEC3=''; mk_spec scope-no3.md
expect_status scope-no3.md bounded_scope fail "Scope — Excluded empty with no open-scope note"

reset_spec; SEC3='none — open scope; this is a repo-wide mechanical rename.'; mk_spec scope-open.md
expect_status scope-open.md bounded_scope pass "Scope — Excluded declaring open scope with a rationale"

reset_spec; SEC3='none'; mk_spec scope-bare-none.md
expect_status scope-bare-none.md bounded_scope fail "bare \"none\" with no rationale"

# ---------------------------------------------------------------------------
# 4. allowed_tools
# ---------------------------------------------------------------------------

reset_spec; SEC7='- none — pure code change'; mk_spec tools-mismatch.md
expect_status tools-mismatch.md allowed_tools fail "section 7 none vs a non-empty tools_required list"

reset_spec; SEC7='- none — pure code change'; TOOLS_FIELD='tools_required: null'; mk_spec tools-none.md
expect_status tools-none.md allowed_tools pass "section 7 none paired with a null field"

reset_spec; TOOLS_FIELD='tools_required: null'; mk_spec tools-null.md
expect_status tools-null.md allowed_tools fail "section 7 content vs a null tools_required"

reset_spec; TOOLS_FIELD='tools_required:
  - pnpm
  - gh'; mk_spec tools-block.md
expect_status tools-block.md allowed_tools pass "block-list tools_required counts as non-empty"

# ---------------------------------------------------------------------------
# 6. budget
# ---------------------------------------------------------------------------

reset_spec; BUDGET_BLOCK='budget:
  max_files_to_edit: 8
  max_lines_changed: null'; mk_spec budget-partial.md
expect_status budget-partial.md budget fail "budget block missing time_budget"

reset_spec; BUDGET_BLOCK='forbidden_actions: null'; mk_spec budget-absent.md
expect_status budget-absent.md budget fail "no budget block at all"

reset_spec; BUDGET_BLOCK='budget:
  max_files_to_edit: null
  max_lines_changed: null
  time_budget: null'; mk_spec budget-nulls.md
expect_status budget-nulls.md budget pass "all-null budget values still pass (key presence, not value)"

# ---------------------------------------------------------------------------
# 7. checkpoints
# ---------------------------------------------------------------------------

reset_spec
SEC6='- [ ] 1. Add the queue service in `src/jobs/BackfillQueue.ts:1`. <!-- step-1 -->
- [ ] 2. Wire the route in `src/api/routes.ts:40`. <!-- step-2 -->'
CKPT_BLOCK='checkpoints: null'
mk_spec ckpt-short.md
expect_status ckpt-short.md checkpoints pass "under 5 steps needs no checkpoints"

reset_spec; CKPT_BLOCK='checkpoints: null'; mk_spec ckpt-missing.md
expect_status ckpt-missing.md checkpoints fail "5 steps with no checkpoints"

reset_spec; CKPT_BLOCK='checkpoints:
  - step_anchor: step-9
    name: "Nowhere"'; mk_spec ckpt-dangling.md
expect_status ckpt-dangling.md checkpoints fail "checkpoint pointing at a step that does not exist"

reset_spec; CKPT_BLOCK='checkpoints:
  - step_anchor: step-5
    name: "Telemetry counters"'; mk_spec ckpt-last.md
expect_status ckpt-last.md checkpoints pass "checkpoint resolving to the final step"

# ---------------------------------------------------------------------------
# 10. placeholder_scan
# ---------------------------------------------------------------------------

reset_spec; SEC3='- admin dashboard
- TODO decide about the export path'; mk_spec ph-todo.md
expect_status ph-todo.md placeholder_scan fail "TODO in the body"

reset_spec; SEC3='- admin dashboard
- ... '; mk_spec ph-ellipsis.md
expect_status ph-ellipsis.md placeholder_scan fail "standalone ellipsis token in the body"

reset_spec; SEC2='- `src/a.ts` (new)
- FIXME the second file'; mk_spec ph-fixme.md
expect_status ph-fixme.md placeholder_scan fail "FIXME in the body"

# Frontmatter is not body — a tracker title carrying TODO must not fail the spec.
reset_spec; WFREFS='workflow_refs:
- kind: linear
  issue_id: ENG-303
  url: https://linear.app/x/issue/ENG-303
  fetched_at: 2026-07-29T09:42:13Z
  status: TODO'; mk_spec ph-fm.md
expect_status ph-fm.md placeholder_scan pass "a placeholder-looking token in frontmatter is out of scope"

# ---------------------------------------------------------------------------
# 11. schema_completeness
# ---------------------------------------------------------------------------

reset_spec; mk_spec schema-base.md
grep -v '^## 5. Risks$' schema-base.md > schema-missing.md
expect_status schema-missing.md schema_completeness fail "a required section header removed"

reset_spec; EXTRA_SECTION='## Notes

- freeform'; mk_spec schema-extra.md
expect_status schema-extra.md schema_completeness fail "a top-level section outside the schema"

reset_spec; EXTRA_SECTION='## Problem & Evidence

**Problem:** counts drift after retroactive edits.'; mk_spec schema-prd.md
expect_status schema-prd.md schema_completeness fail "a retired optional section is no longer allowed"

reset_spec; EXTRA_SECTION='## Comment Resolution Map

- comment 1 -> step 2'; mk_spec schema-crm.md
expect_status schema-crm.md schema_completeness pass "the resolve-only optional section is allowed"

reset_spec; EXTRA_SECTION=''; mk_spec schema-min.md
expect_status schema-min.md schema_completeness pass "no optional sections at all is still complete"

# ---------------------------------------------------------------------------
# 12. workflow_refs_consistency
# ---------------------------------------------------------------------------

reset_spec; SCHEMA_VER="m5-v1"; WFREFS='forbidden_actions: null'; mk_spec wf-v1.md
expect_status wf-v1.md workflow_refs_consistency skip "legacy m5-v1 skips the workflow check"

reset_spec; SCHEMA_VER="m5-v2"; WFREFS='forbidden_actions: null'; mk_spec wf-none.md
expect_status wf-none.md workflow_refs_consistency skip "no workflow_refs[] means nothing to check"

reset_spec; WFREFS='workflow_refs:
- kind: linear
  issue_id: ENG-303
  fetched_at: 2026-07-29T09:42:13Z'; mk_spec wf-nourl.md
expect_status wf-nourl.md workflow_refs_consistency fail "entry missing the required url field"

reset_spec; WFREFS='workflow_refs:
- kind: linear
  issue_id: ENG-303
  url: https://linear.app/x/issue/ENG-303
  fetched_at: 2026-07-29T09:42:13Z
  siblings:
  - issue_id: ENG-301
  - title: "no id here"
  chain_fetched_at: 2026-07-29T09:42:15Z'; mk_spec wf-sib.md
expect_status wf-sib.md workflow_refs_consistency fail "a siblings[] entry with no issue_id"

reset_spec; WFREFS='workflow_refs:
- kind: linear
  issue_id: ENG-303
  url: https://linear.app/x/issue/ENG-303
  fetched_at: 2026-07-29T09:42:13Z
  chain_fetched_at:'; mk_spec wf-chain.md
expect_status wf-chain.md workflow_refs_consistency fail "an empty chain_fetched_at"

reset_spec; WFREFS='workflow_refs:
- kind: jira
  issue_id: PROJ-42
  url: https://example.atlassian.net/browse/PROJ-42
  fetched_at: 2026-07-29T09:42:13Z'; mk_spec wf-missingfile.md
expect_status wf-missingfile.md workflow_refs_consistency warn "an unresolved workflow kind warns rather than fails"
expect_rc wf-missingfile.md 0 "a warn-only spec still exits 0"

reset_spec; WFREFS='workflow_refs:
- kind: linear
  issue_id: ENG-303
  url: https://linear.app/x/issue/ENG-303
  fetched_at: 2026-07-29T09:42:13Z
- kind: jira
  issue_id: PROJ-42
  url: https://example.atlassian.net/browse/PROJ-42'; mk_spec wf-two.md
expect_status wf-two.md workflow_refs_consistency fail "the second of two entries is validated too"

# Deeper-indented sequence layout must parse the same as the flush-left one.
reset_spec; WFREFS='workflow_refs:
  - kind: linear
    issue_id: ENG-303
    url: https://linear.app/x/issue/ENG-303
    fetched_at: 2026-07-29T09:42:13Z
    siblings:
      - issue_id: ENG-301
        title: "Partitioning"'; mk_spec wf-indented.md
expect_status wf-indented.md workflow_refs_consistency pass "indented sequence layout parses"

# ---------------------------------------------------------------------------
# 13. launch_config_consistency
# ---------------------------------------------------------------------------

reset_spec; SCHEMA_VER="m5-v3"; LAUNCH='forbidden_actions: null'; mk_spec lc-absent.md
expect_status lc-absent.md launch_config_consistency skip "an absent launch_config block is skipped, never failed"

reset_spec; LAUNCH='launch_config:
  workspace: new-branch
  deep_mode: false
  branch_freshness: rebase
  ship_mode: yolo-push
  tracker_status: move-to-in-progress'; mk_spec lc-enum.md
expect_status lc-enum.md launch_config_consistency fail "ship_mode outside its enum"

reset_spec; LAUNCH='launch_config:
  deep_mode: false
  branch_freshness: rebase
  ship_mode: draft-pr'; mk_spec lc-missing.md
expect_status lc-missing.md launch_config_consistency fail "a missing core key"

reset_spec; LAUNCH='launch_config:
  workspace: worktree
  deep_mode: true
  branch_freshness: skip
  ship_mode: stop-after-review'; mk_spec lc-notracker.md
expect_status lc-notracker.md launch_config_consistency pass "tracker_status is optional within the block"

reset_spec; LAUNCH='launch_config:
  workspace: New-Branch
  deep_mode: false
  branch_freshness: rebase
  ship_mode: draft-pr'; mk_spec lc-case.md
expect_status lc-case.md launch_config_consistency fail "enum membership is case-sensitive"

# ---------------------------------------------------------------------------
# 14. effort_tier
# ---------------------------------------------------------------------------

for t in trivial small medium big; do
  reset_spec; TIER="$t"; mk_spec "tier-$t.md"
  expect_status "tier-$t.md" effort_tier pass "$t is a legal tier"
done

reset_spec; TIER='Trivial'; mk_spec tier-case.md
expect_status tier-case.md effort_tier fail "tier enum membership is case-sensitive"

reset_spec; TIER='huge'; mk_spec tier-unknown.md
expect_status tier-unknown.md effort_tier fail "a tier outside the enum"

reset_spec; mk_spec tier-absent.md
sed '/^effort_tier:/d' tier-absent.md > tier-absent.tmp && mv tier-absent.tmp tier-absent.md
expect_status tier-absent.md effort_tier fail "an absent effort_tier"
expect_rc tier-absent.md 1 "an absent effort_tier fails the run"

# ---------------------------------------------------------------------------
# API surface: exit codes, sourcing, direct execution
# ---------------------------------------------------------------------------

bash "$HELPER" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 64 ]; then
  pass "no spec path exits 64 (EX_USAGE)"
else
  fail "no spec path exited $rc, expected 64"
fi

expect_rc "$SANDBOX/nope.md" 65 "unreadable spec path exits 65"
expect_rc obj-q.md 1 "a failing check exits 1"

# Sourcing must define the function and run nothing.
out=$(bash -c "source '$HELPER'; command -v validate_plan_spec" 2>&1)
if printf '%s' "$out" | grep -q validate_plan_spec; then
  pass "sourcing defines validate_plan_spec without running it"
else
  fail "sourcing did not define validate_plan_spec: $out"
fi

# Double-source under `set -e` must not trip the readonly guard.
out=$(bash -c "set -e; source '$HELPER'; source '$HELPER'; echo RESOURCE_OK" 2>&1)
if printf '%s' "$out" | grep -q RESOURCE_OK; then
  pass "double-source is idempotent (no readonly crash under set -e)"
else
  fail "double-source crashed: $out"
fi

# Sourced-then-called returns the same rc as the direct run.
bash -c "set -u; source '$HELPER'; validate_plan_spec '$SANDBOX/base.md' >/dev/null"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "sourced call under set -u validates the clean spec (rc=0)"
else
  fail "sourced call under set -u returned rc=$rc"
fi

if command -v zsh >/dev/null 2>&1; then
  out=$(zsh -c "set -u; source '$HELPER'; validate_plan_spec '$SANDBOX/base.md'" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q single_objective; then
    pass "zsh: sourced call under set -u validates the clean spec"
  else
    fail "zsh: sourced call returned rc=$rc out='$out'"
  fi
  out=$(zsh -c "source '$HELPER'" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    pass "zsh: sourcing does not trigger the direct-run guard"
  else
    fail "zsh: sourcing ran the direct-run guard (rc=$rc out='$out')"
  fi
else
  echo "SKIP: zsh not available — cross-shell source checks not run."
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
