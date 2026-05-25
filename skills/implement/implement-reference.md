# Implement Skill — Reference Material

This file contains templates, examples, and detailed procedures referenced by SKILL.md. The orchestrator reads specific sections at the relevant phase — not the entire file upfront.

**Scope:** `/geniro:implement` is a 2-phase autonomous loop (Analyze → Implement → Self-review-and-Ship).

---

## Phase 1: $ARGUMENTS semantic-parse table

No CLI flag grammar. The orchestrator parses `$ARGUMENTS` semantically at Phase 1 entry.

| `$ARGUMENTS` shape | Mode |
|---|---|
| empty | Resume current task from `<task-dir>/state.md` if one exists; else error directing the user to provide a task description. |
| contains `continue` / `resume` (standalone word, any casing) | Resume from state.md (compaction-coupled — reads `non-resumable-actions[]` to skip side-effects already completed). |
| matches a filesystem path (rel or abs) to a `.md` file | Load as spec/plan artifact. Frontmatter validated via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`. |
| free-form description, no path match | Inline-task mode: treat `$ARGUMENTS` as a raw spec description; Phase 1 produces a minimal inline plan and proceeds. |
| ambiguous (bare slug that could be a task name OR a description) | AUQ with 2-3 disambiguation options. Persist outcome to state.md frontmatter `approvals[]` with `category: disambiguate_arguments`. |
| natural-language modifier present (`don't push`, `draft only`, `stop after review`, `with PR`, `commit only`) | Honored semantically by Phase 3 Ship sub-step. Modifier survives in $ARGUMENTS and is consulted at relevant decision points. No CLI flag rewrite needed. |

**Workflow-integration plumbing.** If `.geniro/workflow/*.md` files exist with argument-detection patterns (e.g., Linear issue IDs, GitHub URLs), apply their patterns FIRST — they may inject extra context (issue body, status transition) before the semantic-parse table above runs. Integrations are non-blocking: if a workflow's backend (e.g., MCP) is unavailable, log a warning and proceed without.

**Approvals-persistence protocol:** before firing the disambiguation AUQ, check state.md frontmatter `approvals[]` for a prior entry with `category: disambiguate_arguments` matching the current $ARGUMENTS shape. If found, use the prior `picked` value and skip the AUQ. If not found, fire AUQ → on user pick, append to `approvals[]` via `atomic_state_write` before proceeding.

---

## Phase 1: Spec discovery walk-list

When `$ARGUMENTS` does not directly carry a spec path, walk these in order and stop at the first hit:

1. `<task-dir>/spec.md` — preferred (`/geniro:plan` canonical output).
2. `<task-dir>/plan.md` — alias.
3. design-doc frontmatter detect via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` — covers design docs that don't follow naming convention.

If none match AND $ARGUMENTS is non-empty free-form text → enter **inline-task mode**: write a brief inline plan to state.md body under `## Inline Plan` containing one-sentence goal, file list (best-effort), and approach summary. This becomes the source-of-truth for Phase 3 self-review (the `spec` field consumed by reviewer-agents).

---

## Phase 2: Implement — error-handling

For test-suite failures, follow the in-phase mini fix loop :

```
retry = 1
while retry ≤ 3:
inspect failing test output
edit code (or test) to address the failure
re-run test suite
if all green → exit Phase 2 → Phase 3
retry += 1
else:
escalate via AskUserQuestion (debug-handoff / accept-failure / abort, )
```

**Evidence requirement.** Every PASS/FAIL claim from the test-suite run MUST attach an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` (command, exit code, last 3 lines of output). Stop-hook scans for forbidden phrases (`"all tests pass"`, `"validation complete"`, `"ready to ship"`) without an attached Evidence Block.

**Tool log persistence.** The end-of-phase test-suite run and any subagent spawn outcomes are persisted to state.md `## Tool log` body section via `atomic_state_write` per the schema in Routine Read/Edit/Bash on local files do NOT need logging.

**Termination-reason on escalate-abort.** If the user picks "abort" at, write a `## Termination reason` body line: `repeated-failure: phase-2 retry-limit (<N> failing tests)`. Audit trail for this skill resume.

---

## Phase 3: Self-review reviewer-agent template

Spawn 5 reviewer-agents in parallel — one call per dimension, all `Agent(...)` tool uses in the SAME assistant response. Each uses `subagent_type: "reviewer-agent"` (apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` registration-degradation ladder at every spawn site).

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

Review ONLY for [dimension]. Tag findings [SEVERITY] [NEW|PRE-EXISTING] per the output contract in agents/reviewer-agent.md §Output Format.

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs.
""")
```

### The 5 dimensions

| Dimension | Criteria file | Focus |
|-----------|---------------|-------|
| `bugs` | `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md` | Logic errors, null/undefined, off-by-one, race conditions, broken invariants |
| `security` | `${CLAUDE_PLUGIN_ROOT}/skills/review/security-criteria.md` | Injection, auth/authz, secret handling, untrusted-input flows, OWASP-top-10 |
| `architecture` | `${CLAUDE_PLUGIN_ROOT}/skills/review/architecture-criteria.md` | Layering, coupling, abstractions, dead code, duplication, naming, file placement. **Also covers docs-staleness** (OQ-9 closure): explicit check for README / architecture-doc / contributing-guide references to patterns or files renamed in Phase 2. **Also covers spec-compliance**: explicit check that the Phase 2 diff matches spec.md scope — no unspec'd files touched, no spec'd requirements unaddressed. |
| `tests` | `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md` | Coverage of changed lines, edge cases, F→P invariant, brittle assertions, missing negative cases. **Pre-condition:** tests are green per Phase 2; this dim NEVER sees failing tests. |
| `code-quality` | `${CLAUDE_PLUGIN_ROOT}/skills/review/optimizations-criteria.md` + `${CLAUDE_PLUGIN_ROOT}/skills/review/guidelines-criteria.md` + `${CLAUDE_PLUGIN_ROOT}/skills/review/conventions-criteria.md` | Idiomatic style, readability, comments noise, premature abstractions, simplification opportunities. |

**Code-style pre-inline slot (code-quality + architecture reviewers only):** if the Phase 1 / Phase 3-entry L4 loader echoed `Loaded code-style.md …`, pre-inline that content under a `## Code-style instructions` header per the reviewer-agent contract. If the loader echoed `No code-style.md found — skipping.`, omit the slot. Bugs / security / tests reviewers do NOT get the slot (code-style is orthogonal).

**ACI — reviewer tool surface.** Reviewer-agents are pure-compute on the local diff: Read / Grep / Glob / Bash (read-only) only. Edit / Write / Agent / mutating Bash / external network are blocked. Enforcement: `agents/reviewer-agent.md` frontmatter `tools:` whitelist. Prompt-level reinforcement of "read-only" is a fallback layer.

**Parallel invocation:** all 5 (or fewer, on round N+1) spawns happen in ONE assistant response — multiple `Agent(...)` tool uses in the same message. Serial invocation doubles wall-time and the spec's design intent is parallelism.

### Custom reviewer dimensions (`.geniro/instructions/review-extra/`)

Round 1 only — before issuing the 5 built-in spawns, apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` to discover user-authored `review-extra/<slug>.md` files. The helper returns a list of spawn-specs (slug, dimension-label `custom:<slug>`, model, criteria-content, severity-default, source-path) after applying its `paths:` filter against the changed-files list and enforcing the ≤10 cap. Append one `Agent(subagent_type="reviewer-agent",...)` call per spec to the SAME parallel batch as the 5 built-ins (one assistant turn, one parallel batch — same rule as `/review` Phase llm-spawn and `/refactor` Phase verify per `_shared/load-custom-reviewers.md` §How consumers use the spawn-specs).

Round N+1: re-fire a custom reviewer only if its prior round flagged a CRITICAL or HIGH finding (mirrors the failing-dim rule for built-ins). The custom reviewer's spawn-spec list is recomputed only on round 1; round N+1 reuses the round-1 spec cache.

If `.geniro/instructions/review-extra/` does not exist OR the glob returns zero matches after path filtering, this section is a silent no-op — the round proceeds with the 5 built-ins.

---

## Phase 3: Bounded fix loop

```
round = 1
while round ≤ 3:
spawn reviewer-agents on failing dimensions only
round 1: all 5 dims
round N+1: only dims that flagged in round N
collect findings
if no findings across all dimensions:
break # exit to Phase 3 Ship sub-step
apply fixes inline (single Edit-driven sub-loop, no further agent spawns)
re-run project test suite (must stay green)
round += 1
else:
# round 4 would start — DO NOT enter it
escalate via AskUserQuestion
```

**Round N+1 only re-runs failing dimensions.** Dimensions that passed round N are NOT re-spawned — bounds cost and avoids re-litigating clean code.

**Escalation at exhaust.** When the loop hits round 3 with unresolved findings:

1. Do NOT silently push or claim completion.
2. Surface via `AskUserQuestion` (header: `"Resolve findings"`) with:
- Summary of unresolved findings per dimension (top 3 each).
- Options:
- **A) Hand off to /geniro:debug** — state.md transitions to `phase: debug-handoff` (terminal). Caller resumes via `/geniro:debug` using state.md as a T2 handoff.
- **B) Accept findings and proceed to ship** — state.md adds `## Accepted Findings` body block recording the decision. Transitions to `phase: ship` (proceeds to Ship sub-step). Architecture reviewer prompt in future runs sees the accepted-findings list and may flag scope concerns.
- **C) Abort** — state.md transitions to `phase: aborted` (terminal). Work uncommitted on disk for manual takeover.
3. State.md records `## Termination reason` body line on aborted/handoff: `repeated-failure: phase-3 review-round-limit (<N> unresolved findings)`.

The Always-WAIT contract applies: empty `AskUserQuestion` answer = upstream bug, fall back to plain text and re-ask. NEVER auto-default to any option.

---

## Phase 3 — Ship sub-step

### Pre-Ship Visual Verification

Runs only when BOTH conditions hold: (a) the Phase 2 changed-files list contains at least one file matching the UI-file detection rule (`${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` §UI-file detection rule), AND (b) Playwright MCP is available — check that `mcp__plugin_playwright_playwright__browser_navigate` is in your tool list. If Playwright MCP is NOT available, skip this entire section and note in the ship report: "Pre-Ship Visual Verification skipped — Playwright MCP not installed."

When both conditions hold, prompt the user via a STANDALONE `AskUserQuestion` with header "Smoke-test" as the ONLY question in that call — never batch it with the ship-mode AUQ. If the user picks "Yes — walk through it", execute this sequence:

1. **Detect target URL.** Probe dev-server ports in order — 3000 (Next.js), 5173 (Vite), 8080 (generic), 4321 (Astro), 4200 (Angular) — via `curl -s -o /dev/null -w "%{http_code}" http://localhost:PORT`. On the first 200, fetch `/` and check the response `<title>` or a known marker matches the project's `package.json` `name`; if uncertain, `AskUserQuestion` "Detected server on :PORT — is this the project under test?" before navigating. If no port responds, walk up from the primary changed UI file to the nearest `package.json` containing a `dev`/`start`/`serve` script (monorepo layouts: `apps/<name>/package.json`, `packages/<name>/package.json`). Choose package manager by lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb` → bun, else npm). Run with `run_in_background: true`, record the PID, poll `GET /` until 200 or 30s timeout. On timeout, ask the user "Skip verification" / "Retry" / "Enter URL manually".

2. **Infer the target route.** Map the primary changed UI file to a URL path: `app/<segment>/page.tsx` → `/<segment>`, `pages/<name>.tsx` → `/<name>`, `src/routes/<name>/+page.svelte` → `/<name>`. Leaf component (e.g., `components/Button.tsx`) → fall back to `/` and ask the user where it renders. Navigate with `mcp__plugin_playwright_playwright__browser_navigate`.

3. **Baseline snapshot.** Call `mcp__plugin_playwright_playwright__browser_snapshot` to capture the accessibility tree with element refs. Every subsequent interaction (`browser_click`, `browser_type`, `browser_fill_form`) requires a `ref` from this snapshot.

4. **Console + network sanity check.** Call `mcp__plugin_playwright_playwright__browser_console_messages` — treat any `error`-level entry as a failure worth reporting. Call `mcp__plugin_playwright_playwright__browser_network_requests` — flag same-origin 4xx/5xx responses. Re-run after step 5 and step 6.

5. **Targeted interaction.** Using refs from step 3, perform 1-3 actions that exercise the specific behavior changed in this run. Cap at 5 total interactions. Re-snapshot after each to get fresh refs.

6. **Responsive sweep** — only when the diff includes any `.css`/`.scss`/`.sass`/`.less`/`.styled.*` file, OR a JSX/TSX hunk touching `className`, `style`, or a CSS-module import. Call `mcp__plugin_playwright_playwright__browser_resize` to `{width: 375, height: 667}` (mobile) then `{width: 1280, height: 800}` (desktop). Snapshot each. Skip entirely for pure logic changes.

7. **Visual record.** Final `mcp__plugin_playwright_playwright__browser_take_screenshot` with `fullPage: true`, saved under `<task-dir>/playwright-verify.png`. This is the artifact — do NOT claim a pixel-diff against a prior state (no baseline image exists).

8. **Cleanup.** If step 1 spawned a dev server (PID recorded), send `kill -TERM <pid>`; if still alive after 3s, escalate with `kill -KILL <pid>`. NEVER kill servers the user had running before verification — only clean up what this step spawned.

**Reporting:** summarize in 3-5 lines — interaction result, console/network status, responsive issues (if swept), screenshot path. If issues were found, route via `AskUserQuestion`: "Fix and re-verify" (route through Adjustment Routing Small tweak path below — this section re-fires after the next clean review if UI files remain in the diff), "Ship anyway with noted issues" (append to state.md `## Visual Verification Notes` and proceed to ship-mode AUQ), or "Abort" (`phase: aborted` terminal).

---

### Commit + Push + PR

**Step 2 — Commit.** Stage relevant files, `git commit` with conventional message (e.g., `feat(auth): add OAuth login [ENG-123]`). Task ID inferred from spec.md / state.md metadata. If a workflow file specifies commit-message format (e.g., appending issue ID), follow that format.

**Step 3 — Ship-mode AUQ.** Push is draft-grade (branch becomes visible on remote but carries no review weight); PR creation is commit-grade. The AUQ gates only the PR-creation decision.

Use `AskUserQuestion` (header: `"Ship mode"`):

- **Label:** `"Open draft PR (Recommended)"` / **Description:** `"git push then gh pr create --draft. Safest default — lets you review before marking ready."`
- **Label:** `"Open PR"` / **Description:** `"git push then gh pr create (ready-for-review). Appends task ID to PR title."`
- **Label:** `"Just push (no PR)"` / **Description:** `"git push origin <branch>. No PR created. Done."`

The user can always type a custom response via "Other":
- **"Review diff"** (via Other) → show diff via `git diff origin/HEAD...HEAD`, loop back to ship-mode AUQ.
- **"Don't push"** (via Other; semantically equivalent to the "don't push" inline modifier below) → commit stays local, no push. State.md → `phase: ship-committed-only` (terminal). The Phase 3 commit (step 2) has already executed at this point — this option only suppresses step 3's push, not the upstream commit.

**Approvals-persistence protocol (, step 3):** before firing the ship-mode AUQ, check state.md frontmatter `approvals[]` for a prior entry with `category: ship_mode`. If found, use prior `picked` value and skip the AUQ (typical compaction-resume: user already picked in the original flow). If not found, fire AUQ → on pick, append to `approvals[]` via `atomic_state_write` before executing the chosen action.

**L2 emit on rejection signal:** AFTER appending to `approvals[]`, source `${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh` and invoke:

```bash
emit_rejection_if_signal \
"/geniro:implement" "<branch>" "ship_mode" \
"<recommended ship-mode label>" "<picked label>" "<recommended label>"
```

`<branch>` = current git branch (or `global` if not detectable). Recommended label is whichever option carries the `(Recommended)` suffix per ship-mode AUQ rules (typically «Open draft PR» by default; «Commit + push» when user has just selected «Post findings as Draft PR review» from a chained AUQ). Helper detects rejection signals and emits L2 entry — acceptance is a no-op. Future /implement Phase 1 surface «user consistently picks X over Y» pattern hint.

**Step 4 — Non-resumable-actions update.** After each side-effect that cannot be replayed safely (`git push`, `gh pr create`, posted PR comment), append a structured entry to state.md frontmatter `non-resumable-actions[]` array via `atomic_state_write`. Entry schema `{action, completed-at, <action-specific-fields>}`. Write occurs AFTER the side-effect succeeds — atomic, so partial-write corruption is impossible mid-crash.

**Inline modifiers from $ARGUMENTS** (semantic parsing per Phase 1 table) override the ship-mode AUQ deterministically:

| Modifier in $ARGUMENTS | Effect |
|---|---|
| "don't push" / "no push" / "commit only" | Commit succeeds, no push. State.md → `phase: ship-committed-only` (terminal). Skip ship-mode AUQ. |
| "draft only" / "draft PR" / "open draft" | Push + `gh pr create --draft`. State.md → `phase: done`. Skip ship-mode AUQ. |
| "open PR" / "create PR" / "with PR" | Push + `gh pr create` (ready-for-review). State.md → `phase: done`. Skip ship-mode AUQ. |
| "stop after review" | Exit Phase 3 BEFORE commit. Surface clean review status as the deliverable. State.md → `phase: self-review-only` (terminal). |

---

### Update Docs

Check whether existing docs need updating based on what was implemented. **Skip if nothing changed that affects documented surfaces.** This is a thin fallback over the Phase 3 architecture reviewer's docs-staleness check — if that reviewer already surfaced doc-update findings, they would have been fixed inline during the fix loop. This step catches anything left over.

Scan the diff against main and check:
- Do any existing docs reference patterns/files that were renamed, moved, or superseded?
- Did this implementation introduce a new pattern that should be documented as a canonical example?
- Do README, architecture docs, or contributing guides need patches?

If updates needed, delegate to a general-purpose subagent with `model="haiku"` containing the diff summary + the doc files to patch. Keep changes minimal — patch what's stale or add a new reference, don't rewrite docs. If no docs need updating, skip silently.

---

### Extract Learnings

Per master plan, the standalone `/learnings` skill is deleted; learning capture is an auto-step at the end of /implement. Phase 3 calls the L2 helper `emit-learning` when conditions are met.

**Emit triggers per + **

| Type | When emits |
|---|---|
| `convention` | Phase 3 architecture or code-quality reviewer reports ≥3 instances of same pattern in changed code. Threshold tuning lives in the reviewer-agent spawn prompt. |
| `decision` | Spec.md records a non-trivial approach choice with `## Considered Alternatives` section. Mirrors that decision to L2 for cross-session recall. (Note: when /plan ships, /plan emits the decision directly; inline-task path only.) |

**Trust default per row /implement: `verified`** — entries are grounded in Phase 2 code and Phase 3 reviewer findings (test-validated on entry).

**Promotion suggestion.** When a `convention` entry is emitted, additionally surface a one-line suggestion in the Phase 3 final report:

```
[learnings] Pattern detected ≥3 times: "<convention summary>". Recorded to L2.
→ Consider /geniro:instructions edit <scope>.md to promote as rule.
```

Scope hint follows reviewer dimension: dim=`code-quality` → suggest `code-style.md`; dim=`architecture` → suggest `global.md`; other → "appropriate scope". Suggestion fires ONLY for `convention` type — single-occurrence `decision` emits do NOT warrant L4 promotion. The line is informational (no AUQ, no auto-edit) — user remains source-of-truth for L4 rule curation.

**L3 update site.** If Phase 2 added a new module / file, call `update-semantic --file codebase-map --append "..."` to append a bounded entry to `_CODEBASE_MAP.md`. Lock-guarded; rc=11 (lock held) is a recoverable "skip-and-defer" — caller may retry later or skip silently.

---

### Suggest Improvements (project scope only)

Follow the canonical routing in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` — it owns the routing table, decision logic, and presentation pattern. Skip findings already captured in L2 emit (Step 5); this step focuses on **structural improvements** (where the project records the rule) rather than knowledge capture.

`AskUserQuestion` is always-WAIT here. Plugin-file improvements (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope — submit a PR to the plugin repo OR edit your local plugin install directly.

---

### Integration Updates

**Worktree:** if working in a worktree (from Phase 1 workspace decision), leave the session in it. Do NOT call `ExitWorktree` proactively — runtime already prompts on session exit to keep or remove the worktree.

**Integrations:** if workflow files in `.geniro/workflow/` specify completion actions (status transitions, PR linking, comments), follow their instructions. Always ask the user before changing external state (issue status, comments). NEVER auto-update. If integration backend is unavailable, log warning and skip.

**AI-disclosure prefix.** When the workflow file contains a `## AI-Disclosure Prefix` section, apply the documented prefix to any comment text the skill AUTHORS before posting via the tracker MCP. Status-only updates, assignee-only updates, commit messages, and PR descriptions are excluded per the section's exclusion list. If the AI-Disclosure section is still a TODO stub, skip authoring comments entirely — post only status-only updates.

---

### Cleanup

Run cleanup directly (no agent needed):

**Pipeline artifacts** — under T1 contract (`<task-dir>` is task-ephemeral, deleted at Phase Ship):

```bash
rm -rf <task-dir> # e.g.,.geniro/planning/feat-eng-123-add-oauth/
```

This deletes `spec.md`, `state.md`, `notes.md`, and any other files created during the run. Commit message, PR description, and `learnings.jsonl` (L2) are the durable records. The `.geniro/` deletion guard hook DOES allow `rm -rf.geniro/planning/<task-dir>/` (deep path), but NOT `rm -rf.geniro/` (bulk). Per-task cleanup is a fully-allowed operation.

**Temp files** — remove temporary screenshots, `.tmp`, `.bak`, `debug-*` files (not in `node_modules` or `.git`). Kill orphaned processes on agent ports (avoid touching standard dev ports). Remove stray `.log` files. Best-effort — silent failures OK.

---

## Phase 3 — Adjustment Routing (Big / Medium / Small)

Used when ship-feedback arrives via PR comments or as a follow-up `$ARGUMENTS` invocation. All adjustments route back through `/implement` itself with the original spec + adjustment description as new $ARGUMENTS.

### Big — changes to data model, API contract, new endpoints

1. Write tweak description to state.md `## Adjustments` body section.
2. Re-enter Phase 1 (Analyze) — the adjusted spec.md or inline-plan becomes the fresh source-of-truth. State.md `phase:` transitions back to `analyze`.
3. Run Phase 2 (Implement) and Phase 3 (Self-review + Ship) per the standard pipeline.

### Medium — new logic, additional fields

1. Write tweak description to state.md `## Adjustments` body section.
2. Re-enter Phase 2 (Implement) — apply the delta, run test suite. State.md `phase:` transitions back to `implement`.
3. On green tests, run Phase 3 (Self-review + Ship).

### Small — styling, typo, logic tweak

1. Write tweak description to state.md `## Adjustments` body section.
2. Apply the edit inline, re-run test suite. State.md updates `## Tool log` with the side-effect.
3. Re-enter Phase 3 self-review (single round usually sufficient).

**Soft limits.** Big tweaks: after 2 rounds, suggest starting a new /implement session — fresh context provides clean separation. Medium/Small tweaks: after 3 rounds, surface a message recommending the user re-spec via `/geniro:plan`.

**Loop target.** After any tweak, loop back to the Ship sub-step (Phase 3). Pre-ship steps (Update Docs, Extract Learnings, Suggest Improvements) run once on first Ship entry and are NOT repeated on tweak rounds unless the tweak materially changes the docs/learnings/improvement surface.

---

## Definition of Done

`/geniro:implement` run is complete when:

- [ ] State.md frontmatter `phase:` is a terminal state `done` / `ship-committed-only` / `self-review-only` / `debug-handoff` / `aborted`.
- [ ] Spec source resolved — either a spec.md / plan.md / DESIGN_DOC frontmatter file was loaded, OR inline-task mode wrote a `## Inline Plan` to state.md.
- [ ] Phase 2 ended on green tests (or accepted-failures noted in state.md `## Accepted Failures` per).
- [ ] Phase 3 5-dim reviewer loop ran (round 1 — all 5 dims; round N+1 — failing dims only); exited clean OR escalated per- [ ] Ship sub-step executed per the user's modifier or AUQ pick: commit-only OR push OR push+PR OR push+draft-PR OR self-review-only.
- [ ] `non-resumable-actions[]` frontmatter updated for every external side-effect (`git push`, `gh pr create`).
- [ ] L2 emit fired when triggers were met (`convention` or `decision`); promotion suggestion surfaced for `convention` emits per.
- [ ] L3 update fired if Phase 2 added new modules — `_CODEBASE_MAP.md` appended via `update-semantic`.
- [ ] Stop-hook evidence scan satisfied — Ship report's PASS/FAIL claims attach Evidence Blocks.
