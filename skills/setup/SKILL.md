---
name: geniro:setup
description: "Use when starting on а new codebase or after а major plugin update. Detects tech stack, interviews you about preferences, generates а thin-map CLAUDE.md + .geniro/instructions/user-preferences.md, и validates the result. Singleton bootstrap — one canonical state file."
context: main
model: opus
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[optional: path к template directory] [--reset-prefs]"
---

# Setup: AI-Driven Plugin Setup

M10a 4-phase loop: **Detect → Interview → Generate → Validate**. Turns an unfamiliar repository into а Geniro-ready project в one supervised run. **Singleton bootstrap** — one canonical state file at `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (no `<slug>/` subdir, no parallel runs). Supports `init` (first time) и `re-run` (refresh after stack changes). Uninstall is out of scope. Architecture spec: `architecture/M10a-setup-redesign.md`.

**Anti-goal:** Do NOT become an encyclopedia generator. Every section of the generated CLAUDE.md must justify why it lives inline rather than в `.geniro/docs/<topic>.md` (P-M10-3 split methodology).

## Path Constraints

**NEVER use `~` in file paths passed к Read, Write, Edit, или Glob tools.** Use `${CLAUDE_PLUGIN_ROOT}` for plugin files или absolute paths for project files.

Resolve the user's Claude config dir once, honoring `CLAUDE_CONFIG_DIR`:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

## Subagent Model Tiering

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Every `Agent(...)` spawn passes `model=` explicitly.

| Spawn | Tier | Why |
|---|---|---|
| Verification agent (validate generated CLAUDE.md against codebase) | `sonnet` | Reads files, checks claims — reasoning но bounded |
| Conflict resolution agent (re-run mode, merge existing CLAUDE.md с generated content) | `sonnet` | Pattern-matching merge with judgment calls |

## Loop invariants (M4 §2.2)

1. One result per subagent call — Verification и Conflict-resolver each return one structured report.
2. Args validated before exec — every Write к `CLAUDE.md` / `.geniro/instructions/*.md` preceded by Read-then-diff в re-run mode.
3. Permission before side-effect — Write к project root files (`CLAUDE.md`, `.gitignore`) is AUQ-gated at Phase Validate.
4. Bounded structured results — verification subagent output truncated at ~4K (M4 §2.3 escalation gate); over-long reports trigger AUQ.
5. Hard escalation gates — 3-retry loop on validation drift; on round 4 → AUQ `accept-with-warnings | abort | re-run`.
6. Observations not assumed success — every Bash command в Detect requires explicit observation parse, no silent skips.
7. Errors as structured observations — Detect failures written к `## Errors` (M3 §6 Block 5b), not swallowed.

`## Tool log` selective logging (M3 §6): record verification subagent spawns + every Write к project root or `.geniro/`. Skip routine Read/Bash inside Detect.

## Budgets — quality-first (M4 §2.3)

`/setup` has **zero Class-A hard kill caps**. Aborting mid-bootstrap leaves the project в а half-configured state.

| Layer | Lever | Why |
|---|---|---|
| **Class-B escalation gates** | 3-retry validation loop → AUQ | Validation drift after 3 rounds means structural disagreement; surface к user |
| | Verification report truncation at ~4K chars | Long reports inflate context без commensurate signal |
| **Architecture constraints** | Singleton state file (no `<slug>/`) | Parallel `/setup` runs would race и corrupt `CLAUDE.md` |
| **NOT capped** | Detect duration, Interview question count, total `Read`/`Bash`/`Glob` calls, total subagent spawns | Quality-first |

## ACI surface per phase (M4 §13.5)

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `detect` | `Read`, `Bash` (read-only: `git`, `find`, `grep`, `cat`), `Glob`, `Grep`, `Agent` | `Write`, `Edit`, mutating `Bash`, `mcp__github__*` |
| `interview` | `AskUserQuestion`, `Read` | `Write`, `Edit`, mutating `Bash` |
| `generate` | `Read`, `Write`, `Edit`, `Bash` (mkdir, chmod) | `mcp__github__*`, network egress (`curl`, `gh`, `git push`) |
| `validate` | `Read`, `Bash` (read-only), `Agent` (verification subagent) | `Write`, `Edit` |
| `done` (cleanup) | `Bash` (rm of state file) | everything else |

External sends are not part of `/setup` ACI. Users wire those via `/actions` if needed.

## Termination case → state mapping (M4 §2.1.1)

| Cause | Phase enum on exit | `## Termination reason` body section |
|---|---|---|
| User aborted at Validate AUQ (rejected generated content) | `failed` | "user-aborted at Validate AUQ — generated content rejected; restart via re-run mode" |
| Validation drift cleared after retry | `done` | not written (success path) |
| Validation drift unresolved after 3 retry rounds | `failed` | "validation drift unresolved after 3 rounds — escalate via AUQ; user picks: accept-with-warnings / abort" |
| Generation hit write-protection | `failed` | "write-protected target — bypass via `.geniro/safety.json` then re-run" |
| Bootstrap completed без drift | `done` | not written |

## Phase 0: Pre-flight

**Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: setup`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Echo contract requires one observable line.

**Resolve `PRIMARY_ROOT`** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A. `/setup` writes к `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (singleton — main worktree only, even when invoked from а linked worktree).

## Phase 1: Detect

### 1.1 Mode detect и state-file rehydration

Deterministic resolution (no AUQ):

```
if exists(<PRIMARY_ROOT>/.geniro/state/setup/state.md):
  rehydrate via ${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh
  if frontmatter.phase != "done":
    resume from frontmatter.phase
  else:
    mode = re-run (а prior /setup completed; user is re-invoking)
elif exists(CLAUDE.md) AND grep "<!-- geniro-setup-version:" CLAUDE.md:
  mode = re-run (no state file, but generated marker present)
else:
  mode = init
```

Write `mode: init | re-run` к state frontmatter; persists across the run.

### 1.2 L2 prior-knowledge query

After load-custom-instructions, query L2 (`.geniro/knowledge/learnings.jsonl`) per M2 §5.3 for prior `discovery` entries tagged `setup`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh"
query_learnings --type discovery --tag setup --limit 10
```

Surface в `## Phase log` as `Prior /setup runs: N (last: <timestamp>, stack: <stack>)`. If N ≥ 1, this is at least the 2nd `/setup` — useful context for Interview.

### 1.3 Locate plugin source

```bash
TEMPLATE_DIR="${CLAUDE_PLUGIN_ROOT}"
if [ -z "$TEMPLATE_DIR" ] || [ ! -d "$TEMPLATE_DIR/agents" ]; then
  if [ -n "$ARGUMENTS" ] && [ -d "$ARGUMENTS/agents" ]; then
    TEMPLATE_DIR="$ARGUMENTS"
  else
    echo "ERROR: cannot locate plugin source. \${CLAUDE_PLUGIN_ROOT} unset и no \$ARGUMENTS fallback." >&2
    # → Phase Failed, ## Errors row
    exit 1
  fi
fi
```

Resolved path written к state frontmatter `template_dir:`.

### 1.4 Codebase scan (Evidence Block per M4 §6)

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

Each detection records `{ file: <path>, line: <N>, snippet: "<exact text>" }`. No inference without evidence — if `package.json` exists но no lockfile, `pkg_mgr: unknown` (Interview asks).

**Conventions detected** (read-only — never inferred from heuristic, only from explicit config):

- ESLint config → naming/formatting hints
- Prettier config → style hints
- `.editorconfig` → indentation rules
- `tsconfig.json` / `jsconfig.json` → module resolution
- Test runner: `jest.config.*`, `vitest.config.*`, `pytest.ini`, etc.

**Existing AI tool instructions** (read для domain rules, not just detect presence):

- `.cursorrules`, `.windsurfrules`, `.github/copilot-instructions.md`, `.continue/config.json`, `.cody/`, `AGENTS.md`, `.agents.md`

**Project documentation scan** (extract domain context):

- `README.md`, `CONTRIBUTING.md`, `CONVENTIONS.md`, `ARCHITECTURE.md`, `SECURITY.md`, `API.md`, `docs/architecture.md`, `docs/adr/`, `docs/decisions/`
- API specs: `openapi.{yaml,json}`, `swagger.{yaml,json}`, `asyncapi.{yaml,json}` (extract endpoints/auth/entities — not full content)
- Env docs: `.env.example`, `.env.sample` (variable names и comments; never values)
- GitHub knowledge: `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/`
- Monorepo structure: `turbo.json`, `nx.json`, `pnpm-workspace.yaml`, `lerna.json`

Store as `$PROJECT_KNOWLEDGE` для Phase 3.

### 1.5 Skill inventory

Read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/marketplace.json` (или `plugin.json`). Extract the canonical 11-skill list:

```yaml
skill_inventory:
  - {slug: implement, purpose: "Spec-driven implementation (M4)"}
  - {slug: plan, purpose: "Spec-first planning (M5)"}
  - {slug: review, purpose: "Multi-dim code review (M6)"}
  - {slug: debug, purpose: "Scientific-method investigation (M7)"}
  - {slug: refactor, purpose: "Zero-behavior-change restructuring (M8)"}
  - {slug: onboard, purpose: "Codebase mapping (M9)"}
  - {slug: investigate, purpose: "Codebase Q&A (M9)"}
  - {slug: instructions, purpose: "L4 rules CRUD (M10b)"}
  - {slug: actions, purpose: "Workflow-helper CRUD + runner (M10c)"}
  - {slug: setup, purpose: "Project bootstrap (M10a)"}
  - {slug: update, purpose: "Plugin update + integrity check (M10d)"}
```

If marketplace.json read fails, fallback к the hardcoded list above. **The 8 deleted skills** (`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`) MUST NOT appear in generated CLAUDE.md — they were dropped per master plan §60.

### 1.6 Detect output

All §1.3-§1.5 results land в state frontmatter `detected:` block. Phase log captures one summary line:

```
[<timestamp>] detect complete — stack=node/npm, lang=node, pkg_mgr=npm, has_tests=true (jest), skill_inventory=11, evidence_count=14
```

Transition к Phase 2.

## Phase 2: Interview

### 2.1 Approvals precheck (P-M1-1)

Before opening any AUQ, read state frontmatter `approvals[]`. For each AUQ slot, check `category == <slot-name>`:

- If present и `picked != null` → reuse the prior answer; emit `## Phase log` line: "Reused prior answer for `<slot>`: `<picked>` (asked_in_phase: `<phase>`)". **No re-ask.**
- If absent → ask via `AskUserQuestion`; on answer, append к `approvals[]`.

Categories registered для `/setup`:

| Category | Asked at | Trigger к re-ask |
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

Tech Stack: TypeScript . Next.js . Prisma . React . Tailwind CSS
Package Manager: pnpm
Test Runner: Vitest
Linter: ESLint + Prettier

Validation Commands:
  build:       pnpm run build
  test:        pnpm run test
  lint:        pnpm run lint
  typecheck:   pnpm exec tsc --noEmit

From project documentation:
  Project: Multi-tenant SaaS platform
  Domain entities: Tenants, Workspaces, Projects, Members
  Architecture: Event-driven между services, REST API v2
  (Source: README.md, docs/architecture.md, openapi.yaml, turbo.json)

Is this correct, or want к adjust?
```

If `$PROJECT_KNOWLEDGE` is empty, omit the "From project documentation" section.

AUQ options: `Looks correct` / `Adjust some things`. If adjust, ask specifically what к change.

### 2.3 Question batches (max 2 batches)

**Batch 1 — preferences** (always asked unless `approvals[]` cache hit):

| Slot | Question | Options |
|---|---|---|
| `default_branch` | Default branch для PRs? | `main`, `master`, `develop`, `Other (free-text)` |
| `ship_mode_default` | Default ship mode in `/implement`? | `commit-only`, `push (no PR)`, `open PR (draft)`, `open PR (ready)` |
| `default_reviewer_set` | Which built-in reviewers default-on? | `full set (7 dimensions)`, `bugs+security+tests`, `custom` |
| `communication_style` | Reply style для Geniro skills? | `concise (default)`, `verbose (more rationale)`, `minimal (results-only)` |

**Batch 2 — codebase confirmations** (only if Detect was ambiguous):

E.g., "Detect saw `pyproject.toml` AND `requirements.txt` — primary package manager?" Skip Batch 2 entirely if no ambiguity.

### 2.4 Optional integrations — issue tracker

Use `AskUserQuestion` header "Tracker" — recommended default reflects `$ISSUE_TRACKER` detected в §1.4:

- Per-tracker mapping (Linear, GitHub Issues, GitLab Issues, Jira, Bitbucket, Skip) preserved verbatim from current skill — see `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/` for templates.
- On selection, install `.geniro/workflow/<tracker>.md` from template (или stub for non-Linear). All workflow files MUST include AI-Disclosure Prefix section.

Store as `$ISSUE_TRACKER_CHOICE` для Phase 3.

### 2.5 Custom instructions

AUQ: "Create а custom `.geniro/instructions/global.md` for project-wide workflow rules?" Default: no (avoid clutter). Users can run `/geniro:instructions create global` later.

Transition к Phase 3.

## Phase 3: Generate

### 3.1 Pre-write existing-content audit (re-run only)

If `mode == re-run`:

1. Read existing `CLAUDE.md`. Compute diff against the к-be-generated body (§3.2 output).
2. For each section с `<!-- geniro-setup-managed -->` HTML comment marker, mark for replacement.
3. Sections без the marker = user-edited → **orchestrator-side merge inline** per §3.5 rules (no subagent spawn — section-merge is а bounded reasoning task that fits the orchestrator's own context cleanly; aligns с Anthropic best practice «folding light reasoning into orchestrator when it doesn't flood main context»).
4. Display merged diff к user; AUQ if diff is non-trivial.

If `mode == init`: skip §3.1.

### 3.2 CLAUDE.md generation — split methodology (P-M10-3 closure)

Generated CLAUDE.md body is assembled from candidate sections, each classified by LOC count и content type:

| Section | Default LOC | Default classification |
|---|---|---|
| Header (project name + 1-line purpose) | ~5 | **inline** (always) |
| Getting Started (3-5 lines) | ~5 | **inline** (always) |
| Skill table (slug → 1-line purpose, 11 rows) | ~15 | **inline** (always) |
| Path rules (~6 lines on `~` expansion) | ~10 | **inline** (always) |
| User Preferences (1-line reference) | ~3 | **inline** (always) |
| Safety hooks summary (1 line: "Hooks active — see `.geniro/docs/hooks.md`") | ~2 | **inline** (always) |
| Safety hooks full allowlist details | ~80 | **spin out** к `.geniro/docs/hooks.md` (default) |
| Optional MCP Dependencies table | ~30 | **AUQ-gated** — defaults к `spin out` к `.geniro/docs/mcp.md` |
| Custom Agent Invocation ladder | ~25 | **AUQ-gated** — defaults к `spin out` к `.geniro/docs/agent-runtime.md` |
| Updating instructions (1 line ref к `/update`) | ~5 | **inline** (always) |
| Tech stack summary (Detect output) | ~10-30 | **inline** (always — project-specific) |
| Commands (npm scripts / make targets / pyproject scripts) | ~10-30 | **inline** (always — project-specific) |
| Project conventions (from `code-style.md` if exists) | varies | **inline** (always — project-specific) |

**Split heuristic** (default suggestion when AUQ fires):

```
if section.is_plugin_global (same across all Geniro projects):
  if LOC > 40: default = spin out
  else:        default = inline
else:  # project-specific
  default = inline  (project-specific content always inline)
```

### 3.3 Section-by-section AUQ (per Q3)

For each candidate flagged "AUQ-gated" или "spin out (default)", emit one AUQ:

- **Approvals precheck:** category = `claude_md_section_<section-id>`. If `picked != null` → reuse.
- **AUQ options (≤4):** `inline (keep verbose section в CLAUDE.md)` / `spin out (move к .geniro/docs/<topic>.md, CLAUDE.md gets 1-line ref)` / `drop entirely (project doesn't use this feature)`. Recommended option (per heuristic) is first.

To stay under the 4-AUQ-per-call budget, batch section AUQs в groups of 4. Typical run with `hooks-details + mcp + agent-runtime` is one AUQ call.

### 3.4 Write targets

After AUQ resolution:

- `<PROJECT_ROOT>/CLAUDE.md` — inline sections only; section markers (`<!-- geniro-setup-managed -->` / `<!-- geniro-setup-end -->`) wrap each generated section для re-run safety.
- `<PROJECT_ROOT>/.geniro/docs/hooks.md` (if spun out) — from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/docs-templates/hooks.md`.
- `<PROJECT_ROOT>/.geniro/docs/mcp.md` (if spun out) — same pattern.
- `<PROJECT_ROOT>/.geniro/docs/agent-runtime.md` (if spun out) — same pattern.
- `<PROJECT_ROOT>/.geniro/instructions/user-preferences.md` — per §3.6 (always created).
- `<PROJECT_ROOT>/.geniro/instructions/global.md` — only if user opted in §2.5.
- `<PROJECT_ROOT>/.geniro/workflow/<tracker>.md` — per §2.4.
- `<PROJECT_ROOT>/.geniro/state/setup/state.md` — frontmatter update (`phase: generate → validate`).

All Writes AUQ-gated at **batch level** (one AUQ "Generate all of: CLAUDE.md (X lines), .geniro/instructions/user-preferences.md (Y lines), ...? Options: yes / show preview first / edit which files").

### 3.5 Conflict-resolution merge rules (re-run only)

Section merge runs **orchestrator-inline** — no subagent spawn. Each user-edited section is merged against the to-be-generated counterpart per these rules:

1. Preserve all user customizations from EDITED_CONTENT.
2. Apply any factual updates from NEW_CONTENT (e.g., new commands detected, updated skill table rows).
3. If conflict (same statement contradicted), emit `<!-- CONFLICT: ... -->` HTML comment с both versions inline; do not pick а side — escalate к AUQ at §3.1 step 4.
4. Output is the merged section body inserted directly into the CLAUDE.md draft.

Section merge is а bounded read+reason+rewrite task — the orchestrator reads both versions, applies the rules, и writes merged output via `atomic_state_write` к CLAUDE.md. Each merged section is one entry в `## Tool log` (M3 §6 selective logging) as `merge_section inline` (no `Agent()` call, just the orchestrator's own work).

### 3.6 user-preferences.md generation (P-M2-1 closure)

ALL preferences captured в §2.3 Batch 1 land в `<PROJECT_ROOT>/.geniro/instructions/user-preferences.md` (Q8 — L4 procedural). Format:

```markdown
# User Preferences

## Rules

- **Default branch:** `main`
- **Default ship mode:** `open PR (draft)` — `/implement` Phase Ship pre-selects this option.
- **Default reviewer set:** full (7 built-in dimensions).
- **Communication style:** concise.

## Loaded by

Every Geniro pipeline + discovery skill at Step 0 (initial-load) и at each phase-boundary refresh via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md`. Edit via `/geniro:instructions edit user-preferences`.
```

CLAUDE.md `## User Preferences` section becomes а 1-line reference:

```markdown
## User Preferences

See `.geniro/instructions/user-preferences.md`. Loaded automatically by every Geniro pipeline skill.
```

### 3.7 Runtime directories + gitignore

```bash
mkdir -p .geniro/workflow .geniro/instructions .geniro/planning .geniro/knowledge

# .gitignore — only write if file exists и doesn't already cover these (never create from scratch)
if [ -f .gitignore ]; then
  grep -q "^\.geniro/\*$" .gitignore 2>/dev/null || echo ".geniro/*" >> .gitignore
  grep -q "^\!\.geniro/$" .gitignore 2>/dev/null || echo "!.geniro/" >> .gitignore
  grep -q "^\!\.geniro/workflow/$" .gitignore 2>/dev/null || echo "!.geniro/workflow/" >> .gitignore
  grep -q "^\!\.geniro/workflow/\*\*$" .gitignore 2>/dev/null || echo "!.geniro/workflow/**" >> .gitignore
  grep -q "^\!\.geniro/instructions/$" .gitignore 2>/dev/null || echo "!.geniro/instructions/" >> .gitignore
  grep -q "^\!\.geniro/instructions/\*\*$" .gitignore 2>/dev/null || echo "!.geniro/instructions/**" >> .gitignore
fi
```

### 3.8 Install StatusLine (preserved from current skill)

Copy statusline script к stable location и configure user settings:

```bash
mkdir -p "$CLAUDE_USER_DIR/hooks"
cp "${CLAUDE_PLUGIN_ROOT}/hooks/geniro-statusline.js" "$CLAUDE_USER_DIR/hooks/geniro-statusline.js"
```

Check `$CLAUDE_USER_DIR/settings.json` for а `statusLine` entry. If absent, add one pointing к `<config-dir>/hooks/geniro-statusline.js`. If present и points к something else, ask the user before replacing.

Transition к Phase 4.

## Phase 4: Validate

### 4.1 Verification subagent spawn

```
Agent(
  subagent_type=<resolved-rung>,  # via _shared/spawn-agent.md ladder
  model="sonnet",
  tools=["Read", "Bash", "Glob", "Grep"],  # NO Write/Edit per §ACI
  prompt="""
    Validate the generated <PROJECT_ROOT>/CLAUDE.md against the codebase.

    Checklist:
    1. Every command в the `## Commands` section runs locally (try `bash -n` syntax check; do not execute).
    2. Every claimed file path в `## Tech Stack` exists.
    3. Skill table lists exactly 11 skills; no references к dropped skills (/brainstorm, /decompose, /follow-up, /deep-simplify, /features, /learnings, /cleanup, /vendor).
    4. Path rules section warns against `~` literal.
    5. User Preferences section is а 1-line reference, NOT inlined preferences.
    6. Hooks summary line points к `.geniro/docs/hooks.md` if that file exists, else inlines (consistency check).
    7. Template variable residue grep: `{{`, `$TEMPLATE_DIR`, `$PROJECT_KNOWLEDGE`, `PLACEHOLDER`, `TODO`, `FIXME`, `customize this`, `replace with`, `fill in`.
    8. Stack contamination check: ONLY the detected language/framework appears; no wrong-language commands or code blocks; no multi-framework lists.

    Output а markdown report:
    ## PASS items (one per line)
    ## DRIFT items (one per line with file:line)

    Tools allowed: Read, Bash (read-only), Glob, Grep. Do NOT mutate any file.
    Truncate at 4000 chars (drop trailing PASS items first; keep all DRIFT).

    Anchor: stay within current cwd; verify с `pwd && git branch --show-current` on first Bash call.
  """
)
```

### 4.2 3-retry escalation loop (P-M4-3 Class-B gate)

| Round | Action |
|---|---|
| 1 | Spawn subagent. If `DRIFT items` empty → transition к Phase Done. Else → regenerate affected sections (jump back к Phase 3 для those sections only). |
| 2 | Re-spawn subagent. Same logic. |
| 3 | Re-spawn subagent. Same logic. |
| 4 | **AUQ escalation:** `accept-with-warnings (proceed к done, drift documented в ## Open Questions) | abort (transition к failed) | re-run from Detect`. |

`## Open Questions` (M3 §6 Block 5c) accumulates DRIFT items across rounds — survives compaction.

### 4.3 L2 emit on successful Validate (D9 closure)

Per M2 §5.3 — emit one L2 `discovery` row on transition к DONE (auto-replaces dropped `/learnings`):

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

`trust: verified` per M2 §5.1 base schema (code-grounded — Detect read real files; no WebFetch).

## Phase 5: Done

### 5.1 Final report

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
  • Run а real task: /geniro:plan "your-task-here"
  • Or browse skills: /geniro:investigate "what does /geniro:debug do?"
```

(re-run mode adds а section "Changed since last setup: …" с the section-level diff summary.)

### 5.2 State file cleanup

Delete `<PRIMARY_ROOT>/.geniro/state/setup/state.md`:

```bash
rm -f "$PRIMARY_ROOT/.geniro/state/setup/state.md"
rmdir "$PRIMARY_ROOT/.geniro/state/setup/" 2>/dev/null
```

This is the **only** Geniro state file deleted on success — `/setup` is а singleton bootstrap и the state file has zero value once DONE.

**Exception:** if `mode == re-run` AND user opted for `accept-with-warnings` at §4.2 round 4, the state file is **kept** с `phase: done` и `## Open Questions` populated — surfaces для the next re-run.

### 5.3 Restart-session warning (re-run only, plugin-version delta)

```
⚠ Restart your Claude Code session before using any other Geniro skill.

Claude Code resolves ${CLAUDE_PLUGIN_ROOT} once at session start. The plugin
update brought а new install path, но in-memory skill bodies still reference
the old one. Restart и you're done.
```

Only emitted when `mode == re-run` AND `/setup` detected `plugin.json` version delta vs the version recorded в the prior state file или CLAUDE.md `<!-- geniro-setup-version: -->` marker. Fresh `init` runs never emit this.

## State file schema (M1 §T1 singleton layout)

Path: `<PRIMARY_ROOT>/.geniro/state/setup/state.md`. T1 tier (session-bound, ephemeral, deleted at Phase Done).

### Frontmatter

```yaml
---
tier: T1
producer: setup
schema-version: 1
branch: <git-branch>             # may be empty if not а git repo
timestamp: 2026-05-19T14:32:00Z  # last-updated ISO-8601 UTC
phase: detect                    # init|detect|interview|generate|validate|done|failed
status: in-progress              # in-progress|done|failed
non-resumable-actions: []        # typically empty (/setup ships no external sends)
approvals:                       # P-M1-1 schema
  - {category: ship_mode_default, prompt: "Default ship mode?", options: [...], picked: "open-pr-draft", at: "2026-05-19T14:05:00Z", asked_in_phase: interview}
  - {category: claude_md_section_hooks_details, prompt: "Include hooks details inline?", options: ["inline","spin out","drop"], picked: "spin out", at: "...", asked_in_phase: generate}
geniro_kind: setup-state
geniro_schema_version: m10a-v1
worktree: /absolute/path         # P-M1-2 cross-check on rehydration
mode: init                       # init | re-run
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
  # ... 11 total
preferences:
  default_branch: main
  ship_mode_default: open-pr-draft
  default_reviewer_set: full
  communication_style: concise
write_targets:
  - {path: CLAUDE.md, op: write, loc: 67}
  - {path: .geniro/instructions/user-preferences.md, op: write, loc: 12}
  - {path: .geniro/docs/hooks.md, op: write, loc: 84}
validate_rounds: 1
---
```

### Body sections (M3 §6)

```markdown
## Phase log
[2026-05-19T14:00:00Z] init → detect  (mode=init)
[2026-05-19T14:02:00Z] detect complete — stack=node/npm, evidence_count=14
[2026-05-19T14:05:00Z] interview Batch 1 → 4 preferences captured
[2026-05-19T14:10:00Z] generate Step 3.3 → 3 sections spun out (hooks, mcp, agent-runtime)
[2026-05-19T14:30:00Z] validate round 1 → 0 DRIFT
[2026-05-19T14:32:00Z] → done

## Tool log                        # M3 §6 selective logging
[14:02:00] Detect: read package.json (evidence #1), package-lock.json (#2), ...
[14:30:00] validate: spawn verification-agent → 0 drift items

## Errors                          # M3 §6 Block 5b (only on failure)
(empty)

## Open Questions                  # M3 §6 Block 5c (populated on accept-with-warnings)
(empty)

## Persisted approvals             # M3 §6 Block 5d (renders frontmatter approvals[])
- ship_mode_default = "open-pr-draft" (asked at interview, 2026-05-19T14:05:00Z)
- claude_md_section_hooks_details = "spin out" (asked at generate, 2026-05-19T14:10:00Z)

## Termination reason              # only set on `failed`
```

## Memory I/O (M2 §13)

| Layer | Read at | Write at | Notes |
|---|---|---|---|
| L1 CLAUDE.md | Phase 1 §1.4 (existing AI-tool config scan) | Phase 3 §3.4 (thin-map CLAUDE.md) | Generated CLAUDE.md is the L1 target; preserves user customizations via §3.5 orchestrator-inline merge |
| L2 learnings.jsonl | Phase 1 §1.2 (prior `discovery` query, tag `setup`) | Phase 4 §4.3 (one `discovery` row on `done`) | `trust: verified` — code-grounded; auto-replaces dropped `/learnings` |
| L3 `.geniro/planning/_*.md` | not read | not written | `/setup` и `/onboard` are different skills with non-overlapping write surfaces |
| L4 `.geniro/instructions/*.md` | Phase 1 §1.2 (rules-only load via `load-custom-instructions.md`) | Phase 3 §3.6 writes `user-preferences.md`; optional `global.md` if user opted in | Standard format (`## Rules`, `## Additional Steps`, `## Constraints`) |

## Anti-pattern check (P-MP-1)

| # | Anti-pattern | Status |
|---|---|---|
| 1 | One giant prompt | ✅ SKILL.md modular; phase sections in `_shared/setup/*.md` helpers if SKILL.md grows beyond ~600 LOC |
| 2 | One giant tool | ✅ N/A — Edit/Write/Bash/Glob/Grep native |
| 3 | Unbounded autonomous loop | ✅ §4.2 3-retry validation loop с AUQ escalation; no infinite retry |
| 4 | Autonomous external sends в first release | ✅ Phase Generate ACI forbids `mcp__github__*` и network egress; no Slack/PR auto-send |
| 5 | No approval state | ✅ P-M1-1 `approvals[]` populated (§2.1) и rendered as Block 5d |
| 6 | No durable plans или goals | ✅ State file mandatory — singleton at `state/setup/state.md` |
| 7 | No compaction strategy | ✅ `## Tool log` + `## Errors` + `## Open Questions` + `## Persisted approvals` populated — survives compaction via M3 §6 SessionStart re-injection |
| 8 | All connectors loaded up front | ✅ N/A |
| 9 | High-risk tools без policy | ✅ §ACI per-phase table; verification subagent constrained к `tools: [Read, Bash, Glob, Grep]`; section-merge runs orchestrator-inline (no subagent) per §3.5 |
| 10 | Subagents before single-agent MVP measured | ✅ `/setup` uses 1 verification subagent (Phase 4); section-merge is orchestrator-inline per §3.5 |
| 11 | Dynamic timestamps в plugin-distributed Markdown | ⚠ This SKILL.md must NOT embed runtime timestamps; state file timestamps are fine (state files are generated, not plugin-distributed) |
| 12 | Non-deterministic agent registration order | ✅ N/A — `/setup` consumes registration, doesn't define it |

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I already know this stack, skip Detect" | Every project is different. Auto-detection catches conventions code review misses. |
| "No docs к read, skip §1.4 documentation scan" | Check first. README.md, CONTRIBUTING.md, .cursorrules — even partial docs contain domain knowledge that improves CLAUDE.md. |
| "Default settings are fine, skip Interview" | User preferences prevent rework. 2 minutes of questions saves 20 minutes of fixing. |
| "The generated files look correct, skip Validate" | Placeholder text и wrong-language content are invisible без systematic scanning. |
| "I already verified в §3.x checks, skip the verification agent" | You generated the files — you're blind к your own mistakes. The independent agent catches residual placeholders, broken paths, и cross-file inconsistencies you anchored past. |
| "I'll write user preferences inline into CLAUDE.md instead of `.geniro/instructions/user-preferences.md`" | No — D4 fix. Preferences in CLAUDE.md make it self-modify on every preference change, violating M3 "CLAUDE.md is а stable map". |
| "I'll inline every section к make CLAUDE.md comprehensive" | No — P-M10-3 split methodology. Sections >40 LOC default к spin-out. CLAUDE.md is а thin map. |
| "I'll skip the section-by-section AUQ to save time" | No — Q3 decision. Concrete cut is runtime-AUQ-driven; defaulting к а fixed cut means losing user control over verbosity. |
| "I'll re-ask preferences every run к keep them fresh" | No — P-M1-1 approvals[] persists one-time decisions. Re-ask only on `--reset-prefs` flag. |
| "The user said 'looks good' — setup is done, skip Phase Done cleanup" | No — Phase Done §5.2 deletes the state file (which has zero value once DONE). Forgetting к delete leaves stale state for the next re-run. |

## Definition of Done

- [ ] Phase 0: Template source located (plugin root или explicit path)
- [ ] Phase 1: Mode detected (init/re-run); codebase analyzed; project documentation scanned; skill inventory captured (11 skills, no dropped refs); L2 prior queries surfaced
- [ ] Phase 2: User interviewed via approvals[]-aware AUQ batches; preferences captured
- [ ] Phase 3: CLAUDE.md generated (thin map); user-preferences.md written; .geniro/docs/*.md spun out per AUQ; .gitignore updated; statusline installed
- [ ] Phase 4: Verification subagent passed (≤3 retry rounds или AUQ escalation на round 4); L2 `discovery` emit fired
- [ ] Phase 5: Final report printed; state file deleted on success path (kept on `accept-with-warnings` или `failed`)
- [ ] Generated CLAUDE.md skill table lists exactly 11 skills; no references to /brainstorm /decompose /follow-up /deep-simplify /features /learnings /cleanup /vendor
- [ ] All user interactions used `AskUserQuestion`
- [ ] If re-run mode + plugin-version delta: restart-session warning emitted

## Cross-references

- M1 §T1 — singleton state-file tier definition; `/setup` writes а T1 file
- M2 §5.1 — L2 base schema with `trust:` field; §4.3 emit conforms
- M2 §5.3 — L2 emit trigger table; §4.3 `discovery` row matches the bootstrap trigger
- M2 §12 — P-M2-1 deferred categories; user-preferences row closed here (§3.6)
- M3 §6 — body sections (Tool log, Errors, Open Questions, Persisted approvals, Termination reason)
- M3 §6 Block 5d — approvals[] category list; §2.1 adds setup-specific categories
- M4 §2.2 — 7 loop invariants
- M4 §2.3 — quality-first budgets
- M4 §6 — Evidence Block standard; §1.4 conforms
- M4 §13.4 — model tiering; verification subagent on `sonnet` (section merge runs orchestrator-inline, no separate model assignment)
- M4 §13.5 — per-phase ACI
- M9 (latest doc shape) — TOC structure, anti-rationalization placement; M10a mirrors
- `architecture/M10a-setup-redesign.md` — full design rationale
