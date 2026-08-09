# cursor-review — cheap high-volume eval loop for the /geniro:review content layer

Improve `/geniro:review`'s *review content* — the dimension grid, the per-dimension
criteria, the reviewer prompt — by measuring every candidate change against a
ground-truth benchmark, at a cost low enough to run dozens of experiments.

## Why a second harness

The existing `evals/run-harness` drives the FULL skill through the Claude Agent SDK on
the Claude subscription. It is the right tool for **orchestration regression** (do the
gates fire, is the handoff written, does nothing get posted) — but wrong for
high-volume content iteration:

- A full-skill run costs ~$1.7-2.3 (measured, `evals/PHASE-C-FINDINGS.md`) and ~6 min.
  Iterating dimensions/criteria needs hundreds of runs, not five.
- Most of a full run's spend is orchestration (triage, gates, verification, persist) —
  invariant under a criteria edit, so it is pure noise on the metric we iterate on.
- The skill's mandatory AskUserQuestion gates make headless runs awkward outside the
  SDK driver's auto-answer policy; `cursor-agent` has no equivalent hook.

So: a **two-tier design**.

| Tier | What it measures | Engine | Cost/run | When it runs |
|---|---|---|---|---|
| **T-core** (this dir) | Review content: recall of real bugs, noise rate, per-dimension yield | `cursor-agent -p`, model `cursor-grok-4.5-medium` (non-fast) | cents | every hypothesis, many trials |
| **T-skill** (existing `evals/`) | Orchestration: gates, spawn discipline, handoff shape | Agent-SDK run-harness + `suites/review/*.json` | ~$2/task | before landing a skill-file change; holdout gate |

Plus the always-on mechanical layer: `bash tests/run-all.sh` + `tests/authoring/lint-skills.sh`
on every skill edit.

## Unit under test (T-core)

One T-core trial reproduces what ONE `reviewer-agent` spawn sees in Phase 2
(`skills/review/phase-2-spawns.md` §2.3): the agent body as system-style preamble, the
dimension's criteria file(s), the diff (full changed-file contents inline), project
context, and the §Output Format contract. The driver assembles this prompt directly —
no orchestrator, no gates, no verifier — and runs it read-only.

A **variant** is a named directory that can override any of:

- `dims.json` — which dimensions run and which criteria files each one reads
  (default mirrors the §2.1 grid's always-fire set)
- `criteria/*.md` — replacement criteria bodies
- `preamble.md` — replacement reviewer-agent instructions
- `assembly.json` — context knobs (diff-only vs full-file, caps, extra slots)

The champion variant is a faithful snapshot of the shipped files, so a win over
champion translates 1:1 into a skill edit.

## Benchmark tasks

A task = `{repo, base_sha, head_sha (or diff patch), lang, ground_truth[]}` staged into
a disposable worktree. Two sources:

1. **Real PRs** — mined from `manifestlaw-labs/ManifestOS` closed PRs that carry the
   user's Geniro-generated reviews. Ground truth per PR: findings that were *accepted*
   (addressed by later commits on the PR / acknowledged in threads), plus post-merge
   fix commits touching the reviewed lines (bugs the review missed — recall ceiling).
   Ecological validity; imperfect ground truth.
2. **Planted defects** — clean diffs with injected, exactly-known bugs across the
   taxonomy (null-deref, race, boundary, silent fallback, authz gap, secret, regression,
   perf). Perfect ground truth; controlled recall; cheap to extend.

Ground-truth entry schema:

```json
{
  "id": "gt-3",
  "file": "src/orders/total.ts",
  "lines": [41, 48],
  "class": "null-deref",
  "dimension_hint": "bugs",
  "severity": "HIGH",
  "must_find": true,
  "description": "discount field optional; total() dereferences without guard",
  "acceptance_evidence": "fixed in commit abc123 after review comment"
}
```

`must_find: false` marks debatable/minor ground truth — reported in metrics but
excluded from the primary recall.

**Partition discipline** (same as `evals/suites/*/PARTITION.md`): `tasks/dev/` is
tuned against; `tasks/holdout/` is never read while iterating and gates promotion.

## Scoring

1. **Parse** findings mechanically from the §Output Format blocks (severity, file,
   lines, title, confidence, evidence presence).
2. **Match** each ground-truth entry against the variant's findings:
   mechanical pre-match (same file + line-range overlap) → LLM judge confirms the
   candidate finding describes the same defect (not merely the same lines). Judge runs
   on a FIXED cheap model, blind to which variant produced the findings, with finding
   order shuffled.
3. **Classify the residue** (findings matching no ground truth): judge buckets each as
   `plausible-real` / `noise` / `nitpick`. Residue is never auto-counted as false
   positive — real PRs have incomplete ground truth; `plausible-real` residue at
   CRITICAL/HIGH is surfaced for human/ground-truth promotion.

Per-task metrics:

- `recall_must` — fraction of `must_find` ground truth matched (primary metric)
- `recall_weighted` — severity-weighted (CRITICAL 4 / HIGH 3 / MEDIUM 2 / LOW 1)
- `noise_rate` — `noise + nitpick` findings per task
- `precision_proxy` — matched + plausible-real over total findings
- `tokens_in/out`, `wall_seconds` (from `cursor-agent` JSON usage)

## Statistics and the promotion loop

- The task is the unit of randomization. Compare variant vs champion **paired per
  task** (k trials each, default k=2); decide on the paired sign/bootstrap over tasks —
  reuse `evals/lib/eval-stats.sh` (Wilson + task-clustered seeded bootstrap).
- **A-vs-A first**: champion vs champion must come back a tie; it also measures
  run-to-run variance, which sets the minimum detectable effect.
- Primary gate: `recall_must` up with `noise_rate` not significantly worse — or noise
  down with recall held. A delta inside the CI is a tie.
- Every run appends one JSON line to `runs.jsonl` (variant, refs, per-task metrics,
  tokens, verdict). Promotion additionally requires the T-skill holdout pass and a
  green `tests/run-all.sh`.

Model-transfer caveat: the executor is Grok 4.5, production runs are Claude-tier.
Content-level effects (criteria coverage, dimension partitioning, checklist form)
transfer; model-idiosyncratic prompt tricks may not. Mitigation: the final holdout
confirmation of a landed change runs once on the T-skill harness (Claude executor).

## Cost model

Measured overheads: ~15K input tokens fixed per `cursor-agent -p` call; a review call
adds diff + criteria + preamble (~10-30K) and emits ~1-4K. At Cursor's non-fast Grok
4.5 pricing this lands at cents per dimension-call; a full 6-dimension pass over a
12-task dev set at k=2 stays in the low dollars. Budget guard: the driver records
tokens per run; abort a sweep if a run exceeds 5× the expected token envelope.

## Layout

```
evals/cursor-review/
├── DESIGN.md            this file
├── driver.sh            run one variant over a task set → runs/<run-id>/
├── stage-task.sh        materialize a task's worktree + diff
├── score.sh             parse + judge + per-task metrics
├── compare.sh           paired variant-vs-champion verdict (eval-stats.sh)
├── variants/
│   ├── champion/        faithful snapshot of shipped files (regenerated by sync-champion.sh)
│   └── <hypothesis>/    overrides
├── tasks/
│   ├── dev/<task-id>/task.json + ground_truth.json [+ patch files]
│   └── holdout/...
├── judge/               judge prompt templates (match + residue)
└── runs.jsonl           append-only run ledger (committed)
```

Run workspaces under `evals/cursor-review/runs/` are gitignored like `evals/runs/`.
