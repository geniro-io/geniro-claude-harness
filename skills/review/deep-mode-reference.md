# Review deep mode — reference

**Cross-skill common contract.** The activation pattern, the mandatory Workflow mitigations, the fail-safe ladder, the boundary-preservation rules, and the shared anti-rationalization live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` — read it first. This file covers only what `/geniro:review` deepens.

Deep mode (`--deep`, or the "Deep" pick in the Phase 1 review-depth question — `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §11) multiplies the reviewer and verifier fan-out inside an internal `Workflow(...)`: a thoroughness lever, never a latency one. Two refinements keep its cost off a flat 3× multiplier — **angle-diverse recall** (each per-dim pass searches a distinct region rather than re-running one identical prompt) and **signal-gated precision** (one verifier on the clear majority, the full 3-vote only where the call is contested).

Deep mode sets the boolean `deep-mode: true`. It changes HOW MANY reviewer/verifier passes run and how their results aggregate — it does NOT change the Reporter boundary, the posted-set semantics, the action-gate options, or the `atomic_state_write` contract.

## Contents

- §1 — Activation + state
- §2 — Recall layer (Phase 2: 3 angle-diverse reviewer passes per dimension)
- §3 — Precision layer (Phase 4.2: signal-gated majority verification)
- §4 — The Workflow scripts (shape)
- §5 — Convergence-dedup rule (load-bearing)
- §6 — Fail-safe ladder
- §7 — Reporter-contract preservation inside the workflow
- §8 — Edge cases
- §9 — Anti-rationalization

---

## 1. Activation + state

- **Flag:** `/geniro:review --deep <args>` sets deep mode. Semantic parse (matches `--deep`, `deep`, `deep mode`).
- **Chooser:** when no `--deep` flag is present, the Phase 1 depth question (`${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §11) asks review depth — "Standard" / "Deep — multi-angle review + extra verification". Picking Deep sets the boolean.
- **State:** persist `deep-mode: <true|false>` to state.md frontmatter and the handoff frontmatter (schema-lockstep per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` /geniro:review producer fields; missing reads as `false`). Persist the chooser pick to `approvals[]` with category `deep_mode_choice` so the session-restore hook re-applies it on a compaction-resume.
- **Composition:** deep mode does not change the Phase 4.3 test-confirmation gate — the gate still fires on the verified survivors whenever eligible findings exist; the two never conflict.

When `deep-mode: false` (default), Phase 2 and Phase 4.2 run exactly as today (single reviewer batch; one `finding-verifier-agent` verdict per survivor via file-clustered verifier spawns) — deep mode adds no overhead to standard runs.

---

## 2. Recall layer — Phase 2: 3 angle-diverse reviewer passes per dimension

When `deep-mode: true`, Phase 2 replaces the single parallel reviewer batch with a `Workflow(...)` call that runs **each declared dimension under 3 distinct angles** and aggregates in-script:

- The declared dimension set is unchanged — every always-fire + triggered-conditional + custom dimension from the §2.1 grid (still recorded in `spawn_dims_declared[]`; the `§4.0` verification gate still checks the declared SET, treating the 3 angles as a multiplier on each declared dim, not a new dim). Each angle-pass reviewer receives the same payload shape as standard mode (on large diffs, the Batched grouped reading order per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §12) — the Workflow multiplies angles per dimension, never file-batches.
- For each dimension, the workflow spawns 3 independent `reviewer-agent` passes (parallel), each with the same context the single-pass spawn passes (diff, criteria paths, mechanical pre-pass findings, the dim's context slots), but each scoped to a DISTINCT angle so the passes search near-disjoint regions rather than re-running one identical prompt:
  - **A — common path:** the most likely defects of this dimension on the typical code path.
  - **B — boundaries and error paths:** rare inputs, boundary conditions, exception/error handling, resource lifecycle, concurrency.
  - **C — interaction:** how this dimension's concerns couple with the rest of the diff and the surrounding code — callers of changed symbols, sibling/parallel paths, flags and config.

  These angles are dimension-agnostic (they apply to `bugs`, `security`, `architecture`, … alike), so the angle instruction is a short prefix on the existing per-dim prompt — no per-dimension angle table to maintain.
- The workflow **unions + dedups the 3 angle passes of one dimension into a single per-dim finding set** before returning — see §5. Returns, per dimension, the deduped findings list as raw JSON text.
- The orchestrator reads the workflow result and proceeds to Phase 3 (orchestrator-side dedup + cross-dim convergence) exactly as in standard mode, but over the deeper per-dim sets.

The Workflow tool returns its result to the orchestrator and the orchestrator resumes Phase 3 on completion. State.md `phase: llm-spawn` persists across the workflow call so a mid-workflow compaction resumes correctly (the workflow itself is resumable via its runId; the skill re-reads its result).

---

## 3. Precision layer — Phase 4.2: signal-gated majority verification

When `deep-mode: true`, every §4.1 survivor (CRITICAL / HIGH / MEDIUM — no tier-scaling, unchanged) is verified inside a `Workflow(...)`, but the vote count is **gated by signal** — one verifier on the clear majority, the full 3-vote majority only on contested or high-stakes findings:

- **First vote (always).** Run ONE independent verifier on the finding — the degenerate one-finding cluster input (the finding's body + cited slice + caller grep + sibling tests per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2), NOT any other verifier's output (independence is load-bearing). It emits the standard structured result (`validation: confirmed | refuted | clarified`, `recommended_action`, `confidence`, `evidence`) as raw JSON text.
- **Escalate to 3** (run 2 more independent verifiers, then majority) when ANY of:
  - the first vote fails the minimum bar in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3 (abstained, or `confidence <= 3`);
  - the first vote is `refuted` AND the finding's `convergence_count >= 2` — the verdict contradicts cross-dimension agreement on the same finding, exactly the contested case majority arbitrates (that agreement no longer admits anything at §4.1, but a verdict cutting against it still marks the finding as disputed);
  - the finding is CRITICAL or HIGH AND the first vote is `refuted` — one vote never drops a high-stakes finding.
- **Accept the single vote** (no escalation) otherwise: a high-confidence first vote that agrees with the upstream signal — a `confirmed`/`clarified` of any survivor, or a `refuted` of a lone (`convergence_count < 2`) MEDIUM finding. Cross-dim convergence on the finding already corroborates a confirm, so the lone verifier is not the only evidence; a lone low-stakes refute is cheap to act on if wrong. A `refuted` at CRITICAL or HIGH never reaches this branch — it always escalates, which is deep mode's form of the standard-mode high-stakes refutation guard (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §5 rule 1).
- **Majority rule when escalated (of 3):** count `confirmed` and `clarified` as "stands" votes, `refuted` as "drop" votes.
  - ≥2 "drop" votes → the finding is **refuted** → demote to `## Filtered` (`reason: refuted-by-majority-verify`).
  - otherwise → the finding **stands**; adopt the majority `recommended_action` (if the stands-votes split between `confirmed` and `clarified`, take `clarified` when ≥2 verifiers returned a non-original action, else `confirmed`).
- **Abstain = parse failure.** A verifier whose raw output won't parse into the schema **abstains** — it counts toward neither "stands" nor "drop", and never demotes a finding. A first-vote abstention triggers escalation (run the other 2); if all 3 abstain, quorum fails.
- **Quorum.** If fewer than 2 verifiers returned a parseable vote on an escalated finding (≥2 abstained), there is no majority → **fail-safe**: run ONE fresh single-pass verifier and take its verdict. Note `verification: deep-mode quorum fail-safe (single-pass)` in the finding's `Verification-evidence`. If that single-pass verifier also fails to spawn or returns nothing parseable, apply the standard spawn-failure fail-open — the orchestrator assigns `Validation: unverified` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4.5 (finding kept, excluded from the PR post set, surfaced under `## Caveats`).
- **Persist into existing fields — no schema bump.** Write the verdict to the finding's existing `Validation` field; record the vote path in `Verification-evidence` — `1-vote (corroborated): confirmed, conf 88` for the accepted-single path, `3-vote: 2 confirmed / 1 refuted / 0 abstain → confirmed` for the escalated path. Do NOT add new per-finding schema fields — the consumer (/geniro:implement's handoff-resolution step, §7.0 guard) reads `Validation` unchanged.

---

## 4. The Workflow scripts (shape)

Two fan-outs: the Phase 2 recall script and the Phase 4.2 vote script (may be one script with two phases, or two calls). Both skeletons are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3 §Script skeletons — instantiate them rather than re-deriving. Review's substitutions: the stage set is the declared §2.1 dimension grid, the angles are the three in §2, and the dedup key is the intra-dim rule in §5.

**Apply every mandatory Workflow mitigation in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §4 at both fan-outs** — raw JSON over `agent({schema})`, the boundary re-asserted in every prompt, path constants outside template literals, `model=` omitted, the registration ladder, no `run_in_background`. Each one prevents an observed failure; read them before writing the script.

**Review's escalation predicate** — the one skill-specific piece of the vote skeleton. It keys on cross-dim `convergence_count` (not the within-dim `seen_in`) and escalates a high-stakes finding only on a `refuted` first vote, not in both directions, because review reports rather than fixes:

```
// review's needsEscalation(first, f) = deep-mode.md §3 minimum (abstained OR confidence <= 3)
//   OR (first.validation === 'refuted' && f.convergence_count >= 2)
//   OR (first.validation === 'refuted' && (f.severity === 'CRITICAL' || f.severity === 'HIGH'))
```

---

## 5. Convergence-dedup rule (load-bearing)

`convergence_count` (the §3 escalation predicate; the Phase 5.3 pitfall auto-emit threshold — it admits nothing at Phase 4.1) counts **distinct dimensions** that reported the same issue — it is a cross-reviewer agreement signal. The 3 angle passes of ONE dimension finding the same issue is one dimension's own passes agreeing, NOT cross-dim convergence.

Therefore: **dedup the 3 angle passes of a dimension into a single per-dim finding set BEFORE Phase 3 computes cross-dim convergence.** The recall skeleton (§4) does this in-script, at its within-stage dedup step, so the per-dim set the orchestrator receives already collapses intra-dim duplicates. If this dedup is skipped, three angle passes of `bugs` finding the same defect would inflate its `convergence_count` to 3 on a single dimension's repeated output — suppressing the §3 escalation of a refuted verdict and tripping the Phase 5.3 pitfall auto-emit, both on agreement a single dimension manufactured with itself.

Intra-dim dedup match: same file + overlapping line range + same defect class. When 2 of 3 angle passes agree, keep the finding once (note `seen-in: 2/3 angles` in its body as a within-dim reliability signal — distinct from cross-dim `convergence_count`).

---

## 6. Fail-safe ladder

Degrade per the three rungs in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §5 — single-pass is the floor, degrade with a caveat, never a hard stop. Read it before handling a failure. Review's instantiation of rung 1: the `## Caveats` note reads `Deep review couldn't run the extra passes for the <reviewing|verifying> step — fell back to a single pass.` (map the `llm-spawn` phase → "reviewing", `stratify` → "verifying"), and the storage enum stays in the `## Errors` body entry (`phase: <llm-spawn|stratify>`, `error: deep-workflow-failed`, `consequence: single-pass-fallback`). Rung 3 applies per angle pass: a dimension whose angle pass fails still returns the union of the surviving passes — never drop the dimension.

---

## 7. Reporter-contract preservation inside the workflow

Every skill invariant binds inside every workflow step per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §6 — read-only agents, orchestrator-owned `atomic_state_write`, unchanged gates, no ship. Review's two specifics:

- **Action gate** — deep mode does not add or change the action-gate chain. The canonical 4 option labels bind unchanged, their chained sub-gates (the Post-mode drill, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.2; the include-deferred gate, §4.6) are part of the canonical chain rather than deep-mode variants, and the `report_status: final` precondition (§3.5 of the same reference) binds unchanged.
- **No-ship** — deep mode never pushes or fixes. The authored-test push carve-out (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §1) is the only sanctioned write, and it is independent of deep mode.

---

## 8. Edge cases

**`--deep` on a trivial diff.** Deep mode still runs (the user asked for it). The cost is real but bounded; the Action gate / triage-out of trivial files (size triage, `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §12) still applies, so a formatting-only diff is triaged out before the fan-out.

**`--deep` with test authoring approved at the Phase 4.3 gate.** Both apply: the angle-diverse / signal-gated fan-out AND failing-test authoring. The deep verification runs first (Phase 4.2); the test-gate (Phase 4.3) runs on the survivors of the gated verification, so authored tests target verified findings only — a strict improvement.

**Round-2+ re-run.** Prior-round findings feed the reviewer prompts as today. Depth is re-asked on a fresh re-run — via the §7 re-review gate (`${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §7) — because a fresh `/geniro:review` re-invocation never inherits the prior round's `deep_mode_choice`; only a compaction-resume of an in-flight run re-applies it. Passing `--deep` on the re-run pre-resolves depth to Deep as on any run.

**Workflow unavailable in the runtime** (SDK / cron with no Workflow tool). Fail-safe ladder rung 1 — run single-pass, note the caveat. Deep mode degrades to standard rather than erroring.

---

## 9. Anti-rationalization

The cross-skill rows — deep-mode-is-not-speed, the workflow wrapper does not suspend the contract, `agent({schema})` output, abstentions never demote, workflow error means degrade not abort, tier-pinning the voters, identical repeat passes — are in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §7 and bind here too. Review-specific:

| Your reasoning | Why it's wrong |
|---|---|
| "Three angle passes of the bugs dim all found it — that's convergence_count 3, treat it as corroborated." | The 3 angle passes of ONE dimension agreeing is that dimension agreeing with itself, not cross-dim convergence — and agreement among correlated samplers is the least informative kind. Dedup intra-dim BEFORE computing cross-dim convergence (§5), or deep mode feeds its own escalation predicate and the pitfall auto-emit a number it manufactured. |
| "Run one verifier per survivor in deep mode — the §4.1 gate already vetted them, that saves the most tokens." | The single-vote path is gated by signal, not blanket (§3): a first vote that fails the `_shared/deep-mode.md` §3 minimum bar, a `refuted` of a finding with `convergence_count >= 2`, or any `refuted` of a CRITICAL/HIGH finding escalates to the full 3. Blanket single-vote re-opens the single-hallucination flip the majority prevents. |
