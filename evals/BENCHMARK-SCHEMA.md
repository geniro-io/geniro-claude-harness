# `benchmark.json` — the ingest input contract

`evals/ingest.sh` reads one `benchmark.json` per A/B run and derives the committed ledger
record (plan §8/§9). This file is the **boundary contract** between the run side (the Phase-0
harness + skill-creator's `aggregate_benchmark.py`, wired in Phase C/D) and the bookkeeping
side (`ingest.sh` → `ledger-append.sh`). It is defined here, ahead of its producer, so the
Phase-C wiring has an unambiguous target; `evals/fixtures/benchmark.example.json` is a
conforming instance and the fixture the ingest tests run against.

> **Why a separate schema from the §8 ledger record:** `benchmark.json` carries the
> **per-task raw results** (the unit of randomization — plan decision 4); the ledger record
> carries the **derived summary** (CIs, cost, gate). ingest is the one-way transform between
> them. Never put a derived field (cost, any CI, `significant_on_primary`, `attempt_no`) into
> `benchmark.json` — ingest computes those, and a hand-supplied value would be ignored or, if
> trusted, would let a run launder a fabricated CI into the ledger.

## Provenance legend

| Tag | Meaning |
|---|---|
| **H** | harness-added — from each trial's `runs/<id>/result.json` (token usage, duration) + `meta.json` |
| **A** | skill-creator aggregate — from `aggregate_benchmark.py` over the grader/comparator output |
| **C** | run config — pinned by the operator/harness for the run (models, temps, policy) |
| **D** | derived by ingest — **do NOT put in `benchmark.json`** (listed so the boundary is explicit) |

## Top-level fields

| Field | Tag | Type | Notes |
|---|---|---|---|
| `schema_version` | C | string | `"benchmark-v1"`. |
| `skill` | C | string | e.g. `"plan"`. CLI `--skill` overrides. |
| `candidate_ref` / `baseline_ref` | C | string | git SHAs. CLI `--candidate`/`--baseline` override; one of (flag, field) is required. ingest verifies both resolve to commits and the tree is clean. |
| `executor_model` | C | string | Must have a `price-map.json` entry, or ingest fails fast (cost can't be faked). Cost is derived from **this** model's price for both sides (an A/B pins the executor; only the skill differs). |
| `judge_model`, `cross_family_judge`, `models_resolved_at` | C | string | Pass-through provenance. |
| `executor_temperature`, `judge_temperature` | C | number | Executor pinned > 0 so pass^k measures real variation; judge low/0 (plan §8). |
| `auq_autoanswer_policy` | C | string | `"approve-default-v1"` (the harness policy). |
| `holdout_partition` | C | bool | `true` when the run is scored on the held-out partition (gates promotion — plan §11). |
| `position_swapped` | C | bool | Each pair judged in both orders (plan §10). |
| `length_confounded` | A | bool | Candidate mean output length/format differs materially — the winrate gate alone may not clear (plan §10). |
| `cross_family_agree` | A | bool | The cross-family judge agrees on direction (contested/small-Δ runs). |
| `judge_human_kappa`, `kappa_measured_at` | A | number/string | Cohen's κ vs human spot-grades; trust gated on κ ≥ 0.6 (plan §10/decision 12). Pass-through. |
| `comparator_verdict` | A | string | The blind comparator's human-readable call (e.g. `"candidate better"`). Pass-through; the **gate** is the derived CI, not this. |
| `pointwise_score`, `pointwise_baseline_score` | A | number | Relative 1–5/1–10 anchor; ingest stores `pointwise_score` + derives `pointwise_delta`. |
| `primary_metric` | C | string | Which metric gates promotion (default `"quality_winrate_vs_baseline"`). |
| `primary_null` | C | number | The tie point for the primary metric (0.5 for a pairwise winrate; 0 for a delta metric). The gate is "CI excludes this null". |
| `tasks[]` | A+H | array | Per-task results — see below. **The unit of randomization**: the CI bootstraps across these, never across pooled trials. |

## `tasks[]` — one object per distinct task

| Field | Tag | Type | Notes |
|---|---|---|---|
| `id` | A | number/string | Task id from the suite. |
| `trials` | C | number | Trials run for this task (the variance axis; ingest reports the mean as `trials_per_task`). |
| `primary_value` | A | number | This task's value of the primary metric — e.g. the fraction of position-swapped pairs on this task where the candidate won (∈ [0,1]), or a per-task pass^k delta. ingest means these and bootstraps the mean. |
| `expectation_pass` | A | number[] | Per-trial 0/1 over the suite's `expectations[]` → pooled into `pass_rate` (Wilson). |
| `recall_passk` | A | number | Optional. Per-task reliability: 1 if the planted issue was found-and-survived in all k trials, else 0 (or a fraction). Bootstrapped if present. |
| `recall_at1` | A | number | Optional. Per-task recall on the first trial. |
| `precision_hits` / `precision_total` | A | number | Optional. Per-task precision numerator/denominator → pooled into `precision` (Wilson). |
| `candidate` / `baseline` | H | object | `{ input_tokens, output_tokens, wall_seconds }` for this task, summed over its trials, per side. ingest derives mean cost/tokens/time + deltas. |

## What ingest DERIVES (tag D — never in `benchmark.json`)

`mean_cost_usd`, `cost_delta`, `cost_derived_from`, `mean_tokens`, `tokens_delta`,
`mean_wall_seconds`, `time_delta`, `quality_ci`/`recall_passk_ci`/`pass_rate_ci`/`precision_ci`
+ their `*_ci_method`, `significant_on_primary`, `primary_beats_null`, `attempt_no`,
`instructions_digest`, `run_id` (auto-injected by `ledger-append.sh`).

### The two-sided gate fields (read this before promoting)

ingest records **two** booleans so a significant *regression* is never mistaken for a win:

- `significant_on_primary` — the primary CI **excludes the null** (a statistically real
  difference in *either* direction). This is the `Sig` column in `HISTORY.md`.
- `primary_beats_null` — the CI lower bound is **above the null** (a real difference in the
  *winning* direction). **This is the promotion gate.**

Promote a candidate only when `primary_beats_null` is true **on the held-out partition**
(`holdout_partition: true`) — never on a tie (`significant_on_primary: false`), never on a
significant regression (`significant_on_primary: true` with `primary_beats_null: false`),
never on a secondary metric alone (plan §6 step 7).

## Phase-C wiring note

The harness writes `runs/<id>/result.json` (token usage, `duration_ms`) and `gates.jsonl` per
trial; `aggregate_benchmark.py` produces the grader/comparator point estimates. Phase C's glue
maps those onto this schema: sum a task's per-trial `result.json` token usage + duration into
`tasks[].candidate`/`baseline`; map grader `expectations[]` PASS/FAIL into
`tasks[].expectation_pass`; map the position-swapped comparator's per-task winrate into
`tasks[].primary_value`. `total_cost_usd` from the subscription SDK is **not** used — cost is
derived from tokens × `price-map.json` (plan §3/§9).
