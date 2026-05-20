# TDD Cycle

Canonical RED→GREEN→REFACTOR procedure. Consumers: `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` § Phase 2 in TDD Mode, `${CLAUDE_PLUGIN_ROOT}/skills/review/tdd-mode-reference.md`, `${CLAUDE_PLUGIN_ROOT}/skills/refactor/SKILL.md`, `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` adversarial mode, `${CLAUDE_PLUGIN_ROOT}/agents/backend-agent.md`. The PreToolUse hook `enforce-tdd-order.sh` reads this rule's state file.

This file is the single source of truth. Skills cite this file; do NOT inline-paste the cycle steps or the state-file contract.

## Why this exists

Without an explicit cycle contract, "TDD" reduces to "tests are present" — which is necessary but not sufficient. Three observed failure modes when the cycle is skipped:

- Tests are authored after the production code; they pass on first run, proving they discriminate nothing about the bug they were nominally written for. The "regression test" is theatre.
- The orchestrator runs the new test plus the implementation in the same step; a passing run is reported, but the failing-test signature is never observed — no one actually saw RED.
- REFACTOR is treated as "clean up later, after this WU ships"; the design debt that the cycle exists to amortize accumulates instead.

The cycle below collapses all three. Each phase has a verification step + an Evidence Block + a state-file write so the discipline survives compaction and concurrent sessions.

## State file contract

The TDD cycle persists its current phase in a slug-scoped state file so the PreToolUse hook can gate Edit|Write at the right moment, and so cycle progress survives compaction.

- **Path:** `.geniro/state/tdd/state-<slug>.md`. Slug computed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules. Never write to a non-scoped path; sibling slugs belong to parallel pipelines on other branches and must not collide.
- **Format:** Markdown with sections (NOT JSON). JSON corrupts on partial write — half a `{...}` is unparseable, while half a Markdown file is still readable. The within-skill-state-handoff convention is Markdown for exactly this reason.
- **Required headers** (at the TOP of the file, before any other content, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Producer contract):

  ```
  Branch: <git branch --show-current OR detached-<short-sha>>
  Worktree: <git rev-parse --show-toplevel>
  Timestamp: <ISO-8601 UTC, e.g., 2026-05-10T14:32:00Z>
  ```

- **Required body section `## phase`** with one of: `RED` / `GREEN` / `REFACTOR` / `IDLE`. Phase transitions are linear: `IDLE → RED → GREEN → REFACTOR → IDLE` (REFACTOR is optional; valid to skip from `GREEN → IDLE`).
- **Required body section `## target`** with the absolute file path the cycle is targeting (the production file under change, NOT the test file). The hook compares Edit|Write paths against this target.
- **Atomic write:** orchestrator writes via `mktemp` + `mv -f` (POSIX-atomic — `mv` within the same filesystem is one inode swap). Direct `>` redirect is forbidden — a partial write during compaction leaves the file unreadable mid-cycle. Sample shell:

  ```bash
  tmp="$(mktemp "${state_file}.XXXXXX")"
  printf '%s\n' "$content" > "$tmp"
  mv -f "$tmp" "$state_file"
  ```

- **Single-writer:** ONLY the orchestrator writes this file. Sub-agents NEVER write it — the PreToolUse hook reads it; if a sub-agent could write it, the agent could trivially set `phase: GREEN` and bypass enforcement. Spawn sites declare `disallowedTools: ["Write", "Edit"]` for the state file path or restate the constraint in-prompt per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`.

## RED phase

1. **Author the failing test FIRST.** Production code changes are forbidden in this phase. The test targets the new behavior using the public interface signatures already approved (per `implement-reference.md` § Interface-Design Pre-Approval Gate, when applicable).
2. **Run the test command** (project-specific, captured from CLAUDE.md). Capture stdout/stderr + exit code verbatim.
3. **Verify exit code != 0 AND the failure signature matches the behavior under test.** A test that fails with `ImportError: no module named X` does not prove the new behavior is uncovered — it proves the test file is malformed. The signature must be a real assertion failure (`AssertionError`, `expected X got Y`, or equivalent).
4. **Write Evidence Block** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` schema: command, exit code, last 3 lines of output. Reasoning-from-the-diff is forbidden — the captured run is the only proof.
5. **Update state file:** `## phase\nRED` and `## target\n<absolute path of production file under change>`. Use the atomic-write procedure above.

If exit code is 0 (test passes on current code), REJECT the RED step — the test is testing existing behavior, not the new behavior. Re-author the test with a tighter assertion before proceeding.

## GREEN phase

1. **Author MINIMAL production code to pass the test.** Anti-pattern: anticipating the next behavior in the architect's list. Each cycle is one behavior; resist adding "while I'm here" extensions.
2. **Run the test command.** Same command as RED — change nothing about the invocation.
3. **Verify exit code == 0** for the new test AND the full project test suite. Running only the new test is insufficient — the implementation may have regressed sibling behavior. If sibling tests fail, the implementation regressed; spawn a fixer agent (max 1 round) before declaring GREEN, then escalate if still red.
4. **Write Evidence Block** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. Forbidden phrases (`"all tests pass"`, `"validation complete"`) without an Evidence Block trip the Stop hook.
5. **Update state file:** `## phase\nGREEN`. Same atomic-write procedure.

## REFACTOR phase

REFACTOR is optional but strongly preferred. Skip with explicit IDLE; do not leave the state file at `GREEN` indefinitely (downstream sessions reading a stale `GREEN` mis-handle Edit|Write enforcement).

1. **Refactor either the test or the production code** — preserve test intent. Allowed moves: rename a poorly-named local, extract a duplicated helper, collapse a redundant conditional. Forbidden: changing a test's assertion to make a refactored implementation pass.
2. **Run the FULL test suite** (NOT just the cycle's one test). The point of REFACTOR is to verify the change preserves all existing behavior, not just the just-added behavior.
3. **Verify all tests still GREEN.** If any test reddens, `git stash` the refactor and continue to next cycle; refactor in a follow-up.
4. **Write Evidence Block** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. The Evidence Block is the same schema regardless of phase.
5. **Update state file:** `## phase\nREFACTOR` during the refactor, then `## phase\nIDLE` on completion. The IDLE write is mandatory — without it the hook continues gating Edit|Write under the assumption a cycle is still in flight.

## Hook enforcement

The PreToolUse hook `enforce-tdd-order.sh` reads `.geniro/state/tdd/state-<slug>.md` on every `Edit` and `Write` call. Logic:

- If state file does not exist OR `## phase` is `IDLE` → exit 0 (no gating; TDD cycle not active).
- If `## phase` is `RED` AND the Edit|Write target file does NOT match `*test*` / `*.spec.*` / `*_test.go` / `tests/**` → exit 2 with stderr message: `Edit|Write to production file '<path>' blocked: TDD cycle is in RED phase, target test file must change first. See ${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md.`
- If `## phase` is `GREEN` or `REFACTOR` → exit 0 (production-code edits are expected in these phases).

The hook exits 2 (not 1) so Claude Code surfaces the stderr message to the user without retry. The hook is read-only — it never writes the state file; only the orchestrator writes (per § State file contract single-writer).

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll write the test after the code — it's the same diff in the end." | Tests passing immediately prove nothing about whether they discriminate the behavior under change. The failing-test step is the only verification that the test would have caught the bug; written-after, the test is theatre. |
| "I know the code is right, RED is theatre." | If you didn't watch RED fail, you don't know if your test would have caught the bug. The cost of confirming RED is one test invocation; the cost of skipping it is silently shipping a test that passes on every implementation. |
| "I'll skip REFACTOR — the GREEN code is fine, no duplication." | REFACTOR is optional, but explicitly mark state IDLE so the hook stops gating Edit|Write. Leaving phase at GREEN during the next cycle's RED step blocks the test author from writing the new test. |
| "The state file is overhead — I'll skip writing it for this one quick fix." | The state file IS the contract. Without it the hook can't enforce order, and concurrent same-cwd sessions on different branches collide. The slug-scoped path solves the collision; the headers carry branch identity through compaction. |
| "Sub-agents can write the state file — they're trustworthy." | Single-writer is non-negotiable. If a sub-agent could write `phase: GREEN`, the hook is bypassable by any agent that mis-reads the cycle, and the discipline collapses. Orchestrator writes; agents read (or are pre-inlined the relevant phase by the orchestrator). |
| "I'll keep the state in JSON — it's more structured." | JSON corrupts on partial write per the within-skill-state-handoff.md convention (Citadel's GSD Pattern 5). Markdown with `## phase` sections is half-readable when truncated; JSON is unparseable. The format choice is for compaction-resilience, not aesthetics. |

## Definition of Done

A consumer skill correctly applies the TDD cycle when:

- [ ] State file `.geniro/state/tdd/state-<slug>.md` exists with Branch:/Worktree:/Timestamp: headers and `## phase` + `## target` sections.
- [ ] RED phase wrote an Evidence Block showing exit code != 0 with a real assertion-failure signature.
- [ ] GREEN phase wrote an Evidence Block showing exit code == 0 for the new test AND the full suite.
- [ ] REFACTOR phase (if entered) ran the full test suite, not just the cycle's test.
- [ ] State file ends at `## phase\nIDLE` when the cycle completes; never left at GREEN or REFACTOR.
- [ ] State file written atomically via mktemp + mv -f; never via direct `>` redirect.
- [ ] Sub-agents did not write the state file; orchestrator is the single writer.
