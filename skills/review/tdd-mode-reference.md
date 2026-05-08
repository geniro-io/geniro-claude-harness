# TDD Mode Reference

TDD mode is an opt-in variant of `/geniro:review` that biases the run toward authoring failing tests for eligible findings (Phase 4c) and posting only F-to-P-confirmed evidence to the PR (Phase 6). It changes default highlighting and the Phase 6 PR-comment filter; it does NOT change the Phase 4c safety invariant in `SKILL.md` — the skill MUST `AskUserQuestion` before spawning `adversarial-tester-agent` in every mode. Mode flips defaults, never gates.

## What TDD mode flips and what it does NOT

| Behavior | Standard mode | TDD mode |
|---|---|---|
| Phase 4c gate fires | Always when eligible findings exist | Always when eligible findings exist (gate is non-negotiable) |
| Phase 4c "Author tests for all eligible findings" option | Unmarked | Marked `(Recommended)` |
| Phase 6 PR-comment post set | All kept findings | `[CONFIRMED-BY-TEST]` + `[INTENT-CHECK]` + `[PRODUCT-DECISION]` + `[FIX-NOW]`-typo-class |
| Phase 6 "Commit + push" option (when PR ref present) | Unmarked | Marked `(Recommended)` |
| Phase 6 PR-comment body | severity + description + recommendation (no confidence, no decision-type, no plugin branding — see SKILL.md "PR-comment body content rules") | + `**Failing test:** \`<path>\`` line where `<path>` is the project's actual test file (never `.geniro/...`) |
| Adversarial-tester-agent contract | Unchanged | Unchanged |
| State-file schema | `mode:` field defaults to `standard` (also: pre-TDD-mode state files without the field read as `standard`) | `mode: tdd` |

## Activation paths

- **Explicit flag:** `/geniro:review --tdd <args>` selects TDD; `/geniro:review --standard <args>` forces Standard. Flag parsing lives in Phase 1.
- **Phase 1 Mode AUQ:** When neither flag is present in `$ARGUMENTS`, the skill fires an `AskUserQuestion` with two options (Standard, TDD). User pick is recorded in the state file.
- **Default:** Standard mode, applied when the Mode AUQ is dismissed or returns empty.

## Edge cases

**No eligible findings after Phase 4c filter.** TDD mode behaves like Standard. Phase 4c skips because there is nothing to test; Phase 6's PR-comment filter has no `[TESTABLE]` findings to filter out, so all kept findings post normally. The mode flip is structurally a no-op in this branch.

**All authored tests pass on independent re-run (no `[CONFIRMED-BY-TEST]` tags).** TDD mode's PR-comment filter would empty the post set entirely. The skill surfaces "TDD mode: no F-to-P-confirmed findings — nothing posted to PR" once in chat and Phase 6's final gate ends. The user can re-run with `--standard` to post anyway, or address the underlying false-positive rate. Demoted findings still appear in the local report's `## Filtered` section with `[CHALLENGED-BY-TEST]` so they aren't lost.

**`--tdd` combined with `--plan <path>`.** Both flags coexist freely. `--plan` feeds PLAN CONTEXT into reviewer prompts in Phase 1; `--tdd` controls Phase 4c default-highlighting and the Phase 6 filter. They don't interact at any phase — document this so users don't treat them as mutually exclusive.

**`--tdd` combined with `/geniro:review` running as a sub-phase of `/geniro:implement`.** Phase 4c is skipped entirely when called as a sub-phase (the parent already runs Phase 6 Stage D's adversarial-tester against the same diff — running it twice double-spawns). TDD mode in this branch is a no-op for Phase 4c. The Phase 6 PR-comment posting gate is also skipped because the parent owns its own PR-handling. The mode flag is preserved in the state file but does not affect the sub-run.

**PR ref provided but `gh` unavailable.** Phase 1 already errors and stops (existing behavior, not TDD-specific). Mode detection still runs first; the failure happens at the PR-fetch step regardless of mode.

**Mode mismatch on resume.** If a session resumed from compaction reads a state-file with `mode: tdd` but the user re-invokes `/geniro:review` without `--tdd` (and without re-firing the Mode AUQ), the saved `mode:` is the source of truth — do not silently switch back to Standard. If ambiguity matters, the resumed run can re-fire the Mode AUQ.

## F-to-P contract — what does and does not change

The F-to-P semantics are **unchanged** between modes. `adversarial-tester-agent` runs the same protocol (3x flake check plus orchestrator independent re-run). Mode does not affect what the agent does, only how the orchestrator surfaces the gate and filters posting.

**No P-to-P (preservation tests) is added.** The user-facing TDD mode does NOT widen the agent's contract to also run repo-wide existing tests stay green; that is out of scope for this design (see SWE-bench's F-to-P + P-to-P dual gate for what a future expansion could add).

**No mutation-testing self-check** is added. Out of scope.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "TDD mode is on, the user obviously wants tests authored — skip the Phase 4c AUQ this time" | Mode flips the Recommended highlight, not the gate. The Phase 4c invariant ("the skill MUST NEVER spawn the agent without explicit user approval") is non-negotiable in every mode. The two-step gate (skill asks, then on YES spawn) is the only rationalization-resistant variant. |
| "TDD mode is on, the user obviously wants tests committed and pushed — skip the Phase 6 'Failing tests' AUQ" | Same reasoning, same rule. `git push` is an external write to a public surface. The mode-flip is a "Recommended" suffix; the gate stays. |
| "All tests passed, no findings have `[CONFIRMED-BY-TEST]` — post them anyway, the user wants comments" | TDD mode's whole point is to gate posting on F-to-P-confirmed evidence. If the user wanted comments without the gate, they would have run Standard mode. Surface the empty post-set message and stop. |
| "TDD mode is just a shortcut for 'always run Phase 4c on all findings' — drop the AUQ entirely when `mode: tdd`" | The Phase 4c "Pick" branch is still meaningful in TDD mode (the user may want to test a subset, e.g., only CRITICAL findings). Mode flips the Recommended option; it does not collapse the option set. |

## Compatibility & rollback

Pre-TDD-mode state files (no `mode:` field) read as `mode: standard`. No migration needed.

To roll TDD mode back, remove the `--tdd` parsing in Phase 1, the Mode AUQ block, and the Phase 6 Step 3.5 filter — every other change degrades safely. Rollback can be partial.
