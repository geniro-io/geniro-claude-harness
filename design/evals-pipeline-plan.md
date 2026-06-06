# Evals pipeline — implementation plan

Status: PLAN (not yet implemented). Owner: maintainer. Branch: `claude/harness-model-evals-LO2Hm`.

Purpose of this document: describe how to build a local-run evaluation pipeline that compares
two versions of this plugin's skills/agents/prompts and answers one question per run —
**"is the new version better, and by how much, across quality + speed + cost?"** — while
accumulating every run's result into a committed history that each new run reads back as context.

---

## 1. Goal

A maintainer-run (local) command that:

1. Takes a **baseline** version (the current champion — a git ref) and a **candidate** version
   (usually the working tree / HEAD).
2. Runs a fixed set of realistic tasks through each version's skills, in a clean environment,
   K trials each (default 3) because skill behavior is non-deterministic.
3. Produces three classes of signal per task:
   - **Quality** — blind pairwise judge (candidate vs baseline artifact), the load-bearing metric.
   - **Efficiency** — cost (USD), steps (tool-calls / turns), wall-time.
   - **Discipline** — deterministic pass/fail on the plugin's own safety invariants and pipeline
     contract (e.g. `/refactor` never pushes, spawn omits `model=`, spec has 11 sections).
4. **Appends the run to a committed history** (`evals/history.jsonl` + `evals/HISTORY.md`).
5. **Reads the full history back into the analyzer's context** so the verdict is trend-aware
   ("4th version; quality up 3 runs straight, but cost crept +30% — net positive but watch latency"),
   not just an isolated A-vs-B snapshot.
6. Emits a per-run report (quality delta, efficiency delta, regressions) and a new HISTORY.md row.

## 2. Non-goals

- Not a CI gate on every push (the run costs real subscription credits — see §11). CI is an
  optional later step, manual-trigger only.
- Not a replacement for `tests/run-all.sh` — that stays as the deterministic unit-test floor for
  `lib/` and `hooks/`. This pipeline sits one layer up: behavioral / agentic quality.
- Not a SaaS eval platform (Braintrust / LangSmith). Everything runs locally and lives in the repo.

## 3. Core design decisions (with rationale)

| Decision | Choice | Why |
|---|---|---|
| Unit under test | A whole Claude Code session running a plugin skill on a fixture repo | The thing that changes between versions is skill/agent markdown driving multi-turn tool use — not a single prompt→completion. Prompt-only eval tools (promptfoo/DeepEval) can't run this. |
| Runner | Headless `claude --bare -p ... --output-format stream-json` | No extra dependency; `--bare` gives a clean environment per trial; stream-json exposes every event so steps/time are derivable. (Agent SDK is the alternative — see §13 open decisions.) |
| Quality metric | Blind pairwise (candidate vs baseline), position-swapped, 3-judge majority | "Better relative to" is far more stable from an LLM judge than an absolute 1–5 score. Position-swap cancels order bias; majority cancels judge noise. |
| Subjective skills | No assertions — judge qualitatively only | Per skill-creator guidance: writing-quality / design-soundness can't be a numeric assertion. Assertions are for objective output (generated code, extracted clauses, file structure). |
| History | Committed `history.jsonl` (append-only) + `HISTORY.md` (human table) | The maintainer's explicit requirement: one place, pushed to the repo, holding all prior + current results, fed back into each run. |
| Raw transcripts | Gitignored under `evals/runs/` | Large, noisy, contain local paths; would churn the repo. Only the distilled per-run record is committed. |
| Verdict gating | severity classes + exit codes (borrowed from TribeAI/claude-evals) | Gives a crisp local verdict and makes a future CI gate a one-line change. |

## 4. Directory layout

```
evals/
  README.md                         # how to run it
  run-eval.sh                       # orchestrator (entry point)
  lib/
    capture-metrics.sh              # parse stream-json → {cost, steps, wall_time}
    severity.sh                     # delta → CRITICAL/HIGH/MEDIUM/LOW + exit code
  agents/
    comparator.md                   # blind pairwise quality judge (vendored from skill-creator, adapted)
    analyzer.md                     # trend analysis over history.jsonl (vendored, adapted)
    grader.md                       # assertion + trajectory grading (reuses analyze-thread)
  suites/
    review/
      001-planted-bugs.json         # {prompt, args, fixture, assertions[], planted_bugs[]}
      fixtures/repo-with-bugs/      # committed fixture repo state
    plan/
      001-vague-feature.json
    implement/
      001-small-task.json
  baseline.json                     # current champion: git ref + per-suite metrics
  history.jsonl                     # APPEND-ONLY committed record (fed to analyzer)
  HISTORY.md                        # human-readable cumulative scorecard (one row per version)
  runs/                             # GITIGNORED raw transcripts + per-trial outputs
    <timestamp>-<candidate-ref>/
      review/001/{baseline,candidate}/trial-{1,2,3}/{transcript.jsonl,outputs/,timing.json,grading.json}
```

Add to `.gitignore`: `evals/runs/`.

## 5. The two evaluation layers

**Layer 1 — deterministic discipline (cheap, high-signal, no LLM).**
Assertions encoded per task, checked by a script against the candidate's artifacts + transcript:
- Safety invariants the plugin already documents in its anti-rationalization tables:
  - `/refactor`, `/debug`, `/investigate` produce NO `git push` / `gh pr create` in the transcript.
  - `/review` posts nothing while `open_questions[]` are unresolved.
  - Plugin-agent spawns omit `model=`.
  - Parallel-spawn batches land in one assistant turn (not serialized).
  - `spec.md` carries the 11-section schema; state written via `atomic_state_write`.
- Output-shape checks: expected file created, expected JSON field present, planted bug referenced.

These are the floor. Start here — they catch pipeline regressions instantly and need no judge.

**Layer 2 — behavioral quality (LLM judge, the part the maintainer actually wants).**
Blind pairwise comparator over the produced artifacts (the `spec.md`, the review report, the diff),
plus — for `/review` and `/debug` — the **planted-bug** technique: a fixture repo seeded with N known
bugs, scored on **recall** (bugs caught / N) and **precision** (1 − false-positives / total-flagged).
Planted-bug gives a hard number on top of the pairwise verdict.

## 6. Run flow (step by step)

```
run-eval.sh --baseline <ref|baseline.json> --candidate <HEAD|ref> --suites review,plan --trials 3
```

1. **Resolve versions.** Baseline ref from `baseline.json` (or `--baseline`); candidate = working tree
   or `--candidate <ref>`. Materialize each in its own git worktree so a clean checkout backs each side.
2. **Execute.** For each task × {baseline, candidate} × K trials, run the skill headless:
   `claude --bare -p "<task prompt + args>" --allowedTools "..." --max-turns N --output-format stream-json`
   inside the task's fixture repo. Save `transcript.jsonl` + produced `outputs/`.
3. **Capture metrics** (`capture-metrics.sh`): `total_cost_usd` straight from the result event;
   **steps** = count of `tool_use` events / assistant turns in stream-json; **wall_time** = last-minus-first
   event timestamp (or shell-clock around the process). Write `timing.json {cost_usd, steps, wall_seconds, total_tokens}`.
4. **Grade discipline** (`grader.md` + script + `analyze-thread`): run Layer-1 assertions against
   transcript+outputs → `grading.json {expectations:[{text, passed, evidence}]}`.
5. **Judge quality** (`comparator.md`): for each task, hand the judge the baseline artifact and candidate
   artifact unlabeled, in both orders, 3 votes, with the per-suite rubric. Record winner + rationale.
6. **Analyze with history** (`analyzer.md`): feed the analyzer the new aggregate **plus the tail of
   `history.jsonl`**. It outputs: per-dimension deltas, trend across versions, flaky/non-discriminating
   assertions, and the final verdict + severity.
7. **Persist.** Append one record to `history.jsonl`; append one row to `HISTORY.md`; on a clear win,
   update `baseline.json` to the candidate ref (maintainer confirms — not automatic).
8. **Report.** Print the per-run report and the new HISTORY.md row to the terminal; exit with the
   severity code.

## 7. History mechanism (the committed record fed back into each run)

This is the maintainer's central requirement. Two committed artifacts:

**`evals/history.jsonl`** — append-only, one record per run (machine-readable, fed to the analyzer):
```json
{
  "run_id": "2026-06-06T10:30:00Z",
  "baseline_ref": "a1b2c3d",
  "candidate_ref": "e4f5g6h",
  "trials": 3,
  "suites": {
    "review": {
      "quality_winrate_vs_baseline": 0.78,
      "recall": 0.90, "precision": 0.85,
      "mean_cost_usd": 0.42, "cost_delta": -0.05,
      "mean_steps": 14, "steps_delta": -2,
      "mean_wall_seconds": 31.0, "time_delta": 1.4,
      "discipline_pass_rate": 1.0
    }
  },
  "verdict": "candidate better",
  "severity": "LOW",
  "notes": "review precision up; cost down"
}
```

**`evals/HISTORY.md`** — human-readable cumulative table (one row per run), e.g.:

| Date | Candidate | vs | Quality (winrate) | Cost Δ | Steps Δ | Time Δ | Discipline | Verdict |
|---|---|---|---|---|---|---|---|---|
| 2026-06-06 | e4f5g6h | a1b2c3d | 0.78 | −12% | −2 | +1.4s | 100% | ✅ better |

The analyzer reads `history.jsonl` so its verdict is **trend-aware**: it can say "quality has improved
three runs running, but cumulative cost is up 30% since the first recorded version" — exactly the
"take the history into context" behavior requested. Because the file is committed, the trend survives
across machines and sessions.

## 8. Metrics captured per version (the maintainer's "quality + speed + cost + maybe more")

| Metric | Source | Notes |
|---|---|---|
| Quality | comparator pairwise winrate; planted-bug recall/precision | load-bearing |
| Cost (USD) | `total_cost_usd` from result event | direct |
| Steps | count `tool_use` / turns in stream-json (reuse `analyze-thread`) | derived |
| Wall-time | event-timestamp span or shell clock | derived |
| Tokens | summed usage from stream-json | "maybe more" |
| Discipline | Layer-1 assertion pass rate | regression tripwire |
| Trajectory health | `analyze-thread` findings (wrong tier, missed parallel-spawn, premature completion) | "maybe more" — uniquely valuable for this plugin |

## 9. The judge (comparator) — and a hard constraint

The quality judge is a **separate `claude -p` invocation** running `agents/comparator.md`, NOT a direct
Anthropic Messages API call. Reason: if the pipeline authenticates via a subscription OAuth token
(`CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token`), that token is **inference-only and rejected by the
Messages API** — it works only inside Claude Code. So every model call in the pipeline (executor AND judge)
must go through `claude -p`. Judge model: Opus for accuracy on infrequent local runs, or Sonnet if run
frequency makes cost matter (open decision §13).

Variance control (from TribeAI/claude-evals): run the judge twice; if the two verdicts disagree, take the
majority of a third. Cheaper than always running three.

## 10. Reuse of Anthropic's skill-creator

skill-creator (in `anthropics/skills`) ships an Eval/Improve/Benchmark workflow with four sub-agents
(executor / grader / comparator / analyzer) and concrete file formats. Decision: **vendor its prompts and
formats, own the orchestrator.**

Take directly:
- `agents/comparator.md`, `agents/grader.md`, `agents/analyzer.md` prompt bodies as starting points.
- File formats: `grading.json {text, passed, evidence}`, `timing.json {total_tokens, duration_ms}`,
  `benchmark.json` with `pass_rate ± stderr` + `deltas`, and the `evals.json` assertion schema
  (`type: exact_match|contains|regex|numeric|custom`).
- The **analyzer's pattern detection** (non-discriminating assertions that always pass = dead weight;
  high-variance flaky evals; time/token tradeoffs).
- The **trigger eval set** idea (`{query, should_trigger}`, ~20 cases) for tuning each skill's
  `description:` frontmatter — directly relevant given 11 active skills + 8 deleted-with-routing.

Build our own (skill-creator does NOT cover these):
- Unit under test = a full plugin skill running on a **fixture repo**, not "skill vs no-skill" on a
  single prompt.
- **Trajectory grading** via `analyze-thread` (skill-creator grades outputs only).
- The committed **cross-run history** fed back as analyzer context (skill-creator keeps per-iteration
  workspaces, no cumulative committed ledger).
- Baseline = a **git ref of the previous champion**, not "the model with no skill."

## 11. Subscription / cost note (affects how often this can run)

If authenticating via subscription OAuth token: as of **2026-06-15**, `claude -p` / Agent SDK usage on
subscription plans draws from a **separate monthly Agent SDK credit pool**, distinct from interactive
limits. A full matrix (suites × tasks × 3 trials × 2 versions × judge calls) consumes that pool fast.
Mitigations baked into the design:
- Keep trials low (3) and suites small to start.
- Per-task `max_budget_usd` ceiling (skip/flag a task that blows it).
- Run locally on demand, not per-push.

## 12. CI (optional, later)

Keep the design CI-ready but don't wire it yet. When wanted: a `workflow_dispatch` workflow that runs
`run-eval.sh`, uploads `evals/runs/` as a build artifact (never committed), and commits the new
`history.jsonl` + `HISTORY.md` rows. Auth via `CLAUDE_CODE_OAUTH_TOKEN` secret. The severity exit code
from §3 becomes the gate.

## 13. Open decisions (maintainer to mark before build)

1. **Runner:** headless `claude --bare -p` (zero deps, recommended) vs Agent SDK (Python/TS — richer
   lifecycle hooks, adds a dependency).
2. **Reporting:** own markdown scorecard (`HISTORY.md`, minimal, recommended) vs wrap in promptfoo
   (matrix UI, adds a dependency).
3. **Judge model:** Opus (accuracy, pricier) vs Sonnet (cheaper for frequent runs).
4. **First skill to instrument:** recommend `/review` (planted-bug gives an immediate hard number),
   then expand to `/plan` and `/implement`.

## 14. Phased build plan

- **Phase A — skeleton.** `evals/` tree, `.gitignore` entry, `run-eval.sh` that runs one `/review` task
  headless against a fixture and dumps a transcript. No judge yet.
- **Phase B — metrics + discipline.** `capture-metrics.sh` (cost/steps/time) + Layer-1 assertion grader
  reusing `analyze-thread`. First `timing.json` + `grading.json`.
- **Phase C — quality judge.** Vendored `comparator.md`, blind pairwise with position-swap + majority,
  per-suite rubric. Planted-bug fixture for `/review` with recall/precision.
- **Phase D — history + analyzer.** `history.jsonl` append, `HISTORY.md` row, `analyzer.md` reading the
  ledger for trend-aware verdicts. Severity + exit codes.
- **Phase E — expand + (optional) CI.** Add `/plan`, `/implement` suites; trigger-eval set for
  `description:` tuning; optional `workflow_dispatch` workflow.

## 15. Prior art references

- anthropics/skills — skill-creator (executor/grader/comparator/analyzer, file formats, trigger evals).
- TribeAI/claude-evals — golden dataset, deterministic+judge+human-queue, severity gating + exit codes,
  per-case budget, judge variance reduction.
- wshobson/agents — plugin-eval (static + LLM-judge layers).
- Anthropic engineering — "Demystifying evals for AI agents" (pass@k vs pass^k, grade outcomes not path,
  read transcripts, start at 20–50 tasks).
