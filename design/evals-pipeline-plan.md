# Evals pipeline — implementation plan

Status: PLAN (not yet implemented). Owner: maintainer. Branch: `claude/harness-model-evals-LO2Hm`.
**Implement on a branch rebased on `main`** — this branch forked from v2.22.0, and some referenced infra
(e.g. `lib/score-formula.sh`, added in the v2.22.1 audit, and the current skills) landed on `main`
afterward; rebase first or those reuse targets won't be present.

Purpose: compare two versions of this plugin's skills/agents/prompts and answer, per run —
**"is the new version better, and by how much, across quality + speed + cost?"** — run **locally,
by hand**, while accumulating every run into a committed history that a post-hoc trend reader uses for
context (the blind judge never sees it).

Design philosophy (v4): **reuse skill-creator's eval _schemas, grader/comparator agent prompts, and
viewer_ where they genuinely fit; build the rest on the Claude Agent SDK and geniro's own infra.**
skill-creator was built to grade _self-contained, single-agent_ skills (e.g. xlsx editing) producing one
static artifact. geniro's `/plan` and `/review` are _multi-agent, human-gated orchestrators_. The honest
split (§4): reuse the JSON contracts + judge prompts + eval-viewer; build (a) an Agent-SDK run harness
that drives a human-gated multi-agent skill and auto-answers its gates, (b) cost derivation, (c) the
committed cross-run ledger, (d) a per-skill, task-clustered significance gate. v2's "reuse as-is, build
only the ledger" did not survive contact with the source; v3 corrected the skill-creator facts; **v4
aligns the methodology with current eval best practice and with geniro's actual skills/infra** (see the
§0 changelogs).

---

## 0. Changelogs (why this was rewritten)

### v2 → v3 (ground-truth against skill-creator source)

A skeptical audit checked every v2 claim against the real skill-creator source (`anthropics/skills`
@ `da20c925`, mirrored byte-for-byte in `anthropics/claude-plugins-official`). Roughly half were wrong:

- **No `total_cost_usd` in `timing.json`** — cost is derived downstream (§3, §9).
- **`benchmark.json` reports `± stddev`, not `± stderr`** (§3, §8).
- **Suite schema is `expectations[]` (free-text, LLM-graded), not typed `assertions[]`** (§3, §11).
- **The comparator is blind but NOT position-swapped** — position control is net-new (§3, §10).
- **No reference recall/precision and no _absolute_ pointwise rubric are emitted** — the only recall/
  precision in source is the trigger-classifier's; the 1–5 rubric is _relative_, comparator-only (§3, §10).
- **There is no `executor` component** — it's a role played by an inline-spawned subagent (§3, §4).
- **`≥5 trials` is not a built-in for quality evals** — the orchestrator must drive repeated runs (§3, §8).
- **The blocking problem v2 never named:** the skills under test hard-gate on `AskUserQuestion` (§5).

### v3 → v4 (best-practice + geniro-fit review)

A recheck against current public eval guidance (Anthropic "Demystifying evals for AI agents"; the
LLM-as-judge reporting/ bias literature; the stochastic-evals literature) and against geniro's _actual_
current skills/infra produced these corrections:

- **Phase 0 is no longer an "open platform question" — the mechanism is CONFIRMED.** The Claude Agent
  SDK `canUseTool` callback intercepts **both** tool-permission requests **and** `AskUserQuestion`; you
  auto-answer by returning a non-empty `{answers}` mapping. Phase 0 is a bounded engineering task, not a
  gamble — with one documented sharp edge: `AskUserQuestion` is **not available inside subagents** spawned
  via the Agent tool, so every gate must fire from the main/orchestrator session (§5). Source:
  `https://code.claude.com/docs/en/agent-sdk/user-input`.
- **Statistics fixed (3 real bugs).** (1) The CI estimator must be **Wilson/Clopper-Pearson for single
  proportions and bootstrap for winrate/ratios/pass^k** — a t-interval is the wrong family for a bounded
  Bernoulli quantity (v3's `ci_method: t-interval` was wrong). (2) **Task is the unit of randomization** —
  between-task variance dominates; trials only shrink within-task noise, so the CI must cluster at the
  task level and the suite must grow toward **20–50 distinct tasks**, not re-run 1–2 fixtures. (3) Testing
  4–7 metrics with one `significant` boolean inflates the false-positive rate (~23% at 5 metrics) — gate
  on **one primary metric** per skill (FDR if conjunctive); "adaptive stopping" must be **anytime-valid**
  or it is peeking (§8, §9, §14).
- **Judge: same-family bias does not cleanly cancel.** It is a perplexity/familiarity effect favoring the
  more-Claude-canonical side, and is _correlated_ with the house-style shifts a skill edit causes. Add a
  **different-family judge** as a cross-check on contested/small-Δ runs, and **calibrate the judge against
  human labels** (Cohen's κ ≥ ~0.6) before trusting it (§10, §14, §15).
- **Held-out test partition** added — the candidate is iterated against the suite then promoted on it,
  which overfits; reserve held-out tasks and gate on them (§11, §15).
- **Deterministic-grader-first + volume:** prefer code matchers for programmatically-checkable
  expectations; more cheap automated-graded tasks beat few expensive LLM-graded ones (§9, §10).
- **End-to-end pipeline eval promoted onto the roadmap** (Anthropic's primary unit is the agent's
  end-to-end outcome; per-skill artifact grading is the fast inner loop, not the whole story) (§15, §16).
- **`analyze-thread` reclassified + located:** it is a real repo-local skill at
  `.claude/skills/analyze-thread/` (SKILL.md + `checks-reference.md`) that already implements the exact
  discipline checks — the **recommended trajectory layer for this repo's own eval, ahead of Inspect AI**
  (which cannot answer gates and is a net-new dependency). It is repo-local dev tooling, NOT a shipped
  plugin skill (§13).
- **Reuse geniro infra:** the ledger writer should sit on `lib/atomic-state-write.sh atomic_state_append`
  + `emit-learning.sh`'s dedup/redact pattern; the seam check belongs in `tests/` (auto-discovered by
  `run-all.sh`); the trend math should be single-sourced like `score-formula.sh` (§14, §16).
- **`instructions_digest` confound:** `.geniro/instructions/*` is loaded at Step 0 and re-read at every
  phase boundary (and `code-style.md` is pre-inlined into reviewer-agent prompts), so two runs of the
  _same skill SHA_ differ if those files differ. Record an `instructions_digest` and hold it constant
  across the A/B pair, or a "win" may be an instruction edit (§8, §15).
- **Phase-0 operational risks named:** per-trial `.geniro/state` isolation (vs the SessionStart restore
  hook), an explicit `maxTurns` for the headless top-level run (SDK defaults to 10), and the
  worktree-inside-eval-worktree nesting decision (§5).

---

## 1. Goal

- Maintainer runs the eval **locally, on demand** — no CI, no automation.
- For each version-vs-version run, produce a confidence-gated verdict on **one primary quality metric**
  (cost/speed reported alongside), and append it to a committed ledger that survives across machines.
- Reuse as much of skill-creator's machinery as genuinely fits (its JSON contracts, blind comparator and
  grader prompts, `aggregate_benchmark.py`, `eval-viewer`); build only what geniro's multi-agent,
  human-gated skills require on top, reusing geniro's own `lib/`/`tests/` primitives where they exist.

What this repo contributes that skill-creator does not own:

1. **A run harness (Phase 0)** built on the Claude Agent SDK `canUseTool` driver that runs a geniro skill
   in the main session (so it can fan out its own subagents) and auto-answers its `AskUserQuestion` gates.
   skill-creator cannot do this; its "executor" is a single-shot subagent that produces static files (§5).
2. **Test suites** of realistic tasks (target 20–50 distinct tasks per skill, sourced from real
   regression history), in skill-creator's real `evals.json` shape, with a held-out partition (§11).
3. A **cross-run history ledger** (`evals/HISTORY.md` + `evals/history.jsonl`), built on geniro's
   `atomic_state_append`. The blind comparator never sees it; the post-hoc `/geniro:eval` trend reader does.
4. A **cost-derivation + task-clustered significance ingest** that turns skill-creator's `benchmark.json`
   + `timing.json` (tokens, durations — no dollars) into dollar figures and ledger records, computes the
   right per-metric CI (Wilson/bootstrap, clustered at task), and gates on one primary metric.

## 2. Non-goals

- **No CI.** The maintainer runs this by hand.
- **No re-implementation of what skill-creator provides well.** Reuse its `grader.md` / `comparator.md` /
  `analyzer.md` prompts, `aggregate_benchmark.py`, `eval-viewer/`, and JSON schemas; extend the schemas
  (cost, CI, pass^k, model + instruction digests) rather than forking the grader.
- **Not a replacement for `tests/run-all.sh`** — the deterministic unit-test floor for `lib/` and
  `hooks/`. This sits one layer up. The judge-free **seam check lives _in_ `tests/`** (§14), not a new tree.
- **No SaaS platform** (Braintrust / LangSmith). Inspect AI / promptfoo are optional trajectory layers (§13).
- **Not a buy-the-harness play.** No eval framework can answer geniro's gates (that lives in the SDK
  `canUseTool` layer); the driver must be built regardless (§13).

## 3. Ground truth about skill-creator (verified against source)

Canonical source: `anthropics/skills` @ commit `da20c925`, directory `skills/skill-creator/`
(`SKILL.md`, `scripts/`, `agents/`, `eval-viewer/`, `references/schemas.md`). Also bundled
byte-identically in `anthropics/claude-plugins-official` at `plugins/skill-creator/skills/skill-creator/`.
**Pin a specific commit SHA.** Beware `plugins/plugin-dev/.../skill-creator-original.md` — a stripped
methodology doc with **no eval engine**; do not clone it by mistake.

| What v2 assumed | What the source actually shows | Consequence |
|---|---|---|
| Reuse the **executor** | There is **no executor agent/script**. `agents/` holds exactly `grader.md`, `comparator.md`, `analyzer.md`. The "executor" is an _inline-spawned Task subagent_; `timing.json` arrives via the task notification and is hand-transcribed. | The thing that _runs the skill_ is the part we build (§5). |
| Two callable "Eval mode" / "Improve mode" | No first-class modes. One conversational create→test→improve loop ("Running and evaluating test cases", "Improving the skill", "Advanced: Blind comparison", "Description Optimization"). "Improve/Benchmark mode" appear only in `references/schemas.md`. | Describe a human-in-the-loop loop, not switchable modes. |
| `timing.json {total_tokens, duration_ms}` **and** `total_cost_usd` | `timing.json`: `total_tokens`, `duration_ms`, `total_duration_seconds`, `executor_start/end`, `executor_duration_seconds`, `grader_start/end`, `grader_duration_seconds`. **No cost field.** | Cost is **derived** from tokens × a committed price map (§9). |
| `benchmark.json` `pass_rate ± stderr` | `aggregate_benchmark.py` emits per-config `pass_rate`/`time_seconds`/`tokens` each `{mean, stddev, min, max}` + a delta block; `runs_per_configuration` default **3**. Dispersion is **stddev**. | Ingest computes the right CI per metric (§8) — **not** a naïve `stddev/√n` t-interval (§14, decision 4). |
| Eval suite `{prompt, expected_output, assertions[]}` with a type enum | Real `evals.json`: `{ skill_name, evals: [{ id, prompt, expected_output (prose _description_), files[], expectations[] }] }`. `expectations[]` are **free-text NL statements** graded **PASS/FAIL, no partial credit** by an LLM grader. | Use the real schema (§11). Deterministic matchers are net-new and preferred where possible (§10). |
| Blind, **position-swapped** comparator | `comparator.md` is **blind** but **not** position-swapped (fixed A-then-B order; the only `random.*` is `run_loop.py`'s trigger train/test split). | Blinding reused; **position-swap is net-new** (§10). |
| Native **pointwise rubric** + **reference recall/precision** | Grader emits per-expectation booleans + `summary.pass_rate`, **no numeric rubric**. A 1–5 rubric + `overall_score` exists **only in the A/B comparator** and is **relative**. **No reference recall/precision** — the only `precision/recall` is `run_loop.py`'s _trigger classifier_. | The "3-signal quality model" is **our design**; reference recall/precision is net-new (§10–11). |
| `≥5 trials` is configurable | `--runs-per-query` (default 3) lives in the _trigger_ optimizer, not the quality path. The quality path runs **once per config**; `aggregate_benchmark.py` averages `run-N/` dirs **if they exist**, but nothing produces them. | Driving ≥N quality trials is **our** orchestration (§5, §8). |
| Self-contained-skill grader fits geniro | The executor is a single-shot subagent producing static **files**; the grader scores those files. geniro `/review`/`/implement` (a) **fan out their own subagents**, (b) call **MCP/GitHub**, (c) **gate on `AskUserQuestion`**, (d) write `.geniro/state/` outside `outputs_dir`. | **Conceptual mismatch — the core reason we build an SDK driver (§5).** |

**Bottom line:** genuinely reusable — the skill-snapshot baseline, the blind comparator + grader + analyzer
prompts, `aggregate_benchmark.py`, `eval-viewer`, and the JSON contracts. Net-new — the SDK run harness,
cost in dollars, position-swap, reference recall/precision, the committed ledger, and the per-skill gate.

## 4. Architecture — what we reuse vs what we build

```
  REUSE (upstream skill-creator, pinned)         BUILD (this repo + geniro infra)
  ───────────────────────────────────────        ──────────────────────────────────────
  agents/grader.md       (PASS/FAIL judge)   ┐    run-harness/   Agent-SDK canUseTool driver:
  agents/comparator.md   (blind A/B rubric)  ├──► (Phase 0)      run skill in main session, fan out,
  agents/analyzer.md     (intra-run variance)│                   auto-answer AUQ gates, capture outputs
  scripts/aggregate_benchmark.py             ├──► suites/<skill>/evals.json  (real schema, 20-50 tasks,
  eval-viewer/generate_review.py + .html     │                                held-out partition)
  references/schemas.md  (JSON contracts)    ┘    ingest.sh      tokens→$, Wilson/bootstrap CI clustered
                                                                 at task, primary-metric gate
  REUSE (geniro infra, this repo)                 history.jsonl  append-only ledger (via atomic_state_append)
  ───────────────────────────────────────        HISTORY.md     human table, one row/run
  lib/atomic-state-write.sh atomic_state_append   price-map.json per-model $/MTok (committed)
  lib/emit-learning.sh   (dedup/redact pattern)   position-swap  run each pair both orders, avg
  lib/score-formula.sh   (single-source math)     recall/precision  vs a real planted-bug git fixture
  tests/run-all.sh       (auto-discovers tests/)  tests/seam/*.sh   /plan↔/review↔/implement contract (judge-free)
  .claude/skills/analyze-thread (trajectory)      /geniro:eval   companion skill (trend reader)
```

The reuse is **prompts + scripts + schemas + geniro lib primitives**, not a turnkey CLI. skill-creator's
quality path is an agent-orchestrated choreography (spawn runs → grade → aggregate → view); we borrow the
pieces and supply the SDK driver. **No eval framework (Inspect AI, promptfoo) can answer the gates** — that
capability lives in the Agent SDK `canUseTool` callback underneath any harness (§13), so the driver is
unavoidable regardless of buy-vs-build.

## 5. Phase 0 (blocking) — driving a human-gated, multi-agent skill under eval

The gate on the whole effort. The skills we eval **cannot run unattended as-is**: `/plan` is hard-gated
("binding for Phases 0–8", releases only on the Phase 8 "Approve" AUQ, ~6–7 AUQ calls/run); `/review`
ends in a mandatory **Always-WAIT** Phase 6 gate (its GitHub PENDING-review POST is itself AUQ-gated).
A ≥N-trial _unattended_ run × ~6–7 gates each is impossible without a driver; attended, it's ~30+
hand-clicks per eval.

**The mechanism is confirmed** (this reverses v3's "open platform question" hedge). Per the Claude Agent
SDK docs (`https://code.claude.com/docs/en/agent-sdk/user-input`): a `canUseTool` callback intercepts
**both** tool-permission requests **and** the `AskUserQuestion` tool; to auto-answer, return
`{behavior: "allow", updatedInput: {questions, answers: {"<question text>": "<chosen label>"}}}`. This is
a non-empty injected answer — exactly what geniro's gate contracts require (they re-ask only on an _empty_
answer; they do not forbid a real injected choice). So Phase 0 is a **bounded engineering task**, with one
documented sharp edge and several geniro-specific operational risks.

**Resolution options (pick (A); (B)/(C) are fallbacks):**

- **(A) SDK `canUseTool` driver (recommended, mechanism confirmed).** A headless driver (`claude -p` /
  Agent SDK) runs the skill in the **main session context** — necessary so the skill can **fan out** its
  own subagents — and registers a `canUseTool` callback that auto-answers each `AskUserQuestion` with the
  documented default per a recorded **auto-answer policy** (e.g. `approve-default-v1`). (promptfoo wraps the
  same SDK callback via `ask_user_question: first_option` if you prefer its runner.) In Python the callback
  requires streaming mode + a `PreToolUse` keep-alive hook (per the SDK docs).
- **(B) Pre-gate-only eval.** Evaluate the deterministic phases up to the first gate (e.g. `/plan` through
  spec drafting before Phase 8; `/review` through persisted findings before the action gate). Cheaper,
  measures less.
- **(C) Fully manual.** Run each trial in chat and answer gates by hand — interim until (A) lands.

**The one confirmed sharp edge:** `AskUserQuestion` is **not available inside subagents spawned via the
Agent tool** (SDK docs, "Limitations"). geniro skills must therefore surface every gate from the
**orchestrator/main session**. `medium-gate.md` already does; **Phase 0 must audit that `/plan`, `/review`,
and every `_shared/*-gate.md` fire from the main session, not a spawned subagent** — any gate that fires
inside a subagent is unanswerable and blocks the run.

**Operational risks Phase 0 must close (geniro-specific):**

- **Per-trial state isolation.** All skills write `.geniro/state/` via `atomic_state_write`, and a live
  `hooks/session-start-restore.sh` (matcher `compact|resume|startup`) restores in-progress runs. Each
  trial must run with an **isolated `.geniro/state` root** (per-trial temp dir or worktree) so trial N
  doesn't leak into N+1 and SessionStart doesn't resurrect a half-finished prior trial.
- **`maxTurns`.** The Agent SDK defaults to **10 turns**; a long `/review` truncates mid-fan-out and the
  grader scores a partial artifact as a regression. Set an explicit top-level turn budget.
- **Worktree nesting.** The eval already runs the candidate in a git worktree (§6 step 2); `/review` /
  `/implement` may themselves call `EnterWorktree`. Decide: pass a no-worktree modifier or tolerate nesting.
- **`gh` auth** for the real git/PR fixture (§10–11).
- **Question quality is a graded signal, not a default-away.** The auto-answer masks a skill that asks
  _worse_ questions — record `auq_autoanswer_policy` and treat question quality as its own signal, not a
  silent default.

**Deliverable of Phase 0:** one trial of `/plan` completing end-to-end with no human (canUseTool answering
its gates), outputs landing where the grader expects, in an isolated state root. Until that exists, the
≥N-trial methodology in §8 is unreachable, so no ledger/suite work proceeds past a single manual smoke run.

## 6. Workflow per run (local, by hand)

1. **Set context — discipline matters.** Read `evals/HISTORY.md` only to recall the current champion ref.
   Do **not** read the trend before the blind verdict is fixed — the anchoring bias we design out of the
   machine judge re-enters through the operator otherwise (§15). Read the trend in step 6.
2. **Snapshot baseline.** `git worktree` at the **committed** champion ref (or `cp -r <skill>
   skill-snapshot/` _before_ editing). The candidate must also be a committed SHA — ingest rejects a dirty
   tree (prevents fictional provenance + p-hacking, §8). Pin `instructions_digest` identical across the
   A/B pair (§8) so a "win" is a skill edit, not an instruction edit.
3. **Run the harness (Phase 0)** version-vs-version over the suite, at the **per-skill trial count** (§8 —
   computed, not a flat 5). Each trial drives the skill (auto-answering gates), captures
   artifact(s)+transcript+tokens+duration at a **pinned executor temperature**, and runs `grader.md`
   against the suite's `expectations[]`. Quality (§10): blind **position-swapped** comparator (release
   gate, the **primary metric**); relative pointwise rubric (anchor); reference recall/precision where a
   gold set exists. `aggregate_benchmark.py` summarises into `benchmark.json`.
4. **Ingest.** `evals/ingest.sh <benchmark.json> --candidate <sha> --baseline <sha> --notes "…"` (built on
   `atomic_state_append`). It derives **cost** (tokens × `price-map.json`), computes the **right CI per
   metric** (Wilson/Clopper-Pearson for proportions; bootstrap for winrate/ratios/pass^k), **clustered at
   the task level**, applies the **primary-metric significance gate** (delta inside the CI → tie),
   increments `attempt_no`, and appends one `history.jsonl` record + one `HISTORY.md` row.
5. **Read a sample of transcripts/grades** before trusting the verdict (Anthropic's Step 6: "Read the
   transcripts!"). Especially needed given a same-family, length-confound-prone judge (§15). The
   eval-viewer surfaces these; ensure `evals/runs/` survives locally for the promoting run.
6. **Read the trend (post-hoc).** `/geniro:eval` (NOT skill-creator's analyzer) reads `history.jsonl`
   after the blind verdict is fixed and prints the trend.
7. **Promote (manual).** On a _significant_ win on the **primary metric** (clears the clustered CI;
   corroborated where `length_confounded`; cross-family judge agrees on contested/small-Δ runs — §10),
   bump the champion ref. Never automatic, never on a tie, never on a secondary metric alone.

## 7. (reserved)

## 8. The committed history ledger + the derived fields

skill-creator has **no cumulative, committed, cross-run ledger** — the maintainer's central requirement,
so it is a core build item, together with the fields skill-creator does not emit (cost, the right CI,
pass^k, model + instruction identities). **Build the writer on `lib/atomic-state-write.sh
atomic_state_append`** (torn-write-safe append-only JSONL) and model the record on `emit-learning.sh`'s
producer contract (`ts` auto-inject, `redact-secrets` on the free-text `notes`, dedup key) rather than a
hand-rolled `>>`.

**`evals/history.jsonl`** — append-only, one record per run:
```json
{
  "run_id": "2026-06-06T10:30:00Z",
  "skill": "review",
  "baseline_ref": "a1b2c3d",
  "candidate_ref": "e4f5g6h",
  "tasks": 24,
  "trials_per_task": 5,
  "executor_model": "claude-opus-4-8",
  "judge_model": "claude-opus-4-8",
  "cross_family_judge": "gemini-2.5-pro",
  "models_resolved_at": "2026-06-06",
  "executor_temperature": 1.0,
  "judge_temperature": 0.0,
  "auq_autoanswer_policy": "approve-default-v1",
  "instructions_digest": "sha256:1f3c…",
  "holdout_partition": true,

  "primary_metric": "quality_winrate_vs_baseline",
  "quality_winrate_vs_baseline": 0.78,
  "quality_ci": [0.69, 0.86], "ci_method": "bootstrap-task-clustered@95%",
  "comparator_verdict": "candidate better",
  "position_swapped": true,
  "length_confounded": false,
  "cross_family_agree": true,
  "judge_human_kappa": 0.71, "kappa_measured_at": "2026-06-01",

  "pointwise_score": 4.2, "pointwise_delta": 0.3,

  "recall_at1": 0.90, "recall_passk": 0.80, "recall_passk_ci": [0.66, 0.91],
  "recall_passk_ci_method": "bootstrap-task-clustered@95%",
  "precision": 0.85, "precision_ci_method": "wilson@95%",

  "mean_cost_usd": 0.42, "cost_delta": -0.05, "cost_derived_from": "tokens*price-map@v1",
  "mean_tokens": 51000, "tokens_delta": -3000,
  "mean_wall_seconds": 31.0, "time_delta": 1.4,

  "pass_rate": 0.95, "pass_rate_ci": [0.83, 0.99], "pass_rate_ci_method": "wilson@95%",

  "significant_on_primary": true, "secondary_metrics_reported_not_gated": true,
  "attempt_no": 1,
  "is_champion": true,
  "notes": "primary winrate clears clustered CI; cross-family agrees; cost down; lengths comparable"
}
```

Key points (and what changed from v3):

- **Right CI per metric (v3 bug fix).** Proportions (`pass_rate`, `recall`, `precision`) use
  **Wilson/Clopper-Pearson**; `winrate`, ratios, and `pass^k` use a **bootstrap** (resample the per-trial
  0/1 grades). v3's `t-interval@df=n-1` was the wrong family for a bounded Bernoulli quantity and is
  removed. Record `ci_method` per metric.
- **Task is the unit of randomization (v3 bug fix).** The CI is computed by **clustering/aggregating to a
  per-task mean and bootstrapping across tasks** — not over pooled trials — because between-task variance
  dominates. `tasks` and `trials_per_task` are both recorded; raise `tasks` toward 20–50 (§11), keep
  `trials_per_task` just high enough that within-task noise ≪ between-task variance.
- **One primary metric gates promotion.** `significant_on_primary` is the gate; cost/time/pass-rate are
  reported, **not gated** (avoids the ~23% family-wise false-positive rate of testing 4–7 metrics at once).
- **`recall_passk` is the reliability gate** for reliability-contract skills, reported with a
  **task-clustered bootstrap CI** (a near-1 reliability target estimated from few trials is itself
  high-variance).
- **`judge_human_kappa`** records agreement between the Opus comparator and human spot-grades (§14); the
  CI gate detects variance, not systematic miscalibration or server-side judge drift.
- **`cross_family_judge` / `cross_family_agree`** — a different-family judge cross-checks contested runs
  (same-family self-preference does not cleanly cancel, §10/§15).
- **`instructions_digest`** (sha256 of the loaded `global.md` + `<skill>.md` + `code-style.md` +
  `review-extra/*`, via `lib/hash.sh`) — held constant across the A/B pair; otherwise a "win" may be an
  instruction edit, not a skill edit (§15).
- **`executor_temperature` pinned > 0** (so pass^k measures real variation) and **recorded**; judge low/0.

**`evals/HISTORY.md`** — human table, one row per run:

| Date | Skill | Cand | vs | Primary (winrate, CI) | Recall^k | κ | Cost Δ | Time Δ | Tasks×Trials | Sig | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-06-06 | review | e4f5g6h | a1b2c3d | 0.78 [.69,.86] | 0.80 | 0.71 | −12% | +1.4s | 24×5 | yes | ✅ better |

## 9. Metrics — source vs derived; primary vs secondary

Raw point estimates come from skill-creator; cost, CIs, pass^k, and deltas are **derived by ingest**.
**Exactly one metric per skill gates promotion**; the rest are reported for context.

| Metric | Role | Provenance |
|---|---|---|
| Pairwise winrate (position-swapped) | **PRIMARY gate** (subjective skills) | comparator (blind) + our swap wrapper; CI = task-clustered bootstrap |
| Recall^k | **PRIMARY gate** (reliability skills, e.g. /review) | built planted-bug gold set; CI = task-clustered bootstrap |
| Pointwise rubric | secondary anchor (relative) | comparator's 1–5/overall-1–10 — relative, not absolute (§10) |
| Precision | secondary | built; Wilson CI |
| Cost (USD) | secondary | **derived** `mean_tokens × price-map.json`; skill-creator emits no cost |
| Tokens / Wall-time | secondary | `timing.json` `total_tokens` / `duration_ms` |
| Pass-rate (expectations) | secondary (output shape) | `benchmark.json`; Wilson CI derived by ingest |

**Grade deterministically first.** Where an expectation is programmatically checkable (spec.md has the
11-section schema; severity tags present; no finding outside the diff range), prefer a **code matcher** over
an LLM expectation. Reserve the Opus comparator for genuinely subjective dimensions — Anthropic's grader
ordering is code → human → LLM, and "volume of automated grading > few hand/LLM-graded" (which also helps
the 20–50 task target, §11). A delta inside the CI is a tie, not a win. Trajectory/tool-call metrics are
optional (§13).

## 10. Quality signals — native vs built (be precise)

- **Pairwise winrate (primary gate for subjective skills).** Blind comparator reused; we **add
  position-swap** (each pair judged in both orders, averaged as a _paired_ observation — a free variance
  reduction). **Length/format confound:** position-swap fixes _position_ bias, not _length/verbosity_ bias.
  When candidate mean output length/format differs materially, ingest stamps `length_confounded: true`,
  the comparator prompt applies a length-penalty / per-token-normalized view, and the pairwise verdict
  alone **may not** clear the gate — the pointwise anchor and reference recall must corroborate.
- **Same-family self-preference does NOT cleanly cancel.** It is a perplexity/familiarity effect favoring
  the more-Claude-canonical side, and is _correlated_ with the house-style shift a skill edit causes — so
  it is a live confound on the winrate gate, not a wash. Mitigation: a **different-family judge**
  (`cross_family_judge`, e.g. Gemini/GPT) as a tie-breaker on contested/small-Δ runs; if it and Opus
  disagree on direction, record the run low-confidence. Opus stays primary for capability; cross-family is
  the bias cross-check.
- **Calibrate the judge against human labels.** Before trusting the comparator as the gate, the maintainer
  blind-grades ~30–50 A/B pairs; ingest records **Cohen's κ** (`judge_human_kappa`) and trust is gated on
  κ ≥ ~0.6, re-measured on the cadence the model IDs are re-resolved. The planted-bug check validates the
  recall _suite_, not the subjective _judge_.
- **Pointwise rubric (relative anchor).** Comparator-internal and _relative_; catches "both degraded" only
  loosely. Not an absolute cross-version score.
- **Reference recall/precision (built).** For `/review`, a **real git fixture** (branch/diff/PR ref — not
  static files, since `/review` resolves targets as branch/diff/PR and runs `gh pr diff/view`) with a
  reviewed **manifest of findable issues**. Recall = **found-AND-survived-Phase-4.2 verification** (the
  verifier can legitimately suppress a true positive — measured behaviour). **Recall^k** (caught in all k
  trials) is the reliability gate. Precision is scored against **planted ∪ human-adjudicated-true
  incidental** (the judge is least reliable adjudicating incidental findings it couldn't itself find — so
  that adjudication is **mandatory human**, not optional).
- **Expectation pass-rate (native).** Binary PASS/FAIL per `expectations[]` item, aggregated. Objective
  output shape; secondary.

## 11. Suites — real schema, real fixtures, task count, held-out, integration order

`evals/suites/<skill>/evals.json` in skill-creator's **actual** schema:

```json
{
  "skill_name": "review",
  "evals": [
    {
      "id": 1,
      "prompt": "Review the diff on branch fixture/planted-bugs-01",
      "expected_output": "Findings that include the N planted issues, severity-tagged",
      "files": ["fixture/planted-bugs-01"],
      "expectations": [
        "The output flags the SQL injection in auth.ts",
        "The output does not invent issues outside the diff"
      ]
    }
  ]
}
```

`expectations[]` are free-text statements graded PASS/FAIL by the grader. No typed `assertions[]` enum;
deterministic matchers for output shape are a small net-new check we own (and prefer where possible, §10).

**Task count & sourcing (Anthropic's 20–50 floor).** Distinct **tasks** (the diversity axis) are NOT the
same as trials-per-task (the variance axis). Target **20–50 distinct tasks per skill, drawn from real
failures** — mine the plugin's own regression history (`MEMORY.md`, the git log of fix commits, past CI
incidents) rather than only synthetic planted bugs. v3 conflated the two and spent its statistical rigor
re-running 1–2 fixtures (tight CIs on a non-representative sample). The 1–2 task case is a **Phase 0/C
bootstrap** only.

**Held-out partition.** The maintainer iterates the skill against the suite, then promotes on it — which
overfits the skill to its own eval (the failure skill-creator's own 60/40 train/test split prevents).
Reserve a **held-out fraction the candidate is never tuned against** and gate promotion on the held-out
partition. This closes the p-hacking that `attempt_no` alone does not.

**Integration order (inverted from v2 — de-risk plumbing first):**

1. **`/plan` first** for the end-to-end pipeline signal — a clean single `spec.md`. Prove Phase 0, capture,
   grade, ingest, first `HISTORY.md` row.
2. **`/review`** for judge **calibration** (tiny planted-bug fixture, reference-scored, no comparator
   needed) → then full A/B at 20–50 tasks. Its real output is a **mutated multi-section handoff state file
   + chat + gated GitHub POST** — parse the handoff `## Findings`, normalise the variable dimension set,
   **suppress the GitHub post**.
3. **`/implement`** — last, but **the real prize**: churn analysis shows `/implement` (and `/review`) are
   the highest-blast-radius skills (they ship code), so frame it as the goal once plumbing is proven, not
   an afterthought.

**Seam check lives in `tests/`.** Author it as `tests/seam/plan-review-implement-contract.sh` so the
existing `tests/run-all.sh` auto-discovers it (no new runner): assert `/plan`'s `spec.md` frontmatter
satisfies `/review`'s `workflow_refs[]` parser **when present** (it is _optional_ — present only on
tracker-linked specs; mirror `/review`'s own "treat as absent" acceptance, so it never false-fails on an
inline-task spec), and that `/review`'s handoff carries the `open_questions[]` / `step0_status` sentinels
`/implement` consumes. Judge-free, no trials, no cost — it catches exactly the cross-skill seam regressions
per-skill grading is blind to.

## 12. Run UX

- **Grading/comparison engine = skill-creator's prompts + scripts**, invoked by the harness (or by the
  maintainer in the §5 option-C interim).
- **Driving the skill = our Agent-SDK `canUseTool` run harness (Phase 0).**
- **Bookkeeping + trend = `/geniro:eval` companion skill** (decided — §14). Idiomatic
  (`name: geniro:eval`, `context: main`, `model: inherit`, `allowed-tools: [Read, Bash, AskUserQuestion]`,
  Reporter posture — never a fixer). Prints the prior trend post-hoc, reminds the maintainer of the exact
  invocation + suite path, calls `ingest.sh`. NOT a delegator to skill-creator and NOT its analyzer.

## 13. Trajectory layer + build-vs-buy (resolved)

skill-creator grades outputs, not trajectories. The discipline/path signal (did `/review` miss a
parallel-spawn? did a spawn carry `model=` against inherit? did a phase get skipped?):

- **Recommended: the repo-local `analyze-thread` skill** at `.claude/skills/analyze-thread/` (SKILL.md +
  `checks-reference.md`). It already implements the exact checks this plan wants — A1 missed parallel-spawn,
  A4 wrong-tier `model=`, D1 phase-skip, E1 constraint-disobeyed — across a 32-check taxonomy with a
  mechanical+judge two-pass over the same JSONL transcripts the harness captures, and emits structured
  findings `ingest.sh` can read as `discipline_pass_rate` / `steps`. It is **repo-local dev tooling, not a
  shipped plugin skill** — available because the eval runs _on this repo_. Prefer it over a net-new
  dependency.
- **Inspect AI (UK AISI) only if `analyze-thread`'s taxonomy proves insufficient.** Note: Inspect's Agent
  Bridge proxies the model API and its approvers gate _tool calls only_ — **it cannot answer
  `AskUserQuestion` gates** ("approvers cannot synthesize answers to prompts"). So Inspect is a trajectory
  _scoring_ layer, never the harness core; it would still sit above the SDK `canUseTool` driver.

**Build-vs-buy:** the gate-answering capability is a property of the **Claude Agent SDK** (`canUseTool`),
harness-independent — no eval framework provides it. Therefore: **build** the driver on the SDK; **reuse**
skill-creator's grader/comparator prompts; keep Inspect AI / promptfoo as **optional** trajectory layers.
(promptfoo wraps the same SDK callback — `ask_user_question: first_option` — so it is an alternative
_driver_, not a way to avoid the SDK.) Trajectory grading is additive, out of the initial build.

## 14. Decisions (resolved)

1. **Bookkeeping + trend:** the **`/geniro:eval`** companion skill (decided). Post-hoc trend reader; not a
   delegator, not the analyzer.
2. **Judge model:** **Opus** for capability — a deliberate _upgrade_ over geniro's model-tiering floor
   (`model-tiering.md` puts a PASS/FAIL rubric judge at haiku/sonnet); document the Opus hardcode **inline
   at the spawn site** per that file's carve-out convention or the next audit flags it. **Add a
   different-family judge** (`cross_family_judge`) as a self-preference cross-check on contested/small-Δ
   runs. Executor-internal sub-agents on **Sonnet** is available ONLY on the headless/orchestratorless path
   (`model: inherit` is _fallback, not "the harness may choose"_); in the manual interim (option C) they
   inherit the operator's Opus tier, so decision 10's cost is a **floor**.
3. **skill-creator acquisition:** **git submodule, pinned to a SHA** — freezes prompts/scripts, **not** the
   eval results (the server-side Opus judge + Claude executor drift). Result stability comes from the CI
   gate (decision 4) + recorded `executor_model`/`judge_model`/`models_resolved_at` + `judge_human_kappa`
   (decision 12).
4. **Trials, tasks & significance (rewritten in v4):**
   - **Task is the unit of randomization.** Compute the CI by clustering to per-task means and
     bootstrapping across tasks; raise distinct **tasks toward 20–50** (§11). Trials-per-task only as high
     as needed for within-task noise ≪ between-task variance.
   - **Per-metric CI estimator:** Wilson/Clopper-Pearson for single proportions; bootstrap for
     winrate/ratios/pass^k; `stddev/√n` only for genuinely continuous per-task-aggregated metrics
     (tokens, wall-seconds). **Not** a t-interval on a proportion (v3 bug).
   - **One primary metric gates promotion** (position-swapped winrate for subjective skills; pass^k for
     reliability skills); cost/time/pass-rate are reported, not gated (or apply Benjamini-Hochberg FDR if
     a conjunctive gate is genuinely wanted) — avoids the ~23% family-wise false-positive rate.
   - **Empirical null A-vs-A calibration** of the trial/task count — run the same version twice **across
     tasks** (not just re-running trials) and size so the clustered CI half-width < the smallest delta
     worth detecting; expect `/review` to need more than `/plan`.
5. **History-blind** comparator (anchoring); operator reads the trend only after the blind verdict (§6).
6. **Quality = three signals (our design):** position-swapped pairwise (primary) + relative pointwise
   anchor + built reference recall/precision. Label them as our additions, not skill-creator features.
7. **Integration order:** **`/plan` first** (plumbing on a clean artifact) → `/review` (calibration, then
   A/B) → `/implement` last but the highest-blast-radius prize (inverts v2's "/review first").
8. **Trajectory layer:** **`analyze-thread` (repo-local) preferred** over Inspect AI (inverts v3) — it
   already implements the checks; Inspect cannot answer gates and is a net-new dependency (§13).
9. **What lands in git:** the ledger (`HISTORY.md` + `history.jsonl`), `price-map.json`, suites + held-out
   manifest, `tests/seam/*.sh`, and the harness. Raw per-trial transcripts under `evals/runs/` are
   `.gitignore`d (but survive locally for the promoting run, §6 step 5).
10. **Cost is first-class.** One `/review` run fans out to ~20–25 Opus-tier agents (per the `/review`
    fan-out in `skills/review/SKILL.md` — confirm against the current definition; standard mode, `--deep`
    ~triples it); at the per-skill task×trial count × 2 versions × position-swap, a `/review` suite run is
    plausibly **$80–150 and 1–3 hours** (order-of-magnitude — _measure in Phase C_). Mitigations: Sonnet for
    executor-internal agents + Opus only for the judge; **anytime-valid** sequential stopping (alpha-spending
    / group-sequential / Bayesian posterior) **not** fixed-horizon peeking; a hard per-run dollar ceiling.
11. **Held-out test partition** (decision, v4): reserve tasks the candidate is never tuned against; gate
    promotion on held-out, mirroring skill-creator's own 60/40 split (§11, §15).
12. **Judge-human calibration** (decision, v4): κ ≥ ~0.6 against ~30–50 human-graded pairs before trusting
    the comparator gate; re-measure on the model-resolution cadence; record in the ledger (§10).
13. **`instructions_digest` held constant across the A/B pair** (decision, v4): `.geniro/instructions/*` is
    a hidden eval variable; record its digest and hold it identical, or a "win" may be an instruction edit
    (§8, §15).
14. **Build the driver on the Agent SDK `canUseTool` callback** (decision, v4): gate-answering is an
    SDK-layer capability, harness-independent; Inspect/promptfoo are optional layers, not a way to avoid
    building the driver (§5, §13).
15. **Reuse geniro `lib/` + `tests/` primitives** (decision, v4): ledger on `atomic_state_append` +
    `emit-learning` pattern; single-source the trend/significance math like `score-formula.sh`; seam check
    in `tests/seam/` under `run-all.sh`. Don't re-derive what exists (§4, §8, §11, §16).

## 15. Known limitations (accepted)

- **Per-skill, not end-to-end.** Artifact quality in isolation misses cross-skill seam regressions.
  _Mitigated_ by the in-scope deterministic seam check (§11) AND by a roadmapped end-to-end task (§16
  Phase E) — Anthropic's primary unit is the agent's end-to-end outcome, so this is on the roadmap, not
  "future work indefinitely."
- **Same-family judge.** Self-preference does NOT cleanly cancel (perplexity/familiarity, asymmetric,
  correlated with the house-style shift a skill edit causes). _Mitigated_ by the cross-family cross-check
  (decision 2/§10) + human-κ calibration (decision 12), not by a "roughly symmetric" assumption.
- **Judge competence ceiling.** On `/review` the judge may be unable to verify a subtle bug it couldn't
  itself find — so incidental-finding adjudication is **mandatory human** (§10), and recall is scored
  against the planted manifest (known ground truth) where the judge is reliable.
- **Between-task variance dominates.** A CI from many trials on few tasks is deceptively narrow and won't
  generalize; hence the 20–50-task / task-clustered-CI requirement (§11, decision 4).
- **Overfitting to the eval suite** — the maintainer tunes against the suite then promotes on it.
  _Mitigated_ by the held-out partition (decision 11).
- **Instruction-injection hidden variable.** `.geniro/instructions/*` (loaded at Step 0, re-read at every
  phase boundary; `code-style.md` pre-inlined into reviewer prompts) means two runs of the same SHA can
  differ. _Mitigated_ by `instructions_digest` held constant across the A/B pair (decision 13).
- **Model drift defeats prompt pinning** — the CI gate + recorded model IDs + κ cadence are the defence,
  not the submodule pin (decision 3/12).
- **Gold-fixture rot.** Re-audit when a `/review` dimension changes; score precision against
  planted ∪ human-adjudicated-true; pin the findable-issue manifest beside the fixture.
- **Cost/time is real** (decision 10).
- **Residual human anchoring** — operator reads the trend only after the blind verdict (§6).
- **Ledger is a deliberate exception** to "don't commit eval results" — a small, low-churn scorecard.

## 16. Phased build plan

- **Phase 0 — Agent-SDK gate driver (BLOCKING, §5).** Wire a `canUseTool` responder that auto-answers
  `AskUserQuestion`; **audit that every `/plan` + `/review` gate fires from the main session, not a
  subagent**; per-trial `.geniro/state` isolation; explicit `maxTurns`; worktree-nesting decision; `gh`
  auth. Done when one `/plan` trial completes end-to-end with no human. Nothing below proceeds past a
  manual smoke run until this lands.
- **Phase A — ledger + price map + suites + seam check (reuse infra).** `evals/` tree; `.gitignore`
  `evals/runs/`; `price-map.json`; `evals/suites/plan/evals.json` (real schema) + a held-out partition;
  **`tests/seam/plan-review-implement-contract.sh`** (under `run-all.sh`); seed `history.jsonl` +
  `HISTORY.md`. Ledger writer built on `atomic_state_append` + the `emit-learning` pattern.
- **Phase B — ingest helper.** Cost from tokens × price map; **per-metric CIs (Wilson/bootstrap)
  clustered at task**; primary-metric gate; reject dirty trees; `instructions_digest` + `attempt_no`;
  single-source the math like `score-formula.sh`. README with the exact harness invocation + auto-answer
  policy.
- **Phase C — first real run on `/plan` + measure cost/time.** Pin skill-creator as a submodule; run
  `/plan` version-vs-version through the driver; grade; ingest; eyeball the first row; **record actual $ +
  wall-time** to validate decision 10; **read the transcripts** (§6 step 5).
- **Phase D — `/review` calibration → A/B at scale.** Planted-bug git fixture + findings extractor +
  position-swap wrapper; **judge-human κ calibration** (decision 12); grow to **20–50 tasks from regression
  history** + held-out; **cross-family judge** cross-check; build `/geniro:eval`.
- **Phase E — end-to-end + optional trajectory.** Add ONE end-to-end pipeline task (feature → `/plan` →
  `/implement` → diff passes planted acceptance tests) graded on final outcome; wire `analyze-thread`
  (repo-local) for the discipline/`steps` signal; escalate to Inspect AI only if its taxonomy is
  insufficient.

## 17. Prior art references

- `anthropics/skills` (canonical) + `anthropics/claude-plugins-official` (mirror) — skill-creator: reused
  grader/comparator/analyzer prompts, `aggregate_benchmark.py`, `eval-viewer`, JSON schemas (a
  create→test→improve loop with a blind comparator + `skill-snapshot/` baseline — _not_ switchable modes,
  _not_ a turnkey CLI, _no_ executor agent, cost, position-swap, or reference recall/precision).
- **Claude Agent SDK — "Handle approvals and user input"** (`code.claude.com/docs/en/agent-sdk/user-input`):
  the `canUseTool` callback answers BOTH tool-permission requests AND `AskUserQuestion` (return non-empty
  `{answers}`); `AskUserQuestion` is unavailable inside Agent-tool subagents — the basis for §5/decision 14.
- Anthropic engineering — "Demystifying evals for AI agents" + Claude Docs "Build evaluations": grade
  outcomes not path; **20–50 tasks from real failures**; held-out test set; grader ordering code → human →
  LLM + "volume over quality"; calibrate LLM judges against human experts; **read the transcripts**;
  **pass@k vs pass^k**.
- LLM-as-judge: position-swap ("Judging the Judges: Position Bias…"); verbosity/self-preference
  (Self-Preference / perplexity-familiarity ≈ −38%…+90%); **"How to Correctly Report LLM-as-a-Judge
  Evaluations"** (Wilson/Clopper-Pearson/bootstrap CIs; cluster SE at the task unit; Bonferroni/FDR for
  many comparisons) — the basis for §8/§10/decision 4.
- Stochastic-eval / variance literature ("On Randomness in Agentic Evals"; "Quantifying Variance in
  Evaluation Benchmarks"; law of total variance): between-task variance dominates; bootstrap CIs;
  anytime-valid sequential testing vs fixed-horizon peeking — the basis for decision 4/10.
- Inspect AI (UK AISI) approval/agent-bridge docs (approvers gate tool calls, "cannot synthesize answers
  to prompts") + promptfoo Claude-Agent-SDK provider (`ask_user_question: first_option`) — the basis for
  the build-vs-buy call (§13).
