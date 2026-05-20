# Test-First Gate

Canonical AskUserQuestion gate fired by skills before dispatching code-writing agents. Always-WAIT in Medium/Big scope; auto-defaults to "Author failing test first" in Small.

This file is the single source of truth. Skills cite this file; do NOT inline-paste the AUQ shape or the result-handling table.

## Why this exists

Production-code agents that run before a failing test exists turn TDD into a checkbox: tests are added in the same diff, they pass on first run, and the regression they nominally cover is uncatchable. The Test-First Gate fires upstream of the spawn so the orchestrator records (a) whether a failing test already exists, (b) whether one needs authoring, or (c) explicit user opt-out with justification — and routes the agent accordingly.

Skipping the gate is the documented anti-pattern in the superpowers `test-driven-development` "iron law" and in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` § Forbidden phrases (success claims without an Evidence Block from a captured RED run).

## When this fires

- `/geniro:refactor` — when a behavior-adjacent test-coverage gap is detected (refactor's zero-behavior-change constitution requires existing tests to lock the behavior; if none exists, the gate fires before the refactor-agent spawn).

The gate does NOT fire in:
- `/geniro:implement` (M4) — Phase 2 runs а single whole-feature edit batch followed by Phase 3's 5-dim reviewer pipeline (`tests` dimension covers test-first behaviour); per-WU Test-First check would be redundant against M4's design (`architecture/M4-implement-redesign.md` §6 + §7.2). Lane modes (TDD / Light / Full) were removed in M4.
- `/geniro:debug` — debug's evidence requirement is hypothesis confirmation per `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`, not a test-first gate. Debug's adversarial mode is the closest analogue and runs the cycle in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` directly.

(Legacy `/geniro:follow-up` consumer removed — skill deleted per master plan §65.)

## Required AUQ shape

- **`header`**: `"Tests"`.
- **`question`**: `"Before writing production code: is there an existing failing test that proves the behavior under change?"`
- **`options[]`** (3 single-select):
  - `label`: `"Test exists & failing (proceed RED→GREEN)"` — `description`: `"Skip RED authoring; agent jumps to GREEN per ${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md. Use when a regression test was added before this run (e.g., from a bug-report repro) and is currently red."`
  - `label`: `"Author failing test first"` (Recommended) — `description`: `"Agent runs the full RED→GREEN cycle: author failing test, verify it fails with the right signature, then write minimal production code to pass it. Default for new behavior."`
  - `label`: `"Skip TDD (justify)"` — `description`: `"Agent skips the cycle entirely. Orchestrator records the user's justification in the Ship summary. Use only when TDD is genuinely inapplicable (e.g., pure config edit, or rolling back a known-bad commit). Auto-defaulting to this option is forbidden — see Always-WAIT contract."`

The "Author failing test first" option is highlighted Recommended in every mode and lane — it is the safe default. The other two options exist for the genuine cases where the default is wrong (regression test already in flight, or non-behavioral change).

## Always-WAIT contract

This gate is **Always-WAIT** in every mode and lane that fires it (per § When this fires). Auto-defaulting to "Skip TDD" is the documented anti-pattern catalogued in the superpowers `test-driven-development` "iron law" AND in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` § Forbidden phrases. The user has context the orchestrator does not — e.g., the change is one line of CSS that has no behavior surface, OR the change looks small but is the root cause of a customer-facing bug that absolutely needs a regression test.

Empty `AskUserQuestion` answer = upstream Claude Code bug; fall back to plain text and re-ask. Never auto-default.

Auto-defaulting to the SKIP option is forbidden in every case. `/geniro:refactor` is the sole remaining consumer (post-M4); it fires the gate per its own SKILL.md flow.

## Result handling

After the gate resolves, write `.geniro/state/tdd/state-<slug>.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § State file contract — Markdown, slug-scoped, atomic write, with the required Branch:/Worktree:/Timestamp: headers. The body's `## phase` section depends on the user's choice:

| Choice | State file `## phase` | Agent prompt |
|---|---|---|
| "Test exists & failing (proceed RED→GREEN)" | `GREEN` (skip RED — assumes the existing test is the cycle's RED) | "Make the existing failing test at `<test-path>` pass with minimal code per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § GREEN phase." Pre-inline the test file content per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`. |
| "Author failing test first" (Recommended) | `RED` | "Run the full RED→GREEN cycle per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md`. Author the failing test first; verify it fails with a real assertion signature; then GREEN-phase the minimal implementation." |
| "Skip TDD (justify)" | `IDLE` (cycle not active) | Agent runs without TDD-cycle constraints. Orchestrator captures the user's free-text justification (chained AUQ or follow-up text input) and records it in the Ship summary line "TDD skipped: <justification>". |

The state file path is then passed to the dispatched agent as part of its pre-inlined context. The agent reads (never writes) the state file; the orchestrator's write is the single source of truth per `tdd-cycle.md` § single-writer.

When the user picks "Test exists & failing", the orchestrator MUST verify the named test actually fails before writing `## phase\nGREEN` — capture the test command output and Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`. If the test passes on current code, re-fire the gate with a one-line warning ("Named test `<path>` is currently green — pick again") because the user's premise was wrong.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This is a one-line bugfix, TDD is overkill." | If the bug recurred, it's because no test caught it. RED locks the bug into the regression suite — one line of test, one line of fix, permanent coverage. The "overkill" framing inverts the cost: the test is cheap, the recurrence is expensive. |
| "I'll write the test after the production code, in the same commit." | The state file enforces order; the agent will hit exit 2 from `enforce-tdd-order.sh` on production-file Edit before a test exists per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § Hook enforcement. Same-commit grouping doesn't satisfy the discipline; same-message ordering does. |
| "Auto-mode means the gate should auto-default to whatever's fastest." | Auto-mode picks recommended defaults for non-workspace gray areas (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/auto-mode-signals.md`); TDD-skip is not a gray area — it's an explicit user opt-out with a justification trail. Auto-defaulting to "Skip TDD" is forbidden. The Small-scope auto-default is "Author failing test first" — the recommended, safe path. |
| "The user said 'just fix it' — that means skip the gate." | "Just fix it" is a velocity hint, not a discipline waiver. The user is asking for less ceremony, not for less correctness. Default to "Author failing test first"; if the user reads the AUQ and picks "Skip TDD (justify)", THAT is the explicit opt-out. |
| "I'll fire the gate but auto-pick the Recommended option silently." | That's auto-defaulting to a non-skip option, which is allowed in the Small-scope auto exception above — but only when scope qualifies AND auto-mode is active. In every other case, fire the AUQ; the user's pick is the contract, not the orchestrator's inference of it. |

## Definition of Done

A consumer skill correctly applies the Test-First Gate when:

- [ ] AUQ fires before any production-code agent spawn in the listed skills/lanes.
- [ ] The 3 options match the Required AUQ shape verbatim — no paraphrasing of `label` or `description`.
- [ ] "Author failing test first" carries the Recommended marker.
- [ ] User's choice is persisted to `.geniro/state/tdd/state-<slug>.md` per the Result handling table; never to a non-scoped path.
- [ ] "Test exists & failing" path verifies the named test is actually red (Evidence Block) before transitioning state to `GREEN`.
- [ ] "Skip TDD (justify)" path captures the user's justification and surfaces it in the Ship summary.
- [ ] Auto-defaulting to "Skip TDD" never happens — empty answer falls back to plain text re-ask.
