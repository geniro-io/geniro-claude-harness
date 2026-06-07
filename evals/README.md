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
├── lib/
│   └── ledger-append.sh   the cross-run ledger writer (built on atomic_state_append + emit-learning pattern)
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

## What Phase A delivers (this PR)

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
- **The `/plan` suite** — `suites/plan/{evals.json,holdout.json}` in skill-creator's real
  schema (`{skill_name, evals:[{id,prompt,expected_output,files[],expectations[]}]}`), split
  into a dev partition (tuned against) and a held-out partition (gates promotion — plan §11).
  Bootstrap size (6 + 3); the 20–50-task target from regression history is Phase D.
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

## Read discipline

Consult `HISTORY.md` before a run only to recall the current champion ref. **Do not read the
trend before the blind verdict is fixed** — that re-introduces the anchoring bias the machine
judge is designed to avoid (plan §6, §15). Read the trend post-hoc via `/geniro:eval` (Phase D).

## Roadmap

Phase 0 (driver) ✅ · **Phase A (this PR)** · Phase B (ingest: cost + CIs) · Phase C (first real
`/plan` run + measure $/time) · Phase D (`/review` calibration + κ + 20–50 tasks + cross-family
judge + `/geniro:eval`) · Phase E (end-to-end + `analyze-thread` trajectory).
