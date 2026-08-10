# evals/loop — the module-agnostic improvement loop

The eval stand: measure any plugin module (review content and the spec-claim
check today; plan/implement/debug criteria next) against a versioned benchmark,
cheap enough to iterate, disciplined enough to trust. Its predecessors — the
`evals/cursor-review/` v1 content stand and the Agent-SDK full-skill
run-harness — were deleted in its favor (git history holds them, including the
H1–H6 experiment ledger that produced the criteria charter trim).

Design sources: Anthropic's eval docs + "Demystifying evals for AI agents" +
"Adding Error Bars to Evals" (arXiv 2411.00640); structural patterns from
promptfoo / Inspect AI / lm-eval-harness / Braintrust; LLM-judge evidence from
MT-Bench (arXiv 2306.05685) and PoLL (arXiv 2404.18796). The full research
digest lives in the session report; each mechanism below names its source.

## Core objects

- **Module** (`modules/<name>/`) — the unit under improvement. `target.json`
  declares its facets (parallel sub-reviews and the criteria files each reads),
  prompt-assembly knobs, output contract, parser name, pass expressions, and
  the champion-sync map. (Braintrust's data/task/scorers triple.)
- **Variant** — a directory overriding any champion file (`preamble.md`,
  `criteria/*`, `facets.json`). The champion is a faithful snapshot of shipped
  files (`sync-champion.sh --module <m>`), so a win translates 1:1 into a
  skill edit.
- **Benchmark task** (`modules/<m>/benchmarks/{dev,holdout}/<task>/`) —
  `task.json` (staging inputs) + `rubric.json`:

  ```json
  {"version": 1, "negative": false, "items": [ ...ground-truth defects... ]}
  ```

  `version` is an integer bumped on ANY rubric edit (lm-eval-harness rule);
  `compare.sh` hard-fails on version mismatch — scores across rubric versions
  are never comparable. One carve-out: `acceptance_evidence` is provenance
  metadata that never enters a prompt or a score — editing only it does not
  bump. `negative: true` marks a task whose correct answer is
  zero findings (Anthropic: test both directions or the loop optimizes toward
  overtriggering). `holdout/` is physically separate and never read while
  tuning; it gates promotion. Tasks mined from real repositories are committed
  anonymized — repo location resolves through `repo_alias` + the gitignored
  `repos.local.json`, and no committed field carries a repo name, PR/ticket
  number, username, or machine path.
- **Run** (`runs/scratch/<id>/` → promoted immutable) — self-contained
  (Inspect's log-is-the-artifact): `spec.json` pins variant hash, per-task
  rubric versions + benchmark hash, model, adapter, trials; per-trial raw
  results, prompts, findings, judge verdicts, metrics. Scratch is
  overwritable; a run cited by a ledger line or an EXP file is immutable
  (Braintrust playground/experiment split).

## Engines (adapters/)

| adapter | role | cost |
|---|---|---|
| `cursor-cli.sh` | screening sweeps (composer-2.5 default) | cents, metered by the built-in guard |
| `claude-subagent.md` | judge (primary) + confirmation-tier executor | free on subscription |
| `mock.sh` | deterministic canned results for the test suite | free, no network |

Money guards live in `run.sh`, not in prose: `--probe` runs one paid call and
extrapolates the sweep from the measured usage row; `--max-usd` (default $50)
aborts a sweep that crosses the measured ceiling; the content-keyed cache
(model + task@rubric-version + trial + workspace-signature + prompt hash,
successes only — promptfoo's recipe) makes re-runs and resumes free. Blended
measured rates live in `adapters/cursor-prices.json` — re-probe after any
workload-shape change.

Screening economics (2026-08-09 config; a stand-condition change — pre-change
baselines and the EXP-001 noise floor are indicative, not comparable):

- **Workspace pruning — measured a dud, default stays full.** The hypothesis
  (agent workspace reads are ~90% of a real task's bill → prune the tree) was
  probed 2026-08-09: a pruned real task cost $0.438/call vs $0.44 full — the
  agent's reads track its exploration budget, not tree size. `stage-task.sh`
  keeps `"workspace_scope": "auto"` as a per-task OPT-IN (depth-2 changed
  subtrees + imported workspace packages + root/rule files), and a pruned
  stage adds its scope hash to the cache key; full-workspace keys keep the
  legacy shape so paid caches survive. Don't re-propose pruning as a cost
  lever without new evidence.
- **Screen facet subset** — screens run `target.json.screen_facets` (for
  review: bugs/security/tests/regressions — every must item's class lives
  there, and the legacy H1 result showed recall parity on 4 dimensions);
  confirm always runs the FULL facet set.
- **Sequential trials** (pre-registered escalation rule): screen both arms at
  1 trial first; if the paired Δrecall_must is an exact tie AND
  **|Δnoise_strict|** is under the module's OWN A-vs-A noise-of-noise, record
  the tie and stop. Otherwise sweep both arms at `--trials 2` — trial-1 replays
  free from cache — and issue the standard 2-trial verdict. Never promote from
  a 1-trial screen.

  The threshold reads `noise_strict`, not the combined `noise`, and the band is
  the one that module's own A-vs-A measured — not a constant borrowed from
  another module (the 1.1/task figure this rule used to name came from review's
  A-vs-A and was never re-derived elsewhere). Both corrections have one cause:
  `noise` is noise_strict + nitpick, and nitpick is a judge's classification of
  findings that matched no ground-truth item, so it tracks judge taste rather
  than executor behavior. Recon's A-vs-A (EXP-011) measured it swinging 1.33
  findings/task between IDENTICAL champion arms at an MDE of 1.50, while
  `noise_strict` moved 0.00 → 0.33. An escalation trigger on the combined axis
  therefore fires on judge variance and says nothing about the variant — which
  is exactly what it did to EXP-013. A module that has not run its A-vs-A has no
  band and cannot screen at all; that part is unchanged.

## Scoring

1. **Parse** (mechanical, `loop_lib.py parse`) — the module's output contract
   into findings JSON.
2. **Judge** (reference-guided, binary per rubric item — the regime where
   judges are strongest: MT-Bench 70%→15% failure drop) — blind, shuffled,
   different family, no-guess escape. Contract and calibration duty:
   `judge/README.md`. Unmatched findings are bucketed
   plausible-real / noise / nitpick, never auto-counted false-positive.
3. **Metrics + reducers** (`score.sh finish`) — per-trial rows (recall_must,
   recall_weighted, noise, noise_strict, nitpick, precision_proxy, tokens,
   wall) plus a per-task `pass` from the module's `pass_expr`
   (`negative_pass_expr` for negative tasks), reduced over trials as
   mean / pass@k / pass^k (Inspect epoch reducers): pass@k for "one good
   review among k", pass^k for "reliable every run".

## Statistics

The task is the unit of randomization. `compare.sh`: paired per-task deltas,
seeded task-clustered bootstrap CI (shared `evals/lib/eval-stats.sh`), and the
**MDE** (CI half-width) printed with every verdict — "no difference" and "no
power" are different findings (Error Bars paper). A-vs-A first on any new
benchmark or model: it must come back a tie and it measures the noise floor —
run its second arm with `--no-cache`, or identical prompts replay the first
arm's cached responses and the tie is fake.
Screening minimum: 2 trials (single-trial effects exaggerate — measured on H3).

## The cycle (mechanics in `loop.sh`, judgment in the /eval-loop skill)

1. **Error analysis** — read failing transcripts of the latest champion run;
   name the failure pattern. Automated optimizers hill-climb existing metrics;
   only transcript reading discovers new failure classes.
2. **EXP file** (`experiments/EXP-NNN.md`) — hypothesis, ONE change,
   prediction before the run, success gate. Ties get recorded too.
3. **Screen** — `loop.sh screen` (probe → --yes → candidate + champion sweeps
   on dev → judge prep).
4. **Confirm** — `loop.sh confirm` on holdout, second model family.
5. **Promote** — land the skill edit, full `tests/run-all.sh` + authoring
   lint, ledger line in `runs.jsonl`, `sync-champion.sh`.
6. **Suite hygiene** — harvest real failures into new tasks (a production miss
   is worth more than any synthetic task), keep negative tasks in the mix,
   watch saturation (~100% pass = the suite stopped measuring; refresh), grow
   toward 20–50 tasks per module.

Judge calibration runs on its own cadence: `judge/calibration/kappa.py`
sample → human labels → κ/TPR/TNR; re-shadow after judge-prompt or model
changes.

## Non-goals (decided, don't re-propose without new evidence)

- **Wholesale promptfoo/Inspect adoption** — Node/Python runtime for what
  bash+jq already does here; neither drives an agentic CLI workspace natively.
- **MIPRO-style optimizers** — need 200+ tasks; at our n they memorize the
  suite. GEPA is the only envelope-compatible optimizer (3+ examples,
  reflective mutation on textual feedback) and may later run as a last-mile
  step on ≤9 dev tasks with holdout untouched — off by default.
- **A paid third-model judge as the default** — Claude subagents are free and
  a different family from the executor; the paid path stays a fallback.
