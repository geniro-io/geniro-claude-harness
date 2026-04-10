---
name: geniro:setup
description: "AI-driven project setup. Analyzes your codebase, interviews you about preferences, and generates a tailored CLAUDE.md — specific to your project's language, framework, and conventions."
context: main
model: opus
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[optional: path to template directory]"
---

# Setup: AI-Driven Plugin Setup

This skill uses AI to analyze your codebase, interview you about preferences, and generate tailored configuration files — specific to your project's language, framework, and conventions.

## Installation Model

The **plugin** provides agents, skills, hooks, and review criteria globally. Your **project** gets only what needs to be project-specific: CLAUDE.md.

**Plugin** (source — distributed via Claude Code marketplace, lives at `${CLAUDE_PLUGIN_ROOT}`):
```
geniro-claude-plugin/
├── agents/               # Global — agents read CLAUDE.md for project context
├── skills/               # Global — provided by plugin (including review criteria)
├── hooks/                # Global — provided via hooks.json
├── rules/                # Plugin-internal conventions (not copied to projects)
└── settings.json         # StatusLine + permissions (global)
```

**Your project** (target — what actually gets committed):
```
your-project/
├── CLAUDE.md                    # Enriched with tech stack, commands, conventions
│
└── .geniro/
    ├── workflow/                 # Committed — integration configs (Linear, etc.)
    ├── instructions/            # Committed — custom skill instructions (optional)
    ├── planning/                # Git-ignored
    ├── debug/                   # Git-ignored
    └── knowledge/               # Git-ignored
```

**How to set up** (the user runs this in their project):
1. Install the plugin
2. Run `/geniro:setup` in Claude Code
3. Commit: `git add CLAUDE.md && git commit -m 'chore: add geniro plugin config'`

**To re-sync later:**
1. Update the plugin: `claude plugin update geniro-claude-plugin@geniro-claude-harness` (or run `/geniro:update`)
2. Run `/geniro:setup` in Claude Code — it analyzes your files against what would be generated and shows differences

## Path Constraints

**NEVER use `~` in file paths passed to Read, Write, Edit, or Glob tools.** The `~` character is NOT expanded by these tools — it creates a literal `~` directory in the working directory. Always use `${CLAUDE_PLUGIN_ROOT}` for plugin files or absolute paths for project files.

Before doing anything else, resolve the user's home directory:
```bash
echo "$HOME"
```
Store the output as `$USER_HOME` (e.g., `/Users/username`). Use `$USER_HOME` wherever you need the home directory path — never `~`.

## Phase 0: Locate Template Source

### Locate template files

Find the template files using this priority order:

1. **Plugin location**: Check `${CLAUDE_PLUGIN_ROOT}/agents/` exists
   - If found: use `${CLAUDE_PLUGIN_ROOT}` as `$TEMPLATE_DIR` — this is the standard plugin installation path

2. **Explicit argument**: If `$ARGUMENTS` contains a path -> verify it contains `agents/` directory

Store the resolved path as `$TEMPLATE_DIR` for all subsequent phases.

Also check for `.geniro/.geniro-state.json`:
- If it exists -> read it. Store as `$GENIRO_STATE`. Its presence means a previous `/geniro:setup` completed successfully — this is an **update**, not a fresh install.
- If it does not exist -> **fresh install**.

Store the detected mode as `$INSTALL_MODE` (one of: `fresh`, `update`).

## What Gets Written to Your Project

**Written to project (committed):**
- `CLAUDE.md` — enriched with tech stack, commands, conventions (with user permission)
- `.geniro/workflow/*.md` — integration workflow files (Linear, etc.), created based on user choices
- `.geniro/instructions/*.md` — custom skill instructions (optional, created based on user choices)

**Not written (provided by plugin globally):**
- All 13 agents (read CLAUDE.md for project context at runtime)
- All skills (including review criteria)
- All hooks (via plugin hooks.json)
- StatusLine (in plugin settings.json)

**Written to .geniro/ (git-ignored, not committed):**
- `.geniro/planning/` — created empty, populated during /geniro:implement
- `.geniro/debug/` — created empty, populated during /geniro:debug
- `.geniro/knowledge/` — created empty, populated during /geniro:learnings

## Phase 1: Codebase Analysis

Scan the repository to gather objective facts. Do NOT ask the user for this — detect it.

### 1.1 Language & Framework Detection

Read these files to determine the tech stack:

```
package.json, package-lock.json, yarn.lock, pnpm-lock.yaml, bun.lockb
requirements.txt, pyproject.toml, setup.py, setup.cfg, Pipfile
Cargo.toml, Cargo.lock
go.mod, go.sum
pom.xml, build.gradle, build.gradle.kts
Gemfile, Gemfile.lock
*.csproj, *.sln, Directory.Build.props
```

Detect:
- **Language** (JavaScript/TypeScript, Python, Rust, Go, Java, Ruby, C#, etc.)
- **Framework** (Next.js, Django, FastAPI, Express, Rails, Spring Boot, etc.)
- **Package manager** (npm, yarn, pnpm, bun, pip, cargo, go, maven, gradle, bundler)
- **ORM/database** (Prisma, SQLAlchemy, ActiveRecord, GORM, Diesel, TypeORM, etc.)
- **Test runner** (Jest, Vitest, pytest, cargo test, go test, JUnit, RSpec, etc.)
- **Linter/formatter** (ESLint, Prettier, Ruff, Black, Clippy, golangci-lint, RuboCop, etc.)
- **Component library** (React, Vue, Angular, Svelte — if frontend exists)
- **State management** (Redux, Zustand, Jotai, Pinia — if frontend exists)
- **Styling** (Tailwind, styled-components, CSS Modules, SASS — if frontend exists)

**Fallback:** If no language or framework can be detected (empty repo, documentation-only, or unsupported language), use the `AskUserQuestion` tool (do NOT output options as plain text) to ask "I couldn't auto-detect your tech stack. What language and framework does this project use?" If the user says it's a new/empty project, proceed with CLAUDE.md generation only.

### 1.2 Validation Command Discovery

Three-source priority:

1. **Explicit scripts** — Read `package.json` scripts, `Makefile` targets, `Taskfile.yml` tasks, `justfile` recipes
2. **Config inference** — `tsconfig.json` implies `tsc --noEmit`, `pyproject.toml [tool.ruff]` implies `ruff check .`
3. **Language defaults** — Fallback commands for the detected language

Map each discovered command to these categories:
- `build`, `test`, `lint`, `typecheck`, `format_fix`, `lint_fix`, `start`
- `codegen`, `e2e`, `preflight`, `migrate`, `seed`

### 1.3 Architecture & Convention Scan

Use Glob and Grep to detect:
- **Directory structure** — `src/`, `lib/`, `app/`, `pages/`, `routes/`, `services/`, `models/`, `tests/`
- **Architecture pattern** — Layered (routes -> services -> models), hexagonal, MVC, modular
- **Naming conventions** — camelCase vs snake_case, file naming patterns
- **Error handling** — Custom error classes, Result types, try/catch patterns
- **Testing patterns** — Test file naming (`.test.ts`, `_test.go`, `test_*.py`), fixtures, mocks
- **CI/CD** — `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`
- **Docker** — `Dockerfile`, `docker-compose.yml`
- **Database** — Migration files, schema files, seed files

### 1.4 Existing Configuration

Check for pre-existing configuration:
- `.claude/` directory (existing plugin files)
- `CLAUDE.md` (existing project instructions — preserve as-is, do not overwrite)
- `.cursorrules`, `.windsurfrules` (offer to port)
- `.github/copilot-instructions.md`, `.copilot/` (Copilot rules — offer to port)
- `.continue/`, `.cody/` (Continue / Cody configs — read for project rules)
- `AGENTS.md`, `.agents.md` (generic agent instructions — read for context)
- `.editorconfig`, `.prettierrc`, `eslint.config.*`

Route based on `$INSTALL_MODE` detected in Phase 0:

- **`fresh`**: No existing plugin files. Continue to Phase 2 (User Interview) as normal.
- **`update`**: Previous successful install detected (`.geniro/.geniro-state.json` exists). Skip to the **Re-Running Setup (Feature Sync)** flow below. Do NOT run Phases 2-3 unless the user chooses Full Re-run.

If `.claude/` exists but contains only non-template files (no `.geniro/.geniro-state.json`), run the **Existing File Conflict Resolution** process below before continuing to Phase 2.

If `.claude/` does NOT exist but `CLAUDE.md` exists at the project root, this is a hand-written instructions file (common). **Leave it untouched.** The rest of `.claude/` is installed normally as a fresh setup.

### 1.5 Existing File Conflict Resolution

If `.claude/` exists but contains only non-template files, the user has pre-existing files from a different source. **Read `skills/setup/conflict-resolution.md` using the Read tool** and follow its instructions before continuing to Phase 2.

### 1.6 Project Documentation & Knowledge Scan

Scan existing project documentation to extract domain context, conventions, and project knowledge. This informs how rules and CLAUDE.md are tailored — tech stack detection alone is not enough.

**Files to scan (read if they exist):**

```
# Project documentation
README.md                           # Project purpose, architecture overview, setup
CONTRIBUTING.md                     # Development workflow, PR process, conventions
CONVENTIONS.md, CODING_STANDARDS.md # Explicit coding rules
ARCHITECTURE.md                     # System design, component relationships (root-level)
SECURITY.md                         # Security guidelines, threat model
API.md, API_REFERENCE.md            # API patterns, versioning, auth model
docs/architecture.md                # System design (docs/ subfolder variant)
docs/adr/ or docs/decisions/        # Architecture Decision Records

# API specifications (read structure, not full content — extract endpoints, auth, entities)
openapi.yaml, openapi.json          # OpenAPI/Swagger specs
swagger.yaml, swagger.json          # Swagger specs (legacy naming)
asyncapi.yaml, asyncapi.json        # AsyncAPI specs for event-driven systems

# Environment documentation
.env.example, .env.sample           # Documents required env vars and their purpose

# Existing AI tool instructions (read content for domain rules, not just detect presence)
CLAUDE.md                           # Existing Claude instructions (read for context, don't overwrite)
.cursorrules, .windsurfrules        # Cursor / Windsurf rules
.github/copilot-instructions.md    # GitHub Copilot instructions
.copilot/                           # Copilot workspace config
AGENTS.md, .agents.md              # Generic agent instructions
.continue/config.json               # Continue IDE config (may contain project rules)
.cody/                              # Sourcegraph Cody config

# GitHub/GitLab knowledge
.github/pull_request_template.md    # Review expectations and checklist
.github/ISSUE_TEMPLATE/             # Bug/feature templates (reveals project priorities)

# Monorepo structure (if present — reveals workspace organization)
turbo.json                          # Turborepo task pipelines and workspace config
nx.json                             # Nx monorepo config
pnpm-workspace.yaml                 # pnpm workspace definitions
lerna.json                          # Lerna monorepo config
```

Also check `docs/` for any `*.md` files that describe domain concepts, API contracts, or data flows (Glob `docs/**/*.md`, read headers to identify relevant ones — don't read every file).

**For API specs and monorepo configs:** Don't read the entire file — extract the structural knowledge (endpoint names, entity schemas, workspace layout). These files can be large; scan for the project-relevant context only.

**Extract and store as `$PROJECT_KNOWLEDGE`** (internal, used in Phase 3):

1. **Project purpose** — What does this project do? What domain is it in? (from README first paragraph)
2. **Domain terms** — Key entities, concepts, and terminology specific to the business domain (e.g., "tenant", "workspace", "pipeline run", "invoice"). Sources: README, API specs (schema/model names), docs/
3. **Architecture decisions** — Why things are built this way, constraints, trade-offs (from ADR, ARCHITECTURE.md, architecture docs)
4. **Domain safety rules** — Business-critical constraints (e.g., "financial data must not leave EU", "never delete user data without audit trail", "Keycloak realm config is read-only"). Sources: SECURITY.md, .cursorrules, CLAUDE.md, docs/
5. **Team conventions** — Workflow rules, PR process, review expectations, naming decisions beyond what code analysis reveals (from CONTRIBUTING, CONVENTIONS, .github/pull_request_template.md)
6. **API contracts** — Key API patterns, versioning strategy, auth model, endpoint structure (from API.md, openapi.yaml/json, swagger specs)
7. **Existing AI instructions** — Rules already established in CLAUDE.md, .cursorrules, .windsurfrules, .github/copilot-instructions.md, .continue config, .cody config, AGENTS.md (to avoid contradicting them)
8. **Project structure** — Monorepo workspace layout, package boundaries, shared vs isolated modules (from turbo.json, nx.json, pnpm-workspace.yaml, lerna.json). Only relevant for multi-package repos.
9. **Environment requirements** — Required env vars, external service dependencies, feature flags (from .env.example/.env.sample — extract variable names and comments, never values)

**What NOT to extract:** Raw code patterns (Phase 1.3 handles that), dependency lists (Phase 1.1 handles that), or command discovery (Phase 1.2 handles that).

**If no documentation exists:** That's fine — `$PROJECT_KNOWLEDGE` is empty and tailoring proceeds with tech stack info only. Don't ask the user to write docs.

## Phase 2: User Interview

Use the `AskUserQuestion` tool for each question. Ask only what can't be auto-detected.

### 2.1 Confirm Detection (single question)

Present what was detected and ask for confirmation:

```
I analyzed your codebase. Here's what I found:

Tech Stack: TypeScript . Next.js . Prisma . React . Zustand . Tailwind CSS
Package Manager: pnpm
Test Runner: Vitest
Linter: ESLint + Prettier

Validation Commands:
  build:       pnpm run build
  test:        pnpm run test
  lint:        pnpm run lint
  typecheck:   pnpm exec tsc --noEmit
  format_fix:  pnpm run format:fix

From project documentation:
  Project: Multi-tenant SaaS platform for project management
  Domain entities: Tenants, Workspaces, Projects, Members
  Safety rules: Tenant isolation in all queries, PII encrypted at rest
  Architecture: Event-driven between services, REST API v2
  API: 42 endpoints via OpenAPI spec, JWT auth, v2 versioning
  Structure: Monorepo — 3 packages (api, web, shared)
  Env vars: 12 required (DB, Redis, S3, auth provider)
  AI rules: Ported from .cursorrules (8 rules), .github/copilot-instructions.md
  (Source: README.md, docs/architecture.md, CONTRIBUTING.md, openapi.yaml, turbo.json, .env.example)

Is this correct, or do you want to adjust anything?
```

If `$PROJECT_KNOWLEDGE` is empty (no docs found), omit the "From project documentation" section entirely.

Options: "Looks correct" / "I need to adjust some things"

If adjusting, ask specifically what to change.

### 2.2 Team Conventions (only if not detectable)

Ask about conventions that can't be auto-detected from code:

**Architecture pattern** (only if ambiguous from directory structure):
```
I see a src/ directory with routes/, services/, and models/. Which best describes your architecture?

A) Layered — routes -> services -> models (most common)
B) Hexagonal — ports & adapters with clear domain boundaries
C) Feature-based — grouped by feature/domain, not layer
D) Other — I'll describe it
```

**Error handling** (only if no clear pattern detected):
```
How does your project handle errors?

A) Throw/catch with custom error classes
B) Result/Either types (never throw)
C) Error codes / status objects
D) Mixed / no clear pattern yet
```

### 2.3 Optional Integrations

Use the `AskUserQuestion` tool to ask:

```
Would you like to enable Linear integration?

Enabling Linear creates a workflow file (.geniro/workflow/linear.md) that adapts skill behavior — /geniro:implement will auto-detect Linear issue IDs and URLs, fetch issue context, and link commits to issues.
```

Options: "Enable Linear" / "Skip for now"

### 2.4 Custom Instructions

Use the `AskUserQuestion` tool to ask:

```
Would you like to create a custom instructions file?

Custom instructions let you add project-specific rules and steps that modify how all skills behave — like "always update documentation" or "always run E2E tests before shipping". You can edit .geniro/instructions/global.md anytime.
```

Options: "Create instructions file" / "Skip for now"

### 2.5 Component Summary

**What setup writes to the project:**
- `CLAUDE.md` — enriched with detected tech stack, validation commands, and conventions (with your permission)

All agents, skills, hooks, and review criteria are provided globally by the plugin — nothing is copied to the project.

**If no frontend framework was detected**, frontend-related context is omitted from CLAUDE.md.

## Phase 3: Generate Files

### 3.1 CLAUDE.md Generation

Use the `AskUserQuestion` tool (do NOT output options as plain text) to ask the user:

```
Should I create/enrich your CLAUDE.md with the detected project context?

A) Yes, create CLAUDE.md
B) Enrich existing CLAUDE.md (add missing sections only)
C) Skip — I'll maintain CLAUDE.md myself
```

If user skips: proceed without CLAUDE.md generation.

If user approves creation or enrichment:

Read `${CLAUDE_SKILL_DIR}/reference/CLAUDE.md.example` as a structural guide. Generate the CLAUDE.md content (do NOT write to disk yet) that includes:

1. **Project Overview** — Brief description from README/docs
2. **Tech Stack** — All detected technologies (language, framework, ORM, etc.)
3. **Essential Commands** — All validation commands discovered in Phase 1.2 (build, test, lint, typecheck, format_fix, lint_fix, start, codegen, etc.)
4. **Architecture** — Detected patterns (layered, hexagonal, etc.), directory structure
5. **Conventions** — From $PROJECT_KNOWLEDGE: naming, error handling, PR process
6. **Domain Context** — From $PROJECT_KNOWLEDGE: key entities, safety rules, API patterns

If enriching existing CLAUDE.md: read the existing file, identify what's already covered, only add missing sections. Never overwrite existing content.

**Preview step:** Display the full generated CLAUDE.md content to the user inside a markdown code block so they can review exactly what will be written.

Then use the `AskUserQuestion` tool to ask:

```
Here's the generated CLAUDE.md. How should I proceed?

A) Looks good — write it
B) I want to adjust some things
C) Skip — I'll write it myself
```

- If **A) write it**: write the content to disk.
- If **B) adjust**: ask the user what they want to change, apply the requested changes, show the updated preview in a code block, and ask again with the same A/B/C question. Repeat until the user selects A or C.
- If **C) skip**: proceed without writing.

### 3.2 Create Workflow Files (if integrations selected)

For each integration the user enabled in Phase 2.3, create the corresponding workflow file:

**Linear:**
1. Read the template from `${CLAUDE_SKILL_DIR}/workflow-templates/linear.md`
2. Copy it to `.geniro/workflow/linear.md` (create the directory if needed: `mkdir -p .geniro/workflow`)
3. Inform the user to run: `claude mcp add --transport http linear https://mcp.linear.app/mcp`

Future integrations follow the same pattern: read from `${CLAUDE_SKILL_DIR}/workflow-templates/<name>.md`, copy to `.geniro/workflow/<name>.md`.

**Custom Instructions:**
If the user chose to create custom instructions in Phase 2.4:
1. Read the template from `${CLAUDE_SKILL_DIR}/workflow-templates/instructions-template.md`
2. Copy it to `.geniro/instructions/global.md` (create the directory if needed: `mkdir -p .geniro/instructions`)
3. Inform the user they can edit `.geniro/instructions/global.md` anytime, or create per-skill files like `.geniro/instructions/implement.md`

### 3.3 Install StatusLine

Copy the statusline script to a stable location and configure it in user settings. This ensures the statusline works across all projects and survives plugin version updates.

```bash
# Resolve home directory (never use ~)
USER_HOME=$(echo "$HOME")

# Copy statusline script to stable path
mkdir -p "$USER_HOME/.claude/hooks"
cp "${CLAUDE_PLUGIN_ROOT}/hooks/geniro-statusline.js" "$USER_HOME/.claude/hooks/geniro-statusline.js"
```

Then check if `$USER_HOME/.claude/settings.json` already has a `statusLine` entry. If not, add one:
```json
"statusLine": {
  "type": "command",
  "command": "node \"$USER_HOME/.claude/hooks/geniro-statusline.js\""
}
```

Use the actual resolved `$USER_HOME` path in the JSON (e.g., `/Users/username`), not the variable.

If a `statusLine` entry already exists and points to `geniro-statusline.js`, leave it. If it points to something else, ask the user before replacing.

### 3.4 Create Runtime Directories

```bash
mkdir -p .geniro/workflow .geniro/instructions .geniro/planning .geniro/debug .geniro/knowledge
```

## Phase 4: Verify, Track & Report

### 4.1 Verify Generated Files

**Formatting checks:**
- All generated files are valid markdown (no broken formatting, unclosed code blocks)
- No `{{placeholder}}` or `{{PLACEHOLDER}}` patterns remain in ANY generated file
- CLAUDE.md has no placeholder text

**Read `skills/setup/verification-checks.md` using the Read tool** and run all verification checks against the generated files.

### 4.2 Independent Verification Agent

After the orchestrator's own checks (4.1), spawn a **separate subagent** for an independent, comprehensive review of all generated files. A fresh agent catches issues the orchestrator is blind to — it didn't generate the files, so it has no anchoring bias.

**Spawn the verification agent:**

```
Agent(prompt="""
You are verifying a freshly generated geniro plugin configuration. Your job: find every
residual issue the setup process missed. You did NOT generate these files — review
them with fresh eyes.

DETECTED STACK: [language, framework, ORM, test runner, linter]
PROJECT ROOT: [path]

## What to check

Read CLAUDE.md and verify:

### 1. Template Variable Residue
Grep CLAUDE.md for these patterns:
- `{{` and `}}` — unreplaced template variables
- `$TEMPLATE_DIR`, `$PROJECT_KNOWLEDGE`, `$BOOTSTRAPPED` — internal setup variables leaked
- `PLACEHOLDER`, `TODO`, `FIXME` — unfinished markers
- `customize this`, `replace with`, `fill in` — template instructions left behind

### 2. Path Correctness
For every file path referenced inside CLAUDE.md:
- Verify the referenced file actually exists (Glob or ls)
- Check relative vs absolute paths are appropriate
- Verify `${CLAUDE_PLUGIN_ROOT}` references are valid plugin paths

### 3. Stack Contamination
For CLAUDE.md:
- Verify ONLY the detected language/framework appears
- No wrong-language commands (e.g., `npm` in a Python project)
- No wrong-language code blocks (e.g., ```typescript in a Python project)
- No multi-framework lists like "(Django, Rails, FastAPI)" — file must be specific

## Output Format

Return a structured report:

PASSED CHECKS: [list of check categories that passed cleanly]

ISSUES FOUND:
- [CRITICAL] <file>: <description> — must fix before committing
- [WARNING] <file>: <description> — should fix, not blocking
- [INFO] <file>: <description> — minor, optional fix

If no issues found, return: "ALL CHECKS PASSED — configuration is ready to commit."
""", description="Verify setup output")
```

**Route based on results:**
- **ALL PASSED** -> proceed to 4.3
- **CRITICAL issues** -> fix them immediately (Edit tool), then re-verify the specific files
- **WARNING issues** -> fix if straightforward, otherwise note in the summary report for the user
- **Max 2 fix-verify iterations** — if issues persist after 2 rounds, present remaining issues to user in the summary report

### 4.3 Ensure Runtime Directories are Git-Ignored

Add `.geniro/` to `.gitignore`:

```bash
grep -q "^\.geniro/$" .gitignore 2>/dev/null || echo ".geniro/" >> .gitignore
```

Add exceptions for workflow files (these should be committed):
```bash
grep -q "^\!\.geniro/workflow/$" .gitignore 2>/dev/null || echo "!.geniro/workflow/" >> .gitignore
grep -q "^\!\.geniro/workflow/\*\*$" .gitignore 2>/dev/null || echo "!.geniro/workflow/**" >> .gitignore
grep -q "^\!\.geniro/instructions/$" .gitignore 2>/dev/null || echo "!.geniro/instructions/" >> .gitignore
grep -q "^\!\.geniro/instructions/\*\*$" .gitignore 2>/dev/null || echo "!.geniro/instructions/**" >> .gitignore
```

If old patterns exist from a previous install, clean them up:
```bash
sed -i '' '/^\.geniro\/\*$/d' .gitignore 2>/dev/null
sed -i '' '/^\!\.geniro\/project\/$/d' .gitignore 2>/dev/null
```

Do NOT create `.claude/.gitignore` — all ignore rules go in the project root.

### 4.4 Write Plugin State File

Write `.geniro/.geniro-state.json` to track the installation state for future re-runs. This file is git-ignored (covered by the `.geniro/` entry already in `.gitignore`).

Use the Bash tool to get the template commit hash (if `$TEMPLATE_DIR` is a git repo):

```bash
TEMPLATE_COMMIT=$(cd "$TEMPLATE_DIR" && git rev-parse HEAD 2>/dev/null || echo "unknown")
```

Write the state file:

```json
{
  "plugin_version": "$TEMPLATE_COMMIT",
  "installed_at": "ISO-8601 timestamp",
  "install_mode": "fresh|update",
  "features_enabled": {
    "linear": true,
    "custom_instructions": true
  },
  "files": {
    "generated": [
      "CLAUDE.md",
      ".geniro/workflow/linear.md",
      ".geniro/instructions/global.md"
    ],
    "user_created": [
      "...any files in .claude/ that are NOT from the template"
    ]
  }
}
```

Populate the lists from the actual files installed during Phase 3. The categories are:
- **features_enabled**: Record which optional features the user chose (integration and feature names as keys, boolean values). This allows re-runs to know what was configured without re-asking.
- **generated**: Files created by the plugin (CLAUDE.md if plugin-generated, plus any `.geniro/workflow/*.md` and `.geniro/instructions/*.md` files created from templates)
- **user_created**: Files that existed in `.claude/` before setup and are not part of the template

Note: Only include `CLAUDE.md` in `generated` if the plugin created or enriched it. If the user chose to maintain it themselves, omit it.

Ensure `.geniro/.geniro-state.json` is git-ignored. The `.geniro/` entry added in Phase 4.3 already covers this — no separate gitignore entry is needed.

### 4.5 Summary Report

Present to the user:

```
Setup complete! Here's what was generated:

CLAUDE.md          — tech stack, commands, conventions
[If Linear] .geniro/workflow/linear.md — Linear integration workflow
[If Instructions] .geniro/instructions/global.md — Custom workflow instructions

All agents, skills, hooks, and review criteria are provided globally by the plugin.

Tech Stack: [detected]
Integrations: [list enabled]

Next steps:
1. [If Linear] Run: claude mcp add --transport http linear https://mcp.linear.app/mcp
2. Commit: git add CLAUDE.md .geniro/workflow/ .geniro/instructions/ && git commit -m 'chore: add geniro plugin config'
3. Start using: /geniro:implement, /geniro:review, /geniro:refactor
```

## Re-Running Setup (Feature Sync)

If `/geniro:setup` detects `$INSTALL_MODE` is `update`, it enters Feature Sync mode. This flow is self-maintaining — it discovers features by scanning the template filesystem, so new features appear automatically without updating this section.

### Step 1: Scan & Compare

**Scan template capabilities** (what the plugin currently offers):
- Glob `${CLAUDE_SKILL_DIR}/workflow-templates/*.md` → available integration templates
- Check this skill's Phase 2 and Phase 3 for other configurable features (custom instructions, StatusLine)

**Scan project state** (what the user has installed):
- Read `.geniro/.geniro-state.json` → tracked files and `features_enabled`
- Glob `.geniro/workflow/*.md` → installed integrations
- Check `.geniro/instructions/` → custom instructions present?
- Check `.gitignore` → all required entries present? (`.geniro/`, `!.geniro/workflow/`, `!.geniro/workflow/**`, `!.geniro/instructions/`, `!.geniro/instructions/**`)
- Check runtime directories: `.geniro/planning/`, `.geniro/debug/`, `.geniro/knowledge/`
- Check StatusLine: `$USER_HOME/.claude/hooks/geniro-statusline.js` exists?

**Classify each item:**
- **NEW** — in template but not in project (e.g., new workflow template added to plugin, instructions/ not set up)
- **CURRENT** — installed and up to date
- **ORPHANED** — in project but no longer in template (deprecated feature removed from plugin)
- **MISSING INFRA** — gitignore entries, directories, or StatusLine not present

### Step 2: Present Feature Sync Report

```
Plugin configuration status:

| Feature | Status | Action |
|---------|--------|--------|
| CLAUDE.md | [Plugin-generated / User-maintained] | [Regenerate / —] |
| Linear integration | [Installed / Not installed] | [— / Install] |
| Custom instructions | [Installed / Not installed] | [— / Install] |
| [Any new template] | Not installed | Install |
| [Any orphaned file] | Orphaned (removed from plugin) | Remove |
| StatusLine | [Current / Missing] | [— / Install] |
| .gitignore entries | [Complete / N missing] | [— / Repair] |
| Runtime directories | [Complete / N missing] | [— / Repair] |
```

Use `AskUserQuestion` (do NOT output options as plain text):
- **Question:** "How should I proceed with these changes?"
- **Options:**
  - "Apply all recommended changes (Recommended)" — install new, repair infra, flag orphans
  - "Let me pick which changes to apply" — per-feature selection
  - "Re-run full setup" — re-analyze codebase, regenerate everything (see Fresh Install below)
  - "Cancel — no changes"

### Step 3: Execute Selected Changes

For each approved change, run the corresponding fresh-install step:
- **Install integration:** Read template from `${CLAUDE_SKILL_DIR}/workflow-templates/<name>.md`, copy to `.geniro/workflow/<name>.md`
- **Install custom instructions:** Read template from `${CLAUDE_SKILL_DIR}/workflow-templates/instructions-template.md`, copy to `.geniro/instructions/global.md`
- **Remove orphaned files:** Confirm with user, then delete from `.geniro/workflow/`
- **Repair gitignore:** Run Phase 4.3 gitignore commands
- **Repair directories:** Run Phase 3.4 mkdir command
- **Install StatusLine:** Run Phase 3.3 StatusLine installation
- **Regenerate CLAUDE.md:** Re-run Phases 1-3 (analysis → interview → generate) for CLAUDE.md only

After applying changes, update `.geniro/.geniro-state.json` with new `plugin_version`, `installed_at`, and updated `features_enabled` and `files.generated`.

Run Phase 4 verification checks (4.1, 4.2) on all changed files. Then proceed to Phase 5 (Finalize).

**DO NOT end the conversation or ask "anything else?" here.** You MUST proceed to Phase 4 (Verify) and Phase 5 (Finalize) now.

### Fresh Install (with Knowledge Preservation)

If the user chose "Re-run full setup" and wants a completely fresh start:

1. **Backup** CLAUDE.md if it was plugin-generated:
   ```bash
   mkdir -p .geniro/_backup
   cp CLAUDE.md .geniro/_backup/CLAUDE.md 2>/dev/null || true
   ```

2. **Remove plugin-generated CLAUDE.md**, then re-run from Phase 1.

3. **Run fresh install** (Phases 1-5) — codebase analysis, user interview, file generation, verification.

4. **Delete backups:**
   ```bash
   find .geniro/_backup/ -type f -delete 2>/dev/null
   find .geniro/_backup/ -type d -empty -delete 2>/dev/null
   ```

**DO NOT end the conversation or ask "anything else?" here.** You MUST proceed to Phase 4 (Verify) and Phase 5 (Finalize) now.

## Phase 5: Finalize

After setup is complete and verified, finalize the installation.

**Note:** Do NOT delete `.geniro/.geniro-state.json` — this is a persistent state file needed for future `/geniro:setup` re-runs.

### 5.1 Ask User Feedback

Before cleanup, use the `AskUserQuestion` tool (do NOT output options as plain text) to ask for confirmation:

```
Setup is complete. Does everything look correct?

A) Yes, looks good — I'll commit the changes
B) Something needs adjustment — let me tell you what to fix
C) Start over — re-run setup from scratch
```

- **If A**: Print the commit instructions
- **If B**: Ask what needs fixing, apply changes, then ask again
- **If C**: Remove plugin-generated CLAUDE.md, then re-run from Phase 1

**Note**: The `/geniro:setup` skill is provided by the plugin and persists across runs. It does not need to be removed — the user can re-run `/geniro:setup` at any time to update their plugin configuration.

### 5.2 Verify State

```bash
# State files should exist for future re-runs
[[ -f ".geniro/.geniro-state.json" ]] && echo "State file saved"
```

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "I already know this stack, skip analysis" | Every project is different. Auto-detection catches conventions code review misses. |
| "No docs to read, skip 1.6" | Check first. README.md, CONTRIBUTING.md, .cursorrules — even partial docs contain domain knowledge that improves CLAUDE.md. |
| "Default settings are fine, skip the interview" | User preferences prevent rework. 2 minutes of questions saves 20 minutes of fixing. |
| "The generated files look correct, skip verification" | Placeholder text and wrong-language content are invisible without systematic scanning. |
| "I already verified in 4.1, skip the verification agent" | You generated the files — you're blind to your own mistakes. The independent agent catches residual placeholders, broken paths, and cross-file inconsistencies you anchored past. |
| "The user said 'good' / 'looks good' — setup is done, I can stop" | Phase 5 finalization has not run yet. User approval of file changes is NOT session completion. You MUST proceed to Phase 4 (Verify) and Phase 5 (Finalize) before ending. |
| "I'll skip the analysis and just ask what the user wants" | The user can't make an informed choice without seeing what changed. Always analyze BEFORE asking — show the diff summary with specific file counts and change descriptions, then let the user decide. |
| "Stack-specific CLAUDE.md is the main value" | Correct — but it must be generated from actual codebase analysis, not assumptions. |

## Definition of Done

- [ ] Phase 0: Template source located (plugin root or explicit path)
- [ ] Phase 0: Install mode detected (`$INSTALL_MODE`: fresh/update)
- [ ] Phase 1: Codebase analyzed, all detectable info gathered
- [ ] Phase 1.6: Project documentation scanned, domain context extracted (if docs exist)
- [ ] Phase 1.5: Existing file conflicts resolved (if any)
- [ ] Phase 2: User interviewed, preferences recorded
- [ ] Phase 3.1: CLAUDE.md generated or enriched (with user permission)
- [ ] Phase 4.1: Orchestrator verification passed (formatting, placeholders, stack contamination)
- [ ] Phase 4.2: Independent verification agent passed (paths, consistency)
- [ ] Phase 4.4: `.geniro/.geniro-state.json` written with file manifest
- [ ] Phase 5: Finalization complete, state files verified
- [ ] Re-Running Setup: Analysis completed before user prompt
- [ ] User has received summary with next steps
