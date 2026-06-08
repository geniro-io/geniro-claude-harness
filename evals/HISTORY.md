# Eval history ledger

One row per version-vs-version eval run, appended by `evals/lib/ledger-append.sh`
(via `evals/ingest.sh`). The machine-readable source of truth is `evals/history.jsonl`;
this table is its human mirror and can be regenerated from it.

**Read discipline (plan §6):** consult this table BEFORE a run only to recall the current
champion ref. Do NOT read the trend before the blind verdict is fixed — that re-introduces
the anchoring bias the machine judge is designed to avoid. Read the trend post-hoc via
`/geniro:eval`.

Promotion gates on **one primary metric** clearing its task-clustered CI (plan §9); cost,
time, and pass-rate are reported, not gated. A delta inside the CI is a tie, not a win.

| Date | Skill | Cand | vs | Primary (winrate, CI) | Recall^k | κ | Cost Δ | Time Δ | Tasks×Trials | Sig | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-06-08 | plan | fe328c3 | fe328c3 | 0 [0,0] | — | — | 0.3177 | 71.12 | 1×1 | yes | — |
