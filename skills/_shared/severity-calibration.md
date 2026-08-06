# /geniro:review — Severity and confidence calibration

Canonical decision rules consumed by `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` AND every `*-criteria.md` file. Per-dim criteria files may specialize severity to dim-specific signals, but they honor the inclusion + exclusion lists below — a criteria file that loosens them lets a dim re-classify a doc/cosmetic finding above LOW, corrupting the shared taxonomy that downstream consumers (verifier, stratifier, /geniro:implement) depend on.

## Contents

- §1 — Severity tiers with inclusion + exclusion lists
- §2 — Anti-pattern table (common miscalibrations)
- §3 — Worked examples per dim
- §4 — Confidence and agreement: reported, never admission signals
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
- A finding whose `Decision Type` is `PRODUCT-DECISION`. Its severity stays as scored, LOW included, but it is never cosmetic — it names a call that is the user's to make. This is the disqualifier the all-cosmetic signal in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §4 checks against, so a run holding one is not an all-cosmetic run however it scores.

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
| "I'll tag this MEDIUM so it surfaces — LOW gets dropped" | This is the perverse-incentive trap, and the §5 gate sharpens it rather than removing it: severity IS the admission at HIGH and above. Two things hold the line. §1 gives every tier an EXCLUSION list alongside its inclusion list, and exclusion wins when both could apply — documentation polish, naming, and process suggestions are excluded from MEDIUM by name, whatever inflating them would surface. And every admitted CRITICAL / HIGH / MEDIUM is re-read against its cited code by the Phase 4.2 verifier, so an inflated finding arrives at the one step that reads the code and refutes it. Score the true tier. | depends — true severity |

---

## 3. Worked examples

### bugs
- CRITICAL: SQL injection in `req.body` flowing to a raw query
- HIGH: Race condition between two writes to the same row with no transaction
- MEDIUM: Off-by-one in a paginator when item count is exactly equal to page size
- LOW: Unused import that triggers a lint warning

### pr-metadata

The dim's ceiling is HIGH: §1's CRITICAL inclusion list admits no PR-prose class, and §6 forbids a per-dim file widening it. A misrepresentation that reads as severe is the §1 HIGH "intent source contradicts the diff" case.

- HIGH: PR title misrepresents the diff (e.g., title says "refactor", diff adds new feature)
- HIGH: Missing test plan when test files are modified
- MEDIUM: Missing required field per repo's PR template (e.g., `risk_class:` declared in CONTRIBUTING.md)
- LOW: PR description could include the linked Linear ticket; commit message could be more verbose

### conventions

The dim owns three defect classes; each keeps its own ceiling, defined in its own criteria file (the `conventions` reviewer reads all three):

- **Style-rubric class** — per-file rubrics, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/guidelines-criteria.md` §Severity tagging. Never CRITICAL/HIGH; MEDIUM only on a tooling-load-bearing field, else LOW.
- **Modal-pattern class** — repo-modal patterns, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/conventions-criteria.md` §Severity guidelines (ceiling HIGH on a zero-shot-novel modal violation or a crossed fully-respected module boundary — thresholds owned there; LOW suppressed).
- **Authored-rule-citation class** — explicit rule files, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/rules-compliance-criteria.md` §4. Severity follows the IMPACT of breaking the cited rule (correctness/security invariant → up to CRITICAL; maintainability → MEDIUM; advisory → LOW), never the bare fact that it is a rule.

---

## 4. Confidence and agreement — reported, never admission signals

The reviewer-agent emits `Confidence: XX%` (0-100), and Phase 3 dedup computes a `convergence_count`. Both are reported; neither admits a finding. §5 admits on severity and on a mechanical citation check instead, because both of these fail as correctness estimators in the same way.

What the measurements support:

- **Verbalized confidence is a weak predictor, not a useless one.** Its rank correlation with correctness sits near the bottom of the useful range, and models are overconfident in the aggregate across model families and task types — a self-rated high number reads better than the finding deserves. A signal this weak cannot carry a KEEP decision alone, which is why it stays in the report and stays out of the gate.
- **Agreement is not the stronger alternative it appears to be.** Agreement among model outputs predicts correctness only weakly, and agreement between *correlated* samplers actively misleads: samplers sharing a prompt, a rubric, or a model reinforce their common errors instead of checking each other. Two dimensions sharing a rubric section are correlated by construction — the mirror-gap check is deliberately carried by both `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/architecture-criteria.md` §1.6 and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/regressions-criteria.md` §4 — so their agreeing is expected, not evidence.
- **Neither substitutes for reading the code.** The Phase 4.2 verifier re-reads the cited slice, and that is the step separating a real defect from a plausible description of one.

Implication: do not tune a confidence threshold, and do not add one back. The percentage is a report field the user reads beside the finding; `convergence_count` still feeds deep mode's escalation predicate and the Phase 5.3 recurring-pitfall signal. The §5 gate reads neither.

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

The KEEP/DEFER decision is governed by THREE signals — any one passing keeps the finding. This section is the gate's canonical home; `/geniro:review` applies it at its Phase 4.1 admission step and follows any threshold changed here.

```
KEEP IF:
  # Path A — severity-gated (also admits to the Phase 4.2 verifier)
  severity >= HIGH                                          # CRITICAL / HIGH admit on severity
  OR ( severity == MEDIUM
       AND Evidence-Block present AND properly formatted )  # code-grounded citation
  # Path B — decision-type orthogonal (any severity; a LOW admitted here skips
  #          the §4.2 verifier, a MEDIUM-or-higher still enters it)
  OR Decision Type == PRODUCT-DECISION    # the user's call, not the reviewer's — severity does not gate visibility
ELSE DEFER to ## Deferred — sub-threshold (state.md body; off the PR and the fix list
     by default — a user pick lifts it, per review-handoff.md §7.2 / §4.6)
```

**Why admission stops at severity and citation.** Every signal that tried to estimate whether a finding was *correct* — the reviewer's self-rated confidence, cross-dimension agreement — is too weak to carry the decision (§4), so the gate stops asking that question. It asks the two it can answer: how bad is this if real (severity, scored against §1's inclusion and exclusion lists rather than self-rated), and does the finding cite code that can be re-read (the Evidence-Block check, mechanical at §4.1 entry). Whether the defect is real is the Phase 4.2 verifier's question, and it reads the code to answer it.

The two signals that left the gate are not lost, only no longer load-bearing at admission: a criteria-file pre-resolved marker (e.g. the regressions signal-table) marks findings that score HIGH and are now admitted by severity anyway, and `convergence_count` still feeds deep mode's escalation predicate and the Phase 5.3 recurring-pitfall signal.

Admission constraint for MEDIUM: a MEDIUM finding requires the Evidence-Block. A MEDIUM admitted with nothing to re-read reaches the verifier with no slice to read and the user with no anchor, so it drops to `## Deferred — sub-threshold` instead. At CRITICAL / HIGH that same thin citation is admitted rather than dropped — losing a high-severity defect costs more — and the Phase 4.2 verifier supplies the missing quote, which makes the Evidence Block requirement (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`) a post-verification invariant rather than an admission-time one.

**The high-stakes refutation guard is what keeps this safe.** Putting the whole correctness judgment on the verifier concentrates the risk in a single verdict, and the documented failure mode of an LLM defect-filter is over-refutation — dropping a real bug. So at CRITICAL / HIGH one `refuted` verdict never demotes a finding by itself; it takes a second, independent verdict. That rule and its fail-safe are canonical at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §5.

No tier-dependent behavior at admission — `risk-tier: high` changes nothing in this gate, since the only thing it ever relaxed was a confidence floor that no longer exists. The §4.3 test-confirmation gate affects neither §4.1 admission nor §4.2 verification — test authoring runs after the finding set is fixed and never filters it.

Rationale:

- `severity >= HIGH`: severity is scored against §1's explicit inclusion and exclusion lists, which makes it a rubric judgment rather than a self-rating — and at these tiers the standing preference is to admit and verify rather than defer, because a dropped high-severity defect costs more than a verifier spawn.
- `Evidence-Block present AND properly formatted`: a code-grounded citation is the strongest defense against false positives, and alone among the candidates it is checked mechanically rather than judged.
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
- `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-3-4-filter-stratify.md` §4.1 — consumer: applies this file's §5 gate at its admission step
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` — per-finding verifier (disproof step on every §4.1 survivor)
