#!/usr/bin/env bash
# tests/seam/plan-review-implement-contract.sh
#
# Judge-free cross-skill SEAM check (eval plan §11, §15). No trials, no cost, no LLM.
# Per-skill artifact grading is blind to cross-skill seam regressions; this pins the two
# producer→consumer contracts that bind /plan → /review → /implement, so a doc/template edit
# that breaks the seam fails `tests/run-all.sh` (which auto-discovers this file).
#
# Two seams (and one corrected expectation):
#
#   A. /plan → /review:  spec.md frontmatter `workflow_refs[]` must satisfy /review's parser
#      WHEN PRESENT, and be treated-as-absent (never false-fail) when missing or on m5-v1.
#      Contract: skills/plan/spec-template.md:67,70-79 (4 required keys: kind/issue_id/url/
#      fetched_at; optional otherwise; omitted on inline-task specs) + skills/review/SKILL.md:117
#      ("Accept both m5-v1 (treat field as absent) and m5-v2 (read entries)").
#
#   B. /review → /implement:  the handoff `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md`
#      must carry frontmatter `open_questions[]` (key MUST be present, MAY be []), which /implement
#      gates Edit/Write on (status: unresolved). Contract: skills/_shared/state-tier-spec.md §T2
#      (canonical schema, required per-entry keys id/source/question/status) + skills/review/SKILL.md:606
#      (producer DoD) + skills/implement/SKILL.md:455-457,469 (consumer gate). The runnable validator
#      lib/validate-state-file.sh already enforces the open_questions key-presence rule (rc 5), so we
#      REUSE it (plan decision 15) rather than re-deriving it.
#
#   CORRECTION (surfaced to maintainer): the plan §11/§16 text says "open_questions[] / step0_status
#      sentinels /implement consumes". Ground truth (recon): /implement consumes ONLY open_questions[].
#      `step0_status` is a /review-INTERNAL per-finding field (skills/review/phase-6-handoff-reference.md:258,261)
#      — /review's §3 gate flips pending→resolved and §7.0 Invariant B re-checks it before the PR post;
#      `grep step0_status skills/implement/` = 0 hits. We therefore assert step0_status as a /review
#      producer-side invariant (§7.0 Invariant B: a `report_status: final` handoff has no PRODUCT-DECISION
#      finding left `pending`), NOT as an /implement-consumed sentinel, and pin that it stays review-internal.
#
# Plugin-developer / eval tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/validate-state-file.sh"   # validate_state_file, _vsf_fm_get_value (reuse — decision 15)

TMPDIR_BASE="$(cd "$(mktemp -d)" && pwd -P)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

expect_rc() {
  # The script runs without errexit (set -uo pipefail, no -e), so a non-zero validate_state_file
  # does not abort — capture its rc directly. (Do NOT `set -e` here: it would leak errexit into the
  # rest of the script and a later bare command could silently abort the suite mid-run.)
  local target="$1" expected="$2" label="$3" rc
  validate_state_file "$target" 2>/dev/null
  rc=$?
  if [ "$rc" -eq "$expected" ]; then pass "$label (rc=$rc)"; else fail "$label — want rc=$expected, got rc=$rc"; fi
}

# ── Frontmatter / body extractors (the fixtures use canonical single-entry YAML) ──
_seam_frontmatter() { awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$1"; }
_seam_body()        { awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$1"; }

# A LOCAL re-implementation of /review's documented workflow_refs acceptance rule (the rule itself
# lives only in skill prose — there is no runnable parser in lib/ to bind to). Part A pins THIS model
# against local fixtures; the Part C greps below are what bind the model to the real skill docs, so a
# doc/contract drift is caught there. → present | absent | malformed | not-design-doc.
#   present   = m5-v2 + EVERY workflow_refs entry carries all 4 required keys (kind/issue_id/url/fetched_at)
#   absent    = design-doc on m5-v1, OR m5-v2 with no workflow_refs entries (inline-task) — MUST NOT fail
#   malformed = m5-v2 + ANY entry missing a required key (validator-checks #14 is per-entry)
_seam_workflow_refs_status() {
  local fm gk gsv block
  fm="$(_seam_frontmatter "$1")"
  gk="$(_vsf_fm_get_value "$fm" geniro_kind)"
  gsv="$(_vsf_fm_get_value "$fm" geniro_schema_version)"
  [ "$gk" = "design-doc" ] || { echo "not-design-doc"; return; }
  [ "$gsv" = "m5-v1" ] && { echo "absent"; return; }              # treat field as absent on m5-v1
  block="$(printf '%s\n' "$fm" | awk '/^workflow_refs:/{f=1;next} f && /^[A-Za-z_]/{f=0} f{print}')"
  printf '%s\n' "$block" | grep -qE '^[[:space:]]*-[[:space:]]' || { echo "absent"; return; }   # no entries → inline-task
  if printf '%s\n' "$block" | _seam_workflow_refs_entries_ok; then echo "present"; else echo "malformed"; fi
}

# Per-entry required-key check (mirrors validator-checks #14, which validates PER ENTRY, not per block).
# Reads the workflow_refs block on stdin; rc 0 iff EVERY entry has all 4 required keys. A block-level
# key-presence grep would mis-classify a multi-entry list where only a LATER entry omits a key as present.
# Caveat: an optional `parent_ref:`'s nested kind/issue_id/url keys count toward the enclosing entry
# (parent_ref is rare; the fixtures don't exercise it).
_seam_workflow_refs_entries_ok() {
  awk '
    function flush() { if (started && !(hk && hi && hu && hf)) bad=1 }
    /^[[:space:]]*-[[:space:]]/  { flush(); started=1; hk=hi=hu=hf=0 }
    /(^|[[:space:]])kind:/        { hk=1 }
    /(^|[[:space:]])issue_id:/    { hi=1 }
    /(^|[[:space:]])url:/         { hu=1 }
    /(^|[[:space:]])fetched_at:/  { hf=1 }
    END { flush(); exit (bad ? 1 : 0) }
  '
}

# open_questions[] entry shape → ok | empty | bad (per state-tier-spec §T2: id/source/question/status required)
_seam_open_questions_shape() {
  local fm block k
  fm="$(_seam_frontmatter "$1")"
  printf '%s\n' "$fm" | grep -qE '^open_questions:[[:space:]]*\[\][[:space:]]*$' && { echo "empty"; return; }
  block="$(printf '%s\n' "$fm" | awk '/^open_questions:/{f=1;next} f && /^[A-Za-z_]/{f=0} f{print}')"
  printf '%s\n' "$block" | grep -qE '(^|[[:space:]])id:' || { echo "empty"; return; }
  for k in id source question status; do
    printf '%s\n' "$block" | grep -qE "(^|[[:space:]])$k:" || { echo "bad"; return; }
  done
  echo "ok"
}

# /review §7.0 Invariant B (review-INTERNAL): a `report_status: final` handoff must leave no
# PRODUCT-DECISION finding with `step0_status: pending`. → ok | violation | ok-not-final
_seam_final_no_pending_pd() {
  local fm rs
  fm="$(_seam_frontmatter "$1")"
  rs="$(_vsf_fm_get_value "$fm" report_status)"
  [ -z "$rs" ] && rs="final"                                       # back-compat: missing reads as final
  [ "$rs" != "final" ] && { echo "ok-not-final"; return; }
  # Body field is the bold-colon form `- **step0_status:** pending` (or a bare `step0_status: pending`);
  # match any non-alphanumeric run (`**`, spaces) between the key and the value so both forms are caught.
  if _seam_body "$1" | grep -qE 'step0_status:[^[:alnum:]]*pending'; then echo "violation"; else echo "ok"; fi
}

# ===========================================================================
# Part A — /plan → /review : workflow_refs[] seam
# ===========================================================================

# A1: tracker-linked m5-v2 spec with a complete workflow_refs entry → PRESENT (parser reads it).
cat > "$TMPDIR_BASE/spec-tracker.md" <<'EOF'
---
tier: T1.5
producer: plan
schema-version: 1
branch: ci-303-parallelize
timestamp: 2026-05-26T10:42:13Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: ci-303
lifecycle: draft
workflow_refs:
- kind: linear
  issue_id: CI-303
  url: https://linear.app/manifestlabs/issue/CI-303/parallelize
  fetched_at: 2026-05-26T10:42:13Z
  title: "Parallelize Case Radar backfill"
  status: Todo
---

<!-- geniro:design-doc -->
# Parallelize Case Radar backfill

## 1. Objective
Speed up backfill.
EOF
[ "$(_seam_workflow_refs_status "$TMPDIR_BASE/spec-tracker.md")" = "present" ] \
  && pass "A1 tracker-linked m5-v2 spec → workflow_refs PRESENT" \
  || fail "A1 tracker-linked spec not parsed as present (got: $(_seam_workflow_refs_status "$TMPDIR_BASE/spec-tracker.md"))"

# A2: inline-task m5-v1 spec, no workflow_refs → ABSENT, must NOT false-fail (the never-false-fail property).
cat > "$TMPDIR_BASE/spec-inline-v1.md" <<'EOF'
---
tier: T1.5
producer: plan
schema-version: 1
branch: inline-task
timestamp: 2026-05-26T10:42:13Z
geniro_kind: design-doc
geniro_schema_version: m5-v1
task_slug: inline
lifecycle: draft
---

# Inline task

## 1. Objective
Do a thing.
EOF
[ "$(_seam_workflow_refs_status "$TMPDIR_BASE/spec-inline-v1.md")" = "absent" ] \
  && pass "A2 inline-task m5-v1 spec → treated as ABSENT (no false-fail)" \
  || fail "A2 m5-v1 inline spec mis-parsed (got: $(_seam_workflow_refs_status "$TMPDIR_BASE/spec-inline-v1.md"))"

# A3: m5-v2 spec with NO workflow_refs field (legal — m5-v2 without a tracker fetched) → ABSENT.
cat > "$TMPDIR_BASE/spec-v2-notracker.md" <<'EOF'
---
tier: T1.5
producer: plan
schema-version: 1
branch: no-tracker
timestamp: 2026-05-26T10:42:13Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: notracker
lifecycle: draft
---

# No tracker

## 1. Objective
Do a thing.
EOF
[ "$(_seam_workflow_refs_status "$TMPDIR_BASE/spec-v2-notracker.md")" = "absent" ] \
  && pass "A3 m5-v2 spec w/o workflow_refs field → ABSENT (no false-fail)" \
  || fail "A3 m5-v2-no-field mis-parsed (got: $(_seam_workflow_refs_status "$TMPDIR_BASE/spec-v2-notracker.md"))"

# A4 (drift guard): m5-v2 entry MISSING the required `url` key → MALFORMED (the check must catch it).
cat > "$TMPDIR_BASE/spec-malformed.md" <<'EOF'
---
tier: T1.5
producer: plan
schema-version: 1
branch: bad-ref
timestamp: 2026-05-26T10:42:13Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: bad
lifecycle: draft
workflow_refs:
- kind: linear
  issue_id: CI-303
  fetched_at: 2026-05-26T10:42:13Z
---

# Bad ref

## 1. Objective
Do a thing.
EOF
[ "$(_seam_workflow_refs_status "$TMPDIR_BASE/spec-malformed.md")" = "malformed" ] \
  && pass "A4 m5-v2 entry missing required url → MALFORMED (drift guard fires)" \
  || fail "A4 malformed entry not caught (got: $(_seam_workflow_refs_status "$TMPDIR_BASE/spec-malformed.md"))"

# A5 (per-entry drift guard): multi-entry list where only the SECOND entry omits url → MALFORMED.
# A block-level key check would wrongly read this as present (entry 1 supplies url). Real specs are
# multi-entry (issue + parent epic + merged sub-tasks — review/SKILL.md:117).
cat > "$TMPDIR_BASE/spec-multi-bad.md" <<'EOF'
---
tier: T1.5
producer: plan
schema-version: 1
branch: multi-bad
timestamp: 2026-05-26T10:42:13Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: multi
lifecycle: draft
workflow_refs:
- kind: linear
  issue_id: CI-303
  url: https://linear.app/manifestlabs/issue/CI-303/foo
  fetched_at: 2026-05-26T10:42:13Z
- kind: linear
  issue_id: CI-300
  fetched_at: 2026-05-26T10:42:13Z
---

# Multi bad

## 1. Objective
Do a thing.
EOF
[ "$(_seam_workflow_refs_status "$TMPDIR_BASE/spec-multi-bad.md")" = "malformed" ] \
  && pass "A5 multi-entry, 2nd entry missing url → MALFORMED (per-entry, not per-block)" \
  || fail "A5 per-entry malformed not caught (got: $(_seam_workflow_refs_status "$TMPDIR_BASE/spec-multi-bad.md"))"

# A6: multi-entry list where EVERY entry is complete → PRESENT.
cat > "$TMPDIR_BASE/spec-multi-ok.md" <<'EOF'
---
tier: T1.5
producer: plan
schema-version: 1
branch: multi-ok
timestamp: 2026-05-26T10:42:13Z
geniro_kind: design-doc
geniro_schema_version: m5-v2
task_slug: multi
lifecycle: draft
workflow_refs:
- kind: linear
  issue_id: CI-303
  url: https://linear.app/manifestlabs/issue/CI-303/foo
  fetched_at: 2026-05-26T10:42:13Z
- kind: linear
  issue_id: CI-300
  url: https://linear.app/manifestlabs/issue/CI-300/epic
  fetched_at: 2026-05-26T10:42:13Z
---

# Multi ok

## 1. Objective
Do a thing.
EOF
[ "$(_seam_workflow_refs_status "$TMPDIR_BASE/spec-multi-ok.md")" = "present" ] \
  && pass "A6 multi-entry, all entries complete → PRESENT" \
  || fail "A6 complete multi-entry mis-parsed (got: $(_seam_workflow_refs_status "$TMPDIR_BASE/spec-multi-ok.md"))"

# ===========================================================================
# Part B — /review → /implement : open_questions[] handoff seam
# ===========================================================================

# B1: well-formed handoff carrying an unresolved open_question (the genuine producer→consumer seam)
#     → the real validator accepts it (rc 0).
cat > "$TMPDIR_BASE/from-review-feat.md" <<'EOF'
---
tier: T2
producer: review
schema-version: 1
branch: feat/ci-277
timestamp: 2026-05-26T13:30:00Z
consumer: implement
geniro_kind: state-handoff
geniro_schema_version: m6-v2
report_status: final
open_questions:
  - id: q1
    source: spec-compliance
    question: "API seeder additions in-scope or split into a separate PR?"
    related_findings: [F1]
    status: unresolved
---

# Review: feat/ci-277

## Findings

### CRITICAL

### F1 — [NEW] SQL injection in getUser
- **Severity:** CRITICAL
- **Decision Type:** PRODUCT-DECISION
- **step0_status:** resolved

## Open Questions

### q1 — spec-compliance: seeder scope
**Status:** unresolved
EOF
expect_rc "$TMPDIR_BASE/from-review-feat.md" 0 "B1 well-formed /review→/implement handoff validates"
[ "$(_seam_open_questions_shape "$TMPDIR_BASE/from-review-feat.md")" = "ok" ] \
  && pass "B1 open_questions entry carries id/source/question/status" \
  || fail "B1 open_questions entry shape bad (got: $(_seam_open_questions_shape "$TMPDIR_BASE/from-review-feat.md"))"

# B2 (the /implement-consumed presence contract — negative): drop the open_questions key → validator rc 5.
cat > "$TMPDIR_BASE/from-review-no-oq.md" <<'EOF'
---
tier: T2
producer: review
schema-version: 1
branch: feat/ci-277
timestamp: 2026-05-26T13:30:00Z
consumer: implement
---

## Findings
content
EOF
expect_rc "$TMPDIR_BASE/from-review-no-oq.md" 5 "B2 handoff missing open_questions key → rejected (the /implement gate's machine contract)"

# B3: an unconditionally-actionable handoff (open_questions: []) is valid (key present, empty list).
cat > "$TMPDIR_BASE/from-review-empty-oq.md" <<'EOF'
---
tier: T2
producer: review
schema-version: 1
branch: feat/clean
timestamp: 2026-05-26T13:30:00Z
consumer: implement
open_questions: []
---

## Findings
none
EOF
expect_rc "$TMPDIR_BASE/from-review-empty-oq.md" 0 "B3 empty open_questions[] handoff validates"
[ "$(_seam_open_questions_shape "$TMPDIR_BASE/from-review-empty-oq.md")" = "empty" ] \
  && pass "B3 open_questions: [] recognised as empty (no entries to gate on)" \
  || fail "B3 empty open_questions mis-read (got: $(_seam_open_questions_shape "$TMPDIR_BASE/from-review-empty-oq.md"))"

# B4 (review-INTERNAL invariant §7.0 B): a report_status: final handoff with a PRODUCT-DECISION finding
#    still step0_status: pending is a violation; the same with all resolved is ok.
cat > "$TMPDIR_BASE/from-review-pending-pd.md" <<'EOF'
---
tier: T2
producer: review
schema-version: 1
branch: feat/pending
timestamp: 2026-05-26T13:30:00Z
consumer: implement
report_status: final
open_questions: []
---

## Findings

### F1 — [NEW] ambiguous behaviour change
- **Decision Type:** PRODUCT-DECISION
- **step0_status:** pending
EOF
[ "$(_seam_final_no_pending_pd "$TMPDIR_BASE/from-review-pending-pd.md")" = "violation" ] \
  && pass "B4 final report with a pending PRODUCT-DECISION step0_status → violation caught (review-internal)" \
  || fail "B4 pending-PD-in-final not caught (got: $(_seam_final_no_pending_pd "$TMPDIR_BASE/from-review-pending-pd.md"))"
[ "$(_seam_final_no_pending_pd "$TMPDIR_BASE/from-review-feat.md")" = "ok" ] \
  && pass "B4 final report with all PRODUCT-DECISION step0_status resolved → ok" \
  || fail "B4 clean final handoff flagged (got: $(_seam_final_no_pending_pd "$TMPDIR_BASE/from-review-feat.md"))"

# ===========================================================================
# Part C — cross-doc drift guards (the producer & consumer docs must keep naming the same seam)
# ===========================================================================

# C1: PHRASE-anchored, not bare token co-occurrence — require m5-v1 to co-occur with "absent" on one
# line (the documented "treat field as absent" acceptance). A regression that inverts /review to REJECT
# m5-v1 drops that phrasing and fails this guard (bare-token greps survive the inversion — review finding).
grep -qE 'm5-v1.*absent' "$REPO_ROOT/skills/review/SKILL.md" \
  && grep -qE 'm5-v2' "$REPO_ROOT/skills/review/SKILL.md" \
  && grep -qE 'workflow_refs' "$REPO_ROOT/skills/review/SKILL.md" \
  && pass "C1 /review still documents m5-v1 → treat-as-absent + m5-v2 workflow_refs acceptance" \
  || fail "C1 /review SKILL.md no longer documents the m5-v1→absent / m5-v2 acceptance rule"

# C2: require the 4 required keys BACKTICK-WRAPPED (the per-entry shape table `| `kind` | yes |` …), not
# bare substrings — mangling a key name in the required-key table then fails this guard (a bare substring
# survives because the same key also appears un-backticked in the YAML example — review finding).
grep -qE '`kind`' "$REPO_ROOT/skills/plan/spec-template.md" \
  && grep -qE '`issue_id`' "$REPO_ROOT/skills/plan/spec-template.md" \
  && grep -qE '`url`' "$REPO_ROOT/skills/plan/spec-template.md" \
  && grep -qE '`fetched_at`' "$REPO_ROOT/skills/plan/spec-template.md" \
  && pass "C2 /plan spec-template still defines all 4 required workflow_refs per-entry keys" \
  || fail "C2 /plan spec-template.md per-entry required-key shape drifted"

grep -qE 'from-review-' "$REPO_ROOT/skills/review/SKILL.md" \
  && grep -qE 'open_questions' "$REPO_ROOT/skills/review/SKILL.md" \
  && pass "C3 /review (producer) still writes from-review-<branch>.md with open_questions[]" \
  || fail "C3 /review SKILL.md handoff path / open_questions token drifted"

grep -qE 'from-review' "$REPO_ROOT/skills/implement/SKILL.md" \
  && grep -qE 'open_questions' "$REPO_ROOT/skills/implement/SKILL.md" \
  && grep -qE 'unresolved' "$REPO_ROOT/skills/implement/SKILL.md" \
  && pass "C4 /implement (consumer) still reads from-review handoff and gates on unresolved open_questions" \
  || fail "C4 /implement SKILL.md no longer reads/gates the open_questions seam"

grep -qE 'open_questions' "$REPO_ROOT/skills/_shared/state-tier-spec.md" \
  && pass "C5 _shared/state-tier-spec.md still defines the canonical open_questions schema" \
  || fail "C5 canonical open_questions schema missing from state-tier-spec.md"

# C6: step0_status stays /review-internal — NOT consumed by /implement (pins the plan-text imprecision).
if grep -rIlE 'step0_status' "$REPO_ROOT/skills/implement/" >/dev/null 2>&1; then
  fail "C6 step0_status now appears in skills/implement/ — the review→implement seam changed; update this test + the plan §11/§16 text"
else
  pass "C6 step0_status remains /review-internal (absent from skills/implement/) — /implement consumes only open_questions[]"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
