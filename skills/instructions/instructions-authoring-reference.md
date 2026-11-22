# Instructions — authoring reference

Detail sections for `${CLAUDE_PLUGIN_ROOT}/skills/instructions/SKILL.md`: the per-scope file shapes and create scaffolds, the instruction-writing principles, and the insertion-point catalogue validate-mode checks against. Read the section SKILL.md names.

## Contents

1. File shapes and scope-specific scaffolds — singleton / `memory` / `review-extra`, the scaffold rule, the stubs, the `memory` scaffold
2. Writing effective instructions — rule / step / constraint principles
3. File-size guidance
4. What goes here vs `.claude/rules/` vs CLAUDE.md
5. Insertion-point catalogue — every block and anchor a scope takes, who reads it, when it takes effect

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
```

**`review-extra/<slug>`** — YAML frontmatter plus a `# Criteria` body. Field constraints: `instructions-review-extra.md` §Frontmatter field reference.

```yaml
---
slug: sql-bindings # REQUIRED; matches filename; must NOT collide with built-in dimensions
description: All SQL queries use parameterized bindings, never string concatenation
model: sonnet # OPTIONAL; haiku|sonnet|opus|fable|inherit (+ auto = inherit); omitted = inherit (orchestrator tier)
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

A singleton scope's scaffold opens with `# Custom Instructions`, then the headings §5 grants it: `## Rules`, `## Additional Steps` with one `### After <anchor>` per catalogued anchor (omitted when it has none), `## Constraints`, and `## Data Sources` / `## Verification Surface` carrying their stubs where §5 lists the scope. Headings only; every bullet counts as a real rule.

**Data-Sources stub** — the single copy. Append it verbatim under the `## Data Sources` heading of the scaffolds §5 lists for the block (`_VIF_DATA_SOURCES_SCOPES` in `${CLAUDE_PLUGIN_ROOT}/lib/validate-instructions-file.sh`), so users discover the verification primitive. Leave the entries commented — an empty block is the safe default.

```markdown
<!-- Optional. Read-only sources to cross-check load-bearing facts against (task statuses, the spec's cited claims). Commands have to be read-only — the verification step runs them unattended. Contract: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md -->
<!-- - **prod-db** (confirms: task / feature status) — `psql "$DATABASE_URL_RO" -c "SELECT ..."` -->
<!-- - **deploy-state** (confirms: did it ship?) — MCP tool `mcp__deploys__get_release_state` -->
```

**Verification-Surface stub** — the single copy, appended verbatim under the `## Verification Surface` heading of the scaffolds §5 lists for the block (`_VIF_VERIFICATION_SURFACE_SCOPES`), on the same commented-by-default basis. Both clauses are required per entry: the does-not-cover half is what bounds how wide a claim about a green run may be stated, and it is the half a reader cannot derive from the command name.

```markdown
<!-- Optional. One bullet per check: the command, the ground it covers, and the ground it does NOT cover. A MANUAL row names ground no command reaches. Contract: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-surface.md -->
<!-- - `pnpm test:unit` — covers: logic inside a module, mocked at every boundary. Does not cover: the wiring between modules, or anything the mocks stand in for. -->
<!-- - MANUAL — the payment flow against the provider sandbox. No automated layer covers it. -->
```

**`memory.md` scaffold** (the dedicated `.geniro/instructions/memory.md`):

```markdown
# Memory

## Memory Backend
<!-- Optional. Route agent learnings (L2) through a custom backend (a memory MCP, vector store, knowledge graph). Default = built-in .geniro/knowledge/learnings.jsonl. The `read` tool has to be read-only — it runs unattended during retrieval. Contract: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md -->
<!-- - layer: learnings -->
<!--   mode: mirror            # mirror = file + backend (default); replace = backend only -->
<!--   write: mcp tool `mcp__memory__upsert` -->
<!--   read:  mcp tool `mcp__memory__search` -->
```

The `memory.md` scaffold carries ONLY the commented `## Memory Backend` stub — no Rules/Constraints; an absent block means the built-in file.

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

- **Use an anchor §5 lists for the scope** — `validate` rejects anything else, including a real phase name with no read site; §5 also says when each anchor fires and which worktree bootstrap goes under `After worktree-setup`
- **Keep steps actionable** — each step describes a concrete action
- **Limit to 2-3 steps per phase** — too many slow down workflow and dilute attention

### Constraint writing

- **Quantify where possible** — "Reject uploads over 10 MB" not "Keep uploads small"
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

## 5. Insertion-point catalogue

Every place a custom instruction takes effect, grouped by scope. An `Additional Steps` subsection must be `### After <anchor>` (validate normalizes case) naming an anchor below; any other fails silently in the loader and `validate` flags it. An external instructions dir (`GENIRO_INSTRUCTIONS_DIR` / `instructions_dir`), when set, replaces the in-repo files.

| Scope | Block / anchor | Read by | Takes effect | Does not reach |
|---|---|---|---|---|
| `global` | `## Rules`, `## Constraints` | every skill, both load tiers; self-loaded by the reviewer, codebase-explorer, codebase-research, knowledge-retrieval and reflection agents | from the skill's first action, before its first question, through every phase | the finding-verifier and test-runner agents |
| `global` | event anchor `After worktree-setup` — a per-worktree bootstrap, e.g. a code index for an MCP | implement, debug, review (new worktree, or re-entering its review worktree), investigate (inside an existing linked worktree) — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` §3.1 | once, in the orchestrator, right after the worktree is created or entered, before any subagent fan-out | implement and debug resuming into an existing worktree |
| `code-style` | `## Rules`, `## Constraints` | every `LOAD_TIER: pipeline` skill (plan, implement, review, resolve, debug, refactor, onboard, investigate, reflect) and every reviewer spawn | whenever those skills write or review code | operational skills (setup, instructions, actions, update, audit-instructions) |
| `memory` | `## Memory Backend` | every skill's learnings reads and writes, every load tier; the session-restore hook | each learnings read or write | none |
| `<skill>`: implement, plan, review, resolve, debug, refactor, onboard, investigate, reflect | `## Rules`, `## Constraints` | that skill's orchestrator; forwarded to subagents only where the skill passes them on (implement Phase 2 delegates) | from that skill's first action, before its first question, through every phase | spawned reviewers (they self-load only `global.md` and `code-style.md`) and explorers (only `global.md`); other skills |
| `plan` | `After explore` | Phase 1 §1.5 (`plan/loop-phase-1-explore.md`) | after code research and the prior-work check, before the first design question; no question is asked during the research wait | none |
| `plan` | `After user-approve` | Phase 8 §8.6 | after the plan is approved and committed, before the handoff | none |
| `implement` | `After analyze` | Phase 1 Step 12.6 | after the spec or handoff questions and spec fact-check (or the inline-task parse), before the inline plan is written or any file is edited | none |
| `implement` | `After ship` | Phase 3 step 8.2 "Custom post-ship steps" (`implement/phase-3-ship.md`) | after the ship step (commit, plus push/PR when chosen) and the tracker update, before cleanup | runs that stop after review |
| `refactor` | `After verify` | Phase 3 §3.6 | after the summary and learnings, before the run ends; the step cannot commit or push | runs that refactored nothing |
| `global`, `plan`, `implement`, `review`, `resolve`, `debug`, `investigate` | `## Data Sources` | fact checks; list enforced by `_VIF_DATA_SOURCES_SCOPES` in `lib/validate-instructions-file.sh` | when the run verifies a load-bearing fact | other scopes (validate flags the block) |
| `global`, `implement`, `review`, `debug`, `investigate`, `refactor` | `## Verification Surface` | a run stating what a check proved; list enforced by `_VIF_VERIFICATION_SURFACE_SCOPES` | at each scoped claim | reviewer subagents (they see only `global`'s); other scopes |
| `review-extra/<slug>` | custom reviewer file | `/geniro:review` (every run, filtered by `paths`), `/geniro:implement` self-review (round 1; later rounds only on critical or high findings), `/geniro:refactor` verify (Medium and Big only) | spawned beside the built-in review dimensions | Trivial and Small refactors; implement rounds 2+ without critical or high findings |
| `review`, `resolve`, `debug`, `onboard`, `investigate`, `reflect` | no step anchor | n/a | Rules and Constraints only, plus the blocks above where listed | n/a |

A free-form subsection raises `LOW`; one naming a real phase that has no anchor above (or a dropped one, e.g. `After Phase 4 (Implement)`) raises `MEDIUM`. `validate` never mutates, so an already-authored `### Before ship` stays on disk and is reported each run. There is no pre-ship anchor: tell the user rather than remapping to `After ship`, which changes when the step runs.

**Not here:** file-pattern code rules go in `.claude/rules/<scope>.md` with `paths:` (`/geniro:reflect` or by hand); always-loaded project essentials in CLAUDE.md (`/geniro:setup`); tracker hooks such as `### On task start` in `.geniro/workflow/<kind>.md` (`/geniro:setup`); reusable automations in `.geniro/actions/` (`/geniro:actions`).
