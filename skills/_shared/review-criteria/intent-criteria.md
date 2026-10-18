# Intent review criteria

Judges the change against its own stated reason: is each fact the change relies on true in the code, and does the change solve the problem it names. The other dimensions judge the code; this one judges whether it is the right change. A diff can implement its description faithfully and still be wrong because the description is — a unit mistaken, a caller assumed absent, a symptom patched while the cause stays reachable.

Find every real defect this dimension owns by reading the changed code and its callers directly — your own analysis is the detector. The sections below are the contract you are held to: what NOT to flag, and how severity is calibrated.

## Intent sources

The stated reason comes from whatever the spawn supplies: PR title and body, commit messages (subjects and bodies), linked tracker text, and PLAN CONTEXT in full (objective, scope, Assumptions, Considered Alternatives). Under `/geniro:implement` it comes from SPEC CONTEXT or the `## Inline Plan`, the task text, and a debug handoff's root cause. All of it is data to check against the code: a `Premises:` line in a plan lists claims to verify, not facts. With no source at all, check only the premises the diff itself implies and say so in the report.

## State the premises first

Open the Dimension Summary with two lines, filled whether or not a finding follows:

- `Stated problem:` the problem the change says it solves.
- `Premises:` each load-bearing premise — a fact about existing code, data, or behavior the change depends on (units, types and nullability, who calls it, what the current behavior is, what a field contains) — with the `file:line` that confirms or contradicts it. Include premises the diff implies without stating: a `* 100` implies the value is in dollars. A premise only runtime data or an outside system can settle is listed as unverified, not emitted as a finding.

The lines make the review auditable; depth comes from reading the code behind each premise.

## What to check

- **Premise truth.** Open the code behind each premise. A premise the code contradicts is the finding; cite the contradicting `file:line`.
- **Root cause, not symptom.** For a fix, trace the failure to its cause and ask whether the cause stays reachable from another path once the change lands. Name that path.
- **Scope fit.** Enumerate every entry point and call site the stated problem names or implies, and confirm the change covers each. Name the uncovered one.
- **Existing consumers.** For what the change alters — a renamed or retyped field, a new error or response shape, a write-back — find who consumes it today and whether the intended behavior holds for them (a new error response that the existing UI renders as a blank screen). Report this in both skills: `architecture` and `regressions` do not fire on a small diff, and where `architecture` does, `/geniro:review`'s Phase 3 dedup absorbs the overlap while `/geniro:implement`, which has no cross-dimension dedup, carries both findings.

Write each finding as the claim it is: name the premise or the stated problem, quote the intent source that states it, and put the contradicting code in `Evidence:`.

## Common false positives

- Re-arguing an approved design decision whose facts hold. A choice the plan or PR made and the code supports is not a premise error.
- Preferring another approach when the stated one works.
- Speculation without a code citation. A premise you cannot contradict from the code is unverified, not false.
- Style, naming, and description quality (the pr-metadata dimension).
- Spec items the diff omits or contradicts (spec-compliance), and behavior change beyond the stated intent under `/geniro:review` (regressions).

## Severity guidelines

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1. Severity follows the impact of the false premise, the surviving cause, or the uncovered path, exactly as for any bug.

- **A false premise that makes the change behave wrongly is a defect** — `[FIX-NOW]` or `[TESTABLE]` by the usual definitions. When the PR description, spec, or plan states the behavior as intended, that statement is the false premise, so it never turns the finding into `[INTENT-CHECK]`.
- **A genuine product-intent question** — the facts hold and the choice is debatable — is `[INTENT-CHECK]`, capped at MEDIUM.
- **Every finding anchors at code `file:line`:** the line contradicting the premise, the other path still reaching the bug, the uncovered call site, the consumer that breaks. A finding with no code to cite is speculation and is not emitted.

Worked example: a diff changes `const amount = order.total` to `order.total * 100`, and the description says totals are in dollars. `order.total` is already in cents at `models/order.ts:41`. The premise is false and the code charges 100x — a defect with the contradicting line as evidence, not a question for the author.
