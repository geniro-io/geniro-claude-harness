---
name: setup
description: "Use when starting on a new codebase or after a major plugin update. Detects tech stack, generates a project-specific CLAUDE.md (stack, commands, conventions, domain), and validates it. Re-run mode runs a migration sweep. Singleton bootstrap."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[optional: path to template directory]"
---

# Setup: AI-driven plugin setup

4-phase loop: **Detect → Interview → Generate → Validate**. Turns an unfamiliar repository into a Geniro-ready project in one supervised run. **Singleton bootstrap** — one canonical state file at `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (no `<slug>/` subdir, no parallel runs). Supports `init` (first time) and `re-run` (refresh after stack changes). Uninstall is out of scope.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference: the plugin root is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. Tool and hook substitutions for non-Claude-Code runtimes: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md`.

**Anti-goal:** Do NOT become an encyclopedia generator. Every section of the generated CLAUDE.md must justify why it lives inline rather than in `.geniro/docs/<topic>.md`.

## Path constraints

**No `~` in file paths passed to Read, Write, Edit, or Glob** (not expanded — creates a literal `~` directory); use `${CLAUDE_PLUGIN_ROOT}` for plugin files, absolute paths for project files.

Resolve the user's Claude config dir once, honoring `CLAUDE_CONFIG_DIR`:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

## Subagent model tiering

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`, plugin-agent spawns OMIT `model=` and inherit the orchestrator tier. Setup has a single spawn — the verification subagent — a documented hardcode carve-out (`model=sonnet`, justified inline at §4.1).

| Spawn | Tier | Why |
|---|---|---|
| Verification subagent (validate generated CLAUDE.md against codebase) | `sonnet` | Mechanical check-and-report: runs a fixed check list and emits PASS/DRIFT lines the orchestrator re-decides from, so its output does not scale with orchestrator tier |

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

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. Aborting mid-bootstrap leaves the project in a half-configured state, so this skill's own gates escalate rather than abort:

| Layer | Lever | Why |
|---|---|---|
| **Class-B escalation gates** | 3-retry validation loop → AUQ | Validation drift after 3 rounds means structural disagreement; surface to user |
| | Verification report truncation per the §4.1 subagent-prompt cap | Long reports inflate context without commensurate signal |
| **Architecture constraints** | Singleton state file (no `<slug>/`) | Parallel `/geniro:setup` runs would race and corrupt `CLAUDE.md` |

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

`PROJECT_ROOT` is the current project root — the worktree `/geniro:setup` was invoked from (the cwd). `CLAUDE.md` is written to `PROJECT_ROOT` — a tracked repo file that belongs to the invoked checkout/branch. `.geniro/instructions/` and `.geniro/workflow/` are written to `<PRIMARY_ROOT>` — cross-session user-authored content that must survive worktree removal, per the primary-worktree contract. When invoked from a linked worktree the two diverge, so keep them distinct.

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

After load-custom-instructions, query past learnings for prior `discovery` entries tagged `setup` — route per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override": under a `## Memory Backend` block query the declared read tool (the file `.geniro/knowledge/learnings.jsonl` is empty under `mode: replace`), else:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh"
query_learnings --type discovery --tag setup --limit 10
```

Surface in `## Phase log` as `Prior /geniro:setup runs: N (last: <timestamp>, stack: <stack>)`. If N ≥ 1, this is at least the 2nd `/geniro:setup` — useful context for Interview.

### 1.3 Locate plugin source

Set `TEMPLATE_DIR` to `${CLAUDE_PLUGIN_ROOT}`, falling back to `$ARGUMENTS` when that is unset or does not look like a plugin root. Test the candidate by the presence of an `agents/` directory inside it — a path that merely exists proves nothing, and a wrong `TEMPLATE_DIR` surfaces much later as missing templates mid-generation. When neither candidate passes, transition to Phase Failed with an `## Errors` row rather than continuing on a guess. Write the resolved path to state frontmatter `template_dir:`.

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

**Spec-driven-development tooling (read-only):** an `openspec/` directory (the default OpenSpec root; a non-default checkout shows the same `project.md` / `specs/` / `changes/` children under a different top-level dir). Store the resolved root as `$OPENSPEC_ROOT` (empty when absent) for the Phase 2 OpenSpec integration question.

Store as `$PROJECT_KNOWLEDGE` for Phase 3.

### 1.5 Skill inventory

The canonical list below is the source of truth — `marketplace.json` carries only a `plugins` entry, not a per-skill array, so there is nothing to extract from it. (To cross-check that the list is current, list `${CLAUDE_PLUGIN_ROOT}/skills/` directory entries — every subdirectory except `_shared` is a skill.)

```yaml
skill_inventory:
- {slug: implement, purpose: "Spec-driven implementation"}
- {slug: plan, purpose: "Spec-first planning"}
- {slug: review, purpose: "Multi-dim code review"}
- {slug: resolve, purpose: "PR-feedback triage → fix plan"}
- {slug: debug, purpose: "Scientific-method investigation"}
- {slug: refactor, purpose: "Zero-behavior-change restructuring"}
- {slug: onboard, purpose: "Codebase mapping"}
- {slug: investigate, purpose: "Codebase Q&A"}
- {slug: reflect, purpose: "on-demand session-history rule mining"}
- {slug: instructions, purpose: "L4 rules CRUD"}
- {slug: actions, purpose: "Workflow-helper CRUD + runner"}
- {slug: setup, purpose: "Project bootstrap"}
- {slug: update, purpose: "Plugin update + integrity check"}
```

`skill_inventory` is the source of truth for which skills exist. Name a skill anywhere this run produces user-facing text (the Phase 5 report's next-step suggestions, any generated content) only if it appears in that block — a slug drawn from anywhere else points the user at a command that does not run.

### 1.6 Detect output

All-results land in state frontmatter `detected:` block. The default branch is captured via `git symbolic-ref --short refs/remotes/origin/HEAD` (fallback `git branch --show-current`) into `default_branch_candidates`, surfaced in the Phase 5 report as `Default branch: <branch> (auto-detected)`. Phase log captures one summary line:

```
[<timestamp>] detect complete — stack=node/npm, lang=node, pkg_mgr=npm, has_tests=true (jest), skill_inventory=<count from §1.5>, evidence_count=14
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
- On selection, install `<PRIMARY_ROOT>/.geniro/workflow/<tracker>.md` from template (or stub for non-Linear). Include the AI-Disclosure Prefix section in every workflow file — tracker comments posted from these files need it so human reviewers can tell an AI-authored update from a teammate's.

Store as `$ISSUE_TRACKER_CHOICE` for Phase 3.

### 2.4b Optional integrations — OpenSpec

Fires only when Phase 1 detected OpenSpec (`$OPENSPEC_ROOT` non-empty). When absent, skip silently.

Use `AskUserQuestion` header "OpenSpec", question "This repo uses OpenSpec (at `$OPENSPEC_ROOT`). Have `/geniro:plan` duplicate approved plans into OpenSpec change proposals, and `/geniro:implement` archive them after ship?", options "Yes — add the OpenSpec steps" (Recommended) / "No — skip". On "Yes", append the two instruction blocks to the project's custom-instruction files (creating each from the `instructions-template.md` scaffold first if absent):
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/openspec-plan.md` → merge its `## Additional Steps` → `### After user-approve` subsection into `<PRIMARY_ROOT>/.geniro/instructions/plan.md`.
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/openspec-implement.md` → merge its `### After ship` subsection into `<PRIMARY_ROOT>/.geniro/instructions/implement.md`.

The OpenSpec procedure lives ENTIRELY in these project instruction files — the plugin's `/geniro:plan` and `/geniro:implement` stay tool-agnostic and just execute the user-authored `### After user-approve` / `### After ship` steps via their custom-step anchors. On "No", write nothing.

Store as `$OPENSPEC_CHOICE` for Phase 3.

### 2.5 Custom instructions

AUQ: "Create a custom `.geniro/instructions/global.md` for project-wide workflow rules?" Default: no (avoid clutter). Users can run `/geniro:instructions create global` later. `global.md` also hosts the cross-skill `### After worktree-setup` step, if the project needs a per-worktree bootstrap (e.g. building a per-worktree code index for an MCP) to run whenever a skill creates a new worktree.

Transition to Phase 3.

## Phase 3: Generate

### 3.0 Migration sweep (re-run only)

If `mode == re-run`, run a migration sweep before generating content. This ensures the `.geniro/` directory structure is current before CLAUDE.md and instructions are regenerated.

1. Read `${CLAUDE_PLUGIN_ROOT}/MIGRATION.md`. Parse all `### <name>` entries across ALL `## v<X.Y.Z>` sections — per the consumption contract in MIGRATION.md's preamble: the version heading is not a selection gate, and each entry's read-only auto-detect decides relevance (a user re-running `/geniro:setup` could be coming from any prior version; sweep all entries).
2. For each entry with an `Auto-detect:` field, run the shell command via `bash -c '<command>'`. Run under bash regardless of the user's interactive shell: an unmatched glob stays literal under bash but aborts the command under zsh's default `nomatch`, which would halt the sweep mid-way. Capture output.
3. If output non-empty (user IS affected), branch on the `Auto-fix:` value in this order — test `manual-only` FIRST, because a `manual-only` value carries prose, not a runnable command, so it must not fall through to a branch that runs it via `bash -c`:
   - If the `Auto-fix:` value begins with `manual-only` (matched case-insensitively, so `Manual-only` is caught too): log to `## Phase log`: `[<ts>] migration manual-only: <change-name> — will be addressed by Phase 3 regeneration or user action`.
   - Else if the `Auto-fix:` command is destructive (contains `rm`, `-delete`, or `-exec rm`): do NOT apply it silently — a silent destructive sweep can delete working state the user would have chosen to keep. Log to `## Open Questions`: `[<ts>] migration destructive fix NOT auto-applied: <change-name> — run /geniro:update to apply it interactively per-entry`. When any detected path sits inside a task-dir (`.geniro/planning/<task-dir>/` or `.geniro/state/<skill>/<slug>/`) whose `state.md` shows a live task (present, with non-terminal `phase:`/`status:`), append `; <M> detected path(s) belong to a live task — /geniro:update's live-task guard excludes them from the fix`, so the deferred entry carries the liveness context into the walk.
   - Else (non-destructive command): run it silently via `bash -c`. Log to `## Phase log`: `[<ts>] migration fix applied: <change-name>`.
4. After sweep, re-run the `Auto-detect:` command for every entry that was auto-applied in step 3 (skip entries deferred to `## Open Questions` and entries logged `manual-only` — those are intentionally still affected, so re-flagging them would double-log). Any auto-applied entry that is still affected is logged to `## Open Questions`.

**No question during the sweep, but destructive fixes are surfaced, not auto-applied.** Setup re-run is user-initiated, so safe mechanical fixes (renames, field additions, mkdir) apply silently. Destructive fixes (rm/delete-class) are never silently applied — they are logged to `## Open Questions` for the user to apply through `/geniro:update`'s per-entry walk, so the sweep cannot reverse a deletion the user deliberately deferred. Auto-fix commands are maintainer-written and tested (same commands `/geniro:update` surfaces with "Fix it for me").

**Init mode skips this step entirely** — fresh installs write the current schema directly.

### 3.1 Pre-write existing-content audit (re-run only)

If `mode == re-run`:

1. Read existing `CLAUDE.md`.
2. Identify project-specific sections (Tech Stack, Commands, Conventions, Domain Context).
3. For each: merge detected updates into existing content via orchestrator-inline merge (preserve user edits + update facts).
4. If existing CLAUDE.md carries anything on the §3.2 exclusion list from a prior `/geniro:setup` version — **remove it silently**. It is plugin noise the plugin already loads on its own.
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

**What does NOT go in CLAUDE.md** (the single enumeration — §3.1, §3.4, §4.1, and the Definition of done all resolve to this list):
- Geniro skill table (already in plugin SKILL.md files)
- Path rules / `~` expansion warning (already in plugin CLAUDE.md)
- Safety hooks summary or allowlist (already in plugin hooks/)
- MCP dependencies table (already in plugin settings.json)
- Agent invocation ladder (already in plugin spawn-agent.md)
- Updating instructions (already in plugin update/SKILL.md)
- Any `<!-- geniro-setup-managed -->` markers (CLAUDE.md is user-owned)

### 3.3 Write targets

- `<PROJECT_ROOT>/CLAUDE.md` — project-specific content only. No section markers — CLAUDE.md is user-owned content, not plugin-managed. Re-run mode uses orchestrator-inline merge (preserve user edits + update detected facts).
- `<PRIMARY_ROOT>/.geniro/instructions/global.md` — only if user opted in.
- `<PRIMARY_ROOT>/.geniro/workflow/<tracker>.md` — per tracker selection.
- `<PRIMARY_ROOT>/.geniro/instructions/{plan,implement}.md` — only if OpenSpec was detected AND the user enabled it (§2.4b); the `### After user-approve` / `### After ship` blocks merged from the OpenSpec instruction templates.
- `<PRIMARY_ROOT>/.geniro/state/setup/state.md` — frontmatter update (`phase: generate → validate`). The singleton state file lives in `PRIMARY_ROOT`, not `PROJECT_ROOT` — when invoked from a linked worktree these differ, and rehydration + cleanup both look in the main worktree.
- `$CLAUDE_USER_DIR/hooks/geniro-statusline.js` — statusline script copy (§3.6); a user-config write outside PROJECT_ROOT.
- `$CLAUDE_USER_DIR/settings.json` — `statusLine` entry (§3.6); edited only with the user's confirmation when an entry already points elsewhere.

All Writes AUQ-gated at **batch level** (one AUQ "Generate CLAUDE.md (X lines) + .geniro/ files + install statusline? Options: yes / show preview first / edit"). The statusline `settings.json` replacement (when an entry already points elsewhere) carries its own §3.6 confirm on top of this batch consent.

### 3.4 Conflict-resolution merge rules (re-run only)

Section merge runs **orchestrator-inline** — no subagent spawn. Rules:

1. Preserve all user customizations.
2. Apply factual updates from detection (e.g., new commands detected, stack changes).
3. If conflict (same statement contradicted), surface both versions via AUQ — let user pick.
4. Do not add geniro-specific content during merge — apply the §3.2 exclusion list.

### 3.5 Runtime directories + gitignore

Recompute `PRIMARY_ROOT` via the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` inside this same Bash call — Mode A owns the recompute-per-call rule.

```bash
# workflow/ + instructions/ are cross-session → primary worktree. planning/ is task-local (cwd).
# knowledge/ is cross-session too, but its writers self-route to the repo root via lib/repo-root.sh — this cwd mkdir is only a convenience.
mkdir -p "$PRIMARY_ROOT"/.geniro/workflow "$PRIMARY_ROOT"/.geniro/instructions .geniro/planning .geniro/knowledge
```

#### `.gitignore` re-include procedure

The canonical procedure for keeping a `.geniro/` subdirectory committed while the rest of the tree stays ignored. `/geniro:actions` runs this same procedure for `.geniro/actions/` — edit it here, not in a second copy. Substitute the directories that must stay committed for the `for d in ...` list; everything else is invariant. It targets the primary worktree's `.gitignore`, beside the content being negated, and writes only when that file already exists — creating one from scratch would start ignoring files the project deliberately tracks.

```bash
GI="$PRIMARY_ROOT/.gitignore"
if [ -f "$GI" ]; then
  # A bare `.geniro/` line ignores the whole tree and defeats every negation below — drop it first.
  sed -i.bak '/^\.geniro\/$/d' "$GI" && rm -f "$GI.bak"
  add_line() { grep -qxF "$1" "$GI" 2>/dev/null || printf '%s\n' "$1" >> "$GI"; }
  add_line ".geniro/*"
  add_line "!.geniro/"
  for d in workflow instructions; do
    add_line "!.geniro/$d/"
    add_line "!.geniro/$d/**"
  done
fi
```

Each line is appended only when absent, so re-runs are idempotent. A user who wants one of these directories ignored deletes its two `!` lines by hand.

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
model="sonnet", # hardcode carve-out per _shared/model-tiering.md: mechanical check-and-report — a fixed check list in, PASS/DRIFT lines out, and the orchestrator re-decides from those lines, so output quality does not scale with orchestrator tier
prompt="""
You are a READ-ONLY verifier. Do not create, edit, or delete any file, and run no mutating
shell command — report DRIFT items and let the orchestrator regenerate the affected sections.
An edit from here would overwrite content the orchestrator is about to rewrite from the
detected project facts. Read, read-only Bash, Glob, and Grep are the whole job.

Validate the generated <PROJECT_ROOT>/CLAUDE.md against the codebase.

First, Read ${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md and run every check it
defines (cross-language contamination, template artifact, generic-placeholder) — that
file is the single source for the contamination + template-residue criteria, with a per-language
wrong-token table that catches stack drift this inline list cannot.

Then run these additional checks:
1. Every command in the `## Commands` section runs locally (try `bash -n` syntax check; do not execute).
2. Every claimed file path in `## Tech Stack` exists.
3. No Geniro-plugin content. Read ${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md §3.2 "What does
   NOT go in CLAUDE.md" — that list is the single source — and report every item on it that
   appears in the generated file. CLAUDE.md is project-only.
4. Template variable residue grep: `{{`, `$TEMPLATE_DIR`, `$PROJECT_KNOWLEDGE`, `PLACEHOLDER`, `TODO`, `FIXME`.
5. No `<!-- geniro-setup-managed -->` or `<!-- geniro-setup-end -->` markers (legacy — CLAUDE.md is user-owned).

Output a markdown report:
## PASS items (one per line)
## DRIFT items (one per line with file:line)

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

Delete `<PRIMARY_ROOT>/.geniro/state/setup/state.md`, then remove the now-empty `state/setup/` directory (ignore the failure when it is not empty). This is the **only** Geniro state file deleted on success — the named exception recorded in §State file schema.

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

Path: `<PRIMARY_ROOT>/.geniro/state/setup/state.md`. Durable singleton at the T1.5 tier, with one deliberate, named exception to that tier's survives-past-ship rule: `/geniro:setup` deletes the file at Phase Done (§5.3). Bootstrap state describes a one-shot run that is over — no downstream skill reads it, and a stale copy makes the next invocation resolve to `re-run` against a run that already finished. The exception is scoped to this one path; every other T1.5 file survives. Full frontmatter + body-section schema: `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-state-reference.md` — read it before every state write.

## Memory I/O

| Layer | Read at | Write at | Notes |
|---|---|---|---|
| CLAUDE.md (not a memory layer) | Phase 1 (existing AI-tool config scan) | Phase 3 (project-specific CLAUDE.md) | Project-only content per the §3.2 exclusion list. Preserves user customizations via orchestrator-inline merge |
| L2 learnings.jsonl | Phase 1 (prior `discovery` query, tag `setup`) | Phase 4 (one `discovery` row on `done`) | `trust: verified` — code-grounded |
| L3 `.geniro/planning/_*.md` | not read | not written | `/geniro:setup` and `/geniro:onboard` are different skills with non-overlapping write surfaces |
| L4 `.geniro/instructions/*.md` | Phase 1 (rules-only load via `load-custom-instructions.md`) | Optional `global.md` if user opted in | Standard format (`## Rules`, `## Additional Steps`, `## Constraints`) |

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I already know this stack, skip Detect" | Every project is different. Auto-detection catches conventions code review misses. |
| "No docs to read, skip documentation scan" | Check first. README.md, CONTRIBUTING.md, .cursorrules — even partial docs contain domain knowledge that improves CLAUDE.md. |
| "Default settings are fine, skip Interview" | User preferences prevent rework. 2 minutes of questions saves 20 minutes of fixing. |
| "The generated files look correct, skip Validate" | Placeholder text and wrong-language content are invisible without systematic scanning. |
| "I already verified everything in my own checks, skip the verification subagent" | You generated the files — you're blind to your own mistakes. The independent subagent catches residual placeholders, broken paths, and cross-file inconsistencies you anchored past. |
| "I'll add the Geniro skill table / hooks list / path rules to CLAUDE.md" | No — CLAUDE.md is project-specific. Everything on the §3.2 exclusion list lives in plugin files and is loaded automatically; copying it into CLAUDE.md wastes tokens on every run. |
| "I'll add preference questions to the interview to customize defaults" | No — skill defaults are built into each skill. Setup detects the codebase and generates CLAUDE.md; it does not configure skill behavior. |
| "The user said 'looks good' — setup is done, skip Phase Done cleanup" | No — Phase Done deletes the state file (which has zero value once DONE). Forgetting to delete leaves stale state for the next re-run. |

## Definition of done

These are the load-bearing exit gates — the invariants that, if skipped, make the setup incomplete or unsafe. Per-phase mechanics live in their phase sections; this list is the final correctness/contract check, not a re-listing of every step.

- [ ] Generated CLAUDE.md contains ZERO Geniro-plugin content — every entry on the §3.2 exclusion list checked and absent
- [ ] Verification subagent passed (≤3 retry rounds or AUQ escalation on round 4)
- [ ] L2 `discovery` emit fired
- [ ] State file deleted on the success path
- [ ] All user interactions used `AskUserQuestion`
- [ ] If re-run mode + plugin-version delta: restart-session warning emitted

## Cross-references

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — singleton state-file tier definition (`/geniro:setup` writes a T1.5 durable file, deleted at Phase Done per the named exception in §State file schema) and body sections (Tool log, Errors, Open Questions, Persisted approvals, Termination reason).
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` — the contamination + template-residue check set the §4.1 verification subagent reads and runs (single source for the per-language wrong-token table).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` — L2 base schema with `trust:` field and emit trigger table; the §4.3 `discovery` row conforms and matches the bootstrap trigger.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` — Evidence Block standard; §1.4 conforms.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — model tiering; verification subagent on `sonnet` (section merge runs orchestrator-inline, no separate model assignment).
