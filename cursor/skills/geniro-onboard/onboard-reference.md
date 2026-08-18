<!-- Generated from skills/onboard/onboard-reference.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Onboard — detailed reference

Detail sections extracted from `${CLAUDE_PLUGIN_ROOT}/skills/onboard/SKILL.md` to keep the main skill body lean. The orchestrator reads this file when SKILL.md references one of the sections below by name.

## Contents

1. _CODEBASE_MAP.md format example — full 8-section worked example
2. Discovery-learning emit payload — the `emit_learning` call SKILL.md §2.3 fires

---

## 1. _CODEBASE_MAP.md format example

The 8-section template in SKILL.md §Outputs is the operative spec; this worked example illustrates the rendering.

````markdown
# Codebase Map: [Project Name]

**Generated:** [date]
**Language:** TypeScript/Node.js
**Framework:** Express, PostgreSQL

## Project Overview

| Aspect | Details |
|--------|---------|
| **Purpose** | User task management SaaS |
| **Language/Stack** | TypeScript/Node.js, Express, PostgreSQL |
| **Entry Point** | src/index.ts → Express server port 3000 |
| **Database** | PostgreSQL, migrations in ./db/migrations |

## Directory Structure

```
├── src/
│ ├── index.ts # Server entry point
│ ├── routes/ # Express route handlers
│ │ ├── auth.ts
│ │ ├── tasks.ts
│ ├── services/ # Business logic
│ │ ├── taskService.ts
│ │ ├── authService.ts
│ ├── models/ # Data models & types
│ ├── middleware/ # Auth, logging, errors
│ └── db/ # Database utilities
├── tests/ # Jest unit & integration tests
├── db/
│ ├── migrations/ # SQL migration files
│ └── schema.sql
├──.env.example # Environment template
├── package.json
└── README.md
```

## Module Relationships

```
Express App (index.ts)
├── Routes (routes/*.ts)
│ └── Services (services/*.ts)
│ └── Database (db/*)
│ └── Models (models/*.ts)
└── Middleware (middleware/*.ts)
├── Auth Middleware
└── Error Handler
```

**Key Flows:**
- User registers → authService.register → db.users.insert
- User lists tasks → taskService.list → db.query → Task[]

## Architecture Patterns

| Pattern | Usage | Files |
|---------|-------|-------|
| **MVC** | Route → Service → DB | routes/, services/, db/ |
| **Middleware Chain** | Auth → Logging → Business Logic | middleware/ |
| **Error Handling** | Try-catch → ErrorHandler middleware | middleware/errorHandler.ts |
| **Dependency Injection** | Service constructors receive DB instance | services/*.ts |

## Key Files & Configuration

| File | Role |
|------|------|
| package.json | Dependencies and scripts; npm, lockfile package-lock.json |
| tsconfig.json | TypeScript compiler config |
| .github/workflows | CI/CD via GitHub Actions |
| db/schema.sql | Database schema reference |
| db/migrations/ | SQL migration files (run on startup) |
| .env.example | Environment template |

**Entry points:**
- API Server: src/index.ts (port 3000)
- Tests: [test command from package.json/Makefile/CLAUDE.md]
- DB Setup: [migration command if applicable]

## Conventions & Defaults

- **Naming:** camelCase for variables/functions, PascalCase for classes
- **Files:** One class/service per file
- **Testing:**.test.ts suffix, Jest config in package.json
- **Errors:** Custom error classes in errors.ts, caught by middleware
- **Logging:** console.log for now (TODO: move to Winston)
- **Auth:** JWT tokens in Authorization header
- **Timestamps:** All models use UNIX timestamps (seconds since epoch)

## Critical Paths

### User Registration
1. POST /auth/register → routes/auth.ts
2. authService.register(email, password)
3. Hash password → db.users.insert
4. Return JWT token

### List User Tasks
1. GET /tasks (with JWT header) → authMiddleware checks token
2. taskService.list(userId)
3. db.query('SELECT * FROM tasks WHERE user_id = $1')
4. Return Task[]

## Tech Debt & Notes

| Issue | Impact | Workaround |
|-------|--------|-----------|
| Logging is console.log | Hard to debug in prod | Read logs via SSH |
| No rate limiting | DDoS risk | Add nginx upstream |
| Migrations run on startup | Risk of conflicts | Plan migration strategy |
| No type safety on DB queries | Runtime errors | Consider Prisma migration |
````

---

## 2. Discovery-learning emit payload

The exact `emit_learning` call SKILL.md §2.3 fires after `_CODEBASE_MAP.md` write, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Caller contract:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
emit_learning <<'EOF'
{
"producer": "/geniro:onboard",
"type": "discovery",
"tags": ["onboard", "architecture", "<language>"],
"scope": "global",
"trust": "verified",
"summary": "<one-line architectural pattern>",
"ext": {
"area": "<top-level area, e.g. 'services', 'hexagonal-ports'>",
"insight": "<2-3 sentence non-obvious finding from the scan>"
}
}
EOF
```

After a successful emit, echo `Recorded learning: <summary>` to the user.
