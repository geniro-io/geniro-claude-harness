# Evals pipeline — implementation plan

Status: PLAN (not yet implemented). Owner: maintainer. Branch: `claude/harness-model-evals-LO2Hm`.

Purpose: compare two versions of this plugin's skills/agents/prompts and answer, per run —
**"is the new version better, and by how much, across quality + speed + cost?"** — run **locally,
by hand**, while accumulating every run into a committed history that the analyzer reads back for
trend context (the blind judge does not).

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
     repo. The blind comparator never sees it (avoids anchoring bias); only the post-hoc **analyzer**
     reads it, to produce trend-aware verdicts.
  3. A tiny **ingest helper** that distills skill-creator's `benchmark.json` into that ledger and
     applies the significance gate (delta below the noise band → recorded as a tie, not a win).

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

1. **Set context.** Read `evals/HISTORY.md` to recall the trend and the current champion ref. (Human
   context only — this is NOT fed to the comparator.)
2. **Snapshot baseline.** `git worktree` (or skill-creator's `skill-snapshot/`) at the champion ref;
   working tree = candidate.
3. **Run skill-creator** conversationally on a chosen suite: point it at this plugin's skill, hand it
   `evals/suites/<skill>/evals.json`, ask for the version-vs-version improve run at **≥5 trials per
   task**. Quality is judged three ways: the **blind comparator** (position-swapped, history-blind) as
   the release gate, a **pointwise rubric score** as an absolute anchor (catches "both versions
   degraded"), and **reference-based** recall/precision where a gold fixture exists (e.g. planted bugs
   for `/review`). It produces `benchmark.json` (pass_rate ± stderr, mean tokens, mean time, deltas).
4. **Ingest.** Run `evals/ingest.sh <benchmark.json> --candidate <ref> --baseline <ref> --notes "..."`.
   It computes deltas vs the prior champion, applies the **significance gate** (a quality/cost/time
   delta inside the confidence interval is recorded as a tie, not a win), and appends one record to
   `history.jsonl` + one row to `HISTORY.md`.
5. **Read the trend (analyzer, post-hoc).** The analyzer reads the prior `history.jsonl` AFTER the
   blind verdict is fixed, and prints the trend-aware summary ("quality up 3 runs; cost +30%
   cumulative"). Separating this from step 3 keeps the judge un-anchored.
6. **Promote (manual).** On a significant win, bump the champion ref in `history.jsonl`/`baseline` —
   never automatic, never on a tie.

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
  "skill": "review",
  "baseline_ref": "a1b2c3d",
  "candidate_ref": "e4f5g6h",
  "trials": 5,
  "quality_winrate_vs_baseline": 0.78,
  "comparator_verdict": "candidate better",
  "pointwise_score": 4.2, "pointwise_delta": 0.3,
  "recall": 0.90, "precision": 0.85,
  "mean_cost_usd": 0.42, "cost_delta": -0.05,
  "mean_tokens": 51000, "tokens_delta": -3000,
  "mean_wall_seconds": 31.0, "time_delta": 1.4,
  "pass_rate": 0.95, "pass_rate_delta": 0.10,
  "significant": true, "noise_band_pp": 8,
  "is_champion": true,
  "notes": "higher recall; cost down; delta clears noise band"
}
```

`significant: false` (delta inside the noise band) records the run as a **tie** — the candidate is not
promoted. `noise_band_pp` is the confidence-interval half-width that gated the call.

**`evals/HISTORY.md`** — human table, one row per run:

| Date | Skill | Candidate | vs | Quality | Pointwise | Cost Δ | Time Δ | Significant | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| 2026-06-06 | review | e4f5g6h | a1b2c3d | 0.78 | 4.2 (+0.3) | −12% | +1.4s | yes | ✅ better |

Because both files are committed and pushed, the trend survives across machines/sessions. Only the
**analyzer** reads them (post-hoc); the comparator stays blind. The ingest helper computes deltas
against the prior champion record and stamps `significant`.

## 7. Metrics — all sourced from skill-creator, none re-derived

Quality is measured three complementary ways (production pipelines use all three: pairwise for the
release gate, pointwise for an absolute anchor, reference-based where gold data exists):

| Metric | Role | Source |
|---|---|---|
| Pairwise winrate | **release gate** — "is candidate better than baseline?" | skill-creator blind comparator (position-swapped, history-blind) |
| Pointwise rubric score | **absolute anchor** — catches "both versions degraded" | skill-creator grader against a rubric |
| Recall / precision | **reference-based** — hard number where gold exists | planted-bug fixture (e.g. `/review`) |
| Cost (USD) | efficiency | skill-creator `timing.json` `total_cost_usd` |
| Tokens | efficiency | skill-creator `timing.json` `total_tokens` |
| Wall-time | efficiency | skill-creator `timing.json` `duration_ms` |
| Pass-rate (assertions) | output-shape | skill-creator `benchmark.json` `pass_rate ± stderr` |

Every metric is reported over **≥5 trials** with a confidence interval; a delta inside the interval is
a tie, not a win (single-run agent metrics vary several percentage points even at temperature 0).

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

## 9. Suites — what to feed skill-creator (start with `/review`)

`evals/suites/<skill>/evals.json` in skill-creator's own schema
(`{prompt, expected_output, assertions[]}`, assertion `type: exact_match|contains|regex|numeric|custom`).

Start order (prioritizes signal reliability over integration ease):
1. **`/review`** — a **planted-bug** fixture yields a hard reference-based number (recall/precision).
   This is the most trustworthy first signal AND it lets us **validate the judge's calibration** before
   we trust it on subjective verdicts. First.
2. **`/plan`** — one clean artifact (`spec.md`), but its quality is the most subjective (highest judge
   variance), so it relies most on the blind comparator + pointwise anchor. Second.
3. **`/implement`** — multi-file diff; awkward for skill-creator's output model. Last, if at all.

For subjective dimensions write NO assertions — let the blind comparator + pointwise rubric judge (per
skill-creator's own guidance). Assertions only for objective output shape.

## 10. Optional, this-plugin-only extras (clearly outside the reuse core)

These are the only things skill-creator genuinely can't do (it grades outputs, not trajectories). Add
ONLY if the basic quality/cost/time signal proves insufficient — not part of the initial build:

- **Trajectory / tool-call grading — preferred path: Inspect AI** (UK AISI). It is purpose-built for
  multi-turn agentic evals and can run Claude Code as an external agent, so it grades the *path* (tool
  calls, turns, discipline), which skill-creator and a transcript-parser only approximate. Use it as a
  separate optional layer, not a replacement for the skill-creator artifact-quality core.
- **Lightweight fallback: the existing `analyze-thread` skill** — parse a run transcript for
  safety-invariant violations (`/refactor` pushed, spawn carried `model=`, missed parallel-spawn,
  `spec.md` missing the 11-section schema) and step count. Zero new dependency, but weaker than a real
  trace framework. Record a `discipline_pass_rate` / `steps` column in the ledger.

Keeping these optional and additive preserves the reuse-first stance.

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
4. **Trials & significance:** **≥5 trials per task**, report a confidence interval, and gate promotion
   on it — a delta inside the noise band is a tie. Single-run agent metrics vary several percentage
   points even at temperature 0, so 3 trials would let noise masquerade as improvement.
5. **Comparator is history-blind:** the blind judge never sees prior results (anchoring bias). The
   ledger is read only by the post-hoc analyzer for trend reporting.
6. **Quality = three signals:** pairwise (release gate) + pointwise rubric (absolute anchor) +
   reference-based recall/precision where gold exists. Pure pairwise can't see "both versions degraded".
7. **First skill:** **`/review`** with a planted-bug fixture — hardest, most reliable signal first;
   also validates judge calibration before trusting subjective verdicts. `/plan` second.
8. **Optional trace layer:** **Inspect AI** preferred over `analyze-thread` for trajectory/tool-call
   grading, if the artifact-quality signal proves insufficient.
9. **What lands in git:** the distilled ledger (`HISTORY.md` + `history.jsonl`) is committed and pushed —
   this satisfies the original "history in the repo" requirement and is a curated scorecard, not raw
   output. Raw per-trial transcripts under `evals/runs/` are `.gitignore`d (the best-practice
   "don't commit generated results" rule applies to those).

## Known limitations (accepted, not yet addressed)

- **Per-skill, not end-to-end.** This measures each skill's artifact quality in isolation. It will NOT
  catch regressions in cross-skill seams — handoffs, `open_questions[]` gating, the
  `/plan`→`/implement`→`/review` loop. A pipeline-level eval is future work, out of scope here.
- **Judge is same-family.** Opus judging Claude-produced artifacts carries self-preference bias. In
  pairwise A-vs-B where BOTH sides are Claude the bias is roughly symmetric and cancels; but do not
  read the pointwise anchor as an absolute cross-model quality score, and revisit if the executor model
  ever changes family.
- **Ledger is a deliberate exception** to "don't commit eval results" — justified because it is a small,
  low-churn, semantic scorecard (like a `CHANGELOG`), not raw run data.

## 12. Phased build plan

- **Phase A — ledger + suites.** Create `evals/` tree, `.gitignore` `evals/runs/` (ledger stays
  tracked), write `evals/suites/review/evals.json` + a planted-bug fixture (3–5 `/review` tasks), seed
  empty `history.jsonl` + `HISTORY.md`.
- **Phase B — ingest helper.** `evals/ingest.sh`: read a skill-creator `benchmark.json`, compute deltas
  vs prior champion, apply the significance gate, append to both ledger files. README with the exact
  skill-creator invocation (≥5 trials, position-swap).
- **Phase C — first real run + judge calibration.** Pin skill-creator as a submodule, run it on the
  `/review` planted-bug suite version-vs-version, confirm recall/precision matches the known bug set
  (calibration check), ingest, eyeball the first `HISTORY.md` row.
- **Phase D — expand.** Add the `/plan` suite. Build the `/geniro:eval` companion skill (trend print +
  invocation reminder + ingest call; no delegation).
- **Phase E — optional trace layer.** Wire Inspect AI (or `analyze-thread` fallback) for discipline /
  step-count if the core signal proves insufficient (§10).

## 13. Prior art references

- anthropics/skills + anthropics/claude-plugins-official — skill-creator (the reused engine:
  Eval/Improve modes, blind comparator, timing/benchmark formats).
- TribeAI/claude-evals — ideas only (severity tiers, judge variance reduction, per-case budget).
- Anthropic engineering — "Demystifying evals for AI agents" (grade outcomes not path, read transcripts,
  start at 20–50 tasks, pass@k vs pass^k).
- Inspect AI (UK AISI) — preferred optional trace/tool-call eval layer (§10).
- "On Randomness in Agentic Evals" / "Stochasticity in Agentic Evaluations" (arXiv) — multi-trial +
  confidence-interval gating; single-run deltas <~8–10pp are within noise (§7, decision 4).
- "Judging the Judges: Position Bias in Pairwise LLM-as-Judge" (arXiv) + LLM-judge bias surveys —
  position-swap, history-blind judging, verbosity/self-preference caveats (decisions 5–6, limitations).
