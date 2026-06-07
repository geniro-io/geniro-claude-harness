#!/usr/bin/env bash
# evals/ingest.sh — derive the cost/CI/gate fields and append one ledger run (plan §8/§9, §16).
#
# Reads a benchmark.json (the harness + skill-creator aggregate output; schema in
# evals/BENCHMARK-SCHEMA.md) for a committed A/B pair and:
#   1. DERIVES cost = tokens × price-map.json  — subscription billing emits no $ (plan §3/§9).
#   2. Computes the RIGHT CI per metric (lib/eval-stats.sh, single-sourced like score-formula.sh):
#        proportions (pass_rate, precision) → Wilson;  winrate / pass^k → task-clustered bootstrap.
#      The TASK is the unit of randomization (between-task variance dominates), so the bootstrap
#      resamples the per-task vector — not pooled trials (plan decision 4).
#   3. Applies the primary-metric gate: a delta inside the CI is a TIE, not a win (plan §6/§9).
#   4. REJECTS a dirty tree / unknown ref — no fictional provenance, p-hacking guard (plan §6/§8).
#   5. Stamps instructions_digest (held constant across the A/B pair) + an incrementing attempt_no.
#   6. Appends exactly one history.jsonl record + one HISTORY.md row via ledger_append.
#
# Usage:
#   evals/ingest.sh <benchmark.json> --candidate <sha> --baseline <sha> [--notes "…"] \
#     [--skill <name>] [--price-map <path>] [--seed <int>] [--bootstrap-reps <int>] \
#     [--instructions-dir <path>]
# candidate/baseline/skill fall back to the benchmark's own fields when the flag is omitted.
#
# Exit codes: 0 ok · 64 usage · 66 bad/unreadable benchmark · 70 dirty-or-non-git tree ·
#             71 unknown ref · 72 unpriced executor_model · (ledger_append rc propagated otherwise).
#
# Plugin-developer / eval tooling only — NOT shipped to user projects, NOT loaded by any skill.

set -uo pipefail

_ig_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# evals/lib/eval-stats.sh exposes $GENIRO_EVAL_STATS_JQ_DEFS + $GENIRO_EVAL_Z95.
# evals/lib/ledger-append.sh pulls in repo-root / hash / atomic / redact under its own guard.
# shellcheck disable=SC1091
source "$_ig_script_dir/lib/eval-stats.sh"
# shellcheck disable=SC1091
source "$_ig_script_dir/lib/ledger-append.sh"

usage() {
  sed -n '8,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---- args -------------------------------------------------------------------
BENCH=""
CANDIDATE=""
BASELINE=""
SKILL=""
NOTES=""
PRICE_MAP=""
SEED=20260607
BOOTSTRAP_REPS=10000
INSTRUCTIONS_DIR=""

# A value-taking flag given as the final arg (its value dropped — a common typo) must fail fast,
# not spin: `shift 2` with only one arg left is a silent no-op, so $# never shrinks and the loop
# hangs. Require the value to be present before consuming it.
_need_val() { [ "$1" -ge 2 ] || { echo "ingest: $2 requires a value" >&2; exit 64; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --candidate) _need_val "$#" "$1"; CANDIDATE="$2"; shift 2;;
    --baseline) _need_val "$#" "$1"; BASELINE="$2"; shift 2;;
    --skill) _need_val "$#" "$1"; SKILL="$2"; shift 2;;
    --notes) _need_val "$#" "$1"; NOTES="$2"; shift 2;;
    --price-map) _need_val "$#" "$1"; PRICE_MAP="$2"; shift 2;;
    --seed) _need_val "$#" "$1"; SEED="$2"; shift 2;;
    --bootstrap-reps) _need_val "$#" "$1"; BOOTSTRAP_REPS="$2"; shift 2;;
    --instructions-dir) _need_val "$#" "$1"; INSTRUCTIONS_DIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    --*) echo "ingest: unknown flag $1" >&2; exit 64;;
    *) if [ -z "$BENCH" ]; then BENCH="$1"; shift; else echo "ingest: unexpected argument $1" >&2; exit 64; fi;;
  esac
done

if [ -z "$BENCH" ]; then
  echo "ingest: a benchmark.json path is required" >&2
  usage >&2
  exit 64
fi
if [ ! -f "$BENCH" ]; then
  echo "ingest: benchmark file not found: $BENCH" >&2
  exit 66
fi
if ! jq -e . "$BENCH" >/dev/null 2>&1; then
  echo "ingest: benchmark file is not valid JSON: $BENCH" >&2
  exit 66
fi

# Fall back to the benchmark's own provenance fields when a flag is omitted.
[ -n "$SKILL" ]     || SKILL="$(jq -r '.skill // empty' "$BENCH")"
[ -n "$CANDIDATE" ] || CANDIDATE="$(jq -r '.candidate_ref // empty' "$BENCH")"
[ -n "$BASELINE" ]  || BASELINE="$(jq -r '.baseline_ref // empty' "$BENCH")"
if [ -z "$SKILL" ] || [ -z "$CANDIDATE" ] || [ -z "$BASELINE" ]; then
  echo "ingest: skill, candidate, and baseline are all required (via flag or benchmark.json)" >&2
  exit 64
fi

PRICE_MAP="${PRICE_MAP:-$_ig_script_dir/price-map.json}"
if [ ! -f "$PRICE_MAP" ] || ! jq -e . "$PRICE_MAP" >/dev/null 2>&1; then
  echo "ingest: price map not found or invalid: $PRICE_MAP" >&2
  exit 66
fi

# Reject a task missing its required primary_value rather than silently coercing null→0 (which
# would deflate the winrate and malform its CI — the most decision-relevant field).
nbad="$(jq '[ .tasks[]? | select(.primary_value == null) ] | length' "$BENCH" 2>/dev/null)"
if [ "${nbad:-0}" -gt 0 ]; then
  echo "ingest: $nbad task(s) missing required primary_value in $BENCH — refusing to coerce to 0" >&2
  exit 66
fi

# ---- provenance guards (no fictional results, no p-hacking) -----------------
# $root = the SHARED committed ledger (primary worktree, via _geniro_repo_root's redirect).
# $guard_root = the worktree the eval ACTUALLY ran in (where the candidate skill + any uncommitted
# edits live). They DIFFER under the prescribed linked-worktree workflow: the operator edits in the
# linked worktree, but _geniro_repo_root redirects to the primary for the shared ledger write only.
# The provenance guards MUST inspect $guard_root — guarding the primary would let uncommitted edits
# in the linked eval worktree launder a fabricated-provenance run past the gate.
root="$(_geniro_repo_root)"
guard_root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$guard_root" ]; then
  echo "ingest: not inside a git worktree — cannot verify candidate/baseline provenance" >&2
  exit 70
fi
# ingest's OWN ledger outputs (history.jsonl/HISTORY.md, appended AFTER the run) are not part of
# any skill, so a sweep of several ingests before one ledger commit must not self-block. Exclude
# exactly those two paths; any other uncommitted change (a real skill edit) still trips the guard.
dirty="$(git -C "$guard_root" status --porcelain 2>/dev/null \
  | grep -vE '^.. (evals/history\.jsonl|evals/HISTORY\.md)$' || true)"
if [ -n "$dirty" ]; then
  echo "ingest: working tree at $guard_root is dirty — commit (or stash) before ingest so the recorded SHAs reflect what ran" >&2
  exit 70
fi
for ref in "$CANDIDATE" "$BASELINE"; do
  if ! git -C "$guard_root" cat-file -e "${ref}^{commit}" 2>/dev/null; then
    echo "ingest: ref does not resolve to a commit in $guard_root: $ref" >&2
    exit 71
  fi
done

# ---- executor model must be priced (cost cannot be faked) -------------------
EXEC_MODEL="$(jq -r '.executor_model // empty' "$BENCH")"
PRICE_IN="$(jq -r --arg m "$EXEC_MODEL" '.models[$m].input // empty' "$PRICE_MAP")"
PRICE_OUT="$(jq -r --arg m "$EXEC_MODEL" '.models[$m].output // empty' "$PRICE_MAP")"
if [ -z "$EXEC_MODEL" ] || [ -z "$PRICE_IN" ] || [ -z "$PRICE_OUT" ]; then
  echo "ingest: executor_model '$EXEC_MODEL' has no entry in $PRICE_MAP — re-resolve prices before a cost-gated run" >&2
  exit 72
fi
PRICE_VERSION="$(jq -r '.version // 0' "$PRICE_MAP")"

# ---- instructions_digest (held constant across the A/B pair, plan §8/decision 13) ----
# Hash the concatenated contents of the loaded instruction files in sorted order. Absent by
# default in this repo → empty-input hash (a real constant); the confound is then null but the
# field is still recorded so a future populated run is comparable.
# Default to the eval worktree's instructions (where plan §8 says they are authored), NOT $root's
# primary — else linked-worktree instructions are silently invisible (recorded as the empty hash).
IDIR="${INSTRUCTIONS_DIR:-$guard_root/.geniro/instructions}"
INSTR_DIGEST=""
# Portable NUL-delimited collection (bash 3.2 lacks `mapfile`; an unguarded mapfile would silently
# record the empty-input hash on a stock-macOS host even when instruction files exist). Init the
# array first so `${#...[@]}` is defined under `set -u`.
_instr_files=()
if [ -d "$IDIR" ]; then
  while IFS= read -r -d '' f; do _instr_files+=("$f"); done \
    < <(find "$IDIR" -type f -name '*.md' -print0 2>/dev/null | LC_ALL=C sort -z)
fi
if [ "${#_instr_files[@]}" -gt 0 ]; then
  INSTR_DIGEST="$(cat "${_instr_files[@]}" | _geniro_sha256 | awk '{print $1}')"
fi
[ -n "$INSTR_DIGEST" ] || INSTR_DIGEST="$(printf '' | _geniro_sha256 | awk '{print $1}')"
INSTRUCTIONS_DIGEST="sha256:$INSTR_DIGEST"

# ---- attempt_no: prior runs for this (skill, baseline) + 1 (p-hacking visibility) ----
LEDGER="$root/evals/history.jsonl"
ATTEMPT_NO=1
if [ -f "$LEDGER" ]; then
  prior="$(jq -Rc --arg s "$SKILL" --arg b "$BASELINE" \
    'fromjson? | select(.skill == $s and .baseline_ref == $b)' "$LEDGER" 2>/dev/null | grep -c . || true)"
  ATTEMPT_NO=$(( ${prior:-0} + 1 ))
fi

# ---- derive the §8 record (single-sourced math via $GENIRO_EVAL_STATS_JQ_DEFS) ----
JQ_PROGRAM=' # rounding helpers keep the committed record compact + readable
  def r($n): if . == null then null else (. * pow(10; $n) | round) / pow(10; $n) end;
  def rci($n): if . == null then null else map(if . == null then null else (. * pow(10; $n) | round) / pow(10; $n) end) end;
  . as $b
  | ($b.tasks) as $tasks
  | {input: $pin, output: $pout} as $price
  | ($b.primary_null // 0.5) as $null
  | [ $tasks[].primary_value ] as $pv
  | mean($pv) as $wr
  | bootstrap_ci($pv; $reps; $seed; 0.025; 0.975) as $qci
  | ($qci[0]) as $lo | ($qci[1]) as $hi
  | ( ($lo != null) and (($null < $lo) or ($null > $hi)) ) as $sig
  | ( ($lo != null) and ($lo > $null) ) as $beats
  | ([ $tasks[].expectation_pass[]? ]) as $ep
  | ($ep | add // 0) as $ep_k | ($ep | length) as $ep_n
  | ([ $tasks[].precision_hits? // empty ] | add // 0) as $ph
  | ([ $tasks[].precision_total? // empty ] | add // 0) as $pt
  | ([ $tasks[] | select(.recall_passk != null) | .recall_passk ]) as $rpk
  | ([ $tasks[] | select(.recall_at1 != null) | .recall_at1 ]) as $r1
  | ([ $tasks[] | (.candidate.input_tokens + .candidate.output_tokens) ]) as $ctok
  | ([ $tasks[] | (.baseline.input_tokens + .baseline.output_tokens) ]) as $btok
  | ([ $tasks[] | (.candidate.input_tokens * $price.input + .candidate.output_tokens * $price.output) / 1000000 ]) as $ccost
  | ([ $tasks[] | (.baseline.input_tokens * $price.input + .baseline.output_tokens * $price.output) / 1000000 ]) as $bcost
  | ([ $tasks[].candidate.wall_seconds ]) as $cwall
  | ([ $tasks[].baseline.wall_seconds ]) as $bwall
  | (mean($ctok)) as $mtok | (mean($btok)) as $mtokb
  | (mean($ccost)) as $mcost | (mean($bcost)) as $mcostb
  | (mean($cwall)) as $mwall | (mean($bwall)) as $mwallb
  | {
      skill: $skill, baseline_ref: $baseline, candidate_ref: $candidate,
      tasks: ($tasks | length),
      trials_per_task: ( [ $tasks[] | (.trials // (.expectation_pass | length)) ] | (add / length) | r(2) ),
      executor_model: $b.executor_model, judge_model: $b.judge_model,
      cross_family_judge: $b.cross_family_judge, models_resolved_at: $b.models_resolved_at,
      executor_temperature: $b.executor_temperature, judge_temperature: $b.judge_temperature,
      auq_autoanswer_policy: $b.auq_autoanswer_policy,
      instructions_digest: $idig, holdout_partition: $b.holdout_partition,

      primary_metric: ($b.primary_metric // "quality_winrate_vs_baseline"), primary_null: $null,
      quality_winrate_vs_baseline: ($wr | r(4)),
      quality_ci: ($qci | rci(4)), ci_method: "bootstrap-task-clustered@95%",
      comparator_verdict: $b.comparator_verdict, position_swapped: $b.position_swapped,
      length_confounded: $b.length_confounded, cross_family_agree: $b.cross_family_agree,
      judge_human_kappa: $b.judge_human_kappa, kappa_measured_at: $b.kappa_measured_at,

      pointwise_score: $b.pointwise_score,
      pointwise_delta: ( if ($b.pointwise_score != null and $b.pointwise_baseline_score != null)
                         then ($b.pointwise_score - $b.pointwise_baseline_score | r(2)) else null end ),

      recall_at1: ( if ($r1 | length) > 0 then (mean($r1) | r(4)) else null end ),
      recall_passk: ( if ($rpk | length) > 0 then (mean($rpk) | r(4)) else null end ),
      recall_passk_ci: ( if ($rpk | length) > 0 then (bootstrap_ci($rpk; $reps; ($seed + 1); 0.025; 0.975) | rci(4)) else null end ),
      recall_passk_ci_method: ( if ($rpk | length) > 0 then "bootstrap-task-clustered@95%" else null end ),
      precision: ( if $pt > 0 then ($ph / $pt | r(4)) else null end ),
      precision_ci: ( if $pt > 0 then (wilson_ci($ph; $pt; $z) | rci(4)) else null end ),
      precision_ci_method: ( if $pt > 0 then "wilson@95%" else null end ),

      mean_cost_usd: ($mcost | r(4)),
      cost_delta: ( if ($mcostb != null and $mcostb != 0) then (($mcost - $mcostb) / $mcostb | r(4)) else null end ),
      cost_derived_from: ("tokens*price-map@v" + ($pricever | tostring)),
      mean_tokens: ($mtok | r(0)),
      tokens_delta: ( if ($mtok != null and $mtokb != null) then ($mtok - $mtokb | r(0)) else null end ),
      mean_wall_seconds: ($mwall | r(2)),
      time_delta: ( if ($mwall != null and $mwallb != null) then ($mwall - $mwallb | r(2)) else null end ),

      pass_rate: ( if $ep_n > 0 then ($ep_k / $ep_n | r(4)) else null end ),
      pass_rate_ci: ( if $ep_n > 0 then (wilson_ci($ep_k; $ep_n; $z) | rci(4)) else null end ),
      pass_rate_ci_method: ( if $ep_n > 0 then "wilson@95%" else null end ),

      significant_on_primary: $sig, primary_beats_null: $beats,
      secondary_metrics_reported_not_gated: true,
      attempt_no: $attempt,
      notes: ( if $notes == "" then null else $notes end )
    }
  | with_entries(select(.value != null))'

RECORD="$(jq -c \
  --arg skill "$SKILL" --arg candidate "$CANDIDATE" --arg baseline "$BASELINE" \
  --arg notes "$NOTES" --arg idig "$INSTRUCTIONS_DIGEST" \
  --argjson seed "$SEED" --argjson reps "$BOOTSTRAP_REPS" --argjson attempt "$ATTEMPT_NO" \
  --argjson z "$GENIRO_EVAL_Z95" --argjson pin "$PRICE_IN" --argjson pout "$PRICE_OUT" \
  --argjson pricever "$PRICE_VERSION" \
  "$GENIRO_EVAL_STATS_JQ_DEFS$JQ_PROGRAM" "$BENCH" 2>/dev/null)"
jqrc=$?
if [ "$jqrc" -ne 0 ] || [ -z "$RECORD" ]; then
  echo "ingest: failed to derive the run record from $BENCH (malformed tasks[]?)" >&2
  exit 66
fi

# Append via the ledger writer. Capture rc AFTER a non-negated pipeline — an
# `if ! pipe; then rc=$?` would read 0 and mask a durable-write failure (Phase-A lesson).
printf '%s' "$RECORD" | ledger_append
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "ingest: ledger_append failed (rc=$rc) — nothing committed to the ledger" >&2
  exit "$rc"
fi

echo "ingest: appended attempt #$ATTEMPT_NO for skill '$SKILL' ($CANDIDATE vs $BASELINE) → $LEDGER"
