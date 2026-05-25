---
name: geniro:setup
description: "Use when starting on a new codebase or after a major plugin update. Detects tech stack, interviews you about preferences, generates a thin-map CLAUDE.md + .geniro/instructions/user-preferences.md, and validates the result. Re-run mode also runs a migration sweep — auto-fixes breaking changes from MIGRATION.md (renames L3 files, adds missing frontmatter, cleans orphan state). Singleton bootstrap — one canonical state file."
context: main
model: opus
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[optional: path to template directory] [--reset-prefs]"
---

# Setup: AI-Driven Plugin Setup

4-phase loop: **Detect → Interview → Generate → Validate**. Turns an unfamiliar repository into a Geniro-ready project in one supervised run. **Singleton bootstrap** — one canonical state file at `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (no `<slug>/` subdir, no parallel runs). Supports `init` (first time) and `re-run` (refresh after stack changes). Uninstall is out of scope. Architecture spec: *(internal)*.

**Anti-goal:** Do NOT become an encyclopedia generator. Every section of the generated CLAUDE.md must justify why it lives inline rather than in `.geniro/docs/<topic>.md`.

## Path Constraints

**NEVER use `~` in file paths passed to Read, Write, Edit, or Glob tools.** Use `${CLAUDE_PLUGIN_ROOT}` for plugin files or absolute paths for project files.

Resolve the user's Claude config dir once, honoring `CLAUDE_CONFIG_DIR`:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

## Subagent Model Tiering

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Every `Agent(...)` spawn passes `model=` explicitly.

| Spawn | Tier | Why |
|---|---|---|
| Verification agent (validate generated CLAUDE.md against codebase) | `sonnet` | Reads files, checks claims — reasoning but bounded |
| Conflict resolution agent (re-run mode, merge existing CLAUDE.md with generated content) | `sonnet` | Pattern-matching merge with judgment calls |

## Loop invariants

1. One result per subagent call — Verification and Conflict-resolver each return one structured report.
2. Args validated before exec — every Write to `CLAUDE.md` / `.geniro/instructions/*.md` preceded by Read-then-diff in re-run mode.
3. Permission before side-effect — Write to project root files (`CLAUDE.md`, `.gitignore`) is AUQ-gated at Phase Validate.
4. Bounded structured results — verification subagent output truncated at ~4K; over-long reports trigger AUQ.
5. Hard escalation gates — 3-retry loop on validation drift; on round 4 → AUQ `accept-with-warnings | abort | re-run`.
6. Observations not assumed success — every Bash command in Detect requires explicit observation parse, no silent skips.
7. Errors as structured observations — Detect failures written to `## Errors`, not swallowed.

`## Tool log` selective logging: record verification subagent spawns + every Write to project root or `.geniro/`. Skip routine Read/Bash inside Detect.

## Budgets — quality-first

`/setup` has **zero Class-A hard kill caps**. Aborting mid-bootstrap leaves the project in a half-configured state.

| Layer | Lever | Why |
|---|---|---|
| **Class-B escalation gates** | 3-retry validation loop → AUQ | Validation drift after 3 rounds means structural disagreement; surface to user |
| | Verification report truncation at ~4K chars | Long reports inflate context without commensurate signal |
| **Architecture constraints** | Singleton state file (no `<slug>/`) | Parallel `/setup` runs would race and corrupt `CLAUDE.md` |
| **NOT capped** | Detect duration, Interview question count, total `Read`/`Bash`/`Glob` calls, total subagent spawns | Quality-first |

## ACI surface per phase

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `detect` | `Read`, `Bash` (read-only: `git`, `find`, `grep`, `cat`), `Glob`, `Grep`, `Agent` | `Write`, `Edit`, mutating `Bash`, `mcp__github__*` |
| `interview` | `AskUserQuestion`, `Read` | `Write`, `Edit`, mutating `Bash` |
| `generate` | `Read`, `Write`, `Edit`, `Bash` (mkdir, chmod) | `mcp__github__*`, network egress (`curl`, `gh`, `git push`) |
| `validate` | `Read`, `Bash` (read-only), `Agent` (verification subagent) | `Write`, `Edit` |
| `done` (cleanup) | `Bash` (rm of state file) | everything else |

External sends are not part of `/setup` ACI. Users wire those via `/actions` if needed.

## Termination case → state mapping

| Cause | Phase enum on exit | `## Termination reason` body section |
|---|---|---|
| User aborted at Validate AUQ (rejected generated content) | `failed` | "user-aborted at Validate AUQ — generated content rejected; restart via re-run mode" |
| Validation drift cleared after retry | `done` | not written (success path) |
| Validation drift unresolved after 3 retry rounds | `failed` | "validation drift unresolved after 3 rounds — escalate via AUQ; user picks: accept-with-warnings / abort" |
| Generation hit write-protection | `failed` | "write-protected target — bypass via `.geniro/safety.json` then re-run" |
| Bootstrap completed without drift | `done` | not written |

## Phase 0: Pre-flight

**Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: setup`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Echo contract requires one observable line.

**Resolve `PRIMARY_ROOT`** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A. `/setup` writes to `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (singleton — main worktree only, even when invoked from a linked worktree).

## Phase 1: Detect

### 1.1 Mode detect and state-file rehydration

Deterministic resolution (no AUQ):

```
if exists(<PRIMARY_ROOT>/.geniro/state/setup/state.md):
rehydrate via ${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh
if frontmatter.phase != "done":
resume from frontmatter.phase
else:
mode = re-run (a prior /setup completed; user is re-invoking)
elif exists(CLAUDE.md) AND grep "<!-- geniro-setup-version:" CLAUDE.md:
mode = re-run (no state file, but generated marker present)
else:
mode = init
```

Write `mode: init | re-run` to state frontmatter; persists across the run.

### 1.2 L2 prior-knowledge query

After load-custom-instructions, query L2 (`.geniro/knowledge/learnings.jsonl`) per for prior `discovery` entries tagged `setup`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh"
query_learnings --type discovery --tag setup --limit 10
```

Surface in `## Phase log` as `Prior /setup runs: N (last: <timestamp>, stack: <stack>)`. If N ≥ 1, this is at least the 2nd `/setup` — useful context for Interview.

### 1.3 Locate plugin source

```bash
TEMPLATE_DIR="${CLAUDE_PLUGIN_ROOT}"
if [ -z "$TEMPLATE_DIR" ] || [ ! -d "$TEMPLATE_DIR/agents" ]; then
if [ -n "$ARGUMENTS" ] && [ -d "$ARGUMENTS/agents" ]; then
TEMPLATE_DIR="$ARGUMENTS"
else
echo "ERROR: cannot locate plugin source. \${CLAUDE_PLUGIN_ROOT} unset and no \$ARGUMENTS fallback." >&2
# → Phase Failed, ## Errors row
exit 1
fi
fi
```

Resolved path written to state frontmatter `template_dir:`.

### 1.4 Codebase scan (Evidence Block )

Detect via **lockfile / config presence**, NOT inference:

| Stack signal | Evidence file(s) | Captured |
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
| Java | `pom.xml`, `build.gradle*` | `lang: java` |

Each detection records `{ file: <path>, line: <N>, snippet: "<exact text>" }`. No inference without evidence — if `package.json` exists but no lockfile, `pkg_mgr: unknown` (Interview asks).

**Conventions detected** (read-only — never inferred from heuristic, only from explicit config):

- ESLint config → naming/formatting hints
- Prettier config → style hints
- `.editorconfig` → indentation rules
- `tsconfig.json` / `jsconfig.json` → module resolution
- Test runner: `jest.config.*`, `vitest.config.*`, `pytest.ini`, etc.

**Existing AI tool instructions** (read for domain rules, not just detect presence):

- `.cursorrules`, `.windsurfrules`, `.github/copilot-instructions.md`, `.continue/config.json`, `.cody/`, `AGENTS.md`, `.agents.md`

**Project documentation scan** (extract domain context):

- `README.md`, `CONTRIBUTING.md`, `CONVENTIONS.md`, `ARCHITECTURE.md`, `SECURITY.md`, `API.md`, `docs/architecture.md`, `docs/adr/`, `docs/decisions/`
- API specs: `openapi.{yaml,json}`, `swagger.{yaml,json}`, `asyncapi.{yaml,json}` (extract endpoints/auth/entities — not full content)
- Env docs: `.env.example`, `.env.sample` (variable names and comments; never values)
- GitHub knowledge: `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/`
- Monorepo structure: `turbo.json`, `nx.json`, `pnpm-workspace.yaml`, `lerna.json`

Store as `$PROJECT_KNOWLEDGE` for Phase 3.

### 1.5 Skill inventory

Read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/marketplace.json` (or `plugin.json`). Extract the canonical 11-skill list:

```yaml
skill_inventory:
- {slug: implement, purpose: "Spec-driven implementation"}
- {slug: plan, purpose: "Spec-first planning"}
- {slug: review, purpose: "Multi-dim code review"}
- {slug: debug, purpose: "Scientific-method investigation"}
- {slug: refactor, purpose: "Zero-behavior-change restructuring"}
- {slug: onboard, purpose: "Codebase mapping"}
- {slug: investigate, purpose: "Codebase Q&A"}
- {slug: instructions, purpose: "L4 rules CRUD"}
- {slug: actions, purpose: "Workflow-helper CRUD + runner"}
- {slug: setup, purpose: "Project bootstrap"}
- {slug: update, purpose: "Plugin update + integrity check"}
```

If marketplace.json read fails, fallback to the hardcoded list above. **The 8 deleted skills** (`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`) MUST NOT appear in generated CLAUDE.md — they were dropped per master plan
### 1.6 Detect output

All-results land in state frontmatter `detected:` block. Phase log captures one summary line:

```
[<timestamp>] detect complete — stack=node/npm, lang=node, pkg_mgr=npm, has_tests=true (jest), skill_inventory=11, evidence_count=14
```

Transition to Phase 2.

## Phase 2: Interview

### 2.1 Approvals precheck

Before opening any AUQ, read state frontmatter `approvals[]`. For each AUQ slot, check `category == <slot-name>`:

- If present and `picked != null` → reuse the prior answer; emit `## Phase log` line: "Reused prior answer for `<slot>`: `<picked>` (asked_in_phase: `<phase>`)". **No re-ask.**
- If absent → ask via `AskUserQuestion`; on answer, append to `approvals[]`.

Categories registered for `/setup`:

| Category | Asked at | Trigger to re-ask |
|---|---|---|
| `ship_mode_default` | 2.3 Step 2 | Re-run mode AND `--reset-prefs` flag passed |
| `default_branch` | 2.3 Step 1 | Not git repo at first run, then `git init` happens, then re-run |
| `default_reviewer_set` | 2.3 Step 3 | `--reset-prefs` flag |
| `communication_style` | 2.3 Step 4 | `--reset-prefs` flag |
| `claude_md_section_<id>` | Phase 3 Step 3 (per long section) | Section >40 LOC AND not previously decided |

`--reset-prefs` flag clears ONLY the preference-category subset (`ship_mode_default`, `default_branch`, `default_reviewer_set`, `communication_style`); leaves `claude_md_section_*` alone.

### 2.2 Confirm detection

Present what was detected:

```
I analyzed your codebase. Here's what I found:

Tech Stack: TypeScript. Next.js. Prisma. React. Tailwind CSS
Package Manager: pnpm
Test Runner: Vitest
Linter: ESLint + Prettier

Validation Commands:
build: pnpm run build
test: pnpm run test
lint: pnpm run lint
typecheck: pnpm exec tsc --noEmit

From project documentation:
Project: Multi-tenant SaaS platform
Domain entities: Tenants, Workspaces, Projects, Members
Architecture: Event-driven between services, REST API v2
(Source: README.md, docs/architecture.md, openapi.yaml, turbo.json)

Is this correct, or want to adjust?
```

If `$PROJECT_KNOWLEDGE` is empty, omit the "From project documentation" section.

AUQ options: `Looks correct` / `Adjust some things`. If adjust, ask specifically what to change.

### 2.3 Question batches (max 2 batches)

**Batch 1 — preferences** (always asked unless `approvals[]` cache hit):

| Slot | Question | Options |
|---|---|---|
| `default_branch` | Default branch for PRs? | `main`, `master`, `develop`, `Other (free-text)` |
| `ship_mode_default` | Default ship mode in `/implement`? | `commit-only`, `push (no PR)`, `open PR (draft)`, `open PR (ready)` |
| `default_reviewer_set` | Which built-in reviewers default-on? | `full set (7 dimensions)`, `bugs+security+tests`, `custom` |
| `communication_style` | Reply style for Geniro skills? | `concise (default)`, `verbose (more rationale)`, `minimal (results-only)` |

**Batch 2 — codebase confirmations** (only if Detect was ambiguous):

E.g., "Detect saw `pyproject.toml` AND `requirements.txt` — primary package manager?" Skip Batch 2 entirely if no ambiguity.

### 2.4 Optional integrations — issue tracker

Use `AskUserQuestion` header "Tracker" — recommended default reflects `$ISSUE_TRACKER` detected in:

- Per-tracker mapping (Linear, GitHub Issues, GitLab Issues, Jira, Bitbucket, Skip) preserved verbatim from current skill — see `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/` for templates.
- On selection, install `.geniro/workflow/<tracker>.md` from template (or stub for non-Linear). All workflow files MUST include AI-Disclosure Prefix section.

Store as `$ISSUE_TRACKER_CHOICE` for Phase 3.

### 2.5 Custom instructions

AUQ: "Create a custom `.geniro/instructions/global.md` for project-wide workflow rules?" Default: no (avoid clutter). Users can run `/geniro:instructions create global` later.

Transition to Phase 3.

## Phase 3: Generate

### 3.0 Migration sweep (re-run only)

If `mode == re-run`, run a migration sweep before generating content. This ensures the `.geniro/` directory structure is current before CLAUDE.md and instructions are regenerated.

1. Read `${CLAUDE_PLUGIN_ROOT}/MIGRATION.md`. Parse all `### <name>` entries under the latest `## v<X.Y.Z>` section.
2. For each entry with an `Auto-detect:` field, run the shell command. Capture output.
3. If output non-empty (user IS affected):
   - If entry has an `Auto-fix:` field (not `manual-only`): run the auto-fix commands silently. Log to `## Phase log`: `[<ts>] migration fix applied: <change-name>`.
   - If entry is `manual-only`: log to `## Phase log`: `[<ts>] migration manual-only: <change-name> — will be addressed by Phase 3 regeneration or user action`.
4. After sweep, re-run all `Auto-detect:` commands to verify. Any still-affected entries are logged to `## Open Questions`.

**No AUQ during migration sweep.** Setup re-run is already user-initiated — the user expects the plugin to bring their project up to date. Auto-fix commands are maintainer-written and tested (same commands `/update` surfaces with "Fix it for me"). Manual-only entries are either handled by Phase 3 regeneration (CLAUDE.md refresh) or surfaced in the final report.

**Init mode skips this step entirely** — fresh installs write the current schema directly.

### 3.1 Pre-write existing-content audit (re-run only)

If `mode == re-run`:

1. Read existing `CLAUDE.md`. Compute diff against the to-be-generated body.
2. For each section with `<!-- geniro-setup-managed -->` HTML comment marker, mark for replacement.
3. Sections without the marker = user-edited → **orchestrator-side merge inline** per rules (no subagent spawn — section-merge is a bounded reasoning task that fits the orchestrator's own context cleanly; aligns with Anthropic best practice «folding light reasoning into orchestrator when it doesn't flood main context»).
4. Display merged diff to user; AUQ if diff is non-trivial.

If `mode == init`: skip
### 3.2 CLAUDE.md generation — split methodology

Generated CLAUDE.md body is assembled from candidate sections, each classified by LOC count and content type:

| Section | Default LOC | Default classification |
|---|---|---|
| Header (project name + 1-line purpose) | ~5 | **inline** (always) |
| Getting Started (3-5 lines) | ~5 | **inline** (always) |
| Skill table (slug → 1-line purpose, 11 rows) | ~15 | **inline** (always) |
| Path rules (~6 lines on `~` expansion) | ~10 | **inline** (always) |
| User Preferences (1-line reference) | ~3 | **inline** (always) |
| Safety hooks summary (1 line: "Hooks active — see `.geniro/docs/hooks.md`") | ~2 | **inline** (always) |
| Safety hooks full allowlist details | ~80 | **spin out** to `.geniro/docs/hooks.md` (default) |
| Optional MCP Dependencies table | ~30 | **AUQ-gated** — defaults to `spin out` to `.geniro/docs/mcp.md` |
| Custom Agent Invocation ladder | ~25 | **AUQ-gated** — defaults to `spin out` to `.geniro/docs/agent-runtime.md` |
| Updating instructions (1 line ref to `/update`) | ~5 | **inline** (always) |
| Tech stack summary (Detect output) | ~10-30 | **inline** (always — project-specific) |
| Commands (npm scripts / make targets / pyproject scripts) | ~10-30 | **inline** (always — project-specific) |
| Project conventions (from `code-style.md` if exists) | varies | **inline** (always — project-specific) |

**Split heuristic** (default suggestion when AUQ fires):

```
if section.is_plugin_global (same across all Geniro projects):
if LOC > 40: default = spin out
else: default = inline
else: # project-specific
default = inline (project-specific content always inline)
```

### 3.3 Section-by-section AUQ (per Q3)

For each candidate flagged "AUQ-gated" or "spin out (default)", emit one AUQ:

- **Approvals precheck:** category = `claude_md_section_<section-id>`. If `picked != null` → reuse.
- **AUQ options (≤4):** `inline (keep verbose section in CLAUDE.md)` / `spin out (move to.geniro/docs/<topic>.md, CLAUDE.md gets 1-line ref)` / `drop entirely (project doesn't use this feature)`. Recommended option (per heuristic) is first.

To stay under the 4-AUQ-per-call budget, batch section AUQs in groups of 4. Typical run with `hooks-details + mcp + agent-runtime` is one AUQ call.

### 3.4 Write targets

After AUQ resolution:

- `<PROJECT_ROOT>/CLAUDE.md` — inline sections only; section markers (`<!-- geniro-setup-managed -->` / `<!-- geniro-setup-end -->`) wrap each generated section for re-run safety.
- `<PROJECT_ROOT>/.geniro/docs/hooks.md` (if spun out) — from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/docs-templates/hooks.md`.
- `<PROJECT_ROOT>/.geniro/docs/mcp.md` (if spun out) — same pattern.
- `<PROJECT_ROOT>/.geniro/docs/agent-runtime.md` (if spun out) — same pattern.
- `<PROJECT_ROOT>/.geniro/instructions/user-preferences.md` — per (always created).
- `<PROJECT_ROOT>/.geniro/instructions/global.md` — only if user opted in- `<PROJECT_ROOT>/.geniro/workflow/<tracker>.md` — per- `<PROJECT_ROOT>/.geniro/state/setup/state.md` — frontmatter update (`phase: generate → validate`).

All Writes AUQ-gated at **batch level** (one AUQ "Generate all of: CLAUDE.md (X lines),.geniro/instructions/user-preferences.md (Y lines),...? Options: yes / show preview first / edit which files").

### 3.5 Conflict-resolution merge rules (re-run only)

Section merge runs **orchestrator-inline** — no subagent spawn. Each user-edited section is merged against the to-be-generated counterpart per these rules:

1. Preserve all user customizations from EDITED_CONTENT.
2. Apply any factual updates from NEW_CONTENT (e.g., new commands detected, updated skill table rows).
3. If conflict (same statement contradicted), emit `<!-- CONFLICT:... -->` HTML comment with both versions inline; do not pick a side — escalate to AUQ at step 4.
4. Output is the merged section body inserted directly into the CLAUDE.md draft.

Section merge is a bounded read+reason+rewrite task — the orchestrator reads both versions, applies the rules, and writes merged output via `atomic_state_write` to CLAUDE.md. Each merged section is one entry in `## Tool log` as `merge_section inline` (no `Agent` call, just the orchestrator's own work).

### 3.6 user-preferences.md generation

ALL preferences captured in Batch 1 land in `<PROJECT_ROOT>/.geniro/instructions/user-preferences.md` (Q8 — L4 procedural). Format:

```markdown
# User Preferences

## Rules

- **Default branch:** `main`
- **Default ship mode:** `open PR (draft)` — `/implement` Phase Ship pre-selects this option.
- **Default reviewer set:** full (7 built-in dimensions).
- **Communication style:** concise.

## Loaded by

Every Geniro pipeline + discovery skill at Step 0 (initial-load) and at each phase-boundary refresh via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`. Edit via `/geniro:instructions edit user-preferences`.
```

CLAUDE.md `## User Preferences` section becomes a 1-line reference:

```markdown
## User Preferences

See `.geniro/instructions/user-preferences.md`. Loaded automatically by every Geniro pipeline skill.
```

### 3.7 Runtime directories + gitignore

```bash
mkdir -p.geniro/workflow.geniro/instructions.geniro/planning.geniro/knowledge

#.gitignore — only write if file exists and doesn't already cover these (never create from scratch)
if [ -f.gitignore ]; then
grep -q "^\.geniro/\*$".gitignore 2>/dev/null || echo ".geniro/*" >>.gitignore
grep -q "^\!\.geniro/$".gitignore 2>/dev/null || echo "!.geniro/" >>.gitignore
grep -q "^\!\.geniro/workflow/$".gitignore 2>/dev/null || echo "!.geniro/workflow/" >>.gitignore
grep -q "^\!\.geniro/workflow/\*\*$".gitignore 2>/dev/null || echo "!.geniro/workflow/**" >>.gitignore
grep -q "^\!\.geniro/instructions/$".gitignore 2>/dev/null || echo "!.geniro/instructions/" >>.gitignore
grep -q "^\!\.geniro/instructions/\*\*$".gitignore 2>/dev/null || echo "!.geniro/instructions/**" >>.gitignore
fi
```

### 3.8 Install StatusLine (preserved from current skill)

Copy statusline script to stable location and configure user settings:

```bash
mkdir -p "$CLAUDE_USER_DIR/hooks"
cp "${CLAUDE_PLUGIN_ROOT}/hooks/geniro-statusline.js" "$CLAUDE_USER_DIR/hooks/geniro-statusline.js"
```

Check `$CLAUDE_USER_DIR/settings.json` for a `statusLine` entry. If absent, add one pointing to `<config-dir>/hooks/geniro-statusline.js`. If present and points to something else, ask the user before replacing.

Transition to Phase 4.

## Phase 4: Validate

### 4.1 Verification subagent spawn

```
Agent(subagent_type=<resolved-rung>, # via _shared/spawn-agent.md ladder
model="sonnet",
tools=["Read", "Bash", "Glob", "Grep"], # NO Write/Edit per §ACI
prompt="""
Validate the generated <PROJECT_ROOT>/CLAUDE.md against the codebase.

Checklist:
1. Every command in the `## Commands` section runs locally (try `bash -n` syntax check; do not execute).
2. Every claimed file path in `## Tech Stack` exists.
3. Skill table lists exactly 11 skills; no references to dropped skills (/brainstorm, /decompose, /follow-up, /deep-simplify, /features, /learnings, /cleanup, /vendor).
4. Path rules section warns against `~` literal.
5. User Preferences section is a 1-line reference, NOT inlined preferences.
6. Hooks summary line points to `.geniro/docs/hooks.md` if that file exists, else inlines (consistency check).
7. Template variable residue grep: `{{`, `$TEMPLATE_DIR`, `$PROJECT_KNOWLEDGE`, `PLACEHOLDER`, `TODO`, `FIXME`, `customize this`, `replace with`, `fill in`.
8. Stack contamination check: ONLY the detected language/framework appears; no wrong-language commands or code blocks; no multi-framework lists.

Output a markdown report:
## PASS items (one per line)
## DRIFT items (one per line with file:line)

Tools allowed: Read, Bash (read-only), Glob, Grep. Do NOT mutate any file.
Truncate at 4000 chars (drop trailing PASS items first; keep all DRIFT).

Anchor: stay within current cwd; verify with `pwd && git branch --show-current` on first Bash call.
"""
)
```

### 4.2 3-retry escalation loop

| Round | Action |
|---|---|
| 1 | Spawn subagent. If `DRIFT items` empty → transition to Phase Done. Else → regenerate affected sections (jump back to Phase 3 for those sections only). |
| 2 | Re-spawn subagent. Same logic. |
| 3 | Re-spawn subagent. Same logic. |
| 4 | **AUQ escalation:** `accept-with-warnings (proceed to done, drift documented in ## Open Questions) | abort (transition to failed) | re-run from Detect`. |

`## Open Questions` accumulates DRIFT items across rounds — survives compaction.

### 4.3 L2 emit on successful Validate (D9 closure)

Per — emit one L2 `discovery` row on transition to DONE:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
emit_learning <<'EOF'
{
"type": "discovery",
"trust": "verified",
"skill": "setup",
"mode": "init",
"tags": ["setup", "stack", "bootstrap"],
"summary": "bootstrap complete: node/npm/jest, ship_mode=open-PR-draft, full reviewer set",
"entry": {
"stack": "node/npm",
"test_runner": "jest",
"ship_mode_default": "open-pr-draft",
"reviewer_set": "full",
"claude_md_loc": 67,
"spun_out_docs": ["hooks.md", "mcp.md"]
}
}
EOF
```

`trust: verified` per base schema (code-grounded — Detect read real files; no WebFetch).

## Phase 5: Done

### 5.1 Final report

```
✓ /geniro:setup complete (init)

Wrote:
CLAUDE.md (67 lines — thin map)
.geniro/instructions/user-preferences.md (12 lines)
.geniro/docs/hooks.md (84 lines — spun out per AUQ)
.geniro/docs/mcp.md (28 lines — spun out per AUQ)
.geniro/.gitignore (no change — existing ignores cover.geniro/planning/,.geniro/state/,.geniro/knowledge/)

Detected:
Stack: node/npm + jest tests + ESLint
Default branch: main
Ship mode default: open PR (draft)
Reviewer set: full (7 built-in dimensions)

Next:
• Commit: git add CLAUDE.md.geniro/instructions/user-preferences.md.geniro/docs/
• Run a real task: /geniro:plan "your-task-here"
• Or browse skills: /geniro:investigate "what does /geniro:debug do?"
```

(re-run mode prepends a "Migration sweep" section listing applied auto-fixes and any manual-only items requiring user action, then a "Changed since last setup" section with the section-level diff summary.)

### 5.2 State file cleanup

Delete `<PRIMARY_ROOT>/.geniro/state/setup/state.md`:

```bash
rm -f "$PRIMARY_ROOT/.geniro/state/setup/state.md"
rmdir "$PRIMARY_ROOT/.geniro/state/setup/" 2>/dev/null
```

This is the **only** Geniro state file deleted on success — `/setup` is a singleton bootstrap and the state file has zero value once DONE.

**Exception:** if `mode == re-run` AND user opted for `accept-with-warnings` at round 4, the state file is **kept** with `phase: done` and `## Open Questions` populated — surfaces for the next re-run.

### 5.3 Restart-session warning (re-run only, plugin-version delta)

```
⚠ Restart your Claude Code session before using any other Geniro skill.

Claude Code resolves ${CLAUDE_PLUGIN_ROOT} once at session start. The plugin
update brought a new install path, but in-memory skill bodies still reference
the old one. Restart and you're done.
```

Only emitted when `mode == re-run` AND `/setup` detected `plugin.json` version delta vs the version recorded in the prior state file or CLAUDE.md `<!-- geniro-setup-version: -->` marker. Fresh `init` runs never emit this.

## State file schema

Path: `<PRIMARY_ROOT>/.geniro/state/setup/state.md`. T1 tier (session-bound, ephemeral, deleted at Phase Done).

### Frontmatter

```yaml
---
tier: T1
producer: setup
schema-version: 1
branch: <git-branch> # may be empty if not a git repo
timestamp: 2026-05-19T14:32:00Z # last-updated ISO-8601 UTC
phase: detect # init|detect|interview|generate|validate|done|failed
status: in-progress # in-progress|done|failed
non-resumable-actions: [] # typically empty (/setup ships no external sends)
approvals: # schema
- {category: ship_mode_default, prompt: "Default ship mode?", options: [...], picked: "open-pr-draft", at: "2026-05-19T14:05:00Z", asked_in_phase: interview}
- {category: claude_md_section_hooks_details, prompt: "Include hooks details inline?", options: ["inline","spin out","drop"], picked: "spin out", at: "...", asked_in_phase: generate}
geniro_kind: setup-state
geniro_schema_version: m10a-v1
worktree: /absolute/path # cross-check on rehydration
mode: init # init | re-run
template_dir: /Users/you/.claude/plugins/geniro-claude-plugin@.../abc123
detected:
stack: node/npm
lang: node
pkg_mgr: npm
test_runner: jest
has_eslint: true
default_branch_candidates: [main]
evidence:
- {file: package.json, line: 5, snippet: "\"name\": \"my-project\""}
skill_inventory:
- {slug: implement, purpose: "..."}
#... 11 total
preferences:
default_branch: main
ship_mode_default: open-pr-draft
default_reviewer_set: full
communication_style: concise
write_targets:
- {path: CLAUDE.md, op: write, loc: 67}
- {path:.geniro/instructions/user-preferences.md, op: write, loc: 12}
- {path:.geniro/docs/hooks.md, op: write, loc: 84}
validate_rounds: 1
---
```

### Body sections

```markdown
## Phase log
[2026-05-19T14:00:00Z] init → detect (mode=init)
[2026-05-19T14:02:00Z] detect complete — stack=node/npm, evidence_count=14
[2026-05-19T14:05:00Z] interview Batch 1 → 4 preferences captured
[2026-05-19T14:10:00Z] generate Step 3.3 → 3 sections spun out (hooks, mcp, agent-runtime)
[2026-05-19T14:30:00Z] validate round 1 → 0 DRIFT
[2026-05-19T14:32:00Z] → done

## Tool log # selective logging
[14:02:00] Detect: read package.json (evidence #1), package-lock.json (#2),...
[14:30:00] validate: spawn verification-agent → 0 drift items

## Errors # Block 5b (only on failure)
(empty)

## Open Questions # Block 5c (populated on accept-with-warnings)
(empty)

## Persisted approvals # Block 5d (renders frontmatter approvals[])
- ship_mode_default = "open-pr-draft" (asked at interview, 2026-05-19T14:05:00Z)
- claude_md_section_hooks_details = "spin out" (asked at generate, 2026-05-19T14:10:00Z)

## Termination reason # only set on `failed`
```

## Memory I/O

| Layer | Read at | Write at | Notes |
|---|---|---|---|
| L1 CLAUDE.md | Phase 1 (existing AI-tool config scan) | Phase 3 (thin-map CLAUDE.md) | Generated CLAUDE.md is the L1 target; preserves user customizations via orchestrator-inline merge |
| L2 learnings.jsonl | Phase 1 (prior `discovery` query, tag `setup`) | Phase 4 (one `discovery` row on `done`) | `trust: verified` — code-grounded |
| L3 `.geniro/planning/_*.md` | not read | not written | `/setup` and `/onboard` are different skills with non-overlapping write surfaces |
| L4 `.geniro/instructions/*.md` | Phase 1 (rules-only load via `load-custom-instructions.md`) | Phase 3 writes `user-preferences.md`; optional `global.md` if user opted in | Standard format (`## Rules`, `## Additional Steps`, `## Constraints`) |

## Anti-pattern check

| # | Anti-pattern | Status |
|---|---|---|
| 1 | One giant prompt | ✅ SKILL.md modular; phase sections in `_shared/setup/*.md` helpers if SKILL.md grows beyond ~600 LOC |
| 2 | One giant tool | ✅ N/A — Edit/Write/Bash/Glob/Grep native |
| 3 | Unbounded autonomous loop | ✅ 3-retry validation loop with AUQ escalation; no infinite retry |
| 4 | Autonomous external sends in first release | ✅ Phase Generate ACI forbids `mcp__github__*` and network egress; no Slack/PR auto-send |
| 5 | No approval state | ✅ `approvals[]` populated and rendered as Block 5d |
| 6 | No durable plans or goals | ✅ State file mandatory — singleton at `state/setup/state.md` |
| 7 | No compaction strategy | ✅ `## Tool log` + `## Errors` + `## Open Questions` + `## Persisted approvals` populated — survives compaction via SessionStart re-injection |
| 8 | All connectors loaded up front | ✅ N/A |
| 9 | High-risk tools without policy | ✅ §ACI per-phase table; verification subagent constrained to `tools: [Read, Bash, Glob, Grep]`; section-merge runs orchestrator-inline (no subagent) per |
| 10 | Subagents before single-agent MVP measured | ✅ `/setup` uses 1 verification subagent (Phase 4); section-merge is orchestrator-inline per |
| 11 | Dynamic timestamps in plugin-distributed Markdown | ⚠ This SKILL.md must NOT embed runtime timestamps; state file timestamps are fine (state files are generated, not plugin-distributed) |
| 12 | Non-deterministic agent registration order | ✅ N/A — `/setup` consumes registration, doesn't define it |

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I already know this stack, skip Detect" | Every project is different. Auto-detection catches conventions code review misses. |
| "No docs to read, skip documentation scan" | Check first. README.md, CONTRIBUTING.md,.cursorrules — even partial docs contain domain knowledge that improves CLAUDE.md. |
| "Default settings are fine, skip Interview" | User preferences prevent rework. 2 minutes of questions saves 20 minutes of fixing. |
| "The generated files look correct, skip Validate" | Placeholder text and wrong-language content are invisible without systematic scanning. |
| "I already verified inx checks, skip the verification agent" | You generated the files — you're blind to your own mistakes. The independent agent catches residual placeholders, broken paths, and cross-file inconsistencies you anchored past. |
| "I'll write user preferences inline into CLAUDE.md instead of `.geniro/instructions/user-preferences.md`" | No — design fix. Preferences in CLAUDE.md make it self-modify on every preference change, violating "CLAUDE.md is a stable map". |
| "I'll inline every section to make CLAUDE.md comprehensive" | No — split methodology. Sections >40 LOC default to spin-out. CLAUDE.md is a thin map. |
| "I'll skip the section-by-section AUQ to save time" | No — Q3 decision. Concrete cut is runtime-AUQ-driven; defaulting to a fixed cut means losing user control over verbosity. |
| "I'll re-ask preferences every run to keep them fresh" | No — approvals[] persists one-time decisions. Re-ask only on `--reset-prefs` flag. |
| "The user said 'looks good' — setup is done, skip Phase Done cleanup" | No — Phase Done deletes the state file (which has zero value once DONE). Forgetting to delete leaves stale state for the next re-run. |

## Definition of Done

- [ ] Phase 0: Template source located (plugin root or explicit path)
- [ ] Phase 1: Mode detected (init/re-run); codebase analyzed; project documentation scanned; skill inventory captured (11 skills, no dropped refs); L2 prior queries surfaced
- [ ] Phase 2: User interviewed via approvals[]-aware AUQ batches; preferences captured
- [ ] Phase 3: Migration sweep (re-run only) applied auto-fixes for breaking changes; CLAUDE.md generated (thin map); user-preferences.md written;.geniro/docs/*.md spun out per AUQ;.gitignore updated; statusline installed
- [ ] Phase 4: Verification subagent passed (≤3 retry rounds or AUQ escalation on round 4); L2 `discovery` emit fired
- [ ] Phase 5: Final report printed; state file deleted on success path (kept on `accept-with-warnings` or `failed`)
- [ ] Generated CLAUDE.md skill table lists exactly 11 skills; no references to /brainstorm /decompose /follow-up /deep-simplify /features /learnings /cleanup /vendor
- [ ] All user interactions used `AskUserQuestion`
- [ ] If re-run mode + plugin-version delta: restart-session warning emitted

## Cross-references

- — singleton state-file tier definition; `/setup` writes a T1 file
- — L2 base schema with `trust:` field; emit conforms
- — L2 emit trigger table; `discovery` row matches the bootstrap trigger
- — deferred categories; user-preferences row closed here
- — body sections (Tool log, Errors, Open Questions, Persisted approvals, Termination reason)
- Block 5d — approvals[] category list; adds setup-specific categories
- — 7 loop invariants
- — quality-first budgets
- — Evidence Block standard; conforms
- — model tiering; verification subagent on `sonnet` (section merge runs orchestrator-inline, no separate model assignment)
- — per-phase ACI
- (latest doc shape) — TOC structure, anti-rationalization placement; mirrors
- *(internal)* — full design rationale
