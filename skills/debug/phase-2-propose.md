# Debug Phase 2 — propose

Phase file for `/geniro:debug`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`.

state.md `phase: propose`. Output authoring: text fix proposal + F→P reproduction test. **No production-source edits applied.** Exits to Phase 3 when fix proposal AND reproduction test are both verified.

## Contents

- §2.1 Refresh custom instructions on entry · §2.2 Multi-path fix gate (Always-WAIT) · §2.3 Text fix proposal
- §2.4 Author F→P reproduction test + monkey-patch verify · §2.5 Fix-loop escalation

### 2.1 Refresh custom instructions on entry

On Phase 2 entry, re-fire `load-custom-instructions(SKILL_SLUG: debug, LOAD_TIER: pipeline, MODE: refresh)` once (pipeline tier's load set owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`). The fix proposal and the reproduction test are both authored here, so the code-style rules have to be the ones on disk now — Phase 1's load can be many hypothesis rounds old.

### 2.2 Multi-path fix gate (Always-WAIT)

If the confirmed root cause has more than one valid fix path with real trade-offs (e.g., snapshot-vs-live-fetch, COALESCE vs CHECK constraint vs catch+log, fix-at-source vs fix-at-call-site), do NOT pick one and write a single text proposal.

**Render the investigation context to chat first, then fire the lean `AskUserQuestion` — both per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` § Investigation-driven fix gate (debug-flavored)**. That section carries the full render template (title, opener, root-cause digest, cause → effect flow visual, reproduction status, options) and its source-field map into `.geniro/state/debug/<slug>/state.md`:
- `header: "Fix path"`
- `question` text: plain-English root-cause title + `path:lines`
- options: one per fix path — `label` (1-5 words, path name) + `description` (one-line trade-off); `preview` stays empty or a one-line recap

**Approvals-persistence:** before firing, check state.md frontmatter `approvals[]` for prior entry with `category: multi_path_fix` and matching `root_cause` (use root-cause text as the disambiguator). If found, use prior `picked` value. If not, fire AUQ → on user pick, append entry to `approvals[]` via `atomic_state_write`.

**Re-ask trigger:** if the root cause changes (second-pass investigation overturns the prior root cause), the prior `approvals[]` entry is stale — clear it and re-fire. The session-start restore re-surfaces this from `approvals[]` on resume.

The single-text-proposal default applies ONLY when there is one obvious right fix; multi-path is the explicit branch.

### 2.3 Text fix proposal

- Formulate the minimal fix for the root cause as a **text proposal**: file path(s), exact change (unified diff or before/after snippet), one-sentence rationale.
- Do NOT write the fix to production/source files. Writes and edits are available for EXPERIMENTS only (tests, logging, debug scripts, `.geniro/state/debug/<slug>/` artifacts) — not for applying the proposed patch.
- If any experiment modified non-test source, revert those edits before escalation; the escalated skill applies the real fix cleanly.
- Do NOT refactor adjacent code.

Persist to state.md `## Proposed Fix` body section.

### 2.4 Author F→P reproduction test + monkey-patch verify

**Author the reproduction as a unit/integration test in the project's test framework**, placed at the project's normal test path next to the source it covers. Detect framework + naming convention from CLAUDE.md Essential Commands + an exemplar test file. Scripts / curl / ad-hoc queries are NOT acceptable substitutes — they get deleted at Cleanup and leave no regression guard.

**Seam correctness.** Author the test at a seam that exercises the bug pattern as it actually occurred — a single-caller unit test for a multi-caller interaction bug passes without guarding the regression and buys false confidence. When no correct seam exists, that absence is itself a finding: record it in the findings template's "Special handling" field so the consumer knows the regression is not locked down.

**Test name + comments rule.** The reproduction test name AND any comments inside the test describe the bug behavior — the input, condition, or observable failure — never the hypothesis number from `## Hypotheses` or any other thread-local label. Tags like `Bug A/B/C`, `Hypothesis 1/2`, `Test 1`, `Case X`, `Issue #N from this run`, `regression from review run`, `found by review-gate`, or `confirmed by this <skill> run` are meaningless once the investigation ends. Prefer `cacheKey omits userId so role change leaves stale cached profile` over `Bug C`.

**F→P invariant.** Pre-fix: run the authored test ≥2× and confirm the SAME failure signature both times (same exception type + same failing assertion). Two divergent failures are NOT confirmation — investigate flakiness or two bugs before continuing.

**Verify the proposed fix — monkey-patch in the test by default; production-source edits are an explicit escape hatch.** Apply the patch locally as a monkey-patch inside the authored test file (mock, fixture, test-local shim, or a throwaway helper imported only by the test). Re-run the authored test ≥2× post-fix and confirm the failure DISAPPEARS both times. If the bug genuinely cannot be verified without editing production source (hard-to-mock chain — DI container, framework hook, native module, generated code), list every touched production file under "Verification edits to revert:" in the findings, confirm each is reverted before escalation, and re-run `git diff` against just those listed paths to confirm each is clean — not a whole-tree `git diff`, which cannot distinguish this fix's edits from a user-dirty path, a concurrent session's edits, or a §3.1 user-accepted leftover. §3.1's working-tree check reconciles the full tree against the Phase 0 baseline before the handoff persists; this step only has to prove the debug-recorded set itself is clean. **Deep-mode branch (`deep-mode: true`):** give the fix→test judgment 3 INDEPENDENT verifiers and take a majority vote (does the monkey-patched fix genuinely turn the F→P test red→green, AND is the test a strong regression guard, not too weak); Adversarial Mode's test authoring stays single-pass even in deep mode. Per `${CLAUDE_PLUGIN_ROOT}/skills/debug/deep-mode-reference.md` §3 (abstain/quorum rules, the native-precision rationale, fail-safe to the single-pass monkey-patch verify above).

**Escape hatch — non-deterministic bugs only, after rate-raising.** Available only after the §1.3 rate-raising attempt was made and its outcome recorded in `## Feedback Loop` — a bug never looped, parallelised, or load-tested is not yet "non-reproducible". If the bug genuinely cannot be reproduced at the test layer even at a raised rate (race conditions only seen under load, environment-only failures, UI flake), render the investigation context to chat first, then fire the lean `AskUserQuestion` — both per the canonical shape at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` § Investigation-driven fix gate (debug-flavored):
- `header: "No repro"`
- `question`: plain-English root-cause title + `path:lines` (or "unknown" if not isolated)
- Options: regression-guard alternatives — "Add runtime assertion" / "Author fuzz seed" / "Add monitor/alert" / "Skip regression guard" (description carries one-line trade-off)

Record the user's selection AND rationale in state.md `## Reproduction Test` body section under "Reproduction Decision". The default is mandatory; escape hatch is opt-in with a paper trail.

Do NOT run the full project test suite here — that's the receiving skill's responsibility. Phase 2's goal is the F→P-verified test artifact + evidence the proposed patch turns it green. If the project uses code generation (check CLAUDE.md) AND the proposed fix touches DTOs/schemas/controllers, note this in the findings template "Special handling" field.

### 2.5 Fix-loop escalation (2 fix attempts failed → AUQ)

When 2 distinct fix proposals fail F→P verification (each pre/post-fix monkey-patch round counts as one), surface to user — mirrors escalation pattern:

1. Do **not** silently report "no fix works".
2. Render the two failed attempts to chat first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering — what each attempt changed and what still fails, in plain words, then a `**Technical detail:**` block per attempt with the evidence cites and the failing output (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers) — then the lean `AskUserQuestion` with header "Fix-fail" and options:
- **Try different approach** — go back to (Hypothesize) with a fresh angle. state.md transitions back to `phase: investigate`.
- **Accept as documented limitation** — proceed to Phase 3 ship sub-step with `## Accepted Limitations` block in state.md body. state.md transitions to `phase: ship`. Receiving skill sees the unresolved limitation in the findings summary.
- **Abort** — `phase: aborted` (terminal).
3. state.md marks `phase: phase-2-escalated` with timestamp + fix-attempt count + accumulated test outputs. The session-start restore re-surfaces the open question on resume.

**Record a past learning on fix-loop exit.** When Phase 2 exits AND `fix_attempts ≥ 2`, call `emit-learning` with type=`retry_failure_sequence`, trust=`verified`, required `ext.{phase: "fix-attempts", attempts: [{round: N, failure: "<why this attempt did not verify>"}], resolution}`. `resolution` ∈ `{passed, escalated, aborted}` (passed = test confirmed fix; escalated = user picked "Try different approach" or "Accept as documented limitation"; aborted = terminal). Sliding-window cap per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Sliding-window caps on bookkeeping types, which owns the window size and the flip-then-append order. Single-attempt exits (fix_attempts == 1) do NOT emit. Scope = the file/module the fix targeted.
