# Plan Criteria

Guidelines for generating implementation plans. Pre-inlined into architect-agent and skeptic-agent prompts by `/geniro:implement` (Phase 2) and `/geniro:decompose`. This is the canonical schema for plan files saved to `.geniro/planning/`.

## Plan File Naming

Every plan gets a unique, descriptive filename based on the task:

```
.geniro/planning/<task-dir>/plan-<slug>.md
```

Where `<task-dir>` is the branch-name subdirectory (e.g., `feat-eng-123-add-oauth/`). This colocates the plan with the spec, state, and notes files for the same task. When no branch exists yet, write to `.geniro/planning/plan-<slug>.md` (flat) — `/geniro:implement` will move it into the task directory when a branch is created.

**Slug rules:**
- Derive from the task description: lowercase, hyphens, max 40 chars
- Include a short timestamp prefix for uniqueness: `MMDD-<slug>`
- Examples:
  - "Add OAuth login" → `plan-0405-add-oauth-login.md`
  - "ENG-123 fix pagination" → `plan-0405-eng-123-fix-pagination.md`
  - "Refactor user service" → `plan-0405-refactor-user-service.md`

Never overwrite an existing plan file. If the slug already exists, append `-v2`, `-v3`, etc.

## Plan Structure

The plan must follow this exact structure. Every section is mandatory unless marked optional.

```markdown
# Plan: <descriptive title>

> Generated: <date> | Source: <"architect-agent" or "user-provided"> | Status: <draft | approved | in-progress | completed>

## Goal
One sentence: what we're building and why.

## Approach
2-3 sentences: high-level strategy, key architectural decision, and why this approach over alternatives.
Include a brief mention of alternatives considered and why they were rejected.

## Steps

Ordered by dependency. Each step is a discrete, independently verifiable unit of work.

### Step 1: <ACTION VERB> <short description>
- **Action:** CREATE | EDIT | DELETE | RUN
- **Files:**
  - `path/to/file.ts` (create) — what this file contains and its role
  - `path/to/other.ts` (edit) — what changes: which functions/sections, and why
- **Details:** 1-3 sentences: what exactly to implement. Key logic, data flow, edge cases to handle. Reference specific functions/methods by name when editing existing files.
- **Depends on:** none | Step N
- **Verify:** concrete verification — e.g., "run `npm test -- auth.test.ts`", "`GET /api/settings` returns 200", "file exports `SettingsService` class"
- **Rollback:** what to do if this step fails — e.g., `git checkout -- src/services/auth.ts src/routes/auth.ts`, "delete `src/models/settings.ts`", "run down migration `npx prisma migrate reset --skip-seed`"

### Step 2: ...
[repeat for each step]

## Files Affected

| File | Action | Step | Purpose |
|------|--------|------|---------|
| `src/services/auth.ts` | create | 1 | Authentication service with JWT validation |
| `src/routes/auth.ts` | create | 2 | Auth API routes: login, logout, refresh |
| `src/routes/index.ts` | edit | 3 | Register auth routes in router (hotspot) |
| `tests/auth.test.ts` | create | 4 | Unit + integration tests for auth service |

## Key Decisions
- **<Decision topic>**: <what was chosen> — <why, with trade-off acknowledged>
- **<Decision topic>**: <what was chosen> — <why>

## User Decisions (from Discovery)
[Only present when plan is generated from /geniro:implement pipeline]
- <Question asked>: <user's answer — verbatim>

## Test Scenarios
| Scenario | Type | Input/Setup | Expected Result |
|----------|------|-------------|-----------------|
| Happy path: user logs in | integration | valid credentials | returns JWT + 200 |
| Invalid password | unit | wrong password | returns 401, no token |
| Expired token refresh | unit | expired JWT | returns 401 if refresh token also expired |

## Risks & Assumptions
- **<Risk/assumption>** — <mitigation or what happens if wrong>

## Execution Strategy
- **Parallelism:** which steps can run in parallel (wave grouping), which are sequential. Target 2-4 agents per wave — beyond 4, coordination overhead eats gains.
- **Estimated scope:** N files created, M files modified, ~LOC estimate
- **Hotspot files:** files touched by multiple steps (routing tables, config, barrel exports) — edited last by orchestrator, never delegated to parallel agents
```

## Risk Assessment in Plan

The plan's Risks & Assumptions section should assess task complexity using these dimensions — not just file count:

- **Reversibility:** Are all changes reversible via git, or are there stateful side effects (migrations, API contracts consumed by external clients, external service calls)?
- **Cross-boundary scope:** How many architectural layers does the change cross (DB, service, API, UI)?
- **Pattern availability:** Does the codebase have an existing exemplar to follow, or is this greenfield?
- **Edit scatter:** Are changes concentrated or distributed across many distinct locations?
- **Blast radius:** How many downstream consumers depend on the code being changed? (hotspot files, public APIs, shared types)

These dimensions predict implementation difficulty far better than file count. A 2-file migration + API contract change carries more risk than a 10-file rename.

---

## Detail Level Guidelines

The plan must be **decision-complete** — an implementer agent can execute it without making architectural choices.

| Too Vague | Right Level | Too Detailed (wastes tokens) |
|-----------|-------------|------------------------------|
| "Update the API" | "Edit `src/api/handler.ts` — add input validation in `processRequest()` before the DB call, return 400 on failure" | "On line 47, add `if (!isValid(req.body)) { return res.status(400)...`" |
| "Add tests" | "Create `tests/auth.test.ts` — test login happy path, invalid credentials, and token expiry using existing test patterns from `tests/user.test.ts`" | Full test code in the plan |
| "Modify the model" | "Edit `src/models/user.ts` — add `settings: UserSettings` relation field + create `src/models/settings.ts` with fields: theme, notifications, language" | Complete model class with decorators and all imports |

**Rules:**
- Name every file that will be created, edited, or deleted — no vague "update the API"
- State the action and rationale per file — not the code itself (code belongs in execution)
- Reference specific functions/methods when editing existing files
- 5-15 steps for most features; more than 15 means the feature should be split
- Each step should be completable by a single agent in one pass (1-5 files)
- Include verification criteria for every step — "how do we know it's done?"
- Include rollback instructions for every step — "how do we undo it if it fails?" (usually `git checkout -- <files>` for edits, `delete <file>` for creates)
- Steps must be ordered by dependency — no forward references

## Granularity by File Size

Match plan precision to file complexity:

- **Small files (<100 lines):** plan at file level — "modify file X to add Y"
- **Medium files (100-500 lines):** plan at function level — "modify `createUser()` in file X to add parameter Z"
- **Large files (500+ lines):** plan at section level — "add method `validateSettings()` to `UserService` class after `getSettings()`, update `updateUser()` to call it"

## Plan Quality Checklist

Before the plan is presented to the user, verify:

- [ ] Every file path is exact (no "something like..." or "in the services folder")
- [ ] Every step has a concrete Verify field (not "check it works")
- [ ] Every step has a Rollback field (how to undo if it fails)
- [ ] Dependencies between steps are explicit — no circular or missing deps
- [ ] Files Affected table matches the steps (no files mentioned in steps but missing from table, or vice versa)
- [ ] No implementation decisions left to the executor ("decide the best approach" = plan failure)
- [ ] Test scenarios cover at least: 1 happy path, 2 edge/error cases
- [ ] Hotspot files (routing, config, barrel exports) are identified and assigned to last step or orchestrator
- [ ] Scope matches what was asked — no scope creep, no missing requirements
- [ ] Estimated scope is realistic (LOC, file count)

## Validation Standard

Adapted from Codex's "decision-complete" and GSD's 8-dimension validation. The skeptic-agent validates dimensions 1-8 for every plan. Dimensions 9-10 apply only when the plan has a `## Milestones` section (produced by `/geniro:decompose`).

1. **Requirement coverage** — every user requirement appears as a step or is covered by a step
2. **Task atomicity** — each step is independently verifiable and scoped to 1-5 files
3. **Dependency ordering** — steps are sequenced correctly, no forward references
4. **File scope** — all needed files listed in the table, no critical files missed
5. **Verification commands** — each step has a concrete Verify field and a Rollback field
6. **Context compliance** — plan follows project conventions (naming, patterns, structure)
7. **Gap detection** — nothing silently dropped or assumed "obvious"
8. **Scope sanity** — plan doesn't exceed or fall short of what was asked
9. **Milestone coverage** (decomposed plans only) — every requirement from the master plan's Goal and every acceptance criterion from the spec must be covered by at least one milestone's Acceptance Criteria. No silent drops between milestones. BLOCKER when a requirement has zero milestone coverage.
10. **Milestone dependency ordering** (decomposed plans only) — `Upstream Dependencies` across milestone files must form a DAG with no forward references. If milestone 3 references "the API created in milestone 5", that is a forward reference and a BLOCKER. Same-wave milestones (no cross-dependency) must NOT share a primary file in their Files Affected tables.

**Mirage detection (mandatory):** For every file path, function name, and package the plan references, the validator must grep/glob the codebase to confirm it actually exists. Report any "mirages" — references to things that don't exist. This catches hallucinated APIs, nonexistent files, and dropped requirements before implementation begins. In decomposed plans, a file that does not exist yet because an upstream milestone creates it is NOT a mirage — check the upstream milestone's Files Affected table before reporting. Still a mirage if no milestone creates it.
