---
name: instructions
description: "Use when adding skill-behavior rules at Geniro skill phase boundaries OR cross-cutting code-style rules loaded at every code-writing/review step; also for declaring read-only fact-verification sources (## Data Sources), recording what each project check covers and leaves uncovered so results are not overstated (## Verification Surface), or routing the agent's memory/learnings through a custom backend like an MCP (## Memory Backend). Operations: list, create, edit, validate, delete. Skip for per-file-pattern rules — .claude/rules/."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[what you want — e.g. 'add a rule to run tests', 'show instructions', 'delete review rules']"
---

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
- Frontmatter field reference (`review-extra/<slug>.md`)
- Phase 1 — parse intent, resolve scope, dispatch to a mode
- Writing effective instructions
- Cross-references

---

Stateless loop: **Parse → Execute → Done**. CRUD frontend over `.geniro/instructions/` — the L4 procedural memory layer. Five modes: `list`, `create`, `edit`, `validate`, `delete`; Phase 1 resolves exactly one of them per invocation. Stateless: every invocation is a single transaction; no state file.

**Phase body.** Phase 1's Steps live in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-parse.md`. Read it on entry to the phase, and again on any resumption of it, including after a compaction. A `create`/`edit` run also reads `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-block-type-reference.md` from there.

**Mode bodies.** Each mode's Steps live in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/mode-<op>.md`. Read the one Phase 1 dispatches to, and again on any resumption of it — the four it did not dispatch to are never read.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference: the plugin root is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. Tool and hook substitutions for non-Claude-Code runtimes: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md`.

Code rules split three ways depending on **when** they should fire:

- **`.geniro/instructions/code-style.md`** — cross-cutting code-style rules that apply to **all code writing AND all code review** done by Geniro pipeline skills (loaded at code-writing/review phases regardless of file pattern).
- **`.claude/rules/<scope>.md` with `paths:` YAML frontmatter** — file-pattern-scoped rules (Anthropic-native, auto-loads on matching glob — fires even outside Geniro pipelines).
- **CLAUDE.md** — reserved for always-loaded essentials (commands, project structure, compaction-surviving gates) and should NOT carry code rules.

**After a compaction, re-Read the phase body and the dispatched mode's body file before continuing** — only a skill's front-loaded prefix is re-attached after a summary, so a mid-run summary can drop the Steps while leaving this spine intact. This skill is stateless, so if which mode was running is also gone, re-invoke and restart the transaction from Phase 1.

## Loop invariants

The canonical agent-loop invariants in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` apply throughout /geniro:instructions, with three skill-specific notes (an `#N` inside a note points at that file's numbered list):

1. **Invariant #2 (args validated)** — every write is preceded by scope validation (regex match) AND a file-existence check.
2. **Invariant #3 (permission before side-effect)** — create / edit / delete writes are AUQ-gated.
3. **Invariant #7 (errors → structured observations)** — there is no state file here, so errors surface inline in the final user message.

**Single transaction, no subagents** — `/geniro:instructions` runs entirely in the orchestrator (CRUD is too small for parallelism).

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll auto-fix `validate` issues to save the user a step" | No — auto-fix would silently mutate user-authored content. `validate` reports; user fixes via `edit`. |
| "I'll silently overwrite existing instruction file" | No — for `create` on existing, present overwrite/edit-instead/cancel via AUQ. |
| "I'll skip the per-skill phase-enum check because the user said `### After Phase 1`" | No — old enums fail silently in the loader. Validate-mode catches and suggests the canonical name. |
| "I'll spawn a subagent to do the freeform rule synthesis" | No — `/geniro:instructions` is a small CRUD frontend; subagents add no parallelism benefit and complicate the stateless single-transaction model. |
| "I'll output the questions as plain text instead of `AskUserQuestion`" | No — every WAIT gate uses `AskUserQuestion`. |
| "I'll rename a per-skill scope to something custom (e.g., implement → my-flow)" | No — scope names are fixed; pick from the stable scope set. |
| "I'll skip showing the scope-specific scaffold to save tokens" | No — scaffolds make the empty-file moment less confusing; they're not optional. |

## Definition of done

- [ ] Mode detected from freeform arguments (or default to `list`)
- [ ] Scope(s) resolved — single or batch — within 3 AUQ retry cap
- [ ] The dispatched mode's body file was Read and its Steps completed
- [ ] User confirmed before running the destructive mode (`delete`)
- [ ] Validation checked structure, phase names, scope validity, dropped-skill refs, and description rules
- [ ] All user interactions used `AskUserQuestion` — no plain-text questions
- [ ] review-extra files validated against slug uniqueness, built-in collision, model/severity-default value sets, paths syntax, and count caps
- [ ] Scope-specific scaffold shown on `create` (not skipped)

## Budgets — quality-first

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. Soft gates: 3-retry scope ambiguity → final AUQ abort, `list --with-content` body truncation at ~2000 chars/file. Architecture constraints: stateless, no subagent spawns.

## ACI per-phase tool surface

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `parse` | `Read`, `Bash` (read-only: `ls`, `cat`, `find`, `grep`), `Glob`, `AskUserQuestion` | `Write`, `Edit`, mutating `Bash`, all `mcp__*`, network |
| `execute` | `Read`, `Bash` (`atomic_state_write`, `mkdir -p`, `rm` after AUQ confirm), `Glob`, `Grep`, `AskUserQuestion` | `Write`, `Edit` (`.geniro/instructions/*` is a persistent-CRUD path — a direct write is hard-blocked by the state-helper hook; see `${CLAUDE_PLUGIN_ROOT}/skills/instructions/mode-create.md` §Step 5), `Agent` (no subagents), `mcp__github__*`, network egress |
| `done` | (terminal report) | (none) |

External sends: not in `/geniro:instructions` ACI ever.

## Memory I/O

`/geniro:instructions` is the **CRUD frontend for L4 (procedural memory)**.

| Layer | Read | Write | Notes |
|---|---|---|---|
| CLAUDE.md (not a memory layer) | not read | not written | That's `/geniro:setup`'s domain |
| L4 `.geniro/instructions/*.md` | `list` reads all; `validate` reads target; `edit` reads target before mutation | `create`/`edit` write; `delete` removes | This is `/geniro:instructions`'s entire surface |

**compaction-survival route:** `.geniro/instructions/*.md` files are file-on-disk. After compaction, the SessionStart hook's suggested-file list re-reads `global.md` + active skill's `<skill>.md` + `code-style.md` via `_shared/load-custom-instructions.md`. `/geniro:instructions`'s CRUD writes are immediately durable.

## Termination case → state mapping

No state file, but failure paths report a structured reason in the final user message.

| Cause | Format |
|---|---|
| User cancelled at any question | `aborted: user cancelled at <step>` |
| Scope resolution failed after 3 AUQ retries | `aborted: scope unresolved after 3 AUQ rounds` |
| Write blocked by file-protection hook | `aborted: file-protection hook blocked write to <path>; see .geniro/safety.json` |
| Delete blocked by `.geniro/` deletion guard | `aborted: .geniro/ deletion guard blocked rm of <path>; see .geniro/safety.json` |

## Valid scope set

The stable scope set:

| Scope | File path | Loaded by | Notes |
|---|---|---|---|
| `global` | `.geniro/instructions/global.md` | Every pipeline + discovery skill at Step 0 + phase-boundary refresh | Rules and Constraints, plus the one cross-skill `### After worktree-setup` event step |
| `code-style` | `.geniro/instructions/code-style.md` | All code-writing skills (`implement`, `refactor`) AND all code-review steps (`review`, `implement` Phase self-review, `refactor` Phase verify); pre-inlined into reviewer-agent prompts for the conventions/design/architecture dimensions | Cross-cutting; no per-skill phase mapping |
| `memory` | `.geniro/instructions/memory.md` | Every pipeline + discovery skill (and operational skills that emit L2) at Step 0 + phase-boundary refresh, loaded alongside `global.md` | Holds the `## Memory Backend` block only — no Rules/Constraints/Additional Steps |
| `review-extra/<slug>` | `.geniro/instructions/review-extra/<slug>.md` (directory-style) | `/geniro:review` Phase llm-spawn, `/geniro:implement` Phase self-review, `/geniro:refactor` Phase verify via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` | Directory-style; one file per slug. Frontmatter: `slug`, `description`, `model`, `paths`, `severity-default`, `requires-context` |
| `implement` · `plan` · `review` · `resolve` · `debug` · `refactor` · `onboard` · `investigate` | `.geniro/instructions/<skill>.md` | that skill at Step 0 + phase-boundary refresh | `Additional Steps` map to that skill's phase enum; `onboard` and `investigate` take Rules and Constraints only |
| `reflect` | `.geniro/instructions/reflect.md` | `/geniro:reflect` at Step 0 | Rules and Constraints only (stateless — no Additional Steps) |

**Operational skills (`/geniro:setup`, `/geniro:instructions`, `/geniro:actions`, `/geniro:update`) do NOT load instruction files** beyond `global.md`.

**External instructions dir — read there, manage here.** When an external instructions dir is configured (`GENIRO_INSTRUCTIONS_DIR` or the plugin's `instructions_dir` option), the pipeline skills' loader READS instruction files from that external location. `/geniro:instructions` CRUD (list / create / edit / delete / validate) still operates on the in-repo copy at the primary worktree root (`"$PRIMARY_ROOT"/.geniro/instructions/`) — the path keeps the literal `.geniro/` segment, so the atomic-write helper and the `.geniro/` deletion guard stay engaged; an external location would bypass both. To manage the external set, edit it directly at its path. The override covers the loaded instruction set (`global.md`, `memory.md`, `code-style.md`, and the per-skill `<skill>.md`); custom review-extra reviewers (`review-extra/<slug>.md`) are enumerated separately by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` and are NOT redirected by the external override — they stay in the in-repo `.geniro/instructions/review-extra/`.

## File shapes

Three shapes across the scope set. The schema itself is owned by the loader that parses these files at runtime — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` §Producer contract; the shapes below and the annotated templates are authoring scaffolds written against it, so a schema change lands there first. The templates for all three, plus the per-scope create scaffolds, live in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md` §1 — read that section before rendering a scaffold or judging a body's structure.

- **Singleton scopes** (`global`, `code-style`, every per-skill scope) — `## Rules`, `## Additional Steps` → `### After <phase>` / `### Before <phase>`, `## Constraints`, and the optional `## Data Sources` and `## Verification Surface`.
- **`memory`** — its own `.geniro/instructions/memory.md`, carrying the `## Memory Backend` block only; no Rules / Constraints / Additional Steps.
- **`review-extra/<slug>`** — directory-style, one file per custom reviewer, with YAML frontmatter (fields below) plus a `# Criteria` body.

The optional `## Data Sources` section — valid in `global` and the per-skill scopes — declares the read-only sources the `/geniro:plan` and `/geniro:implement` verification steps cross-check load-bearing facts against; its entry shape, discovery, and read-only screening are owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`, and an absent section just means no declared sources.

The optional `## Verification Surface` section — same scopes — declares what each of the project's checks covers and what it leaves uncovered, so a run picks the check that actually demonstrates a criterion and states the result at that check's width; its entry shape and consumption contract are owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-surface.md`, and an absent section changes nothing.

`memory.md` is loaded alongside `global.md` for every skill, and its `## Memory Backend` section routes the learnings layer through a custom backend (typically a memory MCP); the entry shape and the full routing contract are owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md`, and an absent file or block leaves the built-in `.geniro/knowledge/learnings.jsonl` in use unchanged.

## Frontmatter field reference (`review-extra/<slug>.md`)

The single source for every field's value set and length cap — validate-mode's per-scope check resolves here rather than restating them.

- `slug` (required) — must satisfy the rules `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Discovery procedure Step 4 enforces at load time: the filename without `.md`, matching `^[a-z][a-z0-9-]*$`, and not colliding with a reserved dimension name. That file owns the reserved list, because it is the runtime enforcer — a slug this skill accepts but the loader rejects produces a file the user believes is active while its criteria silently never run.
- `description` (required) — one-line summary, ≤250 chars.
- `model` (optional) — `haiku`/`sonnet`/`opus`/`inherit`; omitted = `inherit` (the reviewer runs at the orchestrator's tier, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md`). Declare a tier only to deliberately pin this reviewer cheaper or stronger than the session.
- `paths` (optional) — list of globs.
- `severity-default` (optional) — `CRITICAL`/`HIGH`/`MEDIUM`/`LOW`; default `MEDIUM`.
- `requires-context` (optional) — natural-language directive naming the live external data this reviewer needs (a Notion page, a Linear issue, an API response). The reviewer runs in a subagent that can't call MCP, so the orchestrator pre-fetches the data and injects it as a `CUSTOM CONTEXT:` block at spawn time, failing open if it's unavailable (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Hydrating requires-context). Omit unless the reviewer genuinely needs external data. Example: `requires-context: "Fetch the live Notion Incident Report (latest entry) and provide its incident-pattern list."`

## Phase 1: Parse intent

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-parse.md`** — it carries the Steps: load custom instructions, locate the instructions directory, detect the mode, route a `create`/`edit` to its block type, resolve and validate the scope(s), then dispatch to the mode body, walking it once per scope when several resolved. Read it again on any resumption of the run.

## Writing effective instructions

Rule / step / constraint writing principles, file-size guidance, and the what-goes-where routing table (`.geniro/instructions/` vs `.claude/rules/` vs CLAUDE.md) live in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md` §2-§4. Read them before authoring any instruction body at create/edit time.

### Custom reviewer authoring (review-extra)

Companion file: `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-review-extra.md`. Read before creating or editing any `.geniro/instructions/review-extra/<slug>.md`.

## Cross-references

- `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-parse.md` — the Phase 1 Steps (Step 0 instruction load, Step 0.5 `PRIMARY_ROOT`, mode + scope resolution, scope validation, dispatch, batch walk). Read on entry to the phase, and again on any resumption of it, including after a compaction.
- `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-block-type-reference.md` — the intent → block-type routing table. Read from Phase 1 when the resolved mode is `create` or `edit`, and again on any resumption of an authoring step.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — T3 persistent-CRUD tier for `.geniro/instructions/` and the optimistic mtime check
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` — the L4 procedural-memory loader for `.geniro/instructions/*.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — write helper for instruction files
- `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md` — file shapes, create scaffolds, writing principles, and the per-skill phase enums validate-mode checks `Additional Steps` anchors against (§5)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/description-quality.md` — the three description-quality rows validate-mode grades a `review-extra/<slug>.md` description against
- `${CLAUDE_PLUGIN_ROOT}/skills/instructions/mode-list.md` · `mode-create.md` · `mode-edit.md` · `mode-validate.md` · `mode-delete.md` — the five mode bodies Phase 1 dispatches to
