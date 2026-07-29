# /geniro:review — Severity and confidence calibration

Canonical decision rules consumed by `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` AND every `*-criteria.md` file. Per-dim criteria files may specialize severity to dim-specific signals, but they honor the inclusion + exclusion lists below — a criteria file that loosens them lets a dim re-classify a doc/cosmetic finding above LOW, corrupting the shared taxonomy that downstream consumers (verifier, stratifier, /geniro:implement) depend on.

## Contents

- §1 — Severity tiers with inclusion + exclusion lists
- §2 — Anti-pattern table (common miscalibrations)
- §3 — Worked examples per dim
- §4 — Confidence: advisory, not load-bearing
- §5 — Multi-signal Phase 4.1 gate
- §6 — Per-dim calibration variants

---

## 1. Severity tiers

The taxonomy is CRITICAL / HIGH / MEDIUM / LOW. Each tier has an INCLUSION list (what counts) AND an EXCLUSION list (what does NOT count). When both lists could apply, exclusion wins — downgrade to the next lower tier.

### CRITICAL

**Includes:**
- Security vulnerability with a concrete exploit path (SQL injection in user input; XSS in unsanitized field; broken auth/authorization; secret leak; insecure deserialization with reachable code path)
- Data-loss or data-corruption path (DROP without WHERE; race condition that overwrites user records; missing migration rollback)
- Hard crash on a documented input (unhandled NPE on common path; stack overflow on bounded recursion; deadlock with documented trigger)
- Compliance violation with regulatory teeth (PII leak; GDPR/HIPAA scope leak; secret committed)
- Deletion of a public API / module export / shared type with surviving cross-file callers OR downstream-consumer repo references (the `regressions` dim's deleted-symbol caller-blast signal). Per-dim concrete criteria in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/regressions-criteria.md` Severity Tagging table.

**Excludes:**
- Hypothetical risk without a documented trigger ("this could lead to..." without a concrete scenario)
- Defense-in-depth gaps where another layer mitigates
- Performance issues, even severe ones (those are HIGH unless they cause a hard timeout in production)

### HIGH

**Includes:**
- Will cause visible regression to users (broken feature with cited reproduction; uncovered error path with concrete failure mode)
- Race condition with a specific cited scenario (the scenario must be cited, not hypothesized)
- Missing validation that lets malformed input reach a downstream consumer
- Deleted production code with cross-file callers (the `regressions` dim signal: deletion + caller-blast)
- Performance issue exceeding a measured threshold (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/optimizations-criteria.md`: >100 items, >1000 rows, >100KB minified — these are HIGH; below those, MEDIUM)
- Behavior change outside stated intent when an intent source exists (spec.md / PR body / commit message contradicts the diff)

**Excludes:**
- Theoretical defects without a reproduction path ("could fail if X" without showing how X happens)
- Maintainability concerns without a defect ("this is hard to read" — LOW)
- Documentation gaps, PR-description suggestions, naming polish, style — these are LOW
- Convention drift on optional fields

### MEDIUM

**Includes:**
- Verifiable defect impacting reliability or clarity for end users that is unlikely or non-blocking
- Edge-case bug with low likelihood (the edge case must be reachable)
- Missing test coverage where the uncovered path has a documented failure mode
- Maintainability or clarity issue with concrete user-visible impact
- Convention drift on a required field (e.g., missing required `risk_class:` per CLAUDE.md `/geniro:actions` contract — MEDIUM because tooling depends on it)

**Excludes:**
- Documentation polish, PR-description verbosity, comment wording — LOW (never MEDIUM)
- Naming polish, formatting, style suggestions — LOW
- Process recommendations ("add a checklist to the PR description", "label this with X", "split into 2 PRs") — LOW
- Cosmetic refactors with no impact — LOW

### LOW

**Includes:**
- Style / naming / format suggestions
- Documentation polish (comments, docstrings, README clarity)
- PR-description / commit-message verbosity suggestions ("add the test plan to the PR description", "mention the linked Linear ticket")
- Cosmetic refactors without defect evidence
- Convention drift on non-critical fields
- Useful-but-optional improvements

**Excludes:**
- Real defects (those are MEDIUM+)
- Cosmetic suggestions that hide a substantive problem (a "could be more readable" finding that masks a hidden bug is MEDIUM, not LOW)

The plugin has no separate NIT tier — LOW covers both "minor real issue" and "cosmetic suggestion". Per §5 below, LOW findings are written to `## Deferred — sub-threshold` for awareness and reach neither the PR-comment surface nor the fix list BY DEFAULT — an explicit user pick lifts that gate (the Post drill's "Send all", or the include-deferred gate on the "/geniro:implement findings" path; `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.2 / §4.6), because severity gates default disposition, not user-elected disposition. One exception to the deferral itself: a LOW finding whose `Decision Type` is `PRODUCT-DECISION` is kept and surfaced regardless of severity (it names the user's call, not the reviewer's), per §5 Path B.

---

## 2. Anti-pattern table

| Rationalization | Why it's wrong | Correct tier |
|---|---|---|
| "Documentation gap is MEDIUM because docs matter" | LOW unless the missing doc directly causes a defect (e.g., undocumented BREAKING change in a public API → HIGH). General doc polish never exceeds LOW. | LOW |
| "PR description should mention X — that's a MEDIUM" | PR-description verbosity is process feedback, not a code defect. Reviewers do not block merge on prose. | LOW |
| "Naming convention drift is MEDIUM because consistency matters" | Naming is style. The `conventions` dim's style-rubric class mandate is to flag it, not block merge on it. | LOW |
| "Missing test coverage is HIGH because tests matter" | HIGH only if the uncovered path has a documented failure mode that this PR could trigger. Otherwise MEDIUM (verifiable defect risk) or LOW (theoretical gap). | MEDIUM or LOW |
| "Performance suggestion is HIGH because it might be slow" | HIGH requires a measured threshold per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/optimizations-criteria.md` (>100 items, >1000 rows, >100KB). Below that: MEDIUM. Untested: LOW. | depends |
| "Could be refactored — MEDIUM" | "Could be refactored" with no impact citation is LOW. MEDIUM requires a specific maintainability impact (e.g., new contributor onboarding time, common error source). | LOW |
| "I'll tag this MEDIUM so it surfaces — LOW gets dropped" | This is the perverse-incentive trap. The Phase 4.1 multi-signal gate (§5) provides four independent signals for a finding to surface — convergence, Evidence-Block + confidence ≥ 60, criteria-pre-resolved marker, and a confidence ≥ 80 fallback. If the finding is correct, one of those will fire — do not inflate severity to game the filter. | depends — true severity |

---

## 3. Worked examples

### bugs
- CRITICAL: SQL injection in `req.body` flowing to a raw query
- HIGH: Race condition between two writes to the same row with no transaction
- MEDIUM: Off-by-one in a paginator when item count is exactly equal to page size
- LOW: Unused import that triggers a lint warning

### pr-metadata
- CRITICAL: PR title misrepresents the diff (e.g., title says "refactor", diff adds new feature)
- HIGH: Missing test plan when test files are modified
- MEDIUM: Missing required field per repo's PR template (e.g., `risk_class:` declared in CONTRIBUTING.md)
- LOW: PR description could include the linked Linear ticket; commit message could be more verbose

### conventions

The dim owns three defect classes; each keeps its own ceiling, defined in its own criteria file (the `conventions` reviewer reads all three):

- **Style-rubric class** — per-file rubrics, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/guidelines-criteria.md` §Severity Tagging. Never CRITICAL/HIGH; MEDIUM only on a tooling-load-bearing field, else LOW.
- **Modal-pattern class** — repo-modal patterns, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/conventions-criteria.md` §Severity Guidelines (ceiling HIGH on a zero-shot-novel ≥80% modal violation or a crossed 100%-respected boundary; LOW suppressed).
- **Authored-rule-citation class** — explicit rule files, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/rules-compliance-criteria.md` §4. Severity follows the IMPACT of breaking the cited rule (correctness/security invariant → up to CRITICAL; maintainability → MEDIUM; advisory → LOW), never the bare fact that it is a rule.

---

## 4. Confidence — advisory, not load-bearing

The reviewer-agent emits `Confidence: XX%` (0-100). This is an advisory hint about reviewer self-rated certainty. It is NOT the load-bearing filter — see §5.

Documented limits of LLM-self-reported confidence:

- Verbalized confidence is poorly calibrated for the Claude family — a self-rated '80%' tends to land closer to a 55-60% true-positive rate, so the number reads higher than the finding actually deserves.
- In production code-review systems, LLM self-rating behaves nearly randomly; filtering on a confidence threshold did not reliably separate true from false findings.
- Coarse-grained confidence labels do not calibrate better than raw percentages, but they resist collapsing toward a single modal value.

Implication: do not invest energy in tuning the threshold value. The percentage is a UI hint; the multi-signal gate in §5 is what actually filters.

Confidence scoring guidance (still emit, advisory):

- 80-100: Definitely real, certain fix needed
- 60-79: Very likely real, should fix
- 40-59: Probably real but uncertain
- 20-39: Might be real, low priority
- 0-19: Probably false positive

Adjustments (still apply):

- Evidence explicit (cites a file:line literal): +10
- Pattern systemic (exists in 3+ places): -10 per individual; flag as systemic
- Mitigating code exists nearby: -20
- Criteria explicitly calls this out: +10

---

## 5. Multi-signal Phase 4.1 gate

The KEEP/DEFER decision is governed by FOUR independent signals — any one passing keeps the finding. This section is the gate's canonical home; `/geniro:review` applies it at its Phase 4.1 admission step and follows any threshold changed here.

```
KEEP IF:
  # Path A — severity-gated (also admits to the Phase 4.2 verifier)
  ( severity >= MEDIUM
    AND (
      convergence_count >= 2                                                # multi-dim agreement
      OR (Evidence-Block present AND properly formatted AND confidence >= 60)  # code-grounded citation
      OR (criteria-file-marked-pre-resolved, e.g. regressions signal-table HIGH)  # explicit overrides
      OR confidence >= 80                                                   # advisory fallback
    )
  )
  # Path B — decision-type orthogonal (any severity; a LOW admitted here skips
  #          the §4.2 verifier, a MEDIUM-or-higher still enters it)
  OR Decision Type == PRODUCT-DECISION    # the user's call, not the reviewer's — severity does not gate visibility
ELSE DEFER to ## Deferred — sub-threshold (state.md body; off the PR and the fix list
     by default — a user pick lifts it, per review-handoff.md §7.1 / §4.6)
```

Additional admission constraint for MEDIUM: a MEDIUM finding requires signal #2 specifically (Evidence-Block present + properly formatted). Signals #1, #3, #4 alone admit CRITICAL and HIGH but NOT MEDIUM. A MEDIUM admitted on convergence or a confidence score alone would be kept with nothing to re-read, so it drops to `## Deferred — sub-threshold` instead. At CRITICAL / HIGH that same thin citation is admitted rather than dropped — losing a high-severity defect costs more — and the Phase 4.2 verifier supplies the missing quote, which makes the Evidence Block requirement (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`) a post-verification invariant rather than an admission-time one.

Tier-aware behavior: standard tier uses signal #4 as written (confidence ≥ 80). High tier (`risk-tier: high`) relaxes signal #4 to `confidence ≥ 70`. Other signals (convergence, Evidence-Block, pre-resolved) unchanged across tiers. The §4.3 test-confirmation gate affects neither §4.1 admission nor §4.2 verification — test authoring runs after the finding set is fixed and never filters it.

Rationale:

- `convergence_count >= 2`: when two or more independent dims flag the same finding, that agreement is a stronger signal than any single dim's self-rated confidence — multiple reviewers converging measurably lifts precision on real defects.
- `Evidence-Block resolves` (with confidence ≥ 60 floor): a code-grounded citation is the strongest defense against false positives; the confidence floor screens out low-conviction citations.
- Pre-resolved markers: explicit overrides preserve existing regressions-criteria signal-table semantics
- Confidence >= 80: kept as a fallback path, no longer the primary gate
- `Decision Type == PRODUCT-DECISION` (Path B): decision-type (who-decides) is orthogonal to severity (impact-if-wrong). A PRODUCT-DECISION is a call the reviewer cannot close, so the user must see it regardless of severity — mirroring `/geniro:refactor`'s always-WAIT PRODUCT-DECISION escalation. Path B keeps severity as scored (a LOW PRODUCT-DECISION stays LOW — admission by decision-type, NOT the severity inflation §2 forbids).

  **Verification splits by severity on Path B.** A LOW admitted here skips the §4.2 verifier — a trade-off at LOW is not a defect-to-confirm, and it carries no verification fields into the handoff. A MEDIUM-or-higher admitted by Path B alone (no Path-A signal held) still enters §4.2, because the handoff schema makes the four verification fields mandatory on every kept CRITICAL / HIGH / MEDIUM finding (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §"Verification fields — presence rules") — a MEDIUM+ that skipped the verifier is a finding the schema cannot express. It verifies against its own `File: path:lines` anchor like any other survivor.

The Phase 4.2 per-finding verifier is the disproof step on every §4.1 survivor — CRITICAL, HIGH, AND MEDIUM: it actively attempts to disprove each finding rather than confirm it.

---

## 6. Per-dim calibration variants

Per-dim criteria files may tighten this rubric (e.g., `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/conventions-criteria.md` caps at HIGH and suppresses LOW) but must not loosen it — loosening lets sub-threshold findings surface past the shared gate. Specifically:

- Documentation, PR-description, and cosmetic suggestions stay at LOW in every criteria file. Lifting one above LOW is how a dim smuggles a paper cut past the shared gate and onto the PR surface.
- CRITICAL stays exactly the §1 inclusion list. Widening it in one dim out-ranks the taxonomy every downstream consumer reads, so the same defect scores differently depending on which reviewer found it.
- Dim-specific HIGH/MEDIUM signals are welcome — regressions: deleted-symbol caller-blast → HIGH; optimizations: >1000 rows → HIGH.

A per-dim file that specializes severity cites §1 as the canonical taxonomy and documents only its own specialization. Restating the tiers locally is how the taxonomy forks: the local copy drifts, and two dims then disagree about what MEDIUM means.

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Severity levels + §Confidence Scoring — agent-side rubric pointers here
- `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` §4.1 — consumer: applies the §5 gate at its admission step
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` — per-finding verifier (disproof step on every §4.1 survivor)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md` — Cause taxonomy ([ROOT-CAUSE] / [SYMPTOM] / [UNKNOWN])
