# M10b — `/geniro:instructions` redesign

**Milestone:** M10 (operational skills) — part **b** of 4. Companion to M10a (`/setup`), M10c (`/actions`), M10d (`/update`).

**Status:** Decided 2026-05-19. Builds on M1 (T3 `.geniro/instructions/` PERSISTENT/CRUD tier), M2 (L4 procedural layer), M3 (instructions loaded by every skill's Step 0 + phase-boundary refresh), M4-M9 (consuming skills' phase enums), M10a (introduces `user-preferences.md` scope).

**Cross-cutting closures landing here:**

- **P-M10-2** — `/instructions validate` lint rules. Practical scope: applied to `review-extra/<slug>.md` frontmatter (the only scope with a `description:` field) and a structural-validation pass over every scope (sections present, frontmatter parses, phase-name correctness, no references to dropped skills).

---

## 1. Purpose

A CRUD frontend over the `.geniro/instructions/` directory — the L4 procedural memory layer (M2 §5.4). Five operations: `list`, `create`, `edit`, `validate`, `delete`. Stateless: every invocation is a single transaction against the file system; no state file (per M10a Q5).

**Why a dedicated skill instead of "user opens the file in their editor":**

- Discoverability — users learn the structure (Rules / Additional Steps / Constraints) via interview-driven scaffolding, not a stale README.
- Validation — `validate` mode catches stale references to dropped skills, phase-name typos in `Additional Steps`, and `review-extra/` slug collisions before the next pipeline run silently no-ops.
- Loader contract — every instruction file participates in the `_shared/load-custom-instructions.md` Echo contract; the skill ensures files conform to the shape the loader expects.

**Anti-goal:** No multi-edit batch state machine. CRUD is single-transaction; bulk edits go through the editor, not through `/instructions`.

---

## 2. Architecture overview

### 2.1 State machine

`/instructions` has **no state file** (per M10a Q5 — stateless single-pass operation). The phase enum below describes runtime flow only — not persisted.

```
init (parse $ARGUMENTS, no AUQ)
  │
  ▼
parse
  │ resolve intent (list|create|edit|validate|delete) and scope(s)
  │ ambiguity → AskUserQuestion
  ▼
execute
  │ branch on intent: list (read+print) | create (scaffold) | edit (open) | validate (lint) | delete (rm + confirm)
  ▼
done
       │
       └─ failed (parse failed, scope invalid after 3 AUQ retries, write blocked by hooks)
```

### 2.1.1 Termination case → state mapping

No state file, but failure paths still report a structured termination reason in the final user-facing message.

| Termination cause | Message format |
|---|---|
| User cancelled at any AUQ | `aborted: user cancelled at <step>` |
| Scope resolution failed after 3 AUQ retries | `aborted: scope unresolved after 3 AUQ rounds` |
| Validation found N issues, user picked "Abort" | `aborted: validate surfaced N issues; user picked abort` |
| Write blocked by file-protection hook | `aborted: file-protection hook blocked write to <path>; see .geniro/safety.json` |
| Delete blocked by `.geniro/` deletion guard | `aborted: .geniro/ deletion guard blocked rm of <path>; see .geniro/safety.json` |

### 2.2 Loop invariants

Per M4 §2.2 — `/instructions` inherits all 7 invariants. Specifics for this CRUD skill:

1. **One result per subagent call** — `/instructions` never spawns subagents (CRUD is too small for parallelism). Invariant 1 is N/A but the constraint is honored vacuously.
2. **Args validated before exec** — every Write to `.geniro/instructions/*.md` is preceded by scope validation (regex match) AND file-existence check (create vs edit branching).
3. **Permission before side-effect** — Write/Delete are AUQ-gated.
4. **Bounded structured results** — `list` mode truncates per-file body display at ~2000 chars (long custom-rules files get a "see file for full content" footer).
5. **Hard escalation gates** — 3-retry on scope ambiguity → final AUQ "abort or pick from valid scopes only".
6. **Observations not assumed success** — every `Read` / `Write` checks return status; no silent skips.
7. **Errors as structured observations** — surfaced inline in the final user message (no state file to write to).

### 2.3 Budgets — quality-first framing (per M4 §2.3)

`/instructions` has **zero Class-A hard kill caps**. CRUD operations should always complete or surface a clear error.

| Layer | Lever | Why |
|---|---|---|
| **Class-B escalation gates** | 3-retry scope ambiguity → final AUQ "abort" | If the user can't disambiguate scope after 3 rounds, abort cleanly with a message naming the valid scope set |
| | `list` mode body truncation at ~2000 chars/file | A 5000-line `code-style.md` doesn't help the user inspect the file inventory; truncate with footer |
| **Architecture constraints** | Stateless (no state file) | CRUD ops are single-transaction; persistent state would just complicate the model |
| | No subagent spawns | The operations are too small; spawning costs more than executing inline |
| **NOT capped** | Number of scopes processed in batch mode, number of files in `review-extra/`, file size after edit, AUQ chain depth for scope picking | Quality-first |

### 2.4 ACI surface per phase

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `parse` | `Read`, `Bash` (read-only: `ls`, `cat`, `find`, `grep`), `Glob`, `AskUserQuestion` | `Write`, `Edit`, `Bash` (mutating), all `mcp__*`, network |
| `execute` | `Read`, `Write`, `Edit`, `Bash` (`mkdir -p`, `rm` after AUQ confirm), `Glob`, `Grep`, `AskUserQuestion` | `Agent` (no subagents), `mcp__github__*`, network egress |
| `DONE` | (none — terminal report) | (none) |

External sends: not in `/instructions` ACI ever.

---

## 3. Scope deltas vs. pre-M10 `/geniro:instructions`

### 3.1 Removed

| Removed item | Why |
|---|---|
| `decompose` scope (per-skill file) | `/decompose` was dropped — merged into `/plan` |
| `follow-up` scope | `/follow-up` was dropped — `/implement` handles any size |
| `deep-simplify` scope | `/deep-simplify` was dropped — became `/review --simplify` flag |
| `brainstorm` scope (was rules-only in current table) | `/brainstorm` was dropped — merged into `/plan` |
| `features` / `learnings` / `actions` / `cleanup` / `vendor` rules-only entries | Those skills are gone (or are operational skills that don't carry custom rules) |
| Implicit "per-skill file phase mapping" buried in table cell text | Replaced by §6.3 explicit phase-enum table per M4-M9 spec docs |

### 3.2 Kept (with adaptation)

| Kept item | Adaptation |
|---|---|
| 5-op CRUD (`list`, `create`, `edit`, `validate`, `delete`) | Preserved verbatim |
| Cross-cutting `code-style.md` scope | Preserved; loads at every code-writing AND code-review step per the same rule as today |
| Directory-style `review-extra/<slug>.md` scope | Preserved verbatim; same frontmatter schema (`slug`, `description`, `model`, `paths`, `severity-default`) |
| `global.md` always-loaded scope | Preserved verbatim |
| Loader integration via `_shared/load-custom-instructions.md` | Preserved; Echo contract unchanged |
| Interview-driven `create` flow with AskUserQuestion | Preserved; question batches stay under the 4-option AUQ cap (chained where needed) |
| Scope chaining for the >4-options case | Preserved; chain pattern documented in `_shared/feedback_askuserquestion_extension.md` |

### 3.3 Added (new in M10b)

| Added item | Source |
|---|---|
| `user-preferences.md` scope (always-loaded across all Geniro skills) | M10a Q8 — `/setup` writes this file; `/instructions edit user-preferences` is the user's manual-edit path |
| `onboard.md` per-skill scope (rules-only, no Additional Steps phases) | M9 — `/onboard` is phase-bearing; rules can scope its discovery work |
| `investigate.md` per-skill scope (rules-only) | M9 — `/investigate` is phase-bearing; rules can scope its Q&A behavior |
| **`validate` mode lint rules (P-M10-2 closure)** | New — see §10 for the full rule set |
| Structural validation pass (Rules / Additional Steps / Constraints sections present and parsable) | New — same `validate` mode |
| Phase-name validation against M4-M9 phase enums | New — same `validate` mode |
| Dropped-skill reference detection | New — same `validate` mode |

---

## 4. Decisions recorded so far

| ID | Question | Decision |
|---|---|---|
| **Q1** | Bundle vs split | Split — this is part b of 4 |
| **Q2** | Phase model | Skill-natural — `/instructions` gets a 3-step parse → execute → done flow (no state machine, no resume) |
| **Q4** | Connector safety | Out of scope here — applies to M10c (`/actions`) |
| **Q5** | State files | None — `/instructions` is stateless |
| **Q8** | user-preferences home | Confirmed — `user-preferences.md` joins the scope list (was created by `/setup`; `/instructions edit user-preferences` is the manual-edit interface) |

Sub-decisions during defect-inventory walk:

| Sub-decision | Resolution |
|---|---|
| Should `validate` mode auto-fix issues? | **No.** Validate reports issues; fixes are user-driven via `edit` mode. Auto-fix would mutate user-authored content unexpectedly — violates the "user-content sacred" rule that hooks already enforce |
| Should `delete` mode require typing the scope name to confirm? | **No** — `AskUserQuestion` 2-option confirm (Confirm delete / Cancel) is sufficient; hooks block bulk deletes regardless |
| Should `list` mode show file sizes + last-modified? | **Yes** — adds zero AUQ overhead, useful signal for "which files are stale" |
| Should `create` mode prefill `Rules:` with examples specific to the picked scope? | **Yes** — scope-specific scaffolds make the empty-file moment less confusing (e.g., `code-style.md` scaffold shows naming conventions, `review.md` scaffold shows quality-gate examples) |
| Should `validate` mode lint user-edited `global.md` against the M4-M9 phase enums? | **No** — `global.md` has no `Additional Steps` phase-mapping (it's rules-only across all skills) |
| Should the skill spawn agents for any phase? | **No** — CRUD is too small; subagents would cost more than executing inline |

---

## 5. Defect inventory (audit 2026-05-19 — before/after)

10 defects identified in current `/instructions` SKILL.md (654 LOC). All closed in this redesign.

| # | Defect | Fix |
|---|---|---|
| **D1** | Valid scopes list contains dropped skills (`decompose`, `follow-up`, `deep-simplify`, `brainstorm`, `features`, `learnings`, `actions`, `cleanup`, `vendor`) | New valid scopes set (§6.1): `global`, `code-style`, `user-preferences`, `review-extra` (directory), and 7 per-skill files (`implement`, `plan`, `review`, `debug`, `refactor`, `onboard`, `investigate`) |
| **D2** | Per-skill file phase mapping uses old phase names (e.g., "After Phase 1 (Discover)", "After Phase 4 (Implement)") that don't match M4-M9 phase enums | §6.3 phase-name table cites M4-M9 phase enums verbatim (`IMPLEMENT` / `REVIEW_AND_VALIDATE` / `SHIP` for `/implement`, `PLAN_STAGE_A` ... etc.) |
| **D3** | `validate` mode mentioned in CLAUDE.md skill blurb but not actually specced in SKILL.md | §10 specs the validate mode rule set (P-M10-2 closure) |
| **D4** | No L4 (procedural memory) layer documentation — readers don't know how instructions relate to M2 layers | §11 Memory I/O links every scope to its M2 layer; all `.geniro/instructions/*.md` files are L4 procedural |
| **D5** | No reference to M3 SessionStart compact hook re-injection (instructions are part of the compact-recovery surface) | §11 Memory I/O notes the compact-survival route via M3 §6 Block 1 (file-on-disk) |
| **D6** | No anti-pattern check section — fails P-MP-1 | §13 added |
| **D7** | No master plan reconciliation section | §12 added |
| **D8** | No structural validation pass — a user can write malformed `Rules / Additional Steps / Constraints` and the loader silently accepts it | §10 validate-mode Step 1 parses sections; warns on missing / misspelled section headers |
| **D9** | `user-preferences.md` (new scope from M10a) not listed | Added in §6.1 + §6.2 (loader integration) |
| **D10** | The current chained-AUQ pattern (3 chained questions) for scope picking is fragile and assumes a fixed scope count | §7.1 simplifies: with 11 scopes, use a 2-level chain (category → specific) ; the count is now stable, no need for "Other" overflow at level 2 |

---

## 6. Mode: list — **DECIDED**

### 6.1 Valid scope set

| Scope name | File path | Layer | Loaded by | Notes |
|---|---|---|---|---|
| `global` | `.geniro/instructions/global.md` | L4 | Every Geniro pipeline + discovery skill at Step 0 + phase-boundary refresh | Rules and Constraints only (no `Additional Steps` — global has no canonical phase enum to attach to) |
| `code-style` | `.geniro/instructions/code-style.md` | L4 | All code-writing skills (`implement`, `refactor`) AND all code-review steps (`review`, `implement` Phase Review, `refactor` Phase Verify); also pre-inlined into reviewer-agent prompts for `guidelines` / `conventions` / `design` / `architecture` dimensions | Cross-cutting scope; no per-skill phase mapping |
| `user-preferences` | `.geniro/instructions/user-preferences.md` | L4 | Every Geniro pipeline + discovery skill at Step 0 + phase-boundary refresh | Created by `/setup` Phase Generate; `/instructions edit user-preferences` is the manual-edit path. Rules and Constraints only |
| `review-extra/<slug>` | `.geniro/instructions/review-extra/<slug>.md` (directory-style — one file per slug) | L4 | `/review` Phase 2, `/implement` Phase REVIEW_AND_VALIDATE, `/refactor` Phase VERIFY via `_shared/load-custom-reviewers.md`; spawned as additional reviewer-agent dimensions | Frontmatter schema preserved verbatim from current skill (`slug`, `description`, `model`, `paths`, `severity-default`) |
| `implement` | `.geniro/instructions/implement.md` | L4 | `/implement` at Step 0 + phase-boundary refresh | `Additional Steps` subsections map to M4 phase enum |
| `plan` | `.geniro/instructions/plan.md` | L4 | `/plan` at Step 0 + phase-boundary refresh | `Additional Steps` map to M5 phase enum |
| `review` | `.geniro/instructions/review.md` | L4 | `/review` at Step 0 + phase-boundary refresh | `Additional Steps` map to M6 phase enum |
| `debug` | `.geniro/instructions/debug.md` | L4 | `/debug` at Step 0 + phase-boundary refresh | `Additional Steps` map to M7 phase enum |
| `refactor` | `.geniro/instructions/refactor.md` | L4 | `/refactor` at Step 0 + phase-boundary refresh | `Additional Steps` map to M8 phase enum |
| `onboard` | `.geniro/instructions/onboard.md` | L4 | `/onboard` at Step 0 + phase-boundary refresh | Rules and Constraints only (M9 §6/§7 has 2 phases; `Additional Steps` is allowed but discovery skills rarely need them) |
| `investigate` | `.geniro/instructions/investigate.md` | L4 | `/investigate` at Step 0 + phase-boundary refresh | Same as `onboard` — rules-focused, `Additional Steps` discouraged |

Operational skills (`/setup`, `/instructions`, `/actions`, `/update`) do NOT load instruction files (per M10a §6.2 — `setup` is rules-only via the loader with `LOAD_TIER: rules-only`; `/instructions`, `/actions`, `/update` are out of the loader scope entirely).

### 6.2 list output format

```
$ /geniro:instructions list

Custom instructions in .geniro/instructions/ (project: my-project):

global.md                          348 B    modified 3 days ago
code-style.md                      1.2 KB   modified 2 hours ago
user-preferences.md                412 B    modified 5 days ago    [generated by /setup]
implement.md                       (none — create with /instructions create implement)
plan.md                            (none)
review.md                          892 B    modified 1 week ago
debug.md                           (none)
refactor.md                        (none)
onboard.md                         (none)
investigate.md                     (none)
review-extra/                      (directory — 2 files)
  ├── sql-bindings.md              1.6 KB   modified 4 days ago
  └── accessibility-aria.md        2.1 KB   modified 1 day ago

11 scopes total · 5 active · 6 not-yet-created
```

Add `--with-content` flag to dump file bodies inline (truncated at ~2000 chars per file).

### 6.3 Per-skill `Additional Steps` phase mapping

When a `Additional Steps` subsection is encountered during validate-mode, it must match a real phase enum value from the corresponding skill's M-doc. Phase enum values are **lowercase-hyphenated** per M4-M9 convention; subsection prose may use any case, validate-mode normalizes for comparison.

| Scope | Real phase enum (M-doc) | Allowed `Additional Steps` subsection names (canonical lowercase form; Title-Case prose also accepted) |
|---|---|---|
| `implement` | M4 §2.1: `analyze \| implement \| self-review \| ship \| phase-2-escalated \| phase-3-escalated \| done \| aborted \| debug-handoff` | `After analyze`, `After implement`, `After self-review`, `Before ship` |
| `plan` | M5 §2.1: `mode-detect \| explore \| clarify \| approaches \| section-approve \| write-spec \| validate \| user-approve \| handoff \| phase-8-escalated \| done \| aborted` | `After explore`, `After clarify`, `After approaches`, `After write-spec`, `Before user-approve` |
| `review` | M6 §2.1: `triage \| mechanical-prepass \| llm-spawn \| filter \| stratify \| persist \| action-gate \| done \| aborted \| escalated` | `After triage`, `After llm-spawn`, `After filter`, `Before action-gate` |
| `debug` | M7 §2.1: `investigate \| propose \| ship \| phase-1-escalated \| ship-summary-only \| aborted` | `After investigate`, `After propose`, `Before ship` |
| `refactor` | M8 §2.1: `plan \| apply \| verify \| plan-escalated \| routed \| reverted \| done` | `After plan`, `After apply`, `Before verify` |
| `onboard` | M9 §6/§7: `mode-detect \| discover \| map \| done \| aborted \| *-escalated` | `After discover`, `Before map` |
| `investigate` | M9 §8/§9/§10: `classify \| investigate \| present \| done \| aborted \| *-escalated` | `After classify`, `After investigate`, `Before present` |

Subsection names are case-insensitive; validate-mode lowercases-and-hyphenates before comparing against the enum.

Free-form subsections (e.g., `After my-custom-rule`) are flagged as `LOW` severity warning, not error — users may want narrative names. Subsections referencing dropped legacy phase enums (`After Phase 4 (Implement)`, `After Discover Context`, `After PHASE 1`, etc., from the pre-M4 8-phase scheme) raise `MEDIUM` — those phases no longer exist.

---

## 7. Mode: create — **DECIDED**

### 7.1 Scope ambiguity resolution (simplified vs current)

Current skill chains up to 3 AUQs to pick from 10 scopes. With 11 scopes in M10b, simplify to a 2-level chain:

**Level 1 — category:**

```
Question: Which instruction file scope?
Options:
  - "global" — Project-wide rules loaded by every Geniro skill
  - "code-style" — Cross-cutting style rules for code writing AND code review
  - "user-preferences" — User communication style and pipeline defaults (also editable via /setup re-run)
  - "Specific skill or review-extra" — Pick from per-skill (7) or review-extra (custom reviewer)
```

If user picks "Specific skill or review-extra", chain level 2:

**Level 2 — specific:**

```
Question: Which specific scope?
Options:
  - "review-extra (new custom reviewer)" — Add a custom reviewer dimension (asks for slug)
  - "implement / plan / review" — Pipeline skills (chain to L2b)
  - "debug / refactor" — Pipeline skills (chain to L2b)
  - "onboard / investigate" — Discovery skills (chain to L2b)
```

If user picks one of the per-skill groups, chain L2b:

**Level 2b — pick exact skill (2-3 options, fits in AUQ):**

Implementation note: avoid the previous "Other" overflow pattern; with 11 stable scopes, the chain depth is fixed at 2-3 levels and the option count per level is fixed.

### 7.2 Approvals precheck (P-M1-1) — applicable here?

`/instructions` is stateless (no state file), so P-M1-1 approvals[] persistence is **N/A** at the skill level. Each invocation starts fresh.

**Exception:** if the user runs `/instructions edit user-preferences`, that file feeds into other skills' `approvals[]` (e.g., `/setup` may have written `ship_mode_default: open-pr-draft` to the user-preferences.md body; downstream skills read from L4, not from `/setup`'s persisted approvals[]). This is the L4 → consumer flow, not an approvals[] thing.

### 7.3 Scope-specific scaffolds

Each `create <scope>` writes a file with scope-specific example Rules. Examples:

**`code-style.md` scaffold:**

```markdown
# Custom Instructions

## Rules

- Use lowercase-hyphen for component file names (e.g., `user-profile.tsx`, not `UserProfile.tsx`).
- Prefer named exports over default exports for tree-shaking.
- All TypeScript interfaces use `I` prefix... (or remove this rule if you don't follow that convention)

## Constraints

- No `any` type without an inline `// reason: ...` comment.
```

**`user-preferences.md` scaffold:** (rarely created manually — `/setup` does it; but `create user-preferences` is allowed for users who skipped `/setup`)

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

**`implement.md` scaffold:** (shows phase-boundary structure)

```markdown
# Custom Instructions

## Rules

- (none — add project-specific rules here)

## Additional Steps

### After IMPLEMENT
- (example: "Run npm run codegen before declaring implementation complete")

### Before SHIP
- (example: "Ensure CHANGELOG.md has an entry for the change")

## Constraints

- Maximum PR size: 500 lines changed (warn user if exceeded; do not block)
```

Scaffolds for `plan.md`, `review.md`, `debug.md`, `refactor.md`, `onboard.md`, `investigate.md`, `review-extra/<slug>.md` follow the same pattern — phase-boundary subsections use the M-doc phase enum for that skill.

### 7.4 Write target — atomic + AUQ-gated

```
Write target: <PROJECT_ROOT>/.geniro/instructions/<scope>.md
  OR:         <PROJECT_ROOT>/.geniro/instructions/review-extra/<slug>.md
```

Before write:

1. Confirm file doesn't already exist (if `create` mode); else AUQ "File exists — overwrite, edit instead, or cancel?"
2. Show preview of the scaffold body via final AUQ "Write scaffold? Options: write / edit body before writing / cancel".
3. On `write`, atomic write per M1 §Atomic write helper (`mktemp` + `mv` rename — never partial-write).

---

## 8. Mode: edit — **DECIDED**

### 8.1 Flow

1. Resolve scope (§7.1).
2. Read existing file. If missing, branch to `create` mode.
3. Display current body to user (via final-report inline).
4. Three-way AUQ: `open in editor (external) | rewrite via dialogue (Geniro asks for additions/deletions) | cancel`.
5. **External editor path:** print the absolute path to the file, instruct user "edit it externally and re-run `/instructions validate <scope>` when done". `/instructions` exits.
6. **Rewrite via dialogue path:** interview-style sequence of AUQs (Add a Rule / Add an Additional Step / Add a Constraint / Remove a Rule by number / Done). Each captured edit is applied to an in-memory copy; final write is AUQ-gated.

The dialogue path is intentionally simpler than the current skill's prompt-driven freeform edit — it stays inside AUQ contracts and avoids prompt-injection through user-supplied text.

### 8.2 Body section invariants

After edit:

- `## Rules` section present (may be empty list).
- `## Additional Steps` section present (omitted only for rules-only scopes: `global`, `code-style`, `user-preferences`, `review-extra/<slug>`, `onboard`, `investigate`).
- `## Constraints` section present (may be empty list).
- Frontmatter (for `review-extra/<slug>.md`) parses YAML cleanly.

Violations are not auto-fixed; `validate` mode surfaces them on next invocation.

---

## 9. Mode: delete — **DECIDED**

### 9.1 Flow

1. Resolve scope.
2. Read existing file (confirm it exists; else "nothing to delete" exit).
3. AUQ: 2-option `Confirm delete | Cancel`. Show file size and last-modified for confirmation context.
4. On confirm: `rm <path>`. The `.geniro/` deletion guard hook **allows** deletion of an individual file at `.geniro/instructions/<scope>.md` (per the hook's "Per-file `rm -f` … remain allowed" rule); only bulk `rm -rf .geniro/instructions/` is blocked.
5. Print confirmation: "Deleted .geniro/instructions/<scope>.md."

For `review-extra/<slug>.md`: delete only the specific slug file. The `review-extra/` directory itself remains.

For `review-extra` without slug arg AND multiple files: AUQ asks which to delete. For `review-extra` ALL: would require bulk-delete; explicitly refused with message "Use `/instructions delete review-extra <slug>` per-file; bulk delete protected by guard hook."

---

## 10. Mode: validate — **DECIDED (P-M10-2 closure)**

### 10.1 Flow

`validate` accepts `<scope>` arg or no arg (== validate all existing files). Operates as a read-only pass; never mutates.

### 10.2 Lint rule set

For each `.geniro/instructions/<file>`:

**Structural checks (apply to all scopes):**

| Check | Severity | Example violation |
|---|---|---|
| File parses as valid Markdown | `CRITICAL` | Binary file masquerading as `.md` |
| `## Rules` heading present | `HIGH` | File has body but no `## Rules` header |
| `## Constraints` heading present | `HIGH` (skip for `review-extra/<slug>.md` — uses `# Criteria` instead) | Missing `## Constraints` |
| File size < 200 lines | `MEDIUM` | Long instruction files get ignored by the model (per report.md §2244 anti-pattern) |

**Reference checks:**

| Check | Severity | Example violation |
|---|---|---|
| No references to dropped skills (`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`) | `HIGH` | "After /decompose" subsection in `implement.md` |
| No references to dropped phase names (e.g., "Phase 4 Implement" was renamed to `IMPLEMENT` in M4) | `MEDIUM` | `### After Phase 4 (Implement)` instead of `### After IMPLEMENT` |
| `Additional Steps` subsections match the per-skill phase enum (§6.3) | `MEDIUM` | `### After QA-PHASE` in `implement.md` (no such phase) |

**Per-scope checks:**

| Scope | Extra checks |
|---|---|
| `review-extra/<slug>.md` | Frontmatter parses YAML; `slug` matches filename; `slug` not a built-in dimension name (`bugs`, `security`, `architecture`, etc.); `description` is one line; `description` length ≤ 250 chars; `description` starts with "Use when" OR explicitly describes intent (lint preference, not block); `model` in `{haiku, sonnet, opus}` if present; `paths` is a list if present; `severity-default` in `{CRITICAL, HIGH, MEDIUM, LOW}` if present |
| `user-preferences.md` | All 4 canonical preference rules present (default branch, ship mode, reviewer set, communication style) — `MEDIUM` if any missing |
| `code-style.md` | At least 1 rule under `## Rules` — `LOW` warning if empty (file with no rules is a no-op) |

**P-M10-2 description lint rules** (applied to `review-extra/<slug>.md` frontmatter `description:` field only — the only scope with a `description:` field):

| Rule | Severity |
|---|---|
| lowercase-hyphens slug (`^[a-z][a-z0-9-]*$`) | `HIGH` (CRITICAL if slug fails validation entirely) |
| description starts with "Use when" or describes intent vs implementation | `LOW` warning (preference, not hard rule) |
| description mentions adjacent terms (e.g., for `sql-bindings`: mentions "SQL", "ORM", "DAO") | `LOW` warning (helps discoverability) |
| description has explicit boundary clauses ("Skip for …", "Not for …") | `LOW` info (suggested for clarity, not required) |

### 10.3 Output format

```
$ /geniro:instructions validate

Validation results: 3 files checked, 2 issues found.

✓ global.md                       no issues
⚠ implement.md                    1 MEDIUM
  └── Line 14: "### After Phase 4 (Implement)" → should be "### After IMPLEMENT" (M4 phase enum)
⚠ review-extra/sql-bindings.md    1 LOW
  └── Frontmatter description: missing "Skip for" boundary clause (LOW — informational)

To fix: /geniro:instructions edit implement
       /geniro:instructions edit review-extra sql-bindings
```

Exit status: 0 if no `CRITICAL` or `HIGH` issues; non-zero otherwise. `MEDIUM` / `LOW` are warnings.

### 10.4 No auto-fix

Per sub-decision in §4 — validate reports; does not mutate. Auto-fix would silently change user-authored content.

---

## 11. Memory I/O (M2 §13 obligation)

`/instructions` is the **CRUD frontend for L4 (procedural memory)** — every operation writes / reads / lints L4 files.

| Layer | Read at | Write at | Notes |
|---|---|---|---|
| **L1 (CLAUDE.md)** | not read | not written | `/instructions` does NOT touch CLAUDE.md — that's `/setup`'s domain |
| **L2 (`learnings.jsonl`)** | not read | not written | `/instructions` is a CRUD frontend, not a knowledge-emit producer (per M2 §5.3 trigger table — no `convention` emit on edits; users can manually run `/instructions validate` to lint, but the edit itself is not an emit event) |
| **L3 (semantic project files)** | not read | not written | Out of scope |
| **L4 (`.geniro/instructions/*.md`)** | `list` reads all; `validate` reads target; `edit` reads target before mutation | `create` / `edit` write; `delete` removes | This is `/instructions`'s entire surface |

**M3 compaction-survival route:** `.geniro/instructions/*.md` files are file-on-disk (M3 §6 Block 1). After compaction, the SessionStart hook's suggested-file list re-reads `global.md` + active skill's `<skill>.md` + `code-style.md` + `user-preferences.md` via `_shared/load-custom-instructions.md` Echo contract. `/instructions`'s CRUD writes are immediately durable — survives compaction without any extra mechanism.

---

## 12. Master plan reconciliation

| Master plan ref | Closure |
|---|---|
| §107 row M10 (operational skills) | M10b covers `/instructions` |
| §122 row M10 ("lowest priority") | Respected — no expansion beyond CRUD; subagent count = 0; phases = 3 (parse → execute → done) |
| **P-M10-2** "Skill description lint rules" | Closed via §10.2 P-M10-2 sub-table (applied to `review-extra/<slug>.md` frontmatter description field) |
| **P-MP-1** "Anti-patterns guardrail" | §13 below |
| Forward-reference from M10a §7.3 (user-preferences as L4) | Closed — `user-preferences` is a first-class scope in §6.1 |

---

## 13. Anti-pattern check (P-MP-1 obligation)

| # | Anti-pattern | M10b status |
|---|---|---|
| 1 | One giant prompt | ✅ N/A — `/instructions` SKILL.md will be ~200 LOC, no `_shared/` helper sprawl needed for CRUD |
| 2 | One giant tool | ✅ N/A — Edit/Write/Bash native |
| 3 | Unbounded autonomous loop | ✅ 3-retry on scope ambiguity, then final abort AUQ; no infinite re-ask |
| 4 | Autonomous external sends | ✅ N/A — `/instructions` has no external send surface |
| 5 | No approval state | ✅ N/A — stateless skill; user re-confirms on each invocation. `approvals[]` is for stateful skills |
| 6 | No durable plans or goals | ✅ N/A — CRUD is inherently single-transaction |
| 7 | No compaction strategy | ✅ Output files (L4) survive compaction natively (file-on-disk per M3 §6 Block 1); skill itself runs single-turn so compaction during the skill itself is unlikely |
| 8 | All connectors loaded up front | ✅ N/A |
| 9 | High-risk tools without policy | ✅ §2.4 ACI table; Write/Delete AUQ-gated; hooks block bulk deletion |
| 10 | Subagents before single-agent MVP measured | ✅ Zero subagents in `/instructions` |
| 11 | Dynamic timestamps in plugin-distributed Markdown | ⚠ Implementation note — `/instructions` SKILL.md should not embed runtime timestamps. State file would carry timestamps, but `/instructions` is stateless, so no state-file timestamp risk |
| 12 | Non-deterministic agent registration order | ✅ N/A |

---

## 14. Open questions

| # | OQ | Resolution path |
|---|---|---|
| **OQ-M10b-1** | Should `validate` mode also lint `.geniro/actions/<slug>.md` frontmatter? | Cross-skill concern. Defer to M10c which owns `/actions` schema definition. M10c will spec whether `/instructions validate review-extra` should be paired with a `/actions validate` (likely yes — same lint rule set) |
| **OQ-M10b-2** | If a user renames a per-skill file (e.g., `/instructions edit implement` but the user wants to rename it to `my-flow.md`), what happens? | Refuse — scope names are not user-editable. Document in `/instructions create` AUQ: "Scope name is fixed; pick from the 11 valid scopes" |
| **OQ-M10b-3** | Should `list` mode also show which skills load each file? | Yes — adds clarity. Already shown in §6.1 table, but list output (§6.2) only shows file inventory. Consider adding a `--with-loaders` flag |
| **OQ-M10b-4** | Should `/instructions validate` be wired as a pre-commit hook for projects that opt in? | Out of scope for M10b — that's a user-defined hook in `.geniro/actions/` (M10c territory). M10b only provides the validate command |

---

## 15. Cleanup checklist

`/instructions` is stateless — no state files to clean.

Side-effects to consider:

| Side-effect | Cleanup behavior |
|---|---|
| `create` written a file | No cleanup — user-authored content is persistent; only the user can delete (via `/instructions delete <scope>`) |
| `edit` modified a file | No cleanup — atomic write replaced content |
| `delete` removed a file | No cleanup — file is gone; the next `create` re-scaffolds |
| `validate` produced report output | No persistence — report is in-conversation only; not written to disk |

---

## 16. Cross-references

- **M1 §T3 PERSISTENT (CRUD)** — `.geniro/instructions/` tier and concurrency model (optimistic mtime check per M1 §T3 CRUD)
- **M1 §Architecture overview** — directory tree row `instructions/` already lists `global.md`, `code-style.md`, `<skill>.md`, `review-extra/<slug>.md`; M10b extends conceptually with `user-preferences.md` (same path pattern, no tree change needed — `<skill>.md` covers it nominally)
- **M2 §5.4 L4 Procedural** — `.geniro/instructions/*.md` is the canonical L4 home
- **M2 §13 OQ "Validator framework"** — `/instructions validate` IS a validator implementation; closes part of OQ M2-3 (instruction-file schema validators)
- **M3 §6 Block 1** — file-on-disk compaction-survival channel; instruction files survive natively
- **M4 §2.1 / M5 / M6 / M7 / M8 phase enums** — §6.3 phase-name validation table cites them
- **M9 §6 / §7 / §8 / §9 / §10** — phase enums for `/onboard` and `/investigate`
- **M10a §7.3** — `/setup` writes `user-preferences.md`; M10b is the manual-edit interface
- **M10c** — `/actions` schema (forward — frontmatter validation may share rule set per OQ-M10b-1)
