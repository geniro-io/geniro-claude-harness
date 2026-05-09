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

*`code-style` is the only cross-skill scope; it captures style/naming/convention rules that apply at every code-writing and review step regardless of which skill ran.*

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

- Explicit scope names: "global", "review", "implement", "decompose", "debug", "follow-up", "refactor", "deep-simplify", "code-style"
- Contextual references: "add a rule to review" → scope=review, action=edit; "create debug instructions" → scope=debug, action=create; "code-style", "style", "code style", "naming conventions", "coding style" → scope=code-style
- Multi-scope indicators: "all", "every", "global and review", "implement and decompose" → collect all mentioned scopes into a list
- "all" or "every" → expand to all valid scopes that have existing files (for edit/validate/delete) or all valid scopes (for create)

Valid scopes: `global`, `implement`, `decompose`, `review`, `debug`, `follow-up`, `refactor`, `deep-simplify`, `code-style`.

### Ambiguity Resolution

If the action is unclear, use the `AskUserQuestion` tool:
- **Question:** "What would you like to do with your instruction files?"
- **Options:**
  - label: "List" — description: "Show all instruction files and their contents"
  - label: "Create" — description: "Create a new instruction file"
  - label: "Edit" — description: "Modify an existing instruction file"
  - label: "Validate" — description: "Check instruction files for issues"
  - label: "Delete" — description: "Remove an instruction file"

If the scope is unclear (and not multi-scope), use the `AskUserQuestion` tool. The full scope list (9 items) exceeds the 4-option AskUserQuestion cap, so chain follow-up questions per `feedback_askuserquestion_extension.md` (do NOT split or drop options):

**First question — pick a category:**
- **Question:** "Which instruction file?"
- **Options:**
  - label: "global" — description: "Rules that apply to all work skills"
  - label: "code-style" — description: "Cross-cutting code-style rules (loaded at code-writing & review by all pipeline skills)"
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

Before proceeding, verify the resolved scope(s) are valid. If any resolved scope is NOT in the valid scopes list (`global`, `implement`, `decompose`, `review`, `debug`, `follow-up`, `refactor`, `deep-simplify`, `code-style`), use the `AskUserQuestion` tool to ask the user to pick from valid scopes instead. Do NOT create, edit, or delete files for invalid scopes.

After resolving intent and scope(s), if multiple scopes were detected, proceed to **Batch Mode**. Otherwise, proceed to the resolved command section below.

## Batch Mode

When multiple scopes are detected (e.g., "edit global and review", "add rules to all"), process each scope sequentially through the same command flow.

### Multi-Scope Confirmation

If the user said "all" or the scope list is ambiguous, the 9-scope list exceeds the 4-option `AskUserQuestion` cap; chain follow-up questions per `feedback_askuserquestion_extension.md` (do NOT split or drop options).

**Q1 — pick categories** (`AskUserQuestion` with `multiSelect: true`). Question: "Which categories of instruction files do you want to target?" Options:
- label: "global" — description: "Rules for all work skills"
- label: "code-style" — description: "Cross-cutting code-style rules — naming, structure, idioms"
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
```

Count the number of entries in each section (Rules = bullet points, Steps = non-empty `###` subsections, Constraints = bullet points).

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

## Command: edit

### Step 1: Read current file

```bash
cat .geniro/instructions/{{scope}}.md
```

If the file doesn't exist: "File not found. Use `/geniro:instructions create {{scope}}` first." and stop.

### Step 2: Show current content and ask what to change

Display the current file content. Use the `AskUserQuestion` tool:
- **Question:** "What would you like to change?"
- **Options:**
  - label: "Add new rules" — description: "Add rule entries to the Rules section"
  - label: "Add workflow steps" — description: "Add steps under Additional Steps"
  - label: "Add or modify constraints" — description: "Add or change hard limits"
  - label: "Remove specific entries" — description: "Delete rules, steps, or constraints"

### Step 3: Apply changes

Based on user input, edit the file using the Edit tool. Preserve existing content — only add, modify, or remove what the user requested.

### Step 4: Show updated file

Display the final content and print: "Updated `.geniro/instructions/{{scope}}.md`. The new rules take effect the next time you run `/geniro:{{scope}}` (or any affected skill for global.md)."

## Command: validate

### Step 1: Scan all instruction files

```bash
ls .geniro/instructions/*.md 2>/dev/null
```

If none found: "No instruction files to validate." and stop.

### Step 2: Validate each file

For each file, check:

1. **Structure** — file contains `## Rules`, `## Additional Steps`, and `## Constraints` sections
2. **Phase names** — any `### <phase>` headers under "Additional Steps" match the valid phase names from the Supported Skills table above. **Special case for `code-style.md`:** since it's loaded by N skills (not one) at runtime, its `## Additional Steps` section accepts ONLY two phase headers: `### Before code writing` and `### On code review`. Any other phase header in `code-style.md` is a warning.
3. **Non-empty content** — at least one section has actual content (not just comment placeholders)
4. **Scope validity** — filename (without `.md`) matches a valid scope: `global`, `implement`, `decompose`, `review`, `debug`, `follow-up`, `refactor`, `deep-simplify`, `code-style`

### Step 3: Report results

```
## Validation Results

| File | Status | Issues |
|------|--------|--------|
| global.md | ✓ Valid | — |
| review.md | ⚠ Warning | Unknown phase "After testing" — valid phases: After Phase 1, After Phase 4, After Phase 5 |
| frontend.md | ✗ Invalid | Unknown scope "frontend" — not a supported skill name |
```

For warnings and errors, suggest the fix.

## Command: delete

### Step 1: Confirm deletion

Use the `AskUserQuestion` tool:
- **Question:** "Are you sure you want to delete `.geniro/instructions/{{scope}}.md`? This cannot be undone (unless the file is committed to git)."
- **Options:**
  - label: "Delete the file" — description: "Permanently remove this instruction file"
  - label: "Cancel" — description: "Keep the file unchanged"

### Step 2: Execute

If confirmed:
```bash
rm -f .geniro/instructions/{{scope}}.md
```

Report: "Deleted `.geniro/instructions/{{scope}}.md`. The {{affected skills}} will no longer load these instructions."

If the directory is now empty:
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
