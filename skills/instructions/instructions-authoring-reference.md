# Instructions — Authoring Reference

Detail sections extracted from `skills/instructions/SKILL.md`: the scope-specific create scaffolds and the instruction-writing principles. The orchestrator reads this file when SKILL.md references one of the sections below by name.

## Contents

1. Scope-specific scaffolds — `code-style` / `implement` / `global` / `memory`
2. Writing effective instructions — rule / step / constraint principles
3. File-size guidance
4. What goes here vs `.claude/rules/` vs CLAUDE.md

---

## 1. Scope-specific scaffolds

**`code-style.md` scaffold:**

```markdown
# Custom Instructions

## Rules

- Use lowercase-hyphen for component file names (e.g., `user-profile.tsx`, not `UserProfile.tsx`).
- Prefer named exports over default exports for tree-shaking.

## Constraints

- No `any` type without an inline `// reason:...` comment.
```

**`implement.md` scaffold** (shows phase-boundary structure):

```markdown
# Custom Instructions

## Rules

- (none — add project-specific rules here)

## Additional Steps

### After implement
- (example: "Run npm run codegen before declaring implementation complete")

### Before ship
- (example: "Ensure CHANGELOG.md has an entry for the change")

## Constraints

- Maximum PR size: 500 lines changed (warn user if exceeded; do not block)

## Data Sources
<!-- Optional. Read-only sources to cross-check load-bearing facts against (task statuses, the spec's cited claims). Commands MUST be read-only. Contract: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md -->
<!-- - **prod-db** (confirms: task / feature status) — `psql "$DATABASE_URL_RO" -c "SELECT ..."` -->
<!-- - **deploy-state** (confirms: did it ship?) — MCP tool `mcp__deploys__get_release_state` -->
```

**`global.md` scaffold:**

```markdown
# Custom Instructions

## Rules

- (none — add project-wide rules here)

## Constraints

- (none — add project-wide hard limits here)

## Data Sources
<!-- Optional. Read-only sources to cross-check load-bearing facts against (task statuses, the spec's cited claims). Commands MUST be read-only. Contract: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md -->
<!-- - **prod-db** (confirms: task / feature status) — `psql "$DATABASE_URL_RO" -c "SELECT ..."` -->
<!-- - **deploy-state** (confirms: did it ship?) — MCP tool `mcp__deploys__get_release_state` -->
```

Include the commented `## Data Sources` stub in the `global` and per-skill scaffolds (not `code-style` or `review-extra`, which are rules-only / criteria-only) so users discover the verification primitive. Leave the stub entries commented — an empty block is the safe default.

**`memory.md` scaffold:**

```markdown
# Memory

## Memory Backend
<!-- Optional. Route agent learnings (L2) through a custom backend (a memory MCP, vector store, knowledge graph). Default = built-in .geniro/knowledge/learnings.jsonl. The `read` tool MUST be read-only. Contract: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md -->
<!-- - layer: learnings -->
<!--   mode: mirror            # mirror = file + backend (default); replace = backend only -->
<!--   write: mcp tool `mcp__memory__upsert` -->
<!--   read:  mcp tool `mcp__memory__search` -->
```

The `memory.md` scaffold carries ONLY the commented `## Memory Backend` stub — no Rules/Constraints. Leave it commented; an absent block means the built-in file.

---

## 2. Writing effective instructions

### Rule Writing

- **Use strong, unambiguous language** — "Always", "Never", "Must" not "Consider", "Try to", "Should"
- **One rule = one constraint** — don't combine multiple ideas in a single bullet
- **Be specific, not vague** — "Run `pnpm test` before committing" not "Make sure tests pass"
- **Include the command or path** — name them exactly
- **Focus on what the AI can't infer** — don't repeat things obvious from the codebase

### Additional Steps Writing

- **Use exact phase enum values** from the per-skill mapping — `validate` checks these (the cross-skill `### After worktree-setup` anchor is the sole non-phase exception, below)
- **Keep steps actionable** — each step describes a concrete action
- **Limit to 2-3 steps per phase** — too many slow down workflow and dilute attention
- **Best insertion points:** `Before ship` (quality gates), `After implement` (post-checks), `After verify` (refactor wrap-up)
- **Per-worktree bootstrap:** put a setup command that a fresh worktree needs (e.g. building a per-worktree code index for an MCP) under `### After worktree-setup` in `global.md` — it runs once, in the orchestrator, right after any skill creates a new worktree and before subagent fan-out

### Constraint Writing

- **Quantify where possible** — "Maximum 400 lines changed per PR" not "Keep PRs small"
- **State the consequence** — "Database migrations must be backwards-compatible — breaking migrations block deploy"
- **Constraints are hard limits** — skills treat these as non-negotiable

---

## 3. File-size guidance

**Soft guidance: when an instruction file passes ~300 lines, consider splitting** (by scope or by topic). A 350-line file that's well-organized and all-load-bearing is fine.

---

## 4. What goes here vs `.claude/rules/` vs CLAUDE.md

- **`.geniro/instructions/<skill>.md`** — skill-scoped rules at phase boundaries
- **`.geniro/instructions/code-style.md`** — cross-cutting code-style rules at every Geniro code-writing/review step
- **`.claude/rules/<scope>.md` with `paths:`** — file-pattern-scoped, Anthropic-native
- **CLAUDE.md** — always-loaded essentials only

**What NOT to put in `.geniro/instructions/<skill>.md` or `code-style.md`:**

- Per-file-pattern code rules → `.claude/rules/<scope>.md`
- Tech stack info → CLAUDE.md (detected by `/geniro:setup`)
- Build/test/lint commands → CLAUDE.md
- Project structure facts → CLAUDE.md
- Compaction-surviving global gates → CLAUDE.md
- Temporary rules → conversation context
- Rules for skills that don't load instructions (operational skills)
