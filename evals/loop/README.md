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
(staging: mode git|patch; git mode names a `repo_alias` resolved through the
gitignored `repos.local.json` — copy `repos.local.example.json`) +
`rubric.json` (`{version, negative, items}` — bump `version` on ANY edit) +
`tree/`+`change.patch` for planted tasks. Committed task content is
anonymized: no source-repo names, PR/ticket numbers, usernames, or local
paths (the /eval-loop skill's iron rule carries the full list).

Ledger: promotion decisions append one line to `runs.jsonl`; hypotheses and
verdicts live in `experiments/EXP-NNN.md` (template provided). `runs/` and
`cache/` are gitignored.
