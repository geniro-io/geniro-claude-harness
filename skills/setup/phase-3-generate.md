# Setup Phase 3 — Generate

Phase file for `/geniro:setup`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`.

## Contents

- Refresh custom instructions · 3.0 Migration sweep · 3.1 Pre-write audit · 3.2 CLAUDE.md generation
- 3.3 Write targets and batch gate · 3.4 Merge rules · 3.5 Runtime directories + gitignore
- 3.6 Statusline · 3.7 Cursor profile install · 3.8 Codex install

---

**Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: setup`, `LOAD_TIER: rules-only`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract.

### 3.0 Migration sweep (re-run only)

When `mode == re-run`, Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` now — before any step of the re-run, echoing per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — as the sole home of the migration apply policy; an improvised sweep runs prose through `bash -c`. Then run its §3.0 sweep before generating content.

**Init mode skips this step** — fresh installs write the current schema directly.

### 3.1 Pre-write existing-content audit (re-run only)

When `mode == re-run`, run the audit in `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` §3.1 — it merges detected updates into the existing `CLAUDE.md` instead of overwriting it. Read the file here if this phase resumed after a compaction.

If `mode == init`, skip the pre-write audit and proceed to §3.2.

### 3.2 CLAUDE.md generation — project-only content

CLAUDE.md is a **project file**, not a plugin manual: ONLY what is specific to THIS repository, and by the cache rule in SKILL.md only what the agent cannot find by looking — never a copy of what ESLint, Prettier, or `.editorconfig` already enforce, nor a README overview. Before generating, Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` §Excluded content — the single enumeration of the plugin content that must not appear in the generated file — and keep every item out.

Generated CLAUDE.md sections — other skills look these headings up by name, so keep them exactly:

| Section | Content | Source |
|---|---|---|
| Header | Project name + 1-line purpose | `README.md` / `package.json` name field |
| Project Overview | What this project does and the design decisions whose reason is written nowhere else | `README.md`, `ARCHITECTURE.md`, `docs/` |
| Tech Stack | Languages, frameworks, databases, infra | Phase 1 Detect output |
| Essential Commands | Build, test, lint, typecheck, dev server | `package.json` scripts / `Makefile` / `pyproject.toml` |
| Project Conventions | Unwritten conventions and the reason behind a choice | `CONTRIBUTING.md`, existing AI-tool instructions, Interview answers |
| Domain Context | Key entities, API patterns, business terms | Project docs, API specs, `.env.example` variable names |

### 3.3 Write targets

- `<PROJECT_ROOT>/<instruction_file>` (CLAUDE.md, or AGENTS.md per §1.1) — project-specific content only. No section markers — user-owned content, not plugin-managed. Re-run mode uses orchestrator-inline merge (preserve user edits + update detected facts). When `instruction_file` is AGENTS.md and CLAUDE.md is absent, also write `<PROJECT_ROOT>/CLAUDE.md` holding the single line `@AGENTS.md`.
- `<PRIMARY_ROOT>/.geniro/instructions/global.md` — only if user opted in.
- `<PRIMARY_ROOT>/.geniro/workflow/<tracker>.md` — per `$ISSUE_TRACKER_CHOICE` (§2.4), installed from `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/` (a stub for non-Linear). Include the AI-disclosure prefix section, a `## Searching for issues` heading, and a `## PR description` heading in every workflow file — filled in for Linear, left as an unfilled placeholder for the user to complete in the non-Linear stub.
- `<PRIMARY_ROOT>/.geniro/instructions/{plan,implement}.md` — only when `$OPENSPEC_CHOICE` is "Yes" (§2.4b). Merge `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/openspec-plan.md`'s `## Additional Steps` → `### After user-approve` subsection into `plan.md`, and `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/openspec-implement.md`'s `### After ship` subsection into `implement.md`, creating either file from its scaffold in `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/instruction-file-scaffolds.md` first when absent.
- `<PRIMARY_ROOT>/.geniro/state/setup/state.md` — frontmatter update (`phase: generate → validate`). The singleton state file lives in `PRIMARY_ROOT`, not `PROJECT_ROOT` (they differ in a linked worktree; rehydration and cleanup look in the main one).
- `$CLAUDE_USER_DIR/hooks/geniro-statusline.js` — statusline script copy (§3.6); a user-config write outside PROJECT_ROOT.
- `$CLAUDE_USER_DIR/settings.json` — `statusLine` entry (§3.6); edited only with the user's confirmation when an entry already points elsewhere.
- `$HOME/.cursor/{skills,agents}/` and `$HOME/.cursor/hooks.json` — the Cursor profile install (§3.7): symlinks to the plugin's generated Cursor skill and subagent copies, plus its hook entries merged into an existing `hooks.json`. A user-config write outside PROJECT_ROOT, listed when `$HOME/.cursor/` exists and the plugin root carries `cursor/skills/`.
- `$CODEX_HOME/config.toml` and `$CODEX_HOME/plugins/cache/` (`CODEX_HOME` defaults to `~/.codex`) — the Codex install (§3.8): the marketplace entry the `codex` CLI records, plus a copy of the plugin. A user-config write outside PROJECT_ROOT, listed when `codex` is on PATH and the plugin isn't installed there.

Render the write plan to chat first — every §3.3 target, the generated CLAUDE.md line count, the statusline install, and the §3.7 Cursor profile and §3.8 Codex installs when Cursor or Codex is present for them to install into — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, in the visual language of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md`. All Writes are then AUQ-gated at **batch level** (one AUQ "Generate CLAUDE.md (X lines) + .geniro/ files + install statusline? Options: yes / edit / cancel", with "+ Cursor skills" / "+ Codex plugin" added before the "?" when §3.7 / §3.8 applies). On `cancel`, write nothing, record `phase: failed` with its `## Termination reason` per `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` §Termination case → state mapping, and stop. The statusline `settings.json` replacement (when an entry already points elsewhere) carries its own §3.6 confirm on top of this batch consent.

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

Check `$CLAUDE_USER_DIR/settings.json` for a `statusLine` entry. If absent, add one pointing to `<config-dir>/hooks/geniro-statusline.js`. If present and points to something else, `AskUserQuestion` (header: "Statusline") quoting the existing command: "Your `settings.json` statusLine is currently `<existing command>` — replace it with the Geniro statusline?" / options "Replace with Geniro statusline" / "Keep the existing one". This confirm is separate from the §3.3 batch AUQ — it overwrites a `~/.claude/settings.json` entry outside PROJECT_ROOT, which affects every project on the machine.

### 3.7 Install Geniro into the Cursor profile (conditional)

Fires only when this machine has a Cursor install (`$HOME/.cursor/` exists) AND the resolved plugin root carries `cursor/skills/` AND it was not dropped at the §3.3 batch approval. Skip silently when any of these fails.

A plugin install alone leaves `cursor-agent` sessions without Geniro skills, subagents, or hooks; `${CLAUDE_PLUGIN_ROOT}/cursor/README.md` §Install carries the evidence.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-cursor.sh"
```

The script is idempotent and touches only what it owns in those shared destinations, so a re-run costs nothing. It picks its own link target, preferring the marketplace checkout over a versioned install cache. Report the source line it prints, and pass on every `WARNING:` and `SKIP:` line it emits — a version-carrying link, a Cursor plugin install that will now double every skill, a `hooks.json` left untouched because `jq` is missing — rather than dropping them. Record the outcome for the §5.1 report.

### 3.8 Install Geniro into Codex (conditional)

Fires only when the `codex` CLI is on PATH AND this plugin is not already installed there AND it was not dropped at the §3.3 batch approval. Skip silently when Codex is absent or the user declined it.

Follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/codex-install.md` §Names, §Detect, §Install source, and §Install. When Detect finds the plugin already installed, record "already installed" and change nothing. Install from a local source, because this phase allows no network egress. Record every outcome, a missing source included, for the §5.1 report; a failed Codex install is reported and does not block the phase.

Transition to Phase 4.

