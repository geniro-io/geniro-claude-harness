# Evals pipeline — implementation plan

Status: PLAN (not yet implemented). Owner: maintainer. Branch: `claude/harness-model-evals-LO2Hm`.

Purpose: compare two versions of this plugin's skills/agents/prompts and answer, per run —
**"is the new version better, and by how much, across quality + speed + cost?"** — run **locally,
by hand**, while accumulating every run into a committed history that each new run reads back as context.

Design philosophy (v2): **reuse Anthropic's skill-creator as the eval engine as-is; build only the
piece it lacks** (a committed cross-run history). Do not clone or re-implement skill-creator's
executor / grader / comparator / analyzer.

---

## 1. Goal

- Maintainer runs the eval **locally, on demand** — no CI, no automation, human-in-the-loop.
- The heavy lifting (run task → capture timing/tokens → grade → blind quality comparison → aggregate)
  is done by **skill-creator**, reused as-is.
- This repo contributes only three committed things skill-creator does not own:
  1. **Test suites** describing realistic tasks for this plugin's skills (data).
  2. A **cross-run history ledger** (`evals/HISTORY.md` + `evals/history.jsonl`) that persists in the
     repo and is fed back as context on the next run, so verdicts are trend-aware.
  3. A tiny **ingest helper** that distills skill-creator's `benchmark.json` into that ledger.

## 2. Non-goals

- **No CI.** Explicitly out of scope. The maintainer runs this by hand. (Earlier draft proposed an
  optional `workflow_dispatch` workflow — dropped.)
- **No clone of skill-creator's logic.** No vendored copies of its `comparator.md` / `grader.md` /
  `analyzer.md` / aggregate script. Point at the upstream skill; copy nothing.
- **Not a replacement for `tests/run-all.sh`** — that stays as the deterministic unit-test floor for
  `lib/` and `hooks/`. This sits one layer up: behavioral / agentic quality.
- **No SaaS platform** (Braintrust / LangSmith).

## 3. Constraints discovered about the reuse target (skill-creator)

| Fact | Consequence for this plan |
|---|---|
| Not a clean marketplace install — clone `anthropics/claude-plugins-official`, reference the skill path | Setup step: clone upstream once; document the path. "Reuse as-is" = point at upstream, not vendor. |
| Modes are conversational, no flags — "I have a draft, evaluate it" jumps to eval/iterate | The maintainer drives skill-creator in chat; we don't script it. |
| Improve mode already does version A vs B: `skill-snapshot/` baseline vs new, captures `timing.json {total_tokens, duration_ms}`, optional blind comparator | Quality + speed + cost A/B is **already covered** — no need to rebuild it. |
| Skill-to-skill delegation NOT supported — human-in-the-loop only | We can't build a `/geniro:eval` skill that programmatically calls skill-creator. Our addition is **bookkeeping + history context**, run alongside skill-creator, not a delegator. |
| Built for self-contained skills (e.g. xlsx editing) | Best fit for our **artifact-producing** skills. `/plan` (→ single `spec.md`) fits cleanly; `/review` (→ report) fits; `/implement` (multi-file diff) is awkward — instrument it last. |

## 4. Architecture — engine reused, gap filled

```
        ┌─────────────────────────────────────────────┐
        │  skill-creator  (UPSTREAM, cloned, reused)    │   ← does the work
        │  executor · grader · comparator · analyzer    │
        │  → emits timing.json + benchmark.json         │
        └───────────────┬───────────────────────────────┘
                        │ benchmark.json (per run)
                        ▼
        ┌─────────────────────────────────────────────┐
        │  THIS REPO  evals/  (committed)               │   ← the only thing we build
        │  suites/<skill>/evals.json   (test data)      │
        │  ingest.sh  benchmark.json → ledger           │
        │  history.jsonl  (append-only, fed back)       │
        │  HISTORY.md     (human table, one row/run)    │
        └─────────────────────────────────────────────┘
```

**Workflow per run (local, by hand):**

1. **Set context.** Read `evals/HISTORY.md` to recall the trend and the current champion ref.
2. **Snapshot baseline.** `git worktree` (or skill-creator's `skill-snapshot/`) at the champion ref;
   working tree = candidate.
3. **Run skill-creator** conversationally on a chosen suite: point it at this plugin's skill, hand it
   `evals/suites/<skill>/evals.json` as the test cases, ask for the version-vs-version improve run with
   the blind comparator. It produces `benchmark.json` (pass_rate ± stderr, mean tokens, mean time,
   deltas) + the comparator verdict.
4. **Ingest.** Run `evals/ingest.sh <benchmark.json> --candidate <ref> --baseline <ref> --notes "..."`.
   It appends one record to `history.jsonl` and one row to `HISTORY.md`, computing deltas vs the prior
   champion.
5. **Read the trend.** The ingest helper (or the maintainer, in chat) reads the prior `history.jsonl`
   and prints the trend-aware verdict ("quality up 3 runs; cost +30% cumulative").
6. **Promote (manual).** On a clear win, bump the champion ref in `history.jsonl`/`baseline` — never
   automatic.

## 5. What we deliberately do NOT build (anti-clone guardrail)

- ❌ executor — skill-creator's.
- ❌ grader (assertion checking) — skill-creator's.
- ❌ comparator (blind pairwise quality judge) — skill-creator's.
- ❌ analyzer (non-discriminating-assertion / variance / tradeoff detection) — skill-creator's.
- ❌ aggregate_benchmark, eval-viewer — skill-creator's.

If a need arises that one of these "almost" covers, prefer filing the gap into our ledger or a thin
post-processing step over re-implementing the agent.

## 6. The committed history (the one real gap we fill)

skill-creator keeps per-iteration workspaces; it has **no cumulative, committed, cross-run ledger**.
That is exactly the maintainer's central requirement, so it is the bulk of what we build.

**`evals/history.jsonl`** — append-only, one record per run, machine-readable, fed back as context:
```json
{
  "run_id": "2026-06-06T10:30:00Z",
  "skill": "plan",
  "baseline_ref": "a1b2c3d",
  "candidate_ref": "e4f5g6h",
  "trials": 3,
  "quality_winrate_vs_baseline": 0.78,
  "comparator_verdict": "candidate better",
  "mean_cost_usd": 0.42, "cost_delta": -0.05,
  "mean_tokens": 51000, "tokens_delta": -3000,
  "mean_wall_seconds": 31.0, "time_delta": 1.4,
  "pass_rate": 0.95, "pass_rate_delta": 0.10,
  "is_champion": true,
  "notes": "tighter clarify phase; fewer tokens"
}
```

**`evals/HISTORY.md`** — human table, one row per run:

| Date | Skill | Candidate | vs | Quality | Cost Δ | Tokens Δ | Time Δ | Pass-rate | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| 2026-06-06 | plan | e4f5g6h | a1b2c3d | 0.78 | −12% | −6% | +1.4s | 0.95 | ✅ better |

Because both files are committed and pushed, the trend survives across machines/sessions and is the
context every new run reads. The ingest helper computes deltas against the prior champion record.

## 7. Metrics — all sourced from skill-creator, none re-derived

| Metric | Source |
|---|---|
| Quality | skill-creator blind comparator winrate + verdict |
| Cost (USD) | skill-creator `timing.json` / `benchmark.json` (`total_cost_usd` / mean) |
| Tokens | skill-creator `timing.json` `total_tokens` |
| Wall-time | skill-creator `timing.json` `duration_ms` |
| Pass-rate (assertions) | skill-creator `benchmark.json` `pass_rate ± stderr` |

"Steps / tool-calls" and pipeline-discipline checks are NOT in skill-creator. They are **optional**
(§10) — left out of the core to honor reuse-first.

## 8. Run UX — "as a skill"

Given skill-creator is conversational and non-delegatable, the honest UX is:

- **Engine = skill-creator, invoked conversationally** by the maintainer ("evaluate `/plan` against
  the previous version using `evals/suites/plan/evals.json`"). This is the skill you "run."
- **Bookkeeping = `evals/ingest.sh`**, a one-line helper run after skill-creator finishes.

A thin companion skill in *this* plugin is **optional** and, if added, must NOT pretend to delegate to
skill-creator. It would only: (a) print the prior `HISTORY.md` trend as opening context, (b) remind the
maintainer of the exact skill-creator invocation + suite path, (c) call `ingest.sh` afterward. Decide
in §11 whether the helper script alone is enough or a companion skill earns its keep.

## 9. Suites — what to feed skill-creator (start with `/plan`)

`evals/suites/<skill>/evals.json` in skill-creator's own schema
(`{prompt, expected_output, assertions[]}`, assertion `type: exact_match|contains|regex|numeric|custom`).

Start order (revised under reuse-first — best fit to skill-creator's output-grading model):
1. **`/plan`** — produces one clean artifact (`spec.md`); easiest to grade + compare. First.
2. **`/review`** — produces a report artifact; a planted-bug fixture lets the comparator/assertions
   score recall/precision. Second.
3. **`/implement`** — multi-file diff; awkward for skill-creator's output model. Last, if at all.

For subjective dimensions write NO assertions — let the blind comparator judge qualitatively (per
skill-creator's own guidance). Assertions only for objective output shape.

## 10. Optional, this-plugin-only extras (clearly outside the reuse core)

These are the only things skill-creator genuinely can't do. Add ONLY if the basic quality/cost/time
signal proves insufficient — not part of the initial build:

- **Pipeline-discipline checks** via the existing `analyze-thread` skill: parse a run transcript for
  safety-invariant violations (`/refactor` pushed, spawn carried `model=`, missed parallel-spawn,
  `spec.md` missing the 11-section schema). Run as a separate pass; record a `discipline_pass_rate`
  column in the ledger.
- **Step count** (tool-calls) from the transcript via `analyze-thread`, if "fewer steps" becomes a
  metric the maintainer wants tracked.

Keeping these optional and additive (a post-pass over the transcript, not a re-implementation of
skill-creator) preserves the reuse-first stance.

## 11. Decisions (resolved)

1. **Form of the bookkeeping layer:** thin companion skill **`/geniro:eval`** in this plugin. It does
   NOT delegate to skill-creator (unsupported). It prints the prior `HISTORY.md` trend as opening
   context, reminds the maintainer of the exact skill-creator invocation + suite path, and calls
   `ingest.sh` afterward. All execution/grading/comparison stays in skill-creator.
2. **Comparator model:** **Opus** — maximize judge reliability on subtle quality differences;
   runs are infrequent and local, so cost is acceptable.
3. **skill-creator acquisition:** **git submodule, pinned**. The upstream commit is pinned in this repo
   so eval results are reproducible — an upstream change to skill-creator can't silently shift the
   judge's behavior between runs. Bumping the submodule is an explicit, reviewable commit.

## 12. Phased build plan

- **Phase A — ledger + suites.** Create `evals/` tree, `.gitignore` `evals/runs/`, write
  `evals/suites/plan/evals.json` (3–5 `/plan` tasks), seed empty `history.jsonl` + `HISTORY.md`.
- **Phase B — ingest helper.** `evals/ingest.sh`: read a skill-creator `benchmark.json`, compute deltas
  vs prior champion, append to both ledger files. README with the exact skill-creator invocation.
- **Phase C — first real run.** Clone skill-creator upstream, run it on the `/plan` suite version-vs-version,
  ingest, eyeball the first `HISTORY.md` row.
- **Phase D — expand.** Add the `/review` suite (+ planted-bug fixture). Optionally the companion skill.
- **Phase E — optional extras.** Wire `analyze-thread` discipline pass + step count if wanted (§10).

## 13. Prior art references

- anthropics/skills + anthropics/claude-plugins-official — skill-creator (the reused engine:
  Eval/Improve modes, blind comparator, timing/benchmark formats).
- TribeAI/claude-evals — ideas only (severity tiers, judge variance reduction, per-case budget).
- Anthropic engineering — "Demystifying evals for AI agents" (grade outcomes not path, read transcripts,
  start at 20–50 tasks, pass@k vs pass^k).
