---
name: geniro:setup
description: "AI-driven project setup. Analyzes your codebase, interviews you about preferences, and generates a tailored .claude/ configuration — agents, skills, rules, hooks, and settings. Replaces manual setup scripts."
context: main
model: opus
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[optional: path to template directory]"
---

# Setup: AI-Driven Plugin Setup

This skill uses AI to analyze your codebase, interview you about preferences, and generate tailored configuration files — specific to your project's language, framework, and conventions.

## Installation Model

The **plugin** is the source. Your **project repo** is the target. Nothing from the plugin pollutes your project — no version files, no reference examples.

**Plugin** (source — distributed via Claude Code marketplace, lives at `${CLAUDE_PLUGIN_ROOT}`):
```
geniro-claude-plugin/
├── README.md             # Plugin docs, never copied
├── HOOKS.md              # Hook docs, never copied
├── skills/setup/reference/ # AI reads during generation, never copied
├── agents/               # → global (provided by plugin); backend/frontend copied + tailored
├── skills/               # → global (provided by plugin, not copied)
├── hooks/                # → global (provided by plugin via hooks.json)
├── rules/                # → stubs, regenerated per-project
└── settings.json         # → copied to .claude/settings.json
```

**Your project — Global mode** (target — what actually gets committed):
```
your-project/
├── .claude/
│   ├── agents/                  # Committed — 2 tailored agents (backend + frontend)
│   ├── rules/                   # Committed — generated per-project
│   └── settings.json            # Committed — permissions only
│
└── .geniro/
    ├── project/                 # Committed (!.geniro/project/ in .gitignore)
    │   └── review/              # 5 generated review criteria files
    ├── planning/                # Git-ignored — specs, architecture, state files
    ├── debug/                   # Git-ignored — hypothesis tracking
    └── knowledge/               # Git-ignored — learnings, session summaries
```

**Your project — Standalone mode** (everything in the project):
```
your-project/
├── .claude/
│   ├── agents/                  # All 13 agents (11 universal + 2 tailored)
│   ├── skills/                  # All skills + review criteria
│   │   ├── review/              # 5 generated review criteria files
│   │   ├── setup/               # Setup skill
│   │   ├── implement/           # Implementation skill
│   │   └── ...                  # All other skills
│   ├── hooks/                   # All hook scripts
│   ├── rules/                   # Generated per-project
│   └── settings.json            # Permissions + hook entries
│
└── .geniro/
    ├── planning/                # Git-ignored
    ├── debug/                   # Git-ignored
    └── knowledge/               # Git-ignored
```

**Standalone commit:** `git add .claude/ && git commit -m 'chore: add geniro plugin (standalone)'`

**Note:** After standalone setup, uninstall the plugin to avoid hook duplication: `claude plugin uninstall geniro-claude-plugin@geniro-claude-harness`. Reinstall only when running `/geniro:update`.

**How to set up** (the user runs this in their project):
1. Install the plugin: `claude plugin install geniro-claude-plugin`
2. Run `/geniro:setup` in Claude Code
3. Commit: `git add .claude/ .geniro/project/ && git commit -m 'chore: add geniro plugin'`

**To re-sync later:**
1. Update the plugin: `claude plugin update geniro-claude-plugin@geniro-claude-harness` (or run `/geniro:update`)
2. Run `/geniro:setup` in Claude Code — it analyzes every file against the template and shows differences

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

2. **Explicit argument**: If `$ARGUMENTS` contains a path → verify it contains `agents/` and `skills/` directories

Store the resolved path as `$TEMPLATE_DIR` for all subsequent phases.

Also check for `.geniro/.geniro-state.json`:
- If it exists → read it. Store as `$GENIRO_STATE`. This contains the template version, install date, and file manifest with categories (verbatim/tailored/user-created). Its presence means a previous `/geniro:setup` completed successfully — this is an **update**, not a fresh install.
- If it does not exist but `.claude/` has recognizable plugin files (agents/skills/hooks from this template) → **legacy install** (installed before state tracking was added). Treat as update but without baseline data.
- If it does not exist and `.claude/` has no recognizable plugin files, only non-template files, or doesn't exist → **fresh install**. (Non-template files are handled by Phase 1.5 Conflict Resolution during the fresh install flow.)

Store the detected mode as `$INSTALL_MODE` (one of: `fresh`, `update`, `legacy-update`).

## Phase 0.5: Deploy Mode

**If `$INSTALL_MODE` is `update` or `legacy-update`:** read `deploy_mode` from `.geniro/.geniro-state.json`. If the field exists, store it as `$DEPLOY_MODE` and skip the question below. If absent (legacy state without `deploy_mode`), fall through and ask.

**For fresh installs (or when state lacks `deploy_mode`):** ask the user using `AskUserQuestion`:

**Question:** "How do you want to deploy the plugin?"
**Options:**
- "Global (Recommended)" — Plugin provides skills, agents, and hooks globally. Only project-specific files are written to the repo.
- "Standalone" — Copy ALL plugin files into the project. The repo becomes self-contained — team members don't need the plugin installed.

Store the answer as `$DEPLOY_MODE` (`global` or `standalone`).

## What Gets Written to Your Project

**Written to .claude/ (committed):**
- `.claude/agents/backend-agent.md` — Tailored to your backend stack
- `.claude/agents/frontend-agent.md` — Tailored to your frontend stack
- `.claude/rules/backend-conventions.md` — Language-specific coding conventions
- `.claude/rules/security-patterns.md` — Language-specific security patterns
- `settings.json` — permissions configuration

**Written to .geniro/project/ (committed — NOT gitignored):**
- `.geniro/project/review/bugs-criteria.md` — Stack-specific bug detection patterns
- `.geniro/project/review/security-criteria.md` — Stack-specific security checks
- `.geniro/project/review/tests-criteria.md` — Stack-specific test quality checks
- `.geniro/project/review/architecture-criteria.md` — Stack-specific architecture checks
- `.geniro/project/review/guidelines-criteria.md` — Stack-specific coding guidelines

**Not copied (provided globally by the plugin):**
- 11 universal agents — the plugin provides them directly. Only `backend-agent.md` and `frontend-agent.md` are written to the project (tailored per-project).
- All skills — the plugin provides them directly.
- All hooks — the plugin provides them via `hooks.json`. Hook scripts run from `${CLAUDE_PLUGIN_ROOT}/hooks/`.

**Written to .geniro/ (git-ignored, not committed):**
- `.geniro/planning/` — created empty, populated during /geniro:implement
- `.geniro/debug/` — created empty, populated during /geniro:debug
- `.geniro/knowledge/` — created empty, populated during /geniro:learnings

**Additional files written in standalone mode ($DEPLOY_MODE = standalone):**
- `.claude/agents/*.md` — All 11 universal agents (in addition to the 2 tailored ones)
- `.claude/skills/*/SKILL.md` — All skill files (with `geniro:` prefix removed from names)
- `.claude/skills/review/*-criteria.md` — Review criteria (instead of `.geniro/project/review/`)
- `.claude/hooks/*.sh`, `.claude/hooks/*.js` — All hook scripts
- `settings.json` includes hook entries (not just permissions)

In standalone mode, `.geniro/project/` is NOT created — review criteria live in `.claude/skills/review/`.

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

**Fallback:** If no language or framework can be detected (empty repo, documentation-only, or unsupported language), use the `AskUserQuestion` tool (do NOT output options as plain text) to ask "I couldn't auto-detect your tech stack. What language and framework does this project use?" If the user says it's a new/empty project, proceed with `settings.json` only (all agents, hooks, and skills are provided by the plugin), skip generated files.

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
- `.claude/` directory (existing plugin files)
- `CLAUDE.md` (existing project instructions — preserve as-is, do not overwrite)
- `.cursorrules`, `.windsurfrules` (offer to port)
- `.github/copilot-instructions.md`, `.copilot/` (Copilot rules — offer to port)
- `.continue/`, `.cody/` (Continue / Cody configs — read for project rules)
- `AGENTS.md`, `.agents.md` (generic agent instructions — read for context)
- `.editorconfig`, `.prettierrc`, `eslint.config.*`

Route based on `$INSTALL_MODE` detected in Phase 0:

- **`fresh`**: No existing plugin files. Continue to Phase 2 (User Interview) as normal.
- **`update`**: Previous successful install detected (`.geniro/.geniro-state.json` exists). Skip to the **Re-Running Setup (Smart Update)** flow below. Do NOT run Phases 2-3 unless the user chooses Fresh Install.
- **`legacy-update`**: Plugin files exist but no `.geniro/.geniro-state.json` (installed before state tracking). Skip to **Re-Running Setup (Smart Update)** flow — it handles the "no snapshot" case with header-level heuristics.

If `.claude/` exists but contains only non-template files (no recognizable plugin agents/skills/hooks AND no `.geniro/.geniro-state.json`), run the **Existing File Conflict Resolution** process below before continuing to Phase 2.

If `.claude/` does NOT exist but `CLAUDE.md` exists at the project root, this is a standalone instructions file (common — many projects have a hand-written CLAUDE.md). **Leave it untouched.** The rest of `.claude/` is installed normally as a fresh setup.

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

☐ Linear (issue tracking — pass issue IDs to /geniro:implement)
```

### 2.5 Component Summary

All agents, skills, and hooks are provided globally by the plugin — no tier selection is needed.

**What setup writes to the project:**
- `backend-agent.md` and `frontend-agent.md` — tailored to the detected stack
- `rules/backend-conventions.md` and `rules/security-patterns.md` — tailored to the detected stack
- 5 review criteria files in `.geniro/project/review/` — generated per-project
- `settings.json` — permissions only (no hook entries)

**If no frontend framework was detected**, `frontend-agent.md` is skipped (not created).

All 11 universal agents, all hooks, and all skills are available automatically via the plugin — they do not need to be installed into the project.

## Phase 3: Generate Files

### 3.1 Copy Template Files

**If `$DEPLOY_MODE` is `standalone`:** skip this section entirely and jump to **Standalone Mode Copy** below.

Copy template files to `.claude/`. **Only write files that exist in the template — never delete existing files that aren't part of the template.** If the user has custom agents, skills, hooks, or rules they created themselves, those must be preserved untouched.

**Tailored agents** (copied from template, then customized for the project's stack):
- `backend-agent.md`, `frontend-agent.md`

Universal agents (`architect-agent.md`, `skeptic-agent.md`, `reviewer-agent.md`, `refactor-agent.md`, `debugger-agent.md`, `security-agent.md`, `doc-agent.md`, `devops-agent.md`, `knowledge-agent.md`, `knowledge-retrieval-agent.md`, `meta-agent.md`) are provided globally by the plugin — do NOT copy them.

**Hooks** — do NOT copy hooks. They are provided globally by the plugin via `hooks.json` in `plugin.json`. Hook scripts run from `${CLAUDE_PLUGIN_ROOT}/hooks/`. Copying hooks to `.claude/hooks/` would cause them to fire twice (different paths bypass deduplication).

**settings.json** — If no existing `.claude/settings.json`, create it with default permissions only. If one already exists, preserve it. The plugin provides `statusLine` and hook configuration globally via its own `settings.json` and `hooks.json` — do NOT copy `statusLine` or hook entries to the project's `settings.json`.

**Review criteria** — The 5 review criteria files are written to `.geniro/project/review/`, generated in Phase 3.5 with stack-specific content. This directory is committed (excluded from the `.geniro/` gitignore via `!.geniro/project/`).

Use shell `cp` via the Bash tool to copy each file individually — do NOT use `rm -rf` on entire directories or `cp -r` on directories, as that would overwrite user-created files. If `.claude/agents/` already contains files not in the template (user-created agents), they must remain untouched after this step.

`$TEMPLATE_DIR` is `${CLAUDE_PLUGIN_ROOT}` — the plugin installation path. If an explicit argument was provided, it's that path instead.

```bash
# Create target directories in the user's project
mkdir -p .claude/agents
mkdir -p .claude/rules
mkdir -p .geniro/project/review

# Tailored agents only (universal agents are provided by the plugin)
cp "$TEMPLATE_DIR/agents/backend-agent.md" .claude/agents/
cp "$TEMPLATE_DIR/agents/frontend-agent.md" .claude/agents/

# Skills and hooks are NOT copied — they are provided globally by the plugin.
# Only .geniro/project/review/ is created for per-project review criteria (Phase 3.5).
```

#### StatusLine Configuration

Configure the geniro status line in `.claude/settings.local.json` (project-level). This overrides any user-level statusLine (e.g., from GSD) so the geniro status line shows in geniro-configured projects.

**IMPORTANT:** `${CLAUDE_PLUGIN_ROOT}` is only expanded in plugin-provided files — it does NOT work in project `settings.local.json`. You must resolve the absolute path at setup time.

1. Resolve the plugin install path using Bash:
```bash
PLUGIN_PATH=$(python3 -c "import json; d=json.load(open('$HOME/.claude/plugins/installed_plugins.json')); p=d['plugins'].get('geniro-claude-plugin@geniro-claude-harness',[]); print(p[0]['installPath'] if p else '')" 2>/dev/null)
```

2. If `$PLUGIN_PATH` is empty, fall back to `${CLAUDE_PLUGIN_ROOT}` (available in skill context):
```bash
PLUGIN_PATH="${CLAUDE_PLUGIN_ROOT}"
```

3. Write the statusLine to `.claude/settings.local.json` using the resolved absolute path:
   - If `.claude/settings.local.json` does not exist, create it with `statusLine` only.
   - If it already exists: merge the `statusLine` key (preserve all existing keys).
   - If it already has a geniro `statusLine` (contains `geniro-statusline`), update the path (version may have changed).
   - The command must be: `node "<absolute_plugin_path>/hooks/geniro-statusline.js"`

#### Legacy Cleanup

If the project has agents, hooks, or skills from a previous install, remove them. These are now provided globally by the plugin.

```bash
# Remove previously-copied universal agents (keep tailored backend/frontend)
for agent in architect-agent skeptic-agent reviewer-agent refactor-agent debugger-agent security-agent doc-agent devops-agent knowledge-agent knowledge-retrieval-agent meta-agent; do
  rm -f ".claude/agents/${agent}.md"
done

# Remove previously-copied hooks (now provided by plugin via hooks.json)
rm -rf .claude/hooks/

# Remove previously-copied skill files (now provided by plugin)
for skill_dir in plan implement follow-up refactor deep-simplify debug learnings onboard features investigate; do
  rm -rf ".claude/skills/$skill_dir"
done
rm -f .claude/skills/review/SKILL.md

# Remove old review criteria location (now in .geniro/project/review/)
rm -rf .claude/skills/review/
```

This cleanup is safe — universal agents are identical to plugin versions, hooks are provided by the plugin, and skill files are global. User-created files in `.claude/agents/` (not in the list above) are preserved. Tailored agents (`backend-agent.md`, `frontend-agent.md`) are preserved.

**In standalone mode (`$DEPLOY_MODE = standalone`), skip the Legacy Cleanup above** — universal agents, hooks, and skills ARE supposed to be in the project.

#### Standalone Mode Copy ($DEPLOY_MODE = standalone)

If `$DEPLOY_MODE` is `standalone`, copy ALL plugin files to the project:

```bash
# Create target directories
mkdir -p .claude/agents .claude/rules .claude/hooks .claude/skills/review

# Copy ALL agents (universal + tailored templates)
for agent in "$TEMPLATE_DIR"/agents/*.md; do
  cp "$agent" .claude/agents/
done

# Copy ALL hook scripts
for hook in "$TEMPLATE_DIR"/hooks/*.sh "$TEMPLATE_DIR"/hooks/*.js; do
  [ -f "$hook" ] && cp "$hook" .claude/hooks/
done

# Copy ALL skills EXCEPT setup, update, cleanup (these only work with plugin installed)
for skill_dir in "$TEMPLATE_DIR"/skills/*/; do
  skill_name=$(basename "$skill_dir")
  [[ "$skill_name" == "setup" || "$skill_name" == "update" || "$skill_name" == "cleanup" ]] && continue
  mkdir -p ".claude/skills/$skill_name"
  cp -r "$skill_dir"* ".claude/skills/$skill_name/" 2>/dev/null
done

# Copy rules
for rule in "$TEMPLATE_DIR"/rules/*.md; do
  [ -f "$rule" ] && cp "$rule" .claude/rules/
done
```

**Path rewriting in copied files:**

After copying, rewrite all `${CLAUDE_PLUGIN_ROOT}` and plugin-specific references in the copied files:

```bash
# Rewrite ${CLAUDE_PLUGIN_ROOT}/hooks/ → .claude/hooks/ in all copied .md files
find .claude/ -name "*.md" -exec sed -i '' 's|\${CLAUDE_PLUGIN_ROOT}/hooks/|.claude/hooks/|g' {} +

# Rewrite ${CLAUDE_PLUGIN_ROOT}/agents/ → .claude/agents/
find .claude/ -name "*.md" -exec sed -i '' 's|\${CLAUDE_PLUGIN_ROOT}/agents/|.claude/agents/|g' {} +

# Rewrite ${CLAUDE_PLUGIN_ROOT} (remaining references) → .claude
find .claude/ -name "*.md" -exec sed -i '' 's|\${CLAUDE_PLUGIN_ROOT}|.claude|g' {} +

# Rewrite skill names in frontmatter: "geniro:skillname" → "skillname"
find .claude/skills/ -name "SKILL.md" -exec sed -i '' 's/name: geniro:/name: /g' {} +

# Rewrite cross-skill references: skill="geniro:xxx" → skill="xxx"
find .claude/ -name "*.md" -exec sed -i '' 's/skill="geniro:/skill="/g' {} +
find .claude/ -name "*.md" -exec sed -i '' "s/skill='geniro:/skill='/g" {} +

# Rewrite /geniro: skill invocations in prose text
find .claude/ -name "*.md" -exec sed -i '' 's|/geniro:|/|g' {} +

# Rewrite .geniro/project/review/ → .claude/skills/review/ (criteria paths)
find .claude/ -name "*.md" -exec sed -i '' 's|\.geniro/project/review/|.claude/skills/review/|g' {} +
```

**Write hooks into settings.json:**

In standalone mode, hooks must be registered in `.claude/settings.json` (not `hooks.json`). Read `$TEMPLATE_DIR/hooks/hooks.json`, extract all hook entries, rewrite their command paths from `${CLAUDE_PLUGIN_ROOT}/hooks/` to `.claude/hooks/`, and merge them into `.claude/settings.json` under the `"hooks"` key.

**StatusLine in standalone mode:**

In standalone mode, the statusLine script is at `.claude/hooks/geniro-statusline.js`. Write to `settings.local.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "node \".claude/hooks/geniro-statusline.js\""
  }
}
```
This uses a project-relative path (no absolute path or `${CLAUDE_PLUGIN_ROOT}` needed).

**CLAUDE.md generation in standalone mode:**

When generating the project's CLAUDE.md (which reads `CLAUDE.md.example` as a structural guide), use `.claude/hooks/backpressure.sh` and `.claude/agents/` instead of `${CLAUDE_PLUGIN_ROOT}/hooks/` and `${CLAUDE_PLUGIN_ROOT}/agents/`. The generated CLAUDE.md is at the project root (not inside `.claude/`), so the path rewriting sed commands do not reach it — the AI must use the correct paths during generation.

### 3.1.1 Save Template Snapshot

**If `$DEPLOY_MODE` is `standalone`:** skip this section. The template snapshot is used by Smart Update to compare template changes, which relies on `$TEMPLATE_DIR` (the plugin). In standalone mode, updates re-copy all files directly — no snapshot comparison needed.

Save a copy of the raw template files (before any tailoring) to `.geniro/template-snapshot/`. This snapshot enables future `/geniro:setup` re-runs to distinguish template structural changes from project-specific tailoring.

```bash
# Save template baseline for future 3-way comparison
rm -rf .geniro/template-snapshot/
mkdir -p .geniro/template-snapshot/
for dir in agents hooks rules skills; do
  if [[ -d "$TEMPLATE_DIR/$dir" ]]; then
    cp -r "$TEMPLATE_DIR/$dir" .geniro/template-snapshot/
  fi
done
```

This snapshot is git-ignored (under `.geniro/`) and is refreshed on every `/geniro:setup` run. On future re-runs, comparing this snapshot against the new template reveals what changed in the template itself — independent of any AI tailoring or user modifications.

Files like `backend-agent.md`, `frontend-agent.md`, `rules/backend-conventions.md`, and `rules/security-patterns.md` are also copied via `cp` here, then tailored via Read+Edit in Phases 3.2-3.4.

For `settings.json`: if no existing file, create it with default permissions only. If one already exists, preserve it. Do NOT add `statusLine` or hook entries — these are plugin-global settings.

**Note:** Do NOT copy universal agents, skills, or hooks from the template to the project. These are provided globally by the plugin. Only write to the project: tailored agents (backend/frontend), tailored rules, review criteria files, and `settings.json` (permissions only).

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
4. **Remove the setup note** (the blockquote about `/geniro:setup` replacing placeholders)
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
4. **Remove the setup note** (the blockquote about `/geniro:setup` replacing placeholders)
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
- Remove the setup note (the blockquote about `/geniro:setup`)
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

**Output path:**
- If `$DEPLOY_MODE` is `global`: write to `.geniro/project/review/` (committed via gitignore exception)
- If `$DEPLOY_MODE` is `standalone`: write to `.claude/skills/review/` (committed with all other `.claude/` files)

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
2. Note that `/geniro:implement` auto-detects Linear issue IDs and URLs

## Phase 4: Verify, Track & Report

### 4.1 Verify Generated Files

**Formatting checks:**
- All generated files are valid markdown (no broken formatting, unclosed code blocks)
- No `{{placeholder}}` or `{{PLACEHOLDER}}` patterns remain in ANY generated file
- `settings.json` is valid JSON
- All agent frontmatter has required fields (name, description, tools, maxTurns)

**Read `skills/setup/verification-checks.md` using the Read tool** and run all verification checks against the generated files.

### 4.2 Independent Verification Agent

After the orchestrator's own checks (4.1), spawn a **separate subagent** for an independent, comprehensive review of all generated files. A fresh agent catches issues the orchestrator is blind to — it didn't generate the files, so it has no anchoring bias.

**Spawn the verification agent:**

```
Agent(prompt="""
You are verifying a freshly generated geniro plugin. Your job: find every
residual issue the setup process missed. You did NOT generate these files — review
them with fresh eyes.

DETECTED STACK: [language, framework, ORM, test runner, linter]
PROJECT ROOT: [path]
DEPLOY MODE: [global or standalone]

## What to check

Read every file in `.claude/` (agents, rules, settings.json) and review criteria directory
(`.geniro/project/review/` in global mode, `.claude/skills/review/` in standalone mode) and verify:

### 1. Template Variable Residue
Grep ALL files in `.claude/` for these patterns:
- `{{` and `}}` — unreplaced template variables
- `$TEMPLATE_DIR`, `$PROJECT_KNOWLEDGE`, `$BOOTSTRAPPED` — internal setup variables leaked
- `PLACEHOLDER`, `TODO`, `FIXME` — unfinished markers
- `customize this`, `replace with`, `fill in` — template instructions left behind

### 2. Path Correctness
For every file path referenced inside agent prompts and rules:
- Verify the referenced file actually exists (Glob or ls)
- Check relative vs absolute paths are appropriate
- Verify review criteria references exist at the correct path for the deploy mode
- **Global mode:** Verify NO `.claude/hooks/` directory exists (hooks are provided by the plugin)
- **Standalone mode:** Verify `.claude/hooks/` directory EXISTS and contains hook scripts

### 3. Cross-File Consistency
- Agent `allowed-tools` in frontmatter match what the agent's instructions reference
- Review criteria files referenced by `/geniro:review` skill actually exist
- Plan criteria file referenced by `/geniro:plan` skill actually exists
- **Global mode:** Verify `settings.json` does NOT contain hook entries (hooks are provided by the plugin via `hooks.json`)
- **Standalone mode:** Verify `settings.json` DOES contain hook entries pointing to `.claude/hooks/`

### 4. Stack Contamination (generated files only)
For backend-agent.md, frontend-agent.md, rules/*.md, and review criteria (`.geniro/project/review/*-criteria.md` in global mode, `.claude/skills/review/*-criteria.md` in standalone mode):
- Verify ONLY the detected language/framework appears
- No wrong-language commands (e.g., `npm` in a Python project)
- No wrong-language code blocks (e.g., ```typescript in a Python project)
- No multi-framework lists like "(Django, Rails, FastAPI)" — file must be specific

### 5. Frontmatter Integrity
For every `.md` file in `.claude/agents/` (in global mode, skills are provided by the plugin; in standalone mode, also check `.claude/skills/`):
- Has valid YAML frontmatter (opens and closes with `---`)
- Required fields present: `name`, `description` (agents also need `tools`)
- No duplicate frontmatter keys
- `model` field (if present) uses a valid value

### 6. Hook Configuration
- **Global mode:** Verify `.claude/hooks/` does NOT exist (legacy cleanup should have removed it) and `settings.json` does NOT contain hook command paths
- **Standalone mode:** Verify `.claude/hooks/` EXISTS with all hook scripts and `settings.json` contains hook entries pointing to `.claude/hooks/`

### 7. settings.json Validity
- Valid JSON (no trailing commas, no comments)
- All tool permission entries reference real tools
- **Global mode:** No hook entries (hooks are provided by the plugin)
- **Standalone mode:** Hook entries present and pointing to `.claude/hooks/`

## Output Format

Return a structured report:

PASSED CHECKS: [list of check categories that passed cleanly]

ISSUES FOUND:
- [CRITICAL] <file>: <description> — must fix before committing
- [WARNING] <file>: <description> — should fix, not blocking
- [INFO] <file>: <description> — minor, optional fix

If no issues found, return: "ALL CHECKS PASSED — plugin is ready to commit."
""", description="Verify setup output")
```

**Route based on results:**
- **ALL PASSED** → proceed to 4.3
- **CRITICAL issues** → fix them immediately (Edit tool), then re-verify the specific files
- **WARNING issues** → fix if straightforward, otherwise note in the summary report for the user
- **Max 2 fix-verify iterations** — if issues persist after 2 rounds, present remaining issues to user in the summary report

### 4.3 Ensure Runtime Directories are Git-Ignored

**If `$DEPLOY_MODE` is `global`:** add both `.geniro/` and `!.geniro/project/` to `.gitignore` (review criteria are in `.geniro/project/review/`):

```bash
# Add to root .gitignore if not already present
grep -q "^\.geniro/$" .gitignore 2>/dev/null || echo ".geniro/" >> .gitignore
# Add exception for .geniro/project/ (committed review criteria, etc.)
grep -q "^\!\.geniro/project/$" .gitignore 2>/dev/null || echo "!.geniro/project/" >> .gitignore
```

**If `$DEPLOY_MODE` is `standalone`:** add only `.geniro/` to `.gitignore` (no `!.geniro/project/` exception needed — review criteria are in `.claude/skills/review/`):

```bash
grep -q "^\.geniro/$" .gitignore 2>/dev/null || echo ".geniro/" >> .gitignore
```

Do NOT create `.claude/.gitignore` — all ignore rules go in the project root.

### 4.4 Write Plugin State File

Write `.geniro/.geniro-state.json` to track the installation state for future re-runs. This file is git-ignored (covered by the `.geniro/` entry already in `.gitignore`).

Use the Bash tool to get the template commit hash (if `$TEMPLATE_DIR` is a git repo or was bootstrapped from one):

```bash
# Get template commit hash if available
TEMPLATE_COMMIT=$(cd "$TEMPLATE_DIR" && git rev-parse HEAD 2>/dev/null || echo "unknown")
```

Write the state file:

```json
{
  "plugin_version": "$TEMPLATE_COMMIT",
  "installed_at": "ISO-8601 timestamp",
  "install_mode": "fresh|update|legacy-update",
  "deploy_mode": "global|standalone",
  "files": {
    "verbatim": [
      "settings.json",
      ...all files copied directly from template without modification
    ],
    "tailored": [
      "agents/backend-agent.md",
      "agents/frontend-agent.md",
      "rules/backend-conventions.md",
      "rules/security-patterns.md",
      ".geniro/project/review/bugs-criteria.md",
      ".geniro/project/review/security-criteria.md",
      ".geniro/project/review/tests-criteria.md",
      ".geniro/project/review/architecture-criteria.md",
      ".geniro/project/review/guidelines-criteria.md",
      ...all files that were AI-generated or tailored
    ],
    "user_created": [
      ...any files in .claude/ that are NOT from the template
    ]
  }
}
```

Populate the lists from the actual files installed during Phase 3. The categories are:
- **verbatim**: Files copied directly from template without AI modification (settings.json)
- **tailored**: Files that were copied then AI-edited (backend-agent, frontend-agent, rules files) or generated from scratch (review criteria files)
- **user_created**: Files that existed in `.claude/` before setup and are not part of the template

In standalone mode (`$DEPLOY_MODE = standalone`), the `files.verbatim` list is much larger — it includes all universal agents, all skill files, and all hook scripts in addition to `settings.json`. Also, review criteria paths in the `tailored` list use `.claude/skills/review/*-criteria.md` instead of `.geniro/project/review/*-criteria.md`.

Ensure `.geniro/.geniro-state.json` is git-ignored. The `.geniro/` entry added in Phase 4.3 already covers this — no separate gitignore entry is needed.

### 4.5 Summary Report

Present to the user:

```
Setup complete! Here's what was generated:

.claude/
  agents/     (2 tailored agents)
  rules/      (N rule files)
  settings.json

.geniro/project/
  review/     (5 review criteria files)

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

3. Commit: git add .claude/ .geniro/project/ && git commit -m 'chore: add geniro plugin'
4. Start using: /geniro:implement, /geniro:review, /geniro:refactor
```

**Standalone mode summary (if $DEPLOY_MODE = standalone):**

```
Setup complete! Here's what was generated:

.claude/
  agents/     (13 agents — 11 universal + 2 tailored)
  skills/     (all skills + 5 review criteria)
  hooks/      (all hook scripts)
  rules/      (N rule files)
  settings.json (permissions + hooks)

Mode: Standalone (self-contained repo)
Tech Stack: [detected]

Next steps:
1. Uninstall plugin to avoid hook duplication:
   claude plugin uninstall geniro-claude-plugin@geniro-claude-harness
2. Commit: git add .claude/ && git commit -m 'chore: add geniro plugin (standalone)'
3. Start using: /implement, /review, /refactor
4. To update later: reinstall plugin, run /geniro:update, then uninstall again
```

## Re-Running Setup (Smart Update)

If `/geniro:setup` detects `$INSTALL_MODE` is `update` or `legacy-update`, it enters update mode instead of the fresh install pipeline.

**Standalone mode updates:**

If `$DEPLOY_MODE` (from `.geniro/.geniro-state.json`) is `standalone`, skip Steps 1-3 below. Instead, re-run Phase 3.1 (Standalone Mode Copy) directly — copy ALL template files again with path rewriting and hook registration. Then skip to Step 3A.5 (Update state file and refresh template snapshot) and Step 3A.6 (Post-update verification). The detailed per-file diff is unnecessary in standalone mode because all files are re-copied from the template.

### Step 1: Analyze Changes (before asking the user anything — global mode only)

Do NOT ask the user what they want to do yet. First, gather data so the user can make an informed choice.

#### 1a: Build File Inventory

Compare the template against the installed plugin:

```bash
# List template files (relative paths)
(cd "$TEMPLATE_DIR" && find agents rules -type f 2>/dev/null)
# List installed files (relative paths)
(cd .claude && find agents rules -type f 2>/dev/null)
```

Additionally, explicitly check `settings.json` since it lives at the template root (not inside agents/rules):
```bash
# settings.json is at template root, not in subdirectories — check separately
if [[ -f "$TEMPLATE_DIR/settings.json" ]]; then
  echo "settings.json"
fi
```
Classify `settings.json` as **verbatim** for diff purposes, but apply using the **merge strategy** (preserve user-added entries).

Classify each file using `$GENIRO_STATE` (if available from a previous install) or by matching filenames against the template:

| Category | Detection | Update Strategy |
|---|---|---|
| **Verbatim** (in `$GENIRO_STATE.files.verbatim` or filename matches template AND file was not tailored) | Direct content comparison against template | Auto-apply if template changed |
| **Tailored** (in `$GENIRO_STATE.files.tailored` or is one of: backend-agent, frontend-agent, rules/*, .geniro/project/review/*-criteria.md) | Compare ONLY template structural sections — ignore LLM-generated project content | Flag structural changes only |
| **User-created** (in `$GENIRO_STATE.files.user_created` or exists in .claude/ but NOT in template) | Skip entirely | Never touch |
| **Template-only** (exists in template but NOT in .claude/) | New file | Offer to install |

**Legacy-update classification fallback** (when `$GENIRO_STATE` is absent):

Without the state file, classify files by explicit enumeration — do NOT rely on LLM judgment alone:

| Always Tailored (never auto-overwrite) | Always Verbatim (safe to auto-apply) | Should be removed (legacy — now provided by plugin) |
|---|---|---|
| `agents/backend-agent.md` | `settings.json` | All universal agents (`architect-agent.md`, `skeptic-agent.md`, `reviewer-agent.md`, `refactor-agent.md`, `debugger-agent.md`, `security-agent.md`, `doc-agent.md`, `devops-agent.md`, `knowledge-agent.md`, `knowledge-retrieval-agent.md`, `meta-agent.md`) |
| `agents/frontend-agent.md` | | All hooks (entire `hooks/` directory) |
| `rules/backend-conventions.md` | | |
| `rules/security-patterns.md` | | |
| `.geniro/project/review/bugs-criteria.md` | | |
| `.geniro/project/review/security-criteria.md` | | |
| `.geniro/project/review/tests-criteria.md` | | |
| `.geniro/project/review/architecture-criteria.md` | | |
| `.geniro/project/review/guidelines-criteria.md` | | |

Any file in `.claude/` that does NOT appear in either column AND does NOT exist in the template directory → classify as **user-created** (never touch).

Any file in `.claude/` that does NOT appear in either column BUT DOES exist in the template directory → classify as **verbatim** (safe to auto-apply).

#### 1b: Diff Verbatim Files

For files categorized as **verbatim**: use `cmp` via Bash to quickly identify which actually changed, then only read the changed ones:

```bash
# Quick binary comparison — only shows files that differ
for f in $VERBATIM_FILES; do
  if [[ -f "$TEMPLATE_DIR/$f" ]] && [[ -f ".claude/$f" ]] && ! cmp -s "$TEMPLATE_DIR/$f" ".claude/$f"; then
    echo "CHANGED: $f"
  fi
done
```

For each changed verbatim file, read both versions to summarize the differences (new sections, bug fixes, restructured phases).

#### 1c: Diff Tailored Files (structural changes only)

For files categorized as **tailored**, do NOT compare the installed file against the template — that would just show LLM-generated project-specific content (Django patterns, domain rules, etc.), which is expected and not actionable.

Instead, detect **template structural changes** using one of these strategies:

**If template snapshot exists** (`.geniro/template-snapshot/`):
Compare the **template snapshot** (what the template looked like when setup last ran) against the **current template** (what the template looks like now). This reveals what changed in the template itself — new sections, restructured phases, added constraints — independent of any project-specific tailoring.

```bash
# Compare old template baseline vs new template for tailored files
for f in $TAILORED_FILES; do
  if [[ -f ".geniro/template-snapshot/$f" ]] && [[ -f "$TEMPLATE_DIR/$f" ]]; then
    if ! cmp -s ".geniro/template-snapshot/$f" "$TEMPLATE_DIR/$f"; then
      echo "TEMPLATE STRUCTURAL CHANGE: $f"
    fi
  fi
done
```

For files with template structural changes, spawn a subagent per file (all in parallel) to identify the specific structural differences:

```
Agent(prompt="""
Compare TWO versions of the same template file (NOT the project's installed version):
- OLD template: .geniro/template-snapshot/{file}
- NEW template: $TEMPLATE_DIR/{file}

Read both files. Identify structural changes — sections added, removed, restructured,
new constraints, new phases, changed instructions. Ignore placeholder values
({{FRAMEWORK}}, {{ORM}}, etc.) — those are filled during setup and are not structural.

Report each structural change:
- SECTION: which section changed
- CHANGE TYPE: added / removed / restructured / constraint-added
- DESCRIPTION: what specifically changed
- IMPACT: how this affects a project that already has a tailored version of this file

Do NOT suggest how to apply these changes — just identify them.
""", description="Diff template structural changes: {file}")
```

**If no template snapshot exists** (legacy install):
Compare ALL section headers (`##` and `###` lines) between the template file and the installed file, AND check for significant line-count deltas (>10%). New or changed headers indicate structural additions; large size changes indicate substantial content updates even when headers stay the same. This heuristic catches most structural changes — new phases, new subsections, and substantive content rewrites.

```bash
# Extract ALL section headers (## and ###) from both files
grep -n "^###\?\s" "$TEMPLATE_DIR/$file" > /tmp/template_headers.txt
grep -n "^###\?\s" ".claude/$file" > /tmp/installed_headers.txt
diff /tmp/template_headers.txt /tmp/installed_headers.txt

# Also check for significant content changes: line count delta > 10% suggests structural change
TEMPLATE_LINES=$(wc -l < "$TEMPLATE_DIR/$file")
INSTALLED_LINES=$(wc -l < ".claude/$file")
DELTA=$(( TEMPLATE_LINES - INSTALLED_LINES ))
DELTA=${DELTA#-}  # absolute value
THRESHOLD=$(( TEMPLATE_LINES / 10 ))
if [[ $DELTA -gt $THRESHOLD ]]; then
  echo "SIGNIFICANT SIZE CHANGE: $file ($INSTALLED_LINES → $TEMPLATE_LINES lines)"
fi
```

For **review criteria files** (`.geniro/project/review/*-criteria.md`): these are fully generated (not edited from template). On update, they should be **regenerated** using the current template criteria as reference + current codebase analysis. Flag them as "regenerate recommended" rather than diffing.

#### 1d: Identify New Files

```bash
for f in $(cd "$TEMPLATE_DIR" && find agents rules -type f 2>/dev/null); do
  if [[ ! -f ".claude/$f" ]]; then
    echo "NEW: $f"
  fi
done
```

#### 1e: Detect Removed Template Files

Check for files in `.claude/` that were part of the previous template but have been removed from the current template:

```bash
# Files in .claude/ that match template structure but no longer exist in template
for f in $(cd .claude && find agents rules -type f 2>/dev/null); do
  if [[ ! -f "$TEMPLATE_DIR/$f" ]]; then
    # Check if this was a template file (not user-created)
    if [[ -n "$GENIRO_STATE" ]] && (echo "$GENIRO_STATE" | grep -q "$f"); then
      echo "REMOVED FROM TEMPLATE: $f"
    fi
  fi
done
```

For legacy installs without `$GENIRO_STATE`: only flag files whose names match known template patterns (e.g., filenames that appear in the legacy classification table from Step 1a). Do NOT flag files that could be user-created.

Present removed files in the Step 2 analysis as a separate category:
```
### Removed from template (N files)
These files existed in the previous template but have been removed:
| File | Action |
|------|--------|
| agents/old-agent.md | Safe to delete — no longer maintained in template |

→ Recommended: review and delete if no longer needed
```

### Step 2: Present Analysis & Suggest Path

Present the findings to the user. Show what changed, categorized by action needed:

```
## Plugin Update Analysis

### Verbatim files with template updates (N files)
These files are direct copies from the template and have been updated upstream:
| File | Change Summary |
|------|---------------|
| agents/reviewer-agent.md | +15 lines: new confidence scoring in Phase 2 |
| skills/implement/SKILL.md | Restructured: new Phase 5 (Simplify) added |

→ Recommended: auto-apply all (template is authoritative for these files)

### Tailored files with template structural changes (N files)
These files were customized for your project, but the template structure has changed:
| File | Structural Change | Your Content |
|------|------------------|--------------|
| agents/backend-agent.md | New "Quality Checklist" section added | Django patterns preserved |

→ Recommended: apply structural changes, preserve your project-specific content

### Review criteria — regeneration recommended (N files)
These were generated for your stack and should be regenerated from the updated template:
| File | Reason |
|------|--------|
| .geniro/project/review/bugs-criteria.md | Template criteria updated with new checks |

→ Recommended: regenerate using current codebase analysis

### New template files (N files)
These are new in the template and not yet installed:
| File | Purpose |
|------|---------|
| agents/knowledge-retrieval-agent.md | RAG-based knowledge retrieval |

→ Recommended: install all

### Removed from template (N files)
These files existed in the previous template but have been removed:
| File | Action |
|------|--------|
| agents/old-agent.md | Safe to delete — no longer maintained in template |

→ Recommended: review and delete if no longer needed

### Your project-only files (N files) — won't be touched
- agents/custom-domain-agent.md

### No changes (N files)
- agents/architect-agent.md, agents/skeptic-agent.md, ...
```

Then use the `AskUserQuestion` tool (do NOT output options as plain text) to present the options:

```
How would you like to proceed?

A) Apply all recommended changes (auto-apply verbatim updates, merge structural 
   changes into tailored files, regenerate criteria, install new files)
B) Let me review each category individually
C) Apply ALL template files — overwrite every template file with latest version,
   preserve project-specific content in tailored files
D) Fresh install — reinstall everything from template, port back my project content
E) Cancel
```

### Step 3A: Apply Recommended Changes

If user chose A:

**3A.1: Auto-apply verbatim file updates**

For each changed verbatim file, copy the template version directly. Skip `settings.json` in this loop — it is handled by Step 3A.1b instead.
```bash
cp "$TEMPLATE_DIR/$rel" ".claude/$rel"
```

Note: Universal agents and hooks are no longer copied to the project (they are provided by the plugin). Verbatim files in the project are limited to `settings.json` and any other non-agent, non-hook template files.

**3A.1b: Merge settings.json updates**

If the inventory flagged `settings.json` as changed, merge template **permission entries only** into the installed version — preserve user-added permissions; add new template entries that are missing. Do NOT copy `statusLine` or hook entries to the project (these are plugin-global settings).

Spawn a subagent:
```
Agent(prompt="""
Merge template settings.json updates into the project's installed version.

TEMPLATE: $TEMPLATE_DIR/settings.json
INSTALLED: .claude/settings.json

Read both files. For each permission entry in the template:
- If it exists in the installed file with the same value → skip
- If it exists in the installed file with a different value → keep the installed value (user customization)
- If it does NOT exist in the installed file → add it (new template entry)

IMPORTANT: Only merge permission entries. Do NOT copy statusLine or hook entries to the
project's settings.json — these are plugin-global settings provided by the plugin's own
settings.json, not project settings. If the installed file has statusLine or hook entries
from a previous install, remove them.

Use the Edit tool to apply changes. Output what was added/changed.
""", description="Merge settings.json updates")
```

**3A.2: Merge structural changes into tailored files**

For each tailored file with template structural changes, spawn a subagent (all in parallel):

```
Agent(prompt="""
Apply structural template changes to a project-tailored file.

TEMPLATE (new version): $TEMPLATE_DIR/{file}
INSTALLED (project-tailored version): .claude/{file}
STRUCTURAL CHANGES IDENTIFIED:
{list of structural changes from Step 1c}

Your task:
1. Read the installed file (the project's tailored version)
2. Read the new template file
3. For each structural change identified:
   - If it's a NEW section: add it to the installed file at the same relative position
     as in the template. Use the template's content as-is (with {{PLACEHOLDER}} values
     if the section has them — they will need tailoring).
   - If it's a RESTRUCTURED section: update the structure (headings, ordering, flow)
     while preserving any project-specific content within the section.
   - If it's a NEW CONSTRAINT: add it to the appropriate location.
   - If a section was REMOVED from the template: keep it in the installed file
     (it may contain project-specific content — flag for user review).
4. PRESERVE all project-specific content: domain context, framework patterns,
   custom commands, safety rules, real code examples from the project.
5. After applying changes, re-run the tailoring step for any newly added sections
   that contain {{PLACEHOLDER}} values — replace them with the project's actual
   detected values.

Use Edit tool to apply changes.
""", description="Merge structural changes: {file}")
```

Spawn one subagent per tailored file with structural changes, all in parallel.

**3A.3: Regenerate review criteria**

Re-run Phase 1 (Codebase Analysis) to detect the current stack, then re-run Phase 3.5 (Generate Review Criteria) using the new template criteria files.

**3A.4: Install new files**

```bash
for f in $NEW_FILES; do
  mkdir -p ".claude/$(dirname "$f")"
  cp "$TEMPLATE_DIR/$f" ".claude/$f"
done
```

**3A.5: Update state file and refresh template snapshot**

Update `.geniro/.geniro-state.json` with the new template version, timestamp, and updated file manifest.

Replace `.geniro/template-snapshot/` with the current template files:
```bash
rm -rf .geniro/template-snapshot/
mkdir -p .geniro/template-snapshot/
for dir in agents hooks rules skills; do
  if [[ -d "$TEMPLATE_DIR/$dir" ]]; then
    cp -r "$TEMPLATE_DIR/$dir" .geniro/template-snapshot/
  fi
done
```

**3A.6: Post-update verification**

Run the same verification checks as fresh install Phase 4 — but scoped to updated files only:

1. **Placeholder residue:** Grep all updated files for `{{`, `}}`, `$TEMPLATE_DIR`, `PLACEHOLDER`
2. **Hook configuration:** Global mode: verify `.claude/hooks/` does not exist and `settings.json` has no hook entries. Standalone mode: verify `.claude/hooks/` exists and `settings.json` has hook entries pointing to `.claude/hooks/`.
3. **settings.json validity:** Parse `.claude/settings.json` as JSON. Global: verify it contains only permissions. Standalone: verify it contains permissions AND hook entries.
4. **Cross-references:** For each updated file, verify paths it references still exist
5. **Frontmatter integrity:** For updated `.md` files in agents/, verify YAML frontmatter has required fields

If issues found: fix immediately (Edit tool for trivial fixes, subagent for complex ones). Max 1 fix round.

This step also applies after Steps 3B, 3C, and 3D — always verify after applying changes.

### Step 3B: Review Each Category

If user chose B, present each category one at a time using the `AskUserQuestion` tool (do NOT output options as plain text):

For **verbatim updates**: show each changed file's diff summary, ask accept/skip per file.
For **tailored structural changes**: show each structural change with context, ask accept/skip.
For **criteria regeneration**: ask per-file whether to regenerate.
For **new files**: ask which to install.

After applying selected changes, update state file and refresh template snapshot (same as 3A.5). Then run Step 3A.6 (Post-update verification) before proceeding.

### Step 3C: Apply ALL Template Files

If user chose C — apply every template file regardless of whether changes were detected. This is useful when the comparison missed changes or the user wants to ensure everything is in sync.

**3C.1: Overwrite all verbatim files**

Copy only tailored agents and rules from template. Universal agents, hooks, and skills are NOT copied — they are provided globally by the plugin:
```bash
# Copy only tailored agents (universal agents are provided by the plugin)
cp "$TEMPLATE_DIR/agents/backend-agent.md" .claude/agents/
cp "$TEMPLATE_DIR/agents/frontend-agent.md" .claude/agents/

# Copy rules
for f in $(find "$TEMPLATE_DIR/rules" -type f 2>/dev/null | sed "s|$TEMPLATE_DIR/||"); do
  mkdir -p ".claude/$(dirname "$f")"
  cp "$TEMPLATE_DIR/$f" ".claude/$f"
done
# settings.json is at template root — handle separately with merge strategy
```

**3C.2: Merge all tailored files**

For each tailored file (CLAUDE.md, settings.json, review criteria), spawn a merge agent (same template as Step 3A.2) — even if no structural changes were detected. The agent reads both template and installed versions, applies the template structure while preserving all project-specific content.

Spawn all merge agents in a single message.

**3C.3: Regenerate review criteria**

Re-run Phase 1 (Codebase Analysis) to detect the current stack, then re-run Phase 3.5 (Generate Review Criteria) using the new template criteria files.

**3C.4: Update state file and refresh template snapshot**

Same as Step 3A.5 — update `.geniro/.geniro-state.json` and refresh the template snapshot.

After applying changes, run Step 3A.6 (Post-update verification) before proceeding.

### Step 3D: Fresh Install

If user chose D, run the **Fresh Install (with Knowledge Preservation)** flow defined immediately below: backup → clean install → analyze backup → enrich → delete backup.

**DO NOT end the conversation or ask "anything else?" here.** After applying changes, run Step 3A.6 (Post-update verification) before proceeding. You MUST proceed to Phase 4 (Verify) and Phase 5 (Finalize) now.

### Fresh Install (with Knowledge Preservation)

If the user chose D (Fresh Install) in the Smart Update flow, or if this is a legacy install where the user prefers a clean slate:

The template is ALWAYS the base — but existing project-specific knowledge is not thrown away. The flow is: **backup → clean copy → analyze backup → enrich → delete backup.**

**Why backup-then-enrich instead of just wiping?** Existing files may contain project-specific patterns, domain rules, custom commands, safety constraints, or conventions that were added over time (by the user, by previous `/geniro:setup` runs, or by manual editing). A fresh install means "start from the latest template structure" — NOT "lose all project knowledge." The template provides the structure; the backup provides the project specificity.

#### 2A.1: Backup existing files

```bash
# Create backup in .geniro (git-ignored)
cp -r .claude/agents/ .geniro/_backup_agents/ 2>/dev/null || true
cp -r .geniro/project/review/ .geniro/_backup_review/ 2>/dev/null || true
cp -r .claude/skills/ .geniro/_backup_skills/ 2>/dev/null || true  # legacy location
cp -r .claude/rules/ .geniro/_backup_rules/ 2>/dev/null || true
cp .claude/settings.json .geniro/_backup_settings.json 2>/dev/null || true
```

#### 2A.2: Remove template files and install fresh

Remove only files that came from the template — **preserve user-created files** (custom agents, skills, hooks, rules not part of the template).

```bash
# List template file names from $TEMPLATE_DIR, then remove only those from .claude/
# Example: if template has agents/architect-agent.md, remove .claude/agents/architect-agent.md
# But if user has .claude/agents/my-custom-agent.md, leave it untouched
```

To identify which files are template files: list all filenames in `$TEMPLATE_DIR/agents/`, `$TEMPLATE_DIR/hooks/`, `$TEMPLATE_DIR/rules/`. Remove only those matching filenames from `.claude/`. Also remove any legacy skill files in `.claude/skills/` and legacy review criteria in `.claude/skills/review/`. Review criteria now live in `.geniro/project/review/` and are backed up separately. Any file in `.claude/` that does NOT have a corresponding template file is user-created and must be kept.

Before re-running the pipeline, re-ask `$DEPLOY_MODE` via Phase 0.5 (the user may want to switch between global and standalone). Then Phase 1-5 runs normally — codebase analysis, user interview, file generation, tailoring, verification. The template files are installed fresh, then tailored for the detected stack. User-created files remain untouched alongside the new template files.

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

BACKUP DIR: .geniro/_backup_<category>/
FRESH DIR: .claude/<category>/

For each backup file that has a corresponding fresh file:
1. Read both files fully
2. Identify project-specific content in the backup that is NOT in the fresh version:
   - Domain context (project descriptions, entity names, domain rules)
   - Custom commands (specific build/test/lint commands beyond what /geniro:setup detected)
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
4. **User-only files** — Restore from backup using shell `cp` (e.g., `cp .geniro/_backup_agents/my-custom-agent.md .claude/agents/`). These are the user's custom agents/skills/hooks — the template has no opinion about them.

**Anti-corruption rules:**
- Do NOT change phase ordering, compliance tables, Definition of Done, or any structural element in template files
- Do NOT duplicate content that Phase 3 tailoring already added (e.g., if the backup had Django patterns and Phase 3.2 already tailored for Django, don't double up)
- Do NOT port content from the backup that contradicts `$PROJECT_KNOWLEDGE` from Phase 1.6 — the current documentation is more authoritative than old file content

#### 2A.5: Delete backups

After enrichments are applied and verified:
```bash
rm -rf .geniro/_backup_agents/
rm -rf .geniro/_backup_review/
rm -rf .geniro/_backup_skills/
rm -rf .geniro/_backup_hooks/
rm -rf .geniro/_backup_rules/
rm -f .geniro/_backup_settings.json
```

**DO NOT end the conversation or ask "anything else?" here.** You MUST proceed to Phase 4 (Verify) and Phase 5 (Finalize) now.

## Phase 5: Finalize

After setup is complete and verified, finalize the installation.

**Note:** Do NOT delete `.geniro/.geniro-state.json` or `.geniro/template-snapshot/` — these are persistent state files needed for future `/geniro:setup` re-runs.

### 5.1 Ask User Feedback

Before cleanup, use the `AskUserQuestion` tool (do NOT output options as plain text) to ask for confirmation:

```
Setup is complete. Does everything look correct?

A) Yes, looks good — clean up setup files and I'll commit
B) Something needs adjustment — let me tell you what to fix
C) Start over — re-run setup from scratch
```

- **If A**: Print the commit instructions
- **If B**: Ask what needs fixing, apply changes, then ask again
- **If C**: Remove only template-originated files (same selective removal as 2A.2 — preserve user-created files), then re-run from Phase 1

**Note**: The `/geniro:setup` skill is provided by the plugin and persists across runs. It does not need to be removed — the user can re-run `/geniro:setup` at any time to update their plugin configuration.

### 5.2 Verify State

```bash
# State files should exist for future re-runs
[[ -f ".geniro/.geniro-state.json" ]] && echo "✓ Plugin state saved"
```

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "I already know this stack, skip analysis" | Every project is different. Auto-detection catches conventions code review misses. |
| "No docs to read, skip 1.6" | Check first. README.md, CONTRIBUTING.md, .cursorrules — even partial docs contain domain knowledge that makes agents project-aware. |
| "Default settings are fine, skip the interview" | User preferences prevent rework. 2 minutes of questions saves 20 minutes of fixing. |
| "The generated files look correct, skip verification" | Placeholder text and wrong-language content are invisible without systematic scanning. |
| "I already verified in 4.1, skip the verification agent" | You generated the files — you're blind to your own mistakes. The independent agent catches residual placeholders, broken paths, and cross-file inconsistencies you anchored past. |
| "The user said 'good' / 'looks good' — setup is done, I can stop" | Phase 5 finalization has not run yet. User approval of file changes is NOT session completion. You MUST proceed to Phase 4 (Verify) and Phase 5 (Finalize) before ending. |
| "I'll skip the analysis and just ask what the user wants" | The user can't make an informed choice without seeing what changed. Always analyze BEFORE asking — show the diff summary with specific file counts and change descriptions, then let the user decide. |
| "The user can customize agents themselves" | Stack-specific agents are the main value. Generic stubs are a failed setup. |

## Definition of Done

- [ ] Phase 0: Template source located (plugin root or explicit path)
- [ ] Phase 0: Install mode detected (`$INSTALL_MODE`: fresh/update/legacy-update)
- [ ] Phase 0.5: Deploy mode determined (`$DEPLOY_MODE`: global/standalone)
- [ ] Phase 1: Codebase analyzed, all detectable info gathered
- [ ] Phase 1.6: Project documentation scanned, domain context extracted (if docs exist)
- [ ] Phase 1.5: Existing file conflicts resolved (if any)
- [ ] Phase 2: User interviewed, preferences recorded
- [ ] Phase 3: All files generated and written
- [ ] Phase 3.1.1: Template snapshot saved to `.geniro/template-snapshot/`
- [ ] Phase 4.1: Orchestrator verification passed (formatting, placeholders, cross-language)
- [ ] Phase 4.2: Independent verification agent passed (paths, consistency, frontmatter, hooks)
- [ ] Phase 4.4: `.geniro/.geniro-state.json` written with file manifest
- [ ] Phase 5: Finalization complete, state files verified
- [ ] Re-Running Setup: Analysis completed before user prompt
- [ ] User has received summary with next steps
