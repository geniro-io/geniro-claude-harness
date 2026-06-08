# TDD Mode Reference

TDD mode is an opt-in variant of `/geniro:review` that is **purely additive**. It runs the full Standard review — every kept finding is reported and posted exactly as in Standard mode — and, on top of that, auto-authors failing tests for the findings a test can reproduce (Phase 4.3), tags those findings `[CONFIRMED-BY-TEST]` with a `**Failing test:** <path>` line, and offers to commit + push the authored tests to the reviewed branch. TDD never removes a finding from the report or the PR post set; it only adds test evidence. It does NOT change the Phase 4.3 safety invariant — the skill MUST `AskUserQuestion` before spawning `adversarial-tester-agent` in every mode. Mode flips defaults, never gates.

**Cycle procedure body lives in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md`** (single source of truth for RED → GREEN → REFACTOR, the state-file contract, and the PreToolUse hook enforcement). This file's scope is the review-specific framing — which findings are eligible for failing-test authoring and the edge cases. When `adversarial-tester-agent` authors a failing test for a seeded finding (Phase 4.3 Step 3), the test-authoring procedure follows the canonical cycle in tdd-cycle.md — this file does NOT re-state the RED/GREEN/REFACTOR steps.

## What TDD mode adds (and what it does NOT change)

| Behavior | Standard mode | TDD mode |
|---|---|---|
| Posted findings set | All kept findings | All kept findings — identical; TDD does not filter the post set |
| Phase 4.3 gate fires | Always when eligible findings exist | Always when eligible findings exist (gate is non-negotiable) |
| Phase 4.3 "Author tests for all eligible findings" option | Unmarked | Marked `(Recommended)` |
| `**Failing test:** <path>` body line on a finding | Only if a test was authored + confirmed | Same — appended to every `[CONFIRMED-BY-TEST]` finding |
| Phase 6 "Commit + push" option (when PR ref present) | Unmarked, except `(Recommended)` when the user just selected "Post Draft PR review" in the Action gate | Marked `(Recommended)` — pushing the authored tests to the reviewed branch is the additive payoff |
| Phase 6 PR draft-review comment body | severity + description + recommendation (no confidence, no decision-type, no plugin branding, no internal finding IDs — see `phase-6-handoff-reference.md` §7.6 "PR-comment body content rules") | + `**Failing test:** \`<path>\`` line on `[CONFIRMED-BY-TEST]` findings, where `<path>` is the project's actual test file (never `.geniro/...`) |
| Adversarial-tester-agent contract | Unchanged | Unchanged |
| State-file schema | `mode:` field defaults to `standard` (also: pre-TDD-mode state files without the field read as `standard`) | `mode: tdd` |

The author-tests question (Phase 1 §11 Q2) carries no `(Recommended)` highlight on either option — TDD is not "safer" than review-only, only costlier (it authors and runs tests). The user picks per run. It is its own question, independent of the review-depth question (Q1), so Deep+TDD is a valid combination from the chooser.

## Activation paths

- **Explicit flag:** `/geniro:review --tdd <args>` selects TDD; `/geniro:review --standard <args>` forces Standard. Flag parsing lives in Phase 1.
- **Phase 1 Mode AUQ (§11), Q2:** When neither `--tdd` nor `--standard` is present in `$ARGUMENTS`, the author-tests question offers "No — review only" / "Yes — also author failing tests" (neither marked Recommended). User pick is recorded in the state file as `mode:`.
- **Default:** Standard mode, applied when the chooser is dismissed or returns empty.

## Edge cases

**No eligible findings after the Phase 4.3 filter.** TDD mode behaves like Standard. Phase 4.3 skips because there is nothing to test, and all kept findings post normally. TDD adds nothing in this branch, but removes nothing either.

**Authored test flips green on independent re-run.** The finding is demoted per the existing demote-don't-delete logic (`[CHALLENGED-BY-TEST]`, kept visible in `## Filtered` with original severity so the user can re-elevate). Every other finding still posts — TDD never empties the post set.

**Eligible set exceeds the 10-test author cap.** The findings beyond the cap still post (without a `**Failing test:**` line); Phase 4.3 surfaces a `## Caveats` note naming them. See `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-3-test-gate-reference.md`.

**`--tdd` combined with `--plan <path>` / `--deep`.** All flags coexist freely. `--plan` feeds PLAN CONTEXT into reviewer prompts in Phase 1; `--deep` multiplies the reviewer/verifier fan-out; `--tdd` controls test authoring + the push offer. They don't interact — document this so users don't treat them as mutually exclusive.

**PR ref provided but `gh` unavailable.** Phase 1 already errors and stops (existing behavior, not TDD-specific). Mode detection still runs first; the failure happens at the PR-fetch step regardless of mode.

**Mode mismatch on resume.** If a session resumed from compaction reads a state-file with `mode: tdd` but the user re-invokes `/geniro:review` without `--tdd` (and without re-firing the Mode AUQ), the saved `mode:` is the source of truth — do not silently switch back to Standard. If ambiguity matters, the resumed run can re-fire the Mode AUQ.

## Failing-test contract — what does and does not change

The failing-test semantics are **unchanged** by the mode flip. `adversarial-tester-agent` runs the same protocol (3x flake check plus orchestrator independent re-run) per the canonical RED → GREEN → REFACTOR cycle at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md`. Mode does not affect what the agent does, only how the orchestrator surfaces the test-gate's Recommended highlight and the push offer.

**No preservation tests are added.** TDD mode does NOT widen the agent's contract to also ensure repo-wide existing tests stay green; that is out of scope.

**No mutation-testing self-check** is added. Out of scope.

Pushing the authored tests to the reviewed branch is the one sanctioned write `/geniro:review` performs. It is gated by the explicit "Commit + push" pick in the Phase 6 Failing-tests gate and scoped to authored test files only, per the carve-out in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §1. A fix never rides along with that push.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "TDD mode is on, the user obviously wants tests authored — skip the Phase 4.3 AUQ this time" | Mode flips the Recommended highlight, not the gate. The Phase 4.3 invariant ("the skill MUST NEVER spawn the agent without explicit user approval") is non-negotiable in every mode. The two-step gate (skill asks, then on YES spawn) is the only rationalization-resistant variant. |
| "TDD mode means I should drop the un-testable findings from the PR" | TDD is additive — it never removes a finding. Every kept finding posts in both modes; TDD only appends test evidence to the ones a test reproduced. Filtering the post set was the old reductive behavior this mode no longer has. |
| "TDD mode is on, the user obviously wants tests committed and pushed — skip the Phase 6 'Failing tests' AUQ" | `git push` is an external write to a public surface. The push is gated by the explicit "Commit + push" pick; TDD only flips that option's Recommended suffix, never the gate. Only authored TEST files push — never a fix. |
| "TDD mode is just a shortcut for 'always run Phase 4.3 on all findings' — drop the AUQ entirely when `mode: tdd`" | The Phase 4.3 "Pick" branch is still meaningful in TDD mode (the user may want to test a subset, e.g., only CRITICAL findings). Mode flips the Recommended option; it does not collapse the option set. |
