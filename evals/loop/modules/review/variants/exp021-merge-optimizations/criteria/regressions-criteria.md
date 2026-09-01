# Regressions review criteria

Defect-class audit for **unintended damage** introduced by the diff: production symbols deleted without paired caller updates, behavior changes that exceed the stated scope of the PR / spec / commit, and tests removed for production code that survives. Diff-anchored — fires on every review run, regardless of whether PLAN CONTEXT is attached. The dim owns the inverse-direction questions that other dims do not: `architecture` covers blast radius of surviving symbols whose behavior shifts; this dim covers callers of symbols the diff deleted. `spec-compliance` covers spec items the diff omits; this dim covers diff hunks that exceed the spec. `tests` Inverse Deletion Test covers cause-path coverage when a test is deleted; this dim covers the higher-level signal that a test vanished while its production target stayed.

Find every real defect this dimension owns by reading the changed code and its callers directly — your own analysis is the detector. The sections below are the contract you are held to: what NOT to flag, and how severity is calibrated.

## Contents

- The mirror-gap signal — §4 Parallel-path symmetry
- Common false positives
- Severity tagging — the four signals: deleted-symbol caller-blast, intent-vs-behavior over-reach, test-coverage delta, parallel-path symmetry
- Anti-rationalization

## The mirror-gap signal

Kept in full: `architecture-criteria.md` §1.6 and `severity-calibration.md` cite this procedure by number.

### 4. Parallel-path symmetry (mirror-gap)

When the diff adds or changes a guard / filter / cleanup / replacement on ONE code path, verify the same treatment was applied to every sibling path that shares the invariant. The defect class is an asymmetric edit: path A gets the new guard, the structurally parallel path B is left in the old behavior, and the gap is invisible at A's diff site. Common parallel-path pairs: scheduled vs. on-demand (sync ↔ weekly / cron ↔ manual trigger), delete vs. replace (a row removed on one branch must be re-created on the mirror branch — delete-without-replacement), cascade vs. single-row wipe, create vs. reclaim, encode vs. decode, serialize vs. deserialize.

For each guard / filter / replacement / cleanup the diff adds or modifies:

1. Name the invariant the change enforces (e.g., "every deleted weekly row is replaced", "superseded records are synced, not dropped").
2. Identify sibling paths that share the invariant. Cues: a sibling function in the same module with a parallel name (`syncWeekly` ↔ `syncDaily`, `reclaim` ↔ `release`); a `switch` / `if` arm adjacent to the changed arm; a caller that dispatches to N variants where only one variant was edited. Search the enclosing module (read-only) for the sibling symbol stem with the project's code-search tooling, scoped to the project's language files (e.g., `**/*.{ts,tsx,js,jsx}` / `**/*.py` / `**/*.go`).
3. For each sibling path, check the diff: was the same guard / replacement applied there? If a sibling shares the invariant but the diff does NOT touch it, that is the mirror gap.
4. Flag as a finding anchored at the EDITED path, body naming the unedited sibling `path:line` and the invariant it now violates. `Suggested fix:` "apply the same <guard|replacement|cleanup> at <sibling-path:line>".

**Sweep before closing.** When step 3 confirms one mirror gap, do not stop at the single sibling — enumerate ALL sibling paths in the enclosing module / switch / dispatch table that share the invariant, and check each. A point-fix on one sibling while paths C and D of the same class stay broken reproduces the original asymmetry one level down.

**Example trigger.** Diff adds a replacement-insert after a row delete in `syncDaily()` at `src/sync/daily.ts:88`. The module also has `syncWeekly()` at `src/sync/weekly.ts:91` which deletes the same row class but the diff does NOT add the replacement there. Emit HIGH finding, decision-type INTENT-CHECK: weekly path deletes without replacement — mirror gap; data loss on the weekly schedule.

**Example skip.** Diff adds a guard to `parseUserInput()`; the only sibling `parseAdminInput()` already had the guard before this diff (grep the working tree confirms the guard line is present and unchanged). No finding — symmetry already holds.

## Common false positives

Two false-positive classes route to other dims rather than being suppressed here:

- **Behavior shifts in surviving (non-deleted) symbols whose callers are silently exposed to new semantics.** Belongs to `architecture-criteria.md` §1.5 (Caller-Blast Check for Semantic Mutations). This dim covers the inverse: callers of DELETED symbols.
- **Diff OMITS items the spec promised.** Belongs to `spec-compliance-criteria.md` (when fires). This dim covers the inverse: the diff EXCEEDS the spec.
- **Cause-path comparison for deleted tests vs. outcome-matching surviving tests.** Belongs to `tests-criteria.md` §"Test Deletions in the Diff (Inverse Deletion Test)". This dim emits the higher-level "test deleted, production stayed" signal; that section handles the cause-path nuance.
- **Cross-round PR-body vs. diff drift.** Belongs to `pr-metadata-criteria.md` §11 (Description ↔ Code Drift on Re-Review). This dim covers the broader diff-vs-stated-intent direction across all intent sources, not just the PR body across rounds.

When two dims have legitimate overlap on the same hunk, both emit. The consuming skill's filter and stratify steps collapse only same-finding duplicates, so orthogonal findings on the same hunk both survive deduplication.

## Severity tagging

| Signal | Condition | Severity |
|---|---|---|
| Symbol deletion with surviving cross-file callers | Caller in unchanged file references the deleted symbol | HIGH — compile / import failure on the call path |
| Symbol deletion with only same-file callers updated; cross-file callers not verified | Grep returned partial results OR was skipped for time | MEDIUM — could break consumers in this repo or sibling packages |
| Symbol deletion of a public API / module export / shared type | Symbol is exported (`export`, `module.exports`, public method on a class consumed externally) | CRITICAL — downstream packages or consumer repos break without source-side warning |
| Behavior change outside stated intent; intent source EXISTS | Spec / PR body / commit message names intent; hunk is unrelated | HIGH, PRODUCT-DECISION |
| Behavior change outside stated intent; intent source ABSENT | No spec, no PR body, no descriptive commit | MEDIUM, INTENT-CHECK |
| Test deleted; production survives | Test removed in diff; production file / symbol persists | HIGH — coverage regression |
| Test deleted alongside production (both removed) | Test and production removed in same diff | LOW informational OR skip; defer to the deleted-symbol caller-blast signal above |
| Conditional branch removed with surviving callers relying on the branch outcome | Diff drops an `else if` / `case` arm; grep shows callers asserting on the removed outcome | HIGH |
| Guard / replacement / cleanup added on one path; sibling parallel path left untreated | Sibling shares the invariant and is not touched by the diff | HIGH when the gap causes data loss / corruption on the untreated path; MEDIUM when it degrades gracefully |

The rubric is additive — a single hunk can trigger multiple rows (e.g., a deleted public API with no test replacement triggers CRITICAL for the deleted-symbol caller-blast signal AND HIGH for the test-coverage delta signal). Emit both findings; do not merge.

## Anti-rationalization

| Reasoning the model might generate | Why that reasoning is wrong + what to do instead |
|---|---|
| "The deletion is obvious cleanup — skip the finding without grepping callers." | Cleanup intent is not visible from the deletion site alone; only the caller grep tells you whether downstream is broken. Run the grep. If callers exist in unchanged files, emit the finding regardless of how clean the deletion looks. |
| "There's no spec.md, so I can't classify behavior changes as in-scope or out-of-scope; skip the dim." | Spec-less changes are the highest-risk regression class. When no intent source exists, default every behavior-mutating hunk to INTENT-CHECK at MEDIUM severity. The user resolves at the open-question gate; silently passing the hunk strips them of that decision. |
| "Symbol-deletion blast radius is the architecture dim's job — skip it here." | `architecture-criteria.md` §1.5 covers blast radius of NON-deleted symbol changes (operator flips, return-value shifts in surviving code). Deleted-symbol caller blast is a distinct defect class with a different fix shape (restore vs. update caller vs. document migration). Both dims can fire; do not skip. |
| "The PR body says 'minor refactor only' — that licenses the behavior change in this hunk." | "Minor refactor only" is intent narrative, not a license. A behavior-mutating hunk under a "refactor only" body is a contradiction between the stated intent and the diff — that IS the finding. Severity HIGH, decision-type PRODUCT-DECISION; the author must either narrow the diff or revise the body. |
| "The deleted test was clearly redundant — same outcome as a surviving test." | Outcome match is not coverage match. Two tests asserting `expect(x).toBeNull()` can pin distinct cause paths. Emit the test-coverage delta finding when production survives; the cause-path verification belongs to `tests-criteria.md` §"Test Deletions in the Diff (Inverse Deletion Test)" and routes from your finding via Phase 3 filter. |
| "The fix only touched the sync path; the weekly path is out of scope for this diff." | If the diff changed a guard / filter / replacement on one path, every parallel path sharing the same invariant IS in scope — an asymmetric edit IS the regression (the asymmetric-edit data-loss class — fix one branch of a cadence/type split, leave the mirror branch in the old behavior). Grep the enclosing module for the sibling symbol and verify the same treatment landed there; a sibling left untreated is the mirror-gap finding. |

