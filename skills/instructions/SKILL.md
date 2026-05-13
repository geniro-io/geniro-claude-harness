---
name: geniro:instructions
description: "Use when adding skill-behavior rules at Geniro skill phase boundaries OR cross-cutting code-style rules loaded at every code-writing and review step. Create, list, edit, validate, delete. Skip for per-file-pattern rules — use .claude/rules/."
context: main
model: sonnet
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[what you want — e.g. 'add a rule to run tests', 'show instructions', 'delete review rules']"
---

# Instructions: Custom Instruction Management

Manage `.geniro/instructions/` files — the home for **skill-behavior rules**: extra workflow steps, quality gates, and hard constraints applied at skill phase boundaries (e.g. "always run codegen after editing DTOs", "max PR size 500 lines"). These files load **when the matching skill runs**, not on every file edit.

Code rules split three ways depending on **when** they should fire:

- **`.geniro/instructions/code-style.md`** — cross-cutting code-style rules that apply to **all code writing AND all code review** done by Geniro pipeline skills (loaded at code-writing/review phases regardless of file pattern). Use this for naming conventions, code structure preferences, and idioms that should hold project-wide.
- **`.claude/rules/<scope>.md` with `paths:` YAML frontmatter** — file-pattern-scoped rules (Anthropic-native, auto-loads when Claude reads or writes a file matching the glob — fires even outside Geniro pipelines). Use this when the rule only applies to specific file types or directories.
- **CLAUDE.md** — reserved for always-loaded essentials (commands, project structure, compaction-surviving gates) and should NOT carry code rules.

These are complementary: `code-style.md` fires "when a Geniro skill writes or reviews code"; `.claude/rules/` fires "when any tool touches a matching file". A project can use both.

## Supported Skills

`global.md` loads in **every** Geniro skill that does real user work — its **Rules** and **Constraints** apply project-wide (lifecycle skills like `setup`, `instructions`, `cleanup`, `update`, `vendor` are excluded). Per-skill instruction files (`<skill>.md`) load only in the seven phase-bearing pipeline skills below, where "Additional Steps" entries map to named phases. `code-style.md` is a **cross-cutting** scope: it loads in every code-writing AND code-review skill (not paired with one skill), capturing style/naming/convention rules that should apply at every code-writing and review step.

| Skill | Loads `global.md` | Per-skill file | Key phases for "Additional Steps" |
|-------|---|---------------|-----------------------------------|
| **implement** | ✓ | `implement.md` | After PHASE 1 (Discover), After PHASE 4 (Implement), After PHASE 6 (Review & Validate), Before PHASE 7 (Ship & Finalize) |
| **decompose** | ✓ | `decompose.md` | After Phase 1 (Discover Context), After Phase 2 (Generate Master Plan + Milestone List), After Phase 4 (Validate) |
| **review** | ✓ | `review.md` | After Phase 1 (Collect Context), After Phase 4 (Judge Pass), After Phase 5 (Learn) |
| **debug** | ✓ | `debug.md` | After step 1 (Observe), After step 5 (Fix), After step 6 (Verify) |
| **follow-up** | ✓ | `follow-up.md` | After Phase 2 (Implement), After Phase 5 (Review), Before Phase 6 (Ship) |
| **refactor** | ✓ | `refactor.md` | After Phase 2 (Analyze & Plan), After Phase 4 (Execute), After Phase 5 (Review Results) |
| **deep-simplify** | ✓ | `deep-simplify.md` | After Phase 3 (Aggregate), After Phase 4 (Fix), Before Phase 5 (Verify) |
| **investigate** | ✓ | — | Rules/Constraints only (no per-skill file; phase-boundary "Additional Steps" not supported) |
| **onboard** | ✓ | — | Rules/Constraints only |
| **learnings** | ✓ | — | Rules/Constraints only |
| **features** | ✓ | — | Rules/Constraints only |
| **actions** | ✓ | — | Rules/Constraints only |

**Cross-cutting (loaded by multiple skills):**

| Skill | Loads `global.md` | Per-skill file | Key phases for "Additional Steps" |
|-------|---|---------------|-----------------------------------|
| **code-style** | — | `code-style.md` | Loaded by `implement` (Phase 4), `follow-up` (Phase 2), `refactor` (Phase 4), `review` (Phase 2), `deep-simplify` (Phase 2), and pre-inlined into reviewer-agent prompts for the guidelines/conventions/design/architecture dimensions. |
| **review-extra** | — | `review-extra/<slug>.md` (directory-style — one file per custom reviewer) | Loaded by `/geniro:review` Phase 2, `/geniro:implement` Phase 6 Stage C, `/geniro:follow-up` Phase 5, and `/geniro:refactor` Phase 5 via the shared helper at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md`. Each file becomes an additional reviewer-agent dimension that runs alongside the built-in 7-9 reviewers. |

*`code-style` and `review-extra` are the cross-skill scopes. `code-style` captures style/naming/convention rules that apply at every code-writing and review step. `review-extra` is the only **directory-style** scope (the other 10 scopes are single files at `.geniro/instructions/<scope>.md`); each file under `.geniro/instructions/review-extra/` declares one custom code-review dimension with its own slug, description, optional model/paths/severity-default, and a "what to flag / what NOT to flag" criteria body.*

## File Structure

Every instruction file uses this format:

```markdown
# Custom Instructions

## Rules
- Clear, single-line constraints (e.g., "Always update docs when modifying public APIs")

## Additional Steps
### After implementation
<!-- Steps to run after code changes -->

### Before shipping
<!-- Steps to run before committing -->

## Constraints
- Hard limits (e.g., "Maximum PR size: 500 lines changed")
```

## File Structure: review-extra

The `review-extra` scope is **directory-style** — instead of a single `.geniro/instructions/review-extra.md`, there is a directory `.geniro/instructions/review-extra/` containing one file per custom reviewer at `.geniro/instructions/review-extra/<slug>.md`. Each file becomes its own code-review dimension that runs alongside the built-in reviewers (bugs, security, architecture, tests, optimizations, guidelines, conventions, plus design/pr-metadata when applicable).

Each file uses the following frontmatter + body shape (the body section mirrors the built-in criteria files at `${CLAUDE_PLUGIN_ROOT}/skills/review/*-criteria.md` — same "what to flag / what NOT to flag" convention):

```yaml
---
slug: sql-bindings              # REQUIRED; matches filename (without `.md`); must NOT collide with built-in dimensions
description: All SQL queries use parameterized bindings, never string concatenation
model: sonnet                   # OPTIONAL; one of haiku|sonnet|opus; default sonnet
paths:                          # OPTIONAL; list of globs; reviewer fires only if at least one changed file matches; absent = always fires
  - "**/*.sql"
  - "**/dao/*.{ts,py}"
severity-default: HIGH          # OPTIONAL; default MEDIUM; per-finding severity ultimately set by the reviewer-agent itself
---

# Criteria

What to flag:
- String concatenation that builds a SQL string with a runtime variable (e.g., `` `SELECT * FROM users WHERE id = ${userId}` ``)
- Template literals containing SQL keywords (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `WHERE`) where any `${...}` interpolation is a non-constant identifier
- ORM `.raw()` / `.query()` calls passing concatenated strings instead of bind parameters
- `f"..."` / `format()` building SQL in Python DAO code

What to NOT flag:
- Static SQL with no variables at all (e.g., `db.query("SELECT * FROM migrations")`)
- Concatenation of pure constants (e.g., a table-name constant defined at module scope)
- Test fixtures that build SQL strings for assertion comparison (not for execution)
- Schema-migration files that intentionally build CREATE/ALTER statements from a column list
```

**Frontmatter field reference:**
- `slug` (required) — lowercase ASCII letters/digits/hyphens, regex `^[a-z][a-z0-9-]*$`. Filename without `.md` must equal this value. Must NOT match any built-in dimension name (case-insensitive): `bugs`, `security`, `architecture`, `tests`, `optimizations`, `guidelines`, `conventions`, `design`, `pr-metadata`.
- `description` (required) — one-line summary of what this reviewer checks; surfaced in the review report and used by the reviewer-agent prompt.
- `model` (optional) — `haiku` / `sonnet` / `opus`; default `sonnet`. Use `haiku` for narrow pattern matchers, `opus` for deep architectural concerns.
- `paths` (optional) — list of globs. Reviewer fires only when at least one changed file in the diff matches. Absent = always fires.
- `severity-default` (optional) — `CRITICAL` / `HIGH` / `MEDIUM` / `LOW`; default `MEDIUM`. The reviewer-agent may override per-finding; this is the starting point for scoring.

The body MUST be a `# Criteria` section with "What to flag:" and "What to NOT flag:" lists. Keep it focused — 30-80 lines is the sweet spot (see "Custom Reviewer Authoring (review-extra)" under "Writing Effective Instructions" below).

## Intent Detection

Parse `$ARGUMENTS` to determine the user's intent. NEVER output questions as plain text — always use the `AskUserQuestion` tool.

### Action Detection

Detect the action from natural language using these aliases:

| Intent | Aliases | Maps to |
|--------|---------|---------|
| List | show, view, list, display, what instructions, current | `list` |
| Create | add, new, create, set up, start | `create` |
| Edit | change, modify, update, edit, tweak, adjust | `edit` |
| Validate | check, verify, validate, lint | `validate` |
| Delete | remove, delete, drop, clear | `delete` |

If no arguments are provided, default to `list`.

### Scope Detection

Extract scope(s) from the arguments:

- Explicit scope names: "global", "review", "implement", "decompose", "debug", "follow-up", "refactor", "deep-simplify", "code-style", "review-extra"
- Contextual references: "add a rule to review" → scope=review, action=edit; "create debug instructions" → scope=debug, action=create; "code-style", "style", "code style", "naming conventions", "coding style" → scope=code-style; "custom reviewer", "review dimension", "extra review", "custom review", "review layer" → scope=review-extra
- Explicit slug form: `review-extra <slug>` (e.g., `review-extra sql-bindings`) → scope=review-extra, slug=`<slug>` (free-form token)
- Multi-scope indicators: "all", "every", "global and review", "implement and decompose" → collect all mentioned scopes into a list
- "all" or "every" → expand to all valid scopes that have existing files (for edit/validate/delete) or all valid scopes (for create); for `review-extra`, "all" expands to every file in `.geniro/instructions/review-extra/`

Valid scopes: `global`, `implement`, `decompose`, `review`, `debug`, `follow-up`, `refactor`, `deep-simplify`, `code-style`, `review-extra`.

### Ambiguity Resolution

If the action is unclear, use the `AskUserQuestion` tool:
- **Question:** "What would you like to do with your instruction files?"
- **Options:**
  - label: "List" — description: "Show all instruction files and their contents"
  - label: "Create" — description: "Create a new instruction file"
  - label: "Edit" — description: "Modify an existing instruction file"
  - label: "Validate" — description: "Check instruction files for issues"
  - label: "Delete" — description: "Remove an instruction file"

If the scope is unclear (and not multi-scope), use the `AskUserQuestion` tool. The full scope list (10 items) exceeds the 4-option AskUserQuestion cap, so chain follow-up questions per `feedback_askuserquestion_extension.md` (do NOT split or drop options):

**First question — pick a category:**
- **Question:** "Which instruction file?"
- **Options:**
  - label: "global" — description: "Rules that apply to all work skills"
  - label: "code-style" — description: "Cross-cutting code-style rules (loaded at code-writing & review by all pipeline skills)"
  - label: "review-extra (custom reviewers)" — description: "Directory-style scope — one file per custom code-review dimension (e.g., sql-bindings, accessibility-aria)"
  - label: "A specific pipeline skill" — description: "Pick one of: implement, decompose, review, debug, follow-up, refactor, deep-simplify"

If the user picks "A specific pipeline skill", chain a second `AskUserQuestion`:

**Second question — pick the skill (chained):**
- **Question:** "Which pipeline skill?"
- **Options (batch 1):**
  - label: "review" — description: "Customize code review behavior"
  - label: "implement" — description: "Customize implementation workflow"
  - label: "decompose" — description: "Customize decomposition workflow"
  - label: "Other" — description: "debug / follow-up / refactor / deep-simplify"

If the user picks "Other", chain a third `AskUserQuestion`:

**Third question (chained):**
- **Question:** "Which one?"
- **Options:**
  - label: "debug" — description: "Customize debugging workflow"
  - label: "follow-up" — description: "Customize follow-up workflow"
  - label: "refactor" — description: "Customize refactoring workflow"
  - label: "deep-simplify" — description: "Customize parallel-review behavior"

### Scope Validation

Before proceeding, verify the resolved scope(s) are valid. If any resolved scope is NOT in the valid scopes list (`global`, `implement`, `decompose`, `review`, `debug`, `follow-up`, `refactor`, `deep-simplify`, `code-style`, `review-extra`), use the `AskUserQuestion` tool to ask the user to pick from valid scopes instead. Do NOT create, edit, or delete files for invalid scopes.

For `review-extra`, the slug-bearing variants of `create` / `edit` / `delete` ALSO require a `<slug>` argument. If the slug is missing, resolve it as follows:
- `create review-extra` with no slug → ask the user for a slug via `AskUserQuestion` free-form (no options — the user enters text via the "Other" path, matching the existing slug-style flow in `/geniro:actions`).
- `edit review-extra` / `delete review-extra` with no slug AND only one file exists in `.geniro/instructions/review-extra/` → default to that file.
- `edit review-extra` / `delete review-extra` with no slug AND multiple files exist → ask via `AskUserQuestion` which slug they mean. If more than 4 files exist, chain follow-up questions per `feedback_askuserquestion_extension.md` (do NOT split or drop options). The hard cap of 10 files (see "Count caps" under "Command: create — review-extra variant") guarantees the chain terminates in at most 3 questions.
- `validate review-extra` ignores any slug — validate ALWAYS processes the whole `.geniro/instructions/review-extra/` directory (per-file validation has no use case beyond the directory pass; a missing-slug or extra-slug invocation produces the same output). Print a one-line notice `Validating the entire review-extra/ directory (slug arguments are ignored for validate).` when a slug was passed so the user understands the input was redundant.

After resolving intent and scope(s), if multiple scopes were detected, proceed to **Batch Mode**. Otherwise, proceed to the resolved command section below.

## Batch Mode

When multiple scopes are detected (e.g., "edit global and review", "add rules to all"), process each scope sequentially through the same command flow.

### Multi-Scope Confirmation

If the user said "all" or the scope list is ambiguous, the 10-scope list exceeds the 4-option `AskUserQuestion` cap; chain follow-up questions per `feedback_askuserquestion_extension.md` (do NOT split or drop options).

**Q1 — pick categories** (`AskUserQuestion` with `multiSelect: true`). Question: "Which categories of instruction files do you want to target?" Options:
- label: "global" — description: "Rules for all work skills"
- label: "code-style" — description: "Cross-cutting code-style rules — naming, structure, idioms"
- label: "review-extra (custom reviewers)" — description: "Directory-style scope — every file under `.geniro/instructions/review-extra/`"
- label: "Specific pipeline skills" — description: "Pick one or more of: implement, decompose, review, debug, follow-up, refactor, deep-simplify"

If "Specific pipeline skills" is picked, chain **Q2** (`AskUserQuestion`, `multiSelect: true`; for edit/validate/delete, filter to pipeline skills that have existing files; for create, show all). Question: "Which pipeline skills?" Options (batch 1):
- label: "implement" — description: "Implementation workflow"
- label: "decompose" — description: "Decomposition workflow"
- label: "review" — description: "Code review"
- label: "follow-up" — description: "Follow-up workflow"

If more pipeline skills are needed beyond batch 1, chain **Q3** (`AskUserQuestion`, `multiSelect: true`; same existing-files filter). Question: "Which other pipeline skills?" Options (batch 2):
- label: "debug" — description: "Debugging workflow"
- label: "refactor" — description: "Refactoring workflow"
- label: "deep-simplify" — description: "Parallel-review workflow"

### Execution

For each scope in the list, run the resolved command's full flow (create, edit, validate, or delete). When the command involves user input (e.g., create interview, edit changes), use the `AskUserQuestion` tool for each scope separately so the user can provide scope-specific input.

### Batch Summary

After processing all scopes, show a summary:

```
## Batch Complete

| Scope | Action | Result |
|-------|--------|--------|
| global | edit | Updated — added 2 rules |
| review | edit | Updated — added 1 constraint |
| implement | edit | Skipped — no changes requested |
```

## Command: list

### Step 1: Scan directory

```bash
ls -la .geniro/instructions/ 2>/dev/null
ls -la .geniro/instructions/review-extra/ 2>/dev/null
```

### Step 2: Present results

If `.geniro/instructions/` does not exist or is empty:

```
No instruction files found.

Run `/geniro:instructions create global` to create your first instruction file,
or `/geniro:instructions create review` for skill-specific instructions.
```

If files exist, show a table:

```
## Instruction Files

| File | Scope | Affects Skills | Sections |
|------|-------|----------------|----------|
| global.md | All work skills | implement, decompose, review, debug, follow-up, refactor, deep-simplify, investigate, onboard, learnings, features, actions | Rules (3), Steps (1), Constraints (2) |
| review.md | review only | review | Rules (5), Steps (0), Constraints (1) |
| review-extra/ | review-extra directory | review skills (review, implement Stage C, follow-up, refactor) | N custom reviewers |
```

Count the number of entries in each section (Rules = bullet points, Steps = non-empty `###` subsections, Constraints = bullet points). For the `review-extra/` summary row, `N` is the number of `.md` files in `.geniro/instructions/review-extra/`.

### Step 3: List review-extra files (when applicable)

When the scope being listed is `review-extra` (explicit) OR the main table includes the `review-extra/` summary row AND files exist there, also print a separate table listing every file in `.geniro/instructions/review-extra/`:

```
## Custom Reviewers (review-extra)

| Slug | Description | Model | Paths | Severity-default |
|------|-------------|-------|-------|------------------|
| sql-bindings | All SQL queries use parameterized bindings, never string concatenation | sonnet | **/*.sql, **/dao/*.{ts,py} | HIGH |
| accessibility-aria | All interactive elements have proper ARIA labels | sonnet | (always fires) | MEDIUM |
```

Read each file's YAML frontmatter to populate columns. Use `(always fires)` when `paths:` is absent, `(default sonnet)` / `(default MEDIUM)` when fields are absent.

When the scope is `review-extra` AND the directory does not exist OR is empty, print:

```
No custom reviewers found.

Run `/geniro:instructions create review-extra <slug>` to add one
(e.g., `/geniro:instructions create review-extra sql-bindings`).
```

## Writing Effective Instructions

When generating instruction content (in `create` or `edit`), follow these principles. These come
from analysis of 14 production AI coding frameworks and real-world plugin usage.

### Rule Writing

- **Use strong, unambiguous language** — "Always", "Never", "Must" not "Consider", "Try to", "Should"
- **One rule = one constraint** — don't combine multiple ideas in a single bullet
- **Be specific, not vague** — "Run `pnpm test` before committing" not "Make sure tests pass"
- **Include the command or path** — rules referencing tools, scripts, or files should name them exactly
- **Focus on what the AI can't infer** — don't repeat things obvious from the codebase (like "use TypeScript" in a TS project). Focus on conventions, team decisions, and non-obvious requirements

### Additional Steps Writing

- **Use exact phase names** from the Supported Skills table — the validate command checks these
- **Keep steps actionable** — each step should describe a concrete action, not a vague reminder
- **Limit to 2-3 steps per phase** — too many steps slow down the workflow and dilute attention
- **Best insertion points:** "Before shipping" (quality gates), "After implementation" (post-checks), "After review" (follow-up actions)

### Constraint Writing

- **Quantify where possible** — "Maximum 400 lines changed per PR" not "Keep PRs small"
- **State the consequence** — "Database migrations must be backwards-compatible — breaking migrations block deploy"
- **Constraints are hard limits** — skills treat these as non-negotiable. Use Rules for soft guidance

### Custom Reviewer Authoring (review-extra)

The directory-style `review-extra` scope has its own authoring guidance (criteria-body length, what-to-flag shape, paths/model/severity selection, count cap sweet-spot) in the companion file: `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-review-extra.md`. Read it before creating or editing any `.geniro/instructions/review-extra/<slug>.md` file.

### File-size guidance — consider splitting at 300 lines

Instruction files load fully into the consuming skill's context every run. As they grow, two failure modes emerge: (1) the consuming skill burns budget on rules it never fires, and (2) the file becomes unscannable so the user can't audit it. **Soft guidance: when an instruction file passes ~300 lines, consider splitting.**

Two ways to split:
- **By scope**: if `global.md` covers rules that only apply during certain skills, move them into the matching `<skill>.md` files. Example: a "always run codegen after editing DTOs" rule moves out of `global.md` into `implement.md` (and `follow-up.md` if relevant).
- **By topic**: if a single skill's instruction file mixes concerns (e.g., review covers severity thresholds AND security-specific checks AND PR-comment formatting), keep one as the main file and link to companion files for the others. Cap the main file at ~150-200 lines so the rules a skill sees on every run stay focused.

This is guidance, not enforcement. A 350-line file that's well-organized and all-load-bearing is fine. The trigger is "the file became hard to scan or has dead rules" — not the line count itself. Skills that author skills (e.g., `/improve-template create-skill`) should also follow this guidance.

### What goes here vs. `.claude/rules/` vs. CLAUDE.md

Three homes, three triggers:

- **`.geniro/instructions/<skill>.md`** — **skill-scoped** rules that fire when the matching pipeline skill (`implement` / `decompose` / `review` / `debug` / `follow-up` / `refactor` / `deep-simplify`) starts a run. Use it for: extra workflow steps, quality gates, hard constraints the user enforces manually at skill phase boundaries.
- **`.geniro/instructions/code-style.md`** — **cross-cutting code-style** rules that fire whenever a Geniro pipeline skill writes OR reviews code (regardless of which skill or which file pattern). Use it for: naming conventions, code structure preferences, idioms (early-return vs nested-if, pure functions vs classes), import order. Loaded by `implement`, `follow-up`, `refactor`, `review`, `deep-simplify`, and pre-inlined into reviewer-agent prompts for the guidelines/conventions/design/architecture dimensions.
- **`.claude/rules/<scope>.md` with `paths:` YAML frontmatter** — **file-pattern-scoped** rules (Anthropic-native, auto-loads when Claude reads or writes a file matching the glob — fires even outside Geniro pipelines). Use it when the rule only applies to specific file types or directories.
- **CLAUDE.md** — reserved for always-loaded essentials only: commands, project structure, compaction-surviving global gates. Piling rules into CLAUDE.md dilutes compliance for every existing rule.

`code-style.md` and `.claude/rules/` are complementary: code-style fires "when a Geniro skill writes or reviews code"; `.claude/rules/` fires "when any tool touches a matching file". A project can use both.

**What NOT to put in `.geniro/instructions/<skill>.md` or `code-style.md`:**

- **Per-file-pattern code rules** (e.g. "all `*.tsx` files must use named exports") — use `.claude/rules/<scope>.md` with `paths:` glob instead (file-scoped, fires per-file, not per-skill)
- **Tech stack info** — detected automatically by setup, lives in CLAUDE.md
- **Build / test / lint / dev commands** — every-turn essentials, belong in CLAUDE.md
- **Project structure facts** — every-turn essentials, belong in CLAUDE.md
- **Compaction-surviving global gates** (e.g. "never commit without approval") — must stay in CLAUDE.md
- **Temporary rules** — use conversation context instead
- **Rules for skills that don't load instructions** — onboard, investigate, features, etc.

**What NOT to put specifically in `code-style.md`:**

- **Per-file-pattern rules** (those belong in `.claude/rules/` so they fire per-file, not per-skill)
- **One-skill-only workflow steps** (those belong in the matching `<skill>.md`, not in cross-cutting code-style)

## Command: create

### Step 1: Check for existing file

```bash
cat .geniro/instructions/{{scope}}.md 2>/dev/null
```

If the file already exists, report: "`.geniro/instructions/{{scope}}.md` already exists. Use `/geniro:instructions edit {{scope}}` to modify it." and stop.

### Step 2: Ensure directory exists

```bash
mkdir -p .geniro/instructions
```

### Step 3: Gather context

Before interviewing the user, scan the project for context that will inform better instructions:

1. Read `CLAUDE.md` to understand the project's tech stack, commands, and conventions
2. Check `package.json`, `Makefile`, or equivalent for available scripts/commands
3. Check for existing linting/testing/CI configuration

This context helps you suggest relevant, project-specific rules instead of generic ones.

### Step 4: Interview the user

NEVER output questions as plain text — always use the `AskUserQuestion` tool.

Use the `AskUserQuestion` tool to present what you found and ask targeted questions:
- **Question:** "What kind of rules do you want to add? Describe your project conventions, quality gates, or workflow requirements."
- **Options:**
  - label: "Documentation rules" — description: "Require docs updates, changelog entries"
  - label: "Quality gates" — description: "Test coverage, PR size limits, linting"
  - label: "Workflow steps" — description: "Extra checks before shipping, after review"
  - label: "Let me describe my own rules" — description: "Free-form input for custom rules"

Based on the response, ask 1-2 follow-up questions to gather specific rules. Keep it concise — don't over-interview.

Use the `AskUserQuestion` tool for each follow-up, tailored to the scope:

**global** — Question: "What rules should ALL skills follow?"
- Options:
  - label: "Commit conventions" — description: "Commit message format, branch naming"
  - label: "Testing requirements" — description: "Required test coverage, test commands"
  - label: "Documentation standards" — description: "When to update docs, required sections"
  - label: "Custom" — description: "Describe your own rules"

**review** — Question: "What should reviewers focus on?"
- Options:
  - label: "Severity thresholds" — description: "Minimum severity to report, blocking vs advisory"
  - label: "File patterns" — description: "Files or patterns to always flag"
  - label: "Security checks" — description: "Security-specific review requirements"
  - label: "Custom" — description: "Describe your own rules"

**implement** — Question: "What implementation checks do you need?"
- Options:
  - label: "Pre-implementation" — description: "Checks before writing code"
  - label: "Architecture constraints" — description: "Module boundaries, dependency rules"
  - label: "Post-implementation" — description: "Validation steps after code changes"
  - label: "Custom" — description: "Describe your own rules"

**decompose** — Question: "What must plans always include?"
- Options:
  - label: "Scope constraints" — description: "Maximum complexity, required breakdown"
  - label: "Required sections" — description: "Risk analysis, rollback plan, dependencies"
  - label: "Validation criteria" — description: "What makes a plan complete"
  - label: "Custom" — description: "Describe your own rules"

**debug** — Question: "What debugging conventions apply?"
- Options:
  - label: "Log requirements" — description: "Required log formats, debug output"
  - label: "Priority systems" — description: "Systems to always check first"
  - label: "Verification steps" — description: "How to confirm a fix works"
  - label: "Custom" — description: "Describe your own rules"

**follow-up** — Question: "What follow-up workflow rules apply?"
- Options:
  - label: "Scope limits" — description: "Maximum change size, escalation triggers"
  - label: "Review requirements" — description: "Required checks before shipping"
  - label: "Custom" — description: "Describe your own rules"

**refactor** — Question: "What refactoring boundaries apply?"
- Options:
  - label: "Protected areas" — description: "Files or modules that must not change"
  - label: "Test requirements" — description: "Required test coverage before/after"
  - label: "Scope limits" — description: "Maximum files changed, complexity limits"
  - label: "Custom" — description: "Describe your own rules"

**deep-simplify** — Question: "What parallel-review rules apply?"
- Options:
  - label: "Severity gates" — description: "Which severity levels to fix vs report"
  - label: "Scope limits" — description: "Maximum fixes per run, file exclusions"
  - label: "Verification rules" — description: "Required validation before keeping fixes"
  - label: "Custom" — description: "Describe your own rules"

**code-style** — Question: "What code-style conventions apply to ALL code in this project?"
- Options:
  - label: "Naming conventions" — description: "Variable / function / file / class naming patterns"
  - label: "Code structure" — description: "Module organization, file size limits, import order"
  - label: "Common idioms" — description: "Preferred patterns (early-return vs nested-if, pure vs class, etc.)"
  - label: "Custom" — description: "Describe your own rules"

### Step 5: Generate the file

Read the template from `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/instructions-template.md` for structure reference.

Write the instruction file to `.geniro/instructions/{{scope}}.md`. Apply the writing principles
from "Writing Effective Instructions" above:
- Convert vague user input into strong, specific rules (e.g., user says "make sure we test" → "Always include tests for new public functions. Run `npm test` to verify before shipping")
- Place workflow steps under the correct phase headers from the Supported Skills table
- Quantify constraints where the user gave qualitative input
- Leave sections empty (with comment placeholders) if the user didn't specify content for them
- Do NOT pad with generic rules — only include what the user actually wants

### Step 6: Confirm

Show the created file content and report:
```
Created `.geniro/instructions/{{scope}}.md`

This file will be loaded by {{affected skills list}} at the start of each run.
These rules take effect the next time you run `/geniro:{{scope}}` (or any affected skill for global.md).
Edit with `/geniro:instructions edit {{scope}}`, or run `/geniro:instructions validate` to check for issues.
```

## Command: create — review-extra variant

When the resolved scope is `review-extra`, follow the slug-bearing 11-step flow in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-review-extra.md` instead of the singleton-file `create` flow above. The output is a single file at `.geniro/instructions/review-extra/<slug>.md` declaring one custom reviewer. The companion file covers: slug resolution, slug validation (regex, built-in collision, no-existing-file), count-cap warning (soft 5→6) and hard-refusal (10→11), directory creation, description/model/paths/severity-default interview prompts (all via `AskUserQuestion`), criteria-body collection, file write, and confirmation message.

## Command: edit

### Step 1: Read current file

For singleton scopes (`global`, `code-style`, or any of the 7 pipeline skills):

```bash
cat .geniro/instructions/{{scope}}.md
```

For `review-extra`, require a slug argument; resolve missing-slug cases per "Scope Validation" above:

```bash
cat .geniro/instructions/review-extra/{{slug}}.md
```

If the file doesn't exist: "File not found. Use `/geniro:instructions create {{scope}}` first." (or `create review-extra {{slug}}` for the directory-style variant) and stop.

### Step 2: Show current content and ask what to change

Display the current file content. The change options differ by scope:

**Singleton scopes** — use `AskUserQuestion`:
- **Question:** "What would you like to change?"
- **Options:**
  - label: "Add new rules" — description: "Add rule entries to the Rules section"
  - label: "Add workflow steps" — description: "Add steps under Additional Steps"
  - label: "Add or modify constraints" — description: "Add or change hard limits"
  - label: "Remove specific entries" — description: "Delete rules, steps, or constraints"

**review-extra** — use `AskUserQuestion`:
- **Question:** "Which part of the custom reviewer would you like to change?"
- **Options:**
  - label: "description" — description: "One-line summary in frontmatter"
  - label: "model" — description: "Override haiku/sonnet/opus (or remove to default to sonnet)"
  - label: "paths" — description: "Globs that scope when this reviewer fires (or remove to always fire)"
  - label: "Other" — description: "severity-default, criteria body, or multiple fields"

On "Other", chain `AskUserQuestion`:
- **Question:** "Which other part?"
- **Options:**
  - label: "severity-default" — description: "CRITICAL/HIGH/MEDIUM/LOW (or remove to default MEDIUM)"
  - label: "criteria body" — description: "The `# Criteria` section — what to flag / what NOT to flag"
  - label: "multiple fields" — description: "Walk through each field interactively"

### Step 3: Apply changes

Based on user input, edit the file using the Edit tool. Preserve existing content — only add, modify, or remove what the user requested. For `review-extra`, never silently rewrite the `slug:` field (it must match the filename — changing it requires a delete-then-create).

### Step 4: Re-validate (review-extra only)

After editing a `review-extra` file, re-run the 7 validation rules from "Command: validate" Step 2 against the edited file. If any rule fails, report the issue and ask whether to revert via `AskUserQuestion`:
- **Question:** "The edit produced an invalid `review-extra` file: {{issue}}. What now?"
- **Options:**
  - label: "Revert" — description: "Restore the previous file content"
  - label: "Keep and fix later" — description: "Save anyway; re-run `/geniro:instructions validate` after manual fix"

### Step 5: Show updated file

Display the final content and print: "Updated `.geniro/instructions/{{scope}}.md`. The new rules take effect the next time you run `/geniro:{{scope}}` (or any affected skill for global.md)." For `review-extra`, the path is `.geniro/instructions/review-extra/{{slug}}.md` and the reviewer takes effect on the next `/geniro:review` (or implement/follow-up/refactor review phase) run.

## Command: validate

### Step 1: Scan all instruction files

```bash
ls .geniro/instructions/*.md 2>/dev/null
ls .geniro/instructions/review-extra/*.md 2>/dev/null
```

If none found: "No instruction files to validate." and stop.

### Step 2: Validate each file

For each singleton file (everything under `.geniro/instructions/` except the `review-extra/` directory), check:

1. **Structure** — file contains `## Rules`, `## Additional Steps`, and `## Constraints` sections
2. **Phase names** — any `### <phase>` headers under "Additional Steps" match the valid phase names from the Supported Skills table above. **Special case for `code-style.md`:** since it's loaded by N skills (not one) at runtime, its `## Additional Steps` section accepts ONLY two phase headers: `### Before code writing` and `### On code review`. Any other phase header in `code-style.md` is a warning.
3. **Non-empty content** — at least one section has actual content (not just comment placeholders)
4. **Scope validity** — filename (without `.md`) matches a valid singleton scope: `global`, `implement`, `decompose`, `review`, `debug`, `follow-up`, `refactor`, `deep-simplify`, `code-style`

**review-extra files** — extra checks (run against every file in `.geniro/instructions/review-extra/`):

1. **Filename / slug agreement** — the filename (without `.md`) MUST equal the `slug:` frontmatter value. Mismatch is an error (the loader keys by slug; mismatch makes the reviewer silently undiscoverable).
2. **No built-in collision** — `slug` MUST NOT match any built-in dimension name (case-insensitive): `bugs`, `security`, `architecture`, `tests`, `optimizations`, `guidelines`, `conventions`, `design`, `pr-metadata`. Collision is an error (the loader would shadow or be shadowed by the built-in reviewer).
3. **Slug regex** — `slug` MUST match `^[a-z][a-z0-9-]*$` (lowercase ASCII letters/digits/hyphens, starts with a letter). Mismatch is an error (other characters break the file-naming convention and downstream prompt assembly).
4. **Model field** — if `model:` is present, it MUST be one of `{haiku, sonnet, opus}`. Other values are an error (only those three models are routed by the reviewer-agent infrastructure).
5. **Severity-default field** — if `severity-default:` is present, it MUST be one of `{CRITICAL, HIGH, MEDIUM, LOW}`. Other values are an error (severity scoring keys against this enum).
6. **Paths field** — if `paths:` is present, it MUST be a YAML list with no empty strings and every entry a string. Malformed entries are an error (the glob matcher rejects them at load time).
7. **YAML frontmatter validity** — the frontmatter block must be well-formed YAML between two `---` fences. Malformed YAML is an error (loader-fatal).
8. **Description present and non-empty** — the `description:` field MUST be present and non-empty. The loader drops files with a missing or empty description; surfacing this here keeps validate and load-time agreement (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Step 4 rule 5).
9. **Body content** — the body section (everything after the closing `---` of the frontmatter) MUST contain at least 5 non-blank lines. Files with shorter bodies are dropped by the loader as a sentinel for "criteria not yet written" (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Step 4 rule 9).

**review-extra count caps** — also check the directory-level count:

- **Soft warning** — if more than 6 files exist in `.geniro/instructions/review-extra/`, emit a warning row: `⚠ Count {{N}} exceeds the 4-6 sweet-spot — consider consolidating overlapping reviewers.` (Matches the loader's `count > 6` trigger.)
- **Hard error** — if more than 10 files exist, emit an error row: `✗ Count {{N}} exceeds hard cap of 10 — the loader will refuse to load all reviewers. Delete files with `/geniro:instructions delete review-extra <slug>`.`

### Step 3: Report results

```
## Validation Results

| File | Status | Issues |
|------|--------|--------|
| global.md | ✓ Valid | — |
| review.md | ⚠ Warning | Unknown phase "After testing" — valid phases: After Phase 1, After Phase 4, After Phase 5 |
| frontend.md | ✗ Invalid | Unknown scope "frontend" — not a supported skill name |
| review-extra/sql-bindings.md | ✓ Valid | — |
| review-extra/bugs.md | ✗ Invalid | slug "bugs" collides with built-in dimension — pick a different slug |
| review-extra/SqlBindings.md | ✗ Invalid | filename "SqlBindings" does not equal slug "sql-bindings"; rename file or update slug |
| review-extra/ (directory) | ⚠ Warning | Count 7 exceeds soft cap of 5 — Pattern 1 sweet-spot is 4-6 dimensions |
```

For warnings and errors, suggest the fix.

## Command: delete

For `review-extra`, require a slug argument; resolve missing-slug cases per "Scope Validation" above. The target path is `.geniro/instructions/review-extra/{{slug}}.md` rather than `.geniro/instructions/{{scope}}.md`.

### Step 1: Confirm deletion

Use the `AskUserQuestion` tool:
- **Question:** "Are you sure you want to delete `.geniro/instructions/{{scope}}.md`? This cannot be undone (unless the file is committed to git)." (For `review-extra`, the path shown is `.geniro/instructions/review-extra/{{slug}}.md` and the question wording is "Are you sure you want to delete the custom reviewer `{{slug}}`?")
- **Options:**
  - label: "Delete the file" — description: "Permanently remove this instruction file"
  - label: "Cancel" — description: "Keep the file unchanged"

### Step 2: Execute

If confirmed (singleton scopes):
```bash
rm -f .geniro/instructions/{{scope}}.md
```

If confirmed (review-extra):
```bash
rm -f .geniro/instructions/review-extra/{{slug}}.md
```

Report: "Deleted `.geniro/instructions/{{scope}}.md`. The {{affected skills}} will no longer load these instructions." (For `review-extra`: "Deleted `.geniro/instructions/review-extra/{{slug}}.md`. The `{{slug}}` reviewer will no longer run during code review.")

If the `review-extra` directory is now empty:
```bash
rmdir .geniro/instructions/review-extra/ 2>/dev/null
```

If the top-level `.geniro/instructions/` directory is now empty:
```bash
rmdir .geniro/instructions/ 2>/dev/null
```

## Definition of Done

- [ ] Intent detected from freeform arguments
- [ ] Scope(s) resolved — single or batch
- [ ] File operations completed successfully
- [ ] User confirmed before any destructive operation (delete)
- [ ] Validation checked structure, phase names, and scope validity
- [ ] All user interactions used `AskUserQuestion` tool — no plain-text questions
- [ ] review-extra files validated against slug uniqueness, built-in collision, model/severity-default value sets, paths syntax, and count caps
