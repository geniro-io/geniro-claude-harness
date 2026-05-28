# /geniro:review Phase 4.2 — Per-finding empirical-reproduction verifier

Every finding surviving Phase 4.1 — CRITICAL, HIGH, and MEDIUM — gets ONE fresh `reviewer-agent` spawn in verify-finding mode. The verifier re-reads the cited code, grepped callers, and 1-2 sibling tests, and emits a structured verification result. Isolated context per verifier (NOT the full reviewer bundle) prevents anchoring and sycophancy. Every §4.1 survivor is verified — no tier-scaling, no severity-scaling. The §4.1 multi-signal gate already constrains the survivor set to findings with Evidence-Block-grade citations (signal #2 mandatory for MEDIUM; Loop Invariant #6 mandates Evidence at every kept severity), so every survivor has a concrete file:line for the verifier to re-read.

## Contents

- §1 — When this fires
- §2 — Input contract (what each verifier receives)
- §3 — Output contract (verifier emits)
- §4 — Spawn batch shape
- §5 — Result aggregation and demotion rules
- §6 — Anti-rationalization

---

## 1. When this fires

After Phase 4.1 multi-signal threshold gate (`severity >= MEDIUM` AND any-of {convergence ≥2, Evidence-Block present + confidence ≥60, criteria-pre-resolved marker, confidence ≥80 fallback}; tier-relaxed at signal #4 to ≥70 for `risk-tier: high`). See `${CLAUDE_PLUGIN_ROOT}/skills/review/severity-calibration-reference.md` §5 for the full gate spec. Fires BEFORE Phase 4.3 test-confirmation gate and Phase 5 stratification.

Skip condition: ONLY when the Phase 4.1 surviving set is empty. Never skip based on tier or severity — every CRITICAL / HIGH / MEDIUM survivor gets a verifier.

---

## 2. Input contract per verifier

Each verifier spawn receives ONLY:

- The single finding's full body (title / file:line / severity / decision-type / confidence / evidence / suggested-fix / why-matters).
- The cited code slice — orchestrator reads the file at finding `file:line ± 30` lines and inlines into the prompt.
- 1-hop caller grep results — orchestrator runs `grep -rn "<symbol>" --include="*.<ext>"` for the cited symbol; pipe results capped at 50 lines.
- 1-2 sibling test references for the same symbol — orchestrator greps test directories (`test/`, `tests/`, `__tests__/`, `spec/`); capped at 20 lines.

Each verifier does NOT receive:

- Other reviewers' findings.
- The full reviewer-agent bundle output.
- The orchestrator's prior reasoning.
- Information about which dimension originated the finding (avoids anchoring on the originating reviewer's framing).

Rationale: "Independent reviewer agents provide decisions WITHOUT seeing each other's outputs; a meta-reviewer integrates. Independence prevents anchoring." — MARS, arXiv 2509.20502.

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

- `validation: confirmed` — the finding is correct as originally stated; original decision-type stands.
- `validation: refuted` — the cited code does not exhibit the claimed defect; verifier read the file and disagrees.
- `validation: clarified` — the finding is correct but the recommended action differs from the original reviewer's; verifier's `recommended_action` overrides.
- `recommended_action` reuses the plugin's existing 4-way taxonomy (fix-now / testable / product-decision / intent-check) plus `drop` for refuted findings.
- `confidence` 1-5 (Greptile-style scale): 1 = "low — could be wrong", 5 = "certain — direct evidence".
- `evidence` must be a literal quote from the cited file or caller chain. "I agree" / "looks correct" / paraphrases are insufficient — refuse the output and re-prompt the verifier.

---

## 4. Spawn batch shape

Orchestrator-side (in /review Phase 4.2):

```
For each §4.1 survivor (CRITICAL / HIGH / MEDIUM):
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

---

## 5. Result aggregation and demotion rules

After all verifiers return, the orchestrator processes results:

1. **`validation: refuted`** — move the finding to the report's `## Filtered` section with reason `refuted-by-verifier`. Do NOT propagate to Phase 4.3 test-confirmation gate or Phase 5 stratify. Do NOT include in the handoff `## Findings` body. This keeps refuted findings out of `open_questions[]` and leaves the consumer-side handoff resolution gate (read by /implement) unchanged.
2. **`validation: clarified`** — update the finding's `Decision Type:` to match the verifier's `recommended_action`. Append verifier `confidence` and `evidence` to the finding body. Keep finding in active set.
3. **`validation: confirmed`** — append verifier `confidence` and `evidence` to the finding body. Keep finding in active set (decision-type unchanged).
4. **State-file persistence** — write `validation`, `recommended_action`, `verification_confidence`, `verification_evidence` to the per-finding body schema in `phase-6-handoff-reference.md` (handoff schema bump from m6-v1 → m6-v2).

---

## 6. Anti-rationalization

| Reasoning the verifier (or orchestrator) might generate | Why that's wrong |
|---|---|
| "The original reviewer is usually right — confirm to maintain coherence." | Sycophancy is the documented multi-judge failure mode (arXiv 2509.23055). Re-read the cited code; if the defect is not visible in the quote, mark refuted. Coherence is not a verification signal. |
| "Skip the caller grep — the finding cites `file:line`, that's enough." | The cited `file:line` is the reviewer's claim. Without grepping callers, impact cannot be refuted or confirmed. Read the call sites before emitting. |
| "Pass the full reviewer bundle to each verifier so they have full context." | Shared context anchors verifiers toward agreement (MARS, arXiv 2509.20502). Each verifier sees ONLY its finding plus cited slice plus caller grep. Independence is load-bearing. |
| "Verifier confidence:1 — silently demote severity to MEDIUM instead of refuting." | `confidence: 1` with no contradicting evidence means the verifier is uncertain; emit `validation: clarified, confidence: 1` and let the orchestrator decide. Silently demoting severity hides the uncertainty from the consumer. |
| "All §4.1 survivors verified takes too many spawns — sample top-N instead." | The verifier explicitly drops tier-scaling AND severity-scaling. Parallel-spawn invariant: wall-time is ~max(spawn-time) regardless of N. Token cost is bounded by the §4.1 multi-signal gate, which is already tight (MEDIUM requires Evidence-Block + ≥60 confidence). If finding count is high, that signals tightening Phase 4.1, not under-verifying. Sampling reintroduces the failure mode the empirical-reproduction pass exists to eliminate. |
| "CRITICAL findings are reliable by definition — skip verification for CRITICALs." | CRITICALs can be admitted under §4.1 signals #1 (convergence) / #3 (criteria pre-resolved) / #4 (confidence ≥80) without an explicit Evidence-Block — a convergent CRITICAL with weak quoting is exactly the case empirical reproduction catches. Skipping verification for CRITICALs because they "look right" is sycophancy at maximum stake: a confirmed-without-evidence CRITICAL lands on the PR, gates `/implement` Phase 1, and surfaces to the user as load-bearing. Verify every survivor. |
| "MEDIUM verification is overkill — these are paper cuts." | MEDIUMs that survive §4.1 carry an Evidence-Block per signal #2 (mandatory for MEDIUM) — they cite concrete code worth re-reading. The risk is the opposite of overkill: an unverified MEDIUM with `validation: refuted` (had the verifier run) propagates to `## Filtered` would-be entries on the PR. The verifier is the mechanism that distinguishes "the reviewer misread the code" from "the defect is real" at MEDIUM stake. Don't pre-judge which severities deserve grounding — let the verifier ground them. |
| "The finding's `suggested-fix:` reads sensible — confirm without re-reading code." | The suggested-fix being sensible is independent of whether the defect exists. Verification reads the cited code AND the caller grep; the suggested-fix is not evidence of the defect. |

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — agent registration ladder.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — OMIT `model=` rule.
- `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` — handoff schema consumer.
- `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` — base agent contract the verifier mode extends.
- MARS: Multi-Agent Review System, arXiv 2509.20502 — independence prevents anchoring.
- Sycophancy in multi-judge LLM systems, arXiv 2509.23055 — coherence is not a verification signal.
