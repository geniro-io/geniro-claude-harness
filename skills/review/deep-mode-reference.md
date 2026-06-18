# Deep Mode Reference

Deep mode (`--deep`, or the "Deep" pick in the Phase 1 §11 review-depth question) raises **quality** — recall (find more) and precision (validate more reliably) — by multiplying the reviewer and verifier fan-out and running it inside an internal `Workflow(...)`. It does NOT raise speed: under the Workflow concurrency cap (`min(16, cores-2)` concurrent agents per workflow) the extra passes do not shrink wall-clock, they only deepen coverage at higher token cost. Two efficiency refinements keep that cost from being a flat 3× multiplier — **angle-diverse recall** (each per-dim pass searches a distinct region, not an identical re-run) and **signal-gated precision** (one verifier on the clear majority, the full 3-vote only where the call is contested). Deep mode is opt-in for exactly this reason — it is not the default.

Deep mode sets the boolean `deep-mode: true`. It changes HOW MANY reviewer/verifier passes run and how their results aggregate — it does NOT change the Reporter boundary, the posted-set semantics, the action-gate options, or the `atomic_state_write` contract.

**Cross-skill common contract.** The rules `/geniro:review`, `/geniro:plan`, and `/geniro:implement` share — the activation pattern, the mandatory Workflow mitigations, the fail-safe ladder, and the boundary-preservation rules — are canonicalized in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md`. This file keeps its review-specific layers (§2 recall, §3 precision) inline; where it overlaps the shared contract (§4 mitigations, §6 fail-safe, §9 anti-rationalization), the shared file is the canonical statement.

## Contents

- §1 — Activation + state
- §2 — Recall layer (Phase 2: 3 angle-diverse reviewer passes per dimension)
- §3 — Precision layer (Phase 4.2: signal-gated majority verification)
- §4 — The Workflow scripts (shape + mandatory mitigations)
- §5 — Convergence-dedup rule (load-bearing)
- §6 — Fail-safe ladder
- §7 — Reporter-contract preservation inside the workflow
- §8 — Edge cases
- §9 — Anti-rationalization

---

## 1. Activation + state

- **Flag:** `/geniro:review --deep <args>` sets deep mode. Semantic parse (matches `--deep`, `deep`, `deep mode`).
- **Chooser:** when no `--deep` flag is present, the Phase 1 §11 Mode AUQ asks review depth — "Standard" / "Deep — multi-angle review + extra verification". Picking Deep sets the boolean.
- **State:** persist `deep-mode: <true|false>` to state.md frontmatter and the handoff frontmatter (schema-lockstep per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` /geniro:review producer fields; missing reads as `false`). Persist the chooser pick to `approvals[]` with category `deep_mode_choice` so the session-restore hook re-applies it on a compaction-resume.
- **Composition:** deep mode does not change the Phase 4.3 test-confirmation gate — the gate still fires on the verified survivors whenever eligible findings exist; the two never conflict.

When `deep-mode: false` (default), Phase 2 and Phase 4.2 run exactly as today (single reviewer batch, single per-finding verifier) — deep mode adds no overhead to standard runs.

---

## 2. Recall layer — Phase 2: 3 angle-diverse reviewer passes per dimension

When `deep-mode: true`, Phase 2 replaces the single parallel reviewer batch with a `Workflow(...)` call that runs **each declared dimension under 3 distinct angles** and aggregates in-script:

- The declared dimension set is unchanged — every always-fire + triggered-conditional + custom dimension from the §2.1 grid (still recorded in `spawn_dims_declared[]`; the `§4.0` verification gate still checks the declared SET, treating the 3 angles as a multiplier on each declared dim, not a new dim).
- For each dimension, the workflow spawns 3 independent `reviewer-agent` passes (parallel), each with the same pre-inlined context the single-pass spawn uses (diff, criteria, mechanical pre-pass findings, the dim's context slots), but each scoped to a DISTINCT angle so the passes search near-disjoint regions rather than re-running one identical prompt:
  - **A — common path:** the most likely defects of this dimension on the typical code path.
  - **B — boundaries and error paths:** rare inputs, boundary conditions, exception/error handling, resource lifecycle, concurrency.
  - **C — interaction:** how this dimension's concerns couple with the rest of the diff and the surrounding code — callers of changed symbols, sibling/parallel paths, flags and config.

  These angles are dimension-agnostic (they apply to `bugs`, `security`, `architecture`, … alike), so the angle instruction is a short prefix on the existing per-dim prompt — no per-dimension angle table to maintain.
- The workflow **unions + dedups the 3 angle passes of one dimension into a single per-dim finding set** before returning — see §5. Returns, per dimension, the deduped findings list as raw JSON text.
- The orchestrator reads the workflow result and proceeds to Phase 3 (orchestrator-side dedup + cross-dim convergence) exactly as in standard mode, but over the deeper per-dim sets.

**Why angle-diverse passes raise recall efficiently:** three identical passes rely only on sampling temperature to scatter — they harvest the tail of one distribution, so much of what they return overlaps and is discarded at dedup. Three angle-scoped passes search where the others do not, so each pass buys new territory at the same token cost — higher recall per token. When 2 of 3 angles independently surface the same issue, that cross-angle agreement is a stronger within-dim reliability signal than three identical clones agreeing (recorded as `seen-in: N/3 angles` per §5).

The Workflow tool returns its result to the orchestrator and the orchestrator resumes Phase 3 on completion. State.md `phase: llm-spawn` persists across the workflow call so a mid-workflow compaction resumes correctly (the workflow itself is resumable via its runId; the skill re-reads its result).

---

## 3. Precision layer — Phase 4.2: signal-gated majority verification

When `deep-mode: true`, every §4.1 survivor (CRITICAL / HIGH / MEDIUM — no tier-scaling, unchanged) is verified inside a `Workflow(...)`, but the vote count is **gated by signal** — one verifier on the clear majority, the full 3-vote majority only on contested or high-stakes findings:

- **First vote (always).** Run ONE independent verifier on the finding — the same isolated input the single-pass verifier gets (the single finding's body + cited slice + caller grep + sibling tests per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2), NOT any other verifier's output (independence is load-bearing). It emits the standard structured result (`validation: confirmed | refuted | clarified`, `recommended_action`, `confidence`, `evidence`) as raw JSON text.
- **Escalate to 3** (run 2 more independent verifiers, then majority) when ANY of:
  - the first vote's `confidence < 70` — a low-confidence vote is the unreliable one the majority exists to backstop;
  - the first vote is `refuted` AND the finding's `convergence_count >= 2` — the verdict contradicts the cross-dimension agreement that admitted it, exactly the contested case majority arbitrates;
  - the finding is CRITICAL or HIGH AND the first vote is `refuted` — one vote never drops a high-stakes finding.
- **Accept the single vote** (no escalation) otherwise: a high-confidence first vote that agrees with the upstream signal — a `confirmed`/`clarified` of any survivor, or a `refuted` of a lone (`convergence_count < 2`) MEDIUM finding. The cross-dim convergence that admitted the finding already corroborates a confirm, so the lone verifier is not the only evidence; a lone low-stakes refute is cheap to act on if wrong.
- **Majority rule when escalated (of 3):** count `confirmed` and `clarified` as "stands" votes, `refuted` as "drop" votes.
  - ≥2 "drop" votes → the finding is **refuted** → demote to `## Filtered` (`reason: refuted-by-majority-verify`).
  - otherwise → the finding **stands**; adopt the majority `recommended_action` (if the stands-votes split between `confirmed` and `clarified`, take `clarified` when ≥2 verifiers returned a non-original action, else `confirmed`).
- **Abstain = parse failure.** A verifier whose raw output won't parse into the schema **abstains** — it counts toward neither "stands" nor "drop", and never demotes a finding. A first-vote abstention triggers escalation (run the other 2); if all 3 abstain, quorum fails.
- **Quorum.** If fewer than 2 verifiers returned a parseable vote on an escalated finding (≥2 abstained), there is no majority → **fail-safe**: run ONE fresh single-pass verifier and take its verdict. Note `verification: deep-mode quorum fail-safe (single-pass)` in the finding's `Verification-evidence`. If that single-pass verifier also fails to spawn or returns nothing parseable, apply the standard spawn-failure fail-open — the orchestrator assigns `Validation: unverified` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4.5 (finding kept, excluded from the PR post set, surfaced under `## Caveats`).
- **Persist into existing fields — no schema bump.** Write the verdict to the finding's existing `Validation` field; record the vote path in `Verification-evidence` — `1-vote (corroborated): confirmed, conf 88` for the accepted-single path, `3-vote: 2 confirmed / 1 refuted / 0 abstain → confirmed` for the escalated path. Do NOT add new per-finding schema fields — the consumer (`/geniro:implement` Step 12, §7.0 guard) reads `Validation` unchanged.

**Why signal-gating preserves precision while cutting votes:** a single verifier can hallucinate — false-confirm a non-bug or false-refute a real one (the documented multi-judge failure mode). The 3-vote majority tolerates one bad vote, but only the contested dispositions actually need that tolerance: a confirm that agrees with cross-dim convergence is already corroborated by independent producers, and a lone low-stakes refute is cheap if wrong. Spending the extra 2 votes only where the first vote is low-confidence, contradicts upstream agreement, or would drop a high-stakes finding keeps the hallucination-tolerance exactly where a flipped disposition is costly — at roughly `N + 2·(contested fraction)·N` votes instead of `3N`.

---

## 4. The Workflow scripts (shape + mandatory mitigations)

Deep mode invokes the Workflow tool from inside the skill — sanctioned because the skill body instructs it (the Workflow opt-in rule covers "a skill whose instructions tell you to call Workflow"). Two fan-outs: the Phase 2 recall script and the Phase 4.2 vote script (may be one script with two phases, or two calls).

**Recall script (Phase 2) — shape:**

```
phase('Deep review — angle-diverse passes')
const ANGLES = ['common-path', 'boundaries-and-errors', 'interaction']   // §2: 3 distinct, dimension-agnostic angles
const passes = await pipeline(
  DIMENSIONS,                                  // the declared §2.1 set
  d => parallel(ANGLES.map(angle =>            // 3 angle-scoped passes per dim — each searches a distinct region
    () => agent(reviewerPrompt(d, angle), { label: `${d.slug}:${angle}`, phase: 'Deep review — angle-diverse passes' })
  )),
  (anglePasses, d) => dedupeWithinDim(anglePasses, d)   // union + dedup IN-SCRIPT → one per-dim set (seen-in: N/3 angles)
)
return passes                                  // per-dim deduped findings (raw JSON text from agents, parsed in-script)
```

**Vote script (Phase 4.2) — shape (signal-gated per §3):**

```
phase('Deep verify — signal-gated')
const verdicts = await parallel(SURVIVORS.map(f => () => (async () => {
  const first = parseVote(await agent(verifierPrompt(f, 0), { label: `verify:${f.id}:v0`, phase: 'Deep verify — signal-gated' }))
  if (!needsEscalation(first, f)) return { id: f.id, verdict: first }       // high-confidence + agrees with upstream → accept 1 vote
  const rest = await parallel([1,2].map(i => () =>                          // contested / high-stakes → full 3-vote majority
    agent(verifierPrompt(f, i), { label: `verify:${f.id}:v${i}`, phase: 'Deep verify — signal-gated' })))
  return { id: f.id, verdict: majority([first, ...rest]) }                  // majority() parses defensively; parse-fail = abstain
})()))
return verdicts
// needsEscalation(first, f) = first abstained (parse-fail) OR first.confidence < 70
//   OR (first.validation === 'refuted' && f.convergence_count >= 2)
//   OR (first.validation === 'refuted' && (f.severity === 'CRITICAL' || f.severity === 'HIGH'))
```

**Mandatory mitigations (every deep workflow MUST observe):**

1. **Raw JSON, not schema.** Use `agent(prompt)` returning raw JSON text and parse it defensively in-script — NEVER `agent({schema})`. The dynamic-Workflow StructuredOutput tool-call drops roughly two-thirds of the time on long / converged agents; a schema-typed vote would silently lose votes. A parse failure is an **abstention**, never a refute.
2. **Re-assert the Reporter contract in every agent prompt.** Each reviewer/verifier prompt restates: read-only; no `Edit`/`Write`; no `git` mutation; no state writes (the orchestrator owns all `atomic_state_write`). The workflow parallelizes the fan-out, not the contract — see §7 and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`.
3. **Path constants outside template literals.** A bare `${CLAUDE_PLUGIN_ROOT}` (or any `${...}`) inside a workflow backtick template literal is interpreted as JS interpolation and crashes the script. Build path/context strings as plain constants BEFORE the literal, or reference plugin files by repo-relative path inside prompts.
4. **OMIT `model=` at every spawn.** Reviewers/verifiers inherit the orchestrator tier (`model: inherit`). Never tier-pin voters to control cost — that defeats the user's session `/model` choice and is exactly the failure mode the model-tiering doctrine prevents.
5. **Agent registration.** The `spawn-agent.md` prefixed→bare→general-purpose retry ladder is awkward inside a single `agent({agentType})` call. Resolve by either (a) passing the session-resolved registration rung as `agentType`, or (b) spawning `general-purpose` with the `reviewer-agent` body (frontmatter stripped) + criteria inlined into the prompt — the most runtime-robust option. If agent registration fails inside the workflow runtime, fail-safe to the non-workflow single-pass path (§6).

---

## 5. Convergence-dedup rule (load-bearing)

`convergence_count` (Phase 4.1 signal #1; Phase 5.3 ≥3 pitfall auto-emit) counts **distinct dimensions** that reported the same issue — it is a cross-reviewer agreement signal. The 3 angle passes of ONE dimension finding the same issue is one dimension's own passes agreeing, NOT cross-dim convergence.

Therefore: **dedup the 3 angle passes of a dimension into a single per-dim finding set BEFORE Phase 3 computes cross-dim convergence.** The recall script (§4) does this in-script (`dedupeWithinDim`) so the per-dim set the orchestrator receives already collapses intra-dim duplicates. If this dedup is skipped, three angle passes of `bugs` finding the same defect would inflate its `convergence_count` to 3 and trip the §4.1 gate (and the pitfall auto-emit) on a single dimension's repeated output — deep mode would game its own quality gate.

Intra-dim dedup match: same file + overlapping line range + same defect class. When 2 of 3 angle passes agree, keep the finding once (note `seen-in: 2/3 angles` in its body as a within-dim reliability signal — distinct from cross-dim `convergence_count`).

---

## 6. Fail-safe ladder

Current single-pass behavior is the **floor** — deep mode is never weaker than standard. Degrade in order:

1. **Workflow errors / returns unparseable aggregate / agent registration fails** → fall back to the standard single-pass Phase 2 batch (or single-pass Phase 4.2 verifier). Surface a plain-English `## Caveats` note — `Deep review couldn't run the extra passes for the <reviewing|verifying> step — fell back to a single pass.` (map the `llm-spawn` phase → "reviewing", `stratify` → "verifying"); keep the storage enum only in the `## Errors` body entry (`phase: <llm-spawn|stratify>`, `error: deep-workflow-failed`, `consequence: single-pass-fallback`).
2. **Per-finding vote quorum fails** (≥2 verifiers abstained) → single fresh single-pass verifier for that finding (§3).
3. **A single angle pass within a dimension fails** → the dimension still returns the union of the surviving angle passes (2 or 1); note the reduced angle count in `## Caveats`. Never drop the dimension.

Fail-safe is silent-degrade-with-a-caveat, never a hard stop — a review that ran shallower than requested is still a valid review.

---

## 7. Reporter-contract preservation inside the workflow

A workflow wrapper makes the model treat the workflow as authority and the skill body as advisory — the contract then evaporates (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`). Inside the deep workflow, ALL of these still bind, re-asserted in each step:

- **Reporter boundary** — reviewers/verifiers are read-only; no `Edit`/`Write`/`git`/`gh` mutation. The workflow produces findings + verdicts, nothing else.
- **Atomic state writes** — the orchestrator (NOT the workflow agents) owns every `atomic_state_write` to state.md and the handoff. Workflow agents return data; they never write `.geniro/` state.
- **Action gate** — deep mode does not add or change action-gate options. The canonical 4 options and the `report_status: final` precondition (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3.5) bind unchanged.
- **No-ship** — deep mode never pushes or fixes. The authored-test push carve-out (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §1) is the only sanctioned write, and it is independent of deep mode.

---

## 8. Edge cases

**`--deep` on a trivial diff.** Deep mode still runs (the user asked for it). The cost is real but bounded; the Action gate / triage-out of trivial files (§12 size triage) still applies, so a formatting-only diff is triaged out before the fan-out.

**`--deep` with test authoring approved at the Phase 4.3 gate.** Both apply: the angle-diverse / signal-gated fan-out AND failing-test authoring. The deep verification runs first (Phase 4.2); the test-gate (Phase 4.3) runs on the survivors of the gated verification, so authored tests target verified findings only — a strict improvement.

**Round-2+ re-run.** Prior-round findings feed the reviewer prompts as today. Depth is re-asked on a fresh re-run — via the §7 re-review gate (`${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §7) — because a fresh `/geniro:review` re-invocation never inherits the prior round's `deep_mode_choice`; only a compaction-resume of an in-flight run re-applies it. Passing `--deep` on the re-run pre-resolves depth to Deep as on any run.

**Workflow unavailable in the runtime** (SDK / cron with no Workflow tool). Fail-safe ladder rung 1 — run single-pass, note the caveat. Deep mode degrades to standard rather than erroring.

---

## 9. Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The deep passes run in parallel, so the review finishes faster." | Parallelism does not reduce wall-clock under the `min(16, cores-2)` cap — the extra agents fill the same concurrency waves (no speedup) or spill into more waves (slowdown). Deep mode is a thoroughness lever, NOT a latency lever. Sell it as quality, never speed. |
| "Three angle passes of the bugs dim all found it — that's convergence_count 3, admit it past the gate." | The 3 angle passes of ONE dimension agreeing is that dimension agreeing with itself, not cross-dim convergence. Dedup intra-dim BEFORE computing cross-dim convergence (§5), or deep mode games its own Phase 4.1 gate. |
| "Re-run each dimension's reviewer prompt 3× identically — that's the recall lever." | Identical passes only scatter by sampling temperature: high overlap, heavy dedup churn, low marginal recall per pass. Scope each pass to a distinct angle (common-path / boundaries-and-errors / interaction) so each buys new territory at the same cost; cross-angle agreement is also a stronger within-dim signal than identical clones (§2). |
| "Run one verifier per survivor in deep mode — the §4.1 gate already vetted them, that saves the most tokens." | The single-vote path is gated by signal, not blanket (§3): a first vote with `confidence < 70`, a `refuted` of a finding with `convergence_count >= 2`, or any `refuted` of a CRITICAL/HIGH finding escalates to the full 3. Blanket single-vote re-opens the single-hallucination flip the majority prevents. |
| "I'm inside a Workflow now, so the no-Edit / no-push boundary is just guidance." | The workflow parallelizes the fan-out, not the contract. Every Reporter invariant binds inside every workflow step (§7). The contract evaporating under the wrapper is the documented failure this rule prevents. |
| "Use agent({schema}) for the votes — structured output is cleaner." | The StructuredOutput tool-call drops ~⅔ of the time on long/converged agents, silently losing votes. Return raw JSON text and parse defensively; a parse failure is an abstention, not a refute. |
| "Two verifiers abstained (parse-failed) and one refuted — that's a majority to drop." | Abstentions count toward neither side. One refute out of one parseable vote is NOT a majority — quorum failed, so fail-safe to a single fresh single-pass verifier. Never demote a finding on abstentions. |
| "Deep workflow errored — abort the review." | Current single-pass behavior is the floor. A workflow failure degrades to single-pass with a `## Caveats` note, never a hard stop (§6). A shallower-than-requested review is still valid. |
| "Pin the voters to a cheaper tier to control deep mode's cost." | OMIT `model=` — voters inherit the orchestrator tier. Tier-pinning defeats the user's session `/model` choice; the cost knob is the opt-in flag itself, not a silent downgrade of the agents. |
