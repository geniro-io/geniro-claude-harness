# Evals pipeline — implementation plan

Status: PLAN (not yet implemented). Owner: maintainer. Branch: `claude/harness-model-evals-LO2Hm`.

Purpose: compare two versions of this plugin's skills/agents/prompts and answer, per run —
**"is the new version better, and by how much, across quality + speed + cost?"** — run **locally,
by hand**, while accumulating every run into a committed history that a post-hoc trend reader uses for
context (the blind judge never sees it).

Design philosophy (v3): **reuse skill-creator's eval _schemas, grader/comparator agent prompts, and
viewer_ where they genuinely fit, and _build_ the parts geniro's skills actually need that
skill-creator does not provide.** skill-creator is real and useful, but it was built to grade
_self-contained, single-agent_ skills (e.g. xlsx editing) producing one static artifact. geniro's
`/plan` and `/review` are _multi-agent, human-gated orchestrators_. The honest split (§4) is: reuse the
JSON contracts + judge prompts + eval-viewer; build (a) an unattended run harness that can drive a
human-gated multi-agent skill, (b) cost derivation, (c) the committed cross-run ledger, (d) a per-skill
significance gate. "Reuse as-is, build only the ledger" (v2) did not survive contact with the source —
see §3 and the v2→v3 changelog at the end.

---

## 0. v2→v3 changelog (why this was rewritten)

A skeptical audit ground-truthed every v2 claim against the real skill-creator source
(`anthropics/skills` @ `da20c925`, mirrored byte-for-byte in `anthropics/claude-plugins-official`).
Roughly half the specific claims were wrong, and the conceptual fit was mis-stated. Corrections folded
into this v3:

- **No `total_cost_usd` in `timing.json`** — cost is derived downstream (§3, §9).
- **`benchmark.json` reports `± stddev`, not `± stderr`** — ingest computes stderr/CI (§3, §8).
- **Eval suite schema is `expectations[]` (free-text, LLM-graded), not `assertions[]` with a type
  enum** (§3, §11).
- **The comparator is blind but NOT position-swapped** — position-bias control is net-new (§3, §10).
- **No reference-based recall/precision and no _absolute_ pointwise rubric are emitted** — the only
  recall/precision in source is the trigger-classifier's; the 1–5 rubric is _relative_, inside the A/B
  comparator only (§3, §10).
- **There is no `executor` component** — the "executor" is a role played by an inline-spawned subagent
  (§3, §4).
- **`≥5 trials` is not a built-in for quality evals** — only the trigger optimizer has `--runs-per-query`
  (default 3); the quality path runs once per config and the orchestrator must drive repeated runs (§3,
  §8).
- **The blocking problem v2 never named:** the skills under test hard-gate on `AskUserQuestion`, so a
  ≥5-trial _unattended_ run is impossible without a gate harness. This is now **Phase 0** (§5).
- Contradictions resolved: cost source, the "analyzer reads our ledger" mis-assignment, the
  reproducibility claim, and the "build only the ledger" framing (§8, §14).

---

## 1. Goal

- Maintainer runs the eval **locally, on demand** — no CI, no automation.
- For each version-vs-version run, produce a confidence-gated verdict across **quality + speed + cost**,
  and append it to a committed ledger that survives across machines and sessions.
- Reuse as much of skill-creator's machinery as genuinely fits (its JSON contracts, its blind comparator
  and grader prompts, its `aggregate_benchmark.py`, its `eval-viewer`); build only what geniro's
  multi-agent, human-gated skills require on top.

What this repo contributes that skill-creator does not own:

1. **A run harness (Phase 0)** that can drive a human-gated, multi-agent geniro skill to completion
   without a human — or, until that exists, an explicit manual-run protocol. skill-creator cannot do
   this; its "executor" is a single-shot subagent that produces static files (§3, §5).
2. **Test suites** describing realistic tasks for this plugin's skills (data, in skill-creator's real
   `evals.json` shape — §11).
3. A **cross-run history ledger** (`evals/HISTORY.md` + `evals/history.jsonl`) that persists in the repo.
   The blind comparator never sees it (avoids anchoring bias); a post-hoc trend reader (the
   `/geniro:eval` companion skill, NOT skill-creator's analyzer) reads it.
4. A **cost-derivation + ingest helper** that turns skill-creator's `benchmark.json` + `timing.json`
   (tokens, durations — no dollars) into per-run dollar figures and ledger records, computes deltas and
   a **per-skill** significance gate (delta inside the run's confidence interval → recorded as a tie).

## 2. Non-goals

- **No CI.** Explicitly out of scope. The maintainer runs this by hand.
- **No re-implementation of the parts skill-creator _does_ provide well.** Reuse its `grader.md` /
  `comparator.md` / `analyzer.md` agent prompts, `aggregate_benchmark.py`, `eval-viewer/`, and JSON
  schemas. We extend the schemas (cost, stderr, pass^k, model IDs) rather than forking the grader.
- **Not a replacement for `tests/run-all.sh`** — that stays as the deterministic unit-test floor for
  `lib/` and `hooks/`. This sits one layer up: behavioral / agentic quality.
- **No SaaS platform** (Braintrust / LangSmith).
- **Not (initially) a full pipeline / cross-skill-seam eval** — but the cheap _deterministic_ seam check
  is promoted out of "future work" (§11, §15).

## 3. Ground truth about skill-creator (verified against source)

Canonical source: `anthropics/skills` @ commit `da20c925`, directory `skills/skill-creator/`
(`SKILL.md`, `scripts/`, `agents/`, `eval-viewer/`, `references/schemas.md`). It is also bundled
byte-identically in `anthropics/claude-plugins-official` at
`plugins/skill-creator/skills/skill-creator/`. **Pin a specific commit SHA.** Beware
`plugins/plugin-dev/skills/skill-development/references/skill-creator-original.md` in
claude-plugins-official — that is a stripped methodology doc with **no eval engine**; do not clone it by
mistake.

| What v2 assumed | What the source actually shows | Consequence |
|---|---|---|
| Reuse the **executor** | There is **no executor agent/script**. `agents/` holds exactly `grader.md`, `comparator.md`, `analyzer.md`. The "executor" is an _inline-spawned Task subagent_ given a freeform prompt (`SKILL.md`: "Execute this task: Skill path… Task… Save outputs to…"); `timing.json` data arrives via the task notification and is hand-transcribed. | The thing that _runs the skill_ is the part we must build for geniro (§5). Only grader/comparator/analyzer are reusable prompts. |
| Two callable "Eval mode" / "Improve mode" | No first-class modes. One conversational workflow with phases: "Running and evaluating test cases", "Improving the skill", "Advanced: Blind comparison", "Description Optimization". "Improve mode"/"Benchmark mode" appear only as labels in `references/schemas.md`. | Don't describe switchable engine modes; describe a create→test→improve loop that is heavily human-in-the-loop. |
| `timing.json {total_tokens, duration_ms}` **and** `total_cost_usd` | `timing.json` fields: `total_tokens`, `duration_ms`, `total_duration_seconds`, `executor_start/end`, `executor_duration_seconds`, `grader_start/end`, `grader_duration_seconds`. **No cost field anywhere** in skill-creator. | Cost is **derived** by our ingest from tokens × a committed per-model price map (§9). |
| `benchmark.json` `pass_rate ± stderr` | `aggregate_benchmark.py` emits per-config `pass_rate`/`time_seconds`/`tokens` each as `{mean, stddev, min, max}` + a delta block; `metadata.runs_per_configuration` default **3**. Dispersion is **stddev**, not stderr. | Ingest computes `stderr = stddev/√n` and the CI half-width itself (§8). |
| Eval suite `{prompt, expected_output, assertions[]}`, type ∈ `{exact_match,contains,regex,numeric,custom}` | Real `evals.json`: `{ skill_name, evals: [{ id, prompt, expected_output (a prose _description_), files[], expectations[] }] }`. `expectations[]` are **free-text NL statements** ("The output includes X") graded by an LLM grader as **PASS/FAIL, no partial credit**. There is no typed-assertion enum. | Use the real schema (§11). Typed/deterministic matchers, if wanted, are net-new. `expected_output` is grader orientation, not a machine reference. |
| Blind, **position-swapped** comparator | `comparator.md` is genuinely **blind** ("you do NOT know which skill produced which"). It is **not** position-swapped: it reads `output_a_path` then `output_b_path` in fixed order; the only `random.*` in the engine is `run_loop.py`'s train/test split for the _trigger_ optimizer. | Blinding is reused; **position-bias control is net-new** — run each pair twice with A/B swapped and average (§10). |
| Native **pointwise rubric** + **reference recall/precision** | The grader emits per-expectation booleans + `summary.pass_rate` and **no numeric rubric**. A 1–5 content/structure rubric + `overall_score` (1–10) exists **only inside the A/B comparator** and is **relative**, not an absolute per-skill score. **No reference-based output recall/precision** exists; the only `precision/recall` in source is `run_loop.py`'s _trigger-classifier_ metrics (did the skill trigger), unrelated to output quality. | The "3-signal quality model" is _our design_ layered on skill-creator's pass-rate + relative rubric. Reference recall/precision is net-new and needs a real machine-comparable gold set (§10, §11). |
| `≥5 trials` is configurable | The only trials knob, `--runs-per-query` (default 3), lives in the _description-triggering_ optimizer (`run_eval.py`/`run_loop.py`) — it measures triggering, not output quality. The quality path spawns **one run per config**; `aggregate_benchmark.py` will average `run-1/ … run-N/` dirs **if they exist**, but nothing produces them. | Driving ≥N quality trials is **our** orchestration: spawn N executor runs per config per task and emit N `timing.json`/`grading.json` sets (§5, §8). |
| Self-contained-skill grader fits geniro | The executor is a single-shot subagent producing static **output files**; the grader scores those files (`transcript_path` + `outputs_dir`). geniro `/review` / `/implement` (a) **fan out their own subagents**, (b) call **MCP tools** (GitHub), (c) **gate on `AskUserQuestion`**, (d) write `.geniro/state/` outside `outputs_dir`. | **Conceptual mismatch — the core risk (§5).** A subagent generally can't host a further subagent fleet, has no human to answer gates, and its state writes aren't captured. The run harness, not skill-creator's executor, must drive geniro skills. |

**Bottom line:** the engine is real and several pieces are genuinely reusable (skill-snapshot baseline,
blind comparator prompt, grader prompt, `aggregate_benchmark.py`, `eval-viewer`, the JSON contracts).
But the _executor_ and the _unattended multi-trial driving of a human-gated multi-agent skill_ are not
provided, and four claimed signals (cost, typed assertions, position-swap, reference recall/precision)
must be built.

## 4. Architecture — what we reuse vs what we build

```
  REUSE (upstream skill-creator, pinned)        BUILD (this repo, evals/)
  ───────────────────────────────────────       ──────────────────────────────────────
  agents/grader.md       (PASS/FAIL judge)  ┐    run-harness/        drive a geniro skill
  agents/comparator.md   (blind A/B rubric) ├──► (Phase 0)           unattended, ≥N trials,
  agents/analyzer.md     (intra-run variance)│                       AUQ auto-answer, MCP,
  scripts/aggregate_benchmark.py            ├──► suites/<skill>/evals.json   (real schema)
  eval-viewer/generate_review.py + .html    │    ingest.sh           tokens→$, stddev→stderr,
  references/schemas.md  (JSON contracts)   ┘                        per-skill significance gate,
                                                 history.jsonl       append-only ledger (fed back)
                                                 HISTORY.md          human table, one row/run
  NOT provided by skill-creator, we build:       price-map.json      per-model $/MTok (committed)
  • the executor (it's an inline subagent role)  position-swap        run each pair twice, avg
  • cost in dollars                              recall/precision     vs a real planted-bug gold set
  • position-bias control                        seam-check.sh        deterministic /plan↔/review↔/implement
  • reference recall/precision                                        contract check (judge-free)
```

The reuse is **prompts + scripts + schemas**, not a turnkey CLI. skill-creator's quality-eval path is an
agent-orchestrated choreography (spawn runs → grade → aggregate → view); only its trigger/description
loop is a scripted binary (`claude -p`). We borrow the choreography's _pieces_ and supply the driver.

## 5. Phase 0 (blocking) — running a human-gated, multi-agent skill under eval

This is the gate on the whole effort. The skills we want to eval **cannot run unattended as-is**:

- `/plan` is hard-gated: its loop is "binding for Phases 0–8" and releases only on the Phase 8
  "Approve" `AskUserQuestion`; `/plan` estimates ~6–7 AUQ calls per run.
- `/review` ends in a mandatory **Always-WAIT** Phase 6 action gate, and its optional GitHub
  PENDING-review POST is itself AUQ-gated.

A ≥N-trial _unattended_ run × ~6–7 gates each is impossible without a harness; attended, it is ~30+
hand-clicks per eval and the "engine does the heavy lifting" framing is false. **And** skill-creator's
own model runs the skill inside a _subagent_, where `AskUserQuestion` can't reach a human and nested
fan-out / MCP / state writes are constrained — so skill-creator's executor cannot drive these skills at
all. Pick one resolution and build it _first_:

- **(A) Non-interactive eval mode + AUQ auto-responder — the Phase 0 research spike (UNVERIFIED).** The
  intended path is a headless driver (`claude -p` / Agent SDK with an explicit `--permission-mode`) that
  runs the skill in the **main session context**. Main-session context is _necessary_ so the skill can
  **fan out** its own subagents (§3/§5) — but it does **not**, by itself, answer gates. Answering gates is
  a _separate, unsolved_ problem: it needs a programmatic `AskUserQuestion` responder hook, and **it is an
  open platform question whether `claude -p` / the Agent SDK exposes one at all.** Worse, geniro's own gate
  contracts (`skills/_shared/medium-gate.md`, `test-first-gate.md`, `root-cause-gate.md`) treat an _empty_
  AUQ answer as a bug to **re-ask — never auto-default** — so the responder must _inject a non-empty
  choice_ (the documented default, e.g. "Approve"/"Proceed") via an SDK callback that may not exist. The
  auto-answer policy is itself a behaviour under test (a skill that asks _worse_ questions is a
  regression). Treat (A) as a spike to prove, not a given; if the hook doesn't exist, the steady state is
  (B) or (C).
- **(B) Pre-gate-only eval.** Evaluate only the deterministic phases up to the first human gate (e.g.
  `/plan` through spec drafting before Phase 8 approve; `/review` through persisted findings before the
  action gate), and stub the gate. Cheaper, but measures less.
- **(C) Fully manual.** The maintainer runs each trial in chat and answers every gate by hand. Honest but
  expensive; ≥N trials becomes dozens of hand-clicks. Use as the interim until (A) exists; drop the
  "engine does the heavy lifting" claim if this is the steady state.

Deliverable of Phase 0: **one trial of one skill completing end-to-end without a human**, its outputs
landing where the grader expects. **The first thing to prove is the open platform question above — can an
`AskUserQuestion` be answered headlessly at all?** If it cannot, (A) is dead and the steady state is
(B)/(C). Until that exists, the ≥N-trial CI methodology in §8 is unreachable, so no ledger/suite work
proceeds past a single manual smoke run.

## 6. Workflow per run (local, by hand)

1. **Set context — discipline matters.** Read `evals/HISTORY.md` only to recall the current champion ref.
   Do **not** read the trend before fixing the blind verdict — the same anchoring bias we design out of
   the machine judge re-enters through the human operator otherwise (§15). Read the trend in step 5.
2. **Snapshot baseline.** `git worktree` at the **committed** champion ref (or skill-creator's
   `cp -r <skill> <workspace>/skill-snapshot/`, taken _before_ editing). The candidate must also be a
   committed SHA — ingest rejects a dirty working tree (§8, prevents fictional provenance and
   multiple-comparisons p-hacking).
3. **Run the harness (Phase 0) on a chosen suite**, version-vs-version, at the **per-skill trial count**
   (§8 — not a hardcoded 5). For each trial it: drives the skill to completion (auto-answering gates per
   policy), captures the output artifact(s) + transcript + token/duration, and runs skill-creator's
   `grader.md` against the suite's `expectations[]`. Quality is judged three ways (§10): the **blind
   comparator** with **position-swap** (run each A/B pair in both orders, average) as the release gate; a
   **pointwise rubric** as an absolute anchor; **reference recall/precision** where a planted-bug gold set
   exists. Then `aggregate_benchmark.py` summarises into `benchmark.json` (`pass_rate ± stddev`, mean
   tokens, mean time, deltas).
4. **Ingest.** `evals/ingest.sh <benchmark.json> --candidate <sha> --baseline <sha> --notes "…"`.
   It derives **cost** (tokens × `price-map.json`, accounting for mixed-tier sub-agent spend), computes
   **stderr/CI** from the run's stddev and trial count, applies the **per-skill significance gate** (a
   delta inside the computed CI → tie, not a win), increments the attempt-count for this
   candidate↔champion pair, and appends one `history.jsonl` record + one `HISTORY.md` row.
5. **Read the trend (post-hoc).** The `/geniro:eval` companion skill (NOT skill-creator's analyzer — that
   one only sees its own per-iteration workspace) reads `history.jsonl` AFTER the blind verdict is fixed
   and prints the trend ("quality up 3 runs; cost +30% cumulative").
6. **Promote (manual).** On a _significant_ win (clears the CI, corroborated where length/format changed —
   §10), bump the champion ref. Never automatic, never on a tie.

## 7. (reserved)

## 8. The committed history ledger (a real gap) + the derived fields

skill-creator keeps per-iteration workspaces; it has **no cumulative, committed, cross-run ledger**.
That is the maintainer's central requirement, so it is a core build item — together with the fields
skill-creator does not emit (cost, stderr/CI, pass^k, model identities).

**`evals/history.jsonl`** — append-only, one record per run, machine-readable, fed back as context:
```json
{
  "run_id": "2026-06-06T10:30:00Z",
  "skill": "review",
  "baseline_ref": "a1b2c3d",
  "candidate_ref": "e4f5g6h",
  "trials": 8,
  "executor_model": "claude-opus-4-8",
  "judge_model": "claude-opus-4-8",
  "models_resolved_at": "2026-06-06",
  "auq_autoanswer_policy": "approve-default-v1",

  "quality_winrate_vs_baseline": 0.78,
  "comparator_verdict": "candidate better",
  "position_swapped": true,
  "length_confounded": false,

  "pointwise_score": 4.2, "pointwise_delta": 0.3,

  "recall_at1": 0.90, "recall_passk": 0.80, "precision": 0.85,

  "mean_cost_usd": 0.42, "cost_delta": -0.05, "cost_derived_from": "tokens*price-map@v1",
  "mean_tokens": 51000, "tokens_delta": -3000,
  "mean_wall_seconds": 31.0, "time_delta": 1.4,

  "pass_rate": 0.95, "pass_rate_stddev": 0.04, "pass_rate_stderr": 0.014,
  "pass_rate_delta": 0.10,

  "significant": true, "ci_halfwidth_pp": 3.1, "ci_source": "computed-from-stderr", "ci_method": "t-interval@95%,df=n-1",
  "attempt_no": 1,
  "is_champion": true,
  "notes": "higher recall; cost down; delta clears computed CI; lengths comparable"
}
```

Key changes from v2's record:

- **`mean_cost_usd` is derived** (`cost_derived_from`) — skill-creator emits no dollars (§3). The price
  map is committed and versioned; mixed-tier sub-agent spend is accounted explicitly.
- **`pass_rate_stddev` (from skill-creator) vs `pass_rate_stderr` (we compute)** are both recorded. The
  gate uses **`ci_halfwidth_pp` computed per run** (`ci_source: computed-from-stderr`), not a hardcoded
  band. Ingest also records the CI **method** (`ci_method`, e.g. a t-interval at df = n−1) so the
  half-width is reproducible from the recorded stddev and trial count. A literal fallback band is allowed
  only when stderr is missing and is labelled as such.
- **`recall_passk`** (all-k-trials-catch-the-planted-bug) sits beside `recall_at1`. For a skill whose
  contract is reliability, **pass^k is the release gate**; pass@1 mean is reported for cost/quality
  context (§10).
- **`position_swapped` / `length_confounded`** make the judge's validity caveats explicit per run.
- **`attempt_no`** tracks repeated candidate↔champion runs to blunt multiple-comparisons p-hacking.
- **`executor_model` / `judge_model` / `models_resolved_at`** record what actually produced the verdict,
  since the pinned submodule does NOT pin the server-side models (§14, decision 3).

**`evals/HISTORY.md`** — human table, one row per run:

| Date | Skill | Candidate | vs | Quality (swap) | Pointwise | Recall^k | Cost Δ | Time Δ | CI ±pp | Significant | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-06-06 | review | e4f5g6h | a1b2c3d | 0.78 | 4.2 (+0.3) | 0.80 | −12% | +1.4s | 3.1 | yes | ✅ better |

Both files are committed and pushed so the trend survives across machines/sessions. The blind comparator
never sees them; the post-hoc `/geniro:eval` trend reader does.

## 9. Metrics — source vs derived (honest provenance)

Raw point estimates come from skill-creator; cost, CIs, pass^k, and all deltas are **derived by ingest**
in this repo. (v2's "all sourced from skill-creator, none re-derived" was wrong on both counts.)

| Metric | Role | Provenance |
|---|---|---|
| Pairwise winrate | **release gate** | skill-creator `comparator.md` (blind) **+ our position-swap wrapper** (run both orders, average) |
| Pointwise rubric | absolute anchor | skill-creator comparator's 1–5/overall-1–10 rubric — note it is _relative_; treat as anchor, not absolute cross-version score (§10) |
| Recall@1 / Recall^k / Precision | reference-based, where gold exists | **built** — our planted-bug gold set + findings extractor; not native to skill-creator |
| Cost (USD) | efficiency | **derived** — `mean_tokens × price-map.json` (per model tier); skill-creator emits no cost |
| Tokens | efficiency | skill-creator `timing.json` `total_tokens` (via task notification) |
| Wall-time | efficiency | skill-creator `timing.json` `duration_ms` |
| Pass-rate (expectations) | output-shape | skill-creator `benchmark.json` `pass_rate ± stddev`; **stderr/CI derived** by ingest |

Every metric is reported over the **per-skill trial count** (§8) with a **computed** CI; a delta inside
the CI is a tie, not a win.

"Steps / tool-calls / trajectory" are not in skill-creator and are optional (§13).

## 10. Quality signals — native vs built (be precise)

- **Pairwise winrate (release gate).** skill-creator's comparator is blind. We **add position-swap**
  (each pair judged in both A/B orders, averaged) because the source does not control position bias.
  **Length/format confound:** a skill edit often changes output shape; position-swap fixes _position_
  bias, not _length/verbosity_ bias. When the candidate's mean output length/format differs materially
  from baseline, ingest stamps `length_confounded: true` and the pairwise verdict alone **may not**
  clear the gate — the pointwise anchor and reference recall must corroborate.
- **Pointwise rubric (absolute anchor).** Exists only inside the comparator and is _relative_; it catches
  "both versions degraded" only loosely. Do not read it as an absolute cross-version quality score.
- **Reference recall/precision (built).** For `/review`, a **real git fixture** (a branch/diff/PR ref —
  not static files, because `/review` resolves targets as branch/diff/PR and runs `gh pr diff/view`)
  with a reviewed **manifest of findable issues**. Recall is measured as **found-AND-survived-Phase-4.2
  verification** (the verifier can legitimately suppress a true positive — that is measured behaviour,
  not noise). Report **recall^k** (caught in all k trials) as the reliability gate. Precision is scored
  against **planted ∪ human-adjudicated-true incidental** findings, not planted-only, or it drifts down
  as the reviewer improves (§15, fixture rot).
- **Expectation pass-rate (native).** Binary PASS/FAIL per `expectations[]` item, aggregated to a rate.
  Use for objective output shape.

## 11. Suites — real schema, real fixtures, and the integration order (inverted)

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

`expectations[]` are free-text statements graded PASS/FAIL by skill-creator's grader. There is **no**
`assertions[]` type enum; if a deterministic matcher is needed for output shape, that is a small net-new
check we own (the grader merely _suggests_ writing a script for programmatically-checkable expectations).

**Integration order (inverted from v2 — de-risk the plumbing first):**

1. **`/plan` for the first END-TO-END pipeline signal.** It produces a **single `spec.md`** — the clean,
   single-artifact case skill-creator was built for. Prove Phase 0 (gate auto-answer), capture, grade,
   ingest, and the first `HISTORY.md` row here, where the output is easy to grade.
2. **`/review` for judge CALIBRATION first, then full A/B.** Use a tiny planted-bug fixture (1–2 tasks,
   reference-scored, **no blind comparator needed**) to confirm recall/precision matches the known bug
   set — this validates the judge before we trust it on subjective verdicts. Only after the plumbing is
   proven on `/plan`, run the full `/review` A/B. Note `/review`'s real output is a **mutated multi-
   section handoff state file + chat message + gated GitHub PENDING POST**, not a clean report: the
   harness must parse the handoff `## Findings` section, normalise across a **variable** reviewer-
   dimension set, and **suppress** the GitHub post in eval runs.
3. **`/implement`** — multi-file diff, no single artifact, full gate chain. Last, if at all.

**Promote the deterministic seam check out of "future work" (judge-free, cheap, high-leverage).** Add
`evals/seam-check.sh`: assert that `/plan`'s `spec.md` frontmatter satisfies what `/review`'s
`workflow_refs[]` parser expects **when that field is present** (it is _optional_ — present only on
tracker-linked specs; assert parser-compatibility only when present, mirroring `/review`'s own
"treat as absent" acceptance, so the check never false-fails on an inline-task spec), and that
`/review`'s handoff carries the `open_questions[]` /
`step0_status` sentinels `/implement` consumes. This catches exactly the cross-skill regressions per-skill
artifact grading is blind to by construction — with no model, no trials, no cost.

## 12. Run UX

- **Engine for grading/comparison = skill-creator's prompts + scripts**, invoked by the harness or, in
  the manual interim (§5 option C), by the maintainer in chat.
- **Driving the skill = our run harness (Phase 0).** This is the part skill-creator cannot do for
  multi-agent, human-gated skills.
- **Bookkeeping + trend = `/geniro:eval` companion skill** (decided — §14). It prints the prior
  `HISTORY.md` trend (post-hoc), reminds the maintainer of the exact run invocation + suite path, and
  calls `ingest.sh`. It does NOT delegate to skill-creator (unsupported) and is NOT skill-creator's
  analyzer.

## 13. Optional trace layer (outside the core)

skill-creator grades outputs, not trajectories. If artifact-quality signal proves insufficient:

- **Trajectory / tool-call grading — preferred: Inspect AI** (UK AISI), purpose-built for multi-turn
  agentic evals; can run Claude Code as an external agent and grade the _path_.
- **Lightweight fallback: the `analyze-thread` skill** — parse a transcript for safety-invariant
  violations (`/refactor` pushed, spawn carried `model=`, missed parallel-spawn, `spec.md` missing the
  11-section schema) and step count. Record `discipline_pass_rate` / `steps`. Weaker than a real trace
  framework, zero new dependency.

These are additive and explicitly out of the initial build.

## 14. Decisions (resolved)

1. **Bookkeeping + trend layer:** the **`/geniro:eval`** companion skill (decided — v2's "optional, decide
   later" is resolved as _build it_). It reads the ledger and prints the trend post-hoc; it does not
   delegate to skill-creator and is not the analyzer.
2. **Judge model:** **Opus** for the blind comparator/judge — a deliberate _upgrade_ over geniro's
   model-tiering floor (`skills/_shared/model-tiering.md` puts a PASS/FAIL rubric judge at haiku/sonnet),
   chosen to maximize judge reliability on subtle differences. **Running executor-internal sub-agents on
   Sonnet is available ONLY on the headless/orchestratorless path (Phase 0 option A):** per
   `model-tiering.md`, `model: inherit` lets the calling layer pick a tier _from the fallback table_ only
   when there is no interactive orchestrator parent — it is _fallback, not "the harness may choose"_. In
   the manual interim (option C) those agents **inherit the operator's session tier (Opus)**, so the cost
   figure in decision 10 is a **floor**, not a range, until the headless harness exists.
3. **skill-creator acquisition:** **git submodule, pinned to a SHA.** This freezes skill-creator's
   _prompts and scripts_ — **not** the eval _results_: the Opus judge and the Claude executor are
   versionless server-side models that drift independently. Reproducibility is therefore scoped to the
   harness; result stability comes from the multi-trial CI gate (decision 4) and recording
   `executor_model`/`judge_model`/`models_resolved_at` per run.
4. **Trials & significance:** **per-skill trial count, computed — not a flat 5.** Establish each skill's
   null A-vs-A spread (run the same version twice at N trials, measure the null delta) and set trials so
   the CI half-width < the smallest delta worth detecting; expect `/review` to need more than `/plan`
   because its sub-agent spawn count varies per run. The significance gate uses the **per-run computed
   CI**, not a hardcoded band.
5. **Comparator is history-blind** (anchoring bias). The ledger is read only post-hoc by `/geniro:eval`.
   The human operator also reads the trend only after fixing the blind verdict (§15).
6. **Quality = three signals (our design):** position-swapped pairwise (gate) + relative pointwise rubric
   (anchor) + built reference recall/precision where gold exists. None is a pure skill-creator feature in
   the form we use; label them as such.
7. **Integration order:** **`/plan` first** for end-to-end plumbing (clean single artifact); `/review`
   for judge calibration, then full A/B; `/implement` last (inverts v2's "`/review` first").
8. **Optional trace layer:** Inspect AI preferred over `analyze-thread`, if needed (§13).
9. **What lands in git:** the ledger (`HISTORY.md` + `history.jsonl`), `price-map.json`, the suites, the
   seam check, and the harness. Raw per-trial transcripts under `evals/runs/` are `.gitignore`d.
10. **Cost is a first-class concern, not "acceptable."** A single `/review` executor run fans out to
    ~20–25 Opus-tier agent invocations (standard mode; `--deep` ~triples the reviewer + per-finding-
    verifier fan-out); at the per-skill trial count × 2 versions × position-swap, one
    `/review` suite run is plausibly **$80–150 and 1–3 hours** (order-of-magnitude — _measure in the first
    real run_). Mitigations: Sonnet for executor-internal agents, Opus only for the judge; adaptive
    (sequential) stopping rather than a flat trial count; a hard per-run dollar ceiling recorded in the
    ledger.

## 15. Known limitations (accepted)

- **Per-skill, not end-to-end.** Artifact quality in isolation will NOT catch cross-skill seam
  regressions (handoffs, `open_questions[]` gating, the `/plan`→`/implement`→`/review` loop). _Mitigated_
  by the deterministic seam check (§11), which is now in-scope; a full pipeline-level _quality_ eval
  remains future work.
- **Judge is same-family.** Opus judging Claude-produced artifacts carries self-preference bias. In blind
  pairwise A-vs-B it is roughly symmetric **only when both sides have similar verbosity/format** — which
  a skill edit frequently breaks. Hence `length_confounded` gating (§10). Do not read the pointwise
  anchor as an absolute cross-model score; revisit if the executor model changes family.
- **Model drift defeats prompt pinning.** The pinned submodule does not pin the server-side judge/executor
  models; the CI gate and recorded model IDs are the defence, not the pin (decision 3).
- **Gold-fixture rot.** As `/review` adds dimensions it will find _real_ incidental issues absent from the
  planted set, depressing measured precision even when correct; a planted bug may also become trivially
  detectable. **Owner + cadence:** re-audit the fixture whenever a review dimension changes; score
  precision against planted ∪ human-adjudicated-true; pin the findable-issue manifest beside the fixture.
- **Cost/time is real** (decision 10) — not a rounding error.
- **Residual human anchoring.** Because the run is human-in-the-loop, the operator who reads the trend can
  re-introduce the anchoring bias the machine judge avoids. Protocol: read `HISTORY.md` trend only AFTER
  the blind verdict is fixed (§6 step 1/5).
- **Ledger is a deliberate exception** to "don't commit eval results" — a small, low-churn, semantic
  scorecard (like a `CHANGELOG`), not raw run data.

## 16. Phased build plan

- **Phase 0 — gate harness (BLOCKING, §5).** Build the unattended driver (or commit to the manual
  protocol). Done when one trial of `/plan` completes end-to-end with no human, outputs where the grader
  expects. Nothing below proceeds past a manual smoke run until this lands.
- **Phase A — ledger + price map + suites + seam check.** Create `evals/` tree, `.gitignore`
  `evals/runs/`, write `price-map.json`, `evals/suites/plan/evals.json` (real schema), `evals/seam-check.sh`,
  seed empty `history.jsonl` + `HISTORY.md`.
- **Phase B — ingest helper.** `evals/ingest.sh`: derive cost from tokens × price map, compute stderr/CI,
  apply the per-skill significance gate, reject dirty trees, track attempt count, append to both ledger
  files. README with the exact harness invocation and auto-answer policy.
- **Phase C — first real run on `/plan` (clean artifact) + measure cost/time.** Pin skill-creator as a
  submodule, run `/plan` version-vs-version through the harness, grade with skill-creator's grader,
  ingest, eyeball the first `HISTORY.md` row, **record actual $ and wall-time** to validate decision 10.
- **Phase D — `/review` calibration then A/B.** Build the planted-bug git fixture + findings extractor +
  position-swap wrapper; calibrate recall/precision against the known bug set; then full A/B. Build
  `/geniro:eval`.
- **Phase E — optional trace layer.** Inspect AI (or `analyze-thread` fallback) if core signal proves
  insufficient (§13).

## 17. Prior art references

- `anthropics/skills` (canonical) + `anthropics/claude-plugins-official` (mirror) — skill-creator: the
  reused **grader/comparator/analyzer prompts, `aggregate_benchmark.py`, `eval-viewer`, and JSON
  schemas** (a create→test→improve loop with a blind comparator and a `skill-snapshot/` baseline — _not_
  switchable "Eval/Improve modes", _not_ a turnkey quality-eval CLI, _no_ executor agent, _no_ cost
  field, _no_ position-swap, _no_ reference recall/precision).
- TribeAI/claude-evals — ideas only (severity tiers, judge variance reduction, per-case budget).
- Anthropic engineering — "Demystifying evals for AI agents" (grade outcomes not path, read transcripts,
  start at 20–50 tasks, **pass@k vs pass^k** — we record pass^k for reliability-contract skills, §8/§10).
- Inspect AI (UK AISI) — preferred optional trace/tool-call eval layer (§13).
- "On Randomness in Agentic Evals" / "Stochasticity in Agentic Evaluations" (arXiv) — variance scales with
  **both** tasks and trials; single-run pass@1 can swing several pp; hence per-skill computed CIs and
  trial counts (§8, decision 4), not a hardcoded band.
- "Judging the Judges: Position Bias in Pairwise LLM-as-Judge" (arXiv) + LLM-judge bias surveys —
  position-swap (which we **add**, §10), blinding, verbosity/self-preference caveats (decisions 5–6,
  §15).
