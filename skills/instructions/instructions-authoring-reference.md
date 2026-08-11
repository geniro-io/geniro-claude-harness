# Instructions — authoring reference

Detail sections extracted from `${CLAUDE_PLUGIN_ROOT}/skills/instructions/SKILL.md`: the per-scope file shapes and create scaffolds, the instruction-writing principles, and the per-skill phase enums validate-mode checks against. The orchestrator reads this file when SKILL.md references one of the sections below by name.

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
### After <legal anchor — §5>
<!-- Steps to run at the named phase -->

## Constraints
- Hard limits

## Data Sources
<!-- Optional. Read-only sources to cross-check load-bearing facts against. -->
- **<label>** (confirms: <what kind of fact>) — `<read-only shell command>` OR MCP tool `<name>` OR action `<name>`

## Verification Surface
<!-- Optional. What each project check covers, and what it leaves uncovered. -->
- `<check command>` — covers: <ground the check demonstrates>. Does not cover: <ground it leaves unproven>
```

**`memory`** — the dedicated `.geniro/instructions/memory.md`, carrying the `## Memory Backend` block only:

```markdown
# Memory

## Memory Backend
<!-- Optional. Route agent learnings through a custom backend. Default = built-in .geniro file. The `read` tool has to be read-only — it runs unattended during retrieval. -->
- layer: learnings   # mode: mirror|replace; write: <mcp tool>; read: <read-only mcp tool>
```

**`review-extra/<slug>`** — YAML frontmatter plus a `# Criteria` body. Field constraints: SKILL.md §Frontmatter field reference.

```yaml
---
slug: sql-bindings # REQUIRED; matches filename; must NOT collide with built-in dimensions
description: All SQL queries use parameterized bindings, never string concatenation
model: sonnet # OPTIONAL; haiku|sonnet|opus|inherit (+ auto outside Claude Code); omitted = inherit (orchestrator tier)
paths: # OPTIONAL; list of globs; absent = always fires
- "**/*.sql"
- "**/dao/*.{ts,py}"
severity-default: HIGH # OPTIONAL; default MEDIUM
# requires-context: "Fetch the live Notion incident report (latest entry) and list its patterns." # OPTIONAL; live external data the orchestrator fetches + injects (fetched once, before spawn)
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

### After ship
- (example: "Post a summary to #eng-ships and open a follow-up issue for any deferred TODO")

## Constraints

- Maximum PR size: 500 lines changed (warn user if exceeded; do not block)

## Data Sources
<!-- append the Data-Sources stub below -->

## Verification Surface
<!-- append the Verification-Surface stub below -->
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

## Verification Surface
<!-- append the Verification-Surface stub below -->
```

**Data-Sources stub** — the single copy. Append it verbatim under the `## Data Sources` heading of the `global` and per-skill scaffolds (not `code-style` or `review-extra`, which are rules-only / criteria-only) so users discover the verification primitive. Leave the entries commented — an empty block is the safe default.

```markdown
<!-- Optional. Read-only sources to cross-check load-bearing facts against (task statuses, the spec's cited claims). Commands have to be read-only — the verification step runs them unattended. Contract: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md -->
<!-- - **prod-db** (confirms: task / feature status) — `psql "$DATABASE_URL_RO" -c "SELECT ..."` -->
<!-- - **deploy-state** (confirms: did it ship?) — MCP tool `mcp__deploys__get_release_state` -->
```

**Verification-Surface stub** — the single copy, appended verbatim under the `## Verification Surface` heading of the same two scaffolds (`global` and per-skill), on the same commented-by-default basis. Both clauses are required per entry: the does-not-cover half is what bounds how wide a claim about a green run may be stated, and it is the half a reader cannot derive from the command name.

```markdown
<!-- Optional. One bullet per check: the command, the ground it covers, and the ground it does NOT cover. A MANUAL row names ground no command reaches. Contract: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-surface.md -->
<!-- - `pnpm test:unit` — covers: logic inside a module, mocked at every boundary. Does not cover: the wiring between modules, or anything the mocks stand in for. -->
<!-- - MANUAL — the payment flow against the provider sandbox. No automated layer covers it. -->
```

**`memory.md` scaffold:**

```markdown
# Memory

## Memory Backend
<!-- Optional. Route agent learnings (L2) through a custom backend (a memory MCP, vector store, knowledge graph). Default = built-in .geniro/knowledge/learnings.jsonl. The `read` tool has to be read-only — it runs unattended during retrieval. Contract: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md -->
<!-- - layer: learnings -->
<!--   mode: mirror            # mirror = file + backend (default); replace = backend only -->
<!--   write: mcp tool `mcp__memory__upsert` -->
<!--   read:  mcp tool `mcp__memory__search` -->
```

The `memory.md` scaffold carries ONLY the commented `## Memory Backend` stub — no Rules/Constraints. Leave it commented; an absent block means the built-in file.

---

## 2. Writing effective instructions

### Rule writing

- **State the criterion, not a prohibition** — "Match the error-handling style of the module you're editing" beats "NEVER use bare try/except". A criterion applies to cases you didn't anticipate; a prohibition only covers the one you named, and a capable model reads emphatic caps on a judgment call as a signal to stop thinking rather than to think harder.
- **Give the reason when a rule is one the model would otherwise talk itself out of** — "Run `pnpm test` before committing — the pre-push hook assumes green tests and skipping leaves CI reviewing stale code." Routine facts (paths, commands, names) need no reason.
- **Write the rule, not the case for it.** That reason stays; what does not is the argument built around it — a sources list, a note on what evidence the rule rests on, a rebuttal of the approach you rejected, or the history of how the rule got here. None of it changes what a run does, and all of it is paid for on every load. Put it in the commit message.
- **Keep the hard bar hard.** Where the cost is data loss, money, or an outward-facing effect, say so plainly and directly — "Never run `db:reset` against a non-local `DATABASE_URL`". These are the cases where an unambiguous bar is doing real work; they are the exception, not the house style.
- **One rule = one constraint** — don't combine multiple ideas in a single bullet
- **Be specific, not vague** — "Run `pnpm test` before committing" not "Make sure tests pass"
- **Include the command or path** — name them exactly
- **Focus on what the AI can't infer** — don't repeat things obvious from the codebase

Every rule here is loaded into the model's context on each skill run that matches its scope, alongside the plugin's own instructions. Rules that are plausible but don't apply to the task in hand measurably degrade rule-following, so a rule that only matters for one kind of work belongs in a scoped file rather than in `global.md`.

### Additional Steps writing

- **Use one of the legal anchors** from §5 — `validate` rejects anything else, including a real phase name that just has no read site
- **Keep steps actionable** — each step describes a concrete action
- **Limit to 2-3 steps per phase** — too many slow down workflow and dilute attention
- **The legal anchors:** `After ship` (implement, post-ship follow-up), `After verify` (refactor wrap-up), `After user-approve` (plan, post-approval)
- **Per-worktree bootstrap:** put a setup command that a fresh worktree needs (e.g. building a per-worktree code index for an MCP) under `### After worktree-setup` in `global.md` — it runs once, in the orchestrator, right after any skill creates a new worktree and before subagent fan-out

### Constraint writing

- **Quantify where possible** — "Maximum 500 lines changed per PR" not "Keep PRs small"
- **State the consequence** — "Database migrations must be backwards-compatible — breaking migrations block deploy"
- **Constraints are hard limits** — skills treat these as non-negotiable

---

## 3. File-size guidance

**The enforced bar is owned by `/geniro:instructions validate`** (`mode-validate.md` §Step 2), which reports a LOW-severity split suggestion past it, overridable via `--max-lines N` or `GENIRO_INSTRUCTIONS_MAX_LINES`. A somewhat larger file that's well-organized and all-load-bearing is fine — the check is advisory, not a hard limit; consider splitting by scope or by topic once it fires.

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

An `Additional Steps` subsection must name a phase that a skill actually reads custom steps at — `### After <phase>`, lowercase-hyphenated (subsection prose may use any case; validate normalizes). Each skill's own state machine has more named phases than this; the table below is narrower on purpose; it lists only the anchors a skill actually reads `## Additional Steps` at, not every phase the skill passes through. Naming any other phase — a real one with no read site, a dropped one, or the `Before <phase>` form (no skill reads that prefix) — fails silently in the loader: the step is parsed, looks legal at a glance, and is never reached, with no error at the point the user would notice. `validate` flags anything outside this table (MEDIUM, below) so the gap surfaces at authoring time instead of staying invisible until someone notices the step never ran.

| Scope | Legal anchor | Execution site |
|---|---|---|
| `implement` | `After ship` | `implement/phase-3-ship.md` §8.2 / `implement-reference.md` §Custom post-ship steps |
| `plan` | `After user-approve` (post-approval/commit — e.g. duplicate the plan into OpenSpec) | `plan/loop-phase-8-user-approval.md` §8.6 |
| `refactor` | `After verify` | `refactor/phase-3-verify.md` §3.6 |
| `global` | `After worktree-setup` (cross-skill; fires once, in the orchestrator, right after any skill creates a new worktree) | branch-freshness §3.1 and review triage |
| `review`, `resolve`, `debug`, `onboard`, `investigate`, `reflect` | none — Rules and Constraints only, no Additional Steps anchor | n/a |

Free-form subsections raise `LOW`. Subsections naming a real phase this skill has (or a dropped one, e.g. `After Phase 4 (Implement)`) that isn't in this table raise `MEDIUM` — that phase exists or existed, but nothing reads a custom step there.

**Already-authored `### Before ship` / `### After implement` / any other now-dropped anchor.** `validate` never mutates a file (§"No auto-fix" in `mode-validate.md`), so an existing subsection under a dropped anchor stays on disk exactly as written — the next `validate` run reports it (MEDIUM, per above) instead of silently no-op'ing it forever. Move the content to the scope's legal anchor if the step is still wanted; there is currently no anchor for a genuine pre-ship gate — say so to the user rather than remapping to `After ship`, which changes when the step runs.
