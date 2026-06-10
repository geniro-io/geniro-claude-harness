# /geniro:review Phase 4.2 — Per-finding empirical-reproduction verifier

Every finding surviving Phase 4.1 — CRITICAL, HIGH, and MEDIUM — gets ONE fresh `reviewer-agent` spawn in verify-finding mode. The verifier re-reads the cited code, grepped callers, and 1-2 sibling tests, and emits a structured verification result. Isolated context per verifier (NOT the full reviewer bundle) prevents anchoring and sycophancy. Every §4.1 survivor is verified — no tier-scaling, no severity-scaling. The §4.1 multi-signal gate already constrains the survivor set to findings with Evidence-Block-grade citations (signal #2 mandatory for MEDIUM; Loop Invariant #6 mandates Evidence at every kept severity), so every code-anchored survivor has a concrete file:line for the verifier to re-read. The two sentinel-`File` dimensions (`SPEC-COMPLIANCE` / `PR-METADATA`) are path-less by design and verify against the diff instead of a code slice (§2 path-less branch).

## Contents

- §1 — When this fires
- §2 — Input contract (what each verifier receives)
- §3 — Output contract (verifier emits)
- §3.5 — Resolve embedded "confirm / verify" asks
- §3.6 — Actionability bar (reachable + behavior delta required for `confirmed`)
- §4 — Spawn batch shape
- §5 — Result aggregation and demotion rules
- §6 — Anti-rationalization

---

## 1. When this fires

After the Phase 4.1 multi-signal threshold gate — Path A, severity-gated (`severity >= MEDIUM` AND any-of {convergence ≥2, Evidence-Block present + confidence ≥60, criteria-pre-resolved marker, confidence ≥80 fallback}; tier-relaxed at signal #4 to ≥70 for `risk-tier: high`). See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5 for the full gate spec, including Path B (a LOW `PRODUCT-DECISION` admitted by decision-type, which skips this verifier). Fires BEFORE Phase 4.3 test-confirmation gate and Phase 5 stratification.

Skip condition: ONLY when the Path-A surviving set is empty (a Path-B-only LOW `PRODUCT-DECISION` is not a defect-to-confirm and is never verified). Never skip based on tier or severity — every CRITICAL / HIGH / MEDIUM survivor gets a verifier.

---

## 2. Input contract per verifier

Each verifier spawn receives ONLY:

- The single finding's full body (title / file:line / severity / decision-type / confidence / evidence / suggested-fix / why-matters).
- The cited code slice — orchestrator reads the file at finding `file:line ± 30` lines and inlines into the prompt.
- 1-hop caller grep results — orchestrator runs `grep -rn "<symbol>" --include="*.<ext>"` for the cited symbol; pipe results capped at 50 lines.
- 1-2 sibling test references for the same symbol — orchestrator greps test directories (`test/`, `tests/`, `__tests__/`, `spec/`); capped at 20 lines.

When the finding's body asks the author to confirm something about ANOTHER file, symbol, or migration (a "confirm X" / "verify Y" claim), the orchestrator also includes the evidence needed to check it — the PR's changed-file list (`git diff --name-only <base>...HEAD`), `git log --oneline -- <cited-path>`, or the relevant grep — so the verifier can resolve the claim rather than pass it through. See §3.5. When the finding's risk depends on a feature flag / gate / role / config branch, the orchestrator also includes the current config state (the flag's default value, the gate's condition) so the verifier can apply the §3.6 actionability bar.

**Path-less sentinel findings (`File: SPEC-COMPLIANCE` / `File: PR-METADATA`).** A finding whose `File:` field is a sentinel string carries no code `path:line`, so the cited-code-slice bullet above does not apply — there is nothing at `<sentinel> ± 30 lines`. For these, the orchestrator supplies instead: the finding's `Evidence:` (which quotes the spec/PR fragment verbatim), the PR's changed-file list (`git diff --name-only <base>...HEAD`), and any real code `file:line` embedded in the Evidence (a spec-defect finding cites the code that contradicts the spec premise — read it ± 30 lines). The verifier judges the claim against the diff + cited fragment: "is the scoped item actually absent from the changed files?" for a code-omission finding, or "does the cited code actually contradict the spec premise?" for a spec-defect finding. For an omission finding, `git diff --name-only` confirms the named artifact's presence or absence — the right granularity for an omission claim; it does not validate the artifact's content, which a code-anchored dimension would have flagged with its own `file:line`. The `confirmed` / `refuted` / `clarified` semantics, the §3.6 actionability bar, and the anti-sycophancy guard are unchanged.

Each verifier does NOT receive:

- Other reviewers' findings.
- The full reviewer-agent bundle output.
- The orchestrator's prior reasoning.
- Information about which dimension originated the finding (avoids anchoring on the originating reviewer's framing).

Rationale: independent verifiers that do not see each other's outputs cannot anchor on a shared framing — each re-reads the cited code cold and judges the finding on its own merits, which is what keeps the verification honest.

---

## 3. Output contract per verifier

The verifier emits exactly one structured response:

```yaml
validation: confirmed | refuted | clarified
recommended_action: fix-now | testable | product-decision | intent-check | drop
confidence: 1 | 2 | 3 | 4 | 5
evidence: "<exact quote from cited file:line OR caller chain that confirms/refutes>"
```

Field semantics:

- `validation: confirmed` — the cited code exhibits the defect AND the defect is actionable (§3.6); original decision-type stands.
- `validation: refuted` — EITHER the cited code does not exhibit the claimed defect (verifier read the file and disagrees), OR the defect exists but is not actionable (§3.6 — unreachable under current config, or a normal/safe pattern with no behavior delta).
- `validation: clarified` — the finding is correct but the recommended action differs from the original reviewer's; verifier's `recommended_action` overrides.
- `recommended_action` reuses the plugin's existing 4-way taxonomy (fix-now / testable / product-decision / intent-check) plus `drop` for refuted findings.
- `confidence` 1-5 coarse scale: 1 = 'low — could be wrong', 5 = 'certain — direct evidence'.
- `evidence` must be a literal quote from the cited file or caller chain. "I agree" / "looks correct" / paraphrases are insufficient — refuse the output and re-prompt the verifier.

---

## 3.5 Resolve embedded "confirm / verify" asks

Some findings — most often migration, regression, or scope findings — phrase part of their body as a request for the author to confirm something: "confirm both migrations ship in the same PR", "verify this symbol has no other callers", "make sure the dropped column isn't read elsewhere". When that something is checkable from evidence the reporter can reach (the diff, the changed-file list, git history, a grep), the verifier resolves it rather than letting the "confirm X" reach the PR. Pushing a verifiable check onto the reader is the offloading failure `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §4 prevents.

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

A non-actionable finding is always `refuted` (`not-actionable`), never `clarified` — `clarified` presupposes the finding is actionable and merely needs a different recommended action, so it must not be the escape hatch for a finding that should be dropped.

A real server-side pattern that is unreachable under the production flag state is exactly what this bar refutes without the user having to prompt a re-check.

---

## 4. Spawn batch shape

Orchestrator-side (in /geniro:review Phase 4.2):

```
For each §4.1 survivor (CRITICAL / HIGH / MEDIUM):
  0. If finding.file is a sentinel (SPEC-COMPLIANCE / PR-METADATA) — path-less, no code slice:
       compose per §2's path-less bullet — finding body + `git diff --name-only <base>...HEAD`
       + any real code file:line embedded in finding.evidence (read ± 30 lines when present);
       skip steps 1-3 and go to step 5.
  1. Read the cited file at finding.file:finding.line ± 30 lines.
  2. Run `grep -rn "<key symbol from finding.evidence>" --include="*.<ext>"` (cap 50 lines).
  3. Run `grep -rn "<symbol>" test/ tests/ __tests__/ spec/` (cap 20 lines).
  4. Compose verifier spawn prompt with finding body + cited slice + caller grep + test grep.
  5. Add to parallel-spawn batch.

After loop:
  Send ALL spawn calls in ONE assistant response (parallel).
  - Use `Agent(subagent_type="geniro-claude-plugin:reviewer-agent", ...)` per the ladder in
    `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`.
  - OMIT `model=` (orchestrator tier inherits via frontmatter `model: inherit`) per
    `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`.
```

Critical: ALL verifier spawns fire in ONE assistant response, same assistant turn, NOT one per turn. Separate turns serialize execution and double wall-time; the canonical parallel-spawn invariant applies.

**Deep mode (`deep-mode: true`).** Spawn 3 independent verifiers per survivor (instead of 1) inside a `Workflow(...)` and aggregate by 2/3 majority — `confirmed`/`clarified` are "stands" votes, `refuted` is a "drop" vote; ≥2 drop → refuted, else stands; a parse failure abstains; quorum < 2 parseable votes → fail-safe to ONE single-pass verifier. The per-verifier input (§2), output (§3), and actionability bar (§3.6) are identical; deep mode changes only the vote count and the aggregation. Persist the majority verdict to the existing `Validation` field and the tally to `Verification-evidence` (no schema bump). Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/deep-mode-reference.md` §3 (a `/geniro:review`-only execution path — cross-skill consumers of this file never follow it).

---

## 5. Result aggregation and demotion rules

After all verifiers return, the orchestrator processes results:

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
| "Pass the full reviewer bundle to each verifier so they have full context." | Shared context anchors verifiers toward agreement — they read the original framing instead of the code. Each verifier sees ONLY its finding plus cited slice plus caller grep. Independence is load-bearing. |
| "Verifier confidence:1 — silently demote severity to MEDIUM instead of refuting." | `confidence: 1` with no contradicting evidence means the verifier is uncertain; emit `validation: clarified, confidence: 1` and let the orchestrator decide. Silently demoting severity hides the uncertainty from the consumer. |
| "All §4.1 survivors verified takes too many spawns — sample top-N instead." | The verifier explicitly drops tier-scaling AND severity-scaling. Parallel-spawn invariant: wall-time is ~max(spawn-time) regardless of N. Token cost is bounded by the §4.1 multi-signal gate, which is already tight (MEDIUM requires Evidence-Block + ≥60 confidence). If finding count is high, that signals tightening Phase 4.1, not under-verifying. Sampling reintroduces the failure mode the empirical-reproduction pass exists to eliminate. |
| "CRITICAL findings are reliable by definition — skip verification for CRITICALs." | CRITICALs can be admitted under §4.1 signals #1 (convergence) / #3 (criteria pre-resolved) / #4 (confidence ≥80) without an explicit Evidence-Block — a convergent CRITICAL with weak quoting is exactly the case empirical reproduction catches. Skipping verification for CRITICALs because they "look right" is sycophancy at maximum stake: a confirmed-without-evidence CRITICAL lands on the PR, gates `/geniro:implement` Phase 1, and surfaces to the user as load-bearing. Verify every survivor. |
| "MEDIUM verification is overkill — these are paper cuts." | MEDIUMs that survive §4.1 carry an Evidence-Block per signal #2 (mandatory for MEDIUM) — they cite a concrete code slice (code-anchored) or a verbatim plan/PR fragment (sentinel `File`) worth re-reading. The risk is the opposite of overkill: an unverified MEDIUM with `validation: refuted` (had the verifier run) propagates to `## Filtered` would-be entries on the PR. The verifier is the mechanism that distinguishes "the reviewer misread the code" from "the defect is real" at MEDIUM stake. Don't pre-judge which severities deserve grounding — let the verifier ground them. |
| "The finding's `suggested-fix:` reads sensible — confirm without re-reading code." | The suggested-fix being sensible is independent of whether the defect exists. Verification reads the cited code AND the caller grep; the suggested-fix is not evidence of the defect. |
| "The finding says 'confirm both migrations ship together' — that's the author's call, I'll pass it through." | If "ship together" means "both are in this PR's diff", that's checkable: read the changed-file list (§3.5). Resolve it and state the fact via `validation: clarified`. Only the part that isn't in git — did it deploy to an environment independently? — stays as a note. Leaving a checkable "confirm X" in a posted finding offloads your job onto the reader. |
| "The cited pattern is real, so confirm it." | Existence is not actionability (§3.6). Ask: with the gating flag / gate / role in its CURRENT production state, does this change produce a different outcome than before the PR? If the path is unreachable or the value equals pre-PR, it is noise — refute it (`not-actionable`). A real-but-unreachable finding posted to the PR is the false positive this bar exists to kill. |

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — agent registration ladder.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — OMIT `model=` rule.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` — handoff schema consumer.
- `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` — base agent contract the verifier mode extends.
