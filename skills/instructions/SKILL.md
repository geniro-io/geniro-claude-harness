---
name: geniro:instructions
description: "Use when adding skill-behavior rules at Geniro skill phase boundaries OR cross-cutting code-style rules loaded at every code-writing and review step. Five operations: list, create, edit, validate, delete. Skip for per-file-pattern rules — use.claude/rules/."
context: main
model: sonnet
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[what you want — e.g. 'add a rule to run tests', 'show instructions', 'delete review rules']"
---

# Instructions: Custom Instruction Management

3-phase stateless loop: **Parse → Execute → Done**. CRUD frontend over `.geniro/instructions/` — the L4 procedural memory layer. Five operations: `list`, `create`, `edit`, `validate`, `delete`. Stateless: every invocation is a single transaction; no state file. Architecture spec: *(internal)*.

Code rules split three ways depending on **when** they should fire:

- **`.geniro/instructions/code-style.md`** — cross-cutting code-style rules that apply to **all code writing AND all code review** done by Geniro pipeline skills (loaded at code-writing/review phases regardless of file pattern).
- **`.claude/rules/<scope>.md` with `paths:` YAML frontmatter** — file-pattern-scoped rules (Anthropic-native, auto-loads on matching glob — fires even outside Geniro pipelines).
- **CLAUDE.md** — reserved for always-loaded essentials (commands, project structure, compaction-surviving gates) and should NOT carry code rules.

## Loop invariants

1. One result per subagent call — `/instructions` never spawns subagents (CRUD too small for parallelism).
2. Args validated before exec — every Write preceded by scope validation (regex match) AND file-existence check.
3. Permission before side-effect — Write/Delete are AUQ-gated.
4. Bounded structured results — `list` mode truncates per-file body display at ~2000 chars.
5. Hard escalation gates — 3-retry on scope ambiguity → final AUQ abort.
6. Observations not assumed success — every Read/Write checks return status.
7. Errors as structured observations — surfaced inline in the final user message (no state file).

## Budgets — quality-first

`/instructions` has **zero Class-A hard kill caps**. Class-B gates: 3-retry scope ambiguity → final AUQ abort, list-mode body truncation at ~2000 chars/file. Architecture constraints: stateless, no subagent spawns. NOT capped: number of scopes processed in batch mode, files in `review-extra/`, file size after edit, AUQ chain depth for scope picking.

## ACI surface per phase

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `parse` | `Read`, `Bash` (read-only: `ls`, `cat`, `find`, `grep`), `Glob`, `AskUserQuestion` | `Write`, `Edit`, mutating `Bash`, all `mcp__*`, network |
| `execute` | `Read`, `Write`, `Edit`, `Bash` (`mkdir -p`, `rm` after AUQ confirm), `Glob`, `Grep`, `AskUserQuestion` | `Agent` (no subagents), `mcp__github__*`, network egress |
| `done` | (terminal report) | (none) |

External sends: not in `/instructions` ACI ever.

## Termination case → state mapping

No state file, but failure paths report a structured reason in the final user message.

| Cause | Format |
|---|---|
| User cancelled at any AUQ | `aborted: user cancelled at <step>` |
| Scope resolution failed after 3 AUQ retries | `aborted: scope unresolved after 3 AUQ rounds` |
| Validation found N issues, user picked "Abort" | `aborted: validate surfaced N issues; user picked abort` |
| Write blocked by file-protection hook | `aborted: file-protection hook blocked write to <path>; see.geniro/safety.json` |
| Delete blocked by `.geniro/` deletion guard | `aborted:.geniro/ deletion guard blocked rm of <path>; see.geniro/safety.json` |

## Valid scope set

The post-11-scope set:

| Scope | File path | Layer | Loaded by | Notes |
|---|---|---|---|---|
| `global` | `.geniro/instructions/global.md` | L4 | Every pipeline + discovery skill at Step 0 + phase-boundary refresh | Rules and Constraints only |
| `code-style` | `.geniro/instructions/code-style.md` | L4 | All code-writing skills (`implement`, `refactor`) AND all code-review steps (`review`, `implement` Phase Review, `refactor` Phase Verify); pre-inlined into reviewer-agent prompts for guidelines/conventions/design/architecture dimensions | Cross-cutting; no per-skill phase mapping |
| `user-preferences` | `.geniro/instructions/user-preferences.md` | L4 | Every pipeline + discovery skill at Step 0 + phase-boundary refresh | Created by `/setup` Phase Generate; `/instructions edit user-preferences` is the manual-edit path. Rules and Constraints only |
| `review-extra/<slug>` | `.geniro/instructions/review-extra/<slug>.md` (directory-style) | L4 | `/review` Phase llm-spawn, `/implement` Phase self-review, `/refactor` Phase verify via `_shared/load-custom-reviewers.md` | Directory-style; one file per slug. Frontmatter: `slug`, `description`, `model`, `paths`, `severity-default` |
| `implement` | `.geniro/instructions/implement.md` | L4 | `/implement` at Step 0 + phase-boundary refresh | `Additional Steps` map to phase enum |
| `plan` | `.geniro/instructions/plan.md` | L4 | `/plan` at Step 0 + phase-boundary refresh | `Additional Steps` map to phase enum |
| `review` | `.geniro/instructions/review.md` | L4 | `/review` at Step 0 + phase-boundary refresh | `Additional Steps` map to phase enum |
| `debug` | `.geniro/instructions/debug.md` | L4 | `/debug` at Step 0 + phase-boundary refresh | `Additional Steps` map to phase enum |
| `refactor` | `.geniro/instructions/refactor.md` | L4 | `/refactor` at Step 0 + phase-boundary refresh | `Additional Steps` map to phase enum |
| `onboard` | `.geniro/instructions/onboard.md` | L4 | `/onboard` at Step 0 + phase-boundary refresh | Rules and Constraints only |
| `investigate` | `.geniro/instructions/investigate.md` | L4 | `/investigate` at Step 0 + phase-boundary refresh | Same as `onboard` |

**Operational skills (`/setup`, `/instructions`, `/actions`, `/update`) do NOT load instruction files** beyond `global.md`.

## File Structure (singleton scopes)

```markdown
# Custom Instructions

## Rules
- Clear, single-line constraints

## Additional Steps
### After <phase-enum-value>
<!-- Steps to run at the named phase -->

## Constraints
- Hard limits
```

## File Structure: review-extra

The `review-extra` scope is **directory-style** — one file per custom reviewer at `.geniro/instructions/review-extra/<slug>.md`:

```yaml
---
slug: sql-bindings # REQUIRED; matches filename; must NOT collide with built-in dimensions
description: All SQL queries use parameterized bindings, never string concatenation
model: sonnet # OPTIONAL; haiku|sonnet|opus; default sonnet
paths: # OPTIONAL; list of globs; absent = always fires
- "**/*.sql"
- "**/dao/*.{ts,py}"
severity-default: HIGH # OPTIONAL; default MEDIUM
---

# Criteria

What to flag:
-...

What to NOT flag:
-...
```

**Frontmatter field reference:**
- `slug` (required) — lowercase ASCII letters/digits/hyphens, regex `^[a-z][a-z0-9-]*$`. Filename without `.md` must equal this. MUST NOT match a built-in dimension (`bugs`, `security`, `architecture`, `tests`, `optimizations`, `guidelines`, `conventions`, `design`, `pr-metadata`).
- `description` (required) — one-line summary, ≤250 chars.
- `model` (optional) — `haiku`/`sonnet`/`opus`; default `sonnet`.
- `paths` (optional) — list of globs.
- `severity-default` (optional) — `CRITICAL`/`HIGH`/`MEDIUM`/`LOW`; default `MEDIUM`.

## Phase 1: Parse intent

**Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: instructions`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Echo contract requires one observable line.

### Action detection

| Intent | Aliases | Maps to |
|--------|---------|---------|
| List | show, view, list, display, what instructions, current | `list` |
| Create | add, new, create, set up, start | `create` |
| Edit | change, modify, update, edit, tweak, adjust | `edit` |
| Validate | check, verify, validate, lint | `validate` |
| Delete | remove, delete, drop, clear | `delete` |

If no arguments: default to `list`.

### Scope detection

- Explicit names: `global`, `code-style`, `user-preferences`, `review-extra`, or a pipeline skill (`implement`, `plan`, `review`, `debug`, `refactor`, `onboard`, `investigate`)
- Contextual: "add a rule to review" → scope=review · "create debug instructions" → scope=debug · "code-style" / "style" / "naming conventions" → scope=code-style · "user preferences" / "preferences" → scope=user-preferences · "custom reviewer" / "review dimension" → scope=review-extra
- Explicit slug form: `review-extra <slug>` (e.g., `review-extra sql-bindings`)
- Multi-scope: "all", "every", "global and review" → collect into list
- "all" / "every" → expand to all valid scopes that have existing files (for edit/validate/delete) or all valid scopes (for create)

### Ambiguity resolution (simplified vs current )

Current skill chains up to 3 AUQs across 10 scopes. With **11 stable scopes**, use a 2-level chain:

**Level 1 — category:**

- **Question:** "Which instruction file scope?"
- **Options:**
- `global` — Project-wide rules loaded by every Geniro skill
- `code-style` — Cross-cutting style rules for code writing AND review
- `user-preferences` — User communication style and pipeline defaults (also editable via /setup re-run)
- `Specific skill or review-extra` — Pick from per-skill (7) or review-extra (custom reviewer)

If "Specific skill or review-extra", chain Level 2:

- **Question:** "Which specific scope?"
- **Options:**
- `review-extra (new custom reviewer)` — Add a custom reviewer dimension (asks for slug)
- `implement / plan / review` — Pipeline skills (chain to L2b)
- `debug / refactor` — Pipeline skills (chain to L2b)
- `onboard / investigate` — Discovery skills (chain to L2b)

Level 2b asks for the exact skill (2-3 options, fits in AUQ). With 11 stable scopes the chain depth is fixed at 2-3 levels. **Cap retry at 3 rounds**; after the third, abort with "Could not narrow down — try `/geniro:instructions list` for the exact set."

### Scope validation

Before proceeding, verify resolved scope(s) are valid. If any resolved scope is NOT in the 11-scope set, AUQ to ask the user to pick from valid scopes. Do NOT create, edit, or delete files for invalid scopes.

For `review-extra`, slug-bearing variants of `create`/`edit`/`delete` ALSO require a `<slug>` argument. Resolve missing-slug cases:

- `create review-extra` no slug → ask via `AskUserQuestion` "Other" path (free-form text).
- `edit review-extra` / `delete review-extra` no slug AND one file exists → default to that file.
- `edit review-extra` / `delete review-extra` no slug AND multiple files exist → AUQ which slug. If >4 files, chain follow-ups per `feedback_askuserquestion_extension.md`.
- `validate review-extra` ignores slug — always validates the whole directory. Print one-line notice if a slug was passed.

If multi-scope, proceed to **Batch Mode**. Otherwise proceed to the resolved command section.

## Phase 2: Mode dispatch (single-scope)

Branch: `list` → · `create` → · `edit` → · `validate` → · `delete` →
## Batch Mode

For multi-scope (e.g., "edit global and review", "add rules to all"), process each scope sequentially through the same command flow. With 11 stable scopes the multi-scope chain stays under 4 AUQ rounds.

Print summary after all scopes complete:

```
## Batch Complete

| Scope | Action | Result |
|-------|--------|--------|
| global | edit | Updated — added 2 rules |
| review | edit | Updated — added 1 constraint |
```

## — Mode: list

### Step 1 — Scan directory

```bash
ls -la.geniro/instructions/ 2>/dev/null
ls -la.geniro/instructions/review-extra/ 2>/dev/null
```

### Step 2 — Present results

If empty:

```
No instruction files found.

Run `/geniro:instructions create global` to create your first instruction file,
or `/geniro:instructions create code-style` for project-wide style rules.
```

Else, table format:

```
Custom instructions in.geniro/instructions/ (project: my-project):

global.md 348 B modified 3 days ago
code-style.md 1.2 KB modified 2 hours ago
user-preferences.md 412 B modified 5 days ago [generated by /setup]
implement.md (none — create with /geniro:instructions create implement)
plan.md (none)
review.md 892 B modified 1 week ago
debug.md (none)
refactor.md (none)
onboard.md (none)
investigate.md (none)
review-extra/ (directory — 2 files)
├── sql-bindings.md 1.6 KB modified 4 days ago
└── accessibility-aria.md 2.1 KB modified 1 day ago

11 scopes total · 5 active · 6 not-yet-created
```

Add `--with-content` flag to dump file bodies inline (truncated at ~2000 chars per file).

## — Mode: create

### Step 1 — Check for existing file

```bash
cat .geniro/instructions/<scope>.md 2>/dev/null
```

If file exists: AUQ "File exists — overwrite, edit instead, or cancel?". Branch accordingly.

### Step 2 — Ensure directory exists

```bash
mkdir -p.geniro/instructions
mkdir -p.geniro/instructions/review-extra # if scope == review-extra
```

### Step 3 — Gather project context

Read `CLAUDE.md` for tech stack/commands/conventions; check `package.json`/`Makefile` for scripts; check for ESLint/Prettier/tsconfig. This context informs scope-specific rule suggestions.

### Step 4 — Scope-specific scaffold + interview

Each scope gets a **scope-specific scaffold** with example Rules to make the empty-file moment less confusing. Examples:

**`code-style.md` scaffold:**

```markdown
# Custom Instructions

## Rules

- Use lowercase-hyphen for component file names (e.g., `user-profile.tsx`, not `UserProfile.tsx`).
- Prefer named exports over default exports for tree-shaking.

## Constraints

- No `any` type without an inline `// reason:...` comment.
```

**`user-preferences.md` scaffold** (rarely created manually — `/setup` does it; allowed for users who skipped `/setup`):

```markdown
# User Preferences

## Rules

- **Default branch:** main
- **Default ship mode:** open PR (draft)
- **Default reviewer set:** full
- **Communication style:** concise

## Loaded by

Every Geniro pipeline + discovery skill at Step 0 and at each phase-boundary refresh.
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
```

Use `AskUserQuestion` after showing the scaffold:

- **Question:** "Add what kind of rules?"
- **Options (scope-tailored):** Documentation / Quality gates / Workflow steps / Free-form (Other path)

Capture 1-2 follow-up answers via additional AUQs. Convert vague user input into strong, specific rules (e.g. "make sure we test" → "Always include tests for new public functions. Run `npm test` to verify before shipping").

### Step 5 — Generate the file

Apply writing principles ("Writing Effective Instructions" below). Show preview via final AUQ `Write scaffold? | Edit body before writing | Cancel`. On `write`, atomic write §Atomic write helper (`atomic_state_write` is for state tiers; instruction files use direct Write through the file-protection hook).

### Step 6 — Confirm

Print:

```
Created `.geniro/instructions/<scope>.md`

This file will be loaded by <affected skills list> at the start of each run.
Edit via `/geniro:instructions edit <scope>`; lint via `/geniro:instructions validate`.
```

For `review-extra`, follow the slug-bearing 11-step flow in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-review-extra.md`.

## — Mode: edit

### Step 1 — Resolve scope (Phase 1) + Read existing file

If missing, branch to `create`. Else display current body inline.

### Step 2 — Three-way AUQ

- **Question:** "How would you like to edit `<scope>`?"
- **Options:**
- `Open in editor (external)` — Print absolute path; instruct user to edit externally and re-run `/instructions validate <scope>` when done. Exit.
- `Rewrite via dialogue` — Interview-style sequence of AUQs (Add a Rule / Add an Additional Step / Add a Constraint / Remove a Rule by number / Done). Apply edits to an in-memory copy; final write AUQ-gated.
- `Cancel`

The dialogue path is intentionally simpler than freeform edit — stays inside AUQ contracts and avoids prompt-injection through user-supplied text.

### Step 3 — Re-validate (review-extra only)

After editing a `review-extra` file, re-run the lint rule set against the edited file. If any rule fails, AUQ revert vs keep-and-fix-later.

### Step 4 — Show updated file

```
Updated `.geniro/instructions/<scope>.md`. The new rules take effect the next time you run `/geniro:<scope>` (or any affected skill for global.md).
```

### Body section invariants (post-edit)

- `## Rules` section present (may be empty list).
- `## Additional Steps` section present (omitted only for rules-only scopes: `global`, `code-style`, `user-preferences`, `review-extra/<slug>`, `onboard`, `investigate`).
- `## Constraints` section present (may be empty list).
- Frontmatter (for `review-extra/<slug>.md`) parses YAML cleanly.

Violations are not auto-fixed; `validate` surfaces them on next invocation.

## — Mode: validate

### Step 1 — Scan + scope

`validate` accepts `<scope>` arg (validate one file) or no arg (validate all). Read-only; never mutates.

**flag:** `--max-lines N` overrides the default 200-LOC threshold (Step 2). Use `--max-lines 0` to disable the length check entirely. Env override: `GENIRO_INSTRUCTIONS_MAX_LINES`.

### Step 2 — Lint rule set

**Structural checks (apply to all scopes):**

| Check | Severity | Example violation |
|---|---|---|
| File parses as valid Markdown | CRITICAL | Binary file masquerading as `.md` |
| `## Rules` heading present | HIGH | File has body but no `## Rules` header |
| `## Constraints` heading present (skip for `review-extra/<slug>.md` — uses `# Criteria` instead) | HIGH | Missing `## Constraints` |
| File ≤ 200 lines (; threshold env-overridable, see Step 1) | LOW | Anthropic Claude Code memory guidance: «longer files consume more context and reduce adherence». Surface suggested actions inline (split into topic-specific files OR trim redundant rules). |

**Reference checks:**

| Check | Severity |
|---|---|
| No references to dropped skills (`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`) | HIGH |
| No references to dropped phase names (e.g., "Phase 4 (Implement)" predates the spec's enum redesign) | MEDIUM |
| `Additional Steps` subsections match per-skill phase enum | MEDIUM |

**Per-scope checks:**

| Scope | Extra checks |
|---|---|
| `review-extra/<slug>.md` | Frontmatter parses YAML; `slug` matches filename; `slug` not a built-in dimension; `description` one line ≤250 chars; `description` starts with "Use when" or describes intent (LOW preference); `model` in `{haiku, sonnet, opus}` if present; `paths` is a list if present; `severity-default` in `{CRITICAL, HIGH, MEDIUM, LOW}` if present |
| `user-preferences.md` | All 4 canonical preference rules present (default branch, ship mode, reviewer set, communication style) — MEDIUM if any missing |
| `code-style.md` | At least 1 rule under `## Rules` — LOW warning if empty (no-op file) |

**description lint rules** (applied to `review-extra/<slug>.md` frontmatter `description:` field only):

| Rule | Severity |
|---|---|
| lowercase-hyphens slug (`^[a-z][a-z0-9-]*$`) | HIGH (CRITICAL if slug fails validation entirely) |
| description starts with "Use when" or describes intent vs implementation | LOW warning |
| description mentions adjacent terms (e.g., for `sql-bindings`: mentions "SQL", "ORM", "DAO") | LOW warning |
| description has explicit boundary clauses ("Skip for …", "Not for …") | LOW info |

### Step 3 — Per-skill phase mapping

`Additional Steps` subsections must match a real phase enum value from the corresponding skill doc. Lowercase-hyphenated; subsection prose may use any case (validate normalizes).

| Scope | Real phase enum (M-doc) | Example subsection names |
|---|---|---|
| `implement` | `analyze \| implement \| self-review \| ship \| ship-committed-only \| self-review-only \| phase-2-escalated \| phase-3-escalated \| debug-handoff \| done \| aborted` | `After analyze`, `After implement`, `After self-review`, `Before ship` |
| `plan` | `mode-detect \| explore \| clarify \| approaches \| section-approve \| write-spec \| validate \| user-approve \| handoff \| phase-8-escalated \| done \| aborted` | `After explore`, `After clarify`, `After approaches`, `After write-spec`, `Before user-approve` |
| `review` | `triage \| mechanical-prepass \| llm-spawn \| filter \| stratify \| persist \| action-gate \| done \| aborted \| escalated` | `After triage`, `After llm-spawn`, `After filter`, `Before action-gate` |
| `debug` | `mode-detect \| investigate \| propose \| ship \| ship-summary-only \| phase-1-escalated \| phase-2-escalated \| debug-handoff \| adversarial-mode-detect \| adversarial-investigate \| adversarial-ship \| adversarial-aborted \| done \| aborted` | `After investigate`, `After propose`, `Before ship` |
| `refactor` | `plan \| apply \| verify \| verify-summary-only \| plan-escalated \| apply-escalated \| verify-escalated \| reverted \| routed \| adr-documented \| done \| aborted` | `After plan`, `After apply`, `Before verify` |
| `onboard` | `discover \| map \| map-truncated \| discover-escalated \| done \| aborted \| routed` | `After discover`, `Before map` |
| `investigate` | `classify \| investigate \| present \| present-summary-only \| present-loop \| classify-escalated \| investigate-escalated \| done \| aborted \| routed` | `After classify`, `After investigate`, `Before present` |

Free-form subsections raise `LOW` warning. Subsections referencing dropped phase names (e.g., `After Phase 4 (Implement)`) raise `MEDIUM`.

### Step 4 — Count caps (review-extra)

- **Soft warning** if >6 files: `⚠ Count {N} exceeds the 4-6 sweet-spot — consider consolidating overlapping reviewers.`
- **Hard error** if >10 files: `✗ Count {N} exceeds hard cap of 10 — the loader will refuse to load all reviewers.`

### Step 5 — Output format

```
$ /geniro:instructions validate

Validation results: 4 files checked, 3 issues found.

✓ global.md no issues
⚠ implement.md 1 MEDIUM
└── Line 14: "### After Phase 4 (Implement)" → should be "### After implement"
⚠ code-style.md 1 LOW
└── File is 380 lines (>200). Anthropic guidance: longer files reduce adherence.
Suggestions: split into code-style-database.md + code-style-api.md, or trim redundant rules.
⚠ review-extra/sql-bindings.md 1 LOW
└── Frontmatter description: missing "Skip for" boundary clause (LOW — informational)

To fix: /geniro:instructions edit implement
/geniro:instructions edit code-style
/geniro:instructions edit review-extra sql-bindings
```

Exit status: 0 if no `CRITICAL`/`HIGH`; non-zero otherwise. `MEDIUM`/`LOW` are warnings.

### No auto-fix

Per sub-decision: `validate` reports; does not mutate. Auto-fix would silently change user-authored content — violates the user-content-sacred rule.

## — Mode: delete

### Step 1 — Resolve + read existing file

If missing: print "nothing to delete" and exit. Else continue.

### Step 2 — Confirm

AUQ 2-option: `Confirm delete` / `Cancel`. Show file size + last-modified for context. For `review-extra/<slug>.md`, the slug must be specified (no bulk-delete).

### Step 3 — Execute

```bash
rm -f.geniro/instructions/<scope>.md
# OR for review-extra:
rm -f.geniro/instructions/review-extra/<slug>.md
```

The `.geniro/` deletion guard hook **allows** per-file `rm -f` of `.geniro/instructions/<scope>.md` (per the hook's "Per-file `rm -f` remain allowed" rule); only bulk `rm -rf.geniro/instructions/` is blocked.

Clean up empty parent dirs silently:

```bash
rmdir.geniro/instructions/review-extra/ 2>/dev/null
rmdir.geniro/instructions/ 2>/dev/null
```

For `review-extra` ALL: explicitly refused with "Use `/instructions delete review-extra <slug>` per-file; bulk delete protected by guard hook."

## Memory I/O

`/instructions` is the **CRUD frontend for L4 (procedural memory)**.

| Layer | Read | Write | Notes |
|---|---|---|---|
| L1 CLAUDE.md | not read | not written | That's `/setup`'s domain |
| L2 learnings.jsonl | not read | not written | `/instructions` is a CRUD frontend, not a knowledge-emit producer |
| L3 semantic files | not read | not written | Out of scope |
| L4 `.geniro/instructions/*.md` | `list` reads all; `validate` reads target; `edit` reads target before mutation | `create`/`edit` write; `delete` removes | This is `/instructions`'s entire surface |

**compaction-survival route:** `.geniro/instructions/*.md` files are file-on-disk. After compaction, the SessionStart hook's suggested-file list re-reads `global.md` + active skill's `<skill>.md` + `code-style.md` + `user-preferences.md` via `_shared/load-custom-instructions.md`. `/instructions`'s CRUD writes are immediately durable.

## Writing Effective Instructions

### Rule Writing

- **Use strong, unambiguous language** — "Always", "Never", "Must" not "Consider", "Try to", "Should"
- **One rule = one constraint** — don't combine multiple ideas in a single bullet
- **Be specific, not vague** — "Run `pnpm test` before committing" not "Make sure tests pass"
- **Include the command or path** — name them exactly
- **Focus on what the AI can't infer** — don't repeat things obvious from the codebase

### Additional Steps Writing

- **Use exact phase enum values** from the per-skill mapping — `validate` checks these
- **Keep steps actionable** — each step describes a concrete action
- **Limit to 2-3 steps per phase** — too many slow down workflow and dilute attention
- **Best insertion points:** `Before ship` (quality gates), `After implement` (post-checks), `After verify` (refactor wrap-up)

### Constraint Writing

- **Quantify where possible** — "Maximum 400 lines changed per PR" not "Keep PRs small"
- **State the consequence** — "Database migrations must be backwards-compatible — breaking migrations block deploy"
- **Constraints are hard limits** — skills treat these as non-negotiable

### Custom Reviewer Authoring (review-extra)

Companion file: `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-review-extra.md`. Read before creating or editing any `.geniro/instructions/review-extra/<slug>.md`.

### File-size guidance

**Soft guidance: when an instruction file passes ~300 lines, consider splitting** (by scope or by topic). A 350-line file that's well-organized and all-load-bearing is fine.

### What goes here vs. `.claude/rules/` vs. CLAUDE.md

- **`.geniro/instructions/<skill>.md`** — skill-scoped rules at phase boundaries
- **`.geniro/instructions/code-style.md`** — cross-cutting code-style rules at every Geniro code-writing/review step
- **`.claude/rules/<scope>.md` with `paths:`** — file-pattern-scoped, Anthropic-native
- **CLAUDE.md** — always-loaded essentials only

**What NOT to put in `.geniro/instructions/<skill>.md` or `code-style.md`:**

- Per-file-pattern code rules → `.claude/rules/<scope>.md`
- Tech stack info → CLAUDE.md (detected by `/setup`)
- Build/test/lint commands → CLAUDE.md
- Project structure facts → CLAUDE.md
- Compaction-surviving global gates → CLAUDE.md
- Temporary rules → conversation context
- Rules for skills that don't load instructions (operational skills)

## Anti-pattern check

| # | Anti-pattern | Status |
|---|---|---|
| 1 | One giant prompt | ✅ SKILL.md modular; no helper sprawl needed |
| 2 | One giant tool | ✅ N/A — Edit/Write/Bash native |
| 3 | Unbounded autonomous loop | ✅ 3-retry on scope ambiguity, then final abort AUQ |
| 4 | Autonomous external sends | ✅ N/A — no external send surface |
| 5 | No approval state | ✅ N/A — stateless; user re-confirms on each invocation. `approvals[]` is for stateful skills |
| 6 | No durable plans or goals | ✅ N/A — CRUD is inherently single-transaction |
| 7 | No compaction strategy | ✅ Output files (L4) survive compaction natively (file-on-disk Block 1) |
| 8 | All connectors loaded up front | ✅ N/A |
| 9 | High-risk tools without policy | ✅ §ACI table; Write/Delete AUQ-gated; hooks block bulk deletion |
| 10 | Subagents before single-agent MVP measured | ✅ Zero subagents |
| 11 | Dynamic timestamps in plugin-distributed Markdown | ⚠ Implementation note — `/instructions` SKILL.md must NOT embed runtime timestamps. Stateless skill — no state-file timestamp risk |
| 12 | Non-deterministic agent registration order | ✅ N/A |

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I'll auto-fix `validate` issues to save the user a step" | No — auto-fix would silently mutate user-authored content. `validate` reports; user fixes via `edit`. |
| "I'll silently overwrite existing instruction file" | No — for `create` on existing, present overwrite/edit-instead/cancel via AUQ. |
| "I'll skip the per-skill phase-enum check because the user said `### After Phase 1`" | No — old enums fail silently in the loader. Validate-mode catches and suggests the canonical name - |
| "I'll spawn a subagent to do the freeform rule synthesis" | No — `/instructions` doesn't spawn subagents (per sub-decision). |
| "I'll output the questions as plain text instead of `AskUserQuestion`" | No — every WAIT gate uses `AskUserQuestion`. |
| "I'll rename a per-skill scope to something custom (e.g., implement → my-flow)" | No — scope names are fixed; pick from the 11 valid scopes. |
| "I'll skip showing the scope-specific scaffold to save tokens" | No — scaffolds make the empty-file moment less confusing; they're not optional. |

## Definition of Done

- [ ] Intent detected from freeform arguments (or default to `list`)
- [ ] Scope(s) resolved — single or batch — within 3 AUQ retry cap
- [ ] File operations completed successfully
- [ ] User confirmed before any destructive operation (delete)
- [ ] Validation checked structure, phase names, scope validity, dropped-skill refs, and description rules
- [ ] All user interactions used `AskUserQuestion` — no plain-text questions
- [ ] review-extra files validated against slug uniqueness, built-in collision, model/severity-default value sets, paths syntax, and count caps
- [ ] Scope-specific scaffold shown on `create` (not skipped)

## Cross-references

- PERSISTENT (CRUD) — `.geniro/instructions/` tier and optimistic mtime check
- L4 Procedural — `.geniro/instructions/*.md` is the canonical L4 home
- Block 1 — file-on-disk compaction-survival channel
- / other skills / phase enums — phase-name validation table cites them
- / / — phase enums for `/onboard` and `/investigate`
- — `/setup` writes `user-preferences.md`; This skill is the manual-edit interface
- — `/actions validate` shares the rule set
- *(internal)* — full design rationale
