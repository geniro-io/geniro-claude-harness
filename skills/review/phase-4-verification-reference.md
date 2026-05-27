# /geniro:review Phase 4.2 — Per-HIGH-finding empirical-reproduction verifier

Every HIGH finding from the parallel reviewer batch gets ONE fresh `reviewer-agent` spawn in verify-finding mode. The verifier re-reads the cited code, grepped callers, and 1-2 sibling tests, and emits a structured verification result. Isolated context per verifier (NOT the full reviewer bundle) prevents anchoring and sycophancy. ALL HIGH findings are verified — no tier-scaling.

## Contents

- §1 — When this fires
- §2 — Input contract (what each verifier receives)
- §3 — Output contract (verifier emits)
- §4 — Spawn batch shape
- §5 — Result aggregation and demotion rules
- §6 — Anti-rationalization

---

## 1. When this fires

After Phase 4.1 threshold filter (`severity >= MEDIUM AND confidence >= 80%` for standard tier; relaxed elsewhere — but the verifier itself drops tier-scaling). Fires BEFORE Phase 4.3 test-confirmation gate and Phase 5 stratification.

Skip condition: ONLY when the Phase 4.1 surviving HIGH-finding set is empty. Never skip based on tier — every HIGH gets a verifier.

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
For each HIGH finding in Phase 4.1 survivors:
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
| "All HIGHs verified takes too many spawns — sample top-5 instead." | The verifier explicitly drops tier-scaling. If finding count is high, that's a signal to investigate the Phase 4.1 filter, not to under-verify. Sampling reintroduces the failure mode the empirical-reproduction pass exists to eliminate. |
| "The finding's `suggested-fix:` reads sensible — confirm without re-reading code." | The suggested-fix being sensible is independent of whether the defect exists. Verification reads the cited code AND the caller grep; the suggested-fix is not evidence of the defect. |

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — agent registration ladder.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — OMIT `model=` rule.
- `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-6-handoff-reference.md` — handoff schema consumer.
- `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` — base agent contract the verifier mode extends.
- MARS: Multi-Agent Review System, arXiv 2509.20502 — independence prevents anchoring.
- Sycophancy in multi-judge LLM systems, arXiv 2509.23055 — coherence is not a verification signal.
