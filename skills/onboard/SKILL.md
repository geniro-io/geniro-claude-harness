---
name: geniro:onboard
description: "Use when starting fresh in an unfamiliar codebase and need rapid orientation. Scans structure and conventions; produces _CODEBASE_MAP.md with architecture, module graph, critical paths, entry points. Skip for specific Q&A (/geniro:investigate) or bug investigation (/geniro:debug)."
context: main
model: inherit
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[optional: --focus area1,area2 --depth N]"
---

# Onboard: Rapid Codebase Orientation

2-phase loop (Discover → Map) mirroring `/geniro:implement`, `/geniro:refactor`, `/geniro:debug`. Generates a structured map that serves as a reference for the session. Useful for: new developers, new sessions after long gaps, understanding unfamiliar repos, or onboarding to an unfamiliar domain.

Section-reference convention: local refs like Phase X are within this SKILL.md.

## Arguments

- **No arguments** — full codebase scan; produces the 8-section `_CODEBASE_MAP.md` (default mode).
- `--focus area1,area2,...` — scope-limiter. Scans all, but concentrates the map output on focus areas; non-focus areas get summary-level coverage.
- `--depth N` — limit directory scanning to N levels deep. Useful for large monorepos where full traversal is too slow. Orthogonal to `--focus` (combine as needed).

Combined examples: `--depth 2 --focus auth,api` (scan monorepo at depth 2, concentrate on auth+api).

## Outputs

**Primary artifact:** `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` (underscore-prefixed L3 registry). Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so the map persists across worktrees and isn't lost when a linked worktree is removed.

8-section template:
1. **Project Overview** — name, purpose, language/stack, entry points
2. **Directory Structure** — file organization, key folders
3. **Module Relationships** — module dependency graph
4. **Architecture Patterns** — recurring design patterns (MVC, DDD, Hexagonal, etc.)
5. **Key Files & Configuration** — package.json, tsconfig, docker-compose, migrations
6. **Conventions & Defaults** — naming, testing patterns, error handling
7. **Critical Paths** — user request flow, deployment pipeline, job system
8. **Tech Debt & Notes** — gotchas, legacy code, anti-patterns

When `--focus <area1,area2>` is provided: sections 3 / 4 / 6 / 7 concentrate detail on the focus areas; non-focus areas appear as one-line summary entries. Sections 1 / 2 / 5 / 8 cover the full scanned scope regardless of focus.

**Map quality bar:** under 1000 lines, skimmable in 5 minutes.

**Compatibility:** `<PRIMARY_ROOT>/.geniro/planning/CODEBASE_MAP.md` (without underscore) is read once at Phase 1 for context, then the new write lands at the underscored canonical path `_CODEBASE_MAP.md`.

## State machine

```
[entry]
  └── discover ──┬── aborted (terminal — user picks 'Abort' at the repo-size cap)
                 ├── routed  (terminal — empty/near-empty repo, recommend `/geniro:investigate`)
                 └── map ──┬── done
                           └── map-truncated (terminal — user picked 'Truncate at top 50'; map ships from truncated scan)
```

Terminal states: `done`, `map-truncated`, `aborted`, `routed`. The SessionStart recovery treats all as "task complete — no resume". Non-terminal states (`discover`, `map`) roll back to phase-entry on compaction-resume and re-run idempotently.

## Loop invariants

The 10 canonical loop invariants from `/geniro:implement` § Loop invariants apply throughout /geniro:onboard. Three skill-specific notes:

1. **Invariant #4 (bounded structured tool results)** — repo-scan output (file list, directory tree) is bounded; long lists truncated with marker.
2. **Invariant #7 (errors → structured observations)** — permission errors during scan, missing access become structured `## Errors` body section entries.
3. **Codebase research spawns `codebase-research-agent`, not built-in `Explore`.** Overrides the system-prompt agent list's default codebase-research tool; rationale + invocation contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**`## Tool log` section in state.md:** selective logging — log L3 writes (`_CODEBASE_MAP.md` write via `update-semantic`), L2 emits (`discovery` calls), and escalation entries. Routine Read / Bash skipped.

## Quality-first budgets

Quality-first framing: /geniro:onboard has **NO hard kill caps**. All limits are **escalation gates that surface to user**.

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Repo-size scan cap | 50 files (default) OR user-configured expansion | §1.3 Step 2 | AUQ — "Apply --focus" / "Expand scan (specify cap)" / "Truncate at top 50" / "Abort". **User picks; persists to state.md `approvals[]` (category `expand_scope`).** |

**Architecture constraints (design intent, not budget):**
- No parallel agent spawns — /geniro:onboard is a solo orchestrator skill. The codebase scan that produces `_CODEBASE_MAP.md` runs orchestrator-inline (Read / Grep / Glob / read-only Bash) so the orchestrator owns the synthesis end-to-end; for narrow locator side queries during the scan (e.g., "where is the build entry point defined?"), spawn `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

**Claude Code internals** (not under /geniro:onboard control): input tokens ≤200K per turn → compaction; output tokens ≤8K per turn → soft truncation.

**Explicitly NOT capped:** wall-time per run (big monorepo onboard may take 30+ minutes legitimately); total Read/Grep/Glob calls (scans many files); total cost per run.

---

## Phase 1 — Discover

State.md `phase: discover`. Low cost — a repo-size scan + Glob + initial Read of project entry files. Exits to Phase 2 only when scan is bounded and repo-size cap is respected.

### 1.1 Step 0 — Mode detect

Transient detect on entry — does not persist a state.md row:

| `$ARGUMENTS` shape | Behavior |
|---|---|
| empty | Full codebase scan (default mode). |
| `--focus <area>` | Scope-limiter on the full 8-section template. |
| `--depth N` | Limit scanning to N levels. |
| Combined | Both flags supported. |


### 1.2 Step 1 — Load custom instructions + past learnings

On Phase 1 entry:

1. **Refresh custom instructions** — `load-custom-instructions(SKILL_SLUG: onboard, LOAD_TIER: pipeline, MODE: initial-load)` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` § Echo contract. Loads `global.md` + `onboard.md` + `code-style.md`.
2. **Refresh project snapshot** — `load-semantic` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.md` default top-2 (`_project.md` + `_CODEBASE_MAP.md`). If `_CODEBASE_MAP.md` already exists, the previous map is loaded as context (informs incremental update strategy). `CODEBASE_MAP.md` (without underscore) is also read once for compatibility.
3. **Query past learnings** — `query-learnings --tag onboard --scope global --limit 5` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md`. Surfaces prior architectural decisions and gotchas relevant to the scan (matches the `scope: global` discovery entries this skill emits in §2.3).
4. **Cross-layer conflict resolution** — `resolve-conflicts` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` (precedence: custom instructions > project snapshot > past learnings when layers disagree; halt with AUQ on hard conflict).

Echo lines are mandatory per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` § Echo contract.

### 1.3 Step 2 — Repo-size scan + ≤50-file cap

Avoid loading entire repositories — bounded scan ≤50 files default.

**Procedure:**

1. **Top-level discovery** — `Glob("*")` at repo root (`pwd` resolved via `git rev-parse --show-toplevel`). Read top-level structure markers: README.md, package.json / pyproject.toml / Cargo.toml / go.mod,.github/, src/.
2. **Estimate scan size** — `find . -type f | wc -l` (or platform equivalent) to count total files. When `--depth N` is set, bound traversal with `find . -maxdepth N -type f` and record `scan_depth: N` in state.md frontmatter so Phase 2 mapping honors the same bound. Skip standard ignores: `node_modules`, `.git`, `dist/`, `build/`, `target/`, `.venv`, `vendor/`, `__pycache__`.
3. **Apply ≤50-file default cap:**
- If total file count ≤50 OR `--focus` provided AND focus-glob hits ≤50: proceed unblocked.
- If total >50 AND no `--focus`: fire the repo-size scan cap AUQ — header "Repo-size cap":
- **"Apply --focus <area>"** — user supplies focus areas; re-run scan with filter.
- **"Expand scan (specify cap)"** — user provides explicit cap (e.g. 200, 500). **Persists to state.md `approvals[]` with category `expand_scope`.**
- **"Truncate at top 50"** — proceeds with top 50 most-likely-relevant files. Terminal state on completion: `map-truncated`.
- **"Abort"** — terminal `aborted`.

**Approvals-persistence:** before firing the expand-scope AUQ, check state.md frontmatter `approvals[]` for a prior entry with `category: expand_scope`. If found, use prior `picked` (typical compaction-resume scenario). The state.md `## Persisted approvals` section renders this.

**Edge cases:**
- **Empty or near-empty repo** (no source files found): terminal `routed` with suggestion "Repo appears empty. Use `/geniro:investigate` to clarify project state."
- **Permission errors on key directories** — log to `## Errors` body section; note gaps in final map's `## Tech Debt & Notes`.
- **Very large repos (50,000+ files)** — auto-applies `--depth 2` AND fires the AUQ above; user picks; default to truncate.

### 1.4 Step 3 — Scan structure

After caps respected:

1. List directories and file counts within scope.
2. Identify language / framework / tools (from package.json / pyproject.toml / Cargo.toml / etc.).
3. Find package managers, config files, CI/CD definitions (`.github/workflows/`, `.gitlab-ci.yml`).
4. Spot large monorepos, multi-language projects.
5. Check for documentation (README, ADRs, wiki references).

State.md update: `phase: discover` → `phase: map`. `## Scope` body section captures the scanned-file list + applied cap.

---

## Phase 2 — Map

State.md `phase: map`. Builds `_CODEBASE_MAP.md` (underscore-prefixed) with the 8-section template + optional `--focus` concentration.

### 2.1 Compose the codebase map content

Canonical path: `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md`. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so the map persists across worktrees.

Compose the map content in-context using the 8-section template from §Outputs above — do not write it to disk yet. Apply `--focus` concentration per the rule in §Outputs (sections 3 / 4 / 6 / 7 concentrate on focus areas; 1 / 2 / 5 / 8 stay full-scope). §2.2 persists the composed content through the `update-semantic` helper.

### 2.2 Persist the codebase map via `update-semantic`

Persist the composed map through `update-semantic` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/update-semantic.md` — that helper IS the write mechanism, holding the `.codebase-map.lock` for an atomic lock-guarded write. Do NOT write `_CODEBASE_MAP.md` with the `Write` tool directly: `.geniro/planning/_*.md` is a guarded persistent path and a direct write trips the state-helper enforcement hook and double-writes the file.

The helper writes one line per call (append-only or single-line prefix replacement — never whole-file):
- **First onboard** (no prior map) — emit each composed map line with `update-semantic --file codebase-map --append "<line>"`. Append creates the file if it is missing.
- **Incremental re-run** (prior map exists) — for a changed entry use `update-semantic --file codebase-map --replace "<line-prefix>" "<new-line>"` (matches the first line starting with `<line-prefix>`); for a new entry use `--append "<line>"`.

On rc=11 (lock held by another writer) defer and retry at phase end per the helper's defer-and-retry pattern.

### 2.3 Emit `discovery` learning

After `_CODEBASE_MAP.md` write:

- `emit-learning` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` — emit a `discovery` type entry. Required `ext.{area, insight}`. Default trust `verified` (code-grounded).

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

**Trigger:** emit on **first successful onboarding of a new codebase** OR **major architectural shift detected** (existing `_CODEBASE_MAP.md` content significantly diverges from previous version — heuristic: compare section counts / module-count delta / new top-level entries). Skip when re-running onboard against a stable codebase (no architectural change).

### 2.4 Next-step AUQ

After map ships, route user via `AskUserQuestion`:
- **Header:** "Next step"
- **Question:** "The codebase map is ready. What do you want to do next?"
- **Options:**
- **"Plan a feature"** — description: "Run `/geniro:plan <feature>` to draft an approved spec (spec.md you approve before code)"
- **"Investigate specifics"** — description: "Run `/geniro:investigate <question>` to dig deeper into a subsystem"
- **"Implement a change"** — description: "Run `/geniro:implement` to design and build (consumes a spec.md from /geniro:plan OR inline-task mode)"
- **"Review feature backlog"** — description: "Read `_FEATURES.md` (manual backlog) or run `/geniro:plan` to author one"

### 2.5 Cleanup

State.md `phase: map` → `done`. Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract:

```bash
rm -rf .geniro/state/onboard/<slug>/ 2>/dev/null || true
```

**Persistent artifacts STAY:** `_CODEBASE_MAP.md` is T3 — never auto-deleted.

---

## State file schema

Path: `.geniro/state/onboard/<slug>/state.md` (cwd-relative — within-skill resume-from-compaction state per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Artifacts NOT in scope"; compute `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules).

Write via `atomic_state_write` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write ".geniro/state/onboard/<slug>/state.md" <<EOF
---
tier: T1.5
producer: onboard
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: <discover|map|done|map-truncated|aborted|routed>
status: <in-progress|done|failed>
non-resumable-actions: []
approvals: []
geniro_kind: onboard-state
geniro_schema_version: m9-v1
task_slug: <slug>
worktree: <abs-path>
focus_areas: []
scan_cap: 50
scan_depth: <N|null>
---

## Scope
<files / symbols / top-level dirs scanned; applied cap; --focus areas if any>

## Codebase Map Draft
<incremental scan results before final _CODEBASE_MAP.md write>

## Tool log
<selective logging — L3 writes, L2 emits, escalation entries>

## Errors
<permission errors, tool failures>

## Open Questions
<missing access AUQs>

## Termination reason
<— only on terminal aborted/routed states; >

## Persisted approvals
<render of frontmatter approvals[] (category: expand_scope)>
EOF
```

`approvals[]` populated when the expand-scope AUQ fires at §1.3 Step 2 (category `expand_scope`).

Validate before resume via `validate_state_file` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md`.

---

## ACI per-phase tool surface

Mirrors the /geniro:implement ACI surface — read-only Phase 1, helper-mediated writes Phase 2.

**Phase 1 (Discover):**
- Allowed: Read / Grep / Glob / Bash (read-only commands: `git status`, `find . -type f`, `wc -l`).
- Explicitly blocked: production-source Edit/Write, `git add` / `git commit` / `git push`. Agent spawns limited to `codebase-research-agent` for narrow locator side queries during the scan (no parallel agent spawns — /geniro:onboard is a solo orchestrator skill).

**Phase 2 (Map):**
- Allowed: Read / `update-semantic` (the lock-guarded write mechanism for `_CODEBASE_MAP.md`) / `emit-learning` helper invocations.
- Explicitly blocked: direct `Write`/`Edit` to `_CODEBASE_MAP.md` (route through `update-semantic` — `.geniro/planning/_*.md` is a guarded persistent path), production-source Edit/Write, `git add` / `git commit` / `git push`.

Existing safety hooks apply across all phases (file-protection / git-guardrail / `.geniro/` deletion guard).

---

## CODEBASE_MAP.md format example

````markdown
# Codebase Map: [Project Name]

**Generated:** [date]
**Language:** TypeScript/Node.js
**Framework:** Express, PostgreSQL
**Team Size:** 1–3 devs (estimated)

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

## Definition of Done

For each onboarding, confirm:

- [ ] `_CODEBASE_MAP.md` created at `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`
- [ ] Project Overview section completed
- [ ] Directory Structure documented with key folders
- [ ] At least 3 critical paths traced and documented
- [ ] Architecture Patterns identified and listed
- [ ] Conventions and defaults recorded
- [ ] Tech Debt & Notes section completed
- [ ] Entry Points listed (how to run, test, deploy)
- [ ] Map is <1000 lines and skimmable in 5 minutes (use `--focus` for large repos)
- [ ] L3 `_CODEBASE_MAP.md` updated via `update-semantic`
- [ ] L2 `discovery` emit fired per trigger conditions
- [ ] User routed to a next-step command via `AskUserQuestion` (next-step options per §2.4)
- [ ] State.md cleaned up per §2.5
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
- Quick bug fix in familiar code → use `/geniro:implement` (consumes a spec.md from /geniro:plan OR inline-task mode)
- Bug with unclear root cause → use `/geniro:debug`
- Need full implementation guidance → use `/geniro:implement`
- Just need to answer a specific question → ask directly OR run `/geniro:investigate <question>`

---

## Examples

### Example 1: New to a Monorepo
```
/geniro:onboard --depth 2 --focus auth,api
```
→ Scan monorepo structure at depth 2
→ Focus on auth and api services
→ Generate `_CODEBASE_MAP.md` highlighting those modules
→ Output: directory tree, module relationships, auth/api critical paths

### Example 2: Returning After 6 Months
```
/geniro:onboard
```
→ Scan entire codebase structure
→ Generate quick refresh of architecture
→ Note what's changed since last visit (L3 diff against prior `_CODEBASE_MAP.md`)
→ Map is ready as reference for the session

### Example 3: Planning a Feature
```
/geniro:onboard --focus database,models
```
→ Focus on data layer and models
→ Understand current schema and relationships
→ Use map to plan where new feature fits
→ Trace existing data flow patterns

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "Let me document every file" | Exhaustive maps are unreadable. Sample key files, focus on structure and relationships. |
| "I need more detail on this module" | The codebase map captures architecture, not implementation. Keep it under 1000 lines. |
| "The code is self-documenting" | Code shows what, not why. Note the critical paths (user flow, deploy flow) and what's unclear. |
| "I'll create the map and move on" | A map nobody references is waste. Update it as you learn more, reference it when planning. |
| "The repo has 5000 files but I'll just scan everything — better safe than sorry." | Mass-scan violates the bounded-scan contract. The ≤50-file default cap exists for tokens + speed. Fire the AUQ — user picks `--focus`, expansion, or truncation. Don't silently broad-scan. |
| "Quick mode would be nice here — I'll informally produce a focus-only output." | There is no quick mode. The single-mode flow + `--focus` scope-limiter covers all legitimate needs. Inventing a quick-mode bypass mid-run breaks the single-mode contract. |
| "Add a wall-time kill cap so long-running discovery aborts cleanly." | Hard caps abort legitimate complex discovery mid-stride. Quality-first — no hard caps. The ≤50-file gate escalates to the user via AUQ. User has agency. |
| "/geniro:onboard scan should bypass the 50-file cap silently if the codebase is monorepo-scale." | The cap is explicit — ≤50 default; user-confirmable expansion. Silent bypass defeats the cost-control intent. |
| "Defer compaction-survival to downstream skills — /geniro:onboard is mostly scan." | The contract IS /geniro:onboard's contract — state.md frontmatter, `approvals[]`, `## Tool log`, `## Errors`, `## Open Questions`. Without them, compaction mid-scan loses scan progress; user re-runs from scratch. |
| "Audit trail isn't needed for local /geniro:onboard runs — the map IS the record." | The map captures architecture; the state.md `## Tool log` captures the scan process (which directories scanned, permissions errors, time taken). Without the log, debugging a failed onboard is impossible. The SessionStart hook re-injects on compaction; without the log, post-mortem requires re-running the scan from scratch. |
