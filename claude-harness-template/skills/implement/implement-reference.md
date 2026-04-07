# Implement Skill — Reference Material

This file contains templates, examples, error tables, and detailed procedures referenced by SKILL.md. The orchestrator reads specific sections at the relevant phase — not the entire file at once.

---

## Phase 1: Auto-Detection Table

| What you say | What the skill detects | Behavior |
|---|---|---|
| `/implement add OAuth login` | Plain description | Full discovery with interactive questions |
| `/implement ENG-123` | Linear issue ID (`[A-Z]{2,}-\d+`) | Fetches issue from Linear MCP, uses as context, then asks discovery questions |
| `/implement https://linear.app/team/issue/ENG-123` | Linear URL | Extracts issue ID, fetches from Linear MCP, then asks discovery questions |
| `/implement ENG-123 add OAuth login` | Issue ID + description | Fetches issue, supplements with description, then asks discovery questions |
| `/implement just do it` or `ASAP` or `no questions` | Urgency signals | Auto mode: skip interactive questions, pick recommended defaults |
| `/implement I think we should add OAuth` | Tentative language ("I think", "maybe", "should we") | Assumptions mode: propose plan, ask user to correct what's wrong |

**Detection rules (checked in order):**
1. **Linear URL** — regex: `https://linear\.app/.+/issue/([A-Z]+-\d+)` -> extract issue ID
2. **Issue ID** — regex: `\b[A-Z]{2,}-\d+\b` (e.g., `ENG-123`, `PROJ-42`) -> fetch from Linear
3. **Auto-mode signals** — keywords like "just do it", "ASAP", "no questions", "auto", "quick" -> skip interactive questions, pick recommended defaults for all gray areas
4. **Assumptions-mode signals** — tentative language like "I think", "maybe", "what if", "should we" -> propose plan with assumptions, let user correct
5. **No special signals** — full interactive discovery with `AskUserQuestion`

If Linear MCP is not configured when an issue ID is detected, log a warning and proceed without tracker integration (non-blocking).

**Example discovery questions (interactive mode, batch 3-5). IMPORTANT — include the git workspace question in this same batch, do NOT defer it to a separate prompt:**
- Scope: Backend-only? Frontend? Both? (recommend: match existing split)
- Backwards compat: Support old API during transition? (recommend: yes, deprecation warning)
- Performance: Any constraints or targets? (recommend: <100ms latency for endpoints)
- Testing: Unit/integration/e2e? (recommend: maintain current test coverage)
- Rollout: Gradual rollout or all-at-once? (recommend: feature flag + gradual)
- **Git workspace:** A) New feature branch (recommend for most features), B) Current branch, C) Git worktree (for risky/parallel work — isolates entire implementation in a separate working tree)

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

## Codebase Conventions
[Paste the CONVENTIONS_BRIEF section from spec file — naming patterns, file structure, error handling, import style, test patterns. Include 1-2 exemplar file snippets showing the patterns to follow.]
Match existing patterns exactly. Find the closest existing example and follow it.

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

## Requirements
- Follow project conventions as documented in the Codebase Conventions section above
- Do NOT run git add/commit/push — the orchestrator handles git
- Do NOT modify files outside your WU scope: [list files]
- Do NOT add abstractions, wrappers, or patterns not present in the exemplar files — a separate simplification pass handles code quality
- Report: files changed, **test files created**, what was done, test results, any issues encountered
```

---

## Phase 4: Error Handling

| Error | Recovery |
|-------|----------|
| Agent produces non-compiling code | Forward raw error output to fixer agent — do NOT diagnose or read source files yourself |
| Agent modifies files outside its WU scope | Revert those changes, re-run agent with stricter scope constraint |
| Agent ignores conventions | Re-spawn agent with exemplar files pre-inlined and stricter convention instructions |
| Agent timeout or garbage output | **RETRY:** re-dispatch with enriched context (add error details, relevant files, conventions). If retry fails: **DECOMPOSE** the WU into smaller sub-tasks. If still failing: **PRUNE** — revert WU, mark BLOCKED, continue to next WU |

**Blocked WU handling:** When a WU is marked BLOCKED, commit successful WUs from the wave, defer WUs that depend on the blocked one, continue independent WUs in the next wave. Present all blocked WUs to user after independent work completes.

---

## Phase 5: Simplify Agent Template

Spawn a **general-purpose** subagent with `model: "sonnet"` and the simplify criteria. Sonnet is sufficient for cleanup work that follows explicit criteria — opus-level reasoning is unnecessary here. Pre-read the criteria file and the changed file list, then delegate:

```markdown
## Task: Simplify Changed Files

You are a code simplifier. Review the changed files and make them cleaner, simpler, and more consistent — without changing behavior.

## Criteria
[Pre-inline the contents of `.claude/skills/deep-simplify/simplify-criteria.md` here — read it first, paste it in]

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

Orchestrator runs shell commands directly (build, lint, test — these are validation, not implementation). If checks fail, delegate the **fix** to an implementer agent — do not fix code yourself.

1. **Autofix:** Run lint/format fix commands from CLAUDE.md. Attempt auto-fixable issues first.

2. **Full check:** Run build + lint + test using the backpressure wrapper:
   ```bash
   source .claude/hooks/backpressure.sh
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

Spawn a **general-purpose** subagent with `model: "sonnet"` to verify spec compliance. The orchestrator does NOT read source files to check requirements — delegate it.

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

Read `<task-dir>/compliance.md` after the agent completes. If ANY requirement is unmet -> route back to Phase 4 implementer with specific gaps. Do NOT proceed to Stage C.
- **Max 2 rounds.** After round 1 failure, re-route to implementer. After round 2 failure: if gaps are in <=3 requirements, present to user with option to ship with documented gaps. If gaps are systemic (>3 requirements), escalate to Phase 2 re-architecture.

---

## Phase 6: Stage C — Code Quality Reviewers

Only reached after Stage B passes.

1. **Collect context:** Capture the changed file list (`git diff --name-only main...HEAD`), read all changed files, build a summary of what changed and why.

2. **Load review criteria:** Pre-read these criteria files from `.claude/skills/review/`:
   - `bugs-criteria.md` — logic errors, null checks, off-by-one, state issues
   - `security-criteria.md` — injection, auth/authz, secrets, crypto
   - `architecture-criteria.md` — design patterns, modularity, coupling
   - `tests-criteria.md` — coverage gaps, missing edge cases, test quality
   - `guidelines-criteria.md` — style, naming, documentation, compliance

3. **Spawn 5 parallel reviewer agents** in a single message, each with `subagent_type: "reviewer-agent"`:

   | Agent | Criteria File | Focus |
   |-------|--------------|-------|
   | 1 | bugs-criteria.md | Logic errors, null checks, off-by-one, state issues |
   | 2 | security-criteria.md | Injection, auth/authz, secrets, validation |
   | 3 | architecture-criteria.md | Patterns, modularity, coupling |
   | 4 | tests-criteria.md | Coverage gaps, edge cases, test quality |
   | 5 | guidelines-criteria.md | Style, naming, documentation |

   Each reviewer gets:
   - Its criteria file content (pre-inlined — one dimension per agent, no cross-reviewing)
   - All changed file contents (pre-inlined)
   - spec file + plan file for context
   - Previous feedback (if round 2+)
   - Instruction: produce confidence-scored findings (Critical/High/Medium)

   For large diffs (>8 files or >400 LOC): split files into batches of ~5, spawn reviewers per batch x dimension. Skip irrelevant dimensions per batch (e.g., test-only batch skips security).

4. **Aggregate findings:** Collect all reviewer outputs. Deduplicate findings that appear in multiple reviewers. Drop findings scored Medium by the reviewer (informational only). Pass CRITICAL and HIGH findings through to the fix loop.

5. **Output:** Write `<task-dir>/review-feedback.md` with aggregated findings by file and severity

---

## Phase 6: Fix Loop (max 3 rounds)

After Stage C produces findings:

1. **Spawn a NEW fixer agent** (same agent type as the original WU — e.g., `backend-agent`). Do NOT reuse the original Phase 4 agent instance — it no longer exists and its context was full of implementation reasoning. A fresh agent with targeted context is more effective. Provide:
   - The specific review findings from `<task-dir>/review-feedback.md` (only CRITICAL/HIGH items)
   - Current file contents (pre-inlined — the code as it exists NOW, not as it was planned)
   - Spec file and conventions brief for reference
   - Instruction: "Fix these specific issues. Do NOT refactor beyond what's needed to resolve each finding."

2. **Re-run Stage A** (autofix + full check + codegen if schema changed).

3. **Spawn FRESH reviewer agents** for re-review — never reuse previous reviewer instances (anchoring bias: reviewers anchor to their prior findings instead of evaluating code as-is). Each fresh reviewer gets: updated file contents, its criteria file, and the previous round's findings (so it can verify fixes were applied). Only re-review dimensions that had findings (saves tokens).

4. If the same error persists across 2+ rounds with no progress -> escalate to re-architecture (Phase 2) with failure context

5. **After 3 rounds:** Stop iterating. Present a structured handoff:
   - List what was fixed vs. what remains
   - Classify remaining issues: spec gap (-> needs re-architecture) vs. code quality (-> `/follow-up` later)
   - Use the `AskUserQuestion` tool (do NOT output options as plain text) to present: A) Ship as-is with known issues documented, B) Re-run Phase 2 (re-architect the approach), C) Create `/follow-up` tasks for remaining items

**Scope constraints (anti-rationalization):**
- Reviews must stay in-scope (code exists, not feature creep)
- Reject "while we're here" refactoring
- Flag out-of-scope suggestions as "nice-to-have only"
- No moving goalposts (review against original spec file)

---

## Phase 6: Error Handling

| Error | Recovery |
|-------|----------|
| Build/lint/test fails | Delegate fix to implementer, re-run Stage A |
| Codegen diff | Update generated files, re-run full check |
| Startup fails | Return to Phase 4 with DI/runtime error details |
| Spec gap found | Route back to Phase 4 implementer with specific gaps |
| Review finds critical bug | Agent fixes, re-run Stage A, re-review |
| Review too subjective | Focus on: bugs, coverage, architecture alignment |
| Fix rounds exceed 3 | Surface to user with current state, ask: proceed or iterate? |

---

## Phase 7: Finalize Steps Detail

### Update Docs

Check whether existing documentation needs updating based on what was implemented. **Skip if nothing changed that affects documented surfaces.**

Scan the diff against main and check:
- Do any existing docs reference patterns/files that were renamed, moved, or superseded?
- Did this implementation introduce a new pattern that should be documented as a canonical example?
- Do README, architecture docs, or contributing guides need patches?

If updates needed, delegate to a subagent (e.g., general-purpose with `model: "sonnet"`) with the diff summary and the doc files to patch. Keep changes minimal and focused — patch what's stale or add a new reference, don't rewrite docs. If no docs need updating, skip silently.

### Extract Learnings

Scan the conversation for events worth remembering:

| Signal | What to save |
|---|---|
| **User corrections** — "don't do X", "do Y instead" | The correction + why + how to apply next time |
| **Discovered problems** — bugs, gotchas, unexpected behaviors | The problem + root cause + resolution |
| **Workarounds** — documented pattern failed, alternative used | What failed, what worked instead, why |
| **CI failure resolutions** requiring non-obvious fixes | The error + non-obvious root cause + fix |
| **Reviewer CRITICAL/HIGH findings** revealing a recurring pattern | The anti-pattern + why it's dangerous |
| **Architectural deviations** from spec that worked better | What changed + why + outcome |
| **Cross-module dependency gotchas** hard to discover | The dependency + why it's surprising |

Save findings to `.claude/.artifacts/knowledge/learnings.jsonl` and/or to memory. Write a session summary to `.claude/.artifacts/knowledge/sessions/YYYY-MM-DD-<feature-name>.md` with: summary, key decisions, discoveries, files changed, unresolved items.

Before writing, check if an existing memory/learning covers this topic — UPDATE rather than duplicate. Skip if nothing genuinely novel was discovered.

### Suggest Improvements

Analyze the full pipeline run and identify improvements to the harness itself:

| Category | What to look for | Target files |
|---|---|---|
| **Rules gaps** | Agent made a mistake a rule would have prevented? | `.claude/rules/*.md` |
| **Rules conflicts** | A rule contradicted what actually works? | `.claude/rules/*.md` |
| **Skill gaps** | Pipeline hit a scenario it wasn't designed for? | `.claude/skills/*/SKILL.md` |
| **Agent prompt gaps** | An agent consistently missed something? | `.claude/agents/*.md` |
| **Stale documentation** | CLAUDE.md or rules reference patterns that no longer exist? | Any doc file |

For each improvement found, draft the change and include it in the commit. If no improvements found, skip silently. For ambiguous improvements where the right fix is unclear, mention them in the Ship summary as suggestions for the user to consider later — do NOT block the pipeline with a separate approval gate.

### Commit

Execute the user's chosen ship method:
- **Commit + PR**: Stage relevant files, `git commit` with conventional message (include issue ID if detected: e.g., `feat(auth): add OAuth login [ENG-123]`), `git push origin [branch]`, then `gh pr create` with summary. Include task ID in PR title.
- **Commit + push**: Same commit, then `git push origin [branch]`
- **Commit only**: Stage relevant files, `git commit` with conventional message. Include doc updates, learning files, and improvement changes in the commit.
- **Leave uncommitted**: `git add` changed files only, skip commit

### Worktree Exit + Linear Update

**Worktree:** If working in a worktree (from Phase 1 Step 9 option C) and user chose a commit option (A/B/C), call `ExitWorktree` to merge changes back and clean up. If user chose to leave uncommitted, warn that changes remain in the worktree directory.

**Linear:** If Linear issue was detected in Phase 1:
- After **Commit + PR**: move issue to **"In Review"**, add comment with PR link
- After **Commit** or **Commit + push**: add comment summarizing what was implemented
- After **Leave uncommitted**: leave status as "In Progress"
- If Linear MCP is unavailable, log a warning and skip (non-blocking)

### Cleanup

Run cleanup directly (no agent needed):

**Pipeline artifacts** — remove the task directory and all its contents:
```bash
rm -rf <task-dir>  # e.g., .claude/.artifacts/planning/feat-eng-123-add-oauth/
```
This deletes `spec.md`, `state.md`, `notes.md`, `notes-resolved.md`, `concerns.md`, `review-feedback.md`, `plan-*.md`, and any other files created during the pipeline. These artifacts served their purpose during the pipeline run — the commit message, PR description, learnings file, and session summary are the durable records.

**Temp files** — remove temporary screenshots, .tmp, .bak, debug-* files (not in node_modules or .git). Kill orphaned processes on agent ports (avoid touching standard dev ports). Remove stray .log files.

If any command fails silently, that's fine — cleanup is best-effort.

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
- [ ] Harness improvements applied (if found) or noted in summary
- [ ] Code committed (with message referencing feature and task ID if applicable)
- [ ] Code pushed to remote (if requested)
- [ ] Linear issue status updated (if detected): In Progress -> In Review / Done
- [ ] Cleanup completed (temp files removed, orphaned processes killed)
