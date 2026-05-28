# /geniro:review — Severity and confidence calibration

Canonical decision rules consumed by `agents/reviewer-agent.md` AND every `*-criteria.md` file. When per-dim criteria files specialize severity to dim-specific signals, they MUST honor the inclusion + exclusion lists below.

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
- Deletion of a public API / module export / shared type with surviving cross-file callers OR downstream-consumer repo references (the `regressions` dim's deleted-symbol caller-blast signal). Per-dim concrete criteria in `${CLAUDE_PLUGIN_ROOT}/skills/review/regressions-criteria.md` Severity Tagging table.

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
- Performance issue exceeding a measured threshold (per `optimizations-criteria.md`: >100 items, >1000 rows, >100KB minified — these are HIGH; below those, MEDIUM)
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
- Convention drift on a required field (e.g., missing required `risk_class:` per CLAUDE.md `/actions` contract — MEDIUM because tooling depends on it)

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

The plugin has no separate NIT tier — LOW covers both "minor real issue" and "cosmetic suggestion". Per §5 below, LOW findings are written to `## Deferred — sub-threshold` for awareness; they do not reach the PR-comment surface in standard mode.

---

## 2. Anti-pattern table

| Rationalization | Why it's wrong | Correct tier |
|---|---|---|
| "Documentation gap is MEDIUM because docs matter" | LOW unless the missing doc directly causes a defect (e.g., undocumented BREAKING change in a public API → HIGH). General doc polish never exceeds LOW. | LOW |
| "PR description should mention X — that's a MEDIUM" | PR-description verbosity is process feedback, not a code defect. Reviewers do not block merge on prose. | LOW |
| "Naming convention drift is MEDIUM because consistency matters" | Naming is style. The `conventions` dim's mandate is to flag it, not block merge on it. | LOW |
| "Missing test coverage is HIGH because tests matter" | HIGH only if the uncovered path has a documented failure mode that this PR could trigger. Otherwise MEDIUM (verifiable defect risk) or LOW (theoretical gap). | MEDIUM or LOW |
| "Performance suggestion is HIGH because it might be slow" | HIGH requires a measured threshold per `optimizations-criteria.md` (>100 items, >1000 rows, >100KB). Below that: MEDIUM. Untested: LOW. | depends |
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

### guidelines
- CRITICAL: never (guidelines findings are by nature style/convention)
- HIGH: never
- MEDIUM: Convention drift on a tooling-load-bearing field (e.g., missing `name:` in a SKILL.md frontmatter that the loader requires)
- LOW: Style / formatting / naming polish; documentation gaps; comment wording

### conventions
- CRITICAL: never (per `conventions-criteria.md` §Severity Guidelines)
- HIGH: clear ≥80% modal violation in [NEW] code that introduces a pattern the repo uses nowhere else (zero-shot novel), or crosses a 100%-respected module/layer boundary
- MEDIUM: ≥80% modal violation in [NEW] code where the introduced pattern exists in 1-2 other places; any [PRE-EXISTING] finding regardless of frequency
- LOW: not emitted (per `conventions-criteria.md`; the dim suppresses sub-threshold rather than down-tagging)

---

## 4. Confidence — advisory, not load-bearing

The reviewer-agent emits `Confidence: XX%` (0-100). This is an advisory hint about reviewer self-rated certainty. It is NOT the load-bearing filter — see §5.

Documented limits of LLM-self-reported confidence:

- "Overconfidence is Key" (arXiv 2405.02917): Claude family is the worst-case for verbalized calibration; "80%" is closer to 55-60% true-positive rate.
- Greptile production data ("How to make LLMs shut up"): LLM self-rating "nearly random"; threshold filtering didn't work; replaced with embedding feedback.
- "On Verbalized Confidence Scores" (arXiv 2412.14737): coarse-grained labels don't outperform percentages on calibration but are more robust to modal collapse.

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

The orchestrator's Phase 4.1 KEEP/DEFER decision is governed by FOUR independent signals — any one passing keeps the finding. Documented at `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` §4.1.

```
KEEP IF:
  severity >= MEDIUM
  AND (
    convergence_count >= 2                                                # multi-dim agreement
    OR (Evidence-Block present AND properly formatted AND confidence >= 60)  # code-grounded citation
    OR (criteria-file-marked-pre-resolved, e.g. simplify P1/P2)           # explicit overrides
    OR confidence >= 80                                                   # advisory fallback
  )
ELSE DEFER to ## Deferred — sub-threshold (state.md body, NOT PR comment)
```

Additional admission constraint for MEDIUM: a MEDIUM finding requires signal #2 specifically (Evidence-Block present + properly formatted). Signals #1, #3, #4 alone admit CRITICAL and HIGH but NOT MEDIUM — Loop Invariant #6 in `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` mandates Evidence at CRITICAL / HIGH / MEDIUM, so a MEDIUM without Evidence-Block drops to `## Deferred — sub-threshold` regardless of convergence or confidence score.

Tier-aware behavior: standard tier uses signal #4 as written (confidence ≥ 80). High tier (`risk-tier: high`) relaxes signal #4 to `confidence ≥ 70`. Other signals (convergence, Evidence-Block, pre-resolved) unchanged across tiers. `--tdd` flag does not affect §4.1 admission — it only affects §4.2 verifier scope.

Rationale:

- `convergence_count >= 2`: cross-dim convergence is a stronger signal than any single dim's self-rated confidence (k-review pattern; Mozilla AI Star Chamber; arXiv 2403.14274 +13.48% precision on vuln detection)
- `Evidence-Block resolves` (with confidence ≥ 60 floor): code-grounded citation is the documented FP mitigation (arXiv 2411.03079); the floor screens low-conviction citations
- Pre-resolved markers: explicit overrides preserve existing simplify P1/P2 / regressions-criteria signal-table semantics
- Confidence >= 80: kept as a fallback path, no longer the primary gate

The Phase 4.2 per-finding verifier is the disproof step on every §4.1 survivor — CRITICAL, HIGH, AND MEDIUM (Anthropic's plugin pattern: "attempts to disprove each finding").

---

## 6. Per-dim calibration variants

Per-dim criteria files MAY TIGHTEN this rubric (e.g., `conventions-criteria.md` caps at HIGH and suppresses LOW; `simplify-criteria.md` maps P1/P2/P3 to HIGH/MEDIUM/dropped) but MUST NOT LOOSEN it. Specifically:

- A criteria file MUST NOT classify documentation / PR-description / cosmetic suggestions above LOW
- A criteria file MUST NOT widen CRITICAL beyond the §1 inclusion list
- A criteria file MAY add dim-specific HIGH/MEDIUM signals (e.g., regressions: deleted-symbol caller-blast → HIGH; optimizations: >1000 rows → HIGH)

When a per-dim file specializes severity, it MUST cite §1 above as the canonical taxonomy and document only the dim-specific specialization — not redefine the tiers.

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Severity levels + §Confidence Scoring — agent-side rubric pointers here
- `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` §4.1 — multi-signal Phase 4.1 gate consumer
- `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-verification-reference.md` — per-finding verifier (disproof step on every §4.1 survivor)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md` — Cause taxonomy ([ROOT-CAUSE] / [SYMPTOM] / [UNKNOWN])
- "Overconfidence is Key", arXiv 2405.02917 — Claude verbalized-confidence calibration limits
- "On Verbalized Confidence Scores", arXiv 2412.14737 — coarse-grained vs percentage calibration
- "k-review precision uplift", arXiv 2403.14274 — convergence as a stronger signal than self-rating
- "Code-grounded citation as FP mitigation", arXiv 2411.03079 — evidence as a filter signal
- Greptile, "How to make LLMs shut up" — production data on self-rating threshold failure
