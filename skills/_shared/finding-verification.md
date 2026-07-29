# /geniro:review Phase 4.2 — Per-finding empirical-reproduction verifier

Every finding surviving Phase 4.1 — CRITICAL, HIGH, and MEDIUM — is verified by a file-clustered fresh `reviewer-agent` spawn in verify-finding mode: survivors citing the same file share one spawn (up to 3 findings per cluster; a solo survivor or a sentinel-`File` finding spawns singly), with one independent verdict per finding. The verifier re-reads the cited code, grepped callers, and 1-2 sibling tests, and emits a structured verification result per finding. Isolated context per verifier (NOT the full reviewer bundle — the isolation boundary is the originating reviewer's bundle, not cluster siblings) prevents anchoring and sycophancy. Every §4.1 survivor is verified — no tier-scaling, no severity-scaling. The §4.1 multi-signal gate already constrains the survivor set to findings with Evidence-Block-grade citations (signal #2 mandatory for MEDIUM, and every kept finding at CRITICAL / HIGH / MEDIUM carries an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`), so every code-anchored survivor has a concrete file:line for the verifier to re-read. The two sentinel-`File` dimensions (`SPEC-COMPLIANCE` / `PR-METADATA`) are path-less by design and verify against the diff instead of a code slice (§2 path-less branch).

## Contents

- §1 — When this fires
- §2 — Input contract (what each verifier receives)
- §3 — Output contract (verifier emits)
- §3.5 — Resolve embedded "confirm / verify" asks
- §3.6 — Actionability bar (reachable + behavior delta required for `confirmed`)
- §4 — Spawn batch shape
- §4.5 — Spawn-failure fail-open (orchestrator-assigned `unverified`)
- §5 — Result aggregation and demotion rules
- §6 — Anti-rationalization

---

## 1. When this fires

After the Phase 4.1 multi-signal threshold gate — Path A, severity-gated (`severity >= MEDIUM` AND any-of {convergence ≥2, Evidence-Block present + confidence ≥60, criteria-pre-resolved marker, confidence ≥80 fallback}; tier-relaxed at signal #4 to ≥70 for `risk-tier: high`). See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5 for the full gate spec, including Path B (decision-type admission). Fires BEFORE Phase 4.3 test-confirmation gate and Phase 5 stratification.

The verified set is every kept finding at CRITICAL / HIGH / MEDIUM, whichever path admitted it: a Path-B `PRODUCT-DECISION` at MEDIUM or higher verifies against its own `File: path:lines` anchor like any Path-A survivor, because the handoff schema makes the verification fields mandatory at those severities. LOW is the only severity that skips — a trade-off at LOW is not a defect-to-confirm, and it carries no verification fields downstream.

Skip condition: ONLY when that set is empty. Never skip based on tier — every CRITICAL / HIGH / MEDIUM survivor gets a verifier.

---

## 2. Input contract per verifier

Each verifier spawn receives ONLY:

- The finding bodies of ONE cluster — 1-3 findings citing the same file, each with its full body (title / file:line / severity / decision-type / confidence / evidence / suggested-fix / why-matters). A single finding is the degenerate one-finding cluster; /geniro:resolve clusters its same-file comment items the same way, and spec-challenge always passes one.
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
- `validation: unverified` — orchestrator-assigned only (§4.5), when the verifier failed to spawn after retry or returned nothing parseable; a verifier never emits this value.
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
- When the pattern exists but no actionable path does, emit `validation: refuted`, `recommended_action: drop`, and an `evidence` line stating the reachability result (e.g. `flag useProposalV2 OFF in prod → the new V2 write block is unreachable; getRejectionHubspotValue(null)==='No'==pre-PR → zero delta`). The orchestrator files it under `## Filtered` with reason `not-actionable`.
- Reason from the code and config, NOT from the finding's framing. A confident reviewer description of a real pattern is not evidence that the pattern is reachable.

**Parity test for effect-claims.** When a finding's impact claim has the shape "X newly enters / newly triggers path P" (dispatch, digest, notification, fanout, billing — any effect-claim), check whether P was already reachable with the same inputs BEFORE the PR — grep the pre-existing callers / columns / predicates that feed P. If an existing path already produces the claimed effect, the delta is overstated: emit `refuted` (zero-delta), or `clarified` with the impact framing downgraded when a genuine residual delta remains. Either way, `evidence` must quote the pre-existing path (file:line) — the same literal-quote standard as the rest of this bar.

A non-actionable finding is always `refuted` (`not-actionable`), never `clarified` — `clarified` presupposes the finding is actionable and merely needs a different recommended action, so it must not be the escape hatch for a finding that should be dropped.

A real server-side pattern that is unreachable under the production flag state is exactly what this bar refutes without the user having to prompt a re-check.

---

## 4. Spawn batch shape

Orchestrator-side (in /geniro:review Phase 4.2):

```
Group non-sentinel §4.1 survivors by cited file path; split a group of 4+ into clusters of ≤3.
A sentinel-File survivor (SPEC-COMPLIANCE / PR-METADATA) never clusters — compose its
spawn per §2's path-less bullet (finding body + `git diff --name-only <base>...HEAD`
+ any real code file:line embedded in its evidence, read ± 30 lines when present);
add to the same parallel-spawn batch.

For each cluster:
  1. Read the cited file ONCE, extracting each member's line ± 30 window (merge overlaps).
  2. Run `grep -rn "<key symbol from member.evidence>" --include="*.<ext>"` per member
     (cap 50 lines each; one merged grep when members share the symbol).
  3. Run `grep -rn "<symbol>" test/ tests/ __tests__/ spec/` per member (cap 20 lines each).
  4. Compose ONE verifier spawn: all member finding bodies + the shared slice + grep
     outputs; instruct one verdict block per finding, keyed by file:line + title.
  5. Add to parallel-spawn batch.

After loop:
  Send ALL spawn calls in ONE assistant response (parallel).
  - Use `Agent(subagent_type="geniro:reviewer-agent", ...)` per the ladder in
    `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`.
  - OMIT `model=` (orchestrator tier inherits via frontmatter `model: inherit`) per
    `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`.
```

Critical: ALL verifier spawns fire in ONE assistant response, same assistant turn, NOT one per turn. Separate turns serialize execution and double wall-time; the canonical parallel-spawn invariant applies.

**Deep mode (`deep-mode: true`).** Clustering applies only in standard mode; deep mode verifies each survivor individually inside a `Workflow(...)` with signal-gated verification — one verifier, escalating to a 3-vote 2/3 majority only where the verdict is contested or high-stakes. The escalation contract, the abstain rule, and the quorum fail-safe are canonical at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3 (precision layer); the consuming skill's own deep-mode reference names the concrete thresholds that instantiate them. The per-verifier input (§2), output (§3), and actionability bar (§3.6) are identical; persist the final verdict to the existing `Validation` field and the vote path to `Verification-evidence` (no schema bump).

---

## 4.5 Spawn-failure fail-open

A verifier can fail to produce a verdict at all: the spawn errors out even after the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`, or it returns output with no parseable `validation:` value after the one empty-result retry (inherit tier). The finding then lands in none of the §3 outcome buckets, and an unmarked `Validation:` would read as `confirmed` to every consumer via the legacy back-compat rule — masking "nobody checked this" as "this was checked". The orchestrator instead assigns an explicit disposition — a failed cluster spawn (after the ladder + one retry) assigns it to EVERY finding in that cluster:

- `Validation: unverified`, `Verification-confidence: 1`, `Verification-evidence: "verifier did not run — spawn failed after retry"`, `Recommended-action` mirroring the finding's original Decision Type.
- The finding stays kept — fail-open, mirroring the Phase 1.5 mechanical pre-pass and Phase 4.3 test-gate doctrine: a tooling failure never deletes a finding the reviewers already paid for.
- It is excluded from any PR post set and surfaced under `## Caveats`: "N findings could not be independently verified — the verifier agent failed to run; they are kept in the report but will not be posted to the PR."
- Write a state.md `## Errors` entry via `atomic_state_write`: `phase: stratify`, `error: verifier-spawn-failed`, plus the affected finding IDs.

Do not fall back to `spawn-agent.md`'s generic inline-author terminal step for verify-finding spawns — the orchestrator holds the full reviewer bundle, which is exactly the anchoring context the §2 isolation contract forbids, so an inline self-check would be an anchored confirmation, not a verification. `unverified` states the truth instead: this finding was never independently checked.

`unverified` is orchestrator-assigned only — a verifier agent never emits it. Consumer-side semantics (legal since `m6-v2`; kept, not postable, one-line warning) live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md`.

---

## 5. Result aggregation and demotion rules

After all verifiers return, the orchestrator processes each finding's verdict block by the same rules:

1. **`validation: refuted`** — move the finding to the report's `## Filtered` section with reason `refuted-by-verifier` (or `not-actionable` when the verifier refuted on the §3.6 actionability bar — the defect was real but unreachable / no behavior delta). Do NOT propagate to Phase 4.3 test-confirmation gate or Phase 5 stratify. Do NOT include in the handoff `## Findings` body. This keeps refuted findings out of `open_questions[]` and leaves the consumer-side handoff resolution gate (read by /geniro:implement) unchanged.
2. **`validation: clarified`** — update the finding's `Decision Type:` to match the verifier's `recommended_action`. Append verifier `confidence` and `evidence` to the finding body. Keep finding in active set. When the verifier resolved an embedded "confirm X" ask (§3.5), replace that phrasing in the finding body with the verified result it returned — the posted finding states the fact, never the un-run check.
3. **`validation: confirmed`** — append verifier `confidence` and `evidence` to the finding body. Keep finding in active set (decision-type unchanged).
4. **State-file persistence** — write `validation`, `recommended_action`, `verification_confidence`, `verification_evidence` to the per-finding body schema in `review-handoff.md` (handoff schema bump from m6-v1 → m6-v2).

---

## 6. Anti-rationalization

| Reasoning the verifier (or orchestrator) might generate | Why that's wrong |
|---|---|
| "The original reviewer is usually right — confirm to maintain coherence." | Agreeing to stay coherent with the original reviewer is the documented multi-judge failure mode. Re-read the cited code; if the defect is not visible in the quote, mark refuted. Coherence is not a verification signal. |
| "Skip the caller grep — the finding cites `file:line`, that's enough." | The cited `file:line` is the reviewer's claim. Without grepping callers, impact cannot be refuted or confirmed. Read the call sites before emitting. |
| "Pass the full reviewer bundle to each verifier so they have full context." | Shared context anchors verifiers toward agreement — they read the original framing instead of the code. Each verifier sees ONLY its cluster's finding bodies plus cited slice plus caller grep. Independence is load-bearing. The sanctioned cluster — up to 3 co-located finding bodies citing the same file — is not the forbidden bundle, which is the originating reviewer's full output and framing. |
| "Sibling finding #1 in this cluster is confirmed, so #2 in the same file is probably real too." | Cross-item anchoring is the documented failure mode of batched judgment — a verdict must rest on its own literal quote from the cited code, not on a sibling's verdict. Confirm/refute each finding as if it were the only one in the spawn. |
| "Verifier confidence:1 — silently demote severity to MEDIUM instead of refuting." | `confidence: 1` with no contradicting evidence means the verifier is uncertain; emit `validation: clarified, confidence: 1` and let the orchestrator decide. Silently demoting severity hides the uncertainty from the consumer. |
| "All §4.1 survivors verified takes too many spawns — sample top-N instead." | The verifier explicitly drops tier-scaling AND severity-scaling. Parallel-spawn invariant: wall-time is ~max(spawn-time) regardless of N. Token cost is bounded by the §4.1 multi-signal gate, which is already tight (MEDIUM requires Evidence-Block + ≥60 confidence), AND by file-clustering — co-located survivors share one spawn. If finding count is high, that signals tightening Phase 4.1, not under-verifying. Sampling or skipping reintroduces the failure mode the empirical-reproduction pass exists to eliminate. |
| "CRITICAL findings are reliable by definition — skip verification for CRITICALs." | CRITICALs can be admitted under §4.1 signals #1 (convergence) / #3 (criteria pre-resolved) / #4 (confidence ≥80) without an explicit Evidence-Block — a convergent CRITICAL with weak quoting is exactly the case empirical reproduction catches. Skipping verification for CRITICALs because they "look right" is sycophancy at maximum stake: a confirmed-without-evidence CRITICAL lands on the PR, gates `/geniro:implement` Phase 1, and surfaces to the user as load-bearing. Verify every survivor. |
| "MEDIUM verification is overkill — these are paper cuts." | MEDIUMs that survive §4.1 carry an Evidence-Block per signal #2 (mandatory for MEDIUM) — they cite a concrete code slice (code-anchored) or a verbatim plan/PR fragment (sentinel `File`) worth re-reading. The risk is the opposite of overkill: a MEDIUM that skips verification — but that the verifier would have refuted had it run — lands on the PR as exactly the false positive `## Filtered` exists to hold back. The verifier is the mechanism that distinguishes "the reviewer misread the code" from "the defect is real" at MEDIUM stake. Don't pre-judge which severities deserve grounding — let the verifier ground them. |
| "The finding's `suggested-fix:` reads sensible — confirm without re-reading code." | The suggested-fix being sensible is independent of whether the defect exists. Verification reads the cited code AND the caller grep; the suggested-fix is not evidence of the defect. |
| "The cited pattern is real, so confirm it." | Existence is not actionability (§3.6). Ask: with the gating flag / gate / role in its CURRENT production state, does this change produce a different outcome than before the PR? If the path is unreachable or the value equals pre-PR, it is noise — refute it (`not-actionable`). A real-but-unreachable finding posted to the PR is the false positive this bar exists to kill. |
| "The fanout/handler is new code, so its effects are new — confirmed." | New code ≠ new effect. Parity-check the EFFECT: if a pre-existing path already produced the same downstream outcome with the same inputs, the finding's impact claim is overstated — quote that path and refute or downgrade. |

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — agent registration ladder.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — OMIT `model=` rule.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` — handoff schema consumer.
- `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` — base agent contract the verifier mode extends.
