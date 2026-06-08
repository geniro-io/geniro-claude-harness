# Phase C — first live-run findings

The first real A-vs-A run (`fe328c3` vs `fe328c3`, 1 task, 1 trial, `/geniro:plan`) validated the
pipeline end-to-end and surfaced the items below. These are **logged follow-ups**, not blockers for
the tsx-resolution fix that shipped with this PR.

## Validated ✅
- **Cost model is exact.** The cache-aware formula reproduces the SDK's `total_cost_usd` to the cent
  on both runs (candidate `$2.2760`, baseline `$1.7272`); cache reads are ~99.5% of the input side,
  exactly as the design assumed. (plan decision 10 confirmed on real data.)
- **End-to-end plumbing works:** 2 real `/plan` runs on `claude-opus-4-8[1m]`, gates auto-answered,
  specs produced + graded 5/5, position-swapped comparison, aggregation, ingest, gate evaluation.

> The A-vs-A calibration did **not** confirm gate safety — it **exposed a false-significance bug**
> (F5 below). That is the calibration doing its job (plan decision 4).

## Follow-ups

### F5 (CRITICAL — gate correctness) — zero-variance sample → zero-width CI → false significance → false-promotion risk
The inaugural A-vs-A row came back `quality_winrate_vs_baseline: 0`, `quality_ci: [0, 0]`,
`significant_on_primary: true`. With 1 task × 1 trial — or **any** sample where all task clusters
agree — the task-clustered CI has zero width, so the significance test ("CI excludes the 0.5 null")
passes trivially. Here `primary_beats_null` was `false` only because the single comparison landed at
0; **had it gone the other way (`value = 1` → `CI = [1,1]`), `primary_beats_null` would be
`1 > 0.5 = true` and the gate would have PROMOTED two identical versions.** This is exactly the
false-promotion the A-vs-A calibration exists to catch (plan decision 4): at n=1 the gate is **not
safe**, and the degeneracy is not unique to n=1 (any zero-variance cluster set trips it — e.g. all
trials agreeing on a modest real effect). Fix before trusting the gate: require a minimum
cluster/trial count for significance, treat a zero-width CI as not-significant, and/or apply a
variance floor / continuity correction. **Blocker for relying on the promotion gate.**

### F1 — `length_confounded` keys on executor output tokens, not artifact length
The flag came back `true` (candidate 24,830 vs baseline 19,307 output tokens) although the two specs
are nearly identical length (3,826 vs 3,421 chars; 87 vs 86 lines). It's measuring *process* tokens
(thinking + tool use), not the compared artifact. Base the confound heuristic on the spec length.

### F2 — the judge's reasoning is computed, then discarded *and* orphaned at the repo root
`run-suite.sh` writes only `{"primary_value": N}` into `eval-*/comparison.json`; the comparator's full
output (winner, rubric scores, reasoning) is written to a CWD-root temp file and left behind as
untracked litter (it also blocks `ingest`'s clean-tree guard). The discarded reasoning is valuable —
on this run it showed the A-vs-A "loss" was driven by **real run-to-run quality variance in `/plan`**
(one sample populated the Risk section + checkpoints + used m5-v2; the other used
`"none — task scope precludes"` + empty checkpoints + m5-v1), not noise. Persist per-order winners +
reasoning into the workspace; stop writing temp files to CWD.

### F3 — single-trial A-vs-A is degenerate; "expect a TIE" needs an n≥k caveat
`primary_value` over one swapped pair is a coin flip (0 / 0.5 / 1). "Expect a TIE" is a statement
about the *expected value over many trials*, not any single trial. The statistical null property
needs trials ≥ ~5–10. Add the caveat to run-suite's messaging and the README; treat n=1 as a
plumbing smoke, not a calibration.

### F4 — `ingest`'s shared-ledger redirect surprises pre-merge
By design (`evals/README.md`), `ingest` writes the row to the **primary** worktree's shared ledger,
not the worktree it ran in. Correct once the tooling is on `main`; but when run from an unmerged
feature-branch worktree, the row lands on `main` rather than the PR branch. Either surface this in
run-suite output, or add an opt-in `--ledger-here` for pre-merge validation runs.
