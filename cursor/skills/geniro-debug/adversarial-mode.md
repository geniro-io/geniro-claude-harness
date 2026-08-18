<!-- Generated from skills/debug/adversarial-mode.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Debug — Adversarial Mode (verify-changes)

Phase file for `/geniro:debug`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`.

state.md `mode: adversarial`. Phases: `adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship`. Parallel to Scientific Mode; shared Phase 0 routes here on anchored verify-keyword signals (Phase 0 — `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-0-mode-detect.md`).

### A1. Purpose

Attacker-mindset pass that AUTHORS executable F→P failing tests against a diff. Complements Scientific Mode: Scientific Mode REPORTS hypotheses about a known bug; Adversarial Mode hunts for unknown bugs in recent changes by writing tests that fail on today's code. Test authoring is delegated to `adversarial-tester-agent`; the orchestrator independently re-runs authored tests to confirm the failure before surfacing findings.

### A2. Diff resolution

**Diff resolution follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`** for the default scope + base-branch resolution; the supported explicit input shapes are enumerated below (self-contained — no cross-skill parser dependency).

**Default when no explicit range:** scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` — anchor on the current cwd's worktree + currently-checked-out branch. Resolve the base branch per scope-anchor rule #3 (`git symbolic-ref --short refs/remotes/origin/HEAD`). Compute `git diff <base>...HEAD`. Fall back to `HEAD~1..HEAD` when the current branch IS the base branch, OR when the computed range is empty because the merge-base of `<base>` and `HEAD` IS `HEAD` — the branch has not diverged from its base yet, whatever the cause (a Step 0.2 relocation onto a fresh `HEAD`-cut branch, among others), so there is nothing between them to diff.

**Supported shapes:** bare keyword (`"verify last changes"`) → default; explicit range (`HEAD~3..HEAD`, `abc123..def456`); branch (`feat/foo...HEAD`); PR ref (strip leading `#`, resolve via `gh pr diff <number-or-url>` or `mcp__github__pull_request_read`).

### A3. Skip conditions

Adversarial mode is SKIPPED and the skill reports `"no adversarial pass — <reason>"` when:

- Empty diff (nothing to test).
- Diff contains zero production-code files (docs / config / lock / generated only).
- Diff >50 changed files OR >1000 changed LOC → suggest `/geniro:review` for oversized diffs (the agent's authored-test hard cap wastes budget on diffs this large).

Write terminal `phase: adversarial-aborted` with `## Termination reason: <skip reason>` — matching the A4 step 6 zero-red-tests exit — then run Cleanup (A7). Without this write, `phase: adversarial-mode-detect` (set at Phase 0 exit) stays the active phase and resurfaces the task on every session start.

### A4. RED-phase workflow

Runs the **RED phase** of the canonical cycle at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § RED phase: author the failing test FIRST, verify it fails with a real assertion signature, then escalate the fix to the receiving skill. Tests are never authored alongside or after the fix in this mode — RED-first ordering is non-negotiable.

0. **Refresh custom instructions on entry.** Re-fire `load-custom-instructions(SKILL_SLUG: debug, LOAD_TIER: pipeline, MODE: refresh)` once. Step 3 spawns `adversarial-tester-agent` to author test code, so the code-style rules the spawn inlines have to be the ones on disk now — Phase 0's load predates the mode routing that got here.
1. **Resolve the diff** (A2). Record the resolved range into state.md `## Diff Scope` — a compaction-resume re-entering this step reads that record rather than re-deriving the range against whatever branch is current then. Pre-inline full diff + changed-file contents for the spawn prompt.
2. **Detect the project test framework.** Read CLAUDE.md Essential Commands + `package.json` scripts / `pyproject.toml` / `Cargo.toml` to extract test command, naming convention, and 1-2 exemplar test files closest to changed code.
3. **Spawn `adversarial-tester-agent`** to AUTHOR RED tests — see Spawn Template (A5). The agent writes failing tests against today's code; no fix is authored. On return, read the report for its `Context loaded:` line and act on an `unreadable` or missing one, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The load report.
4. **Independently verify RED.** Read the agent's report at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` (`<branch>` = state.md frontmatter `branch:`, the workspace this run recorded at the Phase 0 pick, not a fresh `git branch --show-current` — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §6), extract authored test file paths from frontmatter `authored_tests[]` (preferred) or fall back to body `**Test file:**` lines for legacy m7-v1 handoffs. Run the project test command **once per authored test** (single independent re-run — the agent already ran a 3× flake check per its Step 5). Tests that do not fail deterministically are deleted from disk AND removed from the body report AND pruned from the frontmatter `authored_tests[]` array — re-emit the handoff file via `atomic_state_write` so the consumer (/geniro:implement's Phase 1 handoff-resolution step) sees the kept set only. **Re-emit contract:** `atomic_state_write` overwrites rather than merges, so the whole file has to be supplied. Produce it by transforming the bytes on disk — read the file, drop the pruned `authored_tests[]` entries and their `**Test file:**` body lines, write the result back — never by re-typing the agent's file out of context. A multi-kilobyte file the orchestrator did not author loses a clause or a frontmatter key when reproduced by hand, and the loss is silent: the consumer just reads a truncated contract. This is the orchestrator-side RED-verification per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § RED phase Step 3. Persist the same per-test verdict to state.md `## Re-verification Results` — path, pre-rerun F→P status, kept or discarded, and the discard reason where applicable — so a compaction mid-step recovers this step's outcome rather than re-running it.
5. **Present Adversarial Findings** (A6 template).
6. **Emit pitfalls, then escalate fix authoring.** Before firing the escalation AUQ, call `emit-learning` once per kept RED test — `type: pitfall`, payload shape at `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §9 — so the record does not depend on which option the user picks next. Firing it here, ahead of the AUQ, is what keeps it from becoming the trailing step that gets dropped once the deliverable already reads as finished (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Caller contract rule 2). If zero red tests survived re-verification, SKIP entirely (nothing to emit) — report `"no bugs found in scanned diff"` and go directly to Cleanup (A7); terminal state `adversarial-aborted` with `## Termination reason: no-bugs-found-in-diff`.

   Then reuse the §3.2 escalation AUQ (run `/geniro:implement` / Cannot-verify / Leave-it-to-me) with findings file path referencing `from-debug-adversarial-<branch>.md` instead of `from-debug-<branch>.md`. The authored test file paths inside are the escalation targets — the handoff carries RED tests; the receiving skill's own fix loop turns them green as it applies the fix. Run `/geniro:implement` writes `phase: done`, this chain's terminal; the other two options are shared with Scientific Mode and land outside the adversarial chain.

state.md `## Authored Tests` body section tracks each authored test per the column set in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2.

### A5. Spawn template

Literal `Agent(subagent_type="adversarial-tester-agent", ...)` template — pre-inlined diff, framework detection, F→P invariant, authored-test hard cap, scope anchor — in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §6 (A5 spawn template).

### A6. Findings template

Markdown template for the post-re-verification findings block (Diff scope / Hypotheses generated / Tests authored / Tests discarded / CRITICAL-HIGH / MEDIUM / Discarded-Inconclusive / Zero-red-tests outcome) in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §6 (A6 findings template).

If zero red tests survive, skip escalation entirely and go directly to Cleanup (A7). Otherwise proceed to escalation per A4 step 6.

### A7. Cleanup

`rm -rf .geniro/state/debug/<slug>/` for the current branch's slug, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract — every experiment artifact the run wrote under that dir goes with `state.md`. `from-debug-adversarial-<branch>.md` lives under `.geniro/state/handoff/`, outside the slug dir, so it survives as the audit trail. Authored test files stay on disk at their project test paths — they are the deliverable, not scratch. Best-effort: `2>/dev/null || true`.

---

## Definition of done

### Adversarial Mode

- [ ] Custom instructions refreshed on entry (A4 step 0), before the tester agent spawned
- [ ] Diff scope resolved (range + file list recorded in state.md `## Diff Scope`)
- [ ] Skip conditions checked (and explicitly reported if skipped)
- [ ] `adversarial-tester-agent` spawned with every context-isolation slot pre-inlined
- [ ] Report written to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md` (`<branch>` = state.md frontmatter `branch:`, the Phase 0-recorded workspace)
- [ ] Authored tests independently re-run by the orchestrator; F→P-confirmed tests retained, any passing-today tests deleted
- [ ] One `pitfall` learning recorded per kept RED test, before the escalation AUQ (skipped only on the zero-red-tests exit)
- [ ] Escalation decision made via AskQuestion (or no-bugs-found exit if zero red tests → terminal `adversarial-aborted`)
- [ ] Authored test files left on disk (NOT reverted — unlike scientific-method experiments)
- [ ] Cleanup completed (`from-debug-adversarial-<branch>.md` may remain as audit trail)
