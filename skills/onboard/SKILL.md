---
name: geniro:onboard
description: "Rapid codebase mapping and orientation. Scans structure, files, patterns, conventions. Produces CODEBASE_MAP.md with architecture, module relationships, critical paths, and entry points. Do NOT use for answering specific code questions, debugging, implementing features, or quick fixes in familiar code."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent]
argument-hint: "[optional: area to focus on, e.g. 'backend', 'auth module']"
---

# Onboard: Rapid Codebase Orientation

Use this skill to quickly understand a new or unfamiliar codebase. Generates a structured map that serves as a reference for the session. Useful for: new developers, new sessions after long gaps, understanding unfamiliar repos, or onboarding to an unfamiliar domain.

## Arguments

- `--depth N`: Limit directory scanning to N levels deep (default: unlimited). Useful for large monorepos where full traversal is too slow.
- `--focus area1,area2,...`: Concentrate mapping on specified areas/modules. Other areas get summary-level coverage only.
- No arguments: Full codebase scan with automatic depth based on repo size.

## Outputs

**Primary artifact:** `.geniro/planning/CODEBASE_MAP.md`

Contains:
1. **Project Overview** – Name, purpose, language/stack, entry points
2. **Directory Structure** – How files are organized, key folders
3. **Module Relationships** – Which modules depend on which
4. **Architecture Patterns** – Recurring design patterns (MVC, DDD, etc.)
5. **Key Files & Configuration** – package.json, tsconfig, docker-compose, migrations, etc.
6. **Conventions & Defaults** – Naming, testing patterns, error handling
7. **Critical Paths** – User request flow, deployment pipeline, job system
8. **Tech Debt & Notes** – Gotchas, legacy code, anti-patterns

## Workflow: Scan → Map → Reference

### 1. Scan (5–10 min)
- List directories and file counts
- Identify language/framework/tools
- Find package managers, config files, CI/CD
- Spot large monorepos, multi-language projects
- Check for documentation (README, ADRs, wiki)

### 2. Map (15–20 min)
- Create hierarchical module view
- Identify 5–10 core modules/services
- Trace a typical user request (happy path)
- Identify boundary/integration points
- List repeated patterns (error handling, logging, auth)
- Spot legacy code or known issues

### 3. Reference (during session)
- Refer to map when navigating unfamiliar code
- Use it to understand impact of changes
- Check patterns before implementing
- Identify where to add new features

### Edge Cases

- **Empty or near-empty repo**: If no source files are found, note this in the map and ask the user if this is expected.
- **Permission errors**: If scanning is blocked on key directories, document what was accessible and note the gaps.
- **Very large repos (50,000+ files)**: Automatically apply `--depth 2` and note this in the map. Suggest `--focus` for targeted exploration.

## CODEBASE_MAP.md Format

```markdown
# Codebase Map: [Project Name]

**Generated:** 2026-04-03
**Language:** TypeScript/Node.js
**Framework:** Express, PostgreSQL
**Team Size:** 1–3 devs (estimated)

## Quick Reference

| Aspect | Details |
|--------|---------|
| **Purpose** | User task management SaaS |
| **Entry Point** | src/index.ts → Express server port 3000 |
| **Database** | PostgreSQL, migrations in ./db/migrations |
| **CI/CD** | GitHub Actions in .github/workflows |
| **Package Manager** | npm, lockfile: package-lock.json |

## Directory Structure

```
├── src/
│   ├── index.ts              # Server entry point
│   ├── routes/               # Express route handlers
│   │   ├── auth.ts
│   │   ├── tasks.ts
│   ├── services/             # Business logic
│   │   ├── taskService.ts
│   │   ├── authService.ts
│   ├── models/               # Data models & types
│   ├── middleware/           # Auth, logging, errors
│   └── db/                   # Database utilities
├── tests/                    # Jest unit & integration tests
├── db/
│   ├── migrations/           # SQL migration files
│   └── schema.sql
├── .env.example              # Environment template
├── package.json
└── README.md
```

## Module Relationships

```
Express App (index.ts)
├── Routes (routes/*.ts)
│   └── Services (services/*.ts)
│       └── Database (db/*)
│           └── Models (models/*.ts)
└── Middleware (middleware/*.ts)
    ├── Auth Middleware
    └── Error Handler
```

**Key Flows:**
- User registers → authService.register() → db.users.insert()
- User lists tasks → taskService.list() → db.query() → Task[]

## Architecture Patterns

| Pattern | Usage | Files |
|---------|-------|-------|
| **MVC** | Route → Service → DB | routes/, services/, db/ |
| **Middleware Chain** | Auth → Logging → Business Logic | middleware/ |
| **Error Handling** | Try-catch → ErrorHandler middleware | middleware/errorHandler.ts |
| **Dependency Injection** | Service constructors receive DB instance | services/*.ts |

## Conventions & Defaults

- **Naming:** camelCase for variables/functions, PascalCase for classes
- **Files:** One class/service per file
- **Testing:** .test.ts suffix, Jest config in package.json
- **Errors:** Custom error classes in errors.ts, caught by middleware
- **Logging:** console.log for now (TODO: move to Winston)
- **Auth:** JWT tokens in Authorization header
- **Timestamps:** All models use UNIX timestamps (seconds since epoch)

## Critical Paths

### User Registration
1. POST /auth/register → routes/auth.ts
2. authService.register(email, password)
3. Hash password → db.users.insert()
4. Return JWT token

### List User Tasks
1. GET /tasks (with JWT header) → authMiddleware checks token
2. taskService.list(userId)
3. db.query('SELECT * FROM tasks WHERE user_id = $1')
4. Return Task[]

## Known Issues & Tech Debt

| Issue | Impact | Workaround |
|-------|--------|-----------|
| Logging is console.log | Hard to debug in prod | Read logs via SSH |
| No rate limiting | DDoS risk | Add nginx upstream |
| Migrations run on startup | Risk of conflicts | Plan migration strategy |
| No type safety on DB queries | Runtime errors | Consider Prisma migration |

## Entry Points

- **API Server:** src/index.ts (port 3000)
- **Tests:** [test command from package.json/Makefile/CLAUDE.md]
- **DB Setup:** [migration command if applicable]
- **Config:** .env file (see .env.example)

## Resources

- README.md – Project overview and setup
- package.json – Dependencies and scripts
- db/schema.sql – Database schema reference
```

## Compliance — Do Not Over-Document

| Your reasoning | Why it's wrong |
|---|---|
| "Let me document every file" | Exhaustive maps are unreadable. Sample key files, focus on structure and relationships. |
| "I need more detail on this module" | The codebase map captures architecture, not implementation. Keep it under 1000 lines. |
| "The code is self-documenting" | Code shows what, not why. Note the critical paths (user flow, deploy flow) and what's unclear. |
| "I'll create the map and move on" | A map nobody references is waste. Update it as you learn more, reference it when planning. |

## Definition of Done

For each onboarding, confirm:

- [ ] CODEBASE_MAP.md created in .geniro/planning/ directory
- [ ] Project overview section completed
- [ ] Directory structure documented with key folders
- [ ] At least 3 critical paths traced and documented
- [ ] Architecture patterns identified and listed
- [ ] Conventions and defaults recorded
- [ ] Known issues and tech debt noted
- [ ] Entry points listed (how to run, test, deploy)
- [ ] Map is <1000 lines and skimmable in 5 minutes (use --focus for large repos)

---

## When to Use This Skill

**Use `/geniro:onboard`:**
- Starting work on a new/unfamiliar codebase
- Returning to a project after months away
- Onboarding a new team member
- Planning a major change and need context
- Trying to understand impact of a change
- Need to explain architecture to someone else

**Don't use:**
- Quick bug fix in familiar code → use `/geniro:follow-up` or `/geniro:debug`
- Need full implementation guidance → use `/geniro:implement`
- Just need to answer a specific question → ask directly

---

## Examples

### Example 1: New to a Monorepo
```
/geniro:onboard --depth 2 --focus auth,api
```
→ Scan monorepo structure at depth 2
→ Focus on auth and api services
→ Generate CODEBASE_MAP.md highlighting those modules
→ Output: directory tree, module relationships, auth/api critical paths

### Example 2: Returning After 6 Months
```
/geniro:onboard
```
→ Scan entire codebase structure
→ Generate quick refresh of architecture
→ Note what's changed since last visit
→ Map is ready as reference for the session

### Example 3: Planning a Feature
```
/geniro:onboard --focus database,models
```
→ Focus on data layer and models
→ Understand current schema and relationships
→ Use map to plan where new feature fits
→ Trace existing data flow patterns
