# Implement deep mode — reference

Implement-specific layers of the opt-in `--deep` quality mode. The cross-skill contract — activation pattern, the mandatory Workflow mitigations, the fail-safe ladder, and the shared anti-rationalization — lives in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md`; read it first. This file covers only what `/geniro:implement` deepens.

`--deep` raises the quality of two phases: it validates the spec's facts more reliably before the first edit (Phase 1 precision), and it finds + validates more self-review issues before shipping (Phase 3 recall + precision). It does not change the ship gate, the no-push-without-AUQ contract, or state-write ownership.

## Contents

- §1 — Activation
- §2 — Precision: Phase 1 spec fact-check (3× verify)
- §3 — Recall: Phase 3 self-review (3× passes per dimension)
- §4 — Precision: Phase 3 finding verification (3-vote before fix)
- §5 — Interaction with the fix loop
- §6 — Workflow shape
- §7 — Fail-safe
- §8 — Anti-rationalization

---

## 1. Activation

`/geniro:implement --deep <task>` sets `deep-mode: true`. Semantic parse at the Phase 1 `$ARGUMENTS` parse (alongside `no-worktree` / `--no-adversarial`) — matches `--deep` / `deep` / `deep mode`. Implement has no posting-mode AUQ to fold a chooser into (Step 0 is workspace-only), so deep mode is flag-only per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §2. Persist `deep-mode:` to state.md frontmatter and the activation to `approvals[]` category `deep_mode_choice`. When false (default), Phase 1 and Phase 3 run their standard single-pass paths and deep mode adds zero overhead.

## 2. Precision — Phase 1 spec fact-check (3× verify)

No implement-side logic is needed here — deep mode passes `DEEP: true` to the Step 12.5 spec-challenge. Phase 1 already invokes `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` with `MODE: implement` before the first Edit/Write; in deep mode add `DEEP: true`, and the helper runs each cited claim through 3 verifiers with majority aggregation (single-sourced in that file's §4 Deep-mode subsection — identical to plan's Phase 7.5 spec-check). The defects-found AskUserQuestion and the clean-pass silence are unchanged; deep mode only hardens the fact verification feeding them.

## 3. Recall — Phase 3 self-review (3× passes per dimension)

Standard Phase 3 Round 1 spawns one `reviewer-agent` per dimension (bugs / security / architecture / tests / code-quality + any custom dims) in one parallel batch. Deep mode replaces the Round-1 batch with a `Workflow(...)` that runs EACH dimension 3× and unions + dedups in-script:

- The declared dimension set is unchanged — 3× is a multiplier on each declared dim, not a new dim. The `adversarial-tester-agent` stays a SINGLE spawn: it already hunts edge cases exhaustively, and triple-running test authoring would triple authored-test churn for little recall gain.
- For each dimension, spawn 3 independent `reviewer-agent` passes (parallel), each with the same pre-inlined context the single-pass spawn uses (diff, criteria, the dim's context slots).
- Union + dedup the 3 passes of one dimension into a single per-dim finding set BEFORE the fix loop consumes them — same file + overlapping line range + same defect class = one finding (note `seen-in: N/3 passes` as an intra-dim reliability signal). Dedup intra-dim so three passes of one reviewer agreeing with itself is never mistaken for cross-dimension agreement.

**Why 3× raises recall:** a single reviewer pass is non-deterministic and surfaces a subset of its dimension's issues; three independent passes surface overlapping-but-different subsets whose union catches what any one missed — the same recall lever as `/geniro:review --deep`.

## 4. Precision — Phase 3 finding verification (3-vote before fix)

Standard Phase 3 routes every Round-1 finding straight into the fix loop. Deep mode inserts a verification gate BEFORE the fix so the implementer doesn't spend fix-loop rounds on a hallucinated defect: each deduped finding gets **3 independent verifiers** (`reviewer-agent` verify-finding mode), majority-aggregated:

- `confirmed` + `clarified` = "real" votes, `refuted` = "drop" votes. ≥2 "drop" → the finding is demoted out of the fix set (recorded in state.md, not fixed); otherwise it enters the fix loop with the majority `recommended_action`.
- Parse-fail = abstain; quorum < 2 → one fresh single-pass verifier for that finding (deep-mode.md §5).

This mirrors `/geniro:review --deep` precision, adapted to a mutation skill: review demotes a refuted finding to `## Filtered`; implement demotes it out of the fix set. Both prevent acting on a false positive.

## 5. Interaction with the fix loop

Deep cost is front-loaded on Round 1 discovery + verification. The bounded fix loop (rounds 2-3, failing dims only) re-spawns SINGLE-pass — re-running 3× every round would triple the loop cost for diminishing returns, since Round 1's 3× already established the verified finding set and a later round only re-checks whether the applied fixes hold. The `test-runner-agent` and `adversarial-tester-agent` behavior is unchanged across rounds. Round 4 entry stays forbidden (escalate-AUQ) exactly as in standard mode.

## 6. Workflow shape

One script, two phases (recall then verify). Build path/context strings as plain constants before any backtick template literal (deep-mode.md §4, path-constants mitigation). Return raw JSON text and parse defensively — never `agent({schema})`.

```
phase('Deep self-review — 3x passes')
const perDim = await pipeline(
  DIMENSIONS,                                          // the declared Phase 3 dim set (minus adversarial)
  d => parallel([0,1,2].map(i => () =>
    agent(reviewerPrompt(d, i, diffCtx), { label: `${d.slug}:pass${i}`, phase: 'Deep self-review — 3x passes' }))),
  (threePasses, d) => dedupeWithinDim(threePasses, d)  // union + dedup IN-SCRIPT → one per-dim finding set
)
const findings = perDim.flat().filter(Boolean)

phase('Deep verify — 3-vote')
const verified = await parallel(findings.map(f => () =>
  parallel([0,1,2].map(i => () => agent(verifierPrompt(f, i), { label: `verify:${f.id}:v${i}`, phase: 'Deep verify — 3-vote' })))
    .then(votes => ({ ...f, verdict: majority(votes) }))   // majority() parses raw JSON; parse-fail = abstain
))
return verified.filter(v => v.verdict !== 'refuted')       // survivors enter the fix loop
```

Every reviewer/verifier prompt re-asserts the read-only contract (no Edit/Write/git/gh; the orchestrator owns every `atomic_state_write` and all fixes), per deep-mode.md §6 — the workflow finds and verifies, the orchestrator fixes. OMIT `model=` at every spawn.

## 7. Fail-safe

Per deep-mode.md §5 — the standard single-pass Phase 3 batch and the single-pass spec-challenge are the floor. A workflow error / unparseable aggregate / agent-registration failure degrades to the standard single-pass path for that stage with a plain-English caveat (`Deep mode couldn't run the extra self-review passes — fell back to a single pass.`). Never a hard stop; a shallower self-review is still a valid pre-ship gate.

## 8. Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "Three passes of the bugs dim all found it — that's cross-reviewer convergence, weight it high." | Three passes of ONE dimension is one reviewer agreeing with itself, not cross-dimension agreement. Dedup intra-dim into a single finding BEFORE any convergence/priority signal (§3), or deep mode inflates its own signal on a single reviewer's repeated output. |
| "Deep mode is on, so run the fix loop 3× every round too." | Deep cost is front-loaded on Round 1 (§5). Rounds 2-3 re-check whether the applied fixes hold — single-pass is sufficient there, and 3× per round would triple the loop cost for diminishing returns. |
| "Skip the 3-vote — if three passes surfaced a finding, just fix it." | The 3× passes raise recall (find more); the 3-vote raises precision (avoid fixing a hallucinated defect). They are different levers. A finding surfaced by the recall passes still gets majority-verified before it enters the fix set — fixing a false positive wastes a round and can introduce a regression. |
| "Multiply the adversarial-tester 3× too, for parity with the reviewer dims." | The adversarial-tester already hunts edge cases exhaustively and AUTHORS tests; tripling it triples authored-test churn for little recall gain. Deep mode multiplies the reviewer dimensions and the verifier votes, and keeps the adversarial-tester a single spawn (§3). |
| "I'm in the deep Workflow now, so I can let the agents apply the fixes in parallel." | The workflow agents are read-only — they find and verify only. The orchestrator owns every fix and every `atomic_state_write` (deep-mode.md §6). Parallel agents editing source is exactly the boundary the wrapper tempts you to drop. |
