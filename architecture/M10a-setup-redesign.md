# M10a — `/geniro:setup` redesign

**Milestone:** M10 (operational skills) — part **a** of 4 (`/setup` first, then `/instructions`, `/actions`, `/update`).

**Status:** Decided 2026-05-19. Builds on M1 (state-files framework), M2 (memory layers), M3 (compaction survival), M4 (`/implement` reference patterns), M9 (latest bundled-doc shape).

**Cross-cutting closures landing here:**

- **P-M10-3** — `/setup` CLAUDE.md verbosity audit (deferred from P-M3-3). M10a documents the **split methodology** ("when to keep inline vs spin into `.geniro/docs/<topic>.md`"); the concrete cut per project is decided by `/setup` runtime AUQ (per Q3 decision below).
- **P-M2-1 (third deferred category)** — user-preferences memory home. M10a routes them to **L4** procedural via `.geniro/instructions/user-preferences.md` (per Q8 decision below).

---

## 1. Purpose

Turn an unfamiliar repository into a Geniro-ready project in **one supervised run** by:

1. Scanning the codebase for objective facts (tech stack, commands, package manager, conventions).
2. Interviewing the user for preferences that cannot be detected (ship_mode default, reviewer set, communication style).
3. Writing two artifact families:
   - `<PROJECT_ROOT>/CLAUDE.md` — a **thin map** referencing `.geniro/instructions/*` and `.geniro/docs/*` (P-M10-3).
   - `.geniro/instructions/*.md` — L4 procedural rules including the new `user-preferences.md`.
4. Validating the generated artifacts against the repo via a verification agent.

`/setup` is a **singleton bootstrap** — one canonical state file at `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (no `<slug>/` subdir, no parallel runs). Supports two modes — `init` (first time) and `re-run` (refresh after stack changes). Uninstall is out-of-scope (per Q7 — `/cleanup` was intentionally dropped from the master-plan skill set).

**Anti-goal:** Do **not** become an encyclopedia generator. Every section of the generated CLAUDE.md must justify why it lives inline rather than in `.geniro/docs/<topic>.md`.

---

## 2. Architecture overview

### 2.1 State machine

```
init
  │
  ▼ (mode = init | re-run, detected from .geniro/state/setup/state.md presence)
detect
  │ codebase scan — tech stack, commands, conventions, lockfiles
  ▼
interview
  │ AskUserQuestion batches — preferences only (not detectable)
  ▼
generate
  │ write CLAUDE.md (thin map) + .geniro/instructions/*.md (incl. user-preferences.md) + .geniro/docs/*.md
  ▼
validate
  │ verification subagent re-reads codebase + generated CLAUDE.md, surfaces drift
  ▼
done (state file deleted at Phase Ship)
       │
       └─ failed (terminal: validation failed > 3 rounds OR user-aborted at Validate AUQ)
```

Phase enum values (frontmatter `phase:`, lowercase-hyphenated per M4-M9 convention): `init | detect | interview | generate | validate | done | failed`. Opaque to other skills — only `/setup` reads its own phase enum.

### 2.1.1 Termination case → state mapping (shared)

Mirrors M4 §2.1.1 / M9 §2.1.1 — every terminal path declares its reason.

| Termination cause | Phase enum on exit | `## Termination reason` body section |
|---|---|---|
| User aborted at Validate AUQ (rejected generated content) | `failed` | "user-aborted at Validate AUQ — generated content rejected; restart fresh via re-run mode" |
| Validation drift cleared after retry | `done` | not written (success path) |
| Validation drift unresolved after 3 retry rounds | `failed` | "validation drift unresolved after 3 rounds — escalate via AUQ; user picks: accept-with-warnings / abort" |
| Generation hit write-protection (e.g., `CLAUDE.md` protected) | `failed` | "write-protected target — bypass via `.geniro/safety.json` then re-run" |
| Bootstrap completed without drift | `done` | not written |

### 2.2 Loop invariants

Per **M4 §2.2** — `/setup` inherits all 7 invariants verbatim. The relevant subset for a bootstrap skill:

1. **One result per subagent call** — Detect verification subagent and Validate subagent each return a single structured report.
2. **Args validated before exec** — every Write to `CLAUDE.md` / `.geniro/instructions/*.md` is preceded by Read-then-diff (no blind overwrite in re-run mode).
3. **Permission before side-effect** — Write to project root files (`CLAUDE.md`, `.gitignore`) is AUQ-gated at Phase Validate.
4. **Bounded structured results** — verification subagent output truncated at ~4K (M4 §2.3 escalation gate); over-long reports trigger AUQ.
5. **Hard escalation gates** — 3-retry loop on validation drift; on round 4 → AUQ (`accept-with-warnings | abort | re-run`).
6. **Observations not assumed success** — every Bash command in Detect (lockfile scan, `git ls-files`, etc.) requires explicit observation parse, no silent skips.
7. **Errors as structured observations** — Detect failures are written to `## Errors` (M3 §6 Block 5b), not swallowed.

`## Tool log` selective logging (M3 §6): record verification subagent spawns + every Write to project root or `.geniro/`. Skip routine Read/Bash inside Detect (too noisy).

### 2.3 Budgets — quality-first framing (per M4 §2.3)

`/setup` has **zero Class-A hard kill caps**. User tokens are unlimited; aborting mid-bootstrap leaves the project in a half-configured state, which is strictly worse than a longer run.

| Layer | Lever | Why |
|---|---|---|
| **Class-B escalation gates** | 3-retry validation loop → AUQ | Validation drift after 3 rounds means the generator-validator disagreement is structural; surface to user, never silent abort |
| | Verification report truncation at ~4K chars | Long reports inflate context without commensurate signal; M4 §2.3 borrowed verbatim |
| **Architecture constraints** | Singleton state file (no `<slug>/`) | `/setup` is a bootstrap, not a per-task skill — parallel `/setup` runs would race against each other and corrupt `CLAUDE.md` |
| **NOT capped** | Detect duration, Interview question count, total `Read`/`Bash`/`Glob` calls, total subagent spawns | Quality-first — a thorough scan is always preferable to an aborted one |

### 2.4 ACI surface per phase (per M4 §13.5)

| Phase | Allowed tools | Forbidden tools | Rationale |
|---|---|---|---|
| `detect` | `Read`, `Bash` (read-only: `git`, `find`, `grep`, `cat`), `Glob`, `Grep`, `Agent(subagent_type=…)` | `Write`, `Edit`, `Bash` (any state-mutating), `mcp__github__*` | Detect is observation-only; mutation is deferred to Generate |
| `interview` | `AskUserQuestion`, `Read` | `Write`, `Edit`, `Bash` (mutating) | Interview is dialogue-only; preferences captured in working memory, not yet persisted |
| `generate` | `Read`, `Write`, `Edit`, `Bash` (mkdir, chmod) | `mcp__github__*`, network egress (`curl`, `gh`, `git push`) | Generation writes only to local project files; no external sends |
| `validate` | `Read`, `Bash` (read-only), `Agent` (verification subagent) | `Write`, `Edit` | Validate is read-only audit; fixes routed back through Generate via 3-retry loop |
| `done` (cleanup) | `Bash` (rm of state file) | everything else | Phase-Ship terminal cleanup only |

External sends (GitHub PR creation, Slack pings) are not part of `/setup` ACI. Users wire those via `/actions` if needed (see M10c).

---

## 3. Scope deltas vs. pre-M10 `/geniro:setup`

### 3.1 Removed

| Removed item | Why |
|---|---|
| `.geniro/.geniro-state.json` legacy state file | Replaced by `.geniro/state/setup/state.md` (M1 T1 schema, opaque phase enum, body sections per M3 §6) |
| `/setup` vendored-mode routing (`Phase 1.4 Feature Sync`) | `/vendor` was dropped from the 11-skill set — no upstream caller |
| References to `/cleanup`, `/vendor`, `/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings` in generated CLAUDE.md skill table | Those skills are gone in the 11-skill model — the generated table must reflect reality |
| Self-contained CLAUDE.md "encyclopedia" sections (hooks-allowlist details, MCP table inline, Custom Agent Invocation ladder inline) | Replaced by **split methodology** (per Q3): generator AUQs whether to inline vs spin out to `.geniro/docs/<topic>.md` |
| Inline phase numbering as part of CLAUDE.md output | Phase numbers are skill-internal contracts (M3 obligation) — never leak to generated user-facing files |

### 3.2 Kept (with adaptation)

| Kept item | Adaptation |
|---|---|
| Codebase tech-stack detection (`package.json`, `pyproject.toml`, lockfiles, etc.) | Moved into Phase Detect; results structured as Evidence Block per M4 §6 |
| Interview-driven preference capture | Moved into Phase Interview; **persistence target changed**: preferences now write to `.geniro/instructions/user-preferences.md` (L4), not into CLAUDE.md body |
| Verification subagent (validates generated CLAUDE.md against codebase) | Moved into Phase Validate; `model: sonnet` per M4 §13.4 model-tiering; constrained tool surface (`tools: [Read, Bash, Glob, Grep]` — no Write) |
| Conflict-resolution agent (merge existing CLAUDE.md with generated content on re-run) | Kept for `re-run` mode only; spawned during Phase Generate as a sub-step when target `CLAUDE.md` already exists |
| Existing path-constraint rule ("never use `~`") | Preserved verbatim — already enforced by hooks |
| Restart-session warning at end | Moved to Phase Done final-report (not relevant for fresh init; only emitted in re-run mode after plugin-version mismatch) |

### 3.3 Replaced

| Old | New |
|---|---|
| "Write user preferences inline into CLAUDE.md body" | "Write user preferences to `.geniro/instructions/user-preferences.md` (L4 procedural)"; CLAUDE.md only references the file |
| Self-contained `CLAUDE.md` (~300 LOC encyclopedia) | **Split methodology**: every section >40 LOC is AUQ-gated — `inline | spin out to .geniro/docs/<topic>.md | drop` |
| `.geniro/.geniro-state.json` JSON marker | M1 T1 state file `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (Markdown + frontmatter, M3 §6 body sections) |

---

## 4. Decisions recorded so far

| ID | Question | Decision |
|---|---|---|
| **Q1** | Bundle vs split for M10 | **Split** — `M10a-setup`, `M10b-instructions`, `M10c-actions`, `M10d-update` as 4 separate docs |
| **Q2** | Phase model | **Skill-natural** — `/setup` gets 4 phases (Detect → Interview → Generate → Validate) |
| **Q3** | CLAUDE.md verbosity audit | **Document split methodology**; concrete cut decided per project via `/setup` runtime AUQ at Phase Generate |
| **Q4** | Connector safety enforcement | Minimal 3-property (`name`, `description`, `risk_class`) — full details land in M10c `/actions` |
| **Q5** | State files | **`/setup` only** — singleton state file `state/setup/state.md` (no slug subdir); other M10 skills are stateless |
| **Q6** | `/update` scope | Wrapper + integrity check + MIGRATION.md reader (lands in M10d) |
| **Q7** | `/setup` modes | **Init + re-run only** — no uninstall path (`/cleanup` was dropped intentionally) |
| **Q8** | P-M2-1 user-preferences home | **L4 procedural** — `.geniro/instructions/user-preferences.md`, loaded via existing `_shared/load-custom-instructions.md` |

Sub-decisions during defect-inventory walk (§5):

| Sub-decision | Resolution |
|---|---|
| Conflict-resolution model on re-run | Spawn `architect-agent` (M4 §13.4 tiering: `sonnet`) with `tools: [Read, Edit]` constrained to `CLAUDE.md` and `.geniro/instructions/*.md` only — no write access elsewhere |
| When does `/setup` write `.gitignore`? | Phase Generate writes `.geniro/planning/`, `.geniro/state/`, `.geniro/knowledge/` rules **only if** `.gitignore` exists and doesn't already cover them; never creates `.gitignore` from scratch (project conventions vary) |
| What if user has no `git` repo? | Detect emits `## Errors` row "not a git repo — skipping git-based detection (branch, remotes)"; Interview asks for default branch manually |
| What gets re-generated in re-run mode? | Only CLAUDE.md and `.geniro/instructions/*.md` files. User-authored `.geniro/instructions/<custom>.md`, `.geniro/actions/*`, `.geniro/knowledge/learnings.jsonl` are **never** touched |

---

## 5. Defect inventory (audit 2026-05-19 — before/after)

12 defects identified in current `/setup` SKILL.md (869 LOC). All closed in this redesign.

| # | Defect | Fix |
|---|---|---|
| **D1** | References dropped skills (`/cleanup`, `/vendor`, `/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`) in installation-model and skill-table examples | Phase Generate template uses the 11-skill set only; skill table generated from `<PRIMARY_ROOT>/.geniro/state/setup/state.md` frontmatter `skill_inventory:` field populated by Detect Step 4 (read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/marketplace.json` if available, else fallback list of 11) |
| **D2** | `.geniro/.geniro-state.json` JSON-marker conflicts with M1 T1 framework | Removed — state lives at `.geniro/state/setup/state.md` (M1 T1 schema); `init` vs `re-run` detection switches to "file exists at `.geniro/state/setup/state.md` OR `CLAUDE.md` has `<!-- geniro-setup-version: -->` marker" |
| **D3** | "Vendored mode" routing (`$VENDOR_MODE`, `Vendored Mode Resync`) references a dropped skill | Phase 1.4 (`Feature Sync`) entirely removed; re-run mode goes straight from Detect → Interview (diff-mode, only asks new questions) → Generate (diff-write only changed sections) → Validate |
| **D4** | User-preferences inlined into CLAUDE.md make it self-modify on every preference change — violates M3 "CLAUDE.md is a stable map" goal | Preferences → `.geniro/instructions/user-preferences.md` (L4); CLAUDE.md `## User Preferences` section becomes a 1-line reference: "See `.geniro/instructions/user-preferences.md`. Loaded automatically by every Geniro pipeline skill." |
| **D5** | Self-contained CLAUDE.md (~300 LOC) crosses encyclopedia threshold (P-M10-3) | Phase Generate Step 3.2 runs **section-by-section AUQ** (per Q3): for each section >40 LOC, options are `inline | spin to .geniro/docs/<topic>.md | drop`. Default suggestion follows the heuristic in §6.4 (Phase Generate §6.4 "Split heuristic") |
| **D6** | No `## Tool log`, no `## Errors`, no `## Termination reason` — current skill cannot survive compaction | State file body sections added per M3 §6: `## Tool log` (subagent spawns, project-root writes), `## Errors` (Block 5b), `## Open Questions` (Block 5c), `## Persisted approvals` (Block 5d — `disambiguate_arguments`, `ship_mode_default`, `claude_md_section_<name>`), `## Termination reason` (only on `failed`) |
| **D7** | No P-M1-1 approvals[] frontmatter persistence — same questions re-asked across compactions | Phase Interview emits `approvals[]` entries on every AUQ; Phase Generate pre-checks `approvals[]` before re-asking. Categories registered: `ship_mode_default`, `default_branch`, `default_reviewer_set`, `communication_style`, `claude_md_section_<section-id>` |
| **D8** | Verification subagent has uncapped tool surface — could mutate generated CLAUDE.md during validation | Phase Validate spawn passes `tools: [Read, Bash, Glob, Grep]` constraint via `_shared/spawn-agent.md` template; no Write/Edit |
| **D9** | No L2 emit on completion — pattern-of-bootstrap reuse impossible | Phase Validate final step emits a single L2 `discovery` entry: `{type: 'discovery', trust: 'verified', detected_stack, ship_mode_default, ...}` per M2 §5.3 trigger table. Auto-replaces the dropped `/learnings` skill pattern |
| **D10** | No anti-pattern check section — fails P-MP-1 lint criterion | §14 added (12-item anti-pattern table); CI guard documented in §15 (lint script template) |
| **D11** | No master plan reconciliation section | §13 added (closes P-M2-1 user-preferences, P-M3-3-deferred → P-M10-3 split-methodology, master plan §122 row) |
| **D12** | Restart-session warning emitted on every `/setup` run, including fresh init (where there's no old session to restart) | Phase Done Step 4 (`emit_restart_warning`) conditional: only if `mode == 're-run' AND detected plugin-version delta` |

---

## 6. Phase Detect — **DECIDED**

### 6.1 Step 0 — Mode detect and state-file rehydration

Mode resolution (deterministic, no AUQ):

```
if exists(.geniro/state/setup/state.md):
  rehydrate state via `_shared/state-helpers.md::validate_state_file` (M1 §Validation helper, includes P-M1-2 worktree cross-check)
  if frontmatter.phase != "done":
    resume from frontmatter.phase
  else:
    mode = re-run (a prior /setup completed cleanly; user is re-invoking)
elif exists(CLAUDE.md) AND grep "<!-- geniro-setup-version:" CLAUDE.md:
  mode = re-run (no state file, but generated marker present)
else:
  mode = init
```

Mode is written to frontmatter `mode: init | re-run` and persists across the run. **No AUQ here** — the file system is the source of truth.

### 6.2 Step 1 — Load custom instructions + L2 prior-knowledge

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with:

- `SKILL_SLUG: setup`
- `LOAD_TIER: rules-only` (no per-skill `setup.md` — `/setup` is lifecycle, not pipeline; per `/instructions` skill `Supported Skills` table in M10b)
- `MODE: initial-load`

The helper's Echo contract requires one observable line. Mandatory.

Then query L2 (`.geniro/knowledge/learnings.jsonl`) per M2 §5.3 for prior `discovery` entries tagged `setup`:

```bash
grep '"type":"discovery"' .geniro/knowledge/learnings.jsonl 2>/dev/null \
  | grep '"tags":\[.*"setup"' \
  | tail -10
```

Surface in `## Phase log` as "Prior /setup runs: N (last: <timestamp>, stack: <stack>)". If `N >= 1`, this is at least the 2nd `/setup` in this project — useful context for the Interview phase.

### 6.3 Step 2 — Locate plugin source

```bash
TEMPLATE_DIR="${CLAUDE_PLUGIN_ROOT}"
if [ -z "$TEMPLATE_DIR" ] || [ ! -d "$TEMPLATE_DIR/agents" ]; then
  if [ -n "$ARGUMENTS" ] && [ -d "$ARGUMENTS/agents" ]; then
    TEMPLATE_DIR="$ARGUMENTS"
  else
    echo "ERROR: cannot locate plugin source. \${CLAUDE_PLUGIN_ROOT} unset and no \$ARGUMENTS fallback." >&2
    exit 1  # → Phase Failed, ## Errors row
  fi
fi
```

Resolved `$TEMPLATE_DIR` written to state frontmatter `template_dir:`.

### 6.4 Step 3 — Codebase scan (Evidence Block per M4 §6)

Detect via lockfile / config presence, NOT inference:

| Stack signal | Evidence file(s) | Captured into state |
|---|---|---|
| Node/npm | `package.json` + `package-lock.json` | `pkg_mgr: npm`, `lang: node`, `scripts: {...}` |
| Node/yarn | `package.json` + `yarn.lock` | `pkg_mgr: yarn` |
| Node/pnpm | `package.json` + `pnpm-lock.yaml` | `pkg_mgr: pnpm` |
| Node/bun | `package.json` + `bun.lockb` | `pkg_mgr: bun` |
| Python/uv | `pyproject.toml` + `uv.lock` | `pkg_mgr: uv`, `lang: python` |
| Python/poetry | `pyproject.toml` + `poetry.lock` | `pkg_mgr: poetry` |
| Python/pip | `requirements.txt` | `pkg_mgr: pip` |
| Rust | `Cargo.toml` + `Cargo.lock` | `lang: rust` |
| Go | `go.mod` + `go.sum` | `lang: go` |
| Ruby | `Gemfile` + `Gemfile.lock` | `lang: ruby` |
| ... | (full table in current `/setup` SKILL.md §1.1, preserved verbatim) | |

Each detection records evidence as `{ file: <path>, line: <N>, snippet: "<exact text>" }` per M4 §6 Evidence Block standard. No inference without evidence — if `package.json` exists but no lockfile, `pkg_mgr: unknown` (Interview asks).

Conventions detected (read-only — never inferred from heuristic, only from explicit config):

- ESLint config → naming/formatting hints (not enforced, only surfaced)
- Prettier config → style hints
- `.editorconfig` → indentation rules
- `tsconfig.json` / `jsconfig.json` → module resolution
- Test runner: `jest.config.*`, `vitest.config.*`, `pytest.ini`, etc.

### 6.5 Step 4 — Skill inventory

Read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/marketplace.json` (or `plugin.json`). Extract the canonical 11-skill list. Write to state frontmatter:

```yaml
skill_inventory:
  - {slug: implement, purpose: "..."}
  - {slug: plan, purpose: "..."}
  - {slug: review, purpose: "..."}
  ... (8 more)
```

If marketplace.json read fails, fallback to a hard-coded list embedded in `/setup` SKILL.md (kept in sync via `/instructions edit setup` if/when the skill set changes — out of scope for this milestone but noted in §11 Open Questions).

### 6.6 Detect output — frontmatter `detected:` block

All §6.3-6.5 outputs land in state frontmatter `detected:` block. Phase log captures one summary line:

```
[<timestamp>] detect complete — stack=node/npm, lang=node, pkg_mgr=npm, has_tests=true (jest), skill_inventory=11, evidence_count=14
```

Transition to Phase Interview.

---

## 7. Phase Interview — **DECIDED**

### 7.1 Approvals precheck (P-M1-1)

Before opening any AUQ, read state frontmatter `approvals[]`. For each AUQ slot below, check `category == <slot-name>`:

- If present and `picked != null` → reuse the prior answer; emit `## Phase log` line: "Reused prior answer for `<slot>`: `<picked>` (asked_in_phase: `<phase>`)". **No re-ask.**
- If absent → ask via `AskUserQuestion`; on answer, append to `approvals[]`.

Categories registered for `/setup` (P-M1-1 expansion, persisted across compactions per M3 §6 Block 5d):

| Category | Asked at | Trigger to re-ask |
|---|---|---|
| `ship_mode_default` | Interview Step 2 | User invokes `/setup` in re-run mode AND `--reset-prefs` flag passed |
| `default_branch` | Interview Step 1 | Not git repo at first run, then `git init` happens, then re-run |
| `default_reviewer_set` | Interview Step 3 | `--reset-prefs` flag |
| `communication_style` | Interview Step 4 | `--reset-prefs` flag |
| `claude_md_section_<id>` | Generate Step 3.2 (per long section) | Section >40 LOC AND not previously decided |

### 7.2 Question batches

`/setup` interviews in **2 batches** maximum (AUQ accepts up to 4 questions per call — keeps friction low):

**Batch 1 — preferences (always asked unless `approvals[]` cache hit):**

| Slot | Question (paraphrase) | Options |
|---|---|---|
| `default_branch` | Default branch for PRs? | `main`, `master`, `develop`, `other (free-text)` |
| `ship_mode_default` | Default ship mode in `/implement`? | `commit-only`, `push (no PR)`, `open PR (draft)`, `open PR (ready)` |
| `default_reviewer_set` | Which built-in reviewers default-on? | `bugs+security+architecture+tests+optimizations+guidelines+conventions` (full set) / `bugs+security+tests` (minimal) / `custom` |
| `communication_style` | Reply style for Geniro skills? | `concise (default)`, `verbose (more rationale)`, `minimal (results-only)` |

**Batch 2 — codebase confirmations (only asked if Detect was ambiguous):**

E.g., "Detect saw `pyproject.toml` AND `requirements.txt` — primary package manager?" / "Detected branch `main` AND `master` — primary?" Only emitted when Detect output flagged ambiguity.

If Batch 2 has zero questions, skip it entirely. No "asking for the sake of asking."

### 7.3 Preference write-target

All preferences captured in Batch 1 land in **`.geniro/instructions/user-preferences.md`** (per Q8 — L4 procedural). Format:

```markdown
# User Preferences

## Rules

- **Default branch:** `main`
- **Default ship mode:** `open PR (draft)` — `/implement` Phase Ship pre-selects this option in the ship-mode AUQ.
- **Default reviewer set:** `bugs+security+architecture+tests+optimizations+guidelines+conventions` (full built-in set).
- **Communication style:** `concise`.

## Loaded by

Every Geniro pipeline skill at Step 0 (initial-load) and at each phase-boundary refresh via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`. Edit via `/geniro:instructions edit user-preferences`.
```

CLAUDE.md `## User Preferences` section becomes a 1-line reference:

```markdown
## User Preferences

See `.geniro/instructions/user-preferences.md`. Loaded automatically by every Geniro pipeline skill.
```

Transition to Phase Generate.

---

## 8. Phase Generate — **DECIDED**

### 8.1 Pre-write existing-content audit (re-run only)

If `mode == re-run`:

1. Read existing `CLAUDE.md`. Compute diff against the to-be-generated body (Step 8.2 output).
2. For each section in existing CLAUDE.md with `<!-- geniro-setup-managed -->` HTML comment marker, mark for replacement.
3. Sections without the marker = user-edited → spawn **conflict-resolution agent** (`architect-agent`, `model: sonnet`, `tools: [Read, Edit]` constrained to `CLAUDE.md` only) with the prompt template in §8.5.
4. Agent returns a merged body. Display diff to user (`## Phase log` entry + AUQ if diff is non-trivial).

If `mode == init`: skip Step 8.1; proceed to 8.2 directly.

### 8.2 CLAUDE.md generation — split methodology (P-M10-3 closure)

Generated CLAUDE.md body is assembled from candidate sections. Each candidate is classified by **LOC count** and **content type**:

| Section | Default LOC | Default classification |
|---|---|---|
| Header (project name + 1-line purpose) | ~5 | **inline** (always) |
| Getting Started (3-5 lines) | ~5 | **inline** (always) |
| Skill table (slug → 1-line purpose) | ~15 | **inline** (always) |
| Path rules (~6 lines on `~` expansion) | ~10 | **inline** (always) |
| User Preferences section (1-line reference) | ~3 | **inline** (always) |
| Safety hooks summary (1 line: "Hooks active — see `.geniro/docs/hooks.md`") | ~2 | **inline** (always) |
| Safety hooks full allowlist details | ~80 | **spin out** to `.geniro/docs/hooks.md` (default) |
| Optional MCP Dependencies table | ~30 | **AUQ-gated** — defaults to `spin out` to `.geniro/docs/mcp.md` |
| Custom Agent Invocation ladder | ~25 | **AUQ-gated** — defaults to `spin out` to `.geniro/docs/agent-runtime.md` |
| Updating instructions (1 line ref to `/update`) | ~5 | **inline** (always) |
| Tech stack summary (detected from Phase Detect) | ~10-30 | **inline** (always — this is project-specific) |
| Commands (npm scripts / make targets / pyproject scripts) | ~10-30 | **inline** (always — project-specific) |
| Project conventions (from `code-style.md` if exists) | varies | **inline** (always — project-specific) |

**Split heuristic** (default suggestion when AUQ fires):

```
if section.is_plugin_global (i.e., same across all Geniro projects):
  if LOC > 40: default = spin out
  else:        default = inline
else:  # project-specific
  default = inline  (project-specific content always inline)
```

### 8.3 Section-by-section AUQ (per Q3)

For each candidate section flagged "AUQ-gated" or "spin out (default)", emit one `AskUserQuestion`:

- **Approvals precheck (P-M1-1):** category = `claude_md_section_<section-id>`. If `picked != null` → reuse, no AUQ.
- **AUQ options (4 max):** `inline (keep verbose section in CLAUDE.md)` / `spin out (move to .geniro/docs/<topic>.md, CLAUDE.md gets 1-line ref)` / `drop entirely (project doesn't use this feature)`. Recommended option (per heuristic 8.2) is first.

To stay under the 4-AUQ-per-call budget of `AskUserQuestion`: batch the section AUQs in groups of 4. For a typical run with `hooks-details` + `mcp` + `agent-runtime` + `safety-allowlist-fields`, this is one AUQ call.

### 8.4 Write targets

After AUQ resolution:

- `<PROJECT_ROOT>/CLAUDE.md` — inline sections only; section markers (`<!-- geniro-setup-managed -->` / `<!-- geniro-setup-end -->`) wrap each generated section for re-run safety.
- `<PROJECT_ROOT>/.geniro/docs/hooks.md` (if spun out) — copy from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/docs-templates/hooks.md` (new helper, scaffolded by /setup if missing).
- `<PROJECT_ROOT>/.geniro/docs/mcp.md` (if spun out) — same pattern.
- `<PROJECT_ROOT>/.geniro/docs/agent-runtime.md` (if spun out) — same pattern.
- `<PROJECT_ROOT>/.geniro/instructions/user-preferences.md` — per §7.3.
- `<PROJECT_ROOT>/.geniro/instructions/global.md` — only created if user opted in to Batch 2 question "create empty global.md for project-wide workflow rules?"; default = no (avoid clutter).
- `<PROJECT_ROOT>/.geniro/state/setup/state.md` — final frontmatter update (`phase: generate → validate`).

All Writes are AUQ-gated at the **batch level** (one AUQ "Generate all of: CLAUDE.md (X lines), .geniro/instructions/user-preferences.md (Y lines), …? Options: yes / show preview first / edit which files"). Per ACI (§2.4), Phase Generate has write surface to project root and `.geniro/` only — no external sends, no network.

### 8.5 Conflict-resolution agent prompt template

For each user-edited section in re-run mode:

```
You are merging two versions of a CLAUDE.md section. The plugin generated NEW_CONTENT
based on a fresh codebase scan; the user has EDITED_CONTENT in their existing CLAUDE.md.

NEW_CONTENT (auto-generated):
<...>

EDITED_CONTENT (user-modified):
<...>

Rules:
1. Preserve all user customizations from EDITED_CONTENT.
2. Apply any factual updates from NEW_CONTENT (e.g., new commands detected, new tech-stack entries).
3. If there is a conflict (same statement contradicted), emit a `<!-- CONFLICT: ... -->` HTML comment with both versions; do not pick a side.
4. Output ONLY the merged section body. No prose, no explanation outside the merged content itself.

Tools: Read, Edit (constrained to CLAUDE.md only).
Model: sonnet.
```

Output is appended to `## Tool log` as a single `merge_section spawn` entry (M3 §6 selective logging).

Transition to Phase Validate.

---

## 9. Phase Validate — **DECIDED**

### 9.1 Verification subagent spawn

Spawn pattern (per `_shared/spawn-agent.md` runtime-degradation ladder):

```
Agent(
  subagent_type="<resolved-rung>",  # tries geniro-claude-plugin:reviewer-agent → reviewer-agent → general-purpose
  model="sonnet",                    # M4 §13.4 — verification is bounded reasoning
  tools=["Read", "Bash", "Glob", "Grep"],  # NO Write/Edit per §2.4
  prompt="""
    Validate the generated <PROJECT_ROOT>/CLAUDE.md against the codebase.

    Checklist:
    1. Every command in the `## Commands` section runs locally (try `bash -n` syntax check; do not execute).
    2. Every claimed file path in `## Tech Stack` exists.
    3. Skill table lists exactly 11 skills; no references to dropped skills.
    4. Path rules section warns against `~` literal.
    5. User Preferences section is a 1-line reference, NOT inlined preferences.
    6. Hooks summary line points to `.geniro/docs/hooks.md` if that file exists, else inlines (consistency check).

    Output a markdown report:
    ## PASS items (one per line)
    ## DRIFT items (one per line with file:line)

    Tools allowed: Read, Bash (read-only), Glob, Grep. Do NOT mutate any file.
    Truncate at 4000 chars (drop trailing PASS items first; keep all DRIFT).
  """
)
```

### 9.2 3-retry escalation loop

| Round | Action |
|---|---|
| 1 | Spawn subagent. If `DRIFT items` empty → transition to Phase Done. Else → regenerate the affected sections (jump back to Phase Generate for those sections only). |
| 2 | Re-spawn subagent. Same logic. |
| 3 | Re-spawn subagent. Same logic. |
| 4 | **AUQ escalation** (P-M4-3 Class-B gate): `accept-with-warnings (proceed to done, drift documented in ## Open Questions) | abort (transition to failed) | re-run from Detect`. |

`## Open Questions` (M3 §6 Block 5c) accumulates the DRIFT items across rounds — survives compaction.

### 9.3 L2 emit on successful Validate

Per M2 §5.3 trigger table — emit one L2 `discovery` row on transition to DONE (auto-replaces dropped `/learnings` skill pattern):

```jsonl
{"id":"<uuid>","ts":"2026-05-19T14:32:00Z","type":"discovery","trust":"verified","skill":"setup","mode":"init","tags":["setup","stack","bootstrap"],"summary":"bootstrap complete: node/npm/jest, ship_mode=open-PR-draft, full reviewer set","entry":{"stack":"node/npm","test_runner":"jest","ship_mode_default":"open-pr-draft","reviewer_set":"full","claude_md_loc":67,"spun_out_docs":["hooks.md","mcp.md"]}}
```

`trust: verified` per M2 §5.1 base schema (code-grounded — Detect read real files; no WebFetch).

---

## 10. Phase Done — **DECIDED**

### 10.1 Final report to user

```
✓ /geniro:setup complete (init)

Wrote:
  CLAUDE.md (67 lines — thin map)
  .geniro/instructions/user-preferences.md (12 lines)
  .geniro/docs/hooks.md (84 lines — spun out per AUQ)
  .geniro/docs/mcp.md (28 lines — spun out per AUQ)
  .geniro/.gitignore (no change — existing ignores cover .geniro/planning/, .geniro/state/, .geniro/knowledge/)

Detected:
  Stack: node/npm + jest tests + ESLint
  Default branch: main
  Ship mode default: open PR (draft)
  Reviewer set: full (7 built-in dimensions)

Next:
  • Commit: git add CLAUDE.md .geniro/instructions/user-preferences.md .geniro/docs/
  • Run a real task: /geniro:plan "your-task-here"
  • Or browse skills: /geniro:investigate "what does /geniro:debug do?"
```

(re-run mode adds a section "Changed since last setup: …" with the section-level diff summary.)

### 10.2 State file cleanup

Delete `<PRIMARY_ROOT>/.geniro/state/setup/state.md`. This is the **only** Geniro state file that gets deleted on success — `/setup` is a singleton bootstrap and the state file has zero value once DONE.

Exception: if `mode == re-run` AND user opted for `accept-with-warnings` at §9.2 round 4, the state file is **kept** with `phase: DONE` and `## Open Questions` populated — surfaces for the next `/setup` re-run.

### 10.3 Restart-session warning (re-run only, plugin-version delta)

```
⚠ Restart your Claude Code session before using any other Geniro skill.

Claude Code resolves ${CLAUDE_PLUGIN_ROOT} once at session start. The plugin
update brought a new install path, but in-memory skill bodies still reference
the old one. Restart and you're done.
```

Only emitted when:
- `mode == re-run` AND
- `/setup` detected `plugin.json` version delta vs the version recorded in the prior state file or CLAUDE.md `<!-- geniro-setup-version: -->` marker.

Fresh `init` runs never emit this warning (no old session to restart).

---

## 11. State file schema

Path: `<PRIMARY_ROOT>/.geniro/state/setup/state.md`. T1 tier (session-bound, ephemeral, deleted at Phase Done). M1 §T1 schema.

### 11.1 Frontmatter (consolidated per M1 §Frontmatter contract)

```yaml
---
skill: setup
slug: setup                      # singleton — no parallel runs, no slug-collision concern
version: 1                       # frontmatter schema version
phase: detect                    # one of init|detect|interview|generate|validate|done|failed (lowercase per M4-M9 convention)
mode: init                       # init | re-run
worktree: /absolute/path         # P-M1-2 cross-check on rehydration
created: 2026-05-19T14:00:00Z
updated: 2026-05-19T14:32:00Z
template_dir: /Users/you/.claude/plugins/geniro-claude-plugin@geniro-claude-harness/abc123
approvals:                       # P-M1-1 (Block 5d render target)
  - {category: ship_mode_default, prompt: "Default ship mode?", options: [...], picked: "open-pr-draft", at: "2026-05-19T14:05:00Z", asked_in_phase: interview}
  - {category: claude_md_section_hooks_details, prompt: "Include hooks details inline?", options: ["inline","spin out","drop"], picked: "spin out", at: "...", asked_in_phase: generate}
detected:
  stack: node/npm
  lang: node
  pkg_mgr: npm
  test_runner: jest
  has_eslint: true
  default_branch_candidates: [main]
  evidence:
    - {file: package.json, line: 5, snippet: "\"name\": \"my-project\""}
    - {file: package-lock.json, line: 1, snippet: "{"}
    - ...
skill_inventory:
  - {slug: implement, purpose: "..."}
  - ... (11 total)
preferences:                     # captured in interview, written to .geniro/instructions/user-preferences.md in generate
  default_branch: main
  ship_mode_default: open-pr-draft
  default_reviewer_set: full
  communication_style: concise
write_targets:                   # populated in generate
  - {path: CLAUDE.md, op: write, loc: 67}
  - {path: .geniro/instructions/user-preferences.md, op: write, loc: 12}
  - {path: .geniro/docs/hooks.md, op: write, loc: 84}
validate_rounds: 1                # set in validate
---
```

### 11.2 Body sections (per M3 §6)

```markdown
## Phase log
[2026-05-19T14:00:00Z] init → detect  (mode=init)
[2026-05-19T14:02:00Z] detect complete — stack=node/npm, evidence_count=14
[2026-05-19T14:05:00Z] interview Batch 1 → 4 preferences captured
[2026-05-19T14:10:00Z] generate Step 3.2 → 3 sections spun out (hooks, mcp, agent-runtime)
[2026-05-19T14:30:00Z] validate round 1 → 0 DRIFT
[2026-05-19T14:32:00Z] → done

## Tool log                        # M3 §6 selective logging
[14:02:00] Detect: read package.json (evidence #1), package-lock.json (#2), ...
[14:30:00] validate: spawn verification-agent → 0 drift items

## Errors                          # M3 §6 Block 5b (rare — only on failure paths)
(empty)

## Open Questions                  # M3 §6 Block 5c (populated on accept-with-warnings)
(empty)

## Persisted approvals             # M3 §6 Block 5d (renders frontmatter approvals[])
- ship_mode_default = "open-pr-draft" (asked at interview, 2026-05-19T14:05:00Z)
- claude_md_section_hooks_details = "spin out" (asked at generate, 2026-05-19T14:10:00Z)
- claude_md_section_mcp = "spin out" (asked at generate, 2026-05-19T14:10:00Z)
- claude_md_section_agent_runtime = "spin out" (asked at generate, 2026-05-19T14:10:00Z)

## Termination reason              # only set on `failed` — empty here (`done` path)
```

---

## 12. Memory I/O (M2 §13 obligation)

| Layer | Read at | Write at | Notes |
|---|---|---|---|
| **L1 (CLAUDE.md)** | Phase Detect §6.2 (Step 0 instructions load) | Phase Generate §8.4 (writes thin-map CLAUDE.md) | Generated CLAUDE.md is the L1 target; preserves user customizations via §8.5 conflict resolver in re-run mode |
| **L2 (`learnings.jsonl`)** | Phase Detect §6.2 (prior `discovery` query, tag `setup`) | Phase Validate §9.3 (one `discovery` row on `done`) | `trust: verified` — code-grounded; auto-replaces dropped `/learnings` skill |
| **L3 (`.geniro/planning/_project.md` etc.)** | not read (L3 is M2 Semantic — `/onboard` writes it) | not written | `/setup` and `/onboard` are different skills with non-overlapping write surfaces; `/setup` writes CLAUDE.md and `.geniro/instructions/*`, `/onboard` writes `.geniro/planning/_CODEBASE_MAP.md` and `.geniro/planning/_project.md` |
| **L4 (`.geniro/instructions/*.md`)** | Phase Detect §6.2 (rules-only load via `_shared/load-custom-instructions.md`) | Phase Generate §8.4 — writes `.geniro/instructions/user-preferences.md` (always); optionally creates empty `.geniro/instructions/global.md` if user opts in | Schema: standard custom-instruction format (`## Rules`, `## Additional Steps`, `## Constraints`) |

L5 (Episodic — current-session working memory, M2 §5.5) is implicit; not persisted by `/setup`.

---

## 13. Master plan reconciliation

| Master plan ref | Closure |
|---|---|
| §107 row M10 (`/setup` + `/instructions` + `/actions` + `/update`) | M10a closes the `/setup` quarter; M10b/M10c/M10d cover the rest |
| §122 row M10 ("User-extensibility + operational; lowest priority") | M10a respects "lowest priority" — minimal phase count (4), no expansion beyond scope |
| **P-M2-1** "user-preferences (likely M10 /setup)" | Closed — user-preferences → L4 `.geniro/instructions/user-preferences.md` (§7.3, §12 L4 row) |
| **P-M3-3 deferred → P-M10-3** "audit CLAUDE.md verbosity in /setup output" | Closed via Q3 — split methodology documented (§8.2, §8.3); concrete cut runtime-AUQ-driven |
| **P-MP-1** "Anti-patterns guardrail (every milestone design must include an Anti-pattern check)" | §14 below |

---

## 14. Anti-pattern check (P-MP-1 obligation)

12 items from the master plan guardrail (§Anti-patterns guardrail). M10a status:

| # | Anti-pattern | M10a status |
|---|---|---|
| 1 | One giant prompt | ✅ N/A — `/setup` SKILL.md modular; phase sections will be in `_shared/setup/*.md` helpers if SKILL.md grows beyond ~400 LOC |
| 2 | One giant tool | ✅ N/A — Edit/Write/Bash/Glob/Grep native, no plugin meta-tool |
| 3 | Unbounded autonomous loop | ✅ §9.2 3-retry validation loop with AUQ escalation; no infinite retry |
| 4 | Autonomous external sends in first release | ✅ Phase Generate ACI forbids `mcp__github__*` and network egress; no Slack/PR auto-send |
| 5 | No approval state | ✅ P-M1-1 `approvals[]` populated (§7.1) and rendered as Block 5d (§11.2) |
| 6 | No durable plans or goals | ✅ State file mandatory (§11) — singleton at `state/setup/state.md` |
| 7 | No compaction strategy | ✅ `## Tool log` + `## Errors` + `## Open Questions` + `## Persisted approvals` populated (§11.2) — survives compaction via M3 §6 SessionStart re-injection |
| 8 | All connectors loaded up front | ✅ N/A — Claude Code's MCP plugin model gates this; `/setup` doesn't load connectors |
| 9 | High-risk tools without policy | ✅ §2.4 per-phase ACI table; verification subagent constrained to `tools: [Read, Bash, Glob, Grep]`; conflict-resolver constrained to `tools: [Read, Edit]` on CLAUDE.md only |
| 10 | Subagents before single-agent MVP measured | ✅ `/setup` uses 1 verification subagent + (re-run only) 1 conflict-resolution subagent; both bounded and necessary |
| 11 | Dynamic timestamps in plugin-distributed Markdown bodies | ⚠ Verify in implementation: `/setup` SKILL.md must NOT embed runtime timestamps in its own body; state file timestamps are fine (state files are generated, not plugin-distributed) |
| 12 | Non-deterministic agent registration order | ✅ N/A — `/setup` consumes registration, doesn't define it |

Implementation-time CI lint (out-of-scope for this design doc, but documented as TODO): grep `${CLAUDE_PLUGIN_ROOT}/skills/setup/**/*.md` for ISO-8601 timestamp patterns and fail if found.

---

## 15. Open questions

| # | OQ | Why deferred |
|---|---|---|
| **OQ-M10a-1** | Skill inventory fallback list maintenance — when the 11-skill set changes, where does the canonical list live? | Resolution: marketplace.json is canonical; `/setup` reads it. If marketplace.json drifts from reality, `/instructions edit setup` would fix it — but this is meta-bootstrap. Deferred to M10b (`/instructions` skill) for a "validate plugin manifest" mode |
| **OQ-M10a-2** | Should `/setup` re-run mode detect plugin-side breaking changes (e.g., a previously-spun-out `.geniro/docs/<topic>.md` template changed in the new plugin version) and offer to re-generate the spun-out doc? | Yes-in-principle, but the diff-and-merge UX is complex. Deferred to M10d (`/update` skill, since `/update` is the plugin-version-transition skill — see §9 in M10d) |
| **OQ-M10a-3** | What does `--reset-prefs` flag do exactly — clear `approvals[]` entirely, or only the preference-category subset? | Defer to implementation; default behavior should be "only preference categories" (`ship_mode_default`, `default_branch`, `default_reviewer_set`, `communication_style`) — leave `claude_md_section_*` alone so user doesn't re-AUQ split decisions |
| **OQ-M10a-4** | Should `.geniro/docs/<topic>.md` content be a copy of plugin templates, or a symlink? | Copy. Symlinks break on cross-platform (Windows users), confuse `git`, and complicate `/update` behavior. Copy is git-trackable and self-contained per project |

---

## 16. Cleanup checklist

| Item | When | Mechanism |
|---|---|---|
| `<PRIMARY_ROOT>/.geniro/state/setup/state.md` | Phase Done (success path) | `rm` in §10.2 |
| `<PRIMARY_ROOT>/.geniro/state/setup/state.md` | Phase Done (accept-with-warnings path) | **Kept** with `## Open Questions` populated — surfaces for next re-run |
| `<PRIMARY_ROOT>/.geniro/state/setup/state.md` | Phase Failed | Kept — diagnostic value; cleaned by user via `rm .geniro/state/setup/state.md` |
| State frontmatter `detected:` block | survives indefinitely on `failed` | acceptable — re-run reads `detected:` and offers "re-use prior detection or re-scan?" AUQ |

No bulk cleanup of `.geniro/` ever — that's protected by the `.geniro/` deletion guard hook regardless.

---

## 17. Cross-references

- **M1 §T1** — state file tier definition; `/setup` writes a T1 file
- **M1 §Architecture overview** — directory tree needs `state/setup/state.md` row added (see §18 below — this is a write-back to M1)
- **M2 §5.1** — L2 base schema with `trust:` field; §9.3 emit conforms
- **M2 §5.3** — L2 emit trigger table; §9.3 `discovery` row matches the bootstrap trigger
- **M2 §12** — P-M2-1 deferred categories; user-preferences row closed here
- **M3 §6** — body sections (Tool log, Errors, Open Questions, Persisted approvals, Termination reason); §11.2 implements all 5
- **M3 §6 Block 5d** — approvals[] category list; §7.1 adds `ship_mode_default`, `default_branch`, `default_reviewer_set`, `communication_style`, `claude_md_section_<id>`
- **M4 §2.2** — 7 loop invariants; §2.2 cites them verbatim
- **M4 §2.3** — quality-first budgets; §2.3 mirrors structure
- **M4 §6** — Evidence Block standard; §6.4 conforms
- **M4 §13.4** — model tiering; verification subagent on `sonnet`, conflict-resolver on `sonnet`
- **M4 §13.5** — per-phase ACI table; §2.4 mirrors structure
- **M9 (latest doc shape)** — TOC structure, anti-rationalization placement; M10a mirrors

---

## 18. Write-back to M1 (directory tree extension)

M1 §Architecture overview directory tree currently includes `state/onboard/<slug>/` and `state/investigate/<slug>/` but not `state/setup/`. Add:

```
│   ├── setup/                       # T1 (singleton layout, M10a) — no <slug>/ subdir
│   │   └── state.md                 # deleted at Phase Done (success path)
```

And in §T1 Path-roots table Examples column:

| Layout | Used by |
|---|---|
| Session-bound: `state/<skill>/<slug>/state.md` | M7 (`/debug`), M8 (`/refactor`), M9 (`/onboard`, `/investigate`) |
| **Singleton: `state/<skill>/state.md`** (new) | **M10a (`/setup`)** |

This is a write-back obligation — applied in the M10a commit alongside this design doc.
