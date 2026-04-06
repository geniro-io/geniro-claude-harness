---
name: setup
description: "AI-driven project setup. Analyzes your codebase, interviews you about preferences, and generates a tailored .claude/ harness — agents, skills, rules, hooks, and settings. Replaces manual setup scripts."
context: main
model: opus
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[optional: path to template directory]"
---

# Setup: AI-Driven Harness Generation

This skill uses AI to analyze your codebase, interview you about preferences, and generate tailored configuration files — specific to your project's language, framework, and conventions.

## Installation Model

The **template repo** is the source. Your **project repo** is the target. Nothing from the template pollutes your project — no version files, no reference examples.

**Template repo** (source — NOT committed to your project):
```
claude-harness-template/
├── README.md             # Template docs, never copied
├── HOOKS.md              # Hook docs, never copied
├── _reference/           # AI reads during generation, never copied
├── agents/               # → copied to .claude/agents/
├── skills/               # → copied to .claude/skills/
├── hooks/                # → copied to .claude/hooks/
├── rules/                # → stubs, regenerated per-project
└── settings.json         # → copied to .claude/settings.json
```

**Your project** (target — what actually gets committed):
```
your-project/
└── .claude/
    ├── agents/                  # Committed — 12 agents
    ├── skills/                  # Committed — 13 skills
    ├── hooks/                   # Committed — 9 hooks (8 registered + 1 utility)
    ├── rules/                   # Committed — generated per-project
    ├── settings.json            # Committed — permissions & hooks
    └── .artifacts/              # Git-ignored via root .gitignore
        ├── planning/            # Specs, architecture, state files
        ├── debug/               # Hypothesis tracking
        └── knowledge/           # Learnings, session summaries
```

**How to set up** (the user runs this in their project):
1. Clone or download the template repo somewhere (e.g., `~/claude-harness-template`)
2. Run `~/claude-harness-template/install.sh /path/to/your/repo`
3. `cd /path/to/your/repo && claude`
4. Run `/setup` — the skill finds the template files automatically
5. Commit: `git add .claude/ && git commit -m 'chore: add Claude Code harness'`

**To re-sync later:**
1. `cd ~/claude-harness-template && git pull`
2. Run `~/claude-harness-template/install.sh /path/to/your/repo`
3. In your project: `/setup` — it analyzes every file against the template and shows differences

## Phase 0: Locate Template Source

### Locate template files

Find the template files using this priority order:

1. **Bootstrap location** (set by `install.sh`): Check `.claude/.artifacts/template-source/agents/` exists
   - If it exists → use `.claude/.artifacts/template-source/` as `$TEMPLATE_DIR`
   - This is the standard install path — `install.sh` copies the full template here

2. **Explicit argument**: If `$ARGUMENTS` contains a path → verify it contains `agents/` and `skills/` directories

3. **Common locations**: Search `~/claude-harness-template`, `../claude-harness-template`, `~/.claude/harness-template`

4. **Ask user**: Use `AskUserQuestion`: "Where is the claude-harness-template directory? (e.g., ~/claude-harness-template)"

Store the resolved path as `$TEMPLATE_DIR` for all subsequent phases.

Track whether the source was the bootstrap location (`$BOOTSTRAPPED=true`) — this determines whether cleanup runs at the end (Phase 5).

## What Gets Written to Your Project

**Tailored (copied from template, then edited by AI for your stack):**
- `.claude/agents/backend-agent.md` — Tailored to your backend stack
- `.claude/agents/frontend-agent.md` — Tailored to your frontend stack
- `.claude/rules/backend-conventions.md` — Language-specific coding conventions
- `.claude/rules/security-patterns.md` — Language-specific security patterns
- 5 review criteria files in `.claude/skills/review/` — Stack-specific grep patterns, code examples, and framework checks

**Copied directly from template (universal, no customization needed):**
- 11 universal agents from `$TEMPLATE_DIR/agents/`
- 13 skills from `$TEMPLATE_DIR/skills/` (setup is removed after completion)
- 9 hooks from `$TEMPLATE_DIR/hooks/` (8 registered + 1 backpressure utility)
- `settings.json` from `$TEMPLATE_DIR/settings.json`

**Written to .artifacts/ (git-ignored, not committed):**
- `.claude/.artifacts/planning/` — created empty, populated during /implement
- `.claude/.artifacts/debug/` — created empty, populated during /debug
- `.claude/.artifacts/knowledge/` — created empty, populated during /learnings

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

**Fallback:** If no language or framework can be detected (empty repo, documentation-only, or unsupported language), use `AskUserQuestion`: "I couldn't auto-detect your tech stack. What language and framework does this project use?" If the user says it's a new/empty project, proceed with universal agents + hooks only, skip generated files.

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
- **Architecture pattern** — Layered (routes → services → models), hexagonal, MVC, modular
- **Naming conventions** — camelCase vs snake_case, file naming patterns
- **Error handling** — Custom error classes, Result types, try/catch patterns
- **Testing patterns** — Test file naming (`.test.ts`, `_test.go`, `test_*.py`), fixtures, mocks
- **CI/CD** — `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`
- **Docker** — `Dockerfile`, `docker-compose.yml`
- **Database** — Migration files, schema files, seed files

### 1.4 Existing Configuration

Check for pre-existing configuration:
- `.claude/` directory (existing harness files)
- `CLAUDE.md` (existing project instructions — preserve as-is, do not overwrite)
- `.cursorrules`, `.windsurfrules` (offer to port)
- `.github/copilot-instructions.md`, `.copilot/` (Copilot rules — offer to port)
- `.continue/`, `.cody/` (Continue / Cody configs — read for project rules)
- `AGENTS.md`, `.agents.md` (generic agent instructions — read for context)
- `.editorconfig`, `.prettierrc`, `eslint.config.*`

If `.claude/` exists with agents, skills, or hooks (harness files already present), proceed with the "Re-Running Setup" flow (see below) — which compares each file against the template and shows differences.

If `.claude/` exists but contains only user-created files (no agents/skills/hooks from this template), run the **Existing File Conflict Resolution** process below before continuing to Phase 2.

If `.claude/` does NOT exist but `CLAUDE.md` exists at the project root, this is a standalone instructions file (common — many projects have a hand-written CLAUDE.md). **Leave it untouched.** The setup skill does not generate or modify CLAUDE.md — that's the developer's responsibility. The rest of `.claude/` is installed normally as a fresh setup.

### 1.5 Existing File Conflict Resolution

If `.claude/` exists but contains only non-template files, the user has pre-existing files from a different source. **Read `skills/setup/conflict-resolution.md` using the Read tool** and follow its instructions before continuing to Phase 2.

### 1.6 Project Documentation & Knowledge Scan

Scan existing project documentation to extract domain context, conventions, and project knowledge. This informs how agents, rules, and review criteria are tailored — tech stack detection alone is not enough.

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

Tech Stack: TypeScript · Next.js · Prisma · React · Zustand · Tailwind CSS
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

### 2.2 Workflow Preferences

Ask about workflow (one question at a time):

**Git workflow:** Always ask the user before any git operation (commit, push, PR). This is not configurable — do NOT ask the user about it during setup.

**Code review:**
```
How thorough should automated code reviews be?

A) Quick — bugs and security only (faster, less noise)
B) Standard — bugs, security, architecture, tests (recommended)
C) Comprehensive — all categories including style nitpicks
```

### 2.3 Team Conventions (only if not detectable)

Ask about conventions that can't be auto-detected from code:

**Architecture pattern** (only if ambiguous from directory structure):
```
I see a src/ directory with routes/, services/, and models/. Which best describes your architecture?

A) Layered — routes → services → models (most common)
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

### 2.4 Optional Integrations

```
Which integrations do you want to enable?

☐ Linear (issue tracking — pass issue IDs to /implement)
☐ GitHub (PR workflows, issue linking)
☐ Database safety hooks (block dangerous queries)
☐ Context monitoring (warn when context is getting large)
```

### 2.5 Scope Selection

```
Which components do you want to install?

A) Full setup — all 13 agents, 13 skills (incl. plan), 9 hooks (recommended)
B) Core only — 6 core agents, 8 core skills, essential hooks
C) Minimal — just implement, review, and safety hooks
D) Custom — I'll pick individually
```

If "Custom", present agent/skill/hook lists with checkboxes.

## Phase 3: Generate Files

### 3.1 Copy Template Files

Copy template files to `.claude/`. **Only write files that exist in the template — never delete existing files that aren't part of the template.** If the user has custom agents, skills, hooks, or rules they created themselves, those must be preserved untouched.

**All agents** (copy all or selected subset):
- `architect-agent.md`, `skeptic-agent.md`, `reviewer-agent.md`, `refactor-agent.md`
- `debugger-agent.md`, `security-agent.md`, `doc-agent.md`, `devops-agent.md`
- `knowledge-agent.md`, `knowledge-retrieval-agent.md`, `meta-agent.md`
- `backend-agent.md`, `frontend-agent.md`

**All skills** (copy all or selected subset):
- `plan/`, `implement/`, `review/`, `spec/`, `follow-up/`, `refactor/`, `deep-simplify/`
- `debug/`, `learnings/`, `onboard/`, `features/`, `ui-review/`

**Hooks** (copy all or selected subset based on integration choices):
- Safety: `dangerous-command-blocker.sh`, `file-protection.sh`, `secret-protection-input.sh`, `secret-protection-output.sh`
- Monitoring: `context-monitor.sh`
- Lifecycle: `pre-compact-state-save.sh`, `post-compact-notification.sh`
- Database: `db-guard.sh` (only if database integration selected)
- Utility: `backpressure.sh` (not a hook — sourced by skills for output compression)

**settings.json** — If no existing `settings.json`, copy from template and adjust hook paths. If `settings.json` already exists, **merge** template entries into it — preserve any user-added permissions, hooks, or custom settings that aren't in the template.

**Review criteria** — Do NOT copy criteria files here. They are generated in Phase 3.5 with stack-specific content.

Use shell `cp` via the Bash tool to copy each file individually — do NOT use `rm -rf` on entire directories or `cp -r` on directories, as that would overwrite user-created files. If `.claude/agents/` already contains files not in the template (user-created agents), they must remain untouched after this step.

If the template was bootstrapped via `install.sh`, `$TEMPLATE_DIR` is `.claude/.artifacts/template-source/`. Otherwise it's the external template path provided by the user.

```bash
# Create target directories (install.sh only creates .claude/.artifacts/template-source/ and .claude/skills/setup/)
mkdir -p .claude/agents
mkdir -p .claude/hooks
mkdir -p .claude/rules
mkdir -p .claude/skills/plan
mkdir -p .claude/skills/implement
# ... repeat for each selected skill

# Agents (copy all or selected subset)
cp "$TEMPLATE_DIR/agents/architect-agent.md" .claude/agents/
cp "$TEMPLATE_DIR/agents/skeptic-agent.md" .claude/agents/
# ... repeat for each selected agent

# Skills (copy all files in each selected skill directory — includes companion files like plan-criteria.md)
cp "$TEMPLATE_DIR/skills/plan/"* .claude/skills/plan/
cp "$TEMPLATE_DIR/skills/implement/"* .claude/skills/implement/
# ... repeat for each selected skill

# Hooks (copy all or selected subset)
cp "$TEMPLATE_DIR/hooks/dangerous-command-blocker.sh" .claude/hooks/
cp "$TEMPLATE_DIR/hooks/context-monitor.sh" .claude/hooks/
# ... repeat for each selected hook
chmod +x .claude/hooks/*.sh
```

Files like `backend-agent.md`, `frontend-agent.md`, `rules/backend-conventions.md`, and `rules/security-patterns.md` are also copied via `cp` here, then tailored via Read+Edit in Phases 3.2-3.4.

For `settings.json`: if no existing file, use `cp` from template. If one already exists, use Read+Edit to **merge** template entries — preserve any user-added permissions, hooks, or custom settings.

**Note:** Do NOT copy `skills/setup/` from the template — the setup skill is removed after completion (Phase 5.2). It's a bootstrap-only skill, not part of the permanent harness.

### Agent Prompt Principles (apply when editing agents)

When editing agent files for the project, follow these evidence-based principles:

1. **"You are..." framing** — Address the agent in 2nd person ("You are a backend engineer working in..."). Never 3rd person ("This agent specializes in...").
2. **No competency declarations** — Do NOT list abstract expertise ("deep understanding of X", "expertise spans Y"). Listing knowledge doesn't improve behavior. Instead, provide concrete project context, behavioral constraints, and procedures.
3. **Project Context over Domain Expertise** — Use a factual "Project Context" section listing framework, paths, tools, and commands. Facts the agent needs, not claims about what it "understands."
4. **Behavioral constraints > personality** — Brief role identity then immediately into rules, procedures, and concrete examples. No elaborate personality narratives.
5. **Show, don't describe** — Concrete examples of patterns to follow (from the actual codebase) teach better than abstract rules. Include 2-3 real code patterns found during detection.
6. **Critical info at boundaries** — Core identity and constraints at the top. Success criteria and quality checklist at the bottom. Supporting procedures in the middle.

### 3.2 Tailor Backend Agent

The backend agent was copied in 3.1 with `{{PLACEHOLDER}}` values. Edit it in-place:

1. **Frontmatter** — update `description` to mention the detected framework (e.g., "Implement backend features for Django + PostgreSQL")
2. **Project Context section** — replace `{{PLACEHOLDER}}` values with actual detected framework, ORM, test runner, linter commands
3. **Domain Context section** — if `$PROJECT_KNOWLEDGE` contains relevant information, add a `## Domain Context` section after Project Context with:
   - **Project purpose** — one-line description of what the project does (from README)
   - **Key domain entities** — the core objects/concepts this backend manages (e.g., "Tenants, Workspaces, Pipeline Runs, Invoices")
   - **Domain safety rules** — business-critical constraints from docs (e.g., "Never delete user data without audit trail", "Financial calculations use decimal, never float")
   - **API patterns** — versioning strategy, auth model, key conventions from API docs
   - Only include what was found — don't invent domain context. If `$PROJECT_KNOWLEDGE` is empty, skip this section entirely.
4. **Remove the setup note** (the blockquote about `/setup` replacing placeholders)
5. **Replace `{{PLACEHOLDER}}` patterns throughout** — in workflow steps, test commands, quality checks, success criteria. Use actual detected values.
6. **Remove irrelevant sections** — if no ORM detected, remove ORM-related workflow steps. If no specific pattern applies, remove it rather than leaving generic placeholders.
7. **Add 2-3 real code patterns** from the detected codebase (e.g., actual route patterns, actual test patterns found during Phase 1 detection)

**Anti-leakage rules:**
- Code examples must be in the detected language ONLY
- Do not add competency declarations, expertise lists, or 3rd-person framing (see Agent Prompt Principles above)
- Domain context must come from `$PROJECT_KNOWLEDGE` (docs the project actually has) — never invent domain knowledge

### 3.3 Tailor Frontend Agent

The frontend agent was copied in 3.1 with `{{PLACEHOLDER}}` values. Edit it in-place. Same approach as backend.

**If no frontend framework was detected → delete the copied `frontend-agent.md` entirely.**

1. **Frontmatter** — update `description` to mention the detected framework
2. **Project Context section** — replace `{{PLACEHOLDER}}` values with actual detected framework, component library, state management, styling, test runner
3. **Domain Context section** — same as backend (3.2 step 3): add project purpose, key UI entities/flows, and domain-specific UI rules from `$PROJECT_KNOWLEDGE`. For frontend, also include:
   - **Key user flows** — the main workflows users perform (from docs/guides)
   - **UI conventions** — design system references, accessibility requirements, responsive breakpoints (from existing docs)
   - Skip if `$PROJECT_KNOWLEDGE` has no relevant frontend info.
4. **Remove the setup note** (the blockquote about `/setup` replacing placeholders)
5. **Replace `{{PLACEHOLDER}}` patterns throughout** — in workflow steps, test commands, quality checklist
6. **Remove irrelevant sections** — if no state management library detected, simplify those steps. If no E2E runner, remove E2E references.
7. **Add real component patterns** from the detected codebase

**Anti-leakage rules:**
- Only include the ONE detected framework — remove all alternative framework references
- Code examples must use the detected framework and styling approach ONLY
- Domain context must come from `$PROJECT_KNOWLEDGE` — never invent domain knowledge

### 3.4 Tailor Rules Files

**Before tailoring, check if the project already has rules files:**

1. Glob for existing rules in all common locations:
   - `.claude/rules/*.md` — Claude Code rules
   - `.cursor/rules/*.mdc` or `.cursor/rules/*.md` — Cursor rules (new format)
   - `.cursorrules` — Cursor rules (legacy root file)
   - `.windsurfrules` — Windsurf rules
   - `.github/copilot-instructions.md` — GitHub Copilot instructions
   - `.copilot/` — Copilot workspace config
   - `.continue/config.json` — Continue IDE project rules
   - `.cody/` — Sourcegraph Cody config
   - `.aider*` — Aider config files
   - `AGENTS.md` or `.agents.md` — generic agent instructions
   - `CONVENTIONS.md` or `CODING_STANDARDS.md` — manual convention docs
   - `CONTRIBUTING.md` — may contain coding conventions alongside PR process
2. If existing rules files are found:
   - Read them to understand what conventions are already documented
   - **Do NOT overwrite or duplicate existing rules.** If the project already has backend conventions or security patterns documented, skip tailoring that file.
   - If existing rules are partial (e.g., cover naming but not error handling), tailor only the missing parts as a separate file — or ask the user whether to merge or keep separate.
   - If existing rules are from another tool (Cursor, Windsurf, Copilot), ask the user: "Found existing rules at `[path]`. Should I: (A) import and adapt them into `.claude/rules/`, (B) keep the copied template rules alongside them, or (C) skip rules entirely?"
3. If no existing rules found, tailor the copied rules files as described below.

The rules files were copied in Phase 3.1. They contain code examples in MULTIPLE languages (TypeScript, Python, etc.) to cover all possibilities. Edit them in-place to keep ONLY the detected language.

**`rules/backend-conventions.md`:**
- Remove the setup note (the blockquote about `/setup`)
- **Remove all code examples NOT in the detected language.** If project is Python, delete every TypeScript code block — zero non-Python code.
- **Narrow glob patterns** to ONLY the detected language's file extensions (e.g., `"src/**/*.py"` not `"src/**/*.{js,ts,py,go}"`)
- Remove sections that don't apply (e.g., "Async/Await vs Promises" for Go projects)
- Add framework-specific conventions for the detected framework
- Reference actual files in the codebase as "golden examples"
- **Enrich from `$PROJECT_KNOWLEDGE`**: If docs contain team conventions (from CONTRIBUTING.md, CONVENTIONS.md, .cursorrules), merge them into the appropriate sections. Don't duplicate — if a convention already exists in the template rules, skip it. If the project has conventions not covered by the template (e.g., "all API responses use envelope format", "migrations must be reversible"), add them as new subsections.

**`rules/security-patterns.md`:**
- Remove the setup note
- **Remove all code examples NOT in the detected language**
- **Narrow glob patterns** to the detected language's file extensions
- Add framework-specific security guidance (Django CSRF, Express helmet, etc.) — only for the detected framework
- Update dependency audit commands to match the detected package manager
- **Enrich from `$PROJECT_KNOWLEDGE`**: If docs contain domain safety rules (e.g., "PII must be encrypted at rest", "never expose internal IDs in API responses", "financial data stays in EU region"), add them as a "Domain-Specific Security Rules" section. These are the rules a generic security template can't know — they come from the project's own documentation.

### 3.5 Generate Review Criteria

Read the template criteria files at `$TEMPLATE_DIR/skills/review/` (`bugs-criteria.md`, `security-criteria.md`, `tests-criteria.md`, `architecture-criteria.md`, `guidelines-criteria.md`). These are universal/JS-centric references. Generate stack-specific versions tailored to the detected language and framework.

**For each criteria file, transform:**

1. **Grep patterns** — Rewrite all `grep` commands to use the detected language's syntax and file extensions. Replace `file.js` / `file.ts` with the correct extension (`.py`, `.go`, `.rs`, `.rb`, `.java`, etc.).

2. **Code examples** — Replace JavaScript/TypeScript-specific patterns with equivalents for the detected language:
   - Null handling: `?.` / `??` (JS) → `is None` (Python) → `nil` (Go/Ruby) → `Option<T>` (Rust) → `Optional<T>` (Java)
   - Imports: `import/require` (JS) → `import` (Python) → `import` (Go) → `use` (Rust) → `import` (Java)
   - Async: `async/await` / `Promise` (JS) → `asyncio` (Python) → goroutines (Go) → `tokio` (Rust)
   - Error handling: `try/catch` (JS) → `try/except` (Python) → `if err != nil` (Go) → `Result<T,E>` (Rust)

3. **Framework-specific checks** — Add checks specific to the detected framework:
   - **bugs-criteria.md**: Django N+1 (`prefetch_related`), Rails N+1 (`includes`), React stale closures, Vue reactivity caveats
   - **security-criteria.md**: Django CSRF, Express helmet, Rails `params.permit`, Go `html/template` escaping, framework-specific auth middleware
   - **tests-criteria.md**: pytest fixtures/parametrize, RSpec matchers, Jest mocks/spies, Go table-driven tests, Rust `#[test]` patterns
   - **architecture-criteria.md**: Framework-specific module patterns (Django apps, NestJS modules, Rails concerns, Go packages)
   - **guidelines-criteria.md**: Language style guide (PEP 8, Go fmt, Rust fmt, Ruby style guide), framework naming conventions

4. **Dependency audit commands** — Replace `npm audit` with the correct command: `pip audit` (Python), `cargo audit` (Rust), `go vuln check` (Go), `bundle audit` (Ruby), `mvn dependency-check` (Java).

5. **Remove "Stack-Agnostic Patterns" section** — The generated file IS stack-specific. This section listed all language equivalents as a fallback; it's no longer needed.

6. **Enrich from `$PROJECT_KNOWLEDGE`** — If project documentation contains domain-specific review concerns, add them to the relevant criteria file:
   - **security-criteria.md**: Domain safety rules (e.g., "Check that PII fields are never logged", "Verify multi-tenant data isolation in queries")
   - **architecture-criteria.md**: Architecture decisions from ADR (e.g., "Services must not call other services directly — use events", "All database access goes through repository layer")
   - **bugs-criteria.md**: Known domain pitfalls from docs (e.g., "Currency amounts must use Decimal, never float", "Timezone-naive datetime is a bug in this project")
   - **guidelines-criteria.md**: Team conventions from CONTRIBUTING/CONVENTIONS docs
   - Add these as a "Project-Specific Checks" subsection within each criteria file, clearly separated from framework checks. Only add what was found in docs — never invent domain rules.

**Anti-leakage rules for criteria files:**
- Every grep pattern, code example, and tool command must use ONLY the detected language. A Python project's criteria must not contain `grep -n "req\." file.js` or `npm audit`.
- Do not list alternative language equivalents ("In Python use X, in Go use Y"). The file is for ONE language.
- Keep the structure (section headers, severity guidelines, output format, review checklist, common false positives) — only transform the content within.
- If a check category doesn't apply to the detected language (e.g., "Optional chaining" for Go), replace it with the language's equivalent concern (e.g., nil pointer dereference for Go).
- Domain-specific checks from `$PROJECT_KNOWLEDGE` must be traceable to actual project documentation — cite the source file (e.g., "from docs/architecture.md").

### 3.6 Configure Linear Integration (if selected)

If the user selected Linear integration:
1. Inform the user to run: `claude mcp add --transport http linear https://mcp.linear.app/mcp`
2. Note that `/implement` auto-detects Linear issue IDs and URLs

## Phase 4: Verify, Track & Report

### 4.1 Verify Generated Files

**Formatting checks:**
- All generated files are valid markdown (no broken formatting, unclosed code blocks)
- No `{{placeholder}}` or `{{PLACEHOLDER}}` patterns remain in ANY generated file
- All hook scripts are executable (`chmod +x`)
- `settings.json` is valid JSON
- All agent frontmatter has required fields (name, description, tools, maxTurns)

**Read `skills/setup/verification-checks.md` using the Read tool** and run all verification checks against the generated files.

### 4.2 Independent Verification Agent

After the orchestrator's own checks (4.1), spawn a **separate subagent** for an independent, comprehensive review of all generated files. A fresh agent catches issues the orchestrator is blind to — it didn't generate the files, so it has no anchoring bias.

**Spawn the verification agent:**

```
Agent(prompt="""
You are verifying a freshly generated Claude Code harness. Your job: find every
residual issue the setup process missed. You did NOT generate these files — review
them with fresh eyes.

DETECTED STACK: [language, framework, ORM, test runner, linter]
PROJECT ROOT: [path]

## What to check

Read every file in `.claude/` (agents, skills, hooks, rules, settings.json) and verify:

### 1. Template Variable Residue
Grep ALL files in `.claude/` for these patterns:
- `{{` and `}}` — unreplaced template variables
- `$TEMPLATE_DIR`, `$PROJECT_KNOWLEDGE`, `$BOOTSTRAPPED` — internal setup variables leaked
- `PLACEHOLDER`, `TODO`, `FIXME` — unfinished markers
- `customize this`, `replace with`, `fill in` — template instructions left behind

### 2. Path Correctness
For every file path referenced inside agent prompts, skill files, and hook scripts:
- Verify the referenced file actually exists (Glob or ls)
- Check relative vs absolute paths are appropriate
- Verify hook paths in `settings.json` match actual files in `.claude/hooks/`
- Verify skill subdirectory references (e.g., `skills/review/bugs-criteria.md`) exist

### 3. Cross-File Consistency
- Agent `allowed-tools` in frontmatter match what the agent's instructions reference
- Skill `allowed-tools` in frontmatter match what the skill's instructions reference
- Hook filenames in `settings.json` match actual hook files in `.claude/hooks/`
- Review criteria files referenced by `/review` skill actually exist
- Plan criteria file referenced by `/plan` skill actually exists

### 4. Stack Contamination (generated files only)
For backend-agent.md, frontend-agent.md, rules/*.md, skills/review/*-criteria.md:
- Verify ONLY the detected language/framework appears
- No wrong-language commands (e.g., `npm` in a Python project)
- No wrong-language code blocks (e.g., ```typescript in a Python project)
- No multi-framework lists like "(Django, Rails, FastAPI)" — file must be specific

### 5. Frontmatter Integrity
For every `.md` file in `.claude/agents/` and `.claude/skills/`:
- Has valid YAML frontmatter (opens and closes with `---`)
- Required fields present: `name`, `description` (agents also need `tools`)
- No duplicate frontmatter keys
- `model` field (if present) uses a valid value

### 6. Hook Executability
- All `.sh` files in `.claude/hooks/` are executable (`ls -la` check)
- All hook scripts have a shebang line (`#!/bin/bash` or `#!/usr/bin/env bash`)
- `settings.json` hook registrations point to files that exist

### 7. settings.json Validity
- Valid JSON (no trailing commas, no comments)
- All tool permission entries reference real tools
- Hook command paths resolve to actual files

## Output Format

Return a structured report:

PASSED CHECKS: [list of check categories that passed cleanly]

ISSUES FOUND:
- [CRITICAL] <file>: <description> — must fix before committing
- [WARNING] <file>: <description> — should fix, not blocking
- [INFO] <file>: <description> — minor, optional fix

If no issues found, return: "ALL CHECKS PASSED — harness is ready to commit."
""", description="Verify setup output")
```

**Route based on results:**
- **ALL PASSED** → proceed to 4.3
- **CRITICAL issues** → fix them immediately (Edit tool), then re-verify the specific files
- **WARNING issues** → fix if straightforward, otherwise note in the summary report for the user
- **Max 2 fix-verify iterations** — if issues persist after 2 rounds, present remaining issues to user in the summary report

### 4.3 Ensure Runtime Directories are Git-Ignored

Add `.claude/.artifacts/` and `.claude/.state/` to the **root** `.gitignore` (not `.claude/.gitignore`):

```bash
# Add to root .gitignore if not already present
grep -q "\.claude/\.artifacts" .gitignore 2>/dev/null || echo ".claude/.artifacts/" >> .gitignore
grep -q "\.claude/\.state" .gitignore 2>/dev/null || echo ".claude/.state/" >> .gitignore
```

Do NOT create `.claude/.gitignore` — all ignore rules go in the project root.

### 4.4 Summary Report

Present to the user:

```
Setup complete! Here's what was generated:

.claude/
  agents/     (N agents)
  skills/     (N skills)
  hooks/      (N hooks)
  rules/      (N rule files)
  settings.json

Tech Stack: [detected]
Validation: build ✓ | test ✓ | lint ✓ | typecheck ✓

Integrations: [list enabled]

Next steps:
1. [If Linear] Run: claude mcp add --transport http linear https://mcp.linear.app/mcp
2. Add Compact Instructions to your CLAUDE.md (recommended — controls what auto-compaction preserves):

   ## Compact Instructions
   When compacting, always preserve:
   - Current pipeline phase and task directory path
   - Architecture decisions and spec requirements
   - Files changed and validation results
   - After compaction: read <task-dir>/state.md to resume pipeline

3. Commit: git add .claude/ && git commit -m 'chore: add Claude Code harness'
4. Start using: /implement, /review, /refactor
```

## Re-Running Setup (Per-File Diff Comparison)

If the user runs `/setup` again on a project that already has `.claude/` with harness files:

### Step 1: Ask Intent

Use `AskUserQuestion`:
```
This project already has a harness installed.

What would you like to do?
A) Fresh install — reinstall from template, then port back your project-specific content (backup → clean install → enrich → delete backup)
B) Compare & update — analyze each file against the template, show differences, decide per-file
C) Regenerate project-specific files only (backend-agent, frontend-agent, rules, review criteria)
D) Cancel
```

### Step 2A: Fresh Install (with Knowledge Preservation)

If user chose A, the template is ALWAYS the base — but existing project-specific knowledge is not thrown away. The flow is: **backup → clean copy → analyze backup → enrich → delete backup.**

**Why backup-then-enrich instead of just wiping?** Existing files may contain project-specific patterns, domain rules, custom commands, safety constraints, or conventions that were added over time (by the user, by previous `/setup` runs, or by manual editing). A fresh install means "start from the latest template structure" — NOT "lose all project knowledge." The template provides the structure; the backup provides the project specificity.

#### 2A.1: Backup existing files

```bash
# Create backup in .artifacts (git-ignored)
cp -r .claude/agents/ .claude/.artifacts/_backup_agents/ 2>/dev/null || true
cp -r .claude/skills/ .claude/.artifacts/_backup_skills/ 2>/dev/null || true
cp -r .claude/hooks/ .claude/.artifacts/_backup_hooks/ 2>/dev/null || true
cp -r .claude/rules/ .claude/.artifacts/_backup_rules/ 2>/dev/null || true
cp .claude/settings.json .claude/.artifacts/_backup_settings.json 2>/dev/null || true
```

#### 2A.2: Remove template files and install fresh

Remove only files that came from the template — **preserve user-created files** (custom agents, skills, hooks, rules not part of the template).

```bash
# List template file names from $TEMPLATE_DIR, then remove only those from .claude/
# Example: if template has agents/architect-agent.md, remove .claude/agents/architect-agent.md
# But if user has .claude/agents/my-custom-agent.md, leave it untouched
```

To identify which files are template files: list all filenames in `$TEMPLATE_DIR/agents/`, `$TEMPLATE_DIR/skills/`, `$TEMPLATE_DIR/hooks/`, `$TEMPLATE_DIR/rules/`. Remove only those matching filenames from `.claude/`. Any file in `.claude/` that does NOT have a corresponding template file is user-created and must be kept.

Phase 1-5 runs normally — codebase analysis, user interview, file generation, tailoring, verification. The template files are installed fresh, then tailored for the detected stack. User-created files remain untouched alongside the new template files.

#### 2A.3: Analyze backup for project-specific enrichments

After Phase 3 (file generation and tailoring) completes but BEFORE Phase 4 (verification), analyze the backed-up files for project-specific content worth porting into the fresh install.

**Spawn parallel subagents** — one per file category that has backups:

```
Agent(prompt: "<see subagent prompt>", description: "Analyze backup: agents")
Agent(prompt: "<see subagent prompt>", description: "Analyze backup: skills")
Agent(prompt: "<see subagent prompt>", description: "Analyze backup: rules")
```

**Subagent task for each category:**

```
You are analyzing backed-up project files against freshly installed template files.
The goal: identify project-specific content in the backup that should be ported
INTO the fresh template files — WITHOUT breaking the template's structure or flow.

BACKUP DIR: .claude/.artifacts/_backup_<category>/
FRESH DIR: .claude/<category>/

For each backup file that has a corresponding fresh file:
1. Read both files fully
2. Identify project-specific content in the backup that is NOT in the fresh version:
   - Domain context (project descriptions, entity names, domain rules)
   - Custom commands (specific build/test/lint commands beyond what /setup detected)
   - Framework-specific patterns added by the user (not by the template)
   - Safety rules specific to the project domain
   - Custom sections the user added (not present in any template file)
   - Project-specific examples, file paths, module names
3. For each piece of project-specific content, classify:
   - ENRICHMENT: Can be added to the fresh file without changing its structure
     (e.g., adding a domain safety rule to an existing "Constraints" section)
   - EXTENSION: Requires a new section in the fresh file
     (e.g., a "Codegen Rule" section that the template doesn't have)
   - CONFLICT: Contradicts or would break the template's flow
     (e.g., backup has different phase ordering — do NOT port this)
4. For backup files with NO corresponding fresh file (user-created agents/skills):
   - Flag as USER_ONLY — these should be preserved as-is

Return structured output:
FILE: <filename>
  ENRICHMENTS:
    - <content summary> | INSERT INTO: <fresh file section>
  EXTENSIONS:
    - <content summary> | ADD AS: <new section name> | AFTER: <existing section>
  CONFLICTS:
    - <content summary> | REASON: <why it can't be ported>
  USER_ONLY: <list of backup files with no template equivalent>

CRITICAL RULES:
- NEVER port structural changes from the backup (phase ordering, compliance tables,
  state persistence patterns). The fresh template's structure is correct by definition.
- ONLY port project-specific CONTENT — domain knowledge, custom commands, safety rules,
  project-specific patterns, user-added sections.
- If a backup file was clearly just a previous template version with no customization,
  report ENRICHMENTS: none.
```

#### 2A.4: Apply enrichments to fresh files

For each enrichment and extension identified by the subagents:

1. **Enrichments** — Edit the fresh file to insert project-specific content into the identified section. Use the same merge principle as conflict-resolution.md: template structure stays, project content goes in.
2. **Extensions** — Add new sections at the identified location. Keep them clearly separated so future template updates can distinguish template sections from project additions.
3. **Conflicts** — Skip. Log them in the summary report so the user knows what was NOT ported and why.
4. **User-only files** — Restore from backup using shell `cp` (e.g., `cp .claude/.artifacts/_backup_agents/my-custom-agent.md .claude/agents/`). These are the user's custom agents/skills/hooks — the template has no opinion about them.

**Anti-corruption rules:**
- Do NOT change phase ordering, compliance tables, Definition of Done, or any structural element in template files
- Do NOT duplicate content that Phase 3 tailoring already added (e.g., if the backup had Django patterns and Phase 3.2 already tailored for Django, don't double up)
- Do NOT port content from the backup that contradicts `$PROJECT_KNOWLEDGE` from Phase 1.6 — the current documentation is more authoritative than old file content

#### 2A.5: Delete backups

After enrichments are applied and verified:
```bash
rm -rf .claude/.artifacts/_backup_agents/
rm -rf .claude/.artifacts/_backup_skills/
rm -rf .claude/.artifacts/_backup_hooks/
rm -rf .claude/.artifacts/_backup_rules/
rm -f .claude/.artifacts/_backup_settings.json
```

**DO NOT end the conversation or ask "anything else?" here.** You MUST proceed to Phase 4 (Verify) and Phase 5 (Cleanup) now — template-source cleanup is mandatory.

### Step 2B: Per-File Diff Comparison

If user chose B, compare every file in the installed `.claude/` against the template:

1. **Build file inventory.** For each file category (agents, skills, hooks, rules, settings.json):
   - List all files in the installed `.claude/<category>/`
   - List all files in the template `$TEMPLATE_DIR/<category>/`
   - Classify each file as: **identical**, **modified**, **template-only** (new in template), **project-only** (not in template)

2. **Read and diff each non-identical file.** For every file that differs between template and installed:
   - Read both versions (template and installed)
   - Identify the specific differences: added sections, removed sections, changed content
   - Assess each file on two independent dimensions:
     - **Has structural improvements?** — template additions (new phases, better instructions, bug fixes)
     - **Has project-specific content?** — customizations the user or `/setup` made for their stack (backend agent tailoring, rules files, review criteria)
   - Both can be true. For files with both, do section-level analysis: identify which sections are structural improvements and which contain project-specific content

3. **Present the full diff report** to the user via output (not AskUserQuestion — too large):

   ```
   ## File Comparison: Template vs Installed

   ### Identical (N files) — no action needed
   - agents/architect-agent.md
   - agents/skeptic-agent.md
   - ...

   ### Modified (N files) — review needed
   | File | Changes | Structural? | Project-specific? |
   |------|---------|-------------|-------------------|
   | agents/reviewer-agent.md | +12 lines in Phase 3, removed old validation | Yes | No |
   | skills/implement/SKILL.md | New Phase 5 (Simplify), restructured Review | Yes | No |
   | agents/backend-agent.md | Django patterns, pytest commands | No | Yes |
   | rules/security-patterns.md | 5 new security sections + NestJS-tailored patterns | Yes | Yes |

   ### Template-only (N files) — new in template
   - agents/knowledge-retrieval-agent.md (NEW)
   - skills/plan/plan-criteria.md (NEW)

   ### Project-only (N files) — not in template
   - agents/custom-domain-agent.md (user-created)
   - skills/custom-workflow/SKILL.md (user-created)
   ```

4. **For each modified file**, show the specific differences:
   ```
   ### agents/reviewer-agent.md (Structural only)
   **Structural changes from template:**
   - Added: confidence scoring in Phase 2 (lines 45-58)
   - Changed: review output format (line 72 → new table format)
   - Removed: redundant validation step (old lines 80-95)

   ### rules/security-patterns.md (Both)
   **Structural changes from template:**
   - Added: 5 new security sections (CSRF, XSS, injection, auth, logging)
   - Changed: threat model format (section 2 → new checklist format)
   **Your project-specific content (preserved):**
   - NestJS guard patterns in section 3
   - Custom Passport.js auth rules
   ```

5. **Ask for decisions** using `AskUserQuestion`:
   ```
   How would you like to handle the differences?

   A) Update all structural changes, preserve project-specific content
   B) Let me review each modified file individually
   C) Update all — overwrite everything with template (re-run tailoring for generated files)
   D) Skip updates — just install template-only (new) files
   ```

6. **Apply based on choice:**
   - **A (recommended):** For each modified file with structural improvements (including "Both" files), copy the new template version using shell `cp`, then Edit to port in project-specific content. Same algorithm as fresh install — template as base, port user customizations in. For generated files (backend-agent, frontend-agent, rules, review criteria), re-run the generation phases (Phase 3.2-3.5) with fresh codebase analysis. Files with only project-specific changes are left as-is.
   - **B:** Present each file one at a time with full diff, ask accept/skip/custom per file.
   - **C:** Overwrite all files from template, re-run Phase 3 for generated files.
   - **D:** Only copy files that exist in template but not in `.claude/`. Skip all existing files.

7. **Install new files** — for template-only files (new agents, skills, hooks), use shell `cp` to copy them into `.claude/` regardless of the user's choice above.

**DO NOT end the conversation or ask "anything else?" here.** You MUST proceed to Phase 4 (Verify) and Phase 5 (Cleanup) now — template-source cleanup is mandatory.

### Step 2C: Regenerate Project-Specific Only

If user chose C:
1. Re-run Phase 1 (Codebase Analysis) to detect current stack
2. Re-run Phase 3.2 (Tailor Backend Agent), Phase 3.3 (Tailor Frontend Agent), Phase 3.4 (Tailor Rules), Phase 3.5 (Generate Review Criteria)
3. Skip universal files — they remain as-is

**DO NOT end the conversation or ask "anything else?" here.** You MUST proceed to Phase 4 (Verify) and Phase 5 (Cleanup) now — template-source cleanup is mandatory.

**If `.claude/` exists but has no recognizable harness files** (no agents/skills/hooks from this template):

Run the Existing File Conflict Resolution flow (Phase 1.5) — this handles semantic comparison and merge.

## Phase 5: Cleanup (bootstrapped installs only)

**When:** `$BOOTSTRAPPED=true` (template was found in `.claude/.artifacts/template-source/`)

After setup is complete and verified, clean up the bootstrap artifacts:

### 5.1 Remove Template Source

The full template copy in `.claude/.artifacts/template-source/` is no longer needed — everything has been installed to `.claude/`. Remove it:

```bash
rm -rf .claude/.artifacts/template-source/
```

### 5.2 Ask User Feedback & Remove Setup Skill

Before cleanup, ask the user for confirmation using `AskUserQuestion`:

```
Setup is complete. Does everything look correct?

A) Yes, looks good — clean up setup files and I'll commit
B) Something needs adjustment — let me tell you what to fix
C) Start over — re-run setup from scratch
```

- **If A**: Remove the setup skill (see below), then print the commit instructions
- **If B**: Ask what needs fixing, apply changes, then ask again
- **If C**: Remove only template-originated files (same selective removal as 2A.2 — preserve user-created files), then re-run from Phase 1

**Remove the setup skill** (only after user confirms):

The `/setup` skill was installed by `install.sh` purely to bootstrap the process. Since the skill is currently running, schedule deletion as the very last action:

```bash
rm -rf .claude/skills/setup/
```

**Why remove it?** Setup is a one-time bootstrap operation. To re-run setup later, the user runs `install.sh` again — which re-copies the setup skill from the template. This keeps the installed harness clean (no setup-specific files committed to the repo).

### 5.3 Verify Cleanup

```bash
# Template source should be gone
[[ ! -d ".claude/.artifacts/template-source" ]] && echo "✓ Template source cleaned up"
```

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "I already know this stack, skip analysis" | Every project is different. Auto-detection catches conventions code review misses. |
| "No docs to read, skip 1.6" | Check first. README.md, CONTRIBUTING.md, .cursorrules — even partial docs contain domain knowledge that makes agents project-aware. |
| "Default settings are fine, skip the interview" | User preferences prevent rework. 2 minutes of questions saves 20 minutes of fixing. |
| "The generated files look correct, skip verification" | Placeholder text and wrong-language content are invisible without systematic scanning. |
| "I already verified in 4.1, skip the verification agent" | You generated the files — you're blind to your own mistakes. The independent agent catches residual placeholders, broken paths, and cross-file inconsistencies you anchored past. |
| "I'll clean up the template source later" | Leftover bootstrap artifacts confuse future sessions. Clean up now. |
| "The user said 'good' / 'looks good' — setup is done, I can stop" | Phase 5 cleanup has not run yet. User approval of file changes is NOT session completion. You MUST proceed to Phase 4 (Verify) and Phase 5 (Cleanup) before ending — `.claude/.artifacts/template-source/` must be removed. |
| "The user can customize agents themselves" | Stack-specific agents are the main value. Generic stubs are a failed setup. |

## Definition of Done

- [ ] Phase 0: Template source located (bootstrap or explicit path)
- [ ] Phase 1: Codebase analyzed, all detectable info gathered
- [ ] Phase 1.6: Project documentation scanned, domain context extracted (if docs exist)
- [ ] Phase 1.5: Existing file conflicts resolved (if any)
- [ ] Phase 2: User interviewed, preferences recorded
- [ ] Phase 3: All files generated and written
- [ ] Phase 4.1: Orchestrator verification passed (formatting, placeholders, cross-language)
- [ ] Phase 4.2: Independent verification agent passed (paths, consistency, frontmatter, hooks)
- [ ] Phase 5: Bootstrap artifacts cleaned up (if bootstrapped install)
- [ ] User has received summary with next steps
