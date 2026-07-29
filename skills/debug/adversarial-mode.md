# Debug — Adversarial Mode (verify-changes)

Phase file for `/geniro:debug`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`.

state.md `mode: adversarial`. Phases: `adversarial-mode-detect` → `adversarial-investigate` → `adversarial-ship`. Parallel to Scientific Mode; shared Phase 0 routes here on anchored verify-keyword signals (Phase 0 — `${CLAUDE_PLUGIN_ROOT}/skills/debug/phase-0-mode-detect.md`).

### A1. Purpose

Attacker-mindset pass that AUTHORS executable F→P failing tests against a diff. Complements Scientific Mode: Scientific Mode REPORTS hypotheses about a known bug; Adversarial Mode hunts for unknown bugs in recent changes by writing tests that fail on today's code. Test authoring is delegated to `adversarial-tester-agent`; the orchestrator independently re-runs authored tests to confirm the failure before surfacing findings.

### A2. Diff resolution

**Diff resolution follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`** for the default scope + base-branch resolution; the supported explicit input shapes are enumerated below (self-contained — no cross-skill parser dependency).

**Default when no explicit range:** scope follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` — anchor on the current cwd's worktree + currently-checked-out branch. Resolve the base branch per scope-anchor rule #3 (`git symbolic-ref --short refs/remotes/origin/HEAD`). Compute `git diff <base>...HEAD`. If on the base branch, fall back to `HEAD~1..HEAD`.

**Supported shapes:** bare keyword (`"verify last changes"`) → default; explicit range (`HEAD~3..HEAD`, `abc123..def456`); branch (`feat/foo...HEAD`); PR ref (strip leading `#`, resolve via `gh pr diff <number-or-url>` or `mcp__github__pull_request_read`).

### A3. Skip conditions

Adversarial mode is SKIPPED and the skill reports `"no adversarial pass — <reason>"` when:

- Empty diff (nothing to test).
- Diff contains zero production-code files (docs / config / lock / generated only).
- Diff >50 changed files OR >1000 changed LOC → suggest `/geniro:review` for oversized diffs (the agent's authored-test hard cap wastes budget on diffs this large).

### A4. RED-phase workflow

Runs the **RED phase** of the canonical cycle at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § RED phase: author the failing test FIRST, verify it fails with a real assertion signature, then escalate the fix to the receiving skill (which runs GREEN). Tests are never authored alongside or after the fix in this mode — RED-first ordering is non-negotiable.

1. **Resolve the diff** (A2). Pre-inline full diff + changed-file contents for the spawn prompt.
2. **Detect the project test framework.** Read CLAUDE.md Essential Commands + `package.json` scripts / `pyproject.toml` / `Cargo.toml` to extract test command, naming convention, and 1-2 exemplar test files closest to changed code.
3. **Spawn `adversarial-tester-agent`** to AUTHOR RED tests — see Spawn Template (A5). The agent writes failing tests against today's code; no fix is authored.
4. **Independently verify RED.** Read the agent's report at `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`, extract authored test file paths from frontmatter `authored_tests[]` (preferred) or fall back to body `**Test file:**` lines for legacy m7-v1 handoffs. Run the project test command **once per authored test** (single independent re-run — the agent already ran a 3× flake check per its Step 5). Tests that do not fail deterministically are deleted from disk AND removed from the body report AND pruned from the frontmatter `authored_tests[]` array — re-emit the handoff file via `atomic_state_write` so the consumer (/geniro:implement's Phase 1 handoff-resolution step) sees the kept set only. **Re-emit contract:** `atomic_state_write` overwrites rather than merges, so the whole file has to be supplied. Produce it by transforming the bytes on disk — read the file, drop the pruned `authored_tests[]` entries and their `**Test file:**` body lines, write the result back — never by re-typing the agent's file out of context. A multi-kilobyte file the orchestrator did not author loses a clause or a frontmatter key when reproduced by hand, and the loss is silent: the consumer just reads a truncated contract. This is the orchestrator-side RED-verification per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § RED phase Step 3.
5. **Present Adversarial Findings** (A6 template).
6. **Escalate fix authoring** — reuse the §3.2 escalation AUQ (run `/geniro:implement` / Cannot-verify / Leave-it-to-me) with findings file path referencing `from-debug-adversarial-<branch>.md` instead of `from-debug-<branch>.md`. The authored test file paths inside are the escalation targets. The receiving skill writes the fix and runs GREEN verification (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md` § GREEN phase). If zero red tests survived re-verification, SKIP entirely — report `"no bugs found in scanned diff"` and go directly to Cleanup; terminal state `adversarial-aborted` with `## Termination reason: no-bugs-found-in-diff`.

state.md `## Authored Tests` body section tracks each authored test per the column set in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2.

### A5. Spawn template

Literal `Agent(subagent_type="adversarial-tester-agent", ...)` template — pre-inlined diff, framework detection, F→P invariant, authored-test hard cap, scope anchor — in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §6 (A5 spawn template).

### A6. Findings template

Markdown template for the post-re-verification findings block (Diff scope / Hypotheses generated / Tests authored / Tests discarded / CRITICAL-HIGH / MEDIUM / Discarded-Inconclusive / Zero-red-tests outcome) in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §6 (A6 findings template).

If zero red tests survive, skip escalation entirely and go directly to Cleanup. Otherwise proceed to escalation per A4 step 6.

---

## Definition of done

### Adversarial Mode

- [ ] Diff scope resolved (range + file list recorded in state.md `## Diff Scope`)
- [ ] Skip conditions checked (and explicitly reported if skipped)
- [ ] `adversarial-tester-agent` spawned with all 6 context-isolation slots pre-inlined
- [ ] Report written to `<PRIMARY_ROOT>/.geniro/state/handoff/from-debug-adversarial-<branch>.md`
- [ ] Authored tests independently re-run by the orchestrator; F→P-confirmed tests retained, any passing-today tests deleted
- [ ] Escalation decision made via AskUserQuestion (or no-bugs-found exit if zero red tests → terminal `adversarial-aborted`)
- [ ] Authored test files left on disk (NOT reverted — unlike scientific-method experiments)
- [ ] Cleanup completed (`from-debug-adversarial-<branch>.md` may remain as audit trail)
