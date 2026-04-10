---
name: geniro:instructions
description: "Manage custom instruction files in .geniro/instructions/. Create, list, edit, validate, and delete project-specific rules that customize how skills behave."
context: main
model: haiku
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[command: list|create|edit|validate|delete] [optional: scope — global or skill name]"
---

# Instructions: Custom Instruction Management

Manage `.geniro/instructions/` files that customize how core skills behave. These files contain
project-specific rules, additional workflow steps, and hard constraints applied at skill runtime.

## Supported Skills

Six skills load custom instructions at startup:

| Skill | Per-skill file | Key phases for "Additional Steps" |
|-------|---------------|-----------------------------------|
| **implement** | `implement.md` | After PHASE 1 (Discover), After PHASE 4 (Implement), After PHASE 6 (Review & Validate), Before PHASE 7 (Ship & Finalize) |
| **plan** | `plan.md` | After Phase 1 (Discover Context), After Phase 2 (Generate Plan), After Phase 3 (Validate Plan) |
| **review** | `review.md` | After Phase 1 (Collect Context), After Phase 4 (Judge Pass), After Phase 5 (Learn) |
| **debug** | `debug.md` | After step 1 (Observe), After step 5 (Fix), After step 6 (Verify) |
| **follow-up** | `follow-up.md` | After Phase 2 (Implement), After Phase 5 (Review), Before Phase 6 (Ship) |
| **refactor** | `refactor.md` | After Phase 2 (Analyze & Plan), After Phase 4 (Execute), After Phase 5 (Review Results) |

`global.md` applies to **all six** skills above.

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

## Core Commands

| Command | Usage | Purpose |
|---------|-------|---------|
| **list** | `/geniro:instructions list` | Show all instruction files, their status, and which skills they affect |
| **create** | `/geniro:instructions create [scope]` | Create a new instruction file (global or per-skill) |
| **edit** | `/geniro:instructions edit [scope]` | Edit an existing instruction file with guided prompts |
| **validate** | `/geniro:instructions validate` | Check all instruction files for structure and phase name validity |
| **delete** | `/geniro:instructions delete [scope]` | Remove an instruction file (with confirmation) |

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
| global.md | All skills | implement, plan, review, debug, follow-up, refactor | Rules (3), Steps (1), Constraints (2) |
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

### What NOT to put in instructions

- Code patterns already in CLAUDE.md (duplication causes drift)
- Tech stack info (detected automatically by setup)
- Temporary rules (use conversation context instead)
- Rules for skills that don't load instructions (onboard, investigate, features, etc.)

## Command: create

### Step 1: Determine scope

If no scope argument provided, ask:

Use the `AskUserQuestion` tool:
- **Question:** "Which instruction file do you want to create?"
- **Options:**
  - "global — rules that apply to all 6 skills (Recommended)"
  - "review — customize code review behavior"
  - "implement — customize implementation workflow"
  - "plan — customize planning workflow"

If scope is provided as argument (e.g., `create review`), use it directly.

Valid scopes: `global`, `implement`, `plan`, `review`, `debug`, `follow-up`, `refactor`.

### Step 2: Check for existing file

```bash
cat .geniro/instructions/{{scope}}.md 2>/dev/null
```

If the file already exists, report: "`.geniro/instructions/{{scope}}.md` already exists. Use `/geniro:instructions edit {{scope}}` to modify it." and stop.

### Step 3: Ensure directory exists

```bash
mkdir -p .geniro/instructions
```

### Step 4: Gather context

Before interviewing the user, scan the project for context that will inform better instructions:

1. Read `CLAUDE.md` to understand the project's tech stack, commands, and conventions
2. Check `package.json`, `Makefile`, or equivalent for available scripts/commands
3. Check for existing linting/testing/CI configuration

This context helps you suggest relevant, project-specific rules instead of generic ones.

### Step 5: Interview the user

Present what you found and ask targeted questions. Use `AskUserQuestion`:
- **Question:** "What kind of rules do you want to add? Describe your project conventions, quality gates, or workflow requirements."
- **Options:**
  - "Documentation rules — require docs updates, changelog entries"
  - "Quality gates — test coverage, PR size limits, linting"
  - "Workflow steps — extra checks before shipping, after review"
  - "Let me describe my own rules"

Based on the response, ask 1-2 follow-up questions to gather specific rules. Keep it concise — don't over-interview.

**Per-scope guidance** — tailor follow-up questions to the scope:
- **global**: "What rules should ALL skills follow? (e.g., documentation, testing, commit conventions)"
- **review**: "What should reviewers always check? What severity thresholds matter? Any file patterns to always flag?"
- **implement**: "Any pre/post implementation checks? Architecture constraints? Required validation steps?"
- **plan**: "What must plans always include? Constraints on scope or complexity?"
- **debug**: "Any debugging conventions? Required log formats? Systems to always check first?"
- **refactor**: "Any refactoring boundaries? Files/modules that must not change? Required test coverage?"

### Step 6: Generate the file

Read the template from `${CLAUDE_SKILL_DIR}/../setup/workflow-templates/instructions-template.md` for structure reference.

Write the instruction file to `.geniro/instructions/{{scope}}.md`. Apply the writing principles
from "Writing Effective Instructions" above:
- Convert vague user input into strong, specific rules (e.g., user says "make sure we test" → "Always include tests for new public functions. Run `npm test` to verify before shipping")
- Place workflow steps under the correct phase headers from the Supported Skills table
- Quantify constraints where the user gave qualitative input
- Leave sections empty (with comment placeholders) if the user didn't specify content for them
- Do NOT pad with generic rules — only include what the user actually wants

### Step 7: Confirm

Show the created file content and report:
```
Created `.geniro/instructions/{{scope}}.md`

This file will be loaded by {{affected skills list}} at the start of each run.
Edit it anytime, or run `/geniro:instructions validate` to check for issues.
```

## Command: edit

### Step 1: Determine scope

If no scope argument, list existing files and ask which one to edit.

### Step 2: Read current file

```bash
cat .geniro/instructions/{{scope}}.md
```

If the file doesn't exist: "File not found. Use `/geniro:instructions create {{scope}}` first." and stop.

### Step 3: Show current content and ask what to change

Display the current file content. Use `AskUserQuestion`:
- **Question:** "What would you like to change?"
- **Options:**
  - "Add new rules"
  - "Add workflow steps"
  - "Add or modify constraints"
  - "Remove specific entries"

### Step 4: Apply changes

Based on user input, edit the file using the Edit tool. Preserve existing content — only add, modify, or remove what the user requested.

### Step 5: Show updated file

Display the final content and confirm: "Updated `.geniro/instructions/{{scope}}.md`."

## Command: validate

### Step 1: Scan all instruction files

```bash
ls .geniro/instructions/*.md 2>/dev/null
```

If none found: "No instruction files to validate." and stop.

### Step 2: Validate each file

For each file, check:

1. **Structure** — file contains `## Rules`, `## Additional Steps`, and `## Constraints` sections
2. **Phase names** — any `### <phase>` headers under "Additional Steps" match the valid phase names from the Supported Skills table above
3. **Non-empty content** — at least one section has actual content (not just comment placeholders)
4. **Scope validity** — filename (without `.md`) matches a valid scope: `global`, `implement`, `plan`, `review`, `debug`, `follow-up`, `refactor`

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

### Step 1: Determine scope

If no scope argument, list existing files and ask which one to delete.

### Step 2: Confirm deletion

Use `AskUserQuestion`:
- **Question:** "Are you sure you want to delete `.geniro/instructions/{{scope}}.md`? This cannot be undone (unless the file is committed to git)."
- **Options:**
  - "Delete the file"
  - "Cancel"

### Step 3: Execute

If confirmed:
```bash
rm -f .geniro/instructions/{{scope}}.md
```

Report: "Deleted `.geniro/instructions/{{scope}}.md`. The {{affected skills}} will no longer load these instructions."

If the directory is now empty:
```bash
rmdir .geniro/instructions/ 2>/dev/null
```

## No-Argument Behavior

If the user runs `/geniro:instructions` with no command, default to `list`.

## Definition of Done

- [ ] Command routed correctly based on argument
- [ ] File operations completed successfully
- [ ] User confirmed before any destructive operation (delete)
- [ ] Validation checked structure, phase names, and scope validity
