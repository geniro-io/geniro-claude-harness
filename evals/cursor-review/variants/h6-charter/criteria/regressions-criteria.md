# Regressions review criteria


Find unintended behavior changes and deletions relative to the change's stated intent.

## Common false positives

Two false-positive classes route to other dims rather than being suppressed here:

- **Behavior shifts in surviving (non-deleted) symbols whose callers are silently exposed to new semantics.** Belongs to `architecture-criteria.md` §1.5 (Caller-Blast Check for Semantic Mutations). This dim covers the inverse: callers of DELETED symbols.
- **Diff OMITS items the spec promised.** Belongs to `spec-compliance-criteria.md` (when fires). This dim covers the inverse: the diff EXCEEDS the spec.
- **Cause-path comparison for deleted tests vs. outcome-matching surviving tests.** Belongs to `tests-criteria.md` §"Test Deletions in the Diff (Inverse Deletion Test)". This dim emits the higher-level "test deleted, production stayed" signal; that section handles the cause-path nuance.
- **Cross-round PR-body vs. diff drift.** Belongs to `pr-metadata-criteria.md` §11 (Description ↔ Code Drift on Re-Review). This dim covers the broader diff-vs-stated-intent direction across all intent sources, not just the PR body across rounds.

When two dims have legitimate overlap on the same hunk, both emit. The consuming skill's filter and stratify steps collapse only same-finding duplicates, so orthogonal findings on the same hunk both survive deduplication.


