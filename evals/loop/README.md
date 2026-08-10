# evals/loop — quickstart

Design and rationale: [DESIGN.md](DESIGN.md). Driven interactively by the
repo-local `/eval-loop` skill; raw commands:

```bash
# 0. Refresh the champion snapshot after any landed skill change
bash sync-champion.sh --module review

# 1. What would it cost? (assembles everything, calls nothing / one probe call)
bash run.sh --module review --tasks modules/review/benchmarks/dev --dry-run
bash run.sh --module review --tasks modules/review/benchmarks/dev --probe

# 2. Screen a variant against the champion on the dev set
bash loop.sh screen --module review --variant modules/review/variants/<exp> --yes

# 3. Judge: spawn blind Claude subagents per adapters/claude-subagent.md
#    (each Writes match.json), or the paid fallback:
bash score.sh runs/scratch/<run> --phase judge --judge-model gpt-5.2

# 4. Verdict (finish scoring + paired comparison + MDE)
bash loop.sh verdict runs/scratch/<cand> runs/scratch/<champion>

# 5. After a screen win: confirm on holdout with a second model family
bash loop.sh confirm --module review --variant modules/review/variants/<exp> \
  --model cursor-grok-4.5-medium --yes
```

Task anatomy (`modules/<m>/benchmarks/{dev,holdout}/<id>/`): `task.json`
(staging: mode git|patch|spec; `git` names a `repo_alias` resolved through the
gitignored `repos.local.json` — copy `repos.local.example.json`; `spec` takes
that, or a public `repo_url` shallow-fetched into `cache/repos/`) +
`rubric.json` (`{version, negative, items}` — bump `version` on ANY edit) +
`tree/`+`change.patch` for planted tasks. `spec` mode is for an artifact-under-test
module: it stages the tree at `base_sha` with no diff and materializes the
`spec.md` beside it. Pinning the tree is what separates "the claim was wrong"
from "the tree moved on" — an unpinned run over a historical spec measures
whether it shipped, not whether it was right. Committed task content is
anonymized: no source-repo names, PR/ticket numbers, usernames, or local
paths (the /eval-loop skill's iron rule carries the full list).

**Tasks mined from a private repo are NOT committed.** Their ground truth is that
repo's real file paths, and a rubric matches by path against a tree staged from
it — so anonymizing the paths breaks the task rather than protecting it. This
repository is public, so those tasks live in a gitignored
`modules/<m>/benchmarks.local/{dev,holdout}/` beside `repos.local.json`, and the
committed `benchmarks/` holds only fully synthetic tasks. Point a sweep at them
the usual way:

```bash
bash run.sh --module review --tasks modules/review/benchmarks.local/dev --dry-run
```

A clone therefore reproduces the synthetic suite only; the private half travels
with the machine that has the source repo. Scores from the two sets are not
comparable and must not be pooled — `compare.sh` pairs by task id, so run one
set at a time.

Ledger: promotion decisions append one line to `runs.jsonl`; hypotheses and
verdicts live in `experiments/EXP-NNN.md` (template provided). `runs/` and
`cache/` are gitignored.
