---
name: eval-loop
description: "Use when improving a plugin module through the evals/loop measurement cycle — proposing a hypothesis, screening a variant against the champion, judging runs, reading verdicts, confirming on holdout, promoting a winner, calibrating the judge, or growing a benchmark. Owns the judgment half of the loop (error analysis, EXP files, blind judge subagents, spend approval, promotion) on top of the mechanical scripts. Skip for one-off plugin fixes (/improve-template)."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite]
argument-hint: "[status | experiment <hypothesis> | judge <run-dir> | verdict <cand> <base> | confirm | promote EXP-NNN | calibrate <run-dir> | add-task | <free text>]"
---

# eval-loop — drive the module improvement cycle

Working dir for everything here: `evals/loop/`. Read its `DESIGN.md` on first
use in a session. Mechanics live in the scripts; this skill supplies the
judgment the scripts deliberately do not encode.

## Iron rules (hold at every step)

- **Money asks first.** Before ANY paid sweep: run `run.sh --probe`, put the
  extrapolated cost in a chat message, and get an AskUserQuestion approval
  naming the dollar figure. Never launch on a stale rate — after a change to
  task shape, workspace size, or model, the probe is mandatory
  (`adapters/cursor-prices.json` §rule). Judging via Claude subagents is free;
  the `--phase judge` CLI fallback is paid and needs the same approval.
- **Holdout stays dark.** Never open holdout task/rubric content while a
  variant is being tuned. `loop.sh confirm` runs it; you read only its scores.
- **One change per experiment**, named in an EXP file BEFORE the screen run,
  with the prediction written down. A tie is a result — record it.
- **Rubric edits bump `version`** (integer, any edit) — and invalidate every
  standing baseline run for that task; re-sweep the champion before comparing.
- **Read transcripts before trusting numbers.** No verdict is reported to the
  user until you have opened at least the failing trials' findings and one
  judge verdict and confirmed the failures look fair.
- **Committed benchmark content is anonymized.** Tasks mined from a real
  repository never carry, in any committed file: the repo/company/product
  name, tracker ticket IDs, PR/issue numbers (including in task ids —
  `real-N`, never `pr-1234`), usernames or people's names, email domains,
  review-comment IDs, or machine-local paths. Repo location goes through
  `repo_alias` + the gitignored `repos.local.json`; commit SHAs and in-repo
  file paths are fine (needed for staging and matching). Before committing a
  new task, grep it for the source repo's name, the ticket prefix, and the
  author handles — this repo is public, the benchmark sources are not.

## Intake

`status` or empty → report: current champion state (`git log` of the module's
shipped files vs `variants/champion/`), open EXP files, last ledger lines from
`runs.jsonl`, benchmark size dev/holdout, and suggest the next action.

Free text / `experiment <hypothesis>` → start the cycle at §1.

Other subcommands jump straight to their step below.

## The cycle

### 1. Error analysis → EXP file

Read the latest champion run's failing trials (`missed_must` in task rows;
the findings vs the rubric). Name the failure pattern with cited tasks. Draft
`experiments/EXP-NNN.md` from `TEMPLATE.md` (next free number), build the
variant dir under `modules/<m>/variants/` (only the delta files — resolution
falls back to champion). Show the user the hypothesis + predicted effect +
probe cost in a message, then one AUQ: run the screen / edit / drop.

### 2. Screen

`bash loop.sh screen --module <m> --variant <dir> --yes` (after the approval
above; it re-probes internally). On abort (exit 75) report the measured spend
and stop.

### 3. Judge (free path)

For each of the two runs: spawn parallel Claude subagents, one per
`results/*/trial-*/judge-prompt.txt`, batched ≤6 per response, each prompted
exactly: read THAT file only, follow its instructions, Write the verdict JSON
to `match.json` in the same directory. Blindness: the subagent gets the file
path and nothing else about variant identity. Verify every trial dir got a
`match.json` (spawn stragglers again); then `loop.sh verdict <cand> <base>`.

### 4. Verdict

Render the comparison as a self-contained chat message: per-task delta table,
CI, MDE, verdict line, plus your transcript-check note (§Iron rules). Then one
AUQ: confirm on holdout / iterate the variant / record as tie and stop.
Update the EXP file's Runs table either way.

### 5. Confirm

`bash loop.sh confirm --module <m> --variant <dir> --model <second-family>
--yes` after its own probe+approval. Same judge + verdict flow. Both screens
green → §6; holdout regression → record REJECTED with the numbers.

### 6. Promote

Only on explicit user approval, in this order: apply the variant delta to the
shipped skill files; `bash tests/run-all.sh` + authoring lint; append the
promotion line to `runs.jsonl` (jq-built JSON: exp id, run dirs, deltas, CIs,
model, date); `bash sync-champion.sh --module <m>`; mark the EXP file landed. The champion
baseline cache is now stale by definition — next screen re-sweeps it.

## Side jobs

- **`calibrate <run-dir>`** — `python3 judge/calibration/kappa.py sample <run>`;
  walk the user through labeling the pending file (batch rows into AUQs with
  the judge's verdict hidden until they answer); `kappa.py score`; report κ /
  TPR / TNR; κ < 0.6 → propose judge-prompt fixes as a normal EXP against
  `loop_lib.py judgeprompt`.
- **`add-task`** — from a real failure (production review miss, PR regression):
  stage inputs per `README.md` task anatomy, write the rubric with the user
  confirming each item's `must_find` + severity, `version: 1`, anonymized per
  §Iron rules (grep before commit). Prefer negative tasks when the failure was
  overtriggering. New task → champion baseline for that set is stale.
- **New module** — copy `modules/review/target.json` as the template: facets +
  criteria mapping, output contract + parser (a new output shape needs a
  parser in `loop_lib.py` first), pass exprs, champion_sync map; author
  `variants/champion/preamble.md` from the module's agent body; seed ≥6 dev +
  ≥2 holdout tasks before the first A-vs-A.
- **A-vs-A** — first run on any new benchmark, module, or executor model:
  champion vs champion must come back a tie; its CI width IS the noise floor.

## Reporting

Every user-facing verdict message carries: n tasks × k trials, the metric
deltas with CIs, the MDE sentence, spend actually measured, and what got
written where (EXP file, ledger). Lead with the verdict, not the process.
