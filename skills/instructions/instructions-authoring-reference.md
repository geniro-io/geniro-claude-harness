# Instructions — Authoring Reference

Detail sections extracted from `skills/instructions/SKILL.md`: the per-scope file shapes and create scaffolds, the instruction-writing principles, and the per-skill phase enums validate-mode checks against. The orchestrator reads this file when SKILL.md references one of the sections below by name.

## Contents

1. File shapes and scope-specific scaffolds — singleton / `memory` / `review-extra`, plus `code-style` / `implement` / `global` / `memory` scaffolds
2. Writing effective instructions — rule / step / constraint principles
3. File-size guidance
4. What goes here vs `.claude/rules/` vs CLAUDE.md
5. Per-skill phase enums — the `Additional Steps` anchors validate-mode accepts

---

## 1. File shapes and scope-specific scaffolds

### File shapes

**Singleton scopes** (`global`, `code-style`, and every per-skill scope):

```markdown
# Custom Instructions

## Rules
- Clear, single-line constraints

## Additional Steps
### After <phase-enum-value>
<!-- Steps to run at the named phase -->

## Constraints
- Hard limits

## Data Sources
<!-- Optional. Read-only sources to cross-check load-bearing facts against. -->
- **<label>** (confirms: <what kind of fact>) — `<read-only shell command>` OR MCP tool `<name>` OR action `<name>`
```

**`memory`** — the dedicated `.geniro/instructions/memory.md`, carrying the `## Memory Backend` block only:

```markdown
# Memory

## Memory Backend
<!-- Optional. Route agent learnings through a custom backend. Default = built-in .geniro file. The `read` tool MUST be read-only. -->
- layer: learnings   # mode: mirror|replace; write: <mcp tool>; read: <read-only mcp tool>
```

**`review-extra/<slug>`** — YAML frontmatter plus a `# Criteria` body. Field constraints: SKILL.md §Frontmatter field reference.

```yaml
---
slug: sql-bindings # REQUIRED; matches filename; must NOT collide with built-in dimensions
description: All SQL queries use parameterized bindings, never string concatenation
model: sonnet # OPTIONAL; haiku|sonnet|opus|inherit; omitted = inherit (orchestrator tier)
paths: # OPTIONAL; list of globs; absent = always fires
- "**/*.sql"
- "**/dao/*.{ts,py}"
severity-default: HIGH # OPTIONAL; default MEDIUM
# requires-context: "Fetch the live Notion incident report (latest entry) and list its patterns." # OPTIONAL; live external data the orchestrator fetches + injects (subagents can't call MCP)
---

# Criteria

What to flag:
-...

What to NOT flag:
-...
```

### Scaffolds

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
<!-- append the Data-Sources stub below -->
```

**`global.md` scaffold:**

```markdown
# Custom Instructions

## Rules

- (none — add project-wide rules here)

## Constraints

- (none — add project-wide hard limits here)

## Data Sources
<!-- append the Data-Sources stub below -->
```

**Data-Sources stub** — the single copy. Append it verbatim under the `## Data Sources` heading of the `global` and per-skill scaffolds (not `code-style` or `review-extra`, which are rules-only / criteria-only) so users discover the verification primitive. Leave the entries commented — an empty block is the safe default.

```markdown
<!-- Optional. Read-only sources to cross-check load-bearing facts against (task statuses, the spec's cited claims). Commands MUST be read-only. Contract: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md -->
<!-- - **prod-db** (confirms: task / feature status) — `psql "$DATABASE_URL_RO" -c "SELECT ..."` -->
<!-- - **deploy-state** (confirms: did it ship?) — MCP tool `mcp__deploys__get_release_state` -->
```

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

- **State the criterion, not a prohibition** — "Match the error-handling style of the module you're editing" beats "NEVER use bare try/except". A criterion applies to cases you didn't anticipate; a prohibition only covers the one you named, and a capable model reads emphatic caps on a judgment call as a signal to stop thinking rather than to think harder.
- **Give the reason when a rule is one the model would otherwise talk itself out of** — "Run `pnpm test` before committing — the pre-push hook assumes green tests and skipping leaves CI reviewing stale code." Routine facts (paths, commands, names) need no reason.
- **Keep the hard bar hard.** Where the cost is data loss, money, or an outward-facing effect, say so plainly and directly — "Never run `db:reset` against a non-local `DATABASE_URL`". These are the cases where an unambiguous bar is doing real work; they are the exception, not the house style.
- **One rule = one constraint** — don't combine multiple ideas in a single bullet
- **Be specific, not vague** — "Run `pnpm test` before committing" not "Make sure tests pass"
- **Include the command or path** — name them exactly
- **Focus on what the AI can't infer** — don't repeat things obvious from the codebase

Every rule here is loaded into the model's context on each skill run that matches its scope, alongside the plugin's own instructions. Rules that are plausible but don't apply to the task in hand measurably degrade rule-following, so a rule that only matters for one kind of work belongs in a scoped file rather than in `global.md`.

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

**Soft guidance: when an instruction file passes ~2,500 words, consider splitting** (by scope or by topic). A somewhat larger file that's well-organized and all-load-bearing is fine.

Count words, not lines — a table-dense file and a prose-dense file with the same line count differ by 2-3× in what they actually cost. `wc -w` on the file is the measure.

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

---

## 5. Per-skill phase enums

An `Additional Steps` subsection must name a real phase from the owning skill's state machine — `### After <phase>` / `### Before <phase>`, lowercase-hyphenated (subsection prose may use any case; validate normalizes). A subsection naming a phase that does not exist fails silently in the loader: the step is never reached and the user gets no error, which is why validate-mode checks it.

**Maintenance:** each row below mirrors that skill's `## State machine` section in `skills/<skill>/SKILL.md`, which is the source of truth. A skill that adds or renames a phase updates its own state machine first, then this row.

| Scope | Phase enum | Example subsection names |
|---|---|---|
| `implement` | `analyze \| implement \| self-review \| ship \| ship-committed-only \| self-review-only \| phase-2-escalated \| phase-3-escalated \| debug-handoff \| done \| aborted` | `After analyze`, `After implement`, `After self-review`, `Before ship` |
| `plan` | `mode-detect \| problem-discovery \| explore \| visual-companion \| clarify \| approaches \| section-approve \| write-spec \| validate \| spec-challenge \| user-approve \| handoff \| done \| aborted` | `After explore`, `After clarify`, `After approaches`, `After write-spec`, `After user-approve` (post-approval/commit — e.g. duplicate the plan into OpenSpec) |
| `review` | `triage \| mechanical-prepass \| llm-spawn \| filter \| stratify \| persist \| action-gate \| done \| aborted \| escalated` | `After triage`, `After llm-spawn`, `After filter`, `Before action-gate` |
| `resolve` | `triage \| analyze \| clarify \| emit \| done \| aborted` | `After triage`, `After analyze`, `Before emit` |
| `debug` | `mode-detect \| investigate \| propose \| ship \| ship-summary-only \| phase-1-escalated \| phase-2-escalated \| adversarial-mode-detect \| adversarial-investigate \| adversarial-ship \| adversarial-aborted \| done \| aborted` | `After investigate`, `After propose`, `Before ship` |
| `refactor` | `plan \| apply \| verify \| verify-summary-only \| plan-escalated \| apply-escalated \| verify-escalated \| reverted \| routed \| adr-documented \| done \| aborted` | `After plan`, `After apply`, `Before verify` |
| `onboard` | `discover \| map \| map-truncated \| done \| aborted \| routed` | n/a — rules-only, no Additional Steps |
| `investigate` | `classify \| investigate \| present \| present-summary-only \| present-loop \| classify-escalated \| investigate-escalated \| done \| aborted \| routed` | n/a — rules-only, no Additional Steps |
| `reflect` | (stateless — no phase enum) | n/a — rules-only, no Additional Steps |
| `global` | (no phase enum — cross-skill) | `After worktree-setup` (the only permitted anchor; fires when a skill creates a new worktree) |

Free-form subsections raise `LOW`. Subsections naming a dropped phase (e.g. `After Phase 4 (Implement)`) raise `MEDIUM`.
