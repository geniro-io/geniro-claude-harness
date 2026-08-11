# /geniro:review Phase 4.2 — Per-finding empirical-reproduction verifier

Every finding surviving Phase 4.1 — CRITICAL, HIGH, and MEDIUM, with no tier-scaling or severity-scaling — gets one independent verdict from a fresh `finding-verifier-agent` spawn, same-file survivors clustered into one spawn (§4) and each verifier reading only its own cluster's cited code, caller grep, and sibling tests to prevent anchoring. A finding with no explicit line number slices the cited file from its first referenced symbol instead, noting the reconstruction in the verdict; the two sentinel-`File` dimensions (`SPEC-COMPLIANCE` / `PR-METADATA`) verify against the diff instead of a code slice (§2). A thinly-cited CRITICAL or HIGH may still be admitted at §4.1 — supplying the missing quote is this verifier's job, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5.

## Contents

- §1 — When this fires
- §2 — Input contract (what each verifier receives)
- §3 — Output contract (verifier emits)
- §3.5 — Resolve embedded "confirm / verify" asks
- §3.6 — Actionability bar (reachable + behavior delta required for `confirmed`)
- §4 — Spawn batch shape (canonical home of the same-file cluster cap)
- §4.5 — Verifier-never-ran fail-open (orchestrator-assigned `unverified`)
- §5 — Result aggregation and demotion rules
- §6 — Anti-rationalization

---

## 1. When this fires

After the Phase 4.1 multi-signal threshold gate — both its severity-gated Path A and its decision-type Path B, specified in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5, which owns the admission signals and their thresholds. Fires BEFORE the Phase 4.3 test-confirmation gate and Phase 5 stratification.

The verified set is every kept finding at CRITICAL / HIGH / MEDIUM, whichever path admitted it: a Path-B `PRODUCT-DECISION` at MEDIUM or higher verifies against its own `File: path:lines` anchor like any Path-A survivor, because the handoff schema makes the verification fields mandatory at those severities. LOW is the only severity that skips — a trade-off at LOW is not a defect-to-confirm, and it carries no verification fields downstream.

Skip condition: ONLY when that set is empty. Never skip based on tier — every CRITICAL / HIGH / MEDIUM survivor gets a verifier. Mechanical-origin findings (a deterministic scan's hits, e.g. the secret scan) verify like any other survivor: a regex cannot tell a live credential from a test fixture, and that judgment is precisely what the verifier supplies.

---

## 2. Input contract per verifier

Each verifier spawn receives ONLY:

- The finding bodies of ONE cluster — the co-located findings citing the same file (cluster cap per §4), each with its full body (title / file:line / severity / decision-type / confidence / evidence / suggested-fix / why-matters). A single finding is the degenerate one-finding cluster; /geniro:resolve clusters its same-file comment items the same way, and spec-challenge always passes one.
- The cited code slice — orchestrator reads the cited file ONCE per cluster, extracting each member's `line ± 30` window (overlapping windows merge into one range), and inlines into the prompt.
- 1-hop caller grep results — orchestrator runs `grep -rn "<symbol>" --include="*.<ext>"` for each member's key symbol; pipe results capped at 50 lines per member (when members share a symbol, one merged grep serves them).
- 1-2 sibling test references per member symbol — orchestrator greps test directories (`test/`, `tests/`, `__tests__/`, `spec/`); capped at 20 lines per member.

When the finding's body asks the author to confirm something about ANOTHER file, symbol, or migration (a "confirm X" / "verify Y" claim), the orchestrator also includes the evidence needed to check it — the PR's changed-file list (`git diff --name-only <base>...HEAD`), `git log --oneline -- <cited-path>`, or the relevant grep — so the verifier can resolve the claim rather than pass it through. See §3.5. When the finding's risk depends on a feature flag / gate / role / config branch, the orchestrator also includes the current config state (the flag's default value, the gate's condition) so the verifier can apply the §3.6 actionability bar.

**Path-less sentinel findings (`File: SPEC-COMPLIANCE` / `File: PR-METADATA`).** A finding whose `File:` field is a sentinel string carries no code `path:line`, so the cited-code-slice bullet above does not apply — there is nothing at `<sentinel> ± 30 lines`. For these, the orchestrator supplies instead: the finding's `Evidence:` (which quotes the spec/PR fragment verbatim), the PR's changed-file list (`git diff --name-only <base>...HEAD`), and any real code `file:line` embedded in the Evidence (a spec-defect finding cites the code that contradicts the spec premise — read it ± 30 lines). The verifier judges the claim against the diff + cited fragment: "is the scoped item actually absent from the changed files?" for a code-omission finding, or "does the cited code actually contradict the spec premise?" for a spec-defect finding. For an omission finding, `git diff --name-only` confirms the named artifact's presence or absence — the right granularity for an omission claim; it does not validate the artifact's content, which a code-anchored dimension would have flagged with its own `file:line`. The `confirmed` / `refuted` / `clarified` semantics, the §3.6 actionability bar, and the anti-sycophancy guard are unchanged. Sentinel findings never cluster — each gets its own spawn (they verify against the diff, so there is no shared file slice to amortize).

Each verifier does NOT receive:

- Findings outside its own cluster.
- The full reviewer-agent bundle output.
- The orchestrator's prior reasoning.
- Information about which dimension originated the finding (avoids anchoring on the originating reviewer's framing).

Rationale — the isolation boundary is two-part. The load-bearing isolation is from the ORIGINATING reviewer's framing (bundle, dimension, orchestrator reasoning): a verifier that never sees it re-reads the cited code cold and judges each finding on its own merits, which is what keeps the verification honest. Cluster siblings share only co-location on the cited file, and each is judged independently — a sibling's verdict is never evidence for another finding, because cross-item anchoring is the documented failure mode of batched judgment.

---

## 3. Output contract per verifier

The verifier emits one structured verdict block PER finding in its cluster, in the order received, each headed by the finding's `file:line — <title>` verbatim (never by batch position or index; a path-less sentinel finding heads its block with the `File` sentinel — title instead):

```yaml
validation: confirmed | refuted | clarified   # a fourth value, unverified, exists but is orchestrator-assigned (§4.5) — a verifier never emits it
recommended_action: fix-now | testable | product-decision | intent-check | drop
confidence: 1 | 2 | 3 | 4 | 5
evidence: "<exact quote from cited file:line OR caller chain that confirms/refutes>"
```

A single-finding spawn therefore emits exactly one block — the shape cross-skill callers already consume.

Field semantics:

- `validation: confirmed` — the cited code exhibits the defect AND the defect is actionable (§3.6); original decision-type stands.
- `validation: refuted` — EITHER the cited code does not exhibit the claimed defect (verifier read the file and disagrees), OR the defect exists but is not actionable (§3.6 — unreachable under current config, or a normal/safe pattern with no behavior delta).
- `validation: clarified` — the finding is correct but the recommended action differs from the original reviewer's; verifier's `recommended_action` overrides.
- `validation: unverified` — orchestrator-assigned only (§4.5: a failed spawn, or a deliberate skip), never emitted by a verifier.
- `recommended_action` reuses the plugin's existing 4-way taxonomy (fix-now / testable / product-decision / intent-check) plus `drop` for refuted findings.
- `confidence` 1-5 coarse scale: 1 = 'low — could be wrong', 5 = 'certain — direct evidence'.
- `evidence` must be a literal quote from the cited file or caller chain. "I agree" / "looks correct" / paraphrases are insufficient — refuse the output and re-prompt the verifier.

---

## 3.5 Resolve embedded "confirm / verify" asks

Some findings — most often migration, regression, or scope findings — phrase part of their body as a request for the author to confirm something checkable. The verifier resolves that check itself rather than letting the "confirm X" reach the PR; the doctrine behind it is `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §4. The mechanism:

- The orchestrator supplies the needed evidence in the verifier prompt (§2): the PR changed-file list, `git log` for the cited path, or the caller grep already gathered.
- The verifier checks the claim and rewrites the finding body to state the verified fact — e.g. "Both migrations are in this PR's diff; combining the add and drop is safe" or "Migration X is NOT in this diff — the drop is unsafe against an older revision" — emitted as `validation: clarified` so the orchestrator replaces the "confirm X" phrasing with the resolved result.
- Only a genuinely unverifiable residue stays as a human-facing note — e.g. whether a migration was deployed to an environment independently, which is not recorded in git. Narrow the finding to just that residue and tag it `[INTENT-CHECK]`.

The verifier never leaves a checkable "confirm X" in a finding that will be posted.

---

## 3.6 Actionability bar — a pattern is not a defect until it can change an outcome

`confirmed` requires more than the defect existing in the code. There must be a concrete path, reachable under the CURRENT production configuration (feature flags, gates, env, role), where the change produces a wrong or different outcome than before the PR. A real code pattern that cannot change any outcome — because the gating flag is OFF, the branch is dead, or it merely describes the normal/safe shape of the code — is NOT a confirmed finding.

This is the calibration `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` already demands ("hypothetical risk without a documented trigger" excluded from CRITICAL; "the edge case must be reachable" for MEDIUM) — the verifier is where it gets enforced, automatically, on every finding rather than only when a human asks.

- For any finding whose risk depends on a flag / gate / role / config branch, the orchestrator includes the current config state in the verifier prompt (§2) and the verifier asks the decisive question: "with that gate in its CURRENT production state, can this change produce a different value or behavior than before the PR?"
- When the pattern exists but no actionable path does, emit `validation: refuted`, `recommended_action: drop`, and an `evidence` line stating the reachability result (e.g. `flag useCheckoutV2 OFF in prod → the new V2 write block is unreachable; normalizeStatus(null)==='none'==pre-PR → zero delta`). The orchestrator files it under `## Filtered` with reason `not-actionable`.
- Reason from the code and config, NOT from the finding's framing. A confident reviewer description of a real pattern is not evidence that the pattern is reachable.

**Parity test for effect-claims.** When a finding's impact claim has the shape "X newly enters / newly triggers path P" (dispatch, digest, notification, fanout, billing — any effect-claim), check whether P was already reachable with the same inputs BEFORE the PR — grep the pre-existing callers / columns / predicates that feed P. If an existing path already produces the claimed effect, the delta is overstated: emit `refuted` (zero-delta), or `clarified` with the impact framing downgraded when a genuine residual delta remains. Either way, `evidence` must quote the pre-existing path (file:line) — the same literal-quote standard as the rest of this bar.

A non-actionable finding is always `refuted` (`not-actionable`), never `clarified` — `clarified` presupposes the finding is actionable and merely needs a different recommended action, so it must not be the escape hatch for a finding that should be dropped.

A real server-side pattern that is unreachable under the production flag state is exactly what this bar refutes without the user having to prompt a re-check.

---

## 4. Spawn batch shape

**Cluster cap — at most 3 findings per verifier spawn. This section is the cap's canonical home; every other site cites it rather than restating the number.** Three is where two opposing pressures balance: co-locating same-file survivors amortizes one file read and one caller grep across several verdicts, while every extra body in a spawn widens the cross-item anchoring surface the §2 isolation contract exists to narrow — past three, a verdict is materially more likely to rest on a sibling's framing than on its own literal quote. A solo survivor is the degenerate one-finding cluster; a sentinel-`File` survivor never clusters at all, because it verifies against the diff and has no shared file slice to amortize.

Orchestrator-side (in /geniro:review Phase 4.2):

```
Group non-sentinel §4.1 survivors by cited file path; split any group larger than the
cluster cap into clusters at the cap.
A sentinel-File survivor (SPEC-COMPLIANCE / PR-METADATA) never clusters — compose its
spawn per §2's path-less bullet (finding body + `git diff --name-only <base>...HEAD`
+ any real code file:line embedded in its evidence, sliced at the §2 width when present);
add to the same parallel-spawn batch.

For each cluster:
  1. Read the cited file ONCE, extracting each member's slice window per the §2 caps
     (merge overlaps).
  2. Run `grep -rn "<key symbol from member.evidence>" --include="*.<ext>"` per member,
     capped per §2 (one merged grep when members share the symbol).
  3. Run `grep -rn "<symbol>" test/ tests/ __tests__/ spec/` per member, capped per §2.
  4. Compose ONE verifier spawn: all member finding bodies + the shared slice + grep
     outputs; instruct one verdict block per finding, keyed by file:line + title.
  5. Add to parallel-spawn batch.

After loop:
  Send the accumulated batch (the invariant below governs how).
  - Use `Agent(subagent_type="geniro:finding-verifier-agent", ...)` per the ladder in
    `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`.
  - OMIT `model=` (orchestrator tier inherits via frontmatter `model: inherit`) per
    `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`.
```

Critical: ALL verifier spawns fire in ONE assistant response, same assistant turn, NOT one per turn. Separate turns serialize execution and double wall-time; the canonical parallel-spawn invariant applies.

**Deep mode (`deep-mode: true`).** Clustering applies only in standard mode; deep mode verifies each survivor individually inside a `Workflow(...)` with signal-gated verification — one verifier, escalating to a 3-vote 2/3 majority only where the verdict is contested or high-stakes. The escalation contract, the abstain rule, and the quorum fail-safe are canonical at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3 (precision layer); the consuming skill's own deep-mode reference names the concrete thresholds that instantiate them. The per-verifier input (§2), output (§3), and actionability bar (§3.6) are identical; persist the final verdict to the existing `Validation` field and the vote path to `Verification-evidence` (no schema bump).

---

## 4.5 Verifier-never-ran fail-open

A §4.1 survivor can reach Phase 5 with no verdict two ways: the spawn fails — errors out even after the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`, or returns output with no parseable `validation:` value after the one empty-result retry (inherit tier) — or the orchestrator never spawns one at all, the §6 context-budget rationalization this table exists to confront. Either way the finding lands in none of the §3 outcome buckets, and an unmarked `Validation:` would read as `confirmed` to every consumer via the legacy back-compat rule — masking "nobody checked this" as "this was checked" regardless of cause. The orchestrator instead assigns an explicit disposition, the two causes distinguished only by the `Verification-evidence:` string — a failed cluster spawn (after the ladder + one retry) assigns its string to EVERY finding in that cluster:

- `Validation: unverified`, `Verification-confidence: 1`, `Recommended-action` mirroring the finding's original Decision Type, `Verification-evidence:` naming the cause verbatim — `"verifier did not run — spawn failed after retry"` for a tooling failure, `"verifier not spawned — orchestrator elected to skip verification"` for a deliberate skip.
- The finding stays kept — fail-open, mirroring the Phase 1.5 mechanical pre-pass and Phase 4.3 test-gate doctrine: neither cause deletes a finding the reviewers already paid for.
- It is excluded from any PR post set and surfaced under `## Caveats`: "N findings could not be independently verified — the verifier never ran for them; they are kept in the report but will not be posted to the PR."
- Write a state.md `## Errors` entry via `atomic_state_write`: `phase: stratify`, `error: verifier-spawn-failed` (or `verifier-spawn-skipped` for a deliberate skip), plus the affected finding IDs.

Do not fall back to `spawn-agent.md`'s generic inline-author terminal step for a verifier spawn — the orchestrator holds the full reviewer bundle, which is exactly the anchoring context the §2 isolation contract forbids, so an inline self-check would be an anchored confirmation, not a verification. `unverified` states the truth instead: this finding was never independently checked, and the evidence string says why.

`unverified` is orchestrator-assigned only — a verifier agent never emits it. Consumer-side semantics (legal since `m6-v2`; kept, not postable, one-line warning) live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md`, unaffected by which cause applied.

---

## 5. Result aggregation and demotion rules

After all verifiers return, the orchestrator processes each finding's verdict block by the same rules:

1. **`validation: refuted`** — move the finding to the report's `## Filtered` section with reason `refuted-by-verifier` (or `not-actionable` when the verifier refuted on the §3.6 actionability bar — the defect was real but unreachable / no behavior delta). Do NOT propagate to Phase 4.3 test-confirmation gate or Phase 5 stratify. Do NOT include in the handoff `## Findings` body. This keeps refuted findings out of `open_questions[]` and leaves the consumer-side handoff resolution gate (read by /geniro:implement) unchanged. At CRITICAL and HIGH the demotion waits on the guard below.

   **High-stakes refutation guard — one vote never drops a CRITICAL or HIGH.** A `refuted` verdict at those severities does not demote the finding by itself. Collect every high-stakes refutation the first batch produced and fire one more independent verifier per finding — the degenerate one-finding cluster of §2, composed fresh from the code, never shown the first verdict, since a second reader handed the first refutation is anchoring rather than verifying — as ONE parallel batch, same invariant as the first. Demote only when the second verdict is also `refuted`. On `confirmed`, `clarified`, or a spawn failure the finding stays kept, carrying a `Verification-evidence` note that records the split (`2-vote: 1 refuted / 1 confirmed → kept`) so the disagreement reaches the reader rather than being averaged away.

   The asymmetry is deliberate, and it tracks which error costs more. Admission at CRITICAL / HIGH is now severity alone (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5), so this verifier is the only thing standing between a reviewer's claim and the report — and the documented failure mode of an LLM defect-filter is over-refutation, dropping real bugs. A wrongly dropped CRITICAL leaves the user nothing to see; a wrongly kept one reaches a report the user reads and can dismiss. MEDIUM demotes on the single verdict — the second spawn does not earn its cost at that stake. Deep mode already enforces this through its 3-vote escalation predicate, so a deep-mode run satisfies the guard there and does not re-run it here.
2. **`validation: clarified`** — update the finding's `Decision Type:` to match the verifier's `recommended_action`. Append verifier `confidence` and `evidence` to the finding body. Keep finding in active set. When the verifier resolved an embedded "confirm X" ask (§3.5), replace that phrasing in the finding body with the verified result it returned — the posted finding states the fact, never the un-run check.
3. **`validation: confirmed`** — append verifier `confidence` and `evidence` to the finding body. Keep finding in active set (decision-type unchanged).
4. **State-file persistence** — write `validation`, `recommended_action`, `verification_confidence`, `verification_evidence` to the per-finding body schema in `review-handoff.md`.

---

## 6. Anti-rationalization

| Reasoning the verifier (or orchestrator) might generate | Why that's wrong |
|---|---|
| "The original reviewer is usually right — confirm to maintain coherence." | Agreeing to stay coherent with the original reviewer is the documented multi-judge failure mode. Re-read the cited code; if the defect is not visible in the quote, mark refuted. Coherence is not a verification signal. |
| "Skip the caller grep — the finding cites `file:line`, that's enough." | The cited `file:line` is the reviewer's claim. Without grepping callers, impact cannot be refuted or confirmed. Read the call sites before emitting. |
| "Pass the full reviewer bundle to each verifier so they have full context." | Shared context anchors verifiers toward agreement — they read the original framing instead of the code. Each verifier sees ONLY its cluster's finding bodies plus cited slice plus caller grep. Independence is load-bearing. The sanctioned cluster — co-located finding bodies citing the same file, at the §4 cap — is not the forbidden bundle, which is the originating reviewer's full output and framing. |
| "Sibling finding #1 in this cluster is confirmed, so #2 in the same file is probably real too." | Cross-item anchoring is the documented failure mode of batched judgment — a verdict must rest on its own literal quote from the cited code, not on a sibling's verdict. Confirm/refute each finding as if it were the only one in the spawn. |
| "Verifier confidence:1 — silently demote severity to MEDIUM instead of refuting." | `confidence: 1` with no contradicting evidence means the verifier is uncertain; emit `validation: clarified, confidence: 1` and let the orchestrator decide. Silently demoting severity hides the uncertainty from the consumer. |
| "Skip or sample verification for some subset — top-N by impact, CRITICALs (reliable by definition), MEDIUMs (paper cuts, overkill), or 'I've already spent substantial context — the user needs a prioritized report more than more verifier spawns.'" | The verifier explicitly drops tier-scaling AND severity-scaling — every §4.1 survivor gets verified regardless of severity. Sampling reintroduces the failure mode empirical reproduction exists to eliminate: wall-time is ~max(spawn-time) regardless of N (parallel-spawn invariant), and token cost is bounded by the §4.1 gate (an Evidence-Block required at MEDIUM) plus file-clustering (co-located survivors share one spawn) — a high finding count signals tightening Phase 4.1, not under-verifying. CRITICAL is admitted on severity alone, with no Evidence-Block required, so skipping it is sycophancy at maximum stake: a confirmed-without-evidence CRITICAL lands on the PR, gates `/geniro:implement` Phase 1, and surfaces to the user as load-bearing. A MEDIUM that survives §4.1 already carries an Evidence-Block worth re-reading — skipping it risks exactly the false positive `## Filtered` exists to hold back. Verify every survivor at every severity. Running low on context is not license to under-verify silently: if a spawn genuinely cannot fire this run, say so — mark the remainder `Validation: unverified` with the §4.5 skip-cause evidence string, never a bare field the back-compat rule reads as `confirmed`. A prioritized report built on unchecked findings is indistinguishable from a checked one until an unmarked finding turns out wrong. |
| "The first verifier refuted this CRITICAL with a literal quote — a second spawn is waste." | The quote shows the verifier read something, not that it read correctly, and a confident well-quoted dismissal of a real defect is precisely the shape over-refutation takes. Since admission at CRITICAL / HIGH is severity alone, this step decides those findings by itself — the guard is the only check on it, and it costs one spawn across the small subset that is both high-stakes and refuted. Fire the second verifier (§5 rule 1). |
| "The finding's `suggested-fix:` reads sensible — confirm without re-reading code." | The suggested-fix being sensible is independent of whether the defect exists. Verification reads the cited code AND the caller grep; the suggested-fix is not evidence of the defect. |
| "The cited pattern is real, so confirm it." | Existence is not actionability (§3.6). Ask: with the gating flag / gate / role in its CURRENT production state, does this change produce a different outcome than before the PR? If the path is unreachable or the value equals pre-PR, it is noise — refute it (`not-actionable`). A real-but-unreachable finding posted to the PR is the false positive this bar exists to kill. |
| "The fanout/handler is new code, so its effects are new — confirmed." | New code ≠ new effect. Parity-check the EFFECT: if a pre-existing path already produced the same downstream outcome with the same inputs, the finding's impact claim is overstated — quote that path and refute or downgrade. |

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — agent registration ladder.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — OMIT `model=` rule.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` — handoff schema consumer.
- `${CLAUDE_PLUGIN_ROOT}/agents/finding-verifier-agent.md` — the agent this contract spawns.
