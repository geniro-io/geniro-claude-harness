# cursor-review — cheap eval loop for /geniro:review content

> **Superseded by [`evals/loop/`](../loop/)** — the module-agnostic v2 stand
> (rubric versioning, content-keyed cache, built-in cost guard, judge
> calibration, trial reducers, experiment registry). This directory is the
> frozen v1 reference: its 14 tasks migrated to
> `loop/modules/review/benchmarks/`, its `runs.jsonl` stays the historical
> record of the H1–H6 experiments. Iterate in `loop/`, not here.

Design and rationale: [DESIGN.md](DESIGN.md). One-command flow:

```bash
# 0. Refresh the champion snapshot after any landed skill change
bash sync-champion.sh

# 1. Run a variant over a task set (background-friendly; cents per call)
bash driver.sh --variant variants/champion --tasks tasks/dev \
  --trials 2 --model cursor-grok-4.5-medium --out runs/<name>

# 2. Score: parse findings + build blind judge prompts
bash score.sh runs/<name> --phase prep
#    ... judge: the orchestrating Claude session spawns blind subagents that
#    Write match.json per trial (preferred, free), or fallback:
bash score.sh runs/<name> --phase judge --judge-model gpt-5.2
#    ... then metrics:
bash score.sh runs/<name> --phase finish

# 3. Paired verdict vs the champion run
bash compare.sh runs/<candidate> runs/<champion-baseline>
```

Task anatomy (`tasks/dev/<id>/`): `task.json` (mode git|patch, staging inputs,
`project_context`), `ground_truth.json` (defect list with `must_find` flags),
plus `tree/` + `change.patch` for planted tasks. `tasks/holdout/` is never read
while tuning; it gates promotion.

Conventions: the executor model is pinned per experiment sweep; the judge is a
different model family (or the orchestrating Claude session), blind to variant
identity, finding order shuffled. `runs/` is gitignored; promotion decisions and
their numbers go into the experiment log kept by the orchestrator.
