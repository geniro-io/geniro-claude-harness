# Test-quality gate — surface the test audit as a visible decision

Canonical contract for the Phase 3 test-quality gate: an always-on (skip-when-clean), advisory, fail-open step that makes the audit of a run's newly-authored or changed tests visible to the user, instead of letting test-quality findings disappear silently into the auto-fix loop.

The problem it solves: an implementer agent's tests are often wrong on the first pass — they omit a behavior the spec required, or they name two behaviors and assert only one. Left to the broad reviewer pipeline alone, those findings get auto-fixed or filtered without the user seeing that the audit ran, so the user re-runs the audit by hand every time. This gate is the automated, visible form of that manual ask.

Consumer: `/geniro:implement` (Phase 3, after the fix loop converges, before Ship).

## Relationship to the tests reviewer dimension (no new agent)

This gate spawns no agent. The audit is already performed by the fresh `tests` reviewer dimension that Phase 3 spawns — a fresh isolated context, anchoring-free, reading `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/tests-criteria.md`, which carries the test-honesty checks: claimed-vs-asserted scope, spec-coverage traceability, redundancy among new tests, and scenery tests flagged for removal. The gate is the surfacing-and-decision layer on top of that reviewer's output: it selects the test-honesty findings and presents them as a deliberate decision. A second agent re-reading the same diff would double the cost for no new signal — the value this gate adds is visibility and a user decision, not a second audit.

## When it applies

- The run authored or changed at least one test file (detect from the changed-files list / diff matching a test convention: `tests/**`, `test/**`, `__tests__/**`, `*.spec.*`, `*_test.*`, `*-test.*`, `*.test.*`). When no test file changed → skip the user-facing decision entirely, silently — but still persist the skip per §Persistence below, so a later phase can tell it apart from a gate that should have run and didn't. A behavior change with zero test edits is the broad reviewer's concern, not this gate's.
- Both spec-driven and inline-task runs. The claimed-vs-asserted and redundancy checks need no spec; the spec-coverage check is a silent no-op when no spec/plan is in context (nothing to map against).
- Fail-open: if the `tests` reviewer errored or returned nothing parseable, persist the unavailable-audit state (§Persistence) and note it under `## Caveats`, then proceed — the gate never blocks Ship on its own infra failure.

## What it surfaces

From the Phase 3 `tests`-dimension output (and the tests that Phase 3's own inline edge-case authoring step wrote), select the test-honesty findings — those flagged for claimed-vs-asserted mismatch, spec-coverage gap, weak/zero assertions (the Deletion Test), redundancy among new tests, or a scenery test recommended for removal (presentational detail, framework behavior, duplicated coverage). Partition them:

- **Found and already fixed** — test-quality findings the bounded fix loop resolved this run. They need no decision; list them for visibility so the user sees the audit ran and what it changed.
- **Open** — test-quality findings not auto-resolved (a judgment call the loop left standing, or one it did not fix). These carry the decision.

## Gate behavior

- **Zero found (audit clean).** No question. Record one plain-English confirmation line in the ship report, e.g. `Audited the N tests this run added/changed against the spec — no coverage gaps or weak assertions.` Visible confirmation, no forced click.
- **Found, all auto-fixed, none open.** No question. Record the confirmation line plus a one-line summary of what was tightened, e.g. `Audited N added/changed tests; tightened M weak or over-claiming assertions (listed in the review summary).`
- **Open findings exist.** Render the open findings message-first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §"Message-first rendering" — decision-queue tracker when there are two or more, a one-sentence opener, a conversational per-finding digest that expands the reviewer shorthand into plain English with the file:line evidence cite, and a visual per finding — as a self-contained chat block. Then fire ONE lean AskUserQuestion (header: `Test quality`):
  - **Tighten all** — apply the recommended assertion/coverage fixes for every open finding (re-enter the inline fix sub-loop; re-run the suite after).
  - **Let me pick** — present the open findings for selection; fix the chosen ones.
  - **Ship as-is** — accept the open findings; record them in the ship report's deferred list.

  An empty answer means an upstream tool bug, not a user choice — re-ask per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions.

## Persistence — state.md `## Test Quality Audit`

The consumer (`/geniro:implement` Phase 3 Step 5) persists this gate's outcome to state.md `## Test Quality Audit` via `atomic_state_write` on every run, including the skipped and unavailable ones — so the Ship pre-terminal check (`${CLAUDE_PLUGIN_ROOT}/skills/implement/phase-3-ship.md` §"Emit the ship report, then transition") reads a written record instead of this turn's narration. Four states share the one section:

- **Ran, clean or all auto-fixed** — the sentinel `none — the test-quality gate ran and found no issues`, or a one-line found/fixed summary.
- **Ran, open findings** — the disposition the user picked (tighten all / the picked subset / ship as-is) and what remains open.
- **Precondition false — no test file changed** — the gate never applied (§When it applies); the sentinel `none — no test file changed this run; the gate's precondition never held`.
- **Precondition held, audit unavailable** — a test file changed, but the `tests` reviewer errored or returned nothing parseable; the sentinel `none — a test file changed but the tests reviewer returned no usable audit this run`.

A bare or absent section is none of the four: per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel, that reads as unknown — the step that should have written one of the four states above did not run.

## Boundaries

- **Advisory, never a hard block.** The gate opens a decision; it does not gate Ship on its own. A user who picks "Ship as-is" ships. It never overrides the Ship-mode question or the test-suite-green requirement.
- **Orchestrator owns judgment.** The tests reviewer returns evidence (file:line, assertion shape, the claimed-vs-asserted gap); the orchestrator decides which findings are real and what the fix is. A reviewer claim that a test "under-asserts" is checked against the test body before it becomes an open finding.
- **Plain English at the surface.** Every rendered finding and every option label passes the fresh-user test — no `tests-criteria.md` section numbers, no severity tokens, no "claimed-vs-asserted" jargon in the user-facing string; describe the gap ("the test is named for two checks but asserts only one").
