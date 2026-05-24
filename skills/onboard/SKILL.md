---
name: geniro:onboard
description: "Use when starting fresh in an unfamiliar codebase and need rapid orientation. Scans structure and conventions; produces _CODEBASE_MAP.md with architecture, module graph, critical paths, entry points. Skip for specific Q&A (/geniro:investigate) or bug investigation (/geniro:debug)."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[optional: --focus area1,area2 --depth N]"
---

# Onboard: Rapid Codebase Orientation (M9)

M9 redesign — 2-phase loop (Discover → Map) mirroring `/implement`, `/refactor`, `/debug`. Generates а structured map that serves as a reference for the session. Useful for: new developers, new sessions after long gaps, understanding unfamiliar repos, or onboarding к an unfamiliar domain.

Section-reference convention: local refs like §1.x are within this SKILL.md; spec refs like `M9 §6.3` point к `architecture/M9-discovery-redesign.md`.

## Arguments

- **No arguments** — full codebase scan; produces the 8-section `_CODEBASE_MAP.md` (default mode).
- `--focus area1,area2,...` — scope-limiter. Scans all, но concentrates the map output on focus areas; non-focus areas get summary-level coverage. NOT а separate output (M9 dropped the legacy quick-mode `focus-<area>.md` artifact per design Q4 — full mode с `--focus` covers concentrated mapping без а separate 1-page output).
- `--depth N` — limit directory scanning to N levels deep. Useful for large monorepos где full traversal is too slow. Orthogonal к `--focus` (combine as needed).

Combined examples: `--depth 2 --focus auth,api` (scan monorepo at depth 2, concentrate on auth+api).

## Outputs

**Primary artifact:** `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` (M1:508 underscore-prefixed L3 registry per M2 §6.1). Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so the map persists across worktrees и isn't lost when а linked worktree is removed.

8-section template (preserved verbatim from pre-M9):
1. **Project Overview** — name, purpose, language/stack, entry points
2. **Directory Structure** — file organization, key folders
3. **Module Relationships** — module dependency graph
4. **Architecture Patterns** — recurring design patterns (MVC, DDD, Hexagonal, etc.)
5. **Key Files & Configuration** — package.json, tsconfig, docker-compose, migrations
6. **Conventions & Defaults** — naming, testing patterns, error handling
7. **Critical Paths** — user request flow, deployment pipeline, job system
8. **Tech Debt & Notes** — gotchas, legacy code, anti-patterns

When `--focus <area1,area2>` is provided: sections 3 / 4 / 6 / 7 concentrate detail on the focus areas; non-focus areas appear as one-line summary entries. Sections 1 / 2 / 5 / 8 cover the full scanned scope regardless of focus.

**Map quality bar:** under 1000 lines, skimmable в 5 minutes.

**Backward-compat:** legacy `<PRIMARY_ROOT>/.geniro/planning/CODEBASE_MAP.md` (без underscore) is read once at Phase 1 §1.2 для context, then the new write lands at the underscored canonical path. Legacy file stays on disk one release cycle для existing references.

## State machine

```
[entry]
  └── discover ──┬── map ──┬── done
                 │          └── map-truncated (terminal — repo-size cap exceeded + user picked "Truncate at top 50")
                 │
                 └── discover-escalated ──┬── discover (user supplies missing access / picks "Continue" → resume)
                                          ├── aborted (terminal — user picks "Cannot proceed")
                                          └── routed (terminal — empty/near-empty repo, recommend `/geniro:investigate`)
```

Terminal states: `done`, `map-truncated`, `aborted`, `routed`. M3 SessionStart recovery treats all as "task complete — no resume". Non-terminal states (`discover`, `map`) roll back к phase-entry on compaction-resume и re-run idempotently. Escalation state (`discover-escalated`) surfaces к user as "task was paused — last AUQ options" so user re-picks без losing context.

See M9 §2.1 для the canonical phase enum + M9 §2.1.1 for termination-case mapping.

## Loop invariants

The 7 loop invariants from `architecture/M4-implement-redesign.md` §2.2 apply throughout /onboard. Two M9-specific notes per M9 §2.2:

1. **Invariant #4 (bounded structured tool results)** — repo-scan output (file list, directory tree) is bounded; long lists truncated с marker.
2. **Invariant #7 (errors → structured observations)** — permission errors during scan, missing access become structured `## Errors` body section entries.

**`## Tool log` section в state.md:** selective logging per M4 contract — log L3 writes (`_CODEBASE_MAP.md` write via `update-semantic`), L2 emits (`discovery` calls), и escalation entries. Routine Read / Bash skipped.

## Quality-first budgets

Per M9 §2.3 — quality-first framing. /onboard has **NO Class-A hard kill caps**. All limits are **escalation gates that surface к user**.

| Gate | Cap | Where | Past threshold |
|---|---|---|---|
| Repo-size scan cap (P-M9-2) | 50 files (default) OR user-configured expansion | §1.3 | AUQ — "Apply --focus" / "Expand scan (specify cap)" / "Truncate at top 50" / "Abort". **User picks; persists к `approvals[]` per P-M1-1.** |

**Architecture constraints (design intent, not budget):**
- No parallel agent spawns — /onboard is а solo orchestrator skill.

**Claude Code internals** (not under /onboard control): input tokens ≤200K per turn → compaction; output tokens ≤8K per turn → soft truncation.

**Explicitly NOT capped:** wall-time per run (big monorepo onboard may take 30+ minutes legitimately); total Read/Grep/Glob calls (scans many files); total cost per run (deferred к P-X6).

---

## Phase 1 — Discover

State.md `phase: discover`. Light по cost — а repo-size scan + Glob + initial Read of project entry files. Exits к Phase 2 only when scan is bounded и repo-size cap is respected.

### 1.1 Phase 0 — Mode detect (pre-Phase-1)

Pre-Phase-1 detect (transient — does не persist а state.md row):

| `$ARGUMENTS` shape | Behavior |
|---|---|
| empty | Full codebase scan (default mode). |
| `--focus <area>` | Scope-limiter on the full 8-section template. |
| `--depth N` | Limit scanning к N levels. |
| Combined | Both flags supported. |

(M9 §3.1 drops pre-M9 `--quick` mode entirely. The legacy `focus-<area>.md` artifact is removed; full mode с `--focus` covers concentrated mapping без а separate 1-page output.)

### 1.2 Step 0 — Load custom instructions + L2 prior-knowledge

On Phase 1 entry (M9 D12-fix promotes onboard к full L4+L3+L2 load):

1. **L4 refresh** — `load-custom-instructions(SKILL_SLUG: onboard, LOAD_TIER: pipeline, MODE: initial-load)` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` § Echo contract. Loads `global.md` + `onboard.md` + `code-style.md` + `user-preferences.md` (M10b pipeline tier — 4 files).
2. **L3 refresh** — `load-semantic` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.md` default top-2 (`_project.md` + `_CODEBASE_MAP.md`). If `_CODEBASE_MAP.md` already exists, the previous map is loaded as context (informs incremental update strategy). Legacy `CODEBASE_MAP.md` (без underscore) is read once for backward-compat.
3. **L2 prior-knowledge** — `query-learnings --tag onboard --tag architecture --tag codebase --scope task --limit 5` per M2 §5.3 «discovery start» trigger. К surface prior architectural decisions и gotchas relevant к the scan.
4. **Cross-layer conflict resolution** — `resolve-conflicts` per M2 §10 (precedence L4 > L3 > L2 when layers disagree; halt с AUQ on hard conflict).

Echo lines per M3 §7.2 mandatory.

### 1.3 Step 1 — Repo-size scan + P-M9-2 ≤50-file cap

P-M9-2 obligation per master plan §344 — "Avoid loading entire repositories" — bounded scan ≤50 files default.

**Procedure:**

1. **Top-level discovery** — `Glob("*")` at repo root (`pwd` resolved via `git rev-parse --show-toplevel`). Read top-level structure markers: README.md, package.json / pyproject.toml / Cargo.toml / go.mod, .github/, src/.
2. **Estimate scan size** — `find . -type f | wc -l` (or platform equivalent) к count total files. Skip standard ignores: `node_modules`, `.git`, `dist/`, `build/`, `target/`, `.venv`, `vendor/`, `__pycache__`.
3. **Apply ≤50-file default cap (P-M9-2):**
   - If total file count ≤50 OR `--focus` provided AND focus-glob hits ≤50: proceed unblocked.
   - If total >50 AND no `--focus`: fire **AUQ "Scope"** — header "Repo-size cap":
     - **"Apply --focus <area>"** — user supplies focus areas; re-run scan с filter.
     - **"Expand scan (specify cap)"** — user provides explicit cap (e.g. 200, 500). **Persists к state.md `approvals[]` с category `expand_scope` per P-M1-1.**
     - **"Truncate at top 50"** — proceeds с top 50 most-likely-relevant files. Terminal state on completion: `map-truncated`.
     - **"Abort"** — terminal `aborted`.

**Approvals-persistence (P-M1-1 producer-side contract):** before firing the expand-scope AUQ, check state.md frontmatter `approvals[]` for а prior entry с `category: expand_scope`. If found, use prior `picked` (typical compaction-resume scenario). M3 §6 Block 5d renders this.

**Edge cases (preserved от pre-M9):**
- **Empty or near-empty repo** (no source files found): terminal `routed` с suggestion "Repo appears empty. Use `/geniro:investigate` to clarify project state."
- **Permission errors on key directories** — log к `## Errors` body section; note gaps в final map's `## Tech Debt & Notes`.
- **Very large repos (50,000+ files)** — auto-applies `--depth 2` AND fires the AUQ above; user picks; default к truncate.

### 1.4 Step 2 — Scan structure

After §1.3 caps respected:

1. List directories и file counts within scope.
2. Identify language / framework / tools (from package.json / pyproject.toml / Cargo.toml / etc.).
3. Find package managers, config files, CI/CD definitions (`.github/workflows/`, `.gitlab-ci.yml`).
4. Spot large monorepos, multi-language projects.
5. Check for documentation (README, ADRs, wiki references).

State.md update: `phase: discover` → `phase: map`. `## Scope` body section captures the scanned-file list + applied cap.

---

## Phase 2 — Map

State.md `phase: map`. Builds `_CODEBASE_MAP.md` (M1:508 underscore-prefixed) с the 8-section template + optional `--focus` concentration.

### 2.1 Build `_CODEBASE_MAP.md`

Canonical path: `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` per M1:508. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so the map persists across worktrees.

Use the 8-section template from §Outputs above. Apply `--focus` concentration per the rule в §Outputs (sections 3 / 4 / 6 / 7 concentrate on focus areas; 1 / 2 / 5 / 8 stay full-scope).

### 2.2 L3 update via `update-semantic`

After `_CODEBASE_MAP.md` write, call `update-semantic --file codebase-map --replace "<previous-content>" "<new-content>"` per M2 §6.1. The helper handles bounded auto-incremental updates и lock-guarding via `.codebase-map.lock`. For а full regen (first onboard или major architectural shift), pass the full new content.

### 2.3 L2 `discovery` emit (M9 §7.3)

Replaces deleted `/learnings` skill (master plan §69). After `_CODEBASE_MAP.md` write:

- `emit-learning` per M2 §5.2 — emit `discovery` type entry per M2 §5.3 row /onboard. Required `ext.{area, insight}`. Default trust `verified` per M2 §5.3 (code-grounded).

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

**Trigger:** emit при **first successful onboarding of а new codebase** OR **major architectural shift detected** (existing `_CODEBASE_MAP.md` content significantly diverges от previous version — heuristic per M9 OQ-M9-3 deferred: compare section counts / module-count delta / new top-level entries). Skip when re-running onboard against а stable codebase (no architectural change).

### 2.4 Next-step AUQ (M9 §7.4)

After map ships, route user via `AskUserQuestion`:
- **Header:** "Next step"
- **Question:** "The codebase map is ready. What do you want to do next?"
- **Options:**
  - **"Plan а feature"** — description: "Run `/geniro:plan <feature>` to draft an approved spec (M5 spec.md emits а structured plan you approve before code)" (replaces stale pre-M9 routing к /implement direct + /decompose).
  - **"Investigate specifics"** — description: "Run `/geniro:investigate <question>` to dig deeper into а subsystem"
  - **"Implement а change"** — description: "Run `/geniro:implement` to design и build (consumes а spec.md from /plan OR inline-task mode)" (replaces stale /follow-up).
  - **"Review feature backlog"** — description: "Read `_FEATURES.md` (manual backlog) or run `/geniro:plan` to author one"

### 2.5 Cleanup

State.md `phase: map` → `done`. Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract:

```bash
rm -rf .geniro/state/onboard/<slug>/ 2>/dev/null || true
```

**Persistent artifacts STAY:** `_CODEBASE_MAP.md` is T3 — never auto-deleted. Legacy `CODEBASE_MAP.md` (без underscore) stays one release cycle; user-managed cleanup.

---

## State file schema (M1 §T1 + М9 §11.1)

Path: `<PRIMARY_ROOT>/.geniro/state/onboard/<slug>/state.md` (resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A; compute `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules).

Write via `atomic_state_write` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write ".geniro/state/onboard/<slug>/state.md" <<EOF
---
tier: T1
producer: onboard
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: <mode-detect|discover|map|discover-escalated|done|map-truncated|aborted|routed>
status: <in-progress|done|failed>
non-resumable-actions: []
approvals: []
geniro_kind: onboard-state
geniro_schema_version: m9-v1
task_slug: <slug>
worktree: <abs-path>
focus_areas: []
scan_cap: 50
---

## Inputs from <producer>
<optional — present when а T2 input was consumed>

## Scope
<files / symbols / top-level dirs scanned; applied cap; --focus areas если any>

## Codebase Map Draft
<incremental scan results before final _CODEBASE_MAP.md write>

## Tool log
<selective logging per M4 §2.2 — L3 writes, L2 emits, escalation entries>

## Errors
<M3 §6 Block 5b — permission errors, tool failures>

## Open Questions
<M3 §6 Block 5c — missing access AUQs>

## Termination reason
<M3 §6 — only on terminal aborted/routed states; per M9 §2.1.1>

## Persisted approvals
<M3 §6 Block 5d — render of frontmatter approvals[] (category: expand_scope)>
EOF
```

`approvals[]` populated per P-M1-1 when §1.3 fires (category `expand_scope`).

Validate before resume via `validate_state_file` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md`.

---

## ACI per-phase tool surface (M9 §12.5)

Mirrors M4 §13.5 structure.

**Phase 1 (Discover):**
- Allowed: Read / Grep / Glob / Bash (read-only commands: `git status`, `find . -type f`, `wc -l`).
- Explicitly blocked: production-source Edit/Write, `git add` / `git commit` / `git push`, Agent spawns (/onboard does не spawn subagents).

**Phase 2 (Map):**
- Allowed: Read / Write (для `_CODEBASE_MAP.md` only — scope к `.geniro/planning/**` via existing safety hooks).
- Allowed: `update-semantic` и `emit-learning` helper invocations.
- Explicitly blocked: production-source Edit/Write, `git add` / `git commit` / `git push`.

Existing safety hooks apply across all phases (file-protection / git-guardrail / `.geniro/` deletion guard).

---

## Anti-rationalization (P-MP-1 closure)

Per master plan P-MP-1 — every milestone closes с an explicit anti-pattern check. Preserves 4 rows verbatim от pre-M9 + M9 §16.1 additions + cross-cutting LLM rows.

| Your reasoning | Why it's wrong |
|---|---|
| "Let me document every file" | Exhaustive maps are unreadable. Sample key files, focus on structure и relationships. |
| "I need more detail on this module" | The codebase map captures architecture, not implementation. Keep it под 1000 lines. |
| "The code is self-documenting" | Code shows what, not why. Note the critical paths (user flow, deploy flow) и what's unclear. |
| "I'll create the map и move on" | А map nobody references is waste. Update it as you learn more, reference it when planning. |
| "The repo has 5000 files but I'll just scan everything — better safe than sorry." | Mass-scan violates P-M9-2. The ≤50-file default cap exists для tokens + speed. Fire the §1.3 AUQ — user picks `--focus`, expansion, или truncation. Don't silently broad-scan. |
| "Quick mode would be nice here — I'll informally produce а focus-only output." | Quick mode dropped per design Q4. The single-mode flow + `--focus` scope-limiter covers all legitimate needs. Inventing а quick-mode bypass mid-run breaks the single-mode contract. |
| "Add а wall-time kill cap so long-running discovery aborts cleanly." | Class-A hard caps abort legitimate complex discovery mid-stride. M9 §2.3 quality-first — no Class-A caps. §1.3 ≤50-file gate escalates к user via AUQ. User has agency. |
| "/onboard scan should bypass the 50-file cap silently if the codebase is monorepo-scale." | Master plan §344 P-M9-2 is explicit — ≤50 default; user-confirmable expansion. Silent bypass defeats the cost-control intent. |
| "Defer M3 compaction-survival к downstream skills — /onboard is mostly scan." | M3 contract IS /onboard's contract — state.md frontmatter (M1 §T1), `approvals[]` (P-M1-1 + М3 Block 5d), `## Tool log`, `## Errors`, `## Open Questions`. Без them, compaction mid-scan loses scan progress; user re-runs от scratch. |
| "Audit trail isn't needed для local /onboard runs — the map IS the record." | The map captures architecture; the state.md `## Tool log` captures the scan process (which directories scanned, permissions errors, time taken). Без the log, debugging а failed onboard is impossible. М3 SessionStart re-injects on compaction; без log, post-mortem requires re-running the scan от scratch. |

## Anti-pattern check (P-MP-1)

| # | Anti-pattern | /onboard M9 status |
|---|---|---|
| 1 | One giant prompt | ✅ Avoided — orchestration shell + delegated helpers (load-semantic, emit-learning, update-semantic) |
| 2 | One giant tool | ✅ N/A |
| 3 | Unbounded autonomous loop | ✅ §1.3 P-M9-2 cap + AUQ escalation gates |
| 4 | Autonomous external sends в first release | ✅ N/A — /onboard ships no commits / no PRs / no posts |
| 5 | No approval state | ✅ §1.3 approvals[] (P-M1-1 category `expand_scope`) + M3 Block 5d render |
| 6 | No durable plans or goals | ✅ State.md mandatory; M1 §T1 schema |
| 7 | No compaction strategy | ✅ M3 §6 body sections + SessionStart re-injects |
| 8 | All connectors loaded up front | ✅ N/A |
| 9 | High-risk tools without policy | ✅ §ACI per-phase + existing safety hooks |
| 10 | Subagents before single-agent MVP measured | ✅ N/A — /onboard is solo |
| 11 | Dynamic timestamps в plugin-distributed Markdown bodies | ✅ Verified — no runtime timestamps in this SKILL.md body |
| 12 | Non-deterministic agent registration order | ✅ N/A — no agents spawned |

---

## CODEBASE_MAP.md format example

```markdown
# Codebase Map: [Project Name]

**Generated:** [date]
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

- README.md – Project overview и setup
- package.json – Dependencies и scripts
- db/schema.sql – Database schema reference
```

---

## Definition of Done

For each onboarding, confirm:

- [ ] `_CODEBASE_MAP.md` created at `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`
- [ ] Project Overview section completed
- [ ] Directory Structure documented с key folders
- [ ] At least 3 critical paths traced и documented
- [ ] Architecture Patterns identified и listed
- [ ] Conventions и defaults recorded
- [ ] Known Issues и Tech Debt noted
- [ ] Entry Points listed (how к run, test, deploy)
- [ ] Map is <1000 lines и skimmable в 5 minutes (use `--focus` для large repos)
- [ ] L3 `_CODEBASE_MAP.md` updated via `update-semantic`
- [ ] L2 `discovery` emit fired per §2.3 trigger conditions
- [ ] User routed к а next-step command via `AskUserQuestion` (M5/M9/M4 options per §2.4)
- [ ] State.md cleaned up per §2.5

---

## When к Use This Skill

**Use `/geniro:onboard`:**
- Starting work on а new/unfamiliar codebase
- Returning к а project after months away
- Onboarding а new team member
- Planning а major change и need context
- Trying к understand impact of а change
- Need к explain architecture к someone else

**Don't use:**
- Quick bug fix в familiar code → use `/geniro:implement` (consumes а spec.md from /plan OR inline-task mode)
- Bug с unclear root cause → use `/geniro:debug` (M7 — investigates и proposes; hands the fix к `/geniro:implement`)
- Need full implementation guidance → use `/geniro:implement` (M4)
- Just need к answer а specific question → ask directly OR run `/geniro:investigate <question>`

---

## Examples

### Example 1: New к а Monorepo
```
/geniro:onboard --depth 2 --focus auth,api
```
→ Scan monorepo structure at depth 2
→ Focus on auth и api services
→ Generate `_CODEBASE_MAP.md` highlighting those modules
→ Output: directory tree, module relationships, auth/api critical paths

### Example 2: Returning After 6 Months
```
/geniro:onboard
```
→ Scan entire codebase structure
→ Generate quick refresh of architecture
→ Note what's changed since last visit (L3 diff against prior `_CODEBASE_MAP.md`)
→ Map is ready as reference для the session

### Example 3: Planning а Feature
```
/geniro:onboard --focus database,models
```
→ Focus on data layer и models
→ Understand current schema и relationships
→ Use map к plan где new feature fits
→ Trace existing data flow patterns
