---
name: geniro:setup
description: "Use when starting on a new codebase or after a major plugin update. Detects tech stack, generates a project-specific CLAUDE.md (stack, commands, conventions, domain), and validates it. Re-run mode runs a migration sweep. Singleton bootstrap."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[optional: path to template directory]"
---

# Setup: AI-Driven Plugin Setup

4-phase loop: **Detect → Interview → Generate → Validate**. Turns an unfamiliar repository into a Geniro-ready project in one supervised run. **Singleton bootstrap** — one canonical state file at `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (no `<slug>/` subdir, no parallel runs). Supports `init` (first time) and `re-run` (refresh after stack changes). Uninstall is out of scope.

**Anti-goal:** Do NOT become an encyclopedia generator. Every section of the generated CLAUDE.md must justify why it lives inline rather than in `.geniro/docs/<topic>.md`.

## Path constraints

**Don't use `~` in file paths passed to Read, Write, Edit, or Glob** — these tools don't expand `~`, so it creates a literal `~` directory instead of resolving to the home directory. Use `${CLAUDE_PLUGIN_ROOT}` for plugin files or absolute paths for project files.

Resolve the user's Claude config dir once, honoring `CLAUDE_CONFIG_DIR`:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

## Subagent model tiering

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`, plugin-agent spawns OMIT `model=` and inherit the orchestrator tier. Setup has a single spawn — the verification subagent — one of the two documented hardcode carve-outs (`model=sonnet`, justified inline at §4.1 by its read-only tool floor).

| Spawn | Tier | Why |
|---|---|---|
| Verification subagent (validate generated CLAUDE.md against codebase) | `sonnet` | Reads files, checks claims — reasoning but bounded |

## Loop invariants

1. One result per subagent call — the verification subagent returns one structured report.
2. Args validated before exec — every Write to `CLAUDE.md` / `.geniro/instructions/*.md` preceded by Read-then-diff in re-run mode.
3. Permission before side-effect — Write to project root files (`CLAUDE.md`, `.gitignore`) is AUQ-gated at Phase Validate; user-config writes outside PROJECT_ROOT (the §3.6 statusline copy + `settings.json` edit) are gated too — folded into the Phase Validate batch AUQ, with the `settings.json` replacement carrying its own §3.6 confirm when an entry already points elsewhere.
4. Bounded structured results — verification subagent output truncated per the §4.1 subagent-prompt cap; over-long reports trigger AUQ.
5. Hard escalation gates — 3-retry loop on validation drift; on round 4 → AUQ `accept-with-warnings | abort | start-over (re-detect)` (the §4.2 three-option form).
6. Observations not assumed success — every Bash command in Detect requires explicit observation parse, no silent skips.
7. Errors as structured observations — Detect failures written to `## Errors`, not swallowed.

`## Tool log` selective logging: record verification subagent spawns + every Write to project root or `.geniro/`. Skip routine Read/Bash inside Detect.

## Budgets — quality-first

`/geniro:setup` has **zero hard kill caps**. Aborting mid-bootstrap leaves the project in a half-configured state.

| Layer | Lever | Why |
|---|---|---|
| **Class-B escalation gates** | 3-retry validation loop → AUQ | Validation drift after 3 rounds means structural disagreement; surface to user |
| | Verification report truncation per the §4.1 subagent-prompt cap | Long reports inflate context without commensurate signal |
| **Architecture constraints** | Singleton state file (no `<slug>/`) | Parallel `/geniro:setup` runs would race and corrupt `CLAUDE.md` |
| **NOT capped** | Detect duration, Interview question count, total `Read`/`Bash`/`Glob` calls, total subagent spawns | Quality-first |

## ACI surface per phase

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `detect` | `Read`, `Bash` (read-only: `git`, `find`, `grep`, `cat`), `Glob`, `Grep`, `Agent` | `Write`, `Edit`, mutating `Bash`, `mcp__github__*` |
| `interview` | `AskUserQuestion`, `Read` | `Write`, `Edit`, mutating `Bash` |
| `generate` | `Read`, `Write`, `Edit`, `Bash` (mkdir, chmod) | `mcp__github__*`, network egress (`curl`, `gh`, `git push`) |
| `validate` | `Read`, `Bash` (read-only), `Agent` (verification subagent) | `Write`, `Edit` |
| `done` (cleanup) | `Bash` (rm of state file) | everything else |

External sends are not part of `/geniro:setup` ACI. Users wire those via `/geniro:actions` if needed.

## Termination case → state mapping

| Cause | Phase enum on exit | `## Termination reason` body section |
|---|---|---|
| User aborted at Validate AUQ (rejected generated content) | `failed` | "user-aborted at Validate AUQ — generated content rejected; restart via re-run mode" |
| Validation drift cleared after retry | `done` | not written (success path) |
| Validation drift unresolved after 3 retry rounds | `failed` | "validation drift unresolved after 3 rounds — escalate via AUQ; user picks: accept-with-warnings / abort / start-over (re-detect)" |
| Generation hit write-protection | `failed` | "write-protected target — bypass via `.geniro/safety.json` then re-run" |
| Bootstrap completed without drift | `done` | not written |

## Phase 0: Pre-flight

**Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: setup`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Echo contract requires one observable line.

**Resolve `PRIMARY_ROOT`** via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A. `/geniro:setup` writes to `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (singleton — main worktree only, even when invoked from a linked worktree).

`PROJECT_ROOT` is the current project root — the worktree `/geniro:setup` was invoked from (the cwd). `CLAUDE.md`, `.geniro/instructions/`, and `.geniro/workflow/` are written to `PROJECT_ROOT`; only the singleton state file goes to `PRIMARY_ROOT`. When invoked from a linked worktree the two diverge, so keep them distinct.

## Phase 1: Detect

### 1.1 Mode detect and state-file rehydration

Deterministic resolution (no AUQ):

```
if exists(<PRIMARY_ROOT>/.geniro/state/setup/state.md):
    rehydrate via ${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh
    if frontmatter.phase != "done":
        resume from frontmatter.phase
    else:
        mode = re-run (a prior /geniro:setup completed; user is re-invoking)
elif exists(CLAUDE.md):
    mode = re-run (no state file, but a prior CLAUDE.md exists — merge into it rather than overwrite)
else:
    mode = init
```

Write `mode: init | re-run` to state frontmatter; persists across the run.

### 1.2 Query past learnings

After load-custom-instructions, query past learnings (`.geniro/knowledge/learnings.jsonl`) for prior `discovery` entries tagged `setup`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh"
query_learnings --type discovery --tag setup --limit 10
```

Surface in `## Phase log` as `Prior /geniro:setup runs: N (last: <timestamp>, stack: <stack>)`. If N ≥ 1, this is at least the 2nd `/geniro:setup` — useful context for Interview.

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

### 1.4 Codebase scan (Evidence Block standard)

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

The canonical 11-skill list below is the source of truth — `marketplace.json` carries only a `plugins` entry, not a per-skill array, so there is nothing to extract from it. (To cross-check that the list is current, list `${CLAUDE_PLUGIN_ROOT}/skills/` directory entries.)

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

Keep the 8 deleted skills (`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`) out of generated CLAUDE.md — they no longer exist as live skills, so listing them points the user at commands that do not run.

### 1.6 Detect output

All-results land in state frontmatter `detected:` block. The default branch is captured via `git symbolic-ref --short refs/remotes/origin/HEAD` (fallback `git branch --show-current`) into `default_branch_candidates`, surfaced in the Phase 5 report as `Default branch: <branch> (auto-detected)`. Phase log captures one summary line:

```
[<timestamp>] detect complete — stack=node/npm, lang=node, pkg_mgr=npm, has_tests=true (jest), skill_inventory=11, evidence_count=14
```

Transition to Phase 2.

## Phase 2: Interview

### 2.1 Approvals precheck

Before opening any AUQ, read state frontmatter `approvals[]`. For each AUQ slot, check `category == <slot-name>`:

- If present and `picked != null` → reuse the prior answer; emit `## Phase log` line: "Reused prior answer for `<slot>`: `<picked>` (asked_in_phase: `<phase>`)". **No re-ask.**
- If absent → ask via `AskUserQuestion`; on answer, append to `approvals[]`.

`/geniro:setup` has no persistent preference categories. All AUQs are one-shot (detection confirmation, tracker selection, onboard prompt).

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

### 2.3 Codebase confirmations (only if Detect was ambiguous)

E.g., "Detect saw `pyproject.toml` AND `requirements.txt` — primary package manager?" Skip Batch 2 entirely if no ambiguity.

### 2.4 Optional integrations — issue tracker

Use `AskUserQuestion` header "Tracker". The recommended default is whichever tracker Phase 1 detected (else Skip) — e.g. `.github/ISSUE_TEMPLATE/` signals GitHub Issues, a `.gitlab/` directory signals GitLab Issues, a Linear ID or URL in recent commit messages signals Linear.

- Per-tracker mapping (Linear, GitHub Issues, GitLab Issues, Jira, Bitbucket, Skip) — see `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/` for templates.
- On selection, install `.geniro/workflow/<tracker>.md` from template (or stub for non-Linear). Include the AI-Disclosure Prefix section in every workflow file — tracker comments posted from these files need it so human reviewers can tell an AI-authored update from a teammate's.

Store as `$ISSUE_TRACKER_CHOICE` for Phase 3.

### 2.5 Custom instructions

AUQ: "Create a custom `.geniro/instructions/global.md` for project-wide workflow rules?" Default: no (avoid clutter). Users can run `/geniro:instructions create global` later.

Transition to Phase 3.

## Phase 3: Generate

### 3.0 Migration sweep (re-run only)

If `mode == re-run`, run a migration sweep before generating content. This ensures the `.geniro/` directory structure is current before CLAUDE.md and instructions are regenerated.

1. Read `${CLAUDE_PLUGIN_ROOT}/MIGRATION.md`. Parse all `### <name>` entries across ALL `## v<X.Y.Z>` sections — per the consumption contract in MIGRATION.md's preamble: the version heading is not a selection gate, and each entry's read-only auto-detect decides relevance (a user re-running `/geniro:setup` could be coming from any prior version; sweep all entries).
2. For each entry with an `Auto-detect:` field, run the shell command via `bash -c '<command>'`. Run under bash regardless of the user's interactive shell: an unmatched glob stays literal under bash but aborts the command under zsh's default `nomatch`, which would halt the sweep mid-way. Capture output.
3. If output non-empty (user IS affected), branch on the `Auto-fix:` value in this order — test `manual-only` FIRST, because a `manual-only` value carries prose, not a runnable command, so it must not fall through to a branch that runs it via `bash -c`:
   - If the `Auto-fix:` value begins with `manual-only`: log to `## Phase log`: `[<ts>] migration manual-only: <change-name> — will be addressed by Phase 3 regeneration or user action`.
   - Else if the `Auto-fix:` command is destructive (contains `rm`, `-delete`, or `-exec rm`): do NOT apply it silently — a silent destructive sweep can delete working state the user would have chosen to keep. Log to `## Open Questions`: `[<ts>] migration destructive fix NOT auto-applied: <change-name> — run /geniro:update to apply it interactively per-entry`.
   - Else (non-destructive command): run it silently via `bash -c`. Log to `## Phase log`: `[<ts>] migration fix applied: <change-name>`.
4. After sweep, re-run the `Auto-detect:` command for every entry that was auto-applied in step 3 (skip entries deferred to `## Open Questions` and entries logged `manual-only` — those are intentionally still affected, so re-flagging them would double-log). Any auto-applied entry that is still affected is logged to `## Open Questions`.

**No question during the sweep, but destructive fixes are surfaced, not auto-applied.** Setup re-run is user-initiated, so safe mechanical fixes (renames, field additions, mkdir) apply silently. Destructive fixes (rm/delete-class) are never silently applied — they are logged to `## Open Questions` for the user to apply through `/geniro:update`'s per-entry walk, so the sweep cannot reverse a deletion the user deliberately deferred. Auto-fix commands are maintainer-written and tested (same commands `/geniro:update` surfaces with "Fix it for me").

**Init mode skips this step entirely** — fresh installs write the current schema directly.

### 3.1 Pre-write existing-content audit (re-run only)

If `mode == re-run`:

1. Read existing `CLAUDE.md`.
2. Identify project-specific sections (Tech Stack, Commands, Conventions, Domain Context).
3. For each: merge detected updates into existing content via orchestrator-inline merge (preserve user edits + update facts).
4. If existing CLAUDE.md contains legacy geniro-specific sections (skill table, path rules, hooks, updating) from a prior `/geniro:setup` version — **remove them silently**. They're plugin noise.
5. Display merged diff to user; AUQ if diff is non-trivial.

If `mode == init`, skip the pre-write audit and proceed to §3.2.

### 3.2 CLAUDE.md generation — project-only content

CLAUDE.md is a **project file**, not a plugin manual. It contains ONLY information specific to THIS repository. Geniro plugin information (skills, hooks, path rules, MCP dependencies) lives in the plugin's own files and is loaded automatically — it does NOT belong in CLAUDE.md.

Generated CLAUDE.md sections:

| Section | Content | Source |
|---|---|---|
| Header | Project name + 1-line purpose | `README.md` / `package.json` name field |
| Project Overview | What this project does, architecture, key design decisions | `README.md`, `ARCHITECTURE.md`, `docs/` |
| Tech Stack | Languages, frameworks, databases, infra | Phase 1 Detect output |
| Commands | Build, test, lint, typecheck, dev server | `package.json` scripts / `Makefile` / `pyproject.toml` |
| Project Conventions | Naming, patterns, code style rules | `.editorconfig`, ESLint/Prettier config, `CONTRIBUTING.md` |
| Domain Context | Key entities, API patterns, business terms | Project docs, API specs, `.env.example` variable names |

**What does NOT go in CLAUDE.md:**
- Geniro skill table (already in plugin SKILL.md files)
- Path rules / `~` expansion warning (already in plugin CLAUDE.md)
- Safety hooks summary or allowlist (already in plugin hooks/)
- MCP dependencies table (already in plugin settings.json)
- Agent invocation ladder (already in plugin spawn-agent.md)
- Updating instructions (already in plugin update/SKILL.md)
- Any `<!-- geniro-setup-managed -->` markers (CLAUDE.md is user-owned)

### 3.3 Write targets

- `<PROJECT_ROOT>/CLAUDE.md` — project-specific content only. No section markers — CLAUDE.md is user-owned content, not plugin-managed. Re-run mode uses orchestrator-inline merge (preserve user edits + update detected facts).
- `<PROJECT_ROOT>/.geniro/instructions/global.md` — only if user opted in.
- `<PROJECT_ROOT>/.geniro/workflow/<tracker>.md` — per tracker selection.
- `<PRIMARY_ROOT>/.geniro/state/setup/state.md` — frontmatter update (`phase: generate → validate`). The singleton state file lives in `PRIMARY_ROOT`, not `PROJECT_ROOT` — when invoked from a linked worktree these differ, and rehydration + cleanup both look in the main worktree.
- `$CLAUDE_USER_DIR/hooks/geniro-statusline.js` — statusline script copy (§3.6); a user-config write outside PROJECT_ROOT.
- `$CLAUDE_USER_DIR/settings.json` — `statusLine` entry (§3.6); edited only with the user's confirmation when an entry already points elsewhere.

All Writes AUQ-gated at **batch level** (one AUQ "Generate CLAUDE.md (X lines) + .geniro/ files + install statusline? Options: yes / show preview first / edit"). The statusline `settings.json` replacement (when an entry already points elsewhere) carries its own §3.6 confirm on top of this batch consent.

### 3.4 Conflict-resolution merge rules (re-run only)

Section merge runs **orchestrator-inline** — no subagent spawn. Rules:

1. Preserve all user customizations.
2. Apply factual updates from detection (e.g., new commands detected, stack changes).
3. If conflict (same statement contradicted), surface both versions via AUQ — let user pick.
4. Do not add geniro-specific content (skill tables, hook lists, path rules) during merge — those already live in plugin files that load automatically, so adding them to CLAUDE.md duplicates the plugin and wastes tokens on every run.

### 3.5 Runtime directories + gitignore

```bash
mkdir -p .geniro/workflow .geniro/instructions .geniro/planning .geniro/knowledge

# .gitignore — only write if file exists and doesn't already cover these (never create from scratch)
if [ -f .gitignore ]; then
grep -q "^\.geniro/\*$" .gitignore 2>/dev/null || echo ".geniro/*" >> .gitignore
grep -q "^\!\.geniro/$" .gitignore 2>/dev/null || echo "!.geniro/" >> .gitignore
grep -q "^\!\.geniro/workflow/$" .gitignore 2>/dev/null || echo "!.geniro/workflow/" >> .gitignore
grep -q "^\!\.geniro/workflow/\*\*$" .gitignore 2>/dev/null || echo "!.geniro/workflow/**" >> .gitignore
grep -q "^\!\.geniro/instructions/$" .gitignore 2>/dev/null || echo "!.geniro/instructions/" >> .gitignore
grep -q "^\!\.geniro/instructions/\*\*$" .gitignore 2>/dev/null || echo "!.geniro/instructions/**" >> .gitignore
fi
```

### 3.6 Install statusline

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
Agent(subagent_type="general-purpose", # ad-hoc verification agent — spawns as general-purpose directly; the spawn-agent.md ladder applies only if promoted to a plugin-defined agent
model="sonnet", # hardcode carve-out: read-only tool budget (no Write/Edit) IS the safety floor, per _shared/model-tiering.md
tools=["Read", "Bash", "Glob", "Grep"], # NO Write/Edit per §ACI
prompt="""
Validate the generated <PROJECT_ROOT>/CLAUDE.md against the codebase.

First, Read ${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md and run every check it
defines (cross-language contamination, template artifact, generic-placeholder) — that
file is the single source for the contamination + template-residue criteria, with a per-language
wrong-token table that catches stack drift this inline list cannot.

Then run these additional checks:
1. Every command in the `## Commands` section runs locally (try `bash -n` syntax check; do not execute).
2. Every claimed file path in `## Tech Stack` exists.
3. No geniro-specific content: no skill tables, no path rules about `~`, no hooks summary, no MCP tables, no `/geniro:update` instructions. CLAUDE.md is project-only.
4. Template variable residue grep: `{{`, `$TEMPLATE_DIR`, `$PROJECT_KNOWLEDGE`, `PLACEHOLDER`, `TODO`, `FIXME`.
5. No `<!-- geniro-setup-managed -->` or `<!-- geniro-setup-end -->` markers (legacy — CLAUDE.md is user-owned).

Output a markdown report:
## PASS items (one per line)
## DRIFT items (one per line with file:line)

Tools allowed: Read, Bash (read-only), Glob, Grep. Do NOT mutate any file — report DRIFT items;
the orchestrator regenerates affected sections.
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
| 4 | **AUQ escalation:** `Accept with warnings (finish setup; remaining issues noted for next run) | Abort setup | Start over from the beginning (re-detect the codebase)`. |

`## Open Questions` accumulates DRIFT items across rounds — survives compaction.

### 4.3 Emit learning on successful Validate

On transition to DONE — emit one `discovery` learning row, then echo `Recorded learning: <summary>` to the user per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract":

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
"claude_md_loc": 45
}
}
EOF
```

`trust: verified` per base schema (code-grounded — Detect read real files; no WebFetch). The `mode` field records the actual run mode — emit `"re-run"` instead of `"init"` when this fired on a re-run.

## Phase 5: Done

### 5.1 Final report

```
✓ /geniro:setup complete (init)

Wrote:
CLAUDE.md (45 lines — project-specific only)
.gitignore (updated .geniro/ ignores)

Detected:
Stack: node/npm + jest tests + ESLint
Default branch: main (auto-detected)

Next:
• Commit: git add CLAUDE.md
• Run a real task: /geniro:plan "your-task-here"
• Or browse skills: /geniro:investigate "what does /geniro:debug do?"
```

(re-run mode prepends a "Migration sweep" section listing applied auto-fixes and any manual-only items requiring user action, then a "Changed since last setup" section with the section-level diff summary.)

### 5.2 Onboard AUQ

After printing the final report, ask the user if they want to map the codebase:

Use `AskUserQuestion` (header: `"Onboard"`):

- **Label:** `"Map codebase now (Recommended)"` / **Description:** `"Run /geniro:onboard to scan the codebase and produce _CODEBASE_MAP.md — gives all skills structural awareness of your project."`
- **Label:** `"Skip — I'll do it later"` / **Description:** `"You can run /geniro:onboard any time."`

On "Map codebase now" → print `Running /geniro:onboard...` and invoke the onboard skill inline (same session, no restart needed). On "Skip" → proceed to state file cleanup.

**Skip this AUQ in re-run mode** — the user already has a codebase map from a prior `/geniro:onboard` run (or chose to skip it). Re-run is for refreshing CLAUDE.md and running migrations, not re-onboarding.

### 5.3 State file cleanup

Delete `<PRIMARY_ROOT>/.geniro/state/setup/state.md`:

```bash
rm -f "$PRIMARY_ROOT/.geniro/state/setup/state.md"
rmdir "$PRIMARY_ROOT/.geniro/state/setup/" 2>/dev/null
```

This is the **only** Geniro state file deleted on success — `/geniro:setup` is a singleton bootstrap and the state file has zero value once DONE.

**Exception:** if `mode == re-run` AND user opted for `accept-with-warnings` at round 4, the state file is **kept** with `phase: done` and `## Open Questions` populated — surfaces for the next re-run.

### 5.4 Restart-session warning (re-run only, plugin-version delta)

```
⚠ Restart your Claude Code session before using any other Geniro skill.

Claude Code resolves ${CLAUDE_PLUGIN_ROOT} once at session start. The plugin
update brought a new install path, but in-memory skill bodies still reference
the old one. Restart and you're done.
```

Only emitted when `mode == re-run` AND the current `.claude-plugin/plugin.json` version differs from the `plugin_version:` recorded in the prior state file. Init runs write `plugin_version` fresh and never emit this; a prior state file that predates the field (no `plugin_version:`) yields no computable delta, so no warning fires.

## State file schema

Path: `<PRIMARY_ROOT>/.geniro/state/setup/state.md`. T1.5 tier (durable task state — singleton; deleted at Phase Done since the bootstrap state has zero value once complete).

### Frontmatter

```yaml
---
tier: T1.5
producer: setup
schema-version: 1
branch: <git-branch> # may be empty if not a git repo
timestamp: 2026-05-19T14:32:00Z # last-updated ISO-8601 UTC
phase: detect # detect|interview|generate|validate|done|failed
status: in-progress # in-progress|done|failed
non-resumable-actions: [] # typically empty (/geniro:setup ships no external sends)
approvals: [] # no preference questions; AUQ-only for detection confirm + onboard prompt
geniro_kind: setup-state
geniro_schema_version: m10a-v1
worktree: /absolute/path # cross-check on rehydration
mode: init # init | re-run
template_dir: /Users/you/.claude/plugins/geniro-claude-plugin@.../abc123
plugin_version: 2.21.1 # from .claude-plugin/plugin.json; the §5.4 restart-warning compares this against the current plugin.json version (missing on a pre-field state file → no delta computable → no warning)
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
write_targets:
- {path: CLAUDE.md, op: write, loc: 45}
validate_rounds: 1
---
```

### Body sections

```markdown
## Phase log
[2026-05-19T14:00:00Z] init → detect (mode=init)
[2026-05-19T14:02:00Z] detect complete — stack=node/npm, evidence_count=14
[2026-05-19T14:05:00Z] interview → detection confirmed, tracker: Linear
[2026-05-19T14:10:00Z] generate → CLAUDE.md written (45 lines, project-specific only)
[2026-05-19T14:30:00Z] validate round 1 → 0 DRIFT
[2026-05-19T14:32:00Z] → done

## Tool log # selective logging
[14:02:00] Detect: read package.json (evidence #1), package-lock.json (#2),...
[14:30:00] validate: spawn verification subagent → 0 drift items

## Errors # Block 5b (only on failure)
(empty)

## Open Questions # Block 5c (populated on accept-with-warnings)
(empty)

## Persisted approvals # Block 5d (renders frontmatter approvals[])
(empty — no preference questions in current /geniro:setup)

## Termination reason # only set on `failed`
```

## Memory I/O

| Layer | Read at | Write at | Notes |
|---|---|---|---|
| CLAUDE.md (not a memory layer) | Phase 1 (existing AI-tool config scan) | Phase 3 (project-specific CLAUDE.md) | Contains ONLY project info (stack, commands, conventions, domain). No geniro plugin info. Preserves user customizations via orchestrator-inline merge |
| L2 learnings.jsonl | Phase 1 (prior `discovery` query, tag `setup`) | Phase 4 (one `discovery` row on `done`) | `trust: verified` — code-grounded |
| L3 `.geniro/planning/_*.md` | not read | not written | `/geniro:setup` and `/geniro:onboard` are different skills with non-overlapping write surfaces |
| L4 `.geniro/instructions/*.md` | Phase 1 (rules-only load via `load-custom-instructions.md`) | Optional `global.md` if user opted in | Standard format (`## Rules`, `## Additional Steps`, `## Constraints`) |

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I already know this stack, skip Detect" | Every project is different. Auto-detection catches conventions code review misses. |
| "No docs to read, skip documentation scan" | Check first. README.md, CONTRIBUTING.md,.cursorrules — even partial docs contain domain knowledge that improves CLAUDE.md. |
| "Default settings are fine, skip Interview" | User preferences prevent rework. 2 minutes of questions saves 20 minutes of fixing. |
| "The generated files look correct, skip Validate" | Placeholder text and wrong-language content are invisible without systematic scanning. |
| "I already verified everything in my own checks, skip the verification subagent" | You generated the files — you're blind to your own mistakes. The independent subagent catches residual placeholders, broken paths, and cross-file inconsistencies you anchored past. |
| "I'll add the Geniro skill table / hooks list / path rules to CLAUDE.md" | No — CLAUDE.md is project-specific. Plugin info lives in plugin files and is loaded automatically. Adding it to CLAUDE.md wastes tokens on every run. |
| "I'll add preference questions to the interview to customize defaults" | No — skill defaults are built into each skill. Setup detects the codebase and generates CLAUDE.md; it does not configure skill behavior. |
| "The user said 'looks good' — setup is done, skip Phase Done cleanup" | No — Phase Done deletes the state file (which has zero value once DONE). Forgetting to delete leaves stale state for the next re-run. |

## Definition of Done

- [ ] Phase 0: Template source located (plugin root or explicit path)
- [ ] Phase 1: Mode detected (init/re-run); codebase analyzed; project documentation scanned; L2 prior queries surfaced
- [ ] Phase 2: Detection confirmed; codebase ambiguities resolved; optional integrations configured
- [ ] Phase 3: Migration sweep (re-run only) applied auto-fixes; CLAUDE.md generated (project-specific only — no geniro plugin info); .gitignore updated; statusline installed
- [ ] Phase 4: Verification subagent passed (≤3 retry rounds or AUQ escalation on round 4); L2 `discovery` emit fired
- [ ] Phase 5: Final report printed; onboard AUQ offered (init only); state file deleted on success path
- [ ] Generated CLAUDE.md contains ZERO geniro-specific content (no skill tables, no path rules, no hooks, no updating instructions)
- [ ] All user interactions used `AskUserQuestion`
- [ ] If re-run mode + plugin-version delta: restart-session warning emitted

## Cross-references

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — singleton state-file tier definition (`/geniro:setup` writes a T1.5 durable file) and body sections (Tool log, Errors, Open Questions, Persisted approvals, Termination reason).
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` — the contamination + template-residue check set the §4.1 verification subagent reads and runs (single source for the per-language wrong-token table).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` — L2 base schema with `trust:` field and emit trigger table; the §4.3 `discovery` row conforms and matches the bootstrap trigger.
- §Loop invariants and §Budgets (this file) — 7 loop invariants and quality-first budgets.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` — Evidence Block standard; §1.4 conforms.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — model tiering; verification subagent on `sonnet` (section merge runs orchestrator-inline, no separate model assignment).
- §ACI surface per phase (this file) — per-phase ACI.
- `/geniro:setup` adds no preference categories — `approvals[]` stays empty / one-shot (detection-confirm + onboard prompt only).
