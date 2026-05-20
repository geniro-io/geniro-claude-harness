# Implement Skill — Reference Material (M4)

This file contains templates, examples, and detailed procedures referenced by SKILL.md. The orchestrator reads specific sections at the relevant phase — not the entire file upfront.

**Scope under M4:** `/geniro:implement` is а 2-phase autonomous loop (Analyze → Implement → Self-review-and-Ship). Pre-M4 Lane modes (TDD / Light / Auto), per-WU parallel decomposition, milestone-mode special-casing, and the standalone `/geniro:follow-up` flow are removed (see `architecture/M4-implement-redesign.md` §3.1).

---

## Phase 1: $ARGUMENTS semantic-parse table (M4 §5.1)

No CLI flag grammar. The orchestrator parses `$ARGUMENTS` semantically at Phase 1 entry.

| `$ARGUMENTS` shape | Mode |
|---|---|
| empty | Resume current task from `<task-dir>/state.md` if one exists; else error directing the user to provide а task description. |
| contains `continue` / `resume` (standalone word, any casing) | Resume from state.md (M3-coupled — reads `non-resumable-actions[]` to skip side-effects already completed). |
| matches а filesystem path (rel или abs) to а `.md` file | Load as spec/plan artifact. Frontmatter validated via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`. |
| free-form description, no path match | Inline-task mode (M4 §5.3): treat `$ARGUMENTS` as а raw spec description; Phase 1 produces а minimal inline plan and proceeds. |
| ambiguous (bare slug что could be а task name OR а description) | AUQ с 2-3 disambiguation options. Persist outcome to state.md frontmatter `approvals[]` with `category: disambiguate_arguments` (M1 P-M1-1 schema). |
| natural-language modifier present (`don't push`, `draft only`, `stop after review`, `with PR`, `commit only`) | Honored semantically by Phase 3 Ship sub-step. Modifier survives in $ARGUMENTS и is consulted at relevant decision points. No CLI flag rewrite needed. |

**Workflow-integration plumbing.** If `.geniro/workflow/*.md` files exist with argument-detection patterns (e.g., Linear issue IDs, GitHub URLs), apply their patterns FIRST — they may inject extra context (issue body, status transition) before the semantic-parse table above runs. Integrations are non-blocking: if а workflow's backend (e.g., MCP) is unavailable, log а warning и proceed without.

**Approvals-persistence protocol (P-M1-1 producer-side):** before firing the disambiguation AUQ, check state.md frontmatter `approvals[]` для а prior entry с `category: disambiguate_arguments` matching the current $ARGUMENTS shape. If found, use the prior `picked` value и skip the AUQ. If not found, fire AUQ → on user pick, append to `approvals[]` via `atomic_state_write` before proceeding.

---

## Phase 1: Spec discovery walk-list (M4 §5.2)

When `$ARGUMENTS` does not directly carry а spec path, walk these in order и stop at the first hit:

1. `<task-dir>/spec.md` — preferred (`/geniro:plan` M5 canonical output).
2. `<task-dir>/plan.md` — legacy alias (pre-M4 convention).
3. design-doc frontmatter detect via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` — covers legacy /brainstorm-emitted design docs that don't follow naming convention.

If none match AND $ARGUMENTS is non-empty free-form text → enter **inline-task mode** (M4 §5.3): write а brief inline plan to state.md body under `## Inline Plan` containing one-sentence goal, file list (best-effort), и approach summary. This becomes the source-of-truth для Phase 3 self-review (the `spec` field consumed by reviewer-agents).

---

## Phase 2: Implement — error-handling

For test-suite failures, follow the in-phase mini fix loop in M4 §6.2:

```
retry = 1
while retry ≤ 3:
    inspect failing test output
    edit code (or test) to address the failure
    re-run test suite
    if all green → exit Phase 2 → Phase 3
    retry += 1
else:
    escalate via AskUserQuestion (debug-handoff / accept-failure / abort, per M4 §6.3)
```

**Evidence requirement.** Every PASS/FAIL claim from the test-suite run MUST attach an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` (command, exit code, last 3 lines of output). Stop-hook scans для forbidden phrases (`"all tests pass"`, `"validation complete"`, `"ready to ship"`) without an attached Evidence Block.

**Tool log persistence (M4 §2.2 invariant #7).** The end-of-phase test-suite run и any subagent spawn outcomes are persisted to state.md `## Tool log` body section via `atomic_state_write` per the schema in M4 §2.2. Routine Read/Edit/Bash on local files do NOT need logging.

**Termination-reason (M4 §2.1.1) on escalate-abort.** If the user picks "abort" at §6.3, write а `## Termination reason` body line: `repeated-failure: phase-2 retry-limit (<N> failing tests)`. Audit trail для M3 resume.

---

## Phase 3: Self-review reviewer-agent template (M4 §7.2)

Spawn 5 reviewer-agents в parallel — one call per dimension, all `Agent(...)` tool uses в the SAME assistant response. Each uses `subagent_type: "reviewer-agent"` (apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration-degradation ladder at every spawn site).

```
Agent(subagent_type="reviewer-agent", model="sonnet", description="Self-review: <dim>", prompt="""
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIMENSION: bugs | security | architecture | tests | code-quality
CRITERIA (pre-inlined): [content of corresponding criteria file from skills/review/]
CHANGED FILES (with full contents, pre-inlined): [list each file path followed by its current content]
DIFF CONTEXT: [paste `git diff <base>...HEAD` output where <base> resolves per ${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md rule 3]
SPEC CONTEXT: [pre-inline spec.md OR state.md ## Inline Plan section]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
PRIOR-ROUND FINDINGS: [paste prior-round CRITICAL/HIGH per agents/reviewer-agent.md §Step 1.7; first round: `none — first review`]

Review ONLY for [dimension]. Tag findings [SEVERITY] [NEW|PRE-EXISTING] per the output contract в agents/reviewer-agent.md §Output Format.

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs.
""")
```

### The 5 dimensions

| Dimension | Criteria file | Focus |
|-----------|---------------|-------|
| `bugs` | `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md` | Logic errors, null/undefined, off-by-one, race conditions, broken invariants |
| `security` | `${CLAUDE_PLUGIN_ROOT}/skills/review/security-criteria.md` | Injection, auth/authz, secret handling, untrusted-input flows, OWASP-top-10 |
| `architecture` | `${CLAUDE_PLUGIN_ROOT}/skills/review/architecture-criteria.md` | Layering, coupling, abstractions, dead code, duplication, naming, file placement. **Also covers docs-staleness** (OQ-9 closure): explicit check for README / architecture-doc / contributing-guide references к patterns or files renamed in Phase 2. **Also covers spec-compliance** (M4 §7.2 + master plan §139): explicit check that the Phase 2 diff matches spec.md scope — no unspec'd files touched, no spec'd requirements unaddressed. |
| `tests` | `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md` | Coverage of changed lines, edge cases, F→P invariant, brittle assertions, missing negative cases. **Pre-condition:** tests are green per Phase 2 §6.2; this dim NEVER sees failing tests. |
| `code-quality` | `${CLAUDE_PLUGIN_ROOT}/skills/review/optimizations-criteria.md` + `${CLAUDE_PLUGIN_ROOT}/skills/review/guidelines-criteria.md` + `${CLAUDE_PLUGIN_ROOT}/skills/review/conventions-criteria.md` | Idiomatic style, readability, comments noise, premature abstractions, simplification opportunities. **Subsumes pre-M4 Phase 5 SIMPLIFY agent.** |

**Code-style pre-inline slot (code-quality + architecture reviewers only):** if the Phase 1 / Phase 3-entry L4 loader echoed `Loaded code-style.md …`, pre-inline that content under а `## Code-style instructions` header per the reviewer-agent contract. If the loader echoed `No code-style.md found — skipping.`, omit the slot. Bugs / security / tests reviewers do NOT get the slot (code-style is orthogonal).

**ACI (M4 §13.5) — reviewer tool surface.** Reviewer-agents are pure-compute on the local diff: Read / Grep / Glob / Bash (read-only) only. Edit / Write / Agent / mutating Bash / external network are blocked. Enforcement: `agents/reviewer-agent.md` frontmatter `tools:` whitelist. Prompt-level reinforcement of "read-only" is а fallback layer.

**Parallel invocation:** all 5 (or fewer, on round N+1) spawns happen в ONE assistant response — multiple `Agent(...)` tool uses in the same message. Serial invocation doubles wall-time and the spec's design intent is parallelism.

---

## Phase 3: Bounded fix loop (M4 §7.3)

```
round = 1
while round ≤ 3:
    spawn reviewer-agents on failing dimensions only
        round 1: all 5 dims
        round N+1: only dims that flagged in round N
    collect findings
    if no findings across all dimensions:
        break  # exit к Phase 3 Ship sub-step
    apply fixes inline (single Edit-driven sub-loop, no further agent spawns)
    re-run project test suite (must stay green)
    round += 1
else:
    # round 4 would start — DO NOT enter it
    escalate via AskUserQuestion (§7.4)
```

**Round N+1 only re-runs failing dimensions.** Dimensions that passed round N are NOT re-spawned — bounds cost и avoids re-litigating clean code.

**Escalation at exhaust (M4 §7.4).** When the loop hits round 3 with unresolved findings:

1. Do NOT silently push or claim completion.
2. Surface via `AskUserQuestion` (header: `"Resolve findings"`) with:
   - Summary of unresolved findings per dimension (top 3 each).
   - Options:
     - **A) Hand off к /geniro:debug** — state.md transitions to `phase: debug-handoff` (terminal). Caller resumes via `/geniro:debug` using state.md as а T2 handoff.
     - **B) Accept findings и proceed к ship** — state.md adds `## Accepted Findings` body block recording the decision. Transitions to `phase: ship` (proceeds to §7.5 Ship sub-step). Architecture reviewer prompt в future runs sees the accepted-findings list и may flag scope concerns.
     - **C) Abort** — state.md transitions to `phase: aborted` (terminal). Work uncommitted on disk for manual takeover.
3. State.md records `## Termination reason` body line on aborted/handoff: `repeated-failure: phase-3 review-round-limit (<N> unresolved findings)`.

The Always-WAIT contract applies: empty `AskUserQuestion` answer = upstream bug, fall back to plain text и re-ask. NEVER auto-default to any option.

---

## Phase 3 — Ship sub-step

### Pre-Ship Visual Verification (M4 §7.5 step 1)

Runs only when BOTH conditions hold: (a) the Phase 2 changed-files list contains at least one file matching the UI-file detection rule (`${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` §UI-file detection rule), AND (b) Playwright MCP is available — check that `mcp__plugin_playwright_playwright__browser_navigate` is in your tool list. If Playwright MCP is NOT available, skip this entire section и note в the ship report: "Pre-Ship Visual Verification skipped — Playwright MCP not installed."

When both conditions hold, prompt the user via а STANDALONE `AskUserQuestion` with header "Smoke-test" as the ONLY question in that call — never batch it with the ship-mode AUQ. If the user picks "Yes — walk through it", execute this sequence:

1. **Detect target URL.** Probe dev-server ports in order — 3000 (Next.js), 5173 (Vite), 8080 (generic), 4321 (Astro), 4200 (Angular) — via `curl -s -o /dev/null -w "%{http_code}" http://localhost:PORT`. On the first 200, fetch `/` и check the response `<title>` или а known marker matches the project's `package.json` `name`; if uncertain, `AskUserQuestion` "Detected server on :PORT — is this the project under test?" before navigating. If no port responds, walk up from the primary changed UI file к the nearest `package.json` containing а `dev`/`start`/`serve` script (monorepo layouts: `apps/<name>/package.json`, `packages/<name>/package.json`). Choose package manager by lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb` → bun, else npm). Run с `run_in_background: true`, record the PID, poll `GET /` until 200 или 30s timeout. On timeout, ask the user "Skip verification" / "Retry" / "Enter URL manually".

2. **Infer the target route.** Map the primary changed UI file к а URL path: `app/<segment>/page.tsx` → `/<segment>`, `pages/<name>.tsx` → `/<name>`, `src/routes/<name>/+page.svelte` → `/<name>`. Leaf component (e.g., `components/Button.tsx`) → fall back к `/` и ask the user where it renders. Navigate с `mcp__plugin_playwright_playwright__browser_navigate`.

3. **Baseline snapshot.** Call `mcp__plugin_playwright_playwright__browser_snapshot` к capture the accessibility tree with element refs. Every subsequent interaction (`browser_click`, `browser_type`, `browser_fill_form`) requires а `ref` from this snapshot.

4. **Console + network sanity check.** Call `mcp__plugin_playwright_playwright__browser_console_messages` — treat any `error`-level entry as а failure worth reporting. Call `mcp__plugin_playwright_playwright__browser_network_requests` — flag same-origin 4xx/5xx responses. Re-run after step 5 и step 6.

5. **Targeted interaction.** Using refs from step 3, perform 1-3 actions that exercise the specific behavior changed в this run. Cap at 5 total interactions. Re-snapshot after each to get fresh refs.

6. **Responsive sweep** — only when the diff includes any `.css`/`.scss`/`.sass`/`.less`/`.styled.*` file, OR а JSX/TSX hunk touching `className`, `style`, или а CSS-module import. Call `mcp__plugin_playwright_playwright__browser_resize` к `{width: 375, height: 667}` (mobile) then `{width: 1280, height: 800}` (desktop). Snapshot each. Skip entirely for pure logic changes.

7. **Visual record.** Final `mcp__plugin_playwright_playwright__browser_take_screenshot` с `fullPage: true`, saved under `<task-dir>/playwright-verify.png`. This is the artifact — do NOT claim а pixel-diff against а prior state (no baseline image exists).

8. **Cleanup.** If step 1 spawned а dev server (PID recorded), send `kill -TERM <pid>`; if still alive after 3s, escalate с `kill -KILL <pid>`. NEVER kill servers the user had running before verification — only clean up what this step spawned.

**Reporting:** summarize в 3-5 lines — interaction result, console/network status, responsive issues (if swept), screenshot path. If issues were found, route via `AskUserQuestion`: "Fix and re-verify" (route through Adjustment Routing Small tweak path below — this section re-fires after the next clean review if UI files remain в the diff), "Ship anyway with noted issues" (append to state.md `## Visual Verification Notes` и proceed к ship-mode AUQ), или "Abort" (`phase: aborted` terminal).

---

### Commit + Push + PR (M4 §7.5 steps 2-4)

**Step 2 — Commit.** Stage relevant files, `git commit` с conventional message (e.g., `feat(auth): add OAuth login [ENG-123]`). Task ID inferred from spec.md / state.md metadata. If а workflow file specifies commit-message format (e.g., appending issue ID), follow that format.

**Step 3 — Ship-mode AUQ (M4 §7.5 step 3, P-M4-4 draft-grade framing).** Push is draft-grade (branch becomes visible on remote but carries no review weight); PR creation is commit-grade. The AUQ gates only the PR-creation decision.

Use `AskUserQuestion` (header: `"Ship mode"`):

- **Label:** `"Just push (no PR)"` / **Description:** `"git push origin <branch>. No PR created. Done."`
- **Label:** `"Open PR"` / **Description:** `"git push then gh pr create (ready-for-review). Appends task ID к PR title."`
- **Label:** `"Open draft PR"` / **Description:** `"git push then gh pr create --draft. Cannot combine с --web — if browser-view requested, run gh pr view --web afterward."`

The user can always type а custom response via "Other" (e.g., "review diff first", "leave uncommitted"):
- **"Review diff"** (via Other) → show diff via `git diff origin/HEAD...HEAD`, loop back к ship-mode AUQ.
- **"Leave uncommitted"** (via Other) → skip commit AND push entirely, transition к `phase: ship-committed-only` (terminal).

**Approvals-persistence protocol (P-M1-1, M4 §7.5 step 3):** before firing the ship-mode AUQ, check state.md frontmatter `approvals[]` для а prior entry с `category: ship_mode`. If found, use prior `picked` value и skip the AUQ (typical compaction-resume: user already picked в the original flow). If not found, fire AUQ → on pick, append to `approvals[]` via `atomic_state_write` before executing the chosen action.

**Step 4 — Non-resumable-actions update (M4 §8, M1 helpers).** After each side-effect that cannot be replayed safely (`git push`, `gh pr create`, posted PR comment), append а structured entry to state.md frontmatter `non-resumable-actions[]` array via `atomic_state_write`. Entry schema per M3 §8: `{action, completed-at, <action-specific-fields>}`. Write occurs AFTER the side-effect succeeds — atomic, so partial-write corruption is impossible mid-crash.

**Inline modifiers from $ARGUMENTS** (semantic parsing per Phase 1 table) override the ship-mode AUQ deterministically:

| Modifier in $ARGUMENTS | Effect |
|---|---|
| "don't push" / "no push" / "commit only" | Commit succeeds, no push. State.md → `phase: ship-committed-only` (terminal). Skip ship-mode AUQ. |
| "draft only" / "draft PR" / "open draft" | Push + `gh pr create --draft`. State.md → `phase: done`. Skip ship-mode AUQ. |
| "open PR" / "create PR" / "with PR" | Push + `gh pr create` (ready-for-review). State.md → `phase: done`. Skip ship-mode AUQ. |
| "stop after review" | Exit Phase 3 BEFORE commit. Surface clean review status as the deliverable. State.md → `phase: self-review-only` (terminal). |

---

### Update Docs (M4 §7.5 step 4 — auxiliary)

Check whether existing docs need updating based on what was implemented. **Skip if nothing changed that affects documented surfaces.** This is а thin fallback over the Phase 3 architecture reviewer's docs-staleness check — if that reviewer already surfaced doc-update findings, they would have been fixed inline during the fix loop. This step catches anything left over.

Scan the diff против main и check:
- Do any existing docs reference patterns/files that were renamed, moved, или superseded?
- Did this implementation introduce а new pattern that should be documented as а canonical example?
- Do README, architecture docs, или contributing guides need patches?

If updates needed, delegate к а general-purpose subagent с `model="haiku"` containing the diff summary + the doc files to patch. Keep changes minimal — patch what's stale or add а new reference, don't rewrite docs. If no docs need updating, skip silently.

---

### Extract Learnings (M4 §7.5 step 5, L2 auto-emit)

Per master plan §69, the standalone `/learnings` skill is deleted; learning capture is an auto-step at the end of /implement. Phase 3 calls the L2 helper `emit-learning` (M2 §9, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.sh`) when conditions are met.

**Emit triggers per M2 §5.3 (M4 owner) + M4 §13.2:**

| Type | When M4 emits |
|---|---|
| `convention` | Phase 3 architecture или code-quality reviewer reports ≥3 instances of same pattern в changed code. Threshold tuning lives в the reviewer-agent spawn prompt. |
| `decision` | Spec.md records а non-trivial approach choice с `## Considered Alternatives` section. M4 mirrors that decision к L2 для cross-session recall. (Note: when /plan (M5) ships, /plan emits the decision directly; M4-only path для inline-task mode.) |

**Trust default per M2 §5.3 row /implement: `verified`** — entries are grounded in Phase 2 code и Phase 3 reviewer findings (test-validated на entry).

**Promotion suggestion (P-M4-5).** When а `convention` entry is emitted, additionally surface а one-line suggestion в the Phase 3 final report:

```
[learnings] Pattern detected ≥3 times: "<convention summary>". Recorded к L2.
  → Consider /geniro:instructions edit <scope>.md к promote as rule.
```

Scope hint follows reviewer dimension: dim=`code-quality` → suggest `code-style.md`; dim=`architecture` → suggest `global.md`; other → "appropriate scope". Suggestion fires ONLY for `convention` type — single-occurrence `decision` emits do NOT warrant L4 promotion. The line is informational (no AUQ, no auto-edit) — user remains source-of-truth для L4 rule curation.

**L3 update site (M4 §13.3).** If Phase 2 added а new module / file, call `update-semantic --file codebase-map --append "..."` (M2 §6.3) к append а bounded entry к `_CODEBASE_MAP.md`. Lock-guarded; rc=11 (lock held) is а recoverable "skip-and-defer" — caller may retry later or skip silently.

---

### Suggest Improvements (project scope only)

Follow the canonical routing в `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` — it owns the routing table, decision logic, и presentation pattern. Skip findings already captured в L2 emit (Step 5); this step focuses on **structural improvements** (where the project records the rule) rather than knowledge capture.

`AskUserQuestion` is always-WAIT here. Plugin-file improvements (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope — use `/improve-template`.

---

### Integration Updates (M4 §7.5 step 4 — auxiliary)

**Worktree:** if working в а worktree (from Phase 1 workspace decision), leave the session in it. Do NOT call `ExitWorktree` proactively — runtime already prompts on session exit to keep or remove the worktree.

**Integrations:** if workflow files в `.geniro/workflow/` specify completion actions (status transitions, PR linking, comments), follow their instructions. Always ask the user before changing external state (issue status, comments). NEVER auto-update. If integration backend is unavailable, log warning и skip.

**AI-disclosure prefix.** When the workflow file contains а `## AI-Disclosure Prefix` section, apply the documented prefix к any comment text the skill AUTHORS before posting via the tracker MCP. Status-only updates, assignee-only updates, commit messages, and PR descriptions are excluded per the section's exclusion list. If the AI-Disclosure section is still а TODO stub, skip authoring comments entirely — post only status-only updates.

---

### Cleanup

Run cleanup directly (no agent needed):

**Pipeline artifacts** — under M1 T1 contract (`<task-dir>` is task-ephemeral, deleted at Phase Ship):

```bash
rm -rf <task-dir>  # e.g., .geniro/planning/feat-eng-123-add-oauth/
```

This deletes `spec.md`, `state.md`, `notes.md`, и any other files created during the run. Commit message, PR description, и `learnings.jsonl` (L2) are the durable records. The `.geniro/` deletion guard hook DOES allow `rm -rf .geniro/planning/<task-dir>/` (deep path), но NOT `rm -rf .geniro/` (bulk). Per-task cleanup is а fully-allowed operation.

**Temp files** — remove temporary screenshots, `.tmp`, `.bak`, `debug-*` files (not в `node_modules` or `.git`). Kill orphaned processes on agent ports (avoid touching standard dev ports). Remove stray `.log` files. Best-effort — silent failures OK.

---

## Phase 3 — Adjustment Routing (Big / Medium / Small)

Used when ship-feedback arrives via PR comments или as а follow-up `$ARGUMENTS` invocation. Pre-M4 the legacy `/follow-up` handled this; M4 absorbs it — all adjustments route back through `/implement` itself с the original spec + adjustment description as new $ARGUMENTS.

### Big — changes к data model, API contract, new endpoints

1. Write tweak description к state.md `## Adjustments` body section.
2. Re-enter Phase 1 (Analyze) — the adjusted spec.md or inline-plan becomes the fresh source-of-truth. State.md `phase:` transitions back к `analyze`.
3. Run Phase 2 (Implement) and Phase 3 (Self-review + Ship) per the standard pipeline.

### Medium — new logic, additional fields

1. Write tweak description к state.md `## Adjustments` body section.
2. Re-enter Phase 2 (Implement) — apply the delta, run test suite. State.md `phase:` transitions back к `implement`.
3. On green tests, run Phase 3 (Self-review + Ship).

### Small — styling, typo, logic tweak

1. Write tweak description к state.md `## Adjustments` body section.
2. Apply the edit inline, re-run test suite. State.md updates `## Tool log` with the side-effect.
3. Re-enter Phase 3 self-review (single round usually sufficient).

**Soft limits.** Big tweaks: after 2 rounds, suggest starting а new /implement session — fresh context provides clean separation. Medium/Small tweaks: after 3 rounds, surface а message recommending the user re-spec via `/geniro:plan` (M5).

**Loop target.** After any tweak, loop back to the Ship sub-step (Phase 3 §7.5). Pre-ship steps (Update Docs, Extract Learnings, Suggest Improvements) run once on first Ship entry и are NOT repeated on tweak rounds unless the tweak materially changes the docs/learnings/improvement surface.

---

## Definition of Done

`/geniro:implement` run is complete when:

- [ ] State.md frontmatter `phase:` is а terminal state per M4 §2.1: `done` / `ship-committed-only` / `self-review-only` / `debug-handoff` / `aborted`.
- [ ] Spec source resolved — either а spec.md / plan.md / DESIGN_DOC frontmatter file was loaded, OR inline-task mode wrote а `## Inline Plan` к state.md.
- [ ] Phase 2 ended on green tests (or accepted-failures noted in state.md `## Accepted Failures` per §6.3).
- [ ] Phase 3 5-dim reviewer loop ran (round 1 — all 5 dims; round N+1 — failing dims only); exited clean OR escalated per §7.4.
- [ ] Ship sub-step executed per the user's modifier or AUQ pick: commit-only OR push OR push+PR OR push+draft-PR OR self-review-only.
- [ ] `non-resumable-actions[]` frontmatter updated for every external side-effect (`git push`, `gh pr create`).
- [ ] L2 emit fired when triggers were met (`convention` или `decision`); promotion suggestion surfaced for `convention` emits per P-M4-5.
- [ ] L3 update fired if Phase 2 added new modules — `_CODEBASE_MAP.md` appended via `update-semantic`.
- [ ] Stop-hook evidence scan satisfied — Ship report's PASS/FAIL claims attach Evidence Blocks.
