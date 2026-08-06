---
name: setup
description: "Use when starting on a new codebase or after a major plugin update. Detects tech stack, generates a project-specific CLAUDE.md (stack, commands, conventions, domain), and validates it. Re-run mode runs a migration sweep. Singleton bootstrap."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[optional: path to template directory]"
---

# Setup: AI-driven plugin setup

## Contents

- Path constraints
- Subagent model tiering
- Loop invariants
- Anti-rationalization
- Definition of done
- Budgets — quality-first
- ACI per-phase tool surface
- Termination case → state mapping
- Memory I/O
- Phase 0 — pre-flight
- Phase 1 — Detect · Phase 2 — Interview · Phase 3 — Generate · Phase 4 — Validate · Phase 5 — Done
- State file schema
- Cross-references

---

4-phase loop: **Detect → Interview → Generate → Validate**. Turns an unfamiliar repository into a Geniro-ready project in one supervised run. **Singleton bootstrap** — one canonical state file at `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (no `<slug>/` subdir, no parallel runs). Supports `init` (first time) and `re-run` (refresh after stack changes). Uninstall is out of scope.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve it before following any reference: the plugin root is the ancestor directory of this file containing `.claude-plugin/plugin.json` — substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. Tool and hook substitutions for non-Claude-Code runtimes: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md`.

**Anti-goal:** Do NOT become an encyclopedia generator. CLAUDE.md is auto-loaded on every run in this project, so every section has to justify that recurring cost — keep what changes how a task is executed, and leave anything the model can read on demand from the project's own docs where it already lives.

**After a compaction, re-invoke this skill before running a phase whose steps are not in context** — only a skill's front-loaded prefix is re-attached after a summary; the singleton state file's `phase:` says where to resume.

## Path constraints

**No `~` in file paths passed to Read, Write, Edit, or Glob** (not expanded — creates a literal `~` directory); use `${CLAUDE_PLUGIN_ROOT}` for plugin files, absolute paths for project files.

Resolve the user's Claude config dir once, honoring `CLAUDE_CONFIG_DIR`:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

## Subagent model tiering

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`, plugin-agent spawns OMIT `model=` and inherit the orchestrator tier. Setup has a single spawn — the verification subagent — and it is a documented hardcode carve-out. This table is the one place the carve-out's tier and its reason are stated; the §4.1 spawn site and the Cross-references entry point here.

| Spawn | Tier | Why |
|---|---|---|
| Verification subagent (validate generated CLAUDE.md against codebase) | `sonnet` | Mechanical check-and-report: runs a fixed check list and emits PASS/DRIFT lines the orchestrator re-decides from, so its output does not scale with orchestrator tier |

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply, with five setup-specific bindings:

- **Invariant #2 (args validated before execution)** — every Write to `CLAUDE.md` / `.geniro/instructions/*.md` preceded by Read-then-diff in re-run mode.
- **Invariant #3 (permission before side-effect)** — Write to project root files (`CLAUDE.md`, `.gitignore`) is AUQ-gated at the §3.3 batch gate in Phase Generate; user-config writes outside PROJECT_ROOT (the §3.6 statusline copy + `settings.json` edit) fold into that same batch AUQ, with the `settings.json` replacement carrying its own §3.6 confirm when an entry already points elsewhere.
- **Invariant #4 (bounded structured tool results)** — verification subagent output truncated per the §4.1 subagent-prompt cap; over-long reports trigger AUQ.
- **Invariant #5 (escalation gates, not silent abort)** — 3-retry loop on validation drift; on round 4 → AUQ `accept-with-warnings | abort | start-over (re-detect)` (the §4.2 three-option form).
- **Invariant #7 (errors → structured observations)** — Detect failures written to `## Errors`, not swallowed.

`## Tool log` selective logging: record verification subagent spawns + every Write to project root or `.geniro/`. Skip routine Read/Bash inside Detect.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I already know this stack, skip Detect" | Every project is different. Auto-detection catches conventions code review misses. |
| "No docs to read, skip documentation scan" | Check first. README.md, CONTRIBUTING.md, .cursorrules — even partial docs contain domain knowledge that improves CLAUDE.md. |
| "Default settings are fine, skip Interview" | User preferences prevent rework. 2 minutes of questions saves 20 minutes of fixing. |
| "The generated files look correct, skip Validate" | Placeholder text and wrong-language content are invisible without systematic scanning. |
| "I already verified everything in my own checks, skip the verification subagent" | You generated the files — you're blind to your own mistakes. The independent subagent catches residual placeholders, broken paths, and cross-file inconsistencies you anchored past. |
| "I'll add the Geniro skill table / hooks list / path rules to CLAUDE.md" | No — CLAUDE.md is project-specific. Everything on the `verification-checks.md` §Excluded content list lives in plugin files and is loaded automatically; copying it into CLAUDE.md wastes tokens on every run. |
| "I'll add preference questions to the interview to customize defaults" | No — skill defaults are built into each skill. Setup detects the codebase and generates CLAUDE.md; it does not configure skill behavior. |
| "The user said 'looks good' — setup is done, skip Phase Done cleanup" | No — Phase Done deletes the state file (which has zero value once DONE). Forgetting to delete leaves stale state for the next re-run. |

## Definition of done

These are the load-bearing exit gates — the invariants that, if skipped, make the setup incomplete or unsafe. Per-phase mechanics live in their phase sections; this list is the final correctness/contract check, not a re-listing of every step.

- [ ] Generated CLAUDE.md contains ZERO Geniro-plugin content — every entry on `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` §Excluded content checked and absent
- [ ] Verification subagent passed (≤3 retry rounds or AUQ escalation on round 4)
- [ ] L2 `discovery` emit fired
- [ ] State file deleted on the success path
- [ ] All user interactions used `AskUserQuestion`
- [ ] If re-run mode + plugin-version delta: restart-session warning emitted

## Budgets — quality-first

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. Aborting mid-bootstrap leaves the project in a half-configured state, so this skill's own gates escalate rather than abort:

| Layer | Lever | Why |
|---|---|---|
| **Class-B escalation gates** | 3-retry validation loop → AUQ | Validation drift after 3 rounds means structural disagreement; surface to user |
| | Verification report truncation per the §4.1 subagent-prompt cap | Long reports inflate context without commensurate signal |
| **Architecture constraints** | Singleton state file (no `<slug>/`) | Parallel `/geniro:setup` runs would race and corrupt `CLAUDE.md` |

## ACI per-phase tool surface

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `detect` | `Read`, `Bash` (read-only: `git`, `find`, `grep`, `cat`), `Glob`, `Grep`, `Agent` | `Write`, `Edit`, mutating `Bash`, `mcp__github__*` |
| `interview` | `AskUserQuestion`, `Read` | `Write`, `Edit`, mutating `Bash` |
| `generate` | `Read`, `Write`, `Edit`, `Bash` (mkdir, chmod) | `mcp__github__*`, network egress (`curl`, `gh`, `git push`) |
| `validate` | `Read`, `Bash` (read-only), `Agent` (verification subagent) | `Write`, `Edit` |
| `done` (cleanup) | `Bash` (rm of state file), `AskUserQuestion` (the §5.2 map-the-codebase question), inline invocation of `/geniro:onboard` on that question's "Map codebase now" pick | everything else |

External sends are not part of `/geniro:setup` ACI. Users wire those via `/geniro:actions` if needed.

## Termination case → state mapping

| Cause | Phase enum on exit | `## Termination reason` body section |
|---|---|---|
| User aborted at Validate AUQ (rejected generated content) | `failed` | "user-aborted at Validate AUQ — generated content rejected; restart via re-run mode" |
| Validation drift cleared after retry | `done` | not written (success path) |
| Validation drift unresolved after 3 retry rounds | `failed` | "validation drift unresolved after 3 rounds — escalate via AUQ; user picks: accept-with-warnings / abort / start-over (re-detect)" |
| Generation hit write-protection | `failed` | "write-protected target — bypass via `.geniro/safety.json` then re-run" |
| Bootstrap completed without drift | `done` | not written |

## Memory I/O

| Layer | Read at | Write at | Notes |
|---|---|---|---|
| CLAUDE.md (not a memory layer) | Phase 1 (existing AI-tool config scan) | Phase 3 (project-specific CLAUDE.md) | Project-only content per `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` §Excluded content. Preserves user customizations via orchestrator-inline merge |
| L2 learnings.jsonl | Phase 1 (prior `discovery` query, tag `setup`) | Phase 4 (one `discovery` row on `done`) | `trust: verified` — code-grounded |
| L3 `.geniro/planning/_*.md` | not read | not written | `/geniro:setup` and `/geniro:onboard` are different skills with non-overlapping write surfaces |
| L4 `.geniro/instructions/*.md` | Phase 1 (rules-only load via `load-custom-instructions.md`) | Optional `global.md` if user opted in | Standard format (`## Rules`, `## Additional Steps`, `## Constraints`) |

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
    if frontmatter.phase == "failed":
        surface the `## Termination reason` body section, then mode = re-run
        (a failed run has no phase left to resume into — start fresh)
    elif frontmatter.phase != "done":
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

Set `TEMPLATE_DIR` to `${CLAUDE_PLUGIN_ROOT}`, falling back to `$ARGUMENTS` when that is unset or does not look like a plugin root. Test the candidate by the presence of an `agents/` directory inside it — a path that merely exists proves nothing, and a wrong `TEMPLATE_DIR` surfaces much later as missing templates mid-generation. When neither candidate passes, transition to Phase Failed with an `## Errors` row rather than continuing on a guess.

### 1.4 Codebase scan (Evidence Block standard)

Detect via **lockfile / config presence**, NOT inference:

| Stack signal | Evidence file(s) | Captured |
|---|---|---|
| Node/npm | `package.json` + `package-lock.json` | `pkg_mgr: npm`, `lang: node`, `scripts: {...}` |

The same manifest+lockfile pattern captures `pkg_mgr` and `lang` for every other stack (yarn/pnpm/bun for Node; uv/poetry/pip for Python; Cargo.lock for Rust; go.sum for Go; Gemfile.lock for Ruby; pom.xml/build.gradle* for Java).

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

Reconcile two sources: list `${CLAUDE_PLUGIN_ROOT}/skills/` — every subdirectory except `_shared` is a skill — against the block below, which carries the purpose strings a directory listing cannot. `marketplace.json` holds only a `plugins` entry, not a per-skill array, so there is nothing to extract from it.

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
- {slug: reflect, purpose: "On-demand session-history rule mining"}
- {slug: instructions, purpose: "Custom project-rules management (create/edit/delete)"}
- {slug: actions, purpose: "Workflow-helper CRUD + runner"}
- {slug: setup, purpose: "Project bootstrap"}
- {slug: update, purpose: "Plugin update + integrity check"}
```

Name a skill anywhere this run produces user-facing text (the Phase 5 report's next-step suggestions, any generated content) only when it appears in **both** the listing and the block — a slug present in only one either points the user at a command that does not run or hides one that does. On a mismatch the directory decides which skills exist and the block supplies the purpose; log the delta to `## Phase log` and write the reconciled set to state frontmatter `skill_inventory`.

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

Render the detection summary to a chat message before asking anything. It carries, in this order:

- **Tech Stack**, **Package Manager**, **Test Runner**, **Linter** — one line each, from the §1.4 evidence. A signal Detect could not resolve reads `unknown`; never fill it by inference.
- **Validation Commands** — the resolved build / test / lint / typecheck command, verbatim, one per line. Omit a command the project does not define rather than inventing one.
- **From project documentation** — the domain facts §1.4 extracted (purpose, entities, architecture) with the source files named. Omit this block entirely when `$PROJECT_KNOWLEDGE` is empty.

Then `AskUserQuestion`: `Looks correct` / `Adjust some things`. If adjust, ask specifically what to change.

### 2.3 Codebase confirmations (only if Detect was ambiguous)

E.g., "Detect saw `pyproject.toml` AND `requirements.txt` — primary package manager?" Skip Batch 2 entirely if no ambiguity.

### 2.4 Optional integrations — issue tracker

Use `AskUserQuestion` header "Tracker". The recommended default is whichever tracker Phase 1 detected (else Skip) — e.g. `.github/ISSUE_TEMPLATE/` signals GitHub Issues, a `.gitlab/` directory signals GitLab Issues, a Linear ID or URL in recent commit messages signals Linear.

- Per-tracker mapping (Linear, GitHub Issues, GitLab Issues, Jira, Bitbucket, Skip) — see `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/` for templates.

Record the pick as `$ISSUE_TRACKER_CHOICE` for Phase 3 and write nothing here: Interview is read-only (§ACI per-phase tool surface), and §3.3 installs the workflow file under the batch approval gate invariant #3 requires.

### 2.4b Optional integrations — OpenSpec

Fires only when Phase 1 detected OpenSpec (`$OPENSPEC_ROOT` non-empty). When absent, skip silently.

Use `AskUserQuestion` header "OpenSpec", question "This repo uses OpenSpec (at `$OPENSPEC_ROOT`). Have `/geniro:plan` duplicate approved plans into OpenSpec change proposals, and `/geniro:implement` archive them after ship?", options "Yes — add the OpenSpec steps" (Recommended) / "No — skip".

The OpenSpec procedure lives ENTIRELY in the project's own instruction files — the plugin's `/geniro:plan` and `/geniro:implement` stay tool-agnostic and just execute the user-authored `### After user-approve` / `### After ship` steps via their custom-step anchors.

Record the pick as `$OPENSPEC_CHOICE` for Phase 3 and write nothing here — §3.3 merges the template blocks under the batch approval gate.

### 2.5 Custom instructions

AUQ: "Create a custom `.geniro/instructions/global.md` for project-wide workflow rules?" Default: no (avoid clutter). Users can run `/geniro:instructions create global` later. `global.md` also hosts the cross-skill `### After worktree-setup` step, if the project needs a per-worktree bootstrap (e.g. building a per-worktree code index for an MCP) to run whenever a skill creates a new worktree.

Transition to Phase 3.

## Phase 3: Generate

### 3.0 Migration sweep (re-run only)

When `mode == re-run`, Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` now — before any step of the re-run, echoing per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`, because it is the sole home of this skill's migration apply policy: which `Auto-fix:` values may reach a shell at all, the `manual-only`-tested-first ordering, and the destructive-command deferral. A run that improvises the sweep runs prose through `bash -c`, which is exactly what that policy exists to prevent. Then run its §3.0 sweep before generating content — that file carries every re-run-only procedure this run needs (§3.0 sweep, §3.1 pre-write audit, §3.4 merge rules, §5.4 restart warning).

**Init mode skips this step entirely** — fresh installs have no prior schema and write the current one directly.

### 3.1 Pre-write existing-content audit (re-run only)

When `mode == re-run`, run the audit in `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` §3.1 — it merges detected updates into the existing `CLAUDE.md` instead of overwriting it. Read the file here if this phase resumed after a compaction.

If `mode == init`, skip the pre-write audit and proceed to §3.2.

### 3.2 CLAUDE.md generation — project-only content

CLAUDE.md is a **project file**, not a plugin manual. It contains ONLY information specific to THIS repository. Before generating, Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` §Excluded content — the single enumeration of the plugin content that must not appear in the generated file — and keep every item out.

Generated CLAUDE.md sections:

| Section | Content | Source |
|---|---|---|
| Header | Project name + 1-line purpose | `README.md` / `package.json` name field |
| Project Overview | What this project does, architecture, key design decisions | `README.md`, `ARCHITECTURE.md`, `docs/` |
| Tech Stack | Languages, frameworks, databases, infra | Phase 1 Detect output |
| Commands | Build, test, lint, typecheck, dev server | `package.json` scripts / `Makefile` / `pyproject.toml` |
| Project Conventions | Naming, patterns, code style rules | `.editorconfig`, ESLint/Prettier config, `CONTRIBUTING.md` |
| Domain Context | Key entities, API patterns, business terms | Project docs, API specs, `.env.example` variable names |

### 3.3 Write targets

- `<PROJECT_ROOT>/CLAUDE.md` — project-specific content only. No section markers — CLAUDE.md is user-owned content, not plugin-managed. Re-run mode uses orchestrator-inline merge (preserve user edits + update detected facts).
- `<PRIMARY_ROOT>/.geniro/instructions/global.md` — only if user opted in.
- `<PRIMARY_ROOT>/.geniro/workflow/<tracker>.md` — per `$ISSUE_TRACKER_CHOICE` (§2.4), installed from `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/` (a stub for non-Linear). Include the AI-Disclosure Prefix section in every workflow file — tracker comments posted from these files need it so human reviewers can tell an AI-authored update from a teammate's.
- `<PRIMARY_ROOT>/.geniro/instructions/{plan,implement}.md` — only when `$OPENSPEC_CHOICE` is "Yes" (§2.4b). Merge `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/openspec-plan.md`'s `## Additional Steps` → `### After user-approve` subsection into `plan.md`, and `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/openspec-implement.md`'s `### After ship` subsection into `implement.md`, creating either file from its scaffold in `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/instruction-file-scaffolds.md` first when absent.
- `<PRIMARY_ROOT>/.geniro/state/setup/state.md` — frontmatter update (`phase: generate → validate`). The singleton state file lives in `PRIMARY_ROOT`, not `PROJECT_ROOT` — when invoked from a linked worktree these differ, and rehydration + cleanup both look in the main worktree.
- `$CLAUDE_USER_DIR/hooks/geniro-statusline.js` — statusline script copy (§3.6); a user-config write outside PROJECT_ROOT.
- `$CLAUDE_USER_DIR/settings.json` — `statusLine` entry (§3.6); edited only with the user's confirmation when an entry already points elsewhere.

All Writes AUQ-gated at **batch level** (one AUQ "Generate CLAUDE.md (X lines) + .geniro/ files + install statusline? Options: yes / show preview first / edit"). The statusline `settings.json` replacement (when an entry already points elsewhere) carries its own §3.6 confirm on top of this batch consent.

### 3.4 Conflict-resolution merge rules (re-run only)

Section merge runs **orchestrator-inline** — no subagent spawn. The four merge rules are in `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` §3.4; Read the file here if this phase resumed after a compaction.

### 3.5 Runtime directories + gitignore

Recompute `PRIMARY_ROOT` via the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` inside this same Bash call — Mode A owns the recompute-per-call rule.

```bash
# workflow/ + instructions/ are cross-session → primary worktree. planning/ is task-local (cwd).
# knowledge/ is cross-session too, but its writers self-route to the repo root via lib/repo-root.sh — this cwd mkdir is only a convenience.
mkdir -p "$PRIMARY_ROOT"/.geniro/workflow "$PRIMARY_ROOT"/.geniro/instructions .geniro/planning .geniro/knowledge
```

#### `.gitignore` re-include procedure

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gitignore-negation.md` in the same Bash call that resolved `PRIMARY_ROOT`, with `workflow instructions` as the directories that must stay committed. It drops a bare `.geniro/` line if present (that line would ignore the whole tree and defeat every negation), then idempotently appends `.geniro/*`, `!.geniro/`, `!.geniro/<dir>/`, and `!.geniro/<dir>/**` to the primary worktree's `.gitignore`.

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
Agent(subagent_type="general-purpose", # ad-hoc verification agent — spawns as general-purpose directly; the ${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md ladder applies only if promoted to a plugin-defined agent
model="sonnet", # hardcode carve-out per ${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md — tier and its reason stated in §Subagent model tiering; keep the pin
prompt="""
You are a READ-ONLY verifier. The Agent tool has no per-spawn tool allowlist, so this
paragraph is the whole read-only floor: do not create, edit, or delete any file, and run no
mutating shell command — report DRIFT items and let the orchestrator regenerate the affected
sections. An edit from here would overwrite content the orchestrator is about to rewrite from
the detected project facts. Read, read-only Bash, Glob, and Grep are the whole job.

Validate the generated <PROJECT_ROOT>/CLAUDE.md against the codebase.

First, Read ${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md and run every check it
defines (cross-language contamination, template artifact, generic-placeholder) — that
file is the single source for the contamination, template-residue and placeholder criteria, and
its per-language wrong-token table catches stack drift no fixed grep list would.

Then run these additional checks:
1. Every command in the `## Commands` section runs locally (try `bash -n` syntax check; do not execute).
2. Every claimed file path in `## Tech Stack` exists.
3. No Geniro-plugin content — report every entry of verification-checks.md's §Excluded content
   list that appears in the generated file. CLAUDE.md is project-only.

Output a markdown report:
## PASS items (one per line)
## DRIFT items (one per line with file:line)

Truncate at 4000 chars (drop trailing PASS items first; keep all DRIFT) — the bounded-results
invariant in ${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md, bound here by loop
invariant #4.

Anchor: PROJECT_ROOT is your root — run every Bash call from it (`cd <PROJECT_ROOT> && …`) and resolve every file path under it.
"""
)
```

### 4.2 3-retry escalation loop

Rounds 1-3: spawn the verification subagent. If `DRIFT items` is empty → transition to Phase Done. Else → regenerate affected sections (jump back to Phase 3 for those sections only) and re-spawn.

Round 4 — **AUQ escalation:** `Accept with warnings (finish setup; remaining issues noted for next run) | Abort setup | Start over from the beginning (re-detect the codebase)`.

`## Open Questions` accumulates DRIFT items across rounds — survives compaction.

### 4.3 Emit learning on successful Validate

On transition to DONE — emit one `discovery` learning row, then echo `Recorded learning: <summary>` to the user per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract":

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
emit_learning <<'EOF'
{
"producer": "/geniro:setup",
"scope": "global",
"type": "discovery",
"trust": "verified",
"mode": "init",
"tags": ["setup", "stack", "bootstrap"],
"summary": "bootstrap complete: node/npm/jest, ship_mode=open-PR-draft, full reviewer set",
"ext": {
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

### 5.2 Offer to map the codebase

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

Fires only when `mode == re-run` AND the current `.claude-plugin/plugin.json` version differs from the `plugin_version:` recorded in the prior state file. Init runs write `plugin_version` fresh and never emit this. The warning text and the missing-field case are in `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` §5.4; Read the file here if this phase resumed after a compaction.

## State file schema

Path: `<PRIMARY_ROOT>/.geniro/state/setup/state.md`. Durable singleton at the T1.5 tier, with one deliberate, named exception to that tier's survives-past-ship rule: `/geniro:setup` deletes the file at Phase Done (§5.3). Bootstrap state describes a one-shot run that is over — no downstream skill reads it, and a stale copy makes the next invocation resolve to `re-run` against a run that already finished. The exception is scoped to this one path; every other T1.5 file survives. Full frontmatter + body-section schema: `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-state-reference.md` — read it before every state write.

## Cross-references

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — singleton state-file tier definition (`/geniro:setup` writes a T1.5 durable file, deleted at Phase Done per the named exception in §State file schema) and body sections (Tool log, Errors, Open Questions, Persisted approvals, Termination reason).
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` — every re-run-only procedure (§3.0 sweep, §3.1 pre-write audit, §3.4 merge rules, §5.4 restart warning); an `init` run never reads it.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/migration-walk.md` — the §3.0 re-run sweep's parse / auto-detect / classify / re-verify procedure, shared with `/geniro:update`'s per-entry walk.
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` — §Excluded content (what must never reach CLAUDE.md, applied at §3.2 generation and at Validate) plus the contamination + template-residue check set the §4.1 verification subagent runs (single source for the per-language wrong-token table).
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/instruction-file-scaffolds.md` — the `plan.md` / `implement.md` scaffolds §3.3 writes before merging an OpenSpec block into a file that does not exist yet.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` — L2 base schema with `trust:` field and emit trigger table; the §4.3 `discovery` row conforms and matches the bootstrap trigger.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` — Evidence Block standard; §1.4 conforms.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — model tiering; the verification subagent's `sonnet` carve-out is stated in §Subagent model tiering (section merge runs orchestrator-inline, no separate model assignment).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gitignore-negation.md` — the §3.5 `.gitignore` re-include procedure that keeps `.geniro/workflow/` and `.geniro/instructions/` committed.
