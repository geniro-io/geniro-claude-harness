# evals/ — the geniro skill eval pipeline

Compare two versions of this plugin's skills/agents/prompts and answer, per run:
**"is the new version better, and by how much, across quality + speed + cost?"** — run
locally, by hand, accumulating every run into a committed ledger. Full design:
[`design/evals-pipeline-plan.md`](../design/evals-pipeline-plan.md) (v5).

## Layout

```
evals/
├── run-harness/        Phase 0 — Agent-SDK canUseTool driver (subscription, auto-answers gates)
│   └── README.md       how it bills, the driver flags, the approve-default-v1 policy
├── run-suite.sh        Phase C — the one-command §6 loop: drive A/B → grade → swap-compare → aggregate → ingest
├── aggregate-runs.sh   Phase C — glue: a benchmark WORKSPACE (run dirs + grader/comparator output) → benchmark.json
├── ingest.sh           Phase B — derive cost/CIs/gate from a benchmark.json, append one ledger run
├── BENCHMARK-SCHEMA.md the benchmark.json contract (ingest reads it; aggregate-runs.sh writes it)
├── vendor/skills/      Phase C — skill-creator pinned as a submodule @ da20c925 (grader.md/comparator.md prompts)
├── lib/
│   ├── ledger-append.sh   the cross-run ledger writer (built on atomic_state_append + emit-learning pattern)
│   └── eval-stats.sh      single-sourced stats math (Wilson + task-clustered seeded bootstrap), like score-formula.sh
├── fixtures/
│   └── benchmark.example.json   a conforming benchmark.json (the ingest tests run against it)
├── scripts/
│   └── seed-ledger.sh      one-time: seed HISTORY.md (single-sourced header) + empty history.jsonl
├── suites/
│   └── plan/
│       ├── evals.json     dev partition  — the candidate IS tuned against these
│       ├── holdout.json   held-out       — never tuned against; gates promotion
│       └── PARTITION.md   the partition discipline (why held-out exists)
├── price-map.json      per-model $/MTok (committed) — cost is DERIVED, not emitted by skill-creator
├── history.jsonl       append-only ledger, one record per run (machine source of truth)
└── HISTORY.md          human mirror of history.jsonl, one row per run
```

The cross-skill seam check lives in **`tests/seam/plan-review-implement-contract.sh`** (not
here) so the existing `tests/run-all.sh` auto-discovers it (plan §11, decision 15).

## What Phase A delivers (shipped, PR #27)

The bookkeeping + suite scaffolding the methodology sits on — everything except the cost/CI
math (Phase B `ingest.sh`) and the real runs (Phase C+):

- **The ledger writer** (`lib/ledger-append.sh`) — reads one JSON record on stdin, appends a
  normalised line to `history.jsonl` and a row to `HISTORY.md`. Modelled on
  `lib/emit-learning.sh`'s producer contract: auto-injects `run_id`, redacts the free-text
  `notes` via `redact_secrets`, dedups on `run_id` (a run is immutable → re-ingest is a no-op),
  and enforces the 4094-byte atomic-append ceiling. `history.jsonl` is the source of truth;
  `HISTORY.md` is a regenerable mirror. Covered by `tests/evals/ledger-append.sh`.
- **`price-map.json`** — versioned per-model token prices. The ledger stamps
  `cost_derived_from: "tokens*price-map@v1"` so a row's cost is reproducible against this map
  version. Re-resolve + bump `version` when model IDs are re-resolved (plan decision 3).
- **The suites** — `suites/<skill>/{evals.json,holdout.json,PARTITION.md}` in skill-creator's real
  schema (`{skill_name, evals:[{id,prompt,expected_output,files[],expectations[]}]}`), each split
  into a dev partition (tuned against) and a held-out partition (gates promotion — plan §11).
  All bootstrap size (6 + 3); the 20–50-task target from regression history is Phase D.
  - `plan` — runnable today.
  - `review`, `implement` — **suite data only; not yet runnable.** Each needs a per-skill fixture
    (the harness builds a `/plan` one) and an auto-answer policy that DENIES the ship-mode and
    post-to-PR picks. `run-suite.sh` refuses these two under `approve-default-v1` and exits 64
    rather than approving a gate that commits, pushes, opens a PR, or posts a review for real.
    Set `EVAL_AUQ_POLICY` to a denying policy to clear it. These two skills are where an
    instruction change is most likely to cost something, which is why their tasks target gates
    rather than output shape — see each suite's `PARTITION.md`.
- **The seeded ledger** — `history.jsonl` (empty) + `HISTORY.md` (header only, zero rows).
- **The seam check** — `tests/seam/plan-review-implement-contract.sh`, judge-free, no trials,
  no cost: it pins the `/plan`→`/review` `workflow_refs[]` contract and the `/review`→`/implement`
  `open_questions[]` handoff contract that per-skill artifact grading is blind to.

## The ledger record (plan §8)

One JSON object per run in `history.jsonl`. The writer requires `skill`, `baseline_ref`,
`candidate_ref`; `ingest.sh` (Phase B) supplies the derived fields (cost from tokens × price
map, per-metric CIs clustered at task, the primary-metric gate, `attempt_no`,
`instructions_digest`). See plan §8 for the full field reference. Hand-appending a smoke record:

```bash
echo '{"skill":"plan","baseline_ref":"<sha>","candidate_ref":"<sha>","notes":"manual smoke"}' \
  | bash -c 'source evals/lib/ledger-append.sh && ledger_append'
```

> **Where the ledger lives.** The runtime writer resolves the repo root via geniro's
> `_geniro_repo_root`, which **redirects writes from a linked worktree to the primary worktree**
> — so every worktree appends to ONE shared committed ledger. (`seed-ledger.sh` deliberately
> targets the local checkout instead, so the initial committed files land on the branch you're
> committing from.)

## What Phase B delivers (shipped, PR #28)

The math that turns a run into a ledger row — everything the harness can't measure on the
subscription (no per-token $) and the right CI per metric (plan §8/§9, §16):

- **`ingest.sh`** — `evals/ingest.sh <benchmark.json> --candidate <sha> --baseline <sha>
  [--notes …]`. Derives **cost** (tokens × `price-map.json`), the **right CI per metric**
  (Wilson for proportions; a **task-clustered, seeded bootstrap** for winrate/pass^k — the task
  is the unit of randomization), the **primary-metric gate** (`primary_beats_null`; a delta
  inside the CI is a tie), stamps `instructions_digest` + an incrementing `attempt_no`, and
  appends one record via `ledger-append.sh`. **Refuses a dirty tree or an unknown ref** (no
  fictional provenance) — it inspects the **eval worktree it runs in** (not the shared-ledger
  primary), and ignores its own ledger output so a sweep can batch before committing. Covered by
  `tests/evals/ingest.sh` (18 cases, incl. the LCG-bias, linked-worktree, and arg-hang regressions).
- **`lib/eval-stats.sh`** — the estimators as a single-sourced `$GENIRO_EVAL_STATS_JQ_DEFS`
  jq prologue (mirrors `lib/score-formula.sh`), so ingest and `/geniro:eval` (Phase D) can't
  drift on HOW a CI is computed. The bootstrap is **seeded** → the committed CI is reproducible
  on re-ingest. Covered by `tests/evals/eval-stats.sh` (11 cases).
- **`BENCHMARK-SCHEMA.md` + `fixtures/benchmark.example.json`** — the input contract (with
  field provenance) ingest reads, defined ahead of its Phase-C producer.

## What Phase C delivers (this PR)

The wiring that turns the Phase-0 harness into a one-command run that produces a real ledger
row — **plus the first real `/plan` measurement** (plan §16 Phase C):

- **skill-creator pinned as a submodule** (`evals/vendor/skills` @ `da20c925`) — freezes the
  reused `grader.md` / `comparator.md` prompts (decision 3). Prompts/scripts are pinned; eval
  *results* are not (the server-side judge drifts — that's what the CI gate + recorded model ids
  + κ are for). After a fresh clone: `git submodule update --init evals/vendor/skills`.
- **`aggregate-runs.sh`** — the glue from a benchmark **workspace** (per-trial `result.json` +
  `grading.json`, plus a position-swapped `comparison.json` per task) to a `benchmark.json`
  conforming to `BENCHMARK-SCHEMA.md`. Tokens come from `result.json`'s `model_usage` (the
  authoritative cumulative), **cache tiers preserved** so ingest prices them right; a task with no
  `primary_value` is a hard error. Covered by `tests/evals/aggregate-runs.sh` (8 cases).
- **`run-suite.sh`** — the §6 loop as one command (below). Drives A/B trials, grades the candidate,
  position-swap compares (both orders, averaged → `primary_value`), aggregates, and (`--ingest`)
  appends the row. `--dry-run` prints the matrix + a rough cost estimate and spends nothing.
  Covered by `tests/evals/run-suite.sh` (6 cases, incl. the position-swap-cancels-a-biased-judge
  property and the full aggregate→ingest chain, run with injected fakes — no spend).
- **Cache-aware cost** — `price-map.json` gained per-model `cache_read` / `cache_write` tiers and
  the `[1m]` model ids the SDK reports; `ingest.sh` now prices cache tokens (a geniro run is
  cache-read-dominated, so a flat fold over-counts ~4×). Validated against a real run's `costUSD`
  to the cent. Backward-compatible: a cache-less benchmark derives the identical cost (still `@v1`).
- **Driver nesting fix** — the driver strips `CLAUDECODE` so the headless run works when launched
  from inside a Claude Code session (mirrors skill-creator's `run_eval.py`).

### End-to-end: the §6 run loop (one command)

```bash
# 0. Recall the champion ref from HISTORY.md (only the ref — NOT the trend; plan §6, read discipline below).
# 1. Preview the matrix + rough cost, spend nothing:
bash evals/run-suite.sh --skill geniro:plan --suite evals/suites/plan/evals.json \
  --candidate <cand-sha> --baseline <base-sha> --trials 1 --dry-run
# 2. Run it (subscription; gates auto-answered). The FIRST real run is A-vs-A (same ref both sides):
#    it exercises the whole pipeline AND is the empirical-null calibration — it must come back a TIE.
bash evals/run-suite.sh --skill geniro:plan --suite evals/suites/plan/evals.json \
  --candidate <ref> --baseline <ref> --trials 1 --out evals/runs/plan-avsa
# 3. Inspect evals/runs/plan-avsa/benchmark.json, then append the committed row (or pass --ingest above):
bash evals/ingest.sh evals/runs/plan-avsa/benchmark.json --candidate <ref> --baseline <ref> \
  --notes "first /plan A-vs-A null calibration"
# 4. Read a sample of transcripts under the workspace before trusting the verdict (§6 step 5).
# 5. Commit the appended evals/history.jsonl + evals/HISTORY.md.
```

The harness bills against the **Claude Code subscription**, never the per-token API
(`approve-default-v1` auto-answers gates by the `(Recommended)` marker) — see
[`run-harness/README.md`](run-harness/README.md). The exact `benchmark.json` shape is
[`BENCHMARK-SCHEMA.md`](BENCHMARK-SCHEMA.md). Workspaces under `evals/runs/` are gitignored.

## Read discipline

Consult `HISTORY.md` before a run only to recall the current champion ref. **Do not read the
trend before the blind verdict is fixed** — that re-introduces the anchoring bias the machine
judge is designed to avoid (plan §6, §15). Read the trend post-hoc via `/geniro:eval` (Phase D).

## Roadmap

Phase 0 (driver) ✅ · Phase A (ledger + suites + seam) ✅ · Phase B (ingest: cost + CIs) ✅ ·
**Phase C (submodule + aggregate-runs + run-suite + cache-aware cost) — this PR** · Phase D
(`/review` calibration + κ + 20–50 tasks + cross-family judge + `/geniro:eval`) · Phase E
(end-to-end + `analyze-thread` trajectory).
