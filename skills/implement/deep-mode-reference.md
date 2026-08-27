# Implement deep mode — reference

Implement-specific layers of the opt-in `--deep` quality mode. The cross-skill contract — activation pattern, the mandatory Workflow mitigations, the fail-safe ladder, and the shared anti-rationalization — lives in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md`; read it first. This file covers only what `/geniro:implement` deepens.

`--deep` raises the quality of two phases: it validates the spec's facts more reliably before the first edit (Phase 1 precision), and it finds + validates more self-review issues before shipping (Phase 3 recall + precision). It does not change the ship gate, the no-push-without-AUQ contract, or state-write ownership.

## Contents

- §1 — Activation
- §2 — Precision: Phase 1 spec fact-check (3× verify)
- §3 — Recall: Phase 3 self-review (3 angle-diverse passes per dimension)
- §4 — Precision: Phase 3 signal-gated verification before fix
- §5 — Interaction with the fix loop
- §6 — Workflow shape
- §7 — Fail-safe
- §8 — Anti-rationalization

---

## 1. Activation

`/geniro:implement --deep <task>` sets `deep-mode: true`. Semantic parse at the Phase 1 `$ARGUMENTS` parse (alongside `no-worktree` / `--no-adversarial`) — matches `--deep` / `deep` / `deep mode`. When `--deep` is absent, a depth question (Standard / Deep) folds into the Step 0 workspace AUQ as its own question per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §2 — no new standalone gate; on the auto-continue / resume paths where the Step 0 AUQ does not fire, depth falls back to flag-only (on resume, `deep-mode` was already persisted on the original run). Persist `deep-mode:` to state.md frontmatter and the activation to `approvals[]` category `deep_mode_choice`. When false (default), Phase 1 and Phase 3 run their standard single-pass paths and deep mode adds zero overhead.

## 2. Precision — Phase 1 spec fact-check (3× verify)

No implement-side logic is needed here — deep mode passes `DEEP: true` to the Step 12.5 spec-challenge. Phase 1 already invokes `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` with `MODE: implement` before the first Edit/Write; in deep mode add `DEEP: true`, and the helper runs each cited claim through 3 verifiers with majority aggregation (single-sourced in that file's §4 Deep-mode subsection — identical to plan's Phase 7.5 spec-check). The defects-found AskUserQuestion and the clean-pass silence are unchanged; deep mode only hardens the fact verification feeding them.

## 3. Recall — Phase 3 self-review (3 angle-diverse passes per dimension)

Standard Phase 3 Round 1 spawns one `reviewer-agent` per dimension in the `change_scope`-scaled grid (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-grid-scaling.md`) plus any custom dims, in one parallel batch. Deep mode replaces the Round-1 batch with a `Workflow(...)` that runs EACH dimension under 3 distinct angles and unions + dedups in-script:

- The declared dimension set is unchanged — the 3 angles are a multiplier on each declared dim, not a new dim. The edge-case test-authoring step stays a SINGLE pass: it already hunts edge cases exhaustively, and triple-running it would triple authored-test churn for little recall gain.
- For each dimension, spawn 3 independent `reviewer-agent` passes (parallel), each with the same context the single-pass spawn passes (diff, criteria paths, the dim's context slots), but each scoped to a DISTINCT angle so the passes search near-disjoint regions rather than re-running one identical prompt — **A common path** (likely defects on the typical code path), **B boundaries and error paths** (rare inputs, boundary conditions, exception/error handling, resource lifecycle, concurrency), **C interaction** (how the change couples with the rest of the diff and surrounding code — callers of changed symbols, sibling/parallel paths, flags and config). The angles are dimension-agnostic, so the angle instruction is a short prefix on the existing per-dim prompt — no per-dimension angle table to maintain.
- Union + dedup the 3 angle passes of one dimension into a single per-dim finding set BEFORE the fix loop consumes them — same file + overlapping line range + same defect class = one finding (note `seen-in: N/3 angles` as an intra-dim reliability signal). Dedup intra-dim so the 3 angle passes of one dimension agreeing is never mistaken for cross-dimension agreement.

## 4. Precision — Phase 3 signal-gated verification before fix

Standard Phase 3 routes every Round-1 finding straight into the fix loop. Deep mode inserts a verification gate BEFORE the fix so the implementer doesn't spend fix-loop rounds on a hallucinated defect — but the vote count is **gated by signal**: one verifier on the clear majority, the full 3-vote majority only on contested or high-stakes findings.

- **First vote (always).** Run ONE independent verifier (`finding-verifier-agent`) on the deduped finding — the degenerate one-finding cluster input of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2, raw JSON parsed defensively. `confirmed`/`clarified` = "real", `refuted` = "drop".
- **Escalate to 3** (then majority) when ANY of:
  - the first vote fails the minimum bar in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3 (abstained, or `confidence <= 3`);
  - the finding is CRITICAL or HIGH — a code fix to a high-stakes finding should clear the full majority in EITHER direction, because in a mutation skill both a wrong fix (false-confirm → an edit the code didn't need) and a dropped real defect (false-refute → ships with the bug) are costly;
  - the first vote is `refuted` AND `seen-in >= 2/3` angles — the refute contradicts the within-dim corroboration that surfaced it.
- **Accept the single vote** otherwise: a high-confidence first vote on a MEDIUM-or-lower finding that agrees with the corroboration — a `confirmed`/`clarified`, or a `refuted` of a lone (`seen-in: 1/3`) finding.
- **Majority when escalated:** ≥2 "drop" → the finding is demoted out of the fix set (recorded in state.md, not fixed); otherwise it enters the fix loop with the majority `recommended_action`.
- Parse-fail = abstain; a first-vote abstention triggers escalation; quorum < 2 → one fresh single-pass verifier for that finding (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §5).

**Why signal-gating fits a mutation skill:** a single verifier can hallucinate in either direction, and in implement BOTH are costly — a false-confirm authorizes an unneeded edit, a false-refute ships a real bug. So high-stakes findings (CRITICAL/HIGH) always take the full majority, while the MEDIUM-and-lower bulk — high-confidence and corroborated — settles at one vote. This mirrors `/geniro:review --deep`, tightened for the fix loop: review accepts a single high-stakes confirm (its findings are only reported); implement escalates high-stakes findings in both directions (its findings are fixed). Both still demote a refuted finding before acting on it — review to `## Filtered`, implement out of the fix set.

## 5. Interaction with the fix loop

Deep cost is front-loaded on Round 1 discovery + verification. The bounded fix loop (rounds 2-3, dims with actionable findings only — a minor-only dim counts as clean) re-spawns SINGLE-pass — re-running the deep fan-out every round would multiply the loop cost for diminishing returns, since Round 1's deep pass already established the verified finding set and a later round only re-checks whether the applied fixes hold. The `test-runner-agent` behavior and the edge-case test-authoring step are unchanged across rounds. Round 4 entry stays forbidden (escalate-AUQ) exactly as in standard mode.

## 6. Workflow shape

One script, two phases (recall then verify). Both fan-outs instantiate the canonical script skeletons in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3 "Script skeletons", and apply every mandatory Workflow mitigation in that file's §4 — each one prevents an observed failure, so read them before writing the script.

Implement supplies these pieces:

- **Recall phase.** The stage set is the declared Phase 3 dimension set (the `change_scope`-scaled grid, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-grid-scaling.md`), run under the three angles named in §3 above. Dedup key: same file + overlapping line range + same defect class, with the within-dim tally carried as `seen-in: N/3 angles`.
- **Verify phase.** The candidates are the flattened per-dim findings the recall phase returned, and the survivors (`verdict !== 'refuted'`) enter the fix loop. Its escalation predicate, per §4:

```
// needsEscalation(first, f) = deep-mode.md §3 minimum (abstained OR confidence <= 3)
//   OR f.severity === 'CRITICAL' OR f.severity === 'HIGH'
//   OR (first.validation === 'refuted' && f.seen_in >= 2)
```

Every reviewer/verifier prompt re-asserts the read-only contract (no Edit/Write/git/gh; the orchestrator owns every `atomic_state_write` and all fixes), per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §6 — the workflow finds and verifies, the orchestrator fixes. OMIT `model=` at every spawn by default, or pass `model="<tier>"` at every spawn — including inside this workflow — when the run carries `--subagent-model` (`${CLAUDE_PLUGIN_ROOT}/skills/implement/operations-reference.md` §Subagent model tiering); that is the user's own election for the run, not the cheaper-tier shortcut the workflow mitigation guards against.

## 7. Fail-safe

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §5 — the standard single-pass Phase 3 batch and the single-pass spec-challenge are the floor. A workflow error / unparseable aggregate / agent-registration failure degrades to the standard single-pass path for that stage with a plain-English caveat (`Deep mode couldn't run the extra self-review passes — fell back to a single pass.`). Never a hard stop; a shallower self-review is still a valid pre-ship gate.

## 8. Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "Three angle passes of the bugs dim all found it — that's cross-reviewer convergence, weight it high." | The 3 angle passes of ONE dimension agreeing is that dimension agreeing with itself, not cross-dimension agreement. Dedup intra-dim into a single finding (with `seen-in: N/3 angles`) BEFORE any convergence/priority signal (§3), or deep mode inflates its own signal on one dimension's repeated output. |
| "Re-run each dim's prompt 3× identically for recall." | Identical passes only scatter by sampling temperature — high overlap, heavy dedup churn, low marginal recall. Scope each pass to a distinct angle (common-path / boundaries-and-errors / interaction) so each buys new territory at the same cost; cross-angle agreement is also a stronger within-dim signal than identical clones (§3). |
| "Deep mode is on, so run the fix loop 3× every round too." | Deep cost is front-loaded on Round 1 (§5). Rounds 2-3 re-check whether the applied fixes hold — single-pass is sufficient there, and re-running the deep fan-out per round would multiply the loop cost for diminishing returns. |
| "Skip verification — if the angle passes surfaced a finding, just fix it." | The angle passes raise recall (find more); verification raises precision (avoid fixing a hallucinated defect) — different levers. Every finding still gets at least one verifier before the fix, and contested or high-stakes findings get the full 3-vote majority (§4). Fixing a false positive wastes a round and can introduce a regression. |
| "Run one verifier on every finding to save tokens." | The single-vote path is gated, not blanket (§4): a low-confidence first vote, ANY CRITICAL/HIGH finding, or a refute contradicting `seen-in >= 2/3` escalates to the full 3. In a mutation skill both a wrong fix and a dropped real bug are costly, so high-stakes findings always take the majority — one vote is accepted only for the corroborated MEDIUM-and-lower bulk. |
| "Multiply the edge-case test-authoring step 3× too, for parity with the reviewer dims." | The step already hunts edge cases exhaustively and AUTHORS tests inline; tripling it triples authored-test churn for little recall gain. Deep mode multiplies the reviewer dimensions and the verifier votes, and keeps the edge-case step a single pass (§3). |
| "I'm in the deep Workflow now, so I can let the agents apply the fixes in parallel." | The workflow agents are read-only — they find and verify only. The orchestrator owns every fix and every `atomic_state_write` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §6). Parallel agents editing source is exactly the boundary the wrapper tempts you to drop. |
