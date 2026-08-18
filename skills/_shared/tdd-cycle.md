# TDD cycle

Canonical RED→GREEN→REFACTOR procedure. Consumer: `${CLAUDE_PLUGIN_ROOT}/skills/debug/adversarial-mode.md` §A4. RED-phase workflow. This is an unenforced convention — no hook blocks an out-of-order edit; the discipline holds only because the orchestrator follows it.

This file is the single source of truth. Skills cite this file; do NOT inline-paste the cycle steps or the state-file contract.

## Contents

- §Why this exists
- §State file contract — the `.geniro/state/tdd/state-<slug>.md` schema
- §RED phase — write the failing test first
- §GREEN phase — minimal code to pass
- §REFACTOR phase — clean up under green tests
- §Anti-rationalization
- §Definition of Done

## Why this exists

Without an explicit cycle contract, "TDD" reduces to "tests are present" — which is necessary but not sufficient. Three observed failure modes when the cycle is skipped:

- Tests are authored after the production code; they pass on first run, proving they discriminate nothing about the bug they were nominally written for. The "regression test" is theatre.
- The orchestrator runs the new test plus the implementation in the same step; a passing run is reported, but the failing-test signature is never observed — no one actually saw RED.
- REFACTOR is treated as "clean up later, after this WU ships"; the design debt that the cycle exists to amortize accumulates instead.

The cycle below collapses all three. Each phase has a verification step + an Evidence Block + a state-file write so the discipline survives compaction and concurrent sessions.

## State file contract

The TDD cycle persists its current phase in a slug-scoped state file so cycle progress survives compaction and a concurrent session on another branch can tell which phase is active.

- **Path:** `.geniro/state/tdd/state-<slug>.md`. Slug computed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules. Never write to a non-scoped path; sibling slugs belong to parallel pipelines on other branches and must not collide.
- **Format:** Markdown with sections (NOT JSON). JSON corrupts on partial write — half a `{...}` is unparseable, while half a Markdown file is still readable. The within-skill-state-handoff convention is Markdown for exactly this reason.
- **Required frontmatter fields** (inside the `---` fence that opens on line 1, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Producer contract):

  ```yaml
  ---
  branch: <git branch --show-current OR detached-<short-sha>>
  worktree: <git rev-parse --show-toplevel>
  timestamp: <ISO-8601 UTC, e.g., 2026-05-10T14:32:00Z>
  ---
  ```

- **Required body section `## phase`** with one of: `RED` / `GREEN` / `REFACTOR` / `IDLE`. Phase transitions are linear: `IDLE → RED → GREEN → REFACTOR → IDLE` (REFACTOR is optional; valid to skip from `GREEN → IDLE`). This is the field a reader checks to know what should be happening next (see RED phase below); the file does not track or compare a per-cycle target path.
- **Atomic write:** orchestrator writes via `mktemp` + `mv -f` (POSIX-atomic — `mv` within the same filesystem is one inode swap). Direct `>` redirect is forbidden — a partial write during compaction leaves the file unreadable mid-cycle. Sample shell:

  ```bash
  tmp="$(mktemp "${state_file}.XXXXXX")"
  printf '%s\n' "$content" > "$tmp"
  mv -f "$tmp" "$state_file"
  ```

- **Single-writer:** ONLY the orchestrator writes this file. Subagents never write it — a subagent writing concurrently could race the orchestrator's own write and leave `## phase` out of sync with what actually happened, misleading whoever reads it next. Spawn sites declare `disallowedTools: ["Write", "Edit"]` for the state file path or restate the constraint in-prompt per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`.

## RED phase

1. **Author the failing test FIRST.** Production code changes are forbidden in this phase — a self-imposed discipline, not a mechanical block; nothing stops the edit, so hold the order yourself. The test targets the new behavior using the already-approved public interface signatures.
2. **Run the test command** (project-specific, captured from CLAUDE.md). Capture stdout/stderr + exit code verbatim.
3. **Verify exit code != 0 AND the failure signature matches the behavior under test.** A test that fails with `ImportError: no module named X` does not prove the new behavior is uncovered — it proves the test file is malformed. The signature must be a real assertion failure (`AssertionError`, `expected X got Y`, or equivalent).
4. **Write Evidence Block** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` schema: command, exit code, the tail length that schema specifies. Reasoning-from-the-diff is forbidden — the captured run is the only proof.
5. **Update state file:** set `## phase` to `RED`. Use the atomic-write procedure above.

If exit code is 0 (test passes on current code), REJECT the RED step — the test is testing existing behavior, not the new behavior. Re-author the test with a tighter assertion before proceeding.

## GREEN phase

1. **Author MINIMAL production code to pass the test.** Anti-pattern: anticipating the next behavior in the architect's list. Each cycle is one behavior; resist adding "while I'm here" extensions.
2. **Run the test command.** Same command as RED — change nothing about the invocation.
3. **Verify exit code == 0** for the new test AND the full project test suite. Running only the new test is insufficient — the implementation may have regressed sibling behavior. If sibling tests fail, the implementation regressed; spawn a fixer agent (max 1 round) before declaring GREEN, then escalate if still red.
4. **Write Evidence Block** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. Forbidden phrases (`"all tests pass"`, `"validation complete"`) without an Evidence Block are enforced in consumption, not by a hook — the orchestrator re-runs the GREEN verification itself rather than trusting an unbacked completion claim.
5. **Update state file:** `## phase\nGREEN`. Same atomic-write procedure.

## REFACTOR phase

REFACTOR is optional but strongly preferred. Skip with explicit IDLE; do not leave the state file at `GREEN` indefinitely (a downstream session reading a stale `GREEN` would wrongly believe a cycle is still in flight).

1. **Refactor either the test or the production code** — preserve test intent. Allowed moves: rename a poorly-named local, extract a duplicated helper, collapse a redundant conditional. Forbidden: changing a test's assertion to make a refactored implementation pass.
2. **Run the FULL test suite** (NOT just the cycle's one test). The point of REFACTOR is to verify the change preserves all existing behavior, not just the just-added behavior.
3. **Verify all tests still GREEN.** If any test reddens, `git stash` the refactor and continue to next cycle; refactor in a follow-up.
4. **Apply the assertion-completeness & spec-coverage checks** from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md` §"Assertion completeness & spec coverage" to the test this cycle authored: does it assert everything its name claims, does it cover the spec behavior the cycle targets, and is it redundant with a sibling test the cycle just added? RED proved the test *discriminates*; this proves it *covers what it claims*. Tighten the assertion or add the missing one before IDLE — a test that passed RED can still under-assert the behavior the cycle was for. Surface a finding message-first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §"Message-first rendering" only when a check fails; a clean cycle proceeds to IDLE silently.
5. **Write Evidence Block** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. The Evidence Block is the same schema regardless of phase.
6. **Update state file:** `## phase\nREFACTOR` during the refactor, then `## phase\nIDLE` on completion. The IDLE write is mandatory — without it the state file wrongly signals to the next reader that a cycle is still in flight.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll write the test after the code — it's the same diff in the end." | Tests passing immediately prove nothing about whether they discriminate the behavior under change. The failing-test step is the only verification that the test would have caught the bug; written-after, the test is theatre. |
| "I know the code is right, RED is theatre." | If you didn't watch RED fail, you don't know if your test would have caught the bug. The cost of confirming RED is one test invocation; the cost of skipping it is silently shipping a test that passes on every implementation. |
| "I'll skip REFACTOR — the GREEN code is fine, no duplication." | REFACTOR is optional, but explicitly mark state IDLE so the state file doesn't mislead the next reader. Leaving phase at GREEN when the next cycle's RED step begins misrepresents which phase is genuinely active. |
| "The state file is overhead — I'll skip writing it for this one quick fix." | The state file is the only record of which phase is active — concurrent same-cwd sessions on different branches would collide without it. The slug-scoped path solves the collision; the headers carry branch identity through compaction. |
| "Subagents can write the state file — they're trustworthy." | Single-writer is non-negotiable. A subagent writing concurrently could race the orchestrator's own write and leave `## phase` wrong for whoever reads it next. Orchestrator writes; agents read (or are pre-inlined the relevant phase by the orchestrator). |
| "I'll keep the state in JSON — it's more structured." | JSON corrupts on partial write — a half-written `{...}` is unparseable, while a truncated Markdown file with `## phase` sections is still readable. The format choice is for compaction-resilience, not aesthetics. |

## Definition of Done

A consumer skill correctly applies the TDD cycle when:

- [ ] State file `.geniro/state/tdd/state-<slug>.md` exists with `branch:` / `worktree:` / `timestamp:` frontmatter fields and a `## phase` section.
- [ ] RED phase wrote an Evidence Block showing exit code != 0 with a real assertion-failure signature.
- [ ] GREEN phase wrote an Evidence Block showing exit code == 0 for the new test AND the full suite.
- [ ] REFACTOR phase (if entered) ran the full test suite, not just the cycle's test.
- [ ] REFACTOR phase (if entered) applied the assertion-completeness & spec-coverage checks to the cycle's test before the IDLE write.
- [ ] State file ends at `## phase\nIDLE` when the cycle completes; never left at GREEN or REFACTOR.
- [ ] State file written atomically via mktemp + mv -f; never via direct `>` redirect.
- [ ] Subagents did not write the state file; orchestrator is the single writer.
