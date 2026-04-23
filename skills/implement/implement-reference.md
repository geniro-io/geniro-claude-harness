# Implement Skill — Reference Material

This file contains templates, examples, error tables, and detailed procedures referenced by SKILL.md. The orchestrator reads specific sections at the relevant phase — not the entire file at once.

---

## Phase 1: Auto-Detection Table

| What you say | What the skill detects | Behavior |
|---|---|---|
| `/geniro:implement milestone 2` or `/geniro:implement milestone 2 ship it` | Milestone reference (from /geniro:decompose) | Glob `<task-dir>/milestone-2-*.md`, load that milestone file as the implementation target; skip Phase 1 discovery |
| `/geniro:implement <path-to-milestone-N-foo.md>` | Explicit milestone path | Load that milestone file as the implementation target; skip Phase 1 discovery |
| `/geniro:implement continue` | Continue a decomposed pipeline | Read `<task-dir>/state.md` `Milestones:` field, pick the first non-completed milestone, load its file |
| `/geniro:implement add OAuth login` | Plain description | Full discovery with interactive questions |
| `/geniro:implement ENG-123` | Issue tracker reference (from workflow) | Fetches issue via configured integration, uses as context |
| `/geniro:implement https://linear.app/team/issue/ENG-123` | Issue tracker URL (from workflow) | Extracts issue ID, fetches via configured integration |
| `/geniro:implement ENG-123 add OAuth login` | Issue reference + description | Fetches issue, supplements with description |
| `/geniro:implement F3` or `/geniro:implement F3 add OAuth login` | Geniro feature ID (`F<n>`) | Read `.geniro/planning/FEATURES.md`, look up the row for the matching ID, use its description (and linked spec file in the Notes column, if present) as the implementation target |
| `/geniro:implement just do it` or `ASAP` | Urgency signals | Auto mode: skip interactive questions |
| `/geniro:implement I think we should add OAuth` | Tentative language | Assumptions mode: propose plan |

**Detection rules (checked in order):**
0. **Milestone reference** — patterns (checked in priority order): (a) `^milestone\s+(\d+)\b` at start of `$ARGUMENTS`, (b) `$ARGUMENTS` references a path ending in `milestone-<N>-*.md`, (c) `$ARGUMENTS` equals `continue` AND `<task-dir>/state.md` contains a `Milestones:` field. If any matches, load the milestone file via Phase 2 pre-check rule 1 and skip remaining rules. Milestone detection takes priority over workflow files and feature IDs because the user explicitly pointed at a specific unit of work.
1. Check `.geniro/workflow/*.md` for argument detection patterns. Apply them in order before falling through to mode signal detection.
2. **Geniro feature ID** — pattern `^F\d+(\s|$)` at start of `$ARGUMENTS`. Read `.geniro/planning/FEATURES.md` if present and look up the matching row. If FEATURES.md is missing or the ID is not found, treat the rest of `$ARGUMENTS` as a plain description and warn the user once. If found, capture the row's description and spec-file path (from the Notes column) — these get persisted to `state.md` (see SKILL.md Phase 1).
3. **Auto-mode signals** — keywords like "just do it", "ASAP", "no questions", "auto", "quick" -> skip interactive questions, pick recommended defaults for all gray areas
4. **Assumptions-mode signals** — tentative language like "I think", "maybe", "what if", "should we" -> propose plan with assumptions, let user correct
5. **No special signals** — explicitly ask the user which mode to use (see "Mode Selection prompt" below). Default to interactive

If a workflow integration's backend (e.g., MCP) is unavailable, log a warning and proceed without — all integrations are non-blocking.

**Mode Selection prompt** (fires from Step 1 of SKILL.md when no explicit signal was detected in `$ARGUMENTS`):

Use `AskUserQuestion`:
- **Question:** "How should I run this implementation?"
- **Header:** "Mode"
- **Options:**
  - Label: "Interactive (Recommended)" / Description: "Full discovery — I'll ask about gray areas, confirm the architect's plan, and check before shipping."
  - Label: "Auto mode" / Description: "Pick recommended defaults for gray areas and auto-approve the architect's plan. I still WAIT at the ship gate, the Stage C fix-loop after 3 rounds, and the Phase 7 Step 4.5 ship-anyway prompt — see §Auto Mode Behavior."
  - Label: "Assumptions" / Description: "I'll propose a plan with my best guesses on gray areas — you correct anything wrong before architecting."

Skip the prompt entirely if `$ARGUMENTS` already contained an explicit auto-mode signal (rule 3) or assumptions-mode signal (rule 4). Persist the chosen mode in `<task-dir>/state.md` under a `Mode:` line so resumed runs and downstream phases read it without re-prompting.

**Example discovery questions (interactive mode, batch 3-5). IMPORTANT — include the git workspace question in this same batch, do NOT defer it to a separate prompt:**
- Scope: Backend-only? Frontend? Both? (recommend: match existing split)
- Backwards compat: Support old API during transition? (recommend: yes, deprecation warning)
- Performance: Any constraints or targets? (recommend: <100ms latency for endpoints)
- Testing: Unit/integration/e2e? (recommend: maintain current test coverage)
- Rollout: Gradual rollout or all-at-once? (recommend: feature flag + gradual)
- **Git workspace:** A) New feature branch (recommend for most features), B) Current branch, C) Git worktree (for risky/experimental changes with instant rollback without touching main working directory, parallel work when running multiple Claude sessions on same repo, or long-running features where you need to context-switch — isolates entire implementation in a separate working tree)

---

## Phase 1 Step 0: Complexity Gate

**Purpose:** Catch Trivial tasks at entry and suggest the lighter `/geniro:follow-up` skill before spending opus tokens on architect-agent and Phase 1 Discovery.

**When to SKIP the gate (any of these applies → proceed straight to Step 1, no prompt):**
1. Milestone reference detected (Auto-Detection Table rule 0 matched).
2. On-disk plan-file path present in `$ARGUMENTS` (handled by Phase 2 pre-check rule 4).
3. Plan-mode conversation plan is active (handled by Phase 2 pre-check rule 2).
4. `state.md` already contains a `Phase 1 Step 0:` line (resume or second-run already decided this gate).
5. `<task-dir>/state.md` `Completed phases` includes Phase 1 (interrupted after Phase 1 — do not re-prompt).

**When the gate FIRES:** none of the skip conditions apply AND `$ARGUMENTS` is a natural-language request describing the change.

**Signals used (reuse follow-up's rubric — do NOT duplicate):**

Read `skills/follow-up/SKILL.md` §"Step 2: Complexity Assessment" for the canonical 9 hard escalation signals and the Trivial/Small/Medium/Too-large tiers. Apply those definitions here verbatim. If that file moves, update this reference — the rubric must live in exactly one place.

**Decision procedure:**

1. **Hard-signal scan.** Read `$ARGUMENTS` and any obvious file mentions. If any of follow-up's 9 hard escalation signals fire (new entity/table/migration, new endpoint/page, auth/permissions, new module, 3+ modules, open-closed violation, new async/queue, new external integration, ambiguous intent) → proceed silently to Step 1, no prompt. Do NOT offer the fast-path.
2. **Trivial assessment.** Otherwise, estimate whether the request reads as Trivial per follow-up's Trivial definition (see §"Step 2: Complexity Assessment" in `skills/follow-up/SKILL.md`). If unclear, proceed silently to Step 1 — the gate only fires on a clear Trivial signal.
3. **If Trivial AND no hard signals:** use `AskUserQuestion` with header "Skill" and these options (present in this order — the user explicitly invoked `/geniro:implement`, so list it first):
   - "Continue with /geniro:implement — full architect review"
   - "Hand off to /geniro:follow-up — lighter pipeline for Trivial changes"
4. **If user picks follow-up:** print `/geniro:follow-up <original-request>` as the exact command to run next and STOP the pipeline. Do NOT create a task directory — the pipeline is aborted before any state is written.
5. **If user picks implement (or gate did not fire):** proceed to Step 1, which creates the task directory. After Step 1 writes the `Mode:` line, append `Phase 1 Step 0: full pipeline` as an additional line in `state.md`. (If the gate was skipped, use `Phase 1 Step 0: skipped — <reason>` instead, where reason is one of: `milestone`, `plan-path`, `plan-mode`, `resume`.)
6. **If not clearly Trivial (Small/Medium/unclear):** proceed silently to Step 1 without prompting. The gate is biased toward the heavier path — only fires on clear Trivial signal.

**Anti-rationalization:**

| Reasoning | Why it's wrong |
|---|---|
| "Looks Trivial enough, skip even with a hard signal" | Hard signals override size. A 1-file auth change is Medium-complexity minimum. |
| "User said it's simple, trust them" | User-stated simplicity is not a signal — apply the rubric objectively. |
| "Skip the prompt, just redirect to follow-up" | The gate is a `AskUserQuestion` WAIT. User must confirm — they may want architect review even for a typo. |
| "Also offer /geniro:debug as an option" | Out of scope for this gate. Debug has its own entry via `/geniro:debug`. |

---

## Auto Mode Behavior

Canonical table for what every WAIT gate does when `<task-dir>/state.md` shows `Mode: auto` (set either by rule 3 of §Phase 1 Auto-Detection Table or by the Mode Selection prompt). Skill orchestrator MUST read `Mode:` from state.md at every gate and consult this table — do not auto-resolve gates not listed here.

| Gate | Phase / Step | Auto-mode action |
|---|---|---|
| Complexity gate | Phase 1, Step 0 | Auto-proceed with full pipeline. Skip `AskUserQuestion`. Append `Phase 1 Step 0 — complexity gate → auto-proceed (full pipeline)` to `state.md` "Auto-mode decisions". Rationale: auto-mode runs are typically CI or non-interactive — fast-path redirect requires a human to run the new command, so auto-mode defaults to the heavier path the user already invoked. |
| Gray-area resolution | Phase 1, Step 7 | Pick recommended default for each question; append one-liner per decision to `state.md` "Auto-mode decisions" |
| Git workspace | Phase 1, Step 7 (in same batch) | Option A (new branch). If already on a feature branch (not `main`/`master`/`develop`), Option B |
| Existing-plan skeptic blockers | Phase 2 pre-check | Always-WAIT (auto-using a flagged plan is unsafe — user must see the concerns) |
| Plan approval | Phase 3 | **Auto-approve.** Print plan summary (path + heading + step count + skeptic validation summary: N blockers, M warnings) and the line "Auto-approved spec — see `<plan-file>`. Interrupt now if you want to revise." Skip `AskUserQuestion`. Proceed to Phase 4 |
| Compact prompt | Phase 3 (post-approval) | "Continue now" (skip compaction). Skip `AskUserQuestion` |
| Stage C fix loop after 3 rounds | Phase 6 | **Always-WAIT.** Auto-shipping known CRITICAL/HIGH issues is unsafe. Surface the `AskUserQuestion` regardless of mode |
| Suggest improvements | Phase 7, Step 3 | "Skip" (defer improvements; user can run `/geniro:follow-up` later) |
| Pre-Ship Visual Verification | Phase 7, Step 4.5 | "Skip — already verified". If Step 4.5 itself was forced and surfaced issues, the follow-up question is **always-WAIT** (auto-shipping UI regressions is unsafe) |
| Ship decision | Phase 7, Step 5 | **Always-WAIT.** Controls commit/push/PR. User must explicitly choose |
| Cleanup planning artifacts | Phase 7, Step 8 | "Keep" (preserve artifacts; safe default) |
| Next-milestone prompt | Phase 7 Step 8 (milestone-mode only) | "Compact first, then continue". Print the `/compact` instruction + `/geniro:implement continue` resume command. Skip `AskUserQuestion` |

**Auditability:** every auto-resolved decision MUST be appended to `<task-dir>/state.md` under a section named "Auto-mode decisions" with one line per gate: `Phase X Step Y — <gate name> → <chosen option>`.

---

## Phase 4: Decomposition Example

**Example decomposition for "Add user settings page with API":**
```
WU-1 (backend-agent): DB migration + Settings model + repository    [files: migration.sql, settings.model.ts, settings.repo.ts]
WU-2 (backend-agent): Settings service + validation logic            [files: settings.service.ts, settings.validator.ts, settings.service.test.ts]
WU-3 (backend-agent): API route + controller + API tests             [files: settings.controller.ts, settings.routes.ts, settings.api.test.ts]
WU-4 (frontend-agent): Settings page component + state               [files: SettingsPage.tsx, useSettings.ts, SettingsPage.test.tsx]
WU-5 (frontend-agent): Settings form components + styling            [files: SettingsForm.tsx, SettingsField.tsx, settings.css]
WU-6 (backend-agent): Infra cleanup — env vars + terraform + codegen [files: .env.example, main.tf, generated/api-client.ts]

Dependency graph:
  Wave 1: WU-1 (no deps)  |  WU-4 (no backend deps - uses mock API)  |  WU-5 (no deps)
  Wave 2: WU-2 (depends on WU-1 model)
  Wave 3: WU-3 (depends on WU-2 service)  ->  WU-6 (codegen + cleanup, depends on WU-3 API)
  Wave 4: update WU-4 with real API types from WU-6 codegen
  Hotspot: routes/index.ts (register new route) — done last (Step 5 micro-edit)
```

Note: WU-6 groups three small steps (env vars, terraform, codegen) into one WU — more efficient than 3 separate agents, but still delegated, never done by orchestrator.

---

## Phase 4: Agent Delegation Template

When spawning any implementation agent, use this template:

```markdown
## Task — Work Unit [WU-N]
[Copy the relevant Steps from the plan file for this WU — NOT the entire plan, just this WU's steps with their files, details, and verify criteria]

## Definition of Done
- [ ] [File X created/modified with specific content]
- [ ] [Test file Y created with unit/integration tests for all new logic]
- [ ] [Tests pass for this WU's scope — new AND existing]
- [ ] [No changes outside the listed files]

## Pre-Inlined Context
[Paste file contents you already read — saves agent from re-reading]
[If Wave 2+: include relevant outputs from prior wave agents]

## Project Context (for backend-agent / frontend-agent)
[The backend-agent and frontend-agent read CLAUDE.md at runtime for project context.
No additional context injection needed — the agents discover project context automatically.]

## Codebase Conventions
[Paste the CONVENTIONS_BRIEF section from spec file — naming patterns, file structure, error handling, import style, test patterns. Include 1-2 exemplar file snippets showing the patterns to follow.]
Match existing patterns exactly. Find the closest existing example and follow it.

## Design Conventions (when frontend files in scope)
[If the spec's CONVENTIONS_BRIEF includes a DESIGN_CONVENTIONS subsection, paste it here. Frontend-agent uses this as anchor context for tokens, primitives, exemplars, scales — so design isn't re-discovered every cycle. If no design system was detectable, paste the greenfield baseline statement from the spec.]

## UI Intent (when UI Preview Gate ran — paste contents of `<task-dir>/ui-preview.md` if it exists; otherwise omit this section entirely)
[The approved textual UI description from Phase 3 Step 0. Treat as authoritative visual intent — match it exactly. If it contradicts the plan, the UI Intent wins; stop and surface the contradiction.]

## Milestone Context (when milestone-mode — paste the milestone's `## Upstream Dependencies` section + the master plan's most recent `## Implementation Notes (Milestone <N-1>)` entry here; otherwise omit this section entirely)
[Upstream milestone summaries and non-obvious gotchas from prior milestones. Treat as authoritative context — do NOT re-derive what prior milestones already decided. If this contradicts the milestone's Files Affected table, the Files Affected table wins and you surface the contradiction.]

## Tests — MANDATORY (do not skip)
Write tests alongside your implementation. Every new source file MUST have a corresponding test file.
- Unit tests next to the source file for every new/changed service, function, or component
- Integration tests if touching data access, multi-service logic, or API endpoints
- Follow patterns from nearby existing test files. Extend existing specs — don't rewrite.
- Test file naming: match the project's convention (e.g., `foo.test.ts`, `foo.spec.ts`, `__tests__/foo.test.ts`)
- Minimum per source file: 1 happy path test + 2 edge case/error tests

## Verify Your Work
After implementation and tests are written, run these checks yourself:
1. Run the project's test command — all tests must pass (new and existing)
2. Run the project's lint/format command — fix any issues
3. Run the project's build/typecheck command — must compile cleanly
If any check fails, fix the issue and re-run. Do not report success with failing checks.

After all checks pass, include this structured section at the end of your response:

## Checks Report
- build: PASS|FAIL [error summary if fail]
- lint: PASS|FAIL [error summary if fail]
- test: PASS|FAIL [error summary if fail]
- typecheck: PASS|FAIL|SKIP [error summary if fail]

## Requirements
- Follow project conventions as documented in the Codebase Conventions section above
- Do NOT run git add/commit/push — the orchestrator handles git
- Do NOT modify files outside your WU scope: [list files]
- Do NOT add abstractions, wrappers, or patterns not present in the exemplar files — a separate simplification pass handles code quality
- Report: files changed, **test files created**, what was done, test results, checks report, any issues encountered
```

---

## Phase 4: Error Handling

| Error | Recovery |
|-------|----------|
| Agent produces non-compiling code | Forward raw error output to fixer agent — do NOT diagnose or read source files yourself |
| Agent creates a file not in the milestone's Files Affected table (milestone-mode) | Revert that file, re-run agent with explicit scope constraint: "Files Affected table is the hard boundary; if the milestone is missing a file, STOP and report back — do NOT add it." |
| Agent modifies files outside its WU scope | Revert those changes, re-run agent with stricter scope constraint |
| Agent ignores conventions | Re-spawn agent with exemplar files pre-inlined and stricter convention instructions |
| Agent timeout or garbage output | **RETRY:** re-dispatch with enriched context (add error details, relevant files, conventions). If retry fails: **DECOMPOSE** the WU into smaller sub-tasks. If still failing: **PRUNE** — revert WU, mark BLOCKED, continue to next WU |

**Blocked WU handling:** When a WU is marked BLOCKED, commit successful WUs from the wave, defer WUs that depend on the blocked one, continue independent WUs in the next wave. Present all blocked WUs to user after independent work completes.

---

## Phase 5: Simplify Agent Template

Spawn a **general-purpose** subagent with `model="sonnet"` and the simplify criteria. Sonnet is sufficient for cleanup work that follows explicit criteria — opus-level reasoning is unnecessary here. Pre-read the criteria file and the changed file list, then delegate:

```markdown
## Task: Simplify Changed Files

You are a code simplifier. Review the changed files and make them cleaner, simpler, and more consistent — without changing behavior.

## Criteria
[Pre-inline the contents of `${CLAUDE_PLUGIN_ROOT}/skills/deep-simplify/simplify-criteria.md` here — read it first, paste it in]

## Changed Files
[List the files changed by implementation, from git diff --name-only]

## Pipeline
1. Read each changed file + its immediate neighbors for context
2. Run three analysis passes (Reuse, Quality, Efficiency) from the criteria
3. Classify findings as P1/P2/P3
4. Apply P1 and P2 fixes. Skip P3 (report only).
5. Report what was changed using the Completion Report format from the criteria

## Requirements
- Zero behavior change — preserve exact inputs, outputs, side effects
- Do NOT run git add/commit/push
- Do NOT modify files outside the changed file list (unless extracting a shared utility)
- Never delete or weaken test assertions
- Report: files modified, fixes applied, P3 notes
```

---

## Phase 6: Stage A — Automated Checks Detail

Before running checks, inspect implementation agent reports for a `## Checks Report` section. If ALL agents reported PASS for build, lint, and test AND no code was modified after their checks ran (no simplification step in Phase 5 modified files, no fixer agents touched code), skip Steps 1–2 below — proceed directly to Step 3 (codegen check). If any agent reported FAIL, or any agent's report is missing a Checks Report, or code was modified after the agents ran (simplification in Phase 5 modified files, or a fixer agent touched code), run all checks below.

If checks need to run: delegate the **fix** to an implementer agent — do not fix code yourself.

1. **Autofix:** Run lint/format fix commands from CLAUDE.md. Attempt auto-fixable issues first.

2. **Full check:** Run build + lint + test using the backpressure wrapper:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh"
   run_silent "Build" "<build_cmd>"
   run_silent "Lint" "<lint_cmd>"
   run_silent "Tests" "<test_cmd>"
   ```
   Use commands from CLAUDE.md's Essential Commands section. If backpressure.sh is not available, run commands directly but pipe passing output to /dev/null and capture only stderr + exit code.

3. **Codegen check** (if applicable — GraphQL, OpenAPI, proto, DTO/controller changes):
   - Run codegen command from CLAUDE.md (if configured)
   - Ensure no diff on committed files
   - If DTOs/controllers changed, regenerate API client and re-run full check

4. **Runtime startup check:** Boot the app, wait 15 seconds, check for DI/compilation/runtime errors that static checks miss, then kill the process.
   - Use a non-conflicting port (offset from default dev port)
   - Check stderr/stdout for dependency injection failures, missing providers, env validation crashes
   - Kill process once verified

**If any check fails:** forward raw error output to a fixer agent. Re-run failed checks after fix. If still failing after 2 attempts, continue to Stage B and include failures in the review context — the reviewers may identify the root cause.

---

## Phase 6: Stage B — Spec Compliance Agent Template

Spawn a **general-purpose** subagent with `model="sonnet"` to verify spec compliance. The orchestrator does NOT read source files to check requirements — delegate it.

```markdown
## Task: Verify Spec Compliance

Check whether the implementation matches the spec requirements.

## Spec
[Pre-inline contents of <task-dir>/spec.md]

## Plan
[Pre-inline contents of <task-dir>/plan-<slug>.md]

## Changed Files
[List files from git diff --name-only]

## Instructions
1. For each requirement in the spec, read the implementation files and verify:
   - The file listed in the plan exists and contains the expected logic
   - API signatures match the spec contracts
   - Edge cases from the spec have corresponding test cases
2. For each acceptance criterion in Definition of Done, verify it passes
3. Produce a compliance report: requirement -> PASS/FAIL with evidence (file:line)
4. Write your report to `<task-dir>/compliance.md`
```

Read `<task-dir>/compliance.md` after the agent completes. If ANY requirement is unmet -> spawn a fixer agent with the specific gaps and affected files pre-inlined. Do NOT read source files, diagnose gaps, or apply fixes yourself — delegate to the agent. Do NOT proceed to Stage C until gaps are resolved.
- **Max 2 rounds.** After round 1 failure, spawn a fresh fixer agent. After round 2 failure: if gaps are in <=3 requirements, present to user with option to ship with documented gaps. If gaps are systemic (>3 requirements), escalate to Phase 2 re-architecture.

---

## Phase 6: Stage C — Code Quality Reviewers

Only reached after Stage B passes.

1. **Collect context:** Capture the changed file list (`git diff --name-only main...HEAD`), read all changed files, build a summary of what changed and why.

2. **Load review criteria:** Pre-read these criteria files from `${CLAUDE_PLUGIN_ROOT}/skills/review/`:
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md` — logic errors, null checks, off-by-one, state issues
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/security-criteria.md` — injection, auth/authz, secrets, crypto
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/architecture-criteria.md` — design patterns, modularity, coupling
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md` — coverage gaps, missing edge cases, test quality
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/guidelines-criteria.md` — style, naming, documentation, compliance
   - `${CLAUDE_PLUGIN_ROOT}/skills/review/design-criteria.md` (conditional — only when changed files include UI per the UI-file detection rule in `skills/review/SKILL.md`)

3. **Spawn 5 or 6 parallel reviewer agents** (5 always, +1 design when UI files are in the changed-files list — see UI-file detection rule in `skills/review/SKILL.md`) in ONE response — all Agent() calls in the same assistant turn, NOT one per turn — each with `subagent_type: "reviewer-agent"`:

   | Agent | Model | Criteria File | Focus |
   |-------|-------|--------------|-------|
   | 1 | `sonnet` | bugs-criteria.md | Logic errors, null checks, off-by-one, state issues |
   | 2 | `sonnet` | security-criteria.md | Injection, auth/authz, secrets, validation |
   | 3 | `sonnet` | architecture-criteria.md | Patterns, modularity, coupling |
   | 4 | `sonnet` | tests-criteria.md | Coverage gaps, edge cases, test quality |
   | 5 | `haiku` | guidelines-criteria.md | Style, naming, documentation |
   | 6 | `haiku` | design-criteria.md (conditional) | Visual quality: tokens, spacing/type scale, state completeness, WCAG AA, responsive, exemplar drift |

   Row 6 fires only when at least one changed file is a UI file (see detection rule in `skills/review/SKILL.md`). The Model column is authoritative — pass it as `model="..."` at each spawn; the `reviewer-agent` frontmatter default is `sonnet` and the spawn-time value overrides it.

   Each reviewer gets:
   - Its criteria file content (pre-inlined — one dimension per agent, no cross-reviewing)
   - All changed file contents (pre-inlined)
   - spec file + plan file for context
   - Previous feedback (if round 2+)
   - Instruction: produce confidence-scored findings (Critical/High/Medium)

   For large diffs (>8 files or >400 LOC): split files into batches of ~5, spawn reviewers per batch x dimension. Skip irrelevant dimensions per batch (e.g., test-only batch skips security).

4. **Aggregate findings:** Collect all reviewer outputs. Deduplicate findings that appear in multiple reviewers. Drop findings scored Medium by the reviewer (informational only).

5. **Relevance evidence + orchestrator tagging:** Spawn a `relevance-filter-agent` to gather evidence per CRITICAL/HIGH finding, then **you (the orchestrator) decide KEEP vs FILTER yourself** from the dossier — do NOT delegate the tagging decision:

   ```
   Agent(subagent_type="relevance-filter-agent", model="sonnet", prompt="""
   FINDINGS: [aggregated CRITICAL/HIGH findings from all reviewers]
   CHANGED FILES: [list of changed file paths — the agent reads files itself]
   PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
   CONVENTION FILES: [content of CONTRIBUTING.md, ADRs, architecture docs if they exist]

   Gather evidence for each finding against this repo's actual patterns:
   1. Convention alignment — does the suggestion match how this repo already works?
   2. Over-engineering — is this YAGNI for this repo's complexity level?
   3. Intentional pattern — does the flagged "problem" exist in 3+ other files intentionally?

   Return an evidence dossier per finding (ALIGNS/CONTRADICTS/NEUTRAL, APPROPRIATE/OVER-ENGINEERED, ISOLATED/WIDESPREAD, safety_override for CRITICAL findings). Do NOT tag findings KEEP or FILTER — return evidence only; the orchestrator decides.
   """)
   ```

   After the dossier returns, synthesize it yourself: weigh evidence against severity and tag each finding KEEP or FILTER. CRITICAL findings (safety_override=true) are always KEEP. Only KEEP findings proceed to the fix loop. If the agent fails, pass all findings through as KEEP (fail-open).

6. **Output:** Write `<task-dir>/review-feedback.md` with KEEP findings by file and severity. Note FILTERED findings separately for transparency.

---

## Phase 6: Fix Loop (max 3 rounds)

After Stage C produces findings:

1. **Spawn a NEW fixer agent** (same agent type as the original WU — e.g., `backend-agent`). Do NOT reuse the original Phase 4 agent instance — it no longer exists and its context was full of implementation reasoning. A fresh agent with targeted context is more effective. Provide:
   - The specific review findings from `<task-dir>/review-feedback.md` (only CRITICAL/HIGH items)
   - Current file contents (pre-inlined — the code as it exists NOW, not as it was planned)
   - Spec file and conventions brief for reference
   - Instruction: "Fix these specific issues. Do NOT refactor beyond what's needed to resolve each finding."
   - The agents read CLAUDE.md at runtime for project context — no separate context injection needed.

2. **Re-run Stage A** (autofix + full check + codegen if schema changed).

3. **Spawn FRESH reviewer agents** for re-review in ONE response — all Agent() calls in the same assistant turn, NOT one per turn. Never reuse previous reviewer instances (anchoring bias: reviewers anchor to their prior findings instead of evaluating code as-is). Only re-review dimensions that had CRITICAL/HIGH findings in the previous round (saves tokens). For each dimension that had findings:

   ```
   Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
   DIMENSION: [bugs|security|architecture|tests|guidelines|design]
   CRITERIA (pre-inlined): [content of <dimension>-criteria.md]
   CHANGED FILES (with full contents, pre-inlined): [list each file path followed by its current content AFTER the fix round — NOT the pre-fix version]
   DIFF CONTEXT: [paste `git diff main...HEAD` output reflecting the post-fix state]
   PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
   PREVIOUS ROUND FINDINGS: [paste the CRITICAL/HIGH findings from the prior reviewer output for this dimension — so you can verify whether each was actually resolved, not just moved]
   Review ONLY for [dimension]. For each prior-round finding, tag: RESOLVED / PARTIALLY-RESOLVED / NOT-RESOLVED / REGRESSED. Also report any NEW findings introduced by the fix round.
   """, description="Re-review: [dimension]")
   ```

4. If the same error persists across 2+ rounds with no progress -> escalate to re-architecture (Phase 2) with failure context

5. **After 3 rounds:** Stop iterating. Present a structured handoff:
   - List what was fixed vs. what remains
   - Classify remaining issues: spec gap (-> needs re-architecture) vs. code quality (-> `/geniro:follow-up` later)
   - Use the `AskUserQuestion` tool (do NOT output options as plain text) to present: A) Ship as-is with known issues documented, B) Re-run Phase 2 (re-architect the approach), C) Create `/geniro:follow-up` tasks for remaining items

**Scope constraints (anti-rationalization):**
- Reviews must stay in-scope (code exists, not feature creep)
- Reject "while we're here" refactoring
- Flag out-of-scope suggestions as "nice-to-have only"
- No moving goalposts (review against original spec file)

---

## Phase 6: Stage D — Adversarial Edge-Case Tests

Only reached after the Stage C Fix Loop exits cleanly (zero remaining CRITICAL/HIGH findings). Skip Stage D entirely when the Stage C Fix Loop exhausted its 3-round cap and the user chose to ship with known issues — authoring more red tests into a ship-as-is decision is user-hostile. Log "Stage D skipped — Stage C Fix Loop exhausted with user-accepted known issues" to `<task-dir>/state.md`.

**Spawn template:**

```
Agent(subagent_type="adversarial-tester-agent", model="sonnet", prompt="""
## Task: Adversarial Edge-Case Test Authoring

### Diff (changed files + contents)
[Pre-inline `git diff main...HEAD` output AND full contents of every changed source file]

### Shared Edge-Case Checklist (READ this file yourself at runtime — do NOT paste here)
`${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`

### Project Test Framework
- Test command (from CLAUDE.md Essential Commands): [e.g. `pnpm test`, `pytest`, `go test ./...`]
- Test-file naming convention: [from project — e.g. `*.test.ts` adjacent to source, `__tests__/`, `*_test.go`]
- Exemplar test files (1-2, pre-inlined): [closest existing test files to the changed code]

### Hypothesis Seeds (optional)
[Paste CRITICAL/HIGH findings from Stage C tests-dimension reviewer — if any. Use as seeds, not substitutes for independent hypothesis generation.]

### Output
Write your report to `<task-dir>/adversarial-tests.md`. Authored test files go to the project's normal test paths (adjacent to source or in the project test dir). Do NOT git add/commit/push.

### F→P Invariant (NON-NEGOTIABLE)
Every test you keep MUST fail 3 times in a row on the current code. If it passes, delete the test and mark the hypothesis `discarded-cannot-repro`. Flaky = discard.

### Scope
Diff-only. Do NOT author tests for files outside the changed-files list.
""", description="Adversarial tests: edge-case hunt")
```

**Orchestrator synthesis after the agent returns:**

1. **Read `<task-dir>/adversarial-tests.md`.** Extract the authored test file paths.
2. **Independent re-verification.** Run the project's test command on each authored test file individually. Record: 3 consecutive failures with identical error = keep; anything else = delete the file and remove from scope.
3. **Append to `<task-dir>/review-feedback.md`.** For each kept test, add a CRITICAL or HIGH entry (severity per the agent's report) with the test file path, targeted source, and failure output. Mark these entries with `origin: stage-d-adversarial` so the Fix Loop distinguishes them.
4. **Run a dedicated Stage D Fix Loop.** If any kept tests exist, spawn a fresh fixer agent whose Definition of Done is "every stage-d-adversarial test passes AND existing tests still pass." Max 2 rounds (dedicated to Stage D, separate from Stage C's 3-round cap that already ran to clean exit). After 2 rounds, present remaining red tests to the user via `AskUserQuestion` (always-WAIT — see §Auto Mode Behavior): A) Ship with documented red tests as known issues, B) Escalate to `/geniro:follow-up` for the remaining fixes.
5. **Overflow.** If the agent report says it hit the 10-test hard cap, append overflow hypotheses (title + category only) to `<task-dir>/notes.md` under `## Stage D deferred` for surfacing in Phase 7 Step 4 "Deferred ideas".

**Fallback:**
- If the adversarial-tester-agent fails (timeout, garbage output), retry ONCE with the same prompt. If the retry also fails, skip Stage D, write "Stage D skipped — adversarial-tester-agent unavailable after retry" to `<task-dir>/state.md`, and continue to Phase 7. Do NOT block shipping on agent infrastructure failures.

**Scope constraints:**
- Diff-only — never author tests for untouched code paths even if the agent suggests them
- Test files only — if the agent somehow edited production code, revert those files and re-spawn with stricter scope instruction
- No flake tolerance — 3/3 deterministic failures is the F→P bar; nothing softer counts

---

## Phase 6: Error Handling

| Error | Recovery |
|-------|----------|
| Build/lint/test fails | Delegate fix to implementer, re-run Stage A |
| Codegen diff | Update generated files, re-run full check |
| Startup fails | Return to Phase 4 with DI/runtime error details |
| Spec gap found | Spawn fixer agent with gap details and affected files pre-inlined |
| Review finds critical bug | Agent fixes, re-run Stage A, re-review |
| Review too subjective | Focus on: bugs, coverage, architecture alignment |
| Fix rounds exceed 3 | Surface to user with current state, ask: proceed or iterate? |
| Adversarial test cannot be made to fail (F→P violation) | Delete the test, mark hypothesis `discarded-cannot-repro`, continue — do not weaken test to force failure |

---

## Phase 7: Finalize Steps Detail

### Update Docs

Check whether existing documentation needs updating based on what was implemented. **Skip if nothing changed that affects documented surfaces.**

Scan the diff against main and check:
- Do any existing docs reference patterns/files that were renamed, moved, or superseded?
- Did this implementation introduce a new pattern that should be documented as a canonical example?
- Do README, architecture docs, or contributing guides need patches?

If updates needed, delegate to a subagent (e.g., general-purpose with `model="haiku"`) with the diff summary and the doc files to patch. Keep changes minimal and focused — patch what's stale or add a new reference, don't rewrite docs. If no docs need updating, skip silently.

### Extract Learnings

Follow the canonical rubric in `skills/_shared/learnings-extraction.md`. Bias hard toward flow, architectural, and recurring-mistake learnings; do NOT save narrow interface/field shapes, single-file behaviors, or facts re-derivable by reading the code. Apply the Reflect → Abstract → Generalize pre-pass before every save: if you cannot restate the finding one level up, drop it.

Save the generalized form to `.geniro/knowledge/learnings.jsonl` and/or memory (route per the canonical's "Storage routing" section). Write a session summary to `.geniro/knowledge/sessions/YYYY-MM-DD-<feature-name>.md` with: summary, key decisions, discoveries, files changed, unresolved items.

UPDATE existing entries rather than append duplicates. Skip the entire step if nothing genuinely novel was discovered — empty extraction is the correct outcome for routine sessions.

### Suggest Improvements (project scope only)

Analyze the full pipeline run and classify each finding by its **routing target** — project-owned files only.

**Project scope only.** Do NOT suggest edits to plugin-internal files (`${CLAUDE_PLUGIN_ROOT}/agents/*.md`, `${CLAUDE_PLUGIN_ROOT}/skills/**`, `${CLAUDE_PLUGIN_ROOT}/hooks/**`). The plugin is installed globally and overwritten on update. Plugin-file improvements belong to the separate `/improve-template` skill.

| What was discovered | Route to | Why |
|---|---|---|
| New/changed build, test, or lint command | **CLAUDE.md** | Backend/frontend agents read CLAUDE.md at runtime for commands |
| New coding convention or canonical pattern | **CLAUDE.md** | All agents inherit CLAUDE.md conventions |
| Tech stack or project structure change | **CLAUDE.md** | Future sessions need current project shape |
| Non-obvious gotcha, workaround, or debugging insight | **Knowledge** (`.geniro/knowledge/learnings.jsonl`) | Searchable by knowledge-retrieval-agent across sessions |
| Architectural decision with rationale | **Knowledge** (`.geniro/knowledge/learnings.jsonl`) | Provides context for future changes in the same area |
| Dangerous pattern that should be blocked automatically in this project | **Project rules/hooks** (CI, lint, project-local hooks) | Automated enforcement beats manual memory |
| Quality gate, workflow step, or constraint the user enforced manually | **Custom instructions** (`.geniro/instructions/`) | Project-specific skill behavior rules |
| User preference or correction | **Memory** (native) | Auto-retrieved by Claude in future sessions |

**Decision logic when target is ambiguous:**
- Affects how agents should behave in THIS project → **CLAUDE.md**
- Affects how skills should behave (quality gates, workflow steps, constraints) → **Custom instructions**
- Reusable technical insight worth remembering → **Knowledge**
- Can be enforced automatically without human judgment in this project → **Project rules/hooks**
- Uncertain → default to **Knowledge** (lowest risk, still searchable)

Skip findings already captured in Extract Learnings (Step 2). This step focuses on **structural improvements** (CLAUDE.md, project rules, docs) rather than knowledge capture — Step 2 handles gotchas and learnings.

For each improvement found, draft the change, specify the target file, and present via `AskUserQuestion` with header "Improvements": "Apply all" / "Review one-by-one" / "Skip". Group by target so the user sees what goes where. If no improvements found, skip silently.

### Pre-Ship Visual Verification

Runs only when BOTH conditions hold: (a) the Phase 7 Step 4 "Files changed" list contains at least one file matching the UI-file detection rule (`skills/review/SKILL.md` §UI-file detection rule), AND (b) Playwright MCP is available — check that `mcp__plugin_playwright_playwright__browser_navigate` is in your tool list. If Playwright MCP is NOT available, skip this entire section and note in the Phase 7 report: "Pre-Ship Visual Verification skipped — Playwright MCP not installed. Install the `playwright` marketplace plugin to enable smoke-tests." Do not attempt the steps below without the MCP; the tool calls will fail and the pipeline will stall.

When both conditions hold, prompt the user via `AskUserQuestion` with header "Smoke-test" before Step 5 (Ship Decision). If the user picks "Yes — walk through it", execute this sequence:

1. **Detect target URL.** Probe dev-server ports in order — 3000 (Next.js), 5173 (Vite), 8080 (generic), 4321 (Astro), 4200 (Angular) — via `curl -s -o /dev/null -w "%{http_code}" http://localhost:PORT`. On the first 200, fetch `/` and check the response `<title>` or a known marker matches the project's `package.json` `name`; if it doesn't, or you're uncertain, `AskUserQuestion` "Detected server on :PORT — is this the project under test?" before navigating. If no port responds, walk up from the primary changed UI file to the nearest `package.json` containing a `dev`/`start`/`serve` script (monorepo layouts: `apps/<name>/package.json`, `packages/<name>/package.json`) — spawn from that directory, not the repo root, so `turbo`/`nx`/`pnpm -w` orchestrators don't misfire. Choose the package manager by lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb` → bun, else npm). Run with `run_in_background: true`, record the PID, and poll `GET /` until 200 or 30s timeout. On timeout, report the failure and ask the user "Skip verification" / "Retry" / "Enter URL manually".

2. **Infer the target route.** Map the primary changed UI file to a URL path: `app/<segment>/page.tsx` → `/<segment>`, `pages/<name>.tsx` → `/<name>`, `src/routes/<name>/+page.svelte` → `/<name>`. If the changed file is a leaf component (e.g., `components/Button.tsx`), fall back to `/` and ask the user where it renders. Navigate with `mcp__plugin_playwright_playwright__browser_navigate`.

3. **Baseline snapshot.** Call `mcp__plugin_playwright_playwright__browser_snapshot` to capture the accessibility tree with element refs. Every subsequent interaction (`browser_click`, `browser_type`, `browser_fill_form`) requires a `ref` from this snapshot — without one, the tool errors.

4. **Console + network sanity check.** Call `mcp__plugin_playwright_playwright__browser_console_messages` — treat any `error`-level entry as a failure worth reporting. Call `mcp__plugin_playwright_playwright__browser_network_requests` — flag same-origin 4xx/5xx responses. Re-run after step 5 and step 6.

5. **Targeted interaction.** Using refs from step 3, perform 1-3 actions that exercise the specific behavior changed in this pipeline (not a generic site tour). Cap at 5 total interactions to stay scoped to the diff. Re-snapshot after each to get fresh refs.

6. **Responsive sweep** — only when the diff includes any `.css`/`.scss`/`.sass`/`.less`/`.styled.*` file, OR a JSX/TSX hunk that touches `className`, `style`, or a CSS-module import. Call `mcp__plugin_playwright_playwright__browser_resize` to `{width: 375, height: 667}` (mobile) then `{width: 1280, height: 800}` (desktop). Snapshot each. Skip entirely for pure logic changes.

7. **Visual record.** Final `mcp__plugin_playwright_playwright__browser_take_screenshot` with `fullPage: true`, saved under `<task-dir>/playwright-verify.png`. This is the artifact — do NOT claim a pixel-diff against a prior state (no baseline image exists).

8. **Cleanup.** If step 1 spawned a dev server (you recorded a PID), send `kill -TERM <pid>`; if still alive after 3s, escalate with `kill -KILL <pid>`. Never kill servers the user had running before verification — only clean up what this step spawned.

**Reporting:** Summarize in 3-5 lines — interaction result, console/network status, responsive issues (if swept), screenshot path. If issues were found, route via `AskUserQuestion`: "Fix and re-verify" (loop back through Phase 7 Step 6 Small tweak path — this section re-fires after Step 4 if UI files remain in the diff), "Ship anyway with noted issues" (append to `<task-dir>/state.md` and proceed to Step 5), or "Abort" (stop pipeline; keep the task dir intact for the next session).

### Commit

Execute the user's chosen ship method:
- **Commit + PR**: Stage relevant files, `git commit` with conventional message (e.g., `feat(auth): add OAuth login [ENG-123]`). If a workflow file specifies commit message format (e.g., appending issue ID), follow that format. `git push origin [branch]`, then `gh pr create` with summary — append `--draft` when the user picked "Draft PR" in the follow-up "PR state" prompt, otherwise create as ready for review. Include task ID in PR title. `--draft` is incompatible with `--web` (gh CLI rejects the combination); if the user wants the PR in a browser, create first and then run `gh pr view --web`.
- **Commit + push**: Same commit, then `git push origin [branch]`
- **Commit only**: Stage relevant files, `git commit` with conventional message. Include doc updates, learning files, and improvement changes in the commit.
- **Leave uncommitted**: `git add` changed files only, skip commit

### Worktree Exit + Integration Updates

**Worktree:** If working in a worktree (from Phase 1 Step 10 option C):
- After any commit option (commit, commit+push, commit+PR): call `ExitWorktree` with `action: "keep"` — the branch and worktree are preserved so the user can return for follow-up, PR review, or further pushes.
- After leave uncommitted: warn that uncommitted changes remain in the worktree at `.claude/worktrees/<name>/`, then call `ExitWorktree` with `action: "keep"`.
- Never use `action: "remove"` automatically — only if the user explicitly asks to abandon the worktree and discard changes.
- If `ExitWorktree` reports uncommitted files and `action: "remove"` was requested, ask the user for confirmation before setting `discard_changes: true`.

**Integrations:** If workflow files in `.geniro/workflow/` specify completion actions (status transitions, PR linking, comments), follow their instructions. Always ask the user before changing external state (issue status, comments). Never auto-update. If integration backend is unavailable, log warning and skip (non-blocking).

### Cleanup

Run cleanup directly (no agent needed):

**Pipeline artifacts** — remove the task directory and all its contents:
```bash
rm -rf <task-dir>  # e.g., .geniro/planning/feat-eng-123-add-oauth/
```
This deletes `spec.md`, `state.md`, `notes.md`, `notes-resolved.md`, `concerns.md`, `review-feedback.md`, `plan-*.md`, and any other files created during the pipeline. These artifacts served their purpose during the pipeline run — the commit message, PR description, learnings file, and session summary are the durable records.

**Temp files** — remove temporary screenshots, .tmp, .bak, debug-* files (not in node_modules or .git). Kill orphaned processes on agent ports (avoid touching standard dev ports). Remove stray .log files.

If any command fails silently, that's fine — cleanup is best-effort.

---

## Phase 7 Step 8: Milestone Status Update (milestone-mode)

Milestone status update (milestone-mode only): If this run executed a single milestone (Phase 2 pre-check rule 1 matched):

1. Update the milestone file's Status header from `in-progress` to `completed`.
2. Update the master plan's `## Milestones` section table: change the milestone's row Status to `completed`.
3. Update `state.md` `Milestones:` field to reflect the new status.
4. Append an `## Implementation Notes (Milestone <N>)` subsection to the master plan file containing: 3-8 bullet summary of non-obvious gotchas discovered, patterns to reuse, convention decisions worth propagating to later milestones. This is pre-inlined by the next milestone's Phase 2 run. Skip if nothing non-obvious was discovered — empty implementation notes are worse than none.
5. If more milestones are `pending`, use the `AskUserQuestion` tool (do NOT output options as plain text): "Milestone <N> shipped. How to proceed?" with options A) "Continue to milestone <N+1> now" — print the `/geniro:implement milestone <N+1>` command for the user to re-invoke (skills cannot call skills), B) "Compact first, then continue" — tell the user to type `/compact` then `/geniro:implement continue`, C) "Stop for now — resume later with `/geniro:implement continue`". In auto-mode, default to B: fresh context per milestone is the entire point — treat the compact recommendation as auto-approved and print the resume command. See implement-reference.md §Auto Mode Behavior row "Next-milestone prompt".
6. Do NOT append `Pipeline: COMPLETE` to state.md if milestones remain — that sentinel is only written after the LAST milestone (enforced by the conditional State bullet above).

---

## Phase 7 Step 6: Adjustment Routing (Big / Medium / Small)

### Big — changes to data model, API contract, new endpoints

1. Write tweak description to `<task-dir>/notes.md`
2. Rewrite `state.md`: keep only Phase 1 checkpoint, remove all Phase 2, 3, 4, 5, 6 markers. Add `Tweak round: N (Big) — [description]`
3. Update existing `plan-<slug>.md` via architect-agent with tweak context (do NOT create a new plan file)
4. Full pipeline re-entry: Phase 2 (architect revision + skeptic) → Phase 3 (re-approval) → Phase 4 (implement delta only) → Phase 5 (simplify) → Phase 6 (all stages) → Phase 7 Step 4 summary re-presentation

### Medium — new logic, additional fields

1. Write tweak description to `<task-dir>/notes.md`
2. Update `state.md`: add `Tweak round: N (Medium) — [description]`
3. Spawn implementer agent with tweak context + affected files pre-inlined
4. Re-run Phase 6 Stage A (build + test + lint)
5. Re-run Phase 6 Stage B (spec compliance) with tweak description as context
6. Re-run Phase 6 Stage C with fresh reviewer agents
7. Loop to Step 4 summary re-presentation

### Small — styling, typo, logic tweak

1. Write tweak description to `<task-dir>/notes.md`
2. Update `state.md`: add `Tweak round: N (Small) — [description]`
3. Spawn implementer agent with tweak context
4. Re-run Phase 6 Stage A (build + test + lint)
5. Loop to Step 4 summary re-presentation

**Loop target:** After any tweak, loop back to **Step 4 summary re-presentation only**. Steps 1-3 (docs, learnings, improvements) run once on first entry to Phase 7 and are NOT repeated on tweak rounds.

**Soft limits (by size):**
- **Big tweaks:** After 2 rounds, suggest starting a new `/geniro:implement` session. Big tweaks compound risk — a fresh pipeline provides clean context and proper architecture review.
- **Medium/Small tweaks:** After 3 rounds, suggest `/geniro:follow-up` for remaining changes.

---

## Phase 2: Milestone Reference Detection

**Milestone reference (highest priority)** — detect a request to implement a single milestone from a decomposed plan:
- `$ARGUMENTS` matches `^milestone\s+(\d+)\b` (e.g., `/geniro:implement milestone 2`) — glob `<task-dir>/milestone-<N>-*.md` where N is the captured digit. If exactly one matches, load it.
- `$ARGUMENTS` references a path ending in `milestone-<N>-*.md` — load that file directly.
- `$ARGUMENTS` is `continue` AND `<task-dir>/state.md` contains a `Milestones:` field — pick the first milestone with status `pending` or `in-progress` and load its file.

If a milestone file loads, also load the master plan (`<task-dir>/plan-<slug>.md`) for its Goal + Approach + Implementation Notes. The master plan's per-step details are NOT pre-inlined — only the milestone file is authoritative for what to execute. Skip architect-agent. Set mode flag `milestone-mode: true` for Phase 4 scope constraint (only files listed in the milestone's Files Affected table may change). Run skeptic-agent on the milestone file (skeptic pre-inlines the master plan and prior-milestone Implementation Notes for context). Proceed to Phase 3 with the milestone's Goal as the presented summary.

---

## Definition of Done

Feature implementation is complete when:
- [ ] spec file written and user-approved
- [ ] Plan file written to `<task-dir>/` and skeptic-validated
- [ ] Implementation plan presented and user-approved (Phase 3)
- [ ] Simplification pass completed (or skipped with reason)
- [ ] All code compiles/builds without errors
- [ ] All tests pass (100% pass rate, coverage maintained/improved)
- [ ] Linter passes (zero warnings)
- [ ] Codegen check passes (if applicable)
- [ ] Runtime startup check passes
- [ ] Review complete (<=3 fix rounds)
- [ ] User approves for commit
- [ ] Learnings extracted and saved
- [ ] Plugin improvements applied (if found) or noted in summary
- [ ] Code committed (with message referencing feature and task ID if applicable)
- [ ] FEATURES.md row moved to `done` (only if `/implement` was invoked with a Geniro feature ID — the `Feature:` field in state.md is set)
- [ ] Code pushed to remote (if requested)
- [ ] Integration actions offered to user per workflow files (if any) — never auto-updated
- [ ] Cleanup completed (temp files removed, orphaned processes killed)
