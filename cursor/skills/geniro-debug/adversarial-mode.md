<!-- Generated from skills/debug/adversarial-mode.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Debug — Adversarial Mode (verify-changes)

Phase file for `/geniro:debug`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`.

state.md `mode: adversarial`. Phases: `adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship`. Parallel to Scientific Mode; shared Phase 0 routes here on anchored verify-keyword signals (Phase 0 — `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-0-mode-detect.md`).

### A1. Purpose

Attacker-mindset pass that AUTHORS executable F→P failing tests against a diff, run inline in this same context — no subagent spawn. Complements Scientific Mode: Scientific Mode REPORTS hypotheses about a known bug; Adversarial Mode hunts for unknown bugs in recent changes by writing tests that fail on today's code. Because authoring and verification share one context, the guarantee against a false RED claim is not a second reader — it is that no hypothesis counts until its own test has actually been run and observed to fail (A4 step 3).

### A2. Diff resolution

**Diff resolution follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`** for the default scope + base-branch resolution; the supported explicit input shapes are enumerated below (self-contained — no cross-skill parser dependency).

**Default when no explicit range:** scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` — anchor on the current cwd's worktree + currently-checked-out branch. Resolve the base branch per scope-anchor rule #3 (`git symbolic-ref --short refs/remotes/origin/HEAD`). Compute `git diff <base>...HEAD`. Fall back to `HEAD~1..HEAD` when the current branch IS the base branch, OR when the computed range is empty because the merge-base of `<base>` and `HEAD` IS `HEAD` — the branch has not diverged from its base yet, whatever the cause (a Step 0.2 relocation onto a fresh `HEAD`-cut branch, among others), so there is nothing between them to diff.

**Supported shapes:** bare keyword (`"verify last changes"`) → default; explicit range (`HEAD~3..HEAD`, `abc123..def456`); branch (`feat/foo...HEAD`); PR ref (strip leading `#`, resolve via `gh pr diff <number-or-url>` or `mcp__github__pull_request_read`).

### A3. Skip conditions

Adversarial mode is SKIPPED and the skill reports `"no adversarial pass — <reason>"` when:

- Empty diff (nothing to test).
- Diff contains zero production-code files (docs / config / lock / generated only).
- Diff >50 changed files OR >1000 changed LOC → suggest `/geniro:review` for oversized diffs (the authored-test hard cap wastes budget on diffs this large).

Write terminal `phase: adversarial-aborted` with `## Termination reason: <skip reason>` — matching the A4 step 5 zero-red-tests exit — then run Cleanup (A7). Without this write, `phase: adversarial-mode-detect` (set at Phase 0 exit) stays the active phase and resurfaces the task on every session start.

### A4. RED-phase workflow

Runs the **RED phase** of the canonical cycle at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § RED phase: author the failing test FIRST, verify it fails with a real assertion signature, then escalate the fix to the receiving skill. Tests are never authored alongside or after the fix in this mode — RED-first ordering is non-negotiable.

0. **Refresh custom instructions on entry.** Re-fire `load-custom-instructions(SKILL_SLUG: debug, LOAD_TIER: pipeline, MODE: refresh)` once. Step 3 authors test code, so the code-style rules it applies have to be the ones on disk now — Phase 0's load predates the mode routing that got here.
1. **Resolve the diff** (A2). Record the resolved range into state.md `## Diff Scope` — a compaction-resume re-entering this step reads that record rather than re-deriving the range against whatever branch is current then.
2. **Detect the project test framework.** Read CLAUDE.md Essential Commands + `package.json` scripts / `pyproject.toml` / `Cargo.toml` to extract test command, naming convention, and 1-2 exemplar test files closest to changed code.
3. **Generate hypotheses and author F→P-verified RED tests.** Read every changed source file in full, not just the diff hunks — context around the change is where an attacker's inputs hide. Form a hypothesis per plausible edge case, boundary, or interaction the change misses; ceiling **5-12 hypotheses**, scaled to how many distinct regions the diff actually touched — a cap on a large diff, not a floor a small one owes rows to fill. For each hypothesis worth pursuing, author a failing test in the project's framework and naming convention, next to the exemplar files from Step 2.

   **F→P invariant.** Run the authored test. A hypothesis counts only once its test is demonstrated RED on current code with a real assertion failure — an import error or setup exception does not prove the behavior is uncovered, it proves the test file is malformed. A test that passes today, or never produces a genuine assertion failure, is discarded (`discarded-cannot-repro`) and its file deleted — no bug, or the hypothesis was wrong.

   **Flake check.** Once a round of tests is kept, run them together in one filtered test-command invocation, repeated **3 times total**, each run captured separately. A kept test's error signature must match across all 3 rounds; one that diverges is `inconclusive` — discard and delete it. Flaky failures are worse than none: they train the next reader to re-run until green and mask a real regression once it starts failing for a new reason.

   **Stop rule.** 5 hypotheses in a row ending `inconclusive` or `discarded-cannot-repro` stops hypothesis generation — return what survived rather than grinding on a diff that has already yielded what it will.

   **Hard cap:** 10 authored tests per run. At the cap, stop, note the overflow in the A6 Summary, and let the escalation target schedule a second pass.

   Record each authored test into state.md `## Authored Tests` (kept) and `## Re-verification Results` (path / F→P + flake-check status / kept or discarded / discard reason where applicable) as it resolves — so a compaction mid-loop recovers this step's outcome rather than re-running it.
4. **Present Adversarial Findings** (A6 template) **and persist the handoff.** Output the findings block directly in chat AND write it — full T2 frontmatter, per A5 — to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` via `atomic_state_write`, before Step 5's escalation AUQ fires. `<branch>` = state.md frontmatter `branch:`, the workspace this run recorded at the Phase 0 pick, not a fresh `git branch --show-current` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §6).
5. **Emit pitfalls, then escalate fix authoring.** Before firing the escalation AUQ, call `emit-learning` once per kept RED test — `type: pitfall`, payload shape at `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §9 — so the record does not depend on which option the user picks next. Firing it here, ahead of the AUQ, is what keeps it from becoming the trailing step that gets dropped once the deliverable already reads as finished (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Caller contract rule 2). If zero red tests survived the F→P and flake-check verification, SKIP entirely (nothing to emit) — report `"no bugs found in scanned diff"` and go directly to Cleanup (A7); terminal state `adversarial-aborted` with `## Termination reason: no-bugs-found-in-diff`.

   Then reuse the §3.2 escalation AUQ (run `/geniro:implement` / Cannot-verify / Leave-it-to-me) with findings file path referencing `from-debug-adversarial-<branch>.md` instead of `from-debug-<branch>.md`. The authored test file paths inside are the escalation targets — the handoff carries RED tests; the receiving skill's own fix loop turns them green as it applies the fix. Run `/geniro:implement` writes `phase: done`, this chain's terminal; the other two options are shared with Scientific Mode and land outside the adversarial chain.

state.md `## Authored Tests` body section tracks each authored test per the column set in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2.

### A5. Handoff persistence

Field values for `from-debug-adversarial-<branch>.md` frontmatter (A4 step 4) — schema canonical at `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2 and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 / §Producer-specific extensions; read those rather than guessing a field's shape. This mode fixes: `tier: T2`, `producer: debug`, `consumer: implement`, `geniro_kind: debug-handoff`, `geniro_schema_version: m7-v2`, `mode: adversarial`, `phase: adversarial-ship`, `status: done`, `approvals: []`, `open_questions: []` (every gate that populates this array belongs to Scientific Mode — this pass raises none). `authored_tests[]` carries one entry per kept RED test: `mode: adversarial`, `f_to_p_status: red-on-current` (the only status valid for a kept adversarial test), `targeted_source` = the production file the test attacks, `confidence` mirroring the A6 Confidence column, `path` resolved against this run's own worktree. Omitting `branch`/`worktree` routes the consumer into the degraded fallback that drops the relocation suggestion the tests need to be found by (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/debug-handoff.md` §Step 4 Case C). `authored_tests: []` is the correct form for the zero-red-tests terminal outcome.

### A6. Findings template

Markdown template for the findings block (Diff scope / Hypotheses generated / Tests authored / Tests discarded / CRITICAL-HIGH / MEDIUM / Discarded-Inconclusive / Zero-red-tests outcome) in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §6 (A6 findings template).

If zero red tests survive, skip escalation entirely and go directly to Cleanup (A7). Otherwise proceed to escalation per A4 step 5.

### A7. Cleanup

`rm -rf .geniro/state/debug/<slug>/` for the current branch's slug, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract — every experiment artifact the run wrote under that dir goes with `state.md`. `from-debug-adversarial-<branch>.md` lives under `.geniro/state/handoff/`, outside the slug dir, so it survives as the audit trail. Authored test files stay on disk at their project test paths — they are the deliverable, not scratch. Best-effort: `2>/dev/null || true`.

---

## Definition of done

### Adversarial Mode

- [ ] Custom instructions refreshed on entry (A4 step 0), before test authoring begins
- [ ] Diff scope resolved (range + file list recorded in state.md `## Diff Scope`)
- [ ] Skip conditions checked (and explicitly reported if skipped)
- [ ] Hypothesis generation stayed within the 5-12 ceiling (scaled to changed regions) and stopped after 5 consecutive discards, when triggered
- [ ] Every kept test demonstrated RED (real assertion failure, matching signature across all 3 flake-check rounds) before being retained; any test that passed on current code or produced a differing signature was deleted
- [ ] Findings persisted to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` via `atomic_state_write`, before the escalation AUQ
- [ ] One `pitfall` learning recorded per kept RED test, before the escalation AUQ (skipped only on the zero-red-tests exit)
- [ ] Escalation decision made via AskQuestion (or no-bugs-found exit if zero red tests → terminal `adversarial-aborted`)
- [ ] Authored test files left on disk (NOT reverted — unlike scientific-method experiments)
- [ ] Cleanup completed (`from-debug-adversarial-<branch>.md` may remain as audit trail)
