---
name: geniro-instructions
description: "Use when managing Geniro project rules: phase-boundary skill rules, code-style rules, Data Sources, Verification Surface, or a Memory Backend (e.g. an MCP). Ops: list/create/edit/validate/delete. Skip for per-file-pattern rules (.claude/rules/)."
context: main
---
<!-- Generated from skills/instructions/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->


# Instructions: custom instruction management

## Contents

- Loop invariants
- Anti-rationalization
- Definition of done
- Budgets — quality-first
- ACI per-phase tool surface
- Memory I/O
- Termination case → state mapping
- Valid scope set
- File shapes
- Phase 1 — parse intent, resolve scope, dispatch to a mode
- Writing effective instructions
- Cross-references

---

Stateless loop: **Parse → Execute → Done** — every invocation is a single transaction with no state file. CRUD frontend over `.geniro/instructions/` — the L4 procedural memory layer. Five modes: `list`, `create`, `edit`, `validate`, `delete`; Phase 1 resolves exactly one of them per invocation.

**Phase body.** Phase 1's Steps live in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-parse.md`. Read it on entry to the phase, and again on any resumption of it, including after a compaction. That Read is the phase's first action and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the phase file holds the gates and helper call sites, so work started before the Read runs outside them. A `create`/`edit` run also reads `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-block-type-reference.md` from there.

**Mode bodies.** Each mode's Steps live in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/mode-<op>.md`. Read the one Phase 1 dispatches to, and again on any resumption of it — the four it did not dispatch to are never read. That Read comes before any step of the mode and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the dispatched body is this run's phase body and holds every pause this skill declares. `delete` is where that matters most: `mode-delete.md` is the sole home of the destructive-op confirmation, and nothing else stops a per-file `rm -f` on `.geniro/instructions/<scope>.md`.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is a placeholder Claude Code substitutes into file references, not a shell export — it reads empty in Bash under every host, so an empty probe proves nothing (`CLAUDECODE` marks Claude Code). Resolve the root from the first rung that holds: the ancestor of this file's real path (symlinks followed) containing `.claude-plugin/plugin.json`; a copy of the referenced file beside this one (the Cursor build); a plugin checkout in the workspace. The run's first Bash call prints this file's real directory and checks the rungs against it; echo that output verbatim before anything else (a resolved ladder is bookkeeping: add a degraded-run notice only for a rung that failed), then substitute the resolved root everywhere and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. A path the output does not show did not resolve. Before deciding a step cannot run here, read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` — it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not:** name what is unavailable in your first message, run every phase and gate this skill declares, never let project rules stand in for its decision gates, and take no outward-facing action (ready PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

Code rules split three ways depending on **when** they should fire:

- **`.geniro/instructions/code-style.md`** — cross-cutting code-style rules that apply to **all code writing AND all code review** done by Geniro pipeline skills (loaded at code-writing/review phases regardless of file pattern).
- **`.claude/rules/<scope>.md` with `paths:` YAML frontmatter** — file-pattern-scoped rules (Anthropic-native, auto-loads on matching glob — fires even outside Geniro pipelines).
- **CLAUDE.md** — reserved for always-loaded essentials (commands, project structure, compaction-surviving gates) and should NOT carry code rules.

**After a compaction, re-Read the phase body and the dispatched mode's body file before continuing** — only the front-loaded prefix is re-attached, so a summary can drop the Steps while leaving this spine intact. If which mode was running is also gone, re-invoke and restart from Phase 1.

## Loop invariants

The canonical agent-loop invariants in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` apply throughout /geniro:instructions, with three skill-specific notes (an `#N` inside a note points at that file's numbered list):

1. **Invariant #2 (args validated)** — every write is preceded by scope validation (regex match) AND a file-existence check.
2. **Invariant #3 (permission before side-effect)** — create / edit / delete writes are AUQ-gated.
3. **Invariant #7 (errors → structured observations)** — there is no state file here, so errors surface inline in the final user message.

**No subagents** — `/geniro:instructions` runs entirely in the orchestrator (CRUD is too small for parallelism).

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll auto-fix `validate` issues to save the user a step" | Auto-fix would silently mutate user-authored content the user never agreed to change. `validate` reports; the user fixes via `edit`. |
| "I'll silently overwrite existing instruction file" | A silent overwrite destroys user-authored rules with no undo — present overwrite/edit-instead/cancel via AUQ on `create` against an existing file. |
| "I'll skip the per-skill phase-enum check because the user said `### After Phase 1`" | An old enum fails silently in the loader — the anchor never fires and the user believes the step is wired. Validate-mode catches it and suggests the canonical name. |
| "I'll spawn a subagent to do the freeform rule synthesis" | `/geniro:instructions` is a small CRUD frontend; a subagent adds no parallelism benefit and complicates the stateless single-transaction model for no return. |
| "I'll output the questions as plain text instead of `AskQuestion`" | A plain-text question has no structured answer to persist or resume against — the transaction stalls waiting on a reply the skill has no slot for. |
| "I'll rename a per-skill scope to something custom (e.g., implement → my-flow)" | A custom scope name resolves no loader path — no skill's Step 0 ever reads it, so the rules it holds silently never load. |
| "I'll skip showing the scope-specific scaffold to save tokens" | An empty new file with no scaffold reads as a mistake rather than a starting point — the user abandons it or miswrites the section shape. |

## Definition of done

- [ ] Mode detected from freeform arguments (or default to `list`)
- [ ] Scope(s) resolved — single or batch — within 3 AUQ retry cap
- [ ] The dispatched mode's body file was Read and its Steps completed
- [ ] User confirmed before running the destructive mode (`delete`)
- [ ] Validation checked structure, phase names, scope validity, dropped-skill refs, and description rules
- [ ] All user interactions used `AskQuestion` — no plain-text questions
- [ ] review-extra files validated against slug uniqueness, built-in collision, model/severity-default value sets, paths syntax, and count caps
- [ ] Scope-specific scaffold shown on `create` (not skipped)

## Budgets — quality-first

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. Soft gates: 3-retry scope ambiguity → final AUQ abort, `list --with-content` body truncation per `${CLAUDE_PLUGIN_ROOT}/skills/instructions/mode-list.md` §Step 2.

## ACI per-phase tool surface

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `parse` | `Read`, `Bash` (read-only: `ls`, `cat`, `find`, `grep`), `Glob`, `AskQuestion` | `Write`, `Edit`, mutating `Bash`, all `mcp__*`, network |
| `execute` | `Read`, `Bash` (`atomic_state_write`, `mkdir -p`, `rm` after AUQ confirm), `Glob`, `Grep`, `AskQuestion` | `Write`, `Edit` (`.geniro/instructions/*` writes go through `atomic_state_write`, since a direct write truncates in place and a crash leaves a partial file; see `${CLAUDE_PLUGIN_ROOT}/skills/instructions/mode-create.md` §Step 5), `Agent` (no subagents), `mcp__github__*`, network egress |
| `done` | (terminal report) | (none) |

External sends are never part of this skill's tool surface.

## Memory I/O

`/geniro:instructions` is the **CRUD frontend for L4 (procedural memory)**.

| Layer | Read | Write | Notes |
|---|---|---|---|
| CLAUDE.md (not a memory layer) | not read | not written | That's `/geniro:setup`'s domain |
| L4 `.geniro/instructions/*.md` | `list` reads all; `validate` reads target; `edit` reads target before mutation | `create`/`edit` write; `delete` removes | This is `/geniro:instructions`'s entire surface |

**compaction-survival route:** `.geniro/instructions/*.md` files are file-on-disk. After compaction, the SessionStart hook's suggested-file list re-reads `global.md` + active skill's `<skill>.md` + `code-style.md` via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`. `/geniro:instructions`'s CRUD writes are immediately durable.

## Termination case → state mapping

Failure paths report a structured reason in the final user message.

| Cause | Format |
|---|---|
| User cancelled at any question | `aborted: user cancelled at <step>` |
| Scope resolution retry cap exhausted (cap set in `phase-1-parse.md` §Ambiguity resolution) | `aborted: scope unresolved after <cap> rounds of questions` |

## Valid scope set

The stable scope set:

| Scope | File path | Loaded by | Notes |
|---|---|---|---|
| `global` | `.geniro/instructions/global.md` | Every pipeline + discovery skill at Step 0 + phase-boundary refresh | Rules and Constraints, plus the one cross-skill `### After worktree-setup` event step |
| `code-style` | `.geniro/instructions/code-style.md` | Every `LOAD_TIER: pipeline` skill (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Caller contract); loaded by every reviewer spawn (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` Step 1.6) | Cross-cutting; no per-skill phase mapping |
| `memory` | `.geniro/instructions/memory.md` | Every pipeline + discovery skill (and operational skills that emit L2) at Step 0 + phase-boundary refresh, loaded alongside `global.md` | Holds the `## Memory Backend` block only — no Rules/Constraints/Additional Steps |
| `review-extra/<slug>` | `.geniro/instructions/review-extra/<slug>.md` (directory-style) | `/geniro:review` Phase llm-spawn, `/geniro:implement` Phase self-review, `/geniro:refactor` Phase verify via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` | Directory-style; one file per slug. Frontmatter: `slug`, `description`, `model`, `paths`, `severity-default`, `requires-context` |
| `implement` · `plan` · `review` · `resolve` · `debug` · `refactor` · `onboard` · `investigate` | `.geniro/instructions/<skill>.md` | that skill at Step 0 + phase-boundary refresh | `implement` and `plan` each accept two `Additional Steps` anchors — one mid-pipeline, one terminal — and `refactor` one (`instructions-authoring-reference.md` §5); `review`, `resolve`, `debug`, `onboard`, and `investigate` take Rules and Constraints only — no phase currently reads a custom step for them |
| `reflect` | `.geniro/instructions/reflect.md` | `/geniro:reflect` at Step 0 | Rules and Constraints only (stateless — no Additional Steps) |

**Operational skills (`/geniro:setup`, `/geniro:instructions`, `/geniro:actions`, `/geniro:update`, `/geniro:audit-instructions`) load only the `rules-only` tier** — `global.md` + `memory.md` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Caller contract) — never the per-skill or `code-style.md` layers.

## File shapes

Three shapes across the scope set. The schema is owned by the loader that parses these files at runtime — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Producer contract; a schema change lands there first. Annotated templates and the per-scope create scaffolds live in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md` §1 — read that section before rendering a scaffold or judging a body's structure.

- **`code-style`** — `## Rules`, `## Constraints` only. No `## Additional Steps` (`mode-edit.md` §Body section invariants) and no `## Data Sources` / `## Verification Surface`.
- **`global` and every per-skill scope** — `## Rules`, `## Constraints`, and the optional `## Data Sources` and `## Verification Surface`; `## Additional Steps` → `### After <phase>` only where the §Valid scope set table grants that scope a legal anchor (`instructions-authoring-reference.md` §5).
- **`memory`** — `## Memory Backend` only. **`review-extra/<slug>`** — one file per custom reviewer: YAML frontmatter (fields in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-review-extra.md` §Frontmatter field reference) plus a `# Criteria` body.

Optional sections and their contract owners; an absent section changes nothing:

- `## Data Sources` (`global` and per-skill scopes) — read-only sources a phase cross-checks load-bearing facts against: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`.
- `## Verification Surface` (same scopes) — what each project check covers and leaves uncovered, so a run states a result at that check's width: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-surface.md`.
- `## Memory Backend` (`memory.md`, loaded alongside `global.md` for every skill) — routes the learnings layer through a custom backend, typically a memory MCP; absent, the built-in `.geniro/knowledge/learnings.jsonl` stays in use: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md`.

## Phase 1: Parse intent

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-parse.md`** — it carries the Steps: load custom instructions, locate the instructions directory, detect the mode, route a `create`/`edit` to its block type, resolve and validate the scope(s), then dispatch to the mode body, walking it once per scope when several resolved. Read it again on any resumption of the run.

## Writing effective instructions

Rule / step / constraint writing principles, file-size guidance, and the what-goes-where routing table (`.geniro/instructions/` vs `.claude/rules/` vs CLAUDE.md) live in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md` §2-§4. Read them before authoring any instruction body at create/edit time.

### Custom reviewer authoring (review-extra)

Companion file: `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-review-extra.md`. Read before creating or editing any `.geniro/instructions/review-extra/<slug>.md`.

## Cross-references

- `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-parse.md` — the Phase 1 Steps, including the external instructions dir rule (Step 0.5).
- `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-block-type-reference.md` — the intent → block-type routing table.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — persistent-CRUD tier for `.geniro/instructions/` and the optimistic mtime check
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` — the L4 procedural-memory loader for `.geniro/instructions/*.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — write helper for instruction files
- `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md` — file shapes, create scaffolds, writing principles, and the per-skill phase enums validate-mode checks `Additional Steps` anchors against (§5)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/description-quality.md` — the description-quality rows validate-mode grades a `review-extra/<slug>.md` description against
- `${CLAUDE_PLUGIN_ROOT}/skills/instructions/mode-list.md` · `mode-create.md` · `mode-edit.md` · `mode-validate.md` · `mode-delete.md` — the five mode bodies Phase 1 dispatches to
