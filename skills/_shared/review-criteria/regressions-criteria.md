# Regressions review criteria

Defect-class audit for **unintended damage** introduced by the diff: production symbols deleted without paired caller updates, behavior changes that exceed the stated scope of the PR / spec / commit, and tests removed for production code that survives. Diff-anchored — fires on every review run, regardless of whether PLAN CONTEXT is attached. The dim owns the inverse-direction questions that other dims do not: `architecture` covers blast radius of surviving symbols whose behavior shifts; this dim covers callers of symbols the diff deleted. `spec-compliance` covers spec items the diff omits; this dim covers diff hunks that exceed the spec. `tests` Inverse Deletion Test covers cause-path coverage when a test is deleted; this dim covers the higher-level signal that a test vanished while its production target stayed.

When intent sources (a spec.md, a PR ref, or a tracker ticket) are absent, behavior-mutating hunks degrade to INTENT-CHECK decision-type rather than HIGH findings, surfacing the question to the user instead of suppressing it.

## Contents

- What to Check
- Output Format
- Common false positives
- Severity Tagging
- Anti-rationalization
- Reference notes

---

## What to Check

Inputs available to your review:

- `DIFF CONTEXT:` — the full unified diff with hunk headers. Required.
- `PLAN CONTEXT:` — spec.md content if any. May be `none`.
- `LINEAR CONTEXT:` — Linear ticket body and parent-epic body when workflow integration fetched them. May be `none`.
- `PEER-PR CONTEXT:` — similar sibling PR diffs. Optional; used only to disambiguate "intentional split across PRs" cases in §2.
- PR metadata (pr.body / pr.title / commit messages) flows via the `pr-metadata` reviewer's existing context channel; regressions reviewer reads it via the same channel when fired on a PR ref.
- Working-tree access via Bash (read-only `grep` / `rg`) for caller searches in §1.

### 1. Symbol-deletion with caller-blast

Scan the diff for hunks that DELETE production symbols. Targets:

- Function / method declarations (`function foo`, `def foo`, `fn foo`, `func foo`, `foo() {`).
- Class fields and methods (`public foo`, `static foo`, `this.foo =`).
- Type declarations and exported aliases (`type Foo`, `interface Foo`, `class Foo`, `enum Foo`).
- Conditional branches whose existence other code may rely on (`else if (...) { ... }` removed when callers expect the branch outcome).
- Whole-file deletions outside `**/test/`, `**/tests/`, `**/__tests__/`, `**/*.{test,spec}.*` (those route to §3).

For each deleted symbol:

1. Search the diff's ADDITION hunks for any reference to the symbol — if the same name appears in additions, the diff is renaming or relocating it; cross-check whether the relocation is complete.
2. Search the working tree (read-only) for surviving callers of the deleted symbol — the project's code-search tooling (a code index returns the dependents directly when one is configured; otherwise a whole-word, files-with-matches search), scoped to the project's language files. For TypeScript / JavaScript: `**/*.{ts,tsx,js,jsx}`. For Python: `**/*.py`. For Go: `**/*.go`. Match the project's primary language list.
3. For each surviving caller path, verify it is NOT modified in the current diff (compare against the diff's changed-files list). Surviving cross-file callers in unchanged files are the high-confidence regression signal.
4. Flag as a finding with `File:` anchored at the deletion site, body quoting the deleted hunk AND the surviving caller `path:line`, and `Suggested fix:` naming either "restore the symbol" or "update caller at `<path:line>` to use `<replacement>`".

**Example trigger.** Diff deletes `export function calculateTax(amount: number): number` at `src/billing/tax.ts:42`. Grep returns 3 surviving callers in `src/checkout/order.ts:118`, `src/admin/refund.ts:67`, `src/reports/quarterly.ts:204`, none of which appear in the diff's changed-files list. Emit HIGH finding: import will fail to resolve in 3 untouched files.

**Example skip.** Diff deletes a private helper `function normalizeInternal()` at `src/utils/helpers.ts:88`. Grep returns zero surviving callers. No finding — deletion is internal cleanup.

### 2. Intent-vs-behavior over-reach

Read the available intent sources and extract the STATED scope of the change.

Sources, in precedence order:

1. PLAN CONTEXT — spec section 1 (Objective) and section 2 (Scope — Included) when schema-tagged; otherwise the spec's lead paragraph and any explicit scope statements.
2. PR title and body, especially `## Summary` / `## Changes` sections (via the pr-metadata reviewer's context channel).
3. Commit messages from the diff's commit list.

If all three are absent or empty, set `stated_intent = none` and apply the fallback at the end of this section.

For each behavior-mutating hunk in the diff, classify as INTENDED (matches stated scope) or UNINTENDED (exceeds stated scope).

Behavior-mutating hunks (the candidate set):

- Conditional flips (`==` ↔ `!=`, `&&` ↔ `||`, `if` / `else` branches swapped).
- Return-value changes (default value flipped, return type changed, `null` ↔ throw, `false` ↔ `undefined`).
- Operator changes (`+` ↔ `-`, `*` ↔ `/`, `>` ↔ `>=`, regex tightening / loosening).
- Default-argument shifts (function signature default value changed).
- Removed input validation or removed early-return guards.
- Reordering that affects side-effect order (logging, mutation, async call sequence).
- New conditional branches added to previously-total functions.

For each hunk:

1. Match against the stated intent. Keywords from the intent map to identifiers / file paths / behavioral phrases in the hunk.
2. If the hunk's behavior change is named in the intent (verbatim or via clear paraphrase), classify INTENDED; no finding.
3. If the hunk's behavior change is NOT named in the intent but the stated intent EXISTS, classify UNINTENDED with `Decision Type: PRODUCT-DECISION`, severity HIGH. The diff overreaches the contract.
4. If `stated_intent = none`, classify INTENT-CHECK with severity MEDIUM. Quote the hunk and ask whether the change was intentional.

**Example trigger (stated intent exists).** PR body says "Fix off-by-one in pagination offset calculation"; diff also changes the default sort direction from `asc` to `desc` in the same handler. The sort-direction change is unrelated to the stated fix. Emit HIGH finding, decision-type PRODUCT-DECISION: scope creep; the sort change needs its own justification or a separate PR.

**Example trigger (no stated intent).** Local diff (no spec, no PR body, single-commit message "wip"); diff flips `===` to `==` in a validation helper. Emit MEDIUM finding, decision-type INTENT-CHECK: quote the flip, ask whether the equality loosening was intentional, name the 2-3 surviving callers whose behavior shifts.

### 3. Test-coverage delta

Scan the diff for deleted or renamed test artifacts:

- Test files removed (whole-file deletion under `**/*.{test,spec}.*`, `**/__tests__/**`, `tests/**`, `spec/**`, language-equivalent test directories).
- Individual test blocks removed (`-` lines opening `it(...)`, `test(...)`, `describe(...)`, `def test_...`, `@Test`, `func TestXxx`, `it.each(...)`, `test.each(...)`).

For each deletion:

1. Read the deleted test's body verbatim from the diff (the `-` lines carry the full removed block).
2. Identify the production symbol the test covered. Cues: explicit `import` / `require` paths in the test file, function names invoked in the test body, mocked module paths, the test's own name when it references a production symbol.
3. Check the diff's changed-files list — does the corresponding production symbol survive (not deleted by the same diff)?
4. If production survives but its test is deleted, emit HIGH finding: coverage regression. `Suggested fix:` either restore the test, OR document in the PR body why the behavior the test pinned is no longer worth asserting.
5. If production is also deleted alongside the test (both sides agree), emit LOW informational note OR skip. Cross-check §1 — if the production deletion has surviving callers, that's the higher-priority finding; the test deletion follows logically.

**Example trigger.** Diff deletes `test/billing/tax.test.ts` (whole file). Diff retains `src/billing/tax.ts` with `calculateTax` and `applyDeduction` exports. Production survives; test is gone. Emit HIGH finding: coverage regression on the billing module.

**Example skip.** Diff deletes both `src/feature-x/handler.ts` and `test/feature-x/handler.test.ts`. Production gone; test gone. Cross-check §1 for handler callers; emit the §1 finding (if any) and skip the §3 finding — paired deletion is consistent.

For deeper cause-path analysis of WHICH scenario the deleted test was pinning (vs. an outcome-matching surviving test), defer to `tests-criteria.md` §"Test Deletions in the Diff (Inverse Deletion Test)". This dim emits the higher-level "test deleted, production stayed" signal; that section handles the cause-path nuance when both dims fire on the same deletion.

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

### 5. Regression provenance

When §1 (symbol-deletion), §2 (intent-vs-behavior), or §4 (parallel-path symmetry) fires on a hunk that touches code the current PR didn't author, attach provenance — keep these five roles separate so the finding routes to the right human:

- **Blamed code author** — `git log -L`/`git blame` for the affected line; the original author of the surviving (or recently deleted) code.
- **Blamed PR author** — the PR that introduced the blamed line, resolved via `gh pr list --state merged --search "<commit-sha>"` or equivalent.
- **PR merger / committer** — who landed the blamed PR (may differ from the author when CODEOWNERS or maintainers merge).
- **Current PR author** — who wrote the regression-introducing diff under review now.
- **Automation trigger** — the human who armed the merge if the merger account is a bot (see below).

For each finding that needs provenance:

1. Run `git blame -L <line>,<line> -- <path>` on the affected hunk; record the blamed commit SHA.
2. Resolve the blamed commit to its merge PR via `gh` (or the local equivalent) — record `Provenance-PR: #<number>` with PR author and merger.
3. If no merge PR is traceable (commit landed directly on the base branch), fall back to the blamed commit: `Provenance-commit: <SHA> by @<username> on <date>`. Do not guess a merger when none exists; do not raise the missing PR metadata as a separate finding.
4. If the merger is an automation account (`*[bot]`, e.g. `dependabot[bot]`, `claude[bot]`, `clawsweeper[bot]`), identify the human trigger when practical: scan PR timeline / comments for maintainer commands such as `@<bot> automerge`, `/landpr`, or labels / status comments that armed automerge. Report `Automerge-triggered-by: @<login>`; if no human trigger is locatable, report `Automerge-triggered-by: trigger unknown`.
5. Attach the resolved provenance to the finding's body under a `Provenance:` field — not as a separate finding.

**Example trigger.** §1 fires on a deleted `parseFlag()` export. `git blame` on the deletion site shows the line was last touched in commit `a1b2c3d` by `@alice`, merged via PR #482 (author `@bob`, merger `@dependabot[bot]`). Scanning PR #482 timeline shows `@maintainer-carol` commented `/landpr` 3 minutes before merge. Attach `Provenance-PR: #482 author @bob merger @dependabot[bot] automerge-triggered-by @maintainer-carol` to the finding.

**Example skip.** Hunk only touches lines the current PR added (no pre-existing code blamed). Skip provenance — the current PR author owns the finding.

## Output Format

Emit findings in the standard reviewer-agent output format defined in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format. Per-finding fields:

- `File:` — `path:line` anchored at the deletion site (for §1 and §3), at the behavior-mutating hunk (for §2), or at the edited path (for §4). When the finding cites a caller or unedited sibling in an unchanged file, name BOTH the anchor site and the cited path in the body — the `File:` anchor stays at the deletion / edited site.
- `Severity:` — CRITICAL / HIGH / MEDIUM / LOW per the rubric in §Severity Tagging.
- `Criteria:` — short label naming the specific check from this file. Suggested values: `Symbol-deletion + caller-blast` (§1) / `Intent-vs-behavior over-reach` (§2) / `Test-coverage delta` (§3) / `Parallel-path symmetry` (§4) / `Regression provenance` (§5).
- `Evidence:` — quote the deleted hunk verbatim AND cite the surviving caller / surviving production / quoted intent fragment. The reader must be able to reproduce the finding from `Evidence:` alone.
- `Why this matters:` — name the downstream consequence (compile failure, runtime error, silent behavior change, coverage regression).
- `Suggested fix:` — concrete next step (update caller at `<path:line>`, restore deleted block, add test, narrow intent, etc.).
- `Decision Type:` — FIX-NOW for §1 and §3; INTENT-CHECK for §2 when intent sources are absent or ambiguous; PRODUCT-DECISION for §2 when stated intent EXISTS and the diff contradicts it. INTENT-CHECK for §4 mirror-gaps.
- `Confidence:` — 0-100 numeric. Heuristic — ≥80 when caller-grep returns unambiguous downstream references and the deleted symbol has no rename/move match in the diff; 60-79 when callers were checked in a single language scope only; 40-59 when the caller-grep was partial or the intent classification rests on inference rather than explicit statement.
- `Provenance:` — present only when §5 applies; the resolved 5-role attribution per §5. Carries `Provenance-PR: #<num> author @<login> merger @<login>` OR `Provenance-commit: <SHA> by @<login> on <date>` as appropriate; bot merger gets the `automerge-triggered-by: @<login | trigger unknown>` suffix.

## Common false positives

Two false-positive classes route to other dims rather than being suppressed here:

- **Behavior shifts in surviving (non-deleted) symbols whose callers are silently exposed to new semantics.** Belongs to `architecture-criteria.md` §1.5 (Caller-Blast Check for Semantic Mutations). This dim covers the inverse: callers of DELETED symbols.
- **Diff OMITS items the spec promised.** Belongs to `spec-compliance-criteria.md` (when fires). This dim covers the inverse: the diff EXCEEDS the spec.
- **Cause-path comparison for deleted tests vs. outcome-matching surviving tests.** Belongs to `tests-criteria.md` §"Test Deletions in the Diff (Inverse Deletion Test)". This dim emits the higher-level "test deleted, production stayed" signal; that section handles the cause-path nuance.
- **Cross-round PR-body vs. diff drift.** Belongs to `pr-metadata-criteria.md` §11 (Description ↔ Code Drift on Re-Review). This dim covers the broader diff-vs-stated-intent direction across all intent sources, not just the PR body across rounds.

When two dims have legitimate overlap on the same hunk, both emit. The consuming skill's filter and stratify steps collapse only same-finding duplicates, so orthogonal findings on the same hunk both survive deduplication.

## Severity Tagging

| Signal | Condition | Severity |
|---|---|---|
| Symbol deletion with surviving cross-file callers | Caller in unchanged file references the deleted symbol | HIGH — compile / import failure on the call path |
| Symbol deletion with only same-file callers updated; cross-file callers not verified | Grep returned partial results OR was skipped for time | MEDIUM — could break consumers in this repo or sibling packages |
| Symbol deletion of a public API / module export / shared type | Symbol is exported (`export`, `module.exports`, public method on a class consumed externally) | CRITICAL — downstream packages or consumer repos break without source-side warning |
| Behavior change outside stated intent; intent source EXISTS | Spec / PR body / commit message names intent; hunk is unrelated | HIGH, PRODUCT-DECISION |
| Behavior change outside stated intent; intent source ABSENT | No spec, no PR body, no descriptive commit | MEDIUM, INTENT-CHECK |
| Test deleted; production survives | Test removed in diff; production file / symbol persists | HIGH — coverage regression |
| Test deleted alongside production (both removed) | Test and production removed in same diff | LOW informational OR skip; defer to §1 for the caller-blast finding |
| Conditional branch removed with surviving callers relying on the branch outcome | Diff drops an `else if` / `case` arm; grep shows callers asserting on the removed outcome | HIGH |
| Guard / replacement / cleanup added on one path; sibling parallel path left untreated | Sibling shares the invariant and is not touched by the diff | HIGH when the gap causes data loss / corruption on the untreated path; MEDIUM when it degrades gracefully |

The rubric is additive — a single hunk can trigger multiple rows (e.g., a deleted public API with no test replacement triggers CRITICAL for §1 AND HIGH for §3). Emit both findings; do not merge.

## Anti-rationalization

| Reasoning the model might generate | Why that reasoning is wrong + what to do instead |
|---|---|
| "The deletion is obvious cleanup — skip the finding without grepping callers." | Cleanup intent is not visible from the deletion site alone; only the caller grep tells you whether downstream is broken. Run the grep. If callers exist in unchanged files, emit the finding regardless of how clean the deletion looks. |
| "There's no spec.md, so I can't classify behavior changes as in-scope or out-of-scope; skip the dim." | Spec-less changes are the highest-risk regression class. When no intent source exists, default every behavior-mutating hunk to INTENT-CHECK at MEDIUM severity. The user resolves at the open-question gate; silently passing the hunk strips them of that decision. |
| "Symbol-deletion blast radius is the architecture dim's job — skip it here." | `architecture-criteria.md` §1.5 covers blast radius of NON-deleted symbol changes (operator flips, return-value shifts in surviving code). Deleted-symbol caller blast is a distinct defect class with a different fix shape (restore vs. update caller vs. document migration). Both dims can fire; do not skip. |
| "The PR body says 'minor refactor only' — that licenses the behavior change in this hunk." | "Minor refactor only" is intent narrative, not a license. A behavior-mutating hunk under a "refactor only" body is a contradiction between the stated intent and the diff — that IS the finding. Severity HIGH, decision-type PRODUCT-DECISION; the author must either narrow the diff or revise the body. |
| "The deleted test was clearly redundant — same outcome as a surviving test." | Outcome match is not coverage match. Two tests asserting `expect(x).toBeNull()` can pin distinct cause paths. Emit the §3 finding when production survives; the cause-path verification belongs to `tests-criteria.md` §Inverse Deletion Test and routes from your finding via Phase 3 filter. |
| "The fix only touched the sync path; the weekly path is out of scope for this diff." | If the diff changed a guard / filter / replacement on one path, every parallel path sharing the same invariant IS in scope — an asymmetric edit IS the regression (the asymmetric-edit data-loss class — fix one branch of a cadence/type split, leave the mirror branch in the old behavior). Grep the enclosing module for the sibling symbol and verify the same treatment landed there; a sibling left untreated is the mirror-gap finding. |

## Reference notes

- Reviewer output format: `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format.
- Spawn-prompt input inlining (DIFF / PLAN / LINEAR / PEER-PR slots): `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-2-spawns.md` §2.3.
- Dedup + stratify pipeline: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-3-4-filter-stratify.md` §3.1 (dedup key) and §4.1 (admission).
- Cause-path comparison for deleted tests: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md` §"Test Deletions in the Diff (Inverse Deletion Test)".
- Caller-blast for surviving symbols: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/architecture-criteria.md` §1.5.
